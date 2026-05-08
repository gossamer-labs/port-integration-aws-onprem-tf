# -----------------------------------------------------------------------------
# Port Ocean integration (ECS, ALB, API Gateway, EventBridge, etc.)
# VPC and subnet IDs are resolved here via data sources after network.tf creates
# module.vpc (managed) or from var.network_existing_* (BYO). See variables_integration.tf.
# Secrets: TF_VAR_port_client_id, TF_VAR_port_client_secret, TF_VAR_live_events_api_key.
# -----------------------------------------------------------------------------

# Managed: resolve VPC by Name tag after module.vpc. Depends_on ensures create order.
data "aws_vpc" "port_ocean_managed" {
  count = var.network_use_existing_vpc ? 0 : 1

  filter {
    name   = "tag:Name"
    values = [var.network_vpc_name]
  }

  depends_on = [module.vpc]
}

# BYO: read VPC directly by id.
data "aws_vpc" "port_ocean_existing" {
  count = var.network_use_existing_vpc ? 1 : 0
  id    = var.network_existing_vpc_id
}

# Managed: public subnets in the managed VPC (map-public-ip-on-launch matches default public subnet config).
data "aws_subnets" "port_ocean_public" {
  count = var.network_use_existing_vpc ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.port_ocean_managed[0].id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }

  depends_on = [module.vpc, data.aws_vpc.port_ocean_managed]
}

# BYO: read each supplied subnet and validate it belongs to the configured VPC.
data "aws_subnet" "port_ocean_byo" {
  for_each = var.network_use_existing_vpc ? toset(var.network_existing_subnet_ids) : toset([])

  id = each.value

  lifecycle {
    postcondition {
      condition     = self.vpc_id == data.aws_vpc.port_ocean_existing[0].id
      error_message = "Subnet ${self.id} is not in VPC ${data.aws_vpc.port_ocean_existing[0].id}; fix network_existing_subnet_ids."
    }
  }
}

locals {
  # If integration_identifier is null or blank, derive from port_org_slug.
  # Upstream Ocean ECS builds service_name = "port-ocean-aws-<identifier>" and IAM role
  # name = "ecs-task-execution-role-<service_name>". AWS IAM role names are max 64 chars, so
  # len(service_name) <= 40. With integration type "aws", "port-ocean-aws-" is 15 chars, so
  # keep integration.identifier (this value) <= 25 characters. Default pattern
  # "onprem-tf-<port_org_slug>" uses a 10-char prefix (vs 14 for the legacy "aws-onprem-tf-"),
  # so port_org_slug can be up to 15 chars under that cap (legacy prefix allowed up to 11).
  integration_identifier = (
    var.integration_identifier != null && trimspace(var.integration_identifier) != "" ? trimspace(var.integration_identifier) : "onprem-tf-${var.port_org_slug}"
  )

  integration_config = merge(
    var.live_events_api_key != null ? { live_events_api_key = var.live_events_api_key } : {},
    var.organization_role_arn != null ? { organization_role_arn = var.organization_role_arn } : {},
    var.account_read_role_name != null ? { account_read_role_name = var.account_read_role_name } : {},
    var.maximum_concurrent_accounts != null ? { maximum_concurrent_accounts = var.maximum_concurrent_accounts } : {},
  )
}

module "aws" {
  source  = "port-labs/integration-factory/ocean//examples/aws_container_app"
  version = "~> 0.0.24"

  port = {
    client_id     = var.port_client_id
    client_secret = var.port_client_secret
    base_url      = var.port_base_url
  }

  initialize_port_resources = var.initialize_port_resources
  scheduled_resync_interval = var.scheduled_resync_interval

  integration = {
    identifier = local.integration_identifier
    config     = local.integration_config
  }

  # Upstream module defaults integration_version to "latest"; keep explicit default for clarity.
  integration_version = coalesce(var.integration_version, "latest")

  event_listener = {
    type = var.event_listener_type
  }

  allow_incoming_requests = var.allow_incoming_requests
  create_default_sg       = var.create_default_sg
  assign_public_ip        = var.assign_public_ip

  # Managed: public subnets discovered by data source (sorted for stability).
  # BYO: validated subnets from data.aws_subnet.port_ocean_byo.
  vpc_id = (
    var.network_use_existing_vpc
    ? data.aws_vpc.port_ocean_existing[0].id
    : data.aws_vpc.port_ocean_managed[0].id
  )
  subnets = (
    var.network_use_existing_vpc
    ? [for sid in var.network_existing_subnet_ids : data.aws_subnet.port_ocean_byo[sid].id]
    : sort(data.aws_subnets.port_ocean_public[0].ids)
  )
  cluster_name = var.cluster_name

  depends_on = [terraform_data.integration_config_validation]
}

# Module blocks cannot use lifecycle.preconditions (reserved); validate cross-variable rules here.
resource "terraform_data" "integration_config_validation" {
  lifecycle {
    precondition {
      condition = !(
        var.allow_incoming_requests &&
        (var.organization_role_arn != null || var.account_read_role_name != null)
      )
      error_message = "Live events (allow_incoming_requests=true) are single-account only per Port docs. Unset organization_role_arn / account_read_role_name, or set allow_incoming_requests=false to run multi-account in polling mode."
    }

    precondition {
      condition     = (var.organization_role_arn == null) == (var.account_read_role_name == null)
      error_message = "For multi-account, set both organization_role_arn and account_read_role_name, or omit both for single-account."
    }

    precondition {
      condition = (
        var.maximum_concurrent_accounts == null ||
        (var.organization_role_arn != null && var.account_read_role_name != null)
      )
      error_message = "maximum_concurrent_accounts is only valid when organization_role_arn and account_read_role_name are both set."
    }
  }
}

output "integration_identifier" {
  description = "Resolved Port integration identifier (explicit var.integration_identifier or onprem-tf-<port_org_slug>)"
  value       = local.integration_identifier
}

output "network_vpc_id" {
  description = "VPC used by the Port Ocean ECS service"
  value = (
    var.network_use_existing_vpc
    ? data.aws_vpc.port_ocean_existing[0].id
    : data.aws_vpc.port_ocean_managed[0].id
  )
}

output "network_subnet_ids_for_ecs" {
  description = "Subnets passed to the Port Ocean module for ECS tasks"
  value = (
    var.network_use_existing_vpc
    ? [for sid in var.network_existing_subnet_ids : data.aws_subnet.port_ocean_byo[sid].id]
    : sort(data.aws_subnets.port_ocean_public[0].ids)
  )
}

# Port Ocean integration (ECS, ALB, API Gateway, EventBridge, etc.).
# Optional VPC and CloudTrail resources live in network.tf and cloudtrail.tf.
locals {
  # If integration_identifier is null or blank, derive from port_org_slug.
  integration_identifier = (
    var.integration_identifier != null && trimspace(var.integration_identifier) != "" ? trimspace(var.integration_identifier) : "aws-on-prem-tf-live-${var.port_org_slug}"
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
    config = var.live_events_api_key != null ? {
      live_events_api_key = var.live_events_api_key
    } : {}
  }

  # Upstream module defaults integration_version to "latest"; keep explicit default for clarity.
  integration_version = coalesce(var.integration_version, "latest")

  event_listener = {
    type = var.event_listener_type
  }

  allow_incoming_requests = var.allow_incoming_requests
  create_default_sg       = var.create_default_sg
  assign_public_ip        = var.assign_public_ip

  subnets      = local.subnets_for_port
  vpc_id       = local.vpc_id_for_port
  cluster_name = var.cluster_name
}

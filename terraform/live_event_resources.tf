# -----------------------------------------------------------------------------
# Live EventBridge rules beyond the Port Ocean module defaults
#
# This file is the place to add EventBridge rules that mirror the pattern used by the upstream
# aws_container_app example (EC2, S3, CloudFormation are created inside module.aws). Copy the
# module blocks below or add new ones for other AWS services.
#
# Port documentation:
#   - Add other services (custom rules): https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events#add-other-services
#   - Default Terraform module resource types: https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events#supported-resource-types
#   - AWS services that support live events: https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events#supported-aws-services
#
# Example below: EKS clusters (AWS::EKS::Cluster) and EKS node groups (AWS::EKS::Nodegroup).
# Adjust event names and JSONPath identifiers for your APIs; ensure Port mappings cover the
# resource_type values you emit.
#
# These rules (and Port’s default EC2/S3/CloudFormation rules) are fed by management API activity
# delivered to EventBridge as "AWS API Call via CloudTrail" — i.e. live events for these patterns
# are CloudTrail-backed. The account needs an active trail logging management events (see
# cloudtrail.tf / README) or EventBridge will not see the APIs.
#
# Webhook target ARN: looked up via data.aws_api_gateway_rest_api after module.aws creates the
# API (Terraform 1.14+ cannot read module.aws.module.api_gateway[0] from the root module).
# -----------------------------------------------------------------------------

locals {
  live_events_extension_enabled = (
    var.allow_incoming_requests &&
    var.live_events_api_key != null
  )
}

# Deferred read: runs after module.aws creates the REST API on first apply.
data "aws_api_gateway_rest_api" "port_ocean_live_events" {
  count = var.allow_incoming_requests ? 1 : 0

  name       = var.port_ocean_rest_api_name
  depends_on = [module.aws]
}

module "port_ocean_live_events_eks_cluster" {
  source  = "port-labs/integration-factory/ocean//modules/aws_helpers/event"
  version = "~> 0.0.24"

  count = local.live_events_extension_enabled ? 1 : 0

  depends_on = [module.aws]

  name        = "port-aws-ocean-sync-eks-cluster-trails"
  description = "Capture selected EKS cluster control plane API events (CloudTrail)"

  event_pattern = {
    source      = ["aws.eks"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["eks.amazonaws.com"]
      eventName = [
        "CreateCluster",
        "DeleteCluster",
        "UpdateClusterConfig",
        "UpdateClusterVersion",
      ]
    }
  }

  input_paths = {
    resource_type = "AWS::EKS::Cluster"
    account_id    = "$.detail.userIdentity.accountId"
    aws_region    = "$.detail.awsRegion"
    event_name    = "$.detail.eventName"
    # Matches the APIs above; TagResource and other calls may need different paths or rules.
    identifier = "$.detail.requestParameters.name"
  }

  api_key_param = var.live_events_api_key
  target_arn = format(
    "arn:aws:execute-api:%s:%s:%s/production/POST/integration/webhook",
    var.aws_region,
    data.aws_caller_identity.current.account_id,
    data.aws_api_gateway_rest_api.port_ocean_live_events[0].id
  )
}

module "port_ocean_live_events_eks_nodegroup" {
  source  = "port-labs/integration-factory/ocean//modules/aws_helpers/event"
  version = "~> 0.0.24"

  count = local.live_events_extension_enabled ? 1 : 0

  depends_on = [module.aws]

  name        = "port-aws-ocean-sync-eks-nodegroup-trails"
  description = "Capture selected EKS node group API events (CloudTrail)"

  event_pattern = {
    source      = ["aws.eks"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["eks.amazonaws.com"]
      eventName = [
        "CreateNodegroup",
        "DeleteNodegroup",
        "UpdateNodegroupConfig",
        "UpdateNodegroupVersion",
      ]
    }
  }

  input_paths = {
    resource_type = "AWS::EKS::Nodegroup"
    account_id    = "$.detail.userIdentity.accountId"
    aws_region    = "$.detail.awsRegion"
    event_name    = "$.detail.eventName"
    # Prefer the resource ARN when CloudTrail populates detail.resources; some APIs may omit it.
    identifier = "$.detail.resources[0].ARN"
  }

  api_key_param = var.live_events_api_key
  target_arn = format(
    "arn:aws:execute-api:%s:%s:%s/production/POST/integration/webhook",
    var.aws_region,
    data.aws_caller_identity.current.account_id,
    data.aws_api_gateway_rest_api.port_ocean_live_events[0].id
  )
}

output "live_events_webhook_url" {
  description = "HTTPS URL for EventBridge→integration webhook (POST /integration/webhook); null when allow_incoming_requests is false"
  value = var.allow_incoming_requests ? format(
    "https://%s.execute-api.%s.amazonaws.com/production/integration/webhook",
    data.aws_api_gateway_rest_api.port_ocean_live_events[0].id,
    var.aws_region
  ) : null
}

output "integration_identifier" {
  description = "Resolved Port integration identifier (explicit var.integration_identifier or aws-onprem-tf-<port_org_slug>)"
  value       = local.integration_identifier
}

# -----------------------------------------------------------------------------
# live_events_webhook_url — intentionally omitted (Terraform 1.14+)
# -----------------------------------------------------------------------------
# The Port aws_container_app example module declares no outputs. Terraform types
# module.aws using only those outputs, so the root module cannot reference nested
# modules such as module.aws.module.api_gateway[0].aws_api_gateway_rest_api...
# ("module.aws does not have an attribute named module").
#
# To expose this URL from Terraform, upstream would add an output on aws_container_app,
# or you maintain a fork. Otherwise get the REST API id from AWS Console (API Gateway) or
# terraform state show 'module.aws.module.api_gateway[0].aws_api_gateway_rest_api.rest_api'
# after apply, then: https://<id>.execute-api.<region>.amazonaws.com/production/integration/webhook
#
# output "live_events_webhook_url" {
#   description = "HTTPS URL for EventBridge→integration webhook (POST /integration/webhook)"
#   value = var.allow_incoming_requests ? format(
#     "https://%s.execute-api.%s.amazonaws.com/production/integration/webhook",
#     module.aws.module.api_gateway[0].aws_api_gateway_rest_api.rest_api.id,
#     var.aws_region
#   ) : null
# }

output "network_vpc_id" {
  description = "VPC used by the Port Ocean ECS service"
  value       = local.vpc_id_for_port
}

output "network_subnet_ids_for_ecs" {
  description = "Subnets passed to the Port Ocean module for ECS tasks"
  value       = local.subnets_for_port
}

output "network_create_mode" {
  description = "Whether this stack created the VPC or uses an existing one"
  value       = var.network_use_existing_vpc ? "existing_vpc" : "managed_vpc"
}

output "cloudtrail_name" {
  description = "CloudTrail trail name when live events + CloudTrail are enabled; null otherwise"
  value       = length(aws_cloudtrail.port_live_events) > 0 ? aws_cloudtrail.port_live_events[0].id : null
}

output "cloudtrail_arn" {
  description = "CloudTrail trail ARN when provisioned; null otherwise"
  value       = length(aws_cloudtrail.port_live_events) > 0 ? aws_cloudtrail.port_live_events[0].arn : null
}

output "cloudtrail_log_bucket_name" {
  description = "S3 bucket receiving CloudTrail logs when provisioned; null otherwise"
  value       = length(aws_cloudtrail.port_live_events) > 0 ? aws_cloudtrail.port_live_events[0].s3_bucket_name : null
}

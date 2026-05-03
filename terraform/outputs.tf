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

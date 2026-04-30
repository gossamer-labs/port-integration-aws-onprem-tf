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

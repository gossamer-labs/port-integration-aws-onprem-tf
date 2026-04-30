variable "aws_region" {
  description = "AWS region for all resources; must match the region of vpc_id and subnets"
  type        = string
}

variable "port_client_id" {
  description = "Port API client ID"
  type        = string
}

variable "port_client_secret" {
  description = "Port API client secret"
  type        = string
  sensitive   = true
}

variable "port_base_url" {
  description = "Port API base URL"
  type        = string
  default     = "https://api.port.io"
}

variable "initialize_port_resources" {
  description = "When true, the integration creates default blueprints and JQ mappings"
  type        = bool
  default     = true
}

variable "scheduled_resync_interval" {
  description = "Resync interval in minutes"
  type        = number
  default     = 1440
}

variable "integration_identifier" {
  description = "Stable identifier for this Port integration"
  type        = string
}

variable "live_events_api_key" {
  description = "Secret used to secure the live events endpoint"
  type        = string
  sensitive   = true
}

variable "event_listener_type" {
  description = "Event listener type (e.g. POLLING)"
  type        = string
  default     = "POLLING"
}

variable "allow_incoming_requests" {
  description = "Whether to allow incoming requests to the integration"
  type        = bool
  default     = true
}

variable "create_default_sg" {
  description = "Whether to create the default security group"
  type        = bool
  default     = false
}

variable "subnets" {
  description = "Subnets for the load balancer"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for the load balancer"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

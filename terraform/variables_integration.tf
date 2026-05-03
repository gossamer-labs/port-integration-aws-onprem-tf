# -----------------------------------------------------------------------------
# Port Ocean (`module.aws` — port-labs/integration-factory aws_container_app)
# Secrets: TF_VAR_port_client_id, TF_VAR_port_client_secret, TF_VAR_live_events_api_key (see README).
# -----------------------------------------------------------------------------

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
  description = "Port API base URL (US: https://api.us.port.io, EU: https://api.port.io)"
  type        = string
  default     = "https://api.us.port.io"
}

variable "initialize_port_resources" {
  description = "When true, the integration creates default blueprints and JQ mappings in Port"
  type        = bool
  default     = true
}

variable "scheduled_resync_interval" {
  description = "Resync interval in minutes"
  type        = number
  default     = 1440
}

variable "port_org_slug" {
  description = "Short slug for your org, used in the default Port integration id when integration_identifier is unset: aws-on-prem-tf-live-<port_org_slug>."
  type        = string
  default     = "gossamer-labs"
}

variable "integration_identifier" {
  description = "Stable identifier for this integration in Port (set before first apply; hard to change later). If null, defaults to aws-on-prem-tf-live-<port_org_slug>."
  type        = string
  default     = null
  nullable    = true
}

variable "live_events_api_key" {
  description = "Secret you define for EventBridge→integration webhook validation (not an AWS key). Pass via TF_VAR_live_events_api_key."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "event_listener_type" {
  description = "Ocean event listener type"
  type        = string
  default     = "POLLING"
}

variable "allow_incoming_requests" {
  description = "If true, creates ALB + API Gateway + EventBridge for live events (single-account installations per Port)."
  type        = bool
  default     = false
}

variable "create_default_sg" {
  description = "Whether the upstream module creates a default security group for the ECS service"
  type        = bool
  default     = true
}

variable "assign_public_ip" {
  description = "Assign public IP to ECS tasks (typical with public subnets and no NAT)"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "ECS cluster name for the Port Ocean service"
  type        = string
}

variable "integration_version" {
  description = "Port Ocean AWS integration image tag (pin for reproducibility; empty lets upstream default apply)"
  type        = string
  default     = null
  nullable    = true
}

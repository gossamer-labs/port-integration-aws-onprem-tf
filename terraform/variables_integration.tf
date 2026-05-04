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
  description = <<-EOT
    Short org slug. When integration_identifier is null, the Port integration id defaults to
    onprem-tf-<port_org_slug>. The upstream module names IAM roles using
    ecs-task-execution-role-port-ocean-aws-<that_identifier>; AWS IAM role names are capped at
    64 characters, which implies len(service_name) <= 40 and, for type aws,
    len(identifier) <= 25. Prefer a short slug so the default id stays within that budget.
  EOT
  type        = string
  default     = "gossint"
}

variable "integration_identifier" {
  description = <<-EOT
    Stable identifier for this integration in Port (set before first apply; hard to change later).
    If null, defaults to onprem-tf-<port_org_slug>. Upstream builds ECS IAM role names from
    port-ocean-aws-<identifier>; the longest prefix is ecs-task-execution-role- (24 chars), so
    the combined role name must stay <= 64 (service_name <= 40; for type aws, identifier <= 25).
    Shorten this or port_org_slug if apply fails on IAM name length. cluster_name does not feed
    into that IAM role name pattern.
  EOT
  type        = string
  default     = null
  nullable    = true
}

variable "live_events_api_key" {
  description = <<-EOT
    Secret you define for EventBridge→integration webhook validation (not an AWS key).
    Pass via TF_VAR_live_events_api_key.
  EOT
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
  description = <<-EOT
    If true, creates ALB + API Gateway + EventBridge for live events (single-account installations
    per Port).
  EOT
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
  description = <<-EOT
    ECS cluster name for the Port Ocean service (AWS ECS cluster resource). Not concatenated into
    the Ocean module ecs-task-execution-role IAM name—those names come from integration.identifier;
    keep cluster_name readable for operations.
  EOT
  type        = string
}

variable "integration_version" {
  description = <<-EOT
    Port Ocean AWS integration image tag (pin for reproducibility; empty lets upstream default
    apply)
  EOT
  type        = string
  default     = null
  nullable    = true
}

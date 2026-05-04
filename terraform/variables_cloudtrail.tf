# -----------------------------------------------------------------------------
# CloudTrail — enables EventBridge delivery of management API events for Port live
# events (EC2/S3/CloudFormation default rules). Created only when live events are on.
# See README "Live events prerequisites".
# -----------------------------------------------------------------------------

variable "cloudtrail_enabled" {
  description = "When true (and allow_incoming_requests), create CloudTrail with management events and S3 logging (required for EventBridge delivery of API-call events)."
  type        = bool
  default     = true
}

variable "cloudtrail_name_prefix" {
  description = "DNS-compliant prefix for the CloudTrail trail and managed S3 log bucket. Trail name: \"{prefix}-live-events\". Managed bucket: \"{prefix}-cloudtrail-logs-{aws_account_id}\" (suffix is the deployment AWS account ID for global S3 uniqueness)."
  type        = string
  default     = "port-exporter"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,34}[a-z0-9]$", var.cloudtrail_name_prefix))
    error_message = "cloudtrail_name_prefix must be 3-36 lowercase alphanumeric characters or hyphens; cannot start or end with a hyphen."
  }
}

variable "cloudtrail_log_bucket_object_expiration_days" {
  description = "Expire current-version CloudTrail log objects in the managed bucket after this many days (S3 lifecycle)."
  type        = number
  default     = 365
}

variable "cloudtrail_log_bucket_noncurrent_version_expiration_days" {
  description = "Expire non-current object versions in the managed CloudTrail log bucket after this many days."
  type        = number
  default     = 30
}

variable "cloudtrail_existing_log_bucket_name" {
  description = "If set, CloudTrail writes logs to this existing bucket instead of creating one. Terraform attaches the CloudTrail bucket policy; your credentials must allow PutBucketPolicy on that bucket."
  type        = string
  default     = null
  nullable    = true
}

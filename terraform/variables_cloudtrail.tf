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
  description = "Prefix for the trail name and for the managed S3 log bucket name (DNS-compliant segments)."
  type        = string
  default     = "port-ocean"
}

variable "cloudtrail_existing_log_bucket_name" {
  description = "If set, CloudTrail writes logs to this existing bucket instead of creating one. Terraform attaches the CloudTrail bucket policy; your credentials must allow PutBucketPolicy on that bucket."
  type        = string
  default     = null
  nullable    = true
}

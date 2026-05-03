# CloudTrail + S3 so management API events reach EventBridge for Port live events.
# An active trail logging management events publishes `AWS API Call via CloudTrail` to the
# default event bus (see AWS EventBridge docs). Event history alone does not replace a trail.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  cloudtrail_should_create         = var.allow_incoming_requests && var.cloudtrail_enabled
  cloudtrail_managed_bucket        = local.cloudtrail_should_create && var.cloudtrail_existing_log_bucket_name == null
  cloudtrail_trail_name            = "${var.cloudtrail_name_prefix}-port-live-events"
  cloudtrail_new_bucket_name       = "${var.cloudtrail_name_prefix}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  cloudtrail_log_bucket_for_policy = local.cloudtrail_managed_bucket ? aws_s3_bucket.cloudtrail_logs[0].id : var.cloudtrail_existing_log_bucket_name
}

# Note: check blocks surface validation issues but do not halt apply by default (Terraform 1.5+).
check "cloudtrail_byo_bucket_name" {
  assert {
    condition = (
      !local.cloudtrail_should_create ||
      local.cloudtrail_managed_bucket ||
      try(trimspace(var.cloudtrail_existing_log_bucket_name), "") != ""
    )
    error_message = "Set cloudtrail_existing_log_bucket_name to your bucket name when not using the Terraform-managed log bucket."
  }
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = local.cloudtrail_managed_bucket ? 1 : 0
  bucket = local.cloudtrail_new_bucket_name
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail_logs" {
  count = local.cloudtrail_managed_bucket ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count = local.cloudtrail_managed_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.cloudtrail_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket_ownership_controls.cloudtrail_logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count = local.cloudtrail_managed_bucket ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count = local.cloudtrail_managed_bucket ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  count = local.cloudtrail_managed_bucket ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    id     = "expire-cloudtrail-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.cloudtrail_log_bucket_object_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.cloudtrail_log_bucket_noncurrent_version_expiration_days
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.cloudtrail_logs
  ]
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  count = local.cloudtrail_should_create ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.cloudtrail_log_bucket_for_policy}"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_trail_name}"
      ]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.cloudtrail_log_bucket_for_policy}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_trail_name}"
      ]
    }
  }

  # Deny any API call not over TLS (defense in depth; aligns with AWS FSBP / CIS-style checks).
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${local.cloudtrail_log_bucket_for_policy}",
      "arn:${data.aws_partition.current.partition}:s3:::${local.cloudtrail_log_bucket_for_policy}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count = local.cloudtrail_should_create ? 1 : 0

  bucket = local.cloudtrail_managed_bucket ? aws_s3_bucket.cloudtrail_logs[0].id : var.cloudtrail_existing_log_bucket_name
  policy = data.aws_iam_policy_document.cloudtrail_logs[0].json
}

resource "aws_cloudtrail" "port_live_events" {
  count = local.cloudtrail_should_create ? 1 : 0

  name                          = local.cloudtrail_trail_name
  s3_bucket_name                = local.cloudtrail_managed_bucket ? aws_s3_bucket.cloudtrail_logs[0].id : var.cloudtrail_existing_log_bucket_name
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

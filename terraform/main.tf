# Shared account-level data — referenced by cloudtrail.tf and integration.tf.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

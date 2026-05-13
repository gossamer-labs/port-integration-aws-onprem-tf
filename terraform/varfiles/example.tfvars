# -----------------------------------------------------------------------------
# Copy to varfiles/<your-install>.tfvars and pass:
#   terraform plan -var-file=varfiles/<your-install>.tfvars
#
# Required secrets (never commit): set via environment — Terraform picks up TF_VAR_*:
#   export TF_VAR_port_client_id="<from Port>"
#   export TF_VAR_port_client_secret="<from Port>"
#   export TF_VAR_live_events_api_key="<your webhook secret>"   # required when allow_incoming_requests = true
#
# Optional private overlay (gitignored): varfiles/<name>.local.tfvars
#   terraform plan -var-file=varfiles/mystack.tfvars -var-file=varfiles/mystack.local.tfvars
#
# This file lists every root-module variable defined in terraform/variables_*.tf.
# Uncomment or override blocks that match your install; commented lines show shape only.
# -----------------------------------------------------------------------------

# ============================================================
# AWS provider & tagging
# ============================================================
aws_region = "<aws-region>"

# Applied to every AWS resource via the provider default_tags block (merge/replace defaults as needed).
# default_resource_tags = {
#   Environment = "<your-environment-name>"
#   ManagedBy   = "terraform"
#   Project     = "port-ocean-aws"
#   Repository  = "<your-repo-or-project-id>"
# }

# ============================================================
# Port API & integration identity (integration.tf / module.aws)
# ============================================================
# port_client_id     — set via TF_VAR_port_client_id (no default in Terraform).
# port_client_secret — set via TF_VAR_port_client_secret (sensitive).

port_base_url = "https://api.us.port.io" # EU: https://api.port.io

# Short slug: when integration_identifier is null, Port integration id defaults to onprem-tf-<port_org_slug>.
# IAM role names upstream include this — keep short (identifier budget ~25 chars for type aws; see variables_integration.tf).
port_org_slug = "<short slug; keep slug short so IAM role names stay <= 64 chars>"

# Optional: override the Port integration id (stable — set before first apply). If null, defaults to onprem-tf-<port_org_slug>.
# integration_identifier = "onprem-tf-myorg"

initialize_port_resources = true
scheduled_resync_interval = 1440

# Ocean scheduled sync listener (not a substitute for live events). Typically POLLING; see Port Ocean / installation docs for options.
event_listener_type = "POLLING"

# Pin the Port Ocean AWS integration container image tag for reproducibility; null uses the upstream module default.
# integration_version = "1.2.3"

cluster_name = "port-ocean-aws-exporter"

# Upstream “default security group” for the ECS service.
create_default_sg = true

# true = tasks get a public IP (usual with public subnets and no NAT). Use false with private subnets + NAT.
assign_public_ip = true

# ============================================================
# Network — pick ONE path: new VPC (default) OR existing VPC
# ============================================================

# --- Path 1: create a VPC --- set network_use_existing_vpc = false (true = Path 2 / existing VPC).
network_use_existing_vpc     = false
network_vpc_name             = "port-ocean"
network_vpc_cidr             = "10.48.0.0/16"
network_public_subnet_cidrs  = ["10.48.0.0/24", "10.48.1.0/24"]
network_private_subnet_cidrs = [] # non-empty requires network_enable_nat_gateway = true

network_enable_nat_gateway   = false
network_single_nat_gateway   = true # when NAT is on: one NAT for all AZs (cheaper) vs one per AZ

# Extra tags merged into the VPC module (optional).
# network_tags = {
#   Environment = "production"
# }
# network_public_subnet_tags = {
#   Tier = "public"
# }

# --- Path 2: existing VPC ---
# Set network_use_existing_vpc = true above (instead of false). Path 1 name/CIDR lists are then unused.
# Requires at least two subnet IDs in different AZs. Match assign_public_ip to subnet type (public vs private + NAT).
# network_existing_vpc_id     = "vpc-0123456789abcdef0"
# network_existing_subnet_ids = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]

# ============================================================
# Mode A: live events, SINGLE account (mutually exclusive with Mode B)
#
# Per Port: "Live events are currently only available for Single account
# installations (not multi-account)."
# https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events
#
# Provisions ALB + API Gateway + EventBridge; CloudTrail recommended for API events.
# Do not set organization_role_arn / account_read_role_name (Terraform will error).
# ============================================================
allow_incoming_requests = true
cloudtrail_enabled      = true

# Webhook validation secret for EventBridge → integration (not an AWS key): TF_VAR_live_events_api_key.
# live_events_api_key — unset here; use environment variable.

# Name of the REST API created by the Ocean module (default matches upstream). Override only if you fork and rename.
# port_ocean_rest_api_name = "port-ocean-aws-exporter"

# CloudTrail (created only when allow_incoming_requests && cloudtrail_enabled; see cloudtrail.tf and README “Live events prerequisites”).
# cloudtrail_name_prefix must be 3–36 chars, lowercase [a-z0-9-], no leading/trailing hyphen.
# cloudtrail_name_prefix = "port-exporter"

# Lifecycle on the managed log bucket (ignored if you bring your own bucket below).
# cloudtrail_log_bucket_object_expiration_days            = 365
# cloudtrail_log_bucket_noncurrent_version_expiration_days = 30

# Optional: write CloudTrail to an existing bucket (Terraform attaches bucket policy; your creds need PutBucketPolicy).
# cloudtrail_existing_log_bucket_name = "my-org-cloudtrail-logs"

# ============================================================
# Mode B: polling, MULTI account (mutually exclusive with Mode A)
#
# Live events are NOT supported in multi-account per Port docs. Set org/member roles first:
# https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/multi_account
#
# Uncomment this block and comment out / invert Mode A settings above.
# Set organization_role_arn and account_read_role_name together (both required for multi-account).
# ============================================================
# allow_incoming_requests       = false
# cloudtrail_enabled            = false
# organization_role_arn         = "arn:aws:iam::<root-account-id>:role/<OrganizationalOceanRole>"
# account_read_role_name        = "ReadOnlyPermissionsOceanRole"
# maximum_concurrent_accounts   = 50 # optional; only valid when both role vars above are set; omit for null/default

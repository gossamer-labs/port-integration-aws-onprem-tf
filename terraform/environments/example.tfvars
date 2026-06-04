# -----------------------------------------------------------------------------
# Copy this file once per GitHub Actions environment you define, e.g.:
#   cp environments/example.tfvars environments/lab.tfvars
#   cp environments/example.tfvars environments/prod.tfvars
#   cp environments/example.tfvars environments/<your-env>.tfvars
#
# The following must match the environment name exactly:
#   - GitHub Actions environment (Settings → Environments → <your-env>)
#   - CI ENVIRONMENT value (lab / prod / <your-env>)
#   - Terraform Cloud workspace suffix: $TFC_WORKSPACE_SLUG-<your-env>
#
# Secrets and variables are NOT committed in this template — configure per environment:
#
# GitHub Actions (Settings → Environments → <your-env>):
#   Secrets:  TF_API_TOKEN, PORT_CLIENT_SECRET, PORT_LIVE_EVENTS_API_KEY
#             (+ AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY if USE_AWS_STATIC_CREDENTIALS=true in workflow)
#   Variables: PORT_CLIENT_ID, TFC_ORGANIZATION, TFC_WORKSPACE_SLUG, TFC_WORKSPACE_TAGS,
#              AWS_REGION, AWS_ACCOUNT_ID, AWS_ROLE_NAME
#
# Local runs — export before terraform init / plan / apply:
#   # Port (Terraform — no defaults; do not commit secrets)
#   export TF_VAR_port_client_id="..."
#   export TF_VAR_port_client_secret="..."
#   export TF_VAR_live_events_api_key="..."   # required when allow_incoming_requests = true
#
#   # Terraform Cloud (when using cloud {} in terraform.tf)
#   export TF_CLOUD_ORGANIZATION="..."
#   export TF_WORKSPACE="<TFC_WORKSPACE_SLUG>-<your-env>"   # e.g. port-integration-aws-onprem-tf-lab
#   export TF_TOKEN_app_terraform_io="..."   # or: terraform login
#
#   # AWS (provider uses aws_region from this varfile; align region with your credentials)
#   export AWS_PROFILE="..."                 # or standard AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
#   export AWS_DEFAULT_REGION="<same-as-aws_region-below>"
#
# Optional private overlay (gitignored): environments/<name>.local.tfvars
#   terraform plan -var-file=environments/lab.tfvars \
#     -var-file=environments/lab.local.tfvars
#
# This file lists every root-module variable defined in terraform/variables_*.tf.
# Uncomment or override blocks that match your install; commented lines show shape only.
# -----------------------------------------------------------------------------
#
# Resource naming — must be unique per environment
#
# If lab and prod (or any two environments) share the same AWS account
# and region, set DIFFERENT values for every variable below. Otherwise apply will fail
# on duplicate names (ECS cluster, IAM roles, CloudTrail, S3 bucket, Port integration ID).
#
# | Variable                 | AWS / Port resource affected                            |
# |--------------------------|---------------------------------------------------------|
# | port_org_slug            | Port integration ID, IAM roles, ECS service name        |
# | cluster_name             | ECS cluster                                             |
# | network_vpc_name         | VPC Name tag (used by data.aws_vpc lookup)              |
# | network_vpc_cidr       | VPC CIDR (use non-overlapping ranges per env)             |
# | cloudtrail_name_prefix   | CloudTrail trail + managed S3 log bucket name           |
#
# Example suffix pattern: lab → *-int / goss-int; prod → *-prd / goss-prd.
#
# Separate AWS accounts per environment (recommended for prod): only port_org_slug
# (Port-side) and cloudtrail_name_prefix (S3 bucket names are globally unique) must differ.
# ECS clusters, IAM roles, VPCs, and CloudTrail trails are already scoped per account.
#
# Changing port_org_slug on an existing Port registration creates a new integration;
# use integration_identifier explicitly to keep an existing Port integration ID.
# -----------------------------------------------------------------------------

# ============================================================
# AWS provider & tagging
# ============================================================
aws_region = "<aws-region>"

# Applied to every AWS resource via the provider default_tags block (merge/replace defaults as needed).
# default_resource_tags = {
#   Environment = "<your-env>"
#   ManagedBy   = "terraform"
#   Project     = "port-ocean-aws"
#   Repository  = "<your-repo>"
# }

# ============================================================
# Port integration — pick ONE path: live events (single account) OR polling (multi-account)
# ============================================================
#
# Path 1 and Path 2 are mutually exclusive. Terraform validates at plan time
# (see integration.tf integration_config_validation).
#
# Path 1 — live events, SINGLE account (default in this template):
#   allow_incoming_requests = true; CloudTrail recommended. Requires TF_VAR_live_events_api_key.
#   Provisions ALB + API Gateway + EventBridge. Do not set organization_role_arn / account_read_role_name.
#   https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events
#
# Path 2 — polling, MULTI account:
#   allow_incoming_requests = false; set organization_role_arn and account_read_role_name together.
#   Live events are not supported. Set org/member roles per Port before apply:
#   https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/multi_account
#
# --- Common (both paths) ---
port_base_url = "https://api.us.port.io" # EU: https://api.port.io

# Pin the Port Ocean AWS integration container image tag for reproducibility; null uses the upstream module default.
# integration_version = "1.2.3"

# Short slug: when integration_identifier is null, Port integration id defaults to onprem-tf-<port_org_slug>.
# IAM role names upstream include this — keep short (identifier budget ~25 chars for type aws; see variables_integration.tf).
port_org_slug = "<port-org-slug>" # Keep slug short so IAM role names stay <= 64 chars

# Optional: override the Port integration id (stable — set before first apply). If null, defaults to onprem-tf-<port_org_slug>.
# integration_identifier = "onprem-tf-myorg"

# port_client_id - unset here; use PORT_CLIENT_ID (CI) or TF_VAR_port_client_id (local).
# port_client_secret - unset here; use PORT_CLIENT_SECRET (CI) or TF_VAR_port_client_secret (local).

# Scheduled Port sync listener — not a substitute for live events (Path 1). Typically POLLING; see Port Ocean docs.
event_listener_type       = "POLLING"
scheduled_resync_interval = 1440

cluster_name = "port-ocean-aws-exporter"

# Upstream “default security group” for the ECS service.
create_default_sg = true

# true = tasks get a public IP (usual with public subnets and no NAT). Use false with private subnets + NAT.
assign_public_ip = true

# When true, Ocean seeds default Port blueprints and JQ mappings on first start; catalog objects may persist after terraform destroy.
initialize_port_resources = true

# --- Path 1: live events, SINGLE account --- allow_incoming_requests = true (false = Path 2).
allow_incoming_requests = true
cloudtrail_enabled      = true

# live_events_api_key — unset here; use PORT_LIVE_EVENTS_API_KEY (CI) or TF_VAR_live_events_api_key (local).

# CloudTrail (created only when allow_incoming_requests && cloudtrail_enabled; see cloudtrail.tf and README “Live events prerequisites”).
# cloudtrail_name_prefix must be 3–36 chars, lowercase [a-z0-9-], no leading/trailing hyphen.
# cloudtrail_name_prefix = "port-exporter"

# Lifecycle on the managed log bucket (ignored if you bring your own bucket below).
# cloudtrail_log_bucket_object_expiration_days            = 365
# cloudtrail_log_bucket_noncurrent_version_expiration_days = 30

# Optional: write CloudTrail to an existing bucket (Terraform attaches bucket policy; your creds need PutBucketPolicy).
# cloudtrail_existing_log_bucket_name = "my-org-cloudtrail-logs"

# --- Path 2: polling, MULTI account ---
# Uncomment this block and comment out 1 (Path 1) settings above.
# Set organization_role_arn and account_read_role_name together (both required for multi-account).
# allow_incoming_requests       = false
# cloudtrail_enabled            = false
# organization_role_arn         = "arn:aws:iam::<root-account-id>:role/<OrganizationalOceanRole>"
# account_read_role_name        = "ReadOnlyPermissionsOceanRole"
# maximum_concurrent_accounts   = 50 # optional; only valid when both role vars above are set; omit for null/default

# ============================================================
# Network — pick ONE path: new VPC (default) OR existing VPC
# ============================================================

# --- Path 1: create a VPC --- set network_use_existing_vpc = false (true = Path 2 / existing VPC).
network_use_existing_vpc     = false
network_vpc_name             = "port-ocean"
network_vpc_cidr             = "10.48.0.0/16"
network_public_subnet_cidrs  = ["10.48.0.0/24", "10.48.1.0/24"]
network_private_subnet_cidrs = [] # non-empty requires network_enable_nat_gateway = true

network_enable_nat_gateway = false
network_single_nat_gateway = true # when NAT is on: one NAT for all AZs (cheaper) vs one per AZ

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

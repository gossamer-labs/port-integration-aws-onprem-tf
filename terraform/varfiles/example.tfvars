# -----------------------------------------------------------------------------
# Copy to varfiles/<your-install>.tfvars and pass:
#   terraform plan -var-file=varfiles/<your-install>.tfvars
#
# Secrets (never commit): TF_VAR_port_client_id, TF_VAR_port_client_secret,
#   TF_VAR_live_events_api_key (required when allow_incoming_requests = true)
#
# Optional private overlay (gitignored): varfiles/<name>.local.tfvars
#   terraform plan -var-file=varfiles/acme.tfvars -var-file=varfiles/acme.local.tfvars
# -----------------------------------------------------------------------------

# ============================================================
# Common (all installs)
# ============================================================
aws_region    = "<aws-region, e.g. us-east-1>"
port_base_url = "https://api.us.port.io" # or https://api.port.io for EU

# Short slug: default integration id is onprem-tf-<port_org_slug> (<= 25 chars total id; see README IAM budget).
port_org_slug = "<short slug; keep slug short so IAM role names stay <= 64 chars>"

cluster_name = "port-ocean-aws-exporter"

# Tags on every AWS resource (override as needed).
# default_resource_tags = {
#   Environment = "<your-environment-name>"
#   ManagedBy   = "terraform"
#   Project     = "port-ocean-aws"
#   Repository  = "<your-repo-or-project-id>"
# }

initialize_port_resources = true
scheduled_resync_interval = 1440
event_listener_type       = "POLLING"

# Network bootstrap (greenfield). For existing VPC: network_use_existing_vpc = true plus *_existing_* vars.
network_use_existing_vpc     = false
network_vpc_name             = "port-ocean"
network_vpc_cidr             = "10.48.0.0/16"
network_public_subnet_cidrs  = ["10.48.0.0/24", "10.48.1.0/24"]
network_private_subnet_cidrs = []
network_enable_nat_gateway   = false
create_default_sg            = true
assign_public_ip             = true

# ============================================================
# Mode A: live events, SINGLE account (mutually exclusive with Mode B)
#
# Per Port: "Live events are currently only available for Single account
# installations (not multi-account)."
# https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events
#
# Provisions ALB + API Gateway + EventBridge; CloudTrail recommended for API events.
# ============================================================
allow_incoming_requests = true
cloudtrail_enabled      = true

# EKS extension rules (live_event_resources.tf) use a data lookup for the API Gateway webhook
# target; set TF_VAR_live_events_api_key. Optional: port_ocean_rest_api_name if you fork upstream.

# Do not set organization_role_arn / account_read_role_name in Mode A (Terraform will error).

# ============================================================
# Mode B: polling, MULTI account (mutually exclusive with Mode A)
#
# Live events are NOT supported in multi-account per Port docs. Set org/member roles first:
# https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/multi_account
#
# Uncomment and switch off live-events path; set both role knobs together.
# ============================================================
# allow_incoming_requests       = false
# cloudtrail_enabled            = false
# organization_role_arn         = "arn:aws:iam::<root-account-id>:role/<OrganizationalOceanRole>"
# account_read_role_name        = "ReadOnlyPermissionsOceanRole"
# maximum_concurrent_accounts   = 50

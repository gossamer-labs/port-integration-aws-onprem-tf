# -----------------------------------------------------------------------------
# Network — see variables_network.tf and network.tf
# -----------------------------------------------------------------------------

aws_region = "us-east-2"

network_use_existing_vpc = false

network_vpc_name = "port-ocean"
network_vpc_cidr = "10.48.0.0/16"

# Two public subnets / two AZs; no NAT (cheapest). ECS uses public IPs (assign_public_ip).
network_public_subnet_cidrs  = ["10.48.0.0/24", "10.48.1.0/24"]
network_private_subnet_cidrs = []
network_enable_nat_gateway   = false

# -----------------------------------------------------------------------------
# Port Ocean module — see variables_integration.tf and main.tf
# -----------------------------------------------------------------------------

port_base_url = "https://api.us.port.io"

# Integration identifier defaults to aws-on-prem-tf-live-<port_org_slug> when unset (see variables_integration.tf).
port_org_slug = "gossamer-labs"

initialize_port_resources = true
scheduled_resync_interval = 1440

# Per Port docs: POLLING governs scheduled Port sync; AWS live events use EventBridge → API Gateway separately.
event_listener_type = "POLLING"

# Live events (ALB + API Gateway + EventBridge). Port documents this as single-account only.
allow_incoming_requests = true

create_default_sg = true
assign_public_ip  = true

cluster_name = "port-ocean-aws-exporter"
# integration_version: omit for "latest", or set a concrete image tag from ghcr.io/port-labs for reproducible deploys.

# Provide live_events_api_key via TF_VAR_live_events_api_key (e.g. openssl rand -hex 32). See README.

# CloudTrail — see variables_cloudtrail.tf and cloudtrail.tf (created when allow_incoming_requests and cloudtrail_enabled are true).
cloudtrail_enabled = true
# cloudtrail_existing_log_bucket_name = null   # or set to an existing bucket name

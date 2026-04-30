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

integration_identifier = "aws-tf-live-gossamer-int"

initialize_port_resources = true
scheduled_resync_interval = 1440

event_listener_type = "POLLING"

# Phase 1: POLLING sync only. Phase 2: set true + set live_events_api_key (TF_VAR).
allow_incoming_requests = false

create_default_sg = true
assign_public_ip  = true

cluster_name = "port-ocean-aws-exporter"
# integration_version: omit for "latest", or set a concrete image tag from ghcr.io/port-labs for reproducible deploys.

# Secrets (Port client id/secret, optional live events key) via TF_VAR_* — see README.

# -----------------------------------------------------------------------------
# Integration environment
# Pass: terraform plan -var-file=environments/integration.tfvars
# CI: ENVIRONMENT=integration (PRs / non-main workflow_dispatch)
# Secrets: GitHub environment `integration` + TF_VAR_* for local runs
# -----------------------------------------------------------------------------

default_resource_tags = {
  Environment = "integration"
  ManagedBy   = "terraform"
  Project     = "port-ocean-aws"
  Repository  = "port-integration-aws-onprem-tf"
}

aws_region = "us-east-2"

network_use_existing_vpc = false

network_vpc_name = "port-ocean"
network_vpc_cidr = "10.48.0.0/16"

network_public_subnet_cidrs  = ["10.48.0.0/24", "10.48.1.0/24"]
network_private_subnet_cidrs = []
network_enable_nat_gateway   = false

port_base_url = "https://api.us.port.io"

port_org_slug = "gossint"

initialize_port_resources = true
scheduled_resync_interval = 1440

event_listener_type = "POLLING"

allow_incoming_requests = true

create_default_sg = true
assign_public_ip  = true

cluster_name = "port-exporter"

cloudtrail_enabled = true

# -----------------------------------------------------------------------------
# Production environment
# Pass: terraform plan -var-file=environments/production.tfvars
# CI: ENVIRONMENT=production (push to default branch; workflow_dispatch when selected)
# Secrets: GitHub environment `production` + TF_VAR_* for local runs
# -----------------------------------------------------------------------------

default_resource_tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Project     = "port-ocean-aws"
  Repository  = "port-integration-aws-onprem-tf"
}

aws_region = "us-east-2"

network_use_existing_vpc = false

network_vpc_name = "port-ocean-prod"
network_vpc_cidr = "10.49.0.0/16"

network_public_subnet_cidrs  = ["10.49.0.0/24", "10.49.1.0/24"]
network_private_subnet_cidrs = []
network_enable_nat_gateway   = false

port_base_url = "https://api.us.port.io"

# Drives Port integration ID (onprem-tf-<slug>), IAM roles, and ECS service name.
port_org_slug = "goss-prod"

initialize_port_resources = true
scheduled_resync_interval = 1440

event_listener_type = "POLLING"

allow_incoming_requests = true

create_default_sg = true
assign_public_ip  = true

cluster_name = "port-exporter-prod"

cloudtrail_enabled     = true
cloudtrail_name_prefix = "port-exporter-prod"

# Non-secret settings — safe to commit. Update region, subnet, and VPC values for your account.
# Secrets (Port client id/secret, live events key) are set via TF_VAR_* (see repository README).

aws_region                  = "us-east-1"
port_base_url               = "https://api.port.io"
initialize_port_resources   = true
scheduled_resync_interval   = 1440
integration_identifier      = "my-aws-integration"
event_listener_type         = "POLLING"
allow_incoming_requests     = true
create_default_sg           = false
subnets                     = ["subnet-xxxxxxxxxxxx1", "subnet-xxxxxxxxxxxx2", "subnet-xxxxxxxxxxxx3"]
vpc_id                      = "vpc-xxxxxxxx"
cluster_name                = "port-ocean-aws-exporter"

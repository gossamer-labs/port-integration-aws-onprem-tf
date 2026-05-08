# -----------------------------------------------------------------------------
# Network: optional VPC bootstrap (greenfield).
# Vars drive VPC creation only; integration.tf resolves VPC/subnet IDs for module.aws.
# Bring your own VPC: network_use_existing_vpc and existing_* in variables_network.tf (README).
# -----------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # VPC module pairs subnets with AZs by index; support asymmetric counts safely.
  network_subnet_tier_count = max(
    length(var.network_public_subnet_cidrs),
    length(var.network_private_subnet_cidrs)
  )

  network_azs = slice(
    data.aws_availability_zones.available.names,
    0,
    local.network_subnet_tier_count
  )
}

module "vpc" {
  # Pin to VPC module 5.x so hashicorp/aws stays on ~> 5.x (required by Port Ocean submodule).
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  count = var.network_use_existing_vpc ? 0 : 1

  name = var.network_vpc_name
  cidr = var.network_vpc_cidr
  azs  = local.network_azs

  public_subnets  = var.network_public_subnet_cidrs
  private_subnets = var.network_private_subnet_cidrs

  enable_nat_gateway   = var.network_enable_nat_gateway
  single_nat_gateway   = var.network_single_nat_gateway
  enable_dns_hostnames = true

  # ManagedBy / Project / Environment come from provider default_tags.
  tags = merge(
    var.network_tags,
    {
      Name = var.network_vpc_name
    }
  )

  public_subnet_tags  = var.network_public_subnet_tags
  private_subnet_tags = {}
}

output "network_create_mode" {
  description = "Whether this stack created the VPC or uses an existing one"
  value       = var.network_use_existing_vpc ? "existing_vpc" : "managed_vpc"
}

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

locals {
  vpc_id_for_port = var.network_use_existing_vpc ? var.network_existing_vpc_id : module.vpc[0].vpc_id

  # ECS tasks run in public subnets when using the bundled VPC (no NAT). For existing VPC, supply subnets you choose.
  subnets_for_port = var.network_use_existing_vpc ? var.network_existing_subnet_ids : module.vpc[0].public_subnets
}

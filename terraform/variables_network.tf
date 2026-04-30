# -----------------------------------------------------------------------------
# Network (VPC / subnets for ECS + optional future ALB)
# Used by network.tf. When you switch to an existing VPC, set
# network_use_existing_vpc = true and fill the existing_* variables.
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for the provider and new VPC resources"
  type        = string
}

variable "network_use_existing_vpc" {
  description = "If true, use network_existing_vpc_id and network_existing_subnet_ids instead of creating module.vpc"
  type        = bool
  default     = false
}

variable "network_existing_vpc_id" {
  description = "Existing VPC ID (required when network_use_existing_vpc is true)"
  type        = string
  default     = ""

  validation {
    condition     = !var.network_use_existing_vpc || trimspace(var.network_existing_vpc_id) != ""
    error_message = "When network_use_existing_vpc is true, set network_existing_vpc_id."
  }
}

variable "network_existing_subnet_ids" {
  description = "Existing subnet IDs for ECS (>= 2 AZs; typically public subnets if assign_public_ip is true)"
  type        = list(string)
  default     = []

  validation {
    condition     = !var.network_use_existing_vpc || length(var.network_existing_subnet_ids) >= 2
    error_message = "When network_use_existing_vpc is true, provide at least two subnet IDs (different AZs)."
  }
}

variable "network_vpc_name" {
  description = "Name tag for the created VPC (ignored when using an existing VPC)"
  type        = string
  default     = "port-ocean"
}

variable "network_vpc_cidr" {
  description = "CIDR for the created VPC"
  type        = string
  default     = "10.48.0.0/16"
}

variable "network_public_subnet_cidrs" {
  description = "Public subnet CIDRs; length sets AZ count (use at least 2 for HA). Paired with the first N availability zones in the region."
  type        = list(string)
  default     = ["10.48.0.0/24", "10.48.1.0/24"]

  validation {
    condition     = var.network_use_existing_vpc || length(var.network_public_subnet_cidrs) >= 2
    error_message = "When creating a VPC, provide at least two public subnet CIDRs (different AZs)."
  }
}

variable "network_private_subnet_cidrs" {
  description = "Private subnet CIDRs; leave empty for public-only (cheapest). If non-empty, set network_enable_nat_gateway = true for egress."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.network_private_subnet_cidrs) == 0 || var.network_enable_nat_gateway
    error_message = "If network_private_subnet_cidrs is non-empty, set network_enable_nat_gateway = true (or use public subnets only)."
  }
}

variable "network_enable_nat_gateway" {
  description = "Enable NAT gateway(s). Required for private subnets without public IPs on tasks."
  type        = bool
  default     = false
}

variable "network_single_nat_gateway" {
  description = "Use one NAT gateway for all AZs (lower cost)"
  type        = bool
  default     = true
}

variable "network_tags" {
  description = "Extra tags for the VPC module"
  type        = map(string)
  default     = {}
}

variable "network_public_subnet_tags" {
  description = "Extra tags for public subnets"
  type        = map(string)
  default     = {}
}

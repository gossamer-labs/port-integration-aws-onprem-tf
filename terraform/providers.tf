provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "integration"
      ManagedBy   = "terraform"
      Project     = "port-ocean-aws"
      Repository  = "port-integration-aws-tf"
    }
  }
}

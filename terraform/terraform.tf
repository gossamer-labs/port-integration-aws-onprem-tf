terraform {
  required_version = ">= 1.14.5"

  cloud {
    organization = "gossamer-labs"

    workspaces {
      tags = ["port-integration-aws-tf"]
    }
  }

  # Without Terraform Cloud: comment out the entire `cloud {}` block above, then choose a backend,
  # e.g. uncomment and configure:
  # backend "s3" {
  #   bucket = "<your-state-bucket>"
  #   key    = "port-integration-aws/terraform.tfstate"
  #   region = "<your-region>"
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.7"
    }
  }
}

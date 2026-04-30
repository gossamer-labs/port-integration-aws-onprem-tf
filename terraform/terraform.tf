terraform {
  required_version = ">= 1.14.5"

  cloud {
    organization = "gossamer-labs"

    workspaces {
      tags = ["port-integration-aws-tf"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.7.0"
    }
  }
}

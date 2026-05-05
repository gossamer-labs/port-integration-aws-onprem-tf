terraform {
  required_version = ">= 1.14.5"

  # Partial Terraform Cloud config: set TF_CLOUD_ORGANIZATION and TF_WORKSPACE (or use
  # terraform login / TF_TOKEN_app_terraform_io). See README.
  cloud {}

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

# port-integration-aws-tf

Port Integration with AWS. Terraform. Real time.

The following sections describe how to configure and run the Terraform in the `terraform/` directory of this repository.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) **1.14.5+** installed (matches other stacks under `port-getting-started/terraform/`)
- A [HashiCorp Cloud Platform](https://developer.hashicorp.com/terraform/cloud-docs) account with access to the **`gossamer-labs`** organization, and a workspace tagged **`port-integration-aws`** (same pattern as `eks-network`, `eks-cluster`, etc.). Run `terraform login` if you have not already.
- AWS credentials for the account where resources run, with permissions to create the resources this module defines (ECS, load balancing, IAM roles, EventBridge, API Gateway, CloudWatch, and related read access for the integration). The `aws` CLI is optional but useful.
- In `terraform/terraform.tfvars`, set **`aws_region`** to the same region as your VPC and subnets. The placeholder VPC and subnet IDs must be replaced with real values; the load balancer needs **at least two subnets in different Availability Zones** in that VPC (typical for an internet-facing ALB).

## AWS authentication

If your organization uses IAM Identity Center (SSO):

```bash
aws sso login
```

Use whatever AWS authentication flow your team expects before `terraform apply`.

## Secrets — use environment variables (never commit)

Do **not** store Port credentials or the live events API key in `terraform/terraform.tfvars`, `.tf` files, or any tracked file. Terraform reads variables whose names start with `TF_VAR_`:

```bash
export TF_VAR_port_client_id="<your Port client id>"
export TF_VAR_port_client_secret="<your Port client secret>"
export TF_VAR_live_events_api_key="<your live events API key>"
```

Use the same three variables in CI/CD: define them as protected secrets in your pipeline, or inject them from a secrets manager, then run `terraform plan` / `terraform apply` in that environment.

## GitHub Actions

Workflow [`.github/workflows/port-integration-aws-tf.yml`](.github/workflows/port-integration-aws-tf.yml) mirrors the pattern used in `port-getting-started` (Terraform Cloud token, OIDC to AWS, composite **`ensure-tfc-workspace`** helper):

| Trigger | Behavior |
|--------|----------|
| **Pull request / push to `main`** (changes under `terraform/` or to `port-integration-aws-tf.yml`) | `terraform fmt -check` only |
| **`workflow_dispatch`** | Choose **plan**, **apply**, or **destroy**, plus Terraform Cloud **workspace name**, **AWS region**, and optional **IAM role ARN** (defaults to the same OIDC role as the EKS workflows). |

**Repository secrets** (same naming as the Port/EKS flows where possible):

| Secret | Purpose |
|--------|---------|
| `TF_API_TOKEN` | [Terraform Cloud API token](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/api-tokens) for `gossamer-labs` |
| `PORT_CLIENT_ID` | Maps to `TF_VAR_port_client_id` |
| `PORT_CLIENT_SECRET` | Maps to `TF_VAR_port_client_secret` |
| `PORT_LIVE_EVENTS_API_KEY` | Maps to `TF_VAR_live_events_api_key` |

The dispatch job sets **`TF_WORKSPACE_NAME`** from the workflow input so Terraform selects the correct Terraform Cloud workspace for your tagged configuration.

## Non-secret configuration (committed)

`terraform/terraform.tfvars` contains **only** non-sensitive values: **AWS region**, subnets, VPC id, cluster name, integration identifier, and feature flags. **Commit** this file when your team’s shared settings change. Replace placeholder subnet and VPC ids with real values for your environment.

## Remote state (HashiCorp Terraform Cloud)

Like other Terraform projects in this org (e.g. `port-getting-started/terraform/network`, `.../cluster`), this stack uses a **`cloud` block** instead of an S3 backend: organization **`gossamer-labs`**, workspace selection by tag **`port-integration-aws`**.

Create a Terraform Cloud workspace in that org and add the tag `port-integration-aws` (or reuse an existing workspace that already has this tag), then from `terraform/` run `terraform init` and pick the workspace when prompted.

## Run locally

From the `terraform` directory, after exporting the `TF_VAR_*` variables above:

```bash
cd terraform
terraform login   # once per machine, if needed
terraform init
terraform plan
terraform apply
```

## Variable reference

- All inputs are declared in `terraform/variables.tf` (including **`aws_region`** — must match your VPC/subnets).
- Sensitive parameters: `port_client_id`, `port_client_secret`, `live_events_api_key` — set with `TF_VAR_*` (or one-off `terraform apply -var='port_client_id=...'` if you must, but avoid putting those in files under version control).

## First-time checklist

- **Port:** Confirm `TF_VAR_*` values match a valid Port API client in your organization.
- **AWS layout:** Subnets must belong to `vpc_id` and span **at least two AZs** (ALB requirement). For an internet-facing load balancer (default `is_internal` in the upstream module is false), subnets are usually **public** unless you use an internal LB — align with how your network is built.
- **`initialize_port_resources`:** When `true` (default in `terraform.tfvars`), the integration can **create default blueprints and mappings in Port**. Use `false` if you only want to wire existing catalog assets.
- **State:** Remote state lives in **HashiCorp Terraform Cloud** (`gossamer-labs`, workspaces tagged **`port-integration-aws`**), consistent with `port-getting-started/terraform/*`.
- **Module version:** The root module pins the Port example module to **`~> 0.0.24`** so upgrades stay within the 0.0.x line; bump intentionally when you want newer upstream behavior.


# port-integration-aws-tf

Port Integration with AWS. Terraform. Real time.

Configuration lives under [`terraform/`](terraform/). The stack **creates a small VPC** by default (see [`network.tf`](terraform/network.tf), [`variables_network.tf`](terraform/variables_network.tf)) so you can deploy without hand-picking subnet IDs. To attach to an **existing** VPC later, set `network_use_existing_vpc = true` and fill `network_existing_vpc_id` / `network_existing_subnet_ids`.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) **1.14.5+** (see [`terraform.tf`](terraform/terraform.tf))
- [HashiCorp Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) access to organization **`gossamer-labs`**, workspace tag **`port-integration-aws-tf`**. Authenticate the CLI with **`terraform login`** or **`export TF_TOKEN_app_terraform_io="..."`** (see [**Secrets**](#secrets-environment-variables-never-commit)).
- AWS credentials able to create VPC, ECS, IAM, and (when you enable live events) load balancing, API Gateway, EventBridge, etc.
- **Port region:** this repo defaults to the **US** API host **`https://api.us.port.io`** in [`terraform.tfvars`](terraform/terraform.tfvars). Use **`https://api.port.io`** for EU.

## AWS authentication

```bash
export AWS_PROFILE="my-sso-profile"   # replace with your profile name (quote if it contains spaces)
aws sso login --profile "$AWS_PROFILE"   # or your org’s auth flow
```

## Secrets — environment variables (never commit)

```bash
export TF_VAR_port_client_id="<Port client id>"
export TF_VAR_port_client_secret="<Port client secret>"
# Optional until live events (phase 2):
# export TF_VAR_live_events_api_key="$(openssl rand -hex 32)"
```

**Terraform Cloud (local CLI)** — optional alternative to interactive `terraform login`. Use a user token from Terraform Cloud **Settings → Tokens** (new or existing). Same value as pasting at the `terraform login` prompt:

```bash
export TF_TOKEN_app_terraform_io="your-token-here"
```

Phase 1 does **not** require `TF_VAR_live_events_api_key`. Add it when you set `allow_incoming_requests = true`.

## Configuration layout

| File | Purpose |
|------|---------|
| [`terraform.tf`](terraform/terraform.tf) | Terraform version, **Terraform Cloud** org `gossamer-labs`, workspace tag **`port-integration-aws-tf`**, AWS provider constraints |
| [`providers.tf`](terraform/providers.tf) | AWS provider; **`default_tags`** (`Environment`, `ManagedBy`, `Project`, `Repository`) |
| [`variables_network.tf`](terraform/variables_network.tf) | VPC / subnets (`network_*`), `aws_region` |
| [`variables_integration.tf`](terraform/variables_integration.tf) | Port Ocean module inputs (`port_*`, integration, ECS) |
| [`network.tf`](terraform/network.tf) | `terraform-aws-modules/vpc` (**v5.x**, pairs with Port module’s AWS provider **5.x**) |
| [`main.tf`](terraform/main.tf) | `module "aws"` — Port [`aws_container_app`](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app) |
| [`outputs.tf`](terraform/outputs.tf) | VPC id, subnet ids, create mode |
| [`terraform.tfvars`](terraform/terraform.tfvars) | Non-secret defaults (includes **`integration_identifier`**, **`aws_region`**) |

## Phase 1 vs phase 2

- **Phase 1 (default in `terraform.tfvars`):** `allow_incoming_requests = false` — scheduled **POLLING** sync only; **no** ALB, API Gateway, or EventBridge. Good for first validation.
- **Phase 2 (live events):** set `allow_incoming_requests = true`, generate `TF_VAR_live_events_api_key`, apply again. Per [Port docs](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events), live events are **single-account only**. Multi-account needs separate planning.
- **CI (phase 2):** add `TF_VAR_live_events_api_key: ${{ secrets.PORT_LIVE_EVENTS_API_KEY }}` to the **`terraform` job `env`** in [`.github/workflows/port-integration-aws-tf.yml`](.github/workflows/port-integration-aws-tf.yml) (see comment there); create the **`PORT_LIVE_EVENTS_API_KEY`** repository secret.

## Remote state (Terraform Cloud)

Organization **`gossamer-labs`**. Workspaces that carry tag **`port-integration-aws-tf`** are eligible for this configuration ([`terraform.tf`](terraform/terraform.tf) `cloud.workspaces.tags`).

**Selecting a workspace (non-interactive):** set **`TF_WORKSPACE`** to the workspace **name** (same string as GitHub Actions `workflow_dispatch` → **`tf_workspace`**).

**Terraform Cloud API token:** run **`terraform login`** once, or set **`TF_TOKEN_app_terraform_io`** (see [**Secrets**](#secrets-environment-variables-never-commit)) — equivalent to storing the token from the login flow.

Example:

```bash
export TF_WORKSPACE=my-team-port-aws
export TF_TOKEN_app_terraform_io="your-token-here"   # or run `terraform login` instead
cd terraform && terraform init
```

Without **`TF_WORKSPACE`**, `terraform init` may prompt you to pick one workspace among those matching the tag.

## GitHub Actions

Workflow [`.github/workflows/port-integration-aws-tf.yml`](.github/workflows/port-integration-aws-tf.yml):

| Trigger | Behavior |
|--------|----------|
| **Pull request** (paths `terraform/**` or this workflow) | **`terraform` job:** `terraform fmt -check`, **`terraform plan`** (after **`format`** job). Same-repo PRs only (fork PRs skip Terraform; secrets/OIDC are unavailable). |
| **Push to `main`** (same paths) | **`terraform` job:** **`terraform apply`** (runs after merge to trunk). |
| **`workflow_dispatch`** | **`format`** then **`terraform` job:** choose **plan** / **apply** / **destroy** and supply **`tf_workspace`**, **`aws_region`**, optional **`aws_role_arn`**. |

On every **`terraform`** run, [**`ensure-tfc-workspace`**](.github/actions/ensure-tfc-workspace/action.yml) runs first (for **plan**/**apply**, creates the workspace when missing; **destroy** requires an existing workspace). Applies tag **`port-integration-aws-tf`**, **local** execution mode.

**Repository variables** (Settings → Secrets and variables → Actions → **Variables** — required for PR / `main` automation; workflow dispatch can override with inputs)

| Variable | Purpose |
|----------|---------|
| **`TFC_WORKSPACE`** | Terraform Cloud **workspace name** (must match a workspace tagged **`port-integration-aws-tf`**). Optional for PR / **`main`**; workflow defaults to **`port-integration-aws-tf`** if unset. |
| **`AWS_REGION`** | AWS region for OIDC (optional; defaults to **`us-east-2`** in the workflow). Must match **`aws_region`** in [`terraform.tfvars`](terraform/terraform.tfvars). |
| **`AWS_ROLE_ARN`** | IAM role for GitHub OIDC (optional; defaults to **`arn:aws:iam::936835732720:role/github-actions-deploy`**). |

**Repository secrets** (Settings → Secrets and variables → Actions → **Secrets** — use **Secrets**, not **Variables**; required for the **`terraform`** job)

| Secret | Purpose |
|--------|---------|
| `TF_API_TOKEN` | Terraform Cloud API token |
| `PORT_CLIENT_ID` | `TF_VAR_port_client_id` |
| `PORT_CLIENT_SECRET` | `TF_VAR_port_client_secret` |
| `PORT_LIVE_EVENTS_API_KEY` | Phase 2 only: create secret and add `TF_VAR_live_events_api_key` to the **`terraform` job `env`** (not wired in repo until then) |

**Dispatch** supplies **`TF_WORKSPACE`** via **`tf_workspace`**. **PR / `main`** use **`vars.TFC_WORKSPACE`** when set (optional **`vars.AWS_REGION`** / **`vars.AWS_ROLE_ARN`**); workspace name falls back to **`port-integration-aws-tf`** to match workflow **`env.TF_WORKSPACE`** defaults. The OIDC region should match **`aws_region`** in [`terraform.tfvars`](terraform/terraform.tfvars); Terraform still reads **`var.aws_region`** from tfvars for the provider.

**Apply on `main`:** any **push** to **`main`** that matches the path filter runs **apply** (including direct pushes, not only merges). Restrict merges via branch protection if needed.

## Run locally

Authenticate to AWS first so the Terraform AWS provider can reach your account (for example **`export AWS_PROFILE="my-sso-profile"`** then **`aws sso login --profile "$AWS_PROFILE"`** if you use IAM Identity Center — replace **`my-sso-profile`** with your profile; otherwise use [**AWS authentication**](#aws-authentication) above). Leave **`AWS_PROFILE`** exported so Terraform uses the same credentials.

For **Terraform Cloud** remote state, authenticate with **`export TF_TOKEN_app_terraform_io="..."`** or **`terraform login`** before **`terraform init`** (see [**Secrets**](#secrets-environment-variables-never-commit)).

```bash
export AWS_PROFILE="my-sso-profile"   # replace with your profile name (quote if it contains spaces)
aws sso login --profile "$AWS_PROFILE"   # or your org’s AWS credential flow
cd terraform
export AWS_DEFAULT_REGION=us-east-2   # same value as aws_region in terraform.tfvars
export TF_WORKSPACE=<your-tfc-workspace-name>   # optional but avoids init prompts
export TF_VAR_port_client_id="..."
export TF_VAR_port_client_secret="..."
export TF_TOKEN_app_terraform_io="your-token-here"   # optional; or run `terraform login` instead
terraform init
terraform plan
terraform apply
```

## First-time checklist

- **AWS:** Ensure credentials target **`us-east-2`** (matches [`terraform.tfvars`](terraform/terraform.tfvars)) before `terraform plan` / `apply`.
- **Secrets / CI:** Export `TF_VAR_port_client_id` and `TF_VAR_port_client_secret` locally; add **`TF_API_TOKEN`**, **`PORT_CLIENT_ID`**, and **`PORT_CLIENT_SECRET`** as **repository secrets** (Settings → Secrets and variables → Actions → **Secrets**). Optionally set repository **Variables** **`TFC_WORKSPACE`** (and **`AWS_REGION`** / **`AWS_ROLE_ARN`**) for **PR plan** and **`main` apply** — defaults match the workflow if omitted. For local Terraform Cloud auth, use **`terraform login`** or **`TF_TOKEN_app_terraform_io`** (see [**Secrets**](#secrets-environment-variables-never-commit)).
- **Port:** Confirm **`port_base_url`** matches your Port region (US `api.us.port.io` vs EU `api.port.io`).
- **Network:** If CIDR **`10.48.0.0/16`** overlaps another VPC or peered network, change `network_vpc_cidr` and `network_public_subnet_cidrs` together.
- **ECS networking:** **`assign_public_ip = true`** matches **public subnets + no NAT** (default bundle). For private subnets + NAT, set `network_private_subnet_cidrs`, `network_enable_nat_gateway = true`, and `assign_public_ip = false`.
- **Image tag:** Omit **`integration_version`** in `terraform.tfvars` to use the upstream default (`latest`), or set a concrete tag after you confirm one from the running task / registry for reproducible deploys.
- Commit [`.terraform.lock.hcl`](terraform/.terraform.lock.hcl); regenerate with `terraform providers lock` when upgrading providers.

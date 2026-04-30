# port-integration-aws-tf

Port Integration with AWS. Terraform. Real time.

Configuration lives under [`terraform/`](terraform/). The stack **creates a small VPC** by default (see [`network.tf`](terraform/network.tf), [`variables_network.tf`](terraform/variables_network.tf)) so you can deploy without hand-picking subnet IDs. To attach to an **existing** VPC later, set `network_use_existing_vpc = true` and fill `network_existing_vpc_id` / `network_existing_subnet_ids`.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) **1.14.5+** (see [`terraform.tf`](terraform/terraform.tf))
- [HashiCorp Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) access to organization **`gossamer-labs`**, workspace tag **`port-integration-aws`**. Run `terraform login` locally if needed.
- AWS credentials able to create VPC, ECS, IAM, and (when you enable live events) load balancing, API Gateway, EventBridge, etc.
- **Port region:** this repo defaults to the **US** API host **`https://api.us.port.io`** in [`terraform.tfvars`](terraform/terraform.tfvars). Use **`https://api.port.io`** for EU.

## AWS authentication

```bash
aws sso login   # or your org’s auth flow
```

## Secrets — environment variables (never commit)

```bash
export TF_VAR_port_client_id="<Port client id>"
export TF_VAR_port_client_secret="<Port client secret>"
# Optional until live events (phase 2):
# export TF_VAR_live_events_api_key="$(openssl rand -hex 32)"
```

Phase 1 does **not** require `TF_VAR_live_events_api_key`. Add it when you set `allow_incoming_requests = true`.

## Configuration layout

| File | Purpose |
|------|---------|
| [`terraform.tf`](terraform/terraform.tf) | Terraform version, **Terraform Cloud** org `gossamer-labs`, workspace tag **`port-integration-aws`**, AWS provider constraints |
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

Organization **`gossamer-labs`**. Workspaces that carry tag **`port-integration-aws`** are eligible for this configuration ([`terraform.tf`](terraform/terraform.tf) `cloud.workspaces.tags`).

**Selecting a workspace (non-interactive):** set **`TF_WORKSPACE`** to the workspace **name** (same string as GitHub Actions `workflow_dispatch` → **`tf_workspace`**). Example:

```bash
export TF_WORKSPACE=my-team-port-aws
terraform login   # once
cd terraform && terraform init
```

Without **`TF_WORKSPACE`**, `terraform init` may prompt you to pick one workspace among those matching the tag.

## GitHub Actions

Workflow [`.github/workflows/port-integration-aws-tf.yml`](.github/workflows/port-integration-aws-tf.yml):

| Trigger | Behavior |
|--------|----------|
| **PR / push to `main`** (paths `terraform/**` or this workflow) | `terraform fmt -check` |
| **`workflow_dispatch`** | `plan` / `apply` / `destroy` with Terraform Cloud workspace name |

On dispatch, [**`ensure-tfc-workspace`**](.github/actions/ensure-tfc-workspace/action.yml) runs first (for **plan**/**apply**, creates the workspace when missing; **destroy** requires an existing workspace). Applies tag **`port-integration-aws`**, **local** execution mode.

**Secrets**

| Secret | Purpose |
|--------|---------|
| `TF_API_TOKEN` | Terraform Cloud API token |
| `PORT_CLIENT_ID` | `TF_VAR_port_client_id` |
| `PORT_CLIENT_SECRET` | `TF_VAR_port_client_secret` |
| `PORT_LIVE_EVENTS_API_KEY` | Phase 2 only: create secret and add `TF_VAR_live_events_api_key` to the workflow job `env` (not wired in repo until then) |

The **`terraform` job** sets **`TF_WORKSPACE`** from the `tf_workspace` input so the CLI selects one workspace among those tagged **`port-integration-aws`**. The **`aws_region`** workflow input must match **`aws_region`** in [`terraform.tfvars`](terraform/terraform.tfvars): it configures the OIDC AWS session; Terraform still reads **`var.aws_region`** from tfvars for the provider.

## Run locally

Authenticate to AWS first so the Terraform AWS provider can reach your account (for example **`aws sso login`** if your profile uses IAM Identity Center; otherwise use the flow from [**AWS authentication**](#aws-authentication) above).

```bash
aws sso login   # or your org’s AWS credential flow
cd terraform
export AWS_DEFAULT_REGION=us-east-2   # same value as aws_region in terraform.tfvars
export TF_WORKSPACE=<your-tfc-workspace-name>   # optional but avoids init prompts
export TF_VAR_port_client_id="..."
export TF_VAR_port_client_secret="..."
terraform login    # if using Terraform Cloud
terraform init
terraform plan
terraform apply
```

## First-time checklist

- **AWS:** Ensure credentials target **`us-east-2`** (matches [`terraform.tfvars`](terraform/terraform.tfvars)) before `terraform plan` / `apply`.
- **Secrets:** Export `TF_VAR_port_client_id` and `TF_VAR_port_client_secret` locally; add `TF_API_TOKEN`, `PORT_CLIENT_ID`, and `PORT_CLIENT_SECRET` to the GitHub repo before running the workflow.
- **Port:** Confirm **`port_base_url`** matches your Port region (US `api.us.port.io` vs EU `api.port.io`).
- **Network:** If CIDR **`10.48.0.0/16`** overlaps another VPC or peered network, change `network_vpc_cidr` and `network_public_subnet_cidrs` together.
- **ECS networking:** **`assign_public_ip = true`** matches **public subnets + no NAT** (default bundle). For private subnets + NAT, set `network_private_subnet_cidrs`, `network_enable_nat_gateway = true`, and `assign_public_ip = false`.
- **Image tag:** Omit **`integration_version`** in `terraform.tfvars` to use the upstream default (`latest`), or set a concrete tag after you confirm one from the running task / registry for reproducible deploys.
- Commit [`.terraform.lock.hcl`](terraform/.terraform.lock.hcl); regenerate with `terraform providers lock` when upgrading providers.

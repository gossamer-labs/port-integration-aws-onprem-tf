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
| [`variables_network.tf`](terraform/variables_network.tf) | VPC / subnets (`network_*`), `aws_region` |
| [`variables_integration.tf`](terraform/variables_integration.tf) | Port Ocean module (`port_*`, integration, ECS) |
| [`network.tf`](terraform/network.tf) | Optional `terraform-aws-modules/vpc` (**v5.x** — compatible with the Port module’s AWS provider `~> 5.x`) |
| [`main.tf`](terraform/main.tf) | `module "aws"` — Port [`aws_container_app`](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app) |
| [`terraform.tfvars`](terraform/terraform.tfvars) | Non-secret defaults (`integration_identifier` is set for this stack) |

## Phase 1 vs phase 2

- **Phase 1 (default in `terraform.tfvars`):** `allow_incoming_requests = false` — scheduled **POLLING** sync only; **no** ALB, API Gateway, or EventBridge. Good for first validation.
- **Phase 2 (live events):** set `allow_incoming_requests = true`, generate `TF_VAR_live_events_api_key`, apply again. Per [Port docs](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events), live events are **single-account only**. Multi-account needs separate planning.

## Remote state (Terraform Cloud)

Organization **`gossamer-labs`**, workspaces tagged **`port-integration-aws`**. Create or select a workspace, then run `terraform init` and choose it when prompted.

## GitHub Actions

Workflow [`.github/workflows/port-integration-aws-tf.yml`](.github/workflows/port-integration-aws-tf.yml):

| Trigger | Behavior |
|--------|----------|
| **PR / push to `main`** (paths `terraform/**` or this workflow) | `terraform fmt -check` |
| **`workflow_dispatch`** | `plan` / `apply` / `destroy` with Terraform Cloud workspace name |

**Secrets**

| Secret | Purpose |
|--------|---------|
| `TF_API_TOKEN` | Terraform Cloud API token |
| `PORT_CLIENT_ID` | `TF_VAR_port_client_id` |
| `PORT_CLIENT_SECRET` | `TF_VAR_port_client_secret` |
| `PORT_LIVE_EVENTS_API_KEY` | Optional until phase 2; maps to `TF_VAR_live_events_api_key` if you add it to the workflow `env` |

The job sets **`TF_WORKSPACE`** (not `TF_WORKSPACE_NAME`) so the CLI selects the correct Terraform Cloud workspace.

## Run locally

```bash
cd terraform
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

# port-integration-aws-onprem-tf

Deploy the Port **AWS** integration on **ECS** with **Terraform**, optional **Terraform Cloud** remote state, and **GitHub Actions** for multiple environments. This repo wires up the [Port Ocean `aws_container_app`](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app) module, optional VPC and CloudTrail bootstrap, and CI that **plans and applies** to **development** on pull requests and non-trunk pushes, and to **production** on pushes to the repository **default branch** (trunk).

**Two sync paths** (pick one in your varfile):

| Path | When to use | Key settings |
|------|-------------|--------------|
| **Live events** (single account) | Real-time catalog updates via EventBridge → API Gateway → webhook | `allow_incoming_requests = true`, CloudTrail recommended |
| **Polling** (multi-account) | Org-wide read across member accounts | `allow_incoming_requests = false`, `organization_role_arn` + `account_read_role_name` |

Configuration lives under [`terraform/`](terraform/). Per-environment values go in [`terraform/environments/*.tfvars`](terraform/environments/) — there is no auto-loaded root `terraform.tfvars`.

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) **≥ 1.14.5** ([`terraform/terraform.tf`](terraform/terraform.tf))
- AWS credentials that can create VPC, ECS, IAM, ELB, API Gateway, EventBridge, SSM, CloudTrail, and S3 (as needed for your path)
- A [Port](https://www.port.io/) organization and API credentials (`client_id` / `client_secret`)
- *(Optional)* [Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) organization and API token for remote state
- *(Optional)* GitHub repository with **Environments** configured for CI

Default **`port_base_url`** is US (`https://api.us.port.io`). Use `https://api.port.io` for EU.

---

## 🚀 Quick start

**1. Copy a varfile per environment**

```bash
cp terraform/environments/example.tfvars terraform/environments/development.tfvars
# edit port_org_slug, aws_region, network_*, cluster_name, cloudtrail_name_prefix, etc.
```

**2. Set secrets** (never commit these)

```bash
export TF_VAR_port_client_id="<Port client id>"
export TF_VAR_port_client_secret="<Port client secret>"
export TF_VAR_live_events_api_key="$(openssl rand -hex 32)"   # Path 1 only; reuse in CI as PORT_LIVE_EVENTS_API_KEY
```

**3. Terraform Cloud** *(if using `cloud {}` in [`terraform.tf`](terraform/terraform.tf))*

```bash
export TF_CLOUD_ORGANIZATION="<your-tfc-org>"
export TF_WORKSPACE="<workspace-name>"   # CI default: $TFC_WORKSPACE_SLUG-$ENVIRONMENT
export TF_TOKEN_app_terraform_io="..."   # or: terraform login
```

**4. AWS**

```bash
export AWS_PROFILE="my-profile"
aws sso login --profile "$AWS_PROFILE"
export AWS_DEFAULT_REGION="<same-as-aws_region-in-your-varfile>"
```

**5. Plan**

```bash
cd terraform
terraform init -input=false
terraform plan -input=false -var-file=environments/development.tfvars
```

For CI, configure GitHub **Environments** (`development`, `production`) — see [GitHub Actions](#github-actions).

---

## Configuration

### Environment tfvars

Each environment is one file: **`terraform/environments/<name>.tfvars`**. The name must match:

- Your GitHub Actions environment name
- CI **`ENVIRONMENT`** (set by the workflow, not a repo variable)
- Terraform Cloud workspace **`$TFC_WORKSPACE_SLUG-<name>`**

Shipped examples:

| File | `port_org_slug` | VPC CIDR | Notes |
|------|-----------------|----------|--------|
| [`development.tfvars`](terraform/environments/development.tfvars) | `goss-lab` | `10.48.0.0/16` | PR / non-trunk push CI |
| [`production.tfvars`](terraform/environments/production.tfvars) | `goss-prod` | `10.49.0.0/16` | Push to default branch CI |

GitHub environment names (`development`, `production`) are independent of AWS/Port resource names in the varfiles (e.g. `port_org_slug`, `network_vpc_name`).

Start from [`example.tfvars`](terraform/environments/example.tfvars) — it documents every root variable. Optional gitignored overlay: `environments/<name>.local.tfvars`.

Pass **`-var-file=environments/<name>.tfvars`** on every `plan`, `apply`, and `destroy`.

### Resource naming (same AWS account + region)

If two environments share one account and region, these **must differ** per environment:

| Variable | Affects |
|----------|---------|
| `port_org_slug` | Port integration ID (`onprem-tf-<slug>`), IAM roles, ECS service name |
| `cluster_name` | ECS cluster |
| `network_vpc_name` | VPC `Name` tag (used by `data.aws_vpc` lookup) |
| `network_vpc_cidr` | VPC CIDR (use non-overlapping ranges) |
| `cloudtrail_name_prefix` | Trail `{prefix}-live-events` and bucket `{prefix}-cloudtrail-logs-<account_id>` |

Suffix pattern in the shipped files: development varfile uses `*-lab` / `goss-lab`; production varfile uses `*-prod` / `goss-prod` (AWS resource names, not the GitHub environment name).

**Separate AWS accounts per environment** (recommended for production): only `port_org_slug` (Port-side) and `cloudtrail_name_prefix` (S3 names are global) need to differ; other resources are scoped per account.

### Integration identifier and IAM name length

- Default Port integration ID: **`onprem-tf-<port_org_slug>`** unless you set **`integration_identifier`** explicitly (do that to preserve an existing registration when changing slug).
- Upstream builds **`service_name`** = `port-ocean-aws-<identifier>` and IAM role **`ecs-task-execution-role-<service_name>`** (max **64** characters). With type `aws`, **`identifier` ≤ 25** characters — keep **`port_org_slug`** short. **`cluster_name` does not affect IAM role names.**

If apply fails with IAM name length errors, shorten `port_org_slug` or set a shorter `integration_identifier`.

### Secrets (local and CI)

| Name | Where | Purpose |
|------|--------|---------|
| `TF_VAR_port_client_id` | GitHub **variable** `PORT_CLIENT_ID` | Port API |
| `TF_VAR_port_client_secret` | Secret `PORT_CLIENT_SECRET` | Port API |
| `TF_VAR_live_events_api_key` | Secret `PORT_LIVE_EVENTS_API_KEY` | Webhook validation (Path 1) |
| `TF_TOKEN_app_terraform_io` / `TF_API_TOKEN` | Secret `TF_API_TOKEN` | Terraform Cloud + `ensure-tfc-workspace` |

`event_listener_type = "POLLING"` controls scheduled sync with Port; it is **not** a substitute for live events.

---

## Live events vs multi-account

Terraform enforces mutual exclusivity at plan time ([`integration.tf`](terraform/integration.tf)):

- **Path 1 — live events:** `allow_incoming_requests = true`. Do **not** set `organization_role_arn` / `account_read_role_name`. Provisions ALB, API Gateway, and EventBridge. Requires **`TF_VAR_live_events_api_key`**. [Port docs](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events).
- **Path 2 — multi-account polling:** `allow_incoming_requests = false` and **both** `organization_role_arn` and `account_read_role_name`. Live events are not supported. [Port docs](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/multi_account).

### CloudTrail (Path 1)

Port’s EventBridge rules match **`AWS API Call via CloudTrail`** on the default bus. You need an **active trail** logging **management events** — console “Event history” alone is not enough.

When `allow_incoming_requests` and `cloudtrail_enabled` are both `true`, this repo creates a multi-Region trail and (by default) a managed S3 log bucket with lifecycle, encryption, and public-access blocks ([`cloudtrail.tf`](terraform/cloudtrail.tf)).

| Resource | Name pattern |
|----------|----------------|
| Trail | `{cloudtrail_name_prefix}-live-events` |
| Bucket | `{cloudtrail_name_prefix}-cloudtrail-logs-{aws_account_id}` |

Set `cloudtrail_enabled = false` if the account already has a suitable trail. Use `cloudtrail_existing_log_bucket_name` to point at your bucket (Terraform attaches bucket policy; you need `PutBucketPolicy`).

After apply, **`terraform output live_events_webhook_url`** returns the HTTPS webhook URL when live events are enabled.

### Extending EventBridge rules

The Ocean module ships default rules for EC2, S3, and CloudFormation. Add more in [`live_event_resources.tf`](terraform/live_event_resources.tf) (examples: EKS cluster and node group). [Add other services](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events#add-other-services).

---

## Network

| Mode | Settings | Behavior |
|------|----------|----------|
| **Greenfield** (default) | `network_use_existing_vpc = false` | [`network.tf`](terraform/network.tf) creates a VPC and public subnets; [`integration.tf`](terraform/integration.tf) passes `module.vpc[0].public_subnets` to ECS |
| **Bring your own** | `network_use_existing_vpc = true`, `network_existing_vpc_id`, `network_existing_subnet_ids` (≥2 AZs) | Subnets validated against the VPC |

Default bundle: **public subnets**, `assign_public_ip = true`, `network_enable_nat_gateway = false`. For private subnets + NAT, set `network_private_subnet_cidrs`, `network_enable_nat_gateway = true`, and `assign_public_ip = false`.

Avoid CIDR overlap with peered networks; change `network_vpc_cidr` and subnet CIDRs together.

---

## GitHub Actions

Workflow: [`.github/workflows/port-integration-aws-onprem-tf.yml`](.github/workflows/port-integration-aws-onprem-tf.yml)

| Trigger | `ENVIRONMENT` | Terraform |
|---------|---------------|-----------|
| **Push** (non-trunk, path filter) | `development` | `plan -out` (artifact), `apply` |
| **Pull request** (`terraform/**` or workflow) | `development` | `plan -out` (artifact), `apply` (same-repo PRs only; forks skip) |
| **Push** (default branch / trunk) | `production` | `plan -out` (artifact), `apply` |
| **`workflow_dispatch`** | Required input (`development` / `production`) | `plan -out` (artifact) or `destroy` (no apply) |

`ENVIRONMENT` is **never** a GitHub variable — the pipeline sets it. Trunk is the repository **default branch** (`github.event.repository.default_branch`), not a hardcoded branch name. Restrict production deploys via GitHub **environment protection** on `production` (limit to the default branch in the UI).

On push and pull request runs, a single `plan -out` step produces the binary plan file (`terraform/tfplan`); apply uses that file in the same job, and the workflow uploads it as a run artifact (`tfplan-<environment>-<run_id>`) for audit.

Before opening a PR, run from `terraform/`: **`terraform fmt -recursive`**.

### Per-environment GitHub config

The workflow **Validate environment config** step fails fast if the varfile or GitHub environment is missing, or if any required variable or secret below is empty for the target environment.

**Variables** (Settings → Environments → `<name>`)

| Variable | Purpose |
|----------|---------|
| `TFC_ORGANIZATION` | → `TF_CLOUD_ORGANIZATION` |
| `TFC_WORKSPACE_SLUG` | Base name; workspace = `$TFC_WORKSPACE_SLUG-$ENVIRONMENT` |
| `TFC_WORKSPACE_TAGS` | Tags for `ensure-tfc-workspace` |
| `AWS_REGION` | Must match `aws_region` in varfile |
| `AWS_ACCOUNT_ID` | OIDC role ARN account segment |
| `AWS_ROLE_NAME` | OIDC IAM role name |
| `PORT_CLIENT_ID` | → `TF_VAR_port_client_id` |

**Secrets**

| Secret | Purpose |
|--------|---------|
| `TF_API_TOKEN` | Terraform Cloud + workspace ensure |
| `PORT_CLIENT_SECRET` | → `TF_VAR_port_client_secret` |
| `PORT_LIVE_EVENTS_API_KEY` | → `TF_VAR_live_events_api_key` |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Only if `USE_AWS_STATIC_CREDENTIALS=true` |

### Workflow flags (edit YAML, not GitHub Variables)

| Flag | Default | Purpose |
|------|---------|---------|
| `USE_TERRAFORM_CLOUD_BACKEND` | `true` | Terraform Cloud vs S3/local state |
| `USE_AWS_STATIC_CREDENTIALS` | `false` | Static keys vs OIDC |

All four combinations are valid (see comments in the workflow). When `USE_TERRAFORM_CLOUD_BACKEND=false`, CI skips [`gha-ensure-tfc-workspace`](https://github.com/gossamer-labs/gha-ensure-tfc-workspace) and `TF_API_TOKEN` may be unnecessary for `init`.

### OIDC troubleshooting

If **`AssumeRoleWithWebIdentity`** is denied, the IAM role trust policy must allow this repository’s `sub` claim, for example:

```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": "repo:<org>/<repo>:*"
}
```

The `terraform` job sets `permissions: id-token: write`.

---

## ☁️ Remote state (Terraform Cloud)

[`terraform.tf`](terraform/terraform.tf) uses a **partial** `cloud {}` block. Before `terraform init`:

```bash
export TF_CLOUD_ORGANIZATION="<org>"
export TF_WORKSPACE="<workspace-name>"
```

CI sets `TF_WORKSPACE` to **`${TFC_WORKSPACE_SLUG}-${ENVIRONMENT}`**.

**Without Terraform Cloud:**

1. Comment out the entire `cloud {}` block in [`terraform.tf`](terraform/terraform.tf).
2. Uncomment/configure `backend "s3"` in the same file, or omit a backend for local state.
3. Run `terraform init -migrate-state` if switching an existing workspace.
4. Set **`USE_TERRAFORM_CLOUD_BACKEND=false`** in the workflow YAML.

---

## Running locally

One flow — same secrets and varfile as CI:

```bash
export AWS_PROFILE="my-profile"
aws sso login --profile "$AWS_PROFILE"
export AWS_DEFAULT_REGION="us-east-2"   # match aws_region in your varfile

export TF_CLOUD_ORGANIZATION="<org>"
export TF_WORKSPACE="<workspace>"
export TF_TOKEN_app_terraform_io="..."   # or terraform login

export TF_VAR_port_client_id="..."
export TF_VAR_port_client_secret="..."
export TF_VAR_live_events_api_key="..."    # Path 1 only

cd terraform
terraform init -input=false
terraform plan -input=false -var-file=environments/development.tfvars
terraform apply -input=false -var-file=environments/development.tfvars
```

Commit [`.terraform.lock.hcl`](terraform/.terraform.lock.hcl); regenerate with `terraform providers lock` when upgrading providers.

---

## 🧹 Teardown

1. Run the workflow with **`workflow_dispatch`**, **`mode: destroy`**, and the target **environment**.
2. If destroy fails on a **non-empty S3 bucket** (common with versioned CloudTrail logs), empty the bucket (including versions and delete markers), then re-run destroy. Use `terraform output cloudtrail_log_bucket_name` while state still exists.
3. **Terraform does not remove the Port integration registration** — disconnect or delete it in Port after AWS resources are gone.
4. **Terraform Cloud** workspaces and **Port catalog** objects (from `initialize_port_resources = true`) may persist until you clean them up separately.

---

## ✅ Verifying live events

1. **`terraform output live_events_webhook_url`** — confirm the URL when `allow_incoming_requests = true`.
2. **EventBridge → Rules** — invocation count should rise after you change a supported resource (e.g. S3 bucket), if CloudTrail is delivering management events.
3. **Port** — check integration event logs; **CloudWatch** for the ECS task if needed.
4. **Mappings** — ensure your Port integration mapping includes the resource types you expect (e.g. `AWS::S3::Bucket`).

---

## Terraform layout

| File | Role |
|------|------|
| [`terraform.tf`](terraform/terraform.tf) | Version, partial `cloud {}`, provider constraints |
| [`providers.tf`](terraform/providers.tf) | AWS provider + `default_resource_tags` |
| [`main.tf`](terraform/main.tf) | Account-level data (`aws_caller_identity`, `aws_partition`) |
| [`network.tf`](terraform/network.tf) | Optional VPC module (`terraform-aws-modules/vpc` ~> 5.x) |
| [`integration.tf`](terraform/integration.tf) | `module "aws"`, config validation, VPC/subnet wiring, outputs |
| [`cloudtrail.tf`](terraform/cloudtrail.tf) | CloudTrail + S3 for live events |
| [`live_event_resources.tf`](terraform/live_event_resources.tf) | Extra EventBridge rules + `live_events_webhook_url` |
| [`variables_*.tf`](terraform/) | Root module variables |
| [`environments/`](terraform/environments/) | Per-environment `*.tfvars` |

**Outputs:** `integration_identifier`, `network_vpc_id`, `network_subnet_ids_for_ecs`, `live_events_webhook_url`, `cloudtrail_name`, `cloudtrail_arn`, `cloudtrail_log_bucket_name` (where applicable).

---

## First-time checklist

- [ ] Copy `example.tfvars` → `environments/<name>.tfvars` for each GitHub environment
- [ ] Create GitHub environments **`development`** and **`production`** and set **Variables** / **Secrets** (copy from legacy `lab` / `prod` or `integration` if renaming)
- [ ] Apply deployment protection on **`production`** (restrict to the repository default branch, reviewers as needed)
- [ ] Set **`port_org_slug`** (and unique naming if same account)
- [ ] Confirm **`port_base_url`** matches your Port region
- [ ] Align **`aws_region`** in varfile with `AWS_REGION` / `AWS_DEFAULT_REGION`
- [ ] Generate and store **`live_events_api_key`** for Path 1
- [ ] Configure IAM OIDC trust for this repo (if using CI with OIDC)
- [ ] Run `terraform fmt -recursive` before pushing Terraform changes

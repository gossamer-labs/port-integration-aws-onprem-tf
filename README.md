# port-integration-aws-onprem-tf

Port **AWS** integration on **ECS** with **Terraform**, **Terraform Cloud** remote state, and **live events** (EventBridge → API Gateway → integration webhook) in one deployment path.

Configuration lives under [`terraform/`](terraform/). The stack **creates a small VPC** by default (see [`network.tf`](terraform/network.tf), [`variables_network.tf`](terraform/variables_network.tf)) so you can deploy without hand-picking subnet IDs. To attach to an **existing** VPC later, set `network_use_existing_vpc = true` and fill `network_existing_vpc_id` / `network_existing_subnet_ids`.

[`terraform/environments/`](terraform/environments/) holds **per-environment** `*.tfvars`. Copy [`terraform/environments/example.tfvars`](terraform/environments/example.tfvars) to **`environments/<environment-name>.tfvars`** (e.g. **`integration.tfvars`**, **`production.tfvars`**), edit values (including **`aws_region`**), and pass **`-var-file=environments/<name>.tfvars`** on every `plan` / `apply` / `destroy` — there is no auto-loaded root `terraform.tfvars`. The filename must match your GitHub Actions environment name and CI **`ENVIRONMENT`** value.

**Live events vs multi-account:** Per [Port live events](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events), live events are **single-account only**. This repo enforces that at plan time: **`allow_incoming_requests = true`** cannot be combined with **`organization_role_arn`** / **`account_read_role_name`**. For [multi-account](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/multi_account), set **`allow_incoming_requests = false`** and supply both role knobs (see `example.tfvars` Mode B).

**Integration identifier:** set **`port_org_slug`** in your varfile (required variable; no default in `variables_integration.tf`). The Port integration identifier is **`onprem-tf-<port_org_slug>`** unless you override **`integration_identifier`** explicitly in Terraform.

### IAM role name length (integration naming)

AWS [IAM role `name` quotas](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html) cap **customer-managed role names at 64 characters**. The [`aws_container_app`](terraform/main.tf) module from [`port-labs/integration-factory/ocean`](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app) follows [upstream `ecs_service`](https://github.com/port-labs/terraform-ocean-integration-factory/blob/main/modules/aws_helpers/ecs_service/main.tf):

- **`service_name`** = `port-ocean-<integration.type>-<integration.identifier>` — this stack uses **`integration.type = aws`** from the module.
- **`aws_iam_role.task_execution_role.name`** = **`ecs-task-execution-role-`** + **`service_name`**. The literal prefix **`ecs-task-execution-role-`** is **24** characters, so **`len(service_name)` must be ≤ 40** (because **24 + 40 = 64**).
- With **`integration.type = aws`**, **`service_name`** starts with **`port-ocean-aws-`** (**15** characters). So **`integration.identifier` must be ≤ 25** characters (**15 + 25 = 40**).

**`cluster_name` does not appear in that IAM role name.** If apply fails on IAM length, shorten **`integration_identifier`** or **`port_org_slug`** (when using the default **`onprem-tf-<port_org_slug>`**), not the ECS cluster name.

**Worked example (short slug):** identifier **`onprem-tf-acme`** → **`service_name`** = **`port-ocean-aws-onprem-tf-acme`** (**28** chars) → execution role name **`ecs-task-execution-role-port-ocean-aws-onprem-tf-acme`** (**52** chars, within **64**).

**Levers**

- **`integration_identifier`** — set explicitly when you need a specific stable id (still avoid unnecessary churn after first apply).
- **`port_org_slug`** — only drives the default id when **`integration_identifier`** is unset.

If **`terraform apply`** fails with **`expected length of name to be in the range (1 - 64)`** on **`aws_iam_role`**, shorten **`integration_identifier`** or **`port_org_slug`** and re-run **`terraform plan`**.

**`event_listener_type = "POLLING"`** matches [Port’s Terraform examples](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/installation): it controls scheduled sync with Port; it is **not** a substitute for live events (those use the ingress path above).

## Greenfield vs bring-your-own infrastructure

Terraform separates **optional account bootstrap** (network, CloudTrail) from the **Port Ocean stack** in [`main.tf`](terraform/main.tf) and from **state and CI** ([`terraform.tf`](terraform/terraform.tf), GitHub Actions). That split lets both **empty AWS accounts** and **accounts that already have networking or audit trails** use the same configuration.

| Area | What it is | Greenfield (defaults) | Bring your own |
|-------|------------|-------------------------|----------------|
| **Network** | VPC and subnets for ECS | [`network.tf`](terraform/network.tf) creates a VPC plus **public** subnets (see [`variables_network.tf`](terraform/variables_network.tf)). **`module.aws`** consumes **`data.aws_vpc`** / **`data.aws_subnets`** so subnet IDs are **read back** from AWS after create (see [Network discovery](#network-discovery-data-sources)). | Set **`network_use_existing_vpc = true`**, **`network_existing_vpc_id`**, and **`network_existing_subnet_ids`** (at least two subnets in different AZs); each subnet is checked against the VPC. Match **`assign_public_ip`** / **`network_enable_nat_gateway`** / **`network_private_subnet_cidrs`** to your layout (public subnets + **`assign_public_ip = true`** is the default bundle). |
| **CloudTrail + S3** | Logging so **live events** receive management API events via EventBridge | When **`allow_incoming_requests`** and **`cloudtrail_enabled`** are **`true`**, [`cloudtrail.tf`](terraform/cloudtrail.tf) creates a multi-Region trail and optionally a **managed** log bucket. | **`cloudtrail_enabled = false`** if the account already has a trail logging **management events** (see [Live events prerequisites](#live-events-prerequisites-cloudtrail)). **`cloudtrail_existing_log_bucket_name`** uses **your** bucket for the trail **this repo still creates**—Terraform attaches bucket policy; you still add a trail resource in AWS. |
| **Port Ocean integration** | ECS, ALB, API Gateway, EventBridge rules, SSM, IAM, etc. | [`main.tf`](terraform/main.tf) [`module "aws"`](terraform/main.tf) ([`aws_container_app`](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app)). | No separate variables to attach an **existing** ALB, API Gateway, or ECS service—the upstream module owns those resources. Fork or extend the module if you need that. |

**Bootstrap vs integration:** VPC and CloudTrail/S3 are **optional** when you already run equivalents (see table). **[`main.tf`](terraform/main.tf)** deploys the **integration runtime** (ECS, ingress, sync). **[`terraform.tf`](terraform/terraform.tf)** and **[`ensure-tfc-workspace`](https://github.com/gossamer-labs/gha-ensure-tfc-workspace)** handle **remote state and CI**—they are not AWS resources:

| Piece | Purpose |
|-------|---------|
| **[`terraform.tf`](terraform/terraform.tf) `cloud {}`** | Partial **Terraform Cloud** backend: set **`TF_CLOUD_ORGANIZATION`** and **`TF_WORKSPACE`** (environment variables) before **`terraform init`**. Port naming stays in **`port_org_slug`** / **`integration_identifier`**. |
| **GitHub Actions [`ensure-tfc-workspace`](https://github.com/gossamer-labs/gha-ensure-tfc-workspace)** | Ensures a Terraform Cloud workspace exists (**`TFC_ORGANIZATION`**, workspace name **`$TFC_WORKSPACE_SLUG-$ENVIRONMENT`**), **local** execution, and tags from **`TFC_WORKSPACE_TAGS`**. Skipped when workflow **`USE_TERRAFORM_CLOUD_BACKEND`** is **`false`**—see [GitHub Actions](#github-actions). |

**Workflow flag `USE_TERRAFORM_CLOUD_BACKEND`:** Defined in [`.github/workflows/port-integration-aws-onprem-tf.yml`](.github/workflows/port-integration-aws-onprem-tf.yml) (not a GitHub variable). After you switch to **S3 or local** state ([Without Terraform Cloud](#without-terraform-cloud)), set it to **`false`** so CI does **not** call the Terraform Cloud API or run **`ensure-tfc-workspace`**. Default is **`true`** (Terraform Cloud).

**Secrets:** **`TF_API_TOKEN`** is required for Terraform Cloud remote state and for **`ensure-tfc-workspace`**. If you use only S3/local backend and set **`USE_TERRAFORM_CLOUD_BACKEND=false`**, you may omit **`TF_API_TOKEN`** in CI for **`terraform init`** (configure AWS credentials for the S3 backend instead).

## Live events prerequisites (CloudTrail)

Port’s EventBridge rules match **`AWS API Call via CloudTrail`** on the **default** event bus. That requires an **active CloudTrail trail** logging **management events** (see [AWS: events via CloudTrail](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html)). **CloudTrail Event history** in the console can show recent APIs even when **no trail** exists; EventBridge rules stay at **zero invocations** until a trail is logging.

When **`allow_incoming_requests`** and **`cloudtrail_enabled`** are both **`true`**, this repo creates a **multi-Region** trail (management events, global service events), an **S3 log bucket** by default, and the bucket policy CloudTrail needs. Optional **`cloudtrail_existing_log_bucket_name`** uses your bucket instead; Terraform must be allowed to **`PutBucketPolicy`** on it.

**Managed trail and log bucket names:** trail **`{cloudtrail_name_prefix}-live-events`**, bucket **`{cloudtrail_name_prefix}-cloudtrail-logs-{aws_account_id}`** (see [`cloudtrail.tf`](terraform/cloudtrail.tf)). The trailing **12-digit segment is your AWS account ID** from the account Terraform deploys into—not a random suffix. That keeps the bucket name **globally unique** in S3 and ties it to the account. Change the prefix with **`cloudtrail_name_prefix`** (default **`port-exporter`**) in [`variables_cloudtrail.tf`](terraform/variables_cloudtrail.tf).

Expect **S3 storage** charges for log files and normal **CloudTrail** pricing beyond free-tier assumptions for trails. The managed log bucket uses an **S3 lifecycle rule** to expire current-version objects (default **365** days) and non-current versions (default **30** days); tune via **`cloudtrail_log_bucket_object_expiration_days`** and **`cloudtrail_log_bucket_noncurrent_version_expiration_days`** in [`variables_cloudtrail.tf`](terraform/variables_cloudtrail.tf).

**Security (managed log bucket):** [Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html), **bucket owner enforced** (no ACL reliance), **default SSE-S3 encryption**, **versioning** enabled, **TLS-only** access (`Deny` when `aws:SecureTransport` is false), CloudTrail **Put/Get** limited to this trail’s ARN, and **log file integrity validation** on the trail. For **`cloudtrail_existing_log_bucket_name`**, Terraform applies the same CloudTrail + TLS policy statements—you remain responsible for baseline bucket hardening (encryption defaults, blocking public access, retention/lifecycle, KMS if required by policy).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) **1.14.5+** (see [`terraform.tf`](terraform/terraform.tf))
- [HashiCorp Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) (optional): a **Terraform Cloud organization** and **workspace** you control. Set **`TF_CLOUD_ORGANIZATION`** and **`TF_WORKSPACE`** before **`terraform init`**, or use **`terraform login`** / **`TF_TOKEN_app_terraform_io`** (see [**Secrets**](#secrets--environment-variables-never-commit)). **Without Terraform Cloud:** comment out the **`cloud {}`** block in [`terraform.tf`](terraform/terraform.tf), then configure a **`backend`** (commented **`backend "s3"`** example in that file) or use local state—see [**Remote state**](#remote-state-terraform-cloud).
- AWS credentials able to create VPC, ECS, IAM, load balancing, **API Gateway**, **EventBridge** (rules), **Systems Manager Parameter Store** (integration secrets), **CloudTrail**, **S3** (log bucket), and related resources used by the [Ocean `aws_container_app` module](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app).
- **Port region:** default **`port_base_url`** is **`https://api.us.port.io`** in [`variables_integration.tf`](terraform/variables_integration.tf). Override in your varfile; use **`https://api.port.io`** for EU.

## AWS authentication

```bash
export AWS_PROFILE="my-sso-profile"   # replace with your profile name (quote if it contains spaces)
aws sso login --profile "$AWS_PROFILE"   # or your org’s auth flow
```

## Secrets — environment variables (never commit)

```bash
export TF_VAR_port_client_id="<Port client id>"
export TF_VAR_port_client_secret="<Port client secret>"
export TF_VAR_live_events_api_key="$(openssl rand -hex 32)"   # keep this value; store in GitHub as PORT_LIVE_EVENTS_API_KEY for CI
```

The live-events value is a **secret you define** (not an AWS credential). EventBridge sends it so the integration can validate webhook traffic — see [Port installation variables](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/installation).

**Terraform Cloud (local CLI)** — optional alternative to interactive `terraform login`. Use a user token from Terraform Cloud **Settings → Tokens** (new or existing). Same value as pasting at the `terraform login` prompt:

```bash
export TF_TOKEN_app_terraform_io="your-token-here"
```

**Terraform Cloud organization (partial `cloud {}`):** set the HashiCorp organization name Terraform should use (same value GitHub Actions stores as **`TFC_ORGANIZATION`**):

```bash
export TF_CLOUD_ORGANIZATION="<your-terraform-cloud-org>"
```

## Configuration layout

Files below cover **network bootstrap**, **CloudTrail**, the **Port Ocean** module, and outputs. For what is optional in mature accounts, see [Greenfield vs bring-your-own infrastructure](#greenfield-vs-bring-your-own-infrastructure). To remove a deployment, see [Teardown](#teardown).

| File | Purpose |
|------|---------|
| [`terraform.tf`](terraform/terraform.tf) | Terraform version, partial **`cloud {}`** (org/workspace via **`TF_CLOUD_ORGANIZATION`** / **`TF_WORKSPACE`**), AWS provider constraints |
| [`providers.tf`](terraform/providers.tf) | AWS provider; **`default_tags`** from **`default_resource_tags`** (set in your varfile; see [`variables_integration.tf`](terraform/variables_integration.tf)) |
| [`variables_network.tf`](terraform/variables_network.tf) | VPC / subnets (`network_*`), `aws_region` |
| [`variables_cloudtrail.tf`](terraform/variables_cloudtrail.tf) | CloudTrail + log bucket (`cloudtrail_*`), gated with live events |
| [`variables_integration.tf`](terraform/variables_integration.tf) | Port Ocean module inputs (`port_*`, **`port_org_slug`**, multi-account knobs, **`default_resource_tags`**, ECS) |
| [`environments/`](terraform/environments/) | Per-environment **`*.tfvars`** (start from [`example.tfvars`](terraform/environments/example.tfvars)). Pass **`-var-file=environments/<name>.tfvars`**. Optional gitignored overlays: **`environments/*.local.tfvars`**. |
| [`network.tf`](terraform/network.tf) | `terraform-aws-modules/vpc` (**v5.x**); **`data.aws_vpc`** / **`data.aws_subnets`** (managed) or **`data.aws_subnet`** (BYO) resolve IDs for **`module.aws`**. See [Network discovery](#network-discovery-data-sources). |
| [`cloudtrail.tf`](terraform/cloudtrail.tf) | Account CloudTrail + optional managed S3 log bucket (when live events on) |
| [`main.tf`](terraform/main.tf) | `module "aws"` — Port [`aws_container_app`](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app); config validation via **`terraform_data.integration_config_validation`**; explicit **`depends_on`** network data sources |
| [`live_event_resources.tf`](terraform/live_event_resources.tf) | Optional EventBridge rules **beyond** the upstream defaults (example: EKS cluster + node group). Webhook target ARN from **`data.aws_api_gateway_rest_api`**. See [Extending live EventBridge rules](#extending-live-eventbridge-rules). |
| [`outputs.tf`](terraform/outputs.tf) | VPC id, subnet ids, create mode, **`integration_identifier`**, **`live_events_webhook_url`** (when live events on), CloudTrail / log bucket (when created) |

### Network discovery (data sources)

[`terraform/network.tf`](terraform/network.tf) uses **vars only to create** the VPC (or to point at BYO IDs). **`module.aws`** receives **`vpc_id`** and **subnet IDs** from **read APIs** so the Port stack is not wired directly to **`module.vpc`** outputs:

- **Managed VPC:** after **`module.vpc`**, **`data.aws_vpc`** selects the VPC by **`tag:Name`** = **`network_vpc_name`**, and **`data.aws_subnets`** selects subnets in that VPC with **`map-public-ip-on-launch=true`** (the default public subnets from this VPC module). IDs are **sorted** for stability.
- **BYO VPC:** **`data.aws_vpc`** reads **`network_existing_vpc_id`**; each **`network_existing_subnet_ids`** entry is loaded with **`data.aws_subnet`** and a **postcondition** ensures the subnet belongs to that VPC.

If you later run ECS in **private** subnets from the **same** managed VPC, you will need a different discovery rule (for example a dedicated subnet tag); the default path matches **public subnets + `assign_public_ip = true`**.

### Multiple environments from one repo

Use **one GitHub Actions environment + one Terraform Cloud workspace + one varfile per environment** (different **`port_org_slug`** / **`integration_identifier`** / AWS account). CI sets **`ENVIRONMENT`** from the trigger (`integration` on PRs, `production` on push to **`main`**, or explicit choice on **`workflow_dispatch`**). That value must match:

- A GitHub environment name (Settings → Environments) holding **Variables** and **Secrets**
- **`terraform/environments/<ENVIRONMENT>.tfvars`**
- Terraform Cloud workspace **`$TFC_WORKSPACE_SLUG-$ENVIRONMENT`** (from environment variable **`TFC_WORKSPACE_SLUG`**)

The **`terraform`** job’s **`concurrency.group`** is keyed by **`ENVIRONMENT`** so parallel environments do not cancel each other.

### Live events webhook URL (Terraform output)

When **`allow_incoming_requests`** is **`true`**, **`terraform output live_events_webhook_url`** returns the **`POST /integration/webhook`** HTTPS URL. It is built from **`data.aws_api_gateway_rest_api`**, which reads the REST API by name (**`port_ocean_rest_api_name`**, default **`port-ocean-aws-exporter`**) **after** **`module.aws`** creates it—so you get a usable URL in **one apply** without referencing **`module.aws.module.api_gateway[0].…`** (blocked under Terraform **1.14+** typing for root modules).

You can still confirm the API in the console (**API Gateway → REST APIs**) or with **`terraform state show`** on nested resources if you prefer.

### Extending live EventBridge rules

The Port [`aws_container_app`](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app) module ships default live-event rules for **EC2**, **S3**, and **CloudFormation** (see [Supported resource types](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events#supported-resource-types)). Add more rules in **[`terraform/live_event_resources.tf`](terraform/live_event_resources.tf)** using the same [`aws_helpers/event`](https://github.com/port-labs/terraform-ocean-integration-factory/tree/main/modules/aws_helpers/event) pattern.

- **How to extend:** [Live events — Add other services](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events#add-other-services)
- **Which AWS services support live events:** [Supported AWS services](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events#supported-aws-services)

That file includes **examples** for **EKS clusters** (`AWS::EKS::Cluster`) and **EKS node groups** (`AWS::EKS::Nodegroup`); copy or edit them for other APIs and ensure your Port integration mappings cover the **`resource_type`** values you send.

Extension rules are created when **`allow_incoming_requests`** and **`live_events_api_key`** are both set. The EventBridge **target ARN** matches the upstream module (**`arn:aws:execute-api:…/production/POST/integration/webhook`**) and is derived from **`data.aws_api_gateway_rest_api`** with **`depends_on = [module.aws]`** (same **single apply** as the default rules). If you fork upstream and change the REST API **name**, set **`port_ocean_rest_api_name`** in your varfile (see [`variables_integration.tf`](terraform/variables_integration.tf)).

## Remote state (Terraform Cloud)

This repo uses a **partial** [`terraform.tf`](terraform/terraform.tf) **`cloud {}`** block. Before **`terraform init`**, set:

- **`TF_CLOUD_ORGANIZATION`** — your Terraform Cloud organization name (same as GitHub Variable **`TFC_ORGANIZATION`** in CI).
- **`TF_WORKSPACE`** — the workspace **name** (CI default: **`$TFC_WORKSPACE_SLUG-$ENVIRONMENT`**; override with dispatch **`tf_workspace`**).

There is **no** `cloud { workspaces { tags = [...] } }` selector in-repo; each install picks an explicit workspace name via environment / CI variables.

**Migrating from an older checkout:** If **`terraform init`** was run when **`terraform.tf`** pinned a Terraform Cloud **organization** and **tag-based** workspace selection, run **`terraform init -reconfigure`** after pulling this change (or delete **`.terraform/terraform.tfstate`** under **`.terraform/`** if present), then set **`TF_CLOUD_ORGANIZATION`** and **`TF_WORKSPACE`** before the next **`init`**.

### Without Terraform Cloud

1. In [`terraform.tf`](terraform/terraform.tf), **comment out** the entire **`cloud { ... }`** block (Terraform allows only one backend configuration).
2. Uncomment and fill in the **`backend "s3"`** example in the same file, **or** omit a backend to use **local** state (`terraform.tfstate` in the working directory).
3. Run **`terraform init -migrate-state`** if you are switching an existing workspace.
4. In the workflow YAML: set **`USE_TERRAFORM_CLOUD_BACKEND`** to **`false`** so Actions skips **`ensure-tfc-workspace`** (see [Greenfield vs bring-your-own](#greenfield-vs-bring-your-own-infrastructure)). **`TF_API_TOKEN`** may be unnecessary for **`terraform init`** if state is not stored in Terraform Cloud.

**Selecting a workspace (non-interactive):** set **`TF_WORKSPACE`** to the workspace **name** (same string as GitHub Actions `workflow_dispatch` → **`tf_workspace`**).

**Terraform Cloud API token:** run **`terraform login`** once, or set **`TF_TOKEN_app_terraform_io`** (see [**Secrets**](#secrets--environment-variables-never-commit)) — equivalent to storing the token from the login flow.

Example:

```bash
export TF_CLOUD_ORGANIZATION=my-org
export TF_WORKSPACE=my-team-port-aws
export TF_TOKEN_app_terraform_io="your-token-here"   # or run `terraform login` instead
cd terraform && terraform init
```

With **`TF_CLOUD_ORGANIZATION`** and **`TF_WORKSPACE`** set, **`terraform init`** targets that single workspace (no tag-based picker).

## GitHub Actions

Workflow [`.github/workflows/port-integration-aws-onprem-tf.yml`](.github/workflows/port-integration-aws-onprem-tf.yml):

| Trigger | `ENVIRONMENT` | Behavior |
|--------|---------------|----------|
| **Pull request** (paths `terraform/**` or this workflow) | **`integration`** | **`terraform` job:** `terraform fmt -check`, **`terraform plan -var-file=$TFVAR_FILE`** (after **`format`**). Same-repo PRs only (fork PRs skip Terraform). |
| **Push to `main`** (same paths) | **`production`** | **`terraform apply -var-file=$TFVAR_FILE`**. Restrict **`production`** deployments to **`main`** via GitHub environment protection rules. |
| **`workflow_dispatch`** | **Required input** (`integration` or `production`) | **`format`** then **`terraform`:** choose **plan** / **apply** / **destroy** and target environment. |

**`ENVIRONMENT`** is never a GitHub variable — the pipeline sets it from the trigger. It must align with a GitHub environment name, **`terraform/environments/<name>.tfvars`**, and TFC workspace **`$TFC_WORKSPACE_SLUG-<name>`**.

Before opening a PR that changes files under `terraform/`, run `terraform fmt -recursive` from the `terraform/` directory so the CI **format** check passes.

Manual **Run workflow** requires selecting **environment** (no default). Per-environment **Variables** and **Secrets** are not shown in the dispatch form (GitHub limitation).

A **Validate inputs** step fails fast if required environment **Variables** are missing or the varfile does not exist. **`TF_CLOUD_ORGANIZATION`** comes from **`TFC_ORGANIZATION`** in the selected GitHub environment.

When workflow **`USE_TERRAFORM_CLOUD_BACKEND`** is **`true`** (default), [**`ensure-tfc-workspace`**](https://github.com/gossamer-labs/gha-ensure-tfc-workspace) runs before **`terraform init`**. Workspace name defaults to **`${TFC_WORKSPACE_SLUG}-${ENVIRONMENT}`**. Set **`USE_TERRAFORM_CLOUD_BACKEND=false`** in the workflow YAML after switching to S3/local backend.

### Architectural flags (workflow YAML only)

Edit [`.github/workflows/port-integration-aws-onprem-tf.yml`](.github/workflows/port-integration-aws-onprem-tf.yml) — not GitHub Variables:

| Flag | Default | Purpose |
|------|---------|---------|
| **`USE_TERRAFORM_CLOUD_BACKEND`** | **`true`** | Terraform Cloud state vs S3/local |
| **`USE_AWS_STATIC_CREDENTIALS`** | **`false`** | Static AWS keys vs OIDC (independent of backend) |

All four combinations are valid; see comments in the workflow file.

### GitHub Actions: OIDC vs static AWS credentials

- **OIDC (default):** assumes **`arn:aws:iam::<AWS_ACCOUNT_ID>:role/<AWS_ROLE_NAME>`** from the selected environment’s **Variables**, with optional **`workflow_dispatch`** overrides. See [**CI: AssumeRoleWithWebIdentity**](#ci-assumerolewithwebidentity--oidc-denied).
- **Static keys:** set workflow **`USE_AWS_STATIC_CREDENTIALS`** to **`true`** and add **`AWS_ACCESS_KEY_ID`** / **`AWS_SECRET_ACCESS_KEY`** as **secrets** on each GitHub environment.

**Per-environment variables** (Settings → Environments → **`<name>`** → Environment variables)

| Variable | Purpose |
|----------|---------|
| **`TFC_ORGANIZATION`** | Terraform Cloud organization (feeds **`TF_CLOUD_ORGANIZATION`**). If shared across all envs, you could promote this to a repo variable instead. |
| **`TFC_WORKSPACE_SLUG`** | Base workspace name; CI sets **`TF_WORKSPACE`** to **`$TFC_WORKSPACE_SLUG-$ENVIRONMENT`**. |
| **`TFC_WORKSPACE_TAGS`** | Tags for **`ensure-tfc-workspace`**. |
| **`AWS_REGION`** | Region for **`configure-aws-credentials`**; align with **`aws_region`** in your varfile. |
| **`AWS_ACCOUNT_ID`** | Account ID for OIDC role ARN. |
| **`AWS_ROLE_NAME`** | IAM role name for GitHub OIDC. |
| **`PORT_CLIENT_ID`** | `TF_VAR_port_client_id` (not sensitive). |

**Per-environment secrets** (Settings → Environments → **`<name>`** → Environment secrets)

| Secret | Purpose |
|--------|---------|
| `TF_API_TOKEN` | Terraform Cloud API token and **`ensure-tfc-workspace`**. |
| `PORT_CLIENT_SECRET` | `TF_VAR_port_client_secret` |
| `PORT_LIVE_EVENTS_API_KEY` | `TF_VAR_live_events_api_key` |
| `AWS_ACCESS_KEY_ID` | (Optional) When **`USE_AWS_STATIC_CREDENTIALS=true`** |
| `AWS_SECRET_ACCESS_KEY` | (Optional) When **`USE_AWS_STATIC_CREDENTIALS=true`** |

If **`PORT_LIVE_EVENTS_API_KEY`** is missing, live-events webhook validation is not configured — see prior note in this section.

**Dispatch** can override **`tf_workspace`** (full workspace name), **`tfvar_file`** (varfile path), and **`AWS_*`** inputs when non-empty. Default varfile is **`environments/$ENVIRONMENT.tfvars`**.

**Apply on `main`:** runs against **`production`** only (path filter + **`ENVIRONMENT=production`**). Use branch and environment protection as needed.

### CI: `AssumeRoleWithWebIdentity` / OIDC denied

If **`configure-aws-credentials`** fails with **`Not authorized to perform sts:AssumeRoleWithWebIdentity`**, the GitHub OIDC token is valid but the **IAM role trust policy** does not allow **this repository**. Common after adding a new repo: the role still trusts only another repo’s **`sub`** claim.

1. Confirm **`repository`** and **`role-to-assume`** in the workflow log/summary match what you intend.
2. In AWS IAM → **Roles** → that role → **Trust relationships**, ensure **`token.actions.githubusercontent.com`** includes a condition that matches this repo, for example:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:<github-org-or-user>/<repo-name>:*"
    }
  }
}
```

Adjust account ID, repo slug, or **`aud`** if your org differs. The **`terraform`** job sets **`permissions: id-token: write`** for OIDC.

## Teardown

Remove AWS resources created by this Terraform configuration, then clean up Port and optional cloud state as needed.

### AWS — `terraform destroy`

1. Run the workflow [`.github/workflows/port-integration-aws-onprem-tf.yml`](.github/workflows/port-integration-aws-onprem-tf.yml) via **`workflow_dispatch`** with **`mode: destroy`** and the target **environment**. Leave optional inputs blank to use that environment’s **Variables** / **Secrets**, or set the same overrides you use for apply.
2. With **Terraform Cloud** remote state, **`ensure-tfc-workspace`** runs unless **`USE_TERRAFORM_CLOUD_BACKEND=false`**; destroy expects the workspace to exist in that path. If you use **S3 or local** state and **`USE_TERRAFORM_CLOUD_BACKEND=false`**, CI skips workspace ensure but still runs **`terraform destroy`** when dispatching destroy—see [Greenfield vs bring-your-own infrastructure](#greenfield-vs-bring-your-own-infrastructure) and [GitHub Actions](#github-actions).
3. If **`terraform destroy`** fails because **S3 will not delete a bucket that still has contents** (common error: bucket not empty), fix the bucket and **re-run destroy** until it completes:
   - **Managed CloudTrail log bucket** (when this stack created CloudTrail for live events): the bucket name follows **`{cloudtrail_name_prefix}-cloudtrail-logs-<aws_account_id>`** (see [Live events prerequisites](#live-events-prerequisites-cloudtrail)). While the stack still exists, **`terraform output cloudtrail_log_bucket_name`** shows the exact name. This repo enables **S3 versioning** on that bucket, so you must remove **current objects, all versions, and delete markers**—use the S3 console **Empty** action (including versions), or equivalent CLI/API—then run **`terraform destroy`** again. Often the first **`destroy`** already removes the trail and policies; if it stops on **`aws_s3_bucket`**, empty the bucket and re-run.
   - Any other S3 bucket the configuration manages: same **must be empty** (including versioned objects if versioning is on) before AWS allows deletion.

### Port — integration registration

**Terraform does not delete the integration entry in Port.** After AWS destroy succeeds, **remove or disconnect the integration** in the Port product (UI or API) if you no longer want it listed.

### Optional cleanup

- **Terraform Cloud:** the **workspace** and **state history** remain until you delete the workspace in Terraform Cloud if you no longer need them.
- **Catalog:** blueprints, mappings, or entities created in Port (for example when **`initialize_port_resources`** was **`true`**) may persist there independently of AWS—review [Port documentation](https://docs.port.io/) for your catalog hygiene process.

## Run locally

Authenticate to AWS first so the Terraform AWS provider can reach your account (for example **`export AWS_PROFILE="my-sso-profile"`** then **`aws sso login --profile "$AWS_PROFILE"`** if you use IAM Identity Center — replace **`my-sso-profile`** with your profile; otherwise use [**AWS authentication**](#aws-authentication) above). Leave **`AWS_PROFILE`** exported so Terraform uses the same credentials.

For **Terraform Cloud** remote state, authenticate with **`export TF_TOKEN_app_terraform_io="..."`** or **`terraform login`** before **`terraform init`** (see [**Secrets**](#secrets--environment-variables-never-commit)).

```bash
export AWS_PROFILE="my-sso-profile"   # replace with your profile name (quote if it contains spaces)
aws sso login --profile "$AWS_PROFILE"   # or your org’s AWS credential flow
cd terraform
export TF_CLOUD_ORGANIZATION="<your-terraform-cloud-org>"
export TF_WORKSPACE="<your-tfc-workspace-name>"
export TFVAR_FILE="environments/<your-environment>.tfvars"
export AWS_DEFAULT_REGION="<same-as-aws_region-in-your-varfile>"   # see terraform/environments/example.tfvars
export TF_VAR_port_client_id="..."
export TF_VAR_port_client_secret="..."
export TF_VAR_live_events_api_key="..."   # same random secret as in CI / openssl rand -hex 32
export TF_TOKEN_app_terraform_io="your-token-here"   # optional; or run `terraform login` instead
terraform init -input=false
terraform plan -input=false -var-file="$TFVAR_FILE"
terraform apply -input=false -var-file="$TFVAR_FILE"
```

## Verifying live events

After apply, confirm the pipeline end-to-end:

1. **Webhook URL** — run **`terraform output live_events_webhook_url`** when **`allow_incoming_requests`** is **`true`** (see [Live events webhook URL](#live-events-webhook-url-terraform-output)).
2. **EventBridge** — open **EventBridge → Rules** for rules created by the Port module; **Invocations** should increase after you create or change a supported resource (e.g. S3 bucket) *if* [CloudTrail is delivering management events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html) (this repo enables a trail by default when live events are on).
3. **Integration** — in Port, open the integration’s **event logs** / metrics if issues persist; check **CloudWatch** logs for the ECS task.
4. **Catalog** — ensure your [integration mapping](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/installation) includes the resource kind you expect (e.g. `AWS::S3::Bucket` for buckets).

## First-time checklist

- **AWS:** Ensure credentials target the same region as **`aws_region`** in your varfile before **`terraform plan`** / **`apply`**.
- **AWS / GitHub:** Create GitHub environments (e.g. **`integration`**, **`production`**) and set per-environment **Variables** / **Secrets** listed in [GitHub Actions](#github-actions). Copy **`environments/example.tfvars`** to **`environments/<name>.tfvars`** for each environment.
- **Port org slug:** Set **`port_org_slug`** in your **`environments/<name>.tfvars`** (required; no default in code). The Port integration identifier becomes **`onprem-tf-<port_org_slug>`** unless you set **`integration_identifier`**. Long slugs can push upstream IAM role **names** over AWS’s **64-character** limit—see [IAM role name length](#iam-role-name-length-integration-naming).
- **Secrets / CI:** Export **`TF_VAR_*`** locally; configure **`PORT_CLIENT_ID`** (variable), **`PORT_CLIENT_SECRET`**, **`PORT_LIVE_EVENTS_API_KEY`**, and **`TF_API_TOKEN`** on each GitHub environment. For Terraform Cloud, set **`TF_CLOUD_ORGANIZATION`** + **`TF_WORKSPACE`** (workspace name **`$TFC_WORKSPACE_SLUG-$ENVIRONMENT`** in CI).
- **Port:** Confirm **`port_base_url`** matches your Port region (US `api.us.port.io` vs EU `api.port.io`).
- **Network:** If CIDR **`10.48.0.0/16`** overlaps another VPC or peered network, change `network_vpc_cidr` and `network_public_subnet_cidrs` together in your varfile.
- **ECS networking:** **`assign_public_ip = true`** matches **public subnets + no NAT** (default bundle). For private subnets + NAT, set `network_private_subnet_cidrs`, `network_enable_nat_gateway = true`, and `assign_public_ip = false`.
- **Image tag:** Omit **`integration_version`** in your varfile to use the upstream default (`latest`), or set a concrete tag after you confirm one from the running task / registry for reproducible deploys.
- Commit [`.terraform.lock.hcl`](terraform/.terraform.lock.hcl); regenerate with `terraform providers lock` when upgrading providers.

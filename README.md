# port-integration-aws-on-prem-tf-live

Port **AWS** integration on **ECS** with **Terraform**, **Terraform Cloud** remote state, and **live events** (EventBridge → API Gateway → integration webhook) in one deployment path.

Configuration lives under [`terraform/`](terraform/). The stack **creates a small VPC** by default (see [`network.tf`](terraform/network.tf), [`variables_network.tf`](terraform/variables_network.tf)) so you can deploy without hand-picking subnet IDs. To attach to an **existing** VPC later, set `network_use_existing_vpc = true` and fill `network_existing_vpc_id` / `network_existing_subnet_ids`.

[`terraform.tfvars`](terraform/terraform.tfvars) enables **`allow_incoming_requests = true`** so Terraform provisions ALB, API Gateway, and EventBridge for live events. Per [Port live events](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/live-events), live events are **single-account only**; multi-account setups need a separate design ([multi-account guide](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/multi_account)).

**Integration identifier:** set **`organization`** in [`terraform.tfvars`](terraform/terraform.tfvars) (default `gossamer-labs`). The Port integration identifier is **`aws-on-prem-tf-live-<organization>`** unless you override **`integration_identifier`** explicitly in Terraform.

**`event_listener_type = "POLLING"`** matches [Port’s Terraform examples](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/installation): it controls scheduled sync with Port; it is **not** a substitute for live events (those use the ingress path above).

## Live events prerequisites (CloudTrail)

Port’s EventBridge rules match **`AWS API Call via CloudTrail`** on the **default** event bus. That requires an **active CloudTrail trail** logging **management events** (see [AWS: events via CloudTrail](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html)). **CloudTrail Event history** in the console can show recent APIs even when **no trail** exists; EventBridge rules stay at **zero invocations** until a trail is logging.

When **`allow_incoming_requests`** and **`cloudtrail_enabled`** are both **`true`**, this repo creates a **multi-Region** trail (management events, global service events), an **S3 log bucket** by default, and the bucket policy CloudTrail needs. Optional **`cloudtrail_existing_log_bucket_name`** uses your bucket instead; Terraform must be allowed to **`PutBucketPolicy`** on it.

Expect **S3 storage** charges for log files and normal **CloudTrail** pricing beyond free-tier assumptions for trails. The managed log bucket uses an **S3 lifecycle rule** to expire current-version objects (default **365** days) and non-current versions (default **30** days); tune via **`cloudtrail_log_bucket_object_expiration_days`** and **`cloudtrail_log_bucket_noncurrent_version_expiration_days`** in [`variables_cloudtrail.tf`](terraform/variables_cloudtrail.tf).

**Security (managed log bucket):** [Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html), **bucket owner enforced** (no ACL reliance), **default SSE-S3 encryption**, **versioning** enabled, **TLS-only** access (`Deny` when `aws:SecureTransport` is false), CloudTrail **Put/Get** limited to this trail’s ARN, and **log file integrity validation** on the trail. For **`cloudtrail_existing_log_bucket_name`**, Terraform applies the same CloudTrail + TLS policy statements—you remain responsible for baseline bucket hardening (encryption defaults, blocking public access, retention/lifecycle, KMS if required by policy).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) **1.14.5+** (see [`terraform.tf`](terraform/terraform.tf))
- [HashiCorp Terraform Cloud](https://developer.hashicorp.com/terraform/cloud-docs) access to organization **`gossamer-labs`**, workspace tag **`port-integration-aws-on-prem-tf-live`**. Authenticate the CLI with **`terraform login`** or **`export TF_TOKEN_app_terraform_io="..."`** (see [**Secrets**](#secrets--environment-variables-never-commit)). **Without Terraform Cloud:** comment out the **`cloud {}`** block in [`terraform.tf`](terraform/terraform.tf), then configure a **`backend`** (commented **`backend "s3"`** example in that file) or use local state—see [**Remote state**](#remote-state-terraform-cloud).
- AWS credentials able to create VPC, ECS, IAM, load balancing, **API Gateway**, **EventBridge** (rules), **Systems Manager Parameter Store** (integration secrets), **CloudTrail**, **S3** (log bucket), and related resources used by the [Ocean `aws_container_app` module](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app).
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
export TF_VAR_live_events_api_key="$(openssl rand -hex 32)"   # keep this value; store in GitHub as PORT_LIVE_EVENTS_API_KEY for CI
```

The live-events value is a **secret you define** (not an AWS credential). EventBridge sends it so the integration can validate webhook traffic — see [Port installation variables](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/installation).

**Terraform Cloud (local CLI)** — optional alternative to interactive `terraform login`. Use a user token from Terraform Cloud **Settings → Tokens** (new or existing). Same value as pasting at the `terraform login` prompt:

```bash
export TF_TOKEN_app_terraform_io="your-token-here"
```

## Configuration layout

| File | Purpose |
|------|---------|
| [`terraform.tf`](terraform/terraform.tf) | Terraform version, **Terraform Cloud** org `gossamer-labs`, workspace tag **`port-integration-aws-on-prem-tf-live`**, AWS provider constraints |
| [`providers.tf`](terraform/providers.tf) | AWS provider; **`default_tags`** (`Environment`, `ManagedBy`, `Project`, `Repository`) |
| [`variables_network.tf`](terraform/variables_network.tf) | VPC / subnets (`network_*`), `aws_region` |
| [`variables_cloudtrail.tf`](terraform/variables_cloudtrail.tf) | CloudTrail + log bucket (`cloudtrail_*`), gated with live events |
| [`variables_integration.tf`](terraform/variables_integration.tf) | Port Ocean module inputs (`port_*`, **`organization`**, integration, ECS) |
| [`network.tf`](terraform/network.tf) | `terraform-aws-modules/vpc` (**v5.x**, pairs with Port module’s AWS provider **5.x**) |
| [`cloudtrail.tf`](terraform/cloudtrail.tf) | Account CloudTrail + optional managed S3 log bucket (when live events on) |
| [`main.tf`](terraform/main.tf) | `module "aws"` — Port [`aws_container_app`](https://registry.terraform.io/modules/port-labs/integration-factory/ocean/latest/examples/aws_container_app) |
| [`outputs.tf`](terraform/outputs.tf) | VPC id, subnet ids, create mode, **`integration_identifier`**, **`live_events_webhook_url`**, CloudTrail / log bucket (when created) |
| [`terraform.tfvars`](terraform/terraform.tfvars) | Non-secret defaults (`organization`, `aws_region`, **`allow_incoming_requests`**, etc.) |

## Remote state (Terraform Cloud)

Organization **`gossamer-labs`**. Workspaces that carry tag **`port-integration-aws-on-prem-tf-live`** are eligible for this configuration ([`terraform.tf`](terraform/terraform.tf) `cloud.workspaces.tags`).

### Without Terraform Cloud

1. In [`terraform.tf`](terraform/terraform.tf), **comment out** the entire **`cloud { ... }`** block (Terraform allows only one backend configuration).
2. Uncomment and fill in the **`backend "s3"`** example in the same file, **or** omit a backend to use **local** state (`terraform.tfstate` in the working directory).
3. Run **`terraform init -migrate-state`** if you are switching an existing workspace.

**Selecting a workspace (non-interactive):** set **`TF_WORKSPACE`** to the workspace **name** (same string as GitHub Actions `workflow_dispatch` → **`tf_workspace`**).

**Terraform Cloud API token:** run **`terraform login`** once, or set **`TF_TOKEN_app_terraform_io`** (see [**Secrets**](#secrets--environment-variables-never-commit)) — equivalent to storing the token from the login flow.

Example:

```bash
export TF_WORKSPACE=my-team-port-aws
export TF_TOKEN_app_terraform_io="your-token-here"   # or run `terraform login` instead
cd terraform && terraform init
```

Without **`TF_WORKSPACE`**, `terraform init` may prompt you to pick one workspace among those matching the tag.

## GitHub Actions

Workflow [`.github/workflows/port-integration-aws-on-prem-tf-live.yml`](.github/workflows/port-integration-aws-on-prem-tf-live.yml):

| Trigger | Behavior |
|--------|----------|
| **Pull request** (paths `terraform/**` or this workflow) | **`terraform` job:** `terraform fmt -check`, **`terraform plan`** (after **`format`** job). Same-repo PRs only (fork PRs skip Terraform; secrets/OIDC are unavailable). |
| **Push to `main`** (same paths) | **`terraform` job:** **`terraform apply`** (runs after merge to trunk). |
| **`workflow_dispatch`** | **`format`** then **`terraform` job:** choose **plan** / **apply** / **destroy** and supply **`tf_workspace`**, **`aws_region`**, **`aws_account_id`**, **`aws_role_name`** (defaults match repository variables below). |

On every **`terraform`** run, [**`ensure-tfc-workspace`**](.github/actions/ensure-tfc-workspace/action.yml) runs first (for **plan**/**apply**, creates the workspace when missing; **destroy** requires an existing workspace). Applies tag **`port-integration-aws-on-prem-tf-live`**, **local** execution mode.

### GitHub Actions: OIDC vs static AWS credentials

- **OIDC (default):** the workflow assumes **`arn:aws:iam::<AWS_ACCOUNT_ID>:role/<AWS_ROLE_NAME>`**, built from repository variables **`AWS_ACCOUNT_ID`** (default **`936835732720`**) and **`AWS_ROLE_NAME`** (default **`github-actions-deploy`**), or from **`workflow_dispatch`** inputs. Ensure your IAM role trust policy allows this repository — see [**CI: AssumeRoleWithWebIdentity**](#ci-assumerolewithwebidentity--oidc-denied).
- **Static keys:** set repository variable **`AWS_USE_STATIC_CREDENTIALS`** to **`true`** and add secrets **`AWS_ACCESS_KEY_ID`** and **`AWS_SECRET_ACCESS_KEY`**. The OIDC steps are skipped; use least-privilege IAM users and rotate keys regularly.

**Repository variables** (Settings → Secrets and variables → Actions → **Variables** — optional for PR / `main`; **`workflow_dispatch`** can override with inputs)

| Variable | Purpose |
|----------|---------|
| **`TFC_WORKSPACE`** | Terraform Cloud **workspace name** (must match a workspace tagged **`port-integration-aws-on-prem-tf-live`**). Optional for PR / **`main`**; workflow defaults to **`port-integration-aws-on-prem-tf-live`** if unset. |
| **`AWS_REGION`** | AWS region for AWS credentials (optional; defaults to **`us-east-2`** in the workflow). Must match **`aws_region`** in [`terraform.tfvars`](terraform/terraform.tfvars). |
| **`AWS_ACCOUNT_ID`** | AWS account ID used to build the OIDC role ARN `arn:aws:iam::<id>:role/<name>` (optional; defaults to **`936835732720`**). |
| **`AWS_ROLE_NAME`** | IAM role **name** for GitHub OIDC (optional; defaults to **`github-actions-deploy`**). |
| **`AWS_USE_STATIC_CREDENTIALS`** | Set to **`true`** to use **`AWS_ACCESS_KEY_ID`** / **`AWS_SECRET_ACCESS_KEY`** secrets instead of OIDC (optional; default is OIDC). |

**Repository secrets** (Settings → Secrets and variables → Actions → **Secrets** — use **Secrets**, not **Variables**)

| Secret | Purpose |
|--------|---------|
| `TF_API_TOKEN` | Terraform Cloud API token |
| `PORT_CLIENT_ID` | `TF_VAR_port_client_id` |
| `PORT_CLIENT_SECRET` | `TF_VAR_port_client_secret` |
| `PORT_LIVE_EVENTS_API_KEY` | Same value as **`TF_VAR_live_events_api_key`** (e.g. from `openssl rand -hex 32`); wired to Terraform as **`TF_VAR_live_events_api_key`** |
| `AWS_ACCESS_KEY_ID` | (Optional) Static AWS access key when **`AWS_USE_STATIC_CREDENTIALS`** is **`true`** |
| `AWS_SECRET_ACCESS_KEY` | (Optional) Static AWS secret key when **`AWS_USE_STATIC_CREDENTIALS`** is **`true`** |

If **`PORT_LIVE_EVENTS_API_KEY`** is missing or empty in GitHub Actions, **`TF_VAR_live_events_api_key`** is not set. Terraform then passes **`integration.config` without `live_events_api_key`** (see [`main.tf`](terraform/main.tf)) even though **`allow_incoming_requests = true`** — **`terraform plan` / `apply` may still succeed**, but live-events webhook validation is **not** configured. Always define **`PORT_LIVE_EVENTS_API_KEY`** for CI.

**Dispatch** supplies **`TF_WORKSPACE`** via **`tf_workspace`**. **PR / `main`** use **`vars.TFC_WORKSPACE`** when set (optional **`vars.AWS_REGION`**, **`vars.AWS_ACCOUNT_ID`**, **`vars.AWS_ROLE_NAME`**); workspace name falls back to **`port-integration-aws-on-prem-tf-live`** to match workflow **`env.TF_WORKSPACE`** defaults. The AWS region should match **`aws_region`** in [`terraform.tfvars`](terraform/terraform.tfvars); Terraform still reads **`var.aws_region`** from tfvars for the provider.

**Apply on `main`:** any **push** to **`main`** that matches the path filter runs **apply** (including direct pushes, not only merges). Restrict merges via branch protection if needed.

### CI: `AssumeRoleWithWebIdentity` / OIDC denied

If **`configure-aws-credentials`** fails with **`Not authorized to perform sts:AssumeRoleWithWebIdentity`**, the GitHub OIDC token is valid but the **IAM role trust policy** does not allow **this repository**. Common after adding a new repo: the role still trusts only another repo’s **`sub`** claim.

1. Confirm **`repository`** and **`role-to-assume`** in the workflow log/summary match what you intend.
2. In AWS IAM → **Roles** → that role → **Trust relationships**, ensure **`token.actions.githubusercontent.com`** includes a condition that matches this repo, for example:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::936835732720:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:gossamer-labs/port-integration-aws-on-prem-tf-live:*"
    }
  }
}
```

Adjust account ID, repo slug, or **`aud`** if your org differs. The **`terraform`** job sets **`permissions: id-token: write`** for OIDC.

## Run locally

Authenticate to AWS first so the Terraform AWS provider can reach your account (for example **`export AWS_PROFILE="my-sso-profile"`** then **`aws sso login --profile "$AWS_PROFILE"`** if you use IAM Identity Center — replace **`my-sso-profile`** with your profile; otherwise use [**AWS authentication**](#aws-authentication) above). Leave **`AWS_PROFILE`** exported so Terraform uses the same credentials.

For **Terraform Cloud** remote state, authenticate with **`export TF_TOKEN_app_terraform_io="..."`** or **`terraform login`** before **`terraform init`** (see [**Secrets**](#secrets--environment-variables-never-commit)).

```bash
export AWS_PROFILE="my-sso-profile"   # replace with your profile name (quote if it contains spaces)
aws sso login --profile "$AWS_PROFILE"   # or your org’s AWS credential flow
cd terraform
export AWS_DEFAULT_REGION=us-east-2   # same value as aws_region in terraform.tfvars
export TF_WORKSPACE=<your-tfc-workspace-name>   # optional but avoids init prompts
export TF_VAR_port_client_id="..."
export TF_VAR_port_client_secret="..."
export TF_VAR_live_events_api_key="..."   # same random secret as in CI / openssl rand -hex 32
export TF_TOKEN_app_terraform_io="your-token-here"   # optional; or run `terraform login` instead
terraform init
terraform plan
terraform apply
```

## Verifying live events

After apply, confirm the pipeline end-to-end:

1. **Terraform output** — run **`terraform output live_events_webhook_url`**; you should see the API Gateway URL for **`POST /integration/webhook`** (EventBridge target).
2. **EventBridge** — open **EventBridge → Rules** for rules created by the Port module; **Invocations** should increase after you create or change a supported resource (e.g. S3 bucket) *if* [CloudTrail is delivering management events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html) (this repo enables a trail by default when live events are on).
3. **Integration** — in Port, open the integration’s **event logs** / metrics if issues persist; check **CloudWatch** logs for the ECS task.
4. **Catalog** — ensure your [integration mapping](https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/cloud-providers/aws/installations/installation) includes the resource kind you expect (e.g. `AWS::S3::Bucket` for buckets).

## First-time checklist

- **AWS:** Ensure credentials target **`us-east-2`** (matches [`terraform.tfvars`](terraform/terraform.tfvars)) before `terraform plan` / `apply`.
- **AWS / GitHub:** Set repository variables **`AWS_ACCOUNT_ID`** and optionally **`AWS_ROLE_NAME`** to match the IAM role used for OIDC (defaults match this repo’s example). For static credentials, set **`AWS_USE_STATIC_CREDENTIALS=true`** and add **`AWS_ACCESS_KEY_ID`** / **`AWS_SECRET_ACCESS_KEY`** secrets.
- **Organization:** Set **`organization`** in [`terraform.tfvars`](terraform/terraform.tfvars) if you are not using the default; the Port integration identifier becomes **`aws-on-prem-tf-live-<organization>`** unless you set **`integration_identifier`** in Terraform.
- **Secrets / CI:** Export **`TF_VAR_port_client_id`**, **`TF_VAR_port_client_secret`**, and **`TF_VAR_live_events_api_key`** locally; add **`TF_API_TOKEN`**, **`PORT_CLIENT_ID`**, **`PORT_CLIENT_SECRET`**, and **`PORT_LIVE_EVENTS_API_KEY`** as **repository secrets** (Settings → Secrets and variables → Actions → **Secrets**). Omitting **`PORT_LIVE_EVENTS_API_KEY`** in CI skips passing **`live_events_api_key`** into Terraform — see GitHub Actions secrets note above. Optionally set repository **Variables** **`TFC_WORKSPACE`** (and **`AWS_REGION`** / **`AWS_ACCOUNT_ID`** / **`AWS_ROLE_NAME`**) for **PR plan** and **`main` apply** — defaults match the workflow if omitted. For local Terraform Cloud auth, use **`terraform login`** or **`TF_TOKEN_app_terraform_io`** (see [**Secrets**](#secrets--environment-variables-never-commit)).
- **Port:** Confirm **`port_base_url`** matches your Port region (US `api.us.port.io` vs EU `api.port.io`).
- **Network:** If CIDR **`10.48.0.0/16`** overlaps another VPC or peered network, change `network_vpc_cidr` and `network_public_subnet_cidrs` together.
- **ECS networking:** **`assign_public_ip = true`** matches **public subnets + no NAT** (default bundle). For private subnets + NAT, set `network_private_subnet_cidrs`, `network_enable_nat_gateway = true`, and `assign_public_ip = false`.
- **Image tag:** Omit **`integration_version`** in `terraform.tfvars` to use the upstream default (`latest`), or set a concrete tag after you confirm one from the running task / registry for reproducible deploys.
- Commit [`.terraform.lock.hcl`](terraform/.terraform.lock.hcl); regenerate with `terraform providers lock` when upgrading providers.

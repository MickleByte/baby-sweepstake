# AWS bootstrap

Before CI can deploy anything, an AWS account needs a few things that CI can't create for itself: somewhere to keep Terraform state, a way for GitHub Actions to sign in without stored keys, and a role for it to sign in as. The Terraform stack in [`infra/bootstrap`](../../infra/bootstrap) creates them. You run it **once, from your own machine, with admin credentials**, and again only when the deploy role's permissions need to change.

It creates:

| Resource                                           | Why                                                                                                     |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| S3 bucket `baby-sweepstake-tfstate-<account id>`   | Terraform state for every other stack. Versioned, encrypted, private, HTTPS only.                       |
| IAM OIDC identity provider for GitHub Actions      | Lets workflows exchange a GitHub-issued token for AWS credentials, so no AWS keys are stored in GitHub. |
| IAM role `baby-sweepstake-github-deploy`           | What CI signs in as. Only workflows in `MickleByte/baby-sweepstake` can assume it.                      |
| IAM policies `baby-sweepstake-github-deploy-*`     | The deploy role's permissions. See [What the deploy role can do](#what-the-deploy-role-can-do).         |
| IAM policy `baby-sweepstake-service-role-boundary` | The permissions boundary every app service role must carry.                                             |
| AWS Budgets budget `baby-sweepstake-monthly`       | Emails you when the account's spend passes 80% of the monthly limit, or is forecast to pass 100%.       |

Other stacks lock their state with the S3 backend's native lockfile (`use_lockfile = true`), so there is no DynamoDB lock table.

Commands below are for a Bash-like shell. Where PowerShell differs, it's shown too.

## 1. Prerequisites

- **An AWS account** that will host the app. A fresh account is best: the budget covers the whole account, and the deploy role can manage any resource whose name starts with `bs-`.
- **An admin identity in that account**, either an IAM Identity Center user with the `AdministratorAccess` permission set (recommended) or an IAM user with the `AdministratorAccess` policy. Don't use the root user.
- **AWS CLI v2**: `aws --version` should print `aws-cli/2.…`. Install from <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html>.
- **Terraform 1.10 or later**: `terraform version`. Install from <https://developer.hashicorp.com/terraform/install>.
- **Admin access to the GitHub repository** `MickleByte/baby-sweepstake`, for steps 5 to 7. The [GitHub CLI](https://cli.github.com/) (`gh`) makes those steps scriptable, but the web UI works too.
- **A clone of this repository.**

## 2. Configure an AWS CLI profile

Create a profile called `baby-sweepstake`.

With IAM Identity Center:

```sh
aws configure sso --profile baby-sweepstake
aws sso login --profile baby-sweepstake
```

`aws configure sso` asks for your SSO start URL and region (both on the Identity Center settings page), then lets you pick the account and the `AdministratorAccess` role. Set the default region to `eu-west-2`.

With an IAM user, create an access key for the user in the IAM console, then:

```sh
aws configure --profile baby-sweepstake
```

Make it the active profile for this shell, and check who you are:

```sh
export AWS_PROFILE=baby-sweepstake      # PowerShell: $env:AWS_PROFILE = "baby-sweepstake"
aws sts get-caller-identity
```

The `Account` in the output must be the account you mean to deploy to, and the `Arn` must be your admin identity. If it isn't, stop and fix the profile: everything below creates resources in whichever account this prints.

## 3. Apply the bootstrap stack

From the repository root:

```sh
cd infra/bootstrap
```

Create `terraform.tfvars` in that directory. It is gitignored, because it holds your email address:

```hcl
aws_region               = "eu-west-2"
budget_alert_email       = "you@example.com"
budget_monthly_limit_usd = 10
```

`budget_monthly_limit_usd` is in US dollars, the currency AWS bills in. `aws_region` and `budget_monthly_limit_usd` default to the values above, so only the email is required.

Then:

```sh
terraform init
terraform apply
```

Read the plan. It should create 14 resources and change or destroy nothing. Type `yes` to apply. It takes under a minute, and finishes by printing the outputs:

```text
github_deploy_role_arn    = "arn:aws:iam::123456789012:role/baby-sweepstake-github-deploy"
service_role_boundary_arn = "arn:aws:iam::123456789012:policy/baby-sweepstake-service-role-boundary"
state_bucket_name         = "baby-sweepstake-tfstate-123456789012"
```

You'll need the first and last in step 6. `terraform output` prints them again at any time.

If the budget fails with `AccessDenied`, the account hasn't let IAM identities use billing. Sign in as the root user, open **Account**, find **IAM user and role access to Billing information**, choose **Edit**, tick **Activate IAM Access**, then run `terraform apply` again.

### Keep the state file safe

This stack's state is the file `infra/bootstrap/terraform.tfstate`. It can't live in the state bucket, because it is what creates that bucket. It is gitignored: **never commit it**.

It holds no secrets (no keys or passwords, just resource ids and your email address), but you need it to change or remove the bootstrap resources later. After every `terraform apply`:

- Leave the working copy where it is, so the next `terraform apply` finds it.
- Save a copy somewhere private that is backed up and not on this machine, such as an attachment in your password manager or a private cloud drive folder. Keep the previous copy until you know the new one is good.

If the file is ever lost, nothing breaks: CI keeps working. To manage the bootstrap resources again, re-create the state with `terraform import` (or `import` blocks) for each resource in `infra/bootstrap`, then check that `terraform plan` shows no changes.

The state bucket has `prevent_destroy` set, so `terraform destroy` refuses to delete it. That is deliberate: it holds every environment's state.

## 4. Confirm the Route 53 hosted zone

The app is served from `baby-sweepstake.com`, and its stacks add DNS records to that domain's Route 53 hosted zone **in this account**. They can add records but can't create the zone, so it must exist before the first deploy.

Check:

```sh
aws route53 list-hosted-zones-by-name --dns-name baby-sweepstake.com --max-items 1
```

If the first entry in `HostedZones` has `"Name": "baby-sweepstake.com."`, the zone is in this account. Check that the public internet uses it: the name servers from

```sh
aws route53 get-hosted-zone --id <Id from the previous output> --query DelegationSet.NameServers
```

should match the ones from `nslookup -type=NS baby-sweepstake.com` (or `dig NS baby-sweepstake.com +short`). If they match, go to step 5.

If the zone is missing, or the name servers don't match, it depends where the domain is:

- **Registered with Route 53 in this account, but the zone is missing or not in use.** Create the zone (below), then open **Route 53 → Registered domains → baby-sweepstake.com → Edit name servers** and enter the new zone's four name servers.
- **Registered with another registrar.** Create the zone (below). Copy over any records the domain already relies on, such as `MX` records for email. Then, in the registrar's control panel, replace the domain's name servers with the new zone's four.
- **The zone is in a different AWS account.** Zones can't be moved between accounts. Create the zone here (below) and copy the old zone's records into it. Then point the domain at the new zone: if the domain is registered with Route 53 in the other account, edit its name servers there (or move the registration with `aws route53domains transfer-domain-to-another-aws-account --region us-east-1`); otherwise, change them at the registrar. Delete the old zone once `nslookup` shows the new name servers.

To create the zone:

```sh
aws route53 create-hosted-zone --name baby-sweepstake.com --caller-reference "bootstrap-$(date +%s)"
```

(PowerShell: `--caller-reference "bootstrap-$(Get-Date -UFormat %s)"`.) The output's `DelegationSet.NameServers` are the four name servers to use. Name server changes can take up to 48 hours to spread, though it's usually under an hour. A hosted zone costs $0.50 a month.

## 5. Create the GitHub environments

CI deploys through three GitHub environments:

- `preview`: a short-lived environment per pull request.
- `dev`: deployed from `main`.
- `production`: the live site. A person must approve each deploy.

In the web UI, open the repository's **Settings → Environments → New environment** and create each one. For `production`, tick **Required reviewers** and add yourself (and anyone else who may approve production deploys). Under **Deployment branches and tags**, choose **Selected branches and tags** and add `main`, so nothing else can deploy to production.

Or with `gh`:

```sh
gh api --method PUT repos/MickleByte/baby-sweepstake/environments/preview
gh api --method PUT repos/MickleByte/baby-sweepstake/environments/dev
gh api --method PUT repos/MickleByte/baby-sweepstake/environments/production --input - <<EOF
{
  "reviewers": [{ "type": "User", "id": $(gh api user --jq .id) }],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
EOF
gh api --method POST repos/MickleByte/baby-sweepstake/environments/production/deployment-branch-policies -f name=main -f type=branch
```

The last command is what limits production to `main`.

Required reviewers and branch protection are free on public repositories. On a private repository they need a paid GitHub plan.

## 6. Add each environment's secrets and variables

Each environment gets the same three values. Setting them per environment, rather than once for the repository, means production can later move to its own AWS account by changing only its own values.

| Name              | Kind     | Value                                      |
| ----------------- | -------- | ------------------------------------------ |
| `AWS_ROLE_ARN`    | Secret   | The `github_deploy_role_arn` output        |
| `TF_STATE_BUCKET` | Secret   | The `state_bucket_name` output             |
| `AWS_REGION`      | Variable | `eu-west-2` (the `aws_region` you applied) |

In the web UI: **Settings → Environments → _environment_ → Environment secrets → Add environment secret**, and **Environment variables → Add environment variable**.

Or with `gh`, from `infra/bootstrap`:

```sh
ROLE_ARN=$(terraform output -raw github_deploy_role_arn)
STATE_BUCKET=$(terraform output -raw state_bucket_name)
for env in preview dev production; do
  gh secret set AWS_ROLE_ARN --repo MickleByte/baby-sweepstake --env "$env" --body "$ROLE_ARN"
  gh secret set TF_STATE_BUCKET --repo MickleByte/baby-sweepstake --env "$env" --body "$STATE_BUCKET"
  gh variable set AWS_REGION --repo MickleByte/baby-sweepstake --env "$env" --body eu-west-2
done
```

PowerShell:

```powershell
$roleArn = terraform output -raw github_deploy_role_arn
$stateBucket = terraform output -raw state_bucket_name
foreach ($env in "preview", "dev", "production") {
  gh secret set AWS_ROLE_ARN --repo MickleByte/baby-sweepstake --env $env --body $roleArn
  gh secret set TF_STATE_BUCKET --repo MickleByte/baby-sweepstake --env $env --body $stateBucket
  gh variable set AWS_REGION --repo MickleByte/baby-sweepstake --env $env --body eu-west-2
}
```

Check with `gh secret list --env production` and `gh variable list --env production`.

## 7. Protect `main`

Require CI to pass before anything merges into `main`. The two checks are the job names in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml):

- `Lint, typecheck, test, build`
- `Terraform fmt, validate, lint and test`

In the web UI: **Settings → Branches → Add branch protection rule**. Set the branch name pattern to `main`, tick **Require a pull request before merging** and **Require status checks to pass before merging**, then search for and add both checks. The search only finds checks that have run at least once, so open a pull request first if they don't appear.

Or with `gh`:

```sh
gh api --method PUT repos/MickleByte/baby-sweepstake/branches/main/protection --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "Lint, typecheck, test, build" },
      { "context": "Terraform fmt, validate, lint and test" }
    ]
  },
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "enforce_admins": false,
  "restrictions": null
}
EOF
```

If a check's job is ever renamed, update this rule too, or pull requests will wait forever for a check that no longer runs.

## 8. Check the budget alert

AWS Budgets emails the address you gave directly; unlike an SNS email subscription, there is no confirmation email to click. To make sure alerts arrive:

1. Open **Billing and Cost Management → Budgets** and check that `baby-sweepstake-monthly` is listed with your limit, and that its alerts go to your email address.
2. Add `no-reply@budgets.amazonaws.com` to your email contacts, so alerts don't land in spam.

To change the limit or the email later, edit `terraform.tfvars` and run `terraform apply` again (then back up the state file, as in step 3).

You're done. CI can now assume the deploy role and keep its state in the bucket.

## What the deploy role can do

The trust policy accepts a token only if GitHub issued it to a workflow in `MickleByte/baby-sweepstake`: its `sub` claim must match `repo:MickleByte/baby-sweepstake:*`, which covers pull requests, branches and environments in this repository and nothing else. GitHub doesn't give OIDC tokens to `pull_request` workflows triggered from forks, so a fork's pull request can't assume the role. Don't add `pull_request_target` workflows that assume it, because those run with this repository's permissions.

Everything the app stacks create is named with the prefix `bs-`. Where AWS allows it, the role's permissions are limited to resources with that prefix:

- S3 buckets, Lambda functions and layers, DynamoDB tables, CloudWatch log groups, alarms and dashboards, SNS topics, SES configuration sets, and IAM roles and policies.

The bootstrap resources are deliberately named `baby-sweepstake-…`, not `bs-…`, so the deploy role can't change its own permissions, the boundary, or the state bucket's settings. Its only access to the state bucket is reading and writing state objects.

These grants are broader, because the service gives its resources generated ids rather than names we choose, or the action takes no resource:

| Grant                                                 | Why it's broad                                                                                                                                                     |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `cloudfront:*` on all resources                       | Distributions, origin access controls and cache policies get generated ids.                                                                                        |
| `acm:*` on all resources                              | Certificates get generated ids.                                                                                                                                    |
| `apigateway:*` (all HTTP verbs) on all APIs           | HTTP APIs and their stages, routes and integrations get generated ids.                                                                                             |
| `cognito-idp:*` on all resources                      | User pools get generated ids, and creating one takes no resource.                                                                                                  |
| `ses:*` on every SES identity in the account          | Identities are named after the domain or address they verify, not after the app. The SES v1 verify actions take no resource, so they are granted on all resources. |
| Log delivery and log resource policy actions          | API Gateway access logging configures account-level log delivery, which IAM can't scope.                                                                           |
| `route53:ChangeResourceRecordSets` on any hosted zone | Hosted zone ids are generated. A condition limits the change to records named `baby-sweepstake.com` or `*.baby-sweepstake.com`.                                    |
| Read-only list and describe actions                   | Listing actions such as `lambda:ListFunctions` take no resource.                                                                                                   |

The role can't create or delete hosted zones.

### Service roles and the permissions boundary

The app's Lambda functions need IAM roles, so the deploy role can create roles named `bs-…`. Without a limit, that would let it create a `bs-` role with full admin rights and use that role to do anything. To prevent this, the deploy role can only create a role, or change a role's boundary, if the role has the permissions boundary `baby-sweepstake-service-role-boundary` attached. A role's effective permissions are the overlap of its own policies and its boundary, and the boundary allows only what the app needs at runtime: DynamoDB on `bs-` tables, S3 objects in `bs-` buckets, writing logs, metrics and traces, sending email, publishing to SNS, and Cognito user pools. Nothing in it touches IAM or STS.

So every IAM role an app stack creates must set `permissions_boundary` to the `service_role_boundary_arn` output (`arn:aws:iam::<account id>:policy/baby-sweepstake-service-role-boundary`), or AWS rejects it with `AccessDenied`. The deploy role may pass `bs-` roles only to Lambda, API Gateway and Cognito.

### Changing the permissions

When a new stack needs something the deploy role can't do, CI fails with `AccessDenied` naming the missing action. Add it in [`infra/bootstrap/deploy_permissions.tf`](../../infra/bootstrap/deploy_permissions.tf), scoped to `bs-` names if the service allows it, update the table above if the grant is broad, and run steps 2 and 3 again to apply it.

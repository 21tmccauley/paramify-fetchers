# Terraform: the AWS hub-and-spoke IAM for the collector

Provisions the IAM side of [`../AWS_MULTI_ACCOUNT.md`](../AWS_MULTI_ACCOUNT.md):

- **HomeRole** in the EKS account — the Pod's base identity, assumed via IRSA
  (the cluster OIDC provider → this ServiceAccount). Created in `home_role.tf`.
- **A read-only role in each target account** that trusts HomeRole to assume it.
  The `modules/target_account` module; instantiate once per account.
- HomeRole gets `sts:AssumeRole` on those target roles + broad read-only
  (`SecurityAudit` + `ViewOnlyAccess`) for same-account collection.

This is an **example** — scope the read-only policies down for production.

## Inputs

| Variable | What |
|---|---|
| `eks_oidc_provider_arn` | Your cluster's IAM OIDC provider ARN |
| `eks_oidc_provider_url` | OIDC issuer URL **without** `https://` |
| `target_accounts` | `{ name = "account_id" }` — the spoke accounts (name = the manifest `profile:`) |
| `k8s_namespace` / `k8s_service_account` | Where the collector runs (defaults: `default` / `paramify-fetchers`) |

Get the OIDC values from the cluster:

```bash
aws eks describe-cluster --name <cluster> --query cluster.identity.oidc.issuer --output text
# -> https://oidc.eks.<region>.amazonaws.com/id/XXXX  (strip https:// for the URL var;
#    the provider ARN is the IAM OIDC provider you registered for that issuer)
```

## Multi-account: one provider per spoke

Terraform providers can't be `for_each`'d, so each target account needs its own
**aliased provider** (assuming a role you can already use there, e.g.
`OrganizationAccountAccessRole`) and an explicit module block. In `providers.tf`:

```hcl
provider "aws" {
  alias  = "prod"
  region = var.region
  assume_role { role_arn = "arn:aws:iam::<PROD_ACCOUNT_ID>:role/OrganizationAccountAccessRole" }
}
```

Then replace the `for_each` `module "target"` in `target_roles.tf` with one block
per account, wiring the provider:

```hcl
module "target_prod" {
  source        = "./modules/target_account"
  providers     = { aws = aws.prod }
  role_name     = var.readonly_role_name
  home_role_arn = aws_iam_role.home.arn
}
```

(The shipped `for_each` form validates and is correct for a single-account demo —
all roles land in the default provider's account.)

## Apply

```bash
terraform init
terraform apply \
  -var 'eks_oidc_provider_arn=arn:aws:iam::<EKS_ACCT>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/XXXX' \
  -var 'eks_oidc_provider_url=oidc.eks.<region>.amazonaws.com/id/XXXX' \
  -var 'target_accounts={ acct-prod = "111111111111", acct-dev = "222222222222" }'
```

## Wire the outputs back

- `home_role_arn` → the ServiceAccount annotation in
  [`../cronjob-aws.yaml`](../cronjob-aws.yaml) (PROD SWAP #1) **and** the
  `[profile home] role_arn` in [`../aws-config.configmap.yaml`](../aws-config.configmap.yaml).
- `target_role_arns` → the `role_arn` of each `[profile <name>]` in the
  aws-config ConfigMap.

provider "aws" {
  region = var.region
}

# For MULTI-ACCOUNT collection, add one ALIASED provider per target account that
# assumes a role you can already use there (e.g. the Organizations-managed
# OrganizationAccountAccessRole), and pass it to the target module (see
# target_roles.tf + README.md). Terraform providers can't be for_each'd, so this
# is one static block per account. Example:
#
# provider "aws" {
#   alias  = "prod"
#   region = var.region
#   assume_role {
#     role_arn = "arn:aws:iam::<PROD_ACCOUNT_ID>:role/OrganizationAccountAccessRole"
#   }
# }

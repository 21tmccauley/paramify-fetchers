# Read-only role in each target account, trusting HomeRole to assume it (spokes).
#
# Each target role lives in a DIFFERENT account, so in real use you pass an
# ALIASED provider per account (providers can't be for_each'd) — one block each:
#
#   module "target_prod" {
#     source        = "./modules/target_account"
#     providers      = { aws = aws.prod }
#     role_name     = var.readonly_role_name
#     home_role_arn = aws_iam_role.home.arn
#   }
#
# The for_each form below validates and is correct for a SINGLE-account demo
# (every role created in the default provider's account). Replace it with explicit
# per-account module blocks (above) for true multi-account.
module "target" {
  source        = "./modules/target_account"
  for_each      = var.target_accounts
  role_name     = var.readonly_role_name
  home_role_arn = aws_iam_role.home.arn
}

# A read-only role in a target (spoke) account that trusts HomeRole to assume it.
# Instantiate once per account, with an aws provider scoped to that account.

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [var.home_role_arn]
    }
    # Optional hardening (confused-deputy): require a shared ExternalId, and set
    # the same external_id in the aws-config profile.
    # condition {
    #   test     = "StringEquals"
    #   variable = "sts:ExternalId"
    #   values   = ["<external-id>"]
    # }
  }
}

resource "aws_iam_role" "readonly" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# Broad read-only coverage for the fetchers. Scope down to least privilege for prod.
resource "aws_iam_role_policy_attachment" "securityaudit" {
  role       = aws_iam_role.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "viewonly" {
  role       = aws_iam_role.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

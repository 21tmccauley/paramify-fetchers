# HomeRole — the Pod's base identity, lives in the EKS account. IRSA lets the
# collector's ServiceAccount assume it via the cluster's OIDC provider (no keys).

locals {
  oidc_sub = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account}"
  target_role_arns = [
    for id in values(var.target_accounts) :
    "arn:aws:iam::${id}:role/${var.readonly_role_name}"
  ]
}

# Trust policy: the cluster OIDC provider may assume HomeRole, but only for OUR
# ServiceAccount (sub) and the STS audience.
data "aws_iam_policy_document" "home_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = [local.oidc_sub]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "home" {
  name               = var.home_role_name
  assume_role_policy = data.aws_iam_policy_document.home_trust.json
}

# Spoke access: HomeRole may assume each target account's read-only role.
data "aws_iam_policy_document" "home_assume_targets" {
  count = length(local.target_role_arns) > 0 ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = local.target_role_arns
  }
}

resource "aws_iam_role_policy" "home_assume_targets" {
  count  = length(local.target_role_arns) > 0 ? 1 : 0
  name   = "assume-target-readonly"
  role   = aws_iam_role.home.id
  policy = data.aws_iam_policy_document.home_assume_targets[0].json
}

# Same-account collection: if the collector also reads the EKS account itself
# (ambient, no assume-role), HomeRole needs read perms directly. Scope down for prod.
resource "aws_iam_role_policy_attachment" "home_securityaudit" {
  role       = aws_iam_role.home.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "home_viewonly" {
  role       = aws_iam_role.home.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

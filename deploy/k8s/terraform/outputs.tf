output "home_role_arn" {
  description = "Use in the ServiceAccount annotation (PROD SWAP #1) and the aws-config [profile home] role_arn."
  value       = aws_iam_role.home.arn
}

output "service_account_annotation" {
  description = "Copy into deploy/k8s/cronjob-aws.yaml's ServiceAccount."
  value       = "eks.amazonaws.com/role-arn: ${aws_iam_role.home.arn}"
}

output "target_role_arns" {
  description = "Per-account read-only role ARNs — feed into the aws-config profiles."
  value       = { for k, m in module.target : k => m.role_arn }
}

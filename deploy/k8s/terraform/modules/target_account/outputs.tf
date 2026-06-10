output "role_arn" {
  description = "ARN of the read-only role created in this account."
  value       = aws_iam_role.readonly.arn
}

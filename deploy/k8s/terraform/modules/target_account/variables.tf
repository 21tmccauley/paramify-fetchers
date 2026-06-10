variable "role_name" {
  description = "Name of the read-only role to create in this account."
  type        = string
}

variable "home_role_arn" {
  description = "ARN of the HomeRole allowed to assume this role."
  type        = string
}

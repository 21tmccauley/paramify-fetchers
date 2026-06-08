variable "region" {
  description = "Region for the AWS providers (any region; IAM is global)."
  type        = string
  default     = "us-east-1"
}

# --- The EKS cluster's OIDC provider (where the HomeRole lives) ----------------
# Get these from your cluster, e.g.:
#   aws eks describe-cluster --name <cluster> --query cluster.identity.oidc.issuer --output text
# The ARN is the IAM OIDC identity provider you registered for that issuer.
variable "eks_oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC identity provider."
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "Cluster OIDC issuer URL WITHOUT the https:// prefix (e.g. oidc.eks.us-east-1.amazonaws.com/id/ABC123)."
  type        = string
}

variable "k8s_namespace" {
  description = "Namespace the collector runs in."
  type        = string
  default     = "default"
}

variable "k8s_service_account" {
  description = "ServiceAccount name the CronJob uses (matches deploy/k8s/cronjob-aws.yaml)."
  type        = string
  default     = "paramify-fetchers"
}

variable "home_role_name" {
  description = "Name of the HomeRole created in the EKS account (the Pod's base identity)."
  type        = string
  default     = "paramify-fetchers"
}

variable "readonly_role_name" {
  description = "Name of the read-only role created in EACH target account."
  type        = string
  default     = "paramify-readonly"
}

# --- Target accounts to collect from -----------------------------------------
# name => 12-digit account id. The name is what you use as the `profile:` in the
# manifest and in deploy/k8s/aws-config.configmap.yaml.
variable "target_accounts" {
  description = "Map of profile name => target AWS account id."
  type        = map(string)
  default     = {}
}

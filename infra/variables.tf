variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for every resource name."
  type        = string
  default     = "appsec-api"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_name))
    error_message = "Use 3-25 lowercase letters, numbers or hyphens, starting with a letter."
  }
}

variable "owner" {
  description = "Owner tag applied to all resources."
  type        = string
  default     = "ian-guidry"
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, in owner/name form."
  type        = string
  default     = "eguidey/aws-appsec-pipeline"
}

variable "github_owner_id" {
  description = "Numeric GitHub user/org ID. Required for repos created after 2026-07-15 (immutable OIDC subject claims)."
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[0-9]*$", var.github_owner_id))
    error_message = "github_owner_id must be digits only."
  }
}

variable "github_repository_id" {
  description = "Numeric GitHub repository ID. Required for repos created after 2026-07-15 (immutable OIDC subject claims)."
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[0-9]*$", var.github_repository_id))
    error_message = "github_repository_id must be digits only."
  }
}

variable "github_deploy_branch" {
  description = "Only this branch may assume the deploy role."
  type        = string
  default     = "main"
}

variable "github_environment" {
  description = "GitHub deployment environment used by the deploy job (can require manual approval)."
  type        = string
  default     = "production"
}

variable "create_github_oidc_provider" {
  description = "Set to false if your AWS account already has the GitHub OIDC provider."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address that receives security alerts and budget warnings."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "Provide a valid email address."
  }
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the API. Use [\"<your-ip>/32\"] to keep it private."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "desired_count" {
  description = "Number of running tasks. Starts at 0; the pipeline scales to 1 after the first image push."
  type        = number
  default     = 0
}

variable "enable_guardduty" {
  description = "Enable GuardDuty with ECS Fargate runtime monitoring (30-day free trial, then paid)."
  type        = bool
  default     = false
}

variable "monthly_budget_usd" {
  description = "Send a budget alert email when forecast spend exceeds this amount."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "How long to keep application and VPC flow logs."
  type        = number
  default     = 30
}

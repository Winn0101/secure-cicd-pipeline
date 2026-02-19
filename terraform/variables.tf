variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "secure-cicd"
}

variable "github_repo" {
  description = "GitHub repository (owner/repo)"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch to deploy"
  type        = string
  default     = "main"
}

variable "notification_email" {
  description = "Email for pipeline notifications"
  type        = string
}

variable "approval_sns_emails" {
  description = "List of emails for approval notifications"
  type        = list(string)
}

variable "container_image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "enable_break_glass" {
  description = "Enable break-glass emergency deployments"
  type        = bool
  default     = true
}

variable "security_scan_fail_on_high" {
  description = "Fail pipeline on high severity findings"
  type        = bool
  default     = true
}

variable "policy_enforcement_mode" {
  description = "Policy enforcement mode: strict, advisory, permissive"
  type        = string
  default     = "strict"
  
  validation {
    condition     = contains(["strict", "advisory", "permissive"], var.policy_enforcement_mode)
    error_message = "Enforcement mode must be strict, advisory, or permissive"
  }
}

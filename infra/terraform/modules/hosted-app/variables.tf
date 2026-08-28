variable "name" {
  description = "Short, DNS-safe app name. Becomes the ECS service name and the <name>.<base_domain> hostname."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be lowercase alphanumeric/hyphen, starting with a letter, 2-31 chars."
  }
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Public subnet IDs the Fargate task's ENI lands in. No NAT — see docs/well-architected.md."
  type        = list(string)
}

variable "cluster_id" {
  description = "ECS cluster ARN/ID this app's service runs on."
  type        = string
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  description = "0 = the app is dark: task definition and DNS exist, nothing is running or billable. This is the on/off switch."
  type        = number
  default     = 0
}

variable "env" {
  description = "Plain (non-secret) environment variables for the app container."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets injected from SSM Parameter Store, as {name, ssm_parameter_name} pairs. Each name must already exist as a SecureString in Parameter Store — this module does not create app secrets, only the tunnel token."
  type = list(object({
    name               = string
    ssm_parameter_name = string
  }))
  default = []
}

variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "base_domain" {
  type = string
}

variable "allowed_emails" {
  description = "Exact emails allowed through this app's Access policy, regardless of IdP."
  type        = list(string)
}

variable "allowed_google_domain" {
  description = "Google Workspace domain allowed through this app's Access policy, in addition to allowed_emails. Null to disable."
  type        = string
  default     = null
}

variable "github_oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider, for this app's CI deploy role."
  type        = string
}

variable "github_repo" {
  description = "owner/repo allowed to assume this app's deploy role via GitHub Actions OIDC. Defaults to a placeholder — always set this explicitly per app."
  type        = string
  default     = "owner/repo-not-set"
}

variable "enable_ecs_exec" {
  description = "Grant the task role ECS Exec permissions (interactive debug shell into the running container). Off by default — it's a real blast-radius increase."
  type        = bool
  default     = false
}

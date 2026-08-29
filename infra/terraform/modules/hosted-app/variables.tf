variable "name" {
  description = "Short, DNS-safe app name. Becomes the ECS service name and the <name>.<base_domain> hostname."
  type        = string

  validation {
    # Must start and end with an alphanumeric character - a trailing hyphen (e.g.
    # "demo-") is not a valid DNS label and only surfaces as a Cloudflare-side apply
    # failure, not a terraform validate error, without this stricter check.
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) >= 2 && length(var.name) <= 31
    error_message = "name must be lowercase alphanumeric/hyphen, start and end with a letter or digit, 2-31 chars."
  }
}

variable "name_prefix" {
  description = <<-EOT
    Prefix applied to every resource this module creates, so two independent
    instantiations of this stack (e.g. staging + production, or two unrelated
    consumers in the same AWS/Cloudflare account) don't collide on ECR repo names,
    IAM role names, the ECS task-definition family, the CloudWatch log group, or the
    SSM parameter path. Pass root's var.name_prefix through here - it is not threaded
    automatically.
  EOT
  type        = string
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

  validation {
    # The ARN this module builds (main.tf) interpolates ssm_parameter_name directly
    # after "parameter" with no separator - a value missing the leading "/" produces
    # a malformed ARN that silently fails only when the task tries to start, not at
    # plan/apply time.
    condition     = alltrue([for s in var.secrets : startswith(s.ssm_parameter_name, "/")])
    error_message = "Every secrets[].ssm_parameter_name must start with \"/\" (SSM parameter names are absolute paths)."
  }
}

variable "cloudflared_image" {
  description = <<-EOT
    Pinned cloudflared image, including tag. cloudflared is the sole component with
    any network exposure at all (see docs/architecture.md) - do not default this to
    ":latest"; a mutable tag means the trusted ingress path can change behavior on a
    task restart with no corresponding Terraform diff to review. Check
    https://github.com/cloudflare/cloudflared/releases for the current stable release
    before applying, and pin explicitly here.
  EOT
  type        = string
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
  description = "Exact emails allowed through this app's Access policy, via any IdP. At least one of allowed_emails/allowed_google_domain must be set — see the cross-variable validation below."
  type        = list(string)
  default     = []

  validation {
    # The one control gating every app (see docs/architecture.md's own framing) must
    # not be constructible as empty-and-unrestricted. Terraform >= 1.9 (this repo
    # requires >= 1.10) supports referencing other variables in a validation
    # condition, so this is checked here rather than left as an unenforced doc note.
    condition     = length(var.allowed_emails) > 0 || var.allowed_google_domain != null
    error_message = "At least one of allowed_emails or allowed_google_domain must be set - an Access policy with neither is a fail-open risk, not a valid deny-by-default state."
  }
}

variable "allowed_google_domain" {
  description = "Google Workspace domain allowed through this app's Access policy, in addition to allowed_emails. Enforced as Google-IdP-only via a require block (see access policy resources) - a matching email domain authenticated through a different IdP does not satisfy this. Null to disable."
  type        = string
  default     = null
}

variable "github_idp_id" {
  description = "ID of the account-wide GitHub identity provider (root access.tf), referenced by this app's Access application so it is actually restricted to the two configured IdPs."
  type        = string
}

variable "google_idp_id" {
  description = "ID of the account-wide Google identity provider (root access.tf), referenced by this app's Access application, and by the allowed_google_domain policy's require block."
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider, for this app's CI deploy role."
  type        = string
}

variable "github_repo" {
  description = "owner/repo allowed to assume this app's deploy role via GitHub Actions OIDC. No default - every app must set this explicitly; a silently-inherited placeholder here is exactly how one app's deploy role ends up trusting the wrong repo."
  type        = string

  validation {
    # Exact owner/repo shape, no wildcards. This is the enforcement half of the fix
    # for the OIDC trust condition below using StringEquals instead of StringLike -
    # StringEquals still needs a non-wildcard input to actually be exact-match-only.
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo must be an exact \"owner/repo\" pair (letters, digits, dot, underscore, hyphen only - no wildcards, no placeholder default)."
  }
}

variable "enable_ecs_exec" {
  description = "Grant the task role ECS Exec permissions (interactive debug shell into the running container). Off by default — it's a real blast-radius increase."
  type        = bool
  default     = false
}

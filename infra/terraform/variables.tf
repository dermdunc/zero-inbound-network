# --- Provider credentials -----------------------------------------------------
# All sensitive — supply via TF_VAR_ environment variables or a gitignored
# terraform.tfvars, never hardcoded. See terraform.tfvars.example.

variable "cloudflare_api_token" {
  description = "Cloudflare API token, scoped to Zero Trust + DNS edit on the target zone."
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

# --- Cloudflare account/zone ---------------------------------------------------

variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the Zero Trust org and the target zone."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for base_domain."
  type        = string
}

variable "base_domain" {
  description = <<-EOT
    Domain the hosted apps live under (e.g. an app named "demo" becomes
    demo.<base_domain>). Use a domain you actually control in Cloudflare —
    never reuse a real internal/private domain in a public fork of this repo.
  EOT
  type        = string
  default     = "example.test"
}

variable "name_prefix" {
  description = "Prefix applied to every named resource, so this stack can coexist with others in the same account."
  type        = string
  default     = "zin"
}

# --- Identity: who is allowed through Cloudflare Access ------------------------

variable "allowed_emails" {
  description = "Exact email addresses allowed through Access regardless of which IdP they authenticate with. Required — there is no default allow-list."
  type        = list(string)
}

variable "allowed_google_domain" {
  description = "If set, any user authenticating via the Google IdP with this Workspace domain is allowed, in addition to allowed_emails. Leave null to require exact emails only."
  type        = string
  default     = null
}

variable "google_oauth_client_id" {
  description = "OAuth client ID for the Google identity provider registered in Cloudflare Access."
  type        = string
}

variable "google_oauth_client_secret" {
  description = "OAuth client secret for the Google identity provider."
  type        = string
  sensitive   = true
}

variable "github_oauth_client_id" {
  description = "OAuth App client ID for the GitHub identity provider registered in Cloudflare Access."
  type        = string
}

variable "github_oauth_client_secret" {
  description = "OAuth App client secret for the GitHub identity provider."
  type        = string
  sensitive   = true
}

# --- GitHub Actions OIDC --------------------------------------------------------

variable "create_github_oidc_provider" {
  description = <<-EOT
    Whether to create the AWS IAM OIDC provider for GitHub Actions
    (token.actions.githubusercontent.com). AWS allows only one per URL per
    account — set this to false and use a data source instead if your account
    already has one (very likely, if any other stack in this account uses
    GitHub Actions OIDC).
  EOT
  type        = bool
  default     = true
}

# --- Networking ------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Public subnets only — see docs/well-architected.md for the no-NAT tradeoff."
  type        = string
  default     = "10.90.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread the public subnets across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

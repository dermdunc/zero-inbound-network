terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # No backend block on purpose. This repo is a reference implementation, not a
  # deployed instance — pick a real backend (S3 + native locking, Terraform Cloud,
  # whatever your org already runs) before applying anywhere. See docs/well-architected.md
  # "State" for what that backend needs to guarantee.
}

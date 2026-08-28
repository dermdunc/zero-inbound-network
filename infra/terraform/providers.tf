provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project    = "zero-inbound-network"
      managed_by = "terraform"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

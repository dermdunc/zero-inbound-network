# --- Network: public subnets, no NAT ------------------------------------------
# Every hosted app's security group has zero ingress rules (see the hosted-app
# module). The only way in is the outbound-initiated Cloudflare Tunnel each app's
# cloudflared sidecar opens. Because nothing needs to originate from outside,
# there is no NAT gateway and no private subnet tier — see
# docs/well-architected.md "Network" for what that trades away.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in var.availability_zones : az => idx }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value)
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --- Compute: one shared ECS cluster, one Fargate service per hosted app -------

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# --- Example app instance -------------------------------------------------------
# This is the reuse story made literal: standing up a second hosted app is one
# more module block like this one, not a copy-pasted set of resources. Delete
# this block (and app.tf.example survives as a template) once you have real
# apps to declare.

module "example_app" {
  source = "./modules/hosted-app"

  name        = "demo"
  name_prefix = var.name_prefix
  vpc_id      = aws_vpc.this.id
  subnet_ids  = [for s in aws_subnet.public : s.id]
  cluster_id  = aws_ecs_cluster.this.id

  # Pinned, not :latest - check https://hub.docker.com/_/nginx/tags for a current
  # stable tag before reusing this block for a real app; the point being
  # demonstrated is "pin explicitly", not this specific version.
  container_image = "public.ecr.aws/docker/library/nginx:1.27-alpine"
  container_port  = 80
  desired_count   = 0 # off by default — see "The dark switch" in the README

  # Pinned, not :latest - cloudflared is the sole component with any network
  # exposure at all (see docs/architecture.md). Check
  # https://github.com/cloudflare/cloudflared/releases before reusing this value.
  cloudflared_image = "cloudflare/cloudflared:2024.10.0"

  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_zone_id    = var.cloudflare_zone_id
  base_domain           = var.base_domain
  github_idp_id         = cloudflare_zero_trust_access_identity_provider.github.id
  google_idp_id         = cloudflare_zero_trust_access_identity_provider.google.id

  allowed_emails           = var.allowed_emails
  allowed_google_domain    = var.allowed_google_domain
  github_oidc_provider_arn = local.github_oidc_provider_arn
  # This is a real "owner/repo" shape (github_repo's validation requires it), but a
  # placeholder value - replace with the real repo before applying to a real app.
  # It was previously omitted entirely, silently falling back to an unvalidated
  # module default; that default has since been removed, so this is now required.
  github_repo = "your-org/your-repo"
}

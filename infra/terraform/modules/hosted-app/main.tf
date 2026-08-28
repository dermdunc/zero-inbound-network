locals {
  hostname = "${var.name}.${var.base_domain}"
}

# --- Registry + logs -----------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = "${var.name_prefix}-${var.name}-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name_prefix}-${var.name}"
  retention_in_days = 30
}

# --- Network: zero ingress rules ------------------------------------------------
# The absence of an ingress block IS the control. Nothing reaches this task
# except through the outbound-initiated Cloudflare Tunnel the cloudflared
# sidecar opens below. Do not add an ingress rule to "make debugging easier" —
# that's the exact mistake this pattern exists to prevent. Use enable_ecs_exec
# for interactive debugging instead.
resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-${var.name}-task-sg"
  description = "Zero-inbound: no ingress rules. Egress only, for the tunnel and pulling the image."
  vpc_id      = var.vpc_id

  # Unrestricted egress is a residual risk this module does not close: a compromised
  # app container can still exfiltrate data or reach a C2 host outbound. "Zero
  # inbound" is a claim about the ingress side only - see docs/well-architected.md.
  egress {
    description = "All outbound - the tunnel and image pulls both need it."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM: task role (app runtime permissions), execution role (pull image /
# --- read secrets), deploy role (CI, via GitHub OIDC, no long-lived keys) ------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "task" {
  name = "${var.name_prefix}-${var.name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "task_exec_ssm" {
  count = var.enable_ecs_exec ? 1 : 0
  name  = "ecs-exec"
  role  = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "execution" {
  name = "${var.name_prefix}-${var.name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "execution" {
  name = "pull-and-read-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken does not support resource-level scoping (AWS rejects
        # a non-"*" Resource for it) - it must stay separate from the scoped actions.
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # Scoped to this app's own repo only - without this, any app's execution
        # role can pull any other private ECR repo in the account.
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
        ]
        Resource = aws_ecr_repository.this.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.this.arn}:*"
      },
      {
        Effect = "Allow"
        Action = ["ssm:GetParameters", "ssm:GetParameter"]
        Resource = concat(
          [aws_ssm_parameter.tunnel_token.arn],
          [for s in var.secrets : "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${s.ssm_parameter_name}"]
        )
      },
    ]
  })
}

# Deploy role: assumed only by GitHub Actions pushing to var.github_repo's main
# branch, via OIDC. No long-lived AWS access keys anywhere in this app's CI.
resource "aws_iam_role" "deploy" {
  name = "${var.name_prefix}-${var.name}-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # StringEquals, not StringLike: this condition must be an EXACT match, not a
        # wildcard-capable one. github_repo's own validation (variables.tf) already
        # rejects wildcard characters, but StringEquals is the correct operator
        # regardless - it is not "less capable" than StringLike here, it removes a
        # capability (wildcard interpretation) this condition should never have had.
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  # Known limitation, disclosed rather than silently assumed away: this trust is
  # scoped to the repo's current NAME, not an immutable repository ID. If
  # var.github_repo is renamed, transferred, deleted, and the old name is claimed by
  # a different owner, this trust follows the name, not the original repository. An
  # earlier version of this comment claimed an "ID-augmented sub-claim form" was
  # also matched here - it was not; that claim was wrong and has been removed rather
  # than implemented on unverified assumptions about GitHub's token format.
}

resource "aws_iam_role_policy" "deploy" {
  name = "push-and-update-service"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = aws_ecr_repository.this.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = aws_ecs_service.this.id
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition"]
        Resource = "*" # RegisterTaskDefinition does not support resource-level scoping.
      },
      {
        # Scoped to the ECS task-definition use case specifically - without the
        # condition, iam:PassRole on these two ARNs is broader than "for an ECS
        # task definition", even though that's the only intended use.
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.task.arn, aws_iam_role.execution.arn]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
    ]
  })
}

# --- Cloudflare Tunnel: the only way in -----------------------------------------

resource "random_id" "tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.cloudflare_account_id
  name       = "${var.name_prefix}-${var.name}"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config {
    ingress_rule {
      hostname = local.hostname
      service  = "http://localhost:${var.container_port}"
    }

    # Catch-all MUST be last and MUST have no hostname — cloudflared rejects
    # a config missing this, and the app's cloudflared sidecar reaches the app
    # container over localhost inside the task's shared network namespace, not
    # over the SG (which has no ingress rule to allow it anyway).
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "aws_ssm_parameter" "tunnel_token" {
  name  = "/${var.name_prefix}/${var.name}/tunnel-token"
  type  = "SecureString"
  value = cloudflare_zero_trust_tunnel_cloudflared.this.tunnel_token
}

# The "name" argument on a Cloudflare DNS record is relative to the zone identified
# by zone_id, not to var.base_domain as a string. This only produces the intended
# <name>.<base_domain> hostname when cloudflare_zone_id's zone IS base_domain's own
# apex - if base_domain were ever a delegated subdomain living in a *different*
# Cloudflare zone than the one zone_id points at, this record would resolve under
# the wrong parent domain while local.hostname (used by the tunnel config and the
# Access application below) stays correct, silently gating a hostname that doesn't
# match what DNS actually serves. This module assumes, and does not verify, that
# cloudflare_zone_id's zone equals base_domain exactly.
resource "cloudflare_record" "this" {
  zone_id = var.cloudflare_zone_id
  name    = var.name
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
}

# --- Cloudflare Access: gate the hostname behind SSO ----------------------------
# The two account-wide identity providers (github, google) are declared once in the
# root module's access.tf and passed in as var.github_idp_id/var.google_idp_id.

resource "cloudflare_zero_trust_access_application" "this" {
  account_id       = var.cloudflare_account_id
  zone_id          = var.cloudflare_zone_id
  name             = var.name
  domain           = local.hostname
  type             = "self_hosted"
  session_duration = "24h"

  # Without this, Cloudflare defaults an Access application to ALL identity
  # providers configured on the account, not just the two this module creates -
  # an earlier version of this resource omitted it, silently relying on "only two
  # IdPs exist yet" instead of actually restricting the application to them.
  allowed_idps = [var.github_idp_id, var.google_idp_id]
}

# Two separate policies, not one, because the two allow-paths need different IdP
# enforcement:
#  - exact allowed_emails should work via EITHER IdP (no login_method restriction)
#  - allowed_google_domain must only work via the Google IdP specifically - a
#    same-domain email authenticated through GitHub must NOT satisfy it. Cloudflare's
#    email_domain match criterion is IdP-agnostic on its own (it checks the
#    authenticated email's domain regardless of which IdP produced it), so the
#    Google-only restriction has to be added as a separate `require` (AND)
#    condition, which only applies within its own policy - it cannot be bolted onto
#    a single shared policy without also constraining the allowed_emails path.
# Cloudflare Access grants access if ANY policy for the application evaluates to
# allow, so these two policies together are the OR the original single-policy
# design intended - the earlier version was just wrong about how to build it.

resource "cloudflare_zero_trust_access_policy" "emails" {
  count = length(var.allowed_emails) > 0 ? 1 : 0

  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.this.id
  zone_id        = var.cloudflare_zone_id
  name           = "${var.name}-allow-emails"
  precedence     = 1
  decision       = "allow"

  include {
    email = var.allowed_emails
  }
}

resource "cloudflare_zero_trust_access_policy" "google_domain" {
  count = var.allowed_google_domain != null ? 1 : 0

  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.this.id
  zone_id        = var.cloudflare_zone_id
  name           = "${var.name}-allow-google-domain"
  precedence     = 2
  decision       = "allow"

  include {
    email_domain = [var.allowed_google_domain]
  }

  require {
    login_method = [var.google_idp_id]
  }
}

# --- Compute: Fargate service, app container + cloudflared sidecar -------------

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-${var.name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image
      essential = true
      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]
      environment = [for k, v in var.env : { name = k, value = v }]
      secrets = [for s in var.secrets : {
        name      = s.name
        valueFrom = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${s.ssm_parameter_name}"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "app"
        }
      }
    },
    {
      name      = "cloudflared"
      image     = var.cloudflared_image
      essential = true
      command   = ["tunnel", "--no-autoupdate", "run"]
      secrets = [{
        name      = "TUNNEL_TOKEN"
        valueFrom = aws_ssm_parameter.tunnel_token.arn
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "cloudflared"
        }
      }
    },
  ])
}

resource "aws_ecs_service" "this" {
  name                   = "${var.name_prefix}-${var.name}"
  cluster                = var.cluster_id
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = var.enable_ecs_exec

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = true # no NAT — see docs/well-architected.md "Network"
  }

  lifecycle {
    ignore_changes = [task_definition] # CI's deploy role updates this out-of-band
  }
}

locals {
  hostname = "${var.name}.${var.base_domain}"
}

# --- Registry + logs -----------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = "${var.name}-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
}

# --- Network: zero ingress rules ------------------------------------------------
# The absence of an ingress block IS the control. Nothing reaches this task
# except through the outbound-initiated Cloudflare Tunnel the cloudflared
# sidecar opens below. Do not add an ingress rule to "make debugging easier" —
# that's the exact mistake this pattern exists to prevent. Use enable_ecs_exec
# for interactive debugging instead.
resource "aws_security_group" "this" {
  name        = "${var.name}-task-sg"
  description = "Zero-inbound: no ingress rules. Egress only, for the tunnel and pulling the image."
  vpc_id      = var.vpc_id

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
  name = "${var.name}-task-role"

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
  name = "${var.name}-execution-role"

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
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
        ]
        Resource = "*"
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

# Deploy role: assumed only by GitHub Actions in var.github_repo, via OIDC.
# No long-lived AWS access keys anywhere in this app's CI.
resource "aws_iam_role" "deploy" {
  name = "${var.name}-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # StringLike (not StringEquals) because GitHub's `sub` claim can appear
        # either as `repo:owner/repo:ref:refs/heads/main` or, for orgs with ID
        # collisions, the ID-augmented `repo:owner@<id>/repo@<id>:ref:...` form.
        # Both patterns are listed; StringLike OR-evaluates a list.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo}:ref:refs/heads/main",
            "repo:${var.github_repo}:environment:production",
          ]
        }
      }
    }]
  })
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
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.task.arn, aws_iam_role.execution.arn]
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
  name       = var.name
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
  name  = "/zero-inbound-network/${var.name}/tunnel-token"
  type  = "SecureString"
  value = cloudflare_zero_trust_tunnel_cloudflared.this.tunnel_token
}

resource "cloudflare_record" "this" {
  zone_id = var.cloudflare_zone_id
  name    = var.name
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
}

# --- Cloudflare Access: gate the hostname behind SSO ----------------------------
# The two account-wide identity providers (github, google) are declared once in
# the root module's access.tf. This app's policy references both — either IdP
# gets a user through, as long as they also match allowed_emails /
# allowed_google_domain.

resource "cloudflare_zero_trust_access_application" "this" {
  account_id       = var.cloudflare_account_id
  zone_id          = var.cloudflare_zone_id
  name             = var.name
  domain           = local.hostname
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "this" {
  account_id     = var.cloudflare_account_id
  application_id = cloudflare_zero_trust_access_application.this.id
  zone_id        = var.cloudflare_zone_id
  name           = "${var.name}-allow"
  precedence     = 1
  decision       = "allow"

  include {
    email = var.allowed_emails

    # email_domain matches on the authenticated user's email domain regardless
    # of which IdP they signed in with (google or otherwise) - it is not the
    # same as the "gsuite" include type, which matches specific Google
    # Workspace Groups and requires its own identity_provider_id. Domain-wide
    # matching is what "let anyone on our Workspace domain in" actually needs,
    # and it's a plain attribute on this block, not a nested block.
    email_domain = var.allowed_google_domain == null ? null : [var.allowed_google_domain]
  }
}

# --- Compute: Fargate service, app container + cloudflared sidecar -------------

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
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
      image     = "cloudflare/cloudflared:latest"
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
  name                   = var.name
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

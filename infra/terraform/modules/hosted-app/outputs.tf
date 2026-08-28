output "ecr_repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "ecs_service_name" {
  value = aws_ecs_service.this.name
}

output "deploy_role_arn" {
  description = "Set this as the role-to-assume in the app's GitHub Actions workflow (aws-actions/configure-aws-credentials)."
  value       = aws_iam_role.deploy.arn
}

output "hostname" {
  value = local.hostname
}

output "security_group_id" {
  value = aws_security_group.this.id
}

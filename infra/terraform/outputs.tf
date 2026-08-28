output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "ecs_cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "github_oidc_provider_arn" {
  value = local.github_oidc_provider_arn
}

output "example_app_hostname" {
  value = module.example_app.hostname
}

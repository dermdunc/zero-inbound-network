# Well-Architected notes: Zero-Inbound Network

Tradeoffs this pattern makes on purpose, and where it stops being the right call. Written
for whoever is deciding whether to adapt this repo, not as a checkbox compliance exercise.

## Pillar mapping

| Pillar | This pattern's position |
|---|---|
| Security | Single control (no ingress rule) instead of defense-in-depth. See "The single-control tradeoff" below — this is the pillar most worth reading closely before adapting this repo. |
| Reliability | No redundancy built in (`desired_count` defaults to 0/1, not multi-AZ auto-scaling). Fine for a low-traffic, small-audience app; wrong for anything with an SLA. |
| Performance | Cloudflare's edge does TLS termination and proxying; the app itself is a single Fargate task, not built to scale horizontally without changes. |
| Cost optimization | The whole point. No NAT gateway (~$32/mo minimum just to exist, before data processing charges), no second AWS account, no per-seat zero-trust product license. The `desired_count = 0` dark switch means an idle app costs nothing but ECR/log storage. |
| Operational excellence | One Terraform module per app; adding an app is additive, not a fork of the pattern. Deploy is GitHub Actions via OIDC, not a human running `terraform apply` per release. |

## The single-control tradeoff

The zero-inbound security group is the *entire* network-layer defense. There's no NAT, no
private subnet tier, no second layer to fall back on if Cloudflare Access itself is
misconfigured or its tunnel credentials leak. That's a deliberate, disclosed tradeoff for a
personal or small-team, cost-constrained use case — it is very likely the *wrong* call for
a workload that needs dual control (e.g. a compliance regime requiring defense-in-depth
independent of any single vendor). If that's your situation, the variant to build instead
puts the app in a **private** subnet behind a NAT gateway, with the security group allowing
ingress only from a bastion or a second, independently-operated network layer — accept the
NAT cost as the price of a second control.

## Network

No NAT. Public subnets, `assign_public_ip = true` on the ECS service, zero-ingress
security group. The absence of an ingress rule only holds as a control for as long as
nobody adds one "temporarily" to debug something — there's no compensating control if that
discipline slips. `enable_ecs_exec` exists specifically so "I need a shell in the
container" never becomes a reason to open a port.

## Identity

Two identity providers (GitHub, Google) registered once, account-wide, and referenced by
every app's Access policy. This is a deliberate broadening from a single-IdP design: it
trades "one login system to reason about" for "works for people who don't have a GitHub
account." Each app's policy still requires an exact email match (or, optionally, a Google
Workspace domain match) on top of whichever IdP the person used — the IdP choice doesn't
by itself grant access.

GitHub Actions gets no long-lived AWS credentials at all. The trust policy on each app's
deploy role restricts `sts:AssumeRoleWithWebIdentity` to one `owner/repo`, via the OIDC
token's `sub` claim — a leaked repo secret can't be used to assume a different app's role,
and there's no access key to rotate or accidentally commit.

## State

This repo ships with no Terraform backend configured — see `infra/terraform/versions.tf`.
Before applying anywhere real, configure a remote backend with locking (S3 + native
locking on Terraform >= 1.10, Terraform Cloud, or your org's existing convention) so two
people (or two agent sessions) can't race a plan/apply against the same state and corrupt
it. This is not a hypothetical: shared-state races that clobber live infrastructure are a
real, recurring failure mode with local or unlocked state, not a theoretical risk being
mentioned for completeness.

## Cost awareness

Per idle app (`desired_count = 0`): ECR storage (pennies), CloudWatch log retention
(pennies), one SSM SecureString parameter (free tier covers it). Per running app
(`desired_count = 1`): one Fargate task's compute (~$5-15/mo depending on CPU/memory
sizing), Cloudflare Tunnel itself is free on Cloudflare's free tier, Access is free up to
50 users on Cloudflare's free tier. No NAT gateway, no load balancer, no second AWS
account — the three line items that would otherwise dominate a small deployment's bill.

## What this deliberately doesn't solve

- **Multi-tenancy isolation beyond the security group / IAM role / ECR repo boundary.**
  Every app in this pattern shares one AWS account and one VPC. If you need
  account-level blast-radius containment (a compromised app cannot see *any* other app's
  resources, full stop), that's a second AWS account per tenant, not this pattern.
- **High availability.** One task, one AZ by default (Fargate can span the subnets passed
  in, but nothing here auto-scales or health-checks across them).
- **Compliance-grade audit logging beyond what CloudWatch/Cloudflare already provide
  out of the box.** No dedicated audit-log pipeline is built here.

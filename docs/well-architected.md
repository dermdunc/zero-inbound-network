# Well-Architected notes: Zero-Inbound Network

Tradeoffs this pattern makes on purpose, and where it stops being the right call. Written
for whoever is deciding whether to adapt this repo, not as a checkbox compliance exercise.

## Pillar mapping

| Pillar | This pattern's position |
|---|---|
| Security | Single control (no ingress rule) instead of defense-in-depth. See "The single-control tradeoff" below — this is the pillar most worth reading closely before adapting this repo. |
| Reliability | No redundancy built in (`desired_count` defaults to 0 - the module never defaults to a running state - and there is no multi-AZ auto-scaling). Fine for a low-traffic, small-audience app; wrong for anything with an SLA. |
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

**Egress is unrestricted, and that's a real residual risk this pattern does not
close.** The security group's egress rule is `0.0.0.0/0`, all protocols — needed for the
tunnel and image pulls, but it also means a compromised app container has unrestricted
outbound access for data exfiltration or reaching a command-and-control host. "Zero
inbound" is a claim about the ingress side only; nothing here restricts what a
compromised container can reach outbound. A stricter variant would scope egress to
Cloudflare's published IP ranges plus the container registry, at the cost of needing to
track and update that allow-list.

## Identity

Two identity providers (GitHub, Google) registered once, account-wide, and explicitly
referenced by every app's Access application via `allowed_idps` — an earlier version of
this module omitted that argument, which meant Cloudflare defaulted the application to
*every* IdP configured on the account, not just these two; fixed once caught during a
doubt-driven-development review. This is a deliberate broadening from a single-IdP
design: it trades "one login system to reason about" for "works for people who don't
have a GitHub account."

Each app's Access application is gated by **two separate policies**, not one, because
"exact email, any IdP" and "domain match, Google only" need different enforcement:
an exact-email policy (`include { email = ... }`, either IdP) and, if a Google Workspace
domain is configured, a second policy (`include { email_domain = ... }` combined with
`require { login_method = [google_idp_id] }`) — the `require` block is what actually
restricts the domain match to users who authenticated via Google specifically. An
earlier version put both criteria in one policy with no IdP restriction on the domain
match at all, which meant a matching email domain authenticated through *any* IdP would
have satisfied it; also fixed during review, since Cloudflare's `email_domain` criterion
is IdP-agnostic by itself and has to be paired with `require` to add that restriction.

GitHub Actions gets no long-lived AWS credentials at all. The trust policy on each app's
deploy role restricts `sts:AssumeRoleWithWebIdentity` to one `owner/repo` pushing to
`main`, via an exact (`StringEquals`, not `StringLike`) match on the OIDC token's `sub`
claim — a leaked repo secret can't be used to assume a different app's role, and there's
no access key to rotate or accidentally commit. Known limitation, disclosed rather than
silently assumed away: this trust follows the repo's current *name*, not an immutable
repository ID — if the repo is renamed or transferred and the old name gets claimed by a
different owner, the trust follows the name.

## State

This repo ships with no Terraform backend configured — see `infra/terraform/versions.tf`
— and is not wired to any shared state bucket, remote-state data source, or other
private infrastructure. Every module `source =` in this codebase is a local relative
path. That is deliberate: this repo is meant to stand alone, readable and runnable
(as far as `validate`) with nothing outside itself. Before applying anywhere real,
configure a remote backend with locking (S3 + native
locking on Terraform >= 1.10, Terraform Cloud, or your org's existing convention) so two
people (or two agent sessions) can't race a plan/apply against the same state and corrupt
it. This is not a hypothetical: shared-state races that clobber live infrastructure are a
real, recurring failure mode with local or unlocked state, not a theoretical risk being
mentioned for completeness.

**Separately, state contains real secrets in plaintext and needs an encrypted, access-
controlled backend for that reason too, not just locking.** The Cloudflare OAuth client
secrets (`access.tf`'s `github_oauth_client_secret`/`google_oauth_client_secret`), the
per-app tunnel secret, and the per-app tunnel token all land in ordinary Terraform state
as resource attributes. Marking the corresponding variables `sensitive = true` only
redacts CLI/plan output — it does nothing to protect the state file itself. Whatever
backend gets configured (S3 with SSE + a restrictive bucket policy, Terraform Cloud,
etc.) must be chosen with this in mind, not just for locking.

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

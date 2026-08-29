# Architecture: Zero-Inbound Network

## Overview

The problem this solves: host a small number of apps that must be reachable by a small,
named set of people, and unreachable by anyone else, without a second AWS account, a VPN
client, or a bespoke reverse proxy to operate. The answer is to remove the inbound path
entirely rather than defend it — every hosted app's only network exposure is an
outbound-initiated Cloudflare Tunnel, gated by Cloudflare Access before any request ever
reaches AWS.

Rationale in one sentence: **confidentiality here comes from having nothing to attack, not
from attack-resistant infrastructure** — there is no listening inbound port to scan,
rate-limit, or exploit, because none exists.

## Components

| Component | Resource(s) | Role |
|---|---|---|
| Compute | `aws_ecs_task_definition`, `aws_ecs_service` (Fargate) | Runs the app container + `cloudflared` sidecar in one task, sharing a network namespace |
| Network | `aws_vpc`, public `aws_subnet`, `aws_security_group` (zero ingress) | Public subnet, no NAT — nothing needs an inbound path, so none exists |
| Tunnel | `cloudflare_zero_trust_tunnel_cloudflared`, `..._config`, `cloudflare_record` | The only path a request can take from the internet into the task |
| Auth edge | `cloudflare_zero_trust_access_application`, `..._policy`, `..._identity_provider` (GitHub + Google) | Gates the tunnel hostname behind SSO before Cloudflare ever proxies to the tunnel |
| CI identity | `aws_iam_openid_connect_provider`, per-app `aws_iam_role` (deploy) | GitHub Actions gets short-lived STS credentials scoped to one repo — no long-lived AWS keys |
| Secrets | `aws_ssm_parameter` (SecureString) | Tunnel token and app secrets, read only by the task's execution role |
| Reuse unit | `infra/terraform/modules/hosted-app/` | Everything above except the two account-wide identity providers, as one module — a second app is one more `module` block in `main.tf` |

## Data Flow

1. A person hits `<app>.<base_domain>`. Cloudflare's edge terminates TLS and checks
   Access before anything reaches AWS.
2. Access evaluates the request against the app's policy: does this person's GitHub or
   Google identity match the allow-list? If not, they never get further than Cloudflare's
   own login page — no AWS resource has been touched.
3. If allowed, Cloudflare proxies the request through the Tunnel to the `cloudflared`
   sidecar, which is the only process inside the task with any network exposure at all
   (an outbound connection it opened itself).
4. `cloudflared` forwards to the app container over `localhost` inside the task's shared
   `awsvpc` network namespace — this hop never touches the security group, because it
   isn't a network hop the SG's rules apply to.
5. The app responds; the path reverses. At no point does an inbound rule get evaluated,
   because none exists.

## Design Decisions

See [decisions.md](decisions.md) for the ADR log — in particular the zero-inbound-vs-NAT
tradeoff, the dual-IdP choice, and why the reusable module is scoped the way it is.

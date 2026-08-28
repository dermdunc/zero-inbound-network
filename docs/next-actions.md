# Next Actions: Zero-Inbound Network

## Immediate

- [x] Define project brief (this repo's own `docs/architecture.md` "Overview")
- [x] Record first design decisions in `docs/decisions.md`
- [x] Write root + `modules/hosted-app/` Terraform, `terraform validate`-clean
- [x] Write `docs/well-architected.md` (tradeoffs, cost, security posture)
- [ ] Human: create the `dermdunc/zero-inbound-network` GitHub remote and push, when ready
      to make this public (not done yet — local commit only, per this session's scope)
- [ ] Human: register real GitHub + Google OAuth apps and a real Cloudflare zone before
      ever running `terraform plan` against real infrastructure

## This Week

- Cited from a `theagentictekton.com` post about the rationale/reuse pattern this repo
  demonstrates

## Later

- Consider a GitHub Actions workflow example (`.github/workflows/deploy.yml`) showing the
  OIDC-based deploy role actually being assumed, as a second, CI-side artefact
- Consider a `scripts/plan-summary.sh`-style GREEN/AMBER/RED classifier
  (`agentic-infra-lab/patterns/*/`'s human-apply-gate convention) if this repo ever needs
  a real apply workflow rather than staying a read-only reference

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
- [ ] Human: `git add infra/terraform/.terraform.lock.hcl && git commit` — dropped from
      tracking in an earlier commit, still present on disk but untracked; agents can't
      commit it themselves (`infra/**` is a protected path). Until this lands,
      `docs/setup.md`'s provider-pinning note applies (a fresh clone resolves versions
      fresh within `versions.tf`'s ranges, not necessarily identical to what was tested).
- [ ] Address the Open Source Council's one real finding (`docs/oss-council/
      2026-08-29-review.md`, action item 1): the "reuse story made literal" claim is
      validated once, not demonstrated twice — either soften the claim or add a real
      second module instantiation (rename `app.tf.example` to a real `.tf` file).

## This Week

- Cited from a `theagentictekton.com` post about the rationale/reuse pattern this repo
  demonstrates

## Later

- Consider a GitHub Actions workflow example (`.github/workflows/deploy.yml`) showing the
  OIDC-based deploy role actually being assumed, as a second, CI-side artefact
- Consider a `scripts/plan-summary.sh`-style GREEN/AMBER/RED classifier
  (`agentic-infra-lab/patterns/*/`'s human-apply-gate convention) if this repo ever needs
  a real apply workflow rather than staying a read-only reference

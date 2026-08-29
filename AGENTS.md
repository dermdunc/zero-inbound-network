# Agent Context: Zero-Inbound Network

A public, sanitized reference implementation of a zero-inbound AWS network fronted by Cloudflare Access, with GitHub+Google SSO and per-app Terraform module reuse

## Working in this repo

- Work on a short-lived branch; never commit directly to `main`.
- Run the verification entry point before opening a PR:
  ```bash
  bash scripts/check-prereqs.sh
  cd infra/terraform && terraform init -backend=false && terraform validate
  ```
  (`scripts/verify-project.sh` is gitignored - it exists in this local working tree
  but is not tracked, and will not be present in a real clone of this repo. It also
  checks for `docs/local-assumptions.md`/`docs/reproducibility.md`, neither of which
  exists in this repo, so it fails even locally. Do not reference it in reader-facing
  docs, and do not run it as a verification step.)
- Keep changes scoped to what was asked; note assumptions in the PR description.

## Conventions

- Document decisions in `docs/decisions.md`.
- Update `docs/next-actions.md` when you finish or discover work.
- Tests and docs ship with the change, not after it.

<!-- This repo is public. It is developed inside a private factory whose internal
     contracts, ledgers and vault mirror live outside this tree; nothing here depends
     on them, and this file is deliberately self-contained. -->

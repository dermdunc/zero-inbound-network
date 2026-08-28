# Agent Context: Zero-Inbound Network

A public, sanitized reference implementation of a zero-inbound AWS network fronted by Cloudflare Access, with GitHub+Google SSO and per-app Terraform module reuse

## Working in this repo

- Work on a short-lived branch; never commit directly to `main`.
- Run the verification entry point before opening a PR:
  ```bash
  bash scripts/check-prereqs.sh && bash scripts/verify-project.sh
  ```
- Keep changes scoped to what was asked; note assumptions in the PR description.

## Conventions

- Document decisions in `docs/decisions.md`.
- Update `docs/next-actions.md` when you finish or discover work.
- Tests and docs ship with the change, not after it.

<!-- This repo is public. It is developed inside a private factory whose internal
     contracts, ledgers and vault mirror live outside this tree; nothing here depends
     on them, and this file is deliberately self-contained. -->

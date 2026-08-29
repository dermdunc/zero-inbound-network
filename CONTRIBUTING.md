# Contributing

Thanks for looking at this repo. It's a reference implementation, not a product — the
bar for a change is "does this make the pattern clearer or more correct," not "does
this add a feature."

## Before opening a PR

- For anything beyond a typo fix, open an issue first describing the problem or the
  gap you're proposing to close. Saves both of us a rewritten PR.
- Security findings: open an issue like any other finding. There's no deployed
  instance of this pattern behind this repo — it ships with no backend configured and
  has never been applied — so there's no live target to disclose privately against.
  If you're reporting a defect in your own deployment based on this pattern, that's a
  vulnerability in your infrastructure, not this repo's; open an issue anyway if the
  pattern itself is what's wrong.

## What a good PR looks like here

- `terraform fmt` and `terraform validate` pass with no credentials configured
  (`cd infra/terraform && terraform init -backend=false && terraform validate`).
- Changes to the reusable module (`infra/terraform/modules/hosted-app/`) come with a one-line
  explanation of what they change for every existing caller, not just the new one.
- Docs (`docs/architecture.md`, `docs/well-architected.md`, `docs/decisions.md`)
  updated in the same PR as the code they describe, not as a follow-up.
- If you're fixing a tradeoff this repo made on purpose (documented in
  `docs/well-architected.md`), say so explicitly and explain what changed your mind —
  don't silently "fix" a documented, deliberate choice.

## Solo maintainer, honestly

This repo has one maintainer, working on it as time allows alongside everything else.
Response times on issues and PRs will be irregular, sometimes slow. That's not a
reflection on how much a contribution is valued — just the actual capacity available.
If something's been quiet for a while, a polite bump is welcome, not annoying.

## Code of Conduct

This project follows [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

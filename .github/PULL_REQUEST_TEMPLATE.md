## What this changes and why

## Checklist

- [ ] `cd infra/terraform && terraform init -backend=false && terraform validate` passes
- [ ] `terraform fmt -recursive -check` passes
- [ ] Docs (`docs/architecture.md`, `docs/well-architected.md`, `docs/decisions.md`)
      updated if this changes behavior, a tradeoff, or a resource's shape
- [ ] If this touches `infra/terraform/modules/hosted-app/`, the impact on its one real
      caller (`infra/terraform/main.tf`'s `example_app` module block) is noted, and
      `infra/terraform/app.tf.example` (a template, never loaded by Terraform) is kept
      in sync if the change affects it
- [ ] No real credentials, account IDs, or domain names introduced anywhere

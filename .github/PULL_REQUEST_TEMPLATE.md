## What this changes and why

## Checklist

- [ ] `cd infra/terraform && terraform init -backend=false && terraform validate` passes
- [ ] `terraform fmt -recursive -check` passes
- [ ] Docs (`docs/architecture.md`, `docs/well-architected.md`, `docs/decisions.md`)
      updated if this changes behavior, a tradeoff, or a resource's shape
- [ ] If this touches `modules/hosted-app/`, the impact on every existing caller
      (`main.tf`'s `example_app`, `app.tf.example`) is noted
- [ ] No real credentials, account IDs, or domain names introduced anywhere

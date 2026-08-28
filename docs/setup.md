# Setup

This repo ships Terraform, not an application to install — "setup" here means getting
to a clean `terraform validate` with no credentials, which is also as far as CI or a
casual reader needs to go without deploying anything real.

```bash
cd infra/terraform
terraform init -backend=false
terraform validate
```

Both commands run with no AWS or Cloudflare credentials and make no network calls
beyond fetching the pinned providers. See the root [README](../README.md)'s Quick
Start for the next steps (`terraform plan`/`apply`) if you intend to actually deploy
this — read [`docs/well-architected.md`](well-architected.md) first.

`scripts/check-prereqs.sh` and `scripts/bootstrap-project.sh` are generic scaffolding
leftovers that check the repo layout itself, not anything Terraform-specific - useful
as a sanity check, not required reading:

```bash
./scripts/check-prereqs.sh
```


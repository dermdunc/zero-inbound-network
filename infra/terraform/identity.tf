# --- GitHub Actions OIDC: short-lived STS credentials, no long-lived AWS keys --
#
# The OIDC provider is an account-wide singleton (one per issuer URL per AWS
# account) — hence the create_github_oidc_provider escape hatch. Each app's
# deploy role (declared inside the hosted-app module) trusts this provider and
# scopes sts:AssumeRoleWithWebIdentity to its own repo via the OIDC token's
# `sub` claim.

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [] # AWS no longer validates this for GitHub's provider; kept empty on purpose.
}

data "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : data.aws_iam_openid_connect_provider.github_actions[0].arn
}

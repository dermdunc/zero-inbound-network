# --- Cloudflare Access identity providers: registered once, shared by every ---
# --- hosted app's Access policy (declared per-app inside the module) ----------
#
# Two parallel IdPs, either one gets a user through: GitHub OAuth (for a
# developer-tooling audience) and Google OAuth (for anyone else). Access
# evaluates whichever IdP the user picks against the per-app policy's
# `include` blocks — see the hosted-app module's access.tf for how
# allowed_emails / allowed_google_domain map onto that.
#
# These names ("GitHub", "Google") are not guaranteed unique or collision-free: if
# the target Cloudflare account already has identity providers configured under
# these names, this either fails on apply or creates unmanaged duplicates. Import
# the existing resources instead of applying blind if that's the situation.

resource "cloudflare_zero_trust_access_identity_provider" "github" {
  account_id = var.cloudflare_account_id
  name       = "GitHub"
  type       = "github"

  config {
    client_id     = var.github_oauth_client_id
    client_secret = var.github_oauth_client_secret
  }
}

resource "cloudflare_zero_trust_access_identity_provider" "google" {
  account_id = var.cloudflare_account_id
  name       = "Google"
  type       = "google"

  config {
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  }
}

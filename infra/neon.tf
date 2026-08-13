# Creates the Neon project this app's database lives in. Deliberately stops there: the
# kislerdm/neon provider can create projects/branches/databases/roles, but it cannot run SQL
# (no GRANT, no CREATE SCHEMA, no ALTER DEFAULT PRIVILEGES) — and a neon_role resource's
# password is a provider-generated, read-only attribute that Terraform has no choice but to
# store in state. Creating the app's real db_owner/svc_user roles that way would put their
# production passwords in tfstate permanently.
#
# So this stack only creates the project, which comes with one throwaway bootstrap role
# (local.neon_bootstrap_role) that Neon generates a password for regardless — that password
# does land in state, but it's not a credential the app ever uses. Run infra/neon-init.sql
# once, by hand, connected as that bootstrap role, to create the real roles/schema/grants
# with passwords that never touch Terraform. See infra/README.md, "Neon bootstrap".

resource "neon_project" "main" {
  name       = local.app_name
  region_id  = local.neon_region_id
  pg_version = local.neon_pg_version

  branch {
    name          = "production"
    database_name = "${local.app_name_snake}_db"
    role_name     = local.neon_bootstrap_role
  }

  # Point-in-time restore isn't in scope for this template (see infra/README.md — Out of
  # scope). Keeping it off caps Neon storage-tier billing.
  history_retention_seconds = 0
}

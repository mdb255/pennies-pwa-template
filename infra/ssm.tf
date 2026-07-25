# The SSM tree is how the GitHub Actions workflows discover what this stack built. Values the
# stack knows are written here directly; secrets it must not know are created empty and filled
# out of band.
#
# Note the asymmetry with the Lambda environment: the functions get their config as env vars
# straight from resource attributes, so the SSM tree is for *deploy-time* consumers (CI), not
# for the running app. The one exception is RUNTIME_DB_URL, which the app reads from here at
# cold start precisely so it never lands in an env var or in tofu state.

# --- Written by this stack ----------------------------------------------------------------

resource "aws_ssm_parameter" "app_env" {
  name  = "${local.ssm_prefix}/APP_ENV"
  type  = "String"
  value = "prod"
}

resource "aws_ssm_parameter" "user_pool_id" {
  name  = "${local.ssm_prefix}/USER_POOL_ID"
  type  = "String"
  value = aws_cognito_user_pool.main.id
}

resource "aws_ssm_parameter" "app_client_id" {
  name  = "${local.ssm_prefix}/APP_CLIENT_ID"
  type  = "String"
  value = aws_cognito_user_pool_client.app.id
}

resource "aws_ssm_parameter" "cors_origins" {
  name  = "${local.ssm_prefix}/CORS_ORIGINS"
  type  = "String"
  value = local.pwa_origin
}

resource "aws_ssm_parameter" "api_lambda_function_name" {
  name  = "${local.ssm_prefix}/API_LAMBDA_FUNCTION_NAME"
  type  = "String"
  value = aws_lambda_function.api.function_name
}

resource "aws_ssm_parameter" "auth_lambda_function_name" {
  name  = "${local.ssm_prefix}/AUTH_LAMBDA_FUNCTION_NAME"
  type  = "String"
  value = aws_lambda_function.auth.function_name
}

# Baked into the frontend bundle as VITE_API_BASE. The trailing slash on a Function URL would
# produce "//todos/" once the client joins paths, so trim it.
resource "aws_ssm_parameter" "pwa_api_base" {
  name  = "${local.ssm_prefix}/PWA_API_BASE"
  type  = "String"
  value = trimsuffix(aws_lambda_function_url.api.function_url, "/")
}

resource "aws_ssm_parameter" "pwa_s3_bucket" {
  name  = "${local.ssm_prefix}/PWA_S3_BUCKET"
  type  = "String"
  value = aws_s3_bucket.pwa.bucket
}

resource "aws_ssm_parameter" "pwa_cloudfront_distribution_id" {
  name  = "${local.ssm_prefix}/PWA_CLOUDFRONT_DISTRIBUTION_ID"
  type  = "String"
  value = aws_cloudfront_distribution.pwa.id
}

# --- Created empty, filled out of band ----------------------------------------------------
#
# Neon connection strings. This stack creates the parameters so IAM policies and the app's
# RUNTIME_DB_URL_SSM_PATH have something to point at, but never learns their values:
# ignore_changes on `value` means the real secret you put here by hand is never read back,
# never diffed, and never written to tofu state.
#
# Fill them with (see infra/README.md):
#   aws ssm put-parameter --name <name> --type SecureString --overwrite --value '<url>'

resource "aws_ssm_parameter" "runtime_db_url" {
  name        = "${local.ssm_prefix}/RUNTIME_DB_URL"
  description = "Neon connection string for the app runtime (svc_user, DML only)"
  type        = "SecureString"
  value       = "PLACEHOLDER - set out of band, see infra/README.md"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "migrations_db_url" {
  name        = "${local.ssm_prefix}/MIGRATIONS_DB_URL"
  description = "Neon connection string for Alembic migrations (db_owner, DDL)"
  type        = "SecureString"
  value       = "PLACEHOLDER - set out of band, see infra/README.md"

  lifecycle {
    ignore_changes = [value]
  }
}

# Deliberately not created: APP_DOMAIN (nothing reads it since the TMB refactor made the
# session cookie host-only) and SESSION_TOKEN_ENCRYPTION_KEY (refresh-token-at-rest
# encryption is off for v1).

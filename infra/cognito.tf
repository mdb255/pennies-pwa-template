resource "aws_cognito_user_pool" "main" {
  name = "${local.app_name}-users"

  # Email is the sign-in identifier; there is no separate username.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  mfa_configuration   = "OFF"
  user_pool_tier      = "ESSENTIALS"
  deletion_protection = "ACTIVE"

  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # Self-service signup: /auth/signup/ calls SignUp directly.
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }

  # COGNITO_DEFAULT is capped at 50 emails/day and is fine for a template. Switch to
  # DEVELOPER (SES) before any real traffic.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # Changing `schema` forces a new user pool, which would orphan every existing account.
  lifecycle {
    ignore_changes = [schema]
  }
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${local.app_name}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Public client: the auth Lambda holds no secret, it authenticates to Cognito with its
  # execution role's SigV4 credentials.
  generate_secret = false

  # ADMIN_USER_PASSWORD_AUTH backs /auth/login/ (AdminInitiateAuth); REFRESH_TOKEN_AUTH backs
  # /auth/resume/ (InitiateAuth). No SRP, no hosted UI.
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Required for /auth/logout/, which calls RevokeToken on the stored refresh token.
  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"

  # ADR 0001 accepts that the access token reaches the browser and is XSS-stealable for its
  # lifetime; a short TTL is the stated mitigation. /auth/resume/ re-mints silently from the
  # server-side session, so users never see the expiry.
  #
  # The refresh token is the real ceiling on session length: it lives only in the `sessions`
  # table, and once Cognito expires it, /auth/resume/ fails even though the session row and
  # cookie are still valid. So this must match SESSION_RESUME_COOKIE_TTL (30 days) rather
  # than the 5 days sketched in the IaC plan — see infra/README.md.
  access_token_validity  = 15
  id_token_validity      = 15
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Deliberately omitted: callback_urls, logout_urls, allowed_oauth_flows,
  # allowed_oauth_scopes, supported_identity_providers, and a Cognito hosted-UI domain.
  # Auth is entirely API-brokered through the auth Lambda (ADR 0001 §5).
}

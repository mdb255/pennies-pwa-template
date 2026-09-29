# Two functions, one image. APP_COMPONENT selects which routers create_app() mounts, so the
# auth surface and the data surface get separate execution roles, separate Function URL auth
# models, and separate log groups without a second codebase or build pipeline (ADR 0001 §3).

locals {
  image_uri = "${aws_ecr_repository.api.repository_url}:latest"

  # AWS_REGION is intentionally absent: Lambda injects it as a reserved environment variable
  # and rejects any attempt to set it. Settings.aws_region picks it up from there.
  #
  # CORS_ORIGINS is also absent: deployed, the api component's CORS lives on the Function URL
  # below and the auth component is same-origin, so nothing in the app reads it in prod. It
  # stays in the SSM tree for the frontend build.
  common_env = {
    APP_ENV                 = "prod"
    USER_POOL_ID            = aws_cognito_user_pool.main.id
    APP_CLIENT_ID           = aws_cognito_user_pool_client.app.id
    JWKS_CACHE_TTL          = "3600"
    RUNTIME_DB_URL_SSM_PATH = "${local.ssm_prefix}/RUNTIME_DB_URL"
  }
}

# --- api: public Function URL, Bearer-validated -------------------------------------------

resource "aws_lambda_function" "api" {
  function_name = local.api_function_name
  role          = aws_iam_role.api_exec.arn
  package_type  = "Image"
  image_uri     = local.image_uri
  memory_size   = local.lambda_memory
  timeout       = local.lambda_timeout

  environment {
    variables = merge(local.common_env, {
      APP_COMPONENT = "api"
    })
  }

  # The deploy workflow owns the image tag from here on — it pushes :<sha> and calls
  # update-function-code. Without this, every apply would try to drag the function back to
  # :latest and fight CI.
  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [aws_iam_role_policy.api_ssm, terraform_data.seed_image]
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.api_function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"

  # The single source of CORS truth for the data plane. This layer answers preflights without
  # invoking the function, so the app deliberately does not add CORSMiddleware in prod.
  cors {
    allow_origins = [local.pwa_origin]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    allow_headers = ["authorization", "content-type"]
    # The browser sends a Bearer token, never a cookie — credentials mode stays off.
    allow_credentials = false
    max_age           = 86400
  }
}

# authorization_type = "NONE" above only turns off IAM auth on the URL itself — Lambda still
# requires a resource policy before it'll let anyone invoke it. Without this, every call
# (including a plain curl) 403s with "Forbidden ... Function URL authorization issues".
resource "aws_lambda_permission" "api_public_url" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# Since Oct 2025, AWS requires lambda:InvokeFunction in addition to lambda:InvokeFunctionUrl
# for every Function URL (existing NONE-auth URLs get a grace period until 2026-11-01, but any
# newly created URL needs both immediately). invoked_via_function_url scopes the grant to calls
# made through the Function URL, not the raw Invoke API — see
# docs/plans/aws-provider-6-upgrade-plan.md for the full diagnosis and why this needed a
# provider bump (the equivalent condition isn't expressible on provider 5.x).
resource "aws_lambda_permission" "api_public_url_invoke" {
  statement_id             = "AllowPublicFunctionUrlInvokeFunction"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.api.function_name
  principal                = "*"
  invoked_via_function_url = true
}

# --- auth: IAM-authorized Function URL, reachable only through CloudFront ------------------

resource "aws_lambda_function" "auth" {
  function_name = local.auth_function_name
  role          = aws_iam_role.auth_exec.arn
  package_type  = "Image"
  image_uri     = local.image_uri
  memory_size   = local.lambda_memory
  timeout       = local.lambda_timeout

  environment {
    variables = merge(local.common_env, {
      APP_COMPONENT             = "auth"
      SESSION_RESUME_COOKIE_TTL = "2592000" # 30 days; must not exceed the Cognito refresh token validity
    })
  }

  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [aws_iam_role_policy.auth_ssm, terraform_data.seed_image]
}

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/aws/lambda/${local.auth_function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function_url" "auth" {
  function_name      = aws_lambda_function.auth.function_name
  authorization_type = "AWS_IAM"
  invoke_mode        = "BUFFERED"

  # No cors block: this URL is only ever called by CloudFront, which serves it same-origin
  # with the PWA under /auth/*. A direct browser request would fail SigV4 anyway.
}

# Only this distribution may invoke the auth URL. A direct curl to the Function URL gets 403.
resource "aws_lambda_permission" "auth_from_cloudfront" {
  statement_id           = "AllowCloudFrontOacInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.auth.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.pwa.arn
  function_url_auth_type = "AWS_IAM"
}

# Same Oct-2025 AWS requirement as api_public_url_invoke above. Easy to miss because this URL
# is IAM-authorized, not public — but AuthType AWS_IAM needs both actions too (see
# docs/plans/aws-provider-6-upgrade-plan.md), and this path has no test coverage that would
# have caught the gap since the container never ran until the uv fix shipped.
resource "aws_lambda_permission" "auth_from_cloudfront_invoke" {
  statement_id             = "AllowCloudFrontOacInvokeFunction"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.auth.function_name
  principal                = "cloudfront.amazonaws.com"
  source_arn               = aws_cloudfront_distribution.pwa.arn
  invoked_via_function_url = true
}

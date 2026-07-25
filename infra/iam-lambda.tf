# One execution role per function. The api function never talks to Cognito's admin APIs and
# the auth function is the only thing that can revoke tokens or create users, so splitting the
# roles means an XSS or injection bug in the data plane cannot reach the identity plane.

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Both functions resolve RUNTIME_DB_URL from SSM at cold start (see app/db.py), which is why
# neither has the connection string in its environment.
data "aws_iam_policy_document" "ssm_read" {
  statement {
    sid    = "ReadProdParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["arn:aws:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*"]
  }
}

# --- api function ------------------------------------------------------------------------

resource "aws_iam_role" "api_exec" {
  name               = "${local.app_name_snake}_api_exec"
  description        = "Execution role for the ${local.app_name} api Lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "api_logs" {
  role       = aws_iam_role.api_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_ssm" {
  name   = "${local.app_name_snake}_api_ssm_read"
  role   = aws_iam_role.api_exec.id
  policy = data.aws_iam_policy_document.ssm_read.json
}

# The api function needs no Cognito and no database IAM: Neon is reached over the network with
# a connection string, and JWT validation is an unauthenticated HTTPS fetch of Cognito's JWKS.

# --- auth function -----------------------------------------------------------------------

resource "aws_iam_role" "auth_exec" {
  name               = "${local.app_name_snake}_auth_exec"
  description        = "Execution role for the ${local.app_name} auth Lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "auth_logs" {
  role       = aws_iam_role.auth_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "auth_ssm" {
  name   = "${local.app_name_snake}_auth_ssm_read"
  role   = aws_iam_role.auth_exec.id
  policy = data.aws_iam_policy_document.ssm_read.json
}

data "aws_iam_policy_document" "auth_cognito" {
  statement {
    sid    = "BrokerCognitoAuth"
    effect = "Allow"
    actions = [
      "cognito-idp:AdminInitiateAuth", # /auth/login/
      "cognito-idp:InitiateAuth",      # /auth/resume/ (REFRESH_TOKEN_AUTH)
      "cognito-idp:SignUp",            # /auth/signup/
      "cognito-idp:ConfirmSignUp",     # /auth/confirm-signup/
      "cognito-idp:RevokeToken",       # /auth/logout/
    ]
    resources = [aws_cognito_user_pool.main.arn]
  }
}

resource "aws_iam_role_policy" "auth_cognito" {
  name   = "${local.app_name_snake}_auth_cognito"
  role   = aws_iam_role.auth_exec.id
  policy = data.aws_iam_policy_document.auth_cognito.json
}

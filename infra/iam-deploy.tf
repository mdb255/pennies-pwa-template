# The role GitHub Actions assumes via OIDC. Deliberately least-privilege: it can push images,
# re-point the two functions at a new image, read the prod SSM tree, and publish the PWA. It
# cannot create or modify infrastructure — that is a human/admin operation (infra/README.md).

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Pinned to main of this one repository. Without the `sub` condition, any repo in any
    # GitHub org could assume this role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${local.app_name_snake}_deploy"
  description        = "GitHub Actions deploy role for ${local.app_name} (OIDC)"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
}

data "aws_iam_policy_document" "deploy" {
  # ECR login. GetAuthorizationToken is account-scoped and cannot be narrowed to a repository.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.api.arn]
  }

  # Swap the image on both functions. Notably absent: UpdateFunctionConfiguration — env vars
  # and memory are owned by this stack, not by CI.
  statement {
    sid    = "LambdaDeploy"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:UpdateFunctionCode",
    ]
    resources = [
      "arn:aws:lambda:${local.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.api_function_name}",
      "arn:aws:lambda:${local.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.auth_function_name}",
    ]
  }

  # Both workflows read their deploy-time config from here; the backend workflow also reads
  # MIGRATIONS_DB_URL to run Alembic.
  statement {
    sid    = "SsmRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = ["arn:aws:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*"]
  }

  statement {
    sid       = "PwaBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.pwa.arn]
  }

  statement {
    sid    = "PwaBucketObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.pwa.arn}/*"]
  }

  # Scoped to the account rather than the specific distribution: the distribution is created
  # in a later apply than this role (see the apply sequence), and referencing it here would
  # force CloudFront to be built before an image exists. CreateInvalidation cannot read or
  # mutate content, so the widened resource is low-consequence.
  statement {
    sid       = "PwaInvalidate"
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = ["arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${local.app_name_snake}_deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

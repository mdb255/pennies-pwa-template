terraform {
  # 1.10 is the floor for native S3 state locking (use_lockfile) — no DynamoDB table needed.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 5.90+ for aws_cognito_user_pool.user_pool_tier. Bumping to 6.x is fine but
      # unverified against this config — read the provider upgrade guide first.
      version = "~> 5.90"
    }
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.15"
    }
  }

  # Created once, before the first apply — see infra/README.md ("State bucket bootstrap").
  backend "s3" {
    bucket       = "<{{ app_name }}>-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "<{{ aws_region }}>"
    encrypt      = true
    use_lockfile = true
  }
}

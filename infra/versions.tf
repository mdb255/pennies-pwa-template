terraform {
  # 1.10 is the floor for native S3 state locking (use_lockfile) — no DynamoDB table needed.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.28+ for invoked_via_function_url on aws_lambda_permission — required to scope the
      # lambda:InvokeFunction grant Function URLs need since Oct 2025 (see docs/plans/
      # aws-provider-6-upgrade-plan.md). Verified against this config on tmpl-test-2: no
      # breaking changes apply to any of our 22 resource types except additive
      # `region`/`bucket_region` noise, and `tofu plan` after the bump showed zero diff.
      version = "~> 6.28"
    }
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.15"
    }
    # Runs `gh api` to read the repo's OIDC subject-claim prefix — see data.tf.
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
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

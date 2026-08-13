# All configuration for this stack is stamped in by bootstrap.py from bootstrap.config.yaml.
# There are deliberately no variables and no terraform.tfvars: the template renders once, and
# the result is a concrete, readable config for exactly one project.

locals {
  app_name       = "<{{ app_name }}>"
  app_name_snake = "<{{ app_name_snake }}>"
  aws_region     = "<{{ aws_region }}>"
  root_domain    = "<{{ root_domain }}>"
  github_repo    = "<{{ github_repo }}>"
  lambda_memory  = <{{ lambda_memory }}>
  neon_region_id = "<{{ neon_region_id }}>"

  # Matches the postgres image tag in docker-compose.local.yml. Bumping either one without
  # the other means local dev and Neon are running different major versions.
  neon_pg_version = 16

  # Temporary role Neon provisions with the project. Only used once, to connect and run
  # infra/neon-init.sql — the app's real db_owner/svc_user roles come out of that script,
  # never out of this stack. See neon.tf.
  neon_bootstrap_role = "${local.app_name_snake}_bootstrap"

  # The PWA's public hostname. Keyed by app_name (not a fixed "app" label) so multiple apps
  # sharing the same root_domain get distinct subdomains instead of colliding on app.<domain>.
  # Flows through ACM, CloudFront aliases, Route53, CORS, and the SSM tree.
  pwa_host   = "${local.app_name}.${local.root_domain}"
  pwa_origin = "https://${local.pwa_host}"

  ssm_prefix = "/${local.app_name}/prod"

  # Function names are fixed rather than read back off the resources so that IAM can be
  # applied before the functions exist — the Lambdas can't be created until an image has been
  # pushed, and the deploy role is what pushes it. See the apply sequence in infra/README.md.
  api_function_name  = "${local.app_name}-api"
  auth_function_name = "${local.app_name}-auth"

  # Lambda Web Adapter boots uvicorn and answers the readiness probe before the first
  # request, so cold starts are slower than a native handler. 30s leaves room for that plus
  # the SSM fetch for the DB connection string.
  lambda_timeout = 30

  tags = {
    Project   = "<{{ app_name }}>"
    ManagedBy = "OpenTofu"
    Env       = "prod"
  }
}

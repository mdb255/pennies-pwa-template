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

  # The PWA's public hostname. Change the "app" label here if you want a different subdomain;
  # it flows through ACM, CloudFront aliases, Route53, CORS, and the SSM tree.
  pwa_host   = "app.${local.root_domain}"
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

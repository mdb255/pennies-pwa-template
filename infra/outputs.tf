output "pwa_url" {
  description = "Public URL of the PWA"
  value       = local.pwa_origin
}

output "api_function_url" {
  description = "Public Function URL of the api component (VITE_API_BASE)"
  value       = trimsuffix(aws_lambda_function_url.api.function_url, "/")
}

output "auth_function_url" {
  description = "Function URL of the auth component. IAM-authorized — only CloudFront can invoke it, so a direct request returns 403. Reachable publicly under /auth/* on the PWA origin."
  value       = aws_lambda_function_url.auth.function_url
}

output "ecr_repository_url" {
  description = "ECR repository both functions run from"
  value       = aws_ecr_repository.api.repository_url
}

output "deploy_role_arn" {
  description = "Role assumed by GitHub Actions via OIDC"
  value       = aws_iam_role.deploy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.app.id
}

output "pwa_bucket" {
  value = aws_s3_bucket.pwa.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.pwa.id
}

output "neon_project_id" {
  value = neon_project.main.id
}

# Only used once, to run infra/neon-init.sql (see infra/README.md — "Neon bootstrap").
# Marked sensitive so it doesn't print during a normal `tofu apply`/`tofu output`; fetch it
# explicitly with `tofu output -raw neon_bootstrap_connection_uri` when you need it.
output "neon_bootstrap_connection_uri" {
  value     = neon_project.main.connection_uri
  sensitive = true
}

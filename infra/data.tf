data "aws_caller_identity" "current" {}

# The GitHub Actions OIDC provider is account-wide and typically already exists. If this is a
# fresh account, create it once (see infra/README.md) rather than managing it here — deleting
# it via this stack would break every other repo that federates into the account.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# The public hosted zone for root_domain must already exist (domain registration and
# delegation are out of scope for this stack).
data "aws_route53_zone" "root" {
  name         = "${local.root_domain}."
  private_zone = false
}

# AWS-managed CloudFront policies — referenced by name so we don't hardcode their IDs.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Forwards every header, cookie and query string EXCEPT Host. Passing the viewer's Host
# header to a Lambda Function URL origin would break its SigV4 signature, so this is the
# correct policy for the /auth/* behavior — not plain Managed-AllViewer.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

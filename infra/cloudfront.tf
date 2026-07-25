# One distribution serves both the PWA and, under /auth/*, the auth Lambda. That co-location
# is the whole point of the TMB design: /auth/* is same-origin with the app, so the session
# cookie is first-party and no cross-site cookie is involved (ADR 0001).

resource "aws_cloudfront_origin_access_control" "pwa_s3" {
  name                              = "${local.app_name}-pwa-s3"
  description                       = "OAC for the ${local.app_name} PWA bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "auth_lambda" {
  name                              = "${local.app_name}-auth-lambda"
  description                       = "OAC for the ${local.app_name} auth Lambda Function URL"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "pwa" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.app_name} PWA + /auth/*"
  default_root_object = "index.html"
  aliases             = [local.pwa_host]

  # North America + Europe only. Add edge locations when there is traffic to justify them.
  price_class = "PriceClass_100"

  origin {
    origin_id                = "pwa-s3"
    domain_name              = aws_s3_bucket.pwa.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.pwa_s3.id
  }

  origin {
    origin_id = "auth-lambda"
    # function_url is "https://<id>.lambda-url.<region>.on.aws/" — CloudFront wants the bare
    # host, so strip the scheme and the trailing slash.
    domain_name              = replace(replace(aws_lambda_function_url.auth.function_url, "https://", ""), "/", "")
    origin_access_control_id = aws_cloudfront_origin_access_control.auth_lambda.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "pwa-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  ordered_cache_behavior {
    path_pattern           = "/auth/*"
    target_origin_id       = "auth-lambda"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Auth responses are per-session and set cookies — caching any of it would be a
    # cross-user data leak.
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id

    # Forwards cookies, Authorization and query strings to the Lambda, but not the viewer's
    # Host header (which would invalidate the SigV4 signature on the Function URL).
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # SPA routing: the bucket has no object for /todos, so S3 returns 403 (or 404) and the
  # router needs index.html to boot and handle the path client-side.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.pwa.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

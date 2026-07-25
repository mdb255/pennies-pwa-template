# CloudFront's hosted zone id is a fixed global constant, not the distribution's own zone.
locals {
  cloudfront_hosted_zone_id = "Z2FDTNDATAQYW2"
}

resource "aws_route53_record" "pwa_a" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.pwa_host
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.pwa.domain_name
    zone_id                = local.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "pwa_aaaa" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = local.pwa_host
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.pwa.domain_name
    zone_id                = local.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

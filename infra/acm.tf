# CloudFront only accepts certificates from us-east-1, hence the aliased provider.

resource "aws_acm_certificate" "pwa" {
  provider = aws.us_east_1

  domain_name       = local.pwa_host
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "pwa_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.pwa.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.root.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Blocks the apply until the certificate is actually issued, so the distribution never
# references a pending cert.
resource "aws_acm_certificate_validation" "pwa" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.pwa.arn
  validation_record_fqdns = [for r in aws_route53_record.pwa_cert_validation : r.fqdn]
}

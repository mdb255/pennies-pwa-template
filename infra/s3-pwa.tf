# The built PWA. Never public — CloudFront reaches it through an Origin Access Control, so
# the only route to an object is through the distribution.

resource "aws_s3_bucket" "pwa" {
  # Bucket names are globally unique; the account id is a deterministic suffix that avoids
  # needing the random provider.
  bucket = "${local.app_name}-prod-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "pwa" {
  bucket = aws_s3_bucket.pwa.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "pwa" {
  bucket = aws_s3_bucket.pwa.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pwa" {
  bucket = aws_s3_bucket.pwa.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "pwa_bucket" {
  statement {
    sid     = "AllowCloudFrontServicePrincipalReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.pwa.arn}/*"]

    # Scoped to this one distribution, so another account's CloudFront cannot read the bucket.
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.pwa.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "pwa" {
  bucket = aws_s3_bucket.pwa.id
  policy = data.aws_iam_policy_document.pwa_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.pwa]
}

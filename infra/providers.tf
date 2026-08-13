provider "aws" {
  region = local.aws_region

  default_tags {
    tags = local.tags
  }
}

# CloudFront requires its ACM certificate to live in us-east-1, regardless of where the
# rest of the stack runs.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

# Reads NEON_API_KEY from the environment — no key is ever written into config or state.
# Generate one at https://console.neon.tech (Account Settings → API Keys).
provider "neon" {}

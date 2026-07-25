#!/usr/bin/env bash
# Create the S3 bucket that holds this stack's OpenTofu state.
#
# Chicken-and-egg: the backend needs the bucket to exist before the first `tofu init`, so the
# bucket cannot be managed by the stack it stores. This script is the one piece of
# click-ops-equivalent bootstrapping, kept in version control so it is at least reproducible.
#
# Safe to re-run — every step is idempotent.
#
# Usage:  ./bootstrap-state.sh [--profile <aws-profile>]

set -euo pipefail

BUCKET="<{{ app_name }}>-tfstate"
REGION="<{{ aws_region }}>"

PROFILE_ARGS=()
if [[ "${1:-}" == "--profile" ]]; then
  PROFILE_ARGS=(--profile "${2:?--profile needs a value}")
fi

aws_() { aws "${PROFILE_ARGS[@]}" "$@"; }

if aws_ s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket s3://${BUCKET} already exists — reconciling settings."
else
  echo "Creating s3://${BUCKET} in ${REGION}..."
  # us-east-1 is the one region that rejects an explicit LocationConstraint.
  if [[ "$REGION" == "us-east-1" ]]; then
    aws_ s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws_ s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
fi

# Versioning is the recovery path for a corrupted or truncated state file.
aws_ s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws_ s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# State describes the whole account footprint — it must never be reachable publicly.
aws_ s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

echo
echo "Done. Next:  tofu init"

#!/usr/bin/env bash
# Create the S3 bucket that holds this stack's OpenTofu state.
#
# Chicken-and-egg: the backend needs the bucket to exist before the first `tofu init`, so the
# bucket cannot be managed by the stack it stores. This script is the one piece of
# click-ops-equivalent bootstrapping, kept in version control so it is at least reproducible.
#
# Safe to re-run — every step is idempotent. Called by bootstrap-infra.sh's `state` phase,
# which exports AWS_PROFILE/AWS_REGION (via lib.sh) before invoking this script; run directly,
# set AWS_PROFILE yourself if you don't want the default profile.
#
# Usage:  ./bootstrap-state.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  echo "Bucket s3://${STATE_BUCKET} already exists — reconciling settings."
else
  echo "Creating s3://${STATE_BUCKET} in ${AWS_REGION}..."
  # us-east-1 is the one region that rejects an explicit LocationConstraint.
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION"
  else
    aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
  fi
fi

# Versioning is the recovery path for a corrupted or truncated state file.
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# State describes the whole account footprint — it must never be reachable publicly.
aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

# So the bucket is identifiable the same way every other resource in this stack is, even
# though it exists outside the stack (see the comment above).
aws s3api put-bucket-tagging \
  --bucket "$STATE_BUCKET" \
  --tagging "TagSet=[{Key=Project,Value=${APP_NAME}},{Key=ManagedBy,Value=OpenTofu},{Key=Env,Value=prod}]"

echo
echo "Done. Next:  tofu init"

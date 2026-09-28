#!/usr/bin/env bash
# One-time manual frontend build + upload, mirroring what
# .github/workflows/deploy-frontend.yml does in CI. Needed because that workflow only
# triggers on a push to `main` / workflow_dispatch — so the very first deploy (before the
# repo has a real GitHub remote wired up, or before the first push happens) has to be done
# by hand, the same way apply-infra.sh's step 3 hand-pushes the first backend image.
#
# Run every deploy after this one through the GitHub Actions workflow instead.
#
# Usage: ./manual-first-deploy.sh   (run from anywhere; cds to infra/ itself)
set -euo pipefail
# tofu output below needs to run from infra/, one level up from this script.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v pnpm >/dev/null || { echo "pnpm is required" >&2; exit 1; }

FRONTEND_DIR="../front-end/<{{ app_name }}>"

BUCKET=$(tofu output -raw pwa_bucket)
DISTRIBUTION_ID=$(tofu output -raw cloudfront_distribution_id)
API_BASE=$(tofu output -raw api_function_url)

(
  cd "$FRONTEND_DIR"
  pnpm install --frozen-lockfile
  VITE_API_BASE="$API_BASE" pnpm run build

  # Hashed assets / everything else, long cache (mirrors the CI "Sync assets" step).
  aws s3 sync dist "s3://${BUCKET}" \
    --delete \
    --exclude "index.html" \
    --exclude "sw.js" \
    --exclude "manifest.webmanifest" \
    --cache-control "public,max-age=31536000,immutable" \
    --metadata-directive REPLACE

  aws s3 cp dist/sw.js "s3://${BUCKET}/sw.js" \
    --cache-control "no-store" \
    --content-type "application/javascript"

  aws s3 cp dist/index.html "s3://${BUCKET}/index.html" \
    --cache-control "no-store" \
    --content-type "text/html; charset=utf-8"

  aws s3 cp dist/manifest.webmanifest "s3://${BUCKET}/manifest.webmanifest" \
    --cache-control "no-store" \
    --content-type "application/manifest+json"
)

aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/index.html" "/sw.js" "/manifest.webmanifest"

echo "First frontend deploy complete. Every push after this one should go through the"
echo "'Deploy Frontend to AWS S3/CloudFront' GitHub Actions workflow instead."

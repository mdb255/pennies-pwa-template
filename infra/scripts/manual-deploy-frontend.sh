#!/usr/bin/env bash
# Manual frontend build + upload + CloudFront invalidation, mirroring what
# .github/workflows/deploy-frontend.yml does in CI. Use this whenever you need to push a
# frontend change without going through that workflow — e.g. CI isn't wired up to a real
# GitHub remote yet, or the workflow hasn't been exercised/trusted yet.
#
# Unlike manual-first-deploy.sh (a one-time bootstrap artifact), this is meant to be run
# repeatedly for as long as you're deploying by hand.
#
# Usage: ./manual-deploy-frontend.sh   (run from anywhere; cds to infra/ itself)
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

  # Hashed assets (JS/CSS/images) get a long, immutable cache — Vite bakes a content hash into
  # each filename, so a given filename's bytes never change and can be cached forever.
  # index.html/sw.js/manifest.webmanifest are the entry points a client fetches FIRST to learn
  # which hashed assets to load next, so they must never be cached — otherwise a new deploy
  # would never actually reach anyone still holding a cached index.html. `aws s3 sync` can only
  # apply one --cache-control per invocation, hence the exclude-then-cp-individually split.
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

echo "Frontend deploy complete."

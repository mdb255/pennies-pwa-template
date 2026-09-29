#!/usr/bin/env bash
# Drives the infra apply in phases, documented in infra/README.md. Each phase checks reality
# first and skips its action if reality already satisfies it (no local state file tracking
# beliefs about what happened — see NEXT-UP.md for why that burned the previous version of
# this script). Every phase's output is tee'd to infra/.bootstrap-infra-logs/<ts>-<phase>.log.
#
# Usage:
#   ./bootstrap-infra.sh pre               # preflight, state, plan — stop and review the plan
#   ./bootstrap-infra.sh post              # apply, db, deploy, verify
#   ./bootstrap-infra.sh status            # read-only: every phase's check, nothing more
#   ./bootstrap-infra.sh <phase>           # run one phase on its own
#   ./bootstrap-infra.sh db --rotate       # force new DB passwords (replaces reset-pws.sh)
#
# Deploy is outward-facing (creates a GitHub repo, pushes, triggers CI) and always confirms
# first — interactively, or via BOOTSTRAP_CONFIRM_DEPLOY=yes if something already got that
# confirmation another way (the /bootstrap skill asks with AskUserQuestion, then sets this).
#
# Rendered, like the other scripts in this directory: values are stamped in by
# bootstrap-project.py, not read from bootstrap-project.config.yaml at runtime.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

tofu_() { ( cd "$INFRA_DIR" && tofu "$@" ); }

# --- preflight -------------------------------------------------------------------------------
# Read-only. No action, no skip logic — just the checks other phases and `status` rely on,
# plus two more specific to a first run: the hosted zone and the GitHub OIDC provider.

check_preflight() {
  require_tools \
    && require_neon_key \
    && require_matching_account \
    && aws route53 list-hosted-zones-by-name --dns-name "${ROOT_DOMAIN}." --max-items 1 \
         | jq -e --arg name "${ROOT_DOMAIN}." '.HostedZones[]? | select(.Name == $name)' >/dev/null \
    && aws iam list-open-id-connect-providers \
         --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn | [0]" \
         --output text 2>/dev/null | grep -qv '^None$\|^$'
}

phase_preflight() {
  log_info "=== preflight ==="
  require_tools || return 1
  require_neon_key || return 1
  require_matching_account || return 1

  log_info "Checking the Route53 hosted zone for ${ROOT_DOMAIN}..."
  aws route53 list-hosted-zones-by-name --dns-name "${ROOT_DOMAIN}." --max-items 1 \
    | jq -e --arg name "${ROOT_DOMAIN}." '.HostedZones[]? | select(.Name == $name)' >/dev/null \
    || { log_error "No public hosted zone found for ${ROOT_DOMAIN}"; return 1; }

  log_info "Checking the GitHub OIDC provider..."
  local oidc_arn
  oidc_arn=$(aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn | [0]" \
    --output text 2>/dev/null)
  if [[ -z "$oidc_arn" || "$oidc_arn" == "None" ]]; then
    log_error "GitHub OIDC provider not found. It's account-wide, so this script won't create it \
— doing so here could break other repos that already federate into this account. Create it \
once, by hand:"
    log_error "  aws iam create-open-id-connect-provider \\"
    log_error "    --url https://token.actions.githubusercontent.com \\"
    log_error "    --client-id-list sts.amazonaws.com"
    return 1
  fi

  log_info "preflight OK"
}

# --- state -------------------------------------------------------------------------------

check_state() {
  aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null || return 1
  [[ "$(aws s3api get-bucket-versioning --bucket "$STATE_BUCKET" --query Status --output text 2>/dev/null)" == "Enabled" ]] || return 1
  [[ "$(aws s3api get-public-access-block --bucket "$STATE_BUCKET" --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text 2>/dev/null)" == "True" ]] || return 1
  [[ "$(aws s3api get-bucket-tagging --bucket "$STATE_BUCKET" --query "TagSet[?Key=='Project'].Value | [0]" --output text 2>/dev/null)" == "$APP_NAME" ]] || return 1
}

phase_state() {
  log_info "=== state ==="
  if check_state; then
    log_info "State bucket already exists and is configured — skipping bootstrap-state.sh."
  else
    "$SCRIPT_DIR/bootstrap-state.sh"
  fi
  tofu_ init -input=false
  check_state || { log_error "State bucket still isn't fully configured — see the output above."; return 1; }
  log_info "state OK"
}

# --- plan --------------------------------------------------------------------------------
# No skip logic: regenerating the plan is cheap and safe, and this is the approval stop
# point, so it should always reflect the current config.

phase_plan() {
  log_info "=== plan ==="
  local logfile; logfile=$(phase_log_file plan)
  set +e
  tofu_ plan -out="$PLAN_FILE" 2>&1 | tee "$logfile"
  local status=${PIPESTATUS[0]}
  set -e
  [[ $status -eq 0 ]] || return "$status"

  tofu_ show "$PLAN_FILE" >> "$logfile"

  local counts
  counts=$(tofu_ show -json "$PLAN_FILE" | jq -r '
    [.resource_changes[]?.change.actions[]] as $a
    | "\([$a[] | select(.=="create")] | length) to add, \([$a[] | select(.=="update")] | length) to change, \([$a[] | select(.=="delete")] | length) to destroy"')
  log_info "Plan: $counts"
  log_info "Full plan: $logfile"
  log_info "Saved plan: $PLAN_FILE — review it, then run '$0 post' to apply."
}

# --- apply -------------------------------------------------------------------------------

phase_apply() {
  log_info "=== apply ==="
  if [[ ! -f "$PLAN_FILE" ]]; then
    log_error "No saved plan at $PLAN_FILE — run the 'plan' phase (or 'pre') first."
    return 1
  fi
  local stale_tf
  stale_tf=$(find "$INFRA_DIR" -maxdepth 1 -name '*.tf' -newer "$PLAN_FILE" -print -quit)
  if [[ -n "$stale_tf" ]]; then
    log_error "$stale_tf changed after the saved plan — rerun 'plan' before applying."
    return 1
  fi

  local logfile; logfile=$(phase_log_file apply)
  set +e
  tofu_ apply -input=false "$PLAN_FILE" 2>&1 | tee "$logfile"
  local status=${PIPESTATUS[0]}
  set -e
  [[ $status -eq 0 ]] || return "$status"
  rm -f "$PLAN_FILE"

  log_info "Verifying no drift..."
  set +e
  tofu_ plan -detailed-exitcode -input=false >/dev/null 2>>"$logfile"
  local drift=$?
  set -e
  case "$drift" in
    0) log_info "apply OK — no further changes." ;;
    2) log_warn "tofu plan still shows changes after apply — rerun 'plan' to see what's left." ;;
    *) log_error "tofu plan -detailed-exitcode failed after apply — see $logfile"; return 1 ;;
  esac
}

# --- db ----------------------------------------------------------------------------------

check_db() {
  local runtime_url migrations_url
  runtime_url=$(aws ssm get-parameter --name "$SSM_PREFIX/RUNTIME_DB_URL" --with-decryption --query Parameter.Value --output text 2>/dev/null) || return 1
  migrations_url=$(aws ssm get-parameter --name "$SSM_PREFIX/MIGRATIONS_DB_URL" --with-decryption --query Parameter.Value --output text 2>/dev/null) || return 1
  [[ "$runtime_url" != PLACEHOLDER* && -n "$runtime_url" ]] || return 1
  [[ "$migrations_url" != PLACEHOLDER* && -n "$migrations_url" ]] || return 1
  # psql rejects SQLAlchemy's postgresql+psycopg:// scheme; libpq only knows postgresql://.
  psql "${runtime_url/postgresql+psycopg:/postgresql:}" -tAc 'select 1' >/dev/null 2>&1 || return 1
  psql "${migrations_url/postgresql+psycopg:/postgresql:}" -tAc 'select 1' >/dev/null 2>&1 || return 1
}

phase_db() {
  log_info "=== db ==="
  local rotate=false
  [[ "${1:-}" == "--rotate" ]] && rotate=true

  if ! $rotate && check_db; then
    log_info "Both DB URLs already work — skipping. Pass --rotate to force new passwords."
    return 0
  fi
  $rotate && log_info "Rotating: generating new passwords for both roles."

  local db_owner_pw svc_user_pw conn_uri db_host db_name logfile
  # hex, not base64: these are embedded unescaped in connection URLs, and base64's / + = break them.
  db_owner_pw=$(openssl rand -hex 24)
  svc_user_pw=$(openssl rand -hex 24)
  conn_uri=$(tofu_ output -raw neon_bootstrap_connection_uri)
  db_host=$(tofu_ output -raw neon_database_host)
  db_name=$(tofu_ output -raw neon_database_name)
  logfile=$(phase_log_file db)

  # ON_ERROR_STOP means a partial failure here leaves roles/schema in whatever state they
  # reached — safe to just rerun, neon-init.sql is idempotent. Nothing below is ever echoed or
  # written anywhere but the two SSM SecureStrings.
  if ! psql "$conn_uri" \
      -v ON_ERROR_STOP=1 \
      -v db_owner_pw="$db_owner_pw" \
      -v svc_user_pw="$svc_user_pw" \
      -f "$SCRIPT_DIR/neon-init.sql" > "$logfile" 2>&1; then
    log_error "neon-init.sql failed — see $logfile"
    return 1
  fi

  local runtime_url migrations_url
  runtime_url="postgresql+psycopg://${APP_NAME_SNAKE}_svc_user:${svc_user_pw}@${db_host}/${db_name}?options=-csearch_path%3Dapp"
  migrations_url="postgresql+psycopg://${APP_NAME_SNAKE}_db_owner:${db_owner_pw}@${db_host}/${db_name}?options=-csearch_path%3Dapp"

  aws ssm put-parameter --type SecureString --overwrite \
    --name "$SSM_PREFIX/RUNTIME_DB_URL" --value "$runtime_url" >/dev/null
  aws ssm put-parameter --type SecureString --overwrite \
    --name "$SSM_PREFIX/MIGRATIONS_DB_URL" --value "$migrations_url" >/dev/null

  unset db_owner_pw svc_user_pw runtime_url migrations_url conn_uri

  check_db || { log_error "DB URLs still don't work after writing them — see $logfile"; return 1; }
  log_info "db OK"
}

# --- deploy --------------------------------------------------------------------------------

latest_run_id() {
  gh run list --repo "$GITHUB_REPO" --workflow "$1" --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null || true
}

# $2 is the newest run id from before this deploy triggered anything, so a re-deploy doesn't
# latch onto the previous (finished) run.
watch_workflow() {
  local workflow="$1" prev_id="${2:-}" run_id=""
  local i
  for i in $(seq 1 20); do
    run_id=$(latest_run_id "$workflow")
    [[ -n "$run_id" && "$run_id" != "$prev_id" ]] && break
    run_id=""
    sleep 3
  done
  if [[ -z "$run_id" ]]; then
    log_error "No run of $workflow showed up on $GITHUB_REPO"
    return 1
  fi
  gh run watch "$run_id" --repo "$GITHUB_REPO" --exit-status
}

check_deploy() {
  gh repo view "$GITHUB_REPO" >/dev/null 2>&1 || return 1
  local backend frontend
  backend=$(gh run list --repo "$GITHUB_REPO" --workflow deploy-backend.yml --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null)
  frontend=$(gh run list --repo "$GITHUB_REPO" --workflow deploy-frontend.yml --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null)
  [[ "$backend" == "success" && "$frontend" == "success" ]]
}

# The deploy role's OIDC trust policy is built from this repo's own settings (data.tf), so the
# repo has to exist before `plan`. Creates it empty — nothing is pushed until `deploy`.
phase_repo() {
  log_info "=== repo ==="
  if gh repo view "$GITHUB_REPO" >/dev/null 2>&1; then
    log_info "Repo $GITHUB_REPO already exists."
    return 0
  fi
  confirm "Create empty GitHub repo $GITHUB_REPO (${GITHUB_VISIBILITY})? Nothing is pushed until deploy. This is outward-facing." BOOTSTRAP_CONFIRM_REPO \
    || { log_error "Repo $GITHUB_REPO must exist before 'plan' — its OIDC subject claim goes into the deploy role's trust policy."; return 1; }
  ( cd "$INFRA_DIR/.." && gh repo create "$GITHUB_REPO" "--${GITHUB_VISIBILITY}" --source . --remote origin )
}

# GitHub only registers a workflow file once it has processed the push, and a push it hasn't
# registered yet never fires the workflow. So: if a run appears on its own, use it; otherwise,
# once the workflow is listed and still has no run, dispatch it.
ensure_run() {
  local workflow="$1" prev_id="${2:-}" i listed=0 run_id
  for i in $(seq 1 40); do
    run_id=$(latest_run_id "$workflow")
    [[ -n "$run_id" && "$run_id" != "$prev_id" ]] && return 0
    if gh workflow list --repo "$GITHUB_REPO" --json path --jq '.[].path' 2>/dev/null | grep -q "$workflow"; then
      listed=$((listed + 1))
      if (( listed >= 3 )); then
        gh workflow run "$workflow" --repo "$GITHUB_REPO"
        return 0
      fi
    fi
    sleep 2
  done
  log_error "$workflow never registered on $GITHUB_REPO"
  return 1
}

phase_deploy() {
  log_info "=== deploy ==="
  local repo_dir; repo_dir="$(cd "$INFRA_DIR/.." && pwd)"

  phase_repo || return 1

  local prev_backend prev_frontend
  prev_backend=$(latest_run_id deploy-backend.yml)
  prev_frontend=$(latest_run_id deploy-frontend.yml)

  if git -C "$repo_dir" ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    confirm "Trigger both GitHub Actions workflows on $GITHUB_REPO now?" BOOTSTRAP_CONFIRM_DEPLOY \
      || { log_info "Skipping deploy."; return 0; }
    gh workflow run deploy-backend.yml --repo "$GITHUB_REPO"
    gh workflow run deploy-frontend.yml --repo "$GITHUB_REPO"
  else
    confirm "Push main to $GITHUB_REPO and run both deploy workflows? This is outward-facing." BOOTSTRAP_CONFIRM_DEPLOY \
      || { log_info "Skipping deploy."; return 0; }
    git -C "$repo_dir" push -u origin main
    ensure_run deploy-backend.yml "$prev_backend" && ensure_run deploy-frontend.yml "$prev_frontend" || return 1
  fi

  watch_workflow deploy-backend.yml "$prev_backend" && watch_workflow deploy-frontend.yml "$prev_frontend"
}

# --- verify --------------------------------------------------------------------------------

phase_verify() {
  log_info "=== verify ==="
  local api pwa auth ok=true status
  api=$(tofu_ output -raw api_function_url)
  pwa=$(tofu_ output -raw pwa_url)
  auth=$(tofu_ output -raw auth_function_url)

  status=$(curl -s -o /dev/null -w '%{http_code}' "$api/healthz")
  [[ "$status" == "200" ]] || { log_error "api healthz: expected 200, got $status"; ok=false; }

  status=$(curl -s -o /dev/null -w '%{http_code}' -I "$pwa")
  [[ "$status" == "200" ]] || { log_error "pwa: expected 200, got $status"; ok=false; }

  # For POST/PUT through CloudFront OAC to a Lambda Function URL, the viewer must send the real
  # SHA-256 of the body in x-amz-content-sha256 — Lambda rejects UNSIGNED-PAYLOAD with a 403,
  # which the distribution's SPA fallback (403 -> /index.html) then turns into a misleading
  # 200. The body here is empty, so its hash is the well-known empty-string SHA-256.
  local empty_sha256; empty_sha256=$(printf '' | sha256sum | cut -d' ' -f1)
  status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${pwa}/auth/login/" \
    -H "x-amz-content-sha256: ${empty_sha256}")
  [[ "$status" == "422" ]] || { log_error "pwa /auth/login/: expected 422, got $status"; ok=false; }

  status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${auth}auth/login/" \
    -H 'x-amz-content-sha256: UNSIGNED-PAYLOAD')
  [[ "$status" == "403" ]] || { log_error "direct auth function url: expected 403, got $status"; ok=false; }

  $ok || return 1
  log_info "verify OK"
}

# --- status ----------------------------------------------------------------------------------

phase_status() {
  log_info "Status for ${APP_NAME} (account ${AWS_ACCOUNT_ID}, region ${AWS_REGION}, profile ${AWS_PROFILE}):"
  local name
  for name in preflight state db deploy; do
    if "check_$name" >/dev/null 2>&1; then
      printf '  %-10s OK\n' "$name"
    else
      printf '  %-10s NOT READY\n' "$name"
    fi
  done
  printf '  %-10s ' "infra"
  set +e
  tofu_ plan -detailed-exitcode -input=false >/dev/null 2>&1
  local drift=$?
  set -e
  case "$drift" in
    0) echo "OK — applied, no pending changes" ;;
    2) echo "PENDING CHANGES — run 'plan' then 'apply'" ;;
    *) echo "UNKNOWN — not initialized, or plan failed (run 'state' first)" ;;
  esac
  printf '  %-10s ' "verify"
  if phase_verify >/dev/null 2>&1; then echo "OK"; else echo "NOT READY"; fi
}

# --- driver ------------------------------------------------------------------------------

usage() {
  echo "Usage: $0 [pre|post|status|preflight|state|repo|plan|apply|db [--rotate]|deploy|verify]" >&2
  exit 1
}

case "${1:-}" in
  pre)
    phase_preflight && phase_state && phase_repo && phase_plan
    ;;
  post)
    phase_apply && phase_db && phase_deploy && phase_verify
    ;;
  status)   phase_status ;;
  preflight) phase_preflight ;;
  state)    phase_state ;;
  repo)     phase_repo ;;
  plan)     phase_plan ;;
  apply)    phase_apply ;;
  db)       shift; phase_db "$@" ;;
  deploy)   phase_deploy ;;
  verify)   phase_verify ;;
  *)        usage ;;
esac

#!/usr/bin/env bash
# Drives the "Apply sequence" documented in infra/README.md, one step at a time, tracking
# progress in apply-infra.state.json (git-ignored) so a failed run can resume from where it
# left off instead of starting over. This is a convenience wrapper, not a replacement for
# infra/README.md — read that first, especially "What owns what" and the teardown section.
#
# Usage:
#   ./apply-infra.sh           # run all steps that aren't already marked done
#   ./apply-infra.sh status    # show step status, do nothing
#   ./apply-infra.sh <1-6>     # force-(re)run one step
#   ./apply-infra.sh reset     # clear local step tracking (does NOT touch AWS/Neon)
#
# apply-infra.state.json also stores the two DB passwords generated in step 5, so step 6 can
# use them if run later/separately. That means this file holds real production credentials in
# plaintext — it's git-ignored (*.state.json) and chmod'd 600 on every write, but treat it with
# the same care as the passwords themselves.
#
# Set AWS_PROFILE if you don't want the default profile.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# tofu/aws commands below need to run from infra/, one level up from this script — that's
# where the .tf files and .terraform state live. Everything this script owns itself (state
# file, neon-init.sql) stays addressed via $SCRIPT_DIR so it doesn't matter where it's invoked
# from.
cd "$SCRIPT_DIR/.."

command -v jq >/dev/null || { echo "jq is required (state file is JSON) — install it and retry." >&2; exit 1; }

STATE_FILE="$SCRIPT_DIR/apply-infra.state.json"

PROFILE_ARGS=()
if [[ -n "${AWS_PROFILE:-}" ]]; then
  PROFILE_ARGS=(--profile "$AWS_PROFILE")
fi

declare -A STEP_DESCRIPTIONS=(
  [1]="State bucket + tofu init"
  [2]="Targeted apply (ECR, Cognito, IAM)"
  [3]="Manual first image push"
  [4]="Full apply (Lambdas, CloudFront, Route53, SSM, Neon project, ...)"
  [5]="Neon bootstrap SQL (roles/schema/grants)"
  [6]="External secrets (SSM DB URLs)"
)

init_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    jq -n '{steps: {}, secrets: {}}' > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
  fi
}

get_status() {
  jq -r --arg n "$1" '.steps[$n] // "pending"' "$STATE_FILE"
}

set_status() {
  local n="$1" status="$2" tmp
  tmp=$(mktemp)
  jq --arg n "$n" --arg s "$status" '.steps[$n] = $s' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

get_secret() {
  jq -r --arg k "$1" '.secrets[$k] // empty' "$STATE_FILE"
}

set_secret() {
  local key="$1" val="$2" tmp
  tmp=$(mktemp)
  jq --arg k "$key" --arg v "$val" '.secrets[$k] = $v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

confirm() {
  local ans
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

print_status() {
  echo "Step status (from $STATE_FILE):"
  local n
  for n in 1 2 3 4 5 6; do
    printf '  %d. %-55s %s\n' "$n" "${STEP_DESCRIPTIONS[$n]}" "$(get_status "$n")"
  done
}

reset_state() {
  confirm "Reset all local step tracking? (does not touch AWS/Neon, only this file)" || exit 0
  rm -f "$STATE_FILE"
  init_state
  echo "State reset."
}

# --- Steps -------------------------------------------------------------------------------

step1() {
  "$SCRIPT_DIR/bootstrap-state.sh" "${PROFILE_ARGS[@]}" && tofu init
}

step2() {
  tofu apply \
    -target=aws_ecr_repository.api \
    -target=aws_ecr_lifecycle_policy.api \
    -target=aws_cognito_user_pool.main \
    -target=aws_cognito_user_pool_client.app \
    -target=aws_iam_role_policy.deploy \
    -target=aws_iam_role_policy.api_ssm \
    -target=aws_iam_role_policy.auth_ssm \
    -target=aws_iam_role_policy.auth_cognito \
    -target=aws_iam_role_policy_attachment.api_logs \
    -target=aws_iam_role_policy_attachment.auth_logs
}

step3() {
  local ecr_url
  ecr_url=$(tofu output -raw ecr_repository_url) || return 1

  # --provenance=false --sbom=false: buildx's default output is a multi-manifest OCI image
  # (attestations for provenance/SBOM) that Lambda's container runtime rejects. Discovered the
  # hard way against a real Lambda — without these flags the push succeeds but the function
  # fails to update.
  ( cd "../back-end/<{{ app_name }}>-api" || exit 1
    aws ecr get-login-password --region "<{{ aws_region }}>" \
      | docker login --username AWS --password-stdin "<{{ aws_account_id }}>.dkr.ecr.<{{ aws_region }}>.amazonaws.com" \
      || exit 1
    docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
      -t "${ecr_url}:latest" --push . )
}

step4() {
  tofu apply
}

step5() {
  local db_owner_pw svc_user_pw
  db_owner_pw=$(get_secret db_owner_pw)
  svc_user_pw=$(get_secret svc_user_pw)

  # Reuse passwords from a prior partial attempt rather than generating new ones — if the
  # role already got created with the old password, a fresh random one here would just be
  # wrong. neon-init.sql itself is idempotent (skips CREATE ROLE if it already exists).
  if [[ -z "$db_owner_pw" ]]; then
    db_owner_pw=$(openssl rand -base64 24) || return 1
    set_secret db_owner_pw "$db_owner_pw"
  fi
  if [[ -z "$svc_user_pw" ]]; then
    svc_user_pw=$(openssl rand -base64 24) || return 1
    set_secret svc_user_pw "$svc_user_pw"
  fi

  local conn_uri
  conn_uri=$(tofu output -raw neon_bootstrap_connection_uri) || return 1

  psql "$conn_uri" \
    -v ON_ERROR_STOP=1 \
    -v db_owner_pw="$db_owner_pw" \
    -v svc_user_pw="$svc_user_pw" \
    -f "$SCRIPT_DIR/neon-init.sql"
}

step6() {
  local db_owner_pw svc_user_pw
  db_owner_pw=$(get_secret db_owner_pw)
  svc_user_pw=$(get_secret svc_user_pw)
  [[ -z "$db_owner_pw" ]] && db_owner_pw="${DB_OWNER_PW:-}"
  [[ -z "$svc_user_pw" ]] && svc_user_pw="${SVC_USER_PW:-}"

  if [[ -z "$db_owner_pw" || -z "$svc_user_pw" ]]; then
    echo "No DB passwords found in state (step 5 wasn't run by this script) and" >&2
    echo "DB_OWNER_PW/SVC_USER_PW aren't set in the environment. Export them" >&2
    echo "(matching what neon-init.sql actually used) and rerun." >&2
    return 1
  fi
  set_secret db_owner_pw "$db_owner_pw"
  set_secret svc_user_pw "$svc_user_pw"

  local conn_uri hostpart sep runtime_url migrations_url
  conn_uri=$(tofu output -raw neon_bootstrap_connection_uri) || return 1
  hostpart=$(printf '%s' "$conn_uri" | sed -E 's#^postgres(ql)?://[^@]+@##')
  sep='?'
  case "$hostpart" in *'?'*) sep='&' ;; esac

  runtime_url="postgresql+psycopg://<{{ app_name_snake }}>_svc_user:${svc_user_pw}@${hostpart}${sep}options=-csearch_path%3Dapp"
  migrations_url="postgresql+psycopg://<{{ app_name_snake }}>_db_owner:${db_owner_pw}@${hostpart}${sep}options=-csearch_path%3Dapp"

  aws ssm put-parameter --type SecureString --overwrite --region "<{{ aws_region }}>" \
    --name "/<{{ app_name }}>/prod/RUNTIME_DB_URL" --value "$runtime_url" "${PROFILE_ARGS[@]}" \
    && aws ssm put-parameter --type SecureString --overwrite --region "<{{ aws_region }}>" \
    --name "/<{{ app_name }}>/prod/MIGRATIONS_DB_URL" --value "$migrations_url" "${PROFILE_ARGS[@]}"
}

# --- Driver --------------------------------------------------------------------------------

run_step() {
  local n="$1" force="${2:-false}" desc status
  desc="${STEP_DESCRIPTIONS[$n]}"

  if [[ "$force" != true ]]; then
    status=$(get_status "$n")
    if [[ "$status" == "done" ]]; then
      echo "Step $n ($desc): already done — skipping. Run './apply-infra.sh $n' to force a rerun."
      return 0
    fi
    if [[ "$status" == "failed" ]]; then
      echo "Step $n ($desc): previously failed."
      confirm "Retry?" || { echo "Stopping at step $n."; exit 1; }
    fi
  fi

  echo
  echo "=== Step $n: $desc ==="
  if "step$n"; then
    set_status "$n" done
    echo "--- Step $n done ---"
  else
    set_status "$n" failed
    echo "--- Step $n FAILED — fix the issue above, then rerun this script to resume from here ---" >&2
    exit 1
  fi
}

init_state

case "${1:-}" in
  status) print_status ;;
  reset)  reset_state ;;
  1|2|3|4|5|6) run_step "$1" true ;;
  "")
    for n in 1 2 3 4 5 6; do run_step "$n" false; done
    echo
    echo "All steps complete. Next: Phase 4 in NEXT-UP.md — push to main, watch CI/CD, verify."
    ;;
  *)
    echo "Usage: $0 [status|reset|1-6]" >&2
    exit 1
    ;;
esac

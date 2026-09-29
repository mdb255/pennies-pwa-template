#!/usr/bin/env bash
# Removes everything bootstrap-infra.sh provisioned: every resource in tofu state, then the
# state bucket itself. Run only on request — it is not a bootstrap-infra.sh phase. Like its
# sibling it keeps no record of its own: tofu state is the ledger of what exists, and the
# leftover check derives names from lib.sh, so a rerun after a failure picks up from reality.
#
# Usage:
#   ./teardown-infra.sh                 # preflight, plan, confirm, destroy, leftover check
#   ./teardown-infra.sh --plan-only     # stop after showing what would be destroyed
#   ./teardown-infra.sh --check-only    # read-only: list what still exists, by name
#   ./teardown-infra.sh --backup        # also pg_dump the database before destroying it
#
# Confirmation: the user types the app name. If something already got that confirmation
# another way (the /teardown skill asks with AskUserQuestion), export TEARDOWN_CONFIRM_APP to
# the app name — 'yes' is not accepted.
#
# Never touched: the GitHub repo (it must still exist — the OIDC `external` data source calls
# the GitHub API on every plan, including a destroy plan), the account-wide GitHub OIDC
# provider and the Route53 hosted zone (both data sources only), and local files.
#
# Rendered, like the other scripts in this directory: values are stamped in by
# bootstrap-project.py, not read from bootstrap-project.config.yaml at runtime.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

tofu_() { ( cd "$INFRA_DIR" && tofu "$@" ); }

PLAN_ONLY=0 CHECK_ONLY=0 BACKUP=0
for arg in "$@"; do
  case "$arg" in
    --plan-only)  PLAN_ONLY=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    --backup)     BACKUP=1 ;;
    *) log_error "Unknown argument: $arg"; exit 2 ;;
  esac
done

PWA_HOST="${APP_NAME}.${ROOT_DOMAIN}"
UNLOCK_PLAN="$LOG_DIR/teardown-unlock.tfplan"
DESTROY_PLAN="$LOG_DIR/teardown-destroy.tfplan"
GUARDED_RESOURCES='["aws_cognito_user_pool.main","aws_ecr_repository.api","aws_s3_bucket.pwa"]'
# Policies that reference a guarded resource's arn/id get re-planned as in-place updates when
# it changes (the arn is "known after apply"), though their content is identical.
CASCADE_TYPES='["aws_iam_role_policy","aws_s3_bucket_policy"]'

state_bucket_exists() { aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; }

# --- preflight -------------------------------------------------------------------------------
# Deliberately not lib.sh's require_tools: destroy never needs docker, psql, uv or pnpm.

phase_preflight() {
  log_info "=== preflight ==="
  local tools=(tofu aws jq gh) tool missing=()
  (( BACKUP )) && tools+=(pg_dump pg_restore)
  for tool in "${tools[@]}"; do command -v "$tool" >/dev/null || missing+=("$tool"); done
  if (( ${#missing[@]} )); then log_error "Missing required tools: ${missing[*]}"; return 1; fi

  local tofu_version lowest
  tofu_version=$(tofu version -json | jq -r .terraform_version)
  lowest=$(printf '%s\n%s\n' "1.10" "$tofu_version" | sort -V | head -n1)
  [[ "$lowest" == "1.10" ]] || { log_error "tofu >= 1.10 required, found $tofu_version"; return 1; }

  gh auth status >/dev/null 2>&1 || { log_error "gh is not logged in — run 'gh auth login'"; return 1; }
  require_neon_key || return 1
  require_matching_account || return 1

  gh repo view "$GITHUB_REPO" >/dev/null 2>&1 || {
    log_error "GitHub repo $GITHUB_REPO doesn't exist, but tofu's github_oidc_sub data source needs it."
    log_error "Recreate it empty with '$SCRIPT_DIR/bootstrap-infra.sh repo', rerun this, then delete it."
    return 1
  }
  log_info "preflight OK"
}

# --- backup ----------------------------------------------------------------------------------

phase_backup() {
  log_info "=== backup ==="
  local url dump_dir="$INFRA_DIR/backups" dump
  url=$(aws ssm get-parameter --name "$SSM_PREFIX/MIGRATIONS_DB_URL" --with-decryption \
    --query Parameter.Value --output text) \
    || { log_error "Couldn't read $SSM_PREFIX/MIGRATIONS_DB_URL"; return 1; }
  if [[ "$url" == *PLACEHOLDER* ]]; then
    log_error "MIGRATIONS_DB_URL is still the placeholder — there's no database content to back up."
    return 1
  fi
  url="${url/postgresql+psycopg:\/\//postgresql://}"

  mkdir -p "$dump_dir"
  dump="$dump_dir/${APP_NAME}-${RUN_TS}.dump"
  ( umask 077; pg_dump -Fc --dbname "$url" -f "$dump" )
  chmod 600 "$dump"
  pg_restore -l "$dump" >/dev/null || { log_error "Dump $dump failed pg_restore -l"; return 1; }
  log_info "Backup written and verified: $dump"
}

# --- plan ------------------------------------------------------------------------------------

HAVE_UNLOCK_CHANGES=0

phase_plan() {
  log_info "=== plan ==="
  tofu_ init -input=false >/dev/null
  local logfile; logfile=$(phase_log_file teardown-plan)
  set +e
  tofu_ plan -var allow_destroy=true -input=false -out="$UNLOCK_PLAN" 2>&1 | tee "$logfile"
  local status=${PIPESTATUS[0]}
  set -e
  [[ $status -eq 0 ]] || return "$status"
  tofu_ show "$UNLOCK_PLAN" >> "$logfile"

  # Drift guard: the unlock apply may only flip the three guarded resources in place (plus the
  # cascade updates above). Anything
  # else (e.g. an orphan bucket in state whose .tf was deleted) would be created, changed or
  # destroyed by it — and could fail half-way.
  local unexpected
  unexpected=$(tofu_ show -json "$UNLOCK_PLAN" | jq -r --argjson ok "$GUARDED_RESOURCES" --argjson casc "$CASCADE_TYPES" '
    .resource_changes[]?
    | select(.change.actions != ["no-op"] and .change.actions != ["read"])
    | select((.change.actions == ["update"] and ((.address | IN($ok[])) or (.type | IN($casc[])))) | not)
    | "\(.address): \(.change.actions | join(","))"')
  if [[ -n "$unexpected" ]]; then
    log_error "Drift guard: the unlock plan wants to change more than the three guard settings:"
    printf '%s\n' "$unexpected" >&2
    log_error "Reconcile config and state first (see infra/README.md, Teardown). Log: $logfile"
    return 1
  fi

  local n_changes
  n_changes=$(tofu_ show -json "$UNLOCK_PLAN" | jq '[.resource_changes[]? | select(.change.actions == ["update"])] | length')
  HAVE_UNLOCK_CHANGES=$(( n_changes > 0 ? 1 : 0 ))
  (( HAVE_UNLOCK_CHANGES )) || log_info "Guards are already unlocked; no unlock apply needed."

  log_info ""
  log_info "Will be destroyed (tofu state list):"
  tofu_ state list | grep -v '^data\.' | sed 's/^/  - /'
  log_info ""
  log_info "Will NOT be touched:"
  log_info "  - the GitHub OIDC provider and the Route53 hosted zone for ${ROOT_DOMAIN} (data sources only)"
  log_info "  - the GitHub repo $GITHUB_REPO"
  log_info "  - local files"
  log_info "Deleted last, after the destroy: the state bucket $STATE_BUCKET"
  log_info "The Neon project ($APP_NAME) is destroyed with no point-in-time recovery."
}

# --- confirm ---------------------------------------------------------------------------------

phase_confirm() {
  log_info "=== confirm ==="
  if [[ "${TEARDOWN_CONFIRM_APP:-}" == "$APP_NAME" ]]; then
    log_info "Auto-confirmed via \$TEARDOWN_CONFIRM_APP."
    return 0
  fi
  if [[ ! -t 0 ]]; then
    log_error "No terminal to ask, and \$TEARDOWN_CONFIRM_APP isn't set to '$APP_NAME'."
    return 1
  fi
  local ans
  read -r -p "This permanently destroys ${APP_NAME} (account $AWS_ACCOUNT_ID). Type the app name to continue: " ans
  [[ "$ans" == "$APP_NAME" ]] || { log_error "Confirmation didn't match — nothing destroyed."; return 1; }
}

# --- destroy ---------------------------------------------------------------------------------

empty_and_delete_state_bucket() {
  log_info "Emptying and deleting $STATE_BUCKET..."
  local batch
  while :; do
    batch=$(aws s3api list-object-versions --bucket "$STATE_BUCKET" --max-items 500 --output json \
      | jq -c '{Objects: [((.Versions // []) + (.DeleteMarkers // []))[] | {Key, VersionId}], Quiet: true}')
    [[ "$(jq '.Objects | length' <<<"$batch")" -gt 0 ]] || break
    aws s3api delete-objects --bucket "$STATE_BUCKET" --delete "$batch" >/dev/null
  done
  aws s3api delete-bucket --bucket "$STATE_BUCKET"
}

phase_destroy() {
  log_info "=== destroy ==="
  local logfile; logfile=$(phase_log_file teardown-destroy)
  local status

  if (( HAVE_UNLOCK_CHANGES )); then
    set +e; tofu_ apply -input=false "$UNLOCK_PLAN" 2>&1 | tee -a "$logfile"; status=${PIPESTATUS[0]}; set -e
    [[ $status -eq 0 ]] || return "$status"
  fi
  rm -f "$UNLOCK_PLAN"

  # Planned after the unlock apply so it sees the flipped guards.
  set +e
  tofu_ plan -destroy -var allow_destroy=true -input=false -out="$DESTROY_PLAN" 2>&1 | tee -a "$logfile"
  status=${PIPESTATUS[0]}; set -e
  [[ $status -eq 0 ]] || return "$status"
  tofu_ show "$DESTROY_PLAN" >> "$logfile"

  local non_delete n_delete n_state
  non_delete=$(tofu_ show -json "$DESTROY_PLAN" | jq '[.resource_changes[]? | select(.change.actions != ["delete"])] | length')
  n_delete=$(tofu_ show -json "$DESTROY_PLAN" | jq '[.resource_changes[]? | select(.change.actions == ["delete"])] | length')
  n_state=$(tofu_ state list | grep -vc "^data\.")
  if [[ "$non_delete" != 0 || "$n_delete" != "$n_state" ]]; then
    log_error "Destroy plan sanity check failed: $n_delete deletes for $n_state state entries, $non_delete non-delete actions."
    return 1
  fi

  log_info "Destroying $n_delete resources (CloudFront can take 5-15 minutes)..."
  set +e; tofu_ apply -input=false "$DESTROY_PLAN" 2>&1 | tee -a "$logfile"; status=${PIPESTATUS[0]}; set -e
  [[ $status -eq 0 ]] || return "$status"
  rm -f "$DESTROY_PLAN"

  [[ -z "$(tofu_ state list)" ]] || { log_error "State isn't empty after destroy — not deleting the state bucket."; return 1; }
  empty_and_delete_state_bucket
  log_info "destroy OK. Log: $logfile"
}

# --- leftover check --------------------------------------------------------------------------
# Read-only, name-based (no tag sweep: the profile may be denied tag:GetResources).

LEFTOVERS=0

report() { # <label> <found-items...>
  local label="$1"; shift
  if (( $# )); then
    LEFTOVERS=1
    log_warn "FOUND  $label: $*"
  else
    log_info "none   $label"
  fi
}

# Word-split on purpose: callers pass whitespace-separated CLI text output.
lines() { tr '\t' '\n' | sed '/^$/d;/^None$/d'; }

phase_check() {
  log_info "=== leftover check ==="
  local -a found

  mapfile -t found < <(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${APP_NAME}-')].Name" --output text | lines)
  report "S3 buckets ${APP_NAME}-*" "${found[@]}"

  mapfile -t found < <(aws ecr describe-repositories --repository-names "${APP_NAME}-api" --query 'repositories[].repositoryName' --output text 2>/dev/null | lines)
  report "ECR repo ${APP_NAME}-api" "${found[@]}"

  found=()
  local fn
  for fn in "${APP_NAME}-api" "${APP_NAME}-auth"; do
    aws lambda get-function --function-name "$fn" >/dev/null 2>&1 && found+=("$fn")
  done
  report "Lambda functions" "${found[@]}"

  mapfile -t found < <(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${APP_NAME}-" --query 'logGroups[].logGroupName' --output text | lines)
  report "log groups /aws/lambda/${APP_NAME}-*" "${found[@]}"

  mapfile -t found < <(aws ssm get-parameters-by-path --path "/${APP_NAME}/" --recursive --query 'Parameters[].Name' --output text | lines)
  report "SSM params /${APP_NAME}/" "${found[@]}"

  mapfile -t found < <(aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='${APP_NAME}-users'].Id" --output text | lines)
  report "Cognito pool ${APP_NAME}-users" "${found[@]}"

  found=()
  local role
  for role in "${APP_NAME_SNAKE}_api_exec" "${APP_NAME_SNAKE}_auth_exec" "${APP_NAME_SNAKE}_deploy"; do
    aws iam get-role --role-name "$role" >/dev/null 2>&1 && found+=("$role")
  done
  report "IAM roles ${APP_NAME_SNAKE}_{api_exec,auth_exec,deploy}" "${found[@]}"

  mapfile -t found < <(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '${PWA_HOST}')].Id" --output text | lines)
  report "CloudFront distribution for $PWA_HOST" "${found[@]}"

  mapfile -t found < <(aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='${PWA_HOST}'].CertificateArn" --output text | lines)
  report "ACM certificates for $PWA_HOST (us-east-1)" "${found[@]}"

  local zone_id
  zone_id=$(aws route53 list-hosted-zones-by-name --dns-name "${ROOT_DOMAIN}." --max-items 1 \
    --query "HostedZones[?Name=='${ROOT_DOMAIN}.'].Id | [0]" --output text | sed 's|.*/||')
  if [[ -n "$zone_id" && "$zone_id" != None ]]; then
    mapfile -t found < <(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" \
      --query "ResourceRecordSets[?Name=='${PWA_HOST}.' || ends_with(Name, '.${PWA_HOST}.')].[Type,Name]" --output text | tr '\t' ' ' | sed '/^$/d')
    report "Route53 records for $PWA_HOST" "${found[@]}"
  fi

  local neon_ids
  neon_ids=$(printf 'header = "Authorization: Bearer %s"\n' "$NEON_API_KEY" \
    | curl -fsS -K - "https://console.neon.tech/api/v2/projects?search=${APP_NAME}&limit=100" \
    | jq -r --arg n "$APP_NAME" '.projects[]? | select(.name == $n) | .id') \
    || { log_error "Neon API query failed"; LEFTOVERS=1; neon_ids=""; }
  mapfile -t found < <(printf '%s\n' "$neon_ids" | sed '/^$/d')
  report "Neon project $APP_NAME" "${found[@]}"

  if state_bucket_exists; then report "state bucket $STATE_BUCKET" "$STATE_BUCKET"; else report "state bucket $STATE_BUCKET"; fi

  log_info ""
  log_info "Local cleanup, if wanted: infra/.terraform, infra/.bootstrap-infra-logs/, infra/backups/, the checkout itself."
  log_info "The GitHub repo is never deleted by this script. To delete it yourself (needs"
  log_info "'gh auth refresh -s delete_repo'): gh repo delete $GITHUB_REPO"
  return "$LEFTOVERS"
}

# --- main ------------------------------------------------------------------------------------

main() {
  if (( CHECK_ONLY )); then
    require_neon_key && require_matching_account && phase_check
    return
  fi

  phase_preflight
  if ! state_bucket_exists; then
    log_info "State bucket $STATE_BUCKET doesn't exist — nothing for tofu to destroy."
    phase_check
    return
  fi

  (( BACKUP )) && phase_backup
  phase_plan
  (( PLAN_ONLY )) && { log_info "--plan-only: stopping before any change."; return 0; }
  phase_confirm
  phase_destroy
  phase_check
}

main

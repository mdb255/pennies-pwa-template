#!/usr/bin/env bash
# Shared by every infra/scripts/*.sh phase script. Sourced, not executed — sets up logging,
# exports AWS_PROFILE/AWS_REGION, and provides the preflight checks (tools, NEON_API_KEY,
# caller account) that bootstrap-infra.sh's `preflight` phase runs directly.
#
# Rendered, like the other scripts here: values below are stamped in by bootstrap-project.py
# from bootstrap-project.config.yaml, not read from it at runtime.

APP_NAME="<{{ app_name }}>"
APP_NAME_SNAKE="<{{ app_name_snake }}>"
AWS_ACCOUNT_ID="<{{ aws_account_id }}>"
ROOT_DOMAIN="<{{ root_domain }}>"
GITHUB_REPO="<{{ github_repo }}>"
GITHUB_VISIBILITY="<{{ github_visibility }}>"
STATE_BUCKET="${APP_NAME}-tfstate"
SSM_PREFIX="/${APP_NAME}/prod"

export AWS_PROFILE="<{{ aws_profile }}>"
export AWS_REGION="<{{ aws_region }}>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$INFRA_DIR/.bootstrap-infra-logs"
mkdir -p "$LOG_DIR"

# One timestamp per bootstrap-infra.sh invocation — every phase run in that invocation shares
# it, so a `pre` or `post` run's logs sort together. Set by the entrypoint before it sources
# this file; falls back to a fresh one if lib.sh is sourced on its own.
: "${RUN_TS:=$(date -u +%Y%m%dT%H%M%SZ)}"

# Fixed name (not timestamped) so `apply` can find the plan `plan` just saved, and so staleness
# can be checked against the .tf files' mtimes. Lives under LOG_DIR, which is git-ignored.
PLAN_FILE="$LOG_DIR/bootstrap.tfplan"

log_info()  { printf '%s\n' "$*"; }
log_warn()  { printf 'WARNING: %s\n' "$*" >&2; }
log_error() { printf 'ERROR: %s\n' "$*" >&2; }

phase_log_file() {
  printf '%s/%s-%s.log' "$LOG_DIR" "$RUN_TS" "$1"
}

# Confirms with a human before an outward-facing action. If VAR_NAME is exported to "yes"
# (used by the /bootstrap skill, which gets its own confirmation via AskUserQuestion before
# invoking this script), that stands in for the prompt. Otherwise, with no controlling
# terminal, the answer is "no" rather than hanging on a `read` that will never resolve.
confirm() {
  local prompt="$1" var_name="${2:-}"
  if [[ -n "$var_name" && "${!var_name:-}" == "yes" ]]; then
    log_info "$prompt [auto-confirmed via \$$var_name=yes]"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    log_warn "$prompt — no terminal to ask, and \$$var_name isn't 'yes'; treating as no."
    return 1
  fi
  local ans
  read -r -p "$prompt [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# --- preflight checks, shared by the `preflight` phase and `status` -----------------------

require_tools() {
  local missing=() tool
  for tool in tofu aws docker psql jq uv pnpm gh; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if (( ${#missing[@]} )); then
    log_error "Missing required tools: ${missing[*]}"
    return 1
  fi

  local tofu_version lowest
  tofu_version=$(tofu version -json | jq -r .terraform_version)
  lowest=$(printf '%s\n%s\n' "1.10" "$tofu_version" | sort -V | head -n1)
  if [[ "$lowest" != "1.10" ]]; then
    log_error "tofu >= 1.10 required, found $tofu_version"
    return 1
  fi

  docker info >/dev/null 2>&1 || { log_error "Docker daemon is not running"; return 1; }
  gh auth status >/dev/null 2>&1 || { log_error "gh is not logged in — run 'gh auth login'"; return 1; }
}

# Tested with [ -n ], never echoed or logged.
require_neon_key() {
  if [ -z "${NEON_API_KEY:-}" ]; then
    log_error "NEON_API_KEY is not set"
    return 1
  fi
}

require_matching_account() {
  local caller_account
  caller_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
    log_error "aws sts get-caller-identity failed — check AWS_PROFILE=$AWS_PROFILE"
    return 1
  }
  if [[ "$caller_account" != "$AWS_ACCOUNT_ID" ]]; then
    log_error "Caller account ($caller_account) doesn't match bootstrap-project.config.yaml's aws.account_id ($AWS_ACCOUNT_ID)"
    return 1
  fi
}

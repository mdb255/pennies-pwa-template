#!/usr/bin/env bash
# Staged to ~/.config/pennies-pwa-template/export-vars.sh (chmod 600) the first time /bootstrap
# runs. Holds defaults shared across every project you bootstrap from this template, plus your
# Neon API key. NEON_API_KEY is a real credential — this file is never `Read`/`cat`'d by the
# skill, only sourced in a subshell, and its value is never echoed or asked about.
#
# Fill in what you know; leave the rest blank and /bootstrap will ask, offering a detected
# value where it can (aws sts get-caller-identity, aws configure get region, your Route53
# zones) as the recommended answer.

export PENNIES_PROJECTS_DIR=""        # parent dir new projects are created in
export PENNIES_AWS_ACCOUNT_ID=""
export PENNIES_AWS_REGION=""
export PENNIES_AWS_PROFILE="default"
export PENNIES_ROOT_DOMAIN=""
export PENNIES_NEON_REGION_ID=""      # blank → aws-<region>
export PENNIES_GITHUB_VISIBILITY="private"
export PENNIES_LAMBDA_MEMORY="512"
export PENNIES_API_PORT="8000"
export PENNIES_PYTHON_VERSION="3.12"
export PENNIES_NODE_VERSION="24"
export PENNIES_PNPM_VERSION="11"
export NEON_API_KEY=""                # add this yourself; never paste it into chat

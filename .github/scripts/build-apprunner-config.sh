#!/bin/bash
set -euo pipefail

# Usage: build-apprunner-config.sh <ecr-image> <ssm-prefix>
# Example: build-apprunner-config.sh 123456.dkr.ecr.us-east-1.amazonaws.com/myapp:latest /<{{ app_name }}>/prod

ECR_IMAGE=$1
SSM_PREFIX=$2

# List of parameter names to fetch
PARAM_NAMES=(
  "RUNTIME_DB_URL"
  "USER_POOL_ID"
  "APP_CLIENT_ID"
  "CORS_ORIGINS"
  "APP_ENV"
  "APP_DOMAIN"
)

# Build full parameter paths
FULL_PATHS=()
for name in "${PARAM_NAMES[@]}"; do
  FULL_PATHS+=("${SSM_PREFIX}/${name}")
done

# Fetch all parameters and build secrets dictionary (not array)
# Convert from array of {Name, ARN} to dictionary {Name: ARN}
SECRETS=$(aws ssm get-parameters \
  --names "${FULL_PATHS[@]}" \
  --query 'Parameters[].{Name:Name,ARN:ARN}' \
  --output json | \
  jq 'map({
    key: (.Name | split("/")[-1]),
    value: .ARN
  }) | from_entries')

# Build full App Runner source configuration
jq -n \
  --arg image "$ECR_IMAGE" \
  --argjson secrets "$SECRETS" \
  '{
    ImageRepository: {
      ImageIdentifier: $image,
      ImageRepositoryType: "ECR",
      ImageConfiguration: {
        Port: "<{{ api_port }}>",
        RuntimeEnvironmentSecrets: $secrets
      }
    },
    AutoDeploymentsEnabled: false
  }'




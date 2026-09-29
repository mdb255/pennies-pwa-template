# The only variable in this stack, and an operational switch rather than project config (all
# config is stamped into locals.tf). It relaxes the three settings that block `tofu destroy`:
# Cognito deletion protection, ECR force_delete, and S3 force_destroy. Only
# scripts/teardown-infra.sh ever sets it; bootstrap-infra.sh's plan/apply never pass it, so a
# normal apply always restores the guards.
variable "allow_destroy" {
  type    = bool
  default = false
}

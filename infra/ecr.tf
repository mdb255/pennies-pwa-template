resource "aws_ecr_repository" "api" {
  name = "${local.app_name}-api"

  # MUTABLE so the deploy workflow can re-point :latest at each new build. Both Lambda
  # functions run this one image; APP_COMPONENT decides which routers they mount.
  image_tag_mutability = "MUTABLE"

  # Teardown only (see variables.tf): lets destroy delete the repo while it still holds images.
  force_delete = var.allow_destroy

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Every deploy pushes :<sha> and re-points :latest, orphaning the previous layer set. Without
# a policy the repository grows without bound at $0.10/GB-month.
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        # ECR requires the tagStatus=any rule to be last. Keeping 10 tagged images leaves a
        # 10-deploy rollback window.
        rulePriority = 2
        description  = "Keep only the 10 most recent tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

# Seeds the first image inside this same apply, so a container-image Lambda (lambda.tf) can be
# created in one `tofu apply` instead of the two-part sequence this used to require (repo →
# manual `docker push` → everything else). triggers_replace on the repository's id means this
# only runs once, when the repository is (re)created — later pushes go through CI
# (.github/workflows/deploy-backend.yml), never through this resource.
#
# --provenance=false --sbom=false: buildx's default output is a multi-manifest OCI image
# (attestations for provenance/SBOM) that Lambda's container runtime rejects. Discovered the
# hard way against a real Lambda — without these flags the push succeeds but the function
# fails to update.
#
# Runs as whatever AWS credentials `tofu apply` itself runs under (bootstrap-infra.sh exports
# AWS_PROFILE before calling `tofu apply`) — an admin/human principal, not the CI deploy role.
resource "terraform_data" "seed_image" {
  triggers_replace = [aws_ecr_repository.api.id]

  provisioner "local-exec" {
    working_dir = "${path.module}/../back-end/<{{ app_name }}>-api"
    interpreter = ["/usr/bin/env", "bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      aws ecr get-login-password --region ${local.aws_region} \
        | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${local.aws_region}.amazonaws.com
      docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
        -t ${aws_ecr_repository.api.repository_url}:latest --push .
    EOT
  }
}

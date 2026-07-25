resource "aws_ecr_repository" "api" {
  name = "${local.app_name}-api"

  # MUTABLE so the deploy workflow can re-point :latest at each new build. Both Lambda
  # functions run this one image; APP_COMPONENT decides which routers they mount.
  image_tag_mutability = "MUTABLE"

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

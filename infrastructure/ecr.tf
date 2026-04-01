# =============================================================
# ecr.tf — ECR repositories
# Replaces infrastructure/ecr.yml (CloudFormation)
# Everything is now in one tool — Terraform
# =============================================================

resource "aws_ecr_repository" "eshop" {
  name                 = "my-app"
  image_tag_mutability = "MUTABLE"

  # Scan every image on push — catches vulnerabilities before deployment
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encrypt images at rest using AWS-managed key
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "chatbot" {
  name                 = "eshop-chatbot"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Lifecycle policy — keep only the 10 most recent images
# Prevents ECR storage costs from growing unbounded
resource "aws_ecr_lifecycle_policy" "eshop" {
  repository = aws_ecr_repository.eshop.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "chatbot" {
  repository = aws_ecr_repository.chatbot.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

locals {
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.images_to_keep} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.images_to_keep
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  repos = {
    schedule         = "${var.project_name}-schedule-lambda"
    schedule_base    = "${var.project_name}-schedule-lambda-base"
    delete           = "${var.project_name}-delete-lambda"
    delete_base      = "${var.project_name}-delete-lambda-base"
    status           = "${var.project_name}-status-lambda"
    status_base      = "${var.project_name}-status-lambda-base"
    codebuildlens    = "${var.project_name}-codebuildlens-lambda"
    codebuildlens_base = "${var.project_name}-codebuildlens-lambda-base"
  }
}

#------------------------------------------------------------------------------
# Schedule Lambda Repositories
#------------------------------------------------------------------------------
resource "aws_ecr_repository" "schedule" {
  name                 = local.repos.schedule
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = {
    Name = local.repos.schedule
  }
}

resource "aws_ecr_lifecycle_policy" "schedule" {
  repository = aws_ecr_repository.schedule.name
  policy     = local.lifecycle_policy
}

resource "aws_ecr_repository" "schedule_base" {
  name                 = local.repos.schedule_base
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = {
    Name = local.repos.schedule_base
  }
}

resource "aws_ecr_lifecycle_policy" "schedule_base" {
  repository = aws_ecr_repository.schedule_base.name
  policy     = local.lifecycle_policy
}

#------------------------------------------------------------------------------
# Delete Lambda Repositories
#------------------------------------------------------------------------------
resource "aws_ecr_repository" "delete" {
  name                 = local.repos.delete
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = {
    Name = local.repos.delete
  }
}

resource "aws_ecr_lifecycle_policy" "delete" {
  repository = aws_ecr_repository.delete.name
  policy     = local.lifecycle_policy
}

resource "aws_ecr_repository" "delete_base" {
  name                 = local.repos.delete_base
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = {
    Name = local.repos.delete_base
  }
}

resource "aws_ecr_lifecycle_policy" "delete_base" {
  repository = aws_ecr_repository.delete_base.name
  policy     = local.lifecycle_policy
}

#------------------------------------------------------------------------------
# Status Lambda Repositories
#------------------------------------------------------------------------------
resource "aws_ecr_repository" "status" {
  name                 = local.repos.status
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = {
    Name = local.repos.status
  }
}

resource "aws_ecr_lifecycle_policy" "status" {
  repository = aws_ecr_repository.status.name
  policy     = local.lifecycle_policy
}

resource "aws_ecr_repository" "status_base" {
  name                 = local.repos.status_base
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = {
    Name = local.repos.status_base
  }
}

resource "aws_ecr_lifecycle_policy" "status_base" {
  repository = aws_ecr_repository.status_base.name
  policy     = local.lifecycle_policy
}

#------------------------------------------------------------------------------
# CodeBuildLens Lambda Repositories
#------------------------------------------------------------------------------
resource "aws_ecr_repository" "codebuildlens" {
  name                 = local.repos.codebuildlens
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = {
    Name = local.repos.codebuildlens
  }
}

resource "aws_ecr_lifecycle_policy" "codebuildlens" {
  repository = aws_ecr_repository.codebuildlens.name
  policy     = local.lifecycle_policy
}

resource "aws_ecr_repository" "codebuildlens_base" {
  name                 = local.repos.codebuildlens_base
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = {
    Name = local.repos.codebuildlens_base
  }
}

resource "aws_ecr_lifecycle_policy" "codebuildlens_base" {
  repository = aws_ecr_repository.codebuildlens_base.name
  policy     = local.lifecycle_policy
}

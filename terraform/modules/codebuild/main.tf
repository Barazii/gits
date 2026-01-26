# GitHub Source Credential
resource "aws_codebuild_source_credential" "github" {
  count       = var.github_token != "" ? 1 : 0
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
}

# CodeBuild Project
resource "aws_codebuild_project" "main" {
  name          = var.project_name
  service_role  = var.codebuild_service_role_arn
  build_timeout = var.build_timeout
  queued_timeout = var.build_timeout

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type                        = "LINUX_CONTAINER"
    image                       = var.build_image
    compute_type                = var.compute_type
    privileged_mode             = false
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1
    buildspec       = var.buildspec_file
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = [var.private_subnet_id]
    security_group_ids = [var.codebuild_security_group_id]
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = "/aws/codebuild/${var.project_name}"
    }
  }

  tags = {
    Name = var.project_name
  }

  depends_on = [aws_codebuild_source_credential.github]
}

#------------------------------------------------------------------------------
# Schedule Lambda
#------------------------------------------------------------------------------
resource "aws_lambda_function" "schedule" {
  function_name = "${var.project_name}-schedule"
  role          = var.schedule_lambda_role_arn
  package_type  = "Image"
  image_uri     = var.image_uri_schedule
  timeout       = var.schedule_timeout
  memory_size   = var.schedule_memory

  vpc_config {
    subnet_ids         = [var.private_subnet_id]
    security_group_ids = [var.schedule_lambda_security_group_id]
  }

  environment {
    variables = {
      DYNAMODB_TABLE             = var.dynamodb_table_name
      AWS_ACCOUNT_ID             = var.account_id
      AWS_APP_REGION             = var.aws_region
      AWS_BUCKET_NAME            = var.artifact_bucket_name
      AWS_CODEBUILD_PROJECT_NAME = var.codebuild_project_name
      EVENTBRIDGE_TARGET_ROLE_ARN = var.eventbridge_target_role_arn
    }
  }

  tags = {
    Name = "${var.project_name}-schedule"
  }
}

#------------------------------------------------------------------------------
# Delete Lambda
#------------------------------------------------------------------------------
resource "aws_lambda_function" "delete" {
  function_name = "${var.project_name}-delete"
  role          = var.delete_lambda_role_arn
  package_type  = "Image"
  image_uri     = var.image_uri_delete
  timeout       = var.delete_timeout
  memory_size   = var.delete_memory

  vpc_config {
    subnet_ids         = [var.private_subnet_id]
    security_group_ids = [var.delete_lambda_security_group_id]
  }

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
      AWS_APP_REGION = var.aws_region
    }
  }

  tags = {
    Name = "${var.project_name}-delete"
  }
}

#------------------------------------------------------------------------------
# Status Lambda
#------------------------------------------------------------------------------
resource "aws_lambda_function" "status" {
  function_name = "${var.project_name}-status"
  role          = var.status_lambda_role_arn
  package_type  = "Image"
  image_uri     = var.image_uri_status
  timeout       = var.status_timeout
  memory_size   = var.status_memory

  vpc_config {
    subnet_ids         = [var.private_subnet_id]
    security_group_ids = [var.status_lambda_security_group_id]
  }

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
      AWS_APP_REGION = var.aws_region
    }
  }

  tags = {
    Name = "${var.project_name}-status"
  }
}

#------------------------------------------------------------------------------
# CodeBuildLens Lambda
#------------------------------------------------------------------------------
resource "aws_lambda_function" "codebuildlens" {
  function_name = "${var.project_name}-codebuildlens"
  role          = var.codebuildlens_lambda_role_arn
  package_type  = "Image"
  image_uri     = var.image_uri_codebuildlens
  timeout       = var.codebuildlens_timeout
  memory_size   = var.codebuildlens_memory

  vpc_config {
    subnet_ids         = [var.private_subnet_id]
    security_group_ids = [var.codebuildlens_lambda_security_group_id]
  }

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
      AWS_APP_REGION = var.aws_region
    }
  }

  tags = {
    Name = "${var.project_name}-codebuildlens"
  }
}

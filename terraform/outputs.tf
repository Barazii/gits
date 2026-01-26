#------------------------------------------------------------------------------
# VPC Outputs
#------------------------------------------------------------------------------
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = module.vpc.private_subnet_id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = module.vpc.public_subnet_id
}

#------------------------------------------------------------------------------
# Security Group Outputs
#------------------------------------------------------------------------------
output "codebuild_security_group_id" {
  description = "CodeBuild security group ID"
  value       = module.vpc.codebuild_security_group_id
}

output "schedule_lambda_security_group_id" {
  description = "Schedule Lambda security group ID"
  value       = module.vpc.schedule_lambda_security_group_id
}

output "delete_lambda_security_group_id" {
  description = "Delete Lambda security group ID"
  value       = module.vpc.delete_lambda_security_group_id
}

output "status_lambda_security_group_id" {
  description = "Status Lambda security group ID"
  value       = module.vpc.status_lambda_security_group_id
}

output "codebuildlens_lambda_security_group_id" {
  description = "CodeBuildLens Lambda security group ID"
  value       = module.vpc.codebuildlens_lambda_security_group_id
}

#------------------------------------------------------------------------------
# IAM Role Outputs
#------------------------------------------------------------------------------
output "schedule_lambda_role_arn" {
  description = "ARN of the schedule Lambda IAM role"
  value       = module.iam.schedule_lambda_role_arn
}

output "delete_lambda_role_arn" {
  description = "ARN of the delete Lambda IAM role"
  value       = module.iam.delete_lambda_role_arn
}

output "status_lambda_role_arn" {
  description = "ARN of the status Lambda IAM role"
  value       = module.iam.status_lambda_role_arn
}

output "codebuildlens_lambda_role_arn" {
  description = "ARN of the codebuildlens Lambda IAM role"
  value       = module.iam.codebuildlens_lambda_role_arn
}

output "eventbridge_target_role_arn" {
  description = "ARN of the EventBridge target role"
  value       = module.iam.eventbridge_target_role_arn
}

output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = module.iam.codebuild_service_role_arn
}

#------------------------------------------------------------------------------
# DynamoDB Outputs
#------------------------------------------------------------------------------
output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = module.dynamodb.table_arn
}

#------------------------------------------------------------------------------
# S3 Outputs
#------------------------------------------------------------------------------
output "artifact_bucket_name" {
  description = "S3 artifact bucket name"
  value       = module.s3.bucket_name
}

output "artifact_bucket_arn" {
  description = "S3 artifact bucket ARN"
  value       = module.s3.bucket_arn
}

#------------------------------------------------------------------------------
# ECR Outputs
#------------------------------------------------------------------------------
output "ecr_schedule_repo_url" {
  description = "ECR repository URL for schedule Lambda"
  value       = module.ecr.schedule_repo_url
}

output "ecr_delete_repo_url" {
  description = "ECR repository URL for delete Lambda"
  value       = module.ecr.delete_repo_url
}

output "ecr_status_repo_url" {
  description = "ECR repository URL for status Lambda"
  value       = module.ecr.status_repo_url
}

output "ecr_codebuildlens_repo_url" {
  description = "ECR repository URL for codebuildlens Lambda"
  value       = module.ecr.codebuildlens_repo_url
}

#------------------------------------------------------------------------------
# Lambda Outputs
#------------------------------------------------------------------------------
output "schedule_lambda_arn" {
  description = "ARN of the schedule Lambda function"
  value       = var.lambda_image_uri_schedule != "" ? module.lambda[0].schedule_lambda_arn : null
}

output "delete_lambda_arn" {
  description = "ARN of the delete Lambda function"
  value       = var.lambda_image_uri_schedule != "" ? module.lambda[0].delete_lambda_arn : null
}

output "status_lambda_arn" {
  description = "ARN of the status Lambda function"
  value       = var.lambda_image_uri_schedule != "" ? module.lambda[0].status_lambda_arn : null
}

output "codebuildlens_lambda_arn" {
  description = "ARN of the codebuildlens Lambda function"
  value       = var.lambda_image_uri_schedule != "" ? module.lambda[0].codebuildlens_lambda_arn : null
}

#------------------------------------------------------------------------------
# API Gateway Outputs
#------------------------------------------------------------------------------
output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = var.lambda_image_uri_schedule != "" ? module.apigateway[0].api_gateway_id : null
}

output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = var.lambda_image_uri_schedule != "" ? module.apigateway[0].api_url : null
}

output "api_key_id" {
  description = "API Gateway API Key ID (retrieve value from AWS Console)"
  value       = var.lambda_image_uri_schedule != "" ? module.apigateway[0].api_key_id : null
}

#------------------------------------------------------------------------------
# CodeBuild Outputs
#------------------------------------------------------------------------------
output "codebuild_project_name" {
  description = "CodeBuild project name"
  value       = module.codebuild.project_name
}

output "codebuild_project_arn" {
  description = "CodeBuild project ARN"
  value       = module.codebuild.project_arn
}

#------------------------------------------------------------------------------
# Secrets Manager Outputs
#------------------------------------------------------------------------------
output "github_token_secret_arn" {
  description = "ARN of the GitHub token secret"
  value       = var.github_token != "" ? module.secrets[0].github_token_secret_arn : null
  sensitive   = true
}

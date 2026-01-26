variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name"
  type        = string
}

variable "artifact_bucket_name" {
  description = "S3 artifact bucket name"
  type        = string
}

variable "codebuild_project_name" {
  description = "CodeBuild project name"
  type        = string
}

variable "eventbridge_target_role_arn" {
  description = "EventBridge target role ARN"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID"
  type        = string
}

variable "schedule_lambda_role_arn" {
  description = "Schedule Lambda role ARN"
  type        = string
}

variable "delete_lambda_role_arn" {
  description = "Delete Lambda role ARN"
  type        = string
}

variable "status_lambda_role_arn" {
  description = "Status Lambda role ARN"
  type        = string
}

variable "codebuildlens_lambda_role_arn" {
  description = "CodeBuildLens Lambda role ARN"
  type        = string
}

variable "schedule_lambda_security_group_id" {
  description = "Schedule Lambda security group ID"
  type        = string
}

variable "delete_lambda_security_group_id" {
  description = "Delete Lambda security group ID"
  type        = string
}

variable "status_lambda_security_group_id" {
  description = "Status Lambda security group ID"
  type        = string
}

variable "codebuildlens_lambda_security_group_id" {
  description = "CodeBuildLens Lambda security group ID"
  type        = string
}

variable "image_uri_schedule" {
  description = "ECR image URI for schedule Lambda"
  type        = string
}

variable "image_uri_delete" {
  description = "ECR image URI for delete Lambda"
  type        = string
}

variable "image_uri_status" {
  description = "ECR image URI for status Lambda"
  type        = string
}

variable "image_uri_codebuildlens" {
  description = "ECR image URI for codebuildlens Lambda"
  type        = string
}

variable "schedule_timeout" {
  description = "Schedule Lambda timeout"
  type        = number
}

variable "schedule_memory" {
  description = "Schedule Lambda memory"
  type        = number
}

variable "delete_timeout" {
  description = "Delete Lambda timeout"
  type        = number
}

variable "delete_memory" {
  description = "Delete Lambda memory"
  type        = number
}

variable "status_timeout" {
  description = "Status Lambda timeout"
  type        = number
}

variable "status_memory" {
  description = "Status Lambda memory"
  type        = number
}

variable "codebuildlens_timeout" {
  description = "CodeBuildLens Lambda timeout"
  type        = number
}

variable "codebuildlens_memory" {
  description = "CodeBuildLens Lambda memory"
  type        = number
}

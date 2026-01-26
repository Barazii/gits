variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "codebuildlens_lambda_arn" {
  description = "CodeBuildLens Lambda ARN"
  type        = string
}

variable "codebuildlens_lambda_name" {
  description = "CodeBuildLens Lambda function name"
  type        = string
}

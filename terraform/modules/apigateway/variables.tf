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

variable "schedule_lambda_arn" {
  description = "Schedule Lambda ARN"
  type        = string
}

variable "delete_lambda_arn" {
  description = "Delete Lambda ARN"
  type        = string
}

variable "status_lambda_arn" {
  description = "Status Lambda ARN"
  type        = string
}

variable "schedule_lambda_name" {
  description = "Schedule Lambda function name"
  type        = string
}

variable "delete_lambda_name" {
  description = "Delete Lambda function name"
  type        = string
}

variable "status_lambda_name" {
  description = "Status Lambda function name"
  type        = string
}

variable "throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
}

variable "throttle_rate_limit" {
  description = "API Gateway throttle rate limit"
  type        = number
}

variable "quota_limit" {
  description = "API Gateway monthly quota limit"
  type        = number
}

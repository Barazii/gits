#------------------------------------------------------------------------------
# General Configuration
#------------------------------------------------------------------------------
variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "gits"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-3"
}

#------------------------------------------------------------------------------
# VPC Configuration
#------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC Flow Logs in CloudWatch"
  type        = number
  default     = 14
}

variable "s3_prefix_list_id" {
  description = "Managed prefix list ID for S3 (region-specific)"
  type        = string
  default     = "pl-23ad484a" # eu-west-3
}

variable "dynamodb_prefix_list_id" {
  description = "Managed prefix list ID for DynamoDB (region-specific)"
  type        = string
  default     = "pl-abb451c2" # eu-west-3
}

#------------------------------------------------------------------------------
# GitHub IP Ranges (update periodically from https://api.github.com/meta)
#------------------------------------------------------------------------------
variable "github_core_ranges" {
  description = "GitHub core IP ranges"
  type        = list(string)
  default = [
    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20"
  ]
}

variable "github_web_api_ranges" {
  description = "Additional GitHub web/api IP ranges"
  type        = list(string)
  default = [
    "20.201.28.151/32",
    "20.205.243.166/32",
    "20.87.245.0/32",
    "4.237.22.38/32",
    "20.207.73.82/32",
    "20.175.192.147/32"
  ]
}

variable "github_ssh_ranges" {
  description = "Additional GitHub SSH IP ranges"
  type        = list(string)
  default = [
    "20.201.28.152/32",
    "20.205.243.160/32",
    "20.87.245.4/32",
    "4.237.22.40/32",
    "20.207.73.83/32",
    "20.175.192.146/32"
  ]
}

#------------------------------------------------------------------------------
# DynamoDB Configuration
#------------------------------------------------------------------------------
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB"
  type        = bool
  default     = true
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units (only used if billing mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units (only used if billing mode is PROVISIONED)"
  type        = number
  default     = 5
}

#------------------------------------------------------------------------------
# S3 Configuration
#------------------------------------------------------------------------------
variable "s3_enable_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_block_public_access" {
  description = "Block public access to S3 bucket"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# ECR Configuration
#------------------------------------------------------------------------------
variable "ecr_image_tag_mutability" {
  description = "ECR image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "ecr_scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "ecr_encryption_type" {
  description = "ECR encryption type (AES256 or KMS)"
  type        = string
  default     = "AES256"
}

variable "ecr_images_to_keep" {
  description = "Number of images to keep in ECR lifecycle policy"
  type        = number
  default     = 10
}

#------------------------------------------------------------------------------
# Lambda Configuration
#------------------------------------------------------------------------------
variable "lambda_schedule_timeout" {
  description = "Timeout for schedule Lambda (seconds)"
  type        = number
  default     = 30
}

variable "lambda_schedule_memory" {
  description = "Memory for schedule Lambda (MB)"
  type        = number
  default     = 512
}

variable "lambda_delete_timeout" {
  description = "Timeout for delete Lambda (seconds)"
  type        = number
  default     = 30
}

variable "lambda_delete_memory" {
  description = "Memory for delete Lambda (MB)"
  type        = number
  default     = 256
}

variable "lambda_status_timeout" {
  description = "Timeout for status Lambda (seconds)"
  type        = number
  default     = 15
}

variable "lambda_status_memory" {
  description = "Memory for status Lambda (MB)"
  type        = number
  default     = 256
}

variable "lambda_codebuildlens_timeout" {
  description = "Timeout for codebuildlens Lambda (seconds)"
  type        = number
  default     = 30
}

variable "lambda_codebuildlens_memory" {
  description = "Memory for codebuildlens Lambda (MB)"
  type        = number
  default     = 256
}

#------------------------------------------------------------------------------
# CodeBuild Configuration
#------------------------------------------------------------------------------
variable "codebuild_image" {
  description = "Docker image for CodeBuild"
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "codebuild_compute_type" {
  description = "Compute type for CodeBuild"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "codebuild_buildspec_file" {
  description = "Path to buildspec file"
  type        = string
  default     = "codebuild/buildspec.yaml"
}

variable "codebuild_timeout" {
  description = "Build timeout in minutes"
  type        = number
  default     = 30
}

variable "github_repo_url" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/Barazii/gits"
}

#------------------------------------------------------------------------------
# API Gateway Configuration
#------------------------------------------------------------------------------
variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 100
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit"
  type        = number
  default     = 50
}

variable "api_quota_limit" {
  description = "API Gateway monthly quota limit"
  type        = number
  default     = 5000
}

#------------------------------------------------------------------------------
# Secrets Configuration
#------------------------------------------------------------------------------
variable "github_token" {
  description = "GitHub personal access token for private repo access"
  type        = string
  sensitive   = true
  default     = ""
}

#------------------------------------------------------------------------------
# Lambda Image URIs (set after ECR images are pushed)
#------------------------------------------------------------------------------
variable "lambda_image_uri_schedule" {
  description = "ECR image URI for schedule Lambda"
  type        = string
  default     = ""
}

variable "lambda_image_uri_delete" {
  description = "ECR image URI for delete Lambda"
  type        = string
  default     = ""
}

variable "lambda_image_uri_status" {
  description = "ECR image URI for status Lambda"
  type        = string
  default     = ""
}

variable "lambda_image_uri_codebuildlens" {
  description = "ECR image URI for codebuildlens Lambda"
  type        = string
  default     = ""
}

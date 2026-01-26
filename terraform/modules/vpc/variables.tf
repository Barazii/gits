variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for subnets"
  type        = string
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC Flow Logs"
  type        = number
}

variable "vpc_flow_logs_role_arn" {
  description = "ARN of the IAM role for VPC Flow Logs"
  type        = string
}

variable "s3_prefix_list_id" {
  description = "Managed prefix list ID for S3"
  type        = string
}

variable "dynamodb_prefix_list_id" {
  description = "Managed prefix list ID for DynamoDB"
  type        = string
}

variable "github_core_ranges" {
  description = "GitHub core IP ranges"
  type        = list(string)
}

variable "github_web_api_ranges" {
  description = "Additional GitHub web/api IP ranges"
  type        = list(string)
}

variable "github_ssh_ranges" {
  description = "Additional GitHub SSH IP ranges"
  type        = list(string)
}

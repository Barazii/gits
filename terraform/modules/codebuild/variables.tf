variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  type        = string
}

variable "artifact_bucket_name" {
  description = "S3 bucket name for artifacts"
  type        = string
}

variable "build_image" {
  description = "Docker image for CodeBuild"
  type        = string
}

variable "compute_type" {
  description = "Compute type for CodeBuild"
  type        = string
}

variable "buildspec_file" {
  description = "Path to buildspec file"
  type        = string
}

variable "build_timeout" {
  description = "Build timeout in minutes"
  type        = number
}

variable "github_repo_url" {
  description = "GitHub repository URL"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID"
  type        = string
}

variable "codebuild_security_group_id" {
  description = "CodeBuild security group ID"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
  default     = ""
}

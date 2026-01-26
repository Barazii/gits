variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

output "schedule_repo_url" {
  description = "ECR repository URL for schedule Lambda"
  value       = aws_ecr_repository.schedule.repository_url
}

output "schedule_repo_arn" {
  description = "ECR repository ARN for schedule Lambda"
  value       = aws_ecr_repository.schedule.arn
}

output "schedule_base_repo_url" {
  description = "ECR repository URL for schedule Lambda base image"
  value       = aws_ecr_repository.schedule_base.repository_url
}

output "delete_repo_url" {
  description = "ECR repository URL for delete Lambda"
  value       = aws_ecr_repository.delete.repository_url
}

output "delete_repo_arn" {
  description = "ECR repository ARN for delete Lambda"
  value       = aws_ecr_repository.delete.arn
}

output "delete_base_repo_url" {
  description = "ECR repository URL for delete Lambda base image"
  value       = aws_ecr_repository.delete_base.repository_url
}

output "status_repo_url" {
  description = "ECR repository URL for status Lambda"
  value       = aws_ecr_repository.status.repository_url
}

output "status_repo_arn" {
  description = "ECR repository ARN for status Lambda"
  value       = aws_ecr_repository.status.arn
}

output "status_base_repo_url" {
  description = "ECR repository URL for status Lambda base image"
  value       = aws_ecr_repository.status_base.repository_url
}

output "codebuildlens_repo_url" {
  description = "ECR repository URL for codebuildlens Lambda"
  value       = aws_ecr_repository.codebuildlens.repository_url
}

output "codebuildlens_repo_arn" {
  description = "ECR repository ARN for codebuildlens Lambda"
  value       = aws_ecr_repository.codebuildlens.arn
}

output "codebuildlens_base_repo_url" {
  description = "ECR repository URL for codebuildlens Lambda base image"
  value       = aws_ecr_repository.codebuildlens_base.repository_url
}

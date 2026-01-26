output "project_name" {
  description = "CodeBuild project name"
  value       = aws_codebuild_project.main.name
}

output "project_arn" {
  description = "CodeBuild project ARN"
  value       = aws_codebuild_project.main.arn
}

output "project_id" {
  description = "CodeBuild project ID"
  value       = aws_codebuild_project.main.id
}

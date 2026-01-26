output "schedule_lambda_arn" {
  description = "ARN of the schedule Lambda function"
  value       = aws_lambda_function.schedule.arn
}

output "schedule_lambda_name" {
  description = "Name of the schedule Lambda function"
  value       = aws_lambda_function.schedule.function_name
}

output "delete_lambda_arn" {
  description = "ARN of the delete Lambda function"
  value       = aws_lambda_function.delete.arn
}

output "delete_lambda_name" {
  description = "Name of the delete Lambda function"
  value       = aws_lambda_function.delete.function_name
}

output "status_lambda_arn" {
  description = "ARN of the status Lambda function"
  value       = aws_lambda_function.status.arn
}

output "status_lambda_name" {
  description = "Name of the status Lambda function"
  value       = aws_lambda_function.status.function_name
}

output "codebuildlens_lambda_arn" {
  description = "ARN of the codebuildlens Lambda function"
  value       = aws_lambda_function.codebuildlens.arn
}

output "codebuildlens_lambda_name" {
  description = "Name of the codebuildlens Lambda function"
  value       = aws_lambda_function.codebuildlens.function_name
}

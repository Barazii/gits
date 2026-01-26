output "schedule_lambda_role_arn" {
  description = "ARN of the schedule Lambda IAM role"
  value       = aws_iam_role.schedule_lambda.arn
}

output "delete_lambda_role_arn" {
  description = "ARN of the delete Lambda IAM role"
  value       = aws_iam_role.delete_lambda.arn
}

output "status_lambda_role_arn" {
  description = "ARN of the status Lambda IAM role"
  value       = aws_iam_role.status_lambda.arn
}

output "codebuildlens_lambda_role_arn" {
  description = "ARN of the codebuildlens Lambda IAM role"
  value       = aws_iam_role.codebuildlens_lambda.arn
}

output "eventbridge_target_role_arn" {
  description = "ARN of the EventBridge target role"
  value       = aws_iam_role.eventbridge_target.arn
}

output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild.arn
}

output "vpc_flow_logs_role_arn" {
  description = "ARN of the VPC Flow Logs role"
  value       = aws_iam_role.vpc_flow_logs.arn
}

output "cloudformation_deployment_role_arn" {
  description = "ARN of the CloudFormation deployment role"
  value       = data.aws_iam_role.cloudformation_deployment.arn
}

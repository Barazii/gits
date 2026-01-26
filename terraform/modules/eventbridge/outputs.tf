output "codebuild_state_change_rule_arn" {
  description = "ARN of the CodeBuild state change EventBridge rule"
  value       = aws_cloudwatch_event_rule.codebuild_state_change.arn
}

output "codebuild_state_change_rule_name" {
  description = "Name of the CodeBuild state change EventBridge rule"
  value       = aws_cloudwatch_event_rule.codebuild_state_change.name
}

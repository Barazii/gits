# EventBridge Rule for CodeBuild state changes
resource "aws_cloudwatch_event_rule" "codebuild_state_change" {
  name        = "${var.project_name}-codebuild-state-change"
  description = "Triggers codebuildlens lambda on CodeBuild state change"

  event_pattern = jsonencode({
    source      = ["aws.codebuild"]
    detail-type = ["CodeBuild Build State Change"]
    detail = {
      "current-phase" = ["COMPLETED"]
    }
  })

  tags = {
    Name = "${var.project_name}-codebuild-state-change"
  }
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "codebuildlens" {
  rule      = aws_cloudwatch_event_rule.codebuild_state_change.name
  target_id = "CodeBuildLensLambda"
  arn       = var.codebuildlens_lambda_arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.codebuildlens_lambda_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.codebuild_state_change.arn
}

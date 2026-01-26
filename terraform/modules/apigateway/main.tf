#------------------------------------------------------------------------------
# REST API
#------------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "API Gateway for gits system"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

#------------------------------------------------------------------------------
# Schedule Resource and Method
#------------------------------------------------------------------------------
resource "aws_api_gateway_resource" "schedule" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "schedule"
}

resource "aws_api_gateway_method" "schedule" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.schedule.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "schedule" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.schedule.id
  http_method             = aws_api_gateway_method.schedule.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.schedule_lambda_arn}/invocations"
}

resource "aws_lambda_permission" "schedule" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.schedule_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*/*"
}

#------------------------------------------------------------------------------
# Delete Resource and Method
#------------------------------------------------------------------------------
resource "aws_api_gateway_resource" "delete" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "delete"
}

resource "aws_api_gateway_method" "delete" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.delete.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "delete" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.delete.id
  http_method             = aws_api_gateway_method.delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.delete_lambda_arn}/invocations"
}

resource "aws_lambda_permission" "delete" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.delete_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*/*"
}

#------------------------------------------------------------------------------
# Status Resource and Method
#------------------------------------------------------------------------------
resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "status"
}

resource "aws_api_gateway_method" "status" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.status.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "status" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.status.id
  http_method             = aws_api_gateway_method.status.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.status_lambda_arn}/invocations"
}

resource "aws_lambda_permission" "status" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.status_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*/*"
}

#------------------------------------------------------------------------------
# Deployment and Stage
#------------------------------------------------------------------------------
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.schedule.id,
      aws_api_gateway_method.schedule.id,
      aws_api_gateway_integration.schedule.id,
      aws_api_gateway_resource.delete.id,
      aws_api_gateway_method.delete.id,
      aws_api_gateway_integration.delete.id,
      aws_api_gateway_resource.status.id,
      aws_api_gateway_method.status.id,
      aws_api_gateway_integration.status.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.schedule,
    aws_api_gateway_integration.delete,
    aws_api_gateway_integration.status,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  tags = {
    Name = "${var.project_name}-prod-stage"
  }
}

#------------------------------------------------------------------------------
# API Key and Usage Plan
#------------------------------------------------------------------------------
resource "aws_api_gateway_api_key" "main" {
  name        = "${var.project_name}-api-key"
  description = "API Key for gits system"
  enabled     = true

  tags = {
    Name = "${var.project_name}-api-key"
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name        = "${var.project_name}-usage-plan"
  description = "Usage plan for gits API"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = var.throttle_burst_limit
    rate_limit  = var.throttle_rate_limit
  }

  quota_settings {
    limit  = var.quota_limit
    period = "MONTH"
  }

  tags = {
    Name = "${var.project_name}-usage-plan"
  }
}

resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.main.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.main.id
}

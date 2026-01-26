output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_url" {
  description = "API Gateway invoke URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}"
}

output "api_key_id" {
  description = "API Gateway API Key ID"
  value       = aws_api_gateway_api_key.main.id
}

output "api_key_value" {
  description = "API Gateway API Key value"
  value       = aws_api_gateway_api_key.main.value
  sensitive   = true
}

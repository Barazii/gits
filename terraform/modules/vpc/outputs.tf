output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "codebuild_security_group_id" {
  description = "CodeBuild security group ID"
  value       = aws_security_group.codebuild.id
}

output "schedule_lambda_security_group_id" {
  description = "Schedule Lambda security group ID"
  value       = aws_security_group.schedule_lambda.id
}

output "delete_lambda_security_group_id" {
  description = "Delete Lambda security group ID"
  value       = aws_security_group.delete_lambda.id
}

output "status_lambda_security_group_id" {
  description = "Status Lambda security group ID"
  value       = aws_security_group.status_lambda.id
}

output "codebuildlens_lambda_security_group_id" {
  description = "CodeBuildLens Lambda security group ID"
  value       = aws_security_group.codebuildlens_lambda.id
}

output "vpc_endpoint_security_group_id" {
  description = "VPC Endpoint security group ID"
  value       = aws_security_group.vpc_endpoint.id
}

output "github_https_prefix_list_id" {
  description = "Prefix List ID for GitHub HTTPS traffic"
  value       = aws_ec2_managed_prefix_list.github_https.id
}

output "github_ssh_prefix_list_id" {
  description = "Prefix List ID for GitHub SSH traffic"
  value       = aws_ec2_managed_prefix_list.github_ssh.id
}

output "flow_logs_log_group_name" {
  description = "CloudWatch Log Group name for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}

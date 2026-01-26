#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

#------------------------------------------------------------------------------
# Local Values
#------------------------------------------------------------------------------
locals {
  account_id         = data.aws_caller_identity.current.account_id
  availability_zone  = data.aws_availability_zones.available.names[0]
  dynamodb_table_name = "${var.project_name}-jobs"
  artifact_bucket_name = "${var.project_name}-artifacts"
}

#------------------------------------------------------------------------------
# IAM Module - Deploy first (no dependencies)
#------------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  project_name         = var.project_name
  aws_region           = var.aws_region
  account_id           = local.account_id
  dynamodb_table_name  = local.dynamodb_table_name
  artifact_bucket_name = local.artifact_bucket_name
}

#------------------------------------------------------------------------------
# VPC Module - Depends on IAM (for VPC Flow Logs role)
#------------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name             = var.project_name
  aws_region               = var.aws_region
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidr       = var.public_subnet_cidr
  private_subnet_cidr      = var.private_subnet_cidr
  availability_zone        = local.availability_zone
  flow_logs_retention_days = var.flow_logs_retention_days
  vpc_flow_logs_role_arn   = module.iam.vpc_flow_logs_role_arn
  s3_prefix_list_id        = var.s3_prefix_list_id
  dynamodb_prefix_list_id  = var.dynamodb_prefix_list_id
  github_core_ranges       = var.github_core_ranges
  github_web_api_ranges    = var.github_web_api_ranges
  github_ssh_ranges        = var.github_ssh_ranges

  depends_on = [module.iam]
}

#------------------------------------------------------------------------------
# DynamoDB Module
#------------------------------------------------------------------------------
module "dynamodb" {
  source = "./modules/dynamodb"

  table_name             = local.dynamodb_table_name
  billing_mode           = var.dynamodb_billing_mode
  point_in_time_recovery = var.dynamodb_point_in_time_recovery
  read_capacity          = var.dynamodb_read_capacity
  write_capacity         = var.dynamodb_write_capacity
  project_name           = var.project_name
}

#------------------------------------------------------------------------------
# S3 Module
#------------------------------------------------------------------------------
module "s3" {
  source = "./modules/s3"

  bucket_name         = local.artifact_bucket_name
  enable_versioning   = var.s3_enable_versioning
  block_public_access = var.s3_block_public_access
  project_name        = var.project_name
}

#------------------------------------------------------------------------------
# ECR Module
#------------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  project_name         = var.project_name
  image_tag_mutability = var.ecr_image_tag_mutability
  scan_on_push         = var.ecr_scan_on_push
  encryption_type      = var.ecr_encryption_type
  images_to_keep       = var.ecr_images_to_keep
}

#------------------------------------------------------------------------------
# Secrets Manager Module (only if GitHub token is provided)
#------------------------------------------------------------------------------
module "secrets" {
  count  = var.github_token != "" ? 1 : 0
  source = "./modules/secrets"

  project_name = var.project_name
  github_token = var.github_token
}

#------------------------------------------------------------------------------
# CodeBuild Module
#------------------------------------------------------------------------------
module "codebuild" {
  source = "./modules/codebuild"

  project_name                = var.project_name
  codebuild_service_role_arn  = module.iam.codebuild_service_role_arn
  artifact_bucket_name        = local.artifact_bucket_name
  build_image                 = var.codebuild_image
  compute_type                = var.codebuild_compute_type
  buildspec_file              = var.codebuild_buildspec_file
  build_timeout               = var.codebuild_timeout
  github_repo_url             = var.github_repo_url
  vpc_id                      = module.vpc.vpc_id
  private_subnet_id           = module.vpc.private_subnet_id
  codebuild_security_group_id = module.vpc.codebuild_security_group_id
  github_token                = var.github_token

  depends_on = [module.vpc, module.iam, module.secrets]
}

#------------------------------------------------------------------------------
# Lambda Module (only if Lambda images are provided)
#------------------------------------------------------------------------------
module "lambda" {
  count  = var.lambda_image_uri_schedule != "" ? 1 : 0
  source = "./modules/lambda"

  project_name                        = var.project_name
  aws_region                          = var.aws_region
  account_id                          = local.account_id
  dynamodb_table_name                 = local.dynamodb_table_name
  artifact_bucket_name                = local.artifact_bucket_name
  codebuild_project_name              = var.project_name
  eventbridge_target_role_arn         = module.iam.eventbridge_target_role_arn
  private_subnet_id                   = module.vpc.private_subnet_id
  schedule_lambda_role_arn            = module.iam.schedule_lambda_role_arn
  delete_lambda_role_arn              = module.iam.delete_lambda_role_arn
  status_lambda_role_arn              = module.iam.status_lambda_role_arn
  codebuildlens_lambda_role_arn       = module.iam.codebuildlens_lambda_role_arn
  schedule_lambda_security_group_id   = module.vpc.schedule_lambda_security_group_id
  delete_lambda_security_group_id     = module.vpc.delete_lambda_security_group_id
  status_lambda_security_group_id     = module.vpc.status_lambda_security_group_id
  codebuildlens_lambda_security_group_id = module.vpc.codebuildlens_lambda_security_group_id
  image_uri_schedule                  = var.lambda_image_uri_schedule
  image_uri_delete                    = var.lambda_image_uri_delete
  image_uri_status                    = var.lambda_image_uri_status
  image_uri_codebuildlens             = var.lambda_image_uri_codebuildlens
  schedule_timeout                    = var.lambda_schedule_timeout
  schedule_memory                     = var.lambda_schedule_memory
  delete_timeout                      = var.lambda_delete_timeout
  delete_memory                       = var.lambda_delete_memory
  status_timeout                      = var.lambda_status_timeout
  status_memory                       = var.lambda_status_memory
  codebuildlens_timeout               = var.lambda_codebuildlens_timeout
  codebuildlens_memory                = var.lambda_codebuildlens_memory

  depends_on = [module.vpc, module.iam, module.ecr]
}

#------------------------------------------------------------------------------
# API Gateway Module (only if Lambdas are created)
#------------------------------------------------------------------------------
module "apigateway" {
  count  = var.lambda_image_uri_schedule != "" ? 1 : 0
  source = "./modules/apigateway"

  project_name          = var.project_name
  aws_region            = var.aws_region
  account_id            = local.account_id
  schedule_lambda_arn   = module.lambda[0].schedule_lambda_arn
  delete_lambda_arn     = module.lambda[0].delete_lambda_arn
  status_lambda_arn     = module.lambda[0].status_lambda_arn
  schedule_lambda_name  = module.lambda[0].schedule_lambda_name
  delete_lambda_name    = module.lambda[0].delete_lambda_name
  status_lambda_name    = module.lambda[0].status_lambda_name
  throttle_burst_limit  = var.api_throttle_burst_limit
  throttle_rate_limit   = var.api_throttle_rate_limit
  quota_limit           = var.api_quota_limit

  depends_on = [module.lambda]
}

#------------------------------------------------------------------------------
# EventBridge Module (only if Lambdas are created)
#------------------------------------------------------------------------------
module "eventbridge" {
  count  = var.lambda_image_uri_schedule != "" ? 1 : 0
  source = "./modules/eventbridge"

  project_name             = var.project_name
  codebuildlens_lambda_arn = module.lambda[0].codebuildlens_lambda_arn
  codebuildlens_lambda_name = module.lambda[0].codebuildlens_lambda_name

  depends_on = [module.lambda]
}

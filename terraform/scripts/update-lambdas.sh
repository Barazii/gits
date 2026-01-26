#!/bin/bash
#------------------------------------------------------------------------------
# Update Lambda Functions Script
# Updates Lambda function code without full redeploy
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$TERRAFORM_DIR")"

# Configuration
PROJECT_NAME="${PROJECT_NAME:-gits}"
REGION="${AWS_REGION:-eu-west-3}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=============================================="
echo "Updating Lambda Function Code"
echo "=============================================="
echo "Project:  $PROJECT_NAME"
echo "Region:   $REGION"
echo "=============================================="
echo ""

# Function to get latest image URI
get_image_uri() {
    local repo_name=$1
    local repo_uri=$(aws ecr describe-repositories --repository-names $repo_name --query 'repositories[0].repositoryUri' --output text --region $REGION)
    local image_digest=$(aws ecr describe-images --repository-name $repo_name --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageDigest' --output text --region $REGION)
    echo "$repo_uri@$image_digest"
}

# Update each Lambda function
update_lambda() {
    local function_name=$1
    local repo_name=$2
    
    echo "Updating $function_name..."
    
    IMAGE_URI=$(get_image_uri $repo_name)
    
    aws lambda update-function-code \
        --function-name $function_name \
        --image-uri $IMAGE_URI \
        --region $REGION \
        --no-cli-pager
    
    echo "$function_name updated successfully!"
}

# Update all Lambda functions
update_lambda "${PROJECT_NAME}-schedule" "${PROJECT_NAME}-schedule-lambda"
update_lambda "${PROJECT_NAME}-delete" "${PROJECT_NAME}-delete-lambda"
update_lambda "${PROJECT_NAME}-status" "${PROJECT_NAME}-status-lambda"
update_lambda "${PROJECT_NAME}-codebuildlens" "${PROJECT_NAME}-codebuildlens-lambda"

echo ""
echo "=============================================="
echo "All Lambda Functions Updated!"
echo "=============================================="

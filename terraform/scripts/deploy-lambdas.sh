#!/bin/bash
#------------------------------------------------------------------------------
# Deploy Lambdas Script
# Applies Terraform with Lambda image URIs
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$TERRAFORM_DIR")"

# Configuration
PROJECT_NAME="${PROJECT_NAME:-gits}"
REGION="${AWS_REGION:-eu-west-3}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cd "$TERRAFORM_DIR"

echo "=============================================="
echo "Deploying Lambda Functions"
echo "=============================================="
echo "Project:  $PROJECT_NAME"
echo "Region:   $REGION"
echo "Account:  $ACCOUNT_ID"
echo "=============================================="
echo ""

# Get Lambda image URIs
get_image_uri() {
    local repo_name=$1
    local repo_uri=$(aws ecr describe-repositories --repository-names $repo_name --query 'repositories[0].repositoryUri' --output text --region $REGION 2>/dev/null)
    local image_digest=$(aws ecr describe-images --repository-name $repo_name --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageDigest' --output text --region $REGION 2>/dev/null)
    
    if [ -n "$repo_uri" ] && [ -n "$image_digest" ] && [ "$image_digest" != "None" ]; then
        echo "$repo_uri@$image_digest"
    else
        echo ""
    fi
}

echo "Fetching Lambda image URIs..."

IMAGE_URI_SCHEDULE=$(get_image_uri "${PROJECT_NAME}-schedule-lambda")
IMAGE_URI_DELETE=$(get_image_uri "${PROJECT_NAME}-delete-lambda")
IMAGE_URI_STATUS=$(get_image_uri "${PROJECT_NAME}-status-lambda")
IMAGE_URI_CODEBUILDLENS=$(get_image_uri "${PROJECT_NAME}-codebuildlens-lambda")

# Check if all images are available
if [ -z "$IMAGE_URI_SCHEDULE" ] || [ -z "$IMAGE_URI_DELETE" ] || [ -z "$IMAGE_URI_STATUS" ] || [ -z "$IMAGE_URI_CODEBUILDLENS" ]; then
    echo "Error: Not all Lambda images are available in ECR."
    echo ""
    echo "Please run: ./scripts/build-and-push-lambdas.sh"
    exit 1
fi

echo "Schedule Lambda:      $IMAGE_URI_SCHEDULE"
echo "Delete Lambda:        $IMAGE_URI_DELETE"
echo "Status Lambda:        $IMAGE_URI_STATUS"
echo "CodeBuildLens Lambda: $IMAGE_URI_CODEBUILDLENS"
echo ""

# Apply Terraform with Lambda image URIs
echo "Applying Terraform with Lambda images..."
terraform apply -auto-approve \
    -var="lambda_image_uri_schedule=$IMAGE_URI_SCHEDULE" \
    -var="lambda_image_uri_delete=$IMAGE_URI_DELETE" \
    -var="lambda_image_uri_status=$IMAGE_URI_STATUS" \
    -var="lambda_image_uri_codebuildlens=$IMAGE_URI_CODEBUILDLENS"

echo ""
echo "=============================================="
echo "Lambda Functions Deployed Successfully!"
echo "=============================================="
echo ""

# Show outputs
echo "Terraform Outputs:"
terraform output

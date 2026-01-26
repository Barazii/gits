#!/bin/bash
#------------------------------------------------------------------------------
# Build and Push Lambda Images Script
# Builds Lambda container images and pushes to ECR
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$TERRAFORM_DIR")"

# Configuration
PROJECT_NAME="${PROJECT_NAME:-gits}"
REGION="${AWS_REGION:-eu-west-3}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cd "$PROJECT_ROOT"

echo "=============================================="
echo "Building and Pushing Lambda Container Images"
echo "=============================================="
echo "Project:  $PROJECT_NAME"
echo "Region:   $REGION"
echo "Account:  $ACCOUNT_ID"
echo "=============================================="
echo ""

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Function to build and push Lambda
build_and_push_lambda() {
    local lambda_name=$1
    local lambda_dir=$2
    
    echo ""
    echo "----------------------------------------------"
    echo "Building $lambda_name Lambda..."
    echo "----------------------------------------------"
    
    # Build base image first
    if [ -f "$lambda_dir/baseimage/Dockerfile" ]; then
        echo "Building base image for $lambda_name..."
        cd "$PROJECT_ROOT/$lambda_dir/baseimage"
        
        BASE_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$PROJECT_NAME-$lambda_name-lambda-base"
        docker build -t $BASE_REPO:latest .
        docker push $BASE_REPO:latest
        
        cd "$PROJECT_ROOT"
    fi
    
    # Build main Lambda image
    echo "Building main image for $lambda_name..."
    cd "$PROJECT_ROOT/$lambda_dir"
    
    REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$PROJECT_NAME-$lambda_name-lambda"
    docker build -t $REPO:latest .
    docker push $REPO:latest
    
    cd "$PROJECT_ROOT"
    
    echo "$lambda_name Lambda built and pushed successfully!"
}

# Build all Lambda images
build_and_push_lambda "schedule" "schedule_lambda"
build_and_push_lambda "delete" "delete_lambda"
build_and_push_lambda "status" "status_lambda"
build_and_push_lambda "codebuildlens" "codebuildlense_lambda"

echo ""
echo "=============================================="
echo "All Lambda images built and pushed!"
echo "=============================================="
echo ""
echo "Next step: Run ./scripts/deploy-lambdas.sh"

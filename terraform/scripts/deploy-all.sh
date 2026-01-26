#!/bin/bash
#------------------------------------------------------------------------------
# Full Deployment Script
# Deploys everything in one go
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$TERRAFORM_DIR")"

# Configuration
PROJECT_NAME="${PROJECT_NAME:-gits}"
REGION="${AWS_REGION:-eu-west-3}"

echo "=============================================="
echo "Full Gits Infrastructure Deployment"
echo "=============================================="
echo "Project: $PROJECT_NAME"
echo "Region:  $REGION"
echo "=============================================="
echo ""

# Check if terraform.tfvars exists first
if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    echo "Warning: terraform.tfvars not found."
    echo "Creating from terraform.tfvars.example..."
    cp "$TERRAFORM_DIR/terraform.tfvars.example" "$TERRAFORM_DIR/terraform.tfvars"
    echo "Please edit terraform.tfvars with your configuration, then re-run this script."
    exit 1
fi

# Check for GitHub token
if [ -z "$TF_VAR_github_token" ]; then
    if [ -f "$HOME/.gits/config" ]; then
        export TF_VAR_github_token=$(grep '^GITHUB_TOKEN=' "$HOME/.gits/config" | cut -d'=' -f2-)
    fi
    
    if [ -z "$TF_VAR_github_token" ]; then
        echo "Error: GitHub token not set."
        echo "Set it via: export TF_VAR_github_token='your-token'"
        echo "Or add GITHUB_TOKEN to ~/.gits/config"
        exit 1
    fi
fi

# Bootstrap IAM role if it doesn't exist
DEPLOYMENT_ROLE_NAME="${PROJECT_NAME}-cloudformation-deployment-role"
if ! aws iam get-role --role-name "$DEPLOYMENT_ROLE_NAME" &>/dev/null; then
    echo "Deployment role not found. Running bootstrap..."
    "$SCRIPT_DIR/bootstrap-iam.sh"
fi

# Assume the deployment IAM role
source "$SCRIPT_DIR/assume-role.sh"

cd "$SCRIPT_DIR"

# Step 1: Initialize Terraform
echo "Step 1: Initializing Terraform..."
./init.sh

# Step 2: Deploy base infrastructure (ECR, VPC, IAM, etc.)
echo ""
echo "Step 2: Deploying base infrastructure..."
./deploy.sh

# Step 3: Build and push Lambda images
echo ""
echo "Step 3: Building and pushing Lambda images..."
./build-and-push-lambdas.sh

# Step 4: Deploy Lambda functions and remaining resources
echo ""
echo "Step 4: Deploying Lambda functions..."
./deploy-lambdas.sh

echo ""
echo "=============================================="
echo "Full Deployment Complete!"
echo "=============================================="
echo ""

cd "$TERRAFORM_DIR"
echo "API Gateway URL:"
terraform output -raw api_gateway_url 2>/dev/null || echo "Not available yet"
echo ""

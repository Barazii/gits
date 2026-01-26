#!/bin/bash
#------------------------------------------------------------------------------
# Terraform Deploy Script
# Deploys the infrastructure to AWS
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$TERRAFORM_DIR")"

# Configuration
PROJECT_NAME="${PROJECT_NAME:-gits}"
REGION="${AWS_REGION:-eu-west-3}"

cd "$TERRAFORM_DIR"

echo "=============================================="
echo "Deploying Gits Infrastructure with Terraform"
echo "=============================================="
echo "Project: $PROJECT_NAME"
echo "Region:  $REGION"
echo "=============================================="
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "Warning: terraform.tfvars not found."
    echo "Creating from terraform.tfvars.example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "Please edit terraform.tfvars with your configuration."
    exit 1
fi

# Check for GitHub token
if [ -z "$TF_VAR_github_token" ]; then
    # Try to read from config file
    if [ -f "$HOME/.gits/config" ]; then
        export TF_VAR_github_token=$(grep '^GITHUB_TOKEN=' "$HOME/.gits/config" | cut -d'=' -f2-)
    fi
    
    if [ -z "$TF_VAR_github_token" ]; then
        echo "Warning: GitHub token not set."
        echo "Set it via: export TF_VAR_github_token='your-token'"
        echo "Or add GITHUB_TOKEN to ~/.gits/config"
    fi
fi

# Initialize if needed
if [ ! -d ".terraform" ]; then
    echo "Terraform not initialized. Running init..."
    terraform init
fi

# Apply terraform (use plan if exists)
if [ -f "tfplan" ]; then
    echo "Applying saved plan..."
    terraform apply tfplan
    rm -f tfplan
else
    echo "Running terraform apply..."
    terraform apply -auto-approve
fi

echo ""
echo "=============================================="
echo "Base Infrastructure Deployed!"
echo "=============================================="
echo ""
echo "Next steps to complete deployment:"
echo ""
echo "1. Build and push Lambda images:"
echo "   ./scripts/build-and-push-lambdas.sh"
echo ""
echo "2. Apply with Lambda images:"
echo "   ./scripts/deploy-lambdas.sh"
echo ""

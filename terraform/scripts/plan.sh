#!/bin/bash
#------------------------------------------------------------------------------
# Terraform Plan Script
# Shows what changes will be made to infrastructure
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

echo "=============================================="
echo "Running Terraform Plan..."
echo "=============================================="

# Check if tfvars file exists
if [ ! -f "terraform.tfvars" ]; then
    echo "Warning: terraform.tfvars not found."
    echo "Using terraform.tfvars.example as reference."
    echo ""
fi

# Run terraform plan
terraform plan -out=tfplan

echo ""
echo "=============================================="
echo "Plan saved to tfplan"
echo "=============================================="
echo ""
echo "To apply this plan, run:"
echo "  ./scripts/deploy.sh"

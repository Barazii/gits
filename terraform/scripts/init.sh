#!/bin/bash
#------------------------------------------------------------------------------
# Terraform Initialization Script
# Initializes Terraform backend and downloads providers
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

echo "=============================================="
echo "Initializing Terraform..."
echo "=============================================="

# Initialize Terraform
terraform init

echo ""
echo "=============================================="
echo "Terraform initialized successfully!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Copy terraform.tfvars.example to terraform.tfvars"
echo "  2. Edit terraform.tfvars with your configuration"
echo "  3. Run: ./scripts/plan.sh"
echo "  4. Run: ./scripts/deploy.sh"

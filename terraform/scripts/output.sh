#!/bin/bash
#------------------------------------------------------------------------------
# Terraform Output Script
# Shows Terraform outputs in a formatted way
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

echo "=============================================="
echo "Terraform Outputs"
echo "=============================================="
echo ""

terraform output

#!/bin/bash
#------------------------------------------------------------------------------
# Terraform Destroy Script
# Destroys all infrastructure
#------------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

echo "=============================================="
echo "Destroying Gits Infrastructure"
echo "=============================================="
echo ""
echo "WARNING: This will destroy all resources!"
echo ""

read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Check if deployment role exists and assume it
ROLE_NAME="${PROJECT_NAME:-gits}-cloudformation-deployment-role"
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo ""
    echo "Assuming deployment role..."
    source "$SCRIPT_DIR/assume-role.sh"
fi

# Get image URIs if Lambdas were deployed
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
REGION="${AWS_REGION:-eu-west-3}"
PROJECT_NAME="${PROJECT_NAME:-gits}"

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

IMAGE_URI_SCHEDULE=$(get_image_uri "${PROJECT_NAME}-schedule-lambda")
IMAGE_URI_DELETE=$(get_image_uri "${PROJECT_NAME}-delete-lambda")
IMAGE_URI_STATUS=$(get_image_uri "${PROJECT_NAME}-status-lambda")
IMAGE_URI_CODEBUILDLENS=$(get_image_uri "${PROJECT_NAME}-codebuildlens-lambda")

# Build destroy command with image URIs if available
DESTROY_ARGS=""
if [ -n "$IMAGE_URI_SCHEDULE" ]; then
    DESTROY_ARGS="$DESTROY_ARGS -var=lambda_image_uri_schedule=$IMAGE_URI_SCHEDULE"
    DESTROY_ARGS="$DESTROY_ARGS -var=lambda_image_uri_delete=$IMAGE_URI_DELETE"
    DESTROY_ARGS="$DESTROY_ARGS -var=lambda_image_uri_status=$IMAGE_URI_STATUS"
    DESTROY_ARGS="$DESTROY_ARGS -var=lambda_image_uri_codebuildlens=$IMAGE_URI_CODEBUILDLENS"
fi

echo "Running terraform destroy..."
terraform destroy -auto-approve $DESTROY_ARGS

echo ""
echo "=============================================="
echo "Infrastructure Destroyed"
echo "=============================================="

# Ask about bootstrap IAM resources
echo ""
read -p "Do you also want to delete the bootstrap IAM role and policy? (yes/no): " delete_bootstrap

if [[ "$delete_bootstrap" == "yes" ]]; then
    echo "Deleting bootstrap IAM resources..."
    
    # Unset assumed role credentials to use base credentials
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    
    POLICY_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/${PROJECT_NAME}-terraform-deployment-policy"
    
    # Detach policy from role
    aws iam detach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$POLICY_ARN" 2>/dev/null || true
    
    # Delete all policy versions except default
    for version in $(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?!IsDefaultVersion].VersionId' --output text 2>/dev/null); do
        aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$version" 2>/dev/null || true
    done
    
    # Delete policy
    aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null || true
    
    # Delete role
    aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
    
    echo "Bootstrap IAM resources deleted."
fi

echo ""
echo "Cleanup complete!"

#!/bin/bash
#------------------------------------------------------------------------------
# Assume IAM Role for Deployment
# Sources AWS credentials for the deployment role
#------------------------------------------------------------------------------

# Disable AWS CLI pager
export AWS_PAGER=""

# Configuration
DEPLOYMENT_ROLE_ARN="${DEPLOYMENT_ROLE_ARN:-arn:aws:iam::482497089777:role/gits-cloudformation-deployment-role}"
SESSION_NAME="terraform-deploy-$(date +%s)"

# Check if already assumed (avoid re-assuming in nested scripts)
if [ -n "$AWS_SESSION_ASSUMED" ]; then
    return 0 2>/dev/null || exit 0
fi

echo "Assuming deployment role..."
echo "Role: $DEPLOYMENT_ROLE_ARN"

# Assume the role
CREDS=$(aws sts assume-role \
    --role-arn "$DEPLOYMENT_ROLE_ARN" \
    --role-session-name "$SESSION_NAME" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text 2>&1)

if [ $? -ne 0 ]; then
    echo "Error: Failed to assume role"
    echo "$CREDS"
    exit 1
fi

# Parse credentials
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')
export AWS_SESSION_ASSUMED=true

echo "Successfully assumed deployment role"
echo ""

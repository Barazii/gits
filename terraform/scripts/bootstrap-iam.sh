#!/bin/bash
#------------------------------------------------------------------------------
# Bootstrap IAM Role for Terraform Deployment
# Creates the deployment role with minimum required permissions
# This only needs to run once (or when the role doesn't exist)
#------------------------------------------------------------------------------

set -e

# Disable AWS CLI pager
export AWS_PAGER=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="${PROJECT_NAME:-gits}"
REGION="${AWS_REGION:-eu-west-3}"
ROLE_NAME="${PROJECT_NAME}-cloudformation-deployment-role"
POLICY_NAME="${PROJECT_NAME}-terraform-deployment-policy"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=============================================="
echo "Bootstrapping IAM Role for Terraform Deployment"
echo "=============================================="
echo "Project:    $PROJECT_NAME"
echo "Region:     $REGION"
echo "Account:    $ACCOUNT_ID"
echo "Role Name:  $ROLE_NAME"
echo "=============================================="
echo ""

# Check if role already exists
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo "Role '$ROLE_NAME' already exists."
    echo "Updating policy..."
else
    echo "Creating IAM role '$ROLE_NAME'..."
    
    # Create trust policy (allows account root and current user)
    CURRENT_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    TRUST_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::${ACCOUNT_ID}:root",
                    "${CURRENT_USER_ARN}"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
    
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "Role for Terraform/CloudFormation deployments" \
        --tags Key=Project,Value="$PROJECT_NAME" Key=ManagedBy,Value=bootstrap-script
    
    echo "Role created successfully."
fi

# Create/update the policy with all required permissions
echo "Creating/updating deployment policy..."

POLICY_DOCUMENT=$(cat <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DynamoDB",
            "Effect": "Allow",
            "Action": "dynamodb:*",
            "Resource": "*"
        },
        {
            "Sid": "S3",
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "*"
        },
        {
            "Sid": "IAM",
            "Effect": "Allow",
            "Action": [
                "iam:*Role*",
                "iam:*Policy*",
                "iam:*InstanceProfile*",
                "iam:PassRole"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECR",
            "Effect": "Allow",
            "Action": "ecr:*",
            "Resource": "*"
        },
        {
            "Sid": "SecretsManager",
            "Effect": "Allow",
            "Action": "secretsmanager:*",
            "Resource": "*"
        },
        {
            "Sid": "CodeBuild",
            "Effect": "Allow",
            "Action": "codebuild:*",
            "Resource": "*"
        },
        {
            "Sid": "Lambda",
            "Effect": "Allow",
            "Action": "lambda:*",
            "Resource": "*"
        },
        {
            "Sid": "EventBridge",
            "Effect": "Allow",
            "Action": "events:*",
            "Resource": "*"
        },
        {
            "Sid": "APIGateway",
            "Effect": "Allow",
            "Action": "apigateway:*",
            "Resource": "*"
        },
        {
            "Sid": "CloudWatchLogs",
            "Effect": "Allow",
            "Action": "logs:*",
            "Resource": "*"
        },
        {
            "Sid": "VPC",
            "Effect": "Allow",
            "Action": "ec2:*",
            "Resource": "*"
        },
        {
            "Sid": "STS",
            "Effect": "Allow",
            "Action": "sts:GetCallerIdentity",
            "Resource": "*"
        }
    ]
}
EOF
)

# Check if policy exists and delete old versions if needed
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
    echo "Policy exists, updating..."
    
    # Delete non-default versions to make room for new one
    VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    for VERSION in $VERSIONS; do
        echo "Deleting policy version $VERSION..."
        aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION"
    done
    
    # Create new version and set as default
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document "$POLICY_DOCUMENT" \
        --set-as-default
else
    echo "Creating new policy..."
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document "$POLICY_DOCUMENT" \
        --description "Policy for Terraform deployments"
fi

# Attach policy to role
echo "Attaching policy to role..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN" 2>/dev/null || true

echo ""
echo "=============================================="
echo "Bootstrap Complete!"
echo "=============================================="
echo "Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "You can now run: ./deploy-all.sh"
echo "=============================================="

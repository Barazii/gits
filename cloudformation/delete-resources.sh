#!/bin/bash

set -e

# Configuration
PROJECT_NAME="gits"
REGION="eu-west-3"

# Store original credentials to allow re-assuming the role
ORIGINAL_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
ORIGINAL_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
ORIGINAL_AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

# Function to assume the deployment role (can be called multiple times to refresh)
assume_deployment_role() {
    echo "Assuming CloudFormation deployment role..."
    # Temporarily restore original credentials to assume role
    if [ -n "$ORIGINAL_AWS_ACCESS_KEY_ID" ]; then
        export AWS_ACCESS_KEY_ID="$ORIGINAL_AWS_ACCESS_KEY_ID"
        export AWS_SECRET_ACCESS_KEY="$ORIGINAL_AWS_SECRET_ACCESS_KEY"
        export AWS_SESSION_TOKEN="$ORIGINAL_AWS_SESSION_TOKEN"
    else
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        unset AWS_SESSION_TOKEN
    fi
    
    ASSUME_ROLE_OUTPUT=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "deletion")
    export AWS_ACCESS_KEY_ID=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SessionToken')
    echo "Role assumed successfully."
}

# Get the CloudFormation deployment role ARN from stack outputs
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "gits-iam" --query 'Stacks[0].Outputs[?OutputKey==`CloudFormationDeploymentRoleArn`].OutputValue' --output text --region "$REGION")
echo "Retrieved role ARN: $ROLE_ARN"

# Initial role assumption
assume_deployment_role

# Function to delete a stack
delete_stack() {
    local stack_name=$1

    echo "Deleting $stack_name..."
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$REGION"
    echo "Waiting for $stack_name deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$stack_name" \
        --region "$REGION"
    echo "$stack_name deleted successfully."
}

# Delete stacks in reverse dependency order to avoid dependency issues

# API Gateway depends on Lambdas
delete_stack "gits-apigateway"

# EventBridge depends on Lambdas
delete_stack "gits-events"

# Lambdas depend on VPC and IAM
delete_stack "gits-lambdas"

# CodeBuild depends on VPC and IAM
delete_stack "gits-codebuild"

# Secret Manager and DynamoDB don't have dependencies
delete_stack "gits-secret-manager"
delete_stack "gits-dynamodb"

echo "success!"
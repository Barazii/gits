#!/bin/bash

set -e

# Configuration
PROJECT_NAME="gits"
REGION="eu-west-3"
GITHUB_TOKEN=$(grep '^GITHUB_TOKEN=' ~/.gits/config | cut -d'=' -f2-)

# Store original credentials to allow re-assuming the role
ORIGINAL_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
ORIGINAL_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
ORIGINAL_AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

# Deploy IAM stack first with current credentials
echo "Deploying IAM stack first..."
aws cloudformation deploy \
    --stack-name "gits-iam" \
    --template-file "iam.yaml" \
    --region "$REGION" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides ProjectName=$PROJECT_NAME DynamoTableName=${PROJECT_NAME}-jobs ArtifactBucketName=${PROJECT_NAME}-artifacts
echo "IAM stack deployed successfully."

# Get the CloudFormation deployment role ARN from stack outputs
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "gits-iam" --query 'Stacks[0].Outputs[?OutputKey==`CloudFormationDeploymentRoleArn`].OutputValue' --output text --region "$REGION")
echo "Retrieved role ARN: $ROLE_ARN"

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
    
    ASSUME_ROLE_OUTPUT=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "deployment")
    export AWS_ACCESS_KEY_ID=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $ASSUME_ROLE_OUTPUT | jq -r '.Credentials.SessionToken')
    echo "Role assumed successfully."
}

# Initial role assumption
assume_deployment_role

# Function to deploy a stack
deploy_stack() {
    local stack_name=$1
    local template_file=$2
    local capabilities=$3
    local params=$4

    echo "Deploying $stack_name..."
    aws cloudformation deploy \
        --stack-name "$stack_name" \
        --template-file "$template_file" \
        --region "$REGION" \
        $capabilities \
        --parameter-overrides $params
    echo "$stack_name deployed successfully."
}

# Deploy remaining stacks in order
deploy_stack "gits-ecr" "ecr.yaml" "" "ProjectName=$PROJECT_NAME ImageTagMutability=MUTABLE ScanOnPush=true EncryptionType=AES256"

echo "Building and pushing Lambda images..."

# Refresh credentials before each Lambda build (base image builds take ~8-9 minutes each)
assume_deployment_role
../gitsops_lambda/baseimage/build_and_push.sh
../gitsops_lambda/deploy.sh
REPO_URI_SCHEDULE=$(aws ecr describe-repositories --repository-names gits-schedule-lambda --query 'repositories[0].repositoryUri' --output text --region $REGION)
IMAGE_URI_SCHEDULE=$REPO_URI_SCHEDULE@$(aws ecr describe-images --repository-name gits-schedule-lambda --query 'imageDetails[0].imageDigest' --output text --region $REGION)

assume_deployment_role
../delete_lambda/baseimage/build_and_push.sh
../delete_lambda/deploy.sh
REPO_URI_DELETE=$(aws ecr describe-repositories --repository-names gits-delete-lambda --query 'repositories[0].repositoryUri' --output text --region $REGION)
IMAGE_URI_DELETE=$REPO_URI_DELETE@$(aws ecr describe-images --repository-name gits-delete-lambda --query 'imageDetails[0].imageDigest' --output text --region $REGION)

assume_deployment_role
../getstatus_lambda/baseimage/build_and_push.sh
../getstatus_lambda/deploy.sh
REPO_URI_STATUS=$(aws ecr describe-repositories --repository-names gits-status-lambda --query 'repositories[0].repositoryUri' --output text --region $REGION)
IMAGE_URI_STATUS=$REPO_URI_STATUS@$(aws ecr describe-images --repository-name gits-status-lambda --query 'imageDetails[0].imageDigest' --output text --region $REGION)

assume_deployment_role
../codebuildlense_lambda/baseimage/build_and_push.sh
../codebuildlense_lambda/deploy.sh
REPO_URI_CODEBUILD_LENS=$(aws ecr describe-repositories --repository-names gits-codebuildlens-lambda --query 'repositories[0].repositoryUri' --output text --region $REGION)
IMAGE_URI_CODEBUILD_LENS=$REPO_URI_CODEBUILD_LENS@$(aws ecr describe-images --repository-name gits-codebuildlens-lambda --query 'imageDetails[0].imageDigest' --output text --region $REGION)

# Refresh credentials before deploying remaining stacks
assume_deployment_role

deploy_stack "gits-s3" "s3.yaml" "" "BucketName=${PROJECT_NAME}-artifacts EnableVersioning=true BlockPublicAccess=true RetainOnDelete=false"

deploy_stack "gits-dynamodb" "dynamodb.yaml" "" "TableName=${PROJECT_NAME}-jobs PointInTimeRecovery=ENABLED BillingMode=PAY_PER_REQUEST"

deploy_stack "gits-secret-manager" "secretmanager.yaml" "" "ProjectName=$PROJECT_NAME GitHubToken=$GITHUB_TOKEN"

deploy_stack "gits-vpc" "vpc.yaml" "" "ProjectName=$PROJECT_NAME"

deploy_stack "gits-codebuild" "codebuild.yaml" "" "ProjectName=$PROJECT_NAME ArtifactBucketName=${PROJECT_NAME}-artifacts"

deploy_stack "gits-lambdas" "lambdas.yaml" "--capabilities CAPABILITY_IAM" "ProjectName=$PROJECT_NAME DynamoTableName=${PROJECT_NAME}-jobs ArtifactBucketName=${PROJECT_NAME}-artifacts CodeBuildProjectName=$PROJECT_NAME ImageUriSchedule=$IMAGE_URI_SCHEDULE ImageUriDelete=$IMAGE_URI_DELETE ImageUriStatus=$IMAGE_URI_STATUS ImageUriCodeBuildLens=$IMAGE_URI_CODEBUILD_LENS"

deploy_stack "gits-events" "eventbridge.yaml" "" "ProjectName=$PROJECT_NAME"

deploy_stack "gits-apigateway" "apigateway.yaml" "" "ProjectName=$PROJECT_NAME"

echo "All stacks deployed successfully!"

# Unset credentials
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
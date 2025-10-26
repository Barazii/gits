#!/bin/bash
cd "$(dirname "$0")"
ACCOUNT_ID=$(aws sts get-caller-identity --no-cli-pager --query Account --output text)
REGION=eu-north-1
REPO_NAME=delete-lambda
FUNCTION_NAME=gitsdelete
IMAGE_URI=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

# Build & Push
docker build -t $REPO_NAME .
aws ecr get-login-password --no-cli-pager --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
if ! aws ecr describe-repositories --no-cli-pager --repository-names $REPO_NAME --region $REGION >/dev/null 2>&1; then
    aws ecr create-repository --no-cli-pager --repository-name $REPO_NAME --image-scanning-configuration scanOnPush=true
fi
docker tag $REPO_NAME:latest $IMAGE_URI
docker push $IMAGE_URI

# Deploy to Lambda
aws lambda update-function-code \
  --no-cli-pager \
  --function-name $FUNCTION_NAME \
  --image-uri $IMAGE_URI \
  --publish

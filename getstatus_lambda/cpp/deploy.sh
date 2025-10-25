#!/bin/bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=eu-north-1
REPO_NAME=getstatus-lambda
IMAGE_URI=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

# Build & Push
docker build -t $REPO_NAME .
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
aws ecr create-repository --repository-name $REPO_NAME --image-scanning-configuration scanOnPush=true || true
docker tag $REPO_NAME:latest $IMAGE_URI
docker push $IMAGE_URI

# Deploy to Lambda
# aws lambda update-function-code \
#   --function-name $REPO_NAME \
#   --image-uri $IMAGE_URI \
#   --publish

echo "Deployed! Test with: aws lambda invoke --function-name $REPO_NAME out.txt"

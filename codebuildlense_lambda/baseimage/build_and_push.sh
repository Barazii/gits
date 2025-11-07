#!/bin/bash

# Script to build and push the base image to ECR

cd "$(dirname "$0")"
ACCOUNT_ID=$(aws sts get-caller-identity --no-cli-pager --query Account --output text)
REGION=eu-north-1
REPO_NAME=codebuildlense-lambda-base
IMAGE_URI=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

# Build
docker build -t $REPO_NAME .

# Login to ECR
aws ecr get-login-password --no-cli-pager --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Create repository if it doesn't exist
if ! aws ecr describe-repositories --no-cli-pager --repository-names $REPO_NAME --region $REGION >/dev/null 2>&1; then
    aws ecr create-repository --no-cli-pager --repository-name $REPO_NAME --image-scanning-configuration scanOnPush=true
fi

# Tag & Push
docker tag $REPO_NAME:latest $IMAGE_URI
docker push $IMAGE_URI
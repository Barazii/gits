#!/usr/bin/env bash
set -euo pipefail

# Simple Lambda deployment script (no CloudFormation) for gits project.
# Requires AWS CLI configured (or run in CloudShell) with permissions:
#  - lambda:GetFunction lambda:CreateFunction lambda:UpdateFunctionCode lambda:UpdateFunctionConfiguration
#  - iam:PassRole on the Lambda execution role
#  - logs:CreateLogGroup/Stream logs:PutLogEvents (role side)
#
# Reads ~/.gits/config for required environment values:
#   AWS_APP_REGION (or AWS_REGION)
#   AWS_BUCKET_NAME
#   AWS_CODEBUILD_PROJECT_NAME
#   AWS_ACCOUNT_ID
#   EVENTBRIDGE_TARGET_ROLE_ARN
#   (optional) LAMBDA_EXEC_ROLE_ARN  -> Needed only on first create
#   (optional) FUNCTION_NAME (default: gits-scheduler)
#   (optional) TIMEOUT_SECONDS (default: 30)
#   (optional) MEMORY_MB (default: 256)
#
# Usage:
#   scripts/deploy_lambda.sh              # package + create/update
#   FUNCTION_NAME=my-func scripts/deploy_lambda.sh
#
# After deployment you can test:
#   aws lambda invoke --function-name <name> out.json --cli-binary-format raw-in-base64-out \
#     --payload '{"body":"{\\"schedule_time\\":\\"2030-01-01T12:00:00Z\\",\\"repo_url\\":\\"https://github.com/owner/repo.git\\",\\"zip_filename\\":\\"t.zip\\",\\"zip_base64\\":\\"UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA==\\",\\"github_token_secret\\":\\"secret-name\\"}"}'

CONFIG_FILE="$HOME/.gits/config"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

FUNCTION_NAME=${FUNCTION_NAME:-${AWS_LAMBDA_FUNCTION_NAME:-gits-scheduler}}
REGION=${AWS_APP_REGION:-${AWS_REGION:-eu-central-1}}
LAMBDA_ROLE=${LAMBDA_EXEC_ROLE_ARN:-}
TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-30}
MEMORY_MB=${MEMORY_MB:-256}

REQUIRED_VARS=(AWS_BUCKET_NAME AWS_CODEBUILD_PROJECT_NAME AWS_ACCOUNT_ID EVENTBRIDGE_TARGET_ROLE_ARN)
for v in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Error: $v not set (check $CONFIG_FILE)" >&2
    exit 1
  fi
done

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI not found" >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="$ROOT_DIR/.dist"
PACKAGE_ZIP="$BUILD_DIR/lambda_package.zip"
HANDLER_DIR="$ROOT_DIR/lambda_function"
HANDLER_FILE="$HANDLER_DIR/lambda_handler.py"

if [[ ! -f "$HANDLER_FILE" ]]; then
  echo "Error: handler file not found at $HANDLER_FILE" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
rm -f "$PACKAGE_ZIP"

echo "Packaging Lambda source..."
(
  cd "$HANDLER_DIR"
  zip -q "$PACKAGE_ZIP" lambda_handler.py
)
echo "Created package: $PACKAGE_ZIP ($(du -h "$PACKAGE_ZIP" | cut -f1))"

echo "Checking if Lambda function $FUNCTION_NAME exists..."
set +e
aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1
EXISTS=$?
set -e

if [[ $EXISTS -ne 0 ]]; then
  if [[ -z "$LAMBDA_ROLE" ]]; then
    echo "Error: Function does not exist and LAMBDA_EXEC_ROLE_ARN not provided." >&2
    exit 1
  fi
  echo "Creating new Lambda function $FUNCTION_NAME..."
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --handler lambda_function.lambda_handler \
    --role "$LAMBDA_ROLE" \
    --timeout "$TIMEOUT_SECONDS" \
    --memory-size "$MEMORY_MB" \
    --zip-file "fileb://$PACKAGE_ZIP" \
    --region "$REGION" >/dev/null
  CREATED=1
else
  echo "Updating code for existing function $FUNCTION_NAME..."
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$PACKAGE_ZIP" \
    --region "$REGION" >/dev/null
  CREATED=0
fi

echo "Updating environment variables..."
aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --timeout "$TIMEOUT_SECONDS" \
  --memory-size "$MEMORY_MB" \
  --environment "Variables={AWS_BUCKET_NAME=$AWS_BUCKET_NAME,AWS_CODEBUILD_PROJECT_NAME=$AWS_CODEBUILD_PROJECT_NAME,AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID,EVENTBRIDGE_TARGET_ROLE_ARN=$EVENTBRIDGE_TARGET_ROLE_ARN,AWS_APP_REGION=$REGION}" \
  --region "$REGION" >/dev/null

echo "Publishing new version..."
VERSION=$(aws lambda publish-version --function-name "$FUNCTION_NAME" --region "$REGION" --query 'Version' --output text)
echo "Published version $VERSION"

echo "Deployment complete. Function: $FUNCTION_NAME Version: $VERSION"
echo "Test quickly: aws lambda invoke --function-name $FUNCTION_NAME out.json --region $REGION --payload '{"body":"{\\"schedule_time\\":\\"2030-01-01T12:00:00Z\\",\\"repo_url\\":\\"https://github.com/owner/repo.git\\",\\"zip_filename\\":\\"t.zip\\",\\"zip_base64\\":\\"UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA==\\",\\"github_token_secret\\":\\"secret-name\\"}"}' --cli-binary-format raw-in-base64-out && cat out.json && echo"

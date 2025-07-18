#!/bin/bash

# gits: A tool to schedule Git operations for any Git repository
# Usage: gits <schedule-time>
# Example: gits "2025-07-17T15:00:00Z"

CONFIG_FILE="$HOME/.gits/config"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Input parameter: schedule time
SCHEDULE_TIME="$1"

# Validate input
if [ -z "$SCHEDULE_TIME" ]; then
    echo "Error: Schedule time required."
    echo "Usage: $0 <schedule-time>"
    echo "Example: $0 '2025-07-17T15:00:00Z'"
    exit 1
fi

# Check if inside a Git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Must be run inside a Git repository."
    exit 1
fi

# Get the repository URL dynamically
REPO_URL=$(git remote get-url origin 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$REPO_URL" ]; then
    echo "Error: Could not retrieve repository URL. Ensure 'origin' remote is set."
    exit 1
fi

# Generate unique identifiers
PREFIX="changes-$(date +%s)"
RULE_NAME="gits-$(date +%s)"

# Identify modified files
echo "Identifying modified files..."
git status --porcelain | grep '^ M\|^ A\|^ D' | awk '{print $2}' > /tmp/gits-modified-files.txt
if [ ! -s /tmp/gits-modified-files.txt ]; then
    echo "Error: No modified files found."
    rm -f /tmp/gits-modified-files.txt
    exit 1
fi

# Create a zip of modified files
echo "Creating zip of modified files..."
ZIP_FILE="/tmp/gits-changes-$(date +%s).zip"
cat /tmp/gits-modified-files.txt | xargs zip -r "$ZIP_FILE"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create zip."
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

# Upload to S3
echo "Uploading to S3 ($AWS_BUCKET_NAME)..."
aws s3 cp "$ZIP_FILE" "s3://$AWS_BUCKET_NAME/$PREFIX/$(basename "$ZIP_FILE")" --region "$AWS_REGION"
if [ $? -ne 0 ]; then
    echo "Error: Failed to upload to S3."
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

# Convert ISO 8601 to cron format (e.g., "2025-07-17T15:00:00Z" -> "0 15 17 7 ? 2025")
CRON_EXPR=$(date -u -d "$SCHEDULE_TIME" "+%M %H %d %m ? %Y" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Error: Invalid SCHEDULE_TIME format. Use ISO 8601 (e.g., '2025-07-17T15:00:00Z')."
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

# Create EventBridge rule
echo "Creating EventBridge rule..."
aws events put-rule \
    --name "$RULE_NAME" \
    --schedule-expression "cron($CRON_EXPR)" \
    --state ENABLED \
    --region "$AWS_REGION"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create EventBridge rule."
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

# Set CodeBuild as target
echo "Setting CodeBuild target..."
aws events put-targets --region "$AWS_REGION" --rule "$RULE_NAME" --targets '[
  {
    "Id": "Target1",
    "Arn": "arn:aws:codebuild:'$AWS_REGION':482497089777:project/'$AWS_CODEBUILD_PROJECT_NAME'",
    "RoleArn": "arn:aws:iam::482497089777:role/EventBridgeServiceRoleForCodeBuild",
    "Input": "{\"environmentVariablesOverride\":[{\"name\":\"S3_PATH\",\"value\":\"s3://'$AWS_BUCKET_NAME'/'$PREFIX'/'$(basename "$ZIP_FILE")'\",\"type\":\"PLAINTEXT\"},{\"name\":\"REPO_URL\",\"value\":\"'$REPO_URL'\",\"type\":\"PLAINTEXT\"}]}"
  }
]'
if [ $? -ne 0 ]; then
    echo "Error: Failed to set CodeBuild target."
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

echo "Successfully scheduled Git operations for $SCHEDULE_TIME on $REPO_URL."
rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
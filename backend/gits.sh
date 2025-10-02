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
    echo "Usage: gits <schedule-time>"
    echo "Example: gits '2025-07-17T15:00:00Z' (UTC time) or gits '2025-07-17T15:00:00' (CEST/CET time)"
    exit 1
fi

# Time conversion
if [[ "$SCHEDULE_TIME" =~ Z$ ]]; then
    # Already in UTC
    UTC_TIME="$SCHEDULE_TIME"
else
    # Assume local CEST/CET time, convert to UTC
    UTC_TIME=$(TZ="Europe/Berlin" date -d "$SCHEDULE_TIME" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Error: Invalid time format. Use YYYY-MM-DDTHH:MM:SS"
        echo "Example: gits '2025-07-17T15:00:00'"
        exit 1
    fi
fi

# Check if schedule time is in the past
CURRENT_UTC=$(date -u +%s)
UTC_TIMESTAMP=$(date -u -d "$UTC_TIME" +%s 2>/dev/null)
if [ $? -ne 0 ] || [ $UTC_TIMESTAMP -le $CURRENT_UTC ]; then
    echo "Error: Schedule time must be in the future."
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

# Check if REPO_URL is not HTTPS
if [[ ! "$REPO_URL" =~ ^https://.*$ ]]; then
    echo "Error: Repository URL must be HTTPS."
    echo "Update your remote URL to HTTPS format using: git remote set-url origin <https-url>"
    exit 1
fi

# Generate unique identifiers
PREFIX="changes-$(date +%s)"
RULE_NAME="gits-$(date +%s)"

# Identify modified files
git status --porcelain | grep '^ M\|^ A\|^ D' | awk '{print $2}' > /tmp/gits-modified-files.txt
if [ ! -s /tmp/gits-modified-files.txt ]; then
    echo "Error: No modified files found."
    rm -f /tmp/gits-modified-files.txt
    exit 1
fi

# Create a zip of modified files
ZIP_FILE="/tmp/gits-changes-$(date +%s).zip"
cat /tmp/gits-modified-files.txt | xargs zip -r "$ZIP_FILE" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to create zip."
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

# NOTE: S3 upload moved to Lambda (no local AWS credentials needed).

# Convert ISO 8601 to AWS EventBridge cron format (e.g., "2025-07-17T15:00:00Z" -> "0 15 17 7 ? 2025")
CRON_EXPR=$(date -u -d "$UTC_TIME" "+%M %H %d %m ? %Y" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Error: Invalid time format."
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

###############################################
# API Gateway + Lambda proxy call             #
###############################################

# Expect API_GATEWAY_URL in config pointing to the deployed endpoint for the Lambda proxy (POST method)
if [ -z "$API_GATEWAY_URL" ]; then
    echo "Error: API_GATEWAY_URL not set in ~/.gits/config"
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

if [ -z "$AWS_GITHUB_TOKEN_SECRET" ]; then
    echo "Error: AWS_GITHUB_TOKEN_SECRET not set in ~/.gits/config"
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

# Base64 encode the zip (single line)
ZIP_B64=$(base64 -w 0 "$ZIP_FILE" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ZIP_B64" ]; then
    echo "Error: Failed to base64 encode zip file."
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

PAYLOAD=$(cat <<EOF
{
  "schedule_time": "$UTC_TIME",
  "repo_url": "$REPO_URL",
  "zip_filename": "$(basename "$ZIP_FILE")",
  "zip_base64": "$ZIP_B64",
  "github_token_secret": "$AWS_GITHUB_TOKEN_SECRET"
}
EOF
)

# Perform HTTP POST (no AWS credentials required locally)
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_GATEWAY_URL" -H 'Content-Type: application/json' -d "$PAYLOAD")
BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
STATUS=$(echo "$HTTP_RESPONSE" | tail -n1)

if [ "$STATUS" != "200" ]; then
    echo "Error: Remote scheduling failed (status $STATUS). Response: $BODY"
    rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
    exit 1
fi

echo "Successfully scheduled via remote Lambda: $BODY"

echo "Done. Scheduled Git operations for $SCHEDULE_TIME on $REPO_URL (remote)."
rm -f /tmp/gits-modified-files.txt "$ZIP_FILE"
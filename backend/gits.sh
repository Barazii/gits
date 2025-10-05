#!/usr/bin/env bash

# gits: A tool to schedule Git operations for any Git repository
# Usage: gits <schedule-time> [-m|--message "commit message"] [-f|--file <path>]...
# Example: gits "2025-07-17T15:00:00Z" -m "Fix: update readme" -f backend/gits.sh -f README.md

CONFIG_FILE="$HOME/.gits/config"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Parse arguments
SCHEDULE_TIME=""
COMMIT_MESSAGE=""
declare -a FILES

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--message)
            shift
            COMMIT_MESSAGE="${1:-}"
            ;;
        -f|--file)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error: -f|--file requires a file path" >&2
                exit 2
            fi
            # Support comma-separated list or multiple -f flags
            IFS=',' read -r -a _tmpfiles <<< "${1}"
            for _f in "${_tmpfiles[@]}"; do
                [[ -z "$_f" ]] && continue
                FILES+=("$_f")
            done
            ;;
        -h|--help)
            echo "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..."
            echo "Examples:"
            echo "  gits '2025-07-17T15:00:00Z' -m 'Fix: docs'"
            echo "  gits '2025-07-17T15:00:00Z' -f app.py -f README.md"
            echo "  gits '2025-07-17T15:00:00Z' -f app.py,README.md"
            exit 0
            ;;
        *)
            if [[ -z "$SCHEDULE_TIME" ]]; then
                SCHEDULE_TIME="$1"
            else
                echo "Error: unexpected argument: $1" >&2
                echo "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..." >&2
                exit 2
            fi
            ;;
    esac
    shift || true
done

# Validate input
if [ -z "$SCHEDULE_TIME" ]; then
    echo "Error: Schedule time required."
    echo "Usage: gits <schedule-time> [-m|--message \"commit message\"] [-f|--file <path>]..."
    echo "Example:" 
    echo "  gits '2025-07-17T15:00:00Z' -m 'Fix: docs'"
    echo "  gits '2025-07-17T15:00:00Z' -f app.py -f README.md"
    echo "  gits '2025-07-17T15:00:00Z' -f app.py,README.md"
    exit 1
fi

# Time validation & conversion (strict ISO 8601 UTC format: YYYY-MM-DDTHH:MM:SSZ)
ISO_UTC_REGEX='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if [[ "$SCHEDULE_TIME" =~ $ISO_UTC_REGEX ]]; then
    UTC_TIME="$SCHEDULE_TIME"
else
    echo "Error: Time must be in ISO 8601 UTC format: YYYY-MM-DDTHH:MM:SSZ (e.g. 2025-07-17T15:00:00Z)"
    exit 1
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

# Identify files to include
LIST_FILE="/tmp/gits-modified-files.txt"
rm -f "$LIST_FILE"

if [[ ${#FILES[@]} -gt 0 ]]; then
    # Validate provided files exist locally
    _missing=0
    for f in "${FILES[@]}"; do
        if [[ ! -e "$f" ]]; then
            echo "Error: specified file not found: $f" >&2
            _missing=1
        fi
    done
    if [[ $_missing -ne 0 ]]; then
        exit 1
    fi
    printf '%s\n' "${FILES[@]}" > "$LIST_FILE"
else
    # Auto-detect modified/added files in working tree (excludes untracked '??' and deleted ' D')
    git status --porcelain | grep '^ M\|^ A' | awk '{print $2}' > "$LIST_FILE"
    if [ ! -s "$LIST_FILE" ]; then
        echo "Error: No modified files found. Use -f to specify files explicitly."
        rm -f "$LIST_FILE"
        exit 1
    fi
fi

# Create a zip of modified files
ZIP_FILE="/tmp/gits-changes-$(date +%s).zip"
zip -r "$ZIP_FILE" -@ < "$LIST_FILE" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to create zip."
    rm -f "$LIST_FILE" "$ZIP_FILE"
    exit 1
fi

# Convert ISO 8601 to AWS EventBridge cron format (e.g., "2025-07-17T15:00:00Z" -> "0 15 17 7 ? 2025")
CRON_EXPR=$(date -u -d "$UTC_TIME" "+%M %H %d %m ? %Y" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Error: Invalid time format."
    rm -f "$LIST_FILE" "$ZIP_FILE"
    exit 1
fi

# Expect API_GATEWAY_URL in config pointing to the deployed endpoint for the Lambda proxy (POST method)
if [ -z "$API_GATEWAY_URL" ]; then
    echo "Error: API_GATEWAY_URL not set in ~/.gits/config"
    rm -f "$LIST_FILE" "$ZIP_FILE"
    exit 1
fi

if [ -z "$AWS_GITHUB_TOKEN_SECRET" ]; then
    echo "Error: AWS_GITHUB_TOKEN_SECRET not set in ~/.gits/config"
    rm -f "$LIST_FILE" "$ZIP_FILE"
    exit 1
fi

# Base64 encode the zip (single line)
ZIP_B64=$(base64 -w 0 "$ZIP_FILE" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ZIP_B64" ]; then
    echo "Error: Failed to base64 encode zip file."
    rm -f "$LIST_FILE" "$ZIP_FILE"
    exit 1
fi

# Escape commit message for JSON
CM_ESCAPED="$COMMIT_MESSAGE"
CM_ESCAPED=${CM_ESCAPED//\\/\\\\}
CM_ESCAPED=${CM_ESCAPED//\"/\\\"}
CM_ESCAPED=${CM_ESCAPED//$'\n'/\\n}
CM_ESCAPED=${CM_ESCAPED//$'\r'/\\r}
CM_ESCAPED=${CM_ESCAPED//$'\t'/\\t}

PAYLOAD=$(cat <<EOF
{
    "schedule_time": "$UTC_TIME",
    "repo_url": "$REPO_URL",
    "zip_filename": "$(basename "$ZIP_FILE")",
    "zip_base64": "$ZIP_B64",
    "github_token_secret": "$AWS_GITHUB_TOKEN_SECRET",
    "github_user": "$GITHUB_USER",
    "github_email": "$GITHUB_EMAIL",
    "commit_message": "$CM_ESCAPED"
}
EOF
)

# Perform HTTP POST
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_GATEWAY_URL" -H 'Content-Type: application/json' -d "$PAYLOAD")
BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
STATUS=$(echo "$HTTP_RESPONSE" | tail -n1)

if [ "$STATUS" != "200" ]; then
    echo "Error: Remote scheduling failed (status $STATUS). Response: $BODY"
    rm -f "$LIST_FILE" "$ZIP_FILE"
    exit 1
fi

rm -f "$LIST_FILE" "$ZIP_FILE"
echo "Successfully scheduled"
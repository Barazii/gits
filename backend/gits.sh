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

# Identify files to include and detect deletions/renames
LIST_FILE="/tmp/gits-modified-files.txt"
EPOCH_TS=$(date +%s)
MANIFEST_FILE="/tmp/.gits-manifest-${EPOCH_TS}.json"
MANIFEST_REPO_COPY=".gits-manifest-${EPOCH_TS}.json"

cleanup() {
  rm -f "$LIST_FILE" "$ZIP_FILE" "$MANIFEST_FILE" "$MANIFEST_REPO_COPY"
}

# Gather git status once (with rename detection)
GIT_STATUS=$(git status --porcelain -M)

# Build sets for deletes and rename-old-sides
declare -a DELETED_PATHS
declare -a RENAME_OLDS
declare -a RENAME_NEWS

while IFS= read -r _line; do
    X="${_line:0:1}"; Y="${_line:1:1}"

    # Deleted file in working tree: " D path" or "D  path"
    if [[ "$X" == "D" || "$Y" == "D" ]]; then
        _p="${_line:3}"
        DELETED_PATHS+=("$_p")
    fi

    # Rename: "R  old -> new"
    if [[ "$X" == "R" || "$Y" == "R" ]]; then
        # Extract old and new using sed (handles simple paths without newlines)
        rest="${_line:3}"
        _pair=$(printf '%s' "$rest" | sed -E 's/^(.+)[[:space:]]->[[:space:]](.+)$/\1|\2/')
        _old="${_pair%%|*}"; _new="${_pair##*|}"
        RENAME_OLDS+=("$_old"); RENAME_NEWS+=("$_new")
    fi
done < <(printf '%s\n' "$GIT_STATUS")

# Helper: check if value is in array
in_array() {
    local needle="$1"; shift
    local x
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

declare -a FILES_TO_ZIP

if [[ ${#FILES[@]} -gt 0 ]]; then
    # Validate provided files: allow missing if they are deleted/renamed according to git status
    for f in "${FILES[@]}"; do
        if [[ -e "$f" ]]; then
            FILES_TO_ZIP+=("$f")
            continue
        fi
        # Not present on disk: check if it's a deleted path or part of a rename
        if in_array "$f" "${DELETED_PATHS[@]}" || in_array "$f" "${RENAME_OLDS[@]}" || in_array "$f" "${RENAME_NEWS[@]}"; then
            # It's a deletion or a rename side; don't add to zip, will add to manifest
            continue
        fi
        echo "Error: file not found: $f" >&2
        exit 1
    done
else
    # Auto-detect modified/deleted files in working tree (include untracked and modified)
    # Keep behavior for content to zip; deletions handled via manifest below
    mapfile -t FILES_TO_ZIP < <(git status --porcelain | grep -E '^\?\? |^.M |^M. ' | awk '{print $2}')
    # Include the new side of renames so content is present in the zip
    for i in "${!RENAME_NEWS[@]}"; do
        _new="${RENAME_NEWS[$i]}"
        if [[ -e "$_new" ]]; then in_array "$_new" "${FILES_TO_ZIP[@]}" || FILES_TO_ZIP+=("$_new"); fi
    done
    if [[ ${#FILES_TO_ZIP[@]} -eq 0 && ${#DELETED_PATHS[@]} -eq 0 && ${#RENAME_OLDS[@]} -eq 0 ]]; then
        echo "No changes found."
        exit 1
    fi
fi

# Filter deletions/renames to the user-specified set when -f provided
declare -a DELETES_FOR_MANIFEST
if [[ ${#FILES[@]} -gt 0 ]]; then
    for d in "${DELETED_PATHS[@]}"; do
        if in_array "$d" "${FILES[@]}"; then
            DELETES_FOR_MANIFEST+=("$d")
        fi
    done
    for i in "${!RENAME_OLDS[@]}"; do
        _old="${RENAME_OLDS[$i]}"; _new="${RENAME_NEWS[$i]}"
        if in_array "$_old" "${FILES[@]}" && in_array "$_new" "${FILES[@]}"; then
            # Ensure new path content is included when available
            if [[ -e "$_new" ]]; then in_array "$_new" "${FILES_TO_ZIP[@]}" || FILES_TO_ZIP+=("$_new"); fi
            DELETES_FOR_MANIFEST+=("$_old")
        fi
    done
else
    # Include all deletions and rename-old paths
    DELETES_FOR_MANIFEST=("${DELETED_PATHS[@]}")
    for _old in "${RENAME_OLDS[@]}"; do DELETES_FOR_MANIFEST+=("$_old"); done
fi

# De-duplicate FILES_TO_ZIP and DELETES_FOR_MANIFEST
dedup_array() {
    declare -A seen
    local out=()
    local item
    for item in "$@"; do
        [[ -z "$item" ]] && continue
        if [[ -z "${seen[$item]}" ]]; then
            seen[$item]=1
            out+=("$item")
        fi
    done
    printf '%s\n' "${out[@]}"
}

mapfile -t FILES_TO_ZIP < <(dedup_array "${FILES_TO_ZIP[@]}")
mapfile -t DELETES_FOR_MANIFEST < <(dedup_array "${DELETES_FOR_MANIFEST[@]}")

# Prepare list file to zip
if [[ ${#FILES_TO_ZIP[@]} -gt 0 ]]; then
    printf '%s\n' "${FILES_TO_ZIP[@]}" > "$LIST_FILE"
else
    # Touch an empty list for now; we'll still include the manifest below
    : > "$LIST_FILE"
fi

# Build manifest JSON capturing deletions (and implicitly renames via old paths)
{
    echo '{'
    echo '  "deleted": ['
    for i in "${!DELETES_FOR_MANIFEST[@]}"; do
        p="${DELETES_FOR_MANIFEST[$i]}"
        printf '    "%s"' "${p//\"/\\\"}"
        if [[ $i -lt $((${#DELETES_FOR_MANIFEST[@]} - 1)) ]]; then echo ','; else echo; fi
    done
    echo '  ]'
    echo '}'
} > "$MANIFEST_FILE"

# Always include the manifest in the zip at repo root so CodeBuild can apply deletions
cp "$MANIFEST_FILE" "$MANIFEST_REPO_COPY"
echo "$MANIFEST_REPO_COPY" >> "$LIST_FILE"

# Create a zip of modified files + manifest
ZIP_FILE="/tmp/gits-changes-$(date +%s).zip"
zip -r "$ZIP_FILE" -@ < "$LIST_FILE" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to create zip."
    cleanup
    exit 1
fi

# Convert ISO 8601 to AWS EventBridge cron format (e.g., "2025-07-17T15:00:00Z" -> "0 15 17 7 ? 2025")
CRON_EXPR=$(date -u -d "$UTC_TIME" "+%M %H %d %m ? %Y" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Error: Invalid time format."
    cleanup
    exit 1
fi

# Expect API_GATEWAY_URL in config pointing to the deployed endpoint for the Lambda proxy (POST method)
if [ -z "$API_GATEWAY_URL" ]; then
    echo "Error: API_GATEWAY_URL not set in ~/.gits/config"
    cleanup
    exit 1
fi

if [ -z "$AWS_GITHUB_TOKEN_SECRET" ]; then
    echo "Error: AWS_GITHUB_TOKEN_SECRET not set in ~/.gits/config"
    cleanup
    exit 1
fi

if [ -z "$USER_ID" ]; then
    echo "Error: USER_ID not set in ~/.gits/config"
    cleanup
    exit 1
fi

# Base64 encode the zip (single line)
ZIP_B64=$(base64 -w 0 "$ZIP_FILE" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ZIP_B64" ]; then
    echo "Error: Failed to base64 encode zip file."
    cleanup
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
    "commit_message": "$CM_ESCAPED",
    "user_id": "$USER_ID"
}
EOF
)

# Perform HTTP POST
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_GATEWAY_URL" -H 'Content-Type: application/json' -d "$PAYLOAD")
BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
STATUS=$(echo "$HTTP_RESPONSE" | tail -n1)

if [ "$STATUS" != "200" ]; then
    echo "Error: Remote scheduling failed (status $STATUS). Response: $BODY"
    cleanup
    exit 1
fi

cleanup
echo "Successfully scheduled"
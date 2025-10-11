#!/usr/bin/env bash

# Update function code.
# Usage:
#   ./deployment/deploy_lambda.sh [--publish]


FUNCTION_NAME="gitsops"
REGION="eu-north-1"

PUBLISH_FLAG=""
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH_FLAG="--publish" ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SRC_DIR="$ROOT_DIR/gitsops_lambda"
HANDLER_FILE="$SRC_DIR/lambda_function.py"
BUILD_DIR="$ROOT_DIR/.dist"
ZIP_FILE="$BUILD_DIR/lambda_code.zip"

if [[ ! -f "$HANDLER_FILE" ]]; then
  echo "Error: handler not found at $HANDLER_FILE" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
rm -f "$ZIP_FILE"

pushd "$SRC_DIR" >/dev/null
zip -q "$ZIP_FILE" lambda_function.py
popd >/dev/null

aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file "fileb://$ZIP_FILE" \
  --region "$REGION" \
  $PUBLISH_FLAG >/dev/null

rm -rf "$BUILD_DIR"

echo "Deployment complete."; [[ -n "$PUBLISH_FLAG" ]] && echo "(New version published)"
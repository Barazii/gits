#!/usr/bin/env bash
set -euo pipefail

# Deploy the backend gits.sh to a system-wide executable.
# Usage:
#   ./deployment/deploy_backend.sh


SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SRC_FILE="$ROOT_DIR/backend/gits.sh"
TARGET="/usr/local/bin/gits"

# ensure source file exists
if [[ ! -f "$SRC_FILE" ]]; then
	echo "Error: source script not found: $SRC_FILE" >&2
	exit 1
fi

chmod +x "$SRC_FILE"

# ensure target directory exists
TARGET_DIR=$(dirname "$TARGET")
if [[ ! -d "$TARGET_DIR" ]]; then
	echo "Error: target directory not found" >&2
	exit 1
fi

sudo cp "$SRC_FILE" "$TARGET"
sudo chmod 755 "$TARGET"

echo "Installation complete."

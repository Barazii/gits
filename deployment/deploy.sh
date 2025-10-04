#!/usr/bin/env bash
set -euo pipefail

# Wrapper to run both backend and lambda deployments.
# Usage:
#   ./deployment/deploy.sh [--publish] [--backend-only | --lambda-only]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BACKEND_SCRIPT="$SCRIPT_DIR/deploy_backend.sh"
LAMBDA_SCRIPT="$SCRIPT_DIR/deploy_lambda.sh"

RUN_BACKEND=true
RUN_LAMBDA=true
LAMBDA_ARGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--publish)
			LAMBDA_ARGS+=("--publish")
			;;
		--backend-only)
			RUN_BACKEND=true
			RUN_LAMBDA=false
			;;
		--lambda-only)
			RUN_BACKEND=false
			RUN_LAMBDA=true
			;;
		-h|--help)
			echo "Usage: $0 [--publish] [--backend-only | --lambda-only]"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			echo "Usage: $0 [--publish] [--backend-only | --lambda-only]" >&2
			exit 2
			;;
	esac
	shift || true
done

# Ensure scripts exist and are executable
[[ ! -f "$BACKEND_SCRIPT" ]] && { echo "Error: $BACKEND_SCRIPT not found" >&2; exit 1; }
[[ ! -f "$LAMBDA_SCRIPT" ]] && { echo "Error: $LAMBDA_SCRIPT not found" >&2; exit 1; }

chmod +x "$BACKEND_SCRIPT" "$LAMBDA_SCRIPT"

if $RUN_BACKEND; then
	echo "==> Deploying backend"
	"$BACKEND_SCRIPT"
fi

if $RUN_LAMBDA; then
	echo "==> Deploying Lambda"
	"$LAMBDA_SCRIPT" "${LAMBDA_ARGS[@]}"
fi

echo "All requested deployments completed."

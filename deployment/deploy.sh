#!/usr/bin/env bash

set -e

# Wrapper to run both backend and lambda deployments.
# Usage:
#   ./deployment/deploy.sh [--publish] [--backend-only] [--lambda-only] [--codebuildlense-only] [--getstatus-only] [--delete-only]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BACKEND_DIR="$ROOT_DIR/backend"
LAMBDA_SCRIPT="$SCRIPT_DIR/../gitsops_lambda/deploy.sh"
CODEBUILDLENSE_SCRIPT="$SCRIPT_DIR/../codebuildlense_lambda/deploy.sh"
GETSTATUS_SCRIPT="$SCRIPT_DIR/../getstatus_lambda/deploy.sh"
DELETE_SCRIPT="$SCRIPT_DIR/../delete_lambda/deploy.sh"

RUN_BACKEND=false
RUN_LAMBDA=false
RUN_CODEBUILDLENSE=false
RUN_GETSTATUS=false
RUN_DELETE=false
LAMBDA_ARGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--publish)
			LAMBDA_ARGS+=("--publish")
			;;
		--backend-only)
			RUN_BACKEND=true
			;;
		--lambda-only)
			RUN_LAMBDA=true
			;;
		--codebuildlense-only)
			RUN_CODEBUILDLENSE=true
			;;
		--getstatus-only)
			RUN_GETSTATUS=true
			;;
		--delete-only)
			RUN_DELETE=true
			;;
		-h|--help)
			echo "Usage: $0 [--publish] [--backend-only] [--lambda-only] [--codebuildlense-only] [--getstatus-only] [--delete-only]"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			echo "Usage: $0 [--publish] [--backend-only] [--lambda-only] [--codebuildlense-only] [--getstatus-only] [--delete-only]" >&2
			exit 2
			;;
	esac
	shift || true
done

# If no specific components specified, deploy all
if ! $RUN_BACKEND && ! $RUN_LAMBDA && ! $RUN_CODEBUILDLENSE && ! $RUN_GETSTATUS && ! $RUN_DELETE; then
	RUN_BACKEND=true
	RUN_LAMBDA=true
	RUN_CODEBUILDLENSE=true
	RUN_GETSTATUS=true
	RUN_DELETE=true
fi

# Ensure scripts exist and are executable
[[ ! -f "$LAMBDA_SCRIPT" ]] && { echo "Error: $LAMBDA_SCRIPT not found" >&2; exit 1; }
[[ ! -f "$CODEBUILDLENSE_SCRIPT" ]] && { echo "Error: $CODEBUILDLENSE_SCRIPT not found" >&2; exit 1; }
[[ ! -f "$GETSTATUS_SCRIPT" ]] && { echo "Error: $GETSTATUS_SCRIPT not found" >&2; exit 1; }
[[ ! -f "$DELETE_SCRIPT" ]] && { echo "Error: $DELETE_SCRIPT not found" >&2; exit 1; }

chmod +x "$LAMBDA_SCRIPT" "$CODEBUILDLENSE_SCRIPT" "$GETSTATUS_SCRIPT" "$DELETE_SCRIPT"

if $RUN_BACKEND; then
	echo "==> Deploying backend"
	cd "$BACKEND_DIR" && make build && make install || { echo "Backend deployment failed" >&2; exit 1; }
fi

if $RUN_LAMBDA; then
	echo "==> Deploying GitsOps Lambda"
	"$LAMBDA_SCRIPT" "${LAMBDA_ARGS[@]}" || { echo "GitsOps Lambda deployment failed" >&2; exit 1; }
fi

if $RUN_CODEBUILDLENSE; then
	echo "==> Deploying CodeBuild Lense Lambda"
	"$CODEBUILDLENSE_SCRIPT" "${LAMBDA_ARGS[@]}" || { echo "CodeBuild Lense Lambda deployment failed" >&2; exit 1; }
fi

if $RUN_GETSTATUS; then
	echo "==> Deploying GetStatus Lambda"
	"$GETSTATUS_SCRIPT" "${LAMBDA_ARGS[@]}" || { echo "GetStatus Lambda deployment failed" >&2; exit 1; }
fi

if $RUN_DELETE; then
	echo "==> Deploying Delete Lambda"
	"$DELETE_SCRIPT" "${LAMBDA_ARGS[@]}" || { echo "Delete Lambda deployment failed" >&2; exit 1; }
fi

echo "All requested deployments completed."

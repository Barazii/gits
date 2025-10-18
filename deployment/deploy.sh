#!/usr/bin/env bash

# Wrapper to run both backend and lambda deployments.
# Usage:
#   ./deployment/deploy.sh [--publish] [--backend-only | --lambda-only | --codebuildlense-only | --getstatus-only]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BACKEND_SCRIPT="$SCRIPT_DIR/deploy_backend.sh"
LAMBDA_SCRIPT="$SCRIPT_DIR/deploy_gitsops_lambda.sh"
CODEBUILDLENSE_SCRIPT="$SCRIPT_DIR/deploy_codebuildlense_lambda.sh"
GETSTATUS_SCRIPT="$SCRIPT_DIR/deploy_getstatus_lambda.sh"
DELETE_SCRIPT="$SCRIPT_DIR/deploy_delete_lambda.sh"

RUN_BACKEND=true
RUN_LAMBDA=true
RUN_CODEBUILDLENSE=true
RUN_GETSTATUS=true
RUN_DELETE=true
LAMBDA_ARGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--publish)
			LAMBDA_ARGS+=("--publish")
			;;
		--backend-only)
			RUN_BACKEND=true
			RUN_LAMBDA=false
			RUN_CODEBUILDLENSE=false
			RUN_GETSTATUS=false
			;;
		--lambda-only)
			RUN_BACKEND=false
			RUN_LAMBDA=true
			RUN_CODEBUILDLENSE=false
			RUN_GETSTATUS=false
			;;
		--codebuildlense-only)
			RUN_BACKEND=false
			RUN_LAMBDA=false
			RUN_CODEBUILDLENSE=true
			RUN_GETSTATUS=false
			;;
		--getstatus-only)
			RUN_BACKEND=false
			RUN_LAMBDA=false
			RUN_CODEBUILDLENSE=false
			RUN_GETSTATUS=true
			RUN_DELETE=false
			;;
		--delete-only)
			RUN_BACKEND=false
			RUN_LAMBDA=false
			RUN_CODEBUILDLENSE=false
			RUN_GETSTATUS=false
			RUN_DELETE=true
			;;
		-h|--help)
			echo "Usage: $0 [--publish] [--backend-only | --lambda-only | --codebuildlense-only | --getstatus-only | --delete-only]"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			echo "Usage: $0 [--publish] [--backend-only | --lambda-only | --codebuildlense-only | --getstatus-only | --delete-only]" >&2
			exit 2
			;;
	esac
	shift || true
done

# Ensure scripts exist and are executable
[[ ! -f "$BACKEND_SCRIPT" ]] && { echo "Error: $BACKEND_SCRIPT not found" >&2; exit 1; }
[[ ! -f "$LAMBDA_SCRIPT" ]] && { echo "Error: $LAMBDA_SCRIPT not found" >&2; exit 1; }
[[ ! -f "$CODEBUILDLENSE_SCRIPT" ]] && { echo "Error: $CODEBUILDLENSE_SCRIPT not found" >&2; exit 1; }
[[ ! -f "$GETSTATUS_SCRIPT" ]] && { echo "Error: $GETSTATUS_SCRIPT not found" >&2; exit 1; }
[[ ! -f "$DELETE_SCRIPT" ]] && { echo "Error: $DELETE_SCRIPT not found" >&2; exit 1; }

chmod +x "$BACKEND_SCRIPT" "$LAMBDA_SCRIPT" "$CODEBUILDLENSE_SCRIPT" "$GETSTATUS_SCRIPT" "$DELETE_SCRIPT"

if $RUN_BACKEND; then
	echo "==> Deploying backend"
	"$BACKEND_SCRIPT"
fi

if $RUN_LAMBDA; then
	echo "==> Deploying GitsOps Lambda"
	"$LAMBDA_SCRIPT" "${LAMBDA_ARGS[@]}"
fi

if $RUN_CODEBUILDLENSE; then
	echo "==> Deploying CodeBuild Lense Lambda"
	"$CODEBUILDLENSE_SCRIPT" "${LAMBDA_ARGS[@]}"
fi

if $RUN_GETSTATUS; then
	echo "==> Deploying GetStatus Lambda"
	"$GETSTATUS_SCRIPT" "${LAMBDA_ARGS[@]}"
fi

if $RUN_DELETE; then
	echo "==> Deploying Delete Lambda"
	"$DELETE_SCRIPT" "${LAMBDA_ARGS[@]}"
fi

echo "All deployments completed."

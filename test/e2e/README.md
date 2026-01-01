# E2E Tests for gits CLI

This directory contains end-to-end tests for the `gits` CLI tool.

## Test Structure

```
test/e2e/
├── conftest.py              # Pytest fixtures and utilities
├── test_local.py            # Local tests (no AWS required)
├── test_aws_integration.py  # AWS integration tests
├── cleanup.py               # Cleanup script for orphaned resources
└── requirements.txt         # Python dependencies
```

## Test Categories

### Local Tests (`test_local.py`)
These tests verify CLI argument parsing and local validation without making AWS API calls:

| Test Case | Description |
|-----------|-------------|
| 1 | `--message` without value → error (requires value) |
| 2 | `--file` without value → error |
| 3 | `--file` with comma-separated files → parsed correctly |
| 4 | No `--schedule_time` → error |
| 6 | Wrong time format → error |
| 7 | Time in the past → error |
| 8 | Run in non-git repository → error |
| 9 | Run in git repo with non-HTTP/SSH remote → error |
| 12 | `--file` with non-existing file → error |
| 14 | Duplicate `--message` → last value used |
| 15 | `--file` with duplicate files → success (deduplicated) |

### AWS Integration Tests (`test_aws_integration.py`)
These tests verify the full flow with real AWS resources:

| Test Case | Description |
|-----------|-------------|
| 10 | `--file` with deleted files → success |
| 11 | `--file` with existing files → success |
| 13 | No `--file` with staged/unstaged files → auto-detect |
| 16 | Schedule 2 posts at same time → success |
| Full Flow | Schedule → Wait → Verify CodeBuild → Verify Commit |
| Job Ordering | Verify jobs returned in correct order |

## Running Tests Locally

### Prerequisites

1. Build the `gits` CLI:
   ```bash
   cd backend
   mkdir -p build && cd build
   cmake .. && make
   ```

2. Install Python dependencies:
   ```bash
   pip install -r test/e2e/requirements.txt
   ```

3. Set up AWS credentials (for integration tests):
   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_REGION=eu-west-3
   ```

4. Set up gits config:
   ```bash
   mkdir -p ~/.gits
   cat > ~/.gits/config << EOF
   GITHUB_EMAIL=your-email@example.com
   GITHUB_USERNAME=your-github-username
   GITHUB_DISPLAY_NAME=Your Name
   EOF
   ```

### Running Local Tests Only

```bash
# Run from project root
GITS_BINARY=./backend/build/gits pytest test/e2e/test_local.py -v
```

### Running AWS Integration Tests

```bash
# Clone the test repo first
git clone https://github.com/Barazii/gitstest.git /tmp/gitstest

# Run tests
GITS_BINARY=./backend/build/gits \
TEST_REPO_PATH=/tmp/gitstest \
TEST_GITHUB_EMAIL=your-email@example.com \
pytest test/e2e/test_aws_integration.py -v
```

### Running Full Flow Test (takes ~3 minutes)

```bash
pytest test/e2e/test_aws_integration.py::TestFullFlow -v
```

### Skip Slow Tests

```bash
pytest test/e2e/ -v -m "not slow"
```

## GitHub Actions

Tests run automatically on:
- Push to `main` branch
- Pull requests to `main`
- Manual trigger via `workflow_dispatch`

### Required Secrets

Set these in your repository settings:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key for test account |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `TEST_GITHUB_EMAIL` | Email for test commits |
| `TEST_GITHUB_USERNAME` | GitHub username for test commits |
| `TEST_GITHUB_DISPLAY_NAME` | Display name for test commits |

## Cleanup

If tests fail and leave orphaned resources, run:

```bash
TEST_GITHUB_EMAIL=your-email@example.com python test/e2e/cleanup.py
```

This will:
- Delete DynamoDB entries for the test user
- Remove associated EventBridge rules
- Clean up old `gits-*` EventBridge rules (older than 1 hour)

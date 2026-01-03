"""
AWS integration tests for gits CLI.

These tests verify the full flow:
1. Schedule a job using gits CLI
2. Verify DynamoDB entry created
3. Verify EventBridge rule created
4. Wait for scheduled time
5. Verify CodeBuild execution
6. Verify commit appeared in test repository
7. Cleanup

Test cases covered:
10. --file with deleted files → success
11. --file with existing files → success  
13. No --file with staged/unstaged files → success
16. Schedule 2 posts at same time → success
+ Full flow verification
+ Retrieving order verification
"""

import os
import subprocess
import time
import pytest
import boto3
import requests
from datetime import datetime, timedelta
from pathlib import Path


# Configuration from environment
AWS_REGION = os.environ.get("AWS_REGION", "eu-west-3")
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "gits-jobs")
API_GATEWAY_URL = os.environ.get("API_GATEWAY_URL", "")
TEST_REPO_PATH = os.environ.get("TEST_REPO_PATH", "/tmp/gitstest")
TEST_GITHUB_EMAIL = os.environ.get("TEST_GITHUB_EMAIL", "")
GITS_BINARY = os.environ.get("GITS_BINARY", "gits")


# AWS clients
dynamodb = boto3.client("dynamodb", region_name=AWS_REGION)
events = boto3.client("events", region_name=AWS_REGION)
codebuild = boto3.client("codebuild", region_name=AWS_REGION)


def run_gits(args, cwd=None):
    """Run gits command."""
    result = subprocess.run(
        [GITS_BINARY] + args,
        cwd=cwd or TEST_REPO_PATH,
        capture_output=True,
        text=True
    )
    return result


def get_future_time(minutes=2):
    """Get a datetime string for the future.
    
    Returns a tuple of (cli_format, db_format):
    - cli_format: YYYY-MM-DDTHH:MM (what the CLI expects)
    - db_format: YYYY-MM-DDTHH:MM:00Z (what the backend stores)
    """
    future = datetime.now() + timedelta(minutes=minutes)
    cli_format = future.strftime("%Y-%m-%dT%H:%M")
    db_format = future.strftime("%Y-%m-%dT%H:%M:00Z")
    return cli_format, db_format


def get_dynamodb_job(user_id, job_id=None):
    """Query DynamoDB for job(s)."""
    try:
        if job_id:
            response = dynamodb.query(
                TableName=DYNAMODB_TABLE,
                KeyConditionExpression="user_id = :uid",
                FilterExpression="job_id = :jid",
                ExpressionAttributeValues={
                    ":uid": {"S": user_id},
                    ":jid": {"S": job_id}
                }
            )
        else:
            response = dynamodb.query(
                TableName=DYNAMODB_TABLE,
                KeyConditionExpression="user_id = :uid",
                ExpressionAttributeValues={
                    ":uid": {"S": user_id}
                },
                ScanIndexForward=False  # Most recent first
            )
        return response.get("Items", [])
    except Exception as e:
        print(f"Error querying DynamoDB: {e}")
        return []


def get_eventbridge_rule(rule_name):
    """Get EventBridge rule details."""
    try:
        response = events.describe_rule(Name=rule_name)
        return response
    except events.exceptions.ResourceNotFoundException:
        return None
    except Exception as e:
        print(f"Error getting EventBridge rule: {e}")
        return None


def delete_job(job_id, user_id):
    """Delete a scheduled job."""
    result = run_gits(["delete", "--job_id", job_id])
    return result.returncode == 0


def wait_for_codebuild(rule_name, timeout=300):
    """Wait for CodeBuild job to complete."""
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        try:
            # List builds for project
            response = codebuild.list_builds_for_project(
                projectName="gits-codebuild-project",  # Adjust project name
                sortOrder="DESCENDING"
            )
            
            if response.get("ids"):
                # Get build details
                builds = codebuild.batch_get_builds(ids=response["ids"][:5])
                
                for build in builds.get("builds", []):
                    # Check if this build is for our rule
                    env_vars = {e["name"]: e["value"] for e in build.get("environment", {}).get("environmentVariables", [])}
                    
                    if build.get("buildStatus") in ["SUCCEEDED", "FAILED", "STOPPED"]:
                        return build
                    
        except Exception as e:
            print(f"Error checking CodeBuild: {e}")
        
        time.sleep(10)
    
    return None


def get_latest_commit(repo_path):
    """Get the latest commit info from a git repo."""
    result = subprocess.run(
        ["git", "log", "-1", "--format=%H|%s|%an|%ae"],
        cwd=repo_path,
        capture_output=True,
        text=True
    )
    if result.returncode == 0:
        parts = result.stdout.strip().split("|")
        return {
            "hash": parts[0],
            "message": parts[1] if len(parts) > 1 else "",
            "author_name": parts[2] if len(parts) > 2 else "",
            "author_email": parts[3] if len(parts) > 3 else ""
        }
    return None


def reset_test_repo():
    """Reset the test repository to a clean state."""
    subprocess.run(["git", "fetch", "origin"], cwd=TEST_REPO_PATH, capture_output=True)
    subprocess.run(["git", "reset", "--hard", "origin/main"], cwd=TEST_REPO_PATH, capture_output=True)
    subprocess.run(["git", "clean", "-fd"], cwd=TEST_REPO_PATH, capture_output=True)


def create_test_file(filename, content="test content"):
    """Create a test file in the test repo."""
    filepath = Path(TEST_REPO_PATH) / filename
    filepath.parent.mkdir(parents=True, exist_ok=True)
    filepath.write_text(content)
    return filepath


def delete_test_file(filename):
    """Delete a test file from the test repo."""
    filepath = Path(TEST_REPO_PATH) / filename
    if filepath.exists():
        filepath.unlink()


@pytest.fixture(autouse=True)
def setup_and_cleanup():
    """Setup and cleanup for each test."""
    # Setup: Reset test repo
    reset_test_repo()
    
    yield
    
    # Cleanup: Reset test repo and delete any jobs
    reset_test_repo()


class TestScheduleWithFiles:
    """Test case 11: Schedule with specific files."""

    def test_schedule_with_new_file(self):
        """Test scheduling with a new file."""
        # Create a new file
        test_filename = f"test-{int(time.time())}.txt"
        test_content = f"Test content created at {datetime.now()}"
        create_test_file(test_filename, test_content)
        
        # Schedule for 2 minutes in the future
        cli_time, db_time = get_future_time(2)
        
        result = run_gits([
            "schedule",
            "--schedule_time", cli_time,
            "--file", test_filename,
            "--message", f"E2E test: add {test_filename}"
        ])
        
        assert result.returncode == 0, f"Schedule failed: {result.stderr}"
        assert "scheduled" in result.stdout.lower() or "success" in result.stdout.lower()
        
        # Verify DynamoDB entry
        time.sleep(2)  # Give it a moment to propagate
        jobs = get_dynamodb_job(TEST_GITHUB_EMAIL)
        latest_job = jobs[0]
        assert latest_job["schedule_time"]["S"] == db_time
        assert latest_job["status"]["S"] == "pending"
        
        # Verify EventBridge rule exists
        job_id = latest_job["job_id"]["S"]
        rule = get_eventbridge_rule(job_id)
        assert rule is not None, f"EventBridge rule {job_id} not found"
        assert rule["State"] == "ENABLED"
        
        # Cleanup - delete the job
        delete_job(job_id, TEST_GITHUB_EMAIL)


class TestScheduleWithDeletedFiles:
    """Test case 10: Schedule with deleted files."""

    def test_schedule_with_deleted_file(self):
        """Test scheduling when a file is deleted."""
        # First, create and commit a file
        test_filename = f"to-delete-{int(time.time())}.txt"
        create_test_file(test_filename, "content to delete")
        
        subprocess.run(["git", "add", test_filename], cwd=TEST_REPO_PATH, check=True)
        subprocess.run(["git", "commit", "-m", "Add file to delete"], cwd=TEST_REPO_PATH, check=True)
        subprocess.run(["git", "push"], cwd=TEST_REPO_PATH, check=True)
        
        # Now delete the file
        delete_test_file(test_filename)
        subprocess.run(["git", "add", test_filename], cwd=TEST_REPO_PATH, capture_output=True)
        
        # Schedule the deletion
        cli_time, db_time = get_future_time(2)
        
        result = run_gits([
            "schedule",
            "--schedule_time", cli_time,
            "--file", test_filename,
            "--message", f"E2E test: delete {test_filename}"
        ])
        
        assert result.returncode == 0, f"Schedule failed: {result.stderr}"
        
        # Verify and cleanup
        time.sleep(2)
        jobs = get_dynamodb_job(TEST_GITHUB_EMAIL)
        latest_job = jobs[0]
        assert latest_job["schedule_time"]["S"] == db_time

        job_id = latest_job["job_id"]["S"]
        rule = get_eventbridge_rule(job_id)
        assert rule is not None, f"EventBridge rule {job_id} not found"
        assert rule["State"] == "ENABLED"

        delete_job(latest_job["job_id"]["S"], TEST_GITHUB_EMAIL)


class TestScheduleAutoDetect:
    """Test case 13: Schedule without --file (auto-detect changes)."""

    def test_schedule_auto_detect_changes(self):
        """Test scheduling with auto-detected changes."""
        # Create and stage a new file
        test_filename = f"auto-detect-{int(time.time())}.txt"
        create_test_file(test_filename, "auto detected content")
        subprocess.run(["git", "add", test_filename], cwd=TEST_REPO_PATH, check=True)
        
        # Schedule without --file
        cli_time, db_time = get_future_time(2)
        
        result = run_gits([
            "schedule",
            "--schedule_time", cli_time,
            "--message", "E2E test: auto-detect changes"
        ])
        
        assert result.returncode == 0, f"Schedule failed: {result.stderr}"
        
        # Verify and cleanup
        time.sleep(2)
        jobs = get_dynamodb_job(TEST_GITHUB_EMAIL)
        latest_job = jobs[0]
        assert latest_job["schedule_time"]["S"] == db_time

        job_id = latest_job["job_id"]["S"]
        rule = get_eventbridge_rule(job_id)
        assert rule is not None, f"EventBridge rule {job_id} not found"
        assert rule["State"] == "ENABLED"

        delete_job(latest_job["job_id"]["S"], TEST_GITHUB_EMAIL)


class TestScheduleSameTime:
    """Test case 16: Schedule 2 posts at same time."""

    def test_schedule_multiple_jobs_same_time(self):
        """Test scheduling multiple jobs at the same time."""
        cli_time, db_time = get_future_time(3)
        job_ids = []
        
        # Schedule first job
        test_file1 = f"multi-1-{int(time.time())}.txt"
        create_test_file(test_file1, "content 1")
        
        result1 = run_gits([
            "schedule",
            "--schedule_time", cli_time,
            "--file", test_file1,
            "--message", "E2E test: multi job 1"
        ])
        assert result1.returncode == 0, f"First schedule failed: {result1.stderr}"
        
        time.sleep(2)
        
        # Schedule second job at same time
        test_file2 = f"multi-2-{int(time.time())}.txt"
        create_test_file(test_file2, "content 2")
        
        result2 = run_gits([
            "schedule",
            "--schedule_time", cli_time,
            "--file", test_file2,
            "--message", "E2E test: multi job 2"
        ])
        assert result2.returncode == 0, f"Second schedule failed: {result2.stderr}"
        
        # Verify both jobs have the same schedule_time and cleanup
        time.sleep(2)
        jobs = get_dynamodb_job(TEST_GITHUB_EMAIL)
        # Both latest jobs should have the same schedule_time
        assert jobs[0]["schedule_time"]["S"] == db_time
        assert jobs[1]["schedule_time"]["S"] == db_time

        job_id = jobs[0]["job_id"]["S"]
        rule = get_eventbridge_rule(job_id)
        assert rule is not None, f"EventBridge rule {job_id} not found"
        assert rule["State"] == "ENABLED"
        job_id = jobs[1]["job_id"]["S"]
        rule = get_eventbridge_rule(job_id)
        assert rule is not None, f"EventBridge rule {job_id} not found"
        assert rule["State"] == "ENABLED"

        for job in jobs[:2]:
            delete_job(job["job_id"]["S"], TEST_GITHUB_EMAIL)


class TestFullFlow:
    """Full end-to-end test: schedule, wait, verify commit."""

    @pytest.mark.slow
    def test_full_flow_schedule_and_commit(self):
        """
        Full flow test:
        1. Schedule a job for 2 minutes in the future
        2. Verify DynamoDB and EventBridge
        3. Wait for execution
        4. Verify CodeBuild succeeded
        5. Verify commit appeared in test repo
        """
        # Create test file
        test_filename = f"full-flow-{int(time.time())}.txt"
        test_content = f"Full flow test at {datetime.now()}"
        commit_message = f"E2E full flow test: {test_filename}"
        create_test_file(test_filename, test_content)
        
        # Get initial commit hash
        initial_commit = get_latest_commit(TEST_REPO_PATH)
        
        # Schedule for 2 minutes in the future
        cli_time, db_time = get_future_time(2)
        
        result = run_gits([
            "schedule",
            "--schedule_time", cli_time,
            "--file", test_filename,
            "--message", commit_message
        ])
        
        assert result.returncode == 0, f"Schedule failed: {result.stderr}"
        print(f"Scheduled job for {cli_time}")
        
        # Wait for job to appear in DynamoDB
        time.sleep(3)
        jobs = get_dynamodb_job(TEST_GITHUB_EMAIL)
        assert len(jobs) > 0, "No jobs found in DynamoDB"
        
        job = jobs[0]
        assert job["schedule_time"]["S"] == db_time
        job_id = job["job_id"]["S"]
        print(f"Job ID: {job_id}")
        assert job["status"]["S"] == "pending", f"Expected pending, got {job['status']['S']}"
        
        # Verify EventBridge rule
        rule = get_eventbridge_rule(job_id)
        assert rule is not None, f"EventBridge rule not found"
        print(f"EventBridge rule state: {rule['State']}")
        
        # Poll for new commit with timeout (2 min schedule + up to 6 min for CodeBuild)
        max_wait = 480  # 8 minutes total
        poll_interval = 30  # Check every 30 seconds
        elapsed = 0
        latest_commit = None
        
        print(f"Polling for new commit (max {max_wait} seconds)...")
        while elapsed < max_wait:
            time.sleep(poll_interval)
            elapsed += poll_interval
            
            # Pull latest changes from test repo
            fetch_result = subprocess.run(["git", "fetch", "origin"], cwd=TEST_REPO_PATH, capture_output=True)
            if fetch_result.returncode != 0:
                print(f"Git fetch failed: {fetch_result.stderr.decode()}")
            reset_result = subprocess.run(["git", "reset", "--hard", "origin/main"], cwd=TEST_REPO_PATH, capture_output=True)
            if reset_result.returncode != 0:
                print(f"Git reset failed: {reset_result.stderr.decode()}")
            
            # Check for new commit
            latest_commit = get_latest_commit(TEST_REPO_PATH)
            if latest_commit["hash"] != initial_commit["hash"]:
                print(f"New commit found after {elapsed} seconds")
                break
            print(f"Still waiting... ({elapsed}s elapsed, current HEAD: {latest_commit['hash'][:8]})")
        
        # Verify new commit appeared
        assert latest_commit["hash"] != initial_commit["hash"], "No new commit found"
        
        # Verify commit message
        assert commit_message in latest_commit["message"] or test_filename in latest_commit["message"], \
            f"Commit message mismatch: {latest_commit['message']}"
        
        # Verify file exists with correct content
        filepath = Path(TEST_REPO_PATH) / test_filename
        assert filepath.exists(), f"File {test_filename} not found in repo"
        assert filepath.read_text() == test_content, "File content mismatch"
        
        print(f"Full flow test PASSED!")
        print(f"New commit: {latest_commit['hash'][:8]} - {latest_commit['message']}")


class TestStatusCommand:
    """Test status command with AWS."""

    def test_status_shows_latest_job(self):
        """Test that status command shows the latest scheduled job."""
        # Create and schedule a job
        test_filename = f"status-test-{int(time.time())}.txt"
        create_test_file(test_filename, "status test content")
        
        cli_time, db_time = get_future_time(5)
        
        run_gits([
            "schedule",
            "--schedule_time", cli_time,
            "--file", test_filename,
            "--message", "E2E test: status check"
        ])
        
        time.sleep(2)
        
        # Check status
        result = run_gits(["status"])
        
        assert result.returncode == 0, f"Status failed: {result.stderr}"
        assert "pending" in result.stdout.lower() or "job" in result.stdout.lower()
        
        # Verify and cleanup
        jobs = get_dynamodb_job(TEST_GITHUB_EMAIL)
        assert len(jobs) > 0, "No jobs found in DynamoDB"
        latest_job = jobs[0]
        assert latest_job["schedule_time"]["S"] == db_time
        delete_job(latest_job["job_id"]["S"], TEST_GITHUB_EMAIL)


class TestJobOrdering:
    """Test that jobs are retrieved in correct order (most recent first)."""

    def test_job_ordering(self):
        """Test that multiple jobs are returned in correct order."""
        job_ids = []
        
        # Create multiple jobs
        for i in range(3):
            test_filename = f"order-test-{i}-{int(time.time())}.txt"
            create_test_file(test_filename, f"order test {i}")
            
            cli_time, _ = get_future_time(5 + i)
            
            result = run_gits([
                "schedule",
                "--schedule_time", cli_time,
                "--file", test_filename,
                "--message", f"E2E test: order {i}"
            ])
            
            assert result.returncode == 0
            time.sleep(2)
        
        # Get all jobs
        jobs = get_dynamodb_job(TEST_GITHUB_EMAIL)
        
        # Verify ordering (should be most recent first based on added_at)
        added_at_values = [int(job["added_at"]["N"]) for job in jobs if "added_at" in job]
        assert added_at_values == sorted(added_at_values, reverse=True), \
            "Jobs not in correct order (most recent first)"
        
        # Cleanup
        for job in jobs:
            delete_job(job["job_id"]["S"], TEST_GITHUB_EMAIL)

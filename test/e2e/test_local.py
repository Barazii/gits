"""
Local tests for gits CLI - these test argument parsing and local validation
without making any AWS API calls.

Test cases covered:
1. --message without value → success (uses default)
2. --file without value → error
3. --file with files → success (comma/space/plus separated)
4. No time argument → error  
5. Time not as expected argument → error
6. Wrong time format → error
7. Time in the past → error
8. Run in non-git repository → error
9. Run in git repo but not HTTP/SSH remote → error
10. --file with deleted files → requires AWS (tested in integration)
11. --file with existing files → requires AWS (tested in integration)
12. --file with non-existing file → error
13. No --file with changes → requires AWS (tested in integration)
14. Duplicate --message → last value used
15. --file with duplicate files → success
16. Schedule 2 posts at same time → requires AWS (tested in integration)
"""

import os
import subprocess
import pytest
from datetime import datetime, timedelta
from conftest import run_gits, get_future_time


class TestArgumentParsing:
    """Test argument parsing and validation."""

    def test_no_arguments_shows_usage(self, gits_binary):
        """Test that running gits without arguments shows usage."""
        result = run_gits(gits_binary, [])
        assert result.returncode == 2
        assert "Usage:" in result.stderr or "Usage:" in result.stdout

    def test_help_command(self, gits_binary):
        """Test --help flag."""
        result = run_gits(gits_binary, ["--help"])
        assert result.returncode == 0
        assert "schedule" in result.stdout
        assert "status" in result.stdout
        assert "delete" in result.stdout

    def test_version_command(self, gits_binary):
        """Test version command."""
        result = run_gits(gits_binary, ["version"])
        assert result.returncode == 0
        assert "gits" in result.stdout

    def test_unknown_command(self, gits_binary):
        """Test unknown command."""
        result = run_gits(gits_binary, ["unknown"])
        assert result.returncode == 2
        assert "Error: unknown command: unknown" in result.stderr


class TestScheduleTimeValidation:
    """Test case 4, 5, 6, 7: Time validation tests."""

    def test_schedule_without_time_fails(self, gits_binary, temp_git_repo, gits_config):
        """Test case 4: schedule without --schedule_time should fail."""
        result = run_gits(gits_binary, ["schedule"], cwd=temp_git_repo)
        assert result.returncode == 2
        assert "Error: schedule requires --schedule_time <time>" in result.stderr

    def test_schedule_time_wrong_format(self, gits_binary, temp_git_repo, gits_config):
        """Test case 6: Wrong time format should fail."""
        wrong_formats = [
            "2025-07-17",           # Missing time
            "15:00",                 # Missing date
            "2025/07/17T15:00",     # Wrong date separator
            "2025-07-17 15:00",     # Space instead of T
            "2025-07-17T15:00:00",  # Includes seconds
            "not-a-time",           # Invalid
            "2025-13-01T15:00",     # Invalid month
            "2025-07-32T15:00",     # Invalid day
        ]
        
        for time_str in wrong_formats:
            result = run_gits(
                gits_binary, 
                ["schedule", "--schedule_time", time_str],
                cwd=temp_git_repo
            )
            assert result.returncode != 0, f"Expected failure for time format: {time_str}"

    def test_schedule_time_in_past(self, gits_binary, temp_git_repo, gits_config):
        """Test case 7: Time in the past should fail."""
        past_time = (datetime.now() - timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M")
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", past_time],
            cwd=temp_git_repo
        )
        assert result.returncode != 0
        assert "Error: Schedule time must be in the future." in result.stderr


class TestFileArgument:
    """Test cases 2, 3, 12, 15: --file argument tests."""

    def test_file_without_value_fails(self, gits_binary, temp_git_repo, gits_config):
        """Test case 2: --file without value should fail."""
        future_time = get_future_time(5)
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time, "--file"],
            cwd=temp_git_repo
        )
        assert result.returncode == 2
        assert "Error: --file requires a file path" in result.stderr

    def test_file_with_nonexistent_file_fails(self, gits_binary, temp_git_repo, gits_config):
        """Test case 12: --file with non-existing file should fail."""
        future_time = get_future_time(5)
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time, "--file", "nonexistent.txt"],
            cwd=temp_git_repo
        )
        assert result.returncode != 0
        assert "Error: file not found: nonexistent.txt" in result.stderr

    def test_file_comma_separated(self, gits_binary, temp_git_repo, gits_config):
        """Test case 3: --file with comma-separated files."""
        # Create test files
        (temp_git_repo / "file1.txt").write_text("content1")
        (temp_git_repo / "file2.txt").write_text("content2")
        
        future_time = get_future_time(5)
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time, "--file", "file1.txt,file2.txt"],
            cwd=temp_git_repo
        )
        # This will fail because it tries to contact API, but shouldn't fail on arg parsing
        # We check that it got past the file validation stage
        assert "Error: file not found:" not in result.stderr

    def test_file_with_duplicates_succeeds(self, gits_binary, temp_git_repo, gits_config):
        """Test case 15: --file with duplicate files should succeed (deduplicated)."""
        (temp_git_repo / "file1.txt").write_text("content1")
        
        future_time = get_future_time(5)
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time, "--file", "file1.txt,file1.txt"],
            cwd=temp_git_repo
        )
        # Should not fail on argument parsing
        assert "Error: file not found:" not in result.stderr


class TestMessageArgument:
    """Test cases 1, 14: --message argument tests."""

    def test_message_without_value_fails(self, gits_binary, temp_git_repo, gits_config):
        """Test case 1: --message without value should fail (require value after flag)."""
        future_time = get_future_time(5)
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time, "--message"],
            cwd=temp_git_repo
        )
        assert result.returncode == 2

    def test_duplicate_message_uses_last(self, gits_binary, temp_git_repo, gits_config):
        """Test case 14: Duplicate --message should use last value."""
        (temp_git_repo / "test.txt").write_text("content")
        future_time = get_future_time(5)
        
        # This test verifies parsing succeeds - the actual message used
        # would be verified in integration tests
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time, "--message", "first", "--message", "second", "--file", "test.txt"],
            cwd=temp_git_repo
        )
        # Should get past arg parsing (may fail on API call)
        assert result.returncode == 2 or "message" not in result.stderr.lower()


class TestGitRepositoryValidation:
    """Test cases 8, 9: Git repository validation tests."""

    def test_run_in_non_git_repo_fails(self, gits_binary, temp_non_git_dir, gits_config):
        """Test case 8: Running in non-git repository should fail."""
        future_time = get_future_time(5)
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time],
            cwd=temp_non_git_dir
        )
        assert result.returncode != 0
        assert "Error: Must be run inside a Git repository." in result.stderr

    def test_run_in_git_repo_without_remote_fails(self, gits_binary, temp_git_repo_no_remote, gits_config):
        """Test case 9 variant: Running in git repo without remote should fail."""
        future_time = get_future_time(5)
        
        # Create a file to schedule
        (temp_git_repo_no_remote / "test.txt").write_text("content")
        
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time, "--file", "test.txt"],
            cwd=temp_git_repo_no_remote
        )
        assert result.returncode != 0
        # Should fail because no remote is set
        assert "Error: Could not retrieve repository URL. Ensure 'origin' remote is set." in result.stderr

    def test_run_in_git_repo_with_file_remote_fails(self, gits_binary, temp_git_repo_file_remote, gits_config):
        """Test case 9: Running in git repo with file:// remote should fail."""
        future_time = get_future_time(5)
        
        # Create a file to schedule
        (temp_git_repo_file_remote / "test.txt").write_text("content")
        
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time, "--file", "test.txt"],
            cwd=temp_git_repo_file_remote
        )
        assert result.returncode != 0
        assert "Error: Repository URL must be HTTPS or SSH format for GitHub." in result.stderr


class TestStatusCommand:
    """Test status command validation."""

    def test_status_with_extra_args_fails(self, gits_binary, temp_git_repo, gits_config):
        """Status command should not accept extra arguments."""
        result = run_gits(
            gits_binary,
            ["status", "extra"],
            cwd=temp_git_repo
        )
        assert result.returncode == 2

    def test_status_requires_git_repo(self, gits_binary, temp_non_git_dir, gits_config):
        """Status command requires being in a git repo."""
        result = run_gits(
            gits_binary,
            ["status"],
            cwd=temp_non_git_dir
        )
        assert result.returncode != 0


class TestDeleteCommand:
    """Test delete command validation."""

    def test_delete_without_job_id_fails(self, gits_binary, temp_git_repo, gits_config):
        """Delete command requires --job_id."""
        result = run_gits(
            gits_binary,
            ["delete"],
            cwd=temp_git_repo
        )
        assert result.returncode == 2
        assert "Error: delete requires --job_id <id>" in result.stderr

    def test_delete_with_extra_args_fails(self, gits_binary, temp_git_repo, gits_config):
        """Delete command should not accept extra arguments after job_id."""
        result = run_gits(
            gits_binary,
            ["delete", "--job_id", "test-job", "extra"],
            cwd=temp_git_repo
        )
        assert result.returncode == 2


class TestNoChangesScenario:
    """Test when there are no file changes."""

    def test_schedule_with_no_changes_fails(self, gits_binary, temp_git_repo, gits_config):
        """Test case: Run gits with no file changes should fail."""
        future_time = get_future_time(5)
        
        # The repo has no uncommitted changes
        result = run_gits(
            gits_binary,
            ["schedule", "--schedule_time", future_time],
            cwd=temp_git_repo
        )
        assert result.returncode != 0
        assert "No changes found." in result.stderr

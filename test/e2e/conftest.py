"""
Pytest configuration and shared fixtures for E2E tests.
"""

import os
import pytest
import subprocess
import tempfile
import shutil
from pathlib import Path


@pytest.fixture(scope="session")
def gits_binary():
    """Get the path to the gits binary."""
    binary = os.environ.get("GITS_BINARY", "gits")
    if not os.path.isabs(binary):
        # Try to find it in PATH or common locations
        result = shutil.which(binary)
        if result:
            binary = result
    
    if not os.path.exists(binary):
        pytest.skip(f"gits binary not found at {binary}")
    
    return binary


@pytest.fixture
def temp_git_repo(tmp_path):
    """Create a temporary git repository for testing."""
    repo_path = tmp_path / "test-repo"
    repo_path.mkdir()
    
    # Initialize git repo
    subprocess.run(["git", "init"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo_path, check=True, capture_output=True)
    
    # Create initial commit
    (repo_path / "README.md").write_text("# Test Repo\n")
    subprocess.run(["git", "add", "README.md"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=repo_path, check=True, capture_output=True)
    
    # Add a remote (fake HTTPS URL for validation)
    subprocess.run(
        ["git", "remote", "add", "origin", "https://github.com/test/test-repo.git"],
        cwd=repo_path,
        check=True,
        capture_output=True
    )
    
    yield repo_path
    
    # Cleanup is handled by tmp_path fixture


@pytest.fixture
def temp_non_git_dir(tmp_path):
    """Create a temporary directory that is NOT a git repository."""
    non_git_path = tmp_path / "non-git-dir"
    non_git_path.mkdir()
    return non_git_path


@pytest.fixture
def temp_git_repo_no_remote(tmp_path):
    """Create a temporary git repository without a remote."""
    repo_path = tmp_path / "test-repo-no-remote"
    repo_path.mkdir()
    
    subprocess.run(["git", "init"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo_path, check=True, capture_output=True)
    
    (repo_path / "README.md").write_text("# Test Repo\n")
    subprocess.run(["git", "add", "README.md"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=repo_path, check=True, capture_output=True)
    
    yield repo_path


@pytest.fixture
def temp_git_repo_file_remote(tmp_path):
    """Create a git repository with a file:// remote (not HTTP/SSH)."""
    repo_path = tmp_path / "test-repo-file-remote"
    repo_path.mkdir()
    
    subprocess.run(["git", "init"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@test.com"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo_path, check=True, capture_output=True)
    
    (repo_path / "README.md").write_text("# Test Repo\n")
    subprocess.run(["git", "add", "README.md"], cwd=repo_path, check=True, capture_output=True)
    subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=repo_path, check=True, capture_output=True)
    
    # Add a file:// remote (not valid for gits)
    subprocess.run(
        ["git", "remote", "add", "origin", f"file://{tmp_path}/some-repo.git"],
        cwd=repo_path,
        check=True,
        capture_output=True
    )
    
    yield repo_path


@pytest.fixture
def gits_config(tmp_path):
    """Create a temporary gits config."""
    config_dir = tmp_path / ".gits"
    config_dir.mkdir()
    config_file = config_dir / "config"
    
    config_content = """GITHUB_EMAIL=test@example.com
GITHUB_USERNAME=testuser
GITHUB_DISPLAY_NAME=Test User
"""
    config_file.write_text(config_content)
    
    # Set HOME to tmp_path so gits finds the config
    old_home = os.environ.get("HOME")
    os.environ["HOME"] = str(tmp_path)
    
    yield config_file
    
    # Restore HOME
    if old_home:
        os.environ["HOME"] = old_home


def run_gits(binary, args, cwd=None, env=None):
    """Run gits command and return result."""
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    
    result = subprocess.run(
        [binary] + args,
        cwd=cwd,
        capture_output=True,
        text=True,
        env=full_env
    )
    
    return result


def get_future_time(minutes=2):
    """Get a datetime string for the future."""
    from datetime import datetime, timedelta
    future = datetime.now() + timedelta(minutes=minutes)
    return future.strftime("%Y-%m-%dT%H:%M")

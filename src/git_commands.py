import subprocess


def git_push():
    subprocess.run(["git", "push"])


def git_commit(message):
    subprocess.run(["git", "commit", "-m", message])

import subprocess
import logging


logger = logging.getLogger("gits")


def git_push(force_push):
    # pull before push
    try:
        ret = subprocess.run(["git", "pull"], check=True)
    except subprocess.CalledProcessError:
        logger.error("Merge conflict in git pull")
        raise ValueError(f"Merge conflict in git pull {ret.stdout}")
    # push
    if not force_push:
        logger.info("Executing git push")
        subprocess.run(["git", "push"])
    else:
        logger.info("Executing git push --force")
        subprocess.run(["git", "push", "--force"])


def git_commit(message):
    subprocess.run(["git", "commit", "-m", message])


def git_add(pathspec):
    subprocess.run(["git", "add", *pathspec])

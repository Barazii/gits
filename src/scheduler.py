from threading import Timer
from datetime import datetime
from src.git_commands import *
import logging


logger = logging.getLogger("gits")


def schedule_push(force_push, timestamp, task_complete):
    dt = datetime.strptime(timestamp, f"%m-%d-%H:%M")
    dt = dt.replace(year=datetime.now().year)
    delay = (dt - datetime.now()).total_seconds()
    if delay > 0:
        timer = Timer(delay, execute_push, args=[force_push, task_complete])
        timer.start()
        logger.info(f"A push scheduled for {dt}")
    else:
        logger.error("Cannot schedule a push for the past")
        raise ValueError("Cannot schedule a push for the past")


def schedule_commit(message, timestamp, task_complete):
    dt = datetime.strptime(timestamp, f"%m-%d-%H:%M")
    dt = dt.replace(year=datetime.now().year)
    delay = (dt - datetime.now()).total_seconds()
    if delay > 0:
        timer = Timer(delay, execute_commit, args=[message, task_complete])
        timer.start()
        logger.info(f"A commit scheduled for {dt}")
    else:
        logger.error("Cannot schedule a commit for the past")
        raise ValueError("Cannot schedule a commit for the past")


def execute_push(force_push, task_complete):
    git_push(force_push)
    task_complete.set()


def execute_commit(message, task_complete):
    logger.info(f'Executing git commit -m "{message}"')
    git_commit(message=message)
    task_complete.set()

from threading import Timer
from datetime import datetime
from src.git_commands import *
import logging


logger = logging.getLogger("gits")


def schedule_push(timestamp, task_complete):
    dt = datetime.strptime(timestamp, "%m-%d-%Y-%H:%M")
    delay = (dt - datetime.now().replace(microsecond=0)).total_seconds()
    if delay > 0:
        timer = Timer(delay, execute_push, args=[task_complete])
        timer.start()
    else:
        logger.error("Cannot schedule a push for the past")
        raise ValueError("Cannot schedule a push for the past")
    return dt


def schedule_commit(message, timestamp, task_complete):
    dt = datetime.strptime(timestamp, "%m-%d-%Y-%H:%M")
    delay = (dt - datetime.now().replace(microsecond=0)).total_seconds()
    if delay > 0:
        timer = Timer(delay, execute_commit, args=[message, task_complete])
        timer.start()
    else:
        logger.error("Cannot schedule a commit for the past")
        raise ValueError("Cannot schedule a commit for the past")
    return dt


def execute_push(task_complete):
    logger.info("Executing git push")
    git_push()
    task_complete.set()


def execute_commit(message, task_complete):
    logger.info(f'Executing git commit -m "{message}"')
    git_commit(message=message)
    task_complete.set()

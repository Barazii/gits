from src.scheduler import schedule_push, schedule_commit
import logging


logger = logging.getLogger("gits")


def schedule_push_cmd(timestamp, task_complete):
    dt = schedule_push(timestamp, task_complete)
    logger.info(f"A push scheduled for {dt}")


def schedule_commit_cmd(message, timestamp, task_complete):
    dt = schedule_commit(message, timestamp, task_complete)
    logger.info(f"A commit scheduled for {dt}")

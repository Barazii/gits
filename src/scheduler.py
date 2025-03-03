from datetime import datetime
from src.git_commands import *
import logging
import time
import os
import sys


logger = logging.getLogger("gits")


def schedule_cmd(args):
    dt = datetime.strptime(args.timestamp, f"%m-%d-%H:%M")
    dt = dt.replace(year=datetime.now().year)
    delay = (dt - datetime.now()).total_seconds()
    if delay > 0:
        pid = os.fork()
        if pid == 0:  # Child process
            os.setsid()
            time.sleep(delay)
            if args.command == "add":
                git_add(args.pathspec)
            elif args.command == "commit":
                git_commit(args.message)
            elif args.command == "push":
                git_push(args.force)
            sys.exit(0)
        else:  # Parent process
            logger.info(f"An add scheduled for {dt}")
            sys.exit(0)
    else:
        logger.error("Cannot schedule an add for the past")
        raise ValueError("Cannot schedule an add for the past")

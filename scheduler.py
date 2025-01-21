import schedule
import time
from datetime import datetime
from git_commands import *


def schedule_push(timestamp):
    dt = datetime.strptime(timestamp, "%m-%d-%Y-%H:%M")
    schedule.every().day.at(dt.strftime("%H:%M")).do(execute_push)
    return dt

def schedule_commit(message, timestamp):
    dt = datetime.strptime(timestamp, "%m-%d-%Y-%H:%M")
    schedule.every().day.at(dt.strftime("%H:%M")).do(execute_commit, message)
    return dt

def execute_push():
    print("Executing git push")
    # TODO: Implement actual git push
    # git_push()


def execute_commit(message):
    print(f'Executing git commit -m "{message}"')
    # TODO: Implement actual git commit
    # git_commit(message=message)


def run_scheduler():
    while True:
        schedule.run_pending()
        time.sleep(1)

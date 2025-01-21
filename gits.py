import argparse
from commands import (
    schedule_push_cmd,
    schedule_commit_cmd,
    list_tasks_cmd,
    cancel_task_cmd,
)
from scheduler import run_scheduler
from threading import Thread


def gits():
    parser = argparse.ArgumentParser(description="Git Push Scheduler")

    subparsers = parser.add_subparsers(dest="command")

    push_parser = subparsers.add_parser("push", help="Schedule a git push")
    push_parser.add_argument(
        "-ts", "--timestamp", help="When to execute the push (format: MM-DD-YYYY-HH:mm)"
    )

    commit_parser = subparsers.add_parser("commit", help="Schedule a git commit")
    commit_parser.add_argument("-m", "--message", required=True, help="Commit message")
    commit_parser.add_argument(
        "-ts",
        "--timestamp",
        help="When to execute the commit (format: MM-DD-YYYY-HH:mm)",
    )

    status_parser = subparsers.add_parser("status", help="List scheduled tasks")

    cancel_parser = subparsers.add_parser("cancel", help="Cancel a scheduled task")
    cancel_parser.add_argument("task_id", type=int, help="ID of the task to cancel")

    args = parser.parse_args()

    if args.command == "push":
        schedule_push_cmd(args.timestamp)
    elif args.command == "commit":
        schedule_commit_cmd(args.message, args.timestamp)
    elif args.command == "status":
        list_tasks_cmd()
    elif args.command == "cancel":
        cancel_task_cmd(args.task_id)
    else:
        parser.print_help()


if __name__ == "__main__":
    scheduler_thread = Thread(target=run_scheduler)
    scheduler_thread.start()

    gits()

import argparse
import argcomplete
from src.commands import (
    schedule_push_cmd,
    schedule_commit_cmd,
)
from threading import Event


task_complete = Event()


def gits():
    parser = argparse.ArgumentParser(description="Git Push Scheduler")

    subparsers = parser.add_subparsers(dest="command")

    push_parser = subparsers.add_parser("push", help="Schedule a git push")
    push_parser.add_argument(
        "-ts",
        "--timestamp",
        required=True,
        help="When to execute the push (format: MM-DD-YYYY-HH:mm)",
    )

    commit_parser = subparsers.add_parser("commit", help="Schedule a git commit")
    commit_parser.add_argument("-m", "--message", required=True, help="Commit message")
    commit_parser.add_argument(
        "-ts",
        "--timestamp",
        required=True,
        help="When to execute the commit (format: MM-DD-YYYY-HH:mm)",
    )

    argcomplete.autocomplete(parser)
    args = parser.parse_args()

    if args.command == "push":
        schedule_push_cmd(args.timestamp, task_complete)
    elif args.command == "commit":
        schedule_commit_cmd(args.message, args.timestamp, task_complete)
    else:
        parser.print_help()

    task_complete.wait()  # Wait for the scheduled task to complete


if __name__ == "__main__":
    gits()

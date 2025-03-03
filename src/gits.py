import argparse
import argcomplete
from src.scheduler import schedule_cmd
import logging


logging.basicConfig(level=logging.INFO, format="%(name)s:%(levelname)s: %(message)s")


def gits():
    parser = argparse.ArgumentParser(description="Git Push Scheduler")

    subparsers = parser.add_subparsers(dest="command")

    add_parser = subparsers.add_parser("add", help="Schedule a git add")
    add_parser.add_argument(
        "-ps",
        "--pathspec",
        required=True,
        nargs="+",
        help="File contents to add to index",
    )
    add_parser.add_argument(
        "-ts",
        "--timestamp",
        required=True,
        help="When to execute the add (format: MM-DD-HH:mm)",
    )

    push_parser = subparsers.add_parser("push", help="Schedule a git push")
    push_parser.add_argument(
        "-f",
        "--force",
        required=False,
        type=bool,
        default=False,
        help="Force push option",
    )
    push_parser.add_argument(
        "-ts",
        "--timestamp",
        required=True,
        help="When to execute the push (format: MM-DD-HH:mm)",
    )

    commit_parser = subparsers.add_parser("commit", help="Schedule a git commit")
    commit_parser.add_argument("-m", "--message", required=True, help="Commit message")
    commit_parser.add_argument(
        "-ts",
        "--timestamp",
        required=True,
        help="When to execute the commit (format: MM-DD-HH:mm)",
    )

    argcomplete.autocomplete(parser)
    args = parser.parse_args()

    schedule_cmd(args)


if __name__ == "__main__":
    gits()

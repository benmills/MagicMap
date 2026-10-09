"""Progress and notes from the generators, on stderr (stdout may be the output)."""
import sys


def log(msg: str) -> None:
    print(msg, file=sys.stderr)

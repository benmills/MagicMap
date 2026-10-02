#!/usr/bin/env python3
"""Dump a WDC5 .db2 as TSV: one line per record, `id <tab> field0 <tab> ...`.
Array fields are joined with ','. Fields listed in --strings print as
s:<text> when their value is a string offset.

  python3 tools/db2dump.py map.db2 --strings 0,1
"""
from __future__ import annotations

import argparse

from mmtools.db2 import format_value, read_wdc5


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file")
    parser.add_argument("--strings", default="", help="comma-separated field indices holding strings")
    ns = parser.parse_args()
    fields = {int(i) for i in ns.strings.split(",") if i}
    with open(ns.file, "rb") as f:
        rows = read_wdc5(f.read(), fields)
    for r in rows:
        print("\t".join(format_value(v) for v in r))


if __name__ == "__main__":
    main()

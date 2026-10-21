#!/usr/bin/env python3
"""Copy the reference-shot session's screenshots into docs/evidence/shots/ as ref-<id>.jpg
(docs/evidence/shots/README.md). The newest screenshots in the client's Screenshots/ are the
shots, in list order: the oldest of them gets the first id. stamps.txt there keeps which
WoWScrnShot_<stamp>.jpg became which id.

  .venv/bin/python tools/refshots.py                     # every id in the README's list
  .venv/bin/python tools/refshots.py --skip small-group,small-corpse   # optional shots not taken
  .venv/bin/python tools/refshots.py small-seam          # a retake: the newest screenshot only
  .venv/bin/python tools/refshots.py --dry-run           # the pairing, nothing copied

The install is "/Applications/World of Warcraft" (MAGICMAP_WOW, --wow), flavor _classic_beta_ (--flavor).
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "docs", "evidence", "shots")
ROW = re.compile(r"\|\s*\d+\s*\|\s*`([a-z0-9-]+)`")  # a shot row: | 1 | `small-home` | ...
STAMP = re.compile(r"WoWScrnShot_(\d{6}_\d{6})\.jpg$")


def listed() -> list[str]:
    with open(os.path.join(SHOTS, "README.md"), encoding="utf-8") as f:
        return [m.group(1) for m in map(ROW.match, f) if m]


def screenshots(folder: str) -> list[tuple[dt.datetime, str]]:
    """(stamp time, file name), oldest first."""
    out = []
    for p in glob.glob(os.path.join(folder, "WoWScrnShot_*.jpg")):
        m = STAMP.search(p)
        if m:
            out.append((dt.datetime.strptime(m.group(1), "%m%d%y_%H%M%S"), os.path.basename(p)))
    return sorted(out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="only these, in this order (default: the README's list)")
    ap.add_argument("--skip", default="", help="ids not taken, comma-separated")
    ap.add_argument("--wow", default=os.environ.get("MAGICMAP_WOW", "/Applications/World of Warcraft"))
    ap.add_argument("--flavor", default="_classic_beta_")
    ap.add_argument("--dry-run", action="store_true", help="print the pairing, copy nothing")
    args = ap.parse_args(argv)

    ids = listed()
    skip = [i for i in args.skip.split(",") if i]
    unknown = [i for i in args.ids + skip if i not in ids]
    if unknown:
        sys.exit(f"not in docs/evidence/shots/README.md: {', '.join(unknown)}")
    want = [i for i in args.ids or ids if i not in skip]
    folder = os.path.join(args.wow, args.flavor, "Screenshots")
    files = screenshots(folder)
    if len(files) < len(want):
        sys.exit(f"{len(want)} shots, but {len(files)} screenshots in {folder}")

    stamps_path = os.path.join(SHOTS, "stamps.txt")
    stamps = {}
    if os.path.exists(stamps_path):
        with open(stamps_path, encoding="utf-8") as f:
            stamps = dict(line.split() for line in f if line.strip())
    for i, (t, name) in zip(want, files[len(files) - len(want):]):
        print(f"{t:%Y-%m-%d %H:%M:%S}  {name} -> ref-{i}.jpg")
        stamps[i] = name
        if not args.dry_run:
            shutil.copy2(os.path.join(folder, name), os.path.join(SHOTS, f"ref-{i}.jpg"))
    if not args.dry_run:
        with open(stamps_path, "w", encoding="utf-8") as f:
            f.writelines(f"{i} {stamps[i]}\n" for i in ids if i in stamps)
    return 0


if __name__ == "__main__":
    sys.exit(main())

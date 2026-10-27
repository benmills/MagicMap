#!/usr/bin/env python3
"""The map review's marks beside the linter's issues (docs/hardening-plan.md M6): what's been accepted,
rejected or left for later in the web demo, with the reviewers' notes.

  .venv/bin/python tools/review.py                          # the local demo's marks (demo/review/decisions.json)
  .venv/bin/python tools/review.py --from https://HOST/     # a hosted demo's (its /api/review and /api/lint)
  .venv/bin/python tools/review.py --from https://HOST/ --save docs/map-review.json   # keep a copy in the repo
  .venv/bin/python tools/review.py --all                    # open issues too, not only the marked ones
  .venv/bin/python tools/review.py --json -                 # issues with their marks, as JSON

Issues come from the same place as the marks (the hosted demo's /api/lint with --from), or --issues FILE.
An issue whose id the marks name but the issues file lacks is listed as gone (fixed, or renamed by a
linter change). With $MAGICMAP_REVIEW_TOKEN set it's sent along (the hosted review may need it to read).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORDER = {"accepted": 0, "later": 1, "rejected": 2, None: 3}


def fetch(base: str, path: str) -> dict:
    req = urllib.request.Request(base.rstrip("/") + path, headers={"X-Review-Token": os.environ.get("MAGICMAP_REVIEW_TOKEN", "")})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def load(path: str, empty: dict) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return empty


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="src", metavar="URL", help="a demo's address (default: the local files)")
    ap.add_argument("--marks", default=os.path.join(ROOT, "demo", "review", "decisions.json"), help="the marks file, without --from")
    ap.add_argument("--issues", help="the issues file (default: --from's /api/lint, else demo/lint/issues.json)")
    ap.add_argument("--save", metavar="FILE", help="write the marks to FILE (e.g. docs/map-review.json)")
    ap.add_argument("--all", action="store_true", help="list open issues too")
    ap.add_argument("--json", metavar="FILE", help="the issues with their marks as JSON (- for stdout)")
    ns = ap.parse_args()

    marks = fetch(ns.src, "/api/review") if ns.src else load(ns.marks, {"decisions": {}, "log": []})
    if ns.issues:
        lint = load(ns.issues, {"issues": []})
    elif ns.src:
        lint = fetch(ns.src, "/api/lint")
    else:
        lint = load(os.path.join(ROOT, "demo", "lint", "issues.json"), {"issues": []})
    if ns.save:
        with open(ns.save, "w") as f:
            json.dump(marks, f, indent=1)
            f.write("\n")

    dec = marks.get("decisions", {})
    issues = {i["id"]: i for i in lint.get("issues", [])}
    rows = [dict(issues.get(id, {"id": id, "gone": True}), mark=m) for id, m in dec.items()]
    if ns.all:
        rows += [dict(i, mark=None) for id, i in issues.items() if id not in dec]
    rows.sort(key=lambda r: (ORDER.get((r["mark"] or {}).get("status")), r.get("kind", ""), -r.get("severity", 0)))

    if ns.json:
        out = json.dumps(rows, indent=1)
        if ns.json == "-":
            print(out)
        else:
            with open(ns.json, "w") as f:
                f.write(out + "\n")
        return 0
    counts = {}
    for r in rows:
        s = (r["mark"] or {}).get("status") or "open"
        counts[s] = counts.get(s, 0) + 1
    print(f"{len(issues)} issues (build {lint.get('build', '?')}, {lint.get('commit', '?')}); marks updated {marks.get('updated')}; "
          + ", ".join(f"{k} {v}" for k, v in counts.items()))
    last = object()
    for r in rows:
        m = r["mark"] or {}
        s = m.get("status") or "open"
        if s != last:
            print(f"\n== {s}")
            last = s
        where = "GONE from the issues file" if r.get("gone") else f"{r['zone']}  sev {r['severity']}  {r['desc']}"
        print(f"  {r['id']}  {where}")
        if m:
            print(f"      {m.get('by') or '?'} {m.get('at')}" + (f": {m['note']}" if m.get("note") else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())

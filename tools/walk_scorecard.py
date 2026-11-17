#!/usr/bin/env python3
"""The walk scorecard: demo/walk_cases.json's grid cases, each run on each side (the released 3.1.1 and v2) by the demo's
own route code, every drawn line then walked against the real terrain, and a pass/fail per case from its "expect".
Writes demo/walk_scorecard.json, which the Routes page (demo/routes.html) shows.

  .venv/bin/python tools/walk_scorecard.py [--fine DIR] [--sides 311,2]

--fine: gen_walk's terrain cache (fine_<inst>.npz: its per-quad heights and flags; gen_walk writes it from the local
game, so it isn't in git). The checks, on the line a player follows (every yard of it, hand links skipped):
  climb  the most it rises over 4 yards: past 6.8 (50 degrees over 4 yards and the game's 2-yard step) you can't
  drop   the most it falls in one go down ground steeper than 61.6 degrees (what you can walk down): past 14.57 it
         hurts, past ~40 it kills
A partial route's last leg (straight on from as near as it got) isn't checked: the page draws it as "no way on".
"""
import argparse
import json
import math
import os
import sys
import time

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "demo"))
import gen_walk as gw  # noqa: E402

YD = 1600 / 3            # yards a tile
CLIMB_MAX = 4 * math.tan(math.radians(50)) + 2.0   # 6.77 yd over 4 yd
DESCENT = 4 * math.tan(math.radians(61.6))         # a 4-yd fall steeper than this is a drop, not a walk
DROP_HURTS = 14.57
LINK_NEAR = 20 / YD      # a line this near both ends of a link takes it
LINK_W = 12 / YD         # a link's corridor, each side of it


class Ground:
    def __init__(self, fine_dir, inst):
        with np.load(os.path.join(fine_dir, f"fine_{inst}.npz")) as z:
            self.h, self.k, (self.gc0, self.gr0) = z["inner"], z["kind"], (int(v) for v in z["origin"])

    def at(self, col, row):
        """The quad's centre height and whether you'd be swimming (deep water) or nowhere (a hole, no terrain)."""
        qx, qy = int(col * 128) - self.gc0 * 8, int(row * 128) - self.gr0 * 8
        if not (0 <= qy < self.h.shape[0] and 0 <= qx < self.h.shape[1]):
            return None, False
        k = int(self.k[qy, qx])
        h = float(self.h[qy, qx])
        return (None if math.isnan(h) or k & (gw.Q_HOLE | gw.Q_NONE) else h), bool(k & gw.Q_DEEP)


def seg_dist(p, a, b):
    ax, ay, bx, by = a[0], a[1], b[0], b[1]
    vx, vy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * vx + (p[1] - ay) * vy) / ((vx * vx + vy * vy) or 1e-12)))
    return math.hypot(p[0] - ax - t * vx, p[1] - ay - t * vy)


def walk_line(ground, links, way):
    """The line's checks: worst climb over 4 yd, worst drop, the links it takes, where the worst of each is. A hand
    link is a corridor LINK_W wide along its length (a lift's shaft, a bridge's deck): the line in it isn't judged,
    and the link counts as taken when the line comes near both its ends."""
    pts = [way[0]]
    for p, q in zip(way, way[1:]):
        n = max(1, int(math.dist(p, q) * YD / 4))  # a sample every 4 yards (a quad)
        pts += [(p[0] + (q[0] - p[0]) * i / n, p[1] + (q[1] - p[1]) * i / n) for i in range(1, n + 1)]
    near = [l for l in links if min(seg_dist(s, l["a"], l["b"]) for s in pts[::4] + pts[-1:]) < 4 * LINK_W]
    on_link = [any(seg_dist(s, l["a"], l["b"]) < LINK_W for l in near) for s in pts]
    used = [l["name"] for l in near if min(math.dist(s, l["a"]) for s in pts) < LINK_NEAR
            and min(math.dist(s, l["b"]) for s in pts) < LINK_NEAR]
    hs = [ground.at(*s) for s in pts]
    climb, climb_at, drop, drop_at, run, run_at = 0.0, None, 0.0, None, 0.0, None
    for i in range(len(pts) - 1):
        (h0, w0), (h1, w1) = hs[i], hs[i + 1]
        if h0 is None or h1 is None or w0 or w1 or on_link[i] or on_link[i + 1]:  # swimming, no terrain, a link
            run, run_at = 0.0, None
            continue
        dz = h1 - h0
        if dz > climb:
            climb, climb_at = dz, pts[i]
        if -dz > DESCENT:  # down a face you can't walk: falling, the drop adds up till you land
            run, run_at = run - dz, run_at or pts[i]
            if run > drop:
                drop, drop_at = run, run_at
        else:
            run, run_at = 0.0, None
    return {"climb": round(climb, 1), "climbAt": climb_at and [round(v, 4) for v in climb_at],
            "drop": round(drop, 1), "dropAt": drop_at and [round(v, 4) for v in drop_at], "links": used}


def judge(expect, run):
    """Pass or fail with the reasons, from the case's expect: link (takes a hand link), maxRatio, noWayOk (a clear
    "no way" also passes), drop (the most fall allowed: a one-way case's drop is the point, up to what doesn't hurt)."""
    why = []
    if run.get("error"):
        return False, [run["error"]]
    no_way = not run["found"] or run["partial"]
    if no_way and not expect.get("noWayOk"):
        why.append("no way found" if not run["found"] else "only part of the way")
    if run.get("capped"):
        why.append("search gave up (node cap)")
    if run["climb"] > CLIMB_MAX:
        why.append(f"climbs {run['climb']:.0f} yd in 4 yd (a cliff)")
    if run["drop"] > expect.get("drop", DROP_HURTS):
        why.append(f"drops {run['drop']:.0f} yd" + (" (fatal)" if run["drop"] > 40 else " (hurts)"))
    if not no_way:
        if run["ratio"] and run["ratio"] > expect.get("maxRatio", 2.0):
            why.append(f"{run['ratio']:.2f}x straight (allowed {expect.get('maxRatio', 2.0)}x)")
        if expect.get("link") and not run["links"]:
            why.append("doesn't take the hand link")
    return not why, why


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fine", default=os.environ.get("MM_FINE", os.path.join(ROOT, "promo", "walkfine")))
    ap.add_argument("--sides", default="311,2")
    ap.add_argument("-o", "--output", default=os.path.join(ROOT, "demo", "walk_scorecard.json"))
    ns = ap.parse_args()
    import server  # the demo's route code: loads the tree's Atlas and the frozen 3.1.1 one

    with open(os.path.join(ROOT, "tools", "walk_links.json"), encoding="utf-8") as f:
        all_links = json.load(f)["links"]
    with open(os.path.join(ROOT, "demo", "walk_cases.json"), encoding="utf-8") as f:
        expects = {c["name"]: c.get("expect", {}) for c in json.load(f)["cases"]}
    grounds = {}
    t0 = time.time()
    got = server.cases({"sides": ns.sides})
    for case in got["cases"]:
        inst = case["inst"]
        dx, dy = server.OFFSET[inst]
        ground = grounds.setdefault(inst, Ground(ns.fine, inst))
        links = [l for l in all_links if l["inst"] == inst]
        expect = expects.get(case["name"], {})
        case["expect"] = expect
        for run in case["runs"]:
            way = [(x - dx, y - dy) for x, y in run.get("way") or []]
            checked = way[:-1] if (run.get("partial") and len(way) > 2) else way
            run.update(walk_line(ground, links, checked) if len(checked) > 1 else
                       {"climb": 0.0, "climbAt": None, "drop": 0.0, "dropAt": None, "links": []})
            run["pass"], run["why"] = judge(expect, run)
            for k in ("climbAt", "dropAt"):  # back on the demo's world, as the line is
                if run[k]:
                    run[k] = [round(run[k][0] + dx, 4), round(run[k][1] + dy, 4)]
    got["made"] = time.strftime("%Y-%m-%d %H:%M")
    got["commit"] = os.popen(f"git -C {ROOT} describe --always --dirty").read().strip()
    got["score"] = {side["v"]: sum(all(r["pass"] for r in c["runs"] if r["v"] == side["v"]) for c in got["cases"])
                    for side in got["sides"]}
    got["limits"] = {"climb": round(CLIMB_MAX, 2), "drop": DROP_HURTS}
    with open(ns.output, "w", encoding="utf-8") as f:
        json.dump(got, f, indent=1)
    for case in got["cases"]:
        for run in case["runs"]:
            mark = "PASS" if run["pass"] else "FAIL"
            ratio = f"{run['ratio']:.2f}x" if run.get("ratio") else "  -  "
            print(f"{mark}  {run['label']:5} {run['dir']}  {case['name'][:46]:46} {ratio:>6}  climb {run['climb']:5.1f}"
                  f"  drop {run['drop']:5.1f}  {'; '.join(run['why'])}")
    print(f"({time.time() - t0:.1f} s) -> {os.path.relpath(ns.output, ROOT)}")


if __name__ == "__main__":
    main()

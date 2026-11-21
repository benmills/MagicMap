#!/usr/bin/env python3
"""The everyday route's shape: seeded random walks in every zone of both continents (walk_sweep's pairs), each found by
the tree's Atlas.Route.Find as the addon does, and the drawn line measured for what makes it annoying to follow:

  turns    corners of over 20 degrees, a km: a line that keeps changing its mind
  turning  degrees turned, a km, all corners (the curves' small ones too)
  zigzag   a turn undone by one the other way within 25 yd: a wave or a jog round nothing
  tiny     legs under 3 yd that aren't part of a curve: kinks too small to see as anything but noise
  sharp    corners over 100 degrees: doubling back
  knots    the line crossing itself
  ratio    its length over the straight line (the cost of smoothing, if it rises)

  .venv/bin/python tools/walk_smooth.py [--per-zone 4] [--seed 7] [--sheet FILE.png] [--json FILE] [--tune slack=10 ...]

--sheet draws routes (the noisiest first) over the terrain, shaded from gen_walk's height cache (promo/walkfine, or
MM_FINE): rough ground tinted, sheer ground darker, the line red with its points.
"""
import argparse
import json
import math
import os
import statistics
import sys
import time

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import walk_sweep  # noqa: E402

YD = 1600 / 3  # yards a tile
TURN = 20      # degrees: a corner worth counting
ZIGZAG_YD = 25
TINY_YD = 3
SHARP = 100


def angle(ax, ay, bx, by):
    """The turn from heading (ax, ay) to (bx, by), degrees, signed."""
    return math.degrees(math.atan2(ax * by - ay * bx, ax * bx + ay * by))


def crosses(p1, p2, p3, p4):
    def side(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1, d2, d3, d4 = side(p3, p4, p1), side(p3, p4, p2), side(p1, p2, p3), side(p1, p2, p4)
    return (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0) and 0 not in (d1, d2, d3, d4)


def shape(line):
    """The measures of one line (tile coordinates)."""
    pts = [(x * YD, y * YD) for x, y in line]
    pts = [p for i, p in enumerate(pts) if i == 0 or math.dist(p, pts[i - 1]) > 1e-6]
    length = sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
    legs = [math.dist(a, b) for a, b in zip(pts, pts[1:])]
    turns = []  # (signed degrees, yards along at the corner)
    s = 0.0
    for i in range(1, len(pts) - 1):
        s += legs[i - 1]
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        turns.append((angle(b[0] - a[0], b[1] - a[1], c[0] - b[0], c[1] - b[1]), s))
    big = [(t, at) for t, at in turns if abs(t) > TURN]
    zig = 0
    for (t1, s1), (t2, s2) in zip(big, big[1:]):
        if (t1 > 0) != (t2 > 0) and s2 - s1 < ZIGZAG_YD:
            zig += 1
    # a tiny leg between two corners that turn the same way by little is a curve's: not counted
    tiny = 0
    for i in range(1, len(legs) - 1):
        if legs[i] < TINY_YD:
            t1, t2 = turns[i - 1][0], turns[i][0]
            if not ((t1 > 0) == (t2 > 0) and abs(t1) < 45 and abs(t2) < 45):
                tiny += 1
    knots = 0
    n = len(pts)
    for i in range(n - 1):
        for j in range(i + 2, n - 1):
            if crosses(pts[i], pts[i + 1], pts[j], pts[j + 1]):
                knots += 1
    km = max(length, 1) / 1000
    straight = math.dist(pts[0], pts[-1]) if pts else 0
    return {"yd": round(length), "ratio": round(length / straight, 3) if straight > 1 else None,
            "points": len(pts), "turns": round(len(big) / km, 1), "turning": round(sum(abs(t) for t, _ in turns) / km),
            "zigzag": zig, "tiny": tiny, "sharp": sum(1 for t, _ in turns if abs(t) > SHARP), "knots": knots}


def noise(m):
    """One number to sort by: what a player sees as noise."""
    return m["zigzag"] * 3 + m["knots"] * 10 + m["tiny"] * 2 + m["sharp"] * 2 + m["turns"] / 5


# ---------------------------------------------------------------------------------------------------- the sheet

def worst_at(line, yd):
    """The point of the line with the most turning within yd/2 either side (tile coords)."""
    pts = [(x * YD, y * YD) for x, y in line]
    best, at = -1, line[len(line) // 2]
    for i in range(1, len(pts) - 1):
        t = 0.0
        for j in range(1, len(pts) - 1):
            if math.dist(pts[i], pts[j]) < yd / 2:
                a, b, c = pts[j - 1], pts[j], pts[j + 1]
                t += abs(angle(b[0] - a[0], b[1] - a[1], c[0] - b[0], c[1] - b[1]))
        if t > best:
            best, at = t, line[i]
    return at


def sheet(rows, path, fine_dir, n=12, size=360, zoom=None):
    from PIL import Image, ImageDraw
    grounds = {}
    tiles = []
    for r in rows[:n]:
        inst = r["inst"]
        if inst not in grounds:
            p = os.path.join(fine_dir, f"fine_{inst}.npz")
            if not os.path.exists(p):
                continue
            with np.load(p) as z:
                grounds[inst] = (z["inner"], z["kind"], [int(v) for v in z["origin"]])
        h, k, (gc0, gr0) = grounds[inst]
        xs, ys = [p[0] for p in r["line"]], [p[1] for p in r["line"]]
        if zoom:
            (cx, cy), span = worst_at(r["line"], zoom), zoom / YD
        else:
            cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
            span = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.15 + 40 / YD
        q0x, q0y = int((cx - span / 2) * 128) - gc0 * 8, int((cy - span / 2) * 128) - gr0 * 8
        nq = max(8, int(span * 128))
        sub = h[max(q0y, 0):q0y + nq, max(q0x, 0):q0x + nq].astype(np.float64)
        kk = k[max(q0y, 0):q0y + nq, max(q0x, 0):q0x + nq]
        sub = np.nan_to_num(sub, nan=np.nanmin(sub) if np.isfinite(sub).any() else 0)
        sub = np.kron(sub, np.ones((2, 2))) if zoom else sub  # (a little finer than the quads up close)
        kk = np.kron(kk, np.ones((2, 2), kk.dtype)) if zoom else kk
        gy, gx = np.gradient(sub, 2.0 if zoom else 4.0)
        shade = np.clip(0.55 + (-gx * 0.6 - gy * 0.6) / np.sqrt(1 + gx * gx + gy * gy) * 0.8, 0, 1)
        slope = np.degrees(np.arctan(np.hypot(gx, gy)))
        lo, hi = np.percentile(sub, 2), np.percentile(sub, 98)
        tint = np.clip((sub - lo) / max(hi - lo, 1), 0, 1)
        rgb = np.stack([0.55 + 0.25 * tint, 0.6 + 0.1 * tint, 0.45 - 0.1 * tint], -1) * shade[..., None]
        rgb[slope > 50] = rgb[slope > 50] * 0.6 + np.array([0.5, 0.25, 0.1]) * 0.4
        rgb[slope > 61.6] = rgb[slope > 61.6] * 0.5
        water = (kk & 1) != 0  # (gen_walk.Q_DEEP)
        rgb[water] = np.array([0.25, 0.4, 0.6])
        img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).resize((size, size), Image.BILINEAR)
        d = ImageDraw.Draw(img)
        scale = size / (nq / 128)
        px = [((x - (q0x + gc0 * 8) / 128) * scale, (y - (q0y + gr0 * 8) / 128) * scale) for x, y in r["line"]]
        d.line(px, fill=(220, 30, 30), width=2)
        for p in px:
            d.ellipse([p[0] - 1.5, p[1] - 1.5, p[0] + 1.5, p[1] + 1.5], fill=(255, 240, 120))
        d.ellipse([px[0][0] - 4, px[0][1] - 4, px[0][0] + 4, px[0][1] + 4], outline=(0, 160, 0), width=2)
        d.ellipse([px[-1][0] - 4, px[-1][1] - 4, px[-1][0] + 4, px[-1][1] + 4], outline=(160, 0, 0), width=2)
        m = r["m"]
        d.rectangle([0, 0, size, 14], fill=(0, 0, 0))
        d.text((3, 1), f"{r['name'][:26]}  zz{m['zigzag']} kn{m['knots']} tiny{m['tiny']} t/km{m['turns']}",
               fill=(255, 255, 255))
        tiles.append(img)
    if not tiles:
        return None
    cols = 4
    out = Image.new("RGB", (cols * size, ((len(tiles) + cols - 1) // cols) * size), (0, 0, 0))
    for i, t in enumerate(tiles):
        out.paste(t, ((i % cols) * size, (i // cols) * size))
    out.save(path)
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--per-zone", type=int, default=4)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--inst", type=int, nargs="*", default=[0, 1])
    ap.add_argument("--sheet")
    ap.add_argument("--sheet-n", type=int, default=12)
    ap.add_argument("--zoom", type=float, help="yards across each picture, round the route's most winding part")
    ap.add_argument("--json")
    ap.add_argument("--tune", nargs="*", default=[], help="Route.TUNE's, key=value (the Settings > Tracking > Route ones)")
    ap.add_argument("--fine", default=os.environ.get("MM_FINE", os.path.join(ROOT, "promo", "walkfine")))
    ns = ap.parse_args()
    side = walk_sweep.Side("2")
    for kv in ns.tune:
        k, v = kv.split("=")
        side.R.TUNE[k] = float(v)
    t0 = time.time()
    pairs = walk_sweep.random_pairs([side], ns.inst, ns.per_zone, ns.seed)
    rows = []
    for p in pairs:
        r = side.find(p["inst"], p["a"], p["b"])
        if r["class"] != "found" or len(r["pts"]) < 2:
            continue
        rows.append({"name": p["name"], "inst": p["inst"], "line": r["pts"], "m": shape(r["pts"])})
    keys = ("turns", "turning", "zigzag", "tiny", "sharp", "knots")
    print(f"{len(rows)} routes of {len(pairs)} pairs ({time.time() - t0:.1f} s)")
    summ = {}
    for k in keys:
        v = [r["m"][k] for r in rows]
        summ[k] = {"mean": round(statistics.mean(v), 2), "p90": round(float(np.percentile(v, 90)), 1),
                   "routes": sum(1 for x in v if x)}
    ratios = [r["m"]["ratio"] for r in rows if r["m"]["ratio"]]
    summ["ratio"] = {"median": round(statistics.median(ratios), 3), "p90": round(float(np.percentile(ratios, 90)), 3)}
    for k, v in summ.items():
        print(f"  {k:8} " + "  ".join(f"{a} {b}" for a, b in v.items()))
    rows.sort(key=lambda r: -noise(r["m"]))
    print("noisiest:", ", ".join(f"{r['name']} ({noise(r['m']):.0f})" for r in rows[:8]))
    if ns.json:
        with open(ns.json, "w") as f:
            json.dump({"summary": summ, "routes": [{k: r[k] for k in ("name", "inst", "m")} for r in rows]}, f, indent=1)
    if ns.sheet:
        print("sheet:", sheet(rows, ns.sheet, ns.fine, ns.sheet_n, zoom=ns.zoom))


if __name__ == "__main__":
    main()

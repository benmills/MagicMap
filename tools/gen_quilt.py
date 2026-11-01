#!/usr/bin/env python3
"""Bake the demo's "Tile texture" layer: all the map's flat ground quilted from its own zone's minimap tiles (gen_fill.py's quilt), so
it has the tiles' own look at the tiles' own scale; a game ground texture can't, being art for up close. Picked by rule, not by
the review: flat ground (tools/flatmap.py) in patches, less what the review rejected or already rebuilt. A piece is drawn
desaturated (the client's SetDesaturated) and tinted to the ground it covers (vertex colour), so it brings the tiles' structure
and none of their colour, and may come from any good ground nearby. A trial: writes only demo/quilt/ (quilt.json, *.webp), nothing for the addon.

  python3 tools/gen_quilt.py local "/Applications/World of Warcraft" wow_classic_beta --cache DIR [--only inst,c0,r0,c1,r1 ...]
"""
from __future__ import annotations

import argparse
import json
import multiprocessing
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import maplint
from flatmap import read
from gen_clouds import components, grow, places
from gen_fill import PIECE, Ground, bake, quilt, regions
from mmtools.sources import add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEAST = 16      # chunks: a smaller flat patch is left as it is
TOO_BRIGHT = 1.5 # what a piece covers, over its source's grey: brighter than this, no piece
CELL = 10       # tiles: a bigger region is quilted in cells this size


class Grey(Ground):
    """The tiles as the client draws them desaturated."""

    def art(self, key, n):
        a = super().art(key, n)
        return None if a is None else np.repeat(a.mean(-1, keepdims=True), 3, -1)


def tint(g: Grey, pieces: list, tone: np.ndarray, hole_of: np.ndarray) -> None:
    """Each piece's vertex colour: what it covers' tone over its source's own grey (it can only darken)."""
    tiles = {}
    for p in pieces:
        if p["key"] not in tiles:
            tiles[p["key"]] = g.art(p["key"], 16 * 8)
        grey = tiles[p["key"]][p["sr"] * 8:(p["sr"] + PIECE) * 8, p["sc"] * 8:(p["sc"] + PIECE) * 8, 0].mean()
        here = tone[p["row"]:p["row"] + PIECE, p["col"]:p["col"] + PIECE]
        under = hole_of[p["row"]:p["row"] + PIECE, p["col"]:p["col"] + PIECE]
        want = here[under].mean(0) if under.any() else here.mean((0, 1))
        over = float(want.max()) / max(grey, 1)  # (it can only darken: over 1, the whole colour scaled, or its hue goes)
        p["gain"] = [round(float(v / max(grey, 1) / max(over, 1)), 3) for v in want]
        p["over"] = over
    pieces[:] = [p for p in pieces if p["over"] <= TOO_BRIGHT]


def cells(box: tuple) -> list[tuple]:
    c0, r0, c1, r1 = box
    return [(c, r, min(c + CELL, c1), min(r + CELL, r1)) for c in range(c0, c1, CELL) for r in range(r0, r1, CELL)]


def one(job: tuple) -> dict | None:
    inst, n, box, ns_args, out = job
    ap = argparse.ArgumentParser()
    add_source_args(ap)
    ns = ap.parse_args(ns_args[:3])
    src, cache = source_from_args(ap, ns), ns_args[3]
    data = maplint.Data(os.path.join(ROOT, "Data"))
    g = Grey(src, inst, data.tiles[inst], data.sea[inst], cache)
    z = np.load(os.path.join(out, f".job{inst}.npz"))
    c0, r0, c1, r1 = box
    only = np.zeros_like(z["want"])
    only[r0 * 16:r1 * 16, c0 * 16:c1 * 16] = z["want"][r0 * 16:r1 * 16, c0 * 16:c1 * 16]
    pieces, hole = quilt(g, box, only, z["flagged"], np.ones((1024, 1024), int))
    if not pieces:
        return None
    c0_, r0_ = min(p["col"] for p in pieces), min(p["row"] for p in pieces)
    tint(g, pieces, z["tone"], z["want"])
    if not pieces:
        return None
    name = f"{inst}_{n}.webp"
    x, y = (min(p["col"] for p in pieces) - c0_) * 16, (min(p["row"] for p in pieces) - r0_) * 16  # (the hole's box, to what's left)
    x1, y1 = (max(p["col"] for p in pieces) + PIECE - c0_) * 16, (max(p["row"] for p in pieces) + PIECE - r0_) * 16
    box_ = bake(g, pieces, hole[y:y1, x:x1], os.path.join(out, name), 16)
    return {"inst": inst, "pieces": len(pieces), "file": name, **box_}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--out", default=os.path.join(ROOT, "demo", "quilt"))
    ap.add_argument("--only", nargs="*", default=[], help="inst,c0,r0,c1,r1: only these boxes")
    ap.add_argument("--workers", type=int, default=6)
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    args = [ns.source if hasattr(ns, "source") else "local", "/Applications/World of Warcraft", "wow_classic_beta", ns.cache]
    issues = json.load(open(os.path.join(ROOT, "demo", "lint", "issues.json")))["issues"]
    decisions = json.load(open(os.path.join(ROOT, "docs", "map-review.json")))["decisions"]
    rejected = {k: {"status": "accepted"} for k, v in decisions.items() if v.get("status") == "rejected"}
    everything = {i["id"]: {"status": "accepted"} for i in issues if i["kind"] in ("flat-land", "patch-edge", "seam")}
    data = maplint.Data(os.path.join(ROOT, "Data"))
    os.makedirs(ns.out, exist_ok=True)
    jobs = []
    for inst in (0, 1):
        m = read(src, inst, data.tiles[inst], data.sea[inst], ns.cache)
        want = m.flat & ~places(issues, rejected, inst) & ~places(issues, decisions, inst)
        keep = np.zeros_like(want)
        for s in components(want):
            if want[s].sum() >= LEAST:
                keep[s] |= want[s]
        np.savez(os.path.join(ns.out, f".job{inst}.npz"), want=keep, flagged=grow(places(issues, everything, inst), 1), tone=m.tone)
        boxes = [c for b in regions(keep) for c in cells(b)]
        boxes = [b for b in boxes if keep[b[1] * 16:b[3] * 16, b[0] * 16:b[2] * 16].any()]
        only = [tuple(int(v) for v in o.split(",")) for o in ns.only]
        if only:
            boxes = [b for b in boxes if any(o[0] == inst and b[0] < o[3] and o[1] < b[2] and b[1] < o[4] and o[2] < b[3] for o in only)]
        jobs += [(inst, n, b, args, ns.out) for n, b in enumerate(boxes)]
        print(inst, "flat kept", int(keep.sum()), "boxes", len(boxes), flush=True)
    out = {"0": [], "1": []}
    with multiprocessing.Pool(ns.workers) as pool:
        for r in pool.imap_unordered(one, jobs):
            if r:
                print(r["inst"], r["file"], r["pieces"], flush=True)
                out[str(r.pop("inst"))].append({k: r[k] for k in ("file", "col", "row", "w", "h", "pieces")})
    with open(os.path.join(ns.out, "quilt.json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print("pieces", sum(x["pieces"] for v in out.values() for x in v))


if __name__ == "__main__":
    main()

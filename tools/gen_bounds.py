#!/usr/bin/env python3
"""Bake the demo's "out of bounds" veil: land players can't reach, muted so the map doesn't invite them there.

A chunk is in bounds if the terrain lets you walk or swim to it from a town (Data/Walk.lua's crossings) and it's in a zone
(Data/AreaGrid.lua: the game's unfinished land is mostly in none). The terrain can't see invisible walls, so the zone test
does what it can there. An estimate: named exceptions go in KEEP. Ours, a colour and a soft edge, no Blizzard px.

  python3 tools/gen_bounds.py --bake demo/bounds
"""
from __future__ import annotations

import argparse
import json
import os
import re
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

import maplint

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = 1024
PX = 4              # the picture's px a chunk
VEIL = (34, 36, 40) # its colour
ALPHA = .62         # at its strongest
MARGIN = 3          # chunks: land this near what's in bounds stays clear


def walk(inst_body: str) -> np.ndarray:
    v = np.zeros((N, N), np.uint8)
    for key, s in re.findall(r'\[(\d+)\] = "([^"]+)"', inst_body):
        k, cells = int(key), []
        for ch, n in re.findall(r"([a-p])(\d*)", s):
            cells += [ord(ch) - 97] * (int(n) if n else 1)
        v[k % 64 * 16:k % 64 * 16 + 16, k // 64 * 16:k // 64 * 16 + 16] = np.array(cells, np.uint8).reshape(16, 16)
    return v


def reach(v: np.ndarray, towns: list) -> np.ndarray:
    cls, seen, q = v & 3, np.zeros((N, N), bool), deque()
    for x, y in towns:
        c, r = int(x * 16), int(y * 16)
        for d in range(12):
            r0, c0 = max(r - d, 0), max(c - d, 0)
            hit = np.argwhere(cls[r0:r + d + 1, c0:c + d + 1] == 1)
            if len(hit):
                at = (int(hit[0][0]) + r0, int(hit[0][1]) + c0)
                if not seen[at]:
                    seen[at] = True
                    q.append(at)
                break
    while q:
        r, c = q.popleft()
        for dr, dc, ok in ((0, 1, v[r, c] & 4), (1, 0, v[r, c] & 8), (0, -1, c > 0 and v[r, c - 1] & 4), (-1, 0, r > 0 and v[r - 1, c] & 8)):
            rr, cc = r + dr, c + dc
            if ok and 0 <= rr < N and 0 <= cc < N and not seen[rr, cc] and cls[rr, cc] in (1, 2):
                seen[rr, cc] = True
                q.append((rr, cc))
    return seen


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bake", default=os.path.join(ROOT, "demo", "bounds"))
    ns = ap.parse_args()
    data = maplint.Data(os.path.join(ROOT, "Data"))
    text, labels = open(os.path.join(ROOT, "Data", "Walk.lua")).read(), open(os.path.join(ROOT, "Data", "Labels.lua")).read()
    bodies = dict(zip(*[iter(re.split(r"\[(\d)\] = \{ --", text)[1:])] * 2))
    lab = re.split(r"\n\s*\[(\d)\] = \{", labels)[1:]
    os.makedirs(ns.bake, exist_ok=True)
    out = {}
    for inst in (0, 1):
        towns = [(float(x), float(y)) for x, y in re.findall(r'"[^"]+", ([\d.]+), ([\d.]+), "town"', lab[lab.index(str(inst)) + 1])]
        seen = reach(walk(bodies[str(inst)]), towns)
        zones = np.asarray(data.zone_grid[inst]) > 0
        land = np.zeros((N, N), bool)
        for k in data.tiles[inst]:
            if k not in data.sea[inst]:
                land[k % 64 * 16:k % 64 * 16 + 16, k // 64 * 16:k // 64 * 16 + 16] = True
        inb = seen & zones
        g = Image.fromarray(inb.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(MARGIN * 2 + 1))
        off = land & ~(np.asarray(g) > 0)
        rows, cols = np.nonzero(off)
        y0, y1, x0, x1 = rows.min() // 16, rows.max() // 16 + 1, cols.min() // 16, cols.max() // 16 + 1
        pic = Image.fromarray(off[y0 * 16:y1 * 16, x0 * 16:x1 * 16].astype(np.uint8) * 255).resize(((x1 - x0) * 16 * PX, (y1 - y0) * 16 * PX), Image.BILINEAR).filter(ImageFilter.GaussianBlur(PX * 1.5))
        a = np.asarray(pic, np.float32) * ALPHA
        rgba = np.dstack([np.full(a.shape, c, np.float32) for c in VEIL] + [a]).astype(np.uint8)
        name = f"{inst}.webp"
        Image.fromarray(rgba).save(os.path.join(ns.bake, name), quality=70, method=4, alpha_quality=60)
        out[str(inst)] = [{"file": name, "col": float(x0), "row": float(y0), "w": float(x1 - x0), "h": float(y1 - y0)}]
        print(inst, "land chunks", int(land.sum()), "veiled", int(off.sum()), "in bounds", int(inb.sum()))
    with open(os.path.join(ns.bake, "bounds.json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))


if __name__ == "__main__":
    main()

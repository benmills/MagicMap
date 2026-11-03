#!/usr/bin/env python3
"""Generate Textures/Sea*.tga and Data/Sea.lua: an ocean round each continent, where Blizzard's art has only near-black.

The minimap's open water has colour in its shallows and none further out, so there's nothing there to copy: this one is
made, no pixel of anyone's art in it. Open water is what the terrain files say is under water or has no terrain (MCVT,
MH2O), joined to the map's edge (lakes aren't). Its colour runs from SHALLOW by the land through MID to DEEP with the
distance from the land, the line wandering (fractal noise), with a soft swell that dies out by the picture's edge; right by
the land it's SHORE, the dark green Blizzard's own maps use there. It lies over the tiles (ui/Sea.lua), seen through where
Blizzard's water has colour (its alpha reads the art), so their coast and shallows stay theirs and their near-black goes.
Past the picture: DEEP, the window's backdrop.

  python3 tools/gen_sea.py local "/Applications/World of Warcraft" wow_classic_beta --bake demo/sea
"""
from __future__ import annotations

import argparse
import json
import os
import tempfile
from collections import deque

import numpy as np
from PIL import Image

from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.sources import add_source_args, source_from_args
from mmtools.terrain import Ground
from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAD = 6            # tiles of sea round the land
PX = 32            # px a tile the picture's worked out at (the demo's)
SHIP = 16          # ...and shipped at
SHORE, SHALLOW, MID, DEEP = np.array([23, 39, 22.]), np.array([26, 74, 70.]), np.array([12, 48, 62.]), np.array([6, 26, 44.])
NAMES = {0: "EasternKingdoms", 1: "Kalimdor"}


def smooth(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def fractal(seed: int, h: int, w: int, base: float) -> np.ndarray:
    """Noise, 0..1, base blobs a tile."""
    r, out, amp, total, n = np.random.RandomState(seed), np.zeros((h, w), np.float32), 1.0, 0.0, base
    for _ in range(5):
        g = (r.rand(max(2, int(h / PX * n)), max(2, int(w / PX * n))) * 255).astype(np.uint8)
        out += amp * np.asarray(Image.fromarray(g).resize((w, h), Image.BICUBIC), np.float32) / 255
        total, amp, n = total + amp, amp * .55, n * 2
    return out / total


def flood(start: list, h: int, w: int, passable: np.ndarray, seen: np.ndarray) -> None:
    q = deque(start)
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))


def distance(from_: np.ndarray) -> np.ndarray:
    """px to the nearest of from_ (4-way steps)."""
    h, w = from_.shape
    d, q = np.full(from_.shape, 1e6, np.float32), deque()
    for y, x in zip(*np.nonzero(from_)):
        d[y, x] = 0
        q.append((y, x))
    while q:
        y, x = q.popleft()
        v = d[y, x] + 1
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and d[ny, nx] > v:
                d[ny, nx] = v
                q.append((ny, nx))
    return d


def stray(land: np.ndarray, art: np.ndarray) -> np.ndarray:
    """The land nobody painted: a piece of dry terrain whose art is near-black all over."""
    H, W = land.shape
    out, seen = np.zeros(land.shape, bool), np.zeros(land.shape, bool)
    dark = art.max(-1) < 26
    for y, x in zip(*np.nonzero(land)):
        if seen[y, x]:
            continue
        one = np.zeros(land.shape, bool)
        one[y, x] = seen[y, x] = True
        flood([(y, x)], H, W, land, one)
        seen |= one
        if dark[one].mean() > .9:
            out |= one
    return out


def ocean(g: Ground, tiles: dict, sea: dict) -> tuple:
    """(c0, r0, c1, r1), RGBA px at PX a tile."""
    drawn = [k for k in tiles if k not in sea]
    c0, c1 = max(0, min(k // 64 for k in drawn) - PAD), min(64, max(k // 64 for k in drawn) + 1 + PAD)
    r0, r1 = max(0, min(k % 64 for k in drawn) - PAD), min(64, max(k % 64 for k in drawn) + 1 + PAD)
    H, W = (r1 - r0) * PX, (c1 - c0) * PX
    wet, art = np.ones((H, W), bool), np.zeros((H, W, 3), np.float32)
    step = 128 // PX
    for c in range(c0, c1):
        for r in range(r0, r1):
            k, y, x = c * 64 + r, (r - r0) * PX, (c - c0) * PX
            if k in g.maid:
                h, water = g.heights_and_water(k)
                wet[y:y + PX, x:x + PX] = (np.isnan(h) | (h < water))[::step, ::step]
            a = g.art(k, PX)
            if a is not None:
                art[y:y + PX, x:x + PX] = a
    wet |= stray(~wet, art)
    seen = np.zeros((H, W), bool)
    start = [(y, x) for y in range(H) for x in (0, W - 1) if wet[y, x]] + [(y, x) for x in range(W) for y in (0, H - 1) if wet[y, x]]
    for s in start:
        seen[s] = True
    flood(start, H, W, wet, seen)
    tiles_off = distance(~seen) / PX
    edge = distance(np.pad(np.zeros((H - 2, W - 2), bool), 1, constant_values=True)) / PX
    drift, swell = fractal(1, H, W, .7), fractal(2, H, W, 2.5)
    t = np.clip(tiles_off + (drift - .5) * 1.4, 0, None)
    a0, a1, a2 = smooth(0, .22, tiles_off + (drift - .5) * .12)[..., None], smooth(.1, 1.3, t)[..., None], smooth(1.0, 4.5, t)[..., None]
    rgb = ((SHORE * (1 - a0) + SHALLOW * a0) * (1 - a1) + MID * a1) * (1 - a2) + DEEP * a2
    rgb = rgb * (1 + ((swell - .5) * .5 * smooth(0, 2, edge))[..., None])
    # seen through where Blizzard's water has colour (their near-black by the land: SHORE over it)
    colour = smooth(34, 72, art.max(-1))
    near = smooth(0, .05, tiles_off)
    far = smooth(.3, 1.4, tiles_off)
    alpha = near * (1 - colour * (1 - far)) * seen
    return (c0, r0, c1, r1), np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "mm-terrain"), help="the terrain read so far")
    ap.add_argument("--bake", help="also write the web demo's pictures here (sea.json, *.webp)")
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    import maplint
    data = maplint.Data(os.path.join(ROOT, "Data"))
    out, baked = {}, {}
    for inst, name in NAMES.items():
        box, pic = ocean(Ground(src, inst, data.tiles[inst], data.sea[inst], ns.cache), data.tiles[inst], data.sea[inst])
        w, h = (box[2] - box[0]) * SHIP, (box[3] - box[1]) * SHIP
        small = np.asarray(Image.fromarray(pic).resize((w, h), Image.LANCZOS))
        tw, th = 2 ** int(np.ceil(np.log2(w))), 2 ** int(np.ceil(np.log2(h)))
        rows = [[(0, 0, 0, 0)] * tw for _ in range(th)]
        for y in range(h):
            rows[y][:w] = [tuple(int(v) for v in p) for p in small[y]]
        with open(os.path.join(ROOT, "Textures", f"Sea{name}.tga"), "wb") as f:
            f.write(write_tga(tw, th, rows))
        out[inst] = (name, box, tw, th)
        log(f"[{inst}] {box}: {w} x {h} in {tw} x {th}")
        if ns.bake:
            os.makedirs(ns.bake, exist_ok=True)
            Image.fromarray(pic).save(os.path.join(ns.bake, f"{inst}.webp"), quality=85, method=4)
            baked[str(inst)] = {"file": f"{inst}.webp", "col": box[0], "row": box[1], "w": box[2] - box[0], "h": box[3] - box[1]}
    if ns.bake:
        with open(os.path.join(ns.bake, "sea.json"), "w") as f:
            json.dump({"deep": [int(v) for v in DEEP], "maps": baked}, f, separators=(",", ":"))
    with open(os.path.join(ROOT, "Data", "Sea.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- GENERATED by tools/gen_sea.py from the terrain of {src.product} {src.version}. Do not edit.\n")
        f.write("-- [inst] = the continent's ocean (ui/Sea.lua): file (under the addon's folder, no extension), the tile rect it covers,\n")
        f.write("--   px a tile, the texture's size; deep: the colour past it\n")
        f.write(data_head("Sea"))
        f.write("D.Sea = { deep = { %.3f, %.3f, %.3f },\n" % tuple(DEEP / 255))
        for inst, (name, b, tw, th) in out.items():
            f.write(f'  [{inst}] = {{ file = "Textures\\\\Sea{name}", c0 = {b[0]}, r0 = {b[1]}, c1 = {b[2]}, r1 = {b[3]}, px = {SHIP}, w = {tw}, h = {th} }},\n')
        f.write("}\n")


if __name__ == "__main__":
    main()

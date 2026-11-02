#!/usr/bin/env python3
"""Whole-map pictures, to see how a continent's tiles come together: demo/fullmap/<map>_raw.png and <map>_fixed.png, on the same
frame, so they can be flipped between.

  raw:   every tile Blizzard's data lists for the map, as it is, sea tiles and all, on black.
  fixed: what the demo's map draws, its switches as they are by default: the tiles less the open sea, the sea tiles' water
         (Data/Patches.lua), then --layers, baked by their tools (demo/<layer>/<layer>.json), in draw order (demo/mapart.js).

Blizzard's art is in them: generated output, gitignored, never in the addon's package (NOTICE.md). A layer that isn't baked is an
error, not a gap: the fixed picture says what it says only with all of them in.

  cd tools; ../.venv/bin/python gen_fullmap.py local "/Applications/World of Warcraft" wow_classic_beta
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

import numpy as np
from lupa import lua51
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import maplint
from mmtools.log import log
from mmtools.luaout import load_data
from mmtools.mapgrid import blp_rgba
from mmtools.sources import add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = {0: "Eastern Kingdoms", 1: "Kalimdor"}
LAYERS = ("sea", "quilt", "fill", "seams", "bounds")
PX = 128     # px a tile (the game's are 256)
MARGIN = 1   # tiles of backdrop round the map


def frame(keys) -> tuple[int, int, int, int]:
    """The tile rect (c0, r0, c1, r1) round the keys, with the margin."""
    cs, rs = [k // 64 for k in keys], [k % 64 for k in keys]
    return max(0, min(cs) - MARGIN), max(0, min(rs) - MARGIN), min(64, max(cs) + 1 + MARGIN), min(64, max(rs) + 1 + MARGIN)


def lay(img: np.ndarray, rgba: Image.Image, col: float, row: float, w: float, h: float, box: tuple, px: int) -> None:
    """A picture over the canvas at (col, row), w x h tiles, clipped to the frame."""
    x0, y0 = int(round((col - box[0]) * px)), int(round((row - box[1]) * px))
    pw, ph = int(round(w * px)), int(round(h * px))
    if pw < 1 or ph < 1:
        return
    x1, y1 = max(x0, 0), max(y0, 0)
    x2, y2 = min(x0 + pw, img.shape[1]), min(y0 + ph, img.shape[0])
    if x2 <= x1 or y2 <= y1:
        return
    p = np.asarray(rgba.convert("RGBA").resize((pw, ph), Image.BOX if rgba.width >= pw else Image.BILINEAR), np.float32)[y1 - y0:y2 - y0, x1 - x0:x2 - x0]
    a = p[..., 3:] / 255
    img[y1:y2, x1:x2] = (img[y1:y2, x1:x2] * (1 - a) + p[..., :3] * a + .5).astype(np.uint8)


def layer_pics(name: str, inst: int, demo: str) -> tuple[list, list | None]:
    """A baked layer's pictures on inst, and the colour past them (the sea's)."""
    path = os.path.join(demo, name, f"{name}.json")
    if not os.path.exists(path):
        raise SystemExit(f"{path}: not baked; run its tool's --bake, or leave it out of --layers")
    d = json.load(open(path))
    return ([d["maps"][str(inst)]] if "maps" in d else d.get(str(inst), [])), d.get("deep")


def fixed(tile, tiles: dict, sea: dict, patches: dict, inst: int, box: tuple, px: int, layers, demo: str) -> np.ndarray:
    img = np.zeros(((box[3] - box[1]) * px, (box[2] - box[0]) * px, 3), np.uint8)
    for k in tiles:
        if k not in sea:
            lay(img, tile(k), k // 64, k % 64, 1, 1, box, px)
    for k, name in patches.items():
        lay(img, Image.open(os.path.join(ROOT, name.replace("\\", "/") + ".tga")), k // 64, k % 64, 1, 1, box, px)
    for name in layers:
        pics, deep = layer_pics(name, inst, demo)
        if deep:  # past the sea's picture: its colour, over everything (demo/mapart.js)
            keep = np.zeros(img.shape[:2], bool)
            for e in pics:
                keep[max(0, (e["row"] - box[1]) * px):max(0, (e["row"] + e["h"] - box[1]) * px), max(0, (e["col"] - box[0]) * px):max(0, (e["col"] + e["w"] - box[0]) * px)] = True
            img[~keep] = deep
        for e in pics:
            lay(img, Image.open(os.path.join(demo, name, e["file"])), e["col"], e["row"], e["w"], e["h"], box, px)
    return img


def raw(tile, tiles: dict, box: tuple, px: int) -> np.ndarray:
    img = np.zeros(((box[3] - box[1]) * px, (box[2] - box[0]) * px, 3), np.uint8)
    for k in tiles:
        lay(img, tile(k), k // 64, k % 64, 1, 1, box, px)
    return img


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--px", type=int, default=PX, help=f"px a tile (default {PX}; the game's are 256)")
    ap.add_argument("--layers", default=",".join(LAYERS), help="the fixed picture's layers, in draw order")
    ap.add_argument("--maps", default=",".join(map(str, MAPS)), help="instances")
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "demo", "fullmap"))
    ns = ap.parse_args()
    Image.MAX_IMAGE_PIXELS = None
    src = source_from_args(ap, ns)
    data = maplint.Data(os.path.join(ROOT, "Data"))
    P = load_data(lua51.LuaRuntime(), os.path.join(ROOT, "Data", "Patches.lua")).Data.Patches
    layers = [l for l in ns.layers.split(",") if l]
    demo = os.path.join(ROOT, "demo")
    os.makedirs(ns.out, exist_ok=True)
    for inst in map(int, ns.maps.split(",")):
        tiles, sea = data.tiles[inst], data.sea.get(inst, {})
        patches = dict(P[inst].items()) if P[inst] else {}
        cache = {}

        def tile(k):  # a tile at its size: read once, for both pictures
            if k not in cache:
                cache[k] = blp_rgba(src.read(tiles[k])).convert("RGB").resize((ns.px, ns.px), Image.LANCZOS)
            return cache[k]
        box = frame(tiles)
        name = re.sub(r"\W+", "_", MAPS.get(inst, str(inst))).lower()
        for kind, img in (("raw", lambda: raw(tile, tiles, box, ns.px)), ("fixed", lambda: fixed(tile, tiles, sea, patches, inst, box, ns.px, layers, demo))):
            path = os.path.join(ns.out, f"{name}_{kind}.png")
            a = img()
            Image.fromarray(a).save(path, optimize=False)
            log(f"{path}: {a.shape[1]}x{a.shape[0]}, {os.path.getsize(path) / 1e6:.0f} MB")


if __name__ == "__main__":
    main()

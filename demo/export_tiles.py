#!/usr/bin/env python3
"""Export minimap tiles and the sea's textures for the web demo.

For each map (instanceID) in Data/Tiles.lua, every tile's BLP is read from the
local install and written to demo/tiles/<inst>/<key>.webp (key = col * 64 + row).
Tiles are WebP (about a fifth of a PNG's size, so a phone gets sharp tiles
quickly); smaller Lanczos copies go to demo/tiles/<inst>/<size>/<key>.webp
(LODS), so a zoomed-out view doesn't download and hold 512px tiles it draws at
20px. The sea's textures (Textures/Sea/<product>/, tools/gen_sea.py), if the map
has them: <inst>_ocean<v>.blp to demo/tiles/<inst>/ocean<v>.webp with copies at
OCEAN_LODS (as the BLP's mipmaps: a canvas pattern has none), and
<inst>_tint.tga to demo/tiles/<inst>/ocean_tint.png (lossless: it is the sea's
colour).

  .venv/bin/python demo/export_tiles.py                 # Eastern Kingdoms (0)
  .venv/bin/python demo/export_tiles.py --inst 0 --inst 1
  .venv/bin/python demo/export_tiles.py --all
  .venv/bin/python demo/export_tiles.py --sea-only     # just the sea's textures
"""
from __future__ import annotations

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from lupa import lua51  # noqa: E402

from PIL import Image  # noqa: E402

from mmtools.formats import blp_dxt  # noqa: E402
from mmtools.luaout import load_data  # noqa: E402
from mmtools.sources import open_source  # noqa: E402
from mmtools.tga import read_tga  # noqa: E402


LODS = (64, 128, 256)
OCEAN_LODS = (32, 64, 128)
QUALITY = 90


def read_tiles() -> tuple[str, dict[int, dict[int, int]]]:
    t = load_data(lua51.LuaRuntime(), os.path.join(ROOT, "Data", "Tiles.lua")).Data.Tiles
    maps = {int(inst): {int(k): int(v) for k, v in m.tiles.items()} for inst, m in t.maps.items()}
    return t.product, maps


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--inst", type=int, action="append", help="instanceID to export (repeatable; default 0)")
    ap.add_argument("--all", action="store_true", help="export every map in Data/Tiles.lua")
    ap.add_argument("--sea-only", action="store_true", help="only the sea's textures, not the tiles")
    ap.add_argument("--wow", default=os.environ.get("MAGICMAP_WOW", "/Applications/World of Warcraft"))
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "demo", "tiles"))
    ns = ap.parse_args()

    product, maps = read_tiles()
    insts = sorted(maps) if ns.all else (ns.inst or [0])
    src = open_source("local", product, install=ns.wow)
    sea_dir = os.path.join(ROOT, "Textures", "Sea", product)

    for inst in insts:
        tiles = maps[inst]
        out = os.path.join(ns.out, str(inst))
        os.makedirs(out, exist_ok=True)
        if not ns.sea_only:
            src.prefetch(tiles.values())
            for key, fdid in sorted(tiles.items()):
                img = blp_dxt(src.read(fdid))
                full = Image.frombytes("RGB", (img.width, img.height), img.rgb8())
                full.save(os.path.join(out, f"{key}.webp"), quality=QUALITY, method=6)
                for size in LODS:
                    os.makedirs(os.path.join(out, str(size)), exist_ok=True)
                    full.resize((size, size), Image.LANCZOS).save(
                        os.path.join(out, str(size), f"{key}.webp"), quality=QUALITY, method=6)
        n_sea = 0
        while os.path.exists(blp := os.path.join(sea_dir, f"{inst}_ocean{n_sea}.blp")):
            with open(blp, "rb") as f:
                img = blp_dxt(f.read())
            full = Image.frombytes("RGB", (img.width, img.height), img.rgb8())
            full.save(os.path.join(out, f"ocean{n_sea}.webp"), quality=QUALITY, method=6)
            for size in OCEAN_LODS:
                os.makedirs(os.path.join(out, str(size)), exist_ok=True)
                full.resize((size, size), Image.BOX).save(
                    os.path.join(out, str(size), f"ocean{n_sea}.webp"), quality=QUALITY, method=6)
            n_sea += 1
        tga = os.path.join(sea_dir, f"{inst}_tint.tga")
        if os.path.exists(tga):
            with open(tga, "rb") as f:
                w, h, rows = read_tga(f.read())
            Image.frombytes("RGB", (w, h), bytes(v for row in rows for p in row for v in p[:3])).save(
                os.path.join(out, "ocean_tint.png"))
        print(f"[{inst}] {len(tiles)} tiles, {n_sea} sea textures -> {out}", file=sys.stderr)


if __name__ == "__main__":
    main()

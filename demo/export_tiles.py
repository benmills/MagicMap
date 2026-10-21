#!/usr/bin/env python3
"""Export minimap tiles for the web demo.

For each map (instanceID) in Data/Tiles.lua, every tile's BLP is read from the
local install and written to demo/tiles/<inst>/<key>.webp (key = col * 64 + row).
Tiles are WebP (about a fifth of a PNG's size, so a phone gets sharp tiles
quickly); smaller Lanczos copies go to demo/tiles/<inst>/<size>/<key>.webp
(LODS), so a zoomed-out view doesn't download and hold 512px tiles it draws at
20px.

  .venv/bin/python demo/export_tiles.py                 # Eastern Kingdoms (0)
  .venv/bin/python demo/export_tiles.py --inst 0 --inst 1
  .venv/bin/python demo/export_tiles.py --all
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


LODS = (64, 128, 256)
QUALITY = 90


def read_tiles() -> tuple[str, dict[int, dict[int, int]]]:
    t = load_data(lua51.LuaRuntime(), os.path.join(ROOT, "Data", "Tiles.lua")).Data.Tiles
    maps = {int(inst): {int(k): int(v) for k, v in m.tiles.items()} for inst, m in t.maps.items()}
    return t.product, maps


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--inst", type=int, action="append", help="instanceID to export (repeatable; default 0)")
    ap.add_argument("--all", action="store_true", help="export every map in Data/Tiles.lua")
    ap.add_argument("--wow", default=os.environ.get("MAGICMAP_WOW", "/Applications/World of Warcraft"))
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "demo", "tiles"))
    ns = ap.parse_args()

    product, maps = read_tiles()
    insts = sorted(maps) if ns.all else (ns.inst or [0])
    src = open_source("local", product, install=ns.wow)

    for inst in insts:
        tiles = maps[inst]
        out = os.path.join(ns.out, str(inst))
        os.makedirs(out, exist_ok=True)
        src.prefetch(tiles.values())
        for key, fdid in sorted(tiles.items()):
            img = blp_dxt(src.read(fdid))
            full = Image.frombytes("RGB", (img.width, img.height), img.rgb8())
            full.save(os.path.join(out, f"{key}.webp"), quality=QUALITY, method=6)
            for size in LODS:
                os.makedirs(os.path.join(out, str(size)), exist_ok=True)
                full.resize((size, size), Image.LANCZOS).save(
                    os.path.join(out, str(size), f"{key}.webp"), quality=QUALITY, method=6)
        print(f"[{inst}] {len(tiles)} tiles -> {out}", file=sys.stderr)


if __name__ == "__main__":
    main()

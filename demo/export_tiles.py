#!/usr/bin/env python3
"""Export minimap tiles as PNGs for the web demo.

For each map (instanceID) in Data/Tiles.lua, every tile's BLP is read from the
local install and written to demo/tiles/<inst>/<key>.png (key = col * 64 + row),
and its water mask (Textures/Water/<product>/<inst>_<key>.tga, if any) to
demo/tiles/<inst>/water_<key>.png.

  .venv/bin/python demo/export_tiles.py                 # Eastern Kingdoms (0)
  .venv/bin/python demo/export_tiles.py --inst 0 --inst 1
  .venv/bin/python demo/export_tiles.py --all
"""
from __future__ import annotations

import argparse
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from lupa import LuaRuntime  # noqa: E402

from mmtools.formats import blp_dxt  # noqa: E402
from mmtools.sources import open_source  # noqa: E402
from mmtools.tga import read_tga  # noqa: E402


def png(w: int, h: int, pixels: bytes, channels: int) -> bytes:
    """An 8-bit RGB (channels 3) or RGBA (4) PNG of rows top first."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    stride = w * channels
    raw = b"".join(b"\0" + pixels[y * stride:(y + 1) * stride] for y in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2 if channels == 3 else 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")


def read_tiles() -> tuple[str, dict[int, dict[int, int]]]:
    lua = LuaRuntime()
    with open(os.path.join(ROOT, "Data", "Tiles.lua")) as f:
        lua.execute(f.read())
    t = lua.globals().MagicMap_Tiles
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
    water_dir = os.path.join(ROOT, "Textures", "Water", product)

    for inst in insts:
        tiles = maps[inst]
        out = os.path.join(ns.out, str(inst))
        os.makedirs(out, exist_ok=True)
        src.prefetch(tiles.values())
        n_water = 0
        for key, fdid in sorted(tiles.items()):
            img = blp_dxt(src.read(fdid))
            with open(os.path.join(out, f"{key}.png"), "wb") as f:
                f.write(png(img.width, img.height, img.rgb8(), 3))
            tga = os.path.join(water_dir, f"{inst}_{key}.tga")
            if os.path.exists(tga):
                with open(tga, "rb") as f:
                    w, h, rows = read_tga(f.read())
                with open(os.path.join(out, f"water_{key}.png"), "wb") as f:
                    f.write(png(w, h, bytes(v for row in rows for p in row for v in p), 4))
                n_water += 1
        print(f"[{inst}] {len(tiles)} tiles, {n_water} water masks -> {out}", file=sys.stderr)


if __name__ == "__main__":
    main()

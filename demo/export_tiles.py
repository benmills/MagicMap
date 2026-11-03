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
from concurrent.futures import ThreadPoolExecutor
import io
import json
from pathlib import Path
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from lupa import lua51  # noqa: E402

from PIL import Image  # noqa: E402

from mmtools.luaout import load_data  # noqa: E402
from mmtools.sources import open_source  # noqa: E402
from export_terrain import PinnedWagoSource  # noqa: E402


LODS = (64, 128, 256)
QUALITY = 90


def read_tiles() -> tuple[str, str, dict[int, dict[int, int]]]:
    t = load_data(lua51.LuaRuntime(), os.path.join(ROOT, "Data", "Tiles.lua")).Data.Tiles
    maps = {int(inst): {int(k): int(v) for k, v in m.tiles.items()} for inst, m in t.maps.items()}
    return t.product, t.version, maps


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--force',action='store_true')
    ap.add_argument('--source', choices=['local','wago'], default='local')
    ap.add_argument('--version', help='Required pinned build for wago')
    ap.add_argument('--jobs', type=int, default=6)
    ap.add_argument("--inst", type=int, action="append", help="instanceID to export (repeatable; default 0)")
    ap.add_argument("--all", action="store_true", help="export every map in Data/Tiles.lua")
    ap.add_argument("--wow", default=os.environ.get("MAGICMAP_WOW", "/Applications/World of Warcraft"))
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "demo", "tiles"))
    ns = ap.parse_args()

    product, version, maps = read_tiles()
    insts = sorted(maps) if ns.all else (ns.inst or [0])
    if ns.source == 'wago':
        if ns.version != version:
            ap.error(f'--version must match Atlas ({version})')
        src = PinnedWagoSource(product,version=version,cache_dir=str(Path(ROOT)/'.cache-assets'))
    else:
        src = open_source("local", product, install=ns.wow)
    if (src.product,src.version) != (product,version):
        ap.error(f'Source must match Atlas: {product} {version}')

    for inst in insts:
        tiles = maps[inst]
        out = os.path.join(ns.out, str(inst))
        os.makedirs(out, exist_ok=True)
        src.prefetch(tiles.values())
        same_build=False
        manifest=Path(out)/'manifest.json'
        if not ns.force and manifest.is_file():
            metadata=json.loads(manifest.read_text())
            same_build=(metadata.get('product'),metadata.get('version'))==(product,version)
        for size in LODS:
            os.makedirs(os.path.join(out,str(size)),exist_ok=True)
        def export(pair):
            key,fdid=pair
            files=[Path(out)/f'{key}.webp']+[Path(out)/str(n)/f'{key}.webp' for n in LODS]
            if same_build and all(p.is_file() for p in files):
                return True
            data=src.read(fdid)
            if data is None:
                return False
            full=Image.open(io.BytesIO(data)).convert('RGB')
            full.save(files[0],quality=QUALITY,method=4)
            for size,file in zip(LODS,files[1:]):
                full.resize((size,size),Image.Resampling.LANCZOS).save(file,quality=QUALITY,method=4)
            return True
        with ThreadPoolExecutor(max_workers=max(1,min(12,ns.jobs))) as pool:
            for n,ok in enumerate(pool.map(export,sorted(tiles.items())),1):
                if not ok:
                    print(f'[{inst}] unavailable tile at index {n}',file=sys.stderr)
                if n%64==0:
                    print(f'[{inst}] {n}/{len(tiles)}',flush=True)
        (Path(out)/'manifest.json').write_text(json.dumps(dict(product=product,version=version,inst=inst))+'\n')
        print(f"[{inst}] {len(tiles)} tiles -> {out}", file=sys.stderr)


if __name__ == "__main__":
    main()

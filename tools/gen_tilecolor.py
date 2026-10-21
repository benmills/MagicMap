#!/usr/bin/env python3
"""Generate Data/TileColor.lua: each map's open-sea tiles (sea[]), which the
runtime doesn't draw (Atlas.Drawn): the map's backdrop shows there instead.

The tile set is the one the addon ships (Data/Tiles.lua: its
version gates the output, and its FileDataIDs are the textures analysed); the
textures are read from the source by FileDataID. Without that file the maps
are read from the source's own Map.db2 / WDTs, as gen_tiles.py does.

  python3 tools/gen_tilecolor.py local "/Applications/World of Warcraft" wow_classic_beta \\
      -o Data/TileColor.lua

Each 512x512 DXT tile is reduced to its 128x128 block means (exact 4x4 box
filter, read off the DXT endpoints and index counts; no texel decode), then to
SEA_SIZE x SEA_SIZE. The minimap BLPs have no mipmaps, so there is no smaller
level to read. A tile is open sea when that image is the map's backdrop colour
all over (bar a flat frame or bracket some world-edge tiles have).
"""
from __future__ import annotations

import argparse
import os
import pickle
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass

from mmtools.formats import RGB, blp_dxt, box_downsample, wdt_maid
from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.maps import MAP_DB2, read_maps
from mmtools.sources import Source, add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SIDES = ("l", "r", "t", "b")
SEA_SIZE = 32         # px per tile the open-sea test looks at
SEA_DEV = 0.04        # a tile this close to the backdrop everywhere is open sea
FRAME = 0.1           # tiles: how deep flat frame stripes on an open-sea tile may be
FRAME_MAX = 0.5       # at most this share of an open-sea tile may be a one-colour bracket
FRAME_CONTRAST = 0.2  # ... whose colour is at least this far from the backdrop
WATER_BLUE = 0.06     # a colour this much bluer than red is water (blue or teal)


# --- the tile set ---------------------------------------------------------------

@dataclass
class MapTiles:
    inst: int
    name: str
    bg: RGB | None
    kind: str | None
    tiles: dict[int, int]   # key -> minimap FDID


def parse_tileset(path: str) -> tuple[str, str, list[MapTiles]]:
    """(product, version, maps) from a generated Data/Tiles.lua."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r'D\.Tiles = \{ product = "([^"]+)", version = "([^"]+)"', text)
    if not m:
        raise SystemExit(f"{path}: not a tile set")
    product, version = m.groups()
    maps = []
    head = re.compile(r'^  \[(\d+)\] = \{ name = "((?:[^"\\]|\\.)*)", bg = (nil|\{ ([\d.]+), ([\d.]+), ([\d.]+) \})'
                      r'(?:, kind = "(\w+)")?', re.M)
    starts = list(head.finditer(text))
    for i, h in enumerate(starts):
        body = text[h.end():starts[i + 1].start() if i + 1 < len(starts) else len(text)]
        tiles = {int(k): int(v) for k, v in re.findall(r"\[(\d+)\]=(\d+),", body)}
        bg = None if h.group(3) == "nil" else (float(h.group(4)), float(h.group(5)), float(h.group(6)))
        maps.append(MapTiles(int(h.group(1)), h.group(2), bg, h.group(7), tiles))
    return product, version, maps


def tileset_from_source(src: Source) -> list[MapTiles]:
    data = src.read(MAP_DB2)
    if data is None:
        raise SystemExit("Map.db2 not available and no tile set file")
    infos = read_maps(data)
    src.prefetch(m.wdt for m in infos)
    maps = []
    for m in infos:
        wdt = src.read(m.wdt)
        if wdt is None or wdt[:4] != b"REVM":
            continue
        tiles = {k: t.minimap for k, t in wdt_maid(wdt).items() if t.minimap}
        if tiles:
            maps.append(MapTiles(m.inst, m.name, None, m.kind, tiles))
    return maps


# --- per-tile analysis ----------------------------------------------------------

Image = list[list[RGB]]  # SEA_SIZE x SEA_SIZE


def median(values: list[float]) -> float:
    s = sorted(values)
    n = len(s)
    return (s[n // 2] + s[(n - 1) // 2]) / 2 if n else 0.0


def median_rgb(cs: list[RGB]) -> RGB:
    return tuple(median([c[k] for c in cs]) for k in range(3))


def analyse_tile(blp: bytes) -> Image | None:
    img = blp_dxt(blp)
    if img is None or img.blocks_wide != img.blocks_high:
        return None
    return box_downsample(img.block_means(), SEA_SIZE)


def _analyse(item: tuple[int, bytes | None]) -> tuple[int, Image | None]:
    fdid, blp = item
    return fdid, analyse_tile(blp) if blp is not None else None


def analyse_all(src: Source, fdids: set[int], cache_path: str | None, jobs: int) -> dict[int, Image]:
    cache: dict[int, Image | None] = {}
    if cache_path and os.path.exists(cache_path):
        with open(cache_path, "rb") as f:
            cache = pickle.load(f)
    todo = sorted(f for f in fdids if f not in cache)
    if todo:
        src.prefetch(todo)
        t0 = time.time()

        def items():
            for fdid in todo:
                yield fdid, src.read(fdid)

        if jobs > 1:
            with ProcessPoolExecutor(jobs) as pool:
                for fdid, data in pool.map(_analyse, items(), chunksize=16):
                    cache[fdid] = data
        else:
            for item in items():
                fdid, data = _analyse(item)
                cache[fdid] = data
        log(f"analysed {len(todo)} tiles in {time.time() - t0:.1f}s")
        if cache_path:
            with open(cache_path, "wb") as f:
                pickle.dump(cache, f)
    return {f: cache[f] for f in fdids if cache.get(f) is not None}


def near(c: RGB, bg: RGB | None, dev: float) -> bool:
    return bg is not None and all(abs(c[k] - bg[k]) <= dev for k in range(3))


def is_sea(img: Image, bg: RGB | None) -> bool:
    """Open sea: the backdrop colour all over, except perhaps a frame (some
    tiles at the edge of the world have one baked in: flat stripes along a
    side, FRAME tiles deep, or a bracket of one plain colour clearly unlike
    the sea). Frames are editor artefacts."""
    if bg is None:
        return False
    n = len(img)
    rest = [p for row in img for p in row if not near(p, bg, SEA_DEV)]
    if rest and len(rest) <= n * n * FRAME_MAX:  # a bracket
        c = median_rgb(rest)
        if not near(c, bg, FRAME_CONTRAST) and c[2] - c[0] <= WATER_BLUE and all(near(p, c, SEA_DEV) for p in rest):
            return True
    f = max(1, round(n * FRAME))
    if not all(near(p, bg, SEA_DEV) for row in img[f:n - f] for p in row[f:n - f]):
        return False
    for s in SIDES:
        for d in range(f):  # each line parallel to the side: flat (sea or frame)
            line = {"l": [row[d] for row in img[f:n - f]], "r": [row[n - 1 - d] for row in img[f:n - f]],
                    "t": img[d][f:n - f], "b": img[n - 1 - d][f:n - f]}[s]
            c = median_rgb(line)
            if not all(near(p, c, SEA_DEV) for p in line):
                return False
    return True


# --- output ---------------------------------------------------------------------

def write_tilecolor(out, product: str, version: str, results: list[tuple[MapTiles, set[int]]]) -> None:
    w = out.write
    w(f"-- GENERATED by tools/gen_tilecolor.py from the {product} {version} minimap tiles. Do not edit.\n")
    w("-- sea[key] = true: open-sea tiles, the backdrop colour all over (they need not be drawn)\n")
    w("-- key = col * 64 + row, as in Data/Tiles.lua\n")
    w(data_head("TileColor"))
    w("D.TileColor = D.TileColor or {}\n")
    for m, sea in results:
        name = m.name.replace("\n", " ")
        w(f"D.TileColor[{m.inst}] = {{ -- {name}\n")
        w("  sea = {\n")
        keys = sorted(sea)
        for i in range(0, len(keys), 10):
            w("    " + " ".join(f"[{k}]=true," for k in keys[i:i + 10]) + "\n")
        w("  },\n}\n")


# --- main -----------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    parser.add_argument("--tiles", metavar="FILE", help="tile set (default: Data/Tiles.lua if it exists)")
    parser.add_argument("--open-world", action="store_true", help="skip dungeons and raids")
    parser.add_argument("--cache", metavar="FILE", help="keep per-tile analysis in FILE between runs")
    parser.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    ns = parser.parse_args()
    t0 = time.time()
    src = source_from_args(parser, ns)

    tiles_path = ns.tiles or os.path.join(ROOT, "Data", "Tiles.lua")
    shipped = os.path.exists(tiles_path) and parse_tileset(tiles_path)
    if shipped and not ns.tiles and shipped[0] != src.product:
        shipped = None  # the addon's tile set is another product's: read this one's from the source
    if shipped:
        product, version, maps = shipped
        if product != src.product:
            raise SystemExit(f"{tiles_path} is for {product}, not {src.product}")
        if version != src.version:
            log(f"note: tile set {version}, textures read from {src.version} (by FileDataID)")
    else:
        product, version, maps = src.product, src.version, tileset_from_source(src)
    if ns.open_world:
        maps = [m for m in maps if not m.kind]

    data = analyse_all(src, {f for m in maps for f in m.tiles.values()}, ns.cache, ns.jobs)
    results = []
    for m in sorted(maps, key=lambda m: m.inst):
        tiles = {k: data[f] for k, f in m.tiles.items() if f in data}
        if not tiles:
            continue
        sea = {k for k, img in tiles.items() if is_sea(img, m.bg)}
        results.append((m, sea))
        log(f"[{m.inst}] {m.name}: {len(tiles)} tiles ({len(sea)} sea)")

    if ns.output:
        with open(ns.output, "w", encoding="utf-8", newline="\n") as f:
            write_tilecolor(f, product, version, results)
        log(f"wrote {ns.output}: {os.path.getsize(ns.output) // 1024} KB")
    else:
        write_tilecolor(sys.stdout, product, version, results)
    log(f"done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()

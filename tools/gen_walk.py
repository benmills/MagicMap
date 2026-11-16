#!/usr/bin/env python3
"""Generate Data/Walk.lua: where you can walk, for path mode's routes.

Each ADT terrain chunk (16x16 per tile, ~33 yards) is split into 8x8 quads
(~4 yards). A quad is too steep to walk up when its heights rise faster
than MAX_SLOPE, and deep where the liquid over it (MH2O) is deeper than
SWIM_DEPTH (you swim it, steep or not). Per chunk we keep:

  class: 0 blocked (no walkable part of MIN_PART quads), 1 land, 2 water (mostly
         deep), 3 harmful (magma or slime over much of it): all of it from the
         chunk's main walkable part, below
  east, south: whether you can cross into the chunk to the east / south (its main
         part meets the neighbour's main part along that edge)

A chunk's main walkable part is the run of walkable quads (not steep) that
touches the most of the chunk's edges, then the largest, then the first in
order. A narrow pass or a ramp counts as a part; a second part across a ridge
doesn't, so no route leaks through the ridge.

Buildings and bridges (WMOs) aren't terrain: cities and bridges over
chasms read as whatever is under them.

  python3 tools/gen_walk.py local "/Applications/World of Warcraft" wow_classic_beta \\
      -o Data/Walk.lua [--preview DIR]

Output is deterministic: the same game data always gives the same file.
"""
from __future__ import annotations

import argparse
import math
import os
import sys

from mmtools.db2 import read_wdc5
from mmtools.formats import adt_chunks, adt_liquids, wdt_maid
from mmtools.log import log
from mmtools.luaout import data_head, run_letters
from mmtools.maps import MAP_DB2, read_maps
from mmtools.sources import Source, add_source_args, source_from_args

LIQUIDTYPE_DB2 = 1371380  # dbfilesclient/liquidtype.db2
MAGMA_ID = 3               # LiquidType "Magma": its sound-bank-like column names the harmful kinds

QUAD = 100 / 3 / 8         # yards across a quad
MAX_SLOPE = math.tan(math.radians(60))  # steeper than this, you slide back down
SWIM_DEPTH = 1.5           # yards of liquid over the ground before you swim
MIN_PART = 4               # quads: a walkable part smaller than this (a 4-quad path, ~16 yards) isn't walked
MIN_CROSSINGS = 1          # of a chunk edge's 8 quads, this many where the two main parts meet make it passable
WATER_SHARE = 0.5          # the main part with more deep quads than this is water
HARMFUL_SHARE = 0.25       # ...with more magma/slime quads than this, harmful

BLOCKED, LAND, WATER, HARMFUL = 0, 1, 2, 3
EAST, SOUTH = 4, 8


def harmful_liquids(db2: bytes) -> set[int]:
    """LiquidType IDs of magma and slime: the column that's 0 water, 1 ocean,
    2 magma, 3 slime (found by content: Magma's row says 2)."""
    rows = read_wdc5(db2, string_fields={0})
    magma = next(r for r in rows if r[0] == MAGMA_ID)
    col = next(c for c in range(2, len(magma)) if magma[c] == 2 and not isinstance(magma[c], tuple))
    return {r[0] for r in rows if r[col] in (2, 3)}


def chunk_quads(ch, liquids, harmful: set[int]):
    """Per quad (qy * 8 + qx): 0 steep, 1 stand, 2 deep, 3 harmful."""
    z, h = ch.z, ch.heights
    out = bytearray(64)
    for qy in range(8):
        for qx in range(8):
            if h is None:
                a = b = c = d = m = z
            else:
                a, b = z + h[qy * 17 + qx], z + h[qy * 17 + qx + 1]
                c, d = z + h[(qy + 1) * 17 + qx], z + h[(qy + 1) * 17 + qx + 1]
                m = z + h[qy * 17 + 9 + qx]
            ground = (a + b + c + d + m) / 5
            kind = 1
            # The quad's mean slope (of the plane through its corners).
            gx, gy = (b + d - a - c) / (2 * QUAD), (c + d - a - b) / (2 * QUAD)
            if math.sqrt(gx * gx + gy * gy) > MAX_SLOPE:
                kind = 0
            for liq in liquids:
                if liq.covers(qx, qy) and liq.surface > ground:
                    if liq.liquid_type in harmful:
                        kind = 3
                        break
                    if liq.surface - ground > SWIM_DEPTH:
                        kind = 2
            out[qy * 8 + qx] = kind
    return out


def read_quads(src: Source, adts: dict[int, int], harmful: set[int]) -> dict[int, bytearray]:
    """{gc * 1024 + gr: quads} for every terrain chunk (gc, gr: global chunk column, row)."""
    quads = {}
    src.prefetch(adts.values())
    for key in sorted(adts):
        buf = src.read(adts[key])
        if buf is None:
            continue
        col, row = key // 64, key % 64
        liquids: dict[tuple[int, int], list] = {}
        for liq in adt_liquids(buf):
            liquids.setdefault((liq.ix, liq.iy), []).append(liq)
        for ch in adt_chunks(buf):
            quads[(col * 16 + ch.ix) * 1024 + row * 16 + ch.iy] = chunk_quads(ch, liquids.get((ch.ix, ch.iy), ()), harmful)
    return quads


def parts(q: bytearray) -> list[list[int]]:
    """The 4-connected runs of walkable quads (not steep) in a chunk, each a list of quad indices (qy * 8 + qx).
    Up/down/left/right only: a diagonal gap is a wall you can't step through."""
    seen = bytearray(64)
    out = []
    for start in range(64):
        if not q[start] or seen[start]:
            continue
        seen[start] = 1
        part, todo = [], [start]
        while todo:
            i = todo.pop()
            part.append(i)
            x, y = i % 8, i // 8
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < 8 and 0 <= ny < 8 and q[ny * 8 + nx] and not seen[ny * 8 + nx]:
                    seen[ny * 8 + nx] = 1
                    todo.append(ny * 8 + nx)
        out.append(part)
    return out


def edges_touched(part: list[int]) -> int:
    """How many of the chunk's 4 edges (N, S, W, E) the part reaches."""
    rows = {i // 8 for i in part}
    cols = {i % 8 for i in part}
    return (0 in rows) + (7 in rows) + (0 in cols) + (7 in cols)


def main_part(q: bytearray) -> list[int] | None:
    """The part that touches the most edges, then the largest, then the lowest first quad: the one a chunk's
    walking is about. A chunk's other parts are over a ridge or in a pocket. None if there's nothing walkable."""
    best = None
    for part in parts(q):
        key = (-edges_touched(part), -len(part), min(part))
        if best is None or key < best[0]:
            best = (key, part)
    return None if best is None else best[1]


def mask(part: list[int]) -> bytearray:
    m = bytearray(64)
    for i in part:
        m[i] = 1
    return m


def part_class(q: bytearray, part: list[int]) -> int:
    """The class of a chunk from its main part's quads: magma/slime, then deep water, else land."""
    if sum(1 for i in part if q[i] == 3) > len(part) * HARMFUL_SHARE:
        return HARMFUL
    if sum(1 for i in part if q[i] == 2) > len(part) * WATER_SHARE:
        return WATER
    return LAND


def classify(quads: dict[int, bytearray]) -> dict[int, int]:
    """{chunk: class | EAST | SOUTH}."""
    # Two passes: every chunk's main part first (a blocked chunk has none, so nothing crosses into or out of it),
    # then the crossings, which look at the neighbours' main parts.
    cls, mains = {}, {}
    for c, q in quads.items():
        part = main_part(q)
        if part is None or len(part) < MIN_PART:
            cls[c], mains[c] = BLOCKED, None
        else:
            cls[c], mains[c] = part_class(q, part), mask(part)
    cells = {}
    for c, m in mains.items():
        v = cls[c]
        if m is not None:
            east, south = mains.get(c + 1024), mains.get(c + 1)
            if east is not None and sum(m[i * 8 + 7] & east[i * 8] for i in range(8)) >= MIN_CROSSINGS:
                v |= EAST
            if south is not None and sum(m[56 + i] & south[i] for i in range(8)) >= MIN_CROSSINGS:
                v |= SOUTH
        cells[c] = v
    return cells


def encode_tile(cells: dict[int, int], col: int, row: int) -> str:
    """The tile's 256 chunks (iy * 16 + ix) as letters ('a' + value, 'a' where
    there's no chunk), runs written as the letter and a count: "n200b3n53"."""
    return run_letters([chr(97 + cells.get((col * 16 + i % 16) * 1024 + row * 16 + i // 16, 0)) for i in range(256)])


def write_preview(cells: dict[int, int], path: str) -> None:
    from PIL import Image  # only for --preview
    if not cells:
        return
    gcs = [c // 1024 for c in cells]
    grs = [c % 1024 for c in cells]
    x0, y0 = min(gcs), min(grs)
    s = 3
    img = Image.new("RGB", ((max(gcs) - x0 + 1) * s, (max(grs) - y0 + 1) * s), (0, 0, 0))
    px = img.load()
    colours = {BLOCKED: (70, 60, 55), LAND: (150, 170, 110), WATER: (60, 110, 190), HARMFUL: (220, 60, 30)}
    for c, v in cells.items():
        x, y = (c // 1024 - x0) * s, (c % 1024 - y0) * s
        col = colours[v & 3]
        for dx in range(s):
            for dy in range(s):
                px[x + dx, y + dy] = col
        if not v & EAST:
            for dy in range(s):
                px[x + s - 1, y + dy] = (0, 0, 0)
        if not v & SOUTH:
            for dx in range(s):
                px[x + dx, y + s - 1] = (0, 0, 0)
    img.save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    parser.add_argument("--preview", help="also write <dir>/walk_<map>.png (needs Pillow)")
    parser.add_argument("--min-tiles", type=int, default=20, help="skip maps with fewer terrain tiles (default 20)")
    ns = parser.parse_args()
    src = source_from_args(parser, ns)

    src.prefetch([MAP_DB2, LIQUIDTYPE_DB2])
    map_db2, liquid_db2 = src.read(MAP_DB2), src.read(LIQUIDTYPE_DB2)
    if map_db2 is None or liquid_db2 is None:
        raise SystemExit("Map.db2 / LiquidType.db2 not available")
    harmful = harmful_liquids(liquid_db2)
    maps = [m for m in read_maps(map_db2) if m.kind is None]
    src.prefetch(m.wdt for m in maps)

    out = open(ns.output, "w", encoding="utf-8", newline="\n") if ns.output else sys.stdout
    w = out.write
    w(f"-- GENERATED by tools/gen_walk.py from the {src.product} {src.version} terrain (ADT heights, MH2O liquids). Do not edit.\n")
    w("-- [inst][col * 64 + row] = the tile's 16x16 chunks (iy * 16 + ix), each a letter: 'a' + value, a run as the\n")
    w("--   letter and its length. value = class (0 blocked, 1 land, 2 water, 3 magma/slime; from the chunk's main walkable\n")
    w("--   part) + 4 (its main part meets the east chunk's main part) + 8 (the same to the south)\n")
    w(data_head("Walk"))
    w("D.Walk = {\n")
    for m in sorted(maps, key=lambda m: m.inst):
        wdt = src.read(m.wdt)
        if wdt is None:
            continue
        adts = {k: t.root_adt for k, t in wdt_maid(wdt).items() if t.root_adt}
        if len(adts) < ns.min_tiles:
            continue
        cells = classify(read_quads(src, adts, harmful))
        if not cells:
            continue
        counts = [sum(1 for v in cells.values() if v & 3 == k) for k in range(4)]
        log("%s: [%d] %s: %d chunks: %d blocked, %d land, %d water, %d harmful" % (
            src.product, m.inst, m.name, len(cells), *counts))
        name = m.name.replace("\n", " ")
        w(f"  [{m.inst}] = {{ -- {name}\n")
        for key in sorted(adts):
            w(f"    [{key}] = \"{encode_tile(cells, key // 64, key % 64)}\",\n")
        w("  },\n")
        if ns.preview:
            os.makedirs(ns.preview, exist_ok=True)
            write_preview(cells, os.path.join(ns.preview, f"walk_{m.inst}.png"))
    w("}\n")
    if out is not sys.stdout:
        out.close()


if __name__ == "__main__":
    main()

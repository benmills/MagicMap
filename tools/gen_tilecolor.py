#!/usr/bin/env python3
"""Generate Data/TileColor_<product>.lua: per-tile colour corrections so the
minimap tiles' baked lighting meets at their seams, and the colour along each
tile side that faces open space (no tile, or open sea), so the map can fade
out into its backdrop instead of ending in a hard rectangle.

The tile set is the one the addon ships (Data/Tiles_<product>.lua: its
version gates the output, and its FileDataIDs are the textures analysed); the
textures are read from the source by FileDataID. Without that file the maps
are read from the source's own Map.db2 / WDTs, as gen_tiles.py does.

  python3 tools/gen_tilecolor.py local "/Applications/World of Warcraft" wow_classic_beta \\
      -o Data/TileColor_wow_classic_beta.lua --preview /tmp/tilecolor
  python3 tools/gen_tilecolor.py wago wow_classic_era -o Data/TileColor_wow_classic_era.lua

With -o, the water masks go to Textures/Water/<product>/ beside the output's
folder (--water DIR to choose); that folder is the generator's: masks it no
longer produces are deleted.

How it works, per map:
  1. Each 512x512 DXT tile is reduced to its 128x128 block means (exact 4x4
     box filter, read off the DXT endpoints and index counts; no texel decode).
     The minimap BLPs have no mipmaps, so there is no smaller level to read.
  2. Open-sea tiles: the backdrop colour all over (bar a flat frame or
     bracket some world-edge tiles have). Listed in sea[]; everything below treats them as
     absent, so the runtime needn't draw them.
  3. Seams: along every edge shared by two other tiles, STRIP_SEGMENTS samples
     on each side, STRIP_DEPTH blocks deep, leaving out water samples (sea or
     blue/teal): baked water colour changes from tile to tile on its own
     (deep / shallow / lake shading) and no whole-tile tint can match it.
     A tint mismatch is a difference that is consistent all along the edge;
     terrain that just changes is not.
  4. Solve, per channel, drawn = texel * m + a (0 <= m <= 1, a >= 0) for every
     tile, minimising the seam differences (robust: Huber-weighted samples,
     each seam weighted by its share of usable samples) plus a sparse
     (reweighted L1) pull toward identity, so only outlier tiles move; a is
     penalised relative to the tile's brightness (an overlay is a big change on
     a dark tile). Tiles whose correction is under TINT_MIN are then pinned to
     identity and the rest refit with a weaker pull (REFIT, which takes out
     the L1 shrinkage), so what's written is self-consistent.
     Open-world maps only: instances get sea[] and edge[] but no tints.
  5. Shallow water: a 32x32 mask per tile of how much of the backdrop colour
     to lay over its water (see "shallow water" below), written as
     Textures/Water/<product>/<inst>_<key>.tga and listed in water[]. Tiles
     that come out as nothing but sea become sea[] instead. Open-world maps
     whose backdrop is open sea (they have sea tiles) only.
  6. Edge colours: per-channel median of the outer EDGE_DEPTH band (the
     runtime's inward feather) on each side facing open space (no tile or a
     sea tile), after the tint and the water overlay.

--preview DIR writes before/after PNGs and a seam heatmap per continent
(needs Pillow).
"""
from __future__ import annotations

import argparse
import math
import os
import pickle
import re
import sys
import time
from collections import deque
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from itertools import accumulate

from mmtools.formats import RGB, blp_dxt, box_downsample, wdt_maid
from mmtools.maps import MAP_DB2, read_maps
from mmtools.sources import Source, add_source_args, source_from_args
from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SIDES = ("l", "r", "t", "b")
NEIGHBOUR = {"l": -64, "r": 64, "t": -1, "b": 1}  # key = col * 64 + row
STRIP_SEGMENTS = 32   # samples along a tile edge (16 texels each; fewer on small textures)
STRIP_DEPTH = 2       # blocks (4 texels each) into the tile
EDGE_DEPTH = 0.08     # tiles: band the edge colour is taken from (= the runtime's inward feather);
                      # a median, so a thin frame line baked into some tiles' edges doesn't tint it
MIN_SAMPLES = 8       # fewer non-water samples than this along an edge: no seam
PREVIEW_SIZE = 32     # px per tile kept for previews

# Solver
REG_M = 0.02          # pull of m toward 1 (per unit of |m - 1|)
REG_A = 0.02          # pull of a toward 0, per unit of a / the tile's mean brightness
MIN_LEVEL = 0.05      # (floor for that brightness)
L1_EPS = 0.01         # reweighted-L1 smoothing: below this a move is ~quadratic
HUBER = 0.04          # sample residuals beyond this count linearly
OUTER_ITERS = 8
SWEEPS = 60
REFIT = 0.1           # pull kept (x REG_*) when refitting the chosen tiles
TINT_MIN = 0.02       # emit a tint if |m - 1| or a exceeds this in any channel

SEA_DEV = 0.04        # a tile this close to the backdrop everywhere is open sea
FRAME = 0.1           # tiles: how deep flat frame stripes on an open-sea tile may be
FRAME_MAX = 0.5       # at most this share of an open-sea tile may be a one-colour bracket
FRAME_CONTRAST = 0.2  # ... whose colour is at least this far from the backdrop
WATER_BLUE = 0.06     # a sample this much bluer than red is water (blue or teal)


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


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
    m = re.search(r'MagicMap_Tiles = \{ product = "([^"]+)", version = "([^"]+)"', text)
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

@dataclass
class TileData:
    strips: dict[str, list[RGB]]   # side -> STRIP_SEGMENTS samples along it
    outer: dict[str, RGB]          # side -> per-channel median of the band EDGE_DEPTH deep along it
    image: list[list[RGB]]         # PREVIEW_SIZE x PREVIEW_SIZE
    mean: RGB


def mean_rgb(cs) -> RGB:
    cs = list(cs)
    n = len(cs) or 1
    return (sum(c[0] for c in cs) / n, sum(c[1] for c in cs) / n, sum(c[2] for c in cs) / n)


def median_rgb(cs: list[RGB]) -> RGB:
    return tuple(median([c[k] for c in cs]) for k in range(3))


def side_blocks(grid: list[list[RGB]], side: str, depth: int, lo: int, hi: int) -> list[RGB]:
    """Blocks lo..hi-1 along a side, depth blocks in from it."""
    n = len(grid)
    if side == "l":
        return [grid[y][x] for y in range(lo, hi) for x in range(depth)]
    if side == "r":
        return [grid[y][x] for y in range(lo, hi) for x in range(n - depth, n)]
    if side == "t":
        return [grid[y][x] for y in range(depth) for x in range(lo, hi)]
    return [grid[y][x] for y in range(n - depth, n) for x in range(lo, hi)]


def analyse_tile(blp: bytes) -> TileData | None:
    img = blp_dxt(blp)
    if img is None or img.blocks_wide != img.blocks_high:
        return None
    n = img.blocks_wide
    segments = min(STRIP_SEGMENTS, n)
    if n % segments or n < STRIP_DEPTH:
        return None
    grid = img.block_means()
    seg = n // segments
    strips = {s: [mean_rgb(side_blocks(grid, s, STRIP_DEPTH, i * seg, i * seg + seg)) for i in range(segments)]
              for s in SIDES}
    outer = {s: median_rgb(side_blocks(grid, s, max(1, round(n * EDGE_DEPTH)), 0, n)) for s in SIDES}
    image = box_downsample(grid, PREVIEW_SIZE)
    return TileData(strips, outer, image, mean_rgb(c for row in image for c in row))


def _analyse(item: tuple[int, bytes | None]) -> tuple[int, TileData | None]:
    fdid, blp = item
    return fdid, analyse_tile(blp) if blp is not None else None


def analyse_all(src: Source, fdids: set[int], cache_path: str | None, jobs: int) -> dict[int, TileData]:
    cache: dict[int, TileData] = {}
    if cache_path and os.path.exists(cache_path):
        with open(cache_path, "rb") as f:  # plain dicts: loadable from any module
            cache = {k: TileData(**v) if v else None for k, v in pickle.load(f).items()}
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
                pickle.dump({k: vars(v) if v else None for k, v in cache.items()}, f)
    return {f: cache[f] for f in fdids if cache.get(f) is not None}


# --- seams ----------------------------------------------------------------------

@dataclass
class Seam:
    a: int                  # left / upper tile key
    b: int                  # right / lower tile key
    xa: list[RGB]           # a's strip along the shared edge
    xb: list[RGB]           # b's strip along it
    total: int = STRIP_SEGMENTS  # samples along the edge before leaving out water
    offset: RGB = (0.0, 0.0, 0.0)  # robust b - a
    score: float = 0.0


def near(c: RGB, bg: RGB | None, dev: float) -> bool:
    return bg is not None and all(abs(c[k] - bg[k]) <= dev for k in range(3))


def is_water(c: RGB, bg: RGB | None) -> bool:
    """Open-sea coloured, or blue: water, whose baked colour varies from tile
    to tile on its own (deep / shallow / lake shading), so it says nothing
    about a tile's tint."""
    return near(c, bg, SEA_DEV) or c[2] - c[0] > WATER_BLUE


def find_seams(tiles: dict[int, TileData], bg: RGB | None = None) -> list[Seam]:
    """Seams between the given tiles, from the samples where neither side is
    water (see is_water)."""
    seams = []
    for key in sorted(tiles):
        for side, other in (("r", "l"), ("b", "t")):
            nb = key + NEIGHBOUR[side]
            if nb not in tiles or (side == "b" and key % 64 == 63):
                continue
            pairs = [(a, b) for a, b in zip(tiles[key].strips[side], tiles[nb].strips[other])
                     if not is_water(a, bg) and not is_water(b, bg)]
            if len(pairs) < MIN_SAMPLES:
                continue
            s = Seam(key, nb, [a for a, _ in pairs], [b for _, b in pairs], len(tiles[key].strips[side]))
            s.offset, s.score = seam_offset(s.xa, s.xb)
            seams.append(s)
    return seams


def median(values: list[float]) -> float:
    s = sorted(values)
    n = len(s)
    return (s[n // 2] + s[(n - 1) // 2]) / 2 if n else 0.0


def seam_offset(xa: list[RGB], xb: list[RGB]) -> tuple[RGB, float]:
    """The consistent part of xb - xa: per channel the median difference,
    scaled down by how often samples disagree with its sign. The score is
    its length (0..~1.7)."""
    off = []
    for k in range(3):
        d = [b[k] - a[k] for a, b in zip(xa, xb)]
        med = median(d)
        agree = sum(1 for v in d if v * med > 0) / len(d) if med else 0.0
        off.append(med * max(0.0, 2 * agree - 1))
    return tuple(off), math.sqrt(sum(v * v for v in off))


# --- the solve ------------------------------------------------------------------

Tint = tuple[tuple[float, float, float], tuple[float, float, float]]  # (m, a)


def solve_box2(h11: float, h12: float, h22: float, g1: float, g2: float, mlo: float, mhi: float) -> tuple[float, float]:
    """argmin of 1/2 [m a] H [m a]^T - g . [m a] over mlo <= m <= mhi, a >= 0."""
    def val(m, a):
        return 0.5 * (h11 * m * m + 2 * h12 * m * a + h22 * a * a) - g1 * m - g2 * a

    cands = []
    det = h11 * h22 - h12 * h12
    if det > 1e-12:
        m = (g1 * h22 - g2 * h12) / det
        a = (h11 * g2 - h12 * g1) / det
        if mlo <= m <= mhi and a >= 0:
            return m, a
    for m in (mlo, mhi):  # m on a bound: best a
        cands.append((m, max(0.0, (g2 - h12 * m) / h22) if h22 > 0 else 0.0))
    if h11 > 0:  # a = 0: best m
        cands.append((min(mhi, max(mlo, g1 / h11)), 0.0))
    return min(cands, key=lambda c: val(*c))


def solve_channel(keys: list[int], seams: list[Seam], k: int, free: set[int],
                  level: dict[int, float], reg: float = 1.0) -> dict[int, tuple[float, float]]:
    """Per tile (m, a) for channel k. Tiles not in `free` stay at identity.
    `level`: each tile's mean brightness; a is penalised relative to it (an
    overlay that doubles a dark tile's brightness is a big change)."""
    m = {t: 1.0 for t in keys}
    a = {t: 0.0 for t in keys}
    xs = [([c[k] for c in s.xa], [c[k] for c in s.xb]) for s in seams]
    for _ in range(OUTER_ITERS):
        # Robust sample weights from the current residuals (each seam weighs 1
        # in total), reduced to the weighted sums its two tiles' 2x2 systems
        # need: W, A = sum w xa, B, AA, BB, AB.
        by_tile: dict[int, list[tuple[bool, int, tuple]]] = {t: [] for t in keys}
        for s, (xa, xb) in zip(seams, xs):
            ma, aa, mb, ab = m[s.a], a[s.a], m[s.b], a[s.b]
            w = []
            for va, vb in zip(xa, xb):
                r = abs(va * ma + aa - vb * mb - ab)
                w.append(1.0 if r <= HUBER else HUBER / r)
            n = sum(w)
            w = [v / n * len(xa) / s.total for v in w]  # a seam weighs its share of usable samples
            sums = (sum(w), sum(wi * x for wi, x in zip(w, xa)), sum(wi * y for wi, y in zip(w, xb)),
                    sum(wi * x * x for wi, x in zip(w, xa)), sum(wi * y * y for wi, y in zip(w, xb)),
                    sum(wi * x * y for wi, x, y in zip(w, xa, xb)))
            by_tile[s.a].append((True, s.b, sums))
            by_tile[s.b].append((False, s.a, sums))
        rm = {t: reg * REG_M / max(abs(m[t] - 1), L1_EPS) for t in keys}
        ra = {t: reg * REG_A / max(a[t], L1_EPS) / level[t] for t in keys}
        for _ in range(SWEEPS):
            delta = 0.0
            for t in keys:
                if t not in free:
                    continue
                h11, h12, h22, g1, g2 = rm[t], 0.0, ra[t], rm[t], 0.0
                for is_a, o, (sw, sa, sb, saa, sbb, sab) in by_tile[t]:
                    mo, ao = m[o], a[o]
                    own, other, own2 = (sa, sb, saa) if is_a else (sb, sa, sbb)
                    h11 += own2
                    h12 += own
                    h22 += sw
                    g1 += mo * sab + ao * own
                    g2 += mo * other + ao * sw
                nm, na = solve_box2(h11, h12, h22, g1, g2, 0.0, 1.0)
                delta = max(delta, abs(nm - m[t]), abs(na - a[t]))
                m[t], a[t] = nm, na
            if delta < 1e-5:
                break
    return {t: (m[t], a[t]) for t in keys}


def solve(tiles: dict[int, TileData], seams: list[Seam]) -> dict[int, Tint]:
    """Tints for the tiles that need one: a sparse solve picks the tiles,
    then a refit with only those free (and a weaker pull, REFIT) takes out
    the L1 shrinkage, so a clear outlier is corrected fully."""
    keys = sorted(tiles)
    level = {t: max(MIN_LEVEL, sum(tiles[t].mean) / 3) for t in keys}
    free = set(keys)
    for reg in (1.0, REFIT):
        per = [solve_channel(keys, seams, k, free, level, reg) for k in range(3)]
        tint = {t: (tuple(per[k][t][0] for k in range(3)), tuple(per[k][t][1] for k in range(3))) for t in keys}
        free = {t for t in free if needs_tint(tint[t])}
    return {t: tint[t] for t in keys if t in free}


def needs_tint(t: Tint) -> bool:
    return any(abs(v - 1) > TINT_MIN for v in t[0]) or any(v > TINT_MIN for v in t[1])


def apply_tint(c: RGB, t: Tint | None) -> RGB:
    if t is None:
        return c
    return tuple(min(1.0, c[k] * t[0][k] + t[1][k]) for k in range(3))


def edge_colors(land: dict[int, TileData], tint: dict[int, Tint], water: dict | None = None,
                bg: RGB | None = None) -> dict[int, dict[str, RGB]]:
    """Per tile, the colour of each side that faces open space: no tile, or
    a sea tile (which looks like the backdrop). Tiles with a water mask are
    sampled from their recoloured image."""
    out = {}
    for key, td in land.items():
        sides = {}
        img = recoloured(td, tint.get(key), water[key], bg) if water and key in water else None
        for s in SIDES:
            nb = key + NEIGHBOUR[s]
            wraps = (s == "t" and key % 64 == 0) or (s == "b" and key % 64 == 63)
            if not (wraps or nb not in land):
                continue
            if img:
                n = len(img)
                sides[s] = median_rgb(side_blocks(img, s, max(1, round(n * EDGE_DEPTH)), 0, n))
            else:
                sides[s] = apply_tint(td.outer[s], tint.get(key))
        if sides:
            out[key] = sides
    return out


def is_sea(td: TileData, bg: RGB | None) -> bool:
    """Open sea: the backdrop colour all over, except perhaps a frame (some
    tiles at the edge of the world have one baked in: flat stripes along a
    side, FRAME tiles deep, or a bracket of one plain colour clearly unlike
    the sea). Frames are editor artefacts; fading them out would glow."""
    if bg is None:
        return False
    img, n = td.image, len(td.image)
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


# --- shallow water ----------------------------------------------------------------
# Some tiles bake their water a light, shallow blue where the open sea next to
# them is the dark backdrop colour, so they show as blue rectangles. The fix is
# an overlay of the backdrop colour on that water: none near the shore (a thin
# shallow band stays), fading in to full over the open water. Only water that
# connects to open space (an absent or sea tile) counts, so lakes stay as they
# are. Computed per map on a grid at PREVIEW_SIZE px per tile (the tiles'
# 32x32 images), which is also the mask resolution: the fade is smooth enough
# that 32x32 looks the same as 128x128 once bilinear-filtered.

RAMP_BLURS = (4, 4, 3)  # box blur radii (px): ~ a Gaussian of 4 px (0.13 tile) off the shore
KEEP_GAIN = 3.0         # untouched where the blurred land share is >= 1/3
MASK_MIN = 8 / 255      # tiles whose pixels are all covered less than this need no mask
MASK_EFFECT = 0.02      # ... nor those where it changes no pixel's colour by more than this
SEA_MIN_TILES = 4       # maps get water masks only if they have this many sea tiles
SEA_MIN_SHARE = 0.05    # ... and at least this share of their tiles is sea


def box_blur(a: list[float], w: int, h: int, r: int, horizontal: bool) -> list[float]:
    """One box blur pass of radius r along rows or columns, renormalised at
    the borders."""
    out = [0.0] * (w * h)
    lines, length = (h, w) if horizontal else (w, h)
    for i in range(lines):
        idx = range(i * w, i * w + w) if horizontal else range(i, w * h, w)
        pre = [0.0]
        pre.extend(accumulate(a[j] for j in idx))
        for x, j in enumerate(idx):
            lo, hi = max(0, x - r), min(length, x + r + 1)
            out[j] = (pre[hi] - pre[lo]) / (hi - lo)
    return out


def water_alpha(tiles: dict[int, TileData], sea: set[int], tint: dict[int, Tint],
                bg: RGB | None) -> dict[int, list[list[float]]]:
    """For each non-sea tile, PREVIEW_SIZE rows of how much of the backdrop
    colour to lay over each pixel (0..1). Tiles with no such water are left out."""
    land = [k for k in tiles if k not in sea]
    if not land or bg is None:
        return {}
    n = PREVIEW_SIZE
    c0, c1 = min(k // 64 for k in land) - 1, max(k // 64 for k in land) + 1
    r0, r1 = min(k % 64 for k in land) - 1, max(k % 64 for k in land) + 1
    w, h = (c1 - c0 + 1) * n, (r1 - r0 + 1) * n
    water = bytearray(w * h)
    seen = bytearray(w * h)
    queue = deque()
    for c in range(c0, c1 + 1):
        for r in range(r0, r1 + 1):
            key = c * 64 + r
            is_tile = 0 <= c < 64 and 0 <= r < 64 and key in tiles and key not in sea
            for y in range(n):
                base = ((r - r0) * n + y) * w + (c - c0) * n
                if not is_tile:  # open space: water, and where the flood starts
                    for i in range(base, base + n):
                        water[i] = seen[i] = 1
                        queue.append(i)
                    continue
                row, t = tiles[key].image[y], tint.get(key)
                for x in range(n):
                    if is_water(apply_tint(row[x], t), bg):
                        water[base + x] = 1
    while queue:  # water connected to open space
        i = queue.popleft()
        x = i % w
        for j in (i - w, i + w, i - 1 if x else -1, i + 1 if x + 1 < w else -1):
            if 0 <= j < w * h and water[j] and not seen[j]:
                seen[j] = 1
                queue.append(j)
    near = [0.0 if v else 1.0 for v in seen]  # land (anything not open water)
    for rad in RAMP_BLURS:
        near = box_blur(near, w, h, rad, True)
    for rad in RAMP_BLURS:
        near = box_blur(near, w, h, rad, False)
    out = {}
    for key in land:
        ox, oy = (key // 64 - c0) * n, (key % 64 - r0) * n
        rows = [[seen[(oy + y) * w + ox + x] * max(0.0, 1 - KEEP_GAIN * near[(oy + y) * w + ox + x])
                 for x in range(n)] for y in range(n)]
        if max(max(row) for row in rows) > MASK_MIN:
            out[key] = rows
    return out


def recoloured(td: TileData, t: Tint | None, alpha: list[list[float]] | None, bg: RGB) -> list[list[RGB]]:
    """The tile's PREVIEW_SIZE image as drawn: tint, then the water overlay."""
    rows = []
    for y, row in enumerate(td.image):
        out = []
        for x, c in enumerate(row):
            c = apply_tint(c, t)
            if alpha:
                a = alpha[y][x]
                c = tuple(c[k] * (1 - a) + bg[k] * a for k in range(3))
            out.append(c)
        rows.append(out)
    return rows


def write_masks(directory: str, results: list[MapResult]) -> int:
    """Textures/Water/<product>/<inst>_<key>.tga for every tile with a water
    mask: white, alpha = sea-colour coverage. Masks no longer produced are
    deleted. Returns the bytes written."""
    os.makedirs(directory, exist_ok=True)
    wanted, size = set(), 0
    for r in results:
        for key, alpha in r.water.items():
            name = f"{r.map.inst}_{key}.tga"
            wanted.add(name)
            data = write_tga(len(alpha[0]), len(alpha), [[(255, 255, 255, int(a * 255 + 0.5)) for a in row]
                                                          for row in alpha])
            size += len(data)
            path = os.path.join(directory, name)
            if not os.path.exists(path) or open(path, "rb").read() != data:
                with open(path, "wb") as f:
                    f.write(data)
    for name in os.listdir(directory):
        if re.fullmatch(r"\d+_\d+\.tga", name) and name not in wanted:
            os.remove(os.path.join(directory, name))
    return size


# --- per map ------------------------------------------------------------------

@dataclass
class MapResult:
    map: MapTiles
    tiles: dict[int, TileData]       # every tile analysed
    sea: set[int]                    # open-sea tiles (look like the backdrop)
    seams: list[Seam]                # between non-sea tiles
    tint: dict[int, Tint]
    edges: dict[int, dict[str, RGB]]
    water: dict[int, list[list[float]]]  # tile -> its water mask (sea-colour coverage)


def process_map(m: MapTiles, data: dict[int, TileData]) -> MapResult:
    tiles = {k: data[f] for k, f in m.tiles.items() if f in data}
    sea = {k for k, td in tiles.items() if is_sea(td, m.bg)}
    land = {k: td for k, td in tiles.items() if k not in sea}
    seams = find_seams(land, m.bg)
    # Instances: tints and water unverified (often odd art); edges only.
    tint = solve(land, seams) if seams and not m.kind else {}
    # Water only where the backdrop is open sea (maps with sea tiles), not on
    # map fragments whose backdrop is a land colour.
    seaside = not m.kind and len(sea) >= max(SEA_MIN_TILES, SEA_MIN_SHARE * len(tiles))
    water, full = {}, set()
    for k, a in (water_alpha(tiles, sea, tint, m.bg) if seaside else {}).items():
        img = recoloured(tiles[k], tint.get(k), a, m.bg)
        if all(near(p, m.bg, SEA_DEV) for row in img for p in row):
            full.add(k)  # nothing left but sea
        elif max(a[y][x] * max(abs(tiles[k].image[y][x][c] - m.bg[c]) for c in range(3))
                 for y in range(len(a)) for x in range(len(a))) > MASK_EFFECT:
            water[k] = a
    sea |= full
    land = {k: td for k, td in land.items() if k not in full}
    tint = {k: t for k, t in tint.items() if k not in full}
    return MapResult(m, tiles, sea, seams, tint, edge_colors(land, tint, water, m.bg), water)


# --- output ---------------------------------------------------------------------

def rgb_lua(c: RGB) -> str:
    return "{ %.3f, %.3f, %.3f }" % c


def write_tilecolor(out, product: str, version: str, results: list[MapResult]) -> None:
    w = out.write
    w(f"-- GENERATED by tools/gen_tilecolor.py from the {product} {version} minimap tiles. Do not edit.\n")
    w("-- tint[key] = { mr, mg, mb, ar, ag, ab }: drawn colour = texel * m + a (0 <= m <= 1, a >= 0); only tiles that need it\n")
    w("-- edge[key] = { l = {r,g,b}, r = ..., t = ..., b = ... }: mean colour of the outer texels on sides facing an absent tile (after tint)\n")
    w("-- sea[key] = true: open-sea tiles, the backdrop colour all over; edge[] treats them as absent (they need not be drawn)\n")
    w("-- water[key] = true: the tile has a 32x32 mask waterDir .. inst .. \"_\" .. key .. \".tga\" (white, alpha = how much of\n")
    w("--   the backdrop colour covers it) to draw over the whole tile with the vertex colour bg: recolours shallow water\n")
    w("--   toward the open sea; edge[] colours are taken after it\n")
    w("-- key = col * 64 + row, as in Data/Tiles.lua\n")
    w("MagicMap_TileColor = MagicMap_TileColor or {}\n")
    for r in results:
        name = r.map.name.replace("\n", " ")
        w(f"MagicMap_TileColor[{r.map.inst}] = {{ -- {name}\n")
        w("  tint = {\n")
        for key in sorted(r.tint):
            (mr, mg, mb), (ar, ag, ab) = r.tint[key]
            w("    [%d] = { %.3f, %.3f, %.3f, %.3f, %.3f, %.3f },\n" % (key, mr, mg, mb, ar, ag, ab))
        w("  },\n  edge = {\n")
        for key in sorted(r.edges):
            parts = ", ".join(f"{s} = {rgb_lua(r.edges[key][s])}" for s in SIDES if s in r.edges[key])
            w(f"    [{key}] = {{ {parts} }},\n")
        for name, keys in (("sea", sorted(r.sea)), ("water", sorted(r.water))):
            w(f"  }},\n  {name} = {{\n")
            for i in range(0, len(keys), 10):
                w("    " + " ".join(f"[{k}]=true," for k in keys[i:i + 10]) + "\n")
        w("  },\n")
        w(f"  waterDir = \"Interface\\\\AddOns\\\\MagicMap\\\\Textures\\\\Water\\\\{product}\\\\\",\n")
        w("}\n")


# --- previews -------------------------------------------------------------------
# The runtime's edge model: from each open side a strip FADE tiles outward,
# side colour to transparent over the backdrop; FEATHER tiles inward, the
# texels blend into the side colour; at a convex corner (two open sides) the
# mean of the two side colours at alpha (1-u)(1-v).

FADE = 0.6
FEATHER = 0.08


def to8(c) -> tuple[int, int, int]:
    return tuple(int(min(1.0, max(0.0, v)) * 255 + 0.5) for v in c)


def render_map(r: MapResult, px: int, after: bool):
    """The map as the addon would draw it: tiles at px each on the backdrop;
    `after`: tinted, water recoloured, sea tiles left out and the edge model
    applied."""
    from PIL import Image
    bg = r.map.bg or (0.0, 0.0, 0.0)
    cols = [k // 64 for k in r.tiles]
    rows = [k % 64 for k in r.tiles]
    c0, r0 = min(cols) - 1, min(rows) - 1
    wc, hc = max(cols) - c0 + 2, max(rows) - r0 + 2
    W, H = wc * px, hc * px
    buf = [[bg] * W for _ in range(H)]
    for key, td in r.tiles.items():
        if after and key in r.sea:
            continue
        ox, oy = (key // 64 - c0) * px, (key % 64 - r0) * px
        img = recoloured(td, r.tint.get(key), r.water.get(key), bg) if after else td.image
        f = len(img) / px
        for y in range(px):
            src_row = img[int(y * f)]
            for x in range(px):
                buf[oy + y][ox + x] = src_row[int(x * f)]
    if after:
        def blend(x, y, c, al):
            if 0 <= x < W and 0 <= y < H and al > 0:
                o = buf[y][x]
                buf[y][x] = tuple(o[k] * (1 - al) + c[k] * al for k in range(3))

        reach, feather = FADE * px, max(1.0, FEATHER * px)
        for key, sides in r.edges.items():
            ox, oy = (key // 64 - c0) * px, (key % 64 - r0) * px
            for s, c in sides.items():
                for d in range(int(feather)):  # inward feather
                    al = 1 - (d + 0.5) / feather
                    for i in range(px):
                        x, y = {"l": (ox + d, oy + i), "r": (ox + px - 1 - d, oy + i),
                                "t": (ox + i, oy + d), "b": (ox + i, oy + px - 1 - d)}[s]
                        blend(x, y, c, al)
                for d in range(int(reach) + 1):  # outward strip
                    al = 1 - (d + 0.5) / reach
                    for i in range(px):
                        x, y = {"l": (ox - 1 - d, oy + i), "r": (ox + px + d, oy + i),
                                "t": (ox + i, oy - 1 - d), "b": (ox + i, oy + px + d)}[s]
                        blend(x, y, c, al)
            for sv, sh in (("t", "l"), ("t", "r"), ("b", "l"), ("b", "r")):  # convex corners
                if sv in sides and sh in sides:
                    c = mean_rgb((sides[sv], sides[sh]))
                    for dy in range(int(reach) + 1):
                        for dx in range(int(reach) + 1):
                            al = max(0.0, 1 - (dx + 0.5) / reach) * max(0.0, 1 - (dy + 0.5) / reach)
                            x = ox - 1 - dx if sh == "l" else ox + px + dx
                            y = oy - 1 - dy if sv == "t" else oy + px + dy
                            blend(x, y, c, al)
    img = Image.new("RGB", (W, H))
    img.putdata([to8(c) for row in buf for c in row])
    return img


def render_seams(r: MapResult, px: int):
    """Seam heatmap: the map darkened, each seam a bar coloured by its score
    (yellow..red), tinted tiles outlined in cyan, sea tiles in dark blue."""
    from PIL import Image, ImageDraw
    base = Image.eval(render_map(r, px, False), lambda v: v // 3)
    d = ImageDraw.Draw(base)
    c0 = min(k // 64 for k in r.tiles) - 1
    r0 = min(k % 64 for k in r.tiles) - 1

    def origin(key):
        return (key // 64 - c0) * px, (key % 64 - r0) * px

    for key in r.sea:
        ox, oy = origin(key)
        d.rectangle([ox + 1, oy + 1, ox + px - 2, oy + px - 2], outline=(20, 40, 110))
    for key in r.tint:
        ox, oy = origin(key)
        d.rectangle([ox + 2, oy + 2, ox + px - 3, oy + px - 3], outline=(0, 200, 255))
    for s in r.seams:
        v = min(1.0, s.score / 0.12)
        if v < 0.15:
            continue
        colour = (255, int(255 * (1 - v)), 0)
        ax, ay = origin(s.a)
        wdt = max(1, int(1 + 4 * v))
        if s.b == s.a + 64:
            d.rectangle([ax + px - wdt, ay + 2, ax + px + wdt - 1, ay + px - 3], fill=colour)
        else:
            d.rectangle([ax + 2, ay + px - wdt, ax + px - 3, ay + px + wdt - 1], fill=colour)
    return base


# --- main -----------------------------------------------------------------------

def tile_name(key: int) -> str:
    return f"{key // 64}_{key % 64}"


def wrapping_edges(r: MapResult) -> list[int]:
    """Edge tiles on row 0/63 or col 0/63, where plain key offsets wrap."""
    return [k for k in r.edges if k % 64 in (0, 63) or k // 64 in (0, 63)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    parser.add_argument("--tiles", metavar="FILE", help="tile set (default: Data/Tiles.lua if it exists)")
    parser.add_argument("--open-world", action="store_true", help="skip dungeons and raids")
    parser.add_argument("--preview", metavar="DIR", help="write before/after/seam PNGs of the continents here")
    parser.add_argument("--preview-px", type=int, default=16, help="preview pixels per tile (default 16)")
    parser.add_argument("--water", metavar="DIR", help="water masks folder (default with -o: "
                        "<output's folder>/../Textures/Water/<product>; without -o: none written)")
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
    t1 = time.time()
    results = []
    for m in sorted(maps, key=lambda m: m.inst):
        r = process_map(m, data)
        if not r.tiles:
            continue
        results.append(r)
        worst = sorted(r.seams, key=lambda s: -s.score)[:5]
        log(f"[{m.inst}] {m.name}: {len(r.tiles)} tiles ({len(r.sea)} sea), {len(r.seams)} seams, "
            f"{len(r.tint)} tinted, {len(r.water)} water masks, {len(r.edges)} with open sides; worst seams: "
            + ", ".join(f"{tile_name(s.a)}|{tile_name(s.b)} {s.score:.3f}" for s in worst))
        wrap = wrapping_edges(r)
        if wrap:
            log(f"  note: edge data on row/col 0 or 63: {', '.join(tile_name(k) for k in wrap)}")
        if ns.preview and not m.kind and len(r.tiles) >= 100:
            os.makedirs(ns.preview, exist_ok=True)
            stem = os.path.join(ns.preview, re.sub(r"\W+", "_", m.name).strip("_"))
            render_map(r, ns.preview_px, False).save(stem + "_before.png")
            render_map(r, ns.preview_px, True).save(stem + "_after.png")
            render_seams(r, ns.preview_px).save(stem + "_seams.png")
    log(f"solved in {time.time() - t1:.1f}s")

    if ns.output:
        with open(ns.output, "w", encoding="utf-8", newline="\n") as f:
            write_tilecolor(f, product, version, results)
        log(f"wrote {ns.output}: {os.path.getsize(ns.output) // 1024} KB")
    water = ns.water or (ns.output and os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(ns.output))),
                                                     "Textures", "Water", product))
    if water:
        size = write_masks(water, results)
        log(f"wrote {sum(len(r.water) for r in results)} water masks to {water}: {size // 1024} KB")
    else:
        write_tilecolor(sys.stdout, product, version, results)
    log(f"done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()

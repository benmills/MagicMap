#!/usr/bin/env python3
"""Generate Data/Sea.lua and its textures: the open sea beyond the minimap
tiles, continuing the tiles' own painted water instead of replacing it.

The tiles' art is drawn as it is (water included); where there is no tile to
draw (none in the WDT, or an open-sea tile: Data/TileColor.lua sea[], the
art's flat deep water) the map shows the ocean, and the coast tiles' sides
that face it fade into it. Per open-world map with at least MIN_OPEN open-sea
tiles and ocean in its terrain, written to Textures/Sea/<product>/ (beside the output's folder, or
--textures DIR; the folder is the generator's: files it no longer makes are
deleted):

  <inst>_ocean<v>.blp  VARIANTS seamlessly tiling SIZE x SIZE grey textures
      (DXT1 BLP2, full mip chain), one repeat per map tile: the art's water
      texture, as brightness around GAIN. Synthesised from the map's own
      water: windows of the art WINDOW px square over ocean SAMPLE_DEPTH yards
      deep (MH2O "Ocean" liquid over the ADT's MCVT ground, as gen_walk reads
      it), rocks and wrecks opened away (OPEN_PX / CLOSE_PX), band-passed
      (BAND_LO..BAND_HI px) as brightness relative to the surroundings, then
      overlap-added at random places, flips and turns on a torus with a
      variance-keeping blend (so the result is seamless and as contrasty as the
      art), soft-clipped at CLIP standard deviations. (The art's deep sea is a
      flat colour: its only texture is the seabed showing through.) Every
      variant equals variant 0 within BORDER tiles of its edges, so any two
      sit side by side without a seam.
  <inst>_tint.tga  the sea's colour as multipliers of the texture (colour /
      GAIN), TINT_PX px per tile (then stretched to power-of-two sides, as WoW
      wants) over the map's tiles and MARGIN tiles around
      (bilinear-filtered, it is smooth): along each coast side facing the sea,
      the art's own water there (the median of the outer FEATHER band, by
      segment, after Data/TileColor.lua's tint; water = ocean in the terrain),
      fading within about a tile (NEAR) to the art's open-sea colour (the median
      of the open-sea tiles), which darkens by DARKEN beyond FAR tiles from any
      tile and varies by NOISE over NOISE_TILES (none at the border, so a
      clamped texture continues it).
  feather_<code>.tga  MASK_PX square alpha masks (white) for the coast tiles'
      art: 0 at each side that faces the sea, smoothstep to 1 over FEATHER of
      a tile; code bits 1 l, 2 r, 4 t, 8 b, and 16 tl, 32 tr, 64 bl, 128 br
      for a corner that touches the sea only diagonally (cut round).

How the addon draws it (WoW textures only; see demo/tiles.js):
  1. per sea cell in view (a map tile with no art, or a coast tile, or any
     cell off the tiles): <inst>_ocean<v>.blp, v = Atlas.SeaVariant(col, row)
     (any v fits beside any other), SetTexCoord the whole texture: world-
     anchored, one repeat per tile.
  2. over them, one texture filling the view: variant 0 with
     SetTexture(path, "REPEAT", "REPEAT") and SetTexCoord scaled by the zoom to
     one repeat per MACRO tiles, turned a quarter, at alpha MACRO_ALPHA: the
     repeat stops lining up with the cells.
  3. the tint map over the same area with SetBlendMode("MOD") and SetTexCoord
     for the view (default CLAMP: beyond it the border, the open-sea colour).
  4. the tiles' art; on a coast tile AddMaskTexture(feather_<code>.tga).

  .venv/bin/python tools/gen_sea.py local "/Applications/World of Warcraft" wow_classic_beta \\
      -o Data/Sea.lua [--preview DIR]

Needs Pillow. Run after gen_tiles.py and gen_tilecolor.py. Output is deterministic.
"""
from __future__ import annotations

import argparse
import math
import os
import random
import re
import struct
import sys
import time
from array import array
from concurrent.futures import ProcessPoolExecutor

from PIL import Image, ImageFilter

from gen_tilecolor import ROOT, parse_tileset
from mmtools.db2 import read_wdc5
from mmtools.formats import adt_chunks, adt_liquids, blp_dxt, wdt_maid
from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.maps import MAP_DB2, read_maps
from mmtools.sources import add_source_args, source_from_args
from mmtools.tga import write_tga

LIQUIDTYPE_DB2 = 1371380  # dbfilesclient/liquidtype.db2

QUADS = 128          # terrain quads per tile side (8 per chunk), ~4 yd each; art px = 4 per quad
MIN_OPEN = 4         # maps with fewer open-sea tiles have no sea (lakes on map fragments)

# The texture
SIZE = 256           # px per repeat (= per tile) in the addon's textures
SYNTH = 512          # px it is made at (the art's own scale)
VARIANTS = 4
GAIN = 0.6           # the texture's mean brightness (the tint map scales it to the sea's colour)
WINDOW = 128         # art px: sample windows
SAMPLE_DEPTH = (6.0, 45.0)  # yards: windows wholly over ocean this deep (the seabed shows, softly)
PER_TILE = 4         # windows per tile at most
OPEN_PX, CLOSE_PX = 13, 9   # art px: morphological opening / closing (rocks, wrecks, holes out)
BAND_LO, BAND_HI = 3.0, 32.0  # art px: Gaussian sigmas of the band kept (no DXT steps, no slope)
RANGE_MAX = 0.6      # windows whose band strays further than this (relative) are dropped
PATCH_STEP, PATCH_JITTER = 40, 12  # art px: patch centres on the torus
CLIP = 2.0           # soft clip (tanh) at this many standard deviations
BORDER = 0.125       # tiles: every variant is variant 0 this near its edges (then a smoothstep as far again)
SEED = 1

# The tint map
TINT_PX = 4          # px per tile
MARGIN = 8           # tiles around the map's tiles
NEAR = 0.3           # tiles: Gaussian sigma of the coast colours' spread (the shelf drops off within ~1 tile)
NEAR_EPS = 0.01      # ... and the open-sea colour's weight against it (sets how far it reaches)
DARKEN = 0.08        # the open sea this much darker ...
FAR = (1.0, 5.0)     # ... going from this far from any tile to this far (tiles; smoothstep)
NOISE, NOISE_TILES = 0.05, 3.0  # low-frequency brightness variation over the open sea

# The coast
FEATHER = 0.15       # tiles: the art fades to the sea over this much of a coast tile
MASK_PX = 64
SIDE_BITS = {"l": 1, "r": 2, "t": 4, "b": 8}
NEIGHBOUR = {"l": -64, "r": 64, "t": -1, "b": 1}  # key = col * 64 + row
CORNERS = (("tl", 16, "t", "l", -65), ("tr", 32, "t", "r", 63), ("bl", 64, "b", "l", -63), ("br", 128, "b", "r", 65))


def ocean_types(db2: bytes) -> set[int]:
    """LiquidType IDs that are ocean, by name ("Ocean", "Slow Ocean",
    "PBRWater - Generic - Ocean", ...): newer ones aren't in the ocean category."""
    return {r[0] for r in read_wdc5(db2, string_fields={0}) if isinstance(r[1], str) and "Ocean" in r[1]}


def depths(adt: bytes, ocean: set[int]) -> list[float] | None:
    """Per quad (QUADS * QUADS, row-major) the ocean's depth over the ground,
    0 where there is none; None without ocean."""
    liquids: dict[tuple[int, int], list] = {}
    for liq in adt_liquids(adt):
        if liq.liquid_type in ocean:
            liquids.setdefault((liq.ix, liq.iy), []).append(liq)
    if not liquids:
        return None
    d = [0.0] * (QUADS * QUADS)
    for ch in adt_chunks(adt):
        layers = liquids.get((ch.ix, ch.iy))
        if not layers:
            continue
        z, h = ch.z, ch.heights
        for qy in range(8):
            for qx in range(8):
                over = [liq.surface for liq in layers if liq.covers(qx, qy)]
                if not over:
                    continue
                ground = z if h is None else z + (h[qy * 17 + qx] + h[qy * 17 + qx + 1] + h[(qy + 1) * 17 + qx]
                                                  + h[(qy + 1) * 17 + qx + 1] + h[qy * 17 + 9 + qx]) / 5
                d[(ch.iy * 8 + qy) * QUADS + ch.ix * 8 + qx] = max(0.0, max(over) - ground)
    return d


def windows(d: list[float]) -> list[tuple[int, int]]:
    """Quad origins of WINDOW-px windows wholly over ocean SAMPLE_DEPTH deep,
    at most PER_TILE, spread out."""
    w, lo, hi = WINDOW // 4, *SAMPLE_DEPTH
    sat = [[0] * (QUADS + 1) for _ in range(QUADS + 1)]
    for y in range(QUADS):
        run = 0
        for x in range(QUADS):
            run += lo <= d[y * QUADS + x] <= hi
            sat[y + 1][x + 1] = sat[y][x + 1] + run
    out = []
    for qy in range(0, QUADS - w + 1, 8):
        for qx in range(0, QUADS - w + 1, 8):
            if (sat[qy + w][qx + w] - sat[qy][qx + w] - sat[qy + w][qx] + sat[qy][qx] == w * w
                    and all(abs(qx - x) >= w or abs(qy - y) >= w for x, y in out)):
                out.append((qx, qy))
    return out[:PER_TILE]


def band(art: Image.Image) -> array | None:
    """A window's brightness relative to its surroundings (0 = as they are),
    rocks and wrecks opened away; None if it strays too far (built over)."""
    m = [sum(b) / len(b) for b in (list(c.getdata()) for c in art.split())]
    if m[2] > m[1] or m[0] > m[1]:
        return None  # blue (another water style) or red (wood, sand): not this sea
    up = art.convert("L").point(lambda v: min(255, v * 4))  # the water is dark: room for the blurs
    up = (up.filter(ImageFilter.MinFilter(OPEN_PX)).filter(ImageFilter.MaxFilter(OPEN_PX))
          .filter(ImageFilter.MaxFilter(CLOSE_PX)).filter(ImageFilter.MinFilter(CLOSE_PX)))
    a = up.filter(ImageFilter.GaussianBlur(BAND_LO)).tobytes()
    b = up.filter(ImageFilter.GaussianBlur(BAND_HI)).tobytes()
    r = array("f", ((a[i] + 4) / (b[i] + 4) - 1 for i in range(len(a))))
    return r if max(abs(v) for v in r) <= RANGE_MAX else None


def tile_sea(item):
    """(key, colour, sides, patches) for one tile: colour = the art's mean
    (open-sea tiles), sides = {side: [water colour or None per TINT_PX
    segment]} for the sides asked for, patches = band() of its sample windows."""
    key, adt, blp, ocean, is_open, sides = item
    img = blp_dxt(blp) if blp else None
    if img is None:
        return key, None, {}, []
    grid = img.block_means() if img.blocks_wide == QUADS and img.blocks_high == QUADS else None
    if grid is None:
        return key, None, {}, []
    if is_open:
        n = QUADS * QUADS
        return key, tuple(sum(c[k] for row in grid for c in row) / n for k in range(3)), {}, []
    d = depths(adt, ocean) if adt else None
    out = {}
    deep, seg = round(FEATHER * QUADS), QUADS // TINT_PX
    for s in sides:
        segs = []
        for i in range(TINT_PX):
            cs = []
            for a in range(i * seg, i * seg + seg):
                for b in range(deep):
                    x, y = {"l": (b, a), "r": (QUADS - 1 - b, a), "t": (a, b), "b": (a, QUADS - 1 - b)}[s]
                    if d and d[y * QUADS + x] > 0:
                        cs.append(grid[y][x])
            segs.append(tuple(sorted(c[k] for c in cs)[len(cs) // 2] for k in range(3)) if len(cs) >= seg else None)
        out[s] = segs
    patches = []
    if d:
        spots = windows(d)
        if spots:
            art = Image.frombytes("RGB", (img.width, img.height), img.rgb8())
            for qx, qy in spots:
                p = band(art.crop((qx * 4, qy * 4, qx * 4 + WINDOW, qy * 4 + WINDOW)))
                if p is not None:
                    patches.append(p)
    return key, None, out, patches


# --- the texture ---------------------------------------------------------------

def synthesise(pool: list[array], rnd: random.Random) -> list[float]:
    """A seamless SYNTH x SYNTH brightness field (0 = mean): patches from the
    pool overlap-added on a torus, sum(w * p) / sqrt(sum(w^2)) (independent
    patches keep their variance)."""
    n, p = SYNTH, WINDOW
    acc, wsq = [0.0] * (n * n), [1e-12] * (n * n)
    win = [math.sin(math.pi * (i + 0.5) / p) ** 2 for i in range(p)]
    for gy in range(0, n, PATCH_STEP):
        for gx in range(0, n, PATCH_STEP):
            x0 = gx + rnd.randint(-PATCH_JITTER, PATCH_JITTER) - p // 2
            y0 = gy + rnd.randint(-PATCH_JITTER, PATCH_JITTER) - p // 2
            src, o = rnd.choice(pool), rnd.randrange(8)
            for py in range(p):
                wy, row = win[py], (y0 + py) % n * n
                for px in range(p):
                    sx, sy = (py, px) if o & 4 else (px, py)
                    if o & 1:
                        sx = p - 1 - sx
                    if o & 2:
                        sy = p - 1 - sy
                    w = wy * win[px]
                    t = row + (x0 + px) % n
                    wsq[t] += w * w
                    acc[t] += w * src[sy * p + sx]
    return [acc[t] / math.sqrt(wsq[t]) for t in range(n * n)]


def smoothstep(e0: float, e1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def textures(pool: list[array], seed: int) -> list[Image.Image]:
    """VARIANTS SIZE-px grey textures: GAIN * (1 + field), variant 0 at every
    variant's edges."""
    rnd = random.Random(seed)
    fields = [synthesise(pool, rnd) for _ in range(VARIANTS)]
    sd = math.sqrt(sum(v * v for v in fields[0]) / len(fields[0]))
    n, b = SYNTH, BORDER * SYNTH
    edge = [smoothstep(b, 2 * b, min(i + 0.5, n - i - 0.5)) for i in range(n)]
    out = []
    for k, f in enumerate(fields):
        vals = []
        for y in range(n):
            for x in range(n):
                v = f[y * n + x]
                if k:
                    w = min(edge[x], edge[y])
                    v = ((1 - w) * fields[0][y * n + x] + w * v) / math.sqrt((1 - w) ** 2 + w * w)
                vals.append(255 * GAIN * (1 + CLIP * sd * math.tanh(v / (CLIP * sd))))
        img = Image.new("F", (n, n))
        img.putdata(vals)
        out.append(img.resize((SIZE, SIZE), Image.LANCZOS))
    return out


def dxt1_grey(img: Image.Image) -> bytes:
    """DXT1 blocks of a grey 'F' image (0..255), 4-colour mode, endpoints the
    block's extremes."""
    w, h = img.size
    px = img.load()
    out = bytearray()

    def rgb565(v):
        v = max(0, min(255, round(v)))
        return (v >> 3) << 11 | (v >> 2) << 5 | (v >> 3)

    def grey(c):  # the 565 colour's luminance-ish level, as the decoder sees it
        return (((c >> 11) & 31) * 255 / 31 + ((c >> 5) & 63) * 255 / 63 + (c & 31) * 255 / 31) / 3

    for by in range(0, max(h, 4), 4):
        for bx in range(0, max(w, 4), 4):
            vals = [px[min(w - 1, bx + i % 4), min(h - 1, by + i // 4)] for i in range(16)]
            c0, c1 = rgb565(max(vals)), rgb565(min(vals))
            if c0 == c1:
                out += struct.pack("<HHI", c0, c1, 0)
                continue
            if c0 < c1:
                c0, c1 = c1, c0
            g0, g1 = grey(c0), grey(c1)
            pal = (g0, g1, (2 * g0 + g1) / 3, (g0 + 2 * g1) / 3)
            idx = 0
            for i, v in enumerate(vals):
                idx |= min(range(4), key=lambda j: abs(pal[j] - v)) << (2 * i)
            out += struct.pack("<HHI", c0, c1, idx)
    return bytes(out)


def blp_dxt1(img: Image.Image) -> bytes:
    """A BLP2 (DXT1, no alpha) of a square power-of-two grey image, with every
    mip level down to 1x1."""
    levels, level = [], img
    while True:
        levels.append(dxt1_grey(level))
        if level.size[0] == 1:
            break
        level = level.resize((level.size[0] // 2, level.size[1] // 2), Image.BOX)
    head = 20 + 64 + 64 + 256 * 4
    offsets, sizes, pos = [], [], head
    for data in levels:
        offsets.append(pos)
        sizes.append(len(data))
        pos += len(data)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    out = b"BLP2" + struct.pack("<IBBBBII", 1, 2, 0, 0, 1, *img.size)
    out += struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes) + bytes(256 * 4)
    return out + b"".join(levels)


# --- the tint map ----------------------------------------------------------------

def gauss_blur(a: list[float], w: int, h: int, sigma: float) -> list[float]:
    """Separable Gaussian, zero outside."""
    r = int(3 * sigma) + 1
    k = [math.exp(-i * i / (2 * sigma * sigma)) for i in range(-r, r + 1)]
    tmp = [0.0] * (w * h)
    for y in range(h):
        for x in range(w):
            tmp[y * w + x] = sum(k[j + r] * a[y * w + x + j] for j in range(max(-r, -x), min(r, w - 1 - x) + 1))
    out = [0.0] * (w * h)
    for y in range(h):
        for x in range(w):
            out[y * w + x] = sum(k[j + r] * tmp[(y + j) * w + x] for j in range(max(-r, -y), min(r, h - 1 - y) + 1))
    return out


def value_noise(x: float, y: float, seed: int) -> float:
    """Smooth noise in -1..1 on a unit lattice."""
    def lattice(i, j):
        return random.Random(seed * 1000003 + i * 7919 + j * 104729).random() * 2 - 1
    i, j = math.floor(x), math.floor(y)
    fx, fy = x - i, y - j
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    top = lattice(i, j) * (1 - sx) + lattice(i + 1, j) * sx
    bot = lattice(i, j + 1) * (1 - sx) + lattice(i + 1, j + 1) * sx
    return top * (1 - sy) + bot * sy


class MapSea:
    def __init__(self, inst: int, name: str, drawn: set[int], edges: dict, deep: tuple, seed: int):
        self.inst, self.name, self.deep = inst, name, deep
        cols, rows = [k // 64 for k in drawn], [k % 64 for k in drawn]
        self.rect = (min(cols) - MARGIN, min(rows) - MARGIN, max(cols) + 1 + MARGIN, max(rows) + 1 + MARGIN)
        self.coast = {}
        for key in drawn:
            code = sum(bit for s, bit in SIDE_BITS.items() if key + NEIGHBOUR[s] not in drawn)
            for _, bit, a, b, off in CORNERS:
                if not code & (SIDE_BITS[a] | SIDE_BITS[b]) and key + off not in drawn:
                    code |= bit
            if code:
                self.coast[key] = code
        self.tint = self.tint_map(drawn, edges, seed)

    def tint_map(self, drawn, edges, seed) -> list[tuple]:
        c0, r0, c1, r1 = self.rect
        w, h = (c1 - c0) * TINT_PX, (r1 - r0) * TINT_PX
        vw = [[0.0] * (w * h) for _ in range(3)]
        wt = [0.0] * (w * h)
        land = bytearray(w * h)
        for key in drawn:
            ox, oy = (key // 64 - c0) * TINT_PX, (key % 64 - r0) * TINT_PX
            for y in range(TINT_PX):
                for x in range(TINT_PX):
                    land[(oy + y) * w + ox + x] = 1
            for s, segs in edges.get(key, {}).items():
                for i, c in enumerate(segs):
                    if c is None:
                        continue
                    x, y = {"l": (0, i), "r": (TINT_PX - 1, i), "t": (i, 0), "b": (i, TINT_PX - 1)}[s]
                    p = (oy + y) * w + ox + x
                    wt[p] += 1
                    for k in range(3):
                        vw[k][p] += c[k]
        sigma = NEAR * TINT_PX
        wt_b = gauss_blur(wt, w, h, sigma)
        vw_b = [gauss_blur(v, w, h, sigma) for v in vw]
        # distance (tiles) to the nearest tile drawn, by chamfer passes
        big = 1e9
        dist = [0.0 if land[i] else big for i in range(w * h)]
        for passes in ((range(h), range(w), -1), (range(h - 1, -1, -1), range(w - 1, -1, -1), 1)):
            ys, xs, dv = passes
            for y in ys:
                for x in xs:
                    i = y * w + x
                    for dx, dy, cost in ((dv, 0, 1), (0, dv, 1), (dv, dv, 1.414), (-dv, dv, 1.414)):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < w and 0 <= yy < h:
                            dist[i] = min(dist[i], dist[yy * w + xx] + cost)
        out = []
        for y in range(h):
            for x in range(w):
                i = y * w + x
                d = dist[i] / TINT_PX
                edge = min(x + 0.5, w - x - 0.5, y + 0.5, h - y - 0.5) / TINT_PX  # tiles to the border
                n = value_noise((c0 + (x + 0.5) / TINT_PX) / NOISE_TILES, (r0 + (y + 0.5) / TINT_PX) / NOISE_TILES, seed)
                far = (1 - DARKEN * smoothstep(*FAR, d)) * (1 + NOISE * n * smoothstep(0.5, 2, d)
                                                             * smoothstep(1, MARGIN / 2, edge))
                c = tuple((vw_b[k][i] + NEAR_EPS * self.deep[k] * far) / (wt_b[i] + NEAR_EPS) for k in range(3))
                out.append(tuple(min(255, round(255 * v / GAIN)) for v in c))
        self.size = (w, h)
        self.far = tuple(min(255, round(255 * v * (1 - DARKEN) / GAIN)) for v in self.deep)
        return out


def feather_mask(code: int) -> bytes:
    n = MASK_PX
    rows = []
    for y in range(n):
        row = []
        for x in range(n):
            u, v = (x + 0.5) / n, (y + 0.5) / n
            ramp = {"l": smoothstep(0, FEATHER, u), "r": smoothstep(0, FEATHER, 1 - u),
                    "t": smoothstep(0, FEATHER, v), "b": smoothstep(0, FEATHER, 1 - v)}
            a = 1.0
            for s, bit in SIDE_BITS.items():
                if code & bit:
                    a *= ramp[s]
            for _, bit, sv, sh, _ in CORNERS:
                if code & bit:
                    a *= max(ramp[sv], ramp[sh])
            row.append((255, 255, 255, round(255 * a)))
        rows.append(row)
    return write_tga(n, n, rows)


# --- output ---------------------------------------------------------------------

def write_sea(out, product: str, version: str, seas: list[MapSea]) -> None:
    w = out.write
    w(f"-- GENERATED by tools/gen_sea.py from the {product} {version} minimap tiles and terrain (MH2O ocean,"
      " MCVT heights). Do not edit.\n")
    w("-- The open sea beyond the tiles (no tile, or TileColor sea[]), continuing the art's own water. Files in dir:\n")
    w(f"--   inst .. \"_ocean\" .. v .. \".blp\", v = 0..variants-1: {SIZE}px grey, one repeat per tile, mean gain;"
      " any v beside any other\n")
    w(f"--   inst .. \"_tint.tga\": the sea's colour / gain, {TINT_PX} px per tile stretched to power-of-two sides, over"
      " tint = { col0, row0, col1, row1 };"
      " far = its border (0..255)\n")
    w(f"--   \"feather_\" .. code .. \".tga\": a coast tile's mask, 0 at its sides facing the sea, 1 within {FEATHER:g} tile\n")
    w("-- coast[key] = code: bits 1 l, 2 r, 4 t, 8 b; 16 tl, 32 tr, 64 bl, 128 br corners touching the sea diagonally\n")
    w("-- key = col * 64 + row, as in Data/Tiles.lua\n")
    w(data_head("Sea"))
    w(f"D.Sea = {{ product = \"{product}\", version = \"{version}\",\n")
    w(f"  dir = \"Textures\\\\Sea\\\\{product}\\\\\",\n")  # in the addon's folder: Atlas.Sea adds Atlas.ROOT
    w(f"  variants = {VARIANTS}, gain = {GAIN:g}, feather = {FEATHER:g}, maps = {{\n")
    for m in seas:
        w(f"  [{m.inst}] = {{ -- {m.name}\n")
        w("    tint = { %d, %d, %d, %d }, far = { %d, %d, %d },\n" % (*m.rect, *m.far))
        w("    coast = {\n")
        keys = sorted(m.coast)
        for i in range(0, len(keys), 12):
            w("      " + " ".join(f"[{k}]={m.coast[k]}," for k in keys[i:i + 12]) + "\n")
        w("    },\n  },\n")
    w("} }\n")


def pow2(n: int) -> int:
    return 1 << (n - 1).bit_length()


def tint_tga(m: MapSea) -> bytes:
    """The tint map stretched to power-of-two sides (WoW's textures), still over m.rect: it is smooth."""
    img = Image.frombytes("RGB", m.size, bytes(v for c in m.tint for v in c))
    w, h = pow2(m.size[0]), pow2(m.size[1])
    px = img.resize((w, h), Image.BILINEAR).load()
    return write_tga(w, h, [[(*px[x, y], 255) for x in range(w)] for y in range(h)])


def write_textures(directory: str, files: dict[str, bytes]) -> int:
    os.makedirs(directory, exist_ok=True)
    for name, data in files.items():
        path = os.path.join(directory, name)
        if not os.path.exists(path) or open(path, "rb").read() != data:
            with open(path, "wb") as f:
                f.write(data)
    for name in os.listdir(directory):
        if re.fullmatch(r"\d+_(ocean\d+\.blp|tint\.tga)|feather_\d+\.tga|\d+_\d+\.tga", name) and name not in files:
            os.remove(os.path.join(directory, name))
    return sum(len(d) for d in files.values())


def parse_open(path: str) -> dict[int, set[int]]:
    """TileColor sea[] per inst."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out = {}
    for m in re.finditer(r"D\.TileColor\[(\d+)\] = \{.*?\n  sea = \{(.*?)\n  \}", text, re.S):
        out[int(m.group(1))] = {int(k) for k in re.findall(r"\[(\d+)\]=true", m.group(2))}
    return out


def parse_tints(path: str) -> dict[int, dict[int, tuple]]:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out = {}
    for m in re.finditer(r"D\.TileColor\[(\d+)\] = \{.*?\n  tint = \{(.*?)\n  \}", text, re.S):
        out[int(m.group(1))] = {int(k): tuple(float(v) for v in vs.split(","))
                                for k, vs in re.findall(r"\[(\d+)\] = \{ ([^}]*) \}", m.group(2))}
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    parser.add_argument("--textures", metavar="DIR", help="textures folder (default with -o: "
                        "<output's folder>/../Textures/Sea/<product>; without -o: none written)")
    parser.add_argument("--tiles", help="the tile set (default Data/Tiles.lua)")
    parser.add_argument("--tilecolor", help="tile colours (default Data/TileColor.lua)")
    parser.add_argument("--preview", metavar="DIR", help="write <dir>/sea_<inst>.png (the tint map) and "
                        "<dir>/ocean_<inst>.png (the variants, 2x2 each)")
    parser.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    ns = parser.parse_args()
    t0 = time.time()
    src = source_from_args(parser, ns)
    product, version, tilesets = parse_tileset(ns.tiles or os.path.join(ROOT, "Data", "Tiles.lua"))
    colour_path = ns.tilecolor or os.path.join(ROOT, "Data", "TileColor.lua")
    open_sea, tints = parse_open(colour_path), parse_tints(colour_path)

    src.prefetch([MAP_DB2, LIQUIDTYPE_DB2])
    ocean = ocean_types(src.read(LIQUIDTYPE_DB2))
    wdts = {m.inst: m.wdt for m in read_maps(src.read(MAP_DB2))}
    seas, files = [], {}
    for ts in sorted((t for t in tilesets if not t.kind and t.inst in wdts), key=lambda t: t.inst):
        sea = open_sea.get(ts.inst, set()) & set(ts.tiles)
        if len(sea) < MIN_OPEN:
            continue
        drawn = set(ts.tiles) - sea
        wdt = src.read(wdts[ts.inst])
        adts = {k: t.root_adt for k, t in wdt_maid(wdt).items() if t.root_adt and k in ts.tiles}
        src.prefetch(list(adts.values()) + list(ts.tiles.values()))

        def items():
            for key in sorted(ts.tiles):
                sides = [s for s in SIDE_BITS if key in drawn and key + NEIGHBOUR[s] not in drawn]
                yield (key, src.read(adts[key]) if key in adts else None, src.read(ts.tiles[key]), ocean,
                       key in sea, sides)

        edges, opens, pool = {}, [], []
        tint = tints.get(ts.inst, {})
        with ProcessPoolExecutor(ns.jobs) as pool_ex:
            for key, colour, sides, patches in pool_ex.map(tile_sea, items(), chunksize=4):
                if colour:
                    opens.append(colour)
                t = tint.get(key)
                if t:  # drawn = texel * m + a
                    sides = {s: [c and tuple(min(1.0, c[k] * t[k] + t[3 + k]) for k in range(3)) for c in segs]
                             for s, segs in sides.items()}
                if sides:
                    edges[key] = sides
                pool += patches
        name = ts.name.replace("\n", " ")
        if not pool:
            log(f"[{ts.inst}] {name}: no ocean to sample, no sea")
            continue
        deep = tuple(sorted(c[k] for c in opens)[len(opens) // 2] for k in range(3))
        log(f"[{ts.inst}] {name}: {len(drawn)} tiles drawn, {len(sea)} open sea; {len(pool)} water samples; "
            f"open sea {tuple(round(v * 255) for v in deep)}")
        t1 = time.time()
        m = MapSea(ts.inst, name, drawn, edges, deep, SEED + ts.inst)
        texs = textures(pool, SEED + ts.inst)
        log(f"  {len(m.coast)} coast tiles, tint map {m.size[0]}x{m.size[1]}, textures in {time.time() - t1:.1f}s")
        for v, img in enumerate(texs):
            files[f"{ts.inst}_ocean{v}.blp"] = blp_dxt1(img)
        files[f"{ts.inst}_tint.tga"] = tint_tga(m)
        seas.append(m)
        if ns.preview:
            os.makedirs(ns.preview, exist_ok=True)
            Image.frombytes("RGB", m.size, bytes(v for c in m.tint for v in c)).save(
                os.path.join(ns.preview, f"sea_{ts.inst}.png"))
            sheet = Image.new("L", (SIZE * 2 * VARIANTS, SIZE * 2))
            for v, img in enumerate(texs):
                for i in range(4):
                    sheet.paste(img.convert("L"), (v * 2 * SIZE + i % 2 * SIZE, i // 2 * SIZE))
            sheet.save(os.path.join(ns.preview, f"ocean_{ts.inst}.png"))
    for code in sorted({c for m in seas for c in m.coast.values()}):
        files[f"feather_{code}.tga"] = feather_mask(code)

    if ns.output:
        with open(ns.output, "w", encoding="utf-8", newline="\n") as f:
            write_sea(f, product, version, seas)
        log(f"wrote {ns.output}: {os.path.getsize(ns.output) // 1024} KB")
    else:
        write_sea(sys.stdout, product, version, seas)
    directory = ns.textures or (ns.output and os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(ns.output))),
                                                           "Textures", "Sea", product))
    if directory:
        size = write_textures(directory, files)
        log(f"wrote {len(files)} textures to {directory}: {size // 1024} KB")
    log(f"done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()

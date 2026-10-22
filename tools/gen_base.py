#!/usr/bin/env python3
"""Generate Textures/Base<Continent>.blp and Data/Base.lua: each continent as one stylised flat map.

The base layer (ui/Base.lua) lies under the tiles and, zoomed far out, stands in for them: one
picture of the continent instead of ~1,800 tiles. It is not the tiles shrunk (blurry): it's drawn
from them.

  - Land and water per pixel from the real tile art (the minimap's water is a dark teal or black,
    land is anything redder or brighter), at twice the picture's resolution, then a 3x3 close and
    open (a speck of land or water in the other goes) and the edge antialiased on the way down: a
    crisp coastline, as the tiles' own, not the coarse sea[] of Data/TileColor.lua.
  - Land a flat colour a zone: the mean of that zone's land pixels in the real tiles (AreaGrid's
    16x16 chunks a tile say which zone a pixel is in; unzoned ones take the nearest's), so the
    switch to the tiles reads as the same ground. Where two zones meet the colour blends over a
    chunk (~33 yd). No zone borders or names: the live layers draw them.
  - Water the map's backdrop colour (Data/Tiles.lua's bg: ui/Window.lua's), so open sea is
    seamless, with the picture's box and without.
  - A subtle shade inside the coast (SHADE): land darkened by up to a quarter at the water's edge.

The picture covers the continent's drawn tiles (Atlas.Drawn, but a lone one far off), PX pixels a tile, in a power-of-two
texture (the rest backdrop colour); Data/Base.lua says where and how big. BLP2 DXT1 with mips
(mmtools/blp.py), ~2 MB a continent: a TGA (32-bit, uncompressed) would be 16 MB.

  python3 tools/gen_base.py local "/Applications/World of Warcraft" wow_classic_beta \\
      --cache /tmp/mm-base.pkl --preview /tmp/base-preview

Reads Data/Tiles.lua, TileColor.lua, Areas.lua and AreaGrid.lua (the addon's) and the tiles' art
from the source by FileDataID; writes Textures/ and Data/Base.lua beside this tools/ folder.
"""
from __future__ import annotations

import argparse
import os
import pickle
import sys
import time
from collections import deque

from lupa import lua51
from PIL import Image, ImageChops, ImageFilter

from mmtools.blp import write_blp
from mmtools.formats import blp_dxt
from mmtools.log import log
from mmtools.luaout import data_head, load_data
from mmtools.sources import add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CONTINENTS = {0: "EasternKingdoms", 1: "Kalimdor"}
MAX_SIDE = 2048    # a texture's side at most
CHUNKS = 16        # AreaGrid's chunks a tile side
OVER = 2           # the land/water test and its clean-up at this times the picture's resolution
SHADE = 0.28       # land darkened this much at the coast, to nothing PX / 8 inside it
SMOOTH = 1.3       # px at OVER x: the coast rounded (blurred, cut at half)
LAND_BLUR = 0.6    # px at OVER x: the mask's edge softened before it is averaged down (the antialiasing)
# Water: dark and blue-green (R low, B not far under G), or nearly black.
WATER_R, WATER_BG = 24, 0.5
BLACK = 14


def pot(n: int) -> int:
    p = 1
    while p < n:
        p *= 2
    return p


def size_for(w: int, h: int) -> tuple[int, int, int]:
    """(px a tile, texture width, height): the sharpest picture that fits MAX_SIDE, then the
    smallest power-of-two texture that holds a PX within 15% of it."""
    best = min(MAX_SIDE // w, MAX_SIDE // h)
    pick = None
    for px in range(best, int(best * 0.85) - 1, -1):
        tw, th = pot(w * px), pot(h * px)
        if pick is None or tw * th < pick[1] * pick[2]:
            pick = (px, tw, th)
    return pick


# --- the real tiles -------------------------------------------------------------

def read_data():
    lua = lua51.LuaRuntime()
    ns = lua.table()
    for name in ("Tiles", "TileColor", "Areas", "AreaGrid"):
        load_data(lua, os.path.join(ROOT, "Data", name + ".lua"), ns)
    return ns.Data


def tile_means(src, tiles: dict[int, int], cache: dict, inst: int) -> dict[int, bytes]:
    """key -> 128x128 RGB bytes (the tile's 4x4 block means)."""
    todo = [k for k in tiles if (inst, k) not in cache]
    if todo:
        src.prefetch(tiles[k] for k in todo)
        for k in todo:
            blp = src.read(tiles[k])
            img = blp_dxt(blp) if blp else None
            if img is None:
                continue
            m = img.block_means()
            cache[(inst, k)] = bytes(min(255, max(0, round(v * 255))) for row in m for c in row for v in c)
    return {k: cache[(inst, k)] for k in tiles if (inst, k) in cache}


# --- the picture ----------------------------------------------------------------

def mosaic(means: dict[int, bytes], c0: int, r0: int, c1: int, r1: int, s: int, bg: tuple) -> Image.Image:
    """The tiles as one RGB image, s px a tile; tiles without art the backdrop colour."""
    im = Image.new("RGB", ((c1 - c0) * s, (r1 - r0) * s), bg)
    for k, data in means.items():
        col, row = k // 64, k % 64
        if c0 <= col < c1 and r0 <= row < r1:
            t = Image.frombytes("RGB", (128, 128), data).resize((s, s), Image.BOX)
            im.paste(t, ((col - c0) * s, (row - r0) * s))
    return im


def land_mask(im: Image.Image) -> Image.Image:
    """255 where the art is land. Water is dark and blue-green: R under WATER_R with B over
    WATER_BG of G; or every channel under BLACK."""
    r, g, b = im.split()
    low_r = r.point(lambda v: 255 if v < WATER_R else 0)
    teal = ImageChops.subtract(b, g.point(lambda v: int(v * WATER_BG))).point(lambda v: 255 if v > 0 else 0)
    black = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v < BLACK else 0)
    water = ImageChops.lighter(ImageChops.darker(low_r, teal), black)
    land = ImageChops.invert(water)
    land = land.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))  # close: holes in land
    land = land.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))  # open: land specks
    return land.filter(ImageFilter.GaussianBlur(SMOOTH)).point(lambda v: 255 if v > 127 else 0)  # the coast's jags rounded


def zone_of(data, inst: int) -> dict[int, int]:
    """areaID -> its zone (the ancestor with no parent)."""
    areas = {int(k): v for k, v in data.Areas.items()}
    out = {}
    for a in areas:
        z, seen = a, 0
        while areas.get(z) and areas[z][2] is not None and seen < 8:
            z, seen = int(areas[z][2]), seen + 1
        out[a] = z
    return out


def decode(cells: str) -> list[int]:
    out, i = [], 0
    while i < len(cells):
        ch = cells[i]
        i += 1
        j = i
        while j < len(cells) and cells[j].isdigit():
            j += 1
        n = int(cells[i:j]) if j > i else 1
        i = j
        out += [(ord(ch) - 97) if ch.islower() else (ord(ch) - 65 + 26)] * n
    return out


def chunk_zones(data, inst: int, c0: int, r0: int, c1: int, r1: int) -> list[list[int]]:
    """zone id (0: none) of each chunk, rows top first, filled from the nearest chunk with one."""
    zone = zone_of(data, inst)
    cw, ch = (c1 - c0) * CHUNKS, (r1 - r0) * CHUNKS
    grid = [[0] * cw for _ in range(ch)]
    for key, enc in data.AreaGrid[inst].items():
        col, row = int(key) // 64, int(key) % 64
        if not (c0 <= col < c1 and r0 <= row < r1):
            continue
        palette = [int(enc[1][i + 1]) for i in range(len(enc[1]))]
        for n, idx in enumerate(decode(enc[2])):
            a = palette[idx]
            if a:
                grid[(row - r0) * CHUNKS + n // CHUNKS][(col - c0) * CHUNKS + n % CHUNKS] = zone.get(a, a)
    q = deque((x, y) for y in range(ch) for x in range(cw) if grid[y][x])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < cw and 0 <= ny < ch and not grid[ny][nx]:
                grid[ny][nx] = grid[y][x]
                q.append((nx, ny))
    return grid


def zone_colours(grid, im: Image.Image, mask: Image.Image) -> dict[int, tuple[int, int, int]]:
    """Each zone's mean land colour: the land pixels of the art, by chunk."""
    cw, ch = len(grid[0]), len(grid)
    prem = Image.composite(im, Image.new("RGB", im.size, (0, 0, 0)), mask).resize((cw, ch), Image.BOX)
    cov = mask.resize((cw, ch), Image.BOX)
    sums, n = {}, {}
    pd, cd = prem.load(), cov.load()
    for y in range(ch):
        for x in range(cw):
            z = grid[y][x]
            if z and cd[x, y]:
                s = sums.setdefault(z, [0, 0, 0])
                p = pd[x, y]
                s[0] += p[0]
                s[1] += p[1]
                s[2] += p[2]
                n[z] = n.get(z, 0) + cd[x, y] / 255
    return {z: tuple(round(v / n[z]) for v in s) for z, s in sums.items() if n[z] > 0}


def bake(data, src_means: dict[int, bytes], inst: int, bg: tuple, c0: int, r0: int, c1: int, r1: int, px: int):
    """(the picture at px a tile, RGB; the zone colours)."""
    s = px * OVER
    im = mosaic(src_means, c0, r0, c1, r1, s, bg)
    mask = land_mask(im)
    grid = chunk_zones(data, inst, c0, r0, c1, r1)
    cols = zone_colours(grid, im, mask)
    fallback = (110, 100, 70)
    cw, ch = len(grid[0]), len(grid)
    zim = Image.new("RGB", (cw, ch))
    zim.putdata([cols.get(z, fallback) for row in grid for z in row])
    # Colour at the picture's resolution (bilinear: a chunk's blend), the mask softened a touch, both
    # averaged down: the coast's edge is a pixel of the mix.
    w, h = (c1 - c0) * px, (r1 - r0) * px
    land = zim.resize((w, h), Image.BILINEAR).filter(ImageFilter.GaussianBlur(px / CHUNKS))  # (the chunks' stairs rounded)
    m = mask.filter(ImageFilter.GaussianBlur(LAND_BLUR)).resize((w, h), Image.BOX)
    shade = m.filter(ImageFilter.GaussianBlur(px / 8))  # 255 deep inland, less toward the coast
    k = shade.point(lambda v: int(255 * (1 - SHADE * (1 - v / 255))))
    land = ImageChops.multiply(land, Image.merge("RGB", (k, k, k)))
    return Image.composite(land, Image.new("RGB", (w, h), bg), m), cols


def pad(im: Image.Image, tw: int, th: int, bg: tuple) -> Image.Image:
    out = Image.new("RGB", (tw, th), bg)
    out.paste(im, (0, 0))
    return out


def mips(im: Image.Image) -> list[tuple[int, int, bytes]]:
    out, w, h = [], im.width, im.height
    while True:
        out.append((w, h, im.tobytes()))
        if w == 1 and h == 1:
            return out
        w, h = max(1, w // 2), max(1, h // 2)
        im = im.resize((w, h), Image.BOX)


# --- main -----------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("--cache", metavar="FILE", help="keep the tiles' block means in FILE between runs")
    parser.add_argument("--preview", metavar="DIR", help="also write each picture as a PNG (and the DXT1 decoded) here")
    parser.add_argument("--textures", default=os.path.join(ROOT, "Textures"))
    parser.add_argument("-o", "--output", default=os.path.join(ROOT, "Data", "Base.lua"))
    ns = parser.parse_args()
    t0 = time.time()
    src = source_from_args(parser, ns)
    data = read_data()
    cache = {}
    if ns.cache and os.path.exists(ns.cache):
        with open(ns.cache, "rb") as f:
            cache = pickle.load(f)

    rows = []
    for inst, name in CONTINENTS.items():
        m = data.Tiles.maps[inst]
        sea = data.TileColor[inst].sea
        tiles = {int(k): int(v) for k, v in m.tiles.items() if not sea[k]}  # Atlas.Drawn
        bg = tuple(round(m.bg[i] * 255) for i in (1, 2, 3))
        joined = [k for k in tiles if any(k + d in tiles for d in (-65, -64, -63, -1, 1, 63, 64, 65))]  # (a lone tile far off: Kalimdor's 1,1)
        c0, r0 = min(k // 64 for k in joined), min(k % 64 for k in joined)
        c1, r1 = max(k // 64 for k in joined) + 1, max(k % 64 for k in joined) + 1
        px, tw, th = size_for(c1 - c0, r1 - r0)
        means = tile_means(src, tiles, cache, inst)
        log(f"[{inst}] {name}: tiles {c0}..{c1} x {r0}..{r1}, {px} px a tile, texture {tw}x{th}")
        im, cols = bake(data, means, inst, bg, c0, r0, c1, r1, px)
        full = pad(im, tw, th, bg)
        blp = write_blp(mips(full))
        os.makedirs(ns.textures, exist_ok=True)
        path = os.path.join(ns.textures, f"Base{name}.blp")
        with open(path, "wb") as f:
            f.write(blp)
        log(f"  {path}: {len(blp) // 1024} KB; {len(cols)} zones")
        if ns.preview:
            os.makedirs(ns.preview, exist_ok=True)
            im.save(os.path.join(ns.preview, f"{name}.png"))
            dxt = blp_dxt(blp)
            Image.frombytes("RGB", (dxt.width, dxt.height), dxt.rgb8()).crop((0, 0, im.width, im.height)).save(
                os.path.join(ns.preview, f"{name}-dxt1.png"))
        rows.append((inst, name, c0, r0, c1, r1, px, tw, th))
    if ns.cache:
        with open(ns.cache, "wb") as f:
            pickle.dump(cache, f)

    with open(ns.output, "w", encoding="utf-8", newline="\n") as f:
        w = f.write
        w(f"-- GENERATED by tools/gen_base.py from the {src.product} {src.version} minimap tiles. Do not edit.\n")
        w("-- [inst] = the continent's base picture (ui/Base.lua): file (under the addon's folder, no extension), the tile rect it covers\n")
        w("--   (c0, r0 to c1, r1: the drawn tiles), px a tile, and the texture's size (power of two; the picture in its top left)\n")
        w(data_head("Base"))
        w("D.Base = {\n")
        for inst, name, c0, r0, c1, r1, px, tw, th in rows:
            w(f"  [{inst}] = {{ file = \"Textures\\\\Base{name}\", c0 = {c0}, r0 = {r0}, c1 = {c1}, "
              f"r1 = {r1}, px = {px}, w = {tw}, h = {th} }}, -- {name}\n")
        w("}\n")
    log(f"done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()

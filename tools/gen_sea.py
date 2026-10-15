#!/usr/bin/env python3
"""Generate Data/Sea.lua and its masks: where the ocean is, how deep, and the
sea's colours, so the map can draw one sea around (and under) its tiles
instead of square tiles on a flat backdrop.

Per terrain quad (8x8 per ADT chunk, 128x128 per tile, ~4 yards) the ocean
(MH2O layers of an "Ocean" LiquidType) is compared with the ground under it
(MCVT heights, as tools/gen_walk.py reads them): ocean over the ground is sea,
depth = its surface - the ground. Lakes and rivers aren't sea: the tiles'
own art draws them. Outside the map's terrain tiles is deep sea.

For every tile where land meets sea, or the sea is shallow, a 128x128 mask
Textures/Sea/<product>/<inst>_<key>.tga (beside the output's folder, or
--masks DIR; the folder is the generator's: masks it no longer makes are
deleted):

  alpha  land: 1 land, 0 sea; the coast a soft edge (a Gaussian of FEATHER
         quads across the shore, centred on it), so the tile's art fades into
         the sea instead of ending in its square
         ... and land where the art over the sea is built (piers, ships):
         unlike the water around it and not water-coloured (BUILT_*)
  rgb    shelf (grey): exp(-depth / SHELF yards), 1 at the shore and on
         land; softened by SHELF_BLUR quads. The art fades from seabed to
         deep water about so (red faster, green slower)

Sea.lua lists the masked tiles and the open ones (all sea, too deep for a shelf:
the art needn't be drawn), and per map the sea's colours, sampled from the
tiles' own water (per-channel medians of the minimap art over sea SHALLOW
yards deep, and DEEP or more), so the drawn sea matches the art.
Open-world maps with at least MIN_OPEN open-sea tiles only.

How the addon draws it (WoW textures only; see demo/tiles.js):
  1. the ocean: one solid texture (SetColorTexture) of `deep` under the map
  2. per masked tile, over its square: the mask with SetBlendMode("DISABLE")
     (opaque, alpha ignored) and vertex colour shallow - deep, then a solid
     texture of `deep` with SetBlendMode("ADD"): deep + shelf * (shallow -
     deep). (deep <= shallow per channel: Sea.lua clamps deep to it.)
  3. the tile's art with the mask as its MaskTexture (Texture:AddMaskTexture;
     masks use alpha): land shows, sea is ours, the coast fades between.
  Tiles listed in open[] draw no art.

  .venv/bin/python tools/gen_sea.py local "/Applications/World of Warcraft" wow_classic_beta \\
      -o Data/Sea.lua [--preview DIR]

Needs Pillow (blurs and previews). Output is deterministic.
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor

from PIL import Image, ImageChops, ImageFilter

from gen_tilecolor import ROOT, parse_tileset
from mmtools.db2 import read_wdc5
from mmtools.formats import adt_chunks, adt_liquids, blp_dxt, box_downsample, wdt_maid
from mmtools.log import log
from mmtools.maps import MAP_DB2, read_maps
from mmtools.sources import add_source_args, source_from_args
from mmtools.tga import write_tga

LIQUIDTYPE_DB2 = 1371380  # dbfilesclient/liquidtype.db2

PX = 128           # mask pixels per tile: one per terrain quad
FEATHER = 2.0      # coast softness: Gaussian sigma in quads (~4 yd each)
SHELF = 28.0       # yards: shelf = exp(-depth / SHELF), about as the art fades from seabed to deep water
SHELF_BLUR = 2.0   # Gaussian sigma (quads) over the shelf: no quad steps, no seams at tile edges
SHALLOW = (4, 12)  # yards: the art over sea this deep gives the shallow colour (shallower is mostly beach)
DEEP = 60.0        # ... this deep or more, the deep colour
SAMPLE_STEP = 4    # colour samples: every 4th quad each way
BUILT_AROUND = 6.0  # quads: Gaussian sigma of the water around a quad the art there is compared with
BUILT_DIFF = 0.06  # art this far from it (any channel, 0..1) over the sea is built: piers, ships
BUILT_BRIGHT = 0.15  # ... and redder than green, or this much brighter (stone)
BUILT_DEPTH = 0.5  # yards: not on shallower sea (wet sand: the beach is the art's, but blurred into the sea)
BUILT_SOFT = 0.7   # quads: Gaussian sigma of the built parts' edge (they keep their shape, unlike the coast)
MIN_OPEN = 4       # maps with fewer open-sea tiles have no sea (lakes on map fragments)


def ocean_types(db2: bytes) -> set[int]:
    """LiquidType IDs that are ocean, by name ("Ocean", "Slow Ocean",
    "PBRWater - Generic - Ocean", ...): newer ones aren't in the ocean category."""
    return {r[0] for r in read_wdc5(db2, string_fields={0}) if isinstance(r[1], str) and "Ocean" in r[1]}


def tile_sea(item: tuple[int, bytes, bytes, set[int]]):
    """(key, land, shelf, built, samples) for one tile: PX*PX bytes each
    (land 255 / sea 0; shelf 255 at the shore, exp(-depth / SHELF); built 255
    where the art over the sea isn't water), samples [(depth, rgb)] of the art
    over sea; land None without sea."""
    key, adt, blp, ocean = item
    liquids: dict[tuple[int, int], list] = {}
    for liq in adt_liquids(adt):
        if liq.liquid_type in ocean:
            liquids.setdefault((liq.ix, liq.iy), []).append(liq)
    if not liquids:
        return key, None, None, None, []
    land = bytearray(b"\xff" * PX * PX)
    shelf = bytearray(b"\xff" * PX * PX)
    depth: dict[int, float] = {}
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
                if h is None:
                    ground = z
                else:
                    ground = z + (h[qy * 17 + qx] + h[qy * 17 + qx + 1] + h[(qy + 1) * 17 + qx]
                                  + h[(qy + 1) * 17 + qx + 1] + h[qy * 17 + 9 + qx]) / 5
                d = max(over) - ground
                if d > 0:
                    p = (ch.iy * 8 + qy) * PX + ch.ix * 8 + qx
                    land[p] = 0
                    shelf[p] = round(255 * math.exp(-d / SHELF))
                    depth[p] = d
    if not depth:
        return key, None, None, None, []
    grid = blp_dxt(blp).block_means()
    if len(grid) != PX:
        grid = box_downsample(grid, PX)
    art = [c for row in grid for c in row]
    # What's built over the water (piers, ships, buildings): art unlike the water around it (the
    # art over sea blurred, normalised by how much of the blur was sea), and not water-coloured
    # (water is green-blue: wood, sand and roofs are redder) unless much brighter (stone).
    rgb = Image.frombytes("RGB", (PX, PX), bytes(round(v * 255) for c in art for v in c))
    sea = Image.frombytes("L", (PX, PX), bytes(255 - v for v in land))
    blur = ImageFilter.GaussianBlur(BUILT_AROUND)
    around = ImageChops.multiply(rgb, sea.convert("RGB")).filter(blur).tobytes()
    weight = sea.filter(blur).tobytes()
    built = bytearray(PX * PX)
    samples = []
    for p, d in depth.items():
        w = weight[p] / 255
        c = art[p]
        a = [around[p * 3 + k] / 255 / w for k in range(3)] if w else c
        if (d >= BUILT_DEPTH and max(abs(c[k] - a[k]) for k in range(3)) > BUILT_DIFF
                and (c[0] > c[1] or sum(c) - sum(a) > 3 * BUILT_BRIGHT)):
            built[p] = 255
        elif p // PX % SAMPLE_STEP == 0 and p % SAMPLE_STEP == 0:
            samples.append((d, art[p]))
    return key, bytes(land), bytes(shelf), bytes(built), samples


def median(v: list[float]) -> float:
    v = sorted(v)
    return v[len(v) // 2]


def ramp(samples: list[tuple[float, tuple]]) -> tuple[tuple, tuple]:
    """(shallow, deep) colours from the art over shallow / deep sea; deep
    clamped to shallow per channel (the addon adds shelf * (shallow - deep))."""
    def med(sel):
        return tuple(median([c[k] for c in sel]) for k in range(3))
    shallow = med([c for d, c in samples if SHALLOW[0] <= d <= SHALLOW[1]])
    deep = med([c for d, c in samples if d >= DEEP] or [c for d, c in samples])
    return shallow, tuple(min(a, b) for a, b in zip(deep, shallow))


class MapSea:
    def __init__(self, inst, name, tiles, layers):
        self.inst, self.name, self.tiles = inst, name, tiles
        self.shallow = self.deep = None  # (ramp)
        c0, c1 = min(k // 64 for k in tiles) - 1, max(k // 64 for k in tiles) + 1
        r0, r1 = min(k % 64 for k in tiles) - 1, max(k % 64 for k in tiles) + 1
        self.origin = (c0, r0)
        size = ((c1 - c0 + 1) * PX, (r1 - r0 + 1) * PX)
        # Whole-map images (a tile of open sea around) so the blurs cross tile edges.
        land, shelf, built = Image.new("L", size, 0), Image.new("L", size, 0), Image.new("L", size, 0)
        full = Image.new("L", (PX, PX), 255)
        for key in tiles:
            at = ((key // 64 - c0) * PX, (key % 64 - r0) * PX)
            if key in layers:
                for img, b in zip((land, shelf, built), layers[key]):
                    img.paste(Image.frombytes("L", (PX, PX), b), at)
            else:
                land.paste(full, at)
                shelf.paste(full, at)
        self.land = ImageChops.lighter(land.filter(ImageFilter.GaussianBlur(FEATHER)),
                                       built.filter(ImageFilter.GaussianBlur(BUILT_SOFT)))
        self.shelf = shelf.filter(ImageFilter.GaussianBlur(SHELF_BLUR))
        self.masks, self.open = {}, set()
        for key in sorted(tiles):
            box = self.box(key)
            lt, st = self.land.crop(box), self.shelf.crop(box)
            lo, hi = lt.getextrema()
            if lo == 255:
                continue  # all land: the art as it is
            if hi == 0 and st.getextrema()[1] == 0:
                self.open.add(key)  # all deep sea
                continue
            self.masks[key] = (lt, st)

    def box(self, key):
        x, y = (key // 64 - self.origin[0]) * PX, (key % 64 - self.origin[1]) * PX
        return x, y, x + PX, y + PX


def mask_tga(land: Image.Image, shelf: Image.Image) -> bytes:
    a, s = land.tobytes(), shelf.tobytes()
    return write_tga(PX, PX, [[(s[i], s[i], s[i], a[i]) for i in range(y * PX, y * PX + PX)] for y in range(PX)])


def write_masks(directory: str, seas: list[MapSea]) -> int:
    os.makedirs(directory, exist_ok=True)
    wanted, size = set(), 0
    for m in seas:
        for key, (lt, st) in m.masks.items():
            name = f"{m.inst}_{key}.tga"
            wanted.add(name)
            data = mask_tga(lt, st)
            size += len(data)
            path = os.path.join(directory, name)
            if not os.path.exists(path) or open(path, "rb").read() != data:
                with open(path, "wb") as f:
                    f.write(data)
    for name in os.listdir(directory):
        if re.fullmatch(r"\d+_\d+\.tga", name) and name not in wanted:
            os.remove(os.path.join(directory, name))
    return size


def write_sea(out, product: str, version: str, seas: list[MapSea]) -> None:
    w = out.write
    w(f"-- GENERATED by tools/gen_sea.py from the {product} {version} terrain (MH2O ocean, MCVT heights)"
      " and minimap tiles. Do not edit.\n")
    w("-- shallow, deep = the sea's colours (from the art over sea %g..%g / >= %g yd deep; deep <= shallow per channel)\n"
      % (*SHALLOW, DEEP))
    w(f"-- masks = tiles with a {PX}x{PX} mask dir .. inst .. \"_\" .. key .. \".tga\": alpha = land (1 land, 0 sea, the coast\n")
    w(f"--   feathered: Gaussian sigma {FEATHER:g} px), rgb = shelf (exp(-depth / {SHELF:g} yd), 1 at the shore and on land):\n")
    w("--   sea colour = deep + shelf * (shallow - deep)\n")
    w("-- open = tiles that are all deep sea: no art drawn. Other tiles: all land, the art as it is. Off the tiles: deep sea.\n")
    w("-- key = col * 64 + row, as in Data/Tiles.lua\n")
    w(f"MagicMap_Sea = {{ product = \"{product}\", version = \"{version}\",\n")
    w(f"  dir = \"Interface\\\\AddOns\\\\MagicMap\\\\Textures\\\\Sea\\\\{product}\\\\\", maps = {{\n")
    for m in seas:
        w(f"  [{m.inst}] = {{ -- {m.name}\n")
        w("    shallow = { %.3f, %.3f, %.3f }, deep = { %.3f, %.3f, %.3f },\n" % (*m.shallow, *m.deep))
        for name, keys in (("masks", sorted(m.masks)), ("open", sorted(m.open))):
            w(f"    {name} = {{\n")
            for i in range(0, len(keys), 12):
                w("      " + " ".join(f"[{k}]=true," for k in keys[i:i + 12]) + "\n")
            w("    },\n")
        w("  },\n")
    w("} }\n")


def write_preview(m: MapSea, path: str, px: int = 32) -> None:
    """The map's sea as the addon draws it, without the art: land grey."""
    def rgb8(c):
        return tuple(round(v * 255) for v in c)
    deep, shallow = rgb8(m.deep), rgb8(m.shallow)
    size = (m.land.width * px // PX, m.land.height * px // PX)
    shelf = m.shelf.resize(size, Image.BILINEAR)
    sea = Image.composite(Image.new("RGB", size, shallow), Image.new("RGB", size, deep), shelf)
    out = Image.composite(Image.new("RGB", size, (120, 120, 110)), sea, m.land.resize(size, Image.BILINEAR))
    out.save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", help="output file (default: stdout)")
    parser.add_argument("--masks", metavar="DIR", help="masks folder (default with -o: "
                        "<output's folder>/../Textures/Sea/<product>; without -o: none written)")
    parser.add_argument("--tiles", help="the tile set (default Data/Tiles.lua)")
    parser.add_argument("--preview", metavar="DIR", help="write <dir>/sea_<inst>.png per map")
    parser.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1)
    ns = parser.parse_args()
    t0 = time.time()
    src = source_from_args(parser, ns)
    product, version, tilesets = parse_tileset(ns.tiles or os.path.join(ROOT, "Data", "Tiles.lua"))

    src.prefetch([MAP_DB2, LIQUIDTYPE_DB2])
    ocean = ocean_types(src.read(LIQUIDTYPE_DB2))
    wdts = {m.inst: m.wdt for m in read_maps(src.read(MAP_DB2))}
    seas = []
    for ts in sorted((t for t in tilesets if not t.kind and t.inst in wdts), key=lambda t: t.inst):
        wdt = src.read(wdts[ts.inst])
        adts = {k: t.root_adt for k, t in wdt_maid(wdt).items() if t.root_adt and k in ts.tiles}
        src.prefetch(list(adts.values()) + list(ts.tiles.values()))

        def items():
            for key in sorted(adts):
                yield key, src.read(adts[key]), src.read(ts.tiles[key]), ocean

        layers, samples = {}, []
        with ProcessPoolExecutor(ns.jobs) as pool:
            for key, land, shelf, built, got in pool.map(tile_sea, items(), chunksize=4):
                if land:
                    layers[key] = (land, shelf, built)
                samples += got
        m = MapSea(ts.inst, ts.name.replace("\n", " "), ts.tiles, layers)
        if len(m.open) < MIN_OPEN:
            continue
        m.shallow, m.deep = shallow, deep = ramp(samples)
        seas.append(m)
        log(f"[{m.inst}] {m.name}: {len(ts.tiles)} tiles, {len(layers)} with ocean: {len(m.masks)} masks, "
            f"{len(m.open)} open; shallow {tuple(round(v, 3) for v in shallow)} deep {tuple(round(v, 3) for v in deep)}")
        if ns.preview:
            os.makedirs(ns.preview, exist_ok=True)
            write_preview(m, os.path.join(ns.preview, f"sea_{m.inst}.png"))

    if ns.output:
        with open(ns.output, "w", encoding="utf-8", newline="\n") as f:
            write_sea(f, product, version, seas)
        log(f"wrote {ns.output}: {os.path.getsize(ns.output) // 1024} KB")
    else:
        write_sea(sys.stdout, product, version, seas)
    masks = ns.masks or (ns.output and os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(ns.output))),
                                                     "Textures", "Sea", product))
    if masks:
        size = write_masks(masks, seas)
        log(f"wrote {sum(len(m.masks) for m in seas)} masks to {masks}: {size // 1024} KB")
    log(f"done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()

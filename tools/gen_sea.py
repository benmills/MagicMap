#!/usr/bin/env python3
"""Generate Textures/Sea*.tga and Data/Sea.lua: an ocean round each continent, where Blizzard's art has only near-black.

The minimap's open water has colour in its shallows and none further out, so there's nothing there to copy: this one is
made, no pixel of anyone's art in it. Open water is what the terrain files say is under water or has no terrain (MCVT,
MH2O), joined to the map's edge (lakes aren't). Its colour runs from SHALLOW by the land through MID to DEEP with the
distance from the land, the line wandering (fractal noise), with a soft swell that dies out by the picture's edge; right by
the land it's SHORE, the dark green Blizzard's own maps use there. It lies over the tiles (ui/Sea.lua), seen through where
Blizzard's water has colour (its alpha reads the art), so their coast and shallows stay theirs and their near-black goes.
Zephras Isle's terrain is mostly encrypted: its water is where its art is near-black (ART_WATER). It floats (SKY): no
coast round it, deep water below and faint clouds by its land.

The far water's swell is two seamless textures laid on the world (SWELL and SWELL2 tiles a repeat, from world tile 0, 0;
the demo's OFFSET places each map): sea/swell.webp and swell2.webp, which the demo tiles as its whole background. The demo's ocean is one picture over
the whole world (sea/world-sea.webp: every map's land at its place, so no picture overlaps another), its edge meeting the
background pixel for pixel. The addon's pictures, one a map, fade the swell out by their edge, to its flat backdrop (DEEP).

  python3 tools/gen_sea.py local "/Applications/World of Warcraft" wowf --bake demo/sea
"""
from __future__ import annotations

import argparse
import json
import os
import tempfile
from collections import deque

import numpy as np
from PIL import Image

from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.sources import add_source_args, source_from_args
from mmtools.terrain import Ground
from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAD = 6            # tiles of sea round the land
PX = 32            # px a tile the picture's worked out at (the demo's)
SHIP = 16          # ...and shipped at
DARK = .88  # the water a tad darker than the colours below (the shore's dark green stays Blizzard's)
SHORE, SHALLOW, MID, DEEP = (np.array([23, 39, 22.]), np.array([26, 74, 70.]) * DARK, np.array([12, 48, 62.]) * DARK,
                             np.array([6, 26, 44.]) * DARK)
NAMES = {0: "EasternKingdoms", 1: "Kalimdor", 2991: "ZephrasIsle"}
# Maps that float: no coast round them, deep water below and, by the land, faint clouds (CLOUD, at most CLOUD_A).
SKY = {2991}
CLOUD, CLOUD_A = np.array([188, 200, 208.]), .26
ART_WATER = {2991}  # maps whose water is read from the art, not the terrain
SWELL = 8           # tiles: the swell texture's repeat
SWELL_AMP = .5      # the swell's strength: DEEP * (1 + (swell - .5) * SWELL_AMP)
# A second, broader swell over it at another repeat (13 tiles: the two repeat together only every 104, wider than the
# world), so the far water doesn't read as one pattern repeated, zoomed out most. swell = (1 - OVER) * fine + OVER * broad,
# spread back by SPREAD (an average is flatter than either). Linear in each, so the demo draws them as two patterns, the
# broad one at OVER's alpha, and meets the pictures pixel for pixel.
SWELL2, SWELL2_BASE, OVER, SPREAD = 13, .45, .4, 1.3


def world_offsets() -> dict:
    """The demo's OFFSET (demo/server.py): where each map lies on its one world."""
    import ast
    import re
    src = open(os.path.join(ROOT, "demo", "server.py"), encoding="utf-8").read()
    return ast.literal_eval(re.search(r"^OFFSET = (\{.*\})", src, re.M).group(1))


def map_tiles(inst: int) -> dict:
    """Data/Tiles.lua's tiles of one map: key -> minimap FileDataID."""
    import re
    src = open(os.path.join(ROOT, "Data", "Tiles.lua"), encoding="utf-8").read()
    m = re.search(r"\[%d\] = \{ name = .*?tiles = \{(.*?)\} \}" % inst, src, re.S)
    return {int(k): int(v) for k, v in re.findall(r"\[(\d+)\]=(\d+)", m.group(1))}


def swell_texture(seed: int = 2, base: float = 2.5, tiles: int = SWELL) -> np.ndarray:
    """Fractal noise, 0..1, tiles x tiles at PX a tile, seamless: each octave's grid wraps (tiled 3 x 3, resized,
    the middle kept)."""
    n = tiles * PX
    r, out, amp, total, cells = np.random.RandomState(seed), np.zeros((n, n), np.float32), 1.0, 0.0, base
    for _ in range(5):
        k = max(2, int(round(tiles * cells)))
        g = (r.rand(k, k) * 255).astype(np.uint8)
        big = np.asarray(Image.fromarray(np.tile(g, (3, 3))).resize((3 * n, 3 * n), Image.BICUBIC), np.float32) / 255
        out += amp * big[n:2 * n, n:2 * n]
        total, amp, cells = total + amp, amp * .55, cells * 2
    out /= total
    return (out - out.min()) / (out.max() - out.min()) * .8 + .1  # (the octaves sum to a narrow middle: spread it)


def swell_at(texs: tuple, x0: int, y0: int, h: int, w: int) -> np.ndarray:
    """The swell (the fine and broad textures, laid on the world from tile 0, 0) over a picture h x w px whose top left
    is world tile (x0, y0)."""
    def at(tex):
        n = tex.shape[0]
        ys, xs = (np.arange(h) + y0 * PX) % n, (np.arange(w) + x0 * PX) % n
        return tex[np.ix_(ys, xs)]
    fine, broad = texs
    return .5 + ((1 - OVER) * (at(fine) - .5) + OVER * (at(broad) - .5)) * SPREAD


def smooth(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def fractal(seed: int, h: int, w: int, base: float) -> np.ndarray:
    """Noise, 0..1, base blobs a tile."""
    r, out, amp, total, n = np.random.RandomState(seed), np.zeros((h, w), np.float32), 1.0, 0.0, base
    for _ in range(5):
        g = (r.rand(max(2, int(h / PX * n)), max(2, int(w / PX * n))) * 255).astype(np.uint8)
        out += amp * np.asarray(Image.fromarray(g).resize((w, h), Image.BICUBIC), np.float32) / 255
        total, amp, n = total + amp, amp * .55, n * 2
    return out / total


def flood(start: list, h: int, w: int, passable: np.ndarray, seen: np.ndarray) -> None:
    q = deque(start)
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))


def distance(from_: np.ndarray) -> np.ndarray:
    """px to the nearest of from_ (4-way steps)."""
    h, w = from_.shape
    d, q = np.full(from_.shape, 1e6, np.float32), deque()
    for y, x in zip(*np.nonzero(from_)):
        d[y, x] = 0
        q.append((y, x))
    while q:
        y, x = q.popleft()
        v = d[y, x] + 1
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and d[ny, nx] > v:
                d[ny, nx] = v
                q.append((ny, nx))
    return d


def stray(land: np.ndarray, art: np.ndarray) -> np.ndarray:
    """The land nobody painted: a piece of dry terrain whose art is near-black all over."""
    H, W = land.shape
    out, seen = np.zeros(land.shape, bool), np.zeros(land.shape, bool)
    dark = art.max(-1) < 26
    for y, x in zip(*np.nonzero(land)):
        if seen[y, x]:
            continue
        one = np.zeros(land.shape, bool)
        one[y, x] = seen[y, x] = True
        flood([(y, x)], H, W, land, one)
        seen |= one
        if dark[one].mean() > .9:
            out |= one
    return out


def fields(g: Ground, tiles: dict, sea: dict) -> tuple:
    """A map's (c0, r0, c1, r1), its water (bool) and its art (RGB), px at PX a tile."""
    drawn = [k for k in tiles if k not in sea]
    c0, c1 = max(0, min(k // 64 for k in drawn) - PAD), min(64, max(k // 64 for k in drawn) + 1 + PAD)
    r0, r1 = max(0, min(k % 64 for k in drawn) - PAD), min(64, max(k % 64 for k in drawn) + 1 + PAD)
    H, W = (r1 - r0) * PX, (c1 - c0) * PX
    wet, art = np.ones((H, W), bool), np.zeros((H, W, 3), np.float32)
    step = 128 // PX
    for c in range(c0, c1):
        for r in range(r0, r1):
            k, y, x = c * 64 + r, (r - r0) * PX, (c - c0) * PX
            a = g.art(k, PX)
            if g.inst in ART_WATER:
                if a is not None:
                    wet[y:y + PX, x:x + PX] = a.max(-1) < 26
            elif k in g.maid:
                h, water = g.heights_and_water(k)
                wet[y:y + PX, x:x + PX] = (np.isnan(h) | (h < water))[::step, ::step]
            if a is not None:
                art[y:y + PX, x:x + PX] = a
    wet |= stray(~wet, art)
    return (c0, r0, c1, r1), wet, art


def clouds(rgb: np.ndarray, tiles_off: np.ndarray, sky: np.ndarray) -> np.ndarray:
    """Faint clouds by a floating map's land (sky: 1 where the water is its), thinning out over ~3.5 tiles: soft wisps
    (fractal noise, cut), a thin haze under them."""
    H, W = sky.shape
    near = 1 - smooth(0, 3.6, tiles_off + (fractal(7, H, W, .6) - .5) * 2.2)
    wisps = smooth(.4, .78, fractal(9, H, W, .8))
    a = (np.clip(near * wisps + near * .12, 0, 1) * CLOUD_A * sky)[..., None]
    return rgb * (1 - a) + CLOUD * a


def paint(wet: np.ndarray, art: np.ndarray, swell: np.ndarray, addon: bool, sky=None) -> np.ndarray:
    """The ocean over a picture's water and art, RGBA. addon: the swell fading out by the edge, to the window's flat
    backdrop; else (the demo's) the world's swell to the edge, and three tiles in from it the far water's own colour
    (where the picture stops short of DEEP)."""
    H, W = wet.shape
    seen = np.zeros((H, W), bool)
    start = [(y, x) for y in range(H) for x in (0, W - 1) if wet[y, x]] + [(y, x) for x in range(W) for y in (0, H - 1) if wet[y, x]]
    for s in start:
        seen[s] = True
    flood(start, H, W, wet, seen)
    tiles_off = distance(~seen) / PX
    edge = distance(np.pad(np.zeros((H - 2, W - 2), bool), 1, constant_values=True)) / PX
    drift = fractal(1, H, W, .7)
    t = np.clip(tiles_off + (drift - .5) * 1.4, 0, None)
    a0, a1, a2 = smooth(0, .22, tiles_off + (drift - .5) * .12)[..., None], smooth(.1, 1.3, t)[..., None], smooth(1.0, 4.5, t)[..., None]
    rgb = ((SHORE * (1 - a0) + SHALLOW * a0) * (1 - a1) + MID * a1) * (1 - a2) + DEEP * a2
    if sky is not None:  # floating: no coast, the deep water's colour right up to the land
        s = sky[..., None]
        rgb = rgb * (1 - s) + (MID * (1 - smooth(0, 1.5, t)[..., None]) * .35 + DEEP * (.65 + .35 * smooth(0, 1.5, t)[..., None])) * s
    wave = ((swell - .5) * SWELL_AMP)[..., None]
    if addon:
        rgb = rgb * (1 + wave * smooth(0, 2, edge)[..., None])
    else:
        e = smooth(0, 3, edge)[..., None]
        rgb = (rgb * (1 + wave)) * e + (DEEP * (1 + wave)) * (1 - e)
    # seen through where Blizzard's water has colour (their near-black by the land: SHORE over it)
    colour = smooth(34, 72, art.max(-1))
    near = smooth(0, .05, tiles_off)
    far = smooth(.3, 1.4, tiles_off)
    if sky is not None:
        rgb = clouds(rgb, tiles_off, sky)
        far = far * (1 - sky) + sky  # (over the art's own shallows too: a floating map has none)
    alpha = near * (1 - colour * (1 - far)) * seen
    return np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8)


def world_ocean(parts: dict, at: dict, swell_tex: np.ndarray) -> tuple:
    """The demo's one ocean, over every map at its place on the world (no picture overlaps another): the world box
    (c0, r0, c1, r1) and its RGBA. parts: [inst] = fields(...)."""
    boxes = {i: (b[0] + at[i][0], b[1] + at[i][1], b[2] + at[i][0], b[3] + at[i][1]) for i, (b, _, _) in parts.items()}
    c0, r0 = min(b[0] for b in boxes.values()), min(b[1] for b in boxes.values())
    c1, r1 = max(b[2] for b in boxes.values()), max(b[3] for b in boxes.values())
    wet, art = np.ones(((r1 - r0) * PX, (c1 - c0) * PX), bool), np.zeros(((r1 - r0) * PX, (c1 - c0) * PX, 3), np.float32)
    sky = np.zeros(wet.shape, np.float32)  # a floating map's picture box
    for i in SKY & set(boxes):
        b = boxes[i]
        sky[(b[1] - r0) * PX:(b[3] - r0) * PX, (b[0] - c0) * PX:(b[2] - c0) * PX] = 1
    for i, (_, w, a) in parts.items():
        x, y = (boxes[i][0] - c0) * PX, (boxes[i][1] - r0) * PX
        h_, w_ = w.shape
        wet[y:y + h_, x:x + w_] &= w  # (land is any map's)
        np.maximum(art[y:y + h_, x:x + w_], a, out=art[y:y + h_, x:x + w_])
    return (c0, r0, c1, r1), paint(wet, art, swell_at(swell_tex, c0, r0, *wet.shape), addon=False, sky=sky)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "mm-terrain"), help="the terrain read so far")
    ap.add_argument("--bake", help="also write the web demo's pictures here (sea.json, *.webp)")
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    import maplint
    data = maplint.Data(os.path.join(ROOT, "Data"))
    out, parts = {}, {}
    swell_tex, at = (swell_texture(), swell_texture(5, SWELL2_BASE, SWELL2)), world_offsets()
    for inst, name in NAMES.items():
        tiles, sea = data.tiles.get(inst) or map_tiles(inst), data.sea.get(inst, set())  # (maplint's: the continents)
        box, wet, art = parts[inst] = fields(Ground(src, inst, tiles, sea, ns.cache), tiles, sea)
        pic = paint(wet, art, swell_at(swell_tex, box[0] + at[inst][0], box[1] + at[inst][1], *wet.shape), addon=True,
                    sky=np.ones(wet.shape, np.float32) if inst in SKY else None)
        w, h = (box[2] - box[0]) * SHIP, (box[3] - box[1]) * SHIP
        small = np.asarray(Image.fromarray(pic).resize((w, h), Image.LANCZOS))
        tw, th = 2 ** int(np.ceil(np.log2(w))), 2 ** int(np.ceil(np.log2(h)))
        rows = [[(0, 0, 0, 0)] * tw for _ in range(th)]
        for y in range(h):
            rows[y][:w] = [tuple(int(v) for v in p) for p in small[y]]
        with open(os.path.join(ROOT, "Textures", f"Sea{name}.tga"), "wb") as f:
            f.write(write_tga(tw, th, rows))
        out[inst] = (name, box, tw, th)
        log(f"[{inst}] {box}: {w} x {h} in {tw} x {th}")
    if ns.bake:
        box, pic = world_ocean(parts, at, swell_tex)
        os.makedirs(ns.bake, exist_ok=True)
        Image.fromarray(pic).save(os.path.join(ns.bake, "world-sea.webp"), quality=85, method=4)
        for tex, file in zip(swell_tex, ("swell.webp", "swell2.webp")):  # each alone, spread: the page blends them
            far = (DEEP * (1 + ((tex - .5) * SPREAD * SWELL_AMP)[..., None])).clip(0, 255).astype(np.uint8)
            Image.fromarray(far).save(os.path.join(ns.bake, file), lossless=True, method=6)
        with open(os.path.join(ns.bake, "sea.json"), "w") as f:
            json.dump({"deep": [int(v) for v in DEEP], "file": "world-sea.webp", "col": box[0], "row": box[1],
                       "w": box[2] - box[0], "h": box[3] - box[1], "swell": {"file": "swell.webp", "tiles": SWELL},
                       "over": {"file": "swell2.webp", "tiles": SWELL2, "alpha": OVER}}, f, separators=(",", ":"))
        log(f"demo: {box} (world tiles)")
    with open(os.path.join(ROOT, "Data", "Sea.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- GENERATED by tools/gen_sea.py from the terrain of {src.product} {src.version}. Do not edit.\n")
        f.write("-- [inst] = the continent's ocean (ui/Sea.lua): file (under the addon's folder, no extension), the tile rect it covers,\n")
        f.write("--   px a tile, the texture's size; deep: the colour past it\n")
        f.write(data_head("Sea"))
        f.write("D.Sea = { deep = { %.3f, %.3f, %.3f },\n" % tuple(DEEP / 255))
        for inst, (name, b, tw, th) in out.items():
            f.write(f'  [{inst}] = {{ file = "Textures\\\\Sea{name}", c0 = {b[0]}, r0 = {b[1]}, c1 = {b[2]}, r1 = {b[3]}, px = {SHIP}, w = {tw}, h = {th} }},\n')
        f.write("}\n")


if __name__ == "__main__":
    main()

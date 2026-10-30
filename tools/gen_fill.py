#!/usr/bin/env python3
"""Generate Data/Fill.lua and Textures/FillMask*.tga: the map's broken art rebuilt from pieces of the game's own tiles.

Blizzard's minimap tiles have unfinished land in them: flat filler, stepped patches of other art (tools/maplint.py's
flat-land, patch-edge and seam issues). What to rebuild is the map review's call (M6): the issues accepted in
docs/map-review.json, spreading over chunks the game's terrain files show as the same filler: one painted texture over
the whole chunk (tex0 ADT: MCLY, MCAL) and next to no detail in the art. Real ground is finely painted, so it's safe, and
any block of BLOCK such chunks is rebuilt whether the review named it or not. Landmarks are left alone and never copied:
chunks with a building on them (obj0 MODF) or with vivid px out of keeping with the rest.

Each hole is quilted (Efros & Freeman's image quilting, guided): square PIECE-chunk pieces, on a grid, overlapping by a
chunk, each cut from good ground of a nearby zone, inside one tile, and chosen for how well it meets what's round it,
the terrain's real shape under it (MCVT heights, hillshaded) and the tone that belongs there (the ground round the hole
smoothed across it), with a gain per piece (vertex colour, which can only darken) to bring it there. A piece that carries on from
its neighbour's source has no seam at all, and is favoured. Then PASSES of each piece chosen again against all its
neighbours, with the irregular soft-edged mask (Textures/FillMask*.tga) that hides its seam best. Deterministic.

The addon draws each piece from Blizzard's texture at runtime (ui/Fill.lua; NOTICE.md): this file holds where they go.
Draw order: a piece's sublevel (0-3) from its grid place, so neighbours always lie the same way up.

  python3 tools/gen_fill.py local "/Applications/World of Warcraft" wow_classic_beta --bake demo/fill
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys
import tempfile

import numpy as np
from PIL import Image

from gen_clouds import blp_rgba, components, grow, places
from mmtools.formats import adt_chunks, adt_liquids, adt_modf, iter_chunks, wdt_maid
from mmtools.log import log
from mmtools.luaout import data_head, load_data
from mmtools.sources import add_source_args, source_from_args
from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WDT = {0: 775971, 1: 782779}
TILE = 1600 / 3
PX = 8              # px a chunk the choosing works at
PIECE = 6           # chunks a piece's side
OVERLAP = 2         # chunks neighbours share
REACH = 4           # tiles of ground read round a region
RING = 40           # chunks from a hole a piece may come from
ZONE_NEAR = 24      # chunks round a piece whose zones it may come from
BLOCK = 48         # chunks of filler together: rebuilt whether the review named them or not
STANDS_OUT = 60     # a chunk with over 1% of its px this far from its mean (0-255)...
VIVID = 120         # ...and this saturated has a landmark in it
FLAT = 6            # a chunk's art this flat (mean std of its px, 0-255) can be filler
SPREAD = 40         # chunks a hole may spread over filler
KEEP_RANGE = 70     # percentile: pieces with less contrast than this
KEEP_TONE = 70      # percentile: ...nearer the region's usual tone than this
KEEP_SPECK = 75     # percentile: ...and fewer outlying px (buildings, roads) than this
W_SHAPE = 8.0       # the weights: the terrain's shape
W_TONE = 0.25       # ...the tone that belongs here
W_NEAR = 0.03       # ...a chunk's distance to the source
W_ZONE = 0.1        # ...another zone
W_USED = 0.6        # ...each use of the source so far
CARRY = 0.45        # a piece that carries on from a neighbour's source, its cost by this
TONE_CAP = 32       # the most a piece's tone may be off, after its gain
GAIN = 0.6          # the least gain
PASSES = 2          # further passes
MASKS = 8           # soft-edged masks to choose from
GUIDE_BLUR = 6      # chunks: the guide's line between two sides, softened
FLAT_WATER = 28     # a chunk with no channel over this is water or dark: no hole, no source


def wobble(seed: int, n: int) -> np.ndarray:
    """A soft-edged mask, n px: 1 inside, fading over the overlap, the fade's line wandering."""
    r = np.random.RandomState(seed)
    noise = np.asarray(Image.fromarray((r.rand(7, 7) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC), np.float32) / 255 - .5
    d = np.minimum.outer(np.arange(n), n - 1 - np.arange(n)) + 1.0
    px = OVERLAP * n / PIECE
    return np.clip((d + noise * px * 1.6) / (px * 1.2), 0, 1)


def layer_alpha(mcal: bytes, off: int, size: int, flags: int) -> np.ndarray:
    d = mcal[off:off + size]
    if flags & 0x200:  # compressed
        o, p = bytearray(), 0
        while len(o) < 4096 and p < len(d):
            c, p = d[p], p + 1
            n = c & 0x7f
            if c & 0x80:
                o += d[p:p + 1] * n
                p += 1
            else:
                o += d[p:p + n]
                p += n
        a = np.frombuffer(bytes(o[:4096]).ljust(4096, b"\0"), np.uint8)
    elif len(d) >= 4096:
        a = np.frombuffer(d[:4096], np.uint8)
    else:
        b = np.frombuffer(d[:2048].ljust(2048, b"\0"), np.uint8)
        a = np.empty(4096, np.uint8)
        a[::2], a[1::2] = (b & 15) * 17, (b >> 4) * 17
    return a.reshape(64, 64).astype(np.float32) / 255


def painted(buf: bytes) -> np.ndarray:
    """A tex0 ADT's dominant texture (a FileDataID), 8 x 8 a chunk."""
    out, mdid, i = np.zeros((128, 128), np.int64), [], 0
    for m, off, size in iter_chunks(buf):
        if m == b"MDID":
            mdid = list(struct.unpack_from(f"<{size // 4}I", buf, off))
        elif m == b"MCNK":
            ly, mcal = [], b""
            for m2, o2, s2 in iter_chunks(buf[off:off + size]):
                if m2 == b"MCLY":
                    ly = [struct.unpack_from("<IIII", buf, off + o2 + k * 16) for k in range(s2 // 16)]
                elif m2 == b"MCAL":
                    mcal = buf[off + o2:off + o2 + s2]
            if ly:
                w, rest = np.ones((64, 64, len(ly)), np.float32), np.ones((64, 64), np.float32)
                for k in range(len(ly) - 1, 0, -1):
                    nx = ly[k + 1][2] if k + 1 < len(ly) else len(mcal)
                    a = layer_alpha(mcal, ly[k][2], nx - ly[k][2], ly[k][1])
                    w[:, :, k], rest = rest * a, rest * (1 - a)
                w[:, :, 0] = rest
                ids = np.array([mdid[l[0]] if l[0] < len(mdid) else 0 for l in ly])
                out[(i // 16) * 8:(i // 16) * 8 + 8, (i % 16) * 8:(i % 16) * 8 + 8] = ids[w.reshape(8, 8, 8, 8, -1).mean((1, 3)).argmax(-1)]
            i += 1
    return out


class Ground:
    """A continent's tiles and terrain, read when asked."""

    def __init__(self, src, inst: int, tiles: dict, sea: dict, cache: str):
        self.src, self.inst, self.tiles, self.sea, self.cache = src, inst, tiles, sea, cache
        self.maid = wdt_maid(src.read(WDT[inst]))

    def art(self, key: int, n: int) -> np.ndarray | None:
        if key not in self.tiles or key in self.sea:
            return None
        return np.asarray(blp_rgba(self.src.read(self.tiles[key])).convert("RGB").resize((n, n), Image.LANCZOS), np.float32)

    def buildings(self, key: int) -> np.ndarray:
        """The chunks of a tile with a building (WMO) on them, 16 x 16."""
        path = os.path.join(self.cache, f"{self.inst}_{key}.built.npy")
        if os.path.exists(path):
            return np.load(path)
        out = np.zeros((16, 16), bool)
        t = self.maid.get(key)
        b = t and t.obj0 and self.src.read(t.obj0)
        for m in adt_modf(b) if b else ():
            cx = lambda v: (v / TILE - key // 64) * 16
            cy = lambda v: (v / TILE - key % 64) * 16
            out[max(0, int(cy(m.mn[2]))):max(0, int(cy(m.mx[2])) + 1), max(0, int(cx(m.mn[0]))):max(0, int(cx(m.mx[0])) + 1)] = True
        np.save(path, out)
        return out

    def heights_and_water(self, key: int) -> tuple[np.ndarray, np.ndarray]:
        """Heights and the water's surface (-inf: none), 128 x 128."""
        path = os.path.join(self.cache, f"{self.inst}_{key}.water.npy")
        h, _ = self.terrain(key)
        if os.path.exists(path):
            return h, np.load(path)
        w = np.full((16, 16), -np.inf, np.float32)
        t = self.maid.get(key)
        b = t and t.root_adt and self.src.read(t.root_adt)
        for l in adt_liquids(b) if b else ():
            w[l.iy, l.ix] = max(w[l.iy, l.ix], l.surface)
        w = w.repeat(8, 0).repeat(8, 1)
        np.save(path, w)
        return h, w

    def terrain(self, key: int) -> tuple[np.ndarray, np.ndarray]:
        """Heights and painted textures, 128 x 128."""
        path = os.path.join(self.cache, f"{self.inst}_{key}.npz")
        if os.path.exists(path):
            z = np.load(path)
            return z["h"], z["t"]
        h, tex = np.full((128, 128), np.nan, np.float32), np.zeros((128, 128), np.int64)
        t = self.maid.get(key)
        b = t and t.root_adt and self.src.read(t.root_adt)
        for c in adt_chunks(b) if b else ():
            if c.heights is not None:
                for y in range(8):
                    for x in range(8):
                        h[c.iy * 8 + y, c.ix * 8 + x] = c.z + c.heights[y * 17 + x]
        b0 = t and t.tex0 and self.src.read(t.tex0)
        if b0:
            tex = painted(b0)
        os.makedirs(self.cache, exist_ok=True)
        np.savez_compressed(path, h=h, t=tex)
        return h, tex


def spread(t: np.ndarray, n: int, within: np.ndarray | None = None) -> np.ndarray:
    for _ in range(n):
        g = grow(t, 1)
        t = t | (g if within is None else g & within)
    return t


def filler(g: Ground, tiles: dict, sea: dict) -> np.ndarray:
    """The blocks of filler anywhere on the map, by chunk: one texture over each chunk, its art flat, and many of them together."""
    found = np.zeros((64 * 16, 64 * 16), bool)
    for k in tiles:
        a = None if k in sea else g.art(k, 16 * PX)
        if a is None:
            continue
        _, t = g.terrain(k)
        cells = lambda v: v.reshape(16, PX, 16, PX, *v.shape[2:])
        flat = (cells(t).max((1, 3)) == cells(t).min((1, 3))) & (cells(a).std((1, 3)).mean(-1) < FLAT) & (cells(a).mean((1, 3)).max(-1) >= FLAT_WATER)
        found[k % 64 * 16:k % 64 * 16 + 16, k // 64 * 16:k // 64 * 16 + 16] = flat
    out = np.zeros_like(found)
    for sy, sx in components(found):
        if found[sy, sx].sum() >= BLOCK:
            out[sy, sx] |= found[sy, sx]
    return out


def regions(accepted: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Tile boxes round the accepted places, merged where they touch."""
    boxes = [[sx.start // 16 - 1, sy.start // 16 - 1, (sx.stop - 1) // 16 + 2, (sy.stop - 1) // 16 + 2] for sy, sx in components(grow(accepted, 3))]
    again = True
    while again:
        again = False
        for i, a in enumerate(boxes):
            for j, b in enumerate(boxes[i + 1:], i + 1):
                if a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]:
                    boxes[i] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
                    boxes.pop(j)
                    again = True
                    break
            if again:
                break
    return [tuple(int(v) for v in b) for b in boxes]


def quilt(g: Ground, box: tuple, accepted: np.ndarray, flagged: np.ndarray, zones: np.ndarray) -> list[dict]:
    """The pieces for a region, in draw order."""
    c0, r0, c1, r1 = box
    C0, R0, C1, R1 = max(0, c0 - REACH), max(0, r0 - REACH), min(64, c1 + REACH), min(64, r1 + REACH)
    P = 16 * PX
    H, W = (R1 - R0) * P, (C1 - C0) * P
    img, heights, tex = np.zeros((H, W, 3), np.float32), np.full((H, W), np.nan, np.float32), np.zeros((H, W), np.int64)
    built = np.zeros((H, W), bool)
    have = np.zeros((R1 - R0, C1 - C0), bool)
    for c in range(C0, C1):
        for r in range(R0, R1):
            y, x = (r - R0) * P, (c - C0) * P
            a = g.art(c * 64 + r, P)
            if a is not None:
                img[y:y + P, x:x + P], have[r - R0, c - C0] = a, True
            heights[y:y + P, x:x + P], tex[y:y + P, x:x + P] = g.terrain(c * 64 + r)
            built[y:y + P, x:x + P] = g.buildings(c * 64 + r).repeat(PX, 0).repeat(PX, 1)
    heights = np.nan_to_num(heights, nan=float(np.nanmean(heights)))
    gy, gx = np.gradient(heights)
    shade = np.clip((gx - gy) / 5, -1, 1).astype(np.float32)
    sub = lambda m: m[R0 * 16:R1 * 16, C0 * 16:C1 * 16]
    h, w = H // PX, W // PX
    cells = lambda a: a.reshape(h, PX, w, PX, *a.shape[2:])
    tone = cells(img).mean((1, 3))
    detail = cells(img).std((1, 3)).mean(-1)
    uniform = cells(tex).max((1, 3)) == cells(tex).min((1, 3))
    land = np.kron(have, np.ones((16, 16), bool))
    dark = tone.max(-1) < FLAT_WATER
    hole = sub(accepted) & land
    if not hole.any():
        return []
    corner = tex[::PX, ::PX]
    hole = spread(hole, SPREAD, uniform & (detail < FLAT) & ~dark & land & np.isin(corner, np.unique(corner[hole])))
    hole = grow(hole, 1) & land & ~dark
    # what stays: buildings and whatever stands out from the ground, a landmark; never copied, never covered
    px_ = cells(img).transpose(0, 2, 1, 3, 4)
    vivid = (np.abs(px_ - tone[:, :, None, None]).max(-1) > STANDS_OUT) & (px_.max(-1) - px_.min(-1) > VIVID)
    feature = (vivid.mean((2, 3)) > .01) | (cells(built).any((1, 3)) & (detail >= FLAT))
    hole &= ~feature
    bad = hole | sub(flagged) | (uniform & (detail < FLAT)) | feature
    zs = sub(zones)
    ring = spread(hole, RING)
    # the sources: whole pieces of good ground, inside one tile
    ys, xs = [], []
    for y in range(h - PIECE + 1):
        for x in range(w - PIECE + 1):
            if ring[y, x] and (y % 16) + PIECE <= 16 and (x % 16) + PIECE <= 16 and land[y, x] \
                    and not bad[y:y + PIECE, x:x + PIECE].any() and not dark[y:y + PIECE, x:x + PIECE].any():
                ys.append(y)
                xs.append(x)
    if len(ys) < 30:
        log(f"  {box}: {len(ys)} sources: left as it is")
        return []
    ys, xs = np.array(ys), np.array(xs)
    b = PIECE * PX
    block = lambda a, y, x: a[y * PX:y * PX + b, x * PX:x * PX + b]
    mean = np.stack([tone[y:y + PIECE, x:x + PIECE].mean((0, 1)) for y, x in zip(ys, xs)])
    spreadout = np.array([np.abs(tone[y:y + PIECE, x:x + PIECE] - m).max() for y, x, m in zip(ys, xs, mean)])
    off = np.linalg.norm(mean - np.median(mean, 0), axis=1)
    speck = []
    for y, x in zip(ys, xs):
        v = block(img, y, x)
        lum = v.mean(-1)
        speck.append((np.percentile(lum, 99.5) - np.percentile(lum, .5), np.percentile(np.abs(v - v.mean((0, 1))).max(-1), 99.5)))
    speck = np.array(speck)
    keep = (spreadout < np.percentile(spreadout, KEEP_RANGE)) & (off < np.percentile(off, KEEP_TONE)) \
        & (speck[:, 0] < np.percentile(speck[:, 0], KEEP_SPECK)) & (speck[:, 1] < np.percentile(speck[:, 1], KEEP_SPECK))
    ys, xs, mean = ys[keep], xs[keep], mean[keep]
    zone_of = np.array([np.bincount(zs[y:y + PIECE, x:x + PIECE].ravel()).argmax() for y, x in zip(ys, xs)])
    pics = np.stack([block(img, y, x) for y, x in zip(ys, xs)])[:, ::2, ::2]
    shapes = np.stack([block(shade, y, x) for y, x in zip(ys, xs)])[:, ::4, ::4]
    index = {(int(y), int(x)): i for i, (y, x) in enumerate(zip(ys, xs))}
    # the tone that belongs: the nearest good ground's, a hole split between its sides (an average of them would match neither)
    guide, known_tone = tone.copy(), ~hole & land
    while not known_tone[hole].all():
        p, k = np.pad(guide * known_tone[..., None], ((1, 1), (1, 1), (0, 0))), np.pad(known_tone, 1).astype(np.float32)
        n = k[:-2, 1:-1] + k[2:, 1:-1] + k[1:-1, :-2] + k[1:-1, 2:]
        v = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / np.maximum(n, 1)[..., None]
        new = (n > 0) & ~known_tone
        if not new.any():
            break
        guide[new], known_tone = v[new], known_tone | new
    for _ in range(GUIDE_BLUR):
        p = np.pad(guide, ((1, 1), (1, 1), (0, 0)), mode="edge")
        v = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4
        guide[hole] = v[hole]
    masks = [wobble(i, b)[..., None] for i in range(MASKS)]
    step = PIECE - OVERLAP
    spots = {(min(h - PIECE, y // step * step), min(w - PIECE, x // step * step)) for y, x in zip(*np.nonzero(hole))}
    inner = lambda a, p: a[p[0] + 1:p[0] + PIECE - 1, p[1] + 1:p[1] + PIECE - 1]
    spots = [p for p in spots if hole[p[0]:p[0] + PIECE, p[1]:p[1] + PIECE].any() and not inner(feature, p).any()]
    holepx = hole.repeat(PX, 0).repeat(PX, 1)
    used, chosen = np.zeros(len(ys)), {}

    def draw(pic, spot, j, gain, m):
        y, x = spot
        a = masks[m]
        pic[y * PX:y * PX + b, x * PX:x * PX + b] = block(pic, y, x) * (1 - a) + block(img, ys[j], xs[j]) * gain * a

    def choose(spot, under, known):
        y, x = spot
        k = known[::2, ::2, None]
        cost = (((pics - under[::2, ::2]) ** 2) * k).sum((1, 2, 3)) / max(float(k.sum()) * 3, 1) if k.any() else np.zeros(len(pics))
        want = guide[y:y + PIECE, x:x + PIECE].mean((0, 1))
        gain = np.clip(want / np.maximum(mean, 1), GAIN, 1.0)
        toned = mean * gain
        cost = cost + W_TONE * ((toned - want) ** 2).sum(1) / 3
        cost = cost + W_SHAPE * ((shapes - block(shade, y, x)[::4, ::4]) ** 2).mean((1, 2))
        cost = cost + W_NEAR * np.hypot(ys - y, xs - x)
        here = np.bincount(zs[y:y + PIECE, x:x + PIECE].ravel()).argmax()
        cost = cost * (1 + W_ZONE * (zone_of != here)) * (1 + used * W_USED)
        no = np.linalg.norm(toned - want, axis=1) > TONE_CAP
        ya, xa = max(0, y - ZONE_NEAR), max(0, x - ZONE_NEAR)
        near = zs[ya:y + PIECE + ZONE_NEAR, xa:x + PIECE + ZONE_NEAR][~hole[ya:y + PIECE + ZONE_NEAR, xa:x + PIECE + ZONE_NEAR]]
        if near.size:
            other = ~np.isin(zone_of, np.unique(near))
            if (~(no | other)).sum() > 20:
                no = no | other
        if (~no).sum() > 20:
            cost[no] = 1e12
        for q, c in chosen.items():
            if q != spot and abs(q[0] - y) <= step and abs(q[1] - x) <= step:
                jn = index.get((int(ys[c[0]]) + y - q[0], int(xs[c[0]]) + x - q[1]))
                if jn is not None and not no[jn]:
                    cost[jn] = cost[jn] / (1 + used[jn] * W_USED) * CARRY
        j = int(np.argmin(cost))
        return j, gain[j]

    # first pass: the spot with most known round it next
    res, known, left = img.copy(), ~holepx, list(spots)
    while left:
        i = int(np.argmax([block(known, y, x).mean() for y, x in left]))
        spot = left.pop(i)
        j, gain = choose(spot, block(res, *spot), block(known, *spot))
        used[j] += 1
        used[np.hypot(ys - ys[j], xs - xs[j]) < PIECE] += .3
        m = (spot[0] * 7 + spot[1] * 3) % MASKS
        draw(res, spot, j, gain, m)
        known[spot[0] * PX:spot[0] * PX + b, spot[1] * PX:spot[1] * PX + b] = True
        chosen[spot] = (j, gain, m)
    # draw order: by grid place; further passes against all the neighbours
    sub_of = lambda s: (s[0] // step % 2) * 2 + s[1] // step % 2
    order = sorted(chosen, key=lambda s: (sub_of(s), s))
    for _ in range(PASSES):
        for spot in order:
            y, x = spot
            near = [q for q in order if abs(q[0] - y) < PIECE and abs(q[1] - x) < PIECE and q != spot]
            ya, xa = max(0, y - PIECE), max(0, x - PIECE)
            pic = img[ya * PX:(y + 2 * PIECE) * PX, xa * PX:(x + 2 * PIECE) * PX].copy()
            for q in near:
                c = chosen[q]
                qy, qx = (q[0] - ya) * PX, (q[1] - xa) * PX
                a = masks[c[2]]
                sp = pic[qy:qy + b, qx:qx + b]
                sp[:] = sp * (1 - a[:sp.shape[0], :sp.shape[1]]) + (block(img, ys[c[0]], xs[c[0]]) * c[1])[:sp.shape[0], :sp.shape[1]] * a[:sp.shape[0], :sp.shape[1]]
            under = pic[(y - ya) * PX:(y - ya) * PX + b, (x - xa) * PX:(x - xa) * PX + b]
            empty = block(holepx, y, x).copy()
            for q in near:
                dy, dx = (q[0] - y) * PX, (q[1] - x) * PX
                empty[max(0, dy):min(b, dy + b), max(0, dx):min(b, dx + b)] = False
            used[chosen[spot][0]] -= 1
            j, gain = choose(spot, under, ~empty)
            used[j] += 1
            d = ((block(img, ys[j], xs[j]) * gain - under) ** 2).sum(-1)
            m = int(np.argmin([(d * (mk[..., 0] * (1 - mk[..., 0]))).sum() for mk in masks]))
            chosen[spot] = (j, gain, m)
    # back to whole-map chunks and tiles
    out = []
    for spot in order:
        j, gain, m = chosen[spot]
        sy, sx = int(ys[j]) + R0 * 16, int(xs[j]) + C0 * 16
        out.append({"col": spot[1] + C0 * 16, "row": spot[0] + R0 * 16, "key": (sx // 16) * 64 + sy // 16, "sc": sx % 16, "sr": sy % 16,
                    "gain": [round(float(v), 3) for v in gain], "mask": m + 1, "sub": sub_of(spot)})
    return out


def bake(g: Ground, pieces: list, path: str, px: int) -> dict:
    """The pieces as one see-through picture (the web demo's: it has no masks to draw with): its box in tiles."""
    c0, r0 = min(p["col"] for p in pieces), min(p["row"] for p in pieces)
    c1, r1 = max(p["col"] for p in pieces) + PIECE, max(p["row"] for p in pieces) + PIECE
    n = PIECE * px
    pic, alpha = np.zeros(((r1 - r0) * px, (c1 - c0) * px, 3), np.float32), np.zeros(((r1 - r0) * px, (c1 - c0) * px, 1), np.float32)
    masks = [wobble(i, n)[..., None] for i in range(MASKS)]
    tiles = {}
    for p in pieces:
        if p["key"] not in tiles:
            tiles[p["key"]] = g.art(p["key"], 16 * px)
        src = tiles[p["key"]][p["sr"] * px:p["sr"] * px + n, p["sc"] * px:p["sc"] * px + n] * np.array(p["gain"])
        y, x, a = (p["row"] - r0) * px, (p["col"] - c0) * px, masks[p["mask"] - 1]
        pic[y:y + n, x:x + n] = pic[y:y + n, x:x + n] * (1 - a) + src * a  # (premultiplied)
        alpha[y:y + n, x:x + n] = alpha[y:y + n, x:x + n] * (1 - a) + a
    rgb = pic / np.maximum(alpha, 1e-3)
    Image.fromarray(np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8), "RGBA").save(path, quality=88, method=4)
    return {"col": c0 / 16, "row": r0 / 16, "w": (c1 - c0) / 16, "h": (r1 - r0) / 16}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--issues", default=os.path.join(ROOT, "demo", "lint", "issues.json"))
    ap.add_argument("--review", default=os.path.join(ROOT, "docs", "map-review.json"))
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "mm-fill"), help="the terrain read so far")
    ap.add_argument("--bake", help="also write the web demo's pictures here (fill.json, *.webp)")
    ap.add_argument("--bake-px", type=int, default=16, help="px a chunk")
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    issues = json.load(open(ns.issues))["issues"]
    decisions = json.load(open(ns.review))["decisions"]
    everything = {i["id"]: {"status": "accepted"} for i in issues if i["kind"] in ("flat-land", "patch-edge", "seam")}
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import maplint
    data = maplint.Data(os.path.join(ROOT, "Data"))
    maps, baked = {}, {}
    for inst in (0, 1):
        g = Ground(src, inst, data.tiles[inst], data.sea[inst], ns.cache)
        accepted, flagged = places(issues, decisions, inst) | filler(g, data.tiles[inst], data.sea[inst]), grow(places(issues, everything, inst), 1)
        zones = np.asarray(data.zone_grid[inst])
        maps[inst], baked[inst] = [], []
        for n, box in enumerate(regions(accepted)):
            pieces = quilt(g, box, accepted, flagged, zones)
            maps[inst] += pieces
            log(f"[{inst}] {box}: {len(pieces)} pieces")
            if ns.bake and pieces:
                os.makedirs(ns.bake, exist_ok=True)
                name = f"{inst}_{n}.webp"
                baked[inst].append({"file": name, **bake(g, pieces, os.path.join(ns.bake, name), ns.bake_px)})
    if ns.bake:
        with open(os.path.join(ns.bake, "fill.json"), "w") as f:
            json.dump({str(k): v for k, v in baked.items()}, f, separators=(",", ":"))
    n = 32
    for i in range(MASKS):
        m = wobble(i, n)
        rows = [[(255, 255, 255, int(round(v * 255))) for v in line] for line in m]
        with open(os.path.join(ROOT, "Textures", f"FillMask{i + 1}.tga"), "wb") as f:
            f.write(write_tga(n, n, rows))
    with open(os.path.join(ROOT, "Data", "Fill.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- GENERATED by tools/gen_fill.py from the map review's accepted issues ({os.path.relpath(ns.review, ROOT)}), the filler it finds, the terrain and tiles of {src.product} {src.version}. Do not edit.\n")
        f.write("-- [inst] = { col, row, file, sc, sr, r, g, b, mask, sub, ... }: a piece PIECE chunks a side: where (chunks), its source\n")
        f.write("--   (a tile's FileDataID, the chunk in it), gain, Textures/FillMask<mask>, sublevel\n")
        f.write(data_head("Fill"))
        f.write(f"D.Fill = {{ piece = {PIECE},\n")
        for inst, pieces in maps.items():
            f.write(f"  [{inst}] = {{\n")
            for p in pieces:
                f.write("    %d, %d, %d, %d, %d, %g, %g, %g, %d, %d,\n" % (p["col"], p["row"], data.tiles[inst][p["key"]], p["sc"], p["sr"], *p["gain"], p["mask"], p["sub"]))
            f.write("  },\n")
        f.write("}\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate Data/Ground.lua.new and demo/ground_out/masks/GroundMask*.tga: the tiles' flat filler given a grain of its own material.

Where the tiles have flat single-colour land, the addon draws a ground texture of the game's over it, large. Nothing is baked: each
patch is four draws of Blizzard's textures, by FileDataID, under one mask of ours.

What makes that work at map scale:
- The textures' alpha is sparse (a shine map: grass blades, cracks, the tops of pebbles), and BLEND honours it. So what shows is flecks,
  not the whole texture, and the tone Blizzard painted stays between them.
- Flecks darker than the tone and flecks lighter (vertex colours, from the tone over the texture's alpha-weighted colour), balanced by how
  much of the ground each covers, so the mean tone holds. Two scales of each, in ratios that never line up, all turned off the grid: no lattice.
- Their strength goes by how much the texture's alpha varies as seen: the less, the stronger. One too faint, or too dark to make light
  flecks, lends the job to a texture of its colour (so not always its material).
- A texture's size goes by the size of its flecks, against the grass's.
- The mask also carries density: a wander a couple of tiles wide and a finer one, so there are denser and sparser places, not a carpet.
- Coords are anchored to the world, not the patch: patches of a texture meet with no join, and need no overlap.

Which ground: m.flat, opened (no specks, no threads), then out to where the art itself stays smooth and of that tone, px by px, so
the edge follows the true flat shape rather than the chunk grid. It fades inside that. Water, buildings and near-black are out.

The textures come from the source, or failing that from another product of the install (--tex-product): a beta install may not hold them.

  python3 tools/gen_ground.py local "/Applications/World of Warcraft" wow_classic_beta --bake demo/ground --sites /tmp/ground
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import tempfile
from collections import Counter

import numpy as np
from PIL import Image, ImageFilter

from flatmap import read
from gen_clouds import blp_rgba, components, grow
from mmtools.casc import CascStore
from mmtools.log import log
from mmtools.sources import add_source_args, source_from_args
from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYERS = ((1.13, .41, .13, .37), (1.61, 1.93, .61, .07), (2.57, 2.71, .29, .83), (3.49, 4.27, .71, .47))  # repeats a tile side, turn (radians), offset: coarse dark, coarse light, fine dark, fine light
STRENGTH = .7       # a fleck's distance from the tone, for the grass (GRASS)...
MOST = .85          # ...and for the rest what makes them as visible (by how much their alpha varies, as seen), at most this
DARK = .85          # the dark flecks' distance by the light's: they cover what's under them more than the light's do, on average
SPARSEST = .3       # the mask at the sparsest places
HUE_OFF = .16       # a stand-in's colour may be this far off (its channels' shares, summed)
WEAK = .125         # a texture whose alpha varies less than this as seen gives way...
LIVELY = .19        # ...to one of its colour that varies this much
KEEP_DARK = .5      # the dark flecks' least share of their strength, balanced or not
THIN = .06          # a texture's mean alpha below this can't carry it (0..1)
MIN_CHUNKS = 16     # the least flat ground worth a texture
MIN_SHARE = 8       # chunks of a region a texture needs to be used there
ROUGH = 7           # px this rough (std of their luminance, 0-255) aren't flat
TONE_OFF = 34       # ...nor px this far from the flat ground's tone (sum of three channels' 0-255 / 3 * 3)
ART_PX = 8          # px a chunk the art is looked at
MASK_PX = 4         # a mask's px a chunk
SIDES = (16, 8, 4)  # a patch's side, chunks
SPARE = .3          # a patch less full than this splits
BAKE_PX = 16        # the demo's px a chunk
SITES = {"barrens": (1, 33, 28, 37, 32), "needles": (1, 31, 37, 38, 44), "north": (0, 36, 22, 45, 29), "olive": (0, 28, 43, 35, 49)}
LOOKED_AT = 1       # the mip a texture's colour is judged at
GRASS = 189024      # the texture the scale's set by
SMALLEST, POWER = .3, 1.  # a texture's scale by its flecks: at most so far off, and how much of it
WHOLE = 1           # GroundMask1: all of it, shared


class Textures:
    """Ground textures: their mips (box, as the client's near enough), mean alpha, alpha-weighted colour."""

    def __init__(self, src, install: str | None, product: str):
        self.src, self.seen = src, {}
        self.other = CascStore(install, product) if install else None

    def mips(self, fdid: int) -> list | None:
        if fdid not in self.seen:
            b = self.src.read(fdid) or (self.other.read(fdid) if self.other else None)
            if not b or not fdid:
                self.seen[fdid] = None
            else:
                a = np.asarray(blp_rgba(b), np.float32) / 255
                out = [a]
                while out[-1].shape[0] > 1 and out[-1].shape[0] == out[-1].shape[1]:
                    n = out[-1].shape[0] // 2
                    out.append(out[-1].reshape(n, 2, n, 2, 4).mean((1, 3)))
                self.seen[fdid] = out
        return self.seen[fdid]

    def stats(self, fdid: int) -> tuple[np.ndarray, float] | None:
        m = self.mips(fdid)
        if m is None or m[0].shape[0] < 64:
            return None
        w = m[LOOKED_AT][..., 3:]  # (as it's seen: past mip 0 the bright px's colour no longer goes with their alpha)
        return (m[LOOKED_AT][..., :3] * w).sum((0, 1)) / max(float(w.sum()), 1e-3), float(w.mean())

    def varies(self, fdid: int) -> float:
        """How much its alpha varies at the size it's drawn, as the demo's zoom sees it."""
        lod = max(0., math.log2(LAYERS[2][0] * self.scale(fdid) * 256 / (16 * BAKE_PX)))
        return float(self.mips(fdid)[int(round(lod))][..., 3].std())

    def scale(self, fdid: int) -> float:
        """How big to draw it: by its flecks' size (the wavelength the alpha's power centres on) against the grass's, whose REPS are right."""
        def wavelength(a):
            f = np.abs(np.fft.fft2(a - a.mean())) ** 2
            n = a.shape[0]
            y, x = np.indices(a.shape)
            r = np.hypot(np.minimum(y, n - y), np.minimum(x, n - x))
            return n * f.sum() / max(float((f * r).sum()), 1e-6) + 1e-6
        return float(np.clip(wavelength(self.mips(GRASS)[0][..., 3]) / wavelength(self.mips(fdid)[0][..., 3]), SMALLEST, 1)) ** POWER


def sample(mips: list, u: np.ndarray, v: np.ndarray, density: float) -> np.ndarray:
    """TRILINEAR, REPEAT: what the client does. density: texels a screen px."""
    lod = max(0., math.log2(max(density, 1e-6)))
    l0 = min(int(lod), len(mips) - 1)
    l1, f = min(l0 + 1, len(mips) - 1), lod - int(lod)

    def bilinear(m):
        n = m.shape[0]
        x, y = u * n - .5, v * n - .5
        x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
        fx, fy = (x - x0)[..., None], (y - y0)[..., None]
        x0, y0, x1, y1 = x0 % n, y0 % n, (x0 + 1) % n, (y0 + 1) % n
        return (m[y0, x0] * (1 - fx) + m[y0, x1] * fx) * (1 - fy) + (m[y1, x0] * (1 - fx) + m[y1, x1] * fx) * fy

    return bilinear(mips[l0]) * (1 - f) + bilinear(mips[l1]) * f


def coords(col: float, row: float, layer: tuple) -> tuple[float, float]:
    """A map place (chunks) in a layer's texture: the addon's sum too."""
    rep, turn, u0, v0 = layer
    x, y = col / 16, row / 16
    return (x * math.cos(turn) + y * math.sin(turn)) * rep + u0, (-x * math.sin(turn) + y * math.cos(turn)) * rep + v0


def shrink(a: np.ndarray) -> np.ndarray:
    return ~grow(~a, 1)


def core_of(m) -> np.ndarray:
    """The flat chunks that count: pinholes closed, threads and specks gone."""
    ok = m.land & ~m.dark & ~m.wet & ~m.built
    closed = shrink(grow(m.flat, 1)) & ok & (m.detail < 9)
    core = grow(shrink(closed), 1) & closed
    out = np.zeros_like(core)
    for s in components(core):
        if int(core[s].sum()) >= MIN_CHUNKS:
            piece = np.zeros_like(core)
            piece[s] = core[s]
            out |= piece
    return out


def box_blur(a: np.ndarray, r: int) -> np.ndarray:
    s = np.pad(np.pad(a, r, mode="edge"), ((1, 0), (1, 0))).cumsum(0).cumsum(1)  # (edge: zeros would read as a rough rim round each tile)
    n = 2 * r + 1
    return (s[n:, n:] - s[:-n, n:] - s[n:, :-n] + s[:-n, :-n]) / (n * n)


def blur(a: np.ndarray, r: float) -> np.ndarray:
    return np.asarray(Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r)), np.float32) / 255


def field_of(m, g_art, core: np.ndarray, seed: int) -> np.ndarray:
    """Where the layer shows, 0..1, MASK_PX a chunk: the art's own flat shape round the core, fading inside it."""
    n = core.shape[0]
    allowed = grow(core, 2) & m.land & ~m.dark & ~m.wet & ~m.built
    tiles = np.unique(np.argwhere(allowed) // 16, axis=0)
    out = np.zeros((n * MASK_PX, n * MASK_PX), np.float32)
    # the core's tone, carried out over what's round it
    w = core.astype(np.float32)
    weight = blur(w, 3)[..., None]
    tone = np.dstack([blur(m.tone[..., k] * w / 255, 3) for k in range(3)]) / np.maximum(weight, 1e-3) * 255
    known = weight[..., 0] > .004
    for r, c in tiles:
        a = g_art(c * 64 + r)
        if a is None:
            continue
        lum = a.mean(-1)
        rough = np.sqrt(np.maximum(box_blur(lum * lum, 1) - box_blur(lum, 1) ** 2, 0))
        t = np.asarray(Image.fromarray(tone[r * 16:r * 16 + 16, c * 16:c * 16 + 16].astype(np.uint8)).resize((16 * ART_PX, 16 * ART_PX), Image.BILINEAR), np.float32)
        near = np.abs(a - t).sum(-1) < TONE_OFF
        cells = allowed[r * 16:r * 16 + 16, c * 16:c * 16 + 16] & known[r * 16:r * 16 + 16, c * 16:c * 16 + 16]
        good = (rough < ROUGH) & near & cells.repeat(ART_PX, 0).repeat(ART_PX, 1)
        s = ART_PX // MASK_PX
        out[r * 16 * MASK_PX:(r + 1) * 16 * MASK_PX, c * 16 * MASK_PX:(c + 1) * 16 * MASK_PX] = good.reshape(16 * MASK_PX, s, 16 * MASK_PX, s).mean((1, 3))
    rng = np.random.RandomState(seed)
    noise = np.asarray(Image.fromarray((rng.rand(n // 4 + 1, n // 4 + 1) * 255).astype(np.uint8)).resize((n * MASK_PX, n * MASK_PX), Image.BICUBIC), np.float32) / 255 - .5
    t = np.clip((blur(out, MASK_PX * .4) + noise * .2 - .4) / .25, 0, 1)
    return t * t * (3 - 2 * t)


def density(seed: int) -> np.ndarray:
    """Denser and sparser ground (over the mask, for all the draws): a wander a couple of tiles wide and a fine one, so no carpet."""
    n = 1024 * MASK_PX
    r = np.random.RandomState(seed)
    def wave(k):
        return np.asarray(Image.fromarray((r.rand(k, k) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC), np.float32) / 255
    v = np.clip((.65 * wave(32) + .35 * wave(128) - .28) / .44, 0, 1)
    return SPARSEST + (1 - SPARSEST) * v * v * (3 - 2 * v)


def carrier(t: Textures, fdid: int, usable: list[int]) -> int | None:
    """The texture to draw for one painted: itself, or if its alpha's too thin the nearest in colour among those with enough."""
    s = t.stats(fdid)
    if s is None:
        return None
    if s[1] >= THIN:
        return fdid
    a = s[0] / max(float(s[0].sum()), 1e-3)
    best, far = None, 1e9
    for u in usable:
        q = t.stats(u)
        if q and .05 <= q[1] <= .3:
            d = float(np.abs(q[0] / max(float(q[0].sum()), 1e-3) - a).sum()) + abs(float(q[0].sum() - s[0].sum())) * .1
            if d < far:
                best, far = u, d
    return best


def materials(m, t: Textures, core: np.ndarray) -> np.ndarray:
    """The texture drawn for each chunk of the map (0: none); a region's rare ones fold into their neighbours, and it reaches past the core."""
    usable = [k for k, _ in Counter(m.painted[core].tolist()).most_common()]
    pool = [k for k, v in Counter(m.painted[m.land].tolist()).items() if v >= 50 and k]
    lend = {k: carrier(t, k, pool) for k in usable}
    log("  stand-ins: " + ", ".join(f"{k}->{v}" for k, v in lend.items() if k != v))
    mat = np.zeros_like(m.painted)
    for s in components(core):
        here = core[s]
        ids = np.vectorize(lambda k: lend.get(k) or 0)(m.painted[s]) * here
        count = Counter(ids[here].tolist())
        keep = [k for k, v in count.items() if k and v >= MIN_SHARE] or [k for k, _ in count.most_common(1) if k]
        ids[~np.isin(ids, keep)] = 0
        mat[s] = np.where(here, ids, mat[s])
    while True:  # the folded, and a margin out
        empty = (mat == 0) & grow(core, 3)
        if not empty.any():
            break
        p = np.pad(mat, 1)
        v = np.maximum.reduce([p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]])
        new = empty & (v > 0)
        if not new.any():
            break
        mat[new] = v[new]
    return mat


def split(w: np.ndarray, c: int, r: int, side: int, out: list) -> None:
    """The squares (col, row, side) that hold a mask: tile by tile, spare ones split."""
    p = MASK_PX
    a = w[r * p:(r + side) * p, c * p:(c + side) * p]
    on = a > .02
    if not on.any():
        return
    if side > SIDES[-1] and on.mean() < SPARE:
        h = side // 2
        for dc, dr in ((0, 0), (h, 0), (0, h), (h, h)):
            split(w, c + dc, r + dr, h, out)
    elif a.sum() >= p * p * .25:  # (less is nothing to see)
        out.append((c, r, side))


def brighter(t: Textures, pool: list[int], fdid: int, tone: np.ndarray, reach: float, lively: bool = False) -> int:
    """The nearest in colour to the tone among textures bright enough to reach this far over it (lively: and whose flecks show well), or the texture itself."""
    a = tone / max(float(tone.sum()), 1e-3)
    best, far = fdid, HUE_OFF
    for u in pool:
        q = t.stats(u)
        if q and .05 <= q[1] <= .4 and (q[0] >= tone * (1 + reach)).all() and (not lively or t.varies(u) >= LIVELY):
            d = float(np.abs(q[0] / max(float(q[0].sum()), 1e-3) - a).sum())
            if d < far:
                best, far = u, d
    return best


def patches(m, t: Textures, art, field: np.ndarray, mat: np.ndarray) -> list[dict]:
    """The patches: for each texture its share of the field, squares of it, each with its vertex colours."""
    out = []
    pool = [k for k, v in Counter(m.painted[m.land].tolist()).items() if v >= 50 and k]
    ids = [k for k in np.unique(mat) if k]
    n = mat.shape[0]
    weights = {}
    for k in ids:
        hot = Image.fromarray((mat == k).astype(np.uint8) * 255).resize((n * MASK_PX, n * MASK_PX), Image.NEAREST)
        weights[k] = np.asarray(hot.filter(ImageFilter.GaussianBlur(MASK_PX * .8)), np.float32) / 255
    total = sum(weights.values()) if weights else None
    for k in ids:
        w = field * weights[k] / np.maximum(total, 1e-3)
        cells = []
        rows, cols = np.nonzero(w.reshape(n, MASK_PX, n, MASK_PX).max((1, 3)) > .02)
        for r, c in sorted({(int(a) // 16, int(b) // 16) for a, b in zip(rows, cols)}):
            split(w, c * 16, r * 16, 16, cells)
        for c, r, side in cells:
            a = w[r * MASK_PX:(r + side) * MASK_PX, c * MASK_PX:(c + side) * MASK_PX]
            tone = (m.tone[r:r + side, c:c + side] * a.reshape(side, MASK_PX, side, MASK_PX).mean((1, 3))[..., None]).sum((0, 1))
            tone = tone / max(float(a.mean()) * side * side, 1e-3) / 255
            file = int(k)
            if t.varies(file) < WEAK:  # its flecks barely show: one of its colour that shows draws them all
                file = brighter(t, pool, file, tone, .25, True)
            wm, alpha = t.stats(file)
            g = min(MOST, STRENGTH * t.varies(GRASS) / max(t.varies(file), 1e-3))
            light = np.minimum(1, tone * (1 + g) / wm)
            file2 = file
            if ((light * wm / np.maximum(tone, 1e-3)).min() < 1 + g * .7):  # too dark for the light flecks: a brighter one of its colour draws those
                file2 = brighter(t, pool, file, tone, g * .8)
            wm2, alpha2 = t.stats(file2)
            # the two kinds of fleck cancel by how much of the ground each covers: what the light can't balance, the dark gives up, to a point
            cover = alpha2 / max(alpha, 1e-3)
            bright = np.minimum(np.minimum(1, tone * (1 + g) / wm2) * wm2 / np.maximum(tone, 1e-3) - 1, g * DARK / cover)
            light = tone * (1 + bright) / wm2
            dark = np.minimum(1, tone * np.maximum(1 - np.clip(bright * cover, g * DARK * KEEP_DARK, g * DARK), .2) / wm)
            out.append({"col": c, "row": r, "side": side, "file": file, "file2": file2, "dark": np.minimum(dark, 1).round(2).tolist(), "light": np.minimum(light, 1).round(2).tolist(), "w": a, "scale": round(t.scale(file), 2)})
    return out


def draw(p: dict, t: Textures, px: int, rgb: np.ndarray, alpha: np.ndarray | None, x0: int, y0: int) -> None:
    """A patch as the client draws it, over a picture (x0, y0: its place there, px): two draws, a mask, vertex colours, BLEND.
    alpha given: over see-through (the demo's), rgb premultiplied."""
    n = p["side"] * px
    mask = np.asarray(Image.fromarray(p["w"]).resize((n, n), Image.BILINEAR), np.float32)
    y, x = np.indices((n, n), np.float32)
    for layer, vc, file in zip(LAYERS, (p["dark"], p["light"], p["dark"], p["light"]), (p["file"], p["file2"], p["file"], p["file2"])):
        mips = t.mips(file)
        rep, turn = layer[0] * p["scale"], layer[1]
        cols, rows = (x + .5) / px + p["col"], (y + .5) / px + p["row"]
        ct, st = math.cos(turn), math.sin(turn)
        u = (cols / 16 * ct + rows / 16 * st) * rep + layer[2]
        v = (-cols / 16 * st + rows / 16 * ct) * rep + layer[3]
        s = sample(mips, u, v, 256 * rep / (16 * px))
        a = (s[..., 3] * mask)[..., None]
        ys, ye, xs, xe = max(0, y0), min(rgb.shape[0], y0 + n), max(0, x0), min(rgb.shape[1], x0 + n)
        if ys >= ye or xs >= xe:
            return
        cut = (ys - y0, ye - y0, xs - x0, xe - x0)
        a = a[cut[0]:cut[1], cut[2]:cut[3]]
        col = s[cut[0]:cut[1], cut[2]:cut[3], :3] * np.array(vc, np.float32)
        rgb[ys:ye, xs:xe] = rgb[ys:ye, xs:xe] * (1 - a) + col * a
        if alpha is not None:
            alpha[ys:ye, xs:xe] = alpha[ys:ye, xs:xe] * (1 - a) + a


def bake(ps: list, t: Textures, inst: int, out: str) -> list:
    """The patches as see-through pictures, a tile's at a time (the web demo's)."""
    groups, baked = {}, []
    for p in ps:
        groups.setdefault((p["col"] // 16, p["row"] // 16), []).append(p)
    px = BAKE_PX
    for (tc, tr), group in sorted(groups.items()):
        c0, r0 = min(p["col"] for p in group), min(p["row"] for p in group)
        c1, r1 = max(p["col"] + p["side"] for p in group), max(p["row"] + p["side"] for p in group)
        rgb, alpha = np.zeros(((r1 - r0) * px, (c1 - c0) * px, 3), np.float32), np.zeros(((r1 - r0) * px, (c1 - c0) * px, 1), np.float32)
        for p in group:
            draw(p, t, px, rgb, alpha, (p["col"] - c0) * px, (p["row"] - r0) * px)
        straight = rgb / np.maximum(alpha, 1e-3)
        name = f"{inst}_{tc}_{tr}.webp"
        Image.fromarray(np.dstack([straight * 255, alpha * 255]).clip(0, 255).astype(np.uint8)).save(os.path.join(out, name), quality=80, alpha_quality=90, method=4, exact=True)
        baked.append({"file": name, "col": c0 / 16, "row": r0 / 16, "w": (c1 - c0) / 16, "h": (r1 - r0) / 16})
    return baked


def site_image(name: str, box: tuple, g_tile, ps: list, t: Textures, out: str, px: int = BAKE_PX) -> None:
    """Before and after, side by side."""
    inst, c0, r0, c1, r1 = box
    n = 16 * px
    img = np.zeros(((r1 - r0) * n, (c1 - c0) * n, 3), np.float32)
    for c in range(c0, c1):
        for r in range(r0, r1):
            a = g_tile(c * 64 + r)
            if a is not None:
                img[(r - r0) * n:(r - r0 + 1) * n, (c - c0) * n:(c - c0 + 1) * n] = np.asarray(a.resize((n, n), Image.LANCZOS), np.float32) / 255
    after = img.copy()
    for p in ps:
        x, y = (p["col"] - c0 * 16) * px, (p["row"] - r0 * 16) * px
        if x < after.shape[1] and y < after.shape[0] and x + p["side"] * px > 0 and y + p["side"] * px > 0:
            draw(p, t, px, after, None, x, y)
    save = lambda a, s: Image.fromarray((a.clip(0, 1) * 255).astype(np.uint8)).save(os.path.join(out, f"{name}_{s}.png"))
    save(img, "before")
    save(after, "after")
    save(np.hstack([img, np.ones((img.shape[0], 8, 3), np.float32), after]), "both")


def write_masks(ps: list, first: int, out: str) -> int:
    """GroundMask<n>.tga, a patch's; a whole one is the shared one. Numbers them."""
    for p in ps:
        a = p["w"]
        if a.min() > .995:
            p["mask"] = WHOLE
            continue
        rows = [[(255, 255, 255, int(round(float(v) * 255))) for v in line] for line in a]
        with open(os.path.join(out, f"GroundMask{first}.tga"), "wb") as f:
            f.write(write_tga(a.shape[1], a.shape[0], rows))
        p["mask"] = first
        first += 1
    return first


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "mm-fill"), help="the terrain read so far")
    ap.add_argument("--bake", help="also write the web demo's pictures here (ground.json, *.webp)")
    ap.add_argument("--sites", help="also write before/after pictures of the test sites here")
    ap.add_argument("--tex-product", default="wow_classic_era", help="the install's product to read textures from when the source hasn't them")
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import maplint
    data = maplint.Data(os.path.join(ROOT, "Data"))
    masks_dir = os.path.join(ROOT, "demo", "ground_out", "masks")
    os.makedirs(masks_dir, exist_ok=True)
    t = Textures(src, ns.args[0] if ns.mode == "local" else None, ns.tex_product)
    with open(os.path.join(masks_dir, f"GroundMask{WHOLE}.tga"), "wb") as f:
        f.write(write_tga(4, 4, [[(255, 255, 255, 255)] * 4] * 4))
    maps, baked, first = {}, {}, WHOLE + 1
    for inst in (0, 1):
        tiles, sea = data.tiles[inst], data.sea[inst]
        m = read(src, inst, tiles, sea, ns.cache)

        def tile(key):
            return blp_rgba(src.read(tiles[key])).convert("RGB") if key in tiles and key not in sea else None

        def art(key):
            a = tile(key)
            return None if a is None else np.asarray(a.resize((16 * ART_PX, 16 * ART_PX), Image.BOX), np.float32)

        core = core_of(m)
        mat = materials(m, t, core)
        field = field_of(m, art, core, inst + 1) * density(inst + 11)
        ps = patches(m, t, art, field, mat)
        first = write_masks(ps, first, masks_dir)
        maps[inst] = ps
        log(f"[{inst}] flat {int(m.flat.sum())} chunks, kept {int(core.sum())}; {len(ps)} patches ({Counter(p['side'] for p in ps)}), {len({p['file'] for p in ps})} textures, masks to {first - 1}")
        if ns.bake:
            os.makedirs(ns.bake, exist_ok=True)
            baked[inst] = bake(ps, t, inst, ns.bake)
        if ns.sites:
            os.makedirs(ns.sites, exist_ok=True)
            for name, box in SITES.items():
                if box[0] == inst:
                    site_image(name, box, tile, ps, t, ns.sites)
    if ns.bake:  # (the pictures first: this file is what's read)
        path = os.path.join(ns.bake, "ground.json")
        with open(path + ".tmp", "w") as f:
            json.dump({str(k): v for k, v in baked.items()}, f, separators=(",", ":"))
        os.replace(path + ".tmp", path)
    with open(os.path.join(ROOT, "Data", "Ground.lua.new"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- GENERATED by tools/gen_ground.py from the tiles and terrain of {src.product} {src.version}. Do not edit.\n")
        f.write("-- layers: the draws of a patch, in order { repeats a tile side, turn, u, v } (world-anchored; dark, light, dark, light)\n")
        f.write("-- [inst] = { col, row, side, file, file2, dr, dg, db, lr, lg, lb, scale, mask, ... }: a patch: where (chunks), the textures (FileDataIDs: dark draws', light's),\n")
        f.write("--   the dark draws' vertex colour, the light's, what the layers' repeats go by, Textures/GroundMask<mask>\n")
        f.write('local _, ns = ...\nlocal D = ns.Data or {}; ns.Data = D\nD.formats = D.formats or {}; D.formats.Ground = 1\n')  # (data_head's, once mmtools/luaout.py's FORMATS has a Ground row)
        f.write("D.Ground = { layers = { " + ", ".join("{ %g, %g, %g, %g }" % l for l in LAYERS) + " },\n")
        for inst, ps in maps.items():
            f.write(f"  [{inst}] = {{\n")
            for p in ps:
                f.write("    %d, %d, %d, %d, %d, %g, %g, %g, %g, %g, %g, %g, %d,\n" % (p["col"], p["row"], p["side"], p["file"], p["file2"], *p["dark"], *p["light"], p["scale"], p["mask"]))
            f.write("  },\n")
        f.write("}\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate Data/Relief.lua.new and demo/relief_out/Relief*.tga: true hills and hollows drawn over the map's flat ground.

Some of the tiles' land is filler: flat colour, though the terrain under it has shape. This shades that ground from the game's
own heights (tools/flatmap.py), as the tiles' own ground is shaded: the sun's direction and strength are measured (--fit), by
how the art's brightness follows the slope on detailed ground; the direction is kept, the strength raised to the local contrast of the
real ground around (measured too), with gentle forms stretched, noise for lumps and gullies, and patches of light and dark. Made here, no pixel of anyone's art in it: black with alpha where
a slope turns from the sun, the ground's own tone made brighter with alpha where it turns to it, for normal blending over the tiles.

Shown only on flat ground (a chunk's detail, with a wandering edge), gone well before real ground; never on water or buildings;
and level ground gets the noise too. Pictures: squares on a fixed grid, a power of two chunks a side, split till full enough. Specks are dropped.

  python3 tools/gen_relief.py local "/Applications/World of Warcraft" wow_classic_beta --bake demo/relief
  ...  --fit: measure the sun and stop; --mosaic DIR: the finished map as m<inst>.npy (else the bare tiles are read);
  --sites DIR: before/after pictures of the test sites
"""
from __future__ import annotations

import argparse
import json
import os
import tempfile

import numpy as np
from PIL import Image

from flatmap import read
from gen_fill import Ground
from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.sources import add_source_args, source_from_args
from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YD = 533.3333 / 128  # yards between height samples
# The sun, from --fit: the azimuth measured from the west toward the north, how high, how much light isn't the sun's
SUN_AZ, SUN_EL = np.radians(45), np.radians(45)
# How it's drawn is not as measured: on purpose louder, so flat ground stops reading as flat (the sun's direction stays)
CONTRAST, CONTRAST_RANGE = .85, (.07, .17)  # its contrast: this much of the real ground's around it, within this
FORM_SLOPE, STRETCH = .35, 8.  # gentle ground's forms are stretched up to this slope (rms), by at most this
NOISE_SLOPE, GULLY = .4, 3.    # the lumps' slope, the gullies' depth against them
LIGHT = 1.8                    # the light's colour against the ground's
MOTTLE, HOLLOW = .7, .35       # patches of light and dark, hollows darker: against the contrast
BLUR = 1             # the heights' smoothing, box radius (3 passes, samples), so the sample grid doesn't show
DETAIL = (5., 9.)    # a chunk's detail: at or under the first, flat; from the second, real ground
MIN_ALPHA = 3 / 255    # less isn't worth a chunk's texture
SHIP = 4             # px a chunk: 8 is a little crisper at about three times the bytes (--ship)
MIN_SIDE = 8         # chunks: the smallest picture
MAX_SIDE = 512       # px
SPECK = 24           # chunks: fewer, dropped
FILL = .3            # a picture must be this full of relief, or it's split
SITES = {"barrens": (1, 33, 28, 36, 31), "needles": (1, 31, 37, 37, 43), "ekn_north": (0, 36, 22, 44, 28), "ek_olive": (0, 28, 43, 34, 48)}


def box(a: np.ndarray, r: int) -> np.ndarray:
    k = 2 * r + 1
    c = np.cumsum(np.pad(a, ((r + 1, r), (0, 0)), mode="edge"), 0, dtype=np.float64)
    a = c[k:] - c[:-k]
    c = np.cumsum(np.pad(a, ((0, 0), (r + 1, r)), mode="edge"), 1)
    return ((c[:, k:] - c[:, :-k]) / (k * k)).astype(np.float32)


def blur(a: np.ndarray, r: int) -> np.ndarray:
    for _ in range(3):
        a = box(a, r)
    return a


def smooth(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def filled(h: np.ndarray) -> np.ndarray:
    """Heights with their holes (no terrain) filled from around: no cliff at a hole's edge."""
    ok = ~np.isnan(h)
    known = np.where(ok, h, 0).astype(np.float32)
    out, w = blur(known, 8), blur(ok.astype(np.float32), 8)
    return np.where(ok, h, out / np.maximum(w, 1e-3)).astype(np.float32)


def slopes(h: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    gx, gy = np.zeros_like(h), np.zeros_like(h)
    gx[:, 1:-1] = (h[:, 2:] - h[:, :-2]) / (2 * YD)
    gy[1:-1] = (h[2:] - h[:-2]) / (2 * YD)
    return gx, gy


def lit(h: np.ndarray, ambient: float) -> np.ndarray:
    """ln of lit over level ground's brightness, px for px with h."""
    gx, gy = slopes(h)
    lx, ly, lz = -np.cos(SUN_AZ) * np.cos(SUN_EL), -np.sin(SUN_AZ) * np.cos(SUN_EL), np.sin(SUN_EL)  # toward the sun: x east, y south
    return np.log((ambient + np.maximum((-gx * lx - gy * ly + lz) / np.sqrt(1 + gx * gx + gy * gy), 0)) / (ambient + lz))


def fractal(seed: int, n: int, sizes: tuple, rough: float = 1.) -> np.ndarray:
    """Noise, mean 0, sd 1; sizes: its octaves' blobs, px; each octave's height goes as its size ** rough."""
    r, out = np.random.RandomState(seed), np.zeros((n, n), np.float32)
    for size in sizes:
        g = r.rand(n // size + 1, n // size + 1).astype(np.float32)
        out += float(size) ** rough * (np.asarray(Image.fromarray(g, "F").resize((n, n), Image.BICUBIC)) - .5)
    return (out - out.mean()) / out.std()


def ground_contrast(img: np.ndarray, m) -> np.ndarray:
    """The local contrast (sd of ln brightness, lumps' scale) of the real ground around each px, weighted to the nearest."""
    n = m.heights.shape[0]
    bad = m.flat | m.wet | m.built | m.dark | ~m.land
    good = np.kron(box(bad.astype(np.float32), 1) < .001, np.ones((8, 8), np.float32))
    l = np.log(np.maximum(img[..., 0] * .3 + img[..., 1] * .59 + img[..., 2] * .11, 3)).astype(np.float32)
    band = blur(l, 1) - blur(l, 8)
    known = (band * band * good).astype(np.float32)
    v, w = known, good
    for _ in range(2):  # (a wide box, twice over: a smooth window a tile or so across)
        v, w = box(v, 96), box(w, 96)
    whole = known.sum() / good.sum()
    t = np.sqrt(np.where(w > 1e-3, v / np.maximum(w, 1e-3), whole))
    return np.clip(t * CONTRAST, *CONTRAST_RANGE)


def relief(h: np.ndarray, seed: int, target: np.ndarray) -> np.ndarray:
    """The ln of brightness to draw: the real forms, stretched where they're gentle, roughened by noise, lit by the measured sun, brought to target's contrast."""
    n = h.shape[0]
    hs = blur(h, BLUR)
    gx, gy = slopes(hs)
    rms = np.sqrt(blur(gx * gx + gy * gy, 48))
    stretch = blur(np.clip(FORM_SLOPE / np.maximum(rms, .01), 1, STRETCH), 32)  # gentle ground stands up, steep stays
    forms = stretch * (hs - blur(h, 96))
    # lumps and gullies: a fractal, a ridged octave cut into it, its roughness itself patchy
    lumps = fractal(seed, n, (48, 24, 12, 6, 3), .75)
    gully = 1 - np.abs(fractal(seed + 1, n, (40, 20), 1.))
    patch = np.clip(.75 + .55 * fractal(seed + 2, n, (96, 48), 1.), .25, 1.6)
    yards = NOISE_SLOPE * 12 * YD  # a lump of about 12 samples rises this far at NOISE_SLOPE
    rough = blur(patch * (lumps * yards - GULLY * np.maximum(gully - .6, 0) * yards), 1)
    shape = lit(forms + rough, .5)
    shape = shape - blur(shape, 48)
    shape = shape * target / np.maximum(np.sqrt(blur(shape * shape, 32)), .005)
    # patches of light and dark, and hollows darker than what's round them
    hollow = hs - blur(h, 12)
    hollow = hollow / np.maximum(np.sqrt(blur(hollow * hollow, 48)), .25)
    return shape + target * (MOTTLE * fractal(seed + 3, n, (128, 64, 32), .8) + HOLLOW * np.clip(hollow, -2.5, 2.5))


def wander(seed: int, n: int) -> np.ndarray:
    """Smooth noise, about 0..1, blobs of a chunk or two; n px a side. For the mask's edge."""
    r, out, total, amp = np.random.RandomState(seed), np.zeros((n, n), np.float32), 0., 1.
    for cells in (n // 48, n // 24, n // 12):
        g = (r.rand(cells, cells) * 255).astype(np.uint8)
        out += amp * np.asarray(Image.fromarray(g).resize((n, n), Image.BICUBIC), np.float32) / 255
        total, amp = total + amp, amp * .55
    return out / total


def mask_of(m, seed: int) -> np.ndarray:
    """0..1, px for px with the heights: the ground the relief shows on."""
    n = m.heights.shape[0]
    up = lambda a: np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((n, n), Image.BILINEAR))
    soft = 1 - smooth(DETAIL[0], DETAIL[1], m.detail)
    never = m.wet | m.built | m.dark | ~m.land | (m.detail >= DETAIL[1] + 2)  # real ground too: gone well before it
    soft = soft * ~never
    a = blur(up(soft), 3)
    a = smooth(.42, .82, a + (wander(seed, n) - .5) * .5)
    # clear of what it must never touch, by at least half a chunk
    a *= 1 - smooth(.02, .3, blur(up(never.astype(np.float32)), 4))
    return a


def picture(m, img: np.ndarray, seed: int) -> np.ndarray:
    """Signed alpha, px for px with the heights: < 0 black over the ground, > 0 its light colour (tint)."""
    ratio = np.exp(np.clip(relief(filled(m.heights), seed * 10, ground_contrast(img, m)), -.5, .45))
    return (np.maximum(ratio - 1, 0) / (LIGHT - 1) - np.maximum(1 - ratio, 0)) * mask_of(m, seed)


def tint_of(m) -> np.ndarray:
    """The light's colour, px for px with the heights: the ground's own tone (chunks' means, blurred), LIGHT times over. Blending
    toward it multiplies the ground's every channel alike, so a lit slope stays its colour; white turned them milky."""
    n = m.heights.shape[0]
    out = np.zeros((n, n, 3), np.uint8)
    for i in range(3):
        c = np.asarray(Image.fromarray(m.tone[..., i].astype(np.float32), "F").resize((n, n), Image.BILINEAR))
        out[..., i] = np.clip(blur(c, 8) * LIGHT, 0, 255)
    return out


def label(a: np.ndarray) -> list[np.ndarray]:
    """Lists of (y, x) of a's connected pieces (8-way)."""
    seen, out = np.zeros_like(a), []
    H, W = a.shape
    for y0, x0 in zip(*np.nonzero(a)):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        stack, one = [(y0, x0)], []
        while stack:
            y, x = stack.pop()
            one.append((y, x))
            for ny in range(max(0, y - 1), min(H, y + 2)):
                for nx in range(max(0, x - 1), min(W, x + 2)):
                    if a[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        out.append(np.array(one))
    return out


def cover(a: np.ndarray, x: int, y: int, size: int, out: list) -> None:
    """Squares on a fixed grid over a, so none overlaps and neighbours meet edge to edge, each full enough or as small as they go."""
    n = int(a[y:y + size, x:x + size].sum())
    if not n:
        return
    if size <= MIN_SIDE or (size * SHIP <= MAX_SIDE and n >= FILL * size * size):
        out.append((x, y, size, size))
        return
    for ny in (y, y + size // 2):
        for nx in (x, x + size // 2):
            cover(a, nx, ny, size // 2, out)


def regions(sa: np.ndarray) -> tuple[list, np.ndarray]:
    """The pictures; sa with what's dropped cleared."""
    cells = np.abs(sa).reshape(1024, 8, 1024, 8).max((1, 3)) >= MIN_ALPHA
    keep, rects = np.zeros_like(cells), []
    for one in label(cells):
        if len(one) >= SPECK:
            keep[one[:, 0], one[:, 1]] = True
    cover(keep, 0, 0, 1024, rects)
    return rects, sa * np.kron(keep, np.ones((8, 8), bool))


def texels(sa: np.ndarray, tint: np.ndarray, x: int, y: int, w: int, h: int) -> np.ndarray:
    """A square's picture, RGBA, SHIP px a chunk (bicubic, from its px and a little round them, so its edge meets its neighbour's)."""
    d = 8 // SHIP
    pad = 8
    y0, y1, x0, x1 = max(0, y * 8 - pad), min(8192, (y + h) * 8 + pad), max(0, x * 8 - pad), min(8192, (x + w) * 8 + pad)
    small = lambda a, f: np.asarray(Image.fromarray(a, "F" if a.ndim == 2 else None).resize(((x1 - x0) // d, (y1 - y0) // d), f))
    s = small(sa[y0:y1, x0:x1].astype(np.float32), Image.BICUBIC)
    t = small(tint[y0:y1, x0:x1], Image.BILINEAR)
    cy, cx = (y * 8 - y0) // d, (x * 8 - x0) // d
    s, t = s[cy:cy + h * SHIP, cx:cx + w * SHIP], t[cy:cy + h * SHIP, cx:cx + w * SHIP]
    rgb = np.where(s[..., None] > 0, t, 0).astype(np.uint8)
    return np.dstack([rgb, np.clip(np.round(np.abs(s) * 255), 0, 255).astype(np.uint8)])


def over(img: np.ndarray, rgba: np.ndarray) -> None:
    """Normal blending, in place: as the game will."""
    a = rgba[..., 3:].astype(np.float32) / 255
    img[...] = img * (1 - a) + rgba[..., :3] * a


def fit(img: np.ndarray, m) -> dict:
    """How the art follows the slope on real ground: tile by tile, in a band of scales (so neither px noise nor the ground's colour)."""
    n = m.heights.shape[0]
    bad = m.flat | m.wet | m.built | m.dark | ~m.land
    good = np.kron(box(bad.astype(np.float32), 2) < .001, np.ones((8, 8), bool)) & ~np.isnan(m.heights)
    h = filled(m.heights)
    l = np.log(np.maximum(img @ np.array([.3, .59, .11], np.float32), 3)).astype(np.float32)
    band = blur(l, 2) - blur(l, 8)
    hs = blur(h, 2)
    gx, gy = slopes(hs)
    hb = hs - blur(h, 8)
    rows = []
    for c in range(64):
        for r in range(64):
            s = (r * 128, r * 128 + 128), (c * 128, c * 128 + 128)
            cut = lambda a: a[s[0][0]:s[0][1], s[1][0]:s[1][1]]
            k = cut(good) & (np.hypot(cut(gx), cut(gy)) < .6)
            if k.sum() < 2000 or cut(gx)[k].std() < .08:
                continue
            X = np.c_[cut(gx)[k], cut(gy)[k], np.ones(k.sum())]
            b = np.linalg.lstsq(X, cut(band)[k], rcond=None)[0]
            rows.append((np.corrcoef(X @ b, cut(band)[k])[0, 1], b[0], b[1]))
    rows = np.array(rows)
    top = rows[np.argsort(-rows[:, 0])[:len(rows) // 4]]
    k = good & (np.hypot(gx, gy) < .6)
    X = np.c_[gx[k], gy[k], hb[k], np.ones(k.sum())]
    b = np.linalg.lstsq(X, band[k], rcond=None)[0]
    return {"tiles": len(rows), "R": np.percentile(rows[:, 0], [10, 50, 90]).round(3).tolist(),
            "strength": round(float(np.median(np.hypot(rows[:, 1], rows[:, 2]))), 3), "strength_top": round(float(np.median(np.hypot(top[:, 1], top[:, 2]))), 3),
            "from_west_to_north": round(float(np.degrees(np.arctan2(np.median(rows[:, 2]), np.median(rows[:, 1])))), 1),
            "whole": [round(float(v), 4) for v in b[:3]], "whole_R": round(float(np.corrcoef(X @ b, band[k])[0, 1]), 3)}


def mosaic_of(g: Ground, tiles: dict) -> np.ndarray:
    img = np.zeros((8192, 8192, 3), np.uint8)
    for k in tiles:
        a = g.art(k, 128)
        if a is not None:
            img[k % 64 * 128:k % 64 * 128 + 128, k // 64 * 128:k // 64 * 128 + 128] = np.clip(a, 0, 255)
    return img


def main() -> None:
    global SHIP
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "mm-fill"), help="the terrain read so far")
    ap.add_argument("--mosaic", help="the finished map, m<inst>.npy here")
    ap.add_argument("--fit", action="store_true", help="measure the sun and stop")
    ap.add_argument("--bake", help="also write the web demo's pictures here (relief.json, *.webp)")
    ap.add_argument("--sites", help="write before/after pictures here")
    ap.add_argument("--only", type=int, help="one continent")
    ap.add_argument("--ship", type=int, default=SHIP, help="px a chunk shipped (8, 4)")
    ns = ap.parse_args()
    SHIP = ns.ship
    src = source_from_args(ap, ns)
    import maplint
    data = maplint.Data(os.path.join(ROOT, "Data"))
    out_dir = os.path.join(ROOT, "demo", "relief_out")
    os.makedirs(out_dir, exist_ok=True)
    for old in os.listdir(out_dir):
        os.remove(os.path.join(out_dir, old))
    all_, baked, total = {}, {}, 0
    if ns.bake:
        os.makedirs(ns.bake, exist_ok=True)
    for inst in ((ns.only,) if ns.only is not None else (0, 1)):
        m = read(src, inst, data.tiles[inst], data.sea[inst], ns.cache)
        path = ns.mosaic and os.path.join(ns.mosaic, f"m{inst}.npy")
        img = np.load(path) if path and os.path.exists(path) else mosaic_of(Ground(src, inst, data.tiles[inst], data.sea[inst], ns.cache), data.tiles[inst])
        if ns.fit:
            log(f"[{inst}] {fit(img.astype(np.float32), m)}")
            continue
        sa, tint = picture(m, img, inst + 1), tint_of(m)
        rects, sa = regions(sa)
        rects.sort(key=lambda r: -r[2] * r[3])
        list_, shown = [], img.astype(np.float32)
        for n, (x, y, w, h) in enumerate(rects):
            p = texels(sa, tint, x, y, w, h)
            if not p[..., 3].any():
                continue
            over(shown[y * 8:(y + h) * 8, x * 8:(x + w) * 8], p if SHIP == 8 else np.asarray(Image.fromarray(p).resize((w * 8, h * 8), Image.BICUBIC)))
            name = f"Relief{inst}_{len(list_)}"
            raw = write_tga(p.shape[1], p.shape[0], [[tuple(int(v) for v in q) for q in row] for row in p])
            with open(os.path.join(out_dir, name + ".tga"), "wb") as f:
                f.write(raw)
            total += len(raw)
            if ns.bake:
                Image.fromarray(p, "RGBA").save(os.path.join(ns.bake, f"{inst}_{len(list_)}.webp"), lossless=True, method=4)
            list_.append({"file": f"{inst}_{len(list_)}.webp", "col": x, "row": y, "w": w, "h": h, "n": len(list_)})
        all_[inst] = list_
        log(f"[{inst}] {len(list_)} pictures, {sum(r['w'] * r['h'] for r in list_)} chunks of them, on {int((np.abs(sa).reshape(1024, 8, 1024, 8).max((1, 3)) >= MIN_ALPHA).sum())} chunks with relief, of {int(m.flat.sum())} flat")
        strength = np.abs(sa).reshape(1024, 8, 1024, 8).max((1, 3))
        log(f"[{inst}] chunks with alpha over .05: {int((strength > .05).sum())}, of them detail >= {DETAIL[1] + 2:.0f} (real ground): {int(((strength > .05) & (m.detail >= DETAIL[1] + 2)).sum())}")
        log(f"[{inst}] strongest alpha on: flat {strength[m.flat].max():.3f}, detail >= {DETAIL[1]:.0f} {strength[m.detail >= DETAIL[1]].max():.3f}, wet {strength[m.wet].max():.3f}, built {strength[m.built].max():.3f}, dark {strength[m.dark].max():.3f}")
        if ns.sites:
            os.makedirs(ns.sites, exist_ok=True)
            for name, (i, c0, r0, c1, r1) in SITES.items():
                if i != inst:
                    continue
                s = (r0 * 128, (r1 + 1) * 128, c0 * 128, (c1 + 1) * 128)
                a, b = img[s[0]:s[1], s[2]:s[3]], shown[s[0]:s[1], s[2]:s[3]].clip(0, 255).astype(np.uint8)
                gap = np.full((a.shape[0], 8, 3), 255, np.uint8)
                Image.fromarray(np.hstack([a, gap, b])).save(os.path.join(ns.sites, f"{name}.png"))
    if ns.fit:
        return
    log(f"{total / 1e6:.2f} MB of textures")
    if ns.bake:
        tmp = os.path.join(ns.bake, "relief.json.tmp")
        with open(tmp, "w") as f:
            json.dump({str(k): [{"file": r["file"], "col": r["col"] / 16, "row": r["row"] / 16, "w": r["w"] / 16, "h": r["h"] / 16} for r in v] for k, v in all_.items()}, f, separators=(",", ":"))
        os.replace(tmp, os.path.join(ns.bake, "relief.json"))
        named = {r["file"] for v in all_.values() for r in v}
        for old in os.listdir(ns.bake):  # after the json: it never names a picture that's gone
            if old.endswith(".webp") and old not in named:
                os.remove(os.path.join(ns.bake, old))
    with open(os.path.join(ROOT, "Data", "Relief.lua.new"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- GENERATED by tools/gen_relief.py from the terrain of {src.product} {src.version}. Do not edit.\n")
        f.write(f"-- [inst] = {{ n, col, row, w, h, ... }}: a picture, Textures/Relief<inst>_<n>: where (chunks, 16 a tile), {SHIP} px a chunk, filling its texture\n")
        f.write("local _, ns = ...\nlocal D = ns.Data or {}; ns.Data = D\n")  # (data_head, once FORMATS in mmtools/luaout.py has a Relief row)
        f.write("D.Relief = {\n")
        for inst, v in all_.items():
            f.write(f"  [{inst}] = {{\n")
            for r in v:
                f.write("    %d, %d, %d, %d, %d,\n" % (r["n"], r["col"], r["row"], r["w"], r["h"]))
            f.write("  },\n")
        f.write("}\n")


if __name__ == "__main__":
    main()

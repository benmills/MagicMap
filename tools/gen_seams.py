#!/usr/bin/env python3
"""Generate Data/Seams.lua and Textures/SeamMask*.tga: the harsh straight edges in Blizzard's minimap tiles softened.

The tiles were painted a chunk at a time, so where two paintings meet the join runs straight along the chunk grid. That's
how it's found, on the finished map (the tiles and the rebuilt ground, tools/gen_fill.py --bake): along a chunk's length, nearly
every row of px has its biggest step on one line, for two chunks or more (natural edges wander). The same test off the grid is
the check on it: --bake's log gives both counts.

Each stretch is softened by its own ground: the side with more detail, the strip beside the line mirrored over it (so it
meets itself there and no join is left), its far edge wandering (a mask of ours). Nothing comes from anywhere else. Left
alone: water, buildings, near-black ground and the rebuilt ground (whose own edges are soft).

The addon draws each piece from Blizzard's texture at runtime (ui/Fill.lua; NOTICE.md): this file holds where they go.

  python3 tools/gen_seams.py local "/Applications/World of Warcraft" wow_classic_beta --fill demo/fill --bake demo/seams
"""
from __future__ import annotations

import argparse
import json
import os
import tempfile

import numpy as np
from PIL import Image

from gen_fill import FLAT_WATER, Ground
from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.sources import add_source_args, source_from_args
from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PX = 8              # px a chunk it looks at
LOOK = 4            # px each side of a line a row's biggest step is looked for in
STEP = 24           # the least step that counts (the sum of three channels' 0-255)
SURE = .75          # the share of a chunk's rows that makes a line sure, for RUN chunks in a row
RUN = 2
MAYBE = .4          # ...and the share that carries a sure line on
DEPTH = 2           # chunks a piece reaches over the line, at most
LENGTHS = (1, 2, 4) # chunks a piece runs along it
VARIANTS = 4        # masks of a shape
MASK_PX = 16        # a mask's px a chunk


def mosaic(g: Ground, tiles: dict, sea: dict, fill: dict | None, fill_dir: str | None) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The finished map, PX a chunk; which tiles are land; which chunks the rebuilt ground shows on."""
    n = 16 * PX
    img, land = np.zeros((64 * n, 64 * n, 3), np.uint8), np.zeros((64, 64), bool)
    for k in tiles:
        a = g.art(k, n)
        if a is not None:
            c, r = k // 64, k % 64
            img[r * n:r * n + n, c * n:c * n + n], land[r, c] = np.clip(a, 0, 255), True
    covered = np.zeros((64 * 16, 64 * 16), bool)
    for f in fill or ():
        w, h = int(round(f["w"] * n)), int(round(f["h"] * n))
        x, y = int(round(f["col"] * n)), int(round(f["row"] * n))
        p = np.asarray(Image.open(os.path.join(fill_dir, f["file"])).convert("RGBA").resize((w, h), Image.BOX), np.float32)
        a = p[..., 3:] / 255
        img[y:y + h, x:x + w] = (img[y:y + h, x:x + w] * (1 - a) + p[..., :3] * a).astype(np.uint8)
        cells = a[..., 0].reshape(h // PX, PX, w // PX, PX).mean((1, 3))
        covered[y // PX:y // PX + h // PX, x // PX:x // PX + w // PX] |= cells > .05
    return img, land, covered


def agreement(img: np.ndarray, off: int = 0) -> np.ndarray:
    """f[n, x]: over chunk n of the line left of chunk-column x, the share of rows whose biggest step is on it. Lines down the rows."""
    h, w, _ = img.shape
    n = h // PX
    out = np.zeros((n, w // PX), np.float32)
    a = img.astype(np.int16)
    for x in range(PX + off, w - PX, PX):
        d = np.abs(a[:, x - LOOK:x + LOOK] - a[:, x - LOOK - 1:x + LOOK - 1]).sum(-1)
        out[:, x // PX] = ((d.argmax(1) == LOOK) & (d[:, LOOK] > STEP)).reshape(n, PX).mean(1)
    return out


def lines(f: np.ndarray) -> np.ndarray:
    """The chunks of a line that are seam: sure for RUN chunks, carried on while they might be."""
    sure = f >= SURE
    both = sure[:-1] & sure[1:]
    seed = np.zeros_like(sure)
    seed[:-1] |= both
    seed[1:] |= both
    maybe = f >= MAYBE
    out = seed.copy()
    for y in range(1, out.shape[0]):
        out[y] |= out[y - 1] & maybe[y]
    for y in range(out.shape[0] - 2, -1, -1):
        out[y] |= out[y + 1] & maybe[y]
    return out


def runs(e: np.ndarray) -> list[tuple[int, int, int]]:
    """Stretches (x, n0, n1) along each line."""
    out = []
    for x in np.nonzero(e.any(0))[0]:
        ns = np.nonzero(e[:, x])[0]
        for g in np.split(ns, np.nonzero(np.diff(ns) > 1)[0] + 1):
            out.append((int(x), int(g[0]), int(g[-1]) + 1))
    return out


def segments(n0: int, n1: int) -> list[tuple[int, int]]:
    """Pieces (start, length) along a stretch, a source tile at a time; they overlap: they show the same ground, so they join."""
    out, a = [], n0
    while a < n1:
        b = min(n1, (a // 16 + 1) * 16)
        p = b - a
        if p >= 4:
            out += [(s, 4) for s in list(range(a, b - 4, 3)) + [b - 4]]
        elif p == 3:
            out += [(a, 2), (a + 1, 2)]
        else:
            out.append((a, p))
        a = b
    return out


def mask_of(length: int, orient: int, variant: int) -> np.ndarray:
    """A piece's mask, 0..1: whole at the line, its far edge wandering, closing in at the ends. orient: where the piece lies from the line: 0 right, 1 left, 2 below, 3 above."""
    r = np.random.RandomState(length * 100 + variant)
    n, d = length * MASK_PX, DEPTH * MASK_PX
    along = np.arange(n) + .5
    def wave(knots):  # smooth: a line between points would come out sawtoothed
        k = np.interp(along / n * knots, np.arange(knots + 1), np.arange(knots + 1))
        i = np.minimum(k.astype(int), knots - 1)
        t = k - i
        v = r.rand(knots + 1)
        return v[i] + (v[i + 1] - v[i]) * (t * t * (3 - 2 * t))
    reach = (.25 + 1.45 * (.8 * wave(length) + .2 * wave(length * 2))) * MASK_PX
    reach = reach * np.minimum(1, np.minimum(along, n - along) / (MASK_PX * .5))
    a = np.clip((reach[None, :] - (np.arange(d)[:, None] + .5)) / (MASK_PX * .5) + .5, 0, 1)
    a = a * a * (3 - 2 * a)  # across, along
    if orient == 0:
        return a.T
    if orient == 1:
        return a.T[:, ::-1]
    return a if orient == 2 else a[::-1]


def pieces(g: Ground, img: np.ndarray, land: np.ndarray, covered: np.ndarray, v: np.ndarray, h: np.ndarray) -> list[dict]:
    """The pieces: for each stretch, each piece's place and the mirrored source."""
    wet, built = {}, {}

    def water(key):
        if key not in wet:
            ground, surface = g.heights_and_water(key)
            wet[key] = (ground < surface)[::8, ::8]
            built[key] = g.buildings(key)
        return wet[key], built[key]

    def fit(col, row):  # a chunk neither water, building nor near-black
        if not (0 <= col < 1024 and 0 <= row < 1024) or not land[row // 16, col // 16]:
            return False
        w, b = water(col // 16 * 64 + row // 16)
        return not (w[row % 16, col % 16] or b[row % 16, col % 16] or img[row * PX:row * PX + PX, col * PX:col * PX + PX].mean((0, 1)).max() < FLAT_WATER)

    out, variant = [], 0
    for axis, e in ((0, v), (1, h)):
        at = (lambda a, n: (a, n)) if axis == 0 else (lambda a, n: (n, a))  # (col, row) of a place on a line: a across, n along
        for x, n0, n1 in runs(e):
            for s, length in segments(n0, n1):
                sides = []
                for sign in (-1, 1):  # the source on this side of the line, the piece on the other
                    near = x if sign > 0 else x - 1
                    room = 16 - near % 16 if sign > 0 else near % 16 + 1
                    d = min(DEPTH, room)
                    src = [at(near + sign * i, s + j) for i in range(d) for j in range(length)]
                    dst = [at(x - (1 if sign > 0 else 0) - sign * i, s + j) for i in range(d) for j in range(length)]
                    tile = {(c // 16, r // 16) for c, r in src}
                    if len(tile) > 1 or not all(fit(c, r) and not covered[r, c] for c, r in src + dst):
                        continue
                    cs, rs = zip(*src)
                    box = img[min(rs) * PX:(max(rs) + 1) * PX, min(cs) * PX:(max(cs) + 1) * PX]
                    sides.append((float(box.std((0, 1)).mean()), sign, near, d, tile.pop()))
                if not sides:
                    continue
                _, sign, near, d, (tc, tr) = max(sides)
                orient = (0 if sign < 0 else 1) + axis * 2
                # the source's edge on the line and d chunks away, in the tile's chunks
                base = (near - (tc if axis == 0 else tr) * 16) + (1 if sign < 0 else 0)
                far = base + sign * d
                a0 = s - (tr if axis == 0 else tc) * 16
                place = x if sign < 0 else x - d
                if axis == 0:
                    p = {"col": place, "row": s, "w": d, "h": length, "l": base if sign < 0 else far, "r": far if sign < 0 else base, "t": a0, "b": a0 + length}
                else:
                    p = {"col": s, "row": place, "w": length, "h": d, "l": a0, "r": a0 + length, "t": base if sign < 0 else far, "b": far if sign < 0 else base}
                variant = (variant + 1) % VARIANTS
                out.append({**p, "key": tc * 64 + tr, "mask": length * 100 + orient * 10 + variant, "length": length, "orient": orient, "variant": variant})
    return out


def write_masks() -> None:
    for length in LENGTHS:
        for orient in range(4):
            for variant in range(VARIANTS):
                a = mask_of(length, orient, variant)
                rows = [[(255, 255, 255, int(round(float(v) * 255))) for v in line] for line in a]
                with open(os.path.join(ROOT, "Textures", f"SeamMask{length * 100 + orient * 10 + variant}.tga"), "wb") as f:
                    f.write(write_tga(a.shape[1], a.shape[0], rows))


def bake(g: Ground, list_: list, inst: int, out: str, px: int = 16) -> list:
    """The pieces as see-through pictures, a tile's at a time (the web demo's: it has no masks to draw with)."""
    groups, baked, tiles = {}, [], {}
    for p in list_:
        groups.setdefault((p["col"] // 16, p["row"] // 16), []).append(p)
    for (tc, tr), ps in groups.items():
        c0, r0 = min(p["col"] for p in ps), min(p["row"] for p in ps)
        c1, r1 = max(p["col"] + p["w"] for p in ps), max(p["row"] + p["h"] for p in ps)
        pic, alpha = np.zeros(((r1 - r0) * px, (c1 - c0) * px, 3), np.float32), np.zeros(((r1 - r0) * px, (c1 - c0) * px, 1), np.float32)
        for p in ps:
            if p["key"] not in tiles:
                tiles[p["key"]] = g.art(p["key"], 16 * px)
            l, r, t, b = p["l"], p["r"], p["t"], p["b"]
            src = tiles[p["key"]][min(t, b) * px:max(t, b) * px, min(l, r) * px:max(l, r) * px]
            src = src[::-1] if t > b else src
            src = src[:, ::-1] if l > r else src
            w_, h_ = p["w"] * px, p["h"] * px
            a = np.asarray(Image.fromarray(mask_of(p["length"], p["orient"], p["variant"])).resize((w_, h_), Image.BILINEAR), np.float32)[..., None]
            y, x = (p["row"] - r0) * px, (p["col"] - c0) * px
            pic[y:y + h_, x:x + w_] = pic[y:y + h_, x:x + w_] * (1 - a) + src * a  # (premultiplied)
            alpha[y:y + h_, x:x + w_] = alpha[y:y + h_, x:x + w_] * (1 - a) + a
        rgb = pic / np.maximum(alpha, 1e-3)
        name = f"{inst}_{tc}_{tr}.webp"
        Image.fromarray(np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8), "RGBA").save(os.path.join(out, name), quality=88, method=4)
        baked.append({"file": name, "col": c0 / 16, "row": r0 / 16, "w": (c1 - c0) / 16, "h": (r1 - r0) / 16})
    return baked


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--fill", default=os.path.join(ROOT, "demo", "fill"), help="the rebuilt ground's pictures (gen_fill.py --bake)")
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "mm-fill"), help="the terrain read so far")
    ap.add_argument("--bake", help="also write the web demo's pictures here (seams.json, *.webp)")
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import maplint
    data = maplint.Data(os.path.join(ROOT, "Data"))
    fill = json.load(open(os.path.join(ns.fill, "fill.json")))
    maps, baked = {}, {}
    for inst in (0, 1):
        g = Ground(src, inst, data.tiles[inst], data.sea[inst], ns.cache)
        img, land, covered = mosaic(g, data.tiles[inst], data.sea[inst], fill.get(str(inst)), ns.fill)
        turned = img.transpose(1, 0, 2)
        v, h = lines(agreement(img)), lines(agreement(turned))
        off = int(lines(agreement(img, PX // 2)).sum() + lines(agreement(turned, PX // 2)).sum())
        maps[inst] = pieces(g, img, land, covered, v, h)
        log(f"[{inst}] seam chunks on the grid {int(v.sum() + h.sum())}, off it (false alarms' rate) {off}; {len(maps[inst])} pieces")
        if ns.bake:
            os.makedirs(ns.bake, exist_ok=True)
            baked[inst] = bake(g, maps[inst], inst, ns.bake)
    write_masks()
    if ns.bake:
        with open(os.path.join(ns.bake, "seams.json"), "w") as f:
            json.dump({str(k): v for k, v in baked.items()}, f, separators=(",", ":"))
    with open(os.path.join(ROOT, "Data", "Seams.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- GENERATED by tools/gen_seams.py from the tiles of {src.product} {src.version}. Do not edit.\n")
        f.write("-- [inst] = { col, row, w, h, file, l, r, t, b, mask, ... }: a piece: where (chunks), its source (a tile's FileDataID,\n")
        f.write("--   the square of it in chunks: reversed, mirrored), Textures/SeamMask<mask>\n")
        f.write(data_head("Seams"))
        f.write("D.Seams = {\n")
        for inst, ps in maps.items():
            f.write(f"  [{inst}] = {{\n")
            for p in ps:
                f.write("    %d, %d, %d, %d, %d, %d, %d, %d, %d, %d,\n" % (p["col"], p["row"], p["w"], p["h"], data.tiles[inst][p["key"]], p["l"], p["r"], p["t"], p["b"], p["mask"]))
            f.write("  },\n")
        f.write("}\n")


if __name__ == "__main__":
    main()

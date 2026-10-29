#!/usr/bin/env python3
"""Generate Data/Clouds.lua: cloud puffs over the map's broken art (docs/hardening-plan.md M2, M4).

Blizzard's minimap tiles have unfinished land in them: flat untextured filler and stepped, chunk-aligned
patches of other art (tools/maplint.py's flat-land and patch-edge issues), the odd seam and a black hole
in the sea. The addon draws the game's tiles as they are (NOTICE.md), so it covers those places with the
game's own cloud: the adventure map's fog-of-war puff (UiTextureAtlasMember "fogofwar", one soft cloud),
stamped over and over, each sized, turned and flipped, until the place is covered (ui/Clouds.lua).

What to cover is the map review's call (M6): the issues accepted in docs/map-review.json (tools/review.py
--save), their chunks from the issues file (demo/lint/issues.json: a flat-land or patch-edge issue's
mask; a seam's edge or a sea-edge's tile by its box), grown by PAD chunks so the soft edge of the cloud
hides the hard edge of the art. Stamps go greedily: the uncovered chunk deepest inside its place gets the
next, as wide as that depth allows (WIDTH), until COVER of the place is GOAL covered. Deterministic.

  python3 tools/gen_clouds.py local "/Applications/World of Warcraft" wow_classic_beta -o Data/Clouds.lua
"""
from __future__ import annotations

import argparse
import io
import json
import os
import struct
import sys
from collections import deque

import numpy as np
from PIL import Image

from export_icons import UI_TEXTURE_ATLAS, UI_TEXTURE_ATLAS_MEMBER, read_table
from mmtools.log import log
from mmtools.luaout import data_head
from mmtools.sources import add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUFF = "fogofwar"      # the atlas member: one cloud
KINDS = ("flat-land", "patch-edge", "seam", "sea-edge")
CH = 16                # chunks a tile side
GRID = 64 * CH
RES = 2                # px a chunk the placement works at
PAD = 1                # chunks a place grows by
GOAL = 0.9             # a px this covered (1 - the product of the stamps' 1 - alpha) is covered
COVER = 0.97           # ...a place is done with this share of its px covered
WIDTH = (4.0, 0.3, 0.4, 1.6)  # a stamp's width in tiles: a * depth (tiles) + b, clamped to [lo, hi]
MAX_STAMPS = 400       # a place's at most


def blp_rgba(b: bytes) -> Image.Image:
    enc, _, _, _, w, h = struct.unpack_from("<BBBBII", b, 8)
    if enc == 3:
        off = struct.unpack_from("<I", b, 20)[0]
        return Image.frombytes("RGBA", (w, h), b[off:off + w * h * 4], "raw", "BGRA")
    return Image.open(io.BytesIO(b)).convert("RGBA")


def puff_of(src) -> tuple[dict, np.ndarray]:
    """The puff's atlas file and rect ({file, w, h, l, r, t, b}, texels) and its alpha (0..1)."""
    atlases = {a["ID"]: a for a in read_table("UiTextureAtlas", src.read(UI_TEXTURE_ATLAS))}
    m = next(m for m in read_table("UiTextureAtlasMember", src.read(UI_TEXTURE_ATLAS_MEMBER)) if m["CommittedName"] == PUFF)
    a = atlases[m["UiTextureAtlasID"]]
    rect = {"file": a["FileDataID"], "w": a["AtlasWidth"], "h": a["AtlasHeight"],
            "l": m["CommittedLeft"], "r": m["CommittedRight"], "t": m["CommittedTop"], "b": m["CommittedBottom"]}
    im = blp_rgba(src.read(a["FileDataID"])).crop((rect["l"], rect["t"], rect["r"], rect["b"]))
    return rect, np.asarray(im.getchannel("A"), np.float32) / 255


def oriented(alpha: np.ndarray, turn: int) -> np.ndarray:
    """turn 0-3: quarter turns clockwise; +4: mirrored left to right first (ui/Clouds.lua's texcoords)."""
    a = alpha[:, ::-1] if turn >= 4 else alpha
    return np.rot90(a, -(turn % 4))


def places(issues: list, decisions: dict, inst: int) -> np.ndarray:
    """The accepted issues' chunks on inst."""
    t = np.zeros((GRID, GRID), bool)
    for i in issues:
        if i["inst"] != inst or i["kind"] not in KINDS or decisions.get(i["id"], {}).get("status") != "accepted":
            continue
        m = i.get("mask")
        if m:
            cells, pos, on = np.zeros(m["h"] * m["w"], bool), 0, False
            for n in m["rle"]:
                cells[pos:pos + n] = on
                pos, on = pos + n, not on
            t[m["y0"]:m["y0"] + m["h"], m["x0"]:m["x0"] + m["w"]] |= cells.reshape(m["h"], m["w"])
        else:
            c0, r0, c1, r1 = (int(round(v * CH)) for v in i["bbox"])
            t[max(0, r0 - 2):r1 + 2, max(0, c0 - 2):c1 + 2] = True  # an edge's box is a line: 2 chunks each side
    return t


def grow(t: np.ndarray, n: int) -> np.ndarray:
    for _ in range(n):
        g = t.copy()
        g[1:] |= t[:-1]
        g[:-1] |= t[1:]
        g[:, 1:] |= t[:, :-1]
        g[:, :-1] |= t[:, 1:]
        t = g
    return t


def depth(t: np.ndarray) -> np.ndarray:
    """Chunks to the nearest chunk outside t (4-way steps), in t; 0 outside."""
    d = np.zeros(t.shape, np.int32)
    q = deque()
    h, w = t.shape
    for y, x in zip(*np.nonzero(t)):
        if y in (0, h - 1) or x in (0, w - 1) or not (t[y - 1, x] and t[y + 1, x] and t[y, x - 1] and t[y, x + 1]):
            d[y, x] = 1
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and t[ny, nx] and not d[ny, nx]:
                d[ny, nx] = d[y, x] + 1
                q.append((ny, nx))
    return d


def components(t: np.ndarray) -> list[tuple[slice, slice]]:
    """The boxes of t's 8-connected parts."""
    seen, out = np.zeros_like(t), []
    h, w = t.shape
    for y0, x0 in zip(*np.nonzero(t)):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        q, ys, xs = deque([(y0, x0)]), [], []
        while q:
            y, x = q.popleft()
            ys.append(y)
            xs.append(x)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and t[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
        out.append((slice(min(ys), max(ys) + 1), slice(min(xs), max(xs) + 1)))
    return out


def stamp_alpha(alpha: np.ndarray, turn: int, width: float, cache: dict) -> np.ndarray:
    """The puff at width tiles (its height in proportion), turned: px at RES a chunk."""
    key = (turn, round(width, 3))
    if key not in cache:
        a = oriented(alpha, turn)
        aw = width * CH * RES * (a.shape[1] / (alpha.shape[1] if turn % 2 == 0 else alpha.shape[0]))
        ah = aw * a.shape[0] / a.shape[1]
        cache[key] = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize(
            (max(1, round(aw)), max(1, round(ah))), Image.BILINEAR), np.float32) / 255
    return cache[key]


def place(t: np.ndarray, alpha: np.ndarray, cache: dict) -> list[tuple[float, float, float, int]]:
    """Stamps over t's parts: (col, row centre in tiles, width in tiles, turn)."""
    out = []
    for sy, sx in components(t):
        M = 24  # chunks of margin round a part: a stamp's reach
        y0, x0 = max(0, sy.start - M), max(0, sx.start - M)
        sub = t[y0:sy.stop + M, x0:sx.stop + M]
        d = depth(sub)
        want = np.kron(sub, np.ones((RES, RES), bool))
        cov = np.zeros(want.shape, np.float32)
        n0 = int(want.sum())
        for k in range(MAX_STAMPS):
            need = want & (cov < GOAL)
            if need.sum() <= n0 * (1 - COVER):
                break
            nd = need.reshape(sub.shape[0], RES, sub.shape[1], RES).any(axis=(1, 3))
            score = np.where(nd, d, 0)
            cy, cx = np.unravel_index(int(np.argmax(score)), score.shape)  # deepest uncovered, first in row order
            a_, b_, lo, hi = WIDTH
            width = min(hi, max(lo, a_ * score[cy, cx] / CH + b_))
            turn = (cy * 7 + cx * 13 + k * 5) % 8
            s = stamp_alpha(alpha, turn, width, cache)
            py, px = (cy + .5) * RES - s.shape[0] / 2, (cx + .5) * RES - s.shape[1] / 2
            Y0, X0 = int(round(py)), int(round(px))
            ys, xs = slice(max(0, Y0), min(cov.shape[0], Y0 + s.shape[0])), slice(max(0, X0), min(cov.shape[1], X0 + s.shape[1]))
            part = s[ys.start - Y0:ys.stop - Y0, xs.start - X0:xs.stop - X0]
            cov[ys, xs] = 1 - (1 - cov[ys, xs]) * (1 - part)
            out.append(((x0 + cx + .5) / CH, (y0 + cy + .5) / CH, width, turn))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--issues", default=os.path.join(ROOT, "demo", "lint", "issues.json"))
    ap.add_argument("--review", default=os.path.join(ROOT, "docs", "map-review.json"))
    ap.add_argument("-o", "--output", help="output file (default: stdout)")
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    rect, alpha = puff_of(src)
    issues = json.load(open(ns.issues))["issues"]
    decisions = json.load(open(ns.review))["decisions"]
    cache, maps = {}, {}
    for inst in (0, 1):
        t = grow(places(issues, decisions, inst), PAD)
        maps[inst] = place(t, alpha, cache)
        log(f"[{inst}] {int(t.sum())} chunks to cover: {len(maps[inst])} clouds")
    out = open(ns.output, "w", encoding="utf-8", newline="\n") if ns.output else sys.stdout
    w = out.write
    w(f"-- GENERATED by tools/gen_clouds.py from the map review's accepted issues ({os.path.relpath(ns.review, ROOT)}) and the\n")
    w(f"-- {src.product} {src.version} atlas \"{PUFF}\". Do not edit.\n")
    w("-- puff: the cloud's texture (file, its size, the cloud's rect in it: left, right, top, bottom texels)\n")
    w("-- [inst] = { col, row, width, turn, ... }: a cloud's centre (tile units), width (tiles; its height in\n")
    w("--   proportion), turn 0-3 quarter turns clockwise, +4 mirrored first\n")
    w(data_head("Clouds"))
    w("D.Clouds = {\n")
    w("  puff = { file = %d, w = %d, h = %d, l = %d, r = %d, t = %d, b = %d },\n" % tuple(
        rect[k] for k in ("file", "w", "h", "l", "r", "t", "b")))
    for inst, stamps in maps.items():
        w(f"  [{inst}] = {{\n")
        for x, y, wd, turn in stamps:
            w("    %.3f, %.3f, %.3f, %d,\n" % (x, y, wd, turn))
        w("  },\n")
    w("}\n")
    if out is not sys.stdout:
        out.close()


if __name__ == "__main__":
    main()

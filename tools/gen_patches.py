#!/usr/bin/env python3
"""Generate Textures/Patch*.tga, Textures/Wash*.tga and Data/Patches.lua: water for the sea tiles that leave a
block in the sea, and a wash of colour over the broken land under the clouds.

An open-sea tile (Data/TileColor.lua) isn't drawn, the backdrop shows; where its neighbour's shallows run up to
its side, that's a tile-aligned block (tools/maplint.py's sea-edge). The ones the map review accepted
(docs/map-review.json) get a picture of their own, in the place of Blizzard's tile (Atlas.TileArt): the colours
along the four neighbours' edges (the backdrop's beside a sea tile; a beach on an edge bridged by the water either
side of it, so it doesn't bleed in), smoothed across the tile (a harmonic fill). No detail of anyone's art in it: water with no edge.

The land the clouds cover (tools/gen_clouds.py's places, grown by WASH_PAD chunks) gets the same, a part at a time:
the colours of the ground round it, smoothed across it, its alpha fading out at its edge (Atlas.Washes, drawn over the
tiles). The hard edges and colour jumps go, so the thin clouds over them have little to hide. Square, power-of-two
textures (WASH_RES px a chunk), the part centred in each, clear round it.

  python3 tools/gen_patches.py local "/Applications/World of Warcraft" wow_classic_beta
"""
from __future__ import annotations

import argparse
import glob
import json
import os

import numpy as np
from PIL import Image

from PIL import ImageFilter

from gen_clouds import CH, blp_rgba, components, grow, places
from mmtools.log import log
from mmtools.luaout import data_head, load_data
from mmtools.sources import add_source_args, source_from_args
from mmtools.tga import write_tga
from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 128       # px a side
EDGE = 2         # px of a neighbour's edge its colour is read from
SAND = 0.8       # red over green past this, and...
BRIGHT = 60      # ...any channel past this (0-255): not water
SWEEPS = 300     # a level's smoothing passes
WASH_PAD = 3     # chunks a wash's place grows by round the clouds' places
WASH_RES = 2     # px a chunk
WASH_MARGIN = 2  # px of ground round a part, to read its colours from
WASH_EDGE = 1    # chunks in from a part's edge its alpha starts
WASH_BLUR = 3.0  # px: how soft that fade is


def bridged(v: np.ndarray) -> np.ndarray:
    """An edge's colours with its sand replaced by the water either side."""
    water = ~((v[:, 0] > v[:, 1] * SAND) & (v.max(1) > BRIGHT) | (v.max(1) > 2 * BRIGHT))
    x = np.arange(len(v))
    return np.stack([np.interp(x, x[water], v[water, k]) for k in range(3)], 1) if water.any() else v


def edge_colours(src, tiles: dict, sea: dict, bg: list, col: int, row: int) -> dict:
    """The colours just over each side of the tile, SIZE px along it: n, s, w, e."""
    def art(c, r):
        k = c * 64 + r
        if k not in tiles or k in sea:
            return np.tile(np.array(bg) * 255, (SIZE, SIZE, 1))
        return np.asarray(blp_rgba(src.read(tiles[k])).convert("RGB").resize((SIZE, SIZE), Image.BILINEAR), np.float64)
    return {k: bridged(v) for k, v in (("n", art(col, row - 1)[-EDGE:, :].mean(0)), ("s", art(col, row + 1)[:EDGE, :].mean(0)),
                                       ("w", art(col - 1, row)[:, -EDGE:].mean(1)), ("e", art(col + 1, row)[:, :EDGE].mean(1)))}


def fill(edges: dict) -> np.ndarray:
    """The tile, SIZE x SIZE x 3: a harmonic fill between its edges, coarse to fine."""
    u, n = None, 8
    while n <= SIZE:
        f = SIZE // n
        e = {k: v.reshape(n, f, 3).mean(1) for k, v in edges.items()}
        u = np.full((n, n, 3), np.mean([v.mean(0) for v in e.values()], axis=0)) if u is None else u.repeat(2, 0).repeat(2, 1)
        for _ in range(SWEEPS):
            p = np.pad(u, ((1, 1), (1, 1), (0, 0)))
            p[0, 1:-1], p[-1, 1:-1], p[1:-1, 0], p[1:-1, -1] = e["n"], e["s"], e["w"], e["e"]
            u = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4
        n *= 2
    return u


def harmonic(img: np.ndarray, hole: np.ndarray) -> np.ndarray:
    """img (n x n x 3, n a power of two) with its hole smoothed across from what's round it, coarse to fine."""
    n = len(img)
    if n <= 4 or hole.all():
        u = img.copy()
        u[hole] = img[~hole].mean(0) if (~hole).any() else 0
        return u
    known = (~hole)[..., None].astype(np.float64)
    w = known.reshape(n // 2, 2, n // 2, 2, 1).sum((1, 3))
    small = (img * known).reshape(n // 2, 2, n // 2, 2, 3).sum((1, 3)) / np.maximum(w, 1)
    coarse = harmonic(small, w[..., 0] == 0).repeat(2, 0).repeat(2, 1)
    u = img.copy()
    u[hole] = coarse[hole]
    for _ in range(40):
        p = np.pad(u, ((1, 1), (1, 1), (0, 0)), mode="edge")
        v = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4
        u[hole] = v[hole]
    return u


def washes(src, issues: list, decisions: dict, tiles: dict, sea: dict, bg: list, inst: int) -> list:
    """The parts of inst's broken land: [(col, row of the texture's corner, its side, in tiles; RGBA n x n x 4)]."""
    t = grow(places(issues, decisions, inst), WASH_PAD)
    px = CH * WASH_RES
    art = {}

    def tile(k):
        if k not in art:
            art[k] = (np.asarray(blp_rgba(src.read(tiles[k])).convert("RGB").resize((px, px), Image.BILINEAR), np.float64)
                      if k in tiles and k not in sea else np.tile(np.array(bg) * 255, (px, px, 1)))
        return art[k]
    out = []
    for sy, sx in components(t):
        h, w = (sy.stop - sy.start) * WASH_RES, (sx.stop - sx.start) * WASH_RES
        n = 2 ** int(np.ceil(np.log2(max(h, w) + 2 * WASH_MARGIN)))
        x0, y0 = sx.start * WASH_RES - (n - w) // 2, sy.start * WASH_RES - (n - h) // 2  # px on the whole map
        img = np.zeros((n, n, 3))
        for r in range(y0 // px, (y0 + n - 1) // px + 1):
            for c in range(x0 // px, (x0 + n - 1) // px + 1):
                ay, ax = max(y0, r * px), max(x0, c * px)
                by, bx = min(y0 + n, (r + 1) * px), min(x0 + n, (c + 1) * px)
                img[ay - y0:by - y0, ax - x0:bx - x0] = tile(c * 64 + r)[ay - r * px:by - r * px, ax - c * px:bx - c * px]
        hole = np.zeros((n, n), bool)
        part = t[sy, sx].repeat(WASH_RES, 0).repeat(WASH_RES, 1)
        hole[sy.start * WASH_RES - y0:sy.stop * WASH_RES - y0, sx.start * WASH_RES - x0:sx.stop * WASH_RES - x0] = part
        fill_ = harmonic(img, hole)
        inner = hole.copy()
        for _ in range(WASH_EDGE * WASH_RES):
            g = inner.copy()
            g[1:] &= inner[:-1]
            g[:-1] &= inner[1:]
            g[:, 1:] &= inner[:, :-1]
            g[:, :-1] &= inner[:, 1:]
            inner = g
        a = np.asarray(Image.fromarray((inner * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(WASH_BLUR)), np.float64) * hole
        out.append((x0 / px, y0 / px, n / px, np.dstack([fill_, a])))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--issues", default=os.path.join(ROOT, "demo", "lint", "issues.json"))
    ap.add_argument("--review", default=os.path.join(ROOT, "docs", "map-review.json"))
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    decisions = json.load(open(ns.review))["decisions"]
    lua = lua51.LuaRuntime()
    D = lua.table()
    load_data(lua, os.path.join(ROOT, "Data", "Tiles.lua"), D)
    load_data(lua, os.path.join(ROOT, "Data", "TileColor.lua"), D)
    issues = json.load(open(ns.issues))["issues"]
    out = {}
    for i in issues:
        if i["kind"] != "sea-edge" or decisions.get(i["id"], {}).get("status") != "accepted":
            continue
        inst, col, row = i["inst"], int(i["bbox"][0]), int(i["bbox"][1])
        m = D.Data.Tiles.maps[inst]
        tiles, sea = dict(m.tiles.items()), dict(D.Data.TileColor[inst].sea.items())
        pic = fill(edge_colours(src, tiles, sea, list(m.bg.values()), col, row))
        name = f"Patch{inst}_{col}_{row}"
        rows = [[(*(int(round(v)) for v in px), 255) for px in line] for line in pic]
        with open(os.path.join(ROOT, "Textures", name + ".tga"), "wb") as f:
            f.write(write_tga(SIZE, SIZE, rows))
        out.setdefault(inst, {})[col * 64 + row] = "Textures\\\\" + name
        log(f"[{inst}] {col},{row}: {name}")
    for old in glob.glob(os.path.join(ROOT, "Textures", "Wash*.tga")):
        os.remove(old)
    wash = {}
    for inst in (0, 1):
        m = D.Data.Tiles.maps[inst]
        tiles, sea = dict(m.tiles.items()), dict(D.Data.TileColor[inst].sea.items())
        wash[inst] = []
        for k, (col, row, side, pic) in enumerate(washes(src, issues, decisions, tiles, sea, list(m.bg.values()), inst), 1):
            name = f"Wash{inst}_{k}"
            rows = [[tuple(int(round(v)) for v in px) for px in line] for line in pic]
            with open(os.path.join(ROOT, "Textures", name + ".tga"), "wb") as f:
                f.write(write_tga(len(pic), len(pic), rows))
            wash[inst].append((name, col, row, side))
        log(f"[{inst}] {len(wash[inst])} washes")
    with open(os.path.join(ROOT, "Data", "Patches.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- GENERATED by tools/gen_patches.py from the map review's accepted issues ({os.path.relpath(ns.review, ROOT)}). Do not edit.\n")
        f.write("-- Patches[inst] = { [col * 64 + row] = the picture drawn for that sea tile (under the addon's folder, no extension) }\n")
        f.write("-- Washes[inst] = { file, col, row, side, ... }: a wash's picture, its corner and side in tiles\n")
        f.write(data_head("Patches"))
        f.write("D.Patches = {\n")
        for inst, ps in out.items():
            f.write(f"  [{inst}] = {{ " + ", ".join(f'[{k}] = "{v}"' for k, v in ps.items()) + " },\n")
        f.write("}\nD.Washes = {\n")
        for inst, ws in wash.items():
            f.write(f"  [{inst}] = {{\n")
            for name, col, row, side in ws:
                f.write(f'    "Textures\\\\{name}", {col:.4f}, {row:.4f}, {side:.4f},\n')
            f.write("  },\n")
        f.write("}\n")


if __name__ == "__main__":
    main()

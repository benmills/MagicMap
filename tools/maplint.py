#!/usr/bin/env python3
"""Score the map's quality and list its issues (docs/hardening-plan.md M1-M5), to hill-climb and ratchet it.

The primary output is an issues file (--issues FILE, JSON; schema below; the reviewed one is docs/map-issues.json,
its marks docs/map-review.json): one issue per thing to look at, each with a stable id, so marks survive reruns. Its summary holds
the scores (each a count or a share, lower is better) that --baseline ratchets.

Checks (issue kinds in brackets):

  data       game-derived Data/*.lua headers all name one build (with an install found, the installed
             client's) [data] (M1).
  skipped    tiles not drawn (Data/TileColor.lua sea) where the base picture (Data/Base.lua,
             Textures/Base*.blp) shows land or the tile's art strays from the backdrop (by over SEA_EDGE, past
             the solid stripes some empty tiles have along their edges) [skipped-tile]; and, with art, where a drawn
             neighbour's water at the shared edge is far from the backdrop that shows in the skipped tile's
             place: a tile-aligned block in the sea [sea-edge] (M1).
  flat       flat untextured land: a chunk (1/16 tile, 4x4 px of the 64 px art) whose grey std is under
             FLAT_STD and that isn't water; connected regions [flat-land] (M2). Also smooth natural ground
             (snow, sand, smooth grass): none the 70532 review rejected has liquid (MH2O), and no rule found
             separates them from the filler by colour, size, heights or texture layers.
  seams      tile edges whose jump is SEAM_RATIO times the tiles' own variation [seam]; tiles whose colour
             jumps at their own edges on BLOCK_SIDES of their drawn sides, as seams or as one colour offset
             BLOCK_SHIFT times the gradient beside the edges (a misplaced or tinted tile) [colour-block] (M4).
  patches    straight colour edges along the chunk grid inside the art: a chunk line (also a tile edge) whose band
             colours either side are PATCH_JUMP apart and PATCH_RATIO times the gradient beside it, in runs of
             PATCH_RUN chunks or more; runs within PATCH_NEAR chunks grouped, a group with PATCH_EDGE chunks of
             edge an issue: a stepped, chunk-aligned patch of other art (pale or green squares by the flat filler
             east of Loch Modan) [patch-edge] (M2, M4).

Water is a chunk Walk.lua calls water or one in a tile not drawn (open sea) or missing; with art also one
whose pixels are mostly the minimap's water colour (WATER_*: dark, green to blue). Data-only scores use the
first alone, so they're the same with art and without.

The art is the web demo's export (demo/tiles/<inst>/64/<key>.webp, gitignored: --tiles, default demo/tiles
or $MAGICMAP_TILES), or the install's tiles (--wow INSTALL: decoded and shrunk to 64 px as
demo/export_tiles.py does, without its WebP: cached in --out). Note the WebP lifts the dark sea (BLP
(5,7,7) -> WebP (8,17,16)), so sea-edge reads the demo's look with --tiles, the game's with --wow. Without
art the art checks are skipped and their scores left out; --baseline compares the scores both sides have.

  .venv/bin/python tools/maplint.py                         # the text report
  .venv/bin/python tools/maplint.py --issues FILE           # the issues file (- for stdout)
  .venv/bin/python tools/maplint.py --baseline tools/maplint-baseline.json   # exit 1 if any score is worse
  .venv/bin/python tools/maplint.py --write-baseline tools/maplint-baseline.json
  .venv/bin/python tools/maplint.py --wow "/Applications/World of Warcraft" --overlays   # + debug PNGs in --out

Issues file (schema 1):
  { schema: 1, build: Data/Tiles.lua's, commit: git HEAD (+"-dirty"), generated: ISO time,
    art: { "<inst>": source or null },
    summary: { scores: { "<name>": number }, counts: { "<kind>": n } },
    issues: [ { id, kind, inst, bbox: [c0, r0, c1, r1], centroid: [col, row], severity, zone, desc,
                metrics: {...}, mask?: { x0, y0, w, h, rle } } ] }
  Positions are tile space (Data: col, row 0..64). id = "<kind>:<inst>:<place>", place a rounded tile, an
  edge, a zone's areaID or a file name: stable across reruns and small threshold changes. severity: higher
  is worse, comparable within a kind. mask (flat-land; at most MASK_RUNS runs): the chunks (16 a tile) in the box x0, y0 (chunk units), w by
  h, row by row as run lengths, off first (the runs alternate off, on, ...; what follows the last is
  off). Data issues have inst -1 and no place on the map.

Web-demo links use the demo's hash, #map=<inst>&view=2d&x=<col>&y=<row>&z=<px per tile> (tile space), on
--demo (default http://localhost:8000/, demo/server.py). The demo is one map now (demo/README.md): these links' x and y
are the issue's own map's, so only Kalimdor's land where they should; the review panel's own links are right.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lupa import lua51  # noqa: E402

from mmtools.formats import blp_dxt  # noqa: E402
from mmtools.luaout import load_data  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Debug output never goes into the repo: $MAGICMAP_LINT_OUT, else the temp dir.
SCRATCH = os.environ.get("MAGICMAP_LINT_OUT") or os.path.join(tempfile.gettempdir(), "maplint")
CONTINENTS = {0: "EasternKingdoms", 1: "Kalimdor"}
CH = 16              # chunks a tile side
GRID = 64 * CH       # chunks a map side
PX = 64              # the art's side as read (the demo's smallest copy)
CPX = PX // CH       # px a chunk

FLAT_STD = 1.5       # a chunk's grey std under this (0..255) is flat
FLAT_REGION = 4      # chunks: a smaller flat region is counted, not an issue
SEAM_RATIO, SEAM_JUMP = 3.0, 6.0   # an edge's jump over 3x the tiles' own variation, and over 6
BLOCK_SIDES = 3      # a colour block's edges jump on this many of its drawn sides (of 4)...
BLOCK_SHIFT = 2.0    # ...as seams, or as one colour offset this many times the gradient beside the edges
SHIFT_BAND = 4       # px: the edge bands whose mean colours the offset compares
SKIP_BASE, SKIP_ART = 0.02, 0.02   # share of a sea tile that's land in the base picture / its art
PATCH_JUMP = 25.0     # sum |RGB| between the 2 px bands either side of a chunk line...
PATCH_RATIO = 3.0     # ...and this many times the gradient beside it (+1): a hard edge
PATCH_RUN = 3         # chunks: a straight run of hard edge this long counts
PATCH_NEAR = 3        # chunks: runs this near are one patch...
PATCH_EDGE = 4        # ...an issue with this many chunks of edge
STRIPE_STD = 3.0     # an edge line of a sea tile's art this uniform (RGB std) and off the backdrop is a painted stripe
SEA_EDGE = 8.0       # mean |RGB| between a drawn neighbour's edge water and the backdrop
MASK_RUNS = 4000     # an issue's mask at most this many runs (else left out)
TOL = 1e-9

# Water: dark and green to blue (R low, G at least R, B over WATER_BG G), or nearly black. gen_base.py's test
# with B > 0.5 G missed the dark green-tinted sea along coasts (~(17,32,16)); this one, against the ADT liquids
# (MH2O) of 70532's drawn tiles, finds 83% of water chunks in EK (was 70%; Kalimdor 79%, was 63%) and calls 20 of
# 87k dry chunks water (was 50). The unfinished filler (hardening-plan M2: R over 50) stays land.
WATER_R, WATER_BG, BLACK = 24, 0.3, 14


# --- reading -----------------------------------------------------------------------

def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def runs(cells: str) -> list[int]:
    """Letter cells with run lengths (Walk.lua, AreaGrid.lua): the letters' values."""
    out, i, n = [], 0, len(cells)
    while i < n:
        ch = cells[i]
        i += 1
        j = i
        while j < n and cells[j].isdigit():
            j += 1
        k = int(cells[i:j]) if j > i else 1
        i = j
        out += [(ord(ch) - 97) if ch.islower() else (ord(ch) - 65 + 26)] * k
    return out


def header_builds(data_dir: str) -> dict[str, str]:
    """Data file -> the game build its header names (files from QuestieDB alone name none)."""
    out = {}
    for f in sorted(os.listdir(data_dir)):
        if f.endswith(".lua"):
            with open(os.path.join(data_dir, f), encoding="utf-8") as fh:
                text = fh.read() if f == "Repaint.lua" else fh.readline()
            # Repaint.lua's header names the build it was painted on; the build it's good for is the one ai_map.py stamps
            m = re.search(r'D\.Repaint = \{ build = "(\d+\.\d+\.\d+\.\d+)"' if f == "Repaint.lua" else r"\bwow\w* (\d+\.\d+\.\d+\.\d+)", text)
            if m:
                out[f] = m.group(1)
    return out


def installed_build(wow: str | None, product: str) -> str | None:
    """The installed client's version from its .build.info, or None."""
    try:
        with open(os.path.join(wow, ".build.info"), encoding="utf-8") as f:
            rows = [line.rstrip("\n").split("|") for line in f if line.strip()]
    except (OSError, TypeError):
        return None
    cols = [c.split("!")[0] for c in rows[0]]
    for r in rows[1:]:
        row = dict(zip(cols, r))
        if row.get("Product") == product:
            return row.get("Version")
    return None


def git_commit() -> str | None:
    try:
        head = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True, timeout=5).stdout.strip()
        dirty = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--untracked-files=no"], capture_output=True, text=True, timeout=5).stdout.strip()
        return (head + ("-dirty" if dirty else "")) or None
    except (OSError, subprocess.SubprocessError):
        return None


def dxt_rgb(img) -> np.ndarray:
    """A DxtImage (mmtools.formats) decoded with numpy: (h, w, 3) uint8."""
    bw, bh, bb = img.blocks_wide, img.blocks_high, img.block_bytes
    raw = np.frombuffer(img.data, np.uint8, bw * bh * bb, img.offset).reshape(bw * bh, bb)[:, bb - 8:]
    c0 = raw[:, 0].astype(np.uint32) | (raw[:, 1].astype(np.uint32) << 8)
    c1 = raw[:, 2].astype(np.uint32) | (raw[:, 3].astype(np.uint32) << 8)
    idx = raw[:, 4:8].copy().view("<u4")[:, 0]

    def c565(c):
        return np.stack([((c >> 11) & 31) / 31, ((c >> 5) & 63) / 63, (c & 31) / 31], 1)
    p0, p1 = c565(c0), c565(c1)
    four = ((c0 > c1) | (bb == 16))[:, None]
    p2 = np.where(four, (2 * p0 + p1) / 3, (p0 + p1) / 2)
    p3 = np.where(four, (p0 + 2 * p1) / 3, 0.0)
    pal = np.round(np.stack([p0, p1, p2, p3], 1) * 255).astype(np.uint8)        # (n, 4, 3)
    ids = (idx[:, None] >> (2 * np.arange(16, dtype=np.uint32))) & 3            # (n, 16)
    px = pal[np.arange(len(ids))[:, None], ids]                                 # (n, 16, 3)
    px = px.reshape(bh, bw, 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(bh * 4, bw * 4, 3)
    return px[:img.height, :img.width]


def tile_slice(k: int) -> tuple[slice, slice]:
    c, r = k // 64, k % 64
    return slice(r * CH, (r + 1) * CH), slice(c * CH, (c + 1) * CH)


class Data:
    """The Data files the checks read, as Python and chunk grids (GRID x GRID, [y, x])."""

    def __init__(self, data_dir: str):
        lua = lua51.LuaRuntime()
        ns = lua.table()
        for name in ("Tiles", "TileColor", "Base", "Areas", "AreaGrid", "Walk"):
            load_data(lua, os.path.join(data_dir, name + ".lua"), ns)
        D = ns.Data
        self.version = D.Tiles.version
        self.tiles, self.sea, self.bg, self.base, self.walk, self.zone_grid = {}, {}, {}, {}, {}, {}
        areas = {int(k): (v[1], v[2]) for k, v in D.Areas.items()}
        self.names = {k: v[0] for k, v in areas.items()}

        def top(a):
            for _ in range(8):
                p = areas.get(a, (None, None))[1]
                if p is None:
                    return a
                a = int(p)
            return a
        for inst in CONTINENTS:
            m = D.Tiles.maps[inst]
            self.tiles[inst] = {int(k): int(v) for k, v in m.tiles.items()}
            tc = D.TileColor[inst]
            self.sea[inst] = {int(k) for k, v in tc.sea.items() if v} if tc else set()
            self.bg[inst] = tuple(round(m.bg[i] * 255) for i in (1, 2, 3))
            b = D.Base[inst] if D.Base else None
            self.base[inst] = {k: b[k] for k in ("file", "c0", "r0", "c1", "r1", "px", "w", "h")} if b else None
            walk = np.full((GRID, GRID), -1, np.int16)  # Walk's value: class (& 3) + 4 east + 8 south; -1 none
            for k, cells in D.Walk[inst].items():
                walk[tile_slice(int(k))] = np.array(runs(cells), np.int16).reshape(CH, CH)
            self.walk[inst] = walk
            zg = np.zeros((GRID, GRID), np.int32)
            for k, enc in D.AreaGrid[inst].items():
                pal = [int(x) for x in lua_list(enc[1])]
                zg[tile_slice(int(k))] = np.array([top(pal[i]) if pal[i] else 0 for i in runs(enc[2])], np.int32).reshape(CH, CH)
            self.zone_grid[inst] = zg


# --- the art -----------------------------------------------------------------------------

def art_from_dir(d: str, inst: int, keys) -> dict[int, np.ndarray]:
    out, sub = {}, os.path.join(d, str(inst), str(PX))
    if os.path.isdir(sub):
        for k in keys:
            p = os.path.join(sub, f"{k}.webp")
            if os.path.exists(p):
                out[k] = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)
    return out


def art_from_install(wow: str, product: str, inst: int, tiles: dict[int, int], cache_dir: str) -> dict[int, np.ndarray]:
    from mmtools.sources import open_source
    src = open_source("local", product, install=wow)
    path = os.path.join(cache_dir, f"art-{src.version}-{inst}.npz")
    if os.path.exists(path):
        z = np.load(path)
        return {int(k): z[k].astype(np.float32) for k in z.files}
    src.prefetch(tiles.values())
    out = {}
    for k, fdid in sorted(tiles.items()):
        blp = src.read(fdid)
        img = blp_dxt(blp) if blp else None
        if img is not None:
            out[k] = np.asarray(Image.fromarray(dxt_rgb(img)).resize((PX, PX), Image.LANCZOS), dtype=np.float32)
    os.makedirs(cache_dir, exist_ok=True)
    np.savez_compressed(path, **{str(k): v.astype(np.uint8) for k, v in out.items()})
    return out


def water_px(a: np.ndarray) -> np.ndarray:
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return ((r < WATER_R) & (g >= r) & (b > g * WATER_BG)) | (a.max(-1) < BLACK)


def unstriped(a: np.ndarray, bgc: np.ndarray) -> np.ndarray:
    """A sea tile's art without the solid stripes Blizzard paints along some empty tiles' edges (magenta on GM
    Island, pale yellow east of Kalimdor; 4-8 px at 64): edge lines, uniform and off the backdrop, and the
    resampled line past them."""
    def band(lines):
        n = 0
        for ln in lines:
            if ln.std(0).max() >= STRIPE_STD or np.abs(ln.mean(0) - bgc).max() <= SEA_EDGE:
                break
            n += 1
        return n + 1 if n else 0
    h = a.shape[0]
    t, b = band(a[i] for i in range(h // 2)), band(a[h - 1 - i] for i in range(h // 2))
    l, r = band(a[:, i] for i in range(h // 2)), band(a[:, h - 1 - i] for i in range(h // 2))
    return a[t:h - b, l:h - r]


def base_picture(base: dict | None) -> np.ndarray | None:
    if not base:
        return None
    path = os.path.join(ROOT, base["file"].replace("\\", os.sep) + ".blp")
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        rgb = dxt_rgb(blp_dxt(f.read()))
    return rgb[:(base["r1"] - base["r0"]) * base["px"], :(base["c1"] - base["c0"]) * base["px"]]


def mask_of(cells: np.ndarray) -> dict | None:
    """A chunk mask's compact form: its box (chunk units) and row-major run lengths, off first."""
    ys, xs = np.nonzero(cells)
    if not len(ys):
        return None
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    flat = cells[y0:y1, x0:x1].ravel()
    edges = np.flatnonzero(np.diff(np.concatenate([[0], flat.astype(np.int8), [0]])))
    rle, prev, on = [], 0, False
    for e in edges:
        rle.append(int(e - prev))
        prev, on = e, not on
    if len(rle) > MASK_RUNS:
        return None
    return {"x0": int(x0), "y0": int(y0), "w": int(x1 - x0), "h": int(y1 - y0), "rle": rle}


def box_of(cells: np.ndarray) -> list[float]:
    ys, xs = np.nonzero(cells)
    return [round(xs.min() / CH, 3), round(ys.min() / CH, 3), round((xs.max() + 1) / CH, 3), round((ys.max() + 1) / CH, 3)]


# --- the per-continent checks ---------------------------------------------------------

class Continent:
    def __init__(self, data: Data, inst: int, art: dict[int, np.ndarray]):
        self.inst, self.name, self.data, self.art = inst, CONTINENTS[inst], data, art
        tiles, sea = data.tiles[inst], data.sea[inst]
        drawn = np.zeros((64, 64), bool)
        for k in tiles:
            drawn[k % 64, k // 64] = k not in sea
        self.drawn = np.kron(drawn, np.ones((CH, CH), bool))
        walk = data.walk[inst]
        self.cls = np.where(walk >= 0, walk & 3, -1)
        self.water_data = (self.cls == 2) | ~self.drawn
        self.water = self.water_data.copy()
        self.has_art = np.zeros((GRID, GRID), bool)
        self.flat = np.zeros((GRID, GRID), bool)
        for k, a in art.items():
            if k in sea:
                continue
            g = a.mean(-1).reshape(CH, CPX, CH, CPX)
            cw = water_px(a).reshape(CH, CPX, CH, CPX).mean(axis=(1, 3)) > 0.5
            sl = tile_slice(k)
            self.has_art[sl] = True
            self.water[sl] |= cw
            self.flat[sl] = (g.std(axis=(1, 3)) < FLAT_STD) & (g.mean(axis=(1, 3)) > 20)
        self.flat &= ~self.water
        self.land = self.has_art & ~self.water
        self.base = base_picture(data.base[inst])

    def zone_at(self, col: float, row: float) -> str:
        z = int(self.data.zone_grid[self.inst][min(GRID - 1, int(row * CH)), min(GRID - 1, int(col * CH))])
        return self.data.names.get(z, "-") if z else "-"

    def skipped(self) -> list[dict]:
        out, b = [], self.data.base[self.inst]
        bgc = np.array(self.data.bg[self.inst], np.float32)
        for k in sorted(self.data.sea[self.inst]):
            c, r = k // 64, k % 64
            why = {}
            if self.base is not None and b["c0"] <= c < b["c1"] and b["r0"] <= r < b["r1"]:
                p = b["px"]
                cut = self.base[(r - b["r0"]) * p:(r - b["r0"] + 1) * p, (c - b["c0"]) * p:(c - b["c0"] + 1) * p].astype(np.float32)
                share = float((np.abs(cut - bgc).max(-1) > 12).mean())
                if share > SKIP_BASE:
                    why["base_land"] = round(share, 3)
            a = self.art.get(k)
            if a is not None:
                share = float((np.abs(unstriped(a, bgc) - bgc).max(-1) > SEA_EDGE).mean())
                if share > SKIP_ART:
                    why["art_land"] = round(share, 3)
            if why:
                sev = max(why.values())
                out.append(issue("skipped-tile", self.inst, f"{c},{r}", [c, r, c + 1, r + 1], [c + .5, r + .5], sev * 100,
                                 self.zone_at(c + .5, r + .5), why,
                                 f"tile {c},{r} isn't drawn (open sea) but its " + " and ".join(
                                     f"base picture is {v:.0%} land" if w == "base_land" else f"art is {v:.0%} off the backdrop" for w, v in why.items())))
        return out

    def sea_edges(self) -> list[dict]:
        """Skipped tiles beside a drawn tile whose water at the shared edge isn't the backdrop."""
        out, sea = [], self.data.sea[self.inst]
        bgc = np.array(self.data.bg[self.inst], np.float32)
        tiles = self.data.tiles[self.inst]
        for k in sorted(sea):
            c, r = k // 64, k % 64
            worst = []
            for dc, dr, side in ((1, 0, "E"), (-1, 0, "W"), (0, 1, "S"), (0, -1, "N")):
                n = (c + dc) * 64 + r + dr
                a = self.art.get(n)
                if a is None or n in sea or n not in tiles:
                    continue
                strip = {"E": a[:, 0], "W": a[:, -1], "S": a[0, :], "N": a[-1, :]}[side]
                w = water_px(strip)
                if w.mean() < 0.5:
                    continue
                jump = float(np.abs(strip[w] - bgc).mean())
                if jump > SEA_EDGE:
                    worst.append((jump, side))
            if worst:
                worst.sort(reverse=True)
                out.append(issue("sea-edge", self.inst, f"{c},{r}", [c, r, c + 1, r + 1], [c + .5, r + .5], worst[0][0],
                                 self.zone_at(c + .5, r + .5), {"jump": round(worst[0][0], 1), "sides": "".join(s for _, s in worst)},
                                 f"skipped sea tile {c},{r}: the backdrop meets drawn water {worst[0][0]:.0f} apart "
                                 f"({', '.join(s for _, s in worst)}): a tile-aligned block"))
        return out

    def flat_regions(self) -> list[dict]:
        seen = np.zeros_like(self.flat)
        ys, xs = np.nonzero(self.flat)
        out = []
        for y0, x0 in zip(ys, xs):
            if seen[y0, x0]:
                continue
            seen[y0, x0] = True
            q, comp = deque([(y0, x0)]), []
            while q:
                y, x = q.popleft()
                comp.append((y, x))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < GRID and 0 <= nx < GRID and self.flat[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            if len(comp) < FLAT_REGION:
                continue
            cells = np.zeros((GRID, GRID), bool)
            cy, cx = zip(*comp)
            cells[list(cy), list(cx)] = True
            col, row = (sum(cx) / len(comp) + .5) / CH, (sum(cy) / len(comp) + .5) / CH
            zone = self.zone_at(col, row)
            out.append(issue("flat-land", self.inst, f"{round(col)},{round(row)}", box_of(cells), [col, row], len(comp), zone,
                             {"chunks": len(comp), "tiles2": round(len(comp) / CH / CH, 2)},
                             f"{len(comp)} chunks of flat untextured land ({len(comp) / 256:.1f} tiles²) in {zone}", mask_of(cells)))
        return out

    def seams(self) -> list[dict]:
        out, sea = [], self.data.sea[self.inst]
        for k, a in self.art.items():
            if k in sea:
                continue
            c, r = k // 64, k % 64
            for dc, dr, side in ((1, 0, "E"), (0, 1, "S")):
                nk = (c + dc) * 64 + r + dr
                n = self.art.get(nk)
                if n is None or nk in sea:
                    continue
                bbox = [c + 1, r, c + 1, r + 1] if dc else [c, r + 1, c + 1, r + 1]
                jump, inner = edge_jump(a, n, bool(dc))
                if is_seam(jump, inner):
                    cen = [(bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2]
                    out.append(issue("seam", self.inst, f"{c},{r},{side}", bbox, cen, jump / inner, self.zone_at(*cen),
                                     {"ratio": round(jump / inner, 2), "jump": round(jump, 1)},
                                     f"seam on tile {c},{r}'s {'east' if dc else 'south'} edge: a jump {jump / inner:.1f}x the tiles' own variation"))
        return out

    def blocks(self) -> list[dict]:
        """Tiles whose colour jumps at their own edges, on BLOCK_SIDES or more drawn sides: as seams (a misplaced
        tile breaks the texture) or as one shift (a tinted tile is off its neighbours by the same colour on every
        side). A biome edge or a coast runs on through the neighbours, so neither."""
        out, sea = [], self.data.sea[self.inst]
        for k, a in self.art.items():
            if k in sea:
                continue
            c, r = k // 64, k % 64
            seams, shifts, grads = "", [], []
            for nk, side in ((k + 64, "E"), (k - 64, "W"), (k + 1, "S"), (k - 1, "N")):
                n = self.art.get(nk)
                if n is None or nk in sea:
                    continue
                if is_seam(*(edge_jump(a, n, side == "E") if side in "ES" else edge_jump(n, a, side == "W"))):
                    seams += side
                d, g = edge_shift(a, n, side)
                shifts.append(d)
                grads.append(g)
            if len(shifts) < BLOCK_SIDES:
                continue
            m = np.mean(shifts, 0)
            u = m / (np.linalg.norm(m) + TOL)
            shift = sorted(float(d @ u) for d in shifts)[-BLOCK_SIDES] / (float(np.mean(grads)) + 1)  # the BLOCK_SIDES-th side's
            if len(seams) >= BLOCK_SIDES or shift > BLOCK_SHIFT:
                why = (f"seams on {len(seams)} of {len(shifts)} sides ({seams})" if len(seams) >= BLOCK_SIDES else
                       f"its colour is off its neighbours' by ({', '.join(f'{v:+.0f}' for v in m)}) RGB, {shift:.1f}x the gradient beside its edges")
                out.append(issue("colour-block", self.inst, f"{c},{r}", [c, r, c + 1, r + 1], [c + .5, r + .5], max(shift, len(seams)),
                                 self.zone_at(c + .5, r + .5),
                                 {"seams": seams, "shift": round(shift, 2), "offset": [round(float(v), 1) for v in m], "sides": len(shifts)},
                                 f"tile {c},{r}: {why}: a tile-aligned block"))
        return out

    def patches(self) -> list[dict]:
        """Straight hard colour edges along the chunk grid (PATCH_*), grouped into patches."""
        N, P, sea = 64 * PX, CPX, self.data.sea[self.inst]
        pic, drawn = np.zeros((N, N, 3), np.uint8), np.zeros((N, N), bool)
        for k, a in self.art.items():
            if k not in sea:
                c, r = k // 64, k % 64
                pic[r * PX:(r + 1) * PX, c * PX:(c + 1) * PX] = a
                drawn[r * PX:(r + 1) * PX, c * PX:(c + 1) * PX] = True
        xs = np.arange(P, N - P, P)

        def hard(p, d):  # the lines x = xs (chunk units xs // P): [chunk row, line] hard, in runs of PATCH_RUN
            l2, l1, r0, r1 = (p[:, xs + o].astype(np.float32) for o in (-2, -1, 0, 1))
            off = np.abs((l2 + l1) - (r0 + r1)).sum(-1) / 2
            grad = (np.abs(l2 - l1).sum(-1) + np.abs(r0 - r1).sum(-1)) / 2
            off, grad = (v.reshape(GRID, P, len(xs)).mean(1) for v in (off, grad))
            ok = (d[:, xs - 2] & d[:, xs + 1]).reshape(GRID, P, len(xs)).all(1)
            m = (off > PATCH_JUMP) & (off > PATCH_RATIO * (grad + 1)) & ok
            keep = np.zeros_like(m)
            for i in np.flatnonzero(m.sum(0) >= PATCH_RUN):
                e = np.diff(np.r_[0, m[:, i].astype(np.int8), 0])
                for a, b in zip(np.flatnonzero(e == 1), np.flatnonzero(e == -1)):
                    keep[a:b, i] = b - a >= PATCH_RUN
            return keep
        segs = [(j, x, 0) for j, i in zip(*np.nonzero(hard(pic, drawn))) for x in [xs[i] // P]]
        segs += [(y, i, 1) for i, j in zip(*np.nonzero(hard(pic.transpose(1, 0, 2), drawn.T))) for y in [xs[j] // P]]
        at = {}  # chunk -> segments beside it
        for s in segs:
            j, x, h = s
            for cell in (((j, x), (j, x - 1)) if not h else ((j, x), (j - 1, x))):
                at.setdefault(cell, []).append(s)
        out, seen = [], set()
        for s0 in segs:
            if s0 in seen:
                continue
            seen.add(s0)
            q, group = deque([s0]), []
            while q:
                s = q.popleft()
                group.append(s)
                for dy in range(-PATCH_NEAR, PATCH_NEAR + 1):
                    for dx in range(-PATCH_NEAR, PATCH_NEAR + 1):
                        for t in at.get((s[0] + dy, s[1] + dx), ()):
                            if t not in seen:
                                seen.add(t)
                                q.append(t)
            if len(group) < PATCH_EDGE:
                continue
            cells = np.zeros((GRID, GRID), bool)
            for j, x, h in group:
                cells[j, x] = True
                cells[(j - 1, x) if h else (j, x - 1)] = True
            cy, cx = np.nonzero(cells)
            col, row = (cx.mean() + .5) / CH, (cy.mean() + .5) / CH
            zone = self.zone_at(col, row)
            out.append(issue("patch-edge", self.inst, f"{round(col)},{round(row)}", box_of(cells), [col, row], len(group), zone,
                             {"edge": len(group)}, f"{len(group)} chunks of straight colour edge on the chunk grid in {zone}: "
                             "a chunk-aligned patch of other art", mask_of(cells)))
        return out


def edge_jump(a: np.ndarray, n: np.ndarray, east: bool) -> tuple[float, float]:
    """The edge between tile art a and its east (or south) neighbour n: (mean jump across it, the tiles' own
    variation beside it + 1)."""
    if east:
        e1, e2, i1, i2 = a[:, -1], n[:, 0], a[:, -2], n[:, 1]
    else:
        e1, e2, i1, i2 = a[-1, :], n[0, :], a[-2, :], n[1, :]
    return float(np.abs(e1 - e2).mean()), float((np.abs(e1 - i1).mean() + np.abs(e2 - i2).mean()) / 2) + 1


def edge_shift(t: np.ndarray, n: np.ndarray, side: str) -> tuple[np.ndarray, float]:
    """Tile art t against its neighbour n on side (E, W, S, N): t's edge band (SHIFT_BAND px) minus n's facing band,
    as mean RGB; and the gradient beside the edge (|band - the next band in|, the two tiles' mean)."""
    if side in "NS":
        t, n = t.transpose(1, 0, 2), n.transpose(1, 0, 2)
    B = SHIFT_BAND
    if side in "ES":
        t0, t1, n0, n1 = t[:, -B:], t[:, -2 * B:-B], n[:, :B], n[:, B:2 * B]
    else:
        t0, t1, n0, n1 = t[:, :B], t[:, B:2 * B], n[:, -B:], n[:, -2 * B:-B]
    t0, t1, n0, n1 = (x.mean((0, 1)) for x in (t0, t1, n0, n1))
    return t0 - n0, float(np.linalg.norm(t0 - t1) + np.linalg.norm(n0 - n1)) / 2


def is_seam(jump: float, inner: float) -> bool:
    return jump / inner > SEAM_RATIO and jump > SEAM_JUMP


def issue(kind, inst, place, bbox, centroid, severity, zone, metrics, desc, mask=None) -> dict:
    out = {"id": f"{kind}:{inst}:{place}", "kind": kind, "inst": inst, "bbox": [round(float(v), 3) for v in bbox],
           "centroid": [round(float(v), 3) for v in centroid], "severity": round(float(severity), 3), "zone": zone,
           "desc": desc, "metrics": metrics}
    if mask:
        out["mask"] = mask
    return out


# --- overlays (debugging) --------------------------------------------------------------

def overlay(cont: Continent, out_dir: str, issues: list[dict]) -> list[str]:
    S = 32  # px a tile
    ys, xs = np.nonzero(cont.drawn[::CH, ::CH])
    c0, c1, r0, r1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    W, H = (c1 - c0) * S, (r1 - r0) * S
    pic = np.empty((H, W, 3), np.float32)
    pic[:] = cont.data.bg[cont.inst]
    b = cont.data.base[cont.inst]
    if cont.base is not None:
        arr = np.asarray(Image.fromarray(cont.base).resize(((b["c1"] - b["c0"]) * S, (b["r1"] - b["r0"]) * S), Image.BOX), np.float32)
        ox, oy = (b["c0"] - c0) * S, (b["r0"] - r0) * S
        y0, x0, y1, x1 = max(0, oy), max(0, ox), min(H, oy + arr.shape[0]), min(W, ox + arr.shape[1])
        pic[y0:y1, x0:x1] = arr[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    for k, a in cont.art.items():
        c, r = k // 64, k % 64
        if k not in cont.data.sea[cont.inst] and c0 <= c < c1 and r0 <= r < r1:
            pic[(r - r0) * S:(r - r0 + 1) * S, (c - c0) * S:(c - c0 + 1) * S] = np.asarray(Image.fromarray(a.astype(np.uint8)).resize((S, S), Image.BOX), np.float32)
    sub, cs = (slice(r0 * CH, r1 * CH), slice(c0 * CH, c1 * CH)), S // CH

    def tint(p, mask, colour, k):
        m = np.kron(mask[sub], np.ones((cs, cs), bool))
        p[m] = p[m] * (1 - k) + np.array(colour, np.float32) * k

    def xy(col, row):
        return (col - c0) * S, (row - r0) * S
    os.makedirs(out_dir, exist_ok=True)
    paths, colours = [], {"skipped-tile": (0, 255, 255), "sea-edge": (0, 160, 255), "seam": (255, 40, 40),
                          "colour-block": (255, 230, 0), "patch-edge": (255, 128, 0), "flat-land": (255, 255, 255)}
    p = pic.copy()
    tint(p, cont.flat, (255, 0, 255), 0.7)
    im = Image.fromarray(np.clip(p, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    rank = 0
    for i in issues:
        if i["kind"] not in colours:
            continue
        x0, y0 = xy(i["bbox"][0], i["bbox"][1])
        x1, y1 = xy(i["bbox"][2], i["bbox"][3])
        if i["kind"] == "flat-land":
            rank += 1
            if rank <= 10:
                cx, cy = xy(*i["centroid"])
                d.text((cx, cy), f"{rank} ", fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
            continue
        d.rectangle([x0, y0, max(x0, x1 - 1), max(y0, y1 - 1)], outline=colours[i["kind"]], width=2 if i["kind"] != "seam" else 3)
    path = os.path.join(out_dir, f"{cont.name}-tiles.png")
    im.save(path)
    paths.append(path)
    return paths


# --- the run ---------------------------------------------------------------------------

def url(demo: str, i: dict, zoom: int = 128) -> str:
    u = f"{demo}#map={i['inst']}&view=2d&x={i['centroid'][0]:.3f}&y={i['centroid'][1]:.3f}&z={zoom}"
    return u if i["inst"] == 0 or "localhost" not in demo else u + " (this repo's demo: EK only)"


def run(ns) -> tuple[dict, list[str]]:
    t0 = time.time()
    lines = []
    say = lines.append
    data_dir = os.path.join(ROOT, "Data")
    builds = header_builds(data_dir)
    inst_build = None if ns.no_install else installed_build(ns.wow or "/Applications/World of Warcraft", ns.product)
    target = inst_build or max(builds.values(), key=lambda v: tuple(int(x) for x in v.split(".")))
    scores, issues, art_src = {}, [], {}
    stale = {f: v for f, v in builds.items() if v != target}
    scores["data.stale_files"] = len(stale)
    for f, v in stale.items():
        issues.append(issue("data", -1, f, [0, 0, 0, 0], [0, 0], 1, "-", {"build": v, "target": target},
                            f"Data/{f} is from {v}, not {target}: regenerate (docs/development.md)"))
    say(f"== data: {len(builds)} game-derived files; target build {target} ({'installed' if inst_build else 'newest header'})")
    by = {}
    for f, v in builds.items():
        by.setdefault(v, []).append(f[:-4])
    for v, fs in sorted(by.items()):
        say(f"  {v}{' (target)' if v == target else ''}: {', '.join(fs)}")
    say(f"  data.stale_files = {len(stale)}")

    data = Data(data_dir)
    tiles_dir = ns.tiles or os.environ.get("MAGICMAP_TILES") or os.path.join(ROOT, "demo", "tiles")
    overlays = []
    for inst in (ns.inst or list(CONTINENTS)):
        if ns.no_art:
            art, src = {}, None
        elif ns.wow and not ns.tiles:
            art, src = art_from_install(ns.wow, ns.product, inst, data.tiles[inst], ns.out), f"install {ns.wow}"
        else:
            art, src = art_from_dir(tiles_dir, inst, data.tiles[inst]), tiles_dir
        art_src[str(inst)] = src if art else None
        cont = Continent(data, inst, art)
        P, mine = f"{inst}.", []
        say(f"\n== [{inst}] {cont.name}: {len(data.tiles[inst])} tiles, {len(data.sea[inst])} sea; art: "
            + (f"{len(art)} tiles from {src}" if art else "none (art checks skipped)"))

        def show(title, got, n=10, zoom=128):
            say(f"  {title}")
            for i in got[:n]:
                say(f"    {i['desc']}  {url(ns.demo, i, zoom)}")
            mine.extend(got)
        sk = cont.skipped()
        scores[P + "skipped.base_tiles"] = sum(1 for i in sk if "base_land" in i["metrics"])
        show(f"skipped: {len(sk)} sea tiles show land (base picture{' or art' if art else ''})", sk)
        if art:
            scores[P + "skipped.art_tiles"] = sum(1 for i in sk if "art_land" in i["metrics"])
            se = cont.sea_edges()
            se.sort(key=lambda i: -i["severity"])
            scores[P + "skipped.sea_edges"] = len(se)
            show(f"sea edges: {len(se)} skipped tiles beside drawn water over {SEA_EDGE:g} from the backdrop", se, 5)
            land, flat = int(cont.land.sum()), int(cont.flat.sum())
            regions = cont.flat_regions()
            regions.sort(key=lambda i: -i["severity"])
            scores[P + "flat.chunks"] = flat
            scores[P + "flat.share"] = round(flat / land, 4) if land else 0.0
            scores[P + "flat.regions"] = len(regions)
            show(f"flat: {flat} of {land} land chunks ({flat / max(1, land):.2%}); {len(regions)} regions of >= {FLAT_REGION}", regions)
            seams, blocks = cont.seams(), cont.blocks()
            seams.sort(key=lambda i: -i["severity"])
            blocks.sort(key=lambda i: -i["severity"])
            scores[P + "seams.edges"] = len(seams)
            scores[P + "seams.blocks"] = len(blocks)
            show(f"seams: {len(seams)} edges over {SEAM_RATIO:g}x the tiles' variation", seams, zoom=256)
            show(f"colour blocks: {len(blocks)} tiles", blocks)
            patches = cont.patches()
            patches.sort(key=lambda i: -i["severity"])
            scores[P + "patches.edge"] = sum(i["metrics"]["edge"] for i in patches)
            scores[P + "patches.regions"] = len(patches)
            show(f"patches: {len(patches)} chunk-aligned patches ({scores[P + 'patches.edge']} chunks of edge)", patches, zoom=256)
        issues += mine
        if ns.overlays:
            overlays += overlay(cont, ns.out, mine)
    counts = {}
    for i in issues:
        counts[i["kind"]] = counts.get(i["kind"], 0) + 1
    seen = {}
    for i in issues:  # ids unique: a second at the same rounded place gets #2
        n = seen.get(i["id"], 0) + 1
        seen[i["id"]] = n
        if n > 1:
            i["id"] += f"#{n}"
    say(f"\n{len(issues)} issues: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())) + f" ({time.time() - t0:.1f}s)"
        + (f"\noverlays: {', '.join(overlays)}" if overlays else ""))
    res = {"schema": 1, "build": data.version, "commit": git_commit(),
           "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"), "art": art_src,
           "summary": {"scores": scores, "counts": counts}, "issues": issues}
    return res, lines


def compare(scores: dict, base: dict) -> tuple[list[str], list[str], list[str]]:
    worse, better, skipped = [], [], []
    for k, b in sorted(base.items()):
        if k not in scores:
            skipped.append(k)
        elif scores[k] > b + TOL:
            worse.append(f"{k}: {scores[k]} (baseline {b})")
        elif scores[k] < b - TOL:
            better.append(f"{k}: {scores[k]} (baseline {b})")
    return worse, better, skipped


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tiles", help="the demo's tile export (<dir>/<inst>/64/<key>.webp); default demo/tiles or $MAGICMAP_TILES")
    ap.add_argument("--wow", help="read the art from this install instead (cached in --out)")
    ap.add_argument("--product", default="wowf")
    ap.add_argument("--no-art", action="store_true", help="the data checks alone: no tile art read (tools/check.sh: the art's"
                    " scores move with the local export and its codec, so they're not ratcheted)")
    ap.add_argument("--no-install", action="store_true", help="don't look for an installed build (CI, tools/check.sh)")
    ap.add_argument("--inst", type=int, action="append", help="a continent (0, 1); default both")
    ap.add_argument("--issues", metavar="FILE", help="write the issues file (JSON; - for stdout)")
    ap.add_argument("--json", metavar="FILE", help="write the summary alone (JSON; - for stdout)")
    ap.add_argument("--out", default=SCRATCH, help=f"debug output (--overlays, --wow's cache) here; default {SCRATCH}")
    ap.add_argument("--overlays", action="store_true", help="also write overlay PNGs per continent into --out")
    ap.add_argument("--baseline", metavar="FILE", help="exit 1 if any score is worse than FILE's")
    ap.add_argument("--write-baseline", metavar="FILE", help="write the scores to FILE")
    ap.add_argument("--demo", default="http://localhost:8000/", help="the web demo's URL for links")
    ap.add_argument("-q", "--quiet", action="store_true", help="no report")
    ns = ap.parse_args()
    res, lines = run(ns)
    if not ns.quiet and "-" not in (ns.issues, ns.json):
        print("\n".join(lines))
    for path, obj in ((ns.issues, res), (ns.json, {k: res[k] for k in ("schema", "build", "commit", "generated", "art", "summary")})):
        if path:
            text = json.dumps(obj, separators=(",", ":")) if path != "-" else json.dumps(obj, indent=1)
            if path == "-":
                print(text)
            else:
                with open(path, "w") as f:
                    f.write(text + "\n")
    if ns.write_baseline:
        with open(ns.write_baseline, "w") as f:
            json.dump({"build": res["build"], "scores": res["summary"]["scores"]}, f, indent=1, sort_keys=True)
            f.write("\n")
    if ns.baseline:
        with open(ns.baseline) as f:
            base = json.load(f)["scores"]
        worse, better, skipped = compare(res["summary"]["scores"], base)
        if skipped:
            print(f"maplint: {len(skipped)} scores skipped (no tile art here: demo/export_tiles.py)", file=sys.stderr)
        if better:
            print(f"maplint: better than the baseline (ratchet: --write-baseline {ns.baseline}):\n  " + "\n  ".join(better), file=sys.stderr)
        if worse:
            print("maplint: worse than the baseline:\n  " + "\n  ".join(worse), file=sys.stderr)
            return 1
        print(f"maplint: {len(base) - len(skipped)} scores at or under the baseline", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

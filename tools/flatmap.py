#!/usr/bin/env python3
"""A continent's chunks as the map layers see them (tools/gen_ground.py, gen_relief.py, seamcheck.py): whole-continent arrays from the
tiles and the terrain files, kept in the cache. Flat ground: art with next to no detail. What goes with it: how much the
terrain under it rises and falls (no test of unfinished ground: the map review's accepted places are the levellest; seamcheck.py), and what the game paints there.

  from flatmap import read; m = read(src, inst, tiles, sea, cache)
  m.detail, m.tone (1024 x 1024[, 3]): the art; m.painted (1024 x 1024): the texture painted most (a FileDataID);
  m.uniform: one texture over the whole chunk; m.heights (8192 x 8192, nan: none); m.rise: a chunk's height range;
  m.land, m.wet, m.built, m.dark, m.flat (1024 x 1024 bool)
"""
from __future__ import annotations

import os
from types import SimpleNamespace

import numpy as np

from gen_fill import FLAT, FLAT_WATER, Ground

PX = 8
N = 1024


def read(src, inst: int, tiles: dict, sea: dict, cache: str) -> SimpleNamespace:
    path = os.path.join(cache, f"flatmap{inst}.npz")
    if os.path.exists(path):
        z = np.load(path)
        return SimpleNamespace(**{k: z[k] for k in z.files})
    g = Ground(src, inst, tiles, sea, cache)
    detail, tone = np.zeros((N, N), np.float32), np.zeros((N, N, 3), np.float32)
    painted, uniform = np.zeros((N, N), np.int64), np.zeros((N, N), bool)
    heights = np.full((N * PX, N * PX), np.nan, np.float32)
    land, wet, built = np.zeros((N, N), bool), np.zeros((N, N), bool), np.zeros((N, N), bool)
    for k in tiles:
        c, r = k // 64, k % 64
        a = g.art(k, 16 * PX)
        if a is None:
            continue
        cell = a.reshape(16, PX, 16, PX, 3)
        y, x = r * 16, c * 16
        land[y:y + 16, x:x + 16] = True
        detail[y:y + 16, x:x + 16] = cell.std((1, 3)).mean(-1)
        tone[y:y + 16, x:x + 16] = cell.mean((1, 3))
        h, t = g.terrain(k)
        ground, surface = g.heights_and_water(k)
        heights[y * PX:(y + 16) * PX, x * PX:(x + 16) * PX] = h
        cells = t.reshape(16, PX, 16, PX)
        painted[y:y + 16, x:x + 16] = cells[:, 0, :, 0]
        uniform[y:y + 16, x:x + 16] = cells.max((1, 3)) == cells.min((1, 3))
        wet[y:y + 16, x:x + 16] = (ground < surface).reshape(16, PX, 16, PX).any((1, 3))
        built[y:y + 16, x:x + 16] = g.buildings(k)
    hc = heights.reshape(N, PX, N, PX)
    with np.errstate(all="ignore"):
        rise = np.nan_to_num(np.nanmax(hc, (1, 3)) - np.nanmin(hc, (1, 3)))
    dark = tone.max(-1) < FLAT_WATER
    flat = land & (detail < FLAT) & ~dark & ~wet & ~built
    out = dict(detail=detail, tone=tone, painted=painted, uniform=uniform, heights=heights, rise=rise, land=land, wet=wet, built=built, dark=dark, flat=flat)
    os.makedirs(cache, exist_ok=True)
    np.savez(path, **out)
    return SimpleNamespace(**out)

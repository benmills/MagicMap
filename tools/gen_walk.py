#!/usr/bin/env python3
"""Generate Data/Walk.lua and Data/WalkParts.lua: where you can walk, for path mode's routes (walk v2:
promo/pathing/walk-v2-spec.md; the formats: docs/atlas-data.md and tools/mmtools/walkdata.py).

L0, the fine graph (here only, never shipped): the terrain as the client draws it, each ~4-yard quad 4 triangles
round its centre vertex, each triangle a kind (hole, deep water, harmful liquid, else by its slope: flat <= 50
degrees, steep <= 61.6, wall). You walk between standable triangles (flat, water, harmful), step up 2 yards over
one triangle you can't stand on, and slide or drop down steep and wall triangles (a fall of at most 14.57 yards).

L1, what ships: per 33-yard chunk its parts (standable triangles that walk to each other both ways inside the
chunk, at most 7), and the edges between parts of the chunk and of its 4 neighbours (and drop links further).

  python3 tools/gen_walk.py local "/Applications/World of Warcraft" wowf -o Data/Walk.lua \\
      [--parts Data/WalkParts.lua] [--cache DIR] [--report FILE]

--cache DIR keeps each map's terrain as DIR/fine_<inst>.npz (the game's heights, never committed) and reads it
back the next time, so a re-bake doesn't read the game files again.

Buildings and bridges (WMOs) aren't terrain: cities and bridges over chasms read as whatever is under them
(tools/walk_links.json joins what the terrain can't).

Output is deterministic: the same game data always gives the same files.
"""
from __future__ import annotations

import argparse
import collections
import json
import math
import os
import struct
import sys
import time

import numpy as np

from mmtools.db2 import read_wdc5
from mmtools.formats import adt_chunks, adt_liquids, iter_chunks, wdt_maid
from mmtools.log import log
from mmtools.maps import MAP_DB2, read_maps
from mmtools.sources import add_source_args, source_from_args
from mmtools.walkdata import decode_letters

LIQUIDTYPE_DB2 = 1371380  # dbfilesclient/liquidtype.db2
MAGMA_ID = 3               # LiquidType "Magma": its sound-bank-like column names the harmful kinds

QUAD = 100 / 3 / 8         # yards across a quad
SWIM_DEPTH = 1.5           # yards of liquid over the ground before you swim
FLAT_MAX = 50.0            # degrees: a face you can walk up
STEEP_MAX = 61.6           # degrees: a face you slide down (steeper: a wall, you fall)
STEP_UP = 2.0              # yards: the client's step
SAFE_FALL = 14.57          # yards: a fall that doesn't hurt

# Quad flags (the cache's `kind`)
Q_DEEP, Q_HARM, Q_HOLE, Q_NONE = 1, 2, 4, 8
# Triangle kinds
HOLE, FLAT, WATER, HARMFUL, STEEP, WALL = 0, 1, 2, 3, 4, 5
# Triangles of a quad: N (a, b, m), E (b, d, m), S (d, c, m), W (c, a, m); a NW, b NE, c SW, d SE, m centre


def harmful_liquids(db2: bytes) -> set[int]:
    """LiquidType IDs of magma and slime: the column that's 0 water, 1 ocean,
    2 magma, 3 slime (found by content: Magma's row says 2)."""
    rows = read_wdc5(db2, string_fields={0})
    magma = next(r for r in rows if r[0] == MAGMA_ID)
    col = next(c for c in range(2, len(magma)) if magma[c] == 2 and not isinstance(magma[c], tuple))
    return {r[0] for r in rows if r[col] in (2, 3)}


# --- L0: the terrain, per quad ------------------------------------------------------------------------------

_OUTER = np.array([r * 17 + i for r in range(9) for i in range(9)]).reshape(9, 9)
_INNER = np.array([r * 17 + 9 + i for r in range(8) for i in range(8)]).reshape(8, 8)


def adt_holes(buf: bytes) -> dict[tuple[int, int], int]:
    """{(ix, iy): 64-bit mask (bit qy * 8 + qx)} of the MCNK hole masks (high-res, or the low-res 4x4 widened)."""
    out = {}
    for magic, off, size in iter_chunks(buf):
        if magic != b"MCNK" or size < 128:
            continue
        flags, ix, iy = struct.unpack_from("<III", buf, off)
        if flags & 0x10000:
            mask = struct.unpack_from("<Q", buf, off + 0x14)[0]
        else:
            low = struct.unpack_from("<H", buf, off + 0x3c)[0]
            mask = sum(1 << (y * 8 + x) for y in range(8) for x in range(8) if low & (1 << ((y // 2) * 4 + x // 2)))
        out[ix, iy] = mask
    return out


_BITS = np.arange(64, dtype=np.uint64)


def read_fine(src, adts: dict[int, int], harmful: set[int]) -> dict:
    """The map's terrain over its chunks' bounding box: outer [R*8+1, C*8+1] and inner [R*8, C*8] vertex heights
    (float32, NaN where there's no chunk), kind [R*8, C*8] quad flags (Q_*), origin (gc0, gr0)."""
    keys = sorted(adts)
    gcs = [k // 64 * 16 for k in keys]
    grs = [k % 64 * 16 for k in keys]
    gc0, gr0 = min(gcs), min(grs)
    C, R = max(gcs) + 16 - gc0, max(grs) + 16 - gr0
    outer = np.full((R * 8 + 1, C * 8 + 1), np.nan, np.float32)
    inner = np.full((R * 8, C * 8), np.nan, np.float32)
    kind = np.full((R * 8, C * 8), Q_NONE, np.uint8)
    src.prefetch(adts[k] for k in keys)
    for key in keys:
        buf = src.read(adts[key])
        if buf is None:
            continue
        col, row = key // 64, key % 64
        liquids: dict[tuple[int, int], list] = {}
        for liq in adt_liquids(buf):
            liquids.setdefault((liq.ix, liq.iy), []).append(liq)
        holes = adt_holes(buf)
        for ch in adt_chunks(buf):
            if not (0 <= ch.ix < 16 and 0 <= ch.iy < 16):
                continue
            x0 = (col * 16 + ch.ix - gc0) * 8
            y0 = (row * 16 + ch.iy - gr0) * 8
            if ch.heights is None:
                h = np.zeros(145, np.float64)
            else:
                h = np.array(ch.heights, np.float64)
            h += ch.z
            o, m = h[_OUTER], h[_INNER]
            outer[y0:y0 + 9, x0:x0 + 9] = o
            inner[y0:y0 + 8, x0:x0 + 8] = m
            k = np.zeros((8, 8), np.uint8)
            mask = holes.get((ch.ix, ch.iy), 0)
            if mask:
                k |= (((np.uint64(mask) >> _BITS) & np.uint64(1)).astype(np.uint8) * Q_HOLE).reshape(8, 8)
            liqs = liquids.get((ch.ix, ch.iy))
            if liqs:
                ground = (o[:-1, :-1] + o[:-1, 1:] + o[1:, :-1] + o[1:, 1:] + m) / 5
                deep = np.zeros((8, 8), bool)
                harm = np.zeros((8, 8), bool)
                for liq in liqs:
                    cov = np.zeros((8, 8), bool)
                    if liq.exists is None:
                        cov[liq.y0:liq.y0 + liq.h, liq.x0:liq.x0 + liq.w] = True
                    else:
                        bits = np.unpackbits(np.frombuffer(liq.exists, np.uint8), bitorder="little")[:liq.w * liq.h]
                        if len(bits) < liq.w * liq.h:
                            bits = np.pad(bits, (0, liq.w * liq.h - len(bits)))
                        sub = cov[liq.y0:liq.y0 + liq.h, liq.x0:liq.x0 + liq.w]
                        sub[...] = bits.reshape(liq.h, liq.w)[:sub.shape[0], :sub.shape[1]].astype(bool)
                    over = cov & (liq.surface > ground)
                    if liq.liquid_type in harmful:
                        harm |= over
                    else:
                        deep |= over & (liq.surface - ground > SWIM_DEPTH)
                k |= np.where(harm, Q_HARM, np.where(deep, Q_DEEP, 0)).astype(np.uint8)
            kind[y0:y0 + 8, x0:x0 + 8] = k
    return {"outer": outer, "inner": inner, "kind": kind, "origin": np.array([gc0, gr0], np.int32)}


def load_fine(src, inst: int, adts: dict[int, int], harmful: set[int], cache: str | None) -> dict:
    path = os.path.join(cache, f"fine_{inst}.npz") if cache else None
    if path and os.path.exists(path):
        with np.load(path) as z:
            return {k: z[k] for k in z.files}
    fine = read_fine(src, adts, harmful)
    if path:
        os.makedirs(cache, exist_ok=True)
        np.savez(path + ".tmp.npz", **fine)
        os.replace(path + ".tmp.npz", path)
    return fine


# --- L0: triangles, per chunk ---------------------------------------------------------------------------------
# A chunk's 256 triangles, local index l = (qy * 8 + qx) * 4 + k, k = 0 N, 1 E, 2 S, 3 W. Triangle k's corners p, q
# (clockwise) and the centre m; its edges: 0 the quad's side p-q, 1 q-m (shared with k + 1), 2 p-m (with k - 1).

_PQ = ((0, 0, 0, 1), (0, 1, 1, 1), (1, 1, 1, 0), (1, 0, 0, 0))  # per k: p (dy, dx), q (dy, dx)
_BACK = (0, 2, 1)  # the edge of the neighbour across edge j that leads back
_ACROSS = ((0, -1, 2), (1, 0, 3), (0, 1, 0), (-1, 0, 1))  # per k: the quad across edge 0 (dx, dy) and its k
_SIDE = (0, 1, 2, 3)  # per k: the chunk side edge 0 crosses when the quad is on it: N, E, S, W
_DIRS = ((0, -1), (1, 0), (0, 1), (-1, 0))  # chunk sides N, E, S, W as (dx, dy)


def _local_tables():
    nbl = np.full((256, 3), -1, np.int32)  # the neighbour across edge j inside the chunk, else -1
    cross = np.full((256, 3), -1, np.int32)  # across edge 0 out of the chunk: the neighbour's local index
    for l in range(256):
        q, k = divmod(l, 4)
        qy, qx = divmod(q, 8)
        nbl[l, 1] = q * 4 + (k + 1) % 4
        nbl[l, 2] = q * 4 + (k + 3) % 4
        dx, dy, k2 = _ACROSS[k]
        x, y = qx + dx, qy + dy
        if 0 <= x < 8 and 0 <= y < 8:
            nbl[l, 0] = (y * 8 + x) * 4 + k2
        else:
            cross[l, 0] = ((y % 8) * 8 + x % 8) * 4 + k2
    return nbl, cross


NBL, CROSS = _local_tables()
_L = np.arange(256)
_QY, _QX, _K = _L // 32, (_L // 4) % 8, _L % 4
_PDY = np.array([_PQ[k][0] for k in range(4)])[_K]
_PDX = np.array([_PQ[k][1] for k in range(4)])[_K]
_QDY = np.array([_PQ[k][2] for k in range(4)])[_K]
_QDX = np.array([_PQ[k][3] for k in range(4)])[_K]
_TAN_FLAT, _TAN_STEEP = math.tan(math.radians(FLAT_MAX)), math.tan(math.radians(STEEP_MAX))


class Fine:
    """One map's L0: its chunks (those with terrain), chunk-major. ch = index in `gc`/`gr`; nb[ch, s] the
    neighbour chunk on side s (N, E, S, W) or -1; O [n, 9, 9], I [n, 8, 8] heights, QK [n, 8, 8] quad flags;
    kind [n, 256] the triangles' kinds; P, Q, M [n, 256] their corner and centre heights."""

    def __init__(self, fine: dict):
        outer, inner, qk = fine["outer"], fine["inner"], fine["kind"]
        gc0, gr0 = (int(v) for v in fine["origin"])
        R, C = qk.shape[0] // 8, qk.shape[1] // 8
        have = (qk != Q_NONE).reshape(R, 8, C, 8).any(axis=(1, 3))
        ys, xs = np.nonzero(have)  # row-major: gr, then gc
        n = len(ys)
        self.n = n
        self.gc, self.gr = (xs + gc0).astype(np.int32), (ys + gr0).astype(np.int32)
        self.gc0, self.gr0, self.R, self.C = gc0, gr0, R, C
        idx = np.full((R + 2, C + 2), -1, np.int32)
        idx[ys + 1, xs + 1] = np.arange(n, dtype=np.int32)
        self.box = idx
        self.nb = np.stack([idx[ys + 1 + dy, xs + 1 + dx] for dx, dy in _DIRS], axis=1)
        oy = ys[:, None, None] * 8 + np.arange(9)[None, :, None]
        ox = xs[:, None, None] * 8 + np.arange(9)[None, None, :]
        O = outer[oy, ox]
        I = inner[oy[:, :8, :8], ox[:, :8, :8]]
        QK = qk[oy[:, :8, :8], ox[:, :8, :8]]
        none = np.isnan(O[:, :-1, :-1]) | np.isnan(O[:, 1:, 1:]) | np.isnan(O[:, :-1, 1:]) | np.isnan(O[:, 1:, :-1]) | np.isnan(I)
        QK = np.where(none, QK | Q_NONE, QK)
        O = np.nan_to_num(O)
        I = np.nan_to_num(I)
        self.O, self.I, self.QK = O, I, QK
        self.P = O[:, _QY + _PDY, _QX + _PDX]
        self.Q = O[:, _QY + _QDY, _QX + _QDX]
        self.M = I[:, _QY, _QX]
        self.kind = self._kinds()

    def _kinds(self):
        p, q, m = self.P, self.Q, self.M
        k = _K
        # The face's gradient (dz/dx, dz/dy) per k (x east, y south; see _PQ)
        gx = np.where(k == 0, q - p, np.where(k == 1, p + q - 2 * m, np.where(k == 2, p - q, 2 * m - p - q))) / QUAD
        gy = np.where(k == 0, 2 * m - p - q, np.where(k == 1, q - p, np.where(k == 2, p + q - 2 * m, p - q))) / QUAD
        t = np.hypot(gx, gy)
        kind = np.where(t <= _TAN_FLAT, FLAT, np.where(t <= _TAN_STEEP, STEEP, WALL)).astype(np.uint8)
        qk = self.QK.reshape(self.n, 64)[:, _L // 4]
        kind = np.where(qk & Q_DEEP, WATER, kind)
        kind = np.where(qk & Q_HARM, HARMFUL, kind)
        kind = np.where(qk & (Q_HOLE | Q_NONE), HOLE, kind).astype(np.uint8)
        return kind

    def zmid(self, j: int):
        """[n, 256]: the mean height of each triangle's edge j."""
        if j == 0:
            return (self.P + self.Q) / 2
        if j == 1:
            return (self.Q + self.M) / 2
        return (self.P + self.M) / 2

    def zc(self):
        return (self.P + self.Q + self.M) / 3


def standable(kind):
    return (kind == FLAT) | (kind == WATER) | (kind == HARMFUL)


def _two_hop_tables():
    """Per triangle l, 6 slots: via its neighbour B across edge j (inside the chunk), B's other two edges j2:
    (B, edge of B back to l, j2, the triangle across j2), -1 where any is outside the chunk."""
    b = np.full((256, 6), -1, np.int32)
    eb = np.zeros((256, 6), np.int32)
    e2 = np.zeros((256, 6), np.int32)
    t2 = np.full((256, 6), -1, np.int32)
    for l in range(256):
        s = 0
        for j in range(3):
            B = NBL[l, j]
            back = _BACK[j]
            for j2 in range(3):
                if j2 == back:
                    continue
                if B >= 0 and NBL[B, j2] >= 0:
                    b[l, s], eb[l, s], e2[l, s], t2[l, s] = B, back, j2, NBL[B, j2]
                s += 1
    return b, eb, e2, t2


TH_B, TH_EB, TH_E2, TH_T = _two_hop_tables()


def label_pieces(f: Fine, batch: int = 8192):
    """The chunks' pieces: standable triangles joined inside the chunk by rule 1 (across an edge) and rule 2 both
    ways (over one non-standable triangle, |step| <= STEP_UP). Returns lab [n, 256] int16 (-1: not standable),
    pieces numbered per chunk 0.. in order of their first triangle, and their count per chunk."""
    lab = np.full((f.n, 256), -1, np.int16)
    count = np.zeros(f.n, np.int32)
    for s0 in range(0, f.n, batch):
        sl = slice(s0, min(f.n, s0 + batch))
        kind = f.kind[sl]
        st = standable(kind)
        ns = (kind == STEEP) | (kind == WALL)
        zm = np.stack([(f.P[sl] + f.Q[sl]) / 2, (f.Q[sl] + f.M[sl]) / 2, (f.P[sl] + f.M[sl]) / 2], axis=2)
        PT = np.zeros((256, 9), np.int32)
        V = np.zeros(kind.shape + (9,), bool)
        for j in range(3):
            ok = NBL[:, j] >= 0
            PT[:, j] = np.maximum(NBL[:, j], 0)
            V[:, :, j] = ok & st & st[:, PT[:, j]]
        for s in range(6):
            B, eb, e2, T = TH_B[:, s], TH_EB[:, s], TH_E2[:, s], TH_T[:, s]
            Bc, Tc = np.maximum(B, 0), np.maximum(T, 0)
            PT[:, 3 + s] = Tc
            dz = np.abs(zm[:, Bc, eb] - zm[:, Bc, e2])
            V[:, :, 3 + s] = (B >= 0) & st & st[:, Tc] & ns[:, Bc] & (dz <= STEP_UP)
        BIG = np.int16(1 << 14)
        cur = np.where(st, _L[None, :], BIG).astype(np.int16)
        rows = np.nonzero(V.any(axis=(1, 2)))[0]
        while len(rows):
            c = cur[rows]
            cand = np.where(V[rows], c[:, PT], BIG).min(axis=2)
            new = np.minimum(c, cand)
            r = np.arange(len(rows))[:, None]
            new = np.where(new < BIG, new[r, np.minimum(new, 255)], new)  # pointer jump
            new = np.where(new < BIG, new[r, np.minimum(new, 255)], new)
            changed = (new != c).any(axis=1)
            cur[rows] = new
            rows = rows[changed]
        # renumber: roots (cur == l) in order
        root = st & (cur == _L[None, :])
        rank = np.cumsum(root, axis=1) - 1
        out = np.where(st, rank[np.arange(cur.shape[0])[:, None], np.where(st, cur, 0)], -1)
        lab[sl] = out
        count[sl] = root.sum(axis=1)
    return lab, count


def across(f: Fine, ch, l, j: int):
    """The triangle across edge j of triangles (ch, l): (ch2, l2), ch2 -1 where there's none."""
    if j == 1:
        return ch, (l & ~3) | ((l + 1) & 3)
    if j == 2:
        return ch, (l & ~3) | ((l + 3) & 3)
    l2 = NBL[l, 0]
    inside = l2 >= 0
    ch2 = np.where(inside, ch, f.nb[ch, l & 3])
    return ch2, np.where(inside, l2, CROSS[l, 0])


def edge_z(f: Fine, ch, l, j: int):
    if j == 0:
        return (f.P[ch, l] + f.Q[ch, l]) / 2
    if j == 1:
        return (f.Q[ch, l] + f.M[ch, l]) / 2
    return (f.P[ch, l] + f.M[ch, l]) / 2


def _uniq(chunks):
    chunks = [c for c in chunks if len(c)]
    return np.unique(np.concatenate(chunks)) if chunks else np.zeros(0, np.int64)


def piece_moves(f: Fine, pid):
    """The pieces' fine moves (rules 1 and 2) as unique int64 keys u << 32 | v, u != v; pid [n, 256] the global
    piece of each standable triangle (-1 else)."""
    out = []
    st = pid >= 0
    # rule 1 across chunk sides (inside a chunk, rule-1 neighbours are one piece)
    for k in (1, 2):  # E and S sides: each pair once, both ways
        ls = np.nonzero((_K == k) & (NBL[:, 0] < 0))[0]
        ch, l = np.nonzero(st[:, ls])
        l = ls[l]
        ch2, l2 = across(f, ch, l, 0)
        ok = ch2 >= 0
        ch, l, ch2, l2 = ch[ok], l[ok], ch2[ok], l2[ok]
        ok = st[ch2, l2]
        u, v = pid[ch[ok], l[ok]].astype(np.int64), pid[ch2[ok], l2[ok]].astype(np.int64)
        out += [u << 32 | v, v << 32 | u]
    # rule 2: over one non-standable B
    ns = (f.kind == STEEP) | (f.kind == WALL)
    bch, bl = np.nonzero(ns)
    step = 1 << 22
    for s0 in range(0, len(bch), step):
        ch, l = bch[s0:s0 + step], bl[s0:s0 + step]
        nbs = [across(f, ch, l, j) for j in range(3)]
        zs = [edge_z(f, ch, l, j) for j in range(3)]
        ps = [np.where(c >= 0, pid[np.maximum(c, 0), x], -1) for c, x in nbs]
        for j1 in range(3):
            for j2 in range(3):
                if j1 == j2:
                    continue
                dz = zs[j2] - zs[j1]
                ok = (ps[j1] >= 0) & (ps[j2] >= 0) & (ps[j1] != ps[j2]) & (dz >= -SAFE_FALL) & (dz <= STEP_UP)
                out.append(np.unique(ps[j1][ok].astype(np.int64) << 32 | ps[j2][ok]))
    return _uniq(out)


def descents(f: Fine, pid, pch, K: int = 8, reach: int = 3):
    """Rule 3: where you slide or drop from each piece, through non-standable triangles, to the first standable
    one. Returns unique int64 keys u << 32 | v (u != v), and stats. pch: each piece's chunk. Each non-standable
    triangle keeps up to K landing pieces, the nearest first (chunks, Chebyshev), within `reach` chunks of it."""
    t0 = time.time()
    kind = f.kind
    ns = (kind == STEEP) | (kind == WALL)
    nch, nl = np.nonzero(ns)
    N = len(nch)
    if N == 0:
        return np.zeros(0, np.int64), {"ns": 0}
    nsid = np.full(kind.shape, -1, np.int32)
    nsid[nch, nl] = np.arange(N, dtype=np.int32)
    zc = ((f.P[nch, nl] + f.Q[nch, nl] + f.M[nch, nl]) / 3).astype(np.float32)
    wall = kind[nch, nl] == WALL
    child = np.full((N, 3), -1, np.int32)
    land = np.full((N, 3), -1, np.int32)
    ez = np.zeros((N, 3), np.float32)
    for j in range(3):
        c2, l2 = across(f, nch, nl, j)
        e = edge_z(f, nch, nl, j)
        ez[:, j] = e
        has = c2 >= 0
        c2c = np.maximum(c2, 0)
        down = has & (e < zc)
        land[:, j] = np.where(down, pid[c2c, l2], -1)
        x = np.where(down, nsid[c2c, l2], -1)
        xc = np.maximum(x, 0)
        child[:, j] = np.where((x >= 0) & (zc[xc] < e), x, -1)
    # the lowest exit of each wall run (an exit: downhill to a non-wall triangle)
    INF = np.float32(1e9)
    low = np.full(N, INF, np.float32)
    for j in range(3):
        x = child[:, j]
        exit_ = (land[:, j] >= 0) | ((x >= 0) & ~wall[np.maximum(x, 0)])
        low = np.where(wall & exit_, np.minimum(low, ez[:, j]), low)
    wchild = np.where((child >= 0) & wall[:, None] & wall[np.maximum(child, 0)], child, -1)
    rows = np.nonzero(wall & (wchild >= 0).any(axis=1))[0]
    while len(rows):
        c = wchild[rows]
        m = np.where(c >= 0, low[np.maximum(c, 0)], INF).min(axis=1)
        new = np.minimum(low[rows], m)
        changed = new < low[rows]
        low[rows] = new
        rows = rows[changed]
    # a wall run entered from a non-wall: only if the fall to its lowest exit is safe
    for j in range(3):
        x = child[:, j]
        xc = np.maximum(x, 0)
        bad = (x >= 0) & ~wall & wall[xc] & (ez[:, j] - low[xc] > SAFE_FALL)
        child[bad, j] = -1
    t1 = time.time()
    # landing sets, children first (Kahn's order: the descent graph goes strictly down, so no cycles)
    gch, grh = f.gc[nch], f.gr[nch]
    pgc, pgr = f.gc[pch], f.gr[pch]
    S = np.full((N, K), -1, np.int32)
    pending = (child >= 0).sum(axis=1).astype(np.int32)
    cflat = child.ravel()
    has = cflat >= 0
    par_child = cflat[has]
    par_parent = np.repeat(np.arange(N, dtype=np.int32), 3)[has]
    order = np.argsort(par_child, kind="stable")
    par_child, par_parent = par_child[order], par_parent[order]
    start = np.searchsorted(par_child, np.arange(N + 1))
    ready = np.nonzero(pending == 0)[0]
    rounds = full = 0
    BIGK = np.int64(1) << 62
    while len(ready):
        rounds += 1
        b = ready
        cand = [land[b]]
        cb = child[b]
        for j in range(3):
            x = cb[:, j]
            cand.append(np.where((x >= 0)[:, None], S[np.maximum(x, 0)], -1))
        cand = np.concatenate(cand, axis=1).astype(np.int64)
        cc = np.maximum(cand, 0)
        d = np.maximum(np.abs(pgc[cc] - gch[b][:, None]), np.abs(pgr[cc] - grh[b][:, None]))
        key = np.where((cand >= 0) & (d <= reach), d.astype(np.int64) << 32 | cand, BIGK)
        key.sort(axis=1)
        dup = np.zeros_like(key, bool)
        dup[:, 1:] = key[:, 1:] == key[:, :-1]
        key = np.where(dup, BIGK, key)
        key.sort(axis=1)
        full += int((key[:, K] < BIGK).sum())
        top = key[:, :K]
        S[b] = np.where(top < BIGK, top & 0xFFFFFFFF, -1).astype(np.int32)
        lo, hi = start[b], start[b + 1]
        cnt = hi - lo
        tot = int(cnt.sum())
        if tot == 0:
            break
        idx = np.repeat(lo, cnt) + (np.arange(tot) - np.repeat(np.cumsum(cnt) - cnt, cnt))
        ps = par_parent[idx]
        up, dec = np.unique(ps, return_counts=True)
        pending[up] -= dec.astype(np.int32)
        ready = up[pending[up] == 0]
    t2 = time.time()
    # entries: standable A across an edge into non-standable B, downhill (into a wall: a safe fall)
    out = []
    st = pid >= 0
    ach, al = np.nonzero(st)
    for j in range(3):
        c2, l2 = across(f, ach, al, j)
        c2c = np.maximum(c2, 0)
        x = np.where(c2 >= 0, nsid[c2c, l2], -1)
        xc = np.maximum(x, 0)
        e = edge_z(f, ach, al, j)
        ok = (x >= 0) & (zc[xc] < e) & ~(wall[xc] & (e - low[xc] > SAFE_FALL))
        u = pid[ach[ok], al[ok]].astype(np.int64)
        s = S[xc[ok]]
        for k in range(K):
            v = s[:, k]
            m = (v >= 0) & (v != u)
            out.append(np.unique(u[m] << 32 | v[m]))
    keys = _uniq(out)
    stats = {"ns": N, "rounds": rounds, "truncated": full, "t_low": round(t1 - t0, 1), "t_sets": round(t2 - t1, 1),
             "t_entries": round(time.time() - t2, 1)}
    return keys, stats


# --- L1: pieces -> parts --------------------------------------------------------------------------------------

TINY_TRIS = 1024     # a strongly connected component with fewer triangles goes, contracted
DEAD_TRIS = 32       # a piece with fewer triangles and at most one two-way neighbour goes (a cul-de-sac)
MAX_PARTS = 7        # parts a chunk; the smallest beyond go, contracted
FILL_CAP = 4         # contraction: from each in-neighbour, to at most this many out-neighbours per component


class Pieces:
    """The map's pieces (standable triangles that walk to each other both ways inside a chunk) and their
    attributes: chunk, triangles, deep and harmful triangles, centroid (quads from the chunk's NW corner)."""

    def __init__(self, f: Fine):
        lab, cnt = label_pieces(f)
        self.lab, self.cnt = lab, cnt
        offs = np.concatenate([[0], np.cumsum(cnt)]).astype(np.int64)
        self.offs = offs
        self.n = int(offs[-1])
        self.pid = np.where(lab >= 0, offs[:-1, None] + lab, -1).astype(np.int32)
        self.pch = np.repeat(np.arange(f.n, dtype=np.int32), cnt)
        p = self.pid.ravel()
        has = p >= 0
        pp = p[has]
        n = self.n
        kind = f.kind.ravel()[has]
        self.size = np.bincount(pp, minlength=n)
        self.water = np.bincount(pp, weights=kind == WATER, minlength=n)
        self.harm = np.bincount(pp, weights=kind == HARMFUL, minlength=n)
        ll = np.tile(_L, f.n)[has]
        # triangle centroids, quads: N (x + .5, y + 1/6), E (x + 5/6, y + .5), S (x + .5, y + 5/6), W (x + 1/6, y + .5)
        kx = np.array([0.5, 5 / 6, 0.5, 1 / 6])[ll % 4] + (ll // 4) % 8
        ky = np.array([1 / 6, 0.5, 5 / 6, 0.5])[ll % 4] + ll // 32
        self.cx = np.bincount(pp, weights=kx, minlength=n) / np.maximum(self.size, 1)
        self.cy = np.bincount(pp, weights=ky, minlength=n) / np.maximum(self.size, 1)

    def gx(self, f: Fine):
        """Positions in global chunks (for distances while pruning: the centroid)."""
        return f.gc[self.pch] + self.cx / 8, f.gr[self.pch] + self.cy / 8


def csr(n, u, v):
    order = np.lexsort((v, u))
    u, v = u[order], v[order]
    return np.searchsorted(u, np.arange(n + 1)), v


def prune(f: Fine, pc: Pieces, keys):
    """Which pieces stay, and the edges between them (int64 keys u << 32 | v): tiny strongly connected components
    and small cul-de-sacs go, then each chunk's smallest pieces past MAX_PARTS; each piece that goes is
    contracted (u -> x -> v becomes u -> v), so what reaches what doesn't change."""
    from mmtools.walkdata import scc
    n = pc.n
    u = (keys >> 32).astype(np.int64)
    v = (keys & 0xFFFFFFFF).astype(np.int64)
    start, adj = csr(n, u, v)
    comp, ncomp = scc(n, start.tolist(), adj.tolist())
    comp = np.array(comp, np.int64)
    ctris = np.bincount(comp, weights=pc.size, minlength=ncomp)
    stats = {"pieces": n, "edges": len(keys), "sccs": ncomp, "sccs_kept": int((ctris >= TINY_TRIS).sum())}
    tiny = ctris[comp] < TINY_TRIS
    # two-way neighbours
    rev = (v << 32) | u
    two = np.isin(keys, rev, assume_unique=True)
    deg2 = np.bincount(u[two], minlength=n)
    dead = ~tiny & (pc.size < DEAD_TRIS) & (deg2 <= 1)
    gone = tiny | dead
    # the cap: per chunk, the biggest MAX_PARTS of what stays
    order = np.lexsort((np.arange(n), -pc.size, pc.pch))
    keep_o = ~gone[order]
    ch_o = pc.pch[order]
    rank = np.zeros(n, np.int64)
    # rank among kept pieces in each chunk
    csum = np.cumsum(keep_o)
    first = np.searchsorted(ch_o, ch_o)  # index of the chunk's first piece in `order`
    before = csum[first] - keep_o[first]
    rank[order] = csum - before - 1
    over = ~gone & (rank >= MAX_PARTS)
    gone |= over
    stats.update(tiny=int(tiny.sum()), dead=int(dead.sum()), over=int(over.sum()))
    # contraction, the sinks' side first (Tarjan numbers a component after those it reaches)
    out = [set() for _ in range(n)]
    inn = [set() for _ in range(n)]
    for a, b in zip(u.tolist(), v.tolist()):
        out[a].add(b)
        inn[b].add(a)
    px, py = pc.gx(f)
    px, py = px.tolist(), py.tolist()
    compl = comp.tolist()
    elim = np.nonzero(gone)[0]
    elim = elim[np.lexsort((elim, comp[elim]))].tolist()
    added = 0
    for x in elim:
        ins, outs = inn[x], out[x]
        ins.discard(x)
        outs.discard(x)
        for a in ins:
            out[a].discard(x)
        for b in outs:
            inn[b].discard(x)
        if ins and outs:
            # from each in-neighbour, the nearest few out-neighbours of each component
            byc: dict[int, list] = {}
            for b in outs:
                byc.setdefault(compl[b], []).append(b)
            for a in ins:
                ax, ay = px[a], py[a]
                for c, bs in byc.items():
                    if c != compl[x] and len(bs) > FILL_CAP:
                        bs = sorted(bs, key=lambda b: ((px[b] - ax) ** 2 + (py[b] - ay) ** 2, b))[:FILL_CAP]
                    for b in bs:
                        if b != a and b not in out[a]:
                            out[a].add(b)
                            inn[b].add(a)
                            added += 1
        inn[x] = set()
        out[x] = set()
    stats["fill"] = added
    keep = ~gone
    eu, ev = [], []
    for a in np.nonzero(keep)[0].tolist():
        for b in out[a]:
            eu.append(a)
            ev.append(b)
    eu = np.array(eu, np.int64)
    ev = np.array(ev, np.int64)
    return keep, np.unique(eu << 32 | ev), stats


# --- L1: the parts graph, as shipped -----------------------------------------------------------------------

LAND, WATERC, HARMC = 1, 2, 3
HARMFUL_SHARE = 0.25
WATER_SHARE = 0.5


class L1:
    """The map's shipped graph. Chunks by global (gc, gr); parts[(gc, gr)] = list of
    (cls, centre, rep quad) for p = 0..; labels[(gc, gr)] = 64 labels (0 none, 1.. part + 1) for chunks with
    2+ parts; edges = {(a, b)} node ids (gc * 8192 + gr * 8 + p), the stored ones (no derived diagonals);
    tiles = the map's tile keys."""

    def __init__(self, tiles):
        self.tiles = sorted(tiles)
        self.parts: dict[tuple[int, int], list] = {}
        self.labels: dict[tuple[int, int], list] = {}
        self.edges: set[tuple[int, int]] = set()


def node_id(gc, gr, p):
    return gc * 8192 + gr * 8 + p


def build_l1(f: Fine, pc: Pieces, keep, keys, tiles) -> L1:
    out = L1(tiles)
    kept = np.nonzero(keep)[0]
    # parts per chunk: biggest first, then the first piece
    order = kept[np.lexsort((kept, -pc.size[kept], pc.pch[kept]))]
    pnum = np.full(pc.n, -1, np.int64)
    ch_o = pc.pch[order]
    first = np.searchsorted(ch_o, ch_o)
    pnum[order] = np.arange(len(order)) - first
    assert pnum[order].max() < MAX_PARTS
    gid = np.full(pc.n, -1, np.int64)
    gid[order] = node_id(f.gc[ch_o].astype(np.int64), f.gr[ch_o].astype(np.int64), pnum[order])
    # per part and quad: its triangles
    p = pc.pid.ravel()
    has = p >= 0
    has[has] = keep[p[has]]
    q = np.tile(_L // 4, f.n)[has]
    pp = p[has]
    kidx = np.full(pc.n, -1, np.int64)
    kidx[kept] = np.arange(len(kept))
    qc = np.bincount(kidx[pp] * 64 + q, minlength=len(kept) * 64).reshape(len(kept), 64)
    qcx = (np.arange(64) % 8) + 0.5
    qcy = (np.arange(64) // 8) + 0.5
    for x in order.tolist():
        c = int(pc.pch[x])
        key = (int(f.gc[c]), int(f.gr[c]))
        size = int(pc.size[x])
        if pc.harm[x] > size * HARMFUL_SHARE:
            cls = HARMC
        elif pc.water[x] > size * WATER_SHARE:
            cls = WATERC
        else:
            cls = LAND
        centre = size * 2 >= 256
        row = qc[kidx[x]]
        best = row.max()
        cand = np.nonzero(row == best)[0]
        d = (qcx[cand] - pc.cx[x]) ** 2 + (qcy[cand] - pc.cy[x]) ** 2
        rep = int(cand[np.lexsort((cand, d))[0]])
        out.parts.setdefault(key, []).append((cls, centre, rep))
    # label maps: per quad the part with most of its standable triangles (ties: the lower part)
    chunk_of = {}
    for x in order.tolist():
        c = int(pc.pch[x])
        chunk_of.setdefault(c, []).append(x)
    for c, xs in chunk_of.items():
        key = (int(f.gc[c]), int(f.gr[c]))
        if len(xs) < 2:
            continue
        m = np.stack([qc[kidx[x]] for x in xs])  # [n, 64], in part order
        lab = np.where(m.max(axis=0) > 0, m.argmax(axis=0) + 1, 0)
        out.labels[key] = lab.tolist()
    u = (keys >> 32).astype(np.int64)
    v = (keys & 0xFFFFFFFF).astype(np.int64)
    gu, gv = gid[u], gid[v]
    assert (gu >= 0).all() and (gv >= 0).all()
    out.edges = set(zip(gu.tolist(), gv.tolist()))
    return out


def unpack_id(i):
    return i // 8192, (i // 8) % 1024, i % 8


def l1_split(l1: L1):
    """The stored edges by kind: rel (same chunk or a 4-neighbour) and the rest; of the rest, those a derived
    diagonal already gives go (Walk: u -> w diagonal if some v in either side chunk has u -> v -> w)."""
    rel, far = set(), []
    out_rel: dict[int, list] = {}
    for a, b in l1.edges:
        ac, ar, _ = unpack_id(a)
        bc, br, _ = unpack_id(b)
        if abs(ac - bc) + abs(ar - br) <= 1:
            rel.add((a, b))
            out_rel.setdefault(a, []).append(b)
        else:
            far.append((a, b))
    drops = []
    derived = 0
    for a, b in sorted(far):
        ac, ar, _ = unpack_id(a)
        bc, br, _ = unpack_id(b)
        if abs(ac - bc) == 1 and abs(ar - br) == 1:
            ok = False
            for v in out_rel.get(a, ()):
                vc, vr, _ = unpack_id(v)
                if (vc, vr) in ((bc, ar), (ac, br)) and (v, b) in rel:
                    ok = True
                    break
            if ok:
                derived += 1
                continue
        drops.append((a, b))
    return rel, drops, derived


THIN = 3  # chunks: a drop link goes when a kept one between the same two regions has both ends this near


def graph_scc(nodes, edges):
    """{node: component} over the stored edges (derived diagonals don't change it: they follow stored ones)."""
    from mmtools.walkdata import scc
    ids = sorted(nodes)
    ix = {v: i for i, v in enumerate(ids)}
    n = len(ids)
    adj = [[] for _ in range(n)]
    for a, b in edges:
        adj[ix[a]].append(ix[b])
    start, flat = [0], []
    for lst in adj:
        flat += sorted(lst)
        start.append(len(flat))
    comp, _ = scc(n, start, flat)
    return {v: comp[i] for i, v in enumerate(ids)}


def thin_drops(l1: L1, rel, drops):
    """Drop links between the same two regions with both ends near a kept one go: the shortest first."""
    nodes = [node_id(gc, gr, p) for (gc, gr), ps in l1.parts.items() for p in range(len(ps))]
    comp = graph_scc(nodes, rel | set(drops))

    def cheb(a, b):
        ac, ar, _ = unpack_id(a)
        bc, br, _ = unpack_id(b)
        return max(abs(ac - bc), abs(ar - br))

    order = sorted(drops, key=lambda e: (comp[e[0]], comp[e[1]], cheb(*e), e))
    kept, bucket = [], {}
    for a, b in order:
        ac, ar, _ = unpack_id(a)
        g = (comp[a], comp[b])
        near = False
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for a2, b2 in bucket.get((g, ac // THIN + dx, ar // THIN + dy), ()):
                    if cheb(a, a2) <= THIN and cheb(b, b2) <= THIN:
                        near = True
                        break
        if not near:
            kept.append((a, b))
            bucket.setdefault((g, ac // THIN, ar // THIN), []).append((a, b))
    # a drop inside one region may be what holds it together: keep those of any region that falls apart
    comp2 = graph_scc(nodes, rel | set(kept))
    groups: dict[int, set] = {}
    for v in nodes:
        groups.setdefault(comp[v], set()).add(comp2[v])
    broken = {c for c, s in groups.items() if len(s) > 1}
    if broken:
        have = set(kept)
        kept += [e for e in drops if comp[e[0]] == comp[e[1]] and comp[e[0]] in broken and e not in have]
    sizes = sorted(collections.Counter(comp.values()).values(), reverse=True)
    info = {"drops_far": len(drops), "drops_far_cross_region": sum(1 for a, b in drops if comp[a] != comp[b]),
            "drops_kept": len(kept), "regions_split_restored": len(broken), "regions": len(sizes), "biggest": sizes[:6]}
    return sorted(kept), info


# --- encoding (docs/atlas-data.md, tools/mmtools/walkdata.py) -----------------------------------------------

def _c(v: int) -> str:
    assert 0 <= v < 64, v
    return chr(48 + v)


def chunk_record(l1: L1, rel, gc: int, gr: int):
    """('a' + value) for a simple chunk, else ('A' + class, record)."""
    ps = l1.parts.get((gc, gr), [])
    n = len(ps)
    if n == 0:
        return chr(97), None
    pe = l1.parts.get((gc + 1, gr), [])
    pso = l1.parts.get((gc, gr + 1), [])

    def relation(other, ox, oy):
        bits = []
        for i in range(n):
            for j in range(len(other)):
                a, b = node_id(gc, gr, i), node_id(ox, oy, j)
                bits.append(((a, b) in rel) + 2 * ((b, a) in rel))
        return bits

    E = relation(pe, gc + 1, gr)
    S = relation(pso, gc, gr + 1)
    simple = n == 1 and ps[0][1] and all(b in (0, 3) for b in E) and all(b in (0, 3) for b in S)
    simple = simple and (len(pe) <= 1 or not any(E)) and (len(pso) <= 1 or not any(S))
    if simple:
        v = ps[0][0] + (4 if len(pe) == 1 and E[0] == 3 else 0) + (8 if len(pso) == 1 and S[0] == 3 else 0)
        return chr(97 + v), None
    body = [_c(n + 8 * len(pe)), _c(len(pso))]
    for cls, centre, rep in ps:
        body += [_c(rep), _c(cls + 4 * centre)]
    for bits in (E, S):
        for k in range(0, len(bits), 3):
            t = bits[k:k + 3]
            body.append(_c(sum(b << (2 * i) for i, b in enumerate(t))))
    if n >= 2:
        intra = [int((node_id(gc, gr, i), node_id(gc, gr, j)) in rel) for i in range(n) for j in range(n) if i != j]
        for k in range(0, len(intra), 6):
            body.append(_c(sum(b << i for i, b in enumerate(intra[k:k + 6]))))
        lab = l1.labels[(gc, gr)]
        i = 0
        while i < 64:
            j = i
            while j < 64 and j - i < 8 and lab[j] == lab[i]:
                j += 1
            body.append(_c(lab[i] + 8 * (j - i - 1)))
            i = j
    L = len(body)
    return chr(65 + ps[0][0]), _c(L // 64) + _c(L % 64) + "".join(body)


def encode_drop(i: int, p: int, d: int, other: int) -> str:
    oc, orow, q = unpack_id(other)
    return _c(i // 64) + _c(i % 64) + _c(p + 8 * d) + _c(oc // 64) + _c(oc % 64) + _c(orow // 64) + _c(orow % 64) + _c(q)


def lua_chars(s: str) -> str:
    return '"' + s.replace("\\", "\\\\") + '"'


def encode_map(l1: L1, rel, drops):
    """{key: (letters, parts string)}, {key: drops string}."""
    from mmtools.luaout import run_letters
    tiles = {}
    for key in l1.tiles:
        col, row = key // 64, key % 64
        letters, recs = [], []
        for i in range(256):
            gc, gr = col * 16 + i % 16, row * 16 + i // 16
            letter, rec = chunk_record(l1, rel, gc, gr)
            letters.append(letter)
            if rec:
                recs.append(rec)
        tiles[key] = (run_letters(letters), "".join(recs))
    dl: dict[int, list] = {}
    for a, b in drops:
        for d, (x, y) in enumerate(((a, b), (b, a))):
            xc, xr, xp = unpack_id(x)
            key = (xc // 16) * 64 + xr // 16
            i = (xr % 16) * 16 + xc % 16
            dl.setdefault(key, []).append((i, xp, d, y))
    dstr = {k: "".join(encode_drop(*e) for e in sorted(v)) for k, v in dl.items()}
    return tiles, dstr


def bake(fine: dict, tiles) -> tuple[L1, dict]:
    """One map, L0 to L1."""
    t0 = time.time()
    f = Fine(fine)
    pc = Pieces(f)
    t1 = time.time()
    keys = np.union1d(piece_moves(f, pc.pid), descents(f, pc.pid, pc.pch)[0])
    t2 = time.time()
    keep, keys, stats = prune(f, pc, keys)
    l1 = build_l1(f, pc, keep, keys, tiles)
    stats.update(chunks=f.n, tris=dict(zip(('hole', 'flat', 'water', 'harmful', 'steep', 'wall'), np.bincount(f.kind.ravel(), minlength=6).tolist())), t_pieces=round(t1 - t0, 1),
                 t_moves=round(t2 - t1, 1), t_l1=round(time.time() - t2, 1))
    return l1, stats


HEAD = """-- GENERATED by tools/gen_walk.py from the {product} {version} terrain (ADT heights, MH2O liquids). Do not edit.
"""


def main() -> None:
    from mmtools.luaout import data_head
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("-o", "--output", required=True, help="Data/Walk.lua")
    parser.add_argument("--parts", help="Data/WalkParts.lua (default: next to --output)")
    parser.add_argument("--cache", help="keep / read each map's terrain as DIR/fine_<inst>.npz")
    parser.add_argument("--report", help="write each map's numbers (JSON) here")
    parser.add_argument("--inst", type=int, nargs="*", help="only these maps (for experiments)")
    parser.add_argument("--min-tiles", type=int, default=20, help="skip maps with fewer terrain tiles (default 20)")
    ns = parser.parse_args()
    src = source_from_args(parser, ns)
    parts_path = ns.parts or os.path.join(os.path.dirname(ns.output), "WalkParts.lua")

    src.prefetch([MAP_DB2, LIQUIDTYPE_DB2])
    map_db2, liquid_db2 = src.read(MAP_DB2), src.read(LIQUIDTYPE_DB2)
    if map_db2 is None or liquid_db2 is None:
        raise SystemExit("Map.db2 / LiquidType.db2 not available")
    harmful = harmful_liquids(liquid_db2)
    maps = [m for m in read_maps(map_db2) if m.kind is None and (not ns.inst or m.inst in ns.inst)]
    src.prefetch(m.wdt for m in maps)

    walk, parts, drops = [], [], []
    report = {}
    for m in sorted(maps, key=lambda m: m.inst):
        wdt = src.read(m.wdt)
        if wdt is None:
            continue
        adts = {k: t.root_adt for k, t in wdt_maid(wdt).items() if t.root_adt}
        if len(adts) < ns.min_tiles:
            continue
        t = time.time()
        fine = load_fine(src, m.inst, adts, harmful, ns.cache)
        l1, stats = bake(fine, adts.keys())
        rel, dl, derived = l1_split(l1)
        dl, info = thin_drops(l1, rel, dl)
        tiles, dstr = encode_map(l1, rel, dl)
        stats.update(info, far_derived=derived)
        stats["parts"] = sum(len(v) for v in l1.parts.values())
        stats["parts_per_chunk"] = sorted(collections.Counter(len(v) for v in l1.parts.values()).items())
        stats["chunks_complex"] = sum(1 for a, _ in tiles.values() for ch in decode_letters(a) if ch.isupper())
        stats["chunks_with_parts"] = len(l1.parts)
        stats["bytes"] = {"walk": sum(len(a) + 14 for a, _ in tiles.values()), "parts": sum(len(b) + 14 for _, b in tiles.values() if b),
                          "drops": sum(len(d) + 14 for d in dstr.values())}
        stats["t_all"] = round(time.time() - t, 1)
        log("%s: [%d] %s: %s" % (src.product, m.inst, m.name, json.dumps(stats)))
        report[m.inst] = stats
        name = m.name.replace("\n", " ")
        walk.append(f"  [{m.inst}] = {{ -- {name}\n")
        walk += [f"    [{k}] = \"{tiles[k][0]}\",\n" for k in sorted(tiles)]
        walk.append("  },\n")
        recs = [(k, tiles[k][1]) for k in sorted(tiles) if tiles[k][1]]
        if recs:
            parts.append(f"  [{m.inst}] = {{ -- {name}\n")
            parts += [f"    [{k}] = {lua_chars(s)},\n" for k, s in recs]
            parts.append("  },\n")
        if dstr:
            drops.append(f"  [{m.inst}] = {{ -- {name}\n")
            drops += [f"    [{k}] = {lua_chars(dstr[k])},\n" for k in sorted(dstr)]
            drops.append("  },\n")
    head = HEAD.format(product=src.product, version=src.version)
    with open(ns.output, "w", encoding="utf-8", newline="\n") as out:
        out.write(head)
        out.write("-- [inst][col * 64 + row] = the tile's 16x16 chunks (iy * 16 + ix), a letter each, a run as the letter and\n")
        out.write("--   its length: 'a' + value, a simple chunk (value = class: 0 none, 1 land, 2 water, 3 magma/slime; + 4 both\n")
        out.write("--   ways to the east chunk's one part, + 8 to the south's); 'A' + class, a complex one: Data/WalkParts.lua.\n")
        out.write("--   docs/atlas-data.md, tools/mmtools/walkdata.py\n")
        out.write(data_head("Walk"))
        out.write("D.Walk = {\n" + "".join(walk) + "}\n")
    with open(parts_path, "w", encoding="utf-8", newline="\n") as out:
        out.write(head)
        out.write("-- WalkParts[inst][col * 64 + row] = the tile's complex chunks' records (Data/Walk.lua's upper-case letters), in\n")
        out.write("--   chunk order; WalkDrops[inst][col * 64 + row] = the drop links of the tile's parts, 8 chars each. Chars are\n")
        out.write("--   chr(48 + v), v 0..63. docs/atlas-data.md, tools/mmtools/walkdata.py\n")
        out.write(data_head("WalkParts"))
        out.write("D.WalkParts = {\n" + "".join(parts) + "}\n")
        out.write("D.WalkDrops = {\n" + "".join(drops) + "}\n")
    if ns.report:
        with open(ns.report, "w") as f:
            json.dump(report, f, indent=1)


if __name__ == "__main__":
    main()

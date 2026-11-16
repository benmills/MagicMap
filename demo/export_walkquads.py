#!/usr/bin/env python3
"""Export the walk grid's 4-yard squares for the demo's pathing debug (its 4-yd layer): what tools/gen_walk.py
reads before it votes each 33-yard chunk into one class, per square, for every tile of the demo's maps.

  .venv/bin/python demo/export_walkquads.py local "/Applications/World of Warcraft" wowf [--inst 0 1 2991]

Writes demo/walkquads/<inst>/<tile key>.bin (gitignored: from Blizzard's terrain), gzip: per chunk (iy * 16 + ix)
per square (qy * 8 + qx), 3 bytes:
  flags   bit 0 deep (liquid deeper than gen_walk's SWIM_DEPTH), bit 1 harmful (magma/slime), bit 2 a terrain hole
          (a cave mouth or a building's footprint: no ground); 255: no chunk there
  plane   the square's slope as gen_walk takes it (the plane through its 4 corners), degrees
  steep   the steepest of the 4 triangles the game draws it as (around its centre vertex), degrees
"""
import argparse
import gzip
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_walk as gw  # noqa: E402
from mmtools.formats import adt_chunks, adt_liquids, iter_chunks, wdt_maid  # noqa: E402
from mmtools.maps import MAP_DB2, read_maps  # noqa: E402
from mmtools.sources import add_source_args, source_from_args  # noqa: E402
from export_terrain import holes  # noqa: E402

Q = gw.QUAD


def tri(p0, p1, p2):
    ux, uy, uz = p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]
    vx, vy, vz = p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    return math.degrees(math.atan2(math.hypot(nx, ny), abs(nz)))


def tile(buf, harmful):
    out = bytearray(b"\xff\x00\x00" * 256 * 64)
    liquids = {}
    for liq in adt_liquids(buf):
        liquids.setdefault((liq.ix, liq.iy), []).append(liq)
    masks = holes(buf)
    for ch in adt_chunks(buf):
        if not (0 <= ch.ix < 16 and 0 <= ch.iy < 16):
            continue
        z, h, mask = ch.z, ch.heights, masks.get((ch.ix, ch.iy), 0)
        for qy in range(8):
            for qx in range(8):
                flags, plane, steep = 0, 0, 0
                if h is not None:
                    a, b = z + h[qy * 17 + qx], z + h[qy * 17 + qx + 1]
                    c, d = z + h[(qy + 1) * 17 + qx], z + h[(qy + 1) * 17 + qx + 1]
                    m = z + h[qy * 17 + 9 + qx]
                    ground = (a + b + c + d + m) / 5
                    gx, gy = (b + d - a - c) / (2 * Q), (c + d - a - b) / (2 * Q)
                    plane = round(math.degrees(math.atan(math.hypot(gx, gy))))
                    A, B, C, D, M = (0, 0, a), (Q, 0, b), (0, Q, c), (Q, Q, d), (Q / 2, Q / 2, m)
                    steep = round(max(tri(A, B, M), tri(B, D, M), tri(D, C, M), tri(C, A, M)))
                    for liq in liquids.get((ch.ix, ch.iy), ()):
                        if liq.covers(qx, qy) and liq.surface > ground:
                            if liq.liquid_type in harmful:
                                flags |= 2
                            elif liq.surface - ground > gw.SWIM_DEPTH:
                                flags |= 1
                if mask >> (qy * 8 + qx) & 1:
                    flags |= 4
                i = ((ch.iy * 16 + ch.ix) * 64 + qy * 8 + qx) * 3
                out[i:i + 3] = bytes((flags, min(90, plane), min(90, steep)))
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--inst", type=int, nargs="+", default=[0, 1, 2991])
    ap.add_argument("--out", default=os.path.join(ROOT, "demo", "walkquads"))
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    src.prefetch([MAP_DB2, gw.LIQUIDTYPE_DB2])
    harmful = gw.harmful_liquids(src.read(gw.LIQUIDTYPE_DB2))
    for m in read_maps(src.read(MAP_DB2)):
        if m.inst not in ns.inst or m.kind is not None:
            continue
        adts = {k: t.root_adt for k, t in wdt_maid(src.read(m.wdt)).items() if t.root_adt}
        src.prefetch(adts.values())
        os.makedirs(os.path.join(ns.out, str(m.inst)), exist_ok=True)
        n = 0
        for key in sorted(adts):
            buf = src.read(adts[key])
            if buf is None:
                continue
            with open(os.path.join(ns.out, str(m.inst), f"{key}.bin"), "wb") as f:
                f.write(gzip.compress(tile(buf, harmful), 9, mtime=0))
            n += 1
        print(f"{m.inst}: {n} tiles", flush=True)


if __name__ == "__main__":
    main()

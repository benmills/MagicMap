#!/usr/bin/env python3
"""Generate Textures/PlayerArrow.tga: the Minimap's own player arrow (the
2x art of atlas ui-hud-minimap-arrow-player-2x) with its baked drop shadow
softened. On our bright map that shadow reads as a heavy dark halo.

The shadow is the dark, translucent part reachable from the image's edge
without crossing the arrow's lit outline. Its alpha is scaled (by --shadow)
and it is dropped beyond --reach pixels from the arrow, so it hugs the edge:
denser, never wider (the arrow's footprint is the same). The arrow and its
dark centre ring are untouched. The texture is padded to 64x64 (the arrow
centred), a size every client loads.
The spike's tools/gen_arrow.py, on this repo's sources (docs/v1-plan.md §4).

  python3 tools/gen_arrow.py local "/Applications/World of Warcraft" wow_classic_beta

A new texture file needs a full client restart, not just /reload (spike-bugs L5).
"""
from __future__ import annotations

import argparse
import os
import struct
from collections import deque

from mmtools.sources import add_source_args, source_from_args
from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ATLAS_FILE = 4618666           # the 2x HUD minimap atlas (UiTextureAtlas 1995)
ARROW = (441, 238, 486, 283)   # ui-hud-minimap-arrow-player-2x in it: left, top, right, bottom
SIZE = 64
LIT = 70                       # mean channel value from which a pixel is the arrow's lit outline
SOLID = 40                     # alpha below which a pixel is never outline


def decode_blp(data: bytes) -> tuple[int, int, bytes]:
    """(w, h, RGBA bytes) of an uncompressed (encoding 3) BLP2's top mip."""
    if data[:4] != b"BLP2" or data[8] != 3:
        raise ValueError("expected an uncompressed BLP2")
    w, h = struct.unpack_from("<II", data, 12)
    off = struct.unpack_from("<I", data, 20)[0]
    bgra = data[off:off + w * h * 4]
    rgba = bytearray(len(bgra))
    rgba[0::4], rgba[1::4], rgba[2::4], rgba[3::4] = bgra[2::4], bgra[1::4], bgra[0::4], bgra[3::4]
    return w, h, bytes(rgba)


def soften(px: list[list[list[int]]], k: float, reach: int) -> None:
    """Scale the alpha of the shadow (see the module doc) by k, and drop the
    part more than reach steps from the arrow, in place."""
    h, w = len(px), len(px[0])
    seen = set()
    q = deque([(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)])
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        r, g, b, a = px[y][x]
        if a > SOLID and (r + g + b) / 3 >= LIT:
            continue
        seen.add((x, y))
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    # Steps from the arrow (every pixel outside the shadow), through the shadow.
    near = {(x, y): 0 for y in range(h) for x in range(w) if (x, y) not in seen}
    q = deque(near)
    while q:
        x, y = q.popleft()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= n[0] < w and 0 <= n[1] < h and n not in near:
                near[n] = near[(x, y)] + 1
                q.append(n)
    for x, y in seen:
        px[y][x][3] = int(px[y][x][3] * k) if near[(x, y)] <= reach else 0


def arrow(blp: bytes, shadow: float, reach: int) -> bytes:
    """The TGA's bytes from the atlas file's."""
    w, _, rgba = decode_blp(blp)
    l, t, r, b = ARROW
    px = [[list(rgba[(y * w + x) * 4:(y * w + x) * 4 + 4]) for x in range(l, r)] for y in range(t, b)]
    soften(px, shadow, reach)
    pad_x, pad_y = (SIZE - (r - l)) // 2, (SIZE - (b - t)) // 2
    rows = [[(0, 0, 0, 0)] * SIZE for _ in range(SIZE)]
    for y, row in enumerate(px):
        rows[pad_y + y] = rows[pad_y + y][:pad_x] + [tuple(p) for p in row] + rows[pad_y + y][pad_x + len(row):]
    return write_tga(SIZE, SIZE, rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(parser)
    parser.add_argument("--shadow", type=float, default=0.7, help="the shadow's alpha, of the original")
    parser.add_argument("--reach", type=int, default=6, help="the shadow's reach past the arrow, in pixels")
    parser.add_argument("-o", "--output", default=os.path.join(ROOT, "Textures", "PlayerArrow.tga"))
    ns = parser.parse_args()
    src = source_from_args(parser, ns)
    src.prefetch([ATLAS_FILE])
    blp = src.read(ATLAS_FILE)
    if blp is None:
        raise SystemExit(f"file {ATLAS_FILE} (the 2x minimap atlas) not available")
    with open(ns.output, "wb") as f:
        f.write(arrow(blp, ns.shadow, ns.reach))
    l, t, r, b = ARROW
    print(f"wrote {ns.output} ({r - l}x{b - t} arrow in {SIZE}x{SIZE}, shadow at {ns.shadow:.0%}, reach {ns.reach})")


if __name__ == "__main__":
    main()

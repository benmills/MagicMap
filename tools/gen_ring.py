#!/usr/bin/env python3
"""Generate Textures/GlowRing.tga: a thin white ring, transparent inside, that ui/Pins.lua tints gold
around the followed pin (the look of the Blizzard map's own rings, with no filled disc under the icon).

The ring is 64x64, its outer edge on the image's edge and 4 px thick (anti-aliased by 4x4 samples), so
it stays thin at any size it is drawn at. Pins draw it 4 px wider than the icon, 2 px out past its edge.
Needs no game files; a new texture file needs a full client restart, not just /reload (spike-bugs L5).

  python3 tools/gen_ring.py
"""
from __future__ import annotations

import argparse
import os

from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 64
OUTER, THICK = 31.5, 4.0  # radius, ring thickness, px in the image
SUB = 4  # samples per side, per pixel


def coverage(x: int, y: int) -> float:
    c = SIZE / 2
    hit = 0
    for j in range(SUB):
        for i in range(SUB):
            px = x + (i + 0.5) / SUB - c
            py = y + (j + 0.5) / SUB - c
            d = (px * px + py * py) ** 0.5
            if OUTER - THICK <= d <= OUTER:
                hit += 1
    return hit / (SUB * SUB)


def ring() -> bytes:
    rows = []
    for y in range(SIZE - 1, -1, -1):  # write_tga takes the top row first
        rows.append([(255, 255, 255, round(coverage(x, y) * 255)) for x in range(SIZE)])
    return write_tga(SIZE, SIZE, rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-o", "--output", default=os.path.join(ROOT, "Textures", "GlowRing.tga"))
    ns = parser.parse_args()
    with open(ns.output, "wb") as f:
        f.write(ring())
    print(f"wrote {ns.output} ({SIZE}x{SIZE}, ring {THICK:g} px thick)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Mask textures for the Minimap inside MagicMap: Textures/MinimapMask/Rect<w>x<h>.tga.

Each is SIZE x SIZE, opaque inside a centred w x h rectangle and transparent
outside it (w and h even, MIN..SIZE; SIZE is the whole width or height, and
the whole square is WHITE8X8, so it isn't written). The client hides minimap
blips where its mask is transparent, and a mask can only cover the whole
Minimap, centred on you, so MinimapBlips.lua makes the Minimap as big as its
zoom wants and picks the biggest rectangle around you that fits the window.

  python3 tools/gen_minimap_masks.py            # writes Textures/MinimapMask/
  python3 tools/gen_minimap_masks.py -o DIR

Keep SIZE and MIN in step with MASK_TEXELS and MASK_MIN in MinimapBlips.lua.
New texture files need a full client restart in game, not /reload.
"""
from __future__ import annotations

import argparse
import os

from mmtools.tga import write_tga

SIZE = 32
MIN = 4
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sizes() -> list[tuple[int, int]]:
    """Every (w, h) shipped."""
    return [(w, h) for w in range(MIN, SIZE + 1, 2) for h in range(MIN, SIZE + 1, 2) if (w, h) != (SIZE, SIZE)]


def mask(w: int, h: int) -> bytes:
    x0, x1 = (SIZE - w) // 2, (SIZE + w) // 2
    y0, y1 = (SIZE - h) // 2, (SIZE + h) // 2
    rows = [[(255, 255, 255, 255 if x0 <= x < x1 and y0 <= y < y1 else 0) for x in range(SIZE)] for y in range(SIZE)]
    return write_tga(SIZE, SIZE, rows)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "Textures", "MinimapMask"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name in os.listdir(args.out):  # an earlier set's
        if name.endswith(".tga"):
            os.remove(os.path.join(args.out, name))
    for w, h in sizes():
        with open(os.path.join(args.out, f"Rect{w}x{h}.tga"), "wb") as f:
            f.write(mask(w, h))
    print(f"{len(sizes())} masks in {args.out}")


if __name__ == "__main__":
    main()

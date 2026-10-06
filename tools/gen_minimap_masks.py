#!/usr/bin/env python3
"""Minimap mask textures for minimap mode: Textures/MinimapMask/Square<n>.tga.

Each is SIZE x SIZE, opaque inside a centred n x n square and transparent
outside it (n even, MIN..SIZE-2; the full square is WHITE8X8). The client
hides minimap blips where its mask is transparent, so MinimapBlips.lua can
make the Minimap bigger than the window around you and still keep its blips
inside: it picks the mask whose square is the biggest that fits the window.

  python3 tools/gen_minimap_masks.py            # writes Textures/MinimapMask/
  python3 tools/gen_minimap_masks.py -o DIR

Keep SIZE and MIN in step with MASK_TEXELS and MASK_MIN in MinimapBlips.lua.
New texture files need a full client restart in game, not /reload.
"""
from __future__ import annotations

import argparse
import os

from mmtools.tga import write_tga

SIZE = 64
MIN = 8
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def mask(n: int) -> bytes:
    lo, hi = (SIZE - n) // 2, (SIZE + n) // 2
    rows = [[(255, 255, 255, 255 if lo <= x < hi and lo <= y < hi else 0) for x in range(SIZE)] for y in range(SIZE)]
    return write_tga(SIZE, SIZE, rows)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-o", "--out", default=os.path.join(ROOT, "Textures", "MinimapMask"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for n in range(MIN, SIZE, 2):
        with open(os.path.join(args.out, f"Square{n}.tga"), "wb") as f:
            f.write(mask(n))
    print(f"{(SIZE - MIN) // 2} masks in {args.out}")


if __name__ == "__main__":
    main()

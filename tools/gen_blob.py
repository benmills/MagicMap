#!/usr/bin/env python3
"""Generate Textures/BlobHatch<Name>.tga: the quest areas' fill art (ui/Areas.lua), a fine hatch in place of
the client's flat fill so that areas laid over one another stay told apart, as a printed map's hatching
does. A QuestPOIFrame tiles its fill texture over the area (the client's UI-QuestBlob-Inside is 64x64,
opaque, flat, tiled) and scales its alpha by SetFillAlpha; the edges stay the client's own
(Interface/WorldMap/UI-QuestBlob-Outside and its kin).

Each is 32x32 and tiles seamlessly (every period divides 32), in Inside's colour (read off the client's
file with tools/casc_extract.py, FileDataID 334387, a BLP2: flat 58, 109, 255, here BLUE) in every texel,
so the soft side of a line blends to no other colour, with the pattern in the alpha:
  Slash  "/" diagonals, 8 px apart
  Back   "\\" diagonals, 8 px apart
  Horiz  horizontal lines, 8 px apart
  Dots   2 px dots on an 8 px grid
ui/Areas.lua gives each quest one by its id; two that overlap with different ones read as a cross-hatch.
Needs no game files; a new texture file needs a full client restart, not just /reload (spike-bugs L5).

  python3 tools/gen_blob.py
"""
from __future__ import annotations

import argparse
import os

from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLUE = (58, 109, 255)  # UI-QuestBlob-Inside's colour
SIDE, STEP = 32, 8  # a tile's side; a pattern's period (divides SIDE, so it tiles)
WIDTH = 1.6  # a line's width in px, soft at its sides


def wrap(v: float) -> float:
    """v's distance to the nearest multiple of STEP."""
    v %= STEP
    return min(v, STEP - v)


def line(d: float) -> int:
    """Alpha of a texel d px from the nearest line's centre: full within half WIDTH, 0 half a px beyond."""
    return round(255 * min(1.0, max(0.0, WIDTH / 2 + 0.5 - d)))


def dot(x: float, y: float) -> int:
    d = (wrap(x) ** 2 + wrap(y) ** 2) ** 0.5
    return round(255 * min(1.0, max(0.0, 1.6 - d)))


# Alpha of the texel centred at (x, y); the diagonals' distance across a line is its offset over root 2.
PATTERNS = {
    "Slash": lambda x, y: line(wrap(x + y) / 2 ** 0.5),
    "Back": lambda x, y: line(wrap(x - y) / 2 ** 0.5),
    "Horiz": lambda x, y: line(wrap(y)),
    "Dots": dot,
}


def image(alpha) -> bytes:
    r, g, b = BLUE
    return write_tga(SIDE, SIDE, [[(r, g, b, alpha(x + 0.5, y + 0.5)) for x in range(SIDE)] for y in range(SIDE)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-o", "--outdir", default=os.path.join(ROOT, "Textures"))
    ns = parser.parse_args()
    for name, alpha in PATTERNS.items():
        with open(os.path.join(ns.outdir, f"BlobHatch{name}.tga"), "wb") as f:
            f.write(image(alpha))
    print(f"wrote {len(PATTERNS)} textures to {ns.outdir} ({SIDE}x{SIDE}, period {STEP})")


if __name__ == "__main__":
    main()

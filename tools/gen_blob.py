#!/usr/bin/env python3
"""Generate Textures/Blob<Part><Colour>.tga: the quest areas' art (ui/Areas.lua), one set per quest-log
difficulty colour (model/Quests.lua Difficulty: Grey, Green, Yellow, Orange, Red), since a QuestPOIFrame
takes a file for its fill and edge and has no colour setter.

The layout mirrors Blizzard's own (Interface/WorldMap/UI-QuestBlob-Inside and -Outside, read off the
client's files with tools/casc_extract.py, FileDataIDs 334387 and 334388): Inside 64x64, opaque, flat
colour, tiled over the area (its alpha from SetFillAlpha); Outside 16x16, swept along the outline with
x along the edge (constant) and y across it, alpha 220 at the first row falling to 0 by row 9 (the
ramp RAMP). Four parts a colour:
  Fill   64x64, the colour, opaque                            (as Inside)
  Edge   16x16, RAMP across                                   (as Outside: a solid edge)
  Dash   64x16, RAMP across, 16 px on and 16 off along x      (a dashed edge: complete quests)
  Glow   16x16, a wide soft fall-off across (1-t)^2, 255 to 0 (drawn wide and faint under the followed one)
Needs no game files; a new texture file needs a full client restart, not just /reload (spike-bugs L5).

  python3 tools/gen_blob.py
"""
from __future__ import annotations

import argparse
import os

from mmtools.tga import write_tga

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The quest log's difficulty colours (model/Quests.lua RED, ORANGE, YELLOW, GREEN, GREY), 0-255.
COLOURS = {
    "Red": (255, 26, 26),
    "Orange": (255, 128, 64),
    "Yellow": (255, 209, 0),
    "Green": (64, 191, 64),
    "Grey": (128, 128, 128),
}
# UI-QuestBlob-Outside's alpha down its 16 rows (the edge's inside at row 0).
RAMP = [220, 198, 155, 113, 82, 53, 34, 16, 5, 0, 0, 0, 0, 0, 0, 0]
FILL, EDGE, DASH = 64, 16, 64  # Fill's side, Edge's side, Dash's length along the edge (half of it on)
GLOW = [round(255 * (1 - (y + 0.5) / EDGE) ** 2) for y in range(EDGE)]


def image(w: int, h: int, rgb: tuple[int, int, int], alpha) -> bytes:
    """w by h of rgb, alpha(x, y) its alpha."""
    r, g, b = rgb
    return write_tga(w, h, [[(r, g, b, alpha(x, y)) for x in range(w)] for y in range(h)])


def parts(rgb: tuple[int, int, int]) -> dict[str, bytes]:
    return {
        "Fill": image(FILL, FILL, rgb, lambda x, y: 255),
        "Edge": image(EDGE, EDGE, rgb, lambda x, y: RAMP[y]),
        "Dash": image(DASH, EDGE, rgb, lambda x, y: RAMP[y] if x % (DASH // 2) < DASH // 4 else 0),
        "Glow": image(EDGE, EDGE, rgb, lambda x, y: GLOW[y]),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-o", "--outdir", default=os.path.join(ROOT, "Textures"))
    ns = parser.parse_args()
    n = 0
    for colour, rgb in COLOURS.items():
        for part, data in parts(rgb).items():
            with open(os.path.join(ns.outdir, f"Blob{part}{colour}.tga"), "wb") as f:
                f.write(data)
            n += 1
    print(f"wrote {n} textures to {ns.outdir} (Fill {FILL}x{FILL}, Edge and Glow {EDGE}x{EDGE}, Dash {DASH}x{EDGE})")


if __name__ == "__main__":
    main()

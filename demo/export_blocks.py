#!/usr/bin/env python3
"""The tiles' quick copies in blocks: every 8 x 8 tiles' 64 px copies (tiles/<inst>/64/) as one 512 px picture,
tiles/<inst>/b8/<bx>_<by>.webp (block bx, by: tiles bx*8.. and by*8.. of the map, a tile's key being col * 64 + row).
The page fills a view with these first: a screen of tiles in a few requests, where the 64 px copies are one a tile
(the host's cost is the requests, not the bytes), and a zoomed-out view draws only these.

  .venv/bin/python demo/export_blocks.py demo/tiles   # after export_tiles.py; a tiles folder of any demo
"""
import os
import sys

from PIL import Image

B, PX = 8, 64


def blocks(inst_dir: str) -> int:
    src, out = os.path.join(inst_dir, str(PX)), os.path.join(inst_dir, f"b{B}")
    if not os.path.isdir(src):
        return 0
    groups = {}
    for f in os.listdir(src):
        stem, ext = os.path.splitext(f)
        if ext == ".webp" and stem.isdecimal():
            k = int(stem)
            groups.setdefault((k // 64 // B, k % 64 // B), []).append((k // 64 % B, k % 64 % B, os.path.join(src, f)))
    os.makedirs(out, exist_ok=True)
    for (bx, by), cells in groups.items():
        pic = Image.new("RGBA", (B * PX, B * PX), (0, 0, 0, 0))
        for cx, cy, path in cells:
            with Image.open(path) as im:
                pic.paste(im.convert("RGBA").resize((PX, PX)), (cx * PX, cy * PX))
        pic.save(os.path.join(out, f"{bx}_{by}.webp"), quality=85, method=6)
    return len(groups)


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "tiles")
    for inst in sorted(os.listdir(root)):
        if os.path.isdir(os.path.join(root, inst)):
            n = blocks(os.path.join(root, inst))
            if n:
                print(f"tiles/{inst}/b{B}: {n} blocks")

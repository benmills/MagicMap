#!/usr/bin/env python3
"""Export the game's own map icons that the demo's pins use, as one sprite sheet.

  .venv/bin/python tools/export_icons.py local "/Applications/World of Warcraft" wow_classic_beta

Which icon a pin gets is the demo's choice (GAME_ICON in demo/index.html); this
exports exactly the icons named there, plus every AreaPOI icon index:
  - "name": a UiTextureAtlasMember (by CommittedName, case-insensitive),
    cropped from its UiTextureAtlas texture (the addon: SetAtlas(name));
  - "file:FDID": a whole texture file (the addon: SetTexture(fdid));
  - "poi:N": cell N of Interface/Minimap/POIIcons, 14 cells of 18 px a row, as
    the game's GetPOITextureCoords (the addon: SetTexture + SetTexCoord).
Writes demo/icons/icons.png and demo/icons/icons.json: { key: [x, y, w, h] }.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import struct
import sys

from PIL import Image

from mmtools.dbd import read_table
from mmtools.sources import add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEMO = os.path.join(ROOT, "demo")
UI_TEXTURE_ATLAS, UI_TEXTURE_ATLAS_MEMBER, AREA_POI = 897470, 897532, 1000630
POI_ICONS, POI_CELL, POI_COLUMNS = 136441, 18, 14
SHEET_W, PAD = 256, 1


def blp(b: bytes) -> Image.Image:
    """A BLP as RGBA; Pillow reads all but encoding 3 (uncompressed BGRA), done here."""
    enc, _, _, _, w, h = struct.unpack_from("<BBBBII", b, 8)
    if enc == 3:
        off = struct.unpack_from("<I", b, 20)[0]
        return Image.frombytes("RGBA", (w, h), b[off:off + w * h * 4], "raw", "BGRA")
    return Image.open(io.BytesIO(b)).convert("RGBA")


def wanted() -> list[str]:
    html = open(os.path.join(DEMO, "index.html"), encoding="utf-8").read()
    block = re.search(r"const GAME_ICON = \{(.*?)\n\};", html, re.S).group(1)
    return list(dict.fromkeys(re.findall(r'"([\w:-]+)"', re.sub(r"//.*", "", block))))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("-o", "--out", default=os.path.join(DEMO, "icons"))
    ns = ap.parse_args()
    src, out = source_from_args(ap, ns), ns.out

    atlases = {a["ID"]: a for a in read_table("UiTextureAtlas", src.read(UI_TEXTURE_ATLAS))}
    members = {m["CommittedName"].lower(): m for m in read_table("UiTextureAtlasMember", src.read(UI_TEXTURE_ATLAS_MEMBER))}
    textures: dict[int, Image.Image] = {}

    def texture(fdid: int) -> Image.Image:
        if fdid not in textures:
            textures[fdid] = blp(src.read(fdid))
        return textures[fdid]

    icons: dict[str, Image.Image] = {}
    for key in wanted():
        if key.startswith("file:"):
            icons[key] = texture(int(key[5:]))
        else:
            m = members[key.lower()]
            icons[key] = texture(atlases[m["UiTextureAtlasID"]]["FileDataID"]).crop(
                (m["CommittedLeft"], m["CommittedTop"], m["CommittedRight"], m["CommittedBottom"]))
    for n in sorted({p["Icon"] for p in read_table("AreaPOI", src.read(AREA_POI))}):
        x, y = n % POI_COLUMNS * POI_CELL, n // POI_COLUMNS * POI_CELL
        icons[f"poi:{n}"] = texture(POI_ICONS).crop((x, y, x + POI_CELL, y + POI_CELL))

    # Shelf packing, tallest first.
    place, x, y, shelf = {}, 0, 0, 0
    for key, im in sorted(icons.items(), key=lambda kv: (-kv[1].height, kv[0])):
        if x + im.width > SHEET_W:
            x, y, shelf = 0, y + shelf + PAD, 0
        place[key] = [x, y, im.width, im.height]
        x, shelf = x + im.width + PAD, max(shelf, im.height)
    sheet = Image.new("RGBA", (SHEET_W, y + shelf), (0, 0, 0, 0))
    for key, (px, py, _, _) in place.items():
        sheet.paste(icons[key], (px, py))
    os.makedirs(out, exist_ok=True)
    sheet.save(os.path.join(out, "icons.png"), optimize=True)
    with open(os.path.join(out, "icons.json"), "w") as f:
        rows = ",\n".join(f"  {json.dumps(k)}: {json.dumps(v)}" for k, v in sorted(place.items()))
        f.write(f'{{"source": {json.dumps(f"{src.product} {src.version}")}, "icons": {{\n{rows}\n}}}}\n')
    print(f"{len(place)} icons, {sheet.width}x{sheet.height} -> {out}", file=sys.stderr)


if __name__ == "__main__":
    main()

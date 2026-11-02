"""tools/gen_fullmap.py: the two pictures share a frame; raw is the tiles alone, fixed lays the baked layers over them in order."""
import json

import numpy as np
from PIL import Image

import gen_fullmap as fm


def test_raw_and_fixed(tmp_path):
    tile = lambda k: Image.new("RGB", (4, 4), (200, 0, 0) if k == 65 else (0, 0, 200))
    tiles, sea = {65: 1, 66: 2}, {66: True}  # col 1, rows 1 and 2; the second open sea
    box = fm.frame(tiles)
    assert box == (0, 0, 3, 4)
    (tmp_path / "over").mkdir()
    Image.new("RGBA", (4, 4), (0, 255, 0, 255)).save(tmp_path / "over" / "a.png")
    (tmp_path / "over" / "over.json").write_text(json.dumps({"0": [{"file": "a.png", "col": 1, "row": 1, "w": .5, "h": 1}]}))
    r = fm.raw(tile, tiles, box, 4)
    f = fm.fixed(tile, tiles, sea, {}, 0, box, 4, ["over"], str(tmp_path))
    assert r.shape == f.shape == (16, 12, 3)
    assert tuple(r[10, 6]) == (0, 0, 200), "raw keeps the sea tile"
    assert tuple(f[10, 6]) == (0, 0, 0), "fixed doesn't"
    assert tuple(f[5, 5]) == (0, 255, 0) and tuple(f[5, 7]) == (200, 0, 0), "the layer over its half of the tile"

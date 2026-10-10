"""tools/gen_minimap_masks.py: the shipped mask textures are what it writes,
and each is opaque exactly inside its centred rectangle."""
import os
import subprocess
import sys

from mmtools.tga import read_tga

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIPPED = os.path.join(os.path.dirname(TOOLS), "Textures", "MinimapMask")


def test_masks(tmp_path):
    subprocess.run([sys.executable, os.path.join(TOOLS, "gen_minimap_masks.py"), "-o", str(tmp_path)],
                   check=True, capture_output=True)
    names = sorted(os.listdir(tmp_path))
    want = sorted(f"Rect{w}x{h}.tga" for w in range(4, 33, 2) for h in range(4, 33, 2) if (w, h) != (32, 32))
    assert names == want
    assert sorted(os.listdir(SHIPPED)) == want, "the shipped masks aren't the set it writes: rerun tools/gen_minimap_masks.py"
    for name in names:
        data = (tmp_path / name).read_bytes()
        with open(os.path.join(SHIPPED, name), "rb") as f:
            assert f.read() == data, f"{name} is stale: rerun tools/gen_minimap_masks.py"
        mw, mh = (int(v) for v in name[4:-4].split("x"))
        w, h, rows = read_tga(data)
        assert (w, h) == (32, 32)
        x0, x1, y0, y1 = (w - mw) // 2, (w + mw) // 2, (h - mh) // 2, (h + mh) // 2
        for y in (y0 - 1, y0, y1 - 1, y1):
            for x in (x0 - 1, x0, x1 - 1, x1):
                if 0 <= x < w and 0 <= y < h:
                    inside = x0 <= x < x1 and y0 <= y < y1
                    assert rows[y][x][3] == (255 if inside else 0)

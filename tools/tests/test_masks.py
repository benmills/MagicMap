"""tools/gen_minimap_masks.py: the shipped mask textures are what it writes,
and each is opaque exactly inside its centred square."""
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
    assert names == sorted(f"Square{n}.tga" for n in range(8, 64, 2))
    for name in names:
        data = (tmp_path / name).read_bytes()
        with open(os.path.join(SHIPPED, name), "rb") as f:
            assert f.read() == data, f"{name} is stale: rerun tools/gen_minimap_masks.py"
        n = int(name[6:-4])
        w, h, rows = read_tga(data)
        lo, hi = (w - n) // 2, (w + n) // 2
        assert (w, h) == (64, 64)
        for y in (lo - 1, lo, hi - 1, hi):
            for x in (lo - 1, lo, hi - 1, hi):
                inside = lo <= x < hi and lo <= y < hi
                assert rows[y][x][3] == (255 if inside else 0)

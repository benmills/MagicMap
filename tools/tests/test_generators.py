"""The data generators, end to end on a synthetic install, against golden
output. The goldens were checked against the generators' pre-port output:
tiles byte for byte, borders geometry for geometry (the old generator
chained and broke ties in hash order, so only its geometry was stable).

Regenerate after an intended change: UPDATE_GOLDEN=1 pytest tools/tests
"""
import os
import subprocess
import sys

import pytest

import fixtures
from mmtools.luaout import FORMATS

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOLDEN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "golden")


def run_tool(name, *args):
    subprocess.run([sys.executable, os.path.join(TOOLS, name), *args], check=True, capture_output=True)


def check_golden(path, name):
    golden = os.path.join(GOLDEN, name)
    with open(path, "rb") as f:
        got = f.read()
    if os.environ.get("UPDATE_GOLDEN"):
        with open(golden, "wb") as f:
            f.write(got)
    with open(golden, "rb") as f:
        assert got == f.read(), f"{name} changed (UPDATE_GOLDEN=1 to accept)"


@pytest.fixture(scope="module")
def generated(world, tmp_path_factory):
    out = tmp_path_factory.mktemp("out")
    tiles, borders = out / "tiles.lua", out / "borders.lua"
    run_tool("gen_tiles.py", "local", world, fixtures.PRODUCT, "-o", str(tiles))
    run_tool("gen_borders.py", "local", world, fixtures.PRODUCT, "-o", str(borders))
    return {"tiles": tiles, "borders": borders}


@pytest.mark.parametrize("kind", ["tiles", "borders"])
def test_golden(generated, kind):
    check_golden(generated[kind], f"{kind}.lua")


def test_deterministic(world, generated, tmp_path):
    again = tmp_path / "borders.lua"
    run_tool("gen_borders.py", "local", world, fixtures.PRODUCT, "-o", str(again))
    assert again.read_bytes() == generated["borders"].read_bytes()


def lua_load(path):
    """A generated file run as WoW does (addon, ns): its dataset, and the globals it left (none)."""
    from lupa import lua51
    L = lua51.LuaRuntime(encoding=None)
    before = set(L.globals().keys())
    ns = L.table()
    L.eval(b"function(p, ns) return assert(loadfile(p))('MagicMapAtlas', ns) end")(str(path).encode(), ns)
    assert set(L.globals().keys()) == before, "a Data file set a global"
    return ns[b"Data"]


def test_files_load_in_lua(generated):
    D = lua_load(generated["tiles"])
    tiles = D[b"Tiles"]
    assert D[b"formats"][b"Tiles"] == FORMATS["Tiles"]
    assert tiles[b"product"] == fixtures.PRODUCT.encode()
    maps = tiles[b"maps"]
    assert sorted(maps.keys()) == [0, 1, 36]  # not the battleground; not maps without a WDT
    assert maps[36][b"kind"] == b"dungeon" and maps[36][b"continent"] == 0
    D = lua_load(generated["borders"])
    assert list(D[b"Borders"].keys()) == [0]  # Kalimdor is under --min-tiles


def test_labels_regenerate(tmp_path):
    """tools/gen_labels.py over the committed Data files gives the committed Data/Labels.lua, byte for byte:
    deterministic, and Data/Labels.lua is current with Borders, Places, ... (test_atlas: its golden)."""
    out = tmp_path / "labels.lua"
    run_tool("gen_labels.py", "-o", str(out))
    with open(os.path.join(os.path.dirname(TOOLS), "Data", "Labels.lua"), "rb") as f:
        assert out.read_bytes() == f.read(), "Data/Labels.lua is stale: tools/gen_labels.py -o Data/Labels.lua"

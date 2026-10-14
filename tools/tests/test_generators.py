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


def lua_load(path, product):
    from lupa import lua51
    L = lua51.LuaRuntime(encoding=None)
    L.eval(b"function(p) return assert(loadfile(p))() end")(str(path).encode())
    return L


def test_files_load_in_lua(generated):
    L = lua_load(generated["tiles"], fixtures.PRODUCT)
    tiles = L.globals().MagicMap_Tiles
    assert tiles[b"product"] == fixtures.PRODUCT.encode()
    maps = tiles[b"maps"]
    assert sorted(maps.keys()) == [0, 1, 36]  # not the battleground; not maps without a WDT
    assert maps[36][b"kind"] == b"dungeon" and maps[36][b"continent"] == 0
    L = lua_load(generated["borders"], fixtures.PRODUCT)
    assert list(L.globals().MagicMap_Borders.keys()) == [0]  # Kalimdor is under --min-tiles

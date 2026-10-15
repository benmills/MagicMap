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


QUESTIEDB = os.environ.get("QUESTIEDB", "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/QuestieDB")
ROOT = os.path.dirname(TOOLS)

# Over one Atlas: each quest's Atlas.QuestSources as a string; and each npc, object or item id a
# quest or item names that Atlas can't resolve.
QUEST_SOURCES = """function(Atlas)
    local out, missing = {}, {}
    local get = { npc = Atlas.Npc, object = Atlas.Object, item = Atlas.Item }
    local KIND = { monster = "npc", killcredit = "npc", object = "object", item = "item" }
    local function need(kind, list)
        for _, id in ipairs(list) do
            if not get[kind](id) then missing[#missing + 1] = kind .. id end
        end
    end
    for id in pairs(Atlas.Data.Quests) do
        local q, parts = Atlas.Quest(id), {}
        for _, o in ipairs(Atlas.QuestSources(id)) do
            local s = {}
            for _, x in ipairs(o.sources) do s[#s + 1] = x.kind .. x.id end
            parts[#parts + 1] = table.concat({ o.kind, o.id, tostring(o.text), tostring(o.name), table.concat(s, ",") }, "|")
            if KIND[o.kind] then need(KIND[o.kind], { o.id }) end
        end
        out[id] = table.concat(parts, ";")
        need("npc", q.startedBy.npcs); need("object", q.startedBy.objects); need("item", q.startedBy.items)
        need("npc", q.finishedBy.npcs); need("object", q.finishedBy.objects)
    end
    for id in pairs(Atlas.Data.Items) do
        local i = Atlas.Item(id)
        need("npc", i.npcDrops); need("object", i.objectDrops); need("item", i.itemDrops); need("npc", i.vendors)
    end
    return out, missing
end"""


def entities(data):
    """Atlas's entities over the QuestieDB-derived files in data: QuestSources per quest, the ids
    a quest or item names that don't resolve, and the KB of Lua heap Items.lua takes."""
    from lupa import lua51
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns, kb = L.table(), L.eval("function() collectgarbage('collect'); return collectgarbage('count') end")
    run = L.eval("function(p, ns) return assert(loadfile(p))('MagicMapAtlas', ns) end")
    for name in ("Npcs", "Objects", "Quests"):
        run(os.path.join(data, f"{name}.lua"), ns)
    before = kb()
    run(os.path.join(data, "Items.lua"), ns)
    items_kb = kb() - before
    for rel in ("atlas/Coords.lua", "atlas/Entities.lua"):
        run(os.path.join(ROOT, rel), ns)
    out, missing = L.eval(QUEST_SOURCES)(ns.Atlas)
    return dict(out.items()), list(missing.values()), items_kb


def test_data_diet(tmp_path):
    """D3's diet (tools/gen_questie.py): every quest's sources the same as with every item and NPC
    (--full), every id a kept quest or item names there, Items under 2 MB of Lua."""
    if not os.path.isdir(QUESTIEDB):
        pytest.skip(f"no QuestieDB at {QUESTIEDB} (QUESTIEDB=...)")
    maps = ("--uimaps", os.path.join(ROOT, "Data", "UiMaps.lua"), "--tiles", os.path.join(ROOT, "Data", "Tiles.lua"))
    run_tool("gen_questie.py", QUESTIEDB, "-o", str(tmp_path), *maps)
    (tmp_path / "full").mkdir()
    run_tool("gen_questie.py", QUESTIEDB, "-o", str(tmp_path / "full"), "--full", *maps)
    full, _, full_kb = entities(tmp_path / "full")
    diet, missing, kb = entities(tmp_path)
    assert len(diet) > 5000 and diet == full
    assert missing == []
    assert kb < 2 * 1024 < full_kb, (kb, full_kb)


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

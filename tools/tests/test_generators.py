"""The data generators, end to end on a synthetic install, against golden
output. The goldens were checked against the generators' pre-port output:
tiles byte for byte, anchors value for value (the old generator
chained and broke ties in hash order, so only its geometry was stable).

Regenerate after an intended change: UPDATE_GOLDEN=1 pytest tools/tests
"""
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

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
    tiles, anchors = out / "tiles.lua", out / "anchors.lua"
    run_tool("gen_tiles.py", "local", world, fixtures.PRODUCT, "-o", str(tiles))
    run_tool("gen_anchors.py", "local", world, fixtures.PRODUCT, "-o", str(anchors))
    return {"tiles": tiles, "anchors": anchors}


@pytest.mark.parametrize("kind", ["tiles", "anchors"])
def test_golden(generated, kind):
    check_golden(generated[kind], f"{kind}.lua")


def test_deterministic(world, generated, tmp_path):
    again = tmp_path / "anchors.lua"
    run_tool("gen_anchors.py", "local", world, fixtures.PRODUCT, "-o", str(again))
    assert again.read_bytes() == generated["anchors"].read_bytes()


def lua_load(path):
    """A generated file run as WoW does (addon, ns): its dataset, and the globals it left (none)."""
    from lupa import lua51
    L = lua51.LuaRuntime(encoding=None)
    before = set(L.globals().keys())
    ns = L.table()
    L.eval(b"function(p, ns) return assert(loadfile(p))('MagicMap', ns) end")(str(path).encode(), ns)
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
    run = L.eval("function(p, ns) return assert(loadfile(p))('MagicMap', ns) end")
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
    (tmp_path / "full").mkdir()
    with ThreadPoolExecutor() as pool:  # the two runs side by side
        list(pool.map(lambda args: run_tool("gen_questie.py", QUESTIEDB, *args, *maps),
                      [("-o", str(tmp_path)), ("-o", str(tmp_path / "full"), "--full")]))
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
    D = lua_load(generated["anchors"])
    assert list(D[b"Anchors"].keys()) == [0]  # Kalimdor is under --min-tiles


def test_labels_regenerate(tmp_path):
    """tools/gen_labels.py over the committed Data files gives the committed Data/Labels.lua, byte for byte:
    deterministic, and Data/Labels.lua is current with Anchors, Places, ... (test_atlas: its golden)."""
    out = tmp_path / "labels.lua"
    run_tool("gen_labels.py", "-o", str(out))
    with open(os.path.join(os.path.dirname(TOOLS), "Data", "Labels.lua"), "rb") as f:
        assert out.read_bytes() == f.read(), "Data/Labels.lua is stale: tools/gen_labels.py -o Data/Labels.lua"


def test_walk_regions_regenerate(tmp_path):
    """tools/gen_walk_regions.py over the committed Data/Walk.lua, Data/WalkParts.lua and tools/walk_links.json
    gives the committed Data/WalkRegions.lua and Data/WalkGraph.lua, byte for byte (it also checks the reach table
    against the regions' full reach): regenerate them after any input changes."""
    inputs = ["Data/Walk.lua", "Data/WalkParts.lua", "tools/walk_links.json", "tools/gen_walk_regions.py"]
    changed = subprocess.run(["git", "status", "--porcelain", *inputs], cwd=ROOT, capture_output=True, text=True).stdout
    if not changed.strip() and not os.environ.get("MM_SLOW"):
        pytest.skip("its inputs as committed (25 s: MM_SLOW=1 runs it anyway)")
    out = tmp_path / "WalkRegions.lua"
    run_tool("gen_walk_regions.py", "-o", str(out))
    for name in ("WalkRegions.lua", "WalkGraph.lua"):
        with open(os.path.join(os.path.dirname(TOOLS), "Data", name), "rb") as f:
            assert (tmp_path / name).read_bytes() == f.read(), f"Data/{name} is stale: tools/gen_walk_regions.py -o Data/WalkRegions.lua"


def test_walk_data_reads_back():
    """The committed walk data through the reference reader (tools/mmtools/walkdata.py): every map's parts decode
    (records exactly fill their strings), each hand link joins two parts, a snap at a few known towns lands on a
    part of the map's biggest region, and the tile graph has at most 63 entrances a tile."""
    from mmtools import walkdata as wd
    data = os.path.join(os.path.dirname(TOOLS), "Data")
    maps = wd.load_walk(os.path.join(data, "Walk.lua"), os.path.join(data, "WalkParts.lua"))
    regions = wd.read_regions_file(os.path.join(data, "WalkRegions.lua"))
    graph = wd.read_graph_file(os.path.join(data, "WalkGraph.lua"))
    for inst, W in maps.items():
        for key in W.walk:
            W.tile(key)  # asserts the records' lengths
        for a, b, cost, name, oneway in regions["links"].get(inst, []):
            assert W.part(a) and W.part(b) and cost > 0, name
        for entry in graph[inst].values():
            nodes, costs, cross = wd.decode_graph(entry)
            assert 1 <= len(nodes) <= 63
    towns = {0: [(31.95, 49.75), (36.09, 49.28), (32.91, 42.41), (34.191, 44.286)],  # Goldshire, Lakeshire, Kharanos, Thorium Point
             1: [(37.1, 32.6), (39.002, 45.545), (40.892, 19.251), (32.3, 34.95)]}  # Crossroads, Gadgetzan, Everlook, Thunder Bluff low
    for inst, pts in towns.items():
        W, reg = maps[inst], regions["regions"][inst]
        for col, row in pts:
            u = W.snap(col, row)
            assert u is not None
            gc, gr, _ = wd.split_id(u)
            key = wd.tile_key(gc, gr)
            r = wd.decode_regions(reg[key])
            assert (r if isinstance(r, int) else r[W.tile_nodes(key).index(u)]) == 1, (inst, col, row)

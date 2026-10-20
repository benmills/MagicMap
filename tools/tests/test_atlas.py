"""Smoke test: Atlas loads in Lua 5.1 over the real data and its facts hold end to end."""
import os

import pytest

from atlas_lua import load_atlas

LABELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "golden", "labels.tsv")


def ids(t):
    return list(t.values())


def test_atlas():
    L, Atlas = load_atlas()

    # Tiles, coordinates, walk, camera.
    assert Atlas.Maps()[1].name == "Eastern Kingdoms"
    key = next(iter(Atlas.Tiles(0).keys()))
    assert Atlas.TileInfo(0, key).fdid == Atlas.Tiles(0)[key]
    col, row = Atlas.WorldToTile(*Atlas.TileToWorld(31.25, 40.5))
    assert abs(col - 31.25) < 1e-9 and abs(row - 40.5) < 1e-9
    gc, gr = int(32.378 * 16), int(49.024 * 16)  # Northshire
    assert Atlas.Walk.Cell(0, gc, gr)[0] == 1 and Atlas.Walk.Snap(0, gc, gr) == (gc, gr)
    assert Atlas.Camera.Fit(28, 30, 36, 38, 800, 400, 1, 16, 800) == (32, 34, 50)
    assert Atlas.Camera.Fit(32, 34, 32, 34, 800, 400, 1) == (32, 34, 6400)  # one point: MIN_SPAN wide, finite (E3)
    assert Atlas.Camera.Fit(32, 34, 32, 34, 800, 400, 1, None, None, 0) == (32, 34, 6400)  # a span under it: MIN_SPAN

    # Maps and areas: Elwynn Forest, Goldshire in it.
    assert Atlas.Continent(0) == 1415 and Atlas.Continent(1) == 1414
    assert "Elwynn Forest" in [z.name for z in ids(Atlas.Zones(0))]
    z = Atlas.ZoneAt(0, 32.378, 49.024)
    assert (z.name, z.mapID, z.zone) == ("Elwynn Forest", 1429, 12) and 0 < z.x < 1
    assert Atlas.MapToTile(1429, z.x, z.y)[0] == 0
    goldshire = Atlas.Area(Atlas.AreaAt(0, 31.97, 49.743))
    assert (goldshire.name, goldshire.zone) == ("Goldshire", 12)
    lo, hi = Atlas.ZoneLevels(12)
    assert 0 < lo <= hi
    assert Atlas.ZoneAt(0, 0.5, 0.5) is None
    assert Atlas.ZoneAt(509, 27, 46) is None  # Ruins of Ahn'Qiraj: no continent, no zone (Silithus' chunks there)

    # Places.
    dm = Atlas.Dungeon(36)
    assert dm.name == "Deadmines" and dm.entranceInst == 0 and "Edwin VanCleef" in ids(dm.bosses)
    assert 36 in [d.id for d in ids(Atlas.Dungeons(0))]
    assert any(f.name.startswith("Stormwind") for f in ids(Atlas.FlightPoints(0)))

    # NPCs, items, quests (QuestieDB-derived, gitignored).
    if Atlas.Data.Npcs is None:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    assert ids(Atlas.Find("npc", "hogger"))[0] == 448 and Atlas.Npc(448).spawns[0][1] > 0
    # Find's first use per kind steps every 128 names indexed, and every 128 looked at (a Job spreads it).
    steps = L.eval("""function(A)
        local n, rows = 0, 0
        for _ in pairs(A.Data.Objects) do rows = rows + 1 end
        A.Find("object", "mailbox", 1, function() n = n + 1 end)
        return n, math.floor(rows / 128)
    end""")
    n, per_pass = steps(Atlas)
    assert n == 2 * per_pass
    assert (Atlas.BlipService("Innkeeper Farley"), Atlas.BlipService("Mailbox"), Atlas.BlipService("Hogger")) == (
        "innkeeper", "mailbox", None)
    sources = Atlas.QuestSources(33)[1]
    assert (sources.kind, sources.id) == ("item", 750)
    drops = {s.id for s in ids(sources.sources) if s.kind == "npc"}
    assert drops and drops >= set(ids(Atlas.Item(750).npcDrops))
    near = Atlas.SpawnsIn("npc", 0, 31.8, 49.6, 32.1, 49.9)
    assert 295 in [s.id for s in ids(near)]
    assert "innkeeper" in ids(Atlas.Npc(295).services)


def test_data_is_not_global_and_formats_agree():
    from mmtools.luaout import FORMATS
    L, Atlas = load_atlas()
    assert not [k for k in L.globals() if str(k).startswith("MagicMap")]  # no data globals (spike-bugs E1)
    assert dict(Atlas.FORMATS.items()) == FORMATS  # atlas/Coords.lua and tools/mmtools/luaout.py
    assert all(Atlas.Data.formats[name] == f for name, f in FORMATS.items() if Atlas.Data[name] is not None)


def test_stale_format_is_one_error_and_dropped():
    """A Data file of another format: one error naming it, then Atlas answers as if it were missing."""
    import os
    from lupa import lua51
    from atlas_lua import ROOT, files
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    run = L.eval("function(src, name, ns) local f = assert(loadstring(src, name)); local ok, err = pcall(f, 'MagicMap', ns); return ok, err or '' end")
    ns, errors = L.table(), []
    for rel in files():
        if rel.startswith("Data/") and rel not in ("Data/UiMaps.lua", "Data/Areas.lua"):
            continue
        with open(os.path.join(ROOT, rel), "rb") as f:
            ok, err = run(f.read(), "@" + rel, ns)
        if not ok:
            errors.append(err)
        if rel == "Data/UiMaps.lua":
            ns.Data.formats.UiMaps = 0
    assert errors == ["MagicMap: Data/UiMaps.lua is format 0, Atlas reads 1: regenerate (README, tools/gen_*.py)"]
    Atlas = ns.Atlas
    assert Atlas.UiMap(1429) is None and Atlas.Continent(0) is None and len(Atlas.Zones(0)) == 0
    assert Atlas.Area(12).name == "Elwynn Forest" and Atlas.Dungeon(36) is None and Atlas.Npc(448) is None
    # No QuestieDB-derived data: empty answers, not errors.
    assert len(Atlas.QuestSources(33)) == 0 and len(Atlas.Find("npc", "hogger")) == 0
    assert Atlas.BlipService("Mailbox") is None and len(Atlas.Rares(0)) == 0 and len(Atlas.SpawnsIn("npc", 0, 31, 49, 33, 50)) == 0


def test_labels_golden():
    """Atlas.Labels, a lookup into Data/Labels.lua (tools/gen_labels.py), against the golden: what it
    ranked at first use before M1.1, every inst. Same names, tiers and ids in the same order; col, row
    and size within 0.01. UPDATE_GOLDEN=1 pytest tools/tests to accept a change."""
    L, Atlas = load_atlas()
    got = [[inst, a.rank, a.tier, a.text, a.col, a.row, a.size, a.areaID, a.poiID]
           for inst in sorted(Atlas.Data.Labels.keys()) for a in ids(Atlas.Labels(inst))]
    cell = lambda v: "" if v is None else str(v)  # noqa: E731
    if os.environ.get("UPDATE_GOLDEN"):
        with open(LABELS, "w", encoding="utf-8", newline="\n") as f:
            f.writelines("\t".join(map(cell, r)) + "\n" for r in got)
    with open(LABELS, encoding="utf-8") as f:
        want = [line.rstrip("\n").split("\t") for line in f]
    assert len(got) == len(want)
    for g, w in zip(got, want):
        assert [cell(g[i]) for i in (0, 1, 2, 3, 7, 8)] == [w[i] for i in (0, 1, 2, 3, 7, 8)], w
        for i in (4, 5, 6):  # col, row, size
            assert (g[i] is None) == (w[i] == "") and (g[i] is None or abs(g[i] - float(w[i])) <= 0.01), (g, w)

"""Smoke test: Atlas loads in Lua 5.1 over the real data and its facts hold end to end."""
import pytest

from atlas_lua import load_atlas


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

    # Places.
    dm = Atlas.Dungeon(36)
    assert dm.name == "Deadmines" and dm.entranceInst == 0 and "Edwin VanCleef" in ids(dm.bosses)
    assert 36 in [d.id for d in ids(Atlas.Dungeons(0))]
    assert any(f.name.startswith("Stormwind") for f in ids(Atlas.FlightPoints(0)))

    # NPCs, items, quests (QuestieDB-derived, gitignored).
    if L.globals().MagicMap_Npcs is None:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    hogger = ids(Atlas.NpcsByName("Hogger"))
    assert hogger == [448] and Atlas.Npc(448).spawns[0][1] > 0
    assert ids(Atlas.Find("npc", "hogger"))[0] == 448
    sources = Atlas.QuestSources(33)[1]
    assert (sources.kind, sources.id) == ("item", 750)
    drops = {s.id for s in ids(sources.sources) if s.kind == "npc"}
    assert drops and drops >= set(ids(Atlas.Item(750).npcDrops))
    near = Atlas.SpawnsIn("npc", 0, 31.8, 49.6, 32.1, 49.9)
    assert 295 in [s.id for s in ids(near)]
    assert "innkeeper" in ids(Atlas.Npc(295).services)

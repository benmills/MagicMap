"""The web demo's server answers from Atlas over its bundled data, on its one map (demo/README.md)."""
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "demo"))

import server  # noqa: E402


def test_world_places_each_map():
    """Elwynn on the world is Elwynn; a zone's fit and a world tile's key land on it; every row stays a key's."""
    dx, dy = server.OFFSET[0]
    a = server.at({"col": str(32.378 + dx), "row": str(49.024 + dy)})
    assert a["zone"]["name"] == "Elwynn Forest" and a["zone"]["mapID"] == 1429 and a["walk"]["class"] == 1
    assert server.at({"col": "40", "row": "50"})["zone"]["name"] == "Tanaris"
    cam = server.fit({"uiMapID": "1429", "w": "800", "h": "600"})["cam"]
    assert 32 + dx < cam["cx"] < 34 + dx and 48 + dy < cam["cy"] < 50 + dy
    m = server.maps({})
    assert {p["inst"] for p in m["parts"]} == {0, 1, 2991} and 0 <= m["bounds"][1] and m["bounds"][3] <= 64
    keys = [t["key"] for t in server.tiles({})["tiles"]]
    assert len(keys) == len(set(keys))
    capitals = {l["text"] for l in server.labels({})["labels"] if l["tier"] == "zone"}
    assert {"Stormwind", "Ironforge", "Undercity", "Orgrimmar", "Thunder Bluff", "Darnassus"} <= capitals


def test_find_npc_and_quest_sources():
    if server.Atlas.Data.Npcs is None:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    hogger = next(r for r in server.find({"q": "hogger"}) if r["kind"] == "npc")
    spawns = server.npc({"id": str(hogger["id"])})["spawns"][0]
    assert spawns["inst"] == server.WORLD and server.to_real(*spawns["points"][0])[0] == 0
    meat = next(o for o in server.quest({"id": "33"})["objectives"] if o["kind"] == "item")
    assert {"kind": "npc", "id": 299, "name": "Young Wolf"} in meat["sources"]

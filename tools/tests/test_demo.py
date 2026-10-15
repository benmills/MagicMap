"""The web demo's server answers from Atlas over its bundled data."""
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "demo"))

import server  # noqa: E402


def test_at_elwynn():
    assert server.Atlas.Continent(0) == 1415 and server.Atlas.Continent(1) == 1414
    a = server.at({"inst": "0", "col": "32.378", "row": "49.024"})
    assert a["zone"]["name"] == "Elwynn Forest" and a["zone"]["mapID"] == 1429
    assert a["walk"]["class"] == 1


def test_find_npc_and_quest_sources():
    if server.Atlas.Data.Npcs is None:
        pytest.skip("no QuestieDB-derived data (tools/gen_questie.py)")
    hogger = next(r for r in server.find({"q": "hogger"}) if r["kind"] == "npc")
    assert server.npc({"id": str(hogger["id"])})["spawns"][0]["inst"] == 0
    meat = next(o for o in server.quest({"id": "33"})["objectives"] if o["kind"] == "item")
    assert {"kind": "npc", "id": 299, "name": "Young Wolf"} in meat["sources"]

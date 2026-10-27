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


def test_review_marks_round_trip(tmp_path, monkeypatch):
    """The map review (demo/review_api.py): a mark is saved, logged and read back; a bad one is refused."""
    import json

    import review_api as R
    monkeypatch.setattr(R, "STORE", str(tmp_path / "decisions.json"))

    def post(d, h={}):
        return R.handle("POST", "/api/review", json.dumps(d).encode(), h)
    assert post({"id": "flat-land:0:39,25", "status": "later", "note": " north rim ", "by": "ben"})[0] == 200
    assert post({"id": "flat-land:0:39,25", "status": "accepted", "note": "north rim"})[0] == 200
    assert post({"id": "seam:0:1", "status": "maybe"})[0] == 400
    doc = json.loads(R.handle("GET", "/api/review", b"", {})[1])
    assert doc["decisions"]["flat-land:0:39,25"]["status"] == "accepted" and len(doc["log"]) == 2
    assert doc["log"][0]["note"] == "north rim"
    assert post({"id": "flat-land:0:39,25", "status": None})[0] == 200  # back to open, no note: unmarked
    assert "flat-land:0:39,25" not in json.loads(R.handle("GET", "/api/review", b"", {})[1])["decisions"]
    monkeypatch.setattr(R, "TOKEN", "s3cret")
    assert post({"id": "seam:0:1", "status": "later"})[0] == 401
    assert post({"id": "seam:0:1", "status": "later"}, {"X-Review-Token": "s3cret"})[0] == 200
    assert json.loads(R.handle("GET", "/api/lint", b"", {})[1])["schema"] == 1

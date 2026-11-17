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


ROUTE_KEYS = {"v", "label", "api", "map", "way", "found", "partial", "capped", "nodes", "maxNodes", "ms", "yards", "straight",
              "ratio", "regions", "snapped", "box", "closed", "raw", "turns", "instead", "abstract", "nodes2", "closed2"}


def test_route_tool():
    """/api/route runs the addon's own search, 3.1.1's walk (v=311, demo/walk311), main's before v2 (v=31,
    demo/walk31) or the tree's (v=2), in one shape: Goldshire to Lakeshire is found, a little longer than straight,
    its trace world points; the two continents never share a route."""
    dx, dy = server.OFFSET[0]
    q = {"c0": str(31.95 + dx), "r0": str(49.75 + dy), "c1": str(36.09 + dx), "r1": str(49.28 + dy)}
    for v in ("311", "31", "2"):
        r = server.route(dict(q, v=v))
        assert "error" not in r, r["error"]
        assert set(r) == ROUTE_KEYS and r["v"] == v and r["map"] == "Eastern Kingdoms"
        assert r["way"][0] == [31.95 + dx, 49.75 + dy] and len(r["snapped"]) == 2
        assert all(len(p) == 2 for k in ("closed", "raw", "turns") for p in r[k])
        if v == "31":
            assert r["found"] and not r["partial"] and 1 < r["ratio"] < 1.3 and r["nodes"] == len(r["closed"])
            assert r["raw"][0] == r["snapped"][0]
    assert server.route(q)["v"] == "2"
    assert "error" in server.route({"c0": "40", "r0": "30", "c1": str(32 + dx), "r1": str(49 + dy)})


def test_route_regions_and_links():
    """3.1's walk: Dun Morogh's only ways out are tunnels (tools/walk_links.json): Kharanos to Thelsamar goes through
    one. Into Teldrassil (its own region: boats, not a walk) no search runs: the nearest place in yours, at once."""
    dx, dy = server.OFFSET[0]
    r = server.route({"v": "31", "c0": str(32.91 + dx), "r0": str(42.41 + dy), "c1": str(36.85 + dx), "r1": str(42.95 + dy)})
    assert r["found"] and not r["partial"] and r["regions"] is None
    A = server.Atlas
    anchors = A.Anchors(1)
    dol = next(anchors[i] for i in range(1, len(anchors) + 1) if A.Area(anchors[i][1]) and A.Area(anchors[i][1]).name == "Dolanaar")
    r = server.route({"v": "31", "c0": "29.0", "r0": "16.0", "c1": str(dol[2]), "r1": str(dol[3])})
    assert r["regions"] and r["regions"][0] != r["regions"][1] and (r["partial"] or not r["found"])
    assert r["nodes"] < 20000


def test_walk_layer():
    """/api/walk answers on either side: 3.1's cells, or v2's parts graph once the tree's atlas has it."""
    dx, dy = server.OFFSET[0]
    c, r = (32 + dx) * 16, (49 + dy) * 16
    q = {"c0": str(c), "r0": str(r), "c1": str(c + 8), "r1": str(r + 8)}
    w = server.walk(dict(q, v="31"))
    assert w["api"] == "3.1" and len(w["rows"]) == 8 and len(w["rows"][0]) == 8
    w = server.walk(q)
    assert "error" not in w, w["error"]
    assert w["v"] == "2" and len(w["rows"]) == 8 and ("nodes" in w) == (w["api"] == "2")


def test_routes_page_cases():
    """The Routes page's data (/api/cases): every grid case, run now on the previous walk and the new one."""
    d = server.cases({})
    assert [s["v"] for s in d["sides"]] == ["311", "2"] and len(d["cases"]) >= 6
    for c in d["cases"]:
        assert {(r["dir"], r["v"]) for r in c["runs"]} >= {("ab", "311"), ("ab", "2")}
        assert all(r["error"] is None for r in c["runs"]), c["name"]

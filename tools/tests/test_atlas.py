"""Smoke test: Atlas loads in Lua 5.1 and its facts hold end to end."""
from atlas_lua import load_atlas

Y = 1600 / 3  # yards per tile

# A fake continent over Eastern Kingdoms tiles 28..36 x 30..38, split into
# two zones down the middle, with a micro map inside the west one.
RECTS = {1: (28, 30, 36, 38), 2: (28, 30, 32, 38), 3: (32, 30, 36, 38), 4: (29, 31, 30, 32)}
INFO = {1: ("Testland", 2), 2: ("Westshire", 3), 3: ("Eastvale", 3), 4: ("Cave", 5)}


def world_pos(map_id, x, y):
    if map_id not in RECTS:
        return None
    c0, r0, c1, r1 = RECTS[map_id]
    col, row = c0 + (c1 - c0) * x, r0 + (r1 - r0) * y
    return 0, (32 - row) * Y, (32 - col) * Y


READERS = {
    "GetMapInfo": lambda m: {"name": INFO[m][0], "mapType": INFO[m][1], "parentMapID": 1} if m in INFO else None,
    "GetWorldPosFromMapPos": world_pos,
    "GetMapInfoAtPosition": lambda m, x, y: ({"mapID": 2, "name": "Westshire"} if x < 0.5
                                             else {"mapID": 3, "name": "Eastvale"}) if m == 1 else None,
}


def test_atlas():
    L, Atlas = load_atlas(READERS)

    # Tiles: Eastern Kingdoms is there, with a FileDataID per tile.
    assert Atlas.Maps()[1].name == "Eastern Kingdoms"
    c0, r0, c1, r1 = Atlas.TileBounds(0)
    assert c0 < 32 < c1 and r0 < 32 < r1
    key = next(iter(Atlas.Tiles(0).keys()))
    assert Atlas.TileInfo(0, key).fdid == Atlas.Tiles(0)[key]

    # Coordinates round-trip.
    col, row = Atlas.WorldToTile(*Atlas.TileToWorld(31.25, 40.5))
    assert abs(col - 31.25) < 1e-9 and abs(row - 40.5) < 1e-9

    # Walk: somewhere on Eastern Kingdoms you can stand, and from there step.
    walk, found = Atlas.Walk, None
    for k in Atlas.Tiles(0).keys():
        gc, gr = (k // 64) * 16 + 8, (k % 64) * 16 + 8
        if walk.Cell(0, gc, gr)[0] == 1:
            found = gc, gr
            break
    assert found
    assert walk.Snap(0, *found) == found
    assert any(walk.CanMove(0, *found, dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    assert walk.Cell(0, -1, -1)[0] == 0

    # Catalogue from the stub readers.
    assert Atlas.Continent(0) == 1
    assert [z.name for z in Atlas.Zones(0).values()] == ["Eastvale", "Westshire"]
    assert sorted(Atlas.QuestMaps(0).values()) == [2, 3, 4]
    inst, col, row = Atlas.MapToTile(2, 0.5, 0.5)
    assert (inst, col, row) == (0, 30, 34)
    z = Atlas.ZoneAt(0, 30.1, 34.1)
    assert z.name == "Westshire" and z.mapID == 2 and abs(z.x - 0.525) < 1e-9
    assert Atlas.ZoneAt(0, 34, 34).name == "Eastvale"
    assert Atlas.ZoneAt(0, 10, 10) is None

    # Camera: fit a box, and zooming keeps the point under the cursor.
    cx, cy, zoom = Atlas.Camera.Fit(28, 30, 36, 38, 800, 400, 1, 16, 800)
    assert (cx, cy, zoom) == (32, 34, 50)
    cam = L.table_from({"cx": cx, "cy": cy, "zoom": zoom})
    before = Atlas.Camera.ScreenToTile(cam, 800, 400, 100, 50)
    after = Atlas.Camera.ScreenToTile(Atlas.Camera.ZoomAt(cam, 800, 400, 100, 50, 200), 800, 400, 100, 50)
    assert all(abs(a - b) < 1e-9 for a, b in zip(before, after))

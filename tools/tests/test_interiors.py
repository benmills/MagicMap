"""Atlas's interiors over the committed Data/Interiors.lua: Ironforge's rooms and pictures, and the rooms
under a spot in the Great Forge (the prototype's, proven in game: docs/decisions/0008-interiors.md)."""
from atlas_lua import load_atlas


def test_ironforge():
    L, Atlas = load_atlas()
    keys = list(Atlas.BuildingsAt(0, 33.997, 41.063).values())
    b = next(b for b in (Atlas.Building(0, k) for k in keys) if b.fid == 7801267)
    assert b.wmo == 20884
    rooms = dict(b.rooms.items())
    assert len(rooms) == 103 and sum(len(r.pics) for r in rooms.values()) == 108
    assert list(Atlas.RoomsAt(b, 33.997, 41.063).values()) == [65, 88]
    assert (rooms[65].area, rooms[88].area) == ("The Great Forge", "The High Seat")

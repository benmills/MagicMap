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


def test_ironforge_rooms():
    """Game's room tracking (game/parts/Interior.lua) on the Forge floor: the subzone picks the room of
    the two whose masks cover you, the High Seat's name moves you to it and back; out of every mask,
    the room's kept a while, then after 2 s, no building. /mm indoor prints each change."""
    from test_addon import boot, errors
    L, sim, ns = boot()
    sim.player.inst, sim.player.col, sim.player.row, sim.floorPlan = 0, 33.997, 41.063, True  # (mountable)

    def at(sub, s=0.2):
        sim.subzone = sub
        sim.FireEvent("ZONE_CHANGED_INDOORS")
        sim.Run(s)
        i = ns.Model.interior
        return i and (i.room, list(i.rooms.values()))

    sim.Slash("/mm indoor")
    assert at("The Great Forge") == (65, [65]) and ns.Model.minimap.indoors
    b = ns.Model.interior
    assert ns.Atlas.Building(0, b.building).fid == 7801267 and b.floor == ns.Atlas.Building(0, b.building).rooms[65].zmin
    assert "room 65 (The Great Forge), candidates {65}" in sim.prints[len(sim.prints)]
    assert at("The High Seat") == (88, [88])
    assert at("The Great Forge") == (65, [65])
    sim.player.col = 33.6  # out of every mask (still the Minimap's indoor view)
    sim.Run(1.5)
    assert ns.Model.interior.room == 65
    sim.Run(1.5)
    assert ns.Model.interior is False and "no building" in sim.prints[len(sim.prints)]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

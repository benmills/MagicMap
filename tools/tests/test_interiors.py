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
    the two whose masks cover you, the High Seat's name moves you to it and back, no subzone keeps it; out of every mask,
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
    sim.player.col, sim.player.row = 33.9166, 40.9465  # under 65 and unnamed 103 (floor -140)
    assert at("") == (65, [65])  # no subzone names none: the room kept (Test.lua's "")
    sim.player.col = 33.6  # out of every mask (still the Minimap's indoor view)
    sim.Run(1.5)
    assert ns.Model.interior.room == 65
    sim.Run(1.5)
    assert ns.Model.interior is False and "no building" in sim.prints[len(sim.prints)]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_ironforge_drawn():
    """UI's interiors layer (ui/Interiors.lua) in the Forge: Ironforge's pictures over the tiles, veiled to
    x0.35, the Forge's on top, the lower bridge (room 90) on its level, the upper (96: 60 yd above) ghosted, the
    deep room under the city (103) faded; under "The High Seat" (its floor 2.6 yd lower) both bridges ghosted, the
    Forge on its level and room 88 on top; out of the building, nothing drawn. Entering is within the frame budget, priced."""
    from test_addon import boot, errors
    from test_ground import layer
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
    sim.Run(3)
    S, lay = sim.state, layer(ns, "interiors")
    perf, whole = ns.Runtime.Perf()[0]["map: interiors"], ns.Runtime.Perf()[0]["runtime: frame"]
    sim.player.inst, sim.player.col, sim.player.row, sim.floorPlan = 0, 33.997, 41.063, True

    def at(sub, s=1):
        sim.subzone = sub
        sim.FireEvent("ZONE_CHANGED_INDOORS")
        sim.Run(s)
        c = lay.front
        if not lay.on or not c or c.alpha == 0:
            return None
        b = ns.Atlas.Building(0, ns.Model.interior.building)
        room = {}  # a picture's fid -> its room
        for r, v in b.rooms.items():
            for p in v.pics.values():
                room[p[1]] = r
        veil = S[c.pools.veil[1]]
        pics = [S[c.pools.pic[i]] for i in range(1, c.pools.pic.n + 1)]
        alpha = {}  # a room drawn -> its pictures' alpha
        for p in pics:
            alpha[room[p.texture]] = p.alpha
        return veil.color[4], alpha, {room[p.texture] for p in pics if p.sublevel == 7}

    sim.Price(True)
    perf.max = whole.max = 0
    veil, rooms, top = at("The Great Forge")
    sim.Price(False)
    print(f"the Forge: {len(rooms)} rooms drawn; its layout's slowest frame {perf.max:.2f} ms, the slowest frame {whole.max:.2f}")
    assert abs(veil - 0.65) < 1e-9 and top == {65} and rooms[65] == rooms[88] == rooms[90] == 1
    assert rooms[96] == 0.15 and rooms[103] == 0.35
    assert perf.max <= 4.5 and whole.max <= 8
    veil, rooms, top = at("The High Seat")
    assert top == {88} and rooms[90] == rooms[96] == 0.15 and rooms[65] == 1
    sim.player.col = 33.6
    assert at("", 3) is None and ns.Model.interior is False
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

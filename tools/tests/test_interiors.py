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
    # Real floors (world height: the placement's 506.7 up): the Commons ring's box reaches -91, its floor -5.
    assert abs(rooms[8].floor - 501.7) < 2 and abs(rooms[101].floor - 506.7 + 48.5) < 2 and rooms[8].zmin == -91
    assert 9 in rooms[8].over.values() and rooms[8].underground


def test_cities():
    """The capitals' buildings: Ironforge's has it; Orgrimmar's more than one (the Cleft of Shadow is rooms of
    its own); Undercity's rooms under the ruins underground."""
    L, Atlas = load_atlas()
    assert 7706 in Atlas.City(0, 1455).buildings.values()
    org = list(Atlas.City(1, 1454).buildings.values())
    assert len(org) > 1 and any(r.area == "Cleft of Shadow" for r in Atlas.Building(1, 165042).rooms.values())
    uc = Atlas.City(0, 1458)
    assert any(r.underground for k in uc.buildings.values() for r in Atlas.Building(0, k).rooms.values())


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
    assert ns.Atlas.Building(0, b.building).fid == 7801267 and b.floor == ns.Atlas.Building(0, b.building).rooms[65].floor
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
    """UI's interiors layer (ui/Interiors.lua) in Ironforge (city maps on: its three buildings), levels by real
    floors: in the Forge its pictures over the tiles, veiled to x0.35, the Forge's on top, the lower bridge
    (room 90) on its level, the upper (96: 42 yd above) ghosted, the deep room under the city (103) faded; under
    "The High Seat" room 88 on top, the Forge and the lower bridge on its level; in the Commons ring (room 8: its
    box reaches 91 yd down, its floor the street's) every room on its level whole, the rest faded or ghosted only
    for overlapping one on it; out of the building, nothing drawn. Entering is within the frame budget, priced."""
    from test_addon import boot, errors
    from test_ground import layer
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
    sim.Run(3)
    S, lay = sim.state, layer(ns, "interiors")
    perf, whole = ns.Runtime.Perf()[0]["map: interiors"], ns.Runtime.Perf()[0]["runtime: frame"]
    sim.player.inst, sim.player.col, sim.player.row, sim.floorPlan = 0, 33.997, 41.063, True
    IF = 7706

    def at(sub, s=1):
        sim.subzone = sub
        sim.FireEvent("ZONE_CHANGED_INDOORS")
        sim.Run(s)
        c = lay.front
        if not lay.on or not c or c.alpha == 0:
            return None
        pool, alpha, top = c.pools.pic, {}, set()
        for i in range(1, pool.n + 1):
            p, t = pool["keys"][i], S[pool[i]]
            alpha[(p.key, p.room)] = t.alpha
            if t.sublevel == 7:
                top.add((p.key, p.room))
        veil = c.pools.veil and c.pools.veil.n > 0 and S[c.pools.veil[1]].color[4]
        return veil, {r: a for (k, r), a in alpha.items() if k == IF}, {r for k, r in top if k == IF}, alpha

    sim.Price(True)
    perf.max = whole.max = 0
    veil, rooms, top, every = at("The Great Forge")
    sim.Price(False)
    print(f"the Forge: {len(every)} rooms drawn; its layout's slowest frame {perf.max:.2f} ms, the slowest frame {whole.max:.2f}")
    assert abs(veil - 0.65) < 1e-9 and top == {65} and rooms[65] == rooms[88] == rooms[90] == 1
    assert rooms[96] == 0.15 and rooms[103] == 0.35 and len({k for k, _ in every}) > 1
    assert perf.max <= 5 and whole.max <= 8  # a slice within the moving budget, the frame within the max
    veil, rooms, top, _ = at("The High Seat")
    assert top == {88} and rooms[65] == rooms[90] == 1 and rooms[96] == 0.15
    sim.player.col, sim.player.row = 34.0638, 41.3248  # the Commons ring, under room 8 alone
    veil, rooms, top, _ = at("Ironforge")
    b = ns.Atlas.Building(0, IF)
    floor = b.rooms[8].floor
    assert ns.Model.interior.room == 8 and ns.Model.interior.floor == floor and top == {8}
    on = {r for r in rooms if abs(b.rooms[r].floor - floor) <= 22}
    assert all(rooms[r] == 1 for r in on)
    for r, a in rooms.items():
        assert a == 1 or r not in on and set(b.rooms[r].over.values()) & on, (r, a)
    sim.player.col = 33.6  # out of the building, still in the city: undimmed, its rooms (all underground) faded
    veil, rooms, top, _ = at("", 3)
    assert ns.Model.interior is False and not veil and not top and set(rooms.values()) == {0.35}
    ns.UI.Engine.SetLayer("cities", False)
    assert at("") is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_city_maps():
    """Orgrimmar outdoors (no building: the Minimap's outdoor view): with City maps on, the city's buildings
    drawn over undimmed tiles, the Cleft of Shadow's rooms among them, the rooms under the ground faded; off,
    nothing drawn. Entering is within the frame budget, priced."""
    from test_addon import boot, errors
    from test_ground import layer, look
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
    sim.Run(3)
    S, lay = sim.state, layer(ns, "interiors")
    perf, whole = ns.Runtime.Perf()[0]["map: interiors"], ns.Runtime.Perf()[0]["runtime: frame"]
    sim.player.inst, sim.player.col, sim.player.row = 1, 40.15, 28.65  # beside the Cleft of Shadow
    sim.FireEvent("ZONE_CHANGED_NEW_AREA")

    def drawn():
        c = lay.front
        if not lay.on or not c or c.alpha == 0:
            return None
        pool = c.pools.pic
        return (c.pools.veil and c.pools.veil.n or 0), {(pool["keys"][i].key, pool["keys"][i].room): S[pool[i]].alpha for i in range(1, pool.n + 1)}

    sim.Price(True)
    perf.max = whole.max = 0
    sim.Run(2)
    sim.Price(False)
    assert ns.Model.you.uiMap == 1454 and not ns.Model.interior
    veils, rooms = drawn()
    print(f"Orgrimmar: {len(rooms)} rooms drawn; its layout's slowest frame {perf.max:.2f} ms, the slowest frame {whole.max:.2f}")
    assert veils == 0 and all((165042, r) in rooms for r in (74, 75, 137))
    org = ns.Atlas.Building(1, 165042)
    assert all(a == (0.35 if org.rooms[r].underground else 1) for (k, r), a in rooms.items() if k == 165042)
    assert perf.max <= 5 and whole.max <= 8  # a slice within the moving budget, the frame within the max
    look(sim, ns, (40.9, 29.2), ns.UI.Camera.cam.zoom)  # the rooms under the city's east edge
    assert all(a == 0.35 for (k, _), a in drawn()[1].items() if k == 250582) and any(k == 250582 for k, _ in drawn()[1])
    ns.UI.Engine.SetLayer("cities", False)
    sim.Run(1)
    assert drawn() is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

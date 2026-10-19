"""Game's places, group, vignettes, explored and tracking parts and the tracking Command, round trips on the
sim (docs/v1-plan.md M4.1): what the client says reaches obs.places, obs.group, obs.vignettes, obs.explored
and obs.tracking (game/parts/), read when it may have changed, a new table only when something did; the
tracking Command (game/commands/tracking.lua) comes back in the client and in the same frame's
observation. And the observe step with every part on holds its 2 ms, our Lua charged. The vignette read
that throws, or finds no position, is R-E2 (replays/R-E2.lua)."""
import math

from sim import py
from test_addon import boot, errors

ELWYNN, EK, WESTFALL = 1429, 1415, 1436
CELL, SAMPLES = 0.2, 700  # game/parts/Explored.lua
FANG = "Creature-0-4395-0-1519-471-000048D2F1"


def client(**kw):
    L, sim, ns = boot(**kw)
    sim.Run(0.1)
    return L, sim, ns, L.eval("rawequal")


def counter(L, path):
    """Wraps the Lua function at path (a global's field: "C_TaxiMap.GetTaxiNodesForMap") to count its calls:
    a reader of the count so far."""
    return L.eval(f"""function()
        local fn, n = {path}, 0
        {path} = function(...) n = n + 1; return fn(...) end
        return function() return n end
    end""")()


def test_places_round_trip():
    L, sim, ns, held = client()
    sim.Slash("/mma toggle")  # (hidden, held: read once it's shown)
    sim.Step()
    places = ns.Game.obs.places
    assert [p.key for p in places.values()] == ["flight:2", "dungeon:63", "graveyard:1", "poi:501"]
    flight, dungeon, grave, poi = places.values()
    # A place on the continent's map and a zone's: once, where the first (the continent's) has it.
    inst, col, row = ns.Atlas.MapToTile(EK, 0.3, 0.1)
    assert (flight.pos.inst, flight.pos.col, flight.pos.row) == (inst, col, row)
    assert (flight.kind, flight.name, flight.faction, flight.known, flight.icon.atlas) == (
        "flight", "Stormwind, Elwynn", "A", None, "TaxiNode_Alliance")
    assert (dungeon.text, dungeon.icon.atlas, grave.icon.atlas, poi.name, poi.text) == (
        "A dungeon", "Dungeon", "poi-graveyard-neutral", "Lion's Pride Inn", "An inn")
    asked = counter(L, "C_TaxiMap.GetTaxiNodesForMap")
    sim.Run(1)
    assert held(ns.Game.obs.places, places) and asked() == 0  # nothing new: not asked again

    # A flight master opened: one known, one learned of. Read 0.3 s on; the rest kept.
    L.execute("""
        local nodes = C_TaxiMap.GetTaxiNodesForMap
        C_TaxiMap.GetTaxiNodesForMap = function(id)
            local out = nodes(id)
            for _, n in ipairs(out) do n.isUndiscovered = false end
            if id == 1429 then
                out[#out + 1] = { nodeID = 5, name = "Lakeshire, Redridge", position = CreateVector2D(0.9, 0.5),
                    atlasName = "TaxiNode_Neutral", faction = 0, isUndiscovered = true }
            end
            return out
        end""")
    sim.FireEvent("TAXIMAP_OPENED")
    sim.Run(0.2)
    assert held(ns.Game.obs.places, places)
    sim.Run(0.2)
    now = ns.Game.obs.places
    assert [p.key for p in now.values()] == ["flight:2", "flight:5", "dungeon:63", "graveyard:1", "poi:501"]
    assert (now[1].known, now[2].known, now[2].faction) == (True, False, None)
    assert all(held(now[i + 1], p) for i, p in ((2, dungeon), (3, grave), (4, poi)))

    # Their events, nothing changed: the same list.
    for event in ("AREA_POIS_UPDATED", "PLAYER_DEAD", "PLAYER_ALIVE", "TAXIMAP_OPENED"):
        sim.FireEvent(event)
    sim.Run(0.5)
    assert held(ns.Game.obs.places, now)

    # Another instance shown: its places (none the sim's client has on Kalimdor); hidden, held.
    sim.Slash("/mma map 1")
    sim.Run(0.5)
    kalimdor = ns.Game.obs.places
    assert py(kalimdor) == {} and not held(kalimdor, now)
    sim.Slash("/mma toggle")
    sim.FireEvent("AREA_POIS_UPDATED")
    sim.FireEvent("TAXIMAP_OPENED")
    sim.Run(1)
    assert ns.Game.shownInst is False and held(ns.Game.obs.places, kalimdor)
    assert not errors(sim, ns), errors(sim, ns)


def party(L, sim, members):
    """Sim.group from { unit: { name, class, level, guid, col, row, dead } }."""
    for unit, m in members.items():
        sim.units[unit] = L.table_from(m)
    sim.group = L.table_from(list(members))


def test_group():
    L, sim, ns, held = client()
    group = ns.Game.obs.group
    assert py(group) == {}  # in none: known and empty
    party(L, sim, {
        "party1": {"name": "Brannock", "class": "WARRIOR", "level": 9, "guid": "Player-4395-0A1B2C3D", "col": 31.96, "row": 49.77},
        "party2": {"name": "Elandra", "class": "PRIEST", "level": 8, "guid": "Player-4395-0A1B2C3E", "col": 31.94, "row": 49.76},
    })
    sim.Step(1 / 60)
    sim.Step(1 / 60)
    sim.Step(1 / 60)
    got = ns.Game.obs.group
    assert held(got, group)  # per frame: the same table, refilled
    one, two = got.values()
    assert (one.id, one.name, one["class"], one.level, one.dead) == (
        "Player-4395-0A1B2C3D", "Brannock", "WARRIOR", 9, False)
    assert (two.name, two["class"]) == ("Elandra", "PRIEST")
    assert one.pos.inst == 0 and abs(one.pos.col - 31.96) < 1e-9 and abs(one.pos.row - 49.77) < 1e-9

    # 20 a second; the same tables between.
    positions = L.eval("""function()
        local up, n = UnitPosition, 0
        UnitPosition = function(unit) if unit ~= "player" then n = n + 1 end return up(unit) end
        return function() return n end
    end""")()
    pos = one.pos
    sim.Run(1)
    assert 38 <= positions() <= 42, positions()  # 2 members, 20 reads
    assert held(ns.Game.obs.group[1], one) and held(ns.Game.obs.group[1].pos, pos)

    # Walking, dead; withheld (an instance's, nil) and a secret value: no position.
    sim.units.party1.col, sim.units.party1.dead = 31.98, True
    L.execute("""
        local up = UnitPosition
        UnitPosition = function(unit)
            if unit == "party2" then return GetUnitSpeed(unit), 0, 0, 0 end -- (a secret value)
            return up(unit)
        end""")
    sim.Run(0.1)
    assert abs(one.pos.col - 31.98) < 1e-9 and one.dead is True and two.pos is None
    sim.units.party1.col = None
    sim.Run(0.1)
    assert one.pos is None and one.name == "Brannock"

    # The group left: known and empty, the same table.
    sim.group = L.table_from([])
    sim.Run(0.1)
    assert held(ns.Game.obs.group, group) and py(group) == {}
    assert not errors(sim, ns), errors(sim, ns)


def test_vignettes():
    L, sim, ns, held = client()
    first = ns.Game.obs.vignettes
    v = first[1]
    assert (v.id, v.name, v.rare, v.npcID, v.icon.atlas, v.target) == ("Vignette-0-1", "Mother Fang", False, None,
                                                                      "VignetteKill", None)
    assert (v.pos.inst, v.pos.col, v.pos.row) == ns.Atlas.MapToTile(ELWYNN, 0.38, 0.79)

    # A rare's art, the creature's GUID: a rare, its NPC. A burst of events reads once, 0.3 s on.
    sim.vignetteAtlas = "VignetteKillElite"
    L.execute(f"""
        local info = C_VignetteInfo.GetVignetteInfo
        C_VignetteInfo.GetVignetteInfo = function(guid)
            local i = info(guid)
            i.objectGUID, i.isDead = "{FANG}", Sim.vignetteDead
            return i
        end""")
    reads = counter(L, "C_VignetteInfo.GetVignettes")
    for event in ("VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "VIGNETTE_MINIMAP_UPDATED"):
        sim.FireEvent(event)
        sim.Step()
    assert held(ns.Game.obs.vignettes, first)
    sim.Run(0.3)
    rare = ns.Game.obs.vignettes
    assert reads() == 1 and (rare[1].rare, rare[1].npcID) == (True, 471)
    sim.FireEvent("VIGNETTES_UPDATED")
    sim.Run(0.4)
    assert held(ns.Game.obs.vignettes, rare)  # nothing changed

    # Dead: gone.
    sim.vignetteDead = True
    sim.FireEvent("VIGNETTES_UPDATED")
    sim.Run(0.4)
    assert py(ns.Game.obs.vignettes) == {}

    # The rare you target: where you are then, by its NPC, while it's your target; not a player, not a common one.
    sim.units.target = L.table_from({"name": "Mother Fang", "npc": True, "classification": "rare", "guid": FANG})
    sim.FireEvent("PLAYER_TARGET_CHANGED")
    sim.Step()
    t = ns.Game.obs.vignettes[1]
    you = ns.Game.obs.you
    assert (t.id, t.name, t.rare, t.npcID, t.target) == (FANG, "Mother Fang", True, 471, True)
    assert (t.pos.inst, t.pos.col, t.pos.row) == (you.inst, you.col, you.row)
    sim.player.col = sim.player.col + 0.01
    sim.Run(0.5)
    assert held(ns.Game.obs.vignettes[1], t)  # where you were when you targeted it
    for target in ({"name": "Kobold", "npc": True}, {"name": "Brannock", "classification": "rare"}):
        sim.units.target = L.table_from(target)
        sim.FireEvent("PLAYER_TARGET_CHANGED")
        sim.Step()
        assert py(ns.Game.obs.vignettes) == {}, target

    # Another map (Westfall's: the client has none there for us), at once.
    sim.vignetteDead = False
    sim.player.col, sim.player.row = 30.5, 52.2
    sim.FireEvent("ZONE_CHANGED_NEW_AREA")
    sim.Step()
    assert ns.Game.obs.you.uiMap == WESTFALL and py(ns.Game.obs.vignettes) == {}
    assert not errors(sim, ns), errors(sim, ns)


def until_explored(sim, ns, held, was, limit=400):
    """Frames until obs.explored is a new table (not was)."""
    for n in range(1, limit + 1):
        sim.Step()
        if not held(ns.Game.obs.explored, was):
            return n
    raise AssertionError("no sweep ended")


def test_explored():
    L, sim, ns = boot()
    held = L.eval("rawequal")
    sim.unexplored = True  # nothing explored: every cell on land asked
    asks = counter(L, "C_MapExplorationInfo.GetExploredAreaIDsAtPosition")
    most, last, frames = 0, 0, 0
    while ns.Game.obs.explored is None:
        sim.Step()
        frames += 1
        most, last = max(most, asks() - last), asks()
        assert frames <= 200
    r = ns.Atlas.MapRect(EK)
    cells = math.ceil((r.col1 - r.col0) / CELL) * math.ceil((r.row1 - r.row0) / CELL)
    assert frames == math.ceil(cells / SAMPLES) and most <= SAMPLES, (frames, most)
    dark = ns.Game.obs.explored
    goldshire = ns.Atlas.AreaAt(0, 31.95, 49.75)
    got = py(dark)
    assert all(isinstance(k, int) and v is False for k, v in got.items()) and goldshire in got
    print(f"explored: Eastern Kingdoms swept in {frames} frames, {asks()} asks, {len(got)} areas")

    # Explored now (the sim's client names Goldshire everywhere): swept again, the old kept till it ends.
    sim.unexplored = False
    sim.FireEvent("MAP_EXPLORATION_UPDATED")
    n0 = asks()
    sim.Step()
    assert held(ns.Game.obs.explored, dark) and dark[goldshire] is False
    until_explored(sim, ns, held, dark)
    lit = ns.Game.obs.explored
    assert lit[87] is True and all(v is True for v in py(lit).values()) and set(py(lit)) >= set(got)
    assert asks() - n0 <= len(got)  # an area found explored isn't asked about again

    # Again: nothing left to ask, nothing new.
    n0 = asks()
    sim.FireEvent("MAP_EXPLORATION_UPDATED")
    sim.Run(3)
    assert asks() == n0 and held(ns.Game.obs.explored, lit)

    # Kalimdor shown: swept, added; an instance's map: none.
    sim.Slash("/mma toggle")
    sim.Slash("/mma map 1")
    sim.Step()
    until_explored(sim, ns, held, lit)
    both = ns.Game.obs.explored
    kalimdor = ns.Atlas.AreaAt(1, 40.5, 30.5)  # Durotar's
    assert both[kalimdor] is True and both[goldshire] is True
    n0 = asks()
    sim.Slash("/mma map 36")
    sim.Run(2)
    assert asks() == n0 and held(ns.Game.obs.explored, both)
    assert not errors(sim, ns), errors(sim, ns)


def test_tracking_round_trip():
    L, sim, ns, held = client()
    tracking = ns.Game.obs.tracking
    assert [(t.id, t.name, t.active, t.kind) for t in tracking.values()] == [
        (8, "Flight Master", True, "duplicate"), (2383, "Find Herbs", True, None), (65536, "Track Quest POIs", True, "duplicate"),
        (8192, "Points of Interest", False, "duplicate"), (64, "Mailbox", True, None), (128, "Innkeeper", True, None)]
    assert tracking[5].texture == 136459

    # Off: in the client, and in the same frame's obs (a click's: carried out in Input); the rest kept.
    sets = counter(L, "C_Minimap.SetTracking")
    ns.Game.Command(L.table_from({"kind": "tracking", "id": 2383, "on": False}))
    sim.Step()
    off = ns.Game.obs.tracking
    assert sets() == 1 and sim.tracking[2].active is False and off[2].active is False and not held(off, tracking)
    assert all(held(off[i], tracking[i]) for i in (1, 3, 4, 5, 6))
    sim.Run(0.5)  # (the client's MINIMAP_UPDATE_TRACKING: read again, the same)
    assert held(ns.Game.obs.tracking, off)
    ns.Game.Command(L.table_from({"kind": "tracking", "id": 2383, "on": False}))  # again: nothing new
    sim.Step()
    assert sets() == 1 and held(ns.Game.obs.tracking, off)
    ns.Game.Command(L.table_from({"kind": "tracking", "id": 8192, "on": True}))
    sim.Step()
    assert sim.tracking[4].active is True and ns.Game.obs.tracking[4].active is True

    # A type the client has no info for yet: left out till it has.
    L.execute("""
        local info = C_Minimap.GetTrackingInfo
        C_Minimap.GetTrackingInfo = function(i) if i ~= 6 or Sim.trackingReady then return info(i) end end""")
    sim.FireEvent("MINIMAP_UPDATE_TRACKING")
    sim.Step()
    assert [t.id for t in ns.Game.obs.tracking.values()] == [8, 2383, 65536, 8192, 64]
    sim.trackingReady = True
    sim.FireEvent("MINIMAP_UPDATE_TRACKING")
    sim.Step()
    assert [t.id for t in ns.Game.obs.tracking.values()][-1] == 128
    assert not errors(sim, ns), errors(sim, ns)


def test_observe_all_on():
    """Every part on (the map shown, the sensor, a party of 4, a live rare, a sweep of another continent),
    priced, our Lua charged: no observe over 2 ms."""
    L, sim, ns, held = client(lua=True)
    sim.Price(True)
    party(L, sim, {f"party{i}": {"name": f"Member{i}", "class": "MAGE", "guid": f"Player-1-0000000{i}",
                                 "col": 31.95 + 0.01 * i, "row": 49.75} for i in range(1, 5)})
    sim.vignetteAtlas = "VignetteKillElite"
    sim.Run(1)
    sim.Slash("/mma toggle")
    sim.Run(6)  # (past the login's and the first open's graces)
    perf = ns.Runtime.Perf()[0]
    observe, explored = perf["game.observe"], perf["game.part explored"]
    worst, sweep = 0, 0
    sim.Slash("/mma map 1")
    for _ in range(180):
        o, e = observe.ms, explored.ms
        sim.Step()
        worst, sweep = max(worst, observe.ms - o), max(sweep, explored.ms - e)
    sim.Slash("/mma map 0")
    sim.FireEvent("MAP_EXPLORATION_UPDATED")
    sim.FireEvent("VIGNETTES_UPDATED")
    sim.FireEvent("AREA_POIS_UPDATED")
    for _ in range(120):
        o = observe.ms
        sim.Step()
        worst = max(worst, observe.ms - o)
    print(f"observe all on, priced with our Lua: the slowest frame {worst:.2f} ms (the explored sweep's {sweep:.2f})")
    assert ns.Game.obs.explored is not None and len(ns.Game.obs.group) == 4 and len(ns.Game.obs.vignettes) == 1
    assert worst <= 2 and sum(p.over for p in perf.values() if str(p.name).startswith("game.part")) == 0
    assert not errors(sim, ns), errors(sim, ns)

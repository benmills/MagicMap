"""Game's waypoint, /way and corpse, round trips on the sim (docs/v1-plan.md M3.2): the waypoint and way
Commands (game/commands/) come back in the client and in the next observation, and what the client says
of the user waypoint and of your corpse reaches obs.waypoint and obs.corpse (game/parts/Waypoint.lua,
Corpse.lua). The late corpse with no event is R-G4 (replays/R-G4.lua)."""
from sim import py
from test_addon import boot, errors

ELWYNN = 1429
JASPER = {"inst": 0, "col": 33.2, "row": 48.98}  # the Jasperlode Mine, Elwynn
EASTVALE = {"inst": 0, "col": 34.29, "row": 49.87}  # the Eastvale Logging Camp
SEA = {"inst": 0, "col": 10.0, "row": 30.0}  # no zone's map


def client():
    L, sim, ns = boot()
    sim.Run(0.1)
    return L, sim, ns, L.eval("rawequal")


def command(L, ns, kind, pos):
    ns.Game.Command(L.table_from({"kind": kind, "pos": L.table_from(pos) if pos else False}))


def near(pos, want):
    return pos["inst"] == want["inst"] and abs(pos["col"] - want["col"]) < 1e-9 and abs(pos["row"] - want["row"]) < 1e-9


def test_waypoint_round_trip():
    L, sim, ns, held = client()
    assert ns.Game.obs.waypoint is False

    # Set: on Elwynn's map, super-tracked (the followed quest no longer), in the same frame's obs.
    sim.superTracked = 60
    command(L, ns, "waypoint", JASPER)
    sim.Step()
    point = sim.waypoint
    x, y = ns.Atlas.TileToMap(ELWYNN, JASPER["col"], JASPER["row"])
    assert point.uiMapID == ELWYNN and (point.position.x, point.position.y) == (x, y)
    assert sim.superTracked == 0
    at = ns.Game.obs.waypoint
    assert near(py(at), JASPER)
    sim.Run(1)
    assert held(ns.Game.obs.waypoint, at)
    command(L, ns, "waypoint", JASPER)  # again: nothing new
    sim.Step()
    assert held(ns.Game.obs.waypoint, at)

    # Moved; then set by the game's own map: read on its event.
    command(L, ns, "waypoint", EASTVALE)
    sim.Step()
    assert near(py(ns.Game.obs.waypoint), EASTVALE)
    sim.waypoint = L.eval("UiMapPoint.CreateFromCoordinates")(ELWYNN, *ns.Atlas.TileToMap(ELWYNN, JASPER["col"], JASPER["row"]))
    sim.FireEvent("USER_WAYPOINT_UPDATED")
    sim.Step()
    assert near(py(ns.Game.obs.waypoint), JASPER)

    # Where it can't go: why not, and the waypoint kept.
    at = ns.Game.obs.waypoint
    command(L, ns, "waypoint", SEA)
    sim.Step()
    assert sim.prints[len(sim.prints)] == "|cffffd100MagicMapAtlas|r: no zone here to put a waypoint in"
    L.execute("C_Map.CanSetUserWaypointOnMap = function() return false end")
    command(L, ns, "waypoint", EASTVALE)
    sim.Step()
    assert sim.prints[len(sim.prints)] == "|cffffd100MagicMapAtlas|r: can't place a waypoint in Elwynn Forest"
    assert held(ns.Game.obs.waypoint, at) and sim.waypoint.uiMapID == ELWYNN

    # Cleared: none. On a map Atlas hasn't (a mine's own): none we can show.
    command(L, ns, "waypoint", False)
    sim.Step()
    assert sim.waypoint is None and ns.Game.obs.waypoint is False and ns.Game.obs.waypointSet is False
    sim.waypoint = L.eval("UiMapPoint.CreateFromCoordinates")(1601, 0.5, 0.5)
    sim.FireEvent("USER_WAYPOINT_UPDATED")
    sim.Step()
    assert ns.Game.obs.waypoint is False and ns.Game.obs.waypointSet is True  # set, but nowhere we can show
    assert not errors(sim, ns), errors(sim, ns)


def test_way_round_trip():
    L, sim, ns, held = client()
    said = len(sim.prints)
    command(L, ns, "way", JASPER)
    sim.Step()
    assert sim.chat == "/way Elwynn Forest 62.7 48.2"  # in the chat box, not sent
    sim.chat = None
    command(L, ns, "way", SEA)
    sim.Step()
    assert sim.chat is None and len(sim.prints) == said
    assert not errors(sim, ns), errors(sim, ns)


def test_corpse_round_trip():
    L, sim, ns, held = client()
    assert ns.Game.obs.corpse is False

    # Released and known at once: on the continent's map (asked first), the event's frame.
    body = {"inst": 0, "col": 30.8, "row": 50.85}
    x, y = ns.Atlas.TileToMap(1415, body["col"], body["row"])
    sim.units.player.dead, sim.ghost = True, True
    sim.corpse = L.table_from({1415: L.eval("CreateVector2D")(x, y)})
    sim.FireEvent("PLAYER_ALIVE")
    sim.Step()
    at = ns.Game.obs.corpse
    assert near(py(at), body)
    sim.Run(2)
    assert held(ns.Game.obs.corpse, at)

    # Resurrected at the spirit healer: none.
    sim.units.player.dead, sim.ghost, sim.corpse = False, False, None
    sim.FireEvent("PLAYER_UNGHOST")
    sim.Step()
    assert ns.Game.obs.corpse is False
    assert not errors(sim, ns), errors(sim, ns)

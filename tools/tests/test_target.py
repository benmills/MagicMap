"""Model's target (docs/v1-plan.md M3.1: model/Target.lua) on the simulated client, end to end from the
sim's quest log and its areas (Inside: game/Oracles.lua) through Game's parts and Model:

  test_target_priority: your corpse while you're a ghost, else the quest you follow if its pin is on the
    map shown, else your waypoint (F32), each named as the title band names it; another continent shown,
    what's there or none; the same table while nothing changes; Known("corpse"), Known("waypoint").
  test_target_quest_edge: the quest you follow, with an area: its nearest edge from you (a fan of rays,
    then halvings), not its pin; walked into, inside only once that has held 0.5 s, and no route while
    inside; walked out, the edge again once that has held; its area moved off its pin, the same.
  test_target_layers: each target only while its layer is on (Focus.off: the spike's pinData, Layers.lua:
    1029, 1160-1168), the priority falling through; Quest areas off, the quest's pin, not its area's edge.

obs.corpse and obs.waypoint come from Game's parts (M3.2's); here from TARGETS's own, as they hand them.
"""
import math

from test_addon import errors
from test_quests import client

# obs.corpse and obs.waypoint as Game's parts hand them: Put.corpse, Put.waypoint (an MM.Pos, a new table
# on a change; false: none). The route's searches on a clock that counts Lua's VM instructions in them
# (R-P2's: 10 ns each, as the client's Lua, so a 1 ms slice is a slice of work; Counting = false: the
# counted clock's, Lua free): each search's handle in Jobs, its Runtime.Yields counted (yields).
TARGETS = """
local Sim, ns = ...
Put = { corpse = false, waypoint = false }
ns.Game.Part("corpse", function() return Put.corpse end)
ns.Game.Part("waypoint", function() return Put.waypoint end)
function Spot(inst, col, row) return { inst = inst, col = col, row = row } end
Jobs, Counting = {}, true
local R, NS, EVERY, counted, running = ns.Runtime, 0.00001, 100, 0, {}
local clock, Job, Yield = Sim.Clock, R.Job, R.Yield
Sim.Clock = function() return clock() + counted * NS end
R.Job = function(name, fn, ...)
	if name ~= "model: route" then return Job(name, fn, ...) end
	local j
	j = Job(name, function()
		running[coroutine.running()], j.yields = j, 0
		if Counting then debug.sethook(function() counted = counted + EVERY end, "", EVERY) end
		fn()
		debug.sethook()
	end, ...)
	Jobs[#Jobs + 1] = j
	return j
end
R.Yield = function()
	local j = running[coroutine.running()]
	if j then j.yields = j.yields + 1 end
	return Yield()
end
"""

FRONTIER = {"id": 52, "title": "Protect the Frontier", "level": 11, "col": 31.8, "row": 49.7,
            "objectives": [["monster", "Prowler slain: 2/8", 2, 8, False]], "area": 0.05}
GOLD = {"id": 47, "title": "Gold Dust Exchange", "level": 7, "col": 32.4, "row": 49.4,
        "objectives": [["item", "Gold Dust: 0/10", 0, 10, False]]}
ELWYNN = 1429


def targets(quests, followed):
    L, sim, ns, G = client(quests, followed=followed)
    L.execute(TARGETS, sim, ns)
    return L, sim, ns, G


def put(G, kind, inst=None, col=None, row=None):
    setattr(G.Put, kind, G.Spot(inst, col, row) if inst is not None else False)


def test_target_priority():
    L, sim, ns, G = targets([FRONTIER, GOLD], followed=52)
    Model = ns.Model
    sim.Run(0.1)
    t = Model.Target()
    assert (t.kind, t.key, t.title, t.quest) == ("quest", "quest:52", "[11] Protect the Frontier", 52)
    put(G, "waypoint", 0, 32.5, 49.0)
    put(G, "corpse", 0, 31.0, 50.0)
    sim.Run(0.1)
    assert Model.Target().kind == "quest"  # the quest beats the waypoint, a corpse counts only for a ghost
    assert [(e.key, e.name, e.pos.col) for e in Model.Known("corpse")[0].values()] == [("corpse", "Your corpse", 31.0)]
    assert [(e.key, e.name, e.pos.col) for e in Model.Known("waypoint")[0].values()] == [("waypoint", "Waypoint", 32.5)]
    sim.ghost = True
    sim.Run(0.1)
    t = Model.Target()
    assert (t.kind, t.key, t.title, t.pos.col, t.pos.row, t.inside) == ("corpse", "corpse", "Your corpse", 31.0, 50.0, None)
    sim.Run(0.5)
    assert L.eval("rawequal")(Model.Target(), t)  # nothing changed: the same table
    sim.ghost = False
    sim.superTracked = 0  # Blizzard's tracker follows none
    sim.FireEvent("SUPER_TRACKING_CHANGED")
    sim.Run(0.5)
    t = Model.Target()
    assert (t.kind, t.key, t.title, t.pos.col, t.quest) == ("waypoint", "waypoint", "Waypoint", 32.5, None)
    put(G, "waypoint")  # cleared
    sim.Run(0.1)
    assert Model.Target() is False and len(Model.Known("waypoint")[0]) == 0

    # Kalimdor shown (following off): the quest you follow and your corpse are on another map; a waypoint
    # there is the target, but no route to it from Elwynn (same instance only).
    sim.superTracked, sim.ghost = 52, True
    sim.FireEvent("SUPER_TRACKING_CHANGED")
    ns.UI.Motion.SetFollow(False)
    ns.UI.Motion.FitMap(1)
    sim.Run(0.5)
    assert Model.focus.inst == 1 and Model.Target() is False
    put(G, "waypoint", 1, 40.0, 30.0)
    sim.Run(0.5)
    assert Model.Target().kind == "waypoint" and Model.Route() is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_target_quest_edge():
    L, sim, ns, G = targets([FRONTIER], followed=52)
    Model, Atlas, me = ns.Model, ns.Atlas, sim.player
    x0, y0 = Atlas.TileToMap(ELWYNN, FRONTIER["col"], FRONTIER["row"])
    r = FRONTIER["area"]

    def off(col, row):
        """How far (col, row) is from the area's centre, in its radii (the sim's areas are circles on the map)."""
        x, y = Atlas.TileToMap(ELWYNN, col, row)
        return math.hypot(x - x0, y - y0) / r

    me.col, me.row = FRONTIER["col"] - 1.0, FRONTIER["row"] + 0.2  # outside, a tile west
    sim.Run(1)
    t = Model.Target()
    assert t.kind == "quest" and t.inside is False
    assert abs(off(t.pos.col, t.pos.row) - 1) < 0.02  # on its edge...
    d = lambda p: math.hypot(p.col - me.col, p.row - me.row)
    assert d(t.pos) < d(G.Spot(0, FRONTIER["col"], FRONTIER["row"])) - 0.1  # ...nearer you than its pin
    assert Model.Route() is not None

    me.col, me.row = FRONTIER["col"], FRONTIER["row"]  # in it
    sim.Run(0.4)
    assert Model.Target().inside is False  # not held yet
    sim.Run(0.6)
    assert Model.Target().inside is True and Model.Route() is None
    me.col = FRONTIER["col"] - 1.0  # out again
    sim.Run(0.4)
    assert Model.Target().inside is True
    sim.Run(0.6)
    t = Model.Target()
    assert t.inside is False and abs(off(t.pos.col, t.pos.row) - 1) < 0.02
    sim.Run(1)
    assert Model.Route() is not None

    # Its area moved off its pin (a QUEST_POI_UPDATE: 0.08 east, the pin outside it): still its edge from
    # you, not the pin (the spike's InBlob tests the followed frame, Layers.lua:1099-1155); walked into,
    # inside once held.
    x0 += 0.08
    sim.blobShapes[52] = L.table_from([x0, y0, r])
    sim.FireEvent("QUEST_POI_UPDATE")
    sim.Run(1)
    t = Model.Target()
    assert t.inside is False and abs(off(t.pos.col, t.pos.row) - 1) < 0.02 and t.pos.col > FRONTIER["col"]
    _, me.col, me.row = Atlas.MapToTile(ELWYNN, x0, y0)
    sim.Run(0.4)
    assert Model.Target().inside is False
    sim.Run(0.6)
    assert Model.Target().inside is True and Model.Route() is None
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_target_layers():
    L, sim, ns, G = targets([FRONTIER], followed=52)
    Model, Engine, me = ns.Model, ns.UI.Engine, sim.player
    me.col, me.row = FRONTIER["col"] - 1.0, FRONTIER["row"] + 0.2  # outside its area, a tile west
    put(G, "waypoint", 0, 32.5, 49.0)
    put(G, "corpse", 0, 31.0, 50.0)
    sim.ghost = True
    sim.Run(1)
    assert Model.Target().kind == "corpse"
    pin = next(e for e in Model.Known("quests")[0].values() if e.quest == 52).pos

    def turned(layer, on):
        Engine.SetLayer(layer, on)
        sim.Run(1)  # (the area's inside, looked at as the boot's spot, held 0.5 s once it's looked at again)
        return Model.Target()

    t = turned("corpse", False)
    assert t.kind == "quest" and t.inside is False and math.hypot(t.pos.col - pin.col, t.pos.row - pin.row) > 0.1
    t = turned("questAreas", False)  # its pin: no area edge, no inside
    assert t.kind == "quest" and t.inside is None and (t.pos.col, t.pos.row) == (pin.col, pin.row)
    t = turned("quests", False)
    assert t.kind == "waypoint" and Model.Route() is not None
    assert turned("waypoint", False) is False
    assert Model.Route() is None and ns.UI.Path.pieces == 0
    for layer in ("waypoint", "quests", "questAreas"):
        turned(layer, True)
    assert turned("corpse", True).kind == "corpse"
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

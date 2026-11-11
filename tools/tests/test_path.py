"""The way to the target on the simulated client (docs/v1-plan.md M3.3: ui/Path.lua; ui/You.lua's corpse and
waypoint pins and the title's target), Model.Target and Model.Route stubbed as typed (types/model.lua):

  test_path_line: the dotted line (S55-S57, lighter and dotted since 2.0): a light 1.6 px dot each 4 px over a
    dark 3.2 px casing, laid back from the target, 12 px clear of you and 15 of the target, faded at the ends,
    uneven; along the route when there is one; gone once you're inside the target's area, or without a target
    (F33); and Path.DEFAULTS and COLORS as the settings dialog lists them.
  test_path_feel: the look's settings through ui/Feel.lua's API (stubbed, set after Path loaded): a solid line
    at another weight laid out again, a line a leg; the glow off BLEND; a colour, the breath off, an opacity;
    the dashed style the spike's 6/4 at 1.9; a value out of range the default's.
  test_path_redraws: nothing laid out again standing (no widget call); a turn past 3°, a zoom, a new route
    (not the same one handed again) and a walk lay it out again; a pan carries it along, the dashes shown
    left as they stand, those it brings in shown (S58).
  test_path_cap: a long line at zoom 800: 160 pieces at most (the dots spread), only those near the view shown,
    every piece within 4096 px of its canvas (S56; docs/v1-plan.md §2).
  test_edge_arrow: a target off the view gets the gold arrow 16 px inside the edge where the line toward it
    leaves (along the route's leg that does), pointing on; none on the view or inside (F34, S59).
  test_guide_arrow: Track's gold arrow (ui/Guide.lua), no line: 48 px out along the way, pointing on; turning
    doesn't move it; a route north first swings it round (eased) onto that leg; nearer, it rides in short of the
    pin, dimmer, and goes once the pin is by your arrow; its distance and size settings; none pathed or arrived.
  test_path_frame: Path to's framing at the minimap's size (ui/Motion.lua's StepFrame): zoomed out so you and the
    target are in view, never in past the zoom it began at; a drag holds it (hovered, however long), back once
    left alone as the idle return is; a zoom of yours too; none on the big map; arrived, the zoom back.
  test_corpse_forces_follow: your corpse becoming the target (a ghost) glides the view back to you; another
    target doesn't, nor the one you had when the map first looked, nor browsing away and back (F7, F42).
  test_title_target: the subtitle's "<title>" and "<title> here", big or small and hovered (S12).
  test_corpse_waypoint_pins: Known("corpse") and Known("waypoint") as pins (S49), from Game's parts through Model,
    their tooltips, their gear rows.
  test_path_walk_laid_as_new: walking, the line ends as a new layout from where you stop lays it out,
    dash for dash (those left as they stand, those laid by halves), under MAX_PIECES and past it.
  test_path_walk_alloc: walking with a route, the line laid out again as you go: the whole ≤ 50 KB/s (the
    M3.3 Verify), the path's own next to none (its lines made at load).
  test_path_priced: a long winding route at the client's prices, zooming in and out (the line laid out each
    frame the zoom moves), walking and dragging: within the frame budgets, no call over 2 ms. With our Lua
    charged too (R-P2's 10 ns an instruction): the line's own budgets.
  test_path_priced_big: the big window, a waypoint at the view's corner (as a Ctrl-click there): its first
    layout under 2 ms (no line made then); zooming with the line across the view, M shrinking and growing it:
    no frame over 8 ms, the zoom state's p95 ≤ 5 (M1.15: the layouts' slices fit the frame the line's dashes
    share, ~1 ms of it; 6.3 at the M2 review). With our Lua charged too: printed.
  test_path_walk_big: walking in the big window at zoom 400 toward a waypoint across the zone, Model's own
    route, priced and with our Lua charged too: at rest p95 ≤ 1 ms (a line past MAX_PIECES re-spaces every
    dash as you go: half its dashes a frame, their ends at whole pixels; under it, the dashes on legs that
    didn't move left as they stand).
"""
import math

import pytest

import sim as S
from test_addon import boot, errors
from test_quest_areas import stretch
from sim import TEST_UI

SETUP = """
local Sim, ns = ...
local UI, S = ns.UI, Sim.state
Tgt, Way = false, nil
ns.Model.Target = function() if ns.Model.focus then return Tgt end end -- (nil: no Focus yet, as typed)
ns.Model.Route = function() return Way end
ns.Atlas.Walk.Snap = function() end -- (Model's own route, unseen here, finds nowhere to stand: no search runs)
Sim.player.facing = -math.pi / 2 -- east (the client's facing: counter-clockwise from north)
-- A target of kind at tile (col, row) on your map, pathed (Path to: the line; track: Track, the gold arrow alone).
function Target(kind, col, row, title, track)
	Tgt = { kind = kind, key = kind .. ":" .. col .. "," .. row, pos = { inst = 0, col = col, row = row }, title = title,
		track = track }
	return Tgt
end
UI.Track.Pathed = function(t) return t and (t.kind == "corpse" or not t.track) or false end -- (as Track's: the stub's mode)
UI.Feel.Set("path.frame", false) -- (the line measured with the view on you: test_path_frame frames)
-- A route: you, then each { col, row } given (the target last).
function Route(pts)
	local p = Sim.player
	Way = { { inst = 0, col = p.col, row = p.row } }
	for i, q in ipairs(pts) do Way[i + 1] = { inst = 0, col = q[1], row = q[2] } end
	return Way
end
local looks = 0 -- the helpers' own calls on the canvas (Sim.callsOn counts them)
local function Lines()
	looks = looks + 1
	return { UI.Path.canvas:GetRegions() }
end
-- The path's pieces shown of a thickness (a line's, or a dot's side): { ax, ay, bx, by, alpha } in px from
-- the view's centre, y down (a dot: its centre twice).
function Dashes(thick)
	local c, out = S[UI.Path.canvas].points[1], {}
	for _, r in ipairs(Lines()) do
		local st = S[r]
		if st.shown and st.type == "Line" and st.thickness == thick then
			out[#out + 1] = { c.x + st.startPoint[3], -(c.y + st.startPoint[4]), c.x + st.endPoint[3],
				-(c.y + st.endPoint[4]), st.color[4] }
		elseif st.shown and st.type == "Texture" and st.width == thick then
			local p = st.points[1]
			out[#out + 1] = { c.x + p.x, -(c.y + p.y), c.x + p.x, -(c.y + p.y), st.color[4] }
		end
	end
	return out
end
-- The path's pieces shown: { thickness or side, blend, r, g, b } distinct.
function Looks()
	local out = {}
	for _, r in ipairs(Lines()) do
		local st = S[r]
		if st.shown then
			out[table.concat({ st.thickness or st.width, st.blend or "BLEND", st.color[1], st.color[2], st.color[3] }, " ")] = true
		end
	end
	return out
end
-- The path's lines shown: line -> widget calls on it so far.
function ShownLines()
	local out = {}
	for _, r in ipairs(Lines()) do
		if S[r].shown then out[r] = Sim.callsOn[r] or 0 end
	end
	return out
end
-- Of the lines shown in before (ShownLines'), those still shown: how many, and how many had a widget call since.
function Kept(before)
	local kept, touched = 0, 0
	for r, n in pairs(before) do
		if S[r].shown then
			kept = kept + 1
			if (Sim.callsOn[r] or 0) ~= n then touched = touched + 1 end
		end
	end
	return kept, touched
end
-- Widget calls on the path's lines and canvas so far.
function Calls()
	local n = 0
	for _, r in ipairs(Lines()) do n = n + (Sim.callsOn[r] or 0) end
	return n + (Sim.callsOn[UI.Path.canvas] or 0) - looks
end
"""
SEP = "  ·  ".encode("utf-8").decode("latin-1")  # the title's join, as the sim holds it
YD = 1600 / 3  # a tile


def client(saved=None, shown=True, lua=False):
    """lua: our own Lua charged too, as the client's (sim.LUA_PRICE: 10 ns a VM instruction)."""
    L, sim, ns = boot(saved, lua=lua)
    L.execute(SETUP, sim, ns)
    if shown:
        sim.Slash("/mm toggle")
        sim.Run(1.5)
    return L, sim, ns, L.globals()


def dashes(G, thick):
    return [tuple(d[i] for i in range(1, 6)) for d in G.Dashes(thick).values()]


def off_line(pts, x, y):
    """px from (x, y) to the polyline pts (view px)."""
    best = math.inf
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(ax + dx * t - x, ay + dy * t - y))
    return best


def test_path_line():
    L, sim, ns, G = client()
    P, S, z = ns.UI.Path, sim.state, ns.UI.Camera.cam.zoom
    assert P.DEFAULTS.style == "dashed" and P.DEFAULTS.weight == 1.4 and P.DEFAULTS.color == "Gold" and P.COLORS[1][1] == "Parchment"
    assert not P.DEFAULTS.glow and not P.DEFAULTS.breath and P.DEFAULTS.opacity == 0.65 and not P.DEFAULTS.edge and len(P.COLORS) == 6
    # (the line measured below is the tests' look, sim.TEST_LOOK: dotted parchment, its edge on)
    G.Target("waypoint", 33.0, 49.75, "Waypoint")  # 1.05 tiles east of you: 100.8 px at 96
    sim.Run(0.2)
    strokes, washes = dashes(G, 1.6), dashes(G, 3.2)
    assert len(strokes) == len(washes) == P.pieces == 19
    end = (33.0 - 31.95) * z
    for (ax, ay, bx, by, a), (wax, way, wbx, wby, wa) in zip(sorted(strokes), sorted(washes)):
        assert (ax, ay, bx, by) == (wax, way, wbx, wby) and 0 < a <= 0.92 and 0 < wa <= 0.45
        assert 12 <= ax == bx <= end - 15 and ay == by and abs(ay) <= 1.5  # a dot: its centre, half px
    assert sorted(strokes)[-1][0] - sorted(strokes)[-2][0] == 4  # laid back from the target, 4 px apart
    assert len({d[4] for d in strokes}) > 3  # faded at its ends, uneven along it
    assert set(G.Looks().keys()) == {"1.6 ADD 1 0.93 0.76", "3.2 BLEND 0.12 0.08 0.03"}  # a dot ADDed over its casing

    # Along a route: north, then east, then south to it (facing north: no lead-in curve to speak of).
    sim.player.facing = 0
    pts = [(31.95, 49.2), (33.0, 49.2), (33.0, 49.75)]
    G.Route(L.table_from([L.table_from(p) for p in pts]))
    sim.Run(0.2)
    view = [(0, 0)] + [((c - 31.95) * z, (r - 49.75) * z) for c, r in pts]
    strokes = dashes(G, 1.6)
    assert len(strokes) > 40 and all(off_line(view, x, y) <= 1.5 for d in strokes for x, y in (d[:2], d[2:4]))

    # Inside its area: arrived, the line steps aside; no target, none.
    G.Tgt.inside = True
    sim.Step()
    assert dashes(G, 1.6) == [] and dashes(G, 3.2) == []
    G.Tgt.inside = None
    sim.Step()
    n = len(dashes(G, 1.6))
    sim.Step()
    assert 20 < n < len(dashes(G, 1.6)) and len(dashes(G, 1.6)) > 40  # (a line new: half its dots a frame)
    G.Tgt = False
    sim.Step()
    assert dashes(G, 1.6) == [] and P.pieces == 0
    assert not errors(sim, ns), errors(sim, ns)


FEEL = """
local Sim, ns = ...
Over = {} -- ui/Feel.lua's API, stubbed: the values set here over Path's defaults; a change moves rev
-- (the tests' look under it, sim.TEST_LOOK's: not Path's defaults)
local Look = { style = "dotted", weight = 1.6, color = "Parchment", glow = true, breath = true, opacity = 1, edge = true, edgeColor = "Dark" }
ns.UI.Feel = { rev = 1, Get = function(k) local v = Over[k]; if v == nil then v = Look[k:sub(6)] end; return v end }
function Feel(k, v)
	Over[k] = v
	ns.UI.Feel.rev = ns.UI.Feel.rev + 1
end
"""


def test_path_feel():
    """The settings, through Feel's API set after Path loaded: a solid line at another weight is laid out again,
    one line a leg, fewer pieces; the glow off is BLEND; a colour, the breath off (the canvas's alpha 1), an
    opacity; standing, no further layout nor widget call; a value out of range draws the default."""
    L, sim, ns, G = client()
    L.execute(FEEL, sim, ns)
    P, S, z = ns.UI.Path, sim.state, ns.UI.Camera.cam.zoom
    sim.player.facing = 0
    pts = [(31.95, 49.2), (33.0, 49.2), (33.0, 49.75)]
    G.Target("waypoint", 33.0, 49.75, "Waypoint")
    G.Route(L.table_from([L.table_from(p) for p in pts]))
    sim.Run(0.5)
    dots, draws = P.pieces, P.draws
    assert dots > 40 and set(G.Looks().keys()) == {"1.6 ADD 1 0.93 0.76", "3.2 BLEND 0.12 0.08 0.03"}

    G.Feel("path.style", "solid")
    G.Feel("path.weight", 3)
    sim.Run(0.2)
    view = [(0, 0)] + [((c - 31.95) * z, (r - 49.75) * z) for c, r in pts]
    strokes, washes = dashes(G, 3), dashes(G, 6)
    assert P.draws == draws + 1 and dashes(G, 1.6) == [] and dashes(G, 3.2) == []
    assert 3 <= P.pieces == len(strokes) == len(washes) <= 12 < dots  # the legs (the lead-in's steps and the route's)
    assert all(off_line(view, x, y) <= 1e-6 for d in strokes for x, y in (d[:2], d[2:4]))  # no wobble
    assert all(d[:4] == w[:4] for d, w in zip(sorted(strokes), sorted(washes)))
    assert set(G.Looks().keys()) == {"3 ADD 1 0.93 0.76", "6 BLEND 0.12 0.08 0.03"}
    draws, calls = P.draws, G.Calls()
    sim.Run(1)  # standing: nothing more
    assert P.draws == draws and G.Calls() == calls

    G.Feel("path.glow", False)
    G.Feel("path.color", "Sky")
    G.Feel("path.breath", False)
    G.Feel("path.opacity", 0.5)
    sim.Run(0.2)
    assert P.draws == draws + 1 and S[P.canvas].alpha == 1
    assert set(G.Looks().keys()) == {"3 BLEND 0.55 0.8 1", "6 BLEND 0.12 0.08 0.03"}
    assert all(0 < d[4] <= 0.46 for d in dashes(G, 3)) and all(0 < d[4] <= 0.225 for d in dashes(G, 6))

    G.Feel("path.style", "dashed")  # the spike's 6/4 at 1.9, by the weight
    G.Feel("path.weight", 1.9)
    G.Feel("path.opacity", 1)
    G.Feel("path.breath", True)
    sim.Run(0.2)
    strokes = dashes(G, 1.9)
    assert P.pieces == len(dashes(G, 3.8)) > 15 and all(0 < d[2] - d[0] <= 6 or 0 < abs(d[3] - d[1]) <= 6 for d in strokes)
    assert set(G.Looks().keys()) == {"1.9 BLEND 0.55 0.8 1", "3.8 BLEND 0.12 0.08 0.03"}

    G.Feel("path.weight", 40)  # out of range: the default's (1.4 px, gold)
    G.Feel("path.color", "Plaid")
    sim.Run(0.2)
    assert P.pieces == len(dashes(G, 1.4)) > 15 and set(G.Looks().keys()) == {"1.4 BLEND 1 0.82 0.3", "2.8 BLEND 0.12 0.08 0.03"}

    G.Feel("path.edge", False)  # the outline off: the strokes alone; its colour, once on again
    sim.Run(0.2)
    assert P.pieces == len(dashes(G, 1.4)) > 15 and dashes(G, 2.8) == []
    G.Feel("path.edge", True)
    G.Feel("path.edgeColor", "White")
    sim.Run(0.2)
    assert set(G.Looks().keys()) == {"1.4 BLEND 1 0.82 0.3", "2.8 BLEND 1 1 1"} and len(dashes(G, 2.8)) == P.pieces
    assert not errors(sim, ns), errors(sim, ns)


def test_path_redraws():
    L, sim, ns, G = client()
    P, cam = ns.UI.Path, ns.UI.Camera.cam
    G.Target("waypoint", 33.0, 49.75, "Waypoint")
    sim.Run(0.5)
    draws, calls = P.draws, G.Calls()
    sim.Run(3)  # standing: nothing laid out, no widget call
    assert P.draws == draws and G.Calls() == calls

    sim.player.facing += math.radians(1)  # under 3°: as it was
    sim.Run(0.2)
    assert P.draws == draws
    sim.player.facing += math.radians(3)
    sim.Run(0.2)
    assert P.draws == draws + 1

    pts = L.table_from([L.table_from(p) for p in [(32.5, 49.6), (33.0, 49.75)]])
    G.Route(pts)  # found: laid out along it
    sim.Run(0.2)
    assert P.draws == draws + 2
    G.Route(pts)  # the same route again, a new table: as it was
    sim.Run(0.2)
    assert P.draws == draws + 2

    sim.Wheel(ns.UI.Window.view, 1)  # each frame the zoom moves
    sim.Run(1)
    assert P.draws > draws + 10
    draws = P.draws
    sim.player.speed = 7  # walking: as you move half a pixel (7 yd/s at 124.8 px a tile: ~1.6 px/s)
    sim.Run(2)
    sim.player.speed = 0
    assert draws + 4 <= P.draws <= draws + 10

    # A pan carries it: the canvas moves with the map, the dashes shown stay as they stand (no widget call),
    # those coming into view are shown.
    G.Target("waypoint", 36.0, 49.75)  # past the view's east edge
    sim.Run(0.2)
    before, x, n = G.ShownLines(), sim.state[P.canvas].points[1].x, len(dashes(G, 1.6))
    sim.Drag(ns.UI.Window.view, -80, 0)
    sim.Run(0.2)
    assert not ns.UI.Camera.follow and abs(sim.state[P.canvas].points[1].x - (x - 80)) < 1e-6
    kept, touched = G.Kept(before)
    assert kept == 2 * n and touched == 0 and len(dashes(G, 1.6)) > n + 4
    assert cam.zoom > 96 and not errors(sim, ns), errors(sim, ns)


def test_path_cap():
    L, sim, ns, G = client()
    P, S = ns.UI.Path, sim.state
    ns.UI.Motion.SetZoom(800)
    G.Target("waypoint", 40.0, 49.75)  # 8 tiles east: 6440 px
    sim.Run(0.3)
    w, h = ns.UI.Window.Size()
    strokes = dashes(G, 1.6)
    assert P.pieces == 160 and 0 < len(strokes) < 160  # 40 px apart; only those near the view
    assert all(abs(x) <= w + 24 and abs(y) <= h for d in strokes for x, y in (d[:2], d[2:4]))
    c = S[P.canvas].points[1]
    assert abs(c.x) <= 4096 and abs(c.y) <= 4096
    for r in P.canvas.GetRegions(P.canvas):
        if S[r].shown:
            p = S[r].points[1]
            assert max(abs(p.x), abs(p.y)) <= 4096  # (a dot)
    assert not errors(sim, ns), errors(sim, ns)


def test_edge_arrow():
    L, sim, ns, G = client()
    P, S, cam = ns.UI.Path, sim.state, ns.UI.Camera.cam
    w, h = ns.UI.Window.Size()
    z = cam.zoom
    edge = P.edge
    G.Target("waypoint", 33.0, 49.75)  # on the view: none
    sim.Run(0.2)
    assert not S[edge].shown

    # Off it to the east: on the right edge's inset, where the line toward it leaves, pointing on.
    G.Target("waypoint", 36.0, 49.5)
    sim.Step()
    you = ns.Model.you
    x1, y1 = (you.col - cam.cx) * z + w / 2, (you.row - cam.cy) * z + h / 2
    dx, dy = (36.0 - you.col) * z, (49.5 - you.row) * z
    k = (w - 16 - x1) / dx
    p = S[edge].points[1]
    assert S[edge].shown and S[edge].texture == "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW"
    assert (S[edge].width, S[edge].height) == (32, 32) and p.point == "CENTER" and p.relPoint == "TOPLEFT"
    assert (p.x, p.y) == (math.floor(x1 + dx * k + 0.5), -math.floor(y1 + dy * k + 0.5))
    assert abs(S[edge].rotation - math.atan2(-dx, -dy)) < 1e-9

    # With a route, along its leg that leaves the view: north first, so on the top edge's inset.
    G.Route(L.table_from([L.table_from(q) for q in [(32.2, 47.0), (36.0, 49.5)]]))
    sim.Step()
    dx, dy = (32.2 - you.col) * z, (47.0 - you.row) * z
    k = (16 - y1) / dy
    p = S[edge].points[1]
    assert (p.x, p.y) == (math.floor(x1 + dx * k + 0.5), -16) and abs(S[edge].rotation - math.atan2(-dx, -dy)) < 1e-9

    G.Tgt.inside = True  # arrived: none
    sim.Step()
    assert not S[edge].shown
    G.Tgt.inside = None
    sim.Step()
    assert S[edge].shown
    G.Tgt = False
    sim.Step()
    assert not S[edge].shown
    assert not errors(sim, ns), errors(sim, ns)


def test_guide_arrow():
    L, sim, ns, G = client()
    UI, S, cam = ns.UI, sim.state, ns.UI.Camera.cam
    a, D = UI.Guide.arrow, UI.Guide.DEFAULTS
    w, h = UI.Window.Size()
    z, you = cam.zoom, ns.Model.you

    def at():  # the arrow's centre from yours, px
        p = S[a].points[1]
        return p.x - ((you.col - cam.cx) * z + w / 2), -p.y - ((you.row - cam.cy) * z + h / 2)

    # Tracked far to the east: no line, no edge arrow; the gold arrow 48 px out along the way, pointing on.
    G.Target("waypoint", 36.0, 49.75, None, True)
    sim.Run(2)
    assert UI.Path.pieces == 0 and not S[UI.Path.edge].shown
    assert S[a].shown and S[a].texture == "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW" and S[a].width == 32 * D.size
    dx, dy = at()
    assert abs(dx - D.reach) < 0.2 and abs(dy) < 0.2 and abs(S[a].rotation + math.pi / 2) < 0.01 and abs(S[a].alpha - D.opacity) < 0.02
    # Turning doesn't move it (your arrow shows which way you face): no call on it.
    calls = sim.callsOn[a] or 0
    sim.player.facing = 0
    sim.Run(0.5)
    assert (sim.callsOn[a] or 0) == calls
    # A route north first: it swings round onto the route's first leg (eased: part way after a frame), then
    # stands on it, pointing north.
    G.Route(L.table_from([L.table_from(q) for q in [(31.95, 48.5), (36.0, 49.75)]]))
    sim.Step()
    dx, dy = at()
    assert dx > 5 and dy > -40
    sim.Run(2)
    dx, dy = at()
    assert abs(dx) < 0.2 and abs(dy + D.reach) < 0.2 and abs(S[a].rotation) < 0.01
    # Nearer: it rides in short of the pin (16 px), dimmer; within reach of your arrow, the pin takes over: gone.
    G.Way = None
    G.Target("waypoint", 31.95 + 40 / z, 49.75, None, True)
    sim.Run(2)
    dx, dy = at()
    assert abs(dx - 24) < 0.2 and 0 < S[a].alpha < D.opacity / 2
    G.Target("waypoint", 31.95 + 30 / z, 49.75, None, True)
    sim.Run(2)
    assert not S[a].shown
    # Its settings: further out, bigger.
    G.Target("waypoint", 36.0, 49.75, None, True)
    UI.Feel.Set("guide.reach", 80)
    UI.Feel.Set("guide.size", 1.2)
    sim.Run(2)
    assert abs(at()[0] - 80) < 0.2 and abs(S[a].width - 32 * 1.2) < 1e-9
    # Pathed: the line, not the arrow; arrived: neither.
    G.Target("waypoint", 36.0, 49.75)
    sim.Run(2)
    assert UI.Path.pieces > 0 and not S[a].shown
    G.Target("waypoint", 36.0, 49.75, None, True)
    G.Tgt.inside = True
    sim.Run(2)
    assert UI.Path.pieces == 0 and not S[a].shown
    assert not errors(sim, ns), errors(sim, ns)


def test_path_frame():
    L, sim, ns, G = client()
    UI, cam, Atl = ns.UI, ns.UI.Camera.cam, ns.Atlas.Camera
    UI.Feel.Set("path.frame", True)
    UI.saved.path = L.table_from({})  # (Path to's: where its zoom is kept)
    w, h = UI.Window.Size()
    z0, you = cam.zoom, ns.Model.you

    def framed(col, row, pad=26):
        x, y = Atl.TileToScreen(cam, w, h, col, row)
        return pad - 0.5 <= x <= w - pad + 0.5 and pad - 0.5 <= y <= h - pad + 0.5

    # Eight tiles east (768 px at 96, past the view): zoomed out and centred so you and it are both in view.
    G.Target("waypoint", 40.0, 49.0)
    sim.MoveCursorTo(UI.Window.view)
    sim.Run(3)
    assert cam.zoom < z0 * 0.95 and framed(you.col, you.row) and framed(40.0, 49.0) and UI.Path.pieces > 0
    assert UI.saved.path.zoom == z0 and UI.Camera.follow
    mm = ns.Model.minimap  # while the line's drawn Blizzard's blips step aside: our zoom, no steps (game/Minimap.lua)
    assert mm.overlaid is None and mm.steps is None and ns.Game.minimap.engaged
    zf, cx = cam.zoom, cam.cx
    # Your drag holds it where you leave it, under the cursor however long; left alone 3 s, it comes back.
    sim.Drag(UI.Window.view, -200, 0)
    sim.Run(8)
    assert not UI.Camera.follow and cam.cx > cx + 1
    sim.cursorX, sim.cursorY = 5, 5
    sim.Run(2)
    assert UI.Camera.follow and abs(cam.cx - cx) < 0.01 and abs(cam.zoom - zf) < 0.5
    sim.Drag(UI.Window.view, -200, 0)
    sim.cursorX, sim.cursorY = 5, 5
    sim.Run(2.5)
    assert not UI.Camera.follow and cam.cx > cx + 1
    sim.Run(2)
    assert UI.Camera.follow and abs(cam.cx - cx) < 0.01
    # Your zoom too: it stands, then the framing's comes back.
    UI.Motion.ZoomStep(2)
    sim.Run(1.5)
    assert cam.zoom > zf * 1.5
    sim.Run(4)
    assert abs(cam.zoom - zf) < 0.5 and framed(40.0, 49.0)
    # Near now: in, as far as the map goes (still framed).
    G.Target("waypoint", 32.2, 49.75)
    sim.Run(4)
    assert cam.zoom > z0 and abs(cam.zoom - UI.Motion.MAX_ZOOM) < 0.5 and framed(32.2, 49.75)
    # On the big map: the view's yours.
    G.Target("waypoint", 40.0, 49.0)
    UI.BigMap.Toggle()
    sim.Run(2)
    z1, cx1 = cam.zoom, cam.cx
    sim.Run(2)
    assert UI.View().window.big and cam.zoom == z1 and cam.cx == cx1 == you.col
    UI.BigMap.Toggle()
    sim.Run(3)
    # Arrived: the framing ends, the zoom back to where it began.
    assert cam.zoom < z0 * 0.95
    G.Tgt.inside = True
    sim.Run(3)
    assert abs(cam.zoom - z0) < 0.5 and cam.cx == you.col
    assert not errors(sim, ns), errors(sim, ns)


def test_corpse_forces_follow():
    # Not following, saved; a ghost, your corpse already the target when the map first looks: your choice kept.
    L, sim, ns, G = client(saved=TEST_UI.replace("zoom = 96,", "zoom = 96, follow = false,"), shown=False)
    Camera, Motion = ns.UI.Camera, ns.UI.Motion
    sim.units.player.dead, sim.ghost = True, True
    G.Target("corpse", 31.0, 49.75, "Your corpse")
    sim.Slash("/mm toggle")
    sim.Run(1)
    assert not Camera.follow
    sim.units.player.dead, sim.ghost = False, False  # alive again, another target: still not
    G.Target("waypoint", 33.0, 49.75, "Waypoint")
    sim.Run(1)
    assert not Camera.follow
    sim.units.player.dead, sim.ghost = True, True  # you've died and released: back to you, gliding
    G.Target("corpse", 31.0, 49.75, "Your corpse")
    sim.Run(0.25)
    you = ns.Model.you
    assert not Camera.follow and Motion.Goal()[1] == you.col  # flying there
    sim.Run(1)
    assert Camera.follow and Camera.cam.cx == you.col
    # Browsing another continent (no target there) and back: the corpse found already, the pick kept.
    G.Tgt = False
    sim.Slash("/mm map 1")
    sim.Run(1)
    G.Target("corpse", 31.0, 49.75, "Your corpse")
    sim.Slash("/mm map 0")
    sim.Run(1.5)
    assert not Camera.follow
    assert not errors(sim, ns), errors(sim, ns)


def test_title_target():
    L, sim, ns, G = client()
    UI = ns.UI
    UI.Feel.Set("title.rest", "zone,subzone"); UI.Feel.Set("title.hover", "zone,subzone,coords,target")  # (the title as it was)
    sub = ns.UI.Title.subtitle
    text = lambda: sub.GetText(sub)  # noqa: E731
    G.Target("waypoint", 33.0, 49.75, "Waypoint")
    sim.Run(0.2)  # small, hovered: the target with where you are
    yd = math.floor(1.05 * YD + 0.5)
    assert text().startswith("Goldshire" + SEP) and text().endswith(SEP + f"|cffffd27fWaypoint|r")
    sim.cursorX, sim.cursorY = 10, 10  # small, not hovered: where you are, nothing more
    sim.Run(0.2)
    assert text() == "Goldshire"
    sim.Press("M")  # big: the target
    sim.Run(0.5)
    assert text().endswith(SEP + f"|cffffd27fWaypoint|r") and text().count(SEP) == 2
    G.Tgt.inside = True
    sim.Run(0.1)
    assert text().endswith(SEP + "|cffffd27fWaypoint|r here")
    G.Target("quest", 32.0, 49.75)  # untitled
    sim.Run(0.1)
    assert text().endswith(SEP + f"|cffffd27fTarget|r")
    assert not errors(sim, ns), errors(sim, ns)


def test_corpse_waypoint_pins():
    L, sim, ns, G = client(shown=False)
    # Your corpse where the client has it (read on PLAYER_DEAD), a waypoint set: Game's parts, then Model's kinds.
    L.execute("""local ns, sim, col, row = ...
        sim.corpse = { [1415] = CreateVector2D(ns.Atlas.TileToMap(1415, col, row)) }
        ns.Game.Command({ kind = "waypoint", pos = { inst = 0, col = col + 0.3, row = row } })""", ns, sim, 31.95, 49.75)
    sim.FireEvent("PLAYER_DEAD")
    sim.Slash("/mm toggle")
    sim.Run(1.5)
    S, UI = sim.state, ns.UI
    p = UI.Corpse.front.pools.pin
    corpse = p[p.at.corpse]
    assert S[corpse].width == 22 and S[corpse.ring].atlas == "UI-QuestPoi-QuestNumber" and S[corpse.ring].shown
    assert S[corpse.icon].atlas == "deathrecap-icon-tombstone"
    assert abs(S[corpse.icon].width - 22 * 0.6 * 15 / 20) < 1e-9 and abs(S[corpse.icon].height - 22 * 0.6) < 1e-9
    p = UI.Waypoint.front.pools.pin
    wp = p[p.at.waypoint]
    assert S[wp].width == 22 and S[wp.icon].atlas == "Waypoint-MapPin-Tracked" and S[wp.icon].width == 22
    assert not (wp.ring and S[wp.ring].shown)

    # Their tooltips, the spike's.
    tip, view = L.globals().GameTooltip, UI.Window.view
    sim.MoveCursorTo(view)  # on the view's centre: you, on your corpse
    sim.FireScript(view, "OnEnter", False)
    sim.Run(0.2)
    lines = S[tip].lines
    assert S[tip].shown and S[lines[1]].text.endswith("Your corpse") and tip.NumLines(tip) == 1
    sim.cursorX += 0.3 * UI.Camera.cam.zoom * view.GetEffectiveScale(view)
    sim.Run(0.2)
    assert tip.NumLines(tip) == 1 and S[lines[1]].text.endswith("  Waypoint")  # (no hint: its popup clears it)

    sim.Slash("/mm layer corpse")  # turned off (the gear's You: Corpse, Waypoint): gone
    sim.Run(0.5)
    assert S[UI.Corpse.canvases[1]].alpha == 0 and S[UI.Corpse.canvases[2]].alpha == 0
    assert not errors(sim, ns), errors(sim, ns)


def test_path_walk_laid_as_new():
    """Walking (the dashes on legs that didn't move left as they stand; past MAX_PIECES, half of them a frame),
    the line ends as a new layout from where you stop lays it out, dot for dot (within a pixel, and 0.05 of
    alpha in the fade by you: the last layout was at the last half pixel you moved, its ends rounded; the dots
    all but unseen there, under 0.1, left out: one more or less fits by that half pixel)."""
    def ends(L, sim, ns, G):
        cam = ns.UI.Camera.cam
        return [(cam.cx + d[0] / cam.zoom, cam.cy + d[1] / cam.zoom, cam.cx + d[2] / cam.zoom, cam.cy + d[3] / cam.zoom, d[4])
                for d in dashes(G, 1.6) if d[4] > 0.1]

    def matched(a, b, zoom):
        px = 1.01 / zoom
        return all(any(all(abs(x[k] - y[k]) <= px for k in range(4)) and abs(x[4] - y[4]) <= 0.05 for y in b) for x in a)

    def line(zoom, at=None):
        L, sim, ns, G = client()
        ns.UI.Motion.SetZoom(zoom)
        sim.player.facing = 3 * math.pi / 2  # east
        if at:
            sim.player.col, sim.player.row = at
        G.Target("waypoint", 35.5, 49.6, "Waypoint")
        G.Route(L.table_from([L.table_from(q) for q in [(32.4, 49.9), (33.0, 49.9), (33.6, 49.7), (34.5, 49.6), (35.5, 49.6)]]))
        sim.Run(1)
        return L, sim, ns, G

    for zoom in (120, 400):  # (under MAX_PIECES, and past it)
        L, sim, ns, G = walked = line(zoom)
        sim.player.speed = 7  # toward it
        sim.Run(2)
        sim.player.speed = 0
        sim.Run(0.2)
        new = line(zoom, (sim.player.col, sim.player.row))
        a, b = ends(*walked), ends(*new)
        assert len(a) > 30 and abs(len(a) - len(b)) <= 1 and matched(a, b, zoom) and matched(b, a, zoom), (zoom, len(a), len(b))
        assert not errors(sim, ns), errors(sim, ns)


def test_path_walk_alloc():
    L, sim, ns, G = client()
    P = ns.UI.Path
    ns.UI.Motion.SetZoom(384)
    G.Target("waypoint", 34.5, 49.6, "Waypoint")
    G.Route(L.table_from([L.table_from(q) for q in [(32.4, 49.9), (33.0, 49.9), (33.6, 49.7), (34.0, 49.6), (34.5, 49.6)]]))
    sim.Run(6)  # past login's grace
    sim.player.facing, sim.player.speed = 3 * math.pi / 2, 7  # east
    sim.Run(1)
    draws, done = P.draws, stretch(L, ns)
    sim.Run(10)
    sim.player.speed = 0
    kb, by = done()
    print(f"walking with a route: {kb} KB/s, {P.draws - draws} layouts of the line; map: path {by.get('map: path', 0)} KB/s")
    # The path's own: none to speak of (its lines made at load).
    assert P.draws - draws > 60 and by.get("map: path", 0) <= 2 and kb <= 50
    assert not errors(sim, ns), errors(sim, ns)


def slow(fs):
    return {e.name: e.max for e in fs.slow.values()}


# lua: our own Lua charged too (sim.LUA_PRICE, R-P2's 10 ns an instruction). Then the line's own budgets hold
# (map: path never in perf.slow, its first layout within CALL_MS, at rest p95 ≤ 1); the zoom state's p95 is
# held on the priced clock alone (with our Lua: printed).
@pytest.mark.parametrize("lua", [False, True])
def test_path_priced(lua):
    L, sim, ns, G = client(lua=lua)
    sim.Run(5)  # past login's grace and the first open's
    G.Target("waypoint", 40.0, 47.0, "Waypoint")
    G.Route(L.table_from([L.table_from(q) for q in [(33.0, 49.0), (35.0, 48.5), (37.0, 48.0), (38.5, 47.5), (40.0, 47.0)]]))
    sim.Price(True)
    sim.Run(1)
    view = ns.UI.Window.view
    for n in (4, -4, 6, -6):
        for _ in range(abs(n)):
            sim.Wheel(view, 1 if n > 0 else -1)
            sim.Step()
        sim.Run(1)
    sim.player.facing, sim.player.speed = 3 * math.pi / 2, 7  # east
    sim.Run(5)
    sim.player.speed = 0
    sim.Drag(view, 300, 100, 20)
    sim.Run(1)
    sim.Price(False)
    fs = ns.Runtime.FrameStats()
    by = {k: v for k, v in fs.byState.items()}
    path = ns.Runtime.Perf()[0]["map: path"].max
    print(f"long route, priced{' with Lua' if lua else ''}: "
          + ", ".join(f"{k} {v.frames} p95 {v.p95} max {v.max}" for k, v in sorted(by.items()))
          + f"; map: path max {path:.2f} ms; slow {slow(fs)}")
    assert by["small"].p95 <= 1 and by["drag"].p95 <= 5 and fs.max <= 8 and path <= 2 and "map: path" not in slow(fs)
    if not lua:
        assert by["zoom"].p95 <= 5 and not slow(fs)
    assert not errors(sim, ns), errors(sim, ns)


@pytest.mark.parametrize("lua", [False, True])
def test_path_priced_big(lua):
    L, sim, ns, G = client(lua=lua)
    sim.Run(5)  # past login's grace and the first open's
    sim.Press("M")
    sim.Run(3)
    UI = ns.UI
    w, h = UI.Window.Size()
    col, row = ns.Atlas.Camera.ScreenToTile(UI.Camera.cam, w, h, w - 10, 10)
    sim.Price(True)
    G.Target("waypoint", col, row, "Waypoint")
    sim.Run(1)
    first = ns.Runtime.Perf()[0]["map: path"].max
    view = UI.Window.view
    for n in (4, -4, 6, -6):
        for _ in range(abs(n)):
            sim.Wheel(view, 1 if n > 0 else -1)
            sim.Step()
        sim.Run(1)
    for _ in range(2):  # M: shrink and grow again, the line across the way
        sim.Press("M")
        sim.Run(2)
    sim.Price(False)
    fs = ns.Runtime.FrameStats()
    by = {k: v for k, v in fs.byState.items()}
    path = ns.Runtime.Perf()[0]["map: path"].max
    print(f"big, a corner waypoint, priced{' with Lua' if lua else ''}: the first layout {first:.2f} ms, {UI.Path.pieces} pieces; "
          + ", ".join(f"{k} {v.frames} p95 {v.p95} max {v.max}" for k, v in sorted(by.items()))
          + f"; map: path max {path:.2f} ms; slow {slow(fs)}")
    assert first <= 2 and by["big"].p95 <= 1 and fs.max <= 8 and path <= 2 and "map: path" not in slow(fs)
    if not lua:
        assert by["zoom"].p95 <= 5 and not slow(fs)
    assert not errors(sim, ns), errors(sim, ns)


@pytest.mark.parametrize("lua", [False, True])
def test_path_walk_big(lua):
    """Script (c)'s c2: the big window at zoom 400, a waypoint at Lakeshire (Model's own target and route,
    from Game's waypoint), walking east 10 s: the line past MAX_PIECES, each dash re-spaced as you go."""
    c = S.boot(priced=True, lua=lua)
    c.slash("/mm toggle")
    c.run(6)
    c.press("M")
    c.run(3)
    c.lua("ns.UI.Motion.SetZoom(400)")
    c.lua("ns.UI.Feel.Set('path.frame', false)")  # (the line's cost at zoom 400: no framing to zoom out to Lakeshire)
    c.run(3)
    c.lua("ns.UI.Track.Start({ kind = 'place', key = 'lake', name = 'Lakeshire', pos = { inst = 0, col = 36.09, row = 49.28 } }, true)")
    c.run(3)
    P, ns = c.ns.UI.Path, c.ns
    draws = P.draws
    c.walk(10, "east")
    fs = ns.Runtime.FrameStats()
    print(f"walking, big, zoom 400{' with Lua' if lua else ''}: {P.draws - draws} layouts, {P.pieces} pieces; big p95 "
          f"{fs.byState.big.p95} max {fs.byState.big.max}; map: path max {ns.Runtime.Perf()[0]['map: path'].max:.2f} ms")
    assert P.draws - draws > 50 and P.pieces == 160 and not ns.Model.Route().straight
    # (1.1 with our Lua: the rounder route (5 chunks a corner) re-spaces a little more of it: 1.05 priced)
    assert fs.byState.big.p95 <= (1.1 if lua else 1) and "map: path" not in slow(fs) and fs.max <= 8
    assert not c.errors(), c.errors()


def test_arrived_finishes():
    """Within 5 yards of what you track or path to, it's finished: the tracking, the pathing and the waypoint gone."""
    L, sim, ns = boot()
    sim.Slash("/mm toggle")
    sim.Run(1)
    UI, you = ns.UI, ns.Model.you
    away = L.table_from({"key": "t:1", "name": "Spot", "pos": L.table_from(
        {"inst": you.inst, "col": you.col + 0.05, "row": you.row})})  # ~27 yd east
    UI.Track.Start(away, True)
    sim.Run(1)
    assert UI.saved.tracked is not None and UI.saved.path is not None
    near = L.table_from({"key": "t:2", "name": "Here", "pos": L.table_from(
        {"inst": you.inst, "col": you.col + 0.005, "row": you.row})})  # ~3 yd
    UI.Track.Start(near, True)
    sim.Run(1)
    assert UI.saved.tracked is None and UI.saved.path is None and not ns.Model.Target()
    assert not errors(sim, ns), errors(sim, ns)

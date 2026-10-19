"""The way to the target on the simulated client (docs/v1-plan.md M3.3: ui/Path.lua; ui/You.lua's corpse and
waypoint pins and the title's target), Model.Target and Model.Route stubbed as typed (types/model.lua):

  test_path_line: the hand-inked dashes (S55-S57): light 1.6 px over a dark 3.4 px edge, laid back from the
    target 6 px on, 4 off, 14 px clear of you and 15 of the target, faded at the ends, uneven; along the route
    when there is one; gone once you're inside the target's area, or without a target (F33).
  test_path_redraws: nothing laid out again standing (no widget call); a turn past 3°, a zoom, a new route
    (not the same one handed again) and a walk lay it out again; a pan carries it along, the dashes shown
    left as they stand, those it brings in shown (S58).
  test_path_cap: a long line at zoom 800: 160 pieces at most, only those near the view shown, every line's
    end within 4096 px of its canvas (S56; docs/v1-plan.md §2).
  test_edge_arrow: a target off the view gets the gold arrow 16 px inside the edge where the line toward it
    leaves (along the route's leg that does), pointing on; none on the view or inside (F34, S59).
  test_corpse_forces_follow: your corpse becoming the target glides the view back to you; another target
    doesn't, nor the one you had when the map first looked (F7, F42).
  test_title_target: the subtitle's "<title> N yd" and "<title> here", big or small and hovered (S12).
  test_corpse_waypoint_pins: Known("corpse") and Known("waypoint") as pins (S49), their tooltips, their gear rows.
  test_path_walk_alloc: walking with a route, the line laid out again as you go: the whole ≤ 50 KB/s (the
    M3.3 Verify), the path's own only its lines made as dashes first come into view.
  test_path_priced: a long winding route at the client's prices, zooming in and out (the line laid out each
    frame the zoom moves), walking and dragging: within the frame budgets, no call over 2 ms.
"""
import math

from test_addon import boot, errors
from test_quest_areas import stretch
from sim import TEST_UI

SETUP = """
local Sim, ns = ...
local UI, S = ns.UI, Sim.state
Tgt, Way = false, nil
ns.Model.Target = function() return Tgt end
ns.Model.Route = function() return Way end
Sim.player.facing = -math.pi / 2 -- east (the client's facing: counter-clockwise from north)
-- A target of kind at tile (col, row) on your map.
function Target(kind, col, row, title)
	Tgt = { kind = kind, key = kind .. ":" .. col .. "," .. row, pos = { inst = 0, col = col, row = row }, title = title }
	return Tgt
end
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
-- The path's lines shown of a thickness: { ax, ay, bx, by, alpha } in px from the view's centre, y down.
function Dashes(thick)
	local c, out = S[UI.Path.canvas].points[1], {}
	for _, r in ipairs(Lines()) do
		local st = S[r]
		if st.shown and st.thickness == thick then
			out[#out + 1] = { c.x + st.startPoint[3], -(c.y + st.startPoint[4]), c.x + st.endPoint[3],
				-(c.y + st.endPoint[4]), st.color[4] }
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


def client(saved=None, shown=True):
    L, sim, ns = boot(saved)
    L.execute(SETUP, sim, ns)
    if shown:
        sim.Slash("/mma toggle")
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
    G.Target("waypoint", 33.0, 49.75, "Waypoint")  # 1.05 tiles east of you: 100.8 px at 96
    sim.Run(0.2)
    strokes, washes = dashes(G, 1.6), dashes(G, 3.4)
    assert len(strokes) == len(washes) == P.pieces == 8
    end = (33.0 - 31.95) * z
    for (ax, ay, bx, by, a), (wax, way, wbx, wby, wa) in zip(sorted(strokes), sorted(washes)):
        assert (ax, ay, bx, by) == (wax, way, wbx, wby) and 0 < a <= 0.7 and 0 < wa <= 0.3
        assert 13 <= ax < bx <= end - 14 and bx - ax <= 6 and abs(ay) <= 1.5 and abs(by) <= 1.5
    assert sorted(strokes)[-1][2] - sorted(strokes)[-2][2] == 10  # laid back from the target, 10 apart
    assert len({d[4] for d in strokes}) > 3  # faded at its ends, uneven along it
    lines = [r for r in P.canvas.GetRegions(P.canvas) if S[r].shown]
    assert {(S[r].thickness,) + tuple(S[r].color[i] for i in range(1, 4)) for r in lines} == {(1.6, 1, 0.93, 0.76),
                                                                                             (3.4, 0.12, 0.08, 0.03)}

    # Along a route: north, then east, then south to it (facing north: no lead-in curve to speak of).
    sim.player.facing = 0
    pts = [(31.95, 49.2), (33.0, 49.2), (33.0, 49.75)]
    G.Route(L.table_from([L.table_from(p) for p in pts]))
    sim.Run(0.2)
    view = [(0, 0)] + [((c - 31.95) * z, (r - 49.75) * z) for c, r in pts]
    strokes = dashes(G, 1.6)
    assert len(strokes) > 15 and all(off_line(view, x, y) <= 1.5 for d in strokes for x, y in (d[:2], d[2:4]))

    # Inside its area: arrived, the line steps aside; no target, none.
    G.Tgt.inside = True
    sim.Step()
    assert dashes(G, 1.6) == [] and dashes(G, 3.4) == []
    G.Tgt.inside = None
    sim.Step()
    assert len(dashes(G, 1.6)) > 15
    G.Tgt = False
    sim.Step()
    assert dashes(G, 1.6) == [] and P.pieces == 0
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
    assert P.pieces == 160 and 0 < len(strokes) < 160  # 40 px apart, 24 long; only those near the view
    assert all(abs(x) <= w + 24 and abs(y) <= h for d in strokes for x, y in (d[:2], d[2:4]))
    c = S[P.canvas].points[1]
    assert abs(c.x) <= 4096 and abs(c.y) <= 4096
    for r in P.canvas.GetRegions(P.canvas):
        if S[r].shown:
            assert max(abs(S[r].startPoint[3]), abs(S[r].startPoint[4]), abs(S[r].endPoint[3]), abs(S[r].endPoint[4])) <= 4096
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


def test_corpse_forces_follow():
    # Not following, saved; your corpse already the target when the map first looks: your choice kept.
    L, sim, ns, G = client(saved=TEST_UI.replace("zoom = 96,", "zoom = 96, follow = false,"), shown=False)
    Camera = ns.UI.Camera
    G.Target("corpse", 31.0, 49.75, "Your corpse")
    sim.Slash("/mma toggle")
    sim.Run(1)
    assert not Camera.follow
    G.Target("waypoint", 33.0, 49.75, "Waypoint")  # another target: still not
    sim.Run(1)
    assert not Camera.follow
    G.Target("corpse", 31.0, 49.75, "Your corpse")  # you've died and released: back to you, gliding
    sim.Run(0.25)
    you = ns.Model.you
    assert not Camera.follow and ns.UI.Motion.Goal()[1] == you.col  # flying there
    sim.Run(1)
    assert Camera.follow and Camera.cam.cx == you.col
    assert not errors(sim, ns), errors(sim, ns)


def test_title_target():
    L, sim, ns, G = client()
    sub = ns.UI.Title.subtitle
    text = lambda: sub.GetText(sub)  # noqa: E731
    G.Target("waypoint", 33.0, 49.75, "Waypoint")
    sim.Run(0.2)  # small, hovered: the target with where you are
    yd = math.floor(1.05 * YD + 0.5)
    assert text().startswith("Goldshire" + SEP) and text().endswith(SEP + f"|cffffd27fWaypoint|r {yd} yd")
    sim.cursorX, sim.cursorY = 10, 10  # small, not hovered: where you are, nothing more
    sim.Run(0.2)
    assert text() == "Goldshire"
    sim.Press("M")  # big: the target
    sim.Run(0.5)
    assert text().endswith(SEP + f"|cffffd27fWaypoint|r {yd} yd") and text().count(SEP) == 2
    G.Tgt.inside = True
    sim.Run(0.1)
    assert text().endswith(SEP + "|cffffd27fWaypoint|r here")
    G.Target("quest", 32.0, 49.75)  # untitled
    sim.Run(0.1)
    assert text().endswith(SEP + f"|cffffd27fTarget|r {math.floor(0.05 * YD + 0.5)} yd")
    assert not errors(sim, ns), errors(sim, ns)


def test_corpse_waypoint_pins():
    L, sim, ns, G = client(shown=False)
    sim.atlases["deathrecap-icon-tombstone"] = sim.atlases["Waypoint-MapPin-Tracked"] = True
    L.execute("""local ns, col, row = ...
        local t = { corpse = { { key = "corpse", kind = "corpse", name = "Corpse", live = true, pos = { inst = 0, col = col, row = row } } },
            waypoint = { { key = "waypoint", kind = "waypoint", name = "Waypoint", live = true,
                pos = { inst = 0, col = col + 0.3, row = row } } } }
        ns.Model.Kind("corpse", function() return t.corpse, 1 end)
        ns.Model.Kind("waypoint", function() return t.waypoint, 1 end)""", ns, 31.95, 49.75)
    sim.Slash("/mma toggle")
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
    assert S[tip].shown and S[lines[1]].text == "Your corpse" and tip.NumLines(tip) == 1
    sim.cursorX += 0.3 * UI.Camera.cam.zoom * view.GetEffectiveScale(view)
    sim.Run(0.2)
    assert tip.NumLines(tip) == 2 and S[lines[1]].text == "Waypoint" and S[lines[2]].text == "Ctrl-right-click the map to clear"

    sim.Slash("/mma layer corpse")  # turned off (the gear's You: Corpse, Waypoint): gone
    sim.Run(0.5)
    assert S[UI.Corpse.canvases[1]].alpha == 0 and S[UI.Corpse.canvases[2]].alpha == 0
    assert not errors(sim, ns), errors(sim, ns)


def test_path_walk_alloc():
    L, sim, ns, G = client()
    P = ns.UI.Path
    ns.UI.Motion.SetZoom(384)
    G.Target("waypoint", 34.5, 49.6, "Waypoint")
    G.Route(L.table_from([L.table_from(q) for q in [(32.4, 49.9), (33.0, 49.9), (33.6, 49.7), (34.0, 49.6), (34.5, 49.6)]]))
    sim.Run(6)  # past login's grace
    sim.player.facing, sim.player.speed = math.pi / 2, 7  # (east, the sim's way)
    sim.Run(1)
    draws, done = P.draws, stretch(L, ns)
    sim.Run(10)
    sim.player.speed = 0
    kb, by = done()
    print(f"walking with a route: {kb} KB/s, {P.draws - draws} layouts of the line; map: path {by.get('map: path', 0)} KB/s")
    # The path's own: a dash's lines made as it first comes into view (the far end's, walking toward it: at
    # most MAX_PIECES each, the sim's region state ~4.7 KB a pair).
    assert P.draws - draws > 60 and by.get("map: path", 0) <= 5 and kb <= 50
    assert not errors(sim, ns), errors(sim, ns)


def test_path_priced():
    L, sim, ns, G = client()
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
    sim.player.facing, sim.player.speed = math.pi / 2, 7
    sim.Run(5)
    sim.player.speed = 0
    sim.Drag(view, 300, 100, 20)
    sim.Run(1)
    sim.Price(False)
    fs = ns.Runtime.FrameStats()
    by = {k: v for k, v in fs.byState.items()}
    print("long route, priced: " + ", ".join(f"{k} {v.frames} p95 {v.p95} max {v.max}" for k, v in sorted(by.items()))
          + f"; map: path max {ns.Runtime.Perf()[0]['map: path'].max:.2f} ms")
    assert by["small"].p95 <= 1 and by["zoom"].p95 <= 5 and by["drag"].p95 <= 5 and fs.max <= 8
    assert not list(fs.slow.values()), list(fs.slow.values())
    assert not errors(sim, ns), errors(sim, ns)

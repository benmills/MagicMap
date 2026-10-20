-- P1: borders fall behind a fast pan. A 1.5 views/s fling on the counted clock (3 us a widget call):
-- the layouts share a frame's budget, a layer the view lacks first (4.5 ms a frame, else 4), laid out with
-- more margin ahead of the camera's speed and again before the view 0.3 s ahead leaves it (ui/Engine.lua).
-- The M1 exit: borders cover the view on >= 97% of frames, tiles >= 99%, every layer fresh 1 s after
-- stopping, no layout frame over 8 ms; after it, each canvas holds what it shows (the rest parked).
-- Then a 20-step zoom-out, one step a frame (96 to 16 px a tile): layouts started per layer (the
-- spike's ~44 for 4 layers, 33 for 5 before M1.3): a held layer (borders) once, where the zoom lands;
-- the others once a crossing of their band (tiles [0.7, 1.4], 5 here at most; names and pins a
-- log(1.25) drift, 8) and once settled. Last, a long pan
-- at 800 px a tile, ~45 views from you: the shared origin moves with the layouts, so no offset on the
-- map passes 4096 px (T.Anchors, the canvases' included, as set and as each frame ends; the arrow kept by
-- the view), however far the view goes, nor after a zoom's jump, nor with the wheel a tick an event
-- (M1.14) in the small window and the big, priced, no frame over 8 ms nor call over its budget: 16 to 800
-- and back at a notch a frame, a flick out from 800 about the cursor, a drag, a flick and a grow, and
-- flicks in from 16 toward a corner (a canvas laid out nowhere near the view, or whose offsets the zoom
-- would take past 4,000 px, is left where it stands, hidden, and laid out first).
local T = ...
local MAX_MS = 8 -- a layout's slowest frame: 2x its budget (Runtime's overrun for a job; test_zoom.py)
local function R2(v) return math.floor(v * 100 + 0.5) / 100 end
local sim, ns = T.Boot()
sim.Run(1)
sim.Slash("/mm toggle")
sim.Run(3)
local m, layers = ns.UI.Camera, {}
for _, lay in ipairs(ns.UI.Engine.layers) do -- (those on: one off by default, as the shade, lays nothing out)
	if lay.on then layers[#layers + 1] = lay end
end
for _, lay in ipairs(layers) do -- the first open's layouts done: maxima from here
	ns.Runtime.Perf()["map: " .. lay.name].max = 0
end
local w = ns.UI.Window.Size()
local hx, hy = m.cam.cx, m.cam.cy -- (you)
m.follow = false
local covered = {}
for _, lay in ipairs(layers) do covered[lay.name] = 0 end
for _ = 1, 180 do
	m.cam.cx = m.cam.cx + w * 1.5 / 60 / m.cam.zoom
	sim.Step()
	for _, lay in ipairs(layers) do
		if T.Fresh(ns, lay) then covered[lay.name] = covered[lay.name] + 1 end
	end
end
sim.Run(1)
local perf = ns.Runtime.Perf()
local worst, shown = {}, {}
for _, lay in ipairs(layers) do
	worst[lay.name] = R2(perf["map: " .. lay.name].max)
	shown[#shown + 1] = string.format("%s %d / %.2f ms", lay.name, covered[lay.name], worst[lay.name])
end
T.Print("P1: frames covered of 180 at 1.5 views/s / job max ms: %s", table.concat(shown, ", "))
assert(covered.borders >= 175 and covered.tiles >= 179, "covered: borders " .. covered.borders .. ", tiles " .. covered.tiles)
for _, lay in ipairs(layers) do assert(T.Fresh(ns, lay), lay.name) end
for name, ms in pairs(worst) do assert(ms <= MAX_MS, name .. " " .. ms) end
assert(#T.Errors(sim, ns) == 0)

-- After the swaps: a front canvas holds its live regions (and their masks) and nothing else.
for _, lay in ipairs(layers) do
	local c, live, masks = lay.front, 0, 0
	for _, p in pairs(c.pools) do
		live = live + p.n
		for i = 1, p.n do
			if p[i].mask then masks = masks + 1 end
		end
	end
	local held = { MaskTexture = 0, other = 0 }
	for _, f in ipairs({ c, unpack(T.Values(c.mins)) }) do -- (and its frames for a minimum zoom's: Engine.At)
		for _, r in ipairs(sim.state[f].regions) do
			local k = sim.state[r].type == "MaskTexture" and "MaskTexture" or "other"
			held[k] = held[k] + 1
		end
	end
	assert(held.other == live and held.MaskTexture == masks,
		string.format("%s: %d regions, %d masks on its canvas; %d live, %d masks", lay.name, held.other, held.MaskTexture, live, masks))
end

-- The zoom-out: layouts started per layer, counted as traced (the ring keeps 300).
local zoom = m.cam.zoom
local crossings = { scale = math.floor(math.log(zoom / 16) / math.log(1 / 0.7)),
	move = math.floor(math.log(zoom / 16) / math.log(ns.UI.Engine.DRIFT)) }
crossings.pin = crossings.move
local started, trace = {}, ns.Runtime.Trace
ns.Runtime.Trace = function(kind, d)
	if kind == "layout" and d.e == "start" then started[d.layer] = (started[d.layer] or 0) + 1 end
	return trace(kind, d)
end
for _ = 1, 20 do
	ns.UI.Motion.ZoomStep(-1) -- the zoom-out button's tick, a frame apart (a fast wheel's too)
	sim.Step()
end
sim.Run(2)
ns.Runtime.Trace = trace
local total, each = 0, {}
for _, lay in ipairs(layers) do
	local n = started[lay.name] or 0
	total = total + n
	each[#each + 1] = lay.name .. " " .. n
	assert(lay.zoom == "hold" and n == 1 or lay.zoom ~= "hold" and n <= crossings[lay.zoom] + 1, lay.name .. ": " .. n .. " layouts")
end
T.Print("P1: 20-step zoom-out, %.0f to %.0f px a tile: %d layouts started for %d layers (%s)", zoom, m.cam.zoom, total,
	#layers, table.concat(each, ", "))
assert(m.cam.zoom == 16)
for _, lay in ipairs(layers) do assert(T.Fresh(ns, lay), lay.name) end

-- The long pan: 0.75 views a second for 10 s at the top zoom.
for _ = 1, 15 do ns.UI.Motion.ZoomStep(1) end -- (16 to 800)
sim.Run(2)
local x0, origins, ox = m.cam.cx, 0, ns.UI.Engine.ox
for _ = 1, 600 do
	m.cam.cx = m.cam.cx + w * 0.75 / 60 / m.cam.zoom
	sim.Step()
	if ns.UI.Engine.ox ~= ox then origins, ox = origins + 1, ns.UI.Engine.ox end
end
sim.Run(1)
T.Print("P1: a long pan at %.0f px a tile, %.1f tiles: the origin moved %d times", m.cam.zoom, m.cam.cx - x0, origins)
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n"))
assert(m.cam.zoom == 800 and origins >= 2)
for _, lay in ipairs(layers) do assert(T.Fresh(ns, lay), lay.name) end

-- A zoom's jump (ui/BigMap.lua: a shrink with you unknown, the window's first placing), 96 to 800 and
-- back: a label in view before it is moved off the view, not 8x as far out.
ns.UI.Motion.SetZoom(96)
m.cam.cx, m.cam.cy = hx, hy
sim.Run(1)
for _, z in ipairs({ 800, 96, 800 }) do
	ns.UI.Motion.SetZoom(z)
	sim.Run(1)
end
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n"))

local view = ns.UI.Window.view
local function Wheel(d, n, fx, fy)
	for _ = 1, n do
		sim.MoveCursorTo(view, fx or 0.5, fy or 0.5)
		sim.FireScript(view, "OnMouseWheel", d)
		sim.Step()
	end
	sim.Run(2)
end
-- The wheel a notch a frame: following, 16 to 800 and back; free, a flick out from 800 about a corner and
-- back in, a drag, a flick and a grow under it; then flicks in from 16 toward corners (the view's centre
-- running from the origin, names and pins a few drifts behind before M1b's second review: 4,471 px).
local function Wheels(corners)
	ns.UI.Motion.SetFollow(true)
	ns.UI.Motion.SetZoom(16)
	sim.Run(2)
	Wheel(1, 16)
	Wheel(-1, 16)
	ns.UI.Motion.SetFollow(false)
	ns.UI.Motion.SetZoom(800)
	sim.Run(2)
	Wheel(-1, 25, 0.8, 0.2)
	Wheel(1, 12)
	sim.MoveCursorTo(view, 0.5, 0.5)
	sim.buttonsDown.LeftButton = true
	sim.FireScript(view, "OnMouseDown", "LeftButton")
	for i = 1, 65 do
		sim.cursorX, sim.cursorY = sim.cursorX - 12, sim.cursorY + 4
		if i > 40 then sim.FireScript(view, "OnMouseWheel", -1) end
		sim.Step()
	end
	sim.buttonsDown.LeftButton = nil
	sim.FireScript(view, "OnMouseUp", "LeftButton")
	sim.Run(2)
	Wheel(1, 20)
	sim.Press("M")
	Wheel(-1, 10)
	sim.Press("M")
	sim.Run(1)
	ns.UI.Motion.SetFollow(false)
	for _, at in ipairs(corners) do
		Wheel(-1, 40)
		Wheel(1, 16, at[1], at[2])
	end
	assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n"))
end
-- On the priced clock (the client's prices: docs/evidence/perf-m0.md), the small window and the big:
-- calls over their budget counted (perf.slow).
local over, frames = {}, ns.Runtime.FrameStats().overruns
for name, p in pairs(ns.Runtime.Perf()) do over[name] = p.over end
sim.Price(true)
Wheels({ { 0.95, 0.95 }, { 0.9, 0.1 } })
sim.Press("M")
sim.Run(2)
Wheels({ { 0.7, 0.3 }, { 0.95, 0.95 } })
sim.Price(false)
local slow = {}
for name, p in pairs(ns.Runtime.Perf()) do
	if p.over > (over[name] or 0) then slow[#slow + 1] = string.format("%s x%d (%.1f ms)", name, p.over - (over[name] or 0), p.max) end
end
frames = ns.Runtime.FrameStats().overruns - frames
T.Print("P1: the wheel, priced, small and big: %d frames over 8 ms; calls over budget: %s", frames,
	#slow > 0 and table.concat(slow, ", ") or "none")
assert(frames == 0 and #slow == 0)

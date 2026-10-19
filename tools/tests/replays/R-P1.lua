-- P1: borders fall behind a fast pan. A 1.5 views/s fling on the counted clock (3 us a widget call):
-- one layout at a time, a layer the view lacks first (6 ms a frame, else 4), laid out with more
-- margin ahead of the camera's speed and again before the view 0.3 s ahead leaves it (ui/Engine.lua).
-- The M1 exit: borders cover the view on >= 97% of frames, tiles >= 99%, every layer fresh 1 s after
-- stopping, no layout frame over 8 ms; after it, each canvas holds what it shows (the rest parked).
-- Then a 20-step zoom-out, one step a frame (96 to 16 px a tile): layouts started per layer (the
-- spike's ~44 for 4 layers, 33 for 5 before M1.3): a held layer (borders) once, where the zoom lands;
-- the others once a crossing of the [0.7, 1.4] band (5 here at most) and once settled. Last, a long pan
-- at 800 px a tile, ~45 views from you: the shared origin moves with the layouts, so no offset on the
-- map passes 4096 px (T.Anchors; the arrow kept by the view), however far the view goes, nor after a
-- zoom's jump.
local T = ...
local MAX_MS = 8 -- a layout's slowest frame: 2x its budget (Runtime's overrun for a job; test_zoom.py)
local function R2(v) return math.floor(v * 100 + 0.5) / 100 end
local sim, ns = T.Boot()
sim.Run(1)
sim.Slash("/mma toggle")
sim.Run(3)
local m, layers = ns.UI.Camera, ns.UI.Engine.layers
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
	for _, r in ipairs(sim.state[c].regions) do
		local k = sim.state[r].type == "MaskTexture" and "MaskTexture" or "other"
		held[k] = held[k] + 1
	end
	assert(held.other == live and held.MaskTexture == masks,
		string.format("%s: %d regions, %d masks on its canvas; %d live, %d masks", lay.name, held.other, held.MaskTexture, live, masks))
end

-- The zoom-out: layouts started per layer, counted as traced (the ring keeps 300).
local zoom = m.cam.zoom
local crossings = math.floor(math.log(zoom / 16) / math.log(1 / 0.7))
local started, trace = {}, ns.Runtime.Trace
ns.Runtime.Trace = function(kind, d)
	if kind == "layout" and d.e == "start" then started[d.layer] = (started[d.layer] or 0) + 1 end
	return trace(kind, d)
end
for _ = 1, 20 do
	ns.UI.Motion.ZoomStep(-1) -- the zoom-out button's tick (the wheel's are rationed by time: M1.8b)
	sim.Step()
end
sim.Run(2)
ns.Runtime.Trace = trace
local total, each = 0, {}
for _, lay in ipairs(layers) do
	local n = started[lay.name] or 0
	total = total + n
	each[#each + 1] = lay.name .. " " .. n
	assert(lay.zoom == "hold" and n == 1 or lay.zoom ~= "hold" and n <= crossings + 1, lay.name .. ": " .. n .. " layouts")
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

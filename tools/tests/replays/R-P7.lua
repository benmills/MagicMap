-- P7: while an ease moved the camera, layers were laid out again every frame (three "is it moving"
-- flags, one disagreeing). The map reads one, Camera.ZoomSettled (the zoom unchanged 0.15 s; Settled
-- adds "nothing moving it"), and before it lays a layer out again only past [0.7, 1.4] of its layout's
-- zoom; a held layer (borders) where the zoom is headed (ui/Engine.lua). Replayed: a wheel tick and a
-- zone fit start at most 2 layouts a layer, at most 1 once settled; the borders' canvases are never
-- scaled. On the priced clock (docs/evidence/perf-m0.md), the flights (grow, shrink, the follow glide,
-- the idle return): no frame of ours over 8 ms, no swap over 4 ms, the map's allocation over each
-- (its regions made once, by a first grow); a drag's start on its own; the window shown again.
local T = ...
local sim, ns = T.Shown()
local E, Cam, M = ns.UI.Engine, ns.UI.Camera, ns.UI.Motion
local view = ns.UI.Window.view
local scaled = 0
for _, c in ipairs(T.Layer(ns, "borders").canvases) do
	local f = c.SetScale
	c.SetScale = function(...) scaled = scaled + 1; return f(...) end
end
-- Layouts started (by whether the zoom had settled) and the slowest swap, as traced.
local starts, swapMax, trace = {}, 0, ns.Runtime.Trace
ns.Runtime.Trace = function(kind, d)
	if kind == "layout" and d.e == "start" then
		local k = (Cam.ZoomSettled() and "settled " or "moving ") .. d.layer
		starts[k] = (starts[k] or 0) + 1
	elseif kind == "swap" then
		swapMax = math.max(swapMax, d.ms)
	end
	return trace(kind, d)
end

local function Ease(name, start)
	for k in pairs(starts) do starts[k] = nil end
	start()
	sim.Run(2)
	assert(Cam.Settled() and not E.pending, name .. ": still moving")
	local each = {}
	for _, l in ipairs(E.layers) do
		local a, b = starts["moving " .. l.name] or 0, starts["settled " .. l.name] or 0
		each[#each + 1] = string.format("%s %d+%d", l.name, a, b)
		assert(a + b <= 2 and b <= 1, name .. ": " .. each[#each])
	end
	T.Print("P7: %s: layouts while moving + once settled: %s", name, table.concat(each, ", "))
end
Ease("a wheel tick", function() sim.Wheel(view, 1) end)
Ease("a zone fit", function() M.FlyToRect(28, 46, 36, 52) end)
M.SetFollow(true)
sim.Run(1)

-- The flights on the priced clock: our frames (T.Ours: all of Runtime's) and the map's KB a second.
-- KB_S: the map's allocation a second over a flight (before M1.3 every frame of one laid all 5 layers
-- out: ~35 KB a frame, ~2000 KB/s); what's left is the layouts' own: a job each (~8 KB a layer a flight),
-- the big window's first layouts making their regions (M1.4: 60-125 KB/s, no per-line tables left).
local KB_S = 400
local read, P = T.Ours(sim), ns.Runtime.Perf()
local function MapKB()
	local kb = {}
	for name, p in pairs(P) do
		if name:sub(1, 5) == "map: " then kb[name:sub(6)] = p.kb end
	end
	return kb
end
local function Flight(name, seconds, start)
	sim.Price(true)
	swapMax = 0
	if start then start() end
	local kb0, worst, over = MapKB(), 0, 0
	for _ = 1, math.floor(seconds * 60) do
		sim.Step()
		local ms = select(5, read())
		worst = math.max(worst, ms)
		if ms > 8 then over = over + 1 end
	end
	sim.Price(false)
	local all, each = 0, {}
	for k, kb in pairs(MapKB()) do
		local d = kb - (kb0[k] or 0)
		all = all + d
		if d >= 1 then each[#each + 1] = string.format("%s %.0f", k, d) end
	end
	table.sort(each)
	T.Print("P7: %s, priced: slowest frame %.2f ms, %d over 8 ms; slowest swap %.2f ms; the map's %.0f KB/s (%s)", name,
		worst, over, swapMax, all / seconds, table.concat(each, ", "))
	assert(over == 0 and swapMax <= 4, name)
	assert(all / seconds <= KB_S, name .. ": " .. all / seconds .. " KB/s")
end
local function Drag(dx)
	sim.MoveCursorTo(view)
	sim.buttonsDown.LeftButton = true
	sim.FireScript(view, "OnMouseDown", "LeftButton")
	sim.cursorX = sim.cursorX + dx
	sim.Step()
	sim.buttonsDown.LeftButton = nil
	sim.FireScript(view, "OnMouseUp", "LeftButton")
end
sim.Press("M") -- once first: the big window's first layouts make its regions (pooled from then on)
sim.Run(1.5)
sim.Press("M")
sim.Run(1.5)
Flight("grow (M)", 1, function() sim.Press("M") end)
Flight("shrink (M)", 1, function() sim.Press("M") end)
Drag(-120)
sim.Run(1)
Flight("the follow glide", 1, function() M.SetFollow(true, true) end)
Drag(-120)
sim.cursorX, sim.cursorY = 5, 5 -- off the window: left alone, it glides back after 6 s
sim.Run(5.8)
assert(not Cam.follow)
Flight("the idle return", 1)
assert(Cam.follow)
assert(scaled == 0, "the borders' canvases scaled " .. scaled .. " times")

-- A drag's start on its own: the frame the press passes the click's 5 px.
sim.Run(1)
sim.MoveCursorTo(view)
sim.buttonsDown.LeftButton = true
sim.FireScript(view, "OnMouseDown", "LeftButton")
sim.Step()
collectgarbage("collect"); collectgarbage("stop")
sim.Step() -- (the frame after a collect regrows the Lua stacks: R-P3)
sim.cursorX = sim.cursorX + 6
sim.Step()
local kb = select(4, read())
collectgarbage("restart")
sim.buttonsDown.LeftButton = nil
sim.FireScript(view, "OnMouseUp", "LeftButton")
T.Print("P7: a drag's start: %.2f KB in its frame", kb)
assert(M.Dragging() == false and kb <= 10)

-- Hidden, every canvas is emptied (its regions parked), so showing the window again shows none of them
-- at once; the layers lay out again as at the first open, within a frame's budget, fresh within 1 s.
local frame = ns.UI.Window.frame
sim.Run(1)
frame:Hide()
sim.Run(1)
local held = 0
for _, l in ipairs(E.layers) do
	for _, c in ipairs(l.canvases) do held = held + #sim.state[c].regions end
end
local p0 = sim.priced
sim.Price(true)
frame:Show()
local show = sim.priced - p0
local worst = 0
for _ = 1, 60 do
	sim.Step()
	worst = math.max(worst, (select(5, read())))
end
sim.Price(false)
T.Print("P7: shown again: %d regions on the canvases, the Show %.2f ms priced; the slowest frame after it %.2f ms",
	held, show, worst)
assert(held == 0 and worst <= 8)
for _, l in ipairs(E.layers) do assert(T.Fresh(ns, l), l.name) end
assert(#T.Errors(sim, ns) == 0)

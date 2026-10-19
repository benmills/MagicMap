-- P7: while an ease moved the camera, layers were laid out again every frame (three "is it moving"
-- flags, one disagreeing). The map reads one, Camera.ZoomSettled (the zoom unchanged 0.15 s; Settled
-- adds "nothing moving it"), and before it lays a layer out again only past [0.7, 1.4] of its layout's
-- zoom; a held layer (borders) where the zoom is headed (ui/Engine.lua). Replayed: a wheel tick and a
-- zone fit start at most 2 layouts a layer, at most 1 once settled; the borders stay in sight meanwhile,
-- each frame scaled to the camera and dimmed as far as that scale is from 1, to 0.25 at most
-- (Layers.lua:158-170), then crossfaded over FADE_S from the alpha they had (Layers.lua:1820-1836); no
-- layout starts on a canvas still showing (a crossfade ends first: Layers.lua:1853-1855). On the priced clock
-- (docs/evidence/perf-m0.md), the flights (grow, shrink, the follow glide, the idle return): no frame of
-- ours over 8 ms, no swap over 4 ms, the map's allocation over each (its regions made once, by a first
-- grow); a drag's start on its own; the window shown again (after a plain hide, one mid-layout, and its
-- parent's: Alt-Z) and a layer turned back on: no region shown at once.
local T = ...
local sim, ns = T.Shown()
local E, Cam, M = ns.UI.Engine, ns.UI.Camera, ns.UI.Motion
local view, S = ns.UI.Window.view, sim.state
local borders = T.Layer(ns, "borders")
-- Layouts started (by whether the zoom had settled) and the slowest swap, as traced.
local starts, swapMax, trace = {}, 0, ns.Runtime.Trace
local fadeAt, mid, shown = -1, 0, {} -- the borders' last crossfade's start; layouts started during one; on a canvas in sight
ns.Runtime.Trace = function(kind, d)
	if kind == "layout" and d.e == "start" then
		local k = (Cam.ZoomSettled() and "settled " or "moving ") .. d.layer
		starts[k] = (starts[k] or 0) + 1
		local l = T.Layer(ns, d.layer)
		for _, c in ipairs(l.canvases) do -- (an error here would be Runtime's to catch)
			if c ~= l.front and S[c].alpha > 0 then shown[#shown + 1] = d.layer .. " " .. S[c].alpha end
		end
		if l == borders and GetTime() - fadeAt < 0.12 then mid = mid + 1 end -- (FADE_S)
	elseif kind == "swap" then
		swapMax = math.max(swapMax, d.ms)
		if d.layer == "borders" and borders.fade then fadeAt = GetTime() end
	end
	return trace(kind, d)
end

local LN2 = math.log(2)
local function Ease(name, start, most) -- most: layouts a layer (default 2: one a band, [0.7, 1.4], crossed)
	most = most or 2
	for k in pairs(starts) do starts[k] = nil end
	start()
	local dim, fades, longest, run, was = 1, 0, 0, 0, {} -- was: last frame's front and alphas
	for _ = 1, 120 do
		sim.Step()
		local c, f, z = borders.front, borders.fade, Cam.cam.zoom
		dim = math.min(dim, math.max(S[borders.canvases[1]].alpha, S[borders.canvases[2]].alpha))
		if f then -- crossfading: the old falls from the alpha it had, the new rises, both in sight
			if f.from == was.front then
				fades, run = fades + 1, 0
				assert(S[f.from].alpha <= was.alpha, name .. ": the crossfade's old canvas brightened")
			else
				assert(S[f.from].alpha < was.fromAlpha and S[c].alpha > was.alpha, name .. ": a crossfade not moving")
			end
			assert(S[f.from].alpha > 0 and (S[c].alpha > 0 or run == 0), name .. ": a crossfade with a canvas out of sight")
			run = run + 1
			longest = math.max(longest, run)
		elseif c.zoom ~= z then -- scaled to the camera, dimmed the further from 1 (Layers.lua:163-167)
			local s = z / c.zoom
			assert(math.abs(S[c].scale - s) < 1e-9, name .. ": the borders not scaled to the camera")
			local a = math.max(0.25, math.min(1, 1.6 - 0.6 * math.abs(math.log(s) / LN2)))
			assert(math.abs(S[c].alpha - a) < 1e-9, string.format("%s: the borders at alpha %.2f, scaled %.2f", name, S[c].alpha, s))
		end
		was.front, was.alpha, was.fromAlpha = c, S[c].alpha, f and S[f.from].alpha
	end
	assert(dim >= 0.25, name .. ": the borders out of sight, alpha " .. dim)
	assert(fades >= 1 and longest >= 6, name .. ": no crossfade as the borders landed")
	assert(Cam.Settled() and not E.pending, name .. ": still moving")
	local each = {}
	for _, l in ipairs(E.layers) do
		local a, b = starts["moving " .. l.name] or 0, starts["settled " .. l.name] or 0
		each[#each + 1] = string.format("%s %d+%d", l.name, a, b)
		assert(a + b <= most and b <= 1, name .. ": " .. each[#each])
	end
	T.Print("P7: %s: layouts while moving + once settled: %s; the borders' faintest %.2f, %d crossfade(s), the longest %d frames",
		name, table.concat(each, ", "), dim, fades, longest)
end
Ease("a wheel tick", function() sim.Wheel(view, 1) end)
Ease("a zone fit", function() M.FlyToRect(28, 46, 36, 52) end)
Ease("four ticks out at once (the buttons)", function() M.ZoomStep(-4) end, 3) -- x0.35: dimmed
Ease("and back in", function() M.ZoomStep(4) end, 3)
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
-- Hidden mid-layout too (the big window's borders at 250 at Kharanos: its subzones', a few frames), and
-- through its parent (Alt-Z: UIParent).
local frame = ns.UI.Window.frame
local function Held(layers)
	local held = 0
	for _, l in ipairs(layers or E.layers) do
		for _, c in ipairs(l.canvases) do held = held + #S[c].regions end
	end
	return held
end
local function Priced(show)
	local p0 = sim.priced
	sim.Price(true)
	show()
	local cost, worst = sim.priced - p0, 0
	for _ = 1, 60 do
		sim.Step()
		worst = math.max(worst, (select(5, read())))
	end
	sim.Price(false)
	return cost, worst
end
local function Again(name, hide, show)
	hide()
	sim.Run(1)
	local held = Held()
	local cost, worst = Priced(show)
	T.Print("P7: shown again (%s): %d regions on the canvases, the Show %.2f ms priced; the slowest frame after it %.2f ms",
		name, held, cost, worst)
	assert(held == 0 and cost <= 1 and worst <= 8, name)
	for _, l in ipairs(E.layers) do assert(T.Fresh(ns, l), name .. ": " .. l.name) end
end
sim.Run(1)
Again("hidden", function() frame:Hide() end, function() frame:Show() end)
sim.Press("M")
sim.Run(1.5)
M.SetFollow(false)
Cam.cam.cx, Cam.cam.cy = 32.904, 42.474 -- Kharanos
M.SetZoom(200)
sim.Run(2)
Again("mid-layout", function()
	M.SetZoom(250)
	for _ = 1, 60 do
		sim.Step()
		if borders.busy then break end
	end
	assert(borders.busy, "the borders laid out at 250")
	frame:Hide()
end, function() frame:Show() end)
sim.Run(1)
Again("Alt-Z", function() UIParent:Hide() end, function() UIParent:Show() end)
sim.Run(1)

-- A zoom, and a drag as the borders crossfade to it (the view leaves their layout): they lay out again
-- mid-crossfade, on a canvas out of sight (the trace hook above), as the spike's StartBuild
-- (Layers.lua:1853-1855).
M.SetFollow(false)
Cam.cam.cx, Cam.cam.cy = 32.904, 42.474 -- Kharanos, the big window: a borders layout takes frames
mid = 0
for round = 1, 4 do
	M.SetZoom(round % 2 == 1 and 250 or 325)
	for _ = 1, 60 do
		sim.Step()
		if borders.fade then break end
	end
	sim.MoveCursorTo(view)
	sim.buttonsDown.LeftButton = true
	sim.FireScript(view, "OnMouseDown", "LeftButton")
	for _ = 1, 10 do
		sim.cursorX = sim.cursorX + 100
		sim.Step()
	end
	sim.buttonsDown.LeftButton = nil
	sim.FireScript(view, "OnMouseUp", "LeftButton")
	sim.Run(1)
end
T.Print("P7: a drag as the borders crossfade: %d laid out again mid-crossfade", mid)
assert(mid >= 3 and #shown == 0, table.concat(shown, ", "))
Cam.cam.cx, Cam.cam.cy = 32.904, 42.474
sim.Run(1)

-- A layer turned off is emptied too: turned back on after a pan, it lays out anew, no frame over 8 ms.
sim.Slash("/mma layer borders")
sim.Run(1)
local held = Held({ borders })
Cam.cam.cx = Cam.cam.cx + 4
sim.Run(1)
local _, worst = Priced(function() sim.Slash("/mma layer borders") end)
T.Print("P7: the borders turned off: %d regions held; back on after a pan, the slowest frame %.2f ms priced", held, worst)
assert(held == 0 and worst <= 8 and T.Fresh(ns, borders))
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n"))

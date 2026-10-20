-- P3 moving (the user's play-test of the M1 build: in Orgrimmar 83.5 and 131.6 KB/s against 50, a tile
-- layout making 225 KB in one call, a border layout 150-476 KB, the sensor 19-30 KB/s; the drag's frame
-- p95 4.35 ms). CONTAINED: in Orgrimmar, the big window at four zooms down to 36 px a tile, drags and
-- the wheel at each, twice over the same views; then the small window following you on a walk through
-- the city's doors among 10 blips. The priced clock, at the client's prices (below):
--   * the first time, our garbage <= 50 KB/s; what the canvases' first regions take besides (kept in
--     their pools: ~7600 here, made once a session) is printed and held under 7800 and 176 KB/s, so a pool
--     that grows shows (the client's heap reading counts it: d1's shape, docs/runtime.md)
--   * the second time and walking, all of it <= 50 KB/s (over the whole run, ~64 KB/s with the first
--     time's regions: the client's heap reading can't tell pool growth from garbage, docs/runtime.md)
--   * a layout allocates its three traces (~1.1 KB: start, end, swap) and nothing else once its canvas
--     holds what it needs: it re-sets only what the canvas didn't show (Engine.Keep)
--   * the drag's frame p95 under 3 ms (4.35 in game and here when a pan's tile layout re-set every tile)
local T = ...
local sim, ns = T.Boot()
sim.player.inst, sim.player.col, sim.player.row = 1, 40.09, 28.85 -- Orgrimmar, the Valley of Strength
sim.Run(1)
sim.Slash("/mm toggle")
sim.Run(10) -- past telemetry's one full collect (ourKBLoad, 10 s after login)
local view, M, R, Camera = ns.UI.Window.view, ns.UI.Motion, ns.Runtime, ns.UI.Camera

-- At the client's prices: a widget call's own allocation (the sim's state for it, which the client keeps
-- in C) left out, and a region made counted as the client's, a table holding its userdata (~0.125 KB:
-- sessions #13, #14 made 783 lines in 192 KB, 0.245 KB a line with our 3 fields on it).
local CLIENT_KB = 0.125
local made, simKB, depth = 0, 0, 0
local function Out(k, ...)
	depth = depth - 1
	if depth == 0 then simKB = simKB + collectgarbage("count") - k end
	return ...
end
local any = CreateFrame("Button")
local wrapped = {}
for _, w in ipairs({ any, any:CreateTexture(), any:CreateMaskTexture(), any:CreateLine(), any:CreateFontString(), Minimap }) do
	local methods = getmetatable(w).__index
	while methods and not wrapped[methods] do
		wrapped[methods] = true
		for name, fn in pairs(methods) do
			if type(fn) == "function" then
				local count = name:match("^Create%u") and name ~= "CreateAnimationGroup"
				methods[name] = function(...)
					depth = depth + 1
					if count then made = made + 1 end
					return Out(depth == 1 and collectgarbage("count") or 0, fn(...))
				end
			end
		end
		local mt = getmetatable(methods)
		methods = mt and mt.__index
	end
end
-- A frame made (a pin: ui/Pins.lua) at the client's price too, as a region: a table holding its userdata
-- (CreateFrame is a global, not a widget's method).
local frames, createFrame = 0, CreateFrame
CreateFrame = function(...)
	depth = depth + 1
	frames = frames + 1
	return Out(depth == 1 and collectgarbage("count") or 0, createFrame(...))
end
local layouts, trace = 0, R.Trace
MADE = {}
R.Trace = function(kind, d)
	if kind == "layout" and d.e == "end" then layouts = layouts + 1; if d.made > 0 then MADE[#MADE + 1] = d.layer .. ":" .. d.made end end
	return trace(kind, d)
end
local read = T.Ours(sim)
local function Deep(n) if n > 0 then return Deep(n - 1) + 1 end return 0 end -- (R-P3: the main stack grown back first)

-- Our layouts' KB: Rebuild's and the workers' (none of it the sim's once no region is made).
local LAYOUT = { ["map: layout"] = true }
for _, l in ipairs(ns.UI.Engine.layers) do LAYOUT["map: " .. l.name] = true end
local function LayoutKB()
	local kb = 0
	for name, p in pairs(R.Perf()) do
		if LAYOUT[name] then kb = kb + p.kb end
	end
	return kb
end

-- Over run(): KB a second at the client's prices (all of it, the pools' growth with it), and our garbage
-- (all made less what a full collect keeps: the pools' growth); regions made, layouts and their KB, the
-- sim's KB, seconds.
local function Measure(run)
	collectgarbage("collect"); collectgarbage("stop")
	local kept = collectgarbage("count")
	Deep(300)
	sim.Step()
	local _, kb0 = read()
	local m0, f0, s0, l0, t0, lk0 = made, frames, simKB, layouts, sim.time, LayoutKB()
	run()
	collectgarbage("restart")
	local _, kb1 = read()
	collectgarbage("collect")
	kept = collectgarbage("count") - kept
	local m, secs = made - m0, sim.time - t0
	return { kbs = (kb1 - kb0 - (simKB - s0) + (m + frames - f0) * CLIENT_KB) / secs, garbage = (kb1 - kb0 - kept) / secs,
		made = m, layouts = layouts - l0, layoutKB = LayoutKB() - lk0, sim = simKB - s0, secs = secs }
end

local function Drag(dx, dy)
	sim.MoveCursorTo(view)
	sim.buttonsDown.LeftButton = true
	sim.FireScript(view, "OnMouseDown", "LeftButton")
	for _ = 1, 30 do sim.cursorX, sim.cursorY = sim.cursorX + dx, sim.cursorY + dy; sim.Step() end
	sim.buttonsDown.LeftButton = nil
	sim.FireScript(view, "OnMouseUp", "LeftButton")
	sim.Run(0.5)
end
local cx, cy = sim.player.col, sim.player.row
local function Big() -- each zoom from the same spot: again, the same views
	for _, z in ipairs({ 200, 100, 50, 36 }) do
		M.SetZoom(z)
		Camera.cam.cx, Camera.cam.cy = cx, cy
		sim.Run(1)
		for i = 1, 4 do Drag(i % 2 == 0 and 25 or -25, i % 3 == 0 and 15 or -10) end
		for _, d in ipairs({ 1, 1, -1, -1 }) do sim.Wheel(view, d); sim.Run(0.4) end
	end
end

sim.Price(true)
sim.Press("M")
sim.Run(1.5)
M.SetFollow(false)
local first = Measure(Big)
Big() -- (each canvas laid out both ways round)
local again = Measure(Big)

-- The big window's regions by layer, zoom by zoom: live (the front's) and on its canvases (the old
-- front's at alpha 0 with them, its frame for a minimum zoom's too: what the final session's
-- frame.moved.alpha0 would be multiplied by, docs/runtime.md).
for _, z in ipairs({ 200, 100, 60, 50, 36 }) do
	M.SetZoom(z)
	Camera.cam.cx, Camera.cam.cy = cx, cy
	sim.Run(1)
	local live, held, each = 0, 0, {}
	for _, l in ipairs(ns.UI.Engine.layers) do
		local n, on = T.Live(l), 0
		for _, c in ipairs(l.canvases) do
			for _, f in ipairs({ c, unpack(T.Values(c.mins)) }) do on = on + #sim.state[f].regions end
		end
		live, held, each[#each + 1] = live + n, held + on, string.format("%s %d/%d", l.name, n, on)
	end
	T.Print("P3b: big at %d px a tile: %d regions live, %d on the canvases (%s)", z, live, held, table.concat(each, ", "))
end

-- The walk: small, following you east through Orgrimmar among 10 blips (R-P3's), a door every 5 s.
sim.Press("M")
sim.Run(1.5)
M.SetFollow(true)
local Atlas, list = ns.Atlas, {}
local NAMES = { "Mailbox", "Peacebloom", "Silverleaf", "Copper Vein", "Innkeeper Farley" }
for i = 1, 10 do
	local a, d = i * 0.63, (30 + i * 12) / Atlas.TILE_YARDS
	local north, west = Atlas.TileToWorld(sim.player.col + math.cos(a) * d, sim.player.row - math.sin(a) * d)
	list[i] = { NAMES[(i - 1) % #NAMES + 1], north, west }
end
sim.minimapBlips = list
sim.FireEvent("MINIMAP_UPDATE_TRACKING")
sim.indoors = true -- (the building you're in decoded once, before: ~670 KB kept, game/parts/Interior.lua)
sim.Run(0.5)
sim.indoors = false
sim.Run(5)
local walk = Measure(function()
	sim.player.facing, sim.player.speed = 3 * math.pi / 2, 7 -- east
	for i = 1, 4 do
		sim.indoors = i % 2 == 1
		sim.Run(5)
	end
	sim.player.speed, sim.indoors = 0, false
	sim.Run(3)
end)
sim.Price(false)
local drag = R.FrameStats().byState.drag

local secs = first.secs + again.secs + walk.secs
local all = (first.kbs * first.secs + again.kbs * again.secs + walk.kbs * walk.secs) / secs
local each = (again.layoutKB - again.sim) / again.layouts -- (a coast tile's mask made the first time it's needed)
T.Print("P3b: Orgrimmar big, %.0f s: %.1f KB/s at the client's prices, %d regions made (garbage %.1f KB/s);"
	.. " the same again: %.1f KB/s, %d layouts at %.2f KB each; walking small through its doors: %.1f KB/s; all"
	.. " %.0f s: %.1f KB/s; the drag's frame p95 %.2f ms, p99 %.2f", first.secs, first.kbs, first.made, first.garbage,
	again.kbs, again.layouts, each, walk.kbs, secs, all, drag.p95, drag.p99)
assert(first.garbage <= 50 and again.kbs <= 50 and walk.kbs <= 50)
assert(first.made <= 7800 and first.kbs <= 215, "the first pass's pools grew") -- (210.5: labels sized by zoom, each
-- font string SetFont when its size changes (204.8 before); 7311, 158.7 KB/s: M1b review; 7352, 164.7: M3 wave 1;
-- 165.0: M3 review r1, a Focus a zoom more for Focus.moving; 7637, 172.7: M4 wave 1, the places' pins, 205 on
-- Kalimdor: 7194, 156.9 with them off; 7646, 204.8: M4 review r1, the town services gathered as the blips layer
-- asks, Atlas.SpawnsIn's index of Kalimdor's NPCs and their entries, kept: 172.7 without)
assert(again.made <= 50 and again.layouts >= 100 and each <= 1.25, "a layout: its traces, nothing else")
assert(drag.p95 < 3, drag.p95)
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n"))

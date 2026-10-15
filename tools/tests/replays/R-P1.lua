-- P1: borders fall behind a fast pan. MOVED: a layout job's cost per frame is bounded (its budget,
-- under a client-like clock), but a whole-layer rebuild still lags a fling: coverage is measured
-- and printed, and the layers must be fresh 1 s after stopping.
local T = ...
local JOB_MS = 4 -- ui/Map.lua: a layout's budget a frame
local function R2(v) return math.floor(v * 100 + 0.5) / 100 end
local sim, ns = T.Boot()
sim.CountCalls()
sim.Clock = function() return os.clock() * 1000 + sim.callTotal * 0.003 end
sim.Run(1)
sim.Slash("/mma map")
sim.Run(3)
local m = ns.UI.Map
for _, lay in ipairs(m.layers) do -- the first open's layouts done: maxima from here
	ns.Runtime.Perf()["map: " .. lay.name].max = 0
end
local w = m.Size()
m.follow = false
local covered = {}
for _, lay in ipairs(m.layers) do covered[lay.name] = 0 end
for _ = 1, 180 do
	m.cam.cx = m.cam.cx + w * 1.5 / 60 / m.cam.zoom
	sim.Step()
	for _, lay in ipairs(m.layers) do
		if T.Fresh(ns, lay) then covered[lay.name] = covered[lay.name] + 1 end
	end
end
sim.Run(1)
local perf = ns.Runtime.Perf()
local worst, shown = {}, {}
for _, lay in ipairs(m.layers) do
	worst[lay.name] = R2(perf["map: " .. lay.name].max)
	shown[#shown + 1] = string.format("%s %d / %.2f ms", lay.name, covered[lay.name], worst[lay.name])
end
T.Print("P1: frames covered of 180 at 1.5 views/s / job max ms: %s", table.concat(shown, ", "))
for _, lay in ipairs(m.layers) do assert(T.Fresh(ns, lay), lay.name) end
for name, ms in pairs(worst) do assert(ms <= JOB_MS * 1.5, name .. " " .. ms) end
assert(#T.Errors(sim, ns) == 0)

-- A 20-step wheel-out, one step a frame: layouts started, against layers x settled zooms (1).
local function Started()
	local n = 0
	for _, e in pairs(ns.Runtime.TraceCopy()) do
		if e.k == "layout" and e.d.e == "start" then n = n + 1 end
	end
	return n
end
local start = Started()
for _ = 1, 20 do
	sim.Wheel(m.view, -1)
	sim.Step()
end
sim.Run(2)
T.Print("P1: 20-step wheel-out: %d layouts started for %d layers", Started() - start, #m.layers)
for _, lay in ipairs(m.layers) do assert(T.Fresh(ns, lay), lay.name) end

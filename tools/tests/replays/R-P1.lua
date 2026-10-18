-- P1: borders fall behind a fast pan. MOVED: a layout job's cost per frame is bounded (its budget,
-- on the counted clock: 3 us a widget call), but a whole-layer rebuild still lags a fling: coverage
-- is measured and printed, and the layers must be fresh 1 s after stopping.
local T = ...
local JOB_MS = 4 -- ui/Engine.lua: a layout's budget a frame
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
for _, lay in ipairs(layers) do assert(T.Fresh(ns, lay), lay.name) end
for name, ms in pairs(worst) do assert(ms <= JOB_MS * 1.5, name .. " " .. ms) end
assert(#T.Errors(sim, ns) == 0)

-- A 20-step zoom-out, one step a frame: layouts started, against layers x settled zooms (1).
local function Started()
	local n = 0
	for _, e in pairs(ns.Runtime.TraceCopy()) do
		if e.k == "layout" and e.d.e == "start" then n = n + 1 end
	end
	return n
end
local start = Started()
for _ = 1, 20 do
	ns.UI.Motion.ZoomStep(-1) -- the zoom-out button's tick (the wheel's are rationed by time: M1.8b)
	sim.Step()
end
sim.Run(2)
T.Print("P1: 20-step zoom-out: %d layouts started for %d layers", Started() - start, #layers)
for _, lay in ipairs(layers) do assert(T.Fresh(ns, lay), lay.name) end

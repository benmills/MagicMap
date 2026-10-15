-- E7: one error stops everything after it. CONTAINED: a layout job that errors is recorded once
-- (with its stack), its layer isn't frozen (busy cleared, laid out again after a backoff), and a
-- step failing every frame takes one stack, not one per failure.
local T = ...
local sim, ns = T.Shown()
local m, borders = ns.UI.Map, T.Layer(ns, "borders")
local orig, failed = borders.build, nil
borders.build = function(...)
	if not failed then failed = true; error("layout boom") end
	return orig(...)
end
local zoom = m.cam.zoom
sim.Wheel(m.view, 1)
sim.Run(1)
assert(m.cam.zoom ~= zoom)
local errors = ns.Runtime.errors
assert(#errors == 1 and errors[1].name == "map: borders" and errors[1].n == 1)
assert(not borders.busy and T.Fresh(ns, borders) and T.Live(borders) > 0)
local tel = MagicMapAtlasDB.telemetry
local kept
for _, e in pairs(tel.errors) do
	if e.name == "map: borders" then kept = kept or e end
end
assert(kept.count == 1 and kept.msg:find("layout boom", 1, true) and kept.stack)
local traced = false
for _, e in pairs(ns.Runtime.TraceCopy()) do
	traced = traced or (e.k == "layout" and e.d.e == "failed")
end
assert(traced)

-- A step failing every frame (the spike's E1 rate): one stack walk, not one a failure.
local stacks, walk = { v = 0 }, debugstack
debugstack = function(...) stacks.v = stacks.v + 1; return walk(...) end
ns.Runtime.Step("model", "test.every-frame", function() error("again") end)
sim.Run(3)
local fails = T.Errs(ns, "test.every-frame")
T.Print("E7: a step failing every frame for 3 s: %d failures, %d stack walks", fails, stacks.v)
assert(fails >= 10 and stacks.v == 1)
assert(T.Fresh(ns, borders) and T.Errs(ns, "map: borders") == 1)

-- E1: data globals collide. PREVENTED: Data/ lives in the addon's namespace, so no data global is
-- set for the spike to read, and a spike-shaped MagicMap_Borders loaded after us isn't read.
-- A malformed row in our own data is CONTAINED: the borders layout fails, is recorded once, and
-- is retried with a backoff (never per frame) while tiles and labels draw.
local T = ...
local sim, ns = T.Shown()
local leaked = {}
for k in pairs(_G) do
	if type(k) == "string" and (k:find("^MagicMap_") or k:find("^MagicMapAtlas_")) then leaked[#leaked + 1] = k end
end
assert(#leaked == 0, table.concat(leaked, ", "))
MagicMap_Borders = { [0] = { lines = { { 1, 12, 40, 0, 0, 31.0, 49.0, 32.0, 50.0 } }, labels = {} } }
local view, borders = ns.UI.Window.view, T.Layer(ns, "borders")
sim.Wheel(view, 1)
sim.Run(1)
sim.Drag(view, 200, 0)
sim.Run(1)
assert(#T.Errors(sim, ns) == 0 and T.Fresh(ns, borders) and T.Live(borders) > 0)

-- Our own data with the spike's row shape (an odd coordinate count): the E1 error itself.
local lines = ns.Data.Borders[0].lines
lines[#lines + 1] = { 1, 12, 40, 0, 0, 31.9, 49.7, 32.0, 49.8 }
sim.Wheel(view, 1)
sim.Run(1)
local n1 = T.Errs(ns, "map: borders")
sim.Run(3) -- 180 frames
local n2 = T.Errs(ns, "map: borders")
T.Print("E1: malformed row: %d error(s) after 1 s, %d after 4 s (180 frames)", n1, n2)
assert(1 <= n1 and n1 <= 2 and n2 - n1 <= 3, n1 .. ", " .. n2) -- backoff 0.5, 1, 2, 4 s: not per frame
local err
for _, e in pairs(ns.Runtime.errors) do
	if e.name == "map: borders" then err = err or e.err end
end
assert(err:find("bad argument", 1, true))
for _, name in ipairs({ "tiles", "labels" }) do
	assert(T.Fresh(ns, T.Layer(ns, name)) and T.Live(T.Layer(ns, name)) > 0, name)
end
local tel = MagicMapAtlasDB.telemetry
local kept, marks = {}, 0
for _, e in pairs(tel.errors) do
	if e.name == "map: borders" then kept[#kept + 1] = e end
end
assert(#kept == 1 and kept[1].count == n2 and kept[1].stack)
for _, m in pairs(tel.marks) do
	if (m.note or ""):find("map: borders", 1, true) then marks = marks + 1 end
end
assert(marks == 1)

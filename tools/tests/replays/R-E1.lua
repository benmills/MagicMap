-- E1: data globals collide. PREVENTED: Data/ lives in the addon's namespace, so no data global is
-- set for the spike to read, and a spike-shaped MagicMap_Labels loaded after us isn't read.
-- A layout failing on our own data is CONTAINED: the labels layout fails, is recorded once, and
-- is retried with a backoff (never per frame) while the tiles draw.
local T = ...
local sim, ns = T.Shown()
sim.Press("M") -- (zone names show on the big map only)
sim.Run(1)
local leaked = {}
for k in pairs(_G) do
	if type(k) == "string" and k:find("^MagicMap_") and k ~= "MagicMap_OnAddonCompartmentClick" then leaked[#leaked + 1] = k end
end
assert(#leaked == 0, table.concat(leaked, ", "))
MagicMap_Labels = { [0] = { { "Nowhere", 31.0, 49.0, 2, 1 } } }
local view, labels = ns.UI.Window.view, T.Layer(ns, "labels")
sim.Wheel(view, 1)
sim.Run(1)
sim.Drag(view, 200, 0)
sim.Run(1)
assert(#T.Errors(sim, ns) == 0 and T.Fresh(ns, labels) and T.Live(labels) > 0)

-- A layout that fails every time, as the spike's row shape did (an odd coordinate count): the E1 error itself.
labels.build = function() error("bad argument #2 to 'SetPoint'") end
sim.Wheel(view, 1)
sim.Run(1)
local n1 = T.Errs(ns, "map: labels")
sim.Run(3) -- 180 frames
local n2 = T.Errs(ns, "map: labels")
T.Print("E1: malformed row: %d error(s) after 1 s, %d after 4 s (180 frames)", n1, n2)
assert(1 <= n1 and n1 <= 2 and n2 - n1 <= 3, n1 .. ", " .. n2) -- backoff 0.5, 1, 2, 4 s: not per frame
local err
for _, e in pairs(ns.Runtime.errors) do
	if e.name == "map: labels" then err = err or e.err end
end
assert(err:find("bad argument", 1, true))
for _, name in ipairs({ "tiles" }) do
	assert(T.Fresh(ns, T.Layer(ns, name)) and T.Live(T.Layer(ns, name)) > 0, name)
end
local tel = MagicMap2DB.telemetry
local kept, marks = {}, 0
for _, e in pairs(tel.errors) do
	if e.name == "map: labels" then kept[#kept + 1] = e end
end
assert(#kept == 1 and kept[1].count == n2 and kept[1].stack)
for _, m in pairs(tel.marks) do
	if (m.note or ""):find("map: labels", 1, true) then marks = marks + 1 end
end
assert(marks == 1)

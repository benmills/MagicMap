-- K5: a restricted instance. PREVENTED (as a failure): with no position, inst comes from
-- GetInstanceInfo; Model drops the old continent's position, the arrow hides, nothing errors.
local T = ...
local sim, ns = T.Shown()
local arrow
for _, f in ipairs(sim.Frames()) do
	for _, r in ipairs(sim.state[f].regions or {}) do
		if sim.state[r].texture == "Interface\\Minimap\\MinimapArrow" then arrow = arrow or r end
	end
end
assert(ns.Model.you.col ~= nil and arrow:IsShown())
sim.restricted = true
sim.player.inst = 389
sim.FireEvent("PLAYER_ENTERING_WORLD", false, false)
sim.Run(1)
local you = ns.Model.you
T.Print("K5: you.inst %s, col %s, map inst %s", tostring(you.inst), tostring(you.col), tostring(ns.UI.Map.inst))
assert(you.inst == 389 and you.col == nil and not arrow:IsShown())
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n\n"))

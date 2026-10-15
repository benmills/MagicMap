-- K5: a restricted instance. PREVENTED (as a failure): with no position, inst comes from
-- GetInstanceInfo; Model drops the old continent's position, the arrow hides, nothing errors.
-- Following, the map shown is the instance's, whole: its continent's rect, else its tiles'
-- bounds, filling the view (Core.lua:1133-1152, 1540-1542); with neither, its middle.
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
T.Print("K5: you.inst %s, col %s, map inst %s", tostring(you.inst), tostring(you.col), tostring(ns.UI.Camera.inst))
assert(you.inst == 389 and you.col == nil and not arrow:IsShown())
local cam = ns.UI.Camera.cam
assert(ns.Atlas.TileBounds(389) == nil and cam.cx == 32 and cam.cy == 32, "no tiles: its middle")

sim.player.inst = 36 -- the Deadmines: its tiles, whole
sim.FireEvent("PLAYER_ENTERING_WORLD", false, false)
sim.Run(1)
local c0, r0, c1, r1 = ns.Atlas.TileBounds(36)
local w, h = ns.UI.Window.Size()
cam = ns.UI.Camera.cam
T.Print("K5: Deadmines' tiles %d..%d x %d..%d, fitted at (%.2f, %.2f) zoom %.2f", c0, c1, r0, r1, cam.cx, cam.cy, cam.zoom)
assert(ns.UI.Camera.inst == 36 and ns.UI.Camera.follow)
assert(cam.cx == (c0 + c1) / 2 and cam.cy == (r0 + r1) / 2 and math.abs(cam.zoom - math.min(w / (c1 - c0), h / (r1 - r0))) < 1e-9)
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n\n"))

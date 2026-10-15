-- K5: a restricted instance. PREVENTED (as a failure): with no position, inst comes from
-- GetInstanceInfo; Model drops the old continent's position, the arrow hides, nothing errors.
-- Following, the map shown is the instance's, whole: its continent's rect, else its tiles'
-- bounds, filling the view (Core.lua:1133-1152, 1540-1542); one we have no tiles for (most
-- dungeons) leaves the map you came from, titled with its name (Core.lua:1119, 1302).
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
local you, cam0 = ns.Model.you, ns.UI.Camera.cam
sim.cursorX, sim.cursorY = 10, 10 -- (not hovering: that names the zone under the cursor)
sim.Run(0.1)
local title = ns.UI.Title.title:GetText()
T.Print("K5: you.inst %s, col %s, map inst %s, title %s", tostring(you.inst), tostring(you.col),
	tostring(ns.UI.Camera.inst), title)
assert(you.inst == 389 and you.col == nil and not arrow:IsShown())
assert(ns.Atlas.Tiles(389) == nil and ns.UI.Camera.inst == 0 and ns.UI.Camera.follow, "no tiles: the map you came from")
local cam = ns.UI.Camera.cam
assert(cam.cx == cam0.cx and cam.cy == cam0.cy and title == ns.Atlas.Maps()[1].name, "where it was, the continent named")

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

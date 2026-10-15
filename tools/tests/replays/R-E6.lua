-- E6 (with E3's radius 0): the sensor while the Minimap's view radius is 0 (a new zoom
-- applying: the client gives 0 for a frame or two, where the sweep's maths would divide by
-- it). CONTAINED: the sweep starts over and obs.blips keeps what it knew, so no known blip
-- is forgotten (or flickers off) meanwhile; once the radius is back it senses again.
-- (4cd454d swept on at radius 0: in the sim an empty sweep forgot every blip.)
local T = ...
local sim, ns = T.Shown()
local A, p = ns.Atlas, sim.player
local yd = 1 / A.TILE_YARDS
local list = {}
for i, b in ipairs({ { "Mailbox", 40, 20 }, { "Mailbox", -50, -70 }, { "Peacebloom", -60, 30 } }) do
	local north, west = A.TileToWorld(p.col + b[2] * yd, p.row - b[3] * yd)
	list[i] = { b[1], north, west }
end
sim.minimapBlips = list
sim.Run(3)
local obs = ns.Game.obs
local function Live()
	local n = 0
	for _, k in ipairs((ns.Model.Known("blips"))) do n = n + (k.live and 1 or 0) end
	return n
end
assert(#obs.blips.list == 3 and Live() == 3, "sensed")
local sweep = obs.blips.sweep
sim.ZOOM_FRAMES = 60
Minimap:SetZoom(3)
Minimap:SetZoom(0) -- radius 0 for 60 frames
sim.Run(0.75)
assert(C_Minimap.GetViewRadius() == 0)
assert(obs.blips.sweep == sweep and #obs.blips.list == 3 and Live() == 3, "kept while radius 0")
sim.Run(2)
assert(obs.blips.sweep > sweep and #obs.blips.list == 3 and Live() == 3, "sensing again")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

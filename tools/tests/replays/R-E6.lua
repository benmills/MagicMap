-- E6 (with E3's radius 0): the sensor while the Minimap's view radius is 0 (a new zoom
-- applying: the client gives 0 for a frame or two, where the sweep's maths would divide by
-- it). CONTAINED: the sweep starts over and obs.blips keeps what it knew, so no known blip
-- is forgotten (or flickers off) meanwhile; once the radius is back it senses again.
-- (4cd454d swept on at radius 0: in the sim an empty sweep forgot every blip.)
-- And E6's empty grid (the spike built it from the Minimap's size, 0 before layout, and
-- erred every frame): PREVENTED, the grid is the sensor's side over a square's width,
-- both in screen units, so a sweep is the same points at any UI scale.
local T = ...
local sim, ns = T.Shown()
ns.Atlas.BlipService = function() return nil end -- (M1.2's accessor: none of these is a service)
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

-- The last sweep's probes (each blip known: no measuring, the grid alone).
local function Probes()
	local ring = ns.Runtime.TraceCopy()
	for i = #ring, 1, -1 do
		if ring[i].k == "blips" then return ring[i].d.probes end
	end
end
local probes = Probes()
for i, scale in ipairs({ 0.5, 1.4 }) do
	UIParent:SetScale(scale)
	local east, north = 30 * i, -40 -- a new one, measured at this scale
	local n, w = A.TileToWorld(p.col + east * yd, p.row - north * yd)
	list[#list + 1] = { "Silverleaf", n, w }
	sweep = obs.blips.sweep
	sim.Run(3)
	T.Print("E6: UI scale %.1f: %d probes a sweep (%d at 1), the Minimap %.0f units across", scale, Probes(), probes, Minimap:GetWidth())
	assert(Minimap:GetEffectiveScale() == scale and math.abs(Minimap:GetWidth() * scale - 300) < 1e-6, "placed in screen units")
	assert(obs.blips.sweep >= sweep + 2 and Probes() == probes and probes > 300, "the same grid")
	local got = 0
	for _, b in ipairs(obs.blips.list) do
		if b.name == "Silverleaf" and math.abs(b.pos.col - p.col - east * yd) < 0.5 * yd
			and math.abs(p.row - b.pos.row - north * yd) < 0.5 * yd then got = got + 1 end
	end
	assert(#obs.blips.list == 3 + i and got == 1 and Live() == 3 + i, "measured")
end
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

-- E6 (with E3's radius 0): the sensor while the Minimap's view radius is 0 (a new zoom
-- applying: the client gives 0 for a frame or two, where the sweep's maths would divide by
-- it). CONTAINED: the sweep starts over and obs.blips keeps what it knew, so no known blip
-- is forgotten (or flickers off) meanwhile; once the radius is back it senses again.
-- (4cd454d swept on at radius 0: in the sim an empty sweep forgot every blip.)
-- And E6's empty grid (the spike built it from the Minimap's size, 0 before layout, and
-- erred every frame): PREVENTED, the sensor's lattice is a square's width apart in the
-- world (the square in screen units over the Minimap's side in screen units), so a look at
-- every point is the same points at any UI scale.
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
sim.FireEvent("MINIMAP_UPDATE_TRACKING") -- (they show: tracking on, so the sensor looks again at once)
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

-- A look at every point (what tracking changing asks for): its probes, each blip known (no
-- measuring: the lattice alone).
local function Probes()
	local s = obs.blips.sweep
	sim.FireEvent("MINIMAP_UPDATE_TRACKING")
	sim.Run(1.5)
	local ring, most = ns.Runtime.TraceCopy(), 0
	for i = 1, #ring do
		if ring[i].k == "blips" and ring[i].d.sweep > s then most = math.max(most, ring[i].d.probes) end
	end
	return most
end
local probes = Probes()
for i, scale in ipairs({ 0.5, 1.4 }) do
	UIParent:SetScale(scale)
	local east, north = 30 * i, -40 -- a new one, measured at this scale
	local n, w = A.TileToWorld(p.col + east * yd, p.row - north * yd)
	list[#list + 1] = { "Silverleaf", n, w } -- (found: the Minimap placed anew, every point is looked at again)
	sweep = obs.blips.sweep
	sim.Run(3)
	local got, each = 0, Probes()
	T.Print("E6: UI scale %.1f: %d probes a look at every point (%d at 1), the Minimap %.0f units across", scale, each,
		probes, Minimap:GetWidth())
	assert(Minimap:GetEffectiveScale() == scale and math.abs(Minimap:GetWidth() * scale - 300) < 1e-6, "placed in screen units")
	assert(obs.blips.sweep >= sweep + 2 and each == probes and probes > 200, "the same lattice")
	for _, b in ipairs(obs.blips.list) do
		if b.name == "Silverleaf" and math.abs(b.pos.col - p.col - east * yd) < 0.5 * yd
			and math.abs(p.row - b.pos.row - north * yd) < 0.5 * yd then got = got + 1 end
	end
	assert(#obs.blips.list == 3 + i and got == 1 and Live() == 3 + i, "measured")
end
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

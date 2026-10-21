-- D5a: blips read wrong, or shown misplaced, right after a zoom: the client applies a new
-- Minimap zoom level a frame or two late. PREVENTED: the sensor reads only where the last
-- Apply placed the Minimap, once that placement holds still and its zoom has applied (its
-- view radius back): no probe falls in a frame a zoom or a placement is settling, through
-- another addon zooming it and the window moving and resizing, and what it knows stays exact.
local T = ...
local sim, ns = T.Shown()
ns.Atlas.BlipService = function() return nil end -- (M1.2's accessor: none of these is a service)
local A, p, Game, Window = ns.Atlas, sim.player, ns.Game, ns.UI.Window
local yd = 1 / A.TILE_YARDS
local want = { { "Mailbox", 40, 20 }, { "Peacebloom", -60, 30 }, { "Copper Vein", 90, -110 } }
local list = {}
for i, b in ipairs(want) do
	local north, west = A.TileToWorld(p.col + b[2] * yd, p.row - b[3] * yd)
	list[i] = { b[1], north, west }
end
sim.minimapBlips = list
sim.FireEvent("MINIMAP_UPDATE_TRACKING") -- (they show: tracking on, so the sensor looks again at once)
sim.ZOOM_FRAMES = 3 -- (late: the frame it's set in and two more)
sim.Run(3)
local obs = Game.obs
local function Exact()
	if #obs.blips.list ~= #want then return false end
	for _, w in ipairs(want) do
		local n = 0
		for _, b in ipairs(obs.blips.list) do
			if b.name == w[1] and not b.rough and math.abs(b.pos.col - p.col - w[2] * yd) < 0.5 * yd
				and math.abs(p.row - b.pos.row - w[3] * yd) < 0.5 * yd then n = n + 1 end
		end
		if n ~= 1 then return false end
	end
	return true
end
assert(Exact(), "sensed")
-- The frames the Minimap was last zoomed and placed in; a probe before the frame after the
-- zoom has applied (its radius back after ZOOM_FRAMES), or in the frame after a placement
-- (Apply, then the next frame's Observe), is early.
local zoomed, placed = 0, 0
for name, set in pairs({ SetZoom = function() zoomed = sim.frame end, SetPoint = function() placed = sim.frame end,
	SetSize = function() placed = sim.frame end }) do
	local fn = Minimap[name]
	Minimap[name] = function(...)
		set()
		return fn(...)
	end
end
local probe, early = C_TooltipInfo.GetMinimapMouseover, 0
C_TooltipInfo.GetMinimapMouseover = function()
	if sim.frame - zoomed <= sim.ZOOM_FRAMES or sim.frame - placed < 2 then early = early + 1 end
	return probe()
end
local function Through(n, what)
	local s = obs.blips.sweep
	for _ = 1, n do
		sim.Step()
		assert(Exact(), what)
	end
	assert(obs.blips.sweep > s, what .. ": sensing again")
end
Minimap:SetZoom(4) -- another addon
Through(120, "zoomed")
local f = Window.frame
f:ClearAllPoints()
f:SetPoint("CENTER", UIParent, "CENTER", -300, 120) -- moved
Through(120, "moved")
f:SetSize(500, 400) -- resized
Through(120, "resized")
for _ = 1, 30 do -- dragged: placed anew each frame
	f:SetPoint("CENTER", UIParent, "CENTER", -300 + sim.frame % 7, 120)
	sim.Step()
	assert(Exact(), "dragged")
end
Through(120, "dropped")
T.Print("D5a: %d probes in a frame a zoom or placement was settling", early)
assert(early == 0)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

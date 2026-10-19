-- D5b: near a screen edge every blip landed in the wrong place, and off screen the sensor
-- saw nothing: the client draws a Minimap running off the screen into its on-screen part,
-- squashed, and stops updating one off it. MOVED (that client behaviour, handled in Game's
-- Apply): the sensor stays whole on the screen, off its centre under the view if it must,
-- and measures as well there (the Minimap is centred on you wherever it sits). The window
-- in each corner, the Minimap's home among them (a small window at the top right), with
-- blips placed anew each time (a window moved keeps what the lattice's points answered: the
-- world changed too here, so every point is looked at again, as when the tracking changes).
local T = ...
local sim, ns = T.Shown()
ns.Atlas.BlipService = function() return nil end -- (M1.2's accessor: none of these is a service)
local A, p, Game, Window = ns.Atlas, sim.player, ns.Game, ns.UI.Window
local yd = 1 / A.TILE_YARDS
local obs, want = Game.obs, nil
local function Put(dx, dy)
	want = { { "Mailbox", 40 + dx, 20 + dy }, { "Peacebloom", -60 + dx, 30 + dy }, { "Copper Vein", 90 + dx, -110 + dy } }
	local list = {}
	for i, b in ipairs(want) do
		local north, west = A.TileToWorld(p.col + b[2] * yd, p.row - b[3] * yd)
		list[i] = { b[1], north, west }
	end
	sim.minimapBlips = list
end
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
local W, H = UIParent:GetWidth() * UIParent:GetEffectiveScale(), UIParent:GetHeight() * UIParent:GetEffectiveScale()
local f = Window.frame
f:SetSize(240, 240)
-- Each corner: the window's point and offset, and the blips' shift (yd east, north: well clear of the last's squares).
for _, corner in ipairs({ { "TOPRIGHT", -10, -10, 30, -25 }, { "BOTTOMLEFT", -60, -60, -30, 25 },
	{ "TOPLEFT", 0, 0, 25, 30 }, { "BOTTOMRIGHT", 80, 0, -25, -30 } }) do
	f:ClearAllPoints()
	f:SetPoint(corner[1], UIParent, corner[1], corner[2], corner[3])
	Put(corner[4], corner[5])
	sim.FireEvent("MINIMAP_UPDATE_TRACKING")
	sim.Run(4)
	local l, b, w, h = Sim.Rect(Minimap)
	local vx, vy = Window.view:GetCenter()
	local s = Window.view:GetEffectiveScale()
	T.Print("D5b: window at %s: the sensor at %.0f,%.0f-%.0f,%.0f (screen %dx%d), its centre %.0f,%.0f off the view's",
		corner[1], l, b, l + w, b + h, W, H, l + w / 2 - vx * s, b + h / 2 - vy * s)
	assert(l >= 2 - 1e-6 and b >= 2 - 1e-6 and l + w <= W - 2 + 1e-6 and b + h <= H - 2 + 1e-6, "whole on the screen")
	assert(math.abs(l + w / 2 - vx * s) > 1 or math.abs(b + h / 2 - vy * s) > 1, "off the view's centre")
	assert(Exact(), corner[1])
end
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

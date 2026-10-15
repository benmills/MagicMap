-- G3: other client code changing the state the takeover set (HybridMinimap turns the
-- Minimap's ground and rotation back on as it hides; Rotate Minimap; anyone zooming,
-- hiding or moving it). CONTAINED: Apply puts each right every frame; the sensor reads
-- only a Minimap as Apply left it (a frame it isn't, it starts its sweep over, keeping
-- what it knew); only something fighting Apply for BLIND s is traced ("sensor" blind,
-- a kept kind); and the undo list still puts back what was there before the takeover.
local T = ...
local sim, ns = T.Shown()
ns.Atlas.BlipService = function() return nil end -- (M1.2's accessor: none of these is a service)
local A, p, Game = ns.Atlas, sim.player, ns.Game
local yd = 1 / A.TILE_YARDS
local want = { { "Mailbox", 40, 20 }, { "Peacebloom", -60, 30 } }
local list = {}
for i, b in ipairs(want) do
	local north, west = A.TileToWorld(p.col + b[2] * yd, p.row - b[3] * yd)
	list[i] = { b[1], north, west }
end
sim.minimapBlips = list
sim.Run(3)
local obs, m = Game.obs, Game.minimap
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
local function Held()
	local l, b, w = Minimap:GetRect()
	return Minimap:IsShown() and Minimap:GetZoom() == 0 and not C_Minimap.GetDrawGroundTextures()
		and C_Minimap.IsRotateMinimapIgnored() and math.abs(l - m.left) < 1e-6 and math.abs(b - m.bottom) < 1e-6
		and math.abs(w - m.size) < 1e-6
end
-- Every probe reads the Minimap as Apply left it.
local probe, bad = C_TooltipInfo.GetMinimapMouseover, 0
C_TooltipInfo.GetMinimapMouseover = function()
	if not Held() then bad = bad + 1 end
	return probe()
end
assert(m.engaged and Exact() and Held(), "sensed")

local function Sweeps(n)
	local s = obs.blips.sweep
	for _ = 1, 600 do
		if obs.blips.sweep >= s + n then return end
		sim.Step()
	end
	error("no sweep")
end

-- HybridMinimap hides: ground and rotation on, the Minimap hidden. Right the next frame.
C_Minimap.SetDrawGroundTextures(true)
C_Minimap.SetIgnoreRotateMinimap(false)
Minimap:Hide()
sim.Step()
assert(Held() and Exact(), "put right")
-- Another addon zooms it and moves it away.
Minimap:SetZoom(2)
Minimap:ClearAllPoints()
Minimap:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
sim.Step()
assert(Held() and Exact(), "put back")
Sweeps(2)
assert(Exact(), "sensing again")
-- Rotate Minimap on: the Minimap stays ours, north up.
sim.cvars.rotateMinimap = "1"
Sweeps(2)
assert(m.engaged and Held() and Exact(), "north up")
-- Something turning rotation back on every frame for 2 s: the sensor can't read, keeps what it
-- knew, and says so once.
local onStep = sim.onStep
sim.onStep = function(dt) onStep(dt); C_Minimap.SetIgnoreRotateMinimap(false) end
local s = obs.blips.sweep
sim.Run(2)
assert(obs.blips.sweep == s and Exact(), "kept while blind")
sim.onStep = onStep
Sweeps(2)
assert(Exact(), "sensing again")
local kept = MagicMapAtlasDB.telemetry.sessions[#MagicMapAtlasDB.telemetry.sessions].kept
local said = {}
for _, e in ipairs(kept) do
	if e.k == "sensor" then said[#said + 1] = e.d.e .. " " .. e.d.why end
end
T.Print("G3: kept %s; %d probes read a Minimap Apply hadn't left", table.concat(said, ", "), bad)
assert(#said == 1 and said[1] == "blind rotated" and bad == 0)

-- Released after all that: what was there before the takeover (the sim's: ground on, rotation not ignored).
C_TooltipInfo.GetMinimapMouseover = probe
sim.Slash("/mma minimap blizzard")
sim.Step()
assert(not m.engaged and C_Minimap.GetDrawGroundTextures() and not C_Minimap.IsRotateMinimapIgnored()
	and Minimap:GetParent() == MinimapCluster and Minimap:GetWidth() == 140 and Minimap:GetZoom() == 0, "released")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

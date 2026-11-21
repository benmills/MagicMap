-- Blizzard's Minimap rim parts while the takeover has it (View.chrome, types/view.lua MM.ViewChrome),
-- after the takeover's own apply step (game/Minimap.lua), so a release puts them back that frame:
--   questRing false: its quest, dig-site and bonus-objective rings (the patterned circle where an
--     area runs past its edge) sized 0: they mark a rim we don't show
--   rimArrows false: its rim's icons, the big arrows toward your target, pushed far out, off
--     screen (the client won't swap their art): our gold arrows point the way instead (ui/Guide.lua, ui/Path.lua)
--   indicators: Blizzard's mail and crafting-order indicators (MinimapCluster.IndicatorFrame), which hide with
--     the cluster, hung there (its TOPRIGHT, SIZE px tall), above it; each apply puts them back if the client's own
--     layout moved them; never in combat, nor a protected frame
-- nil, not engaged, or logging out: as Blizzard has them.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local RINGS = { "SetQuestBlobRingScalar", "SetArchBlobRingScalar", "SetTaskBlobRingScalar" }
local INSET = 1000 -- the rim's icons this many times out, all round

local rings, arrows = false, false -- hidden now

local function Set(r, a)
	if r ~= rings then
		rings = r
		for _, set in ipairs(RINGS) do Minimap[set](Minimap, r and 0 or 1) end
	end
	if a ~= arrows then
		arrows = a
		if a then C_Minimap.SetMinimapInsetInfo(0, 360, INSET) else C_Minimap.ClearMinimapInsetInfo() end
	end
end

local SIZE = 24 -- the indicators' height on our map, px (Blizzard's mail button is 33)
local home -- the indicators' own parent, points, scale, strata and level while they're on our host
local function Indicators(host)
	local f = MinimapCluster and MinimapCluster.IndicatorFrame
	if not f or (host == nil and home == nil) or InCombatLockdown() or (f.IsProtected and f:IsProtected()) then return end
	if host then
		local _, rel = f:GetPoint(1)
		if f:GetParent() == host and rel == host then return end
		if not home then
			local points = {}
			for i = 1, f:GetNumPoints() do points[i] = { f:GetPoint(i) } end
			home = { parent = f:GetParent(), points = points, scale = f:GetScale(), strata = f:GetFrameStrata(),
				level = f:GetFrameLevel() }
		end
		f:SetParent(host)
		f:SetFrameStrata(host:GetFrameStrata())
		f:SetFrameLevel(host:GetFrameLevel() + 2)
		f:ClearAllPoints()
		f:SetPoint("TOPRIGHT", host, "TOPRIGHT")
		local mail = f.MailFrame
		local h = mail and mail:GetHeight() or 0
		f:SetScale(h > 0 and SIZE / h or 1) -- /: never 0 (h > 0 checked)
		return
	end
	local stand = MagicMapMinimapStandIn -- (game/Minimap.lua's: put back by its release, the Minimap's again)
	f:SetParent(home.parent)
	f:SetScale(home.scale)
	f:SetFrameStrata(home.strata)
	f:SetFrameLevel(home.level)
	f:ClearAllPoints()
	for _, p in ipairs(home.points) do
		f:SetPoint(p[1], p[2] == stand and Minimap or p[2], p[3], p[4], p[5])
	end
	home = nil
end

Game.Apply("chrome", function(view)
	local c = Game.minimap.engaged and view.chrome
	Set(c and c.questRing == false or false, c and c.rimArrows == false or false)
	Indicators(c and c.indicators or nil)
end)

Runtime.On("PLAYER_LOGOUT", "game.chrome logout", function()
	Set(false, false)
	Indicators(nil)
end)

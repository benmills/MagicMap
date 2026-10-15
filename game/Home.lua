-- The Minimap's home spot (spike MinimapTakeover.lua:579-599): obs.minimap.home, where UI puts
-- the small window (UIParent units, types/observation.lua MM.ScreenRect), with the cluster's
-- strata (UI's small window sits in it); and View.window.homeAlpha, the spot faded while big.
-- Read each time, as the spike did (MinimapTakeover.lua:590-599: whatever moved it, a new UI scale
-- or Edit Mode): from the Minimap before the takeover moves it, from then on from its stand-in,
-- which holds the spot at its scale (game/Minimap.lua); a new rect only when it moved.

local _, ns = ...
local Game = ns.Game

local home -- the last read

function Game.Home()
	local spot = Game.minimap.engaged and MagicMapAtlasMinimapStandIn or Minimap
	local left, top, w, h = spot:GetLeft(), spot:GetTop(), spot:GetSize()
	if not (left and top) then return home, MinimapCluster:GetFrameStrata() end -- (not laid out yet)
	local s = spot:GetEffectiveScale() / UIParent:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
	left, top, w, h = left * s, top * s, w * s, h * s
	if not (home and home.left == left and home.top == top and home.w == w and home.h == h) then
		home = { left = left, top = top, w = w, h = h }
	end
	return home, MinimapCluster:GetFrameStrata()
end

-- The spot (the cluster, and the stand-in holding what hung on the Minimap) at homeAlpha of the
-- cluster's own alpha: read when it first fades, put back at 1 (spike MinimapTakeover.lua:585-588,
-- MinimapMode.lua:150-185). 0 while the takeover can't hide the cluster yet (Game.minimap.fade).
local own, applied = nil, 1
Game.Apply("home", function(view)
	local a = Game.minimap.fade and 0 or view.window.homeAlpha
	if a == applied then return end
	own, applied = own or MinimapCluster:GetAlpha(), a
	MinimapCluster:SetAlpha(own * a)
	MagicMapAtlasMinimapStandIn:SetAlpha(own * a)
	if a == 1 then own = nil end
end)

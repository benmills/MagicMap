-- The Minimap's home spot (spike MinimapTakeover.lua:579-599): obs.minimap.home, where UI puts
-- the small window (UIParent units, types/observation.lua MM.ScreenRect), with the cluster's
-- strata (UI's small window sits in it); and View.window.homeAlpha, the spot faded while big.
-- The rect is read before the takeover moves the Minimap (from then on its stand-in holds the
-- spot, game/Minimap.lua), kept, and read again when the UI's scale or the screen changes.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local home, strata -- nil until read

function Game.Home()
	if not home then
		local spot = Game.minimap.engaged and MagicMapAtlasMinimapStandIn or Minimap
		local left, top, w, h = spot:GetLeft(), spot:GetTop(), spot:GetSize()
		if not (left and top) then return nil end -- (not laid out yet)
		local s = spot:GetEffectiveScale() / UIParent:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
		home, strata = { left = left * s, top = top * s, w = w * s, h = h * s }, MinimapCluster:GetFrameStrata()
	end
	return home, strata
end

local function Changed() home = nil end
Runtime.On("UI_SCALE_CHANGED", "game.home", Changed)
Runtime.On("DISPLAY_SIZE_CHANGED", "game.home", Changed)

-- The spot (the cluster, and the stand-in holding what hung on the Minimap) at homeAlpha of the
-- cluster's own alpha: read when it first fades, put back at 1 (spike MinimapTakeover.lua:585-588,
-- MinimapMode.lua:150-185).
local own, applied = nil, 1
Game.Apply("home", function(view)
	local a = view.window.homeAlpha
	if a == applied then return end
	own, applied = own or MinimapCluster:GetAlpha(), a
	MinimapCluster:SetAlpha(own * a)
	MagicMapAtlasMinimapStandIn:SetAlpha(own * a)
	if a == 1 then own = nil end
end)

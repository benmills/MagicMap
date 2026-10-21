-- Blizzard's Minimap rim parts while the takeover has it (View.chrome, types/view.lua MM.ViewChrome),
-- after the takeover's own apply step (game/Minimap.lua), so a release puts them back that frame:
--   questRing false: its quest, dig-site and bonus-objective rings (the patterned circle where an
--     area runs past its edge) sized 0: they mark a rim we don't show
--   rimArrows false: its rim's icons, the big arrows toward your target, pushed far out, off
--     screen (the client won't swap their art): our edge arrow points the way instead
-- nil, not engaged, or logging out: as Blizzard has them.
-- (spike da0a49c^:MinimapTakeover.lua:213-231 ClearRim, before the Minimap became only a sensor)

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

Game.Apply("chrome", function(view)
	local c = Game.minimap.engaged and view.chrome
	Set(c and c.questRing == false or false, c and c.rimArrows == false or false)
end)

Runtime.On("PLAYER_LOGOUT", "game.chrome logout", function() Set(false, false) end)

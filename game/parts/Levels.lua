-- obs.levels (types/observation.lua), on change: each map's level range as the client gives it,
-- { lo, hi } (C_Map.GetMapLevels: the spike's inspector, ZoneInfo.lua:58-69), for every map Atlas has; one
-- it gives none (0) is missing. Read once, at the first observe.

local _, ns = ...
local Atlas, Game = ns.Atlas, ns.Game

local levels

Game.Part("levels", function()
	if levels then return levels end
	levels = {}
	for _, id in ipairs(Atlas.UiMapIDs()) do
		local lo, hi = C_Map.GetMapLevels(id)
		if hi > 0 then levels[id] = { lo, hi } end
	end
	return levels
end)

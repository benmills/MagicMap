-- Zone and subzone borders traced offline from the terrain's chunk areas
-- (Data/Borders.lua). Area names are the game's to give, so they're not here.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

-- { lines = { { kind, areaA, areaB, fadeStart, fadeEnd, x1, y1, ... } },
--   labels = { { areaID, col, row, weight, kind } } }, in tile units.
function Atlas.Borders(inst)
	return MagicMap_Borders and MagicMap_Borders[inst]
end

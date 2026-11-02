-- The spot for each zone's and subzone's name, worked out offline from the terrain's chunk areas
-- (Data/Anchors.lua, see docs/atlas-data.md). Area names are the game's to give, so they're not here.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)

-- { { areaID, col, row, weight (land chunks), kind (1: a zone, 2: a subzone) } } in tile units.
function Atlas.Anchors(inst)
	return Data.Anchors and Data.Anchors[inst]
end

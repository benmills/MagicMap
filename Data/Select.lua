-- Only the tile set for this client's version is kept in memory. Each
-- Data/Tiles_<product>.lua asks first and returns early if it isn't wanted.
-- Retail ("wow") loads last and is the fallback when nothing else matched.
local major, minor = (GetBuildInfo()):match("^(%d+)%.(%d+)")

function MagicMap_WantTileSet(product, version)
	if MagicMap_TileSets and next(MagicMap_TileSets) then return false end
	local a, b = version:match("^(%d+)%.(%d+)")
	return (a == major and b == minor) or product == "wow"
end

-- Terrain heights (Data/Heights_<product>.lua) belong to one exact terrain
-- version: load them only alongside the tile set they were generated with.
function MagicMap_WantHeights(product, version)
	local set = MagicMap_TileSets and MagicMap_TileSets[product]
	return MagicMap_ActiveProduct == product and set ~= nil and set.version == version
end

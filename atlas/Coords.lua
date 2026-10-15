-- Atlas: facts that hold. Plain Lua 5.1; reads no system and no WoW API.
--
-- Tile space: (col, row) as floats, matching the minimap file names
-- map<col>_<row>. Tile (0,0) is the north-west corner of a 64x64 grid;
-- col grows east, row grows south. key = col * 64 + row.

local ADDON, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

-- The addon's folder (its name), which data paths (Data/Sea.lua's dir) are relative to.
Atlas.ROOT = "Interface\\AddOns\\" .. ADDON .. "\\"

Atlas.TILE_YARDS = 1600 / 3 -- one ADT / minimap tile = 533.33 yards
local TILE_YARDS = Atlas.TILE_YARDS

-- World yards in UnitPosition's order: (north axis, west axis).
function Atlas.WorldToTile(north, west)
	return 32 - west / TILE_YARDS, 32 - north / TILE_YARDS
end

function Atlas.TileToWorld(col, row)
	return (32 - row) * TILE_YARDS, (32 - col) * TILE_YARDS
end

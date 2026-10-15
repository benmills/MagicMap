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

-- The generated data (Data/*.lua) is ns.Data.<Name>, never a global (docs/atlas-data.md):
-- a global is shared with every addon (the MagicMap spike had the same names, E1).
-- Each file records its format in ns.Data.formats; a dataset whose format isn't the one
-- Atlas reads is dropped (Atlas answers as if it were missing) and named in one error, last.
Atlas.FORMATS = {
	Tiles = 1, TileColor = 1, Sea = 1, Borders = 1, Walk = 1, UiMaps = 1, Areas = 1,
	AreaGrid = 1, Places = 1, ItemIcons = 1, Npcs = 1, Objects = 1, Items = 1, Quests = 1,
}
local Data = ns.Data or {}; ns.Data = Data
Atlas.Data = Data -- raw datasets, read only: for counts (game/Validate.lua); use Atlas's functions
local stale, formats = {}, Data.formats or {}
for name, want in pairs(Atlas.FORMATS) do
	if Data[name] ~= nil and formats[name] ~= want then
		stale[#stale + 1] = string.format("Data/%s.lua is format %s, Atlas reads %d", name, tostring(formats[name]), want)
		Data[name] = nil
	end
end
if #stale > 0 then
	table.sort(stale)
	error(ADDON .. ": " .. table.concat(stale, "; ") .. ": regenerate (README, tools/gen_*.py)", 0)
end

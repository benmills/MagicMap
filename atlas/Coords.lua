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
-- One row per Data file: a package adds or bumps only its own (tools/mmtools/luaout.py: the same rows).
Atlas.FORMATS = {
	Tiles = 1,     -- Data/Tiles.lua (tools/gen_tiles.py)
	TileColor = 1, -- Data/TileColor.lua (tools/gen_tilecolor.py)
	Sea = 1,       -- Data/Sea.lua (tools/gen_sea.py)
	Borders = 2,   -- Data/Borders.lua (tools/gen_borders.py)
	Walk = 1,      -- Data/Walk.lua (tools/gen_walk.py)
	UiMaps = 1,    -- Data/UiMaps.lua (tools/gen_world.py)
	Areas = 1,     -- Data/Areas.lua (tools/gen_world.py)
	AreaGrid = 1,  -- Data/AreaGrid.lua (tools/gen_areagrid.py)
	Places = 1,    -- Data/Places.lua (tools/gen_world.py)
	Labels = 1,    -- Data/Labels.lua (tools/gen_labels.py)
	ItemIcons = 1, -- Data/ItemIcons.lua (tools/gen_world.py)
	Npcs = 1,      -- Data/Npcs.lua (tools/gen_questie.py)
	Objects = 1,   -- Data/Objects.lua (tools/gen_questie.py)
	Items = 1,     -- Data/Items.lua (tools/gen_questie.py)
	Quests = 1,    -- Data/Quests.lua (tools/gen_questie.py)
	BlipServices = 2, -- Data/BlipServices.lua (tools/gen_questie.py)
}
local Data = ns.Data or {}; ns.Data = Data
Atlas.Data = Data -- raw datasets, read only: for tests and game/NoData.lua (which data loaded); use Atlas's functions
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

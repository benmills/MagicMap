-- The tile set (Data/Tiles.lua, from WoW Forever's own WDT files) and how
-- each tile is drawn (Data/TileColor.lua).

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

local function MapData(inst)
	local maps = MagicMap_Tiles and MagicMap_Tiles.maps
	return maps and maps[inst]
end

local maps -- sorted list, built once
function Atlas.Maps()
	if maps then return maps end
	maps = {}
	for inst, m in pairs(MagicMap_Tiles and MagicMap_Tiles.maps or {}) do
		maps[#maps + 1] = { inst = inst, name = m.name, kind = m.kind, continent = m.continent, bg = m.bg }
	end
	table.sort(maps, function(a, b) return a.inst < b.inst end)
	return maps
end

function Atlas.Tiles(inst)
	local m = MapData(inst)
	return m and m.tiles
end

-- The tile-space bounds of a map's tiles.
local bounds = {}
function Atlas.TileBounds(inst)
	local b = bounds[inst]
	if b == nil then
		b = false
		local tiles = Atlas.Tiles(inst)
		if tiles then
			local c0, r0, c1, r1 = 64, 64, 0, 0
			for key in pairs(tiles) do
				local col, row = math.floor(key / 64), key % 64
				c0, r0 = math.min(c0, col), math.min(r0, row)
				c1, r1 = math.max(c1, col + 1), math.max(r1, row + 1)
			end
			if c1 > c0 then b = { c0, r0, c1, r1 } end
		end
		bounds[inst] = b
	end
	if b then return b[1], b[2], b[3], b[4] end
end

-- Is a tile drawn at key? Open sea tiles aren't, so beside them counts as open.
function Atlas.Drawn(inst, key)
	local tiles = Atlas.Tiles(inst)
	local colors = MagicMap_TileColor and MagicMap_TileColor[inst]
	return tiles and tiles[key] and not (colors and colors.sea and colors.sea[key]) and true or false
end

-- tint: drawn colour = texel * m + a, for tiles baked off from their neighbours.
-- edge: each open side's mean colour, to spill outward. sea: open sea all over (not drawn).
local info = {} -- [inst][key] -> info | false
function Atlas.TileInfo(inst, key)
	local cache = info[inst]
	if not cache then
		cache = {}
		info[inst] = cache
	end
	local t = cache[key]
	if t == nil then
		local tiles = Atlas.Tiles(inst)
		local fdid = tiles and tiles[key]
		t = false
		if fdid then
			local c = MagicMap_TileColor and MagicMap_TileColor[inst] or {}
			t = { fdid = fdid, tint = c.tint and c.tint[key], edge = c.edge and c.edge[key],
				sea = c.sea and c.sea[key] and true or false }
		end
		cache[key] = t
	end
	return t or nil
end

-- The tile set (Data/Tiles.lua, from WoW Forever's own WDT files), less the
-- open-sea tiles (Data/TileColor.lua's sea[]: one flat colour, the backdrop's).

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)

local function MapData(inst)
	local maps = Data.Tiles and Data.Tiles.maps
	return maps and maps[inst]
end

local maps -- sorted list, built once
function Atlas.Maps()
	if maps then return maps end
	maps = {}
	for inst, m in pairs(Data.Tiles and Data.Tiles.maps or {}) do
		maps[#maps + 1] = { inst = inst, name = m.name, kind = m.kind, continent = m.continent, bg = m.bg }
	end
	table.sort(maps, function(a, b) return a.inst < b.inst end)
	return maps
end

function Atlas.Tiles(inst)
	local m = MapData(inst)
	return m and m.tiles
end

-- The tile set's product and build (Core.lua:417-422: /mm tiles, the title's debug line).
function Atlas.TileSet()
	local set = Data.Tiles
	return set and set.product, set and set.version
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

-- The picture for a sea tile that leaves a block in the sea (Data/Patches.lua, tools/gen_patches.py), its path; nil: none.
local function Patch(inst, key)
	local p = Data.Patches and Data.Patches[inst]
	return p and p[key] and Atlas.ROOT .. p[key]
end

-- Is a tile drawn at key? Open sea tiles aren't, so beside them counts as open; but for a patched one.
function Atlas.Drawn(inst, key)
	local tiles = Atlas.Tiles(inst)
	local colors = Data.TileColor and Data.TileColor[inst]
	return tiles and tiles[key] and (Patch(inst, key) or not (colors and colors.sea and colors.sea[key])) and true or false
end

-- A map's ocean (Data/Sea.lua, tools/gen_sea.py) and the colour past it; nil: none.
function Atlas.Sea(inst)
	local s = Data.Sea
	return s and s[inst]
end
function Atlas.SeaDeep() return Data.Sea.deep end

-- A map's AI repaints (Data/Repaint.lua, tools/ai_map.py ship): { col, row, file, sublevel, ... }, a tile each; nil: none.
function Atlas.Repaint(inst)
	local r = Data.Repaint
	return r and r.maps[inst]
end
-- The game build they're good for (as "1.60.1.70532"); nil: none shipped.
function Atlas.RepaintBuild()
	local r = Data.Repaint
	return r and r.build
end
-- Whether the repaints fit a client build ("1.60.1.70888"): the one they're stamped for, or a later build of the same
-- version. A build within a version has left the tiles under them alone (70707, 70862, 70888: tools/ai_map.py check
-- found all unchanged each time), so only a new version (or an older build) turns them off; ai_map.py check is still
-- run on each new build, and a place whose tiles changed is repainted or dropped.
local function Split(b)
	local v, n = tostring(b):match("^(.*)%.(%d+)$")
	return v, tonumber(n)
end
function Atlas.RepaintFits(build)
	local want = Atlas.RepaintBuild()
	if not (want and build) then return false end
	local wv, wn = Split(want)
	local hv, hn = Split(build)
	return wv ~= nil and wv == hv and hn >= wn
end

-- What a drawn tile shows: its patch, or Blizzard's tile (a FileDataID).
function Atlas.TileArt(inst, key)
	return Patch(inst, key) or Atlas.Tiles(inst)[key]
end

-- A map's base picture (Data/Base.lua, tools/gen_base.py), the continents'; nil: none.
-- { file (under the addon's folder), c0, r0, c1, r1 (the tile rect it covers), px (a tile), w, h (the texture) }
function Atlas.Base(inst)
	local b = Data.Base
	return b and b[inst]
end


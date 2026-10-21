-- Areas (Data/Areas.lua, AreaTable) and which one each terrain chunk is in
-- (Data/AreaGrid.lua). A zone is an area with no parent; the rest are its
-- subzones.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)

local CHUNKS = 16
local NONE = {}

local areas = {} -- areaID -> named row | false
function Atlas.Area(id)
	local a = areas[id]
	if a == nil then
		local rows = Data.Areas or NONE
		local r = rows[id]
		a = false
		if r then
			local zone = id
			while rows[zone][2] and rows[rows[zone][2]] do
				zone = rows[zone][2]
			end
			a = { id = id, name = r[1], parent = r[2], inst = r[3], level = r[4], faction = r[5],
				uiMap = r[6], zone = zone }
		end
		areas[id] = a
	end
	return a or nil
end

-- palette index per letter: a..z 1..26, A..Z 27..52
local INDEX = {}
for i = 1, 26 do
	INDEX[string.char(96 + i)] = i
	INDEX[string.char(64 + i)] = 26 + i
end

local tiles = {} -- [inst][tile key] = { palette, its 256 chunk letters decoded } | false
local function Tile(inst, key)
	local cache = tiles[inst]
	if not cache then
		cache = {}
		tiles[inst] = cache
	end
	local t = cache[key]
	if t == nil then
		local enc = Data.AreaGrid and Data.AreaGrid[inst] and Data.AreaGrid[inst][key]
		t = false
		if enc then
			local parts = {}
			for letter, n in enc[2]:gmatch("(%a)(%d*)") do parts[#parts + 1] = letter:rep(tonumber(n) or 1) end
			t = { enc[1], table.concat(parts) }
		end
		cache[key] = t
	end
	return t
end

-- The areaID of the chunk under (col, row).
function Atlas.AreaAt(inst, col, row)
	local c, r = math.floor(col), math.floor(row)
	local t = Tile(inst, c * 64 + r)
	if not t then return nil end
	local ix, iy = math.floor((col - c) * CHUNKS), math.floor((row - r) * CHUNKS)
	local id = t[1][INDEX[t[2]:sub(iy * CHUNKS + ix + 1, iy * CHUNKS + ix + 1)]]
	if id == 0 then return nil end
	return id
end

-- The zone at (col, row): its uiMap (mapID, name, normalized x, y), zone and area IDs. Only on a
-- continent, a zone whose map is on it: the spike asks the continent's map (Layers.lua:2059-2070), so
-- an instance's map (Ruins of Ahn'Qiraj: Silithus' chunks) has none.
function Atlas.ZoneAt(inst, col, row)
	if not Atlas.Continent(inst) then return nil end
	local id = Atlas.AreaAt(inst, col, row)
	local area = id and Atlas.Area(id)
	if not area then return nil end
	local mapID = Atlas.Area(area.zone).uiMap
	local r = mapID and Atlas.MapRect(mapID)
	if not (r and r.inst == inst) then return nil end
	local x, y = Atlas.TileToMap(mapID, col, row)
	return { mapID = mapID, name = Atlas.UiMap(mapID).name, x = x, y = y, zone = area.zone, area = id }
end

-- The zone whose map has (col, row): ZoneAt's, only where it's on that zone's map (x, y in 0..1), as the
-- client's zone at a point on the continent (C_Map.GetMapInfoAtPosition: Layers.lua:2059-2070); nil: none.
-- Where a waypoint can go, and a /way line names: Game's waypoint and way, UI's offers of them.
function Atlas.ZoneMapAt(inst, col, row)
	local z = Atlas.ZoneAt(inst, col, row)
	if z and z.x >= 0 and z.x <= 1 and z.y >= 0 and z.y <= 1 then return z end
end

-- A zone's level range, from its subzones' exploration levels (zones have none).
-- The first call indexes every area: step(), if given, is called every 128 so a
-- caller can spread it over frames (as Atlas.Rares).
local levels -- zone areaID -> { min, max }
function Atlas.ZoneLevels(zone, step)
	if not levels then
		local index, n = {}, 0
		for id, r in pairs(Data.Areas or NONE) do
			if r[4] and r[4] > 0 then
				local z = Atlas.Area(id).zone
				local l = index[z]
				if l then
					l[1], l[2] = math.min(l[1], r[4]), math.max(l[2], r[4])
				else
					index[z] = { r[4], r[4] }
				end
			end
			n = n + 1
			if step and n % 128 == 0 then step() end
		end
		levels = index
	end
	local l = levels[zone]
	if l then return l[1], l[2] end
end

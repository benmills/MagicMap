-- The map catalogue: every uiMap's rectangle in tile space, each map's
-- continent, zones and quest maps, and a coarse grid of which zone covers
-- where. Scan builds it once at login through readers Game hands it;
-- afterwards everything here is a lookup.
--
-- readers = {
--   GetMapInfo(uiMapID) -> { name, mapType, parentMapID } | nil
--   GetWorldPosFromMapPos(uiMapID, x, y) -> inst, north, west | nil
--   GetMapInfoAtPosition(uiMapID, x, y) -> { mapID, name } | nil
-- }

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

local WORLD, CONTINENT, ZONE, MICRO = 1, 2, 3, 5 -- Enum.UIMapType
local MAX_MAP_ID = 4000
local CELL = 0.25 -- zone grid cell, in tiles (~133 yards)
local PACE_EVERY = 50 -- calls to readers between paces

local rects = {}      -- uiMapID -> { inst, col0, row0, col1, row1 }
local zones = {}      -- inst -> zone rects (+ name, uiMapID), sorted by name
local continents = {} -- inst -> uiMapID of the continent map
local questMaps = {}  -- inst -> uiMapIDs (zones + micro maps) that can carry quests
local grids = {}      -- inst -> { cont, c0, r0, nc, nr, ids = { zone uiMapID or 0 } }
local names = {}      -- uiMapID -> name, as the zone grid saw it

-- A uiMap is an axis-aligned rectangle in world space, so two corners give a
-- linear transform between its normalized coords and tile space.
local function Rect(readers, uiMapID)
	local inst, top, left = readers.GetWorldPosFromMapPos(uiMapID, 0, 0)
	local inst2, bottom, right = readers.GetWorldPosFromMapPos(uiMapID, 1, 1)
	if not inst or inst ~= inst2 then return nil end
	local col0, row0 = Atlas.WorldToTile(top, left)
	local col1, row1 = Atlas.WorldToTile(bottom, right)
	if col1 > col0 and row1 > row0 then
		return { inst = inst, col0 = col0, row0 = row0, col1 = col1, row1 = row1 }
	end
end

function Atlas.MapRect(uiMapID)
	return rects[uiMapID]
end

-- uiMap normalized (x, y) -> inst, col, row
function Atlas.MapToTile(uiMapID, x, y)
	local r = rects[uiMapID]
	if not r then return nil end
	return r.inst, r.col0 + (r.col1 - r.col0) * x, r.row0 + (r.row1 - r.row0) * y
end

-- tile (col, row) -> uiMap normalized (x, y)
function Atlas.TileToMap(uiMapID, col, row)
	local r = rects[uiMapID]
	if not r then return nil end
	return (col - r.col0) / (r.col1 - r.col0), (row - r.row0) / (r.row1 - r.row0)
end

local function SampleZones(readers, inst, cont, tick)
	local r = rects[cont]
	local grid = { cont = cont, c0 = r.col0, r0 = r.row0, ids = {},
		nc = math.ceil((r.col1 - r.col0) / CELL), nr = math.ceil((r.row1 - r.row0) / CELL) }
	for j = 0, grid.nr - 1 do
		for i = 0, grid.nc - 1 do
			local x, y = Atlas.TileToMap(cont, grid.c0 + (i + 0.5) * CELL, grid.r0 + (j + 0.5) * CELL)
			local info = readers.GetMapInfoAtPosition(cont, x, y)
			local id = info and info.mapID ~= cont and info.mapID or 0
			if id ~= 0 then names[id] = info.name end
			grid.ids[j * grid.nc + i + 1] = id
			tick()
		end
	end
	grids[inst] = grid
end

function Atlas.Scan(readers, pace)
	rects, zones, continents, questMaps, grids, names = {}, {}, {}, {}, {}, {}
	local n = 0
	local function tick()
		n = n + 1
		if pace and n % PACE_EVERY == 0 then pace() end
	end
	local seenNames, continentArea = {}, {}
	for uiMapID = 1, MAX_MAP_ID do
		local info = readers.GetMapInfo(uiMapID)
		if info then
			local r = Rect(readers, uiMapID)
			rects[uiMapID] = r
			local t = info.mapType
			if r and Atlas.Tiles(r.inst) and info.name and info.name ~= ""
				and (t == ZONE or t == CONTINENT or t == MICRO) then
				if t ~= CONTINENT then
					questMaps[r.inst] = questMaps[r.inst] or {}
					table.insert(questMaps[r.inst], uiMapID)
				end
				if t == CONTINENT then
					-- Several continent maps can share an instance (flight maps too); the
					-- real one hangs off a world map, and among those keep the biggest.
					local parent = info.parentMapID and readers.GetMapInfo(info.parentMapID)
					local area = (r.col1 - r.col0) * (r.row1 - r.row0)
					if parent and parent.mapType == WORLD then area = area + 1e6 end
					if area > (continentArea[r.inst] or 0) then
						continentArea[r.inst] = area
						continents[r.inst] = uiMapID
					end
				elseif t == ZONE then
					-- Micro maps are for quests only.
					local key = r.inst .. ":" .. info.name
					if not seenNames[key] then
						seenNames[key] = true
						zones[r.inst] = zones[r.inst] or {}
						table.insert(zones[r.inst], { name = info.name, uiMapID = uiMapID,
							col0 = r.col0, col1 = r.col1, row0 = r.row0, row1 = r.row1 })
					end
				end
			end
		end
		tick()
	end
	for _, list in pairs(zones) do
		table.sort(list, function(a, b) return a.name < b.name end)
	end
	for inst, cont in pairs(continents) do SampleZones(readers, inst, cont, tick) end
end

local NONE = {}
function Atlas.Zones(inst) return zones[inst] or NONE end
function Atlas.Continent(inst) return continents[inst] end
function Atlas.QuestMaps(inst) return questMaps[inst] or NONE end

-- The zone covering (col, row), from the grid Scan sampled.
function Atlas.ZoneAt(inst, col, row)
	local grid = grids[inst]
	if not grid then return nil end
	local i, j = math.floor((col - grid.c0) / CELL), math.floor((row - grid.r0) / CELL)
	if i < 0 or j < 0 or i >= grid.nc or j >= grid.nr then return nil end
	local id = grid.ids[j * grid.nc + i + 1]
	if id == 0 then return nil end
	local x, y = Atlas.TileToMap(id, col, row)
	if not x then return nil end
	return { mapID = id, name = names[id], x = x, y = y }
end

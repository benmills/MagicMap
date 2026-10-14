-- The uiMaps (Data/UiMaps.lua): each map's rectangle in tile space, each
-- instance's continent and zones.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

local WORLD, CONTINENT, ZONE, MICRO = 1, 2, 3, 5 -- Enum.UIMapType
local NONE = {}

local maps = {} -- uiMapID -> named row | false
function Atlas.UiMap(id)
	local m = maps[id]
	if m == nil then
		local r = MagicMap_UiMaps[id]
		m = r and { id = id, name = r[1], mapType = r[2], parent = r[3], inst = r[4],
			col0 = r[5], row0 = r[6], col1 = r[7], row1 = r[8], areaID = r[9] } or false
		maps[id] = m
	end
	return m or nil
end

local rects = {} -- uiMapID -> { inst, col0, row0, col1, row1 } | false
function Atlas.MapRect(id)
	local r = rects[id]
	if r == nil then
		local m = Atlas.UiMap(id)
		r = m and m.col0 and { inst = m.inst, col0 = m.col0, row0 = m.row0, col1 = m.col1, row1 = m.row1 } or false
		rects[id] = r
	end
	return r or nil
end

-- uiMap normalized (x, y) -> inst, col, row
function Atlas.MapToTile(id, x, y)
	local r = Atlas.MapRect(id)
	if not r then return nil end
	return r.inst, r.col0 + (r.col1 - r.col0) * x, r.row0 + (r.row1 - r.row0) * y
end

-- tile (col, row) -> uiMap normalized (x, y)
function Atlas.TileToMap(id, col, row)
	local r = Atlas.MapRect(id)
	if not r then return nil end
	return (col - r.col0) / (r.col1 - r.col0), (row - r.row0) / (r.row1 - r.row0)
end

-- Per instance: zones (first of each name, sorted by name), the continent
-- (the one hanging off a world map; 1463/1464 are parentless duplicates) and
-- quest maps (zones + micro maps). Built once, on first use.
local zones, continents, questMaps
local function Index()
	zones, continents, questMaps = {}, {}, {}
	local ids = {}
	for id in pairs(MagicMap_UiMaps) do ids[#ids + 1] = id end
	table.sort(ids)
	local seen = {}
	for _, id in ipairs(ids) do
		local m = Atlas.UiMap(id)
		local inst = m.col0 and m.inst
		if inst and m.mapType == CONTINENT then
			local p = m.parent and Atlas.UiMap(m.parent)
			if p and p.mapType == WORLD then continents[inst] = id end
		elseif inst and (m.mapType == ZONE or m.mapType == MICRO) then
			questMaps[inst] = questMaps[inst] or {}
			table.insert(questMaps[inst], id)
			local key = inst .. ":" .. m.name
			if m.mapType == ZONE and not seen[key] then
				seen[key] = true
				zones[inst] = zones[inst] or {}
				table.insert(zones[inst], { name = m.name, uiMapID = id,
					col0 = m.col0, row0 = m.row0, col1 = m.col1, row1 = m.row1 })
			end
		end
	end
	for _, list in pairs(zones) do
		table.sort(list, function(a, b) return a.name < b.name end)
	end
end

function Atlas.Zones(inst)
	if not zones then Index() end
	return zones[inst] or NONE
end

function Atlas.Continent(inst)
	if not continents then Index() end
	return continents[inst]
end

function Atlas.QuestMaps(inst)
	if not questMaps then Index() end
	return questMaps[inst] or NONE
end

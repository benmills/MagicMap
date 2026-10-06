-- What's at a spot on the map, for the top of the big map's right-click menu
-- (Core's OpenMapMenuAt): the zone and sub-zone, coordinates, level range,
-- how far it is from you, quest areas under it and the nearest landmarks.
-- A few short colour-coded lines; anything the client can't say is skipped.
-- Gathered once per right-click, never per frame.

local ADDON, ns = ...
local state = ns.state

local TILE_YARDS = 1600 / 3
local NEAR_YARDS = 900       -- landmarks further from the click than this aren't "nearby"
local SUBZONE_NEAR_YARDS = 350 -- an unexplored spot is "near" a sub-zone label this close
local MAX_QUESTS = 2
local MAX_NEARBY = 2

local GOLD, WHITE, GREY, DIM = "|cffffd100", "|cffffffff", "|cffa8a8a8", "|cff808080"
local SEP = DIM .. "  ·  |r"

-- Notable pins, in order of interest: layer key, label, and for services
-- the kinds that count (Landmarks.lua's entry.kind).
local NOTABLE = {
	{ key = "flight", label = "Flight point" },
	{ key = "dungeons", label = "Dungeon" },
	{ key = "services", label = "Innkeeper", kinds = { inn = true } },
	{ key = "graveyards", label = "Graveyard" },
}

local function SafeCall(fn, ...)
	if not fn then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end

-- 1,234
local function Thousands(n)
	local s = tostring(math.floor(n + 0.5))
	local out
	repeat
		s, out = s:sub(1, -4), s:sub(-3) .. (out and ("," .. out) or "")
	until s == ""
	return out
end

-- Rounded to what a glance needs: 5 yards close by, 10 further out.
local function Yards(tiles)
	local yd = tiles * TILE_YARDS
	local step = yd < 200 and 5 or 10
	return Thousands(math.floor(yd / step + 0.5) * step) .. " yd"
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
-- Compass point from (c0, r0) to (c1, r1); columns run east, rows south.
local function Direction(c0, r0, c1, r1)
	local a = math.atan2(c1 - c0, r0 - r1) -- 0 = north, clockwise
	return COMPASS[math.floor(a / (math.pi / 4) + 0.5) % 8 + 1]
end

local function Dist(c0, r0, c1, r1) return math.sqrt((c1 - c0) ^ 2 + (r1 - r0) ^ 2) end

-- "Level 1-10", coloured against yours: green in range, red below it, grey past it.
local function LevelLine(mapID)
	if not (C_Map.GetMapLevels) then return nil end
	local lo, hi = SafeCall(C_Map.GetMapLevels, mapID)
	if type(lo) ~= "number" or type(hi) ~= "number" or hi <= 0 then return nil end
	local mine = UnitLevel and UnitLevel("player")
	local color = WHITE
	if type(mine) == "number" and mine > 0 then
		color = mine < lo and "|cffff6040" or mine > hi and GREY or "|cff40c040"
	end
	local range = lo == hi and tostring(lo) or (lo .. "-" .. hi)
	return GREY .. "Level|r " .. color .. range .. "|r"
end

-- Sub-zone names explored at the spot (exploration knows the area there);
-- false if the client says nothing is explored, nil if it can't say.
local function ExploredAreas(zone)
	local api = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
	if not api or not CreateVector2D then return nil end
	local ids = SafeCall(api, zone.mapID, CreateVector2D(zone.x, zone.y))
	if not ids or #ids == 0 then
		-- Cities have no fog of war to lift.
		if C_Map.IsCityMap and SafeCall(C_Map.IsCityMap, zone.mapID) then return nil end
		return false
	end
	local names, seen = {}, { [zone.name] = true }
	for _, id in ipairs(ids) do
		local name = C_Map.GetAreaInfo and SafeCall(C_Map.GetAreaInfo, id)
		if name and name ~= "" and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	return names
end

-- Sub-zone and coordinates: "Goldshire  ·  42.1, 65.8".
local function PlaceLine(zone, col, row)
	local coords = string.format("%.1f, %.1f", zone.x * 100, zone.y * 100)
	local areas = ExploredAreas(zone)
	local place
	if areas and #areas > 0 then
		place = WHITE .. table.concat(areas, " / ", 1, math.min(#areas, 2)) .. "|r"
	elseif areas == false then
		place = DIM .. "Unexplored|r"
		-- The offline borders still know the sub-zones' names (they're labelled on the map).
		local name, d, lc, lr
		if ns.SubzoneNear then name, d, lc, lr = ns.SubzoneNear(col, row) end
		if name and d * TILE_YARDS <= SUBZONE_NEAR_YARDS and name ~= zone.name then
			local at = ns.GetZoneAt(lc, lr) -- the label's own zone: not one across a border
			if at and at.mapID == zone.mapID then place = place .. DIM .. ", near|r " .. WHITE .. name .. "|r" end
		end
	end
	return place and (place .. SEP .. GREY .. coords .. "|r") or (GREY .. coords .. "|r")
end

-- How far and which way from you, when you're on this map.
local function YouLine(col, row)
	if not (state.playerCol and state.playerMap == state.map) then return nil end
	local d = Dist(state.playerCol, state.playerRow, col, row)
	if d * TILE_YARDS < 15 then return GREY .. "You're here|r" end
	return WHITE .. Yards(d) .. "|r " .. GREY .. Direction(state.playerCol, state.playerRow, col, row) .. " of you|r"
end

local function QuestLines(col, row, out)
	local quests = ns.QuestsAt and ns.QuestsAt(col, row) or {}
	table.sort(quests, function(a, b)
		if a.followed ~= b.followed then return a.followed end
		return a.title < b.title
	end)
	for i, q in ipairs(quests) do
		if i > MAX_QUESTS then
			out[#out] = out[#out] .. DIM .. string.format("  (+%d more)", #quests - MAX_QUESTS) .. "|r"
			break
		end
		if q.followed then
			out[#out + 1] = GOLD .. "Quest|r " .. GOLD .. q.title .. "|r " .. DIM .. "(following)|r"
		else
			out[#out + 1] = GREY .. "Quest|r " .. WHITE .. q.title .. "|r"
		end
	end
end

-- The nearest notable landmarks around the click, one per kind, closest first.
local function NearbyLines(col, row, out)
	if not ns.LayerPins then return end
	local found = {}
	for _, n in ipairs(NOTABLE) do
		local best, bestD
		for _, e in ipairs(ns.LayerPins(n.key) or {}) do
			if e.col and (not n.kinds or n.kinds[e.kind]) then
				local d = Dist(col, row, e.col, e.row)
				if d * TILE_YARDS <= NEAR_YARDS and (not bestD or d < bestD) then best, bestD = e, d end
			end
		end
		if best then found[#found + 1] = { e = best, d = bestD, label = n.label } end
	end
	table.sort(found, function(a, b) return a.d < b.d end)
	for i = 1, math.min(#found, MAX_NEARBY) do
		local f = found[i]
		local where = f.d * TILE_YARDS < 15 and "here"
			or (Yards(f.d) .. " " .. Direction(col, row, f.e.col, f.e.row))
		local title = f.e.title and f.e.title ~= f.label and (WHITE .. f.e.title .. "|r" .. SEP) or ""
		out[#out + 1] = GREY .. f.label .. "|r " .. title .. GREY .. where .. "|r"
	end
end

-- Lines describing tile (col, row) on the shown map, the first being the
-- zone's name (gold); nil if there's nothing to say.
function ns.ZoneInfoAt(col, row)
	if not (col and state.map and C_Map) then return nil end
	local out = {}
	local zone = ns.GetZoneAt and ns.GetZoneAt(col, row)
	if zone then
		out[1] = GOLD .. zone.name .. "|r"
		out[2] = PlaceLine(zone, col, row)
		local levels = LevelLine(zone.mapID)
		local you = YouLine(col, row)
		if levels and you then
			out[#out + 1] = levels .. SEP .. you
		else
			out[#out + 1] = levels or you
		end
	else
		-- Open sea, or a map without zones: name the map, and the distance.
		local cont = ns.GetContinentMapID and ns.GetContinentMapID(state.map)
		local info = cont and SafeCall(C_Map.GetMapInfo, cont)
		if info and info.name then out[1] = GOLD .. info.name .. "|r" end
		out[#out + 1] = YouLine(col, row)
	end
	QuestLines(col, row, out)
	NearbyLines(col, row, out)
	return #out > 0 and out or nil
end

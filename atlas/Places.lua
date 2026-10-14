-- Places (Data/Places.lua): flight points and paths, points of interest,
-- dungeons and their entrances.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

local NONE = {}

-- Rows of one Places table grouped per inst as named tables, sorted by id.
local function ByInst(rows, instOf, named)
	local out = {}
	local ids = {}
	for id in pairs(rows) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local inst = instOf(rows[id])
		if inst then
			out[inst] = out[inst] or {}
			table.insert(out[inst], named(id, rows[id]))
		end
	end
	return out
end

local flights
function Atlas.FlightPoints(inst)
	if not flights then
		flights = ByInst(MagicMap_Places.flight, function(r) return r[3] end, function(id, r)
			return { id = id, name = r[1], faction = r[2], col = r[4], row = r[5], areaID = r[6] }
		end)
	end
	return flights[inst] or NONE
end

local paths
function Atlas.TaxiPaths()
	if not paths then
		paths = {}
		for i, r in ipairs(MagicMap_Places.taxiPaths) do paths[i] = { from = r[1], to = r[2], cost = r[3] } end
	end
	return paths
end

local pois
function Atlas.POIs(inst)
	if not pois then
		pois = ByInst(MagicMap_Places.pois, function(r) return r[5] end, function(id, r)
			return { id = id, name = r[1], description = r[2], icon = r[3], importance = r[4],
				col = r[6], row = r[7], areaID = r[8] }
		end)
	end
	return pois[inst] or NONE
end

local function Named(id, r)
	return { id = id, name = r[1], kind = r[2], entranceInst = r[3], col = r[4], row = r[5],
		minLevel = r[6], maxPlayers = r[7], bosses = r[8] or NONE }
end

local dungeons = {} -- instID -> named row | false
function Atlas.Dungeon(id)
	local d = dungeons[id]
	if d == nil then
		local r = MagicMap_Places.dungeons[id]
		d = r and Named(id, r) or false
		dungeons[id] = d
	end
	return d or nil
end

local entrances -- entrance inst -> dungeons
function Atlas.Dungeons(inst)
	if not entrances then
		entrances = ByInst(MagicMap_Places.dungeons, function(r) return r[3] end, function(id)
			return Atlas.Dungeon(id)
		end)
	end
	return entrances[inst] or NONE
end

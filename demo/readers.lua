-- Fake C_Map readers for the web demo, backed by demo/catalogue.lua
-- (MagicMap_Catalogue). Same contract as the readers Game hands Atlas.Scan.
local _, ns = ...

local ZONE = 3 -- Enum.UIMapType.Zone

-- assign = { inst, x0, y0, x1, y1, north0, north1, west0, west1 }
local function ToWorld(a, x, y)
	local u = (x - a[2]) / (a[4] - a[2])
	local v = (y - a[3]) / (a[5] - a[3])
	return a[1], a[7] - v * (a[7] - a[6]), a[9] - u * (a[9] - a[8])
end

local maps = MagicMap_Catalogue.maps -- load catalogue.lua first
local r = {}

function r.GetMapInfo(uiMapID)
	local m = maps[uiMapID]
	if m then
		return { name = m.name, mapType = m.mapType, parentMapID = m.parent }
	end
end

-- The first assignment (OrderIndex order) whose normalized rect holds (x, y).
function r.GetWorldPosFromMapPos(uiMapID, x, y)
	local m = maps[uiMapID]
	if not m then return end
	for _, a in ipairs(m.assign) do
		if x >= a[2] and x <= a[4] and y >= a[3] and y <= a[5] then
			return ToWorld(a, x, y)
		end
	end
end

-- The smallest zone on the same instance whose world rect holds the point.
function r.GetMapInfoAtPosition(uiMapID, x, y)
	local inst, north, west = r.GetWorldPosFromMapPos(uiMapID, x, y)
	if not inst then return end
	local best, bestArea
	for id, m in pairs(maps) do
		if m.mapType == ZONE then
			for _, a in ipairs(m.assign) do
				if a[1] == inst and north >= a[6] and north <= a[7] and west >= a[8] and west <= a[9] then
					local area = (a[7] - a[6]) * (a[9] - a[8])
					if not bestArea or area < bestArea then
						best, bestArea = id, area
					end
				end
			end
		end
	end
	if best then
		return { mapID = best, name = maps[best].name }
	end
end

ns.FixtureReaders = r

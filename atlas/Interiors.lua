-- Buildings with indoor minimap pictures (Data/Interiors.lua; docs/decisions/0008-interiors.md):
-- where each is, and per room its floor, subzone name, portals, floor mask and pictures. A
-- building's packed row is decoded the first time it's asked for, and kept.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)

local FLOOR = 98 -- "b": a mask cell with floor

local function Map(inst)
	return Data.Interiors and Data.Interiors[inst]
end

-- The keys of the buildings whose box covers tile point (col, row).
function Atlas.BuildingsAt(inst, col, row)
	local out = {}
	local m = Map(inst)
	for _, key in ipairs(m and m.tiles[math.floor(col) * 64 + math.floor(row)] or out) do
		local b = m.buildings[key]
		if col >= b[1] and col <= b[3] and row >= b[2] and row <= b[4] then out[#out + 1] = key end
	end
	return out
end

local function Mask(enc)
	local parts = {}
	for letter, n in enc:gmatch("(%a)(%d*)") do parts[#parts + 1] = letter:rep(tonumber(n) or 1) end
	return table.concat(parts)
end

-- { key, inst, fid, wmo, col, row, yaw, rooms = { [room] = { zmin, zmax, area, links, pics, floor, underground,
-- over, ... } } }: room the building's group index; links the rooms it has portals to; pics { fid, ox, oy, ux,
-- uy, vx, vy } in tile units, a picture's pixel (u, v) in 0..1 at o + u*U + v*V (U along its width, V down its
-- height); floor its real floor (world height); underground: that > 10 yd under the terrain; over: the rooms
-- whose floor masks overlap its.
local decoded = {} -- [inst][key]
function Atlas.Building(inst, key)
	local cache = decoded[inst]
	if not cache then
		cache = {}
		decoded[inst] = cache
	end
	local b = cache[key]
	if not b then
		local p = assert(loadstring("return " .. Map(inst).buildings[key][5]))()
		b = { key = key, inst = inst, fid = p[1], wmo = p[2], col = p[3], row = p[4], yaw = p[5],
			cos = math.cos(p[5]), sin = math.sin(p[5]), k = p[6], rooms = {} }
		for i, r in pairs(p[7]) do
			local pics, list = {}, r[10]
			for j = 1, #list, 7 do pics[#pics + 1] = { unpack(list, j, j + 6) } end
			b.rooms[i] = { zmin = r[1], zmax = r[2], area = r[3], links = r[4], x0 = r[5], y0 = r[6],
				cols = r[7], rows = r[8], mask = Mask(r[9]), pics = pics, floor = r[11], underground = r[12], over = r[13] }
		end
		cache[key] = b
	end
	return b
end

-- The rooms (sorted) whose floor mask covers tile point (col, row): the point in the building's own
-- coordinates, in mask cells (the prototype's Candidates, docs/evidence/indoors/addon/Test.lua).
function Atlas.RoomsAt(b, col, row)
	local dc, dr = col - b.col, row - b.row
	local x = (dc * b.cos - dr * b.sin) * b.k
	local y = -(dc * b.sin + dr * b.cos) * b.k
	local out = {}
	for i, r in pairs(b.rooms) do
		local c, rr = math.floor(x - r.x0), math.floor(y - r.y0)
		if c >= 0 and c < r.cols and rr >= 0 and rr < r.rows and r.mask:byte(rr * r.cols + c + 1) == FLOOR then
			out[#out + 1] = i
		end
	end
	table.sort(out)
	return out
end

-- A capital's buildings (uiMap 1453..1458; nil: not one): { buildings = { key... }, over = { [key] = { [room] =
-- { { key, room }... } } }, labels = { { text, col, row, size }... } }, over the other buildings' rooms each
-- room's floor overlaps, labels the areas named on its rooms (biggest first; size: their floor's side in
-- tiles, as Atlas.Labels's) (kept).
local cities = {} -- [uiMap]
function Atlas.City(inst, uiMap)
	local c = cities[uiMap]
	local raw = not c and Map(inst) and Map(inst).cities and Map(inst).cities[uiMap]
	if raw then
		c = { buildings = raw[1], over = {}, labels = {} }
		for i, l in ipairs(raw[3]) do c.labels[i] = { text = l[1], col = l[2], row = l[3], size = l[4] } end
		for key, rooms in pairs(raw[2]) do
			local o = {}
			for room, list in pairs(rooms) do
				local two = {}
				for j = 1, #list, 2 do two[#two + 1] = { list[j], list[j + 1] } end
				o[room] = two
			end
			c.over[key] = o
		end
		cities[uiMap] = c
	end
	return c
end

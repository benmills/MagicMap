-- Map names as ranked anchors: what each name is, where it sits and how much
-- it matters. Static facts only; how big, when and whether a name is drawn is
-- the UI's to decide (it places them in rank order, dropping ones that collide).
--
-- Tiers, most important first:
--   continent  the continent's name, at the land's visual centre
--   zone       Data/Borders.lua labels of kind 1, by land area
--   town       AreaPOI towns and cities (Places.lua), capitals first
--   subzone    Data/Borders.lua labels of kind 2, by land area
--   poi        AreaPOI landmarks
-- A town and the subzone label of the same name at the same spot are one
-- name: the town (at its POI, where its pin is). A landmark that duplicates a
-- subzone label is skipped. POIs with a description are events or world-PvP
-- states, not places, so they're left out.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

local NONE = {}
local SAME_SPOT = 0.5 -- tiles (~270 yd): a POI this near a subzone label of its name is that label
local CENTRE_SAMPLES = 4 -- land samples per tile side when finding the continent's visual centre
local TIERS = { continent = 1, zone = 2, town = 3, subzone = 4, poi = 5 }
local TOWN_ICON = { [4] = 1, [5] = 2 } -- AreaPOI icons: 4 town, 5 capital; 6 a place, 2 a lake
local POI_ICON = { [2] = true, [6] = true }

-- The land's visual centre: the land sample farthest from water or the map's
-- edge (a pole of inaccessibility, by a two-pass chamfer distance transform).
local function VisualCentre(inst)
	local c0, r0, c1, r1 = Atlas.TileBounds(inst)
	local tiles = Atlas.Tiles(inst)
	local S, step = CENTRE_SAMPLES, Atlas.Walk.CHUNKS / CENTRE_SAMPLES
	local w, h = (c1 - c0) * S, (r1 - r0) * S
	local d = {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local col, row = c0 + (x + 0.5) / S, r0 + (y + 0.5) / S
			local land = tiles[math.floor(col) * 64 + math.floor(row)]
				and Atlas.Walk.Cell(inst, math.floor(col * Atlas.Walk.CHUNKS), math.floor(row * Atlas.Walk.CHUNKS)) ~= 2
			d[y * w + x] = land and math.huge or 0
		end
	end
	local function Relax(x, y, dx, dy, cost)
		local nx, ny = x + dx, y + dy
		local v = (nx < 0 or ny < 0 or nx >= w or ny >= h) and 0 or d[ny * w + nx]
		if v + cost < d[y * w + x] then d[y * w + x] = v + cost end
	end
	local D = math.sqrt(2)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			Relax(x, y, -1, 0, 1); Relax(x, y, 0, -1, 1); Relax(x, y, -1, -1, D); Relax(x, y, 1, -1, D)
		end
	end
	local best, bx, by = -1, 0, 0
	for y = h - 1, 0, -1 do
		for x = w - 1, 0, -1 do
			Relax(x, y, 1, 0, 1); Relax(x, y, 0, 1, 1); Relax(x, y, 1, 1, D); Relax(x, y, -1, 1, D)
			if d[y * w + x] > best then best, bx, by = d[y * w + x], x, y end
		end
	end
	return c0 + (bx + 0.5) / S, r0 + (by + 0.5) / S
end

local labels = {} -- inst -> anchors
-- { text, col, row, tier, rank, areaID?, poiID?, size? } sorted by rank (1 first).
-- size: the land named (continent, zone or subzone) as the side of a square, in tiles.
function Atlas.Labels(inst)
	if labels[inst] then return labels[inst] end
	local out, subzones, land = {}, {}, 0
	local b = Atlas.Borders(inst)
	for _, l in ipairs(b and b.labels or NONE) do
		local area, col, row, weight, kind = l[1], l[2], l[3], l[4], l[5]
		if kind == 1 then land = land + weight end
		local a = { text = Atlas.Area(area).name, col = col, row = row, tier = kind == 1 and "zone" or "subzone",
			areaID = area, size = math.sqrt(weight) / Atlas.Walk.CHUNKS, score = weight }
		out[#out + 1] = a
		if kind == 2 then subzones[#subzones + 1] = a end
	end
	local function Subzone(name, col, row)
		for _, s in ipairs(subzones) do
			if s.text == name and (s.col - col) ^ 2 + (s.row - row) ^ 2 < SAME_SPOT ^ 2 then return s end
		end
	end
	for _, p in ipairs(Atlas.POIs(inst)) do
		if not p.description then
			local town = TOWN_ICON[p.icon] or (POI_ICON[p.icon] and p.importance >= 2 and 0)
			local same = Subzone(p.name, p.col, p.row)
			if town then
				local a = same or { text = p.name, col = p.col, row = p.row, areaID = p.areaID }
				a.tier, a.poiID, a.score, a.col, a.row = "town", p.id, p.importance * 10 + town, p.col, p.row
				if not same then out[#out + 1] = a end
			elseif POI_ICON[p.icon] and not same then
				out[#out + 1] = { text = p.name, col = p.col, row = p.row, tier = "poi", areaID = p.areaID, poiID = p.id,
					score = 0 }
			end
		end
	end
	local continent = Atlas.Continent(inst)
	if continent and Atlas.TileBounds(inst) then
		local col, row = VisualCentre(inst)
		out[#out + 1] = { text = Atlas.UiMap(continent).name, col = col, row = row, tier = "continent",
			size = math.sqrt(land) / Atlas.Walk.CHUNKS, score = 0 }
	end
	table.sort(out, function(x, y)
		if x.tier ~= y.tier then return TIERS[x.tier] < TIERS[y.tier] end
		if x.score ~= y.score then return x.score > y.score end
		return x.text < y.text
	end)
	for i, a in ipairs(out) do
		a.rank, a.score = i, nil
	end
	labels[inst] = out
	return out
end

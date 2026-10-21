-- Zone borders, zone outlines and label anchors, traced offline from the
-- terrain's chunk areas and smoothed there (Data/Borders.lua, see
-- docs/atlas-data.md). Area names are the game's to give, so they're not here.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)

-- The zone borders' levels of detail (tools/gen_borders.py LEVELS): below each zoom (px per tile),
-- the level within about 1.5 px there; lines past the last. The first two: docs/v1-plan.md M1.4's bands.
Atlas.BORDER_FAR_ZOOM = 50 -- (far: the demo's too)
Atlas.BORDER_LEVELS = { { 12, "z12" }, { 30, "z30" }, { Atlas.BORDER_FAR_ZOOM, "far" }, { 100, "z100" }, { 200, "z200" } }

-- { lines, z12, z30, far, z100, z200, sub, subz200, outlines, labels } in tile units:
--   lines and its levels = { { areaA, areaB, fadeStart, fadeEnd, x1, y1, ... } }
--   sub, subz200 = { { areaA, areaB, x1, y1, ... } }: subzone borders, as lines and z200
--   outlines   = { [zone areaID] = { { x1, y1, ... }, ... } }
--   labels     = { { areaID, col, row, weight, kind } }
function Atlas.Borders(inst)
	return Data.Borders and Data.Borders[inst]
end

-- The zone borders to draw at a zoom (px per tile): the coarsest level still within a pixel or so.
function Atlas.BorderLines(inst, zoom)
	local b = Atlas.Borders(inst)
	if not b then return nil end
	for _, l in ipairs(Atlas.BORDER_LEVELS) do
		if zoom < l[1] then return b[l[2]] end
	end
	return b.lines
end

-- The subzone borders to draw at a zoom: { { areaA, areaB, x1, y1, ... } }; z200's level below 300
-- (a faint hairline: within 2.25 px there).
Atlas.SUBZONE_NEAR_ZOOM = 300
function Atlas.SubzoneLines(inst, zoom)
	local b = Atlas.Borders(inst)
	return b and (zoom < Atlas.SUBZONE_NEAR_ZOOM and b.subz200 or b.sub)
end

-- A zone's land as closed rings { x1, y1, ... } in tile units; even-odd (a ring inside another is a hole).
function Atlas.ZoneOutline(inst, zone)
	local b = Atlas.Borders(inst)
	return b and b.outlines[zone]
end

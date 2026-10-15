-- Zone borders, zone outlines and label anchors, traced offline from the
-- terrain's chunk areas and smoothed there (Data/Borders.lua, see
-- docs/atlas-data.md). Area names are the game's to give, so they're not here.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

-- far is within 0.03 tiles of lines (tools/gen_borders.py FAR): under 1.5 px below this zoom.
Atlas.BORDER_FAR_ZOOM = 50 -- px per tile

-- { lines, far, outlines, labels } in tile units:
--   lines, far = { { areaA, areaB, fadeStart, fadeEnd, x1, y1, ... } }
--   outlines   = { [zone areaID] = { { x1, y1, ... }, ... } }
--   labels     = { { areaID, col, row, weight, kind } }
function Atlas.Borders(inst)
	return MagicMap_Borders and MagicMap_Borders[inst]
end

-- The zone borders to draw at a zoom (px per tile): the coarser level when it's still within a pixel or so.
function Atlas.BorderLines(inst, zoom)
	local b = Atlas.Borders(inst)
	return b and (zoom < Atlas.BORDER_FAR_ZOOM and b.far or b.lines)
end

-- A zone's land as closed rings { x1, y1, ... } in tile units; even-odd (a ring inside another is a hole).
function Atlas.ZoneOutline(inst, zone)
	local b = Atlas.Borders(inst)
	return b and b.outlines[zone]
end

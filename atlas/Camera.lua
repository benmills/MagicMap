-- Camera maths. cam = { cx, cy, zoom }: the tile at the view's centre and
-- pixels per tile. Screen origin is the view's top-left.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Camera = {}
Atlas.Camera = Camera

local function Clamp(v, lo, hi)
	if lo and v < lo then return lo end
	if hi and v > hi then return hi end
	return v
end

-- Centre on a box and zoom to fit it, with margin (share of the view) to spare.
function Camera.Fit(c0, r0, c1, r1, w, h, margin, minZoom, maxZoom)
	local zoom = math.min(w / (c1 - c0), h / (r1 - r0)) * (margin or 0.92)
	return (c0 + c1) / 2, (r0 + r1) / 2, Clamp(zoom, minZoom, maxZoom)
end

function Camera.ScreenToTile(cam, w, h, x, y)
	return cam.cx + (x - w / 2) / cam.zoom, cam.cy + (y - h / 2) / cam.zoom
end

function Camera.TileToScreen(cam, w, h, col, row)
	return (col - cam.cx) * cam.zoom + w / 2, (row - cam.cy) * cam.zoom + h / 2
end

-- Zoom to zoom with the tile under (x, y) staying put.
function Camera.ZoomAt(cam, w, h, x, y, zoom)
	local col, row = Camera.ScreenToTile(cam, w, h, x, y)
	return { cx = col - (x - w / 2) / zoom, cy = row - (y - h / 2) / zoom, zoom = zoom }
end

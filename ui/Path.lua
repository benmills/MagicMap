-- The line to what you go to (Model.Target: your corpse, the quest you follow, your waypoint): narrow
-- dashes like a route on a printed map, a little uneven as if inked by hand, light on a faint dark edge
-- so they read on pale ground (Path.lua:1-6). It follows the way you'd walk (Model.Route: you first, the
-- target last) once that's found, else it's straight - "that way". It leaves you the way you're facing and
-- bends onto the way, under the names and pins (level 8). On a canvas of its own whose origin is a tile
-- near the view, so a pan carries it along (Path.lua:126-129); laid out again when you or the target move
-- half a pixel, you turn 3°, the zoom changes or the route is found again, only the dashes that meet the
-- view (and a margin) shown (a line's ends stay within a few thousand px: docs/v1-plan.md §2); and as a pan
-- takes the view past them, the dashes it brings in shown, the rest left as they stand.
-- Off the view, the target gets a gold arrow on its edge, where the line toward it leaves (Path.lua:24-79).
-- And your corpse becoming the target brings the view back to you (Core.lua:1095-1108).

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Camera, Window, Motion = UI.Camera, UI.Window, UI.Motion
local Maths = ns.Atlas.Camera

local LEVEL = 8 -- over the borders (7), under the names (9): the spike's path frame (Core.lua:149)
local CLEAR_YOU, CLEAR_TARGET = 14, 15 -- px left clear around your arrow and the target's pin (Path.lua:11)
local FADE = 40 -- px over which the line fades in and out at its ends (Path.lua:12)
local STROKE, WASH = 1.6, 3.4 -- px: the light dash and the dark edge under it (Path.lua:13)
local STROKE_RGBA = { 1, 0.93, 0.76, 0.7 } -- Path.lua:14
local WASH_RGBA = { 0.12, 0.08, 0.03, 0.3 } -- Path.lua:15
local DASH, GAP = 6, 4 -- px (longer, in proportion, when there'd be more than MAX_PIECES dashes: Path.lua:16)
local PERIOD = DASH + GAP
local MAX_PIECES = 160 -- Path.lua:17
local WOBBLE = 0.8 -- px the line strays either side of true, in long slow waves (Path.lua:18)
local UNEVEN = 0.25 -- share of the dashes' alpha that comes and goes along it (Path.lua:19)
local LEAD, LEAD_STEPS = 48, 8 -- px of line (at most half of it) that bends from where you face onto the way (Path.lua:20-21)
local FACING_STEP = math.rad(3) -- turning less than this doesn't redraw the line (Path.lua:22)
local EDGE_INSET = 16 -- px from the view's edge to the arrow's centre (Path.lua:27)
local EDGE_ART, EDGE_SIZE = "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW", 32 -- Path.lua:31-33
local CHECK = 0.2 -- s between looks at which target you have (Core.lua:1096 TARGET_CHECK)
local MARGIN = 32 -- px laid out past the view's edges (following you, the view moves less between layouts)
local ORIGIN_PX = 1024 -- the canvas's origin moves to the tile at the view's centre once further off than this

local Path = { draws = 0, pieces = 0 } -- draws: the line laid out again; pieces: its dashes then (≤ MAX_PIECES)
UI.Path = Path

local frame = CreateFrame("Frame", nil, Window.view)
frame:SetAllPoints()
frame:SetFrameLevel(Window.view:GetFrameLevel() + LEVEL)
-- Tile (col, row) at ((col - ox) * zoom, (row - oy) * zoom) down from its top left.
local canvas = CreateFrame("Frame", nil, frame)
canvas:SetSize(1, 1)
Path.canvas = canvas

local edge = UI.You.overlay:CreateTexture(nil, "OVERLAY", nil, 3)
edge:SetTexture(EDGE_ART)
edge:SetSize(EDGE_SIZE, EDGE_SIZE)
edge:SetSnapToPixelGrid(false)
edge:SetTexelSnappingBias(0)
edge:Hide()
edge.on = false
Path.edge = edge

---------------------------------------------------------------------------
-- The line (Path.lua:81-275)
---------------------------------------------------------------------------

local strokes, washes = {}, {}
local used = 0

-- A piece's line, made the first time it shows (pieces counted from the target: at most MAX_PIECES each).
local function Get(list, i, sublevel, thick)
	local l = list[i]
	if not l then
		l = canvas:CreateLine(nil, "ARTWORK", nil, sublevel)
		l:SetSnapToPixelGrid(false)
		l:SetTexelSnappingBias(0)
		l:SetThickness(thick)
		list[i] = l
	end
	return l
end

-- Only what changed: the far end of the line (its waves are counted from the target) stays put as you go.
local function Segment(l, ax, ay, bx, by, c, a)
	if l.a ~= a then
		l.a = a
		l:SetColorTexture(c[1], c[2], c[3], a)
	end
	if l.ax ~= ax or l.ay ~= ay or l.bx ~= bx or l.by ~= by then
		l.ax, l.ay, l.bx, l.by = ax, ay, bx, by
		l:SetStartPoint("TOPLEFT", canvas, ax, -ay)
		l:SetEndPoint("TOPLEFT", canvas, bx, -by)
	end
	if not l.on then
		l.on = true
		l:Show()
	end
end

local function Off(l)
	if l and l.on then
		l.on = false
		l:Hide()
	end
end

-- What the line was last drawn for: you and the target on the canvas, your facing, the zoom (and the
-- route: Same). Nothing moved, nothing to draw.
local drawn = {}
local function Unchanged(x1, y1, x2, y2, facing, z)
	if drawn[1] == x1 and drawn[2] == y1 and drawn[3] == x2 and drawn[4] == y2 and drawn[5] == facing
		and drawn[6] == z then return true end
	drawn[1], drawn[2], drawn[3], drawn[4], drawn[5], drawn[6] = x1, y1, x2, y2, facing, z
	return false
end

-- The route's points between you and the target as last drawn: one found again draws again, however
-- Model hands it (a new table, or the same one changed).
local had = { n = 0 }
local function Same(route)
	local m = route and #route or 0
	if had.n ~= m then return false end
	for i = 2, m - 1 do
		local p = route[i]
		if had[i * 2 - 1] ~= p.col or had[i * 2] ~= p.row then return false end
	end
	return true
end
local function Had(route)
	local m = route and #route or 0
	had.n = m
	for i = 2, m - 1 do had[i * 2 - 1], had[i * 2] = route[i].col, route[i].row end
end

local function HalfPixel(v) return math.floor(v * 2 + 0.5) / 2 end

-- The line's corners on the canvas, and how far along it each one is ([1..m] this draw).
local xs, ys, along = {}, {}, {}
local you, dest = {}, {} -- the line's ends, tile space
local way = {} -- its points: you, the route's between, the target
local shownWay -- way as last drawn, when a route was found: the edge arrow's legs

-- The line leaving you the way you face (radians, 0 north, turning left): a curve from you along it onto
-- the way, `lead` tiles along, joining the way's own direction there; then the rest of the way.
local bent, bentPts = {}, {}
local function BentPoint(i)
	local p = bentPts[i]
	if not p then
		p = {}
		bentPts[i] = p
	end
	return p
end
local function LeadIn(pts, facing, lead)
	local m, total = #pts, 0
	for i = 2, m do total = total + math.sqrt((pts[i].col - pts[i - 1].col) ^ 2 + (pts[i].row - pts[i - 1].row) ^ 2) end
	lead = math.min(lead, total / 2)
	if lead <= 0 then return pts end
	-- Where the curve joins the way: `lead` along it, on leg j.
	local j, left = 1, lead
	local jx, jy, ux, uy
	while j < m do
		local a, b = pts[j], pts[j + 1]
		local seg = math.sqrt((b.col - a.col) ^ 2 + (b.row - a.row) ^ 2)
		if seg > 0 then
			ux, uy = (b.col - a.col) / seg, (b.row - a.row) / seg -- /: never 0 (seg > 0)
			if left <= seg or j == m - 1 then
				left = math.min(left, seg)
				jx, jy = a.col + ux * left, a.row + uy * left
				break
			end
		end
		left = left - seg
		j = j + 1
	end
	if not jx then return pts end
	local x0, y0 = pts[1].col, pts[1].row
	local k = math.sqrt((jx - x0) ^ 2 + (jy - y0) ^ 2) / 2
	-- A cubic Bezier: out along your facing, in along the way.
	local ax, ay = x0 - math.sin(facing) * k, y0 - math.cos(facing) * k
	local bx, by = jx - ux * k, jy - uy * k
	wipe(bent)
	for i = 0, LEAD_STEPS do
		local t = i / LEAD_STEPS
		local u = 1 - t
		local p = BentPoint(i + 1)
		p.col = u * u * u * x0 + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * jx
		p.row = u * u * u * y0 + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * jy
		bent[#bent + 1] = p
	end
	for i = j + 1, m do bent[#bent + 1] = pts[i] end
	return bent
end

-- Point at distance s along the line, on leg i (s between along[i] and along[i + 1]), nudged sideways by
-- the wobble.
local function At(i, s, len)
	local seg = along[i + 1] - along[i]
	local k = seg > 0 and (s - along[i]) / seg or 0 -- /: never 0 (seg > 0)
	local dx, dy = xs[i + 1] - xs[i], ys[i + 1] - ys[i]
	local x, y = xs[i] + dx * k, ys[i] + dy * k
	if seg > 0 then
		-- Counted from the target, so the waves stay put as you walk.
		local u = len - s
		local o = WOBBLE * (0.6 * math.sin(u * 0.09 + 1.3) + 0.4 * math.sin(u * 0.031 + 4.1))
		x, y = x - dy / seg * o, y + dx / seg * o -- /: never 0 (seg > 0)
	end
	return x, y
end

-- The canvas's origin, kept while the view stays near it (a line drawn on it stays put as the map pans).
local ox, oy
local rect = {} -- the canvas px laid out over (the view's and a margin): x0, y0, x1, y1

local function Covered(cam, w, h)
	local z = cam.zoom
	local vx, vy = (cam.cx - ox) * z, (cam.cy - oy) * z
	return vx - w / 2 >= rect[1] and vx + w / 2 <= rect[3] and vy - h / 2 >= rect[2] and vy + h / 2 <= rect[4]
end

-- The line to t from you, laid out again unless nothing it shows changed: its pieces.
local function Line(t, me, cam, w, h)
	local z = cam.zoom
	if not ox or math.abs(ox - cam.cx) * z > ORIGIN_PX or math.abs(oy - cam.cy) * z > ORIGIN_PX then
		ox, oy = math.floor(cam.cx + 0.5), math.floor(cam.cy + 0.5)
	end
	local cx, cy = (ox - cam.cx) * z, (cam.cy - oy) * z
	if canvas.x ~= cx or canvas.y ~= cy then
		canvas.x, canvas.y = cx, cy
		canvas:SetPoint("TOPLEFT", frame, "CENTER", cx, cy)
	end
	local pos = t.pos
	local x1, y1 = HalfPixel((me.col - ox) * z), HalfPixel((me.row - oy) * z)
	local x2, y2 = HalfPixel((pos.col - ox) * z), HalfPixel((pos.row - oy) * z)
	local route = Model.Route()
	if route and route.straight then route = nil end
	local facing = me.facing
	facing = facing and math.floor(facing / FACING_STEP + 0.5) * FACING_STEP
	if Unchanged(x1, y1, x2, y2, facing, z) and Same(route) and Covered(cam, w, h) then return nil end
	Had(route)
	Path.draws = Path.draws + 1
	wipe(way)
	you.col, you.row, dest.col, dest.row = me.col, me.row, pos.col, pos.row
	way[1] = you
	for i = 2, route and #route - 1 or 0 do way[#way + 1] = route[i] end
	way[#way + 1] = dest
	local pts = way
	if facing then pts = LeadIn(pts, facing, LEAD / z) end -- /: never 0 (zoom >= MIN_ZOOM)
	shownWay = route and pts
	local m = #pts
	for i = 1, m do
		xs[i], ys[i] = (pts[i].col - ox) * z, (pts[i].row - oy) * z
		along[i] = i == 1 and 0 or along[i - 1] + math.sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2)
	end
	-- Over the view and a margin: a dash that doesn't meet it is left off.
	local vx, vy = (cam.cx - ox) * z, (cam.cy - oy) * z
	local mw, mh = w / 2 + MARGIN, h / 2 + MARGIN
	rect[1], rect[2], rect[3], rect[4] = vx - mw, vy - mh, vx + mw, vy + mh
	local n, len = 0, along[m]
	local s0, s1 = CLEAR_YOU, len - CLEAR_TARGET
	if s1 > s0 then
		-- Dashes laid back from the target, so they stay put as you walk.
		local step = math.max(PERIOD, (s1 - s0) / MAX_PIECES)
		local dash = step * DASH / PERIOD
		local i = m - 1
		local b = s1 + step
		while b - step > s0 and n < MAX_PIECES do
			b = b - step
			local a = math.max(s0, b - dash)
			while i > 1 and along[i] > a do i = i - 1 end
			local j = i
			while j < m - 1 and along[j + 1] < b do j = j + 1 end
			n = n + 1
			local ax, ay = At(i, a, len)
			local bx, by = At(j, b, len)
			ax, ay, bx, by = HalfPixel(ax), HalfPixel(ay), HalfPixel(bx), HalfPixel(by)
			if math.max(ax, bx) >= rect[1] and math.min(ax, bx) <= rect[3] and math.max(ay, by) >= rect[2]
				and math.min(ay, by) <= rect[4] then
				local mid = (a + b) / 2
				local f = math.min(1, (mid - s0) / FADE, (s1 - mid) / FADE)
				local even = 1 - UNEVEN * (0.5 + 0.5 * math.sin((len - mid) * 0.045 + 2))
				Segment(Get(washes, n, 0, WASH), ax, ay, bx, by, WASH_RGBA, HalfPixel(WASH_RGBA[4] * f * 100) / 100)
				Segment(Get(strokes, n, 1, STROKE), ax, ay, bx, by, STROKE_RGBA, HalfPixel(STROKE_RGBA[4] * f * even * 100) / 100)
			else
				Off(washes[n])
				Off(strokes[n])
			end
		end
	end
	return n
end

---------------------------------------------------------------------------
-- The edge arrow (Path.lua:24-79)
---------------------------------------------------------------------------

local function In(x, y, lo, hiX, hiY) return x >= lo and x <= hiX and y >= lo and y <= hiY end

-- Where the line toward t leaves the view (inset), along the route's leg that does: there, pointing on.
local function Arrow(t, me, cam, w, h)
	local lo, hiX, hiY = EDGE_INSET, w - EDGE_INSET, h - EDGE_INSET
	local x1, y1 = Maths.TileToScreen(cam, w, h, me.col, me.row)
	local x2, y2 = Maths.TileToScreen(cam, w, h, t.pos.col, t.pos.row)
	local pts = shownWay
	if pts and In(x1, y1, lo, hiX, hiY) then
		for i = 2, #pts do
			x2, y2 = Maths.TileToScreen(cam, w, h, pts[i].col, pts[i].row)
			if not In(x2, y2, lo, hiX, hiY) then break end
			x1, y1 = x2, y2
		end
	end
	if not (In(x1, y1, lo, hiX, hiY) and not In(x2, y2, lo, hiX, hiY)) then return false end
	-- How far along it the line leaves the inset rect.
	local dx, dy = x2 - x1, y2 - y1
	local k = 1
	if dx ~= 0 then k = math.min(k, ((dx > 0 and hiX or lo) - x1) / dx) end -- /: never 0 (dx ~= 0)
	if dy ~= 0 then k = math.min(k, ((dy > 0 and hiY or lo) - y1) / dy) end -- /: never 0 (dy ~= 0)
	local ax, ay = math.floor(x1 + dx * k + 0.5), math.floor(y1 + dy * k + 0.5)
	local rot = math.atan2(-dx, -dy) -- the art points up
	if ax ~= edge.x or ay ~= edge.y or rot ~= edge.rot then
		edge.x, edge.y, edge.rot = ax, ay, rot
		edge:ClearAllPoints()
		edge:SetPoint("CENTER", UI.You.overlay, "TOPLEFT", ax, -ay)
		edge:SetRotation(rot)
	end
	return true
end

-- Each frame while shown, after the map's draw: the line and the arrow, for a target on the map shown
-- while you're on it with a position, not yet arrived (inside its area: they step aside).
Runtime.Step("ui", "map: path", function()
	local t, me, inst = Model.Target(), Model.you, Camera.inst
	local n, arrow = 0, false
	if t and not t.inside and me.col and not me.stale and me.inst == inst and t.pos.inst == inst then
		local cam, w, h = Camera.cam, Window.Size()
		n = Line(t, me, cam, w, h)
		arrow = Arrow(t, me, cam, w, h)
	else
		drawn[1], shownWay = nil, nil
	end
	if arrow ~= edge.on then
		edge.on = arrow
		edge:SetShown(arrow)
	end
	if not n then return end -- (unchanged)
	for i = n + 1, used do
		Off(strokes[i])
		Off(washes[i])
	end
	used, Path.pieces = n, n
end, { shownOnly = Window.frame })

---------------------------------------------------------------------------
-- Your corpse as the target brings the view back to you (Core.lua:1095-1108)
---------------------------------------------------------------------------

-- Which target you have, looked at every CHECK s: one changing to your corpse (you've released) follows
-- you again, gliding back; what you had at the first look keeps your saved choice (the first once
-- Model knows it: nil before its first Focus).
local looked, key, since = false, nil, CHECK
Runtime.Step("ui", "map: target", function(elapsed)
	since = since + elapsed
	if since < CHECK then return end
	since = 0
	local t = Model.Target()
	if t == nil then return end
	local k = t and t.key or nil
	if looked and k == key then return end
	local first = not looked
	looked, key = true, k
	if not first and t and t.kind == "corpse" and not Camera.follow then Motion.SetFollow(true, true) end
end, { shownOnly = Window.frame })

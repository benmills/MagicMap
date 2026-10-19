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
-- And your corpse becoming the target brings the view back to you (Core.lua:1095-1108), once a ghost.

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Camera, Window, Motion = UI.Camera, UI.Window, UI.Motion
local Maths = ns.Atlas.Camera
local floor, sin = math.floor, math.sin

local LEVEL = 8 -- over the borders (7), under the names (9): the spike's path frame (Core.lua:149)
local CLEAR_YOU, CLEAR_TARGET = 14, 15 -- px left clear around your arrow and the target's pin (Path.lua:11)
local FADE = 40 -- px over which the line fades in and out at its ends (Path.lua:12)
local STROKE, WASH = 1.6, 3.4 -- px: the light dash and the dark edge under it (Path.lua:13)
local STROKE_RGBA = { 1, 0.93, 0.76, 0.7 } -- Path.lua:14
local WASH_RGBA = { 0.12, 0.08, 0.03, 0.3 } -- Path.lua:15
local STROKE_A, WASH_A = STROKE_RGBA[4] * 200, WASH_RGBA[4] * 200 -- (their alphas in half hundredths)
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

-- Each piece's two lines (pieces counted from the target: MAX_PIECES), made once at load, in login's grace,
-- hidden, in their colour: a layout only places and shows them, and sets an alpha where it differs (made as
-- they first showed, a long line's first layout made up to 2 x MAX_PIECES in one call: 2-7 ms priced; the
-- wash's alpha is its colour's but by the ends).
local strokes, washes = {}, {}
local used = 0
local function Make(sublevel, thick, c)
	local l = canvas:CreateLine(nil, "ARTWORK", nil, sublevel)
	l:SetSnapToPixelGrid(false)
	l:SetTexelSnappingBias(0)
	l:SetThickness(thick)
	l:SetColorTexture(c[1], c[2], c[3], c[4])
	l:Hide()
	l.on, l.a = false, c[4]
	return l
end
for i = 1, MAX_PIECES do washes[i], strokes[i] = Make(0, WASH, WASH_RGBA), Make(1, STROKE, STROKE_RGBA) end

-- Only what changed: the far end of the line (its waves are counted from the target) stays put as you go;
-- of a dash that moves, only the end that does.
local function Segment(l, ax, ay, bx, by, c, a)
	if l.a ~= a then
		l.a = a
		l:SetColorTexture(c[1], c[2], c[3], a)
	end
	if l.ax ~= ax or l.ay ~= ay then
		l.ax, l.ay = ax, ay
		l:SetStartPoint("TOPLEFT", canvas, ax, -ay)
	end
	if l.bx ~= bx or l.by ~= by then
		l.bx, l.by = bx, by
		l:SetEndPoint("TOPLEFT", canvas, bx, -by)
	end
	if not l.on then
		l.on = true
		l:Show()
	end
end

local function Off(l)
	if l.on then
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
local had = { n = 0 } -- (and route: the table; Model hands the same one while its way is the same)
local function Same(route)
	if route and route == had.route then return true end
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
	had.n, had.route = m, route
	for i = 2, m - 1 do had[i * 2 - 1], had[i * 2] = route[i].col, route[i].row end
end

local function HalfPixel(v) return math.floor(v * 2 + 0.5) / 2 end

-- The line's corners on the canvas, how far along it each one is, and how far from the target (summed from
-- it: [1..m] this draw); each leg's length and way (a unit vector: ux, uy; 0 for none: [1..m - 1]); and how
-- many of legs 1..k have a box (wobble and all) that meets the rect laid out over (meet[k]: [0..m - 1]).
local xs, ys, along, back, segs, ux, uy, meet = {}, {}, {}, {}, {}, {}, {}, { [0] = 0 }
-- The last layout: its corners from the target end (pxs, pys, pback: xs, ys, back as they were), its zoom,
-- origin, step and length; and each dash's ends and alphas as worked out then (dash n's: kept[n] the
-- layout, Path.draws, it was worked out for or still stood in; nil: not worked out). A dash wholly on legs
-- by the target that didn't move, past the fade by you, stands as it was: walking, only those near you move.
local pxs, pys, pback = {}, {}, {}
local last = { m = 0 }
local dax, day, dbx, dby, dwa, dsa, kept = {}, {}, {}, {}, {}, {}, {}
-- The canvas's origin, kept while the view stays near it (a line drawn on it stays put as the map pans).
local ox, oy
local rect = {} -- the canvas px laid out over (the view's and a margin): x0, y0, x1, y1
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

local function Covered(cam, w, h)
	local z = cam.zoom
	local vx, vy = (cam.cx - ox) * z, (cam.cy - oy) * z
	return vx - w / 2 >= rect[1] and vx + w / 2 <= rect[3] and vy - h / 2 >= rect[2] and vy + h / 2 <= rect[4]
end

-- The dashes of the line as laid out (lay: m, len, s0, s1, step, id (Path.draws), still; parity, half),
-- laid back from the target so they stay put as you walk; each worked out only where its legs meet the
-- rect, and left as it stands on legs that didn't move (still: how far from the target). half: 0, all of
-- them; 1 or 2, the odd or even ones only (the rest as they stand). How many there are.
local lay = {}
local function Dashes(half)
	local L = lay
	local m, len, s0, s1, step, id, still = L.m, L.len, L.s0, L.s1, L.step, L.id, L.still
	local dash = step * DASH / PERIOD
	local q = step > PERIOD and 1 or 2 -- px a dash's ends are rounded to: halves, whole past MAX_PIECES (the M3 review)
	local r1, r2, r3, r4 = rect[1], rect[2], rect[3], rect[4]
	local n, i = 0, m - 1
	local b = s1 + step
	while b - step > s0 and n < MAX_PIECES do
		b = b - step
		local a = b - dash
		if a < s0 then a = s0 end
		while i > 1 and along[i] > a do i = i - 1 end
		local j = i
		while j < m - 1 and along[j + 1] < b do j = j + 1 end
		n = n + 1
		if half == 0 or n % 2 == half - 1 then
			local near, ax, ay, bx, by = false, nil, nil, nil, nil
			if len - a <= still and kept[n] == id - 1 then -- as it was: shown again if it's come into the rect
				kept[n], ax, ay, bx, by = id, dax[n], day[n], dbx[n], dby[n]
				near = (ax >= r1 or bx >= r1) and (ax <= r3 or bx <= r3) and (ay >= r2 or by >= r2) and (ay <= r4 or by <= r4)
				if near and not (washes[n].on and strokes[n].on) then
					Segment(washes[n], ax, ay, bx, by, WASH_RGBA, dwa[n])
					Segment(strokes[n], ax, ay, bx, by, STROKE_RGBA, dsa[n])
				end
				a = nil
			else
				kept[n], near = nil, meet[j] > meet[i - 1]
			end
			if a and near then
				-- Its ends on legs i and j, nudged sideways by the wobble (counted from the target, so the waves
				-- stay put as you walk).
				local u, d, vx, vy = len - a, a - along[i], ux[i], uy[i]
				local o = WOBBLE * (0.6 * sin(u * 0.09 + 1.3) + 0.4 * sin(u * 0.031 + 4.1))
				ax, ay = floor((xs[i] + vx * d - vy * o) * q + 0.5) / q, floor((ys[i] + vy * d + vx * o) * q + 0.5) / q -- /: never 0 (q 1 or 2)
				u, d, vx, vy = len - b, b - along[j], ux[j], uy[j]
				o = WOBBLE * (0.6 * sin(u * 0.09 + 1.3) + 0.4 * sin(u * 0.031 + 4.1))
				bx, by = floor((xs[j] + vx * d - vy * o) * q + 0.5) / q, floor((ys[j] + vy * d + vx * o) * q + 0.5) / q -- /: never 0 (q 1 or 2)
				local mid = (a + b) / 2
				local f = (mid - s0) / FADE
				if f > 1 then f = 1 end
				local g = (s1 - mid) / FADE
				if g < f then f = g end
				local even = 1 - UNEVEN * (0.5 + 0.5 * sin((len - mid) * 0.045 + 2))
				kept[n], dax[n], day[n], dbx[n], dby[n] = id, ax, ay, bx, by
				dwa[n], dsa[n] = floor(WASH_A * f + 0.5) / 200, floor(STROKE_A * f * even + 0.5) / 200
				near = (ax >= r1 or bx >= r1) and (ax <= r3 or bx <= r3) and (ay >= r2 or by >= r2) and (ay <= r4 or by <= r4)
				if near then
					Segment(washes[n], ax, ay, bx, by, WASH_RGBA, dwa[n])
					Segment(strokes[n], ax, ay, bx, by, STROKE_RGBA, dsa[n])
				end
			end
			if not near then
				Off(washes[n])
				Off(strokes[n])
			end
		end
	end
	return n
end

-- The line to t from you, laid out again unless nothing it shows changed (but half its dashes left from the
-- last frame: Dashes): its pieces, or nil.
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
	if Unchanged(x1, y1, x2, y2, facing, z) and Same(route) and Covered(cam, w, h) then
		local half = lay.half
		if not half then return nil end
		lay.half = nil
		return Dashes(half)
	end
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
	-- Over the view and a margin: a dash that doesn't meet it is left off.
	local vx, vy = (cam.cx - ox) * z, (cam.cy - oy) * z
	local mw, mh = w / 2 + MARGIN, h / 2 + MARGIN
	local r1, r2, r3, r4 = vx - mw, vy - mh, vx + mw, vy + mh
	rect[1], rect[2], rect[3], rect[4] = r1, r2, r3, r4
	local pad = WOBBLE + 1
	xs, pxs, ys, pys, back, pback = pxs, xs, pys, ys, pback, back -- (the last layout's kept to compare)
	for i = 1, m do
		local x, y = (pts[i].col - ox) * z, (pts[i].row - oy) * z
		xs[i], ys[i] = x, y
		if i == 1 then
			along[i] = 0
		else
			local px, py = xs[i - 1], ys[i - 1]
			local seg = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
			along[i] = along[i - 1] + seg
			local k = i - 1
			segs[k] = seg
			if seg > 0 then ux[k], uy[k] = (x - px) / seg, (y - py) / seg else ux[k], uy[k] = 0, 0 end -- /: never 0 (seg > 0)
			local meets = (x + pad >= r1 or px + pad >= r1) and (x - pad <= r3 or px - pad <= r3)
				and (y + pad >= r2 or py + pad >= r2) and (y - pad <= r4 or py - pad <= r4)
			meet[k] = meet[k - 1] + (meets and 1 or 0)
		end
	end
	back[m] = 0
	for i = m - 1, 1, -1 do back[i] = back[i + 1] + segs[i] end
	-- How far from the target the line is as last laid out (-1: none of it).
	local fixed, lm, k = -1, last.m, 0
	if last.z == z and last.ox == ox and last.oy == oy then
		while k < m and k < lm and xs[m - k] == pxs[lm - k] and ys[m - k] == pys[lm - k] and back[m - k] == pback[lm - k] do
			k = k + 1
		end
		if k >= 2 then fixed = back[m - k + 1] end
	end
	local len = along[m]
	local s0, s1 = CLEAR_YOU, len - CLEAR_TARGET
	local n, step = 0, math.max(PERIOD, (s1 - s0) / MAX_PIECES)
	if s1 > s0 then
		local L = lay
		L.m, L.len, L.s0, L.s1, L.step, L.id, L.still = m, len, s0, s1, step, Path.draws, -1
		if fixed >= 0 and last.step == step then L.still = math.min(fixed, math.min(len, last.len) - s0 - FADE) end
		-- At the zoom and origin of the last layout (walking, turning, a route found), or a line new: half its
		-- dashes this frame, the rest the next, odd and even by turns (the M3 review: one frame behind, unseen;
		-- past MAX_PIECES every dash moves as its length does). While the zoom moves, all at once.
		if last.z == z and last.ox == ox and last.oy == oy or Path.pieces == 0 then
			L.parity = 3 - (L.parity or 1)
			L.half = 3 - L.parity
			n = Dashes(L.parity)
		else
			L.half = nil
			n = Dashes(0)
		end
	end
	last.m, last.z, last.ox, last.oy, last.len, last.step = m, z, ox, oy, len, step
	return n
end

---------------------------------------------------------------------------
-- The edge arrow (Path.lua:24-79)
---------------------------------------------------------------------------

local function In(x, y, lo, hiX, hiY) return x >= lo and x <= hiX and y >= lo and y <= hiY end

-- Where the line toward t leaves the view (inset), along the route's leg that does: there, pointing on.
-- Worked out again only once the view, you, the target or the line moved.
local placed = {} -- cam's cx, cy, zoom, w, h, you, the target's pos, Path.draws; on: the answer
local function Arrow(t, me, cam, w, h)
	local p = placed
	if p[1] == cam.cx and p[2] == cam.cy and p[3] == cam.zoom and p[4] == w and p[5] == h and p[6] == me.col
		and p[7] == me.row and p[8] == t.pos and p[9] == Path.draws then return p.on end
	p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9] = cam.cx, cam.cy, cam.zoom, w, h, me.col, me.row, t.pos, Path.draws
	p.on = false
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
	p.on = true
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
		drawn[1], shownWay, lay.half = nil, nil, nil
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

-- Hidden: every line off, laid out anew when it shows (left shown under the window, they'd all show with
-- it in that one call: R-P7), as the map's canvases are emptied (ui/Engine.lua).
Window.frame:HookScript("OnHide", Runtime.Wrap("map: path hidden", function()
	for i = 1, used do
		Off(strokes[i])
		Off(washes[i])
	end
	used, Path.pieces, drawn[1], shownWay, last.z, lay.half = 0, 0, nil, nil, nil, nil
	edge.on = false
	edge:Hide()
end))

---------------------------------------------------------------------------
-- Your corpse as the target brings the view back to you (Core.lua:1095-1108)
---------------------------------------------------------------------------

-- Looked at every CHECK s: a ghost's corpse once the target (found on the map shown: the spike's
-- corpseFound, Layers.lua:504-521) stays found for the rest of that ghost, whatever map is shown after (its
-- TargetKey, Layers.lua:1182-1184); found after the first look, it follows you again, gliding back. Found at
-- the first look (nil before Model's first Focus) keeps your saved choice.
local looked, found, since = false, false, CHECK
Runtime.Step("ui", "map: target", function(elapsed)
	since = since + elapsed
	if since < CHECK then return end
	since = 0
	local t = Model.Target()
	if t == nil then return end
	if not Model.you.ghost then
		found = false
	elseif not found and t and t.kind == "corpse" then
		found = true
		if looked and not Camera.follow then Motion.SetFollow(true, true) end
	end
	looked = true
end, { shownOnly = Window.frame })

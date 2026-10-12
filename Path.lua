-- The line to what you track (the quest you follow, your waypoint, your
-- corpse): wide, soft and a little uneven, like a pencilled route, a light
-- stroke over a darker wash so it reads on pale ground without shouting.
-- It follows the way you'd walk (Route.lua) once that's found, else it's
-- straight - "that way". It leaves you the way you're facing and bends onto
-- the way, and it sits under the labels and pins.

local ADDON, ns = ...
local state = ns.state

local CLEAR_YOU, CLEAR_TARGET = 14, 15 -- px left clear around your arrow and the target's pin
local FADE = 40            -- px over which the line fades in and out at its ends
local STROKE, WASH = 3, 7  -- px: the light stroke and the dark wash under it
local STROKE_RGBA = { 1, 0.92, 0.72, 0.4 }
local WASH_RGBA = { 0.14, 0.09, 0.04, 0.22 }
local PIECE = 10           -- px per piece of the line (longer when there'd be more than MAX_PIECES)
local MAX_PIECES = 160
local WOBBLE = 1.4         -- px the line strays either side of true, in long slow waves
local UNEVEN = 0.3         -- share of the stroke's alpha that comes and goes along it
local LEAD = 48            -- px of line (at most half of it) that bends from where you face onto the way
local LEAD_STEPS = 8
local FACING_STEP = math.rad(3) -- turning less than this doesn't redraw the line

-- Off the map, your target gets a gold arrow on the map's edge, where the
-- line toward it leaves the map (Blizzard's own rim arrows are pushed away:
-- MinimapTakeover).
local EDGE_INSET = 16 -- px from the map's edge to the arrow's centre
-- The route the line last followed (tile positions, you first), or nil:
-- straight. Set by the line's hook below, so the arrow is a frame behind.
local routePts
local edgeArrow = ns.overlay:CreateTexture(nil, "OVERLAY", nil, 3)
edgeArrow:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW")
edgeArrow:SetSize(32, 32)
edgeArrow:Hide()

local function In(x, y, lo, hiX, hiY) return x >= lo and x <= hiX and y >= lo and y <= hiY end

ns.frame:HookScript("OnUpdate", ns.Timed("path arrow", function()
	local t = ns.FrameTarget()
	if t and not t.inside and state.playerCol and state.playerMap == state.map then
		local w, h = ns.ViewSize()
		local lo, hiX, hiY = EDGE_INSET, w - EDGE_INSET, h - EDGE_INSET
		local x1, y1 = ns.TileToScreen(state.playerCol, state.playerRow)
		local x2, y2 = ns.TileToScreen(t.col, t.row)
		-- Along the route, the leg that leaves the inset rect.
		local pts = routePts
		if pts and In(x1, y1, lo, hiX, hiY) then
			for i = 2, #pts do
				x2, y2 = ns.TileToScreen(pts[i][1], pts[i][2])
				if not In(x2, y2, lo, hiX, hiY) then break end
				x1, y1 = x2, y2
			end
		end
		if In(x1, y1, lo, hiX, hiY) and not In(x2, y2, lo, hiX, hiY) then
			-- How far along it the line leaves the inset rect.
			local dx, dy = x2 - x1, y2 - y1
			local k = 1
			if dx ~= 0 then k = math.min(k, ((dx > 0 and hiX or lo) - x1) / dx) end
			if dy ~= 0 then k = math.min(k, ((dy > 0 and hiY or lo) - y1) / dy) end
			local ax, ay = math.floor(x1 + dx * k + 0.5), math.floor(y1 + dy * k + 0.5)
			local rot = math.atan2(-dx, -dy) -- the art points up
			if ax ~= edgeArrow.x or ay ~= edgeArrow.y or rot ~= edgeArrow.rot then
				edgeArrow.x, edgeArrow.y, edgeArrow.rot = ax, ay, rot
				edgeArrow:ClearAllPoints()
				edgeArrow:SetPoint("CENTER", ns.overlay, "TOPLEFT", ax, -ay)
				edgeArrow:SetRotation(rot)
			end
			if not edgeArrow.on then
				edgeArrow.on = true
				edgeArrow:Show()
			end
			return
		end
	end
	if edgeArrow.on then
		edgeArrow.on = false
		edgeArrow:Hide()
	end
end))

local layer = ns.layerFrames.path

local strokes, washes = {}, {}
local used = 0

local function Get(list, i, sublevel, thick)
	local l = list[i]
	if not l then
		l = layer:CreateLine(nil, "ARTWORK", nil, sublevel)
		l:SetSnapToPixelGrid(false)
		l:SetTexelSnappingBias(0)
		list[i] = l
	end
	if l.thick ~= thick then
		l.thick = thick
		l:SetThickness(thick)
	end
	return l
end

-- Only what changed: the far end of the line (its waves are counted from
-- the target) stays put as you go.
local function Segment(l, ax, ay, bx, by, c, a)
	if l.a ~= a then
		l.a = a
		l:SetColorTexture(c[1], c[2], c[3], a)
	end
	if l.ax ~= ax or l.ay ~= ay or l.bx ~= bx or l.by ~= by then
		l.ax, l.ay, l.bx, l.by = ax, ay, bx, by
		l:SetStartPoint("TOPLEFT", ns.tileCanvas, ax, -ay)
		l:SetEndPoint("TOPLEFT", ns.tileCanvas, bx, -by)
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

-- What the line was last drawn for; nothing moved, nothing to draw. It's
-- drawn on the tiles' canvas, so panning and following carry it along with
-- the map for free; it's redrawn when you or the target move half a pixel,
-- you turn, the zoom changes, or the route is found again.
local drawn = {}
local drawnRoute -- routePts as last drawn
local function Unchanged(x1, y1, x2, y2, route, facing)
	if drawn[1] == x1 and drawn[2] == y1 and drawn[3] == x2 and drawn[4] == y2
		and drawn[5] == route and drawn[6] == facing then return true end
	drawn[1], drawn[2], drawn[3], drawn[4], drawn[5], drawn[6] = x1, y1, x2, y2, route, facing
	return false
end

local function HalfPixel(v) return math.floor(v * 2 + 0.5) / 2 end

-- The line's corners on the canvas, and how far along it each one is
-- ([1..m] this frame; past that, left over).
local xs, ys, along = {}, {}, {}
local straight = { {}, {} }

-- The line leaving you the way you face (radians, 0 north, turning left):
-- a curve from you along it onto the way, `lead` tiles along, joining the
-- way's own direction there; then the rest of the way. Tables reused.
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
	for i = 2, m do total = total + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
	lead = math.min(lead, total / 2)
	if lead <= 0 then return pts end
	-- Where the curve joins the way: `lead` along it, on leg j.
	local j, left = 1, lead
	local jx, jy, ux, uy
	while j < m do
		local a, b = pts[j], pts[j + 1]
		local seg = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		if seg > 0 then
			ux, uy = (b[1] - a[1]) / seg, (b[2] - a[2]) / seg
			if left <= seg or j == m - 1 then
				left = math.min(left, seg)
				jx, jy = a[1] + ux * left, a[2] + uy * left
				break
			end
		end
		left = left - seg
		j = j + 1
	end
	if not jx then return pts end
	local x0, y0 = pts[1][1], pts[1][2]
	local k = math.sqrt((jx - x0) ^ 2 + (jy - y0) ^ 2) / 2
	-- A cubic Bezier: out along your facing, in along the way.
	local ax, ay = x0 - math.sin(facing) * k, y0 - math.cos(facing) * k
	local bx, by = jx - ux * k, jy - uy * k
	wipe(bent)
	for i = 0, LEAD_STEPS do
		local t = i / LEAD_STEPS
		local u = 1 - t
		local p = BentPoint(i + 1)
		p[1] = u * u * u * x0 + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * jx
		p[2] = u * u * u * y0 + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * jy
		bent[#bent + 1] = p
	end
	for i = j + 1, m do bent[#bent + 1] = pts[i] end
	return bent
end

-- Point at distance s along the line, on leg i (s between along[i] and
-- along[i + 1]), nudged sideways by the wobble.
local function At(i, s, len)
	local seg = along[i + 1] - along[i]
	local k = seg > 0 and (s - along[i]) / seg or 0
	local dx, dy = xs[i + 1] - xs[i], ys[i + 1] - ys[i]
	local x, y = xs[i] + dx * k, ys[i] + dy * k
	if seg > 0 then
		-- Counted from the target, so the waves stay put as you walk.
		local u = len - s
		local o = WOBBLE * (0.6 * math.sin(u * 0.09 + 1.3) + 0.4 * math.sin(u * 0.031 + 4.1))
		x, y = x - dy / seg * o, y + dx / seg * o
	end
	return x, y
end

ns.frame:HookScript("OnUpdate", ns.Timed("path line", function()
	local n = 0
	routePts = nil
	local t = ns.FrameTarget()
	if t and not t.inside and state.playerCol and state.playerMap == state.map then
		-- On the canvas: tile (col, row) is at (col * zoom, row * zoom) down from its top left.
		local z = state.zoom
		local x1, y1 = HalfPixel(state.playerCol * z), HalfPixel(state.playerRow * z)
		local x2, y2 = HalfPixel(t.col * z), HalfPixel(t.row * z)
		local pts, found = ns.RouteTo(t)
		local facing = GetPlayerFacing()
		facing = facing and math.floor(facing / FACING_STEP + 0.5) * FACING_STEP
		if Unchanged(x1, y1, x2, y2, found, facing) then
			routePts = drawnRoute
			return
		end
		if not pts then
			pts = straight
			pts[1][1], pts[1][2], pts[2][1], pts[2][2] = state.playerCol, state.playerRow, t.col, t.row
		end
		if facing then pts = LeadIn(pts, facing, LEAD / z) end
		routePts = found and pts
		drawnRoute = routePts
		local m = #pts
		for i = 1, m do
			xs[i], ys[i] = pts[i][1] * z, pts[i][2] * z
			along[i] = i == 1 and 0 or along[i - 1] + math.sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2)
		end
		local len = along[m]
		local s0, s1 = CLEAR_YOU, len - CLEAR_TARGET
		if s1 > s0 then
			-- Pieces of a fixed length laid back from the target, so they too stay put as you walk.
			local step = math.max(PIECE, (s1 - s0) / MAX_PIECES)
			local i = m - 1
			local a = s1
			while a > s0 and n < MAX_PIECES do
				local b = a
				a = math.max(s0, b - step)
				while i > 1 and along[i] > a do i = i - 1 end
				local j = i
				while j < m - 1 and along[j + 1] < b do j = j + 1 end
				n = n + 1
				local mid = (a + b) / 2
				local f = math.min(1, (mid - s0) / FADE, (s1 - mid) / FADE)
				local even = 1 - UNEVEN * (0.5 + 0.5 * math.sin((len - mid) * 0.045 + 2))
				local ax, ay = At(i, a, len)
				local bx, by = At(j, b, len)
				ax, ay, bx, by = HalfPixel(ax), HalfPixel(ay), HalfPixel(bx), HalfPixel(by)
				Segment(Get(washes, n, 0, WASH), ax, ay, bx, by, WASH_RGBA, HalfPixel(WASH_RGBA[4] * f * 100) / 100)
				Segment(Get(strokes, n, 1, STROKE), ax, ay, bx, by, STROKE_RGBA, HalfPixel(STROKE_RGBA[4] * f * even * 100) / 100)
			end
		end
	end
	if n == 0 then drawn[1] = nil end
	for i = n + 1, used do
		Off(strokes[i])
		Off(washes[i])
	end
	used = n
end))

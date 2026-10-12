-- Path mode's line: a dashed line from you to your target, light on a dark
-- edge so it reads on pale ground too, its dashes drifting slowly toward
-- the target. It follows the way you'd walk (Route.lua) once that's found,
-- else it's straight - "that way". It leaves you the way you're facing and
-- bends onto the way, and it sits under the labels and pins. Outside path
-- mode, whatever you track still gets the same line, thin, faint and solid.

local ADDON, ns = ...
local state = ns.state

local DASH, GAP = 7, 6     -- px
local FLOW = 14            -- px per second the dashes drift toward the target
local MAX_DASHES = 120     -- longer lines get longer dashes instead of more
local CLEAR_YOU, CLEAR_TARGET = 14, 15 -- px left clear around your arrow and the target's pin
local FADE = 40            -- px over which the line fades in and out at its ends
local DRIFT_HZ = 10        -- the drift steps this often (1.4 px a step); the line redraws only when it or the view moves
local CORE, EDGE = 2.2, 4.5 -- px: the dash and the dark edge under it
local CORE_ALPHA, EDGE_ALPHA = 0.85, 0.45
local THIN, THIN_EDGE = 1.2, 2.6 -- px: outside path mode, the solid line and its edge
local THIN_ALPHA, THIN_EDGE_ALPHA = 0.5, 0.25
local LEAD = 48            -- px of line (at most half of it) that bends from where you face onto the way
local LEAD_STEPS = 8
local FACING_STEP = math.rad(3) -- turning less than this doesn't redraw the line

-- Off the map, your target gets a gold arrow on the map's edge, where the
-- line toward it leaves the map (Blizzard's own rim arrows are pushed away:
-- MinimapTakeover).
local EDGE_INSET = 16 -- px from the map's edge to the arrow's centre
-- The route the path line last followed (tile positions, you first), or nil:
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

local dashes, shadows = {}, {}
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

-- Only what changed: most of a line's dashes keep their colour from frame to frame.
local function Segment(l, ax, ay, bx, by, r, g, b, a)
	if l.r ~= r or l.a ~= a then
		l.r, l.a = r, a
		l:SetColorTexture(r, g, b, a)
	end
	l:SetStartPoint("TOPLEFT", ns.tileCanvas, ax, -ay)
	l:SetEndPoint("TOPLEFT", ns.tileCanvas, bx, -by)
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
-- the zoom changes, the route is found again, or the drift steps (DRIFT_HZ).
local drawn = {}
local drawnRoute -- routePts as last drawn
local function Unchanged(x1, y1, x2, y2, phase, route, facing)
	if drawn[1] == x1 and drawn[2] == y1 and drawn[3] == x2 and drawn[4] == y2 and drawn[5] == phase
		and drawn[6] == route and drawn[7] == facing then return true end
	drawn[1], drawn[2], drawn[3], drawn[4], drawn[5], drawn[6], drawn[7] = x1, y1, x2, y2, phase, route, facing
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

-- Point at distance s along the line, from corner i on (s past along[i]).
local function At(i, s)
	local seg = along[i + 1] - along[i]
	local k = seg > 0 and (s - along[i]) / seg or 0
	return xs[i] + (xs[i + 1] - xs[i]) * k, ys[i] + (ys[i + 1] - ys[i]) * k
end

ns.frame:HookScript("OnUpdate", ns.Timed("path line", function()
	local n = 0
	routePts = nil
	local t = ns.FrameTarget()
	if t and not t.inside and state.playerCol and state.playerMap == state.map then
		local solid = not state.path
		-- On the canvas: tile (col, row) is at (col * zoom, row * zoom) down from its top left.
		local z = state.zoom
		local x1, y1 = HalfPixel(state.playerCol * z), HalfPixel(state.playerRow * z)
		local x2, y2 = HalfPixel(t.col * z), HalfPixel(t.row * z)
		local phase = solid and -1 or math.floor(GetTime() * DRIFT_HZ) / DRIFT_HZ
		local pts, found = ns.RouteTo(t)
		local facing = GetPlayerFacing()
		facing = facing and math.floor(facing / FACING_STEP + 0.5) * FACING_STEP
		if Unchanged(x1, y1, x2, y2, phase, found, facing) then
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
		if s1 > s0 and solid then
			-- A piece per leg, faded toward the ends like the dashes.
			for i = 1, m - 1 do
				local a, b = math.max(along[i], s0), math.min(along[i + 1], s1)
				if b > a and n < MAX_DASHES then
					n = n + 1
					local mid = (a + b) / 2
					local f = math.min(1, (mid - s0) / FADE, (s1 - mid) / FADE)
					local ax, ay = At(i, a)
					local bx, by = At(i, b)
					Segment(Get(shadows, n, 0, THIN_EDGE), ax, ay, bx, by, 0, 0, 0, THIN_EDGE_ALPHA * f)
					Segment(Get(dashes, n, 1, THIN), ax, ay, bx, by, 1, 0.93, 0.75, THIN_ALPHA * f)
				end
			end
		elseif s1 > s0 then
			local scale = math.max(1, (s1 - s0) / (DASH + GAP) / MAX_DASHES)
			local dash, step = DASH * scale, (DASH + GAP) * scale
			local s = s0 + (phase * FLOW) % step - step
			local i, j = 1, 1 -- the legs a dash starts and ends on
			while s < s1 and n < MAX_DASHES do
				local a, b = math.max(s, s0), math.min(s + dash, s1)
				if b > a then
					n = n + 1
					local mid = (a + b) / 2
					local f = math.min(1, (mid - s0) / FADE, (s1 - mid) / FADE)
					while i < m - 1 and along[i + 1] < a do i = i + 1 end
					while j < m - 1 and along[j + 1] < b do j = j + 1 end
					local ax, ay = At(i, a)
					local bx, by = At(j, b)
					Segment(Get(shadows, n, 0, EDGE), ax, ay, bx, by, 0, 0, 0, EDGE_ALPHA * f)
					Segment(Get(dashes, n, 1, CORE), ax, ay, bx, by, 1, 0.93, 0.75, CORE_ALPHA * f)
				end
				s = s + step
			end
		end
	end
	if n == 0 then drawn[1] = nil end
	for i = n + 1, used do
		Off(dashes[i])
		Off(shadows[i])
	end
	used = n
end))

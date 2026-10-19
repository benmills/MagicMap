-- Zone and subzone borders, the spike's look (D5; Layers.lua:1531-1590, 1735-1802): a zone border a
-- warm line on one soft shadow (from zoom 60), 2 Lines a segment; a subzone's a faint hairline from
-- zoom 140. A point nearer than MIN_SEG_PX to the last kept merges into it; a dead end (Data/Borders.lua's
-- fadeStart, fadeEnd) breaks over its last FADE_PX into dashes of falling width and alpha, at most
-- DASHES an end. At most CAP Lines a layout. Segments are clipped to the layout's region, so no Line
-- reaches far past it (the offsets stay small: ui/Engine.lua). While the zoom moves, scaled and dimmed, then
-- crossfaded to the layout where it lands (Engine's "hold"). A layout keeps the Lines its canvas drew
-- (Engine.Keep, by piece): one whole at the same zoom and origin is left as it is, so a pan's layout sets
-- only what it adds (it set every Line: most of a drag's frames over 3 ms in Orgrimmar).

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime, Engine = ns.Atlas, ns.Runtime, ns.UI.Engine
local Get, Keep, Yield = Engine.Get, Engine.Keep, Runtime.Yield

local FADE_PX, DASH_PX, GAP_PX = 36, 5, 4 -- Layers.lua:1531
local DASHES = 4 -- an end's dashes: 4 fill FADE_PX (the rebuild's cost cap: docs/v1-plan.md §4)
local MIN_FADE = 0.08 -- a dash fainter is dropped (Layers.lua:1575)
local MIN_SEG_PX = 2.5 -- Layers.lua:1532
local CAP = 3000 -- Lines a layout (Layers.lua:218-226)
local SHADOW_ZOOM, SUBZONE_ZOOM = 60, 140 -- Layers.lua:1746, 1424
local ZONE, SHADOW, SUB = { 1, 0.9, 0.72, 0.6 }, { 0, 0, 0, 0.25 }, { 1, 0.95, 0.85, 0.22 } -- Layers.lua:1589-1590, 1747
local COLOR = { line = ZONE, shadow = SHADOW, sub = SUB }
local SHADOW_PX = 1.2 -- the shadow's width over the line's (Layers.lua:1747)

-- Line makers by kind: subzones under the shadows, the shadows under the zone lines (Layers.lua:230-233).
local SUBLEVEL, makers = { sub = -1, shadow = 0, line = 1 }, {}
for kind, sub in pairs(SUBLEVEL) do
	makers[kind] = function(c)
		local l = c:CreateLine(nil, "ARTWORK", nil, sub)
		l:SetSnapToPixelGrid(false) -- else short or thin segments snap away and look dashed
		l:SetTexelSnappingBias(0)
		return l
	end
end

-- The layout's region in canvas px, and its Lines so far.
local box, made = { 0, 0, 0, 0 }, 0

-- A segment clipped to the box (Liang-Barsky), or nil: none of it inside; and whether it's whole.
local function Clip(x1, y1, x2, y2)
	local t0, t1, dx, dy = 0, 1, x2 - x1, y2 - y1
	for side = 1, 4 do
		local p, q
		if side == 1 then p, q = -dx, x1 - box[1]
		elseif side == 2 then p, q = dx, box[3] - x1
		elseif side == 3 then p, q = -dy, y1 - box[2]
		else p, q = dy, box[4] - y1 end
		if p == 0 then
			if q < 0 then return nil end
		else
			local r = q / p -- /: never 0 (p checked)
			if p < 0 then
				if r > t1 then return nil end
				if r > t0 then t0 = r end
			else
				if r < t0 then return nil end
				if r < t1 then t1 = r end
			end
		end
	end
	return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1, t0 == 0 and t1 == 1
end

-- A Line set: its colour is its kind's (a pool a kind), its alpha and width as given. One whole (not
-- clipped to the box) stands as set while its canvas's epoch holds (l.e).
local function Set(c, l, kind, x1, y1, x2, y2, w, a, whole)
	if l.a ~= a then
		local col = COLOR[kind]
		l:SetColorTexture(col[1], col[2], col[3], a)
		l.a = a
	end
	if l.w ~= w then
		l:SetThickness(w)
		l.w = w
	end
	l:SetStartPoint("TOPLEFT", c, x1, -y1)
	l:SetEndPoint("TOPLEFT", c, x2, -y2)
	l.e = whole and c.epoch
end

-- The Lines no Line on the canvas drew (Engine.Keep): drawn after the rest (a Get takes the next one,
-- whatever it drew). Scratch, reused: each one's kind, key, ends, width, alpha, whole.
local lk, lkey, lx1, ly1, lx2, ly2, lw, la, lwhole, nl = {}, {}, {}, {}, {}, {}, {}, {}, {}, 0

-- One Line of a piece: the canvas's own for key if it drew it (whole, at this epoch: left as it is).
local function Line(c, kind, key, x1, y1, x2, y2, w, a, whole)
	if made >= CAP then return end
	made = made + 1
	local l = Keep(c, kind, key)
	if l then
		if not (whole and l.e == c.epoch) then Set(c, l, kind, x1, y1, x2, y2, w, a, whole) end
	else
		nl = nl + 1
		lk[nl], lkey[nl], lx1[nl], ly1[nl], lx2[nl], ly2[nl], lw[nl], la[nl], lwhole[nl] = kind, key, x1, y1, x2, y2, w, a, whole
	end
	Yield()
end

-- One polyline's points in canvas px, those kept, and the length along it to each: scratch, reused.
local xs, ys, at = {}, {}, {}
local function Points(l, first, zoom, ox, oy)
	local n, last, min2 = 0, #l - 1, MIN_SEG_PX * MIN_SEG_PX
	for i = first, last, 2 do
		local x, y = (l[i] - ox) * zoom, (l[i + 1] - oy) * zoom
		if n == 0 or i >= last - 1 or (x - xs[n]) ^ 2 + (y - ys[n]) ^ 2 >= min2 then
			n = n + 1
			xs[n], ys[n] = x, y
			at[n] = n == 1 and 0 or at[n - 1] + math.sqrt((x - xs[n - 1]) ^ 2 + (y - ys[n - 1]) ^ 2)
		end
	end
	return n
end

-- The point s px along the polyline.
local function PointAt(n, s)
	local k = n - 1
	if s < at[n] / 2 then
		k = 1
		while at[k + 1] < s do k = k + 1 end
	else
		while k > 1 and at[k] > s do k = k - 1 end
	end
	local d = at[k + 1] - at[k]
	local u = d > 0 and (s - at[k]) / d or 0 -- /: never 0 (checked)
	return xs[k] + (xs[k + 1] - xs[k]) * u, ys[k] + (ys[k + 1] - ys[k]) * u
end

-- A zone border's piece (its shadow, then it) or a subzone's, f of the way faded in (Layers.lua:1568-1577).
-- key: which piece of which polyline (its Lines' keys: Engine.Keep).
local style = {} -- this layout's: thick, shadow (zone), sub (subzone thick)
local function Piece(c, zone, key, x1, y1, x2, y2, f)
	local whole
	x1, y1, x2, y2, whole = Clip(x1, y1, x2, y2)
	if not x1 then return end
	local w = 0.6 + 0.4 * f
	if not zone then return Line(c, "sub", key, x1, y1, x2, y2, style.sub, SUB[4], whole) end
	if style.shadow then Line(c, "shadow", key, x1, y1, x2, y2, (style.thick + SHADOW_PX) * w, SHADOW[4] * f, whole) end
	Line(c, "line", key, x1, y1, x2, y2, style.thick * w, ZONE[4] * f, whole)
end

-- An end's dashes, from it inward over fade px (fromEnd: the polyline's last point's). base: the
-- polyline's key, a piece's: base + 16 * (its segment, or dash) + (0 solid, 1 a dash from its start, 2 its end).
local function Dashes(c, n, fade, fromEnd, base)
	local total = at[n]
	for j = 0, DASHES - 1 do
		local d0 = j * (DASH_PX + GAP_PX)
		if d0 >= fade then return end
		local d1 = math.min(fade, d0 + DASH_PX)
		local f = (d0 + d1) / 2 / fade -- /: never 0 (fade > d0 >= 0)
		if f > MIN_FADE then
			local x1, y1 = PointAt(n, fromEnd and total - d0 or d0)
			local x2, y2 = PointAt(n, fromEnd and total - d1 or d1)
			Piece(c, true, base + j * 16 + (fromEnd and 2 or 1), x1, y1, x2, y2, f)
		end
	end
end

-- The polyline in xs, ys: its solid stretch, then each fading end's dashes (subzones never fade).
local function Polyline(c, n, zone, fs, fe, base)
	if n < 2 then return end
	local total = at[n]
	local fade = math.min(FADE_PX, total / 2)
	local s0, s1 = fs and fade or 0, total - (fe and fade or 0)
	for k = 1, n - 1 do
		local a0, a1 = at[k], at[k + 1]
		if a1 > s0 and a0 < s1 and a1 > a0 then
			local d, x, y = a1 - a0, xs[k], ys[k]
			local u0, u1 = math.max(0, (s0 - a0) / d), math.min(1, (s1 - a0) / d) -- /: never 0 (a1 > a0)
			local dx, dy = xs[k + 1] - x, ys[k + 1] - y
			Piece(c, zone, base + k * 16, x + dx * u0, y + dy * u0, x + dx * u1, y + dy * u1, 1)
		end
	end
	if fs and fade > 0 then Dashes(c, n, fade, false, base) end
	if fe and fade > 0 then Dashes(c, n, fade, true, base) end
end

-- Each line's bounds in tiles, once per line (its points from first).
local bounds = setmetatable({}, { __mode = "k" })
local function Bounds(l, first)
	local b = bounds[l]
	if not b then
		b = { math.huge, math.huge, -math.huge, -math.huge }
		for i = first, #l, 2 do
			b[1], b[3] = math.min(b[1], l[i]), math.max(b[3], l[i])
			b[2], b[4] = math.min(b[2], l[i + 1]), math.max(b[4], l[i + 1])
		end
		bounds[l] = b
	end
	return b
end

-- The lines whose bounds meet the region, each as a polyline (first: its first x).
local NONE = {}
local function Lines(c, lines, first, zone, zoom, c0, r0, c1, r1)
	local ox, oy = c.ox, c.oy -- (the canvas's origin, ui/Engine.lua)
	for i, l in ipairs(lines) do
		local b = Bounds(l, first)
		if not (b[3] < c0 or b[1] > c1 or b[4] < r0 or b[2] > r1) then
			Polyline(c, Points(l, first, zoom, ox, oy), zone, zone and l[3] > 0, zone and l[4] > 0, i * 1048576)
		end
		if made >= CAP then return end
		Yield()
	end
end

UI.Borders = Engine.Layer("borders", 7, function(c, inst, zoom, c0, r0, c1, r1)
	local lines = Atlas.BorderLines(inst, zoom)
	if not lines then return end
	made, nl = 0, 0
	box[1], box[2], box[3], box[4] = (c0 - c.ox) * zoom, (r0 - c.oy) * zoom, (c1 - c.ox) * zoom, (r1 - c.oy) * zoom
	style.thick = math.max(1.1, math.min(1.8, zoom / 140)) -- Layers.lua:1589
	style.shadow = zoom >= SHADOW_ZOOM
	style.sub = math.max(0.8, math.min(1.1, zoom / 300)) -- Layers.lua:1590
	Lines(c, lines, 5, true, zoom, c0, r0, c1, r1)
	if zoom >= SUBZONE_ZOOM then Lines(c, Atlas.SubzoneLines(inst, zoom) or NONE, 3, false, zoom, c0, r0, c1, r1) end
	for i = 1, nl do
		local kind = lk[i]
		Set(c, Get(c, kind, "line", makers[kind], lkey[i]), kind, lx1[i], ly1[i], lx2[i], ly2[i], lw[i], la[i], lwhole[i])
		Yield()
	end
end, nil, "hold")

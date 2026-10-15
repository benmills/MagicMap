-- Zone borders as demo/borders.js draws them: one Line region per segment, the halo
-- (wider, darker Lines) under them all, fading ends cut into short Lines of falling
-- alpha and thickness.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime, Engine = ns.Atlas, ns.Runtime, ns.UI.Engine
local Get, Yield = Engine.Get, Runtime.Yield

local STYLE = { -- demo/borders.js BORDER_STYLE
	steps = { -- from zoom (px per tile) up: the light line's width, alpha; halo { extra width, alpha }, widest first
		{ zoom = 0, width = 1.0, alpha = 0.6, halo = { { 3.0, 0.16 }, { 1.8, 0.3 } } },
		{ zoom = 40, width = 1.3, alpha = 0.7, halo = { { 4.0, 0.16 }, { 2.4, 0.32 } } },
		{ zoom = 120, width = 1.7, alpha = 0.78, halo = { { 5.5, 0.15 }, { 3.0, 0.34 } } },
		{ zoom = 300, width = 2.2, alpha = 0.82, halo = { { 7.0, 0.14 }, { 3.8, 0.36 } } },
	},
	color = { 1, 216 / 255, 140 / 255 },
	haloColor = { 12 / 255, 8 / 255, 4 / 255 },
	fadeMinPx = 12, fadePiecePx = 4, minSegmentPx = 1.5,
}

-- Line makers, one per sublevel: halos under (0, 1), the light line over (2).
local makers = {}
local function Maker(sub)
	makers[sub] = makers[sub] or function(c)
		local l = c:CreateLine(nil, "ARTWORK", nil, sub)
		l:SetSnapToPixelGrid(false) -- else short or thin segments snap away and look dashed
		l:SetTexelSnappingBias(0)
		return l
	end
	return makers[sub]
end

local function Line(c, kind, sub, x1, y1, x2, y2, w, col, a)
	local l = Get(c, kind, "line", Maker(sub))
	if l.r ~= col[1] or l.g ~= col[2] or l.b ~= col[3] or l.a ~= a then
		l:SetColorTexture(col[1], col[2], col[3], a)
		l.r, l.g, l.b, l.a = col[1], col[2], col[3], a
	end
	if l.w ~= w then
		l:SetThickness(w)
		l.w = w
	end
	l:SetStartPoint("TOPLEFT", c, x1, -y1)
	l:SetEndPoint("TOPLEFT", c, x2, -y2)
end

-- A polyline (flat x, y list in canvas px) as Lines; fs / fe px fade out at its start / end.
-- Segments outside box (canvas px) are skipped.
local function Polyline(c, kind, sub, p, w, col, a, fs, fe, box)
	local total = 0
	for i = 3, #p, 2 do total = total + math.sqrt((p[i] - p[i - 2]) ^ 2 + (p[i + 1] - p[i - 1]) ^ 2) end
	fs, fe = math.min(fs, total / 2), math.min(fe, total / 2)
	local along = 0
	for i = 3, #p, 2 do
		local x1, y1, x2, y2 = p[i - 2], p[i - 1], p[i], p[i + 1]
		local d = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		local inside = math.max(x1, x2) >= box[1] and math.min(x1, x2) <= box[3] and math.max(y1, y2) >= box[2]
			and math.min(y1, y2) <= box[4]
		if inside and along >= fs and along + d <= total - fe then
			Line(c, kind, sub, x1, y1, x2, y2, w, col, a)
		elseif inside then
			local n = math.max(1, math.ceil(d / STYLE.fadePiecePx)) -- /: never 0 (STYLE.fadePiecePx = 4)
			for k = 0, n - 1 do
				local m = along + d * (k + 0.5) / n -- /: never 0 (n >= 1)
				local f = math.min(1, fs > 0 and m / fs or 1, fe > 0 and (total - m) / fe or 1) -- /: never 0 (checked > 0)
				if f >= 0.05 then
					Line(c, kind, sub, x1 + (x2 - x1) * k / n, y1 + (y2 - y1) * k / n, -- /: never 0 (n >= 1)
						x1 + (x2 - x1) * (k + 1) / n, y1 + (y2 - y1) * (k + 1) / n, -- /: never 0 (n >= 1)
						w * (0.6 + 0.4 * f), col, a * f)
					Yield() -- a long fading segment is many Lines
				end
			end
		end
		along = along + d
		Yield() -- per segment: a long border mustn't overrun its layout's budget (spike-bugs P1)
	end
end

-- Each line's bounds in tiles, once per line list.
local bounds = setmetatable({}, { __mode = "k" })
local function Bounds(l)
	local b = bounds[l]
	if not b then
		b = { math.huge, math.huge, -math.huge, -math.huge }
		for i = 5, #l, 2 do
			b[1], b[3] = math.min(b[1], l[i]), math.max(b[3], l[i])
			b[2], b[4] = math.min(b[2], l[i + 1]), math.max(b[4], l[i + 1])
		end
		bounds[l] = b
	end
	return b
end

UI.Borders = Engine.Layer("borders", 2, function(c, inst, zoom, c0, r0, c1, r1)
	local lines = Atlas.BorderLines(inst, zoom)
	if not lines then return end
	local s = STYLE.steps[1]
	for _, st in ipairs(STYLE.steps) do
		if zoom >= st.zoom then s = st end
	end
	local drawn, min2 = {}, STYLE.minSegmentPx ^ 2
	local box = { c0 * zoom, r0 * zoom, c1 * zoom, r1 * zoom }
	for _, l in ipairs(lines) do
		local b = Bounds(l)
		if not (b[3] < c0 or b[1] > c1 or b[4] < r0 or b[2] > r1) then
			local p, n = {}, (#l - 4) / 2
			for k = 1, n do
				local x, y = l[3 + k * 2] * zoom, l[4 + k * 2] * zoom
				local m = #p
				if m == 0 or k == n or (x - p[m - 1]) ^ 2 + (y - p[m]) ^ 2 >= min2 then
					p[m + 1], p[m + 2] = x, y
				end
			end
			drawn[#drawn + 1] = { p = p, fs = l[3] > 0 and math.max(l[3] * zoom, STYLE.fadeMinPx) or 0,
				fe = l[4] > 0 and math.max(l[4] * zoom, STYLE.fadeMinPx) or 0 }
		end
		Yield()
	end
	-- Halos first, all of them, so none darkens a neighbour's light line where they meet.
	for i, h in ipairs(s.halo) do
		for _, d in ipairs(drawn) do
			Polyline(c, "halo" .. i, i - 1, d.p, h[1] + s.width, STYLE.haloColor, h[2], d.fs, d.fe, box)
			Yield()
		end
	end
	for _, d in ipairs(drawn) do
		Polyline(c, "line", 2, d.p, s.width, STYLE.color, s.alpha, d.fs, d.fe, box)
		Yield()
	end
end)

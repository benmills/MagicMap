-- Map names from Atlas.Labels and flight points from Atlas.FlightPoints, after
-- demo/labels.js: per tier a zoom band, a font and size; placed in rank order,
-- a name that would touch one already placed (or a flight point) dropped.
-- Morpheus for continent and zone, Friz Quadrata for the rest. No fades,
-- small caps, tracking or soft glow yet: a shadow is the halo.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime, Map = ns.Atlas, ns.Runtime, ns.UI.Map
local Get, Unget, Yield = Map.Get, Map.Unget, Runtime.Yield

local TITLE, BODY = "Fonts\\MORPHEUS.TTF", "Fonts\\FRIZQT__.TTF"
local PAD = 3 -- px a label keeps clear of placed labels and pins
local PIN = 20 -- a flight point's size, px
local FLIGHT = { A = "taxinode_alliance", H = "taxinode_horde", AH = "taxinode_neutral" }

-- demo/labels.js LABEL_STYLE: zoom band [from, to) px per tile; size px, or k * the
-- area's side on screen clamped; below `over` the name ignores pins.
local huge = math.huge
local TIERS = {
	continent = { zoom = { 0, 26 }, over = 26, font = TITLE, size = { k = 0.1, min = 15, max = 22 }, upper = true,
		color = { 0.95, 0.87, 0.68 }, alpha = 0.92 },
	zone = { zoom = { 6, 320 }, over = 40, font = TITLE, size = { k = 0.085, min = 11.5, max = 22 },
		color = { 1, 0.89, 0.63 }, alpha = 0.95 },
	town = { zoom = { 30, huge }, font = BODY, size = 12.5, color = { 0.98, 0.96, 0.92 }, alpha = 0.9 },
	subzone = { zoom = { 72, huge }, font = BODY, size = { k = 0.1, min = 10.5, max = 13 },
		color = { 0.91, 0.86, 0.77 }, alpha = 0.78 },
	poi = { zoom = { 150, huge }, font = BODY, size = 10.5, color = { 0.84, 0.8, 0.71 }, alpha = 0.68 },
}

local function MakeFont(c)
	local fs = c:CreateFontString(nil, "OVERLAY")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.85)
	return fs
end

local function MakePin(c)
	return c:CreateTexture(nil, "ARTWORK")
end

local function Size(l, st, zoom)
	local s = st.size
	if type(s) == "number" then return s end
	return math.floor(math.max(s.min, math.min(s.max, s.k * (l.size or 0) * zoom)) * 2 + 0.5) / 2
end

local function Clear(boxes, x0, y0, x1, y1)
	for _, b in ipairs(boxes) do
		if x0 - PAD < b[3] and x1 + PAD > b[1] and y0 - PAD < b[4] and y1 + PAD > b[2] then return false end
	end
	return true
end

-- Where a label may sit relative to its anchor, in order: on it, above / below, beside;
-- a town or landmark beside its spot first after on it.
-- One scratch list, refilled per label (a layout makes no tables per label).
local spots = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
local function Spot(i, x, y) spots[i][1], spots[i][2] = x, y end
local function Spots(l, w, h)
	if l.tier == "town" or l.tier == "poi" then
		local g = PIN / 2 + PAD
		Spot(2, g + w / 2, 0); Spot(3, -g - w / 2, 0); Spot(4, 0, -g - h / 2); Spot(5, 0, g + h / 2)
		return spots
	end
	local dx, dy = math.min(w * 0.35, 40), h * 1.1
	Spot(2, 0, -dy); Spot(3, 0, dy); Spot(4, dx, 0); Spot(5, -dx, 0)
	return spots
end

UI.Labels = Map.NewLayer("labels", 3, function(c, inst, zoom, c0, r0, c1, r1)
	local pins = {}
	for _, f in ipairs(Atlas.FlightPoints(inst)) do
		if f.col >= c0 and f.col <= c1 and f.row >= r0 and f.row <= r1 then
			local x, y = f.col * zoom, f.row * zoom
			local t = Get(c, "flight", "tex", MakePin)
			t:SetAtlas(FLIGHT[f.faction] or "taxinode_neutral")
			t:SetSize(PIN, PIN)
			t:SetPoint("CENTER", c, "TOPLEFT", x, -y)
			pins[#pins + 1] = { x - PIN / 2, y - PIN / 2, x + PIN / 2, y + PIN / 2 }
		end
	end
	local boxes = {}
	for i, l in ipairs(Atlas.Labels(inst)) do
		local st = TIERS[l.tier]
		if zoom >= st.zoom[1] and zoom < st.zoom[2] and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then
			local fs = Get(c, "label", "font", MakeFont)
			local size = Size(l, st, zoom)
			if fs.font ~= st.font or fs.size ~= size then
				fs:SetFont(st.font, size, "")
				fs.font, fs.size = st.font, size
			end
			fs:SetText(st.upper and l.text:upper() or l.text)
			fs:SetTextColor(st.color[1], st.color[2], st.color[3], st.alpha)
			local w, h = fs:GetStringWidth(), fs:GetStringHeight()
			local ax, ay, at = l.col * zoom, l.row * zoom, nil
			for _, s in ipairs(Spots(l, w, h)) do
				local x, y = ax + s[1], ay + s[2]
				local x0, y0, x1, y1 = x - w / 2, y - h / 2, x + w / 2, y + h / 2
				if Clear(boxes, x0, y0, x1, y1) and (zoom < (st.over or 0) or Clear(pins, x0, y0, x1, y1)) then
					boxes[#boxes + 1] = { x0, y0, x1, y1 }
					at = s
					fs:SetPoint("CENTER", c, "TOPLEFT", x, -y)
					break
				end
			end
			if not at then Unget(c, "label") end
		end
		if i % 20 == 0 then Yield() end
	end
end)

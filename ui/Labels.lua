-- Zone and subzone names (Atlas.Labels, ranked offline: Data/Labels.lua), the spike's look
-- (Layers.lua:1417-1458, 1619-1694): quiet, as on a printed map. Zones in Morpheus, mixed case, 11.5 to
-- 22 pt by their land's size on screen, up to zoom 450, with a soft dark shadow and an outline at small
-- sizes (the MVP's look, 672d8b2^:ui/Labels.lua); subzones quieter, one look at every zoom: Friz Quadrata
-- 9 pt, dimmer, the shadow alone, from zoom 120, 220 or 400 by their size. Zones first,
-- then subzones, each biggest first: a name tries its spot, just above, just below, and is skipped
-- if all three touch one placed. Every zone of the map is placed (its box: a name's spot doesn't
-- change on a pan), those over the view and its margin drawn (ui/Engine.lua); subzones are placed
-- near the view, around them, and again once it pans out of them (Layers.lua:1631-1673); moved with
-- the zoom ("move"). A name the last layout didn't show fades in. While the big map shows a capital's city map
-- (ui/Interiors.lua), the areas named on its rooms (Atlas.City's labels: The Great Forge, the Apothecarium...)
-- are subzones too, placed first, but for a name the terrain's subzones have.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime, Engine = ns.Atlas, ns.Runtime, ns.UI.Engine
local Get, Unget, At, Yield = Engine.Get, Engine.Unget, Engine.At, Runtime.Yield

local TITLE, BODY = "Fonts\\MORPHEUS.TTF", GameFontNormal:GetFont() -- Morpheus for zones; Friz Quadrata (Layers.lua:1417)
local ZONE, SUB = { 1, 0.89, 0.63, 0.95 }, { 0.91, 0.86, 0.77, 0.6 } -- the MVP's (672d8b2^:ui/Labels.lua); subzones quieter
local ZONE_K, ZONE_MIN, ZONE_MAX = 0.085, 11.5, 22 -- a zone's size: k * its land's side * zoom, clamped
local SUB_SIZE = 9 -- a subzone's, one size and look at every zoom: shadow only, no outline (quiet over legible)
local OUTLINE_MAX = 12 -- a zone name at or below this size gets an outline (the font's OUTLINE flag) with the shadow
local MAX_ZOOM = 450 -- zone names hidden zoomed in past this (Layers.lua:77)
local SUB_ZOOM = 120 -- subzone names from here (weight >= 40), 220 (>= 15), else 400 (Layers.lua:1426, 1639)
local SHADOW = 0.85 -- the soft drop shadow's alpha, offset (1, -1)
local PAD_X, PAD_Y, GAP = 4, 2, 3 -- a name's clearance, and its spots' gap above and below (Layers.lua:1447-1448)
local FADE_S = 0.2 -- Layers.lua:1619

local function MakeFont(c)
	local fs = c:CreateFontString(nil, "OVERLAY")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, SHADOW)
	return fs
end

-- A name's font flags at its size: an outline where the shadow alone reads thin.
local function Flags(size) return size <= OUTLINE_MAX and "OUTLINE" or "" end

-- A name's size on screen: k * its land's side (tiles) * zoom, clamped, in whole points (fewer SetFonts as the zoom moves).
local function SizeAt(l, k, min, max, zoom)
	return math.floor(math.max(min, math.min(max, k * (l.side or 0) * zoom)) + 0.5)
end

-- Per map, its names as the spike has them: zones and subzones (a town that is one included), each
-- biggest first; weight: land chunks (docs/atlas-data.md: Data/Labels.lua's size).
local lists = {}
local function Bigger(a, b) return a.weight > b.weight or a.weight == b.weight and a.rank < b.rank end
local function List(inst)
	local list = lists[inst]
	if list then return list end
	list = { zones = {}, subs = {} }
	for _, a in ipairs(Atlas.Labels(inst)) do
		if a.size and a.tier ~= "continent" then
			local w = math.floor((a.size * 16) ^ 2 + 0.5)
			local l = { text = a.text, col = a.col, row = a.row, weight = w, rank = a.rank, areaID = a.areaID, side = a.size }
			if a.tier == "zone" then
				list.zones[#list.zones + 1] = l
			else
				l.zoom = w >= 40 and SUB_ZOOM or w >= 15 and 220 or 400
				list.subs[#list.subs + 1] = l
			end
		end
	end
	table.sort(list.zones, Bigger)
	table.sort(list.subs, Bigger)
	list.named = {}
	for _, l in ipairs(list.subs) do list.named[l.text] = true end
	lists[inst] = list
	return list
end

-- A city's area names as subzones (weight, zoom: as List's), but for those the map's subzones have. Kept.
local cityLists = {}
local function CityList(city, list)
	local out = cityLists[city]
	if out then return out end
	out = {}
	for i, a in ipairs(city.labels) do
		if not list.named[a.text] then
			local w = math.floor((a.size * 16) ^ 2 + 0.5)
			out[#out + 1] = { text = a.text, col = a.col, row = a.row, weight = w, rank = i,
				zoom = w >= 40 and SUB_ZOOM or w >= 15 and 220 or 400 }
		end
	end
	cityLists[city] = out
	return out
end

-- Placed names' boxes (canvas px, flat: x0, y0, x1, y1, ...): scratch, reused.
local boxes, nboxes = {}, 0
local function Overlaps(x0, y0, x1, y1)
	for i = 1, nboxes, 4 do
		if x0 < boxes[i + 2] and x1 > boxes[i] and y0 < boxes[i + 3] and y1 > boxes[i + 1] then return true end
	end
	return false
end

-- The name's spot (its offset down, px), just above or just below, whichever touches no name placed,
-- kept as placed; nil: none (Layers.lua:1440-1461). w: half its width, padded; h: its height.
local function Spot(c, l, zoom, w, h)
	local x, y = (l.col - c.ox) * zoom, (l.row - c.oy) * zoom
	for i = 1, 3 do
		local dy = i == 1 and 0 or i == 2 and -(h + GAP) or h + GAP
		local y0, y1 = y + dy - h / 2 - PAD_Y, y + dy + h / 2 + PAD_Y
		if not Overlaps(x - w, y0, x + w, y1) then
			boxes[nboxes + 1], boxes[nboxes + 2], boxes[nboxes + 3], boxes[nboxes + 4] = x - w, y0, x + w, y1
			nboxes = nboxes + 4
			return dy
		end
	end
end

local function Font(c, l, font, size, color, flags)
	local fs = Get(c, "label", "font", MakeFont)
	if fs.font ~= font or fs.size ~= size or fs.flags ~= flags then
		fs:SetFont(font, size, flags)
		fs.font, fs.size, fs.flags = font, size, flags
	end
	if fs.color ~= color then
		fs:SetTextColor(color[1], color[2], color[3], color[4])
		fs.color = color
	end
	if fs.text ~= l.text then
		fs:SetText(l.text)
		fs.text = l.text
	end
	return fs
end

local NONE = {}
-- The name drawn at its spot; fading in unless the last layout showed it.
local function Show(c, fs, l, dy, shown)
	At(c, fs, "CENTER", l.col, l.row, 0, dy)
	c.names[l.text], fs.label = true, l -- (fs.label.areaID: the zone a hover lights, M3.4)
	local a = shown[l.text] and 1 or 0
	if fs.alpha ~= a then
		fs:SetAlpha(a)
		fs.alpha = a
	end
	if a == 0 then
		c.nfading = c.nfading + 1
		c.fading[c.nfading] = fs
	end
end

-- A zone name's half width (padded) and height at its size: measured once, at REF pt in its face on a
-- font string of ours never shown (every zone's box is placed, few drawn), then scaled (a face's
-- width and height go with its size).
local REF = 20
local ruler = CreateFrame("Frame")
ruler:Hide()
ruler = ruler:CreateFontString()
ruler:SetFont(TITLE, REF, "")
local function Measure(l, size)
	if not l.w then
		ruler:SetText(l.text)
		l.w, l.h = ruler:GetStringWidth() / REF, ruler:GetStringHeight() / REF
	end
	return l.w * size + PAD_X, l.h * size
end

UI.Labels = Engine.Layer("labels", 9, function(c, inst, zoom, c0, r0, c1, r1)
	local front = UI.Labels.front -- what shows now: its names don't fade in again
	local shown = front and front ~= c and front.names or NONE
	c.names, c.fading = c.names or {}, c.fading or {}
	for k in pairs(c.names) do c.names[k] = nil end
	c.nfading, c.fadeAt, nboxes = 0, nil, 0
	local list = List(inst)
	if zoom <= MAX_ZOOM then
		for i, l in ipairs(list.zones) do
			local size = SizeAt(l, ZONE_K, ZONE_MIN, ZONE_MAX, zoom)
			local w, h = Measure(l, size)
			local dy = Spot(c, l, zoom, w, h)
			if dy and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then
				Show(c, Font(c, l, TITLE, size, ZONE, Flags(size)), l, dy, shown)
			end
			if i % 16 == 0 then Yield() end
		end
	end
	local city = UI.Interiors.City()
	if zoom >= SUB_ZOOM and city then
		for _, l in ipairs(CityList(city, list)) do
			if zoom >= l.zoom and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then
				local fs = Font(c, l, BODY, SUB_SIZE, SUB, "")
				local dy = Spot(c, l, zoom, fs:GetStringWidth() / 2 + PAD_X, fs:GetStringHeight())
				if dy then Show(c, fs, l, dy, shown) else Unget(c, "label") end
			end
		end
	end
	if zoom >= SUB_ZOOM then
		for i, l in ipairs(list.subs) do
			if zoom >= l.zoom and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then
				local fs = Font(c, l, BODY, SUB_SIZE, SUB, "")
				local dy = Spot(c, l, zoom, fs:GetStringWidth() / 2 + PAD_X, fs:GetStringHeight())
				if dy then Show(c, fs, l, dy, shown) else Unget(c, "label") end
			end
			if i % 16 == 0 then Yield() end
		end
	end
end, function() return UI.Interiors.City() or false end, "move") -- (a city map shown or gone: laid out again)

-- Each frame while shown: the shown layout's new names fading in, from when it first shows.
Runtime.Step("ui", "map: labels fade", function()
	local c = UI.Labels.front
	if not (c and c.nfading > 0) then return end
	local now = GetTime()
	c.fadeAt = c.fadeAt or now
	local a = math.min(1, (now - c.fadeAt) / FADE_S)
	for i = 1, c.nfading do
		local fs = c.fading[i]
		fs:SetAlpha(a)
		fs.alpha = a
	end
	if a >= 1 then c.nfading = 0 end
end, { shownOnly = UI.Window.frame })

-- Zone and subzone names (Atlas.Labels, ranked offline: Data/Labels.lua): quiet, as on a printed map.
-- Zones in Morpheus, mixed case, one treatment for every zone: its size the zoom's alone (12 pt out at the
-- continent, growing to 22 as you close in; the same for a sliver of a zone as for the widest, so no name
-- outranks its neighbour), an outline over a soft dark shadow at every size, up to zoom 450; subzones quieter,
-- one look at every zoom: Friz Quadrata 9 pt, dimmer, the shadow alone, from zoom 120, 220 or 400 by their size. Zones first,
-- then subzones, each biggest first: a name tries its spot, just above, just below, and is skipped
-- if all three touch one placed. Every zone of the map is placed (its box: a name's spot doesn't
-- change on a pan), those over the view and its margin drawn (ui/Engine.lua); subzones are placed
-- near the view, around them, and again once it pans out of them; moved with
-- the zoom ("move"). A name the last layout didn't show fades in. While the big map shows a capital's city map
-- (ui/Interiors.lua), the areas named on its rooms (Atlas.City's labels: The Great Forge, the Apothecarium...)
-- are subzones too, placed first, but for a name the terrain's subzones have. Settings > Map > Names (ui/Feel.lua,
-- declared at the bottom): zone names and subzone names each on or off (the gear's rows too: ui/Menus.lua), the
-- label size, the zone names' opacity, the subzones' own size and opacity, and Zone levels: a zone's level range
-- ("Level 10-20") under its name, smaller, in Friz Quadrata, outlined as its name is and in its difficulty's colour
-- for your level (Model.ZoneColor: the quests' grey, green, yellow, orange and red, so the map shows where you'd
-- level); the client's range for its map (Model.levels), else the data's, its subzones' exploration levels
-- (Atlas.ZoneLevels); placed with its name as one box.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Atlas, Runtime, Engine = ns.Atlas, ns.Runtime, ns.UI.Engine
local Get, Unget, At, Yield = Engine.Get, Engine.Unget, Engine.At, Runtime.Yield

local TITLE, BODY = "Fonts\\MORPHEUS.TTF", GameFontNormal:GetFont() -- Morpheus for zones; Friz Quadrata
local ZONE, SUB = { 1, 0.89, 0.63, 0.95 }, { 0.91, 0.86, 0.77, 0.45 } -- subzones quieter
local ZONE_K, ZONE_MIN, ZONE_MAX = 0.34, 11.5, 22 -- a zone name's size: k * zoom, clamped (12 pt to zoom 35, 22 from 65)
local SUB_SIZE = 9 -- a subzone's, one size and look at every zoom: shadow only, no outline (quiet over legible)
local OUTLINE = "OUTLINE" -- a zone name's font flags, and its level line's: outlined at every size (legible over snow and lava alike, and one dress for every name: an outline at small sizes only would dress neighbours at one zoom two ways)
local MAX_ZOOM = 450 -- zone names hidden zoomed in past this
local SUB_ZOOM = 120 -- subzone names from here (weight >= 40), 220 (>= 15), else 400
local SHADOW = 0.85 -- the soft drop shadow's alpha, offset (1, -1)
local PAD_X, PAD_Y, GAP = 4, 2, 3 -- a name's clearance, and its spots' gap above and below
local FADE_S = 0.2 -- s: a new name's fade-in
local LEVEL_K, LEVEL_MIN = 0.55, 9 -- a zone's level line: this much of its name's size, at least this (pt: its colour has to read)
local LEVEL_ALPHA = 0.9 -- its alpha against the name's (a little quieter than the name)
local LEVEL_GAP = 0 -- px between the name and its level line (the fonts' own leading is enough)

-- The settings' label size ("labels.scale"), a factor on every name's size; the layer's rev moves with it, so the
-- names are laid out again at the new size (and, as the names', at a new size or opacity).
local scale, subScale, subSize, scaleRev = 1, 0.8, math.floor(SUB_SIZE * 0.8 + 0.5), 0 -- (Subzone size: 80% by default)
local zonesOn, subsOn, levelsOn = true, true, false -- Zone names, Subzone names, Zone levels (Settings > Map > Names)
local zone, sub = ZONE, SUB -- the names' colours (their alphas, the settings' "labels.alpha" and "labels.subAlpha", are each
-- name's own alpha: Font's fs.base)
local levelColor = { ZONE[1], ZONE[2], ZONE[3], ZONE[4] * LEVEL_ALPHA } -- a zone's level line while your level isn't known: its name's, quieter
local levelColors = {} -- a difficulty's colour (Model.ZoneColor's table) -> ours for a level line, at the opacity now

local function MakeFont(c)
	local fs = c:CreateFontString(nil, "OVERLAY")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, SHADOW)
	return fs
end

-- A zone name's size at a zoom, every zone's: k * zoom, clamped, in whole points (fewer SetFonts as the zoom moves).
local function ZoneSize(zoom)
	return math.floor(scale * math.max(ZONE_MIN, math.min(ZONE_MAX, ZONE_K * zoom)) + 0.5)
end

-- Per map, its names: zones and subzones (a town that is one included), each
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
			local l = { text = a.text, col = a.col, row = a.row, weight = w, rank = a.rank, areaID = a.areaID }
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
-- kept as placed; nil: none. w: half its width, padded; h: its height.
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
		-- The opacity is the font string's own alpha (Show, the fade), the text and its shadow both: the game
		-- doesn't keep a text colour's alpha under SetAlpha, so the settings' opacity was lost.
		fs:SetTextColor(color[1], color[2], color[3], 1)
		fs.color, fs.base = color, color[4]
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
	local key = l.key or l.text -- (a level line's own: "Level 10-20" is many zones')
	c.names[key], fs.label = true, l -- (fs.label.areaID: the zone a hover lights)
	local a = shown[key] and fs.base or 0
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

-- A zone's level line ("Level 10-20"), its own label (placed under the zone's name, lighting the same zone on a
-- hover), or nil: none known. The client's range once it gives one (kept then), else the data's.
local function LevelLabel(l)
	local lv = l.level
	if lv and lv.client then return lv end
	local lo, hi
	local area = l.areaID and Atlas.Area(l.areaID)
	local client = area and area.uiMap and Model.levels[area.uiMap]
	if client then
		lo, hi = client[1], client[2]
	elseif l.areaID then
		lo, hi = Atlas.ZoneLevels(l.areaID, Yield)
		if lo == hi then lo = nil end -- (the data's one level for all of it: a capital's or a sanctuary's, no range to level through)
	end
	if not (lo and lo > 0) then return nil end
	local text = "Level " .. (lo == hi and tostring(lo) or (lo .. "-" .. hi))
	if not (lv and lv.text == text) then
		lv = { text = text, key = "level:" .. l.text, col = l.col, row = l.row, areaID = l.areaID, line = true, lo = lo, hi = hi }
		l.level = lv
	end
	lv.client = client ~= nil
	return lv
end

-- A level line's colour: its zone's difficulty for your level (Model.ZoneColor: grey, green, yellow, orange or red, the
-- quests' own), so the map shows where you'd level; the name's, quieter, until your level is known. One table a
-- difficulty (Font compares the table), made again when the opacity changes.
local function LevelColor(lv)
	local m = Model.ZoneColor(lv.lo, lv.hi)
	if not m then return levelColor end
	local c = levelColors[m]
	if not c then
		c = { m[1], m[2], m[3], zone[4] * LEVEL_ALPHA }
		levelColors[m] = c
	end
	return c
end

-- A quest's name on the big map (ui/Quests.lua) in the subzone names' size and font, and a rev that moves with it.
function UI.LabelsSub() return BODY, subSize, scaleRev end

UI.Labels = Engine.Layer("labels", 9, function(c, inst, zoom, c0, r0, c1, r1)
	local front = UI.Labels.front -- what shows now: its names don't fade in again
	local shown = front and front ~= c and front.names or NONE
	c.names, c.fading = c.names or {}, c.fading or {}
	for k in pairs(c.names) do c.names[k] = nil end
	c.nfading, c.fadeAt, nboxes = 0, nil, 0
	if not UI.BigMap.big then return end -- (at the minimap's size, no names)
	local list = List(inst)
	if zonesOn and zoom <= MAX_ZOOM then
		local size = ZoneSize(zoom)
		for i, l in ipairs(list.zones) do
			local w, h = Measure(l, size)
			-- With its level line: one box, the name over the line (each centred on its own height).
			local lv = levelsOn and LevelLabel(l)
			local lsize = lv and math.max(LEVEL_MIN, math.floor(size * LEVEL_K + 0.5))
			local lh = lv and lsize * (l.h or 1) + LEVEL_GAP or 0
			local dy = Spot(c, l, zoom, w, h + lh)
			if dy and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then
				Show(c, Font(c, l, TITLE, size, zone, OUTLINE), l, dy - lh / 2, shown)
				if lv then Show(c, Font(c, lv, BODY, lsize, LevelColor(lv), OUTLINE), lv, dy + h / 2, shown) end
			end
			if i % 16 == 0 then Yield() end
		end
	end
	local city = UI.Interiors.City()
	if subsOn and zoom >= SUB_ZOOM and city then
		for _, l in ipairs(CityList(city, list)) do
			if zoom >= l.zoom and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then
				local fs = Font(c, l, BODY, subSize, sub, "")
				local dy = Spot(c, l, zoom, fs:GetStringWidth() / 2 + PAD_X, fs:GetStringHeight())
				if dy then Show(c, fs, l, dy, shown) else Unget(c, "label") end
			end
		end
	end
	if subsOn and zoom >= SUB_ZOOM then
		for i, l in ipairs(list.subs) do
			if zoom >= l.zoom and l.col >= c0 and l.col <= c1 and l.row >= r0 and l.row <= r1 then
				local fs = Font(c, l, BODY, subSize, sub, "")
				local dy = Spot(c, l, zoom, fs:GetStringWidth() / 2 + PAD_X, fs:GetStringHeight())
				if dy then Show(c, fs, l, dy, shown) else Unget(c, "label") end
			end
			if i % 16 == 0 then Yield() end
		end
	end
end, (function() -- (a city map shown or gone, the map grown or shrunk, the size or opacity, or your level with the level lines on, which colours them: laid out again; one value, which Engine compares)
	local city, seen, big, mine, n = nil, nil, nil, nil, 0
	return function()
		local c, lvl = UI.Interiors.City() or false, levelsOn and Model.you.level or nil
		if c ~= city or scaleRev ~= seen or UI.BigMap.big ~= big or lvl ~= mine then
			city, seen, big, mine, n = c, scaleRev, UI.BigMap.big, lvl, n + 1
		end
		return n
	end
end)(), "move")

local function SetScale(k)
	if scale == k then return end
	scale, subSize, scaleRev = k, math.floor(SUB_SIZE * k * subScale + 0.5), scaleRev + 1
end
-- The zone names' opacity; the subzone names' own size (a factor on the label size's) and opacity.
local function SetAlpha(a)
	if zone[4] == a then return end
	zone, scaleRev = { ZONE[1], ZONE[2], ZONE[3], a }, scaleRev + 1
	levelColor, levelColors = { ZONE[1], ZONE[2], ZONE[3], a * LEVEL_ALPHA }, {}
end
-- Zone names, Subzone names, Zone levels: each on or off, the names laid out again.
local function Switch(set)
	return function(on)
		on = on ~= false
		if set(on) then scaleRev = scaleRev + 1 end
	end
end
local SetZones = Switch(function(on) local was = zonesOn; zonesOn = on; return was ~= on end)
local SetSubs = Switch(function(on) local was = subsOn; subsOn = on; return was ~= on end)
local SetLevels = Switch(function(on) local was = levelsOn; levelsOn = on; return was ~= on end)
local function SetSubScale(k)
	if subScale == k then return end
	subScale, subSize, scaleRev = k, math.floor(SUB_SIZE * scale * k + 0.5), scaleRev + 1
end
local function SetSubAlpha(a)
	if sub[4] == a then return end
	sub, scaleRev = { SUB[1], SUB[2], SUB[3], a }, scaleRev + 1
end

-- Each frame while shown: the shown layout's new names fading in, from when it first shows.
Runtime.Step("ui", "map: labels fade", function()
	local c = UI.Labels.front
	if not (c and c.nfading > 0) then return end
	local now = GetTime()
	c.fadeAt = c.fadeAt or now
	local a = math.min(1, (now - c.fadeAt) / FADE_S)
	for i = 1, c.nfading do
		local fs = c.fading[i]
		fs:SetAlpha(a * fs.base)
		fs.alpha = a * fs.base
	end
	if a >= 1 then c.nfading = 0 end
end, { shownOnly = UI.Window.frame })

UI.Feel.Add("map", "Names", {
	{ key = "labels.zones", kind = "toggle", label = "Zone names", default = true, apply = SetZones,
		tip = "The names of zones (Elwynn Forest, Durotar) on the big map." },
	{ key = "labels.levels", kind = "toggle", label = "Zone levels", default = false, under = "labels.zones", apply = SetLevels,
		tip = "Each zone's level range in small text under its name, coloured as a quest of that level would be for you: grey, green, yellow, orange or red." },
	{ key = "labels.subs", kind = "toggle", label = "Subzone names", default = true, apply = SetSubs,
		tip = "The names of places within zones (Goldshire, Razor Hill) on the big map, zoomed in." },
	{ key = "labels.scale", kind = "slider", label = "Zone names", min = 0.7, max = 1.5, step = 0.1, pct = true, default = scale,
		apply = SetScale, tip = "The zone and subzone names' size. Open it (+) for the zone names' opacity." },
	{ key = "labels.alpha", kind = "slider", label = "Opacity", under = "labels.scale", min = 0.3, max = 1, step = 0.05, pct = true, default = ZONE[4],
		apply = SetAlpha, tip = "How solid the zone names are." },
	{ key = "labels.subScale", kind = "slider", label = "Subzone names", min = 0.7, max = 1.5, step = 0.1, pct = true, default = subScale,
		apply = SetSubScale, tip = "The subzone names' size, on top of the zone names'. Open it (+) for their opacity." },
	{ key = "labels.subAlpha", kind = "slider", label = "Opacity", under = "labels.subScale", min = 0.2, max = 1, step = 0.05, pct = true, default = SUB[4],
		apply = SetSubAlpha, tip = "How solid the subzone names are." },
})

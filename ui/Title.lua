-- The title band: a title, then a subtitle, left-aligned on one line just above the map
-- (below it, when the map is at the top of the screen), the gear and mode buttons at its
-- right end; no plate, like the minimap's own (Core.lua:177-226, 292-314). Clicking the title
-- opens the map picker (Core.lua:200-223); dragging it moves the window. Its text (Core.lua:1240-1320), 20 times a
-- second while shown: the pieces its settings page (Frame title) chooses, in their order, at rest (the small map, the
-- pointer off it) and on hover (the pointer over the map, and the big map); the first there is the title, the rest
-- the subtitle. The pieces:
--   Zone: the place it's about: hovering the map (big, or not on your map), the zone under the cursor (else the
--     map's name); on your map, your zone (your uiMap's name, else the client's); otherwise the zone last flown to on
--     this map (a zone's click, /mm zone), else the map's name
--   Subzone: the client's (the inn, inside it), on your map, while it isn't the zone's name
--   Coordinates: that zone's, the cursor's or yours
--   Tracked target: its name (ui/You.lua's Target), "here" inside its area; Distance to target: the yards to it,
--     outside it; both only while it's about you
--   Local time, Server time (Model.clock: Game reads them), as Blizzard's clock shows them (24 hours or 12) or as set,
--     led by the minimap's own day or night picture in its gold ring (Blizzard_Minimap's Diel.lua) rather than an
--     AM or PM (without the pictures, the AM or PM)
-- By default today's text: at rest the zone and subzone; on hover those, the coordinates and the target. Whatever is
-- chosen, off your map on the big map the hint to follow you again leads the subtitle; and with /mm debug, last
-- (Core.lua:1305-1313), grey: the tile under the cursor (else the view's centre), its FileDataID, the zoom and the
-- tile set's build.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Model = ns.Model
local Camera, Window, Chrome, Controls = UI.Camera, UI.Window, UI.Chrome, UI.Controls
local Maths = Atlas.Camera

local HEADER_ICON = 20 -- Core.lua:281
local ROOM = 3 * HEADER_ICON + 4 + 2 + 6 + 4 + 8 -- the buttons' share of the line (Core.lua:300): mode, gear, AddOns
local TOP_ROOM = 24 -- closer to the screen's top: the line goes below (Core.lua:305)
local EVERY = 0.05 -- s (Core.lua:1563)
local SEP = "  ·  " -- Core.lua:1244
local HINT = "|cff8a7f6e|A:UI-RefreshButton:12:12|a Back to you|r" -- Core.lua:1303 (the reset, ui/Controls.lua)
local COLOR, HOVER = { 1, 0.82, 0.25 }, { 1, 0.93, 0.6 } -- Core.lua:202
local DEBUG = "|cff777777%d_%d  %s  zoom %d  %s|r" -- Core.lua:1311
local FONT = GameFontNormal:GetFont()
local _, BUILD = Atlas.TileSet()

local Title = {}
UI.Title = Title

local frame, band = Window.frame, Chrome.band

local function Text(size, r, g, b)
	local fs = band:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size, "")
	fs:SetTextColor(r, g, b)
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	return fs
end
local title = Text(14, COLOR[1], COLOR[2], COLOR[3])
local subtitle = Text(11, 0.74, 0.68, 0.58)
Title.title, Title.subtitle = title, subtitle

-- The gold ring Blizzard_Minimap's Diel.lua puts round its day and night picture (UI-HUD-Minimap-Frame-Cycle: 42 px
-- round a 33 px picture at 1x), at our picture's size, one for each time shown (local, server): placed where its
-- picture falls in its line (Show), shown while the picture is there and fits (Fit).
-- Made prominent: a touch larger, and lit by a copy of itself added over it (RING_LIT).
local ICON, RING_SIZE, RING_LIT = 14, 19, 0.6
local rings, ringOn, ringX = {}, {}, {} -- the rings; each one's line (title or subtitle) and its picture's x there
for i = 1, 2 do
	local ring = band:CreateTexture(nil, "OVERLAY", nil, 6)
	ring:SetAtlas("UI-HUD-Minimap-Frame-Cycle")
	ring:SetSize(RING_SIZE, RING_SIZE)
	ring:Hide()
	local lit = band:CreateTexture(nil, "OVERLAY", nil, 7)
	lit:SetAtlas("UI-HUD-Minimap-Frame-Cycle")
	lit:SetBlendMode("ADD")
	lit:SetAlpha(RING_LIT)
	lit:SetAllPoints(ring)
	lit:Hide()
	ring.lit = lit
	rings[i] = ring
end
Title.rings = rings

-- Over the title, padded: a click opens the map picker (ui/Menus.lua); dragging it moves the window,
-- no pick after it.
local hit = CreateFrame("Button", nil, band)
hit:SetPoint("TOPLEFT", title, "TOPLEFT", -4, 3)
hit:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT", 4, -3)
hit:RegisterForDrag("LeftButton")
hit:SetScript("OnDragStart", Runtime.Wrap("map: move", function(self)
	self.dragged = true
	frame:StartMoving()
end))
hit:SetScript("OnDragStop", Runtime.Wrap("map: moved", function()
	frame:StopMovingOrSizing()
	Window.Moved()
end))
hit:SetScript("OnEnter", Runtime.Wrap("map: title hover", function() title:SetTextColor(HOVER[1], HOVER[2], HOVER[3]) end))
hit:SetScript("OnLeave", Runtime.Wrap("map: title left", function() title:SetTextColor(COLOR[1], COLOR[2], COLOR[3]) end))
-- (The picker is the client's own menu, MenuUtil, about twice the gear's rows: the frame's budget, as the gear's.)
hit:SetScript("OnClick", Runtime.Wrap("map: picker", function(self)
	if self.dragged then
		self.dragged = nil
		return
	end
	UI.Menus.Picker(self)
end, Runtime.FRAME_MS))
Title.hit = hit

-- Placed above the map, or below it near the screen's top, the mode button with it; each
-- part as wide as its text, within the line's room.
local function Fit()
	title:ClearAllPoints()
	subtitle:ClearAllPoints()
	local top, screenTop = frame:GetTop(), UIParent:GetTop()
	if not top then return end
	local room = frame:GetWidth() - 4 - ROOM
	local tw = math.min(title:GetUnboundedStringWidth(), room)
	title:SetWidth(tw)
	subtitle:SetWidth(math.max(1, math.min(subtitle:GetUnboundedStringWidth(), room - tw - 6)))
	local mode = Controls.mode
	mode:ClearAllPoints()
	if screenTop - top >= TOP_ROOM then
		title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 2, 4)
		mode:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -2, 3)
	else
		title:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 2, -4)
		mode:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -2, -3)
	end
	-- Share the title's baseline, nudged for the smaller descender.
	subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
	for i, ring in ipairs(rings) do
		ring:SetShown(ringOn[i] ~= nil and ringX[i] + ICON <= ringOn[i]:GetWidth())
		ring.lit:SetShown(ring:IsShown())
	end
end
Title.Fit = Fit
frame:HookScript("OnSizeChanged", Runtime.Wrap("map: title fit", Fit))

-- The pieces (the settings' lists' options), each with its format and how many values it takes. They go through
-- SetFormattedText: the client formats numbers without a Lua string (hovering the big map, coordinates change every
-- update: a string and its join each, 20 times a second). A form for each list and set of pieces there, made once.
local COORDS = "%.1f, %.1f" -- a tenth of a percent
local CLOCK = "%s%d:%02d%s" -- the day or night picture (and its room), hour, minute, AM or PM
local FMT = { zone = "%s", subzone = "%s", coords = COORDS, target = "|cffffd27f%s|r%s", -- Core.lua:1295-1299
	distance = "%d yd", time = CLOCK, server = CLOCK }
local N = { zone = 1, subzone = 1, coords = 2, target = 2, distance = 1, time = 4, server = 4 }
local PIECES = {
	{ "Zone", "zone" }, { "Subzone", "subzone" }, { "Coordinates", "coords" }, { "Tracked target", "target" },
	{ "Distance to target", "distance" }, { "Local time", "time" }, { "Server time", "server" },
}
local HINT_BIT, DEBUG_BIT = 2 ^ #PIECES, 2 ^ (#PIECES + 1)

-- The minimap's day and night pictures (Blizzard_Minimap's Diel.lua) inline before a time, a space after (the
-- ring's edge just past it); none without them. Over the picture, the gold ring Diel.lua puts round it (rings, above).
local DAY, NIGHT, RINGED
local function DayNight(day)
	if RINGED == nil then
		local function Inline(atlas)
			return C_Texture.GetAtlasInfo(atlas) and "|A:" .. atlas .. ":" .. ICON .. ":" .. ICON .. "|a " or nil
		end
		DAY, NIGHT = Inline("UI-HUD-Minimap-DayCycle"), Inline("UI-HUD-Minimap-NightCycle")
		RINGED = DAY ~= nil and NIGHT ~= nil
	end
	if not RINGED then return nil end
	return day and DAY or NIGHT
end

-- The two lists, each with which pieces it has, read again when a setting changes (Feel.rev).
local Feel = UI.Feel
local lists = { rev = -1 }
local forms = {} -- list -> its forms by key (bit i: its i-th piece is there; then the hint, the debug line)
local function Lists()
	if lists.rev == Feel.rev then return end
	lists.rev, forms = Feel.rev, {}
	for _, k in ipairs({ "rest", "hover" }) do
		local l = Feel.List("title." .. k)
		l.has = {}
		for _, p in ipairs(l) do l.has[p] = true end
		lists[k] = l
	end
end
local function Form(list, key)
	local byKey = forms[list] or {}
	forms[list] = byKey
	local f = byKey[key]
	if f then return f end
	f = { t = "", tn = 0, rings = {} } -- (a time's picture each: line, its line; pre, the subtitle's form before it, pn its values)
	local parts, sn = {}, 0
	if key % DEBUG_BIT >= HINT_BIT then parts[1] = HINT end
	for i, p in ipairs(list) do
		if key % 2 ^ i >= 2 ^ (i - 1) then
			local timed = p == "time" or p == "server"
			if f.t == "" then
				f.t, f.tn = FMT[p], N[p]
				if timed then f.rings[#f.rings + 1] = { line = title } end
			else
				if timed then
					f.rings[#f.rings + 1] = { line = subtitle, pre = table.concat(parts, SEP) .. (parts[1] and SEP or ""), pn = sn }
				end
				parts[#parts + 1] = FMT[p]
				sn = sn + N[p]
			end
		end
	end
	if key >= DEBUG_BIT then parts[#parts + 1] = "%s" end
	f.s = table.concat(parts, SEP)
	byKey[key] = f
	return f
end

-- A clock's four values from n + 1: the day or night picture ("" without it), hour, minute, and "" (the picture says
-- it) or, without the picture, " AM" / " PM" at 12 hours (12 at noon and midnight).
local function Clock(out, n, h, m, military, day)
	local form, pic = Feel.Get("title.clock"), DayNight(day)
	local twelve = not (form == "24" or form == "game" and military)
	out[n + 1], out[n + 2], out[n + 3] = pic or "", twelve and ((h % 12 == 0) and 12 or h % 12) or h, m
	out[n + 4] = (twelve and not pic) and (h < 12 and " AM" or " PM") or ""
end

-- Shown from v, this update's values (zone, subzone, nx, ny: tenths of a percent, tt, here, yd, clock, hint,
-- debug), in the list's order: set only when they differ from what's shown (compared value by value, no table made).
local v, cur, shown = {}, {}, {}
local shownList, shownKey, shownN
local function Present(p)
	if p == "zone" then return v.zone elseif p == "subzone" then return v.subzone elseif p == "coords" then return v.nx
	elseif p == "target" then return v.tt elseif p == "distance" then return v.yd else return v.clock end
end
local function Put(p, n)
	if p == "coords" then
		cur[n + 1], cur[n + 2] = v.nx / 10, v.ny / 10
	elseif p == "target" then
		cur[n + 1], cur[n + 2] = v.tt, v.here and " here" or ""
	elseif p == "time" then
		Clock(cur, n, v.clock.h, v.clock.m, v.clock.military, v.clock.day)
	elseif p == "server" then
		Clock(cur, n, v.clock.sh, v.clock.sm, v.clock.military, v.clock.day)
	else
		cur[n + 1] = p == "zone" and v.zone or p == "subzone" and v.subzone or v.yd
	end
	return n + N[p]
end
local function Show(list)
	local key, n = 0, 0
	for i, p in ipairs(list) do
		if Present(p) then key, n = key + 2 ^ (i - 1), Put(p, n) end
	end
	if v.hint then key = key + HINT_BIT end
	if v.debug then
		key, n = key + DEBUG_BIT, n + 1
		cur[n] = v.debug
	end
	if list == shownList and key == shownKey and n == shownN then
		local same = true
		for i = 1, n do
			if cur[i] ~= shown[i] then same = false end
		end
		if same then return end
	end
	shownList, shownKey, shownN = list, key, n
	cur, shown = shown, cur
	local f = Form(list, key)
	-- Each ring's place: the width of the subtitle's text before its picture (the title's picture is its first).
	for i, ring in ipairs(rings) do
		local fr = RINGED and f.rings[i]
		ringOn[i], ringX[i] = fr and fr.line or nil, 0
		if fr and fr.pre and fr.pre ~= "" then
			subtitle:SetFormattedText(fr.pre, unpack(shown, f.tn + 1, f.tn + fr.pn))
			ringX[i] = subtitle:GetUnboundedStringWidth()
		end
		if fr then
			ring:ClearAllPoints()
			ring:SetPoint("CENTER", fr.line, "LEFT", ringX[i] + ICON / 2, 0)
		end
	end
	if f.t == "" then title:SetText("") else title:SetFormattedText(f.t, unpack(shown, 1, f.tn)) end
	if f.s == "" then subtitle:SetText("") else subtitle:SetFormattedText(f.s, unpack(shown, f.tn + 1, n)) end
	Fit()
end

-- The map's name: Atlas's (the tile set's) or the instance's number (Core.lua:1262).
local names = {}
local function MapName(inst)
	local n = names[inst]
	if not n then
		for _, m in ipairs(Atlas.Maps()) do
			if m.inst == inst then n = m.name end
		end
		n = n or ("Instance " .. tostring(inst))
		names[inst] = n
	end
	return n
end

-- The zone at (a, b): its uiMap and name, worked out again only when the area under it changes
-- (a walk or a hover makes no table each update).
local at = {}
local function ZoneAt(inst, a, b)
	local id = Atlas.AreaAt(inst, a, b)
	if id ~= at.area or inst ~= at.inst then
		local z = Atlas.ZoneAt(inst, a, b)
		at.area, at.inst, at.mapID, at.name = id, inst, z and z.mapID, z and z.name
	end
	return at.mapID and at
end

-- The debug line (Core.lua:1305-1313): the tile under the cursor (hovering), else the view's centre.
local function Debug(inst, hovering)
	local cam, c, r = Camera.cam, nil, nil
	if hovering then
		local w, h = Window.Size()
		c, r = Maths.ScreenToTile(cam, w, h, Window.Cursor())
	else
		c, r = cam.cx, cam.cy
	end
	local col, row = math.floor(c), math.floor(r)
	local tiles = Atlas.Tiles(inst)
	local fdid = tiles and col >= 0 and col < 64 and row >= 0 and row < 64 and tiles[col * 64 + row]
	return string.format(DEBUG, col, row, fdid and tostring(fdid) or "-", cam.zoom, tostring(BUILD))
end

-- What it was last worked out from, so a still map works nothing out (and allocates nothing; the debug
-- line, on, each update).
local last = {}

local function Update()
	local inst, you, big, debug = Camera.inst, Model.you, UI.BigMap.big, UI.saved.debug
	local hovering = Window.view:IsMouseOver()
	local onMap = you.inst == inst
	local here = onMap and not big -- small, on your map: always where you are
	Lists()
	local list = (hovering or big) and lists.hover or lists.rest
	local has = list.has
	local a, b -- the tile it names: under the cursor, or yours
	if hovering and not here then
		local w, h = Window.Size()
		a, b = Maths.ScreenToTile(Camera.cam, w, h, Window.Cursor())
	elseif onMap then
		a, b = you.col, you.row
	end
	local tt, yd -- the target, while it's about you (Core.lua:1294)
	if onMap and not (hovering and big) and (has.target or has.distance) then
		tt, yd = UI.You.Target()
		if not has.distance then yd = yd and true end -- (no yards shown: none to redraw for)
	end
	local clock = (has.time or has.server) and Model.clock or nil
	local l = last
	if not debug and not l.debug and l.inst == inst and l.big == big and l.hovering == hovering and l.a == a
		and l.b == b and l.uiMap == you.uiMap and l.subzone == you.subzone and l.tt == tt and l.yd == yd
		and l.zone == Camera.zone and l.list == list and l.clock == clock and l.rev == Feel.rev then return end
	l.inst, l.big, l.hovering, l.a, l.b, l.uiMap, l.subzone, l.tt, l.yd, l.zone, l.debug = inst, big, hovering, a, b,
		you.uiMap, you.subzone, tt, yd, Camera.zone, debug
	l.list, l.clock, l.rev = list, clock, Feel.rev
	v.debug = debug and Debug(inst, hovering) or nil
	v.tt, v.here, v.yd, v.clock = tt, tt and not yd, type(yd) == "number" and yd or nil, clock
	v.subzone, v.hint = nil, nil
	local x, y
	if hovering and not here then
		local z = ZoneAt(inst, a, b)
		if z then x, y = Atlas.TileToMap(z.mapID, a, b) end
		v.zone = x and z.name or MapName(inst)
	elseif onMap then
		-- Your uiMap's name (the client's best map for you), else the client's zone, else the
		-- zone you're in (Core.lua:1278-1291).
		local map = you.uiMap and Atlas.UiMap(you.uiMap)
		local zone = not map and a and ZoneAt(inst, a, b)
		local mapID = map and map.id or zone and zone.mapID
		local name = map and map.name or you.zone or zone and zone.name or MapName(inst)
		if a and mapID and has.coords then x, y = Atlas.TileToMap(mapID, a, b) end
		v.zone, v.subzone = name, you.subzone ~= name and you.subzone or nil
	else
		v.zone, v.hint = Camera.zone or MapName(inst), big
	end
	v.nx, v.ny = x and math.floor(x * 1000 + 0.5), y and math.floor(y * 1000 + 0.5)
	Show(list)
end

-- Its page in the settings (ui/Feel.lua): what it says at rest and on hover, each the pieces chosen, in order (the
-- first the title); the clock's form while a time is chosen.
local function Timed()
	Lists()
	local r, h = lists.rest.has, lists.hover.has
	return (r.time or r.server or h.time or h.server) == true
end
Feel.Page({ key = "title", title = "Frame title", icon = "Interface\\Icons\\INV_Scroll_03", order = 25, sections = { "Format" },
	tip = "What the title above the map says: at rest, and with the pointer over the map." })
Feel.Add("title", nil, {
	{ key = "title.rest", kind = "list", ordered = true, label = "At rest", options = PIECES, default = "time,zone",
		tip = "What the title says while the pointer isn't over the small map, in this order: the first is the title, the rest follow it, smaller." },
	{ key = "title.hover", kind = "list", ordered = true, label = "On hover", options = PIECES,
		default = "coords,zone",
		tip = "What it says with the pointer over the map, and on the big map. Over the big map, or a map you're not on, the zone and coordinates are the ones under the pointer." },
})
Feel.Add("title", "Format", {
	{ key = "title.clock", kind = "select", label = "Clock", default = "game", when = Timed,
		options = { { "As Blizzard's clock", "game" }, { "24-hour", "24" }, { "12-hour", "12" } },
		tip = "How the times show: as Blizzard's clock is set (its 24-hour box), or always 24-hour or 12-hour." },
})

-- /mm debug (Core.lua:1746-1748): the gear's Advanced runs it (GearMenu.lua:35).
function Title.Debug()
	UI.saved.debug = not UI.saved.debug
	UI.Print("debug info " .. (UI.saved.debug and "on" or "off"))
end
ns.Game.Command({ kind = "slash", name = "debug", fn = Title.Debug,
	help = "the tile, its FileDataID and the zoom in the title" })

local since = EVERY
Runtime.Step("ui", "map: title", function(elapsed)
	since = since + elapsed
	if since < EVERY then return end
	since = 0
	Update()
end, { shownOnly = frame })

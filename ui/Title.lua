-- The title band: the zone, then a subtitle, left-aligned on one line just above the map
-- (below it, when the map is at the top of the screen), the gear and mode buttons at its
-- right end; no plate, like the minimap's own (Core.lua:177-226, 292-314). Dragging the
-- title moves the window. Its text (Core.lua:1240-1320), 20 times a second while shown:
--   hovering the map (big, or not on your map): the zone under the cursor and its coordinates
--   on your map: your zone (your uiMap's name, else the client's), the client's subzone (the
--     inn, inside it); coordinates and the target (ui/You.lua) while big or hovered
--   otherwise: the map's name; big: the hint to follow you again

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Model = ns.Model
local Camera, Window, Chrome, Controls = UI.Camera, UI.Window, UI.Chrome, UI.Controls
local Maths = Atlas.Camera

local HEADER_ICON = 20 -- Core.lua:281
local ROOM = 2 * HEADER_ICON + 4 + 6 + 8 -- the buttons' share of the line (Core.lua:300)
local TOP_ROOM = 24 -- closer to the screen's top: the line goes below (Core.lua:305)
local EVERY = 0.05 -- s (Core.lua:1563)
local SEP = "  ·  " -- Core.lua:1244
local HINT = "|cff8a7f6eright-click: Follow me|r" -- Core.lua:1303
local COLOR, HOVER = { 1, 0.82, 0.25 }, { 1, 0.93, 0.6 } -- Core.lua:202
local FONT = GameFontNormal:GetFont()

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

-- Over the title, padded: dragging it moves the window (the map picker's click: M3.4).
local hit = CreateFrame("Button", nil, band)
hit:SetPoint("TOPLEFT", title, "TOPLEFT", -4, 3)
hit:SetPoint("BOTTOMRIGHT", title, "BOTTOMRIGHT", 4, -3)
hit:RegisterForDrag("LeftButton")
hit:SetScript("OnDragStart", Runtime.Wrap("map: move", function() frame:StartMoving() end))
hit:SetScript("OnDragStop", Runtime.Wrap("map: moved", function()
	frame:StopMovingOrSizing()
	Window.Moved()
end))
hit:SetScript("OnEnter", Runtime.Wrap("map: title hover", function() title:SetTextColor(HOVER[1], HOVER[2], HOVER[3]) end))
hit:SetScript("OnLeave", Runtime.Wrap("map: title left", function() title:SetTextColor(COLOR[1], COLOR[2], COLOR[3]) end))
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
end
Title.Fit = Fit
frame:HookScript("OnSizeChanged", Runtime.Wrap("map: title fit", Fit))

-- The subtitle's forms: a subzone, coordinates ("x, y" at a tenth of a percent), the target ("<title>
-- N yd", "<title> here": Core.lua:1294-1300), each there or not, joined; or the hint. Coordinates and
-- yards go through SetFormattedText: the client formats them without a Lua string (hovering the big map,
-- they change every update: a string and its join each, 20 times a second).
local COORDS = "%.1f, %.1f"
local TARGET, HERE = "|cffffd27f%s|r %d yd", "|cffffd27f%s|r here" -- Core.lua:1295-1299
local forms, args = {}, {} -- a form by its parts (a subzone 1, coordinates 2, a target 4, here 8), made once
local function Form(k)
	local f = forms[k]
	if not f then
		local parts = {}
		if k % 2 == 1 then parts[#parts + 1] = "%s" end
		if k % 4 >= 2 then parts[#parts + 1] = COORDS end
		if k >= 8 then parts[#parts + 1] = HERE elseif k >= 4 then parts[#parts + 1] = TARGET end
		f = table.concat(parts, SEP)
		forms[k] = f
	end
	return f
end
local shown = {} -- what it shows: name, sub, nx, ny (tenths of a percent: nil, none), hint, the target's tt, yd
local function Show(name, sub, x, y, hint, tt, yd)
	local nx, ny = x and math.floor(x * 1000 + 0.5), y and math.floor(y * 1000 + 0.5)
	local s = shown
	if name == s.name and sub == s.sub and nx == s.nx and ny == s.ny and hint == s.hint and tt == s.tt
		and yd == s.yd then return end
	if name ~= s.name then title:SetText(name) end
	s.name, s.sub, s.nx, s.ny, s.hint, s.tt, s.yd = name, sub, nx, ny, hint, tt, yd
	if nx or tt then
		local k, n = 0, 0
		if sub then
			k, n = 1, 1
			args[1] = sub
		end
		if nx then
			args[n + 1], args[n + 2] = nx / 10, ny / 10
			k, n = k + 2, n + 2
		end
		if tt then
			args[n + 1], args[n + 2] = tt, yd
			k, n = k + (yd and 4 or 8), n + (yd and 2 or 1)
		end
		subtitle:SetFormattedText(Form(k), unpack(args, 1, n))
	else
		subtitle:SetText(hint and HINT or sub or "")
	end
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

-- What it was last worked out from, so a still map works nothing out (and allocates nothing).
local last = {}

local function Update()
	local inst, you, big = Camera.inst, Model.you, UI.BigMap.big
	local hovering = Window.view:IsMouseOver()
	local onMap = you.inst == inst
	local here = onMap and not big -- small, on your map: always where you are
	local a, b -- the tile it names: under the cursor, or yours
	if hovering and not here then
		local w, h = Window.Size()
		a, b = Maths.ScreenToTile(Camera.cam, w, h, Window.Cursor())
	elseif onMap then
		a, b = you.col, you.row
	end
	local tt, yd -- the target: big, or small and hovered (Core.lua:1294)
	if onMap and (big and not hovering or hovering and not big) then tt, yd = UI.You.Target() end
	local l = last
	if l.inst == inst and l.big == big and l.hovering == hovering and l.a == a and l.b == b and l.uiMap == you.uiMap
		and l.subzone == you.subzone and l.tt == tt and l.yd == yd then return end
	l.inst, l.big, l.hovering, l.a, l.b, l.uiMap, l.subzone, l.tt, l.yd = inst, big, hovering, a, b, you.uiMap,
		you.subzone, tt, yd
	if hovering and not here then
		local z = ZoneAt(inst, a, b)
		local x, y
		if z then x, y = Atlas.TileToMap(z.mapID, a, b) end
		if x then Show(z.name, nil, x, y) else Show(MapName(inst)) end
	elseif onMap then
		-- Your uiMap's name (the client's best map for you), else the client's zone, else the
		-- zone you're in (Core.lua:1278-1291).
		local map = you.uiMap and Atlas.UiMap(you.uiMap)
		local zone = not map and a and ZoneAt(inst, a, b)
		local mapID = map and map.id or zone and zone.mapID
		local name = map and map.name or you.zone or zone and zone.name or MapName(inst)
		local x, y
		if a and mapID and (big or hovering) then x, y = Atlas.TileToMap(mapID, a, b) end
		Show(name, you.subzone ~= name and you.subzone or nil, x, y, nil, tt, yd)
	else
		Show(MapName(inst), nil, nil, nil, big)
	end
end

local since = EVERY
Runtime.Step("ui", "map: title", function(elapsed)
	since = since + elapsed
	if since < EVERY then return end
	since = 0
	Update()
end, { shownOnly = frame })

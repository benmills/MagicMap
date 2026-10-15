-- The title band: the zone, then a subtitle, left-aligned on one line just above the map
-- (below it, when the map is at the top of the screen), the gear and mode buttons at its
-- right end; no plate, like the minimap's own (Core.lua:177-226, 292-314). Dragging the
-- title moves the window. Its text (Core.lua:1240-1320), 20 times a second while shown:
--   hovering the map (big, or not on your map): the zone under the cursor and its coordinates
--   on your map: your zone (your uiMap's name), subzone; coordinates while big or hovered
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

local function Coords(x, y) return string.format("%.1f, %.1f", x * 100, y * 100) end

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

-- What it was last worked out from, so a still map works nothing out (and allocates nothing).
local last = {}
local parts, shownName, shownSub = {}, nil, nil

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
	local l = last
	if l.inst == inst and l.big == big and l.hovering == hovering and l.a == a and l.b == b and l.uiMap == you.uiMap then return end
	l.inst, l.big, l.hovering, l.a, l.b, l.uiMap = inst, big, hovering, a, b, you.uiMap
	local name
	wipe(parts)
	if hovering and not here then
		local z = Atlas.ZoneAt(inst, a, b)
		if z then
			name = z.name
			parts[#parts + 1] = Coords(z.x, z.y)
		else
			name = MapName(inst)
		end
	elseif onMap then
		-- Your uiMap's name (the client's best map for you), else the zone you're in.
		local zone = a and Atlas.ZoneAt(inst, a, b)
		local mapID = you.uiMap or (zone and zone.mapID)
		local map = mapID and Atlas.UiMap(mapID)
		name = map and map.name or zone and zone.name or MapName(inst)
		local area = zone and Atlas.Area(zone.area)
		if area and area.id ~= area.zone and area.name ~= name then parts[#parts + 1] = area.name end
		if a and map and (big or hovering) then
			local x, y = Atlas.TileToMap(mapID, a, b)
			if x then parts[#parts + 1] = Coords(x, y) end
		end
	else
		name = MapName(inst)
		if big then parts[#parts + 1] = HINT end
	end
	local sub = table.concat(parts, SEP)
	if name ~= shownName or sub ~= shownSub then
		shownName, shownSub = name, sub
		title:SetText(name)
		subtitle:SetText(sub)
		Fit()
	end
end

local since = EVERY
Runtime.Step("ui", "map: title", function(elapsed)
	since = since + elapsed
	if since < EVERY then return end
	since = 0
	Update()
end, { shownOnly = frame })

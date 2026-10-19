-- Zones on the map, and what's at a spot (Core.lua:1247-1416, 1721-1734; Layers.lua:1786-1811,
-- 1996-2010, 2064-2122, 2280-2316; ZoneInfo.lua):
--   Hover: while more than one zone (its heart, weight 30 or more) is in view, the zone under the cursor
--     (big, or off your map: as the title names it) lights up, its name brighter, its border drawn over
--     the borders' on their shown canvas; a click there flies to it (fit 0.92), following off. A click's
--     turn (ui/Window.lua): a pin, then a quest's area while zone clicks aren't on offer, then the zone.
--   Ctrl-click: a waypoint there; Ctrl-right-click: none; Shift-click: its /way line in the chat box
--     (the waypoint and way Commands: Game's). Taken on the press, so the map doesn't pan.
--   At(col, row): the big map's right-click menu leads with it (ui/Menus.lua): the zone, its subzones and
--     coordinates, its levels against yours, how far and which way from you, at most 2 quests whose areas
--     hold it. Explored and landmark lines: M4.4.
--   /mma zone <name>: fly to the first zone whose name holds it, the map shown's first.
--   The title's click: the map picker (ui/Menus.lua), as the spike's title button (Core.lua:200-223).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window, Motion, Engine = UI.Camera, UI.Window, UI.Motion, UI.Engine
local Maths = Atlas.Camera
local Command = ns.Game.Command
local Yield = Runtime.Yield

local EVERY = 0.05 -- s: the hover's look, as the title's (Core.lua:1563)
local MIN_WEIGHT = 30 -- a zone's land chunks to count as in view (Layers.lua:2006)
local LABEL, LABEL_HOVER = { 1, 0.9, 0.7, 0.75 }, { 1, 1, 0.9, 1 } -- Layers.lua:1420-1421
local LIT = { 1, 0.84, 0.4, 0.95 } -- the hovered zone's border (Layers.lua:1799)
-- Its dead ends as the borders' (ui/Borders.lua; Layers.lua:1531-1577).
local FADE_PX, DASH_PX, GAP_PX, DASHES, MIN_FADE, MIN_SEG_PX = 36, 5, 4, 4, 0.08, 2.5
local TILE_YARDS = Atlas.TILE_YARDS
local RADIUS = 110 / 533.33 -- tiles: a quest's estimated area (Layers.lua:78)
local MAX_QUESTS = 2 -- ZoneInfo.lua:13
local HERE_YD = 15 -- closer: "You're here" (ZoneInfo.lua:115)
local GOLD, WHITE, GREY, DIM = "|cffffd100", "|cffffffff", "|cffa8a8a8", "|cff808080" -- ZoneInfo.lua:16
local SEP = DIM .. "  ·  |r"
local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local OCTANT = math.pi / 4
-- /mma zone alone: the spike's usage line (Core.lua:1752).
local USAGE = "/mma [toggle] | follow | map <id|name> | zone <name> | icon | tiles | tint | layers | landmarks | blips"
	.. " | indoor | perf | debug | reset"
local NONE = {}

local ZoneInfo = {}
UI.ZoneInfo = ZoneInfo

-- The tile under the cursor on the map shown (Core.lua:1047-1051).
function ZoneInfo.CursorTile()
	local w, h = Window.Size()
	return Maths.ScreenToTile(Camera.cam, w, h, Window.Cursor())
end

---------------------------------------------------------------------------
-- Hover (Core.lua:1264-1327): the zone under the cursor, 20 times a second
---------------------------------------------------------------------------

-- The zone at (col, row): Atlas's, worked out again only when the area under it changes (a hover
-- makes no table each update).
local at = {}
local function ZoneAt(inst, col, row)
	local id = Atlas.AreaAt(inst, col, row)
	if id ~= at.area or inst ~= at.inst then at.area, at.inst, at.z = id, inst, Atlas.ZoneAt(inst, col, row) end
	return at.z
end

-- How many zones meaningfully share the view: those whose heart (their label's anchor, Data/Borders.lua)
-- is on it (Layers.lua:1996-2010). Worked out again when the view moves.
local inView = {}
local function ZonesInView(inst)
	local cam, w, h = Camera.cam, Window.Size()
	local v = inView
	if v.inst == inst and v.cx == cam.cx and v.cy == cam.cy and v.zoom == cam.zoom and v.w == w and v.h == h then
		return v.n
	end
	local c0, r0 = Maths.ScreenToTile(cam, w, h, 0, 0)
	local c1, r1 = Maths.ScreenToTile(cam, w, h, w, h)
	local n, b = 0, Atlas.Borders(inst)
	for _, l in ipairs(b and b.labels or NONE) do -- { areaID, col, row, weight, kind (1: a zone) }
		if l[5] == 1 and l[4] >= MIN_WEIGHT and l[2] >= c0 and l[2] <= c1 and l[3] >= r0 and l[3] <= r1 then n = n + 1 end
	end
	v.inst, v.cx, v.cy, v.zoom, v.w, v.h, v.n = inst, cam.cx, cam.cy, cam.zoom, w, h, n
	return n
end

-- zone: the hovered zone lit (its areaID), while zone clicks are on offer; map: its uiMap, a click's.
local hover = {}
local function Hover()
	local inst, z = Camera.inst, nil
	-- At the minimap's size on your map it always names where you are: no zone to click (Core.lua:1269).
	if Window.view:IsMouseOver() and (UI.BigMap.big or Model.you.inst ~= inst) then
		z = ZoneAt(inst, ZoneInfo.CursorTile())
	end
	local on = z and not Motion.Dragging() and ZonesInView(inst) > 1
	hover.zone, hover.map = on and z.zone or nil, on and z.mapID or nil
end

---------------------------------------------------------------------------
-- Its look (Layers.lua:1786-1811): its name brighter, its border over the borders', on the canvases shown
---------------------------------------------------------------------------

-- Its name on the labels' shown canvas (ui/Labels.lua: each name's font string carries its label, fs.label;
-- the next layout there sets its colour back, fs.color).
local named = {} -- zone, c: the canvas; fs: the name lit
local function Name(zone)
	local c = UI.Labels.on and UI.Labels.front or nil
	if zone == named.zone and c == named.c then return end
	local fs = named.fs
	if fs and fs.color == LABEL_HOVER then
		fs:SetTextColor(LABEL[1], LABEL[2], LABEL[3], LABEL[4])
		fs.color = LABEL
	end
	named.zone, named.c, named.fs = zone, c, nil
	local p = zone and c and c.pools.label
	for i = 1, p and p.n or 0 do
		fs = p[i]
		if fs.label.areaID == zone then
			fs:SetTextColor(LABEL_HOVER[1], LABEL_HOVER[2], LABEL_HOVER[3], LABEL_HOVER[4])
			fs.color, named.fs = LABEL_HOVER, fs
		end
	end
end

-- Its border: Lines of its own on the borders' shown canvas, over theirs (Layers.lua:235: the spike's
-- highlight pool), thick clamp(z / 100, 1.6, 2.4) at that canvas's zoom, clipped to its layout's region as
-- theirs; scaled, dimmed and crossfaded with it. Drawn by a job a few a frame, once the map's layouts are
-- done (Engine.pending: their frames are full); parked off the canvases when not drawn, as Engine's.
local lit = {} -- zone, c: what it's drawn for (c nil: none)
local BUDGET = 1 -- ms a frame
local park = CreateFrame("Frame", nil, Window.view)
park:Hide()
local lines = { n = 0, out = 0 } -- 1..n this drawing's; 1..out on lit.c, the rest parked

local function Park(from)
	for i = from, lines.out do
		local l = lines[i]
		if l.on ~= park then
			l:SetParent(park)
			l.on = park
		end
	end
	lines.out = math.min(lines.out, from - 1)
end

local function MakeLine()
	local l = park:CreateLine(nil, "ARTWORK", nil, 3)
	l:SetSnapToPixelGrid(false)
	l:SetTexelSnappingBias(0)
	l.on = park
	return l
end

local box, thick = { 0, 0, 0, 0 }, 1 -- the canvas's region in its px; this drawing's width

-- A segment clipped to the box (Liang-Barsky, as ui/Borders.lua), or nil: none of it inside.
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
			elseif r < t0 then
				return nil
			elseif r < t1 then
				t1 = r
			end
		end
	end
	return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
end

-- A piece f of the way faded in (Layers.lua:1568-1577): the next Line, on the canvas.
local function Piece(c, x1, y1, x2, y2, f)
	x1, y1, x2, y2 = Clip(x1, y1, x2, y2)
	if not x1 then return end
	local n = lines.n + 1
	local l = lines[n] or MakeLine()
	lines[n], lines.n = l, n
	if l.on ~= c then
		l:SetParent(c)
		l.on = c
	end
	if n > lines.out then lines.out = n end
	local a, w = LIT[4] * f, thick * (0.6 + 0.4 * f)
	if l.a ~= a then
		l:SetColorTexture(LIT[1], LIT[2], LIT[3], a)
		l.a = a
	end
	if l.w ~= w then
		l:SetThickness(w)
		l.w = w
	end
	l:SetStartPoint("TOPLEFT", c, x1, -y1)
	l:SetEndPoint("TOPLEFT", c, x2, -y2)
	Yield()
end

-- A polyline's points in canvas px, those kept, and the length along it to each: scratch, reused.
local xs, ys, along = {}, {}, {}
local function Points(c, l)
	local n, last, min2, zoom = 0, #l - 1, MIN_SEG_PX * MIN_SEG_PX, c.zoom
	for i = 5, last, 2 do
		local x, y = (l[i] - c.ox) * zoom, (l[i + 1] - c.oy) * zoom
		if n == 0 or i >= last - 1 or (x - xs[n]) ^ 2 + (y - ys[n]) ^ 2 >= min2 then
			n = n + 1
			xs[n], ys[n] = x, y
			along[n] = n == 1 and 0 or along[n - 1] + math.sqrt((x - xs[n - 1]) ^ 2 + (y - ys[n - 1]) ^ 2)
		end
	end
	return n
end

local function PointAt(n, s)
	local k = 1
	while k < n - 1 and along[k + 1] < s do k = k + 1 end
	local d = along[k + 1] - along[k]
	local u = d > 0 and (s - along[k]) / d or 0 -- /: never 0 (checked)
	return xs[k] + (xs[k + 1] - xs[k]) * u, ys[k] + (ys[k + 1] - ys[k]) * u
end

-- A line of Data/Borders.lua ({ areaA, areaB, fadeStart, fadeEnd, x1, y1, ... }) as ui/Borders.lua draws a
-- zone's: solid, each fading end in at most DASHES dashes of falling width and alpha.
local function Polyline(c, l)
	local n = Points(c, l)
	if n < 2 then return end
	local total = along[n]
	local fade = math.min(FADE_PX, total / 2)
	local fs, fe = l[3] > 0, l[4] > 0
	local s0, s1 = fs and fade or 0, total - (fe and fade or 0)
	for k = 1, n - 1 do
		local a0, a1 = along[k], along[k + 1]
		if a1 > s0 and a0 < s1 and a1 > a0 then
			local d, x, y = a1 - a0, xs[k], ys[k]
			local u0, u1 = math.max(0, (s0 - a0) / d), math.min(1, (s1 - a0) / d) -- /: never 0 (a1 > a0)
			local dx, dy = xs[k + 1] - x, ys[k + 1] - y
			Piece(c, x + dx * u0, y + dy * u0, x + dx * u1, y + dy * u1, 1)
		end
	end
	for e = 1, 2 do
		local fromEnd = e == 2
		if fade > 0 and (fromEnd and fe or not fromEnd and fs) then
			for j = 0, DASHES - 1 do
				local d0 = j * (DASH_PX + GAP_PX)
				if d0 >= fade then break end
				local d1 = math.min(fade, d0 + DASH_PX)
				local f = (d0 + d1) / 2 / fade -- /: never 0 (fade > d0 >= 0)
				if f > MIN_FADE then
					local x1, y1 = PointAt(n, fromEnd and total - d0 or d0)
					local x2, y2 = PointAt(n, fromEnd and total - d1 or d1)
					Piece(c, x1, y1, x2, y2, f)
				end
			end
		end
	end
end

local function Light()
	local c, zone = lit.c, lit.zone
	local list = zone and Atlas.BorderLines(c.inst, c.zoom)
	lines.n = 0
	if list then
		local z, r = c.zoom, c.region
		box[1], box[2], box[3], box[4] = (r[1] - c.ox) * z, (r[2] - c.oy) * z, (r[3] - c.ox) * z, (r[4] - c.oy) * z
		thick = math.max(1.6, math.min(2.4, z / 100)) -- Layers.lua:1794
		for _, l in ipairs(list) do
			if l[1] == zone or l[2] == zone then Polyline(c, l) end
		end
	end
	Park(lines.n + 1)
end
local job = Runtime.Worker("map: zone border", function()
	while true do
		Light()
		Runtime.Idle()
	end
end, BUDGET)

local function Border(zone)
	local c = UI.Borders.on and UI.Borders.front or nil
	if zone ~= lit.zone or c ~= lit.c then
		if c ~= lit.c then Park(1) end
		lit.zone, lit.c = zone, c
		Runtime.Cancel(job)
		if c then Runtime.Wake(job) end
	end
	job.budget = Engine.pending and 0 or BUDGET -- (0: it waits its turn, queued)
end

local since = EVERY
Runtime.Step("ui", "map: zone hover", function(elapsed)
	since = since + elapsed
	if since >= EVERY then
		since = 0
		Hover()
	end
	Name(hover.zone)
	Border(hover.zone)
end, { shownOnly = Window.frame })
-- Hidden: none (the canvases are emptied: ui/Engine.lua).
Window.frame:HookScript("OnHide", Runtime.Wrap("map: zone hover hidden", function()
	hover.zone, hover.map, since = nil, nil, EVERY
	Name(nil)
	Border(nil)
end))

---------------------------------------------------------------------------
-- Clicks (Core.lua:1335-1416, Layers.lua:2102-2122): ui/Window.lua routes them here
---------------------------------------------------------------------------

local pressed -- the zone a left press would fly to (its uiMap; false: zone clicks weren't on offer)

-- Shift or Ctrl held: true if taken (the map doesn't pan).
function ZoneInfo.Modified(button)
	if IsControlKeyDown() and button == "RightButton" then
		Command({ kind = "waypoint", pos = false })
		return true
	end
	if button ~= "LeftButton" then return false end
	local inst, col, row = Camera.inst, ZoneInfo.CursorTile()
	if not Atlas.ZoneAt(inst, col, row) then return false end
	local pos = { inst = inst, col = col, row = row }
	Command({ kind = IsControlKeyDown() and "waypoint" or "way", pos = pos })
	return true
end

function ZoneInfo.Press() pressed = hover.map or false end

-- A click no pin took: a quest's area, while zone clicks aren't on offer; else the zone's, flown to.
function ZoneInfo.Tap()
	if not pressed then
		UI.Areas.Tap()
		return
	end
	local r = Atlas.MapRect(pressed)
	if r and r.inst == Camera.inst then Motion.FlyToRect(r.col0, r.row0, r.col1, r.row1) end
end

---------------------------------------------------------------------------
-- What's at a spot (ZoneInfo.lua): a few short colour-coded lines, once a right-click
---------------------------------------------------------------------------

-- 1,234
local function Thousands(n)
	local s, out = tostring(math.floor(n + 0.5)), nil
	repeat
		s, out = s:sub(1, -4), s:sub(-3) .. (out and ("," .. out) or "")
	until s == ""
	return out
end

-- Rounded to what a glance needs: 5 yards close by, 10 further out (ZoneInfo.lua:42-47).
local function Yards(tiles)
	local yd = tiles * TILE_YARDS
	local step = yd < 200 and 5 or 10
	return Thousands(math.floor(yd / step + 0.5) * step) .. " yd" -- /: never 0 (5 or 10)
end

-- From (c0, r0) to (c1, r1); columns run east, rows south.
local function Direction(c0, r0, c1, r1)
	local a = math.atan2(c1 - c0, r0 - r1) -- 0 = north, clockwise
	return COMPASS[math.floor(a / OCTANT + 0.5) % 8 + 1]
end

local function Dist(c0, r0, c1, r1) return math.sqrt((c1 - c0) ^ 2 + (r1 - r0) ^ 2) end

-- "Level 1-10", coloured against yours: green in range, red below it, grey past it (ZoneInfo.lua:58-69).
local function LevelLine(zone)
	local lo, hi = Atlas.ZoneLevels(zone.zone)
	if not lo or hi <= 0 then return nil end
	local mine, color = Model.you.level, WHITE
	if mine and mine > 0 then color = mine < lo and "|cffff6040" or mine > hi and GREY or "|cff40c040" end
	return GREY .. "Level|r " .. color .. (lo == hi and tostring(lo) or (lo .. "-" .. hi)) .. "|r"
end

-- Subzones and coordinates: "Goldshire  ·  42.1, 65.8" (ZoneInfo.lua:91-111): the areas there under the
-- zone, at most 2, the zone's first.
local function PlaceLine(zone)
	local coords = GREY .. string.format("%.1f, %.1f", zone.x * 100, zone.y * 100) .. "|r"
	local names, id = {}, zone.area
	while id and id ~= zone.zone do
		local a = Atlas.Area(id)
		if a.name ~= "" and a.name ~= zone.name then table.insert(names, 1, a.name) end
		id = a.parent
	end
	if not names[1] then return coords end
	return WHITE .. table.concat(names, " / ", 1, math.min(#names, 2)) .. "|r" .. SEP .. coords
end

-- How far and which way from you, when you're on this map (ZoneInfo.lua:111-117).
local function YouLine(inst, col, row)
	local you = Model.you
	if not (you.col and not you.stale and you.inst == inst) then return nil end
	local d = Dist(you.col, you.row, col, row)
	if d * TILE_YARDS < HERE_YD then return GREY .. "You're here|r" end
	return WHITE .. Yards(d) .. "|r " .. GREY .. Direction(you.col, you.row, col, row) .. " of you|r"
end

local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- "[12] Title" in its difficulty's colour (QuestInfo.lua:40-53).
local function Title(e)
	if not e.level then return e.name end
	return Hex(e.color) .. string.format("[%d] %s", e.level, e.name) .. "|r"
end

-- Your quests whose area holds (col, row) (Layers.lua:2282-2306): those the game draws (the quest areas'
-- frames shown, hit-tested as ui/Areas.lua does), then the estimated discs.
local function QuestsAt(inst, col, row)
	local out, seen, list = {}, {}, Model.Known("quests")
	local function Add(q)
		if seen[q] then return end
		for _, e in ipairs(list) do
			if e.quest == q then
				seen[q] = true
				out[#out + 1] = e
			end
		end
	end
	local layer = UI.Areas.layer
	local c = layer.on and layer.front
	local p = c and c.inst == inst and c.pools.blob
	for i = 1, p and p.n or 0 do
		local f = p[i]
		local r = f.rect
		if f.drawn > 0 and col >= r.col0 and col <= r.col1 and row >= r.row0 and row <= r.row1 then
			local q = f:UpdateMouseOverTooltip((col - r.col0) / (r.col1 - r.col0), -- /: never 0 (a map's rect has a size)
				(row - r.row0) / (r.row1 - r.row0)) -- /: never 0 (a map's rect has a size)
			if q then Add(q) end
		end
	end
	if Engine.LayerOn("quests") and Engine.LayerOn("questAreasApprox") then
		for _, e in ipairs(list) do
			local s = e.estimate
			if s and s.inst == inst and (s.col - col) ^ 2 + (s.row - row) ^ 2 <= RADIUS ^ 2 then Add(e.quest) end
		end
	end
	return out
end

-- At most 2, the one you follow first, then by title; how many more on the last (ZoneInfo.lua:119-136).
local function QuestLines(inst, col, row, out)
	local quests = QuestsAt(inst, col, row)
	table.sort(quests, function(a, b)
		if (a.followed == true) ~= (b.followed == true) then return a.followed == true end
		return a.name < b.name
	end)
	for i, e in ipairs(quests) do
		if i > MAX_QUESTS then
			out[#out] = out[#out] .. DIM .. string.format("  (+%d more)", #quests - MAX_QUESTS) .. "|r"
			break
		end
		if e.followed then
			out[#out + 1] = GOLD .. "Quest|r " .. Title(e) .. " " .. DIM .. "(following)|r"
		else
			out[#out + 1] = GREY .. "Quest|r " .. Title(e)
		end
	end
end

-- Lines describing tile (col, row) on the map shown, the first the zone's name (gold); nil: nothing to
-- say (ZoneInfo.lua:160-187).
function ZoneInfo.At(col, row)
	local inst, out = Camera.inst, {}
	local zone = Atlas.ZoneAt(inst, col, row)
	if zone then
		out[1] = GOLD .. zone.name .. "|r"
		out[2] = PlaceLine(zone)
		local levels, you = LevelLine(zone), YouLine(inst, col, row)
		out[3] = levels and you and (levels .. SEP .. you) or levels or you
	else
		-- Open sea, or a map without zones: the map's name, and the distance.
		local m = Atlas.Continent(inst)
		m = m and Atlas.UiMap(m)
		if m then out[1] = GOLD .. m.name .. "|r" end
		out[#out + 1] = YouLine(inst, col, row)
	end
	QuestLines(inst, col, row, out)
	return out[1] and out or nil
end

---------------------------------------------------------------------------
-- /mma zone; the title's click
---------------------------------------------------------------------------

-- The first zone whose name holds it, the map shown's first, then by map (Core.lua:1721-1734).
Command({ kind = "slash", name = "zone", help = "<name>: fly to a zone", fn = function(arg)
	arg = arg:lower()
	if arg == "" then return UI.Print(USAGE) end
	local found, inst
	local function Find(i)
		for _, z in ipairs(Atlas.Zones(i)) do
			if not found and z.name:lower():find(arg, 1, true) then found, inst = z, i end
		end
	end
	Find(Camera.inst or -1)
	for _, m in ipairs(Atlas.Maps()) do Find(m.inst) end
	if not found then return UI.Print("no zone matching '" .. arg .. "'") end
	Window.frame:Show()
	Camera.inst = inst
	Motion.FlyToRect(found.col0, found.row0, found.col1, found.row1)
end })

-- Dragging the title moves the window: no pick after it.
local title = UI.Title.hit
title:HookScript("OnDragStart", Runtime.Wrap("map: title drag", function(self) self.dragged = true end))
title:SetScript("OnClick", Runtime.Wrap("map: picker", function(self)
	if self.dragged then
		self.dragged = nil
		return
	end
	UI.Menus.Picker(self)
end))

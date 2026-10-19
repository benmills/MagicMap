-- Zones on the map, and what's at a spot (Core.lua:1247-1416, 1721-1734; Layers.lua:1786-1811,
-- 1996-2010, 2064-2122, 2280-2316; ZoneInfo.lua):
--   Hover: while more than one zone (its heart, weight 30 or more) is in view, the zone under the cursor
--     (big, or off your map: as the title names it) lights up, its name brighter, its border drawn over
--     the borders' on their shown canvas; a click there flies to it (fit 0.92), following off. A click's
--     turn (ui/Window.lua): a pin, then a quest's area while zone clicks aren't on offer, then the zone.
--   Ctrl-click: a waypoint there; Ctrl-right-click: none; Shift-click: its /way line in the chat box
--     (the waypoint and way Commands: Game's). Taken on the press, so the map doesn't pan; not off the
--     zones' maps (Atlas.ZoneMapAt: where Game's waypoint can go).
--   At(col, row): the big map's right-click menu leads with it (ui/Menus.lua): the zone, the areas explored
--     there and coordinates, its levels against yours, how far and which way from you, at most 2 quests whose
--     areas hold it, at most 2 landmarks near it.
--   /mma zone <name>: fly to the first zone whose name holds it, the map shown's first.

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
local TILE_YARDS = Atlas.TILE_YARDS
local RADIUS = 110 / 533.33 -- tiles: a quest's estimated area (Layers.lua:78)
local MAX_QUESTS, MAX_NEARBY = 2, 2 -- ZoneInfo.lua:13-14
local HERE_YD = 15 -- closer: "You're here" (ZoneInfo.lua:115)
local NEAR_YD = 900 -- landmarks further from the spot aren't near it (ZoneInfo.lua:11)
local CELL = 0.2 -- tiles: Game's sweep's cells (Model.exploredCells; Layers.lua:75)
-- Notable places, in order of interest: Known("places")' kind and label (ZoneInfo.lua:19-24).
local NOTABLE = { { place = "flight", label = "Flight point" }, { place = "dungeon", label = "Dungeon" },
	{ place = "graveyard", label = "Graveyard" } }
-- C_Map.IsCityMap's (ZoneInfo.lua:79): no fog of war to lift (Stormwind City, Orgrimmar, Ironforge, Thunder
-- Bluff, Darnassus, Undercity).
local CITY = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
local GOLD, WHITE, GREY, DIM = "|cffffd100", "|cffffffff", "|cffa8a8a8", "|cff808080" -- ZoneInfo.lua:16
local SEP = DIM .. "  ·  |r"
local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local OCTANT = math.pi / 4
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
	-- At the minimap's size on your map it always names where you are: no zone to click (Core.lua:1269);
	-- none while the left button is held, still or not (Core.lua:1323, 1349).
	if Window.view:IsMouseOver() and (UI.BigMap.big or Model.you.inst ~= inst) and not Motion.Pressed() then
		z = ZoneAt(inst, ZoneInfo.CursorTile())
	end
	local on = z and ZonesInView(inst) > 1
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
-- highlight pool), thick clamp(z / 100, 1.6, 2.4) at that canvas's zoom, its lines as theirs (ui/Borders.lua's
-- polyline: clipped to its layout's region, fading ends), scaled, dimmed and crossfaded with it. Drawn by a
-- job a few a frame, once the map's layouts are done (Engine.pending: their frames are full); parked off the
-- canvases when not drawn, as Engine's.
local lit = {} -- zone, c: what it's drawn for (c nil: none)
local BUDGET = 1 -- ms a frame
local park = CreateFrame("Frame", nil, Window.view)
park:Hide()
local lines = { n = 0, out = 0 } -- 1..n this drawing's; 1..out on lit.c, the rest parked
local scratch, thick = UI.Borders.Scratch(), 1 -- (its own: the borders' layout is another job); this drawing's width

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

-- A piece f of the way faded in (Layers.lua:1568-1577), clipped: the next Line, on the canvas.
local function Piece(c, _, x1, y1, x2, y2, f)
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

-- Its lines of Data/Borders.lua ({ areaA, areaB, fadeStart, fadeEnd, x1, y1, ... }), each as ui/Borders.lua
-- draws a zone's.
local function Light()
	local c, zone = lit.c, lit.zone
	local list = zone and Atlas.BorderLines(c.inst, c.zoom)
	lines.n = 0
	if list then
		local z, r, box = c.zoom, c.region, scratch.box
		box[1], box[2], box[3], box[4] = (r[1] - c.ox) * z, (r[2] - c.oy) * z, (r[3] - c.ox) * z, (r[4] - c.oy) * z
		thick = math.max(1.6, math.min(2.4, z / 100)) -- Layers.lua:1794
		for _, l in ipairs(list) do
			if l[1] == zone or l[2] == zone then UI.Borders.Polyline(scratch, c, l, 5, l[3] > 0, l[4] > 0, 0, Piece) end
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
	if not Atlas.ZoneMapAt(inst, col, row) then return false end -- (where Game's waypoint and way go)
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
	if r and r.inst == Camera.inst then Motion.FlyToRect(r.col0, r.row0, r.col1, r.row1, Atlas.UiMap(pressed).name) end
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

-- "Level 1-10", the client's for the zone's map (Model.levels), coloured against yours: green in range, red
-- below it, grey past it (ZoneInfo.lua:58-69).
local function LevelLine(zone)
	local l = Model.levels[zone.mapID]
	if not l then return nil end
	local lo, hi = l[1], l[2]
	local mine, color = Model.you.level, WHITE
	if mine and mine > 0 then color = mine < lo and "|cffff6040" or mine > hi and GREY or "|cff40c040" end
	return GREY .. "Level|r " .. color .. (lo == hi and tostring(lo) or (lo .. "-" .. hi)) .. "|r"
end

-- The areas explored at the spot (ZoneInfo.lua:71-89): false if the client names none at its cell (Game's
-- sweep, Model.exploredCells: a city has no fog to lift, nil); else those of its chain (the area there, then
-- each it's in, up to the zone) the client names explored (Model.explored), their names but the zone's, the
-- outermost first; nil: Game can't say.
local function Explored(zone, inst, col, row)
	local all, explored = Model.exploredCells, Model.explored or NONE
	local r = all and all[inst] and Atlas.MapRect(Atlas.Continent(inst))
	local lit = r and (all[inst][math.floor((row - r.row0) / CELL) + 1] or NONE)[math.floor((col - r.col0) / CELL) + 1]
	if lit == nil then return nil end
	if not lit then
		if CITY[zone.mapID] then return nil end
		return false
	end
	local names, seen, id = {}, { [zone.name] = true }, zone.area
	while id do
		local a = Atlas.Area(id)
		if explored[id] and not seen[a.name] and a.name ~= "" then
			seen[a.name] = true
			table.insert(names, 1, a.name)
		end
		id = id ~= zone.zone and a.parent or nil
	end
	return names
end

-- The spot's outermost area under the zone, by name (the area chain's): where an unexplored spot is near.
local function Near(zone)
	local name, id = nil, zone.area
	while id and id ~= zone.zone do
		local a = Atlas.Area(id)
		if a.name ~= "" and a.name ~= zone.name then name = a.name end
		id = a.parent
	end
	return name
end

-- The areas explored and coordinates: "Goldshire  ·  42.1, 65.8"; none explored, "Unexplored, near Goldshire  ·
-- 42.1, 65.8"; Game can't say, or only the zone's explored, the coordinates (ZoneInfo.lua:91-109).
local function PlaceLine(zone, inst, col, row)
	local coords = GREY .. string.format("%.1f, %.1f", zone.x * 100, zone.y * 100) .. "|r"
	local names, place = Explored(zone, inst, col, row), nil
	if names and names[1] then
		place = WHITE .. table.concat(names, " / ", 1, math.min(#names, 2)) .. "|r"
	elseif names == false then
		local near = Near(zone)
		place = DIM .. "Unexplored|r" .. (near and (DIM .. ", near|r " .. WHITE .. near .. "|r") or "")
	end
	return place and (place .. SEP .. coords) or coords
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

-- Your quests whose area holds (col, row) (Layers.lua:2282-2306): those the game draws (ui/Areas.lua's
-- hit test), then the estimated discs while they're on (their parent too: Layers.lua:82-87, 2297).
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
	for _, q in ipairs(UI.Areas.QuestsAt(inst, col, row)) do Add(q) end
	if Engine.LayerOn("quests") and Engine.LayerOn("questAreas") and Engine.LayerOn("questAreasApprox") then
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

-- The nearest notable place of each kind within NEAR_YD of the spot (Known("places"), its layer on or off),
-- the closest first, at most 2: "Graveyard Goldshire  ·  175 yd SE" (ZoneInfo.lua:138-157).
local found = {}
local function Closer(a, b) return a.d < b.d end
local function NearbyLines(inst, col, row, out)
	local list, n = Model.Known("places"), 0
	for _, k in ipairs(NOTABLE) do
		local best, bestD
		for _, e in ipairs(list) do
			local p = e.pos
			if e.place == k.place and p.inst == inst then
				local d = Dist(col, row, p.col, p.row)
				if d * TILE_YARDS <= NEAR_YD and (not bestD or d < bestD) then best, bestD = e, d end
			end
		end
		if best then
			n = n + 1
			found[n] = { e = best, d = bestD, label = k.label }
		end
	end
	for i = #found, n + 1, -1 do found[i] = nil end
	table.sort(found, Closer)
	for i = 1, math.min(n, MAX_NEARBY) do
		local f = found[i]
		local p = f.e.pos
		local where = f.d * TILE_YARDS < HERE_YD and "here" or (Yards(f.d) .. " " .. Direction(col, row, p.col, p.row))
		local title = f.e.name ~= f.label and (WHITE .. f.e.name .. "|r" .. SEP) or ""
		out[#out + 1] = GREY .. f.label .. "|r " .. title .. GREY .. where .. "|r"
	end
end

-- Lines describing tile (col, row) on the map shown, the first the zone's name (gold); nil: nothing to
-- say (ZoneInfo.lua:160-187).
function ZoneInfo.At(col, row)
	local inst, out = Camera.inst, {}
	local zone = Atlas.ZoneAt(inst, col, row)
	if zone then
		out[1] = GOLD .. zone.name .. "|r"
		out[2] = PlaceLine(zone, inst, col, row)
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
	NearbyLines(inst, col, row, out)
	return out[1] and out or nil
end

---------------------------------------------------------------------------
-- /mma zone; the title's click
---------------------------------------------------------------------------

-- The first zone whose name holds it, the map shown's first, then by map (Core.lua:1721-1734). Alone: the
-- spike's usage line (game/Slash.lua).
Command({ kind = "slash", name = "zone", help = "<name>: fly to a zone", fn = function(arg)
	arg = arg:lower()
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
	Motion.FlyToRect(found.col0, found.row0, found.col1, found.row1, found.name)
end })

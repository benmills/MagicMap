-- Zones on the map, and what's at a spot:
--   Hover: while more than one zone (its heart, weight 30 or more) is in view, the zone under the cursor
--     (big, or off your map: as the title names it) lights up, its name brighter; a click there flies to it
--     (fit 0.92), following off. A click's turn (ui/Window.lua): a pin, then a quest's area while zone
--     clicks aren't on offer, then the zone.
--   Ctrl-click: a waypoint there; Ctrl-right-click: none; Shift-click: its /way line in the chat box
--     (the waypoint and way Commands: Game's). Taken on the press, so the map doesn't pan; not off the
--     zones' maps (Atlas.ZoneMapAt: where Game's waypoint can go).
--   At(col, row): the big map's right-click menu leads with it (ui/Menus.lua): the zone, the areas explored
--     there and coordinates, its levels against yours, how far and which way from you, at most 2 quests whose
--     areas hold it, at most 2 landmarks near it.
--   /mm zone <name>: fly to the first zone whose name holds it, the map shown's first.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window, Motion = UI.Camera, UI.Window, UI.Motion
local Maths = Atlas.Camera
local Command = ns.Game.Command

local EVERY = 0.05 -- s: the hover's look, as the title's
local MIN_WEIGHT = 30 -- a zone's land chunks to count as in view
-- A pointed-at zone's name (Settings > Map > Names > Zone names > Light up on hover): its colour, one table, so a
-- name whose colour is still this one is still lit (ui/Labels.lua keeps each name's: fs.color); its size against
-- the size it has, and its outline's font flags (nil: the one it has). The colours and outlines on offer are the
-- names' states' (ui/Labels.lua, as your zone's).
local HOVER_COLORS, HOVER_OUTLINES, FLAGS = UI.Labels.STATE_COLORS, UI.Labels.STATE_OUTLINES, UI.Labels.FLAGS
local LABEL_HOVER = { 1, 1, 0.9, 1 }
local hoverOn, hoverK, hoverFlags = true, 1, nil
local TILE_YARDS = Atlas.TILE_YARDS
local MAX_QUESTS, MAX_NEARBY = 2, 2 -- lines of quests and of landmarks at a spot, at most
local HERE_YD = 15 -- closer: "You're here"
local NEAR_YD = 900 -- landmarks further from the spot aren't near it
local NEAR_SUB_YD = 350 -- an unexplored spot is "near" a subzone label this close
local CELL = 0.2 -- tiles: Game's sweep's cells (Model.exploredCells)
-- Notable places, in order of interest: Known("places")' kind and label.
local NOTABLE = { { place = "flight", label = "Flight point" }, { place = "dungeon", label = "Dungeon" },
	{ place = "graveyard", label = "Graveyard" } }
-- C_Map.IsCityMap's: no fog of war to lift (Stormwind City, Orgrimmar, Ironforge, Thunder
-- Bluff, Darnassus, Undercity).
local CITY = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
local GOLD, WHITE = "|cffffd100", "|cffffffff"
local DIM, SEP = UI.Tip.DIM, UI.Tip.SEP -- the map's one grey for facts (ui/Tip.lua)
local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local OCTANT = math.pi / 4
local NONE = {}

local ZoneInfo = {}
UI.ZoneInfo = ZoneInfo

-- The tile under the cursor on the map shown.
function ZoneInfo.CursorTile()
	local w, h = Window.Size()
	return Maths.ScreenToTile(Camera.cam, w, h, Window.Cursor())
end

---------------------------------------------------------------------------
-- Hover: the zone under the cursor, 20 times a second
---------------------------------------------------------------------------

-- The zone at (col, row): Atlas's, worked out again only when the area under it changes (a hover
-- makes no table each update).
local at = {}
local function ZoneAt(inst, col, row)
	local id = Atlas.AreaAt(inst, col, row)
	if id ~= at.area or inst ~= at.inst then at.area, at.inst, at.z = id, inst, Atlas.ZoneAt(inst, col, row) end
	return at.z
end

-- How many zones meaningfully share the view: those whose heart (their name's anchor, Data/Anchors.lua)
-- is on it. Worked out again when the view moves.
local inView = {}
local function ZonesInView(inst)
	local cam, w, h = Camera.cam, Window.Size()
	local v = inView
	if v.inst == inst and v.cx == cam.cx and v.cy == cam.cy and v.zoom == cam.zoom and v.w == w and v.h == h then
		return v.n
	end
	local c0, r0 = Maths.ScreenToTile(cam, w, h, 0, 0)
	local c1, r1 = Maths.ScreenToTile(cam, w, h, w, h)
	local n = 0
	for _, l in ipairs(Atlas.Anchors(inst) or NONE) do -- { areaID, col, row, weight, kind (1: a zone) }
		if l[5] == 1 and l[4] >= MIN_WEIGHT and l[2] >= c0 and l[2] <= c1 and l[3] >= r0 and l[3] <= r1 then n = n + 1 end
	end
	v.inst, v.cx, v.cy, v.zoom, v.w, v.h, v.n = inst, cam.cx, cam.cy, cam.zoom, w, h, n
	return n
end

-- zone: the hovered zone lit (its areaID), while zone clicks are on offer; map: its uiMap, a click's.
local hover = {}
local function Hover()
	local inst, z = Camera.inst, nil
	-- At the minimap's size on your map it always names where you are: no zone to click;
	-- none while the left button is held, still or not.
	if inst and Window.view:IsMouseOver() and (UI.BigMap.big or Model.you.inst ~= inst) and not Motion.Pressed() then
		z = ZoneAt(inst, ZoneInfo.CursorTile())
	end
	local on = z and ZonesInView(inst) > 1
	hover.zone, hover.map = on and z.zone or nil, on and z.mapID or nil
end

---------------------------------------------------------------------------
-- Its look: its name brighter, on the canvas shown
---------------------------------------------------------------------------

-- Its name on the labels' shown canvas (ui/Labels.lua: each name's font string carries its label, fs.label, and
-- how it's dressed: fs.color, fs.font, fs.size, fs.flags): the name alone, in the pointed-at look (its colour; its
-- size and outline where they differ), then back as it was dressed, your zone's look if it's yours (one a layout
-- has dressed again since is left be: what it's told of the font is kept on it, so the layout sets its own). Its
-- level line (label.line, the same zone's) keeps its own colour: that says its difficulty.
local named = {} -- zone, c: the canvas; fs: the name lit; was, size, flags: its colour, size and outline before
local function Dress(fs, size, flags)
	if fs.size ~= size or fs.flags ~= flags then
		fs:SetFont(fs.font, size, flags)
		fs.size, fs.flags = size, flags
	end
end
local function Name(zone)
	if not hoverOn then zone = nil end
	local c = UI.Labels.on and UI.Labels.front or nil
	if zone == named.zone and c == named.c then return end
	local fs, was = named.fs, named.was
	if fs and fs.color == LABEL_HOVER then
		fs:SetTextColor(was[1], was[2], was[3], 1) -- (its opacity is the font string's own alpha: ui/Labels.lua's Font)
		fs.color = was
		Dress(fs, named.size, named.flags)
	end
	named.zone, named.c, named.fs, named.was = zone, c, nil, nil
	local p = zone and c and c.pools.label
	for i = 1, p and p.n or 0 do
		fs = p[i]
		if fs.label.areaID == zone and not fs.label.line then
			named.fs, named.was, named.size, named.flags = fs, fs.color, fs.size, fs.flags
			fs:SetTextColor(LABEL_HOVER[1], LABEL_HOVER[2], LABEL_HOVER[3], 1)
			fs.color = LABEL_HOVER
			Dress(fs, math.floor(fs.size * hoverK + 0.5), hoverFlags or fs.flags)
			break
		end
	end
end

local since = EVERY
Runtime.Step("ui", "map: zone hover", function(elapsed)
	since = since + elapsed
	if since >= EVERY then
		since = 0
		Hover()
	end
	Name(hover.zone)
end, { shownOnly = Window.frame })
-- The pointed-at look's settings: one lit now is set back, and lit again in the new look at the next frame.
local function SetHoverColor(v)
	local _, c = UI.Feel.RGB(HOVER_COLORS, v, HOVER_COLORS[1][1])
	Name(nil)
	LABEL_HOVER[1], LABEL_HOVER[2], LABEL_HOVER[3] = c[1], c[2], c[3]
end
UI.Feel.Add("map", "Names", {
	{ key = "labels.hover", kind = "toggle", label = "Light up on hover", default = true, under = "labels.zones",
		apply = function(on) hoverOn = on ~= false end,
		tip = "A zone's name takes a look of its own while you point at the zone on the big map. Open it (+) for its colour, size and outline." },
	{ key = "labels.hoverColor", kind = "color", label = "Colour", under = "labels.hover", colors = HOVER_COLORS, default = HOVER_COLORS[1][1],
		apply = SetHoverColor, tip = "The colour a zone's name lights up in." },
	{ key = "labels.hoverSize", kind = "slider", label = "Size", under = "labels.hover", min = 1, max = 1.5, step = 0.05, pct = true, default = hoverK,
		apply = function(k) Name(nil); hoverK = k end, tip = "How much bigger a zone's name is while you point at its zone." },
	{ key = "labels.hoverOutline", kind = "select", label = "Outline", under = "labels.hover", options = HOVER_OUTLINES, default = "same",
		apply = function(v) Name(nil); hoverFlags = FLAGS[v] end,
		tip = "The outline of a zone's name while you point at its zone: as the other names', none, thin or thick." },
})
-- Hidden: none (the canvases are emptied: ui/Engine.lua).
Window.frame:HookScript("OnHide", Runtime.Wrap("map: zone hover hidden", function()
	hover.zone, hover.map, since = nil, nil, EVERY
	Name(nil)
end))

---------------------------------------------------------------------------
-- Clicks: ui/Window.lua routes them here
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
-- What's at a spot: a few short colour-coded lines, once a right-click
---------------------------------------------------------------------------

-- 1,234
local function Thousands(n)
	local s, out = tostring(math.floor(n + 0.5)), nil
	repeat
		s, out = s:sub(1, -4), s:sub(-3) .. (out and ("," .. out) or "")
	until s == ""
	return out
end

-- Rounded to what a glance needs: 5 yards close by, 10 further out.
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

-- "Level 1-10", the client's for the zone's map (Model.levels), in its difficulty's colour for your level
-- (Model.ZoneColor, as the level line under its name on the map: ui/Labels.lua); white until yours is known.
local function LevelLine(zone)
	local l = Model.levels[zone.mapID]
	if not l then return nil end
	local lo, hi = l[1], l[2]
	local c = Model.ZoneColor(lo, hi)
	return DIM .. "Level|r " .. (c and UI.Tip.Hex(c) or WHITE) .. (lo == hi and tostring(lo) or (lo .. "-" .. hi)) .. "|r"
end

-- The areas explored at the spot: false if the client names none at its cell (Game's
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

-- The subzone anchor nearest the spot, within NEAR_SUB_YD, not the zone's name and on the zone's own
-- map (not one in the next zone): where an unexplored spot is near.
local function Near(zone, inst, col, row)
	local best, bestD, name
	for _, l in ipairs(Atlas.Anchors(inst) or NONE) do
		local a = l[5] ~= 1 and Atlas.Area(l[1])
		if a and a.name ~= "" then
			local d = (l[2] - col) ^ 2 + (l[3] - row) ^ 2
			if not bestD or d < bestD then best, bestD, name = l, d, a.name end
		end
	end
	if not best or math.sqrt(bestD) * TILE_YARDS > NEAR_SUB_YD or name == zone.name then return nil end
	local at = Atlas.ZoneMapAt(inst, best[2], best[3])
	return at and at.mapID == zone.mapID and name or nil
end

-- The areas explored and coordinates: "Goldshire  ·  42.1, 65.8"; none explored, "Unexplored, near Goldshire  ·
-- 42.1, 65.8"; Game can't say, or only the zone's explored, the coordinates.
local function PlaceLine(zone, inst, col, row)
	local coords = DIM .. string.format("%.1f, %.1f", zone.x * 100, zone.y * 100) .. "|r"
	local names, place = Explored(zone, inst, col, row), nil
	if names and names[1] then
		place = WHITE .. table.concat(names, " / ", 1, math.min(#names, 2)) .. "|r"
	elseif names == false then
		local near = Near(zone, inst, col, row)
		place = DIM .. "Unexplored|r" .. (near and (DIM .. ", near|r " .. WHITE .. near .. "|r") or "")
	end
	return place and (place .. SEP .. coords) or coords
end

-- How far and which way from you, when you're on this map.
local function YouLine(inst, col, row)
	local you = Model.you
	if not (you.col and not you.stale and you.inst == inst) then return nil end
	local d = Dist(you.col, you.row, col, row)
	if d * TILE_YARDS < HERE_YD then return DIM .. "You're here|r" end
	return WHITE .. Yards(d) .. "|r " .. DIM .. Direction(you.col, you.row, col, row) .. " of you|r"
end

local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- The title in its difficulty's colour, its level after it in DIM (as its tooltip: ui/QuestTooltip.lua).
local function Title(e)
	if not e.level then return e.name end
	return Hex(e.color) .. e.name .. "|r " .. DIM .. e.level .. "|r"
end

-- Your quests whose area holds (col, row): those the game draws (ui/Areas.lua's
-- hit test).
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
	return out
end

-- At most 2, the one you follow first, then by title; how many more on the last.
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
			out[#out + 1] = DIM .. "Quest|r " .. Title(e)
		end
	end
end

-- The nearest notable place of each kind within NEAR_YD of the spot (Known("places"), its layer on or off),
-- the closest first, at most 2: "Graveyard Goldshire  ·  175 yd SE".
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
		out[#out + 1] = DIM .. f.label .. "|r " .. title .. DIM .. where .. "|r"
	end
end

-- Lines describing tile (col, row) on the map shown, the first the zone's name (gold); nil: nothing to
-- say.
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
-- /mm zone; the title's click
---------------------------------------------------------------------------

-- The first zone whose name holds it, the map shown's first, then by map. Alone: the usage line
-- (game/Slash.lua).
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

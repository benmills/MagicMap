-- Scenarios for tools/smoketest.py: each drives the loaded addon through
-- one area of behaviour on the simulated client (tools/tests/wowsim.lua).
-- `check(cond, msg)` records a failed expectation; Lua errors anywhere in
-- the addon are collected by the simulation itself.
--
-- Each runs in a fresh client, after login, with the map open and following.

local Sim, ns, check = ...
local S = Sim.state
local scenarios = {}

-- Tile textures currently drawn: shown textures holding a FileDataID.
local function TilesDrawn()
	local n = 0
	local function walk(f)
		for _, r in ipairs(S[f].regions) do
			if S[r].type == "Texture" and type(S[r].texture) == "number" and r:IsVisible() then n = n + 1 end
		end
		for _, c in ipairs(S[f].children) do walk(c) end
	end
	walk(ns.frame)
	return n
end

local function Fly() Sim.Run(1.5) end

-- Pins drawn for quest `questID` (frames whose entry carries it).
local function QuestPin(questID)
	for _, f in ipairs(Sim.Frames()) do
		if f.entry and f.entry.questID == questID and f:IsVisible() then return f end
	end
end

-- Choose `text` from the open right-click menu: the client's (MenuUtil) or
-- our fallback's. Returns whether it was there.
local function PickMenu(text)
	for _, e in ipairs(Sim.MenuItems("button")) do
		if e.text == text then
			Sim.menu = nil
			e.onSelect()
			return true
		end
	end
	for _, f in ipairs(Sim.Frames()) do
		if f.item and f.item.text == text and f:IsVisible() then
			Sim.Click(f)
			return true
		end
	end
	return false
end

-- Click the map where `frame` is, as a player would.
local function ClickOn(frame, button)
	local x, y = frame:GetCenter()
	local s = frame:GetEffectiveScale()
	Sim.Click(ns.viewport, button, x * s, y * s, "screen")
end

scenarios.boot = function()
	check(ns.frame:IsVisible(), "the map is open after login")
	check(ns.state.map == 0, "showing the player's continent (0), got " .. tostring(ns.state.map))
	check(TilesDrawn() > 0, "tiles are drawn")
	check(ns.state.playerCol ~= nil, "knows where the player is")
	Sim.Run(3) -- borders, labels, pins settle
	check(QuestPin(60) ~= nil, "the Elwynn quest has a pin")
	if Sim.flavor == "forever" then
		check(ns.layoutStats and ns.layoutStats.lines > 0, "zone borders are drawn (from offline data)")
	end
	check(#Sim.timers == 0 or Sim.timers[1].at > Sim.time - 1, "timers drain")
end

scenarios.zoom_and_pan = function()
	local z0 = ns.state.zoom
	for _ = 1, 6 do Sim.Wheel(ns.viewport, 1); Sim.Run(0.1) end
	Sim.Run(1)
	check(ns.state.zoom > z0, "wheel up zooms in")
	for _ = 1, 20 do Sim.Wheel(ns.viewport, -1); Sim.Run(0.05) end
	Sim.Run(1)
	check(ns.state.zoom < z0, "wheel down zooms out")
	local cx = ns.state.cx
	Sim.Drag(ns.viewport, 200, -100)
	Sim.Run(0.5)
	check(ns.state.cx ~= cx, "dragging pans")
	check(not ns.state.follow, "dragging stops following")
	Sim.Click(ns.viewport, "RightButton")
	check(PickMenu("Follow me"), "right-click offers to follow you")
	Fly()
	check(ns.state.follow, "and that goes back to following")
	-- All the way out and in, past the limits.
	for _ = 1, 40 do Sim.Wheel(ns.viewport, -1) end
	Sim.Run(2)
	for _ = 1, 60 do Sim.Wheel(ns.viewport, 1) end
	Sim.Run(2)
	check(TilesDrawn() > 0, "tiles still drawn after zooming in fully")
end

scenarios.follow_moving_player = function()
	local z0 = ns.state.zoom
	Sim.player.speed, Sim.player.facing = 60, 1.2 -- flying, heading west-ish
	Sim.Run(6)
	check(ns.state.zoom == z0, "moving fast leaves your zoom alone")
	check(math.abs(ns.state.cx - Sim.player.col) < 0.01, "the view follows the player")
	Sim.player.speed = 0
	-- Teleport to the other continent.
	Sim.player.inst, Sim.player.col, Sim.player.row = 1, 42, 28
	Sim.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	Sim.Run(1)
	check(ns.state.map == 1, "follows the player to Kalimdor")
	-- An instance that hides your position.
	Sim.restricted = true
	Sim.player.inst = 36
	Sim.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	Sim.Run(2)
	Sim.restricted = false
	Sim.player.inst, Sim.player.col, Sim.player.row = 0, 31.95, 49.75
	Sim.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	Sim.Run(1)
end

scenarios.slash_commands = function()
	for _, cmd in ipairs({ "", "", "follow", "follow", "map 1", "map kalimdor", "map 0", "map nowhere", "zone elwynn",
		"zone westfall", "zone nowhere", "tiles", "debug", "debug", "reset", "layers", "landmarks", "icon", "icon",
		"blips", "minimap", "sync", "sync", "sync full", "sync", "minimap", "perf top", "perf", "perf", "help" }) do
		Sim.Slash(cmd)
		Sim.Run(0.3)
	end
	check(#Sim.prints > 0, "slash commands print")
end

scenarios.title_buttons = function()
	-- The window's controls: gear and mode button in the band, toggles and
	-- zoom inside the map; all fade in while you hover.
	Sim.MoveCursorTo(ns.viewport, 0.5, 0.5)
	Sim.Run(0.5)
	check(ns.gearButton:IsVisible() and ns.gearButton:GetAlpha() > 0.9, "the gear shows while hovering the window")
	check(ns.mapControls.frame:IsVisible() and ns.mapControls.frame:GetAlpha() > 0.9, "and the map's controls")
	for _, button in ipairs({ ns.gearButton, ns.mapControls.follow, ns.mapControls.path, ns.mapControls.zoomIn, ns.mapControls.zoomOut }) do
		Sim.Hover(button)
		Sim.Click(button)
		Sim.Run(0.3)
	end
	Sim.MoveCursorTo(UIParent, 0.1, 0.1)
	Sim.Run(0.5)
	check(ns.gearButton:GetAlpha() < 0.1 and ns.mapControls.frame:GetAlpha() < 0.1, "they fade once the mouse leaves")
end

scenarios.minimap_mode = function()
	local parent = Minimap:GetParent()
	Sim.Click(ns.modeButton)
	Sim.Run(2)
	check(ns.IsMinimapMode(), "minimap mode is on")
	-- Its header: zone left, gear and back right, on one line above the map.
	check(ns.gearButton:IsVisible() and ns.modeButton:IsVisible(), "gear and mode button above the map")
	local _, backY = ns.modeButton:GetCenter()
	check(backY > ns.frame:GetTop() or backY < ns.frame:GetBottom(), "they sit outside the map (above it, or below at the screen's top)")
	-- (Font strings have no height in the simulator, so check the anchor.)
	local p, rel, rp = ns.titleText:GetPoint(1)
	local above = backY > ns.frame:GetTop()
	check(rel == ns.frame and p == (above and "BOTTOMLEFT" or "TOPLEFT") and rp == (above and "TOPLEFT" or "BOTTOMLEFT"),
		"the zone text is left-aligned on the same side as the buttons")
	Sim.Click(ns.gearButton)
	Sim.Run(0.2)
	local gearMenu
	for _, f in ipairs(Sim.Frames()) do
		if f:GetParent() == ns.gearButton and f:IsVisible() then gearMenu = f end
	end
	check(gearMenu ~= nil or Sim.menu ~= nil, "the gear opens the layers menu")
	if Sim.menu then Sim.menu = nil else Sim.Click(ns.gearButton) end
	-- Inside the map, while hovering: toggles and zoom.
	local mc = ns.mapControls
	Sim.MoveCursorTo(ns.viewport, 0.5, 0.5)
	Sim.Run(0.5)
	check(mc.frame:IsVisible() and mc.frame:GetAlpha() > 0.9, "hovering shows the map's controls")
	check(mc.follow.ring:IsShown() and not mc.path.ring:IsShown(), "the follow toggle is lit while following")
	local z1 = ns.state.zoom
	Sim.Click(mc.zoomIn)
	Sim.Run(0.6)
	check(ns.state.zoom > z1 and ns.state.follow, "+ zooms in, still following")
	Sim.Click(mc.zoomOut)
	Sim.Run(0.6)
	Sim.Click(mc.follow)
	check(not ns.state.follow and not mc.follow.ring:IsShown(), "the follow toggle turns following off")
	Sim.Click(mc.follow)
	Sim.Run(1)
	check(ns.state.follow, "and back on")
	check(ns.gearButton:GetAlpha() > 0.9, "the gear and back show while hovering")
	local gx, gy = ns.gearButton:GetCenter()
	Sim.cursorX, Sim.cursorY = gx, gy -- onto the header line, off the map itself
	Sim.Run(0.5)
	check(ns.gearButton:GetAlpha() > 0.9, "and stay while the mouse is on them")
	Sim.MoveCursorTo(UIParent, 0.1, 0.1)
	Sim.Run(0.5)
	check(mc.frame:GetAlpha() < 0.1 and ns.gearButton:GetAlpha() < 0.1, "they fade once the mouse leaves")
	local side = math.min(ns.frame:GetSize())
	check(math.abs(ns.state.zoom - side / (200 / (1600 / 3))) < 1, "it starts showing 200 yards across")
	ns.frame:SetSize(side * 1.5, side * 1.5)
	check(math.abs(ns.state.zoom - 1.5 * side / (200 / (1600 / 3))) < 1, "and keeps showing 200 yards as it grows")
	ns.frame:SetSize(side, side)
	check(Minimap:GetParent() == ns.viewport, "the Minimap moved into the map")
	check(Minimap:GetAlpha() == 0, "its terrain is hidden")
	check(Sim.minimapButton:GetParent() == ns.minimapStandIn, "other addons' minimap buttons moved to the stand-in")
	local pinHost = _G.MagicMapMinimapPins
	check(Sim.gatherPin:GetParent() == Minimap or Sim.gatherPin:GetParent() == pinHost, "pins stay with the Minimap")
	check(not MinimapCluster:IsShown() and not Sim.minimapButton:IsVisible(), "nothing of the minimap is left in its corner")
	-- Ours first: standing at a turn-in, our pin stays, over the Minimap's.
	local home = { Sim.player.col, Sim.player.row }
	local _, col, row = ns.MapToTile(1429, 0.40, 0.80)
	Sim.player.col, Sim.player.row = col, row
	Sim.Run(1)
	check(QuestPin(62) ~= nil, "our turn-in pin stays where the Minimap is")
	Sim.player.col, Sim.player.row = home[1], home[2]
	Sim.Run(1)
	-- Ride, zoom out past the blips, back in.
	Sim.player.speed = 14
	Sim.Run(2)
	for _ = 1, 30 do Sim.Wheel(ns.viewport, -1) end
	Sim.Run(2)
	for _ = 1, 30 do Sim.Wheel(ns.viewport, 1) end
	Sim.Run(2)
	Sim.player.speed = 0
	-- Pan away; it drifts back to you once left alone.
	Sim.Drag(ns.viewport, 80, 0)
	Sim.MoveCursorTo(UIParent, 0.1, 0.1)
	Sim.Run(8)
	check(ns.state.follow, "goes back to following after idling")
	check(ns.MinimapShowsPlayer() and Sim.minimapMask:find("MinimapMask\\Square%d+$"),
		"zoomed in past its closest level, the Minimap still shows, masked")
	check(Sim.gatherPin:GetParent() == pinHost and pinHost:IsVisible(), "HereBeDragons' pins are on our host in the window")
	ns.SetZoom(160)
	Sim.Run(0.5)
	check(ns.MinimapShowsPlayer() and Minimap:IsVisible(), "settled, the Minimap's blips show")
	check(not C_Minimap or Sim.rimInset == 1000, "Blizzard's rim arrows are pushed off screen")
	check(Sim.BlobRingsAt(0), "and its quest area rings are hidden")
	check(Sim.minimapMask and not Minimap:IsClampedToScreen(), "square or masked, and never clamped to the screen")
	Sim.Wheel(ns.viewport, 1)
	Sim.Run(0.05)
	check(not Minimap:IsVisible() and not ns.MinimapShowsPlayer(), "mid-zoom, it steps aside")
	Sim.Run(1.5)
	check(ns.MinimapShowsPlayer(), "and is back once the zoom settles")
	-- Indoors: the window wears the Minimap itself, and the wheel zooms it.
	Sim.indoors = true
	Sim.Run(1)
	check(Minimap:IsVisible() and Minimap:GetAlpha() == 1 and ns.MinimapShowsPlayer(), "indoors, the Minimap shows whole")
	check(Sim.rimInset == nil and Sim.BlobRingsAt(1), "indoors, its own arrows and rings are back")
	local mz = Minimap:GetZoom()
	local top = ns.viewport -- what the cursor would wheel: the highest wheel-enabled frame over the map
	for _, c in ipairs({ ns.viewport:GetChildren() }) do
		if c:IsVisible() and S[c].wheel and c:GetFrameLevel() > top:GetFrameLevel() then top = c end
	end
	Sim.Wheel(top, mz < 5 and 1 or -1)
	check(Minimap:GetZoom() ~= mz, "indoors, the wheel zooms the Minimap")
	Sim.indoors = false
	Sim.Run(2)
	check(Minimap:GetAlpha() == 0, "back outdoors, our map again")
	check(ns.frame:GetFrameStrata() == MinimapCluster:GetFrameStrata(), "it sits at the minimap's strata")
	-- M: ours grows to most of the screen instead of Blizzard's world map.
	local smallW, smallZoom = ns.frame:GetWidth(), ns.state.zoom
	ToggleWorldMap()
	Sim.Run(1)
	check(ns.IsMapExpanded() and not WorldMapFrame:IsShown(), "M grows our window instead of opening Blizzard's map")
	check(ns.frame:GetWidth() > smallW * 2 and ns.frame:GetParent() == UIParent, "to most of the screen")
	check(ns.state.follow and ns.state.zoom < smallZoom and ns.state.zoom >= smallZoom / 1.5 - 0.5,
		"still on you, zoomed out only a little")
	ToggleWorldMap()
	Sim.Run(1)
	check(not ns.IsMapExpanded() and math.abs(ns.frame:GetWidth() - smallW) < 1, "M again shrinks it back")
	ToggleWorldMap()
	Sim.Run(1)
	ToggleWorldMap()
	Sim.Run(0.05) -- M again while it's still shrinking
	ToggleWorldMap()
	Sim.Run(1)
	ToggleWorldMap()
	Sim.Run(1)
	check(math.abs(ns.frame:GetWidth() - smallW) < 1, "pressing M mid-shrink still comes back to the minimap's size")
	ToggleWorldMap()
	Sim.Run(1)
	_G.MagicMapWorldMapEscape:Hide() -- Escape
	Sim.Run(1)
	check(not ns.IsMapExpanded(), "Escape shrinks it back too")
	-- The quest log opens Blizzard's world map as usual, ours untouched.
	if ToggleQuestLog then ToggleQuestLog() else WorldMapFrame:Show() end
	Sim.Run(1)
	check(WorldMapFrame:IsShown() and not ns.IsMapExpanded(), "the quest log opens Blizzard's world map as usual")
	check(ns.frame:GetParent() == UIParent and math.abs(ns.frame:GetWidth() - smallW) < 1, "ours stays the minimap")
	ToggleWorldMap() -- M closes it, as usual
	Sim.Run(1)
	check(not WorldMapFrame:IsShown() and not ns.IsMapExpanded(), "M closes Blizzard's map rather than growing ours")
	check(ns.frame:GetFrameStrata() == MinimapCluster:GetFrameStrata(), "at the minimap's strata again")
	check(ns.frame:IsShown(), "...without closing the minimap")
	-- Rotating minimap: hands the Minimap back.
	Sim.cvars.rotateMinimap = "1"
	Sim.Run(0.5)
	check(Minimap:GetParent() == parent, "rotate minimap gives the Minimap back")
	Sim.cvars.rotateMinimap = "0"
	Sim.Run(0.5)
	Sim.FireEvent("PLAYER_LOGOUT")
	-- Off again with the back button: everything goes home.
	Sim.Click(ns.modeButton)
	Sim.Run(1)
	check(not ns.IsMinimapMode(), "minimap mode is off")
	check(Minimap:GetParent() == parent, "the Minimap is back in its cluster")
	check(Minimap:GetAlpha() == 1, "its terrain is visible again")
	check(not Sim.minimapMask:find("WHITE8X8") and Sim.rimInset == nil and Sim.BlobRingsAt(1), "round again, its arrows and rings back")
	check(math.abs(Minimap:GetWidth() - 140) < 0.01, "at its own size")
	check(Sim.minimapButton:GetParent() == Minimap, "addon buttons are back on the Minimap")
	check(MinimapCluster:IsShown() and _G.MinimapBorder:IsVisible(), "the minimap cluster is shown again")
	check(Sim.minimapButton:IsVisible(), "addon buttons are visible again")
end

-- Where the Minimap's blips may show: its mask's opaque square (screen
-- left, bottom, side), centred on it.
local function BlipSquare()
	local cx, cy = Minimap:GetCenter()
	local w = Minimap:GetWidth()
	local n = Sim.minimapMask:match("Square(%d+)$")
	local side = n and w * tonumber(n) / 64 or w
	return cx - side / 2, cy - side / 2, side
end

local function InsideWindow(l, b, side)
	local vl, vb, vw, vh = ns.viewport:GetRect()
	return l >= vl - 1 and b >= vb - 1 and l + side <= vl + vw + 1 and b + side <= vb + vh + 1
end

-- The Minimap bigger than the window, its blips kept inside it by masks.
scenarios.minimap_clip = function()
	local parent = Minimap:GetParent()
	Sim.Click(ns.modeButton)
	Sim.Run(2)
	-- Zoomed in close: Blizzard's closest level is far bigger than the window.
	ns.SetZoom(1500)
	Sim.Run(1)
	check(ns.MinimapShowsPlayer() and Minimap:GetZoom() == 5, "zoomed in close, the Minimap still shows, at its closest level")
	local l, b, side = BlipSquare()
	check(Minimap:GetWidth() > ns.viewport:GetWidth() and InsideWindow(l, b, side),
		"bigger than the window, its mask keeps the blips inside it")
	check(side > 0.8 * math.min(ns.viewport:GetSize()) - 4, "in about the biggest square around you that fits")
	local il, ir, it, ib = Minimap:GetHitRectInsets()
	check(math.abs(il - (Minimap:GetWidth() - side) / 2) < 1 and math.abs(ib - il) < 1, "hover reaches it only in that square")
	-- Off-centre (panned away from you): the square shrinks to the room left.
	ns.SetZoom(400)
	Sim.Run(1)
	local _, _, wide = BlipSquare()
	Sim.Drag(ns.viewport, 30, 0)
	Sim.Run(0.5)
	l, b, side = BlipSquare()
	check(ns.MinimapShowsPlayer() and InsideWindow(l, b, side) and side < wide, "off-centre, a smaller square, still inside")
	ns.SetFollow(true)
	Sim.Run(1)
	Sim.Click(ns.modeButton)
	Sim.Run(1)
	check(Minimap:GetParent() == parent and Minimap:GetHitRectInsets() == 0, "leaving minimap mode, it's back, all of it hoverable")
	check(Sim.gatherPin:GetParent() == Minimap and not _G.MagicMapMinimapPins:IsVisible(), "and the pins are back on it")
end

-- The plan's maths, on its own: which Minimap zoom level, and which mask.
scenarios.minimap_plan = function()
	local P = ns.MinimapPlan
	local YARDS = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
	local zoom = 200
	local function px(level) return YARDS[level] * zoom / (1600 / 3) end -- 175 .. 50 px
	check(P.Level("outdoor", zoom, 300, false) == 0, "unmasked, room for its widest: the widest")
	local l = P.Level("outdoor", zoom, 100, false)
	check(l and px(l) <= 100 and px(l - 1) > 100, "unmasked: the widest level whose square fits")
	check(P.Level("outdoor", zoom, 40, false) == nil, "unmasked: none if even the closest won't fit")
	check(P.Level("outdoor", zoom, 40, true) == 5, "masked: the closest level, which covers the room")
	l = P.Level("outdoor", zoom, 120, true)
	check(l and px(l) >= 120 and (l == 5 or px(l + 1) < 120), "masked: the closest level that still covers the room")
	check(P.Level("outdoor", zoom, 1000, true) == 0, "masked: its widest when even that fits")
	local mask, side = P.Mask(90, 100, true)
	check(mask == "Interface\\Buttons\\WHITE8X8" and side == 90, "fits the room: plain square, all of it")
	mask, side = P.Mask(300, 100, true)
	check(mask and mask:find("MinimapMask\\Square%d+$") and side <= 98 and side > 98 - 3 * 300 / 64,
		"bigger: a mask about the room's size (masks come in steps of 2 texels)")
	check(P.Mask(300, 100, false) == nil, "bigger without masks: not shown")
	check(P.Mask(3000, 100, true) == nil, "far bigger: no mask is small enough")
end

-- Everything minimap mode changes on Blizzard's side, as text: compared
-- before and after a round of everything that engages and releases it.
local function MinimapSnapshot()
	local out = {}
	local function add(key, ...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		out[#out + 1] = key .. " = " .. table.concat(parts, ", ")
	end
	local function frame(name, f)
		add(name .. " parent", f:GetParent())
		for i = 1, f:GetNumPoints() do add(name .. " point " .. i, f:GetPoint(i)) end
		add(name .. " size", f:GetSize())
		add(name .. " shown", f:IsShown())
		add(name .. " alpha", f:GetAlpha())
		if f.GetFrameStrata then add(name .. " strata", f:GetFrameStrata(), f:GetFrameLevel()) end
	end
	frame("Minimap", Minimap)
	add("Minimap scale", Minimap:GetScale())
	add("Minimap zoom", Minimap:GetZoom())
	add("Minimap mouse", Minimap:IsMouseEnabled(), Minimap:IsMouseWheelEnabled())
	add("Minimap clamped", Minimap:IsClampedToScreen())
	add("Minimap hit", Minimap:GetHitRectInsets())
	frame("MinimapCluster", MinimapCluster)
	for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapZoneTextButton" }) do frame(name, _G[name]) end
	frame("button", Sim.minimapButton)
	add("gather pin parent", Sim.gatherPin:GetParent())
	for _, t in ipairs(Sim.tracking or {}) do add("tracking " .. t.name, t.active) end
	return out
end

scenarios.minimap_restores_everything = function()
	local before = MinimapSnapshot()
	Sim.Click(ns.modeButton)
	Sim.Run(2)
	check(ns.Takeover.IsEngaged(), "minimap mode takes the Minimap")
	ns.Takeover.Engage() -- twice is once
	ns.SetZoom(1500) -- masked
	Sim.Run(1)
	Sim.Slash("sync")
	Sim.Run(0.5)
	Sim.Slash("sync")
	Sim.indoors = true
	Sim.Run(1)
	Sim.indoors = false
	Sim.Run(1)
	ToggleWorldMap() -- grown
	Sim.Run(1)
	ToggleWorldMap()
	Sim.Run(1)
	Sim.cvars.rotateMinimap = "1" -- given back...
	Sim.Run(0.5)
	check(not ns.Takeover.IsEngaged(), "rotate minimap releases it")
	Sim.cvars.rotateMinimap = "0" -- ...and taken again
	Sim.Run(1)
	ns.frame:Hide()
	Sim.Run(0.2)
	check(not ns.Takeover.IsEngaged(), "closing the map releases it")
	ns.frame:Show()
	Sim.Run(1)
	check(ns.Takeover.IsEngaged(), "and opening it takes it again")
	Sim.Click(ns.modeButton)
	Sim.Run(1)
	ns.Takeover.Release() -- twice is once
	check(not ns.Takeover.IsEngaged(), "leaving minimap mode releases it")
	local after = MinimapSnapshot()
	local diffs = {}
	for i = 1, math.max(#before, #after) do
		if before[i] ~= after[i] then diffs[#diffs + 1] = tostring(before[i]) .. "  ->  " .. tostring(after[i]) end
	end
	check(#diffs == 0, "everything is back as it was:\n    " .. table.concat(diffs, "\n    "))
end

-- Ours first: Blizzard's own markers for what we draw go off while the
-- Minimap is in the map; the tooltip goes to our pins, then its blips, then
-- the quest area.
scenarios.minimap_ours_first = function()
	if not (C_Minimap and C_Minimap.SetTracking) then return end
	local function Active(name)
		for _, t in ipairs(Sim.tracking) do
			if t.name == name then return t.active end
		end
	end
	Sim.Click(ns.modeButton)
	ns.SetZoom(160)
	Sim.Run(2)
	check(not Active("Flight Master") and not Active("Track Quest POIs"), "Blizzard's flight masters and quest objectives go off")
	check(Active("Find Herbs") and Active("Mailbox") and not Active("Points of Interest"), "the rest of its tracking is untouched")
	MagicMapDB.layers.flight = false
	Sim.Run(2.5)
	check(Active("Flight Master"), "with our flight points off, Blizzard's flight masters come back")
	MagicMapDB.layers.flight = true
	Sim.Run(2.5)
	check(not Active("Flight Master"), "and go again with ours")
	Sim.Slash("dupes")
	Sim.Run(0.2)
	check(Active("Flight Master") and Active("Track Quest POIs"), "/mm dupes keeps Blizzard's")
	Sim.Slash("dupes")
	Sim.Run(0.2)
	check(not Active("Flight Master"), "/mm dupes again: ours only")
	Sim.indoors = true
	Sim.Run(1)
	check(Active("Flight Master") and Active("Track Quest POIs"), "indoors (Blizzard's minimap whole) its markers are back")
	Sim.indoors = false
	Sim.Run(1)
	check(not Active("Flight Master"), "outdoors again, ours")
	Sim.FireEvent("PLAYER_LOGOUT")
	check(Active("Flight Master") and Active("Track Quest POIs") and not next(MagicMapDB.trackingOff),
		"logging out puts them back (and they're saved that way)")
	Sim.Run(2.5)

	-- Tooltips over a quest area (where the client draws quest areas).
	if Sim.flavor == "retail" then
		local function Line1() return _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText() end
		Sim.MoveCursorTo(Minimap, 0.5, 0.5)
		Sim.questUnderCursor = 60
		Sim.Run(0.3)
		check(GameTooltip:IsShown() and Line1() == "Kobold Candles", "over a quest area, the quest's tooltip")
		Sim.FireScript(Minimap, "OnEnter", false)
		Sim.blip = "Peacebloom"
		local steady = true
		for _ = 1, 10 do
			Sim.Step()
			steady = steady and GameTooltip:IsShown() and Line1() == "Peacebloom"
		end
		check(steady, "a Blizzard blip under the cursor wins over the quest area, every frame")
		Sim.blip = nil
		steady = true
		for _ = 1, 10 do
			Sim.Step()
			steady = steady and GameTooltip:IsShown() and Line1() == "Kobold Candles"
		end
		check(steady, "off the blip, the quest area's again, every frame (no flicker)")
		Sim.FireScript(Minimap, "OnLeave", false)
		Sim.Run(0.2)
		check(GameTooltip:IsShown() and Line1() == "Kobold Candles", "off the Minimap, the quest area keeps it")
		Sim.questUnderCursor = nil
		Sim.Run(0.2)
		check(not GameTooltip:IsShown(), "and lets go off the area")
	end
	local pin = QuestPin(60)
	-- (Same strata in the client, which hands a frame's strata down to its children.)
	check(pin and pin:GetFrameLevel() > Minimap:GetFrameLevel(),
		"our pins sit above the Minimap, so they take the mouse first")

	Sim.Click(ns.modeButton)
	Sim.Run(1)
	check(Active("Flight Master") and Active("Track Quest POIs") and not Active("Points of Interest"),
		"leaving minimap mode puts Blizzard's tracking back as it was")
	check(not next(MagicMapDB.trackingOff), "and forgets what it turned off")
end

-- Party members: dots at their positions, moving with them.
scenarios.group_members = function()
	local function Dot()
		for _, f in ipairs(Sim.Frames()) do
			if f.unit == "party1" and f:IsVisible() then return f end
		end
	end
	local function At(dot, col, row)
		local x, y = ns.TileToScreen(col, row)
		local cx, cy = dot:GetCenter()
		return math.abs(cx - (ns.viewport:GetLeft() + x)) < 1 and math.abs(cy - (ns.viewport:GetTop() - y)) < 1
	end
	check(Dot() == nil, "alone, no party dots")
	Sim.units.party1 = { name = "Friend", class = "PRIEST", level = 6, col = Sim.player.col + 0.05, row = Sim.player.row }
	Sim.group = { "party1" }
	Sim.Run(0.2)
	local dot = Dot()
	check(dot and At(dot, Sim.units.party1.col, Sim.units.party1.row), "a party member shows where they are")
	Sim.units.party1.row = Sim.units.party1.row + 0.04
	Sim.Run(0.1)
	check(dot and At(dot, Sim.units.party1.col, Sim.units.party1.row), "and moves with them")
	if dot then
		Sim.Hover(dot)
		check(_G.GameTooltipTextLeft1:GetText() == "Friend", "hovering shows who it is")
	end
	MagicMapDB.layers.group = false
	Sim.Run(0.1)
	check(Dot() == nil, "the layer turned off hides them")
	MagicMapDB.layers.group = true
	Sim.restricted = true
	Sim.Run(0.1)
	check(Dot() == nil, "where positions are withheld, none")
	Sim.restricted = false
	Sim.group = {}
	Sim.Run(0.1)
	check(Dot() == nil, "leaving the group clears them")
end

-- Quests to pick up (the world map's quest offers).
scenarios.quest_offers = function()
	if not C_QuestLine then return end
	local function Offer()
		for _, f in ipairs(Sim.Frames()) do
			if f.entry and f.entry.title == "Wolves Across the Border" and f:IsVisible() then return f end
		end
	end
	Sim.Run(1.5)
	check(Sim.offersAsked[1429], "the zone's quest offers are asked for")
	check(Offer() ~= nil, "and drawn once the client has them")
	Sim.offers[1429][1].inProgress = true
	Sim.FireEvent("QUEST_LOG_UPDATE")
	Sim.Run(1)
	check(Offer() == nil, "once taken, it's no longer offered")
end

scenarios.quests_and_path = function()
	Sim.Run(2)
	-- Click the Elwynn quest's pin: Kobold Candles.
	local pin = QuestPin(60)
	check(pin ~= nil, "the Elwynn quest has a pin")
	if pin then
		Sim.Hover(pin)
		ClickOn(pin)
		Sim.Run(0.5)
		check(ns.GetTarget() ~= nil, "clicking a quest makes it the target")
		check(ns.state.path, "and turns on path mode")
		ns.SetZoom(2000) -- close in, the quest is off the map: an arrow on the edge points to it
		Sim.Run(1)
		local edge
		for _, r in ipairs({ ns.overlay:GetRegions() }) do
			if tostring(S[r].texture):find("GUIDEARROW") and r:IsVisible() then edge = r end
		end
		check(edge ~= nil, "an off-map target gets an arrow on the map's edge")
		check(Sim.watched == 60 or Sim.watchedIndex ~= nil, "the quest is tracked")
		Sim.Run(2)
		-- Path mode: at your zoom, you sit off-centre toward the target.
		local st, t = ns.state, ns.GetTarget()
		local w, h = ns.viewport:GetSize()
		local ox, oy = (st.cx - st.playerCol) * st.zoom, (st.cy - st.playerRow) * st.zoom
		local tx, ty = t.col - st.playerCol, t.row - st.playerRow
		check(st.path and st.follow, "path mode is on, still following you")
		check(st.zoom == 2000, "it keeps your zoom")
		check(ox * tx + oy * ty > 0, "the view leans toward the target")
		check(math.abs(math.sqrt(ox * ox + oy * oy) - 0.35 * math.min(w, h)) < 3, "as far as path mode leans, with the target off the map")
		Sim.Click(ns.mapControls.path)
		Sim.Run(2)
		check(not st.path and math.abs(st.cx - st.playerCol) * st.zoom < 1, "path mode off: back to centred on you")
		Sim.Click(ns.mapControls.path)
		Sim.player.speed, Sim.player.facing = 200, 2.5
		Sim.Run(4)
		Sim.player.speed = 0
		pin = QuestPin(60)
		if pin then
			ClickOn(pin) -- again: unfollow
			Sim.Run(1)
			check(ns.GetTarget() == nil, "clicking it again stops following it")
			check(not ns.state.path, "and turns off path mode")
		end
	end
	-- Hover over zones and pins.
	for _, fx in ipairs({ 0.2, 0.5, 0.8 }) do
		Sim.MoveCursorTo(ns.viewport, fx, 0.5)
		Sim.Run(0.2)
	end
	-- Ctrl-click: waypoint; ctrl-right-click clears it.
	Sim.modifiers.ctrl = true
	Sim.Click(ns.viewport, "LeftButton", 0.6, 0.4)
	Sim.Run(0.5)
	if ns.CanSetWaypoints() then check(ns.state.path, "a ctrl-click waypoint turns on path mode") end
	Sim.Click(ns.viewport, "RightButton", 0.6, 0.4)
	Sim.modifiers.ctrl = false
	Sim.Run(0.5)
	check(not ns.state.path, "clearing the waypoint turns it off")
	-- Right-click, "Waypoint here": it's your target, and path mode leans to it.
	ns.SetFollow(false) -- looking around: the menu's waypoint brings you back
	Sim.Click(ns.viewport, "RightButton", 0.7, 0.3)
	if ns.CanSetWaypoints() then
		check(PickMenu("Waypoint here"), "right-click offers a waypoint")
		Sim.Run(2)
		check(Sim.waypoint ~= nil and ns.GetTarget() ~= nil, "the waypoint is your target")
		check(ns.state.path and ns.state.follow, "and path mode is on")
		Sim.Click(ns.viewport, "RightButton", 0.5, 0.5)
		check(PickMenu("Clear waypoint"), "right-click offers to clear it")
		Sim.Run(1)
		check(Sim.waypoint == nil, "and that clears it")
		check(not ns.state.path, "and turns off path mode")
	end
	-- Click a zone to fly there.
	Sim.Click(ns.viewport, "LeftButton", 0.3, 0.6)
	Fly()
end

-- Dying: once the client knows where your corpse is (a while after you
-- release, with no event), it shows, becomes your target, and the view
-- follows you, leaning toward it. Back alive, it's gone and so is path mode.
scenarios.corpse = function()
	Sim.Run(2)
	local st = ns.state
	ns.SetFollow(false)
	st.cx = st.cx + 2 -- looking elsewhere
	Sim.FireEvent("PLAYER_DEAD")
	Sim.ghost = true
	Sim.FireEvent("PLAYER_ALIVE") -- released, the corpse not placed yet
	Sim.Run(1.5)
	check(ns.GetTarget() == nil, "no corpse known yet: no target")
	local x, y = ns.TileToMap(1429, st.playerCol + 0.4, st.playerRow + 0.2)
	Sim.corpse = { [1429] = CreateVector2D(x, y) }
	Sim.Run(3)
	local t = ns.GetTarget()
	check(t ~= nil and t.title == "Your corpse", "the corpse turns up without a toggle, as your target")
	check(st.path and st.follow, "path mode on, following you again")
	check(math.abs(st.cx - st.playerCol) < 1, "the view came back to you")
	Sim.ghost, Sim.corpse = false, nil
	Sim.FireEvent("PLAYER_UNGHOST")
	Sim.Run(2)
	check(ns.GetTarget() == nil and not st.path, "alive again: no corpse, path mode off")
end

-- The open layers menu's rows in order, from the client's menu (MenuUtil)
-- or our fallback: { title = text } or { key, text, checked, enabled, tip, indent, toggle }.
local function LayerRows()
	local rows = {}
	if Sim.menu then
		for _, e in ipairs(Sim.MenuItems()) do
			if e.kind == "title" or (e.kind == "button" and #e.items > 0) then
				rows[#rows + 1] = { title = e.text }
			elseif e.kind == "checkbox" then
				rows[#rows + 1] = { key = e.data, text = e.text, checked = e.isSelected(), enabled = e:IsEnabled(),
					tip = e.tooltip, indent = e.text:match("^ +") ~= nil,
					toggle = function() Sim.Call("menu " .. e.text, e.onSelect, e.data) end }
			end
		end
		return rows
	end
	-- Our own (Menu.lua): its rows were created top to bottom.
	for _, f in ipairs(Sim.Frames()) do
		local it = f.item
		if it and f:IsVisible() and f:GetParent() and f:GetParent():GetParent() == ns.gearButton then
			if it.value == nil then
				rows[#rows + 1] = { title = it.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") }
			else
				rows[#rows + 1] = { key = it.value, text = it.text, checked = it.checked, enabled = not it.disabled,
					tip = it.tip, indent = (it.indent or 0) > 0, toggle = function() Sim.Click(f) end }
			end
		end
	end
	return rows
end

local function LayersOpen() return Sim.menu ~= nil or #LayerRows() > 0 end
local function CloseLayers()
	if not LayersOpen() then return end
	if Sim.menu then Sim.menu = nil else Sim.Click(ns.gearButton) end
end
local function OpenLayers()
	CloseLayers()
	Sim.Click(ns.gearButton)
	Sim.Run(0.3)
	return LayerRows()
end

local function FindRow(rows, key)
	for i, r in ipairs(rows) do
		if r.key == key then return r, i end
	end
end

scenarios.layers = function()
	Sim.Run(2)
	Sim.Slash("layers")
	local printed = Sim.prints[#Sim.prints] or ""
	check(printed:find("Map:", 1, true) and printed:find("You:", 1, true), "/mm layers lists them by group: " .. printed)
	Sim.Run(0.5)

	-- Sections in order, each with its layers.
	local rows = OpenLayers()
	local want = {
		{ "Map", "zoneLabels", "zoneBorders", "unexplored" },
		{ "Quests", "quests", "questAreas", "questAreasApprox", "offers" },
		{ "Places", "flight", "dungeons", "graveyards", "areaPOIs", "services" },
		{ "People", "group", "rares", "vignettes" },
		{ "You", "corpse", "waypoint" },
	}
	local i = 1
	for _, sec in ipairs(want) do
		check(rows[i] and rows[i].title == sec[1], "section " .. sec[1] .. " at row " .. i .. ", got " .. tostring(rows[i] and (rows[i].title or rows[i].key)))
		for k = 2, #sec do
			i = i + 1
			check(rows[i] and rows[i].key == sec[k], sec[1] .. ": " .. sec[k] .. " at row " .. i .. ", got " .. tostring(rows[i] and (rows[i].title or rows[i].key)))
		end
		i = i + 1
	end
	check(rows[i] == nil or rows[i].title == "Other addons", "only other addons may follow, got " .. tostring(rows[i] and (rows[i].title or rows[i].key)))
	local approx = FindRow(rows, "questAreasApprox")
	check(approx and approx.indent and approx.text:find("Estimate missing areas", 1, true), "the estimate is a short, indented sub-option")
	check(approx and approx.tip ~= nil, "with the long explanation as a tooltip")
	if Sim.menu and approx then
		approx.tip(GameTooltip)
		check(GameTooltip:NumLines() >= 2, "the tooltip has a title and the explanation")
	end

	-- A sub-option is greyed while its parent is off.
	check(approx and approx.enabled, "the estimate is usable while quest areas are on")
	FindRow(rows, "questAreas").toggle()
	Sim.Run(0.4)
	rows = LayerRows()
	check(not MagicMapDB.layers.questAreas and not FindRow(rows, "questAreasApprox").enabled, "and greyed while they're off")
	check(not ns.LayerEnabled("questAreasApprox") and MagicMapDB.layers.questAreasApprox, "off in effect, the setting kept")
	FindRow(rows, "questAreas").toggle()
	Sim.Run(0.4)
	rows = LayerRows()
	check(MagicMapDB.layers.questAreas and FindRow(rows, "questAreasApprox").enabled, "usable again once they're back")

	-- Toggle every layer off and on; the menu stays open and follows.
	local toggled = 0
	for _, r in ipairs(rows) do
		if r.key then
			local before = MagicMapDB.layers[r.key]
			r.toggle()
			Sim.Run(0.4)
			check(MagicMapDB.layers[r.key] ~= before, "toggling " .. r.key .. " flips it")
			check(LayersOpen(), "the menu stays open after toggling " .. r.key)
			FindRow(LayerRows(), r.key).toggle()
			Sim.Run(0.4)
			check(MagicMapDB.layers[r.key] == before, "and back")
			toggled = toggled + 1
		end
	end
	check(toggled >= 17, "every layer has a toggle, got " .. toggled)

	-- Another addon's layer, added after login: under "Other addons", from its default.
	local calls = {}
	ns.AddLayer({ key = "addon:Test", label = "Test pins", group = "addons", default = true,
		tip = "Pins from Test.", onToggle = function(on) calls[#calls + 1] = on end })
	check(MagicMapDB.layers["addon:Test"] == true, "a late layer starts from its default")
	rows = OpenLayers()
	local row, at = FindRow(rows, "addon:Test")
	local head
	for k = (at or 1), 1, -1 do
		if rows[k].title then head = rows[k].title break end
	end
	check(row and row.checked and head == "Other addons", "it shows under Other addons, on (heading " .. tostring(head) .. ")")
	if row then
		row.toggle()
		Sim.Run(0.4)
		check(MagicMapDB.layers["addon:Test"] == false and calls[1] == false, "toggling it calls onToggle(false)")
		FindRow(LayerRows(), "addon:Test").toggle()
		check(calls[2] == true, "and onToggle(true)")
	end
	-- Again with the same key: updated, not duplicated.
	ns.AddLayer({ key = "addon:Test", label = "Test pins (renamed)", group = "addons", default = false })
	rows = OpenLayers()
	local n = 0
	for _, r in ipairs(rows) do if r.key == "addon:Test" then n = n + 1 end end
	row = FindRow(rows, "addon:Test")
	check(n == 1 and row and row.text:find("renamed", 1, true) and row.checked, "re-adding renames it, once, keeping the setting")
	CloseLayers()
	check(not LayersOpen(), "the menu closes")
	Sim.Run(2)
end

scenarios.landmarks = function()
	Sim.units.target = { name = "Brog Hamfist", npc = true, guid = "Creature-0-0-0-0-1234-0" }
	Sim.unitSubtitle.target = "<General Supplies>"
	Sim.units.npc = Sim.units.target
	Sim.unitSubtitle.npc = "<General Supplies>"
	Sim.FireEvent("PLAYER_TARGET_CHANGED")
	for _, e in ipairs({ "MERCHANT_SHOW", "GOSSIP_SHOW", "TRAINER_SHOW", "BANKFRAME_OPENED", "MAIL_SHOW", "CONFIRM_BINDER",
		"VIGNETTES_UPDATED", "AREA_POIS_UPDATED", "QUEST_LOG_UPDATE", "MAP_EXPLORATION_UPDATED" }) do
		Sim.FireEvent(e)
		Sim.Run(0.4)
	end
	Sim.Slash("landmarks")
	check(next(MagicMapLandmarks or {}) ~= nil, "a vendor visit is remembered")
end

scenarios.window = function()
	ns.frame:Hide()
	Sim.Run(0.5)
	check(not MagicMapDB.shown, "closing is remembered")
	Sim.Slash("")
	Sim.Run(0.5)
	check(ns.frame:IsShown(), "/mm opens it")
	ns.frame:SetSize(300, 200)
	Sim.Run(1)
	ns.frame:SetSize(1400, 900)
	Sim.Run(1)
	MagicMap_OnAddonCompartmentClick()
	Sim.Run(0.2)
	MagicMap_OnAddonCompartmentClick()
	Sim.Run(0.5)
	Sim.FireEvent("PLAYER_LOGOUT")
end

-- Border lines on a buffer canvas, as "x1,y1,x2,y2" keys (the zone borders
-- only: sublevel 1).
local function BorderSegments(canvas)
	local keys, dupes = {}, 0
	for _, r in ipairs(S[canvas].regions) do
		local st = S[r]
		if st.type == "Line" and st.shown and st.sublevel == 1 and st.startPoint and st.endPoint then
			local key = string.format("%.2f,%.2f,%.2f,%.2f", st.startPoint[3], st.startPoint[4], st.endPoint[3], st.endPoint[4])
			if keys[key] then dupes = dupes + 1 end
			keys[key] = true
		end
	end
	return keys, dupes
end

-- Fling the map around at street zoom with the border builder paying what
-- it would in the client (a few microseconds a widget call), and check the
-- borders keep up, and that growing them in place draws exactly what a
-- fresh build would, once.
scenarios.borders_keep_up = function()
	Sim.CountCalls()
	function debugprofilestop() return os.clock() * 1000 + Sim.callTotal * 0.003 end
	ns.SetZoom(160)
	Sim.Run(1)
	local frames, gaps = 0, 0
	local step = Sim.Step
	Sim.Step = function(elapsed)
		step(elapsed)
		frames = frames + 1
		if not ns.GeometryInfo().covers then gaps = gaps + 1 end
	end
	for i = 1, 12 do
		local dir = i % 4
		Sim.Drag(ns.viewport, ({ 600, 0, -600, 0 })[dir + 1], ({ 0, 400, 0, -400 })[dir + 1], 12)
		Sim.Run(0.1)
	end
	Sim.Run(1)
	Sim.Step = step
	check(gaps <= frames * 0.02, ("borders cover the view while panning (%d of %d frames short)"):format(gaps, frames))

	local g = ns.GeometryInfo()
	local grown, dupes = BorderSegments(g.canvas)
	check(dupes == 0, ("no border drawn twice (%d duplicates)"):format(dupes))
	ns.LayoutStatic() -- a fresh build, same view and zoom
	Sim.Run(1)
	local fresh = BorderSegments(ns.GeometryInfo().canvas)
	local missing, total = 0, 0
	for key in pairs(fresh) do
		total = total + 1
		if not grown[key] then missing = missing + 1 end
	end
	check(total > 0, "there are borders to compare")
	check(missing == 0, ("grown borders hold everything a fresh build draws (%d of %d missing)"):format(missing, total))
end

-- Tiles are whole pixels in size, and neighbours share their edges exactly
-- (no seams or overlaps), after panning and zooming by odd amounts. (Where
-- they sit isn't rounded: the map moves smoothly, by fractions of a pixel.)
scenarios.tiles_seamless = function()
	for _, step in ipairs({ { 137, -61, 1 }, { -333, 245, -1 }, { 71, 19, 1 }, { 5, -3, 1 } }) do
		Sim.Drag(ns.viewport, step[1], step[2], 7)
		Sim.Wheel(ns.viewport, step[3])
		Sim.Run(0.6)
		local edges, bad = {}, 0
		local function walk(f)
			for _, r in ipairs(S[f].regions) do
				if S[r].type == "Texture" and type(S[r].texture) == "number" and r:IsVisible() then
					local l, b, w, h = r:GetRect()
					if l then
						for _, v in ipairs({ w, h }) do
							if math.abs(v - math.floor(v + 0.5)) > 1e-6 then bad = bad + 1 end
						end
						edges[#edges + 1] = { l, l + w }
					end
				end
			end
			for _, c in ipairs(S[f].children) do walk(c) end
		end
		walk(ns.frame)
		check(#edges > 0, "tiles drawn")
		check(bad == 0, ("tiles whole pixels in size (%d fractional)"):format(bad))
		local near = 0
		for _, a in ipairs(edges) do
			for _, b in ipairs(edges) do
				local d = math.abs(a[2] - b[1])
				if d > 0 and d < 2 then near = near + 1 end
			end
		end
		check(near == 0, ("no hairline seams or overlaps between tiles (%d)"):format(near))
	end
end

-- Tile colour data (Data/TileColor_*.lua): tinted tiles get their vertex
-- colour and an additive overlay, open sides with a colour fade outward over
-- the empty cell (corners too), pooled textures come back plain, /mm tint
-- turns it all off, and none of it costs anything per frame.
scenarios.tile_colors = function()
	local map = ns.state.map
	local tiles = MagicMap_TileSets[next(MagicMap_TileSets)].maps[map].tiles
	MagicMap_TileColor = nil -- the flavor's own data, if any: this test brings its own
	ns.SetZoom(24)
	Sim.Run(2)
	local function Drawn(key) local t = ns.activeTiles[map * 4096 + key]; return t and t:IsVisible() and t end
	local function Open(key, d) return not tiles[key + d] end
	local function Shown(t) return t and t:IsVisible() end
	-- Drawn as it comes: no vertex colour (or white), no overlay or outward fades.
	local function Coloured(t)
		local v, n = S[t].vertex, 0
		if (v and (v[1] ~= 1 or v[2] ~= 1 or v[3] ~= 1)) or Shown(t.add) then n = n + 1 end
		for i = 1, 4 do if Shown(t.outs[i]) then n = n + 1 end end
		for j = 1, 4 do if t.corners[j] and (Shown(t.corners[j][1]) or Shown(t.corners[j][2])) then n = n + 1 end end
		if Shown(t.water) then n = n + 1 end
		return n
	end
	-- An interior tile and a coast tile with a convex corner (left and top
	-- open, and the cell between); every other tile is left without data.
	local inner, coast
	for key in pairs(tiles) do
		if Drawn(key) then
			if not inner and not (Open(key, -64) or Open(key, 64) or Open(key, -1) or Open(key, 1)) then
				inner = key
			elseif not coast and Open(key, -64) and Open(key, -1) and Open(key, -65) then
				coast = key
			end
		end
	end
	-- And a sea tile, with a drawn tile to its right, away from those two.
	local sea
	for key in pairs(coast and tiles or {}) do
		local far = math.abs(math.floor(key / 64) - math.floor(coast / 64)) > 2 or math.abs(key % 64 - coast % 64) > 2
		if not sea and far and key ~= inner and key + 64 ~= inner and Drawn(key) and Drawn(key + 64) then sea = key end
	end
	check(inner and coast and sea, "found interior, coast and sea tiles on screen")
	if not (inner and coast and sea) then return end

	local cl, ct, cr, cb = { 0.1, 0.4, 0.8 }, { 0.2, 0.5, 0.7 }, { 0.3, 0.3, 0.3 }, { 0.4, 0.4, 0.4 }
	local cs = { 0.15, 0.45, 0.75 }
	MagicMap_TileColor = { [map] = {
		tint = { [inner] = { 0.5, 0.6, 0.7, 0.1, 0.2, 0.3 } },
		edge = {
			[coast] = { l = cl, t = ct, r = Open(coast, 64) and cr or nil, b = Open(coast, 1) and cb or nil },
			[sea + 64] = { l = cs },
		},
		sea = { [sea] = true },
		water = { [inner] = true },
		waterDir = "Interface\\AddOns\\MagicMap\\Textures\\Water\\test\\",
	} }
	ns.state.dirty = true
	Sim.Run(0.2)

	local tex = Drawn(inner)
	local v = S[tex].vertex
	check(v and v[1] == 0.5 and v[2] == 0.6 and v[3] == 0.7, "a tinted tile is scaled by its vertex colour")
	local add = tex.add
	check(add and add:IsVisible() and S[add].blend == "ADD", "and lifted by an additive overlay")
	local c = add and S[add].color
	check(c and c[1] == 0.1 and c[2] == 0.2 and c[3] == 0.3, "the overlay has the tint's additive colour")
	local water = tex.water
	if add then
		local _, subTile = tex:GetDrawLayer()
		local _, subAdd = add:GetDrawLayer()
		local _, subFeather = tex.feathers[1]:GetDrawLayer()
		local subWater = water and select(2, water:GetDrawLayer())
		check(subWater and subTile < subAdd and subAdd < subWater and subWater < subFeather,
			"tile < overlay < water mask < feathers")
	end
	check(Shown(water) and S[water].texture == "Interface\\AddOns\\MagicMap\\Textures\\Water\\test\\" .. map .. "_" .. inner .. ".tga",
		"a tile with a water mask draws it, from its own file")
	local bg = MagicMap_TileSets[next(MagicMap_TileSets)].maps[map].bg or { 0.03, 0.06, 0.065 }
	local wv = water and S[water].vertex
	check(wv and wv[1] == bg[1] and wv[2] == bg[2] and wv[3] == bg[3], "the water mask is the backdrop's colour")

	tex = Drawn(coast)
	local expect = { cl, Open(coast, 64) and cr, ct, Open(coast, 1) and cb }
	for i, want in ipairs(expect) do
		local out = tex.outs[i]
		if want then
			local g = Shown(out) and S[out].gradient
			local opaque = g and (g[2].a == 1 and g[2] or g[3])
			check(opaque and opaque.r == want[1] and opaque.g == want[2] and opaque.b == want[3],
				"an open side fades its colour outward (side " .. i .. ")")
		else
			check(not Shown(out), "no outward fade on a side with a neighbour (side " .. i .. ")")
		end
	end
	check(Shown(tex.corners[1] and tex.corners[1][1]) and Shown(tex.corners[1][2]), "the open corner gets a corner piece")
	check(not Drawn(sea), "a sea tile isn't drawn")
	local out = Drawn(sea + 64).outs[1]
	local g = Shown(out) and S[out].gradient
	check(g and g[3].a == 1 and g[3].r == cs[1], "the tile beside it fades outward over it")
	local pieces = 0
	for key in pairs(tiles) do
		local t = Drawn(key)
		if t and key ~= coast and key ~= inner and key ~= sea + 64 then pieces = pieces + Coloured(t) end
	end
	check(pieces == 0, ("tiles without data are drawn plain, inward fades only (%d coloured)"):format(pieces))

	-- Nothing moves: no tile texture is touched from frame to frame.
	Sim.CountCalls()
	Sim.Run(1)
	local touched = 0
	for _, r in ipairs(S[ns.tileCanvas].regions) do touched = touched + (Sim.callsOn[r] or 0) end
	check(touched == 0, ("idle frames leave the tiles alone (%d calls)"):format(touched))
	ns.SetZoom(30)
	Sim.Run(1)
	touched = 0
	for _, r in ipairs(S[ns.tileCanvas].regions) do touched = touched + (Sim.callsOn[r] or 0) end
	check(touched > 0, "(and that count sees a zoom's layout)")
	ns.SetZoom(24)
	Sim.Run(2)

	-- Off: everything back to plain tiles.
	Sim.Slash("tint")
	Sim.Run(0.2)
	local left = 0
	for key in pairs(tiles) do
		local t = Drawn(key)
		if t then left = left + Coloured(t) end
	end
	check(left == 0, ("/mm tint off draws plain tiles (%d still coloured)"):format(left))
	check(Drawn(sea), "/mm tint off draws the sea tile again")
	Sim.Slash("tint")
	Sim.Run(0.2)
	check(Shown(Drawn(inner).add) and Shown(Drawn(coast).outs[1]) and Shown(Drawn(inner).water)
		and not Drawn(sea), "/mm tint on brings the colours back")

	-- Tinted textures go back to the pool and come out plain for another map.
	local was = {}
	for key in pairs(tiles) do
		if Drawn(key) then
			MagicMap_TileColor[map].tint[key] = { 0.5, 0.5, 0.5, 0.1, 0.1, 0.1 }
			MagicMap_TileColor[map].water[key] = true
			was[Drawn(key)] = true
		end
	end
	local old = MagicMap_TileColor[map]
	MagicMap_TileColor[map] = { tint = old.tint, edge = old.edge, water = old.water, waterDir = old.waterDir }
	ns.state.dirty = true
	Sim.Run(0.2)
	Sim.Slash("map 1")
	Sim.Run(2)
	Sim.Drag(ns.viewport, 400, 300, 10)
	Sim.Run(0.5)
	local dirty, reused = 0, 0
	for id, t in pairs(ns.activeTiles) do
		if t:IsVisible() and math.floor(id / 4096) == 1 then
			if was[t] then reused = reused + 1 end
			dirty = dirty + Coloured(t)
		end
	end
	check(reused > 0, "textures from the tinted map are reused")
	check(dirty == 0, ("reused textures come back plain (%d of %d not)"):format(dirty, reused))
	MagicMap_TileColor = nil
end

scenarios.perf_report = function()
	Sim.Slash("perf")
	Sim.Drag(ns.viewport, 300, 120, 20)
	Sim.Run(11)
	local found
	for _, msg in ipairs(Sim.prints) do
		if tostring(msg):find("borders: ", 1, true) then found = true end
	end
	check(found, "/mm perf reports after its recording")
end

-- The open right-click menu: info lines (MenuUtil titles, or the fallback's
-- disabled rows) without colour codes, action texts, and whether a divider
-- separates them.
local function MapMenu()
	local function Plain(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
	local info, actions, divider = {}, {}, false
	if Sim.menu then
		for _, e in ipairs(Sim.MenuItems()) do
			if e.kind == "title" then info[#info + 1] = Plain(e.text)
			elseif e.kind == "button" then actions[#actions + 1] = e.text
			elseif e.kind == "divider" then divider = true end
		end
	else
		for _, f in ipairs(Sim.Frames()) do
			local it = f.item
			if it and f:IsVisible() and f:GetParent():GetParent() == ns.viewport then
				if it.divider then divider = true
				elseif it.disabled then info[#info + 1] = Plain(it.text)
				else actions[#actions + 1] = it.text end
			end
		end
	end
	return info, actions, divider
end

-- Right-click on the big map: what's there on top (zone, place and
-- coordinates, levels and distance, quest areas, nearby landmarks), then the
-- usual actions. Compact (minimap mode) keeps to the actions.
scenarios.map_menu_info = function()
	Sim.Run(3) -- pins and quest areas settle
	ns.SetFollow(false)
	-- Over Kobold Candles' (estimated) area in Elwynn, east of you.
	local col, row = 32.28, 49.69
	ns.FlyTo(col, row, 400, 0.01)
	Sim.Run(0.5)
	Sim.Click(ns.viewport, "RightButton", 0.5, 0.5)
	local info, actions, divider = MapMenu()
	local text = table.concat(info, "\n")
	check(info[1] == "Elwynn Forest", "the menu opens with the zone's name, got " .. tostring(info[1]))
	check(#info >= 3 and #info <= 7, "a few info lines, got " .. #info .. ":\n" .. text)
	check(text:find("Goldshire", 1, true) and text:find("35.0, 55.0", 1, true), "the place and /way coordinates:\n" .. text)
	check(text:find("Level 1-10", 1, true), "the zone's level range:\n" .. text)
	check(text:find("180 yd E of you", 1, true), "how far and which way from you:\n" .. text)
	check(text:find("Quest Kobold Candles", 1, true), "the quest area under the click:\n" .. text)
	check(text:find("Graveyard Goldshire", 1, true), "the nearest graveyard:\n" .. text)
	check(divider, "a divider before the actions")
	check(actions[#actions] == "Follow me", "the actions follow the info")
	check(PickMenu("Waypoint here"), "the actions still work: waypoint here")
	Sim.Run(1)
	check(Sim.waypoint ~= nil and ns.state.follow, "and that sets the waypoint and follows you")
	Sim.Click(ns.viewport, "RightButton", 0.5, 0.5)
	check(PickMenu("Clear waypoint"), "clear waypoint is offered")
	Sim.Run(0.5)
	check(Sim.waypoint == nil, "and clears it")
	-- Unexplored ground says so (and a followed quest is marked).
	Sim.unexplored = true
	local pin = QuestPin(60)
	if pin then ClickOn(pin) Sim.Run(0.5) end
	ns.SetFollow(false)
	ns.FlyTo(col, row, 400, 0.01)
	Sim.Run(0.5)
	Sim.Click(ns.viewport, "RightButton", 0.5, 0.5)
	info = MapMenu()
	text = table.concat(info, "\n")
	check(text:find("Unexplored", 1, true), "an unexplored spot says so:\n" .. text)
	if pin then check(text:find("Kobold Candles (following)", 1, true), "the followed quest is marked:\n" .. text) end
	PickMenu("Follow me")
	Sim.unexplored = nil
	-- Minimap mode: just the actions, as before.
	Sim.Click(ns.modeButton)
	Sim.Run(2)
	check(ns.IsCompact(), "minimap mode is compact")
	Sim.Click(ns.viewport, "RightButton", 0.3, 0.3)
	info, actions = MapMenu()
	check(#info == 0 and actions[1] == "Waypoint here", "compact: the old menu, no info (" .. #info .. " lines)")
	PickMenu("Waypoint here")
	-- M grows it into a big map: the info is back.
	ToggleWorldMap()
	Sim.Run(1)
	check(ns.IsMapExpanded() and not ns.IsCompact(), "M grows it, not compact")
	Sim.Click(ns.viewport, "RightButton", 0.5, 0.5)
	info = MapMenu()
	check(info[1] ~= nil and #info >= 2, "expanded: the info is on top")
	PickMenu("Clear waypoint")
	ToggleWorldMap()
	Sim.Run(1)
end


---------------------------------------------------------------------------
-- Other addons' world-map pins (AddonPins.lua): Questie's renamed copy of
-- HereBeDragons-Pins, loaded after us.
---------------------------------------------------------------------------

-- Questie, with an icon in Elwynn (on Blizzard's map, which shows Elwynn),
-- one in Durotar and a route line (its zone map only).
local function LoadQuestie()
	local pins = Sim.LoadQuestie()
	Sim.FireEvent("ADDON_LOADED", "Questie")
	local icons = { elwynn = Sim.QuestieIcon(), durotar = Sim.QuestieIcon(), line = Sim.QuestieIcon() }
	pins:AddWorldMapIconMap(Questie, icons.elwynn, 1429, 0.5, 0.5, HBD_PINS_WORLDMAP_SHOW_WORLD)
	pins:AddWorldMapIconMap(Questie, icons.durotar, 1411, 0.5, 0.5, HBD_PINS_WORLDMAP_SHOW_WORLD)
	pins:AddWorldMapIconMap(Questie, icons.line, 1429, 0.4, 0.4, HBD_PINS_WORLDMAP_SHOW_CURRENT)
	Sim.Run(0.5)
	return pins, icons
end

-- How far (px) `icon` sits from where tile (col, row) is on our map.
local function PinOff(icon, col, row)
	local x, y = ns.TileToScreen(col, row)
	local cx, cy = icon:GetCenter()
	if not cx then return math.huge end
	return math.abs(cx - ns.viewport:GetLeft() - x) + math.abs(ns.viewport:GetTop() - cy - y)
end

local function OnOurMap(icon) return icon:GetParent() == _G.MagicMapAddonPins and icon:IsVisible() end

-- Back with the library: on its Blizzard map pin, or hidden in UIParent.
local function WithLibrary(icon)
	local p = icon:GetParent()
	return (p and p.icon == icon) or (p == UIParent and not icon:IsShown())
end

scenarios.addon_pins_questie = function()
	local _, icons = LoadQuestie()
	local _, col, row = ns.MapToTile(1429, 0.5, 0.5)
	local a = icons.elwynn
	check(OnOurMap(a), "Questie's Elwynn icon is on our map")
	check(PinOff(a, col, row) < 1, "at its spot (" .. PinOff(a, col, row) .. " px off)")
	check(a:GetWidth() == 16, "at its own size")
	check(a:GetFrameLevel() > ns.layerFrames.areas:GetFrameLevel() and a:GetFrameLevel() <= ns.overlay:GetFrameLevel(),
		"above quest areas, below the player marker (level " .. a:GetFrameLevel() .. ")")
	check(not OnOurMap(icons.durotar), "the Durotar icon (another continent) isn't")
	check(not OnOurMap(icons.line), "nor its route line (zone map only)")
	check(ns.LayerEnabled("addon:Questie") or not ns.AddLayer, "Questie has a layer, on")
	-- Zoom and pan: it keeps its spot and its size.
	ns.SetZoom(900)
	Sim.Run(0.3)
	check(PinOff(a, col, row) < 1, "zoomed in, still at its spot")
	check(a:GetWidth() == 16 and a:GetEffectiveScale() == ns.viewport:GetEffectiveScale(), "and not scaled with the map")
	ns.SetFollow(false)
	Sim.Drag(ns.viewport, 60, -40)
	Sim.Run(0.3)
	check(PinOff(a, col, row) < 1, "panned, still at its spot")
	-- Zoomed out to a continent: pins flagged for continents stay, zone pins go.
	local zonePin = Sim.QuestieIcon()
	Sim.questiePins:AddWorldMapIconMap(Questie, zonePin, 1429, 0.6, 0.6) -- no flag: its zone (and zone-type maps) only
	Sim.Run(0.3)
	check(OnOurMap(zonePin), "a zone-only pin shows close up")
	ns.SetZoom(20)
	Sim.Run(0.3)
	check(OnOurMap(a) and PinOff(a, col, row) < 1, "zoomed out to the continent, shown (flagged for the world map)")
	check(not OnOurMap(zonePin) and WithLibrary(zonePin), "the zone-only pin isn't, at continent scale")
	ns.SetZoom(400)
	Sim.Run(0.3)
	local _, zc, zr = ns.MapToTile(1429, 0.6, 0.6)
	check(OnOurMap(zonePin) and PinOff(zonePin, zc, zr) < 1, "and is back, in place, zoomed in again")
	-- Its turn-in for a quest whose turn-in we draw repeats ours: skipped. Its
	-- quests to pick up (ours don't cover them) stay.
	check(ns.ShowsTurnIn(62), "our quests layer shows quest 62's turn-in")
	local turnIn, offer = Sim.QuestieIcon(), Sim.QuestieIcon()
	turnIn.data = { Type = "complete", Id = 62 }
	offer.data = { Type = "available", Id = 999 }
	Sim.questiePins:AddWorldMapIconMap(Questie, turnIn, 1429, 0.40, 0.80, HBD_PINS_WORLDMAP_SHOW_WORLD)
	Sim.questiePins:AddWorldMapIconMap(Questie, offer, 1429, 0.45, 0.70, HBD_PINS_WORLDMAP_SHOW_WORLD)
	Sim.Run(0.3)
	check(not OnOurMap(turnIn) and OnOurMap(offer), "Questie's repeat of our turn-in is skipped, its quest offer kept")
	-- Added later: shows up shortly.
	local b = Sim.QuestieIcon()
	Sim.questiePins:AddWorldMapIconMap(Questie, b, 1436, 0.5, 0.5, HBD_PINS_WORLDMAP_SHOW_WORLD)
	Sim.Run(0.3)
	check(OnOurMap(b), "a pin added later joins our map")
	-- Removed: gone from ours.
	Sim.questiePins:RemoveWorldMapIcon(Questie, b)
	b:Hide() -- (Questie unloads it)
	Sim.Run(0.3)
	check(b:GetParent() ~= _G.MagicMapAddonPins and not b:IsVisible(), "a removed pin leaves our map")
	-- Another continent: only that continent's pins.
	Sim.Slash("map 1")
	Sim.Run(0.5)
	check(ns.state.map == 1, "showing Kalimdor")
	check(OnOurMap(icons.durotar), "on Kalimdor, the Durotar icon shows")
	check(not OnOurMap(a) and WithLibrary(a), "and the Elwynn one is back with the library")
	local _, dc, dr = ns.MapToTile(1411, 0.5, 0.5)
	check(PinOff(icons.durotar, dc, dr) < 1, "at its spot")
end

scenarios.addon_pins_toggle_and_close = function()
	local _, icons = LoadQuestie()
	local a = icons.elwynn
	check(OnOurMap(a), "Questie's icon is on our map")
	local home = nil
	if ns.AddLayer then
		local layer = ns.AddLayer({ key = "addon:Questie" })
		check(layer.group == "addons" and layer.label == "Questie", "its layer is Questie's, under other addons")
		MagicMapDB.layers["addon:Questie"] = false
		layer.onToggle(false)
		check(not OnOurMap(a) and WithLibrary(a), "layer off: back with the library")
		home = a:GetParent()
		check(home.icon == a and a:IsShown() and a:GetFrameLevel() == 2016, "on its Blizzard map pin, at Questie's level")
		Sim.Run(1.5)
		check(not OnOurMap(a), "and stays off")
		MagicMapDB.layers["addon:Questie"] = true
		layer.onToggle(true)
		check(OnOurMap(a), "layer on: back on our map")
	end
	-- Blizzard's world map (L) takes them while it's open.
	if ToggleQuestLog then ToggleQuestLog() else WorldMapFrame:Show() end
	Sim.Run(0.5)
	check(WorldMapFrame:IsShown() and not OnOurMap(a) and a:IsVisible() and a:GetParent().icon == a,
		"Blizzard's world map open: the icon shows on it")
	WorldMapFrame:Hide()
	Sim.Run(0.5)
	check(OnOurMap(a), "closed again: back on ours")
	-- Blizzard's map moved to Westfall meanwhile: Elwynn's pins were released.
	WorldMapFrame.mapID = 1436
	WorldMapFrame:Show()
	Sim.Run(0.2)
	WorldMapFrame:Hide()
	Sim.Run(0.5)
	check(OnOurMap(a), "after Blizzard's map changed maps, still ours")
	-- Closing our map gives everything back.
	ns.frame:Hide()
	Sim.Run(0.2)
	check(a:GetParent() == UIParent and not a:IsShown(), "our map closed: hidden in UIParent, as the library left it")
	check(next(ns.HostedAddonPins()) == nil, "nothing hosted")
	WorldMapFrame.mapID = 1429
	WorldMapFrame:Show()
	Sim.Run(0.2)
	check(a:IsVisible() and a:GetParent().icon == a, "Blizzard's map back on Elwynn shows it")
	WorldMapFrame:Hide()
	ns.frame:Show()
	Sim.Run(0.5)
	check(OnOurMap(a), "our map open again: ours again")
end

-- Questie's minimap pins go to our clipped host in minimap mode, and back.
scenarios.addon_pins_minimap = function()
	local pins = Sim.LoadQuestie()
	local dot = Sim.QuestieIcon()
	local p = Sim.player
	local x, y = ns.TileToMap(1429, p.col + 0.05, p.row)
	pins:AddMinimapIconMap(Questie, dot, 1429, x, y, true, true)
	check(dot:GetParent() == Minimap, "Questie's minimap pin starts on the Minimap")
	Sim.Click(ns.modeButton)
	Sim.Run(2)
	ns.SetZoom(1500) -- the Minimap far bigger than the window: clipped
	Sim.Run(1)
	local host = _G.MagicMapMinimapPins
	check(ns.MinimapShowsPlayer() and pins.Minimap ~= Minimap and not dot:IsVisible(),
		"Questie's world-map pins are on our map, so its minimap copies stay out of sight")
	check(Sim.gatherPin:GetParent() == host and Sim.gatherPin:IsVisible(), "the shared copy's pins are on our host, in the window")
	local db = MagicMapDB
	db.layers["addon:Questie"] = false
	Sim.Run(1)
	check(pins.Minimap == host and dot:GetParent() == host and dot:IsVisible(),
		"Questie's layer off: its minimap pins are on our host instead")
	db.layers["addon:Questie"] = true
	Sim.Click(ns.modeButton)
	Sim.Run(1)
	check(pins.Minimap == Minimap and dot:GetParent() == Minimap, "minimap mode off: back on the Minimap")
end

return scenarios

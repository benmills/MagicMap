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
		"blips", "minimap", "sync", "sync", "sync full", "sync", "minimap", "help" }) do
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
	check(gearMenu ~= nil, "the gear opens the layers menu")
	Sim.Click(ns.gearButton)
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
	check(Sim.gatherPin:GetParent() == Minimap, "pins stay on the Minimap")
	check(not MinimapCluster:IsShown() and not Sim.minimapButton:IsVisible(), "nothing of the minimap is left in its corner")
	-- Standing at a turn-in, the Minimap's own ? is the only one shown.
	local home = { Sim.player.col, Sim.player.row }
	local _, col, row = ns.MapToTile(1429, 0.40, 0.80)
	Sim.player.col, Sim.player.row = col, row
	Sim.Run(1)
	check(QuestPin(62) == nil, "our turn-in pin steps aside for the Minimap's")
	Sim.player.col, Sim.player.row = home[1], home[2]
	Sim.Run(1)
	check(QuestPin(62) ~= nil, "and comes back once the Minimap has moved on")
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
	check(not ns.state.minimapShown, "zoomed in past its closest level, the Minimap stays out (it couldn't fit)")
	ns.SetZoom(160)
	Sim.Run(0.5)
	check(ns.state.minimapShown and Minimap:IsVisible(), "settled, the Minimap's blips show")
	check(not C_Minimap or Sim.rimInset == 1000, "Blizzard's rim arrows are pushed off screen")
	check(Sim.BlobRingsAt(0), "and its quest area rings are hidden")
	local vl, vb, vw, vh = ns.viewport:GetRect()
	local ml, mb, mw, mh = Minimap:GetRect()
	check(ml >= vl - 1 and mb >= vb - 1 and ml + mw <= vl + vw + 1 and mb + mh <= vb + vh + 1,
		"its square lies inside the window (the client won't clip it)")
	check(Sim.minimapMask:find("WHITE8X8") and not Minimap:IsClampedToScreen(), "square, and never clamped to the screen")
	Sim.Wheel(ns.viewport, 1)
	Sim.Run(0.05)
	check(not Minimap:IsVisible() and not ns.state.minimapShown, "mid-zoom, it steps aside")
	Sim.Run(1.5)
	check(ns.state.minimapShown, "and is back once the zoom settles")
	-- Indoors: the window wears the Minimap itself, and the wheel zooms it.
	Sim.indoors = true
	Sim.Run(1)
	check(Minimap:IsVisible() and Minimap:GetAlpha() == 1 and ns.state.minimapShown, "indoors, the Minimap shows whole")
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
	local smallW = ns.frame:GetWidth()
	ToggleWorldMap()
	Sim.Run(1)
	check(ns.IsMapExpanded() and not WorldMapFrame:IsShown(), "M grows our window instead of opening Blizzard's map")
	check(ns.frame:GetWidth() > smallW * 2 and ns.frame:GetParent() == UIParent, "to most of the screen")
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

scenarios.layers = function()
	Sim.Run(2)
	Sim.Slash("layers")
	Sim.Run(0.5)
	-- Toggle every layer off and on via the layers menu.
	Sim.Click(ns.gearButton)
	Sim.Run(0.5)
	local toggled = 0
	if Sim.menu then
		for _, item in ipairs(Sim.MenuItems()) do
			if item.onSelect and (item.kind == "checkbox" or item.kind == "radio" or item.kind == "button") then
				Sim.Call("menu " .. tostring(item.text), item.onSelect, item.data)
				Sim.Run(0.4)
				Sim.Call("menu " .. tostring(item.text), item.onSelect, item.data)
				Sim.Run(0.4)
				toggled = toggled + 1
			end
		end
	end
	-- Classic menus are our own (Menu.lua): click its rows.
	for _, f in ipairs(Sim.Frames()) do
		if S[f].type == "Button" and f:IsVisible() and f:GetParent() and f:GetParent():GetParent() == ns.gearButton then
			Sim.Click(f)
			Sim.Run(0.4)
			Sim.Click(f)
			Sim.Run(0.4)
			toggled = toggled + 1
		end
	end
	check(toggled > 0, "the layers menu has toggles")
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

return scenarios

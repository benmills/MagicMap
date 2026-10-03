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
	Fly()
	check(ns.state.follow, "right-click goes back to following")
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
	Sim.Run(6) -- dynamic zoom keeps its hands off for a few seconds after login
	check(ns.state.zoom < z0 * 0.8, ("moving fast, dynamic zoom pulls out (%.0f -> %.0f)"):format(z0, ns.state.zoom))
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
	for name, button in pairs({ follow = ns.followButton, layers = ns.layersButton, minimap = ns.minimapButton }) do
		if button then
			Sim.Hover(button)
			Sim.Click(button)
			Sim.Run(0.5)
		end
	end
	-- The title is the map picker.
	Sim.Run(0.5)
end

scenarios.minimap_mode = function()
	local parent = Minimap:GetParent()
	Sim.Click(ns.minimapButton)
	Sim.Run(2)
	check(ns.IsMinimapMode(), "minimap mode is on")
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
	check(Sim.rimInset == nil, "indoors, its own arrows are back")
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
	-- M: Blizzard's world map opens, ours docked over its map area.
	local area = WorldMapFrame.ScrollContainer
	WorldMapFrame:Show()
	Sim.Run(1)
	check(ns.IsMapExpanded() and WorldMapFrame:IsShown(), "the world map opens, quest log and all")
	check(ns.frame:GetParent() == area and not area.Child:IsShown(), "our map stands in for its map")
	check(math.abs(ns.frame:GetWidth() - area:GetWidth()) < 1, "filling its map area")
	local zoom = ns.state.zoom
	WorldMapFrame:SetMapID(1411) -- picking another zone on Blizzard's side
	Sim.Run(1)
	check(ns.state.zoom ~= zoom, "picking a zone there flies our map to it")
	WorldMapFrame:Hide()
	Sim.Run(1)
	check(not ns.IsMapExpanded() and ns.frame:GetParent() == UIParent and area.Child:IsShown(), "closing it puts ours back")
	check(ns.frame:GetFrameStrata() == MinimapCluster:GetFrameStrata(), "at the minimap's strata again")
	check(ns.frame:IsShown(), "...without closing the minimap")
	-- Rotating minimap: hands the Minimap back.
	Sim.cvars.rotateMinimap = "1"
	Sim.Run(0.5)
	check(Minimap:GetParent() == parent, "rotate minimap gives the Minimap back")
	Sim.cvars.rotateMinimap = "0"
	Sim.Run(0.5)
	Sim.FireEvent("PLAYER_LOGOUT")
	-- Off again: everything goes home.
	Sim.Click(ns.minimapButton)
	Sim.Run(1)
	check(not ns.IsMinimapMode(), "minimap mode is off")
	check(Minimap:GetParent() == parent, "the Minimap is back in its cluster")
	check(Minimap:GetAlpha() == 1, "its terrain is visible again")
	check(not Sim.minimapMask:find("WHITE8X8") and Sim.rimInset == nil, "round again, its arrows back")
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
		ns.SetZoom(2000) -- close in, the quest is off the map: an arrow on the edge points to it
		Sim.Run(1)
		local edge
		for _, r in ipairs({ ns.overlay:GetRegions() }) do
			if tostring(S[r].texture):find("GUIDEARROW") and r:IsVisible() then edge = r end
		end
		check(edge ~= nil, "an off-map target gets an arrow on the map's edge")
		check(Sim.watched == 60 or Sim.watchedIndex ~= nil, "the quest is tracked")
		Sim.Click(ns.pathButton or ns.frame)
		check(ns.SetPath(true), "path mode turns on with a target")
		Sim.player.speed, Sim.player.facing = 200, 2.5
		Sim.Run(4)
		Sim.player.speed = 0
		pin = QuestPin(60)
		if pin then
			ClickOn(pin) -- again: unfollow
			Sim.Run(1)
			check(ns.GetTarget() == nil, "clicking it again stops following it")
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
	Sim.Click(ns.viewport, "RightButton", 0.6, 0.4)
	Sim.modifiers.ctrl = false
	Sim.Run(0.5)
	-- Click a zone to fly there.
	Sim.Click(ns.viewport, "LeftButton", 0.3, 0.6)
	Fly()
end

scenarios.layers = function()
	Sim.Run(2)
	Sim.Slash("layers")
	Sim.Run(0.5)
	-- Toggle every layer off and on via the layers menu.
	Sim.Click(ns.layersButton)
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
		if S[f].type == "Button" and f:IsVisible() and f:GetParent() and f:GetParent():GetParent() == ns.layersButton then
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

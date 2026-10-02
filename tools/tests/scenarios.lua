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
	Sim.player.speed, Sim.player.facing = 300, 1.2 -- fast, heading west-ish
	Sim.Run(3)
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
		"blips", "minimap", "minimap", "help" }) do
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
	check(Minimap:GetParent() == ns.viewport, "the Minimap moved into the map")
	check(Minimap:GetAlpha() == 0, "its terrain is hidden")
	check(Sim.minimapButton:GetParent() == ns.minimapStandIn, "other addons' minimap buttons moved to the stand-in")
	check(Sim.gatherPin:GetParent() == Minimap, "pins stay on the Minimap")
	-- Walk, zoom out past the blips, back in.
	Sim.player.speed = 120
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
	-- Indoors: the minimap's zoom table changes.
	Sim.indoors = true
	Sim.Run(1)
	Sim.indoors = false
	-- M: the world map grows the window; M again shrinks it.
	WorldMapFrame:Show()
	Sim.Run(1)
	check(ns.IsMapExpanded(), "opening the world map expands the window")
	check(not WorldMapFrame:IsShown(), "Blizzard's world map is closed again")
	WorldMapFrame:Show()
	Sim.Run(1)
	check(not ns.IsMapExpanded(), "M again collapses it")
	WorldMapFrame:Show()
	Sim.Run(1)
	_G.MagicMapWorldMapEscape:Hide() -- Escape
	Sim.Run(1)
	check(not ns.IsMapExpanded(), "Escape collapses it")
	WorldMapFrame:Show()
	Sim.Run(1)
	Sim.Click(ns.frame.CloseButton)
	Sim.Run(1)
	check(not ns.IsMapExpanded(), "the close button collapses it")
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
	check(math.abs(Minimap:GetWidth() - 140) < 0.01, "at its own size")
	check(Sim.minimapButton:GetParent() == Minimap, "addon buttons are back on the Minimap")
	check(_G.MinimapBorder:IsShown(), "the minimap border is shown again")
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

return scenarios

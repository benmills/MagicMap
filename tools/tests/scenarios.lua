-- Scenarios for tools/smoketest.py: each drives the loaded addon through
-- one area of behaviour on the simulated client (tools/tests/wowsim.lua).
-- `check(cond, msg)` records a failed expectation; Lua errors anywhere in
-- the addon are collected by the simulation itself.
--
-- Each runs in a fresh client, after login, with the map open on the
-- minimap's spot (Blizzard's Minimap in it) and following.

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
	walk(ns.tileCanvas)
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

-- The Minimap's whole square is on the screen (off it, the client draws its
-- blips into the part still on screen, shifted).
local function OnScreen()
	local l, b, w, h = Minimap:GetRect()
	local k = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * k >= -1 and b * k >= -1 and (l + w) * k <= UIParent:GetWidth() + 1 and (b + h) * k <= UIParent:GetHeight() + 1
end

-- All of the Minimap's square is in the window (well, its map).
local function InWindow(f)
	local vl, vb, vw, vh = ns.viewport:GetRect()
	local l, b, w, h = f:GetRect()
	return l >= vl - 1 and b >= vb - 1 and l + w <= vl + vw + 1 and b + h <= vb + vh + 1
end

-- Mid-screen: room for the Minimap's square however far it's zoomed.
local function Midscreen()
	ns.frame:ClearAllPoints()
	ns.frame:SetPoint("CENTER", UIParent, "CENTER")
end

scenarios.boot = function()
	check(ns.frame:IsVisible(), "the map is open after login")
	check(ns.state.map == 0, "showing the player's continent (0), got " .. tostring(ns.state.map))
	check(TilesDrawn() > 0, "tiles are drawn")
	check(ns.state.playerCol ~= nil, "knows where the player is")
	Sim.Run(3) -- borders, labels, pins settle
	check(QuestPin(60) ~= nil, "the Elwynn quest has a pin")
	check(ns.layoutStats and ns.layoutStats.lines > 0, "zone borders are drawn (from offline data)")
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
		"perf top", "perf mem", "perf", "perf", "blips", "help" }) do
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
	for _, button in ipairs({ ns.gearButton, ns.mapControls.follow, ns.mapControls.zoomIn, ns.mapControls.zoomOut }) do
		Sim.Hover(button)
		Sim.Click(button)
		Sim.Run(0.3)
	end
	Sim.MoveCursorTo(UIParent, 0.1, 0.1)
	Sim.Run(0.5)
	check(ns.gearButton:GetAlpha() < 0.1 and ns.mapControls.frame:GetAlpha() < 0.1, "they fade once the mouse leaves")
end

-- The buttons' tips: small, after a moment, gone on leaving, on a menu, and
-- after a couple of seconds anyway.
scenarios.button_tips = function()
	local function Tip()
		for _, f in ipairs(Sim.Frames()) do
			if f.text and f.owner and f:IsVisible() and f:GetAlpha() > 0 then return f.text:GetText() end
		end
	end
	Sim.MoveCursorTo(ns.gearButton)
	Sim.FireScript(ns.gearButton, "OnEnter", false)
	Sim.Run(0.1)
	check(Tip() == nil, "not straight away")
	Sim.Run(0.5)
	check(Tip() == "Layers & settings", "after a moment, a word or two: " .. tostring(Tip()))
	Sim.Run(3)
	check(Tip() == nil, "and gone after a couple of seconds, still hovering")
	Sim.FireScript(ns.gearButton, "OnLeave", false)
	Sim.MoveCursorTo(ns.modeButton)
	Sim.FireScript(ns.modeButton, "OnEnter", false)
	Sim.Run(0.5)
	check(Tip() == "Big map (M)", "the red button's: " .. tostring(Tip()))
	Sim.MoveCursorTo(UIParent, 0.1, 0.1)
	Sim.FireScript(ns.modeButton, "OnLeave", false)
	Sim.Run(0.1)
	check(Tip() == nil, "gone on leaving")
end

scenarios.minimap_mode = function()
	local parent = ns.minimapStandIn:GetParent() -- the Minimap's own
	Sim.Run(1)
	check(ns.Takeover.Sensing(), "the Minimap is our sensor")
	check(ns.viewport:GetWidth() >= ns.frame:GetWidth() - 16 and ns.viewport:GetHeight() >= ns.frame:GetHeight() - 16,
		"the map fills the window, inside its border")
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
	check(mc.follow.ring:IsShown(), "the follow toggle is lit while following")
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
	check(Minimap:GetAlpha() == 0 and not Sim.minimapGround and Minimap:GetZoom() == 0,
		"outdoors the Minimap is an invisible sensor, at its widest zoom")
	check(not Minimap:IsMouseEnabled(), "that never takes the mouse")
	check(OnScreen(Minimap) and Minimap:GetFrameLevel() < ns.frame:GetFrameLevel() and S[Minimap].iconScale < 0.1,
		"on screen (off it, its blips stop updating), under our window, its own icons tiny (alpha doesn't fade them)")
	check(math.abs(Minimap:GetWidth() * Minimap:GetEffectiveScale() - 300) < 0.5, "300 screen units across, whatever our window")
	local p1 = { ns.frame:GetPoint(1) }
	ns.frame:ClearAllPoints()
	ns.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	Sim.Run(0.2)
	check(OnScreen(), "with our window in the screen's corner, the sensor still all on screen")
	ns.frame:ClearAllPoints()
	ns.frame:SetPoint(unpack(p1))
	Sim.Run(0.2)
	check(Sim.minimapUnrotated, "and it stays north up, even with Rotate Minimap")
	check(ns.Takeover.Sensing(), "it's sensing")
	check(Sim.minimapButton:GetParent() == ns.minimapStandIn, "other addons' minimap buttons moved to the stand-in")
	local pinHost = _G.MagicMapMinimapPins
	check(Sim.gatherPin:GetParent() == Minimap or Sim.gatherPin:GetParent() == pinHost, "pins stay with the Minimap")
	check(not MinimapCluster:IsShown() and not Sim.minimapButton:IsVisible(), "nothing of the minimap is left in its corner")
	check(not ns.MinimapShowsPlayer(), "outdoors our arrow is you")
	-- At a turn-in our "?" stays: the Minimap draws nothing of its own.
	local home = { Sim.player.col, Sim.player.row }
	local _, col, row = ns.MapToTile(1429, 0.40, 0.80)
	Sim.player.col, Sim.player.row = col, row
	Sim.Run(1)
	check(QuestPin(62) ~= nil, "at a turn-in, ours shows")
	Sim.player.col, Sim.player.row = home[1], home[2]
	Sim.Run(1)
	-- Ride, zoom out, back in.
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
	ns.SetZoom(160)
	Sim.Run(0.5)
	check(Sim.gatherPin:GetParent() == pinHost and pinHost:IsVisible(), "HereBeDragons' pins are on our host in the window")
	check(ns.Takeover.Sensing() and Minimap:GetZoom() == 0, "zooming our map leaves the sensor at its widest")
	Sim.Wheel(ns.viewport, 1)
	Sim.Run(1.5)
	-- Indoors: the window wears the Minimap itself, and the wheel zooms it.
	Sim.indoors = true
	Sim.Run(1)
	check(Minimap:IsVisible() and Sim.minimapGround and Minimap:GetAlpha() == 1 and ns.MinimapShowsPlayer(), "indoors, the Minimap shows whole")
	check(not ns.Takeover.Sensing(), "and doesn't sense")
	local mz = Minimap:GetZoom()
	local top = ns.viewport -- what the cursor would wheel: the highest wheel-enabled frame over the map
	for _, c in ipairs({ ns.viewport:GetChildren() }) do
		if c:IsVisible() and S[c].wheel and c:GetFrameLevel() > top:GetFrameLevel() then top = c end
	end
	Sim.Wheel(top, mz < 5 and 1 or -1)
	check(Minimap:GetZoom() ~= mz, "indoors, the wheel zooms the Minimap")
	Sim.Wheel(top, 1)
	Sim.Wheel(top, 1)
	Sim.indoors = false
	Sim.Run(2)
	check(not Sim.minimapGround and Minimap:GetAlpha() == 0 and Minimap:GetZoom() == 0, "back outdoors, our map again, the sensor at its widest")
	-- Somewhere you may mount but the Minimap draws its floor plan
	-- (Undercity, underground): the whole Minimap.
	Sim.floorPlan = true
	Sim.Run(1)
	check(Minimap:IsVisible() and Sim.minimapGround and ns.MinimapShowsPlayer(), "where you may mount but it draws a floor plan, the Minimap shows whole")
	-- But Orgrimmar, open-air, which it draws grey: our map and the sensor.
	local best = C_Map.GetBestMapForUnit
	C_Map.GetBestMapForUnit = function() return 1454 end
	Sim.Run(1)
	check(ns.Takeover.Sensing() and not ns.MinimapShowsPlayer(), "in Orgrimmar, our map and the sensor")
	Sim.minimapUnrotated, Sim.minimapGround = false, true -- (as Blizzard_HybridMinimap leaves them, hiding)
	Sim.Run(0.5)
	check(Sim.minimapUnrotated and not Sim.minimapGround, "the sensor keeps itself north up with no ground")
	C_Map.GetBestMapForUnit = best
	Sim.floorPlan = false
	Sim.Run(1)
	check(not Sim.minimapGround, "and out from under it, our map again")
	check(ns.frame:GetFrameStrata() == MinimapCluster:GetFrameStrata(), "it sits at the minimap's strata")
	-- M: ours grows to most of the screen instead of Blizzard's world map.
	local smallW, smallZoom = ns.frame:GetWidth(), ns.state.zoom
	ToggleWorldMap()
	Sim.Run(1)
	check(ns.IsMapExpanded() and not WorldMapFrame:IsShown(), "M grows our window instead of opening Blizzard's map")
	check(ns.frame:GetWidth() > smallW * 2 and ns.frame:GetParent() == UIParent, "to most of the screen")
	check(not ns.frame.CloseButton:IsShown(), "in the same chrome: no title band, no close button")
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
	-- Rotate Minimap: the Minimap stays (north up, ours don't turn), but
	-- HereBeDragons would turn its pins, so they go out of sight.
	ns.SetZoom(160)
	Sim.Run(1)
	check(Sim.gatherPin:IsVisible(), "HereBeDragons' pins show")
	Sim.cvars.rotateMinimap = "1"
	Sim.Run(0.5)
	check(ns.Takeover.Sensing(), "with Rotate Minimap, the sensor keeps sensing")
	check(not Sim.gatherPin:IsVisible(), "but HereBeDragons' pins are out of sight")
	Sim.cvars.rotateMinimap = "0"
	Sim.Run(0.5)
	check(Sim.gatherPin:IsVisible(), "and back when it's off")
	Sim.FireEvent("PLAYER_LOGOUT")
	-- Hidden: everything goes home.
	ns.frame:Hide()
	Sim.Run(1)
	check(Minimap:GetParent() == parent, "the Minimap is back in its cluster")
	check(Minimap:GetAlpha() == 1 and Sim.minimapGround and not Sim.minimapUnrotated, "its terrain is back, and it follows Rotate Minimap again")
	check(Minimap:IsMouseEnabled() and Minimap:GetZoom() == 0, "it takes the mouse again, at its own zoom")
	check(math.abs(Minimap:GetWidth() - 140) < 0.01, "at its own size")
	check(Sim.minimapButton:GetParent() == Minimap, "addon buttons are back on the Minimap")
	check(MinimapCluster:IsShown() and _G.MinimapBorder:IsVisible(), "the minimap cluster is shown again")
	check(Sim.minimapButton:IsVisible(), "addon buttons are visible again")
end

-- It starts on the minimap's spot and keeps where you put it: moved and
-- resized, hidden (Blizzard's minimap back) and shown, it's where you left
-- it; hidden while grown, it comes back at the minimap's size.
scenarios.minimap_mode_remembers = function()
	local home = { ns.frame:GetLeft(), ns.frame:GetTop() }
	local spot = ns.minimapStandIn
	check(math.abs(home[1] - spot:GetLeft()) < 1 and math.abs(home[2] - spot:GetTop()) < 1, "it starts on the minimap's spot")
	ns.frame:ClearAllPoints()
	ns.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 300, 500)
	ns.frame:SetSize(260, 260)
	ns.SaveFrameLayout()
	Sim.Run(0.5)
	local zoom = ns.state.zoom
	ns.frame:Hide()
	Sim.Run(1)
	ns.frame:Show()
	Sim.Run(1)
	check(math.abs(ns.frame:GetLeft() - 300) < 1 and math.abs(ns.frame:GetTop() - 500) < 1, "shown again: where it was left")
	check(math.abs(ns.frame:GetWidth() - 260) < 1 and math.abs(ns.state.zoom - zoom) < 1, "at the size and zoom it had")
	check(MagicMapDB.point and math.abs(MagicMapDB.width - 260) < 1, "kept in saved variables")
	-- The red button grows it, as M does, and again shrinks it.
	Sim.Click(ns.modeButton)
	Sim.Run(1)
	check(ns.IsMapExpanded() and ns.frame:GetWidth() > 400, "the red button grows it")
	Sim.Click(ns.modeButton)
	Sim.Run(1)
	check(not ns.IsMapExpanded() and math.abs(ns.frame:GetWidth() - 260) < 1, "and shrinks it back")
	-- Hidden while grown, it comes back small.
	ToggleWorldMap()
	Sim.Run(1)
	ns.frame:Hide()
	Sim.Run(0.5)
	check(not ns.IsMapExpanded() and math.abs(MagicMapDB.width - 260) < 1, "hidden while grown: saved at its small size")
	check(MinimapCluster:GetAlpha() == 1, "and Blizzard's minimap corner is fully back")
	ns.frame:Show()
	Sim.Run(1)
	-- Escape: it shrinks the grown map back, but never closes the minimap.
	Sim.Escape()
	Sim.Run(0.5)
	check(ns.frame:IsShown(), "Escape leaves the minimap-sized map alone")
	ToggleWorldMap()
	Sim.Run(1)
	Sim.Escape()
	Sim.Run(1)
	check(ns.frame:IsShown() and not ns.IsMapExpanded() and math.abs(ns.frame:GetWidth() - 260) < 1, "grown, Escape shrinks it back")
	-- Logging out (or a /reload) while grown keeps the small window and its zoom.
	ToggleWorldMap()
	Sim.Run(1)
	Sim.FireEvent("PLAYER_LOGOUT")
	check(math.abs(MagicMapDB.width - 260) < 1 and math.abs(MagicMapDB.zoom - zoom) < 1, "logging out while grown saves the small window and zoom")
	ToggleWorldMap()
	ToggleWorldMap()
	Sim.Run(0.05)
	ns.frame:Hide() -- mid-shrink
	Sim.Run(0.5)
	check(not ns.IsMapExpanded() and math.abs(MagicMapDB.width - 260) < 1, "hidden mid-shrink: saved at its small size")
	-- Hidden, M is Blizzard's again.
	ToggleWorldMap()
	Sim.Run(0.5)
	check(WorldMapFrame:IsShown() and not ns.frame:IsShown(), "with the map hidden, M opens Blizzard's world map")
	ToggleWorldMap()
	Sim.Run(0.5)
	ns.frame:Show()
	Sim.Run(1)
	check(math.abs(ns.frame:GetWidth() - 260) < 1 and math.abs(ns.frame:GetLeft() - 300) < 1, "shown again small, where it was")
	-- Grown, it reads as a big map in the same chrome: your coordinates show
	-- without hovering (at the minimap's size, only while you hover).
	local function ShowsCoords()
		for _, r in ipairs({ ns.titleText:GetParent():GetRegions() }) do
			if r.GetText and (r:GetText() or ""):find("%d+%.%d, %d+%.%d") then return true end
		end
		return false
	end
	ToggleWorldMap()
	Sim.MoveCursorTo(UIParent, 0.01, 0.01)
	Sim.Run(1)
	check(ShowsCoords(), "grown, the title shows your coordinates without hovering")
	SlashCmdList.MAGICMAP("reset")
	Sim.Run(0.5)
	check(ns.IsMapExpanded(), "/mm reset while grown leaves it alone")
	ToggleWorldMap()
	Sim.Run(1)
	check(not ShowsCoords(), "at the minimap's size, not until you hover")
	SlashCmdList.MAGICMAP("reset")
	Sim.Run(1)
	check(math.abs(ns.frame:GetLeft() - home[1]) < 1 and math.abs(ns.frame:GetTop() - home[2]) < 1, "/mm reset: back onto the minimap")
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
	add("Minimap ground, unrotated", Sim.minimapGround, Sim.minimapUnrotated)
	add("Minimap hit", Minimap:GetHitRectInsets())
	frame("MinimapCluster", MinimapCluster)
	for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapZoneTextButton" }) do frame(name, _G[name]) end
	frame("button", Sim.minimapButton)
	add("gather pin parent", Sim.gatherPin:GetParent())
	for _, t in ipairs(Sim.tracking or {}) do add("tracking " .. t.name, t.active) end
	return out
end

scenarios.minimap_restores_everything = function()
	ns.frame:Hide() -- Blizzard's minimap as it is without us
	Sim.Run(1)
	local before = MinimapSnapshot()
	ns.frame:Show()
	Sim.Run(2)
	check(ns.Takeover.IsEngaged(), "showing the map takes the Minimap")
	ns.Takeover.Engage() -- twice is once
	ns.SetZoom(1500) -- (our closest)
	Sim.Run(1)
	Sim.indoors = true
	Sim.Run(1)
	Sim.indoors = false
	Sim.Run(1)
	ToggleWorldMap() -- grown
	Sim.Run(1)
	ToggleWorldMap()
	Sim.Run(1)
	Sim.cvars.rotateMinimap = "1"
	Sim.Run(0.5)
	check(ns.Takeover.IsEngaged(), "rotate minimap keeps it")
	Sim.cvars.rotateMinimap = "0"
	Sim.Run(1)
	-- Off the map being shown (browsing another continent, or crossing to
	-- one): still ours, Blizzard's minimap kept out of its home spot.
	ToggleWorldMap() -- (grown, to browse)
	Sim.Run(1)
	Sim.Slash("map 1")
	Sim.Run(1)
	check(ns.state.map == 1 and ns.Takeover.IsEngaged() and not MinimapCluster:IsShown() and not _G.MagicMapMinimapPins:IsShown(),
		"off the map shown, the minimap stays ours (its pins' host hidden)")
	ToggleWorldMap()
	ns.SetFollow(true)
	Sim.Run(1)
	check(ns.Takeover.Sensing() and _G.MagicMapMinimapPins:IsShown(), "back on your map, the sensor and pins again")
	ns.frame:Hide()
	Sim.Run(0.2)
	check(not ns.Takeover.IsEngaged(), "closing the map releases it")
	ns.frame:Show()
	Sim.Run(1)
	check(ns.Takeover.IsEngaged(), "and opening it takes it again")
	ToggleWorldMap() -- hidden while grown
	Sim.Run(0.1)
	ns.frame:Hide()
	Sim.Run(1)
	ns.Takeover.Release() -- twice is once
	check(not ns.Takeover.IsEngaged(), "hiding the map releases it")
	local after = MinimapSnapshot()
	local diffs = {}
	for i = 1, math.max(#before, #after) do
		if before[i] ~= after[i] then diffs[#diffs + 1] = tostring(before[i]) .. "  ->  " .. tostring(after[i]) end
	end
	check(#diffs == 0, "everything is back as it was:\n    " .. table.concat(diffs, "\n    "))
end

-- Ours first: Blizzard's own markers for what we draw go off while the
-- Minimap is our sensor, so it doesn't report them twice.
scenarios.minimap_ours_first = function()
	if not (C_Minimap and C_Minimap.SetTracking) then return end
	local function Active(name)
		for _, t in ipairs(Sim.tracking) do
			if t.name == name then return t.active end
		end
	end
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
	local function Line1() return _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText() end
	Sim.MoveCursorTo(ns.viewport, 0.5, 0.5)
	Sim.questUnderCursor = 60
	Sim.Run(0.3)
	check(GameTooltip:IsShown() and Line1() == "Kobold Candles", "over a quest area, the quest's tooltip")
	Sim.questUnderCursor = nil
	Sim.Run(0.2)
	check(not GameTooltip:IsShown(), "and lets go off the area")

	ns.frame:Hide()
	Sim.Run(1)
	check(Active("Flight Master") and Active("Track Quest POIs") and not Active("Points of Interest"),
		"hiding the map puts Blizzard's tracking back as it was")
	check(not next(MagicMapDB.trackingOff), "and forgets what it turned off")
end

-- Quest areas hide while the zoom moves and are redrawn at the zoom it
-- settles at (the client's drawing doesn't scale smoothly with the canvas).
scenarios.quest_areas_follow_zoom = function()
	ns.SetZoom(300)
	Sim.Run(1)
	for _ = 1, 3 do Sim.Wheel(ns.viewport, 1) end
	Sim.Run(0.05)
	local _, alpha = ns.QuestAreaState()
	check(alpha == 0, "mid-zoom, quest areas are out of sight")
	Sim.Run(1.5)
	local z, a2 = ns.QuestAreaState()
	check(a2 == 1 and math.abs(z - ns.state.zoom) < 1e-6, "settled, they're back, drawn at the new zoom")
	ns.FlyTo(ns.state.cx + 1, ns.state.cy, 120)
	Sim.Run(2)
	z, a2 = ns.QuestAreaState()
	check(a2 == 1 and math.abs(z - ns.state.zoom) < 1e-6, "after a flight too")
end

-- Hovering a quest, by its pin or its area, lights its area up.
scenarios.quest_area_hover = function()
	ns.SetZoom(300)
	Sim.Run(2)
	local pin = QuestPin(60)
	check(pin ~= nil, "the quest with an area has a pin")
	if not pin then return end
	Sim.MoveCursorTo(pin)
	Sim.FireScript(pin, "OnEnter", false)
	Sim.Run(0.1)
	check(ns.HoveredQuestArea() == 60, "hovering its pin lights its area up")
	Sim.FireScript(pin, "OnLeave", false)
	Sim.MoveCursorTo(UIParent, 0.05, 0.05)
	Sim.Run(0.2)
	check(ns.HoveredQuestArea() == nil, "and leaving lets it go")
	Sim.questUnderCursor = 60
	Sim.MoveCursorTo(ns.viewport, 0.3, 0.3)
	Sim.Run(0.2)
	check(ns.HoveredQuestArea() == 60, "hovering the area itself lights it up too")
	Sim.questUnderCursor = nil
	Sim.Run(0.2)
	check(ns.HoveredQuestArea() == nil, "and off it, it's quiet again")
end

-- A quest pin says the quest's level, coloured by how hard it is for you,
-- and how far along it is.
scenarios.quest_meta = function()
	ns.SetZoom(300)
	Sim.Run(2)
	local pin = QuestPin(60)
	check(pin ~= nil, "the quest has a pin")
	if not pin then return end
	local function Near(c, r, g, b) return c and math.abs(c[1] - r) + math.abs(c[2] - g) + math.abs(c[3] - b) < 0.01 end
	check(pin.entry.title == "[7] Kobold Candles", "its title has its level, got " .. tostring(pin.entry.title))
	check(Near(S[pin.ring].vertex, 1, 0.82, 0), "two levels above you, its disc is yellow")
	check(pin.count:GetText() == "3/8", "its progress is under it, got " .. tostring(pin.count:GetText()))
	check(pin.inner:IsShown() and S[pin.inner].texture == 134335, "the item it still needs (QuestieDB's) sits in its disc, behind the \"...\"")
	check(not QuestPin(62).inner:IsShown(), "a quest ready to turn in has none")
	Sim.FireScript(pin, "OnEnter", false)
	check(Near(S[_G.GameTooltipTextLeft1].textColor, 1, 0.82, 0), "and its tooltip title is yellow")
	local tip = {}
	for i = 1, GameTooltip:NumLines() do tip[#tip + 1] = _G["GameTooltipTextLeft" .. i]:GetText() end
	local text = table.concat(tip, "\n")
	check(text:find("Dropped by", 1, true), "its tooltip says what drops the item:\n" .. text)
	local tunneler, miner = text:find("Kobold Tunneler", 1, true), text:find("Kobold Miner", 1, true)
	check(tunneler and miner and tunneler < miner, "the mobs, lowest level first:\n" .. text)
	check(text:find("|cffffd1004-5|r", 1, true) and text:find("|cffff7f3f7-8|r", 1, true), "with their level ranges, coloured for you (5): yellow, orange:\n" .. text)
	check(text:find("Goldtooth", 1, true) and text:find("Elite", 1, true), "an elite one says so:\n" .. text)
	check(text:find("Turn in to|r William Pestle", 1, true), "and who to turn it in to:\n" .. text)
	check(text:find("Level|r |cffffd1007|r", 1, true), "its level among the facts under its name:\n" .. text)
	-- A mob met (under the mouse): its own portrait on its line from then on.
	Sim.FireScript(pin, "OnLeave", false)
	Sim.units.mouseover = { name = "Kobold Tunneler", guid = "Creature-0-1-0-1-475-00001", npc = true }
	Sim.FireEvent("UPDATE_MOUSEOVER_UNIT")
	Sim.units.mouseover = nil
	Sim.FireScript(pin, "OnEnter", false)
	local portrait
	for _, r in ipairs({ GameTooltip:GetRegions() }) do
		if S[r].portrait == "Creature-0-1-0-1-475-00001" and r:IsShown() then portrait = r end
	end
	check(portrait ~= nil, "a mob you've moused over shows its own portrait in the tooltip")
	local line
	if portrait then line = select(2, portrait:GetPoint(1)) end
	check(line and (line:GetText() or ""):find("Kobold Tunneler", 1, true), "on its line")
	Sim.FireScript(pin, "OnLeave", false)
	local done = QuestPin(62)
	check(done and done.count:GetText() == nil, "a quest ready to turn in has no count")
	check(ns.QuestTitleText(60):find("Kobold Candles", 1, true) ~= nil, "titles in text carry their colour")

	Sim.units.player.level = 13
	Sim.FireEvent("PLAYER_LEVEL_UP", 13)
	Sim.Run(1)
	pin = QuestPin(60)
	check(pin and Near(S[pin.ring].vertex, 0.5, 0.5, 0.5), "levels later, it's grey")
	Sim.units.player.level = 5
end

-- Following a quest with an area: the line heads for the area's nearest
-- edge, and stands down once you're inside it.
scenarios.path_to_quest_area = function()
	local MAP = 1429
	Sim.blobShapes[60] = { 0.35, 0.55, 0.05 } -- quest 60's area: a circle around its pin
	local function At(x, y)
		local _, col, row = ns.MapToTile(MAP, x, y)
		Sim.player.col, Sim.player.row = col, row
	end
	local function Dashes()
		local n = 0
		for _, r in ipairs({ ns.layerFrames.path:GetRegions() }) do
			if r:GetObjectType() == "Line" and r:IsShown() then n = n + 1 end
		end
		return n
	end
	ns.frame:SetSize(400, 400) -- room for the line, you centred
	At(0.20, 0.55) -- west of it, outside
	C_SuperTrack.SetSuperTrackedQuestID(60)
	Sim.FireEvent("SUPER_TRACKING_CHANGED")
	ns.SetZoom(600)
		Sim.Run(2)
	local t = ns.GetTarget()
	check(t and not t.inside, "outside the area, it's a target")
	if t then
		local _, ex = ns.MapToTile(MAP, 0.30, 0.55) -- the area's west edge
		local _, cx = ns.MapToTile(MAP, 0.35, 0.55) -- its centre
		check(math.abs(t.col - ex) < math.abs(t.col - cx) / 4, "aimed at the area's near edge, not its centre")
	end
	check(Dashes() > 0, "with the path line drawn")
	At(0.34, 0.56) -- inside
	Sim.Run(1.5)
	t = ns.GetTarget()
	check(t and t.inside, "inside the area, you've arrived")
	check(Dashes() == 0, "and the path line is gone")
	At(0.20, 0.55)
	Sim.Run(1.5)
	t = ns.GetTarget()
	check(t and not t.inside and Dashes() > 0, "out again, it points the way again")
	C_SuperTrack.SetSuperTrackedQuestID(0)
	Sim.FireEvent("SUPER_TRACKING_CHANGED")
	Sim.blobShapes[60] = nil
end

-- Path mode's route goes the way you'd walk (Data/Walk.lua's terrain).
scenarios.path_routes = function()
	-- Elwynn Forest to Lakeshire: Redridge's mountains are in the way.
	local pts = ns.FindRoute(0, 32.84, 49.03, 36.0, 49.5)
	check(pts and #pts > 2, "Elwynn to Lakeshire bends")
	local south = false
	for _, p in ipairs(pts or {}) do south = south or p[2] > 49.6 end
	check(south, "round the mountains by Three Corners, south of the straight line")
	check(pts and pts[1][1] == 32.84 and pts[#pts][2] == 49.5, "from you, to the target")
	pts = ns.FindRoute(0, 32.84, 49.03, 33.0, 49.1)
	check(pts and #pts == 2, "across open ground, straight")
	check(ns.FindRoute(9999, 1, 1, 2, 2) == nil, "no terrain data, no route (straight line)")
end

-- The line follows its route: found over a few frames, the dashes along
-- it, and found again once you stray off it.
scenarios.path_follows_route = function()
	Sim.player.col, Sim.player.row = 32.84, 49.03
	ns.frame:SetSize(400, 400)
	ns.SetZoom(60)
	ns.SetWaypointAt(36.0, 49.5) -- Lakeshire, past Redridge's mountains
	Sim.Run(2)
	local pts, found = ns.RouteTo(ns.FrameTarget())
	check(pts and #pts > 2, "a route, not a straight line")
	if not pts then return end
	check(pts[1][1] == 32.84 and pts[1][2] == 49.03, "from you")
	local dashes = 0
	for _, r in ipairs({ ns.layerFrames.path:GetRegions() }) do
		if r:GetObjectType() == "Line" and r:IsShown() then dashes = dashes + 1 end
	end
	check(dashes > 0, "drawn as dashes")
	-- It leaves you the way you face: the first dash, facing east, then west.
	local function FirstDash()
		local best, bx, by
		for _, r in ipairs({ ns.layerFrames.path:GetRegions() }) do
			if r:GetObjectType() == "Line" and r:IsShown() then
				local _, _, x, y = r:GetStartPoint()
				local d = (x - 32.84 * ns.state.zoom) ^ 2 + (-y - 49.03 * ns.state.zoom) ^ 2
				if not best or d < best then best, bx = d, x end
			end
		end
		return bx
	end
	Sim.player.facing = -math.pi / 2 -- east
	Sim.Run(0.3)
	local east = FirstDash()
	Sim.player.facing = math.pi / 2 -- west
	Sim.Run(0.3)
	local west = FirstDash()
	check(east and west and east > 32.84 * ns.state.zoom and west < east, "the line leaves you the way you face")
	Sim.player.facing = 0
	Sim.player.col, Sim.player.row = 32.84, 50.0 -- well off it, south
	Sim.Run(2)
	local pts2, found2 = ns.RouteTo(ns.FrameTarget())
	check(pts2 and found2 ~= found, "strayed off it, it's found again from where you are")
	check(pts2 and pts2[1][2] == 50.0, "and starts from you")
	ns.ClearWaypoint()
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
	check(dot and dot.icon:GetTexture() == "Interface\\Minimap\\PartyRaidBlipsV2", "in the art of the Minimap's own party blips")
	Sim.units.party1.dead = true
	Sim.Run(0.1)
	check(dot and dot.icon:GetVertexColor() < 0.6, "greyed while dead")
	Sim.units.party1.dead = nil
	Sim.Run(0.1)
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

scenarios.quests_and_target = function()
	Sim.Run(2)
	-- Click the Elwynn quest's pin: Kobold Candles.
	local pin = QuestPin(60)
	check(pin ~= nil, "the Elwynn quest has a pin")
	if pin then
		Sim.Hover(pin)
		ClickOn(pin)
		Sim.Run(0.5)
		check(ns.GetTarget() ~= nil, "clicking a quest makes it the target")
		ns.SetZoom(800) -- close in, the quest is off the map: an arrow on the edge points to it
		Sim.Run(0.1)
		local edge
		for _, r in ipairs({ ns.overlay:GetRegions() }) do
			if tostring(S[r].texture):find("GUIDEARROW") and r:IsVisible() then edge = r end
		end
		check(edge ~= nil, "an off-map target gets an arrow on the map's edge")
		check(ns.state.zoom == 800, "and the view stays at your zoom")
		check(Sim.watched == 60 or Sim.watchedIndex ~= nil, "the quest is tracked")
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
	check(Sim.waypoint ~= nil, "ctrl-click sets a waypoint")
	Sim.Click(ns.viewport, "RightButton", 0.6, 0.4)
	Sim.modifiers.ctrl = false
	Sim.Run(0.5)
	check(Sim.waypoint == nil, "and ctrl-right-click clears it")
	-- Right-click, "Waypoint here": it's your target.
	Sim.Click(ns.viewport, "RightButton", 0.7, 0.3)
	check(PickMenu("Waypoint here"), "right-click offers a waypoint")
	Sim.Run(2)
	check(Sim.waypoint ~= nil and ns.GetTarget() ~= nil, "the waypoint is your target")
	Sim.Click(ns.viewport, "RightButton", 0.5, 0.5)
	check(PickMenu("Clear waypoint"), "right-click offers to clear it")
	Sim.Run(1)
	check(Sim.waypoint == nil, "and that clears it")
	-- Click a zone to fly there.
	Sim.Click(ns.viewport, "LeftButton", 0.3, 0.6)
	Fly()
end

-- Dying: once the client knows where your corpse is (a while after you
-- release, with no event), it shows, becomes your target, and the view
-- follows you again. Back alive, it's gone.
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
	local corpsePin
	for _, f in ipairs(Sim.Frames()) do
		if f.entry and f.entry.title == "Your corpse" and f:IsVisible() then corpsePin = f end
	end
	check(corpsePin and not corpsePin.glow:IsShown(), "its pin has no gold halo (that's only the quest you follow)")
	check(st.follow, "following you again")
	check(math.abs(st.cx - st.playerCol) < 1, "the view came back to you")
	Sim.ghost, Sim.corpse = false, nil
	Sim.FireEvent("PLAYER_UNGHOST")
	Sim.Run(2)
	check(ns.GetTarget() == nil, "alive again: no corpse")
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
		{ "Places", "flight", "dungeons", "graveyards", "areaPOIs", "blips" },
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
	if rows[i] and rows[i].title == "Other addons" then
		repeat i = i + 1 until not rows[i] or rows[i].title
	end
	check(rows[i] and rows[i].title == "Tracking", "then Blizzard's tracking, got " .. tostring(rows[i] and (rows[i].title or rows[i].key)))
	-- Its own types, but not those ours replace (flight masters, quest POIs, POIs).
	local tracking = {}
	i = i + 1
	while rows[i] and not rows[i].title do
		tracking[#tracking + 1] = rows[i].text
		i = i + 1
	end
	check(table.concat(tracking, ",") == "Find Herbs,Mailbox,Innkeeper", "tracking lists Blizzard-only types, got " .. table.concat(tracking, ","))
	check(rows[i] and rows[i].title == "Settings", "and settings last, got " .. tostring(rows[i] and (rows[i].title or rows[i].key)))
	local mailbox = Sim.tracking[5]
	for _, r in ipairs(rows) do
		if r.text == "Mailbox" then r.toggle() end
	end
	Sim.Run(0.2)
	check(not mailbox.active, "a tracking checkbox switches Blizzard's tracking")
	local tint = MagicMapDB.tint
	for _, r in ipairs(rows) do
		if r.text == "Colour-matched tiles" then r.toggle() end
	end
	check(MagicMapDB.tint ~= tint, "a settings checkbox flips its setting")
	check(LayersOpen(), "and the menu stays open")
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
	check(toggled >= 16, "every layer has a toggle, got " .. toggled)

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
	Sim.FireEvent("PLAYER_TARGET_CHANGED")
	Sim.Run(0.4)
	local function Remembered()
		local n = 0
		for _, entries in pairs(MagicMapLandmarks) do
			for _ in pairs(entries) do n = n + 1 end
		end
		return n
	end
	check(Remembered() == 0, "an ordinary NPC isn't remembered")
	Sim.units.target.classification = "rare"
	Sim.FireEvent("PLAYER_TARGET_CHANGED")
	for _, e in ipairs({ "VIGNETTES_UPDATED", "AREA_POIS_UPDATED", "QUEST_LOG_UPDATE", "MAP_EXPLORATION_UPDATED" }) do
		Sim.FireEvent(e)
		Sim.Run(0.4)
	end
	local inst = select(4, UnitPosition("player"))
	check(MagicMapLandmarks[inst] and MagicMapLandmarks[inst]["rare:1234"], "a rare you target is remembered")
	Sim.Slash("landmarks")
	check((Sim.prints[#Sim.prints] or ""):find("1 rares remembered", 1, true), "/mm landmarks counts it")
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
		walk(ns.tileCanvas)
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
	local tiles = MagicMap_Tiles.maps[map].tiles
	MagicMap_TileColor = nil -- the flavor's own data, if any: this test brings its own
	ns.frame:ClearAllPoints() -- room for interior, coast and sea at once
	ns.frame:SetPoint("CENTER")
	ns.frame:SetSize(860, 620)
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
	local bg = MagicMap_Tiles.maps[map].bg or { 0.03, 0.06, 0.065 }
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
	for _, r in pairs(ns.activeTiles) do touched = touched + (Sim.callsOn[r] or 0) end
	check(touched == 0, ("idle frames leave the tiles alone (%d calls)"):format(touched))
	ns.SetZoom(30)
	Sim.Run(1)
	touched = 0
	for _, r in pairs(ns.activeTiles) do touched = touched + (Sim.callsOn[r] or 0) end
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
-- usual actions. At the minimap's size it keeps to the actions.
scenarios.map_menu_info = function()
	ToggleWorldMap() -- the big map
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
	check(text:find("[7] Kobold Candles", 1, true), "the quest area under the click:\n" .. text)
	check(text:find("Graveyard Goldshire", 1, true), "the nearest graveyard:\n" .. text)
	check(divider, "a divider before the actions")
	check(actions[#actions] == "Follow me", "the actions follow the info")
	check(PickMenu("Waypoint here"), "the actions still work: waypoint here")
	Sim.Run(1)
	check(Sim.waypoint ~= nil, "and that sets the waypoint")
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
	-- At the minimap's size: just the actions.
	ToggleWorldMap()
	Sim.Run(1)
	Sim.Click(ns.viewport, "RightButton", 0.3, 0.3)
	info, actions = MapMenu()
	check(#info == 0 and actions[1] == "Waypoint here", "at the minimap's size: the actions, no info (" .. #info .. " lines)")
	PickMenu("Waypoint here")
	-- M grows it into a big map: the info is back.
	ToggleWorldMap()
	Sim.Run(1)
	check(ns.IsMapExpanded(), "M grows it")
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

-- No addon brings LibStub at all: nothing to borrow, and nothing breaks.
scenarios.addon_pins_without_libstub = function()
	local saved = LibStub
	LibStub = nil
	local libs = ns.HBDPinLibs(true)
	check(type(libs) == "table", "no LibStub: the scan still answers (with the copies it already knew)")
	ns.frame:Hide()
	ns.frame:Show()
	Sim.Run(0.5)
	LibStub = saved
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

-- Questie's minimap pins go to our clipped host while the map is shown, and back.
scenarios.addon_pins_minimap = function()
	Midscreen()
	ns.frame:Hide() -- Blizzard's minimap, as Questie finds it
	Sim.Run(1)
	local pins = Sim.LoadQuestie()
	local dot = Sim.QuestieIcon()
	local p = Sim.player
	local x, y = ns.TileToMap(1429, p.col + 0.05, p.row)
	pins:AddMinimapIconMap(Questie, dot, 1429, x, y, true, true)
	check(dot:GetParent() == Minimap, "Questie's minimap pin starts on the Minimap")
	ns.frame:Show()
	Sim.Run(2)
	ns.SetZoom(160)
	Sim.Run(1.5)
	local host = _G.MagicMapMinimapPins
	check(ns.Takeover.Sensing() and pins.Minimap ~= Minimap and not dot:IsVisible(),
		"Questie's world-map pins are on our map, so its minimap copies stay out of sight")
	check(Sim.gatherPin:GetParent() == host and Sim.gatherPin:IsVisible(), "the shared copy's pins are on our host, in the window")
	local db = MagicMapDB
	db.layers["addon:Questie"] = false
	Sim.Run(1)
	check(pins.Minimap == host and dot:GetParent() == host and dot:IsVisible(),
		"Questie's layer off: its minimap pins are on our host instead")
	db.layers["addon:Questie"] = true
	ns.frame:Hide()
	Sim.Run(1)
	check(pins.Minimap == Minimap and dot:GetParent() == Minimap, "the map hidden: back on the Minimap")
end

-- A live rare has one pin: the rare you've seen steps aside while its vignette shows.
scenarios.live_rare_one_pin = function()
	local function Pins()
		local live, seen = 0, 0
		for _, f in ipairs(Sim.Frames()) do
			local e = f.entry
			if e and e.title == "Mother Fang" and f:IsVisible() then
				if e.lines[1] == "Rare" then seen = seen + 1 else live = live + 1 end
			end
		end
		return live, seen
	end
	ns.SetZoom(200)
	Sim.vignetteAtlas = "VignetteKillElite"
	Sim.FireEvent("VIGNETTES_UPDATED")
	Sim.Run(2)
	local live, seen = Pins()
	check(live == 1 and seen == 0, "a live rare: just its vignette's pin, got " .. live .. " live, " .. seen .. " seen")
	Sim.noVignettes = true
	Sim.FireEvent("VIGNETTES_UPDATED")
	Sim.Run(2)
	live, seen = Pins()
	check(live == 0 and seen == 1, "gone: the rare you've seen is back, got " .. live .. " live, " .. seen .. " seen")
	Sim.noVignettes = nil
	Sim.FireEvent("VIGNETTES_UPDATED")
	Sim.Run(2)
	check((Pins()) == 1, "live again: its vignette's pin")
	FindRow(OpenLayers(), "vignettes").toggle()
	CloseLayers()
	Sim.Run(2)
	live, seen = Pins()
	check(live == 0 and seen == 1, "live rares switched off: the rare you've seen is back, got " .. live .. " live, " .. seen .. " seen")
	FindRow(OpenLayers(), "vignettes").toggle()
	CloseLayers()
	Sim.vignetteAtlas = nil
end

-- Blizzard's blips, read off the invisible Minimap and drawn as our pins:
-- each where it is, with its own icon; what we draw ourselves isn't
-- repeated; they stay put as you walk and go when Blizzard's do.
scenarios.minimap_blips = function()
	local n, w = UnitPosition("player")
	local truth = {
		{ "Peacebloom", n + 40, w - 25 },
		{ "Copper Vein", n + 12.5, w + 70 },
		{ "Mailbox", n - 30, w + 10 },
		{ "Gruff Stranger", n - 60.3, w + 35.7 },
		{ "Innkeeper Tess", n + 70, w - 60 },
		{ "Peacebloom", n - 20, w - 80 },
		{ "Peacebloom", n - 26, w - 88 }, -- (their squares overlap)
	}
	Sim.minimapBlips = {}
	for _, b in ipairs(truth) do Sim.minimapBlips[#Sim.minimapBlips + 1] = b end
	local p = Sim.player
	Sim.group = { "party1" }
	Sim.units.party1 = { name = "Friend", class = "PRIEST", col = p.col + 50 / (1600 / 3), row = p.row }
	local fn, fw = UnitPosition("party1")
	table.insert(Sim.minimapBlips, { "Friend", fn, fw })
	-- (The answer square is in screen units: the sensor's scale mustn't
	-- matter. Room for the whole sensor: smaller, its squares are wider in
	-- yards and blips of a name this close merge.)
	local w0, h0 = ns.frame:GetSize()
	ns.frame:SetScale(0.7)
	ns.frame:SetSize(480, 480)
	ns.SetZoom(300)
	Sim.Run(2)
	local function Where()
		local out = {}
		for _, b in ipairs(ns.Blips()) do out[#out + 1] = ("%s %.2f,%.2f"):format(b.name, b.north - n, b.west - w) end
		return table.concat(out, "; ")
	end
	local function Near(name, north, west, most)
		for _, b in ipairs(ns.Blips()) do
			if b.name == name and math.sqrt((b.north - north) ^ 2 + (b.west - west) ^ 2) <= (most or 0.3) then return b end
		end
	end
	for _, t in ipairs(truth) do
		check(Near(t[1], t[2], t[3]), ("%s found where it is (%.1f, %.1f)"):format(t[1], t[2] - n, t[3] - w))
	end
	check(#ns.Blips() == #truth + 1, "one blip each, got " .. #ns.Blips())
	local function Pins(title)
		local out = {}
		for _, f in ipairs(Sim.Frames()) do
			if f.entry and f.entry.title == title and f:IsVisible() then out[#out + 1] = f end
		end
		return out
	end
	local herb = Pins("Peacebloom")[1]
	check(#Pins("Peacebloom") == 3 and herb.entry.icon.atlas == "Professions_Tracking_Herb", "herbs: the herb icon")
	check(Pins("Copper Vein")[1] and Pins("Copper Vein")[1].entry.icon.atlas == "Professions_Tracking_Ore", "ore: the ore icon")
	check(Pins("Mailbox")[1] and Pins("Mailbox")[1].entry.icon.texture == 136459, "the mailbox: its tracking icon")
	check(Pins("Innkeeper Tess")[1] and Pins("Innkeeper Tess")[1].entry.icon.texture == 136458,
		"town services: Blizzard's tracking icon, by QuestieDB's NPC flags")
	check(Pins("Gruff Stranger")[1] and Pins("Gruff Stranger")[1].entry.icon.color, "anything else: a dot")
	check(#Pins("Friend") == 0, "party members aren't repeated (their dots are ours)")
	-- Riding (the client moves its blips in steps): no copies, and they
	-- settle where they are in the world once you stop.
	p.speed = 14
	for _ = 1, 6 do
		Sim.Run(0.5)
		check(#ns.Blips() == #truth + 1, "riding: one blip each, got " .. #ns.Blips() .. ": " .. Where())
	end
	p.speed = 0
	Sim.Run(2)
	for _, t in ipairs(truth) do
		check(Near(t[1], t[2], t[3], 0.5), t[1] .. " stays put as you walk: " .. Where())
	end
	-- Gone from Blizzard's: gone from ours.
	table.remove(Sim.minimapBlips, 3)
	Sim.Run(2)
	check(not Near("Mailbox", truth[3][2], truth[3][3], 5) and #Pins("Mailbox") == 0, "a blip that's gone goes")
	-- The layer off: none drawn, nothing read.
	MagicMapDB.layers.blips = false
	ns.RefreshLayer("blips")
	Sim.Run(1)
	check(#Pins("Peacebloom") == 0, "the layer off hides them")
	MagicMapDB.layers.blips = true
	ns.RefreshLayer("blips")
	Sim.Run(1)
	check(#Pins("Peacebloom") == 3, "and on again shows them: " .. #Pins("Peacebloom") .. " " .. Where())
	-- Away from you: town services from QuestieDB, for your faction, from
	-- town scale in, for the kinds Blizzard tracks; and blips seen before.
	local _, tc, tr = ns.MapToTile(1429, 0.40, 0.80)
	local pc, pr = ns.WorldToTile(UnitPosition("player"))
	check(math.sqrt((tc - pc) ^ 2 + (tr - pr) ^ 2) * 1600 / 3 > 300, "(the remote innkeeper is out of the sensor's reach)")
	local function Remote(name)
		for _, f in ipairs(Sim.Frames()) do
			if f.entry and f.entry.title == name and f.entry.minZoom and f:IsVisible() then return f end
		end
	end
	ns.SetZoom(150)
	Sim.Run(3)
	check(Remote("Innkeeper Tess") and Remote("Innkeeper Allie") and Remote("Innkeeper Horus") == nil,
		"town services away from you: QuestieDB's, those friendly to you")
	check(Remote("Innkeeper Tess").entry.icon.texture == 136458, "with their tracking icon")
	ns.SetZoom(30)
	Sim.Run(1)
	check(Remote("Innkeeper Tess") == nil, "not zoomed out past town scale")
	ns.SetZoom(150)
	Sim.tracking[#Sim.tracking].active = false -- (Innkeeper)
	ns.RefreshLayer("blips")
	Sim.Run(1)
	check(Remote("Innkeeper Tess") == nil, "nor for what Blizzard's tracking has off")
	Sim.tracking[#Sim.tracking].active = true
	-- The mailbox seen near you is remembered; far from it, it stays.
	table.insert(Sim.minimapBlips, truth[3])
	Sim.Run(2)
	p.col = p.col + 400 / (1600 / 3)
	Sim.Run(2)
	check(Remote("Mailbox"), "a mailbox seen before still shows once you're far from it")
	p.col = p.col - 400 / (1600 / 3)
	Sim.Run(2)
	check(Remote("Mailbox") == nil and #Pins("Mailbox") == 1, "back near it, only the live one")
	-- Two remembered mailboxes on a map both show.
	local inst = select(4, UnitPosition("player"))
	MagicMapLandmarks[inst]["blip:Mailbox:far"] = { kind = "blip", name = "Mailbox", icon = 136459,
		n = truth[3][2] + 600, w = truth[3][3], t = time() }
	p.col = p.col + 400 / (1600 / 3)
	Sim.Run(2)
	local mailboxes = 0
	for _, f in ipairs(Sim.Frames()) do
		if f.entry and f.entry.title == "Mailbox" and f.entry.minZoom and f:IsVisible() then mailboxes = mailboxes + 1 end
	end
	check(mailboxes == 2, "every remembered mailbox shows, got " .. mailboxes)
	p.col = p.col - 400 / (1600 / 3)
	-- Seen gone where it was remembered: forgotten.
	table.remove(Sim.minimapBlips, #Sim.minimapBlips)
	Sim.Run(3)
	local kept = 0
	for _, e in pairs(MagicMapLandmarks[inst]) do
		if e.kind == "blip" and e.name == "Mailbox" then kept = kept + 1 end
	end
	check(kept == 1, "a remembered mailbox the sensor sees gone is forgotten (the far one stays), kept " .. kept)
	-- In combat the sensor rests; what it knew stays.
	Sim.inCombat = true
	table.remove(Sim.minimapBlips, 1)
	Sim.Run(1)
	check(Near("Peacebloom", truth[1][2], truth[1][3]), "in combat nothing is read")
	Sim.inCombat = false
	Sim.Run(1)
	check(not Near("Peacebloom", truth[1][2], truth[1][3], 5), "out of it, reading resumes")
	ns.frame:SetScale(1)
	ns.frame:SetSize(w0, h0)
	Sim.group, Sim.units.party1, Sim.minimapBlips = {}, nil, {}
end

-- Indoors with map art (Undercity, a dungeon floor): the art of the map
-- you're on, under our layers, the sensor running; without art, Blizzard's
-- floor plan; outdoors again, neither.
scenarios.indoor_art = function()
	local zone = C_Map.GetBestMapForUnit("player")
	Sim.mapArt[zone] = { 1002, 668, 256 } -- (a zone's painting)
	Sim.mapArt[1455] = { 1002, 668, 256 } -- Ironforge's
	local function ArtShown()
		local n = 0
		for _, r in ipairs({ ns.tileCanvas:GetRegions() }) do
			if r:IsVisible() and type(S[r].texture) == "number" and S[r].texture > 900000 then n = n + 1 end
		end
		return n
	end
	-- In a hut: the map you're on is the zone, its art the zone's painting.
	Sim.floorPlan = true
	Sim.Run(1)
	check(ArtShown() == 0 and ns.MinimapShowsPlayer(), "indoors where the map is the whole zone: no art, Blizzard's floor plan")
	-- In a city: its own map's art.
	local best = C_Map.GetBestMapForUnit
	C_Map.GetBestMapForUnit = function() return 1455 end
	Sim.Run(1)
	check(ArtShown() == 4 * 3, "in a city, its map's art: 4 x 3 pieces, got " .. ArtShown())
	check(ns.Takeover.Sensing() and not ns.MinimapShowsPlayer(), "with our map and the sensor, not Blizzard's floor plan")
	local r = ns.MapRect(1455)
	local first
	for _, t in ipairs({ ns.tileCanvas:GetRegions() }) do
		if S[t].texture == 900001 then first = t end
	end
	local z = ns.state.zoom
	local _, _, _, x, y = first:GetPoint(1)
	check(math.abs(x - r.col0 * z) < 0.01 and math.abs(y + r.row0 * z) < 0.01, "its first piece at the map's corner")
	ns.SetZoom(z * 1.5)
	Sim.Run(1)
	_, _, _, x = first:GetPoint(1)
	check(math.abs(x - r.col0 * ns.state.zoom) < 0.01, "and laid out again as you zoom")
	Sim.Slash("indoor")
	Sim.Run(0.2)
	check(MagicMapDB.indoorDebug, "/mm indoor reports")
	Sim.Slash("indoor")
	Sim.floorPlan = false
	Sim.Run(1)
	check(ArtShown() == 0, "outdoors, no art")
	C_Map.GetBestMapForUnit = best
	Sim.mapArt[zone], Sim.mapArt[1455] = nil, nil
end

return scenarios

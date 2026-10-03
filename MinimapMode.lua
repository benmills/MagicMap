-- Minimap mode (the spyglass button): the MagicMap window takes the
-- minimap's place.
--
--   * The window moves onto the minimap's spot, square, showing SPAN yards
--     across (and keeping that as you resize it), with compact chrome (Core's SetCompact): just the map, the
--     zone floating above it, the buttons on hover. Blizzard's minimap moves
--     inside (MinimapBlips.lua), so its blips and pins land on our terrain.
--   * Pan away and leave it alone for a few seconds, and it glides back to
--     following you.
--   * It sits at the minimap's strata, so other windows go over it.
--   * Opening the world map opens Blizzard's as usual (quest log and all),
--     with this map docked over its map area in place of Blizzard's; picking
--     a zone or quest there flies this map to it. Closing it puts it back.
--
-- Turning the mode off puts the window back where it was.

local ADDON, ns = ...
local TILE_YARDS = 1600 / 3
local IDLE_FOLLOW = 6 -- seconds untouched before the map follows you again
local SPAN = 200 -- yards across the window's shorter side to start with (Blizzard's widest: 467)

local db
local state = ns.state
local frame = ns.frame
local expanded = false
local small -- while docked: the minimap-sized rect { left, top, w, h, zoom = } to return to

function ns.IsMinimapMode() return db and db.minimapMode end

function ns.IsMapExpanded() return expanded end

local function UpdateButton()
	local on = db and db.minimapMode
	ns.minimapButton.icon:SetDesaturated(not on)
	ns.minimapButton.icon:SetVertexColor(1, 1, 1, on and 1 or 0.55)
end

-- Escape closes the map normally, but not while it stands in for the minimap.
local function SetCloseOnEscape(on)
	for i = #UISpecialFrames, 1, -1 do
		if UISpecialFrames[i] == "MagicMapFrame" then table.remove(UISpecialFrames, i) end
	end
	if on then tinsert(UISpecialFrames, "MagicMapFrame") end
end

---------------------------------------------------------------------------
-- Window rect, in the frame's own coordinates from UIParent's bottom-left:
-- { left, top, width, height }.
---------------------------------------------------------------------------

local function SetRect(r)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r[1], r[2])
	frame:SetSize(r[3], r[4])
end

-- The minimap's strata in minimap mode (other windows go over it); the
-- window's own otherwise.
local function SetHomeStrata()
	frame:SetFrameStrata(db and db.minimapMode and (MinimapCluster and MinimapCluster:GetFrameStrata() or "LOW") or "HIGH")
end

-- Resizing the small window keeps the same yards across it (the zoom scales
-- with it), rather than showing more or less of the world.
local lastSide
frame:HookScript("OnSizeChanged", function(_, w, h)
	local side = math.min(w, h)
	if db and db.minimapMode and not expanded and lastSide and lastSide > 0 then
		ns.SetZoom(ns.state.zoom * side / lastSide)
	end
	lastSide = side
end)

-- The minimap's spot, as a square.
local function MinimapSquare()
	local left, top, w, h = ns.MinimapRect()
	if not left then return nil end
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local side = math.max(w, h) * k
	return { left * k, top * k, side, side }
end

---------------------------------------------------------------------------
-- World map takeover
---------------------------------------------------------------------------

-- Blizzard's map area: its canvas (hidden while we're there) and our dock.
local function WorldMapArea()
	return WorldMapFrame and (WorldMapFrame.ScrollContainer
		or (WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer()))
end

-- Show what Blizzard's map is on (a zone, or the continent).
local function FlyToWorldMapsMap()
	local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local r = mapID and ns.MapRect(mapID)
	if not r then return end
	if r.inst ~= state.map then ns.SetMap(r.inst) end
	ns.SetPath(false)
	ns.SetFollow(false)
	ns.FlyTo((r.col0 + r.col1) / 2, (r.row0 + r.row1) / 2, ns.FitZoom(r.col0, r.row0, r.col1, r.row1), 0.3)
end

local function Dock()
	local area = WorldMapArea()
	if expanded or not area or not db.minimapMode then return end
	expanded = true
	local l, t, w, h = frame:GetLeft(), frame:GetTop(), frame:GetSize()
	small = { l, t, w, h, zoom = ns.GoalZoom() }
	frame:SetParent(area)
	frame:ClearAllPoints()
	frame:SetAllPoints(area)
	frame:SetFrameStrata(area:GetFrameStrata())
	frame:SetFrameLevel(area:GetFrameLevel() + 1)
	if area.Child then area.Child:Hide() end
	ns.SetDocked(true)
	frame:Show()
	FlyToWorldMapsMap()
end

local function Undock()
	if not expanded then return end
	expanded = false
	local area = WorldMapArea()
	if area and area.Child then area.Child:Show() end
	frame:SetParent(UIParent)
	SetHomeStrata()
	ns.SetDocked(false)
	local target = small
	small = nil
	SetRect(target)
	ns.SaveFrameLayout()
	if state.playerCol and state.playerMap == state.map then
		ns.FlyTo(state.playerCol, state.playerRow, target.zoom, 0.3, function() ns.SetFollow(true) end)
	else
		ns.SetZoom(target.zoom)
		ns.SetFollow(true)
	end
end

local worldMapHooked = false
local function HookWorldMap()
	if worldMapHooked or not WorldMapFrame then return end
	worldMapHooked = true
	WorldMapFrame:HookScript("OnShow", function() if db and db.minimapMode then Dock() end end)
	WorldMapFrame:HookScript("OnHide", Undock)
	if WorldMapFrame.OnMapChanged then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function() if expanded then FlyToWorldMapsMap() end end)
	end
end
HookWorldMap()

---------------------------------------------------------------------------
-- Entering and leaving
---------------------------------------------------------------------------

local function EnterMinimapMode()
	local rect = MinimapSquare()
	local p, _, rp, x, y = frame:GetPoint()
	db.normalLayout = { point = { p, rp, x, y }, width = frame:GetWidth(), height = frame:GetHeight(), zoom = state.zoom }
	db.minimapMode = true
	SetCloseOnEscape(false)
	SetHomeStrata()
	ns.SetCompact(true)
	if rect then
		SetRect(rect)
		ns.SaveFrameLayout()
		ns.SetZoom(rect[3] / (SPAN / TILE_YARDS))
	end
	ns.SetFollow(true)
	frame:Show()
	ns.FitTitle()
	UpdateButton()
end

local function LeaveMinimapMode()
	Undock()
	db.minimapMode = false
	SetHomeStrata()
	ns.ReleaseMinimap()
	SetCloseOnEscape(true)
	ns.SetCompact(false)
	local layout = db.normalLayout
	if layout then
		frame:ClearAllPoints()
		frame:SetPoint(layout.point[1], UIParent, layout.point[2], layout.point[3], layout.point[4])
		frame:SetSize(layout.width, layout.height)
		ns.SaveFrameLayout()
		ns.SetZoom(layout.zoom)
		db.normalLayout = nil
	end
	UpdateButton()
end

local function ToggleMinimapMode()
	if db.minimapMode then LeaveMinimapMode() else EnterMinimapMode() end
	local why = db.minimapMode and ns.MinimapBlocker()
	if why then ns.Print("minimap mode: blips are waiting (" .. why .. ")") end
end

ns.minimapButton:SetScript("OnClick", ToggleMinimapMode)
ns.Tooltip(ns.minimapButton, function()
	return db and db.minimapMode and "Minimap mode  |cff888888(click to put the window back)|r"
		or "Minimap mode  |cff888888(move onto the minimap, with its blips)|r"
end)
ns.slash.minimap = ToggleMinimapMode

-- Left alone after you've panned away, go back to you (or to framing you
-- and your target, if that's how you left it).
frame:HookScript("OnUpdate", function()
	if not (db and db.minimapMode) or expanded or state.follow or state.path or state.dragging or ns.IsAnimating() then return end
	if frame:IsMouseOver() or GetTime() - (state.lastInteract or 0) < IDLE_FOLLOW then return end
	if db.cameraMode == "path" and ns.SetPath(true) then return end
	if state.playerCol and state.playerMap == state.map then
		ns.FlyTo(state.playerCol, state.playerRow, state.zoom, 0.55, function() ns.SetFollow(true) end)
	else
		ns.SetFollow(true)
	end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		HookWorldMap() -- load-on-demand world maps
	elseif event == "PLAYER_LOGOUT" and small then
		-- Never come back expanded: save the minimap-sized window.
		db.point = { "TOPLEFT", "BOTTOMLEFT", small[1], small[2] }
		db.width, db.height = small[3], small[4]
	end
end)

ns.On("Loaded", function(savedDB)
	db = savedDB
	db.minimapBlips = nil -- an earlier version's setting
	if db.minimapMode == nil then db.minimapMode = false end
	if db.minimapMode then
		SetCloseOnEscape(false)
		ns.SetCompact(true)
	end
	SetHomeStrata()
	UpdateButton()
end)

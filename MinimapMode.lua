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
--   * The world map key (M) grows the window to most of the screen instead
--     of opening Blizzard's; M, Escape or the close button shrink it back.
--     Anything else that opens Blizzard's world map (the quest log, L) still
--     opens it as usual.
--
-- Turning the mode off puts the window back where it was.

local ADDON, ns = ...
local TILE_YARDS = 1600 / 3
local IDLE_FOLLOW = 6 -- seconds untouched before the map follows you again
local EXPAND_TIME, COLLAPSE_TIME = 0.22, 0.18
local EXPANDED_SIZE = 0.7 -- of the screen, each way
local MAPTYPE_ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local SPAN = 200 -- yards across the window's shorter side to start with (Blizzard's widest: 467)

local db
local state = ns.state
local frame = ns.frame
local expanded = false -- grown to most of the screen (the world map, M)
local small -- meanwhile: the minimap-sized rect { left, top, w, h, zoom = } to return to

function ns.IsMinimapMode() return db and db.minimapMode end

function ns.IsMapExpanded() return expanded end

local function UpdateButton()
	ns.SetModeButtonArt(db and db.minimapMode)
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


local function EaseOutCubic(t) return 1 - (1 - t) ^ 3 end

-- The minimap's home corner (Blizzard's cluster, and the stand-in holding the
-- buttons that hung off the minimap) fades out while the window is expanded,
-- so nothing of the minimap is left floating there.
local homeAlpha = 1 -- the cluster's own alpha, to restore
local function SetHomeAlpha(a)
	if MinimapCluster then MinimapCluster:SetAlpha(a) end
	if ns.minimapStandIn then ns.minimapStandIn:SetAlpha(a) end
end

local tween
local tweener = CreateFrame("Frame")
tweener:Hide()
tweener:SetScript("OnUpdate", function(self, elapsed)
	local tw = tween
	tw.t = tw.t + elapsed
	local p = EaseOutCubic(math.min(1, tw.t / tw.dur))
	local r = {}
	for i = 1, 4 do r[i] = tw.from[i] + (tw.to[i] - tw.from[i]) * p end
	if tw.alpha then SetHomeAlpha(tw.alpha[1] + (tw.alpha[2] - tw.alpha[1]) * p) end
	SetRect(r)
	if p >= 1 then
		tween = nil
		self:Hide()
		if tw.onDone then tw.onDone() end
	end
end)

-- alpha (optional): { from, to } for the minimap's home corner.
local function TweenTo(to, duration, onDone, alpha)
	tween = { from = { frame:GetLeft(), frame:GetTop(), frame:GetSize() }, to = to, t = 0, dur = duration, onDone = onDone, alpha = alpha }
	tweener:Show()
end

local function StopTween()
	tween = nil
	tweener:Hide()
end


-- Resizing the small window keeps the same yards across it (the zoom scales
-- with it), rather than showing more or less of the world.
local lastSide
frame:HookScript("OnSizeChanged", function(_, w, h)
	local side = math.min(w, h)
	if db and db.minimapMode and not ns.IsMapExpanded() and not tween and lastSide and lastSide > 0 then
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

local function RememberSmall()
	local l, t, w, h = frame:GetLeft(), frame:GetTop(), frame:GetSize()
	small = { l, t, w, h, zoom = ns.GoalZoom() }
end

-- Back on you at the zoom you had, following.
local function ReturnToSmallView(target, duration)
	if state.playerCol and state.playerMap == state.map then
		ns.FlyTo(state.playerCol, state.playerRow, target.zoom, duration, function() ns.SetFollow(true) end)
	else
		ns.SetZoom(target.zoom)
		ns.SetFollow(true)
	end
end

-- Expanded (the world map, M) ---------------------------------------------

-- Escape while expanded shrinks the window back rather than closing it.
local escapeCatcher = CreateFrame("Frame", "MagicMapWorldMapEscape", UIParent)
escapeCatcher:Hide()
tinsert(UISpecialFrames, "MagicMapWorldMapEscape")

-- Your zone's rect in tile space (walking up from a sub-zone or micro map).
local function PlayerZoneRect()
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType and info.mapType > MAPTYPE_ZONE and info.parentMapID do
		mapID = info.parentMapID
		info = C_Map.GetMapInfo(mapID)
	end
	local r = mapID and ns.MapRect(mapID)
	return r and r.inst == state.map and r or nil
end

local function Expand()
	if expanded or not db.minimapMode then return end
	expanded = true
	-- Still shrinking back from the last time: the rect to return to stands.
	if not small then
		RememberSmall()
		homeAlpha = MinimapCluster and MinimapCluster:GetAlpha() or 1
	end
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local sw, sh = UIParent:GetWidth() * k, UIParent:GetHeight() * k
	local w, h = sw * EXPANDED_SIZE, sh * EXPANDED_SIZE
	ns.SetCompact(false)
	frame:SetFrameStrata("HIGH")
	escapeCatcher:Show()
	frame:Show()
	frame:Raise()
	TweenTo({ (sw - w) / 2, (sh + h) / 2, w, h }, EXPAND_TIME, nil, { MinimapCluster and MinimapCluster:GetAlpha() or homeAlpha, 0 })
	-- Land on your zone, the way the world map opens on it.
	local r = PlayerZoneRect()
	if r then
		local vw, vh = w - 4, h - 23 -- the map area inside the full chrome
		local zoom = math.min(vw / (r.col1 - r.col0), vh / (r.row1 - r.row0)) * 0.92
		ns.SetPath(false)
		ns.SetFollow(false)
		ns.FlyTo((r.col0 + r.col1) / 2, (r.row0 + r.row1) / 2, zoom, EXPAND_TIME + 0.1)
	end
end

local function Collapse()
	if not expanded then return end
	expanded = false
	escapeCatcher:Hide()
	local target = small
	TweenTo({ target[1], target[2], target[3], target[4] }, COLLAPSE_TIME, function()
		small = nil
		ns.SetCompact(true)
		SetHomeStrata()
		ns.SaveFrameLayout()
	end, { 0, homeAlpha })
	ReturnToSmallView(target, COLLAPSE_TIME)
end

escapeCatcher:SetScript("OnHide", Collapse)
ns.OnCloseClicked = function()
	if expanded then
		Collapse()
		return true
	end
end

-- M (ToggleWorldMap) grows our window instead of opening Blizzard's world
-- map, and M again shrinks it back. (M closing Blizzard's map, opened from
-- the quest log, is left alone.)
local function OnToggleWorldMap()
	if not (db and db.minimapMode) or not WorldMapFrame:IsShown() then return end
	if HideUIPanel then HideUIPanel(WorldMapFrame) else WorldMapFrame:Hide() end
	if expanded then Collapse() else Expand() end
end

local worldMapHooked = false
local function HookWorldMap()
	if worldMapHooked or not ToggleWorldMap then return end
	worldMapHooked = true
	hooksecurefunc("ToggleWorldMap", OnToggleWorldMap)
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
	if expanded then
		expanded = false
		escapeCatcher:Hide()
		SetHomeAlpha(homeAlpha)
	end
	StopTween()
	small = nil
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

ns.modeButton:SetScript("OnClick", ToggleMinimapMode)
ns.Tooltip(ns.modeButton, function()
	return db and db.minimapMode and "Back to the window  |cff888888(leave minimap mode)|r"
		or "Minimap mode  |cff888888(move onto the minimap, with its blips)|r"
end)
ns.slash.minimap = ToggleMinimapMode

-- Left alone after you've panned away, go back to you (or to framing you
-- and your target, if that's how you left it).
frame:HookScript("OnUpdate", function()
	if not (db and db.minimapMode) or ns.IsMapExpanded() or state.follow or state.path or state.dragging or ns.IsAnimating() then return end
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

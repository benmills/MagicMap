-- The MagicMap window is the minimap: it takes the minimap's place.
--
--   * It starts on the minimap's spot, square, showing SPAN yards across (and
--     keeping that as you resize it): just the map, the zone floating above
--     it, the buttons on hover. Move and resize it anywhere; /mm reset puts it
--     back. Blizzard's minimap moves inside (MinimapBlips.lua decides,
--     MinimapTakeover.lua does it), so its blips and pins land on our terrain.
--     Hiding the window gives Blizzard's minimap back.
--   * Pan away and leave it alone for a few seconds, and it glides back to
--     following you.
--   * It sits at the minimap's strata, so other windows go over it.
--   * The world map key (M) or the red button grows the window to most of the
--     screen instead of opening Blizzard's map, in the same chrome; M, the
--     button or Escape shrink it back. Anything else that opens Blizzard's
--     world map (the quest log, L) still opens it as usual.

local ADDON, ns = ...
local TILE_YARDS = 1600 / 3
local IDLE_FOLLOW = 6 -- seconds untouched before the map follows you again
local EXPAND_TIME, COLLAPSE_TIME = 0.22, 0.18
local EXPAND_ZOOM_OUT = 1.5 -- M zooms out this much (the window grows far more)
local EXPANDED_SIZE = 0.7 -- of the screen, each way
local MAPTYPE_ZONE = Enum.UIMapType.Zone
local SPAN = 200 -- yards across the window's shorter side to start with (Blizzard's widest: 467)

local db
local state = ns.state
local frame = ns.frame
local expanded = false -- grown to most of the screen (the world map, M)
local small -- meanwhile: the minimap-sized rect { left, top, w, h, zoom = } to return to

function ns.IsMapExpanded() return expanded end

---------------------------------------------------------------------------
-- Window rect, in the frame's own coordinates from UIParent's bottom-left:
-- { left, top, width, height }.
---------------------------------------------------------------------------

local function SetRect(r)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r[1], r[2])
	frame:SetSize(r[3], r[4])
end

-- The minimap's strata (other windows go over it); grown, the window's own.
local function SetHomeStrata()
	frame:SetFrameStrata(ns.Takeover.HomeStrata())
end

local function EaseOutCubic(t) return 1 - (1 - t) ^ 3 end

-- The minimap's home corner (Blizzard's cluster, and the stand-in holding the
-- buttons that hung off the minimap) fades out while the window is expanded,
-- so nothing of the minimap is left floating there.
local homeAlpha = 1 -- the cluster's own alpha, to restore
local SetHomeAlpha = ns.Takeover.SetHomeAlpha

local tween
local tweener = CreateFrame("Frame")
tweener:Hide()
tweener:SetScript("OnUpdate", ns.Timed("minimap mode tween", function(self, elapsed)
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
end))

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
	if db and not expanded and not tween and lastSide and lastSide > 0 then
		ns.SetZoom(ns.state.zoom * side / lastSide)
	end
	lastSide = side
end)

-- The minimap's spot, as a square.
local function MinimapSquare()
	local left, top, w, h = ns.Takeover.HomeRect()
	if not left then return nil end
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local side = math.max(w, h) * k
	return { left * k, top * k, side, side }
end

local function PlaceOnMinimap()
	local rect = MinimapSquare()
	if not rect then return end
	SetRect(rect)
	ns.SaveFrameLayout()
	ns.SetZoom(rect[3] / (SPAN / TILE_YARDS))
end

---------------------------------------------------------------------------
-- Growing into the world map (M)
---------------------------------------------------------------------------

-- Back on you at the zoom you had, following.
local function ReturnToSmallView(target, duration)
	if state.playerCol and state.playerMap == state.map then
		ns.FlyTo(state.playerCol, state.playerRow, target.zoom, duration, function() ns.SetFollow(true) end)
	else
		ns.SetZoom(target.zoom)
		ns.SetFollow(true)
	end
end

-- Escape while expanded shrinks the window back rather than closing it.
local escapeCatcher = CreateFrame("Frame", "MagicMapWorldMapEscape", UIParent)
escapeCatcher:Hide()
tinsert(UISpecialFrames, "MagicMapWorldMapEscape")

-- Your zone's rect in tile space (walking up from a sub-zone or micro map).
local function PlayerZoneRect()
	local mapID = C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	while info and info.mapType and info.mapType > MAPTYPE_ZONE and info.parentMapID do
		mapID = info.parentMapID
		info = C_Map.GetMapInfo(mapID)
	end
	local r = mapID and ns.MapRect(mapID)
	return r and r.inst == state.map and r or nil
end

local function Expand()
	if expanded then return end
	expanded = true
	-- Still shrinking back from the last time: the rect to return to stands.
	if not small then
		small = { frame:GetLeft(), frame:GetTop(), frame:GetWidth(), frame:GetHeight(), zoom = ns.GoalZoom() }
		homeAlpha = ns.Takeover.HomeAlpha()
	end
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local sw, sh = UIParent:GetWidth() * k, UIParent:GetHeight() * k
	local w, h = sw * EXPANDED_SIZE, sh * EXPANDED_SIZE
	frame:SetFrameStrata("HIGH")
	escapeCatcher:Show()
	frame:Raise()
	TweenTo({ (sw - w) / 2, (sh + h) / 2, w, h }, EXPAND_TIME, nil, { ns.Takeover.HomeAlpha(), 0 })
	-- Still on you, a little further out: the bigger window does the rest.
	-- Never further out than your whole zone, the way the world map opens.
	local zoom = state.zoom / EXPAND_ZOOM_OUT
	local r = PlayerZoneRect()
	if r then
		local vw = w - (frame:GetWidth() - ns.viewport:GetWidth()) -- the map area inside the border
		local vh = h - (frame:GetHeight() - ns.viewport:GetHeight())
		zoom = math.max(zoom, math.min(vw / (r.col1 - r.col0), vh / (r.row1 - r.row0)) * 0.92)
	end
	if state.playerCol and state.playerMap == state.map then
		ns.FlyTo(state.playerCol, state.playerRow, zoom, EXPAND_TIME + 0.1, function() ns.SetFollow(true) end)
	end
end

local function Collapse()
	if not expanded then return end
	expanded = false
	escapeCatcher:Hide()
	local target = small
	TweenTo({ target[1], target[2], target[3], target[4] }, COLLAPSE_TIME, function()
		small = nil
		SetHomeStrata()
		ns.SaveFrameLayout()
	end, { 0, homeAlpha })
	ReturnToSmallView(target, COLLAPSE_TIME)
end

escapeCatcher:SetScript("OnHide", Collapse)

local function ToggleExpanded()
	if expanded then Collapse() else Expand() end
end

-- M (ToggleWorldMap) grows our window instead of opening Blizzard's world
-- map, and M again shrinks it back. (M closing Blizzard's map, opened from
-- the quest log, is left alone; so is M while MagicMap is hidden.)
hooksecurefunc("ToggleWorldMap", function()
	if not frame:IsShown() or not WorldMapFrame:IsShown() then return end
	HideUIPanel(WorldMapFrame)
	ToggleExpanded()
end)

ns.modeButton:SetScript("OnClick", ToggleExpanded)
ns.Tooltip(ns.modeButton, function()
	return expanded and "Minimap (M)" or "Big map (M)"
end)

---------------------------------------------------------------------------
-- Showing and hiding
---------------------------------------------------------------------------

-- Hidden while grown (or growing): straight back to the minimap's size, so
-- it comes back there.
frame:HookScript("OnHide", function()
	if not (expanded or small) then return end
	StopTween()
	expanded = false
	escapeCatcher:Hide()
	SetHomeAlpha(homeAlpha)
	SetRect(small)
	ns.SaveFrameLayout()
	ns.SetZoom(small.zoom)
	small = nil
	SetHomeStrata()
end)

-- The first time it shows (no saved place yet), onto the minimap's spot.
frame:HookScript("OnShow", function()
	if db and not db.point then PlaceOnMinimap() end
	SetHomeStrata()
end)

-- /mm reset: back onto the minimap's spot, at its size.
function ns.ResetLayout()
	if expanded or tween then
		ns.Print("reset: shrink the map back first (M)")
		return
	end
	PlaceOnMinimap()
	ns.SetFollow(true)
	frame:Show()
end

-- Left alone after you've panned away, glide back to following you.
frame:HookScript("OnUpdate", ns.Timed("minimap mode idle", function()
	if expanded or state.follow or state.dragging or ns.IsAnimating() then return end
	if frame:IsMouseOver() or GetTime() - (state.lastInteract or 0) < IDLE_FOLLOW then return end
	ns.SetFollow(true, true)
end))

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", ns.TimedEvents("minimap mode", function()
	if small then
		-- Never come back expanded: save the minimap-sized window.
		db.point = { "TOPLEFT", "BOTTOMLEFT", small[1], small[2] }
		db.width, db.height, db.zoom = small[3], small[4], small.zoom
	end
end))

ns.On("Loaded", function(savedDB)
	db = savedDB
	-- An earlier version's separate window: its layout was the window's, so
	-- the one minimap mode kept takes over, else the minimap's spot.
	if db.minimapMode == false then
		local m = db.minimapLayout
		if m then
			db.point, db.width, db.height = { "TOPLEFT", "BOTTOMLEFT", m[1], m[2] }, m[3], m[4]
			SetRect(m)
			ns.SetZoom(m.zoom)
		else
			db.point, db.width, db.height = nil, 200, 200
			frame:SetSize(200, 200)
		end
	end
	db.minimapMode, db.minimapLayout, db.normalLayout, db.minimapBlips = nil, nil, nil, nil
	SetHomeStrata()
end)

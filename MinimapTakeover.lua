-- The minimap takeover: every change MagicMap makes to Blizzard's Minimap,
-- its cluster, its tracking and the HereBeDragons pins on it lives here, so
-- all of it can be put back.
--
--   Engage()   takes the Minimap into the map window: its children and the
--              things hanging off it go to a stand-in at its usual spot, the
--              cluster hides, the Minimap sits in our viewport, faded to its
--              blips (Minimap:SetAlpha only fades terrain, as FarmHud relies
--              on), square, its rim icons pushed off screen.
--   Release()  puts all of that back.
--   In between, MinimapBlips.lua (the policy) only places it: Place (its
--   blips over our terrain), ShowWhole (indoors), Hide, SetLevel.
--
-- Every change Engage makes is paired with its undo on a list, and Release
-- runs the list backwards. Nothing else restores anything, so what comes
-- back is exactly what was taken.
--
-- Relies on behaviour the client doesn't document (README, "Unknowns"):
--   * Minimap:SetAlpha(0) hides its terrain but not its blips;
--   * blips hide where the Minimap's mask texture is transparent;
--   * C_Minimap.SetMinimapInsetInfo pushes the rim's icons outward;
--   * HereBeDragons' SetMinimapObject and its minimapPins table.

local ADDON, ns = ...
local T = {}
ns.Takeover = T

local state = ns.state
local db
local engaged = false
local indoor = false   -- wearing the Minimap whole (ShowWhole) rather than its blips
local shown = false    -- the Minimap is on the map this frame (its arrow stands in for ours)
local hover = false    -- the mouse is over the Minimap
local undo = {}        -- what Engage changed, as functions that change it back
local ours = {}        -- our own children of the Minimap, which stay on it
local lastMask, lastInsets, lastSize

T.SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
-- Blizzard's round mask, put back on release. (Retail-engine clients, Forever
-- included, have only the first.)
local ROUND_MASK = GetFileIDFromPath and GetFileIDFromPath("Interface\\Masks\\CircleMaskScalable")
	and "Interface\\Masks\\CircleMaskScalable" or "Textures\\MinimapMask"

local function OnRelease(fn) undo[#undo + 1] = fn end

-- A frame of ours parented to the Minimap: it stays there when Engage clears it out.
function T.Own(frame) ours[frame] = true end

---------------------------------------------------------------------------
-- Our frames
---------------------------------------------------------------------------

-- Holds what hung off the Minimap, at its usual spot, hidden with the cluster.
local standIn = CreateFrame("Frame", "MagicMapMinimapStandIn", UIParent)
standIn:Hide()
ns.minimapStandIn = standIn

-- HereBeDragons' minimap pins, outdoors: an ordinary frame in the window, the
-- Minimap's size and in its place, which the window clips (the Minimap
-- itself isn't clipped). It answers what HereBeDragons asks a minimap
-- (FarmHud does the same).
local pinHost = CreateFrame("Frame", "MagicMapMinimapPins", ns.viewport)
pinHost:Hide()
pinHost.GetZoom = function() return Minimap:GetZoom() end
pinHost.GetZoomLevels = function() return Minimap:GetZoomLevels() end
pinHost.SetZoom = function(_, z) Minimap:SetZoom(z) end -- (clients without C_Minimap.GetViewRadius)

-- The minimap pins of an addon whose world-map pins we already host
-- (AddonPins.lua) go here, out of sight: they'd only repeat those.
local hiddenHost = CreateFrame("Frame", nil, ns.viewport)
hiddenHost:Hide()
hiddenHost:SetSize(1, 1)
hiddenHost.GetZoom, hiddenHost.GetZoomLevels, hiddenHost.SetZoom = pinHost.GetZoom, pinHost.GetZoomLevels, pinHost.SetZoom

-- Indoors: a black backdrop over our map, under the Minimap, catching the
-- mouse (our map isn't there to drag) and wheeling the Minimap's zoom.
local indoorBg = CreateFrame("Frame", nil, ns.viewport)
indoorBg:SetAllPoints()
indoorBg:Hide()
indoorBg:CreateTexture(nil, "BACKGROUND"):SetAllPoints()
indoorBg:GetRegions():SetColorTexture(0, 0, 0, 1)
indoorBg:EnableMouse(true)
indoorBg:EnableMouseWheel(true)
indoorBg:SetScript("OnMouseWheel", function(_, delta)
	local z = Minimap:GetZoom() + delta
	if z >= 0 and z < Minimap:GetZoomLevels() then Minimap:SetZoom(z) end
end)

---------------------------------------------------------------------------
-- HereBeDragons
---------------------------------------------------------------------------

-- Every copy of HereBeDragons-Pins (Questie bundles its own, renamed; see
-- AddonPins.lua). rescan: look for copies loaded since.
local NO_LIBS = {}
local function HBDPinsRaw(rescan)
	return ns.HBDPinLibs and ns.HBDPinLibs(rescan) or NO_LIBS
end

-- The copies drawing on the real Minimap or our hosts (not, say, FarmHud's).
local mine = {}
local function HBDPins()
	wipe(mine)
	for _, hbd in ipairs(HBDPinsRaw()) do
		if hbd.Minimap == Minimap or hbd.Minimap == pinHost or hbd.Minimap == hiddenHost then mine[#mine + 1] = hbd end
	end
	return mine
end

-- Pins are positioned on the Minimap by their addons; they travel with it.
local function IsPin(obj)
	for _, hbd in ipairs(HBDPinsRaw()) do
		if type(hbd.minimapPins) == "table" and hbd.minimapPins[obj] then return true end
	end
	local name = obj.GetDebugName and obj:GetDebugName()
	return name and name:find("GatherMatePin", 1, true) ~= nil
end

local function HostFor(hbd, host)
	if host ~= Minimap and ns.HostsWorldPins and ns.HostsWorldPins(hbd) then return hiddenHost end
	return host
end

-- Have HereBeDragons (re-)place its pins on `host` now: it only re-reads the
-- size once a second, and they must keep in step with the terrain.
local function PlacePins(host)
	for _, hbd in ipairs(HBDPins()) do
		if hbd.SetMinimapObject then
			local to = HostFor(hbd, host)
			hbd:SetMinimapObject(to)
			-- They must still clear our terrain and layers.
			for pin in pairs(hbd.minimapPins or {}) do
				if pin.GetFrameLevel and pin:GetFrameLevel() <= to:GetFrameLevel() then pin:SetFrameLevel(to:GetFrameLevel() + 1) end
			end
		end
	end
end

-- Some copy isn't drawing on `host` yet.
local function PinsOff(host)
	for _, hbd in ipairs(HBDPins()) do
		if hbd.Minimap ~= HostFor(hbd, host) then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Moving things off the Minimap
---------------------------------------------------------------------------

-- Swap anchors relative to `from` for the same anchors relative to `to`.
local function Reanchor(obj, from, to)
	if not obj.GetNumPoints then return false end
	local points = {}
	for i = 1, obj:GetNumPoints() do
		local p, rel, rp, x, y = obj:GetPoint(i)
		if rel == from then points[#points + 1] = { p, rp, x, y } end
	end
	for _, p in ipairs(points) do obj:SetPoint(p[1], to, p[2], p[3], p[4]) end
	return #points > 0
end

-- A new parent, keeping the draw layer (regions) or strata and level (frames).
local function Reparent(obj, parent)
	local layer, sublevel, strata, level
	if obj.GetDrawLayer then
		layer, sublevel = obj:GetDrawLayer()
	else
		strata, level = obj:GetFrameStrata(), obj:GetFrameLevel()
	end
	obj:SetParent(parent)
	if layer then
		obj:SetDrawLayer(layer, sublevel)
	else
		obj:SetFrameStrata(strata)
		obj:SetFrameLevel(level)
	end
end

local function Movable(obj)
	local t = obj:GetObjectType()
	return t ~= "Line" and t ~= "MaskTexture" and not IsPin(obj) and not ours[obj]
		and not (obj.IsProtected and obj:IsProtected())
end

local function MoveToStandIn(obj)
	if not Movable(obj) then return end
	Reparent(obj, standIn)
	Reanchor(obj, Minimap, standIn)
	OnRelease(function()
		Reparent(obj, Minimap)
		Reanchor(obj, standIn, Minimap)
	end)
end

-- Blizzard's minimap parts that aren't its children but hang off it (borders,
-- the compass ring, zoom buttons), a few levels down from its parent.
local function ReanchorAround(frame, depth)
	local function One(obj)
		if Reanchor(obj, Minimap, standIn) then
			OnRelease(function() Reanchor(obj, standIn, Minimap) end)
		end
	end
	for _, obj in ipairs({ frame:GetRegions() }) do One(obj) end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child ~= Minimap and child ~= standIn and not (child.IsProtected and child:IsProtected()) then
			One(child)
			if depth > 1 then ReanchorAround(child, depth - 1) end
		end
	end
end

---------------------------------------------------------------------------
-- The rim: Blizzard's big arrows toward your target sit on it; ours
-- (Path.lua) point the way instead. The client won't swap their art, but it
-- lets the rim's icons be pushed outward, so they go far off screen. Its
-- quest, dig-site and bonus-objective rings (the patterned circle where an
-- area runs past the edge) mark a rim we don't show, so they go too.
---------------------------------------------------------------------------

local BLOB_RINGS = { "SetQuestBlobRingScalar", "SetArchBlobRingScalar", "SetTaskBlobRingScalar" }

local function ClearRim(on)
	for _, method in ipairs(BLOB_RINGS) do
		if Minimap[method] then pcall(Minimap[method], Minimap, on and 0 or 1) end
	end
	if not (C_Minimap and C_Minimap.SetMinimapInsetInfo) then return end
	if on then
		pcall(C_Minimap.SetMinimapInsetInfo, 0, 360, 1000) -- the whole rim (degrees or radians), 1000x out
	else
		pcall(C_Minimap.ClearMinimapInsetInfo)
	end
end

---------------------------------------------------------------------------
-- Ours first: Blizzard's own markers for what our layers draw are tracking
-- filters (flight masters, quest objectives, points of interest). They go
-- off while the Minimap's blips are on our map and come back after (and at
-- logout). MagicMapDB remembers which we turned off, so a /reload mid-way
-- restores them too. /mm dupes keeps Blizzard's.
---------------------------------------------------------------------------

local F = Enum and Enum.MinimapTrackingFilter or {}
local DUPLICATES = { [F.TaxiNode or 8] = "flight", [F.QuestPOIs or 65536] = "quests", [F.POI or 8192] = "areaPOIs" }
T.DUPLICATES = DUPLICATES

local function TrackingAPI()
	local C = C_Minimap
	return C and C.GetNumTrackingTypes and C.GetTrackingFilter and C.GetTrackingInfo and C.SetTracking and C
end
T.CanTrack = function() return TrackingAPI() ~= nil end

-- on: our layers are on the map in Blizzard's place.
local function SyncTracking(on)
	local C = TrackingAPI()
	if not (db and C) then return end
	db.trackingOff = db.trackingOff or {}
	local off = db.trackingOff
	for i = 1, C.GetNumTrackingTypes() or 0 do
		local filter = C.GetTrackingFilter(i)
		local id = filter and filter.filterID
		local layer = id and DUPLICATES[id]
		if layer then
			local info = C.GetTrackingInfo(i)
			local want = on and db.hideDupes ~= false and ns.LayerEnabled and ns.LayerEnabled(layer)
			if want and info and info.active then
				if pcall(C.SetTracking, i, false) then off[id] = true end
			elseif not want and off[id] and info then -- (no info yet at login: next time)
				if not info.active then pcall(C.SetTracking, i, true) end
				off[id] = nil
			end
		end
	end
end

local trackingOn, trackingAt -- what SyncTracking last did, and when
-- Each frame; acts on a change, and again now and then (a layer was toggled).
function T.KeepTracking(on)
	local now = GetTime()
	if on == trackingOn and now - trackingAt < 2 then return end
	trackingOn, trackingAt = on, now
	SyncTracking(on)
end

-- Apply a change of db.hideDupes now.
function T.RefreshTracking()
	trackingOn = nil
	if engaged and not indoor then T.KeepTracking(true) end
end

---------------------------------------------------------------------------
-- Engage and release
---------------------------------------------------------------------------

-- The Minimap's own setup, put back last.
local function KeepMinimap()
	local m = Minimap
	local parent, w, h = m:GetParent(), m:GetSize()
	local points = {}
	for i = 1, m:GetNumPoints() do points[i] = { m:GetPoint(i) } end
	local scale, strata, level = m:GetScale(), m:GetFrameStrata(), m:GetFrameLevel()
	local zoom, alpha, shownBefore = m:GetZoom(), m:GetAlpha(), m:IsShown()
	local mouse, wheel, clamped = m:IsMouseEnabled(), m:IsMouseWheelEnabled(), m:IsClampedToScreen()
	OnRelease(function()
		m:SetParent(parent)
		m:ClearAllPoints()
		for _, p in ipairs(points) do m:SetPoint(unpack(p)) end
		m:SetSize(w, h)
		m:SetScale(scale)
		m:SetFrameStrata(strata)
		m:SetFrameLevel(level)
		m:EnableMouse(mouse)
		m:EnableMouseWheel(wheel)
		m:SetHitRectInsets(0, 0, 0, 0)
		m:SetAlpha(alpha)
		m:SetZoom(zoom)
		m:SetShown(shownBefore)
		m:SetClampedToScreen(clamped)
		m:SetMaskTexture(ROUND_MASK)
	end)
	return parent, points, w, h, scale, strata, level
end

-- The window's strata changes (minimap mode, expanding): the Minimap and our
-- host go with it. Above our layers, below our pins and overlay; indoors,
-- above the backdrop.
local function FollowWindow()
	local strata = ns.frame:GetFrameStrata()
	local base = ns.overlay:GetFrameLevel()
	if Minimap:GetFrameStrata() ~= strata then Minimap:SetFrameStrata(strata) end
	local level = base + (indoor and 2 or -1)
	if Minimap:GetFrameLevel() ~= level then Minimap:SetFrameLevel(level) end
	if pinHost:GetFrameStrata() ~= strata then pinHost:SetFrameStrata(strata) end
	if pinHost:GetFrameLevel() ~= base - 1 then pinHost:SetFrameLevel(base - 1) end
end

function T.Engage()
	if engaged then return end
	engaged = true
	HBDPinsRaw(true) -- any copy loaded since

	-- Undone last: pins back on the Minimap once it's back at its own size.
	OnRelease(function()
		pinHost:Hide()
		for _, hbd in ipairs(HBDPins()) do
			if hbd.SetMinimapObject then hbd:SetMinimapObject(Minimap) end
		end
	end)
	local parent, points, w, h, scale, strata, level = KeepMinimap()

	-- The stand-in takes the Minimap's place exactly (hidden: it only holds
	-- things, and anything anchored to it stays where it was).
	standIn:SetParent(parent)
	standIn:SetScale(scale)
	standIn:SetFrameStrata(strata)
	standIn:SetFrameLevel(level)
	standIn:ClearAllPoints()
	for _, p in ipairs(points) do standIn:SetPoint(unpack(p)) end
	standIn:SetSize(w, h)
	for _, obj in ipairs({ Minimap:GetChildren() }) do MoveToStandIn(obj) end
	for _, obj in ipairs({ Minimap:GetRegions() }) do MoveToStandIn(obj) end
	local root = MinimapCluster or parent
	if root then ReanchorAround(root, 3) end
	if MinimapCluster and MinimapCluster:IsShown() then
		MinimapCluster:Hide()
		OnRelease(function() MinimapCluster:Show() end)
	end

	-- Into the map. Hover still reaches the Minimap (the game's own blip
	-- tooltips); clicks and the wheel go through to the map, for dragging and
	-- zooming. Never clamped: that would slide its blips off ours.
	Minimap:SetParent(ns.viewport)
	Minimap:SetScale(1)
	FollowWindow()
	-- The pins that stayed must still clear our terrain and layers.
	for _, pin in ipairs({ Minimap:GetChildren() }) do
		if pin:GetFrameLevel() <= Minimap:GetFrameLevel() then pin:SetFrameLevel(Minimap:GetFrameLevel() + 1) end
	end
	if Minimap.SetMouseClickEnabled and Minimap.SetMouseMotionEnabled then
		Minimap:EnableMouse(true)
		Minimap:SetMouseClickEnabled(false)
		Minimap:SetMouseMotionEnabled(true)
	else
		Minimap:EnableMouse(false)
	end
	Minimap:EnableMouseWheel(false)
	Minimap:SetAlpha(0)
	Minimap:SetClampedToScreen(false)
	lastMask, lastInsets, lastSize = nil, nil, nil
	T.SetMask(T.SQUARE_MASK)
	ClearRim(true)
	OnRelease(function() ClearRim(false) end)
	OnRelease(function()
		trackingOn = nil
		SyncTracking(false)
	end)
	OnRelease(function() T.SetIndoor(false) end) -- undone first
	Minimap:Hide() -- until the policy finds it a settled spot
	shown = false
end

-- Everything Engage changed, changed back, newest first. Every step runs
-- even if one fails; the first failure is raised after.
function T.Release()
	if not engaged then return end
	engaged = false
	shown = false
	local failure
	for i = #undo, 1, -1 do
		local ok, err = pcall(undo[i])
		if not ok and not failure then failure = err end
		undo[i] = nil
	end
	lastMask, lastInsets, lastSize = nil, nil, nil
	if failure then error(failure, 0) end
end

function T.IsEngaged() return engaged end

---------------------------------------------------------------------------
-- Placing it (between Engage and Release)
---------------------------------------------------------------------------

function T.SetMask(mask)
	if mask == lastMask then return end
	lastMask = mask
	Minimap:SetMaskTexture(mask)
end

-- Hover reaches the Minimap only where its blips may show.
local function SetHitInsets(l, r, t, b)
	local key = string.format("%d %d %d %d", l, r, t, b)
	if key == lastInsets then return end
	lastInsets = key
	Minimap:SetHitRectInsets(l, r, t, b)
end

-- Indoors (on) or out: the Minimap shown whole over a backdrop, or faded to
-- just its blips under our markers.
function T.SetIndoor(on)
	if on == indoor then return end
	indoor = on
	indoorBg:SetFrameLevel(ns.overlay:GetFrameLevel() + 1)
	indoorBg:SetShown(on)
	FollowWindow()
	Minimap:SetAlpha(on and 1 or 0)
	ClearRim(not on) -- indoors it's Blizzard's minimap, rim and all
	if on then
		T.SetMask(T.SQUARE_MASK)
		SetHitInsets(0, 0, 0, 0)
		pinHost:Hide()
	end
	lastSize = nil
end

function T.Level() return Minimap:GetZoom() end
function T.Levels() return Minimap:GetZoomLevels() end

-- Its zoom level; true if that changed it (the client takes a moment to apply one).
function T.SetLevel(z)
	if Minimap:GetZoom() == z then return false end
	Minimap:SetZoom(z)
	return true
end

function T.Hide()
	if Minimap:IsShown() then Minimap:Hide() end
	pinHost:Hide()
	shown = false
end

-- Indoors: the Minimap whole, the size of the window, centred.
function T.ShowWhole()
	FollowWindow()
	local w, h = ns.viewport:GetSize()
	local d = math.floor(math.min(w, h) + 0.5)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", ns.viewport)
	if d ~= lastSize then
		lastSize = d
		Minimap:SetSize(d, d)
		PlacePins(Minimap)
	end
	if not Minimap:IsShown() then Minimap:Show() end
	shown = true
end

-- Outdoors: centred on (x, y) of `canvas` (you, on the tiles' canvas, so it
-- moves with them pixel for pixel), d px across, `mask` confining its blips
-- to the square `insets` leave for hover ({ left, right, top, bottom }).
-- alpha: its terrain's (0 but for /mm sync).
function T.Place(canvas, x, y, d, mask, insets, alpha)
	FollowWindow()
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", canvas, "TOPLEFT", x, y)
	pinHost:ClearAllPoints()
	pinHost:SetPoint("CENTER", canvas, "TOPLEFT", x, y)
	T.SetMask(mask)
	SetHitInsets(insets[1], insets[2], insets[3], insets[4])
	d = math.floor(d + 0.5)
	if d ~= lastSize or PinsOff(pinHost) then
		lastSize = d
		Minimap:SetSize(d, d)
		pinHost:SetSize(d, d)
		PlacePins(pinHost)
	end
	if Minimap:GetAlpha() ~= alpha then Minimap:SetAlpha(alpha) end
	if not Minimap:IsShown() then Minimap:Show() end
	pinHost:Show()
	shown = true
end

---------------------------------------------------------------------------
-- The minimap's home corner (the cluster, and the stand-in holding what hung
-- off the Minimap), for minimap mode's expand and collapse.
---------------------------------------------------------------------------

function T.HomeAlpha() return MinimapCluster and MinimapCluster:GetAlpha() or 1 end

function T.SetHomeAlpha(a)
	if MinimapCluster then MinimapCluster:SetAlpha(a) end
	standIn:SetAlpha(a)
end

function T.HomeStrata() return MinimapCluster and MinimapCluster:GetFrameStrata() or "LOW" end

-- The minimap's rect in UIParent coordinates (the stand-in's while engaged).
function T.HomeRect()
	local src = engaged and standIn or Minimap
	local left, top, w, h = src:GetLeft(), src:GetTop(), src:GetSize()
	if not (left and top) then return nil end
	local s = src:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return left * s, top * s, w * s, h * s
end

---------------------------------------------------------------------------
-- Queries for the rest of the addon
---------------------------------------------------------------------------

-- The Minimap is on the map, its arrow standing in for ours.
function ns.MinimapShowsPlayer() return shown end

-- The Minimap has the mouse (its hover handler owns GameTooltip).
function ns.MinimapHasMouse() return hover and engaged and Minimap:IsVisible() end

---------------------------------------------------------------------------
-- Tooltips. While the Minimap has the mouse, Blizzard's hover handler
-- (Minimap_OnUpdate, every frame) takes GameTooltip for the blips under the
-- cursor. Right after it, if it found none, the quest area there gets it;
-- our pins sit above the Minimap and take the mouse before either. Layers'
-- own hover (OnMapHover) stands aside meanwhile, so nothing flickers.
---------------------------------------------------------------------------

local function AfterMinimapHover()
	if not engaged or indoor or not ns.ShowQuestAreaTooltip then return end
	if GameTooltip:IsShown() and GameTooltip:NumLines() > 0 and GameTooltip:IsOwned(UIParent) then return end -- a blip
	ns.ShowQuestAreaTooltip(ns.CursorTile())
end
if Minimap_OnUpdate then hooksecurefunc("Minimap_OnUpdate", AfterMinimapHover) end
Minimap:HookScript("OnEnter", function() hover = true end)
Minimap:HookScript("OnLeave", function() hover = false end)

---------------------------------------------------------------------------
-- Saved state
---------------------------------------------------------------------------

ns.On("Loaded", function(savedDB)
	db = savedDB
	if db.hideDupes == nil then db.hideDupes = true end
end)

-- Tracking we turned off comes back at logout, and after a /reload (its
-- state is known only once the client has sent it).
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "MINIMAP_UPDATE_TRACKING" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGOUT" or not (engaged and not indoor) then
		if db and db.trackingOff and next(db.trackingOff) then SyncTracking(false) end
	end
end)

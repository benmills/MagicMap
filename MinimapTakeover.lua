-- The minimap takeover: every change MagicMap makes to Blizzard's Minimap,
-- its cluster, its tracking and the HereBeDragons pins on it lives here, so
-- all of it can be put back.
--
--   Engage()   takes the Minimap out of its corner: its children and the
--              things hanging off it go to a stand-in at its usual spot, the
--              cluster hides, and the Minimap is parented into our viewport.
--   Release()  puts all of that back.
--
-- Every change Engage makes is paired with its undo on a list, and Release
-- runs the list backwards. Nothing else restores anything, so what comes
-- back is exactly what was taken.
--
-- While engaged, the Minimap has one of two jobs, set each frame:
--   * outdoors, the sensor: SENSOR_PX screen units square, centred under our
--     window but kept on the screen, its own icons shrunk out of sight (alpha
--     0 doesn't hide them), no ground, no mouse, at its widest zoom, north up.
--     Blips.lua reads its blips through a pretend mouse and draws them on our
--     map itself. The HereBeDragons pins on it (addons' minimap pins, such as
--     GatherMate's) are hosted on a frame of ours, the Minimap's view in map
--     pixels, centred on you;
--   * indoors, the whole Minimap: its terrain, rim and hover tooltips, in the
--     window over a black backdrop, the wheel zooming it. Its arrow stands in
--     for ours.
--
-- Tracking: Blizzard's own markers for what our layers draw (flight masters,
-- quest objectives, points of interest) are off while we're outdoors, and
-- back on at release and logout. MagicMapDB remembers which we turned off, so
-- a /reload mid-way restores them too.
--
-- Relies on behaviour the client doesn't document (README, "Unknowns"):
--   * the Minimap answers a pretend mouse (Blips.lua) while it's invisible;
--   * HereBeDragons' SetMinimapObject and its minimapPins table.

local ADDON, ns = ...
local T = {}
ns.Takeover = T

local TILE_YARDS = ns.TILE_YARDS
-- The sensor's side in screen units, whatever our window's size or scale:
-- a blip answers in a square about 16 screen units wide (Blips.lua), so
-- the bigger it is, the smaller that square in yards (about 25 yd here)
-- and the closer two blips of a name can be told apart; but the more
-- points a sweep tries. (Positions are exact at any size.)
local SENSOR_PX = 300
local SENSOR_MARGIN = 2 -- screen units it keeps inside the screen's edge (off it, the client stops updating its blips)
local SENSOR_ICONS = 0.05 -- its own icons' scale: tiny (what it answers doesn't change with it)
-- Open-air cities the Minimap draws as an indoor map, much of its ground
-- grey (seen in game): our terrain there instead of its floor plan. By uiMap.
local OPEN_CITIES = { [1454] = "Orgrimmar" }
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 } -- yards across its outdoor view, by zoom level
local OUTDOOR_WIDEST = OUTDOOR[0]
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 } -- yards across its indoor view, by zoom level

local db
local engaged = false
local mode                -- "whole" (indoors) or "sensor" (outdoors) while engaged; nil before
local undo = {}           -- what Engage changed, as functions that change it back
local lastSize           -- indoors: the size the whole Minimap was last set to
local pinSize             -- outdoors: the size the pins' host was last set to
local pinsCheckAt = 0     -- when the pins next check every HereBeDragons copy is on our host
local placed = {}         -- where the pins' host was last anchored: canvas, x, y
local sensorAt            -- where PlaceSensor last put the sensor (screen units)
local followed, followedMode -- the window strata and mode FollowWindow last applied
local trackingOn, trackingAt -- what SyncTracking last did, and when

local function OnRelease(fn) undo[#undo + 1] = fn end

---------------------------------------------------------------------------
-- Our frames
---------------------------------------------------------------------------

-- Holds what hung off the Minimap, at its usual spot, hidden with the cluster.
local standIn = CreateFrame("Frame", "MagicMapMinimapStandIn", UIParent)
standIn:Hide()
ns.minimapStandIn = standIn

-- HereBeDragons' minimap pins, outdoors: an ordinary frame in the window, the
-- Minimap's view in size, which the window clips. It answers what
-- HereBeDragons asks a minimap (FarmHud does the same).
local pinHost = CreateFrame("Frame", "MagicMapMinimapPins", ns.viewport)
pinHost:Hide()
pinHost.GetZoom = function() return Minimap:GetZoom() end
pinHost.GetZoomLevels = function() return Minimap:GetZoomLevels() end
pinHost.SetZoom = function(_, z) Minimap:SetZoom(z) end

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

-- The copies drawing on the real Minimap or our hosts (not, say, FarmHud's).
local mine = {}
local function HBDPins()
	wipe(mine)
	for _, hbd in ipairs(ns.HBDPinLibs()) do
		if hbd.Minimap == Minimap or hbd.Minimap == pinHost or hbd.Minimap == hiddenHost then mine[#mine + 1] = hbd end
	end
	return mine
end

-- Pins are positioned on the Minimap by their addons; they travel with it.
local function IsPin(obj)
	for _, hbd in ipairs(ns.HBDPinLibs()) do
		if type(hbd.minimapPins) == "table" and hbd.minimapPins[obj] then return true end
	end
	local name = obj.GetDebugName and obj:GetDebugName()
	return name and name:find("GatherMatePin", 1, true) ~= nil
end

-- With Rotate Minimap, HereBeDragons turns its pins with your facing (it reads
-- the setting, not the Minimap), while the Minimap stays north up in our map:
-- they'd land in the wrong places, so they stay out of sight.
local function HostFor(hbd, host)
	if host == Minimap then return host end
	if ns.HostsWorldPins(hbd) or C_CVar.GetCVar("rotateMinimap") == "1" then return hiddenHost end
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
	return t ~= "Line" and t ~= "MaskTexture" and not IsPin(obj)
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
-- Tracking. Ours first: Blizzard's own markers for what our layers draw are
-- tracking filters, off while we're outdoors (the sensor's blips are drawn
-- on our map, and our layers draw these too).
---------------------------------------------------------------------------

local F = Enum.MinimapTrackingFilter
local DUPLICATES = { [F.TaxiNode] = "flight", [F.QuestPOIs] = "quests", [F.POI] = "areaPOIs" }
T.DUPLICATES = DUPLICATES

-- on: our layers are on the map in Blizzard's place.
local function SyncTracking(on)
	if not db then return end
	local C = C_Minimap
	db.trackingOff = db.trackingOff or {}
	local off = db.trackingOff
	for i = 1, C.GetNumTrackingTypes() or 0 do
		local filter = C.GetTrackingFilter(i)
		local id = filter and filter.filterID
		local layer = id and DUPLICATES[id]
		if layer then
			local info = C.GetTrackingInfo(i)
			local want = on and ns.LayerEnabled(layer)
			if want and info and info.active then
				if pcall(C.SetTracking, i, false) then off[id] = true end
			elseif not want and off[id] and info then -- (no info yet at login: next time)
				if not info.active then pcall(C.SetTracking, i, true) end
				off[id] = nil
			end
		end
	end
end

-- Each frame; acts on a change, and again now and then (a layer was toggled).
local function KeepTracking(on)
	local now = GetTime()
	if on == trackingOn and now - trackingAt < 2 then return end
	trackingOn, trackingAt = on, now
	SyncTracking(on)
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
	local ground, unrotated = C_Minimap.GetDrawGroundTextures(), C_Minimap.IsRotateMinimapIgnored()
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
		m:SetAlpha(alpha)
		C_Minimap.SetDrawGroundTextures(ground)
		C_Minimap.SetIgnoreRotateMinimap(unrotated)
		m:SetZoom(zoom)
		m:SetShown(shownBefore)
		m:SetClampedToScreen(clamped)
	end)
	return parent, points, w, h, scale, strata, level
end

-- Just beneath `frame`: the strata and level to draw under it.
local function Beneath(frame)
	local strata, level = frame:GetFrameStrata(), frame:GetFrameLevel()
	if level > 0 then return strata, level - 1 end
	for i = 2, #STRATA do
		if STRATA[i] == strata then return STRATA[i - 1], 100 end
	end
	return strata, 0
end

-- The window's strata changes (growing and shrinking): the Minimap and our
-- host go with it. Outdoors, under the whole window; indoors, above the
-- backdrop. The pins' host sits just under our layers and overlay.
local function FollowWindow()
	local strata = ns.frame:GetFrameStrata()
	if strata == followed and mode == followedMode then return end
	followed, followedMode = strata, mode
	local base = ns.overlay:GetFrameLevel()
	-- Indoors above our backdrop; the sensor beneath the whole window, so
	-- our terrain covers what's left of its blips (alpha doesn't fade them).
	local mStrata, level = strata, base + 2
	if mode == "sensor" then mStrata, level = Beneath(ns.frame) end
	if Minimap:GetFrameStrata() ~= mStrata then Minimap:SetFrameStrata(mStrata) end
	if Minimap:GetFrameLevel() ~= level then Minimap:SetFrameLevel(level) end
	if pinHost:GetFrameStrata() ~= strata then pinHost:SetFrameStrata(strata) end
	if pinHost:GetFrameLevel() ~= base - 1 then pinHost:SetFrameLevel(base - 1) end
end

local function Engage()
	if engaged then return end
	engaged = true
	ns.HBDPinLibs(true) -- any copy loaded since

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
	ReanchorAround(MinimapCluster, 3)
	if MinimapCluster:IsShown() then
		MinimapCluster:Hide()
		OnRelease(function() MinimapCluster:Show() end)
	end

	OnRelease(function() Minimap:SetIconScale(1) end) -- (the client's own; it can't be read back)
	-- Into the window. Never clamped: that would slide its blips off ours.
	Minimap:SetParent(ns.viewport)
	Minimap:SetScale(1)
	followed = nil
	FollowWindow()
	-- Pins that stayed on it (indoors, they're in view) must clear our layers.
	for _, pin in ipairs({ Minimap:GetChildren() }) do
		if pin:GetFrameLevel() <= Minimap:GetFrameLevel() then pin:SetFrameLevel(Minimap:GetFrameLevel() + 1) end
	end
	C_Minimap.SetIgnoreRotateMinimap(true) -- our map doesn't turn, nor does the sensor
	Minimap:SetClampedToScreen(false)
	OnRelease(function()
		trackingOn = nil
		SyncTracking(false)
	end)
end

-- Everything Engage changed, changed back, newest first. Every step runs
-- even if one fails; the first failure is raised after.
local function Release()
	if not engaged then return end
	engaged = false
	mode = nil
	ns.IndoorArt.Show(nil)
	indoorBg:Hide()
	local failure
	for i = #undo, 1, -1 do
		local ok, err = pcall(undo[i])
		if not ok and not failure then failure = err end
		undo[i] = nil
	end
	lastSize, pinSize, followed = nil, nil, nil
	wipe(placed)
	if failure then error(failure, 0) end
end

---------------------------------------------------------------------------
-- The two modes
---------------------------------------------------------------------------

-- Indoors ("whole") or out ("sensor"): what the Minimap is set up as. Applied
-- once per change; each mode's frame work is in Update.
local function SetMode(m)
	if m == mode then return end
	mode = m
	lastSize, pinSize = nil, nil
	wipe(placed)
	FollowWindow()
	indoorBg:SetFrameLevel(ns.overlay:GetFrameLevel() + 1)
	indoorBg:SetShown(m == "whole")
	-- The sensor must stay on the screen (off it, the client stops updating
	-- its blips) and draws under our window; indoors it's in the window.
	Minimap:SetParent(m == "whole" and ns.viewport or UIParent)
	followed = nil
	FollowWindow()
	Minimap:ClearAllPoints()
	sensorAt = nil
	if m == "whole" then Minimap:SetPoint("CENTER", ns.viewport) end
	Minimap:SetIconScale(m == "whole" and 1 or SENSOR_ICONS)
	if m == "whole" then
		-- Blizzard's minimap as it is: terrain, rim, its own hover tooltips.
		-- The wheel goes to the backdrop, which zooms it.
		Minimap:SetAlpha(1)
		C_Minimap.SetDrawGroundTextures(true)
		Minimap:EnableMouse(true)
		Minimap:SetMouseClickEnabled(false)
		Minimap:SetMouseMotionEnabled(true)
		Minimap:EnableMouseWheel(false)
		pinHost:Hide()
	else
		-- The sensor: drawn nowhere, at its widest zoom, the mouse left alone.
		Minimap:SetAlpha(0)
		C_Minimap.SetDrawGroundTextures(false)
		Minimap:SetZoom(0)
		Minimap:EnableMouse(false)
		Minimap:SetMouseMotionEnabled(false)
		Minimap:EnableMouseWheel(false)
		Minimap:Show()
	end
end

-- Outdoors: SENSOR_PX across, centred on our map (under it, so our terrain
-- covers what of its blips shows at all), but all of it on the screen.
local function PlaceSensor()
	local ms = Minimap:GetEffectiveScale()
	local vx, vy = ns.viewport:GetCenter()
	if not vx then return end
	local vs = ns.viewport:GetEffectiveScale()
	local sw, sh = UIParent:GetWidth() * UIParent:GetEffectiveScale(), UIParent:GetHeight() * UIParent:GetEffectiveScale()
	local half = SENSOR_PX / 2 + SENSOR_MARGIN
	local x = math.max(half, math.min(sw - half, vx * vs))
	local y = math.max(half, math.min(sh - half, vy * vs))
	local d = SENSOR_PX / ms
	if math.abs(Minimap:GetWidth() - d) > 0.01 then Minimap:SetSize(d, d) end
	if not sensorAt or x ~= sensorAt.x or y ~= sensorAt.y then
		sensorAt = { x = x, y = y }
		Minimap:ClearAllPoints()
		Minimap:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / ms, y / ms)
	end
end

-- Indoors: the Minimap whole, the size of the window, centred.
local function ShowWhole()
	FollowWindow()
	local w, h = ns.ViewSize()
	local d = math.floor(math.min(w, h) + 0.5)
	if d ~= lastSize then
		lastSize = d
		Minimap:SetSize(d, d)
		PlacePins(Minimap)
	end
	if not Minimap:IsShown() then Minimap:Show() end
end

-- Outdoors: the pins' host centred on you, on the tiles' canvas (so it moves
-- with them pixel for pixel), at the Minimap's view in map pixels: its
-- diameter in yards at this zoom, over a tile's yards.
local function PlaceHost(cam)
	FollowWindow()
	local canvas, x, y = cam.canvas, cam.playerCol * cam.zoom, -cam.playerRow * cam.zoom
	-- Anchored to the canvas, so it only moves when you do (or the zoom does);
	-- one cheap look each frame catches anything else moving it.
	local _, rel, _, px, py = pinHost:GetPoint(1)
	if canvas ~= placed.canvas or x ~= placed.x or y ~= placed.y or rel ~= canvas or px ~= x or py ~= y then
		placed.canvas, placed.x, placed.y = canvas, x, y
		pinHost:ClearAllPoints()
		pinHost:SetPoint("CENTER", canvas, "TOPLEFT", x, y)
	end
	local r = C_Minimap.GetViewRadius()
	if not r or issecretvalue(r) or r <= 0 then r = OUTDOOR_WIDEST / 2 end
	local d = math.floor(2 * r / TILE_YARDS * cam.zoom + 0.5)
	-- (HereBeDragons copies changing hosts is rare: a look twice a second.)
	local now, pinsOff = GetTime(), false
	if now >= pinsCheckAt then
		pinsCheckAt = now + 0.5
		pinsOff = PinsOff(pinHost)
	end
	if d ~= pinSize or pinsOff then
		pinSize = d
		pinHost:SetSize(d, d)
		PlacePins(pinHost)
	end
	if not pinHost:IsShown() then pinHost:Show() end
end

---------------------------------------------------------------------------
-- When it may join the map at all
---------------------------------------------------------------------------

-- nil if the Minimap can join the map right now, else why not.
local function Blocker()
	if not ns.frame:IsShown() then return "the map is closed" end
	if FarmHud and FarmHud.IsShown and FarmHud:IsShown() then return "FarmHud has the minimap" end
	-- (Not while you're off the map being shown, crossing to another
	-- continent or browsing one: our window sits on the Minimap's home spot,
	-- so letting it go there puts Blizzard's whole minimap over ours.)
	return nil
end

-- Whether the Minimap is drawing its indoor map. Its view radius tells: at
-- its zoom level the indoor view is nearer to it than the widest outdoor
-- one. Not IsIndoors(): that's whether you may mount, and Forever lets you
-- in Undercity, deep underground, where the floor plan is what you want.
local function MinimapIndoors()
	local r = C_Minimap.GetViewRadius()
	if not r or issecretvalue(r) or r <= 0 then return IsIndoors() and true or false end
	local z = Minimap:GetZoom()
	return math.abs(2 * r - (INDOOR[z] or INDOOR[0])) < math.abs(2 * r - (OUTDOOR[z] or OUTDOOR_WIDEST))
end

---------------------------------------------------------------------------
-- Each frame. After the map's own OnUpdate, so the view has already moved.
---------------------------------------------------------------------------

local function Update()
	local cam = ns.Camera()
	if Blocker() then
		Release()
		return
	end
	Engage()
	-- Where the Minimap draws its indoor map: the art of the map you're on
	-- (IndoorArt.lua) under our layers, the sensor running as outdoors; where
	-- there's none, Blizzard's floor plan. But in open-air cities it draws
	-- badly (OPEN_CITIES), our terrain.
	local best = C_Map.GetBestMapForUnit("player")
	local indoor = MinimapIndoors() and not OPEN_CITIES[best or 0]
	local art = indoor and cam.onMap and ns.IndoorArt.Usable(best) and best or nil
	ns.IndoorArt.Show(art)
	local whole = indoor and not art and not ns.IsMapExpanded()
	ns.IndoorArt.Note(best, indoor, art and "art" or whole and "floor plan" or "terrain")
	SetMode(whole and "whole" or "sensor")
	KeepTracking(not whole)
	if whole then
		ShowWhole()
	else
		if not Minimap:IsShown() then Minimap:Show() end
		if Minimap:GetZoom() ~= 0 then Minimap:SetZoom(0) end -- (HereBeDragons may zoom it through our host)
		-- Blizzard_HybridMinimap, where the client uses it, turns these back as it hides.
		if not C_Minimap.IsRotateMinimapIgnored() then C_Minimap.SetIgnoreRotateMinimap(true) end
		if C_Minimap.GetDrawGroundTextures() then C_Minimap.SetDrawGroundTextures(false) end
		PlaceSensor()
		if cam.onMap then
			PlaceHost(cam)
		elseif pinHost:IsShown() then
			pinHost:Hide() -- (its pins are around you, not on the map shown)
		end
	end
end

ns.frame:HookScript("OnUpdate", ns.Timed("minimap", Update))
ns.frame:HookScript("OnHide", Release)

---------------------------------------------------------------------------
-- The minimap's home corner (the cluster, and the stand-in holding what hung
-- off the Minimap), for growing the window and shrinking it back.
---------------------------------------------------------------------------

function T.HomeAlpha() return MinimapCluster:GetAlpha() end

function T.SetHomeAlpha(a)
	MinimapCluster:SetAlpha(a)
	standIn:SetAlpha(a)
end

function T.HomeStrata() return MinimapCluster:GetFrameStrata() end

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

T.Engage, T.Release = Engage, Release
function T.IsEngaged() return engaged end

-- Outdoors: the Minimap is our sensor this frame (Blips.lua reads it).
function T.Sensing() return engaged and mode == "sensor" and Minimap:IsShown() end

-- Indoors, Blizzard's minimap is on the map whole, its arrow standing in for ours.
function ns.MinimapShowsPlayer() return engaged and mode == "whole" end

---------------------------------------------------------------------------
-- Saved state
---------------------------------------------------------------------------

ns.On("Loaded", function(savedDB)
	db = savedDB
	-- Settings that are gone (2026-10-12): their saved values go too. Safe to drop this line after a few releases.
	db.terrainByAlpha, db.blipsPastEdge, db.hideDupes = nil, nil, nil
end)

-- Tracking we turned off comes back at logout, and after a /reload (its
-- state is known only once the client has sent it).
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "MINIMAP_UPDATE_TRACKING" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", ns.TimedEvents("takeover", function(_, event)
	if event == "PLAYER_LOGOUT" or not (engaged and mode == "sensor") then
		if db and db.trackingOff and next(db.trackingOff) then SyncTracking(false) end
	end
end))

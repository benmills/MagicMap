-- Minimap blips on the big map. Blizzard's Minimap moves into the MagicMap
-- window with its terrain faded out (Minimap:SetAlpha only fades terrain, as
-- FarmHud relies on). It sits centred on you, sized so its yards per pixel
-- match our zoom, so its live blips (tracked herbs and ore, party, quest
-- marks, your arrow) and addon pins (GatherMate, HandyNotes, Questie, via
-- HereBeDragons, which reads the Minimap's own size) land on our terrain,
-- while our terrain shows far more than the Minimap ever could.
--
-- The Minimap only knows what's within its view radius (about 233 yards
-- outdoors at its widest), so blips cover a circle around you; past a certain
-- zoom-out that circle is too small to read and the Minimap steps aside.
--
-- Ours first: whatever our layers draw (quests, flight points, party,
-- corpse...) sits above the Minimap and covers Blizzard's own marker for it,
-- and the tracking filters for those markers go off while it's here. The
-- Minimap is left for what no addon can read (tracked herbs and ore, NPCs).
--
-- The client doesn't clip the Minimap to the window (the window's
-- SetClipsChildren doesn't reach it), so its blips may only show inside the
-- window. Zoomed in closer than its closest level, or leaning off-centre in
-- path mode, its square is bigger than the room around you; then (/mm clip)
-- a mask texture whose opaque square fits that room confines its blips, as
-- the client hides blips where the mask is transparent. HereBeDragons' pins
-- move to an ordinary frame in its place, which the window does clip.
--
-- Everything else hanging off the Minimap (addon buttons, Blizzard's own
-- parts anchored to it) moves to a stand-in frame at the Minimap's usual
-- spot, and the whole minimap cluster (clock, calendar, tracking, the
-- stand-in with it) is hidden, so nothing is left floating around the hole.
-- All of it comes back when the map closes.
--
-- Indoors our terrain has nothing to show, so the window just wears the
-- Minimap itself: full terrain, centred, the wheel zooming it.
--
-- This runs while minimap mode (MinimapMode.lua) is on.

local ADDON, ns = ...
local TILE_YARDS = 1600 / 3
local MIN_DIAMETER = 28 -- px; any smaller and the blips just pile up on your arrow

-- Minimap:GetZoom() -> view diameter in yards, for choosing a zoom level (and
-- the radius on clients without C_Minimap.GetViewRadius).
local DIAMETER = {
	outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
	indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local state = ns.state
local db
local embedded = false
local saved -- the Minimap's own setup, restored on release
local moved = {}    -- child or region of the Minimap -> true, now on the stand-in
local anchored = {} -- other objects re-anchored from the Minimap to the stand-in
local ours = {}     -- our own children of the Minimap, which stay on it
local lastDiameter
local lastZoom
local STILL = 0.002 -- a zoom change per frame smaller than this (log scale) counts as settled
local SETTLE_FRAMES = 3 -- frames the Minimap stays hidden after a change of its zoom level
local settling = 0

local standIn = CreateFrame("Frame", "MagicMapMinimapStandIn", UIParent)
standIn:Hide()
ns.minimapStandIn = standIn

-- Indoors: a black backdrop over our map, under the Minimap, catching the
-- mouse (our map isn't there to drag) and wheeling the Minimap's zoom.
local skinned = false
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

-- Blizzard's big arrows toward your target sit on the Minimap's rim; ours
-- (Path.lua) point the way instead. The client won't swap their art, but it
-- lets the rim's icons be pushed outward, so they go far off screen.
-- Its quest, dig-site and bonus-objective rings (the patterned circle at the
-- Minimap's edge, where an area runs past it) mark a rim we don't show, so
-- they go too. (Retail's own UI keeps them at 0; classic-style UIs show them.)
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

-- Square in the window (the frame is square); Blizzard's round mask after.
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
-- (Retail-engine clients, Forever included, have only the first.)
local ROUND_MASK = GetFileIDFromPath and GetFileIDFromPath("Interface\\Masks\\CircleMaskScalable")
	and "Interface\\Masks\\CircleMaskScalable" or "Textures\\MinimapMask"

-- /mm clip: how the Minimap may be bigger than the room around you.
--   mask:   a mask whose opaque square fits that room confines its blips;
--   scroll: it's the scroll child of a ScrollFrame over the window, in case
--           that clips it where SetClipsChildren doesn't (an experiment);
--   off:    it only shows while its whole square fits (as before).
local CLIP_MODES = { mask = true, scroll = true, off = true }
local function ClipMode() return db and CLIP_MODES[db.minimapClip] and db.minimapClip or "mask" end

-- Textures/MinimapMask/Square<n>: 64x64, opaque in a centred n x n square
-- (tools/gen_minimap_masks.py). Loaded up front so a switch never waits on
-- a file; a client that can't find them (new files need a restart, not a
-- /reload) clips nothing, as before.
local MASK_PATH = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\MinimapMask\\Square"
local MASK_TEXELS, MASK_MIN = 64, 8
local MASK_MARGIN = 2 -- px kept clear inside the room's edge
local masksFound
do
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 8, -8) -- off screen
	holder:SetAlpha(0)
	for n = MASK_MIN, MASK_TEXELS - 2, 2 do
		local t = holder:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		local ok = t:SetTexture(MASK_PATH .. n)
		if n == MASK_MIN then masksFound = ok ~= false end
	end
end

-- The mask for a Minimap d px across in the room around you, and the side
-- (px) of the square its blips may show in; nil if none fits.
local function MaskFor(d, room, clip)
	if d <= room + 1 or clip == "scroll" then return SQUARE_MASK, math.min(d, room) end
	if clip ~= "mask" then return nil end
	-- Half a texel of slack each side: the mask's edge is filtered.
	local n = math.floor(((room - MASK_MARGIN) / d - 1 / MASK_TEXELS) * MASK_TEXELS / 2) * 2
	if n < MASK_MIN then return nil end
	n = math.min(n, MASK_TEXELS - 2)
	return MASK_PATH .. n, d * n / MASK_TEXELS
end

-- Scroll mode's ScrollFrame, over the window, under our overlay.
local scroller = CreateFrame("ScrollFrame", nil, ns.viewport)
scroller:SetAllPoints()
local scrollEmpty = CreateFrame("Frame", nil, scroller)
scrollEmpty:SetSize(1, 1)
scroller:SetScrollChild(scrollEmpty)
local scrolled = false -- the Minimap is its scroll child

-- HereBeDragons' pins, while clipping: a stand-in host the Minimap's size,
-- in its place, but an ordinary frame in the window, which clips it. It
-- answers what HereBeDragons asks the minimap (FarmHud does the same). Every
-- copy of HereBeDragons moves its pins here, Questie's renamed one too.
local pinHost = CreateFrame("Frame", "MagicMapMinimapPins", ns.viewport)
pinHost:Hide()
pinHost.GetZoom = function() return Minimap:GetZoom() end
pinHost.GetZoomLevels = function() return Minimap:GetZoomLevels() end
pinHost.SetZoom = function(_, z) Minimap:SetZoom(z) end -- (clients without C_Minimap.GetViewRadius)

-- Where the minimap pins of an addon whose world-map pins we already host
-- (AddonPins.lua) go: out of sight. They'd only repeat those, and drift, as
-- the library re-places them on its own schedule while our map moves.
local hiddenHost = CreateFrame("Frame", nil, ns.viewport)
hiddenHost:Hide()
hiddenHost:SetSize(1, 1)
hiddenHost.GetZoom, hiddenHost.GetZoomLevels, hiddenHost.SetZoom = pinHost.GetZoom, pinHost.GetZoomLevels, pinHost.SetZoom

local function GetCVarValue(name)
	if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
	return GetCVar and GetCVar(name)
end

-- Every copy of HereBeDragons-Pins (Questie bundles its own, renamed; see
-- AddonPins.lua). rescan: look for copies loaded since.
local NO_LIBS = {}
local function HBDPinsRaw(rescan)
	return ns.HBDPinLibs and ns.HBDPinLibs(rescan) or NO_LIBS
end

-- The copies drawing on the real Minimap or our host (not, say, FarmHud's).
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

local function Movable(obj)
	local t = obj:GetObjectType()
	return t ~= "Line" and t ~= "MaskTexture" and not IsPin(obj) and not ours[obj]
		and not (obj.IsProtected and obj:IsProtected())
end

local function MoveToStandIn(obj)
	if moved[obj] or not Movable(obj) then return end
	local layer, sublevel, strata, level
	if obj.GetDrawLayer then
		layer, sublevel = obj:GetDrawLayer()
	else
		strata, level = obj:GetFrameStrata(), obj:GetFrameLevel()
	end
	obj:SetParent(standIn)
	if layer then
		obj:SetDrawLayer(layer, sublevel)
	else
		obj:SetFrameStrata(strata)
		obj:SetFrameLevel(level)
	end
	Reanchor(obj, Minimap, standIn)
	moved[obj] = true
end

-- Blizzard's minimap parts that aren't its children but hang off it (borders,
-- the compass ring, zoom buttons), a few levels down from its parent.
local function ReanchorAround(frame, depth)
	for _, obj in ipairs({ frame:GetRegions() }) do
		if Reanchor(obj, Minimap, standIn) then anchored[obj] = true end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child ~= Minimap and child ~= standIn and not (child.IsProtected and child:IsProtected()) then
			if Reanchor(child, Minimap, standIn) then anchored[child] = true end
			if depth > 1 then ReanchorAround(child, depth - 1) end
		end
	end
end

-- Our host for HereBeDragons' pins while it clips (outdoors, /mm clip not
-- off); else the Minimap itself, as before.
local function PinHost()
	return (not skinned and ClipMode() ~= "off") and pinHost or Minimap
end

-- Have HereBeDragons (re-)place its pins on their host now: it only re-reads
-- the size once a second, and they must keep in step with the terrain.
local function HostFor(hbd, host)
	if host ~= Minimap and ns.HostsWorldPins and ns.HostsWorldPins(hbd) then return hiddenHost end
	return host
end

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

-- Hover reaches the Minimap only where its blips may show.
local lastInsets
local function SetHitInsets(l, r, t, b)
	local key = string.format("%d %d %d %d", l, r, t, b)
	if key == lastInsets then return end
	lastInsets = key
	Minimap:SetHitRectInsets(l, r, t, b)
end

local lastMask
local function SetMask(mask)
	if mask == lastMask then return end
	lastMask = mask
	Minimap:SetMaskTexture(mask)
end

---------------------------------------------------------------------------
-- Ours first: Blizzard's own markers for what our layers draw are tracking
-- filters (flight masters, quest objectives, points of interest). They go
-- off while the Minimap shows here and come back with it (and at logout).
-- MagicMapDB remembers which we turned off, so a /reload mid-way restores
-- them too. /mm dupes keeps Blizzard's.
---------------------------------------------------------------------------

local F = Enum and Enum.MinimapTrackingFilter or {}
local DUPLICATES = { [F.TaxiNode or 8] = "flight", [F.QuestPOIs or 65536] = "quests", [F.POI or 8192] = "areaPOIs" }

local function TrackingAPI()
	local C = C_Minimap
	return C and C.GetNumTrackingTypes and C.GetTrackingFilter and C.GetTrackingInfo and C.SetTracking and C
end

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
local function KeepTracking(on)
	local now = GetTime()
	if on == trackingOn and now - trackingAt < 2 then return end -- and again now and then: a layer toggled
	trackingOn, trackingAt = on, now
	SyncTracking(on)
end

local function Engage()
	if embedded then return end
	embedded = true
	HBDPinsRaw(true) -- any copy loaded since
	local w, h = Minimap:GetSize()
	saved = {
		parent = Minimap:GetParent(), points = {}, w = w, h = h,
		scale = Minimap:GetScale(), strata = Minimap:GetFrameStrata(), level = Minimap:GetFrameLevel(),
		zoom = Minimap:GetZoom(), alpha = Minimap:GetAlpha(),
		mouse = Minimap:IsMouseEnabled(), wheel = Minimap:IsMouseWheelEnabled(),
		shown = Minimap:IsShown(), cluster = MinimapCluster and MinimapCluster:IsShown(),
		clamped = Minimap:IsClampedToScreen(),
	}
	for i = 1, Minimap:GetNumPoints() do saved.points[i] = { Minimap:GetPoint(i) } end

	-- The stand-in takes the Minimap's place exactly (hidden: it only holds
	-- things, and anything anchored to it stays where it was).
	standIn:SetParent(saved.parent)
	standIn:SetScale(saved.scale)
	standIn:SetFrameStrata(saved.strata)
	standIn:SetFrameLevel(saved.level)
	standIn:ClearAllPoints()
	for _, p in ipairs(saved.points) do standIn:SetPoint(unpack(p)) end
	standIn:SetSize(w, h)
	for _, obj in ipairs({ Minimap:GetChildren() }) do MoveToStandIn(obj) end
	for _, obj in ipairs({ Minimap:GetRegions() }) do MoveToStandIn(obj) end
	local root = MinimapCluster or saved.parent
	if root then ReanchorAround(root, 3) end
	if saved.cluster then MinimapCluster:Hide() end

	-- Into the map: above our layers, below our pins (two levels above their
	-- layer) and overlay; mouse goes to the map.
	scrolled = ClipMode() == "scroll" and pcall(scroller.SetScrollChild, scroller, Minimap)
	if not scrolled then Minimap:SetParent(ns.viewport) end
	Minimap:SetScale(1)
	Minimap:SetFrameStrata(ns.frame:GetFrameStrata())
	Minimap:SetFrameLevel(ns.overlay:GetFrameLevel() - 1)
	scroller:SetFrameLevel(ns.overlay:GetFrameLevel() - 2)
	pinHost:SetFrameStrata(ns.frame:GetFrameStrata())
	pinHost:SetFrameLevel(ns.overlay:GetFrameLevel() - 1)
	-- The pins that stayed must still clear our terrain and layers.
	for _, pin in ipairs({ Minimap:GetChildren() }) do
		if pin:GetFrameLevel() <= Minimap:GetFrameLevel() then pin:SetFrameLevel(Minimap:GetFrameLevel() + 1) end
	end
	-- Hover still reaches the Minimap (the game's own blip tooltips); clicks
	-- and the wheel go through to the map, for dragging and zooming.
	if Minimap.SetMouseClickEnabled and Minimap.SetMouseMotionEnabled then
		Minimap:EnableMouse(true)
		Minimap:SetMouseClickEnabled(false)
		Minimap:SetMouseMotionEnabled(true)
	else
		Minimap:EnableMouse(false)
	end
	Minimap:EnableMouseWheel(false)
	Minimap:SetAlpha(0)
	-- Never pushed back on screen: that would slide its blips off ours.
	Minimap:SetClampedToScreen(false)
	lastMask, lastInsets = nil, nil
	SetMask(SQUARE_MASK)
	ClearRim(true)
	Minimap:Hide() -- until Update finds it a settled spot
	lastDiameter = nil
end

-- Indoors (on) or out: the Minimap shown whole over a backdrop, or faded to
-- just its blips under our marker.
local function SetSkin(on)
	if on == skinned then return end
	skinned = on
	indoorBg:SetFrameLevel(ns.overlay:GetFrameLevel() + 1)
	indoorBg:SetShown(on)
	Minimap:SetFrameLevel(ns.overlay:GetFrameLevel() + (on and 2 or -1))
	Minimap:SetAlpha(on and 1 or 0)
	ClearRim(not on) -- indoors it's Blizzard's minimap, rim and all
	if on then
		SetMask(SQUARE_MASK)
		SetHitInsets(0, 0, 0, 0)
		pinHost:Hide()
	end
	lastDiameter = nil
end

local function Release()
	if not embedded then return end
	embedded = false
	SetSkin(false)
	ClearRim(false)
	state.minimapShown = false
	pinHost:Hide()
	trackingOn = nil
	SyncTracking(false)

	if scrolled then
		scroller:SetScrollChild(scrollEmpty)
		scrolled = false
	end
	Minimap:SetParent(saved.parent)
	Minimap:ClearAllPoints()
	for _, p in ipairs(saved.points) do Minimap:SetPoint(unpack(p)) end
	Minimap:SetSize(saved.w, saved.h)
	Minimap:SetScale(saved.scale)
	Minimap:SetFrameStrata(saved.strata)
	Minimap:SetFrameLevel(saved.level)
	Minimap:EnableMouse(saved.mouse)
	Minimap:EnableMouseWheel(saved.wheel)
	Minimap:SetHitRectInsets(0, 0, 0, 0)
	Minimap:SetAlpha(saved.alpha)
	Minimap:SetZoom(saved.zoom)
	Minimap:SetShown(saved.shown)
	Minimap:SetClampedToScreen(saved.clamped)
	Minimap:SetMaskTexture(ROUND_MASK)
	lastMask, lastInsets = nil, nil

	for obj in pairs(moved) do
		local layer, sublevel, strata, level
		if obj.GetDrawLayer then
			layer, sublevel = obj:GetDrawLayer()
		else
			strata, level = obj:GetFrameStrata(), obj:GetFrameLevel()
		end
		obj:SetParent(Minimap)
		if layer then
			obj:SetDrawLayer(layer, sublevel)
		else
			obj:SetFrameStrata(strata)
			obj:SetFrameLevel(level)
		end
		Reanchor(obj, standIn, Minimap)
		moved[obj] = nil
	end
	for obj in pairs(anchored) do
		Reanchor(obj, standIn, Minimap)
		anchored[obj] = nil
	end
	if saved.cluster then MinimapCluster:Show() end
	for _, hbd in ipairs(HBDPins()) do
		if hbd.SetMinimapObject then hbd:SetMinimapObject(Minimap) end -- re-place pins at the normal size
	end
end

-- nil if the Minimap can join the map right now, else why not.
local function Blocker()
	if not (ns.IsMinimapMode and ns.IsMinimapMode()) then return "off" end
	if not ns.frame:IsShown() then return "the map is closed" end
	if FarmHud and FarmHud.IsShown and FarmHud:IsShown() then return "FarmHud has the minimap" end
	if GetCVarValue("rotateMinimap") == "1" then return "Rotate Minimap is on" end
	if not state.playerCol or state.playerMap ~= state.map then return "you're not on the map being shown" end
	return nil
end

local function ViewRadius(kind)
	if C_Minimap and C_Minimap.GetViewRadius then
		local r = C_Minimap.GetViewRadius()
		if r and r > 0 then return r end
	end
	return (DIAMETER[kind][Minimap:GetZoom()] or DIAMETER[kind][0]) / 2
end

-- The Minimap's zoom level for the room around you: unclipped, the widest
-- whose square fits it; clipped, the closest that still covers it (its
-- widest when even that fits).
local function PickLevel(kind, zoom, room, clipped)
	local px = zoom / TILE_YARDS
	if clipped then
		for z = 5, 0, -1 do
			if DIAMETER[kind][z] * px >= room then return z end
		end
		return 0
	end
	for z = 0, 5 do
		if DIAMETER[kind][z] * px <= room then return z end
	end
end

-- /mm sync: show the Minimap's own terrain at half strength over ours, inside
-- an outline of where we put it, so any drift between its blips and our map
-- shows as doubled terrain. Its terrain is masked like its blips, so with
-- clipping on it also shows the square they're confined to.
local syncCheck
local syncOutline = CreateFrame("Frame", nil, Minimap)
syncOutline:SetAllPoints()
syncOutline:Hide()
ours[syncOutline] = true
for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
	local t = syncOutline:CreateTexture(nil, "OVERLAY")
	t:SetColorTexture(1, 0.2, 0.8, 0.9) -- where we put the Minimap: its terrain should fill this exactly
	t:SetPoint(e[1])
	t:SetPoint(e[2])
	if e[3] then t:SetWidth(1) else t:SetHeight(1) end
end
-- /mm sync full: Blizzard's terrain at full strength, for comparing the two.
ns.slash.sync = function(arg)
	syncCheck = not syncCheck and { alpha = arg == "full" and 1 or 0.5 } or nil
	if not syncCheck then syncOutline:Hide() end
	ns.Print(not syncCheck and "sync: off"
		or syncCheck.alpha == 1 and "sync: Blizzard's terrain in place of ours where its blips show. /mm sync again to stop"
		or "sync: Blizzard's terrain at 50% over ours; zoom and pan, watch for doubling. /mm sync again to stop")
end

local function Hidden()
	if Minimap:IsShown() then Minimap:Hide() end
	pinHost:Hide()
	state.minimapShown = false
end

local function Update(elapsed)
	if Blocker() then
		Release()
		return
	end
	Engage()
	-- The window's strata changes (minimap mode, expanding): the Minimap goes with it.
	if Minimap:GetFrameStrata() ~= ns.frame:GetFrameStrata() then
		Minimap:SetFrameStrata(ns.frame:GetFrameStrata())
		Minimap:SetFrameLevel(ns.overlay:GetFrameLevel() + (skinned and 2 or -1))
		pinHost:SetFrameStrata(ns.frame:GetFrameStrata())
		pinHost:SetFrameLevel(ns.overlay:GetFrameLevel() - 1)
	end
	local expanded = ns.IsMapExpanded and ns.IsMapExpanded()
	SetSkin(IsIndoors and IsIndoors() and not expanded or false)
	KeepTracking(not skinned) -- indoors our pins are under the backdrop: Blizzard's stay
	if skinned then
		local w, h = ns.viewport:GetSize()
		local d = math.floor(math.min(w, h) + 0.5)
		Minimap:ClearAllPoints()
		Minimap:SetPoint("CENTER", ns.viewport)
		if d ~= lastDiameter then
			lastDiameter = d
			Minimap:SetSize(d, d)
			PlacePins(Minimap)
		end
		if not Minimap:IsShown() then Minimap:Show() end
		state.minimapShown = true
		return
	end

	-- Outdoors the Minimap only shows where it can't go wrong: the map settled
	-- (not mid-zoom), its blips confined to the room around you in the window
	-- (its square fits, or a mask or the scroll frame clips it), and a couple
	-- of frames after any change of its zoom level (the client takes a moment
	-- to apply one).
	local zoom = state.zoom
	local still = not ns.IsAnimating() and lastZoom and math.abs(math.log(zoom / lastZoom)) < STILL
	lastZoom = zoom
	local kind = (IsIndoors and IsIndoors()) and "indoor" or "outdoor"
	local w, h = ns.viewport:GetSize()
	local x, y = ns.TileToScreen(state.playerCol, state.playerRow)
	local room = 2 * math.min(x, w - x, y, h - y) -- the biggest square around you in the window
	local clip = ClipMode()
	if clip == "mask" and not masksFound then clip = "off" end
	if clip == "scroll" and not scrolled then clip = "off" end
	local level = PickLevel(kind, zoom, room, clip ~= "off")
	if level and still and Minimap:GetZoom() ~= level then
		Minimap:SetZoom(level)
		settling = SETTLE_FRAMES
	end
	settling = math.max(0, settling - 1)
	local d = 2 * ViewRadius(kind) / TILE_YARDS * zoom
	local mask, side = MaskFor(d, room, clip)
	if expanded or not (level and still) or settling > 0 or d < MIN_DIAMETER or not mask then
		Hidden()
		return
	end

	-- Pinned to the tiles' own canvas, so it moves with them pixel for pixel.
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", ns.tileCanvas, "TOPLEFT", state.playerCol * zoom, -state.playerRow * zoom)
	SetMask(mask)
	local inset = (d - side) / 2
	SetHitInsets(math.max(inset, d / 2 - x), math.max(inset, d / 2 - (w - x)), math.max(inset, d / 2 - y), math.max(inset, d / 2 - (h - y)))
	local host = PinHost()
	if host == pinHost then
		pinHost:ClearAllPoints()
		pinHost:SetPoint("CENTER", ns.tileCanvas, "TOPLEFT", state.playerCol * zoom, -state.playerRow * zoom)
	end
	d = math.floor(d + 0.5)
	if d ~= lastDiameter or PinsOff(host) then
		lastDiameter = d
		Minimap:SetSize(d, d)
		pinHost:SetSize(d, d)
		PlacePins(host)
	end
	local alpha = syncCheck and syncCheck.alpha or 0
	if Minimap:GetAlpha() ~= alpha then Minimap:SetAlpha(alpha) end
	syncOutline:SetShown(syncCheck ~= nil)
	if syncCheck and (level ~= syncCheck.level or mask ~= syncCheck.mask) then
		syncCheck.level, syncCheck.mask = level, mask
		ns.Print(string.format("sync: Minimap zoom %d, radius %.1f yd (%s), %d px across at map zoom %.0f; blips in %d px (%s)",
			level, ViewRadius(kind), (C_Minimap and C_Minimap.GetViewRadius) and "client" or "table", d, zoom,
			side, mask == SQUARE_MASK and "whole square" or mask:match("Square%d+$")))
	end
	if not Minimap:IsShown() then Minimap:Show() end
	pinHost:SetShown(host == pinHost)
	state.minimapShown = true -- its arrow (the same art as ours) stands in for ours
end

---------------------------------------------------------------------------
-- Tooltips. While the Minimap has the mouse, Blizzard's hover handler
-- (Minimap_OnUpdate, every frame) takes GameTooltip for the blips under the
-- cursor. Right after it, if it found none, the quest area there gets it;
-- our pins sit above the Minimap and take the mouse before either. Layers'
-- own hover (OnMapHover) stands aside meanwhile, so nothing flickers.
---------------------------------------------------------------------------

local function CursorTile()
	local v = ns.viewport
	local left, top = v:GetLeft(), v:GetTop()
	if not left then return nil end
	local s = v:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local w, h = v:GetSize()
	return state.cx + (cx / s - left - w / 2) / state.zoom, state.cy + (top - cy / s - h / 2) / state.zoom
end

local function AfterMinimapHover()
	if not embedded or skinned or not ns.ShowQuestAreaTooltip then return end
	if GameTooltip:IsShown() and GameTooltip:NumLines() > 0 and GameTooltip:IsOwned(UIParent) then return end -- a blip
	ns.ShowQuestAreaTooltip(CursorTile())
end
if Minimap_OnUpdate then hooksecurefunc("Minimap_OnUpdate", AfterMinimapHover) end
Minimap:HookScript("OnEnter", function() state.minimapHover = true end)
Minimap:HookScript("OnLeave", function() state.minimapHover = false end)

---------------------------------------------------------------------------
-- Debug toggles
---------------------------------------------------------------------------

local CLIP_HELP = {
	mask = "masks confine its blips to the room around you in the window",
	scroll = "it's clipped by a ScrollFrame over the window (experiment)",
	off = "it only shows while its whole square fits the window (as before)",
}

-- /mm clip [mask|scroll|off]: how the Minimap may be bigger than the window.
ns.slash.clip = function(arg)
	if not db then return end
	local mode = CLIP_MODES[arg or ""] and arg or (ClipMode() == "off" and "mask" or "off")
	db.minimapClip = mode
	Release() -- back next frame, in the new mode
	local note = ""
	if mode == "mask" and not masksFound then note = " |cffff6060(mask files not found: restart the game client; clipping off meanwhile)|r" end
	ns.Print("clip: " .. mode .. ": " .. CLIP_HELP[mode] .. note .. ". /mm clip [mask|scroll|off]")
end

-- /mm dupes: Blizzard's own markers for what our layers draw, back on (or off again).
ns.slash.dupes = function()
	if not db then return end
	db.hideDupes = db.hideDupes == false
	trackingOn = nil
	if embedded and not skinned then KeepTracking(true) end
	local off = {}
	for id in pairs(db.trackingOff or {}) do off[#off + 1] = DUPLICATES[id] or tostring(id) end
	ns.Print(db.hideDupes and ("dupes: Blizzard's markers for what we draw are off while the minimap is in the map"
		.. (#off > 0 and (" (" .. table.concat(off, ", ") .. ")") or (TrackingAPI() and "" or " (this client can't)")))
		or "dupes: Blizzard's markers stay on alongside ours")
end

-- The minimap's rect in UIParent coordinates (the stand-in's while the
-- Minimap is in the window).
function ns.MinimapRect()
	local src = embedded and standIn or Minimap
	local left, top, w, h = src:GetLeft(), src:GetTop(), src:GetSize()
	if not (left and top) then return nil end
	local s = src:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return left * s, top * s, w * s, h * s
end


ns.ReleaseMinimap = Release
ns.MinimapBlocker = Blocker

-- After the map's own OnUpdate, so the view has already moved this frame.
ns.frame:HookScript("OnUpdate", function(_, elapsed) Update(elapsed) end)
ns.frame:HookScript("OnHide", Release)

ns.On("Loaded", function(savedDB)
	db = savedDB
	if not CLIP_MODES[db.minimapClip] then db.minimapClip = "mask" end
	if db.hideDupes == nil then db.hideDupes = true end
end)

-- Tracking we turned off comes back at logout, and after a /reload (its
-- state is known only once the client has sent it).
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "MINIMAP_UPDATE_TRACKING" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGOUT" or not (embedded and not skinned) then
		if db and db.trackingOff and next(db.trackingOff) then SyncTracking(false) end
	end
end)

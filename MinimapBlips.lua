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
local embedded = false
local saved -- the Minimap's own setup, restored on release
local moved = {}    -- child or region of the Minimap -> true, now on the stand-in
local anchored = {} -- other objects re-anchored from the Minimap to the stand-in
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
local function PushRimArrowsAway(on)
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

local function GetCVarValue(name)
	if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
	return GetCVar and GetCVar(name)
end

local function HBDPinsRaw()
	return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

-- HereBeDragons, when it's drawing on the real Minimap (not, say, FarmHud's).
local function HBDPins()
	local hbd = HBDPinsRaw()
	return hbd and hbd.Minimap == Minimap and hbd or nil
end

-- Pins are positioned on the Minimap by their addons; they travel with it.
local function IsPin(obj)
	local hbd = HBDPinsRaw()
	if hbd and hbd.minimapPins and hbd.minimapPins[obj] then return true end
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
	return t ~= "Line" and t ~= "MaskTexture" and not IsPin(obj)
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

local function Engage()
	if embedded then return end
	embedded = true
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

	-- Into the map: above our pins, below our overlay; mouse goes to the map.
	Minimap:SetParent(ns.viewport)
	Minimap:SetScale(1)
	Minimap:SetFrameStrata(ns.frame:GetFrameStrata())
	Minimap:SetFrameLevel(ns.overlay:GetFrameLevel() - 1)
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
	Minimap:SetMaskTexture(SQUARE_MASK)
	PushRimArrowsAway(true)
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
	PushRimArrowsAway(not on) -- indoors it's Blizzard's minimap, arrows and all
	lastDiameter = nil
end

local function Release()
	if not embedded then return end
	embedded = false
	SetSkin(false)
	PushRimArrowsAway(false)
	state.minimapShown = false
	ns.SetMinimapCircle(nil)

	Minimap:SetParent(saved.parent)
	Minimap:ClearAllPoints()
	for _, p in ipairs(saved.points) do Minimap:SetPoint(unpack(p)) end
	Minimap:SetSize(saved.w, saved.h)
	Minimap:SetScale(saved.scale)
	Minimap:SetFrameStrata(saved.strata)
	Minimap:SetFrameLevel(saved.level)
	Minimap:EnableMouse(saved.mouse)
	Minimap:EnableMouseWheel(saved.wheel)
	Minimap:SetAlpha(saved.alpha)
	Minimap:SetZoom(saved.zoom)
	Minimap:SetShown(saved.shown)
	Minimap:SetClampedToScreen(saved.clamped)
	Minimap:SetMaskTexture(ROUND_MASK)

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
	local hbd = HBDPins()
	if hbd and hbd.SetMinimapObject then hbd:SetMinimapObject(Minimap) end -- re-place pins at the normal size
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

-- /mm sync: show the Minimap's own terrain at half strength over ours, inside
-- an outline of where we put it, so any drift between its blips and our map
-- shows as doubled terrain.
local syncCheck
local syncOutline = CreateFrame("Frame", nil, Minimap)
syncOutline:SetAllPoints()
syncOutline:Hide()
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
	end
	local expanded = ns.IsMapExpanded and ns.IsMapExpanded()
	SetSkin(IsIndoors and IsIndoors() and not expanded or false)
	if skinned then
		ns.SetMinimapCircle(nil)
		local w, h = ns.viewport:GetSize()
		local d = math.floor(math.min(w, h) + 0.5)
		Minimap:ClearAllPoints()
		Minimap:SetPoint("CENTER", ns.viewport)
		if d ~= lastDiameter then
			lastDiameter = d
			Minimap:SetSize(d, d)
			local hbd = HBDPins()
			if hbd and hbd.SetMinimapObject then hbd:SetMinimapObject(Minimap) end
		end
		if not Minimap:IsShown() then Minimap:Show() end
		state.minimapShown = true
		return
	end

	-- Outdoors the Minimap only shows where it can't go wrong: the map settled
	-- (not mid-zoom), its square wholly inside the window around you (the
	-- client doesn't clip it to the window), and a couple of frames after any
	-- change of its zoom level (the client takes a moment to apply one).
	local zoom = state.zoom
	local still = not ns.IsZooming() and lastZoom and math.abs(math.log(zoom / lastZoom)) < STILL
	lastZoom = zoom
	local kind = (IsIndoors and IsIndoors()) and "indoor" or "outdoor"
	local w, h = ns.viewport:GetSize()
	local x, y = ns.TileToScreen(state.playerCol, state.playerRow)
	local room = 2 * math.min(x, w - x, y, h - y) -- the biggest square around you in the window
	local level -- the widest zoom level whose square fits that room
	for z = 0, 5 do
		if DIAMETER[kind][z] / TILE_YARDS * zoom <= room then
			level = z
			break
		end
	end
	if level and still and Minimap:GetZoom() ~= level then
		Minimap:SetZoom(level)
		settling = SETTLE_FRAMES
	end
	settling = math.max(0, settling - 1)
	local d = 2 * ViewRadius(kind) / TILE_YARDS * zoom
	if expanded or not (level and still) or settling > 0 or d < MIN_DIAMETER or d > room + 1 then
		if Minimap:IsShown() then Minimap:Hide() end
		state.minimapShown = false
		ns.SetMinimapCircle(nil)
		return
	end

	-- Pinned to the tiles' own canvas, so it moves with them pixel for pixel.
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", ns.tileCanvas, "TOPLEFT", state.playerCol * zoom, -state.playerRow * zoom)
	d = math.floor(d + 0.5)
	if d ~= lastDiameter then
		lastDiameter = d
		Minimap:SetSize(d, d)
		-- HereBeDragons only re-reads the size once a second; have it re-place
		-- its pins now, in step with the terrain.
		local hbd = HBDPins()
		if hbd and hbd.SetMinimapObject then hbd:SetMinimapObject(Minimap) end
	end
	local alpha = syncCheck and syncCheck.alpha or 0
	if Minimap:GetAlpha() ~= alpha then Minimap:SetAlpha(alpha) end
	syncOutline:SetShown(syncCheck ~= nil)
	if syncCheck and level ~= syncCheck.level then
		syncCheck.level = level
		ns.Print(string.format("sync: Minimap zoom %d, radius %.1f yd (%s), %d px across at map zoom %.0f",
			level, ViewRadius(kind), (C_Minimap and C_Minimap.GetViewRadius) and "client" or "table", d, zoom))
	end
	if not Minimap:IsShown() then Minimap:Show() end
	state.minimapShown = true -- its arrow (the same art as ours) stands in for ours
	ns.SetMinimapCircle(state.playerCol, state.playerRow, ViewRadius(kind) / TILE_YARDS)
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


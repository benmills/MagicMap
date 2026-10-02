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
-- spot, so it stays put. All of it goes back when the map closes.
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

local standIn = CreateFrame("Frame", "MagicMapMinimapStandIn", UIParent)
standIn:Hide()
ns.minimapStandIn = standIn

-- Blizzard's minimap dressing that would only frame an empty hole: the zone
-- text (ours floats above the map) and the round border.
local DRESSING = { "MinimapZoneTextButton", "MinimapBorderTop", "MinimapBorder", "MinimapCompassTexture", "MinimapNorthTag" }
local hiddenDressing = {}

local function HideDressing()
	local list = {}
	for _, name in ipairs(DRESSING) do list[#list + 1] = _G[name] end
	if MinimapCluster then
		list[#list + 1] = MinimapCluster.ZoneTextButton
		list[#list + 1] = MinimapCluster.BorderTop
	end
	for _, obj in ipairs(list) do
		if obj.IsShown and obj:IsShown() then
			obj:Hide()
			hiddenDressing[obj] = true
		end
	end
end

local function ShowDressing()
	for obj in pairs(hiddenDressing) do obj:Show() end
	wipe(hiddenDressing)
end

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
		shown = Minimap:IsShown(),
	}
	for i = 1, Minimap:GetNumPoints() do saved.points[i] = { Minimap:GetPoint(i) } end

	-- The stand-in takes the Minimap's place exactly.
	standIn:SetParent(saved.parent)
	standIn:SetScale(saved.scale)
	standIn:SetFrameStrata(saved.strata)
	standIn:SetFrameLevel(saved.level)
	standIn:ClearAllPoints()
	for _, p in ipairs(saved.points) do standIn:SetPoint(unpack(p)) end
	standIn:SetSize(w, h)
	standIn:Show()
	for _, obj in ipairs({ Minimap:GetChildren() }) do MoveToStandIn(obj) end
	for _, obj in ipairs({ Minimap:GetRegions() }) do MoveToStandIn(obj) end
	local root = MinimapCluster or saved.parent
	if root then ReanchorAround(root, 3) end
	HideDressing()

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
	lastDiameter = nil
end

local function Release()
	if not embedded then return end
	embedded = false
	state.hideMarker = false

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
	ShowDressing()
	standIn:Hide()
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

local function Update(elapsed)
	if Blocker() then
		Release()
		return
	end
	Engage()

	-- The widest Minimap zoom whose circle still fits the window, judged at the
	-- zoom the camera is headed for so it doesn't switch part-way through.
	local goal = ns.GoalZoom()
	local kind = (IsIndoors and IsIndoors()) and "indoor" or "outdoor"
	local w, h = ns.viewport:GetSize()
	local fit = math.max(w, h)
	local level = 5
	for z = 0, 5 do
		if DIAMETER[kind][z] / TILE_YARDS * goal <= fit then
			level = z
			break
		end
	end
	if Minimap:GetZoom() ~= level then Minimap:SetZoom(level) end

	local d = 2 * ViewRadius(kind) / TILE_YARDS * state.zoom
	-- Expanded into the world-map view, the minimap stays out of sight entirely
	-- (still held here, so it doesn't reappear in its corner either).
	if d < MIN_DIAMETER or (ns.IsMapExpanded and ns.IsMapExpanded()) then
		Minimap:Hide()
		state.hideMarker = false
		return
	end
	if not Minimap:IsShown() then Minimap:Show() end
	state.hideMarker = true -- Blizzard's arrow is ours now
	local x, y = ns.TileToScreen(state.playerCol, state.playerRow)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", ns.viewport, "TOPLEFT", x, -y)

	d = math.floor(d + 0.5)
	if d ~= lastDiameter then
		lastDiameter = d
		Minimap:SetSize(d, d)
		-- HereBeDragons only re-reads the size once a second; have it re-place
		-- its pins now, in step with the terrain.
		local hbd = HBDPins()
		if hbd and hbd.SetMinimapObject then hbd:SetMinimapObject(Minimap) end
	end
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

-- The minimap's view radius in yards at its own (not our) zoom.
function ns.MinimapViewRadius()
	local kind = (IsIndoors and IsIndoors()) and "indoor" or "outdoor"
	if embedded then return (DIAMETER[kind][saved.zoom] or DIAMETER[kind][0]) / 2 end
	return ViewRadius(kind)
end

ns.ReleaseMinimap = Release
ns.MinimapBlocker = Blocker

-- After the map's own OnUpdate, so the view has already moved this frame.
ns.frame:HookScript("OnUpdate", function(_, elapsed) Update(elapsed) end)
ns.frame:HookScript("OnHide", Release)


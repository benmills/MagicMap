-- The Minimap takeover (the spike's MinimapTakeover.lua), in the apply phase (Game.Apply),
-- from View (types/view.lua):
--   View.minimap "ours" and the window shown (nothing blocking): Blizzard's
--     Minimap becomes an unseen sensor, SENSOR_PX square, centred under the
--     window's view (kept on the screen: off it the client stops updating its
--     blips), just beneath the window's strata, at its widest zoom, north up, no
--     ground, no mouse (each put right every apply: other client code turns them
--     back). What hung on it waits on a stand-in at its home spot; the cluster hides.
--     HereBeDragons' minimap pins go to hosts of Game's (game/AddonPins.lua): on the unseen
--     sensor they'd still take the mouse, over our map. View.renderer "blizzard": the Minimap
--     whole in the window instead, no sensor (game/Renderer.lua's Game.Whole), and back.
--   otherwise (or a View Game can't use: SAFE, game/Apply.lua): released, every change undone.
-- Every change Engage makes is paired with its undo on a list; Release runs it
-- backwards, so what comes back is exactly what was taken. But the cluster: its Show and
-- Hide are refused in combat (it's protected: spike-bugs K2), so each apply puts it right
-- once they aren't, hidden while engaged and as it was otherwise; meanwhile, engaged, it's
-- faded (Game.minimap.fade: game/Home.lua; alpha isn't refused).
-- Game.minimap tells the sensor (game/Blips.lua) where things stand: engaged,
-- sensor (the blips layer is on, not whole), still (the last Apply didn't move it, and its zoom has
-- applied), whole (the Minimap whole in the window: game/Renderer.lua).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local SENSOR_PX = 300   -- its side in screen units (a blip's square is ~16 of them)
local MARGIN = 2        -- screen units it keeps inside the screen's edge
local ICONS = 0.05      -- its own icons' scale: out of sight (alpha alone doesn't hide them)
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

local m = { engaged = false, sensor = false, still = false, fade = false, whole = false } -- blocker: why it isn't taken
Game.minimap = m
local undo, placed = {}, nil
local clusterShown -- the cluster's own shown state, from an engage until it's back

local standIn = CreateFrame("Frame", "MagicMapMinimapStandIn", UIParent)
standIn:Hide()

local function OnRelease(fn) undo[#undo + 1] = fn end

-- A pin travels with the Minimap: a copy's that stayed there, or GatherMate's (MinimapTakeover.lua:124-129).
local function IsPin(obj)
	for _, copy in ipairs(Game.PinLibs()) do
		if copy.lib.minimapPins[obj] then return true end
	end
	return obj:GetDebugName():find("GatherMatePin", 1, true) ~= nil
end

-- Swap anchors relative to `from` for the same anchors relative to `to` (true if any).
local function Reanchor(obj, from, to)
	local points = {}
	for i = 1, obj:GetNumPoints() do
		local p, rel, rp, x, y = obj:GetPoint(i)
		if rel == from then points[#points + 1] = { p, rp, x, y } end
	end
	for _, p in ipairs(points) do obj:SetPoint(p[1], to, p[2], p[3], p[4]) end
	return #points > 0
end

-- A new parent, keeping the draw layer (regions) or strata and level (frames: the client
-- re-bases them on the new parent) (MinimapTakeover.lua:181-195).
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

local function Move(obj, from, to)
	local t = obj:GetObjectType()
	if t == "Line" or t == "MaskTexture" or (obj.IsProtected and obj:IsProtected()) or IsPin(obj) then return end
	Reparent(obj, to)
	Reanchor(obj, from, to)
	OnRelease(function()
		Reparent(obj, from)
		Reanchor(obj, to, from)
	end)
end

-- Blizzard's parts that hang off the Minimap without being its children (borders, the zone
-- text, its buttons), a few levels down from the cluster: onto the stand-in (MinimapTakeover.lua:215-229).
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

-- The cluster hidden while engaged, else as it was; its state forgotten once it's back.
local function Cluster()
	local c = MinimapCluster
	if m.engaged and clusterShown == nil then clusterShown = c:IsShown() end
	if clusterShown == nil then return end
	local want = not m.engaged and clusterShown
	if c:IsShown() ~= want and not InCombatLockdown() then c:SetShown(want) end
	m.fade = m.engaged and c:IsShown()
	if not m.engaged and c:IsShown() == clusterShown then clusterShown = nil end
end

-- The sensor's own settings (MinimapTakeover.lua:434-443): unseen, its icons out of sight, no mouse;
-- Hold and Place see to the rest. Placed afresh.
local function Sensor()
	local mm = Minimap
	mm:SetAlpha(0)
	mm:SetIconScale(ICONS)
	mm:EnableMouse(false)
	mm:EnableMouseWheel(false)
	C_Minimap.SetDrawGroundTextures(false)
	placed = nil
end

local function Engage()
	m.engaged = true
	Game.PinLibs(true) -- any copy loaded since (its pins travel with the Minimap: IsPin)
	-- Undone last: the pins back on the Minimap once it's back at its own size (MinimapTakeover.lua:338-344).
	OnRelease(Game.MinimapPinsHome)
	local mm = Minimap
	local parent, w, h = mm:GetParent(), mm:GetSize()
	local points = {}
	for i = 1, mm:GetNumPoints() do points[i] = { mm:GetPoint(i) } end
	local scale, strata, level, zoom, alpha = mm:GetScale(), mm:GetFrameStrata(), mm:GetFrameLevel(), mm:GetZoom(), mm:GetAlpha()
	local ground, unrotated = C_Minimap.GetDrawGroundTextures(), C_Minimap.IsRotateMinimapIgnored()
	local mouse, wheel, shown = mm:IsMouseEnabled(), mm:IsMouseWheelEnabled(), mm:IsShown()
	-- The stand-in takes the Minimap's place exactly (hidden: it only holds things).
	standIn:SetParent(parent)
	standIn:SetScale(scale)
	standIn:SetFrameStrata(strata)
	standIn:SetFrameLevel(level)
	standIn:ClearAllPoints()
	for _, p in ipairs(points) do standIn:SetPoint(unpack(p)) end
	standIn:SetSize(w, h)
	for _, obj in ipairs({ mm:GetChildren() }) do Move(obj, mm, standIn) end
	for _, obj in ipairs({ mm:GetRegions() }) do Move(obj, mm, standIn) end
	ReanchorAround(MinimapCluster, 3)
	-- Undone first: the Minimap back in its place before what hung on it comes back to it
	-- (a parent moved re-bases what it holds).
	OnRelease(function()
		mm:SetParent(parent)
		mm:ClearAllPoints()
		for _, p in ipairs(points) do mm:SetPoint(unpack(p)) end
		mm:SetSize(w, h)
		mm:SetScale(scale)
		mm:SetFrameStrata(strata)
		mm:SetFrameLevel(level)
		mm:EnableMouse(mouse)
		mm:EnableMouseWheel(wheel)
		mm:SetAlpha(alpha)
		mm:SetIconScale(1) -- (the client's own; it can't be read back)
		C_Minimap.SetDrawGroundTextures(ground)
		C_Minimap.SetIgnoreRotateMinimap(unrotated)
		mm:SetZoom(zoom)
		mm:SetShown(shown)
	end)
	mm:SetParent(UIParent)
	mm:SetScale(1)
	Sensor()
	C_Minimap.SetIgnoreRotateMinimap(true)
	mm:Show()
	Runtime.Trace("minimap", "engaged")
end

local function Release()
	if not m.engaged then return end
	if m.whole then Game.Whole(nil) end
	m.engaged, m.sensor, m.still, placed = false, false, false, nil
	local failure
	for i = #undo, 1, -1 do -- every step runs; the first failure is raised after
		local ok, err = pcall(undo[i])
		if not ok and not failure then failure = err end
		undo[i] = nil
	end
	Cluster()
	Runtime.Trace("minimap", "released")
	if failure then error(failure, 0) end
end

-- Just beneath (strata, level).
local function Beneath(strata, level)
	if level > 0 then return strata, level - 1 end
	for i = 2, #STRATA do
		if STRATA[i] == strata then return STRATA[i - 1], 100 end
	end
	return strata, 0
end

-- What other client code turns back (HybridMinimap turns its ground and rotation on as it
-- hides: spike-bugs G3), or anyone zooms, hides or shows it, put right every apply. True if it held.
local function Hold(mm)
	local held = mm:IsShown() and mm:GetZoom() == 0 and C_Minimap.IsRotateMinimapIgnored()
	if not mm:IsShown() then mm:Show() end
	if mm:GetAlpha() ~= 0 then mm:SetAlpha(0) end
	if mm:GetZoom() ~= 0 then mm:SetZoom(0) end
	if C_Minimap.GetDrawGroundTextures() then C_Minimap.SetDrawGroundTextures(false) end
	if not C_Minimap.IsRotateMinimapIgnored() then C_Minimap.SetIgnoreRotateMinimap(true) end
	return held
end

-- Under the window's view, all of it on the screen; still: placed as last frame (View's
-- place is the same table while it doesn't move), where it was put, held, and its zoom
-- applied (a new one applies a frame or two late, its view radius 0 meanwhile: D5a, E6).
-- Where it went is kept in Game.minimap (left, bottom, size in its own units; scale) for
-- the sensor to read; moved by anyone else (or a new UI scale), it's put back.
local function Place(w, held)
	local mm = Minimap
	local r, l, b, size = C_Minimap.GetViewRadius(), mm:GetRect()
	local ready = held and not issecretvalue(r) and r > 0
	local there = placed and l and mm:GetEffectiveScale() == m.scale and math.abs(l - m.left) < 1
		and math.abs(b - m.bottom) < 1 and math.abs(size - m.size) < 1
	if there and placed.place == w.place and placed.strata == w.strata and placed.level == w.level then
		m.still = w.still and ready
		return
	end
	local s, p = UIParent:GetEffectiveScale(), w.place
	local sw, sh, half = UIParent:GetWidth() * s, UIParent:GetHeight() * s, SENSOR_PX / 2 + MARGIN
	local x = math.max(half, math.min(sw - half, (p.left + p.w / 2) * s))
	local y = math.max(half, math.min(sh - half, (p.top - p.h / 2) * s))
	local moved = not there or placed.x ~= x or placed.y ~= y
	placed, m.still = { place = w.place, strata = w.strata, level = w.level, x = x, y = y }, not moved and w.still and ready
	local strata, level = Beneath(w.strata, w.level)
	mm:SetFrameStrata(strata)
	mm:SetFrameLevel(level)
	if not moved then return end
	local ms = mm:GetEffectiveScale()
	local d, cx, cy = SENSOR_PX / ms, x / ms, y / ms -- /: never 0 (an effective scale is > 0)
	mm:SetSize(d, d)
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
	m.left, m.bottom, m.size, m.scale = cx - d / 2, cy - d / 2, d, ms
end

Game.Apply("minimap", function(view)
	local w = view.window
	m.blocker = FarmHud and FarmHud.IsShown and FarmHud:IsShown() and "FarmHud has the minimap" or nil
	if view.minimap ~= "ours" or not (w.shown and w.place) or m.blocker then
		Release()
	else
		if not m.engaged then Engage() end
		local whole = view.renderer == "blizzard"
		m.sensor = view.layers.blips == true and not whole
		if whole then
			m.still = false
			Game.Whole(w)
		else
			if m.whole then
				Game.Whole(nil)
				Sensor()
			end
			Place(w, Hold(Minimap))
		end
	end
	Cluster()
end)

Runtime.On("PLAYER_LOGOUT", "game.minimap logout", Release)

-- The Minimap takeover (the minimum of the spike's MinimapTakeover.lua), in the
-- apply phase (Game.Apply), from View (types/view.lua):
--   View.minimap "ours" and the window shown (nothing blocking): Blizzard's
--     Minimap becomes an unseen sensor, SENSOR_PX square, centred under the
--     window's view (kept on the screen: off it the client stops updating its
--     blips), just beneath the window's strata, at its widest zoom, north up, no
--     ground, no mouse. What hung on it waits on a stand-in at its home spot; the
--     cluster hides.
--   otherwise (or a View Game can't use: SAFE, game/Apply.lua): released, every change undone.
-- Every change Engage makes is paired with its undo on a list; Release runs it
-- backwards, so what comes back is exactly what was taken.
-- Game.minimap tells the sensor (game/Blips.lua) where things stand: engaged,
-- sensor (the blips layer is on), still (the last Apply didn't move it).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local SENSOR_PX = 300   -- its side in screen units (a blip's square is ~16 of them)
local MARGIN = 2        -- screen units it keeps inside the screen's edge
local ICONS = 0.05      -- its own icons' scale: out of sight (alpha alone doesn't hide them)
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

local m = { engaged = false, sensor = false, still = false } -- blocker: why it isn't taken
Game.minimap = m
local undo, placed = {}, nil

local standIn = CreateFrame("Frame", "MagicMapAtlasMinimapStandIn", UIParent)
standIn:Hide()

local function OnRelease(fn) undo[#undo + 1] = fn end

-- Swap anchors relative to `from` for the same anchors relative to `to`.
local function Reanchor(obj, from, to)
	local points = {}
	for i = 1, obj:GetNumPoints() do
		local p, rel, rp, x, y = obj:GetPoint(i)
		if rel == from then points[#points + 1] = { p, rp, x, y } end
	end
	for _, p in ipairs(points) do obj:SetPoint(p[1], to, p[2], p[3], p[4]) end
end

local function Move(obj, from, to)
	local t = obj:GetObjectType()
	if t == "Line" or t == "MaskTexture" or (obj.IsProtected and obj:IsProtected()) then return end
	obj:SetParent(to)
	Reanchor(obj, from, to)
	OnRelease(function()
		obj:SetParent(from)
		Reanchor(obj, to, from)
	end)
end

local function Engage()
	m.engaged = true
	local mm = Minimap
	local parent, w, h = mm:GetParent(), mm:GetSize()
	local points = {}
	for i = 1, mm:GetNumPoints() do points[i] = { mm:GetPoint(i) } end
	local scale, strata, level, zoom, alpha = mm:GetScale(), mm:GetFrameStrata(), mm:GetFrameLevel(), mm:GetZoom(), mm:GetAlpha()
	local ground, unrotated = C_Minimap.GetDrawGroundTextures(), C_Minimap.IsRotateMinimapIgnored()
	local mouse, wheel, shown = mm:IsMouseEnabled(), mm:IsMouseWheelEnabled(), mm:IsShown()
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
	-- The stand-in takes the Minimap's place (hidden with the cluster: it only holds things).
	standIn:SetParent(parent)
	standIn:ClearAllPoints()
	for _, p in ipairs(points) do standIn:SetPoint(unpack(p)) end
	standIn:SetSize(w, h)
	for _, obj in ipairs({ mm:GetChildren() }) do Move(obj, mm, standIn) end
	for _, obj in ipairs({ mm:GetRegions() }) do Move(obj, mm, standIn) end
	if MinimapCluster:IsShown() then
		MinimapCluster:Hide()
		OnRelease(function() MinimapCluster:Show() end)
	end
	mm:SetParent(UIParent)
	mm:SetScale(1)
	mm:SetAlpha(0)
	mm:SetIconScale(ICONS)
	mm:EnableMouse(false)
	mm:EnableMouseWheel(false)
	C_Minimap.SetDrawGroundTextures(false)
	C_Minimap.SetIgnoreRotateMinimap(true)
	mm:Show()
	placed = nil
	Runtime.Trace("minimap", "engaged")
end

local function Release()
	if not m.engaged then return end
	m.engaged, m.sensor, m.still, placed = false, false, false, nil
	local failure
	for i = #undo, 1, -1 do -- every step runs; the first failure is raised after
		local ok, err = pcall(undo[i])
		if not ok and not failure then failure = err end
		undo[i] = nil
	end
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

-- Under the window's view, all of it on the screen; still: placed as last frame (View's
-- place is the same table while it doesn't move). Where it went is kept in Game.minimap
-- (left, bottom, size in its own units; scale) for the sensor to read.
local function Place(w)
	if placed and placed.place == w.place and placed.strata == w.strata and placed.level == w.level then
		m.still = w.still
		return
	end
	local s, p = UIParent:GetEffectiveScale(), w.place
	local sw, sh, half = UIParent:GetWidth() * s, UIParent:GetHeight() * s, SENSOR_PX / 2 + MARGIN
	local x = math.max(half, math.min(sw - half, (p.left + p.w / 2) * s))
	local y = math.max(half, math.min(sh - half, (p.top - p.h / 2) * s))
	local mm = Minimap
	local moved = not placed or placed.x ~= x or placed.y ~= y
	placed, m.still = { place = w.place, strata = w.strata, level = w.level, x = x, y = y }, not moved and w.still
	local strata, level = Beneath(w.strata, w.level)
	mm:SetFrameStrata(strata)
	mm:SetFrameLevel(level)
	if not moved then return end
	local ms = mm:GetEffectiveScale()
	local d = SENSOR_PX / ms
	mm:SetZoom(0)
	mm:SetSize(d, d)
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / ms, y / ms)
	m.left, m.bottom, m.size, m.scale = x / ms - d / 2, y / ms - d / 2, d, ms
end

Game.Apply("minimap", function(view)
	local w = view.window
	m.blocker = FarmHud and FarmHud.IsShown and FarmHud:IsShown() and "FarmHud has the minimap" or nil
	if view.minimap ~= "ours" or not (w.shown and w.place) or m.blocker then return Release() end
	if not m.engaged then Engage() end
	m.sensor = view.layers.blips == true and view.renderer ~= "blizzard"
	Place(w)
end)

Runtime.On("PLAYER_LOGOUT", "game.minimap logout", Release)

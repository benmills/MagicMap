-- You on the map: your arrow (Core.lua:155-175, 795-819), the Minimap's own arrow art with its shadow
-- softened (Textures/PlayerArrow.tga: tools/gen_arrow.py), the size the Minimap draws it, unsnapped
-- so it turns smoothly, over every layer. None while the map shown isn't yours, while the client
-- withholds where you are (Model.you stale: an instance's), or without a facing. Your corpse and your
-- waypoint as pins (Layers.lua:500-521, 625-634), and the title band's target (Core.lua:1294-1300).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local SIZE = 22 * 64 / 45 -- the texture, for a 22-unit arrow (Core.lua:169)
local PINS = 13 -- the corpse's and the waypoint's level: over the blips (12), under the offers (14)
-- On the quest pins' disc, no halo (that's only the followed quest's): Layers.lua:512-516.
local CORPSE = { size = 22, icon = { atlas = "deathrecap-icon-tombstone", under = "UI-QuestPoi-QuestNumber", scale = 0.6,
	aspect = 15 / 20, color = { 0.85, 0.85, 0.85 } } }
local WAYPOINT = { size = 22, icon = { atlas = "Waypoint-MapPin-Tracked", color = { 0.2, 0.9, 1 } } } -- Layers.lua:629-630
local TARGET = "Target" -- an untitled target's (Core.lua:1297)

local You = {}
UI.You = You

-- Over the layers (quests' pins: +17) and the world socket (+10): the spike's overlay (Core.lua:158),
-- the edge arrow's too (ui/Path.lua).
local overlay = CreateFrame("Frame", nil, Window.view)
overlay:SetAllPoints()
overlay:SetFrameLevel(Window.view:GetFrameLevel() + 18)
You.overlay = overlay
local arrow = overlay:CreateTexture(nil, "OVERLAY")
arrow:SetTexture(Atlas.ROOT .. "Textures\\PlayerArrow")
arrow:SetSize(SIZE, SIZE)
arrow:SetSnapToPixelGrid(false)
arrow:SetTexelSnappingBias(0)
arrow:Hide()
You.arrow = arrow

-- Each frame while shown, after the map's draw: only what changed is applied (an idle frame makes
-- no widget calls for it).
Runtime.Step("ui", "map: you", function()
	local you = ns.Model.you
	if you and you.col and not you.stale and you.facing and you.inst == Camera.inst then
		local w, h = Window.Size()
		local x, y = Maths.TileToScreen(Camera.cam, w, h, you.col, you.row)
		x, y = math.max(-SIZE, math.min(w + SIZE, x)), math.max(-SIZE, math.min(h + SIZE, y)) -- off the view: kept by it (no offset grows)
		if arrow.x ~= x or arrow.y ~= y then
			arrow.x, arrow.y = x, y
			arrow:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
		end
		if arrow.facing ~= you.facing then
			arrow.facing = you.facing
			arrow:SetRotation(you.facing)
		end
		if not arrow.shown then arrow.shown = true; arrow:Show() end
	elseif arrow.shown then
		arrow.shown = false
		arrow:Hide()
	end
end, { shownOnly = Window.frame })

-- The target in the title band (Core.lua:1294-1300): its title, and how far you are from it in yards
-- (rounded), or false: here (inside its area). Nil: no target on the map shown, or no position of yours.
function You.Target()
	local t, you = Model.Target(), Model.you
	if not (t and t.pos.inst == Camera.inst) then return nil end
	if t.inside then return t.title or TARGET, false end
	if not you.col or you.stale then return nil end
	local yd = math.sqrt((t.pos.col - you.col) ^ 2 + (t.pos.row - you.row) ^ 2) * Atlas.TILE_YARDS
	return t.title or TARGET, math.floor(yd + 0.5)
end

-- Your corpse (Known("corpse"): the ghost's target) and your waypoint (Known("waypoint")), their tooltips
-- the spike's.
UI.Corpse = UI.Pins.Layer("corpse", PINS, function(put)
	for _, e in ipairs(Model.Known("corpse")) do put(e, CORPSE) end
end, function() return select(2, Model.Known("corpse")) end, {
	lines = function() return "Your corpse" end, -- Layers.lua:514
})
UI.Waypoint = UI.Pins.Layer("waypoint", PINS, function(put)
	for _, e in ipairs(Model.Known("waypoint")) do put(e, WAYPOINT) end
end, function() return select(2, Model.Known("waypoint")) end, {
	lines = function() return "Waypoint", "Ctrl-right-click the map to clear" end, -- Layers.lua:629
})
-- (no gear rows: the corpse and the waypoint are always drawn while there's one)

-- You on the map: your arrow (Core.lua:155-175, 795-819), the Minimap's own arrow (its atlas,
-- ui-hud-minimap-arrow-player; the classic Interface\Minimap\MinimapArrow where a client lacks it), the size the
-- Minimap draws it, unsnapped so it turns smoothly, over every layer. None while the map shown isn't yours, while the client
-- withholds where you are (Model.you stale: an instance's), without a facing, or while Blizzard's Minimap is seen over the
-- map (obs.minimap.overlaid, /mm overlay: its own arrow is there, and can't be hidden). Your corpse and your
-- waypoint as pins (Layers.lua:500-521, 625-634), the waypoint's left out while a tracked icon stands on it
-- (ui/Track.lua: the icon is the target), and the title band's target (Core.lua:1294-1300), named for the
-- tracked icon then. Its size: Settings > Map > Your arrow (ui/Feel.lua). The corpse's and the waypoint's types:
-- Settings > Pins > Other (ui/PinTypes.lua), Blizzard's other art for each to choose from.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local SIZE = 22 -- a 22-unit arrow (Core.lua:169): the atlas's own size
local ARROW, OLD_ARROW = "ui-hud-minimap-arrow-player", "Interface\\Minimap\\MinimapArrow" -- (the Minimap's)
local PINS = 13 -- the corpse's and the waypoint's level: over the places and rares (11), under the quests (15)
-- On the quest pins' disc, no halo (that's only the followed quest's): Layers.lua:512-516.
local CORPSE = { size = 22, icon = { atlas = "deathrecap-icon-tombstone", under = "UI-QuestPoi-QuestNumber", scale = 0.6,
	aspect = 15 / 20, color = { 0.85, 0.85, 0.85 } }, type = "corpse" }
local WAYPOINT = { size = 22, icon = { atlas = "Waypoint-MapPin-Tracked", color = { 0.2, 0.9, 1 } }, type = "waypoint" } -- Layers.lua:629-630
UI.PinTypes.Add({ id = "corpse", family = "other", name = "Your corpse", look = CORPSE,
	icons = { { "Tombstone on a disc", "A:deathrecap-icon-tombstone" }, { "Skull and cross", "A:playerdeadblip" } },
	big = "always", tip = "Where you died, while you're a ghost." })
UI.PinTypes.Add({ id = "waypoint", family = "other", name = "Waypoint", look = WAYPOINT,
	icons = { { "Map pin", "A:Waypoint-MapPin-Tracked" }, { "Small pin", "A:waypoint-mappin-minimap-tracked" },
		{ "Red cross", "A:xmarksthespot" } },
	big = "always", tip = "The waypoint you set (Ctrl-right-click the map, or Track and Path to)." })
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
if C_Texture.GetAtlasInfo(ARROW) then arrow:SetAtlas(ARROW) else arrow:SetTexture(OLD_ARROW) end
arrow:SetSize(SIZE, SIZE)
arrow:SetSnapToPixelGrid(false)
arrow:SetTexelSnappingBias(0)
arrow:Hide()
You.arrow = arrow
UI.Feel.Add("map", "You", {
	{ key = "arrow.scale", kind = "slider", label = "Your arrow", min = 0.6, max = 1.6, step = 0.1, pct = true, default = 1,
		apply = function(k) arrow:SetSize(SIZE * k, SIZE * k) end, tip = "Your arrow's size." },
})

-- Each frame while shown, after the map's draw: only what changed is applied (an idle frame makes
-- no widget calls for it).
Runtime.Step("ui", "map: you", function()
	local you = ns.Model.you
	local mm = Model.minimap
	if you and you.col and not you.stale and you.facing and you.inst == Camera.inst and not (mm and mm.overlaid) then
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
	local title = t.title or TARGET
	if t.kind == "waypoint" and UI.Track.Covers(t.pos) then title = UI.Track.Name() or title end
	if t.inside then return title, false end
	if not you.col or you.stale then return nil end
	local yd = math.sqrt((t.pos.col - you.col) ^ 2 + (t.pos.row - you.row) ^ 2) * Atlas.TILE_YARDS
	return title, math.floor(yd + 0.5)
end

-- Your corpse (Known("corpse"): the ghost's target) and your waypoint (Known("waypoint")), their tooltips
-- the spike's.
UI.Corpse = UI.Pins.Layer("corpse", PINS, function(put)
	for _, e in ipairs(Model.Known("corpse")) do put(e, CORPSE) end
end, function() return select(2, Model.Known("corpse")) end, {
	lines = function() return "Your corpse" end, -- Layers.lua:514
})
-- None while Blizzard's Minimap is seen over the small map (obs.minimap.overlaid): its own waypoint pin is there.
local function Blips()
	local mm = Model.minimap
	return mm and mm.overlaid or false
end
UI.Waypoint = UI.Pins.Layer("waypoint", PINS, function(put)
	if Blips() then return end
	for _, e in ipairs(Model.Known("waypoint")) do
		if not UI.Track.Covers(e.pos) then put(e, WAYPOINT) end -- (a tracked icon stands on it: that reads as the target)
	end
end, function() return select(2, Model.Known("waypoint")) * 2 + (Blips() and 1 or 0) end, {
	lines = function() return "Waypoint" end, -- Layers.lua:629 (its popup clears it: ui/Track.lua's Actions)
})
-- (no gear rows: the corpse and the waypoint are always drawn while there's one)

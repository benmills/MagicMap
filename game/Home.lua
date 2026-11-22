-- The Minimap's home spot: obs.minimap.home, where UI puts the small window (UIParent units,
-- types/observation.lua MM.ScreenRect), with the cluster's strata (UI's small window sits in it); and
-- View.window.homeAlpha, the spot faded while big. Read each time (whatever moved it, a new UI scale
-- or Edit Mode): from the Minimap before the takeover moves it, from then on from its stand-in,
-- which holds the spot at its scale (game/Minimap.lua); a new rect only when it moved.

local _, ns = ...
local Game = ns.Game

local home -- the last read

function Game.Home()
	local spot = Game.minimap.engaged and MagicMapMinimapStandIn or Minimap
	local left, top, w, h = spot:GetLeft(), spot:GetTop(), spot:GetSize()
	if not (left and top) then return home, MinimapCluster:GetFrameStrata() end -- (not laid out yet)
	local s = spot:GetEffectiveScale() / UIParent:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
	left, top, w, h = left * s, top * s, w * s, h * s
	if not (home and home.left == left and home.top == top and home.w == w and home.h == h) then
		home = { left = left, top = top, w = w, h = h }
	end
	return home, MinimapCluster:GetFrameStrata()
end

-- Where UI's badge goes under Blizzard's minimap (ui/Under.lua): under the tracking button left of the zone name, as
-- Blizzard's addon compartment is under the calendar (its TOP to the calendar's BOTTOM, 1 px up; with the header
-- under the map, its BOTTOM to the calendar's TOP, 1 px down): { x, y, below } in UIParent units, x the button's
-- centre, y the edge the badge hangs from, below whether it hangs under it. nil while the tracking button isn't shown.
local badge
function Game.BadgeSpot()
	local t = MinimapCluster.Tracking
	t = t and t:IsVisible() and (t.Button or t)
	local x, bottom, top = t and t:GetCenter(), t and t:GetBottom(), t and t:GetTop()
	if not (x and bottom and top) then return nil end
	local c = AddonCompartmentFrame
	local below = not (c and c:GetNumPoints() > 0 and c:GetPoint(1) == "BOTTOM")
	local s = t:GetEffectiveScale() / UIParent:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
	x = x * s
	local y = below and bottom * s + 1 or top * s - 1
	if not (badge and badge.x == x and badge.y == y and badge.below == below) then badge = { x = x, y = y, below = below } end
	return badge
end

-- Where Blizzard's + is under its minimap (ui/Under.lua stands the reset and pin above it, as above ours): { x, y }
-- in UIParent units, its centre. nil on a client without one, or before it's laid out.
local zoom
local ZOOM_IN = Minimap.ZoomIn or MinimapZoomIn
function Game.ZoomSpot()
	local x, y
	if ZOOM_IN then x, y = ZOOM_IN:GetCenter() end
	if not (x and y) then return nil end
	local s = ZOOM_IN:GetEffectiveScale() / UIParent:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
	x, y = x * s, y * s
	if not (zoom and zoom.x == x and zoom.y == y) then zoom = { x = x, y = y } end
	return zoom
end

-- The spot (the cluster, and the stand-in holding what hung on the Minimap) at homeAlpha of the
-- cluster's own alpha: read when it first fades, put back at 1. 0 while the takeover can't hide the
-- cluster yet (Game.minimap.fade).
local own, applied = nil, 1
Game.Apply("home", function(view)
	local a = Game.minimap.fade and 0 or view.window.homeAlpha
	if a == applied then return end
	own, applied = own or MinimapCluster:GetAlpha(), a
	MinimapCluster:SetAlpha(own * a)
	MagicMapMinimapStandIn:SetAlpha(own * a)
	if a == 1 then own = nil end
end)

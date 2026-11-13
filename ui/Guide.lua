-- Track's arrow: Blizzard's gold guide arrow (the Minimap's ROTATING-MINIMAPGUIDEARROW, the art of the line's edge
-- arrow: ui/Path.lua) showing the way to the target (Model.Target) while it's tracked, not pathed (UI.Track.Pathed:
-- then the line has it). Placed by the walk the line follows (Model.Route: you first, the target last; straight
-- without one), not on the view's edge:
--   where: `reach` px from you along the way (Settings > Tracking > Distance), measured along the walk, so it
--     stands on the way's first leg or round its first bend, not on the straight bearing to the target;
--   which way: along the way where it stands (the chord from LOOK px before it to LOOK after: a rounded corner
--     reads as one turn), never your facing (your own arrow shows that, and turning doesn't move this one);
--   how far: reach while the target is further along the way than that; nearer, it rides in just short of the
--     target's pin (CLEAR px), so it settles beside it, and fades as the pin comes within reach of your arrow
--     (NEAR): the pin takes over;
--   in view: reach is at most half the view less INSET, and the arrow is kept INSET inside it.
-- Eased (RATE a second) as a distance and an angle about you, and its rotation, so a route found again, a corner
-- turned or a zoom swings it round instead of making it jump; only a move past a tenth of a px or a fifth of a
-- degree is set (no widget call at rest). It fades in and out. None while you're off the view (panned away), not
-- on the target's map, or once you've arrived (UI.Track.Arrived: inside its area, or within 5 yards). Its look: Settings > Tracking (Size, Opacity, Distance).

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = ns.Atlas.Camera
local sqrt, atan2, cos, sin, exp, pi = math.sqrt, math.atan2, math.cos, math.sin, math.exp, math.pi

local ART, SIZE = "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW", 32 -- the edge arrow's (ui/Path.lua)
local INSET = 14 -- px from the view's edge to its centre, at most
local CLEAR = 16 -- px short of the target's pin it rides in to
local NEAR = 12 -- px from you, plus a third of its size: its least (clear of your arrow)
local FADE = 12 -- px the target comes in over while it fades
local LOOK = 10 -- px either side of where it stands: the chord its way is
local RATE = 5 -- per second: the share of the way to where it should be it closes (1 - e^-RATE)
local MOVE, TURN, DIM = 0.1, math.rad(0.2), 0.01 -- px, radians, alpha: less isn't set
local DEFAULTS = { size = 1.05, opacity = 1, reach = 96 }

local Guide = { DEFAULTS = DEFAULTS }
UI.Guide = Guide

local arrow = UI.You.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
arrow:SetTexture(ART)
arrow:SetSize(SIZE * DEFAULTS.size, SIZE * DEFAULTS.size)
arrow:SetSnapToPixelGrid(false)
arrow:SetTexelSnappingBias(0)
arrow:SetAlpha(0)
arrow:Hide()
Guide.arrow = arrow

local size, opacity, reach = DEFAULTS.size, DEFAULTS.opacity, DEFAULTS.reach
UI.Feel.Add("tracking", "Arrow", {
	{ key = "guide.size", kind = "slider", label = "Size", min = 0.6, max = 1.6, step = 0.05, pct = true, default = DEFAULTS.size,
		apply = function(v)
			size = v
			arrow:SetSize(SIZE * v, SIZE * v)
		end, tip = "The gold arrow's size." },
	{ key = "guide.opacity", kind = "slider", label = "Opacity", min = 0.3, max = 1, step = 0.05, pct = true,
		default = DEFAULTS.opacity, apply = function(v) opacity = v end, tip = "How solid the gold arrow is." },
	{ key = "guide.reach", kind = "slider", label = "Distance", min = 24, max = 96, step = 4, fmt = "%d px",
		default = DEFAULTS.reach, apply = function(v) reach = v end,
		tip = "How far from you the arrow sits along the way, at most. It comes in as you near what you track." },
})

local function Clamp(v, lo, hi) return v < lo and lo or v > hi and hi or v end
local function Wrap(a) return (a + pi) % (2 * pi) - pi end -- (-pi..pi)

-- The way on the view, px: you, the route's points between, the target ([1..n]).
local xs, ys = {}, {}
local function Way(me, t, cam, w, h)
	local route = Model.Route()
	if route and route.straight then route = nil end
	xs[1], ys[1] = Maths.TileToScreen(cam, w, h, me.col, me.row)
	local n = 1
	for i = 2, route and #route - 1 or 0 do
		n = n + 1
		xs[n], ys[n] = Maths.TileToScreen(cam, w, h, route[i].col, route[i].row)
	end
	n = n + 1
	xs[n], ys[n] = Maths.TileToScreen(cam, w, h, t.pos.col, t.pos.row)
	return n
end

-- The point s px along the way (its ends past them).
local function At(n, s)
	for i = 2, n do
		local dx, dy = xs[i] - xs[i - 1], ys[i] - ys[i - 1]
		local seg = sqrt(dx * dx + dy * dy)
		if seg > 0 and s <= seg then
			local k = s / seg -- /: never 0 (seg > 0)
			return xs[i - 1] + dx * k, ys[i - 1] + dy * k
		end
		s = s - seg
	end
	return xs[n], ys[n]
end

-- Where it should be (want: d, ang about you, rot, a) for target t, or a = 0 for none; worked out again only once
-- the view, you, the target or the route moved.
local want = { d = 0, ang = 0, rot = 0, a = 0 }
local seen = {} -- cam's cx, cy, zoom, w, h, you, the target's pos, the route, the settings
local function Want(t, me, cam, w, h)
	local route = Model.Route()
	local k = seen
	if k[1] == cam.cx and k[2] == cam.cy and k[3] == cam.zoom and k[4] == w and k[5] == h and k[6] == me.col
		and k[7] == me.row and k[8] == t.pos and k[9] == route and k[10] == size and k[11] == opacity and k[12] == reach then return end
	k[1], k[2], k[3], k[4], k[5], k[6], k[7], k[8], k[9], k[10], k[11], k[12] = cam.cx, cam.cy, cam.zoom, w, h, me.col,
		me.row, t.pos, route, size, opacity, reach
	local n = Way(me, t, cam, w, h)
	local ex, ey = xs[1], ys[1]
	if ex < INSET or ex > w - INSET or ey < INSET or ey > h - INSET then -- (you off the view)
		want.a = 0
		return
	end
	local len = 0
	for i = 2, n do len = len + sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2) end
	local near = NEAR + SIZE * size / 3
	local r = math.max(near, math.min(reach, math.min(w, h) / 2 - INSET))
	local s = Clamp(len - CLEAR, near, r)
	local px, py = At(n, s)
	local ax, ay = At(n, math.max(0, s - LOOK))
	local bx, by = At(n, math.min(len, s + LOOK))
	local dx, dy = bx - ax, by - ay
	if dx == 0 and dy == 0 then dx, dy = px - ex, py - ey end
	px, py = Clamp(px, INSET, w - INSET), Clamp(py, INSET, h - INSET)
	want.d, want.ang = sqrt((px - ex) ^ 2 + (py - ey) ^ 2), atan2(py - ey, px - ex)
	want.rot = atan2(-dx, -dy) -- the art points up
	want.a = opacity * Clamp((len - CLEAR - near) / FADE, 0, 1)
end

-- As shown: on (shown), d, ang, rot, a; the texture's as last set (x, y, r, alpha).
local cur = { on = false, d = 0, ang = 0, rot = 0, a = 0 }

local function Off()
	cur.on, cur.a = false, 0
	arrow.alpha = 0
	arrow:SetAlpha(0)
	arrow:Hide()
end

-- Each frame while shown, after the line's step: eased onto where it should be, then set where that moved.
Runtime.Step("ui", "map: guide", function(elapsed)
	local t, me, inst = Model.Target(), Model.you, Camera.inst
	local cam, w, h = Camera.cam, Window.Size()
	if t and not UI.Track.Arrived(t) and me.col and not me.stale and me.inst == inst and t.pos.inst == inst and w > 0 and h > 0
		and UI.Track.Arrow(t) then
		Want(t, me, cam, w, h)
	else
		seen[1], want.a = nil, 0
	end
	if not cur.on then
		if want.a <= 0 then return end
		cur.on, cur.d, cur.ang, cur.rot, cur.a = true, want.d, want.ang, want.rot, 0 -- (in where it should be: faded in)
		arrow:Show()
	end
	local k = 1 - exp(-RATE * elapsed)
	cur.d = cur.d + (want.d - cur.d) * k
	cur.ang = cur.ang + Wrap(want.ang - cur.ang) * k
	cur.rot = cur.rot + Wrap(want.rot - cur.rot) * k
	cur.a = math.abs(want.a - cur.a) < DIM and want.a or cur.a + (want.a - cur.a) * k
	if cur.a <= 0 then return Off() end
	local x, y = arrow.x, arrow.y -- (no position of yours: it fades where it stood)
	if me.col then
		local ex, ey = Maths.TileToScreen(cam, w, h, me.col, me.row)
		x, y = Clamp(ex + cos(cur.ang) * cur.d, INSET, w - INSET), Clamp(ey + sin(cur.ang) * cur.d, INSET, h - INSET)
	end
	if x and (not arrow.x or math.abs(x - arrow.x) > MOVE or math.abs(y - arrow.y) > MOVE) then
		arrow.x, arrow.y = x, y
		arrow:ClearAllPoints()
		arrow:SetPoint("CENTER", UI.You.overlay, "TOPLEFT", x, -y)
	end
	if not arrow.r or math.abs(Wrap(cur.rot - arrow.r)) > TURN then
		arrow.r = cur.rot
		arrow:SetRotation(cur.rot)
	end
	if not arrow.alpha or math.abs(cur.a - arrow.alpha) >= DIM or cur.a == want.a and arrow.alpha ~= cur.a then
		arrow.alpha = cur.a
		arrow:SetAlpha(cur.a)
	end
end, { shownOnly = Window.frame })

-- Hidden: gone, in again where it should be when the map shows.
Window.frame:HookScript("OnHide", Runtime.Wrap("map: guide hidden", function()
	seen[1] = nil
	Off()
end))

-- How the camera moves, the spike's way (Core.lua:931-1025, 1335-1443, 1507-1550). The wheel
-- and the ± buttons chase a target zoom, closing a fixed share of the (log) distance a second:
-- quick ticks just move the target, so the motion stays continuous instead of restarting a
-- curve per tick. It pins the point under the cursor (you while following, the centre for the
-- buttons). Flights (FlyTo) ease out, zoom in log space and, zooming in, keep the destination
-- on a straight line toward the centre (it "comes to you"). A press moving under CLICK_SLOP px
-- is a click; past it, a drag: it pans and stops following. Panned away and left alone, the
-- small map glides back to following you (MinimapMode.lua:244-249).
-- Window routes the view's input here and calls Chase each frame (ui/Window.lua); what this
-- marks on Camera (moving, zoomedAt, vx, vy) is what Camera.Settled and Camera.Velocity read;
-- Rect is Focus's (ui/View.lua sends it).

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local MIN_ZOOM, MAX_ZOOM = 16, 800 -- px per tile (Core.lua:13)
local WHEEL_STEP = 1.3 -- Core.lua:14
local FLY_TIME = 0.55 -- s (Core.lua:15)
local ZOOM_RATE = 14 -- per second: how quickly wheel zoom closes on its target (Core.lua:16)
local ZOOM_STOP = 0.002 -- log distance the chase lands from (Core.lua:969)
local CLICK_SLOP, CLICK_TIME = 5, 0.35 -- a click moves less than this many px, this fast (Core.lua:17)
local IDLE_FOLLOW = 6 -- s untouched before the map follows you again (MinimapMode.lua:20)
local FIT = 0.92 -- a rect flown to fills this much of the view (Core.lua:1038)
local CHUNKS = Atlas.Walk.CHUNKS -- a tile's walk chunks a side: Focus's rect is out to whole ones

local Motion = {}
UI.Motion = Motion

local goal, anchor -- the wheel's target zoom, and { col, row, dx, dy }: the tile kept at (dx, dy) from the view's centre
local flight -- { t, dur, fx, fy, fz, tx, ty, tz, onDone }
local press -- the left button down: { x, y (the press), lx, ly (the last pan), t, moved }
local touched = 0 -- the last press or zoom step (GetTime): the idle return's clock

Camera.moving, Camera.zoomedAt, Camera.vx, Camera.vy = false, 0, 0, 0
local px, py = Camera.cam.cx, Camera.cam.cy -- the centre at the last step

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function Animating() return goal ~= nil or flight ~= nil end

-- A zoom replaces the camera's table (ui/Camera.lua).
local function Set(cx, cy, zoom)
	if zoom ~= Camera.cam.zoom then Camera.zoomedAt = GetTime() end
	Camera.cam = { cx = cx, cy = cy, zoom = zoom }
end

---------------------------------------------------------------------------
-- Zoom, flights, follow
---------------------------------------------------------------------------

-- One zoom step in (delta > 0) or out, about the cursor (the wheel) or the view's centre
-- (the buttons, and you while following: you're the centre). Ticks stack onto the target.
function Motion.ZoomStep(delta, atCursor)
	local cam, w, h = Camera.cam, Window.Size()
	touched = GetTime()
	goal = Clamp((goal or cam.zoom) * (delta > 0 and WHEEL_STEP or 1 / WHEEL_STEP), MIN_ZOOM, MAX_ZOOM)
	flight, Camera.moving = nil, true
	local x, y = w / 2, h / 2
	if atCursor and not Camera.follow then x, y = Window.Cursor() end
	local col, row = Maths.ScreenToTile(cam, w, h, x, y)
	anchor = { col, row, x - w / 2, y - h / 2 }
	Camera.Trace("wheel")
end

function Motion.Wheel(delta) Motion.ZoomStep(delta, true) end

-- Fly to (cx, cy) at zoom over duration s (default FLY_TIME); onDone() when there.
function Motion.FlyTo(cx, cy, zoom, duration, onDone)
	local cam = Camera.cam
	goal, Camera.moving = nil, true
	flight = { t = 0, dur = duration or FLY_TIME, fx = cam.cx, fy = cam.cy, fz = cam.zoom,
		tx = cx, ty = cy, tz = Clamp(zoom, MIN_ZOOM, MAX_ZOOM), onDone = onDone }
end

-- Following (the view centred on you) or free. glide: fly back to you first, at the zoom you have.
function Motion.SetFollow(on, glide)
	local you = ns.Model.you
	if on and glide and you.col then
		Motion.FlyTo(you.col, you.row, Camera.cam.zoom, FLY_TIME, function() Motion.SetFollow(true) end)
		return
	end
	if Camera.follow ~= on then
		Camera.follow = on
		Camera.Trace(on and "follow on" or "follow off")
	end
end

-- Fly to fit a tile rect (a zone), following off (Core.lua:1123-1127).
function Motion.FlyToRect(c0, r0, c1, r1)
	Motion.SetFollow(false)
	local w, h = Window.Size()
	local cx, cy, zoom = Maths.Fit(c0, r0, c1, r1, w, h, FIT, MIN_ZOOM, MAX_ZOOM)
	Motion.FlyTo(cx, cy, zoom)
end

-- Straight to a zoom, about the view's centre, ending any chase or flight.
function Motion.SetZoom(zoom)
	local cam = Camera.cam
	goal, flight = nil, nil
	Set(cam.cx, cam.cy, Clamp(zoom, MIN_ZOOM, MAX_ZOOM))
end

-- Where the camera is headed: the zoom and centre it will settle at (Core.lua:993-1005).
function Motion.Goal()
	local cam, you = Camera.cam, ns.Model.you
	local zoom = goal or flight and flight.tz or cam.zoom
	if Camera.follow and you.col then return zoom, you.col, you.row end
	if flight then return zoom, flight.tx, flight.ty end
	if goal then return zoom, anchor[1] - anchor[3] / goal, anchor[2] - anchor[4] / goal end -- /: never 0 (goal >= MIN_ZOOM)
	return zoom, cam.cx, cam.cy
end

-- Following: the view centred on you (Model.you with an inst, or nil), but while a flight flies.
function Motion.Chase(you)
	if Camera.follow and you and you.col and not flight then
		local cam = Camera.cam
		cam.cx, cam.cy = you.col, you.row
	end
end

local function StepZoom(elapsed)
	local cam = Camera.cam
	local lz, lg = math.log(cam.zoom), math.log(goal)
	local z = math.exp(lz + (lg - lz) * (1 - math.exp(-ZOOM_RATE * elapsed)))
	if math.abs(lg - math.log(z)) < ZOOM_STOP then z, goal = goal, nil end
	if Camera.follow then
		Set(cam.cx, cam.cy, z) -- Chase keeps you in the middle
	else
		Set(anchor[1] - anchor[3] / z, anchor[2] - anchor[4] / z, z) -- /: never 0 (z: between two zooms >= MIN_ZOOM)
	end
end

local function StepFlight(elapsed)
	local f = flight
	f.t = f.t + elapsed
	local p = math.min(1, f.t / f.dur) -- /: never 0 (a flight's duration: FLY_TIME or a caller's, > 0)
	local e = 1 - (1 - p) ^ 3 -- EaseOutCubic
	local z = math.exp(math.log(f.fz) + (math.log(f.tz) - math.log(f.fz)) * e)
	if p >= 1 then
		flight = nil
		Set(f.tx, f.ty, f.tz)
		if f.onDone then f.onDone() end
	elseif f.tz > f.fz then -- the target's offset on screen shrinks linearly while we zoom in on it
		local k = f.fz / z * (1 - e) -- /: never 0 (z: between two zooms >= MIN_ZOOM)
		Set(f.tx - (f.tx - f.fx) * k, f.ty - (f.ty - f.fy) * k, z)
	else
		Set(f.fx + (f.tx - f.fx) * e, f.fy + (f.ty - f.fy) * e, z)
	end
end

---------------------------------------------------------------------------
-- Press, drag, click
---------------------------------------------------------------------------

-- A press that has moved: the map is being dragged.
function Motion.Dragging() return press ~= nil and press.moved == true end

function Motion.Press(button)
	if button == "LeftButton" then
		local x, y = Window.Cursor()
		touched = GetTime()
		goal, flight = nil, nil
		press = { x = x, y = y, lx = x, ly = y, t = touched, moved = false }
	elseif button == "RightButton" and not Camera.follow then
		Motion.SetFollow(true, true) -- the spike's "Follow me" (Core.lua:1367); its right-click menu: M3.4
	end
end

-- The left button up: true for a click, the press moved under CLICK_SLOP and up within CLICK_TIME.
function Motion.Release()
	local p = press
	press = nil
	if not p then return false end
	if p.moved then Camera.Trace("drag end") end
	return not p.moved and GetTime() - p.t < CLICK_TIME
end

local function StepDrag()
	if not IsMouseButtonDown("LeftButton") then Motion.Release(); return end -- let go off the view
	local x, y = Window.Cursor()
	if not press.moved and (math.abs(x - press.x) > CLICK_SLOP or math.abs(y - press.y) > CLICK_SLOP) then
		press.moved, Camera.moving = true, true
		Camera.follow = false
		Camera.Trace("drag start") -- follow's off now
	end
	if press.moved and (x ~= press.lx or y ~= press.ly) then
		local cam = Camera.cam -- moved in place: no table a frame
		cam.cx, cam.cy = cam.cx - (x - press.lx) / cam.zoom, cam.cy - (y - press.ly) / cam.zoom -- /: never 0 (zoom >= MIN_ZOOM)
		press.lx, press.ly = x, y
	end
end

---------------------------------------------------------------------------
-- Each frame while shown: the camera's flight, chase, drag and idle return; what Camera reports
---------------------------------------------------------------------------

-- Left alone after you've panned away (small only, not hovered), glide back to following you.
local function StepIdle()
	if Camera.follow or press or Animating() or UI.View().window.big then return end
	if Window.frame:IsMouseOver() or GetTime() - touched < IDLE_FOLLOW then return end
	Motion.SetFollow(true, true)
end

Runtime.Step("input", "map: motion", function(elapsed)
	local cam = Camera.cam
	-- The centre's move over the last frame (the steps here, Chase's in the draw, scripts').
	Camera.vx, Camera.vy = (cam.cx - px) / elapsed, (cam.cy - py) / elapsed -- /: never 0 (a frame's elapsed is > 0)
	px, py = cam.cx, cam.cy
	if flight then StepFlight(elapsed) end
	if goal then StepZoom(elapsed) end
	if press then StepDrag() end
	StepIdle()
	Camera.moving = Animating() or Motion.Dragging()
end, { shownOnly = Window.frame })

-- Focus's rect (types/focus.lua): the tile rect in view, out to whole walk chunks; the same
-- table until that changes, and while a drag, chase or flight moves the camera (Model wants
-- where the view rests, not a table a frame). nil while the view has no size.
local rect
function Motion.Rect()
	local w, h = Window.Size()
	if w <= 0 or h <= 0 then return nil end
	local cam, inst = Camera.cam, Camera.inst or 0
	if rect and rect.inst == inst and Camera.moving then return rect end
	local c0, r0 = Maths.ScreenToTile(cam, w, h, 0, 0)
	local c1, r1 = Maths.ScreenToTile(cam, w, h, w, h)
	c0, r0 = math.floor(c0 * CHUNKS) / CHUNKS, math.floor(r0 * CHUNKS) / CHUNKS
	c1, r1 = math.ceil(c1 * CHUNKS) / CHUNKS, math.ceil(r1 * CHUNKS) / CHUNKS
	if not rect or rect.inst ~= inst or rect.c0 ~= c0 or rect.r0 ~= r0 or rect.c1 ~= c1 or rect.r1 ~= r1 then
		rect = { inst = inst, c0 = c0, r0 = r0, c1 = c1, r1 = r1 }
	end
	return rect
end

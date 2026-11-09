-- How the camera moves, the spike's way (Core.lua:931-1025, 1335-1443, 1507-1550). The wheel
-- and the ± buttons chase a target zoom, closing a fixed share of the (log) distance a second:
-- quick ticks just move the target, so the motion stays continuous instead of restarting a
-- curve per tick. Every wheel event is a tick, as the spike's (Core.lua:1422-1441): the MVP the
-- user plays (D4; M1.8b rationed them by time, and a fast scroll mostly did nothing). It pins you
-- while following, else the point under the cursor (the wheel) or the view's centre (the buttons).
-- Flights (FlyTo) ease out, zoom in log space and, zooming in, keep the destination
-- on a straight line toward the centre (it "comes to you"). A press moving under CLICK_SLOP px
-- is a click; past it, a drag: it pans and stops following. Panned away and left alone, the
-- small map glides back to following you (MinimapMode.lua:244-249). While you path to something (Path
-- to, ui/Path.lua's Motion.Frame), the small map frames you and it instead of centring on you (StepFrame);
-- your own pan or zoom holds that, and it comes back as the idle return does. Its settings (General > Movement,
-- ui/Feel.lua): Follow you (Camera.follow), Return to you and its wait (IDLE_FOLLOW), and the zoom a notch (WHEEL_STEP).
-- Window routes the view's input here and calls Chase each frame (ui/Window.lua); what this
-- marks on Camera (moving, zoomedAt, vx, vy) is what Camera.Settled and Camera.Velocity read;
-- Rect is Focus's (ui/View.lua sends it). tools/tests/spike_camera.lua is the spike's camera
-- ported; tools/tests/test_feel.py holds this one to it frame by frame.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local MIN_ZOOM, MAX_ZOOM = 16, 800 -- px per tile (Core.lua:13)
local WHEEL_STEP = 1.3 -- a tick (Core.lua:14)
local FLY_TIME = 0.55 -- s (Core.lua:15)
local ZOOM_RATE = 14 -- per second: how quickly wheel zoom closes on its target (Core.lua:16)
local ZOOM_STOP = 0.002 -- log distance the chase lands from (Core.lua:969)
local CLICK_SLOP, CLICK_TIME = 5, 0.35 -- a click moves less than this many px, this fast (Core.lua:17)
local IDLE_FOLLOW = 6 -- s untouched before the map follows you again (MinimapMode.lua:20)
local FIT = 0.92 -- a rect flown to fills this much of the view (Core.lua:1038)
local WHOLE = 1.0 -- a whole map shown fills the view (Core.lua:1146)
local CHUNKS = Atlas.Walk.CHUNKS -- a tile's walk chunks a side: Focus's rect is out to whole ones
local JUMP = 0.5 -- of the view in a frame: a move further is a jump (a teleport, a hearth), not a speed

local Motion = { MAX_ZOOM = MAX_ZOOM } -- (ui/Interiors.lua: a small building zooms all the way in)
UI.Motion = Motion

local goal, anchor = nil, { 0, 0, 0, 0 } -- the wheel's target zoom; { col, row, dx, dy }: the tile kept at (dx, dy) from the view's centre (set in place: no table a tick)
local flight -- { t, dur, fx, fy, fz, tx, ty, tz, onDone }
local press -- the left button down: { x, y (the press), lx, ly (the last pan), t, moved }
local touched = 0 -- the last press or zoom step (GetTime): the idle return's clock
local wheelStep, idleOn, idleAfter = WHEEL_STEP, true, IDLE_FOLLOW -- (the settings', below)
-- The wheel's events since Motion's last step (its `wheel` trace: what the device sends): how many, their
-- deltas' sum, s from the event before them; at: the last event's GetTime.
local wheel = { n = 0, delta = 0, dt = 0, at = 0 }

Camera.moving, Camera.zoomedAt, Camera.vx, Camera.vy = false, 0, 0, 0
local px, py, pinst -- the centre and map at the last draw; nil: none since the window showed

-- The framing (Path to, ui/Path.lua): framer() -> c0, r0, c1, r1 (you and where you go, tiles) or nil; home(z) ->
-- the zoom it never goes in past (the one you had: z, kept, the first time). framed: it had a box this frame;
-- framing: it moved the camera (Chase leaves it); held: your own pan or zoom paused it, back as the idle return
-- would be; fz: the zoom it glides to; back: the zoom to glide back to once it ends (home's).
local FRAME_PAD = 26 -- px kept clear round the box (the pins at its corners, your arrow)
local FRAME_OUT = 1.15 -- the zoom's past what fits by this (room to walk on)
local FRAME_STEP = 1.1 -- the framing's zooms, each this past the last
local LOG_STEP = math.log(FRAME_STEP)
local FRAME_PAN, FRAME_ZOOM = 5, 3 -- per second: how quickly its centre and zoom close on theirs
local framer, home
local framed, framing, held, fz, back = false, false, false, nil, nil

local step -- (the overlay's steps, below: the one the camera is on)
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function Animating() return goal ~= nil or flight ~= nil or fz ~= nil and Camera.cam.zoom ~= fz end -- (fz: settled once there)

-- The camera moved, in place (a table a zoom frame was `map: motion`'s 3.6-5.7 KB/s zooming: M1b).
local function Set(cx, cy, zoom)
	local cam = Camera.cam
	if zoom ~= cam.zoom then Camera.zoomedAt = GetTime() end
	cam.cx, cam.cy, cam.zoom = cx, cy, zoom
end

---------------------------------------------------------------------------
-- Zoom, flights, follow
---------------------------------------------------------------------------

-- Chase the zoom to `target` (clamped). It keeps you where you are while following, else the point
-- under the cursor (atCursor: the wheel) or the view's centre (the buttons).
local function Aim(target, atCursor)
	local cam, you, w, h = Camera.cam, ns.Model.you, Window.Size()
	touched, step = GetTime(), nil
	goal = Clamp(target, MIN_ZOOM, MAX_ZOOM)
	flight, Camera.moving = nil, true
	if framed then held, fz = true, nil end -- (your zoom: the framing waits)
	local x, y = w / 2, h / 2
	if Camera.follow and you.col then
		x, y = Maths.TileToScreen(cam, w, h, you.col, you.row)
	elseif atCursor then
		x, y = Window.Cursor()
	end
	anchor[1], anchor[2] = Maths.ScreenToTile(cam, w, h, x, y)
	anchor[3], anchor[4] = x - w / 2, y - h / 2
end

-- The overlay spike's steps (/mm overlay: obs.minimap.steps, game/Minimap.lua): while you're followed, the zooms at which
-- each of Blizzard's Minimap's zooms covers the view, rising. A tick inside them goes to the next one at once, as
-- Blizzard's Minimap zooms; past the last either way, the wheel's own glide (its blips fade out); coming back in from
-- past them, it glides to the end one and steps from there. step: the one the camera is on (kept on it as they move).
local STEP_TOL = 0.01 -- of a zoom: on a step
local function Steps()
	local mm = ns.Model.minimap
	local s = Camera.follow and not framed and mm and mm.steps
	if not s then step = nil; return nil end
	return s
end
local function Stepped(ticks)
	local s = Steps()
	if not s then return false end
	local z = goal or Camera.cam.zoom
	local lo, hi = s[1], s[#s]
	local dir = ticks > 0 and 1 or -1
	if z < lo * (1 - STEP_TOL) then -- out past them: in, the glide to the widest (else the wheel's)
		if dir > 0 and z * wheelStep ^ ticks >= lo then Aim(lo); step = 1; return true end
		return false
	end
	if z > hi * (1 + STEP_TOL) then -- in past them: out, the glide to the closest
		if dir < 0 and z * wheelStep ^ ticks <= hi then Aim(hi); step = #s; return true end
		return false
	end
	local i = 1 -- the step it's on, or the nearest
	for j = 2, #s do if math.abs(math.log(s[j] / z)) < math.abs(math.log(s[i] / z)) then i = j end end -- /: never 0 (zooms > 0)
	local on = math.abs(s[i] - z) <= s[i] * STEP_TOL
	local n = on and i + dir or (s[i] > z) == (dir > 0) and i or i + dir
	if n < 1 or n > #s then return false end -- (past the end: the wheel's own)
	if s[n] > MAX_ZOOM or s[n] < MIN_ZOOM then return false end
	touched, goal, flight, step = GetTime(), nil, nil, n
	Set(Camera.cam.cx, Camera.cam.cy, s[n]) -- at once (Chase keeps you in the middle)
	return true
end

-- Past Blizzard's Minimap's zooms (obs.minimap.steps: out past its widest, or in past where its closest fits), its
-- blips not shown: the zoom buttons say so (ui/Controls.lua). False without them (the big map, no overlay).
function Motion.PastBlips()
	local mm = ns.Model.minimap
	local s = mm and mm.steps
	if not s then return false end
	local z = Camera.cam.zoom
	return mm.minZoom ~= nil and z < mm.minZoom or mm.maxZoom ~= nil and z > mm.maxZoom
end

-- The reset (ui/Controls.lua): back to you, at the default zoom (UI.DefaultZoom), following; without where you are,
-- the zoom alone.
function Motion.Reset()
	local you, zoom = ns.Model.you, UI.DefaultZoom()
	held = false
	if you.col then
		Camera.inst = you.inst
		Motion.FlyTo(you.col, you.row, zoom, FLY_TIME, function() Motion.SetFollow(true) end)
	else
		Motion.ZoomTo(zoom)
		Motion.SetFollow(true)
	end
end

-- A zoom of `ticks` steps, in (> 0) or out; ticks stack onto the target (Core.lua:1422-1441). See Aim.
function Motion.ZoomStep(ticks, atCursor)
	if Stepped(ticks) then Camera.Trace("wheel"); return end
	step = nil
	Aim((goal or Camera.cam.zoom) * wheelStep ^ ticks, atCursor)
	if not atCursor then Camera.Trace("wheel") end -- (the wheel's: Motion's step, a frame's events in one)
end

-- Glide to a zoom (the reset button, ui/Controls.lua): the buttons' chase, to `zoom` about the view's centre.
function Motion.ZoomTo(zoom)
	Aim(zoom)
	Camera.Trace("wheel")
end

-- The wheel (ui/Window.lua): each event a tick, in or out by its sign (Core.lua:1424, 1439).
function Motion.Wheel(delta)
	local now = GetTime()
	if wheel.n == 0 then wheel.dt = now - wheel.at end
	wheel.n, wheel.delta, wheel.at = wheel.n + 1, wheel.delta + delta, now
	Motion.ZoomStep(delta > 0 and 1 or -1, true)
end

-- Fly to (cx, cy) at zoom over duration s (default FLY_TIME); onDone() when there.
function Motion.FlyTo(cx, cy, zoom, duration, onDone)
	local cam = Camera.cam
	goal, Camera.moving, step = nil, true, nil
	flight = { t = 0, dur = duration or FLY_TIME, fx = cam.cx, fy = cam.cy, fz = cam.zoom,
		tx = cx, ty = cy, tz = Clamp(zoom, MIN_ZOOM, MAX_ZOOM), onDone = onDone }
end

-- Following (the view centred on you) or free. glide: fly back to you first, at the zoom you have,
-- on your map (Core.lua:1080-1085).
function Motion.SetFollow(on, glide)
	local you = ns.Model.you
	if on then held = false end
	if on and glide and you.col then
		Camera.inst = you.inst
		Motion.FlyTo(you.col, you.row, Camera.cam.zoom, FLY_TIME, function() Motion.SetFollow(true) end)
		return
	end
	if Camera.follow ~= on then
		Camera.follow = on
		Camera.Trace(on and "follow on" or "follow off")
	end
end

-- Fly to fit a tile rect (a zone), following off; the title names it (Core.lua:1123-1127).
function Motion.FlyToRect(c0, r0, c1, r1, name)
	Motion.SetFollow(false)
	Camera.zone, Camera.zoneInst = name, Camera.inst
	local w, h = Window.Size()
	local cx, cy, zoom = Maths.Fit(c0, r0, c1, r1, w, h, FIT, MIN_ZOOM, MAX_ZOOM)
	Motion.FlyTo(cx, cy, zoom)
end

-- A whole map at once, ending any chase or flight: its continent's rect, else its tiles'
-- (Core.lua:1133-1152, FitMap).
function Motion.FitMap(inst)
	goal, flight, step = nil, nil, nil
	Camera.inst = inst
	local cont = Atlas.Continent(inst)
	local r = cont and Atlas.MapRect(cont)
	local c0, r0, c1, r1
	if r then c0, r0, c1, r1 = r.col0, r.row0, r.col1, r.row1 else c0, r0, c1, r1 = Atlas.TileBounds(inst) end
	if c0 then
		local w, h = Window.Size()
		Set(Maths.Fit(c0, r0, c1, r1, w, h, WHOLE, MIN_ZOOM, MAX_ZOOM))
	else
		Set(32, 32, Camera.cam.zoom)
	end
end

-- Straight to a zoom, about the view's centre, ending any chase or flight.
function Motion.SetZoom(zoom)
	local cam = Camera.cam
	goal, flight, step = nil, nil, nil
	Set(cam.cx, cam.cy, Clamp(zoom, MIN_ZOOM, MAX_ZOOM))
end

-- Where the camera is headed: the zoom and centre it will settle at (Core.lua:993-1005).
function Motion.Goal()
	local cam, you = Camera.cam, ns.Model.you
	local zoom = goal or flight and flight.tz or fz or cam.zoom
	if framing and not (flight or goal) then return zoom, cam.cx, cam.cy end -- (where the framing heads is where it is, near enough)
	if Camera.follow and you.col then return zoom, you.col, you.row end
	if flight then return zoom, flight.tx, flight.ty end
	if goal then return zoom, anchor[1] - anchor[3] / goal, anchor[2] - anchor[4] / goal end -- /: never 0 (goal >= MIN_ZOOM)
	return zoom, cam.cx, cam.cy
end

-- Following: the view centred on you (Model.you with an inst, or nil), but while a flight flies;
-- on a map that withholds where you are, the whole of it if we have its tiles, else the map
-- you came from stays (Core.lua:1119, 1540-1542: K5).
function Motion.Chase(you)
	if not (Camera.follow and you) or flight or framing then return end
	if you.col then
		local cam = Camera.cam
		cam.cx, cam.cy = you.col, you.row
	elseif you.inst ~= Camera.inst and Atlas.Tiles(you.inst) then
		Motion.FitMap(you.inst)
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

-- The left button held, moved or not (the spike's state.dragging, set on the press: Core.lua:1349).
function Motion.Pressed() return press ~= nil end

-- The cursor on the screen, in the view's units, y up: a press and its pans are measured there, so the
-- window moving under a still cursor (growing, shrinking) isn't a drag (Core.lua:1345-1351, 1523-1534).
local function Screen()
	local x, y = GetCursorPosition()
	local s = Window.view:GetEffectiveScale()
	return x / s, y / s -- /: never 0 (an effective scale is > 0)
end

-- The left button down (Core.lua:1344-1352).
function Motion.Press()
	local x, y = Screen()
	touched = GetTime()
	goal, flight = nil, nil
	press = { x = x, y = y, lx = x, ly = y, t = touched, moved = false }
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
	local x, y = Screen()
	if not press.moved and (math.abs(x - press.x) > CLICK_SLOP or math.abs(y - press.y) > CLICK_SLOP) then
		press.moved, Camera.moving = true, true
		Camera.follow, step = false, nil
		if framed then held, fz = true, nil end
		Camera.Trace("drag start") -- follow's off now
	end
	if press.moved and (x ~= press.lx or y ~= press.ly) then
		local cam = Camera.cam -- moved in place: no table a frame
		-- (screen y is up, rows grow south)
		cam.cx, cam.cy = cam.cx - (x - press.lx) / cam.zoom, cam.cy + (y - press.ly) / cam.zoom -- /: never 0 (zoom >= MIN_ZOOM)
		press.lx, press.ly = x, y
	end
end

---------------------------------------------------------------------------
-- Each frame while shown: the camera's flight, chase, drag and idle return; what Camera reports
---------------------------------------------------------------------------

-- Left alone after you've panned away (small only, not hovered), glide back to following you (framing: StepFrame's).
local function StepIdle()
	if framed or Camera.follow or not idleOn or press or Animating() or UI.View().window.big then return end
	if Window.frame:IsMouseOver() or GetTime() - touched < idleAfter then return end
	Motion.SetFollow(true, true)
end

-- Path to's framing (Motion.Frame), the small map only: the view's centre and zoom ease, every frame, as following pans,
-- so the box (you and where you go) fits inside FRAME_PAD (FRAME_OUT past it), the zoom within MIN_ZOOM and
-- MAX_ZOOM: in as you near it, as far as the map goes; the centre eases on to the box's, kept
-- where you stay in view when the box can't fit. Your own drag or zoom holds it (as panning away holds the
-- follow), back once left alone as the idle return is (Return to you, Return after, not under the cursor); with
-- Return to you off, until you follow again (Follow me) or choose Path to again. Ended (arrived, stopped), the
-- zoom glides back to home's.
local function StepFrame(elapsed)
	local big, was = UI.View().window.big, framed
	framing = false
	local c0, r0, c1, r1
	if framer and not big then c0, r0, c1, r1 = framer() end
	framed = c0 ~= nil
	if not framed then
		if was and back and not held and Camera.follow then Motion.ZoomTo(back) end
		if not big then back = nil end
		held, fz = false, nil
		return
	end
	if held then
		if not idleOn or press or goal or flight or Window.frame:IsMouseOver() or GetTime() - touched < idleAfter then return end
		Motion.SetFollow(true) -- (held cleared)
	end
	if not Camera.follow then -- (Follow you off, a zone flown to: held as a pan is)
		held = true
		return
	end
	framing = true -- (Chase leaves the view where the framing has it: a press, a flight)
	if press or goal or flight then return end
	local cam, you, w, h = Camera.cam, ns.Model.you, Window.Size()
	if w <= 0 or h <= 0 or not you.col then return end
	back = Clamp(home(cam.zoom), MIN_ZOOM, MAX_ZOOM) -- (the zoom it glides back to once ended)
	-- In as far as the map goes as you near it, but for the blips' overlay: no further than its closest zoom fits on the
	-- screen around you (obs.minimap.maxZoom: past it, the overlay hides its blips).
	local mz = ns.Model.minimap and ns.Model.minimap.maxZoom
	local cap = mz and Clamp(mz, MIN_ZOOM, MAX_ZOOM) or MAX_ZOOM
	local aw, ah = math.max(w - 2 * FRAME_PAD, w / 2), math.max(h - 2 * FRAME_PAD, h / 2)
	local fit = math.min(aw / math.max(c1 - c0, 1 / CHUNKS), ah / math.max(r1 - r0, 1 / CHUNKS)) -- /: never 0 (at least a chunk)
	local want = Clamp(fit / FRAME_OUT, MIN_ZOOM, cap)
	-- Progressively, as following pans: every frame a share of the way to the zoom that frames it (fz), which moves
	-- once it's a FRAME_STEP off (settled between: the layouts redo their work only while the
	-- zoom moves; no flicker across a step as you walk to and fro).
	if not fz or want >= cap and fz < cap or math.abs(math.log(want) - math.log(fz)) >= LOG_STEP then fz = want end
	local z, lg = cam.zoom, math.log(fz)
	if z ~= fz then
		z = math.exp(math.log(z) + (lg - math.log(z)) * (1 - math.exp(-FRAME_ZOOM * elapsed)))
		if math.abs(lg - math.log(z)) < ZOOM_STOP then z = fz end
	end
	local hw, hh = math.max(w / 4, w / 2 - FRAME_PAD) / z, math.max(h / 4, h / 2 - FRAME_PAD) / z -- /: never 0 (z >= MIN_ZOOM)
	local tx = Clamp((c0 + c1) / 2, you.col - hw, you.col + hw)
	local ty = Clamp((r0 + r1) / 2, you.row - hh, you.row + hh)
	local k = 1 - math.exp(-FRAME_PAN * elapsed)
	Set(cam.cx + (tx - cam.cx) * k, cam.cy + (ty - cam.cy) * k, z)
end

-- Path to's framer and home (ui/Path.lua; StepFrame's): set once.
function Motion.Frame(fn, homeFn) framer, home = fn, homeFn end

-- A new Path to: a framing your pan or zoom held starts again at once (the small map following you again).
function Motion.Reframe()
	held, fz = false, nil
	if not UI.View().window.big then Motion.SetFollow(true) end
end

local function R3(v) return math.floor(v * 1000 + 0.5) / 1000 end -- for traces

Runtime.Step("input", "map: motion", function(elapsed)
	if wheel.n > 0 then
		Camera.Trace("wheel", wheel.delta, wheel.n, R3(wheel.dt))
		wheel.n, wheel.delta = 0, 0
	end
	if flight then StepFlight(elapsed) end
	if goal then StepZoom(elapsed) end
	if press then StepDrag() end
	StepFrame(elapsed)
	if step and not (goal or flight) then
		local s = Steps()
		local want = s and s[step]
		if want and want <= MAX_ZOOM and want >= MIN_ZOOM and math.abs(want - Camera.cam.zoom) > 1e-6 then
			Set(Camera.cam.cx, Camera.cam.cy, want)
		end
	end
	StepIdle()
	Camera.moving = Animating() or Motion.Dragging()
end, { shownOnly = Window.frame })

-- What Camera.Velocity reports: the centre's move since the last draw (the steps here, Chase's,
-- scripts'), measured in the draw once the map shown is settled. None on the first draw after the
-- window shows (the camera catches up with you then), across maps, or for a jump.
function Motion.Measure(elapsed)
	local cam, w, h = Camera.cam, Window.Size()
	local dx, dy = 0, 0
	if px and Camera.inst == pinst then dx, dy = cam.cx - px, cam.cy - py end
	if math.abs(dx) * cam.zoom > JUMP * w or math.abs(dy) * cam.zoom > JUMP * h then dx, dy = 0, 0 end
	Camera.vx, Camera.vy = dx / elapsed, dy / elapsed -- /: never 0 (a frame's elapsed is > 0)
	px, py, pinst = cam.cx, cam.cy, Camera.inst
end
Window.frame:HookScript("OnShow", Runtime.Wrap("map: motion shown", function() px = nil end))

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

UI.Feel.Add("general", "Movement", {
	{ key = "general.follow", kind = "toggle", label = "Follow you", default = true, keep = true,
		get = function() return Camera.follow == true end, set = function(on) Motion.SetFollow(on, true) end,
		tip = "Keeps the map centred on you. Drag the map to look about; it glides back to you when left alone." },
	{ key = "motion.idle", kind = "toggle", label = "Return to you", default = true, apply = function(v) idleOn = v end,
		tip = "The small map, panned away and left alone, glides back to you. Off: it stays where you left it." },
	{ key = "motion.idleTime", kind = "slider", label = "Return after", min = 2, max = 30, step = 1, fmt = "%d s",
		default = IDLE_FOLLOW, when = "motion.idle", apply = function(v) idleAfter = v end,
		tip = "How long the small map waits, untouched and not under the cursor, before it glides back to you." },
	{ key = "motion.wheel", kind = "slider", label = "Zoom per notch", min = 1.1, max = 2, step = 0.05, default = WHEEL_STEP,
		fmt = function(v) return "+" .. math.floor((v - 1) * 100 + 0.5) .. "%" end, apply = function(v) wheelStep = v end,
		tip = "How far each notch of the mouse wheel (and each press of + or -) zooms where Blizzard's minimap has no zoom of its own: zoomed out past its widest, in past its closest, on the big map, or while you've panned away. Following you, each notch is its next zoom." },
})

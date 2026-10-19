-- The spike's camera, the MVP the user plays (~/code/MagicMap: D4), ported as it is for
-- tools/tests/test_feel.py, which feeds it and ui/Motion.lua the same input and holds ours to
-- its path frame by frame. Core.lua: ZoomStep (1422-1441), StepZoom (965-983), GoalZoom and
-- GoalCenter (994-1006), AnimateTo and StepAnimation (949-1034), SetFollow (1081-1096), the press,
-- drag and release (1335-1352, 1387-1398, 1520-1540), following (1542-1551); MinimapMode.lua: the
-- idle return (246-250), Expand and Collapse's flights (116-189). Left out: its maps (SetMap,
-- FitMap: one map here), clicks on the map (OnMapTap, zone flights), the corpse's follow.
-- env, the world it reads (the sim's): Size() the view's w, h; Cursor() the cursor in the view
-- (CursorInViewport); Screen() the cursor on the screen in the view's units; Down() the left button
-- held; Over() the window hovered; Player() col, row, inst (nil: withheld); Grown() the view's size
-- grown (Expand's vw, vh); ZoneRect() your zone's tile rect on this map, or nil.

local env = ...

local MIN_ZOOM, MAX_ZOOM = 16, 800 -- Core.lua:13
local WHEEL_STEP = 1.3
local FLY_TIME = 0.55
local ZOOM_RATE = 14
local CLICK_SLOP, CLICK_TIME = 5, 0.35
local IDLE_FOLLOW = 6 -- MinimapMode.lua:20
local EXPAND_TIME, COLLAPSE_TIME = 0.22, 0.18
local EXPAND_ZOOM_OUT = 1.5

local state = { cx = 32, cy = 32, zoom = 256, follow = true, dragging = false, lastCursorX = 0, lastCursorY = 0 }
local S = { state = state }

local function Clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

local function TileToScreen(col, row)
	local w, h = env.Size()
	return (col - state.cx) * state.zoom + w / 2, (row - state.cy) * state.zoom + h / 2
end

local anim
local zoomGoal, zoomAnchor

local function EaseOutCubic(t) return 1 - (1 - t) ^ 3 end

local function AnimateTo(cx, cy, zoom, duration, opts)
	opts = opts or {}
	zoomGoal = nil
	anim = {
		t = 0, dur = duration,
		fx = state.cx, fy = state.cy, fz = state.zoom,
		tx = cx, ty = cy, tz = Clamp(zoom, MIN_ZOOM, MAX_ZOOM),
		anchor = opts.anchor, onDone = opts.onDone,
	}
end

local function StopAnimation()
	anim = nil
	zoomGoal = nil
end

local function StepZoom(elapsed)
	if not zoomGoal then return end
	local lz, lg = math.log(state.zoom), math.log(zoomGoal)
	local z = math.exp(lz + (lg - lz) * (1 - math.exp(-ZOOM_RATE * elapsed)))
	if math.abs(lg - math.log(z)) < 0.002 then
		z = zoomGoal
		zoomGoal = nil
	end
	state.zoom = z
	if zoomAnchor and not state.follow then
		local a = zoomAnchor
		state.cx, state.cy = a[1] - a[3] / z, a[2] - a[4] / z
	end
end

local function FollowCenter()
	return state.playerCol, state.playerRow
end

function S.GoalZoom()
	return zoomGoal or (anim and anim.tz) or state.zoom
end

function S.GoalCenter()
	if state.follow and state.playerCol then return FollowCenter() end
	if anim and not anim.anchor then return anim.tx, anim.ty end
	if zoomGoal and zoomAnchor then
		local a = zoomAnchor
		return a[1] - a[3] / zoomGoal, a[2] - a[4] / zoomGoal
	end
	return state.cx, state.cy
end

local function StepAnimation(elapsed)
	if not anim then return end
	anim.t = anim.t + elapsed
	local p = math.min(1, anim.t / anim.dur)
	local e = EaseOutCubic(p)
	local z = math.exp(math.log(anim.fz) + (math.log(anim.tz) - math.log(anim.fz)) * e)
	state.zoom = z
	if anim.anchor then
		local a = anim.anchor
		state.cx, state.cy = a[1] - a[3] / z, a[2] - a[4] / z
	elseif anim.tz > anim.fz then
		local k = (anim.fz / z) * (1 - e)
		state.cx = anim.tx - (anim.tx - anim.fx) * k
		state.cy = anim.ty - (anim.ty - anim.fy) * k
	else
		state.cx = anim.fx + (anim.tx - anim.fx) * e
		state.cy = anim.fy + (anim.ty - anim.fy) * e
	end
	if p >= 1 then
		local done = anim.onDone
		anim = nil
		if done then done() end
	end
end

function S.SetFollow(on, animate)
	if on and animate and state.playerCol then
		local cx, cy = FollowCenter()
		AnimateTo(cx, cy, state.zoom, FLY_TIME, { onDone = function() S.SetFollow(true) end })
		return
	end
	state.follow = on
end

function S.FlyTo(cx, cy, zoom, duration, onDone) AnimateTo(cx, cy, zoom, duration or FLY_TIME, { onDone = onDone }) end

function S.SetZoom(zoom)
	StopAnimation()
	state.zoom = Clamp(zoom, MIN_ZOOM, MAX_ZOOM)
end

function S.IsAnimating() return anim ~= nil or zoomGoal ~= nil end

local function UpdatePlayer()
	local col, row, inst = env.Player()
	state.playerCol, state.playerRow, state.playerMap = col, row, inst
end

local function CursorInViewport() return env.Cursor() end

-- Input (Core.lua:1333-1441).
local press

function S.Press()
	local x, y = env.Screen()
	state.lastInteract = GetTime()
	StopAnimation()
	state.dragging = true
	state.lastCursorX, state.lastCursorY = x, y
	press = { x = x, y = y, t = GetTime() }
end

-- true: a click (the spike's then a tap on a quest or a zone flight, not ported).
function S.Release()
	state.dragging = false
	local click = press and not press.moved and GetTime() - press.t < CLICK_TIME
	press = nil
	return click or false
end

function S.ZoomStep(delta, atCursor)
	local w, h = env.Size()
	local factor = delta > 0 and WHEEL_STEP or 1 / WHEEL_STEP
	state.lastInteract = GetTime()
	local target = Clamp((zoomGoal or state.zoom) * factor, MIN_ZOOM, MAX_ZOOM)
	anim = nil
	local ax, ay
	if state.follow and state.playerCol then
		ax, ay = TileToScreen(state.playerCol, state.playerRow)
	elseif atCursor then
		ax, ay = CursorInViewport()
	else
		ax, ay = w / 2, h / 2
	end
	local tx = state.cx + (ax - w / 2) / state.zoom
	local ty = state.cy + (ay - h / 2) / state.zoom
	zoomGoal, zoomAnchor = target, { tx, ty, ax - w / 2, ay - h / 2 }
end
function S.Wheel(delta) S.ZoomStep(delta, true) end

-- MinimapMode.lua:116-189: the flights of a grow and a shrink (the window's own tween is the sim's).
local expanded, small, tween

local function ReturnToSmallView(target, duration)
	if state.playerCol and state.playerMap == state.map then
		S.FlyTo(state.playerCol, state.playerRow, target.zoom, duration, function() S.SetFollow(true) end)
	else
		S.SetZoom(target.zoom)
		S.SetFollow(true)
	end
end

local function Expand()
	if expanded then return end
	expanded = true
	if not small then small = { zoom = S.GoalZoom() } end
	tween = nil
	local zoom = state.zoom / EXPAND_ZOOM_OUT
	local r = env.ZoneRect()
	if r then
		local vw, vh = env.Grown()
		zoom = math.max(zoom, math.min(vw / (r.col1 - r.col0), vh / (r.row1 - r.row0)) * 0.92)
	end
	if state.playerCol and state.playerMap == state.map then
		S.FlyTo(state.playerCol, state.playerRow, zoom, EXPAND_TIME + 0.1, function() S.SetFollow(true) end)
	end
end

local function Collapse()
	if not expanded then return end
	expanded = false
	local target = small
	tween = { t = 0, dur = COLLAPSE_TIME, onDone = function() small = nil end }
	ReturnToSmallView(target, COLLAPSE_TIME)
end

function S.Toggle() if expanded then Collapse() else Expand() end end
function S.Expanded() return expanded end

-- The map's OnUpdate (Core.lua:1507-1551), then MinimapMode's idle hook (246-250) and tween's end.
function S.Update(elapsed)
	UpdatePlayer()
	StepAnimation(elapsed)
	StepZoom(elapsed)
	if state.dragging then
		if not env.Down() then
			state.dragging = false
		else
			local x, y = env.Screen()
			local dx, dy = x - state.lastCursorX, y - state.lastCursorY
			if press and (math.abs(x - press.x) > CLICK_SLOP or math.abs(y - press.y) > CLICK_SLOP) then
				press.moved = true
				if state.follow then S.SetFollow(false) end
			end
			if (dx ~= 0 or dy ~= 0) and (not press or press.moved) then
				state.cx = state.cx - dx / state.zoom
				state.cy = state.cy + dy / state.zoom
				state.lastCursorX, state.lastCursorY = x, y
			end
		end
	end
	if state.follow and state.playerCol and not anim then
		local cx, cy = FollowCenter()
		if state.cx ~= cx or state.cy ~= cy then state.cx, state.cy = cx, cy end
	end
	if not (expanded or state.follow or state.dragging or S.IsAnimating())
		and not (env.Over() or GetTime() - (state.lastInteract or 0) < IDLE_FOLLOW) then
		S.SetFollow(true, true)
	end
	if tween then
		tween.t = tween.t + elapsed
		if tween.t >= tween.dur then
			local done = tween.onDone
			tween = nil
			done()
		end
	end
end

-- Start from where ours is (the map shown: state.map).
function S.Sync(cx, cy, zoom, follow, map)
	state.cx, state.cy, state.zoom, state.follow, state.map = cx, cy, zoom, follow, map
	StopAnimation()
	state.lastInteract = GetTime()
end

return S

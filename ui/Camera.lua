-- The map's camera: where it looks, and whether it's moving. UI's own; View.camera
-- copies it for Game. Camera.cam = { cx, cy, zoom }: the tile at the view's centre
-- and pixels per tile (Atlas.Camera's maths), moved in place. Camera.inst: the map shown
-- (nil before the first draw). Camera.follow: centred on you. Moved by ui/Motion.lua.

local _, ns = ...
local UI = ns.UI or {}; ns.UI = UI
local Runtime = ns.Runtime

local START_ZOOM = 96 -- px per tile
local SETTLE_S = 0.15 -- s the zoom holds before the map lays out at it

local Camera = { cam = { cx = 32, cy = 32, zoom = START_ZOOM }, follow = true }
UI.Camera = Camera

-- The zoom has stopped: unchanged for 0.15 s (Camera.zoomedAt: ui/Motion.lua marks it). What the
-- map's layers wait for before laying out at a new zoom (ui/Engine.lua); a pan or a drag doesn't count.
function Camera.ZoomSettled() return GetTime() - Camera.zoomedAt >= SETTLE_S end

-- The camera at rest: the zoom settled, and no chase, flight or drag moving it (Camera.moving).
function Camera.Settled() return not Camera.moving and Camera.ZoomSettled() end

-- How fast the view's centre moves, tiles a second (col, row): its move over the last frame
-- (Motion's), 0, 0 when still. The map lays out further ahead of it (ui/Engine.lua).
function Camera.Velocity() return Camera.vx, Camera.vy end

local function R2(v) return math.floor(v * 100 + 0.5) / 100 end -- for traces

-- A "cam" trace: at most one of each e a frame. The wheel's (ui/Motion.lua) says what the device sent
-- since the last frame: delta, the events' deltas summed; n, how many; dt, s from the event before them.
local traced = {} -- e -> the frame it was last traced in
function Camera.Trace(e, delta, n, dt)
	if traced[e] == Runtime.frames then return end
	traced[e] = Runtime.frames
	local cam = Camera.cam
	if not n then
		Runtime.Trace("cam", { e = e, cx = R2(cam.cx), cy = R2(cam.cy), zoom = R2(cam.zoom) })
	else
		Runtime.Trace("cam", { e = e, cx = R2(cam.cx), cy = R2(cam.cy), zoom = R2(cam.zoom), delta = delta, n = n, dt = dt })
	end
end

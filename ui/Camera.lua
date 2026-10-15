-- The map's camera: where it looks, and whether it's moving. UI's own; View.camera
-- copies it for Game. Camera.cam = { cx, cy, zoom }: the tile at the view's centre
-- and pixels per tile (Atlas.Camera's maths); a zoom replaces the table, a pan moves
-- it in place. Camera.inst: the map shown (nil before the first draw). Camera.follow:
-- centred on you. Moved by ui/Motion.lua.

local _, ns = ...
local UI = ns.UI or {}; ns.UI = UI
local Runtime = ns.Runtime

local START_ZOOM = 96 -- px per tile

local Camera = { cam = { cx = 32, cy = 32, zoom = START_ZOOM }, follow = true }
UI.Camera = Camera

-- The zoom has stopped moving: unchanged for 0.15 s, and no chase, flight or drag moving the
-- camera (Camera.moving, Camera.zoomedAt: ui/Motion.lua marks them each frame).
function Camera.Settled() return not Camera.moving and GetTime() - Camera.zoomedAt >= 0.15 end

-- How fast the view's centre moves, tiles a second (col, row): its move over the last frame
-- (Motion's), 0, 0 when still. M1.3 prefetches ahead of it.
function Camera.Velocity() return Camera.vx, Camera.vy end

local function R2(v) return math.floor(v * 100 + 0.5) / 100 end -- for traces

-- A "cam" trace: at most one a frame.
local traced
function Camera.Trace(e)
	if traced == Runtime.frames then return end
	traced = Runtime.frames
	local cam = Camera.cam
	Runtime.Trace("cam", { e = e, cx = R2(cam.cx), cy = R2(cam.cy), zoom = R2(cam.zoom) })
end

-- How the camera moves: the wheel zooms about the cursor (about you while
-- following), a drag pans and stops following, a right click follows you again,
-- and while following the view is centred on you (Chase, from Window's draw step).
-- Input comes routed from Window (ui/Window.lua). AnimateTo and idle return: M1.8.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local MIN_ZOOM, MAX_ZOOM = 4, 1024 -- px per tile

local Motion = {}
UI.Motion = Motion

local drag -- { x, y, cx, cy, moved } while the left button is down

function Motion.Follow()
	if not Camera.follow then Camera.follow = true; Camera.Trace("follow on") end
end

-- Following: the view centred on you (Model.you with an inst, or nil).
function Motion.Chase(you)
	if Camera.follow and you and you.col then
		local cam = Camera.cam
		cam.cx, cam.cy = you.col, you.row
	end
end

-- A press that has moved: the map is being dragged.
function Motion.Dragging() return drag ~= nil and drag.moved == true end

function Motion.Wheel(delta)
	local cam = Camera.cam
	local zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, cam.zoom * 2 ^ (delta / 4)))
	local w, h = Window.Size()
	local x, y = Window.Cursor()
	if Camera.follow then x, y = w / 2, h / 2 end -- following: about you
	Camera.cam = Maths.ZoomAt(cam, w, h, x, y, zoom)
	Camera.Trace("wheel")
end

function Motion.Press(button)
	if button == "LeftButton" then
		local x, y = Window.Cursor()
		drag = { x = x, y = y, cx = Camera.cam.cx, cy = Camera.cam.cy }
	elseif button == "RightButton" then
		Motion.Follow()
	end
end

function Motion.Release()
	if drag and drag.moved then Camera.Trace("drag end") end
	drag = nil
end

Runtime.Step("input", "map: drag", function()
	if not drag then return end
	local x, y = Window.Cursor()
	if Camera.follow and (x - drag.x) ^ 2 + (y - drag.y) ^ 2 < 9 then return end -- a click, not yet a drag
	Camera.follow = false
	local cam = Camera.cam -- moved in place: no table a frame
	cam.cx, cam.cy = drag.cx - (x - drag.x) / cam.zoom, drag.cy - (y - drag.y) / cam.zoom -- /: never 0 (zoom >= MIN_ZOOM)
	if not drag.moved and (x ~= drag.x or y ~= drag.y) then drag.moved = true; Camera.Trace("drag start") end -- follow's off now
end, { shownOnly = Window.frame })

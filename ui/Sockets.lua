-- The sockets (types/view.lua MM.ViewSockets): frames of ours Game puts other addons' pins on.
-- For now the world socket's minimum, for M1.9's HereBeDragons borrow (M4.4 adds the minimap
-- socket and the "Other addons" layers' toggles): a canvas over the map's layers, under your
-- arrow, tile (col, row) of the map shown at (col * zoom, -row * zoom) from its TOPLEFT, while
-- the window shows our renderer; and every addon with world pins (Model.addons) on, as the
-- spike's layers started (AddonPins.lua:113). Its zoom is where the view rests: while a chase or
-- flight moves the camera the canvas is scaled to it instead, so Game re-places each pin once a
-- zoom, not every frame of it (pins grow or shrink with the motion meanwhile).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Camera, Window = UI.Camera, UI.Window

local Sockets = {}
UI.Sockets = Sockets

local view = Window.view
local canvas = CreateFrame("Frame", nil, view)
canvas:SetSize(1, 1)
canvas:SetFrameLevel(view:GetFrameLevel() + 8) -- over the layers' canvases, under the arrow's (+10)
local world = { frame = canvas, inst = 0, zoom = 0 }
Sockets.world = world

local scale, x, y, addons -- as applied
-- Each frame (ui/View.lua's step): View.sockets and the layers Game borrows for.
function Sockets.Update(v)
	if not (Window.frame:IsShown() and v.renderer ~= "blizzard") then
		v.sockets.world = nil
		return
	end
	local cam, w, h = Camera.cam, Window.Size()
	if not Camera.moving or world.zoom == 0 then world.zoom = cam.zoom end
	world.inst = Camera.inst or 0
	local k = cam.zoom / world.zoom -- /: never 0 (a cam's zoom)
	if k ~= scale then scale = k; canvas:SetScale(k) end
	local nx, ny = (w / 2 - cam.cx * cam.zoom) / k, (cam.cy * cam.zoom - h / 2) / k -- /: never 0 (k: two zooms' ratio)
	if nx ~= x or ny ~= y then
		x, y = nx, ny
		canvas:SetPoint("TOPLEFT", view, "TOPLEFT", nx, ny)
	end
	v.sockets.world = world
	if Model.addons ~= addons then
		addons = Model.addons
		for _, a in ipairs(addons) do
			if a.world then v.layers["addon:" .. a.key] = true end
		end
	end
end

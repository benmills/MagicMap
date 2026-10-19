-- The sockets (types/view.lua MM.ViewSockets): frames of ours Game puts other addons' pins on.
-- For now the world socket's minimum, for M1.9's HereBeDragons borrow (M4.4 adds the minimap
-- socket): a canvas over the map's layers, under your arrow, tile (col, row) of the map shown at
-- (col * zoom, -row * zoom) from its TOPLEFT, while the window shows our renderer; and every addon
-- with world pins (Model.addons) whose layer is on (the gear's Other addons, ui/Menus.lua: on until
-- turned off, as the spike's layers started, AddonPins.lua:113), from the frame after a toggle. Its zoom is where the view rests:
-- the camera's, once it holds still a frame (not through a chase, a flight or the window being sized), so Game
-- re-places each pin once a zoom (a job: its holder see-through until done), not every frame of it. Meanwhile the pins would sit at the old
-- zoom: the canvas is see-through until then. Never scaled (a SetScale costs the client per
-- region under the frame, every frame of the motion: thousands with Questie's pins, spike-bugs
-- P4), nor shown or hidden (the same, per region).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Camera, Window, Engine = UI.Camera, UI.Window, UI.Engine

local Sockets = {}
UI.Sockets = Sockets

local view = Window.view
local canvas = CreateFrame("Frame", nil, view)
canvas:SetSize(1, 1)
canvas:SetFrameLevel(view:GetFrameLevel() + 8) -- over the layers' canvases, under the arrow's (+10)
local world = { frame = canvas, inst = 0, zoom = 0 }
Sockets.world = world

local held, placed, x, y = nil, true, nil, nil -- the zoom last frame; as applied
local keys = {} -- an addon's key -> its layer's
-- Each frame (ui/View.lua's step): View.sockets and the layers Game borrows for. True: either changed.
function Sockets.Update(v)
	if not (Window.frame:IsShown() and v.renderer ~= "blizzard") then
		local was = v.sockets.world
		v.sockets.world = nil
		return was ~= nil
	end
	local cam, w, h = Camera.cam, Window.Size()
	if world.zoom == 0 or cam.zoom == held then world.zoom = cam.zoom end
	held = cam.zoom
	world.inst = Camera.inst or 0
	local at = world.zoom == cam.zoom -- the pins where they belong
	if at ~= placed then
		placed = at
		canvas:SetAlpha(at and 1 or 0)
	end
	local nx, ny = w / 2 - cam.cx * cam.zoom, cam.cy * cam.zoom - h / 2
	if at and (nx ~= x or ny ~= y) then
		x, y = nx, ny
		canvas:SetPoint("TOPLEFT", view, "TOPLEFT", nx, ny)
	end
	local changed = v.sockets.world ~= world
	v.sockets.world = world
	for _, a in ipairs(Model.addons) do
		if a.world then
			local key = keys[a.key]
			if not key then key = "addon:" .. a.key; keys[a.key] = key end
			local on = Engine.LayerOn(key) or nil
			if v.layers[key] ~= on then v.layers[key], changed = on, true end
		end
	end
	return changed
end

-- What View tells Game about the map's ground and other addons' pins, each frame from ui/View.lua's step:
-- the Minimap's rim parts (types/view.lua MM.ViewChrome: while the window shows, its arrows and quest rings
-- stand down for our edge arrow and areas; hidden, left as Blizzard has them), the layers Game acts on (ours
-- drawn: Blizzard's tracking of the same off, MinimapTakeover.lua:236; and every addon with world pins,
-- Model.addons, whose layer is on: the gear's Other addons, ui/Menus.lua, on until turned off, as the spike's
-- layers started, AddonPins.lua:113), and the sockets (MM.ViewSockets): frames of ours Game puts other
-- addons' pins on, while the window shows. The world socket: a canvas over the map's layers, under our pins,
-- tile (col, row) of the map shown at (col * zoom, -row * zoom) from its TOPLEFT. Its zoom is where the view rests: the camera's,
-- once it holds still a frame (not through a chase, a flight or the window being sized), so Game re-places
-- each pin once a zoom (a job: its holder see-through until done), not every frame of it. Meanwhile the
-- pins would sit at the old zoom: the canvas is see-through until then. Never scaled (a SetScale costs the
-- client per region under the frame, every frame of the motion: thousands with Questie's pins, spike-bugs
-- P4), nor shown or hidden (the same, per region). The minimap socket: a canvas of its own at the camera
-- every frame, its zoom the camera's, as the spike's host moved and sized with the view (MinimapTakeover.lua:
-- 479-508): its pins (around you: Game sizes their host to the Minimap's view) over ours, under your arrow
-- (MinimapTakeover.lua:325-331).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Camera, Window, Engine = UI.Camera, UI.Window, UI.Engine

local CHROME = { rimArrows = false, questRing = false }
local GAME = { flight = "flight", quests = "quests", pois = "areaPOIs" } -- View.layers' key -> our layer's
local MINI = 17 -- the minimap socket's pins: under your arrow's overlay (18: ui/You.lua), over our pins

local Sockets = {}
UI.Sockets = Sockets

local view = Window.view
local canvas = CreateFrame("Frame", nil, view)
canvas:SetSize(1, 1)
canvas:SetFrameLevel(view:GetFrameLevel() + 10) -- over the names (9), under our pins (11 on), as AddonPins.lua:139
local world = { frame = canvas, inst = 0, zoom = 0 }
local around = CreateFrame("Frame", nil, view)
around:SetSize(1, 1)
around:SetFrameLevel(view:GetFrameLevel() + MINI - 1) -- (its pins a level over it)
local mini = { frame = around, inst = 0, zoom = 0, level = 0 }
Sockets.world, Sockets.minimap = world, mini

local held, placed, x, y = nil, true, nil, nil -- the zoom last frame; as applied
local ax, ay -- the minimap socket's, as applied
local keys = {} -- an addon's key -> its layer's
-- Each frame (ui/View.lua's step): View's chrome, the layers Game acts on and the sockets. True:
-- any changed, a socket's zoom or map with it (set in place: Game re-places its pins on them).
function Sockets.Update(v)
	local window = v.window
	local ours = window.shown
	local chrome = ours and CHROME or nil
	local changed = chrome ~= v.chrome
	v.chrome = chrome
	local layers = v.layers
	for k, layer in pairs(GAME) do
		local on = Engine.LayerOn(layer) or nil
		if layers[k] ~= on then layers[k], changed = on, true end
	end
	if not ours then
		changed = changed or v.sockets.world ~= nil or v.sockets.minimap ~= nil
		v.sockets.world, v.sockets.minimap = nil, nil
		return changed
	end
	local cam, w, h = Camera.cam, Window.Size()
	local zoom, inst = world.zoom, Camera.inst or 0
	if world.zoom == 0 or cam.zoom == held then world.zoom = cam.zoom end
	held = cam.zoom
	local moved = world.zoom ~= zoom or world.inst ~= inst
	world.inst = inst
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
	if nx ~= ax or ny ~= ay then
		ax, ay = nx, ny
		around:SetPoint("TOPLEFT", view, "TOPLEFT", nx, ny)
	end
	local level = window.level + 1 + MINI -- (the view's: the window's + 1)
	changed = changed or moved or v.sockets.world ~= world or v.sockets.minimap ~= mini or mini.level ~= level
		or mini.zoom ~= cam.zoom or mini.inst ~= inst
	mini.inst, mini.zoom, mini.level = inst, cam.zoom, level
	v.sockets.world, v.sockets.minimap = world, mini
	for _, a in ipairs(Model.addons) do
		if a.world then
			local key = keys[a.key]
			if not key then key = "addon:" .. a.key; keys[a.key] = key end
			local on = Engine.LayerOn(key) or nil
			if layers[key] ~= on then layers[key], changed = on, true end
		end
	end
	return changed
end

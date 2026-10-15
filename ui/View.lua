-- View (types/view.lua): what Game acts on in its apply step, published by
-- UI.View(). Refreshed in UI's ui step each frame (so `still` means "the same
-- place as last frame" however often View() is read), which also sends Model
-- the focus (types/focus.lua) when it changes. UI's saved part (types/saved.lua
-- MM.SavedUI: the layer toggles, the minimap mode) comes through a load Command.

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Camera, Window, Engine = UI.Camera, UI.Window, UI.Engine
local Command = ns.Game.Command

local saved = { layers = {}, minimap = "ours" } -- until loaded
local window = { shown = false, big = false, still = false, strata = "LOW", level = 0, homeAlpha = 1 }
local camera = { cx = 0, cy = 0, zoom = 0, w = 0, h = 0 } -- the map's, each frame (telemetry's motion ring, shot stamps)
local view = { v = 1, frame = 0, minimap = "ours", renderer = "ours", inst = 0, window = window,
	layers = {}, sockets = {}, button = true, camera = camera }
local focus = { inst = 0, shown = false, follow = true }

-- For telemetry marks (docs/telemetry.md "State" map, layers): Game stores it, never acts on it.
function view.diag()
	return { map = Window.State(), layers = Engine.State() }
end

function UI.View() return view end

Command({ kind = "load", owner = "UI", spec = { version = 1, defaults = { layers = {}, minimap = "ours" } }, fn = function(s)
	saved = s
	Engine.toggles = s.layers
end })

local function R(v) return math.floor(v * 100 + 0.5) / 100 end

-- The view's scale in UIParent's units, and the window's strata and level: read when it's
-- shown (they change only with the window's own scale and strata, which UI sets).
local scale = 1
Window.frame:HookScript("OnShow", Runtime.Wrap("ui: view shown", function()
	scale = Window.view:GetEffectiveScale() / UIParent:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
	window.strata, window.level = Window.frame:GetFrameStrata(), Window.frame:GetFrameLevel()
end))

Runtime.Step("ui", "ui: view", function()
	local shown = Window.frame:IsShown()
	local place, still = window.place, false
	local left, bottom, w, h
	if shown then left, bottom, w, h = Window.view:GetRect() end
	if left then
		local l, t = R(left * scale), R((bottom + h) * scale)
		w, h = R(w * scale), R(h * scale)
		still = place ~= nil and place.left == l and place.top == t and place.w == w and place.h == h
		if not still then place = { left = l, top = t, w = w, h = h } end
	else
		place = nil
	end
	local layersOn = Engine.LayerOn("blips")
	if shown ~= window.shown or place ~= window.place or saved.minimap ~= view.minimap
		or layersOn ~= (view.layers.blips == true) or (Camera.inst or 0) ~= view.inst then
		view.frame = Runtime.frames
	end
	window.shown, window.place, window.still = shown, place, still
	view.minimap, view.inst = saved.minimap, Camera.inst or 0
	view.layers.blips = layersOn or nil
	local cam = Camera.cam
	camera.cx, camera.cy, camera.zoom, camera.w, camera.h = cam.cx, cam.cy, cam.zoom, Window.Size()
	-- Focus: Model only compares, but send it only on a change (the rect: a new table when it changes).
	local rect = UI.Motion.Rect()
	if focus.inst ~= view.inst or focus.shown ~= shown or focus.follow ~= Camera.follow or focus.zoom ~= cam.zoom
		or focus.rect ~= rect then
		focus = { inst = view.inst, rect = rect, shown = shown, follow = Camera.follow, zoom = cam.zoom }
		Model.Focus(focus)
	end
end)

Command({ kind = "slash", name = "minimap", help = "ours | blizzard: who has the Minimap while the map is shown",
	fn = function(args)
		if args == "ours" or args == "blizzard" then saved.minimap = args end
		print("  minimap: " .. saved.minimap)
	end })

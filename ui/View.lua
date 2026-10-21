-- View (types/view.lua): what Game acts on in its apply step, published by
-- UI.View(). Refreshed in UI's ui step each frame (so `still` means "the same
-- place as last frame" however often View() is read), which also sends Model
-- the focus (types/focus.lua) when it changes. UI's saved part (types/saved.lua
-- MM.SavedUI) comes through a load Command: the window (ui/BigMap.lua), shown,
-- zoom, follow, the map and centre when not following, the layer toggles, the
-- minimap mode, the title's debug line and the minimap button (UI.saved, read where they're used).

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Camera, Window, Engine, BigMap = UI.Camera, UI.Window, UI.Engine, UI.BigMap
local Command = ns.Game.Command

-- Core.lua:19-29: shown, zoom 384, following, no debug line in the title, the button shown.
local DEFAULTS = { layers = {}, minimap = "ours", shown = true, zoom = 384, follow = true, debug = false, button = true }

UI.DefaultZoom = DEFAULTS.zoom -- the zoom the reset button goes back to (ui/Controls.lua)

local saved = {} -- until loaded: the defaults
for k, v in pairs(DEFAULTS) do saved[k] = v end
UI.saved = saved
local window = { shown = false, big = false, still = false, strata = "LOW", level = 0, homeAlpha = 1 }
local camera = { cx = 0, cy = 0, zoom = 0, w = 0, h = 0 } -- the map's, each frame (telemetry's motion ring, shot stamps)
local view = { v = 1, frame = 0, minimap = "ours", inst = 0, window = window,
	layers = {}, sockets = {}, button = true, camera = camera }
local focus = { inst = 0, shown = false, follow = true }
-- The layers Model reads (Focus.off): turned off, its target skips that one (or a quest's area), a seen rare
-- shows under a live vignette (vignettes), a blip near one of those pins isn't skipped (model/Blips.lua).
local TARGETED = { "corpse", "quests", "waypoint", "questAreas", "vignettes", "offers", "flight", "dungeons", "rares" }
local showing -- shown when saved: on the first frame, past login (its first open is then the map's grace, docs/runtime.md)

-- For telemetry marks (docs/telemetry.md "State" map, layers): Game stores it, never acts on it.
function view.diag()
	return { map = Window.State(), layers = Engine.State() }
end

function UI.View() return view end

-- Focus.off's layers changed: any of TARGETED on or off unlike `off` says.
local function OffChanged(off)
	for _, k in ipairs(TARGETED) do
		if Engine.LayerOn(k) == (off ~= nil and off[k] == true) then return true end
	end
	return false
end

local function Off()
	local off
	for _, k in ipairs(TARGETED) do
		if not Engine.LayerOn(k) then
			off = off or {}
			off[k] = true
		end
	end
	return off
end

-- UI's chat line (Core.lua:45-46).
function UI.Print(msg) print("|cffffd100MagicMap|r: " .. msg) end

local OPTIONAL = { window = "table", inst = "number", center = "table", clusterTune = "table" } -- types/saved.lua MM.SavedUI
Command({ kind = "load", owner = "UI", spec = { version = 1, defaults = DEFAULTS, optional = OPTIONAL }, fn = function(s)
	saved = s
	UI.saved = s
	Engine.toggles = s.layers
	for _, key in ipairs({ "corpse", "waypoint", "blips", "unexplored" }) do s.layers[key] = nil end -- (no gear rows now: on)
	s.layers.vignettes = s.layers.rares -- (one row turns both: ui/Menus.lua)
	BigMap.Load(s)
	showing = s.shown
end })

local function R(v) return math.floor(v * 100 + 0.5) / 100 end
local function R3(v) return math.floor(v * 1000 + 0.5) / 1000 end -- saved positions: 3 decimals (types/saved.lua)

-- The view's scale in UIParent's units: read when it's shown (it changes only with the
-- window's own scale, which UI sets).
local scale = 1
Window.frame:HookScript("OnShow", Runtime.Wrap("ui: view shown", function()
	scale = Window.view:GetEffectiveScale() / UIParent:GetEffectiveScale() -- /: never 0 (an effective scale is > 0)
end))

Runtime.Step("ui", "ui: view", function()
	local frame = Window.frame
	if showing then showing = nil; frame:Show() end
	local shown = frame:IsShown()
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
	local strata, level = frame:GetFrameStrata(), frame:GetFrameLevel()
	local layersOn = Engine.LayerOn("blips")
	if shown ~= window.shown or place ~= window.place or still ~= window.still or saved.minimap ~= view.minimap
		or layersOn ~= (view.layers.blips == true) or (Camera.inst or 0) ~= view.inst or BigMap.big ~= window.big
		or BigMap.homeAlpha ~= window.homeAlpha or strata ~= window.strata or level ~= window.level
		or saved.button ~= view.button then
		view.frame = Runtime.frames
	end
	window.shown, window.place, window.still = shown, place, still
	window.big, window.homeAlpha, window.strata, window.level = BigMap.big, BigMap.homeAlpha, strata, level
	view.minimap, view.inst, view.button = saved.minimap, Camera.inst or 0, saved.button
	view.layers.blips = layersOn or nil
	if UI.Sockets.Update(view) then view.frame = Runtime.frames end -- (the world socket, an addon's layer)
	local cam = Camera.cam
	camera.cx, camera.cy, camera.zoom, camera.w, camera.h = cam.cx, cam.cy, cam.zoom, Window.Size()
	-- Saved as it goes (the client writes it at logout): the small window's zoom only, while big the
	-- one it goes back to (MinimapMode.lua:252-260).
	saved.shown, saved.follow = shown, Camera.follow
	local small = BigMap.Small()
	saved.zoom = small and small.zoom or cam.zoom
	if not Camera.follow and Camera.inst then
		local c = saved.center
		if not c then c = {}; saved.center = c end
		saved.inst, c.col, c.row = Camera.inst, R3(cam.cx), R3(cam.cy)
	end
	-- Focus: Model only compares, but send it only on a change (the rect: a new table when it changes;
	-- the zoom, as the rect, where the view rests: held while a chase or flight moves it; off: a new table
	-- when a layer it names turns on or off; moving: till the camera settles and the map's layers show its zoom).
	local rect, moving, off = UI.Motion.Rect(), not Camera.Settled() or Engine.zooming or nil, focus.off
	if OffChanged(off) then off = Off() end
	if focus.inst ~= view.inst or focus.shown ~= shown or focus.follow ~= Camera.follow
		or (focus.zoom ~= cam.zoom and not Camera.moving) or focus.rect ~= rect or focus.moving ~= moving
		or focus.off ~= off then
		focus = { inst = view.inst, rect = rect, shown = shown, follow = Camera.follow, zoom = cam.zoom, off = off,
			moving = moving }
		Model.Focus(focus)
	end
end)

Command({ kind = "slash", name = "minimap", help = "ours | blizzard: who has the Minimap while the map is shown",
	fn = function(args)
		if args == "ours" or args == "blizzard" then saved.minimap = args end
		print("  minimap: " .. saved.minimap)
	end })

-- The minimap button (Game's, View.button) shown or hidden (MinimapButton.lua:49-53).
function UI.Icon()
	saved.button = not saved.button
	UI.Print("minimap button " .. (saved.button and "shown" or "hidden (/mm icon to show)"))
end
Command({ kind = "slash", name = "icon", help = "show or hide the minimap button", fn = UI.Icon })
-- /mm alone or /mm toggle (Core.lua:1700); /mm map <id|name> is the map picker's (M3.4).
Command({ kind = "slash", name = "", help = "our map, or Blizzard's minimap (as toggle)", fn = Window.Toggle })
Command({ kind = "slash", name = "toggle", help = "our map, or Blizzard's minimap", fn = Window.Toggle })

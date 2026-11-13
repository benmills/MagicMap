-- View (types/view.lua): what Game acts on in its apply step, published by
-- UI.View(). Refreshed in UI's ui step each frame, which also sends Model
-- the focus (types/focus.lua) when it changes. UI's saved part (types/saved.lua
-- MM.SavedUI) comes through a load Command: the window (ui/BigMap.lua), shown,
-- zoom, follow, the map and centre when not following, the layer toggles, the
-- what MagicMap replaces (ui/Replace.lua), the minimap mode, the tracker kept on (View.keep: ui/Resources.lua), the title's debug line and the minimap button (UI.saved, read where they're used;
-- the button a switch in Settings > General, ui/Feel.lua). The looks (UI.saved.feel) are checked by Feel.Loaded.

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Camera, Window, Engine, BigMap = UI.Camera, UI.Window, UI.Engine, UI.BigMap
local Command = ns.Game.Command

-- Core.lua:19-29: shown, zoom 384, following, no debug line in the title, the button shown.
local DEFAULTS = { layers = {}, minimap = "ours", shown = true, zoom = 384, follow = true, debug = false, button = true }

-- The small map's default zoom (the reset button, the idle return, every load): with Blizzard's Minimap's zooms over
-- it (obs.minimap.steps), the one chosen on the Default zoom slider ("zoom.default": its index, widest 1; by default
-- the one before its closest the map reaches, following the window's size till one is chosen), no closer than the map
-- goes; else DEFAULTS.zoom. Only Blizzard's zooms: its blips and their tooltips show at each. While a small building's
-- auto-zoom holds the map in (ui/Interiors.lua), that.
local function Reachable(s)
	local n = 0
	for i = 1, #s do
		if s[i] <= UI.Motion.MAX_ZOOM then n = i end
	end
	return n
end
-- Blizzard's zooms the map reaches, how many, the default's index and the chosen one's (nil: not known yet).
function UI.DefaultZoomIndex()
	local mm = Model.minimap
	local s = mm and mm.steps
	if not s or UI.BigMap.big then return nil end
	local n = Reachable(s)
	if n == 0 then return nil end
	local auto = math.max(1, n - 1)
	local t = UI.saved and UI.saved.feel -- (saved, not Feel.Get: the setting's default is this auto)
	local chosen = t and t["zoom.default"] or auto
	if type(chosen) ~= "number" or chosen < 1 then chosen = auto end -- (0: the old Auto)
	return math.min(chosen, n), s, n, auto
end
function UI.DefaultZoom()
	if not UI.BigMap.big and UI.Interiors.Holding() then return UI.Motion.MAX_ZOOM end
	local i, s = UI.DefaultZoomIndex()
	if i then return s[i] end
	return DEFAULTS.zoom
end
-- A zoom as yards across the window.
function UI.Across(zoom)
	local w, h = Window.Size()
	return math.floor(math.min(w, h) / zoom * ns.Atlas.TILE_YARDS / 10 + 0.5) * 10 -- /: never 0 (a zoom > 0)
end
local live -- (the pick once the saved settings are in: a change from it after that is the player's)
UI.Feel.Add("general", "Movement", {
	{ key = "zoom.default", kind = "slider", label = "Default zoom", min = 0, max = 6, step = 1,
		default = function()
			local _, _, _, auto = UI.DefaultZoomIndex()
			return auto or 5
		end,
		range = function()
			local _, _, n = UI.DefaultZoomIndex()
			return 1, n or 6
		end,
		fmt = function(v)
			local _, s, n, auto = UI.DefaultZoomIndex()
			if not s then return tostring(v) end
			local i = math.max(1, math.min(v, n))
			return UI.Across(s[i]) .. " yd" .. (i == auto and " (auto)" or "")
		end,
		apply = function(v)
			local open = UI.Feel.frame and UI.Feel.frame:IsShown() -- (the slider moved: shown at once)
			if live and v ~= live and open then UI.Motion.Reset() end
			live = live and v
		end,
		tip = "The small map's zoom on login, on the reset arrow and when it goes back by itself: one of Blizzard's minimap zooms (its herbs, ores and other blips show at each), shown as the yards across the map, widest to closest. By default the one before the closest." },
})

local saved = {} -- until loaded: the defaults
for k, v in pairs(DEFAULTS) do saved[k] = v end
UI.saved = saved
local window = { shown = false, big = false, strata = "LOW", level = 0, homeAlpha = 1 }
local camera = { cx = 0, cy = 0, zoom = 0, w = 0, h = 0 } -- the map's, each frame (telemetry's motion ring, shot stamps)
local here = { x = 0, y = 0, zoom = 0, w = 0 } -- View.here: you on the view (the overlay spike), or false
local view = { v = 1, frame = 0, minimap = "ours", inst = 0, window = window,
	layers = {}, sockets = {}, button = true, replace = { minimap = false, worldmap = false }, camera = camera }
local focus = { inst = 0, shown = false, follow = true }
-- The layers Model reads (Focus.off): turned off, its target skips that one (or a quest's area), a seen rare
-- shows under a live vignette (vignettes).
local TARGETED = { "corpse", "quests", "waypoint", "questAreas", "vignettes" }
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

-- After a load, the map held at the default zoom (UI.DefaultZoom: Blizzard's zooms' once known, guessed at first and
-- the window's saved size, applied a frame or two late, rescaling the zoom) till it's stood there SETTLED frames,
-- or you zoom (Motion.zooms), or the map's grown, or SETTLE_MAX s pass. settle: { zooms, still, at }, or nil.
local SETTLED, SETTLE_MAX = 30, 10
local settle
local OPTIONAL = { window = "table", bigWindow = "table", inst = "number", center = "table", clusterTune = "table", replace = "table", welcome = "boolean",
	tracked = "table", path = "table", feel = "table", feelPage = "string" } -- types/saved.lua MM.SavedUI
Command({ kind = "load", owner = "UI", spec = { version = 1, defaults = DEFAULTS, optional = OPTIONAL }, fn = function(s, fresh)
	saved = s
	UI.saved = s
	Engine.toggles = s.layers
	for _, key in ipairs({ "corpse", "waypoint", "blips", "unexplored", "borders", "offers" }) do s.layers[key] = nil end -- (no gear rows now: on; borders, offers: gone)
	s.layers.vignettes = s.layers.rares -- (one row turns both: ui/Menus.lua)
	if s.feel then s.feel["zoom.notch"] = nil end -- (3.1.0's notch, any notch of the wheel: gone)
	UI.Feel.Loaded() -- (the saved looks reach what read them at load: the line, the areas)
	live = UI.Feel.Get("zoom.default")
	UI.Replace.Load(s, fresh)
	-- Every login and /reload starts at the default zoom (not the last session's: zoomed off Blizzard's zooms its
	-- blips stay hidden). Its zooms aren't known yet: the default's stand-in till they are.
	s.zoom = DEFAULTS.zoom
	settle = { zooms = UI.Motion.zooms, still = 0, at = GetTime() }
	BigMap.Load(s)
	showing = s.shown and UI.Replace.Get("minimap") -- (without the minimap, a big map is never reopened at login)
end })

-- Start at this zoom instead of the default (the simulator's: a test's saved zoom is where it starts).
function UI.StartAt(zoom)
	settle = nil
	UI.Motion.SetZoom(zoom)
end

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
	local place = window.place
	local left, bottom, w, h
	if shown then left, bottom, w, h = Window.view:GetRect() end
	if left then
		local l, t = R(left * scale), R((bottom + h) * scale)
		w, h = R(w * scale), R(h * scale)
		if not (place and place.left == l and place.top == t and place.w == w and place.h == h) then
			place = { left = l, top = t, w = w, h = h }
		end
	else
		place = nil
	end
	local strata, level = frame:GetFrameStrata(), frame:GetFrameLevel()
	local rmin, rworld = UI.Replace.Get("minimap"), UI.Replace.Get("worldmap")
	-- The Minimap is ours only while MagicMap replaces it (and not swapped back: /mm); else Blizzard's minimap is left
	-- as it is (the window's then always big, where the overlay never shows anyway).
	local mode = rmin and saved.minimap or "blizzard"
	local replace = view.replace
	if shown ~= window.shown or place ~= window.place or mode ~= view.minimap
		or rmin ~= replace.minimap or rworld ~= replace.worldmap
		or (Camera.inst or 0) ~= view.inst or BigMap.big ~= window.big
		or BigMap.homeAlpha ~= window.homeAlpha or strata ~= window.strata or level ~= window.level
		or saved.button ~= view.button then
		view.frame = Runtime.frames
	end
	window.shown, window.place = shown, place
	window.big, window.homeAlpha, window.strata, window.level = BigMap.big, BigMap.homeAlpha, strata, level
	view.minimap, view.inst, view.button = mode, Camera.inst or 0, saved.button
	view.pathing = UI.Path and UI.Path.pathed or false -- (Path to's line laid out this frame or the last; Track's leaves the blips)
	view.keep = UI.Resources.Keep() -- (the tracker Game keeps on: ui/Resources.lua, game/Keep.lua)
	replace.minimap, replace.worldmap = rmin, rworld -- (Game: M is ours only while worldmap; ui/Replace.lua)
	if UI.Sockets.Update(view) then view.frame = Runtime.frames end -- (the world socket, an addon's layer)
	local cam = Camera.cam
	if settle then
		local z = UI.DefaultZoom()
		if UI.Motion.zooms ~= settle.zooms or BigMap.big or GetTime() - settle.at > SETTLE_MAX then
			settle = nil
		elseif math.abs(cam.zoom - z) > 0.01 then
			UI.Motion.SetZoom(z)
			settle.still = 0
		elseif Model.minimap and Model.minimap.steps then
			settle.still = settle.still + 1
			if settle.still >= SETTLED then settle = nil end
		end
	end
	camera.cx, camera.cy, camera.zoom, camera.w, camera.h = cam.cx, cam.cy, cam.zoom, Window.Size()
	local you = Model.you
	if you and you.col and not you.stale and you.inst == Camera.inst and camera.w > 0 then
		here.x, here.y = ns.Atlas.Camera.TileToScreen(cam, camera.w, camera.h, you.col, you.row)
		here.zoom, here.w = cam.zoom, camera.w
		view.here = here
	else
		view.here = false
	end
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
UI.Feel.Add("general", "Blizzard's maps", {
	{ key = "general.button", kind = "toggle", label = "Minimap button", default = true, keep = true,
		get = function() return saved.button == true end, set = function(on) if (saved.button == true) ~= on then UI.Icon() end end,
		tip = "The button on Blizzard's minimap, for when MagicMap is switched off." },
})
-- /mm alone or /mm toggle (Core.lua:1700); /mm map <id|name> is the map picker's (M3.4).
Command({ kind = "slash", name = "", help = "our map, or Blizzard's minimap (as toggle)", fn = Window.Toggle })
Command({ kind = "slash", name = "toggle", help = "our map, or Blizzard's minimap", fn = Window.Toggle })

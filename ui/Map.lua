-- The map window: a movable, resizable frame drawing your continent from
-- Atlas (sea, tiles, borders, labels, flight points) around you.
--
-- Each layer lays its regions out on a canvas (a 1x1 frame; tile (col, row)
-- at (col * zoom, -row * zoom) on it) at one zoom, over the view and a margin,
-- in a Runtime.Job. Panning moves the canvas; zooming scales it until a fresh
-- layout, built on the layer's other (hidden) canvas, swaps in.

local ADDON, ns = ...
local UI = ns.UI or {}; ns.UI = UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera = Atlas.Camera

local MIN_ZOOM, MAX_ZOOM = 4, 1024 -- px per tile
local START_ZOOM = 96
local MARGIN = 0.5 -- share of the view laid out past each side, so a pan finds it drawn
local JOB_MS = 4 -- a layout's budget a frame
local RETRY_S, RETRY_MAX_S = 0.5, 30 -- a failed layout is tried again after this, doubling each failure in a row

local Map = { layers = {}, cam = { cx = 32, cy = 32, zoom = START_ZOOM }, follow = true }
UI.Map = Map

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "MagicMapAtlasMap", UIParent)
frame:SetSize(720, 520)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:SetResizeBounds(240, 180)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:Hide()
local opened -- the first open builds Atlas's indexes: its frames are budgeted apart (docs/runtime.md)
frame:SetScript("OnShow", Runtime.Wrap("map: shown", function()
	if not opened then opened = true; Runtime.Grace("map", 2) end
	Runtime.Trace("map", "shown")
end))
frame:SetScript("OnHide", Runtime.Wrap("map: hidden", function()
	Runtime.Trace("map", "hidden")
	Runtime.SetState("closed")
end))
Runtime.SetState("closed") -- frames by map state (docs/runtime.md); the draw step sets the shown ones
Map.frame = frame

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.04, 0.04, 0.05, 0.96)

local bar = CreateFrame("Frame", nil, frame)
bar:SetPoint("TOPLEFT")
bar:SetPoint("TOPRIGHT")
bar:SetHeight(22)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:SetScript("OnDragStart", Runtime.Wrap("map: move", function() frame:StartMoving() end))
bar:SetScript("OnDragStop", Runtime.Wrap("map: moved", function() frame:StopMovingOrSizing() end))

local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("LEFT", 8, 0)

local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
close:SetPoint("RIGHT", 2, 0)
close:SetSize(24, 24)

local view = CreateFrame("Frame", nil, frame)
view:SetPoint("TOPLEFT", 4, -22)
view:SetPoint("BOTTOMRIGHT", -4, 4)
view:SetClipsChildren(true)
view:EnableMouse(true)
view:EnableMouseWheel(true)
Map.view = view

local grip = CreateFrame("Button", nil, frame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(view:GetFrameLevel() + 20)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", Runtime.Wrap("map: resize", function() frame:StartSizing("BOTTOMRIGHT") end))
grip:SetScript("OnMouseUp", Runtime.Wrap("map: resized", function() frame:StopMovingOrSizing() end))

-- Your arrow, above every layer.
local overlay = CreateFrame("Frame", nil, view)
overlay:SetAllPoints()
overlay:SetFrameLevel(view:GetFrameLevel() + 10)
local arrow = overlay:CreateTexture(nil, "OVERLAY")
arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
arrow:SetSize(28, 28)
arrow:SetSnapToPixelGrid(false)
arrow:SetTexelSnappingBias(0)
arrow:Hide()

function Map.Size()
	return view:GetWidth(), view:GetHeight()
end

---------------------------------------------------------------------------
-- Layers, canvases and pools
---------------------------------------------------------------------------

-- build(canvas, inst, zoom, c0, r0, c1, r1): lay the layer out on canvas (in
-- canvas units, tile * zoom) over that tile rect, calling Runtime.Yield() now and then.
-- rev (optional): a function whose value changing lays it out again (Model.Known's rev).
-- Each layer can be toggled (Map.toggles[name], UI's saved layers: a missing key is on).
function Map.NewLayer(name, level, build, rev)
	local f = CreateFrame("Frame", nil, view)
	f:SetAllPoints()
	f:SetFrameLevel(view:GetFrameLevel() + level)
	local layer = { name = name, frame = f, build = build, rev = rev, canvases = {} }
	for i = 1, 2 do
		local c = CreateFrame("Frame", nil, f)
		c:SetSize(1, 1)
		c:Hide()
		c.pools = {}
		layer.canvases[i] = c
	end
	Map.layers[#Map.layers + 1] = layer
	return layer
end

-- The next region of a kind on the canvas being laid out: make(canvas) makes one.
-- what: "tex" | "line" | "font", for the counts.
function Map.Get(canvas, kind, what, make)
	local p = canvas.pools[kind]
	if not p then
		p = { n = 0, what = what, make = make }
		canvas.pools[kind] = p
	end
	p.n = p.n + 1
	local o = p[p.n]
	if not o then
		o = make(canvas)
		p[p.n] = o
	end
	o:Show()
	return o
end

-- Give back the last Get of a kind (it didn't fit).
function Map.Unget(canvas, kind)
	local p = canvas.pools[kind]
	p[p.n]:Hide()
	p.n = p.n - 1
end

-- Tile-space position on a canvas laid out at zoom, rounded so neighbours share edges.
function Map.Px(v, zoom)
	return math.floor(v * zoom + 0.5)
end

-- The tile rect to lay out: the view and a margin.
local function Region()
	local w, h = Map.Size()
	local cam = Map.cam
	local mw, mh = w * (0.5 + MARGIN) / cam.zoom, h * (0.5 + MARGIN) / cam.zoom
	return cam.cx - mw, cam.cy - mh, cam.cx + mw, cam.cy + mh
end

local function Covers(c, cam, w, h)
	local r = c.region
	local c0, r0 = Camera.ScreenToTile(cam, w, h, 0, 0)
	local c1, r1 = Camera.ScreenToTile(cam, w, h, w, h)
	return c0 >= r[1] and r0 >= r[2] and c1 <= r[3] and r1 <= r[4]
end

local Place

local function R2(v) return math.floor(v * 100 + 0.5) / 100 end -- for traces

-- A layout job that errored or was cancelled (Runtime reported it): the layer lays out
-- again after a backoff, keeping its last good canvas meanwhile.
local function Failed(layer)
	layer.busy = false
	layer.backoff = math.min((layer.backoff or RETRY_S / 2) * 2, RETRY_MAX_S)
	layer.retryAt = GetTime() + layer.backoff
	Runtime.Trace("layout", { e = "failed", layer = layer.name, retry = layer.backoff })
end

local function Rebuild(layer)
	local back = layer.canvases[layer.front == layer.canvases[1] and 2 or 1]
	local inst, zoom = Map.inst, Map.cam.zoom
	local c0, r0, c1, r1 = Region()
	back.rev = layer.rev and layer.rev()
	layer.busy = true -- until the job ends: its last stretch clears it; a failure, the draw step (Failed)
	Runtime.Trace("layout", { e = "start", layer = layer.name, inst = inst, zoom = R2(zoom),
		c0 = R2(c0), r0 = R2(r0), c1 = R2(c1), r1 = R2(r1) })
	layer.job = Runtime.Job("map: " .. layer.name, function()
		local t0, used = debugprofilestop(), 0
		for _, p in pairs(back.pools) do p.n = 0 end
		layer.build(back, inst, zoom, c0, r0, c1, r1)
		for _, p in pairs(back.pools) do -- the back canvas is hidden: this may yield
			for i = p.n + 1, #p do
				p[i]:Hide()
				Runtime.Yield()
			end
			used = used + p.n
		end
		Runtime.Trace("layout", { e = "end", layer = layer.name, ms = R2(debugprofilestop() - t0), regions = used })
		back.inst, back.zoom, back.region, back.scale, back.x, back.y = inst, zoom, { c0, r0, c1, r1 }, nil, nil, nil
		layer.busy, layer.retryAt, layer.backoff = false, nil, nil
		if inst ~= Map.inst then return end -- moved to another map meanwhile
		if layer.front then layer.front:Hide() end
		layer.front = back
		-- Placed before it's shown: jobs run after the frame's steps, so waiting for the
		-- next draw would show it a frame at wherever it last was (a jump while panning).
		Place(layer, Map.cam, Map.Size())
		back:Show()
		Runtime.Trace("swap", { layer = layer.name, x = R2(back.x), y = R2(back.y), scale = R2(back.scale) })
	end, JOB_MS)
end

-- A canvas laid out at its zoom, shown at the camera's: scaled, and moved so tile (0, 0) is where it belongs.
function Place(layer, cam, w, h)
	local c = layer.front
	local s = cam.zoom / c.zoom
	local x, y = (w / 2 - cam.cx * cam.zoom) / s, -(h / 2 - cam.cy * cam.zoom) / s
	if c.scale ~= s then
		c.scale = s
		c:SetScale(s)
	end
	if c.x ~= x or c.y ~= y then
		c.x, c.y = x, y
		c:SetPoint("TOPLEFT", layer.frame, "TOPLEFT", x, y)
	end
end

---------------------------------------------------------------------------
-- Input: wheel zooms about the cursor, drag pans, right click follows you again
---------------------------------------------------------------------------

local drag -- { x, y, cx, cy, moved } while the left button is down

local camFrame -- the frame of the last "cam" trace: at most one a frame
local function Cam(e)
	if camFrame == Runtime.frames then return end
	camFrame = Runtime.frames
	local cam = Map.cam
	Runtime.Trace("cam", { e = e, cx = R2(cam.cx), cy = R2(cam.cy), zoom = R2(cam.zoom) })
end

local function Cursor()
	local x, y = GetCursorPosition()
	local s = view:GetEffectiveScale()
	return x / s - view:GetLeft(), view:GetTop() - y / s
end

view:SetScript("OnMouseWheel", Runtime.Wrap("map: wheel", function(_, delta)
	local cam = Map.cam
	local zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, cam.zoom * 2 ^ (delta / 4)))
	local w, h = Map.Size()
	local x, y = Cursor()
	if Map.follow then x, y = w / 2, h / 2 end -- following: about you
	Map.cam = Camera.ZoomAt(cam, w, h, x, y, zoom)
	Cam("wheel")
end))

view:SetScript("OnMouseDown", Runtime.Wrap("map: press", function(_, button)
	if button == "LeftButton" then
		local x, y = Cursor()
		drag = { x = x, y = y, cx = Map.cam.cx, cy = Map.cam.cy }
	elseif button == "RightButton" and not Map.follow then
		Map.follow = true
		Cam("follow on")
	end
end))

view:SetScript("OnMouseUp", Runtime.Wrap("map: release", function()
	if drag and drag.moved then Cam("drag end") end
	drag = nil
end))

Runtime.Step("input", "map: drag", function()
	if not drag then return end
	local x, y = Cursor()
	if Map.follow and (x - drag.x) ^ 2 + (y - drag.y) ^ 2 < 9 then return end -- a click, not yet a drag
	Map.follow = false
	local cam = Map.cam
	cam.cx, cam.cy = drag.cx - (x - drag.x) / cam.zoom, drag.cy - (y - drag.y) / cam.zoom -- in place: no table a frame
	if not drag.moved and (x ~= drag.x or y ~= drag.y) then drag.moved = true; Cam("drag start") end -- follow's off now
end, { shownOnly = frame })

---------------------------------------------------------------------------
-- Each frame: camera, layouts, canvases, your arrow
---------------------------------------------------------------------------

local function You()
	local you = ns.Model.you
	return you and you.inst and you
end

local function SetInst(inst)
	Map.inst = inst
	for _, layer in ipairs(Map.layers) do
		if layer.front then layer.front:Hide() end
		layer.front = nil
	end
	local continent = Atlas.Continent(inst)
	local name = continent and Atlas.UiMap(continent).name
	if not name then
		for _, m in ipairs(Atlas.Maps()) do
			if m.inst == inst then name = m.name end
		end
	end
	title:SetText(name or ("Map " .. inst))
end

Runtime.Step("ui", "map: draw", function()
	local you = You()
	local inst = you and you.inst or Map.inst or 0
	if inst ~= Map.inst then SetInst(inst) end
	local cam = Map.cam
	if Map.follow and you and you.col then
		cam.cx, cam.cy = you.col, you.row
	end
	local w, h = Map.Size()
	if w <= 0 or h <= 0 then return end
	local zooming = false -- a shown layer still scaled from another zoom: the wheel's not laid out yet
	for _, layer in ipairs(Map.layers) do
		local c, on = layer.front, Map.LayerOn(layer.name)
		if layer.on ~= on then layer.on = on; layer.frame:SetShown(on) end
		if layer.busy and layer.job.done then Failed(layer) end -- done but still busy: it didn't finish
		if on and not layer.busy and (not layer.retryAt or GetTime() >= layer.retryAt)
			and (not c or c.inst ~= inst or c.zoom ~= cam.zoom or not Covers(c, cam, w, h)
				or (layer.rev and c.rev ~= layer.rev())) then
			Rebuild(layer)
		end
		if layer.front then
			Place(layer, cam, w, h)
			zooming = zooming or (on and layer.front.zoom ~= cam.zoom)
		end
	end
	Runtime.SetState(drag and drag.moved and "drag" or zooming and "zoom" or "small") -- "big" comes with the grow (M1.7)
	-- The arrow: only what changed is applied (an idle frame makes no widget calls for it).
	if you and you.col then
		local x, y = Camera.TileToScreen(cam, w, h, you.col, you.row)
		local facing, stale = you.facing or 0, you.stale and true or false
		if arrow.x ~= x or arrow.y ~= y then
			arrow.x, arrow.y = x, y
			arrow:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
		end
		if arrow.facing ~= facing then arrow.facing = facing; arrow:SetRotation(facing) end
		if arrow.stale ~= stale then
			arrow.stale = stale
			arrow:SetDesaturated(stale) -- last known: greyed
			arrow:SetAlpha(stale and 0.5 or 1)
		end
		if not arrow.shown then arrow.shown = true; arrow:Show() end
	elseif arrow.shown then
		arrow.shown = false
		arrow:Hide()
	end
end, { shownOnly = frame })

Map.toggles = {} -- UI's saved layers (ui/View.lua loads them)
function Map.LayerOn(name) return Map.toggles[name] ~= false end

function Map.Toggle()
	if frame:IsShown() then
		frame:Hide()
	else
		if not Map.follow then Map.follow = true; Cam("follow on") end
		frame:Show()
	end
end

-- For telemetry: the camera, and each layer's shown layout.
function Map.State()
	local cam, w, h = Map.cam, Map.Size()
	local layers = {}
	for i, l in ipairs(Map.layers) do
		local c = l.front
		local r = c and c.region
		layers[i] = { name = l.name, busy = l.busy, zoom = c and R2(c.zoom), region = r and { R2(r[1]), R2(r[2]), R2(r[3]), R2(r[4]) } }
	end
	return { shown = frame:IsShown(), inst = Map.inst, cx = R2(cam.cx), cy = R2(cam.cy), zoom = R2(cam.zoom),
		follow = Map.follow, w = R2(w), h = R2(h) }, layers
end

-- Live regions on the shown canvases, and all made (pooled), by kind.
function Map.Stats()
	local live, made = { tex = 0, line = 0, font = 0 }, { tex = 0, line = 0, font = 0 }
	for _, layer in ipairs(Map.layers) do
		for _, c in ipairs(layer.canvases) do
			for _, p in pairs(c.pools) do
				made[p.what] = made[p.what] + #p
				if c == layer.front then live[p.what] = live[p.what] + p.n end
			end
		end
	end
	return live, made
end

local Command = ns.Game.Command
Command({ kind = "slash", name = "map", help = "show or hide the map window", fn = Map.Toggle })
Command({ kind = "slash", name = "layer", help = "<name>: show or hide a map layer; alone, list them", fn = function(name)
	local known = false
	for _, l in ipairs(Map.layers) do known = known or l.name == name end
	if known then Map.toggles[name] = not Map.LayerOn(name) end
	for _, l in ipairs(Map.layers) do print(string.format("  %s %s", l.name, Map.LayerOn(l.name) and "on" or "off")) end
end })
Command({ kind = "slash", name = "mapstats", help = "the map's live textures, lines and font strings", fn = function()
	local live, made = Map.Stats()
	local cam = Map.cam
	print(string.format("MagicMapAtlas map: inst %s, zoom %.1f px/tile; live %d textures, %d lines, %d font strings"
		.. " (made %d, %d, %d)", tostring(Map.inst), cam.zoom, live.tex, live.line, live.font, made.tex, made.line,
		made.font))
end })

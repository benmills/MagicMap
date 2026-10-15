-- The map's engine: layers drawn on canvases. Engine.Layer(name, level, build, rev)
-- adds one (ui/Tiles.lua, ...). Each lays its regions out on a canvas (a 1x1 frame;
-- tile (col, row) at (col * zoom, -row * zoom) on it) at one zoom, over the view and
-- a margin, in a Runtime.Job, taking them from the canvas's pools (Engine.Get).
-- Panning moves the canvas; zooming scales it until a fresh layout, built on the
-- layer's other (hidden) canvas, swaps in. Window's draw step calls Engine.Draw.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local MARGIN = 0.5 -- share of the view laid out past each side, so a pan finds it drawn
local JOB_MS = 4 -- a layout's budget a frame
local RETRY_S, RETRY_MAX_S = 0.5, 30 -- a failed layout is tried again after this, doubling each failure in a row

local Engine = { layers = {}, toggles = {} } -- toggles: UI's saved layers (ui/View.lua loads them)
UI.Engine = Engine

---------------------------------------------------------------------------
-- Layers, canvases and pools
---------------------------------------------------------------------------

-- build(canvas, inst, zoom, c0, r0, c1, r1): lay the layer out on canvas (in
-- canvas units, tile * zoom) over that tile rect, calling Runtime.Yield() now and then.
-- rev (optional): a function whose value changing lays it out again (Model.Known's rev).
-- Each layer can be toggled (Engine.toggles[name], UI's saved layers: a missing key is on).
function Engine.Layer(name, level, build, rev)
	local view = Window.view
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
	Engine.layers[#Engine.layers + 1] = layer
	return layer
end

-- The next region of a kind on the canvas being laid out: make(canvas) makes one.
-- what: "tex" | "line" | "font", for the counts.
function Engine.Get(canvas, kind, what, make)
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
function Engine.Unget(canvas, kind)
	local p = canvas.pools[kind]
	p[p.n]:Hide()
	p.n = p.n - 1
end

-- Tile-space position on a canvas laid out at zoom, rounded so neighbours share edges.
function Engine.Px(v, zoom)
	return math.floor(v * zoom + 0.5)
end

function Engine.LayerOn(name) return Engine.toggles[name] ~= false end

-- The tile rect to lay out: the view and a margin.
local function Region()
	local w, h = Window.Size()
	local cam = Camera.cam
	local mw, mh = w * (0.5 + MARGIN) / cam.zoom, h * (0.5 + MARGIN) / cam.zoom
	return cam.cx - mw, cam.cy - mh, cam.cx + mw, cam.cy + mh
end

local function Covers(c, cam, w, h)
	local r = c.region
	local c0, r0 = Maths.ScreenToTile(cam, w, h, 0, 0)
	local c1, r1 = Maths.ScreenToTile(cam, w, h, w, h)
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
	local inst, zoom = Camera.inst, Camera.cam.zoom
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
		if inst ~= Camera.inst then return end -- moved to another map meanwhile
		if layer.front then layer.front:Hide() end
		layer.front = back
		-- Placed before it's shown: jobs run after the frame's steps, so waiting for the
		-- next draw would show it a frame at wherever it last was (a jump while panning).
		Place(layer, Camera.cam, Window.Size())
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
-- Each frame (Window's draw step)
---------------------------------------------------------------------------

-- Another map shown: no layer keeps the last one's canvas.
function Engine.Clear()
	for _, layer in ipairs(Engine.layers) do
		if layer.front then layer.front:Hide() end
		layer.front = nil
	end
end

-- Each layer laid out again where it's stale, and placed at the camera. True while
-- zooming: a shown layer still scaled from another zoom (the wheel's not laid out yet).
function Engine.Draw(inst, cam, w, h)
	local zooming = false
	for _, layer in ipairs(Engine.layers) do
		local c, on = layer.front, Engine.LayerOn(layer.name)
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
	return zooming
end

-- For telemetry: each layer's shown layout (View.diag's layers).
function Engine.State()
	local layers = {}
	for i, l in ipairs(Engine.layers) do
		local c = l.front
		local r = c and c.region
		layers[i] = { name = l.name, busy = l.busy, zoom = c and R2(c.zoom), region = r and { R2(r[1]), R2(r[2]), R2(r[3]), R2(r[4]) } }
	end
	return layers
end

-- Live regions on the shown canvases, and all made (pooled), by kind.
function Engine.Stats()
	local live, made = { tex = 0, line = 0, font = 0 }, { tex = 0, line = 0, font = 0 }
	for _, layer in ipairs(Engine.layers) do
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
Command({ kind = "slash", name = "layer", help = "<name>: show or hide a map layer; alone, list them", fn = function(name)
	local known = false
	for _, l in ipairs(Engine.layers) do known = known or l.name == name end
	if known then Engine.toggles[name] = not Engine.LayerOn(name) end
	for _, l in ipairs(Engine.layers) do print(string.format("  %s %s", l.name, Engine.LayerOn(l.name) and "on" or "off")) end
end })
Command({ kind = "slash", name = "mapstats", help = "the map's live textures, lines and font strings", fn = function()
	local live, made = Engine.Stats()
	local cam = Camera.cam
	print(string.format("MagicMapAtlas map: inst %s, zoom %.1f px/tile; live %d textures, %d lines, %d font strings"
		.. " (made %d, %d, %d)", tostring(Camera.inst), cam.zoom, live.tex, live.line, live.font, made.tex, made.line,
		made.font))
end })

-- The map's engine: layers drawn on canvases. Engine.Layer(name, level, build, rev, zoom) adds one
-- (ui/Tiles.lua, ...). A layer has two canvases (1x1 frames, both always shown): the front at alpha 1,
-- the back at alpha 0. A layout, a Runtime.Job (one at a time: a layer missing from the view first,
-- then by level), lays the layer out on its back canvas at one zoom, over the view and a margin (more
-- ahead of the camera's motion), into the canvas's own regions where they stand (Engine.Get), parks
-- what it didn't use (SetParent to a hidden frame), then swaps the two by alpha. Tile (col, row) is at
-- ((col - ox) * zoom, -(row - oy) * zoom) on a canvas: (ox, oy), the origin, a whole tile near the
-- view shared by every layer, so no offset grows past a few thousand px. Panning moves the canvases;
-- until the zoom settles (or drifts out of [0.7, 1.4] of a layout's), a layer shows as its zoom says:
-- "scale" (SetScale its canvas: tiles), "move" (what it placed with Engine.At moved to the camera's
-- zoom, so fonts and icons keep their size: labels, pins), "hold" (scaled and dimmed the further it is
-- from its layout's zoom, laid out where the zoom is headed, crossfaded in as it lands: borders,
-- Layers.lua:16-24, 158-170, 1824-1836). The window hidden or a layer turned off, its canvases are
-- emptied. Why, from the client's prices: docs/runtime.md "The map's engine". Window's draw step
-- calls Engine.Draw.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local MARGIN = 0.5 -- of the view laid out past each side at rest, so a pan finds it drawn
local LEAD, TRAIL, FAST = 0.75, 0.25, 0.5 -- moving FAST views a second or more: the margin ahead, behind
local AHEAD_S = 0.3 -- moving: laid out again before the view this far ahead leaves the layout
local GOAL_S = 0.1 -- s a zoom's goal holds before a held layer lays out there (wheel ticks keep moving it)
local JOB_MS, MISSING_MS = 4, 5 -- a layout's budget a frame; a layer the view lacks (the frame stays under 8 ms)
local BAND_LO, BAND_HI = 0.7, 1.4 -- the camera's zoom over a layout's: outside, laid out again before it settles
local FADE_S = 0.12 -- a held layer's crossfade to a layout at another zoom (Layers.lua:1697 CROSSFADE)
local SAME_ZOOM = 0.02 -- log: a held layer's layouts this close in zoom cut straight over (Layers.lua:1698)
local LN2 = math.log(2)
-- A layout reaching further than this from the origin (px at its zoom) moves it: offsets stay under
-- 4096 px, moved 1.4x included (the tear's suspect: docs/v1-plan.md §2).
local ORIGIN_PX = 2800
local PAD = 200 -- px past the view a moved label or pin may show from (its anchor: its centre)
local RETRY_S, RETRY_MAX_S = 0.5, 30 -- a failed layout is tried again after this, doubling each failure in a row

local Engine = { layers = {}, toggles = {} } -- toggles: UI's saved layers (ui/View.lua loads them)
UI.Engine = Engine

local park = CreateFrame("Frame", nil, Window.view) -- regions no layout uses: off every canvas
park:Hide()

---------------------------------------------------------------------------
-- Layers, canvases and pools
---------------------------------------------------------------------------

-- build(canvas, inst, zoom, c0, r0, c1, r1): lay the layer out on canvas over that tile rect, tile
-- (col, row) at ((col - canvas.ox) * zoom, -(row - canvas.oy) * zoom) from its TOPLEFT, calling
-- Runtime.Yield() now and then. rev (optional): a function whose value changing lays it out again
-- (Model.Known's rev). zoom: "scale" (default), "move" or "hold" (the top). Each layer can be toggled
-- (Engine.toggles[name], UI's saved layers: a missing key is on). build returns true when it has
-- nothing to draw at that zoom anywhere (none known, or not from this zoom): no layout again on a pan.
function Engine.Layer(name, level, build, rev, zoom)
	local view = Window.view
	local f = CreateFrame("Frame", nil, view)
	f:SetAllPoints()
	f:SetFrameLevel(view:GetFrameLevel() + level)
	local layer = { name = name, level = level, frame = f, build = build, rev = rev, zoom = zoom or "scale",
		canvases = {}, fading = {} } -- fading: its crossfade (layer.fade while one runs)
	for i = 1, 2 do
		local c = CreateFrame("Frame", nil, f)
		c:SetSize(1, 1)
		c:SetAlpha(0)
		c.pools, c.alpha, c.made, c.scale = {}, 0, 0, 1
		layer.canvases[i] = c
	end
	local i = #Engine.layers + 1 -- by level: the order layouts go in
	while i > 1 and Engine.layers[i - 1].level > level do i = i - 1 end
	table.insert(Engine.layers, i, layer)
	return layer
end

-- A region onto a frame, with its mask (a tile's coast fade: it moves with it).
local function Reparent(o, to)
	o:SetParent(to)
	if o.mask then o.mask:SetParent(to) end
end

-- The next region of a kind on the canvas being laid out: make(canvas) makes one. what: "tex" |
-- "line" | "font", for the counts. Pooled per canvas: 1..out on it, the rest parked.
function Engine.Get(canvas, kind, what, make)
	local p = canvas.pools[kind]
	if not p then
		p = { n = 0, out = 0, what = what }
		canvas.pools[kind] = p
	end
	local n = p.n + 1
	p.n = n
	local o = p[n]
	if not o then
		o = make(canvas)
		p[n] = o
		canvas.made = canvas.made + 1
	elseif n > p.out then
		Reparent(o, canvas)
	end
	if n > p.out then p.out = n end
	return o
end

-- Give back the last Get of a kind (it didn't fit): parked at the layout's end, unless used again.
function Engine.Unget(canvas, kind)
	local p = canvas.pools[kind]
	p.n = p.n - 1
end

-- Place o (a "move" layer's region) at tile (col, row), dx, dy px right and down (default 0); while the
-- zoom moves, Engine moves it there at the camera's zoom.
function Engine.At(c, o, point, col, row, dx, dy)
	dx, dy = dx or 0, dy or 0
	o.apoint, o.acol, o.arow, o.adx, o.ady, o.az = point, col, row, dx, dy, c.zoom
	o:SetPoint(point, c, "TOPLEFT", (col - c.ox) * c.zoom + dx, -((row - c.oy) * c.zoom + dy))
end

-- Tile-space position on a canvas laid out at zoom (v from its origin), rounded so neighbours share edges.
function Engine.Px(v, zoom)
	return math.floor(v * zoom + 0.5)
end

function Engine.LayerOn(name) return Engine.toggles[name] ~= false end

local function Alpha(c, a)
	if c.alpha ~= a then
		c.alpha = a
		c:SetAlpha(a)
	end
end

-- The margins (before, after) on an axis moving v tiles a second, the view size px long.
local function Margins(v, zoom, size)
	local k = math.min(1, math.abs(v) * zoom / size / FAST) -- /: never 0 (size: Draw's w, h > 0)
	local ahead, behind = MARGIN + (LEAD - MARGIN) * k, MARGIN - (MARGIN - TRAIL) * k
	if v < 0 then return ahead, behind end
	return behind, ahead
end

-- The tile rect to lay out: the view and its margins.
local function Region(cam, w, h)
	local z = cam.zoom
	local l, r = Margins(Camera.vx, z, w)
	local t, b = Margins(Camera.vy, z, h)
	local tw, th = w / z, h / z -- /: never 0 (zoom >= MIN_ZOOM)
	return cam.cx - tw * (0.5 + l), cam.cy - th * (0.5 + t), cam.cx + tw * (0.5 + r), cam.cy + th * (0.5 + b)
end

-- The origin every layout shares: kept while a layout's region stays within ORIGIN_PX of it, else the
-- whole tile nearest the view's centre (the layers then lay out again onto it, one by one).
local function Origin(cam, c0, r0, c1, r1)
	local z, ox, oy = cam.zoom, Engine.ox, Engine.oy
	if not ox or math.max(ox - c0, c1 - ox) * z > ORIGIN_PX or math.max(oy - r0, r1 - oy) * z > ORIGIN_PX then
		ox, oy = math.floor(cam.cx + 0.5), math.floor(cam.cy + 0.5)
		Engine.ox, Engine.oy = ox, oy
	end
	return ox, oy
end

local function Covers(c, cam, w, h)
	local r = c.region
	local c0, r0 = Maths.ScreenToTile(cam, w, h, 0, 0)
	local c1, r1 = Maths.ScreenToTile(cam, w, h, w, h)
	return c0 >= r[1] and r0 >= r[2] and c1 <= r[3] and r1 <= r[4]
end

local function R2(v) return math.floor(v * 100 + 0.5) / 100 end -- for traces

local function Near(x, y, w, h) return x > -PAD and x < w + PAD and y > -PAD and y < h + PAD end

-- A "move" canvas's regions to the camera's zoom: each that shows there, or did where it was (o.az, its
-- zoom); the rest stay put out of view until they would show (c.late), or the next layout.
local function Move(c, cam, w, h)
	local z, ox, oy = cam.zoom, c.ox, c.oy
	local x0, y0 = w / 2 + (ox - cam.cx) * z, h / 2 + (oy - cam.cy) * z -- the origin on the view
	local late = false
	for _, p in pairs(c.pools) do
		for i = 1, p.n do
			local o = p[i]
			if o.az ~= z then
				local col, row, dx, dy = o.acol - ox, o.arow - oy, o.adx, o.ady
				if Near(x0 + col * z + dx, y0 + row * z + dy, w, h) or Near(x0 + col * o.az + dx, y0 + row * o.az + dy, w, h) then
					o.az = z
					o:SetPoint(o.apoint, c, "TOPLEFT", col * z + dx, -(row * z + dy))
				else
					late = true
				end
			end
		end
	end
	c.moved, c.late = z, late
end

-- A canvas at the camera: its origin where the camera shows that tile, scaled ("scale", "hold") or
-- its regions moved ("move"). Its scale.
local function Put(layer, c, cam, w, h)
	local z = cam.zoom
	local s = layer.zoom == "move" and 1 or z / c.zoom -- /: never 0 (a canvas's zoom: the camera's at layout)
	if layer.zoom == "move" and (c.moved ~= z or c.late) then Move(c, cam, w, h) end
	local x, y = (w / 2 + (c.ox - cam.cx) * z) / s, -(h / 2 + (c.oy - cam.cy) * z) / s -- /: never 0 (s: two zooms > 0, or 1)
	if c.scale ~= s then
		c.scale = s
		c:SetScale(s)
	end
	if c.x ~= x or c.y ~= y then
		c.x, c.y = x, y
		c:SetPoint("TOPLEFT", layer.frame, "TOPLEFT", x, y)
	end
	return s
end

-- A layer's front canvas at the camera, at alpha 1; a held one's dimmed the further its scale is from 1
-- (Layers.lua:163-167), or crossfading in over the one it replaced (Layers.lua:1967-1972).
local function Place(layer, cam, w, h)
	local c, f = layer.front, layer.fade
	local s = Put(layer, c, cam, w, h)
	if f then
		Put(layer, f.from, cam, w, h)
		local p = math.min(1, (GetTime() - f.t) / FADE_S)
		Alpha(c, p)
		Alpha(f.from, f.a * (1 - p))
		if p >= 1 then layer.fade = nil end
	elseif layer.zoom == "hold" then
		local off = math.abs(math.log(s) / LN2)
		Alpha(c, math.max(0.25, math.min(1, 1.6 - 0.6 * off)))
	else
		Alpha(c, 1)
	end
end

-- A layout job that errored or was cancelled (Runtime reported it): the layer lays out
-- again after a backoff, keeping its last good canvas meanwhile.
local function Failed(layer)
	layer.busy = false
	layer.backoff = math.min((layer.backoff or RETRY_S / 2) * 2, RETRY_MAX_S)
	layer.retryAt = GetTime() + layer.backoff
	Runtime.Trace("layout", { e = "failed", layer = layer.name, retry = layer.backoff })
end

-- The back canvas, laid out, to the front: placed, then the alphas swapped (no region is shown or
-- hidden). Over the old at once (a pan's two agree where they overlap); a held layer's at another
-- zoom crossfades from the old one's alpha (Layers.lua:1820-1836).
local function Swap(layer, back, live, parked)
	local t = debugprofilestop()
	local old, f = layer.front, layer.fade
	if f then Alpha(f.from, 0) end
	layer.front, layer.fade = back, nil
	if old and old.alpha > 0 and layer.zoom == "hold" and math.abs(math.log(old.zoom / back.zoom)) >= SAME_ZOOM then -- /: never 0 (zooms > 0)
		f = layer.fading
		f.from, f.a, f.t = old, old.alpha, GetTime()
		layer.fade = f
	end
	Place(layer, Camera.cam, Window.Size())
	if old and not layer.fade then Alpha(old, 0) end
	Runtime.Trace("swap", { layer = layer.name, ms = R2(debugprofilestop() - t), live = live, parked = parked,
		x = back.x and R2(back.x), y = back.y and R2(back.y), scale = back.scale and R2(back.scale) })
end

-- Lay layer out for the camera at (a "hold" layer: where it's headed), on its back canvas.
local function Rebuild(layer, inst, at, w, h, budget)
	local back = layer.canvases[layer.front == layer.canvases[1] and 2 or 1]
	local zoom = at.zoom
	local c0, r0, c1, r1 = Region(at, w, h)
	local ox, oy = Origin(at, c0, r0, c1, r1)
	back.inst, back.zoom, back.moved, back.late, back.ox, back.oy, back.made = inst, zoom, zoom, false, ox, oy, 0
	local r = back.region or {}
	r[1], r[2], r[3], r[4] = c0, r0, c1, r1
	back.region, back.rev = r, layer.rev and layer.rev()
	layer.busy = true -- until the job ends: its last stretch clears it; a failure, the draw step (Failed)
	Runtime.Trace("layout", { e = "start", layer = layer.name, inst = inst, zoom = R2(zoom),
		c0 = R2(c0), r0 = R2(r0), c1 = R2(c1), r1 = R2(r1), ox = ox, oy = oy })
	layer.job = Runtime.Job("map: " .. layer.name, function()
		local t0 = debugprofilestop()
		for _, p in pairs(back.pools) do p.n = 0 end
		back.none = layer.build(back, inst, zoom, c0, r0, c1, r1) == true
		local live, parked = 0, 0
		for _, p in pairs(back.pools) do -- the back canvas is clear: this may yield
			for i = p.n + 1, p.out do
				Reparent(p[i], park)
				parked = parked + 1
				Runtime.Yield()
			end
			p.out = p.n
			live = live + p.n
		end
		Runtime.Trace("layout", { e = "end", layer = layer.name, ms = R2(debugprofilestop() - t0), regions = live,
			made = back.made })
		layer.busy, layer.retryAt, layer.backoff = false, nil, nil
		Swap(layer, back, live, parked)
	end, budget)
end

---------------------------------------------------------------------------
-- Each frame (Window's draw step)
---------------------------------------------------------------------------

-- A layer showing nothing: its layout stopped, both canvases at alpha 0; it lays out again as at the
-- first open. (Its regions stay where they are: Park parks them.)
local function Empty(layer)
	if layer.busy then
		Runtime.Cancel(layer.job)
		layer.busy = false
	end
	for _, c in ipairs(layer.canvases) do Alpha(c, 0) end
	layer.front, layer.fade = nil, nil
end

-- Another map shown: no layer keeps the last one's canvas, nor lays it out.
function Engine.Clear()
	for _, layer in ipairs(Engine.layers) do Empty(layer) end
	Engine.ox, Engine.oy = nil, nil
end

-- The layers' regions parked, a few a frame (a job), until wanted(layer) (it lays out again: its
-- canvases are its own), so showing them again shows no region at once (a Show pays ~7 us a region
-- unmoved, 20-50 moved: docs/evidence/perf-m0.md).
local function Park(layers, wanted)
	Runtime.Job("map: park", function()
		for _, layer in ipairs(layers) do
			for _, c in ipairs(layer.canvases) do
				for _, p in pairs(c.pools) do
					while p.out > 0 do
						if wanted(layer) then return end
						Reparent(p[p.out], park)
						p.out = p.out - 1
						Runtime.Yield()
					end
				end
			end
		end
	end, JOB_MS)
end

-- What a layer's front lacks: nil (nothing), "late" (lay it out again) or "missing" (the view lacks it:
-- before the rest, with more budget). settled: the zoom's (Camera.ZoomSettled); goal: where it's headed
-- (goal.held: for GOAL_S); ahead: the camera AHEAD_S on at its speed.
local function Stale(layer, inst, cam, w, h, settled, goal, ahead)
	local c = layer.front
	if not c or c.inst ~= inst then return "missing" end
	if c.none and c.zoom == cam.zoom and (not layer.rev or c.rev == layer.rev()) then -- nothing to draw: no layout on a pan
		c.ox, c.oy = Engine.ox, Engine.oy
		return
	end
	local zoomed = c.zoom ~= cam.zoom
	if layer.zoom == "hold" and zoomed then return c.zoom ~= goal.zoom and goal.held and "missing" or nil end -- dimmed till it lands
	if not Covers(c, cam, w, h) then return "missing" end
	if not Covers(c, ahead, w, h) then return "late" end
	local s = cam.zoom / c.zoom -- /: never 0 (zooms >= MIN_ZOOM)
	if zoomed and (settled or s < BAND_LO or s > BAND_HI) then return "late" end
	if c.ox ~= Engine.ox or c.oy ~= Engine.oy or (layer.rev and c.rev ~= layer.rev()) then return "late" end
end

-- Each layer placed at the camera, and the stalest laid out again unless a layout runs. True while
-- zooming: a shown layer from another zoom (the wheel's not laid out yet). Engine.pending: a layer
-- stale, laying out, crossfading or zooming (at rest, every layer shows the camera's zoom on the one origin).
local function On(layer) return layer.on end
local goal, ahead = { since = 0 }, {} -- cameras: where it's headed (Motion.Goal), where it is AHEAD_S on
function Engine.Draw(inst, cam, w, h)
	local zooming, settled, now = false, Camera.ZoomSettled(), GetTime()
	local busy, pending, next, why = false, false, nil, nil
	local gz, gx, gy = UI.Motion.Goal()
	if gz ~= goal.zoom then goal.since = now end
	goal.zoom, goal.cx, goal.cy, goal.held = gz, gx, gy, now - goal.since >= GOAL_S
	ahead.zoom, ahead.cx, ahead.cy = cam.zoom, cam.cx + Camera.vx * AHEAD_S, cam.cy + Camera.vy * AHEAD_S
	for _, layer in ipairs(Engine.layers) do
		local on = Engine.LayerOn(layer.name)
		if layer.on ~= on then
			layer.on = on
			if not on then -- emptied while off (its frame stays shown: showing it would show every region at once)
				Empty(layer)
				Park({ layer }, On)
			end
		end
		if layer.busy and layer.job.done then Failed(layer) end -- done but still busy: it didn't finish
		local stale = on and Stale(layer, inst, cam, w, h, settled, goal, ahead)
		pending = pending or stale or layer.busy or layer.fade
		if layer.busy then
			busy = true
			layer.job.budget = stale == "missing" and MISSING_MS or JOB_MS
		elseif stale and (not layer.retryAt or now >= layer.retryAt) and (not next or stale == "missing" and why ~= "missing") then
			next, why = layer, stale
		end
		if on and layer.front then
			Place(layer, cam, w, h)
			zooming = zooming or layer.front.zoom ~= cam.zoom
		end
	end
	Engine.pending = pending or zooming
	if next and not busy then
		Rebuild(next, inst, next.zoom == "hold" and goal or cam, w, h, why == "missing" and MISSING_MS or JOB_MS)
	end
	return zooming
end

-- The window hidden (its own Hide, or its parent's: Alt-Z): every layer emptied and parked until
-- it's visible again.
local function Visible() return Window.frame:IsVisible() end
Window.frame:HookScript("OnHide", Runtime.Wrap("map: hidden park", function()
	for _, layer in ipairs(Engine.layers) do Empty(layer) end
	Park(Engine.layers, Visible)
end))

-- For telemetry: each layer's shown layout (View.diag's layers).
function Engine.State()
	local layers = {}
	for i, l in ipairs(Engine.layers) do
		local c = l.front
		local r = c and c.region
		layers[i] = { name = l.name, busy = l.busy, zoom = c and R2(c.zoom), origin = c and { c.ox, c.oy },
			region = r and { R2(r[1]), R2(r[2]), R2(r[3]), R2(r[4]) } }
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

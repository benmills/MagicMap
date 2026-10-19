-- The map's engine: layers drawn on canvases. Engine.Layer(name, level, build, rev, zoom) adds one
-- (ui/Tiles.lua, ...). A layer has two canvases (1x1 frames, both always shown): the front at alpha 1,
-- the back at alpha 0. A layout, a Runtime.Job (one at a time: a layer the view lacks, or a zoom out is
-- about to, first: the ground, names and pins, then borders, stopping one after it; else the one laid
-- out longest ago; ahead of a pan in smaller slices), lays the layer out on its back canvas at one zoom
-- (tiles zooming out: where it's headed, one layout holding every view on the way), over the view and a
-- margin (more ahead of the camera's motion), into the canvas's own regions where they stand
-- (Engine.Get; Engine.Keep: what the canvas already shows, left as it is), parks what it didn't use
-- (SetParent to a hidden frame), then swaps the two by alpha. Tile (col, row) is at ((col - ox) * zoom,
-- -(row - oy) * zoom) on a canvas: (ox, oy), the origin, a whole tile near the view shared by every
-- layer, so no offset grows past a few thousand px. Panning moves the canvases; until the zoom settles,
-- a layer shows as its zoom says: "scale" (SetScale its canvas: tiles, laid out again once the zoom
-- leaves [0.7, 1.4] of a layout's), "move" (what it placed with Engine.At moved to the camera's zoom, so
-- fonts and icons keep their size, a pin shown from its minimum zoom each frame; laid out again once the
-- zoom drifts log(1.25) from the layout's, a drift on toward where it's headed: labels, pins,
-- Layers.lua:404-416, 2012-2030), "hold" (scaled and dimmed the further it is from its layout's zoom,
-- laid out where the zoom is headed once the wheel stops, crossfaded in as it lands: borders,
-- Layers.lua:16-24, 158-170, 1824-1836, 1907-1937). The window hidden or a layer turned off, its
-- canvases are emptied. Why, from the client's prices: docs/runtime.md "The map's engine". Window's
-- draw step calls Engine.Draw.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local MARGIN = 0.5 -- of the view laid out past each side at rest, so a pan finds it drawn
local LEAD, TRAIL, FAST = 0.75, 0.25, 0.5 -- moving FAST views a second or more: the margin ahead, behind
local AHEAD_S = 0.3 -- moving: laid out again before the view this far ahead leaves the layout
local JOB_MS, MISSING_MS = 4, 4.5 -- a layout's budget a frame; a layer the view lacks, or soon will (with the steps, ~5)
local PAN_MS = 2.5 -- a layout ahead of a pan, the view still covered: smaller slices (the drag's frame p95)
local BAND_LO, BAND_HI = 0.7, 1.4 -- the camera's zoom over a layout's: outside, laid out again before it settles
local DRIFT = 1.25 -- a "move" layer's: its names and pins are chosen for a zoom (Layers.lua:2012 LABEL_DRIFT)
local FADE_S = 0.12 -- a held layer's crossfade to a layout at another zoom (Layers.lua:1697 CROSSFADE)
local SAME_ZOOM = 0.02 -- log: a held layer's layouts this close in zoom cut straight over (Layers.lua:1698)
local LN2 = math.log(2)
-- A layout reaching further than this from the origin (px at its zoom) moves it: offsets stay under
-- 4096 px, moved 1.4x included (the tear's suspect: docs/v1-plan.md §2).
local ORIGIN_PX = 2800
local PAD = 200 -- px past the view a moved label or pin may show from (its anchor: its centre)
local RETRY_S, RETRY_MAX_S = 0.5, 30 -- a failed layout is tried again after this, doubling each failure in a row

local Engine = { layers = {}, toggles = {}, DRIFT = DRIFT } -- toggles: UI's saved layers (ui/View.lua loads them)
UI.Engine = Engine

local park = CreateFrame("Frame", nil, Window.view) -- regions no layout uses: off every canvas
park:Hide()
local Layout -- (below: a layer's worker runs it)

---------------------------------------------------------------------------
-- Layers, canvases and pools
---------------------------------------------------------------------------

-- build(canvas, inst, zoom, c0, r0, c1, r1): lay the layer out on canvas over that tile rect, tile
-- (col, row) at ((col - canvas.ox) * zoom, -(row - canvas.oy) * zoom) from its TOPLEFT, calling
-- Runtime.Yield() now and then. rev (optional): a function whose value changing lays it out again
-- (Model.Known's rev). zoom: "scale" (default), "move" or "hold" (the top). Each layer can be toggled
-- (Engine.toggles[name], UI's saved layers: a missing key is on). build returns true when it has
-- nothing to draw at that zoom anywhere (none known, or not from this zoom: nor further out, then): no
-- layout again on a pan, nor zooming out until it settles.
-- canvas.epoch changes with what a region's place and look hang on (the canvas's map, zoom, origin, the
-- layer's rev): a region kept (Engine.Keep) that was set in this epoch is as it should be.
function Engine.Layer(name, level, build, rev, zoom)
	local view = Window.view
	local f = CreateFrame("Frame", nil, view)
	f:SetAllPoints()
	f:SetFrameLevel(view:GetFrameLevel() + level)
	zoom = zoom or "scale"
	-- order: which goes first when the view lacks it, or soon will: the ground, then names and pins (quick),
	-- then borders (held meanwhile, scaled and dimmed); by level within each
	local layer = { name = name, level = level, frame = f, build = build, rev = rev, zoom = zoom,
		order = (zoom == "scale" and 0 or zoom == "move" and 100 or 200) + level, started = 0, -- started: its last layout's frame
		canvases = {}, fading = {} } -- fading: its crossfade (layer.fade while one runs)
	layer.job = Runtime.Worker("map: " .. name, function()
		while true do
			Layout(layer)
			Runtime.Idle()
		end
	end)
	for i = 1, 2 do
		local c = CreateFrame("Frame", nil, f)
		c:SetSize(1, 1)
		c:SetAlpha(0)
		c.pools, c.alpha, c.made, c.scale, c.epoch = {}, 0, 0, 1, 0
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
-- "line" | "font", for the counts. Pooled per canvas: 1..out on it, the rest parked; 1..n this layout's.
-- key (optional): what it shows (a tile), so the next layout on this canvas finds it (Engine.Keep).
function Engine.Get(canvas, kind, what, make, key)
	local p = canvas.pools[kind]
	if not p then
		p = { n = 0, out = 0, what = what, keys = {}, at = {} } -- keys[i]: what region i shows; at[key]: i
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
	local k = p.keys[n]
	if k ~= key then
		if k ~= nil then p.at[k] = nil end
		if key ~= nil then
			local j = p.at[key]
			if j then p.keys[j] = nil end
			p.at[key] = n
		end
		p.keys[n] = key
	end
	return o
end

-- Regions i and j of a pool trade places, their keys with them.
local function Trade(p, i, j)
	local ki, kj = p.keys[i], p.keys[j]
	p[i], p[j], p.keys[i], p.keys[j] = p[j], p[i], kj, ki
	if kj ~= nil then p.at[kj] = i end
	if ki ~= nil then p.at[ki] = j end
end

-- The region that showed key on this canvas before (Get's key), the layout's next of its kind; nil: none.
-- A layer keeps what it can first, then Gets the rest (a Get takes the next region, whatever it showed).
-- Kept, it stands where it was put if the canvas's epoch is the one it was put in: a pan's layout
-- re-anchors and re-textures only what the canvas didn't show (a tile layout re-set every region).
function Engine.Keep(canvas, kind, key)
	local p = canvas.pools[kind]
	local j = p and p.at[key]
	if not j or j <= p.n then return nil end
	local n = p.n + 1
	if j > p.out then -- parked: back on the canvas, at the end of those on it
		local o = p.out + 1
		Reparent(p[j], canvas)
		Trade(p, j, o)
		p.out, j = o, o
	end
	Trade(p, j, n)
	p.n = n
	return p[n]
end

-- Give back the last Get of a kind (it didn't fit): parked at the layout's end, unless used again.
function Engine.Unget(canvas, kind)
	local p = canvas.pools[kind]
	p.n = p.n - 1
end

-- A "move" region at zoom z: shown from its minimum zoom (Engine.At's), else at alpha 0 (Layers.lua:404-416).
local function Cut(o, z)
	local hid = o.amin ~= nil and z < o.amin
	if hid ~= (o.hid == true) then
		o.hid = hid
		o:SetAlpha(hid and 0 or 1)
	end
end

-- Place o (a "move" layer's region) at tile (col, row), dx, dy px right and down (default 0); while the
-- zoom moves, Engine moves it there at the camera's zoom. minZoom (optional): shown from this zoom only,
-- checked every frame the zoom moves (a pin's: a layer lays those out from a DRIFT below it, so a zoom
-- crossing it shows them that frame, as the spike's PositionPins).
function Engine.At(c, o, point, col, row, dx, dy, minZoom)
	dx, dy = dx or 0, dy or 0
	o.apoint, o.acol, o.arow, o.adx, o.ady, o.az, o.amin = point, col, row, dx, dy, c.zoom, minZoom
	o.x, o.y = (col - c.ox) * c.zoom + dx, (row - c.oy) * c.zoom + dy -- where it stands on the canvas
	o:SetPoint(point, c, "TOPLEFT", o.x, -o.y)
	Cut(o, c.zoom)
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

-- The tile rect r (c0, r0, c1, r1) holds cam's view.
local function Holds(r, cam, w, h)
	local c0, r0 = Maths.ScreenToTile(cam, w, h, 0, 0)
	local c1, r1 = Maths.ScreenToTile(cam, w, h, w, h)
	return c0 >= r[1] and r0 >= r[2] and c1 <= r[3] and r1 <= r[4]
end

local function Covers(c, cam, w, h) return Holds(c.region, cam, w, h) end

local function R2(v) return math.floor(v * 100 + 0.5) / 100 end -- for traces

local function Near(x, y, w, h) return x > -PAD and x < w + PAD and y > -PAD and y < h + PAD end

-- The tile rect r comes within PAD px of cam's view (a label or pin moved there may show in it).
local function Meets(r, cam, w, h)
	local pw, ph = (w / 2 + PAD) / cam.zoom, (h / 2 + PAD) / cam.zoom -- /: never 0 (zoom >= MIN_ZOOM)
	return r[1] < cam.cx + pw and r[3] > cam.cx - pw and r[2] < cam.cy + ph and r[4] > cam.cy - ph
end

-- A "move" canvas's regions to the camera's zoom (o.az: the zoom each stands at): each that shows
-- there, or does where it stands (o.x, o.y); one only showing where it stands goes off the view, kept by
-- it (a zoom's jump would put it thousands of px out). The rest stay put out of view until they would
-- show (c.late), or the next layout; one under its minimum zoom stays put, hidden.
local function Move(c, cam, w, h)
	local z, ox, oy = cam.zoom, c.ox, c.oy
	local x0, y0 = w / 2 + (ox - cam.cx) * z, h / 2 + (oy - cam.cy) * z -- the origin on the view
	local late = false
	for _, p in pairs(c.pools) do
		for i = 1, p.n do
			local o = p[i]
			if o.az ~= z and o.amin and z < o.amin then
				Cut(o, z)
			elseif o.az ~= z then
				local x, y = (o.acol - ox) * z + o.adx, (o.arow - oy) * z + o.ady
				local near = Near(x0 + x, y0 + y, w, h)
				if near or Near(x0 + o.x, y0 + o.y, w, h) then
					if near then
						o.az = z
						Cut(o, z)
					else
						x = math.max(-PAD, math.min(w + PAD, x0 + x)) - x0
						y = math.max(-PAD, math.min(h + PAD, y0 + y)) - y0
						late = true
					end
					o.x, o.y = x, y
					o:SetPoint(o.apoint, c, "TOPLEFT", x, -y)
				else
					late = true
				end
			end
		end
	end
	c.moved, c.late = z, late
end

-- A canvas at the camera: its origin where the camera shows that tile, scaled ("scale", "hold") or
-- its regions moved ("move"). Its scale; nil: a "move" canvas laid out nowhere near the view, left as it
-- stands (a flight or a jump ran past it: its origin far off, it shows nothing there; Place hides it).
-- Anchored to the view's centre, in its own units: a scaled one's offset is the origin's at its
-- layout's zoom (what it moves on the screen: that times its scale).
local function Put(layer, c, cam, w, h)
	local z = cam.zoom
	local s, k = 1, z -- k: px a tile in the canvas's units
	if layer.zoom == "move" then
		if not Meets(c.region, cam, w, h) then return nil end
		if c.moved ~= z or c.late then Move(c, cam, w, h) end
	else
		s, k = z / c.zoom, c.zoom -- /: never 0 (a canvas's zoom: the camera's at layout)
	end
	local x, y = (c.ox - cam.cx) * k, (cam.cy - c.oy) * k
	if c.scale ~= s then
		c.scale = s
		c:SetScale(s)
	end
	if c.x ~= x or c.y ~= y then
		c.x, c.y = x, y
		c:SetPoint("TOPLEFT", layer.frame, "CENTER", x, y)
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
		Alpha(c, s and 1 or 0)
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

-- A layout: the layer laid out on its back canvas (layer.back, at its zoom over its region), then
-- swapped in. Each layer's worker runs one at a time (a coroutine made once: ~10 KB a layout in the
-- client as a job of its own, sessions #8 and #9).
function Layout(layer)
	local back, t0 = layer.back, debugprofilestop()
	local r = back.region
	for _, p in pairs(back.pools) do p.n = 0 end
	back.none = layer.build(back, back.inst, back.zoom, r[1], r[2], r[3], r[4]) == true
	local live, parked = 0, 0
	for _, p in pairs(back.pools) do -- the back canvas is clear: this may yield (stopped, its pools hold)
		while p.out > p.n do
			Reparent(p[p.out], park)
			p.out, parked = p.out - 1, parked + 1
			Runtime.Yield()
		end
		live = live + p.n
	end
	Runtime.Trace("layout", { e = "end", layer = layer.name, ms = R2(debugprofilestop() - t0), regions = live,
		made = back.made })
	layer.busy, layer.retryAt, layer.backoff = false, nil, nil
	Swap(layer, back, live, parked)
end

-- Lay layer out for the camera at (a "hold" layer: where it's headed), on its back canvas. A crossfade
-- running ends first (its old canvas is the back: Layers.lua:1853-1855, FinishCrossfade). Its own call,
-- for what a start costs (perf.alloc: its trace). (4 arguments at most: the sim's xpcall passes more in
-- a table of its own, which the client's doesn't make.)
local Rebuild = Runtime.Wrap("map: layout", function(layer, inst, at, budget)
	local w, h = Window.Size()
	if layer.fade then
		Alpha(layer.fade.from, 0)
		layer.fade = nil
		Place(layer, Camera.cam, w, h)
	end
	local back = layer.canvases[layer.front == layer.canvases[1] and 2 or 1]
	local zoom, rev = at.zoom, layer.rev and layer.rev()
	local c0, r0, c1, r1 = Region(at, w, h)
	local ox, oy = Origin(at, c0, r0, c1, r1)
	if back.inst ~= inst or back.zoom ~= zoom or back.ox ~= ox or back.oy ~= oy or back.rev ~= rev then
		back.epoch = back.epoch + 1 -- (what a region kept from an earlier epoch shows, or where, may differ)
	end
	back.inst, back.zoom, back.moved, back.late, back.ox, back.oy, back.made = inst, zoom, zoom, false, ox, oy, 0
	local r = back.region or {}
	r[1], r[2], r[3], r[4] = c0, r0, c1, r1
	back.region, back.rev = r, rev
	layer.back, layer.busy, layer.started = back, true, Runtime.frames -- busy until the job ends: its last stretch clears it; a failure, the draw step (Failed)
	Runtime.Trace("layout", { e = "start", layer = layer.name, zoom = R2(zoom), ox = ox, oy = oy }) -- (its region: Engine.State)
	Runtime.Wake(layer.job, budget)
end)

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

-- Cameras on the way to where the zoom is headed (Draw's, each frame): step, a DRIFT nearer it (a "move"
-- layer's layout: what's chosen for a zoom is never further than that from the one shown, and the camera
-- heads into it); near, two (a zoom out about to run past the tiles' layout).
local goal, ahead, step, near = {}, {}, {}, {} -- goal: where it's headed (Motion.Goal); ahead: AHEAD_S on at its speed

-- t: the camera f times nearer the goal's zoom (at most there), centred on the way (the centre moves as
-- 1/zoom: the wheel keeps a point still; following, you).
local function Toward(t, cam, f)
	local z, gz = cam.zoom, goal.zoom
	local to, k = math.max(z / f, math.min(z * f, gz)), 0 -- /: never 0 (f: DRIFT's power)
	if gz ~= z then k = (1 / to - 1 / z) / (1 / gz - 1 / z) end -- /: never 0 (zooms > 0, the two differ)
	t.zoom, t.cx, t.cy = to, cam.cx + (goal.cx - cam.cx) * k, cam.cy + (goal.cy - cam.cy) * k
end

-- What a layer's front lacks: nil (nothing), "late" (lay it out again), "soon" (a zoom out about to run
-- past its tiles) or "missing" (the view lacks it); both first (layer.order), with more budget. settled: the
-- zoom's (Camera.ZoomSettled); goal.held: the wheel's ticks have stopped; goal.out: zooming out, its
-- layout would hold the view now. A held layer not yet laid out for the goal is late, missing once off
-- the view (a fast zoom out): the ones it scales over (tiles, names, pins) go first.
local function Stale(layer, inst, cam, w, h, settled)
	local c = layer.front
	if not c or c.inst ~= inst then return "missing" end
	local zoomed = c.zoom ~= cam.zoom
	-- Far enough from the layout's zoom to lay out again before the zoom settles: a "move" layer once it
	-- drifts DRIFT (Layers.lua:2012-2030), the rest out of [BAND_LO, BAND_HI]; but not while the camera
	-- heads into it (laid out where the zoom is headed, or on the way).
	local s, lo, hi = cam.zoom / c.zoom, BAND_LO, BAND_HI -- /: never 0 (zooms >= MIN_ZOOM)
	if layer.zoom == "move" then lo, hi = 1 / DRIFT, DRIFT end
	local drifted = (s < lo or s > hi) and (c.zoom - cam.zoom) * (goal.zoom - c.zoom) < 0
	if c.none and (not layer.rev or c.rev == layer.rev()) then -- nothing to draw at its zoom: laid out again for another zoom only
		if c.ox ~= Engine.ox or c.oy ~= Engine.oy then c.ox, c.oy, c.epoch = Engine.ox, Engine.oy, c.epoch + 1 end
		if zoomed and (settled or drifted and s > 1) then return "late" end -- (one further in may have some)
		return
	end
	if layer.zoom == "hold" and zoomed then -- dimmed till it lands
		if c.zoom == goal.zoom or not goal.held then return end
		return Covers(c, cam, w, h) and "late" or "missing"
	end
	if not Covers(c, cam, w, h) then return "missing" end
	if goal.out and layer.zoom == "scale" and not Covers(c, near, w, h) then return "soon" end
	if not Covers(c, ahead, w, h) then return "late" end
	if zoomed and (settled or drifted) then return "late" end
	if c.ox ~= Engine.ox or c.oy ~= Engine.oy or (layer.rev and c.rev ~= layer.rev()) then return "late" end
end

-- Each layer placed at the camera, and the first stale laid out again unless a layout runs. True while
-- zooming: a shown layer from another zoom (the wheel's not laid out yet). Engine.pending: a layer
-- stale, laying out, crossfading or zooming (at rest, every layer shows the camera's zoom on the one origin).
local function On(layer) return layer.on end
local URGENT = { missing = true, soon = true } -- Stale's: first (by layer.order), at MISSING_MS

-- The camera a layer lays out for: a held one's where the zoom is headed; tiles the camera's, but zooming
-- out where it's headed when that layout would hold the view now (goal.out): the wheel keeps a point in
-- view still (following, you), so every view on the way nests in the goal's, and one layout covers them
-- all (laid out at the camera, a fast zoom out ran past each layout before it landed: blank edges; the
-- spike lays its tiles out every frame). Names and pins: step (they're chosen for the zoom shown).
local function For(layer, cam)
	if layer.zoom == "hold" or goal.out and layer.zoom == "scale" then return goal end
	return layer.zoom == "move" and step or cam
end
local headed = {} -- the goal's layout region
function Engine.Draw(inst, cam, w, h)
	local zooming, settled, now = false, Camera.ZoomSettled(), GetTime()
	local panning = Camera.vx ~= 0 or Camera.vy ~= 0
	local busy, pending, next, why = nil, false, nil, nil
	local gz, gx, gy = UI.Motion.Goal()
	goal.held = gz == goal.zoom -- no tick since the last frame: a held layer lays out there (Layers.lua:1907-1937)
	goal.zoom, goal.cx, goal.cy = gz, gx, gy
	headed[1], headed[2], headed[3], headed[4] = Region(goal, w, h)
	goal.out = gz < cam.zoom and Holds(headed, cam, w, h)
	ahead.zoom, ahead.cx, ahead.cy = cam.zoom, cam.cx + Camera.vx * AHEAD_S, cam.cy + Camera.vy * AHEAD_S
	Toward(step, cam, DRIFT)
	Toward(near, cam, DRIFT * DRIFT)
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
		local stale = on and Stale(layer, inst, cam, w, h, settled)
		pending = pending or stale or layer.busy or layer.fade
		if layer.busy then
			busy = layer
			layer.job.budget = URGENT[stale] and MISSING_MS or panning and PAN_MS or JOB_MS
		elseif stale and (not layer.retryAt or now >= layer.retryAt) and (not next or URGENT[stale]
			and (not URGENT[why] or layer.order < next.order) or not URGENT[why] and layer.started < next.started) then
			next, why = layer, stale -- (else the one laid out longest ago: zooming in, names wait on no tile layout)
		end
		if on and layer.front then
			Place(layer, cam, w, h)
			zooming = zooming or layer.front.zoom ~= cam.zoom
		end
	end
	Engine.pending = pending or zooming
	if next and busy and URGENT[why] and next.order < busy.order then -- the view lacks it, or soon will: one after
		Runtime.Cancel(busy.job) -- it laying out stops, to start again after
		busy.busy, busy = false, nil
	end
	if next and not busy then
		Rebuild(next, inst, For(next, cam), URGENT[why] and MISSING_MS or panning and PAN_MS or JOB_MS)
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
	if known then -- only the ones off are saved (the gear's: ui/Menus.lua)
		if Engine.LayerOn(name) then Engine.toggles[name] = false else Engine.toggles[name] = nil end
	end
	for _, l in ipairs(Engine.layers) do print(string.format("  %s %s", l.name, Engine.LayerOn(l.name) and "on" or "off")) end
end })
Command({ kind = "slash", name = "mapstats", help = "the map's live textures, lines and font strings", fn = function()
	local live, made = Engine.Stats()
	local cam = Camera.cam
	print(string.format("MagicMapAtlas map: inst %s, zoom %.1f px/tile; live %d textures, %d lines, %d font strings"
		.. " (made %d, %d, %d)", tostring(Camera.inst), cam.zoom, live.tex, live.line, live.font, made.tex, made.line,
		made.font))
end })

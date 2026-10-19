-- The map's engine: layers drawn on canvases. Engine.Layer(name, level, build, rev, zoom) adds one
-- (ui/Tiles.lua, ...). A layer has two canvases (1x1 frames, both always shown): the front at alpha 1,
-- the back at alpha 0. A layout, a Runtime.Job, lays the layer out on its back canvas at one zoom (tiles
-- zooming out: where it's headed, one layout holding every view on the way), over the view and a margin
-- (more ahead of the camera's motion), into the canvas's own regions where they stand (Engine.Get;
-- Engine.Keep: what the canvas already shows, left as it is), parks what it didn't use (SetParent to a
-- hidden frame), then swaps the two by alpha. The layouts share a frame's budget, one at a time, in turn
-- (Draw's plan: the view lacking a layer, or about to, first, the ground, then names and pins, then
-- borders; a layout going on; else the one laid out longest ago; ahead of a pan in smaller slices): one
-- ending with budget left hands it on (Chain). Tile (col, row) is at ((col - ox) * zoom, -(row - oy) *
-- zoom) on a canvas: (ox, oy), the origin, a whole tile near the view shared by every layer, so no offset
-- grows past a few thousand px. Panning moves the canvases; until the zoom settles, a layer shows as its
-- zoom says: "scale" (SetScale its canvas: tiles, laid out again once the zoom leaves [0.7, 1.4] of a
-- layout's), "move" (what it placed with Engine.At moved to the camera's zoom, so fonts keep their size;
-- laid out at the camera's zoom each time it drifts log(1.25) and where it lands: names, the spike's
-- LayoutLabels, Layers.lua:1647-1653, 2012-2030), "pin" (moved too, a pin shown from its minimum zoom the
-- frame it's crossed; laid out a drift on toward where the zoom is headed, for the view, not each drift:
-- pins, PositionPins, Layers.lua:403-416), "hold" (scaled and dimmed the further it is from its layout's
-- zoom, laid out where the zoom is headed once the wheel stops, crossfaded in as it lands; in a glide, the
-- camera within 2% of that zoom, laid out for the view as a pan's, over the glide's way: borders,
-- Layers.lua:16-24, 158-170, 1824-1836, 1907-1937). The window hidden or a layer turned off, its canvases
-- are emptied. Why, from the client's prices: docs/runtime.md "The map's engine". Window's draw step
-- calls Engine.Draw.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime = ns.Atlas, ns.Runtime
local Camera, Window = UI.Camera, UI.Window
local Maths = Atlas.Camera

local MARGIN = 0.5 -- of the view laid out past each side at rest, so a pan finds it drawn
local LEAD, TRAIL, FAST = 0.75, 0.25, 0.5 -- moving FAST views a second or more: the margin ahead, behind
local AHEAD_S = 0.3 -- moving: laid out again before the view this far ahead leaves the layout
local JOB_MS, MISSING_MS = 4, 4.5 -- the layouts' budget a frame; with one urgent (with the steps, ~5)
local PAN_MS = 2.5 -- layouts ahead of a pan, the view still covered: smaller slices (the drag's frame p95)
local CHAIN_MS, CHAIN_TO = 1, 3.5 -- a layout ending with this much left of the frame's budget, at most this, hands it on (Chain)
local BAND_LO, BAND_HI = 0.7, 1.4 -- the camera's zoom over a layout's: outside, laid out again before it settles
local DRIFT = 1.25 -- a "move" or "pin" layer's: its names and pins are chosen for a zoom (Layers.lua:2012 LABEL_DRIFT)
local FADE_S = 0.12 -- a held layer's crossfade to a layout at another zoom (Layers.lua:1697 CROSSFADE)
local SAME_ZOOM = 0.02 -- log: a held layer's layouts this close in zoom cut straight over; the camera this close to the goal's, a glide (Layers.lua:1698)
local LN2 = math.log(2)
-- A layout reaching further than this from the origin (px at its zoom) moves it: offsets stay under
-- 4096 px, moved 1.4x included (the tear's suspect: docs/v1-plan.md §2).
local ORIGIN_PX = 2800
local PAD = 200 -- px past the view a moved label or pin may show from (its anchor: its centre)
-- A "move" or "pin" canvas shows while its offsets stay under this (its origin's from the view's centre;
-- its layout's furthest from the origin at the camera's zoom, a label's spot on top): under 4096, however
-- far the zoom runs from its layout's before it's laid out again.
local SHOWN_PX = 4000
local RETRY_S, RETRY_MAX_S = 0.5, 30 -- a failed layout is tried again after this, doubling each failure in a row

-- toggles: UI's saved layers (ui/View.lua loads them); defaults: false for a layer off until turned on
-- (its gear row's, ui/Menus.lua)
local Engine = { layers = {}, toggles = {}, defaults = {}, DRIFT = DRIFT }
UI.Engine = Engine

local park = CreateFrame("Frame", nil, Window.view) -- regions no layout uses: off every canvas
park:Hide()
local Layout, Chain -- (below: a layer's worker runs it; at its end, it hands the frame on)
local goal, headed, step -- (below: Draw's, each frame: where the zoom is headed, its layout region, a drift on)

---------------------------------------------------------------------------
-- Layers, canvases and pools
---------------------------------------------------------------------------

-- build(canvas, inst, zoom, c0, r0, c1, r1): lay the layer out on canvas over that tile rect, tile
-- (col, row) at ((col - canvas.ox) * zoom, -(row - canvas.oy) * zoom) from its TOPLEFT, calling
-- Runtime.Yield() now and then. rev (optional): a function whose value changing lays it out again
-- (Model.Known's rev). zoom: "scale" (default), "move", "pin" or "hold" (the top). Each layer can be
-- toggled (Engine.toggles[name], UI's saved layers: a missing key is its default, on unless its gear row
-- says otherwise). build returns true when it has nothing to draw at that zoom anywhere (none known, or
-- not from this zoom: nor further out, then): no layout again on a pan, nor zooming out until it settles;
-- or a zoom: what it left out shows from there (Engine.From said no), laid out again once a layout would
-- draw it (nothing drawn: none, as true).
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
		moves = zoom == "move" or zoom == "pin", -- placed with Engine.At, moved to the camera's zoom
		order = (zoom == "scale" and 0 or zoom == "hold" and 200 or 100) + level, started = 0, -- started: its last layout's frame
		canvases = {}, fading = {}, -- fading: its crossfade (layer.fade while one runs)
		-- since load, for /mma perf and debug (the gauge below): its layouts at a new zoom (builds, their ms) and at
		-- the zoom shown (pans: the spike's extensions), the frames the view ran past it; its last layout's ms, regions
		builds = 0, buildMs = 0, pans = 0, past = 0, ms = 0, regions = 0 }
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
		c.pools, c.alpha, c.made, c.scale, c.epoch, c.mins = {}, 0, 0, 1, 0, {}
		layer.canvases[i] = c
	end
	local i = #Engine.layers + 1 -- by level: the order layouts go in
	while i > 1 and Engine.layers[i - 1].level > level do i = i - 1 end
	table.insert(Engine.layers, i, layer)
	return layer
end

-- A region onto a frame (o.on), with its mask (a tile's coast fade: it moves with it).
local function Reparent(o, to)
	o:SetParent(to)
	o.on = to
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
		p[n], o.on = o, canvas
		canvas.made = canvas.made + 1
	elseif n > p.out then
		Reparent(o, o.home or canvas)
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
		Reparent(p[j], p[j].home or canvas)
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

-- The canvas's frame for regions shown from minZoom: its alpha, set as the zoom crosses it (Put), shows or
-- hides them all at once (a SetAlpha each was the draw's 3.1 ms priced for the big window's ~440 rares at
-- 60, a crossing's frame twice another's: docs/runtime.md).
local function Min(c, minZoom)
	local f = c.mins[minZoom]
	if not f then
		f = CreateFrame("Frame", nil, c)
		f:SetAllPoints()
		f.alpha = 1
		c.mins[minZoom] = f
	end
	return f
end

-- Place o (a "move" or "pin" layer's region) at tile (col, row), dx, dy px right and down (default 0);
-- while the zoom moves, Engine moves it there at the camera's zoom. minZoom (optional): shown from this
-- zoom only, on the canvas's frame for it (a pin's: a layer lays those out from a DRIFT below it,
-- Engine.From, so a zoom crossing it shows them that frame, as the spike's PositionPins, Layers.lua:404-416).
function Engine.At(c, o, point, col, row, dx, dy, minZoom)
	dx, dy = dx or 0, dy or 0
	o.apoint, o.acol, o.arow, o.adx, o.ady, o.az, o.amin = point, col, row, dx, dy, c.zoom, minZoom
	o.x, o.y = (col - c.ox) * c.zoom + dx, (row - c.oy) * c.zoom + dy -- where it stands on the canvas
	local on = minZoom and Min(c, minZoom) or c
	if o.on ~= on then Reparent(o, on) end
	o.home = on ~= c and on or nil -- (taken back from the park, onto it: Get)
	o:SetPoint(point, c, "TOPLEFT", o.x, -o.y)
end

-- A layout at zoom draws what shows from minZoom (Engine.At's): the camera's zoom or the layout's from it,
-- or from a drift below it unless the zoom is headed out, so the frame it crosses shows or hides it
-- (Layers.lua:404-416); not zooming out past it.
function Engine.From(zoom, minZoom)
	zoom = math.max(zoom, Camera.cam.zoom)
	return zoom >= minZoom or zoom * DRIFT >= minZoom and goal.zoom >= zoom
end

-- Tile-space position on a canvas laid out at zoom (v from its origin), rounded so neighbours share edges.
function Engine.Px(v, zoom)
	return math.floor(v * zoom + 0.5)
end

function Engine.LayerOn(name)
	local on = Engine.toggles[name]
	if on == nil then return Engine.defaults[name] ~= false end
	return on
end

-- A layer turned on or off: saved only where that isn't its default (types/saved.lua SavedUI.layers).
function Engine.SetLayer(name, on)
	if on == (Engine.defaults[name] ~= false) then Engine.toggles[name] = nil else Engine.toggles[name] = on end
end

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

-- A "move" or "pin" canvas c shows at cam: near the view, its offsets under SHOWN_PX at the camera's zoom
-- (its regions stand within its layout's tile rect: c.reach tiles from the origin at most).
local function Shown(c, cam, w, h)
	local z = cam.zoom
	return Meets(c.region, cam, w, h) and c.reach * z <= SHOWN_PX and math.abs(c.ox - cam.cx) * z <= SHOWN_PX
		and math.abs(c.oy - cam.cy) * z <= SHOWN_PX
end

-- A moved canvas's regions to the camera's zoom (o.az: the zoom each stands at): each that shows
-- there, or does where it stands (o.x, o.y); one only showing where it stands goes off the view, kept by
-- it (a zoom's jump would put it thousands of px out). The rest stay put out of view until they would
-- show (c.late), or the next layout; one under its minimum zoom stays put, hidden (its frame's: Put).
local function Move(c, cam, w, h)
	local z, ox, oy = cam.zoom, c.ox, c.oy
	local x0, y0 = w / 2 + (ox - cam.cx) * z, h / 2 + (oy - cam.cy) * z -- the origin on the view
	local late = false
	for _, p in pairs(c.pools) do
		for i = 1, p.n do
			local o = p[i]
			if o.az ~= z and not (o.amin and z < o.amin) then
				local x, y = (o.acol - ox) * z + o.adx, (o.arow - oy) * z + o.ady
				local near = Near(x0 + x, y0 + y, w, h)
				if near or Near(x0 + o.x, y0 + o.y, w, h) then
					if near then
						o.az = z
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
-- its regions moved ("move", "pin"). Its scale; nil: left as it stands, its offsets past SHOWN_PX on the
-- screen (a flight, a jump or a flick ran past its layout: its origin far off, a moved one laid out nowhere
-- near the view or far from the camera's zoom; Place hides it, and Stale has it laid out first), but a
-- held one scaled past BAND_HI, its offset growing with its scale until it lands, as the spike's
-- PlaceCanvas (Layers.lua:142-156). Anchored to the view's centre, in its own units: a scaled one's
-- offset is the origin's at its layout's zoom (what it moves on the screen: that times its scale).
local function Put(layer, c, cam, w, h)
	local z = cam.zoom
	local s, k = 1, z -- k: px a tile in the canvas's units
	if layer.moves then
		if not Shown(c, cam, w, h) then return nil end
		if c.moved ~= z or c.late then Move(c, cam, w, h) end
		for m, f in pairs(c.mins) do Alpha(f, z < m and 0 or 1) end
	else
		s, k = z / c.zoom, c.zoom -- /: never 0 (a canvas's zoom: the camera's at layout)
	end
	local x, y = (c.ox - cam.cx) * k, (cam.cy - c.oy) * k
	if s <= BAND_HI and math.max(math.abs(x), math.abs(y)) * s > SHOWN_PX then return nil end
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
		local from = Put(layer, f.from, cam, w, h)
		local p = math.min(1, (GetTime() - f.t) / FADE_S)
		Alpha(c, s and p or 0)
		Alpha(f.from, from and f.a * (1 - p) or 0)
		if p >= 1 then layer.fade = nil end
	elseif layer.zoom == "hold" and s then
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
-- swapped in, the frame's budget left handed on (Chain). Each layer's worker runs one at a time (a
-- coroutine made once: ~10 KB a layout in the client as a job of its own, sessions #8 and #9).
function Layout(layer)
	local back, t0 = layer.back, debugprofilestop()
	local r = back.region
	for _, p in pairs(back.pools) do p.n = 0 end
	local more = layer.build(back, back.inst, back.zoom, r[1], r[2], r[3], r[4])
	local live, parked = 0, 0
	for _, p in pairs(back.pools) do -- the back canvas is clear: this may yield (stopped, its pools hold)
		while p.out > p.n do
			Reparent(p[p.out], park)
			p.out, parked = p.out - 1, parked + 1
			Runtime.Yield()
		end
		live = live + p.n
	end
	back.none, back.from = more == true or more ~= nil and live == 0, more ~= true and more or nil
	Runtime.Trace("layout", { e = "end", layer = layer.name, ms = R2(debugprofilestop() - t0), regions = live,
		made = back.made })
	local f, ms = layer.front, Runtime.Spent()
	if f and f.inst == back.inst and f.zoom == back.zoom then
		layer.pans = layer.pans + 1
	else
		layer.builds, layer.buildMs = layer.builds + 1, layer.buildMs + ms
	end
	layer.ms, layer.regions = ms, live
	layer.busy, layer.retryAt, layer.backoff = false, nil, nil
	Swap(layer, back, live, parked)
	Chain(layer)
end

-- Lay layer out at at.zoom over the tile rect at[1..4] (For's), on its back canvas. A crossfade running
-- ends first (its old canvas is the back: Layers.lua:1853-1855, FinishCrossfade). Names and pins, the goal
-- a drift or less away in zoom (a glide, a chase landing): over the goal's view too; borders (laid out at
-- the goal) in a glide: over the camera's; if that stays within ORIGIN_PX of the origin, so one layout holds
-- every view on the way (the spike lays its pins out map-wide, Layers.lua:418-430). Draw's its own call,
-- for what a start costs (perf.alloc: its trace; Chain's counts in the layout's job that started it). (4
-- arguments at most: the sim's xpcall passes more in a table of its own, which the client's doesn't make.)
local function Start(layer, inst, at, budget)
	local w, h = Window.Size()
	if layer.fade then
		Alpha(layer.fade.from, 0)
		layer.fade = nil
		Place(layer, Camera.cam, w, h)
	end
	local back = layer.canvases[layer.front == layer.canvases[1] and 2 or 1]
	local zoom, rev = at.zoom, layer.rev and layer.rev()
	local c0, r0, c1, r1 = at[1], at[2], at[3], at[4]
	local ox, oy = Origin(at, c0, r0, c1, r1)
	local glide = layer.zoom == "hold" and goal.glide
	if layer.moves and step.zoom == goal.zoom or glide then
		local p0, q0, p1, q1 = headed[1], headed[2], headed[3], headed[4]
		if glide then p0, q0, p1, q1 = Region(Camera.cam, w, h) end
		local g0, s0 = math.min(c0, p0), math.min(r0, q0)
		local g1, s1 = math.max(c1, p1), math.max(r1, q1)
		if math.max(ox - g0, g1 - ox, oy - s0, s1 - oy) * zoom <= ORIGIN_PX then c0, r0, c1, r1 = g0, s0, g1, s1 end
	end
	if back.inst ~= inst or back.zoom ~= zoom or back.ox ~= ox or back.oy ~= oy or back.rev ~= rev then
		back.epoch = back.epoch + 1 -- (what a region kept from an earlier epoch shows, or where, may differ)
	end
	back.inst, back.zoom, back.moved, back.late, back.ox, back.oy, back.made = inst, zoom, zoom, false, ox, oy, 0
	local r = back.region or {}
	r[1], r[2], r[3], r[4] = c0, r0, c1, r1
	back.region, back.rev, back.gx, back.gy = r, rev, goal.cx, goal.cy
	back.reach = math.max(ox - c0, c1 - ox, oy - r0, r1 - oy)
	layer.back, layer.busy, layer.started = back, true, Runtime.frames -- busy until the job ends: its last stretch clears it; a failure, the draw step (Failed)
	Runtime.Trace("layout", { e = "start", layer = layer.name, zoom = R2(zoom), ox = ox, oy = oy }) -- (its region: Engine.State)
	Runtime.Wake(layer.job, budget)
end
local Rebuild = Runtime.Wrap("map: layout", Start)

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

-- Cameras on the way to where the zoom is headed (Draw's, each frame): step, a DRIFT nearer it (the goal
-- within a drift: step's zoom is the goal's; pins lay out there); near, two (a zoom out about to run past
-- the tiles' layout; zooming in, the tiles' layout zoom).
goal, step = {}, {} -- goal: where it's headed (Motion.Goal)
local ahead, near = {}, {} -- ahead: AHEAD_S on at its speed, not past the goal

-- t: the camera f times nearer the goal's zoom (at most there), centred on the way (the centre moves as
-- 1/zoom: the wheel keeps a point still; following, you); no zoom to speak of (a glide's: log and back,
-- not quite its own), the camera's centre.
local function Toward(t, cam, f)
	local z, gz = cam.zoom, goal.zoom
	local to, k = math.max(z / f, math.min(z * f, gz)), 0 -- /: never 0 (f: DRIFT's power)
	if math.abs(math.log(gz / z)) > SAME_ZOOM then k = (1 / to - 1 / z) / (1 / gz - 1 / z) end -- /: never 0 (zooms > 0, the two differ)
	t.zoom, t.cx, t.cy = to, cam.cx + (goal.cx - cam.cx) * k, cam.cy + (goal.cy - cam.cy) * k
end

-- AHEAD_S on from c at v tiles a second, but not past g when headed there (a glide's start is its fastest).
local function Ahead(c, v, g)
	local a = c + v * AHEAD_S
	if (g - c) * v > 0 and (a - g) * v > 0 then return g end
	return a
end

-- What a layer's front lacks: nil (nothing), "late" (lay it out again), or urgent: "missing" (the view
-- lacks it, or a moved one's offsets would pass SHOWN_PX), "soon" (a zoom out about to run past its
-- tiles; a moved one reaching past ORIGIN_PX at the camera's zoom, before SHOWN_PX hides it), "drift"
-- (names chosen for a zoom a drift from the camera's, or another than the one it landed at: Layers.lua:
-- 2012-2030; pins left out by their minimum zoom a layout would now draw; names and pins not laid out for
-- where it's headed), "blur" (tiles zoomed in past [0.7, 1.4] of their layout's). Pins aren't chosen for a zoom
-- (PositionPins places them, Layers.lua:403-416): laid out again for the view, not each drift. settled: the zoom's (Camera.ZoomSettled); goal.held: the wheel's
-- ticks have stopped; goal.out: zooming out, its layout would hold the view now; goal.glide: the camera
-- within SAME_ZOOM of the goal's zoom (a glide's, log and back, isn't quite its own). A held layer not yet
-- laid out for the goal is late, missing once off the view (a fast zoom out): the ones it scales over go
-- first; one laid out for it in a glide isn't zoomed: laid out for the view, as a pan's (the spike's Fits,
-- Layers.lua:1698-1700, 1875-1877, 1915).
local function Stale(layer, inst, cam, w, h, settled)
	local c = layer.front
	if not c or c.inst ~= inst then return "missing" end
	local zoomed, move = c.zoom ~= cam.zoom, layer.moves
	if layer.zoom == "hold" and c.zoom == goal.zoom and goal.glide then zoomed = false end
	-- Far enough from the layout's zoom to lay out again before the zoom settles: names and pins once they
	-- drift DRIFT (Layers.lua:2012-2030), the rest out of [BAND_LO, BAND_HI]; but not while the camera
	-- heads into it (laid out where the zoom is headed, or on the way).
	local s, lo, hi = cam.zoom / c.zoom, BAND_LO, BAND_HI -- /: never 0 (zooms >= MIN_ZOOM)
	if move then lo, hi = 1 / DRIFT, DRIFT end
	local drifted = (s < lo or s > hi) and (c.zoom - cam.zoom) * (goal.zoom - c.zoom) < 0
	local landed = goal.zoom == cam.zoom and layer.zoom == "move" -- no chase or flight zooming: names for it now (Layers.lua:2023-2028)
	-- what it left out by zoom now drawn by a layout where it would lay out (Engine.From: pins, a zoom in
	-- laying them out before it crosses their minimum zoom)
	local more = c.from and Engine.From(step.zoom, c.from)
	if c.none and (not layer.rev or c.rev == layer.rev()) then -- nothing to draw at its zoom: laid out again for another zoom only
		if c.ox ~= Engine.ox or c.oy ~= Engine.oy then c.ox, c.oy, c.epoch = Engine.ox, Engine.oy, c.epoch + 1 end
		if more or zoomed and drifted and s > 1 then return move and "drift" or "late" end -- (one further in may have some)
		if zoomed and (settled or landed) then return "late" end
		return
	end
	if layer.zoom == "hold" and zoomed then -- dimmed till it lands
		if c.zoom == goal.zoom or not goal.held then return end
		return Covers(c, cam, w, h) and "late" or "missing"
	end
	if not Covers(c, cam, w, h) or move and not Shown(c, cam, w, h) then return "missing" end
	if goal.out and layer.zoom == "scale" and not Covers(c, near, w, h) or move and c.reach * cam.zoom > ORIGIN_PX then
		return "soon"
	end
	if layer.zoom == "pin" then drifted = false end
	if move and (more or zoomed and (drifted or landed) or step.zoom == goal.zoom and (c.gx ~= goal.cx or c.gy ~= goal.cy)
		and not Holds(c.region, goal, w, h)) then return "drift" end
	if layer.zoom == "scale" and drifted and s > 1 then return "blur" end
	if not Covers(c, ahead, w, h) then return "late" end
	if zoomed and (settled or drifted) then return "late" end
	if c.ox ~= Engine.ox or c.oy ~= Engine.oy or (layer.rev and c.rev ~= layer.rev()) then return "late" end
end

local function On(layer) return layer.on end
-- Stale's urgent kinds (at MISSING_MS), each its turn after layer.order (the ground 0, names and pins 100,
-- borders 200, + level): the view lacking a layer, or soon to, first (a zoom out's ground laid out later is
-- laid out further out: the goal runs on), but borders after names and pins drifted, then a blurred ground.
local URGENT = { missing = 0, soon = 0, drift = 50, blur = 170 }

-- A layer's turn this frame, lower first: an urgent one; then a layout going on; then the one laid out
-- longest ago (zooming in, names wait on no tile layout).
local function Rank(layer, why)
	if URGENT[why] then return layer.order + URGENT[why] end
	if layer.busy then return 1000 end
	return 2000 + layer.started
end

-- Where a layer lays out (at.zoom, over the tile rect at[1..4]): a held one where the zoom is headed;
-- tiles the camera's, but zooming out where it's headed when that layout would hold the view now (goal.out:
-- the wheel keeps a point in view still, following you, so every view on the way nests in the goal's,
-- and one layout covers them all; laid out at the camera, a fast zoom out ran past each layout before it
-- landed: blank edges; the spike lays its tiles out every frame), and zooming in two drifts on toward it
-- (near, at most there), the camera's view with it, so one layout lasts the way in. Names: the camera's
-- (the spike's LayoutLabels: state.zoom). Pins: a drift on toward it (step), so a zoom in lays them out
-- before it crosses their minimum zoom. Start adds the goal's view to both, and the camera's to a held one's
-- in a glide.
local at = {}
local function For(layer, cam, w, h)
	local src = cam
	if layer.zoom == "hold" or layer.zoom == "scale" and goal.out then
		src = goal
	elseif layer.zoom == "scale" and math.log(goal.zoom / cam.zoom) > SAME_ZOOM then -- /: never 0 (zooms > 0)
		src = near
	elseif layer.zoom == "pin" then
		src = step
	end
	at.zoom, at.cx, at.cy = src.zoom, src.cx, src.cy
	at[1], at[2], at[3], at[4] = Region(src, w, h)
	if src == near then -- (the wheel off the centre: near's view nests in the camera's, off to a side)
		local hw, hh = w / 2 / cam.zoom, h / 2 / cam.zoom -- /: never 0 (zoom >= MIN_ZOOM)
		at[1], at[2] = math.min(at[1], cam.cx - hw), math.min(at[2], cam.cy - hh)
		at[3], at[4] = math.max(at[3], cam.cx + hw), math.max(at[4], cam.cy + hh)
	end
	return at
end

-- This frame's layouts, in turn (Draw's): plan[1] runs (started, or going on) with the frame's budget,
-- the rest queued after it in turn at 0 (Runtime.Requeue: waiting, not resumed) for what it leaves (Chain).
-- slot: a layer's place in the plan, slotAt the frame it got its turn.
local plan, nplan, tail = {}, 0, false -- tail: Chain started one (queued last: those waiting are past)
local frame = { inst = nil, w = 0, h = 0, budget = 0 } -- Draw's, for Chain

-- At a layout's end (in its job): what's left of the frame's budget to the next in the plan, a layout
-- going on (queued after it) first, else the first not yet laid out this frame (started: queued last).
function Chain(layer)
	local left, now = Runtime.Left(), Runtime.frames
	if layer.slot == 1 then left = left - math.max(0, frame.budget - CHAIN_TO) end -- (the frame's first: its budget the whole)
	if left < CHAIN_MS or layer.slotAt ~= now then return end
	if not tail then
		for i = layer.slot + 1, nplan do
			local l = plan[i]
			if l.busy then
				l.job.budget, l.slot, l.slotAt = left, i, now
				return
			end
		end
	end
	for i = 1, nplan do
		local l = plan[i]
		if not l.busy and l.slotAt ~= now then
			tail, l.slot, l.slotAt = true, i, now
			Start(l, frame.inst, For(l, Camera.cam, frame.w, frame.h), left)
			return
		end
	end
end

-- Each layer placed at the camera, and the frame's layouts planned (Rank's turns: Chain). True while
-- zooming: a shown layer from another zoom (the wheel's not laid out yet; Engine.zooming the last draw's).
-- Engine.pending: a layer stale, laying out, crossfading or zooming (at rest, every layer shows the camera's
-- zoom on the one origin).
headed = {} -- the goal's layout region
function Engine.Draw(inst, cam, w, h)
	local zooming, settled, now = false, Camera.ZoomSettled(), GetTime()
	local panning = Camera.vx ~= 0 or Camera.vy ~= 0
	local pending = false
	local gz, gx, gy = UI.Motion.Goal()
	goal.held = gz == goal.zoom -- no tick since the last frame: a held layer lays out there (Layers.lua:1907-1937)
	goal.glide = math.abs(math.log(gz / cam.zoom)) < SAME_ZOOM -- /: never 0 (zooms > 0)
	goal.zoom, goal.cx, goal.cy = gz, gx, gy
	headed[1], headed[2], headed[3], headed[4] = Region(goal, w, h)
	goal.out = gz < cam.zoom and Holds(headed, cam, w, h)
	ahead.zoom = cam.zoom
	ahead.cx, ahead.cy = Ahead(cam.cx, Camera.vx, gx), Ahead(cam.cy, Camera.vy, gy)
	Toward(step, cam, DRIFT)
	Toward(near, cam, DRIFT * DRIFT)
	nplan, tail = 0, false
	frame.inst, frame.w, frame.h = inst, w, h
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
		if layer.busy and layer.zoom == "hold" and layer.back.zoom ~= gz then -- headed elsewhere now: re-aimed (Layers.lua:1913-1928)
			Runtime.Cancel(layer.job)
			layer.busy = false
		end
		local stale = on and Stale(layer, inst, cam, w, h, settled)
		if stale == "missing" and layer.front then layer.past = layer.past + 1 end -- (laid out once: Perf.lua:172)
		pending = pending or stale or layer.busy or layer.fade
		if layer.busy or stale and (not layer.retryAt or now >= layer.retryAt) then
			local r = Rank(layer, stale)
			local i = nplan + 1
			while i > 1 and plan[i - 1].rank > r do
				plan[i] = plan[i - 1]
				i = i - 1
			end
			plan[i], layer.rank, layer.why, nplan = layer, r, stale, nplan + 1
		end
		if on and layer.front then
			Place(layer, cam, w, h)
			zooming = zooming or layer.front.zoom ~= cam.zoom
		end
	end
	Engine.pending, Engine.zooming = pending or zooming, zooming
	local budget = plan[1] and (URGENT[plan[1].why] and MISSING_MS or panning and PAN_MS or JOB_MS)
	frame.budget = budget or 0
	for i = 1, nplan do
		local l = plan[i]
		if i == 1 then l.slot, l.slotAt = 1, Runtime.frames end
		if l.busy then
			l.job.budget = i == 1 and budget or 0
			Runtime.Requeue(l.job)
		elseif i == 1 then
			Rebuild(l, inst, For(l, cam, w, h), budget)
		end
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

-- /mma perf and perf mem (Perf.lua:103-122, 146-159): the borders' counts (Engine.Layer's), each kind's
-- regions made and in use (Layers.lua:2262-2273), the tiles drawn and their textures spare (Core.lua:1640-1646).
local KINDS = { tex = "Texture", line = "Line", font = "FontString" }
Runtime.Gauge("map", function()
	local b, t, live, made = UI.Borders, UI.Tiles, Engine.Stats()
	local objects, drawn, all = {}, 0, 0
	for what, kind in pairs(KINDS) do objects[kind] = { made = made[what], used = live[what] } end
	for _, c in ipairs(t.canvases) do
		local p = c.pools.art -- (ui/Tiles.lua's tile textures)
		if p then
			all = all + #p
			if c == t.front then drawn = p.n end
		end
	end
	return { builds = b.builds, buildMs = b.buildMs, pans = b.pans, past = b.past, objects = objects, tiles = drawn,
		spare = all - drawn }
end)

local Command = ns.Game.Command
Command({ kind = "slash", name = "layer", help = "<name>: show or hide a map layer; alone, list them", fn = function(name)
	local known = false
	for _, l in ipairs(Engine.layers) do known = known or l.name == name end
	if known then Engine.SetLayer(name, not Engine.LayerOn(name)) end -- (the gear's: ui/Menus.lua)
	for _, l in ipairs(Engine.layers) do print(string.format("  %s %s", l.name, Engine.LayerOn(l.name) and "on" or "off")) end
end })
Command({ kind = "slash", name = "mapstats", help = "the map's live textures, lines and font strings", fn = function()
	local live, made = Engine.Stats()
	local cam = Camera.cam
	print(string.format("MagicMapAtlas map: inst %s, zoom %.1f px/tile; live %d textures, %d lines, %d font strings"
		.. " (made %d, %d, %d)", tostring(Camera.inst), cam.zoom, live.tex, live.line, live.font, made.tex, made.line,
		made.font))
end })

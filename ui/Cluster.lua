-- Overlapping pins grouped (ui/Cluster.lua). Where more than 3 pins of the clustered layers (quests, offers,
-- places, rares: opts.cluster in Pins.Layer) overlap at the zoom (centres within RANGE px of each other, the
-- greedy pass in Group), they draw as one pill at their centroid: its first few icons side by side and a
-- "+N", on a dark backing. Clicking the pill opens a grid of its members above it at their normal size; each
-- grid icon is a pin of its own layer (a proxy at its cell, standing for the real entry), so its tooltip and
-- click are its layer's. Clicking elsewhere, Escape, a zoom or a pan away closes the grid.
--
-- Membership is worked out per zoom band (a DRIFT: Members), from each source's own fill with a collecting put
-- (the whole instance, not a layout's region), at most once a frame and band: a source's put drops its
-- clustered members (Hides), and each source's rev moves with the membership (Rev), so a change lays them out
-- again. The collected members sit in reused arrays: only the clustered ones allocate. Pills and the grid are
-- Engine layers over pooled frames (Engine.Get), placed with Engine.At.

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Engine, Pins, Window, Camera = UI.Engine, UI.Pins, UI.Window, UI.Camera
local Yield = Runtime.Yield

local RANGE = 18 -- px: pins whose centres are closer than this overlap (about one icon)
local MIN = 4 -- pins in a seed's neighbourhood (the seed included): more than 3 make a cluster
local SHOWN = 3 -- icons in a pill, then "+N"
local PILL_H, ICON, GAP, PAD, MORE_W = 18, 12, 2, 4, 22 -- px: the pill's height, its icons, the gaps, its side padding, the "+N" slot
local CELL, COLS, PANEL_PAD, PANEL_GAP, PANEL_R = 24, 6, 6, 4, 6 -- px: the grid's cell, its columns, its padding, its gap above the pill, its corner radius
local BG = { 0, 0, 0, 0.72 } -- the backings: dark, translucent
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- Pins.lua's disc
local PILL_LEVEL, GRID_LEVEL = 16, 17 -- above the pins (11-15), the grid above the pills
local DRIFT = 1.25 -- the zoom bands membership is worked out for (Engine's DRIFT); the grid closes this far from where it opened
local LOG_BAND = math.log(DRIFT)
local K = 2 ^ 20 -- a cell's key: col * K + row
-- A member is an array (less than a table of names): its slots.
local E, LOOK, MINZ, SRC, COL, ROW, PX, SMALL = 1, 2, 3, 4, 5, 6, 7, 8 -- the entry, its look, its minimum zoom, its source, its centre, its grid pin, its icon's look

local Cluster = {}
UI.Cluster = Cluster

local sources = {} -- { name, fill, rev, lo (its layer on, at the last Stamp), r (its rev then) }
local setting -- UI.saved.cluster: grouping on
local stamp, stampFrame = 0, -1 -- the membership's counter, the frame it was last read in
local openV = 0 -- the grid's state's counter (a rev of the pill and grid layers)
local open -- the grid open: { key, col, row, zoom, set } (its cluster's key, its centroid, the zoom, its members' entries)
local cache = { stamp = nil, inst = nil, byBand = {}, n = 0 }

---------------------------------------------------------------------------
-- Membership
---------------------------------------------------------------------------

-- Moves when the setting, a source's rev or its layer's toggle does (read once a frame).
local REGROUP, regrouped = 0.5, -math.huge
local function Stamp()
	local f = Runtime.frames
	if f == stampFrame then return stamp end
	stampFrame = f
	local on = UI.saved.cluster ~= false
	local changed = on ~= setting
	setting = on
	local moved = false -- a source's own rev: grouped again REGROUP s at most after the last time
	for _, s in ipairs(sources) do
		local lo = Engine.LayerOn(s.name)
		if lo ~= s.lo then s.lo, changed = lo, true end
		if s.rev() ~= s.r then moved = true end
	end
	local now = GetTime()
	if changed or (moved and now - regrouped >= REGROUP) then
		for _, s in ipairs(sources) do s.r = s.rev() end
		regrouped, stamp = now, stamp + 1
	end
	return stamp
end

-- A rev (Engine.Layer's) moving with rev (a source's own, if any), the membership, and with the grid's state
-- when withGrid.
local function Rev(rev, withGrid)
	local a, s, o, n = nil, nil, nil, 0
	return function()
		local r, st, ov = rev and rev(), Stamp(), withGrid and openV or 0
		if r ~= a or st ~= s or ov ~= o then a, s, o, n = r, st, ov, n + 1 end
		return n
	end
end

-- A grid layer's rev: moves with the grid's state, and with the membership only while a grid is open (else
-- there's nothing for it to lay out).
local function GridRev()
	local s, o, n = nil, nil, 0
	return function()
		local st = open and Stamp() or 0
		if st ~= s or openV ~= o then s, o, n = st, openV, n + 1 end
		return n
	end
end

-- Scratch, reused: the members collected (ent, look, minz, srcs, cols, rows: n of them), the grid's buckets
-- (bucket[h]: a hashed cell's last member, nxt: the one before it, 0 for none; ck: a member's cell key), the
-- greedy pass's marks (takenGen = gen; near: a seed's neighbours). A fixed array, cleared on the way out.
local BUCKETS = 512
local ent, look, minz, srcs, cols, rows, n = {}, {}, {}, {}, {}, {}, 0
local bucket, nxt, ck, takenGen, near = {}, {}, {}, {}, {}
local gen = 0
local inst_, zoom_, src_ -- the collection in hand

local function want(minZoom) return Engine.From(zoom_, minZoom) end

-- The collecting put a source's fill calls: the instance's entries, each once.
local function put(e, l, minZoom)
	if e.pos.inst == inst_ and (not minZoom or want(minZoom)) then
		n = n + 1
		ent[n], look[n], minz[n], srcs[n], cols[n], rows[n] = e, l, minZoom, src_, e.pos.col, e.pos.row
	end
end

-- Every member of the sources at zoom in inst, into the scratch arrays.
local function Collect(inst, zoom)
	n, inst_, zoom_ = 0, inst, zoom
	for _, s in ipairs(sources) do
		if s.lo then
			src_ = s
			s.fill(put, inst, zoom, want)
		end
	end
	src_ = nil
end

-- A cluster of m members (near[1..m], scratch): its members, its centroid, its key (the least of its members'
-- keys); c.hidden: each member's entry -> it.
local clPool, listPool, memPool = {}, {}, {} -- retired clusters, their member lists and members, made again
local function Make(c, m)
	local col, row, members, key = 0, 0, table.remove(listPool) or {}, nil
	for t = 1, m do
		local j = near[t]
		takenGen[j] = gen
		local mem = table.remove(memPool) or {}
		mem[1], mem[2], mem[3], mem[4], mem[5], mem[6], mem[7], mem[8] = ent[j], look[j], minz[j], srcs[j], cols[j], rows[j], false, false
		members[t] = mem
		col, row = col + cols[j], row + rows[j]
		local k = tostring(ent[j].key)
		if not key or k < key then key = k end
	end
	local cl = table.remove(clPool) or {}
	cl.key, cl.col, cl.row, cl.members = key, col / m, row / m, members -- /: never 0 (m >= MIN)
	c.clusters[#c.clusters + 1] = cl
	local hidden = c.hidden
	for _, mem in ipairs(members) do hidden[mem[E]] = cl end
end

-- The clusters of the collection, at zoom, into c: from each member not yet taken, the untaken members within
-- RANGE px of it (itself included), in its 3x3 buckets; MIN or more make a cluster. Buckets are RANGE px square,
-- so O(n) a zoom, and the scratch is cleared on the way out.
local function Group(zoom, c)
	local cell = RANGE / zoom -- tiles; /: never 0 (a zoom is > 0)
	local r2 = cell * cell
	gen = gen + 1
	for i = 1, n do
		local cx, cy = math.floor(cols[i] / cell), math.floor(rows[i] / cell) -- /: never 0 (cell > 0)
		local h = (cx * 31 + cy) % BUCKETS + 1
		ck[i] = cx * K + cy
		nxt[i] = bucket[h] or 0
		bucket[h] = i
	end
	for i = 1, n do
		if takenGen[i] ~= gen then
			local cx, cy = math.floor(cols[i] / cell), math.floor(rows[i] / cell) -- /: never 0 (cell > 0)
			local m = 0
			for dc = -1, 1 do
				for dr = -1, 1 do
					local x, y = cx + dc, cy + dr
					local key = x * K + y
					local j = bucket[(x * 31 + y) % BUCKETS + 1]
					while j and j ~= 0 do
						if ck[j] == key and takenGen[j] ~= gen and (cols[j] - cols[i]) ^ 2 + (rows[j] - rows[i]) ^ 2 < r2 then
							m = m + 1
							near[m] = j
						end
						j = nxt[j]
					end
				end
			end
			if m >= MIN then Make(c, m) end
		end
	end
	for h = 1, BUCKETS do bucket[h] = nil end
end

-- The clusters at zoom in inst, and hidden: each clustered member's entry -> its cluster. Worked out once a
-- frame for each zoom band asked for (a few kept).
-- A band's table, retired: emptied and kept for the next band (its hash kept, not made again).
local spare = {} -- (kept at SPARE most)
local SPARE = 8
local function Retire(c)
	for k in pairs(c.hidden) do c.hidden[k] = nil end
	for i = #c.clusters, 1, -1 do
		local cl = c.clusters[i]
		local members = cl.members
		for t = #members, 1, -1 do
			memPool[#memPool + 1] = members[t]
			members[t] = nil
		end
		listPool[#listPool + 1] = members
		cl.members = nil
		clPool[#clPool + 1] = cl
		c.clusters[i] = nil
	end
	if #spare < SPARE then spare[#spare + 1] = c end
end

local function RetireAll()
	for b, c in pairs(cache.byBand) do
		Retire(c)
		cache.byBand[b] = nil
	end
	cache.n = 0
end

local function Members(inst, zoom)
	local st = Stamp()
	if cache.stamp ~= st or cache.inst ~= inst then
		RetireAll()
		cache.stamp, cache.inst = st, inst
	end
	local b = math.floor(math.log(zoom) / LOG_BAND + 0.5) -- /: never 0 (LOG_BAND > 0)
	local c = cache.byBand[b]
	if c then return c end
	c = table.remove(spare) or { clusters = {}, hidden = {} }
	if setting then
		local z = DRIFT ^ b
		Collect(inst, z)
		Group(z, c)
	end
	if cache.n >= 6 then RetireAll() end
	cache.byBand[b], cache.n = c, cache.n + 1
	return c
end

-- The grid's cluster at zoom in inst, while it's open (nil: none).
local function OpenAt(inst, zoom)
	if not open then return nil end
	for _, cl in ipairs(Members(inst, zoom).clusters) do
		if cl.key == open.key then return cl end
	end
end

-- Pins.Layer's put: whether e (of a clustered layer) stands in a pill at this layout's zoom, not on its own.
function Cluster.Hides(e, inst, zoom)
	return Members(inst, zoom).hidden[e] ~= nil
end

---------------------------------------------------------------------------
-- Drawing: backings, pills, the grid
---------------------------------------------------------------------------

-- A texture on the map: unsnapped (the map moves by fractions of a pixel, as Pins' Tex).
local function Tex(f, layer)
	local t = f:CreateTexture(nil, layer)
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

local function Place(t, f, x, y, w, h)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
	t:SetSize(w, h)
end

-- A rounded backing of w by h px (corner radius r) on frame f: four corner discs and three bands. Re-placed
-- only when its size changes.
local function Backing(f, w, h, r)
	if f.bkw == w and f.bkh == h then return end
	f.bkw, f.bkh = w, h
	local t = f.bk
	if not t then
		t = {}
		for _, name in ipairs({ "tl", "tr", "bl", "br" }) do
			t[name] = Tex(f, "BACKGROUND")
			t[name]:SetTexture(CIRCLE)
			t[name]:SetVertexColor(BG[1], BG[2], BG[3], BG[4])
		end
		for _, name in ipairs({ "mid", "left", "right" }) do
			t[name] = Tex(f, "BACKGROUND")
			t[name]:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
		end
		f.bk = t
	end
	local d = 2 * r
	Place(t.tl, f, 0, 0, d, d)
	Place(t.tr, f, w - d, 0, d, d)
	Place(t.bl, f, 0, h - d, d, d)
	Place(t.br, f, w - d, h - d, d, d)
	Place(t.mid, f, r, 0, w - d, h)
	Place(t.left, f, 0, r, r, h - d)
	Place(t.right, f, w - r, r, r, h - d)
end

local function MakeFrame(c)
	return CreateFrame("Frame", nil, c)
end

local function MakePill(c)
	local p = MakeFrame(c)
	p.icons = {}
	return p
end

-- A member's icon look at ICON px (Pins.Style's), made once for it.
local function Small(m)
	local s = m[SMALL]
	if not s then
		s = { size = ICON, icon = m[LOOK].icon }
		m[SMALL] = s
	end
	return s
end

-- A pill's width for n members.
local function PillWidth(n)
	local shown = math.min(n, SHOWN)
	return 2 * PAD + shown * ICON + (shown - 1) * GAP + (n > shown and GAP + MORE_W or 0)
end

-- A pill for cluster cl on region p: its backing, its first icons in a line (each a pin's look at ICON px,
-- Pins.Style), the "+N".
local function LayPill(p, cl)
	local n = #cl.members
	local shown = math.min(n, SHOWN)
	local w = PillWidth(n)
	p.cluster = cl
	if p.w ~= w then
		p.w, p.h = w, PILL_H
		p:SetSize(w, PILL_H)
		Backing(p, w, PILL_H, PILL_H / 2)
	end
	for i = 1, shown do
		local icon = p.icons[i]
		if not icon then
			icon = Pins.Make(p) -- (its place: fixed by its index, once)
			icon:SetPoint("CENTER", p, "LEFT", PAD + ICON / 2 + (i - 1) * (ICON + GAP), 0)
			p.icons[i] = icon
		end
		Pins.Style(icon, Small(cl.members[i]))
		if not icon.vis then icon:Show(); icon.vis = true end
	end
	for i = shown + 1, #p.icons do
		local icon = p.icons[i]
		if icon.vis then icon:Hide(); icon.vis = false end
	end
	if n > shown then
		local fs = p.more
		if not fs then
			fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
			fs:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
			p.more = fs
		end
		if p.moreN ~= n then
			p.moreN = n
			fs:SetText("+" .. (n - shown))
		end
		fs:Show()
	elseif p.more then
		p.more:Hide()
	end
end

-- The grid for n members: its dy (its centre, px down from the pill's centre: above it), its box, its columns.
local function Panel(n)
	local cols_ = math.min(n, COLS)
	local rows_ = math.ceil(n / cols_) -- /: never 0 (n >= 1)
	local w, h = 2 * PANEL_PAD + cols_ * CELL, 2 * PANEL_PAD + rows_ * CELL
	return -(PILL_H / 2 + PANEL_GAP + h / 2), w, h, cols_
end

-- Member k's cell's centre in the grid: px from the pill's centre.
local function Cell(k, cols_, w, h, dy)
	local r = math.floor((k - 1) / cols_) -- /: never 0 (cols_ >= 1)
	local c = (k - 1) % cols_ -- %: never 0 (cols_ >= 1)
	return -w / 2 + PANEL_PAD + (c + 0.5) * CELL, dy - h / 2 + PANEL_PAD + (r + 0.5) * CELL
end

local function Inside(cl, c0, r0, c1, r1)
	return cl.col >= c0 and cl.col <= c1 and cl.row >= r0 and cl.row <= r1
end

local function Build(c, inst, zoom, c0, r0, c1, r1)
	local M = Members(inst, zoom)
	local k = 0
	for _, cl in ipairs(M.clusters) do
		if Inside(cl, c0, r0, c1, r1) then
			local p = Engine.Get(c, "pill", "tex", MakePill)
			LayPill(p, cl)
			if p.acol ~= cl.col or p.arow ~= cl.row or p.az ~= c.zoom or p.on ~= c then
				Engine.At(c, p, "CENTER", cl.col, cl.row, 0, 0) -- (placed where it stands already: as Pins' Set)
			end
			k = k + 1
			if k % 4 == 0 then Yield() end -- (a pill new to the pool makes ~10 regions: a few a stretch)
		end
	end
	local cl = OpenAt(inst, zoom)
	if cl and Inside(cl, c0, r0, c1, r1) then
		local dy, w, h = Panel(#cl.members)
		local g = Engine.Get(c, "grid", "tex", MakeFrame)
		if g.w ~= w or g.h ~= h then
			g.w, g.h = w, h
			g:SetSize(w, h)
			Backing(g, w, h, PANEL_R)
		end
		Engine.At(c, g, "CENTER", cl.col, cl.row, 0, dy)
	end
	return #M.clusters == 0 or nil
end

---------------------------------------------------------------------------
-- The grid's pins: each member a pin of its source's layer, at its cell
---------------------------------------------------------------------------

-- A member's grid pin: a proxy standing for the entry, placed at (col, row); Pins reads its pos and key, and
-- the layer's opts get the entry itself (Wrap). Made once for the member.
local function Proxy(m, col, row)
	local p = m[PX]
	if not p then
		p = { real = m[E], key = m[E].key, pos = { inst = m[E].pos.inst } }
		m[PX] = p
	end
	p.pos.col, p.pos.row = col, row
	return p
end

-- A grid layer's fill for source s: the open cluster's members of s, each at its cell.
local function GridFill(s)
	return function(put_, inst, zoom)
		local cl = OpenAt(inst, zoom)
		if not cl then return end
		local dy, w, h, cols_ = Panel(#cl.members)
		for k, m in ipairs(cl.members) do
			if m[SRC] == s then
				local x, y = Cell(k, cols_, w, h, dy)
				put_(Proxy(m, cl.col + x / zoom, cl.row + y / zoom), m[LOOK], m[MINZ]) -- /: never 0 (a zoom is > 0)
			end
		end
	end
end

-- A source's opts for its grid layer: the same tooltip, hover and click, given the entry it stands for.
local function Wrap(o)
	local w = {
		lines = function(p)
			if o.lines then return o.lines(p.real) end
			return p.real.name, p.real.text
		end,
	}
	if o.tooltip then w.tooltip = function(tip, p) o.tooltip(tip, p.real) end end
	if o.hover then w.hover = function(p) o.hover(p and p.real) end end
	if o.click then w.click = function(p, button) o.click(p.real, button) end end
	return w
end

---------------------------------------------------------------------------
-- Layers, open and close
---------------------------------------------------------------------------

-- Pins.Layer's: a clustered layer (opts.cluster) is one of the sources. Returns its rev (its own, and the
-- membership's); its grid layer is made here.
function Cluster.Add(name, fill, rev, opts)
	local s = { name = name, fill = fill, rev = rev or function() return nil end }
	sources[#sources + 1] = s
	local grid = UI.Pins.Layer("grid " .. name, GRID_LEVEL, GridFill(s), GridRev(), Wrap(opts))
	grid.idle = function() return not open end -- (no layouts while no grid is open)
	return Rev(rev, false)
end

local pills = Engine.Layer("clusters", PILL_LEVEL, Build, Rev(nil, true), "pin")

local function Close()
	if open then
		open = nil
		openV = openV + 1
	end
end

local function Open(cl)
	local set = {}
	for _, m in ipairs(cl.members) do set[m[E]] = true end
	open = { key = cl.key, col = cl.col, row = cl.row, zoom = Camera.cam.zoom, set = set }
	openV = openV + 1
end

-- The pill under the view's point (px from its centre): its cluster, or nil.
local function PillAt(x, y)
	local cam = Camera.cam
	local c = pills.front
	local p = c and c.alpha > 0 and c.pools.pill
	for i = 1, p and p.n or 0 do
		local o = p[i]
		local dx, dy = (o.acol - cam.cx) * cam.zoom - x, (o.arow - cam.cy) * cam.zoom - y
		if math.abs(dx) <= o.w / 2 and math.abs(dy) <= o.h / 2 then return o.cluster end
	end
end

-- Pins.Tap's, first: a click on a pill opens its grid (or closes it, again). Else a click off the grid
-- closes it (a click on one of its pins is theirs: false). True when the click was the pill's.
function Cluster.Tap(button)
	local x, y = Window.Cursor()
	local w, h = Window.Size()
	local cl = PillAt(x - w / 2, y - h / 2)
	if cl then
		if open and open.key == cl.key then Close() else Open(cl) end
		return true
	end
	if open then
		local e = Pins.Hovered()
		local real = e and rawget(e, "real")
		if not (real and open.set[real]) then Close() end
	end
	return false
end

-- The grid closes on Escape, a zoom or pan away from where it opened, or the setting off. Looked at each
-- frame from the controls' step (ui/Controls.lua: a step of its own costs its probes every frame).
function Cluster.Watch()
	if not open then return end
	local cam = Camera.cam
	local w, h = Window.Size()
	local escape = false
	for _, hk in ipairs(Model.hooked) do
		if hk.kind == "escape" then escape = true end
	end
	local s = cam.zoom / open.zoom -- /: never 0 (a zoom is > 0)
	local far = s > DRIFT or s < 1 / DRIFT
	local off = math.abs((open.col - cam.cx) * cam.zoom) > w / 2 or math.abs((open.row - cam.cy) * cam.zoom) > h / 2
	if far or off or escape or not setting then Close() end
end

-- Interiors (docs/decisions/0008-interiors.md): buildings' indoor minimap pictures over the terrain tiles,
-- under quest areas and pins: an Engine layer at level 2 (over the tiles' 1, under the areas' 3), "scale" like
-- the tiles, so a zoom or pan moves its canvas. Which buildings: the one you're in on the map shown
-- (Model.interior, Game's); with City maps on (gear -> Map) and the map big, every building of the capital
-- you're in, or else of the one at the view's centre (Atlas.City), indoors or out. The terrain dimmed x0.35 only while you're in a building. The prototype's
-- drawing (docs/evidence/indoors/addon/Test.lua): each picture a parallelogram drawn as the axis-aligned box
-- around it, the box's corner texture coordinates solved for, CLAMPTOBLACKADDITIVE so outside the picture is
-- clear. By level from your floor (real floors, world height, so buildings compare): rooms on yours (within
-- 22 yd) whole; another faded below (x0.35) or ghosted above (x0.15) only where it overlaps a room on your
-- level, else whole. Outdoors your level is the surface: underground rooms faded where they're under it,
-- the rest whole; a city looked at from away, whole. Drawn
-- below, then above, then the rest by floor, your room (or every candidate) over every other room. The
-- boxes are worked out once a building; a new Model.interior or city (the layer's rev) lays it out again.
-- Nothing to draw: the layer idle, the tiles as they are.

local _, ns = ...
local UI, Model, Atlas, Runtime = ns.UI, ns.Model, ns.Atlas, ns.Runtime
local Engine, Camera = UI.Engine, UI.Camera
local Get, Keep, Yield = Engine.Get, Engine.Keep, Runtime.Yield

local DIM = 0.35 -- the terrain under a building (Test.lua's opt.dim): a black veil at 1 - DIM
local LEVEL = 22 -- yd: a room's floor within this of yours is on your level (Test.lua's opt.cull, tuned in Ironforge)
local BELOW, ABOVE = 0.35, 0.15 -- the alpha of rooms on levels below yours (faded) and above (ghosted)
local MINE = 7 -- the sublevel of your room's pictures, over every other room's (Test.lua's)
local STEP = 16 -- yd of floor a sublevel
local TEXELS = 1600 / 3 * 2 -- a picture's pixels a tile unit (2 a yard)
local CAPITALS = { 1453, 1454, 1455, 1456, 1457, 1458 }

-- Inside a capital's map rect (not by uiMap: in the Ruins of Lordaeron, over Undercity, the client likely
-- says Tirisfal Glades).
local function In(id, inst, col, row)
	local r = Atlas.MapRect(id)
	return r.inst == inst and col >= r.col0 and col <= r.col1 and row >= r.row0 and row <= r.row1
end

-- With City maps on and the map big (Atlas.City): the capital you're in on the map shown, here true; else
-- the one at the view's centre, here false (looked at from away). Else nil.
local function City()
	if not (UI.BigMap.big and Engine.LayerOn("cities")) then return end
	local y, inst, cam = Model.you, Camera.inst, Camera.cam
	for _, id in ipairs(CAPITALS) do
		if y.col and y.inst == inst and In(id, inst, y.col, y.row) then return Atlas.City(inst, id), true end
	end
	for _, id in ipairs(CAPITALS) do
		if In(id, inst, cam.cx, cam.cy) then return Atlas.City(inst, id), false end
	end
end

-- What's drawn: { i = Model.interior on the map shown, or nil; c, here = City() }, the same table while
-- they are; false: nothing.
local scene = false
local function Scene()
	local i, c, here = Model.interior, City()
	if not (i and i.inst == Camera.inst) then i = nil end
	if not (i or c) then
		scene = false
	elseif not scene or scene.i ~= i or scene.c ~= c or scene.here ~= here then
		scene = { i = i, c = c, here = here }
	end
	return scene
end

-- A building's pictures, placed: { [n] = { fid, key, room, x0, y0, x1, y1, uv (8) } }, the box in tile
-- units, kept. The texture coordinates are inset half a pixel, so a picture's edge samples its own pixels,
-- not the clear outside: no hairline at the seams between a room's 128-yd blocks.
local built = {} -- [building]
local function Built(b)
	if built[b] then return built[b] end
	local out = {}
	for room, r in pairs(b.rooms) do
		for _, p in ipairs(r.pics) do
			local fid, ox, oy, ux, uy, vx, vy = p[1], p[2], p[3], p[4], p[5], p[6], p[7]
			local x0, x1 = math.min(ox, ox + ux, ox + vx, ox + ux + vx), math.max(ox, ox + ux, ox + vx, ox + ux + vx)
			local y0, y1 = math.min(oy, oy + uy, oy + vy, oy + uy + vy), math.max(oy, oy + uy, oy + vy, oy + uy + vy)
			local det = ux * vy - vx * uy
			local hu = 0.5 / (math.sqrt(ux * ux + uy * uy) * TEXELS) -- /: never 0 (a picture has width)
			local hv = 0.5 / (math.sqrt(vx * vx + vy * vy) * TEXELS) -- /: never 0 (and height)
			local function U(x, y) return hu + (1 - 2 * hu) * ((x - ox) * vy - vx * (y - oy)) / det end -- /: never 0 (a picture's edges aren't parallel)
			local function V(x, y) return hv + (1 - 2 * hv) * (ux * (y - oy) - (x - ox) * uy) / det end -- /: never 0 (as U's)
			out[#out + 1] = { fid = fid, key = b.key, room = room, x0 = x0, y0 = y0, x1 = x1, y1 = y1,
				uv = { U(x0, y0), V(x0, y0), U(x0, y1), V(x0, y1), U(x1, y0), V(x1, y0), U(x1, y1), V(x1, y1) } }
			if #out % 32 == 0 then Yield() end
		end
	end
	built[b] = out
	return out
end

local function Has(list, v)
	for _, x in ipairs(list) do if x == v then return true end end
	return false
end

-- The scene's buildings (Atlas.Building): the city's, and the one you're in if it isn't one.
local function Buildings(s, inst)
	local out = {}
	for _, key in ipairs(s.c and s.c.buildings or out) do
		out[#out + 1] = Atlas.Building(inst, key)
		Yield()
	end
	if s.i and not (s.c and Has(s.c.buildings, s.i.building)) then out[#out + 1] = Atlas.Building(inst, s.i.building) end
	return out
end

-- Sublevel from a floor f, ref yd down: n sublevels from first.
local function By(f, ref, first, n)
	return first + math.max(0, math.min(n - 1, math.floor((f - ref) / STEP)))
end

-- Each room's look, [key][room] = { alpha, sublevel }. In a building (s.i): on your level whole, by floor;
-- another overlapping (its over, the city's over) one on your level faded below, ghosted above; the rest
-- whole; yours on top. Outdoors in the city: an underground room faded where it's under one above ground
-- (its over), the rest whole. A city looked at from away (not s.here): every room whole, by floor.
local NONE = {}
local function Looks(s, list)
	local i, c, looks = s.i, s.c, {}
	local yours = i and i.floor
	if not i then -- the surface's floor: the mean of the rooms above ground (by which the rest go)
		local sum, n = 0, 0
		for _, b in ipairs(list) do
			for _, r in pairs(b.rooms) do
				if not r.underground then sum, n = sum + r.floor, n + 1 end
			end
		end
		yours = n > 0 and sum / n or 0 -- /: never 0 (n > 0)
	end
	local function On(b, room) return math.abs(b.rooms[room].floor - yours) <= LEVEL end
	local byKey = {}
	for _, b in ipairs(list) do byKey[b.key] = b end
	for _, b in ipairs(list) do
		local l, cross = {}, c and c.over[b.key]
		local away = c and not s.here and Has(c.buildings, b.key)
		for room, r in pairs(b.rooms) do
			local f, near, under = r.floor, false, false
			if away then -- (whole)
			elseif i and not On(b, room) then
				for _, o in ipairs(r.over) do near = near or On(b, o) end
				for _, o in ipairs(cross and cross[room] or NONE) do near = near or byKey[o[1]] ~= nil and On(byKey[o[1]], o[2]) end
			elseif not i and r.underground then
				for _, o in ipairs(r.over) do under = under or not b.rooms[o].underground end
			end
			if i and b.key == i.building and Has(i.rooms, room) then
				l[room] = { 1, MINE }
			elseif near and f < yours or under then
				l[room] = { BELOW, By(f, yours - LEVEL - 4 * STEP, -8, 5) }
			elseif near then
				l[room] = { ABOVE, By(f, yours + LEVEL, -3, 3) }
			else
				l[room] = { 1, By(f, yours - 3 * STEP, 0, 7) }
			end
		end
		looks[b.key] = l
		Yield()
	end
	return looks
end

local function Tex(c)
	local t = c:CreateTexture(nil, "ARTWORK")
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

local function Veil(c)
	local t = Tex(c)
	t:SetDrawLayer("BACKGROUND")
	t:SetColorTexture(0, 0, 0, 1 - DIM)
	return t
end

-- Picture p as its box at zoom on canvas c, looking as its room does (Looks).
local function Pic(c, t, p, zoom, look)
	if t.e == c.epoch then return end
	if t.fid ~= p.fid then
		t:SetTexture(p.fid, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		t.fid = p.fid
	end
	local uv = p.uv
	t:SetTexCoord(uv[1], uv[2], uv[3], uv[4], uv[5], uv[6], uv[7], uv[8])
	t:SetAlpha(look[1])
	t:SetDrawLayer("ARTWORK", look[2])
	t:SetPoint("TOPLEFT", c, "TOPLEFT", (p.x0 - c.ox) * zoom, -(p.y0 - c.oy) * zoom)
	t:SetSize((p.x1 - p.x0) * zoom, (p.y1 - p.y0) * zoom)
	t.e = c.epoch
end

local left, nleft = {}, 0 -- the pictures no region on the canvas showed: placed after the rest (Tiles.lua's)

local layer = Engine.Layer("interiors", 2, function(c, inst, zoom, c0, r0, c1, r1)
	local s = Scene()
	if not s then return true end
	if s.i then
		local veil = Get(c, "veil", "tex", Veil)
		veil:SetPoint("TOPLEFT", c, "TOPLEFT", (c0 - c.ox) * zoom, -(r0 - c.oy) * zoom)
		veil:SetSize((c1 - c0) * zoom, (r1 - r0) * zoom)
	end
	if not s.looks then
		s.list = Buildings(s, inst)
		s.looks = Looks(s, s.list)
	end
	nleft = 0
	local n = 0
	for _, b in ipairs(s.list) do
		local looks = s.looks[b.key]
		for _, p in ipairs(Built(b)) do
			if p.x1 > c0 and p.x0 < c1 and p.y1 > r0 and p.y0 < r1 then
				local t = Keep(c, "pic", p)
				if t then
					Pic(c, t, p, zoom, looks[p.room])
				else
					nleft = nleft + 1
					left[nleft] = p
				end
			end
			n = n + 1
			if n % 32 == 0 then Yield() end
		end
		Yield()
	end
	for k = 1, nleft do
		local p = left[k]
		local t = Get(c, "pic", "tex", Tex, p)
		t.e = nil
		Pic(c, t, p, zoom, s.looks[p.key][p.room])
		if k % 16 == 0 then Yield() end
	end
end, Scene)
layer.idle = function() return not Scene() end
layer.City = City -- (ui/Labels.lua: the city's area names)
UI.Interiors = layer

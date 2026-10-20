-- Interiors (docs/decisions/0008-interiors.md): while you're in a building on the map shown (Model.interior,
-- Game's), its rooms' indoor minimap pictures over the terrain tiles, dimmed x0.35, under quest areas and
-- pins: an Engine layer at level 2 (over the tiles' 1, under the areas' 3), "scale" like the tiles, so a
-- zoom or pan moves its canvas. The prototype's drawing (docs/evidence/indoors/addon/Test.lua): each
-- picture a parallelogram drawn as the axis-aligned box around it, the box's corner texture coordinates
-- solved for, CLAMPTOBLACKADDITIVE so outside the picture is clear; a room whose floor is over 22 yd above
-- yours hidden; drawn by floor, yours (or every candidate) over every other room. The boxes are worked out
-- once a building; a room change (a new Model.interior: the layer's rev) lays it out again. Out of every
-- building the layer is idle: nothing drawn, the tiles as they are.

local _, ns = ...
local UI, Model, Atlas, Runtime = ns.UI, ns.Model, ns.Atlas, ns.Runtime
local Engine, Camera = UI.Engine, UI.Camera
local Get, Keep, Yield = Engine.Get, Engine.Keep, Runtime.Yield

local DIM = 0.35 -- the terrain under a building (Test.lua's opt.dim): a black veil at 1 - DIM
local CULL = 22 -- yd: a room's floor this far over yours, hidden (Test.lua's opt.cull, tuned in Ironforge)
local MINE = 7 -- the sublevel of your room's pictures, over every other room's (Test.lua's)

-- Model.interior when it's a building on the map shown; else nil.
local function Here()
	local i = Model.interior
	if i and i.inst == Camera.inst then return i end
end

-- A building's pictures, placed: { b = building, [n] = { fid, room, zmin, sub, x0, y0, x1, y1, uv (8) } },
-- the box in tile units. The last building's only.
local built
local function Built(i)
	local b = Atlas.Building(i.inst, i.building)
	if built and built.b == b then return built end
	built = { b = b }
	for room, r in pairs(b.rooms) do
		local sub = math.max(-8, math.min(6, math.floor((r.zmin + 140) / 16) - 8)) -- by floor (Test.lua's)
		for _, p in ipairs(r.pics) do
			local fid, ox, oy, ux, uy, vx, vy = p[1], p[2], p[3], p[4], p[5], p[6], p[7]
			local x0, x1 = math.min(ox, ox + ux, ox + vx, ox + ux + vx), math.max(ox, ox + ux, ox + vx, ox + ux + vx)
			local y0, y1 = math.min(oy, oy + uy, oy + vy, oy + uy + vy), math.max(oy, oy + uy, oy + vy, oy + uy + vy)
			local det = ux * vy - vx * uy
			local function U(x, y) return ((x - ox) * vy - vx * (y - oy)) / det end -- /: never 0 (a picture's edges aren't parallel)
			local function V(x, y) return (ux * (y - oy) - (x - ox) * uy) / det end -- /: never 0 (as U's)
			built[#built + 1] = { fid = fid, room = room, zmin = r.zmin, sub = sub, x0 = x0, y0 = y0, x1 = x1, y1 = y1,
				uv = { U(x0, y0), V(x0, y0), U(x0, y1), V(x0, y1), U(x1, y0), V(x1, y0), U(x1, y1), V(x1, y1) } }
		end
	end
	return built
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

local function Has(list, v)
	for _, x in ipairs(list) do if x == v then return true end end
	return false
end

-- Picture p as its box at zoom on canvas c, from your room's (or every candidate's) sublevel if mine.
local function Pic(c, t, p, zoom, mine)
	if t.e == c.epoch then return end
	if t.fid ~= p.fid then
		t:SetTexture(p.fid, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		t.fid = p.fid
	end
	local uv = p.uv
	t:SetTexCoord(uv[1], uv[2], uv[3], uv[4], uv[5], uv[6], uv[7], uv[8])
	t:SetDrawLayer("ARTWORK", mine and MINE or p.sub)
	t:SetPoint("TOPLEFT", c, "TOPLEFT", (p.x0 - c.ox) * zoom, -(p.y0 - c.oy) * zoom)
	t:SetSize((p.x1 - p.x0) * zoom, (p.y1 - p.y0) * zoom)
	t.e = c.epoch
end

local left, nleft = {}, 0 -- the pictures no region on the canvas showed: placed after the rest (Tiles.lua's)

local layer = Engine.Layer("interiors", 2, function(c, _, zoom, c0, r0, c1, r1)
	local i = Here()
	if not i then return true end
	local veil = Get(c, "veil", "tex", Veil)
	veil:SetPoint("TOPLEFT", c, "TOPLEFT", (c0 - c.ox) * zoom, -(r0 - c.oy) * zoom)
	veil:SetSize((c1 - c0) * zoom, (r1 - r0) * zoom)
	local set, top = Built(i), i.floor + CULL
	nleft = 0
	for n, p in ipairs(set) do
		if p.zmin <= top and p.x1 > c0 and p.x0 < c1 and p.y1 > r0 and p.y0 < r1 then
			local t = Keep(c, "pic", n)
			if t then
				Pic(c, t, p, zoom, Has(i.rooms, p.room))
			else
				nleft = nleft + 1
				left[nleft] = n
			end
		end
		if n % 32 == 0 then Yield() end
	end
	for k = 1, nleft do
		local n = left[k]
		local t = Get(c, "pic", "tex", Tex, n)
		t.e = nil
		Pic(c, t, set[n], zoom, Has(i.rooms, set[n].room))
		if k % 16 == 0 then Yield() end
	end
end, function() return Here() or false end)
layer.idle = function() return not Here() end
UI.Interiors = layer

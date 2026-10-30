-- Clouds over the map's broken art (Data/Clouds.lua, tools/gen_clouds.py): the unfinished land in Blizzard's
-- tiles (flat filler, stepped patches of other art, a seam) that the map review accepted,
-- under the game's own cloud, the adventure map's fog-of-war puff, stamped over and over, each sized, turned
-- and flipped. Laid out with the tiles (UI.Clouds.Lay, from ui/Tiles.lua's layout), on their canvas, so they
-- move, scale and fade with them; but on a frame of the canvas's own at level 7 (VEIL): over the borders (6),
-- so no border runs across a cloud, under the path (8) and the names (9). Not a layer of their own: most of
-- the map has none, and a layer's layouts would hold up the names and pins as the ground's do. Tinted to the
-- minimap's warm greys (TINT): white reads as a hole on the dark ground; thin (the puff's alpha), so the ground's
-- colour comes through. Kept by cloud (Engine.Keep).

local _, ns = ...
local UI = ns.UI
local Atlas, Engine, Window = ns.Atlas, ns.UI.Engine, ns.UI.Window
local Get, Keep, Px, Yield = Engine.Get, Engine.Keep, Engine.Px, ns.Runtime.Yield

local VEIL = 7
local TINT = { 0.78, 0.75, 0.68 }

local Clouds = {}
UI.Clouds = Clouds

-- A cloud's texture, on its canvas's veil frame (made the first time; home: where Engine puts it back).
local function CloudTex(c)
	local veil = c.veil
	if not veil then
		veil = CreateFrame("Frame", nil, c)
		veil:SetAllPoints()
		veil:SetFrameLevel(Window.view:GetFrameLevel() + VEIL)
		c.veil = veil
	end
	local t = veil:CreateTexture(nil, "ARTWORK")
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	t:SetVertexColor(TINT[1], TINT[2], TINT[3])
	t.home = veil
	return t
end

-- The puff's corners in its texture for each turn (0-3 quarter turns clockwise, +4 mirrored first), as
-- SetTexCoord takes them: UL, LL, UR, LR; and its height a width, upright (0) and turned (1). Built once.
local coords, tall
local function Puff(p)
	if coords then return coords, tall end
	local l, r, t, b = p.l / p.w, p.r / p.w, p.t / p.h, p.b / p.h -- /: never 0 (the puff's texture, Data/Clouds.lua)
	coords = {}
	for turn = 0, 7 do
		local cw = turn >= 4 and { r, t, l, t, l, b, r, b } or { l, t, r, t, r, b, l, b } -- UL, UR, LR, LL
		local k = turn % 4
		local function At(i) -- the texture corner shown at clockwise corner i: the one k back
			local j = (i - k) % 4
			return cw[2 * j + 1], cw[2 * j + 2]
		end
		local ulx, uly = At(0)
		local urx, ury = At(1)
		local lrx, lry = At(2)
		local llx, lly = At(3)
		coords[turn] = { ulx, uly, llx, lly, urx, ury, lrx, lry }
	end
	local aspect = (p.b - p.t) / (p.r - p.l) -- /: never 0 (the puff's rect, Data/Clouds.lua)
	tall = { [0] = aspect, 1 / aspect } -- /: never 0 (as above)
	return coords, tall
end

-- Cloud at (x, y), w by h (tiles), turn: kept as it stands while its canvas's epoch holds.
local function Cloud(c, t, p, zoom, x, y, w, h, turn, kept)
	if kept and t.e == c.epoch then return end
	if t.turn ~= turn then
		if not t.turn then
			t:SetTexture(p.file, "CLAMP", "CLAMP", "TRILINEAR")
			t:SetAlpha(p.alpha)
		end
		local q = Puff(p)[turn]
		t:SetTexCoord(q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8])
		t.turn = turn
	end
	local ox, oy = c.ox, c.oy
	local x0, y0 = Px(x - w / 2 - ox, zoom), Px(y - h / 2 - oy, zoom)
	t:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y0)
	t:SetSize(Px(x + w / 2 - ox, zoom) - x0, Px(y + h / 2 - oy, zoom) - y0)
	t.e = c.epoch
end

-- The clouds no region on the canvas showed: placed after the rest. Scratch, reused.
local pend, np = {}, 0

-- The clouds over the region (c0, r0)-(c1, r1) on the tiles' canvas c.
function Clouds.Lay(c, inst, zoom, c0, r0, c1, r1)
	local list, p = Atlas.Clouds(inst)
	if not list then return end
	local _, tall = Puff(p)
	np = 0
	for i = 1, #list, 4 do -- (a few hundred: no yield)
		local x, y, w, turn = list[i], list[i + 1], list[i + 2], list[i + 3]
		local h = w * tall[turn % 2]
		if x + w / 2 > c0 and x - w / 2 < c1 and y + h / 2 > r0 and y - h / 2 < r1 then
			local t = Keep(c, "cloud", i)
			if t then
				Cloud(c, t, p, zoom, x, y, w, h, turn, true)
			else
				np = np + 1
				pend[np] = i
			end
		end
	end
	for k = 1, np do
		local i = pend[k]
		local w, turn = list[i + 2], list[i + 3]
		Cloud(c, Get(c, "cloud", "tex", CloudTex, i), p, zoom, list[i], list[i + 1], w, w * tall[turn % 2], turn, false)
		if k % 32 == 0 then Yield() end
	end
end

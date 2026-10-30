-- The map's broken art rebuilt (Data/Fill.lua, tools/gen_fill.py): over the unfinished land in Blizzard's tiles that the map
-- review accepted, pieces of the game's own good ground, each drawn from its tile (SetTexture(fdid), a square of it by
-- SetTexCoord), toned by vertex colour, its edge softened and made irregular by a mask (Textures/FillMask*.tga). Laid out
-- with the tiles (UI.Fill.Lay, from ui/Tiles.lua's layout), on their canvas, so they move, scale and fade with them; on a
-- frame of the canvas's own, its pieces and masks together (home: where Engine puts them back). Neighbours overlap: a
-- piece's sublevel keeps them the same way up. Switched by Feel's "fill.on": Fill.Rev lays the tiles out anew.

local _, ns = ...
local UI = ns.UI
local Atlas, Engine, Runtime = ns.Atlas, ns.UI.Engine, ns.Runtime
local Get, Keep, Px, Yield = Engine.Get, Engine.Keep, Engine.Px, Runtime.Yield

local CHUNKS = 16 -- chunks a tile side
local STRIDE = 10 -- a piece's fields in the list
local BUDGET = 0.5 -- ms a frame for making pieces
local FLAT_BELOW = 96 -- px a tile

local Fill = {}
UI.Fill = Fill

local on, rev = true, 0
function Fill.Rev() return rev end
function Fill.Set(v)
	if v ~= on then on, rev = v, rev + 1 end
end

local function Tex(c)
	local frame = c.fill
	if not frame then
		frame = CreateFrame("Frame", nil, c)
		frame:SetAllPoints()
		frame:SetFrameLevel(c:GetFrameLevel() + 1) -- over its canvas: at its own level it would lie under the tiles
		c.fill = frame
	end
	local t = frame:CreateTexture(nil, "ARTWORK")
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	t.home = frame
	return t
end

-- A piece up close, its edge masked; far out (FLAT_BELOW), where the seam is a pixel or two, none: half the regions.
local function MaskedTex(c)
	local t = Tex(c)
	local mask = c.fill:CreateMaskTexture()
	mask:SetSnapToPixelGrid(false)
	mask:SetTexelSnappingBias(0)
	mask:SetAllPoints(t)
	t:AddMaskTexture(mask)
	t.mask = mask
	return t
end

-- Piece i of the list, kept as it stands while its canvas's epoch holds.
local function Piece(c, t, list, i, side, zoom, kept)
	if kept and t.e == c.epoch then return end
	if t.i ~= i then -- what it shows
		t:SetTexture(list[i + 2], "CLAMP", "CLAMP", "TRILINEAR")
		local sc, sr = list[i + 3], list[i + 4]
		t:SetTexCoord(sc / CHUNKS, (sc + side) / CHUNKS, sr / CHUNKS, (sr + side) / CHUNKS)
		t:SetVertexColor(list[i + 5], list[i + 6], list[i + 7])
		if t.mask then t.mask:SetTexture(Atlas.ROOT .. "Textures\\FillMask" .. list[i + 8], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
		t:SetDrawLayer("ARTWORK", list[i + 9])
		t.i = i
	end
	local col, row = list[i] / CHUNKS, list[i + 1] / CHUNKS
	local x0, y0 = Px(col - c.ox, zoom), Px(row - c.oy, zoom)
	t:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y0)
	t:SetSize(Px(col + side / CHUNKS - c.ox, zoom) - x0, Px(row + side / CHUNKS - c.oy, zoom) - y0)
	t.e = c.epoch
end

-- The pieces no region on the canvas showed: made by a job of their own once the layout has swapped its canvas in (a
-- piece is dear, its mask and all, and a layout holds up the view), so a new one comes in a frame or two late.
local pend, np, target, zoomAt, listAt, sideAt = {}, 0, nil, 0, nil, 0
local job = Runtime.Worker("map: fill", function()
	while true do
		local c, tiles = target, UI.Tiles
		local k = 1
		while k <= np and c == target and (tiles.front == c or tiles.back == c) do
			if tiles.front == c and not tiles.busy then
				local i = pend[k]
				local flat = zoomAt < FLAT_BELOW
				Piece(c, Get(c, flat and "fillFlat" or "fill", "tex", flat and Tex or MaskedTex, i), listAt, i, sideAt, zoomAt, false)
				k = k + 1
				Yield()
			else
				coroutine.yield()
			end
		end
		np = 0
		Runtime.Idle()
	end
end, BUDGET)

-- The pieces over the region (c0, r0)-(c1, r1) on the tiles' canvas c.
function Fill.Lay(c, inst, zoom, c0, r0, c1, r1)
	if not on then return end
	local list, side = Atlas.Fill(inst)
	if not list then return end
	local size = side / CHUNKS
	local kind = zoom < FLAT_BELOW and "fillFlat" or "fill"
	np, target, zoomAt, listAt, sideAt = 0, c, zoom, list, side
	local moved = 0
	for i = 1, #list, STRIDE do
		local col, row = list[i] / CHUNKS, list[i + 1] / CHUNKS
		if col + size > c0 and col < c1 and row + size > r0 and row < r1 then
			local t = Keep(c, kind, i)
			if t then
				if t.e ~= c.epoch then
					moved = moved + 1
					if moved % 16 == 0 then Yield() end -- (a moved region is dear)
				end
				Piece(c, t, list, i, side, zoom, true)
			else
				np = np + 1
				pend[np] = i
			end
		end
	end
	if np > 0 then Runtime.Wake(job, BUDGET) end
end

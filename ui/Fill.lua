-- Pieces of the game's own tiles over Blizzard's: each drawn from its tile (SetTexture(fdid), a square of it by SetTexCoord),
-- its mask its own texture (a soft edge, and only where it's wanted). Laid out with the tiles (Lay, from ui/Tiles.lua's
-- layout), on their canvas, so they move, scale and fade with them; on a frame of the canvas's own, its pieces and masks
-- together (home: where Engine puts them back). Two sets, switched by Feel (Rev lays the tiles out anew):
--   UI.Fill ("fill.on"): the unfinished land the map review accepted, rebuilt (Data/Fill.lua, tools/gen_fill.py), toned by
--     vertex colour. Neighbours overlap: a piece's sublevel keeps them the same way up.
--   UI.Seams ("seams.on"): the harsh straight edges softened (Data/Seams.lua, tools/gen_seams.py), a strip mirrored over its
--     line. Over the rebuilt ground.

local _, ns = ...
local UI = ns.UI
local Atlas, Engine, Runtime = ns.Atlas, ns.UI.Engine, ns.Runtime
local Get, Keep, Px, Yield = Engine.Get, Engine.Keep, Engine.Px, Runtime.Yield

local CHUNKS = 16 -- chunks a tile side
local BUDGET = 0.5 -- ms a frame for making pieces

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

-- A set of pieces: stride fields each in Source(inst)'s list; Box(list, i) their place (col, row, w, h: chunks); Show(t, list, i)
-- what one shows.
local function Set(kind, stride, Source, Box, Show)
	local set = {}
	local on, rev = true, 0
	function set.Rev() return rev end
	function set.Set(v)
		if v ~= on then on, rev = v, rev + 1 end
	end

	-- Piece i of the list, kept as it stands while its canvas's epoch holds.
	local function Piece(c, t, list, i, zoom, kept)
		if kept and t.e == c.epoch then return end
		if t.i ~= i then
			Show(t, list, i)
			t.i = i
		end
		local col, row, w, h = Box(list, i)
		col, row = col / CHUNKS, row / CHUNKS
		local x0, y0 = Px(col - c.ox, zoom), Px(row - c.oy, zoom)
		t:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y0)
		t:SetSize(Px(col + w / CHUNKS - c.ox, zoom) - x0, Px(row + h / CHUNKS - c.oy, zoom) - y0)
		t.e = c.epoch
	end

	-- The pieces no region on the canvas showed: made by a job of their own once the layout has swapped its canvas in (a
	-- piece is dear, its mask and all, and a layout holds up the view), so a new one comes in a frame or two late.
	local pend, np, target, zoomAt, listAt = {}, 0, nil, 0, nil
	local job = Runtime.Worker("map: " .. kind, function()
		while true do
			local c, tiles = target, UI.Tiles
			local k = 1
			while k <= np and c == target and (tiles.front == c or tiles.back == c) do
				if tiles.front == c and not tiles.busy then
					local i = pend[k]
					Piece(c, Get(c, kind, "tex", MaskedTex, i), listAt, i, zoomAt, false)
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
	function set.Lay(c, inst, zoom, c0, r0, c1, r1)
		if not on then return end
		local list = Source(inst)
		if not list then return end
		np, target, zoomAt, listAt = 0, c, zoom, list
		local moved = 0
		for i = 1, #list, stride do
			local col, row, w, h = Box(list, i)
			col, row = col / CHUNKS, row / CHUNKS
			if col + w / CHUNKS > c0 and col < c1 and row + h / CHUNKS > r0 and row < r1 then
				local t = Keep(c, kind, i)
				if t then
					if t.e ~= c.epoch then
						moved = moved + 1
						if moved % 16 == 0 then Yield() end -- (a moved region is dear)
					end
					Piece(c, t, list, i, zoom, true)
				else
					np = np + 1
					pend[np] = i
				end
			end
		end
		if np > 0 then Runtime.Wake(job, BUDGET) end
	end
	return set
end

local function Mask(t, name)
	t.mask:SetTexture(Atlas.ROOT .. "Textures\\" .. name, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
end

-- { col, row, file, sc, sr, r, g, b, mask, sub, ... }; every piece a square of Data/Fill.lua's side
local side = 0
UI.Fill = Set("fill", 10, function(inst)
	local list, s = Atlas.Fill(inst)
	side = s or side
	return list
end, function(list, i)
	return list[i], list[i + 1], side, side
end, function(t, list, i)
	t:SetTexture(list[i + 2], "CLAMP", "CLAMP", "TRILINEAR")
	local sc, sr = list[i + 3], list[i + 4]
	t:SetTexCoord(sc / CHUNKS, (sc + side) / CHUNKS, sr / CHUNKS, (sr + side) / CHUNKS)
	t:SetVertexColor(list[i + 5], list[i + 6], list[i + 7])
	Mask(t, "FillMask" .. list[i + 8])
	t:SetDrawLayer("ARTWORK", list[i + 9])
end)

-- { col, row, w, h, file, l, r, t, b, mask, ... }
UI.Seams = Set("seams", 10, Atlas.Seams, function(list, i)
	return list[i], list[i + 1], list[i + 2], list[i + 3]
end, function(t, list, i)
	t:SetTexture(list[i + 4], "CLAMP", "CLAMP", "TRILINEAR")
	t:SetTexCoord(list[i + 5] / CHUNKS, list[i + 6] / CHUNKS, list[i + 7] / CHUNKS, list[i + 8] / CHUNKS)
	t:SetVertexColor(1, 1, 1)
	Mask(t, "SeamMask" .. list[i + 9])
	t:SetDrawLayer("ARTWORK", 5)
end)

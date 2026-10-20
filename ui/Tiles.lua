-- Tiles and the sea, as demo/tiles.js draws them (see its top comment), with textures only:
--   1. per sea cell its water variant (Atlas.SeaVariant), one repeat a tile; below
--      CELLS_MIN_PX a tile, one REPEAT texture over the whole layout instead
--   2. variant 0 REPEAT over the layout, a repeat every MACRO tiles, turned a quarter, faint
--   4. the tiles' art (SetTexture(fdid)), TileColor tint as vertex colour + an ADD overlay,
--      coast tiles masked with their feather (AddMaskTexture), wrap CLAMP: CLAMPTOBLACKADDITIVE
--      would fade every edge's last texel to clear and draw the tile grid in hairlines of sea
-- The sea's textures are in its colour (the coast tiles' water: tools/gen_sea.py), drawn as they are:
-- nothing over them, so no seam. The colour matching (TileColor's tint, the coast fades) is the
-- atlas's: always on, no setting. A map without a sea of its own gets Eastern Kingdoms' water. A layout keeps the cells and tiles its canvas showed (Engine.Keep, by tile):
-- at the same zoom and origin they're left as they are, so a pan's layout re-textures and places only
-- the ground it adds (a pan's re-set every region: the drag's frame p95 4.35 ms in game).

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime, Engine = ns.Atlas, ns.Runtime, ns.UI.Engine
local Get, Keep, Px, Yield = Engine.Get, Engine.Keep, Engine.Px, Runtime.Yield

local CELLS_MIN_PX = 48 -- px a tile: below, one fill (the variants wouldn't show)
local MACRO, MACRO_ALPHA, MACRO_AT = 2.7, 0.35, { 0.37, 0.61 }

-- Tiles don't snap to the pixel grid: the canvas moves by fractions of a pixel, so they must too
-- (their masks too: a snapped mask on unsnapped art was a suspect of the tear, docs/v1-plan.md §2).
local function Unsnapped(t)
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

local function Maker(layer, sub)
	return function(c) return Unsnapped(c:CreateTexture(nil, layer, nil, sub)) end
end
local SeaTex, MacroTex = Maker("BACKGROUND", 0), Maker("BACKGROUND", 1)
local ArtTex, AddTex = Maker("ARTWORK", 0), Maker("ARTWORK", 1)

local function MakeCell(c)
	local t = SeaTex(c)
	t:SetTexCoord(0, 1, 0, 1)
	return t
end

local function MakeAdd(c)
	local t = AddTex(c)
	t:SetBlendMode("ADD")
	return t
end

-- A region's coast fade: its mask (a region's masks are its own) with feather's texture on it, or none
-- (feather nil). Made the first time a coast tile needs it, on the canvas t is on (a coast is the
-- fewest: a mask for every tile was half a tile layout's regions).
local function Fade(t, c, feather)
	if feather and not t.mask then
		t.mask = Unsnapped(c:CreateMaskTexture())
		t.mask:SetAllPoints(t)
	end
	if t.mask and t.mask.path ~= feather then
		if feather then t.mask:SetTexture(feather, "CLAMP", "CLAMP") end
		t.mask.path = feather
	end
	if (feather ~= nil) ~= (t.masked == true) then
		if feather then t:AddMaskTexture(t.mask) else t:RemoveMaskTexture(t.mask) end
		t.masked = feather ~= nil
	end
end

-- Place t over the tile rect (c0, r0)-(c1, r1) (from the canvas's origin, ui/Engine.lua).
local function Rect(t, c, zoom, c0, r0, c1, r1)
	local ox, oy = c.ox, c.oy
	local x0, y0 = Px(c0 - ox, zoom), Px(r0 - oy, zoom)
	t:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y0)
	t:SetSize(Px(c1 - ox, zoom) - x0, Px(r1 - oy, zoom) - y0)
end

local function Texture(t, path, wrap)
	if t.path ~= path or t.wrap ~= wrap then
		t:SetTexture(path, wrap, wrap, "TRILINEAR")
		t.path, t.wrap = path, wrap
	end
end

-- The macro layer's texture coordinate at tile (col, row): world-anchored, a quarter turned.
local function MacroUV(col, row)
	return (row - MACRO_AT[2]) / MACRO, -(col - MACRO_AT[1]) / MACRO
end

-- A tile drawn at key: with the tint, not an open-sea one (Atlas.Drawn); without, any.
local function Drawn(inst, key, tint)
	if tint then return Atlas.Drawn(inst, key) end
	local tiles = Atlas.Tiles(inst)
	return tiles ~= nil and tiles[key] ~= nil
end

-- A layout's cells and tiles no region on the canvas showed (Engine.Keep): placed after the rest (a
-- Get takes the next region, whatever it showed). Scratch, reused: col, row.
local pc, pr, np = {}, {}, 0
local function Later(col, row)
	np = np + 1
	pc[np], pr[np] = col, row
end

local function SeaKey(col, row) return col * 4096 + row end -- (cells past the tile grid too)

-- A sea cell: its water variant over the tile, kept as it stands while its canvas's epoch holds.
local function Cell(c, t, sea, zoom, col, row, kept)
	if kept and t.e == c.epoch then return end
	Texture(t, sea.textures[Atlas.SeaVariant(col, row)], "CLAMP")
	Rect(t, c, zoom, col, row, col + 1, row + 1)
	t.e = c.epoch
end


local function Sea(c, inst, zoom, sea, tint, c0, r0, c1, r1)
	if zoom < CELLS_MIN_PX then
		local t = Get(c, "fill", "tex", SeaTex)
		Texture(t, sea.textures[1], "REPEAT")
		Rect(t, c, zoom, c0, r0, c1, r1)
		t:SetTexCoord(c0, c1, r0, r1)
	else
		np = 0
		for col = math.floor(c0), math.floor(c1) do
			for row = math.floor(r0), math.floor(r1) do
				local key = col * 64 + row
				local inside = col >= 0 and col < 64 and row >= 0 and row < 64
				if not (inside and Drawn(inst, key, tint) and not (tint and Atlas.SeaFeather(inst, key))) then
					local t = Keep(c, "sea", SeaKey(col, row))
					if t then Cell(c, t, sea, zoom, col, row, true) else Later(col, row) end
				end
			end
			Yield()
		end
		for i = 1, np do
			local col, row = pc[i], pr[i]
			Cell(c, Get(c, "sea", "tex", MakeCell, SeaKey(col, row)), sea, zoom, col, row, false)
			if i % 32 == 0 then Yield() end
		end
	end

	local m = Get(c, "macro", "tex", MacroTex)
	Texture(m, sea.textures[1], "REPEAT")
	m:SetAlpha(MACRO_ALPHA)
	Rect(m, c, zoom, c0, r0, c1, r1)
	local ulx, uly = MacroUV(c0, r0)
	local llx, lly = MacroUV(c0, r1)
	local urx, ury = MacroUV(c1, r0)
	local lrx, lry = MacroUV(c1, r1)
	m:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

-- The tint's overlay on a tile's art: a colour added, fading with the art, anchored to it.
local function Add(c, add, t, m, feather)
	if add.on ~= t then
		add:SetAllPoints(t)
		add.on = t
	end
	if add.m ~= m then
		add:SetColorTexture(m[4], m[5], m[6], 1)
		add.m = m
	end
	Fade(add, c, feather)
end

-- A tile's art (FileDataID), tint (vertex colour + an ADD overlay) and coast fade (its mask), at
-- (col, row); kept as it stands while its canvas's epoch holds (the tint's change is a new one: the
-- layer's rev). Its overlay kept too, or one made after the rest (Later).
local function Art(c, t, inst, zoom, tint, sea, col, row, kept)
	local key = col * 64 + row
	local info = Atlas.TileInfo(inst, key)
	local m = tint and info.tint or false
	local plus = m and (m[4] > 0 or m[5] > 0 or m[6] > 0)
	if not (kept and t.e == c.epoch) then
		if t.fdid ~= info.fdid then
			t:SetTexture(info.fdid, "CLAMP", "CLAMP", "TRILINEAR")
			t.fdid = info.fdid
		end
		Rect(t, c, zoom, col, row, col + 1, row + 1)
		if t.m ~= m then -- (a pooled tile mostly keeps its tint: set only when it changes)
			if m then t:SetVertexColor(m[1], m[2], m[3]) else t:SetVertexColor(1, 1, 1) end
			t.m = m
		end
		local feather = tint and sea and Atlas.SeaFeather(inst, key) or nil
		Fade(t, c, feather)
		t.e, t.feather = c.epoch, feather
	end
	if plus then
		local add = Keep(c, "add", key)
		if add then Add(c, add, t, m, t.feather) else Later(col, row) end
	end
end

-- The tiles drawn over the layout: what the canvas showed kept (Engine.Keep), then the rest. Later's
-- list holds both the art not kept (its col as -1 - col) and the overlays not kept (Art adds those).
local function Tiles(c, inst, zoom, sea, tint, c0, r0, c1, r1)
	np = 0
	for col = math.max(0, math.floor(c0)), math.min(63, math.floor(c1)) do
		for row = math.max(0, math.floor(r0)), math.min(63, math.floor(r1)) do
			local key = col * 64 + row
			if Drawn(inst, key, tint) then
				local t = Keep(c, "art", key)
				if t then Art(c, t, inst, zoom, tint, sea, col, row, true) else Later(-1 - col, row) end
			end
		end
		Yield()
	end
	for i = 1, np do -- (np as it is now: the art's overlays it adds come next)
		local col, row = pc[i], pr[i]
		if col < 0 then
			col = -1 - col
			Art(c, Get(c, "art", "tex", ArtTex, col * 64 + row), inst, zoom, tint, sea, col, row, false)
		end
		if i % 32 == 0 then Yield() end
	end
	for i = 1, np do -- every overlay not kept: the kept art's, then the fresh art's (Art added them on)
		local col, row = pc[i], pr[i]
		if col >= 0 then
			local key = col * 64 + row
			local add = Get(c, "add", "tex", MakeAdd, key)
			local t = c.pools.art[c.pools.art.at[key]]
			Add(c, add, t, t.m, t.feather)
		end
		if i % 32 == 0 then Yield() end
	end
end

UI.Tiles = Engine.Layer("tiles", 1, function(c, inst, zoom, c0, r0, c1, r1)
	local own = Atlas.Sea(inst)
	local sea = own or Atlas.Sea(0) -- a map with no sea of its own: Eastern Kingdoms' water, not black
	if sea then Sea(c, inst, zoom, sea, true, c0, r0, c1, r1) end
	Tiles(c, inst, zoom, own or nil, true, c0, r0, c1, r1)
end)

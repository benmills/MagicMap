-- Tiles and the sea, as demo/tiles.js draws them (see its top comment), with textures only:
--   1. per sea cell its water variant (Atlas.SeaVariant), one repeat a tile; below
--      CELLS_MIN_PX a tile, one REPEAT texture over the whole layout instead
--   2. variant 0 REPEAT over the layout, a repeat every MACRO tiles, turned a quarter, faint
--   3. the tiles' art (SetTexture(fdid)), plain, wrap CLAMP: CLAMPTOBLACKADDITIVE would fade every
--      edge's last texel to clear and draw the tile grid in hairlines of sea
-- A sea cell is any cell with no land tile: none, or an open-sea one (Atlas.Drawn). Nothing is drawn
-- under the gaps of a map with no sea data (Data/Sea.lua): the window's black shows through, never a
-- flat colour. A layout keeps the cells and tiles its canvas showed (Engine.Keep, by tile): at the same
-- zoom and origin they're left as they are, so a pan's layout re-textures and places only the ground it
-- adds (a pan's re-set every region: the drag's frame p95 4.35 ms in game).

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime, Engine = ns.Atlas, ns.Runtime, ns.UI.Engine
local Get, Keep, Px, Yield = Engine.Get, Engine.Keep, Engine.Px, Runtime.Yield

local CELLS_MIN_PX = 48 -- px a tile: below, one fill (the variants wouldn't show)
local MACRO, MACRO_ALPHA, MACRO_AT = 2.7, 0.35, { 0.37, 0.61 }

-- Tiles don't snap to the pixel grid: the canvas moves by fractions of a pixel, so they must too
-- (docs/v1-plan.md §2).
local function Unsnapped(t)
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

local function Maker(layer, sub)
	return function(c) return Unsnapped(c:CreateTexture(nil, layer, nil, sub)) end
end
local SeaTex, MacroTex, ArtTex = Maker("BACKGROUND", 0), Maker("BACKGROUND", 1), Maker("ARTWORK", 0)
local TintTex = Maker("BORDER", 0)

-- The sea's colour: its water textures are grey (mean gain), coloured by the tint map with blend MOD
-- (BORDER: over the sea, under the tiles' art, which stays as it is).
local function MakeTint(c)
	local t = TintTex(c)
	t:SetBlendMode("MOD")
	return t
end

local function MakeCell(c)
	local t = SeaTex(c)
	t:SetTexCoord(0, 1, 0, 1)
	return t
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

-- What lies past the tint's rect: its border colour (the four sides around it).
local function Far(c, zoom, far, a0, b0, a1, b1)
	if a1 <= a0 or b1 <= b0 then return end
	local f = Get(c, "tint", "tex", MakeTint)
	f.path = nil
	f:SetColorTexture(far[1], far[2], far[3], 1)
	Rect(f, c, zoom, a0, b0, a1, b1)
end

-- own: the map's own sea (its tint map lines up with it); else another's water, its far colour alone.
local function Sea(c, inst, zoom, sea, own, c0, r0, c1, r1)
	if zoom < CELLS_MIN_PX then
		local t = Get(c, "fill", "tex", SeaTex)
		Texture(t, sea.textures[1], "REPEAT")
		Rect(t, c, zoom, c0, r0, c1, r1)
		t:SetTexCoord(c0, c1, r0, r1)
	else
		np = 0
		for col = math.floor(c0), math.floor(c1) do
			for row = math.floor(r0), math.floor(r1) do
				local inside = col >= 0 and col < 64 and row >= 0 and row < 64
				if not (inside and Atlas.Drawn(inst, col * 64 + row)) then
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

	-- The tint over its rect (the part in the layout's: no offset reaches past it), its border colour
	-- on the four sides around it.
	local far = sea.far
	if not own then return Far(c, zoom, far, c0, r0, c1, r1) end
	local tc0, tr0, tc1, tr1 = sea.rect[1], sea.rect[2], sea.rect[3], sea.rect[4]
	local a0, b0, a1, b1 = math.max(c0, tc0), math.max(r0, tr0), math.min(c1, tc1), math.min(r1, tr1)
	if a1 > a0 and b1 > b0 then
		local t = Get(c, "tint", "tex", MakeTint)
		Texture(t, sea.tint, "CLAMP")
		Rect(t, c, zoom, a0, b0, a1, b1)
		local sw, sh = tc1 - tc0, tr1 - tr0
		t:SetTexCoord((a0 - tc0) / sw, (a1 - tc0) / sw, (b0 - tr0) / sh, (b1 - tr0) / sh) -- /: never 0 (a sea rect has area: gen_sea.py)
	end
	Far(c, zoom, far, c0, r0, c1, math.min(r1, tr0))              -- above
	Far(c, zoom, far, c0, math.max(r0, tr1), c1, r1)              -- below
	Far(c, zoom, far, c0, math.max(r0, tr0), math.min(c1, tc0), math.min(r1, tr1)) -- left
	Far(c, zoom, far, math.max(c0, tc1), math.max(r0, tr0), c1, math.min(r1, tr1)) -- right
end

-- The tiles drawn over the layout: what the canvas showed kept (Engine.Keep), then the rest.
local function Art(c, t, inst, zoom, col, row, kept)
	if kept and t.e == c.epoch then return end
	local fdid = Atlas.TileInfo(inst, col * 64 + row).fdid
	if t.fdid ~= fdid then
		t:SetTexture(fdid, "CLAMP", "CLAMP", "TRILINEAR")
		t.fdid = fdid
	end
	Rect(t, c, zoom, col, row, col + 1, row + 1)
	t.e = c.epoch
end

local function Tiles(c, inst, zoom, c0, r0, c1, r1)
	np = 0
	for col = math.max(0, math.floor(c0)), math.min(63, math.floor(c1)) do
		for row = math.max(0, math.floor(r0)), math.min(63, math.floor(r1)) do
			local key = col * 64 + row
			if Atlas.Drawn(inst, key) then
				local t = Keep(c, "art", key)
				if t then Art(c, t, inst, zoom, col, row, true) else Later(col, row) end
			end
		end
		Yield()
	end
	for i = 1, np do
		local col, row = pc[i], pr[i]
		Art(c, Get(c, "art", "tex", ArtTex, col * 64 + row), inst, zoom, col, row, false)
		if i % 32 == 0 then Yield() end
	end
end

UI.Tiles = Engine.Layer("tiles", 1, function(c, inst, zoom, c0, r0, c1, r1)
	local own = Atlas.Sea(inst)
	local sea = own or Atlas.Sea(0) -- a map with no sea of its own: Eastern Kingdoms' water, not black
	if sea then Sea(c, inst, zoom, sea, own ~= nil and own ~= false, c0, r0, c1, r1) end
	Tiles(c, inst, zoom, c0, r0, c1, r1)
end)

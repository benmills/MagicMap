-- Tiles and the sea, as demo/tiles.js draws them (see its top comment), with textures only:
--   1. per sea cell its water variant (Atlas.SeaVariant), one repeat a tile; below
--      CELLS_MIN_PX a tile, one REPEAT texture over the whole layout instead
--   2. variant 0 REPEAT over the layout, a repeat every MACRO tiles, turned a quarter, faint
--   3. the tint map with blend MOD over its rect; its border colour (far) MOD beyond
--   4. the tiles' art (SetTexture(fdid)), TileColor tint as vertex colour + an ADD overlay,
--      coast tiles masked with their feather (AddMaskTexture)
-- No sea on the map: its backdrop colour under the tiles.

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime, Map = ns.Atlas, ns.Runtime, ns.UI.Map
local Get, Px, Yield = Map.Get, Map.Px, Runtime.Yield

local CELLS_MIN_PX = 48 -- px a tile: below, one fill (the variants wouldn't show)
local MACRO, MACRO_ALPHA, MACRO_AT = 2.7, 0.35, { 0.37, 0.61 }

-- Tiles don't snap to the pixel grid: the canvas moves by fractions of a pixel, so they must too.
local function Unsnapped(t)
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

local function Maker(layer, sub)
	return function(c) return Unsnapped(c:CreateTexture(nil, layer, nil, sub)) end
end
local SeaTex, MacroTex = Maker("BACKGROUND", 0), Maker("BACKGROUND", 1)
local TintTex, ArtTex, AddTex = Maker("BORDER", 0), Maker("ARTWORK", 0), Maker("ARTWORK", 1)

local function MakeTint(c)
	local t = TintTex(c)
	t:SetBlendMode("MOD")
	return t
end

local function MakeAdd(c)
	local t = AddTex(c)
	t:SetBlendMode("ADD")
	return t
end

local function MakeArt(c)
	local t = ArtTex(c)
	t.mask = c:CreateMaskTexture()
	t.mask:SetAllPoints(t)
	return t
end

-- Place t over the tile rect (c0, r0)-(c1, r1).
local function Rect(t, c, zoom, c0, r0, c1, r1)
	local x0, y0 = Px(c0, zoom), Px(r0, zoom)
	t:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y0)
	t:SetSize(Px(c1, zoom) - x0, Px(r1, zoom) - y0)
end

local function Texture(t, path, wrap)
	if t.path ~= path .. wrap then
		t:SetTexture(path, wrap, wrap, "TRILINEAR")
		t.path = path .. wrap
	end
end

-- The macro layer's texture coordinate at tile (col, row): world-anchored, a quarter turned.
local function MacroUV(col, row)
	return (row - MACRO_AT[2]) / MACRO, -(col - MACRO_AT[1]) / MACRO
end

local function Sea(c, inst, zoom, sea, c0, r0, c1, r1)
	if zoom < CELLS_MIN_PX then
		local t = Get(c, "sea", "tex", SeaTex)
		Texture(t, sea.textures[1], "REPEAT")
		Rect(t, c, zoom, c0, r0, c1, r1)
		t:SetTexCoord(c0, c1, r0, r1)
	else
		for col = math.floor(c0), math.floor(c1) do
			for row = math.floor(r0), math.floor(r1) do
				local key = col * 64 + row
				local inside = col >= 0 and col < 64 and row >= 0 and row < 64
				if not (inside and Atlas.Drawn(inst, key) and not Atlas.SeaFeather(inst, key)) then
					local t = Get(c, "sea", "tex", SeaTex)
					Texture(t, sea.textures[Atlas.SeaVariant(col, row)], "CLAMP")
					Rect(t, c, zoom, col, row, col + 1, row + 1)
					t:SetTexCoord(0, 1, 0, 1)
				end
			end
			Yield()
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

	-- The tint over its rect, its border colour on the four sides around it.
	local tc0, tr0, tc1, tr1 = sea.rect[1], sea.rect[2], sea.rect[3], sea.rect[4]
	local t = Get(c, "tint", "tex", MakeTint)
	Texture(t, sea.tint, "CLAMP")
	Rect(t, c, zoom, tc0, tr0, tc1, tr1)
	local far = sea.far
	local function Far(a0, b0, a1, b1)
		if a1 <= a0 or b1 <= b0 then return end
		local f = Get(c, "tint", "tex", MakeTint)
		f.path = nil
		f:SetColorTexture(far[1], far[2], far[3], 1)
		Rect(f, c, zoom, a0, b0, a1, b1)
	end
	Far(c0, r0, c1, math.min(r1, tr0))              -- above
	Far(c0, math.max(r0, tr1), c1, r1)              -- below
	Far(c0, math.max(r0, tr0), math.min(c1, tc0), math.min(r1, tr1)) -- left
	Far(math.max(c0, tc1), math.max(r0, tr0), c1, math.min(r1, tr1)) -- right
end

local backdrops = {}
local function Backdrop(inst)
	if not backdrops[inst] then
		for _, m in ipairs(Atlas.Maps()) do
			if m.inst == inst then backdrops[inst] = m.bg end
		end
	end
	return backdrops[inst] or { 0, 0, 0 }
end

local function Tiles(c, inst, zoom, sea, c0, r0, c1, r1)
	for col = math.max(0, math.floor(c0)), math.min(63, math.floor(c1)) do
		for row = math.max(0, math.floor(r0)), math.min(63, math.floor(r1)) do
			local key = col * 64 + row
			if Atlas.Drawn(inst, key) then
				local info = Atlas.TileInfo(inst, key)
				local t = Get(c, "art", "tex", MakeArt)
				if t.fdid ~= info.fdid then
					t:SetTexture(info.fdid, "CLAMP", "CLAMP", "TRILINEAR")
					t.fdid = info.fdid
				end
				Rect(t, c, zoom, col, row, col + 1, row + 1)
				local tint, add = info.tint, nil
				if tint then
					t:SetVertexColor(tint[1], tint[2], tint[3])
					if tint[4] > 0 or tint[5] > 0 or tint[6] > 0 then
						add = Get(c, "add", "tex", MakeAdd)
						add:SetColorTexture(tint[4], tint[5], tint[6], 1)
						add:SetAllPoints(t)
					end
				else
					t:SetVertexColor(1, 1, 1)
				end
				local feather = sea and Atlas.SeaFeather(inst, key)
				if feather then
					local path = feather
					if t.mask.path ~= path then
						t.mask:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
						t.mask.path = path
					end
					if not t.masked then t:AddMaskTexture(t.mask); t.masked = true end
				elseif t.masked then
					t:RemoveMaskTexture(t.mask)
					t.masked = false
				end
				if add then
					-- The overlay fades with the art: a mask of its own (a region's masks are its own).
					add.mask = add.mask or c:CreateMaskTexture()
					add.mask:SetAllPoints(add)
					if feather then
						add.mask:SetTexture(feather, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
						if not add.masked then add:AddMaskTexture(add.mask); add.masked = true end
					elseif add.masked then
						add:RemoveMaskTexture(add.mask)
						add.masked = false
					end
				end
			end
		end
		Yield()
	end
end

UI.Tiles = Map.NewLayer("tiles", 1, function(c, inst, zoom, c0, r0, c1, r1)
	local sea = Atlas.Sea(inst)
	if sea then
		Sea(c, inst, zoom, sea, c0, r0, c1, r1)
	else
		local b = Get(c, "backdrop", "tex", SeaTex)
		local col = Backdrop(inst)
		b:SetColorTexture(col[1], col[2], col[3], 1)
		Rect(b, c, zoom, c0, r0, c1, r1)
	end
	Tiles(c, inst, zoom, sea, c0, r0, c1, r1)
end)

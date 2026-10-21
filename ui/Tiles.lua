-- The tiles' art as Blizzard drew it (SetTexture(fdid)), on the window's backdrop: the map's own
-- dark water colour (ui/Window.lua, Data/Tiles.lua's bg), as the game's minimap has it. Open-sea
-- tiles (Atlas.Drawn: one flat colour, the backdrop's) aren't drawn. Wrap CLAMP:
-- CLAMPTOBLACKADDITIVE would fade every edge's last texel to clear and draw the tile grid in
-- hairlines. A layout keeps the tiles its canvas showed (Engine.Keep, by tile): at the same zoom and
-- origin they're left as they are, so a pan's layout re-textures and places only the ground it adds
-- (a pan's re-set every region: the drag's frame p95 4.35 ms in game).

local _, ns = ...
local UI = ns.UI
local Atlas, Runtime, Engine = ns.Atlas, ns.Runtime, ns.UI.Engine
local Get, Keep, Px, Yield = Engine.Get, Engine.Keep, Engine.Px, Runtime.Yield

-- Tiles don't snap to the pixel grid: the canvas moves by fractions of a pixel, so they must too.
local function ArtTex(c)
	local t = c:CreateTexture(nil, "ARTWORK")
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

-- A tile's art at (col, row), kept as it stands while its canvas's epoch holds.
local function Art(c, t, inst, zoom, col, row, kept)
	if kept and t.e == c.epoch then return end
	local fdid = Atlas.Tiles(inst)[col * 64 + row]
	if t.fdid ~= fdid then
		t:SetTexture(fdid, "CLAMP", "CLAMP", "TRILINEAR")
		t.fdid = fdid
	end
	local ox, oy = c.ox, c.oy
	local x0, y0 = Px(col - ox, zoom), Px(row - oy, zoom)
	t:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y0)
	t:SetSize(Px(col + 1 - ox, zoom) - x0, Px(row + 1 - oy, zoom) - y0)
	t.e = c.epoch
end

-- The tiles no region on the canvas showed (Engine.Keep): placed after the rest (a Get takes the next
-- region, whatever it showed). Scratch, reused.
local pc, pr, np = {}, {}, 0

UI.Tiles = Engine.Layer("tiles", 1, function(c, inst, zoom, c0, r0, c1, r1)
	np = 0
	for col = math.max(0, math.floor(c0)), math.min(63, math.floor(c1)) do
		for row = math.max(0, math.floor(r0)), math.min(63, math.floor(r1)) do
			if Atlas.Drawn(inst, col * 64 + row) then
				local t = Keep(c, "art", col * 64 + row)
				if t then
					Art(c, t, inst, zoom, col, row, true)
				else
					np = np + 1
					pc[np], pr[np] = col, row
				end
			end
		end
		Yield()
	end
	for i = 1, np do
		local col, row = pc[i], pr[i]
		Art(c, Get(c, "art", "tex", ArtTex, col * 64 + row), inst, zoom, col, row, false)
		if i % 32 == 0 then Yield() end
	end
end)

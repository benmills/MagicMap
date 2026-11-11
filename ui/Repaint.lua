-- The AI repaints of the broken map art (Data/Repaint.lua, tools/ai_map.py ship; Settings > Map > Repair broken map art, "repaint.on"): the flat, unfinished ground of
-- Blizzard's tiles painted over, each picture a tile's size with its own soft alpha. Laid out with the tiles (Lay, at the end of ui/
-- Tiles.lua's layout), on their canvas, so they move, scale and fade with them; on a frame of that canvas's own, over the ocean
-- (ui/Sea.lua: it lies over the tiles and some repaints reach the coast) and under the layers above the ground. Places overlapping keep their order by sublevel.
-- They're painted for one set of tiles, so they're drawn only on the game build Data/Repaint.lua names or a later build of its version
-- (Atlas.RepaintFits; tools/ai_map.py check and stamp move it on, when the tiles under them haven't changed): on any other, or with
-- no data, the raw map, whatever the setting.

local _, ns = ...
local UI = ns.UI
local Atlas, Engine, Model, Runtime = ns.Atlas, UI.Engine, ns.Model, ns.Runtime
local Get, Keep, Px, Yield = Engine.Get, Engine.Keep, Engine.Px, Runtime.Yield

local BUDGET = 0.5 -- ms a frame for making pieces
local STRIDE = 4 -- a piece's fields in Atlas.Repaint's list: col, row, file, sublevel

local Repaint = {}
UI.Repaint = Repaint

local on, rev = true, 0
function Repaint.Rev() return Model.build and rev + 1 or rev end -- (the build's first known: laid out again)
function Repaint.Set(v)
	if v ~= on then on, rev = v, rev + 1 end
end

-- This client is a build they fit (Model.build: game/parts/Build.lua, which says so in chat if not; not known yet: not yet):
-- Atlas.RepaintFits, theirs or a later one of its version.
local function Fits() return Model.build ~= nil and Atlas.RepaintFits(Model.build) end

local function Tex(c)
	local frame = c.repaint
	if not frame then
		frame = CreateFrame("Frame", nil, c)
		frame:SetAllPoints()
		frame:SetFrameLevel(UI.Sea.frame:GetFrameLevel() + 1) -- its level, not its canvas's: the ocean's frame stands over that
		c.repaint = frame
	end
	local t = frame:CreateTexture(nil, "ARTWORK")
	t:SetSnapToPixelGrid(false) -- (as the tiles: the canvas moves by fractions of a pixel)
	t:SetTexelSnappingBias(0)
	t.home = frame
	return t
end

-- Piece i of the list, kept as it stands while its canvas's epoch holds.
local function Piece(c, t, list, i, zoom, kept)
	if kept and t.e == c.epoch then return end
	local file = list[i + 2]
	if t.file ~= file then
		t:SetTexture(Atlas.ROOT .. file, "CLAMP", "CLAMP", "TRILINEAR")
		t:SetDrawLayer("ARTWORK", list[i + 3])
		t.file = file
	end
	local col, row = list[i], list[i + 1]
	local x0, y0 = Px(col - c.ox, zoom), Px(row - c.oy, zoom)
	t:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y0)
	t:SetSize(Px(col + 1 - c.ox, zoom) - x0, Px(row + 1 - c.oy, zoom) - y0)
	t.e = c.epoch
end

-- The pieces no region on the canvas showed: made by a job of their own once the layout has swapped its canvas in (each
-- loads a picture, and a layout holds up the view), so a new one comes a frame or two late. gen: which Lay's they are; a newer
-- Lay's pieces replace them. A canvas neither shown nor being laid out (the window hid) drops them: the next layout asks again.
local pend, np, target, zoomAt, listAt, gen = {}, 0, nil, 0, nil, 0
local job = Runtime.Worker("map: repaint", function()
	while true do
		local mine, c, list, zoom, k, tiles = gen, target, listAt, zoomAt, 1, UI.Tiles
		while k <= np and mine == gen and (tiles.front == c or tiles.busy and tiles.back == c) do
			if tiles.front == c and not tiles.busy then
				local i = pend[k]
				Piece(c, Get(c, "repaint", "tex", Tex, list[i + 2]), list, i, zoom, false)
				k = k + 1
				Yield()
			else
				coroutine.yield()
			end
		end
		if mine == gen then
			np = 0
			Runtime.Idle()
		end
	end
end, BUDGET)

-- The pieces over the region (c0, r0)-(c1, r1) on the tiles' canvas c.
function Repaint.Lay(c, inst, zoom, c0, r0, c1, r1)
	gen, np, target = gen + 1, 0, nil
	local list = on and Atlas.Repaint(inst)
	if not list or not Fits() then return end
	target, zoomAt, listAt = c, zoom, list
	local moved = 0
	for i = 1, #list, STRIDE do
		local col, row = list[i], list[i + 1]
		if col + 1 > c0 and col < c1 and row + 1 > r0 and row < r1 then
			local t = Keep(c, "repaint", list[i + 2])
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

UI.Feel.Add("map", "Ground", {
	{ key = "repaint.on", kind = "toggle", label = "Repair broken map art", default = true, apply = Repaint.Set,
		tip = "Paints over the flat, unfinished blocks in Blizzard's map with AI-generated pictures. Only on the game version they were checked against (its later builds too): on another, the map stays as Blizzard's until MagicMap updates." },
})

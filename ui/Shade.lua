-- The unexplored shade (Layers.lua:1257-1269, 1334-1361, 1772-1784, 2245-2248), off until turned on (the
-- gear's "Shade unexplored"): the parts of each zone you haven't discovered, darkened (0, 0, 0, 0.55) over
-- the tiles, under the quest areas. The map shown's continent in cells CELL tiles a side: a cell whose area
-- Game found unexplored (Model.explored: M4.1's sweep) is dark, each row's runs of dark cells one rectangle,
-- PAD px past each side so neighbours meet. Worked out in a job, a Yield each EVERY cells, when the map or
-- what's explored changes; the old shade kept until it's done (and Game hands what's explored over only
-- when a sweep ends). A layout places the rectangles meeting its region, clipped to it, keeping those the
-- canvas showed whole at its epoch; scaled while the zoom moves.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Atlas, Runtime, Engine = ns.Atlas, ns.Runtime, UI.Engine
local Camera = UI.Camera
local Get, Keep, Yield = Engine.Get, Engine.Keep, Runtime.Yield
local AreaAt = Atlas.AreaAt

local LEVEL = 2 -- over the tiles (1), under the quest areas (3) (Core.lua:149)
local CELL = 0.2 -- tiles (~107 yd): the spike's sampling grid (Layers.lua:75)
local SHADE = { 0, 0, 0, 0.55 } -- Layers.lua:1779
local PAD = 0.5 -- px (Layers.lua:1782)
local EVERY = 128 -- cells a Yield (docs/structure.md "Atlas first use")

-- The rectangles, flat: col0, row0, col1 each (CELL tall), for a map and what was explored then.
local shade = { n = 0 }
local aim, rev = {}, 0 -- what the job works out (inst, explored); the layer's rev
local job

local function Build(inst, explored)
	return Runtime.Job("map: shade", function()
		local r, out, n, k = Atlas.MapRect(Atlas.Continent(inst)), { inst = inst }, 0, 0
		local nc, nr = math.ceil((r.col1 - r.col0) / CELL), math.ceil((r.row1 - r.row0) / CELL)
		for j = 0, nr - 1 do
			local row, start = r.row0 + (j + 0.5) * CELL, nil
			for i = 0, nc do
				local dark = false
				if i < nc then
					dark = explored[AreaAt(inst, r.col0 + (i + 0.5) * CELL, row)] == false -- (at sea: nil)
					k = k + 1
					if k % EVERY == 0 then Yield() end
				end
				if dark and not start then
					start = i
				elseif not dark and start then
					out[n + 1], out[n + 2], out[n + 3] = r.col0 + start * CELL, r.row0 + j * CELL, r.col0 + i * CELL
					n, start = n + 3, nil
				end
			end
		end
		out.n, shade, rev = n, out, rev + 1
	end, 1)
end

-- The layer's rev: a new shade worked out when the map shown or what's explored changes (none known: none).
local function Rev()
	local inst, explored = Camera.inst, Model.explored
	if inst ~= aim.inst or explored ~= aim.explored then
		aim.inst, aim.explored = inst, explored
		if job then Runtime.Cancel(job) end
		job = explored and Atlas.Continent(inst) and Build(inst, explored) or nil
	end
	return rev
end

local function Make(c)
	local t = c:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(SHADE[1], SHADE[2], SHADE[3], SHADE[4])
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	return t
end

-- A rectangle's region t, its run clipped to the layout's region from x0 to x1; whole: not clipped.
local function Set(c, t, x0, x1, row, whole)
	local zoom = c.zoom
	t:SetPoint("TOPLEFT", c, "TOPLEFT", (x0 - c.ox) * zoom, -(row - c.oy) * zoom)
	t:SetSize((x1 - x0) * zoom + PAD, CELL * zoom + PAD)
	t.e = whole and c.epoch
end

local miss, nmiss = {}, 0 -- those the canvas didn't show: their index, then Get (after the Keeps)
UI.Shade = Engine.Layer("unexplored", LEVEL, function(c, inst, _, c0, r0, c1, r1)
	local s = shade
	if s.inst ~= inst or s.n == 0 then return true end
	nmiss = 0
	for i = 1, s.n, 3 do
		local a, row, b = s[i], s[i + 1], s[i + 2]
		if row < r1 and row + CELL > r0 and a < c1 and b > c0 then
			local x0, x1 = math.max(a, c0), math.min(b, c1)
			local whole, t = x0 == a and x1 == b, Keep(c, "shade", i)
			if not t then
				nmiss = nmiss + 1
				miss[nmiss] = i
			elseif not (whole and t.e == c.epoch) then
				Set(c, t, x0, x1, row, whole)
			end
		end
		if i % 96 == 1 then Yield() end
	end
	for j = 1, nmiss do
		local i = miss[j]
		local a, row, b = s[i], s[i + 1], s[i + 2]
		local x0, x1 = math.max(a, c0), math.min(b, c1)
		Set(c, Get(c, "shade", "tex", Make, i), x0, x1, row, x0 == a and x1 == b)
		if j % 32 == 0 then Yield() end
	end
end, Rev)

UI.Menus.Layer({ key = "unexplored", label = "Shade unexplored", group = "map", default = false,
	tip = "Darken the parts of each zone you haven't discovered yet." })

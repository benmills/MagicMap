-- Minimap blips: what Game's sensor knows now (obs.blips) as Known("blips"), and the ones
-- remembered from before (saved.blips, types/saved.lua) as Known("remembered"), Focus's instance.
--   dedupe   a sensed blip this close (SAME) to a remembered one of its name is that one: it moves
--            there, keeping one entry across sweeps (the live one carries its key)
--   forget   when a sweep ends, a remembered blip well inside its reach that it didn't see is gone
--            (picked, despawned, wrongly measured)
--   keep     a sensed blip with a tracking icon (a mailbox, a town service), measured standing still,
--            is remembered for when you're away; at most MAX an instance (D6), the oldest dropped.
--            Without one (herbs and ore: an atlas; other NPCs) it's shown only while sensed.
-- The store is bucketed by cell, so dedupe and forget look at a blip's neighbours only, and
-- Known("remembered") changes only when what's remembered on its map does, not with each sweep.
-- While the sensor doesn't run (obs.blips nil) nothing is sensed: only the remembered show.

local _, ns = ...
local Model = ns.Model

local YD = 1 / ns.Atlas.TILE_YARDS
local SAME = 10 * YD
local FORGET = 0.8 -- of a sweep's reach
local MAX = 5000 -- an instance (D6; ADR 0004)
local CELL = 4 -- a cell's side in a key's steps (1/64 tile): 1/16 tile, ~33 yd, wider than SAME
local NONE = {}

local store = {}             -- saved.blips: [inst][key] = { name, icon, col, row, t }
local cells, counts = {}, {} -- per inst (made at first use): [cell] = { [key] = true }; how many it holds
local live = {}              -- copies of what the sensor knows now: { name, inst, col, row, icon, atlas, rough, key }
local list, rev = {}, 0      -- Known("blips")
local seen, seenRev, seenInst, seenDirty = {}, 0, nil, true -- Known("remembered") and its instance
local entries = setmetatable({}, { __mode = "k" }) -- a saved one -> its Known entry
local textures, atlases = {}, {} -- MM.Icon tables, one each
local lastSweep

local function R3(v) return math.floor(v * 1000 + 0.5) / 1000 end
local function Step(v) return math.floor(v * 64 + 0.5) end
local function Key(name, col, row) return name .. ":" .. Step(col) .. ":" .. Step(row) end
local function Near(a, name, col, row) return a.name == name and (a.col - col) ^ 2 + (a.row - row) ^ 2 < SAME * SAME end
local function Cell(x, y) return x * 4096 + y end
local function At(col, row) return math.floor(Step(col) / CELL), math.floor(Step(row) / CELL) end

local function Texture(t)
	if not textures[t] then textures[t] = { texture = t } end
	return textures[t]
end

local function Atlas(a)
	if not atlases[a] then atlases[a] = { atlas = a } end
	return atlases[a]
end

local function Add(inst, key, s)
	local c = cells[inst]
	local k = Cell(At(s.col, s.row))
	local b = c[k]
	if not b then b = {}; c[k] = b end
	b[key], counts[inst] = true, counts[inst] + 1
	if inst == seenInst then seenDirty = true end
end

local function Drop(inst, key)
	local s = store[inst][key]
	store[inst][key] = nil
	cells[inst][Cell(At(s.col, s.row))][key] = nil
	counts[inst] = counts[inst] - 1
	if inst == seenInst then seenDirty = true end
end

-- An instance's cells, made at its first use.
local function Index(inst)
	if cells[inst] then return end
	cells[inst], counts[inst] = {}, 0
	for key, s in pairs(store[inst]) do Add(inst, key, s) end
end

-- The keys remembered in (col, row)'s cell and the 8 around it: a reused list, and its length.
local around = {}
local function Around(inst, col, row)
	local c, n = cells[inst], 0
	local cx, cy = At(col, row)
	for x = cx - 1, cx + 1 do
		for y = cy - 1, cy + 1 do
			for key in pairs(c[Cell(x, y)] or NONE) do
				n = n + 1
				around[n] = key
			end
		end
	end
	return around, n
end

-- obs.blips.list copied into live if it differs (it's per frame: Game reuses it).
local function Sync(l)
	local same = #l == #live
	for i = 1, same and #l or 0 do
		local x, y = l[i], live[i]
		if x.name ~= y.name or x.pos.col ~= y.col or x.pos.row ~= y.row or x.pos.inst ~= y.inst or x.rough ~= y.rough then
			same = false
			break
		end
	end
	if same then return false end
	for i, x in ipairs(l) do
		live[i] = { name = x.name, inst = x.pos.inst, col = x.pos.col, row = x.pos.row, icon = x.icon, atlas = x.atlas,
			rough = x.rough }
	end
	for i = #live, #l + 1, -1 do live[i] = nil end
	return true
end

local function Remember(e, now)
	local inst = e.inst
	if not store[inst] then store[inst] = {} end
	Index(inst)
	local entries, key = store[inst], Key(e.name, e.col, e.row)
	local keys, n = Around(inst, e.col, e.row)
	for i = 1, n do
		local k = keys[i]
		if k ~= key and entries[k] and Near(entries[k], e.name, e.col, e.row) then Drop(inst, k) end -- the same one, measured better
	end
	local col, row, s = R3(e.col), R3(e.row), entries[key]
	if s and s.col == col and s.row == row then
		s.t = now or 0
		return
	end
	if s then
		Drop(inst, key)
	elseif counts[inst] >= MAX then -- the oldest goes (only at the cap: a pass over the instance)
		local oldest
		for k, x in pairs(entries) do
			if not oldest or x.t < entries[oldest].t then oldest = k end
		end
		Drop(inst, oldest)
	end
	s = { name = e.name, icon = e.icon, col = col, row = row, t = now or 0 }
	entries[key] = s
	Add(inst, key, s)
end

local function Forget(b)
	local c, reach = b.center, b.reach * FORGET
	local entries = store[c.inst]
	if not entries then return end
	Index(c.inst)
	local index, r = cells[c.inst], math.ceil(Step(reach) / CELL) + 1
	local cx, cy = At(c.col, c.row)
	for x = cx - r, cx + r do
		for y = cy - r, cy + r do
			for key in pairs(index[Cell(x, y)] or NONE) do
				local s = entries[key]
				if (s.col - c.col) ^ 2 + (s.row - c.row) ^ 2 < reach * reach then
					local sensed = false
					for _, e in ipairs(live) do sensed = sensed or (e.inst == c.inst and Near(e, s.name, s.col, s.row)) end
					if not sensed then Drop(c.inst, key) end -- (clearing a field mid-pairs: allowed)
				end
			end
		end
	end
end

-- Known("blips") anew: each live one, under the key of a remembered one it stands for.
local function Live()
	rev, list = rev + 1, {}
	for i, e in ipairs(live) do
		local key = Key(e.name, e.col, e.row) .. ":live"
		if store[e.inst] then
			Index(e.inst)
			local keys, n = Around(e.inst, e.col, e.row)
			for j = 1, n do
				if Near(store[e.inst][keys[j]], e.name, e.col, e.row) then key = keys[j] end
			end
		end
		list[i] = { key = key, kind = "blips", name = e.name, live = true, pos = { inst = e.inst, col = e.col, row = e.row },
			icon = e.icon and Texture(e.icon) or e.atlas and Atlas(e.atlas) or nil }
	end
end

Model.Part(function(obs)
	local b = obs.blips
	if not b then
		if live[1] then live = {}; Live() end
		return
	end
	if Sync(b.list) then
		for _, e in ipairs(live) do
			if e.icon and not e.rough then Remember(e, obs.epoch) end
		end
		Live()
	end
	if b.sweep ~= lastSweep then
		lastSweep = b.sweep
		if b.center then Forget(b) end
	end
end, function(saved)
	store, cells, counts, seenDirty = saved.blips, {}, {}, true
end)

Model.Kind("blips", function() return list, rev end)

-- Known("remembered"): Focus's instance (else yours), its entries made once a saved one.
Model.Kind("remembered", function()
	local f = Model.focus
	local inst = f and f.inst or Model.you.inst
	if inst ~= seenInst then seenInst, seenDirty = inst, true end
	if not seenDirty then return seen, seenRev end
	seenDirty, seenRev, seen = false, seenRev + 1, {}
	for key, s in pairs(store[inst] or NONE) do
		local e = entries[s]
		if not e then
			e = { key = key, kind = "remembered", name = s.name, live = false, pos = { inst = inst, col = s.col, row = s.row },
				icon = Texture(s.icon) }
			entries[s] = e
		end
		e.t = s.t
		seen[#seen + 1] = e
	end
	return seen, seenRev
end)

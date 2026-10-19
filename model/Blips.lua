-- Minimap blips: what Game's sensor knows now (obs.blips) as Known("blips"), and the ones
-- remembered from before (saved.blips, types/saved.lua) as Known("remembered"), Focus's instance.
--   dedupe   a sensed blip this close (SAME) to a remembered one of its name is that one: it moves
--            there, keeping one entry across sweeps (the live one carries its key; one met on the move,
--            rough, within SAME + LAG: the client's lag, Blips.lua:33-39)
--   forget   when a sweep ends, a remembered blip well inside its reach (0.8 of 220 yd, or of the
--            sweep's when less) that it didn't see is gone (picked, despawned, wrongly measured), if
--            tracking shows its kind (else the sweep can't: Blips.lua:607-626)
--   keep     a sensed blip with a tracking icon (a mailbox, a town service), measured standing still,
--            is remembered for when you're away, seen again at most hourly; at most MAX an instance
--            (D6), the oldest dropped; not one Atlas's services have (Model.ServiceNear: Blips.lua:581-605).
--            Without one (herbs and ore: an atlas; other NPCs) it's shown only while sensed.
--   ours     a sensed blip within NEAR_OURS of one of our pins (quests, offers, flight points, rares,
--            dungeons, corpse, waypoint; while its layer is on: Focus.off) is that pin's: not listed,
--            not kept (Blips.lua:446-468, 659-664). One with no icon a quest giver (Atlas.BlipService)
--            shows the "!", a quest ender the "?" (Blips.lua:387-388, 433-436): those our layers don't cover.
-- The store is bucketed by cell, so dedupe and forget look at a blip's neighbours only, and
-- Known("remembered") changes only when what's remembered on its map does, not with each sweep;
-- listed while tracking shows its icon, and not where a service of its name is (Blips.lua:644-650).
-- While the sensor doesn't run (obs.blips nil) nothing is sensed: only the remembered show.

local _, ns = ...
local Model = ns.Model

local YD = 1 / ns.Atlas.TILE_YARDS
local SAME, LAG = 10 * YD, 8 * YD -- Blips.lua:38
local FORGET, LIVE = 0.8, 220 * YD -- of the sensor's word around you (Blips.lua:480, 613)
local HOUR = 3600 -- s: a remembered one seen again within it is left as it is (Blips.lua:592)
local NEAR_OURS = 8 * YD -- Blips.lua:40
local QUEST = { questgiver = 132049, questender = 132048 } -- the "!" and the "?" (Blips.lua:387-388)
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
local function Near(a, name, col, row, rough)
	local r = rough and SAME + LAG or SAME
	return a.name == name and (a.col - col) ^ 2 + (a.row - row) ^ 2 < r * r
end
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
	if Model.ServiceNear(inst, e.name, e.col, e.row) then return end -- (Atlas's services have it anyway)
	if not store[inst] then store[inst] = {} end
	Index(inst)
	local entries, key = store[inst], Key(e.name, e.col, e.row)
	local s = entries[key]
	if s and s.t > now - HOUR then return end
	local keys, n = Around(inst, e.col, e.row)
	for i = 1, n do
		local k = keys[i]
		if k ~= key and entries[k] and Near(entries[k], e.name, e.col, e.row) then Drop(inst, k) end -- the same one, measured better
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
	s = { name = e.name, icon = e.icon, col = R3(e.col), row = R3(e.row), t = now }
	entries[key] = s
	Add(inst, key, s)
end

local function Forget(b)
	local c, reach = b.center, FORGET * math.min(b.reach, LIVE)
	local entries = store[c.inst]
	if not entries then return end
	Index(c.inst)
	local index, r = cells[c.inst], math.ceil(Step(reach) / CELL) + 1
	local cx, cy = At(c.col, c.row)
	for x = cx - r, cx + r do
		for y = cy - r, cy + r do
			for key in pairs(index[Cell(x, y)] or NONE) do
				local s = entries[key]
				if (s.col - c.col) ^ 2 + (s.row - c.row) ^ 2 < reach * reach and Model.Tracked(s.icon) then
					local sensed = false
					for _, e in ipairs(live) do sensed = sensed or (e.inst == c.inst and Near(e, s.name, s.col, s.row, e.rough)) end
					if not sensed then Drop(c.inst, key) end -- (clearing a field mid-pairs: allowed)
				end
			end
		end
	end
end

-- Our pins a blip stands under: the kinds, each the layer it's drawn on (Focus.off's key; Blips.lua:447).
local OURS = { quests = "quests", offers = "offers", rares = "rares", corpse = "corpse", waypoint = "waypoint" }
local PLACES = { flight = "flight", dungeon = "dungeons" }
local ours, oursRev, oursOff = {}, -1, nil -- inst, col, row of each; the revs (summed) and Focus.off they're of

-- ours made again if any of those changed: whether it was.
local function Ours()
	local f = Model.focus
	local off, r = f and f.off, select(2, Model.Known("places"))
	for kind in pairs(OURS) do r = r + select(2, Model.Known(kind)) end
	if r == oursRev and off == oursOff then return false end
	oursRev, oursOff, off = r, off, off or NONE
	local n = 0
	for kind, layer in pairs(OURS) do
		for _, e in ipairs(off[layer] and NONE or Model.Known(kind)) do
			local p = e.pos
			ours[n + 1], ours[n + 2], ours[n + 3], n = p.inst, p.col, p.row, n + 3
		end
	end
	for _, e in ipairs((Model.Known("places"))) do
		local layer, p = PLACES[e.place], e.pos
		if layer and not off[layer] then ours[n + 1], ours[n + 2], ours[n + 3], n = p.inst, p.col, p.row, n + 3 end
	end
	for i = #ours, n + 1, -1 do ours[i] = nil end
	return true
end

local function NearOurs(e)
	for i = 1, #ours, 3 do
		if ours[i] == e.inst and math.abs(ours[i + 1] - e.col) < NEAR_OURS and math.abs(ours[i + 2] - e.row) < NEAR_OURS then
			return true
		end
	end
	return false
end

-- A quest giver's "!", a quest ender's "?" (no tracking icon: Atlas.BlipService's), by name; nil: neither.
local quests = {}
local function Quest(name)
	local q = quests[name]
	if q == nil then
		local t = QUEST[ns.Atlas.BlipService(name)]
		q = t and Texture(t) or false
		quests[name] = q
	end
	return q or nil
end

-- Known("blips") anew: each live one but ours, under the key of a remembered one it stands for.
local function Live()
	rev, list = rev + 1, {}
	for _, e in ipairs(live) do
		if not NearOurs(e) then
			local key = Key(e.name, e.col, e.row) .. ":live"
			if store[e.inst] then
				Index(e.inst)
				local keys, n = Around(e.inst, e.col, e.row)
				for j = 1, n do
					if Near(store[e.inst][keys[j]], e.name, e.col, e.row, e.rough) then key = keys[j] end
				end
			end
			list[#list + 1] = { key = key, kind = "blips", name = e.name, live = true,
				pos = { inst = e.inst, col = e.col, row = e.row },
				icon = e.icon and Texture(e.icon) or e.atlas and Atlas(e.atlas) or Quest(e.name) }
		end
	end
end

Model.Part(function(obs)
	local b = obs.blips
	if not b then
		if live[1] then live = {}; Live() end
		return
	end
	if Sync(b.list) then
		Ours()
		for _, e in ipairs(live) do
			if e.icon and not e.rough and not NearOurs(e) then Remember(e, obs.epoch or 0) end
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

Model.Kind("blips", function()
	if Ours() then Live() end
	return list, rev
end)

-- Known("remembered"): Focus's instance (else yours), those tracking shows but where Atlas's services
-- have one of the name, its entries made once a saved one.
local servicesRev
Model.Kind("remembered", function()
	local f = Model.focus
	local inst = f and f.inst or Model.you.inst
	local r = Model.servicesRev
	if inst ~= seenInst or r ~= servicesRev then seenInst, servicesRev, seenDirty = inst, r, true end
	if not seenDirty then return seen, seenRev end
	seenDirty, seenRev, seen = false, seenRev + 1, {}
	for key, s in pairs(store[inst] or NONE) do
		if Model.Tracked(s.icon) and not Model.ServiceNear(inst, s.name, s.col, s.row) then
			local e = entries[s]
			if not e then
				e = { key = key, kind = "remembered", name = s.name, live = false, pos = { inst = inst, col = s.col, row = s.row },
					icon = Texture(s.icon) }
				entries[s] = e
			end
			e.t = s.t
			seen[#seen + 1] = e
		end
	end
	return seen, seenRev
end)

-- Minimap blips (obs.blips: what Game's sensor knows now) merged with the ones
-- remembered from before (saved.blips, types/saved.lua), as Known("blips").
--   dedupe   a sensed blip this close (SAME) to a remembered one of its name is
--            that one: it moves there, keeping one entry across sweeps
--   forget   when a sweep ends, a remembered blip well inside its reach that it
--            didn't see is gone (picked, despawned, wrongly measured)
--   keep     a sensed blip with a tracking icon (a mailbox, a town service),
--            measured standing still, is remembered for when you're away; at most
--            MAX an instance, the oldest dropped. Without an icon (herbs, ore,
--            other NPCs) it's shown only while sensed.
-- While the sensor doesn't run (obs.blips nil) nothing is sensed: only the
-- remembered show.

local _, ns = ...
local Model = ns.Model

local YD = 1 / ns.Atlas.TILE_YARDS
local SAME = 10 * YD
local FORGET = 0.8 -- of a sweep's reach
local MAX = 200
local NONE = {}

local store = {}            -- saved.blips: [inst][key] = { name, icon, col, row, t }
local live = {}             -- copies of what the sensor knows now: { name, inst, col, row, icon, rough }
local list, rev, dirty = {}, 0, true
local lastSweep

local function R3(v) return math.floor(v * 1000 + 0.5) / 1000 end
local function Key(name, col, row) return name .. ":" .. math.floor(col * 64 + 0.5) .. ":" .. math.floor(row * 64 + 0.5) end
local function Near(a, name, col, row) return a.name == name and (a.col - col) ^ 2 + (a.row - row) ^ 2 < SAME * SAME end

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
		live[i] = { name = x.name, inst = x.pos.inst, col = x.pos.col, row = x.pos.row, icon = x.icon, rough = x.rough }
	end
	for i = #live, #l + 1, -1 do live[i] = nil end
	return true
end

local function Remember(e, now)
	local entries = store[e.inst]
	if not entries then entries = {}; store[e.inst] = entries end
	local key, n, oldest = Key(e.name, e.col, e.row), 0, nil
	for k, s in pairs(entries) do
		if k ~= key and Near(s, e.name, e.col, e.row) then
			entries[k] = nil -- the same one, measured better: one entry
		else
			n = n + 1
			if not oldest or s.t < entries[oldest].t then oldest = k end
		end
	end
	if not entries[key] and n >= MAX then entries[oldest] = nil end
	entries[key] = { name = e.name, icon = e.icon, col = R3(e.col), row = R3(e.row), t = now or 0 }
end

local function Forget(b)
	local c, reach = b.center, b.reach * FORGET
	for key, s in pairs(store[c.inst] or NONE) do
		if (s.col - c.col) ^ 2 + (s.row - c.row) ^ 2 < reach * reach then
			local seen = false
			for _, e in ipairs(live) do seen = seen or (e.inst == c.inst and Near(e, s.name, s.col, s.row)) end
			if not seen then store[c.inst][key] = nil; dirty = true end
		end
	end
end

Model.Part(function(obs)
	local b = obs.blips
	if not b then
		if live[1] then live, dirty = {}, true end
		return
	end
	if Sync(b.list) then
		dirty = true
		for _, e in ipairs(live) do
			if e.icon and not e.rough then Remember(e, obs.epoch) end
		end
	end
	if b.sweep ~= lastSweep then
		lastSweep = b.sweep
		if b.center then Forget(b) end
	end
end, function(saved)
	store, dirty = saved.blips, true
end)

-- Known("blips"): the sensed (live) and the remembered not sensed now, one list.
Model.Kind("blips", function()
	if not dirty then return list, rev end
	dirty, rev, list = false, rev + 1, {}
	local matched = {}
	for _, e in ipairs(live) do
		local key = Key(e.name, e.col, e.row) .. ":live"
		for k, s in pairs(store[e.inst] or NONE) do
			if Near(s, e.name, e.col, e.row) then key = k; matched[s] = true end
		end
		list[#list + 1] = { key = key, kind = "blips", name = e.name, live = true,
			pos = { inst = e.inst, col = e.col, row = e.row }, icon = e.icon and { texture = e.icon } }
	end
	for inst, entries in pairs(store) do
		for k, s in pairs(entries) do
			if not matched[s] then
				list[#list + 1] = { key = k, kind = "blips", name = s.name, live = false, t = s.t,
					pos = { inst = inst, col = s.col, row = s.row }, icon = { texture = s.icon } }
			end
		end
	end
	return list, rev
end)

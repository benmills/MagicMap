-- Rare and rare-elite NPCs' spawn points (Atlas.Rares: static data, nothing
-- sensed), as Known("rares"), for the map shown only (Model.focus.inst, while
-- shown). Lazy: built the first time Known("rares") is asked for that map, in a
-- Runtime job (a pass over every NPC the first time per map, spread over
-- frames); until it's done the last list stays (UI filters by inst).

local _, ns = ...
local Model = ns.Model

local NONE = {}
local ICON = { [4] = { atlas = "vignettekill" }, [2] = { atlas = "vignettekillelite" } } -- the game's rare icons
local RANK = { [4] = "Rare", [2] = "Rare Elite" }

local list, rev = NONE, 0
local inst, job -- the map the list (or the running job) is for
local failed = {} -- [inst] = true: its job failed (Runtime reported it); not tried again

local function Level(e)
	if not e.minLevel then return "" end
	if e.maxLevel and e.maxLevel ~= e.minLevel then return ", level " .. e.minLevel .. "-" .. e.maxLevel end
	return ", level " .. e.minLevel
end

local function Build(at)
	local Runtime = ns.Runtime
	return Runtime.Job("model: rares", function()
		local out, keys = {}, {}
		for _, e in ipairs(ns.Atlas.Rares(at, Runtime.Yield)) do
			local key = "npc:" .. e.id .. ":" .. math.floor(e.col * 64 + 0.5) .. ":" .. math.floor(e.row * 64 + 0.5)
			while keys[key] do key = key .. "+" end -- two spawns in one cell: still one key each
			keys[key] = true
			out[#out + 1] = { key = key,
				kind = "rares", name = e.name, live = false, icon = ICON[e.rank],
				text = RANK[e.rank] .. Level(e), pos = { inst = at, col = e.col, row = e.row } }
			Runtime.Yield()
		end
		list, rev = out, rev + 1
	end, 1) -- (1 ms: docs/structure.md "Atlas first use")
end

Model.Kind("rares", function()
	local f = Model.focus
	if not f or not f.shown or f.inst == nil then return list, rev end
	if job and not job.done then return list, rev end
	if job and job.err then failed[inst] = true end
	job = nil
	if f.inst ~= inst and not failed[f.inst] then
		inst = f.inst
		job = Build(inst)
	end
	return list, rev
end)

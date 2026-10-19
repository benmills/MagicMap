-- Model: what we know. Plain Lua: no WoW API; sees only what it's handed:
-- Model.Observe(obs, oracles) from Game's observe step, Model.Focus(focus) from
-- UI, Model.Load(saved) (its saved part) from Game. UI reads it back through
-- types/model.lua: Known(kind), you, hooked, minimap, addons, Target, Route.
--
-- Model.you = { inst, col, row, facing, stale }: tile space (Atlas), facing in
-- radians (0 north, counter-clockwise). While the position isn't known (instances,
-- loading) the last known one is kept with stale = true; nil: never known
-- (or not on the map we're now on). uiMap, zone, subzone, level, faction, dead, ghost, combat:
-- this frame's, as handed (nil: the client gave nothing).
-- Model.hooked, Model.minimap: this frame's obs.hooked and obs.minimap, handed on unchanged
-- (UI reads them the same frame). Model.addons: obs.addons, the last handed ({} until then); Model.levels:
-- obs.levels so.
--
-- Each kind lives in its own file: Model.Part(observe, load) hooks it into
-- Observe and Load, Model.Kind(kind, fn) answers Known(kind) with fn() -> list, rev.

local _, ns = ...
local Model = ns.Model or {}; ns.Model = Model

local NONE = {}
Model.you, Model.hooked, Model.addons, Model.levels = {}, NONE, NONE, NONE
Model.SAVED = { version = 1, defaults = { rares = {}, blips = {} } } -- types/saved.lua MM.SavedModel

local parts, kinds = {}, {}

function Model.Part(observe, load) parts[#parts + 1] = { observe = observe, load = load } end
function Model.Kind(kind, fn) kinds[kind] = fn end

function Model.Known(kind)
	local fn = kinds[kind]
	if not fn then return NONE, 0 end
	return fn()
end

function Model.Load(saved)
	Model.saved = saved
	for _, p in ipairs(parts) do
		if p.load then p.load(saved) end
	end
end

function Model.Focus(focus) Model.focus = focus end

function Model.Observe(obs, oracles)
	local o, you = obs.you, Model.you
	Model.hooked, Model.minimap, Model.addons = obs.hooked or NONE, obs.minimap, obs.addons or Model.addons
	Model.levels = obs.levels or Model.levels
	if o.col then
		you.inst, you.col, you.row, you.stale = o.inst, o.col, o.row, false
	else
		you.stale = true
		if o.inst and o.inst ~= you.inst then you.inst, you.col, you.row = o.inst, nil, nil end
	end
	if o.facing then you.facing = o.facing end
	you.uiMap, you.zone, you.subzone, you.level, you.faction = o.uiMap, o.zone, o.subzone, o.level, o.faction
	you.dead, you.ghost, you.combat = o.dead, o.ghost, o.combat
	for _, p in ipairs(parts) do
		if p.observe then p.observe(obs, oracles) end
	end
end

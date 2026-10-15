-- Model: what we know. Plain Lua: no WoW API; sees only what it's handed
-- (Model.Observe(obs) from Game's observe step).
--
-- Model.you = { inst, col, row, facing }: tile space (Atlas), facing in
-- radians (0 north, counter-clockwise); nil when not known.

local _, ns = ...
local Model = ns.Model or {}; ns.Model = Model

Model.you = {}

function Model.Observe(obs)
	local o, you = obs.you, Model.you
	if o then you.inst, you.col, you.row, you.facing = o.inst, o.col, o.row, o.facing end
end

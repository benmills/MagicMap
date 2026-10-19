-- Your party's or raid's other members where the game says they are (obs.group: per frame, its tables
-- Game's to refill, ~20 Hz), as Known("group"): key the member's GUID, its class, level and dead (or a
-- ghost) for its dot (Layers.lua:705-760); one withheld (an instance, another continent) isn't listed.
-- An entry a member, kept while it's listed: a change sets its fields in place and the rev goes up; a
-- new list when one is added or goes.

local _, ns = ...
local Model = ns.Model

local NONE = {}

local list, rev = NONE, 0
local byId = {} -- id -> its entry

Model.Part(function(obs)
	local g = obs.group
	if g == nil then return end
	local n, changed, again = 0, false, false
	for _, m in ipairs(g) do
		local p = m.pos
		if p then
			n = n + 1
			local e = byId[m.id]
			if not e then
				e = { key = m.id, kind = "group", live = true, pos = {} }
				byId[m.id] = e
			end
			local q = e.pos
			if e.name ~= m.name or e.class ~= m.class or e.level ~= m.level or e.dead ~= m.dead
				or q.inst ~= p.inst or q.col ~= p.col or q.row ~= p.row then
				e.name, e.class, e.level, e.dead = m.name, m.class, m.level, m.dead
				q.inst, q.col, q.row, changed = p.inst, p.col, p.row, true
			end
			again = again or list[n] ~= e
		end
	end
	again = again or n ~= #list
	if again then
		local out, ids = {}, {}
		for _, m in ipairs(g) do
			if m.pos then
				out[#out + 1], ids[m.id] = byId[m.id], byId[m.id]
			end
		end
		list, byId = out, ids
	end
	if changed or again then rev = rev + 1 end
end)

Model.Kind("group", function() return list, rev end)

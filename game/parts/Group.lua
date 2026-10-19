-- obs.group (types/observation.lua MM.ObsMember[]), per frame: your party's or raid's other members, read
-- STEP s apart (20 a second: they walk; Layers.lua:711-717) and the same tables between: the list, each
-- member and its position refilled. A member's class token, level (nil: too high to tell), dead or a
-- ghost, and where it stands (UnitPosition); nil where the client withholds it (instances, a secret
-- value: Layers.lua:727). You aren't in it; in no group, known and empty.

local _, ns = ...
local Atlas, Game = ns.Atlas, ns.Game

local STEP = 0.05 -- s (Layers.lua:717)
local PARTY, RAID = {}, {}
for i = 1, 40 do PARTY[i], RAID[i] = "party" .. i, "raid" .. i end

local group, members, spots = {}, {}, {} -- the list; its member tables and their positions, by place in it
local due = 0

Game.Part("group", function(obs)
	if obs.t < due then return group end
	due = obs.t + STEP
	local raid, n = IsInRaid(), 0
	local units, count = raid and RAID or PARTY, GetNumGroupMembers()
	for i = 1, raid and count or count - 1 do
		local unit = units[i]
		if not UnitIsUnit(unit, "player") then
			n = n + 1
			local m, p = members[n], spots[n]
			if not m then
				m, p = {}, {}
				members[n], spots[n] = m, p
			end
			local _, class = UnitClass(unit)
			local level = UnitLevel(unit)
			m.id, m.name, m.class, m.level, m.dead = UnitGUID(unit), UnitName(unit), class, level > 0 and level or nil,
				UnitIsDeadOrGhost(unit)
			local north, west, _, inst = UnitPosition(unit)
			if north and not issecretvalue(north) then
				p.inst, p.col, p.row = inst, Atlas.WorldToTile(north, west)
				m.pos = p
			else
				m.pos = nil
			end
			group[n] = m
		end
	end
	for i = #group, n + 1, -1 do group[i] = nil end
	return group
end)

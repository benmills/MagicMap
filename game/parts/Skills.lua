-- obs.skills (types/observation.lua), on change: your gathering skills, { herb = n, ore = n }: Herbalism's and
-- Mining's rank with its bonus (GetProfessions, GetProfessionInfo: their skill lines 182, 186), 0 for one you haven't
-- learnt. What a resource pin's difficulty badge reads (ui/Blips.lua). Read again on SKILL_LINES_CHANGED and at
-- each loading screen; a new table only when one changed.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local LINES = { [182] = "herb", [186] = "ore" } -- SkillLine ids: Herbalism, Mining

local skills -- the last handed over
local dirty = true
local function Dirty() dirty = true end
Runtime.On("SKILL_LINES_CHANGED", "game.skills", Dirty)
Runtime.On("PLAYER_ENTERING_WORLD", "game.skills enter", Dirty)

-- Each of GetProfessions' indices (prof1, prof2, then the secondary ones; nil where you have none).
local function Read(out, ...)
	for k = 1, select("#", ...) do
		local i = select(k, ...)
		if i then
			local _, _, rank, _, _, _, line, bonus = GetProfessionInfo(i)
			local kind = LINES[line]
			if kind then out[kind] = (rank or 0) + (bonus or 0) end
		end
	end
	return out
end

Game.Part("skills", function()
	if not dirty then return skills end
	dirty = false
	local out = Read({ herb = 0, ore = 0 }, GetProfessions())
	if skills and skills.herb == out.herb and skills.ore == out.ore then return skills end
	skills = out
	return skills
end)

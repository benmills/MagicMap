-- Which quests you could take now, from Atlas's quest facts and what the game says of you: obs.done (handed in),
-- obs.quests (your log), obs.you (level, faction, race, class). As Questie reads availability, simplified: not done
-- and not in your log; your level at least its required level; its faction, races and classes yours; its single
-- prerequisites one done (if any), its group ones all done; none it excludes done or in your log. A quest giver's
-- blip with no offer of ours by it gets its "!" from this (model/Blips.lua). Model.availableRev moves when any input does.

local _, ns = ...
local Model, Atlas = ns.Model, ns.Atlas

local NONE = {}
local done, log, inLog = NONE, nil, {}
local you = {}
Model.availableRev = 0

-- bit b (0-based) of mask m set (masks are whole numbers: no bit library needed)
local function Bit(m, b) return math.floor(m / 2 ^ b) % 2 == 1 end -- /: never 0 (a power of two)

local function Has(id) return done[id] == true end

function Model.CanTake(id)
	if done[id] or inLog[id] then return false end
	local q = Atlas.Quest(id)
	if not q then return false end
	if q.requiredLevel and you.level and you.level < q.requiredLevel then return false end
	if q.faction and you.faction and q.faction ~= you.faction then return false end
	if q.races and q.races > 0 and you.race and not Bit(q.races, you.race - 1) then return false end
	if q.classes and q.classes > 0 and you.class and not Bit(q.classes, you.class - 1) then return false end
	local single = q.preQuestSingle
	if single[1] then
		local any = false
		for _, p in ipairs(single) do if Has(p) then any = true break end end
		if not any then return false end
	end
	for _, p in ipairs(q.preQuestGroup) do if not Has(p) then return false end end
	for _, x in ipairs(q.exclusiveTo) do if Has(x) or inLog[x] then return false end end
	return true
end

Model.Part(function(obs)
	local changed = false
	if obs.done and obs.done ~= done then done, changed = obs.done, true end
	if obs.quests and obs.quests ~= log then
		log, changed = obs.quests, true
		inLog = {}
		for _, x in ipairs(log) do inLog[x.id] = true end
	end
	local y = obs.you
	if y.level ~= you.level or y.faction ~= you.faction or y.race ~= you.race or y.class ~= you.class then
		you.level, you.faction, you.race, you.class, changed = y.level, y.faction, y.race, y.class, true
	end
	if changed then Model.availableRev = Model.availableRev + 1 end
end)

-- obs.done (types/observation.lua), on change: the quests this character has handed in, as a set
-- (C_QuestLog.GetAllCompletedQuestIDs; GetQuestsCompleted on a client without it). Read at the first observe,
-- again a few seconds after entering the world (the server sends the list late), and after each quest handed
-- in or dropped. Model reads it to tell which quests a quest giver's blip can still offer (model/Available.lua).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local LATE = 5 -- s after entering the world: read again
local done, dirty = nil, true

local function Again() dirty = true end
Runtime.On("QUEST_TURNED_IN", "game.done", Again)
Runtime.On("QUEST_REMOVED", "game.done", Again)
Runtime.On("PLAYER_ENTERING_WORLD", "game.done", function()
	dirty = true
	Runtime.After(LATE, "game.done late", Again)
end)

Game.Part("done", function()
	if not dirty then return done end
	dirty = false
	local set = {}
	if C_QuestLog.GetAllCompletedQuestIDs then
		for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do set[id] = true end
	elseif GetQuestsCompleted then
		for id in pairs(GetQuestsCompleted() or {}) do set[id] = true end
	end
	if done then -- the same as before: kept (Model sees no change)
		local same = true
		for id in pairs(set) do if not done[id] then same = false break end end
		if same then for id in pairs(done) do if not set[id] then same = false break end end end
		if same then return done end
	end
	done = set
	return done
end)

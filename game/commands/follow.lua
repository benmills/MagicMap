-- follow (types/view.lua MM.CmdFollow): the game's super-tracked quest, watched in Blizzard's tracker;
-- false: none (Layers.lua:1033-1043). The same frame's obs.quests has it when sent from a click (carried
-- out in Input: game/parts/Quests.lua); from a ui step, the next frame's.

local _, ns = ...
local Game = ns.Game

Game.Handle("follow", function(c)
	if not c.quest then return C_SuperTrack.SetSuperTrackedQuestID(0) end
	C_QuestLog.AddQuestWatch(c.quest)
	C_SuperTrack.SetSuperTrackedQuestID(c.quest)
end)

-- questlog (types/view.lua MM.CmdQuestLog): the client's quest log opened on a quest. A Retail-engine
-- client's is the world map's quest panel (QuestMapFrame_OpenToQuestDetails); an older one's the
-- QuestLogFrame, its entry selected; else the log as L opens it.

local _, ns = ...
local Game = ns.Game

Game.Handle("questlog", function(c)
	local id = c.quest
	if QuestMapFrame_OpenToQuestDetails then return QuestMapFrame_OpenToQuestDetails(id) end
	local index = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
		or GetQuestLogIndexByID and GetQuestLogIndexByID(id)
	if QuestLogFrame and index and index > 0 and QuestLog_SetSelection then
		ShowUIPanel(QuestLogFrame)
		QuestLog_SetSelection(index)
		if QuestLog_Update then QuestLog_Update() end
		return
	end
	ToggleQuestLog()
end)

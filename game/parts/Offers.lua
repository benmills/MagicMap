-- obs.offers (types/observation.lua MM.ObsOffer[]), on change: quests to pick up on the zones of the
-- map shown (Game.shownInst, a frame behind; yours before the first; not while hidden), as the world map's
-- QuestOfferDataProvider reads them (Layers.lua:636-664): each zone asked once (the client fills it
-- in and fires QUESTLINE_UPDATE; with an argument, it wants every zone asked again), a quest on
-- several zones kept on the first, those in progress skipped, and those the client hides unless you
-- track hidden quests (a per-character CVar). Read again 0.3 s after QUESTLINE_UPDATE or
-- MINIMAP_UPDATE_TRACKING (Layers.lua:2219-2252), at once when another instance is shown. The spike
-- read them again after every QUEST_LOG_UPDATE too; what's offered changes with your log, so here only
-- after a quest is taken or given up or handed in (QUEST_ACCEPTED, QUEST_REMOVED: Forever's, as Questie's
-- EventHandler.lua:157-193) or a level gained: the client makes a table an offer each read (130 on a
-- continent: ~50 KB), and QUEST_LOG_UPDATE comes with every loot. Each offer is compared with its last
-- as it's read and kept if the same; a new table only when something changed.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local DELAY = 0.3 -- s (Layers.lua:1236)

local list -- the last handed over
local dirty, pending = true, false
local read -- the instance last read
local asked = {} -- uiMapID -> true
local last = {} -- questID -> its MM.ObsOffer in list
local seen = {} -- questID -> the read that found it
local order = {} -- this read's offers by questID, in list order
local reads = 0

local function Due() pending, dirty = false, true end
local function Soon()
	if pending then return end
	pending = true
	Runtime.After(DELAY, "game.offers refresh", Due)
end
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "MINIMAP_UPDATE_TRACKING" }) do
	Runtime.On(event, "game.offers", Soon)
end
Runtime.On("QUESTLINE_UPDATE", "game.offers", function(_, again)
	if again then wipe(asked) end
	Soon()
end)

-- Offer q on map as obs has it: its last if the same.
local function Offer(map, q)
	local id, name, line = q.questID, q.questName or ("Quest " .. q.questID), q.questLineName
	line = line ~= "" and line ~= name and line or nil
	local i, col, row = Atlas.MapToTile(map, q.x, q.y)
	local o = last[id]
	local p = o and o.pos
	if o and o.name == name and o.line == line and p.inst == i and p.col == col and p.row == row then return o end
	o = { questID = id, name = name, line = line, pos = { inst = i, col = col, row = row } }
	last[id] = o
	return o
end

local function Read(inst)
	reads = reads + 1
	local n, hidden, changed = 0, C_Minimap.IsTrackingHiddenQuests(), list == nil
	for _, z in ipairs(Atlas.Zones(inst)) do
		local map = z.uiMapID
		if not asked[map] then
			asked[map] = true
			C_QuestLine.RequestQuestLinesForMap(map)
		end
		for _, q in ipairs(C_QuestLine.GetAvailableQuestLines(map)) do
			local id = q.questID
			if seen[id] ~= reads and not q.inProgress and (hidden or not q.isHidden) then
				seen[id], n = reads, n + 1
				local o = Offer(map, q)
				order[n] = id
				if not changed and list[n] ~= o then changed = true end
			end
		end
	end
	for i = #order, n + 1, -1 do order[i] = nil end
	for id in pairs(last) do
		if seen[id] ~= reads then last[id], seen[id] = nil, nil end
	end
	if not changed and n == #list then return list end
	local out = {}
	for i = 1, n do out[i] = last[order[i]] end
	return out
end

Game.Part("offers", function(obs)
	local inst = Game.shownInst
	if inst == false then return list end -- (hidden: read once it's shown)
	inst = inst or obs.you.inst
	if dirty or inst ~= read then
		dirty, read = false, inst
		list = Read(inst)
	end
	return list
end)

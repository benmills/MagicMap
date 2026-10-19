-- obs.offers (types/observation.lua MM.ObsOffer[]), on change: quests to pick up on the zones of the
-- map shown (View.inst, a frame behind; yours until UI has shown one), as the world map's
-- QuestOfferDataProvider reads them (Layers.lua:636-664): each zone asked once (the client fills it
-- in and fires QUESTLINE_UPDATE; with an argument, it wants every zone asked again), a quest on
-- several zones kept on the first, those in progress skipped, and those the client hides unless you
-- track hidden quests (a per-character CVar). Read again 0.3 s after QUEST_LOG_UPDATE,
-- QUESTLINE_UPDATE or MINIMAP_UPDATE_TRACKING (Layers.lua:2219-2252), at once when another
-- instance is shown; a new table only when something changed.

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local DELAY = 0.3 -- s (Layers.lua:1236)

local list -- the last handed over
local dirty, pending = true, false
local shown, read -- the instance shown; the one last read
local asked = {} -- uiMapID -> true

local function Due() pending, dirty = false, true end
local function Soon()
	if pending then return end
	pending = true
	Runtime.After(DELAY, "game.offers refresh", Due)
end
Runtime.On("QUEST_LOG_UPDATE", "game.offers", Soon)
Runtime.On("MINIMAP_UPDATE_TRACKING", "game.offers", Soon)
Runtime.On("QUESTLINE_UPDATE", "game.offers", function(_, again)
	if again then wipe(asked) end
	Soon()
end)
Game.Apply("offers shown", function(view) shown = view.inst end)

local function Same(a, b)
	if #a ~= #b then return false end
	for i, o in ipairs(a) do
		local p = b[i]
		if o.questID ~= p.questID or o.name ~= p.name or o.line ~= p.line or o.pos.col ~= p.pos.col or o.pos.row ~= p.pos.row then
			return false
		end
	end
	return true
end

local function Read(inst)
	local out, seen, hidden = {}, {}, C_Minimap.IsTrackingHiddenQuests()
	for _, z in ipairs(Atlas.Zones(inst)) do
		local map = z.uiMapID
		if not asked[map] then
			asked[map] = true
			C_QuestLine.RequestQuestLinesForMap(map)
		end
		for _, q in ipairs(C_QuestLine.GetAvailableQuestLines(map)) do
			if not seen[q.questID] and not q.inProgress and (hidden or not q.isHidden) then
				seen[q.questID] = true
				local name, line = q.questName or ("Quest " .. q.questID), q.questLineName
				local i, col, row = Atlas.MapToTile(map, q.x, q.y)
				out[#out + 1] = { questID = q.questID, name = name, line = line ~= "" and line ~= name and line or nil,
					pos = { inst = i, col = col, row = row } }
			end
		end
	end
	return out
end

Game.Part("offers", function(obs)
	local inst = shown or obs.you.inst
	if dirty or inst ~= read then
		dirty, read = false, inst
		local new = Read(inst)
		if not (list and Same(new, list)) then list = new end
	end
	return list
end)

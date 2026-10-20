-- Oracles (types/observation.lua MM.Oracles, ADR 0001): what Model may ask Game in a frame.
-- Inside(quest, col, row): is the point in the quest's objective area, as the game draws it?
-- HasArea(quest): does the game draw an area at the quest's pin, its own or another of your
-- quests' on its map (Layers.lua:928-937)? nil: can't tell yet, ask again.
-- The client's own blobs answer, unseen: each quest drawn on a QuestPOIFrame set to its area's
-- uiMap (one per quest: the hit test names one quest under a point, so quests sharing a frame
-- answer for each other where their areas overlap), all one size under a holder at alpha 0.
-- The client lays a frame out only at the end of a frame and draws a blob into the rect laid
-- out then (spike-bugs L1, Layers.lua:802-817): a quest is drawn when first asked (nil: can't
-- tell yet) and again on a later frame, into its rect. Its frames never move, so a drawing
-- holds (cached per quest) until QUEST_POI_UPDATE, then is drawn again at the next ask.
-- A quest's area map and pin: obs.quests (areaMap, pin), or /mm check inside. Inside tests the
-- quest's own frame wherever its area lies, as the spike's InBlob the followed one (Layers.lua:
-- 1099-1102): none drawn, false everywhere; no areaMap, nil. A frame's asks share ASK_MS; past it,
-- nil (ask again).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local SIZE = 1024 -- px: every quest's frame (about the world map's canvas)
local ASK_MS = Runtime.CALL_MS / 2 -- a frame's asks: Model's own work and one dear draw past it fit the rest
local ART = "Interface\\WorldMap\\UI-QuestBlob-" -- Inside / Outside (Layers.lua:786)
local GREEN, RED, GREY = "|cff60ff60", "|cffff6060", "|cff999999"

local obs = Game.obs
local holder = CreateFrame("Frame", nil, UIParent)
holder:SetSize(SIZE, SIZE)
holder:SetPoint("TOPLEFT")
holder:SetFrameStrata("BACKGROUND")
holder:SetAlpha(0)

-- quest -> { map, x, y (its pin on map), f (its frame), drawn (the frame it was last drawn in), has (an area at its pin) }
local areas = {}
local free = {} -- frames no quest holds: laid out, so a drawing holds at once
local quests -- the obs.quests areas came from
local at, spent = 0, 0 -- this frame, and its ms in Inside

local function Take()
	local f = table.remove(free)
	if f then return f end
	f = CreateFrame("QuestPOIFrame", nil, holder)
	f:SetAllPoints()
	f:EnableMouse(false)
	f:SetFillTexture(ART .. "Inside")
	f:SetBorderTexture(ART .. "Outside")
	f:GetRect() -- (reading it lays it out in the client: Layers.lua:812)
	f.born = Runtime.frames -- laid out at this frame's end
	return f
end

local function Note(quest, map, x, y)
	local a = areas[quest]
	if not a then
		a = {}
		areas[quest] = a
	end
	if a.map ~= map then a.map, a.drawn, a.has = map, nil, nil end
	if a.x ~= x or a.y ~= y then a.x, a.y, a.has = x, y, nil end
end

local function Forget(quest)
	local f = areas[quest].f
	if f then
		f:DrawNone()
		free[#free + 1] = f
	end
	areas[quest] = nil
end

-- (Only on a map Atlas has a rect for: the point is in tile space.)
local function Sync(list)
	quests = list
	local seen = {}
	for _, q in ipairs(list) do
		if q.areaMap and q.pin and Atlas.MapRect(q.areaMap) then
			Note(q.id, q.areaMap, Atlas.TileToMap(q.areaMap, q.pin.col, q.pin.row))
			seen[q.id] = true
		end
	end
	for quest in pairs(areas) do
		if not seen[quest] then Forget(quest) end
	end
end

-- True once a's frame holds its quest drawn into a rect the client laid out (a.has: an area at its
-- pin); else drawn now, false (the frame born this frame: drawn again on a later one).
local function Ready(quest, a)
	if a.has ~= nil then return true end
	if a.drawn == Runtime.frames then return false end
	local f = a.f
	if not f then
		f = Take()
		a.f = f
	end
	f:SetMapID(a.map)
	f:DrawBlob(quest, true)
	a.drawn = Runtime.frames
	if a.drawn == f.born then return false end
	a.has = f:UpdateMouseOverTooltip(a.x, a.y) == quest
	return true
end

-- This frame's asks: synced with obs.quests, and whether they're spent.
local function Ask()
	if at ~= Runtime.frames then at, spent = Runtime.frames, 0 end
	if obs.quests and obs.quests ~= quests then Sync(obs.quests) end
	return spent < ASK_MS
end

local function Inside(quest, col, row)
	if not Ask() then return nil end
	local a = areas[quest]
	if not a then return nil end
	local t0, answer = debugprofilestop(), nil
	if Ready(quest, a) then answer = a.f:UpdateMouseOverTooltip(Atlas.TileToMap(a.map, col, row)) == quest end
	spent = spent + debugprofilestop() - t0
	return answer
end

-- Any of your quests' areas on its map at its pin (Layers.lua:928-937: BlobAt over the map's frames).
local function HasArea(quest)
	if not Ask() then return nil end
	local a = areas[quest]
	if not a then return false end
	local t0, hit, unsure = debugprofilestop(), false, false
	for id, b in pairs(areas) do
		if b.map == a.map then
			if spent + debugprofilestop() - t0 >= ASK_MS then -- (the rest next frame)
				unsure = true
				break
			end
			if not Ready(id, b) then
				unsure = true
			elseif id == quest and b.has or id ~= quest and b.f:UpdateMouseOverTooltip(a.x, a.y) == id then
				hit = true
				break
			end
		end
	end
	spent = spent + debugprofilestop() - t0
	if hit then return true end
	if not unsure then return false end
end

Game.oracles.Inside = Runtime.Wrap("game.oracle inside", Inside)
Game.oracles.HasArea = Runtime.Wrap("game.oracle has area", HasArea)

-- The client's quest areas changed: each drawn again at its next ask.
Runtime.On("QUEST_POI_UPDATE", "game.oracle: poi update", function()
	for _, a in pairs(areas) do a.drawn, a.has = nil, nil end
end)

-- /mm check inside -----------------------------------------------------------------------

-- Your quests here (on your map and the maps above it Atlas has, each on the smallest: its
-- area's), asked where you stand in one frame and answered in the next; the client's own
-- answer beside it where it has one (C_Minimap.IsInsideQuestBlob).
local function Check()
	local col, row = obs.you.col, obs.you.row
	if not col then return Game.Print("check inside: your position isn't known here") end
	local list, maps = {}, {} -- quest ids; quest -> its map
	local info = C_Map.GetMapInfo(C_Map.GetBestMapForUnit("player"))
	while info and info.mapType >= Enum.UIMapType.Zone do
		for _, q in ipairs(Atlas.MapRect(info.mapID) and C_QuestLog.GetQuestsOnMap(info.mapID) or {}) do
			if not q.isMapIndicatorQuest and not maps[q.questID] then
				maps[q.questID] = info.mapID
				Note(q.questID, info.mapID, q.x, q.y)
				list[#list + 1] = q.questID
			end
		end
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	for _, quest in ipairs(list) do Game.oracles.Inside(quest, col, row) end
	Runtime.After(0, "check inside", function()
		Game.Print(string.format("check inside: %d quests here, at %.3f, %.3f", #list, col, row))
		for _, quest in ipairs(list) do
			local inside, a = Game.oracles.Inside(quest, col, row), areas[quest]
			local client = C_Minimap.IsInsideQuestBlob and C_Minimap.IsInsideQuestBlob(quest)
			print(string.format("  %s  %s (%d, map %d)%s",
				inside == nil and GREY .. "no answer|r" or inside and GREEN .. "inside|r"
					or a and a.has == false and GREY .. "no area at its pin|r" or RED .. "outside|r",
				C_QuestLog.GetTitleForQuestID(quest) or "?", quest, maps[quest],
				client == nil and "" or "  client: " .. (client and "inside" or "outside")))
		end
	end)
end

Game.Slash("check inside", "your quests here: is where you stand in each one's area (as the game draws it)?", function()
	Runtime.After(0, "check inside", Check) -- (asked in a frame: drawn before its layout, answered after)
end)

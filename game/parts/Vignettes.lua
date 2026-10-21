-- obs.vignettes (types/observation.lua MM.ObsVignette[]), on change: what the game shows near you now
-- (C_VignetteInfo, on the map you're on: Landmarks.lua:74-108), those not dead with a name and a place
-- there, placed by that map's rect: Atlas's, or the client's for one Atlas keeps none of (a micro map: a
-- cave, an inn; Core.lua:838-865); one whose art (its atlas) is a rare's or an elite's is a rare, which Model remembers, with its
-- NPC from the creature's GUID (objectGUID) when the client has one. Read again 0.3 s after
-- VIGNETTES_UPDATED or VIGNETTE_MINIMAP_UPDATED (Landmarks.lua:150-160; Layers.lua:1233-1242), at once on
-- another map. And the rare you target (not a player, classed rare or rareelite: Landmarks.lua:154-156),
-- at your position then (an NPC's isn't given), with its NPC (its GUID's: Landmarks.lua:17-22), while it's
-- your target: not a vignette (target), a rare you've seen for Model to remember (Landmarks.lua:25-44).
-- Each read compared with its last and kept if the same; a new list only when something changed.
-- E2: a position's x and y are read in two statements (`pos and pos:GetXY()` is one value).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local DELAY = 0.3 -- s (Layers.lua:1236)

local list -- the last handed over
local found, aim = {}, true -- the vignettes as last read; the target to read again
local target = false -- the rare you target, as handed over
local dirty, pending, map = true, false, nil -- map: the one last read on
local last = {} -- GUID -> its MM.ObsVignette
local rects = {} -- uiMap -> its rect { inst, c0, r0, c1, r1 } | false: none

local function Due() pending, dirty = false, true end
local function Soon()
	if pending then return end
	pending = true
	Runtime.After(DELAY, "game.vignettes refresh", Due)
end
Runtime.On("VIGNETTES_UPDATED", "game.vignettes", Soon)
Runtime.On("VIGNETTE_MINIMAP_UPDATED", "game.vignettes", Soon)
Runtime.On("PLAYER_TARGET_CHANGED", "game.vignettes target", function() aim = true end)

-- A creature's NPC ID from its GUID ("Creature-0-[server]-[instance]-[zone]-[id]-[spawn]").
local function Npc(guid)
	if not guid or issecretvalue(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return (kind == "Creature" or kind == "Vehicle") and tonumber(id) or nil
end

-- A map's rect in tile space, the client's (Core.lua:838-857): Atlas keeps no dungeon floors or micro maps.
local function MapRect(uiMap)
	local inst, tl = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(0, 0))
	local inst2, br = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(1, 1))
	if not (tl and br and inst == inst2) then return nil end
	local c0, r0 = Atlas.WorldToTile(tl:GetXY())
	local c1, r1 = Atlas.WorldToTile(br:GetXY())
	if c1 > c0 and r1 > r0 then return { inst = inst, c0 = c0, r0 = r0, c1 = c1, r1 = r1 } end
end

local function Rect(uiMap)
	local r = rects[uiMap]
	if r == nil then
		local a = Atlas.MapRect(uiMap)
		r = a and { inst = a.inst, c0 = a.col0, r0 = a.row0, c1 = a.col1, r1 = a.row1 } or MapRect(uiMap) or false
		rects[uiMap] = r
	end
	return r
end

local function Read(uiMap, r)
	wipe(found)
	local seen = {}
	for _, guid in ipairs(C_VignetteInfo.GetVignettes()) do
		local info = C_VignetteInfo.GetVignetteInfo(guid)
		local pos = info and not info.isDead and info.name and C_VignetteInfo.GetVignettePosition(guid, uiMap)
		if pos then
			local x, y = pos:GetXY()
			local inst, col, row = r.inst, r.c0 + (r.c1 - r.c0) * x, r.r0 + (r.r1 - r.r0) * y
			local atlas = info.atlasName
			local low = (atlas or ""):lower()
			local rare, npc = (low:find("rare") or low:find("elite")) ~= nil, Npc(info.objectGUID)
			local v = last[guid]
			local p = v and v.pos
			if not (v and v.name == info.name and v.icon.atlas == atlas and v.rare == rare and v.npcID == npc
				and p.inst == inst and p.col == col and p.row == row) then
				v = { id = guid, name = info.name, rare = rare, npcID = npc, icon = { atlas = atlas },
					pos = { inst = inst, col = col, row = row } }
			end
			seen[guid] = v
			found[#found + 1] = v
		end
	end
	last = seen
end

local function Target(you)
	local c = UnitExists("target") and not UnitIsPlayer("target") and UnitClassification("target")
	if not (c == "rare" or c == "rareelite") or not you.col then return false end
	local guid = UnitGUID("target")
	return { id = guid, name = UnitName("target"), rare = true, npcID = Npc(guid), target = true,
		pos = { inst = you.inst, col = you.col, row = you.row } }
end

Game.Part("vignettes", function(obs)
	local you, changed = obs.you, list == nil
	if aim then
		aim = false
		local t = Target(you)
		changed = changed or t ~= target
		target = t
	end
	if dirty or you.uiMap ~= map then
		dirty, map = false, you.uiMap
		local was = #found
		local r = map and Rect(map)
		if r then Read(map, r) else wipe(found) end
		for i = 1, #found do
			if not changed and list[i] ~= found[i] then changed = true end
		end
		changed = changed or #found ~= was
	end
	if not changed then return list end
	local out = {}
	for i = 1, #found do out[i] = found[i] end
	if target then out[#out + 1] = target end
	list = out
	return list
end)

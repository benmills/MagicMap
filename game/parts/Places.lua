-- obs.places (types/observation.lua MM.ObsPlace[]), on change: the live places the game marks on the map
-- shown (Game.shownInst, a frame behind; yours before the first; not while hidden), each asked of its
-- continent's map, then its zones', a place kept on the first that has it (Layers.lua:450-457): flight
-- points (C_TaxiMap), dungeon entrances (C_EncounterJournal) and graveyards (C_DeathInfo; Layers.lua:463-540),
-- and the zones' area POIs (C_AreaPoiInfo; Landmarks.lua:120-141). A kind is read again 0.3 s after its
-- events (Layers.lua:1233-1242, 2220-2233; Landmarks.lua:150-160): flight points TAXIMAP_OPENED, graveyards
-- PLAYER_DEAD, PLAYER_ALIVE and PLAYER_UNGHOST, area POIs AREA_POIS_UPDATED; all at once when another instance
-- is shown. Each place is compared with its last as it's read and kept if the same; a new list only when one
-- changed. Atlas has the static ones (Model merges: M4.3).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local DELAY = 0.3 -- s (Layers.lua:1236)
local GRAVEYARD = "poi-graveyard-neutral" -- Layers.lua:490
local FACTION = { [1] = "H", [2] = "A" } -- a flight point's (0: neutral; Layers.lua:459)
local KINDS = { "flight", "dungeon", "graveyard", "poi" }

local list -- the last handed over
local read -- the instance last read
local maps = {} -- its continent's map (if any), then its zones'
local found = { flight = {}, dungeon = {}, graveyard = {}, poi = {} } -- kind -> its places, as last read
local last = {} -- key -> its MM.ObsPlace
local seen = {} -- key -> the read that found it
local dirty, pending = { flight = true, dungeon = true, graveyard = true, poi = true }, {}
local reads = 0

for _, on in ipairs({ { "flight", "TAXIMAP_OPENED" }, { "graveyard", "PLAYER_DEAD" }, { "graveyard", "PLAYER_ALIVE" },
	{ "graveyard", "PLAYER_UNGHOST" }, { "poi", "AREA_POIS_UPDATED" } }) do
	local kind = on[1]
	local function Due() pending[kind], dirty[kind] = false, true end
	Runtime.On(on[2], "game.places " .. kind, function()
		if pending[kind] then return end
		pending[kind] = true
		Runtime.After(DELAY, "game.places " .. kind .. " refresh", Due)
	end)
end

-- The place kind:id at p on map, once a read: its last if the same. Its art: the atlas the client names,
-- else (an area POI it names none for) its textureIndex, POIIcons' cell (icon = { atlas | cell }).
local function Put(out, kind, id, map, p, name, text, atlas, faction, known, cell)
	local key = kind .. ":" .. id
	if seen[key] == reads then return end
	seen[key] = reads
	local x, y = p:GetXY()
	local inst, col, row = Atlas.MapToTile(map, x, y)
	local o = last[key]
	local q = o and o.pos
	if not (o and o.name == name and o.text == text and o.icon.atlas == atlas and o.icon.cell == cell and o.faction == faction
		and o.known == known and q.inst == inst and q.col == col and q.row == row) then
		o = { key = key, kind = kind, name = name, text = text, icon = { atlas = atlas, cell = cell }, faction = faction, known = known,
			pos = { inst = inst, col = col, row = row } }
		last[key] = o
	end
	out[#out + 1] = o
end

-- A flight point you have, if the client says (isUndiscovered); nil: it doesn't.
local function Known(n)
	if n.isUndiscovered == nil then return nil end
	return not n.isUndiscovered
end

local READ = {
	flight = function(out, map)
		for _, n in ipairs(C_TaxiMap.GetTaxiNodesForMap(map)) do
			Put(out, "flight", n.nodeID, map, n.position, n.name, nil, n.atlasName, FACTION[n.faction], Known(n))
		end
	end,
	dungeon = function(out, map)
		for _, d in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(map)) do
			Put(out, "dungeon", d.journalInstanceID, map, d.position, d.name, d.description, d.atlasName)
		end
	end,
	graveyard = function(out, map)
		for _, g in ipairs(C_DeathInfo.GetGraveyardsForMap(map)) do
			Put(out, "graveyard", g.graveyardID, map, g.position, g.name, nil, GRAVEYARD)
		end
	end,
	poi = function(out, map)
		if map == maps.continent then return end -- (the zones': Landmarks.lua:123)
		for _, id in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(map)) do
			local info = C_AreaPoiInfo.GetAreaPOIInfo(map, id)
			if info then Put(out, "poi", id, map, info.position, info.name, info.description, info.atlasName, nil, nil, info.textureIndex) end
		end
	end,
}

local function Read(kind)
	reads = reads + 1
	local out = found[kind]
	wipe(out)
	for _, map in ipairs(maps) do READ[kind](out, map) end
	for key, o in pairs(last) do
		if o.kind == kind and seen[key] ~= reads then last[key], seen[key] = nil, nil end
	end
end

Game.Part("places", function(obs)
	local inst = Game.shownInst
	if inst == false then return list end -- (hidden: read once it's shown)
	inst = inst or obs.you.inst
	if inst ~= read then
		read = inst
		wipe(maps)
		maps.continent = Atlas.Continent(inst)
		maps[1] = maps.continent
		for _, z in ipairs(Atlas.Zones(inst)) do maps[#maps + 1] = z.uiMapID end
		for _, kind in ipairs(KINDS) do dirty[kind] = true end
	end
	local any = false
	for _, kind in ipairs(KINDS) do
		if dirty[kind] then
			dirty[kind], any = false, true
			Read(kind)
		end
	end
	if not any then return list end
	local n, changed = 0, list == nil
	for _, kind in ipairs(KINDS) do
		for _, o in ipairs(found[kind]) do
			n = n + 1
			if not changed and list[n] ~= o then changed = true end
		end
	end
	if not changed and n == #list then return list end
	local out = {}
	for _, kind in ipairs(KINDS) do
		for _, o in ipairs(found[kind]) do out[#out + 1] = o end
	end
	list = out
	return list
end)

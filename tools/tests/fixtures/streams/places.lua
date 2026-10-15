-- Fixture stream (types/observation.lua MM.ObsPlace[]): live places the game marks
-- (Atlas has the static ones), for Model alone (tools/tests/replay.lua). Elwynn
-- Forest's: flight points (one known, one not, one not known either way), Goldshire,
-- its graveyard, the Deadmines; Sentinel Hill's flight point is learned; on Westfall's
-- map its graveyard joins.
-- On-change parts keep their table while nothing changes: a new table is a change.

local function At(frame, places)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, places = places,
		you = { inst = 0, col = 31.95, row = 49.75, facing = 0, uiMap = 1429, level = 8, faction = "A" } }
end
local function Place(key, kind, name, col, row, more)
	local p = more or {}
	p.key, p.kind, p.name, p.pos = key, kind, name, { inst = 0, col = col, row = row }
	return p
end
local function Flight(id, name, col, row, known)
	return Place("flight:" .. id, "flight", name, col, row, { faction = "A", known = known, icon = { atlas = "TaxiNode_Alliance" } })
end

local stormwind = Flight(2, "Stormwind, Elwynn", 31.103, 48.561, true)
local lakeshire = Flight(5, "Lakeshire, Redridge", 36.184, 49.68, nil)
local goldshire = Place("poi:7", "poi", "Goldshire", 31.881, 49.775, { icon = { atlas = "poi-town" } })
local grave = Place("graveyard:1", "graveyard", "Goldshire", 32.52, 49.88, { icon = { atlas = "poi-graveyard-neutral" } })
local deadmines = Place("dungeon:63", "dungeon", "Deadmines", 28.848, 53.015, { text = "A dungeon", icon = { atlas = "Dungeon" } })
local elwynn = { stormwind, Flight(4, "Sentinel Hill, Westfall", 30.056, 51.929, false), lakeshire, goldshire, grave, deadmines }
local learned = { stormwind, Flight(4, "Sentinel Hill, Westfall", 30.056, 51.929, true), lakeshire, goldshire, grave, deadmines }
local westfall = { learned[1], learned[2], lakeshire, goldshire, grave, deadmines,
	Place("graveyard:2", "graveyard", "Sentinel Hill", 30.07, 51.69, { icon = { atlas = "poi-graveyard-neutral" } }) }

return {
	At(1, elwynn),
	At(60, elwynn),
	At(300, learned),
	At(360, learned),
	At(420, westfall),
}

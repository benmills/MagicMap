-- Fixture stream (types/observation.lua MM.ObsTracking[]): Blizzard's minimap tracking,
-- for Model alone (tools/tests/replay.lua). Flight masters, quest POIs and points of
-- interest are duplicates (our layers draw them): Game turns off the two that are on
-- while it senses; the user turns Find Herbs off; the map goes back to Blizzard's and
-- the two come back on.
-- On-change parts keep their table while nothing changes: a new table is a change.

local function At(frame, tracking)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, tracking = tracking,
		you = { inst = 0, col = 31.95, row = 49.75, facing = 0, uiMap = 1429, level = 8, faction = "A" } }
end
local function T(id, name, texture, active, kind) return { id = id, name = name, texture = texture, active = active, kind = kind } end

local mail, inn = T(64, "Mailbox", 136459, true), T(128, "Innkeeper", 136458, true)
local poi = T(8192, "Points of Interest", 136457, false, "duplicate")
local herbs = T(2383, "Find Herbs", 133939, true)
local start = { T(8, "Flight Master", 136456, true, "duplicate"), herbs, T(65536, "Track Quest POIs", 136455, true, "duplicate"), poi, mail, inn }
local sensing = { T(8, "Flight Master", 136456, false, "duplicate"), herbs, T(65536, "Track Quest POIs", 136455, false, "duplicate"), poi, mail, inn }
local noHerbs = { sensing[1], T(2383, "Find Herbs", 133939, false), sensing[3], poi, mail, inn }
local released = { start[1], noHerbs[2], start[3], poi, mail, inn }

return {
	At(1, start),
	At(30, sensing),
	At(60, sensing),
	At(120, noHerbs),
	At(240, released),
	At(300, released),
}

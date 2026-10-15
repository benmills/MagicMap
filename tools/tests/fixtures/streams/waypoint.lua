-- Fixture stream (types/observation.lua obs.waypoint, MM.Pos|false): the user waypoint,
-- for Model alone (tools/tests/replay.lua). None; set on the Jasperlode Mine; moved to
-- the Eastvale Logging Camp; cleared; set in Durotar while browsing Kalimdor (another
-- instance than yours).
-- On-change parts keep their table while nothing changes: a new table is a change.

local function At(frame, waypoint)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, waypoint = waypoint,
		you = { inst = 0, col = 31.95, row = 49.75, facing = 0, uiMap = 1429, level = 8, faction = "A" } }
end

local jasper = { inst = 0, col = 33.2, row = 48.98 }
local eastvale = { inst = 0, col = 34.29, row = 49.87 }
local durotar = { inst = 1, col = 42.0, row = 28.5 }

return {
	At(1, false),
	At(30, jasper),
	At(60, jasper),
	At(90, jasper),
	At(120, eastvale),
	At(180, false),
	At(240, durotar),
	At(300, durotar),
}

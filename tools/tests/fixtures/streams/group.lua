-- Fixture stream (types/observation.lua MM.ObsMember[]): your party at ~20 Hz, for Model
-- alone (tools/tests/replay.lua). Two members walk with you toward the Fargodeep Mine;
-- Brannock dies there; Elandra's position is withheld (she's ported into an instance),
-- then she leaves the party; then you're in none (known and empty). You aren't in it.
-- Per frame: a part Game may reuse and mutate, so each frame's is its own here.

local function At(frame, col, row, group)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, group = group,
		you = { inst = 0, col = col, row = row, facing = 3.6, uiMap = 1429, level = 8, faction = "A" } }
end
local function Brannock(col, row, dead)
	return { id = "Player-4395-0A1B2C3D", name = "Brannock", class = "WARRIOR", level = 9, dead = dead,
		pos = { inst = 0, col = col, row = row } }
end
local function Elandra(col, row)
	return { id = "Player-4395-0A1B2C3E", name = "Elandra", class = "PRIEST", level = 8,
		pos = col and { inst = 0, col = col, row = row } }
end

local out = {}
for i = 0, 10 do
	local f = 1 + 3 * i
	local col, row = 31.95 - 0.01 * i, 49.75 + 0.04 * i
	out[#out + 1] = At(f, col, row, { Brannock(col + 0.01, row + 0.02, false), Elandra(col - 0.01, row + 0.01) })
end
out[#out + 1] = At(34, 31.85, 50.15, { Brannock(31.86, 50.17, true), Elandra(31.84, 50.16) })
out[#out + 1] = At(37, 31.85, 50.15, { Brannock(31.86, 50.17, true), Elandra(nil) })
out[#out + 1] = At(40, 31.85, 50.15, { Brannock(31.86, 50.17, true), Elandra(nil) })
out[#out + 1] = At(43, 31.85, 50.15, { Brannock(31.86, 50.17, true) })
out[#out + 1] = At(46, 31.85, 50.15, {})
return out

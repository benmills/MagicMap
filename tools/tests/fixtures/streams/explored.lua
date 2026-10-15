-- Fixture stream (types/observation.lua obs.explored, table<AreaID, boolean>): the areas
-- Game has checked (a missing key is unknown), for Model alone (tools/tests/replay.lua).
-- Goldshire; then the Fargodeep Mine (explored), the Stonefield Farm and the Maclure
-- Vineyards (not); you explore the Stonefield Farm, and more of Elwynn is checked.
-- On-change parts keep their table while nothing changes: a new table is a change.

local function At(frame, col, row, explored)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, explored = explored,
		you = { inst = 0, col = col, row = row, facing = 3.9, uiMap = 1429, level = 8, faction = "A" } }
end

local some = { [87] = true, [57] = true, [63] = false, [64] = false }

return {
	At(1, 31.95, 49.75, { [87] = true }),
	At(60, 31.9, 49.9, some),
	At(120, 31.8, 50.1, some),
	At(300, 31.38, 50.55, { [87] = true, [57] = true, [63] = true, [64] = false, [9] = true, [18] = true,
		[54] = false, [88] = false, [91] = false }),
}

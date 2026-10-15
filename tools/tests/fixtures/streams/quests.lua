-- Fixture stream (types/observation.lua MM.ObsQuest[]): your quest log in Goldshire,
-- Elwynn Forest, at level 8, for Model alone (tools/tests/replay.lua). Kobold Candles is
-- followed and goes 3/8 to 4/8; the follow moves to The Fargodeep Mine, which completes
-- (its pin moves to the turn-in) and is handed in, and The Jasperlode Mine is taken; a
-- loading frame doesn't know (nil); then the log is abandoned (known and empty).
-- `areas`: the objective areas Replay.Oracles answers Inside from (circles in tile
-- space); Hogger has none (Model estimates), nor do quests ready to turn in.
-- On-change parts keep their table while nothing changes: a new table is a change.

local function At(frame, col, row, quests)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, quests = quests,
		you = { inst = 0, col = col, row = row, facing = 3.4, uiMap = 1429, level = 8, faction = "A", dead = false, ghost = false, combat = false } }
end
local function Pos(col, row) return { inst = 0, col = col, row = row } end

local candles = { id = 60, title = "Kobold Candles", level = 7, trivial = false, complete = false, followed = true, areaMap = 1429,
	objectives = { { type = "item", text = "Large Candle: 3/8", have = 3, need = 8, finished = false, itemID = 772 } }, pin = Pos(31.775, 50.39) }
local gold = { id = 47, title = "Gold Dust Exchange", level = 7, trivial = false, complete = false, followed = false, areaMap = 1429,
	objectives = { { type = "item", text = "Gold Dust: 0/10", have = 0, need = 10, finished = false, itemID = 773 } }, pin = Pos(31.8, 50.3) }
local mine = { id = 62, title = "The Fargodeep Mine", level = 7, trivial = false, complete = false, followed = false, areaMap = 1429,
	objectives = { { type = "event", text = "Scout through the Fargodeep Mine", finished = false } }, pin = Pos(31.74, 50.42) }
local frontier = { id = 52, title = "Protect the Frontier", level = 10, trivial = false, complete = false, followed = false, areaMap = 1429,
	objectives = { { type = "monster", text = "Prowler slain: 2/8", have = 2, need = 8, finished = false },
		{ type = "monster", text = "Young Forest Bear slain: 0/5", have = 0, need = 5, finished = false } }, pin = Pos(33.95, 49.95) }
local hogger = { id = 176, title = "Wanted:  \"Hogger\"", level = 11, trivial = false, complete = false, followed = false,
	objectives = { { type = "item", text = "Huge Gnoll Claw: 0/1", have = 0, need = 1, finished = false, itemID = 1931 } }, pin = Pos(30.749, 50.919) }
local lovers = { id = 106, title = "Young Lovers", level = 6, trivial = false, complete = true, followed = false, objectives = {}, pin = Pos(31.063, 50.619) }
local cleanup = { id = 7, title = "Kobold Camp Cleanup", level = 2, trivial = true, complete = true, followed = false,
	objectives = { { type = "monster", text = "Kobold Vermin slain: 10/10", have = 10, need = 10, finished = true } }, pin = Pos(32.305, 48.66) }

local log1 = { candles, gold, mine, frontier, hogger, lovers, cleanup }
local candles2 = { id = 60, title = "Kobold Candles", level = 7, trivial = false, complete = false, followed = true, areaMap = 1429,
	objectives = { { type = "item", text = "Large Candle: 4/8", have = 4, need = 8, finished = false, itemID = 772 } }, pin = Pos(31.775, 50.39) }
local log2 = { candles2, gold, mine, frontier, hogger, lovers, cleanup }
local candles3 = { id = 60, title = "Kobold Candles", level = 7, trivial = false, complete = false, followed = false, areaMap = 1429,
	objectives = candles2.objectives, pin = candles2.pin }
local mine2 = { id = 62, title = "The Fargodeep Mine", level = 7, trivial = false, complete = false, followed = true, areaMap = 1429,
	objectives = mine.objectives, pin = mine.pin }
local log3 = { candles3, gold, mine2, frontier, hogger, lovers, cleanup }
local mine3 = { id = 62, title = "The Fargodeep Mine", level = 7, trivial = false, complete = true, followed = true,
	objectives = { { type = "event", text = "Scout through the Fargodeep Mine", finished = true } }, pin = Pos(31.862, 49.748) }
local log4 = { candles3, gold, mine3, frontier, hogger, lovers, cleanup }
local jasper = { id = 76, title = "The Jasperlode Mine", level = 10, trivial = false, complete = false, followed = false, areaMap = 1429,
	objectives = { { type = "event", text = "Scout through the Jasperlode Mine", finished = false } }, pin = Pos(33.2, 48.98) }
local log5 = { candles3, gold, frontier, hogger, lovers, cleanup, jasper }

return {
	At(1, 31.95, 49.75, log1),
	At(60, 31.91, 49.9, log1),
	At(180, 31.82, 50.2, log2),
	At(240, 31.8, 50.3, log2),
	At(360, 31.77, 50.38, log3),
	At(540, 31.74, 50.42, log4),
	At(720, 31.86, 49.76, log5),
	At(780, 31.86, 49.76, nil),
	At(840, 31.86, 49.76, log5),
	At(900, 31.86, 49.76, {}),
	areas = {
		[60] = { inst = 0, col = 31.775, row = 50.39, r = 0.08 },
		[47] = { inst = 0, col = 31.8, row = 50.32, r = 0.1 },
		[62] = { inst = 0, col = 31.74, row = 50.42, r = 0.05 },
		[52] = { inst = 0, col = 33.95, row = 49.95, r = 0.25 },
		[76] = { inst = 0, col = 33.2, row = 48.98, r = 0.05 },
	},
}

-- Fixture stream (types/observation.lua MM.ObsVignette[]): what the game shows near you,
-- for Model alone (tools/tests/replay.lua). None; Mother Fang (a rare) at the
-- Jasperlode Mine; a chest beside her; she wanders; she's killed; the chest is looted.
-- On-change parts keep their table while nothing changes: a new table is a change.

local function At(frame, vignettes)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, vignettes = vignettes,
		you = { inst = 0, col = 33.1, row = 49.05, facing = 0.6, uiMap = 1429, level = 8, faction = "A" } }
end
local function Fang(col, row)
	return { id = "Vignette-0-4395-0-1519-471-000048D2F1", name = "Mother Fang", rare = true, npcID = 471,
		icon = { atlas = "VignetteKill" }, pos = { inst = 0, col = col, row = row } }
end

local chest = { id = "Vignette-0-4395-0-1519-0-000048D2F2", name = "Battered Chest", rare = false,
	icon = { atlas = "VignetteLoot" }, pos = { inst = 0, col = 33.21, row = 49.02 } }
local fang = { Fang(33.165, 48.972) }
local both = { fang[1], chest }

return {
	At(1, {}),
	At(60, fang),
	At(90, fang),
	At(120, both),
	At(180, { Fang(33.18, 48.99), chest }),
	At(240, { chest }),
	At(300, {}),
}

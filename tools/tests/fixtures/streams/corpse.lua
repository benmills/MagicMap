-- Fixture stream (types/observation.lua obs.corpse, MM.Pos|false): dying to Hogger, for
-- Model alone (tools/tests/replay.lua). In combat, then dead at your body (no corpse
-- known yet); released, a ghost at the Goldshire graveyard, where the client knows the
-- corpse only 3 s later (G4); walking back; resurrected there (none again).
-- On-change parts keep their table while nothing changes: a new table is a change.

local function At(frame, col, row, state, corpse)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, corpse = corpse,
		you = { inst = 0, col = col, row = row, facing = 2.2, uiMap = 1429, level = 8, faction = "A",
			dead = state ~= "alive" and state ~= "combat", ghost = state == "ghost", combat = state == "combat" } }
end

local body = { inst = 0, col = 30.8, row = 50.85 }

return {
	At(1, 30.8, 50.85, "combat", false),
	At(60, 30.8, 50.85, "dead", false),
	At(120, 32.52, 49.88, "ghost", false),
	At(240, 32.52, 49.88, "ghost", false),
	At(300, 32.5, 49.9, "ghost", body),
	At(360, 32.2, 50.15, "ghost", body),
	At(420, 31.6, 50.4, "ghost", body),
	At(480, 30.85, 50.82, "ghost", body),
	At(540, 30.8, 50.85, "alive", false),
}

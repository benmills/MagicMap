-- G4: the corpse pin showed only after toggling the layer: the client knows where your corpse is only
-- a while after you release, and fires no event then. PREVENTED: while you're a ghost with none known,
-- Game asks again every second (game/parts/Corpse.lua), so it's in the Observation within a poll of the
-- client knowing it, with no event, and Model's target that frame: the view, looking elsewhere, glides
-- back to you (ui/Path.lua); found, Game stops asking; alive again, none and no target.
local T = ...
local sim, ns = T.Shown()
local A, Game, Model = ns.Atlas, ns.Game, ns.Model
local Camera = ns.UI.Camera
ns.UI.Motion.SetFollow(false) -- looking elsewhere
local body = { inst = 0, col = 32.2, row = 50.15 } -- Elwynn, by the Fargodeep Mine
local asked, ask = 0, C_DeathInfo.GetCorpseMapPosition
C_DeathInfo.GetCorpseMapPosition = function(id)
	asked = asked + 1
	return ask(id)
end

-- Dead, then released: a ghost, and for 3 s the client doesn't know where the corpse is.
sim.units.player.dead = true
sim.FireEvent("PLAYER_DEAD")
sim.Run(0.5)
sim.ghost = true
sim.FireEvent("PLAYER_ALIVE")
sim.Run(3)
assert(Game.obs.corpse == false and Model.Target() == false, "none known yet")
assert(not Camera.follow, "not following")
assert(asked > 0, "asked")

-- The client knows it now, and says nothing.
sim.corpse = { [1429] = CreateVector2D(A.TileToMap(1429, body.col, body.row)) }
local frames = 0
repeat
	sim.Step()
	frames = frames + 1
	assert(frames <= 61, "found within a poll")
until Game.obs.corpse
local c = Game.obs.corpse
assert(c.inst == 0 and math.abs(c.col - body.col) < 1e-9 and math.abs(c.row - body.row) < 1e-9, "where it is")
assert(Model.Target().kind == "corpse" and Model.Target().pos == c, "the target that frame")
sim.Run(1)
assert(Camera.follow, "the view follows you")
T.Print("G4: the corpse in the Observation %d frames after the client knew it", frames)

-- Browsing another continent (no target there) and back: found already this ghost, the pick kept
-- (TargetKey, Layers.lua:1182-1184).
sim.Slash("/mma map 1")
sim.Run(1)
assert(Model.Target() == false, "none on Kalimdor")
sim.Slash("/mma map 0")
sim.Run(1.5)
assert(Model.Target().kind == "corpse" and not Camera.follow, "back on your map: not following")

-- Found: not asked again, the same table each frame.
asked = 0
sim.Run(3)
assert(asked == 0 and Game.obs.corpse == c, "kept")

-- Alive again (back at the body): none, that frame.
sim.ghost, sim.units.player.dead, sim.corpse = false, false, nil
sim.FireEvent("PLAYER_UNGHOST")
sim.Step()
assert(Game.obs.corpse == false and Model.Target() == false, "none again")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

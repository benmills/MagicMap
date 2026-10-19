-- D4: one thing showed as two of our pins: a live rare (its vignette) beside the seen rare's pin. MOVED: the
-- merge is Model's alone (model/Rares.lua: Landmarks.lua:50-56, 96-99, 107, 112-117), tested here as it's
-- handed: a rare you've seen with a live rare vignette of its name is that pin's, not listed while the vignettes
-- layer is on; the vignette gone, or that layer off, the seen one is back. Each step one Mother Fang among
-- Known("rares") and the vignettes drawn, and on the map one pin at most (the rares layer's when it's listed;
-- the vignettes' layer is M4.4's). Questie's turn-in "?" beside ours: M4.2's (test_addonpins).
-- obs.vignettes is M4.1's (game/parts/Vignettes.lua); until it's here, the replay's part hands the sim's
-- vignette over (Mother Fang, at Atlas.MapToTile(1429, 0.38, 0.79)), and its last say wins once it is.
local T = ...
local COL, ROW = 31.594, 50.316
local sim, ns = T.Boot(T.TEST_UI .. "\nMagicMapAtlasDB.Model = { _v = 1, blips = {}, rares = { [0] = { ['npc:471'] = "
	.. "{ name = 'Mother Fang', npcID = 471, col = " .. COL .. ", row = " .. ROW .. ", t = 1792000000 } } } }")
local Model = ns.Model
local function Fang() return { id = "Vignette-0-1", name = "Mother Fang", rare = true, npcID = 471,
	icon = { atlas = "VignetteKill" }, pos = { inst = 0, col = COL, row = ROW } } end
local vignettes = { Fang() }
ns.Game.Part("vignettes", function() return vignettes end)
sim.Run(1)
sim.Slash("/mma toggle")
sim.Run(3)

-- Mother Fang among Known("rares") and Known("vignettes") (those drawn: its layer on); her pins shown on the
-- map (every pin layer's, at its minimum zoom), and the rares layer's.
local function Count(drawn)
	local n = 0
	for _, e in ipairs((Model.Known("rares"))) do n = n + (e.name == "Mother Fang" and 1 or 0) end
	for _, e in ipairs(drawn and Model.Known("vignettes") or {}) do n = n + (e.name == "Mother Fang" and 1 or 0) end
	return n
end
local function Pins()
	local S, n, rares = sim.state, 0, 0
	for _, l in ipairs(ns.UI.Engine.layers) do
		local c = l.zoom == "pin" and l.on and l.front
		local p = c and S[c].alpha > 0 and c.pools.pin
		for i = 1, p and p.n or 0 do
			local o = p[i]
			if S[o].shown and S[o].alpha > 0 and S[S[o].parent].alpha > 0 and o.entry.name == "Mother Fang" then
				n, rares = n + 1, rares + (l.name == "rares" and 1 or 0)
			end
		end
	end
	return n, rares
end

-- Live: the vignette's, the seen one under it (and seen again now).
assert(Count(true) == 1 and Model.Known("vignettes")[1].name == "Mother Fang", "one: the live one")
local n, rares = Pins()
assert(n <= 1 and rares == 0, "no seen-rare pin under the live one")
local live = n
local seen = Model.saved.rares[0]["npc:471"]
assert(seen.t > 1792000000 and seen.col == COL and seen.row == ROW, "seen again where it is")

-- The vignette gone: the seen one is back.
vignettes = {}
sim.Run(0.5)
n, rares = Pins()
assert(Count(true) == 1 and n == 1 and rares == 1, "one: the seen one")

-- Live again, the vignettes layer off (UI's Focus.off: ui/View.lua names the layers Model reads): the seen one.
vignettes = { Fang() }
sim.Run(0.5)
assert(Count(true) == 1 and select(2, Pins()) == 0, "under the live one again")
local f = {}
for k, v in pairs(Model.focus) do f[k] = v end
f.off = { vignettes = true }
Model.Focus(f)
sim.Run(0.5)
n, rares = Pins()
assert(Count(false) == 1 and n == 1 and rares == 1, "the layer off: one, the seen one")
T.Print("D4: one Mother Fang each step: live (%d pins: the vignettes layer is M4.4's), gone and the vignettes layer off (the seen one)", live)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

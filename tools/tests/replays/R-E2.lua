-- E2: vignette and area-POI pins errored on every map change, and login aborted: `local x, y = pos and
-- pos:GetXY()` left y nil, inside handlers nothing isolated. CONTAINED: Game's vignette read is its own
-- wrapped call (game/parts/Vignettes.lua, "game.part vignettes"), x and y read in two statements: a
-- vignette and its pin stand where the client says, one it gives no position isn't there, and a read that
-- throws is reported once while the map draws on; the next read hands them over again.
local T = ...
local sim, ns = T.Shown()
local A, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

-- The client's vignette on Elwynn's map at (0.38, 0.79): a rare's art.
sim.vignetteAtlas = "VignetteKillElite"
sim.FireEvent("VIGNETTES_UPDATED")
sim.Run(0.5)
local v, inst, col, row = Game.obs.vignettes[1], A.MapToTile(1429, 0.38, 0.79)
assert(v and v.rare and v.name == "Mother Fang", "the rare")
assert(type(v.pos.col) == "number" and type(v.pos.row) == "number", "both coordinates")
assert(v.pos.inst == inst and math.abs(v.pos.col - col) < 0.01 and math.abs(v.pos.row - row) < 0.01, "where the client says")
-- On the map, the live rare's pin (ui/Places.lua) stands there.
local S, places, pin = sim.state, T.Layer(ns, "places"), nil
local pool = places.front.pools.pin
for i = 1, pool.n do
	local o = pool[i]
	if S[o].shown and o.entry.kind == "vignettes" then pin = o end
end
assert(pin and math.abs(pin.acol - col) < 0.01 and math.abs(pin.arow - row) < 0.01, "its pin there")

-- No position given: none, no error.
local position = C_VignetteInfo.GetVignettePosition
C_VignetteInfo.GetVignettePosition = function() return nil end
sim.FireEvent("VIGNETTE_MINIMAP_UPDATED")
sim.Run(0.5)
assert(#Game.obs.vignettes == 0, "none")
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n"))

-- The read throws: reported once, the map drawn every frame meanwhile.
C_VignetteInfo.GetVignettePosition = position
local vignettes = C_VignetteInfo.GetVignettes
C_VignetteInfo.GetVignettes = function() error("GetVignettes failed") end
sim.FireEvent("VIGNETTES_UPDATED")
local draw = Runtime.Perf()["map: draw"]
local n0 = draw.n
sim.Run(1)
local named = 0
for _, e in pairs(Runtime.errors) do
	if e.name == "game.part vignettes" then named = named + 1 end
end
assert(named == 1 and T.Errs(ns, "game.part vignettes") == 1, "reported once")
assert(math.abs(draw.n - n0 - 60) <= 1, "drawn 60 a second: " .. (draw.n - n0))
T.Print("E2: a throwing read reported %d time(s); map: draw %d calls in 1 s", T.Errs(ns, "game.part vignettes"), draw.n - n0)

-- And the next read hands them over.
C_VignetteInfo.GetVignettes = vignettes
sim.FireEvent("VIGNETTES_UPDATED")
sim.Run(0.5)
v = Game.obs.vignettes[1]
assert(v and math.abs(v.pos.col - col) < 0.01, "back")

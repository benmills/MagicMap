-- E4: opening the map called a nil global when no addon brought LibStub (0415084 dropped the
-- guard as if LibStub were the client's). CONTAINED: Game alone reads other addons, in one scan
-- (game/AddonPins.lua) that looks for LibStub first, at login, as addons load and as the window
-- opens; Runtime isolates it. No error, nothing borrowed, obs.addons known and empty. (Nothing
-- stops a cleanup dropping that line again; this replay would fail.)
local T = ...
local sim, ns = T.Boot("LibStub = nil; " .. T.TEST_UI)
ns.UI.View().layers["addon:Questie"] = true
sim.Run(1)
for _ = 1, 3 do -- open, close, open (the world socket published while open)
	sim.Slash("/mma toggle")
	sim.Run(1.2)
end
assert(ns.UI.View().sockets.world ~= nil)
sim.FireEvent("ADDON_LOADED", "Questie")
sim.Run(0.2)
assert(LibStub == nil and ns.UI.Window.frame:IsShown())
local addons = ns.Game.obs.addons
assert(type(addons) == "table" and #addons == 0, "known, and empty")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

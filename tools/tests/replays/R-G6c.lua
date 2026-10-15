-- G6, the minimap half while the takeover has the Minimap: HereBeDragons parents every minimap pin
-- to its pins.Minimap, so one added after the engage landed on the unseen sensor (alpha 0, under
-- our map), where it still took the mouse: Questie's at frame level 2016+, over the view (child
-- frames take their parent's strata, the view the window's). PREVENTED: while engaged, every copy
-- drawing on the Minimap, one loaded since too, draws on a hidden host (the spike's hiddenHost,
-- MinimapTakeover.lua:84-93); released, back on the Minimap, last.
local T = ...
local sim, ns = T.Boot("MagicMapAtlasDB = nil") -- the shipped default: shown, small, on the minimap's spot
sim.Run(3)
local Game, Window = ns.Game, ns.UI.Window
assert(Game.minimap.engaged)
assert(Window.view:GetFrameStrata() == Window.frame:GetFrameStrata(), "the view in the window's strata")

local gather = sim.gatherPin -- the shared copy's, there before we engaged
local q = sim.LoadQuestie() -- Questie loads after us, while engaged
sim.FireEvent("ADDON_LOADED", "Questie")
local icon = sim.QuestieIcon({ Type = "available", Id = 70 })
icon:EnableMouse(true)
q:AddMinimapIconMap(Questie, icon, 1429, 0.297, 0.546)
sim.Run(0.5)
local host = icon:GetParent()
T.Print("G6c: Questie's minimap pin on %s (shown %s, visible %s); GatherMate's on the same: %s",
	host == Minimap and "the Minimap" or "a hidden host", tostring(icon:IsShown()), tostring(icon:IsVisible()),
	tostring(gather:GetParent() == host))
assert(host ~= Minimap and not host:IsShown() and not icon:IsVisible(), "out of sight, the mouse not on it")
assert(gather:GetParent() == host and not gather:IsVisible())
assert(host:GetZoom() == Minimap:GetZoom(), "the host answers the library's zoom")

sim.Slash("/mma toggle") -- released: back on the Minimap, placed again
sim.Step()
assert(not Game.minimap.engaged and icon:GetParent() == Minimap and gather:GetParent() == Minimap)
assert(q.Minimap == Minimap and sim.hbdPins.Minimap == Minimap)
assert(icon:IsVisible() and icon:GetNumPoints() == 1)
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n\n"))

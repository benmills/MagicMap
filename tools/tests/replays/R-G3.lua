-- G3: other client code changing the state the takeover set (HybridMinimap turns the
-- Minimap's ground and rotation back on as it hides; Rotate Minimap; anyone zooming,
-- hiding or moving it). CONTAINED: Apply puts each right every frame (the overlay back on its
-- zoom, where it placed it: game/Minimap.lua); and the undo list still puts back what was there
-- before the takeover.
local T = ...
local sim, ns = T.Shown()
local Game = ns.Game
local m = Game.minimap
ns.UI.Motion.SetZoom(m.steps[1]) -- (the overlay seen: its widest zoom covers the window just so)
sim.Run(1)
local x, y = Minimap:GetCenter()
local w = Minimap:GetWidth()
local function Held()
	local cx, cy = Minimap:GetCenter()
	return Minimap:IsShown() and Minimap:GetZoom() == (m.zoom or 0) and not C_Minimap.GetDrawGroundTextures()
		and C_Minimap.IsRotateMinimapIgnored() and math.abs(cx - x) < 1 and math.abs(cy - y) < 1
		and math.abs(Minimap:GetWidth() - w) < 1
end
assert(m.engaged and m.overlaid and Held(), "taken")

-- HybridMinimap hides: ground and rotation on, the Minimap hidden. Right the next frame.
C_Minimap.SetDrawGroundTextures(true)
C_Minimap.SetIgnoreRotateMinimap(false)
Minimap:Hide()
sim.Step()
assert(Held(), "put right")
-- Another addon moves it away and sizes it: back the next frame.
Minimap:ClearAllPoints()
Minimap:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
Minimap:SetSize(50, 50)
sim.Step()
assert(Held() and m.overlaid, "put back")
-- And zooms it: back on its zoom, seen again once its radius has applied.
Minimap:SetZoom((m.zoom or 0) == 0 and 2 or 0)
sim.Step()
assert(Minimap:GetZoom() == (m.zoom or 0), "its zoom")
sim.Run(1)
assert(Held() and m.overlaid, "seen again")
-- Rotate Minimap on: the Minimap stays ours, north up.
sim.cvars.rotateMinimap = "1"
sim.Run(1)
assert(m.engaged and Held(), "north up")
-- Something turning rotation back on every frame for 2 s: put right each frame, held once it stops.
local onStep = sim.onStep
sim.onStep = function(dt) onStep(dt); C_Minimap.SetIgnoreRotateMinimap(false) end
sim.Run(2)
sim.onStep = onStep
sim.Step()
assert(m.engaged and Held(), "held")

-- Released after all that: what was there before the takeover (the sim's: ground on, rotation not ignored).
sim.Slash("/mm minimap blizzard")
sim.Step()
assert(not m.engaged and C_Minimap.GetDrawGroundTextures() and not C_Minimap.IsRotateMinimapIgnored()
	and Minimap:GetParent() == MinimapCluster and Minimap:GetWidth() == 140 and Minimap:GetZoom() == 0, "released")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

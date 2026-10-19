-- G2: arriving by zeppelin, Blizzard's whole minimap (its border, its buttons) showed over ours: the
-- takeover let the Minimap go whenever you were off the map shown (it read the camera, cam.onMap).
-- MOVED: Game acts only on View (types/view.lua), which says nothing of the map shown but its
-- instance; whether it takes the Minimap hangs on the window shown and View.minimap alone. Browsing
-- Kalimdor from Eastern Kingdoms (the picker, /mma map) and coming back (Follow me): the takeover held
-- every frame, the Minimap still the sensor, its cluster hidden (T.Invariants), HereBeDragons' minimap
-- pins on the hidden host.
local T = ...
local sim, ns = T.Boot("MagicMapAtlasDB = nil") -- the shipped default: shown, small, on the minimap's spot
sim.Run(3)
local Game, UI = ns.Game, ns.UI
local m, gather = Game.minimap, sim.gatherPin
local host = gather:GetParent()
assert(m.engaged and m.sensor and host ~= Minimap and not host:IsShown(), "taken")

local frames = 0
local function Held(seconds)
	for _ = 1, math.ceil(seconds * 60) do
		sim.Step()
		frames = frames + 1
		assert(m.engaged and m.sensor and gather:GetParent() == host and not host:IsShown() and not gather:IsVisible(),
			"let go off the map shown")
	end
end

-- The picker: Kalimdor, from Eastern Kingdoms.
sim.FireScript(UI.Title.hit, "OnClick", "LeftButton", false)
local kalimdor
for _, e in ipairs(sim.MenuItems("radio")) do
	if e.text == "Kalimdor" then kalimdor = e end
end
kalimdor.onSelect()
Held(2)
assert(UI.Camera.inst == 1 and UI.View().inst == 1 and sim.player.inst == 0 and not UI.Camera.follow)
-- Grown and browsing, then an instance's map by id.
sim.Press("M")
Held(1)
sim.Slash("/mma map 36")
Held(1)
assert(UI.View().inst == 36)
-- Back: Follow me, from the map's menu.
local view = UI.Window.view
sim.Click(view, "RightButton")
local follow
for _, e in ipairs(sim.MenuItems("button")) do
	if e.text == "Follow me" then follow = e end
end
follow.onSelect()
Held(1)
assert(UI.Camera.inst == 0 and UI.Camera.follow)
T.Print("G2: %d frames browsing Kalimdor and Deadmines from Eastern Kingdoms and back: taken throughout", frames)
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n\n"))

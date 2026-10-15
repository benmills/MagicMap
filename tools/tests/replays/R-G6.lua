-- G6: other addons' pins misbehaved: Questie's renamed HereBeDragons copy was missed and its
-- pins spilled out of the window; pins drifted as HBD re-placed them. MOVED (Game borrows HBD
-- pins on its internals); the world half here (minimap pins, Rotate Minimap: M4.2). Every copy
-- is found through LibStub, the renamed one loaded after us too, and obs.addons names their
-- addons. While the window shows, a world pin of an addon whose layer is on (UI turns on each
-- with world pins) is hosted on the socket UI publishes (View.sockets.world, ui/Sockets.lua) at
-- its spot, and handed back to its parent, points, shown state and level on each way out (the
-- HBD round trip): its layer off, Blizzard's world map opening, the window hiding. One the
-- library takes back meanwhile is left as the library left it.
local T = ...
local sim, ns = T.Shown()
local view = ns.UI.View()
local canvas = view.sockets.world.frame -- tile (col, row) at (col * zoom, -row * zoom)
assert(canvas and view.sockets.world.inst == 0 and view.sockets.world.zoom == ns.UI.Camera.cam.zoom, "the socket's published")

-- Questie loads after us: a pin in Elwynn (on Blizzard's map, which shows Elwynn), one in
-- Durotar, its route line (its own map only), a frame drawn for Blizzard's canvas, a minimap pin.
local q = sim.LoadQuestie()
sim.FireEvent("ADDON_LOADED", "Questie")
local pin, durotar, line, big = sim.QuestieIcon({ Type = "available", Id = 70 }), sim.QuestieIcon(), sim.QuestieIcon(),
	sim.QuestieIcon()
big:SetSize(300, 300)
q:AddWorldMapIconMap(Questie, pin, 1429, 0.5, 0.5, HBD_PINS_WORLDMAP_SHOW_WORLD)
q:AddWorldMapIconMap(Questie, durotar, 1411, 0.5, 0.5, HBD_PINS_WORLDMAP_SHOW_WORLD)
q:AddWorldMapIconMap(Questie, line, 1429, 0.4, 0.4, HBD_PINS_WORLDMAP_SHOW_CURRENT)
q:AddWorldMapIconMap(Questie, big, 1429, 0.6, 0.6, HBD_PINS_WORLDMAP_SHOW_WORLD)
q:AddMinimapIconMap(Questie, sim.QuestieIcon(), 1429, 0.29, 0.56)

local function Where(icon)
	return { icon:GetParent(), icon:IsShown(), icon:GetFrameLevel(), icon:GetNumPoints(), icon:GetPoint(1) }
end
local function Same(a, b)
	for i = 1, math.max(#a, #b) do
		if a[i] ~= b[i] then return false end
	end
	return true
end
local m = sim.maps[1429] -- the sim's Elwynn: its pin's spot, (0.5, 0.5) of it
local col, row = m[5] + (m[7] - m[5]) * 0.5, m[6] + (m[8] - m[6]) * 0.5
local function Hosted()
	local p, rel, rp, x, y = pin:GetPoint(1)
	local z = view.sockets.world.zoom
	return pin:GetParent() == canvas and pin:IsShown() and pin:GetFrameLevel() == canvas:GetFrameLevel() + 1
		and p == "CENTER" and rel == canvas and rp == "TOPLEFT" and math.abs(x - col * z) < 1e-6 and math.abs(y + row * z) < 1e-6
end
local home = Where(pin)
assert(home[1]:GetParent() == WorldMapFrame.canvas and home[2] and home[3] == 2016, "on its pin on Blizzard's map")

sim.Run(0.2)
assert(Hosted(), "borrowed, at its spot")
assert(durotar:GetParent() ~= canvas and line:GetParent() ~= canvas and big:GetParent() ~= canvas,
	"not another continent's, its own map's alone, nor a frame bigger than a pin")
local addons = {}
for _, a in ipairs(ns.Game.obs.addons) do addons[a.key] = (a.world and "w" or "") .. (a.minimap and "m" or "") end
T.Print("G6: obs.addons Questie %s, GatherMate2 %s", tostring(addons.Questie), tostring(addons.GatherMate2))
assert(addons.Questie == "wm" and addons.GatherMate2 == "m")
assert(view.layers["addon:Questie"], "its layer on, as UI found it with world pins")
ns.UI.Motion.SetZoom(128) -- the socket's zoom changes once the camera's holds a frame: re-placed at once
sim.Step()
assert(view.sockets.world.zoom ~= 128 and canvas:GetAlpha() == 0, "the zoom moving: the pins out of sight")
sim.Step()
assert(view.sockets.world.zoom == 128 and Hosted() and canvas:GetAlpha() == 1, "re-placed at the new zoom")

view.layers["addon:Questie"] = nil -- its layer off: back on its pin (by the next pass)
sim.Run(1.1)
assert(Same(Where(pin), home), "layer off: as it was")
view.layers["addon:Questie"] = true
sim.Run(1.1)
assert(Hosted(), "layer on: borrowed again")

-- Blizzard's world map gets it as it opens (the first time, the library re-places every pin; the
-- level it had there is put back within the frame).
WorldMapFrame:Show()
sim.Step()
local function OnBlizzards() return pin:GetParent().icon == pin and pin:IsVisible() and pin:GetFrameLevel() == 2016 end
assert(OnBlizzards(), "Blizzard's map open: on a pin there")
local there = Where(pin)
sim.Run(0.2)
assert(Same(Where(pin), there))
WorldMapFrame:Hide()
sim.Run(0.2)
assert(Hosted(), "closed: ours again")
WorldMapFrame:Show() -- again (the library leaves its pins be): back where it was taken from, that frame
sim.Step()
assert(OnBlizzards() and Same(Where(pin), there), "open again: as it was")
WorldMapFrame:Hide()
sim.Run(0.2)
assert(Hosted())

q:RemoveWorldMapIcon(Questie, pin) -- the library takes it back while we host it
sim.Run(0.2)
assert(pin:GetParent() == UIParent and not pin:IsShown(), "removed: hidden in UIParent, as the library left it")
q:AddWorldMapIconMap(Questie, pin, 1429, 0.5, 0.5, HBD_PINS_WORLDMAP_SHOW_WORLD)
home = Where(pin)
sim.Run(0.2)
assert(Hosted(), "added again: borrowed again")

ns.UI.Window.frame:Hide() -- the window hides: everything back
sim.Step()
assert(Same(Where(pin), home), "window hidden: as it was")

-- A newer minor of the shared copy loads over it (its methods redefined on the same table: our
-- hooks gone, AddonPins.lua:55-56): hooked again, so an addon's first pin on it is heard.
local shared = sim.hbdPins
function shared:AddWorldMapIconWorld(ref, icon, instanceID, x, y, showFlag) -- the newer minor's own
	self.worldmapPinRegistry[ref] = self.worldmapPinRegistry[ref] or {}
	self.worldmapPinRegistry[ref][icon] = true
	self.worldmapPins[icon] = { instanceID = instanceID, x = x, y = y, worldMapShowFlag = showFlag or 0 }
end
sim.FireEvent("ADDON_LOADED", "NewerHBD")
local note = CreateFrame("Frame", nil, UIParent)
note:SetSize(12, 12)
shared:AddWorldMapIconWorld("HandyNotes", note, 0, -8900, -150, HBD_PINS_WORLDMAP_SHOW_WORLD)
sim.Step()
local keys = {}
for _, a in ipairs(ns.Game.obs.addons) do keys[a.key] = a.world end
assert(keys.HandyNotes == true, "a pin on the upgraded copy: its addon listed")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

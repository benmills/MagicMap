-- G6 at Questie's scale: thousands of world pins borrowed and given back without a long call.
-- Borrowing (Claim) and giving back (Restore) are a Runtime.Job, 1 ms a frame; Blizzard's world
-- map opening (M opens it for a moment) starts a give-back instead of doing it in its hook; the
-- socket's zoom changes only where the view rests (UI scales it meanwhile), so pins are re-placed
-- once a zoom; a minimap pin added or removed only re-lists the addons. On a counted clock (each
-- widget call 0.5 us, Lua free: the client's cost is its engine calls), every call of ours that
-- touches the pins stays within 2 ms through opening, closing, the world map, M, a layer toggle,
-- a wheel zoom and minimap churn, and each time every pin on the map shown ends up hosted or home.
local T = ...
local sim, ns = T.Shown()
local view = ns.UI.View()
local q = sim.LoadQuestie()
sim.FireEvent("ADDON_LOADED", "Questie")
local N, maps = 3000, { 1429, 1411, 1426, 1436, 1453 }
for i = 1, N do
	local icon = sim.QuestieIcon({ Type = "available", Id = i })
	q:AddWorldMapIconMap(Questie, icon, maps[i % #maps + 1], (i % 97) / 97, (i % 89) / 89, HBD_PINS_WORLDMAP_SHOW_WORLD)
end
local here = 0 -- pins on the map shown (instance 0: every map but Durotar's)
for icon, data in pairs(q.worldmapPins) do
	if data.instanceID == 0 then here = here + 1 end
end
sim.CountCalls()
sim.Clock = function() return sim.callTotal * 0.0005 end
local canvas = view.sockets.world.frame
local P = ns.Runtime.Perf()
local function Hosted() return select("#", canvas:GetChildren()) end
local worst = { 0, "-" }
local function Check(what, want)
	for name, p in pairs(P) do
		if name:find("addon pins", 1, true) then
			if p.max > worst[1] then worst[1], worst[2] = p.max, name .. " (" .. what .. ")" end
			assert(p.max <= 2, string.format("%s: %s took %.2f ms", what, name, p.max))
			p.max = 0
		end
	end
	assert(Hosted() == want, string.format("%s: %d hosted, %d wanted", what, Hosted(), want))
end

sim.Run(3)
Check("borrowed", here)
ns.UI.Window.frame:Hide()
sim.Run(1)
Check("window hidden", 0)
ns.UI.Window.frame:Show()
sim.Run(1.5)
Check("reopened", here)
WorldMapFrame:Show()
sim.Run(0.5)
Check("Blizzard's world map open", 0)
WorldMapFrame:Hide()
sim.Run(1.5)
Check("closed", here)
sim.Press("M") -- grows: Blizzard's map opened and hidden again at once
sim.Run(1)
Check("M", here)
sim.Press("M")
sim.Run(1)
Check("M again", here)
view.layers["addon:Questie"] = nil
sim.Run(1.5)
Check("layer off", 0)
view.layers["addon:Questie"] = true
sim.Run(1.5)
Check("layer on", here)
for _ = 1, 3 do sim.Wheel(ns.UI.Window.view, 1) end
sim.Run(1)
Check("wheel", here)
local apply, mini = P["game.addon pins"], sim.QuestieIcon()
local ms, n = apply.ms, P["game.addon pins: borrow"] and P["game.addon pins: borrow"].n or 0
for f = 1, 300 do -- a minimap pin re-added every 0.1 s (an addon refreshing what's in range): no extra pass
	if f % 6 == 0 then
		q:RemoveMinimapIcon(Questie, mini)
		q:AddMinimapIconMap(Questie, mini, 1429, 0.29, 0.56)
	end
	sim.Step()
end
local passes = P["game.addon pins: borrow"].n - n
Check("minimap churn", here)
T.Print("G6b: %d pins (%d here); slowest call %.2f ms, %s; minimap churn: %.2f ms/s, %d borrow resumes in 5 s",
	N, here, worst[1], worst[2], (apply.ms - ms) / 5, passes)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

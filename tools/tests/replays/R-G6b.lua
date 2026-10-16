-- G6 at Questie's scale: thousands of world pins borrowed and given back without a long call.
-- Borrowing (Claim) and giving back (Restore) are a Runtime.Job, 1 ms a frame with news, 0.25 the
-- regular pass each second; Blizzard's world map opening (M opens it for a moment) starts a
-- give-back instead of doing it in its hook; the socket's zoom changes only where the view rests
-- (the canvas see-through meanwhile, never scaled), so pins are re-placed once a zoom; a minimap
-- pin added or removed only re-lists the addons. On a counted clock (each widget call 0.5 us, Lua
-- free: the client's cost is its engine calls), every call of ours that touches the pins stays
-- within 2 ms through opening, closing, the world map, M, a layer toggle, a wheel zoom, sizing the
-- window and minimap churn, and each time every pin on the map shown ends up hosted or home; standing, the frame
-- p95 stays under 1 ms with the regular passes running (the real clock's, Lua too, is printed). The wheel and
-- the window hiding also run on the priced clock (what the client charges per region: each icon has its art):
-- the wheel's frames never scale the pins' canvas; the hide's cost, per region under the window, is printed.
local T = ...
local sim, ns = T.Shown()
sim.Counted(0.0005)
local view = ns.UI.View()
local q = sim.LoadQuestie()
sim.FireEvent("ADDON_LOADED", "Questie")
local N, maps = 3000, { 1429, 1411, 1426, 1436, 1453 }
for i = 1, N do
	local icon = sim.QuestieIcon({ Type = "available", Id = i })
	icon:CreateTexture(nil, "ARTWORK"):SetAllPoints() -- its art (Questie's has more: a lower bound)
	q:AddWorldMapIconMap(Questie, icon, maps[i % #maps + 1], (i % 97) / 97, (i % 89) / 89, HBD_PINS_WORLDMAP_SHOW_WORLD)
end
local here = 0 -- pins on the map shown (instance 0: every map but Durotar's)
for icon, data in pairs(q.worldmapPins) do
	if data.instanceID == 0 then here = here + 1 end
end
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
-- Standing, nothing changing, the regular passes included: our frame's p95.
local read = T.Ours(sim)
local function P95()
	local costs = {}
	for i = 1, 300 do
		sim.Step()
		costs[i] = select(5, read())
	end
	table.sort(costs)
	return costs[285]
end
local p95 = P95()
assert(p95 <= 1, string.format("standing: frame p95 %.2f ms", p95))
local priced = sim.priced
sim.Price(true)
ns.UI.Window.frame:Hide()
local hide = sim.priced - priced
sim.Price(false)
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
local scaled, setScale = 0, canvas.SetScale
canvas.SetScale = function(...) scaled = scaled + 1; return setScale(...) end
sim.Price(true)
for _ = 1, 3 do sim.Wheel(ns.UI.Window.view, 1) end
sim.Run(1)
sim.Price(false)
assert(scaled == 0, "the pins' canvas scaled")
Check("wheel", here)
-- The window sized a little each frame (its grip; the zoom keeps the yards across it): the socket's
-- zoom holds until the size does, then the pins are re-placed once.
local f, z = ns.UI.Window.frame, view.sockets.world.zoom
local w0, h0 = f:GetWidth(), f:GetHeight()
for i = 1, 30 do
	f:SetSize(w0 + i * 2, h0 + i * 2)
	sim.Step()
	assert(view.sockets.world.zoom == z, "sizing: the socket's zoom held")
end
sim.Run(0.5)
assert(view.sockets.world.zoom ~= z)
Check("sized", here)
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
-- Standing again, on the real clock (Lua too; printed only: a shared CI runner's pauses land in it).
sim.Clock = sim.RealClock
T.Print("G6b: standing, frame p95 %.2f ms counted, %.2f ms real; the window hiding with them hosted: %.1f ms priced",
	p95, P95(), hide)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

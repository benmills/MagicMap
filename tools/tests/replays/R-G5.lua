-- G5: wrong or missing data from runtime sources. PREVENTED: with no QuestieDB loaded, Atlas has
-- the NPC services, item icons and quest objectives offline.
-- Without the QuestieDB-derived data (a build missing them; parity F56) Atlas's indexes are
-- empty and the map runs on (test_spike_bugs.py runs every replay so): one chat line says so
-- (QuestInfo.lua:71-75), quests, offers, blips and a seen rare are drawn, quest 60's tooltip has no
-- droppers or turn-in (with the data: both), and nothing errs.
local T = ...
local NOTICE = "|cffffd100MagicMap|r: QuestieDB isn't loaded: quests show without their mobs and items."
local sim, ns = T.Boot(T.TEST_UI .. "\nMagicMap2DB.Model = { _v = 1, blips = {}, rares = { [0] = { ['npc:471'] = "
	.. "{ name = 'Mother Fang', npcID = 471, col = 31.594, row = 50.316, t = 1792000000 } } } }")
local A, S = ns.Atlas, sim.state
assert(QuestieDB == nil and QuestieLoader == nil)
local data = A.Data.Quests ~= nil
if data then
	local innkeeper = false
	for _, s in pairs(A.Npc(295).services) do innkeeper = innkeeper or s == "innkeeper" end
	assert(innkeeper) -- Innkeeper Farley, Goldshire
	assert(A.Item(750).icon ~= nil) -- Tough Wolf Meat (quest 33's objective)
	local o = A.Quest(33).objectives[1]
	assert(o.kind == "item" and o.id == 750)
else
	assert(A.Npc(295) == nil and A.Item(750) == nil and A.Quest(33) == nil)
end

-- A mailbox 40 yd east and 20 north; no live vignette (the seen rare is drawn: R-D4).
local yd = 1 / A.TILE_YARDS
local north, west = A.TileToWorld(sim.player.col + 40 * yd, sim.player.row - 20 * yd)
sim.minimapBlips = { { "Mailbox", north, west } }
sim.noVignettes = true
sim.Run(1)
sim.Slash("/mm toggle")
sim.FireEvent("MINIMAP_UPDATE_TRACKING")
sim.Run(3)

local function Pins(name)
	local l, n = T.Layer(ns, name), 0
	local c = l.on and l.front
	local p = c and S[c].alpha > 0 and c.pools.pin
	for i = 1, p and p.n or 0 do n = n + (S[p[i]].shown and 1 or 0) end
	return n
end
local drawn = {}
for _, name in ipairs({ "quests", "offers", "blips", "rares" }) do
	drawn[#drawn + 1] = name .. " " .. Pins(name)
	assert(Pins(name) > 0, name .. ": none drawn")
end

-- Quest 60's tooltip (the sim's log: Kobold Candles, Large Candle 3/8), the cursor on its pin.
local p = T.Layer(ns, "quests").front.pools.pin
local l, b, w, h = sim.Rect(p[p.at["quest:60"]])
sim.cursorX, sim.cursorY = l + w / 2, b + h / 2
sim.FireScript(ns.UI.Window.view, "OnEnter", false)
sim.Step()
local lines, has = {}, {}
for i = 1, GameTooltip:NumLines() do
	local text = S[GameTooltip:GetLeftLine(i)].text
	lines[i] = text
	for _, k in ipairs({ "Dropped by", "Turn in to" }) do has[k] = has[k] or text:find(k, 1, true) ~= nil end
end
assert(S[GameTooltip].shown and lines[1] == "Kobold Candles" and lines[3] == "Large Candle: 3/8", table.concat(lines, " | "))
assert(has["Dropped by"] == data and has["Turn in to"] == data, table.concat(lines, " | "))

local notices = 0
for _, line in ipairs(sim.prints) do notices = notices + (line == NOTICE and 1 or 0) end
assert(notices == (data and 0 or 1), notices .. " notices")
T.Print("G5 %s: %s; quest 60's tooltip %d lines; %d notice", data and "with the data" or "without it",
	table.concat(drawn, ", "), #lines, notices)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

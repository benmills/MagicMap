-- S1: remembered blips vanished at every login (Landmarks' migration wiped every kind but "rare" from the
-- store Blips also wrote), and grew without bound. MOVED: Model owns both, each a table of its own in its part
-- (saved.rares, saved.blips: types/saved.lua), so no migration of one touches the other, and seen blips are
-- capped (D6: 5000 an instance, the oldest dropped; ADR 0004's amendment).
--   A Model part from before versions (no _v) with 2 rares, 5 seen blips and the spike's vendor kind beside them:
--   the 7 load and show, the vendor nowhere (no kind reads it); a /reload keeps the 7 (a rare survives it).
--   Past 5000 on an instance, the oldest goes first.
--   A sweep that sees a remembered spot empty forgets it.
local T = ...
local YD = 3 / 1600
local function Blip(name, icon, col, row, t)
	return string.format("[%q] = { name = %q, icon = %d, col = %.3f, row = %.3f, t = %d }",
		name .. ":" .. math.floor(col * 64 + 0.5) .. ":" .. math.floor(row * 64 + 0.5), name, icon, col, row, t)
end
local blips = {} -- far from you (Goldshire): no sweep of yours reaches them
for i, b in ipairs({ { "Mailbox", 136459, 31.30, 48.95 }, { "Mailbox", 136459, 31.40, 49.00 }, { "Mailbox", 136459, 34.30, 51.70 },
	{ "Innkeeper Allison", 136458, 31.35, 48.90 }, { "Innkeeper Trelayne", 136458, 34.37, 51.75 } }) do
	blips[i] = Blip(b[1], b[2], b[3], b[4], 1792000000 + i)
end
local old = {}
for i = 1, 5000 do old[i] = Blip("Mailbox", 136459, 30 + i % 100 * 0.05, 30 + math.floor(i / 100) * 0.05, 1000 + i) end
local sim, ns = T.Shown(T.TEST_UI .. "\nMagicMapAtlasDB.Model = { rares = { [0] = {"
	.. " ['npc:471'] = { name = 'Mother Fang', npcID = 471, col = 31.594, row = 50.316, t = 1792000000 },"
	.. " ['at:2195:3315'] = { name = 'Mor\\'Ladim', col = 34.3, row = 51.8, t = 1792000001 } } },"
	.. " blips = { [0] = { " .. table.concat(blips, ", ") .. " }, [1] = { " .. table.concat(old, ", ") .. " } },"
	.. " vendors = { [0] = { ['vendor:-9465:63'] = { kind = 'vendor', name = 'Brog Hamfist', n = -9465.1, w = 63.2, t = 1 } } } }")
local Model = ns.Model

-- What Model shows of you: every kind's names.
local KINDS = { "rares", "remembered", "blips", "services", "places", "vignettes", "group" }
local function Names()
	local out = {}
	for _, kind in ipairs(KINDS) do
		for _, e in ipairs((Model.Known(kind))) do out[#out + 1] = e.name end
	end
	table.sort(out)
	return table.concat(out, ", ")
end
local SEVEN = "Innkeeper Allison, Innkeeper Trelayne, Mailbox, Mailbox, Mailbox, Mor'Ladim, Mother Fang"
local function Shown()
	local names = {}
	for _, e in ipairs((Model.Known("rares"))) do names[#names + 1] = e.name end
	for _, e in ipairs((Model.Known("remembered"))) do names[#names + 1] = e.name end
	table.sort(names)
	return table.concat(names, ", ")
end
assert(Shown() == SEVEN, Shown())
assert(not Names():find("Brog Hamfist", 1, true), "the vendor shown")

-- A /reload: the part as the client writes it, read at the next login.
local function Dump(v)
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) ~= "table" then return tostring(v) end
	local out = {}
	for k, x in pairs(v) do out[#out + 1] = "[" .. Dump(k) .. "] = " .. Dump(x) end
	return "{ " .. table.concat(out, ", ") .. " }"
end
sim, ns = T.Boot("MagicMapAtlasDB = " .. Dump(MagicMapAtlasDB)) -- (shown at login: it was)
sim.Run(4)
Model = ns.Model
assert(Model.saved._v == 1 and Shown() == SEVEN, Shown())

-- Past the cap on Kalimdor: one more, the oldest gone.
local function Count(inst)
	local n = 0
	for _ in pairs(Model.saved.blips[inst]) do n = n + 1 end
	return n
end
assert(Count(1) == 5000)
local you = ns.Game.obs.you
Model.Observe({ frame = 0, t = GetTime(), epoch = time(), hooked = {}, you = you,
	blips = { list = { { name = "Mailbox", rough = false, icon = 136459, pos = { inst = 1, col = 40, row = 40 } } }, sweep = -1, reach = 0 } },
	ns.Game.oracles)
local oldest = Model.saved.blips[1]["Mailbox:" .. math.floor(30.05 * 64 + 0.5) .. ":1920"] -- (i = 1)
assert(Count(1) == 5000 and Model.saved.blips[1]["Mailbox:2560:2560"] and not oldest, "the oldest goes")

-- Seen by you, then a sweep sees its spot empty: forgotten.
local A, p = ns.Atlas, sim.player
local north, west = A.TileToWorld(p.col + 40 * YD, p.row - 20 * YD)
sim.minimapBlips = { { "Mailbox", north, west } }
sim.FireEvent("MINIMAP_UPDATE_TRACKING")
sim.Run(3)
assert(Count(0) == 6, "seen: remembered")
sim.minimapBlips = {}
sim.Run(3)
assert(Count(0) == 5, "a sweep saw it gone: forgotten")
T.Print("S1: 2 rares and 5 blips through a load from no _v and a /reload, the vendor nowhere; 5000 on Kalimdor, the oldest gone")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

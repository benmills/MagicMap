-- S1: remembered blips vanished at every login (Landmarks' migration wiped every kind but "rare" from the
-- store Blips also wrote), and grew without bound. MOVED: Model owns its saved part, each kind a table of its own
-- (saved.rares: types/saved.lua), so no migration of one touches another. Blips are no longer kept (Blizzard's
-- overlay draws them: game/Minimap.lua), and an older part's store of them (saved.blips, till 2.2.1) is dropped.
--   A Model part from before versions (no _v) with 2 rares, 5 seen blips and the spike's vendor kind beside them:
--   the 2 rares load and show, the blips are dropped, the vendor nowhere (no kind reads it); a /reload keeps the 2.
local T = ...
local function Blip(name, icon, col, row, t)
	return string.format("[%q] = { name = %q, icon = %d, col = %.3f, row = %.3f, t = %d }",
		name .. ":" .. math.floor(col * 64 + 0.5) .. ":" .. math.floor(row * 64 + 0.5), name, icon, col, row, t)
end
local blips = {}
for i, b in ipairs({ { "Mailbox", 136459, 31.30, 48.95 }, { "Mailbox", 136459, 31.40, 49.00 }, { "Mailbox", 136459, 34.30, 51.70 },
	{ "Innkeeper Allison", 136458, 31.35, 48.90 }, { "Innkeeper Trelayne", 136458, 34.37, 51.75 } }) do
	blips[i] = Blip(b[1], b[2], b[3], b[4], 1792000000 + i)
end
local sim, ns = T.Shown(T.TEST_UI .. "\nMagicMap2DB.Model = { rares = { [0] = {"
	.. " ['npc:471'] = { name = 'Mother Fang', npcID = 471, col = 31.594, row = 50.316, t = 1792000000 },"
	.. " ['at:2195:3315'] = { name = 'Mor\\'Ladim', col = 34.3, row = 51.8, t = 1792000001 } } },"
	.. " blips = { [0] = { " .. table.concat(blips, ", ") .. " } },"
	.. " vendors = { [0] = { ['vendor:-9465:63'] = { kind = 'vendor', name = 'Brog Hamfist', n = -9465.1, w = 63.2, t = 1 } } } }")
local Model = ns.Model

-- What Model shows of you: every kind's names.
local KINDS = { "rares", "places", "vignettes", "group" }
local function Names()
	local out = {}
	for _, kind in ipairs(KINDS) do
		for _, e in ipairs((Model.Known(kind))) do out[#out + 1] = e.name end
	end
	table.sort(out)
	return table.concat(out, ", ")
end
local TWO = "Mor'Ladim, Mother Fang"
local function Shown()
	local names = {}
	for _, e in ipairs((Model.Known("rares"))) do names[#names + 1] = e.name end
	table.sort(names)
	return table.concat(names, ", ")
end
assert(Shown() == TWO, Shown())
assert(Model.saved.blips == nil, "the blips' store kept")
assert(not Names():find("Brog Hamfist", 1, true) and not Names():find("Innkeeper", 1, true), "a vendor or a blip shown")

-- A /reload: the part as the client writes it, read at the next login.
local function Dump(v)
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) ~= "table" then return tostring(v) end
	local out = {}
	for k, x in pairs(v) do out[#out + 1] = "[" .. Dump(k) .. "] = " .. Dump(x) end
	return "{ " .. table.concat(out, ", ") .. " }"
end
sim, ns = T.Boot("MagicMap2DB = " .. Dump(MagicMap2DB)) -- (shown at login: it was)
sim.Run(4)
Model = ns.Model
assert(Model.saved._v == 1 and Shown() == TWO and Model.saved.blips == nil, Shown())
T.Print("S1: 2 rares through a load from no _v and a /reload, the blips dropped, the vendor nowhere")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))

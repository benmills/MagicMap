-- Town services, Known("services"): every NPC Atlas knows with a service (its flags, the spike's in its
-- order: Blips.lua:377-406), friendly to you, at each of its spawns, on Focus's instance where the map
-- has shown at town scale (zoom 60 and in: Blips.lua:479) while they're asked for: each tile of Focus's
-- rect gathered once, in a Runtime job, a tile a slice (Atlas.SpawnsIn's first use on an instance
-- passes over every NPC). Listed while Blizzard's tracking has its icon on (obs.tracking; Trainer is the
-- switch for class trainers too: Blips.lua:561-570); tracking not known yet: all. Its line: the NPC's title.
-- For model/Blips.lua: Model.Tracked(icon), whether tracking shows that icon; Model.ServiceNear(inst,
-- name, col, row), a service of that name gathered within NEAR (Blips.lua:572-579); Model.servicesRev,
-- up by one when either may have changed.

local _, ns = ...
local Model, Atlas = ns.Model, ns.Atlas

local ZOOM = 60 -- px a tile (Blips.lua:479 REMOTE_MIN_ZOOM)
local NEAR = 30 / Atlas.TILE_YARDS -- tiles (Blips.lua:487 NEAR_SAME)
local TRAINER, CLASS_TRAINER = 136463, 136455 -- Blips.lua:389
local SERVICES = { -- npcFlags bit, its tracking icon, Data/BlipServices' name for it (Blips.lua:377-385)
	{ 128, 136458, "innkeeper" }, { 256, 136453, "banker" }, { 4096, 136452, "auctioneer" },
	{ 8192, 136466, "stablemaster" }, { 2048, 136454, "battlemaster" }, { 16, TRAINER, "trainer" },
	{ 16384, 136465, "repair" },
}
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" } -- Blips.lua:390
local NONE = {}

local on -- the icons tracking shows (nil: not known yet)
local tracking -- obs.tracking, the last handed
local gathered = {} -- [inst] = { tiles = { [tile] = true }, list = { entries }, names = { [name] = { entries } } }
local list, rev, listInst = NONE, 0, nil
local job, looked -- the gathering under way; the rect last looked at
local textures = {}
Model.servicesRev = 0

-- The service in flags (an NPC's) and its icon; nil: none (Blips.lua:392-406).
local function Service(flags, sub)
	for _, s in ipairs(SERVICES) do
		if flags % (s[1] * 2) >= s[1] then -- bit s[1] set
			if s[2] == TRAINER and sub then
				for _, c in ipairs(CLASSES) do
					if sub:find(c, 1, true) then return "classtrainer", CLASS_TRAINER end
				end
			end
			return s[3], s[2]
		end
	end
end

local function Serves(id) return Service(Atlas.Npc(id).flags) ~= nil end

local function Texture(t)
	if not textures[t] then textures[t] = { texture = t } end
	return textures[t]
end

function Model.Tracked(icon) return on == nil or on[icon] == true end

function Model.ServiceNear(inst, name, col, row)
	local g = gathered[inst]
	for _, e in ipairs(g and g.names[name] or NONE) do
		local p = e.pos
		if (p.col - col) ^ 2 + (p.row - row) ^ 2 < NEAR * NEAR then return true end
	end
	return false
end

-- The tiles' services, a tile a slice.
local function Gather(inst, tiles, faction)
	local g = gathered[inst]
	for _, tile in ipairs(tiles) do
		local c, r = math.floor(tile / 64), tile % 64
		for _, s in ipairs(Atlas.SpawnsIn("npc", inst, c, r, c + 1, r + 1, Serves, ns.Runtime.Yield)) do
			local n = Atlas.Npc(s.id)
			if math.floor(s.col) == c and math.floor(s.row) == r and n.faction and n.faction:find(faction, 1, true) then
				local service, icon = Service(n.flags, n.subName)
				local e = { key = "npc:" .. s.id .. ":" .. math.floor(s.col * 64 + 0.5) .. ":" .. math.floor(s.row * 64 + 0.5),
					kind = "services", name = n.name, live = false, pos = { inst = inst, col = s.col, row = s.row },
					icon = Texture(icon), text = n.subName, service = service, npc = s.id }
				g.list[#g.list + 1] = e
				local same = g.names[n.name]
				if not same then same = {}; g.names[n.name] = same end
				same[#same + 1] = e
			end
		end
		ns.Runtime.Yield()
	end
	Model.servicesRev = Model.servicesRev + 1
end

-- Focus's rect at town scale (a new table when it moves: Motion.Rect): the tiles not yet gathered there,
-- gathered, one job at a time.
local function Start(f)
	local rect = f.rect
	if rect == looked or not (f.shown and rect and f.zoom and f.zoom >= ZOOM) or job and not job.done then return end
	looked = rect
	local inst = f.inst
	local g = gathered[inst]
	if not g then g = { tiles = {}, list = {}, names = {} }; gathered[inst] = g end
	local tiles
	for c = math.max(0, math.floor(rect.c0)), math.min(63, math.floor(rect.c1)) do
		for r = math.max(0, math.floor(rect.r0)), math.min(63, math.floor(rect.r1)) do
			local tile = c * 64 + r
			if not g.tiles[tile] then
				g.tiles[tile] = true
				tiles = tiles or {}
				tiles[#tiles + 1] = tile
			end
		end
	end
	if not tiles then return end
	local faction = Model.you.faction or "A"
	job = ns.Runtime.Job("model: services", function() Gather(inst, tiles, faction) end, 1) -- (1 ms: docs/structure.md "Atlas first use")
end

Model.Part(function(obs)
	local t = obs.tracking
	if t == nil or t == tracking then return end
	tracking, on, Model.servicesRev = t, {}, Model.servicesRev + 1
	for _, x in ipairs(t) do
		if x.active then on[x.texture] = true end
	end
	if on[TRAINER] then on[CLASS_TRAINER] = true end -- (one switch for both kinds of trainer)
end)

-- Focus's instance (else yours): its services gathered so far that tracking shows.
local listRev = -1
Model.Kind("services", function()
	local f = Model.focus
	if f then Start(f) end
	local inst = f and f.inst or Model.you.inst
	if inst == listInst and Model.servicesRev == listRev then return list, rev end
	listInst, listRev, rev, list = inst, Model.servicesRev, rev + 1, {}
	for _, e in ipairs(gathered[inst] and gathered[inst].list or NONE) do
		if Model.Tracked(e.icon.texture) then list[#list + 1] = e end
	end
	return list, rev
end)

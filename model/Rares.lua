-- The rares you've seen (saved.rares, types/saved.lua: account-wide), as Known("rares"), and what the
-- game shows near you now (obs.vignettes) as Known("vignettes") (Landmarks.lua:13-117).
--   remember  a rare among obs.vignettes (its art a rare's or an elite's; or the one you target, at your
--             position: Game's `target`, not a vignette) is kept where it was last seen, one entry an NPC
--             (else its spot), seen then (Landmarks.lua:24-44, 96-103, 154-156)
--   hide      a seen rare with a live rare vignette of its name stands under that pin: not listed while
--             the vignettes layer is on (Focus.off; D4: Landmarks.lua:50-56, 96-99, 107, 112-117)
-- Known("rares"): Focus's instance (else yours), live false, t last seen, its line "Rare" (the tooltip's
-- "Seen here <Mon DD>" is UI's to write from t: Model has no date). Known("vignettes"): obs.vignettes but
-- the target, key the vignette GUID, live; "Nearby now" (Landmarks.lua:93).

local _, ns = ...
local Model = ns.Model

local NONE = {}

local store = {} -- saved.rares: [inst][key] = { name, npcID, col, row, t }
local vignettes -- obs.vignettes, the last handed
local shown, shownRev = NONE, 0 -- Known("vignettes")
local live = {} -- the names of rare vignettes shown now
local list, rev, listInst, hiding, dirty = NONE, 0, nil, nil, true -- Known("rares")
local entries = setmetatable({}, { __mode = "k" }) -- a saved one -> its Known entry

local function R3(v) return math.floor(v * 1000 + 0.5) / 1000 end

local function Remember(v, now)
	local p = v.pos
	local key = v.npcID and "npc:" .. v.npcID or "at:" .. math.floor(p.col * 64 + 0.5) .. ":" .. math.floor(p.row * 64 + 0.5)
	if not store[p.inst] then store[p.inst] = {} end
	store[p.inst][key] = { name = v.name, npcID = v.npcID, col = R3(p.col), row = R3(p.row), t = now or 0 }
	dirty = true
end

Model.Part(function(obs)
	local v = obs.vignettes
	if v == nil or v == vignettes then return end
	vignettes, shownRev, shown, live, dirty = v, shownRev + 1, {}, {}, true
	for _, x in ipairs(v) do
		if x.rare then Remember(x, obs.epoch) end
		if not x.target then
			if x.rare then live[x.name] = true end
			shown[#shown + 1] = { key = x.id, kind = "vignettes", name = x.name, pos = x.pos, icon = x.icon, live = true,
				rare = x.rare, npc = x.npcID, text = "Nearby now" }
		end
	end
end, function(saved)
	store, dirty = saved.rares, true
end)

Model.Kind("vignettes", function() return shown, shownRev end)

-- Focus's instance (else yours), but those a live vignette stands for while that layer is on.
Model.Kind("rares", function()
	local f = Model.focus
	local inst, hide = f and f.inst or Model.you.inst, not (f and f.off and f.off.vignettes)
	if inst ~= listInst or hide ~= hiding then listInst, hiding, dirty = inst, hide, true end
	if not dirty then return list, rev end
	dirty, rev, list = false, rev + 1, {}
	for key, s in pairs(store[inst] or NONE) do
		if not (hide and live[s.name]) then
			local e = entries[s]
			if not e then
				e = { key = key, kind = "rares", name = s.name, live = false, pos = { inst = inst, col = s.col, row = s.row },
					t = s.t, text = "Rare" }
				entries[s] = e
			end
			list[#list + 1] = e
		end
	end
	return list, rev
end)

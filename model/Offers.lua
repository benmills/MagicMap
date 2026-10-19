-- Quests to pick up (obs.offers: the maps Game asked about) as Known("offers"): one a quest,
-- none in your log (obs.quests: in progress), as the world map's QuestOfferDataProvider
-- (Layers.lua:640-663). An offer the same as before keeps its entry; a log with the same quests (a count
-- ticking) changes nothing.

local _, ns = ...
local Model = ns.Model

local NONE = {}
local ICON = { atlas = "QuestNormal", color = { 1, 0.82, 0 } } -- Layers.lua:658
local TEXT = "Quest to pick up" -- Layers.lua:652

local offers, log -- the obs parts the list is from
local mine, n = {}, 0 -- [quest] = true for those in the log, and how many
local entries = {} -- [quest] = its entry, while offered
local list, rev = NONE, 0

-- Whether log q holds the quests mine does.
local function Same(q)
	if #q ~= n then return false end
	for _, x in ipairs(q) do
		if not mine[x.id] then return false end
	end
	return true
end

Model.Part(function(obs)
	local o, q = obs.offers or offers, obs.quests or log
	if o == offers and q == log then return end
	local again = o == offers and Same(q or NONE)
	offers, log = o, q
	if again then return end
	local was, out = entries, {}
	mine, n = {}, #(q or NONE)
	for _, x in ipairs(q or NONE) do mine[x.id] = true end
	entries = {}
	for _, x in ipairs(o or NONE) do
		local id, p = x.questID, x.pos
		if not entries[id] and not mine[id] then
			local e = was[id]
			if not (e and e.name == x.name and e.line == x.line and e.pos.inst == p.inst and e.pos.col == p.col
				and e.pos.row == p.row) then
				e = { key = "quest:" .. id, kind = "offers", pos = p, name = x.name, live = true, quest = id, line = x.line,
					icon = ICON, text = TEXT }
			end
			entries[id] = e
			out[#out + 1] = e
		end
	end
	local same = #out == #list
	for i = 1, same and #out or 0 do
		if out[i] ~= list[i] then
			same = false
			break
		end
	end
	if not same then list, rev = out, rev + 1 end
end)

Model.Kind("offers", function() return list, rev end)

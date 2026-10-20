-- Your quests on the map (Layers.lua:579-621): Known("quests") as pins on the pin store (ui/Pins.lua),
-- in the world map's art (S46), Blizzard's atlases (Pins' (c), (b)): in progress, the yellow progress
-- atlas over the quest-number disc ("UI-QuestPoi-QuestNumber") tinted its difficulty (Model's colour),
-- the first unfinished objective's icon inside, its count under it; ready to turn in, the "questturnin"
-- "?" the atlas Model names; 22 px, the one you follow 26 in a thin gold ring (Pins' glow).
-- Hovering one lights its area (ui/Areas.lua) and shows its tooltip (ui/QuestTooltip.lua); a click
-- follows it, again to stop. And quests to pick up (Layers.lua:636-664): Known("offers"), "questnormal"
-- (the "!") at 18, their tooltip the quest, its line's name and "Quest to pick up". Over the other pins.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Pins, Areas = UI.Pins, UI.Areas

local SIZE, FOLLOWED = 22, 26 -- Layers.lua:611
local UNDER = "UI-QuestPoi-QuestNumber" -- Layers.lua:608
local OFFER = 18 -- Layers.lua:657
local DIM = "|cff9d9d9d" -- Layers.lua:652

-- StylePin's look, one an entry (Model makes a new one when it changes): (c) in progress, (b) ready.
local looks = setmetatable({}, { __mode = "k" })
local function Look(e)
	local look = looks[e]
	if look then return look end
	local icon = e.icon
	if not e.complete then
		icon = { atlas = icon.atlas, under = UNDER, tint = e.color, inner = e.inner and e.inner.texture, color = icon.color }
	else
		icon = UI.Art.Icon(icon.atlas) -- (a missing atlas: no icon, a dot)
		icon.color = e.icon.color
	end
	look = { size = e.followed and FOLLOWED or SIZE, glow = e.followed, count = e.count, icon = icon }
	looks[e] = look
	return look
end

UI.Quests = Pins.Layer("quests", 15, function(put)
	for _, e in ipairs(Model.Known("quests")) do put(e, Look(e)) end
end, function() return select(2, Model.Known("quests")) end, {
	tooltip = function(_, e) UI.QuestTooltip.Show(e) end,
	hover = Areas.Hover,
	click = Areas.Follow,
	cluster = true,
})

local offers = {} -- an offer's icon -> its look
UI.Offers = Pins.Layer("offers", 14, function(put)
	for _, e in ipairs(Model.Known("offers")) do
		local look = offers[e.icon]
		if not look then
			local icon = UI.Art.Icon(e.icon.atlas)
			icon.color = e.icon.color
			look = { size = OFFER, icon = icon }
			offers[e.icon] = look
		end
		put(e, look)
	end
end, function() return select(2, Model.Known("offers")) end, {
	lines = function(e) return e.name, e.line, DIM .. e.text .. "|r" end, -- Layers.lua:652-655
	cluster = true,
})

UI.Menus.Layer({ key = "quests", label = "Quests", group = "quests", tip = "Quests in your log. Click one to follow it." })
UI.Menus.Layer({ key = "offers", label = "Quests to pick up", group = "quests", tip = "Quests you could start nearby." })

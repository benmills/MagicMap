-- Your quests on the map (Layers.lua:579-621): Known("quests") as pins on the pin store (ui/Pins.lua),
-- in the world map's art (S46), Blizzard's atlases (Pins' (c), (b)): in progress, the yellow progress
-- atlas over the quest-number disc ("UI-QuestPoi-QuestNumber") tinted its difficulty (Model's colour),
-- the first unfinished objective's icon inside, its count under it; ready to turn in, the "questturnin"
-- "?" the atlas Model names; 24 px (the "?" 19), the one you follow 28 (23) in a thin gold ring (Pins' glow).
-- Hovering one lights its area (ui/Areas.lua) and shows its tooltip (ui/QuestTooltip.lua); a click opens
-- the track menu (ui/Track.lua), whose one row follows it ("Track quest"), again to stop ("Stop tracking").
-- And quests to pick up (Layers.lua:636-664): Known("offers"), "questnormal"
-- (the "!") at 18, their tooltip the quest, its line's name and "Quest to pick up". Over the other pins.
-- Their size: Settings > Icons > Quest icon size (ui/Feel.lua).

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Pins, Areas = UI.Pins, UI.Areas

local SIZE, FOLLOWED = 24, 28 -- in progress (Layers.lua:611: 22, 26, a little bigger)
local TURN_IN, TURN_IN_FOLLOWED = 19, 23 -- ready to turn in: the "?" a little smaller
local UNDER = "UI-QuestPoi-QuestNumber" -- Layers.lua:608
local OFFER = 18 -- Layers.lua:657
local DIM = "|cff9d9d9d" -- Layers.lua:652

-- StylePin's look, one an entry (Model makes a new one when it changes): (c) in progress, (b) ready.
local looks = setmetatable({}, { __mode = "k" })
local scale, scaleRev = 1, 0 -- the settings' (Feel "quests.scale"): a factor on the quests' size; the layer's rev moves with it
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
	local size = e.complete and (e.followed and TURN_IN_FOLLOWED or TURN_IN) or (e.followed and FOLLOWED or SIZE)
	look = { size = size * scale, glow = e.followed, count = e.count, icon = icon }
	looks[e] = look
	return look
end

UI.Quests = Pins.Layer("quests", 15, function(put)
	for _, e in ipairs(Model.Known("quests")) do put(e, Look(e)) end
end, (function()
	local seen, strength, n = nil, nil, 0
	return function()
		local r = select(2, Model.Known("quests"))
		if r ~= seen or scaleRev ~= strength then seen, strength, n = r, scaleRev, n + 1 end
		return n
	end
end)(), {
	tooltip = function(_, e) UI.QuestTooltip.Show(e) end,
	hover = Areas.Hover,
	-- (never grouped: a quest always stands where it is)
})

-- Quests' icon size (a factor on every in-progress and turn-in icon, on top of the icons'): the looks made again.
UI.Feel.Add("icons", "Size", {
	{ key = "quests.scale", kind = "slider", label = "Quest icon size", min = 0.7, max = 1.6, step = 0.1, pct = true, default = 1,
		apply = function(k)
			if scale == k then return end
			scale, scaleRev = k, scaleRev + 1
			looks = setmetatable({}, { __mode = "k" })
		end, tip = "The quests' icons, on top of the icon size." },
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
	-- (never grouped, as the quests)
})

UI.Menus.Layer({ key = "quests", label = "Quests", group = "quests", tip = "Quests in your log. Click one to track it." })
UI.Menus.Layer({ key = "offers", label = "Quests to pick up", group = "quests", tip = "Quests you could start nearby." })

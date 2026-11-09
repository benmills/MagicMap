-- Your quests on the map (Layers.lua:579-621): Known("quests") as pins on the pin store (ui/Pins.lua),
-- Blizzard's atlases as Blizzard's world map draws them: in progress, the yellow dots "Quest-In-Progress-Icon-yellow"
-- at full size on the quest disc "UI-QuestPoi-QuestNumber" untinted (Pins' (c)), its count under it;
-- ready to turn in, the "questturnin" "?" the atlas Model names; 24 px (the "?" 19), the one you follow
-- the same size, its glow saying it (ui/Pins.lua's Glow).
-- Hovering one lights its area (ui/Areas.lua) and shows its tooltip (ui/QuestTooltip.lua); a click grows the
-- tooltip into the popup (ui/Popup.lua), whose buttons (ui/Track.lua's Actions) follow it (Track, Path to), again
-- to stop, or open it in the quest log.
-- And quests to pick up (Layers.lua:636-664): Known("offers"), "questnormal"
-- (the "!") at 18, their tooltip the quest, then "Quest to pick up" and its line's name. Over the other pins.
-- Their types (Settings > Pins, ui/PinTypes.lua): In progress, To turn in (the "?") and To pick
-- up (the "!"), never grouped; the "?" and "!" with Blizzard's other quest art to choose from. 2.1's
-- "Quest icon size" (quests.scale, a factor on top of the icon size) is moved, once, onto In progress's and To turn
-- in's own size at load.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Pins, Areas = UI.Pins, UI.Areas

local SIZE = 24 -- in progress (Layers.lua:611: 22)
local TURN_IN = 19 -- ready to turn in: the "?" a little smaller
local OFFER = 18 -- Layers.lua:657
local SEP = UI.Tip.SEP
local UNDER = "UI-QuestPoi-QuestNumber" -- the world map's quest disc: dark, its gold ring (untinted)
local ACTIVE = { atlas = "Quest-In-Progress-Icon-yellow", under = UNDER, scale = 1 } -- (model/Quests.lua's, its page sample)
local Types, Feel = UI.PinTypes, UI.Feel
local TURN, OFFER_ART = ns.Atlas.BlipArt("questender"), ns.Atlas.BlipArt("questgiver")

Types.Add({ id = "quest", family = "quests", name = "In progress", look = { size = SIZE, icon = ACTIVE },
	tip = "A quest in your log not yet done, its progress under it." })
Types.Add({ id = "turnin", family = "quests", name = "To turn in", look = { size = TURN_IN, icon = { atlas = TURN } },
	icons = { { "Turn in", "A:" .. TURN }, { "Repeatable", "A:questrepeatableturnin" }, { "Campaign", "A:quest-campaign-turnin" } },
	tip = "A quest ready to hand in." })
Types.Add({ id = "offer", family = "quests", name = "To pick up", look = { size = OFFER, icon = { atlas = OFFER_ART } },
	icons = { { "Available", "A:" .. OFFER_ART }, { "Daily", "A:questdaily" }, { "Small", "A:smallquestbang" },
		{ "Campaign", "A:quest-campaign-available" } },
	tip = "A quest you could start nearby." })

-- 2.1's Quest icon size: its saved factor times the icon size's, onto the two quest types' own size (on its step, in
-- range), and gone.
local OLD = "quests.scale"
Feel.OnLoad(function()
	local t = UI.saved.feel
	local q = t and t[OLD]
	if type(q) ~= "number" then return end
	t[OLD] = nil
	local k = Feel.Entry("pins.quest.size")
	local v = math.floor(q * Feel.Get("icons.scale") / k.step + 0.5) * k.step -- /: never 0 (a slider's step > 0)
	v = math.floor(math.max(k.min, math.min(k.max, v)) * 1000 + 0.5) / 1000
	if not next(t) then UI.saved.feel = nil end
	Feel.Set("pins.quest.size", v)
	Feel.Set("pins.turnin.size", v)
end)

-- StylePin's look, one an entry (Model makes a new one when it changes): (b), in progress or ready.
local looks = setmetatable({}, { __mode = "k" })
local function Look(e)
	local look = looks[e]
	if look then return look end
	local icon = UI.Art.Icon(e.icon.atlas) -- (a missing atlas: no icon, a dot)
	icon.color = e.icon.color
	if not e.complete then icon.under, icon.scale = UNDER, 1 end -- (the world map's: its dots on the disc, full size)
	local size = e.complete and TURN_IN or SIZE -- (the one you follow its size too: it glows, ui/Pins.lua)
	look = { size = size, count = e.count, icon = icon, type = e.complete and "turnin" or "quest" }
	looks[e] = look
	return look
end

UI.Quests = Pins.Layer("quests", 15, function(put)
	for _, e in ipairs(Model.Known("quests")) do put(e, Look(e)) end
end, function() return select(2, Model.Known("quests")) end, {
	tooltip = UI.QuestTooltip.Fill, -- (a click grows it into the popup: ui/Pins.lua's Tap)
	hover = Areas.Hover,
	-- (never grouped: a quest always stands where it is)
})

local offers = {} -- an offer's icon -> its look
UI.Offers = Pins.Layer("offers", 14, function(put)
	for _, e in ipairs(Model.Known("offers")) do
		local look = offers[e.icon]
		if not look then
			local icon = UI.Art.Icon(e.icon.atlas)
			icon.color = e.icon.color
			look = { size = OFFER, icon = icon, type = "offer" }
			offers[e.icon] = look
		end
		put(e, look)
	end
end, function() return select(2, Model.Known("offers")) end, {
	lines = function(e) return e.name, e.text .. (e.line and SEP .. e.line or "") end, -- Layers.lua:652-655: "Quest to pick up"
	-- (never grouped, as the quests)
})

UI.Menus.Layer({ key = "quests", label = "Quests", group = "quests", tip = "Quests in your log. Click one to track it." })
UI.Menus.Layer({ key = "offers", label = "Quests to pick up", group = "quests", tip = "Quests you could start nearby." })

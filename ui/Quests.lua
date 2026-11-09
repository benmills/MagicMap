-- Your quests in progress on the map (Layers.lua:579-621): Known("quests") as pins on the pin store (ui/Pins.lua),
-- Blizzard's atlases as Blizzard's world map draws them: the yellow dots "Quest-In-Progress-Icon-yellow" at full size
-- on the quest disc "UI-QuestPoi-QuestNumber" untinted (Pins' (c)), its count under it; 24 px, the one you follow
-- the same size, its glow saying it (ui/Pins.lua's Glow). Ready to turn in, and quests to pick up: none of ours, the
-- "?" and "!" are Blizzard's blips (the overlay: game/Minimap.lua).
-- Hovering one lights its area (ui/Areas.lua) and shows its tooltip (ui/QuestTooltip.lua); a click grows the
-- tooltip into the popup (ui/Popup.lua), whose buttons (ui/Track.lua's Actions) follow it (Track, Path to), again
-- to stop, or open it in the quest log.
-- Its type (Settings > Pins, ui/PinTypes.lua): In progress, never grouped. 2.1's "Quest icon size" (quests.scale, a
-- factor on top of the icon size) is moved, once, onto In progress's own size at load.

local _, ns = ...
local UI, Model = ns.UI, ns.Model
local Pins, Areas = UI.Pins, UI.Areas

local SIZE = 24 -- in progress (Layers.lua:611: 22)
local UNDER = "UI-QuestPoi-QuestNumber" -- the world map's quest disc: dark, its gold ring (untinted)
local ACTIVE = { atlas = "Quest-In-Progress-Icon-yellow", under = UNDER, scale = 1 } -- (model/Quests.lua's, its page sample)
local Types, Feel = UI.PinTypes, UI.Feel

Types.Add({ id = "quest", family = "quests", name = "In progress", look = { size = SIZE, icon = ACTIVE },
	tip = "A quest in your log not yet done, its progress under it." })
-- 2.1's Quest icon size: its saved factor times the icon size's, onto In progress's own size (on its step, in
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
end)

-- StylePin's look, one an entry (Model makes a new one when it changes): (b), in progress.
local looks = setmetatable({}, { __mode = "k" })
local function Look(e)
	local look = looks[e]
	if look then return look end
	local icon = UI.Art.Icon(e.icon.atlas) -- (a missing atlas: no icon, a dot)
	icon.color = e.icon.color
	icon.under, icon.scale = UNDER, 1 -- (the world map's: its dots on the disc, full size)
	-- (the one you follow its size too: it glows, ui/Pins.lua)
	look = { size = SIZE, count = e.count, icon = icon, type = "quest" }
	looks[e] = look
	return look
end

UI.Quests = Pins.Layer("quests", 15, function(put)
	for _, e in ipairs(Model.Known("quests")) do
		if not e.complete then put(e, Look(e)) end -- (ready to turn in: Blizzard's "?" blip, the overlay's)
	end
end, function() return select(2, Model.Known("quests")) end, {
	tooltip = UI.QuestTooltip.Fill, -- (a click grows it into the popup: ui/Pins.lua's Tap)
	hover = Areas.Hover,
	-- (never grouped: a quest always stands where it is)
})

UI.Menus.Layer({ key = "quests", label = "Quests", group = "quests", tip = "Quests in your log. Click one to track it." })

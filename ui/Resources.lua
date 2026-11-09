-- Resources (#18): the tracker kept on (the gear's Keep tracking row; its setting has no page).
-- Keep tracking: one of the spells' tracking types the character knows (Model.tracking's `spell`: Find Herbs, Find
-- Minerals, a hunter's tracks), Game turning it back on whenever the game may have dropped it (View.keep:
-- game/Keep.lua). One, not one a type: the client has one tracking spell on at a time (classic's rule: a second one
-- cast takes the first's place). The setting "resources.keep": "auto" (the default), your gathering tracker, the
-- first you know of Find Herbs, Find Minerals, Find Treasure (so a new character, or an alt with other professions,
-- needs no choosing); a spell's ID, that one (on a character that doesn't know it: auto's); "off", none. Saved
-- account-wide as every setting is. One you pick yourself, in Blizzard's tracking menu or Nearby's rows, is the new
-- choice (its spell turned on, while the setting isn't off); one you turn off stays off till the game next drops it.
-- Reachable from the gear's own menu (Menus.Gear: Resources.Menu, a row "Keep tracking: <name>" and a radio a
-- tracker, Off last).

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Feel = UI.Feel

local Resources = {}
UI.Resources = Resources

local KEY = "resources.keep"
local GATHER = { 2383, 8387, 2580, 8388, 2481 } -- Find Herbs (two ranks), Find Minerals (two), Find Treasure (Minimap.lua:34-41)


-- The spells' tracking types the client lists now (what Game can keep on).
local function Spells()
	local out = {}
	for _, t in ipairs(Model.tracking) do
		if t.spell then out[#out + 1] = t end
	end
	return out
end
local function Spell(id)
	for _, t in ipairs(Model.tracking) do
		if t.spell and t.id == id then return t end
	end
end
local function Auto()
	for _, id in ipairs(GATHER) do
		if Spell(id) then return id end
	end
end

-- The tracker kept on: its ID (MM.ObsTracking.id), false for none (View.keep).
function Resources.Keep()
	local v = Feel.Get(KEY)
	if v == "off" then return false end
	local id = tonumber(v)
	return id and Spell(id) and id or Auto() or false
end
local Keep = Resources.Keep

-- id chosen (false: off), saved as auto when auto's is it.
local function Choose(id)
	Feel.Set(KEY, not id and "off" or id == Auto() and "auto" or tostring(id))
end

local function Options()
	local auto = Spell(Auto())
	local out = { { "Your gathering tracker" .. (auto and " (" .. auto.name .. ")" or ""), "auto" } }
	for _, t in ipairs(Spells()) do out[#out + 1] = { t.name, tostring(t.id), t.texture } end
	out[#out + 1] = { "Off", "off" }
	return out
end
Feel.Add(false, nil, { -- (no page: the gear's Keep tracking row)
	{ key = KEY, kind = "select", label = "Keep tracking", default = "auto", options = Options,
		tip = "Turned back on whenever the game drops it: at login, after a loading screen, death or resurrection. "
			.. "Your gathering tracker is the first you know of Find Herbs, Find Minerals and Find Treasure. One you pick "
			.. "yourself in the tracking menu becomes the one kept; one you turn off stays off till the game next drops it." },
})

-- A spell tracker you turned on (it was listed off, now on) that isn't the one kept: your new choice.
local last = Model.tracking
Runtime.Step("ui", "ui: keep tracking", function()
	local list = Model.tracking
	if list == last then return end
	local before = last
	last = list
	if not before[1] or Feel.Get(KEY) == "off" then return end
	local was = {}
	for _, t in ipairs(before) do
		if t.spell then was[t.id] = t.active end
	end
	local keep = Keep()
	for _, t in ipairs(list) do
		if t.spell and t.active and was[t.id] == false and t.id ~= keep then return Choose(t.id) end
	end
end)

-- The gear's row (ui/Menus.lua's Gear): "Keep tracking: <name>", a radio a tracker and Off; none while the character
-- knows no tracking spell.
local Run = Runtime.Wrap("map: keep pick", function(fn, arg) fn(arg) end)
local Mark = UI.Tip.Mark -- (a spell's icon, an Interface\Icons one: cropped)
function Resources.Menu(root)
	local spells = Spells()
	if not spells[1] then return end
	local cur = Spell(Keep())
	local sub = root:CreateButton(Mark(cur and cur.texture or "Interface\\Icons\\INV_Misc_Flower_02") .. "Keep tracking: "
		.. (cur and cur.name or "off"))
	for _, t in ipairs(spells) do
		sub:CreateRadio(Mark(t.texture) .. t.name, function() return Keep() == t.id end, function()
			Run(Choose, t.id)
			return MenuResponse.Refresh
		end)
	end
	sub:CreateRadio("Off", function() return Keep() == false end, function()
		Run(Choose, false)
		return MenuResponse.Refresh
	end)
end

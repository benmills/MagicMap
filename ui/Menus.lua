-- Menus are the client's own (MenuUtil), no skin (Menu.lua). Opened through here, they count
-- as open for the controls that opened them, so those don't fade out under them.
-- The gear menu (GearMenu.lua), its minimum for now: what others add above (layers: M2-M4,
-- Menus.gear) and Settings: Map (Colour-matched tiles), Minimap (Minimap button, Reset
-- position, Use Blizzard's minimap).

local _, ns = ...
local UI = ns.UI

local Menus = { gear = {} } -- gear: fn(root) each, in order, above Settings
UI.Menus = Menus

local menu -- the last menu opened

function Menus.IsOpen()
	return menu ~= nil and menu:IsShown()
end

function Menus.Show(owner, generator)
	menu = MenuUtil.CreateContextMenu(owner, generator)
	return menu
end

-- Settings, in sections: { title, rows }. A row is a checkbox ({ label, on =, run =, tip = })
-- or a button ({ label, run = }) (GearMenu.lua:30-59).
local SETTINGS = {
	{ "Map", {
		{ "Colour-matched tiles", on = function() return UI.saved.tint end, run = function() UI.saved.tint = not UI.saved.tint end,
			tip = "Evens out the minimap art's colours where tiles meet, and fades the coasts into the sea." },
	} },
	{ "Minimap", {
		{ "Minimap button", on = function() return UI.saved.button end, run = function() UI.Icon() end,
			tip = "The button on Blizzard's minimap, for when MagicMap is switched off." },
		{ "Reset position", run = function() UI.BigMap.Reset() end },
		{ "Use Blizzard's minimap", run = function() UI.Window.frame:Hide() end },
	} },
}

local function AddSections(sub, sections)
	for n, section in ipairs(sections) do
		if n > 1 then sub:CreateDivider() end
		sub:CreateTitle(section[1])
		for _, row in ipairs(section[2]) do
			if row.on then
				local cb = sub:CreateCheckbox(row[1], function() return row.on() and true or false end, function()
					row.run()
					return MenuResponse.Refresh
				end)
				cb:SetTooltip(function(tooltip)
					tooltip:SetText(row[1], 1, 1, 1)
					tooltip:AddLine(row.tip, 1, 0.82, 0, true)
				end)
			else
				sub:CreateButton(row[1], function() row.run() end)
			end
		end
	end
end

function Menus.Gear(owner)
	Menus.Show(owner, function(_, root)
		for _, fn in ipairs(Menus.gear) do fn(root) end
		if Menus.gear[1] then root:CreateDivider() end
		AddSections(root:CreateButton("Settings"), SETTINGS)
	end)
end

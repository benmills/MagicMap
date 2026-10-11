-- The gear menu: what's drawn (a submenu per layer section, Layers.lua),
-- Blizzard's minimap tracking (its own button is hidden with the minimap's
-- corner while MagicMap has it), and settings, with the debug helpers
-- under Advanced.

local ADDON, ns = ...
local db

-- Blizzard's tracking types, but for those ours replace (MinimapTakeover's
-- DUPLICATES: their filters stay off while the Minimap is in our map).
local function AddTracking(root)
	local C = C_Minimap
	local menu = root:CreateButton("Tracking")
	for i = 1, C.GetNumTrackingTypes() do
		local filter, info = C.GetTrackingFilter(i), C.GetTrackingInfo(i)
		if info and not (filter and ns.Takeover.DUPLICATES[filter.filterID]) then
			menu:CreateCheckbox(info.name,
				function() local t = C.GetTrackingInfo(i); return t and t.active end,
				function()
					local t = C.GetTrackingInfo(i)
					if t then C.SetTracking(i, not t.active) end
					return MenuResponse.Refresh
				end)
		end
	end
end

local function Command(cmd) SlashCmdList.MAGICMAP(cmd) end

-- Settings, in sections: { title, rows }. A row is a checkbox ({ label, on =,
-- run =, tip = }), a button ({ label, run = }), or a submenu ({ label, sub =
-- sections }).
local ADVANCED = {
	{ "Diagnostics", {
		{ "Debug info in the title", on = function() return db.debug end, run = function() Command("debug") end,
			tip = "Tile, zoom and layout timings next to the zone name." },
		{ "Blizzard's terrain over ours", on = function() return ns.SyncShown() end, run = function() Command("sync") end,
			tip = "Blizzard's own minimap at half strength, to check its blips land on our map." },
		{ "Hide Blizzard's terrain by fading", on = function() return db.terrainByAlpha end, run = function()
			db.terrainByAlpha = not db.terrainByAlpha or nil
			ns.Takeover.RefreshTerrain()
		end, tip = "The older way to hide Blizzard's minimap terrain, if its own switch shows a solid square." },
	} },
	{ "Performance", {
		{ "Record 10 seconds", on = function() return ns.PerfRecording() end, run = function() Command("perf") end,
			tip = "Times every part of MagicMap while you play, then prints a summary." },
		{ "Compare with other addons", run = function() Command("perf top") end },
		{ "Memory breakdown", run = function() Command("perf mem") end },
	} },
}
local SETTINGS = {
	{ "Map", {
		{ "Colour-matched tiles", on = function() return db.tint end, run = function() Command("tint") end,
			tip = "Evens out the minimap art's colours where tiles meet, and fades the coasts into the sea." },
		{ "Blizzard's blips past the edge", on = function() return db.blipsPastEdge end,
			run = function() db.blipsPastEdge = not db.blipsPastEdge or nil end,
			tip = "On a long window, Blizzard's herbs, ore and tracked NPCs cover all of it, spilling past its "
				.. "shorter sides. Off, they stay in the biggest square around you inside the window." },
		{ "One marker for each thing", on = function() return db.hideDupes ~= false end, run = function() Command("dupes") end,
			tip = "Turns off Blizzard's own markers for what MagicMap draws (flight points, quest objectives, points of interest)." },
	} },
	{ "Minimap", {
		{ "Minimap button", on = function() return not db.minimap.hide end, run = function() Command("icon") end,
			tip = "The button on Blizzard's minimap, for when MagicMap is switched off." },
		{ "Reset position", run = function() Command("reset") end },
		{ "Use Blizzard's minimap", run = function() ns.frame:Hide() end },
	} },
	{ nil, { { "Advanced", sub = ADVANCED } } },
}

local function AddSections(menu, sections)
	for n, section in ipairs(sections) do
		if n > 1 then menu:CreateDivider() end
		if section[1] then menu:CreateTitle(section[1]) end
		for _, row in ipairs(section[2]) do
			if row.sub then
				AddSections(menu:CreateButton(row[1]), row.sub)
			elseif row.on then
				local cb = menu:CreateCheckbox(row[1], function() return row.on() and true or false end, function()
					row.run()
					return MenuResponse.Refresh
				end)
				if row.tip then
					cb:SetTooltip(function(tooltip)
						tooltip:SetText(row[1], 1, 1, 1)
						tooltip:AddLine(row.tip, 1, 0.82, 0, true)
					end)
				end
			else
				menu:CreateButton(row[1], function() row.run() end)
			end
		end
	end
end

ns.gearButton:HookScript("OnClick", function(self)
	ns.OpenClientMenu(self, function(_, root)
		ns.AddLayerMenus(root)
		AddTracking(root)
		root:CreateDivider()
		AddSections(root:CreateButton("Settings"), SETTINGS)
	end)
end)

ns.On("Loaded", function(savedDB) db = savedDB end)

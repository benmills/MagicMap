-- The gear menu: what's drawn (a submenu per layer section, Layers.lua),
-- Blizzard's minimap tracking (its own button is hidden with the minimap's
-- corner while MagicMap has it), and settings and debug helpers.

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

-- { label, on = fn -> bool, run = fn } (a checkbox), or { label, run = fn } (a button), or "-".
local SETTINGS = {
	{ "Minimap button", on = function() return not db.minimap.hide end, run = function() Command("icon") end },
	{ "Tile colours", on = function() return db.tint end, run = function() Command("tint") end },
	{ "Hide Blizzard's copies of ours", on = function() return db.hideDupes ~= false end, run = function() Command("dupes") end },
	{ "Back onto the minimap's spot", run = function() Command("reset") end },
	{ "Use Blizzard's minimap", run = function() ns.frame:Hide() end },
	"-",
	{ "Debug info in the title", on = function() return db.debug end, run = function() Command("debug") end },
	{ "Blizzard's terrain over ours", on = function() return ns.SyncShown() end, run = function() Command("sync") end },
	{ "Hide its terrain by fading it (the old way)", on = function() return db.terrainByAlpha end, run = function()
		db.terrainByAlpha = not db.terrainByAlpha or nil
		ns.Takeover.RefreshTerrain()
	end },
	{ "Record performance", on = function() return ns.PerfRecording() end, run = function() Command("perf") end },
	{ "CPU and memory vs. other addons", run = function() Command("perf top") end },
	"-",
	{ "Test: clip blips with a scroll frame", on = function() return ns.Takeover.TestClip() end,
		run = function() ns.Takeover.SetTest("testClip", not ns.Takeover.TestClip()) end },
	{ "Test: Minimap as wide as the window", on = function() return ns.Takeover.TestStretch() end,
		run = function() ns.Takeover.SetTest("testStretch", not ns.Takeover.TestStretch()) end },
	{ "Memory breakdown", run = function() Command("perf mem") end },
}

local function AddSettings(root)
	local menu = root:CreateButton("Settings")
	for _, s in ipairs(SETTINGS) do
		if s == "-" then
			menu:CreateDivider()
		elseif s.on then
			menu:CreateCheckbox(s[1], function() return s.on() and true or false end, function()
				s.run()
				return MenuResponse.Refresh
			end)
		else
			menu:CreateButton(s[1], function() s.run() end)
		end
	end
end

ns.gearButton:HookScript("OnClick", function(self)
	ns.OpenClientMenu(self, function(_, root)
		ns.AddLayerMenus(root)
		AddTracking(root)
		root:CreateDivider()
		AddSettings(root)
	end)
end)

ns.On("Loaded", function(savedDB) db = savedDB end)

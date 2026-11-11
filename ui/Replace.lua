-- What MagicMap replaces: two independent choices, saved as UI.saved.replace = { minimap, worldmap }
-- (types/saved.lua), nil until the user picks (the welcome, ui/Welcome.lua, or Settings):
--   minimap  our small map takes the Minimap's spot, shown from login. Off: Blizzard's minimap stays, and
--            our window is never small: it opens big, and closing it hides it (ui/BigMap.lua Close).
--   worldmap M opens our big map (Game hears it: game/Hooks.lua reads View.replace). Off: M is Blizzard's.
-- Neither: nothing of Blizzard's is touched; the minimap button, the addon compartment and /mm open and close
-- our big map as a window of its own. A fresh install is that until the welcome is answered. The Minimap
-- is borrowed as the blips' overlay only while ours replaces it (ui/View.lua: game/Minimap.lua engages then);
-- otherwise Blizzard's minimap is left as it is.
-- API: Replace.Get(key), Replace.Set(key, on) (live: shows or hides the window as the mode says; saves),
-- Replace.Chosen(); Replace.Load(saved, fresh) is View's, at load (migration). Both are switches in
-- Settings > General > Blizzard's maps (ui/Feel.lua; kept here, so a reset leaves them).

local _, ns = ...
local UI = ns.UI

local Replace = {}
UI.Replace = Replace

local KEYS = { minimap = true, worldmap = true }

function Replace.Chosen() return UI.saved.replace ~= nil end

function Replace.Get(key)
	local r = UI.saved.replace
	return r ~= nil and r[key] == true
end

function Replace.Set(key, on)
	if not KEYS[key] then return end
	on = on == true
	local saved = UI.saved
	local r = saved.replace
	if not r then
		r = { minimap = false, worldmap = false }
		saved.replace = r
	end
	saved.welcome = nil
	local was = r[key]
	r[key] = on
	if key ~= "minimap" or was == on then return end
	local frame = UI.Window.frame
	if on then
		if not frame:IsShown() then frame:Show() end -- (the small map, on the Minimap's spot)
	elseif frame:IsShown() and not UI.BigMap.big then
		frame:Hide() -- (no small state without the minimap: a big one stays till closed)
	end
end

-- UI's saved part just loaded (ui/View.lua). An existing 2.0 player keeps what they had: minimap unless they'd
-- chosen Blizzard's, the world map unless they'd turned the override off; no welcome. A new install is
-- marked (welcome), so its second login isn't mistaken for an existing player's. The old setting retires.
function Replace.Load(s, fresh)
	if s.replace == nil then
		if fresh then
			s.welcome = true
		elseif not s.welcome then
			s.replace = { minimap = s.minimap ~= "blizzard", worldmap = s.worldmap ~= false }
		end
	end
	if s.replace and not s.replace.minimap then s.minimap = "ours" end -- ("blizzard" is the quick hide while minimap is on)
	s.worldmap = nil
end

local function Switch(key) return function(on) Replace.Set(key, on) end end
UI.Feel.Add("general", "Blizzard's maps", {
	{ key = "replace.minimap", kind = "toggle", label = "Replace minimap", default = false, keep = true,
		get = function() return Replace.Get("minimap") end, set = Switch("minimap"),
		tip = "Our map stands in for Blizzard's minimap. Off: Blizzard's minimap as usual." },
	{ key = "replace.worldmap", kind = "toggle", label = "Replace world map", default = false, keep = true,
		get = function() return Replace.Get("worldmap") end, set = Switch("worldmap"),
		tip = "M opens our map in place of Blizzard's world map. Off: M opens Blizzard's world map as usual." },
})

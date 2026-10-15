-- Art: every atlas and file UI draws with, by name. Checked against the client
-- once after login's grace and on /mma check art; each miss traces "art" (its
-- name). Forever lacks some art other clients have, and a missing name draws
-- nothing, silently (spike-bugs L2, L5). A name UI starts using goes here.
-- Not listed: data's art (tile FileDataIDs, Textures\Sea: generated, K4) and
-- the client's own tracking icons (whatever C_Minimap names).

local _, ns = ...
local UI, Runtime = ns.UI, ns.Runtime
local Command = ns.Game.Command

local Art = {
	atlases = {
		"taxinode_alliance", "taxinode_horde", "taxinode_neutral", -- ui/Labels.lua: flight points
		"vignettekill", "vignettekillelite",                       -- ui/Rares.lua (model/Rares.lua ICON)
	},
	files = {
		"Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",        -- ui/Map.lua: the grip
		"Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight",
		"Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down",
		"Interface\\Minimap\\MinimapArrow",                      -- ui/Map.lua: you
		"Interface\\COMMON\\Indicator-Yellow",                   -- ui/Blips.lua: a blip without an icon
		"Fonts\\MORPHEUS.TTF", "Fonts\\FRIZQT__.TTF",            -- ui/Labels.lua
		136458, 136453, 136452, 136466, 136454, 136463, 136465,  -- ui/Blips.lua: services (game/Blips.lua SERVICE)
	},
}
UI.Art = Art

local GRACE = 6 -- s after login or /reload: past its grace (5 s, game/Game.lua)

-- A path the client resolves; a FileDataID a texture takes (the client has no lookup by id).
local probe = UIParent:CreateTexture()
probe:Hide()
local function Has(file)
	if type(file) == "string" then return GetFileIDFromPath(file) ~= nil end
	return probe:SetTexture(file) ~= false
end

-- The names the client lacks, each traced.
local function Check()
	local misses = {}
	for _, name in ipairs(Art.atlases) do
		if not C_Texture.GetAtlasInfo(name) then misses[#misses + 1] = name end
	end
	for _, file in ipairs(Art.files) do
		if not Has(file) then misses[#misses + 1] = tostring(file) end
	end
	for _, m in ipairs(misses) do Runtime.Trace("art", m) end
	return misses
end

local function Report(misses)
	print(misses[1] and "  art missing: " .. table.concat(misses, ", ")
		or string.format("  art: all %d there", #Art.atlases + #Art.files))
end

Runtime.On("PLAYER_ENTERING_WORLD", "ui: art", function(_, login, reload)
	if not (login or reload) then return end
	Runtime.After(GRACE, "ui: art check", function()
		local misses = Check()
		if misses[1] then Report(misses) end
	end)
end)

Command({ kind = "slash", name = "check art", help = "the atlases and files UI draws with: any the client lacks",
	fn = function() Report(Check()) end })

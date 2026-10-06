-- Landmarks: things worth finding again.
--
--  * Services you've used: vendors, innkeepers, trainers, banks, auction
--    houses, stable masters, mailboxes. There is no API that lists NPC
--    positions, but when you interact with one you're standing next to it,
--    so your own position is an accurate fix. Learned as you play, and kept
--    account-wide (MagicMapLandmarks) so every character benefits.
--  * Rares: learned from vignettes (exact position) or from targeting one.
--  * Live vignettes: rares and treasures the game is currently showing.
--  * Area POIs the game defines for each zone.
--
-- Icons are FileDataIDs of the classic minimap tracking / gossip icons, which
-- the client ships even where their file names aren't resolvable.

local ADDON, ns = ...
local state = ns.state
local store -- MagicMapLandmarks[instanceID][key] = { kind, name, sub, n, w, t }

local KINDS = {
	inn = { label = "Innkeeper", icon = 136458 },
	vendor = { label = "Vendor", icon = 132060 },
	repair = { label = "Repairs", icon = 136465 },
	food = { label = "Food & drink", icon = 136457 },
	reagents = { label = "Reagents", icon = 136464 },
	ammo = { label = "Ammunition", icon = 136451 },
	poisons = { label = "Poisons", icon = 136462 },
	classTrainer = { label = "Class trainer", icon = 136455 },
	proTrainer = { label = "Profession trainer", icon = 136463 },
	trainer = { label = "Trainer", icon = 132058 },
	bank = { label = "Bank", icon = 136453 },
	ah = { label = "Auction house", icon = 136452 },
	stable = { label = "Stable master", icon = 136466 },
	mailbox = { label = "Mailbox", icon = 136459, minZoom = 300 },
	flight = { label = "Flight master", icon = 136456 },
	rare = { label = "Rare", icon = 137008, minZoom = 60 },
}
local SERVICE_MIN_ZOOM = 180 -- about "a town fills the window"

-- Subtitle keywords (English clients) -> kind. First match wins.
local SUBTITLE_KINDS = {
	{ "innkeeper", "inn" }, { "banker", "bank" }, { "auctioneer", "ah" }, { "stable master", "stable" },
	{ "flight master", "flight" }, { "gryphon master", "flight" }, { "wind rider master", "flight" },
	{ "hippogryph master", "flight" }, { "bat handler", "flight" },
	{ "trainer", "trainer" },
	{ "repair", "repair" }, { "armorer", "repair" }, { "weaponsmith", "repair" },
	{ "food", "food" }, { "drink", "food" }, { "baker", "food" }, { "butcher", "food" }, { "innkeep", "inn" },
	{ "reagent", "reagents" }, { "ammunition", "ammo" }, { "arrow", "ammo" }, { "poison", "poisons" },
	{ "vendor", "vendor" }, { "merchant", "vendor" }, { "supplies", "vendor" }, { "goods", "vendor" },
}

local CLASS_NAMES = {}
for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
	for _, name in pairs(names) do CLASS_NAMES[name:lower()] = true end
end

---------------------------------------------------------------------------
-- Reading the NPC you're talking to
---------------------------------------------------------------------------

local scanTip
local function Subtitle(unit)
	local line
	if C_TooltipInfo and C_TooltipInfo.GetUnit then
		local data = C_TooltipInfo.GetUnit(unit)
		line = data and data.lines and data.lines[2] and data.lines[2].leftText
	else
		scanTip = scanTip or CreateFrame("GameTooltip", "MagicMapScanTip", nil, "GameTooltipTemplate")
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
		scanTip:SetUnit(unit)
		local fs = _G["MagicMapScanTipTextLeft2"]
		line = fs and fs:GetText()
		scanTip:Hide()
	end
	if type(line) ~= "string" or line == "" then return nil end
	line = line:gsub("^<(.*)>$", "%1")
	-- Line 2 is the level line for NPCs without a title.
	if line:find("^" .. (LEVEL or "Level")) or line:find("%d") then return nil end
	return line
end

local function KindFromSubtitle(sub)
	if not sub then return nil end
	local s = sub:lower()
	for _, rule in ipairs(SUBTITLE_KINDS) do
		if s:find(rule[1], 1, true) then
			if rule[2] == "trainer" then
				local first = s:match("^(%S+)")
				return (first and CLASS_NAMES[first]) and "classTrainer" or "proTrainer"
			end
			return rule[2]
		end
	end
end

local function NpcID(unit)
	local guid = UnitGUID(unit)
	if not guid then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function Remember(kind, unit, fallbackName, north, west, inst)
	if not store then return end
	if not north then
		local n, w, _, i = UnitPosition("player")
		if not n then return end -- instances hide your position
		north, west, inst = n, w, i
	end
	local name = unit and UnitName(unit) or fallbackName or KINDS[kind].label
	local sub = unit and Subtitle(unit)
	local id = unit and NpcID(unit)
	-- One entry per NPC; objects (mailboxes) are keyed by rounded position.
	local key = id and (kind .. ":" .. id)
		or (kind .. ":" .. math.floor(north / 8 + 0.5) .. ":" .. math.floor(west / 8 + 0.5))
	store[inst] = store[inst] or {}
	store[inst][key] = {
		kind = kind, name = name, sub = sub,
		n = math.floor(north * 10 + 0.5) / 10, w = math.floor(west * 10 + 0.5) / 10,
		t = time(),
	}
	ns.RefreshLayer(kind == "rare" and "rares" or "services")
end

local function OnInteract(defaultKind)
	local unit = UnitExists("npc") and "npc" or nil
	local kind = unit and KindFromSubtitle(Subtitle(unit)) or defaultKind
	if not kind or kind == "flight" then return end -- flight masters have their own layer
	if kind == "vendor" and CanMerchantRepair and CanMerchantRepair() then kind = "repair" end
	Remember(kind, unit)
end

---------------------------------------------------------------------------
-- Layers
---------------------------------------------------------------------------

local function StoredPins(mapID, wantRares)
	local list = {}
	for _, e in pairs(store and store[mapID] or {}) do
		if (e.kind == "rare") == wantRares and KINDS[e.kind] then
			local k = KINDS[e.kind]
			local col, row = ns.WorldToTile(e.n, e.w)
			local lines = { e.sub or k.label }
			if e.kind == "rare" then
				lines[#lines + 1] = "|cff808080Seen here " .. date("%b %d", e.t) .. "|r"
			end
			ns.PinAtTile(list, mapID, col, row, {
				size = e.kind == "rare" and 18 or 16,
				minZoom = k.minZoom or SERVICE_MIN_ZOOM,
				title = e.name, lines = lines, icon = { texture = k.icon },
				kind = e.kind, -- for ZoneInfo's "nearest innkeeper"
			})
		end
	end
	return list
end

ns.AddPinLayer({ key = "services", label = "Vendors & services you've visited", default = true },
	function(mapID) return StoredPins(mapID, false) end)

ns.AddPinLayer({ key = "rares", label = "Rares you've seen", default = true },
	function(mapID) return StoredPins(mapID, true) end)

-- Live vignettes (what the game is showing near you right now).
local function VignettePins(mapID)
	local list = {}
	local V = C_VignetteInfo
	if not (V and V.GetVignettes and V.GetVignetteInfo and V.GetVignettePosition) then return list end
	local uiMapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not uiMapID then return list end
	for _, guid in ipairs(V.GetVignettes() or {}) do
		local info = V.GetVignetteInfo(guid)
		if info and not info.isDead and info.name then
			local pos = V.GetVignettePosition(guid, uiMapID)
			local x, y
			if pos then x, y = pos:GetXY() end -- not `pos and pos:GetXY()`: `and` keeps only x
			if x then
				local inst, col, row = ns.MapToTile(uiMapID, x, y)
				ns.PinAtTile(list, inst, col, row, {
					size = 20, title = info.name, lines = { "|cff808080Nearby now|r" },
					icon = { atlas = info.atlasName, color = { 1, 0.4, 0.3 } },
				})
				-- Rare vignettes get remembered at their exact position.
				local atlas = (info.atlasName or ""):lower()
				if inst and (atlas:find("rare") or atlas:find("elite")) then
					local north = (32 - row) * 1600 / 3
					local west = (32 - col) * 1600 / 3
					Remember("rare", nil, info.name, north, west, inst)
				end
			end
		end
	end
	return list
end
ns.AddPinLayer({ key = "vignettes", label = "Rares & treasures nearby (live)", default = true }, VignettePins)

-- Area POIs defined by the game for each zone.
local function AreaPOIPins(mapID)
	local list, seen = {}, {}
	local A = C_AreaPoiInfo
	if not (A and A.GetAreaPOIForMap and A.GetAreaPOIInfo) then return list end
	for _, uiMapID in ipairs(ns.GetQuestMaps(mapID)) do
		for _, poiID in ipairs(A.GetAreaPOIForMap(uiMapID) or {}) do
			if not seen[poiID] then
				seen[poiID] = true
				local info = A.GetAreaPOIInfo(uiMapID, poiID)
				local x, y
				if info and info.position then x, y = info.position:GetXY() end
				if x then
					local inst, col, row = ns.MapToTile(uiMapID, x, y)
					ns.PinAtTile(list, inst, col, row, {
						size = 18, title = info.name, lines = { info.description },
						icon = { atlas = info.atlasName, color = { 0.6, 0.85, 1 } },
					})
				end
			end
		end
	end
	return list
end
ns.AddPinLayer({ key = "areaPOIs", label = "Points of interest", default = true }, AreaPOIPins)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local INTERACT = {
	MERCHANT_SHOW = "vendor",
	GOSSIP_SHOW = false,        -- only if the subtitle says what they are
	TRAINER_SHOW = "trainer",
	BANKFRAME_OPENED = "bank",
	AUCTION_HOUSE_SHOW = "ah",
	PET_STABLE_SHOW = "stable",
	CONFIRM_BINDER = "inn",
}

local events = CreateFrame("Frame")
for event in pairs(INTERACT) do pcall(events.RegisterEvent, events, event) end
for _, event in ipairs({ "MAIL_SHOW", "PLAYER_TARGET_CHANGED", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "AREA_POIS_UPDATED" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if INTERACT[event] ~= nil then
		OnInteract(INTERACT[event] or nil)
	elseif event == "MAIL_SHOW" then
		Remember("mailbox", nil, "Mailbox")
	elseif event == "PLAYER_TARGET_CHANGED" then
		local c = UnitExists("target") and not UnitIsPlayer("target") and UnitClassification("target")
		if c == "rare" or c == "rareelite" then Remember("rare", "target") end
	elseif event == "AREA_POIS_UPDATED" then
		ns.RefreshLayer("areaPOIs")
	else
		ns.RefreshLayer("vignettes")
	end
end)

ns.On("Loaded", function()
	MagicMapLandmarks = MagicMapLandmarks or {}
	store = MagicMapLandmarks
end)

ns.slash.landmarks = function()
	local counts, total = {}, 0
	for _, entries in pairs(store or {}) do
		for _, e in pairs(entries) do
			counts[e.kind] = (counts[e.kind] or 0) + 1
			total = total + 1
		end
	end
	local parts = {}
	for kind, n in pairs(counts) do parts[#parts + 1] = n .. " " .. (KINDS[kind] and KINDS[kind].label or kind) end
	table.sort(parts)
	ns.Print(total .. " landmarks learned" .. (total > 0 and (": " .. table.concat(parts, ", ")) or
		". Visit vendors, innkeepers, trainers, banks and mailboxes and they'll appear on the map."))
end

-- Probe (/mm blips): can we read the minimap's blips without the mouse?
-- Blizzard's minimap hover calls GameTooltip:SetMinimapMouseover(), which the
-- engine fills with the names under the hover point, and
-- Minimap:UpdateMouseoverAtPoint(x, y) moves that point. We don't know which
-- coordinates it expects, so scan the minimap once in each convention and
-- report what a hidden tooltip picked up, with offsets in yards from you.
local scanTip
local function ScanTooltipText()
	scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTip:SetMinimapMouseover()
	local lines = {}
	for i = 1, scanTip:NumLines() do
		local fs = _G["MagicMapBlipScanTextLeft" .. i]
		local text = fs and fs:GetText()
		if issecretvalue and text and issecretvalue(text) then return "<secret>" end
		if text and text ~= "" then lines[#lines + 1] = text end
	end
	scanTip:Hide()
	return #lines > 0 and table.concat(lines, " / ") or nil
end

ns.slash.blips = function()
	if not (Minimap and Minimap.UpdateMouseoverAtPoint and GameTooltip.SetMinimapMouseover) then
		ns.Print("blips: this client can't move the minimap's hover point")
		return
	end
	scanTip = scanTip or CreateFrame("GameTooltip", "MagicMapBlipScan", nil, "GameTooltipTemplate")
	local cx, cy = Minimap:GetCenter()
	local r = Minimap:GetWidth() / 2
	local scale = Minimap:GetEffectiveScale()
	local yardsPerPx = (C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius() or 0) / r
	local STEP = 4
	for _, mode in ipairs({ "offset", "ui", "screen" }) do
		local found, n = {}, 0
		for dy = -r, r, STEP do
			for dx = -r, r, STEP do
				if dx * dx + dy * dy <= r * r then
					local x, y = dx, dy
					if mode == "ui" then x, y = cx + dx, cy + dy
					elseif mode == "screen" then x, y = (cx + dx) * scale, (cy + dy) * scale end
					local ok = pcall(Minimap.UpdateMouseoverAtPoint, Minimap, x, y)
					local text = ok and ScanTooltipText()
					if text and not found[text] then
						found[text] = true
						n = n + 1
						if n <= 8 then
							ns.Print(string.format("  [%s] %s  (%+d, %+d yd)", mode, text, dx * yardsPerPx, dy * yardsPerPx))
						end
					end
				end
			end
		end
		ns.Print(string.format("blips [%s]: %d distinct", mode, n))
	end
	ns.Print(string.format("view radius %.0f yd, minimap %.0f px, rotating %s", yardsPerPx * r, r * 2,
		tostring(GetCVar and GetCVar("rotateMinimap"))))
end

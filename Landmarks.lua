-- Landmarks: things worth finding again.
--
--  * Rares: learned from vignettes (exact position) or from targeting one,
--    kept account-wide (MagicMapLandmarks) so every character benefits.
--  * Live vignettes: rares and treasures the game is currently showing.
--  * Area POIs the game defines for each zone.
--
-- Vendors, trainers, innkeepers and the like are Blizzard's minimap tracking:
-- it knows every one, where we'd only know those you've visited.

local ADDON, ns = ...
local store -- MagicMapLandmarks[instanceID][key] = { kind, name, sub, n, w, t }

local RARE_ICON, RARE_MIN_ZOOM = 137008, 60

local function NpcID(unit)
	local guid = UnitGUID(unit)
	if not guid then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- A rare at (north, west) in instance `inst`: the unit's, else yours.
local function Remember(unit, name, north, west, inst)
	if not store then return end
	if not north then
		local n, w, _, i = UnitPosition("player")
		if not n then return end -- instances hide your position
		north, west, inst = n, w, i
	end
	name = unit and UnitName(unit) or name
	local id = unit and NpcID(unit)
	-- One entry per NPC; one without an ID is keyed by its rounded position.
	local key = id and ("rare:" .. id)
		or ("rare:" .. math.floor(north / 8 + 0.5) .. ":" .. math.floor(west / 8 + 0.5))
	store[inst] = store[inst] or {}
	store[inst][key] = {
		kind = "rare", name = name,
		n = math.floor(north * 10 + 0.5) / 10, w = math.floor(west * 10 + 0.5) / 10,
		t = time(),
	}
	ns.RefreshLayer("rares")
end

---------------------------------------------------------------------------
-- Layers
---------------------------------------------------------------------------

local function RarePins(mapID)
	local list = {}
	for _, e in pairs(store and store[mapID] or {}) do
		local col, row = ns.WorldToTile(e.n, e.w)
		ns.PinAtTile(list, mapID, col, row, {
			size = 15, -- about the size Blizzard draws them on the minimap
			minZoom = RARE_MIN_ZOOM,
			title = e.name, lines = { "Rare", "|cff808080Seen here " .. date("%b %d", e.t) .. "|r" },
			icon = { texture = RARE_ICON },
		})
	end
	return list
end

ns.AddPinLayer({ key = "rares", label = "Rares you've seen", group = "people", default = true,
	tip = "Rare creatures where you last saw them, remembered between sessions." }, RarePins)

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
					Remember(nil, info.name, north, west, inst)
				end
			end
		end
	end
	return list
end
ns.AddPinLayer({ key = "vignettes", label = "Live rares & treasures", group = "people", default = true,
	tip = "Rares, treasures and events the game is showing near you right now." }, VignettePins)

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
ns.AddPinLayer({ key = "areaPOIs", label = "Points of interest", group = "places", default = true,
	tip = "Places the game marks in each zone." }, AreaPOIPins)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "AREA_POIS_UPDATED" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", ns.TimedEvents("landmarks", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		local c = UnitExists("target") and not UnitIsPlayer("target") and UnitClassification("target")
		if c == "rare" or c == "rareelite" then Remember("target") end
	elseif event == "AREA_POIS_UPDATED" then
		ns.RefreshLayer("areaPOIs")
	else
		ns.RefreshLayer("vignettes")
	end
end))

ns.On("Loaded", function()
	MagicMapLandmarks = MagicMapLandmarks or {}
	store = MagicMapLandmarks
	-- Vendors and the like an earlier version learned: Blizzard's tracking now.
	for _, entries in pairs(store) do
		for key, e in pairs(entries) do
			if e.kind ~= "rare" then entries[key] = nil end
		end
	end
end)

ns.slash.landmarks = function()
	local total = 0
	for _, entries in pairs(store or {}) do
		for _ in pairs(entries) do total = total + 1 end
	end
	ns.Print(total .. " rares remembered" .. (total > 0 and "" or ". Target one, or pass one the game shows, and it'll appear on the map."))
end

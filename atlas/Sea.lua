-- The sea (Data/Sea.lua): one ocean under the tiles. Per map its colours; per
-- tile whether it's land (the art as it is), open sea (no art), or coast: a
-- mask whose alpha is land (the art's MaskTexture) and whose grey is the
-- shelf (sea colour = deep + shelf * (shallow - deep)).

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

local function MapData(inst)
	local maps = MagicMap_Sea and MagicMap_Sea.maps
	return maps and maps[inst]
end

-- { shallow = { r, g, b }, deep = { r, g, b } }, or nil: no sea on this map.
function Atlas.Sea(inst)
	return MapData(inst)
end

-- "coast", maskPath | "open" | "land"; nil without sea on this map.
function Atlas.SeaTile(inst, key)
	local m = MapData(inst)
	if not m then return nil end
	if m.masks[key] then return "coast", MagicMap_Sea.dir .. inst .. "_" .. key .. ".tga" end
	if m.open[key] then return "open" end
	return "land"
end

-- The sea (Data/Sea.lua): the open sea beyond the tiles, continuing their own
-- painted water. Per map: tiling water textures (variants that fit beside any
-- other), a tint map (the sea's colour over and around the map), and per coast
-- tile the mask that fades its sides facing the sea. See tools/gen_sea.py for
-- how it is drawn.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas

local function MapData(inst)
	local maps = MagicMap_Sea and MagicMap_Sea.maps
	return maps and maps[inst]
end

-- { textures = { path, ... }, gain, tint = path, rect = { col0, row0, col1, row1 },
-- far = { r, g, b } (0..1: the tint beyond rect) }, or nil: no sea on this map.
local seas = {}
function Atlas.Sea(inst)
	local s = seas[inst]
	if s == nil then
		local m = MapData(inst)
		s = false
		if m then
			local dir = MagicMap_Sea.dir
			s = { textures = {}, gain = MagicMap_Sea.gain, tint = dir .. inst .. "_tint.tga", rect = m.tint,
				far = { m.far[1] / 255, m.far[2] / 255, m.far[3] / 255 } }
			for v = 0, MagicMap_Sea.variants - 1 do
				s.textures[v + 1] = dir .. inst .. "_ocean" .. v .. ".blp"
			end
		end
		seas[inst] = s
	end
	return s or nil
end

-- Which texture (1..#textures) the sea cell at col, row draws: a hash, so
-- neighbours differ and the choice holds still.
function Atlas.SeaVariant(col, row)
	local h = (col * 1619 + row * 31337 + 1013) % 65521
	h = (h * h + col * 7) % 65521
	return h % (MagicMap_Sea and MagicMap_Sea.variants or 1) + 1
end

-- The mask path for a coast tile's art (its sides facing the sea fade out), or
-- nil: not a coast tile (or no sea on this map).
function Atlas.SeaFeather(inst, key)
	local m = MapData(inst)
	local code = m and m.coast[key]
	return code and MagicMap_Sea.dir .. "feather_" .. code .. ".tga"
end

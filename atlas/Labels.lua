-- Map names as ranked anchors: what each name is, where it sits and how much
-- it matters (Data/Labels.lua, ranked offline by tools/gen_labels.py: tiers
-- continent, zone, town, subzone, poi). Static facts only; how big, when and
-- whether a name is drawn is the UI's to decide (it places them in rank order,
-- dropping ones that collide).

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)

local NONE = {}

local labels = {} -- inst -> anchors
-- { text, col, row, tier, rank, size?, areaID?, poiID? } sorted by rank (1 first).
-- size: the land named (continent, zone or subzone) as the side of a square, in tiles.
function Atlas.Labels(inst)
	local out = labels[inst]
	if out then return out end
	out = {}
	for i, r in ipairs(Data.Labels and Data.Labels[inst] or NONE) do
		out[i] = { text = r[1], col = r[2], row = r[3], tier = r[4], rank = i, size = r[5], areaID = r[6], poiID = r[7] }
	end
	labels[inst] = out
	return out
end

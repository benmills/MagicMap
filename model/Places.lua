-- Places, Known("places"): flight points, dungeon entrances, graveyards and area POIs. The game's
-- (obs.places: the map shown's, each asked of its continent's map and its zones') and Atlas's (flight
-- points, area POIs, dungeon and raid entrances, Data/Places.lua) for Focus's instance (else yours),
-- deduped:
--   across maps   a place the game marks on two maps (its continent's, a zone's) is one entry (its key)
--   live/static   a kind the game marks on an instance stands for Atlas's of that kind there (the spike
--                 drew the game's: Layers.lua:459-540, Landmarks.lua:119-143); Atlas's where it marks
--                 none, or before it's read there
-- place: its kind; live: the game's. icon: the art, as the client draws the kind (an atlas, or for an area
-- POI Data's POIIcons cell: { cell }); Atlas's entries get the client's own atlas names for their kind.

local _, ns = ...
local Model, Atlas = ns.Model, ns.Atlas

local NONE = {}
local FLIGHT = { A = "taxinode_alliance", H = "taxinode_horde" } -- a flight point's (C_TaxiMap's, by faction)

local places -- obs.places, the last handed
local marked = {} -- [inst][kind] = true: the game marks that kind there
local statics = {} -- [inst] = Atlas's places there, as entries (made once)
local list, rev, listInst, dirty = NONE, 0, nil, true

local function Entry(key, place, name, inst, col, row, live)
	return { key = key, kind = "places", place = place, name = name, live = live, pos = { inst = inst, col = col, row = row } }
end

local function Static(inst)
	local out = statics[inst]
	if out then return out end
	out = {}
	for _, f in ipairs(Atlas.FlightPoints(inst)) do
		local e = Entry("flight:" .. f.id, "flight", f.name, inst, f.col, f.row, false)
		e.faction = f.faction
		e.icon = { atlas = FLIGHT[f.faction] or "taxinode_neutral" }
		out[#out + 1] = e
	end
	for _, p in ipairs(Atlas.POIs(inst)) do
		local e = Entry("poi:" .. p.id, "poi", p.name, inst, p.col, p.row, false)
		e.text = p.description
		e.icon = { cell = p.icon }
		out[#out + 1] = e
	end
	for _, d in ipairs(Atlas.Dungeons(inst)) do
		if d.kind ~= "battleground" then
			local e = Entry("dungeon:" .. d.id, "dungeon", d.name, inst, d.col, d.row, false)
			e.icon = { atlas = d.kind == "raid" and "raid" or "dungeon" }
			out[#out + 1] = e
		end
	end
	statics[inst] = out
	return out
end

Model.Part(function(obs)
	local p = obs.places
	if p == nil or p == places then return end
	places, marked, dirty = p, {}, true
	for _, o in ipairs(p) do
		local m = marked[o.pos.inst]
		if not m then m = {}; marked[o.pos.inst] = m end
		m[o.kind] = true
	end
end)

Model.Kind("places", function()
	local f = Model.focus
	local inst = f and f.inst or Model.you.inst
	if inst ~= listInst then listInst, dirty = inst, true end
	if not dirty then return list, rev end
	dirty, rev, list = false, rev + 1, {}
	local keys = {}
	for _, o in ipairs(places or NONE) do
		if not keys[o.key] then
			keys[o.key] = true
			local e = Entry(o.key, o.kind, o.name, o.pos.inst, o.pos.col, o.pos.row, true)
			e.icon, e.text, e.faction, e.known = o.icon, o.text, o.faction, o.known
			list[#list + 1] = e
		end
	end
	local m = inst and marked[inst] or NONE
	for _, e in ipairs(inst and Static(inst) or NONE) do
		if not m[e.place] then list[#list + 1] = e end
	end
	return list, rev
end)

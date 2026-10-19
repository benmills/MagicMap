-- obs.tracking (types/observation.lua MM.ObsTracking[]), on change: Blizzard's minimap tracking types
-- (C_Minimap), each by its filter (Enum.MinimapTrackingFilter) or, a spell's (Find Herbs), its spell's
-- ID. Those our layers draw the same as (flight masters, quest POIs, points of interest:
-- MinimapTakeover.lua:236-237) are "duplicate": kept off while ours draw them (game/Tracking.lua), not
-- offered (GearMenu.lua:9-24). A type the client has no info for yet (at login) is left out till it has
-- (MinimapTakeover.lua:255). Read again on MINIMAP_UPDATE_TRACKING and at once after a tracking Command
-- (Game.TrackingChanged). Each compared with its last as it's read and kept if the same; a new list
-- only when one changed.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local F = Enum.MinimapTrackingFilter
local DUPLICATES = Game.DUPLICATES -- game/Tracking.lua: filter id -> our layer (MinimapTakeover.lua:237)

local list -- the last handed over
local dirty = true
local last = {} -- id -> its MM.ObsTracking

-- Read the tracking types again this observe.
function Game.TrackingChanged() dirty = true end
Runtime.On("MINIMAP_UPDATE_TRACKING", "game.tracking", Game.TrackingChanged)

-- A tracking type's id (MM.ObsTracking.id) from its filter (C_Minimap.GetTrackingFilter): the filter's, else its spell's.
local function ID(f)
	local id = f.filterID
	if id == nil or id == F.Unfiltered then return f.spellID end
	return id
end

-- Tracking type i's id.
function Game.TrackingID(i) return ID(C_Minimap.GetTrackingFilter(i)) end

Game.Part("tracking", function()
	if not dirty then return list end
	dirty = false
	local n, changed, seen = 0, list == nil, {}
	local out = {}
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		if info then
			local f = C_Minimap.GetTrackingFilter(i)
			local id, kind = ID(f), DUPLICATES[f.filterID] and "duplicate" or nil
			local t = last[id]
			if not (t and t.name == info.name and t.texture == info.texture and t.active == info.active and t.kind == kind) then
				t = { id = id, name = info.name, texture = info.texture, active = info.active, kind = kind }
			end
			n, seen[id] = n + 1, t
			out[n] = t
			if not changed and list[n] ~= t then changed = true end
		end
	end
	last = seen
	if not changed and n == #list then return list end
	list = out
	return list
end)

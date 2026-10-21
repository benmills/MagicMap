-- obs.interior (types/observation.lua MM.ObsInterior), on change: the building you're in and its room
-- (docs/decisions/0008-interiors.md; the prototype's Track and Floor, docs/evidence/indoors/addon/Test.lua).
-- In a building only while the Minimap draws its indoor map (obs.minimap.indoors) and some building's
-- floor mask covers you (Atlas.BuildingsAt, Atlas.RoomsAt); recomputed when you move a yard or your
-- subzone changes. Which room: the rooms under you; of those, the ones named like your subzone; the
-- room you were in, if still one of them; else the ones it has a portal to. One left: your room;
-- several: unsure (room nil, rooms the candidates kept). No mask under you: stay (a seam between
-- masks); AWAY s so: out (false). floor: your room's real floor (world height), unsure the highest
-- candidate's.
-- Each change, and the Minimap's indoors, is traced ("indoor") and printed under /mm indoor
-- (SavedGame.indoorDebug).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local AWAY = 2 -- s with no room's floor under you: out of the building (Test.lua's Track)
local YD = Atlas.TILE_YARDS -- yd a tile: each yard you move recomputes

local shown = false -- the obs.interior handed
local b, room, rooms -- the building (Atlas.Building), your room, the candidates kept
local away -- since when no mask has covered you
local qc, qr, sub, inst -- where it was last recomputed (yards), your subzone, the map
local indoors -- the Minimap's, as last noted

local function Has(list, v)
	for _, x in ipairs(list) do
		if x == v then return true end
	end
end
local function Pass(id, links)
	if links then return Has(links, id) end
	return sub ~= nil and b.rooms[id].area == sub -- no subzone: none (Test.lua's "")
end
-- c (a list of ours) narrowed in place to the rooms named like your subzone, or with links those in
-- it; left as it is if none are (Test.lua's Keep).
local function Keep(c, links)
	local n = #c
	for i = 1, n do
		if Pass(c[i], links) then break end
		if i == n then return end
	end
	local j = 0
	for i = 1, n do
		local id = c[i]
		c[i] = nil
		if Pass(id, links) then
			j = j + 1
			c[j] = id
		end
	end
end

-- The building you're in (the one you were in first) and the rooms whose mask covers you.
local function Under(i, col, row)
	if b and b.inst == i then
		local c = Atlas.RoomsAt(b, col, row)
		if #c > 0 then return b, c end
	end
	for _, key in ipairs(Atlas.BuildingsAt(i, col, row)) do
		local nb = Atlas.Building(i, key)
		local c = nb ~= b and Atlas.RoomsAt(nb, col, row)
		if c and #c > 0 then return nb, c end
	end
end

local function Floor()
	local f
	for _, id in ipairs(rooms) do
		local z = b.rooms[id].floor
		f = f and math.max(f, z) or z
	end
	return f
end

local function Say()
	local s = shown
	local r = s and s.room
	Game.Say(s and ("indoor: building %d, room %s (%s), candidates {%s}, floor %.0f; Minimap %s"):format(s.building,
		r or "?", r and b.rooms[r].area or sub or "", table.concat(s.rooms, ","), s.floor, indoors and "indoors" or "outdoors")
		or ("indoor: no building; Minimap %s"):format(indoors and "indoors" or "outdoors"))
end

local function Note()
	local s = shown
	local r = s and s.room
	Runtime.Trace("indoor", { building = s and s.building, room = r, area = r and b.rooms[r].area,
		rooms = s and table.concat(s.rooms, ",") or "", floor = s and s.floor, indoors = indoors })
	if Game.saved.indoorDebug then Say() end
end

local function Out()
	qc, away = nil, nil
	if not b then return end
	b, room, rooms = nil, nil, nil
	if shown then shown = false; Note() end
end

local function Track(y, t)
	local nb, c = Under(y.inst, y.col, y.row)
	if not nb then
		away = away or t
		return
	end
	away = nil
	if nb ~= b then b, room = nb, nil end
	Keep(c)
	if room and Has(c, room) then
		for i = #c, 1, -1 do c[i] = nil end
		c[1] = room
	elseif room then
		Keep(c, b.rooms[room].links)
	end
	rooms, room = c, #c == 1 and c[1] or nil
	local s, f = shown, Floor()
	if s and s.building == b.key and s.room == room and s.floor == f and #s.rooms == #c then
		local same = true
		for i = 1, #c do same = same and s.rooms[i] == c[i] end
		if same then return end
	end
	shown = { inst = b.inst, building = b.key, room = room, rooms = c, floor = f }
	Note()
end

Game.Part("interior", function(obs)
	local y, m = obs.you, obs.minimap.indoors
	if m ~= indoors then
		indoors = m
		Note()
	end
	if not (m and y.col) then
		Out()
		return shown
	end
	local c, r = math.floor(y.col * YD), math.floor(y.row * YD)
	if c ~= qc or r ~= qr or y.subzone ~= sub or y.inst ~= inst then
		qc, qr, sub, inst = c, r, y.subzone, y.inst
		Track(y, obs.t)
	end
	if away and b and obs.t - away > AWAY then Out() end
	return shown
end)

-- IndoorArt.lua:178-185.
Game.Slash("indoor", "report the building and room you're in as they change; again to stop", function()
	local s = Game.saved
	s.indoorDebug = not s.indoorDebug or nil
	Game.Say(s.indoorDebug and "indoor: reporting each change of building and room; /mm indoor to stop" or "indoor: quiet")
	if s.indoorDebug then Say() end
end)

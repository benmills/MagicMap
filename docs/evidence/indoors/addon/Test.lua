-- A throwaway test: Ironforge's indoor minimap pictures, placed on the terrain tiles by the
-- building's placement, in a window centred on you. /mmit toggles it; /mmit help for the rest.
local _, ns = ...
local TILE = 1600 / 3
local SIZE = 420

local f = CreateFrame("Frame", "MagicMapIndoorTestFrame", UIParent, "BackdropTemplate")
f:SetSize(SIZE, SIZE)
f:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
f:SetClipsChildren(true)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
f:Hide()
local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
bg:SetAllPoints()
bg:SetColorTexture(0.06, 0.05, 0.04, 1)

local opt = { k = 1.5, dim = 0.35, terrain = true, pics = true, zlo = -1e9, zhi = 1e9, cull = 22 } -- cull: tuned in Ironforge
local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
info:SetPoint("TOPLEFT", 8, -8)
info:SetJustifyH("LEFT")

-- Terrain tiles: axis-aligned squares.
local tiles = {}
for i, t in ipairs(ns.tiles) do
	local tex = f:CreateTexture(nil, "BACKGROUND", nil, 0)
	tex:SetTexture(t[1])
	tiles[i] = { tex = tex, x = t[2] * TILE, y = t[3] * TILE }
end

-- Pictures: each a parallelogram o + u*U + v*V; drawn as the axis-aligned box around it, with
-- the box's corners' texture coordinates solved for, and transparent outside the picture.
local pics = {}
for i, p in ipairs(ns.pics) do
	local fid, ox, oy, ux, uy, vx, vy, zmin, room = unpack(p)
	local sub = math.max(-8, math.min(6, math.floor((zmin + 140) / 16) - 8)) -- by floor; 7: the room you're in
	local tex = f:CreateTexture(nil, "ARTWORK", nil, sub)
	tex:SetTexture(fid, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	local xs = { ox, ox + ux, ox + vx, ox + ux + vx }
	local ys = { oy, oy + uy, oy + vy, oy + uy + vy }
	local x0, x1 = math.min(unpack(xs)), math.max(unpack(xs))
	local y0, y1 = math.min(unpack(ys)), math.max(unpack(ys))
	local det = ux * vy - vx * uy
	local function UV(x, y)
		local dx, dy = x - ox, y - oy
		return (dx * vy - vx * dy) / det, (ux * dy - dx * uy) / det
	end
	local ulu, ulv = UV(x0, y0)
	local llu, llv = UV(x0, y1)
	local uru, urv = UV(x1, y0)
	local lru, lrv = UV(x1, y1)
	tex:SetTexCoord(ulu, ulv, llu, llv, uru, urv, lru, lrv)
	pics[i] = { tex = tex, x0 = x0, y0 = y0, w = x1 - x0, h = y1 - y0, zmin = zmin, room = room, fid = fid, sub = sub }
end

local dot = f:CreateTexture(nil, "OVERLAY")
dot:SetColorTexture(1, 0.85, 0.1, 1)
dot:SetSize(7, 7)
dot:SetPoint("CENTER")
local nose = f:CreateLine(nil, "OVERLAY")
nose:SetColorTexture(1, 0.85, 0.1, 1)
nose:SetThickness(2)
nose:SetStartPoint("CENTER", f, 0, 0)

-- Which room you're in: the rooms whose floor covers your spot (Rooms.lua's 4-yd masks, in the
-- building's own coordinates); of those, the ones named like your subzone; then the one you were
-- in, else one it has a portal to. Still several: unknown (room nil, `here` the candidates).
-- (NEW_WMO_CHUNK fires per building, not per room: only counted.)
local room, crossed, events = nil, false, 0
local narrowed = {}
local function Candidates(cx, cy)
	local w = ns.wmo
	local dx, dz = cx - w.x, cy - w.z
	local lx = dx * math.cos(w.t) - dz * math.sin(w.t)
	local ly = -(dx * math.sin(w.t) + dz * math.cos(w.t))
	local out = {}
	for id, r in pairs(ns.rooms) do
		local c, rr = math.floor((lx - r[3]) / 4), math.floor((ly - r[4]) / 4)
		if c >= 0 and c < r[5] and rr >= 0 and rr < r[6] and r[7]:byte(rr * r[5] + c + 1) == 49 then
			out[#out + 1] = id
		end
	end
	table.sort(out)
	return out
end
local function Has(list, v)
	for _, x in ipairs(list) do if x == v then return true end end
end
local function Keep(c, test)
	local out = {}
	for _, id in ipairs(c) do if test(id) then out[#out + 1] = id end end
	return #out > 0 and out or c
end
local away -- since when no room's floor has covered you
local function Track(c)
	if #c == 0 then -- a gap between masks: stay; out of the building a while: no room
		away = away or GetTime()
		if GetTime() - away > 2 and (room or #narrowed > 0) then
			room, narrowed = nil, {}
			if opt.debug then print("mmit: out of the building") end
		end
		return
	end
	away = nil
	local was = room
	local sub = GetSubZoneText() or ""
	c = Keep(c, function(id) return ns.roomArea[id] == sub end)
	if room and Has(c, room) then
		c = { room }
	elseif room then
		local links = ns.roomLinks[room] or {}
		c = Keep(c, function(id) return Has(links, id) end)
	end
	narrowed = c
	room = #c == 1 and c[1] or nil
	crossed = false
	if opt.debug and room ~= was then
		print(("mmit: room %s (%s)"):format(room and tostring(room) or ("? {" .. table.concat(c, ",") .. "}"),
			room and ns.roomArea[room] or GetSubZoneText() or ""))
	end
end
-- The floor culling measures from: your room's, or unsure, the highest candidate's (never hides
-- the room you may be in).
local function Floor()
	local f
	for _, id in ipairs(narrowed) do
		local z = ns.rooms[id][1]
		f = f and math.max(f, z) or z
	end
	return f
end
local ev = CreateFrame("Frame")
ev:RegisterEvent("NEW_WMO_CHUNK")
ev:RegisterEvent("ZONE_CHANGED_INDOORS")
ev:SetScript("OnEvent", function(_, e)
	if e == "NEW_WMO_CHUNK" then crossed, events = true, events + 1 end
	if opt.debug then
		local north, west = UnitPosition("player")
		local c = north and Candidates(32 * TILE - west, 32 * TILE - north) or {}
		print(("mmit: %s, rooms here {%s}, was in %s, subzone %s"):format(e, table.concat(c, ","),
			tostring(room), GetSubZoneText() or ""))
	end
end)

local function Place(tex, x, y, w, h, cx, cy)
	local k = opt.k
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", f, "CENTER", (x - cx) * k, -(y - cy) * k)
	tex:SetSize(math.max(1, w * k), math.max(1, h * k))
end

local acc = 0
f:SetScript("OnUpdate", function(_, e)
	acc = acc + e
	if acc < 0.05 then return end
	acc = 0
	local north, west = UnitPosition("player")
	if not north then
		info:SetText("no position here")
		return
	end
	local cx, cy = 32 * TILE - west, 32 * TILE - north
	for _, t in ipairs(tiles) do
		t.tex:SetShown(opt.terrain)
		t.tex:SetVertexColor(opt.dim, opt.dim, opt.dim)
		if opt.terrain then Place(t.tex, t.x, t.y, TILE, TILE, cx, cy) end
	end
	local here = Candidates(cx, cy)
	Track(here)
	local floor = Floor()
	for _, p in ipairs(pics) do
		local mine = Has(narrowed, p.room)
		if p.mine ~= mine then -- the room you're in (or may be) over every other
			p.mine = mine
			p.tex:SetDrawLayer("ARTWORK", mine and 7 or p.sub)
		end
		local on = opt.pics and p.zmin >= opt.zlo and p.zmin <= opt.zhi
		if on and opt.cull and floor then on = p.zmin <= floor + opt.cull end
		if on and opt.only then on = Has(narrowed, p.room) end
		p.tex:SetShown(on)
		if on then Place(p.tex, p.x0, p.y0, p.w, p.h, cx, cy) end
	end
	local face = GetPlayerFacing() or 0
	nose:SetEndPoint("CENTER", f, -math.sin(face) * 14, math.cos(face) * 14)
	info:SetText(("col %.3f row %.3f  %s\n%s  zoom %.2f px/yd\nroom %s (floor %s)  here {%s}  crossings %d%s"):format(
		cx / TILE, cy / TILE, IsIndoors() and "indoors" or "outdoors", GetSubZoneText() or "", opt.k,
		room and ("%d %s"):format(room, ns.roomArea[room] or "") or ("? {" .. table.concat(narrowed, ",") .. "}"), floor and ("%.0f"):format(floor) or "?", table.concat(here, ","), events,
		opt.cull and (" cull +%d"):format(opt.cull) or ""))
end)

f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function(_, d)
	opt.k = math.max(0.2, math.min(8, opt.k * (d > 0 and 1.25 or 0.8)))
end)

SLASH_MAGICMAPINDOORTEST1 = "/mmit"
SlashCmdList.MAGICMAPINDOORTEST = function(msg)
	local cmd, a, b = strsplit(" ", msg or "")
	if cmd == "" then
		f:SetShown(not f:IsShown())
	elseif cmd == "terrain" then
		opt.terrain = not opt.terrain
	elseif cmd == "pics" then
		opt.pics = not opt.pics
	elseif cmd == "dim" then
		opt.dim = tonumber(a) or 0.35
	elseif cmd == "z" then
		opt.zlo, opt.zhi = tonumber(a) or -1e9, tonumber(b) or 1e9
	elseif cmd == "cull" then
		opt.cull = (tonumber(a) or (not opt.cull and 22)) or nil
		print("mmit: hide rooms whose floor is over yours by more than", opt.cull or "(off)")
	elseif cmd == "only" then
		opt.only = not opt.only
	elseif cmd == "debug" then
		opt.debug = not opt.debug
		print("mmit: printing room crossings", opt.debug and "on" or "off")
	elseif cmd == "size" then
		local s = tonumber(a) or SIZE
		f:SetSize(s, s)
	else
		print("/mmit: toggle | terrain | pics | dim <0-1> | z <lo> <hi> (rooms by floor height; z alone: all) | size <px> | cull [yd] (hide rooms above yours) | only (just your room) | debug (print crossings); wheel zooms, drag moves")
	end
end

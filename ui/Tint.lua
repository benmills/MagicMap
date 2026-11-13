-- The time-of-day tint (a prototype): WoW Forever tints its minimap with the game's outdoor light; so do we.
-- Where you stand, the lights around you (Data/Light.lua: Light.db2's, blended by their falloff over the map's
-- default) give a colour through the day (LightData.db2's direct, ambient and Forever's own); at the server's time
-- it makes a multiply over the ground (the tiles, repaints and ocean), under the buildings and the pins:
--   tint = ((1 - mix) + mix * hue / max(hue)) * (1 - dark * (1 - lum(bright) / its day's brightest))
-- Only on the small map, on your map, outdoors. /mm tint [on | off | hue <src> | mix <k> | dark <d> |
-- bright <src> | time <HH:MM | off> | big | reset], src: direct, ambient or forever; the knobs kept in UI.saved.tint.

local _, ns = ...
local UI, Atlas, Runtime, Model = ns.UI, ns.Atlas, ns.Runtime, ns.Model

local Tint = {}
UI.Tint = Tint

local DEFAULTS = { on = true, hue = "direct", mix = 0.3, dark = 0.25, bright = "direct", big = false }
local SRC = { direct = 2, ambient = 3, forever = 4 } -- a key's fields after its time

local tex = UI.Sea.frame:CreateTexture(nil, "OVERLAY") -- over the ocean (its ARTWORK), its frame over the tiles
tex:SetAllPoints(UI.Window.view)
tex:SetColorTexture(1, 1, 1, 1)
tex:SetBlendMode("MOD")
tex:Hide()

local function Knob(k)
	local t = UI.saved and UI.saved.tint
	local v = t and t[k]
	if v == nil then v = DEFAULTS[k] end
	return v
end
local function SetKnob(k, v)
	local t = UI.saved.tint or {}
	if v == DEFAULTS[k] then t[k] = nil else t[k] = v end
	UI.saved.tint = next(t) and t or nil
end

local function RGB(c) return math.floor(c / 65536) % 256 / 255, math.floor(c / 256) % 256 / 255, c % 256 / 255 end
local function Lum(r, g, b) return 0.2126 * r + 0.7152 * g + 0.0722 * b end

-- A params' colour (field f) at time t (half-minutes), between its keys round the day.
local function At(day, f, t)
	local n = #day / 4
	if n == 0 then return 1, 1, 1 end
	local i = n -- the last key at or before t (else the day's last, wrapping)
	for k = 1, n do
		if day[(k - 1) * 4 + 1] <= t then i = k end
	end
	local j = i % n + 1
	local t0, t1 = day[(i - 1) * 4 + 1], day[(j - 1) * 4 + 1]
	local span = (t1 - t0) % 2880
	local u = span > 0 and ((t - t0) % 2880) / span or 0 -- /: never 0 (span > 0)
	local r0, g0, b0 = RGB(day[(i - 1) * 4 + f])
	local r1, g1, b1 = RGB(day[(j - 1) * 4 + f])
	return r0 + (r1 - r0) * u, g0 + (g1 - g0) * u, b0 + (b1 - b0) * u
end

local brightest = {} -- [params .. f]: the day's brightest key
local function Brightest(pid, day, f)
	local k = pid .. ":" .. f
	if not brightest[k] then
		local m = 0
		for i = 1, #day, 4 do m = math.max(m, Lum(RGB(day[i + f - 1]))) end
		brightest[k] = m
	end
	return brightest[k]
end

-- The lights at (col, row) on inst: { { params, weight }, ... }, the map's default first, weights over it.
local function Here(inst, col, row)
	local m = Atlas.Light(inst)
	if not m then return nil end
	local out = { { m.default, 1 } }
	local near = {}
	for _, l in ipairs(m.lights) do
		local d = math.sqrt((col - l[1]) ^ 2 + (row - l[2]) ^ 2)
		if d < l[4] then
			local w = d <= l[3] and 1 or (l[4] - d) / math.max(l[4] - l[3], 1e-6) -- /: never 0 (max)
			near[#near + 1] = { l[5], w, l[4] }
		end
	end
	table.sort(near, function(a, b) return a[3] > b[3] end) -- the wide first, the small over them
	for _, n in ipairs(near) do out[#out + 1] = n end
	return out
end

-- A source's colour and its brightness (0..1 of its day's brightest) over the lights, at t.
local function Mix(lights, f, t)
	local r, g, b, l = 1, 1, 1, 1
	for i, p in ipairs(lights) do
		local day = p[1] and Atlas.LightDay(p[1])
		if day then
			local pr, pg, pb = At(day, f, t)
			local top = Brightest(p[1], day, f)
			local pl = top > 0 and Lum(pr, pg, pb) / top or 1 -- /: never 0 (top > 0)
			local w = i == 1 and 1 or p[2]
			r, g, b, l = r + (pr - r) * w, g + (pg - g) * w, b + (pb - b) * w, l + (pl - l) * w
		end
	end
	return r, g, b, l
end

local last -- what /mm tint reports: { inst, col, row, t, lights, hue, lum, tint }

-- The time it lights for (half-minutes): the override, else the server's.
local function Now()
	local o = Knob("time")
	if o then return o end
	local c = Model.clock
	return c and ((c.sh or 0) * 60 + (c.sm or 0)) * 2 or 1440
end

function Tint.Compute(inst, col, row, t)
	local lights = Here(inst, col, row)
	if not lights then return nil end
	local hr, hg, hb = Mix(lights, SRC[Knob("hue")] or 2, t)
	local _, _, _, lum = Mix(lights, SRC[Knob("bright")] or 2, t)
	local top = math.max(hr, hg, hb)
	local k, dark = Knob("mix"), Knob("dark")
	local s = 1 - dark * (1 - math.min(lum, 1))
	local r, g, b
	if top > 0 then
		r, g, b = ((1 - k) + k * hr / top) * s, ((1 - k) + k * hg / top) * s, ((1 - k) + k * hb / top) * s -- /: never 0 (top > 0)
	else
		r, g, b = s, s, s
	end
	last = { inst = inst, col = col, row = row, t = t, lights = lights, hue = { hr, hg, hb }, lum = lum, tint = { r, g, b } }
	return r, g, b
end

local shown
local function Update()
	local you, cam = Model.you, UI.Camera
	local ok = Knob("on") and you and you.col and not you.stale and cam.inst == you.inst and not Model.interior
		and (Knob("big") or UI.BigMap.big ~= true) and not UI.Window.Blank()
	local r, g, b
	if ok then r, g, b = Tint.Compute(you.inst, you.col, you.row, Now()) end
	if not r then
		if shown then tex:Hide(); shown = nil end
		return
	end
	local key = string.format("%.3f %.3f %.3f", r, g, b)
	if key ~= shown then
		tex:SetVertexColor(r, g, b, 1)
		tex:Show()
		shown = key
	end
end
Runtime.Every(1, "map: tint", Update)
function Tint.Shown() return shown ~= nil end -- (the tests)
Tint.tex = tex

local function Say(msg) print("|cffffd100MagicMap|r: " .. msg) end
local function Clock(t) return string.format("%02d:%02d", math.floor(t / 120), math.floor(t % 120 / 2)) end
local function Report()
	Say(string.format("tint %s: hue %s, mix %.2f, dark %.2f, bright %s%s%s", Knob("on") and "on" or "off", Knob("hue"),
		Knob("mix"), Knob("dark"), Knob("bright"), Knob("time") and ", time " .. Clock(Knob("time")) or "",
		Knob("big") and ", big map too" or ""))
	if not last then return Say("no light here yet (indoors, another map, or no data)") end
	local ids = {}
	for _, p in ipairs(last.lights) do ids[#ids + 1] = string.format("%s x%.2f", tostring(p[1]), p[2]) end
	Say(string.format("at %s on %d (%.2f, %.2f): lights %s", Clock(last.t), last.inst, last.col, last.row, table.concat(ids, " ")))
	Say(string.format("hue %d,%d,%d  brightness %.2f  ->  tint %.2f, %.2f, %.2f%s", last.hue[1] * 255 + 0.5,
		last.hue[2] * 255 + 0.5, last.hue[3] * 255 + 0.5, last.lum, last.tint[1], last.tint[2], last.tint[3],
		shown and "" or " (not shown)"))
end

function Tint.Command(args)
	local k, v = strtrim(args or ""):lower():match("^(%S*)%s*(.-)$")
	if k == "on" or k == "off" then SetKnob("on", k == "on")
	elseif (k == "hue" or k == "bright") and SRC[v] then SetKnob(k, v)
	elseif (k == "mix" or k == "dark") and tonumber(v) then SetKnob(k, math.max(0, math.min(1, tonumber(v))))
	elseif k == "time" and v == "off" then SetKnob("time", nil)
	elseif k == "time" and v:match("^%d+:%d+$") then
		local h, m = v:match("^(%d+):(%d+)$")
		SetKnob("time", (tonumber(h) % 24 * 60 + tonumber(m) % 60) * 2)
	elseif k == "big" then SetKnob("big", not Knob("big"))
	elseif k == "reset" then UI.saved.tint = nil
	elseif k ~= "" then
		return Say("/mm tint [on | off | hue direct|ambient|forever | mix 0-1 | dark 0-1 | bright direct|ambient|forever | time HH:MM|off | big | reset]")
	end
	Update()
	Report()
end

ns.Game.Command({ kind = "slash", name = "tint", help = "the time-of-day tint: what it is here and now, and its knobs (tint help)",
	fn = Tint.Command })

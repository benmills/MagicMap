-- Telemetry (docs/telemetry.md): sessions, errors with stacks, and marks
-- (state + Runtime's trace ring + the motion ring) in MagicMapAtlasDB.telemetry,
-- written to disk on /reload or logout for tools/telemetry.py.
-- Errors come from Runtime.onError (every Wrap) and the global error handler
-- (anything else whose stack is in our folder). An error's first occurrence
-- in a session traces "error" and takes an "error" mark; a taint's
-- (ADDON_ACTION_BLOCKED/FORBIDDEN naming us) traces "taint" and takes a "taint" mark,
-- and the sensor's first "sensor" trace of each kind (game/Blips.lua) a "sensor" mark.
-- Each session's perf (Runtime.FrameStats, errors, load, memory after a full
-- collect: docs/runtime.md) is written at logout and with each mark, with the
-- bench (game/Bench.lua) if one ran. Every trace passes here too (Runtime.onTrace): the
-- kinds that must stay empty are kept past the ring, layouts, swaps and sweeps counted.

local ADDON, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local SESSIONS, ERRORS, MARKS, ZONES, KEPT = 10, 50, 20, 30, 50
local MSG, STACK = 300, 2000 -- chars kept
local MOTION = 120 -- frames of camera and you in each mark
local LOAD_KB_AT = 10 -- s after login: past its grace (5 s, game/Game.lua) and the world streaming in
local KEEP = { taint = true, art = true, sensor = true } -- trace kinds kept for the session (each a bug)
local STATS = { layout = true, swap = true, blips = true } -- counted per layer: n and each number's max
local OURS = "AddOns[/\\]" .. ADDON .. "[/\\]"

local version = C_AddOns.GetAddOnMetadata(ADDON, "Version")
local db, session
local errors, loginAt = 0, nil -- this session's errors; GetTime() at login
local pending = {} -- errors before SavedVariables load
local seen = {} -- error keys this session
local kbLoad, kbOut -- our KB after a full collect: past the login grace, at logout

local function R(v, n) return v and math.floor(v * n + 0.5) / n end -- /: never 0 (n: a literal at each call)
local NONE = {}
local boot = Runtime.boot
local function Ms() return R(debugprofilestop() - (boot.login and boot.login.t or boot.t0), 10) end -- as Trace's

local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end

-- View as Game's apply step last read it (types/view.lua: Game reads View only there): the
-- motion ring's camera, shot stamps, and marks' diag (called only for a mark, ADR 0003).
local applied = { inst = 0, big = false }

local function State()
	local you = Game.obs.you
	local diag = applied.diag and applied.diag() or {}
	local map, layers = diag.map, diag.layers
	return {
		you = { inst = you.inst, col = you.col, row = you.row, facing = you.facing },
		zone = GetZoneText(), subzone = GetSubZoneText(), map = map, layers = layers,
	}
end

-- Our memory alone, garbage collected first (else ~a third is garbage: docs/runtime.md). Slow: a frame of ~100 ms.
local function OurKB()
	collectgarbage("collect")
	UpdateAddOnMemoryUsage()
	return math.floor(GetAddOnMemoryUsage(ADDON))
end

-- session.perf: Runtime.FrameStats() (alloc, gaps, ledger, byState with it) plus errors, errors an
-- hour, load ms, our KB at load and logout; session.bench[build]: the last /mma bench.
local function Perf()
	local p = Runtime.FrameStats()
	local hours = math.max((GetTime() - (loginAt or 0)) / 3600, 1 / 60) -- at least a minute
	local perHour = errors / hours -- /: never 0 (hours: at least a minute)
	p.errors, p.errorsPerHour, p.loadMs = errors, math.floor(perHour * 10 + 0.5) / 10, session.boot.loadMs
	p.ourKBLoad, p.ourKB = kbLoad, kbOut
	session.perf, session.frames = p, Runtime.frames
	local bench = Game.Bench.result
	if bench then session.bench[bench.build] = Copy(bench) end
end

-- The motion ring: the camera (View.camera) and you each frame, in preallocated slots (no garbage).
local motion, at = {}, 0
for i = 1, MOTION do motion[i] = {} end

local function Motion() -- oldest first
	local out = {}
	for i = 1, MOTION do
		local m = motion[(at + i - 1) % MOTION + 1]
		if m.f then
			out[#out + 1] = { f = m.f, ms = m.ms, cx = R(m.cx, 1e4), cy = R(m.cy, 1e4), zoom = R(m.zoom, 100),
				px = R(m.px, 1e4), py = R(m.py, 1e4), w = R(m.w, 10), h = R(m.h, 10) }
		end
	end
	return out
end

local function Mark(kind, note, stamp, shot)
	Perf()
	local marks = db.marks
	marks[#marks + 1] = {
		kind = kind, note = note, t = time(), stamp = stamp, session = session.id, version = version,
		frame = Runtime.frames, state = State(), trace = Runtime.TraceCopy(), motion = Motion(), shot = shot,
	}
	if #marks > MARKS then table.remove(marks, 1) end
end

local function Record(name, msg, stack)
	msg = tostring(msg)
	if not db then pending[#pending + 1] = { name, msg, stack }; return end
	errors = errors + 1
	local key = name .. ": " .. msg:match("^[^\n]*"):sub(1, MSG)
	local kept, t = db.errors, time()
	local e = kept[key]
	if not e then
		local n, oldest = 0, nil
		for k, o in pairs(kept) do
			n = n + 1
			if not oldest or (o.last or 0) < (kept[oldest].last or 0) then oldest = k end
		end
		if n >= ERRORS then kept[oldest] = nil end
		e = { name = name, msg = msg:sub(1, MSG), count = 0, first = t }
		kept[key] = e
	end
	e.count, e.last = e.count + 1, t
	if seen[key] then return end
	seen[key] = true
	e.stack, e.version, e.session = stack and stack:sub(1, STACK), version, session.id
	Runtime.Trace("error", key)
	Mark("error", key)
end

Runtime.onError = Record

-- Everything else's errors: ours (by stack) recorded; never re-entered (an error while
-- recording one is dropped), and the previous handler always runs.
local previous, inHandler = geterrorhandler(), false
seterrorhandler(function(msg, ...)
	if not inHandler then
		inHandler = true
		local stack = debugstack(2)
		if (tostring(msg) .. stack):find(OURS) then pcall(Record, "lua", msg, stack) end
		inHandler = false
	end
	return previous(msg, ...)
end)

-- Every trace passes here too (Runtime.onTrace, after the ring has it): KEEP kinds go to
-- session.kept (the ring forgets them), STATS kinds to session.stats["<kind> <layer>"] =
-- { n, <field> = max |value| }, a swap's `lag` being frames since its layer's last layout end.
local ends = {} -- [layer] = Runtime.frames at its last layout end
local sensed = {} -- sensor events marked this session: the first of each kind (as a taint's per function)
local Keep = Runtime.Wrap("telemetry: trace", function(kind, d)
	if KEEP[kind] then
		local kept = session.kept
		if #kept < KEPT then kept[#kept + 1] = { f = Runtime.frames, ms = Ms(), k = kind, d = d } end
		if kind == "sensor" and not sensed[d.e] then
			sensed[d.e] = true
			Mark("sensor", d.e .. " " .. (d.why or d.px))
		end
	end
	if not (STATS[kind] and type(d) == "table") or (kind == "layout" and d.e ~= "end") then return end
	local key = d.layer and kind .. " " .. d.layer or kind
	local s = session.stats[key]
	if not s then s = { n = 0 }; session.stats[key] = s end
	s.n = s.n + 1
	for k, v in pairs(d) do
		if type(v) == "number" and not (s[k] and s[k] >= math.abs(v)) then s[k] = math.abs(v) end -- (a 0 is kept: recorded)
	end
	if kind == "layout" then ends[d.layer] = Runtime.frames end
	if kind == "swap" and ends[d.layer] then s.lag = math.max(s.lag or 0, Runtime.frames - ends[d.layer]) end
end, false)

Game.Load("telemetry", function(saved)
	local last = saved.sessions[#saved.sessions]
	local v, build = GetBuildInfo()
	session = {
		id = (tonumber(type(last) == "table" and last.id) or 0) + 1, version = version, build = v .. "." .. build,
		started = time(), boot = { loadMs = boot.loaded.t - boot.t0, loadKB = boot.loaded.mem - boot.mem0 }, frames = 0,
		zones = {}, kept = {}, stats = {}, bench = {},
	}
	db = saved
	db.sessions[#db.sessions + 1] = session
	if #db.sessions > SESSIONS then table.remove(db.sessions, 1) end
	Runtime.onTrace = Keep -- (from here: the session holds what it keeps)
	for _, p in ipairs(pending) do Record(p[1], p[2], p[3]) end
	pending = nil
end, { version = 1, defaults = { sessions = {}, errors = {}, marks = {} } })

local function Zone()
	local zone, zones = GetZoneText(), session.zones
	Runtime.Trace("zone", zone)
	if zones[#zones] ~= zone and #zones < ZONES then zones[#zones + 1] = zone end
end

local loadAt -- GetTime() to read ourKBLoad at
Runtime.On("PLAYER_LOGIN", "telemetry.login", function()
	session.boot.loginMs = boot.login.t - boot.t0
	loginAt, loadAt = GetTime(), GetTime() + LOAD_KB_AT
	Runtime.Trace("login", version)
	Zone()
end)
Runtime.On("ZONE_CHANGED_NEW_AREA", "telemetry.zone", Zone)
Runtime.On("PLAYER_LOGOUT", "telemetry.logout", function() -- also /reload
	kbOut = OurKB()
	Perf()
end)

-- Each frame, from View (Game.Apply): what shots stamp and the motion ring (View.camera is
-- OPEN: none, no row); once, ourKBLoad, its full collect in a grace ("gc": not an overrun).
Game.Apply("telemetry", function(view)
	local cam, place, you = view.camera, view.window.place, Game.obs.you
	local c, p = cam or NONE, place or NONE
	applied.inst, applied.big, applied.diag, applied.left, applied.top = view.inst, view.window.big, view.diag, p.left, p.top
	applied.cx, applied.cy, applied.zoom, applied.w, applied.h = c.cx, c.cy, c.zoom, c.w, c.h
	if cam then
		at = at % MOTION + 1
		local m = motion[at]
		m.f, m.ms, m.cx, m.cy, m.zoom, m.w, m.h = Runtime.frames, Ms(), cam.cx, cam.cy, cam.zoom, cam.w, cam.h
		m.px, m.py = you.col, you.row
	end
	if loadAt and GetTime() >= loadAt then
		loadAt = nil
		Runtime.Grace("gc", 0.1)
		kbLoad = OurKB()
	end
end)

-- Taint (spike-bugs K2): the client blocked a protected call and blamed us. The first per function takes a mark.
local tainted = {}
local function Taint(event, addon, fn)
	if addon ~= ADDON then return end
	local d = { e = event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden", fn = tostring(fn) }
	Runtime.Trace("taint", d)
	if tainted[d.fn] then return end
	tainted[d.fn] = true
	Mark("taint", d.e .. " " .. d.fn)
end
Runtime.On("ADDON_ACTION_BLOCKED", "telemetry.taint", Taint)
Runtime.On("ADDON_ACTION_FORBIDDEN", "telemetry.taint", Taint)

-- Shots: stamped when asked (what the screenshot shows), marked on SCREENSHOT_SUCCEEDED;
-- stamp as in WoWScrnShot_<stamp>.jpg. Chat answers by id, after the picture: on the client's
-- SCREENSHOT_SUCCEEDED or _FAILED (Forever's Blizzard_ActionStatus shows both), or when neither
-- came in ANSWER_S (none taken). The M0 sessions have no shot, `shot` trace or screenshot file,
-- and nothing there said either way.
local ANSWER_S = 5
local shot -- the pending /mma shot: { id, note, at = its stamp, wait = its timer }

local function Answer(said)
	Runtime.Cancel(shot.wait)
	Game.Print("shot " .. shot.id .. ": " .. said)
	shot = nil
end

Runtime.On("SCREENSHOT_SUCCEEDED", "telemetry.shot", function()
	if not shot then return end -- not ours (Print Screen)
	local stamp = date("%m%d%y_%H%M%S")
	Runtime.Trace("shot", shot.note)
	Mark("shot", shot.note, stamp, shot.at)
	Answer("WoWScrnShot_" .. stamp .. ", marked")
end)
Runtime.On("SCREENSHOT_FAILED", "telemetry.shot failed", function()
	if not shot then return end
	Runtime.Trace("shot", "failed " .. shot.note)
	Answer("the client took no screenshot (no mark)")
end)

Game.Slash("mark", "<note>: save state and the recent trace (written on /reload)", function(note)
	note = note ~= "" and note or nil
	Runtime.Trace("mark", note)
	Mark("mark", note)
	Game.Print("marked")
end)

Game.Slash("shot", "<id> [note]: a screenshot, and a mark matched to it (docs/playtest.md shot ids)", function(note)
	local id = note:match("^%S+")
	if not id then return Game.Print("shot: the id first (docs/playtest.md), e.g. /mma shot small-home") end
	if shot then return Game.Print("shot " .. id .. ": not taken, " .. shot.id .. "'s still waiting on the client") end
	local a = applied
	shot = { id = id, note = note, at = { inst = a.inst, cx = R(a.cx, 1e4), cy = R(a.cy, 1e4), zoom = R(a.zoom, 100),
		w = R(a.w, 10), h = R(a.h, 10), left = a.left, top = a.top, big = a.big,
		uiScale = R(UIParent:GetEffectiveScale(), 1e3), screenW = R(UIParent:GetWidth(), 10),
		screenH = R(UIParent:GetHeight(), 10) } }
	shot.wait = Runtime.After(ANSWER_S, "telemetry.shot unanswered", function()
		Runtime.Trace("shot", "failed " .. shot.note)
		Answer("the client took no screenshot (no answer, no mark)")
	end)
	Screenshot()
end)

Game.Slash("telemetry", "counts of sessions, errors and marks kept; telemetry clear", function(args)
	if args == "clear" then
		wipe(db.errors)
		wipe(db.marks)
		wipe(db.sessions)
		db.sessions[1] = session
		wipe(seen)
		errors = 0
	end
	local n = 0
	for _ in pairs(db.errors) do n = n + 1 end
	Game.Print(string.format("session %d (%s): %d sessions, %d errors, %d marks, %d traced; /reload to write them",
		session.id, tostring(version), #db.sessions, n, #db.marks, #Runtime.TraceCopy()))
end)

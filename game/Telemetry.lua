-- Telemetry (docs/telemetry.md): sessions, errors with stacks, and marks
-- (state + Runtime's trace ring) in MagicMapAtlasDB.telemetry, written to
-- disk on /reload or logout for tools/telemetry.py.
-- Errors come from Runtime.onError (every Wrap) and the global error handler
-- (anything else whose stack is in our folder). An error's first occurrence
-- in a session traces "error" and takes an "error" mark.
-- Each session's perf (Runtime.FrameStats, errors, load, memory: docs/runtime.md)
-- is written at logout and with each mark.

local ADDON, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local SESSIONS, ERRORS, MARKS, ZONES = 10, 50, 20, 30
local MSG, STACK = 300, 2000 -- chars kept
local OURS = "AddOns[/\\]" .. ADDON .. "[/\\]"

local version = C_AddOns.GetAddOnMetadata(ADDON, "Version")
local db, session
local errors, loginAt = 0, nil -- this session's errors; GetTime() at login
local pending = {} -- errors before SavedVariables load
local seen = {} -- error keys this session

local function State()
	local you, view = Game.obs.you, ns.UI.View()
	local diag = view.diag and view.diag() or {}
	local map, layers = diag.map, diag.layers
	return {
		you = { inst = you.inst, col = you.col, row = you.row, facing = you.facing },
		zone = GetZoneText(), subzone = GetSubZoneText(), map = map, layers = layers,
	}
end

-- session.perf: Runtime.FrameStats() plus errors, errors an hour, load ms (and our KB at logout).
local function Perf(ourKB)
	local p = Runtime.FrameStats()
	local hours = math.max((GetTime() - (loginAt or 0)) / 3600, 1 / 60) -- at least a minute
	p.errors, p.errorsPerHour, p.loadMs = errors, math.floor(errors / hours * 10 + 0.5) / 10, session.boot.loadMs
	p.ourKB = ourKB or (session.perf and session.perf.ourKB)
	session.perf, session.frames = p, Runtime.frames
end

local function Mark(kind, note, stamp)
	Runtime.Trace(kind, note)
	Perf()
	local marks = db.marks
	marks[#marks + 1] = {
		kind = kind, note = note, t = time(), stamp = stamp, session = session.id, version = version,
		frame = Runtime.frames, state = State(), trace = Runtime.TraceCopy(),
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
	Runtime.Trace("error", key:sub(1, 120))
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

Game.Load("telemetry", function(saved)
	local last = saved.sessions[#saved.sessions]
	local v, build = GetBuildInfo()
	local b = Runtime.boot
	session = {
		id = (tonumber(type(last) == "table" and last.id) or 0) + 1, version = version, build = v .. "." .. build,
		started = time(), boot = { loadMs = b.loaded.t - b.t0, loadKB = b.loaded.mem - b.mem0 }, frames = 0, zones = {},
	}
	db = saved
	db.sessions[#db.sessions + 1] = session
	if #db.sessions > SESSIONS then table.remove(db.sessions, 1) end
	for _, p in ipairs(pending) do Record(p[1], p[2], p[3]) end
	pending = nil
end, { version = 1, defaults = { sessions = {}, errors = {}, marks = {} } })

local function Zone()
	local zone, zones = GetZoneText(), session.zones
	Runtime.Trace("zone", zone)
	if zones[#zones] ~= zone and #zones < ZONES then zones[#zones + 1] = zone end
end

Runtime.On("PLAYER_LOGIN", "telemetry.login", function()
	local b = Runtime.boot
	session.boot.loginMs = b.login.t - b.t0
	loginAt = GetTime()
	Runtime.Trace("login", version)
	Zone()
end)
Runtime.On("ZONE_CHANGED_NEW_AREA", "telemetry.zone", Zone)
Runtime.On("PLAYER_LOGOUT", "telemetry.logout", function() -- also /reload
	UpdateAddOnMemoryUsage()
	Perf(math.floor(GetAddOnMemoryUsage(ADDON)))
end)

-- Shots: the mark waits for SCREENSHOT_SUCCEEDED; stamp as in WoWScrnShot_<stamp>.jpg.
local shot -- the pending /mma shot's note ("" for none)
Runtime.On("SCREENSHOT_SUCCEEDED", "telemetry.shot", function()
	if not shot then return end -- not ours (Print Screen)
	Mark("shot", shot ~= "" and shot or nil, date("%m%d%y_%H%M%S"))
	shot = nil
end)
Runtime.On("SCREENSHOT_FAILED", "telemetry.shot failed", function() shot = nil end)

Game.Slash("mark", "<note>: save state and the recent trace (written on /reload)", function(note)
	Mark("mark", note ~= "" and note or nil)
	Game.Print("marked")
end)

Game.Slash("shot", "[note]: a screenshot, and a mark matched to it", function(note)
	shot = note
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

-- /mm record on|off: the observations handed to Model, kept in
-- MagicMap2DB.recording.obs (written on /reload) for replaying into Model
-- alone (tools/tests/replay.lua). One is kept each time what the blip sensor
-- knows changes (Game.blipsRev), as handed over: you, blips, frame, t, epoch;
-- at most MAX, then it stops.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local MAX = 3000
local db, rev

local function R3(v) return v and math.floor(v * 1000 + 0.5) / 1000 end
local function Pos(p) return p and { inst = p.inst, col = R3(p.col), row = R3(p.row) } end

Game.Load("recording", function(saved) db = saved end, { version = 1, defaults = { on = false, obs = {} } })

Runtime.Step("observe", "game.record", function()
	if not (db and db.on) or rev == Game.blipsRev then return end
	rev = Game.blipsRev
	local o, list = Game.obs, {}
	local b = o.blips
	for i, x in ipairs(b and b.list or {}) do
		list[i] = { name = x.name, pos = Pos(x.pos), rough = x.rough, icon = x.icon, atlas = x.atlas }
	end
	db.obs[#db.obs + 1] = { frame = o.frame, t = R3(o.t), epoch = o.epoch,
		you = { inst = o.you.inst, col = R3(o.you.col), row = R3(o.you.row), facing = R3(o.you.facing) },
		blips = b and { list = list, sweep = b.sweep, center = Pos(b.center), reach = R3(b.reach) } }
	if #db.obs >= MAX then db.on = false; Game.Print("recording full: " .. MAX .. " observations; /reload to write them") end
end)

Game.Slash("record", "on | off | clear: keep the observations handed to Model (for replay tests)", function(args)
	if args == "on" or args == "off" then db.on = args == "on" end
	if args == "clear" then wipe(db.obs) end
	Game.Print(string.format("recording %s, %d observations kept", db.on and "on" or "off", #db.obs))
end)

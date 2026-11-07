-- Track or path to any icon. A click, left or right, on a pin of any pin layer (ui/Pins.lua's Pins.Tap; a pill's
-- grid pins too, ui/Cluster.lua) grows its tooltip into the popup (ui/Popup.lua), its buttons the pin's actions
-- (Track.Actions): Track and Path to, each Stop tracking (Stop pathing) while it's what you do to that pin. Either
-- sets the user waypoint the map already follows (the waypoint Command, game/commands/waypoint.lua: C_Map's,
-- super-tracked) at the icon's pos, and stops following a followed quest (Model's target is corpse, then the
-- followed quest, then the waypoint: model/Target.lua), so the title band's target goes to the icon. Track shows
-- the way with Blizzard's gold arrow alone, placed along the route (ui/Guide.lua); Path to with the full line,
-- the small map framing you and it (ui/Path.lua, ui/Motion.lua). The two are exclusive: choosing one replaces the
-- other, Stop ends either. The waypoint's own pin steps aside while it stands under the icon (ui/You.lua:
-- Track.Covers); the title names the icon (You.Target). Your waypoint's own pin (set by Ctrl-click, the map's
-- menu, /way) is tracked as it stands while no quest is followed: its actions switch the mode, or stop it, and
-- Clear waypoint. A quest pin's follow it, no waypoint (ui/Areas.lua's Follow): Track, Path to, and Open in quest
-- log (the questlog Command); the quest pill's too, which while it shows the followed quest is that quest's pin
-- (ui/Controls.lua).
-- The tracked icon is UI.saved.tracked = { key, name, inst, col, row } (types/saved.lua): its key, where it was;
-- what's pathed is UI.saved.path = { quest } or { inst, col, row } (the waypoint's pos), with the framing's zoom
-- once it has one (ui/Path.lua). Your corpse, while you're a ghost, always has the line (Track.Pathed).
-- Arriving finishes it (Track.Arrived: within ARRIVE yards, or inside a quest's area): a waypoint's tracking or
-- pathing ends, the waypoint cleared; a quest's pathing ends, the quest still followed (its arrow steps aside
-- while you're there).
-- The tracking ends when the waypoint goes or moves elsewhere (Ctrl-right-click, the map's menu, /way, the
-- game's own), a waypoint's pathing too, and a quest's pathing once that quest is no longer followed; watched
-- once a frame from the pin layers' revs (Track.Rev: a change lays them out again) once Model has seen the
-- waypoint and the Command has had its frame; and across sessions the game keeps the waypoint and the
-- followed quest, so both stay as they were.

local _, ns = ...
local UI, Model, Runtime, Atlas = ns.UI, ns.Model, ns.Runtime, ns.Atlas
local Command = ns.Game.Command

local NEAR = 0.01 -- tiles (~5 yards): the waypoint stands at the tracked pos (set through map coordinates and read back)
local ARRIVE = 5 -- yards: within this of the target (or inside its quest's area) you've arrived
local ARM = 2 -- frames after a Track before the waypoint must stand there (the Command's apply, the next observe)

-- The actions' icons (the popup's buttons, ui/Popup.lua): the world map's gold tracked arrow; the travel boot
-- (flightpath), made gold, each before its word on a red panel button; the micro menu's quest log button (28 x 36);
-- Clear, its word alone.
local TRACK_ICON = { atlas = "Navigation-Tracked-Arrow" }
local PATH_ICON = { atlas = "flightpath", gold = true }
local LOG_ICON = { up = "hud-microbutton-Quest-Up", down = "hud-microbutton-Quest-Down",
	lit = "hud-microbutton-highlight", aspect = 28 / 36, blend = "ADD" }
local CLEAR_ICON = {} -- (a word alone)

local Track = {}
UI.Track = Track

local rev, frame = 0, -1 -- moves with the tracked key; the frame it was last looked at
local last -- the saved table seen at the last look (a /reload's, or ours)
local armed = 0 -- the frame the watch resumes at

local function Saved()
	local s = UI.saved
	return s and s.tracked
end

local function Path()
	local s = UI.saved
	return s and s.path
end

local function Near(pos, t)
	return pos.inst == t.inst and math.abs(pos.col - t.col) <= NEAR and math.abs(pos.row - t.row) <= NEAR
end

-- The tracked icon's pos covers pos: the waypoint stands under it.
function Track.Covers(pos)
	local t = Saved()
	return t ~= nil and Near(pos, t)
end

-- e is the tracked icon (its key's; a grid proxy carries the real one's key).
function Track.Is(e)
	local t = Saved()
	return t ~= nil and t.key == e.key
end

-- e is what you track: the tracked icon, or the quest you follow. Never grouped into a pill, nor held back
-- to a closer zoom (ui/Pins.lua, ui/Cluster.lua): it is always on the map while its layer is.
function Track.Focus(e)
	return Track.Is(e) or e.kind == "quests" and e.followed == true
end

-- The tracked icon's name, or nil.
function Track.Name()
	local t = Saved()
	return t and t.name
end

-- Target t (Model.Target's) has the line (Path to), not the arrow (Track): your corpse always; the quest you
-- follow, or your waypoint, while it's what Path to was chosen for.
function Track.Pathed(t)
	if not t then return false end
	if t.kind == "corpse" then return true end
	local p = Path()
	if not p then return false end
	if t.kind == "quest" then return p.quest ~= nil and p.quest == t.quest end
	return t.kind == "waypoint" and p.inst ~= nil and Near(t.pos, p)
end

-- You've arrived at target t (Model.Target's): inside its quest's area, else within ARRIVE yards of it, on its
-- map. Not your corpse (the game ends that).
function Track.Arrived(t)
	if not t or t.kind == "corpse" then return false end
	if t.inside then return true end
	local you = Model.you
	if not (you and you.col and not you.stale and you.inst == t.pos.inst) then return false end
	local yd = math.sqrt((t.pos.col - you.col) ^ 2 + (t.pos.row - you.row) ^ 2) * Atlas.TILE_YARDS
	return yd <= ARRIVE
end

local function Set(t)
	UI.saved.tracked = t
	rev = rev + 1
end

local function Followed()
	for _, e in ipairs((Model.Known("quests"))) do
		if e.followed then return e end
	end
end

-- Once a frame: the waypoint gone or elsewhere ends the tracking and a waypoint's pathing; a quest no longer
-- followed (its entry says so) ends its pathing (not before Model has read the waypoint: rev 0, nor in the
-- frames the Command takes).
local function Watch()
	local t, p = Saved(), Path()
	if t ~= last then last, rev = t, rev + 1 end
	if Runtime.frames < armed then return end
	-- Arrived: finished. A waypoint's (or the icon tracked on it) tracking or pathing ends, the waypoint cleared;
	-- a quest's pathing ends (still followed: its arrow steps aside while you're there, ui/Guide.lua).
	local g = Model.Target()
	if g and Track.Arrived(g) then
		if g.kind == "waypoint" and (t or p and p.inst) then
			Track.Stop()
			return
		end
		if g.kind == "quest" and p and p.quest == g.quest then
			UI.saved.path = nil
			p = nil
		end
	end
	if not (t or p) then return end
	local list, r = Model.Known("waypoint")
	if r == 0 then return end
	local w = list[1]
	if t and not (w and Near(w.pos, t)) then Set(nil) end
	if p and p.inst and not (w and Near(w.pos, p)) then UI.saved.path = nil end
	if p and p.quest then -- (seen followed first: the follow Command takes an observation or two)
		for _, e in ipairs((Model.Known("quests"))) do
			if e.quest == p.quest then
				if e.followed then p.seen = true elseif p.seen then UI.saved.path = nil end
			end
		end
	end
end

-- A rev moving with the tracked key (the pin layers' revs carry it: ui/Pins.lua).
function Track.Rev()
	if frame ~= Runtime.frames then
		frame = Runtime.frames
		Watch()
	end
	return rev
end

-- Track e, or (path) Path to it: the waypoint at its pos, your target (the followed quest let go). Your
-- waypoint's own pin stays as it is: the mode alone set.
function Track.Start(e, path)
	local p = e.pos
	armed = Runtime.frames + ARM
	UI.saved.path = path and { inst = p.inst, col = p.col, row = p.row } or nil
	if path then UI.Motion.Reframe() end
	if Followed() then Command({ kind = "follow", quest = false }) end
	if e.kind == "waypoint" then return end
	Set({ key = e.key, name = e.name, inst = p.inst, col = p.col, row = p.row })
	Command({ kind = "waypoint", pos = { inst = p.inst, col = p.col, row = p.row } })
end

-- Tracking or pathing ended, the waypoint cleared.
function Track.Stop()
	Set(nil)
	UI.saved.path = nil
	Command({ kind = "waypoint", pos = false })
end

-- Follow quest e, or (path) Path to it; the mode it has already, again: stopped (unfollowed).
local function Quest(e, path)
	armed = Runtime.frames + ARM
	if e.followed and Track.Pathed({ kind = "quest", quest = e.quest }) == path then
		UI.saved.path = nil
		UI.Areas.Follow(e)
		return
	end
	UI.saved.path = path and { quest = e.quest } or nil
	if path then UI.Motion.Reframe() end
	if not e.followed then UI.Areas.Follow(e) end
end

local Pick = Runtime.Wrap("map: track pick", function(fn, e, path) fn(e, path) end)

local OpenLog = function(e) Command({ kind = "questlog", quest = e.quest }) end

-- What you do to pin e: "track", "path" or nil. Your waypoint's own pin is tracked while no quest is followed.
local function Mode(e)
	local on
	if e.kind == "quests" then
		on = e.followed
	elseif e.kind == "waypoint" then
		on = not Followed()
	else
		on = Track.Is(e)
	end
	if not on then return nil end
	local p = Path()
	if e.kind == "quests" then return p and p.quest == e.quest and "path" or "track" end
	return p and p.inst and Near(e.pos, p) and "path" or "track"
end

-- Pin e's actions, the popup's buttons (ui/Popup.lua), { label, fn, icon, on? }: Track and Path to, each "Stop
-- tracking" ("Stop pathing") while it's the mode (its button gold-trimmed); a quest's follow it, and Open in quest log;
-- your waypoint's own pin, Clear waypoint too.
function Track.Actions(e)
	local mode, quest = Mode(e), e.kind == "quests"
	local list = {
		{ mode == "track" and "Stop tracking" or "Track", function()
			if quest then Pick(Quest, e, false) elseif mode == "track" then Pick(Track.Stop) else Pick(Track.Start, e, false) end
		end, word = "Track", icon = TRACK_ICON, on = mode == "track" },
		{ mode == "path" and "Stop pathing" or "Path to", function()
			if quest then Pick(Quest, e, true) elseif mode == "path" then Pick(Track.Stop) else Pick(Track.Start, e, true) end
		end, word = "Path", icon = PATH_ICON, on = mode == "path" },
	}
	if quest then list[3] = { "Open in quest log", function() Pick(OpenLog, e) end, icon = LOG_ICON } end
	if e.kind == "waypoint" then list[3] = { "Clear waypoint", function() Pick(Track.Stop) end, word = "Clear", icon = CLEAR_ICON } end
	return list
end

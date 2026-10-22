-- Track any icon. A left click on a pin of any pin layer (ui/Pins.lua's Pins.Tap; a pill's grid pins too,
-- ui/Cluster.lua) opens a small menu, the client's own (UI.Menus.Show, as the map's right-click): the pin's
-- name, then Track, or Stop tracking while it's the tracked one. Tracking sets the user waypoint the map
-- already follows (the waypoint Command, game/commands/waypoint.lua: C_Map's, super-tracked) at the icon's
-- pos, and stops following a followed quest (Model's target is corpse, then the followed quest, then the
-- waypoint: model/Target.lua), so the line and the title band's target go to the icon. The tracked pin wears
-- the followed quest's gold ring (Pins.Style's glow, forced for its key: Track.Is) and the waypoint's own pin
-- steps aside while it stands under the icon (ui/You.lua: Track.Covers); the title names the icon (You.Target).
-- A quest pin's Track is following it, no waypoint (ui/Areas.lua's Follow): one row, "Track quest".
-- The tracked icon is UI.saved.tracked = { key, name, inst, col, row } (types/saved.lua): its key, where
-- it was. It ends when the waypoint goes or moves elsewhere (Ctrl-right-click, the map's menu, /way, the
-- game's own), watched once a frame from the pin layers' revs (Track.Rev: a change lays them out again) once
-- Model has seen the waypoint and the Command has had its frame; and across sessions the game keeps the
-- waypoint, so the icon stays tracked.

local _, ns = ...
local UI, Model, Runtime = ns.UI, ns.Model, ns.Runtime
local Command = ns.Game.Command

local NEAR = 0.01 -- tiles (~5 yards): the waypoint stands at the tracked pos (set through map coordinates and read back)
local ARM = 2 -- frames after a Track before the waypoint must stand there (the Command's apply, the next observe)

local Track = {}
UI.Track = Track

local rev, frame = 0, -1 -- moves with the tracked key; the frame it was last looked at
local last -- the saved table seen at the last look (a /reload's, or ours)
local armed = 0 -- the frame the watch resumes at

local function Saved()
	local s = UI.saved
	return s and s.tracked
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

-- The tracked icon's name, or nil.
function Track.Name()
	local t = Saved()
	return t and t.name
end

local function Set(t)
	UI.saved.tracked = t
	rev = rev + 1
end

-- Once a frame: the waypoint gone or elsewhere ends the tracking (not before Model has read it: rev 0, nor in
-- the frames the Command takes).
local function Watch()
	local t = Saved()
	if t ~= last then last, rev = t, rev + 1 end
	if not t then return end
	local list, r = Model.Known("waypoint")
	if r == 0 or Runtime.frames < armed then return end
	local w = list[1]
	if not (w and Near(w.pos, t)) then Set(nil) end
end

-- A rev moving with the tracked key (the pin layers' revs carry it: ui/Pins.lua).
function Track.Rev()
	if frame ~= Runtime.frames then
		frame = Runtime.frames
		Watch()
	end
	return rev
end

local function Followed()
	for _, e in ipairs((Model.Known("quests"))) do
		if e.followed then return true end
	end
	return false
end

-- Track e: the waypoint at its pos, your target (the followed quest let go).
function Track.Start(e)
	local p = e.pos
	Set({ key = e.key, name = e.name, inst = p.inst, col = p.col, row = p.row })
	armed = Runtime.frames + ARM
	if Followed() then Command({ kind = "follow", quest = false }) end
	Command({ kind = "waypoint", pos = { inst = p.inst, col = p.col, row = p.row } })
end

-- Tracking ended, the waypoint cleared.
function Track.Stop()
	Set(nil)
	Command({ kind = "waypoint", pos = false })
end

local Pick = Runtime.Wrap("map: track pick", function(fn, e) fn(e) end)

-- The menu for pin e (a Known entry), anchored on owner (its frame).
function Track.Menu(owner, e)
	UI.Menus.Show(owner, function(_, root)
		root:CreateTitle(e.name or "?")
		if e.kind == "quests" then -- (following it: ui/Quests.lua)
			root:CreateButton(e.followed and "Stop tracking" or "Track quest", function() Pick(UI.Areas.Follow, e) end)
		elseif Track.Is(e) then
			root:CreateButton("Stop tracking", function() Pick(Track.Stop) end)
		else
			root:CreateButton("Track", function() Pick(Track.Start, e) end)
		end
	end)
end

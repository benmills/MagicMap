---@meta
-- Contract 3: View (UI-owned, read by Game in Apply) and Commands (UI -> Game,
-- carried out in Input). docs/decisions/0003-view-and-commands.md
--
-- View is the one place Game reads UI. It is cross-system, so it is minimal
-- and versioned: only what Game acts on, nothing UI keeps for itself (camera,
-- animation, layout, menus stay inside UI).
--
-- LOCKED (one-way door):
--   * UI publishes with UI.View() -> MM.View (the same table each call is fine);
--     Game reads it only in its apply step, never writes it
--   * `v`: Game acts on a View only if it knows `v`; otherwise it acts as on
--     SAFE_VIEW (below) (Blizzard's minimap, nothing borrowed). Adding an optional
--     field doesn't bump `v`; renaming, removing or changing a meaning does
--   * the fields below and their meaning
--   * Commands: Game.Command(cmd); the kinds below, each idempotent
--   * HookedInput: what Game's hooks catch for UI, via Observation.hooked
-- OPEN: new optional View fields, new command kinds, new hooked kinds.

---@alias MM.ViewVersion 1

---Who has the Minimap. "blizzard": Game releases it (puts back everything it
---changed); "ours": Game takes it while the window is shown and nothing blocks it.
---@alias MM.MinimapMode "blizzard"|"ours"

---What draws the ground in our window while the Minimap is ours.
---"ours": our tiles, the Minimap a hidden sensor (blips) under the window.
---"ours+art": the same, UI drawing the indoor art (Observation.indoorArt) over the tiles.
---"blizzard": the Minimap whole inside the window (its indoor floor plan); no sensor.
---@alias MM.Renderer "ours"|"ours+art"|"blizzard"

---@class MM.View
---@field v MM.ViewVersion
---@field frame MM.Frame         when UI last changed it
---@field minimap MM.MinimapMode
---@field renderer MM.Renderer
---@field inst MM.Inst           the map shown: Game scopes per-map reads (offers, places, addon pins) to it and to yours
---@field window MM.ViewWindow
---@field layers table<string, boolean> shown layers Game acts on (keys: MM.GameLayer); a missing key is off
---@field sockets MM.ViewSockets
---@field button boolean         Game's minimap button is shown
---@field diag? fun(): table      UI's state for telemetry marks (camera, layouts: docs/telemetry.md "State" `map`, `layers`).
---                              Game calls it only when taking a mark and stores the result; it never acts on it. Its shape is UI's (OPEN).

---@class MM.ViewWindow
---@field shown boolean
---@field big boolean            grown to the big map: Game shows its Escape catcher
---@field place? MM.ScreenRect   the map's view (where tiles are drawn), screen units; nil while hidden
---@field still boolean          `place` hasn't changed since the last frame: the blip sensor may read
---@field strata string          the window's frame strata: the Minimap goes just beneath it (sensor) or in it (whole)
---@field level integer          the window's frame level
---@field homeAlpha number       0..1: the Minimap's home corner (cluster), faded out while big

---Layers Game acts on:
---  "blips"   run the blip sensor
---  "flight", "quests", "pois"  ours are drawn: Game turns Blizzard's tracking of the same off (and back on when not)
---  "addon:" .. MM.ObsAddon.key  borrow that addon's pins onto the sockets
---@alias MM.GameLayer "blips"|"flight"|"quests"|"pois"|string

---Frames UI owns and Game places other addons' pins on. Game parents pins to
---a socket's frame and positions them on it; it never moves, sizes or hides
---the frame itself, and takes every pin back when the socket goes (nil) or changes frame.
---@class MM.ViewSockets
---@field world? MM.Socket       other addons' world-map pins (HereBeDragons), on the map shown
---@field minimap? MM.Socket     their minimap pins, around you (Game sizes them to the Minimap's view)

---A canvas: tile (col, row) of `inst` sits at (col * zoom, -row * zoom) from the frame's TOPLEFT.
---@class MM.Socket
---@field frame table            a Frame (UI's)
---@field inst MM.Inst
---@field zoom number            pixels per tile on the frame
---@field level? integer         frame level for the pins (default: the frame's + 1)

---What Game falls back to when it can't use the View (unknown `v`, UI.View
---missing or failing): Blizzard's minimap, nothing borrowed, our tracking changes undone.
---@type MM.View
local SAFE_VIEW = {
	v = 1, frame = 0, minimap = "blizzard", renderer = "ours", inst = 0,
	window = { shown = false, big = false, still = false, strata = "LOW", level = 0, homeAlpha = 1 },
	layers = {}, sockets = {}, button = true,
}

-- Commands ------------------------------------------------------------------------
--
-- UI calls Game.Command(cmd) from anywhere (a click script, its input step).
-- Game queues it and carries the queue out, in order, in its input step: in the
-- same frame for a click (scripts run between frames), at most one frame later
-- from a step. Each command states the result wanted, so sending it again does
-- nothing new. No reply: the effect shows in the next Observation (the same
-- frame, since Observe follows Input). One that fails is reported (Runtime)
-- and dropped, never retried.

---@alias MM.Command MM.CmdFollow|MM.CmdWaypoint|MM.CmdWay|MM.CmdTracking|MM.CmdTooltip|MM.CmdSlash|MM.CmdLoad

---Follow a quest: the game's super-tracked quest (and watched); false: follow none.
---@class MM.CmdFollow
---@field kind "follow"
---@field quest MM.QuestID|false

---Set the user waypoint at pos (Game finds the zone uiMap there); false clears it.
---@class MM.CmdWaypoint
---@field kind "waypoint"
---@field pos MM.Pos|false

---Open the chat box holding a "/way <zone> <x> <y>" line for pos (not sent).
---@class MM.CmdWay
---@field kind "way"
---@field pos MM.Pos

---Turn one of Blizzard's tracking types (MM.ObsTracking.id) on or off.
---@class MM.CmdTracking
---@field kind "tracking"
---@field id integer
---@field on boolean

---Show GameTooltip's own content for a game thing on owner (what UI can't
---write itself: a unit's tooltip, an NPC's portrait); owner false hides it if Game showed it.
---Portraits never cross as objects (ADR 0001): Game draws the NPC's portrait into the
---tooltip itself and takes it back when the tooltip hides.
---@class MM.CmdTooltip
---@field kind "tooltip"
---@field owner table|false      a Frame (UI's)
---@field anchor? string         "ANCHOR_RIGHT" etc. (default ANCHOR_CURSOR)
---@field member? string         a group member's id (MM.ObsMember.id)
---@field npc? MM.NpcID          an NPC: Game adds its portrait (if it has captured one)

---Register `/mma <name>` (Game owns slash commands): fn(args) runs wrapped when typed.
---Sending it again replaces fn. Added with the walking skeleton (open: new kinds).
---@class MM.CmdSlash
---@field kind "slash"
---@field name string
---@field help string
---@field fn fun(args: string)

---Hand UI its saved part (ADR 0004): Game.Load(owner, fn, spec) on UI's behalf.
---fn gets the part once (again on a repeat: the same table).
---@class MM.CmdLoad
---@field kind "load"
---@field owner "UI"
---@field fn fun(saved: table)
---@field spec? MM.SavedSpec

---@class MM.GameEntry
local Game = {}

---@param cmd MM.Command
function Game.Command(cmd) end

-- Hooked input (Game -> UI, through Model) -----------------------------------------
--
-- Keys Blizzard owns (M, Escape) reach us only through Game's hooks. Game puts
-- what they caught in Observation.hooked; Model hands it on unchanged as
-- Model.hooked for UI's ui step to act on, the same frame.

---@alias MM.HookedKind
---| "worldmap"   M (ToggleWorldMap) while View.window.shown: Game has hidden Blizzard's world map
---| "escape"     Escape while View.window.big: Game's catcher closed

---@class MM.HookedInput
---@field kind MM.HookedKind

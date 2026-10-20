---@meta
-- Contract 6: Model's read API (UI reads Model), and how Game hands Model its
-- saved part. docs/decisions/0006-model-read-api.md
--
-- UI reads Model only through these. Everything else in Model (merge state,
-- indexes, caches) is internal.
--
-- LOCKED (one-way door):
--   * Known(kind) -> list, rev: every pin-like thing Model knows, one shape for
--     all kinds, so a new kind is a Model file that fills it and a UI layer that
--     draws it (plus Atlas data if static), with no change here
--   * Model.you, Model.hooked, Target(), Route() and their meanings
--   * Model.Load(saved) / Model.SAVED: Game.Load("Model", Model.Load, Model.SAVED)
-- OPEN: new kinds (strings), new optional MM.Known fields, Target / Route shapes
-- beyond the fields below, new optional fields of Model.you, and
-- more of the Observation handed on unchanged (minimap, addons, levels, waypointSet, explored, exploredCells,
-- indoorArt, tracking).

---@alias MM.KnownKind "blips"|"remembered"|"rares"|"quests"|"offers"|"places"|"group"|"corpse"|"waypoint"|"vignettes"|"services"|string

---One thing Model knows, of any kind.
---@class MM.Known
---@field key string           stable within its kind across frames (and /reload, for remembered ones)
---@field kind MM.KnownKind
---@field pos MM.Pos
---@field name string
---@field icon? MM.Icon        how the game shows it; nil: the kind's default look
---@field live boolean         sensed now (false: remembered from before)
---@field t? MM.Epoch          last seen, for remembered ones
---@field text? string         a line for its tooltip

-- Known kinds (OPEN): MM.Known plus optional fields of their own; each nil: the
-- kind's default look (docs/v1-plan.md §4). `name` is the tooltip's title.

---Known("quests"): your log's quests on their maps (obs.quests + Atlas).
---@class MM.KnownQuest: MM.Known
---@field quest? MM.QuestID
---@field level? integer
---@field color? number[]          difficulty { r, g, b }; nil: no level
---@field complete? boolean        ready to turn in
---@field followed? boolean        super-tracked
---@field count? string            "n/m" of the first unfinished objective that counts
---@field inner? MM.Icon           the first unfinished objective's icon (its item's, else its type's)
---@field need? "kill"|"gather"|"other"  what it still needs: its area's colour
---@field areaMap? MM.UiMapID      the game draws its objective area on this uiMap
---@field objectives? MM.KnownObjective[]  tooltip lines
---@field turnIn? string           who takes it in (Atlas finishedBy)
---@field tag? string              obs.quests' tag: the tooltip's facts line ("Elite", "Group (3)": QuestInfo.lua:321-325)
---@field group? integer           obs.quests' suggested group size; shown past 1
-- Known("quests")' list carries obs.quests' poi (list.poi): a new one, a new list of the same entries (the
-- game's areas may have changed: UI draws them again; a count ticking draws nothing again).

---@class MM.KnownObjective
---@field text string
---@field finished boolean
---@field drops? MM.KnownMob[]     who drops its item: at most 3, lowest level first
---@field more? integer            droppers past those
---@field from? string             no drops: the objects it's in ("A, B")
---@field sold? string             neither: who sells it

---@class MM.KnownMob
---@field npc MM.NpcID             its portrait once met (tooltip Command)
---@field name string
---@field lo? integer              levels
---@field hi? integer
---@field color? number[]          difficulty of `hi`
---@field rank? string             "Elite", "Rare", ...

---Known("offers"): quests to pick up (obs.offers), none in progress.
---@class MM.KnownOffer: MM.Known
---@field quest? MM.QuestID
---@field line? string             its quest line's name, when not the quest's

---Known("places"): Atlas's and the game's live places, deduped; Atlas's of a kind where the game marks none of
---that kind on the instance, or before it's read there.
---@class MM.KnownPlace: MM.Known
---@field place? MM.PlaceKind
---@field faction? MM.Faction      flight: whose
---@field known? boolean           flight: you have it

---Known("group"): members with a position (obs.group); key the member's id (tooltip Command `member`).
---@class MM.KnownMember: MM.Known
---@field class? string            class token, for its colour
---@field level? integer
---@field dead? boolean

---Known("corpse"): yours, at most one.
---@class MM.KnownCorpse: MM.Known

---Known("waypoint"): the user waypoint, at most one.
---@class MM.KnownWaypoint: MM.Known

---Known("vignettes"): what the game shows near you now (obs.vignettes), not the targeted rare; key the vignette
---GUID; text "Nearby now".
---@class MM.KnownVignette: MM.Known
---@field rare? boolean            a rare or elite
---@field npc? MM.NpcID

---Known("blips"): the Minimap's blips sensed now (obs.blips), live; icon the tracking texture or a
---gathering atlas (nil: a dot). One a remembered blip stands for carries that one's key, so a layer
---drawing both skips the remembered of that key.
---Known("remembered"): blips seen before (saved.blips), Focus's instance (else yours); live false, t last seen;
---listed while tracking shows its icon (obs.tracking; not yet known: all), none within 30 yd of a service of its name.
---Known("rares"): the rares you've seen (saved.rares), Focus's instance (else yours), but one a live rare vignette
---of its name stands for while the vignettes layer is on (Focus.off); live false, t last seen, text "Rare".

---Known("services"): town services (Atlas BlipServices), Focus's instance, while their tracking is on; gathered
---for Focus's rect once asked for at zoom 60 or more (a job); text the NPC's title.
---@class MM.KnownService: MM.Known
---@field service? string          its BlipServices value
---@field npc? MM.NpcID

---@class MM.ModelYou
---@field inst? MM.Inst
---@field col? MM.Col          last known (kept while unknown)
---@field row? MM.Row
---@field facing? number
---@field stale boolean        the position is the last known, not this frame's
---@field uiMap? MM.UiMapID    this frame's (obs.you.uiMap); nil: the client gives none (an instance without a map)
---@field zone? string         this frame's (obs.you.zone): the client's name for your zone
---@field subzone? string      this frame's (obs.you.subzone): its name for where you are in it
---@field level? integer
---@field faction? MM.Faction
---@field dead? boolean        dead or a ghost
---@field ghost? boolean       released: your corpse becomes the target
---@field combat? boolean      InCombatLockdown()

---What to go to (OPEN beyond these fields).
---@class MM.Target
---@field kind MM.KnownKind|"quest"|"corpse"|"waypoint"
---@field key string
---@field pos MM.Pos
---@field inside? boolean      you're in its area (held 0.5 s): arrived, the line and edge arrow step aside; nil: no area
---@field title? string        what the title band names it ("<title> N yd", "<title> here")
---@field quest? MM.QuestID    kind "quest": which

---The way to the target: still an MM.Pos[] (tile space, you first, the target last: as the MVP's
---RouteTo, Route.lua:362-370), with two optional flags.
---@class MM.Route
---@field [integer] MM.Pos
---@field straight? boolean    no walk data here: you and the target only, drawn straight
---@field partial? boolean     no way all the way: it ends where the walk grid gets nearest, then straight on

---@class MM.ModelRead
---@field you MM.ModelYou
---@field hooked MM.HookedInput[]  this frame's hooked keys, handed on from obs.hooked unchanged (ADR 0003)
---@field minimap? MM.ObsMinimap  this frame's obs.minimap, handed on unchanged like hooked (UI places its small window on home)
---@field addons MM.ObsAddon[]     other addons whose pins Game can borrow, handed on from obs.addons (the "Other addons"
---                                layers: View.layers "addon:<key>"); {} until known
---@field levels table<MM.UiMapID, integer[]> each map's level range, { lo, hi }, handed on from obs.levels (the
---                                inspector's level line); {} until known
---@field waypointSet? boolean     obs.waypointSet, the last handed: a user waypoint is set, wherever (the menu's Clear
---                                waypoint: Known("waypoint") has none where Atlas can't place it)
---@field explored? table<MM.AreaID, boolean>  obs.explored, the last handed (nil until known): the inspector's
---                                place line's names
---@field exploredCells? table<MM.Inst, table<integer, table<integer, boolean>>>  obs.exploredCells, the last handed
---                                (nil until known): the inspector's "Unexplored"
---@field indoorArt? MM.ObsArt|false  obs.indoorArt, the last handed (nil until known; false: none): UI's indoor art
---                                and its View.renderer pick
---@field tracking MM.ObsTracking[]  obs.tracking, the last handed ({} until known): the gear's Tracking submenu
---@field SAVED MM.SavedSpec       Model's saved part's spec (types/saved.lua MM.SavedModel)
local Model = {}

---What Model knows of `kind`: every instance, or for a kind built from Atlas on
---demand (e.g. rares), only Focus's instance; UI filters by inst either way. The same
---list table until it changes; rev goes up by one each time it does (a layer
---redraws when rev changes). An unknown kind: {}, 0. Never errors.
---@param kind MM.KnownKind
---@return MM.Known[] list
---@return integer rev
function Model.Known(kind) end

---@return MM.Target|false|nil  false: none; nil: not known yet
function Model.Target() end

---The way to the target: points in tile space, you first, the target last; nil while not found.
---@return MM.Route|nil
function Model.Route() end

---Game's loader for Model's saved part (Game.Load("Model", Model.Load, Model.SAVED)),
---once SavedVariables are loaded. Model keeps the table and mutates it in place.
---@param saved MM.SavedModel
function Model.Load(saved) end

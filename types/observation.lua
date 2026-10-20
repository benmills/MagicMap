---@meta
-- Contract 1: Observation and Oracles (Game -> Model).
-- docs/decisions/0001-observation-and-oracles.md
--
-- Each frame, Game's observe step calls Model.Observe(obs, oracles) once.
--
-- LOCKED (one-way door):
--   * the delivery: one call a frame, in the observe phase, obs and oracles
--   * positions in tile space (MM.Pos), the nil / false rule (types/core.lua)
--   * the two cadences and the identity rule:
--       per frame  `you`, `group`, `minimap`, `blips`, `hooked`: Game may reuse
--                  and mutate these tables next frame; Model copies what it keeps.
--       on change  every other part: a snapshot never mutated after handover.
--                  A new table (by identity) means it changed; the same table
--                  means nothing new. Model compares `obs.x ~= last.x`.
--   * the part names below and the meaning of the fields given here
--   * Oracles are pure reads of this frame's game state, called only inside
--     Model.Observe or a Model step in the same frame, never kept
-- OPEN: how Game reads each part (events, polling, sweeps, slices), new
-- optional fields, new parts (Model ignores what it doesn't know).

---@class MM.Observation
---@field frame MM.Frame             when Game assembled it
---@field t MM.Time                  GetTime() then
---@field epoch? MM.Epoch            time() then: what Model stamps saved things with (it has no clock)
---@field you MM.ObsYou              per frame; always present (fields may be nil)
---@field group? MM.ObsMember[]      per frame (Game may throttle to ~20 Hz); you are not in it
---@field minimap? MM.ObsMinimap     per frame
---@field blips? MM.ObsBlips         per frame while the sensor runs; nil while it doesn't
---@field hooked MM.HookedInput[]    per frame; usually empty (see types/view.lua)
---@field quests? MM.ObsQuests      on change: your quest log
---@field places? MM.ObsPlace[]      on change: live places the game marks (Atlas has the static ones)
---@field corpse? MM.Pos|false       on change: false = no corpse known
---@field waypoint? MM.Pos|false     on change: the user waypoint (C_Map); false = none Model can place: none, or on a map Atlas hasn't (ADR 0001's LOCKED clarification, M3)
---@field waypointSet? boolean        with waypoint: a user waypoint is set, wherever it is (C_Map.GetUserWaypoint() ~= nil)
---@field vignettes? MM.ObsVignette[] on change: what the game shows near you now
---@field offers? MM.ObsOffer[]      on change: quests to pick up on the maps Game asked about
---@field explored? table<MM.AreaID, boolean> on change: per area Game has checked; a missing key is unknown
---@field exploredCells? table<MM.Inst, table<integer, table<integer, boolean>>> on change: per continent Game
---                                   has swept, its map's rect (Atlas.MapRect(Atlas.Continent(inst))) in cells 0.2
---                                   tile a side, [j][i] (1-based, rows from its top-left): true where the client
---                                   names an explored area at the cell's centre, false where it names none (the
---                                   inspector's Unexplored), missing where no zone is (sea). A row changed is a new table.
---@field tracking? MM.ObsTracking[] on change: Blizzard's minimap tracking types
---@field indoorArt? MM.ObsArt|false on change: the world map's art for the map you're on; false = none
---@field addons? MM.ObsAddon[]      on change: other addons whose pins Game can borrow (View.layers "addon:<key>")
---@field levels? table<MM.UiMapID, integer[]> on change: each map's level range as the client gives it,
---                                   { lo, hi } (C_Map.GetMapLevels), for the maps Atlas has; one it gives none is
---                                   missing. Read once.

---@class MM.ObsYou
---@field inst? MM.Inst        the instance you're in (GetInstanceInfo: known in instances too)
---@field col? MM.Col          nil where the game hides your position (instances)
---@field row? MM.Row
---@field facing? number       radians, 0 north, counter-clockwise (GetPlayerFacing)
---@field uiMap? MM.UiMapID    C_Map.GetBestMapForUnit("player")
---@field zone? string         GetZoneText(): the client's name for your zone; nil: none
---@field subzone? string      GetSubZoneText(): its name for where you are in it (an inn, a keep); nil: none
---@field level? integer
---@field trivialRange? integer UnitQuestTrivialLevelRange("player"): a mob more than this many levels below you is grey (spike QuestInfo.lua:191); nil: 5
---@field faction? MM.Faction  "A" or "H"
---@field dead? boolean        dead or a ghost
---@field ghost? boolean       a ghost (released): your corpse becomes the target
---@field combat? boolean      InCombatLockdown(): what Game can't do now

---@class MM.ObsMember
---@field id string            the unit's GUID (stable across frames)
---@field name string
---@field class? string        class token ("WARRIOR"), for its colour
---@field level? integer
---@field dead? boolean
---@field pos? MM.Pos          nil: withheld (instances, another continent)

---@alias MM.ObjectiveType "monster"|"item"|"object"|"event"|"log"|"progressbar"|"reputation"|"other"

---@class MM.ObsObjective
---@field type MM.ObjectiveType
---@field text string
---@field have? integer
---@field need? integer
---@field finished boolean
---@field itemID? integer      for "item": its icon / tooltip (Atlas.Item)

---@class MM.ObsQuest
---@field id MM.QuestID
---@field title string
---@field level? integer       nil: the client doesn't say
---@field trivial? boolean     the client calls it grey
---@field complete boolean     ready to turn in
---@field followed boolean     the super-tracked quest (one at most)
---@field objectives MM.ObsObjective[]
---@field pin? MM.Pos          where the game puts its map pin (the smallest map that has it); nil: none
---@field areaMap? MM.UiMapID  the uiMap whose objective area holds it (for Inside and for drawing)
---@field tag? string          C_QuestLog.GetQuestTagInfo(id).tagName ("Elite", "Group", "Dungeon"); nil: none or ""
---@field group? integer       C_QuestLog.GetSuggestedGroupSize(id); nil: 0

---obs.quests: still an MM.ObsQuest[], with the game's areas' version on the list (as MM.Route's flags).
---@class MM.ObsQuests
---@field [integer] MM.ObsQuest
---@field poi? integer         the QUEST_POI_UPDATEs Game has seen (nil: none): a new one makes a new list, its
---                            quests kept (UI draws the areas again)

---@alias MM.PlaceKind "flight"|"poi"|"dungeon"|"graveyard"

---@class MM.ObsPlace
---@field key string           stable across reads: kind .. ":" .. the game's id
---@field kind MM.PlaceKind
---@field pos MM.Pos
---@field name string
---@field text? string         a description line
---@field icon? MM.Icon
---@field faction? MM.Faction
---@field known? boolean       flight: you have it (nil: not known)

---@class MM.ObsVignette
---@field id string            the vignette GUID (a targeted rare's: the unit's GUID)
---@field name string
---@field pos MM.Pos
---@field rare boolean         a rare or elite: Model remembers it (account-wide)
---@field npcID? MM.NpcID
---@field icon? MM.Icon
---@field target? boolean      not a vignette: the rare you target (not a player; rare or rareelite: spike
---                           Landmarks.lua:154-156), at your position when you targeted it (an NPC's isn't
---                           given), while it's your target; Model remembers it as a rare you've seen
---                           (SavedModel.rares, key npc:<id>) and lists no live pin for it

---@class MM.ObsOffer
---@field questID MM.QuestID
---@field name string
---@field line? string         the quest line's name when it isn't the quest's
---@field pos MM.Pos

---@class MM.ObsTracking
---@field id integer           the tracking filter id (Enum.MinimapTrackingFilter) or, without one (a spell's: Find
---                           Herbs; nil or Unfiltered), its spell ID
---@field name string
---@field texture MM.FileID    its icon: also how a blip's kind is matched to "is this tracked"
---@field active boolean
---@field kind? "duplicate"    Game keeps it off while our layer draws the same (flight, quests, POIs): not offered to the user

---@class MM.ObsMinimap
---@field engaged boolean      Game has taken the Minimap (View.minimap ~= "blizzard" and nothing blocks it)
---@field blocker? string      why it isn't, in words ("FarmHud has the minimap")
---@field indoors? boolean     the Minimap draws its indoor floor plan here (its view radius tells)
---@field indoorDebug? boolean /mm indoor is reporting (SavedGame.indoorDebug): the gear's Indoor maps box
---@field sensing boolean      the blip sensor ran this frame
---@field home? MM.ScreenRect  the Minimap's home spot (its cluster), for placing our window there
---                           (kept: Game reads it each frame and hands a new table only when the spot moved, so UI may hold it)
---@field homeStrata? string   the cluster's frame strata: UI's small window sits in it (spike MinimapMode.lua:46-49)

---A rect in UIParent units from its bottom-left (what SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT") takes).
---@class MM.ScreenRect
---@field left number
---@field top number
---@field w number
---@field h number

---@class MM.ObsBlip
---@field name string          what the Minimap's tooltip calls it
---@field pos MM.Pos
---@field rough boolean        its position wasn't measured (met while moving): don't keep it or merge on it;
---                           measured once you stand still. (How far off is the sensor's, not this contract's:
---                           today where a sweep point hit it, up to a square, ~12 yd at the widest zoom, plus lag.)
---@field icon? MM.FileID      the tracking icon Game matched it to, if any
---@field atlas? string        else a gathering node's tracking atlas (Professions_Tracking_Herb, _Ore), if any

---@class MM.ObsBlips
---@field list MM.ObsBlip[]    what the sensor knows now
---@field sweep integer        completed sweeps; goes up by one when a sweep ends
---@field center? MM.Pos       where the last completed sweep was centred
---@field reach number         its radius in tiles: a blip inside it that the sweep didn't see is gone

---@class MM.ObsArt
---@field uiMap MM.UiMapID
---@field pieces MM.ArtPiece[]
---@field outline? boolean     /mm indoor is on: UI outlines the art in pink (IndoorArt.lua:124-131, 145, 181);
---                           a new obs.indoorArt when it changes

---@class MM.ArtPiece
---@field file MM.FileID
---@field rect MM.Rect
---@field u? number            texcoord right (1 if nil)
---@field v? number            texcoord bottom (1 if nil)

---@class MM.ObsAddon
---@field key string           stable: the library copy's tag and the addon's name ("Questie")
---@field name string          for the layer menu
---@field world boolean        it has world-map pins
---@field minimap boolean      it has minimap pins

-- No WoW object crosses into Model: an NPC's portrait is drawn by Game into UI's
-- tooltip on a `tooltip` Command (types/view.lua), never handed over.

-- Oracles ---------------------------------------------------------------------------

---Functions Game backs and Model may call, within the frame they were handed.
---Each answers from this frame's game state, never errors (nil on failure)
---and never yields. Model budgets its own calls (see each one).
---@class MM.Oracles
local Oracles = {}

---Is (col, row) inside the quest's objective area, as the game draws it (wherever it lies, its pin
---in it or not; the game draws none on its areaMap: false)? nil: the quest has no areaMap, or it
---can't tell now (ask again).
---Cost: a hit test on a hidden QuestPOI frame, ~tens of us; Model calls it at
---most a few dozen times a frame (the followed quest's edge search, hover).
---The instance is the quest's areaMap's.
---@param quest MM.QuestID
---@param col MM.Col
---@param row MM.Row
---@return boolean|nil
function Oracles.Inside(quest, col, row) end


# 0001 Observation and Oracles (Game → Model)

Status: accepted (v1). Types: [types/observation.lua](../../types/observation.lua), [types/core.lua](../../types/core.lua).

## Context

Model is plain Lua and sees only what it is handed (architecture.md). Everything it
knows about the live game comes through this one boundary: where you are, your quest
log, the game's places, your group, corpse, waypoint, vignettes, quest offers,
exploration, Blizzard's tracking, the Minimap's blips and whether it is
indoors, and keys Game's hooks caught. Some answers can't be handed over as data at all:
whether a point is inside a quest's objective area is a hit test on a QuestPOI frame the
client draws. The spike read all of this ad hoc from every file, in world yards, uiMap
0..1 and pixels, and kept its own caches of each. Changing this shape later means
touching every Game reader and every Model consumer at once.

## Decision

- **One call a frame**: Game's observe step calls `Model.Observe(obs, oracles)`.
- **Tile space only**: every position is `MM.Pos { inst, col, row }` (docs/atlas-data.md).
  Game converts world yards and uiMap coordinates once, with Atlas.
- **nil / false / {}**: nil is unknown (unread, unreadable such as your position in an
  instance, or a failed read): keep the last belief. `false` is known none (no corpse,
  no waypoint). `{}` is known and empty.
- **Two cadences**: `you`, `group`, `minimap`, `blips`, `hooked` are per frame. Game may
  reuse and mutate those tables, so Model copies what it keeps. Every other part is a
  snapshot handed over on change and never mutated afterwards. A new table means the
  part changed, so Model compares by identity, which costs nothing when nothing changed.
- **Time**: `obs.frame` (Runtime.frames), `obs.t` (GetTime) and `obs.epoch` (time()). Saved times are `time()` (ADR 0004).
- **Oracles** are functions Game backs that Model may call, only during the frame they
  were handed. Each one is a pure read of this frame's state, never errors (nil instead),
  never yields, and states its cost. v1 has one, `Inside(quest, col, row) → boolean|nil`
  (nil means the game has no area, so Model estimates one).
- **Blip forgetting** needs to know a sweep finished and where: `blips.sweep` counts
  completed sweeps, and `center` and `reach` say what the last one covered.
- **Hooked keys** (M, Escape) ride along as `obs.hooked` and Model passes them on to UI
  unchanged (ADR 0003). This keeps the rule that UI reads only Model and View.

Locked: the call and its timing, tile space, nil/false/{}, the cadences and the identity
rule, part names and the meanings given, and the oracle rules. Open: how Game reads each
part (events, polls, sweeps, slices), new optional fields, new parts (Model ignores
unknown ones), and new oracles.

## Consequences

- Model can be tested headless by feeding it observation tables. No WoW API is needed.
- Game holds the only caches of game state. Model holds beliefs (what it merged and
  remembers), which is not the same thing.
- `you.inst` comes from GetInstanceInfo, not UnitPosition, so instances still know which
  map you're on with `col`/`row` nil.
- No WoW object crosses into Model. Portraits (textures) were going to cross as opaque
  handles; instead UI asks Game with a `tooltip` Command carrying the NPC and Game draws
  the portrait into the tooltip (ADR 0003). `portraits` is not an Observation part.
- Model has no clock, so `obs.epoch` (time()) is what it stamps saved things with (ADR 0004).
- Identity-compare means Game must build a new table to signal a change. That garbage
  only appears on change, never per frame.
- OPEN additions (v1 plan M1): `minimap.homeStrata`, the cluster's strata, beside `home`
  (M1.6), and `home` is kept: a new table only when the spot moved, so UI may hold it.
  `you.zone` and `you.subzone`, the client's names for where you are (GetZoneText,
  GetSubZoneText: the title names the inn, not the chunk's area, as the spike did).
- OPEN addition (v1 plan M2.3): `you.trivialRange`, UnitQuestTrivialLevelRange("player"): how
  far below you a mob's level turns grey in a quest tooltip (the spike's QuestInfo.lua:191).
  Model has no WoW API, so Game hands it each frame; nil: 5, the spike's fallback.
- OPEN addition (v1 plan M2.4): `ObsQuest.tag`, GetQuestTagInfo's `tagName` (nil when none or
  empty), and `ObsQuest.group`, GetSuggestedGroupSize (nil when 0), for the quest tooltip's facts
  line ("Elite", "Group (3)": the spike's QuestInfo.lua:321-325). Part of the quest's value: a
  change makes a new `obs.quests`.
- OPEN additions (v1 plan M2, its review's round 1): the oracle `HasArea(quest) → boolean|nil`,
  whether the game draws an area at the quest's pin, its own or another of your quests' on its
  map (the spike's hasBlob, Layers.lua:928-937), and nil, apart from false, for "can't tell yet"
  (not yet drawn into a laid-out rect, or the frame's asks spent): Model asks again next frame and
  estimates only on false. `Inside`'s nil still means both, so a late answer had made an estimate
  final. And `ObsQuest.poi`, the QUEST_POI_UPDATEs Game has seen (nil: none): part of the quest's
  value, so the game's areas changing makes a new `obs.quests` with every quest new (Model asks
  HasArea again, UI draws the areas again), as the spike's refresh re-laid them all out.
- OPEN addition, revised (v1 plan M2, its review's round 2): `poi` moves off each quest onto the
  list (`obs.quests.poi`, as `MM.Route`'s flags: still an `MM.ObsQuest[]`), so a QUEST_POI_UPDATE
  makes a new list of the same quests: Model asks HasArea again and UI draws the areas again, but no
  entry, look or pin is remade (it had been ~110 KB a POI update with 25 quests). Game reads where
  the pins are (every zone's GetQuestsOnMap) only when they may have moved: QUEST_ACCEPTED,
  QUEST_REMOVED (Forever sends the quest id: Questie's EventHandler.lua:157-193), QUEST_POI_UPDATE,
  the instances, a quest done or a count changed; and quests to pick up only after QUEST_ACCEPTED,
  QUEST_REMOVED, a level, QUESTLINE_UPDATE or tracking (not every QUEST_LOG_UPDATE, the spike's).
- LOCKED clarification (v1 plan M3, its review's round 1; recorded at round 2): `obs.waypoint`'s
  false is "no waypoint Model can place": none, or one on a map Atlas hasn't (no tile position to
  hand). Whether one is set at all is `waypointSet` (below), so the right-click menu offers Clear
  waypoint from it, as the spike's HasWaypoint (Layers.lua:2080-2081). types/core.lua's nil/false
  example points here.
- OPEN additions (v1 plan M3, its review's round 1): `waypointSet`, beside `waypoint`: a user
  waypoint is set, wherever it is (C_Map.GetUserWaypoint() ~= nil). `levels`, a new part: each
  map's level range as the client gives it (C_Map.GetMapLevels), read once for the maps Atlas has,
  for the inspector's level line (the spike's ZoneInfo.lua:58-69; Atlas's subzone exploration
  levels were another source: Elwynn 5-10, Dun Morogh 4-56, against 1-10).
- OPEN, revised (v1 plan M3, its review's round 2): `Inside` answers from the quest's own drawn
  area wherever it lies, not only when it covers the quest's pin: false where it isn't, and false
  everywhere for an areaMap the game draws nothing on; nil only while it can't tell (not yet drawn
  into a rect the client laid out, the frame's asks spent) or for a quest with no areaMap. As the
  spike's AreaTarget tests the followed quest's own frame (Layers.lua:1099-1155), so a quest whose
  area lies off its pin is gone to the area's edge, and you're inside it there.
- LOCKED clarification (v1 plan M1): `ObsBlip.rough` was "measured while moving: a few yards
  off". Its meaning stays what Model relies on: the position wasn't measured, so don't keep it
  or merge on it; it's measured once you stand still (M1.5 measures only then). How far off a
  rough one is belongs to the sensor (OPEN, non-binding: today up to a square, ~12 yd at the
  widest zoom, plus the client's lag), not to the contract.
- OPEN additions (v1 plan M4, wave 1): `ObsVignette.target`, the rare you target (M4.1, Landmarks.lua:
  154-156), at your position, its `id` the unit's GUID: Model remembers it as a seen rare and lists no
  live pin for it (M4.3). `ObsArt.outline` while `/mma indoor` is on (M4.2: UI outlines the art), and
  `ObsMinimap.indoorDebug`, the same flag for the gear's Indoor maps box (M4.5), since UI can't read
  SavedGame. `ObsTracking.id` without a filter is its spell's ID (M4.1: Find Herbs).
- OPEN addition (v1 plan M4, its review's round 1): the part `exploredCells`, per continent swept, its
  0.2-tile cells lit or dark as the client answers at each (Layers.lua:1334-1348): the spike shades per
  spot, and an area named explored somewhere isn't explored everywhere (overlays' rects overlap; the
  zone's own wilderness has none). `explored` stays per area, true only for the areas the client names.

## Revisit if

- A part changes so often that rebuilding its snapshot shows in `/mma perf load`. Then make it
  per-frame-mutable and add a `rev` counter.
- Model needs more than a few oracle calls a frame (e.g. shading every quest area). Then
  have Game hand the result over as data instead.
- A second client or flavor appears with different sources for the same parts. The shape
  should hold, and only Game's readers change.

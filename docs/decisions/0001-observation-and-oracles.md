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
- LOCKED clarification (v1 plan M1): `ObsBlip.rough` was "measured while moving: a few yards
  off". Its meaning stays what Model relies on: the position wasn't measured, so don't keep it
  or merge on it; it's measured once you stand still (M1.5 measures only then). How far off a
  rough one is belongs to the sensor (OPEN, non-binding: today up to a square, ~12 yd at the
  widest zoom, plus the client's lag), not to the contract.

## Revisit if

- A part changes so often that rebuilding its snapshot shows in `/mma perf load`. Then make it
  per-frame-mutable and add a `rev` counter.
- Model needs more than a few oracle calls a frame (e.g. shading every quest area). Then
  have Game hand the result over as data instead.
- A second client or flavor appears with different sources for the same parts. The shape
  should hold, and only Game's readers change.

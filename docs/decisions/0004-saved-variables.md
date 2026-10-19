# 0004 SavedVariables: one root, a part per owner, each versioned

Status: accepted (v1). Types: [types/saved.lua](../../types/saved.lua). The mechanism and
its failure cases are in [docs/runtime.md](../runtime.md) under "Saved data", implemented
by `Game.Load` in game/Game.lua.

## Context

Saved data is the only contract that outlives a release, because it sits on players'
disks. architecture.md says saved data belongs to the system that owns it and that Game
only loads and saves it. The spike had two account-wide SavedVariables: `MagicMapDB`, a
flat mix of window, camera, toggles, tracking and logs, and `MagicMapLandmarks`, with rares
and seen blips in world yards. Its migrations were one-off lines ("safe to drop after a
few releases").

## Decision

- **One account-wide SavedVariable**: `MagicMapAtlasDB`, which becomes `MagicMapDB` when
  merged into MagicMap. Its root is a table of owners: `Game`, `UI`, `Model`, `telemetry`
  and `validation`. Game leaves owners it doesn't know untouched.
- **Each owner declares its part**: `Game.Load(owner, fn, spec)` (Model's through
  `Game.Load("Model", Model.Load, Model.SAVED)`, ADR 0006; UI's through a `load` Command, ADR 0003), where
  `spec = { version, defaults, migrate(saved, from) }`. Game stamps the version on the part as `_v`.
- **The migration rule** is applied by Game before the owner sees its part, so the owner
  never sees garbage:
  - If the part is not a table, or `_v` is not a number, it is reset.
  - If `_v` is older (absent counts as 0), `migrate` runs. If it errors, the part is wiped.
  - If `_v` is newer (a downgrade), the part is left untouched on disk and the session
    runs on defaults that are never saved.
  - Any top-level key of the wrong type gets its default: a key the spec lists in `defaults`
    a copy of it, one it lists in `optional` (by type name) nil.
  - The loader is wrapped, so nothing fails past it.
- **Saved positions are tile space** (`col`, `row`, 3 decimals, by `inst`), and **saved times are `time()`**.
- **What each owner keeps in v1**:
  - Game keeps `trackingOff`, the tracking it turned off, restored after a /reload or
    crash, and `buttonAngle`.
  - UI keeps the window rect, `shown`, the small view's `zoom`, `follow` (with
    `inst`/`center` for when it isn't following), the layer toggles the user changed
    (a missing key means the layer's default), `minimap` (`"blizzard"` if the user
    chose it), `button` and `tint`.
  - Model keeps `rares[inst][key]` and `blips[inst][key]` (at most 5000 an instance since the D6
    amendment below; the oldest goes first).
  - telemetry is as described in docs/telemetry.md.
  - validation is the spike's log, until Validate.lua goes.

Locked: the root's shape, `_v` per part, the migration rule, tile space and epoch times,
and v1's field names and meanings. Open: what any owner adds in a later version, with its
`migrate` (or accepting defaults for it).

## Consequences

- A broken or alien save never crashes the addon. At worst one owner starts fresh.
- A downgrade never destroys data, because a newer part is kept as it is. The price is
  that while running an older build, nothing that owner does is saved.
- An owner with no `migrate` keeps whatever saved keys still have the right type. So adding
  a key costs nothing, but changing a key's meaning without changing its name or type
  needs a `version` bump and a `migrate`.
- telemetry and validation (unversioned until now) load as version 0 → 1 with their data kept.
- Nothing migrates from the spike's `MagicMapDB` / `MagicMapLandmarks`, so v1 starts
  fresh. See the open question about rares.
- Everything is account-wide, as in the spike.

## Revisit if

- Something must differ per character (for example, a window position per character).
  Add a per-character SavedVariable with the same owner/version rule rather than nesting by character.
- A part grows past ~1 MB. Blips and telemetry are capped, rares are not, so cap rares.
- The addon merges into MagicMap under `MagicMapDB`. If any spike data is worth keeping,
  write one migration then.

## Amendment 2026-10-18: seen blips, 5000 an instance (D6)

The user's decision D6 (docs/v1-plan.md §9): a cap high enough that most players never reach it.
`blips[inst]` holds at most **5000** an instance (was 200; the spike's MagicMapLandmarks held 300).
The meaning of every field is unchanged and 200 fits under 5000, so nothing migrates and `_v` stays 1.

- Size: a remembered blip is ~110 bytes on disk and ~0.25 KB in memory, so an instance at the cap is
  ~0.55 MB saved, ~1.2 MB loaded. Past the "~1 MB a part" line below only for a player at the cap on
  two or more instances; most stay at tens to hundreds (mailboxes and town services they've seen).
- Cost: model/Blips.lua buckets each instance's blips by 1/16-tile cell, so dedupe and forget look at
  a blip's neighbours only, and Known("remembered") (Focus's instance) changes only when what's
  remembered there does, not with each sweep. Only adding one past the cap walks the instance (for
  the oldest).

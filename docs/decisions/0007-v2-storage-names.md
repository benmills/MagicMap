# 0007 v2 storage names: MagicMap2DB

Status: accepted (2.0.0, M6.1). Amends [ADR 0004](0004-saved-variables.md)'s root name, a LOCKED
part. Types: [types/saved.lua](../../types/saved.lua). Decision D9 (docs/v1-plan.md §9, 2026-10-15).

## Context

At the rename (M6) the rebuild becomes the addon `MagicMap`, in the spike's own folder
(`Interface/AddOns/MagicMap`), so its SavedVariables file is the spike's:
`WTF/Account/*/SavedVariables/MagicMap.lua`. The spike kept two account-wide variables there:
`MagicMapDB`, a flat mix of window, camera, toggles, tracking, probe reports and the sensor's
`blipLog` (Blips.lua:192-206: up to 600 lines), and `MagicMapLandmarks`, rares and seen blips in
world yards (Landmarks.lua:13, Blips.lua:486: 300 blips an instance). ADR 0004 had planned to
become `MagicMapDB`; keeping that name would hand Game a root full of the spike's keys, which
aren't owners, kept forever and counted against our 64 MB.

## Decision

- **The root is `MagicMap2DB`** (TOC `## SavedVariables: MagicMap2DB`). Everything else in ADR
  0004 holds: a part per owner, `_v` per part, the migration rule, tile space, epoch times.
- **A fresh `_v`**: every part starts at version 1 under the new name, validation too (it was 2
  under `MagicMapAtlasDB` for its build stamp: same keys, nothing to migrate from). No `migrate`
  carries anything from `MagicMapAtlasDB`, which 2.0.0's TOC doesn't name.
- **The spike's data isn't read**: no code reads `MagicMapDB` or `MagicMapLandmarks`, and nothing
  migrates from them. The spike's rares and remembered blips, its window, camera and toggles are
  lost (accepted in D9). The other names follow the spike: slash `/mm` and `/magicmap`, the chat
  prefix `|cffffd100MagicMap|r: `, `MagicMap_OnAddonCompartmentClick`, and the frames
  `MagicMapFrame`, `MagicMapMinimapStandIn`, `MagicMapWorldMapEscape`.

Locked: the name `MagicMap2DB`. Open: as ADR 0004.

## Consequences

- The first login after installing over the spike runs the spike's file as the client always
  does, so `MagicMapDB` and `MagicMapLandmarks` sit in memory (in our addon's count) for that
  session; the client writes back only `MagicMap2DB` at logout, so from the next login they're
  gone. tools/tests/test_addon.py `test_spike_saved` loads a spike file at its caps
  (fixtures/spike_MagicMap.lua): ours fresh, the spike's rares not ours, the heap after a full
  collect under 64 MB, and after a /reload neither spike variable exists.
- A player going back to the spike gets a fresh spike (its variables were dropped); a 1.x
  `MagicMapDB` is never written by 2.x.
- tools/install.py installs into `MagicMap` and refuses while the spike is there (its TOC saves
  `MagicMapDB`) unless `--replace-spike`, which moves it to `MagicMap.spike-backup` first.
- tools/telemetry.py reads `MagicMap2DB` from `SavedVariables/MagicMap.lua`.

## Revisit if

- A later version must read the spike's rares after all: they'd need a one-off migration from
  a file the client no longer writes, so it would have to ship before most players' first logout.

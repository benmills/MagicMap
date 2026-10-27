# Hardening pass (late October 2026)

The beta is down for about a week, so this is a hardening pass checked in the sim and the web demo, not in game.
It starts from a five-part review (2026-10-24: pins, settings and saved state, clicks and menus, code health, tests)
and a map-quality probe (2026-10-27).

How we work:
- **Measure first.** Each problem gets a check (a sim invariant, a test, or a `tools/maplint.py` score) before its fix.
- **This file is the ledger.** A problem found while working becomes a row here, not a side fix.
- **Design notes come first** for the two big changes (the pin set, settings ownership). The user reviews each before
  it's built.
- **Each merge needs:** `tools/check.sh` green, plain and strict; its rows' checks green; a fresh reviewer agent's read
  of the diff; this file updated.
- **No look changes without the user.** The map-quality work proposes before/after images (overlays, the web demo);
  the user picks.

Status: `open`, `check` (a check exists and fails as it should), `fixed` (fixed, its check green), `wontfix`.

## Ledger

### P: pins (one thing, one pin)

| id | problem | evidence | status |
| --- | --- | --- | --- |
| P1 | A grouped pin draws alone beside its pill for up to 0.5 s after each blip update. | Cluster hides members by entry table (ui/Cluster.lua:167, 279); model/Blips.lua Live() makes new tables each sensor change; reproduced in the sim (5 pins + 2 pills for 0.4 s). | open |
| P2 | A remembered pin vanishes as you walk into the blips' range, until the sensor finds it. | ui/Blips.lua REACH is a fixed 220 yd; the sensor finds blips within ~208 yd outdoors, ~131 indoors (game/Blips.lua:338). | open |
| P3 | A blip within 8 yd of a quest objective's centre or a rare spawn is dropped even when that pin isn't drawn (zoom, layer off, grouping). | model/Blips.lua Ours/NearOurs. | open |
| P4 | Three different "same thing" distances (6, 10/18, 8 yd) in three places; no live-vs-live dedupe in Model. | game/Blips.lua SAME, model/Blips.lua SAME+LAG, NEAR_OURS. | open |
| P5 | Services draw beside their live blip between 220 yd and the sensor's edge (no carried check). | ui/Blips.lua:76-78. | open |
| P6 | Quests and offers share the key form `quest:<id>`: a tracked offer makes the quest pin glow once accepted. | model/Quests.lua:168, model/Offers.lua:43, Track.Is. | open |
| P7 | Layers swap canvases independently, so a pill and its members can be out of step for a few frames. | ui/Engine.lua:396-419. | open |
| P8 | Model decides drawing using UI's layer names and tracking (Focus.off, Focus.tracked). | model/Blips.lua:176-198, model/Rares.lua:55. | open |

### S: settings and saved state

| id | problem | evidence | status |
| --- | --- | --- | --- |
| S1 | Defaults are defined twice and the winning copy differs by setting. | Feel.lua KEYS vs Pins, Controls, Labels, Interiors, Path, Areas. | open |
| S2 | Settings pushed on the window's OnShow aren't pushed again when saved data loads. | Feel.lua:266-270; safe only while the window shows after the load. | open |
| S3 | One bad saved value (wrong type) stops the push for every setting after it; nothing is range-checked. | Feel.lua:266-270, Game.lua:55-59. | open |
| S4 | Grouping's tunables have the latent reload bug the tracking line had. | Cluster.lua tuneV. | open |
| S5 | `/mm layer rares` doesn't turn vignettes with it. | Engine.lua:808-811 vs Menus.lua:102. | open |
| S6 | Tracking only ends while some pin layer asks for redraws (Watch inside Track.Rev). | ui/Track.lua:71-88. | open |
| S7 | Reset and downgrade turn both replace options on (`fresh` false). | Game.lua:35, 44; Replace.lua:55-56. | open |
| S8 | The saved schema lives in three places and they disagree; migrations are done by hand outside `spec.migrate`. | types/saved.lua vs View.lua OPTIONAL; Replace.lua:51-61. | open |

### I: clicks, menus, tooltips

| id | problem | evidence | status |
| --- | --- | --- | --- |
| I1 | A quest area follows on click; its pin and the quest pill open a menu. | Areas.lua:386-391. | open |
| I2 | A click that closes a pill's grid also goes through (it can follow a quest or fly to a zone). | Cluster.lua:544-549, Window.lua:109. | open |
| I3 | Escape doesn't close the grid on the small map; on the big map one press can close several things. | Hooks.lua catcher, Cluster.Watch. | open |
| I4 | Ctrl- and Shift-clicks on a pin use the cursor position, not the pin's. | Window.lua:89, ZoneInfo.lua:238-249. | open |
| I5 | The quest tooltip says "Click to track" where a click opens a menu; Quests.lua's header and features.md are stale. | QuestTooltip.lua:25, 92. | open |
| I6 | The tracked pin's menu shows both Stop tracking and Clear waypoint. | Track.lua, Menus.lua:426. | open |
| I7 | Dead ends: no tooltip on a pill, the tracking pill, or the zone-count pill. | Controls.lua, Cluster.lua. | open |
| I8 | questlog.lua: C_QuestLog unguarded; Blizzard's quest panel may open under our big map; the fallback toggles. | game/commands/questlog.lua. | open |

### C: code health

| id | problem | evidence | status |
| --- | --- | --- | --- |
| C1 | Three hand-made ways of combining revs (sums, counters, `styleRev*1e9`). | Pins.lua:287, Quests.lua:42, Areas.lua:189, model/Blips.lua:185. | open |
| C2 | Copied helpers: colour presets, "first atlas the client has", the circle mask path (7 files), pill backings (2). | Controls, Pins, Art, Cluster, Menus. | open |
| C3 | ~530 comments cite the spike's file:line; the spike now lives only in git history. | e.g. Pins.lua "Layers.lua:304-400". | open |
| C4 | Shadow-prone names (glow, ring, Atlas, Track); luacheck has no shadowing warning. | the `glow` bug in 2.1. | open |
| C5 | docs/structure.md registries and the retired "Advanced" menu are stale. | structure.md; Cluster.lua:34 and others. | open |
| C6 | Engine, Runtime and Path each carry several jobs. | Engine.lua 820 lines; Runtime.lua diagnostics. | open |

### T: tests and tools

| id | problem | evidence | status |
| --- | --- | --- | --- |
| T1 | No check for one pin per real thing across layers; OnePin is per layer. | harness.lua:100-126. | open |
| T2 | Every blip test is outdoors in Goldshire with a perfect sensor. | test_blips.py. | open |
| T3 | `/reload` (PLAYER_ENTERING_WORLD false, true) is never simulated; no full settings round trip. | sim.py:121-123. | open |
| T4 | Tests assert pixel sizes and colours (TEST_LOOK pins the old look). | test_path, test_pins, test_quests. | open |
| T5 | The quest-log path is untested; the sim lacks both client shapes. | wowsim.lua. | open |
| T6 | No warning when the game ran an older build than the checkout; install.py needs the venv's Python. | install.py:147, telemetry.py. | open |
| T7 | No shared "what's drawn" dump (five tests each write their own). | test_blips, test_gear, test_interiors, test_pins, test_services. | open |

### M: map quality (tiles, borders)

| id | problem | evidence | status |
| --- | --- | --- | --- |
| M1 | Game data comes from two builds: Base from 70532 (the client's), the rest from 70450. Where 70532 has land that 70450 had as sea, the tile is skipped and the base picture shows as pale blocks (east Loch Modan, south of Blasted Lands). | Data/*.lua headers; Data/TileColor.lua sea keys (41,34..38), (42,31..39), (40,54..56). | open |
| M2 | Unfinished terrain: flat untextured land in the game's own tiles (east Loch Modan, north of the Plaguelands, the Hinterlands' coast, south-west of Dun Morogh, south of Blasted Lands). | probe: 3,568 flat land chunks in Eastern Kingdoms. | open |
| M3 | Zone borders wrap unplayable land the game assigns to a zone (Wetlands' east and west coasts, west of Dun Morogh). | screenshots 2026-10-27. | open |
| M4 | A few tile-edge seams. | probe: 5 of 1,402 edges with a jump over 3 times the tile's own variation. | open |
| M5 | No linter to score the map and ratchet it. | — | open |
| M6 | No shared place to review map issues: the user wants the linter's issues in the web demo, on the exe VM, each marked accepted / rejected / later, with notes, and the decisions readable by Claude. | user, 2026-10-27 | open |

## Log

- 2026-10-27: plan written; 2.1 work committed (60e3daf). Design notes proposed: ADR 0009 (the pin set), ADR 0010
  (settings ownership). Started in parallel: the sim checks (T1, T2, T3, T7) and the map linter (M1-M5).

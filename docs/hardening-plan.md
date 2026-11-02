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
| P1 | A grouped pin draws alone beside its pill for up to 0.5 s after each blip update. | Cluster hides members by entry table (ui/Cluster.lua:167, 279); model/Blips.lua Live() makes new tables each sensor change; reproduced in the sim (5 pins + 2 pills for 0.4 s). | check |
| P2 | A remembered pin vanishes as you walk into the blips' range, until the sensor finds it. | ui/Blips.lua REACH is a fixed 220 yd; the sensor finds blips within ~208 yd outdoors, ~131 indoors (game/Blips.lua:338). | check |
| P3 | A blip within 8 yd of a quest objective's centre or a rare spawn is dropped even when that pin isn't drawn (zoom, layer off, grouping). | model/Blips.lua Ours/NearOurs. | open |
| P4 | Three different "same thing" distances (6, 10/18, 8 yd) in three places; no live-vs-live dedupe in Model. | game/Blips.lua SAME, model/Blips.lua SAME+LAG, NEAR_OURS. | open |
| P5 | Services draw beside their live blip between 220 yd and the sensor's edge (no carried check). | ui/Blips.lua:76-78. | open |
| P6 | Quests and offers share the key form `quest:<id>`: a tracked offer makes the quest pin glow once accepted. | model/Quests.lua:168, model/Offers.lua:43, Track.Is. | open |
| P7 | Layers swap canvases independently, so a pill and its members can be out of step for a few frames. | ui/Engine.lua:396-419. | open |
| P9 | A remembered blip the sensor misses (not on the minimap until close) is forgotten by a sweep and stays gone until found again. Forgetting is right for a picked herb; wrong for a sensor miss. Design question for ADR 0009. Also: the reviewer found the missed blip, once on the minimap at about 100 yd, stays undrawn until you stop, so the sensor may not pick up new blips while you move: a second cause, to be split from P2 before the fix. | T2 [missed], 2026-10-27 | check |
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
| S9 | "Follow you" off doesn't hold: the idle return (ui/Motion.lua, as the MVP's) turns following back on after about 6 s, and it isn't kept across a reload. Is the setting meant to be "glide back when left alone" on/off? Ask the user. | found by T3, 2026-10-27 | open |
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
| T1 | No check for one pin per real thing across layers; OnePin is per layer. | harness.lua:100-126. | check |
| T2 | Every blip test is outdoors in Goldshire with a perfect sensor. | test_blips.py. | check |
| T3 | `/reload` (PLAYER_ENTERING_WORLD false, true) is never simulated; no full settings round trip. | sim.py:121-123. | fixed (passes: S2, S4 stay latent in the sim) |
| T4 | Tests assert pixel sizes and colours (TEST_LOOK pins the old look). | test_path, test_pins, test_quests. | open |
| T5 | The quest-log path is untested; the sim lacks both client shapes. | wowsim.lua. | open |
| T6 | No warning when the game ran an older build than the checkout; install.py needs the venv's Python. | install.py:147, telemetry.py. | open |
| T7 | No shared "what's drawn" dump (five tests each write their own). | test_blips, test_gear, test_interiors, test_pins, test_services. | check |

### M: map quality (tiles, borders)

| id | problem | evidence | status |
| --- | --- | --- | --- |
| M1 | Game data headers name two builds (Base 70532, the rest 70450). Corrected 2026-10-27: the 70532 data is byte-identical (headers only), and no skipped sea tile shows land in the game's art or the base picture, so this is *not* the pale-block cause. The pale blocks in the screenshots come from the hosted demo, which is the terrain lab (~/code/magic-map-lab: a separate renderer drawing all 3,322 ADT tiles), not this repo's demo or the addon. Still: regenerate from 70532 so the headers match the client. | maplint data check; linter report | fixed (every game-derived file regenerated from 70532: headers only) |
| M2 | Unfinished terrain: flat untextured land in the game's own tiles (east Loch Modan, north of the Plaguelands, the Hinterlands' coast, south-west of Dun Morogh, south of Blasted Lands). | probe: 3,568 flat land chunks in Eastern Kingdoms. | open |
| M3 | Zone borders wrap unplayable land the game assigns to a zone (Wetlands' east and west coasts, west of Dun Morogh). | screenshots 2026-10-27. | open |
| M4 | Seams: 0 tile edges by the linter; 6 colour blocks (worst 29,42 and 29,40, Dun Morogh's west coast). The demo's WebP export lifts dark sea from (5,7,7) to (8,17,16), so drawn sea tiles read paler than the backdrop in skipped ones (86 sea edges in the demo, 0 in game art). | maplint | open |
| M5 | No linter to score the map and ratchet it. | — | fixed (tools/maplint.py; check.sh ratchets its data scores) |
| M6 | No shared place to review map issues: the user wants the linter's issues in the web demo, on the exe VM, each marked accepted / rejected / later, with notes, and the decisions readable by Claude. | user, 2026-10-27 (built: demo/review.js, demo/review_api.py, tools/review.py, demo/lint/issues.json; the hosted demo's patch in demo/hosted/) | fixed (live on magic-map-outdoor.exe.xyz 2026-10-27; saving needs the token) |
| M7 | The hosted demo (magic-map-outdoor.exe.xyz: 2D/3D, both continents) is its own code on the VM, in no repo here; this repo's demo/ and the lab's are older forks. Its source is ~/magic-map-demo-refined on mills.systems (not the SRC_REPO infra's vm.env names); its demo/tiles and demo/terrain are symlinks, so `bin/deploy` from it would break the site. Changes go by patch (demo/hosted/) over `bin/vm-ssh`. | found building M6, 2026-10-27 | open |

## Log

- 2026-10-27: plan written; 2.1 work committed (60e3daf). Design notes proposed: ADR 0009 (the pin set), ADR 0010
  (settings ownership). Started in parallel: the sim checks (T1, T2, T3, T7) and the map linter (M1-M5).
- 2026-10-27: merged tools/maplint.py and the 70532 regeneration (reviewed; fixes: the ratchet takes the data scores
  alone, the tests read the build from Data/Tiles.lua).
- 2026-10-27: the linter reported: flat land 3.66% of Eastern Kingdoms in 59 regions (worst SW of Dun Morogh, Eastern
  Plaguelands' north, Tirisfal, east Loch Modan, the Arathi coast); border wrap worst in Wetlands (16.7% of its
  outline), then Eastern Plaguelands, Arathi, Tirisfal. M1 corrected (see the row).
- 2026-10-27: merged the sim checks (T.Drawn, T.OneThing behind T.strictPins, P1 and P2's strict xfails, the reload
  round trip); reviewed, 229 passed + 5 xfailed. New rows S9, P9.
- 2026-10-27: built the map review (M6): issues drawn on the map and listed, Accept / Reject / Later with notes, saved
  on the server, read back by tools/review.py. Checked in this repo's demo and in the hosted demo's pages patched
  locally (proxied to the VM). The issues file is from the installed client's art (150 issues). New row M7.
- 2026-10-27: M6 deployed to magic-map-outdoor (targeted update over infra's bin/vm-ssh; marks in
  /var/lib/magic-map-outdoor; token in mills.systems:~dev/infra/secrets/magic-map-outdoor.env).
- 2026-10-28: reviewed the linter's 150 issues with the user on the hosted demo. Border slivers, colour blocks and
  border wraps were mostly false (they judged the outline data and mean colours, not what's drawn); fixed and merged:
  wraps and slivers judge the drawn lines (new kind border-fragment: The Great Sea's piece of Kalimdor's coast),
  colour blocks must jump at their own edges, dark green sea is water, skipped tiles skip edge stripes. 150 -> 99
  issues. M3: the drawn lines don't wrap Wetlands' coasts; that wrap is only the demo's hover outline. Flat land
  (M2) kept: no rule separates smooth natural ground from the filler, so those are rejected by hand.
- 2026-10-29: the user found stepped, chunk-aligned patches (pale and green squares east of Loch Modan) that no
  check caught: colour blocks are whole tiles, seams tile edges, flat land only the untextured filler. New kind
  patch-edge: straight hard colour edges along the chunk grid (33 issues; ~2 look benign). 99 -> 132 issues.
- 2026-10-29: Haiku agents marked the 101 open issues (50 accepted, 69 rejected, 21 later with the user's; the user
  takes the 21 later). Fixes, first pass: the user chose clouds for the broken art (M2, M4): the game's own
  fog-of-war puff (atlas "fogofwar", the adventure map's) stamped over each accepted flat-land, patch-edge, seam
  and sea-edge place (tools/gen_clouds.py -> Data/Clouds.lua; ui/Clouds.lua, laid out with the tiles on a frame
  of their canvas over the borders: a layer of its own held up the names, test_feel). 243 clouds in Eastern
  Kingdoms, 93 in Kalimdor. The sea edge's tile is black in Blizzard's own art, so drawing it wouldn't help: it's
  clouded. The Great Sea's piece of Kalimdor's coast joins Azshara (gen_borders.py FRAGMENT): no border round it.
- 2026-10-30: the user's look at the clouds. Thinner (a stamp's alpha 0.4, wider and fewer: 206 from 336), so the
  ground's colour comes through. No cloud at Solliden Farmstead (flat-land:0:29,28 rejected). The black sea tile at
  30,55 gets water of our own instead of a cloud (tools/gen_patches.py -> Textures/Patch0_30_55.tga, Data/Patches.lua,
  Atlas.TileArt): its neighbours' edge colours, smoothed across it. Blizzard's own seam east of it stays.
- 2026-10-30: a wash under the clouds: the colours of the ground round each covered place, smoothed across it, soft-edged
  (tools/gen_patches.py -> Textures/Wash*.tga, 16 of them, 884 KB; ui/Clouds.lua). Switches: Settings -> Map, "Clouds" and
  "Smooth broken ground" (Feel "clouds.on", "clouds.wash"), and two buttons on the hosted demo (demo/clouds.js).
- 2026-10-30: the broken art rebuilt, in place of the wash ("pure blur") and, by default, the clouds: guided image quilting
  (tools/gen_fill.py -> Data/Fill.lua; ui/Fill.lua draws each piece from Blizzard's tile, masked, toned). The terrain files show
  filler exactly (one painted texture a chunk): safe to spread over. New pieces are made by a job after the layout, masks parked
  with their pieces, none far out: the budgets hold (231 passed). Switches: Settings -> Map, the demo's buttons; clouds off.
- 2026-11-02: clouds removed, the user's call: not a direction to go down any more (ui/Clouds.lua, Data/Clouds.lua, tools/gen_clouds.py, the switch, the demo's). What others used of the tool is in tools/mmtools/mapgrid.py; the demo's map art is demo/mapart.js, the sea tiles' water demo/export_patches.py. The entries above stay as they were. Whole-map pictures: tools/gen_fullmap.py -> demo/fullmap/<map>_raw.png, _fixed.png (gitignored: Blizzard's art), same frame; Eastern Kingdoms and Kalimdor, the only continents in Data/Tiles.lua.

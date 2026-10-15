# Play-test kit

Every gate (docs/v1-plan.md §6) is judged from one scripted session in game, read with
`tools/telemetry.py` (docs/telemetry.md). This page is the scripts: what to do, where to mark,
which shots to take. Play time is the plan's critical path, so each script batches a gate into
one sitting.

## Every session

Before:

1. Install the build: `.venv/bin/python tools/install.py`. If it says files were **added**
   (a new texture, a new Lua file), quit and restart the client: `/reload` doesn't see new
   files (spike-bugs L5).
2. AddOns list: **MagicMap (the spike) off** (both hook ToggleWorldMap and take over the
   Minimap), MagicMapAtlas on, every other addon off unless the script names it. The one
   exception is the reference session (below): the spike only.
3. Log in where the script starts. Wait **10 s** before doing anything: the login grace (5 s)
   and the memory read after it (`ourKBLoad`, a full collect: one graced hitch, tens to hundreds
   of ms, ~10 s after every login and `/reload`; expected, don't mark it).
4. `/mma check clear` (the log is this session's), then `/mma check log`: a toggle that says
   which; run it again if it says `off`. It stays on, across `/reload` too: don't toggle it again
   during the session.
5. `/mma telemetry`: note the session number it prints; tell the lead.

During:

- **Marks**: `/mma mark <script><step> <what you saw>` (e.g. `/mma mark a5 tear at the inn`), the
  moment something looks or feels wrong: a hitch, a tear, a pin in the wrong place, missing art.
  A mark keeps the last 300 events and the last 120 frames of camera and position (2 s at
  60 fps), so mark right away, not after walking on. The script's own marks are listed per step.
- **Shots**: `/mma shot <id> [note]`, the id first (the reference shot list,
  docs/evidence/shots/README.md), at the spot, zoom and form its row gives. The mark stamps zoom,
  camera, window and UI scale; the reader pairs it with the spike's `docs/evidence/shots/ref-<id>.jpg`.
  Print Screen alone takes no mark.
- Don't `/reload` unless a step says so: each `/reload` ends a session (and writes it).

After:

1. `/reload` (or log out): SavedVariables are written only then. Leave the check log on.
2. `.venv/bin/python tools/telemetry.py --budgets --trace > session.txt` and
   `.venv/bin/python tools/telemetry.py --shots --marks`.
3. Give the lead `session.txt` and the shot list's ids you took. The lead triages: every FAIL
   names an owner (perf.alloc, the worst-frames ledger, gaps, ourKB after GC, per-state
   histograms, a mark's motion ring).

## M0 gate session (~5 min, Dun Morogh)

M0 changes nothing visible; this session prices the client so M1's fixes aim at measured costs.

| # | Do | Mark / shot |
|---|---|---|
| 1 | Every session's "before" at the Kharanos inn (Dun Morogh, uiMap 1426). Map closed. | — |
| 2 | `/mma bench regions`, standing still. It hitches while it runs (expected); wait for it to print its result. Once only. | — |
| 3 | `/mma check art`. Expect no misses; each one prints and is traced (`art`). | `/mma mark m0 art` if it named a miss |
| 4 | `/mma map` (it opens following you; right-click follows again after a drag). Wheel in a tick at a time to the closest zoom, then out to the farthest, then back to the default. | `/mma mark m0 wheel` |
| 5 | At the closest zoom (1024 today), walk west to east through Kharanos for **2 minutes**, crossing the col 33 tile edge (it runs through Kharanos: the play-test's tear) several times. Watch for a tear. | `/mma mark m0 walk` at ~1 min; `/mma shot small-seam` while crossing the edge; `/mma mark m0 tear <what>` the moment you see one |
| 6 | Drag the map away (follow off), fling it a few times, let it settle; right-click to follow again. | `/mma mark m0 fling` |
| 7 | Every session's "after". | — |

The lead writes `docs/evidence/perf-m0.md` from it: the ~20 µs/region price (bench), the top
allocator (perf.alloc: `game.part blips` against `model.observe`), the swap costs (stats
`swap <layer>`: ms, live) and gaps, ourKB after GC.

## Script (a): Dun Morogh motion (M1, M5)

Start: every session's "before" (spike off, `/mma check log` on) at the Kharanos inn; the map
small on the Minimap's spot, follow on, default zoom.

| # | Do | Mark / shot |
|---|---|---|
| a1 | Open: if the map is hidden, `/mma toggle`. First open of the session. At the Thunderbrew door, cursor off. | `/mma shot small-home` |
| a2 | Wheel in a tick at a time to the closest zoom, then out to the farthest, and back: 4→1024→4 today (16→800→16 once M1.8 has the spike's range). Then the same as fast as the wheel turns. | `/mma mark a2 wheel` |
| a3 | Fling: drag-pan fast in several directions, release, let it settle each time. | `/mma mark a3 fling` |
| a4 | Zoom to the closest (1024), small, follow on. Walk for **2 minutes** through Kharanos, crossing the col 33 tile edge (it runs through the village) several times. | `/mma shot small-seam` on the edge; `/mma mark a4 tear <what>` on any tear |
| a5 | Grow and shrink ×5 (M, or the red button): let each animation end. | `/mma mark a5 grow` after the 5th; `/mma shot big-home` once as M lands, cursor off |
| a6 | Walk or ride into Ironforge (uiMap 1455), The Commons. Small at the default zoom, then big. | `/mma shot small-indoor`, `/mma shot big-indoor` |
| a7 | Big map: zoom out to the continent (4–24 px/tile) and pan over the Eastern Kingdoms. | `/mma shot big-continent` (all the way out); `/mma mark a7 continent` |
| a8 | Shrink. Every session's "after". | — |

## Script (b): a 25-quest hub (M2)

Start: every session's "before" (spike off, `/mma check log` on) at a quest hub with your log
full (25, or the log's cap), several objectives in view: for a Dun Morogh character, Kharanos with Coldridge and Kharanos quests; else Goldshire (Elwynn, 1429)
or Sentinel Hill (Westfall, 1436). Some quests complete (turn-in), some offers (`!`) nearby.

| # | Do | Mark / shot |
|---|---|---|
| b1 | `/reload` at the hub (so the next open is the session's first), then the 10 s wait. | — |
| b2 | Open the map small at the default zoom: the quest-heavy first open (≤50 ms). | `/mma shot small-quests` |
| b3 | Hover five quest pins: kill, collect, a complete one (turn-in), an offer, a followed one. | `/mma mark b3 tooltips` |
| b4 | Click a pin: it's super-tracked in Blizzard's tracker; click again: off. Click a quest area (blob). | `/mma mark b4 follow` |
| b5 | Wheel 60 → 140 → 384 and back: blobs hide while zooming and come back at settle. | `/mma mark b5 zoom` |
| b6 | Walk into a quest area; `/mma check inside` there; walk out. | `/mma mark b6 inside` |
| b7 | Big map, wheeled until the quest areas fill it: areas and estimates. | `/mma shot big-quests` |
| b8 | Every session's "after". | — |

## Script (c): route, corpse run, keys in combat (M3)

Start: every session's "before" (spike off, `/mma check log` on) in a zone with a followed quest
whose area is off the view (Dun Morogh or Elwynn).

| # | Do | Mark / shot |
|---|---|---|
| c1 | Follow the quest (click its pin): the route line and, when off view, the edge arrow. | `/mma shot small-edge-arrow` |
| c2 | Ctrl-click the map: a waypoint, route to it. Ctrl-right-click: cleared. Shift-click: a `/way` line in the chat box (not sent). | `/mma mark c2 waypoint` |
| c3 | Die (pull mobs well above your level), release. Corpse run along the route; resurrect. | `/mma shot small-corpse` while a ghost, small; `/mma mark c3 corpse` |
| c4 | Get into combat (attack a mob and stay in combat). In combat, once each: M (grow), Escape (shrink), L (Blizzard's quest log opens), `/mma toggle` twice (Blizzard's minimap back, then ours). | `/mma mark c4 combat keys` |
| c5 | Out of combat: the same four again. | `/mma mark c5 keys` |
| c6 | Every session's "after". Taint must be 0 (`--budgets` gate). | — |

## Script (d): capital, indoors, party, toggles in combat (M4)

Start: every session's "before" (spike off, `/mma check log` on) in Stormwind (1453) or Ironforge,
in a group of two if you can (a friend or an alt).

| # | Do | Mark / shot |
|---|---|---|
| d1 | Walk the capital's trade district with tracking on (mailbox, trainers, flight master): services and blips. | `/mma shot small-town` (the reference is Kharanos: compare services and mailbox, not the town) |
| d2 | Gear menu: toggle every layer off and on, small and big. | `/mma mark d2 gear` |
| d3 | Enter a building or a cave: indoor art, or Blizzard's floor plan; `/mma indoor` cycles them. | `/mma shot small-indoor` |
| d4 | Party: walk apart from your partner; have them die and release (dot grey). | `/mma shot small-group`; `/mma mark d4 party` |
| d5 | In combat: open the gear menu and toggle tracking, a layer, the minimap button. | `/mma mark d5 combat toggles` |
| d6 | `/reload` mid-session: tracking comes back as it was (this starts a second session: read both). | `/mma mark d6 after reload` |
| d7 | Every session's "after". | — |

## Script (e): continent zoom with Questie and GatherMate (M4, M5)

Start: every session's "before" (spike off, `/mma check log` on) with Questie and GatherMate2
enabled (the only other addons), in Elwynn Forest.

| # | Do | Mark / shot |
|---|---|---|
| e1 | Big map, zoom out to the continent (4–24) and back into Elwynn at 140, then 384: their pins on our map, skipped past 48 px/tile and over 128 px. | `/mma shot big-addon-pins` at 140, big |
| e2 | Shrink: their minimap pins around you on the small map; Rotate Minimap on (Interface options): hidden; off again. | `/mma shot small-addon-pins` before Rotate; `/mma mark e2 minimap pins` |
| e3 | Close ours and open Blizzard's world map: their pins are back on it. | `/mma mark e3 pins returned` |
| e4 | Every session's "after". | — |

## Shots

A shot's id is a row of the reference list, docs/evidence/shots/README.md (M0.8): the spike shot
once at that spot, zoom and form, saved as `docs/evidence/shots/ref-<id>.jpg` by tools/refshots.py.
The reader pairs `/mma shot <id>` with it (`telemetry.py --shots`). Take a shot standing still,
cursor off unless the row says otherwise, at the row's zoom: the spike's units (16..800 a tile)
until M1.8 adopts them, so before then the closest zoom stands in for 800 (1024 today). The stamp
records the real zoom, camera, window and UI scale.

The scripts take these (the rest of the list is for M5's full pass):

| id | Script | Look at | Gates |
|---|---|---|---|
| small-home | a1 | tiles, colour match, borders, labels, title, chrome | M1, M5 |
| small-seam | M0 5, a4 | tear, tile seam on the col 32\|33 line | M0 (baseline), M1, M5 |
| big-home | a5 | big map as M lands, controls | M1, M5 |
| small-indoor | a6, d3 | the city / indoor art or floor plan | M1, M4, M5 |
| big-indoor | a6 | big map in a city | M1, M5 |
| big-continent | a7 | continent: tiles, zone labels | M1, M5 |
| small-quests | b2 | quest pins, difficulty, counts | M2, M5 |
| big-quests | b7 | quest areas, estimates | M2, M5 |
| small-edge-arrow | c1 | route ink, edge arrow | M3, M5 |
| small-corpse | c3 | corpse pin, route | M3, M5 |
| small-town | d1 | services, mailbox, blips | M4, M5 |
| small-group | d4 | party dots | M4, M5 |
| big-addon-pins | e1 | borrowed world pins | M4, M5 |
| small-addon-pins | e2 | borrowed minimap pins | M4, M5 |

## Reference session (M0.8, the spike only)

Once, with MagicMap on and MagicMapAtlas **off**: docs/evidence/shots/README.md has the steps and
the list, and `tools/refshots.py` names the screenshots `ref-<id>.jpg`.

# What the client charges: the M0 gate

The M0 gate's numbers (docs/v1-plan.md §6 M0 exit): the client's prices from `/mma bench regions`,
the swaps and allocation of real play, the owner of every FAIL and the package that fixes it. The
sim's priced clock (tools/tests/wowsim.lua `Sim.PRICES`) is set from this page.

Sources: telemetry sessions on build 1.60.1.70450 (`tools/telemetry.py --budgets --trace`,
`--compare 4 5`), the client's `Logs/gx.log`. The spike disabled throughout.

| Session | Version | Frames | Where | What |
|---|---|---|---|---|
| #4 | 0ad5a54 | 62,298 | Silverpine Forest, Hillsbrad Foothills | ~15 min of play: small, big, zoom, drag |
| #5 | d088282 | 20,029 | Hillsbrad Foothills (Tarren Mill) | the M0 gate session (~5 min): `/mma bench regions`, `/mma check art`, the M1 wave 1a check; marks `wheel` (f12439), `grow` (f18184) |
| #6 | d088282 | 7,426 | Tarren Mill | ~4 min standing, small; the client in the **background** its first 4 min (gx.log 17:19:01 → 17:22:54): not a pricing source |

0 errors and 0 taint in all three. Load 100-106 ms, first open 3.5-5.3 ms, ours after a full
collect 38.4-39.4 MB at logout (37.6-38.5 at load): PASS, each with room.

## The bench (session #5, `/mma bench regions`)

µs a call, timed alone; a canvas op over 100 live, 1000 live or 1000 hidden child Lines, its µs a
child after the slash. The bench's lines are clear (an alpha-0 colour) and never re-anchored: it
prices the call itself.

| Op | µs | | Canvas op | 100 live | 1000 live | 1000 hidden |
|---|---|---|---|---|---|---|
| CreateTexture | 1.64 | | Show | 1.51 / 0.015 | 20.21 / 0.020 | 3.88 / 0.004 |
| CreateLine | 1.70 | | Hide | 1.46 / 0.015 | 20.14 / 0.020 | 4.58 / 0.005 |
| CreateFontString | 0.86 | | SetScale | 0.67 / 0.007 | 8.14 / 0.008 | 10.44 / 0.010 |
| SetPoint | 0.31 | | SetAlpha | 0.45 / 0.005 | 4.22 / 0.004 | 4.41 / 0.004 |
| SetStartPoint | 0.41 | | SetPoint | 0.20 / 0.002 | 0.91 / 0.001 | 0.84 / 0.001 |
| SetParent park | 0.22 | | | | | |
| SetParent unpark | 0.70 | | | | | |

So a canvas's own calls are nearly free per child: SetScale on 1000 lines is 8 µs, not 20 ms
(spike-bugs P4's 1.4 ms/frame was the client's frame, not the call), and hidden children cost
~0.004 µs each, not 20 µs.

## The ~20 µs a region: confirmed, for what a swap shows

The swaps (stats `swap <layer>`, the worst-frames ledger, the marks' layouts) put it where the bench
can't: showing a canvas whose regions were laid out anew while it was hidden.

| Layer | Swap ms / live | µs a region | Where |
|---|---|---|---|
| borders | 116.1 / 2418, 113.6 / 2457, 108.5 / 2508 | 45-48 | #5 ledger f9951, f9957, f9846 |
| borders | 174.1 / 3477, 115.4 / 2124 | 50-54 | #4 stats, ledger f47593 |
| borders | 8.06 / 231, 6.02 / 165, 5.03 / 147, 4.18 / 120 | 34-36 (0 ms at 0 lines) | #5 `grow` mark, f17002-f17006 |
| tiles | 24.3 / 887, 31.8 / 1190 | 27 | #5, #4 stats |
| rares | 12.9 / 696, 16.5 / 696 | 19-24 | #5, #4 stats |
| labels | 3.7 / 191, 4.8 / 194 | 19-25 | #5, #4 stats |
| blips | 0.88 / 54 | 16 | #5 stats |

- **Confirmed**: ~20 µs a texture or font string, ~35-50 µs a line, paid in the swap's `back:Show()`,
  which can't yield (ui/Engine.lua). The play-test's guess (docs/v1-plan.md §2) holds for this.
- **Corrected**: it isn't the canvas's Show, Hide or SetScale per se (the bench), and hidden pooled
  regions don't pay it. It's regions made visible after moving: the same 120 border lines and 8 tiles
  re-shown at the zoom that canvas last had (f17008, nothing moved) cost 0.91 and 0.72 ms.
- **Tiles' floor**: after a continent view, a tile swap costs 9-10 ms however few tiles show (6
  live 9.5 ms at zoom 800, the `wheel` mark; 8 live 10 ms, 59 live 10.5 ms, the `grow` mark). Likely
  the pool's mask textures: Engine.Get hides a pooled art texture, never its `mask` (ui/Tiles.lua
  MakeArt), so every mask ever made (~one per tile of the widest view) shows and moves with the canvas.
- **Bench gap** (M1.3, which picks the swap by bench): price a canvas of *visible* lines re-anchored
  while hidden, its Show at alpha 1 and at alpha 0 then SetAlpha 1, and textures with masks. Added by
  M1.3: `canvas.Show.moved@1000live`, `canvas.Show.moved.alpha0@1000live`,
  `canvas.SetAlpha.moved@1000live`, `canvas.Show.moved@100masked` (the next session reads them).

## Allocation: the sensor is the top allocator, confirmed

| Allocator (KB/s) | #4 | #5 | #6 (background, standing) |
|---|---|---|---|
| total | 372.9 | 538.2 | 237.2 |
| game.part blips | 296.7 | 261.3 | 233.1 |
| map: draw | 38.7 | 145.2 | — |
| map: borders | 20.6 | 75.2 | — |
| map: labels | 6.6 | 20.4 | — |
| map: tiles | 2.5 | 8.2 | — |

- **The sensor**: every probe makes ~0.35-0.4 KB, answer or not: 400-probe sweeps, ~1.9 a second in
  the foreground (#5: 261 KB/s ≈ 760 probes/s × 0.34 KB), ~1.5 standing in the background (#6: 395 B a
  probe). Blips answer at a few of a sweep's 400 points, so this is the client's TooltipData per probe,
  not our parse: M1.5's parse cache would save only the answers' strings. kbFrameP95 34-40 KB is the
  probing frames. At 0.35 KB, the 50 KB/s budget is ~140 probes/s for everything (a 400-point sweep
  every ~3 s); R-P3's 0.1 KB a frame (6 KB/s), ~17.
- **A probe's time**: a 400-probe sweep took 2 frames of ≤0.5 ms in the foreground (#5: 1.1-2.5 µs a
  probe, not the 0.1 ms the plan assumed) and 7-8 frames in the background (#6: ~8 µs).
- **map: draw** (second): 35 KB in each zoom frame (the spikes' `allocKb=35.08`): every chase frame
  starts a layout per layer (a Runtime.Job, its coroutine and closures, a region table, traces).
  **map: borders**: the per-segment tables of each of those layouts.

## The FAILs, their owners and the packages that fix them

Session #5 (the gate's), with #4 where it says more.

| FAIL (limit) | Measured | Owner (from) | Fixed by |
|---|---|---|---|
| frame p95 (1 ms) | 5.6 ms; zoom state p50 13.4, p95 20 (1,082 frames); drag p95 3.95; small 0.75, big 0.55 | every chase frame lays all 5 layers out again and swaps each (layouts f12240-f12255 at zooms 762→800, one a frame) | M1.3: rebuild only at settle or outside [0.7, 1.4] scale; borders held, then crossfaded; labels moved, not re-laid |
| frame p99 (5 ms) | 20 ms (#4: 15.05) | the same | M1.3 |
| frame max (8 ms) | 142.6 ms, f9951: swap borders 116.1 ms (2418 live) + tiles 14.4 (842) + rares 3.5 (200) + labels 1.3; #4 231.6 ms, f24955: `map: borders` 177.6 | the borders swap | M1.3: a swap that never shows a whole canvas in one call (the bench's pick), parked pools, masks hidden with their art; M1.4: 2 Lines a segment, the bands, cap 3000 (≤2418 lines → about half) |
| allocation (50 KB/s) | 538 KB/s: blips 261, draw 145, borders 75, labels 20 | the sensor's probes; a layout per layer per zoom frame | M1.5b: probe less (~140 probes/s for all of us); M1.3: no layout while the zoom moves; M1.4: no per-line tables |
| `perf.slow` (empty) | borders ×414 (120 ms), tiles ×309 (26.1), rares ×5 (13.5), draw ×2 (2.2), game.part blips ×2 (4.7) | the swaps; the blips part's 4.7 ms is a GC step paid by the allocator (#6's worst frames: blips 1.2-2.9 ms, standing) | M1.3, M1.4; blips: M1.5b |
| `perf.gaps` (empty) | borders 116.1 ms ×566, tiles 24.3 ×911, rares 12.9 ×25, each "(ran to the job's end)": the swap | the swap's single stretch | M1.3 |
| `art` (empty) | `redbutton-expand-c60`, `-pressed-c60`, `redbutton-highlight-c60`; `Fonts\MORPHEUS.TTF`, `Fonts\FRIZQT__.TTF` (each login and `/mma check art`) | ui/Art.lua lists the first name of a fallback chain (ui/Controls.lua draws `redbutton-expand`, the spike's fallback: Core.lua:281-310), and checks fonts with GetFileIDFromPath | M1.11: a miss only when no name of a chain resolves; fonts checked the way the client loads them |
| `sensor` (empty) | 12 at f20065-f20153 (the session's last seconds, after the `grow` mark): `{e=square px=4.51}`, then 11 × `{e=square px=8 n=4}` | the refined square fell to half the client's 8, then lone blips measured as four; no mark, so no state | M1.5b: find why (the window or Minimap scale at that moment), and a `sensor` trace takes a mark as `taint` does |
| rares at every zoom | swap rares 12.9 ms with 696 live at continent zooms | ui/Rares.lua draws every rare at any zoom; the spike from zoom 60 (§4 S50, Landmarks.lua:15-134) | M1.11: from zoom 60 (the icon, 137008 at 15, stays M2.1's) |

## The play-tester's findings

- **"Zooming in and out feels too sensitive."** The `wheel` mark's ring: a wheel event on every
  frame f12239-f12281 (one traced a frame, so 40 or more in 0.45 s) from one gesture, a trackpad's or
  Magic Mouse's inertial scroll. Each event is a ×1.3 tick (the spike's, Core.lua:14, 1418-1438), so
  one flick runs the target to the clamp; session 345b724's mark shows the same (f1878-f1917,
  114 → 1024). M1.8b: a lone tick stays ×1.3 (§4 S26), a burst counts by time, not by events; tried
  on the trackpad and on a wheel mouse (the user's call over the spike's code, D4).
- **`/mma shot` took nothing**: no screenshot written since 10-11 (`Screenshots/`), no `shot` trace,
  no taint (a blocked `Screenshot()` would be ADDON_ACTION_BLOCKED), no error; the sim's round trip
  passes (test_telemetry_sim). Not shown broken; most likely not run, and nothing in chat said either
  way. Now it says so: `shot <id>: WoWScrnShot_<stamp>, marked`, or that the client took none,
  answered or not in 5 s (game/Telemetry.lua; M1.11: every `/mma shot <id>` is answered by id). The kit lists every shot as a checklist (docs/playtest.md).
- **Marks without ids**: `wheel`, `grow` (the kit's `a2 wheel`, `a5 grow`); no `m0` marks.
- **The tear walk wasn't done**: the sessions were in Silverpine and Hillsbrad. The tear (mark
  "slight tear when moving", session 345b724) was at Kharanos on the col 33 edge; its re-check has to
  be there (docs/playtest.md).
- **The client in the background**: gx.log has the app going to the background 11 times in #5's
  last 3.5 minutes (the marks were taken between) and for #6's first 4; background frames run slower (a probe ~8 µs, not ~2) and
  don't show the swaps' cost. A gate session keeps the client in front.

## What the sim prices now

`Sim.PRICES` (tools/tests/wowsim.lua), all in ms, from the tables above: a probe 0.002; each
region a frame's Show makes visible 0.02 (a line 0.035); a frame's own Show 0.000004, Hide 0.00002,
SetScale 0.00001, SetAlpha 0.000004, SetPoint 0.000001 per region under it. One widget call costs
the counted clock's 3 µs (`Sim.Counted`), above every single call the bench priced (0.22-1.7 µs). A
probe that nothing answers makes 0.34 KB of garbage, as one that does.

With them the sim predicts the client: wheel-zooming, the layouts' slowest frames are borders 93 ms,
tiles 25, rares 13 (in game 116, 24, 13); the default window standing and walking allocates
263 KB/s, p95 40 KB a frame (in game 233-297 KB/s, p95 34-40 KB). What failed on them, each a strict
xfail until its package flipped it (all three pass since M1 wave 1b; Now: at the M1 gate, e50e7d5):

| Test | Failed on | Flipped by | Now (priced) |
|---|---|---|---|
| test_zoom.py::test_zoom_layouts_priced | each layer's slowest layout frame ≤ 8 ms while zooming | M1.3 abdddfe | tiles 4.6, borders 5.0, labels 2.2, rares 3.1 ms |
| test_blips.py::test_default_ui_alloc_priced | 50 KB/s and p95 0.1 KB a frame, the default window | M1.5b 92e5ddd | 14 KB/s over standing, walking and a door (e60ff51; ~5 before it), p95 0.1 KB |
| test_spike_bugs.py::test_replay[P3] | 0.1 KB a frame idle, walking, dragging; 0.5 walking among 10 blips | M1.5b 92e5ddd | 66 / 36 / 77 B; 64 B among 10 blips (p95 85) |

test_zoom_draw_priced (the draw step ≤ 2 ms while zooming, xfail since M1.8 on SetScale's guessed
20 µs a region) passes on the bench's prices: SetScale was never the cost. R-G6b's window hiding with
2400 pins hosted is 0.1 ms, not 112 (a Hide is ~0.02 µs a child); showing them is the price that
matters (~20 µs a visible region).

## After M1 wave 1b, in the sim

Every FAIL above has its sim fix merged (M1.3 abdddfe, M1.5b 92e5ddd, M1.8b 2ef936d, M1.11 40e4581),
each to be re-checked in the next session:

- **Frame p95/p99/max, `perf.gaps`** (M1.3): no layout while the zoom moves; a layer is laid out at
  settle or outside [0.7, 1.4]; the swap shows the fresh canvas by alpha (shown at 0, then
  SetAlpha) and yields; leftovers and their masks parked; layouts 4-5 ms a frame, swaps under
  0.5 ms on the priced clock; grow, shrink, the follow glide and the idle return 0 frames over 8 ms
  (R-P7). Canvas offsets under ~2800 px (the shared origin: the whole tile nearest the view's centre).
- **Allocation** (M1.5b, M1.3): the sensor ~5 KB/s in the default window; no layout per zoom frame.
  The flights still allocate 160-300 KB/s for the map while they run (R-P7: the layouts' own
  tables, mostly tiles and labels; M1.4's).
- **`art`** (M1.11): a chain counts if any of its names resolves, fonts are loaded to check them.
- **`sensor`** (M1.5b): one blip read as four corrected; a `sensor` event takes a mark.
- **Rares at every zoom** (M1.11): from zoom 60. At 60-75 a big window still holds ~500 of a
  continent's 696 (the layout region is the view plus a wide margin).
- **Wheel** (M1.8b, then round 2 of the M1 review): a bucket of 1 tick refilling 2 a second, a
  gesture 3 ticks at most; `/mma wheel` tried others. Stale since M1.14 (M1b, the user's play-test of
  M1: "the scrolling / zooming is still pretty broken compared to the MVP"): the wheel is the spike's
  again, every event a x1.3 tick, and the `wheel` cam trace shows what a device sends (delta, n, dt).

## The next session re-checks

The one consolidated play-test at the end of the run (D10), on M1.3, M1.4, M1.5b, M1.8b and M1.11
(its steps: docs/playtest-final.md):

- **8/8 budgets** in script (a) at Kharanos, client in front throughout: p95 ≤1 ms at rest, p99 at
  rest and the zoom and drag states' p95 ≤5 ms (docs/runtime.md since ebdf22e; the user confirms
  that reading), no swap over 4 ms (`swap <layer>` ms), `perf.slow`, `perf.gaps`, `art`, `sensor`
  empty; `map: draw` and `game.part blips` out of perf.alloc's top or under 10 KB/s each.
- **The tear walk** at Kharanos, col 33 edge, at 800, 2 minutes, with its marks and `small-seam` shot.
- **Every shot** of the script's checklist, each answered in chat.
- **`/mma bench regions`** again, with M1.3's visible re-anchored canvas ops: if
  `canvas.SetAlpha.moved@1000live` costs what `canvas.Show.moved@1000live` does, the alpha swap is
  wrong and the swap extends in place instead.
- **The wheel** on the trackpad and on a wheel mouse: one flick, one tick, ticks in a row; marked
  with the device (`/mma mark a2 wheel trackpad`).
- **The sensor's square**: if a `sensor` trace comes, its mark has the state (M1.5b). A herb shows
  within ~1 s of turning tracking on; blips met while riding become exact once you stop; a blip
  that appears while you stand still may take up to ~40 s (the slow pass).
- Allocation at ~140 probes/s or under, the blips still exact within 2 sweeps standing.

# Spike bugs against the new architecture

Every real failure the MagicMap spike (`~/code/MagicMap`, 123 commits, 2026-10-02..10-13) had, each
traced to the system or contract that owns it in architecture.md, with a verdict on whether the
new design deals with it.

Sources:
- **Commits**: every fix-like commit, plus feature commits whose diff is really a fix. Root causes
  come from the diffs, not only the messages.
- **Client logs**: `_classic_beta_/Logs/*.log`. General.log only covers the 10/14 22:18 session.
  FrameXML.log has one line from 9/26. AccountData.log has no errors.
- **Crash dumps**: `_classic_beta_/Errors/`. There are 11. None can be blamed on the spike; see the
  Appendix.
- **Docs**: README "Limits"/"Risks", `dist/RELEASE_NOTES-*.md`, and `tools/tests/scenarios.lua`
  (scenario names are cited as `scen:`).

Owners: Game, Model, UI, Atlas, Runtime, or one of the cross-system contracts: Observation, Oracle,
Focus, View, Commands, SavedVariables. "Tooling" covers the one row that no system owns: the
offline install check.

Verdicts:
- **PREVENTED**: the new design rules it out. That takes a boundary, an offline fact, or a step
  order.
- **CONTAINED**: it can still happen, but Runtime isolation or telemetry limits the damage and
  reports it.
- **MOVED**: the same risk remains, just in another place.

Replay column:
- **now**: the rebuild's `tools/tests/wowsim.lua` can drive it today. Every "now" row is replayed
  in `tools/tests/test_spike_bugs.py`, one `test_replay[<id>]` per row (linked in the cell); its
  docstring states the verdict it asserts, and `pytest -s` prints what it measured.
- **v1**: it can be replayed once the feature exists.
- **no**: the sim can't model it.

## The table

### Errors

| id | symptom | root cause | spike file(s) | evidence | owner | verdict: why | replay |
|---|---|---|---|---|---|---|---|
| E1 | `Layers.lua:1473: bad argument #2 to 'min' (number expected, got nil)`, every frame the view moved (2905, via `Core.lua:1556 → Fire("ViewChanged") → OnViewChanged → RequestGeometry:1930 → OfflineBorders`) and on title updates while hovering (75, via `Core.lua:1565 UpdateTitle:1323 → ns.ZonesInView:2004`) | **The rebuild caused it.** MagicMapAtlas defines the same data global, `MagicMap_Borders`. It loads after MagicMap (alphabetical order), so the spike's lazy `OfflineBorders` read the rebuild's table. The formats differ. The spike's lines are `{kind, a, b, fs, fe, x1, y1...}` and it takes points from index 6. The rebuild's lines are `{a, b, fs, fe, x1, y1...}`, so index 6 holds y1 and the coordinate count is odd. `pts[i + 1]` is then nil. Because `prepared` is never set, the read retries every frame. | Layers.lua:1463-1473, Core.lua | General.log: 2980 errors, 10/14 22:19:26-22:24:40. Installed spike = HEAD 0c71e2b (v1.0.0). AccountData.log shows `MagicMapAtlasMap` in the same session. | Atlas | **PREVENTED** (was MOVED; the replay changed it): Data/ now loads into the addon's namespace (`ns.Data`), so the rebuild sets no data global for the spike to read, and a spike-shaped `MagicMap_Borders` loaded after us is never read. The replay checks both, and that a malformed row in our own data is CONTAINED: the borders layout fails, is recorded once, and retries with a backoff, never per frame, while tiles and labels draw. Still open: `tools/telemetry.py` only keeps log lines naming `MagicMapAtlas`, so another addon's errors stay invisible to it. | now: [`test_replay[E1]`](../../tools/tests/test_spike_bugs.py) |
| E2 | Vignette and area-POI pins errored on every map change. Login aborted before the map was shown. | `local x, y = pos and pos:GetXY()`: an `and` expression is one value, so `y` was always nil, and `MapToTile` threw. The error was inside `SetMap`'s MapChanged handlers and nothing isolated them. | Landmarks.lua | 4a70b10 (found by the first smoke test). scen: boot | Observation | **CONTAINED**: `Runtime.Wrap` isolates the Game read, so login and draw run on, and telemetry records it once with its stack. The Lua idiom can still be miswritten in Game. Area POIs are now static (`Atlas.POIs`, Places.lua), so that half is PREVENTED. Live vignettes remain. | v1 |
| E3 | Route finding failed in the Barrens, so path mode fell back to a straight line. | Line-of-sight divided by a zero column/row count. Plain Lua gives `inf`, which the code then replaced. WoW's Lua raises "Division by zero" instead, so the sim and tests passed. | Route.lua (`Sight`) | e581d43 | Model | **MOVED**: Model and Atlas are plain Lua, tested in plain Lua (lupa 5.1), which still disagrees with WoW about `x/0`. A Runtime.Job would contain the failure (the route job dies, the line falls back), but nothing catches it before the game does. Bounded since M0.7: `tools/lint_div.py` (in check.sh) passes no `/` in atlas, model, game or ui whose divisor isn't a literal, a named constant or annotated `-- /: never 0 (why)`, and every test runs again strict (`MM_STRICT=1`: the sim's `x/0` raises, as the client's). | static: tools/lint_div.py; MM_STRICT=1 runs |
| E4 | Opening the map called a nil global when no addon brought LibStub. | 0415084 removed "guards for APIs Forever always has", but LibStub belongs to other addons, not the client. A cleanup regression. | AddonPins.lua | e1e13f3 (regression of 0415084). scen: addon_pins_without_libstub | Game | **CONTAINED**: Game owns "other addons", so the risk now lives in one place, and `Runtime.Wrap` isolates the scan. Nothing stops a missing guard (the replay would fail). | now: [`test_replay[E4]`](../../tools/tests/test_spike_bugs.py) |
| E5 | The whole addon failed to load: `Core.lua:254: function arguments expected near 'and'`. | Lua that doesn't compile was installed. This predates the repo, so the code can't be read. | Core.lua | FrameXML.log 9/26 23:09:13 (pre-911034b) | Tooling | **PREVENTED**: `tools/install.py` refuses to install unless `tools/luacheck.py` compiles every TOC file with real Lua 5.1. The same check catches the 200-locals limit, which Layers.lua was near (9a57bec). | static (test_luacheck) |
| E6 | The blip sensor could error every frame on an empty grid. The town-service gatherer swallowed its errors and, when QuestieDB wasn't ready, kept an empty list for the session. | `#grid == 0` was not handled. The coroutine result was dropped on failure. | Blips.lua | 7c21fec ("an empty grid can't error every frame", "reports an error instead of swallowing it") | Game | **CONTAINED**: a failing sensor step is caught per name and counted (Runtime.errors, telemetry), and a failing `Runtime.Job` is reported, not swallowed. The QuestieDB half is PREVENTED by G5. Replayed: radius 0 (a zoom applying) restarts the sweep and keeps what it knew; the empty grid is PREVENTED (the lattice is a square's width apart in the world, the square and the Minimap's side both in screen units): a look at every point probes the same 302 lattice points at UI scales 0.5 and 1.4. | now: [`test_replay[E6]`](../../tools/tests/test_spike_bugs.py) |
| E7 | One error stopped everything after it. E2 aborted the login handler. In E1, each of the 2980 errors also skipped the rest of the map's OnUpdate (arrow, hover, title) and every ViewChanged handler after Layers (addon pins). | `ns.Timed` timed callbacks but didn't `pcall` them (Profile.lua:10-18). `Fire()` ran handlers in a bare loop (Core.lua:55). | Profile.lua, Core.lua | 4a70b10; General.log stack (Core.lua:56 → Layers) | Runtime | **CONTAINED**: every Step/On/After/Every/Job is wrapped. A failure is caught with its stack, reported once, kept per name, and the rest of the frame runs. test_smoke checks this ("test.fails" ×60 and "test.after-fail" still 60). The replay found that a failed layout job froze its layer (`busy` never cleared); now fixed (ui/Map.lua `Failed`: retried after a backoff), and a step failing every frame walks one stack, not 60 a second. | now: [`test_replay[E7]`](../../tools/tests/test_spike_bugs.py) |

### Hitches and cost

| id | symptom | root cause | spike file(s) | evidence | owner | verdict: why | replay |
|---|---|---|---|---|---|---|---|
| P1 | Borders, and tiles with them, fell behind a fast pan: blank edges. | Every view change rebuilt borders from scratch, in small fixed slices, with nothing prefetched. Fixed with a prefetch margin, in-place extension at the same zoom, and bigger slices while behind. | Layers.lua, Core.lua | 25fe7dd, 47f7407. scen: borders_keep_up, tiles_seamless | UI | **CONTAINED** (was MOVED; M1.3 changed it): each layer is laid out in a `Runtime.Job` over the view plus a margin led by the camera's speed, a layer the view lacks first (5 ms a frame, else 4), and only once the zoom settles or leaves the [0.7, 1.4] band; the swap shows the fresh canvas by its alpha and yields, and what it no longer shows is parked. A fling faster than the replay's can still outrun it; `layout` and `swap` traces report it. Replayed (1.5 views/s, counted clock): every layer covers the view on 180 of 180 frames (asserted: borders ≥175, tiles ≥179), every layer fresh 1 s after stopping, no layout frame over 8 ms (the slowest 4.18 ms), each front canvas holding only its live regions and their masks; a 20-step zoom-out starts 16 layouts for 5 layers (borders 1; 33 before M1.3, the spike's ~44 for 4). The M0 gate's 108-174 ms border swap (docs/evidence/perf-m0.md) is now layouts of 4-5 ms a frame and swaps under 0.5 ms on the priced clock. M1.4 halved the borders' Lines (2 a segment, levels of detail by zoom, ≤4 dashes an end, ≤3000 a layout): the big window draws 325-1056 at zoom 16-100 (1428-4050 before), every borders swap 0.01 ms and every layout frame ≤5 ms priced. M1 review round 2: a 10 s pan at 800 and a zoom's jump (96 to 800) keep every offset on the map under 4096 px (the arrow kept by the view, a moved label off it), and the invariant fails if the shared origin stops moving. M1 gate (2026-10-18, e50e7d5): the sim's half met. M1b (M1.12 c31930f): the spike's in-place extension at the same zoom, pooled: a pan's layout takes back what its canvas showed (`Engine.Keep`) and sets only the ground it adds, ahead of a pan in 2.5 ms slices; R-P1 still 180 of 180 frames on every layer, the slowest layout frame 3.04 ms. In game: docs/playtest-final.md a3 (the fling), d1 (a city) and the session's read (no `map: borders` or `map: layout` in perf.slow). | now: [`test_replay[P1]`](../../tools/tests/test_spike_bugs.py) |
| P2 | Path routing peaked at 3.5 ms/frame against a 2 ms slice. | The A* coroutine checked the clock every 200 nodes, so a slice overran by up to 200 nodes. The fix: 1 ms slices, checked every 50 nodes. | Route.lua | f5644cc (bench path_far_ride) | Runtime | **MOVED**: `Runtime.Yield()` checks the budget only where the job calls it, so the same overrun is possible. `Runtime.Perf()` max per job does surface it. Replayed: yielding every 200 iterations gives a 4.0 ms slice against a 1 ms budget; every iteration, 1.0 ms. MOVED confirmed. | now (Runtime): [`test_replay[P2]`](../../tools/tests/test_spike_bugs.py), v1 (route) |
| P3 | Too much work and garbage every frame: 660 widget calls, 85 KB and 0.34 ms/frame riding; 222 calls/frame standing in minimap mode. | Several causes. Unchanged state was re-applied every frame. The title rebuilt strings and C_Map lookups 20×/s. The target was looked up many times a frame. Path dashes ran at 20 Hz. **`viewport:SetScript("OnSizeChanged")` replaced the hook that cleared the size cache, so it was cleared every frame.** | Core.lua, Layers.lua, Path.lua, MinimapTakeover.lua | f1491bd, 732070b, 5cc4395 (bench KB/frame) | UI | **CONTAINED** (was MOVED; changed with the fixes the replay drove): Runtime now measures allocation per frame (`kbFrameP95`, `kbPerSec` in FrameStats and the session's perf, budget ≤ 50 KB/s in docs/runtime.md and `telemetry.py --budgets`). The drag step no longer allocates a camera a frame, the arrow is re-applied only when it changed, and label layout no longer makes 6 tables per label. The replay holds a standing map to 0 setter calls on its widgets and ≤ 0.1 KB a frame, walking and dragging too (the frame after its full collect left out: it regrows the Lua stacks the collect shrank), and walking among 10 blips on the priced clock to ≤ 0.5 KB a frame. Nothing structural stops re-applying unchanged state, and a raw widget `SetScript` can still clobber a hook (P6's replay catches an unwrapped one). Map names now come from Atlas (UiMaps), so that part is gone. The M0 gate found the sensor the top allocator (233-297 KB/s): every probe makes ~0.35 KB of the client's garbage, answer or not, which the sim's probes now copy. M1.5b probes less (a slow discovery pass; a look at every point only when tracking changes, the window moves, combat ends or the view radius changes), and the replay passes: idle 66 B, walking 36 B, dragging 77 B a frame, among 10 blips 64 B a frame priced (p95 85 B, at the M1 gate); the default window 14 KB/s priced over standing, walking and a door (e60ff51). In game the sensor alone made 27-30 KB/s in sessions #8 and #9 (build cd0c82c, before e60ff51 and M1.4): the final session's `perf.alloc` decides it (`game.part blips` under 10 KB/s, docs/playtest-final.md's read). M1.4: a frame's deepest call can land a frame late (a timer's, by the counted clock), and its stack regrowth (250 slots, 3.91 KB) failed about 1 run in 4 strict; the replay now grows the main stack before it measures. M1b (M1.12 c31930f), from the user's sessions #13 and #14 in Orgrimmar (83.5 and 131.6 KB/s; a tile layout 225 KB in one call, a border layout 150-476 KB; the drag's frame p95 4.35 ms): a layout keeps what its canvas shows (`Engine.Keep`), tile masks only on coasts, title coordinates through SetFormattedText, a door keeps the sensor's circles, the validator's sample ~0. R-P3b, Orgrimmar big at four zooms with drags and the wheel, twice, then walking small through its doors, at the client's prices: 150.3 KB/s the first time (7065 regions made, kept in their pools; garbage 10.7 KB/s), 14.2 the second (155 layouts at 1.18 KB, their three traces), 20.3 walking, the drag's p95 2.75 ms. Left (docs/v1-plan.md M1b): Motion's camera a zoom frame, View, `model.observe`, Areas' tile decode, the traces' tables. In game: docs/playtest-final.md d1 and the read's `perf.alloc`. | now: [`test_replay[P3]`](../../tools/tests/test_spike_bugs.py), [`test_replay[P3b]`](../../tools/tests/test_spike_bugs.py) |
| P4 | Zooming cost up to 1,400 widget calls per frame. The "fix" then cost 1.7 ms per frame in the client. | First, every zoom frame laid every tile out again. 906666c instead scaled a tile frame while the zoom moved, and in the real client that measured 1.4 ms/frame just to move the canvas (it had been 0.008). b02d96a reverted it. The sim's call counts said the opposite. | Core.lua | 906666c → b02d96a (regression, reverted) | UI | **PREVENTED** (was MOVED; M1.3 changed it): no layout per zoom frame. While the zoom moves tiles `SetScale`, and borders too (dimmed, then crossfaded in 0.12 s as the zoom lands: since the M1 review, as the spike's); labels and pins move (`Engine.At`); a layer is laid out again only once the zoom settles or leaves [0.7, 1.4]. A swap shows or hides no canvas (the fresh one waits shown at alpha 0). Measured at the M0 gate (`/mma bench regions`): SetScale on a canvas of 1000 lines is 8 µs, so scaling wasn't the cost; each zoom frame's layouts and swaps were. Priced: every layer's slowest layout frame ≤8 ms while zooming (tiles 4.6, borders 5.0, labels 2.2, rares 3.1 ms at the M1 gate), the draw 1.50 ms of its 2. M1 review: the borders are scaled again while the zoom moves (the spike's look, parity S30): whether scaling thousands of Lines costs the client a frame is read in the final session from `byState.zoom.client` against `small`, and the bench's `frame.*`. M1.4: a borders swap 0.01 ms priced, at 325-1056 Lines in the big window at zoom 16-100 (1106-2751 at 140-300 with the subzone borders, under the cap of 3000). In game: the final session's `/mma bench regions` (docs/playtest-final.md a5b: SetAlpha.moved must cost far less than Show.moved, and frame.swap about frame.idle, or the swap extends in place instead). | priced: test_zoom_draw_priced, test_zoom_layouts_priced |
| P5 | Quest areas lagged and drifted while zooming. | The client's blob art doesn't follow a scaled canvas, so the spike hid areas mid-zoom and redrew them on settle. | Layers.lua | 720faf3. scen: quest_areas_follow_zoom | UI | **PREVENTED**: in v1 UI draws quest areas itself, and Game only senses `Inside(quest, col, row)`. None of the client's blob art is shown, so none lags. The sensing half is L1. | v1 |
| P6 | Where time went was invisible: the client profiler showed 0.31 ms/frame against the map script's own 0.12. `/mm perf top` said the profiler was "not available" when it was only switched off. | Timing covered only the map OnUpdate and the border builder. Hooks, events and timers weren't bucketed. | Profile.lua, Perf.lua | 694befb, 1a3fa18, 4f110f4, 816574e | Runtime | **CONTAINED**: anything registered through Runtime (Step/On/After/Every/Job/Wrap) is timed per name by construction. A raw widget script must be wrapped by hand (ui/Map.lua does). The replay now enforces it in the sim: every script and hook on a frame the addon made must be a `Runtime.Wrap` closure (`Runtime.Wrapped`); it found Runtime's own event dispatcher unwrapped (now wrapped). | now: [`test_replay[P6]`](../../tools/tests/test_spike_bugs.py) |
| P7 | While path mode eased the zoom, labels and quest areas were laid out again every frame. | `ns.IsAnimating()` and `Camera().animating` didn't include `pathGoal`. Three places derived "is the camera moving" and one disagreed. | Core.lua | 732070b | View | **PREVENTED** (was MOVED; R-P7 changed it): one flag decides layouts, `Camera.ZoomSettled` (ui/Camera.lua; `Camera.Settled` builds on it), read by every layer through Engine. Replayed: a wheel tick, a zone fit, grow, shrink, the follow glide and the idle return lay each layer out at most once moving and once settled (borders once, held), with no frame over 8 ms on the priced clock. M1.4: the map's allocation over the flights 61-125 KB/s (108-196 before; asserted ≤400): no per-line tables, tiles skip unchanged vertex colours, and the sim's SetVertexColor no longer makes garbage the client's doesn't (26-118 KB/s at the M1 gate, grow the most: its borders 70). M1 review round 2: every frame of an ease checks the borders scaled to the camera and dimmed by that scale (Layers.lua:163-167), crossfaded from the alpha they had, and no layout started on a canvas in sight (a crossfade ends first, Layers.lua:1853-1855; a drag mid-crossfade started 4 there); each layer lays out on one worker (a coroutine made once). | now: [`test_replay[P7]`](../../tools/tests/test_spike_bugs.py) |

### Drawing twice, and the Minimap as a sensor

| id | symptom | root cause | spike file(s) | evidence | owner | verdict: why | replay |
|---|---|---|---|---|---|---|---|
| D1 | Things were drawn twice, ours and Blizzard's: two "?" at a turn-in, the Minimap's quest-area rim rings floating mid-map, and Questie's HereBeDragons (HBD) minimap pins repeating and drifting beside ours. | The visible Blizzard Minimap sat inside our map and drew its own markers. Fixes kept flip-flopping between stepping ours aside and switching Blizzard tracking off; d41655c restored what 118571e had replaced. | MinimapBlips.lua, Layers.lua, AddonPins.lua | 4e9786d, 01fafa7, 118571e, 2accfc9, d41655c. Release notes 1.0.0 "No more doubled icons". scen: minimap_ours_first, addon_pins_minimap | Game | **PREVENTED**: in v1 Blizzard's Minimap is only a sensor. UI draws every pin from one store, diffed by id, and Game hosts other addons' HBD pins. Nothing of Blizzard's is meant to show; when it leaks anyway, that's D2. | v1 |
| D2 | Blizzard's sensor art leaked into view: blips and the arrow at alpha 0, a masked-away Minimap leaving a frozen arrow, masks leaking icons past the window. | Undocumented client behaviour. `SetAlpha(0)` fades the terrain only. A hidden Minimap doesn't redraw. Masks clip some icons and not others. | MinimapTakeover.lua | 42805f8, aba905b, 785c91a, 7202f06 ("whether its arrow shrinks too is unknown"). README Risks | Game | **MOVED**: Apply still has to place, size and hide the sensor on undocumented behaviour. The sim doesn't render, so it can only check the placement rules. | v1 (placement only) |
| D3 | Each blip read as four. Blips were duplicated while riding. "Copies turned up again." | A blip's answer square is fixed in screen units (about 8), not Minimap units (the sim answered in Minimap units, so it passed). The client moves blips in steps as you move, past the 6 yd "same blip" radius. | Blips.lua | e041ba8, 272949e, 0e249fd (blipLog added to diagnose) | Observation | **MOVED**: measurement stays in Game's sensor and merging moves to Model ("decides dedup and merge"). It's a cleaner split, and Model's half is pure-Lua testable, but the same tolerance problem remains. Replayed at a UI scale other than 1: overlapping squares read as the blips they are, none known twice riding, every one exact within 2 sweeps standing. M1.5b: one blip read as four is corrected (the square takes the client's size; the four merge, traced `sensor` and marked once); a measure across a view-radius change, or one whose lone middle no longer answers, is dropped; overlapping same-name blips are counted from the tooltip's answer. The replay covers the 5.6, 10.5 and door cases. To confirm in game (docs/playtest-final.md a3b): blips met riding exact once you stop, and the tooltip naming each of two overlapping same-name blips (if it merges them, the sensor does as before). | now: [`test_replay[D3]`](../../tools/tests/test_spike_bugs.py) |
| D4 | One thing showed as two of our own pins: a live rare (vignette) beside the seen-rare pin, Questie's turn-in "?" beside ours for the same quest. | No single merge rule across sources. | Landmarks.lua, AddonPins.lua | 5a491b1, 2accfc9. scen: live_rare_one_pin, addon_pins_questie | Model | **MOVED**: dedup is now Model's job alone, and Model sees only what it's handed, so it can be tested directly. Two sources are still two sources. | v1 |
| D5a | Blips read wrong, or shown misplaced, right after a zoom. | The client applies a new Minimap zoom level a frame or two late. | MinimapBlips.lua | 4e9786d ("applies a new zoom level a frame or two late"), 785c91a | Game | **PREVENTED**: architecture.md: "the blip sensor reads where the last Apply placed the Minimap, and waits until that placement holds still". The frame order (Apply, then the next frame's Observe) plus the settle rule makes reading a moving sensor a contract violation. Replayed: no probe falls in a frame a zoom or a placement is settling. | now: [`test_replay[D5a]`](../../tools/tests/test_spike_bugs.py) |
| D5b | Near a screen edge, every blip and its hover spot landed in the wrong place. Off screen, the sensor saw nothing. | When the Minimap's square runs off screen, the client draws into the on-screen part, shifted and squashed. Off screen, it stops updating blips; the probe had read them only within frames of moving them. | MinimapTakeover.lua, MinimapBlips.lua | 785c91a, 42805f8 → 679cbf7 (reverted), Release notes 1.0.0 | Game | **MOVED**: still undocumented client behaviour, handled in Game's Apply. Replayed: the sensor stays whole on the screen, off centre under the view if it must, the window in each corner. | now: [`test_replay[D5b]`](../../tools/tests/test_spike_bugs.py) |

### Layout, chrome and saved state

| id | symptom | root cause | spike file(s) | evidence | owner | verdict: why | replay |
|---|---|---|---|---|---|---|---|
| L1 | Quest areas were drawn offset and squashed (looked like duplicates next to the hover copy). | The client draws a blob into its frame's rect as it stood at `DrawBlob`, and applies a new size and anchor only at the next layout pass. Pooled frames were moved and then drawn straight away. | Layers.lua | a12a27b | Game | **MOVED**: in v1 Game still uses the client's quest blobs to answer `Inside(quest, col, row)`, so the deferred-layout trap moves into the sensor. Bounded (M1.9): each quest on a hidden QuestPOI frame of its own that never moves, drawn when first asked (nil: can't tell yet) and again the next frame; the sim draws a blob a layout late since M0.6. | now: [`test_replay[L1]`](../../tools/tests/test_spike_bugs.py) |
| L2 | Chrome geometry was wrong. Minimap mode shrank the map "to a stamp" (a 190 px inset), the map showed through under the metal border, and the zoom buttons sat under the resize grip. | Forever's edge atlases report sizes far beyond their visible metal, and the code trusted `GetWidth()` of the art. | UI.lua, Core.lua | 81df555, f0853fc (test), 4f110f4, 7a2cd63 | UI | **MOVED**: any chrome built from atlas art sizes. The border inset is clamped 2..6 px (M1.7). | now: test_chrome (an oversized edge atlas, inset clamped) |
| L3 | Pressing M again mid-shrink lost the minimap-sized rect. | Growing while still animating saved the in-between rect as "small". | MinimapMode.lua | 7a2cd63. scen: minimap_mode ("pressing M mid-shrink still comes back") | UI | **MOVED**: small ⇄ big is UI's state machine, unchanged in kind. | now: test_bigmap (M mid-shrink) |
| L4 | The window lost its place: turning minimap mode on snapped it to Blizzard's spot. Hiding or logging out while grown saved the big rect. | Layout was saved from the live frame, not from the "small" state. | MinimapMode.lua, Core.lua | f2083f6, 2b6d7b3. scen: minimap_mode_remembers | SavedVariables | **MOVED**: UI owns layout (saved), and Game only loads and saves. That makes ownership clear but doesn't make the transitions correct. Only the small rect and zoom are saved (M1.7). | now: test_bigmap (logout or hide while big) |
| L5 | Missing textures: Forever has no `Textures\MinimapMask`. New texture files show as missing after a `/reload` until the client restarts (a `None.tga` fallback was needed). | Art assumed from other clients. The client only scans new files at start. | MinimapBlips.lua, MinimapTakeover.lua | 7a2cd63, 785c91a, 98c68d2, bbbcc1a | Atlas | **CONTAINED** (was MOVED; M1.11 changed it): every atlas, file and font UI draws (ui/Art.lua) is checked at login and on `/mma check art`: a fallback chain counts if any of its names resolves, a font by loading it as the client does. Each miss is traced `art` and `telemetry.py --budgets` gates on it. Atlas still ships generated textures (Textures/Sea), with the same restart hazard. M1.4 adds Textures/PlayerArrow.tga (ui/You.lua): the first install after it needs a client restart, not a `/reload`. In game: `/mma check art` answers `art: all 36 there` and the `art` trace is empty (docs/playtest-final.md a0; 0 in sessions #8 and #9, before M1.4). | sim: test_bench test_check_art |
| S1 | Remembered blips vanished at every login. Remembered blips grew without bound. | Landmarks' login migration wiped every kind but "rare" from a store that Blips also wrote ("blip"). No cap. | Landmarks.lua, Blips.lua | 7c21fec. Also b4be9c6 (migrations for keys that never shipped) | SavedVariables | **MOVED**: Model owns both rares and seen blips ("rares + seen blips (saved)"), so one owner's migration can still wipe its own data. It is now a pure Model test. | v1 |

### Game sensing and client quirks

| id | symptom | root cause | spike file(s) | evidence | owner | verdict: why | replay |
|---|---|---|---|---|---|---|---|
| G1 | Indoors was decided wrongly: surface terrain in the Cleft of Shadow, Blizzard's grey patchy Minimap in Orgrimmar, Undercity NPCs strewn over the ruins, a whole zone's painting drawn in a Sun Rock hut. | Each signal was the wrong question. `IsIndoors()` means "can't mount". `ShouldUseHybridMinimap()` is read once per loading screen. "Floor plan only where you can't mount" fails underground. The map you're on can be zone-wide. Six fixes in a row. | MinimapBlips.lua, MinimapTakeover.lua, IndoorArt.lua | c812f4a, bbcc42e, 04a2db2, 55941dc, d50270b, 0c71e2b. scen: minimap_mode (indoors), indoor_art | Game | **MOVED**: still a heuristic over client behaviour, now feeding View's renderer (ours / ours + art / Blizzard), which makes each decision explicit and traceable. | v1 |
| G2 | Arriving by zeppelin, Blizzard's whole minimap (border, buttons) showed over ours. | The takeover released whenever you were off the map shown. The release decision read the camera (`cam.onMap`). | MinimapTakeover.lua | 9977ca8 | View | **MOVED**: Game acts only on View, so the rule moves into what View says. View can still say the wrong thing. | v1 |
| G3 | Blizzard turned back on what we'd turned off: HybridMinimap re-enables the Minimap's ground and rotation as it hides. Rotate Minimap handed the minimap back. The `SetAlpha(0)` trick was replaced by documented switches. | Other client code changes the same state. | MinimapTakeover.lua | bbcc42e, 5233961, alpha and beta release notes (Rotate Minimap limit), f4b29d7 (undo list) | Game | **CONTAINED**: Apply acts on View every frame, so drift is put right the next frame. The takeover's undo list reverses every change, and finishes even if one step fails. A one-frame flash is still possible and isn't reported. Replayed: HybridMinimap's re-enables put right the next frame; the sensor reads only a Minimap as Apply left it; something fighting Apply for 1 s is traced (`sensor` blind). | now: [`test_replay[G3]`](../../tools/tests/test_spike_bugs.py) |
| G4 | The corpse pin showed only after toggling the layer. | The client knows the corpse position only a while after release, and fires no event. | Layers.lua | f8f073f. scen: corpse | Observation | **PREVENTED**: Observe re-reads game state every frame, with no reliance on events, so a late value appears the frame it exists. | v1 |
| G5 | Wrong or missing data from runtime sources: town NPCs came out as gold dots, services were empty when QuestieDB wasn't ready, and objective icons needed the item cache plus a name match. | QuestieDB doesn't export its NPC flag values, it loads late, and the quest API gives no objective IDs. | Blips.lua, QuestInfo.lua | 679cbf7, 7c21fec, d79111d → bbcf9eb | Atlas | **PREVENTED**: Atlas bundles NPC flags (with documented Classic values), item icons (Item DB2) and objectives by kind and ID offline, and nothing reads QuestieDB at runtime (atlas-data.md). | now: [`test_replay[G5]`](../../tools/tests/test_spike_bugs.py) (skips without the QuestieDB-derived data) |
| G6 | Other addons' pins misbehaved. Questie's renamed HBD copy was missed and its pins spilled out of the window. HBD rotated its minimap pins under Rotate Minimap. Questie's pins drifted as HBD re-placed them on its own schedule. | Depends on HBD internals (`SetMinimapObject`, `minimapPins`) and on the names of its renamed copies. | AddonPins.lua, MinimapTakeover.lua | 95699c4, 2accfc9, 5233961. README Risks. scen: addon_pins_* | Game | **MOVED**: Game "adapts HBD world + minimap pins" on the same internals. While the takeover has the Minimap, every copy drawing on it (one loaded since too) draws on a hidden host, so no pin sits on the unseen sensor over our map taking the mouse (replayed: R-G6c); the world pins' round trip: R-G6, R-G6b. The minimap pins under Rotate Minimap, and the full borrow, are M4.2's. M1 review: a new zoom's re-place is a 1 ms job on a holder kept see-through until it's done (one call was 7.2 ms for 2400 pins on the counted clock); R-G6b runs on the default clock (no frame of ours over 8 ms after M or the wheel, priced). Left for the final session (docs/playtest-final.md e1-e3, Questie loaded): in the sim, M with 3000 Questie pins costs 60 ms (grow) and 41 ms (shrink) priced in the key press itself, outside our frames and budgets: Blizzard's map opening for a moment makes HereBeDragons show its pins before our hook takes them back. The spike pays it too. | now: [`test_replay[G6]`](../../tools/tests/test_spike_bugs.py), [`test_replay[G6b]`](../../tools/tests/test_spike_bugs.py), [`test_replay[G6c]`](../../tools/tests/test_spike_bugs.py) |
| G7 | Tooltips misbehaved. Blizzard's blip tooltips fought ours (flicker). Button tips lingered over menus. The quest-area tooltip was rebuilt every frame. | Several owners of GameTooltip, with no hide path. | Core.lua, MinimapMode.lua, Layers.lua | 118571e, 14762d0, 732070b. scen: button_tips | UI | **MOVED**: UI owns "tooltips", and Game owns the GameTooltip hook, so the two still meet at one shared widget. Game hides its own only through one owner-checked path (M1.6); UI's tiny tips: test_chrome; quest areas' with M2.4. | now: [`test_replay[G7]`](../../tools/tests/test_spike_bugs.py) (Game's half) |
| M1 | The route line misbehaved. It hopped sideways onto a crooked detour (Mulgore). It flashed straight while re-routing. The target flickered between arrived and not at an area's edge. | No hysteresis. The line was drawn from the nearest route point, not the furthest visible one. The old route was dropped before the new one existed. | Route.lua, Path.lua, Core.lua | 93a8372, 2c2c6ce, 8ba58b9. scen: path_to_quest_area, path_follows_route | Model | **MOVED**: Target and Route are Model's, the same logic, but plain Lua fed observations, so it's replayable frame by frame. | v1 |

### Known limits still open at the spike's HEAD (README, release notes)

| id | symptom | root cause | spike file(s) | evidence | owner | verdict: why | replay |
|---|---|---|---|---|---|---|---|
| K1 | Blips are only sensed within about 233 yd. Two of a name closer than a few yards show as one. | The Minimap only knows what's around you, and its answer square is about 16 screen units. | Blips.lua | README Limits. Release notes (all three) | Game | **MOVED**: inherent to the sensor. | no |
| K2 | "Action blocked" errors are possible, especially in combat. | Hiding Blizzard frames (the minimap cluster, the world map on M) from insecure code. | MinimapTakeover.lua, MinimapMode.lua | README Limits | Game | **MOVED**: Game still hides Blizzard frames. Bounded: the sim refuses insecure protected calls in combat (M0.6), and no replay makes one on any frame (T.Invariants); in combat the cluster fades and its hide or show waits for combat's end (M1.6). 0 taint in game, sessions #4-#6. Whether HideUIPanel(WorldMapFrame) is blocked in combat is the M1 gate's: the guard means no code path makes the call in combat, so 0 taint there proves nothing; `/mma check combat` (game/Hooks.lua) makes it once, on purpose, at the final session (docs/playtest-final.md c4), and c6 opens protected panels in combat after M's out-of-combat HideUIPanel (panel-manager taint would name us there). The sim's answer (blocked: Sim.Protect(WorldMapFrame)) is an assumption until then. | now: [`test_replay[K2]`](../../tools/tests/test_spike_bugs.py) |
| K3 | Conflicts with SexyMap and square-minimap addons, and with FarmHud. | More than one addon owns the Minimap. | MinimapTakeover.lua | README Limits (FarmHud is special-cased in `Blocker`) | Game | **MOVED**. | no |
| K4 | Tile IDs change between Forever builds, so Data/ must be regenerated. | Generated from one build. | Data/ | README Risks | Atlas | **CONTAINED**: `game/Validate.lua` (`/mma check`, `check log`) compares Atlas with the live client as you travel and logs mismatches to SavedVariables, and every data file names its build. Stale data is reported, not prevented. Data regenerated for build 1.60.1.70450 (72c1ba5). M1b (M1.12 c31930f): the logger judges as `/mma check` does (one Sample: the client not knowing yet at login and a WMO's own subzone, Orgrimmar's Valley of Strength, are info, 9eb08fe), its log is one build's (validation `_v` 2, `version`: another build's is cleared at load, after sessions #13-#22 showed earlier builds' lines as e50e7d5's), `/mma check report` names the build, and a sample makes ~19 B (~8 KB, 3.4 KB/s all session, before). In game: docs/playtest-final.md d1. | now (the logger): [`test_replay[K4]`](../../tools/tests/test_spike_bugs.py); stale data itself: live only |
| K5 | Instances that hide your position are shown whole, without the line or blips. | `UnitPosition` returns nil in restricted instances. | Core.lua (`FitMap(state.playerMap)`) | README Limits | Observation | **PREVENTED** (as a failure): Observation's nil means unknown (`obs.you` fields), so Model and UI must handle it. `game/Observe.lua` now takes `inst` from `GetInstanceInfo()`, which is known there: Model drops the old continent's position, the map switches to the instance, whole, when Atlas has its tiles (else it stays on the map you came from, titled with that map's name, as the spike's `playerMap` is nil there: Core.lua:1119), the arrow hides, nothing errors (replayed; see R-K5). | now: [`test_replay[K5]`](../../tools/tests/test_spike_bugs.py) |

### Appendix: crash dumps (none attributable) and what was left out

| dump | what | addons loaded |
|---|---|---|
| 09-18 ×3, 09-26 | `SIGTERM [HANG]` (339-byte stubs, no addon list) | unknown, pre-repo |
| 09-24, 10-14 19:52 | `EXC_BAD_ACCESS` at 0x20 | none (MagicMap listed Unloaded) |
| 09-27 | `ASSERTSAFES(!statInfo.alternateValue)`, Blizzard AuctionHouse tooltip (TooltipInfo.cpp:6150; Lua stack all Blizzard_AuctionHouseUI) | MagicMap 1.0.0, WhatsTraining. Not in the stack. |
| 10-05 ×2 | `ERROR #134 ... CAS system unable to initialize: container locked` | none. Possibly a tool reading CASC while the client started (the same day as the CASC-reading commits fb8546a and e8017e4). Unconfirmed; tooling, not the addon. |
| 10-08, 10-09 | `BC_ASSERT(targetUpdateSlot.hash == 0)` | none |

Left out because they are tuning or product decisions, not failures: 14a6ca5, 76c514d (quest-area
alpha), 06a13e5 (zoom limit), 6503d74 and 818ed3e (path-mode lean reversed, then removed, "at Ben's
call"), 8d288f9 (539 KB of heights shipped for one readout: a cost, not a bug), and style commits.
Experiment commits (da2e5c7, c177f4b, 2e4df6a, ace370f, ae11aba, 4a8352d) are the evidence behind
D2, D5b and K1.

## Replay scenarios

Since M1 wave 1a these "v1" sketches are replayed too, one file each in tools/tests/replays/:
R-D3, R-D5a, R-D5b, R-E4, R-E6, R-G3, R-G6 (with R-G6b, R-G6c), R-G7, R-K2, R-L1. M1b adds R-K4 (the
validator's logger) and R-P3b (P3 moving, in Orgrimmar).

Each sketch is written for the rebuild's harness: `L, sim, ns = boot()` from
tools/tests/test_addon.py, `sim.Slash`, `sim.Step`, `sim.Run`, `sim.Wheel`, `sim.Drag`,
`Sim.player`, `Sim.restricted`, `Sim.CountCalls`, and `ns.Runtime.errors` / `Perf()`.

### Replayable now

- **R-E1 (data globals collide).**
  - Initial: `boot()`. Then set `MagicMap_Borders` to a spike-shaped table, e.g.
    `{[0] = {lines = {{1, 12, 40, 0, 0, 31.0, 49.0, 32.0, 50.0}}, labels = {}}}`, and clear the
    Atlas border cache if there is one. `/mma map`.
  - Frames: `Run(1)`, then `Drag(view, 200, 0)` and `Run(1)`.
  - Expect:
    - Atlas detects the foreign table, either through a format/version field it checks or by the
      rows' shape, and the borders layer reports one error.
    - `ns.Runtime.errors` has at most one entry for the borders layer, its n doesn't grow with
      frames (no per-frame retry), and tiles and labels are still drawn.
  - A second check belongs in `tools/luacheck.py`: generated data globals must start with the
    addon's own name (`MagicMapAtlas_*`), so the spike and the rebuild can't share one.
  - **Replayed**: Data/ moved into `ns.Data`, so the global is never read (0 errors, borders drawn)
    and no `MagicMap_*`/`MagicMapAtlas_*` global exists after login. The format clash itself, a
    spike-shaped row added to our own `ns.Data.Borders`, errors 2 times in the first second and 4
    by 4 s (backoff 0.5, 1, 2 s...), recorded once in telemetry, tiles and labels fresh.
- **R-E7 (isolation, extended).** test_smoke already shows that a failing step leaves the others
  running. Add a failing layout job:
  - Initial: `/mma map`, `Run(1)`. Wrap the borders layer's `build` so that it errors once.
  - Frames: `Wheel(view, 1)` (forces a rebuild), then `Run(1)`.
  - Expect:
    - One error, named `map: borders`, in Runtime.errors and telemetry.
    - After it, `layer.busy == false`, and the layer rebuilds and shows the new zoom.
  - **This failed**: `ui/Map.lua` `Rebuild` set `busy = true` and only the job's success path
    cleared it, so a failed layout froze that layer for the session. Fixed: the draw step sees the
    job done but still busy (`Failed`), clears it, traces `layout failed`, and lays out again after
    0.5 s, doubling to 30 s while it keeps failing. The replay passes.
  - Also replayed: a step failing every frame for 3 s fails 12 times (throttled) and walks 1 stack.
- **R-P1 (borders keep up with a fling).** This ports the spike's `borders_keep_up`.
  - Initial: `debugprofilestop` on the counted clock (`Sim.Counted`, the replays' own: 3 us a
    widget call, Lua free), so widget calls cost client-like time, the same on every machine.
    `/mma map` at zoom 96, then `Run(1)`.
  - Frames: 180 frames of panning at 1.5 view-widths per second. Each frame, `Drag` by
    `w * 1.5 / 60` px, or set `Map.cam` directly with follow off. Each frame, record for every
    layer whether `front.region` covers the view rect and `front.zoom == cam.zoom`.
  - Expect:
    - Every layer covers the view on at least 95% of frames.
    - No job's `Perf().max` exceeds `JOB_MS * 1.5`.
    - 1 s after stopping, every layer is fresh.
    - Separately, after a 20-step wheel-out, layouts started ≤ (layers × distinct settled zooms).
      Count the `layout start` traces.
- **R-P2 (cooperative budget overrun).**
  - Initial: `debugprofilestop` advances 0.02 ms per loop iteration (a counter).
  - Frames: run `Runtime.Job("t", fn, 1)`, where `fn` loops 10⁴ iterations and calls
    `Runtime.Yield()` every 200 of them.
  - Expect: `Perf()["t"].max` stays at most budget + 0.1 ms. This fails as designed (about 4 ms),
    which proves the check-interval risk. Then pass with Yield on every iteration.
  - v1: the same with Model's route search, Elwynn (31.95, 49.75) to Lakeshire, under the
    counted clock. Expect max ≤ 1.2× budget and the route found within 60 frames.
- **R-P3 (per-frame garbage and idle work).**
  - Initial: `/mma map`, `Run(1)`, then `collectgarbage("stop")`.
  - Frames:
    - Idle: measure `collectgarbage("count")` and `Sim.callTotal` over 120 frames.
    - Dragging: 120 frames of drag.
  - Expect:
    - Idle: ≤ 0.1 KB and ≤ 2 widget calls per frame (the spike's "idle frames leave the tiles
      alone").
    - Dragging: no growth per frame beyond a constant. This failed on `Map.cam = {...}` in the
      `map: drag` step (now updated in place).
  - **Replayed** inside Runtime's frame only (the sim's own bookkeeping is outside it): standing,
    39 B and 0 setter calls on the map's widgets a frame (~49 widget calls in all, getters and the
    Minimap sensor's); dragging, 27 B a frame. The idle arrow used to re-apply 5 setters a frame.
- **R-P6 (every callback is timed).**
  - Initial: `boot()`, `/mma map`, `Run(1)`, then every `/mma` command.
  - Expect: every script set on a frame the addon created has its name in `Runtime.Perf()`.
    Enumerate `Sim.Frames()` for OnUpdate, OnEvent and OnMouse* scripts and check that each is a
    `Runtime.Wrap` closure, for example by keeping a weak set of wrapped functions in Runtime.
- **R-G5 (Atlas has the facts QuestieDB lacked at runtime).**
  - Initial: Atlas only, with QuestieDB not loaded.
  - Expect:
    - `Atlas.Npc(<an innkeeper>).services` includes innkeeper.
    - `Atlas.Item(<quest item>).icon` is non-nil.
    - `Atlas.Quest(id).objectives[k]` has a kind and an ID.
  - These belong in test_atlas, and parts may already be there.
- **R-K5 (restricted instance).**
  - Initial: `/mma map`, `Run(1)` on continent 0. Then `Sim.restricted = true` and
    `Sim.player.inst = 389`.
  - Frames: `Run(1)`.
  - Expect:
    - No errors, `Model.you.col == nil`, and the arrow hidden.
    - Once v1 handles instances, the map shows instance 389 whole. That needs the instance ID from
      `GetInstanceInfo()` (8th return), not `UnitPosition`.
  - **Replayed**: inst 389 from `GetInstanceInfo`, `you.col` nil, arrow hidden, no errors; the
    map switches to 389 (nothing drawn there until v1).

### Replayable once the feature exists (v1)

- **R-E2 (vignettes).**
  - Initial: the vignette mock (`GetVignettePosition` returns (0.38, 0.79) on uiMap 1429), the
    player in Elwynn, the map shown.
  - Frames: `Run(0.5)`.
  - Expect:
    - The live-rare pin at `Atlas.MapToTile(1429, 0.38, 0.79)` within 0.01 tile, with both
      coordinates non-nil.
    - A mutated mock where `GetVignettePosition` returns nil gives no pin and no error.
    - Make Game's vignette read throw: `Runtime.errors` holds it once, and `map: draw` still counts
      60 calls per second.
- **R-E3 (division by zero).** The sim can't raise on `x/0`. Two substitutes:
  1. A Model route test with targets on the same row and on the same column as you. Assert that a
     route is found and that no output number is inf or nan (`x ~= x`, `x == math.huge`).
  2. A luacheck rule for atlas/ and model/ that flags `/` whose divisor isn't a literal or isn't
     guarded in the same expression (`n > 0 and a / n or ...`).
- **R-E4 (no LibStub).** `LibStub = nil` before boot, then `/mma map`, `Run(1)`. Expect zero
  errors and the "Other addons" layer group empty. This ports scen addon_pins_without_libstub.
- **R-E6 (empty sensor grid).** Engage the sensor with Minimap size 0×0, or a Blips grid of 0
  points. Run 60 frames. Expect 0 errors, then restore the size and expect blips sensed within
  2 sweeps.
- **R-P5 (quest areas while zooming).** A quest with `Sim.blobShapes[q] = {x, y, r}`. Wheel-zoom
  through 8 steps over 0.5 s. Expect each frame that UI's quest-area geometry and the pin stay
  within 1 px of each other on screen, and that no POI/blob frame is visible (alpha 0 or hidden).
- **R-P7 (one moving/settled flag).** Run a camera ease (wheel animation or target fit) for 1 s.
  Expect label and quest-area layouts started ≤ 2 per layer: one at the start, one on settle.
  Every consumer reads View's `settled`.
- **R-D1 (nothing of Blizzard's drawn).**
  - Initial: the sensor engaged outdoors, a turn-in quest giver beside you, the HBD and Questie
    mocks present.
  - Expect:
    - Exactly one pin per entity id in UI's store.
    - `Sim.BlobRingsAt(0)` (rim rings sized 0).
    - The sensor at alpha 0, ground off, icons at 5%, below our window's level.
    - Questie's minimap pins not on screen.
- **R-D2 (sensor placement rules).**
  - Initial: the window at each screen corner, the window scale at 0.7 and 1.3.
  - Expect after Apply:
    - The sensor rect is wholly inside UIParent.
    - It is shown (never `Hide()` while ours).
    - Its frame level is below our window, and it never takes the mouse.
- **R-D3 (blips while riding).**
  - Initial: UI scale 0.7, 3 herbs within 100 yd, the sim's blips moving in 8 yd steps.
  - Frames: ride at 7 yd/s past them for 10 s, then stand for 1 s.
  - Expect: Model `Known("blip")` count == 3 on every frame after the first full sweep, and after
    standing 0.5 s each position within 2 yd of the truth.
  - Port scen minimap_blips: its answer square is in screen units.
- **R-D4 (live rare and seen rare).**
  - Initial: a Model saved rare at the vignette's spot, with the vignette live.
  - Expect one pin. Remove the vignette: one pin (seen). Turn the live-rares layer off: one pin.
  - Port scen live_rare_one_pin.
- **R-D5a (settle before sensing).**
  - Initial: give the sim a 2-frame delay before a new `Minimap:SetZoom` takes effect.
  - Frames: change the zoom via View, then `Step()` ×4.
  - Expect: the sensor issues no reads on frames 1-2 after the change. Trace `sense` events by
    frame.
- **R-D5b (screen edge).** Place the window flush with the screen's right edge at zoom 800 (the
  closest). Expect the sensor square on screen, and blips from a mock at known yards placed within
  1 px of where Atlas projects them.
- **R-L1 (deferred blob layout).**
  - Sim change: `POI:SetPoint` and `SetSize` take effect for `DrawBlob` and hit-tests only at the
    end of `Sim.Step`.
  - Then: change the zoom and immediately ask Game's `Inside(q, col, row)` at the circle's centre
    and just outside it.
  - Expect the same answers as after one settled frame.
- **R-L2 (Forever-sized chrome).** Mock the border edge atlases at 200 px wide, as Forever reports.
  Expect the viewport inset between 2 and 6 px, the map filling the window ±6 px, and the zoom
  buttons clear of the resize grip's rect. Port f0853fc.
- **R-L3 (M mid-shrink).** Grow (M), `Run(0.5)`, M, `Run(0.05)`, M, `Run(1)`, M, `Run(1)`. Expect
  the final rect equal to the original small rect within 1 px.
- **R-L4 (saved layout).**
  - Grow, then fire `PLAYER_LOGOUT`. Expect the saved UI layout to be the small rect and zoom.
  - Grow, then hide, then show. Expect it small, where it was.
  - Move and size it, toggle Minimap mode off and on. Expect the same rect.
  - Port scen minimap_mode_remembers.
- **R-S1 (seen blips survive login).**
  - Initial: a Model saved table with 2 rares, 5 seen blips and 1 stale vendor entry from an old
    version. `Game.Load("Model")`.
  - Expect:
    - 7 kept and the vendor dropped.
    - Over 300 blips in one instance, the oldest go first.
    - A sweep that sees a remembered spot empty forgets it.
- **R-G1 (indoors decisions).** Set `Sim.indoors`, the Minimap view radius (indoor or outdoor
  values) and `Sim.mapArt`, then walk through these places. Expect View's renderer to be:
  - outdoors Elwynn: ours
  - Orgrimmar, outdoors and mountable, drawn with a floor plan: ours
  - Undercity, mountable, floor plan: ours + art
  - a hut in a zone-wide map: Blizzard
  - a dungeon floor with art: ours + art
  - Each change should leave one trace.
- **R-G2 (off the map shown).** Browse Kalimdor while standing in Eastern Kingdoms. Expect the
  takeover held (the Minimap still in sensor state, Blizzard's cluster hidden) and the HBD minimap
  host hidden. Then return. Expect nothing of Blizzard's shown on any frame.
- **R-G3 (Blizzard re-enables).** After Apply, call `C_Minimap.SetDrawGroundTextures(true)` and
  `SetIgnoreRotateMinimap(false)` from outside, as HybridMinimap does. Expect both reverted by the
  next frame's Apply. Then release, and expect every value as it was before engaging. Port scen
  minimap_restores_everything.
- **R-G4 (late corpse).**
  - Initial: `UnitIsGhost` true, and `GetCorpseMapPosition` nil for 3 s, then a position.
  - Expect, with no event fired: the corpse becomes Model's Target within 1 frame of the position
    existing, and the view follows you.
  - Alive again: no corpse and no target.
- **R-G6 (renamed HBD).** Only `HereBeDragonsQuestie-Pins-2.0` is in LibStub, with one world pin
  and one minimap pin. Expect:
  - The world pin hosted on our map at its spot.
  - The minimap pin off screen while its layer is on, and hosted when it's off.
  - With Rotate Minimap on, the minimap pins hidden.
- **R-G7 (tooltips).**
  - Hover a button 0.5 s: its tip shows.
  - Leave: it's gone. Open a menu: gone. Hover 2.5 s: gone.
  - Hover a quest area: one tooltip build per hover, not per frame (count `SetOwner` calls).
- **R-M1 (route line and arrival).** Model only.
  - Initial: a route from A to B over Atlas.Walk.
  - Frames:
    1. Move you 2 chunks off it, perpendicular.
    2. Cross the area edge back and forth every 0.2 s for 2 s.
    3. Move the target 3 chunks.
  - Expect:
    1. The line's first point is you, and its second is the furthest route point in line of sight
       (not the nearest).
    2. `Target.inside` flips at most once.
    3. The old route stays until the new one is found (no straight-line frame).

## Counts

The table has 39 failures (duplicates grouped). This page cites 74 distinct spike commits, counting
the excluded and experiment ones. There are 2 distinct log errors (2980 + 1 occurrences) and 5
known limits.

| owner | PREVENTED | CONTAINED | MOVED | total |
|---|---|---|---|---|
| Game | 2 (D1, D5a) | 3 (E4, E6, G3) | 8 (D2, D5b, L1, G1, G6, K1, K2, K3) | 13 |
| UI | 2 (P4, P5) | 2 (P1, P3) | 3 (L2, L3, G7) | 7 |
| Atlas | 2 (E1, G5) | 2 (K4, L5) | 0 | 4 |
| Observation | 2 (G4, K5) | 1 (E2) | 1 (D3) | 4 |
| Runtime | 0 | 2 (E7, P6) | 1 (P2) | 3 |
| Model | 0 | 0 | 3 (E3, D4, M1) | 3 |
| View | 1 (P7) | 0 | 1 (G2) | 2 |
| SavedVariables | 0 | 0 | 2 (L4, S1) | 2 |
| Tooling | 1 (E5) | 0 | 0 | 1 |
| **total** | **10** | **10** | **19** | **39** |

Replay (at the M1 gate): 19 now, in tools/tests/test_spike_bugs.py (E1, E4, E6, E7, P1, P2,
P3, P6, P7, D3, D5a, D5b, L1, G3, G5, G6, G7, K2, K5); 4 in sim tests (L2 test_chrome, L3 and L4
test_bigmap, L5 test_bench test_check_art); 3 static or priced (E3 lint_div and the strict runs,
E5 test_luacheck, P4 the priced zoom tests); 10 in v1 (E2, P5, D1, D2, D4, S1, G1, G2, G4, M1);
3 not in the sim (K1, K3, K4). The replays changed six verdicts: E1 MOVED → PREVENTED (Data/
moved into the namespace), P3 MOVED → CONTAINED (allocation now measured and budgeted, the
per-frame allocations fixed), and in wave 1b P1 → CONTAINED and P4, P7 → PREVENTED (M1.3: settled
layouts, the alpha swap, parking; R-P7), L5 → CONTAINED (M1.11: `/mma check art`). M1.4 (wave 2)
changed no verdict: half the border Lines (P1, P4), R-P3's stack regrowth, the arrow's new texture
(L5). The M1 gate (2026-10-18, e50e7d5: tools/check.sh green, 80 passed plain and strict, no
xfail) changed none either: every sim half is met, and the in-game halves are user-gate, steps in
docs/playtest-final.md (D10): P1 (a3), P3 (the read's `perf.alloc`), P4 (a5b's bench), L5 (a0),
D3 (a3b), K2 (c4), G6 (e1-e3). M1b wave 1 (M1.12, M1.13; tools/check.sh green, 83 passed plain and
strict) changed no verdict: K4's logger is replayed (R-K4: 20 rows replayed now; stale data itself
stays live only), P3 gained R-P3b (moving, in a city), P1 every layer 180/180. In game: docs/playtest-final.md d1.

## MOVED: risks the v1 run must design against

Most important first:

1. **Data globals shared with the spike (E1).** The rebuild's `MagicMap_*` data globals already
   broke the installed spike 2980 times in one session. `tools/telemetry.py` filters on
   "MagicMapAtlas", so it never showed. Fixes:
   - Done: Data/ loads into `ns.Data`; no data global is set (replayed: E1).
   - Have Atlas check a format field in each file.
   - Have telemetry also report client-log errors in any addon while ours is loaded.
2. **Scaling canvases costs a lot in the real client (P4).** The rebuild's zoom is `SetScale` on
   every layer canvas, tiles included. The spike measured that for tiles at 1.4 ms/frame (b02d96a)
   and reverted it. The sim's call counts said it was cheaper. Measure `/mma perf` while
   wheel-zooming on a big view before building more on it. Measured (M0 gate,
   docs/evidence/perf-m0.md): SetScale isn't the cost (8 µs on a canvas of 1000); each zoom
   frame's layouts and their swaps are, ~20 µs a region shown. Done in the sim (M1.3): no layout
   while the zoom moves, the swap by alpha; the bench's `canvas.SetAlpha.moved` confirms it in game (docs/playtest-final.md a5b).
3. **Layouts keeping up (P1), and containment that freezes (from R-E7).**
   - Done in the sim (M1.3): whole-layer rebuilds lagged a fling (borders covered the view on ~81%
     of frames at 1.5 views/s; a 20-step wheel-out started ~44 layouts for 4 layers). Now velocity-led
     margins and the view's missing layer first: 180/180 frames, 16 layouts for 5 layers.
   - Done: a layout job that errors left `layer.busy` true forever, so Runtime turned a crash into
     a silently stale layer. Now cleared on failure and retried with a backoff (replayed: E7).
   - Done: `Runtime.Wrap`'s catch took a `debugstack` on every failure, so a step failing every
     frame paid for that 60 times a second (the spike's E1 rate). Now a name's first failure, then
     at most once per 10 s (replayed: E7).
4. **Cooperative budgets (P2).** `Runtime.Yield` enforces nothing between calls, so jobs must yield
   at a fine grain (the route needed every 50 nodes). The P1 replay checks every layout job's
   `Perf().max` against 1.5× its budget; it caught borders at 7.5 ms against 4 (Map's end-of-layout
   pool hiding, and Borders' fading segments, didn't yield; both now do).
5. **The Minimap sensor runs on undocumented client behaviour (D2, D5b, L1, G1, G2, G6, K1-K3).**
   This is the largest cluster: 8 of Game's 13 rows. The architecture puts it in one place (Game,
   with Apply acting on View) but cannot make the client behave. Design for:
   - every placement rule, as an assertion the sim can check;
   - blob frames laid out before they're drawn or hit-tested;
   - indoors as one traced renderer decision;
   - a release that is driven by View, never by camera state.
6. **Merging and dedup in Model (D3, D4, S1, M1).** These are now pure Lua that only sees what it's
   handed. Make that pay off: each needs a frame-by-frame replay, because each was "fixed" more
   than once in the spike.
7. **WoW's Lua is not plain Lua (E3).** Model and Atlas are tested in plain 5.1, where `x/0` gives
   inf instead of an error. Add a static rule or inf/nan assertions.
8. **UI state machines and what they save (L3, L4).** Grow and shrink mid-animation, logging out
   while grown, mode toggles. Saving through `Game.Load(owner)` gives clear ownership, not
   correctness.
9. **Per-frame cost that `Runtime.Perf` doesn't see (P3, P7).**
   - Done: Runtime measures allocation per frame (`kbFrameP95`, `kbPerSec`, budget ≤ 50 KB/s), and
     the drag step's camera table a frame is gone (replayed: P3).
   - Done: "is the zoom settled" is derived once (`Camera.ZoomSettled`), and every layer reads it
     through Engine (replayed: P7).
10. **Chrome geometry and art (L2, L5).** Don't trust atlas art sizes. New texture files need a
    client restart, so code must survive their absence after `/reload`. Done: `/mma check art` at
    login checks every name UI draws (M1.11); an `art` trace fails `--budgets`.

## Patterns

- **Undocumented client behaviour was the biggest source of bugs, and most fixes were reversals.**
  - G1 took six commits.
  - D2 and D5b went 42805f8 → 679cbf7: off screen, then back on screen.
  - D1 went 118571e → d41655c: the fix was undone and redone.
  - L1, D3 and G3 too.

  Game owns all of this now, but no boundary removes it; only measuring in game does (the probe
  commits).
- **Hitches came from doing a whole job in one go, or from slices that only checked the clock now
  and then.**
  - Borders rebuilt per view change (P1).
  - Tiles laid out per zoom frame (P4).
  - A* checked the clock every 200 nodes (P2).
  - Unchanged state re-applied per frame (P3).

  The cheapest-looking fix in the sim was the most expensive in the client (906666c → b02d96a).
- **Things were drawn twice because there were two drawers.** At least 8 commits deal with doubles:
  ours with Blizzard's, ours with Questie's, live with seen, one blip measured as four. The design's
  answer is real: one pin store, Model's merge, and the Minimap only as a sensor.
- **One error cascaded because nothing isolated it.** A nil in a MapChanged handler aborted login
  (E2). One nil in Layers skipped the arrow, title and hover 2980 times (E1). `Runtime.Wrap` fixes
  the cascade, but containment can still leave stale state behind (layer.busy did, until the E7
  replay found it).
- **The sim's fidelity gaps let bugs through:**
  - division by zero (E3);
  - screen units versus Minimap units (D3);
  - deferred layout (L1);
  - the engine cost of `SetScale` (P4);
  - a bench measured before its waypoint applied (f5644cc);
  - test helpers counting pin icons as tiles (d79111d).

  The spike README says it directly: tests "catch crashes and wrong API assumptions, not how it
  looks in the real client".
- **Cleanup and "optimisation" caused regressions:**
  - removing a "dead" guard for an optional dependency (e1e13f3);
  - a perf change that made things slower (b02d96a);
  - migrations wiping a neighbour's data (S1).
- **Facts that never change were being read at runtime.** QuestieDB flags and readiness, item
  icons by name, map names 20 times a second. Atlas removes the whole class (G5); that is where
  most of the clear PREVENTED verdicts come from, along with the frame order (D5a, G4).
- **Lua idioms that compile but break at runtime.** `a and f()` keeps only one return value (E2).
  A SetScript replaces a hook (P3). luacheck's bytecode globals check doesn't catch either; review
  has to, or a lint does.

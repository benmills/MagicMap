# Runtime: what holds when things go wrong

Runtime (runtime/Runtime.lua) runs every frame's steps in phase order
(architecture.md "Each frame": Input → Observe → Model → UI → Apply), then timers'
due callbacks before them and jobs after them, and dispatches WoW events. This page
says, for each way the frame loop can fail, what is guaranteed, what enforces it,
and where it shows up in telemetry (docs/telemetry.md). The sim test
`tools/tests/test_addon.py::test_failures` drives each of them.

"Wrapped" below means `Runtime.Wrap`: every step, event handler, timer, job,
loader and slash command goes through it.

## Budgets

Our cost a frame is everything we run in it: timers, the five phases, jobs, and
the event handlers since the previous frame. It's measured with `debugprofilestop`
into a histogram (0.05 ms buckets up to 20 ms), so p50/p95/p99 are a bucket's top.
Frames inside a *grace* are kept apart (their slowest is reported, not counted):
5 s after each PLAYER_ENTERING_WORLD (`login` for login and /reload, `loading` for
a loading screen), 2 s after the first map open (`map`), the memory read's collect
(`gc`) and `/mma bench` (`bench`). A frame inside two counts to the newest only (the map
opened during login's: `map`), which keeps its slowest frame (`grace`) and that frame's
slowest call (`graceTop`). Nothing inside a grace counts against the budgets: no
overruns, gaps, allocation or ledger frames.

| Budget | Limit | Why |
|---|---|---|
| frame cost p95, at rest (`small`, `big`, `closed`: each state's, from `byState`) | ≤ 1.0 ms | 6% of a 60 fps frame; the spike's map ran ~0.3–1 ms/frame on average and felt free. |
| frame cost p99 at rest, and p95 moving (`zoom`, `drag`) | ≤ 5 ms | a frame with the layouts' share (4 ms, 4.5 with one urgent: 5 before the M1b review, which no frame with a step beside it could meet; since its second round the layouts share it in turn, one ending early handing what's left to the next, to 3.5 ms in all) plus the steps (~0.3-0.5 ms in the client; the counted clock's 3 µs a widget call, ~10x a SetPoint's, makes the draw 1-1.8 ms there, so test_feel's streams read 0.65-6.3 ms zooming on the priced clock, held to 5 ms and the draw's own: test_zoom_look). Moving, the slices run back to back, so a session's p95 says how much of it moved, not how it ran: script (a)'s shape on the priced clock is 1.8 ms over the session (a third of its frames zoom or drag), p99 4.7, 0.2 at rest, 4.5 zooming (the M1b review's second round; 1.65 and 4.65 at its first, 1.55 and 4.5 at M1.14, 1.95 and 4.95 before) (tools/tests/test_zoom.py test_script_a_priced holds zooming to ≤ 5; sessions #8 and #9 passed the session-wide p95 only because 82-93% of their frames were at rest). Decided in round 2 of the M1 review over smaller slices while moving, which would leave the borders behind a fling (R-P1's coverage). Sessions before `byState` (M0) are judged on the session's p95 and p99. |
| frame cost max, outside graces | ≤ 8 ms | half a 60 fps frame: at worst one dropped frame, never a hitch you notice. Each frame over it is an *overrun*. |
| one call (step, handler, timer) | ≤ 2 ms | `CALL_MS`: a step taking more starves the rest; work that size belongs in a Job. A job's resume: ≤ 2× its own budget. |
| first map open, slowest frame | ≤ 50 ms | first-use Atlas indexes (Labels are offline since M1.1: the sim's first open is 9 ms, its slowest call `map: borders` at 4 ms); ~3 frames, once a session. |
| load (Data + Atlas at login) | ≤ 250 ms | the sim measures 84–110 ms (`/mma perf load`, `boot.loadMs`); the client also reads the files from disk, so ~2.5× room. |
| our Lua memory, after a full collect (at logout) | ≤ 64 MB | ours alone (`GetAddOnMemoryUsage`) after `collectgarbage("collect")`, so garbage isn't counted (the play-test's 70.8 MB held ~24 MB of it: docs/v1-plan.md §2). Read at logout (`ourKB`) and 10 s after login (`ourKBLoad`: Data + Atlas, ~40 MB expected; ~39 MB in the sim since M1.4's border levels and subzone borders made Data/Borders.lua 927 KB, +1.7 MB of heap). Over it: a leak (`ourKB` − `ourKBLoad`, and `perf.alloc`) or data growth (`ourKBLoad`). |
| Lua allocation, outside graces | ≤ 50 KB/s | garbage is paid for later, by the collector, in someone's frame. A standing frame should make next to none, but every sensor probe makes ~0.35 KB of the client's garbage, answer or not (docs/evidence/perf-m0.md: `game.part blips` 233-297 KB/s in game at the M0 gate), so the sensor probes little (M1.5b: the default window 14 KB/s priced over standing, walking and a door, R-P3 walking among 10 blips 64 B a frame; in game 27-30 KB/s in sessions #8 and #9, before e60ff51's door fix). Without the sensor, ~40 B a frame standing or walking; more during a sustained fling (the ground a layout adds, its end and swap traces; a layer with nothing to draw, blips or rares out of zoom, isn't laid out again on a pan), more while the first layouts on a canvas create its regions (one frame of several MB). A layout's start was a job of its own (a coroutine, a closure, a handle, a start trace of 11 fields): 2.8 KB in the sim, but 8.6-10.3 KB in the client (sessions #8 and #9: `map: draw` 6-22 KB/s, over 2 layouts a second), so the budget failed (56.7 and 108.7 KB/s, with the sensor's 30). Since round 2 of the M1 review each layer lays out on one worker (`Runtime.Worker`: its coroutine made once), the start its own call (`map: layout`, so `perf.alloc` names it) with a 5-field trace: 0.37 KB a start in the sim (its trace; the 0.83 measured before M1.12 counted the sim's xpcall shim, which makes a table for more than 4 arguments: the client's doesn't). A whole layout is its three traces (start, end, swap: ~1.1 KB) and, since M1.12, nothing else once its canvas holds what it needs (`Engine.Keep`: R-P3b, Orgrimmar at the client's prices, 12.9 KB/s over views seen before (14.2 at M1.12), 20.3 walking through its doors; 83.5 and 131.6 KB/s in the user's sessions #13 and #14). The first time a city's big window zooms out, its canvases make their regions (~7,000, ~3.6 MB, kept in their pools, made once a session), which the client's heap reading counts as allocation: a short session can read over 50 KB/s for it (R-P3b's 76 s: ~64 KB/s, the second pass over the same views 13), ~6 KB/s spread over a 10-minute one (the budget can't tell pool growth from garbage). The client's price is to be re-measured at the final play-test (`map: layout` in `perf.alloc`: about one trace a start). The budget is the session's average. `kbFrameP95` (KB a frame) is reported beside it, to find the frames. |
| errors per hour | 0 | every error is a bug; the counts make a regression obvious. |

Login frames aren't budgeted (load time is); their slowest is reported as `grace.login`.

Allocation is the Lua heap's growth (`collectgarbage("count")`) over each frame's run, the
same frames as the cost: `kbFrameP95`, `kbFrameMax` (KB a frame), `kbPerSec`, `kbFrames`. A
frame in which the collector freed more than we allocated (the heap shrank) can't be measured
and is left out, so it's a lower bound; event handlers between frames aren't in it. In the sim,
widget calls cost no Lua memory (as in the client), so the replays (tools/tests/replays/R-P3.lua)
measure ours alone.

`tools/telemetry.py --budgets` checks the newest session's `perf` against these
(PASS / FAIL each, exit 1 on a FAIL). The limits live there in `BUDGETS`, and
`FRAME_MS`, `CALL_MS` in runtime/Runtime.lua: change all three with this table.

## Attribution: who to blame for a FAIL

`Runtime.FrameStats()` names an owner for each budget, outside graces like the frame stats
(a grace's own owner is `graceTop`: its slowest frame's slowest call; the first open's FAIL reads it).
All of it is kept in tables made at load: a measured frame allocates nothing more.

| Key | What | How |
|---|---|---|
| `alloc` | the 5 names making most KB/s: `{ name, kbPerSec, kbMax, calls }` (`kbMax`: most in one call; `calls`: measured) | `collectgarbage("count")` before and after each wrapped call and each job resume; a call in which the heap shrank (the collector ran) is left out, so it's a lower bound. Inclusive: a wrapped call inside another counts in both. Calls with budget `false` (Runtime's own frame and event dispatch, loaders) aren't counted. The `spike` trace names the frame's top allocator too (`alloc`, `allocKb`). |
| `gaps` | per job name `{ job, ms, n, stack }`: its longest stretch without a `Yield` over its budget, how many, and the stack of its first | each `Yield` times the stretch since the last (or since the resume); a resume also checks the stretch from its last `Yield` to its end (`stack` = "(ran to the job's end)"). A `gap` trace `{ job, ms, n }` at a name's 1st, 10th, every 100th. One `debugstack` per name. |
| `ledger` | the 5 worst frames `{ frame, ms, top, topMs, events }`, worst first | `events`: the 10 trace events up to the frame's end (its own, the `spike` last) and the 10 traced after it |
| `byState` | `{ [state] = { frames, p50, p95, p99, max, client = { p50, p95, p99, max } } }` | the frame cost again, in one histogram per map state; UI calls `Runtime.SetState(state)`: `closed` (hidden), `small`, `big`, `zoom` (the wheel's zoom not laid out yet), `drag`. `client`: the client's whole frame in that state (OnUpdate's `elapsed`, 0.5 ms buckets), so a cost the client defers to its drawing (no budget sees it: our cost is Lua's) shows as zoom or drag frames slower than small ones |

`Runtime.Perf()`'s entries carry the per-name totals behind these: `kb`, `kbN`, `kbMax`,
`gaps`, `gapMax`, `gapStack`, and `gc`. `tools/tests/test_addon.py::test_attribution` drives each.

An overrun is a call's own: one over budget in which the heap shrank (the collector's step ran
inside it, paid for every addon's garbage: sessions #8 and #9's `game.part blips` at 2.4 and 3.9 ms,
a sensor slice that yields at 0.5 ms) counts apart (`gc`, `perf.slowGc`, a `slow` trace with `gc`),
not in `over` or `perf.slow`, the gate's. A press that runs the client's own UI is budgeted the frame's
8 ms, not a call's 2, with its reason beside it: the gear's menu (`map: gear`, MenuUtil building it:
3 ms in #8) and a grow (`map: mode`, `map: keys`: SetFrameStrata and Raise over the window's tree,
2.2 ms in #8).

## The map's engine: swap, zoom and pan by the client's prices

ui/Engine.lua (M1.3) chooses each from docs/evidence/perf-m0.md, the M0 gate's measures:

| The client charges | So the engine |
|---|---|
| Showing a canvas whose regions moved while it was hidden: ~20 µs a texture or font string, 35-50 µs a line, in one call that can't yield (the swaps' 116 ms for 2418 border lines, 24 for 887 tiles, 13 for 696 rares); ~7 µs a region shown unmoved | never shows or hides a canvas. Each layer's two canvases stay shown, the front at alpha 1, the back at alpha 0; a layout re-anchors the back's own regions where they stand (pooled per canvas), spread over its frames, and the swap is a SetPoint and two SetAlphas (a canvas's SetAlpha: ~4 µs for 1000 children). The swap now measures under 0.5 ms on the priced clock |
| SetParent onto a hidden frame 0.22 µs, back 0.70 | parks what a layout didn't use, a tile's mask with its art: a canvas holds only what it shows, so hidden pooled lines and masks (the tile swap's 9-10 ms floor) no longer ride with it (R-P1 checks a canvas holds its live regions and their masks, nothing else) |
| SetScale ~8 µs a canvas of 1000 (not the cost); every chase frame laid all 5 layers out and swapped each (zoom state p95 20 ms, `map: draw` 35 KB a zoom frame) | lays out again only when the zoom settles (unchanged 0.15 s: `Camera.ZoomSettled`) or the camera's zoom leaves [0.7, 1.4] of a layout's (tiles). Meanwhile tiles are scaled (`"scale"`); names and pins are moved to the camera's zoom (`"move"`, `"pin"`, `Engine.At`: a SetPoint each, 0.31 µs, only those in or entering the view), so fonts and icons keep their size. Names are laid out at the camera's zoom on the frame it drifts log(1.25) from theirs and on the frame it lands (the spike's LayoutLabels at state.zoom, LABEL_DRIFT: Layers.lua:1647-1653, 2012-2030; until the M1b review at the [0.7, 1.4] band, ~0.5 s after the spike's; until its second round a drift on toward where it was headed, the drift late behind other layouts: 3-6 drifts on a fast flick). Pins aren't chosen for a zoom (the spike's PositionPins places them, Layers.lua:403-416): laid out a drift on toward where the zoom is headed, for the view, not each drift; those under their minimum zoom (`Engine.At`'s `minZoom`: rares and remembered blips from 60) from a drift below it but zooming out (`Engine.From`), on the canvas's frame for that zoom, whose one SetAlpha shows or hides them all the frame the zoom crosses it (a SetAlpha a pin was the draw's 3.1 ms priced for the big window's ~440 rares at 60); a build that left pins out by zoom says from which zoom, and is laid out again as soon as a layout would draw them; borders (`"hold"`) as the spike's: scaled too, and dimmed the further from their layout's zoom (`max(0.25, min(1, 1.6 - 0.6·|log2 s|))`, Layers.lua:158-170), laid out where the zoom is headed (`Motion.Goal`) from the frame after the wheel's last tick (RequestGeometry, Layers.lua:1907-1937; until the M1b review, once the goal held 0.1 s), then crossfaded from the old canvas's alpha over 0.12 s (Layers.lua:16-24, 1824-1836, 1967-1972; a layout within 2% of the old one's zoom cuts straight over). Whether scaling a canvas of thousands of Lines costs the client per frame (spike-bugs P4's 1.4 ms a frame was the client's frame, not the call) is the final session's to show: the zoom state's client frame time (`byState.zoom.client`) |
| five 4 ms layout jobs a frame: 20 ms frames | the layouts share a frame's budget, one at a time, in turn (Engine.Draw plans each frame): a layer the view lacks (missing) or about to (soon: a zoom out about to run past its tiles, the next row; names or pins whose offsets near the bound, the last row) first, the ground, then names and pins, then borders, but borders after names and pins drifted (the rows above), then a blurred ground (tiles zoomed in past 1.4 of their layout), at 4.5 ms; then a layout going on; else (late) at 4, the one laid out longest ago, and 2.5 ahead of a pan while the view is still covered (`PAN_MS`: the drag's frame p95, 4.35 ms in sessions #13 and #14, is 2.75 priced in R-P3b). A layout going on but outranked waits at budget 0, its place kept (`Runtime.Requeue`; until the M1b review's second round one was stopped, to start again after: a drift's names kept the ground waiting), and one ending with 1 ms or more of the frame's budget left hands it on, to 3.5 ms in all (`Chain`): names are laid out on the frame they drift, pins and the ground after them (until then one layout a frame: a drifted name waited on tile and border layouts by age, 3-7 drifts behind on a fast flick, R-P1's labels canvas 4,900 px off before that). A held layout whose goal moves on is cancelled, as RequestGeometry re-aims (Layers.lua:1913-1928). The plan's "8 ms" for a layer the view lacks would make every such frame an overrun (our frame max is 8 ms, and the draw step's moves and the sensor share it): at 4.5, the priced grow's and shrink's slowest frames are 4.4 and 3.0 ms (6.1 and 6.2 before the second round) |
| a fast zoom out, laid out at the camera's zoom, ran past each layout before it landed (blank edges; the spike lays its tiles out every frame) | zooming out, lays the tiles out where the zoom is headed (`Motion.Goal`) when that layout holds the view now (M1.14), once the camera is two drifts from running past the one shown (soon): the zoom keeps a point still (you while following, else the cursor or the centre), so every view on the way nests in the goal's and one layout covers them all; zooming in, two drifts on toward it (at most there) over the camera's view, so one layout lasts the way in (the tiles shown at 1.8x their layout at most on the big window's flick to the clamp, 2.2x a fast scroll; 7.9x before the M1b review's second round, laid out at the camera). Names at the camera's zoom, pins a drift on toward it (M1.14 laid them out at the goal too, so a zoom out showed the destination's names and pins from its start). A glide, the goal a drift or less away in zoom (the follow glide, the idle return, a chase landing): names and pins over its whole path, the view and the goal's, while that stays within the origin's reach (until the M1b review's second round the pins were gone for 9-11 of the idle return's 33 frames after a pan: the spike lays its pins out map-wide, Layers.lua:418-430). Held borders are late (4 ms) until they no longer cover the view, then missing. Priced (tools/tests/test_feel.py, 14 streams): tiles cover the view every frame; names and pins miss its edges for at most 4 frames (rares, 32% of the view at worst, a trackpad's burst; the big window's flick to the clamp 1; the mouse wheel's fast scroll, grow and shrink mid-zoom none); every rare in view is drawn wherever their layout covers the view, but on the frame the zoom crosses 60, the glides' whole way; names are chosen for a zoom a drift or more from the camera's one frame in a row at most, 1.6 drifts at most, but while the ground's urgent layout runs (3.7 drifts flicking the big window to the clamp) |
| a pan's coverage: a whole-layer layout lags a fling (P1: borders covered 81-86% of frames at 1.5 views/s) | lays out 0.5 of the view past each side at rest; moving, up to 0.75 ahead and 0.25 behind (by speed, all of it from 0.5 views/s), and again before the view 0.3 s ahead leaves the layout: R-P1 covers 180 of 180 frames, every layer (177-180 before M1.12's `Engine.Keep`, the next row: the spike's in-place extension at the same zoom, pooled) |
| a pan's layout re-anchored and re-textured every region it laid out (in Orgrimmar a tile layout made 225 KB in one call, a border layout 150-476 KB: sessions #13 and #14) | keeps what a canvas shows: `Engine.Get(canvas, kind, what, make, key)` records what a region shows (a tile, a border piece), and the next layout on that canvas takes it back with `Engine.Keep(canvas, kind, key)`, left as it is while the canvas's epoch (its map, zoom, origin, the layer's rev) is the one it was set in. So a pan's tile and border layouts set only the ground they add. Tile masks are made only for coast tiles (half a tile layout's regions); a border Line's colour is its kind's |
| showing the window shows every region under it in that one call (a re-open: 115 ms on the priced clock, ~26 in the client at ~7 µs a region unmoved; script (c) toggles it in combat) | empties every layer when the window hides (its own Hide, or its parent's: Alt-Z), a layout in progress stopped, and parks their regions in a job until it's visible again, so showing it again shows none at once and the layers lay out again as at the first open: 0.6 ms priced, the slowest frame after it ~5 ms, fresh within 1 s (R-P7: hidden, mid-layout and Alt-Z). A layer turned off is emptied and parked the same way (its frame stays shown), so turning it back on lays it out anew (R-P7: no frame over 8 ms priced) |
| canvas offsets of ~27,000-33,000 px (tile (0, 0) at a canvas's TOPLEFT: the tear's suspect) | places tile (col, row) at ((col - ox) * zoom, -(row - oy) * zoom): (ox, oy), the origin, is the whole tile nearest the view's centre, shared by every layer, and moves only when a layout would reach past 2800 px from it (every layer then lays out onto the new one). So an offset stays under ~2800 px at its layout's zoom. Each canvas is anchored to the view's centre in its own units (a scaled one's offset is then the origin's at its layout's zoom; what it moves on the screen is that times its scale). A canvas whose offsets would pass 4,000 px on the screen (`SHOWN_PX`: a flight, a jump or a flick ran past its layout; names or pins far from the camera's zoom, or laid out nowhere near the view) is left where it stands, hidden, and laid out first, names and pins already as theirs pass 2,800 at the camera's zoom (until the M1b review's second round they lagged 3-7 drifts behind a free flick in toward a corner: 4,471 px, and 6,827 in the big window); but a held one scaled past 1.4, as the spike's PlaceCanvas. Every replay and test_feel stream checks each anchor under the view as it's set and each canvas as the frame ends (until the M1b review only regions and lines were: R-P1's zoom jump had put the tiles canvas 34,190 of its units off), in screen px, under 4096; but the world socket's (Game hosts other addons' pins on it at tile (0, 0)), and a held canvas scaled past 1.4: a layout from further out while the zoom comes in (borders, a crossfade's old canvas), its origin's offset growing with its scale until it's laid out again (35,034 px at 45x in R-P1, 16 notches in from 16 after a flick out about a corner; the client's error still a thousandth of a pixel there). The ground past 1.4 (a zoom in outrunning its layout) is held to the limit: 2,869 px at most, 2.3x, in R-P1. R-P1 runs the wheel at a notch a frame 16 → 800 → 16, a flick out from 800 about the cursor, a drag, a flick and a grow under it, and flicks in from 16 toward corners, in the small window and the big, priced. Also one canvas a layer shown, and at rest every layer on the one origin, so their offsets round alike |

On the sim's priced clock, wheel-zooming, each layer's slowest layout frame is now 4-5 ms (were borders
93, tiles 25, rares 13 with the swap; in game 116, 24, 13); grow, shrink, the follow glide and the idle
return make no frame over 8 ms (19-31 a grow before); a 20-step zoom-out (a tick a frame) starts 12
layouts (tiles 2, borders 1, labels 6, rares 2, blips 1: names at the camera's zoom each drift and where it
lands; 10 at M1.14 and the M1b review's first round, 16 before it, 33 before M1.3). The counted
clock prices a widget call at 3 µs, ~10x a SetPoint's: moving ~500 static rare spawns a zoom frame is
~1.9 ms there, ~0.15 ms in the client (M1.11 shows rares from zoom 60). Quests to pick up have no minimum
zoom (the spike's, Layers.lua:636-664): at the continent's zoom the draw moves every one, and with 5 a zone
over the Eastern Kingdoms (130: test_quest_areas test_offers_priced) `map: draw` passes CALL_MS there
(2.1 ms; 2.3 with 10 a zone), ~0.2 ms in the client; CI holds it to 2.5 ms, so a regression in moving pins
shows. The client's quest areas (ui/Areas.lua's QuestPOIFrames) are priced as any widget call until the
final session's bench says otherwise (`/mma bench regions`: `poi.DrawBlob`, `poi.draw` a frame of your map's
quests, `poi.UpdateMouseOverTooltip`, `frame.poi`): a frame is drawn as it's laid out and again the next frame,
so a zoom draws each quest twice, but a count ticking draws none (only a quest's id, the game's areas'
version, the frame's style or size do), and the hover's hit test runs only when the cursor, the camera or a
drawing changes.

What the bench must still confirm (`/mma bench regions`, the final session): that re-anchoring a shown
canvas's regions at alpha 0 costs what a SetPoint costs, not the 20-50 µs a Show paid. It times Show
after the regions moved (at alpha 1 and at alpha 0), SetAlpha(1) after they moved while shown at alpha
0, and masked textures shown after moving, its lines coloured as a border's (clear lines would read
cheap to a client that culls by alpha); and, since a call's time can't show a cost the client defers
to its drawing, the whole frame after 1000 lines moved on a shown alpha-0 canvas (`frame.moved.alpha0`)
against the same move hidden (`frame.moved.hidden`) and an idle frame (`frame.idle`), and the frame
after the engine's swap itself (`frame.swap`: moved at alpha 0, a frame drawn, then SetAlpha(1); the
deciding number: about `frame.idle`, or the swap pays the M0 gate's 35-50 µs a line where it shows them).
A minimum zoom crossed (500 pins moved and shown in one frame): each by its own SetAlpha
(`reveal.each@500`, `frame.reveal.each`: the engine's way until the M1b review's second round) against
their frame's one (`reveal.frame@500`, `frame.reveal.frame`: its way now), the calls and the frame after.
The session's `byState[state].client` (the client's whole frame by map state, booked to the state each
frame ran in) shows the same in play: zoom and drag frames should be within a few ms of small ones.
A layer holds its live regions and its old front's at alpha 0 until it's laid out again (and pins under
their minimum zoom, at alpha 0 by their frame): Stormwind's big window, set to zoom 400 down to 20, holds
2,113-5,712 on its canvases for 833-2,850 live (at 50, 5,712 for 2,850: the tiles 3,316 for 1,798, 624
rares hidden under 60; at 400 the borders 2,436 for 730); before the M1b review's second round the peak
was 6,892 (6,282 for 2,595 at 200, the borders 4,903 for 2,065; the M1 review's "worst seen", 2,388
lines at alpha 0, undercounted it). R-P3b prints Orgrimmar's by layer (5,399 for 2,530 at 50).
If moved alpha-0 regions turn out to cost, park the old front's leftovers after each swap (and its
crossfade) in a job (0.22 µs a park, 0.70 an unpark), or extend the front canvas in place.

## Guarantees

| Failure | Guarantee | Enforced by | Observed |
|---|---|---|---|
| a step errors | the frame's other steps, timers and jobs still run; recorded once per key with its stack; after 10 failing calls in a row it runs once a second until one succeeds; a stack is walked for a name's first failure, then at most once per 10 s | `Wrap`: `xpcall` + its catch (stack, `StackDue`), `Fail`, strikes in `Finish` | `errors[key]` (count, stack on first), an `error` mark with the trace, `throttled` trace, `perf.errors`, `errorsPerHour`; `/mma errors` |
| a step overruns its budget | it finishes (Lua can't be preempted); counted per name outside graces; the frame is counted as an overrun if over 8 ms | `Done` (per call), `Count` (per frame) | `slow` trace (1st, 10th, every 100th), `spike` trace naming the frame's slowest call, `perf.overruns`, `perf.slow`, `perf.max`; `/mma perf load` |
| an event arrives mid-frame | handlers never run inside a phase: an event fired during a frame is dispatched after its phases; Game's handlers only note what changed and the observe step reads, so Model sees one snapshot a frame | `inFrame` + `queued` + `Flush` in Runtime; the rule for Game | handlers' time counts in the next frame's cost |
| a stuck job | a job still running after 600 resumes (its `maxFrames`) is cancelled and reported; one that doesn't `Yield` can't be stopped, but shows as an overrun; Map's layout jobs that fail or are cancelled leave their layer on its last good canvas and lay out again after a backoff (0.5 s, doubling to 30 s) | `RunJobs` watchdog; `Done(job, 2× budget)`; ui/Engine.lua `Failed` | `job` trace, `errors[key]` ("still running after N frames: cancelled"), `slow`/`spike` traces; handle `.done`, `.err` |
| nil position (instances, loading) | Observation carries nil fields (a frame the you part fails: all of them); Model keeps the last known with `stale = true`; the map follows it with the arrow hidden; no step assumes a position | game/parts/You.lua, model/Model.lua, ui/You.lua (`you.stale`) | `position` trace (`lost`/`back`); marks' `state.you` |
| missing or stale saved data | the loader always gets a table of its version: absent or not a table → defaults; older → `migrate` (failing: reset) and defaults by type; newer (a downgrade) → left untouched on disk, the session runs on defaults | `Game.Load(owner, fn, spec)` (game/Game.lua `Open`) | `saved` trace (`reset`, `newer`), a failing migrate or loader as an error |
| loading screen / PLAYER_ENTERING_WORLD again | handlers are idempotent; the frames after it are a grace, not overruns | game/Game.lua `game.enter` → `Runtime.Grace` | `enter` trace, `perf.grace.login`, `.loading` |
| /reload mid-job | nothing half-done is saved: jobs build into locals or widgets and commit in their last, non-yielding stretch; SavedVariables are written from tables at PLAYER_LOGOUT, which /reload fires | the rule (Map's layouts: back canvas, then swap) | `perf` written at logout |
| a callback added during iteration | runs from the next pass: a step from the next frame, a handler from the next event, a timer when due; a job started in a frame runs that frame | `for i = 1, #list` read once; `RunTimers` keeps added timers; `RunJobs` walks to the end | — |
| timers late after a hitch | an `After` fires once; an `Every` fires once, then re-phases: never a burst | `RunTimers` | — |
| error handler recursion | an error while reporting an error isn't reported again: a failing `onError` is switched off (printed once); our global error handler never re-enters and always calls the previous one | `reporting` in `Fail`; `inHandler` + `pcall` in game/Telemetry.lua | the print; `lua` errors |

### A step errors

`Wrap` calls the function under `xpcall`; its catch takes `debugstack` while the
failing frames still exist, but only for the name's first failure and then at most once
every 10 s (`STACK_EVERY`): Telemetry keeps only a key's first stack, and a step failing
every frame would otherwise walk the stack 60 times a second (the spike's E1 rate). `Fail` prints the first error per name, keeps
`Runtime.errors` (`{ name, err, n }`), and hands every one to `Runtime.onError`,
which Telemetry keys by `name: first line of the message`: the first occurrence
in a session stores the stack, traces `error` and takes an `error` mark; later
ones only count. One failing step costs nothing else: the loop goes on to the next.

Throttling: a callback failing 10 calls in a row (`STRIKES`) is skipped except once
a second (`RETRY`) until a call succeeds, which resets it. We keep retrying rather
than disabling it because most every-frame errors are about state (an instance, a
missing frame) that passes; once a second keeps the stack walk and the spam down to
nothing while it doesn't.

### A step overruns

Lua in WoW can't be preempted (there are no debug hooks), so Runtime never stops
a call; it measures it. A call over its budget (`CALL_MS` 2 ms, a step's
`opts.budgetMs`, a job resume's 2× its budget) outside a grace adds to the name's `over` and traces
`slow` on the 1st, 10th and every 100th, so repeated overruns show as a rising `n`
without flooding the ring. A frame whose cost is over `FRAME_MS` (8 ms) outside a
grace is an overrun: counted in `perf.overruns`, and traced as `spike` with the
frame's slowest call. `perf.slow` lists the five names with most overruns.

### Events

WoW fires events between frames, and also synchronously inside some API calls a
step makes (CVars, tracking, quest log selection). Between frames a handler runs at
once. During a frame (`inFrame`), the event is queued and dispatched after the
Apply phase and jobs, so no handler ever runs inside a phase. Game's handlers only
note what changed (a dirty flag, a buffered value); the observe step reads the game
and hands Model one observation, so Model sees one consistent snapshot a frame and
UI draws from it.

### A stuck job

A job is a coroutine resumed once a frame for up to its budget. If it's still
running after `maxFrames` resumes (default 600: 10 s at 60 fps; frames, not
seconds, so a loading screen doesn't count against it) it's cancelled: `.done`,
`.err` set, a `job` trace and an error (once per key). A job that never calls
`Runtime.Yield` runs to its end in one resume; that can't be stopped, but its resume
shows as an overrun (`slow`, and `spike` if the frame went over). A job whose body
errors ends with `.err` and its coroutine's stack recorded.

### Nil position

`UnitPosition` returns nothing in instances and on some loading frames, and
`GetPlayerFacing` likewise. Observe hands Model nil fields, never a guess, and
traces `position lost`/`back` on the change; a frame the you part fails hands an
all-unknown `you` (the LOCKED nil rule), never last frame's values as this one's. Model
keeps the last known position and facing with `you.stale = true` (cleared on the next
real one; if a new instance is known but no position, the old position is dropped). The
map keeps following the last known spot and hides the arrow while it's stale (ui/You.lua),
as with nothing ever known. Every step treats every observed field as possibly nil.

### Saved data

`Game.Load(owner, fn, spec)` with `spec = { version, defaults, optional, migrate(saved, from) }`
(all optional; version 1, no defaults). `MagicMapAtlasDB` that isn't a table is
replaced. Then per owner, before `fn` sees it:

- not a table, or a non-number `_v`: reset to `{}` (traced `saved reset`);
- `_v` newer than ours (an older build after a newer one): the saved table is left
  exactly as it is, and `fn` gets fresh defaults, not saved this session (traced
  `saved newer`): a downgrade never destroys data;
- `_v` older (absent counts as 0) with data and a `migrate`: it runs wrapped; if it
  errors the table is wiped (traced `saved reset`, the error recorded);
- every key in `defaults` whose saved value has another type gets a copy of the default, and every
  key in `optional` (by type name: `{ window = "table" }`) whose saved value has another type is
  dropped (nil, traced `saved dropped`);
- `_v` is stamped with our version.

`fn` itself is wrapped: if it errors, the error is recorded and the rest of the
addon loads. Each owner's `fn` runs once a session, at ADDON_LOADED (or at once, if `Load` is called later).

### Loading screens, /reload, iteration, timers, recursion

- PLAYER_ENTERING_WORLD fires at login, /reload and every loading screen. Handlers
  must be idempotent (Game's only starts a grace and traces `enter`). Frames after
  it, often slow while the world streams in, are graced, not overruns.
- /reload throws away all Lua state, jobs included, after PLAYER_LOGOUT. So a job
  must never leave saved data half-written across a yield: build in locals (or a
  hidden canvas, as Map's layouts do) and commit in one stretch at the end.
  Telemetry writes the session's `perf` at PLAYER_LOGOUT.
- Lists are walked with their length read once: a step or handler added during a
  pass runs from the next. Timers added by a timer callback are kept. Jobs are
  walked to the end, so one started this frame runs this frame.
- After a hitch, `After` timers fire once, late; an `Every` fires once and its next
  is one period from now.
- `Runtime.onError` runs under `pcall` with a re-entry guard; if it fails it's
  switched off for the session, printed once. Telemetry's global error handler
  records under `pcall`, ignores errors raised while it records, and always passes
  the error on to the previous handler.

## Not guaranteed

- An infinite loop that never yields freezes the client: nothing in WoW's Lua can
  interrupt it.
- Event handlers called by the client between frames can't be delayed: only ones
  fired during our frame are queued.
- Memory is sampled as the whole Lua heap (`collectgarbage("count")`: every addon)
  every 10 s outside graces; ours alone (`GetAddOnMemoryUsage`), after a full collect, only
  twice: 10 s after login and at logout, since a full collect and `UpdateAddOnMemoryUsage`
  are too slow to call while playing (the one at load is graced as `gc`). That collect walks
  every addon's heap and Blizzard's UI too: a visible hitch (tens to hundreds of ms in the
  client) 10 s after every login and `/reload`. Expected, the price of `ourKBLoad`; not a
  stutter to triage.

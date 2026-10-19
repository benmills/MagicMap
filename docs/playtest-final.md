# The final play-test

One consolidated play-test at the end of the run (D10, decided 2026-10-18), in place of a session
per gate. Each gate's lead adds its user-gate items here: what the sim can't prove (the client's
prices, the look, the feel, taint). The session runs docs/playtest.md's scripts (a)-(e) with these
items folded in; that page has every session's "before", "during" and "after". This page is the
checklist: tick each item as chat answers it, and give the ticked list to the lead with the session.

- **id**: a script step of docs/playtest.md (`a2`), or one added here (`a1r`), in the order to do
  them.
- **Signs**: the docs/parity.md rows (F, S) and docs/evidence/spike-bugs.md rows it proves in game.
- **Gate**: the milestone that put it here.

## First: the reference session (the spike only)

The shot pairs need the spike's side first: docs/evidence/shots/README.md, blocks A-E (O if the
moment comes), MagicMap on and MagicMapAtlas off, then `tools/refshots.py`. Moved here from M0.8
by D10. Without it no shot below can be judged.

## Install

`.venv/bin/python tools/install.py` from main. Quit and restart the client after it: since
sessions #8 and #9 (cd0c82c) the build has a new texture, Textures/PlayerArrow.tga, and `/reload`
doesn't see new files (spike-bugs L5). Before the session, watch the spike's GIFs:
`~/code/MagicMap/docs/zoomable-minimap.gif`, `minimap-to-big-map.gif` and `big-map-zoom.gif`.
The client stays in front during the session, so judge against them from memory and say what
differs in the mark.

## Script (a): Dun Morogh motion

Start at the Kharanos inn, as docs/playtest.md (a): the map small on the Minimap's spot, follow on,
default zoom.

| id | Do | Mark / shot | Signs | Gate |
|---|---|---|---|---|
| a0 | After the 10 s wait: `/mma check art`. Chat: `art: all 36 there`. | `/mma mark a0 art <names>` only if it names a miss | L5, S15, S17 | M1 |
| a1 | First open of the session (`/mma toggle` if hidden), at the Thunderbrew door, cursor off. | `/mma shot small-home` | F1, F2, F19, S1-S3, S9, S11, S19, S22 | M1 |
| a1h | Cursor resting on the map left of the arrow, not on a pin: the controls show, the title gains coordinates. | `/mma shot small-hover` | F2, F3, S6, S10, S13, S17-S19 | M1 |
| a1d | Drag the map ~40 px east (follow turns off), cursor resting on the map. Then cursor off and wait: it glides back to you after 6 s. | `/mma shot small-drag`; `/mma mark a1d idle <back after ~6 s, or what>` | F6, F7, S18, S28, S29 | M1 |
| a1r | Alt-Z twice (the UI hidden, then back); then `/mma toggle` twice (Blizzard's minimap, then ours). Each time the map fills in as at the first open, tiles first, briefly, with no hitch (M1.3: a re-open lays the layers out again). | `/mma mark a1r reopen <ok, or what>` | P1, F12 | M1 |
| a1b | The ground, cursor off: wheel out to 62-80 (Ironforge's border on its shadow, zone names in capitals), in to 250-300 (subzone borders and names), in to 800 (the closest). Your arrow: the Minimap's own, its shadow softened, turning smoothly as you turn. Then back to the default zoom. | `/mma shot small-zone`; `/mma shot small-town`; `/mma shot small-near`; `/mma mark a1b arrow <ok, or what>` | F12-F16, F20, S31-S33, S35-S38, S41 | M1 |
| a1c | A herb or a vein in view: cast Find Herbs or Find Minerals off, then on (spellbook; skip without the profession). It shows within about 1 s. | `/mma mark a1c herb <seconds>` | F19 (M1.5b) | M1 |
| a2 | The wheel, as the MVP (docs/playtest.md a2): a tick at a time 16→800→16, then as fast as the wheel turns (every notch a tick, the glide stacking); on a trackpad or Magic Mouse a flick and a slow drag. Against zoomable-minimap.gif: the glide, and the ground covered at the edges zooming out fast (M1b: names and pins may miss the edges for a few frames of the fastest scroll). | `/mma mark a2 wheel mouse <ok, or what>`; `/mma mark a2 wheel trackpad <ok, or what>`: their `wheel` cam traces (delta, n, dt) show what each device sends | F5, S26, S30, P1 | M1, M1b |
| a3 | Fling: drag-pan fast in several directions, release, let it settle. No blank edges (borders and tiles keep up), no hitch. | `/mma mark a3 fling` | P1, F12, F15 | M1 |
| a3b | Mount and ride a loop past herbs, veins or Kharanos' services, then stop. Blips met riding settle on their spots once you stop, none doubled. If two of one name sit within a few yards: `/mma toggle`, hover Blizzard's minimap where they overlap (the tooltip names it twice, or once), `/mma toggle` back. A blip that appears while you stand still (a respawn) can take up to ~40 s: say if that bothers you. | `/mma mark a3b blips <ok, or what>`; `/mma mark a3b twin <twice, once>` (if it came up) | D3, F19 | M1 |
| a4 | The tear walk (docs/playtest.md): Kharanos, x = 47.4, at 800, small, follow on, 2 minutes. | `/mma mark a4 walk` at ~1 min; `/mma shot small-seam` on the line; `/mma mark a4 tear <what>` on any tear | F12, plan §2 "tear" | M1 |
| a5 | Grow and shrink x5 (M, or the red button), each animation ended. Against minimap-to-big-map.gif. Then M once more, cursor off as it lands; then cursor on the gear until its tip shows. | `/mma mark a5 grow <ok, or what differs>` after the 5th; `/mma shot big-home`; `/mma shot big-hover` | F3, F10, F11, F50, S1, S2, S9-S11, S15, S16, S20, S24, S25 | M1 |
| a5g | The gear (`Layers & settings`), big as a5 left it: click it. A submenu per group of layers (Map, Places, People; Other addons too when an addon with world-map pins, such as Questie, is loaded), a line, then Settings. Hover each row: its tip, a white title over gold text. Turn each layer off and on from its row: it goes at once and comes back, the menu staying open. Shrink (M) and open the gear on the small map: the same rows. Settings > Map: Colour-matched tiles off and on (the art plain, then tinted). Settings > Minimap: Minimap button off and on (the rim button goes and comes back); move the window, then Reset position (back on the Minimap's spot, following); Use Blizzard's minimap (ours hides), then `/mma toggle` (back). Grow (M) for a5b, Zone labels left on. The user's question this answers: do the settings work, and is it clear how to use them. | `/mma shot big-gear` (Gear → Map open, cursor on Zone borders); `/mma mark a5g gear <ok, or what doesn't work or isn't clear>` | F11, F48, F49, F55, S60, S61 | M1b |
| a5b | Big, Dun Morogh centred, 80-100, cursor off. Then 140-200 and pan about (up to ~2750 border Lines). Then `/mma bench regions`, standing still, once (it hitches; a box flickers with lines): wait for its result. Shrink. | `/mma shot big-zones`; `/mma mark a5b borders` after the pan | P4, F15, S30, S32, S36 | M1 |
| a6 | Ironforge, as docs/playtest.md a6. | `/mma shot small-indoor`; `/mma shot big-indoor` | (F24: M4) | — |
| a7 | Big, all the way out (16-24), pan the Eastern Kingdoms. Against big-map-zoom.gif. Then `/mma tint` twice (the art plain, then tinted again). | `/mma shot big-continent`; `/mma mark a7 continent <ok, or what differs>` | F5, F13, F16, S4, S26, S31 | M1 |
| a7b | Still big: `/mma reset` answers `reset: shrink the map back first (M)`. Shrink (M). Move the window by its title, by its border, and Alt-drag on the map; resize it by the grip (the yards across kept); push it against the screen's edge (it stays on screen). Then `/mma reset`: back on the Minimap's spot, following. | `/mma mark a7b window <ok, or what>` | F8, F9, S5, S7, S14, S23 | M1 |

## Script (b): a 25-quest hub

The rest of (b) is M2's.

| id | Do | Mark / shot | Signs | Gate |
|---|---|---|---|---|
| b6 | Your log at ~25 quests. Walk into a quest's area, `/mma check inside` there (inside), walk out, again (not). | `/mma mark b6 inside <agrees, or what>` | F29 (Inside), L1 | M1 |

## Script (c): keys in combat

| id | Do | Mark / shot | Signs | Gate |
|---|---|---|---|---|
| c4 | As docs/playtest.md c4: in combat, M (Blizzard's map opens, ours doesn't grow), then `/mma check combat` with it open: it prints whether the client blocked hiding it. `/mma toggle` twice in combat: the cluster fades, its hide or show waits for combat's end. | `/mma mark c4 combat keys` after the check's line | F10, K2 | M1 |
| c5 | Out of combat: M (grow), Escape (shrink), L (Blizzard's quest log; close it), `/mma toggle`: Blizzard's minimap back exactly as it was; cursor on our rim button (lower left) for its tip; `/mma toggle` again. | `/mma shot blizzard-rim`; `/mma mark c5 keys` | F1, F10, F52, F53, S21 | M1 |
| c6 | As docs/playtest.md c6: spellbook and talents by keybind in combat. A taint from M's HideUIPanel would name us here. | `/mma mark c6 panels` | K2 | M1 |

## Script (d): a city

| id | Do | Mark / shot | Signs | Gate |
|---|---|---|---|---|
| d1 | In a city (Orgrimmar, where sessions #13 and #14 were, or Stormwind or Ironforge), big: zoom out to about 36 and back in, dragging and wheeling at each zoom, then over the same views again. Shrink, follow on, and walk in and out of a few doors. No blank edges, no hitch on the drags. Then `/mma check report`: it names this build, and no city's or building's own subzone (Valley of Strength) is in it. | `/mma mark d1 city <ok, or what>` | P1, P3, K4 | M1b |

## Script (e): Questie

Questie the only other addon. The rest of (e) is M4's.

| id | Do | Mark / shot | Signs | Gate |
|---|---|---|---|---|
| e1 | Big map in Elwynn at 140, then out to the continent and back: Questie's pins on our map. They're see-through while the zoom moves and come back where it rests (the spike moved each pin every zoom frame): sign it or not. M with Questie loaded can hitch on the key press itself; the spike pays it too: say if it's worse. | `/mma mark e1 pins <ok, or what>` | F46, G6 | M1 |
| e3 | `/mma toggle` (ours off), open Blizzard's world map: their pins are back on it. | `/mma mark e3 pins returned` | F46, G6 | M1 |

## The read (the lead)

`telemetry.py --budgets --trace` and `--shots --marks`. M1 passes when:

- **8/8 PASS**: frame max ≤8 ms; p95 ≤1 ms at rest, p99 at rest and p95 moving ≤5 ms (by map
  state, docs/runtime.md: decision 1 below); first open ≤50 ms (target ≤20); ourKB after GC ≤64 MB
  (~39 expected); allocation ≤50 KB/s; load ≤250 ms; 0 errors. Sessions #8 and #9 (cd0c82c, before
  M1.4 and round 2 of the M1 review) were 7/8: allocation 56.7 and 108.7 KB/s.
- **perf.slow** without `map: borders`, `map: labels`, `map: draw`, `map: layout` or
  `game.observe` (#9 had `game.part blips` at 2.4 ms); **perf.gaps** empty; the `sensor` and `art`
  traces empty (a `sensor` event carries its mark); 0 taint but `/mma check combat`'s own block,
  if the client blocked it; `/mma check log`: 0 K4 drift lines.
- **perf.alloc**: `game.part blips` under 10 KB/s (27-30 in #8 and #9, before e60ff51); `map: layout`
  about one trace a start (0.37 KB in the sim since M1.12, a layout ~1.1 KB with its end and swap; the
  old job start cost 8.6-10.3 KB in the client); `validate.log` near 0 (3.4 KB/s in #13-#22). A session
  that zooms a city's big window out reads its canvases filling as allocation (~7,000 regions, ~3.6 MB,
  kept in their pools, made once a session: over 50 KB/s in a short session, ~6 KB/s over 10 minutes):
  the budget can't tell pool growth from garbage, so judge it over the whole session (M1b, d1).
- **The bench** (a5b): `canvas.SetAlpha.moved@1000live` far under `canvas.Show.moved@1000live`, and
  `frame.swap` about `frame.idle`; else the swap extends in place (M1.3's fallback). Also
  `canvas.Show.moved.alpha0@1000live` and `canvas.Show.moved@100masked`.
- **byState.zoom.client** against `small`: what scaling the borders while zooming costs the client
  (S30, P4). `swap <layer>` under 4 ms.
- **Shots**: each answered `shot <id>: WoWScrnShot_<stamp>, marked`, paired with `ref-<id>.jpg`:
  small-home, small-hover, small-drag, small-near, small-seam, small-town, small-zone, big-home,
  big-hover, big-gear (M1b), big-zones, big-continent, blizzard-rim. A seam on small-seam is M1.4's seam overlap
  (1 px right and bottom, half-texel inset), built only if a shot shows one.

## Decisions for you at the session

1. **Budgets by map state** (M1 review round 2, ebdf22e, an agent's change): p95 ≤1 ms at rest
   only, ≤5 ms moving. The plan's M1 exit and §1 gate 3 read p95 ≤1 and p99 ≤5 over the whole
   session, which script (a)'s shape fails on the priced clock (p95 1.55, p99 4.6 ms since M1.14,
   1.95 / 5.55 before; at rest 0.2, zooming 4.5). Keep it, or ask for smaller slices while moving (borders fall behind a fling:
   R-P1).
2. **The wheel** (a2): the MVP's again since M1.14 (M1b: every event a x1.3 tick), so one trackpad
   flick can run to the clamp, the thing M1.8b's rationing answered ("too sensitive"). Keep it, or
   change it from what the `wheel` cam traces show each device sends (delta, n, dt).
3. **M in combat** (c4): blocked, the guard stays, a deviation from the spike to sign (F10, K2);
   not blocked, the guard goes.
4. **The sea** (a7, S31): keep the rebuild's (Data/Sea, feather masks) or port the spike's
   gradient coast fades (Core.lua:441-700).
5. **Subzone borders** (a1b, S33): Gaussian-smoothed, rounder, about half the points, against the
   spike's Douglas-Peucker 0.035 + Chaikin.
6. **Labels re-placed** (a1b, a2, S38) when the zoom leaves [0.7, 1.4] and at settle, not after the
   spike's log(1.25) drift. Zooming out over several notches (M1.14), names are laid out for where
   the zoom is headed, so subzone names drop as it starts, not when it crosses 120.
7. **The world socket** (e1, F46): Questie's pins see-through while the zoom moves.
8. **Borders zooming out fast** (a2, S30): as the spike's, the old borders are scaled and dimmed to
   0.25 until the zoom's goal holds 0.1 s, then crossfade in; a fast burst leaves them nearly out of
   sight for about 0.25 s (the spike restarts its layout every frame of a burst: the same gap).
9. **Slow discovery** (a3b): a blip appearing while you stand still found within ~40 s, not 0.5 s.

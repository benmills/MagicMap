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
| a0 | After the 10 s wait: `/mma check art`. Chat: `art: all 40 there` (M3 added the tombstone, the quest disc under it, the waypoint pin and the edge arrow). | `/mma mark a0 art <names>` only if it names a miss | L5, S15, S17 | M1 |
| a1 | First open of the session (`/mma toggle` if hidden), at the Thunderbrew door, cursor off. | `/mma shot small-home` | F1, F2, F19, S1-S3, S9, S11, S19, S22 | M1 |
| a1h | Cursor resting on the map left of the arrow, not on a pin: the controls show, the title gains coordinates. | `/mma shot small-hover` | F2, F3, S6, S10, S13, S17-S19 | M1 |
| a1d | Drag the map ~40 px east (follow turns off), cursor resting on the map. Then cursor off and wait: it glides back to you after 6 s. | `/mma shot small-drag`; `/mma mark a1d idle <back after ~6 s, or what>` | F6, F7, S18, S28, S29 | M1 |
| a1g | Small, following: drag the map about its width east and let go, cursor off. After 6 s it glides back to you. Tiles, names and pins stay on the map the whole way. The borders should too: M1.15 is meant to fix them before this session; at the M1b gate they missed the map's edges for most of the glide (test_feel). | `/mma mark a1g glide <ok, or what>` | F7, F15, S29, P1 | M1b |
| a1r | Alt-Z twice (the UI hidden, then back); then `/mma toggle` twice (Blizzard's minimap, then ours). Each time the map fills in as at the first open, tiles first, briefly, with no hitch (M1.3: a re-open lays the layers out again). | `/mma mark a1r reopen <ok, or what>` | P1, F12 | M1 |
| a1b | The ground, cursor off: wheel out to 62-80 (Ironforge's border on its shadow, zone names in capitals), in to 250-300 (subzone borders and names), in to 800 (the closest). Your arrow: the Minimap's own, its shadow softened, turning smoothly as you turn. Then back to the default zoom. | `/mma shot small-zone`; `/mma shot small-town`; `/mma shot small-near`; `/mma mark a1b arrow <ok, or what>` | F12-F16, F20, S31-S33, S35-S38, S41 | M1 |
| a1c | A herb or a vein in view: cast Find Herbs or Find Minerals off, then on (spellbook; skip without the profession). It shows within about 1 s. | `/mma mark a1c herb <seconds>` | F19 (M1.5b) | M1 |
| a2 | The wheel, as the MVP (docs/playtest.md a2): a tick at a time 16→800→16, then as fast as the wheel turns (every notch a tick, the glide stacking); on a trackpad or Magic Mouse a flick and a slow drag. Against zoomable-minimap.gif: the glide, and the ground covered at the edges zooming out fast (names and pins may miss the edges for a few frames of a trackpad's fastest flick; none on the mouse wheel's fast scroll, priced); rares appearing as the zoom passes 60, names changing every quarter zoom; after a drag, the idle return's glide keeps the pins on the map. | `/mma mark a2 wheel mouse <ok, or what>`; `/mma mark a2 wheel trackpad <ok, or what>`: their `wheel` cam traces (delta, n, dt) show what each device sends | F5, S26, S30, P1 | M1, M1b |
| a3 | Fling: drag-pan fast in several directions, release, let it settle. No blank edges (borders and tiles keep up), no hitch. | `/mma mark a3 fling` | P1, F12, F15 | M1 |
| a3b | Mount and ride a loop past herbs, veins or Kharanos' services, then stop. Blips met riding settle on their spots once you stop, none doubled. If two of one name sit within a few yards: `/mma toggle`, hover Blizzard's minimap where they overlap (the tooltip names it twice, or once), `/mma toggle` back. A blip that appears while you stand still (a respawn) can take up to ~40 s: say if that bothers you. | `/mma mark a3b blips <ok, or what>`; `/mma mark a3b twin <twice, once>` (if it came up) | D3, F19 | M1 |
| a4 | The tear walk (docs/playtest.md): Kharanos, x = 47.4, at 800, small, follow on, 2 minutes. | `/mma mark a4 walk` at ~1 min; `/mma shot small-seam` on the line; `/mma mark a4 tear <what>` on any tear | F12, plan §2 "tear" | M1 |
| a5 | Grow and shrink x5 (M, or the red button), each animation ended. Against minimap-to-big-map.gif. Then M once more, cursor off as it lands; then cursor on the gear until its tip shows. | `/mma mark a5 grow <ok, or what differs>` after the 5th; `/mma shot big-home`; `/mma shot big-hover` | F3, F10, F11, F50, S1, S2, S9-S11, S15, S16, S20, S24, S25 | M1 |
| a5g | The gear (`Layers & settings`), big as a5 left it: click it. A submenu per group of layers (Map, Places, People; Other addons too when an addon with world-map pins, such as Questie, is loaded), a line, then Settings. Hover each row: its tip, a white title over gold text. Turn each layer off and on from its row: it goes at once and comes back, the menu staying open. Shrink (M) and open the gear on the small map: the same rows. Settings > Map: Colour-matched tiles off and on (the art plain, then tinted). Settings > Minimap: Minimap button off and on (the rim button goes and comes back); move the window, then Reset position (back on the Minimap's spot, following); Use Blizzard's minimap (ours hides), then `/mma toggle` (back). Grow (M) for a5b, Zone labels left on. People > Rares you've seen: until M4.3 it draws every rare spawn the data knows (QuestieDB), not only those you've seen, whatever its tip says (the spike's): judge the toggle, not the tip. The user's question this answers: do the settings work, and is it clear how to use them. | `/mma shot big-gear` (Gear → Map open, cursor on Zone borders); `/mma mark a5g gear <ok, or what doesn't work or isn't clear>` | F11, F48, F49, F55, S60, S61 | M1b |
| a5b | Big, Dun Morogh centred, 80-100, cursor off. Then 140-200 and pan about (up to ~2750 border Lines). Then `/mma bench regions`, standing still, once (it hitches; a box flickers with lines): wait for its result. Shrink. | `/mma shot big-zones`; `/mma mark a5b borders` after the pan | P4, F15, S30, S32, S36 | M1 |
| a6 | Ironforge, as docs/playtest.md a6. | `/mma shot small-indoor`; `/mma shot big-indoor` | (F24: M4) | — |
| a7 | Big, all the way out (16-24), pan the Eastern Kingdoms. Against big-map-zoom.gif. Then `/mma tint` twice (the art plain, then tinted again). | `/mma shot big-continent`; `/mma mark a7 continent <ok, or what differs>` | F5, F13, F16, S4, S26, S31 | M1 |
| a7b | Still big: `/mma reset` answers `reset: shrink the map back first (M)`. Shrink (M). Move the window by its title, by its border, and Alt-drag on the map; resize it by the grip (the yards across kept); push it against the screen's edge (it stays on screen). Then `/mma reset`: back on the Minimap's spot, following. | `/mma mark a7b window <ok, or what>` | F8, F9, S5, S7, S14, S23 | M1 |

## Script (b): a 25-quest hub

M2.4's items (quest pins, offers, areas and their tooltip) are b12-b19, added at the M2 review, and b20 at
the M2 gate; b8-b10 need them drawn. Start as docs/playtest.md (b): a hub with your log at about 25 quests, some complete, offers near.

| id | Do | Mark / shot | Signs | Gate |
|---|---|---|---|---|
| b6 | Your log at ~25 quests. Walk into a quest's area, `/mma check inside` there (inside), walk out, again (not). | `/mma mark b6 inside <agrees, or what>` | F29 (Inside), L1 | M1 |
| b7 | Big, at a hub with blips about (and a seen rare if one's near): hover a blip, then a rare. Its tooltip stands to the right of the pin, its name then small grey lines, and goes as the cursor leaves it. Press on a pin and drag: the map pans, no tooltip left behind. Hover a pin under the window's buttons (zoom +/-, the gear): the button's tip only, no pin's. Zoom in and out over where pins were: no tooltip from a pin that's gone. | `/mma mark b7 tips <ok, or what>` | F51, S42, S45, S50, G7, D1 | M2 |
| b8 | Super-track a quest from Blizzard's objective tracker: our map shows it followed within a frame (its pin's glow, once M2.4 draws quest pins). Click one of our quest pins: Blizzard's tracker super-tracks it and watches it (C_QuestLog.AddQuestWatch); click again: none. | `/mma mark b8 follow <ok, or what>` | F31 | M2 |
| b9 | Open the big map on a continent you haven't shown this session: quests to pick up appear about 0.4 s later (every zone of it asked at once). Turn Track Hidden Quests on (the Minimap's tracking menu): the hidden ones appear; off: gone. | `/mma mark b9 offers <ok, or what>` | F40 | M2 |
| b10 | Mouse over, target, or see the nameplate of a mob a quest needs, then hover that quest's pin: the mob's line in its tooltip shows its portrait over a dark disc (up to 3 mobs an objective). A mob never met keeps the plain icon. | `/mma shot big-quest-tip`; `/mma mark b10 portraits <ok, or what>` | F28, S63 | M2 |
| b11 | Loot quest items quickly for about 10 s (a QUEST_LOG_UPDATE storm), the map open: `/mma mark b11 before` just before, `/mma mark b11 storm` right after. Then the same with it hidden (`/mma toggle`). No hitch; `game.part quests` never in the read's perf.slow. Each storm mark's `alloc` (since the mark before it: `telemetry.py --marks`; the session's perf.alloc averages the whole session) ≤50 KB/s, `game.part quests` under ~40 KB/s open, nothing hidden, no `game.part offers` (test_quests_storm, priced, the sim's C_ calls making their tables anew as the client's: 39.5 KB/s, `game.part quests` 36.2, 0 hidden). | `/mma mark b11 before`, `/mma mark b11 storm` (open); `/mma mark b11 before hidden`, `/mma mark b11 storm hidden` | F26 | M2 |
| b12 | `/reload` at the hub (the next open is the session's first), the 10 s wait, then open the map small at the default zoom: the quest-heavy first open, its slowest frame ≤50 ms in the read (test_quests_first_open, priced: 6 ms, its slowest call `map: rares` 5.3). | `/mma shot small-quests` | F26, F40, S46 | M2 |
| b13 | Hover quest pins: a kill, a collect, one ready to turn in, an offer (`!`), the followed one. Each tooltip as the spike's: the title in its difficulty colour, the facts line (level, tag, ready), objectives, up to 3 droppers (lowest first, `(+N more)`), apart and dim `Turn in to` and the click hint. Hover a quest's area where no pin is: the area lights (drawn again on top), its quest's tooltip shows; onto a pin inside another quest's area: the pin's. | `/mma shot big-quest-tip` (on a collect quest's pin); `/mma mark b13 tooltips <ok, or what>` | F28, F51, S53 (hover), S63 | M2 |
| b14 | Click a quest's area where no pin is: Blizzard's tracker super-tracks that quest; again: none. A pin inside another's area: the pin's quest, not the area's. | `/mma mark b14 area click <ok, or what>` | F31 | M2 |
| b15 | Big, wheeled until the quest areas fill the map: each in the client's own art, the followed one filled blue, the rest a quiet edge (kill rust, collect green, other blue); a kill or collect quest the game gives no area gets a faint dashed disc (one for two close), none where an area covers its pin. Follow one by its pin. | `/mma shot big-quests` (before the follow); `/mma shot big-quest-follow` (after); `/mma mark b15 areas <ok, or what>` | F29, F30, S46, S53, S54 | M2 |
| b16 | Areas through a zoom and a drag, an area in view: wheel 60 → 140 → 384 and back: out of sight while the zoom moves, back on their pins where it lands (not offset, not squashed); the cursor resting on an area through a wheel tick keeps its tooltip. Then drag the map about 200 px, slowly, and fling it: the areas move with the map, on their pins every frame (a pan never draws them again: the spike's Layers.lua:142-156). The sim moves a drawing with its frame since the M2 gate (R-P5's drag and fling, 0.000 px off); this checks the client does. | `/mma mark b16 areas zoom <ok, or what>`; `/mma mark b16 areas drag <ok, or what>` | P5, L1, F29, S53 | M2 |
| b17 | Accept a quest from an offer (`!`) on the map: its `!` goes and its quest pin comes, never both in a frame; abandon one: its pin goes and its `!` comes back; hand one in whose next quest is offered near: its pin goes and the next one's `!` comes. Each within about 0.3 s, as the spike's. Finish a quest's objective: its pin and area move to the next objective or the turn-in with its count. Not every QUEST_LOG_UPDATE reads them now (the spike's did): where pins are, on QUEST_ACCEPTED, QUEST_REMOVED, QUEST_POI_UPDATE or a count or quest done; what's offered, on QUEST_ACCEPTED, QUEST_REMOVED, a level, QUESTLINE_UPDATE or tracking. An offer that comes with none of those (a reputation, a profession) waits for the next: say if one does. | `/mma mark b17 offer taken <ok, or what>` | F26, F40, D1 | M2 |
| b18 | Standing at the hub (your quests on your map): `/mma bench regions` once (it hitches; a box flickers): its `poi.*` lines price the client's quest areas (DrawBlob a quest, a frame's draw, the hit test, the frame after); the lead sets `Sim.PRICES` from them. Pass: `poi.DrawBlob` at most about 0.06 ms a quest (with 25 quests `map: quest areas` stays under CALL_MS and the zoom's p95 at or under 5 ms: test_quests_priced with a planted cost passes at 0.05 ms, fails at 0.1). Over it, Front's second draw is spread over frames, a frame's quests a frame. | `/mma mark b18 bench` after its result | S53, F29 | M2 |
| b19 | After about 10 minutes questing at the hub, the map shown (kills, loot, an objective or two finished): `/mma perf load poi` and `/mma perf load quest`. The calls of `game.oracle: poi update` (one a QUEST_POI_UPDATE) against `game.quests` (the quests part's events): how often this client says the game's areas changed. Each costs a read of the zones and the areas drawn again, no entry or pin (test_quests_ticks: a count every 2 s, 17.8 KB/s without, 19.3 with one each time). | `/mma mark b19 poi <its calls>, <game.quests' calls> in <minutes>` | F29, S53 | M2 |
| b20 | With quests in Stranglethorn (or another big zone: Stranglethorn is 12 tiles by 8), fly or ride there from another zone with the map open, then big, wheel in to the clamp (800) over their areas, and drag a little. Each area stands on its pin, its shape as at zoom 100, not squashed into a sliver nor off to one side. The M2 gate found an area frame keeping two anchors once the corner it stands on changed, which sized Stranglethorn's 9,572 px frame 515 x 114 (fixed: ee26c4f; test_quest_area_big_zone). | `/mma mark b20 big zone <ok, or what>` | F29, S53, L1 | M2 |

## Script (c): route, corpse run, keys in combat

Start (docs/playtest.md script (c)): Dun Morogh or Elwynn, a quest followed whose area is off the view.

| id | Do | Mark / shot | Signs | Gate |
|---|---|---|---|---|
| c1 | Small, following: follow a quest whose area is off the view (click its pin). A hand-inked dashed line from you to the area's nearest edge (not its pin), a light stroke over a dark edge, uneven, faded at both ends, along the way you'd walk (round cliffs and deep water); the gold edge arrow 16 px inside the window's edge where the line leaves the view, pointing on. Walk toward it: the line keeps to the route (no hop sideways onto a detour, no straight flash while it's found again); step into the area and stay 0.5 s: the line and arrow step aside, the title (hovered) says `<title> here`. Against `~/code/MagicMap/MagicMap-path-mode.gif`. `model: route` and `map: path` never in perf.slow (the first draw of a long line wholly in view priced 1.99 ms in test_path_priced at 720 x 520: a bigger window could pass 2 ms). | `/mma shot small-edge-arrow` (before walking); `/mma mark c1 route <ok, or what>` | F32, F33, F34, S55-S59, M1, P2 | M3 |
| c1b | Big (M), cursor off the map: the title band ends `<title> N yd` (yards to the target, rounded), and small with the cursor on the map too. Stand still 10 s: the line doesn't flicker (no redraw standing); wheel in and out over it: it's laid out again at each zoom. | `/mma mark c1b title <ok, or what>` | S12, S58 | M3 |
| c2 | Big, Kharanos at 300-400: Ctrl-click the map: the cyan waypoint pin, Blizzard's tracker super-tracks it, the line now goes to it. Ctrl-right-click: cleared. Ctrl-click far out at sea: no waypoint, the press pans the map (a sea chunk outside every zone's map: Atlas.ZoneMapAt). Shift-click: the chat box opens on `/way <zone> x y`, not sent (that it opens at all checks `ChatFrame_OpenChat` or `ChatFrameUtil.OpenChat` on the 16001 client); press Escape to close it. Then, with `/console taintLog 1`, in combat type `/target <a mob>` in chat and use an action-bar ability (the box's state was written from our code): 0 ADDON_ACTION_BLOCKED and 0 taint naming MagicMapAtlas. Right-click: Waypoint here, Clear waypoint (one set), Follow me (not following). Hover the waypoint pin: `Waypoint`, `Ctrl-right-click the map to clear`. | `/mma shot big-waypoint` (a waypoint set, the line to it); `/mma mark c2 waypoint <ok, or what>`; `/mma mark c2 way taint <ok, or what>` | F35, F36, F37, S49, S55-S57 | M3 |
| c2b | Big, right-click a spot in Elwynn (the reference session's spot): the menu leads with the inspector: the zone in gold; its subzones and coordinates; `Level a-b` in green, red or grey against yours, how far (5 yd steps close, 10 further, thousands with commas, `You're here` close by) and which way from you; up to 2 quests whose areas hold the spot (the followed one gold, `(following)`). Against the spike's ZoneInfo at the same spot: the level line here is the subzones' exploration levels (Elwynn 5-10, Dun Morogh 4-56 with the Ironforge Submarine Facility), the spike's the client's map levels (Elwynn 1-10): say which you want. The subzones are Atlas's (the spot's area chain), not the client's explored ones. | `/mma shot big-inspector`; `/mma mark c2b inspector <ok, or what differs>` | F37, F38, S62 | M3 |
| c2c | Big, Eastern Kingdoms at 16: click the zone name: the map picker (Continents, Other maps, Instances by the continent of their entrance); pick Kalimdor: its map whole, following off; Blizzard's minimap cluster stays hidden while you browse (spike-bugs G2). `/mma map` alone lists the maps; `/mma map Deadmines`: its map whole, no arrow, line, blips or borders; `/mma zone Westfall`: it flies there (0.55 s). Drag the zone name: the window moves, no picker. Right-click, Follow me: back to you. | `/mma shot big-picker` (the picker open); `/mma mark c2c picker <ok, or what>` | F4, F11, F18, S60, G2 | M3 |
| c2d | Big, Dun Morogh at 80-100, several zones in view: hover one: its name brightens and its border is drawn over the borders (under the route line) once the map rests; click: it flies there (fit 0.92), following off. A quest's area under the cursor isn't clickable while zone clicks are on offer; a pin is. Against `~/code/MagicMap/docs/pick-and-fly.gif`. | `/mma mark c2d zone hover <ok, or what>` | F17, S34, S36 | M3 |
| c3 | As docs/playtest.md c3: die (pull mobs well above your level), drag the map away, release. A few seconds after release the client knows where your corpse is: the tombstone pin within about a second of that, the view glides back to you and the line runs to the corpse. Corpse run; resurrect: the pin and the line gone. | `/mma shot small-corpse` while a ghost, small; `/mma mark c3 corpse <ok, or what>` | F42, F7, S49, G4 | M3 |
| c4 | As docs/playtest.md c4: in combat, M (Blizzard's map opens, ours doesn't grow), then `/mma check combat` with it open: it prints whether the client blocked hiding it. `/mma toggle` twice in combat: the cluster fades, its hide or show waits for combat's end. | `/mma mark c4 combat keys` after the check's line | F10, K2 | M1 |
| c5 | Out of combat: M (grow), Escape (shrink), L (Blizzard's quest log; close it), `/mma toggle`: Blizzard's minimap back exactly as it was; cursor on our rim button (lower left) for its tip; `/mma toggle` again. | `/mma shot blizzard-rim`; `/mma mark c5 keys` | F1, F10, F52, F53, S21 | M1 |
| c6 | As docs/playtest.md c6: spellbook and talents by keybind in combat. A taint from M's HideUIPanel would name us here. | `/mma mark c6 panels` | K2 | M1 |
| c7 | `/console taintLog 1` first. Out of combat, follow a quest that has a usable item by its pin, then by its area (the usual path: Blizzard's tracker re-lays out from our call); enter combat, advance one of its objectives, use its item from Blizzard's tracker. Then in combat, with a quest item in the tracker: click our quest pin to follow it and again to stop, then a quest's area to follow it; then use the tracker's item button. Then, still in combat with the quest item in the tracker, big: Ctrl-click the map (a waypoint, super-tracked: the quest no longer), Ctrl-right-click to clear it, then use the tracker's item button. 0 ADDON_ACTION_BLOCKED and 0 taint naming MagicMapAtlas (our follow super-tracks and watches, our waypoint sets, super-tracks and clears, from insecure code: R-K2 records each path in the sim, not refused there). | `/mma mark c7 follow <ok, or what blocked>` (out of combat, after the item); `/mma mark c7 follow in combat <ok, or what blocked>`; `/mma mark c7 waypoint in combat <ok, or what blocked>` | F31, K2 | M2 |

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
| e4 | Big, where a Questie pin overlaps one of ours (a blip, a rare): hover the overlap. Questie's tooltip shows, not ours, and never both (this leans on the client sending the view OnLeave when a frame that takes the mouse covers it). | `/mma mark e4 overlap <ok, or what>` | F51, G7 | M2 |

## The read (the lead)

`telemetry.py --budgets --trace` and `--shots --marks`. M1 and M1b pass when:

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
  kept in their pools, made once a session: over 50 KB/s in a short session, ~6 KB/s over 10 minutes;
  R-P3b at the M1b gate: 7333 regions, its first pass 158.4 KB/s with 8.9 of garbage, all 76 s 65.8):
  the budget can't tell pool growth from garbage, so judge it over the whole session (M1b, d1).
- **The bench** (a5b): `canvas.SetAlpha.moved@1000live` far under `canvas.Show.moved@1000live`, and
  `frame.swap` about `frame.idle`; else the swap extends in place (M1.3's fallback). Also
  `canvas.Show.moved.alpha0@1000live` and `canvas.Show.moved@100masked`. A minimum zoom crossed:
  `reveal.frame@500` and `frame.reveal.frame` (the engine's: 500 pins shown by their frame's SetAlpha)
  against `reveal.each@500` and `frame.reveal.each` (a SetAlpha a pin); if the frame's costs like a
  Show of its moved children, reveal the pins a slice a frame instead (M1b review, round 2).
- **byState.zoom.client** against `small`: what scaling the borders while zooming costs the client
  (S30, P4). `swap <layer>` under 4 ms.
- **Script (b)** (M2): 8/8 PASS with ~25 quests; the quest-heavy first open (b12) ≤50 ms; b11's storm
  marks' `alloc` ≤50 KB/s, `game.part quests` under ~40 KB/s and nothing while hidden; the bench's `poi.*`
  (b18) against its pass line and into `Sim.PRICES` (DrawBlob is priced as any widget call until then),
  then test_quests_priced again; b19's QUEST_POI_UPDATEs a minute. M2.4's sim budgets hold for frames, for
  allocation at rest and through the storm and ticking counts; allocation while zooming and dragging is
  M1's borders (test_quests_priced's wheel and drags, that stretch alone: 443 KB/s with 25 quests, 426
  without, `map: borders` ~390, `map: quest areas` 6.8): judged with M1.15 and script (a)'s reads, not
  blamed on quests.
- **Script (c)** (M3): 8/8 PASS; `model: route` and `map: path` never in perf.slow (route jobs: a
  1 ms job, 1.05 ms its slowest resume in R-P2); 0 taint in combat toggles; the line against
  MagicMap-path-mode.gif (c1), the inspector against the spike's ZoneInfo (c2b).
- **Shots**: each answered `shot <id>: WoWScrnShot_<stamp>, marked`, paired with `ref-<id>.jpg`:
  small-home, small-hover, small-drag, small-near, small-seam, small-town, small-zone, big-home,
  big-hover, big-gear (M1b), big-zones, big-continent, blizzard-rim; small-quests, big-quests,
  big-quest-follow, big-quest-tip (M2); small-edge-arrow, big-waypoint, big-inspector, big-picker,
  small-corpse (M3). A seam on small-seam is M1.4's seam overlap
  (1 px right and bottom, half-texel inset), built only if a shot shows one.

## Decisions for you at the session

1. **Budgets by map state** (M1 review round 2, ebdf22e, an agent's change): p95 ≤1 ms at rest
   only, ≤5 ms moving. The plan's M1 exit and §1 gate 3 read p95 ≤1 and p99 ≤5 over the whole
   session, which script (a)'s shape fails on the priced clock (p95 1.8, p99 4.7 ms since the M1b
   review's second round, the layouts sharing each moving frame's budget in turn; 1.55 / 4.6 at
   M1.14, 1.95 / 5.55 before; at rest 0.2, zooming 4.5: docs/runtime.md). Keep it, or ask for smaller slices while moving (borders fall behind a fling:
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
6. **Names and pins while zooming** (a1b, a2, S38, F21, F43): as the spike's since the M1b review's
   second round: names laid out at the zoom shown on the frame it drifts log(1.25) from theirs and the
   frame it lands, rares and remembered blips shown from zoom 60 the frame it's crossed, pins kept on
   the map through a glide. The ground goes first, so on the fastest flicks names can be chosen for a
   zoom a few drifts off while it lays out (priced: 3.7 drifts flicking the big window to the clamp,
   one frame past a drift at most otherwise), and names and pins can miss the view's edges for a few
   frames (4 in a trackpad's burst, 1 flicking the big window to the clamp; none on a mouse wheel's
   fast scroll or growing mid-zoom).
7. **The world socket** (e1, F46): Questie's pins see-through while the zoom moves.
8. **Borders zooming out fast** (a2, S30): as the spike's, the old borders are scaled and dimmed to
   0.25 until the wheel stops, then laid out where the zoom is headed and crossfaded in. The spike
   starts that layout the frame after the last tick at 8 ms slices beside everything else; ours lays
   out the ground, names and pins first (the layouts share a frame's budget in turn), so it lands about
   0.1 s after the spike's (8 notches out from 400, one a frame, priced: its layout starts 6 frames
   after the last tick and lands that frame).
9. **Slow discovery** (a3b): a blip appearing while you stand still found within ~40 s, not 0.5 s.

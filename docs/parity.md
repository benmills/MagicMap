# Parity with the spike

The checklist behind gate 1 of docs/v1-plan.md §1. It lists every spike feature (§5) and every
style value (§4) with the package that ships it, what proves it, and the reference shot it's judged
against. The non-goals are here too, as rows that are out by decision. 1.0 ships when every row is
`signed` or `out, by decision`.

- **Spec**: the spike's code, `~/code/MagicMap` at 1.0.0 (D4), not its release notes. The style
  values are copied verbatim from §4, and the spike ref is the `file:line` there. Packages copy
  them as constants, with that ref in a comment.
- **Who edits**: only the lead, once per gate, from the packages' hand-offs (v1-plan §3). The
  user signs rows at M5.3 against the shot pairs.
- **Status**: `todo` → `built <pkg> <sha>` (lead, from a hand-off) → `signed` (user, with its
  shot pair). `out, by decision` means not in v1.
- **Proof**: `sim:` a sim scenario or replay in tools/tests (named as in the plan's Verify
  columns; most land with their package). `tel:` a gate session read with `tools/telemetry.py`.
  `game:` a step in a gate script. `gif:` the spike's GIFs, for motion that a still can't show.
  `shot` means a shot pair: a gate's `/mma shot <id>` beside `docs/evidence/shots/ref-<id>.jpg`.
- **Shot**: `id` (spot uiMap, zoom, form). Zoom is the spike's, in screen units per tile (16..800).
  `home` is the minimap's spot after `/mm reset` (200 yd across), and `big home` is where M
  lands (home ÷ 1.5). The list, and how the session was run: docs/evidence/shots/README.md.
  `(opt)` marks an optional shot, which exists only if the moment came up.
- **Now**: the rebuild before M1, from §5: B built, P partial, M missing.

## Features (§5)

| # | Feature | What | Package | Proof | Shot | Now | Status |
|---|---|---|---|---|---|---|---|
| F1 | Takes the minimap's spot, exact release | Square on Blizzard's minimap home rect at the cluster's strata. Blizzard's Minimap becomes an unseen sensor. Hiding the window or `/mma toggle` gives every property back. | M1.6, M1.7 | sim: test_chrome (home placement), release restores every property, R-G7, no protected calls in combat; tel: 0 taint; game: `/mma toggle` restores Blizzard's minimap exactly | `small-home` (Kharanos 1426, home, small); `blizzard-rim` (Kharanos 1426, Blizzard's) | P (engage/release) | built M1.6 9c9a9d3, M1.7 16f2f11 |
| F2 | Square metal chrome, hover controls | Metal border on four sides, title band; the controls show only while hovered | M1.7 | sim: test_chrome (L2 inset clamp, 0.15 s fade); shot | `small-home`, `small-hover` (Kharanos 1426, home, small) | M | built M1.7 16f2f11 |
| F3 | Zone title line (small/big rules, debug) | Small: where you are, coordinates only on hover. Big: coordinates, target, the browse hint. Debug line on request. | M1.7 (+debug M4.6) | sim: title text small vs big, hovered vs not (test_chrome); shot | `small-hover` (Kharanos 1426, home, small); `big-home` (Kharanos 1426, big home, big); `big-browse` (Kalimdor 1414, as opened, big); `small-seam` (Kharanos tile line 1426, 800, small) | M | built M1.7 16f2f11 (debug line: M4.6) |
| F4 | Map picker on the title | Click the zone name: Continents (≥300 tiles), Other maps, Instances by entrance continent, a lone group skipped | M3.4 | sim: test_interact (picker groups for EK); gif: pick-and-fly | `big-picker` (Eastern Kingdoms 1415, 16, big) | M | todo |
| F5 | Wheel and ± zoom, log chase | Wheel or ± buttons, ticks stack, a log-space chase toward the target | M1.8 | sim: test_zoom (chase converges, zooming ≤2 ms draw, test_wheel_burst); game: one flick, one tick, ticks in a row, on a trackpad and a wheel mouse; gif: zoomable-minimap | `small-near` (Kharanos 1426, 800, small); `big-continent` (Eastern Kingdoms 1415, 16, big) | P | built M1.8 9b0754a, M1.8b 2ef936d (a burst counts by time; in game on a trackpad and a wheel mouse at the final play-test) |
| F6 | Pan; click vs drag | Drag pans. A click moves under 5 px in under 0.35 s. A drag turns follow off. | M1.8 | sim: test_motion (thresholds) | `small-drag` (Kharanos 1426, home, small) | P | built M1.8 9b0754a |
| F7 | Follow toggle, idle return | Follow button and `/mma follow`. Left alone for 6 s after a pan (small only), it glides back to following. | M1.7, M1.8 (corpse → follow M3.3) | sim: test_motion (idle at 6 s, not while hovered) | `small-hover` (on), `small-drag` (off) (Kharanos 1426, home, small) | P | built M1.7 16f2f11, M1.8 9b0754a (corpse → follow: M3.3) |
| F8 | Move and resize (yards kept) | Drag the title or border, or Alt-drag the map; the grip resizes; small keeps the yards across | M1.7 | sim: yards kept on resize (test_chrome) | — | P | built M1.7 16f2f11 |
| F9 | `/mma reset` (refused while big) | Back onto the minimap's spot at its size, following; while big: `reset: shrink the map back first (M)` | M1.7 | sim: reset refused while big | — | M | built M1.7 16f2f11 |
| F10 | Big map: M, red button, Escape | M or the red button grows it; M, the button or Escape shrinks it; L still opens Blizzard's map | M1.6, M1.7 | sim: test_bigmap (L3, L4, Escape), M keeps WorldMapFrame hidden + hooked, L opens Blizzard's; gif: minimap-to-big-map | `big-home` (Kharanos 1426, big home, big) | M | built M1.6 9c9a9d3, M1.7 16f2f11 (M in combat: the M1 gate. In combat M leaves Blizzard's map open and ours as it was: game/Hooks.lua's guard, which the spike lacks, MinimapMode.lua:198-201. The final session's script (c) c4 answers it: `/mma check combat` hides Blizzard's map once in combat and says whether the client blocked it; blocked: the guard stays, a deviation for sign-off; not: the guard goes) |
| F11 | Small vs big differences | Strata, title parts, the browse hint, the inspector on big only, the gear's contents | M1.7, M3.4 | sim: test_gear (small vs big), test_bigmap; shot | `small-home` + `big-home` (Kharanos 1426); `big-browse` (Kalimdor 1414, as opened, big) | M | todo |
| F12 | Terrain tiles | The game's minimap terrain by FileDataID, at any zoom | M1.3 | sim: R-P1 (tiles ≥99% frames), map textures unsnapped; tel: 8/8 | `small-near` (Kharanos 1426, 800, small); `small-seam` (Kharanos tile line 1426, 800, small) | B |  built M1.3 abdddfe, M1.4 672d8b2 (R-P1: tiles 180/180 frames; no texture, mask or Line on the map snaps, checked in every replay by T.Anchors; tel 8/8: the final session) |
| F13 | Colour-matched tiles, coast fades, `/mma tint` | TileColor tints and coast fades; `/mma tint` toggles them, `(no data for this map)` where there are none | M1.4 | sim: tint relays; shot | `big-continent` (Eastern Kingdoms 1415, 16, big) | P |  built M1.4 672d8b2 (test_ground test_tint: `/mma tint` and the gear lay the tiles out plain and back, `(no data for this map)`; the coast fades: S31) |
| F14 | Player arrow (hidden off-map / withheld; under 'blizzard' M4.2) | Our arrow; none off the shown map or while the position is withheld | M1.4 | sim: arrow hidden off-map, instance-map scenario | `small-near` (Kharanos 1426, 800, small); `big-instance` (picker instance, as opened, big) | P |  built M1.4 672d8b2 (test_ground test_arrow, R-K5: none off your map, while withheld or without a facing; under 'blizzard': M4.2) |
| F15 | Zone and subzone borders | Traced from the terrain, the spike's look (D5) | M1.4 | sim: 2 Lines/segment, ≤3000 at zoom 4 EK, band goldens | `small-town` (Kharanos 1426, 250–300, small); `small-zone` (Kharanos 1426, 62–80, small); `big-zones` (Dun Morogh 1426, 80–100, big) | P (demo style) |  built M1.4 672d8b2 (test_ground test_borders: 2 Lines a segment, ≤4 dashes an end, ≤3000 at zoom 4 EK, band goldens; the shots: S32, S33, S35) |
| F16 | Zone and subzone labels | Ranked names, laid out offline (Data/Labels.lua) | M1.1, M1.4 | sim: test_atlas Labels golden, label counts at 100/200/500; tel: first open ≤50 ms | `small-town` (Kharanos 1426, 250–300, small); `small-zone` (Kharanos 1426, 62–80, small); `big-continent` (Eastern Kingdoms 1415, 16, big) | P (demo style) |  built M1.1 0fc62e8 (ranked offline), M1.4 672d8b2 (the spike's look: test_ground test_labels, counts at 100/200/500) |
| F17 | Hover zone, click to fly | With more than one zone of weight ≥30 in view: the hovered zone lights up, a click flies to it (fit 0.92), follow off | M3.4 | sim: test_interact (zone click flies 0.55 s, follow off); gif: pick-and-fly | `big-zones` (Dun Morogh 1426, 80–100, big) | M | todo |
| F18 | `/mma map`, `/mma zone` | Show a map by id or name (alone: lists them); fly to a zone by name; the spike's messages | M3.4 | sim: test_interact | — | P (`map`) | todo |
| F19 | Blip sensor | Blizzard's Minimap read as a sensor where Apply placed it, once it holds still | M1.5 | sim: test_blips priced (≤2 ms/frame, exact within 2 sweeps), R-G3, R-D3, R-D5a, R-D5b, R-E6; tel: game.part blips ≤2 ms (none in perf.slow), `sensor` trace empty | `small-home` (Kharanos 1426, home, small) | B (over budget) | built M1.5 f4d4976, M1.5b 92e5ddd (allocation: the default window ~5 KB/s priced, p95 0.1 KB a frame; in game: the final session) |
| F20 | Blip icons (incl. quest `!`/`?`) | Blizzard's tracking icon per kind, a gold dot otherwise; quest `!`/`?` where our layers don't cover them | M1.5, M4.3, M4.4 | sim: test_services, Icon() from BlipServices; tel: no `art` misses | `small-near` (Kharanos 1426, 800, small); `small-town` (Kharanos 1426, 250–300, small) | P | built M1.5 f4d4976, M1.2 a06a9c0, M1 review 0c00a0d (herb and ore by name: their tracking atlases at 14; a class trainer 136455; anything else StylePin's dot (d): test_blips); `!`/`?`: M4.3 |
| F21 | Town services and remembered blips | Tracked services from zoom 60 (QuestieDB); blips seen before shown with live=false | M4.3, M4.4 | sim: test_services (zoom 60 shows, 59 not; tracking off hides), R-S1 | `small-town` (Kharanos 1426, 250–300, small); `small-zone` (Kharanos 1426, 62–80, small) | P (live only) | partial: M1 review 0c00a0d (the remembered: Known("remembered"), Focus's map, from zoom 60 at full alpha, 5000 an instance: D6, ADR 0004 amended); M4.3: QuestieDB's services, both gated by Blizzard's tracking (one switch both trainers), "Not in sight" tooltip |
| F22 | Duplicate tracking suppression, crash-safe | TaxiNode, QuestPOI and POI tracking off while sensing outdoors with our layer on; restored at stop, release, logout and after a crash | M4.2 | sim: test_tracking (restored after a simulated crash + reload); game: `/reload` mid-session restores tracking | `big-tracking` (Kharanos 1426, big home, big) | M | todo |
| F23 | Gear: Tracking | Blizzard's tracking types, less the duplicates, as checkboxes | M4.5 | sim: test_gear | `big-tracking` (Kharanos 1426, big home, big) | M | todo |
| F24 | Indoors: art or Blizzard floor plan, `/mma indoor` | The world-map art of the map you're on (≤1600 yd, or a dungeon floor) over a dark backdrop; no art: Blizzard's whole Minimap in the window | M4.2, M4.4 | sim: R-G1 (Undercity, Orgrimmar 1454, no art → blizzard) | `small-indoor` (Ironforge 1455, home, small); `big-indoor` (Ironforge 1455, big home, big) | M | todo |
| F25 | Rotate Minimap ignored | North up always; other addons' minimap pins hidden while it's on | M1.5, M4.2 | sim: rotation re-asserted every apply, test_addonpins (hidden under Rotate Minimap); game: checked at M5 | — | P | todo (rotation re-asserted each apply: M1.5 f4d4976; pins: M4.2) |
| F26 | Quest pins | Quests in the log in Blizzard's art, with objective icon and count | M2.1–M2.4 | sim: test_quests (forms, 22/26, glow, count), no duplicate pin per frame | `big-quests` (quest hub 1426, 100–130, big); `small-quests` (quest hub 1426, home, small) | M | todo |
| F27 | Difficulty colours | The level disc's tint (style row S47) | M2.3 | sim: Model-alone fixture replay (colours) | `big-quests` (quest hub 1426, 100–130, big) | M | todo |
| F28 | Rich quest tooltip | QuestInfo.lua's tooltip: facts, mobs, items, turn-in | M2.4 | sim: tooltip line order (≤3 mobs + `(+N more)`, Turn in to), no-data scenario (reduced tooltip) | `big-quest-tip` (quest hub 1426, 100–130, big) | M | todo |
| F29 | Quest areas (blobs) | Objective areas drawn as the game draws them, sensed with Inside; hover lights one | M1.9, M2.4 | sim: test_quest_areas, R-L1, R-P5; game: `/mma check inside` agrees standing in an area | `big-quests`, `big-quest-follow` (quest hub 1426, 100–130, big) | M | todo (Inside: M1.9 9176bca; drawn: M2.4) |
| F30 | Estimated areas | A 110 yd dashed circle for kill, collect and interact objectives with no area, merged within 0.6 r | M2.3, M2.4 | sim: test_quest_areas (estimate only without a blob, merge) | `big-quests` (quest hub 1426, 100–130, big) | M | todo |
| F31 | Click to follow a quest | Click a pin (or its area, zoomed in) to follow it: the game's super-tracked quest; again to stop; pins beat areas | M2.2, M2.4 | sim: click → follow Command → super-track back in obs; game: super-tracks in Blizzard's tracker | `big-quest-follow` (quest hub 1426, 100–130, big) | M | todo |
| F32 | Target selection | Corpse (as a ghost), then the followed quest on the shown map, then the waypoint; a quest's area edge by rays; inside held 0.5 s | M3.1 | sim: test_target | `big-quest-follow` (quest hub 1426, 100–130, big); `big-waypoint` (Kharanos 1426, 300–400, big) | M | todo |
| F33 | Walking route line | A* over the walk grid in a Job, around cliffs, lava and water, drawn as hand-inked dashes | M3.1, M3.3 | sim: test_route, R-M1, R-E3, R-P2, ≤160 pieces, 0 redraws standing; tel: route jobs never in perf.slow; gif: path-mode | `big-waypoint` (Kharanos 1426, 300–400, big); `big-quest-follow` (quest hub 1426, 100–130, big) | M | todo |
| F34 | Off-map edge arrow | A gold arrow on the window's edge pointing at a target out of view | M3.3 | sim: arrow position when off view | `small-edge-arrow` (Kharanos 1426, home, small) | M | todo |
| F35 | Waypoints (Ctrl-click / Ctrl-right-click) | The game's user waypoint, super-tracked; menu entries set and clear it | M3.2, M3.4 | sim: test_interact (Ctrl-click), waypoint round trip | `big-waypoint` (Kharanos 1426, 300–400, big) | M | todo |
| F36 | `/way` link (Shift-click) | Chat opens with `/way <zone> %.1f %.1f`, not sent | M3.2, M3.4 | sim: way round trip | — | M | todo |
| F37 | Right-click menu | Waypoint here, Clear waypoint, Follow me; the big map leads with the inspector | M3.4 | sim: test_interact | `big-inspector` (Kharanos 1426, 300–400, big) | P (follow only) | todo |
| F38 | Zone info inspector | Zone, subzones, coordinates, level against yours, distance and compass, ≤2 quests; explored, ≤2 landmarks within 900 yd | M3.4 (explored + landmark lines M4.4) | sim: inspector at a known Elwynn spot, explored + landmark lines | `big-inspector` (Kharanos 1426, 300–400, big) | M | todo |
| F39 | Places: flight, dungeons, graveyards, POIs | Static and live places, deduped across maps | M4.1, M4.3, M4.4 | sim: test_places (dedupe across maps) | `big-places` (Dun Morogh 1426, 40–60, big); `small-zone` (Kharanos 1426, 62–80, small) | P (flight in labels) | todo |
| F40 | Quests to pick up | Offers per zone (C_QuestLine), skipping quests in progress, hidden per the client's CVar | M2.2–M2.4 | sim: offers round trip, Known('offers') skips in-progress | `big-quests` (quest hub 1426, 100–130, big) | M | todo |
| F41 | Party and raid dots | Class colours, dead grey, 20 Hz | M4.1, M4.3, M4.4 | sim: test_group (dead grey, 20 Hz) | `small-group` (opt) (party, home, small) | M | todo |
| F42 | Corpse | Found after release, tombstone pin, the ghost's target, forces follow | M3.2, M3.3 | sim: R-G4, test_target (ghost → corpse), corpse forces follow | `small-corpse` (opt) (corpse, home, small) | M | todo |
| F43 | Rares seen account-wide | Rares you target or pass are remembered for every character | M4.1, M4.3 | sim: R-D4, a rare survives reload | `small-rare` (opt) (near a seen rare, 62–80, small) | P (static) | todo (M4.3: the rares you've seen, SavedModel.rares, replace the static spawns (Atlas.Rares) as the pin source, as the spike's RarePins: Landmarks.lua:53-69; until then the layer shows every static spawn from zoom 60) |
| F44 | Live vignettes | Rares and treasures the game shows now; a seen-rare pin hides under a live one of the same name | M4.1, M4.3, M4.4 | sim: R-D4, R-E2 | `small-vignette` (opt) (near a vignette, home, small) | M | todo |
| F45 | Unexplored shade (opt-in) | Undiscovered parts of each zone darkened; off by default | M4.1, M4.4 | sim: shade cell count | `big-shade` (Dun Morogh 1426, 80–100, big) | M | todo |
| F46 | HBD world pins | Other addons' HereBeDragons world pins hosted on the map while open, handed back on close | M1.9 (thin), M4.2 | sim: HBD round trip, R-G6, test_addonpins (continent filter, 128 px, Questie complete skipped); game: Questie pins borrowed and returned | `big-addon-pins` (opt) (Kharanos 1426, 100–130, big) | M | todo (thin borrow: M1.9 9176bca, 82a65c6; re-placed by a 1 ms job at a new zoom: M1 review 51eb7b5). **Deviation for sign-off** at `big-addon-pins`: the pins are see-through while the zoom moves (wheel chase, flight, grow, shrink) and while Game re-places them where the view rests (about a frame in the client); the spike re-placed every hosted pin each zoom frame (AddonPins.lua:274-283), ~0.7 ms a frame with Questie's thousands |
| F47 | HBD minimap pins | Their minimap pins on our host; hidden under Rotate Minimap or off the map, and for an addon whose world pins we host | M4.2 | sim: test_addonpins | `small-addon-pins` (opt) (Kharanos 1426, home, small) | M | todo (a hidden host while engaged: 898daf8) |
| F48 | Gear: layers + `/mma layers` | Groups Map, Quests, Places, People, You, Other addons, with tips; children indented, disabled while their parent is off; `/mma layers` in chat | M1.7 (stub), M2–M3 add, M4.5 | sim: test_gear (tree and indentation match the spike; toggles reach SavedUI and View.layers) | `big-gear` (Kharanos 1426, big home, big); `chat-layers` (chat) | M | todo (stub: M1.7 16f2f11) |
| F49 | Gear: Settings | Map (Colour-matched tiles), Minimap (Minimap button, Reset position, Use Blizzard's minimap), Advanced (Diagnostics, Performance) | M1.7 (Map, Minimap), M4.5 (Advanced) | sim: test_gear | `big-settings` (Kharanos 1426, big home, big) | M | todo (Map, Minimap: M1.7 16f2f11; Advanced: M4.5) |
| F50 | Button tips | Tiny tips on mode, gear, zoom and follow | M1.7 | sim: test_chrome; shot | `big-hover` (Kharanos 1426, big home, big) | M | built M1.7 16f2f11 |
| F51 | Pin hover tooltips | GameTooltip for any pin, hidden on one owner-checked path | M2.1 (hide path M1.6) | sim: R-G7 | `big-places` (Dun Morogh 1426, 40–60, big); `big-quest-tip` (quest hub 1426, 100–130, big) | M | todo |
| F52 | Minimap button, compartment, `/mma icon` | Rim button (draggable, angle saved), addon compartment entry, `/mma icon` shows or hides it | M1.6, M1.7 | sim: buttonAngle survives reload | `blizzard-rim` (Kharanos 1426, Blizzard's) | M | built M1.6 9c9a9d3, M1.7 16f2f11 |
| F53 | `/mma toggle`, `/mma follow` | Our map or Blizzard's minimap; follow on or off | M1.7 | sim: toggle + reload, release restores every property | `blizzard-rim` (Kharanos 1426, Blizzard's) | P | built M1.7 16f2f11 |
| F54 | Diagnostics: blips, tiles, debug, perf, perf top, perf mem, landmarks | The spike's commands and their output; gear Advanced calls the same code | M4.6 | sim: each command prints without error | `small-seam` (Kharanos tile line 1426, 800, small) (debug title) | P (perf) | todo (M4.6; `/mma perf` is `/mma perf load` since the M1 review, so `perf`, `perf top` and `perf mem` can be the spike's: Core.lua, GearMenu.lua:41; an unknown command answers with the spike's one usage line, Core.lua:1752, the rebuild's diagnostics outside it) |
| F55 | Account-wide saved state (SavedUI fields) | Window, shown, zoom, follow, inst, center, button, tint, layers; rares | M1.7, M4.3 | sim: reload round trip, a rare survives reload | — | P | todo (SavedUI: M1.7 16f2f11; rares: M4.3) |
| F56 | No-data notice (one chat line) | Without the QuestieDB-derived data: one chat line, and the map still works | M5.2 | sim: no-QuestieDB-data scenario (0 errors, pins drawn, reduced tooltips, one notice) | — | M | todo |

## Style (§4)

Values are verbatim. Font face is GameFontNormal's unless stated, and shadows are black. A row
with no shot is behaviour or timing, which the sim or a GIF proves.

### Frame and chrome

| # | Element | Value | Spike ref | Package | Proof | Shot | Status |
|---|---|---|---|---|---|---|---|
| S1 | Window | `ButtonFrameTemplate` stripped: portrait, button bar, Inset, TitleText off; every template region hidden but viewport, band, grip, border, controls | Core.lua:76-90, UI.lua:1-80 | M1.7 | sim: test_chrome; shot | `small-home` (Kharanos 1426, home, small); `big-home` (Kharanos 1426, big home, big) | built M1.7 16f2f11 |
| S2 | Border | Bottom metal pieces on all 4 sides: `UI-Frame-Metal-CornerBottomLeft/Right` (top corners = vertical texcoord flip), `_UI-Frame-Metal-EdgeBottom` (flipped for top), `!UI-Frame-Metal-EdgeLeft/Right`; OVERLAY, native size, edges stretched; level frame+505 | UI.lua ApplyBorder | M1.7 | sim: test_chrome; tel: no `art` misses; shot | `small-home` (Kharanos 1426, home, small); `big-home` (Kharanos 1426, big home, big) | built M1.7 16f2f11 |
| S3 | Viewport inset | Border thickness clamped 2..6 px per side (`MAX_INSET=6`; L2 oversized atlases) | Core.lua:383-391 | M1.7 | sim: test_chrome (L2: mocked oversized edge atlas → clamped); shot | `small-home` (Kharanos 1426, home, small) | built M1.7 16f2f11 |
| S4 | Backdrop | (0,0,0,1) or sampled sea colour, default (0.03,0.06,0.065) | Core.lua | M1.7 (sea sample M1.4) | shot | `big-continent` (Eastern Kingdoms 1415, 16, big) |  built M1.7 16f2f11 (default; the sea's colour under the tiles: Window.SetInst, found done at M1.4) |
| S5 | Bounds | Clamped to screen, movable, `SetResizeBounds(120,120)` | Core.lua:76-90 | M1.7 | sim: test_chrome | — | built M1.7 16f2f11 |
| S6 | Grip | 14×14 at BOTTOMRIGHT (-4,4), level +520, alpha 0.8; `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up/-Highlight/-Down` | Core.lua:316-327 | M1.7 | shot | `small-hover` (Kharanos 1426, home, small) | built M1.7 16f2f11 |
| S7 | Move | Drag title, drag frame/border, or Alt+left-drag map | Core.lua:1342-1389 | M1.7 | sim: test_chrome | — | built M1.7 16f2f11 |
| S8 | Layer order | backdrop → tiles (sensor + path canvas on tile canvas) → shade → areas → lines → path → labels → pins (tile level +i) → overlay +8 (arrow, edge arrow); border +505, band +515, mapControls +518, grip +520 | Core.lua:142-153 | M1.3, M1.7 | sim: frame levels (test_chrome); shot | `big-quests` (quest hub 1426, 100–130, big) | todo |

### Title band

| # | Element | Value | Spike ref | Package | Proof | Shot | Status |
|---|---|---|---|---|---|---|---|
| S9 | Title | 14 pt, (1,0.82,0.25), hover (1,0.93,0.6), shadow (1,-1) alpha 1, left, no wrap | Core.lua:177-226 | M1.7 | shot | `small-home` (Kharanos 1426, home, small); `big-home` (Kharanos 1426, big home, big) | built M1.7 16f2f11 |
| S10 | Subtitle | 11 pt, (0.74,0.68,0.58), 6 px right of title, same baseline, +1 y | Core.lua:177-226 | M1.7 | shot | `small-hover` (Kharanos 1426, home, small); `big-home` (Kharanos 1426, big home, big) | built M1.7 16f2f11 |
| S11 | Position | 4 px above frame top-left (x+2); below the bottom when frame is within 24 px of screen top | Core.lua:291-312 | M1.7 | sim: test_chrome (flips near the top); shot | `small-home` (Kharanos 1426, home, small); `big-home` (Kharanos 1426, big home, big) | built M1.7 16f2f11 |
| S12 | Joins | parts `'  ·  '`; coords `'%.1f, %.1f'`; target `'\|cffffd27f<title>\|r N yd'` or `'<title> here'`; big hint `'\|cff8a7f6eright-click: Follow me\|r'`; debug `\|cff777777` | Core.lua:1244-1320 | M1.7 (target M3.3, debug M4.6) | sim: title strings; shot | `big-waypoint` (Kharanos 1426, 300–400, big); `big-browse` (Kalimdor 1414, as opened, big); `small-seam` (Kharanos tile line 1426, 800, small) | todo (parts, coords, hint: M1.7 16f2f11; target M3.3, debug M4.6) |
| S13 | Width cap | frame w − 4 − (2·20+4+6+8) | Core.lua | M1.7 | sim: test_chrome | `small-hover` (Kharanos 1426, home, small) | built M1.7 16f2f11 |
| S14 | Hit rect | padded 4 px wide, 3 px tall | Core.lua | M1.7 | sim: test_chrome | — | built M1.7 16f2f11 |

### Buttons and controls

| # | Element | Value | Spike ref | Package | Proof | Shot | Status |
|---|---|---|---|---|---|---|---|
| S15 | Mode (big map) | 20×20 `redbutton-expand-c60` (fallback `redbutton-expand`), pushed `-pressed(-c60)`, highlight `redbutton-highlight(-c60)` ADD; BOTTOMRIGHT→frame TOPRIGHT (-2,+3), flipped (-2,-3); tip `Big map (M)` / `Minimap (M)` | Core.lua:281-310 | M1.7 | tel: no `art` misses; shot | `small-hover` (Kharanos 1426, home, small); `big-hover` (Kharanos 1426, big home, big) | built M1.7 16f2f11 (draws `redbutton-expand`, the spike's fallback, as the spike does here), M1.11 40e4581 (a chain is a miss only when none of its names resolves) |
| S16 | Gear | 24×24 `Interface\WorldMap\Gear_64` tc (0,0.5,0,0.5), pushed (0,0.5,0.5,1), same as ADD highlight; 6 px left of mode; tip `Layers & settings` | Core.lua:281-310 | M1.7 | shot | `big-hover` (Kharanos 1426, big home, big) | built M1.7 16f2f11 |
| S17 | Zoom out / in | `ui-hud-minimap-zoom-out` 20×11 at BOTTOMRIGHT (-12, 18); `ui-hud-minimap-zoom-in` 20×20, 2 px above; `-down`/`-mouseover` variants | Core.lua:335-381 | M1.7 | tel: no `art` misses; shot | `small-hover` (Kharanos 1426, home, small) | built M1.7 16f2f11 |
| S18 | Follow | 24×24 at BOTTOMLEFT (12,12); ring CIRCLE mask (1,0.82,0.3,0.9) only when on; disc (0,0,0,0.65) 21×21; icon `ui-hud-minimap-arrow-player` 17×17; highlight (1,1,1,0.12); off = desaturated, alpha 0.6 | Core.lua:335-381 | M1.7 | shot | `small-hover` (on), `small-drag` (off) (Kharanos 1426, home, small) | built M1.7 16f2f11 |
| S19 | Hover reveal | controls 0↔1 linear over 0.15 s; grip to 0.8×; reach `IsMouseOver(+32,-32)`; kept shown while a menu is open | Core.lua:393-408 | M1.7 | sim: test_chrome (0.15 s fade); shot | `small-home` vs `small-hover` (Kharanos 1426, home, small) | built M1.7 16f2f11 |
| S20 | Tiny tip | TOOLTIP strata, plate (0,0,0,0.6), 11 pt (0.95,0.9,0.8), pad +10 w +6 h, 3 px above; delay 0.35 s, fade-in 0.12 s, life 2.5 s; hide on leave/down/menu | Core.lua:1457-1504 | M1.7 | sim: tip timings; shot | `big-hover` (Kharanos 1426, big home, big) | built M1.7 16f2f11 |
| S21 | Rim button | `CreateRoundButton`: bg CIRCLE (0.06,0.05,0.04,0.9) at size−3; icon masked at size−inset; ring `Interface\HUD\UIMinimap2xC60` tc (510,591,511,592)/1024 at size+2; highlight (1,0.9,0.6,0.18). Map button: 28 px, `INV_Misc_Map_01`, inset 8, MEDIUM, radius w/2+6, default 215°, draggable; tip `\|cffffd100MagicMap\|r` + white Click/Drag lines | UI.lua:82-126, MinimapButton.lua:7-30 | M1.6 | sim: buttonAngle survives reload; shot | `blizzard-rim` (Kharanos 1426, Blizzard's) | built M1.6 9c9a9d3 |

### Window states and motion

| # | Element | Value | Spike ref | Package | Proof | Shot | Status |
|---|---|---|---|---|---|---|---|
| S22 | Minimap form | square on cluster home rect, side = max(w,h), cluster strata; SPAN 200 yd across; zoom = side/(200/533.33); no plate, no round mask | MinimapMode.lua:21-29, 98-114 | M1.7 (home rect M1.6) | sim: test_chrome (home placement); shot | `small-home` (Kharanos 1426, home, small) | built M1.7 16f2f11 (home rect: M1.6 9c9a9d3) |
| S23 | Resize small | zoom × newSide/oldSide (yards kept) | MinimapMode.lua:88-96 | M1.7 | sim: yards kept on resize | — | built M1.7 16f2f11 |
| S24 | Grow (M) | 0.7 screen each way, centred, HIGH + Raise, 0.22 s EaseOutCubic `1-(1-t)^3`; home alpha → 0; zoom /1.5 but not past whole zone at fit 0.92, over 0.32 s | MinimapMode.lua:47-80 | M1.7 | sim: test_bigmap; gif: minimap-to-big-map; shot (end state) | `big-home` (Kharanos 1426, big home, big) | built M1.7 16f2f11 |
| S25 | Shrink | 0.18 s to saved small rect; home alpha back; fly to saved zoom, follow | MinimapMode.lua:139-189 | M1.7 | sim: test_bigmap (L3 mid-shrink, L4); gif: minimap-to-big-map | — | built M1.7 16f2f11 |
| S26 | Zoom | 16..800 px/tile (tile 533.33 yd), default 384; tick ×1.3; log-space chase 14/s, stop within 0.002 log; ticks stack; anchor cursor / you while following / centre for buttons | Core.lua:13-17, 1418-1438 | M1.8 | sim: test_zoom (chase converges); gif: zoomable-minimap | `small-near` (Kharanos 1426, 800, small); `big-continent` (Eastern Kingdoms 1415, 16, big) | built M1.8 9b0754a, M1.8b 2ef936d (the wheel rationed by time: a lone tick ×1.3, ticks stack; a burst from a bucket of 1 tick refilling 4 a second, ui/Motion.lua WHEEL_BURST, WHEEL_RATE; the buttons not rationed; the user's call, D4) |
| S27 | Flight | `AnimateTo` 0.55 s EaseOutCubic, log-space zoom; zoom-in "comes to you"; zone fit 0.92 | Core.lua:946-1025 | M1.8 | sim: flight end state; gif: pick-and-fly, big-map-zoom | — | built M1.8 9b0754a |
| S28 | Click vs drag | click <5 px and <0.35 s; drag turns follow off | Core.lua:1064-1090 | M1.8 | sim: thresholds | `small-drag` (Kharanos 1426, home, small) | built M1.8 9b0754a |
| S29 | Idle return | 6 s untouched, small only, not hovered/dragging/animating | MinimapMode.lua | M1.8 | sim: idle at 6 s, not while hovered | — | built M1.8 9b0754a |
| S30 | Crossfade | borders 0.12 s; label fade-in 0.2 s | Layers.lua | M1.3 (borders), M1.4 (labels) | sim: D1 (≤1 canvas/layer α>0 outside a timed fade) | — | built M1.3 abdddfe, M1 review 981b9b4 (borders as the spike's while the zoom moves: scaled with it and dimmed to max(0.25, min(1, 1.6 − 0.6·log2 of the scale)), then crossfaded from that alpha over 0.12 s, Layers.lua:158-170, 1824-1836; R-P7: never out of sight; D1 per frame outside a crossfade; the client's frame while zooming: the final session's byState.zoom.client), M1.4 672d8b2 (labels: a name new to the view fades in over 0.2 s) |

### Ground

| # | Element | Value | Spike ref | Package | Proof | Shot | Status |
|---|---|---|---|---|---|---|---|
| S31 | Tiles | by FileDataID, TRILINEAR, unsnapped; no colour data: inward fade 0.35 tile; with TileColor: inward 0.08 to edge mean, outward 0.6 to backdrop, gradient corners | Core.lua:441-700 | M1.4 (canvases M1.3) | sim: map textures unsnapped, tint relays; shot | `small-near` (Kharanos 1426, 800, small); `big-continent` (Eastern Kingdoms 1415, 16, big) |  todo (canvases: M1.3 abdddfe, shared origin, park, masks parked with their art; masks unsnapped, tint off draws the art plain: M1.4 672d8b2. The rebuild keeps its own sea look, Data/Sea and feather masks, not Core.lua:441-700's gradient coast fades: port it or not is the user's call at the shot pairs) |
| S32 | Zone border | unsnapped; thick clamp(z/140,1.1,1.8), (1,0.9,0.72) α0.6; shadow from zoom 60 at thick+1.2, black α0.25 (2 Lines/segment, D5) | Layers.lua:1531-1590, 1735-1760 | M1.4 | sim: 2 Lines/segment, ≤3000 at zoom 4 EK; shot | `small-zone` (Kharanos 1426, 62–80, small); `big-zones` (Dun Morogh 1426, 80–100, big) |  built M1.4 672d8b2 (2 Lines a segment; zone levels at 0.15, 0.05, 0.03, 0.015, 0.0075 tile, each within ~1.5 px where drawn) |
| S33 | Subzone border | from zoom 140, clamp(z/300,0.8,1.1), (1,0.95,0.85) α0.22, simplify 0.035 tile | Layers.lua:1786-1802 | M1.4 | sim: band goldens; shot | `small-town` (Kharanos 1426, 250–300, small) |  built M1.4 672d8b2 (smoothed as the zone borders, Gaussian then 0.003 tile, 0.0075 below zoom 300, not Douglas-Peucker 0.035 + Chaikin: rounder, about half the points; judge at the shot) |
| S34 | Hover zone border | (1,0.84,0.4) α0.95, clamp(z/100,1.6,2.4) | Layers.lua | M3.4 | sim: test_interact; shot | `big-zones` (Dun Morogh 1426, 80–100, big) | todo |
| S35 | Dead ends | last 36 px as 5 px dashes / 4 px gaps, width thick·(0.6+0.4f), α·f, dropped below f 0.08; merge points <2.5 px; cap ≤4 pieces/end (rebuild cost cap) | Layers.lua:218-227 | M1.4 | sim: ≤4 fade pieces/end, merge <2.5 px; shot | `small-zone` (Kharanos 1426, 62–80, small) |  built M1.4 672d8b2 (test_ground test_borders: ≤4 dashes an end, merge <2.5 px) |
| S36 | Zone labels | UPPERCASE 10 pt (1,0.9,0.7,0.75), hover (1,1,0.9,1); hidden past zoom 450 | Layers.lua:1417-1458 | M1.4 (data M1.1) | sim: label counts at 100/200/500; shot | `small-zone` (Kharanos 1426, 62–80, small); `big-zones` (Dun Morogh 1426, 80–100, big) (hover) |  built M1.4 672d8b2 (hover colour: M3.4, each placed label carries its areaID) |
| S37 | Subzone labels | 9 pt (0.95,0.92,0.85,0.62); zoom 120 (weight ≥40), 220 (≥15), else 400 | Layers.lua:1636-1694 | M1.4 | sim: label counts; shot | `small-town` (Kharanos 1426, 250–300, small) |  built M1.4 672d8b2 |
| S38 | Label rules | no outline, shadow (1,-1) α0.55; collision ±4/±2 px; try 0, −(h+3), +(h+3), else skip; fade-in 0.2 s; re-place after log(1.25) drift | Layers.lua:239-244, 1804-1811 | M1.4 (ranks M1.1) | sim: test_atlas Labels golden, label counts; shot | `small-town` (Kharanos 1426, 250–300, small) |  built M1.4 672d8b2 (re-placed when the zoom leaves Engine's [0.7, 1.4] band and at settle, not after log(1.25) drift) |
| S39 | Shade | (0,0,0,0.55) cells 0.2 tile, +0.5 px, opt-in | Layers.lua:1772-1784 | M4.4 | sim: shade cell count; shot | `big-shade` (Dun Morogh 1426, 80–100, big) | todo |
| S40 | Indoor art backdrop | (0.06,0.05,0.04,1) | IndoorArt.lua | M4.4 | sim: R-G1; shot | `small-indoor` (Ironforge 1455, home, small) | todo |
| S41 | Player arrow | `Textures/PlayerArrow.tga` (gen_arrow.py), 22·64/45 ≈31.3 px, unsnapped, overlay +8 | Core.lua:155-175 | M1.4 | sim: hidden off-map, unsnapped; shot | `small-near` (Kharanos 1426, 800, small) |  built M1.4 672d8b2 (the overlay at view +10, above the world socket's +8; a new texture: restart the client after installing, L5) |

### Pins

| # | Element | Value | Spike ref | Package | Proof | Shot | Status |
|---|---|---|---|---|---|---|---|
| S42 | StylePin | default 14; forms (a) texture, (b) atlas, (c) atlas over tinted under, icon ×0.62, inner masked ×0.56 shaded (0.55,0.55,0.55) tc 0.08..0.92, (d) dot ×0.6 on black ring (0,0,0,0.9) ×0.6+3 | Layers.lua:303-400 | M2.1 | sim: test_quests (forms); shot | `big-quests` (quest hub 1426, 100–130, big); `small-zone` (Kharanos 1426, 62–80, small) | todo |
| S43 | Followed glow | CIRCLE size+14 (1,0.82,0.3,0.45) BACKGROUND | Layers.lua | M2.1 | sim: test_quests (glow); shot | `big-quest-follow` (quest hub 1426, 100–130, big) | todo |
| S44 | Count | `GameFontHighlightSmallOutline`, TOP→BOTTOM +2 | Layers.lua | M2.1 | sim: test_quests (count); shot | `big-quests` (quest hub 1426, 100–130, big) | todo |
| S45 | Tooltip | GameTooltip ANCHOR_RIGHT; title then grey 0.85 lines in `GameTooltipTextSmall`, restored on hide | Layers.lua:112-114 | M2.1 (hide path M1.6) | sim: R-G7; shot | `big-places` (Dun Morogh 1426, 40–60, big) | todo |
| S46 | Quest | `Quest-In-Progress-Icon-yellow` over `UI-QuestPoi-QuestNumber` (difficulty tint), 22 / 26 followed; inner icon item or 135274/134063/133633; complete `UI-QuestIcon-TurnIn-Normal`; offer `QuestNormal` 18 | Layers.lua:603-613, QuestInfo.lua | M2.4 (kinds M2.3) | sim: test_quests (22/26); tel: no `art` misses; shot | `big-quests`, `big-quest-follow` (quest hub 1426, 100–130, big) | todo |
| S47 | Difficulty | red (1,0.1,0.1) ≥+5; orange (1,0.5,0.25) ≥+3; yellow (1,0.82,0) to −2; green (0.25,0.75,0.25); grey (0.5,0.5,0.5) trivial | QuestInfo.lua:14-28 | M2.3 | sim: Model-alone fixture replay; shot | `big-quests` (quest hub 1426, 100–130, big) | todo |
| S48 | Places | flight `atlasName` 18, fallback (1,0.82,0)/(0.9,0.2,0.2)/(0.3,0.5,1); graveyard `poi-graveyard-neutral` 16; dungeon 20 fallback (0.7,0.4,1); area POI 18; vignette 20 | Layers.lua:459-659 | M4.4 | sim: each kind with defaults; tel: no `art` misses; shot | `big-places` (Dun Morogh 1426, 40–60, big); `small-vignette` (opt) | todo |
| S49 | You | corpse `deathrecap-icon-tombstone` on disc 22, scale 0.6, aspect 15/20; waypoint `Waypoint-MapPin-Tracked` 22 | Landmarks.lua | M3.3 | sim: test_target; tel: no `art` misses; shot | `big-waypoint` (Kharanos 1426, 300–400, big); `small-corpse` (opt) | todo |
| S50 | Rares | 137008 at 15, from zoom 60, `Seen here <Mon DD>` | Landmarks.lua:15-134 | M2.1 (pin), M4.3 | sim: R-D4; shot | `small-rare` (opt) (near a seen rare, 62–80, small) | todo (from zoom 60: M1.11 40e4581; the 137008 icon at 15: M2.1; only the rares you've seen, with `Rare` + `Seen here <Mon DD>`: M4.3) |
| S51 | Blips | ore `Professions_Tracking_Ore`, herb `Professions_Tracking_Herb` 14; mailbox 136459; services 136458/136453/136452/136466/136454/136463/136455/136465 at 14; quest `!` 132049 `?` 132048; unknown gold dot (1,0.82,0) 10; remote from zoom 60 | Blips.lua:373-641 | M1.5 (icons), M4.3 (services, remembered, `!`/`?`) | sim: test_services (zoom 60 shows, 59 not); tel: no `art` misses; shot | `small-near` (Kharanos 1426, 800, small); `small-town` (Kharanos 1426, 250–300, small) | partial: M1 review 0c00a0d (ore and herb atlases at 14, the services' textures at 14 with 136455 for class trainers, the unknown gold dot (1,0.82,0) at 10, remembered from zoom 60); `!`/`?` and QuestieDB's services: M4.3 |
| S52 | Group | `Interface\Minimap\PartyRaidBlipsV2` tc (0,0.5,0,1) 12, class colour, dead (0.5,0.5,0.5), 20 Hz | Layers.lua:673-760 | M4.4 (20 Hz part M4.1) | sim: test_group; shot | `small-group` (opt) (party, home, small) | todo |
| S53 | Quest blobs | fill/border/scalar: followed blue 32/120/0.8; kill rust 0/85/0.6; gather green 0/55/0.6; other blue 0/85/0.6; hover 40/150/0.8; drawn twice (now + next frame), hidden while zooming | Layers.lua:785-985 | M2.4 | sim: R-P5, R-L1 (UI); shot | `big-quests`, `big-quest-follow` (quest hub 1426, 100–130, big) | todo |
| S54 | Estimates | disc (1,0.85,0.4,0.05) r 110 yd; 18 dashes at 1.5 px (1,0.85,0.4,0.35); merge within 0.6 r | Layers.lua | M2.4 (merge M2.3) | sim: test_quest_areas; shot | `big-quests` (quest hub 1426, 100–130, big) | todo |

### Path

| # | Element | Value | Spike ref | Package | Proof | Shot | Status |
|---|---|---|---|---|---|---|---|
| S55 | Stroke / wash | 1.6 px (1,0.93,0.76,0.7) over 3.4 px (0.12,0.08,0.03,0.3) | Path.lua:1-40 | M3.3 | shot; gif: path-mode | `big-waypoint` (Kharanos 1426, 300–400, big) | todo |
| S56 | Dashes | 6/4 px, ≤160 pieces; end fades 40 px; clearance 14 / 15 px | Path.lua | M3.3 | sim: piece cap; shot | `big-waypoint` (Kharanos 1426, 300–400, big) | todo |
| S57 | Ink | wobble 0.8·(0.6 sin(u·0.09+1.3)+0.4 sin(u·0.031+4.1)); α unevenness 25% sin(…·0.045+2); Bezier lead-in 48 px / 8 steps | Path.lua:220-275 | M3.3 | shot | `big-waypoint` (Kharanos 1426, 300–400, big); `big-quest-follow` (quest hub 1426, 100–130, big) | todo |
| S58 | Redraw | half-pixel move, 3° turn, zoom change, new route | Path.lua | M3.3 | sim: 0 redraws standing; tel: allocation while walking ≤50 KB/s | — | todo |
| S59 | Edge arrow | `Interface\Minimap\ROTATING-MINIMAPGUIDEARROW` 32×32, 16 px inside edge | Path.lua | M3.3 | sim: arrow position; shot | `small-edge-arrow` (Kharanos 1426, home, small) | todo |

### Menus and text

| # | Element | Value | Spike ref | Package | Proof | Shot | Status |
|---|---|---|---|---|---|---|---|
| S60 | Menus | client `MenuUtil.CreateContextMenu` only, no skin | Menu.lua | M3.4, M4.5 | sim: test_gear; shot | `big-picker` (Eastern Kingdoms 1415, 16, big); `big-gear` (Kharanos 1426, big home, big) | todo |
| S61 | Gear tips | white title, gold (1,0.82,0) body; children indented 5 spaces, disabled while parent off | GearMenu.lua | M4.5 (stub M1.7) | sim: test_gear (indentation); shot | `big-gear`, `big-settings` (Kharanos 1426, big home, big) | todo |
| S62 | Zone info | GOLD `\|cffffd100`, WHITE, GREY `\|cffa8a8a8`, DIM `\|cff808080`; SEP dim `'  ·  '`; level green `\|cff40c040` / red `\|cffff6040` / grey | ZoneInfo.lua:1-187 | M3.4 (+lines M4.4) | sim: inspector lines; shot | `big-inspector` (Kharanos 1426, 300–400, big) | todo |
| S63 | Quest tooltip | facts DIM `\|cff9d9d9d`, tag orange `\|cffff8040`, `\|cff33ff33Ready to turn in`; ≤3 mobs + `(+N more)`; 14 px portraits; `Turn in to` at 0.85; `Click to follow` | QuestInfo.lua:175-369 | M2.4 | sim: tooltip line order; shot | `big-quest-tip` (quest hub 1426, 100–130, big) | todo |
| S64 | Chat | prefix `\|cffffd100MagicMap\|r: ` (`MagicMapAtlas` until M6); layers on `\|cff33ff33`, off `\|cff888888`, titles gold | Core.lua:44-46, Layers.lua:2196-2207 | M1.7, M4.5 | shot | `chat-layers` (chat) | todo |

## Out, by decision

The spike did these, or its notes promised them, and v1 won't. D2 (docs/v1-non-goals.md) was
confirmed on 2026-10-18; D3, D4 and D6 are decided.

| # | Out | Note | Decision | Status |
|---|---|---|---|---|
| N1 | Spike data migration | v1 starts fresh with a new SavedVariables name (D9). Seen rares, blips and `MagicMapLandmarks` from the spike are lost; the release notes say so. | D2, D9 | out, by decision |
| N2 | Locales other than enUS | The herb list, `Vein`/`Deposit` and tooltip-name matching are enUS | D2 | out, by decision |
| N3 | Routes beyond walking | No flight network drawn, no boats, portals or mounts | D2 | out, by decision |
| N4 | Addon pin API | Other addons' pins come only through HBD | D2 | out, by decision |
| N5 | Gamepad | Input is mouse-driven, and the sensor borrows the soft cursor | D2 | out, by decision |
| N6 | Map rotating with the camera | North up; Rotate Minimap is ignored (F25) | D2 | out, by decision |
| N7 | Positions inside instances | Instance maps shown whole, with no arrow, path, blips or borders (F14) | D2 | out, by decision |
| N8 | Per-character profiles | Everything is account-wide (ADR 0004) | D2 | out, by decision |
| N9 | Network telemetry | Telemetry is SavedVariables read locally | D2 | out, by decision |
| N10 | Sharing rares between players | Rares are shared across your own account's characters only (F43) | D2 | out, by decision |
| N11 | Path auto-fit | Only in RELEASE_NOTES-v1.0.0, not in the spike's code | D4 | out, by decision |
| N12 | Blips past the edge | Only in RELEASE_NOTES-v1.0.0, not in the spike's code | D4 | out, by decision |
| N13 | Item tooltips | Items are cut down to those quests reach (offline data diet, M1.2) | D3 | out, by decision |
| N14 | Dungeon NPCs | NPCs without an open-world spawn are dropped unless a quest, rare or service needs them (M1.2) | D3 | out, by decision |
| N15 | Seen-blips cap 300 per instance | v1 keeps 5000 seen blips per instance, so most players never reach it (ADR 0004 amended 2026-10-18) | D6 | out, by decision |

## Sign-off

One line per gate. The lead fills in the first four columns. The user signs at M5.3, once every row
is `signed` or `out, by decision`.

| Gate | Date | Rows built | Shot pairs | Signed |
|---|---|---|---|---|
| M0 | 2026-10-18 | none of its own (M0 builds no feature); 39 rows `built` by M1 wave 1a since | reference shots: the final session (D10) | |
| M1 | | | | |
| M2 | | | | |
| M3 | | | | |
| M4 | | | | |
| M5 | | | | |

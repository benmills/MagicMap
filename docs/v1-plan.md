# MagicMap 1.0: the plan for the big run

Status: PLAN, for an agent swarm. Inputs: synthesized plan + critic gaps (all applied, see §10) + readers (spike style, spike features, rebuild state, play-test perf).

## 1. Goal and definition of done

Ship the rebuild (now `MagicMapAtlas`, `/mma`) as **MagicMap 1.0**. It must look and behave like the spike's shipped 1.0 code (`~/code/MagicMap`, read-only) minus the non-goals, on the rebuild's locked contracts. Spec source is the spike's **code**, not `RELEASE_NOTES-v1.0.0` (path auto-fit and "blips past the edge" stay out unless the user says otherwise, §9 D4).

1.0 is done when all of these hold:

| # | Gate | Measured by |
|---|---|---|
| 1 | Every spike feature in §5 is shipped or marked "out, by decision"; the user signs off `docs/parity.md` with shots | parity.md, `/mma shot` pairs |
| 2 | The look matches §4 values verbatim | shot pairs vs `docs/evidence/shots/` reference |
| 3 | 8/8 budgets PASS in a real 10+ min session, twice, per script (a)–(e); `perf.slow`, `perf.gaps`, `sensor` and `art` traces empty | `tools/telemetry.py --budgets` |
| 4 | `/mma check log` on throughout: 0 K4 drift lines; 0 taint events (ADDON_ACTION_BLOCKED/FORBIDDEN) | telemetry |
| 5 | 0 errors | errors/hour budget |
| 6 | CI green: `tools/check.sh`, `pytest tools/tests`, empty luacheck BASELINE, no-QuestieDB-data scenario green | CI |
| 7 | Renamed (MagicMap, `/mm`), merged into `~/code/MagicMap`, packaged from a tag; the user does any push/upload | M6 exit |

## 2. Play-test findings and how the plan answers them

Session `345b724`, build 1.60.1.70374, ~90 s, Dun Morogh/Kharanos, 0 errors. Load 155 ms, p95 0.35 ms, p99 4.5 ms PASS.

| Finding | Cause (from the mark ring + lupa heap) | Fix: package | Proof |
|---|---|---|---|
| **FAIL frame max 27.2 ms** (≤8) | Swap end (`front:Hide; Place; back:Show`) can't yield, ~20 µs/region; borders ~1000 Lines at 3/segment; hidden pooled Lines still pay; SetScale on borders ~2 ms/wheel frame; every wheel tick rebuilds all 5 layers. game.observe 10.5 ms: sensor capped by probe count (~100 probes × ~0.1 ms) | Park pools, settle flag, no SetScale on borders, bench-chosen swap: **M1.3**. 2 Lines/segment + simplification bands: **M1.4**. Time-budgeted, resumable sensor: **M1.5** | R-P1, R-P7, `swap` trace ≤4 ms, game.observe ≤2 ms |
| **FAIL first open 67.5 ms** (≤50) | `Atlas.Labels` VisualCentre at runtime, one 56.2 ms call | Labels offline (`tools/gen_labels.py` → `Data/Labels.lua`): **M1.1** | test_atlas golden; grace.map ≤50 (target ≤20) |
| **FAIL memory 70.8 MB** (≤64) | No GC before reading: ~24 MB is garbage (274 KB/s × 90 s). Data: Items 10.5 + Npcs 9.3 + Quests 5.5 + Objects 3.8 MB; only 2,683/21,262 Items referenced | Full collect before reading: **M0.4**. Offline data diet: **M1.2** (D3) | ourKB after GC ≤64 (expect ~40); Items ≤2 MB |
| **FAIL allocation 274 KB/s** (≤50) | Not attributed. Suspect: sensor (fresh tooltip tables + gsub per probe), then a coroutine + closure per Rebuild × 5 layers/tick, Borders `p` per line, model/Blips Kind() | Attribute first: **M0.3** (HARD edge). Then parse cache + REST sweep: **M1.5**; settle-only rebuilds: **M1.3** | R-P3 ≤0.5 KB/frame; `perf.alloc` top 5 |
| **Mark "slight tear when moving"** (zoom 1024, follow, 320×203) | Undiagnosed. Candidates: (1) tile seam in view (col-33 boundary at x≈232), (2) snapped mask textures/FontStrings against unsnapped ground, (3) ~33,000 px canvas offsets; blips region ~0.08 rows off the ground's | Motion ring in marks: **M0.4**. Region-local origins + shared origin: **M1.3**. Unsnap masks; seam overlap only if a shot shows one: **M1.4** | Re-mark crossing a tile boundary at 1024 with ring + shot; sim offsets ≤4096 px, all map textures unsnapped |

The 4 FAILs and the tear are single-session inferences. M0 makes them measured before M1's engine and sensor fixes commit.

## 3. Rules for every package

- Contracts: OPEN additions only, by the single `types/` owner (M0.1). The only LOCKED change is the SavedVariables rename (ADR 0007, M6.1), plus ADR 0004 amendment if D6 = 300.
- Tests: simple sim scenarios or `R-*` replays only. No unit-test sprawl.
- No defensive code. E3 (`x/0` raises in the client) is handled by the `/` lint rule (M0.7) and fixes at the source. Absent QuestieDB data is handled once in Atlas (empty indexes), not per call site.
- Comments: terse, spike-style.
- Values in §4 are constants copied verbatim with spike `file:line` in a comment. Not starting points.
- Commands stay `/mma` until M6.
- The spike addon is **disabled** in every play-test (both hook ToggleWorldMap and take over the Minimap). Exception: the one reference-shot session (M0.8), which has the spike only.
- Risky client behaviour (QuestPOI Inside L1, HBD borrow, M/Escape hooks, taint) is proven thin and in game one milestone before features lean on it.
- Model builds against fixture streams through stubs with the real interface, so the fixture → Game swap needs no code change.
- Every package runs in its own git worktree branch; the lead merges. Packages marked **exclusive** below hold their files alone until merged.
- Hand-off: each package lists the spike-bugs rows it closed and the parity rows it ticked. Only the lead edits `docs/evidence/spike-bugs.md` and `docs/parity.md`, once per gate.
- Hot files are split in M0.2 so packages add files instead of editing shared ones: per-folder `files.txt` manifests (TOC generated), `Game.Part`/`Game.Handle`/`Game.Apply`/`Engine.Layer` registries, one replay per file under `tools/tests/replays/R-XX.lua`, per-Data-file FORMATS versions.

## 4. Style guide (match exactly)

All paths are in `~/code/MagicMap`. Font face is GameFontNormal's unless stated. Shadow colour is black.

### Frame and chrome
| Element | Value | Spike ref |
|---|---|---|
| Window | `ButtonFrameTemplate` stripped: portrait, button bar, Inset, TitleText off; every template region hidden but viewport, band, grip, border, controls | Core.lua:76-90, UI.lua:1-80 |
| Border | Bottom metal pieces on all 4 sides: `UI-Frame-Metal-CornerBottomLeft/Right` (top corners = vertical texcoord flip), `_UI-Frame-Metal-EdgeBottom` (flipped for top), `!UI-Frame-Metal-EdgeLeft/Right`; OVERLAY, native size, edges stretched; level frame+505 | UI.lua ApplyBorder |
| Viewport inset | Border thickness clamped 2..6 px per side (`MAX_INSET=6`; L2 oversized atlases) | Core.lua:383-391 |
| Backdrop | (0,0,0,1) or sampled sea colour, default (0.03,0.06,0.065) | Core.lua |
| Bounds | Clamped to screen, movable, `SetResizeBounds(120,120)` | Core.lua:76-90 |
| Grip | 14×14 at BOTTOMRIGHT (-4,4), level +520, alpha 0.8; `Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up/-Highlight/-Down` | Core.lua:316-327 |
| Move | Drag title, drag frame/border, or Alt+left-drag map | Core.lua:1342-1389 |
| Layer order | backdrop → tiles (sensor + path canvas on tile canvas) → shade → areas → lines → path → labels → pins (tile level +i) → overlay +8 (arrow, edge arrow); border +505, band +515, mapControls +518, grip +520 | Core.lua:142-153 |

### Title band
| Element | Value | Spike ref |
|---|---|---|
| Title | 14 pt, (1,0.82,0.25), hover (1,0.93,0.6), shadow (1,-1) alpha 1, left, no wrap | Core.lua:177-226 |
| Subtitle | 11 pt, (0.74,0.68,0.58), 6 px right of title, same baseline, +1 y | Core.lua:177-226 |
| Position | 4 px above frame top-left (x+2); below the bottom when frame is within 24 px of screen top | Core.lua:291-312 |
| Joins | parts `'  ·  '`; coords `'%.1f, %.1f'`; target `'|cffffd27f<title>|r N yd'` or `'<title> here'`; big hint `'|cff8a7f6eright-click: Follow me|r'`; debug `|cff777777` | Core.lua:1244-1320 |
| Width cap | frame w − 4 − (2·20+4+6+8) | Core.lua |
| Hit rect | padded 4 px wide, 3 px tall | Core.lua |

### Buttons and controls
| Element | Value | Spike ref |
|---|---|---|
| Mode (big map) | 20×20 `redbutton-expand-c60` (fallback `redbutton-expand`), pushed `-pressed(-c60)`, highlight `redbutton-highlight(-c60)` ADD; BOTTOMRIGHT→frame TOPRIGHT (-2,+3), flipped (-2,-3); tip `Big map (M)` / `Minimap (M)` | Core.lua:281-310 |
| Gear | 24×24 `Interface\WorldMap\Gear_64` tc (0,0.5,0,0.5), pushed (0,0.5,0.5,1), same as ADD highlight; 6 px left of mode; tip `Layers & settings` | Core.lua:281-310 |
| Zoom out / in | `ui-hud-minimap-zoom-out` 20×11 at BOTTOMRIGHT (-12, 18); `ui-hud-minimap-zoom-in` 20×20, 2 px above; `-down`/`-mouseover` variants | Core.lua:335-381 |
| Follow | 24×24 at BOTTOMLEFT (12,12); ring CIRCLE mask (1,0.82,0.3,0.9) only when on; disc (0,0,0,0.65) 21×21; icon `ui-hud-minimap-arrow-player` 17×17; highlight (1,1,1,0.12); off = desaturated, alpha 0.6 | Core.lua:335-381 |
| Hover reveal | controls 0↔1 linear over 0.15 s; grip to 0.8×; reach `IsMouseOver(+32,-32)`; kept shown while a menu is open | Core.lua:393-408 |
| Tiny tip | TOOLTIP strata, plate (0,0,0,0.6), 11 pt (0.95,0.9,0.8), pad +10 w +6 h, 3 px above; delay 0.35 s, fade-in 0.12 s, life 2.5 s; hide on leave/down/menu | Core.lua:1457-1504 |
| Rim button | `CreateRoundButton`: bg CIRCLE (0.06,0.05,0.04,0.9) at size−3; icon masked at size−inset; ring `Interface\HUD\UIMinimap2xC60` tc (510,591,511,592)/1024 at size+2; highlight (1,0.9,0.6,0.18). Map button: 28 px, `INV_Misc_Map_01`, inset 8, MEDIUM, radius w/2+6, default 215°, draggable; tip `|cffffd100MagicMap|r` + white Click/Drag lines | UI.lua:82-126, MinimapButton.lua:7-30 |

### Window states and motion
| Element | Value | Spike ref |
|---|---|---|
| Minimap form | square on cluster home rect, side = max(w,h), cluster strata; SPAN 200 yd across; zoom = side/(200/533.33); no plate, no round mask | MinimapMode.lua:21-29, 98-114 |
| Resize small | zoom × newSide/oldSide (yards kept) | MinimapMode.lua:88-96 |
| Grow (M) | 0.7 screen each way, centred, HIGH + Raise, 0.22 s EaseOutCubic `1-(1-t)^3`; home alpha → 0; zoom /1.5 but not past whole zone at fit 0.92, over 0.32 s | MinimapMode.lua:47-80 |
| Shrink | 0.18 s to saved small rect; home alpha back; fly to saved zoom, follow | MinimapMode.lua:139-189 |
| Zoom | 16..800 px/tile (tile 533.33 yd), default 384; tick ×1.3; log-space chase 14/s, stop within 0.002 log; ticks stack; anchor cursor / you while following / centre for buttons | Core.lua:13-17, 1418-1438 |
| Flight | `AnimateTo` 0.55 s EaseOutCubic, log-space zoom; zoom-in "comes to you"; zone fit 0.92 | Core.lua:946-1025 |
| Click vs drag | click <5 px and <0.35 s; drag turns follow off | Core.lua:1064-1090 |
| Idle return | 6 s untouched, small only, not hovered/dragging/animating | MinimapMode.lua |
| Crossfade | borders 0.12 s; label fade-in 0.2 s | Layers.lua |

### Ground
| Element | Value | Spike ref |
|---|---|---|
| Tiles | by FileDataID, TRILINEAR, unsnapped; no colour data: inward fade 0.35 tile; with TileColor: inward 0.08 to edge mean, outward 0.6 to backdrop, gradient corners | Core.lua:441-700 |
| Zone border | unsnapped; thick clamp(z/140,1.1,1.8), (1,0.9,0.72) α0.6; shadow from zoom 60 at thick+1.2, black α0.25 (2 Lines/segment, D5) | Layers.lua:1531-1590, 1735-1760 |
| Subzone border | from zoom 140, clamp(z/300,0.8,1.1), (1,0.95,0.85) α0.22, simplify 0.035 tile | Layers.lua:1786-1802 |
| Hover zone border | (1,0.84,0.4) α0.95, clamp(z/100,1.6,2.4) | Layers.lua |
| Dead ends | last 36 px as 5 px dashes / 4 px gaps, width thick·(0.6+0.4f), α·f, dropped below f 0.08; merge points <2.5 px; cap ≤4 pieces/end (rebuild cost cap) | Layers.lua:218-227 |
| Zone labels | UPPERCASE 10 pt (1,0.9,0.7,0.75), hover (1,1,0.9,1); hidden past zoom 450 | Layers.lua:1417-1458 |
| Subzone labels | 9 pt (0.95,0.92,0.85,0.62); zoom 120 (weight ≥40), 220 (≥15), else 400 | Layers.lua:1636-1694 |
| Label rules | no outline, shadow (1,-1) α0.55; collision ±4/±2 px; try 0, −(h+3), +(h+3), else skip; fade-in 0.2 s; re-place after log(1.25) drift | Layers.lua:239-244, 1804-1811 |
| Shade | (0,0,0,0.55) cells 0.2 tile, +0.5 px, opt-in | Layers.lua:1772-1784 |
| Indoor art backdrop | (0.06,0.05,0.04,1) | IndoorArt.lua |
| Player arrow | `Textures/PlayerArrow.tga` (gen_arrow.py), 22·64/45 ≈31.3 px, unsnapped, overlay +8 | Core.lua:155-175 |

### Pins
| Element | Value | Spike ref |
|---|---|---|
| StylePin | default 14; forms (a) texture, (b) atlas, (c) atlas over tinted under, icon ×0.62, inner masked ×0.56 shaded (0.55,0.55,0.55) tc 0.08..0.92, (d) dot ×0.6 on black ring (0,0,0,0.9) ×0.6+3 | Layers.lua:303-400 |
| Followed glow | CIRCLE size+14 (1,0.82,0.3,0.45) BACKGROUND | Layers.lua |
| Count | `GameFontHighlightSmallOutline`, TOP→BOTTOM +2 | Layers.lua |
| Tooltip | GameTooltip ANCHOR_RIGHT; title then grey 0.85 lines in `GameTooltipTextSmall`, restored on hide | Layers.lua:112-114 |
| Quest | `Quest-In-Progress-Icon-yellow` over `UI-QuestPoi-QuestNumber` (difficulty tint), 22 / 26 followed; inner icon item or 135274/134063/133633; complete `UI-QuestIcon-TurnIn-Normal`; offer `QuestNormal` 18 | Layers.lua:603-613, QuestInfo.lua |
| Difficulty | red (1,0.1,0.1) ≥+5; orange (1,0.5,0.25) ≥+3; yellow (1,0.82,0) to −2; green (0.25,0.75,0.25); grey (0.5,0.5,0.5) trivial | QuestInfo.lua:14-28 |
| Places | flight `atlasName` 18, fallback (1,0.82,0)/(0.9,0.2,0.2)/(0.3,0.5,1); graveyard `poi-graveyard-neutral` 16; dungeon 20 fallback (0.7,0.4,1); area POI 18; vignette 20 | Layers.lua:459-659 |
| You | corpse `deathrecap-icon-tombstone` on disc 22, scale 0.6, aspect 15/20; waypoint `Waypoint-MapPin-Tracked` 22 | Landmarks.lua |
| Rares | 137008 at 15, from zoom 60, `Seen here <Mon DD>` | Landmarks.lua:15-134 |
| Blips | ore `Professions_Tracking_Ore`, herb `Professions_Tracking_Herb` 14; mailbox 136459; services 136458/136453/136452/136466/136454/136463/136455/136465 at 14; quest `!` 132049 `?` 132048; unknown gold dot (1,0.82,0) 10; remote from zoom 60 | Blips.lua:373-641 |
| Group | `Interface\Minimap\PartyRaidBlipsV2` tc (0,0.5,0,1) 12, class colour, dead (0.5,0.5,0.5), 20 Hz | Layers.lua:673-760 |
| Quest blobs | fill/border/scalar: followed blue 32/120/0.8; kill rust 0/85/0.6; gather green 0/55/0.6; other blue 0/85/0.6; hover 40/150/0.8; drawn twice (now + next frame), hidden while zooming | Layers.lua:785-985 |
| Estimates | disc (1,0.85,0.4,0.05) r 110 yd; 18 dashes at 1.5 px (1,0.85,0.4,0.35); merge within 0.6 r | Layers.lua |

### Path
| Element | Value | Spike ref |
|---|---|---|
| Stroke / wash | 1.6 px (1,0.93,0.76,0.7) over 3.4 px (0.12,0.08,0.03,0.3) | Path.lua:1-40 |
| Dashes | 6/4 px, ≤160 pieces; end fades 40 px; clearance 14 / 15 px | Path.lua |
| Ink | wobble 0.8·(0.6 sin(u·0.09+1.3)+0.4 sin(u·0.031+4.1)); α unevenness 25% sin(…·0.045+2); Bezier lead-in 48 px / 8 steps | Path.lua:220-275 |
| Redraw | half-pixel move, 3° turn, zoom change, new route | Path.lua |
| Edge arrow | `Interface\Minimap\ROTATING-MINIMAPGUIDEARROW` 32×32, 16 px inside edge | Path.lua |

### Menus and text
| Element | Value | Spike ref |
|---|---|---|
| Menus | client `MenuUtil.CreateContextMenu` only, no skin | Menu.lua |
| Gear tips | white title, gold (1,0.82,0) body; children indented 5 spaces, disabled while parent off | GearMenu.lua |
| Zone info | GOLD `|cffffd100`, WHITE, GREY `|cffa8a8a8`, DIM `|cff808080`; SEP dim `'  ·  '`; level green `|cff40c040` / red `|cffff6040` / grey | ZoneInfo.lua:1-187 |
| Quest tooltip | facts DIM `|cff9d9d9d`, tag orange `|cffff8040`, `|cff33ff33Ready to turn in`; ≤3 mobs + `(+N more)`; 14 px portraits; `Turn in to` at 0.85; `Click to follow` | QuestInfo.lua:175-369 |
| Chat | prefix `|cffffd100MagicMap|r: ` (`MagicMapAtlas` until M6); layers on `|cff33ff33`, off `|cff888888`, titles gold | Core.lua:44-46, Layers.lua:2196-2207 |

## 5. Feature checklist

Status today: B built, P partial, M missing. M0.8 turns this into `docs/parity.md` (one row per feature + style element, with proving test/script step and shot spot/zoom).

| # | Spike feature | Package | Now |
|---|---|---|---|
| 1 | Takes the minimap's spot, exact release | M1.6, M1.7 | P (engage/release) |
| 2 | Square metal chrome, hover controls | M1.7 | M |
| 3 | Zone title line (small/big rules, debug) | M1.7 (+debug M4.6) | M |
| 4 | Map picker on the title | M3.4 | M |
| 5 | Wheel and ± zoom, log chase | M1.8 | P |
| 6 | Pan; click vs drag | M1.8 | P |
| 7 | Follow toggle, idle return | M1.7, M1.8 (corpse → follow M3.3) | P |
| 8 | Move and resize (yards kept) | M1.7 | P |
| 9 | `/mma reset` (refused while big) | M1.7 | M |
| 10 | Big map: M, red button, Escape | M1.6, M1.7 | M |
| 11 | Small vs big differences | M1.7, M3.4 | M |
| 12 | Terrain tiles | M1.3 | B |
| 13 | Colour-matched tiles, coast fades, `/mma tint` | M1.4 | P |
| 14 | Player arrow (hidden off-map / withheld; under 'blizzard' M4.2) | M1.4 | P |
| 15 | Zone and subzone borders | M1.4 | P (demo style) |
| 16 | Zone and subzone labels | M1.1, M1.4 | P (demo style) |
| 17 | Hover zone, click to fly | M3.4 | M |
| 18 | `/mma map`, `/mma zone` | M3.4 | P (`map`) |
| 19 | Blip sensor | M1.5 | B (over budget) |
| 20 | Blip icons (incl. quest `!`/`?`) | M1.5, M4.3, M4.4 | P |
| 21 | Town services and remembered blips | M4.3, M4.4 | P (live only) |
| 22 | Duplicate tracking suppression, crash-safe | M4.2 | M |
| 23 | Gear: Tracking | M4.5 | M |
| 24 | Indoors: art or Blizzard floor plan, `/mma indoor` | M4.2, M4.4 | M |
| 25 | Rotate Minimap ignored | M1.5, M4.2 | P |
| 26 | Quest pins | M2.1–M2.4 | M |
| 27 | Difficulty colours | M2.3 | M |
| 28 | Rich quest tooltip | M2.4 | M |
| 29 | Quest areas (blobs) | M1.9, M2.4 | M |
| 30 | Estimated areas | M2.3, M2.4 | M |
| 31 | Click to follow a quest | M2.2, M2.4 | M |
| 32 | Target selection | M3.1 | M |
| 33 | Walking route line | M3.1, M3.3 | M |
| 34 | Off-map edge arrow | M3.3 | M |
| 35 | Waypoints (Ctrl-click / Ctrl-right-click) | M3.2, M3.4 | M |
| 36 | `/way` link (Shift-click) | M3.2, M3.4 | M |
| 37 | Right-click menu | M3.4 | P (follow only) |
| 38 | Zone info inspector | M3.4 (explored + landmark lines M4.4) | M |
| 39 | Places: flight, dungeons, graveyards, POIs | M4.1, M4.3, M4.4 | P (flight in labels) |
| 40 | Quests to pick up | M2.2–M2.4 | M |
| 41 | Party and raid dots | M4.1, M4.3, M4.4 | M |
| 42 | Corpse | M3.2, M3.3 | M |
| 43 | Rares seen account-wide | M4.1, M4.3 | P (static) |
| 44 | Live vignettes | M4.1, M4.3, M4.4 | M |
| 45 | Unexplored shade (opt-in) | M4.1, M4.4 | M |
| 46 | HBD world pins | M1.9 (thin), M4.2 | M |
| 47 | HBD minimap pins | M4.2 | M |
| 48 | Gear: layers + `/mma layers` | M1.7 (stub), M2–M3 add, M4.5 | M |
| 49 | Gear: Settings | M1.7 (Map, Minimap), M4.5 (Advanced) | M |
| 50 | Button tips | M1.7 | M |
| 51 | Pin hover tooltips | M2.1 | M |
| 52 | Minimap button, compartment, `/mma icon` | M1.6, M1.7 | M |
| 53 | `/mma toggle`, `/mma follow` | M1.7 | P |
| 54 | Diagnostics: blips, tiles, debug, perf, perf top, perf mem, landmarks | M4.6 | P (perf) |
| 55 | Account-wide saved state (SavedUI fields) | M1.7, M4.3 | P |
| 56 | No-data notice (one chat line) | M5.2 | M |

### Non-goals (docs/v1-non-goals.md, DRAFT: assumed until the user confirms, D2)
| Out | Note |
|---|---|
| Spike data migration | v1 starts fresh. Seen rares and blips from the spike are lost (say so in release notes) |
| Locales other than enUS | herb list, `Vein`/`Deposit`, tooltip-name matching are enUS |
| Routes beyond walking | no flight network drawn |
| Addon pin API | borrow HBD pins only |
| Gamepad | |
| Map rotating with camera | Rotate Minimap ignored |
| Positions inside instances | instance maps shown whole, no arrow/path/blips/borders |
| Per-character profiles, network telemetry, sharing rares | |
| Release-notes-only features | path auto-fit, "blips past the edge" (D4) |

## 6. Milestones

Every milestone ends playable in game and is gated by: one scripted session read with `telemetry.py --budgets` (8/8 PASS, `perf.slow`/`perf.gaps` empty, 0 taint, no `art` misses); `/mma shot` pairs against the reference shots; the lead updating spike-bugs.md and parity.md from hand-offs.

Legend for package tables: **Wave** = when it may start. **Iso** = worktree rule (W = own worktree, merged by lead; X = exclusive, holds listed files and merges before dependents start).

### M0 Groundwork (no visible change)

Goal: make parallel work safe, every FAIL attributable, the sim price what the client charges. User runs one session; its numbers are a HARD edge before M1.3 and M1.5's allocation work commit.

Exit:
- CI: check.sh green, BASELINE empty; `/` rule fails on a planted site; test_telemetry_fixture covers every new field.
- Sim: test_blips, test_map, test_spike_bugs, test_blips_replay pass unchanged after the split; a View/Observation with every new OPEN field nil runs; 100 probes ≈10 ms sim time; blob hit before layout → nil (L1); mocked oversized edge atlas → 200 px (L2).
- In game (user, ~5 min, spike disabled): `/mma bench regions` once; `/mma check art` clean; 2-min Dun Morogh with `/mma check log`. `--budgets --trace` names an owner for every FAIL from perf.alloc, swap {ms, live, parked}, perf.gaps, the worst-frames ledger, a mark's motion ring, ourKB after GC at load and logout, per-state histograms.
- The ~20 µs/region price and "sensor is the top allocator" are confirmed or corrected in writing in `docs/evidence/perf-m0.md` (new file, lead).
- Reference shots of the spike recorded (M0.8). `docs/parity.md` written.

| Pkg | Owner | Scope | Contracts | Verify | Wave / Iso |
|---|---|---|---|---|---|
| M0.1 Contract seams (diff only) | `types/` (sole editor until M6) | Confirm already present: obs.minimap.home/indoors, obs.you uiMap/level/faction/dead/ghost/combat, tracking `kind="duplicate"`, explored, indoorArt, addons, SavedUI window..tint, SavedGame trackingOff/buttonAngle, SavedModel.rares. Add only: optional `View.chrome` {rimArrows?, questRing?}; MM.Target `inside?`, `title?`, `quest?`; Route keeps `MM.Pos[]` and gains optional array fields `straight?`, `partial?`; Known kind shapes (quests, offers, places, group, corpse, waypoint, vignettes, services). Cap stays 200 (D6) | OPEN clauses of view.lua, model.lua only | test_no_globals, test_luacheck; all-nil scenario | Wave 0a, X (`types/`) — short |
| M0.2 Hot-file split + registries | game/, ui/, tools (one agent) | `Game.Part(name, read)` + `game/parts/*.lua`; `Game.Handle(kind, fn)` + `game/commands/*.lua`; `Game.Apply(name, fn)` for Minimap apply steps; ui/Map.lua → `ui/Engine.lua` (canvases, jobs, swap, pools, `Engine.Layer`), `ui/Camera.lua` (state, settled, velocity; stubs `Camera.Settled()`, `Camera.Velocity()`), `ui/Motion.lua` (chase, AnimateTo, idle, click/drag), `ui/Window.lua` (frame, input routing). Per-folder `files.txt` manifests, TOC generated by install.py and verified by check.sh. Replays move to `tools/tests/replays/R-XX.lua` with one parametrized collector. FORMATS becomes a per-Data-file table. Document registries in docs/structure.md and architecture.md | None | Same assertions pass, no behaviour change | Wave 0b (after M0.1), X (game/Observe, Command, Minimap; ui/Map; TOC; luacheck.py NS_RULES/BOUNDARIES; test_spike_bugs.py). Land within day 1 |
| M0.3 Runtime attribution | runtime/Runtime.lua | Per-call kb/kbMax around Wrap Finish and each RunJobs resume (negatives ignored); `perf.alloc` top 5 KB/s; spike trace names top allocator; yield gaps: `gap` trace + `perf.gaps` with debugstack(2) once per job; worst-5 frames ledger ±10 events; histograms by map state (hook set by UI). Hands key list to M0.4 | None (Perf OPEN) | Sim: 100 KB job tops perf.alloc; 10 ms between yields leaves one gap; test_failures passes | Wave 0a, W |
| M0.4 Telemetry, reader, play-test kit | game/Telemetry.lua, game/Record.lua, tools/telemetry.py, docs/telemetry.md, docs/runtime.md (sole owner of all five) | Full collect then UpdateAddOnMemoryUsage after login grace (`ourKBLoad`) and at logout (`ourKB`); runtime.md memory row "after full collect". 120-frame motion ring in marks. Record swap/layout-end/sweep stats, copy `Bench.result` → `bench[build]`, flag ADDON_ACTION_BLOCKED/FORBIDDEN as `taint`, `art` misses. `/mma shot` stamps zoom, camera, window size, UI scale. telemetry.py: `--trace` full ring, end→swap column, per-state histograms, alloc/gaps/ledger/bench/taint/art, `--compare`, shot pairing. Kit scripts (each lists steps, marks, shots, `/mma check log` on): (a) Dun Morogh open, wheel 4→1024→4, fling, 2-min follow at 1024 small across a tile boundary, grow/shrink ×5, Ironforge, continent 4–24; (b) 25-quest hub; (c) route + corpse run, M/Escape/L/`/mma toggle` in combat; (d) capital, indoor, party, combat toggles; (e) continent zoom with Questie + GatherMate. Shot list per gate: spot, uiMap, zoom, small/big | View.diag free-form | test_telemetry_fixture per field; `--budgets` on fixture names owners; sim mark mid-walk carries 120 ring entries | Wave 0a, W |
| M0.5 Bench + art check | game/Bench.lua (replaces game/Validate.lua atlas checks), ui/Art.lua (art name list) | `/mma bench regions`: CreateLine/Texture/FontString, SetStartPoint, SetPoint; canvas SetPoint/SetScale/Show/Hide/SetAlpha at N=100, 1000 live and 1000 hidden; SetParent to park frame → `Bench.result`. `/mma check art`: GetAtlasInfo / file ids for every name in ui/Art.lua, at login after grace, misses → `art` trace. Delete Validate's spike checks covered by test_atlas; keep `/mma check log` | None | Sim writes bench table of right shape; a missing atlas gives one `art` trace | Wave 0a, W |
| M0.6 Sim fidelity + fixture streams | tools/tests/wowsim.lua, fixtures.py, replay.lua | Clock cost per probe (~0.1 ms) and per region on canvas Show/Hide/SetScale (~20 µs, updated from bench); GetMinimapMouseover allocates; oversized edge atlases (L2); DrawBlob hit only after next layout frame (L1); view radius 0 while zooming (E3/E6); HBD-Pins-2.0 mock with renamed copies; protected-call log under InCombatLockdown (K2); x/0 raises in an opt-in strict mode. Fixture streams: quests, offers, group, corpse, waypoint, vignettes, places, tracking, explored | None | Existing pass; self-tests as in exit; each stream replays through Model | Wave 0a, W |
| M0.7 `/` lint + Atlas first-use rule | tools/lint_div.py (new, called by check.sh), atlas/Camera.lua, docs/structure.md (rule section only) | R-E3: flag `/` in atlas/model/game/ui unless literal/named constant divisor or `-- /: never 0 (why)`. Fix/annotate all sites; Camera.Fit takes a minimum span. Rule: whole-table Atlas indexes are offline or take `step` | None | check.sh fails on planted site; Fit on one point is finite | Wave 0a, W; merge before M1.4/M1.5 |
| M0.8 Parity doc + reference shots | Lead + user | Write docs/parity.md from §4–§5 (one row per feature and style element: package, proof, shot spot/zoom; non-goals "out, by decision"). User runs one spike-only session (rebuild disabled) taking the shot list → `docs/evidence/shots/` | None | Every §5 row present; shot set complete | Wave 0a, W |
| M0 gate | Lead + user | Install, session above, triage to perf-m0.md | — | Exit list | Last |

### M1 Budgets green + the spike's face

Goal: user logs in and sees the spike: the 200 yd square on Blizzard's spot, metal hairline, gold title, hover controls, wheel glide, follow and idle return, M/Escape grow/shrink, spike ground style. 8/8 PASS, tear gone. QuestPOI Inside, HBD borrow, hooks and taint proven thin in game.

Exit:
- Sim: R-P1 at 1.5 views/s (borders ≥97% frames, tiles ≥99%, fresh ≤1 s); R-P7 (≤1 layout/layer after settle, no SetScale on borders); R-P3 ≤0.5 KB/frame walking with sensor + 10 blips; observe ≤2 ms on priced clock; R-P2 (every Atlas first-use in a 1 ms Job ≤2 ms); per-frame invariants on all replays: offsets ≤4096 px, map textures/masks/lines unsnapped (FontStrings excepted), shared region origin, D1 (≤1 canvas/layer α>0 outside a timed fade), no visible Blizzard Minimap art, no protected calls in combat. test_atlas Labels golden; test_generators QuestSources identical after diet. test_chrome, test_bigmap, test_zoom, test_motion, reset refused while big. Replays R-G3, R-G7, R-D3, R-D5a, R-D5b, R-E6, R-L1, HBD round trip.
- In game, script (a), spike disabled: 8/8 PASS (max ≤8, p95 ≤1, p99 ≤5, first open ≤50 target ≤20, ourKB after GC ≤64 expect ~40, alloc ≤50 KB/s, load ≤250, 0 errors); no `map: borders/labels/draw` or `game.observe` in perf.slow; perf.gaps empty; 0 taint; tear re-check at 1024 across a tile boundary clean (ring + shot); shot pairs vs reference and `docs/zoomable-minimap.gif`, `minimap-to-big-map.gif`, `big-map-zoom.gif` signed off; M, Escape, L as spike; `/mma toggle` restores Blizzard's minimap exactly; `/mma check inside` agrees with standing in a quest area; Questie pins borrowed and returned.

| Pkg | Owner | Scope | Contracts | Verify | Wave / Iso |
|---|---|---|---|---|---|
| M1.1 Offline labels | tools/gen_labels.py (new), Data/Labels.lua, atlas/Labels.lua, atlas manifest, docs/atlas-data.md (Labels section) | Port VisualCentre, POI/subzone merge, rank sort to Python; emit `Data.Labels[inst]` ranked {text, col, row, tier, size, areaID?, poiID?}; Atlas.Labels = lookup; bump its own FORMATS key | None | Golden = old runtime output (col/row ±0.01, same order); determinism; in game first open ≤50 | Wave 1a, W |
| M1.2 Data diet + BlipServices | tools/gen_questie.py, tools/gen_world.py, atlas/Entities.lua | Items reachable from Quests only (objectives, startedBy, startQuest); ItemIcons same; drop NPCs without open-world spawn unless quest/rare/service needs them; emit `Data.BlipServices {[name]=service}` (name agreed day 1); retire NpcsByName from runtime; Names() offline or `step`; Atlas returns empty indexes when Data.X is nil | None. **Blocked on D3** | QuestSources identical for every quest; all ids resolve; lupa Items ≤2 MB; boot.loadKB ~36 MB | Wave 1a, W |
| M1.3 Engine perf | ui/Engine.lua, ui/Camera.lua | (a) park leftovers via SetParent to hidden frame; (b) settled = zoom unchanged 0.15 s; rebuild on settle or scale outside [0.7,1.4]; (c) zooming: tiles SetScale or in-place relayout per bench; borders never scaled, held then crossfaded 0.12 s at settle; labels move without SetScale; (d) swap = bench's pick (alpha-0 pre-shown + SetAlpha, or extend in place); (e) velocity prefetch leading side, trailing 0.25; uncovered layer 8 ms budget; order tiles, borders, labels, pins; (f) canvas origin at region's top-left tile; all layers share origin; (g) emit swap {ms, live, parked}, layout-end {made}; (h) D1 invariant | None | R-P1, R-P7, 20-step wheel call log; children after swap = live; borders swap ≤4 ms; zooming ≤2 ms draw (test_zoom_draw_priced, xfail until then: M1.8's Verify item, handed on); flights too (grow, shrink, follow glide, idle return: each frame re-lays and SetScales every canvas today, 19-31 overruns a grow on the priced clock): overruns and kbPerSec over the animation, not only the wheel's draw max; R-P3's drag start measured on its own (0.5-10 KB a drag start, outside every window now) | Wave 1b (**after M0 gate numbers**), X (Engine, Camera) |
| M1.4 Ground layers, spike cost and style | ui/Borders.lua, ui/Tiles.lua, ui/Labels.lua, ui/You.lua (arrow), tools/gen_borders.py (bands), tools/gen_arrow.py + Textures/PlayerArrow.tga | Borders per §4 (2 Lines/segment, cap 3000, ≤4 fade pieces/end, merge <2.5 px, no per-line `p`); bands 0.15 tile <zoom 12, 0.05 <30. Labels per §4; flight icons leave Labels; subzones placed near view, re-placed on pan out. Tiles: unsnap masks, `SavedUI.tint` + `/mma tint` with `(no data for this map)`, the gear's "Colour-matched tiles" (a stub flipping `SavedUI.tint` since M1.7) running the same function, re-lay and message, as GearMenu.lua:49 routes through the command; seam overlap (1 px R/B, half-texel inset) only if a shot shows a seam. Arrow per §4, hidden off-map or withheld | None | 2 Lines/segment; ≤3000 at zoom 4 EK; label counts at 100/200/500; tint relays; band goldens; shots at 3 zooms | Wave 1c (after M1.3's Engine.Layer API merges), W |
| M1.5 Sensor time budget + G3 | game/Blips.lua, game/Minimap.lua (sole owner in M1) | Probe until 0.5 ms (1 ms kept frame p95 over 1 ms: sweep frames are far more than 5%); resumable Locate record dropped on Restart, measured only while still; parse cache per raw leftText; while moving sweep at most every REST; Icon() reads BlipServices, pcall removed; `blips` trace per sweep, `sensor` trace on blind or >25% square drift; radius 0 = not engaged; re-assert ground textures, rotation, SetIgnoreRotateMinimap every apply | None | test_blips priced: ≤2 ms/frame, frame p95 ≤1 ms, exact within 2 sweeps; R-G3, R-D3, R-D5a, R-D5b, R-E6 | Wave 1a (alloc part after M0 gate), W |
| M1.6 Takeover placement, hooks, button, tooltip hide | game/parts/MinimapState.lua, game/Home.lua, game/Chrome.lua (via Game.Apply), game/Hooks.lua, game/Button.lua, game/Tooltip.lua, game/Game.lua (Load('Game') line) | Publish obs.minimap.home (read before engage, cached, re-read on UI scale change). hooksecurefunc ToggleWorldMap (hide Blizzard's only when ours shown and it just opened → `hooked worldmap`). Escape catcher in UISpecialFrames while big. homeAlpha, big strata HIGH + Raise. Game.Load('Game'). Rim button per §4, `/mma icon`, AddonCompartmentFunc. View.chrome rim arrows/quest ring. One owner-checked GameTooltip hide path (leave, release, window hide) | M0.1 OPEN fields | Sim: M keeps WorldMapFrame hidden + hooked; L opens Blizzard's; Escape only while big; buttonAngle survives reload; release restores every property; R-G7; no protected calls in combat | Wave 1a, W |
| M1.7 Chrome, window, big map | ui/Window.lua, ui/Chrome.lua, ui/Title.lua, ui/Controls.lua, ui/BigMap.lua, ui/Menus.lua (gear stub), ui/View.lua | Port §4 frame, title band, buttons, hover, tips, minimap form, grow/shrink exactly; zone fit uses you.uiMap (M1.10). Grow mid-shrink keeps small rect; hide while big snaps; logout saves small rect; consume Model.hooked. Load SavedUI window, shown, zoom, follow, inst, center, button, tint. `/mma reset` (`reset: shrink the map back first (M)`), `/mma toggle`, `/mma follow`. Minimal gear: Settings > Map (Colour-matched tiles), Minimap (Minimap button, Reset position, Use Blizzard's minimap) | M0.1 only | test_chrome (L2 clamp, home placement, 0.15 s fade), test_bigmap (L3, L4, Escape), yards kept on resize, reset refused while big; shots | Wave 1a, W |
| M1.8 Camera feel | ui/Motion.lua | §4 zoom, chase, AnimateTo, click/drag thresholds, idle return 6 s; Focus sends rect; drives Camera.Settled via the M0.2 stub. (Corpse-forced follow moved to M3.3) | Focus (0002) rect | Sim: chase converges; idle fires at 6 s, not while hovered; flight end state; thresholds; zooming ≤2 ms draw | Wave 1a, W |
| M1.9 Unknowns probe | game/Oracles.lua, game/AddonPins.lua (skeleton), game/parts/Addons.lua | Oracles.Inside on Game's hidden QuestPOI frame per uiMap: draw, redraw next frame, hit test, cache per quest until QUEST_POI_UPDATE, within CALL_MS; `/mma check inside`. Thin HBD borrow: every copy via LibStub, world pins to View.sockets.world while open, returned on close/world-map open, borrowed and returned in 1 ms jobs. Publish obs.addons. (Review: UI's minimal world socket, ui/Sockets.lua, brought forward from M4.4 so the round trip runs for real) | Oracles (0001), Sockets (0003) | R-L1 (nil before layout, right after, ≤2 ms over 25 quests), R-G6, R-G6b (3000 pins, no call over 2 ms), R-E4, pins return to original parent and points | Wave 1a, W |
| M1.10 You part | game/parts/You.lua | uiMap, level, faction, dead, ghost, combat | Already typed | Sim round trip | Wave 1a, W |
| M1 gate | Lead + user | Script (a), triage via perf.alloc/ledger/swap, tear re-check, shots. Also, from wave 1a's review: M in combat (game/Hooks.lua leaves Blizzard's map open in combat: prove whether HideUIPanel(WorldMapFrame) is blocked there; if not, drop the guard, else record it in parity F10 and spike-bugs K2); the takeover in combat (the cluster faded, its hide or show waiting for combat's end: R-K2) as the client does it; QuestSources after the diet (CI has no QuestieDB: the local run is the evidence, 159 never-resolving source ids dropped, 4 objectives left with none); the world socket while zooming (scaled, pins grow with the motion, re-placed at rest) against the bench's SetScale and SetPoint prices; M1.5's parse cache, still OPEN | — | Exit list | Last |

Parallel waves: 1a = M1.1, 1.2, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10 from day 1; 1b = M1.3 once M0 numbers land; 1c = M1.4 after M1.3's layer API. Day-1 agreements: BlipServices name (M1.2↔M1.5), settled API (M1.3↔M1.8, stubbed in M0.2), hooked/homeAlpha flow (M1.6↔M1.7).

### M2 Quests on one pin store

Goal: quest pins in Blizzard art with difficulty discs, objective icons and counts; rich tooltip; styled blobs, estimates, hover lighting; click to super-track; quests to pick up. One pin store diffed by id also carries blips and rares.

Exit:
- Sim: test_quests (forms, 22/26, glow, count); click → follow Command → super-track back in obs; tooltip line order (≤3 mobs + `+N`, Turn in to); test_quest_areas (Inside after deferred layout; estimate when no blob, merged within 0.6 r); pin-store diff (200 pins, 1 changed → 1 relaid; unchanged rev → 0 regions); R-P5, R-L1 (UI); per-frame no-duplicate-pin; no-QuestieDB-data scenario: 0 errors, pins drawn, tooltip without mob/item/turn-in lines.
- In game, script (b): 8/8 PASS, quest-heavy open ≤50 ms, shots match, click super-tracks in Blizzard's tracker.

| Pkg | Owner | Scope | Contracts | Verify | Wave / Iso |
|---|---|---|---|---|---|
| M2.1 Pin store, StylePin, pin tooltips | ui/Pins.lua (+ migrate ui/Blips.lua, ui/Rares.lua) | One store diffed by id, re-placed on pan, changed on rev, minZoom per kind; StylePin (a)–(d), glow, count per §4; tooltip via M1.6 hide path; clicks propagate. Stub API in first commit | Reads Known (0006) | Diff scenario; drag over pin pans; test_blips, test_map pass | Wave 2a, W |
| M2.2 Observation quests, offers; Commands follow, tooltip | game/parts/Quests.lua, Offers.lua; game/commands/follow.lua, tooltip.lua | Quests via GetQuestsOnMap over continent zones (smallest map wins, indicators skipped), objectives, complete, super-tracked, level, trivial, areaMap; coalesced 0.3 s on the 5 events. Offers via C_QuestLine per zone scoped to Focus.inst, once per map, re-asked on QUESTLINE_UPDATE with arg, hidden per CVar. follow: AddQuestWatch + SetSuperTrackedQuestID / 0. tooltip: unit/member/npc portrait; portraits from mouseover/target/nameplates ≤300/session | Typed | Per-part and per-command round trips; fixture stream = real part output | Wave 2a, W |
| M2.3 Model quests, offers | model/Quests.lua, model/Offers.lua | Known('quests') with difficulty (§4), first-objective icon, `n/m`, Atlas sources (drops by level ≤3 + N, objects, vendors, finishedBy); Inside nil → 110 yd estimate merged within 0.6 r for kill/collect/interact; Known('offers') skipping in-progress | M0.1 Known shapes | Model-alone fixture replay: kinds, colours, merge, blob → no estimate | Wave 2a (Inside stub until data), W |
| M2.4 UI quests, areas, estimates, tooltip | ui/Quests.lua, ui/Areas.lua, ui/QuestTooltip.lua | Pins, blobs (twice, hidden while zooming, redrawn at settle), estimates, hover per §4; click pin/area toggles follow, pins beat areas; tooltip exactly per QuestInfo.lua. Layers Quests, Quest areas, Estimate missing areas, Quests to pick up, added to the gear stub | follow, tooltip Commands | R-P5, R-L1 (UI); click toggles; tooltip order; budgets with 25 quests | Wave 2b (after M2.1 stub), W |
| M2 gate | Lead + user | Script (b), shots, triage | — | Exit list | Last |

### M3 Target, route, interactions

Goal: hand-inked dashed route to corpse, followed-quest edge or waypoint, with edge arrow; waypoints and `/way`; right-click menu and big-map inspector; map picker; zone hover-and-fly; `/mma map`, `/mma zone`.

Exit:
- Sim: test_route (A* Job ≤2× budget/resume, 60k cap, old route kept, replan on 3-chunk stray / 2-chunk target move, no inf/nan: R-M1, R-E3, R-P2; Dun Morogh route at ≤1 ms/frame); test_target (ghost→corpse, quest edge, waypoint, inside held 0.5 s); path ≤160 pieces, 0 redraws standing, edge arrow when off view; corpse forces follow; test_interact (Ctrl-click waypoint, inspector lines for zone/coords/level/distance/quests, distance rounding, picker groups for EK, zone click flies 0.55 s follow off, quest areas not clickable while zone clicks on offer); instance map shown whole with no arrow/path/blips/borders; R-G2 (browsing another continent keeps the takeover engaged); R-G4.
- In game, script (c): 8/8 PASS, route jobs never in perf.slow, 0 taint in combat toggles; shots vs `MagicMap-path-mode.gif` line style and spike ZoneInfo output.

| Pkg | Owner | Scope | Contracts | Verify | Wave / Iso |
|---|---|---|---|---|---|
| M3.1 Model Target, Route | model/Target.lua, model/Route.lua | Priority corpse (ghost) → followed quest on shown map → waypoint; quest edge via 7 rays (±0.35/0.7/1.05) × 16 steps + 8 refinements every 0.25 s, inside held 0.5 s. A* over Atlas.Walk in a Job, 1 ms/frame, 60k cap, 33 yd chunks; swim 3, magma/slime 25, cliffs blocked; snap ≤4 chunks; LOS straighten, corner round; replan rules; no data → straight, no way → partial; same instance only; divisors annotated | Target/Route OPEN fields from M0.1 | test_route, test_target, R-M1, R-E3, R-P2 | Wave 3a, W |
| M3.2 Game waypoint, way, corpse | game/commands/waypoint.lua, way.lua; game/parts/Waypoint.lua, Corpse.lua | waypoint: zone uiMap at point, SetUserWaypoint + super-track, spike messages, false clears; way: chat `/way <zone> %.1f %.1f` not sent; corpse polled 1 s after release until found, refreshed on PLAYER_DEAD/ALIVE/UNGHOST | Typed | Round trips; R-G4 | Wave 3a, W |
| M3.3 UI path, edge arrow, corpse/waypoint pins, title target | ui/Path.lua, ui/You.lua (pins + title target only) | Path, edge arrow, pins per §4; title `|cffffd27f<title>|r N yd` / `here`; corpse target forces follow (moved from M1.8) | Reads Target, Route | Piece cap; 0 redraws standing; arrow position; alloc while walking ≤50 KB/s | Wave 3a, W |
| M3.4 Menus, inspector, zone hover/fly | ui/Menus.lua (picker + right-click sections), ui/ZoneInfo.lua, ui/Window.lua (input) | Picker per §4 (Continents ≥300 tiles, Other maps, Instances by entrance continent, single group skipped); zone hover only with >1 zone of weight ≥30 in view, hover border/label, click flies 0.92 fit, follow off; right-click: Waypoint here, Clear waypoint, Follow me; big map leads with inspector (zone, subzones, coords, level, distance/compass, ≤2 quests). Explored and landmark lines come in M4.4. Ctrl/Ctrl-right/Shift clicks; `/mma map`, `/mma zone` with spike messages; precedence rule for quest areas vs zone clicks | waypoint, way Commands | test_interact; picker groups EK; inspector at a known Elwynn spot; R-G2; instance-map scenario | Wave 3a, W (owns Window.lua input for M3) |
| M3 gate | Lead + user | Script (c), shots, triage | — | Exit list | Last |

### M4 Feature-complete

Goal: places, group, rares account-wide with vignettes, services and remembered blips (incl. quest `!`/`?`), duplicate suppression with crash-safe restore, gear menu complete, indoor renderers, full HBD world + minimap pins, opt-in shade, diagnostics slash.

Exit:
- Sim: test_places (dedupe across maps), test_group (dead grey, 20 Hz), R-D4, R-E2, R-S1, test_services (zoom 60 shows, 59 not; tracking off hides), test_tracking (restored after simulated crash + reload), R-G1 (Undercity, Orgrimmar 1454, no art → blizzard), test_addonpins (continent filter, 128 px, Questie complete skipped, hidden under Rotate Minimap), test_gear (tree and indentation match spike), shade cell count, inspector explored + landmark lines; per-frame over all replays: no duplicate visible pins, no Blizzard Minimap art outside 'blizzard'. Every MOVED spike-bugs row has a replay or a listed in-game check.
- In game, scripts (d) and (e): 8/8 PASS with every default layer on; every gear toggle works; `/reload` mid-session restores tracking; 0 taint.

| Pkg | Owner | Scope | Contracts | Verify | Wave / Iso |
|---|---|---|---|---|---|
| M4.1 Game parts + tracking Command | game/parts/Places.lua, Group.lua, Vignettes.lua, Explored.lua, Tracking.lua; game/commands/tracking.lua | places (TaxiMap, EncounterJournal, DeathInfo graveyards, AreaPoiInfo on AREA_POIS_UPDATED); group ~20 Hz, class, dead, withheld skipped; vignettes not dead + rares from target (keyed by NPC id); explored per AreaID, 700 samples/frame; tracking with duplicate kind; SetTracking | Typed | Per part; R-E2; observe ≤2 ms all on | Wave 4a, W |
| M4.2 Game apply: duplicates, indoors, full HBD | game/Tracking.lua, game/Renderer.lua, game/parts/IndoorArt.lua, game/AddonPins.lua (via Game.Apply) | Turn off TaxiNode/QuestPOIs/POI while sensing outdoors and our layer on; save trackingOff; restore at stop/release/logout and after crash on PLAYER_ENTERING_WORLD / MINIMAP_UPDATE_TRACKING; ≤ every 2 s. Indoors from view radius vs zoom widths, OPEN_CITIES (1454); indoorArt ≤1600 yd or dungeon floor; renderer 'blizzard' (whole Minimap in small window over black, wheel zooms it, its arrow; ours hidden); `/mma indoor`. HBD full: continent-only past 48 px/tile, skip >128 px and -1 pins, skip Questie complete when we show turn-in, sync 0.1 s after change + every 1 s; minimap pins via SetMinimapObject to host on sockets.minimap, hidden under Rotate Minimap / off map; renamed copy hosting world pins → its minimap pins hidden | SavedGame (0004), View.renderer, sockets (0003) | test_tracking, R-G1, test_addonpins | Wave 4a, W |
| M4.3 Model kinds | model/Places.lua, Group.lua, Rares.lua, Services.lua, Blips.lua | places static + live, deduped; group, corpse, waypoint kinds; rares read/write SavedModel.rares, hidden under same-name live vignette (D4); services from zoom 60 in a Job, gated by tracking (one switch both trainers); remembered blips live=false, hourly refresh, forget at 0.8×220 yd, LAG merge, Kind() current inst only, cap per D6; quest `!`/`?` blip icons when our layers don't cover | SavedModel (0004); D6=300 → ADR 0004 amendment + part `_v` bump | R-D4, R-S1, test_services; rare survives reload | Wave 4a, W |
| M4.4 UI remaining layers | ui/Places.lua, ui/Group.lua, ui/Shade.lua, ui/IndoorArt.lua, ui/Sockets.lua (the world socket's minimum is there since M1), ui/ZoneInfo.lua (explored + landmark lines) | Pins per §4 on the store; shade (old kept until new pass done); indoor art; pick View.renderer; publish sockets (the minimap one; the world one's addon layers toggled from the menu), layers (flight, quests, pois, addon:*), chrome flags; inspector `Unexplored, near …` and ≤2 landmarks within 900 yd even when that layer is off | View (0003) | Each kind with defaults, toggle hides; shade count; View snapshot small/big/indoor/hidden; inspector lines | Wave 4a, W |
| M4.5 Gear menu complete | ui/Menus.lua (gear section) | Groups Map, Quests, Places, People, You, Other addons; tips, indentation, greying, empty groups hidden; Tracking (non-duplicates → Command); Settings Advanced (Diagnostics: Debug info in the title, Indoor maps; Performance: Record 10 seconds, Compare with other addons, Memory breakdown); SavedUI.layers changed keys only; `/mma layers` | SavedUI.layers | test_gear small vs big; toggles reach SavedUI and View.layers | Wave 4a, W |
| M4.6 Diagnostics slash + cleanup | game/Slash.lua, runtime Perf, ui/Title.lua (debug line) | `/mma blips, tiles, debug, indoor, perf, perf top, perf mem, landmarks` matching spike output; gear Advanced calls same code; title debug (tile col_row, FileDataID, zoom, layout ms); remove remaining Validate spike code, keep check log, bench, art | None | Each command prints without error | Wave 4a, W |
| M4 gate | Lead + user | Scripts (d), (e), parity rows, shots | — | Exit list | Last |

### M5 Full-load hardening + parity sign-off

Goal: every layer on, budgets hold in the worst places, every parity row signed, no MOVED row without a test or reason.

Exit: full replay suite + 10-min sim soak (memory flat after GC, no stuck jobs); spike-bugs.md has no unexplained MOVED (G3, P4, K2, L5 included); CI green, BASELINE empty. In game: scripts (a)–(e), 10+ min each, on two sessions: 0 errors, 8/8, perf.slow/gaps/sensor/art empty, 0 taint; parity.md signed by the user with shots; FarmHud yield and Rotate Minimap checked.

| Pkg | Owner | Scope | Contracts | Verify | Wave / Iso |
|---|---|---|---|---|---|
| M5.1 Perf soak + fixes | Owners named by perf.alloc / perf.gaps | Run scripts, fix at the attributed owner, `--compare` | None | 2 sessions all PASS | Wave 5, W per fix |
| M5.2 Replay sweep + no-data build | tools/tests/replays, test_spike_bugs.py | Close remaining R-*; CI "no-QuestieDB-data" scenario over M2–M4 replays (0 errors, pins drawn, reduced tooltips, one chat notice); hand statuses to lead | None | pytest green; no unexplained MOVED | Wave 5, W |
| M5.3 Visual parity pass | UI owners, with user | Shot pairs vs reference; fix values only | None | User signs parity.md | Wave 5, W |

### M6 Rename, merge, release (features frozen)

Exit: full CI green under new names incl. test_only_game_defines_globals; sim loads a real spike `MagicMapDB` fixture and shows the D9 behaviour with ourKB after GC ≤64; packaged zip installed alone (spike removed) loads with 0 errors, final 8/8; `/mm`, rim button, compartment work; no `MagicMapAtlas` strings; Data regenerated for the release build with goldens checked and 0 K4 drift; release notes match code; the user does any push/upload.

| Pkg | Owner | Scope | Contracts | Verify | Wave / Iso |
|---|---|---|---|---|---|
| M6.1 Rename | Whole tree, one agent | TOC/folder, SV per D9 with fresh `_v`, `/mm` + `/magicmap`, chat prefix, frame names, compartment func, luacheck BOUNDARIES, telemetry.py, install.py (refuses while spike folder present; warns "restart the client (not /reload)" when files were added, L5) | **ADR 0007** "v1 storage names" (LOCKED SV change; spike keys and MagicMapLandmarks loss stated) | Full pytest + luacheck; sim `/mm` toggle + reload; spike-DB fixture test; in-game install | Alone after M5, X (whole tree) |
| M6.2 Merge into ~/code/MagicMap | Tooling (git; user approves every write and push) | Tag spike `spike-1.0.0`; import per D8; carry CI, docs, README media, LICENSE | None | CI green there; tag reachable | After M6.1, X |
| M6.3 Package + release | tools/package.sh, dist/, README | Rerun every generator on the release build, test_generators goldens (re-bless only after in-game look), bump `## Interface`, one `/mma check log` session; zip from tag with Data per D1; release notes from code; version per D7; README features from parity.md; user records new GIFs; CurseForge/Wago metadata draft | None | Unzip into clean AddOns: 0 errors, final telemetry session | With M6.2, W |

## 7. Swarm schedule

| Wave | Packages (parallel) | Exclusive holds |
|---|---|---|
| 0a | M0.1, M0.3, M0.4, M0.5, M0.6, M0.7, M0.8 | M0.1: `types/` |
| 0b | M0.2 (after M0.1; target: day 1) | game/Observe, Command, Minimap; ui/Map; TOC; luacheck.py; test_spike_bugs.py |
| gate | M0 user session (HARD edge for M1.3 and M1.5 alloc) | — |
| 1a | M1.1, 1.2*, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10 (*after D3) | — |
| 1b | M1.3 (after M0 numbers) | ui/Engine.lua, ui/Camera.lua |
| 1c | M1.4 (after M1.3 layer API) | — |
| 2a/2b | M2.1, 2.2, 2.3 → M2.4 after M2.1 stub | — |
| 3a | M3.1–M3.4 | — |
| 4a | M4.1–M4.6 | — |
| 5 | M5.1–M5.3 | — |
| 6 | M6.1 alone → M6.2 + M6.3 | M6.1: whole tree |

Counts: **38 work packages** (M0 8, M1 10, M2 4, M3 4, M4 6, M5 3, M6 3) + 5 gate packages (M0–M4). Max swarm width: 8 (wave 1a).

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Perf diagnoses come from one 90 s session (20 µs/region, sensor as top allocator) | M0.3/M0.5 measure; HARD edge before M1.3 and M1.5 alloc commit |
| Sim can't see rendering, taint, SetScale cost, deferred layout, widget allocation; user play time is the critical path | M0.6 prices what it can; M0.4 batches each gate into one scripted session; reference shots once in M0.8 |
| M1 is heavy (perf + chrome + hooks + probes + You part) | M0.2 seams (Motion.lua, Game.Apply, manifests) keep 8 packages parallel; only M1.3 → M1.4 is serial |
| M0.2 is the single serial bottleneck | Mechanical, one agent, land day 1; everything else in wave 0a avoids its files |
| QuestPOI draw-then-redraw quirk underpins areas, edges, estimates | Proven in game at M1 (M1.9, `/mma check inside`); R-L1 in sim |
| HBD internals (worldmapPins, SetMinimapObject, Questie icon.data.Type) can change | Thin proof in M1, full in M4; round-trip test; re-check at M5 and in final session |
| Forever atlases can blank chrome silently | `/mma check art` (M0.5) every login → `art` trace, `--budgets` prints misses |
| Tear survives origin + unsnap fixes | Motion ring + shot; seam overlap fallback in M1.4 |
| ~10 new layers in M2–M4 push budgets back over | Pin store diffed by id, parked pools, 8/8 at every gate, M5 backstop |
| Spike and rebuild both hook ToggleWorldMap / take Minimap | Spike disabled in every play-test; install.py refuses at M6 while the spike folder exists |
| Taint (K2) from hiding cluster, UISpecialFrames, hooks, SetParent of HBD frames | Sim protected-call log in combat; combat steps in scripts (c)/(d); `taint` events = 0 in M1/M5 exits |
| New texture files not seen on `/reload` (L5) | install.py warns "restart the client"; kit says so |
| Data filter removes rows a later feature needs | Only if D2/D3 confirmed; item tooltips and dungeon NPCs out of v1 |
| No QuestieDB licence blocks public release | D1; no-data CI scenario keeps the public build working |
| Shared `MagicMapDB` holds spike root keys (blipLog can be MBs) and breaks 64 MB for spike users; MagicMapLandmarks dropped | D9 + ADR 0007; spike-DB fixture test in M6.1 |
| Data built for 1.60.1; K4 tile id drift at release | M6.3 regenerates, checks goldens, 0 drift lines |
| Release notes promise removed features | Plan follows code (D4) |

## 9. Decisions needed from the user up front

| # | Decision | Blocks | Recommendation |
|---|---|---|---|
| D1 | QuestieDB licence: get permission, ship without derived data (degraded tooltips, services, blip icons), or keep 1.0 private | public upload (M6.3) | decide by M5; internal 1.0 proceeds |
| D2 | Confirm docs/v1-non-goals.md (DRAFT) as listed in §5 | M1.2, parity.md | confirm |
| D3 | Approve offline filter of Items, ItemIcons, NPCs (no item tooltips, no dungeon NPCs in v1) | M1.2 (memory FAIL) | **DECIDED 2026-10-15: approved** |
| D4 | Spec source: spike 1.0 code, or bring back "blips past the edge" and path auto-fit | parity.md, scope | **DECIDED 2026-10-15: the spike's code** |
| D5 | Border look: spike's 1 shadow + line (2 Lines/segment), or demo's 2 halos + line | M1.4 | **DECIDED 2026-10-15: spike (1 shadow + line)** |
| D6 | Seen-blips cap per instance: 200 (contract) or 300 (spike, needs ADR 0004 amendment) | M4.3, R-S1 | 200 |
| D7 | Version and channel: re-release as 1.0, or 1.1 / 2.0; CurseForge / Wago / GitHub; beta builds per milestone? | M6.3 | user's call |
| D8 | Merge mechanics: tag spike `spike-1.0.0` and replace tree (history or squashed), or separate repo; confirm before any push | M6.2 | tag + replace with history |
| D9 | Saved name: new SV (e.g. `MagicMapDB_v1`, spike file left orphaned) or keep `MagicMapDB` and clear non-owner root keys once; accept spike rares are lost | M6.1, ADR 0007 | **DECIDED 2026-10-15: new SV name** (spike rares lost, accepted) |
| D10 | Commit to the play-test sessions: M0 reference shots (spike only), M0, M1, M2, M3, M4, M5 ×2, M6 final, spike disabled, shots per script | every gate | — |

## 10. Critic gaps: where each landed

| Gap | Resolution |
|---|---|
| Camera.lua shared by M1.3 / M1.8 | M0.2 splits Camera.lua (M1.3) and Motion.lua (M1.8), Settled/Velocity stubbed |
| game/Minimap.lua shared by M1.5 / M1.6 / M1.9 | `Game.Apply` registry; M1.6 gets Home.lua + Chrome.lua; M1.5 sole owner of Minimap.lua in M1 |
| luacheck.py shared by M0.2 / M0.7 | M0.7 writes tools/lint_div.py |
| Telemetry files shared by M0.3 / 0.4 / 0.5 | M0.4 owns Telemetry.lua + both docs; M0.5 writes `Bench.result`; M0.3 hands keys |
| TOC, files.txt, FORMATS, spike-bugs, test_spike_bugs hot | Manifests + generated TOC, per-file FORMATS, one replay per file, lead edits evidence docs at gates |
| gen_world.py shared by M1.1 / M1.2 | M1.1 uses new gen_labels.py |
| you.uiMap needed in M1 | M1.10 You part |
| Zone info needs explored + places | Explored/landmark lines and their test moved to M4.4 |
| Corpse-forced follow before corpse exists | Moved to M3.3 |
| K2 taint unchecked | Sim combat log (M0.6), combat script steps, `taint` events (M0.4), exit criteria M1/M3/M4/M5 |
| L5 new files need restart | install.py warning (M6.1 and kept from M1 install), kit note (M0.4) |
| G2 no replay | R-G2 in M3.4 |
| Atlases may vanish silently | `/mma check art` + ui/Art.lua (M0.5) |
| Spike root keys + MagicMapLandmarks | D9, ADR 0007, spike-DB fixture test (M6.1) |
| Data regen + Interface bump at release | M6.3 |
| No-data build untested | M5.2 CI scenario; Atlas empty indexes in M1.2; M2 exit checks it early |
| No parity checklist | M0.8 docs/parity.md |
| No shot protocol | M0.4 shot list + stamped `/mma shot`; M0.8 reference session |
| Missing features (`/mma follow`, `/mma icon`, `!`/`?`, tint no-data, instance maps, arrow hiding, subzone re-place, title debug, area/zone click precedence) | M1.7, M1.6, M4.3/4.4, M1.4, M3.4, M1.4/M4.2, M1.4, M4.6, M3.4 |
| Gear dead end M1–M3 | M1.7 minimal gear; M2/M3 add their layers |
| Tooltip owners before G7 | One hide path in M1.6, R-G7 at M1 gate |
| M0.1 re-adds existing fields | M0.1 is a diff; most fields confirmed present (checked against types/) |
| Cap 300 under LOCKED clause | D6; ADR 0004 amendment in M4.3 only if 300 |
| Structure docs unassigned | M0.2 updates structure.md + architecture.md; M6.3 rewrites README from parity.md |
| Synth plan said "8 failing budgets" | Corrected: 4 FAIL today; every gate needs 8/8 PASS |

# Development

The developer manual behind the [README](../README.md)'s "How it works".


The rebuild's design is in [architecture.md](../architecture.md); the addon (the repo root is the
addon root, `MagicMap.toc`), its folders, load order and the Runtime contract are in
[structure.md](structure.md). **Atlas** (`atlas/`) is the library of facts that hold
(tiles, labels, walk grid, uiMaps, areas, places, interiors and the capitals' buildings,
NPCs / objects / items / quests, coordinates and camera maths), from data the offline tools generate (`Data/`, see
[atlas-data.md](atlas-data.md)).

## Setup

    python3 -m venv .venv && .venv/bin/pip install -r tools/requirements-dev.txt

## Regenerate data

Each generator reads a local install (see its docstring for options) and states the build
in its output's header. Run them in this order: gen_tilecolor and gen_interiors read Data/Tiles.lua (gen_base too, with TileColor, Areas and AreaGrid, so it runs after them), gen_questie
reads Data/UiMaps.lua from gen_world and gen_world's ItemIcons reads gen_questie's
Data/Items.lua (the data diet), so gen_world runs again after it; gen_labels reads Anchors,
Places, Areas, UiMaps, Tiles and Walk, so it runs last. The rest are independent. gen_questie's
five files (Npcs, Objects, Items, Quests, BlipServices) come from QuestieDB and Questie, used under
their GPLv3 terms (NOTICE.md); they're committed like the rest.

    W="/Applications/World of Warcraft"
    .venv/bin/python tools/gen_tiles.py     local "$W" wowf -o Data/Tiles.lua
    .venv/bin/python tools/gen_tilecolor.py local "$W" wowf -o Data/TileColor.lua
    .venv/bin/python tools/gen_anchors.py   local "$W" wowf -o Data/Anchors.lua
    .venv/bin/python tools/gen_walk.py      local "$W" wowf -o Data/Walk.lua
    .venv/bin/python tools/gen_areagrid.py  local "$W" wowf -o Data/AreaGrid.lua
    .venv/bin/python tools/gen_world.py     local "$W" wowf -o Data   # UiMaps, Areas, Places, ItemIcons
    .venv/bin/python tools/gen_questie.py "$W/_forever_/Interface/AddOns/QuestieDB"
    .venv/bin/python tools/gen_world.py     local "$W" wowf -o Data   # again: ItemIcons for the items kept
    .venv/bin/python tools/gen_labels.py    -o Data/Labels.lua
    .venv/bin/python tools/gen_interiors.py local "$W" wowf -o Data/Interiors.lua   # reads Data/Tiles.lua's maps
    .venv/bin/python tools/gen_base.py      local "$W" wowf   # Textures/Base*.blp and Data/Base.lua; reads Tiles, TileColor, Areas, AreaGrid (--preview DIR: PNGs)
    .venv/bin/python tools/gen_sea.py       local "$W" wowf   # Textures/Sea*.tga and Data/Sea.lua, from the terrain (--bake demo/sea: the demo's)

The map art repairs aren't regenerated with the rest: a new run gives new pictures, and each costs money
(OpenAI's image edits; the key is `OPENAI_API_KEY` or the repo's `.env`). `tools/ai_regions.json` holds the
places and which candidate was picked; `tools/ai_fix.py` makes candidates for one place, under `demo/aifix/`
(gitignored); `tools/ai_map.py` runs it for the listed places and bakes the picks. After a game patch that
changes tiles under a place, repaint it or the setting's build check keeps the patches off. See
[ai-map-art.md](ai-map-art.md).

The demo's assets, after the above: [demo/README.md](../demo/README.md).

## Install and try it in game

    .venv/bin/python tools/install.py      # into _forever_ (WoW Forever); another flavor folder as argument

It writes the TOC from the folders' `files.txt` (`--toc`: only that), then copies the TOC, its
files and Textures/ into `Interface/AddOns/MagicMap`. That is 1.0's folder too: while 1.0 is there it stops,
and `--replace-spike` moves 1.0 to `MagicMap.spike-backup` first (its saved data isn't
read: docs/decisions/0007-v2-storage-names.md). Log in (it says when files are new to the client:
restart it, not `/reload`), then:

- `/mm help` lists the commands. On a fresh install nothing of Blizzard's is touched until the welcome
  (ui/Welcome.lua) is answered: click the minimap button (or `/mm`) and pick what MagicMap replaces. After that,
  with the minimap replaced the map sits on the Minimap's spot from login (`/mm` or the minimap button hides and
  shows it, M grows it into the big map, `/mm reset` puts it back); the settings are the gear's Settings, `/mm feel`,
  or Game menu -> Options -> AddOns -> MagicMap
- with the map shown, Blizzard's Minimap becomes an unseen sensor and its blips (mailboxes,
  herbs, services) are drawn on the map; `/mm minimap blizzard` gives it back, `/mm layer <name>`
  toggles a layer, `/mm record on|off` keeps the observations for Model replay tests
  (flow: docs/structure.md "One flow end to end")
- `/mm perf load`: Atlas's load cost (ms, KB) and time per step / event / timer / job
- `/mm errors`: errors caught so far (each is also printed once when it happens)

Trying the welcome: `/mm welcome` shows it again any time (Escape or the close button saves nothing). To see it
as a new player does, quit the game, delete the `MagicMap2DB` table from
`WTF/Account/<account>/SavedVariables/MagicMap.lua` (or that file), log in and click the minimap button.
An existing 2.0 save migrates instead, both replaced and no welcome (ui/Replace.lua `Load`). In the sim,
`sim.boot(saved="MagicMap2DB = nil")` is a fresh start (tools/tests/test_replace.py).

## Release

Set `## Version:` in `MagicMap.toc` (D7: 2.x.x), run every generator on the installed client (above;
the QuestieDB-derived five too) and `tools/check.sh`, commit, tag `v<version>`, then

    tools/package.sh v2.1.0   # dist/MagicMap-v2.1.0.zip

One zip of the committed tree, with LICENSE and NOTICE.md; it's unzipped into a scratch AddOns folder
and loaded in the sim from there (every TOC file present; 0 errors) or isn't written. It goes on the
GitHub release, with its notes: [dist/RELEASE_NOTES-v2.1.0.md](../dist/RELEASE_NOTES-v2.1.0.md) (2.0's:
[dist/RELEASE_NOTES-v2.0.0.md](../dist/RELEASE_NOTES-v2.0.0.md); a listing draft for other channels:
[dist/listing-v2.1.0.md](../dist/listing-v2.1.0.md); what to try in game first: [playtest-2.1.md](playtest-2.1.md)). How 2.0 replaced 1.x's tree in this repo:
[release/merge-plan.md](release/merge-plan.md) (option A).

## Telemetry

Play, `/reload`, then read what the addon saved (sessions, errors with stacks, marks with
state and trace, screenshots matched to `/mm shot`, the validation log, client `Logs/` lines
that mention the addon, and other addons' errors while ours was loaded). The contract is [telemetry.md](telemetry.md).

    .venv/bin/python tools/telemetry.py                  # everything, newest first
    .venv/bin/python tools/telemetry.py --errors --full  # one section: --errors --marks --shots --validation --logs
    .venv/bin/python tools/telemetry.py --since 30 --json   # last 30 minutes (or an ISO time), as JSON

Options: `--wow` (or `MAGICMAP_WOW`), `--flavor` (default `_forever_`), `--sv <file>`, `--trace N`.

## Test and lint

The tests include a headless smoke test: the TOC's files loaded in order on a simulated WoW
Forever client (`tools/tests/wowsim.lua`), logged in, ~60 frames and every `/mm` command,
with no Lua error expected; `tools/luacheck.py` over the TOC (globals, every file listed,
the TOC = what the folders' `files.txt` make: `tools/install.py --toc` writes it); and
`tools/lint_div.py`, no `/` that may divide by 0 (docs/structure.md "Rules"). luacheck runs as a
test (test_luacheck).

    tools/check.sh                                     # all three, as CI runs them (makes .venv if missing): before committing
    tools/check.sh --quick -k zoom                     # lint_div + the plain pass alone, pytest arguments passed on: while iterating
    PYTEST_XDIST_AUTO_NUM_WORKERS=4 tools/check.sh     # 4 workers in all (default: the CPUs), for several checks at once
    MM_CLOCK_SCALE=4 tools/check.sh                    # the sim's real clock 4x slow: the tests (counted clock) don't notice
    .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider
    .venv/bin/python tools/luacheck.py                 # the TOC's files: globals, TOC, boundaries
    .venv/bin/python tools/lint_div.py                 # each / by a literal, a constant or a reason

`check.sh` runs the tests twice side by side (plain, and `MM_STRICT=1`), each spread over half the
CPUs by pytest-xdist, so every test boots its own Lua and writes only under its `tmp_path`
(`UPDATE_GOLDEN=1`: one pass after the other, the goldens rewritten by the first). `--quick -k X`
runs in one process (a few tests: workers cost more than they save); `--quick -n0 -s` shows the
tests' prints.

`tools/sim.py` drives the same simulated client (the tests boot through it) from Python or the
shell: `s = sim.boot(priced=True)`, then `s.blips([("Mailbox", 40, 20)])` (yards east and north of
where you log in), `s.slash("/mm toggle")`, `s.run(6)` (past login's 5 s grace: a grace's frames
aren't in perf's byState), `s.wheel(3)`, `s.drag(200, 0, 20)`, `s.walk(10, "east")`, `s.press("M")`,
`s.lua(code)` (sim and ns are locals), and read back
`s.perf()` (FrameStats: byState, alloc, ledger; per-name calls), `s.errors()`, `s.layers()`,
`s.pins()` (what's drawn: every pin and pill shown, T.Drawn; `pins` in a script);
`s.T` is the replays' harness (tools/tests/harness.lua: `sim.checked()` boots through its T.Boot, T.Invariants
after every frame, and `T.strictPins = True` adds one pin per real thing across layers). From the shell, a script:

    .venv/bin/python tools/sim.py --priced --run 'blip Mailbox 40 20; slash /mm toggle; run 6; wheel 3; run 2; perf; layers'
    .venv/bin/python tools/sim.py --run 'run 1; lua local cam = ns.UI.Camera.cam
    return cam.zoom, cam.cx'                          # lua: the rest of the script, lines and ';' as is
    .venv/bin/python tools/sim.py --help              # the commands

CI (`.github/workflows/check.yml`) runs `tools/check.sh` on every push and PR.

## How to add a setting

A setting is declared once, in the file that uses it; the settings window (ui/Feel.lua) is built from what's
declared, so a declared setting is in the window, resettable and saved, with nothing else to change:

    UI.Feel.Add("map", "Names", {   -- its page's key and section (nil: above the page's sections)
        { key = "labels.alpha", kind = "slider", label = "Zone name opacity", min = 0.3, max = 1, step = 0.05,
          pct = true, default = ZONE[4], apply = SetAlpha, tip = "How solid the zone names are." },
    })

- **key**: `<area>.<name>`, the name it's saved by in `UI.saved.feel` (only while it differs from its default).
  Never rename one: players' values are under it.
- **default**: today's value, taken from the constant the code already has (one copy). A function is read when
  asked: a value inherited from another setting (until it's set, its row and its `apply` follow that one).
- **kind**: `toggle`; `slider` (`min`, `max`, `step`, the default on its step; shown as `pct`, `of`, or `fmt`);
  `select` (`options = { { label, value, icon? } }`, or a function giving them); `color` (`colors = { { name,
  { r, g, b } } }`; a custom `"#rrggbb"` through the client's colour picker; `Feel.RGB` reads either); `list`
  (`options`, `ordered`; the value the chosen joined by commas: `Feel.List`); `button` (`run`).
- **How the code gets it**: `apply(v)` (called on a change and as the map shows), or `Feel.Get(key)` where it's
  used, with `Feel.rev` to notice a change. A value its owner keeps elsewhere: `get`/`set` (and `keep = true` for a
  switch a reset mustn't touch).
- **when**: a key or a function; the row shows only while it's on.
- **A page of its own**: `UI.Feel.Page({ key, title, icon, order, tip, sections })`, its order between the others'
  (General 10, Map 20, Title 25, Icons 30, Resources 35, Info pills 40, Tracking line 50, Quest areas 60, Grouping 70, Diagnostics 90).

Then list it in ui/Feel.lua's header (its page's line) and docs/features.md's settings table. test_lookfeel's
`test_settings_declared` fails if the code reads a key by name that isn't declared, or a declared one lacks a page,
label, tip or default its control offers; `test_settings_layout` if a row doesn't fit its page.

## Boundaries

`tools/luacheck.py` enforces [architecture.md](../architecture.md)'s Rules per folder: the
globals each may read (`BOUNDARIES`: sections of `tools/lua51_globals.txt` and
`tools/wow_globals.txt`) and the `ns.<System>`s it may use (`NS_RULES`, a static scan).
Also: `Runtime.On` only in game/ (Game registers game events) and `UI.View` only in
game/Apply.lua (`ONLY`); only a system's own folder sets its fields, but for the hooks it
declares (`HOOKS`: Runtime's `onError`, `onTrace`); named frames only from `FRAME_NAMES`.

| folder   | globals                                       | ns                                         |
|----------|-----------------------------------------------|--------------------------------------------|
| atlas/   | Lua 5.1 only                                  | Atlas, Data (its generated `ns.Data`)      |
| runtime/ | Lua 5.1 + `[lua]` `[runtime]`: frame, clocks | Runtime                                    |
| model/   | Lua 5.1 only                                  | Model, Atlas, Runtime                      |
| ui/      | Lua 5.1 + `[lua]` `[ui]`: widgets, input     | UI, Atlas, Runtime; Model's read API (`Known`, `Target`, `Route`, `you`, `hooked`, `Focus`); `Game.Command` (slash and saved data too) |
| game/    | all of it, and only it the SavedVariables     | Game, Atlas, Runtime; `UI.View` (game/Apply.lua), `Model.Observe` / `Load` / `SAVED` |
| game/parts/, game/commands/ | as game/                     | Game, Atlas, Runtime (no View, no Model: Observe and Apply have those) |

Known violations waiting on a contract are `BASELINE` in `tools/luacheck.py` (each with
its TODO); the check fails once one is gone, so the list only shrinks.

## Demo

Atlas on its own in a browser (the hosted one: https://magic-map-outdoor.exe.xyz): the server runs Atlas in Lua (lupa) over its
bundled data and serves its answers as JSON; `demo/index.html` only draws them, Kalimdor, the Eastern Kingdoms and Zephras Isle
as one map. Its assets, how they're baked and how it's deployed: [demo/README.md](../demo/README.md).

    .venv/bin/python demo/server.py        # http://localhost:8000 (optional port argument)


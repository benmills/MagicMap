# MagicMap: notes for agents

A minimap and world map addon for WoW Forever (client 1.60.1, `_forever_`). The addon is Lua 5.1 under `atlas/`
(data library), `model/`, `runtime/`, `game/`, `ui/`, with generated `Data/` and `Textures/`; the tooling, the sim
and the tests are Python under `tools/`; `demo/` is the web demo. Start with README.md, architecture.md and
docs/structure.md (the systems and their contracts). Feature behaviour: docs/features.md. The route search:
docs/walk.md. Data formats: docs/atlas-data.md. Frame budgets: docs/runtime.md.

## Rules
- Lua 5.1 (no `goto`). Every `/` in addon code carries a `-- /: never 0 (why)` comment
  on its line (tools/lint_div.py; WoW raises on x/0).
- The folders' boundaries are enforced by tools/luacheck.py (`NS_RULES`): UI reads Model only through the listed
  fields; only a system's own folder sets its fields.
- Never commit Blizzard art or game data dumps beyond the generated `Data/` files: extracted art, footage and caches
  (promo/, demo/tiles, the walk terrain cache) stay gitignored.
- Tests stay light: high-level sim scenarios; unit tests only where nothing else catches it. Measure before tuning
  (tools/walk_smooth.py, walk_scorecard.py for the route; `/mm perf` and tools/telemetry.py in game).
- Comments say what a value means and why a choice was made (often a client behaviour). No history, milestone ids
  or citations of old files.
- Commit to main and push; ask before tagging or releasing.

## Commands
    tools/check.sh                      # lint_div, maplint's ratchet, every test twice (plain and MM_STRICT=1)
    tools/check.sh --quick -k path      # a few tests
    .venv/bin/python tools/install.py   # into the installed client's AddOns: /reload, or restart for new files
    .venv/bin/python tools/telemetry.py # what the addon saved in game (after /reload)
    tools/package.sh v<version>         # the release zip (docs/development.md "Release")

Generators run against the installed client (docs/development.md); a new game build means re-running them and
checking the map art (`tools/ai_map.py check`).

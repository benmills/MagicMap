# MagicMap architecture

Three systems: Game, Model, UI. Two libraries under them: Atlas and Runtime.

- Game: everything outside
- Model: what we know
- UI: what you see and do
- Atlas: facts that hold
- Runtime: when things run

## Rules

- Only Game reads or changes game state or other addons. Anyone may make widgets.
  One exception, decided at M2 (docs/brief.md §7): UI draws your quests' objective areas with the
  client's own art on QuestPOIFrames of its own and hit-tests them for hover and click (the spike's
  blob art, Layers.lua:765-1069), the one game read UI makes, through a widget. Only ui/Areas.lua and
  Game's sensor (game/Oracles.lua) make one (luacheck's `POI_FILES`).
- Anyone may read Atlas and use Runtime. Neither reads a system.
- Model is plain Lua. It sees only what it is handed: observations and oracles from Game, focus from UI.
- UI reads Model, owns View, and sends commands to Game. UI's drawing reads only Model and View, never input.
- Game reads only View from UI.
- Saved data belongs to the system that owns it. Game only loads and saves it.

## Each frame

    Input    UI turns input into commands; Game carries them out
    Observe  Game reads, so this frame sees the commands' effects
    Model    merge, target, route slice
    UI       camera, View, draw
    Apply    Game acts on View: Minimap mode, tracking, addon pins;
             and carries out the commands a ui step sent (their effect shows in the next Observation)

Each step is isolated: one failing doesn't stop the rest.
Drawing runs while shown. Input, learning and saving always run.
The blip sensor reads where the last Apply placed the Minimap, and waits until that placement holds still.

## Systems

**Game**
  reads   location · quest log · places · group · corpse · waypoint · vignettes
          · offers · exploration · tracking state
  senses  Minimap blips · quest areas (Inside(quest, col, row)) · Minimap indoors
  adapts  HBD world + minimap pins
  owns    Minimap takeover (undo list) · hooks (M, Escape, GameTooltip's hide path)
          · minimap button · SavedVariables load/save
  takes   commands: Follow, Waypoint, Way, Tracking · View

**Model**
  holds   per continent: you · quests · places · blips · services
          · rares + seen blips (saved)
  gives   Known(kind) · Target · Route
  decides dedup and merge · what to forget
  takes   observations · oracles · focus (the map shown)

**UI**
  holds   frame & chrome · layout + toggles (saved)
  owns    View: camera · focus · shown layers
          · sockets for other addons' pins
  input   clicks → hits (pin, area, zone) → commands · camera, follow, idle return
          · small ⇄ big
  draws   tiles · borders · labels · quest areas (the client's art: the exception above) · interiors (the building's indoor minimap pictures, ADR 0008)
          · pins (one store, diffed by id) · group · addon pins · path · arrows
  shows   title · tooltips (its own small fonts put back on GameTooltip's hide) · inspector · menus & settings

**Atlas** (library)
  holds   tiles · tile colour · sea · zone borders, outlines + label anchors · walk grid
          · uiMaps · areas + area grid · flight points + paths · POIs · dungeons
          · NPCs · objects · items · quests (Data/, generated; see docs/atlas-data.md)
  gives   coordinates · map rects · zone at point · zone levels · ranked map labels
          · spawns in a box · name search · quest sources · camera maths · walk cells + moves

**Runtime** (library)
  frame steps · slices and budgets · timers · events · perf (/mm perf)
  wraps every callback for timing and isolation

## Registries

A shared file takes additions by registration, so a new piece is a new file:
`Game.Part` (a part of the observation, game/parts/), `Game.Handle` (a command kind,
game/commands/), `Game.Apply` (an apply step acting on View), `Model.Part` and `Model.Kind`
(a kind Model knows, model/), `Engine.Layer` (a map layer, ui/). Each folder lists its files in `files.txt`; the TOC is made from them.
docs/structure.md "Registries" has the calls.

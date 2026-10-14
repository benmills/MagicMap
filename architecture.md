# MagicMap architecture

Three systems: Game, Model, UI. Two libraries under them: Atlas and Runtime.

- Game: everything outside
- Model: what we know
- UI: what you see and do
- Atlas: facts that hold
- Runtime: when things run

## Rules

- Only Game reads or changes game state or other addons. Anyone may make widgets.
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
    Apply    Game acts on View: Minimap mode, tracking, addon pins

Each step is isolated: one failing doesn't stop the rest.
Drawing runs while shown. Input, learning and saving always run.
The blip sensor reads where the last Apply placed the Minimap, and waits until that placement holds still.

## Systems

**Game**
  reads   location · quest log · places · group · corpse · waypoint · vignettes
          · offers · exploration · portraits · tracking state
  senses  Minimap blips · quest areas (Inside(quest, col, row)) · Minimap indoors
  adapts  QuestieDB (one adapter, contract-checked) · HBD world + minimap pins
  owns    Minimap takeover (undo list) · hooks (M, Escape, GameTooltip)
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
  owns    View: camera · focus · shown layers · renderer (ours | ours + art | Blizzard)
          · sockets for other addons' pins
  input   clicks → hits (pin, area, zone) → commands · camera, follow, idle return
          · small ⇄ big
  draws   tiles · borders · labels · shade · quest areas · indoor art
          · pins (one store, diffed by id) · group · addon pins · path · arrows
  shows   title · tooltips · inspector · menus & settings

**Atlas** (library)
  holds   tiles · tile colour + water · borders · walk grid · map catalogue
  gives   coordinates · map rects · zone at point · camera maths · walk cells
  login   map scan, through readers Game hands it

**Runtime** (library)
  frame steps · slices and budgets · timers · events · perf (/mm perf)
  wraps every callback for timing and isolation
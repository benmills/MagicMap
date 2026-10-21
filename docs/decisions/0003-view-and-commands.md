# 0003 View (UI → Game, read in Apply) and Commands (UI → Game, in Input; a ui step's in Apply)

Status: accepted (v1). Types: [types/view.lua](../../types/view.lua).

## Context

Only Game may change game state, but much of that state follows what the user sees.
Whether the Minimap is ours, whether it is a hidden sensor or drawn whole indoors, where
it must sit so the blip sensor reads under our window, which Blizzard tracking to turn off
because our layer draws the same thing, and which other addons' pins to borrow onto which
canvas all depend on UI. In the spike every file reached into every other. Some user
actions are game actions too: follow a quest, set or clear the waypoint, open a `/way`
line, toggle tracking, or show a unit's tooltip. Keys Blizzard owns (M, Escape) reach us
only through Game's hooks.

## Decision

**View** is a table UI owns and publishes with `UI.View()`. Game reads it only in its
apply step and never writes it. It holds only what Game acts on:

- `minimap` is `"blizzard"` (Game releases everything) or `"ours"`.
- `renderer` is `"ours"`, `"ours+art"` or `"blizzard"` (the whole Minimap in the window, with no sensor).
  Removed by ADR 0008 (below).
- `inst` is the map shown, which scopes Game's per-map reads.
- `window` holds `shown`, `big`, `place` (screen rect), `still`, `strata`, `level` and `homeAlpha`.
  The sensor waits for `still`, and Escape is caught while `big`.
- `layers` lists shown layers Game acts on: `blips`, `flight`/`quests`/`pois` (which turn off
  Blizzard's duplicate tracking), and `addon:<key>`.
- `sockets.world` and `sockets.minimap` are frames UI owns, on which Game places other
  addons' pins. Game never moves, sizes or hides them.
- `button` controls whether the minimap button is shown.
- `diag` is optional. Game calls it only for telemetry marks and stores the result without acting on it.
- `camera` is optional: where the map looks, which Game copies in its apply step for telemetry's
  motion ring and shot stamps, without acting on it.

`diag` and `camera` are the exception to "only what Game acts on": they are sampled for
telemetry, never acted on, and their shapes are UI's (OPEN), so Game never depends on UI's
internals through them.

View is **versioned** (`v = 1`). Game acts only on a `v` it knows. Otherwise it falls back
to a safe View: Blizzard's minimap, nothing borrowed, tracking restored. Adding an optional
field does not bump `v`. Renaming, removing or changing a meaning does.

**Commands**: `Game.Command(cmd)` may be called from anywhere. Game queues each one and
carries the queue out in order in its input step: the same frame for a click, and at most
one frame later from a step. The kinds are `follow {quest|false}`,
`waypoint {pos|false}`, `way {pos}`, `tracking {id, on}` and
`tooltip {owner|false, member, npc}` (Game draws an NPC's portrait into the tooltip itself:
no WoW object crosses into Model, ADR 0001). Added since (open: new kinds): `slash {name,
help, fn}` (Game owns `/mm`; UI's commands register through it) and `load {owner, fn, spec}`
(Game.Load on UI's behalf, ADR 0004). Each names the result wanted, so a repeat does nothing
new. There is no reply: the effect shows in the same frame's Observation. A command that
fails is reported and dropped.

**Hooked input** (`"worldmap"` for M while shown, `"escape"` while big) goes Game →
`obs.hooked` → `Model.hooked` → UI, within the same frame.

Locked: `UI.View()`, its fields and meanings, `v` and the fallback, `Game.Command` and the
five kinds with their idempotence, and the hooked kinds. Open: new optional fields, new
command and hooked kinds, and everything inside UI (camera, layout, menus, chrome).

## Consequences

- UI is not fully self-contained: View is a cross-system contract, so its fields change
  only with a version bump. This is the price of Game alone touching the Minimap.
- Game can be tested by feeding it Views, and UI by recording the commands it sends.
- The takeover's undo list (the spike's MinimapTakeover) stays inside Game. View only says
  what is wanted, never how.
- Telemetry reads UI only through `diag` and `camera` (lifting luacheck's
  `game/Telemetry.lua → UI.Map` baseline entry), whose shapes stay UI's.
- OPEN additions (v1 plan M0.1, `v` stays 1): `chrome` {rimArrows?, questRing?} for Blizzard's Minimap rim parts; `camera` {cx, cy, zoom, w, h}, sampled for telemetry's motion ring, never acted on.
- OPEN addition (v1 plan M1.6): hooked kind `"toggle"`, Game's minimap button or the addon
  compartment clicked; UI shows or hides the map as `/mm toggle` does. Not a key, but the same
  path: only Game may make that button, and UI hears of it only through Model.
- OPEN addition (v1 plan M2.2): CmdTooltip `line`, so one quest tooltip can have up to 3
  portraits an objective, each on its own line (the spike's `shown[line] = npcID`); Game finds
  the line by index and rewrites only its icon. An `npc` comes with its `line`.
- Clarification (v1 plan M2, its review's round 1; the kinds and their idempotence unchanged):
  Game carries the queue out in its apply step too, after UI's steps, so a command a ui step sends
  is carried out that frame, not the next frame's input (the promise was "at most one frame later").
  A quest tooltip is built in a ui step, so its portraits now show the frame it does, as the
  spike's built them with the tooltip (QuestInfo.lua:187, 365-368); a met mob's sword showed a frame.
- OPEN addition (v1 plan M4.5, M4.6): command kind `"run"` { line }, `/mm <line>` as if typed
  (game/commands/run.lua: Game.Run), for the gear's Advanced rows (GearMenu.lua:28). The one kind that
  isn't idempotent: each one runs the line once, as a click on the spike's row did.
- Change (ADR 0008, interiors): `renderer` removed. UI draws the indoor pictures itself and Game had
  already stopped reading the field, so nothing acts on it and `v` stays 1.

## Revisit if

- Game needs to act on something UI decides that is not in View (e.g. hiding Blizzard's
  world map in other cases). Add an optional field.
- A command needs an answer before the next Observation (e.g. "could the waypoint be
  set?"). Prefer an Observation field over adding replies.
- The hooked-input detour through Model proves awkward. Then a direct, typed
  Game → UI input queue would be the change, and it would need an architecture.md rule change.

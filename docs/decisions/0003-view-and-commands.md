# 0003 View (UI → Game, read in Apply) and Commands (UI → Game, in Input)

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
- `inst` is the map shown, which scopes Game's per-map reads.
- `window` holds `shown`, `big`, `place` (screen rect), `still`, `strata`, `level` and `homeAlpha`.
  The sensor waits for `still`, and Escape is caught while `big`.
- `layers` lists shown layers Game acts on: `blips`, `flight`/`quests`/`pois` (which turn off
  Blizzard's duplicate tracking), and `addon:<key>`.
- `sockets.world` and `sockets.minimap` are frames UI owns, on which Game places other
  addons' pins. Game never moves, sizes or hides them.
- `button` controls whether the minimap button is shown.
- `diag` is optional. Game calls it only for telemetry marks and stores the result without acting on it.

View is **versioned** (`v = 1`). Game acts only on a `v` it knows. Otherwise it falls back
to a safe View: Blizzard's minimap, nothing borrowed, tracking restored. Adding an optional
field does not bump `v`. Renaming, removing or changing a meaning does.

**Commands**: `Game.Command(cmd)` may be called from anywhere. Game queues each one and
carries the queue out in order in its input step: the same frame for a click, and at most
one frame later from a step. The kinds are `follow {quest|false}`,
`waypoint {pos|false}`, `way {pos}`, `tracking {id, on}` and
`tooltip {owner|false, member, npc}` (Game draws an NPC's portrait into the tooltip itself:
no WoW object crosses into Model, ADR 0001). Added since (open: new kinds): `slash {name,
help, fn}` (Game owns `/mma`; UI's commands register through it) and `load {owner, fn, spec}`
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
- `diag` keeps telemetry's camera and layout snapshot out of the contract (lifting
  luacheck's `game/Telemetry.lua → UI.Map` baseline entry) without Game reading UI internals.

## Revisit if

- Game needs to act on something UI decides that is not in View (e.g. hiding Blizzard's
  world map in other cases). Add an optional field.
- A command needs an answer before the next Observation (e.g. "could the waypoint be
  set?"). Prefer an Observation field over adding replies.
- The hooked-input detour through Model proves awkward. Then a direct, typed
  Game → UI input queue would be the change, and it would need an architecture.md rule change.

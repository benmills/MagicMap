# 0006 Model's read API (UI → Model)

Status: accepted (v1). Types: [types/model.lua](../../types/model.lua).

## Context

UI reads only Model and View (architecture.md). Model's two entry points (Observe, Focus)
were locked in ADR 0001/0002, but what UI reads back wasn't. Every pin kind we'll add
(blips, rares, services, quests, offers, places, group) would otherwise grow its own getter,
and each new kind would touch the contract. Model also needs its saved part (ADR 0004)
without reading the SavedVariables or calling Game.

## Decision

- **`Model.Known(kind) → list, rev`**: one shape for every kind, `MM.Known { key, kind, pos,
  name, icon?, live, t?, text? }`. The list is the same table until it changes; `rev` goes
  up when it does, so a UI layer redraws on a rev change and costs nothing otherwise.
  An unknown kind gives `{}, 0`. Adding a kind means a Model file that fills it and a UI
  layer that draws it (and Atlas data if it is static): no change to this contract.
- **`Model.you`** (last known position, `stale`), **`Model.hooked`** (this frame's hooked
  keys, handed on from `obs.hooked`, ADR 0003), **`Model.Target()`**, **`Model.Route()`**.
  Target and Route are typed with the fields we're sure of; their full shapes stay open
  until they're built.
- **`Model.Load(saved)` and `Model.SAVED`**: Game calls
  `Game.Load("Model", Model.Load, Model.SAVED)`. Model keeps the table and changes it in
  place; Game's luacheck rule allows `Model.Observe`, `Model.Load`, `Model.SAVED`.
- Model has no clock: saved times come from `obs.epoch` (ADR 0001).

Locked: the calls and fields above and their meanings. Open: kinds, new optional fields,
Target and Route beyond the typed fields.

## Consequences

- UI draws any kind with the same pin code; a kind's look is `icon` or the layer's default.
- `live` lets UI tell sensed-now from remembered (greyed, or only past some zoom).
- Model's internals (merge state, indexes) can change freely.
- A kind may be scoped to Focus's instance (rares: built from Atlas on demand, in a
  budgeted job). Found adding the first such kind; the shape didn't change.
- Proven: adding rares touched atlas/, model/, ui/ and the TOC only.
- OPEN additions (v1 plan M0.1): Target `inside?`, `title?`, `quest?`; Route still `MM.Pos[]` with `straight?`, `partial?` on the array; typed kinds quests, offers, places, group, corpse, waypoint, vignettes, services (MM.Known plus optional fields).
- OPEN additions (v1 plan M1): `Model.you` gains this frame's `uiMap`, `level`, `faction`,
  `dead`, `ghost`, `combat` (M1.10; the title and the big map's zone fit read `uiMap`).
  `Model.minimap` hands on this frame's `obs.minimap` unchanged, as `hooked` is (M1.7 places
  the small window on `home` in `homeStrata`; it stands for M1.6's asked-for `Model.home` and
  `Model.homeStrata`, and carries `indoors` for M4.4's renderer). `Model.addons` hands on
  `obs.addons`, `{}` until known (M1.9, for the "Other addons" layers).

## Revisit if

- A kind needs data that doesn't fit a pin (an area, a path): give it its own getter
  rather than stretching `MM.Known`.
- Lists get large enough that UI wants only a rect: add an optional `Known(kind, rect)`.

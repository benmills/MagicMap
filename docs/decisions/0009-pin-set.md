# 0009 One thing, one pin (the pin set)

Status: **proposed** (hardening pass, 2026-10-27). Ledger rows P1-P8, T1, T7 (docs/hardening-plan.md).

## Context

The 2.0 plan wanted one system responsible for pins. What was built is one *renderer* (ui/Pins.lua's
`Pins.Layer`: one style, hover, tooltip and click path, pins diffed by key), but seven pin layers, each with
its own fill, rev and pair of canvases. Nothing owns "which things exist and which one pin each gets".
Instead, about eight rules in five files try to keep doubles apart:

- sensor vs model distances (6 yd, then 10/18 yd);
- blips under "our" pins dropped in Model (8 yd, by UI's layer names through Focus.off);
- remembered blips and services hidden within a fixed 220 yd of you (`Away`);
- `carried` keys;
- `Track.Covers`;
- rares hidden under vignettes;
- grouping hiding members by table identity, regrouping on its own 0.5 s clock.

Seen in game: duplicate pins (P1, reproduced: a pill and its members drawn together for 0.4 s after each blip
update) and pins vanishing as you walk close (P2: the 220 yd rule against a sensor that sees ~208 yd outdoors,
~131 indoors).

## Decision

Split the job in two, each done once:

**1. Model matches: what is the same thing.** A new Model part (model/Things.lua) reads every pin kind's
`Known` list and groups entries that are one real thing. It hands UI `Model.Known("things")`:

    MM.Thing { key, pos, name, members = { MM.Known... } }   -- members best first (the precedence below)

- **One rule for "same thing".** The same name within `SAME` yards (one constant: 10, +8 for a reading taken
  on the move). Or a *role* match: a quest-giver blip within `SAME` of an offer of that NPC, a turn-in blip
  of a quest ready to hand in. Different things at one spot stay apart: a herb by a quest's objective centre
  draws (fixes P3).
- **A stable key.** A thing keeps its key while any member stays: the key of its most durable member (place,
  quest, offer, service, remembered, then live). A live blip coming or going never changes it. Entries are
  matched by key, never by table (fixes P1's root).
- **Coverage, not distance.** A remembered member draws until a live one replaces it or a sweep forgets it
  (Model's existing forget, which knows the sensor's real reach). There is no 220 yd rule, so there's no gap
  (fixes P2, P5).
- **Distinct keys per kind**: `quest:<id>` and `offer:<id>` no longer collide (fixes P6).

**2. UI picks and draws: one layer.** ui/Pins.lua becomes one Engine pin layer drawing `Known("things")`.
Each kind registers a spec instead of a layer:

    Pins.Kind{ kind, toggle (the gear's key), level (draw order), minZoom?, look(e), lines/tooltip, hover?, click? }

For each thing, a layout draws its **first member whose kind is toggled on and whose zoom gate passes**. If the
best member is hidden, the next one draws instead. A thing that's tracked or followed wears the ring at any
zoom.

**Precedence, best first:**
1. tracked / followed;
2. quest, then offer;
3. live vignette;
4. live blip;
5. flight point / dungeon / other places;
6. service;
7. rare;
8. remembered blip;
9. corpse / waypoint: these merge into the thing they stand on, so a tracked icon's waypoint is the icon.

Draw order within the layer is by `level`, as the separate layers' levels were.

Grouping (ui/Cluster.lua) runs inside the same layout, on the picked list, keyed by thing key. So the pills
and the pins are always the same membership, in one canvas swap (fixes P1 and P7). Hover's hit test walks
one pool.

Focus.off no longer reaches blips (fixes P8); Target keeps reading it as today.

**Out of scope:** other addons' borrowed pins (game/AddonPins.lua) keep their own Questie turn-in rule. Areas,
labels and borders are not pins.

## Migration

1. `model/Things.lua` beside the existing kinds; `Known` lists unchanged (Target, tooltips, Areas still read
   them). The sim's strict pins invariant (T1) runs against things first.
2. `ui/Pins.lua`: one layer from things; each kind file (Blips, Places, Quests, Rares, You's corpse and
   waypoint) turns its `Pins.Layer` into a `Pins.Kind`. The gear's toggles stay keyed as they are: Engine
   already keeps toggles that no layer owns, as the place kinds do.
3. Cluster on the picked list.
4. Delete: `Away`, `carried`, `Ours`/`NearOurs`, `Cluster.Hides` by table, `Track.Covers`, rares hiding under
   vignettes, the sensor/model distance split (one `SAME`), and Focus.off's blip keys.
5. The strict pins invariant runs on in every test and replay; the P1/P2 xfails pass.

## Consequences

- One place decides what you see; a new kind is a spec plus its Known list.
- Any change re-lays one bigger layer. Keyed diffing keeps unchanged pins untouched, and layouts already yield.
  The priced tests (test_path, test_quests_first_open, test_soak) must stay in budget; measure at step 2.
- Draw order across kinds moves from Engine layer levels to sublevels within one canvas: check overlaps
  (quests over blips) in the sim dump and the web demo.
- Model's matching is a little work per change of any kind's list. Bucketed by cell as model/Blips.lua's store
  is.

## Open questions for the user

1. **Precedence:** the order above. Should a rare win over a live blip of its name? Today the vignette hides
   the rare.
2. **Stale remembered pins:** a picked herb's remembered pin stays until the next sweep forgets it (about a
   second within range), rather than vanishing early. This is the trade for no gaps.
3. **SAME = 10 yd** (18 on the move) for everything, including NPCs that walk. Too tight or too loose?

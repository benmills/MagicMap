# 0012 No zone or subzone borders

Status: **accepted** (2026-11-02, the user's decision).

## Context

The big map drew zone and subzone borders traced from the terrain (ui/Borders.lua, Data/Borders.lua,
tools/gen_borders.py), and the hovered zone's own border over them (ui/ZoneInfo.lua). The linter scored them, and
hardening item M3 was open against them: they wrap unplayable land the game assigns to a zone.

## Decision

**The borders go, completely.** No lines on the map, no layer row, no opacity or width sliders. Hovering a zone still
brightens its name, a click still flies there, right-click still says what's at the spot, and `/mm zone` still works.

The one thing kept from that data is where each name sits: `Data/Anchors.lua` (tools/gen_anchors.py, `Atlas.Anchors`),
862 anchors, value for value what `Borders.labels` was. Data/Labels.lua and the hover's zone count read them.

## Why

- The data can't do better. A border is the area ID of a chunk (~33 yards), assigned for gameplay, not for a map:
  it's coarse, and it wraps land no player reaches.
- They read as roads.
- The art and the labels already show the zones.
- It was a lot to carry: ~700 lines of Lua and Python, a level-of-detail scheme, three linter checks, and 900 KB of data.

## Tried and dropped

Restricting the lines to playable land, with a quieter style. It still wasn't worth keeping.

## Consequences

- Engine's `"hold"` zoom mode stays: quest areas use it. It no longer has a layer that shows while the zoom moves, so
  its dimming goes unseen, and only the laying out where the zoom lands still matters.
- Old saved settings load harmlessly: the `borders` layer key is dropped at load, and saved `borders.*` looks are ignored.
- `/mm perf` no longer reports border builds, and `/mm debug` and `/mm mapstats` no longer count Lines: no engine
  layer draws any now (the path's are its own).

# 0002 Focus (UI → Model)

Status: accepted (v1). Types: [types/focus.lua](../../types/focus.lua).

## Context

Model needs to know what the user is looking at for three decisions: **what to forget**
(it holds per continent, so another continent can be dropped or compacted), **targeting**
(a target off the map shown is still a target, but its route is only found on your own
instance), and **which slice of the route to find first** (the part in view, near you).
The camera itself (centre, zoom, animation, follow-you easing, big/small window) is UI's
business and changes every frame while panning. If Model read the camera, every UI
camera change would become a Model change.

## Decision

`Model.Focus(focus)` is called from UI's ui step whenever the focus changes (calling it
every frame is allowed, since Model only compares). Model reads it in the next frame's
model step. Model runs before UI, so focus is one frame behind, and that is intended.

    MM.Focus { inst, rect?, zoom?, shown, follow }

- `inst`: the map shown. Required, and Model must work with only this set.
- `rect`: the tile rect in view (nil before the first layout).
- `zoom`: pixels per tile, for "is this detail worth keeping or finding now".
- `shown`: whether the map is visible. When false, Model keeps learning and skips work that only matters for the view.
- `follow`: whether the view follows you.

Locked: the call, its timing, and these fields. Open: new optional fields. Everything
else about the camera stays inside UI.

## Consequences

- UI can rebuild its camera, animation and layout freely without touching Model.
- One frame of latency on focus. That is invisible for forgetting and route priority. If
  a route slice ever needs the same-frame view, UI can call Focus from its input step.
- Model never knows pixels or screen sizes, only tile space and a zoom figure.

## Revisit if

- Model needs hover or selection (e.g. "quests under the cursor" computed by Model rather
  than UI asking Model and Atlas). In that case add an optional `hover: MM.Pos`, which is
  additive.
- More than one map is shown at once (a minimap and a big map as separate views). Focus
  would become a list, and that is a breaking change.

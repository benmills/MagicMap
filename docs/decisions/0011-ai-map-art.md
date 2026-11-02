# 0011 Map art: AI repaints, default on, disclosed

Status: **accepted** (2026-11-02, the user's decision). Plan and state of the work: docs/ai-map-art.md.

## Context

Parts of Blizzard's minimap tiles were never finished: flat, single-colour blocks with stepped edges, and
straight joins along the chunk grid. The map review (docs/map-review.json) accepted these as broken.

Until now the addon's rule was that terrain is the game's own textures, drawn by file ID, with a few pictures of
our own that hold none of Blizzard's pixels. Fixing the art within that rule was tried many ways.

## Decision

**1. Repaint the broken ground with OpenAI's image edits, and ship the result.** 14 places, 32.9 tiles' worth of
ground (tools/ai_regions.json). This changes the art rule: the addon now ships pictures derived from Blizzard's
tiles, `Textures/Repaint*.blp` with `Data/Repaint.lua`, drawn by ui/Repaint.lua on the tiles' canvas.

**2. A setting, on by default.** "Repair broken map art" (`repaint.on`), under Map in the Settings window. Off, the
player sees Blizzard's map as it is.

**3. It stops on another build.** The patches were painted for one set of tiles. On a game build they weren't made
for, the layer draws nothing, rather than risk patches that no longer line up.

**4. Disclosed.** A plain section at the end of README.md. NOTICE.md carves the pictures out of the GPLv3, says what
they are and where they came from, and promises removal if a rights holder objects.

## Why

- Of everything tried (below), the repaints are what the user chose to keep, after looking at them on the demo.
- Only the broken ground changes. The put-back is ours, not the model's: outside the mask the game's pixels stay
  exact, whatever the model did to them.
- The player stays in control: one switch, and the map is Blizzard's again.
- Players are told what it is, so anyone who objects to AI art can turn it off.

## The recipe

`tools/ai_fix.py`, per place:

- The window: the place and 0.75 tiles of good ground round it (0.5 for one), at 512 px a tile, sent at full
  size up to the API's limit. No reference images.
- The mask: the review's accepted broken ground, the flat ground connected to it, and any added by hand, grown by 2
  chunks. Real features the flat-ground test catches are protected by hand (`keep`).
- `gpt-image-2.5-sunburst`, `high`, the `blend` prompt (`sea` for joins in shallow water), 6 candidates.
- The put-back: the model's colours pulled to the real ones round the hole, laid in through a soft, wandering edge.
- A person picks. The scores (drift, edge, detail) can't pick a winner.
- A big place is painted in overlapping steps, the later continuing from the earlier (`over`).

Experiments that didn't hold: reference images made results worse, and a second refine pass didn't keep the layout.

## Alternatives tried and dropped

All of them are in git history (fae4b8e removed the last), and dropped on the user's call after looking at them.

| Alternative | What it did | State when dropped |
|---|---|---|
| Clouds | The game's fog-of-war puff stamped over each broken place, with a wash of the ground's colours under it | In the addon, then off by default |
| Rebuilt ground (`gen_fill.py`) | Guided image quilting: new pieces drawn from Blizzard's tile, masked and toned | In the addon |
| Soften seams (`gen_seams.py`) | Each straight join covered by a mirrored strip of its better side | In the addon |
| Tile texture (`gen_quilt.py`) | Flat ground quilted from its zone's tiles, desaturated and tinted | Demo only |
| Game textures (`gen_ground.py`) | Flecks of the game's ground textures, by file ID. They're art for up close, not map scale | Demo only |
| Relief (`gen_relief.py`) | Flat ground shaded from the game's own heights | Demo only |
| The veil, Mute unreachable land (`gen_bounds.py`) | Flat land you can't reach muted. Reach is an estimate, and a wrong guess mustn't dim a real zone | Demo only |

## Risk accepted by the user

The patches are made from Blizzard's art and so may be derivatives of it, and the addon distributes them. They
can't be licensed under the GPLv3, and were made by a third party's model. Blizzard, a host listing the addon, or
OpenAI's terms could each be a problem. The user weighed this and chose to ship without waiting on legal review.

If someone does object, the pictures come out: the repair is one setting's layer, and the addon works without it.
The fallback is removal, or a separate optional download.

## Consequences

- A game patch that changes tiles turns the layer off until the build is regenerated, and a changed tile under a place
  means repainting that place.
- Pictures can't be regenerated the same: a new run gives new ones. The shipped textures are the record.
- `Textures/` grows a lot, and the layer needs a look in the real client (docs/ai-map-art.md).
- Tools: tools/ai_fix.py, tools/ai_map.py, tools/ai_regions.json; tools/gen_fullmap.py draws each continent raw and fixed.

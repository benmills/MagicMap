# AI map art: the plan to the finish line

The broken parts of Blizzard's minimap art are repainted with OpenAI's image edits. Only the broken ground changes. This replaces every earlier art fix. The decision, its reasons and the alternatives: [ADR 0011](decisions/0011-ai-map-art.md).

## Where it stands (2026-11-03)

Done:

- All 16 places are painted, picked and live in the web demo (Menu -> Map art -> AI repaint). ek8, ek9 and kal6 (2026-11-03) had their seams marked by hand (`add`): the broken-ground detector doesn't see hard seams.
- `tools/ai_fix.py` makes candidates (cut to the recipes in use, `blend` and `sea`), `tools/ai_regions.json` holds the places and picks, `tools/ai_map.py` bakes them to `demo/ai/`.
- `tools/gen_fullmap.py` draws each continent raw and fixed.
- Removed: Relief, Tile texture, Game textures, Mute unreachable land, Rebuilt ground, Soften seams, and their tooling.
- Decided: the repaints ship as a default-on setting with a disclosure, without waiting on legal review (step 2).
- Written: the README's disclosure, `NOTICE.md`, ADR 0011, and the mentions in `docs/atlas-data.md`, `docs/structure.md` and `docs/features.md`.

Built: **step 3, the addon layer**, full size (123 textures, 43.1 MB), stamped for wowf 1.60.1.70707. Not yet seen in the real client: that test is what's left of step 3.

The recipe the experiments settled on: the `blend` prompt, no reference images, full size, 0.75 tiles of context, 6 candidates at `high`, a person picks. References made results worse, a second refine pass doesn't hold the layout, and the scores can't pick a winner.

## The steps

### 1. Review the demo (the user)

- Change any pick: one number in `tools/ai_regions.json`, then bake.
- Name any place to repaint, or a real feature lost: `add` and `keep` in the same file.
- Decide the 21 Later review items. Anything accepted becomes more places, at about $0.40-0.90 each. Other flat ground stays raw.

### 2. How it's licensed and distributed (decided)

The patches are made from Blizzard's tiles, so they may be derivatives of Blizzard's art, and we distribute them. The user decided:

- A setting, `repaint.on`, on by default: off, the player sees Blizzard's map as it is.
- A plain disclosure at the end of `README.md`.
- `NOTICE.md` carves the pictures out of the GPLv3 and promises removal if a rights holder objects.
- Not to wait on legal review. The user accepts the risk (ADR 0011).

If a host or a rights holder objects: remove the pictures, or move them to a separate optional download. Removing them means removing `Data/Repaint.lua` too: the layer tolerates missing data, not missing textures listed in it.

### 3. Draw it in the addon (built; real-client test to do)

1. Slice each patch on a 512 px grid, dropping empty cells: **123 textures**.
2. Write them as BLP. DXT5, for the soft alpha, in `tools/mmtools/blp.py`.
3. Generate `Data/Repaint.lua` and add its format to `atlas/Coords.lua` and `tools/mmtools/luaout.py`.
4. Add `ui/Repaint.lua`, a layer on the tiles' canvas with a Feel switch, `repaint.on`, "Repair broken map art", on by default. It draws nothing on a game build the patches weren't made for. Start from the piece layout in the removed `ui/Fill.lua` (in git history), without its masks: these pictures carry their own alpha.
5. Add it to `MagicMap.toc`, the files lists and `tools/package.sh`'s check, with a simple simulator test.

Size: full size, DXT5 with mips. Half size stays the fallback (about 10 MB, softer) if the real client shows a cost.

**Test in the real client.** The simulator can't show the look, DXT5 artifacts on the soft edge, or load and frame cost. Those need a real game session, including the bench and a pan over the biggest places.

### 4. Keep it true to the game

Each patch is painted for one set of tiles. The layer's build check keeps patches off a game build they weren't made for. For a new build: record the FileDataIDs under each place, and have the build fail if one changes, naming the place to repaint. A game patch then can't silently misalign the art.

### 5. Protect the source

Candidates live in `demo/aifix/` (2 GB, gitignored) and can't be regenerated the same: a new run gives new pictures. The user backed it up on 2026-11-03. Once step 3 lands, the shipped textures are committed, which is the record of what's on the map.

### 6. Update the project

Done, besides what depends on step 3:

- `NOTICE.md`, `README.md`, `docs/decisions/0011-ai-map-art.md`, `docs/atlas-data.md`, `docs/structure.md`, `docs/features.md`, `docs/development.md`.
- `tools/ai_fix.py`: only `blend` and `sea` left.
- `demo/hosted/README.md`: how to redeploy `ai/`.
- `dist/RELEASE_NOTES-v2.1.0.md` and `dist/listing-v2.1.0.md`: say plainly that some map art is AI-generated.

Left:

- `docs/brief.md` (levels).
- Delete the experiment folders from `demo/aifix/`, keeping those `tools/ai_regions.json` names.

### 7. Release

`tools/check.sh`, the package's load test, a play session over the repainted places, then tag.

## Costs

About $17.50 so far, experiments included. Repainting all 16 places again would be about $10. Each further place is about $0.40-0.90 for six candidates.

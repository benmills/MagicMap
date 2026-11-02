# AI map art: the plan to the finish line

The broken parts of Blizzard's minimap art are repainted with OpenAI's image edits. Only the broken ground changes. This replaces every earlier art fix.

## Where it stands (2026-11-02)

Done:

- All 14 places are painted, picked and live in the web demo (Map -> Map art -> AI repaint): 32.9 tiles' worth of ground.
- `tools/ai_fix.py` makes candidates, `tools/ai_regions.json` holds the places and picks, `tools/ai_map.py` bakes them to `demo/ai/`.
- `tools/gen_fullmap.py` draws each continent raw and fixed.
- Removed: Relief, Tile texture, Game textures, Mute unreachable land, Rebuilt ground, Soften seams, and their tooling.

Not done: **the addon draws none of this yet.** Its art fixes are gone, so until step 3 it shows Blizzard's broken art, plus the ocean and the sea-tile water. Don't release between the removal and step 3.

The recipe the experiments settled on: the `blend` prompt, no reference images, full size, 0.75 tiles of context, 6 candidates at `high`, a person picks. References made results worse, a second refine pass doesn't hold the layout, and the scores can't pick a winner.

## The steps

### 1. Review the demo (the user)

- Change any pick: one number in `tools/ai_regions.json`, then bake.
- Name any place to repaint, or a real feature lost: `add` and `keep` in the same file.
- Decide the 21 Later review items. Anything accepted becomes more places, at about $0.40-0.90 each. Other flat ground stays raw.

### 2. Decide how it's licensed and distributed (the user, blocks release)

The patches are made from Blizzard's tiles, so they are derivatives of Blizzard's art, and we'd distribute them. This is the first time the addon ships such pixels. Three things to settle, none of which this plan can answer:

- **GPL:** we can't license Blizzard-derived pictures under GPLv3, so they have to be carved out of it (see the draft below).
- **Blizzard's and the hosts':** check Blizzard's add-on policy and EULA, and the rules of each place the addon is listed.
- **OpenAI's:** check its terms cover this use of the output, and of the art we send it.

Legal advice is worth getting: this is a real risk, and it can't be tested away.

The fallback if a host refuses: a separate optional download of the art, with the addon working without it. Step 3's layer should tolerate missing textures, so that stays possible.

### 3. Draw it in the addon

1. Slice each patch on a 512 px grid, dropping empty cells: **115 textures**.
2. Write them as BLP. `tools/mmtools/blp.py` writes DXT1 only, which has no soft alpha, so it needs DXT5.
3. Generate `Data/Repaint.lua` and add its format to `atlas/Coords.lua` and `tools/mmtools/luaout.py`.
4. Add `ui/Repaint.lua`, a layer on the tiles' canvas with a Feel switch, `repaint.on`. Start from the piece layout in the removed `ui/Fill.lua` (in git history), without its masks: these pictures carry their own alpha.
5. Add it to `MagicMap.toc`, the files lists and `tools/package.sh`'s check, with a simple simulator test.

Size is the open question (a decision for this step):

| Option | Size | Trade-off |
|---|---|---|
| Full size, DXT5 with mips | about 39 MB | Crisp, against 8 MB of `Textures/` today |
| Half size, DXT5 with mips | about 10 MB | Softer beside the game's crisp tiles |

Recommendation: build full size, compare both in game, and ship the smaller if the difference doesn't show at normal zoom.

**Test in the real client.** The simulator can't show the look, DXT5 artifacts on the soft edge, or load and frame cost. Those need a real game session (the beta was down at the time of writing), including the bench and a pan over the biggest places.

### 4. Keep it true to the game

Each patch is painted for one set of tiles. Record the FileDataIDs under each place, and have the build fail if one changes, naming the place to repaint. A game patch then can't silently misalign the art.

### 5. Protect the source

Candidates live in `demo/aifix/` (2 GB, gitignored) and can't be regenerated the same: a new run gives new pictures. Back up the raw picks, at least, before anything clears the folder. Once step 3 lands, the shipped textures are committed, which is the record of what's on the map.

### 6. Update the project

- `NOTICE.md`: the draft below, once step 2 is settled.
- `docs/decisions/0011-ai-map-art.md`: the art rule's change, why, and what was tried.
- `README.md` (the line "the addon only draws the game's own textures"), `docs/brief.md` (levels), `docs/atlas-data.md`, `docs/structure.md`, `docs/features.md`.
- Release notes and listings: say plainly that some map art is AI-generated.
- `tools/ai_fix.py`: drop the recipes and prompts the experiments ruled out (`refs`, `markup`, `flare`, `refine`, `plain`, `no-mask` and so on), keeping `blend` and `sea`. Delete experiment folders from `demo/aifix/`.
- `demo/hosted/README.md`: how to redeploy `ai/`.

### 7. Release

`tools/check.sh`, the package's load test, a play session over the repainted places, then tag.

## Draft for NOTICE.md (not in force until step 2 and step 3)

> ## AI-repainted map art
>
> `Textures/Repaint*` and `Data/Repaint.lua` are not covered by the GPLv3 licence above. Parts of the game's minimap are unfinished: flat blocks of colour. These pictures repaint those parts. They were made by OpenAI's image models from the surrounding World of Warcraft minimap art, and may contain or derive from Blizzard Entertainment's art, whose rights remain Blizzard's. They are included only so that the map looks whole for people playing the game, and aren't offered for any other use. All other terrain is drawn at runtime from the game's own textures.
>
> If you are a rights holder and object to these pictures, open an issue and they will be removed.

## Costs

About $15 so far, experiments included. Repainting all 14 places again would be about $8.50. Each further place is about $0.40-0.90 for six candidates.

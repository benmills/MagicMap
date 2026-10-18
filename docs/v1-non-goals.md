# v1 non-goals

**CONFIRMED (D2, 2026-10-18): for the user to confirm.** Drafted from the spike's features (~/code/MagicMap
README, "Limits") and architecture.md. Each line says what v1 will *not* do and why. Anything
here can become a goal later, but none of it shapes v1's contracts (docs/decisions/).

v1 is the spike's feature set rebuilt on Game / Model / UI over Atlas and Runtime: the
zoomable minimap that grows into a big map, Blizzard's blips, quests and their areas, places,
group, rares, corpse, waypoint, the walking route, other addons' pins, and indoor art.

## Platform

- **Other flavors and clients** (Classic Era, SoD, Cata/MoP Classic, Retail, other servers).
  The data is generated from one WoW Forever build, and the sensor relies on that client's
  undocumented behaviour.
- **Builds other than the one Data/ was generated from, without regenerating.** Tile
  FileDataIDs change between builds, so a patch means re-running the generators, not a
  runtime fallback.
- **Locales other than enUS.** Atlas names, the herb list and matching blips by tooltip name
  are all enUS. Supporting another locale means generating its names and re-measuring the sensor.
- **Gamepad or controller-first input.** The sensor borrows the soft cursor, and the
  map's input is mouse-driven.

## Map

- **Editing maps**: no user notes, custom pins, drawing or renaming. The waypoint is the
  one user mark, and it is the game's own.
- **Rotating the map with the camera.** We stay north-up. Rotate Minimap is ignored, and
  other addons' minimap pins hide while it is on.
- **Positions inside instances.** The game withholds them, so dungeons and raids show
  whole, with no arrow, route or blips.
- **Replacing Blizzard's world map everywhere.** M grows our map. The quest log (L) and
  anything else that opens Blizzard's map still opens it.
- **Drawing the flight network or planning flights.** Atlas has taxi paths, but v1 only
  shows flight points.
- **Unexplored shading beyond the spike's.** It stays an opt-in layer and gets no fog-of-war art.

## Routes

- **Routes beyond walking**: no flight paths, boats, zeppelins, portals, hearthstone or
  mount speed, and nothing across instances or continents. The walk grid covers one
  instance at a time, and a target elsewhere gets a straight line or an edge arrow.
- **Optimal quest ordering or multi-stop routes.** v1 has one target at a time (corpse,
  then the followed quest, then the waypoint).

## Data and memory

- **A quest or gathering database of our own.** Quests, NPCs and objects come from the
  QuestieDB-derived Atlas data. Seen blips are capped at 200 an instance, so v1 is not a
  GatherMate replacement.
- **Sharing between players** (addon messages, guild-shared rares). Rares are shared only
  across your own account's characters.
- **Per-character settings or profiles.** Everything is account-wide, as in the spike (ADR 0004).
- **Migrating the spike's saved data** (`MagicMapDB`, `MagicMapLandmarks`). v1 starts fresh.
- **Network telemetry.** The addon can't reach the network. Telemetry is SavedVariables
  read locally (docs/telemetry.md).

## Other addons

- **An API for other addons to add pins to our map directly.** We borrow HereBeDragons'
  pins and don't offer our own provider.
- **Integrating with other minimap addons** (SexyMap, square-minimap addons). We may
  conflict. While FarmHud has the minimap, we yield to it rather than share.
- **Working without QuestieDB-derived data.** The map runs without it, but quest
  objectives lose their mobs and items, and v1 is not tuned for that.

## Not a non-goal, but a release blocker

- QuestieDB declares no license, so the QuestieDB-derived data (docs/atlas-data.md) can't
  be published until that is settled, or until v1 reads QuestieDB at runtime as the spike
  did. This needs the user's decision before a public v1.

# Notices

MagicMap is free software: you can redistribute it and/or modify it under the terms of the GNU General
Public License, version 3, as published by the Free Software Foundation (see [LICENSE](LICENSE)). It
comes with NO WARRANTY, to the extent permitted by law.

## Quest, NPC, object and item data

`Data/Npcs.lua`, `Data/Objects.lua`, `Data/Items.lua`, `Data/Quests.lua` and `Data/BlipServices.lua` are
derived by `tools/gen_questie.py` from **QuestieDB** (https://github.com/Questie/QuestieDB), whose data,
schema and corrections were imported from **Questie** (https://github.com/Questie/Questie). They are
used, modified (filtered, projected onto MagicMap's map coordinates and repacked) and redistributed
under the GPLv3 terms that QuestieDB's and Questie's `LICENSE.md` extend to forks and copies.

Credit for that data belongs to the Questie and QuestieDB authors and contributors: Aero, Logon (Logonz),
Muehe, TheCrux (BreakBB), Drejjmit, Dyaxler, Cheeq, TechnoHunter, Yttrium, Sommos, and everyone else who
contributed to Questie and QuestieDB. As their licence notes say, Questie's history predates its licence;
see their `LICENSE.md` files for the full terms.

MagicMap is not affiliated with or endorsed by the Questie project, and doesn't use the Questie name or
logo for itself: it names Questie only to credit this data and, at runtime, to place Questie's own pins
on its map when Questie is installed.

## Game data

The map's terrain tiles, indoor maps, icons and the rest of `Data/` are read from the World of Warcraft
client's own files and APIs at build time (`tools/gen_*.py`), and drawn at runtime from the game's own
textures. World of Warcraft is a trademark of Blizzard Entertainment, Inc.; MagicMap is not affiliated
with Blizzard.

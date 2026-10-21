# Interiors prototype (2026-10-20)

The offline mockup and in-game test behind [ADR 0008](../../decisions/0008-interiors.md), kept as
the reference implementation. Scratch code: not part of the addon, not tested.

- `common.py`: reading game files (through tools/mmtools), MODF and WMO-root parsing, `place()`.
- `render.py`: Ironforge's pictures composited over our terrain tiles (ironforge-mockup.jpg).
- `rooms_meta.py`: rooms to WMOAreaTable names (via each room file's MOGP group ID) and portals.
- `gen_lua.py`, `gen_rooms.py`: the test addon's data (pictures; rooms' masks, names, links).
- `levels.py`, `census.py`: how much floor is stacked; buildings and pictures per continent.
- `addon/`: the test addon (MagicMapIndoorTest, /mmit): placement, room tracking, culling.

Run with the repo's venv from this folder (they import ../../../tools/mmtools by absolute path:
edit `common.py`'s sys.path if the repo moves).

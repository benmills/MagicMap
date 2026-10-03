"""Which maps exist: Map.db2 and AreaTable.db2, read by content rather than
fixed column numbers, since table layouts shift between builds.
"""
from __future__ import annotations

from dataclasses import dataclass

from .db2 import read_wdc5

MAP_DB2 = 1349477        # dbfilesclient/map.db2
AREATABLE_DB2 = 1353545  # dbfilesclient/areatable.db2
AZEROTH_WDT = 775971

KINDS = {0: None, 1: "dungeon", 2: "raid"}  # Map InstanceType -> kind


@dataclass(frozen=True)
class MapInfo:
    inst: int                 # instanceID (Map.db2 ID)
    wdt: int                  # WDT FileDataID
    name: str
    kind: str | None = None   # None: open world
    continent: int | None = None  # for instances: the entrance's continent, if known


def read_maps(map_db2: bytes) -> list[MapInfo]:
    """Every open-world map, dungeon and raid that has a WDT.

    Columns are found by content: the WDT column holds Azeroth's known WDT on
    map 0; InstanceType follows MapType, which follows the first array field
    (Corpse x,y). CorpseMapID (the continent an instance's entrance is on) is
    0 for Deadmines (36) and 1 for Razorfen Kraul (47) and Zul'Farrak (209).
    """
    rows = read_wdc5(map_db2, string_fields={0, 1})
    by_id = {r[0]: r for r in rows}
    azeroth = by_id.get(0)
    if azeroth is None:
        raise SystemExit("map 0 missing from Map.db2")
    wdt_col = next((c for c, v in enumerate(azeroth) if v == AZEROTH_WDT), None)
    if wdt_col is None:
        raise SystemExit("WDT column not found in Map.db2")
    array_col = next((c for c in range(1, len(azeroth)) if isinstance(azeroth[c], tuple)), None)
    if array_col is None:
        raise SystemExit("Corpse column not found in Map.db2")
    inst_col = array_col + 2

    def col(r, c):
        return r[c] if c < len(r) else None

    corpse_map_col = next((c for c in range(inst_col + 1, len(azeroth))
                           if col(by_id.get(36, []), c) == 0 and col(by_id.get(47, []), c) == 1
                           and col(by_id.get(209, []), c) == 1), None)
    maps = []
    for r in rows:
        if r[inst_col] not in KINDS or not isinstance(r[wdt_col], int) or r[wdt_col] <= 0:
            continue
        name = r[2] if isinstance(r[2], str) and r[2] else f"Map {r[0]}"
        kind = KINDS[r[inst_col]]
        # An unset corpse point (0,0) means the entrance's continent is unknown.
        continent = None
        if kind and corpse_map_col is not None and any(r[array_col]):
            continent = r[corpse_map_col]
        maps.append(MapInfo(r[0], r[wdt_col], name, kind, continent))
    return maps


def read_area_parents(areatable_db2: bytes) -> dict[int, int]:
    """AreaTable: area ID -> parent area ID (0 for a zone)."""
    return {r[0]: r[4] for r in read_wdc5(areatable_db2, string_fields={0, 1})}

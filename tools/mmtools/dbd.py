"""DB2 columns by name, from the WoWDBDefs definitions vendored in tools/dbd/
(github.com/wowdev/WoWDBDefs). The layout is picked by the table's own
layout hash, so columns follow the build rather than fixed positions.

    rows = read_table("AreaTable", src.read(AREATABLE_DB2))
    # -> [{"ID": 12, "ZoneName": "Elwynn", "ParentAreaID": 0, ...}, ...]

Floats are floats, signed ints are signed, arrays are lists.
"""
from __future__ import annotations

import re
import struct
from dataclasses import dataclass
from pathlib import Path

from .db2 import layout_hash, read_wdc5

DBD_DIR = Path(__file__).resolve().parent.parent / "dbd"


@dataclass(frozen=True)
class Field:
    name: str
    type: str          # int | float | string | locstring
    ann: frozenset     # id, relation, noninline
    bits: int          # 32 when unsized
    signed: bool
    arr: int           # 1 for scalars


def layout(table: str, hash_: str) -> list[Field]:
    """The fields of `table`'s LAYOUT block naming hash_, in record order."""
    blocks = (DBD_DIR / f"{table}.dbd").read_text().split("\n\n")
    types = {}
    for line in blocks[0].splitlines()[1:]:
        typ, name = re.match(r"(\w+)(?:<[^>]*>)?\s+(\w+)", line).groups()
        types[name] = typ
    for block in blocks[1:]:
        lines = block.strip().splitlines()
        if not lines[0].startswith("LAYOUT") or hash_ not in re.findall(r"\w+", lines[0]):
            continue
        fields = []
        for line in lines:
            if line.startswith(("LAYOUT", "BUILD", "COMMENT")):
                continue
            ann, name, uns, bits, arr = re.match(r"(?:\$([\w,]+)\$)?(\w+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?", line).groups()
            fields.append(Field(name, types[name], frozenset(ann.split(",") if ann else ()),
                                int(bits or 32), not uns, int(arr or 1)))
        return fields
    raise SystemExit(f"layout {hash_} not in {table}.dbd")


def _f32(v: int) -> float:
    return struct.unpack("<f", struct.pack("<I", v))[0]


def read_table(table: str, b: bytes) -> list[dict]:
    fields = layout(table, layout_hash(b))
    inline = [f for f in fields if "noninline" not in f.ann]
    strings = {i for i, f in enumerate(inline) if f.type in ("string", "locstring")}
    id_field = next((f.name for f in fields if "id" in f.ann), "ID")
    rel_field = next((f.name for f in fields if "relation" in f.ann and "noninline" in f.ann), None)
    out = []
    for r in read_wdc5(b, strings, relation=rel_field is not None):
        row = {id_field: r[0]}
        for f, v in zip(inline, r[1:]):
            if f.arr > 1 and isinstance(v, int):  # packed small array (storage none)
                v = [(v >> (k * f.bits)) & ((1 << f.bits) - 1) for k in range(f.arr)]
            vs = list(v) if f.arr > 1 else [v]
            if f.type == "float":
                vs = [_f32(x) for x in vs]
            elif f.type == "int" and f.signed:
                vs = [x - (1 << f.bits) if x >= 1 << (f.bits - 1) else x for x in vs]
            elif f.type in ("string", "locstring") and not isinstance(vs[0], str):
                vs = [""]
            row[f.name] = vs if f.arr > 1 else vs[0]
        row[id_field] = r[0]
        if rel_field:
            row[rel_field] = r[-1]
        out.append(row)
    return out

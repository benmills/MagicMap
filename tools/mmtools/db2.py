"""Minimal WDC5 (.db2) reader.

    rows = read_wdc5(data, string_fields={0, 1})
    # -> [[id, field0, field1, ...], ...]

Values are ints; array fields are tuples of ints; fields listed in
string_fields are str when their value resolves to a string (else the raw
int). Floats come back as their raw uint32 bits. The ID comes from the id
list, else the inline id field. Copy-table rows are included. With
relation=True each row ends with its relationship-map value (a non-inline
foreign key, e.g. MapDifficulty's MapID), or 0.

Storage types: none(0), bitpacked(1), common(2), bitpacked-indexed(3),
bitpacked-indexed-array(4), bitpacked-signed(5). Encrypted sections are
skipped; sparse tables (offset map) aren't supported. mmtools.dbd names and
types the columns from WoWDBDefs.
"""
from __future__ import annotations

import struct


def _bits(rec: bytes, bit_off: int, nbits: int) -> int:
    if nbits == 0:
        return 0
    first, last = bit_off >> 3, (bit_off + nbits - 1) >> 3
    v = int.from_bytes(rec[first:last + 1], "little") >> (bit_off & 7)
    return v & ((1 << nbits) - 1)


HEADER = 4 + 4 + 128  # magic, schema version, schema build string


def layout_hash(b: bytes) -> str:
    """The header's layout hash, as WoWDBDefs writes it (e.g. "0B8D2AAD")."""
    return f"{struct.unpack_from('<I', b, HEADER + 20)[0]:08X}"


def read_wdc5(b: bytes, string_fields=(), relation: bool = False) -> list[list]:
    if b[:4] != b"WDC5":
        raise ValueError(f"not WDC5 ({b[:4]!r})")
    string_fields = set(string_fields)
    p = HEADER
    (rec_count, field_count, rec_size, _str_size, _table_hash, _layout_hash, _min_id, _max_id, _locale,
     flags, id_index, _total_fields, _bitpacked_offset, _lookup_cols, _fsi_size, common_size, pallet_size,
     section_count) = struct.unpack_from("<9IHH7I", b, p)
    p += 4 * 9 + 4 + 4 * 7
    if not rec_count:
        return []

    sections = []
    for _ in range(section_count):
        key_lo, key_hi, off, rc, ss, _rec_end, id_list_size, rel_size, _off_map_count, copy_count = \
            struct.unpack_from("<10I", b, p)
        sections.append({"encrypted": bool(key_lo or key_hi), "off": off, "rc": rc, "ss": ss,
                         "id_list_size": id_list_size, "rel_size": rel_size, "copy_count": copy_count})
        p += 40
    p += 4 * field_count  # field structure (size, position): implied by the storage info
    fsi = []
    for _ in range(field_count):
        off_bits, size_bits, add_size, typ, v1, v2, v3 = struct.unpack_from("<HHIIIII", b, p)
        fsi.append({"off_bits": off_bits, "size_bits": size_bits, "add_size": add_size, "type": typ,
                    "v1": v1, "v2": v2, "v3": v3})
        p += 24
    pallet_start = p
    common_start = pallet_start + pallet_size

    pal_off = com_off = 0
    for f in fsi:
        if f["type"] in (3, 4):
            f["pallet_base"] = pallet_start + pal_off
            pal_off += f["add_size"]
        if f["type"] == 2:  # common data: (id, value) pairs
            n = f["add_size"] // 8
            pairs = struct.unpack_from(f"<{2 * n}I", b, common_start + com_off)
            f["common"] = dict(zip(pairs[0::2], pairs[1::2]))
            com_off += f["add_size"]

    if flags & 1:
        raise ValueError("sparse db2 not supported")

    # WDC3+ string offsets are relative to a field's position within the
    # records of *all* sections laid end to end (encrypted ones included);
    # each section's string table covers the next slice of "keys" after all
    # record data.
    first_rec, key_base = 0, rec_count * rec_size
    for s in sections:
        s["first_rec"] = first_rec
        s["str_key_base"] = key_base
        s["str_start"] = s["off"] + s["rc"] * rec_size
        first_rec += s["rc"]
        key_base += s["ss"]

    def string_at(key: int) -> str | None:
        for s in sections:
            if s["encrypted"] or not s["str_key_base"] <= key < s["str_key_base"] + s["ss"]:
                continue
            start = s["str_start"] + key - s["str_key_base"]
            return b[start:b.index(b"\0", start)].decode("utf-8", "replace")
        return None

    rows = []
    for s in sections:
        if not s["rc"] or s["encrypted"] or s["off"] >= len(b):
            continue
        rec_start = s["off"]
        q = rec_start + s["rc"] * rec_size + s["ss"]
        ids = struct.unpack_from(f"<{s['id_list_size'] // 4}I", b, q)
        q += s["id_list_size"]
        copies = struct.unpack_from(f"<{2 * s['copy_count']}I", b, q)
        q += 8 * s["copy_count"]
        rel = {}
        if s["rel_size"]:
            n = struct.unpack_from("<I", b, q)[0]
            pairs = struct.unpack_from(f"<{2 * n}I", b, q + 12)  # (foreign id, record index)
            rel = dict(zip(pairs[1::2], pairs[0::2]))
        by_id = {}
        for r in range(s["rc"]):
            rec = b[rec_start + r * rec_size:rec_start + (r + 1) * rec_size]
            vals: list = []
            for fi, f in enumerate(fsi):
                t = f["type"]
                if t == 0:
                    nbytes = f["size_bits"] // 8
                    if f["size_bits"] % 32 == 0 and f["size_bits"] > 32:
                        val = struct.unpack_from(f"<{nbytes // 4}I", rec, f["off_bits"] // 8)
                    else:
                        val = _bits(rec, f["off_bits"], f["size_bits"])
                    if fi in string_fields and val:
                        key = (s["first_rec"] + r) * rec_size + f["off_bits"] // 8 + val
                        text = string_at(key)
                        if text is not None:
                            val = text
                elif t in (1, 5):
                    val = _bits(rec, f["off_bits"], f["v2"])  # v2 = bit width
                    if t == 5 and val & (1 << (f["v2"] - 1)):
                        val -= 1 << f["v2"]
                elif t == 2:
                    val = None  # filled once the id is known
                elif t == 3:
                    idx = _bits(rec, f["off_bits"], f["v2"])
                    val = struct.unpack_from("<I", b, f["pallet_base"] + idx * 4)[0]
                elif t == 4:
                    idx = _bits(rec, f["off_bits"], f["v2"])
                    n = f["v3"]
                    val = struct.unpack_from(f"<{n}I", b, f["pallet_base"] + idx * 4 * n)
                else:
                    raise ValueError(f"unsupported storage type {t} (field {fi})")
                vals.append(val)
            rid = ids[r] if ids else vals[id_index]
            for fi, f in enumerate(fsi):
                if f["type"] == 2:
                    vals[fi] = f["common"].get(rid, f["v1"])
            row = [rid] + vals + ([rel.get(r, 0)] if relation else [])
            rows.append(row)
            by_id[rid] = row
        for new, old in zip(copies[0::2], copies[1::2]):
            rows.append([new] + by_id[old][1:])
    return rows


def format_value(v) -> str:
    """The db2dump text form: arrays joined with ',', strings as s:<text>."""
    if v is None:
        return ""
    if isinstance(v, tuple):
        return ",".join(str(x) for x in v)
    if isinstance(v, str):
        return "s:" + v
    return str(v)

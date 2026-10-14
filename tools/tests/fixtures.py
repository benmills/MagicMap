"""Synthetic game data for testing the generators without a game install:
writers for WDC5 tables, WDT / ADT / BLP files, and a minimal local CASC
install holding them, plus a small seeded world built from all of those.
"""
from __future__ import annotations

import hashlib
import math
import os
import random
import struct
import zlib

# --- WDC5 ---------------------------------------------------------------------
# Field specs:
#   ("int", bits)              inline (storage 0)
#   ("string",)                inline 32-bit offset into the string table
#   ("array", n)               inline n x uint32 (storage 0, 32n bits)
#   ("bitpacked", bits)        storage 1
#   ("signed", bits)           storage 5
#   ("common", default)        storage 2: values off-record, by id
#   ("pallet", bits)           storage 3: index into a value list
#   ("pallet_array", bits, n)  storage 4: index into a list of n-tuples


def build_wdc5(fields: list[tuple], rows: list[tuple[int, list]], sections: int = 1, id_list: bool = True) -> bytes:
    """rows: (id, [value per field]). Records are split evenly over
    `sections`, each with its own string table and id list."""
    # Layout: inline bits for every field but common.
    offs, bit = [], 0
    for f in fields:
        offs.append(bit)
        kind = f[0]
        if kind == "int":
            bit += f[1]
        elif kind in ("string",):
            bit += 32
        elif kind == "array":
            bit += 32 * f[1]
        elif kind in ("bitpacked", "signed", "pallet", "pallet_array"):
            bit += f[1]
    rec_size = (bit + 7) // 8
    rec_count = len(rows)

    # Pallets and common data.
    pallets: list[list] = [[] for _ in fields]
    common: list[dict] = [{} for _ in fields]
    for rid, vals in rows:
        for fi, f in enumerate(fields):
            if f[0] in ("pallet", "pallet_array") and vals[fi] not in pallets[fi]:
                pallets[fi].append(vals[fi])
            if f[0] == "common" and vals[fi] != f[1]:
                common[fi][rid] = vals[fi]
    pallet_blob, common_blob = b"", b""
    fsi = b""
    for fi, f in enumerate(fields):
        kind = f[0]
        size_bits = {"int": f[1] if kind == "int" else 0}.get(kind, 0)
        if kind == "string":
            size_bits = 32
        if kind == "array":
            size_bits = 32 * f[1]
        typ, add, v1, v2, v3 = 0, 0, 0, 0, 0
        if kind == "bitpacked":
            typ, v2 = 1, f[1]
            size_bits = f[1]
        elif kind == "signed":
            typ, v2 = 5, f[1]
            size_bits = f[1]
        elif kind == "common":
            typ, v1 = 2, f[1]
            items = sorted(common[fi].items())
            add = 8 * len(items)
            common_blob += b"".join(struct.pack("<II", k, v) for k, v in items)
        elif kind == "pallet":
            typ, v2 = 3, f[1]
            size_bits = f[1]
            add = 4 * len(pallets[fi])
            pallet_blob += b"".join(struct.pack("<I", v) for v in pallets[fi])
        elif kind == "pallet_array":
            typ, v2, v3 = 4, f[1], f[2]
            size_bits = f[1]
            add = 4 * f[2] * len(pallets[fi])
            pallet_blob += b"".join(struct.pack(f"<{f[2]}I", *v) for v in pallets[fi])
        fsi += struct.pack("<HHIIIII", offs[fi], size_bits, add, typ, v1, v2, v3)

    # Records, per section, with strings.
    per = math.ceil(rec_count / sections) if rec_count else 0
    chunks = [rows[i:i + per] for i in range(0, rec_count, per)] if per else []
    key_base = rec_count * rec_size  # string keys follow all record data
    sec_blobs = []
    first = 0
    for chunk in chunks:
        strings = bytearray(b"\0")  # offset 0 = empty
        recs = bytearray()
        for r, (rid, vals) in enumerate(chunk):
            v = 0
            for fi, f in enumerate(fields):
                kind, val = f[0], vals[fi]
                if kind == "int" or kind == "bitpacked":
                    v |= (val & ((1 << f[1]) - 1)) << offs[fi]
                elif kind == "signed":
                    v |= (val & ((1 << f[1]) - 1)) << offs[fi]
                elif kind == "string":
                    if val:
                        pos = len(strings)
                        strings += val.encode() + b"\0"
                        key = key_base + pos
                        rel = key - ((first + r) * rec_size + offs[fi] // 8)
                        v |= (rel & 0xFFFFFFFF) << offs[fi]
                elif kind == "array":
                    for k, x in enumerate(val):
                        v |= x << (offs[fi] + 32 * k)
                elif kind in ("pallet", "pallet_array"):
                    v |= pallets[fi].index(val) << offs[fi]
            recs += v.to_bytes(rec_size, "little")
        ids = b"".join(struct.pack("<I", rid) for rid, _ in chunk) if id_list else b""
        sec_blobs.append((bytes(recs), bytes(strings), ids, len(chunk)))
        key_base += len(strings)
        first += len(chunk)

    total_str = sum(len(s) for _, s, _, _ in sec_blobs)
    ids_all = [rid for rid, _ in rows]
    header = b"WDC5" + struct.pack("<I", 5) + b"\0" * 128
    header += struct.pack("<9IHH7I", rec_count, len(fields), rec_size, total_str, 0x1234, 0x5678,
                          min(ids_all, default=0), max(ids_all, default=0), 0, 0 if id_list else 4, 0,
                          len(fields), 0, 0, 24 * len(fields), len(common_blob), len(pallet_blob), len(sec_blobs))
    field_struct = b"".join(struct.pack("<hH", 0, offs[fi] // 8) for fi in range(len(fields)))
    meta_len = len(header) + 40 * len(sec_blobs) + len(field_struct) + len(fsi) + len(pallet_blob) + len(common_blob)
    sec_headers, body, off = b"", b"", meta_len
    for recs, strings, ids, n in sec_blobs:
        sec_headers += struct.pack("<10I", 0, 0, off, n, len(strings), 0, len(ids), 0, 0, 0)
        blob = recs + strings + ids
        body += blob
        off += len(blob)
    return header + sec_headers + field_struct + fsi + pallet_blob + common_blob + body


# --- WDT / ADT / BLP ------------------------------------------------------------

def chunk(magic: bytes, data: bytes) -> bytes:
    return magic[::-1] + struct.pack("<I", len(data)) + data


def build_wdt(tiles: dict[int, tuple[int, int]]) -> bytes:
    """tiles: {col * 64 + row: (root ADT FDID, minimap FDID)}"""
    ids = [0] * (4096 * 8)
    for key, (adt, minimap) in tiles.items():
        col, row = divmod(key, 64)
        i = row * 64 + col
        ids[i * 8] = adt
        ids[i * 8 + 7] = minimap
    return chunk(b"MVER", struct.pack("<I", 18)) + chunk(b"MPHD", b"\0" * 32) + \
        chunk(b"MAID", struct.pack(f"<{len(ids)}I", *ids))


def build_adt(chunks: list[tuple[int, int, int, float, list[float] | None]]) -> bytes:
    """chunks: (ix, iy, area, z, 145 height offsets or None)"""
    out = chunk(b"MVER", struct.pack("<I", 18)) + chunk(b"MHDR", b"\0" * 64)
    for ix, iy, area, z, heights in chunks:
        head = bytearray(0x80)
        struct.pack_into("<III", head, 0, 0, ix, iy)
        struct.pack_into("<I", head, 0x34, area)
        struct.pack_into("<f", head, 0x70, z)
        body = bytes(head)
        if heights is not None:
            body += chunk(b"MCVT", struct.pack("<145f", *heights))
        body += chunk(b"MCNR", b"\0" * 448)
        out += chunk(b"MCNK", body)
    return out


def build_blp(w: int, h: int, color_fn) -> bytes:
    """A DXT1 BLP2 whose block (bx, by) has endpoint colours color_fn(bx, by)
    -> (c0, c1) as RGB565 ints."""
    head = b"BLP2" + struct.pack("<I", 1) + struct.pack("<BBBBII", 2, 0, 0, 0, w, h)
    data_off = 20 + 64 + 64 + 1024
    mips = struct.pack("<16I", data_off, *[0] * 15) + struct.pack("<16I", (w // 4) * (h // 4) * 8, *[0] * 15)
    palette = b"\0" * 1024
    blocks = b"".join(struct.pack("<HHI", *color_fn(bx, by), 0) for by in range(h // 4) for bx in range(w // 4))
    return head + mips + palette + blocks


# --- CASC -----------------------------------------------------------------------

def blte(data: bytes, chunked: bool) -> bytes:
    if not chunked:
        return b"BLTE" + struct.pack(">I", 0) + b"N" + data
    half = len(data) // 2
    parts = [b"Z" + zlib.compress(data[:half]), b"N" + data[half:]]
    header_size = 12 + 24 * len(parts)
    info = b"".join(struct.pack(">II", len(p), len(p) - 1) + hashlib.md5(p).digest() for p in parts)
    return b"BLTE" + struct.pack(">I", header_size) + b"\x0f" + struct.pack(">I", len(parts))[1:] + info + b"".join(parts)


def build_casc(install: str, product: str, version: str, files: dict[int, bytes], page_entries: int = 3) -> None:
    """A local install holding `files` (FDID -> bytes) for `product`."""
    data_dir = os.path.join(install, "Data")
    os.makedirs(os.path.join(data_dir, "data"), exist_ok=True)
    archive = bytearray()
    index: list[tuple[bytes, int, int]] = []
    encoding_entries: list[tuple[bytes, bytes]] = []  # (ckey, ekey)

    def store(content: bytes, chunked: bool) -> tuple[bytes, bytes]:
        encoded = blte(content, chunked)
        ckey = hashlib.md5(content).digest()
        ekey = hashlib.md5(encoded).digest()
        index.append((ekey[:9], len(archive), 30 + len(encoded)))
        archive.extend(ekey[::-1] + struct.pack("<I", 30 + len(encoded)) + b"\0" * 10 + encoded)
        return ckey, ekey

    # Two root blocks: one for another locale (skipped), one enUS.
    fdids = sorted(files)
    stored = {fdid: store(files[fdid], chunked=i % 2 == 0) for i, fdid in enumerate(fdids)}
    for ckey, ekey in stored.values():
        encoding_entries.append((ckey, ekey))

    def root_block(ids: list[int], locale: int, keys: list[bytes]) -> bytes:
        deltas, prev = [], -1
        for f in ids:
            deltas.append(f - prev - 1)
            prev = f
        n = len(ids)
        return struct.pack("<IIIIB", n, locale, 0x10000000, 0, 0) + struct.pack(f"<{n}i", *deltas) + b"".join(keys)

    decoy = [hashlib.md5(b"decoy%d" % f).digest() for f in fdids]
    root = b"TSFM" + struct.pack("<IIIII", 0x18, 2, len(fdids), 0, 0) + \
        root_block(fdids, 0x4, decoy) + root_block(fdids, 0x2, [stored[f][0] for f in fdids])
    root_ckey, root_ekey = store(root, chunked=False)
    encoding_entries.append((root_ckey, root_ekey))

    # Encoding: CKey -> EKey pages, sorted, a few entries per page.
    encoding_entries.sort()
    pages = [encoding_entries[i:i + page_entries] for i in range(0, len(encoding_entries), page_entries)]
    page_kb = 1
    page_table, page_data = b"", b""
    for page in pages:
        body = b"".join(b"\x01" + b"\0" * 5 + ck + ek for ck, ek in page)
        body = body.ljust(page_kb * 1024, b"\0")
        page_table += page[0][0] + hashlib.md5(body).digest()
        page_data += body
    espec = b"z\0"
    enc = b"EN" + struct.pack(">BBBHHIIBI", 1, 16, 16, page_kb, 0, len(pages), 0, 0, len(espec)) + espec + page_table + page_data
    _, enc_ekey = store(enc, chunked=True)

    with open(os.path.join(data_dir, "data", "data.000"), "wb") as f:
        f.write(archive)
    # Two generations of one index bucket: only the newer counts.
    entries = b""
    for key, off, size in sorted(index):
        loc = off  # archive 0
        entries += key + struct.pack(">BI", loc >> 32, loc & 0xFFFFFFFF) + struct.pack("<I", size)
    idx = struct.pack("<I", 16) + b"\0" * 16
    idx = idx.ljust(0x20, b"\0") + struct.pack("<II", len(entries), 0) + entries
    with open(os.path.join(data_dir, "data", "0000000002.idx"), "wb") as f:
        f.write(idx)
    stale = struct.pack("<I", 16) + b"\0" * 16
    stale = stale.ljust(0x20, b"\0") + struct.pack("<II", 0, 0)
    with open(os.path.join(data_dir, "data", "0000000001.idx"), "wb") as f:
        f.write(stale)

    build_key = hashlib.md5(b"build" + version.encode()).hexdigest()
    cfg_dir = os.path.join(data_dir, "config", build_key[:2], build_key[2:4])
    os.makedirs(cfg_dir, exist_ok=True)
    with open(os.path.join(cfg_dir, build_key), "w") as f:
        f.write("# Build Configuration\n\n")
        f.write(f"root = {root_ckey.hex()}\n")
        f.write(f"encoding = {hashlib.md5(enc).hexdigest()} {enc_ekey.hex()}\n")
        f.write(f"build-name = WOW-{version.split('.')[-1]}patch{version}\n")
    with open(os.path.join(install, ".build.info"), "w") as f:
        f.write("Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|CDN Key!HEX:16|Version!STRING:0|Product!STRING:0\n")
        f.write(f"eu|1|{'0' * 32}|{'0' * 32}|9.9.9.1|wow\n")
        f.write(f"eu|1|{build_key}|{'0' * 32}|{version}|{product}\n")


# --- a small world ------------------------------------------------------------

PRODUCT, VERSION = "wow_test", "1.60.1.12345"
MAP_DB2, AREATABLE_DB2 = 1349477, 1353545
AZEROTH_WDT, KALIMDOR_WDT, DEADMINES_WDT, BG_WDT = 775971, 782779, 900001, 900002

MAP_FIELDS = [
    ("string",),            # 0 Directory
    ("string",),            # 1 MapName
    ("int", 32),            # 2 some flags
    ("array", 2),           # 3 Corpse x, y (float bits)
    ("bitpacked", 4),       # 4 MapType
    ("pallet", 3),          # 5 InstanceType
    ("common", 0),          # 6 CorpseMapID
    ("int", 32),            # 7 WdtFileDataID
    ("pallet_array", 2, 3),  # 8 some array
    ("signed", 8),          # 9 a signed field
]


def _f(x: float) -> int:
    return struct.unpack("<I", struct.pack("<f", x))[0]


def map_rows() -> list[tuple[int, list]]:
    def row(i, dir_, name, inst_type, corpse_map, wdt, corpse=(0, 0)):
        return (i, [dir_, name, 7, corpse, 1, inst_type, corpse_map, wdt, (1, 2, 3), -5])
    return [
        row(0, "Azeroth", "Eastern Kingdoms", 0, 0, AZEROTH_WDT),
        row(1, "Kalimdor", "Kalimdor", 0, 0, KALIMDOR_WDT),
        row(36, "DeadminesInstance", "Deadmines", 1, 0, DEADMINES_WDT, (_f(-11208.0), _f(1672.0))),
        row(47, "RazorfenKraulInstance", "Razorfen Kraul", 1, 1, 0, (_f(-4459.0), _f(-1660.0))),
        row(209, "TanarisInstance", "Zul'Farrak", 2, 1, 0, (_f(-6790.0), _f(-2891.0))),
        row(489, "PVPzone03", "Warsong Gulch", 3, 0, BG_WDT),
    ]


AREA_FIELDS = [("string",), ("string",), ("int", 16), ("int", 16)]
# Zones 1 (west), 2 (east); 1's subzones 10, 11; 99 a sea "zone"; 98 a tiny
# subzone too small to outline.
# 3 is a lake-like zone ringed by 2 (a closed border); 4 meets 1 and 2 (a
# three-way junction).
AREAS = {1: (0, "Westfall"), 2: (0, "Duskwood"), 3: (0, "Deadwind"), 4: (0, "Redridge"),
         10: (1, "Moonbrook"), 11: (1, "Sentinel Hill"), 99: (0, "The Great Sea"), 98: (2, "Tiny")}


def area_rows() -> list[tuple[int, list]]:
    return [(a, ["Zone", name, 0, parent]) for a, (parent, name) in sorted(AREAS.items())]


def world_terrain(seed: int = 7):
    """Map 0: a 5x5-tile island (cols 30-34, rows 30-34) with two zones split by
    a wavy line, subzones, and sea along the south. Returns {tile key: chunks}."""
    rnd = random.Random(seed)
    tiles = {}
    for col in range(30, 35):
        for row in range(30, 35):
            chunks = []
            for iy in range(16):
                for ix in range(16):
                    gx, gy = (col - 30) * 16 + ix, (row - 30) * 16 + iy
                    if gy >= 66:  # the southern sea
                        area, z = 99, -40.0
                        heights = [rnd.uniform(-5, 0) for _ in range(145)]
                    else:
                        border = 40 + 6 * math.sin(gy / 7.0)
                        area = 1 if gx < border else 2
                        if area == 1 and gy < 30:
                            area = 10 if gx < 20 else 11
                        if area == 2 and 50 <= gx < 52 and 10 <= gy < 12:
                            area = 98
                        if (gx - 62) ** 2 + (gy - 42) ** 2 < 40:
                            area = 3
                        if gy < 12 and gx >= 34:
                            area = 4
                        z = 20 + 30 * math.sin(gx / 11.0) * math.cos(gy / 9.0)
                        heights = [rnd.uniform(0, 8) for _ in range(145)]
                        if gy >= 62:  # the shore: water, but not open sea
                            z, heights = -1.0, [rnd.uniform(0, 0.4) for _ in range(145)]
                    if rnd.random() < 0.01:
                        heights = None  # a chunk without MCVT
                    chunks.append((ix, iy, area, z, heights))
            tiles[col * 64 + row] = chunks
    return tiles


def build_world(install: str) -> None:
    files: dict[int, bytes] = {}
    files[MAP_DB2] = build_wdc5(MAP_FIELDS, map_rows(), sections=2)
    files[AREATABLE_DB2] = build_wdc5(AREA_FIELDS, area_rows())

    def add_map(wdt_fdid: int, tiles: dict[int, list], fdid_base: int, minimap_color):
        wdt_tiles = {}
        for n, (key, chunks) in enumerate(sorted(tiles.items())):
            adt, mm = fdid_base + 2 * n, fdid_base + 2 * n + 1
            files[adt] = build_adt(chunks)
            files[mm] = build_blp(64, 64, minimap_color(key))
            wdt_tiles[key] = (adt, mm)
        files[wdt_fdid] = build_wdt(wdt_tiles)

    def water(key):
        return lambda bx, by: (((2 + key % 3) << 11) | (10 << 5) | 12, (3 << 11) | ((8 + bx % 4) << 5) | 14)

    add_map(AZEROTH_WDT, world_terrain(), 2000000, water)
    # Kalimdor: few tiles (no borders), all land at one height (flat tiles).
    kalimdor = {c * 64 + r: [(ix, iy, 1, 5.0, [0.0] * 145) for iy in range(16) for ix in range(16)]
                for c in range(10, 13) for r in range(10, 12)}
    add_map(KALIMDOR_WDT, kalimdor, 3000000, water)
    dungeon = {c * 64 + r: [(ix, iy, 0, 0.0, None) for iy in range(16) for ix in range(16)]
               for c in range(20, 22) for r in range(20, 21)}
    add_map(DEADMINES_WDT, dungeon, 4000000, lambda key: lambda bx, by: (0x8410, 0x4208))
    build_casc(install, PRODUCT, VERSION, files)

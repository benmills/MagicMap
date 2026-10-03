"""Minimal read-only CASC reader: files by FileDataID from a local WoW install,
for one product (e.g. wow_classic_beta = WoW Forever).

    store = CascStore("/Applications/World of Warcraft", "wow_classic_beta")
    data = store.read(1349477)  # bytes, or None if it isn't stored locally

Encrypted BLTE chunks are dropped (their bytes are left out).
"""
from __future__ import annotations

import os
import struct
import sys
import zlib


def read_build_info(install: str) -> list[dict[str, str]]:
    """Rows of the install's .build.info, keyed by column name."""
    with open(os.path.join(install, ".build.info"), encoding="utf-8") as f:
        lines = f.read().splitlines()
    cols = [c.split("!")[0] for c in lines[0].split("|")]
    return [dict(zip(cols, line.split("|"))) for line in lines[1:] if line]


def product_info(install: str, product: str) -> dict[str, str]:
    for row in read_build_info(install):
        if row.get("Product") == product:
            return row
    raise SystemExit(f"product {product} not in {install}/.build.info")


def blte_decode(blte: bytes) -> bytes:
    if blte[:4] != b"BLTE":
        raise ValueError("not BLTE")
    header_size = struct.unpack_from(">I", blte, 4)[0]
    if header_size == 0:
        chunks = [blte[8:]]
    else:
        count = struct.unpack(">I", b"\0" + blte[9:12])[0]
        chunks, pos = [], header_size
        for i in range(count):
            comp_size = struct.unpack_from(">I", blte, 12 + i * 24)[0]
            chunks.append(blte[pos:pos + comp_size])
            pos += comp_size
    out = []
    for c in chunks:
        mode, body = c[:1], c[1:]
        if mode == b"N":
            out.append(body)
        elif mode == b"Z":
            out.append(zlib.decompress(body))
        elif mode == b"F":
            out.append(blte_decode(body))
        elif mode == b"E":
            print("encrypted chunk (dropped)", file=sys.stderr)
        else:
            raise ValueError(f"unsupported BLTE mode {mode!r}")
    return b"".join(out)


class CascStore:
    def __init__(self, install: str, product: str):
        self.install = install
        self.product = product
        self.data_dir = os.path.join(install, "Data")
        info = product_info(install, product)
        self.version = info.get("Version", "")
        build_key = info["Build Key"]
        config = self._read_config(build_key)
        self.build_name = config.get("build-name", "")
        self._index = self._read_indices()
        self._enc = self._read_ekey(config["encoding"].split(" ")[1])
        if self._enc is None:
            raise SystemExit("encoding file not in local storage")
        self._parse_encoding_header()
        root_ekey = self._ckey_to_ekey(config["root"])
        root = self._read_ekey(root_ekey) if root_ekey else None
        if root is None:
            raise SystemExit("root not in local storage")
        self._root_data = root
        self._ckeys: dict[int, str | None] = {}

    # --- config + indices ---------------------------------------------------
    def _read_config(self, key: str) -> dict[str, str]:
        path = os.path.join(self.data_dir, "config", key[0:2], key[2:4], key)
        config = {}
        with open(path, encoding="utf-8") as f:
            for line in f:
                k, sep, v = line.rstrip("\n").partition(" = ")
                if sep:
                    config[k] = v
        return config

    def _read_indices(self) -> dict[bytes, tuple[int, int, int]]:
        """First 9 bytes of each EKey -> (archive, offset, size), from the
        newest .idx of each bucket."""
        idx_dir = os.path.join(self.data_dir, "data")
        latest: dict[str, tuple[int, str]] = {}
        for name in os.listdir(idx_dir):
            if len(name) != 14 or not name.lower().endswith(".idx"):
                continue
            try:
                bucket, ver = name[:2].lower(), int(name[2:10], 16)
            except ValueError:
                continue
            if bucket not in latest or ver > latest[bucket][0]:
                latest[bucket] = (ver, os.path.join(idx_dir, name))
        index: dict[bytes, tuple[int, int, int]] = {}
        for _, path in latest.values():
            with open(path, "rb") as f:
                buf = f.read()
            header_hash_size = struct.unpack_from("<I", buf, 0)[0]
            pos = (8 + header_hash_size + 0x0F) & ~0x0F
            entries_size = struct.unpack_from("<I", buf, pos)[0]
            pos += 8
            for i in range(0, entries_size, 18):
                e = buf[pos + i:pos + i + 18]
                key = e[:9]
                loc = (e[9] << 32) | struct.unpack_from(">I", e, 10)[0]
                size = struct.unpack_from("<I", e, 14)[0]
                index.setdefault(key, (loc >> 30, loc & (2**30 - 1), size))
        return index

    def _read_ekey(self, ekey_hex: str) -> bytes | None:
        loc = self._index.get(bytes.fromhex(ekey_hex)[:9])
        if not loc:
            return None
        archive, offset, size = loc
        with open(os.path.join(self.data_dir, "data", f"data.{archive:03d}"), "rb") as f:
            f.seek(offset + 30)  # skip the 30-byte local header
            return blte_decode(f.read(size - 30))

    # --- encoding: CKey -> EKey ---------------------------------------------
    def _parse_encoding_header(self) -> None:
        enc = self._enc
        (self._ck_size, self._ek_size, self._ce_page_kb, _, self._ce_pages, _, _,
         especsize) = struct.unpack_from(">BBHHIIBI", enc, 3)
        self._page_table = 22 + especsize
        self._pages_start = self._page_table + self._ce_pages * 32

    def _ckey_to_ekey(self, ckey_hex: str) -> str | None:
        enc, ckey = self._enc, bytes.fromhex(ckey_hex)
        lo, hi = 0, self._ce_pages - 1
        while lo < hi:  # last page whose first key <= ckey
            mid = (lo + hi + 1) // 2
            if enc[self._page_table + mid * 32:self._page_table + mid * 32 + 16] <= ckey:
                lo = mid
            else:
                hi = mid - 1
        page_size = self._ce_page_kb * 1024
        p = self._pages_start + lo * page_size
        end = p + page_size
        while p < end:
            key_count = enc[p]
            if key_count == 0:
                break
            if enc[p + 6:p + 6 + self._ck_size] == ckey:
                e = p + 6 + self._ck_size
                return enc[e:e + self._ek_size].hex()
            p += 6 + self._ck_size + key_count * self._ek_size
        return None

    # --- root (MFST): FileDataID -> CKey ------------------------------------
    # The root lists millions of files; rather than index them all, each
    # resolve() scans it once for just the IDs asked for.
    def _resolve_root(self, wanted: set[int]) -> None:
        root = self._root_data
        if root[:4] != b"TSFM":
            raise SystemExit("unsupported root format")
        header_size, version = struct.unpack_from("<II", root, 4)
        if header_size == 0x18:
            pos = header_size
        else:
            pos, version = 12, 0
        found = self._ckeys
        while pos < len(root):
            if version >= 2:
                n, locale_flags, f1, f2, f3 = struct.unpack_from("<IIIIB", root, pos)
                content_flags = f1 | f2 | (f3 << 17)
                pos += 17
            else:
                n, content_flags, locale_flags = struct.unpack_from("<III", root, pos)
                pos += 12
            deltas_at = pos
            pos += 4 * n
            ckey_base = pos
            pos += 16 * n
            if not content_flags & 0x10000000:  # named: a name hash per file
                pos += 8 * n
            if not locale_flags & 0x2:  # enUS only
                continue
            fdid = -1
            for i, d in enumerate(struct.unpack_from(f"<{n}i", root, deltas_at)):
                fdid += 1 + d
                if fdid in wanted and fdid not in found:
                    found[fdid] = root[ckey_base + 16 * i:ckey_base + 16 * i + 16].hex()
        for fdid in wanted:
            found.setdefault(fdid, None)

    # --- public ---------------------------------------------------------------
    def resolve(self, fdids) -> None:
        """Look up many files at once (one pass over the root)."""
        wanted = {f for f in fdids if f not in self._ckeys}
        if wanted:
            self._resolve_root(wanted)

    def ckey(self, fdid: int) -> str | None:
        self.resolve([fdid])
        return self._ckeys[fdid]

    def read(self, fdid: int) -> bytes | None:
        ckey = self.ckey(fdid)
        ekey = ckey and self._ckey_to_ekey(ckey)
        return self._read_ekey(ekey) if ekey else None

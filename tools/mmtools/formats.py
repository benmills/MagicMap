"""Readers for the chunked game files the generators use: WDT (which tile is
where), ADT (terrain chunks: area IDs and heights; obj0: building placements),
WMO (buildings: rooms, portals) and BLP (minimap textures).
"""
from __future__ import annotations

import math
import struct
from dataclasses import dataclass
from typing import Iterator


def iter_chunks(buf: bytes) -> Iterator[tuple[bytes, int, int]]:
    """(magic, data offset, size) for each top-level chunk. Magic is in
    reading order (b"MAID"), though the file stores it reversed."""
    pos = 0
    while pos + 8 <= len(buf):
        magic, size = struct.unpack_from("<4sI", buf, pos)
        yield magic[::-1], pos + 8, size
        pos += 8 + size


# --- WDT --------------------------------------------------------------------

@dataclass(frozen=True)
class WdtTile:
    root_adt: int
    obj0: int
    obj1: int
    tex0: int
    lod: int
    map_texture: int
    map_texture_n: int
    minimap: int


def wdt_maid(buf: bytes) -> dict[int, WdtTile]:
    """The MAID chunk: 64x64 entries of 8 FileDataIDs, stored [row][col].
    Returns {col * 64 + row: WdtTile} for tiles with a root ADT or a minimap
    texture."""
    for magic, off, size in iter_chunks(buf):
        if magic == b"MAID":
            ids = struct.unpack_from(f"<{size // 4}I", buf, off)
            tiles = {}
            for i in range(min(4096, len(ids) // 8)):
                e = ids[i * 8:i * 8 + 8]
                if e[0] or e[7]:
                    tiles[(i % 64) * 64 + i // 64] = WdtTile(*e)
            return tiles
    return {}


# --- ADT --------------------------------------------------------------------

@dataclass(frozen=True)
class AdtChunk:
    ix: int
    iy: int
    area: int
    z: float                  # base height
    heights: tuple | None     # the 145 MCVT offsets from z, if present

    @property
    def max_height(self) -> float:
        if self.heights is None:
            return self.z
        return max(self.z, self.z + max(self.heights))


def adt_chunks(buf: bytes) -> Iterator[AdtChunk]:
    """The MCNK terrain chunks (16x16 per tile, ~33 yards each) of a root ADT."""
    for magic, off, size in iter_chunks(buf):
        if magic != b"MCNK" or size < 0x80:
            continue
        d = buf[off:off + size]
        ix, iy = struct.unpack_from("<II", d, 4)
        area = struct.unpack_from("<I", d, 0x34)[0]
        z = struct.unpack_from("<f", d, 0x70)[0]
        mcvt = d.find(b"TVCM", 0x80)
        heights = struct.unpack_from("<145f", d, mcvt + 8) if mcvt >= 0 and mcvt + 8 + 580 <= len(d) else None
        yield AdtChunk(ix, iy, area, z, heights)


@dataclass(frozen=True)
class AdtLiquid:
    ix: int                   # the MCNK chunk it lies in
    iy: int
    liquid_type: int          # LiquidType.db2 ID
    surface: float            # highest point of its surface
    x0: int                   # the 8x8 quads it covers: x0, y0, width, height
    y0: int
    w: int
    h: int
    exists: bytes | None      # w*h bits (row-major, LSB first) of quads it covers; None: all of them

    def covers(self, qx: int, qy: int) -> bool:
        x, y = qx - self.x0, qy - self.y0
        if not (0 <= x < self.w and 0 <= y < self.h):
            return False
        if self.exists is None:
            return True
        i = y * self.w + x
        return bool(self.exists[i >> 3] >> (i & 7) & 1)


def adt_liquids(buf: bytes) -> Iterator[AdtLiquid]:
    """The liquid layers (MH2O) of a root ADT, one per chunk and layer."""
    for magic, off, size in iter_chunks(buf):
        if magic != b"MH2O" or size < 256 * 12:
            continue
        for i in range(256):
            inst_off, layers, _ = struct.unpack_from("<III", buf, off + i * 12)
            if not inst_off or not layers:
                continue
            for k in range(layers):
                p = off + inst_off + k * 24
                if p + 24 > off + size:
                    break
                ltype, _, _lo, hi, x0, y0, w, h, ex_off, _ = struct.unpack_from("<HHffBBBBII", buf, p)
                exists = buf[off + ex_off:off + ex_off + (w * h + 7) // 8] if ex_off else None
                yield AdtLiquid(i % 16, i // 16, ltype, hi, x0, y0, w, h, exists)


@dataclass(frozen=True)
class Modf:
    """A building (WMO) placed on the map: one MODF entry of an obj0 ADT. File space: x and z
    over TILE_YARDS are tile col and row, y is up (docs/decisions/0008-interiors.md)."""
    fid: int                  # the WMO root's FileDataID
    uid: int                  # unique per map: a building spanning tiles is listed in each
    pos: tuple                # (x, y, z)
    rot: tuple                # degrees (x, y, z)
    mn: tuple                 # box min, file space
    mx: tuple                 # box max
    flags: int
    scale: int                # 1024 = 1


def adt_modf(buf: bytes) -> list[Modf]:
    """The building placements (MODF, 64 bytes an entry) of an obj0 ADT."""
    out = []
    for magic, off, size in iter_chunks(buf):
        if magic == b"MODF":
            for i in range(size // 64):
                v = struct.unpack_from("<II3f3f3f3fHHHH", buf, off + i * 64)
                out.append(Modf(v[0], v[1], v[2:5], v[5:8], v[8:11], v[11:14], v[14], v[17]))
    return out


# --- WMO --------------------------------------------------------------------

@dataclass(frozen=True)
class WmoGroupInfo:
    flags: int                # 0x2000 indoor, 0x8 outdoor
    mn: tuple                 # box min, the building's own (x, y, z), z up
    mx: tuple


@dataclass(frozen=True)
class WmoRoot:
    wmo_id: int               # MOHD +32: WMOAreaTable's and WMOMinimapTexture's key
    groups: list              # MOGI: WmoGroupInfo per room (group)
    group_fids: list          # GFID: the rooms' files, the first len(groups) of them LOD 0
    portals: list             # MOPT: (start vertex, count, plane a, b, c, d)
    portal_refs: list         # MOPR: (portal, group, side)


def wmo_root(buf: bytes) -> WmoRoot:
    ch = {m: (o, s) for m, o, s in iter_chunks(buf)}

    def rows(magic, fmt, n):
        o, s = ch.get(magic, (0, 0))
        return [struct.unpack_from(fmt, buf, o + k * n) for k in range(s // n)]

    wmo_id = struct.unpack_from("<I", buf, ch[b"MOHD"][0] + 32)[0]
    groups = [WmoGroupInfo(g[0], g[1:4], g[4:7]) for g in rows(b"MOGI", "<I6fi", 32)]
    fids = [f[0] for f in rows(b"GFID", "<I", 4)]
    return WmoRoot(wmo_id, groups, fids, rows(b"MOPT", "<HH4f", 20), [r[:3] for r in rows(b"MOPR", "<HHhH", 8)])


@dataclass(frozen=True)
class WmoGroup:
    group_id: int             # MOGP +56: global, WMOAreaTable keys on it
    portal_start: int         # its portal refs: MOPR[portal_start:portal_start + portal_count]
    portal_count: int
    floor: float | None       # the room's real floor (its own z): None, no floor triangles


def group_floor(buf: bytes) -> float | None:
    """A MOGP's real floor (its own z), from its upward-facing triangles (normal z > 0.7; collision-only ones,
    MOPY material 0xFF, skipped): indoors their area-weighted median; open to the sky (flag 0x40: Orgrimmar's
    streets, cliffs and roofs in the same room) the lower quartile of the lowest of them over each 4-yd cell,
    the ground the cliffs and roofs stand on. buf: the MOGP's data; its sub-chunks follow its 68-byte header."""
    sky = struct.unpack_from("<I", buf, 8)[0] & 0x40
    sub = buf[68:]
    ch = {m: sub[o:o + s] for m, o, s in iter_chunks(sub)}
    if b"MOVT" not in ch or b"MOVI" not in ch:
        return None
    v = list(struct.iter_unpack("<3f", ch[b"MOVT"]))
    idx = struct.unpack(f"<{len(ch[b'MOVI']) // 2}H", ch[b"MOVI"])
    mat = ch.get(b"MOPY", b"")
    tris, low = [], {}  # low: 4-yd cell -> the lowest upward z over its centre
    for t in range(len(idx) // 3):
        if mat and mat[t * 2 + 1] == 0xFF:
            continue
        a, b, c = v[idx[3 * t]], v[idx[3 * t + 1]], v[idx[3 * t + 2]]
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        n = (nx * nx + ny * ny + nz * nz) ** 0.5
        if not (n > 0 and nz / n > 0.7):
            continue
        tris.append(((a[2] + b[2] + c[2]) / 3, n / 2))
        if not sky:
            continue
        for i in range(math.floor(min(a[0], b[0], c[0]) / 4), math.floor(max(a[0], b[0], c[0]) / 4) + 1):
            for j in range(math.floor(min(a[1], b[1], c[1]) / 4), math.floor(max(a[1], b[1], c[1]) / 4) + 1):
                px, py = (i + 0.5) * 4 - a[0], (j + 0.5) * 4 - a[1]
                s, r = (px * vy - vx * py) / nz, (ux * py - px * uy) / nz  # /: never 0 (nz > 0.7 n)
                if s >= 0 and r >= 0 and s + r <= 1 and a[2] + s * uz + r * vz < low.get((i, j), math.inf):
                    low[i, j] = a[2] + s * uz + r * vz
    if low:
        return sorted(low.values())[(len(low) - 1) // 4]
    if not tris:
        return None
    tris.sort()
    half, acc = sum(w for _, w in tris) / 2, 0
    for z, w in tris:
        acc += w
        if acc >= half:
            return z


def wmo_group(buf: bytes) -> WmoGroup | None:
    """A room file's MOGP header and real floor."""
    for magic, off, size in iter_chunks(buf):
        if magic == b"MOGP":
            ps, pc = struct.unpack_from("<HH", buf, off + 36)
            return WmoGroup(struct.unpack_from("<I", buf, off + 56)[0], ps, pc, group_floor(buf[off:off + size]))
    return None


# --- BLP --------------------------------------------------------------------

def blp_edge_colors(blp: bytes, sides: dict[str, bool]) -> list[tuple[float, float, float]]:
    """Average colour of DXT blocks along the given sides of a BLP2 texture
    (every 4th block). Each sample is the mean of the block's two endpoint
    colours, 0..1."""
    if len(blp) < 28:
        return []
    enc, _alpha_depth, alpha_type, _mips, w, h = struct.unpack_from("<BBBBII", blp, 8)
    if enc != 2 or w < 16 or h < 16:
        return []
    off = struct.unpack_from("<I", blp, 20)[0]
    block_bytes = 8 if alpha_type in (0, 1) else 16  # DXT1 vs DXT3/5
    color_at = 0 if block_bytes == 8 else 8
    bw, bh = w // 4, h // 4
    out = []

    def sample(bx: int, by: int) -> None:
        c0, c1 = struct.unpack_from("<HH", blp, off + (by * bw + bx) * block_bytes + color_at)
        rgb = [(((c >> 11) & 31) / 31, ((c >> 5) & 63) / 63, (c & 31) / 31) for c in (c0, c1)]
        out.append(tuple((rgb[0][k] + rgb[1][k]) / 2 for k in range(3)))

    for i in range(0, bw, 4):
        if sides.get("left"):
            sample(0, i)
        if sides.get("right"):
            sample(bw - 1, i)
        if sides.get("top"):
            sample(i, 0)
        if sides.get("bottom"):
            sample(i, bh - 1)
    return out


# --- DXT (BLP2 encoding 2: DXT1 / DXT3 / DXT5) ---------------------------------
# Each 4x4 texel block holds two RGB565 endpoint colours and 16 2-bit indices
# into a 4-colour palette (DXT1 with c0 <= c1: 3 colours + transparent black).
# DXT3/5 put 8 bytes of alpha first, then the same colour block (always 4
# colours). Alpha is ignored here: minimap tiles are opaque.

RGB = tuple[float, float, float]


def rgb565(c: int) -> RGB:
    return ((c >> 11) & 31) / 31, ((c >> 5) & 63) / 63, (c & 31) / 31


def dxt_palette(c0: int, c1: int, four: bool) -> list[RGB]:
    a, b = rgb565(c0), rgb565(c1)
    if four:
        return [a, b, tuple((2 * x + y) / 3 for x, y in zip(a, b)), tuple((x + 2 * y) / 3 for x, y in zip(a, b))]
    return [a, b, tuple((x + y) / 2 for x, y in zip(a, b)), (0.0, 0.0, 0.0)]


def _index_weights() -> list[tuple[float, float, float, float]]:
    """Per index byte (4 texels): how much of c0 and c1 those texels hold, in
    4-colour mode and in 3-colour mode (index 3 = black)."""
    out = []
    for byte in range(256):
        w = [0.0, 0.0, 0.0, 0.0]
        for k in range(4):
            i = (byte >> (2 * k)) & 3
            w[0] += (1, 0, 2 / 3, 1 / 3)[i]
            w[1] += (0, 1, 1 / 3, 2 / 3)[i]
            w[2] += (1, 0, 0.5, 0)[i]
            w[3] += (0, 1, 0.5, 0)[i]
        out.append(tuple(w))
    return out


_WEIGHTS = _index_weights()


@dataclass(frozen=True)
class DxtImage:
    """One mip level of a DXT-compressed BLP2, decoded on demand by block."""
    data: bytes
    offset: int
    width: int
    height: int
    block_bytes: int    # 8 (DXT1) or 16 (DXT3/5)

    @property
    def blocks_wide(self) -> int:
        return max(1, self.width // 4)

    @property
    def blocks_high(self) -> int:
        return max(1, self.height // 4)

    def _color_block(self, bx: int, by: int) -> tuple[int, int, int]:
        pos = self.offset + (by * self.blocks_wide + bx) * self.block_bytes + (self.block_bytes - 8)
        return struct.unpack_from("<HHI", self.data, pos)

    def block(self, bx: int, by: int) -> list[RGB]:
        """The 16 texels of block (bx, by), row by row."""
        c0, c1, idx = self._color_block(bx, by)
        pal = dxt_palette(c0, c1, self.block_bytes == 16 or c0 > c1)
        return [pal[(idx >> (2 * k)) & 3] for k in range(16)]

    def block_mean(self, bx: int, by: int) -> RGB:
        """Mean colour of block (bx, by): exactly a 4x4 box filter, without
        decoding the texels."""
        c0, c1, idx = self._color_block(bx, by)
        w0 = w1 = 0.0
        if self.block_bytes == 16 or c0 > c1:
            for s in (0, 8, 16, 24):
                w = _WEIGHTS[(idx >> s) & 255]
                w0 += w[0]
                w1 += w[1]
        else:
            for s in (0, 8, 16, 24):
                w = _WEIGHTS[(idx >> s) & 255]
                w0 += w[2]
                w1 += w[3]
        w0 /= 16 * 31
        w1 /= 16 * 31
        g0, g1 = w0 * 31 / 63, w1 * 31 / 63
        return (((c0 >> 11) & 31) * w0 + ((c1 >> 11) & 31) * w1,
                ((c0 >> 5) & 63) * g0 + ((c1 >> 5) & 63) * g1,
                (c0 & 31) * w0 + (c1 & 31) * w1)

    def texels(self) -> list[list[RGB]]:
        """The whole image, rows of texels (slow in pure Python for 512x512:
        prefer block_means)."""
        rows = [[(0.0, 0.0, 0.0)] * self.width for _ in range(self.height)]
        for by in range(self.blocks_high):
            for bx in range(self.blocks_wide):
                for k, c in enumerate(self.block(bx, by)):
                    y, x = by * 4 + k // 4, bx * 4 + k % 4
                    if y < self.height and x < self.width:
                        rows[y][x] = c
        return rows

    def rgb8(self) -> bytes:
        """The whole image as 8-bit RGB, rows top first (for exporting)."""
        out = bytearray(self.width * self.height * 3)
        for by in range(self.blocks_high):
            for bx in range(self.blocks_wide):
                c0, c1, idx = self._color_block(bx, by)
                pal = [bytes(round(v * 255) for v in c)
                       for c in dxt_palette(c0, c1, self.block_bytes == 16 or c0 > c1)]
                for k in range(16):
                    y, x = by * 4 + k // 4, bx * 4 + k % 4
                    if y < self.height and x < self.width:
                        p = (y * self.width + x) * 3
                        out[p:p + 3] = pal[(idx >> (2 * k)) & 3]
        return bytes(out)

    def block_means(self) -> list[list[RGB]]:
        """The image at 1/4 size: rows of block means."""
        return [[self.block_mean(bx, by) for bx in range(self.blocks_wide)] for by in range(self.blocks_high)]


def box_downsample(grid: list[list[RGB]], size: int) -> list[list[RGB]]:
    """A size x size box-filtered copy of a square image whose side is a
    multiple of size."""
    f = max(1, len(grid) // size)
    out = []
    for y in range(0, len(grid) - f + 1, f):
        row = []
        for x in range(0, len(grid[0]) - f + 1, f):
            r = g = b = 0.0
            for yy in range(y, y + f):
                for c in grid[yy][x:x + f]:
                    r += c[0]
                    g += c[1]
                    b += c[2]
            n = f * f
            row.append((r / n, g / n, b / n))
        out.append(row)
    return out


def blp_dxt(blp: bytes, min_size: int | None = None) -> DxtImage | None:
    """A DXT BLP2's full-size image, or with min_size its smallest mip level
    at least that wide (mip 0 if the file has no mipmaps); None if it isn't
    a DXT BLP2."""
    if len(blp) < 148 or blp[:4] != b"BLP2":
        return None
    enc, _alpha_depth, alpha_type, has_mips, w, h = struct.unpack_from("<BBBBII", blp, 8)
    if enc != 2:
        return None
    offsets = struct.unpack_from("<16I", blp, 20)
    sizes = struct.unpack_from("<16I", blp, 84)
    block_bytes = 8 if alpha_type in (0, 1) else 16
    level = 0
    if has_mips and min_size is not None:
        while (level + 1 < 16 and offsets[level + 1] and sizes[level + 1]
               and max(1, w >> (level + 1)) >= max(min_size, 4)):
            level += 1
    lw, lh = max(1, w >> level), max(1, h >> level)
    need = max(1, lw // 4) * max(1, lh // 4) * block_bytes
    if offsets[level] + need > len(blp):
        return None
    return DxtImage(blp, offsets[level], lw, lh, block_bytes)

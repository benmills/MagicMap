"""Readers for the chunked game files the generators use: WDT (which tile is
where), ADT (terrain chunks: area IDs and heights) and BLP (minimap textures).
"""
from __future__ import annotations

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
    def mean_height(self) -> float | None:
        return None if self.heights is None else self.z + sum(self.heights) / 145

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

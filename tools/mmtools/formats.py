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

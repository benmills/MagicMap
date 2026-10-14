"""Uncompressed 32-bit TGA, the texture format an addon can ship and load.

Rows are stored bottom-up (the TGA default, image descriptor bit 5 clear),
which every TGA loader handles; the reader honours either origin.
"""
from __future__ import annotations

import struct

Pixel = tuple[int, int, int, int]  # r, g, b, a: 0..255


def write_tga(w: int, h: int, rows: list[list[Pixel]]) -> bytes:
    """rows: h rows of w pixels, top row first."""
    head = struct.pack("<BBB HHB HHHH BB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)  # 8 alpha bits, bottom-left
    body = bytearray()
    for row in reversed(rows):
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    return head + bytes(body)


def read_tga(data: bytes) -> tuple[int, int, list[list[Pixel]]]:
    """(w, h, rows top row first) of an uncompressed 24/32-bit TGA."""
    idlen, cmap, kind = data[0], data[1], data[2]
    w, h, bpp, desc = struct.unpack_from("<HHBB", data, 12)
    if cmap or kind != 2 or bpp not in (24, 32):
        raise ValueError("not an uncompressed true-colour TGA")
    n, pos = bpp // 8, 18 + idlen
    rows = []
    for _ in range(h):
        row = []
        for x in range(w):
            p = data[pos + x * n:pos + x * n + n]
            row.append((p[2], p[1], p[0], p[3] if n == 4 else 255))
        rows.append(row)
        pos += w * n
    if not desc & 0x20:  # bottom-left origin: stored bottom row first
        rows.reverse()
    if desc & 0x10:  # right-to-left
        rows = [r[::-1] for r in rows]
    return w, h, rows

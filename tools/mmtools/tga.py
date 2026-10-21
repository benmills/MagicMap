"""Uncompressed 32-bit TGA, the texture format an addon can ship and load.

Rows are stored bottom-up (the TGA default, image descriptor bit 5 clear),
which every TGA loader handles.
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

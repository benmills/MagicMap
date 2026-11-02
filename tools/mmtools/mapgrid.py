"""What the map-art tools share: a Blizzard texture's pixels, and the map's chunks as a boolean grid (64 tiles of 16 chunks a side)."""
from __future__ import annotations

import io
import struct
from collections import deque

import numpy as np
from PIL import Image

KINDS = ("flat-land", "patch-edge", "seam")
CH = 16                # chunks a tile side
GRID = 64 * CH


def blp_rgba(b: bytes) -> Image.Image:
    enc, _, _, _, w, h = struct.unpack_from("<BBBBII", b, 8)
    if enc == 3:
        off = struct.unpack_from("<I", b, 20)[0]
        return Image.frombytes("RGBA", (w, h), b[off:off + w * h * 4], "raw", "BGRA")
    return Image.open(io.BytesIO(b)).convert("RGBA")


def places(issues: list, decisions: dict, inst: int) -> np.ndarray:
    """The accepted issues' chunks on inst."""
    t = np.zeros((GRID, GRID), bool)
    for i in issues:
        if i["inst"] != inst or i["kind"] not in KINDS or decisions.get(i["id"], {}).get("status") != "accepted":
            continue
        m = i.get("mask")
        if m:
            cells, pos, on = np.zeros(m["h"] * m["w"], bool), 0, False
            for n in m["rle"]:
                cells[pos:pos + n] = on
                pos, on = pos + n, not on
            t[m["y0"]:m["y0"] + m["h"], m["x0"]:m["x0"] + m["w"]] |= cells.reshape(m["h"], m["w"])
        else:
            c0, r0, c1, r1 = (int(round(v * CH)) for v in i["bbox"])
            t[max(0, r0 - 2):r1 + 2, max(0, c0 - 2):c1 + 2] = True  # an edge's box is a line: 2 chunks each side
    return t


def grow(t: np.ndarray, n: int) -> np.ndarray:
    for _ in range(n):
        g = t.copy()
        g[1:] |= t[:-1]
        g[:-1] |= t[1:]
        g[:, 1:] |= t[:, :-1]
        g[:, :-1] |= t[:, 1:]
        t = g
    return t


def components(t: np.ndarray) -> list[tuple[slice, slice]]:
    """The boxes of t's 8-connected parts."""
    seen, out = np.zeros_like(t), []
    h, w = t.shape
    for y0, x0 in zip(*np.nonzero(t)):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        q, ys, xs = deque([(y0, x0)]), [], []
        while q:
            y, x = q.popleft()
            ys.append(y)
            xs.append(x)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and t[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
        out.append((slice(min(ys), max(ys) + 1), slice(min(xs), max(xs) + 1)))
    return out

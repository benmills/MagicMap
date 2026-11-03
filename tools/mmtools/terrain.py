"""A continent's tiles and terrain, for the tools that paint over them (tools/gen_sea.py)."""
from __future__ import annotations

import os
import struct

import numpy as np
from PIL import Image

from mmtools.formats import adt_chunks, adt_liquids, adt_modf, iter_chunks, wdt_maid
from mmtools.mapgrid import blp_rgba

WDT = {0: 775971, 1: 782779, 2991: 7198644}  # 2991: Zephras Isle (most of its ADTs encrypted)
TILE = 1600 / 3


def layer_alpha(mcal: bytes, off: int, size: int, flags: int) -> np.ndarray:
    d = mcal[off:off + size]
    if flags & 0x200:  # compressed
        o, p = bytearray(), 0
        while len(o) < 4096 and p < len(d):
            c, p = d[p], p + 1
            n = c & 0x7f
            if c & 0x80:
                o += d[p:p + 1] * n
                p += 1
            else:
                o += d[p:p + n]
                p += n
        a = np.frombuffer(bytes(o[:4096]).ljust(4096, b"\0"), np.uint8)
    elif len(d) >= 4096:
        a = np.frombuffer(d[:4096], np.uint8)
    else:
        b = np.frombuffer(d[:2048].ljust(2048, b"\0"), np.uint8)
        a = np.empty(4096, np.uint8)
        a[::2], a[1::2] = (b & 15) * 17, (b >> 4) * 17
    return a.reshape(64, 64).astype(np.float32) / 255


def painted(buf: bytes) -> np.ndarray:
    """A tex0 ADT's dominant texture (a FileDataID), 8 x 8 a chunk."""
    out, mdid, i = np.zeros((128, 128), np.int64), [], 0
    for m, off, size in iter_chunks(buf):
        if m == b"MDID":
            mdid = list(struct.unpack_from(f"<{size // 4}I", buf, off))
        elif m == b"MCNK":
            ly, mcal = [], b""
            for m2, o2, s2 in iter_chunks(buf[off:off + size]):
                if m2 == b"MCLY":
                    ly = [struct.unpack_from("<IIII", buf, off + o2 + k * 16) for k in range(s2 // 16)]
                elif m2 == b"MCAL":
                    mcal = buf[off + o2:off + o2 + s2]
            if ly:
                w, rest = np.ones((64, 64, len(ly)), np.float32), np.ones((64, 64), np.float32)
                for k in range(len(ly) - 1, 0, -1):
                    nx = ly[k + 1][2] if k + 1 < len(ly) else len(mcal)
                    a = layer_alpha(mcal, ly[k][2], nx - ly[k][2], ly[k][1])
                    w[:, :, k], rest = rest * a, rest * (1 - a)
                w[:, :, 0] = rest
                ids = np.array([mdid[l[0]] if l[0] < len(mdid) else 0 for l in ly])
                out[(i // 16) * 8:(i // 16) * 8 + 8, (i % 16) * 8:(i % 16) * 8 + 8] = ids[w.reshape(8, 8, 8, 8, -1).mean((1, 3)).argmax(-1)]
            i += 1
    return out


class Ground:
    """A continent's tiles and terrain, read when asked."""

    def __init__(self, src, inst: int, tiles: dict, sea: dict, cache: str):
        self.src, self.inst, self.tiles, self.sea, self.cache = src, inst, tiles, sea, cache
        self.maid = wdt_maid(src.read(WDT[inst]))

    def art(self, key: int, n: int) -> np.ndarray | None:
        if key not in self.tiles or key in self.sea:
            return None
        return np.asarray(blp_rgba(self.src.read(self.tiles[key])).convert("RGB").resize((n, n), Image.LANCZOS), np.float32)

    def buildings(self, key: int) -> np.ndarray:
        """The chunks of a tile with a building (WMO) on them, 16 x 16."""
        path = os.path.join(self.cache, f"{self.inst}_{key}.built.npy")
        if os.path.exists(path):
            return np.load(path)
        out = np.zeros((16, 16), bool)
        t = self.maid.get(key)
        b = t and t.obj0 and self.src.read(t.obj0)
        for m in adt_modf(b) if b else ():
            cx = lambda v: (v / TILE - key // 64) * 16
            cy = lambda v: (v / TILE - key % 64) * 16
            out[max(0, int(cy(m.mn[2]))):max(0, int(cy(m.mx[2])) + 1), max(0, int(cx(m.mn[0]))):max(0, int(cx(m.mx[0])) + 1)] = True
        np.save(path, out)
        return out

    def heights_and_water(self, key: int) -> tuple[np.ndarray, np.ndarray]:
        """Heights and the water's surface (-inf: none), 128 x 128."""
        path = os.path.join(self.cache, f"{self.inst}_{key}.water.npy")
        h, _ = self.terrain(key)
        if os.path.exists(path):
            return h, np.load(path)
        w = np.full((16, 16), -np.inf, np.float32)
        t = self.maid.get(key)
        b = t and t.root_adt and self.src.read(t.root_adt)
        for l in adt_liquids(b) if b else ():
            w[l.iy, l.ix] = max(w[l.iy, l.ix], l.surface)
        w = w.repeat(8, 0).repeat(8, 1)
        np.save(path, w)
        return h, w

    def terrain(self, key: int) -> tuple[np.ndarray, np.ndarray]:
        """Heights and painted textures, 128 x 128."""
        path = os.path.join(self.cache, f"{self.inst}_{key}.npz")
        if os.path.exists(path):
            z = np.load(path)
            return z["h"], z["t"]
        h, tex = np.full((128, 128), np.nan, np.float32), np.zeros((128, 128), np.int64)
        t = self.maid.get(key)
        b = t and t.root_adt and self.src.read(t.root_adt)
        for c in adt_chunks(b) if b else ():
            if c.heights is not None:
                for y in range(8):
                    for x in range(8):
                        h[c.iy * 8 + y, c.ix * 8 + x] = c.z + c.heights[y * 17 + x]
        b0 = t and t.tex0 and self.src.read(t.tex0)
        if b0:
            tex = painted(b0)
        os.makedirs(self.cache, exist_ok=True)
        np.savez_compressed(path, h=h, t=tex)
        return h, tex

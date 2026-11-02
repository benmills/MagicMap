"""Writing a BLP2 the client loads: DXT1 (4 bits a pixel, no alpha) or DXT5 (8 bits a pixel, soft alpha), every mip level.

An addon's texture can be BLP as well as TGA (Interface\\AddOns\\MagicMap\\Textures\\Name, no
extension). DXT1 is an eighth of a 32-bit TGA's size, and flat colours (a stylised map) survive
it: a block of two colours is exact, one of one colour is within a texel of a step (the 565
endpoints bracket it, the in-between palette entries take up the rest: the map's backdrop colour
must come out as itself, or the picture's sea shows as a box on it).

DXT1 is pure Python: a 2048x2048 picture takes ~10 s, blocks of the same pixels encoded once. DXT5 (write_blp_dxt5,
pictures with a soft edge: the AI repaints) is numpy, a 512x512 picture and its mips in well under a second.
"""
from __future__ import annotations

import struct

import numpy as np

Rgb = bytes  # w * h * 3, rows top first


def _e5(q: int) -> int:
    return (q << 3) | (q >> 2)


def _e6(q: int) -> int:
    return (q << 2) | (q >> 4)


E5 = [_e5(q) for q in range(32)]
E6 = [_e6(q) for q in range(64)]


def _unpack(c: int) -> tuple[int, int, int]:
    return E5[c >> 11], E6[(c >> 5) & 63], E5[c & 31]


def _palette(c0: int, c1: int) -> list[tuple[float, float, float]]:
    a, b = _unpack(c0), _unpack(c1)
    return [a, b, tuple((2 * a[k] + b[k]) / 3 for k in range(3)), tuple((a[k] + 2 * b[k]) / 3 for k in range(3))]


def _indices(px: list[tuple[int, int, int]], c0: int, c1: int) -> int:
    pal = _palette(c0, c1)
    out = 0
    for i, (r, g, b) in enumerate(px):
        best, bi = 1e18, 0
        for j, (pr, pg, pb) in enumerate(pal):
            d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
            if d < best:
                best, bi = d, j
        out |= bi << (2 * i)
    return out


def _bracket(v: int, n: int, expand: list[int]) -> tuple[int, int]:
    """The endpoint steps (high, low) either side of 0..255 value v, for n levels."""
    q = v * (n - 1) // 255
    while q > 0 and expand[q] > v:
        q -= 1
    return min(n - 1, q + 1), q


def encode_block(px: list[tuple[int, int, int]]) -> bytes:
    lo = tuple(min(p[k] for p in px) for k in range(3))
    hi = tuple(max(p[k] for p in px) for k in range(3))
    if lo != hi:
        axis = tuple(hi[k] - lo[k] for k in range(3))
        proj = [sum((p[k] - lo[k]) * axis[k] for k in range(3)) for p in px]
        a, b = px[proj.index(min(proj))], px[proj.index(max(proj))]
        a, b = (tuple(a[k] + (b[k] - a[k]) // 16 for k in range(3)),  # inset: the extremes need not be hit exactly
                tuple(b[k] - (b[k] - a[k]) // 16 for k in range(3)))
        c0 = (round(a[0] * 31 / 255) << 11) | (round(a[1] * 63 / 255) << 5) | round(a[2] * 31 / 255)
        c1 = (round(b[0] * 31 / 255) << 11) | (round(b[1] * 63 / 255) << 5) | round(b[2] * 31 / 255)
        if c0 != c1:
            if c0 < c1:
                c0, c1 = c1, c0
            return struct.pack("<HHI", c0, c1, _indices(px, c0, c1))
    v = px[0] if lo == hi else tuple(sum(p[k] for p in px) // 16 for k in range(3))
    (r1, r0), (g1, g0), (b1, b0) = _bracket(v[0], 32, E5), _bracket(v[1], 64, E6), _bracket(v[2], 32, E5)
    c0, c1 = (r1 << 11) | (g1 << 5) | b1, (r0 << 11) | (g0 << 5) | b0
    if c0 == c1:
        return struct.pack("<HHI", c0, c0, 0)
    return struct.pack("<HHI", c0, c1, _indices(px, c0, c1))


def encode_dxt1(w: int, h: int, rgb: Rgb) -> bytes:
    """The image as DXT1 blocks (a side under 4: its last texel repeated)."""
    out, memo = bytearray(), {}
    for by in range((h + 3) // 4):
        ys = [min(h - 1, by * 4 + k) for k in range(4)]
        for bx in range((w + 3) // 4):
            xs = [min(w - 1, bx * 4 + k) for k in range(4)]
            key = b"".join(bytes(rgb[(y * w + x) * 3:(y * w + x) * 3 + 3]) for y in ys for x in xs)
            blk = memo.get(key)
            if blk is None:
                blk = memo[key] = encode_block([(key[i], key[i + 1], key[i + 2]) for i in range(0, 48, 3)])
            out += blk
    return bytes(out)


def _blp2(w: int, h: int, flags: tuple[int, int, int, int], datas: list[bytes]) -> bytes:
    """The file: flags are its encoding (2: DXT), alpha depth, alpha type (0: DXT1, 7: DXT5) and has-mips (1)."""
    offset = 148 + 1024  # the header, then the (unused) 256-colour palette every BLP2 carries
    offsets, sizes = [0] * 16, [0] * 16
    for i, d in enumerate(datas):
        offsets[i], sizes[i] = offset, len(d)
        offset += len(d)
    head = b"BLP2" + struct.pack("<IBBBBII", 1, *flags, w, h) + struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    return head + bytes(1024) + b"".join(datas)


def write_blp(levels: list[tuple[int, int, Rgb]]) -> bytes:
    """A BLP2 of DXT1 from levels[0] (w, h, rgb) and each half-size mip after it down to 1x1."""
    return _blp2(levels[0][0], levels[0][1], (2, 0, 0, 1), [encode_dxt1(*lv) for lv in levels])


_DXT5 = np.dtype([("a0", "u1"), ("a1", "u1"), ("ai", "u1", 6), ("c0", "<u2"), ("c1", "<u2"), ("ci", "<u4")])
_E5, _E6 = np.array(E5, np.float32), np.array(E6, np.float32)


def _to_565(v: np.ndarray) -> np.ndarray:
    v = np.clip(v, 0, 255)
    return (np.rint(v[..., 0] * 31 / 255).astype(np.uint32) << 11) | (np.rint(v[..., 1] * 63 / 255).astype(np.uint32) << 5) | np.rint(v[..., 2] * 31 / 255).astype(np.uint32)


def _from_565(c: np.ndarray) -> np.ndarray:
    return np.stack((_E5[c >> 11], _E6[(c >> 5) & 63], _E5[c & 31]), -1)


def encode_dxt5(rgba: np.ndarray) -> bytes:
    """h x w x 4 uint8 as DXT5 blocks (a side not a multiple of 4: its last texel repeated). A block's colour line is
    fitted to the pixels that show (a clear pixel's colour doesn't matter), so a soft edge's colours keep their fit."""
    h, w = rgba.shape[:2]
    p = np.pad(rgba, ((0, -h % 4), (0, -w % 4), (0, 0)), "edge")
    px = p.reshape(p.shape[0] // 4, 4, p.shape[1] // 4, 4, 4).swapaxes(1, 2).reshape(-1, 16, 4)
    out = np.zeros(len(px), _DXT5)

    # Alpha: the block's extremes, exact (so 0 and 255 stay), 6 steps between.
    a = px[..., 3].astype(np.float32)
    a0, a1 = a.max(1), a.min(1)
    pal = np.stack([a0, a1] + [((7 - k) * a0 + k * a1) / 7 for k in range(1, 7)], 1)
    ai = np.abs(a[:, :, None] - pal[:, None, :]).argmin(2).astype(np.uint64)
    bits = (ai << (np.uint64(3) * np.arange(16, dtype=np.uint64))).sum(1, dtype=np.uint64)
    out["a0"], out["a1"] = a0, a1
    out["ai"] = np.frombuffer(bits.astype("<u8").tobytes(), np.uint8).reshape(-1, 8)[:, :6]

    # Colour: the principal axis of the pixels, by their alpha (none shows: all alike), its extremes inset.
    rgb = px[..., :3].astype(np.float32)
    wt = np.where(a0[:, None] > 0, a / 255, 1.0).astype(np.float32)
    total = wt.sum(1, keepdims=True)
    mean = (rgb * wt[..., None]).sum(1) / total
    d = rgb - mean[:, None]
    cov = np.einsum("nki,nkj,nk->nij", d, d, wt)
    axis = np.full((len(px), 3), 0.577, np.float32) + np.array((0.01, 0, -0.01), np.float32)
    for _ in range(6):
        axis = np.einsum("nij,nj->ni", cov, axis)
        axis /= np.maximum(np.linalg.norm(axis, axis=1, keepdims=True), 1e-6)
    t = np.einsum("nki,ni->nk", d, axis)
    seen = wt > 0
    lo, hi = np.where(seen, t, np.inf).min(1), np.where(seen, t, -np.inf).max(1)
    inset = (hi - lo) / 16
    c0 = _to_565(mean + axis * (hi - inset)[:, None])
    c1 = _to_565(mean + axis * (lo + inset)[:, None])
    swap = c0 < c1  # c0 > c1: four colours (BC3 always means that; some drivers look)
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    e0, e1 = _from_565(c0), _from_565(c1)
    cpal = np.stack((e0, e1, (2 * e0 + e1) / 3, (e0 + 2 * e1) / 3), 1)
    ci = ((rgb[:, :, None] - cpal[:, None]) ** 2).sum(3).argmin(2).astype(np.uint32)
    ci[c0 == c1] = 0
    out["c0"], out["c1"] = c0, c1
    out["ci"] = (ci << (np.uint32(2) * np.arange(16, dtype=np.uint32))).sum(1, dtype=np.uint32)
    return out.tobytes()


def half(rgba: np.ndarray) -> np.ndarray:
    """The next mip: 2 x 2 means, colour by alpha (what's clear must not bleed into what shows); a side of 1 stays."""
    h, w = rgba.shape[:2]
    fy, fx = (2 if h > 1 else 1), (2 if w > 1 else 1)
    v = rgba.astype(np.float64).reshape(h // fy, fy, w // fx, fx, 4)
    a = v[..., 3:] / 255
    n = a.sum((1, 3))
    plain = v[..., :3].mean((1, 3))
    rgb = np.where(n > 0, (v[..., :3] * a).sum((1, 3)) / np.maximum(n, 1e-9), plain)
    return np.rint(np.dstack((rgb, v[..., 3].mean((1, 3))))).astype(np.uint8)


def write_blp_dxt5(rgba: np.ndarray) -> bytes:
    """A BLP2 of DXT5 from h x w x 4 uint8 (rows top first; power-of-two sides), every mip down to 1x1."""
    h, w = rgba.shape[:2]
    assert w & (w - 1) == 0 and h & (h - 1) == 0, "a BLP's sides are powers of two"
    datas = [encode_dxt5(rgba)]
    while rgba.shape[0] > 1 or rgba.shape[1] > 1:
        rgba = half(rgba)
        datas.append(encode_dxt5(rgba))
    return _blp2(w, h, (2, 8, 7, 1), datas)

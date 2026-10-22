"""Writing a BLP2 the client loads: DXT1 (4 bits a pixel, no alpha), every mip level.

An addon's texture can be BLP as well as TGA (Interface\\AddOns\\MagicMap\\Textures\\Name, no
extension). DXT1 is an eighth of a 32-bit TGA's size, and flat colours (a stylised map) survive
it: a block of two colours is exact, one of one colour is within a texel of a step (the 565
endpoints bracket it, the in-between palette entries take up the rest: the map's backdrop colour
must come out as itself, or the picture's sea shows as a box on it).

Pure Python (no numpy): a 2048x2048 picture takes ~10 s, blocks of the same pixels encoded once.
"""
from __future__ import annotations

import struct

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


def write_blp(levels: list[tuple[int, int, Rgb]]) -> bytes:
    """A BLP2 of DXT1 from levels[0] (w, h, rgb) and each half-size mip after it down to 1x1."""
    datas = [encode_dxt1(*lv) for lv in levels]
    w, h = levels[0][0], levels[0][1]
    offset = 148 + 1024  # the header, then the (unused) 256-colour palette every BLP2 carries
    offsets, sizes = [0] * 16, [0] * 16
    for i, d in enumerate(datas):
        offsets[i], sizes[i] = offset, len(d)
        offset += len(d)
    head = b"BLP2" + struct.pack("<IBBBBII", 1, 2, 0, 0, 1, w, h) + struct.pack("<16I", *offsets) + struct.pack("<16I", *sizes)
    return head + bytes(1024) + b"".join(datas)

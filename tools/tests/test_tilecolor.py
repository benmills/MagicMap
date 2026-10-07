"""The DXT decoder and gen_tilecolor.py: seam solver on synthetic grids,
sea / edge handling, and the generated file end to end."""
import math
import os
import struct
import subprocess
import sys

import pytest

import fixtures
import gen_tilecolor as gt
from mmtools.formats import blp_dxt, box_downsample, dxt_palette, rgb565
from mmtools.tga import read_tga, write_tga

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def to565(r: float, g: float, b: float) -> int:
    return (round(r * 31) << 11) | (round(g * 63) << 5) | round(b * 31)


def blp_raw(w, h, blocks: bytes, alpha_type=0, mips=None) -> bytes:
    """A BLP2 with the given block data for mip 0 (and optional smaller mips:
    a list of block data per level)."""
    levels = [blocks] + (mips or [])
    head = b"BLP2" + struct.pack("<I", 1) + struct.pack("<BBBBII", 2, 8 if alpha_type else 0, alpha_type,
                                                        1 if mips else 0, w, h)
    off, offs, sizes = 20 + 64 + 64 + 1024, [], []
    for data in levels:
        offs.append(off)
        sizes.append(len(data))
        off += len(data)
    offs += [0] * (16 - len(offs))
    sizes += [0] * (16 - len(sizes))
    return head + struct.pack("<16I", *offs) + struct.pack("<16I", *sizes) + b"\0" * 1024 + b"".join(levels)


# --- DXT ------------------------------------------------------------------------

def test_dxt1_four_colour_block():
    c0, c1 = 0xF800, 0x001F  # red > blue: 4-colour mode
    idx = sum(i % 4 << (2 * i) for i in range(16))  # 0,1,2,3,0,1,...
    img = blp_dxt(blp_raw(4, 4, struct.pack("<HHI", c0, c1, idx)))
    texels = img.block(0, 0)
    assert texels[:4] == [(1, 0, 0), (0, 0, 1), (2 / 3, 0, 1 / 3), (1 / 3, 0, 2 / 3)]
    mean = img.block_mean(0, 0)
    assert all(abs(mean[k] - sum(t[k] for t in texels) / 16) < 1e-9 for k in range(3))


def test_dxt1_three_colour_block_has_black():
    c0, c1 = 0x001F, 0xF800  # c0 <= c1: 3 colours + black
    idx = 0xFFFFFFFF  # all index 3
    img = blp_dxt(blp_raw(4, 4, struct.pack("<HHI", c0, c1, idx)))
    assert img.block(0, 0) == [(0.0, 0.0, 0.0)] * 16
    assert img.block_mean(0, 0) == (0.0, 0.0, 0.0)
    assert dxt_palette(c0, c1, False)[2] == (0.5, 0.0, 0.5)


def test_dxt5_reads_the_colour_half():
    c0, c1 = 0x07E0, 0x0000  # green, black
    block = b"\xff" * 8 + struct.pack("<HHI", c0, c1, 0)  # alpha block first
    img = blp_dxt(blp_raw(4, 4, block, alpha_type=7))
    assert img.block_bytes == 16 and img.block(0, 0)[0] == (0, 1, 0)
    # DXT3/5 are always 4-colour, even with c0 <= c1
    img = blp_dxt(blp_raw(4, 4, b"\0" * 8 + struct.pack("<HHI", 0, 0x07E0, 0xFFFFFFFF), alpha_type=1 << 3))
    assert img.block(0, 0)[0] == (0, 2 / 3, 0)


def test_block_means_and_downsample_match_texels():
    blp = fixtures.build_blp(32, 32, lambda bx, by: (to565(bx / 8, by / 8, 0.5), to565(0.2, 0.9, 0.1)))
    img = blp_dxt(blp)
    texels = img.texels()
    grid = img.block_means()
    assert len(grid) == 8 and len(grid[0]) == 8
    small = box_downsample(grid, 2)
    for y in range(2):
        for x in range(2):
            want = [sum(texels[ty][tx][k] for ty in range(y * 16, y * 16 + 16) for tx in range(x * 16, x * 16 + 16)) / 256
                    for k in range(3)]
            assert all(abs(small[y][x][k] - want[k]) < 1e-9 for k in range(3))


def test_blp_dxt_picks_a_mip():
    big = struct.pack("<HHI", 0xF800, 0, 0) * 16   # 16x16: red
    mid = struct.pack("<HHI", 0x07E0, 0, 0) * 4    # 8x8: green
    tiny = struct.pack("<HHI", 0x001F, 0, 0)       # 4x4: blue
    blp = blp_raw(16, 16, big, mips=[mid, tiny])
    assert blp_dxt(blp).width == 16
    assert blp_dxt(blp, min_size=8).block(0, 0)[0] == (0, 1, 0)
    assert blp_dxt(blp, min_size=1).block(0, 0)[0] == (0, 0, 1)
    assert blp_dxt(b"BLP2" + b"\0" * 200) is None
    assert rgb565(0xFFFF) == (1, 1, 1)


# --- the solver ------------------------------------------------------------------

def terrain(gx: float, gy: float) -> tuple[float, float, float]:
    """Smooth land colours (never water-blue), continuous across tiles."""
    return (0.35 + 0.12 * math.sin(gx / 37.0) * math.cos(gy / 23.0),
            0.30 + 0.10 * math.sin(gy / 29.0 + 1),
            0.15 + 0.05 * math.cos((gx + gy) / 41.0))


def tile_blp(col: int, row: int, gain: float = 1.0, add: float = 0.0, size: int = 128) -> bytes:
    """A size x size DXT1 tile of the global terrain, scaled and offset."""
    nb = size // 4

    def color(bx, by):
        c = terrain(col * nb + bx, row * nb + by)
        c = [min(1.0, max(0.0, v * gain + add)) for v in c]
        return to565(*c), 0
    return fixtures.build_blp(size, size, color)


def grid_tiles(n: int, odd: dict[tuple[int, int], tuple[float, float]]) -> dict[int, gt.TileData]:
    tiles = {}
    for c in range(10, 10 + n):
        for r in range(10, 10 + n):
            gain, add = odd.get((c, r), (1.0, 0.0))
            tiles[c * 64 + r] = gt.analyse_tile(tile_blp(c, r, gain, add))
    return tiles


def test_identity_tiles_stay_identity():
    tiles = grid_tiles(5, {})
    seams = gt.find_seams(tiles)
    assert len(seams) == 2 * 5 * 4
    assert max(s.score for s in seams) < 0.02
    assert gt.solve(tiles, seams) == {}


def test_bright_tile_is_darkened():
    odd = (12, 12)
    tiles = grid_tiles(5, {odd: (1.3, 0.0)})
    seams = gt.find_seams(tiles)
    worst = sorted(seams, key=lambda s: -s.score)[:4]
    assert all(odd[0] * 64 + odd[1] in (s.a, s.b) for s in worst)  # the detector finds its 4 seams
    tint = gt.solve(tiles, seams)
    assert set(tint) == {odd[0] * 64 + odd[1]}  # only the outlier moves
    m, a = tint[odd[0] * 64 + odd[1]]
    assert all(abs(v - 1 / 1.3) < 0.05 for v in m) and all(v < 0.02 for v in a)


def test_dark_tile_gets_an_overlay():
    odd = (11, 12)
    tiles = grid_tiles(4, {odd: (1.0, -0.06)})
    tint = gt.solve(tiles, gt.find_seams(tiles))
    assert set(tint) == {odd[0] * 64 + odd[1]}
    m, a = tint[odd[0] * 64 + odd[1]]
    assert all(v > 0.98 for v in m) and all(abs(v - 0.06) < 0.02 for v in a)


def test_solve_box2_respects_bounds():
    assert gt.solve_box2(1, 0, 1, 2, 0.5, 0, 1) == (1, 0.5)      # m wants 2: capped at 1
    m, a = gt.solve_box2(1, 0, 1, 0.5, -1, 0, 1)                 # a wants -1: 0
    assert (m, a) == (0.5, 0.0)


# --- sea, edges, output ----------------------------------------------------------

BG = (0.03, 0.06, 0.06)


def flat_tile(c) -> gt.TileData:
    blp = fixtures.build_blp(128, 128, lambda bx, by: (to565(*c), 0))
    return gt.analyse_tile(blp)


def test_sea_tiles_count_as_open_space():
    sea, land = flat_tile(BG), flat_tile((0.4, 0.3, 0.2))
    framed = gt.analyse_tile(fixtures.build_blp(128, 128, lambda bx, by: (to565(0.3, 0.3, 0.2) if by < 2 else to565(*BG), 0)))
    m = gt.MapTiles(1, "Test", BG, None, {})
    assert gt.is_sea(sea, BG) and gt.is_sea(framed, BG) and not gt.is_sea(land, BG)
    data = {1: land, 2: sea, 3: land, 4: framed}
    m.tiles = {10 * 64 + 10: 1, 11 * 64 + 10: 2, 10 * 64 + 11: 3, 10 * 64 + 9: 4}
    r = gt.process_map(m, data)
    assert r.sea == {11 * 64 + 10, 10 * 64 + 9}
    e = r.edges[10 * 64 + 10]
    assert set(e) == {"l", "r", "t"}  # sea right, framed sea on top, nothing left; land below
    assert all(abs(e["r"][k] - (0.4, 0.3, 0.2)[k]) < 0.02 for k in range(3))
    assert set(r.edges[10 * 64 + 11]) == {"l", "r", "b"}


def test_bracket_frame_tile_is_sea():
    """A world-edge tile with a baked one-colour bracket (deeper than FRAME)
    is sea, so it gets no glowing edge fade; a sea tile with a shore patch
    is not."""
    grey = to565(0.5, 0.5, 0.5)
    bracket = gt.analyse_tile(fixtures.build_blp(128, 128, lambda bx, by: (grey if by < 10 or bx < 3 else to565(*BG), 0)))
    assert gt.is_sea(bracket, BG)
    shore = gt.analyse_tile(fixtures.build_blp(
        128, 128, lambda bx, by: (to565(0.05, 0.12, 0.06) if bx > 20 and by > 10 else to565(*BG), 0)))
    assert not gt.is_sea(shore, BG)


def test_water_samples_are_not_seams():
    blue, teal = flat_tile((0.1, 0.2, 0.3)), flat_tile((0.03, 0.24, 0.19))
    tiles = {10 * 64 + 10: blue, 11 * 64 + 10: teal, 12 * 64 + 10: flat_tile(BG)}
    assert gt.find_seams(tiles, BG) == []


@pytest.fixture(scope="module")
def generated(world, tmp_path_factory):
    out = tmp_path_factory.mktemp("tilecolor")
    path, preview = out / "tilecolor.lua", out / "preview"
    subprocess.run([sys.executable, os.path.join(TOOLS, "gen_tilecolor.py"), "local", world, fixtures.PRODUCT,
                    "-o", str(path), "-j", "1", "--preview", str(preview), "--water", str(out / "water")],
                   check=True, capture_output=True)
    return path


def test_generated_file_loads(generated):
    from lupa import lua51
    text = generated.read_text()
    assert text.startswith("-- GENERATED by tools/gen_tilecolor.py from the wow_test 1.60.1.12345 minimap tiles.")
    L = lua51.LuaRuntime(encoding=None)
    L.eval(b"function(p) return assert(loadfile(p))() end")(str(generated).encode())
    tc = L.globals().MagicMap_TileColor
    assert sorted(tc.keys()) == [0, 1, 36]
    assert tc[1][b"waterDir"] == b"Interface\\AddOns\\MagicMap\\Textures\\Water\\wow_test\\"
    assert tc[1][b"water"] is not None
    k = tc[1]
    # Kalimdor: a 3x2 block of tiles, every outer side open
    edges = {key: sorted(v.keys()) for key, v in k[b"edge"].items()}
    assert edges[10 * 64 + 10] == [b"l", b"t"] and edges[12 * 64 + 11] == [b"b", b"r"]
    assert len(edges) == 6
    for v in k[b"edge"].values():
        for c in v.values():
            assert all(0 <= c[i] <= 1 for i in (1, 2, 3))
    for t in k[b"tint"].values():
        assert all(0 <= t[i] <= 1 for i in (1, 2, 3)) and all(t[i] >= 0 for i in (4, 5, 6))


# --- shallow water ---------------------------------------------------------------

def test_tga_round_trip_keeps_rows_top_first():
    rows = [[(255, 0, 0, 10), (0, 255, 0, 20), (0, 0, 255, 30)],
            [(1, 2, 3, 40), (4, 5, 6, 50), (7, 8, 9, 60)]]
    data = write_tga(3, 2, rows)
    assert len(data) == 18 + 3 * 2 * 4
    assert data[2] == 2 and data[16] == 32 and data[17] == 0x08  # uncompressed, 8 alpha bits, bottom-left origin
    assert data[18:22] == bytes((3, 2, 1, 40))  # stored bottom row first, as BGRA
    assert read_tga(data) == (3, 2, rows)
    top_left = data[:17] + bytes((0x28,)) + data[18 + 12:] + data[18:18 + 12]  # same image stored top-down
    assert read_tga(top_left) == (3, 2, rows)


LAND, SHALLOW = (0.4, 0.3, 0.2), (0.12, 0.21, 0.29)


def coast_map(lake: bool = False):
    """A 3x3 map: sea all round, a land tile at (11, 10) (with an inland lake
    if asked) and below it a coast tile, land in its top 8 rows and shallow
    blue water below."""
    def tile(fn):
        return gt.analyse_tile(fixtures.build_blp(128, 128, lambda bx, by: (to565(*fn(bx, by)), 0)))

    data = {
        1: tile(lambda bx, by: BG),
        2: tile(lambda bx, by: SHALLOW if lake and 12 <= bx < 20 and 12 <= by < 20 else LAND),
        3: tile(lambda bx, by: LAND if by < 8 else SHALLOW),
    }
    tiles = {c * 64 + r: 1 for c in range(10, 13) for r in range(9, 13)}
    tiles[11 * 64 + 10], tiles[11 * 64 + 11] = 2, 3
    return gt.MapTiles(1, "Coast", BG, None, tiles), data


def test_shallow_water_gets_a_mask(tmp_path):
    m, data = coast_map()
    r = gt.process_map(m, data)
    coast = 11 * 64 + 11
    assert set(r.water) == {coast}
    a = r.water[coast]
    assert max(a[y][x] for y in range(8) for x in range(32)) == 0  # land untouched
    assert a[9][16] < 0.2  # a shallow band along the shore
    assert min(a[31]) > 0.9  # open water: the sea colour
    assert all(abs(r.edges[coast]["b"][k] - BG[k]) < 0.02 for k in range(3))  # edge taken after recolouring

    (tmp_path / "1_999.tga").write_bytes(b"stale")
    (tmp_path / "keep.txt").write_text("not ours")
    gt.write_masks(str(tmp_path), [r])
    assert sorted(os.listdir(tmp_path)) == [f"1_{coast}.tga", "keep.txt"]
    w, h, rows = read_tga((tmp_path / f"1_{coast}.tga").read_bytes())
    assert (w, h) == (32, 32)
    assert all(p[:3] == (255, 255, 255) for row in rows for p in row)
    assert rows[0][0][3] == 0 and rows[31][16][3] > 230  # top of the tile is the land: orientation kept


def test_inland_lakes_are_untouched():
    m, data = coast_map(lake=True)
    r = gt.process_map(m, data)
    assert 11 * 64 + 10 not in r.water and 11 * 64 + 11 in r.water


def test_no_water_where_the_backdrop_is_land():
    m, data = coast_map()
    m.tiles = {k: (2 if f == 1 else f) for k, f in m.tiles.items()}  # no sea tiles: a map fragment
    m.bg = LAND
    assert gt.process_map(m, data).water == {}

"""The file-format readers, on synthetic files."""

from fixtures import build_adt, build_blp, build_wdc5, build_wdt
from mmtools.db2 import format_value, read_wdc5
from mmtools.formats import adt_chunks, blp_edge_colors, wdt_maid

FIELDS = [("string",), ("int", 16), ("array", 3), ("bitpacked", 5), ("signed", 7), ("common", 9),
          ("pallet", 2), ("pallet_array", 2, 2), ("string",)]
ROWS = [
    (5, ["alpha", 1, (1, 2, 3), 31, -64, 9, 70000, (1, 2), ""]),
    (17, ["beta", 65535, (0, 0, 0), 0, 63, 4, 70000, (3, 4), "x"]),
    (900, ["", 0, (7, 8, 9), 5, -1, 9, 12, (1, 2), "gamma delta"]),
]


def test_wdc5_every_storage_type():
    for sections in (1, 2, 3):
        rows = read_wdc5(build_wdc5(FIELDS, ROWS, sections=sections), string_fields={0, 8})
        assert rows == [[rid] + [v if v != "" else 0 for v in vals] for rid, vals in ROWS]


def test_wdc5_ids_without_an_id_list():
    rows = read_wdc5(build_wdc5([("int", 32), ("int", 8)], [(1, [1, 2]), (2, [2, 3])], id_list=False))
    assert [r[0] for r in rows] == [1, 2]  # from the id field


def test_wdc5_text_form():
    assert [format_value(v) for v in (None, (1, 2), "x", 7)] == ["", "1,2", "s:x", "7"]


def test_wdt_maid_is_stored_row_major():
    tiles = wdt_maid(build_wdt({30 * 64 + 31: (100, 200), 5 * 64 + 63: (0, 300)}))
    assert set(tiles) == {30 * 64 + 31, 5 * 64 + 63}
    assert tiles[30 * 64 + 31].root_adt == 100 and tiles[30 * 64 + 31].minimap == 200
    assert tiles[5 * 64 + 63].root_adt == 0 and tiles[5 * 64 + 63].minimap == 300


def test_adt_chunks():
    heights = [float(i % 7) for i in range(145)]
    chunks = list(adt_chunks(build_adt([(3, 4, 12, 10.0, heights), (5, 6, 13, -50.0, None)])))
    assert [(c.ix, c.iy, c.area) for c in chunks] == [(3, 4, 12), (5, 6, 13)]
    assert chunks[0].max_height == 16.0
    assert chunks[1].max_height == -50.0


def test_blp_edge_colors():
    blp = build_blp(64, 64, lambda bx, by: (0xF800, 0x001F))  # pure red, pure blue
    colors = blp_edge_colors(blp, {"left": True})
    assert len(colors) == 4  # every 4th block down a 16-block edge
    assert colors[0] == (0.5, 0.0, 0.5)
    assert blp_edge_colors(blp, {}) == []

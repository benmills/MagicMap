"""ai_map.py check and stamp: a new game build is re-enabled only if the tiles under the repaints didn't change."""
import json

import ai_map


class Src:
    product, version = "wow_classic_beta", "1.60.1.99999"


def setup(tmp_path, monkeypatch, now, bytes_of):
    guard, data = tmp_path / "guard.json", tmp_path / "Repaint.lua"
    guard.write_text(json.dumps({"places": {"good": {"map": 0, "tiles": {"1,2": [10, "aa"]}}, "bad": {"map": 0, "tiles": {"3,4": [20, "bb"]}}}}))
    data.write_text('-- head\nD.Repaint = { build = "1.60.1.1", maps = {\n} }\n')
    monkeypatch.setattr(ai_map, "GUARD", str(guard))
    monkeypatch.setattr(ai_map, "DATA", str(data))
    monkeypatch.setattr(ai_map, "wdt_tiles", lambda src, insts: {0: now})
    monkeypatch.setattr(ai_map, "tile_hash", lambda src, fdid: bytes_of[fdid])
    return data


def test_stamp_refuses_a_changed_tile(tmp_path, monkeypatch, capsys):
    data = setup(tmp_path, monkeypatch, {66: 10, 196: 21}, {10: "aa", 21: "new"})
    assert ai_map.stamp(Src) == ["bad"]
    assert "1.60.1.1" in data.read_text() and "bad: changed" in capsys.readouterr().out


def test_stamp_a_clean_build(tmp_path, monkeypatch):
    data = setup(tmp_path, monkeypatch, {66: 10, 196: 21}, {10: "aa", 21: "bb"})  # 21: a new id, the same bytes
    assert ai_map.stamp(Src) == []
    assert 'build = "1.60.1.99999"' in data.read_text()

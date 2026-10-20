"""Nothing defines a global but game/ (its SavedVariables, SLASH_*): tools/luacheck.py.
The spike's E1 (docs/evidence/spike-bugs.md) was two addons sharing data globals."""
import luacheck


def problems(monkeypatch, tmp_path, rel, src):
    monkeypatch.setattr(luacheck, "ROOT", str(tmp_path))
    monkeypatch.setattr(luacheck, "saved_variables", lambda: {"MagicMap2DB"})
    path = tmp_path / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(src)
    return luacheck.check([str(path)])


def test_only_game_defines_globals(monkeypatch, tmp_path, capsys):
    assert problems(monkeypatch, tmp_path, "game/Slash.lua", "SLASH_MAGICMAP1 = '/mm'\nMagicMap2DB = {}\n") == 0
    for rel, src in [
        ("Data/Tiles.lua", "MagicMap_Tiles = {}\n"),  # the E1 shape
        ("game/Game.lua", "MagicMap_Debug = true\n"),  # an addon-prefixed name is still a global
        ("ui/Map.lua", "SLASH_FOO1 = '/foo'\n"),  # slash commands are game/'s
        ("ui/Map.lua", "MagicMap2DB = {}\n"),  # so are the SavedVariables
        ("atlas/Tiles.lua", "_G.MagicMap_Tiles = {}\n"),  # around the bytecode check
    ]:
        assert problems(monkeypatch, tmp_path, rel, src) >= 1, (rel, src)
    assert "only game/ defines globals" in capsys.readouterr().out

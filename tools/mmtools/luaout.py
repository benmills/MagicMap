"""Writing Lua literals for the generated Data/*.lua files."""
from __future__ import annotations

import os


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n") + '"'


def run_letters(letters: list[str]) -> str:
    """Single-letter cells with runs written as the letter and a count: "n200b3n53"."""
    out, i, n = [], 0, len(letters)
    while i < n:
        j = i
        while j < n and letters[j] == letters[i]:
            j += 1
        out.append(letters[i] + (str(j - i) if j - i > 1 else ""))
        i = j
    return "".join(out)


# Each dataset's format: bump it when the shape of D.<Name> changes, together with
# Atlas.FORMATS (atlas/Coords.lua; tools/tests/test_atlas.py checks they agree).
FORMATS = {
    "Tiles": 1, "TileColor": 1, "Sea": 1, "Borders": 1, "Walk": 1, "UiMaps": 1, "Areas": 1,
    "AreaGrid": 1, "Places": 1, "ItemIcons": 1, "Npcs": 1, "Objects": 1, "Items": 1, "Quests": 1,
}


def data_head(name: str) -> str:
    """The wrapper a Data/<name>.lua starts with, after its comments: no globals, the
    data goes into the addon's ns (docs/atlas-data.md). Follow it with `D.<name> = {...}`."""
    return ("local _, ns = ...\n"
            "local D = ns.Data or {}; ns.Data = D\n"
            f"D.formats = D.formats or {{}}; D.formats.{name} = {FORMATS[name]}\n")


def load_data(lua, path: str, ns=None, addon: str = "MagicMapAtlas"):
    """Run a generated Data/*.lua in a lupa runtime as WoW does (called with addon, ns);
    returns ns (a new one unless given): its datasets are ns.Data.<Name>."""
    if ns is None:
        ns = lua.table()
    load = lua.eval("function(src, name) local f, err = loadstring(src, name) if not f then error(err) end return f end")
    with open(path, "rb") as f:
        load(f.read(), "@" + os.path.basename(path))(addon, ns)
    return ns

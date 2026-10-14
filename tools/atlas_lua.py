"""Load the Atlas library into Lua 5.1 (lupa), as WoW would: each file in
atlas/files.txt, in order, called with (addonName, ns). Atlas reads only its
data globals (Data/*.lua), so loading is all there is.

  L, Atlas = load_atlas()
  L, Atlas = load_atlas(extra=["demo/something.lua"])   # more files after, same ns

Data files that aren't there are skipped: the QuestieDB-derived ones
(Npcs, Objects, Items, Quests) are gitignored and may be missing.
"""
from __future__ import annotations

import os

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = os.path.join(ROOT, "atlas", "files.txt")


def files() -> list[str]:
    with open(FILES, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


def load_atlas(extra: list[str] = ()):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    load = L.eval("function(src, name) local f, err = loadstring(src, name) if not f then error(err) end return f end")
    ns = L.table()
    for rel in files() + list(extra):
        path = os.path.join(ROOT, rel)
        if rel.startswith("Data/") and not os.path.exists(path):
            continue
        with open(path, "rb") as f:
            load(f.read(), "@" + rel)("MagicMap", ns)
    return L, ns.Atlas

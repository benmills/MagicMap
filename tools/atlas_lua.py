"""Load the Atlas library into Lua 5.1 (lupa), as WoW would: each file in
atlas/files.txt, in order, called with (addonName, ns).

  L, Atlas = load_atlas()                 # tiles, walk, camera ...
  L, Atlas = load_atlas(readers={...})    # ... and Atlas.Scan(readers) run
  L, Atlas = load_atlas("FixtureReaders", extra=["demo/catalogue.lua", "demo/readers.lua"])

readers: a dict of Python callables (see atlas/Catalogue.lua). A dict they
return becomes a Lua table; a tuple, several return values. Or the name of a
Lua readers table that one of the extra files (loaded after Atlas, with the
same ns) sets on ns.
"""
from __future__ import annotations

import os

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = os.path.join(ROOT, "atlas", "files.txt")


def files() -> list[str]:
    with open(FILES, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


def load_atlas(readers: dict | str | None = None, extra: list[str] = ()):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    load = L.eval("function(src, name) local f, err = loadstring(src, name) if not f then error(err) end return f end")
    ns = L.table()
    for rel in files() + list(extra):
        with open(os.path.join(ROOT, rel), "rb") as f:
            load(f.read(), "@" + rel)("MagicMap", ns)
    atlas = ns.Atlas
    if isinstance(readers, str):
        atlas.Scan(ns[readers])
    elif readers is not None:
        def wrap(fn):
            def call(*args):
                r = fn(*args)
                return L.table_from(r) if isinstance(r, dict) else r
            return call
        atlas.Scan(L.table_from({k: wrap(v) for k, v in readers.items()}))
    return L, atlas

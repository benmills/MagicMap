"""Writing Lua literals for the generated Data/*.lua files."""
from __future__ import annotations


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

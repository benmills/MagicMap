"""Writing Lua literals for the generated Data/*.lua files."""
from __future__ import annotations

import re

_LUA_UNSAFE = re.compile(rb'[\x00-\x1f"\\\x7f]')


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_bytes(b: bytes) -> bytes:
    """A byte string as a Lua literal: raw bytes, with only those a literal
    can't hold escaped as \\ddd."""
    return b'"' + _LUA_UNSAFE.sub(lambda m: b"\\%03d" % m.group(0)[0], b) + b'"'

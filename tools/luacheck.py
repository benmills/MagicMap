#!/usr/bin/env python3
"""Check the addon's Lua with a real Lua 5.1 compiler (the dialect WoW uses,
via the `lupa` package): syntax errors, plus a globals check from the
compiled bytecode, so scoping is exact.

  * Writing a global is an error unless it's one of the addon's own
    (MagicMap*, SLASH_*, BINDING_*, ...): usually a missing `local`.
  * Reading a global is an error unless the addon sets it somewhere or it's
    listed in tools/wow_globals.txt (the WoW API and Lua's own library):
    usually a typo'd local.
  * Every file in MagicMap.toc must exist, and every addon .lua must be in it.

  python3 tools/luacheck.py              # the files in MagicMap.toc
  python3 tools/luacheck.py Core.lua     # just these
  python3 tools/luacheck.py --globals Core.lua   # list globals read / written

Needs `pip install lupa`.
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "MagicMap.toc")
ALLOWLIST = os.path.join(ROOT, "tools", "wow_globals.txt")
# Globals the addon may create.
OWN_GLOBALS = ["MagicMap*", "SLASH_*", "BINDING_*"]

OP_GETGLOBAL, OP_SETGLOBAL = 5, 7


def lua51():
    try:
        from lupa import lua51 as mod
    except ImportError:
        sys.exit("luacheck needs Lua 5.1 from the lupa package: pip install lupa")
    return mod.LuaRuntime(encoding=None)


class Bytecode:
    """A Lua 5.1 string.dump reader: just enough to list global accesses."""

    def __init__(self, data: bytes):
        self.b, self.p = data, 12
        if data[:5] != b"\x1bLua\x51":
            raise ValueError("not Lua 5.1 bytecode")
        self.int_size, self.size_t = data[7], data[8]
        self.accesses: list[tuple[str, str, int]] = []  # (op, name, line)
        self.function()

    def u8(self) -> int:
        v = self.b[self.p]
        self.p += 1
        return v

    def int(self) -> int:
        v = int.from_bytes(self.b[self.p:self.p + self.int_size], "little")
        self.p += self.int_size
        return v

    def string(self) -> bytes | None:
        n = int.from_bytes(self.b[self.p:self.p + self.size_t], "little")
        self.p += self.size_t
        if n == 0:
            return None
        s = self.b[self.p:self.p + n - 1]
        self.p += n
        return s

    def function(self) -> None:
        self.string()  # source
        self.int(), self.int()  # line defined, last line defined
        self.p += 4  # nups, numparams, is_vararg, maxstacksize
        code = struct.unpack_from(f"<{self.int()}I", self.b, self.p)
        self.p += 4 * len(code)
        consts = []
        for _ in range(self.int()):
            t = self.u8()
            if t == 1:
                consts.append(bool(self.u8()))
            elif t == 3:
                self.p += 8
                consts.append(None)
            elif t == 4:
                consts.append(self.string())
            else:
                consts.append(None)
        for _ in range(self.int()):
            self.function()
        lines = [self.int() for _ in range(self.int())]
        for _ in range(self.int()):  # local variables
            self.string()
            self.int(), self.int()
        for _ in range(self.int()):  # upvalue names
            self.string()
        for pc, ins in enumerate(code):
            op = ins & 0x3F
            if op in (OP_GETGLOBAL, OP_SETGLOBAL):
                name = consts[ins >> 14].decode("utf-8", "replace")
                self.accesses.append(("get" if op == OP_GETGLOBAL else "set", name, lines[pc] if pc < len(lines) else 0))


def toc_files() -> list[str]:
    files = []
    with open(TOC, encoding="utf-8-sig") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                files.append(line.replace("\\", "/"))
    return files


def load_allowlist() -> set[str]:
    names = set()
    with open(ALLOWLIST, encoding="utf-8") as f:
        for line in f:
            names.update(line.split("#", 1)[0].split())
    return names


def is_own(name: str) -> bool:
    return any(fnmatch.fnmatchcase(name, p) for p in OWN_GLOBALS)


def check(paths: list[str], list_globals: bool = False) -> int:
    L = lua51()
    compile_ = L.eval(b"function(src, name) local f, err = loadstring(src, name) "
                      b"if not f then return nil, err end return string.dump(f) end")
    problems = 0
    accesses: dict[str, list[tuple[str, str, int]]] = {}
    for path in paths:
        rel = os.path.relpath(path, ROOT)
        with open(path, "rb") as f:
            src = f.read()
        if src.startswith(b"\xef\xbb\xbf"):
            src = src[3:]
        result = compile_(src, b"@" + rel.encode())
        if isinstance(result, tuple):  # nil, error
            print(result[1].decode("utf-8", "replace"))
            problems += 1
            continue
        accesses[rel] = Bytecode(result).accesses

    set_anywhere = {name for acc in accesses.values() for op, name, _ in acc if op == "set"}
    if list_globals:
        for rel, acc in accesses.items():
            print(f"{rel}:")
            seen: dict[tuple[str, str], list[int]] = {}
            for op, name, line in acc:
                seen.setdefault((name, op), []).append(line)
            for (name, op), lines in sorted(seen.items()):
                print(f"  {op} {name:32} {','.join(map(str, sorted(set(lines))[:6]))}")
        return problems

    allowed = load_allowlist()
    for rel, acc in accesses.items():
        reported = set()
        for op, name, line in sorted(acc, key=lambda a: a[2]):
            if (op, name) in reported:
                continue
            if op == "set" and not is_own(name):
                print(f"{rel}:{line}: sets global '{name}' (missing 'local'? or add it to OWN_GLOBALS)")
            elif op == "get" and name not in allowed and name not in set_anywhere and not is_own(name):
                print(f"{rel}:{line}: reads unknown global '{name}' (typo? or add it to tools/wow_globals.txt)")
            else:
                continue
            reported.add((op, name))
            problems += 1
    return problems


def check_toc() -> int:
    problems = 0
    listed = toc_files()
    for f in listed:
        if not os.path.exists(os.path.join(ROOT, f)):
            print(f"MagicMap.toc: lists {f}, which doesn't exist")
            problems += 1
    on_disk = [f for f in os.listdir(ROOT) if f.endswith(".lua")]
    on_disk += ["Data/" + f for f in os.listdir(os.path.join(ROOT, "Data")) if f.endswith(".lua")]
    for f in sorted(set(on_disk) - set(listed)):
        print(f"MagicMap.toc: {f} isn't listed, so the game never loads it")
        problems += 1
    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--globals", action="store_true", help="list each file's global reads and writes")
    parser.add_argument("files", nargs="*", help="default: everything in MagicMap.toc")
    ns = parser.parse_args()
    if ns.files:
        paths, problems = [os.path.abspath(f) for f in ns.files], 0
    else:
        paths, problems = [os.path.join(ROOT, f) for f in toc_files()], check_toc()
    problems += check(paths, ns.globals)
    if not ns.globals:
        print(f"{len(paths)} files, {problems} problem{'s' if problems != 1 else ''}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()

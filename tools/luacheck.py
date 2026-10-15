#!/usr/bin/env python3
"""Check the addon's Lua with a real Lua 5.1 compiler (the dialect WoW uses,
via the `lupa` package): syntax errors, plus a globals check from the
compiled bytecode, so scoping is exact.

  * Nothing defines a global but game/: its SavedVariables (the TOC's) and
    SLASH_* (SlashCmdList's entries are fields, not globals). Any other global
    write is an error (usually a missing `local`), and so is reaching for
    globals around this check (_G, setglobal, getfenv, setfenv): a global is
    shared with every addon (docs/structure.md; the spike's E1 collision).
    The generated data is ns.Data, not globals (docs/atlas-data.md).
  * Reading a global is an error unless the addon sets it somewhere or it's
    listed in tools/wow_globals.txt (the WoW API and Lua's own library):
    usually a typo'd local.
  * Boundaries (architecture.md Rules; README "Boundaries"): each folder
    may read only its own globals (BOUNDARIES: sections of
    tools/lua51_globals.txt and tools/wow_globals.txt), only game/ may touch
    the SavedVariables, and each folder may use only the ns.<System>s that
    NS_RULES allow (a static scan; limits at check_ns). Known violations
    waiting on a contract are in BASELINE; one that's gone must be removed.
  * MagicMapAtlas.toc must be what the folders' files.txt manifests make
    (tools/install.py generates it), every file in it must exist (a gitignored
    one may be missing: QuestieDB-derived data), and every addon .lua must be
    in it.

  python3 tools/luacheck.py              # the files in MagicMapAtlas.toc
  python3 tools/luacheck.py Core.lua     # just these
  python3 tools/luacheck.py --globals Core.lua   # list globals read / written
  python3 tools/luacheck.py --allow tools/lua51_globals.txt atlas/*.lua   # only this allowlist (no boundaries)

Needs `pip install lupa`.
"""
from __future__ import annotations

import argparse
import fnmatch
import os
import re
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "MagicMapAtlas.toc")
ADDON_DIRS = ["Data", "atlas", "runtime", "game", "model", "ui"]
ALLOWLIST = os.path.join(ROOT, "tools", "wow_globals.txt")
LUA51 = os.path.join(ROOT, "tools", "lua51_globals.txt")
# The only globals the addon creates, and only in game/: the SavedVariables (TOC) and these.
GAME_GLOBALS = ["SLASH_*"]
GAME = "game"
# Ways to read or write a global by name, past the bytecode check: banned outright.
GLOBAL_ESCAPES = {"_G", "setglobal", "getfenv", "setfenv"}

# The globals each folder may read: (allowlist, its sections; None = all).
BOUNDARIES = {
    "atlas": [(LUA51, {"lua51"})],
    "model": [(LUA51, {"lua51"})],
    "runtime": [(LUA51, {"lua51"}), (ALLOWLIST, {"lua", "runtime"})],
    "ui": [(LUA51, {"lua51"}), (ALLOWLIST, {"lua", "ui"})],
}

# The ns.<System>s each folder may use: any field of these, or just the
# listed fields of another. Game talks to UI only through View, Model only
# through Observe (and Load / SAVED: its saved part, types/model.lua); UI talks to
# Game only through Command (the commands channel: slash and load too).
NS_RULES = {
    "Data": ({"Data"}, {}),
    "atlas": ({"Atlas", "Data"}, {}),
    "runtime": ({"Runtime"}, {}),
    "model": ({"Model", "Atlas", "Runtime"}, {}),
    "ui": ({"UI", "Model", "Atlas", "Runtime"}, {"Game": {"Command"}}),
    "game": ({"Game", "Atlas", "Runtime"}, {"UI": {"View"}, "Model": {"Observe", "Load", "SAVED"}}),
}

# Known violations, each waiting on a contract: (file, System, field). Keep it
# short; the check fails on any entry that no longer matches, so it only shrinks.
BASELINE: set[tuple[str, str, str]] = set()

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


def load_allowlist(path: str = ALLOWLIST, sections: set[str] | None = None) -> set[str]:
    """The names in an allowlist; only those under the given [section]s if any."""
    names, section = set(), None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line.startswith("["):
                section = line.strip("[]")
            elif sections is None or section in sections:
                names.update(line.split())
    return names


def folder(rel: str) -> str:
    return rel.replace("\\", "/").split("/")[0]


def saved_variables() -> set[str]:
    with open(TOC, encoding="utf-8-sig") as f:
        for line in f:
            if line.startswith("## SavedVariables"):
                return {v.strip() for v in line.split(":", 1)[1].split(",") if v.strip()}
    return set()


def check_boundaries(accesses: dict[str, list[tuple[str, str, int]]]) -> int:
    """Each folder reads only its BOUNDARIES globals; only game/ touches the SavedVariables."""
    problems, sv = 0, saved_variables()
    allowed = {d: set().union(*(load_allowlist(p, s) for p, s in lists)) for d, lists in BOUNDARIES.items()}
    for rel, acc in accesses.items():
        d, reported = folder(rel), set()
        for op, name, line in sorted(acc, key=lambda a: a[2]):
            if name in reported:
                continue
            if name in sv and d != "game":
                print(f"{rel}:{line}: uses SavedVariables '{name}': only game/ loads and saves")
            elif op == "get" and d in allowed and name not in allowed[d]:
                print(f"{rel}:{line}: {d}/ may not read '{name}' (BOUNDARIES in tools/luacheck.py)")
            else:
                continue
            reported.add(name)
            problems += 1
    return problems


LUA_NOISE = re.compile(r"""--\[(=*)\[.*?\]\1\]|\[(=*)\[.*?\]\2\]|--[^\n]*|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'""", re.S)
NS_REF = re.compile(r"\bns\s*\.\s*([A-Za-z_]\w*)(?:\s*[.:]\s*([A-Za-z_]\w*))?")
ALIAS = re.compile(r"\blocal\s+([\w\s,]+?)\s*=\s*([^\n;]+)")


def ns_refs(src: str) -> list[tuple[str, str | None, int]]:
    """(System, field or None, line) for each ns.System use, through `local X = ns.System` aliases too."""
    src = LUA_NOISE.sub(lambda m: "\n" * m.group(0).count("\n"), src)  # comments and strings; lines kept
    line_at = lambda pos: src.count("\n", 0, pos) + 1  # noqa: E731
    aliases, skip = {}, set()
    for m in ALIAS.finditer(src):
        for name, expr in zip(m.group(1).split(","), m.group(2).split(",")):
            a = re.match(r"\s*ns\s*\.\s*([A-Za-z_]\w*)\s*(?:or\b.*)?$", expr)
            if a:
                aliases[name.strip()] = a.group(1)
                skip.add(m.start(2) + m.group(2).index(expr) + expr.index("ns"))
    refs = [(m.group(1), m.group(2), line_at(m.start())) for m in NS_REF.finditer(src) if m.start() not in skip]
    for name, system in aliases.items():
        for m in re.finditer(rf"(?<![\w.:])\b{re.escape(name)}\s*[.:]\s*([A-Za-z_]\w*)", src):
            refs.append((system, m.group(1), line_at(m.start())))
    return refs


def check_ns(paths: list[str]) -> int:
    """NS_RULES over each folder's files. A static scan: it sees ns.X.f and
    `local A, B = ns.X, ns.Y` then A.f; not ns["X"], an alias passed on or
    reassigned, nor a table of ns's handed through a call."""
    problems, used = 0, set()
    for path in paths:
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        rule = NS_RULES.get(folder(rel))
        if not rule:
            continue
        own, fields = rule
        with open(path, encoding="utf-8", errors="replace") as f:
            refs = ns_refs(f.read())
        reported = set()
        for system, field, line in sorted(refs, key=lambda r: r[2]):
            if system in own or field in fields.get(system, ()) or (system, field) in reported:
                continue
            reported.add((system, field))
            if (rel, system, field) in BASELINE:
                used.add((rel, system, field))
                continue
            what = f"ns.{system}.{field}" if field else f"ns.{system}"
            print(f"{rel}:{line}: {folder(rel)}/ may not use {what} (NS_RULES in tools/luacheck.py)")
            problems += 1
    for rel, system, field in sorted(BASELINE - used):
        if os.path.join(ROOT, rel) in paths:
            print(f"tools/luacheck.py: BASELINE ({rel}, ns.{system}.{field}) no longer happens: remove it")
            problems += 1
    return problems


def may_set(rel: str, name: str) -> bool:
    """Only game/ defines globals: the SavedVariables and SLASH_*."""
    return folder(rel) == GAME and (name in saved_variables() or any(fnmatch.fnmatchcase(name, p) for p in GAME_GLOBALS))


def check(paths: list[str], list_globals: bool = False, allowlist: str = ALLOWLIST) -> int:
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

    # A strict allowlist also stops the addon's own globals passing as read.
    strict = allowlist != ALLOWLIST
    allowed = load_allowlist(allowlist)
    for rel, acc in accesses.items():
        reported = set()
        for op, name, line in sorted(acc, key=lambda a: a[2]):
            if (op, name) in reported:
                continue
            if op == "set" and not may_set(rel, name):
                print(f"{rel}:{line}: sets global '{name}': only game/ defines globals, its SavedVariables and "
                      "SLASH_* (missing 'local'? data goes in ns: docs/structure.md)")
            elif op == "get" and name in GLOBAL_ESCAPES and not strict:
                print(f"{rel}:{line}: uses '{name}', which reaches globals past this check: use a local or ns")
            elif op == "get" and name not in allowed and (strict or name not in set_anywhere):
                print(f"{rel}:{line}: reads unknown global '{name}' (typo? or add it to {os.path.relpath(allowlist, ROOT)})")
            else:
                continue
            reported.add((op, name))
            problems += 1
    if not strict:  # the default run: the boundaries too
        problems += check_boundaries(accesses) + check_ns(paths)
    return problems


def gitignored(paths: list[str]) -> set[str]:
    if not paths:
        return set()
    r = subprocess.run(["git", "-C", ROOT, "check-ignore", "--no-index", *paths], capture_output=True, text=True)
    return set(r.stdout.split())


def existing_toc_files() -> list[str]:
    """The TOC's files that are here; a missing one may only be gitignored."""
    listed = toc_files()
    missing = [f for f in listed if not os.path.exists(os.path.join(ROOT, f))]
    ignored = gitignored(missing)
    return [f for f in listed if f not in missing or f not in ignored]


def addon_lua() -> list[str]:
    """Every .lua under the addon's folders, subfolders too (game/parts/...)."""
    out = []
    for d in ADDON_DIRS:
        for dirpath, _, filenames in os.walk(os.path.join(ROOT, d)):
            out += [os.path.relpath(os.path.join(dirpath, f), ROOT).replace(os.sep, "/")
                    for f in filenames if f.endswith(".lua")]
    return out


def check_toc() -> int:
    from install import toc  # (install imports this module)
    problems = 0
    with open(TOC, encoding="utf-8") as fh:
        if fh.read() != toc():
            print("MagicMapAtlas.toc: isn't what the files.txt manifests make: run tools/install.py --toc")
            problems += 1
    listed = toc_files()
    for f in existing_toc_files():
        if not os.path.exists(os.path.join(ROOT, f)):
            print(f"MagicMapAtlas.toc: lists {f}, which doesn't exist")
            problems += 1
    on_disk = addon_lua()
    for f in sorted(set(on_disk) - set(listed)):
        print(f"MagicMapAtlas.toc: {f} isn't listed (its folder's files.txt), so the game never loads it")
        problems += 1
    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--globals", action="store_true", help="list each file's global reads and writes")
    parser.add_argument("--allow", default=ALLOWLIST, help="globals the files may read (default: tools/wow_globals.txt)")
    parser.add_argument("files", nargs="*", help="default: everything in MagicMapAtlas.toc")
    ns = parser.parse_args()
    if ns.files:
        paths, problems = [os.path.abspath(f) for f in ns.files], 0
    else:
        problems = check_toc()
        paths = [os.path.join(ROOT, f) for f in existing_toc_files() if os.path.exists(os.path.join(ROOT, f))]
    problems += check(paths, ns.globals, os.path.abspath(ns.allow))
    if not ns.globals:
        print(f"{len(paths)} files, {problems} problem{'s' if problems != 1 else ''}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()

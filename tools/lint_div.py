#!/usr/bin/env python3
"""Every `/` in the addon's code must be one that can't divide by 0 (spike-bugs E3):
WoW's Lua raises "Division by zero" where plain Lua, so the tests, gives inf or nan.

In atlas/, model/, game/, ui/ and runtime/ (subfolders too), a `/` passes when its
divisor is a numeric literal other than 0, a named constant (an UPPER_CASE name of two
or more characters, so not a local like `W`: `TILE_YARDS`, `Atlas.TILE_YARDS`), or its
line says why it's never 0:

    local u = d / n -- /: never 0 (n counts the segments, at least 1)

Fix at the source first (a minimum, a constant); the comment is for a divisor that's
non-zero by construction. docs/structure.md "Rules".

  python3 tools/lint_div.py              # the addon's folders
  python3 tools/lint_div.py ui/Foo.lua   # just these
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["atlas", "model", "game", "ui", "runtime"]  # not Data/: generated
WHY = re.compile(r"/:\s*never 0 \(.+\)")
CONSTANT = re.compile(r"[A-Z][A-Z0-9_]+$")
NUMBER = re.compile(r"0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
NAME = re.compile(r"[A-Za-z_]\w*")
LONG = re.compile(r"\[(=*)\[")
SYMBOL = re.compile(r"\.\.\.|\.\.|==|~=|<=|>=|\S")


def tokens(src: str) -> tuple[list[tuple[str, str, int]], dict[int, str]]:
    """(kind, text, line) for each token, and each line's `--` comment text."""
    out, comments, i, line = [], {}, 0, 1
    while i < len(src):
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif src.startswith("--", i):
            m = LONG.match(src, i + 2)
            if m:
                end = src.find(f"]{m.group(1)}]", m.end()) + len(m.group(0))
            else:
                end = src.find("\n", i)
                end = len(src) if end < 0 else end
                comments[line] = src[i:end]
            line += src.count("\n", i, end)
            i = end
        elif c in "\"'":
            j = i + 1
            while src[j] != c:
                j += 2 if src[j] == "\\" else 1
            out.append(("string", src[i:j + 1], line))
            line += src.count("\n", i, j)
            i = j + 1
        elif LONG.match(src, i):
            m = LONG.match(src, i)
            end = src.find(f"]{m.group(1)}]", m.end()) + len(m.group(0))
            out.append(("string", src[i:end], line))
            line += src.count("\n", i, end)
            i = end
        elif (m := NUMBER.match(src, i)) and (c.isdigit() or src[i + 1:i + 2].isdigit()):
            out.append(("number", m.group(0), line))
            i = m.end()
        elif m := NAME.match(src, i):
            out.append(("name", m.group(0), line))
            i = m.end()
        else:
            m = SYMBOL.match(src, i)
            out.append(("op", m.group(0), line))
            i = m.end()
    out.append(("eof", "", line))
    return out, comments


CLOSE = {"(": ")", "[": "]", "{": "}"}


def balanced(toks, i: int) -> int:
    """The index past the bracket that closes toks[i]."""
    depth = 0
    while toks[i][0] != "eof":
        if toks[i][1] in CLOSE and toks[i][0] == "op":
            depth += 1
        elif toks[i][1] in CLOSE.values() and toks[i][0] == "op":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def operand(toks, i: int) -> int:
    """The index past the right operand of a `/` starting at toks[i]: unary operators,
    a value (a prefix expression with its fields, indexes and calls), then any `^ operand`."""
    while toks[i][1] in ("-", "not", "#"):
        i += 1
    kind, text, _ = toks[i]
    i = balanced(toks, i) if text in ("(", "{") else i + 1
    if text == "(" or (kind == "name" and text not in ("nil", "true", "false")):
        while True:
            k, t, _ = toks[i]
            if k == "op" and t in (".", ":"):
                i += 2
            elif k == "op" and t in ("(", "[", "{"):
                i = balanced(toks, i)
            elif k == "string":
                i += 1
            else:
                break
    if toks[i][1] == "^":
        i = operand(toks, i + 1)
    return i


def safe(div) -> bool:
    """A numeric literal other than 0, or an UPPER_CASE name (`A.B.NAME` too)."""
    if len(div) == 2 and div[0][1] == "-":
        div = div[1:]
    if len(div) == 1 and div[0][0] == "number":
        return float.fromhex(div[0][1]) != 0 if div[0][1][:2] in ("0x", "0X") else float(div[0][1]) != 0
    names = div[::2]
    return (all(t[0] == "name" for t in names) and all(t[1] == "." for t in div[1::2])
            and bool(CONSTANT.match(names[-1][1])))


def lint(path: str) -> list[str]:
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(path, encoding="utf-8-sig") as f:
        toks, comments = tokens(f.read())
    out = []
    for i, (kind, text, line) in enumerate(toks):
        if kind != "op" or text != "/":
            continue
        div = toks[i + 1:operand(toks, i + 1)]
        if safe(div) or WHY.search(comments.get(line, "")):
            continue
        out.append(f"{rel}:{line}: / {shown(div)} may be 0")
    return out


def shown(div) -> str:
    """The divisor as written, near enough: `obj:Get()`, `(c1 - c0)`."""
    out = ""
    for i, (_, text, _) in enumerate(div):
        tight = i == 0 or text in (")", "]", ".", ":", "(", "[") or div[i - 1][1] in ("(", "[", ".", ":", "#") \
            or (i == 1 and div[0][1] == "-")
        out += text if tight else " " + text
    return out


def addon_lua() -> list[str]:
    return sorted(os.path.join(dirpath, f) for d in DIRS for dirpath, _, files in os.walk(os.path.join(ROOT, d))
                  for f in files if f.endswith(".lua"))


def main() -> None:
    paths = [os.path.abspath(p) for p in sys.argv[1:]] or addon_lua()
    problems = [p for path in paths for p in lint(path)]
    if problems:
        print("\n".join(problems))
        sys.exit(f"lint_div: {len(problems)} / that may be 0, in {len(paths)} files. WoW raises on x/0 (spike-bugs E3): "
                 "divide by a literal or a NAMED constant, fix it at the source, or end the line -- /: never 0 (why)")
    print(f"lint_div: {len(paths)} files, every / by a literal, a constant or a reason")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""One package's (or milestone's) slice of the docs and code, in one read (docs/brief.md first).

  .venv/bin/python tools/brief.py M2.1    # a package: its docs/v1-plan.md §6 row, its milestone's Goal and Exit,
                                          # an outline of each Owner file, the replays and tests its row names,
                                          # the types/ blocks and decision records of its contracts, its
                                          # docs/parity.md and docs/evidence/spike-bugs.md rows, the spike files
                                          # they cite, the public functions around it, other mentions (file:line)
  .venv/bin/python tools/brief.py M2      # a milestone: Goal, Exit, every row, their parity and spike-bugs rows
  .venv/bin/python tools/brief.py M1b     # (M2 gate: its milestone's)
  .venv/bin/python tools/brief.py --list  # the ids

A row "mentions" a package when it names its id (a range like M2.1–M2.4 counts); a parity row also
when it names an Owner path; a spike-bugs row also when the package's row or its parity rows' Proof
name it (R-<id>, or a bare E/P/L/G/K id; R-* is every row whose replay is v1 or no). Contract blocks
are picked by name (the Contracts cell's words, then the title's and owner files'), by owner folder
(FOLDER_TYPES), then the classes they refer to. Outlines are a regex's (functions, tables, UPPER_CASE
constants, registrations), not a parser's.
"""
from __future__ import annotations

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = "docs/v1-plan.md"
PARITY = "docs/parity.md"
BUGS = "docs/evidence/spike-bugs.md"
SPIKE = os.path.expanduser("~/code/MagicMap")  # the spec (D4), read-only
CODE_DIRS = ["atlas", "game", "model", "ui", "runtime", "tools"]
HEADER_LINES = 12  # of a file's leading comment
SNIPPET = 220  # chars of a mention's line

PKG = re.compile(r"(?<![\w.])(M\d+\.\d+b?)(?![\w])")
RANGE = re.compile(r"(?<![\w.])M(\d+)\.(\d+)\s*[–-]\s*M?(\d+)\.(\d+)")
REPLAY = re.compile(r"\bR-([A-Z]\d+[a-z]?)\b")
BARE = re.compile(r"(?<![\w-])([EPLGK]\d+[a-z]?)\b")  # a spike-bugs id without R- (D, S, M ones read as decisions, parity, milestones)
TEST = re.compile(r"\btest_\w+")
PATH = re.compile(r"[\w.-]+(?:/[\w.-]*)*")
LINK = re.compile(r"\[`([^`]+)`\]\([^)]*\)")  # [`test_replay[E1]`](../../tools/...) -> test_replay[E1]
SPIKE_REF = re.compile(r"(?<![\w/.])([A-Z]\w+\.lua)(?::(\d+(?:-\d+)?(?:,\s*\d+(?:-\d+)?)*))?")

LUA_DEF = re.compile(r"^(?:local\s+)?function\s+[\w.:]+\s*\(|^(?:local\s+)?[\w.]+\s*=\s*function\s*\(")
LUA_TABLE = re.compile(r"^(?:local\s+)?[\w.]+(?:\s*,\s*[\w.]+)*\s*=\s*\{")
LUA_CONST = re.compile(r"^local\s+[A-Z][A-Z0-9_]+(?:\s*,\s*[A-Z][A-Z0-9_]+)*\s*=(?!\s*ns\.)")  # not `local UI = ns.UI`
LUA_REG = re.compile(r"\b(?:Engine\.Layer|Game\.(?:Part|Handle|Apply|Slash|Load)|Model\.(?:Part|Kind)"
                     r"|Runtime\.(?:Step|On|Every|After|Job|Worker))\s*\(|kind\s*=\s*\"(?:slash|load)\"")
PY_DEF = re.compile(r"^(?:class|def)\s|^    def\s|^[A-Z][A-Z0-9_]+\s*=")

# Contract words that don't name a types/ block themselves.
ALIASES = {
    "group": ["MM.ObsMember", "MM.KnownMember"],
    "sv": ["MM.SavedRoot", "MM.SavedSpec"],
    "savedvariable": ["MM.SavedRoot", "MM.SavedSpec"],
    "part": ["MM.Observation"],
    "pick": ["MM.KnownOffer"],  # the "Quests to pick up" layer
}
# Words of a Contracts cell that name no contract.
FILLER = {"none", "typed", "already", "read", "from", "open", "field", "shape", "locked", "change", "lua", "only",
          "of", "the", "and", "clause", "free", "form", "stated", "loss", "key", "spike", "name", "storage"}
# And of a package's title and owner names, too common to pick a types/ block by.
STOP = FILLER | {"ui", "game", "model", "map", "data", "with", "for", "full", "complete", "remaining", "new",
                 "stub", "section", "line", "layer", "cleanup", "store", "kind"}
# An owner folder's packages read these types/ blocks, and those of a family their row's words name
# (its title, owners, Scope: MM.KnownQuest by "quests"); "*": the whole family.
FOLDER_TYPES = {
    "game/parts/": (["MM.Observation"], "MM.Obs"),
    "model/": (["MM.Oracles", "MM.Focus"], "MM.Known*"),
    "ui/": (["MM.Known"], "MM.Known"),
}
HUB = 4  # a block referring to more classes than this (MM.Observation, MM.View) isn't followed


def read(rel: str) -> list[str]:
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read().split("\n")


def norm(word: str) -> str:
    w = word.lower()
    return w[:-1] if len(w) > 3 and w.endswith("s") and not w.endswith("ss") else w


def camel(name: str) -> list[str]:
    return [norm(t) for t in re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+", name)]


def ids_in(text: str) -> set[str]:
    """Package ids a text names, a range's ids included."""
    out = set(PKG.findall(text))
    for m, a, m2, b in RANGE.findall(text):
        if m == m2:
            out |= {f"M{m}.{i}" for i in range(int(a), int(b) + 1)}
    return out


def cells(row: str) -> list[str]:
    return [c.strip() for c in row.strip().strip("|").split(" | ")]


def snippet(line: str, at: int) -> str:
    line = line.strip()
    if len(line) <= SNIPPET:
        return line
    lo = max(0, min(at - SNIPPET // 3, len(line) - SNIPPET))
    return ("…" if lo else "") + line[lo:lo + SNIPPET] + ("…" if lo + SNIPPET < len(line) else "")


# docs/v1-plan.md §6 -------------------------------------------------------------------------

class Plan:
    def __init__(self):
        self.lines = read(PLAN)
        self.milestones = {}  # "M2" -> {title, line, goal, exit, rows, after}
        self.rows = {}  # "M2.1" -> {id, title, line, cells, milestone}
        at = {l[3:5]: i for i, l in enumerate(self.lines) if l.startswith("## ")}
        start, end = at["6."], at["7."]
        self.checklist = range(at["5."] + 1, start + 1)  # §5: parity.md's F rows say it all
        ms = None
        for i in range(start, end):
            line = self.lines[i]
            head = re.match(r"### (M\d+b?) (.*)", line)
            if head:
                ms = {"id": head[1], "title": head[2], "line": i + 1, "goal": [], "exit": [], "rows": [],
                      "after": []}
                self.milestones[head[1]] = ms
                continue
            if not ms:
                continue
            if line.startswith(("Goal:", "Exit:")):
                j = i
                while j < end and self.lines[j].strip():
                    ms[line[:4].lower()].append((j + 1, self.lines[j]))
                    j += 1
            elif line.startswith("| M"):
                c = cells(line)
                pid = c[0].split(" ")[0]
                if len(c) == 6 and re.fullmatch(r"M\d+(\.\d+b?)?", pid):
                    title = c[0][len(pid):].strip()
                    if title.startswith("gate"):
                        pid, title = f"{pid} gate", ""
                    row = {"id": pid, "title": title, "line": i + 1, "cells": c, "milestone": ms["id"]}
                    self.rows[pid] = row
                    ms["rows"].append(row)
            elif line.strip() and not line.startswith(("|", "Legend")) and ms["rows"]:
                ms["after"].append((i + 1, line))


# Owner files ----------------------------------------------------------------------------

def repo_files() -> list[str]:
    out = []
    for d in CODE_DIRS + ["Data", "Textures", "docs", "types"]:
        for p in glob.glob(os.path.join(ROOT, d, "**", "*"), recursive=True):
            if os.path.isfile(p):
                out.append(os.path.relpath(p, ROOT))
    return out


def owner_paths(owner: str, files: list[str]) -> list[str]:
    """The paths an Owner cell names: a bare name is in the folder of the path before it."""
    out, folder = [], ""
    for tok in PATH.findall(owner.replace("`", "")):
        tok = tok.rstrip(".,;")
        if "/" in tok:
            path = tok.rstrip("/")
            if os.path.isdir(os.path.join(ROOT, path)) or tok.endswith("/"):
                folder = path
                out.append(path + "/")
                continue
            folder = os.path.dirname(path)
            out.append(path)
        elif re.search(r"\.(lua|py|md|sh|tga|txt)$", tok) and folder:
            path = f"{folder}/{tok}"
            if not os.path.exists(os.path.join(ROOT, path)):
                top = folder.split("/")[0]
                same = [f for f in files if os.path.basename(f) == tok and f.startswith(top + "/")]
                if len(same) == 1:
                    path = same[0]
            out.append(path)
    return list(dict.fromkeys(out))


def outline(path: str) -> list[str]:
    full = os.path.join(ROOT, path)
    if path.endswith("/"):
        names = sorted(os.listdir(full)) if os.path.isdir(full) else []
        return [f"  folder: {len(names)} entries" + (f": {', '.join(names)}" if len(names) <= 30 else "")]
    if not os.path.exists(full):
        return ["  (new: not in the tree yet)"]
    if path.startswith("Data/") or not re.search(r"\.(lua|py|md|sh|txt)$", path):
        return [f"  (generated or binary: {os.path.getsize(full) // 1024} KB; not outlined)"]
    lines = read(path)
    out = [f"  {len(lines)} lines"]
    if path.endswith(".md"):
        return out + [f"  {n:5}  {l}" for n, l in enumerate(lines, 1) if l.startswith("#")]
    head = []
    if path.endswith(".lua"):
        for l in lines:
            if not l.startswith("--"):
                break
            head.append(l)
    elif path.endswith(".py"):
        m = re.search(r'"""(.*?)"""', "\n".join(lines[:60]), re.S)
        head = m[1].strip().split("\n") if m else []
    if head:
        out += ["  | " + l for l in head[:HEADER_LINES]]
        if len(head) > HEADER_LINES:
            out.append(f"  | … ({len(head) - HEADER_LINES} more lines)")
    for n, l in enumerate(lines, 1):
        if path.endswith(".lua"):
            hit = (LUA_DEF.match(l) or LUA_TABLE.match(l) or LUA_CONST.match(l)
                   or (LUA_REG.search(l) and not l.lstrip().startswith("--")))
        else:
            hit = PY_DEF.match(l)
        if hit:
            text = l.rstrip()
            out.append(f"  {n:5}  {text if len(text) <= 150 else text[:150] + '…'}")
    return out


def manifests(paths: list[str]) -> list[str]:
    out = []
    for folder in dict.fromkeys(os.path.dirname(p.rstrip("/")) for p in paths):
        man = os.path.join(folder, "files.txt")
        if os.path.exists(os.path.join(ROOT, man)):
            names = [os.path.basename(l) for l in read(man) if l.strip()]
            out.append(f"{man}: {', '.join(names)}")
    return out


# types/ and docs/decisions/ ----------------------------------------------------------------

def type_blocks() -> list[dict]:
    """Each doc-comment run of a types/ file with what it names: @class, @alias, a function."""
    out = []
    for path in sorted(glob.glob(os.path.join(ROOT, "types", "*.lua"))):
        rel = os.path.relpath(path, ROOT)
        lines = read(rel)
        i = 0
        while i < len(lines):
            if not lines[i].startswith("---") or lines[i].startswith("---@meta"):
                i += 1
                continue
            j = i
            while j < len(lines) and lines[j].startswith("---"):
                j += 1
            names = re.findall(r"^---@(?:class|alias)\s+([\w.]+)", "\n".join(lines[i:j]), re.M)
            if not names:  # a kind told in words only: ---Known("blips"): ...
                names = ["MM.Known" + k.capitalize() for k in re.findall(r'Known\("(\w+)"\)', "\n".join(lines[i:j]))]
            if j < len(lines):
                fn = re.match(r"function\s+([\w.]+)", lines[j])
                if fn:
                    names.append(fn[1])
                if lines[j].strip() and not lines[j].startswith("--"):
                    if re.match(r"local\s+\w+\s*=\s*\{\s*$", lines[j]):  # a table literal: to its end
                        while j < len(lines) and lines[j] != "}":
                            j += 1
                    j += 1
            if names:
                out.append({"file": rel, "start": i + 1, "end": j, "names": names, "text": lines[i:j]})
            i = j
    return out


def block_tokens(name: str) -> tuple[list[str], str]:
    """(camel tokens: the table's first for a function, then the name's own; the whole name normalised)."""
    parts = name.split(".")
    if parts[0] == "MM":
        parts = parts[1:]
    own = parts[-1]
    toks = camel(own)
    if len(parts) > 1:  # Model.Known: first the table
        toks = camel(parts[0])[:1] + toks
    return toks, norm("".join(parts))


def decisions() -> dict[str, dict]:
    out = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "docs", "decisions", "*.md"))):
        rel = os.path.relpath(path, ROOT)
        lines = read(rel)
        num = os.path.basename(rel)[:4]
        types = re.findall(r"types/\w+\.lua", next((l for l in lines if "Types:" in l), ""))
        out[num] = {"file": rel, "title": lines[0].lstrip("# "), "types": sorted(set(types)), "lines": lines}
    return out


def words(text: str) -> set[str]:
    """Normalised words of a text, camel names split too (IndoorArt: indoorart, indoor, art)."""
    out = set()
    for w in re.findall(r"[A-Za-z]{3,}", text):
        out |= {norm(w)} | set(camel(w))
    return out


def contracts(row: dict, owners: list[str], adrs: dict[str, dict], blocks: list[dict]):
    """The types/ blocks the row's Contracts cell, title and owners name, its owner folders' (FOLDER_TYPES),
    and the classes those refer to (MM.X); the decision records the cell names."""
    cell, scope = row["cells"][3], row["cells"][2]
    named = re.findall(r"\b(\d{4})\b", cell)
    strong = {norm(w) for w in re.findall(r"[A-Za-z]{2,}", cell)} - FILLER
    weak = words(row["title"] + " " + " ".join(os.path.basename(p) for p in owners if not p.endswith("/")))
    want = {n for w in strong | weak for n in ALIASES.get(w, [])}
    weak -= STOP | set(ALIASES)
    by_name = {n: b for b in blocks for n in b["names"]}
    picked = []
    for b in blocks:
        for name in b["names"]:
            toks, whole = block_tokens(name)
            if (name in want or whole in strong or toks[0] in strong or toks[-1] in strong
                    or toks[-1] in weak or whole in weak):
                picked.append(b)
                break
    kinds = (weak | words(scope)) - STOP
    kinds |= {n for w in kinds for n in ALIASES.get(w, [])}
    for folder, (always, family) in FOLDER_TYPES.items():
        if any(p.startswith(folder) for p in owners):
            picked += [by_name[n] for n in always]
            picked += [b for b in blocks for n in b["names"] if n.startswith(family.rstrip("*"))
                       and (family.endswith("*") or n in kinds or block_tokens(n)[0][-1] in kinds)]
    # The classes they refer to (not a hub's: MM.Observation's parts are picked by name), and a class's
    # functions (`local Oracles = {}`: Oracles.Inside).
    todo = list(picked)
    while todo:
        b = todo.pop()
        text = "\n".join(b["text"])
        refs = [by_name[n] for n in dict.fromkeys(re.findall(r"MM\.\w+", text))
                if n in by_name and by_name[n]["file"] != "types/core.lua" and by_name[n] is not b]
        local = re.search(r"^local (\w+) = \{\}$", text, re.M)
        if local:
            refs += [o for o in blocks if o["file"] == b["file"] and o["names"][0].startswith(local[1] + ".")]
        for r in refs if len(refs) <= HUB else []:
            if r not in picked:
                picked.append(r)
                todo.append(r)
    return named, [b for b in blocks if b in picked]


def adr_pointers(adr: dict, ids: set[str]) -> list[str]:
    out = [f"{adr['file']}: {adr['title']} (types: {', '.join(adr['types']) or '—'})"]
    for n, l in enumerate(adr["lines"], 1):
        if l.startswith("## ") or l.startswith("Locked:") or (ids & ids_in(l)):
            out.append(f"  {adr['file']}:{n}  {snippet(l, 0)}")
    return out


# docs/parity.md and docs/evidence/spike-bugs.md ---------------------------------------------

def table_rows(rel: str) -> list[dict]:
    """Each table row with its header's columns: {line, id, cols: [(name, value)], raw}."""
    out, header = [], None
    for n, l in enumerate(read(rel), 1):
        if not l.startswith("|"):
            header = None
            continue
        if header is None:
            header = cells(l)
            continue
        if set(l.replace("|", "").strip()) <= {"-", " "}:
            continue
        c = [v.replace("\\|", "|") for v in cells(l)]
        out.append({"line": n, "id": c[0], "cols": list(zip(header, c)), "raw": l})
    return out


def bug_rows() -> list[dict]:
    return [r for r in table_rows(BUGS) if re.fullmatch(r"[A-Z]\d+[a-z]?", r["id"])]


def col(r: dict, name: str) -> str:
    return next((v for k, v in r["cols"] if k.startswith(name)), "")


def replay_sketches() -> dict[str, tuple[int, list[str]]]:
    lines = read(BUGS)
    out = {}
    for i, l in enumerate(lines):
        m = re.match(r"- \*\*R-([A-Z]\d+[a-z]?) ", l)
        if not m:
            continue
        j = i + 1
        while j < len(lines) and not lines[j].startswith(("- **R-", "#")):
            j += 1
        block = lines[i:j]
        while block and not block[-1].strip():
            block.pop()
        out[m[1]] = (i + 1, block)
    return out


def show_row(rel: str, r: dict) -> list[str]:
    return [f"{r['id']} ({rel}:{r['line']})"] + [f"  {k}: {v}" for k, v in r["cols"][1:]]


def short_row(rel: str, r: dict) -> str:
    """One line: a parity row's name, package, status; a spike-bugs row's owner, verdict, replay."""
    if rel == PARITY:
        name = r["cols"][1][1]
        return f"{r['id']} ({rel}:{r['line']}) {name} · {col(r, 'Package')} · {col(r, 'Status')[:160]}"
    verdict = re.match(r"\*\*(\w+)\*\*", col(r, "verdict"))
    replay = LINK.sub(r"\1", col(r, "replay"))[:100]
    return (f"{r['id']} ({rel}:{r['line']}) {col(r, 'owner')} · {verdict[1] if verdict else '?'} · "
            f"{col(r, 'symptom')[:120]} · replay: {replay}")


def bugs_section(text: str, ids: set[str], short: bool) -> tuple[list[str], list[dict]]:
    """Spike-bugs rows naming the ids or that the text names (R-<id>, or bare: L5); R-* is every row whose
    replay is still to write (v1, no)."""
    replays = set(REPLAY.findall(text))
    rows = [r for r in bug_rows() if r["id"] in replays | set(BARE.findall(text)) or ids & ids_in(r["raw"])]
    out = []
    for r in rows:
        out += [short_row(BUGS, r)] if short else show_row(BUGS, r)
    if "R-*" in text:
        rest = [r for r in bug_rows() if not col(r, "replay").startswith("now")]
        out += ([""] if out else []) + ["Not replayed yet (R-* in the row: replay v1 or no):"]
        out += [short_row(BUGS, r) for r in rest if col(r, "replay").startswith(("v1", "no"))]
        out += ["", "Proven another way (no replay to write):"]
        out += [f"{r['id']} ({BUGS}:{r['line']}) proven by {col(r, 'replay')}" for r in rest
                if not col(r, "replay").startswith(("v1", "no"))]
    sketches = replay_sketches()
    for rid in sorted(replays):
        if rid in sketches:
            n, block = sketches[rid]
            out += [f"(replay sketch R-{rid}, {BUGS}:{n})"] if short else [f"(replay sketch, {BUGS}:{n})"] + block
    return out or ["(none)"], rows


def api(folder: str, skip=()) -> list[str]:
    """A folder's public functions (function X.Y(...)) in its files.txt's order, but for the files skipped."""
    out = []
    for path in [l for l in read(f"{folder}/files.txt") if l.startswith(f"{folder}/") and l not in skip]:
        for n, l in enumerate(read(path), 1):
            m = re.match(r"function ([A-Z]\w*\.\w+\s*\([^)]*\))", l)
            if m:
                sig = re.sub(r"^(Camera|Walk)\.", r"Atlas.\1.", m[1]) if folder == "atlas" else m[1]
                out.append(f"{sig}  {path}:{n}")
    return out


# Pointers ---------------------------------------------------------------------------------

def spike_refs(texts: list[str]) -> list[str]:
    """The spike's files these cite (Layers.lua:303-400), with what's cited of each."""
    refs = {}
    for t in texts:
        for name, lines in SPIKE_REF.findall(t):
            refs.setdefault(name, [])
            if lines and lines not in refs[name]:
                refs[name].append(lines)
    out = []
    for name, lines in sorted(refs.items()):
        path = os.path.join(SPIKE, name)
        if os.path.exists(path):
            with open(path, encoding="utf-8", errors="replace") as f:
                size = f"{sum(1 for _ in f)} lines"
        else:
            size = "gone from its tree"
        out.append(f"{path} ({size})" + (f": {', '.join(lines)}" if lines else ""))
    return out


def named_files(text: str, skip: list[str]) -> list[str]:
    """Paths of the addon or tools a row's text names, beyond its owners: what each is now."""
    out = []
    for p in dict.fromkeys(re.findall(r"\b(?:atlas|game|model|ui|runtime|tools|docs|types|Data)/[\w./-]*\w", text)):
        if p in skip:
            continue
        full = os.path.join(ROOT, p)
        if os.path.isfile(full):
            out.append(f"{p} ({len(read(p))} lines)" if p.endswith((".lua", ".py", ".md")) else p)
        else:
            out.append(f"{p}" + ("" if os.path.isdir(full) else " (not in the tree)"))
    return out


def mentions(ids: set[str], paths: list[str], skip: set[tuple[str, int]]) -> list[str]:
    files = sorted(glob.glob(os.path.join(ROOT, "docs", "*.md"))) + ["architecture.md", "README.md"]
    for d in CODE_DIRS:
        for ext in ("lua", "py", "sh"):
            files += sorted(glob.glob(os.path.join(ROOT, d, "**", f"*.{ext}"), recursive=True))
    out = []
    for path in files:
        rel = os.path.relpath(os.path.join(ROOT, path), ROOT)
        if rel in (PARITY, BUGS, "tools/brief.py") or rel in paths:
            continue
        for n, l in enumerate(read(rel), 1):
            if (rel, n) in skip:
                continue
            found = ids & ids_in(l)
            if found:
                out.append(f"{rel}:{n}: {snippet(l, min((l.find(i) for i in found if i in l), default=0))}")
    return out


def verify_names(text: str, files: list[str]) -> list[str]:
    out = []
    for rid in dict.fromkeys(REPLAY.findall(text)):
        path = f"tools/tests/replays/R-{rid}.lua"
        out.append(f"R-{rid}: {path}" + ("" if os.path.exists(os.path.join(ROOT, path)) else " (new)"))
    tests = [f for f in files if re.match(r"tools/tests/test_\w+\.py$", f)]
    for name in dict.fromkeys(TEST.findall(text)):
        path = f"tools/tests/{name}.py"
        if path in tests:
            out.append(f"{name}: {path}")
            continue
        where = [f"{t}:{n}" for t in tests for n, l in enumerate(read(t), 1) if re.match(rf"def {name}\b", l)]
        out.append(f"{name}: {', '.join(where) if where else '(new)'}")
    return out


# The brief ----------------------------------------------------------------------------------

FIELDS = ["Owner", "Scope", "Contracts", "Verify", "Wave / Iso"]


def package(plan: Plan, pid: str) -> list[str]:
    row = plan.rows[pid]
    ms = plan.milestones[row["milestone"]]
    files = repo_files()
    c = row["cells"]
    out = [f"# {pid} {row['title']}  ({PLAN}:{row['line']})", ""]
    out += [f"**{k}**: {v}" for k, v in zip(FIELDS, c[1:])]
    out += ["", f"## Milestone {ms['id']} {ms['title']}  ({PLAN}:{ms['line']})", ""]
    out += [l for _, l in ms["goal"]] + [""] + [l for _, l in ms["exit"]]
    near = [l for _, l in ms["after"] if pid in ids_in(l)]
    if near:
        out += [""] + near
    out += ["", "Its packages: " + "; ".join(f"{r['id']} {r['title']}".strip() for r in ms["rows"])]

    owners = owner_paths(c[1], files)
    out += ["", "## Owner files", ""]
    if not owners:
        out.append(f"(none named: {c[1]})")
    for p in owners:
        out += [p] + outline(p)
    out += manifests(owners)
    others = named_files(" ".join(c[2:5]), owners)
    if others:
        out += ["", "Also named in its row: " + "; ".join(others)]

    names = verify_names(" ".join(c[2:5]), files)
    if names:
        out += ["", "## Replays and tests its row names", ""] + names

    adrs, blocks = decisions(), type_blocks()
    named, picked = contracts(row, owners, adrs, blocks)
    out += ["", f"## Contracts: {c[3]}", ""]
    out += [f"ADR {n}: not written yet (docs/decisions/{n}-*.md)" for n in named if n not in adrs]
    for b in picked:
        span = b["start"] if b["end"] <= b["start"] else f"{b['start']}-{b['end']}"
        out += [f"{b['file']}:{span}"] + b["text"] + [""]
    for n in sorted(set(named) | {k for k, a in adrs.items() if set(a["types"]) & {b["file"] for b in picked}}):
        if n in adrs:
            out += adr_pointers(adrs[n], {pid})
    if not picked and not named:
        out.append("(none named)")

    ids = {pid}
    out += ["", f"## {PARITY} rows", ""]
    rows = [r for r in table_rows(PARITY) if ids & ids_in(r["raw"]) or any(p in r["raw"] for p in owners)]
    for r in rows:
        out += show_row(PARITY, r)
    if not rows:
        out.append("(none)")

    lines, bugs = bugs_section(" ".join(c[2:5] + [col(r, "Proof") for r in rows]), ids, short=False)
    out += ["", f"## {BUGS} rows", ""] + lines

    refs = spike_refs([" ".join(c[2:5])] + [col(r, "Spike ref") + " " + col(r, "Value") for r in rows]
                      + [col(r, "spike file") for r in bugs])
    if refs:
        out += ["", "## The spike's code it cites (the spec, D4)", ""] + refs

    for folder in dict.fromkeys(p.split("/")[0] for p in owners):
        if folder in ("ui", "game", "model", "runtime"):
            out += ["", f"## The rest of {folder}/: its public functions (grep the file for the comment)", ""]
            out += api(folder, owners)
    if any(p.startswith(("model/", "ui/", "game/")) for p in owners) or "Atlas" in " ".join(c[2:5]):
        out += ["", "## Atlas's API (atlas/: any piece may read it)", ""] + api("atlas")

    skip = ({(PLAN, row["line"])} | {(PLAN, n) for n, _ in ms["goal"] + ms["exit"] + ms["after"]}
            | {(PLAN, n) for n in plan.checklist})
    out += ["", "## Mentioned elsewhere", ""] + (mentions(ids, owners, skip) or ["(nowhere else)"])
    return out


def milestone(plan: Plan, mid: str) -> list[str]:
    ms = plan.milestones[mid]
    files = repo_files()
    out = [f"# {mid} {ms['title']}  ({PLAN}:{ms['line']})", ""]
    out += [l for _, l in ms["goal"]] + [""] + [l for _, l in ms["exit"]]
    ids = {r["id"] for r in ms["rows"]}
    for r in ms["rows"]:
        out += ["", f"## {r['id']} {r['title']}  ({PLAN}:{r['line']})"]
        out += [f"**{k}**: {v}" for k, v in zip(FIELDS, r["cells"][1:])]
        status = []
        for p in owner_paths(r["cells"][1], files):
            full = os.path.join(ROOT, p)
            status.append(p + (f" ({len(read(p))} lines)" if os.path.isfile(full) and p.endswith(".lua")
                               else "" if os.path.exists(full) else " (new)"))
        if status:
            out.append("Owner files: " + ", ".join(status))
    if ms["after"]:
        out += [""] + [l for _, l in ms["after"]]

    alone = re.compile(rf"(?<![\w.]){re.escape(mid)}(?![\w.])")
    out += ["", f"## {PARITY} rows", ""]
    rows = [r for r in table_rows(PARITY)
            if r["id"] != mid and (ids & ids_in(r["raw"]) or alone.search(r["raw"]))]  # not the sign-off's row
    out += [short_row(PARITY, r) for r in rows]

    text = " ".join([l for _, l in ms["exit"]] + [" ".join(r["cells"][2:5]) for r in ms["rows"]]
                    + [col(r, "Proof") for r in rows])
    out += ["", f"## {BUGS} rows", ""] + bugs_section(text, ids, short=True)[0]

    adrs = decisions()
    named = sorted({n for r in ms["rows"] for n in re.findall(r"\b(\d{4})\b", r["cells"][3])})
    if named:
        out += ["", "## Decision records its rows name", ""]
        for n in named:
            out += adr_pointers(adrs[n], ids) if n in adrs else [f"ADR {n}: not written yet"]
    out += ["", f"A package's owner outlines, types/ blocks and full rows: tools/brief.py {ms['rows'][0]['id']}"]
    return out


def main() -> None:
    plan = Plan()
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return
    if args[0] == "--list":
        for mid, ms in plan.milestones.items():
            print(f"{mid} {ms['title']}")
            for r in ms["rows"]:
                print(f"  {r['id']} {r['title']}".rstrip())
        return
    key = {k.lower(): k for k in [*plan.rows, *plan.milestones]}.get(args[0].strip().lower())
    if key in plan.rows and not key.endswith(" gate"):
        out = package(plan, key)
    elif key:
        out = milestone(plan, key.split()[0])  # a gate: its milestone's Exit and rows
    else:
        sys.exit(f"brief: no package or milestone {args[0]!r} (tools/brief.py --list)")
    print("\n".join(out))


if __name__ == "__main__":
    main()

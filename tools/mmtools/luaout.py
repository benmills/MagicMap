"""Writing Lua literals for the generated Data/*.lua files."""
from __future__ import annotations


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

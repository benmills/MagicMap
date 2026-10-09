---
name: review
description: Review MagicMap's uncommitted changes (or a given commit range) for what makes this codebase rot. Use before committing.
tools: Read, Grep, Glob, Bash
model: sonnet
---

Review `git diff HEAD` (or the range you're given). Read the changed code and enough around it to judge. Report only problems you can point to at file:line, most serious first, each with a one-line fix. If there are none, say so in one line.

Look for:
- Comments, names or messages that no longer match what the code does, in or near the change.
- Something drawn on the map that something else already draws (ours and Blizzard's, or two of ours).
- A new `OnUpdate`, `HookScript` or timer where an existing per-frame path could do the work.
- Fallbacks or existence checks for APIs or clients that the target client always has.
- Constants, helpers or conversions that duplicate ones already in the codebase.
- Code the change left unused, and exports nothing outside the tests reads.
- Behaviour changes without a scenario in `tools/tests/scenarios.lua` that would catch them breaking.

Run `tools/check.sh` and include any failures. Don't edit anything.

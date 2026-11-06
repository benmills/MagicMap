# 0010 Settings: each owner declares its own

Status: **proposed** (hardening pass, 2026-10-27). Ledger rows S1-S5, S8, C1 (docs/hardening-plan.md).
Decision 1 is built (#15: `Feel.Add(page, section, { ... })` in each owner, the pages `Feel.Page`), and 2's
checks at load (`Feel.Loaded`) with each apply wrapped; the OnShow push, `clusterTune` and the migrations (2-5)
stay as they were.

## Context

ui/Feel.lua (the settings window) declares every setting in one KEYS table. The code that uses a setting keeps
its own copy of the default. Which copy wins depends on the setting:
- Feel's wins for icon size, ring and pills (pushed on the window's OnShow).
- The owner's wins for the tracking line and quest areas (read through `Feel.Get`, with Feel keeping fallback
  copies because those files load after it).

Values reach owners two ways: the OnShow push, and rev polling. The tracking-line reload bug came from that
split (a saved look ignored until a setting changed). The same pattern is still latent in the OnShow push and
in Grouping's tunables (S2, S4). Nothing range-checks a saved value, and one bad one stops the push for all
the rest (S3). Settings live in five places in saved data:
- `feel`;
- `clusterTune`;
- `layers`;
- `replace`;
- plain keys (`button`, `cluster`, `debug`).

## Decision

**1. Owners declare.** Feel keeps the registry and the window; each owner file registers its own settings
at load:

    Feel.Key{ key, page, label, kind, min, max, step, options, default, tip, apply? }

The window is built from the registry on first open, when every owner has loaded. The page list stays in
Feel. The default lives only in the owner's declaration, so Feel keeps no fallbacks (fixes S1).

**2. One way in.**
- `Feel.Get(key)` validates against its declaration (type, range, options) and returns the default for a bad
  or missing value (fixes S3).
- `apply(v)`, where a key has one, is called on Set, on Reset, and from `Feel.Loaded()` once saved data loads,
  each call wrapped on its own.
- There is no OnShow push. Owners that read lazily use `Feel.Rev(page)`, a rev for each page, so the
  tracking line doesn't re-read on a Grouping change (fixes S2, S4).

**3. One store.**
- Grouping's tunables move from `clusterTune` into `feel` as `group.*` keys.
- The rares-to-vignettes link moves into one linked-toggles table that Engine.SetLayer honours, so
  `/mm layer rares` and the gear agree (fixes S5).
- Toggles (`layers`), `replace` and the plain switches stay where they are. They aren't looks, and Feel
  already reads them through get/set.

**4. Real migrations.**
- UI's saved part goes to version 2 with a `spec.migrate`. It moves `clusterTune` into `feel`, and does
  Replace's 2.0 move and the layer-key renames that View does by hand on every load today.
- OPTIONAL is generated from types/saved.lua, or tested against it (fixes S8).

**5. One rev helper (C1).** `Rev.Of(f1, f2, ...)`: compare each input, count changes. It replaces the
hand-made combinations: sums, counters, `styleRev*1e9`.

## Consequences

- A new setting is one declaration in the file that uses it; changing a default is one edit.
- Feel.lua shrinks to the registry, the window and the push. KEYS rows move to their owners.
- Tests: the reload round trip (T3) covers every key automatically, since it walks the registry.
- Risk: low. Each owner's change is mechanical. The migration is the only part touching saved data, and the
  reload test plus a 2.1-saved fixture cover it.

## Open question for the user

Pages stay as they are (General, Map, Icons, Tracking line, Quest areas, Grouping, Diagnostics)? Owners only
name their page.

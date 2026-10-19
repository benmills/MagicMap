# 0005 Runtime's guarantees as a contract

Status: accepted (v1). Types: [types/runtime.lua](../../types/runtime.lua). Guarantees,
budgets and how each is observed: [docs/runtime.md](../runtime.md), which is the authority
for numbers. This record says what is locked, not what the numbers are.

## Context

Every system is written against Runtime: the per-frame phases from architecture.md, events,
timers, sliced jobs, timing and isolation. The spike wrapped callbacks for timing only
(`ns.Timed`), so one error could stop a whole OnUpdate. Every system needs the same
assurances (an error stays where it happened, slow work is sliced, nothing bursts after a
hitch), and they only hold if the API that gives them stays put.

## Decision

The API surface is locked: `Step(phase, name, fn, opts)`, `On(event, name, fn)`,
`After` and `Every(seconds, name, fn)` returning a handle, `Cancel(handle)`,
`Job(name, fn, budgetMs, maxFrames)` returning a handle with `done` and `err`, `Yield()`,
`Wrap(name, fn, budgetMs)`, `Trace(kind, detail)` and `TraceCopy()`, and
`onError(name, err, stack)`, which Game sets. So are the phases and their order: `input`,
`observe`, `model`, `ui`, `apply`.

So are these guarantees (docs/runtime.md states each one with its failure mode):

1. **Isolation**: every callback is wrapped. An error is caught with its stack, reported,
   and never stops another callback, phase or frame. A failing `onError` is turned off and
   is never recursive.
2. **Order**: steps run each frame in phase order, then in registration order within a
   phase. One added during a frame runs from the next.
3. **No re-entrancy**: an event fired while a frame runs (by an API call a step made)
   waits until the frame's phases are done.
4. **No bursts**: a periodic timer running late by more than a period runs once.
5. **Budgets**: a job runs only within its per-frame budget, and `Yield` gives the frame
   back. A job still running after `maxFrames` is cancelled and reported. Overruns are
   counted and traced, never enforced by killing a call.
6. **No hot failure loops**: a callback failing call after call is throttled.
7. **Trace** keeps the event shape in docs/telemetry.md.

Open: the budget numbers (`FRAME_MS`, `CALL_MS`, job defaults), the throttling policy,
the `Perf` and `FrameStats` shapes, `Grace`, `SetState` (UI's map state, for `FrameStats`
by state), `onTrace(kind, detail)` (every trace after the ring has it, set by Game: telemetry
keeps some kinds and counts others; the only other hook besides `onError`), and new optional `opts`.

## Consequences

- Systems never call `pcall` around their own callbacks or schedule with `C_Timer` or
  `OnUpdate`. luacheck catches `C_Timer` in atlas/, model/ and ui/. A raw `OnUpdate`
  script, or game/ (which may read every section), is covered by the rule only, not by a check.
- One frame's latency is the price for some flows (a command sent from a step, events
  deferred to the end of a frame). ADR 0003 and ADR 0002 accept it.
- Tests can drive frames deterministically (tools/tests/wowsim.lua) because all timing
  goes through one frame loop.
- Jobs that share a frame's budget order themselves (OPEN, the M1b review's second round:
  ui/Engine.lua's layouts): `Requeue` puts a queued job last, a job at budget 0 waits its turn
  queued and isn't resumed, and `Left` says what's left of the running job's budget, which it may
  hand to the next. "A job runs only while its budget lasts" holds: a budget of 0 lasts no time.

## Revisit if

- WoW's script-ran-too-long limit, or combat lockdown, needs a guarantee Runtime can't
  give from Lua (e.g. secure callbacks). That would be a new, separate contract.
- A phase is needed between existing ones (e.g. `late` after `apply` for layout jobs). A
  new phase name is additive, but it changes "phase order", so it needs a record.

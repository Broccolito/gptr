# Coordinator-scheduled follow-up fixes

Defects found by plan lanes and routed to the coordinator, fixed in a follow-up lane. They are not
plan tasks: the owning plan's text gives context, the coordinator's task notes are authoritative.
Each section records what was built, the deviations, the actual red/green counts, lint and log
paths (`dev/.validation/FIX/`, ignored by Git). The owning plans' progress logs carry a
cross-reference line.

## Task FIX-1 - Fix session finalizer race with registry iteration

Owners: P02 (`R/ext-registry.R`, `R/ext-events.R`, `R/ext-load.R`, `R/ext-check.R`) and P06
(`R/session-live.R`, `R/session-object.R`). Maintainer-requested. Deviation: D-085.

**Defect** (`progress/P07.md`, Task 7 review item 2 and the Task 8 test-side note). P06's
`session_finalizer()` called `ev_dispatch("session_shutdown", reason = "gc")`, and P02's
`ev_dispatch()` then ran `registry_session_drop()` on exit. R runs a finalizer wherever a
collection happens, so hooks ran and records were removed in the middle of unrelated code.
`registry_recs()` read an id snapshot and then `get()` each id, which failed with "object 'rNN'
not found" (P07's flaky "Tool 'trials' was not added: object 'r150' not found"). The same
get-after-snapshot pattern was in `registry_session_drop()`, `ext_unload()`, `gptr_reload()`,
`check_in_scratch()` and `check_factory()`.

**Built.**

- P06 `session_finalizer()` now does only what is safe at any allocation. It removes the shell's
  `the$live` entry, releases the file lock (now inside `tryCatch()`) and queues the
  notification with `ev_defer()`. The lock release and the live-index removal stay immediate,
  as architecture 5.1 says; the reasons are in D-085 item 1.
- P02 `ev_defer(event, payload, session)` adds one uniquely keyed binding (`d<seq>`) to the
  registry's new `deferred` environment. A key already taken (a finalizer that ran inside
  another `ev_defer()` call) moves to the next number. `ev_drain(reg, force = FALSE, session = NULL)` dispatches
  the queued events oldest first: each item is removed before its dispatch, and a failing
  dispatch becomes a diagnostic.
- Reentrancy and "never inside an iteration": `registry_enter(reg, drain = TRUE)` and
  `registry_leave(reg)` count registry work in `reg$busy`. A drain runs only when no work is in
  progress and no drain is running (`reg$draining`). An event deferred during a drain is taken by
  the same drain afterwards, never dispatched nested. Registry work is `ev_dispatch()`,
  `registry_get()`, `registry_all()`, `registry_names()`, `gptr_registry()`, `ext_load()`,
  `ext_activate()`, `ext_unload()`, `gptr_reload()` and `registry_session_drop()`, each of which
  drains first. `ext_run_factory()` also counts as work, but does not drain. A lookup made by a
  hook, by a factory or by P03's redaction (through `registry_diagnostic()`) therefore never
  drains under its caller.
- Other safe points are `session_new()` (start) and `session_attach()` (after its `gc()`
  re-check). `live_new()` calls `ev_drain(session = id)` before it registers a shell under an id,
  even under registry work. A collected shell with the same id (a resumed or attached session)
  thus has its shutdown dispatched before the new shell exists, and that shutdown never drops
  the new shell's records.
- `live_unload()` drains (forced) before and after the live sessions' `unload` shutdowns. At
  process exit, `live_exit()` (an exit finalizer on `the$live`, registered in P06's `on_load()`)
  drains (forced). R runs exit finalizers newest first, so it runs after every session's own exit
  finalizer has queued.
- Hardened loops: `registry_recs()` uses `mget(ifnotfound = list(NULL))` and drops missing
  ids, returning an unnamed list as before. `registry_session_drop()`, `ext_unload()`,
  `gptr_reload()`, `check_in_scratch()` (records and kinds) and `check_factory()` use `get0()`
  and skip a missing entry. `ext_activate()` and `live_all()` already did.
- State: no new field of `the`. The queue and counters are fields of the P02 registry env
  (`deferred`, `deferred_seq`, `busy`, `draining`), created by `registry_new()`.

**Tests** (written first).

`tests/testthat/test-ext-registry.R` (+2 tests, 13 expectations):

- "registry_recs() skips ids whose record is gone (FIX-1)".
- "a deferred session_shutdown waits for the next registry entry (FIX-1)": no drain under a
  dispatch, the drain happens at the next entry, and an event deferred during a drain is taken
  by the same drain, not nested.

`tests/testthat/test-session-live.R` (+7 tests, 42 expectations after review round 1; helpers
`fix1_cmd()` and `fix1_registry()`):

1. the deterministic race: a `gc()` inside `registry_session_drop()`'s loop, through a mocked
   `registry_remove()`, finalises a session with rank-0 records;
2. the same inside `ext_unload()`'s extensions loop, through a mocked `ext_forget()`;
3. a session collected inside a `turn_end` handler. Its `session_shutdown` (reason `gc`) runs at
   the next registry entry, after the handler, and its own listener still sees its records. The
   records are dropped afterwards, while the lock is already released and the live entry is
   already gone;
4. reentrancy: a `session_shutdown` hook that creates, registers and drops sessions and calls
   `gc()` while the queue drains. Three shutdowns are dispatched in sequence, nesting depth 1;
5. id reuse: a new shell created under a collected shell's id inside registry work gets the old
   shutdown first and keeps its own records;
6. unload: queued `gc` shutdowns run before the live sessions' `unload` ones, and the live lock is
   released;
7. process exit (a child `Rscript` through `tracemem_loader()`). Nothing is dispatched inside
   `gc()`, and both shutdowns (the collected session first) run at exit.

**Red** (`task1-red.log`, `^(session-live|ext-registry)$`, before any source change, without
test 5, which was added later): `[ FAIL 21 | WARN 0 | SKIP 0 | PASS 221 ]`. The failures are
the expected ones:

- "object 'r3' not found" in `registry_session_drop()` and "object 'e2' not found" in
  `ext_unload()`, which reproduce the race;
- "object 'r2' not found" in `registry_recs()`;
- shutdowns dispatched inside `gc()`: orders `own:gc, turn_end`, a non-empty log after `gc()`,
  and "GPTR-AFTER-GC TRUE" in the child;
- the missing `ev_defer()`, `reg$deferred` and `ev_drain()`.

Errors stopped three tests before their last expectations, which is why the red total is lower.

**Sabotage checks** (each source change reverted alone, then restored):

- without `live_new()`'s targeted drain, test 5 fails 3 expectations: the new shell's record is
  dropped and the old shutdown arrives after it (`task1-sabotage-targeted.log`, `[ FAIL 3 | WARN
  0 | SKIP 0 | PASS 72 ]`);
- without the exit finalizer, test 7 fails: no shutdown is written at exit
  (`task1-sabotage-exit.log`, `[ FAIL 1 | WARN 1 | SKIP 0 | PASS 74 ]`; the test now reads a
  missing file as empty).

**Green.**

- `^(session-live|ext-registry)$` (`task1-green.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 250 ]`.
  That is 198 existing expectations, unchanged, plus 52 new. The test "an unreferenced session
  is finalised and its lock removed" passes unchanged. With `ext-events` added, on the final code
  (`task1-green-final.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 446 ]`.
- Neighbours, `^(ext-|session-|agent-|aaa-state$|zzz$)` (`task1-green-broad-final.log`):
  `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 3657 ]`. The one failure is the known `test-zzz.R:301`
  ("every gptr:: call ... names an export": `gptr_return`, `gptr`; P08/P15, recorded in
  `progress/P02.md` and `progress/P07.md`), which this change does not touch. An earlier run of
  the same filter, before the last small edits, gave the same result (`task1-green-broad.log`).
- `^(arch-layers|lint-rules)$` (`task1-arch-lint-rules.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 18 ]`.
  P06 (L3) calls P02 (L0) only.
- P07, read-only check, `^prompt-` (`task1-prompt.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 745 ]`.
  Its `gc()` workarounds (`test-prompt-sections.R`, `test-prompt-cache.R`,
  `test-prompt-compact.R`) are no longer needed but are left to the P07 lane.

**Lint** (`task1-lint.log`): no lints in the 8 touched R and test files.

**Cost.** `registry_enter()` plus `registry_leave()` take about 3 microseconds per call. A hookless
`ev_dispatch()` takes about 14 microseconds (20,000 calls). `registry_enter()` checks the queue
length before it calls `ev_drain()`.

**Adaptations.**

- The coordinator's preferred design deferred the lock release too. It stays in the finalizer,
  as architecture 5.1 and P06's existing test have it (D-085 item 1).
- No reactor-pump drain: P04's `R/http-reactor.R` is not touched. A collected session's shutdown
  is dispatched at the next gptr call that reaches a safe point.
- The plan's tests of a direct `ev_dispatch("session_shutdown", ...)` are unchanged; that path
  still drops records at once.

No `NAMESPACE` or `man/` change: every new function is `@noRd` and internal.

**Review round 1** (verdict clear; one minor finding, fixed; logs `review1-*.log`).

- Finding (minor, tests only): tests 1, 2, 3 and 5 dropped the last reference with `rm(a)` and
  then allocated (an expectation, a `with_mocked_bindings()` setup, `ev_dispatch()`'s prologue)
  before the controlled `gc()`. A natural collection in that window finalised `a` early while no
  registry work ran, and the next entry (`registry_session_drop()`, `ext_unload()`,
  `ev_dispatch()`) drained its shutdown before the scenario started. The reviewer measured 7 early
  finalisations in 600 iterations of test 1's window. Verified: it is real, and the code under
  test is correct (contract 7.2 and D-085: a shutdown queued while no registry work runs is
  dispatched at the next entry).
- Fix: those four tests keep the session only in `hold = new.env(); hold$a = test_session()` and
  release it with `hold$a = NULL` immediately before the controlled `gc()`, inside the mocked
  `registry_remove()` / `ext_forget()` (tests 1, 2) or inside the `turn_end` hook (tests 3, 5).
  The early `rm(a)` is gone. Each window now has an explicit `invisible(gc())`, so a regression
  to the early release fails every run instead of rarely; tests 1, 2 and 5 also check
  `session_by_id(id_a)` after it (+3 expectations). Tests 4, 6 and 7 call `rm()` directly before
  `gc()` with no entry point in between and are unchanged. The section's header comment states
  the pattern. No source change.
- Regression red (`fixer1-red.log`): the pre-fix test file with an `invisible(gc())` injected
  right after each `rm(a)` (a stand-in for the natural collection), run through a scratch copy of
  the isolated runner (`testthat::test_dir()` over a mirrored test directory):
  `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 67 ]`, exactly the reviewer's failure modes: `ls(reg$recs)`
  empty instead of `r3 r4`, `ls(reg$exts)` empty instead of `e2`, the lock already released and
  the order `own:gc, turn_end` in test 3, and `shutdown:gc, collected, new shell` in test 5. The
  same harness on the unmodified file gives `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 75 ]`
  (`fixer1-harness-base.log`), matching the real runner.
- Regression green: the fixed file through the same harness with ten more collections injected
  across the windows (`fixer1-green-injected.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 78 ]`. A
  600-iteration loop of test 1's window (`fixer1-stress.log`) found no early finalisation with
  the holder (none with `rm(a)` in that run either; the natural rate depends on heap state, which
  is why the committed tests force the collection).
- Final green on the real runner: `^(session-live|ext-registry)$` (`fixer1-green.log`)
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 253 ]`; `^(session-live|ext-registry|ext-events)$`
  (`fixer1-green-final.log`) `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 449 ]`; `^session-live$` three
  more times (`fixer1-repeat-{1,2,3}.log`), each `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 78 ]`;
  `^(ext-|session-|agent-|aaa-state$|zzz$)` (`fixer1-green-broad.log`)
  `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 3722 ]`. The one failure is the known `test-zzz.R:301`
  (`gptr_return`, `gptr`), already failing at HEAD. This round adds 3 expectations; the rest of
  the rise from 3657 comes from the concurrent P17 lane's uncommitted `test-ext-plugins.R`.
- Lint (`fixer1-lint.log`): no lints in `tests/testthat/test-session-live.R`, the only file this
  round touched.

Commit message: `fix(session): defer GC-time session shutdown out of registry iteration`.

Files of this task:

- `R/ext-registry.R`
- `R/ext-events.R`
- `R/ext-load.R`
- `R/ext-check.R`
- `R/session-live.R`
- `R/session-object.R`
- `tests/testthat/test-ext-registry.R`
- `tests/testthat/test-session-live.R`
- `dev/DEVIATIONS.md` (the D-085 hunk only)
- `dev/progress/fixes.md`
- `dev/progress/P02.md` (cross-reference line)
- `dev/progress/P06.md` (cross-reference line)

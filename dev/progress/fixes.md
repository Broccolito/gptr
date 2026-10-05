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

## Task FIX-2 - Build gptr:: calls without quote() in the document scanner

Owner: P15 (`R/doc-blocks.R`, Tasks 2-3 recorded-code cleaning). Coordinator-scheduled. No
deviation entry: the behaviour is unchanged.

**Defect.** `doc_drop_expr()` (P15's recorded-code cleaner, IC-48) compared expression heads
with `quote(gptr::gptr_return)` and `quote(gptr::gptr)`, as the plan literal has it (P15 plan
line 1401 and 1406). R CMD check's "checking dependencies in R code" reads every literal
`gptr::name` in package code, quoted or not, as a use of an export. While P08's `gptr()` and
`gptr_return()` are not exported, it warns "Missing or unexported objects: 'gptr::gptr'
'gptr::gptr_return'". That WARNING fails every hosted check job (`error-on: "warning"`), and
the P01-level test `test-zzz.R:301` ("every gptr:: call in the package code names an export of
NAMESPACE") failed. CI Task CI-4 fixed the same pattern in `R/eval-guard.R`.

**Built.** `doc_drop_expr()` now builds the two heads with P09's `eval_guard_ns_call()`
(`call("::", as.symbol("gptr"), as.symbol(name))`). The built call is `identical()` to the
quoted one, so what is dropped does not change. The layering rules allow the call:
`R/doc-blocks.R` is L4 and `R/eval-guard.R` is a declared "L4 svc" file
(`tests/testthat/helper-arch.R`, `arch_edge_ok()`); `^arch-layers$` is green. The function's
roxygen note gives the reason.

**Test** (written first; `tests/testthat/test-doc-blocks.R`, +1 test, 13 expectations): "the
scanner builds gptr::gptr and gptr::gptr_return without a literal gptr:: (FIX-2)":

- `eval_guard_ns_call("gptr_return")` and `eval_guard_ns_call("gptr")` are `identical()` to
  `quote(gptr::gptr_return)` and `quote(gptr::gptr)`;
- a local walker of function formals and bodies (the shape R CMD check reads) finds no
  `gptr::` reference in `doc_drop_expr`, with a negative control on a quoted call;
- behaviour: `gptr::gptr_return(x)`, `gptr_return(x)`, `gptr::gptr$out(...)` and
  `gptr::gptr[["out"]](...)` are dropped; `gptr::gptr$grep(...)`, `gptr::gptr("task")`,
  `other::gptr_return(x)` and `other::gptr$out(...)` are kept; `doc_code_clean()` drops
  `gptr::gptr$out("o1a2b3")` from `gptr::gptr$out("o1a2b3"); y = 1` and keeps `y = 1`.

**Red** (`task2-red.log`, `^(doc-blocks|zzz|eval-guard)$`, before the source change):
`[ FAIL 2 | WARN 0 | SKIP 0 | PASS 478 ]`. The failures are the expected ones:
`test-doc-blocks.R:514` (the walker finds `"gptr_return" "gptr"` in `doc_drop_expr`) and
`test-zzz.R:301` (`"gptr_return" "gptr"` not exported).

**R CMD check's own check** (`task2-check-deps.log`): `tools:::.check_packages_used()` on two
temporary installs of a `git archive HEAD` export (R, DESCRIPTION, NAMESPACE, inst; scratch
libraries, removed afterwards). HEAD as committed gives "Missing or unexported objects:
'gptr::gptr' 'gptr::gptr_return'"; the same export with this task's `R/doc-blocks.R` gives
nothing. The same function run on the source directory reports nothing on either version
(`task2-packages-used.log`), so only the installed-package runs count as evidence.

**Green.**

- `^(doc-blocks|zzz|eval-guard)$` (`task2-green.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 480 ]`
  (478 + the 2 expectations that failed).
- Neighbours, `^(doc-|arch-layers$|lint-rules$|eval-|env-history$)` (`task2-neighbours.log`):
  `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 1046 ]`. The skip is P09 Task 8's known guard
  (`test-eval-core.R:413`, "P08's gptr_return() is not implemented yet", D-054).
- No other R file calls `doc_drop_expr()` or `doc_code_clean()`.

**Lint** (`task2-lint.log`): no lints in `R/doc-blocks.R` and `tests/testthat/test-doc-blocks.R`.
Both stay ASCII-only. No roxygen export changed, so `document` was not run; no `NAMESPACE` or
`man/` change.

**Adaptations.** The plan literal (`quote(gptr::...)`) is replaced by the helper call, as CI-4
did for P09. The coordinator's alternative, an inline `as.call(list(...))`, was not needed
because the helper is reachable under the layer rules. Once P08 exports `gptr()` and
`gptr_return()`, a literal would pass R CMD check again; the helper stays correct either way.

Commit message: `fix(doc): build gptr:: calls without quote() so R CMD check sees no missing export`.

Files of this task:

- `R/doc-blocks.R`
- `tests/testthat/test-doc-blocks.R`
- `dev/progress/fixes.md`
- `dev/progress/P15.md` (cross-reference line)

## Task FIX-3 - rebuild_frozen() keeps human and reinject

Owner: P06 (`R/session-store.R`, Task 13 rebuild; also the replay cut of Task 12's
`replay_rebuild()` in `R/session-object.R`, which calls the same function). Coordinator-scheduled.
Closes the open item of D-069; no new deviation entry (the extra keys are D-069's own).

**Defect** (`progress/P07.md`, Task 7 review item 3; D-069 "Open for P06"). P07 writes two extra
keys in `gptr.frozen`: `human`, the audience the prompt was frozen for, and `reinject`, the
re-injection budgets when IC-71's floor check cut them (finite, non-negative `project` and
`skills`; full budgets are not written). P07's `prompt_frozen_restore()` reads both back.
P06's `rebuild_frozen()` copied neither. It is the restore of `store_rebuild()` (every
`gptr_resume()` of a file) and of a replay's cut. A resumed session therefore had no
`.d$frozen$human`, so P07's consumers fell back to `gptr_can_prompt()` (mode block, `ask`
schema, IC-52 withholding). It had no `.d$frozen$reinject` either, so the compactor re-injected
the full budgets instead of the recorded cut. A fork of a resumed session inherits the
source's `.d$frozen` (`fork_frozen()`), and so did the fork.

**Built.** `rebuild_frozen()` now returns the same frozen list as `prompt_frozen_restore()`. It
has the same ten fields in the same order: the seven it had, plus `human = x$human %||%
gptr_can_prompt()`, `document = NULL` and `reinject = prompt_reinject_read(x$reinject) %||%
list(project = Inf, skills = 10000)`. The cut is read with P07's own reader, so the rule (two
finite, non-negative numbers; JSON integers become doubles) has one home. The call from
`session-store.R` (L3) to `prompt-sections.R` (L3) is within one layer (architecture 2.2, L3 =
`session`, `agent-run`, `prompt`); `^arch-layers$` is green. The roxygen block lists the
fields and their fallbacks. No P07 file was touched.

**Tests** (written first; +4 tests, 20 expectations).

`tests/testthat/test-session-store.R`:

1. "a resumed session and its forks keep the frozen audience and budget cut (FIX-3)" (8). A real
   first run freezes through P07's `prompt_freeze()` with the run option `interactive = TRUE`
   (`gptr_can_prompt()` is FALSE in the tests). P07's `prompt_floor_check()` is stubbed to make
   the IC-71 cut (1904/0); the arithmetic is P07's and tested there. Preconditions: the
   `gptr.frozen` entry and `.d$frozen` hold `human = TRUE` and the cut. Then the session is
   resumed from its file, and its frozen list must be `identical()` to
   `prompt_frozen_restore()`. A fork of the resumed session shares it, runs one turn, and is
   resumed from its own file: both keys are kept. The stub is a top-level function, so it keeps
   no test frame, and no session, alive (the FIX-1 pattern).
2. "a session frozen for nobody resumes frozen for nobody, with full budgets (FIX-3)" (3). A
   default run records `human = FALSE` and no `reinject`. It is resumed under a mocked
   `gptr_can_prompt()` that returns TRUE, and keeps `human = FALSE` with the full budgets: the
   recorded audience decides, not the console.
3. "rebuild_frozen() falls back as P07's restore does when a key is missing (FIX-3)" (7). With
   no `human`, the value is the console's (TRUE and FALSE mocked); `document` is NULL. A
   malformed `reinject` (negative, one field, a string, NA) gives the full budgets. Integer
   JSON numbers come back as doubles.

`tests/testthat/test-session-object.R`:

4. "a replay cut takes the frozen audience and budget cut of its own path (FIX-3)" (2). Turn 1
   runs under an entry with `human = TRUE` and a cut; turn 2 is refrozen for nobody. A replay
   of turn 1 takes T0, `human` and `reinject` from the turn-1 entry (`replay_rebuild()`).

**Red** (HEAD's `R/session-store.R`, `^session-(store|object)$`):

- Before test 3 was added (`task3-red.log`): `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 706 ]`.
- With all four tests (`task3-red2.log`; HEAD's file put back for the run, then the fix
  restored): `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 706 ]`.

The failures are exactly the missing fields. `human` and `reinject` are absent (NULL) after a
resume (store lines 972, 985, 1005) and after the replay cut (object line 1177). Against
`prompt_frozen_restore()` the length is 7 instead of 10 (line 973). Test 3 fails all 7 of its
expectations. Every precondition passes on HEAD: the entry, `.d$frozen`, the fork sharing the
source's list, and the fork's answer.

**Green.**

- `^session-(store|object)$` (`task3-green.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 718 ]`.
  That is 698 existing expectations plus 20 new; no existing expectation changed.
- `^(session-|agent-run$)` (`task3-session-agent.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1642 ]`.
  `^session-store$` once more (`task3-repeat.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 252 ]`.
- Neighbours. These were run before test 3 was added; test 3 is a pure unit test of
  `rebuild_frozen()`.
  - `^(arch-layers|lint-rules)$` (`task3-arch-lint-rules.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 18 ]`.
  - `^(doc-|ckpt-|agent-|ext-registry$|ext-events$)` (`task3-neighbours.log`):
    `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1815 ]`.
  - P07, read-only check, `^prompt-` (`task3-prompt.log`, on the P07 lane's working tree):
    `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 894 ]`.

**Lint** (`task3-lint.log`): no lints in `R/session-store.R`,
`tests/testthat/test-session-store.R` and `tests/testthat/test-session-object.R`. Added lines
are ASCII-only. All functions are internal (`@noRd`), so `document` was not run; no `NAMESPACE`
or `man/` change.

**Adaptations.**

- The coordinator offered calling `prompt_frozen_restore()`. It takes a session and reads the
  session's active path, while `rebuild_frozen()` takes a path (the replay cut passes a cut
  path). So the function keeps its signature, reads the two keys with P07's rule, and the test
  asserts equality with `prompt_frozen_restore()`. The 10,000-token skills default is P07's
  constant, repeated as P07's restore and compactor repeat it.
- `document = NULL` is included only so that the list matches P07's restore in shape;
  `.d$frozen$document` was NULL before as well.
- Not in scope: P07 review item 2 (`progress/P07.md`, a fork of a foreign-resumed session before
  its first run restores the foreign prompt). That is a separate P06 follow-up.

Commit message: `fix(session): keep human and reinject when rebuilding the frozen prompt`.

Files of this task:

- `R/session-store.R`
- `tests/testthat/test-session-store.R`
- `tests/testthat/test-session-object.R`
- `dev/DEVIATIONS.md` (the D-069 hunk only: the open item is closed)
- `dev/progress/fixes.md`
- `dev/progress/P06.md` (cross-reference line)

## Task FIX-4 - Make secret_late_check() tolerate NA in live entries

Owner: P03 (`R/auth-secrets.R`, the IC-70 late-registration check of Task 1). Found by P12's
plan acceptance (`progress/P12.md`, "Cross-plan defect found, not fixed here"; reproduction
`dev/.validation/P12/p12-diag-na.R`, `acceptance-diag-*.log`). Coordinator-scheduled. No new
deviation entry: the only behavioural change is that unknown (NA) and non-text leaves of live
entries are not scanned, which is what the coordinator's notes ask for.

**Defect.** `secret_late_check()` scanned `unlist(live[[id]])` of every live session's entries.
IC-74 (07 section 5, "Missing usage remains unknown") makes NA normal in those entries: the
usage and cost of an unpriced model, or of an aborted or truncated stream (D-022). `unlist()`
coerced the NA cost to `NA_character_`, `gregexpr()` returned NA for it, the count became NA and
`if (n > 0L) counts[[id]] = n` failed with "missing value where TRUE/FALSE needed". After P12's
INFRA-25 run tests `gptr_last()` holds such a session (scripted provider, no price), so every
`secret_register()` of a value of redactable length threw, including P05's
`provider_credential()` registering an environment key: 9 tests of `test-provider-registry.R`
failed in every run where they follow P12's tests (`devtools::test()`, R CMD check, CI). A
second gap of the same scan: a non-atomic leaf (a function, an environment) made `unlist()`
return a list, so `!is.character(txt)` skipped the whole session and a genuine leak next to it
went uncounted (scratch probe `taskFIX-4-probe-old-scan.log`).

**Built.** A new internal `secret_known_strings(x)` returns the known strings of a nested list:
every character leaf at any depth (classed character vectors included, class dropped), NA
removed; it recurses into lists (data frames and classed lists through `unclass()`, so no
`as.list()` dispatch) and ignores every other leaf (numbers, flags, functions, environments).
`secret_late_check()` scans that instead of `unlist()`, skips a session with no known string,
and records a count with `if (isTRUE(n > 0L))`. Matching itself is unchanged (every derived form,
fixed, bytewise), so detection in text is as before. Scanning character leaves alone matches
`redact_tree()`, which also treats only character leaves as text (a value held as a number is
not text the redactor would replace either). Cost: on 5,000 typical
message entries the walk takes about 0.13 s against 0.02 s for `unlist()`, next to about 0.46 s
for the unchanged matching of five derived forms (scratch benchmark, not kept). `rapply()` was
measured faster but drops classed character leaves and fails on pairlists, so the plain
recursive walk was kept.

**Audit** of `R/auth-secrets.R` and `R/auth-redact.R` for the same NA-unsafe `if` over scanned
entry fields: no other instance. `redact()` blanks NA before matching and restores it;
`redact_tree()` collects string leaves, compares with an explicit NA rule and its
`structural_blank()` tests `is.na(v)`; `lits_present()` uses `grepl()`, which gives FALSE for
NA; the `gptr_scrub()` scanners read file text (never NA) and test `is.na()` on decoded record
fields; `secret_discover_env()` already guards with `%in% TRUE`. Confirmed by a scratch probe
with NA usage, cost, text, flags and an NA name through `redact_tree()` (plain and structural),
`redact()`, `gptr_redact()`, `lits_present()` and `structural_blank()`
(`taskFIX-4-audit-probe.log`, isolated HOME).

**Test** (written first; `tests/testthat/test-auth-secrets.R`, +1 test, 6 expectations):
"unknown NA fields of live entries are ignored and a late leak is still counted". Four fake
live sessions: an aborted assistant message whose usage holds `NA_integer_` tokens, an
`NA_real_` cost list (input, output, cache_read, cache_write, total), an NA `estimated` flag,
`NA_character_` response id, error message and text block, plus one text block with the value;
a session with only an unknown-usage message; a custom entry whose data holds a function and an
environment next to a note with the value; a custom entry with `data = NA`. Registering the
value warns `secret_late` with `counts == c(sNA0000001 = 1L, sNA0000003 = 1L)` and no value in
the message; a value no session holds registers without warning; a callback serving only
unknown and empty sessions neither warns nor errors.

**Red** (HEAD's `R/auth-secrets.R`):
- `^auth-secrets$` (`taskFIX-4-red.log`): `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 296 ]`, the new test
  erroring at its `expect_warning()` (line 187) with "missing value where TRUE/FALSE needed" from
  `if (n > 0L) counts[[id]] = n` (`R/auth-secrets.R:389`), the defect itself.
- Cross-file `^(provider-anthropic|provider-registry)$` (`taskFIX-4-red-cross.log`):
  `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 992 ]`, the 9 P12 found (`test-provider-registry.R` lines
  166, 191, 217, 242, 281, 295, 315, 333, 2182), same error.

**Green.**
- `^auth-secrets$` (`taskFIX-4-green.log`): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 302 ]` (296 + 6).
- `^(provider-anthropic|provider-registry)$` (`taskFIX-4-green-cross.log`):
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1032 ]` (992 + the 40 expectations of the 9 tests).
- `^auth-` (`taskFIX-4-auth.log`): `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 1068 ]`; the skip is
  `test-auth-store.R:75` ("keyring is installed").
- Neighbours `^(session-live|arch-layers|lint-rules)$` (`taskFIX-4-neighbours.log`; P06 installs
  the callback): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 96 ]`.
- Full unfiltered suite once (runner filter `.`, `taskFIX-4-full.log`):
  `[ FAIL 3 | WARN 0 | SKIP 6 | PASS 16358 ]`. No failure in `test-provider-registry.R`. The 3
  failures are `test-perm-classify.R:817`, `:1038` and `:1213` ("`!nq`: invalid argument type"
  inside `risk_cmd_walk()`), in P11's uncommitted in-progress `R/perm-classify.R`, not touched
  here. The 6 skips: keyring installed, D-054 (`eval-core`), P08 Task 7 (`gptr-config`), the
  three live files without `GPTR_LIVE_TESTS=true`.

**Lint** (`taskFIX-4-lint.log`): no lints in `R/auth-secrets.R` and
`tests/testthat/test-auth-secrets.R`. Added lines are ASCII-only. The new function is `@noRd`,
so `document` was not run; no `NAMESPACE` or `man/` change.

**Adaptations.**
- The coordinator's suggested `txt = txt[!is.na(txt)]` alone would have left the non-text-leaf
  gap (a session skipped whole); the walk over character leaves closes both, as the notes'
  "skip NA values (and non-character leaves)" asks.
- The regression entries are built as literal R-shape lists (04 sections 4.3, 4.6) rather than
  with P05's constructors, so the L0 test file stays free of upper-layer dependencies; the
  cross-file filter exercises the real structure P06's `live_entries_all()` serves.

Commit message: `fix(auth): late secret check ignores unknown NA fields of live entries`.

Files of this task:

- `R/auth-secrets.R`
- `tests/testthat/test-auth-secrets.R`
- `dev/progress/fixes.md`
- `dev/progress/P03.md` (cross-reference section)
- `dev/progress/P12.md` (cross-reference section)

## Task FIX-5 (P15 part) - doc_format_of() reads extensions with path_ext()

Owner: P15 (`R/doc-io.R`). Done inside P15 Task 13 at the coordinator's request (the P15 lane
released the file); the other two call sites of HANDOFF's FIX-5 item, `R/ext-specs.R` (P02/P17)
and `R/gptr-gateway.R` (P08), are not touched here and stay open. Deviation: D-122 item 7
(D-111 item 1 gives the rule).

**Defect.** `doc_format_of()` called `tolower(tools::file_ext(path[1L]))`. R >= 4.6's
`tools::file_ext()` tests the extension on `basename(x)`, which stops on a marked UTF-8 non-ASCII
path in a non-UTF-8 locale ("unable to translate 'caf<U+00E9>.R' to native encoding"). Every
caller (the locator, the writer, transcript targets, inert blocks) failed for such a document.

**Built.** `doc_format_of()` reads the extension with P01's `path_ext()` (R 4.6's rule without
`basename()`, every locale and every R). No other line of `R/doc-io.R` changed.

**Test** (written first; `tests/testthat/test-doc-io.R`, +1 test, 9 expectations): "a non-ASCII
document name has its format in any locale (R >= 4.6)" runs under `local_name_locale()` (C locale
on macOS and Linux) and `local_r46_file_ext()` (R 4.6.1's `tools` bodies on any R): `.R`, `.Rmd`
under a non-ASCII directory, upper-case `.QMD`, `.ipynb`; `.txt`, no extension, `".R"` (no
extension under R 4.6's rule), `NULL` and `NA` give `NULL`. All literals are `\u` escapes.

**Red** (`R/doc-io.R` of `HEAD`): `^doc-io$` `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 352 ]`, the new
test erroring with "unable to translate 'caf<U+00E9>.R' to native encoding" in `basename(x)`
(`dev/.validation/P15/task13-fix5-red.log`).

**Green**: `^doc-io$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 361 ]` (`task13-fix5-green.log`); in
`^doc-(formats|replay|io)$` with Task 13, `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 903 ]` in the default
and the C locale (`task13-green.log`, `task13-green-clocale.log`). Lint of `R/doc-io.R` and
`tests/testthat/test-doc-io.R`: no lints (`task13-lint.log`).

To be committed with P15 Task 13 (`feat(doc): register builtin:documents with the document
route, section, hooks and services`).

## Task FIX-6 - Conformance coverage for classifier adapters (IC-74 P12 row)

Owners: P12 (`R/provider-anthropic.R`, `check_adapter()`; its test file) and P13 (`R/s1-client.R`,
`R/s1-types.R`; the canonical-answer validator). Coordinator-scheduled; closes P12's open IC-74
item (07-local-ollama.md section 6, P12 row: "classifier adapters receive conformance coverage";
`progress/P12.md` plan acceptance, open item 1; D-026's open point). Deviation: D-026, closing
section (items 1-5).

**Choice: `check_adapter()`, not `gptr_check()`.** Contract 6.7 sends every adapter spec through
`check_adapter()`, the `check.adapter` service of 7.12, so the classifier branch is there and
`gptr_check()` (P02, unchanged) gets it through the service. `ext-check.R` is L0 and could not call
the s1 area anyway.

**Built.**
- `R/provider-anthropic.R` (P12):
  - an adapter with `classify` goes to the new `adp_check_classifier()` instead of the stream
    suite. It replays each `fixtures/classifier/<api>/<case>.json` (or `fixtures`) once through
    `classify$parse(model, status, headers, body, questions)`, or `classify$run(model, state,
    questions, opts)` for an inprocess classifier;
  - rows per case: `.no_condition`, `.result` (04 section 8.1 shapes), `.canonical`
    (`s1_check_answers()` returns the answers unchanged), then `.golden_answers`
    (order-sensitive, against `<case>.answers.json`) or `.typed_error` (class and status from
    `<case>.error.json`); an unreadable case file gives `.fixture`;
  - no cases: `adapter.fixtures` fails for a wire classifier; an inprocess classifier without a
    fixture directory keeps `adapter.replay` ("nothing to replay");
  - helpers `adp_classifier_case()`, `adp_check_classify()` (exiting error, warning and message
    handlers, as `adp_check_replay()`), `adp_classifier_result_ok()`, `adp_check_canonical()`,
    `adp_answers_json()`, `adp_classifier_golden()`;
  - `adp_fixture_model()` gains `type = "chat"`, and `adp_fixture_dir()` gains `kind = "sse"`.
    Existing callers are unchanged.
- `R/s1-types.R` / `R/s1-client.R` (P13): the canonical-record validator and its primitives moved
  unchanged to the end of `s1-types.R` (L1). They are `s1_types`, `s1_round_tol`,
  `s1_condition()`, `s1_num()`, `s1_unit()`, `s1_option_keys()`, `s1_answer_probs()`,
  `s1_parse_choice()`, `s1_parse_score()`, `s1_check_answers()`, `s1_check_answer()` and
  `s1_check_probs()`. Only header comments changed besides. A parse-tree comparison of the two
  files before and after: 119 definitions, all deparse identically
  (`task6-move-check.log`).
- Fixtures: `tests/testthat/fixtures/classifier/typesafe-system-one/` (18 cases) and
  `.../ollama-system-one/` (13 cases), each with `model.json` and one golden per case:
  - the Jev bodies come from P13's recorded `fixtures/jev/`; the Ollama bodies from P13's
    synthetic `fixtures/ollama/`;
  - success cases cover all three answer types, multi-question answers in another order than
    the questions, shuffled probability keys, computed values (TypeSafe's confidence formulas;
    Ollama's entropy confidence, golden digits computed independently in R), an unavailable
    (gateway) probability map and ignored extra fields;
  - error cases cover error bodies by status (400, 401, 404, 429, 500, 502), a malformed body,
    missing answers, a wrong answer type, an unknown option, a bad sum, a missing answer, another
    model and a confidence that the probabilities do not give.

**Adaptations.**
1. **Layering.** `provider-anthropic.R` is L1 and `s1-client.R` is L4. The negative control (scratch
   copy, validator left in `s1-client.R`): `^arch-layers$` `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 12 ]`,
   "adp_check_canonical (provider-anthropic.R) -> s1_check_answers (s1-client.R)"
   (`task6-negative-layers.log`). So the validator moved to L1, rather than adding a service
   that contract 7.0's complete list (39) does not have.
2. **Plan Task 3 test changed** (`test-provider-anthropic.R`, "check_adapter() reports missing
   fixtures, skips inprocess adapters, asks classifiers"). The `classify`-only `http_json`
   adapter without fixtures now gives `adapter.fixtures` = FALSE (and `gptr_check()` rows
   `spec.class`, `spec.fields`, `adapter.fixtures` = TRUE, TRUE, FALSE). It used to give
   `adapter.replay` = TRUE. IC-74 overrides the plan literal; this is a stronger check.
3. **Fake classifier.** P01's fake is exercised through the registered `fake-classifier`
   adapter with a temporary fixture directory. Its `model.json` names the provider of a live
   `gptr_fake_provider(type = "classifier")`, which `fake_engine()` finds by name. No default
   `fixtures/classifier/fake-classifier/` exists, because it would need a script.

**Tests** (written first; `tests/testthat/test-provider-anthropic.R`): the adapted test above,
plus five new tests:
- "check_adapter() replays classifier wire fixtures through classify$parse (IC-74)": both
  built-in adapters; every row passes, and each case has exactly its rows.
- "gptr_check() runs the classifier conformance of the built-in classifier adapters": through
  the service, from the default directory.
- "check_adapter() fails classifier parsers that keep a wire shape or order, or signal":
  - the wire answers handed on;
  - the question order lost;
  - probabilities in wire order;
  - a parser that throws, warns, signals a message or signals its typed error (nothing reaches
    the caller);
  - untyped errors and a missing `model_version`.
- "a classifier golden or fixture that differs fails only its own case".
- "inprocess classifiers: P01's fake classifier answers fixture states canonically": golden
  answers and a typed 429, one `run()` per case, a non-canonical `run()`, `s1-emulate` and the
  fake without fixtures, and an empty fixture directory.

**Red** (tests on the previous `check_adapter()`): `^provider-anthropic$`
`[ FAIL 86 | WARN 0 | SKIP 0 | PASS 341 ]`, all failures and no errors (`task6-red.log`). Each
failure is a missing classifier row: the old code gave `adapter.replay` for every classifier.

**Green**: `^provider-anthropic$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 427 ]`, first run and final
(`task6-green1.log`, `task6-green.log`), and the same under `LC_ALL=C` (`task6-green-lc-c.log`).
P12 acceptance's count was 307. The 120 more are the five new tests and the adapted test (3
assertions became 5). No golden needed a correction.

**Neighbours.**
- `^(s1-(types|client|cache|emulate|ollama|route)|provider-(anthropic|openai-responses|openai-completions|google|fake|registry)|ext-check|aaa-state|copy-s1|live-ollama-s1|live-jev)$`:
  `[ FAIL 0 | WARN 0 | SKIP 4 | PASS 3908 ]` (`task6-neighbours.log`; the skips are the four
  live tests, `GPTR_LIVE_TESTS` false).
- `^(arch-layers|lint-rules)$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 18 ]` (`task6-arch.log`).

**Lint.** No lints in `R/provider-anthropic.R`, `R/s1-types.R`, `R/s1-client.R` or
`tests/testthat/test-provider-anthropic.R` (`task6-lint.log`). The R sources and fixtures are
ASCII, and no R line exceeds 100 characters.

**Document.** All touched roxygen is `@noRd`. On a scratch copy, the `document` action changed no
`man/` or `NAMESPACE` entry of this task (`task6-document-scratch.log`): the only additions are
P15's committed `gptr_blocks`, `gptr_cache` and `gptr_doc` exports. Its six "Could not resolve
link" notes for `s1-types.R` ("[0, 1]" in titles) are the ones the moved roxygen already gave in
`s1-client.R` (P12 acceptance counted them). The real tree's `NAMESPACE`/`man/` were not touched.

**Review round 1** (verdict clear, two minor findings; both real, both fixed test-first).
1. *s1-emulate's calibration notice failed conformance.* IC-19 makes s1-emulate's `classify$run`
   give a `gptr_message_notice` (once per process; `test-s1-emulate.R`: "never silent"), and
   contract 1.5 sends notices through `gptr_inform()`. The exiting `message` handler of
   `adp_check_classify()` failed the first case for it, so the verdict depended on the
   session's once state. The case's request was never sent, and the user's one notice was used
   up by a check that never showed it. Fix (`R/provider-anthropic.R`):
   - for an inprocess `run()` only, `adp_check_classify(notices = TRUE)` muffles a `gptr_message`
     with a calling handler (through its `muffleMessage` restart) and records its text. The
     passing `.no_condition` row notes it ("muffled notice: ...");
   - a bare `message()`, a `gptr_message` without a muffle restart, a warning or an error still
     fails the case through the exiting handlers, and a wire `parse()` stays fully silent;
   - new `adp_once_restore()`: `adp_check_classifier()` clears the once slots (04 section 2.1)
     that its replay set, because whatever the replay signalled was caught or muffled and never
     shown.
2. *Usage NA semantics were unchecked.* `.result` took any count, and its comment claimed "unknown
   counts NA". Fix:
   - an optional golden `<case>.usage.json` (`{"input", "output"}`, `null` for an unreported
     count that must stay NA, IC-74) gives a new row `.golden_usage` after
     `.golden_answers`, for answered cases (`adp_classifier_usage()`; a malformed usage golden
     fails the row, and a failed case gets no usage row);
   - every answered built-in case now has one: 8 typesafe and 5 ollama goldens from the wire
     `usage` of each body (`computed` in both directories has none: `null`/`null`). One new
     typesafe case, `usage-partial` (only `input_tokens` on the wire: `{"input": 77, "output":
     null}`), checks the counts one by one;
   - `.result` now also requires each count to be NA or one nonnegative, finite number, and the
     comment says that `.golden_usage`, not `.result`, checks the NA semantics. The case-file
     filters (`adp_check_classifier()` and the test helper `cls_cases()`) skip `.usage.json`.

Tests (`test-provider-anthropic.R`):
- the built-in fixture test now expects `.golden_usage` on every answered case: 5 rows per
  answered case, 3 per failed case;
- new test "classifier usage meets its golden: unreported counts stay NA (IC-74)": the
  reviewer's zeroing wrapper fails exactly `computed` (and typesafe `usage-partial`); dropped or
  swapped counts fail; -1, Inf and NA fail `.result`; malformed goldens fail; a usage golden on
  an error case adds no row;
- new test "s1-emulate replays fixture states; its calibration notice fails no case (IC-19)":
  the reviewer's scenario through a fake chat provider `emu`. All 12 rows pass with no
  condition escaping and 3 requests sent, the notice is noted on `a1`, and the once slot is
  unset afterwards (a real `s1_emulate_classify()` still gives the notice). With the slot
  already set the verdicts are identical. A bare `message()`, an unmuffleable `gptr_message`
  and a warning from `run()` fail every case, and a `gptr_inform()` in a wire `parse()` fails.
- Regression red, against the round-0 code: `^provider-anthropic$`
  `[ FAIL 43 | WARN 0 | SKIP 0 | PASS 429 ]`, all failures and no errors
  (`task6-fix1-red.log`). Among them, the emulate case `a1` failed `.no_condition` on the notice,
  2 of 3 requests were sent, the once slot was left set, the next `s1_emulate_classify()` gave no
  notice, and with the slot preset the verdicts differed (`a1` then passed all four rows). The remaining failures were the
  missing `.golden_usage` rows, the `.usage.json` files read as cases (`.fixture`), and -1/Inf
  accepted by `.result`.
- Green: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 472 ]` (`task6-fix1-green1.log`). Adding the
  unmuffleable-notice assertion gave the final `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 475 ]`
  (`task6-fix1-green.log`), the same under `LC_ALL=C` (`task6-fix1-green-lc-c.log`).
- Neighbours (same filter as above): `[ FAIL 0 | WARN 0 | SKIP 4 | PASS 3956 ]`
  (`task6-fix1-neighbours.log`; 3908 + the 48 new provider-anthropic passes; the 4 skips are
  the live tests). `^(arch-layers|lint-rules)$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 18 ]`
  (`task6-fix1-arch.log`).
- Lint: "No lints found." for `R/provider-anthropic.R` and
  `tests/testthat/test-provider-anthropic.R` (`task6-fix1-lint.log`). ASCII-only, no line over
  100 characters.
- Document: the roxygen touched is `@noRd`. On a fresh scratch copy (without `.secrets/`), the
  `document` action left `man/` and `NAMESPACE` identical to the working tree and gave no note
  for `provider-anthropic.R` (`task6-fix1-document-scratch.log`).
- `dev/DEVIATIONS.md`: D-026's closing section, items 2 and 3, now describes `<case>.usage.json`,
  `.golden_usage`, the counts accepted by `.result` and the muffled notices of an inprocess
  `run()`, and gives 19 typesafe cases. The cross-reference bullets in `progress/P12.md` and
  `progress/P13.md` stay as they were (still accurate). Note for the committer: the P13 lane's
  commit `1968f1c` ("docs(progress): record P13 plan acceptance") already contains the P13
  "Cross-reference (FIX-6, ...)" bullet, so `progress/P13.md` has no FIX-6 hunk left to stage.

Not changed: the stream path's `adp_check_replay()` (plan Task 3) still uses exiting handlers
for every condition. Stream normalisers have no notice channel (04 section 8.1: no R
condition after start), so the finding does not apply there.

Logs: `dev/.validation/FIX/task6-*.log`. Files of this task:
- `R/provider-anthropic.R`, `R/s1-types.R`, `R/s1-client.R`
- `tests/testthat/test-provider-anthropic.R`
- `tests/testthat/fixtures/classifier/` (new: two directories, 80 files; review round 1 added
  13 `.usage.json` goldens and the typesafe `usage-partial` case with its answers and usage
  goldens)
- `dev/DEVIATIONS.md` (the D-026 title and closing section)
- `dev/progress/fixes.md` (this section)
- `dev/progress/P12.md` (cross-reference)
- `dev/progress/P13.md` (cross-reference under Task 8b's forward notes only; the P13
  acceptance section at the end of that file belongs to the P13 lane)

Commit subject: `test(provider): conformance coverage for classifier adapters`.

## Task FIX-7 - home_keep() keeps environments that eval() puts on the call stack (2026-10-05)
- Red: FAIL 1 (`session-live`: an eval() target got no home). Green: `session-live` PASS 82
  (+1 test). Lint clean. Neighbours green: `session-|agent-` PASS 2142,
  `doc-replay|env-snapshot|doc-blocks` PASS 1056 (P15 Task 17 tests now pass),
  `copy-|gptr-gateway` PASS 391.
- Reviews: round 1 clear; minor fixed test-first: home_label() skips primitive frames as
  home_keep() does, so a kept eval() target is `<environment>`, not `frame of eval()`; nit
  (line wrap) fixed.
- Deviations: none (implements 03 section 5.1 `home`: never a function frame). Open: none.

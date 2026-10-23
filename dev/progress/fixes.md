# Coordinator follow-up fixes (FIX-1..9, PERF-1)
Defects routed from plan lanes and fixed outside plan tasks; the owning plans' logs cross-reference
them. Status: FIX-1..4, 6..9 committed; FIX-5 partial (P15 part done, the rest is FIX5-LINT).

## FIX-1 - Fix session finalizer race with registry iteration (2026-10-04, `a5af999`)
- Owners P02 (`R/ext-registry.R`, `ext-events.R`, `ext-load.R`, `ext-check.R`) and P06
  (`R/session-live.R`, `session-object.R`); maintainer-requested. Defect (`progress/P07.md` Task 7
  review item 2): `session_finalizer()` dispatched `session_shutdown` inside any `gc()`, so registry
  loops failed with "object 'rNN' not found". Finalizer now queues with `ev_defer()`; `ev_drain()`
  runs at registry entry (never nested); the six get-after-snapshot loops skip missing ids.
- Red: FAIL 21 (the race, shutdowns inside `gc()`, missing `ev_defer()`/`ev_drain()`). Green:
  `session-live|ext-registry` PASS 253 (198 existing; +2 tests/13 in `test-ext-registry.R`, +7/42 in
  `test-session-live.R`), with `ext-events` 449, `session-live` 78 three times. Lint clean.
  Neighbours: `ext-|session-|agent-|aaa-state|zzz` PASS 3722 FAIL 1 (known `test-zzz.R:301`,
  `gptr_return`/`gptr`, P08/P15), `arch-layers|lint-rules` 18, `prompt-` 745 green.
- Reviews: r1 1 finding (0/0/1, tests only: natural collection before the controlled `gc()`; fixed
  with a holder env and explicit `gc()`, +3 expectations; regression red FAIL 8); verdict clear.
- Deviations: D-085. Open: none (P07's test `gc()` workarounds, left to P07, are gone). Notes: a
  direct `ev_dispatch("session_shutdown")` still drops at once; P04's reactor pump is no safe point.

## FIX-2 - Build gptr:: calls without quote() in the document scanner (2026-10-04, `13ddf95`)
- Owner P15 (`R/doc-blocks.R`, `doc_drop_expr()`, IC-48). The literal `quote(gptr::gptr_return)` /
  `quote(gptr::gptr)` made R CMD check warn "Missing or unexported objects" (fails hosted CI) and
  failed `test-zzz.R:301`. Heads are now built with P09's `eval_guard_ns_call()` (identical calls;
  L4 -> L4 svc), as CI-4 did in `R/eval-guard.R`.
- Red: FAIL 2 (`test-doc-blocks.R:514` walker, `test-zzz.R:301`). Green: `doc-blocks|zzz|eval-guard`
  PASS 480 (478 + 2; +1 test, 13 expectations); installed-package `.check_packages_used()` warns on
  HEAD, clean with the fix. Lint clean. Neighbours: `doc-|arch-layers|lint-rules|eval-|env-history`
  PASS 1046 SKIP 1 (`test-eval-core.R:413`, D-054) green.
- Reviews: none recorded.
- Deviations: none (behaviour unchanged). Open: none. Note: the helper stays correct after P08
  exports `gptr()`/`gptr_return()`.

## FIX-3 - rebuild_frozen() keeps human and reinject (2026-10-04, `106434a`)
- Owner P06 (`R/session-store.R` Task 13; Task 12's replay cut via `replay_rebuild()`). Defect
  (`progress/P07.md` Task 7 review item 3; D-069 "Open for P06"): resumed sessions, their forks and
  replay cuts lost P07's `gptr.frozen` keys `human` (IC-52 audience) and `reinject` (IC-71 cut).
  `rebuild_frozen()` now returns `prompt_frozen_restore()`'s ten fields, reading the cut with
  P07's `prompt_reinject_read()`.
- Red: FAIL 12 (`human`/`reinject` NULL, length 7 not 10). Green: `session-(store|object)` PASS 718
  (698 + 20; +4 tests), `session-store` 252. Lint clean. Neighbours: `session-|agent-run` 1642,
  `arch-layers|lint-rules` 18, `doc-|ckpt-|agent-|ext-registry|ext-events` 1815, `prompt-` 894
  green.
- Reviews: none recorded.
- Deviations: none new; closes D-069's open item. Open: P07 Task 7 review item 2 (a fork of a
  foreign-resumed session before its first run restores the foreign prompt), a separate P06 fix.

## FIX-4 - Make secret_late_check() tolerate NA in live entries (2026-10-04, `d34e1c2`)
- Owner P03 (`R/auth-secrets.R`, IC-70 check); found by P12's plan acceptance (`progress/P12.md`).
  NA usage/cost (IC-74, D-022) made `if (n > 0L)` error, so every `secret_register()` threw after
  P12's tests (P05's `provider_credential()` too); a non-atomic leaf skipped a whole session. New
  `secret_known_strings()` scans character leaves only (as `redact_tree()`); an audit of
  `auth-secrets.R` and `auth-redact.R` found no other NA-unsafe `if`.
- Red: FAIL 1 ("missing value where TRUE/FALSE needed");
  `provider-anthropic|provider-registry` FAIL 9. Green: `auth-secrets` PASS 302 (296 + 6; +1 test),
  cross PASS 1032 (992 + 40). Lint clean. Neighbours: `auth-` 1068 SKIP 1
  (`test-auth-store.R:75`, keyring), `session-live|arch-layers|lint-rules` 96 green; full suite
  PASS 16358 SKIP 6 FAIL 3 (`test-perm-classify.R:817/1038/1213`, P11's then-uncommitted code).
- Reviews: none recorded.
- Deviations: none. Open: none.

## FIX-5 (P15 part) - doc_format_of() reads extensions with path_ext() (2026-10-05, `3e24e8c`)
- Done in and committed with P15 Task 13. R >= 4.6's `tools::file_ext()` stops on a UTF-8
  non-ASCII path in a non-UTF-8 locale; `R/doc-io.R` now uses P01's `path_ext()`.
- Red: FAIL 1 ("unable to translate 'caf<U+00E9>.R'"). Green: `doc-io` PASS 361 (352 + 9; +1
  test); `doc-(formats|replay|io)` with Task 13 PASS 903 in the default and C locale. Lint clean.
- Reviews: none recorded.
- Deviations: D-122 item 7 (rule: D-111 item 1). Open: `R/ext-specs.R` (P02/P17) and
  `R/gptr-gateway.R` (P08) still call `tools::file_ext()` -> FIX5-LINT (HANDOFF section 5).

## FIX-6 - Conformance coverage for classifier adapters (IC-74 P12 row) (2026-10-05, `2d2d75a`)
- Owners P12 (`check_adapter()`, `R/provider-anthropic.R`) and P13; closes P12 acceptance open
  item 1 and D-026's open point. A classifier adapter replays `fixtures/classifier/<api>/` cases,
  rows `.no_condition`, `.result`, `.canonical`, `.golden_answers` or `.typed_error`,
  `.golden_usage`. P13's validator moved unchanged from `s1-client.R` (L4) to `s1-types.R` (L1)
  (119 definitions identical; layering control FAIL 1). Plan Task 3 test changed: a fixture-less
  classifier fails `adapter.fixtures` (was `adapter.replay` TRUE). Cases: typesafe 19, ollama 13.
- Red: FAIL 86 (missing classifier rows). Green: `provider-anthropic` PASS 475 (P12 acceptance
  307; +7 tests, 1 adapted), also under `LC_ALL=C`. Lint clean; `document` unchanged (the six
  known "[0, 1]" link notes now come from `s1-types.R`). Neighbours:
  `s1-*|provider-*|ext-check|aaa-state|copy-s1|live-*` PASS 3956 SKIP 4 (live),
  `arch-layers|lint-rules` 18 green.
- Reviews: r1 2 findings (0/0/2) -> D-026 items 2-3, fixed test-first (regression red FAIL 43):
  s1-emulate's IC-19 notice failed `.no_condition` (inprocess `run()` now muffles it,
  `adp_once_restore()`); usage NA unchecked (`<case>.usage.json`, `.golden_usage`). Verdict clear.
- Deviations: D-026 closing section (items 1-5). Open: none. Notes: the stream path's
  `adp_check_replay()` keeps exiting handlers (04 section 8.1); P13's cross-reference bullet landed
  in `1968f1c`; fixture layout superseded by K-CLS (`1dac2be`, `progress/simplicity.md`).

## FIX-7 - home_keep() keeps environments eval() puts on the call stack (2026-10-05, `7d784df`)
- Red: FAIL 1 (`session-live`: an eval() target got no home). Green: `session-live` PASS 82
  (+1 test). Lint clean. Neighbours green: `session-|agent-` PASS 2142,
  `doc-replay|env-snapshot|doc-blocks` PASS 1056 (P15 Task 17 tests now pass),
  `copy-|gptr-gateway` PASS 391.
- Reviews: r1 1 finding (0/0/1) + 1 nit, fixed test-first: home_label() skips primitive frames
  as home_keep() does, so a kept eval() target is `<environment>`, not `frame of eval()`; verdict
  clear.
- Deviations: none (implements 03 section 5.1 `home`: never a function frame). Open: none.

## FIX-8 - The image placeholder names a call that works (2026-10-05)
- `peter$plot("<id>")` (IC-67) re-attaches the session's image with that id (`images_scan()` moved
  to L0 `utils-tokens.R` for P10); `gptr.image_elision` lists an id once per omitted copy and
  `images_omit()` omits one copy per listing, so the re-attached copy is sent; `images_elide()`
  takes the projection (`request_fallback()` omits first). Two P06 tests re-elide the projection;
  a second fallback build checks that elision is recorded once.
- Red: FAIL 1 (`'which' must be number`), then FAIL 1 (the copy omitted again). Green: `agent-run`
  PASS 597 (+1 test), `tool-namespace` 398 (+1), `prompt-cache` 104. Lint clean. Neighbours
  `^(arch-layers|lint-rules|session-|agent-|prompt-|tool-r$|tool-read|eval-plots|eval-format|`
  `utils-tokens|copy-)` PASS 3510; token bench `run.R --check` OK (placeholder text unchanged).
- Reviews: R1 changes required. Major (the fallback's `images_omit()` untested): second fallback
  build added, FAIL 1 with the line removed. Minor (listings cut by a compaction): Open. Nits fixed.
- Deviations: none (D-036 item 7 holds). Open: `context_tokens()` estimates a copy re-attached
  after its anchor as omitted until the next reported total; listings whose copies a compaction
  cut still omit the next copies of their id, so the first `peter$plot("<id>")` after it is
  omitted again (as at HEAD; tying listings to their entries is a larger change).

## FIX-9 - Policies read their own extension state (2026-10-06)
- `perm_policies()` calls each policy with the ctx attributed to its record's source
  (`ctx_with_source()`, as `ev_call()` does for hooks), so `ctx$state()` is the policy's own
  extension state (04 section 10.6); `registry_all_recs()` returns the records `registry_all()`
  maps.
- Red: FAIL 1 (`agent-dispatch`: the policy read NULL). Green: `agent-dispatch` PASS 210 (+1 test).
  Lint clean. Neighbours: `agent-|ext-|session-` PASS 4027, `^perm-` PASS 879.
- Reviews: R1 clear, 1 minor (counts taken with Task 7's uncommitted files; header not updated):
  counts re-measured on HEAD plus FIX-9, header updated.
- Deviations: none. Open: none.

## PERF-1 - Settings are read from disk once per change, not once per lookup (2026-10-06)
- `settings_file_read()` keys its cache on mtime, ctime and size and caches a file only once its
  last change is over 2 s old (git's racy-clean rule, as `ckpt-files.R`).
- Red: FAIL 2 (a file changed within 2 s served from the cache; a same-size rewrite with its
  mtime restored read stale). Green: `^gptr-config$` PASS 492 (+1 test). Lint clean. Neighbours:
  `gptr-|session-|agent-|ext-|doc-|s1-` PASS 8966 SKIP 1.
- Measured: 10 fake-provider sessions, best of 3, 1.31 s before and 1.33 s after (files were
  already parsed once per change); elapsed sampling puts `settings_layered()` at 3.5-7%, so layer
  paths are not cached.
- Reviews: R1 clear; minor (a malformed file changed within 2 s logs a diagnostic per lookup)
  accepted as Open; nit (entry length, stale warning note) fixed.
- Deviations: none. Open: a malformed settings file changed within 2 s logs its `parse_error` once
  per lookup; a new session's time is in `ev_redact_payload()` (21% elapsed), `model_resolve()`
  (17%) and `registry_sort()` (13%).

## Task FIX-10 - A worker receives no closure environments beyond its own records (2026-10-06)
- Red: FAIL 2 in `^subagent-worker$` (the walk entered the registry; no `refhook`) and FAIL 2 in
  `^secrets-e2e$` (spec.rds 30 MB holding the key 15 times). Green: `^subagent-worker$` PASS 114,
  `^secrets-e2e$` PASS 36, `^(ext-plugins|secrets-e2e)$` PASS 415. Lint clean. Neighbours: `^subagent-`
  PASS 565, `^(secrets-e2e|injection-e2e)$` PASS 229, `cli-codex` PASS 248 (INFRA-16 leg skips: gptr not
  installed), `^(arch-layers|lint-rules)$` PASS 19, `^(utils-paths|utils-hash|copy-ckpt|doc-io)$` PASS 604.
- Reviews: none recorded.
- Deviations: D-177. Open: none.

## Task CI-15 - The artifact registry tests leave no processx supervisor open (2026-10-06)
- Red: the connections gate on `^artifact-(app|registry)$` 3 -> 5, and on `^northstar$` 3 -> 5 (processx's
  supervisor fifos: chromote, started by the registry's launching tests and by NS-8, always supervises
  Chrome). Fix (tests only): CI-8's per-file `supervisor_kill()` line moves from test-artifact-app.R to
  setup.R (`testthat::teardown_env()`), ending the supervisor with the run; NS-8 in test-northstar.R closes
  its browser. Green: gate `^(artifact-app|artifact-registry|northstar)$` 3 -> 3, PASS 543; `^northstar$`
  gate 3 -> 3, PASS 81. Lint clean. Neighbours: `^(artifact-|copy-artifact$|lint-rules$|northstar$|utils-options$)`
  PASS 603.
- Reviews: r1 1 finding (0/1/0): the per-file fix left NS-8's supervisor open (3 -> 5) -> fixed (suite-level).
- Deviations: none. Open: none.

## Task CI-16 - The plugin settings test unregisters the user-scope command it creates (2026-10-06)
- Red: after `^ext-plugins$` the process registry still held the user command `p17-user-ext` (1
  record, shipped to later workers). Fix (test only): the test's defer removes that record, as
  `test-secrets-e2e.R` does for `e2e-ext`; 0 records after the file. Green: `^ext-plugins$` PASS 379,
  `^(ext-plugins|subagent-worker|secrets-e2e)$` PASS 529. Lint clean. Neighbours: `^(ext-|subagent-)`
  PASS 2332.
- Reviews: none recorded.
- Deviations: none. Open: none.

## Task FIX-11 - gptr_sessions() shows created and updated in the same time zone (2026-10-06)
- Red: FAIL 1 in `^session-store$` (America/Los_Angeles: `created` shown in UTC, `updated` from
  `file.mtime()` in local time, 25199 s apart). Fix: a stored row's `updated` is UTC POSIXct like
  `created`, the live row and the empty frame. Green: `^session-store$` PASS 253. Lint clean.
  Neighbours: `^session-(store|object|live)$` PASS 800, `^ckpt-rewind$` PASS 192,
  `^(arch-layers|lint-rules)$` PASS 19 green.
- Reviews: none recorded.
- Deviations: none. Open: none.

## Task PERF-2 - Stream-event redaction does constant work per event (2026-10-07)
- Red: FAIL 13 on HEAD sources (per call: marker table, built-in markers, registry walk; latin1
  text valid as UTF-8 re-marked). Green: `^auth-redact$` PASS 471 (421 + 50; +3 tests), also under
  `LC_ALL=C`. Lint clean. Neighbours: `auth-|secrets|ext-|injection-e2e|session-live|console-`,
  `provider-registry|subagent-team|arch-layers|lint-rules|doc-blocks|cli-common|s11-conformance`,
  `agent-run|gptr-gateway`, dev bench `perf` green; `perf/run.R --check` exit 0 (new row `peter`
  1.73 s, bar 3 s; HEAD 5.88 s fails).
- Measured: `peter()` over a fake 50 KB reply 5.8 -> 1.65 s (installed 5.15 -> 1.49 s);
  `test-subagent-team.R` 186.6 -> 65.4 s; installed suite, NOT_CRAN unset, 420.8 -> 284.1 s. Output
  byte-identical to HEAD on 2,965 comparisons except latin1 text valid as UTF-8 that matches no
  value: kept as given (as with an empty vault; HEAD re-marked it UTF-8, under `LC_ALL=C` as
  `<c3><a9>` text).
- Reviews: none recorded.
- Deviations: none. Open: the report-budget test still takes 47.5 s (was 167.2 s; per-delta event
  pipeline, redaction about a third).

## Task FIX-12 - A speculative keyring lookup never warns about keyring's env fallback (2026-10-07)
- Red: FAIL 2 in `^auth-secrets$` (the keyring source's `resolve`/`list` passed keyring's "Selecting 'env'
  backend" warning through; hosted run 37588313491 WARN 2 at `test-auth-secrets.R:423/505`). Fix: both
  run with `options(keyring_warn_for_env_fallback = FALSE)`, restored on exit; `auth-store.R`'s
  explicit keyring references unchanged. Green: `^auth-secrets$` PASS 308 (+1 test). Lint clean.
  Neighbours: `^auth-` PASS 1199 SKIP 1 (keyring installed), `^secrets` 36,
  `^(arch-layers|lint-rules)$` 19, `^(ext-api|provider-registry)$` 960 green, all WARN 0.
- Reviews: none recorded.
- Deviations: none. Open: none.

## Task CI-21 - Every timed compaction wait runs under the controlled clock (2026-10-18, #47)
- `test-compaction-wait.R:569` failed in run 38997490469 (`ubuntu-latest (release, LC_ALL=C)`,
  `short$elapsed` 0.42 >= 0.20): `cp_wait_short()` timed `gptr_wait(timeout = 0.04)` on the real
  clock while its synchronous reactor step (`run_drive()` through `compact.run`) stalled. Fix (tests
  only): `cp_wait_clock()` opens the eight tests that timed `cp_wait_short()` without it (HEAD
  `:113, 179, 363, 514, 565, 748, 854, 934`); every 0.2 s bound and fixture guard is unchanged.
- Red: a scratch copy with a 0.4 s `Sys.sleep()` in the first `run_drive()` of each test's first
  short wait FAIL 31, in all eight tests. Green: that copy with the fix PASS 506 in 10 of 10 runs;
  `^compaction-wait$` PASS 506, also under `LC_ALL=C`. Lint clean. Neighbours:
  `^(compaction-|prompt-compact$)` PASS 1043.
- Reviews: none recorded.
- Deviations: none. Open: none.

## Task CI-22 - wait_until() reads its condition once per poll (2026-10-18, #47)
- `test-proc-supervise.R:123` failed in run 38997490469 (`macos-latest (release)`) well before its
  10 s deadline: `wait_until()` read `cond()` in its loop test and again for its value, and
  `marker_tree_is()` is not monotonic on macOS (`ps` cannot read the environment of the SIP
  `/bin/sh` that runs `R_HOME/bin/R` between `Rscript` and `bin/exec/R`). Fix (tests only): the
  helper returns TRUE on the first read that holds and FALSE once the deadline passes, in
  `test-proc-supervise.R` and in its copy in `test-proc-spawn.R` (its `reactor_now()` clock kept);
  deadlines and callers unchanged (the other callers wait on monotonic conditions).
- Red: FAIL 4 in `^proc-(supervise|spawn)$` (+1 test per file: a TRUE-then-FALSE condition made the
  old helper return FALSE after two reads). Green: `^proc-(supervise|spawn)$` PASS 371. Lint clean.
  Neighbours: `^proc-` PASS 2092 SKIP 11.
- Reviews: none recorded.
- Deviations: none. Open: `:123` may now pass during the `Rscript` stage, so the sweep may kill by
  recorded pid and creation time rather than by marker tree; an orphan that prints a ready line
  from R would pin the marker-tree path (proposed in #47, not done).

## Task CI-23 - The backpressure sampler retries one transient observer failure (2026-10-18, #47)
- native-06 (`test-proc-writer-idle-slots.R:98, 105`) failed in run 38997490469
  (`windows-latest (oldrel-4)`) on `observer-metadata-invalid` at `entry-metadata`: CPython
  `os.lstat` of a delete-pending Windows file returns `st_ino == 0`, and the strict oracle ends the
  case at the first observer error (the same class failed 8 earlier Windows jobs). Fix (tests only,
  #47 Option A): `bp_observe()` takes one more snapshot only after `observer-metadata-invalid`,
  `-snapshot-deadline`, `-parent-entry-absent`, `-link-entry-absent` or
  `-entry-disappearance-uncertain`; any other reason or a failed retry is still one fatal sampling
  error, and every bound and the observer are unchanged. The witness adds `observer_retries` and the
  first `observer_retry_reason`. A failed retry reports its own condition, because the observer's
  `last_failure` (read by `bp_sample_error()`) then describes the retry.
- Red: FAIL 51 in `^proc-backpressure-sampling$` (+2 tests: `bp_observe()` per reason; `bp_run()`
  with a base R child and a scripted observer, where one retried failure completes with
  `sampling_errors` 0 and a bound reason or a failed retry stays `resource_observation`). Green:
  `^(proc-backpressure-sampling|bp-declared-observer|bp-disk-observer)$` PASS 639 SKIP 5 (no
  Python; with Python 3.15 `^bp-disk-observer$` PASS 145). Lint clean. Neighbours: `^(proc-|bp-)`
  PASS 2285 SKIP 16, `^(bridge-python-native|subagent-worker)$` PASS 157 SKIP 7.
- Reviews: r1 1 finding (high): the `bp_run()` case enabled the observer, so the suite process
  (its supervisor) counted toward the unchanged 1 GiB caps, and a one-process ordinary run as
  `test_check()` does (128 files, RSS 3.6 GB) stopped it at initialization -> fixed (tests only):
  the case mocks `ps::ps_memory_info()` to a unit RSS. Red: ERROR 1 (`initialization exceeded its
  unchanged resource bound`) with 1.2 GB of ballast in the test process; green PASS 512 with 1.2
  and 3.6 GB. One process over the 127 ordinary files to this one (installed package): PASS 22265
  SKIP 24, RSS 3.3 GB at the end.
- Deviations: none. Open: hosted Windows evidence (native-06 and the other native backpressure
  cases on release and oldrel-4, twice). On 85e5883 the one retry met the same delete-pending file
  (native-07), so CI-70 retries for one snapshot deadline; on d9a7840 native-01's entry outlasted
  that too, so CI-73 charges an exactly delete-pending file as a file.

## Task CI-24 - The fd-0 reader test types its check mark only in a UTF-8 locale (2026-10-18, #48)
- `test-console-typing.R:446` (new in #48) failed in runs 39175666947 and 39179983061
  (`ubuntu-latest (release, LC_ALL=C)`): `processx` writes text in the native encoding, so
  `p$write_input("one\ntwo \u2713\nthr")` cannot encode the check mark in a C locale and errors
  before the reader runs. Fix (tests only): the typed second line is `"two \u2713"` in a UTF-8
  locale and `"two"` otherwise; the complete-line, partial-line, Ctrl-D and `/dev/null` checks run
  unchanged in every locale.
- Red: `^console-typing$` under `LC_ALL=C` ERROR 1 (the CI error). Green: PASS 88 under `LC_ALL=C`
  and in UTF-8. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: none.

## Task CI-25 - The plan gates accept any contiguous P01..Pnn plan set (2026-10-18, #51)
- `dev/ci/check-plans.py` required exactly P01..P25 and a 25-plan index, so P26 turned the Linux plan
  gate (Plan-gates.yaml, Optional-integrations.yaml) red with "Require the exact P01 through P25 plan
  set" before any check ran. Fix (CI only, `3e63a8a`): `plan_files()` takes P01..Pnn with no gap,
  duplicate or malformed name and n >= 25, and the index must cover all with zero error findings;
  `extract.py` extracts every `P<nn>-*.md` (it dropped plans above P25).
- Red: a full `check-plans.py` at base stops with the P25 message. Green: `test-check-plans.py` 8 OK
  (+2 plan-set cases); a full run 26 plans, 0 errors, 770 R blocks clean, no lints.
- Reviews: r1 1 finding (low: `extract.py` still stopped at P25) -> fixed.
- Deviations: none. Open: `build_index.py --scope` still defaults to P01-P25 (labels only); Plan-gates
  has not run on this branch (dispatch only).

## Task CI-26 - The optional-integration registry names current tests only (2026-10-18, #51)
- 7928d0f and 326fe82 renamed two cases each in `test-artifact-browser-cleanup.R` and
  `test-cli-codex.R`, but `dev/ci/optional-integrations.R` kept the old titles, so every
  Optional-integrations row selecting those files stopped at "Missing mandatory integration cases".
  Fix (CI only, `b00d681`): the registry and its two pinned copies carry the current titles; a pure
  gate test, "every approved title names a current test of its file", walks the combined registry
  by position.
- Red: the new test fails on exactly the two renamed files. Green: `dev/ci/test-optional-integrations.R`
  PASS 3737. Lint clean.
- Reviews: r1 1 finding (medium: a by-name lookup never read the guard titles) -> fixed (index loop).
- Deviations: none. Open: none; the gate caught the later renames (CI-57) in the optional run on
  2c9b6a4 (run 39202182790, job 117897311639) and passed on 92a2944 (run 39235001873).

## Task CI-27 - Ordinary windows-by-file runs provision R-CMD-check's Windows Python (2026-10-18, #51)
- On Windows `bp_run()` always starts the no-follow disk observer, which needs `RETICULATE_PYTHON` and
  `RETICULATE_USE_MANAGED_VENV=false`; ordinary windows-by-file set neither, so every observer case
  failed with "The optional nofollow observer requires its provisioned Python runtime" (run
  39179988023 job 117830492561; run 38839828091 job 116777121470). Fix (CI only, `f1b62da`): ordinary
  mode runs R-CMD-check's `actions/setup-python` pin (3.12.10) and provisioning step.
- Green: the workflow parses and the step conditions select provisioning only in ordinary mode (and
  the RSS route).
- Reviews: r1 no finding.
- Deviations: none. Open: none; the ordinary run on 2c9b6a4 (run 39202175985, job 117897290402)
  passed every `test-proc-writer-*.R` observer case. Repeat pending (P27 A3).

## Task CI-28 - The checkpoint ACL script gets a startup-safe hang guard (2026-10-18, #51)
- "the blob store reports effective create denial and restores its owned bucket" ran its test-owned
  PowerShell deny/restore script under `processx::run(timeout = 5)`; two of four real-CRAN-mode
  Windows R-devel Exact-tarball legs (jobs 114834115071, 114882859729) stopped at `stage=launch`: a
  cold PowerShell start alone took over 5 s. Fix (tests only, `17c0fb9`): a 60 s guard for deny and
  restore; no assertion changed and no product path runs the script.
- Green: `^ckpt-files$` PASS 241 on macOS (the branch is Windows-only). Lint clean.
- Reviews: r1 no finding.
- Deviations: none. Open: Exact-tarball on 2c9b6a4 (run 39202180585) green on Windows release and
  R-devel in CRAN mode, once. Repeat pending (P27 A5).

## Task CI-29 - Owned Windows test children start from pwsh, not Git Bash (2026-10-18, #51)
- "Windows native absence probe refuses existing aliases and denied attributes"
  (`test-proc-writer-runtime.R`) passed in R-CMD-check but failed the windows-by-file optional
  owned-child runner (runs 38840747973, 38840750797): Git Bash's MSYS runtime enables
  SeBackup/SeRestore in its token and every child's, so the test's own Deny ACL controls were void
  (phases `absence-privilege-pre-backup-2`, `control-*-lookup-2`, probe 2). Fix (CI only, `1637f4b`):
  the ordinary by-file step uses pwsh; the two optional owned-child steps take the runner default
  (pwsh on Windows, bash on Linux).
- Green: both workflows parse; the folded command splits into the expected argv for Linux and
  Windows; `test-optional-dependencies.py` OK.
- Reviews: r1 1 finding (low: `shell: pwsh` also moved the Linux rows) -> fixed (runner default).
- Deviations: none. Open: the optional owned-child run of `test-proc-writer-runtime.R` under pwsh has
  not run; the ordinary pwsh run on 2c9b6a4 passed the file (853 expectations).

## Task CI-30 - bridge_program() skips WindowsApps aliases reported by 8.3 name (2026-10-18, #51)
- On Windows `Sys.which()` returns `GetShortPathName()` paths, so a Store alias read as
  `...\MICROS~1\WINDOW~1\python3.exe` and `bridge_program()`'s `windowsapps` match missed it:
  `peter$script()` and the knit engines could pick the Store python3 or bash stub. Fix (`f370026`,
  `R/bridge-sh.R`): the stub check matches `normalizePath(path, mustWork = FALSE)`.
- Red: the old matcher returns an alias reached under another name (a `WINDOW~1` symlink, scratch
  script). Green: test-bridge-sh.R "program lookup skips WindowsApps aliases, also under Windows 8.3
  short names" on macOS. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: passed on hosted Windows release and oldrel-4 in R-CMD-check run
  39217189384 (9170baf); repeat pending.

## Task CI-31 - Shell routes, scripts and knit engines run on Windows (tests, 2026-10-18, #51)
- `ec6cf5b`, `838f322`, `6ede769` (tests only): the resolution, direct-line, pipeline, timeout
  (`ps_children()` instead of pgrep), `.sh` and `#!` tests of `test-bridge-sh.R` and the shell-engine
  test of `test-bridge-lang.R` drop `skip_on_os("windows")`. New: "a background command line runs in
  the shell and kill() stops its process tree", Windows-only "without Git Bash a Windows command line
  runs in PowerShell, else in cmd", "on Windows a .sh script runs through Git Bash when no bash is on
  PATH", "a windows_only interpreter has its program on Windows and none elsewhere" and "the cmd and
  powershell engines run on Windows with UTF-8 output and exit codes".
- The elapsed bounds of the timeout test (`ec6cf5b`) and the shell-engine test (`6ede769`) go from
  10 s to 30 s on every OS, for Git Bash start-up on hosted Windows; their jobs run 57 s and 999 s,
  so a timeout kill is still proven.
- Green: `^bridge-sh$` PASS 275 SKIP 3, `^bridge-lang$` PASS 106 SKIP 4 on macOS. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: the first hosted runs found cmd output in the OEM page (CI-49) and a lost
  PowerShell exit status (CI-50, fixed by CI-66); the macOS skip of the background tree test went
  with CI-47; the background job tests' timing is CI-65.

## Task CI-32 - A bare R MCP server and the orphan sweep run on Windows (tests, 2026-10-18, #51)
- `efe55df`: "a server configured with a bare Rscript or R command runs with this R" also starts the
  fixture server with command `R` (on Windows `bin/x64/R.exe`, which starts Rterm.exe). `e1ebdb6`: "a
  killed parent leaves a grandchild that the next load's sweep removes" runs on Windows: processx's
  kill-on-close job ends the `proc_spawn()` child with its parent and `Rscript.exe` runs R in its own
  process (R's `src/unix/Rscript.c` calls `AppMain()`), so the child starts a `cleanup = FALSE`
  grandchild, which the sweep kills. Tests only.
- Green: `^mcp-client$` PASS 173 SKIP 1, `^proc-spawn$` PASS 222 on macOS. Lint clean.
- Reviews: r1 1 finding each: (high) the first sweep test followed a supposed Rterm.exe, which is the
  child itself -> fixed (grandchild); (low) a tautological `mcp_stdio_command()` check -> dropped.
- Deviations: D-019 item 2 corrected (P27). Open: the sweep test's read race on hosted Windows is
  CI-56; both pass in R-CMD-check run 39217189384 (9170baf).

## Task CI-33 - Paths, the walker and the edit and write tools run on Windows (tests, 2026-10-18, #51)
- Tests only: drive-path rewrites in `resolve_tool_path()` (`d43511f`); a real junction loop through
  `walk_files()`, `search_find()` and `search_grep()` (`607777a`); case-only patch moves (`439d00c`);
  read-only files refused with EACCES by write and edit (`ea3abc9`); the relative Rscript file
  fallback of `doc_rscript_file()` (`e23f44d`); two operations through a file link refused
  (`9be7d4b`); `path_class()` through junctions and file links (`c036bb2`); `local_symlink()` as the
  one link helper (`d29750a`). Windows links come from the wsec helpers, which skip on CRAN.
- Green: `^tool-walk$`, `^tool-edit$` PASS 170, `^tool-write$` PASS 69, `^doc-locate$`,
  `^storage-boundaries$` PASS 137, `^utils-paths$` PASS 123 SKIP 1 on macOS; the Windows branches were
  checked with `is_windows()` forced and `Sys.readlink()` emptied. Lint clean.
- Reviews: r1 4 findings (1 medium, 3 low) -> CI-35, CI-36, `d29750a`, `9be7d4b`.
- Deviations: none. Open: passed in R-CMD-check run 39217189384 (9170baf, Windows release and
  oldrel-4); the relative chain and loop of `test-tool-write.R` stay POSIX-only.

## Task CI-34 - A Windows patch move never renames a file link over its target (2026-10-18, #51)
- On Windows `Sys.readlink()` is always "", so `patch_finish_move()` took a file link for the moved
  file and renamed it: "Update File: link.R / Move to: real.R" replaced `real.R` with a link to
  itself and reported success. `patch_remove()` used `unlink()`, which on Windows deletes only a
  junction-tagged reparse point. Fix (`e761a8a`, `R/tool-edit.R`): `path_is_link()` decides, and
  `file.remove()` removes the link.
- Red: a macOS run with `Sys.readlink()` stubbed to "" and `is_windows()` TRUE lost the content.
  Green: `^tool-edit$` on macOS; the link moves of two tests now run on Windows. Lint clean.
- Reviews: r1 (medium): `path_is_link()` also flags an 8.3 alias -> CI-35.
- Deviations: none. Open: passed on hosted Windows in run 39217189384 (9170baf).

## Task CI-35 - A patch move from a Windows short-name alias keeps the file (2026-10-18, #51)
- `path_is_link()` flags an 8.3 or trailing-dot alias, so after CI-34 `patch_finish_move()` removed
  the old name and "Update File: LONGFI~1.R / Move to: longfilename.R" deleted the file it had just
  written. Fix (`d415b90`): on Windows a link must also be its own directory entry (`path_listed()`,
  case folded); an alias is renamed and kept, a true link is still removed.
- Red/green: simulated on macOS with an NFD spelling of an NFC name as the alias; `^tool-edit$` PASS
  169. The move-onto-own-file test moves short to long on Windows when the volume has 8.3 names.
- Reviews: none recorded.
- Deviations: none. Open: a short alias of a true file link moved onto the link's target is still
  renamed over the target; passed on hosted Windows in run 39217189384 (9170baf).

## Task CI-36 - write_file() refuses a dangling Windows link as POSIX does (2026-10-18, #51)
- `resolve_link_target()` took a dangling Windows link for a new file, so `write_file()` replaced the
  user's link where POSIX refuses ("it names no file"); `6541910` had pinned that replacement. Fix
  (`745397d`): a missing name that `path_listed()` finds is refused; the edit tool's `patch_key()`
  inherits it, and the dangling case of the chain test runs on Windows (NOT_CRAN).
- Red/green: simulated on macOS with the Windows stubs; `^tool-write$` PASS 69. Lint clean.
- Reviews: r1 (low): `6541910` pinned a fixable inconsistency -> reversed here.
- Deviations: D-231. Open: its premise was wrong: Windows `file.exists()` is TRUE for a dangling link,
  so the refusal never ran there (hosted, CI-51).

## Task CI-37 - The wire log refuses dangling links on Windows too (2026-10-18, #51)
- R's `Sys.readlink()` is "" on Windows (`do_readlink` needs `HAVE_READLINK`), so
  `wire_log_path()`'s dangling-link guard never fired there and `wire_log()` opened a dangling
  junction or file link at or above the log path. Fix (`267f441`): `safe()` refuses a listed entry
  without followed metadata, on every OS (the rule became `path_dangling()`, CI-48; on POSIX a
  readlink target since CI-68).
- Red: a POSIX simulation of the two new Windows tests with `Sys.readlink()` emptied fails 3 on the
  old code. Green: `^http-reactor$` PASS 225 SKIP 2. Lint clean.
- Reviews: none recorded.
- Deviations: D-231. Open: "Windows wire log resolves junctions and refuses dangling ones" and
  "Windows wire log refuses escaping file links, dangling or not" passed in run 39217189384 (9170baf).

## Task CI-38 - Scrub skips dangling links without Windows warnings (2026-10-18, #51)
- `scrub_walk()` chose files with `utils::file_test("-f")`: on Windows `stat()` succeeds on a dangling
  link, so `file.info()` warned "cannot open file" (D-137) and the link counted as a file;
  `scrub_scan()`'s `file.size()` warned again. Fix (`13de743`): a file needs a followed
  `file.info()` mtime, the warning muffled. POSIX unchanged.
- Red: a POSIX simulation with Windows `file.info()` gives WARN 1, ERROR 1 on the old code. Green:
  `^auth-redact$` PASS 486 SKIP 1. Lint clean.
- Reviews: none recorded.
- Deviations: D-231. Open: "Windows scrub skips foreign junctions and dangling links without
  warnings" passed on hosted Windows (2c9b6a4 ordinary by-file; 9170baf R-CMD-check).

## Task CI-39 - Crash recovery runs on Windows (tests, 2026-10-18, #51)
- Tests only: "SIGKILL mid-stream: resume parses, keeps the last complete message, no duplicate" and
  "SIGKILL mid-append, resume, three appends: all present and the tree connected (IC-59)" (`21f01b7`)
  and "SIGTERM leaves a sidecar that the next touch applies around user edits (IC-51)" (`f2cf9a3`)
  drop their Windows skips: processx's `kill()` and `signal(SIGTERM)` are `TerminateProcess()` plus a
  wait there. The two dangling sidecar tests use real junctions (`1b87c03`, `doc_io_dangling()`).
- Green: `^session-store$` PASS 273, `^doc-io$` PASS 670 on macOS. Lint clean.
- Reviews: r1 3 findings (medium: a tree kill built on the false Rterm.exe cause; low: a renamed
  IC-51 test; low: an overclaimed commit body) -> fixed.
- Deviations: none. Open: passed on hosted Windows (2c9b6a4 by-file; 9170baf R-CMD-check), the
  dangling sidecar tests with warnings until CI-60.

## Task CI-40 - The artifact tests run on Windows; a Chrome skip says why (tests, 2026-10-18, #51)
- Tests only: the access token test pins the Windows tokenless fallback (`6644347`); the socket path
  limit check runs on Windows (`0cbd095`); a session-check skip names `chromote::find_chrome()` and
  quotes the last 3 lines of the stderr log its own launch wrote (`71baed1`, `2a5e415`), since both
  Windows R-CMD-check jobs skipped with "startup timed out" only (run 39179983061). `610ecf8` (a
  USERPROFILE with AppData\Local) was reverted by `630968f` as unverified.
- Green: `^artifact-app$` PASS 494 SKIP 0 (real Chrome), PASS 482 SKIP 2 with a fake Chrome;
  `^artifact-browser-launch$` PASS 476. Lint clean.
- Reviews: r1 3 findings (medium: unverified swap -> reverted; low: stale allowances -> CI-42; low: a
  stale log could be quoted -> fixed; its claim that the refusal is a LOG(ERROR) was rejected).
- Deviations: none. Open: on 2c9b6a4 the system Google Chrome quoted "DevTools remote debugging
  requires a non-default data directory" (job 117897245682), so R-CMD-check's session checks still
  skipped; the cause was the suite's empty Windows profile (CI-63).

## Task CI-41 - The credential store, child env and CLI stdin are pinned on Windows (tests, 2026-10-18, #51)
- Tests only: "on Windows auth.json lives under the per-user APPDATA profile (privacy is its ACL)"
  (`0711327`); "an mcp child gets exactly the documented base variables its parent defines"
  (`6e225bb`); a 200 KB codex prompt and "a 200 KB first user line reaches the claude child intact"
  (`275cd6d`), more than the 65536-byte processx stdin pipe and one owned-writer chunk (D-019 item 5).
- Red: dropping `TMPDIR` from the Unix `env_allow_base()` list fails the env test. Green:
  `^auth-store$` PASS 64 SKIP 2, `^auth-childenv$` PASS 167, `^cli-(claude|codex)$` PASS 790 on macOS,
  also under `LC_ALL=C`. Lint clean.
- Reviews: none recorded.
- Deviations: D-234; D-019 item 5, D-101, D-104, D-106 status. Open: passed on hosted Windows
  (2c9b6a4 by-file; 9170baf R-CMD-check); claude control responses over one chunk are untested.

## Task CI-42 - The renamed access-token test loses its Windows skip allowances (2026-10-18, #51)
- After `6644347` the old access-token title matched no test but stayed allowed to skip on Windows in
  `dev/ci/rscript-native.R` and `optional_allowed_skip()`. Fix (CI only, `37edb30`): both entries go,
  and the allowance test names another real Windows platform guard.
- Green: `dev/ci/test-optional-integrations.R` PASS 3695. Lint clean.
- Reviews: r1 finding 2 of CI-40 (low).
- Deviations: none. Open: none.

## Task CI-43 - A walked file is one /undo item in per-turn scan mode (2026-10-18, #51)
- The Exact-tarball windows-latest release check in CRAN mode (job 117848217386) failed the #37 test:
  after a walk slower than `gptr.checkpoint_scan_budget` the session scans once per turn, and
  `ckpt_files_explicit()` recorded the walked `a.txt` with its absolute path, so one file was two
  `/undo` items, the dry run found a conflict and the UI cancelled. Fix (`e941222`): such a row is
  relative, as the walk records it; `05537a8` runs the #37 test in walk mode (budget `Inf`) and a new
  test in per-turn mode (budget -1).
- Red: per-turn mode forced on the old tree fails the #37 test on the same 7 lines as Windows. Green:
  all `ckpt-*` tests and the full offline suite. Lint clean.
- Reviews: r1 (the bound-document rewind fails in per-turn mode) -> CI-54.
- Deviations: D-228. Open: Exact-tarball on 2c9b6a4 (run 39202180585) green in CRAN mode, once.
  Repeat pending (P27 A5).

## Task CI-44 - The observer's supervisor counts toward the cap only by its growth (2026-10-18, #51)
- "a Windows worker exits within 10 s after its acknowledged parent dies (IC-60)" failed in
  rscript-native (run 39185663719, source context) as `resource_limit`: on Windows the observer added
  the supervisor's absolute RSS, 537 MB after 11 earlier files in one process, to the 544 MB family
  (1,088,077,824 > 1,073,741,824); the supervisor grew by 7 MB. Fix (tests only, `f663aa1`): the cap
  charges the supervisor only for its growth since `before_rss`; the 1 GiB cap, family and disk caps,
  deadlines and witness fields are unchanged; CI-23's unit-RSS mock goes.
- Red: FAIL 5 with the old helper and 1.2 GB of ballast. Green:
  `^(proc-backpressure-sampling|bp-declared-observer)$` PASS 583 with 0, 1.2 and 3.6 GB of ballast.
  Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: rscript-native on 2c9b6a4 (job 117897297705) completed the case with guard
  null (combined peak 1,130,909,696 B, growth within the cap); on 92a2944 rscript-native is green.

## Task CI-45 - An exited artifact test child must end with its whole marker family (2026-10-18, #51)
- Release run 39182291391 (job 117842876468) stopped "a broken app ends the child" in cleanup with
  "The artifact test child did not settle"; the same test passed in 37 other hosted Windows jobs.
  Inferred mechanism: processx's `wait()` returns at once after `is_alive()` collected the exit code,
  while ps 1.9.3 lists an exited pid as running; `kill_all()` then ran within milliseconds. Fix (tests
  only, `f35bb9a`): the two tests whose child exits by itself wait, within their 10 s and 15 s, until
  ps lists neither the child nor a carrier of its marker (`family_left()`), which names what stays.
- Green: `^artifact-app$` PASS 499 (NOT_CRAN), PASS 419 SKIP 13 (CRAN mode). Lint clean.
- Reviews: r1 findings 2, 5 and 6: the launch path's exposure -> CI-55; the wording fixed.
- Deviations: none. Open: no recurrence on 2c9b6a4 or 9170baf; the cause stays a hypothesis.

## Task CI-46 - The preflight's tool probes share one startup-safe bound (2026-10-18, #51)
- The optional run 39185668717 (job 117847473135, R 4.6.1) stopped in its dependency preflight:
  `processx::run(Sys.which("perl"), c("-e", "print 42"), timeout = 5)` timed out starting Rtools45's
  `C:\rtools45\usr\bin\perl.exe` (R's installer Rprofile puts Rtools first on PATH). Identical runs
  finished the preflight in 5.7 s and 6.1 s, so the slow start is intermittent. Fix (CI only,
  `6537173`): the quarto, rg and perl probes share `optional_startup_s = 60`; every check, the 90 s
  child deadline and chromote's 10 s bound are unchanged; a dev/ci test pins the probes.
- Red: a fake perl that sleeps 6 s fails the base preflight with the CI error. Green: it passes all
  three probes; windows-rss, windows-token and windows-startup controller tests pass. Lint clean.
- Reviews: r1 finding 4 answered in the commit body; finding 5 declined (the probe calls stay pinned).
- Deviations: none. Open: the preflight passed in the optional run on 92a2944 (run 39235001873).

## Task CI-47 - kill_all() stops the background children a shell's interrupt leaves on macOS (2026-10-18, #51)
- `peter$bg("sleep 57 & sleep 58 & echo ready; wait")` then `job$kill()` left both sleeps running on
  macOS: SIGINT ended the shell alone, the sleeps were reparented to launchd, ps reads no environment
  of system binaries (no marker), and processx's `$kill()` does not signal a reaped leader's group.
  Fix (`812940c`, `R/proc-supervise.R`): `kill_all()` records a live process's descendants by parent
  link before the interrupt and kills them after `$kill()`; no bound changes.
- Red: the unskipped test fails on macOS with the old `kill_all()`. Green: `^bridge-sh$` PASS 279 SKIP
  2, 3 runs; `^(proc-.*|bridge-.*)$` PASS 2691 SKIP 23. Lint clean.
- Reviews: none recorded.
- Deviations: D-233. Open: on 92a2944 `ubuntu-latest (release, LC_ALL=C)` (job 118001849130) failed
  `test-bridge-sh.R:512` (`length(tree)` 1, expected >= 2) in this test; the Linux create-time filter
  of `ps_children()`, which also hid descendants from `kill_all()`, is CI-69.

## Task CI-48 - Scrub refuses a dangling lock-root link where readlink has no target (2026-10-18, #51)
- On Windows `Sys.readlink()` is "" and `normalizePath()` falls back to the lexical path, so
  `scrub_lock()` took the session lock and tried creates through a dangling junction at `.gptr` or
  `.gptr/locks` (Win32 `_wmkdir()` failed them; nothing was written outside). Fix (`2c9b6a4`):
  `scrub_lock()` refuses when `path_dangling(root)` or `path_dangling(lock_root)` holds, before any
  lock; `path_dangling()` (a listed entry without followed metadata; on POSIX a readlink target since
  CI-68) also backs the wire log.
- Red: an emulation on macOS records 2 `write_atomic()` calls on the base. Green: none on this
  commit; `^auth-redact$` PASS 486 SKIP 1, `^utils-paths$`, `^http-reactor$`. Lint clean.
- Reviews: r1 6 findings; F1-F3 applied, F4 not tested (rests on an unverified `dir.exists()`), F5
  -> CI-51, F6 -> CI-52.
- Deviations: D-231. Open: "Windows scrub refuses a dangling lock-root junction before taking any
  lock" passed in run 39217189384 (9170baf).

## Task CI-49 - A Windows cmd line runs in a cmd started after chcp 65001 (2026-10-18, #51)
- Hosted windows-by-file (run 39193453652) returned `"a b" caf\x82 ??` for `echo "a b" café 日本`
  from the cmd knit engine and the cmd route of `peter$sh()`: chcp and the echo shared one `/c` line,
  so the output kept the OEM page. Fix (`7c36123`): `shell_cmd()` runs an outer
  `cmd /d /v:on /s /c` that changes the code page and starts the inner cmd that runs the line from
  `GPTR_SHELL_CMD`; `bridge_exec()` and `bridge_bg()` set the target's env.
- Red: a cross-platform test of the target env fails with the old plumbing. Green: `^proc-spawn$` PASS
  224, `^bridge-sh$` PASS 281 SKIP 2, `^bridge-lang$` PASS 106 SKIP 4. Lint clean.
- Reviews: r1 4 findings: a log claim removed; the env field documented and the spec rows routed to
  D-229; a caller's `GPTR_SHELL_CMD` documented as refused (precedence kept).
- Deviations: D-229. Open: the cmd route and engine passed in R-CMD-check run 39217189384 (9170baf,
  Windows release and oldrel-4); a multi-line cmd chunk still runs only to its first LF.

## Task CI-50 - The PowerShell route's lost exit status gets a diagnostic test (2026-10-18, #51)
- Hosted Windows (run 39193453652) returned status 0 for `Write-Output "café 日本"; cmd /c exit 4`
  through `-EncodedCommand` while stdout matched. `0fbca74` (tests only) keeps the assertion and adds
  a run that prints `lec=$LASTEXITCODE ok=$?` after `cmd /c exit 4` and `cmd /d /c exit 5`, then runs
  this R with status 6. Product unchanged here; the fix is CI-66.
- Green: `^bridge-sh$` PASS 281 SKIP 2 on macOS (the Windows assertions do not run there).
- Reviews: none recorded.
- Deviations: none. Open: on 9170baf both Windows R-CMD-check rows fail `test-bridge-sh.R:146` (status
  0) and `:155` (stdout `lec= ok=True` twice), and again on 92a2944 (run 39235008757); status 6
  passes. `$LASTEXITCODE` stays unset after both cmd exits, so registry AutoRun (the only effect of
  `/d`) is ruled out. Cause and fix: CI-66 (Rtools' MSYS2 `usr/bin/cmd` shadows `cmd.exe` in
  PowerShell's PATH search, diagnostic run 39234534171); its test asserts the status contract instead
  of printing these values.

## Task CI-51 - write_file() refuses a dangling Windows link that stat() still sees (2026-10-18, #51)
- Hosted windows-by-file (run 39193453652) failed `test-tool-write.R:153` with three warnings and
  `Error in file(p, "rb"): cannot open the connection`: Windows `file.exists()` is `_wstati64() ==
  0`, which succeeds on a dangling link, so `resolve_link_target()` returned `path_norm(p)` before
  CI-36's refusal. Fix (`73b60c2`): `path_dangling()` comes first on Windows; POSIX keeps readlink.
  An edit of such a link is refused with the classed error, and an Add File gets POSIX's text.
- Red: a macOS emulation of the Win32 calls reproduces the hosted warnings and error. Green:
  `^tool-write$` PASS 69, `^tool-edit$` PASS 170, `^windows-link-policy$` PASS 21. Lint clean.
- Reviews: none recorded.
- Deviations: D-231. Open: passed in R-CMD-check run 39217189384 (9170baf); a dangling link named
  by its 8.3 alias is not listed and still ends in an unclassed `file()` error.

## Task CI-52 - Scrub refuses a Windows workspace junction onto a foreign directory (2026-10-18, #51)
- `scrub_lock()` refused a `.gptr` or locks link only through `Sys.readlink()`, and `path_inside()`
  resolves both through the same junction, so on Windows it made `<foreign>/locks` and took the
  document lock there. Fix (`fda61bf`): the readlink check is `any(path_is_link(c(root,
  lock_root)))`, identical on POSIX. New mandatory case "Windows scrub refuses a workspace junction
  onto a foreign directory".
- Red: the emulation on the base returns the locks and leaves `<foreign>/locks`. Green: nine
  neighbouring files PASS 1382 SKIP 13. Lint clean.
- Reviews: none recorded.
- Deviations: D-231. Open: passed in R-CMD-check run 39217189384 (9170baf) and the optional run on
  92a2944.

## Task CI-53 - The by-file runner writes its progress to stdout (2026-10-18, #51)
- windows-by-file (run 39193453652) failed `test-console-notice.R:232`: the runner gave testthat's
  LocationReporter `stderr()`, which writes through `REvprintf()` into an active
  `sink(type = "message")`, so its line for the `expect_warning()` at 223:7 entered the test's
  `capture.output(type = "message")`. Fix (CI only, `c8600c8`): the reporter and the runner's lines
  go to `stdout()`, which no sink diverts; the test is unchanged.
- Red: the same failure through the runner on macOS. Green: console-notice 66/66 and all 19
  `console-*` files through the runner. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: `test-console-notice.R` passed in the filtered by-file run on 9170baf (run
  39217182105).

## Task CI-54 - gptr's own document writes stay out of the files checkpointer's turn scans (2026-10-18, #51)
- In per-turn scan mode (a slow walk, which a hosted Windows runner can cross at random) and on every
  CLI route, the agent_end turn scan recorded gptr's own block write into the bound script, so a
  rewind restored the turn-1 bytes and deleted the undone blocks (0 undone markers, 8 requests not
  6). Fix (`136beda`): `doc_write()` and the IDE clean-buffer save run through `doc_own_write()` and
  the new P16 service `checkpoint.own_write`; no bound, scan mode or builtin order changes.
- Red: the new rewind test fails 6 expectations (3 per mode). Green: the full offline suite FAIL 0
  SKIP 61 PASS 34702 in default mode and with budget -1. Lint clean.
- Reviews: r1 4 findings applied (the IDE clean-buffer save included), except part of 3a (a bare
  `hash_file()` could block on a FIFO) and of 4 (session-scoped records are unreachable).
- Deviations: D-232. Open: `test-ckpt-rewind.R` passed on hosted Windows (9170baf).

## Task CI-55 - An exited app's family leaves the process table before the launch settles it (2026-10-18, #51)
- `artifact_launch_shiny()` calls `kill_all(proc, grace = 1)` as soon as the app child exits; if a
  family member is still listed past `kill_all()`'s waits (CI-45's inferred Windows mechanism), the
  launch keeps a recovery record, a job row, `run.json` and the raw log. Defensive fix (`c751670`):
  `proc_family_wait()` (the test rule moved to `R/proc-supervise.R`) gives the exited family up to
  `artifact_stop_grace` (3 s) first, wrapped so an error or interrupt cannot replace the launch error.
- Red: 9 failures against the base launch site, 1 against an unwrapped wait. Green: `^artifact-app$`
  PASS 517 (NOT_CRAN), PASS 437 SKIP 13 (CRAN mode). Lint clean.
- Reviews: r1 5 findings; 1-3 applied, 4-5 kept by choice.
- Deviations: none. Open: the root cause is not proven on Windows.

## Task CI-56 - The orphan sweep test reads only the marker records (2026-10-19, #51)
- R-CMD-check run 39202162326 (2c9b6a4, Windows release and oldrel-4) failed `test-proc-spawn.R:232`:
  the test listed `proc_dir()` by `^GPTR_PROC_`, which also matches the stdin writer's
  `<marker>.stdin` files, and one was removed between the listing and the read. Fix (tests only,
  `9170baf`): the test reads only `<marker>.json`, the records it checks.
- Green: `^proc-spawn$` on macOS. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: passed in R-CMD-check run 39217189384 (9170baf, release and oldrel-4).

## Task CI-57 - The optional and rscript-native registries match the current tests (2026-10-19, #51)
- An audit of each registry's titles and skip allowances against the tests found: the stale
  mandatory "50 KB" codex title (every host failed "Missing mandatory"); Windows allowances for
  tests now renamed or run on Windows; 8 genuine Windows skips (6 FIFO checkpoint, 2 POSIX rename)
  and 4 Windows-only tests skipped off Windows without an allowance. Fix (CI only, `dd4820c`): the
  registries follow, and the skip allowances become one table, `optional_os_skips`, which the title
  check covers. No mandatory case, bound or strictness check is loosened.
- Red: `dev/ci/test-optional-integrations.R` 2 failures. Green: 72 cases, 3803 passed; all 37
  optional files gated on macOS; the hosted 2c9b6a4 by-file rows regated. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: the optional Windows packet passed on 92a2944 (run 39235001873), once.

## Task CI-58 - The optional and callr-native runners write progress to stdout (2026-10-19, #51)
- The optional-integrations and callr-native children built their LocationReporter on `stderr()`,
  which enters a test's message sink (CI-53). Fix (CI only, `8fde8fa`): both use `stdout()`, which
  already goes to its own owned log; the frozen windows-token runners are unchanged.
- Red: a two-test fixture fails its message-capture test with `stderr()`. Green: both pass with
  `stdout()`; the 8 optional files that capture messages pass either way. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: passed in the optional run on 92a2944.

## Task CI-59 - The owned Chrome binds an ephemeral DevTools port (2026-10-19, #51)
- rscript-native on windows-latest (job 117897297705, Chrome for Testing 155) skipped the session
  check: Chrome logged `bind() ... (0x271D)` and "Cannot start http server for devtools." and stayed
  alive without an endpoint; the bind of the port from `port_candidates(1L)` failed with WSAEACCES,
  most likely an excluded port range (inferred: no log shows the runner's ranges), and Chrome does
  not retry. Fix (`96aab0e`): `--remote-debugging-port=0` and the port read from Chrome's
  announcement; `f40cadb` proves the Shiny child's fall-through past a port that does not bind.
- Red: on macOS port 1 reproduces the runner's Chrome log; without the loop's `tryCatch()` the new
  app test fails 2. Green: `^artifact-browser-launch$` PASS 494, `^artifact-app$` PASS 517 (real
  Chrome). Lint clean.
- Reviews: none recorded.
- Deviations: D-230. Open: rscript-native on 92a2944 (run 39234997432) and the optional packet passed
  the session checks with Chrome for Testing; R-CMD-check's system Google Chrome refusal (CI-40) is
  CI-63.

## Task CI-60 - A dangling sidecar link is read without Windows metadata warnings (2026-10-19, #51)
- R-CMD-check on 2c9b6a4 and 9170baf warned in the two dangling sidecar tests of `test-doc-io.R`:
  `file.info(f)` in `doc_sidecar_read()` warns "cannot open file" on Windows, as stat() succeeds on
  the link (R 4.2.3 once per call, job 117897245682; R 4.6.1 twice, with the owner lookup, job
  117897245789). Fix (`4ac06da`): `path_info()`, used by `doc_sidecar_read()`, `path_dangling()`,
  `scrub_walk()`, `pcli_control_digest()` and `write_atomic()`.
- Red: the hosted 9170baf runs show the warnings the new `expect_no_warning()` assertions forbid; a
  macOS emulation reproduces them. Green: 5 neighbouring files FAIL 0 WARN 0 PASS 1873. Lint clean.
- Reviews: r1 findings applied with CI-61.
- Deviations: D-231. Open: on 92a2944 the Windows release check has WARN 0 (job 118001849245), but
  the new `test-utils-paths.R:324` fails on R 4.2.3 ("cannot coerce class '"octmode"' to a
  data.frame" in the emulated row; Windows oldrel-4 job 118001849423, ubuntu oldrel-4 job
  118001849303); fixed in the test by CI-67.

## Task CI-61 - A dangling link reads as absent in Windows readers and tools (2026-10-19, #51)
- On Windows `file.exists()` is TRUE for a dangling link and a later `file()` warns and fails, so the
  readers, the read, edit and grep tools, `ls`, the files checkpointer, `@file` mentions, the document
  arguments and cache, image checks and `dotenv_discover()` gave warnings, base errors or wrong answers.
  Fix (`3383843`): their metadata reads and guards use `path_info()` and give POSIX's answers; gptr's
  own stores keep base reads and the trust gate keeps `file.exists()`.
- Red: on 9170baf the Windows emulation of the new test's calls gives warnings, base errors and wrong
  answers. Green: the full offline suite FAIL 0 WARN 0 SKIP 62 PASS 34753 on macOS. Lint clean.
- Reviews: r1 5 findings applied; finding 5's patch-delete part rejected (`patch_key()` refuses the
  link earlier on both OSes).
- Deviations: D-231. Open: passed in R-CMD-check run 39235008757 (92a2944, Windows release and
  oldrel-4); the other `file.exists()` guards are not audited.

## Task CI-62 - The mock server accepts every pending connection before reading requests (2026-10-19, #51)
- INFRA-01's six-stream wall failed in about 3% of hosted Windows jobs (11 of 338) while gptr
  delivered every end within 16 ms; 7 of the 9 failures under D-063 show heads at 0, D, D per mock
  (D = 0.11-0.63 s; job 117897245682: wall 2.594 s against 2.475 s). Most likely cause (inferred):
  the mock read requests in the same iteration as a `socketAccept()`, which blocks on
  `gethostbyaddr()`. Fix (tests only, `92a2944`): the mock reads only when no connection waits; the
  failure message prints each head's delay after its read; bound and latency check unchanged.
- Red: 0.3 s after every accept reproduces the shape with the old loop (FAIL). Green: the new loop
  PASS; http-reactor FAIL 0 PASS 225, 16 other mock-server files PASS 4376. Lint clean.
- Reviews: r1 5 findings; 1, 3, 5 applied, 2 reworded (cause inferred), 4 open.
- Deviations: none. Open: e288902 (job 114359166815) and ee5088a (job 114920821918) show a separate
  stall after the read; a late client gives the same shape; proving the fix needs about 50 Windows
  runs of the test.

## Task CI-63 - The suite home is a Windows profile, so system Chrome serves DevTools (2026-10-19, #51)
- R-CMD-check `windows-latest` release and oldrel-4 on 2c9b6a4 skipped both `test-artifact-app.R`
  session checks: system Google Chrome 155 wrote "DevTools remote debugging requires a non-default
  data directory" (jobs 117897245682, 117897245789) although gptr passes its own `--user-data-dir`.
  Branded Chrome serves DevTools only when `IsUsingDefaultDataDirectory()` is false and takes "cannot
  tell" for default; the unknown came from `SHGetFolderPath(CSIDL_LOCAL_APPDATA)`, whose registry value
  `%USERPROFILE%\AppData\Local` named a missing folder under the suite's empty home (Chromium sources;
  outside support: the Stack Overflow 50666524 answer). Chrome for Testing has no such gate, and real
  users keep their profile. Fix (tests only, `6bae056`): `setup.R` creates `APPDATA` and
  `LOCALAPPDATA` as `home/AppData/Roaming` and `home/AppData/Local`; the new case "the suite home is a
  Windows profile whose Local AppData the browser child resolves" pins the layout and, on Windows
  (NOT_CRAN), asks Windows PowerShell 5.1 for `GetFolderPath('LocalApplicationData')` in
  `child_env("artifact")`.
- Red: the new case fails before the change on macOS (folders missing, outside the home). Green: it
  passes, also its Windows branch with `/bin/sh` standing for PowerShell; `artifact-app` and
  `test-environment` with real Chrome FAIL 0 WARN 0 SKIP 2 PASS 524, both session checks ran; full
  suite FAIL 0 WARN 0 SKIP 63 PASS 34773. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: R-CMD-check Windows release and oldrel-4 on 85e5883 (jobs 118053097431,
  118053097175) and 74de8c6 (jobs 118076803835, 118076804097) list no `test-artifact-app.R` skip, so
  both session checks ran with system Google Chrome, and the new case passed. The two ordinary by-file
  runs on 74de8c6 (39255516069, 39255537264) skipped the first session check (`test-artifact-app.R:511`,
  `skip_if_browser_failed()`; the runner prints no skip reason); the run on 85e5883 (39250571244) ran
  both. Repeat pending on the final head.

## Task CI-64 - The owned Chrome's close waits for its unmarked helpers (2026-10-19, #51)
- Hosted ubuntu R-CMD-check failed the first real session check's cleanup (`test-artifact-app.R:488`)
  with "The private headless browser directory did not finish cleanup: unlink returned 1." (oldrel-4
  on 9170baf, job 117943690034; oldrel-1 on 33720c1; oldrel-4 on 945fa60 before the stage
  diagnostics): 3 of about 330 ubuntu jobs since Oct 13, none on macOS or Windows. `release()` judged
  the family by the `GPTR_PROC` marker alone, which Chrome's helpers never show: on Linux their
  `setproctitle()` zeroes the block `/proc/<pid>/environ` reads, and on macOS ps reads no Chrome
  environment. So the profile was unlinked while orphaned helpers (the network service above all)
  still wrote in it. Fix (`a7b1793`): `owner$close()` records the browser's descendants by parent link
  before SIGTERM through `proc_children()`, which `kill_all()` now shares; `release(seconds)` waits for
  them with `proc_wait_exit()` within the remaining 10 s `artifact_browser_close()` deadline, and a
  helper still running or unknown raises "The owned headless browser family did not finish cleanup."
  and keeps the directory for a retry. The startup unwind and the retained cleanup job keep the single
  check.
- Red: the new test "artifact browser close waits for its unmarked helpers before removing the
  profile" fails on 92a2944 with the hosted message. Green: it passes, and a helper alive past the
  deadline keeps the root until a retry succeeds; in an offline Ubuntu container with Chromium 145 an
  immediate unlink failed 3 of 40 rounds and a wait for the recorded family first removed all 40
  (settled within 0.023 s); with real Chrome on macOS `release()` waits 0.06-0.08 s for 9 helpers;
  full offline suite FAIL 0 SKIP 62 PASS 34794. Lint clean.
- Reviews: none recorded.
- Deviations: D-233 (amended). Open: not seen in the ubuntu R-CMD-check rows on 85e5883 and 74de8c6,
  which at about 1% per job proves little; after a browser that died before `close()` no helper can be
  recorded, so `release()` has the marker check alone, as before; `proc_wait_exit()` polls every 20 ms,
  so the wait can end one poll past the close deadline, which then reports "close timed out".

## Task CI-65 - A job's status is read before its bytes; its tests release through a file (2026-10-19, #51)
- `test-bridge-sh.R:445` and `:449` failed in the filtered windows-by-file run on 9170baf (run
  39217182105, job 117943670939) with `(no output) [j... done, 1s]`. Cause (test timing): there
  `bridge_bg()` takes 0.66 to 1.19 s to return, mostly after the spawn, which used up the child's
  `Sys.sleep(1)`; the first wait settled after the child had written DONE, so `wait(until = "ready")`
  rightly returned both lines and the next wait had none. Passing runs had about 60 ms to spare, and
  the partial-line test passed without exercising its rule. Fix (tests, `1f5359e`): each child blocks
  after its first output until the test creates the file `go` (its path an argument); the 20 s
  timeouts and the assertions are unchanged, and the partial-line test adds a 1 s wait that must
  return no line while only `rea` is written.
- Product (`adfef78`, a race on every OS, not the hosted cause): `bridge_job_read()` took the status
  after the bytes, so a child that exited in between gave a `done` footer while its partial last line
  was unread. The status now comes first and decides whether a partial line waits; the snapshot read
  (`file.size() - pos`, one `readBin()`) is unchanged.
- Red: 92a2944 with the new test "a job that exits during a read reads running, so a done read holds
  all output" FAIL 1 (footer `done`); with `bridge_emit()` slowed by 1.5 s the old tests fail `:445`
  and `:449` as hosted. Green: `^bridge-sh$` PASS 286 SKIP 2 (4 runs); the new tests pass with
  `bridge_emit()` slowed by 0, 0.9, 1.5 and 3 s; NOT_CRAN=false PASS 144 SKIP 27. Lint clean. Mutants:
  a `settled()` that matches partial lines fails the new partial-line test (`:467`); a read that
  returns partial lines fails `:465`.
- Reviews: r1 6 findings: the handshake (1) and the partial-line handshake (6) applied; the read-to-EOF
  loop and the unproven stale Windows `file.size()` claim reverted (2, 5: the hosted logs show the size
  was current); the `file.size` mock dropped (3); the status-first reorder kept (4).
- Deviations: none. Open: `test-bridge-sh.R` passed in the ordinary by-file runs on 85e5883
  (39250571244) and 74de8c6 (39255516069, 39255537264) and in R-CMD-check Windows release and oldrel-4
  on both; repeat pending on the final head.

## Task CI-66 - PowerShell runs the program cmd would run and returns the last status (2026-10-19, #51)
- On hosted Windows the PowerShell route of `peter$sh()` returned 0 for `cmd /c exit 4` (CI-50). The
  diagnostic run 39234534171 (job 118000300246, branch `claude/diag-ps-exit`, since deleted) printed
  `(Get-Command cmd).Source` = `C:\rtools45/usr/bin\cmd` (pwsh 7.6.6), while `cmd.exe`,
  `& $env:ComSpec` and `Start-Process` each gave 4. PowerShell's `CommandPathSearch` takes the PATH
  directories in order and ranks the bare name last only within each, so MSYS2's extensionless
  `usr/bin/cmd` script, which R CMD's `Rcmd_environ` puts first on PATH, shadows `cmd.exe`;
  `IsExecutable` is false for it, so PowerShell opens it with ShellExecute in the background, does not
  wait and sets no `$LASTEXITCODE`.
- Fix (`shell_ps_encode()`, `R/proc-spawn.R`): `b4df19c` sets a `PostCommandLookupAction` that replaces
  a lookup resolved to an extensionless Application with the first Application of that name with an
  extension (`Get-Command -CommandType Application -All`, PowerShell's PATH order); `bd8e30b` makes the
  postfix `if ($?) { exit 0 }; if ($LASTEXITCODE) { exit $LASTEXITCODE }; exit 1`, so a last command
  that succeeded wins over an earlier native failure; `c65f11e` sets the hook only when
  `$IsWindows -ne $false` (pwsh on Windows and Windows PowerShell 5.1); `3596af1` makes a name that
  only an extensionless file provides not found ("not recognized", status 1), as in cmd. The same
  encoder serves the knit powershell engine and the stdin ACL verifier (bootstrap 9133 and 9117 bytes
  on macOS, limit 9998). `3942e0b` (tests) runs the shadowed line under Windows PowerShell 5.1 too.
- Red: hosted status 0 where 4 was expected. The Windows test now prepends a temporary directory with
  an extensionless `cmd` to PATH, which reproduces the shadow on any runner, and asserts status 4 (pwsh
  and 5.1), status 6 and stdout `6\n` for this R after `cmd /d /c exit 5`, 0 for `cmd /c exit 4;
  Write-Output ok`, 1 for `cmd /c exit 0; Write-Error no`, and stdout `ok\n` with status 1 for an
  extensionless-only `gptr-none`. Green: on macOS `proc-spawn`, `bridge-sh`, `bridge-lang` and
  `proc-writer-runtime` PASS 1293 SKIP 14 (Windows-only). Lint clean.
- Reviews: r1 5 findings: (medium) green unproven -> the hosted runs below; (low) the 5.1 route never
  ran -> `3942e0b`; (low) the hook searched PATH on every native lookup under Unix pwsh -> `c65f11e`;
  (low) plan, spec and DEVIATIONS out of sync -> D-235 and the 03 and 04 rows; (low) a silent 0 for an
  extensionless-only name -> `3596af1`.
- Deviations: D-235. Open: the Windows test passed on 85e5883 (R-CMD-check jobs 118053097431 and
  118053097175, whose failure is CI-70; by-file run 39250571244) and on 74de8c6 (jobs 118076803835,
  118076804097; by-file runs 39255516069, 39255537264); no test runs the hook's Unix branch; a name
  with a non-PATHEXT extension is still opened with ShellExecute (a document with a file association,
  kept on purpose).

## Task CI-67 - path_info()'s dangling-link test runs on R 4.2 and ignores atime (2026-10-19, #51)
- On 92a2944 R 4.2.3 (Windows oldrel-4 job 118001849423, ubuntu oldrel-4 job 118001849303) errored
  at `test-utils-paths.R:324` in the Windows `file.info()` mock: R 4.2's `data.frame()` cannot coerce
  an octmode column. On macOS the comparison of a regular file's row with a second `file.info()` failed
  once on atime, which reading the file between the calls may update. Fix (tests only, `95199d2`): the
  mock adds the mode column after construction; atime leaves that one comparison.
- Red: the hosted R 4.2.3 error; the macOS atime failure once. Green: `test-utils-paths.R` passed on
  R 4.2.3 in R-CMD-check on 85e5883 (ubuntu oldrel-4 job 118053097194; Windows oldrel-4 job
  118053097175, whose failure is CI-70) and 74de8c6 (jobs 118076804031, 118076804097). No local run
  or lint is recorded in the commit.
- Reviews: none recorded.
- Deviations: none. Open: none beyond the repeat on the final head.

## Task CI-68 - A dangling link is a readlink target on POSIX, a listed entry on Windows (2026-10-19, #51)
- Since CI-48 `path_dangling()` asked for no followed metadata and a directory entry whose name matched
  with case folded, on every OS. On a case-sensitive file system (Linux) a missing name beside a
  sibling that differs only in case was therefore a dangling link: `wire_log_path()` refused a valid
  `gptr.wire_log` inside `tempdir()` with the "must be inside the workspace root or tempdir()" notice,
  and `scrub_lock()` refused a missing `locks/` beside `Locks/`; origin/main (a readlink target and no
  file) accepted both. Found by the whole-diff review. Fix (`dba9c78`): POSIX takes no followed
  metadata and a readlink target (`path_is_link()`), Windows keeps `path_listed()` (names folded as
  NTFS does); `resolve_link_target()` drops its own POSIX rule and asks `path_dangling()` and
  `path_is_link()` on every OS, with unchanged results. `089bc9a` (tests): `local_dangling_link()` in
  `helper-files.R` builds the fixture that `test-doc-io.R` and `test-utils-paths.R` each copied.
- Red: with TMPDIR on a case-sensitive APFS image, 74de8c6's `R/` fails the new case "a case variant
  is a dangling link only where file names ignore case" at `test-utils-paths.R:332` and `:333`; a
  base-R replica of its assertions and of `wire_log_path()`, `resolve_link_target()` and
  `scrub_lock()`'s guard in rocker/r-ver:4.5.0 (`--network none`) fails 5 checks. Green: the replica
  passes all 12; on the case-sensitive image 6 files FAIL 0 PASS 1767; on macOS
  `^(utils-paths|tool-write|http-reactor|windows-security)$` PASS 444 and
  `^(auth-redact|tool-edit|doc-io|tool-read|tool-search|storage-boundaries)$` PASS 1809, the skips
  Windows-only. Lint clean.
- Reviews: whole-diff review: `path_listed()` folds case on every OS (medium, low) and a second copy
  of the fixture (low) -> these commits. r1 3 findings: the D-231 and P27 text (applied); the
  case-sensitive testthat evidence (above); `doc_sidecar_exists()` kept, since folding it into
  `path_dangling()` would drop a fail-closed POSIX case (#47).
- Deviations: D-231 (corrected). Open: on d9a7840 (run 39274424747, both attempts) the case passed in
  R-CMD-check `windows-latest (release)`, the Windows branch (a junction `Link` looked up as `link`),
  and in the ubuntu rows other than oldrel-4 (CI-71), the case-sensitive branch; repeat pending on
  the final head.

## Task CI-69 - A child's descendants are read from ps's own handle of its pid (2026-10-19, #51)
- On 92a2944 `ubuntu-latest (release, LC_ALL=C)` (job 118001849130) found 1 of the 2 background
  sleeps at `test-bridge-sh.R:512` (CI-47). `85e5883` (tests) looked again for up to 10 s until ps
  listed both; it passed on 85e5883 (job 118053097216), but on 74de8c6 `ubuntu-latest (release, no
  Suggests)` (run 39255504135, job 118076803865) failed `test-bridge-sh.R:569` with 0 of 2 for the
  whole 10 s. Cause: on Linux processx 3.9.0 stamps a child from `CLOCK_REALTIME - CLOCK_MONOTONIC`
  read at the spawn, ps 1.9.3 times every process from the boot time it read once, and
  `ps_children()` keeps a descendant only when the parent's stamp is not later than its creation time;
  a shell forks its background jobs in its first 10 ms tick, so whenever processx's estimate was the
  larger, `ps_children(p$as_ps_handle())` listed none of them, at every look. `kill_all()`'s
  parent-link record (`proc_children()`) used the same lookup. Fix (`d480ee5`): `proc_children()`
  lists from `ps::ps_handle(pid)` and keeps the list only while processx still reads the child alive
  (no pid reuse); the bridge tests read the tree with `proc_children()`; `85e5883`'s re-look is
  removed; the 5 s bound for `kill()` is unchanged.
- Red: a C emulation with the formulas of processx 3.9.0, ps 1.9.3 and `ps_children()`, 1000 runs of
  the test's line in debian bookworm (arm64, dash): processx's handle listed neither sleep in 187 runs
  (180 with LC_ALL=C; rocker/r-ver:4.5.0 under amd64 emulation 2 and 3 of 300). The new test
  "proc_children() follows parent links from ps's own handle while the parent lives" lists a child
  when processx's stamp of the parent reads later than the child (the old lookup lists nothing) and
  nothing once the parent ended. Green: ps's own handle listed both sleeps in every emulated run; on
  macOS `bridge-sh` and `proc-supervise` pass, also with `_R_CHECK_PACKAGE_NAME_=gptr` and LC_ALL=C,
  and the `proc-*`, `subagent-*`, `cli-*` and `bridge-*` files and their neighbours pass. Lint clean.
- Reviews: none recorded.
- Deviations: D-233 (amended). Open: on d9a7840 (run 39274424747) `test-bridge-sh.R` passed in the
  ubuntu R-CMD-check rows other than oldrel-4 (CI-71) on both attempts, `release, no Suggests` and
  `release, LC_ALL=C` among them; the old lookup missed only in some runs, so this pair alone does
  not prove the fix. Other `ps_children()` callers are unchanged: the backpressure and
  marker-family helpers already use `ps::ps_handle(pid)`, and the windows-startup probe's processx
  handle carries one OS timestamp on Windows.

## Task CI-70 - The sampler retries transient observer failures for one snapshot deadline (2026-10-19, #51)
- R-CMD-check `windows-latest (oldrel-4)` on 85e5883 (run 39250578309, job 118053097175) failed
  "owned writer prototype preserves every 4 MB duplex stdout and stderr line" (native-07,
  `test-proc-writer-prototype.R:6`) as `resource_observation`: the first snapshot raised
  `observer-metadata-invalid` at `entry-metadata` (a delete-pending Windows file, CPython `st_ino` 0),
  and CI-23's one immediate retry met the same file (`elapsed_s` 0, `observer_retries` 1) while the
  writer met every bound (13 samples, peak disk 4,049,354 B). A file stays delete-pending while any
  handle (an antivirus or indexer scan) is open, which can span two back-to-back snapshots. Fix (tests
  only, `404b90a`): `bp_observe()` retries the same five reasons every 100 ms until the observer's own
  1 s snapshot deadline has passed since the first failure (about ten retries); any other reason, and
  a transient that outlasts the deadline, stay one fatal sampling error with the last snapshot's
  condition. `observer_retries` counts every retry and the first reason is kept. The observer, the
  caps and the 1 s, 30 s and 45/60 s deadlines are unchanged; a sample can take about 1 s longer,
  inside the 15 s the 60 s lease reserves.
- Red: `^proc-backpressure-sampling$` FAIL 12 with the old helper. The CI-23 unit test is renamed to
  "backpressure observation retries fixed transient observer reasons for one deadline" and covers
  transients that clear, a bound reason after two retries and a persisting transient (it stops after
  at least 1 s, after 2 to 19 retries); the `bp_run()` case completes after three retries and fails for
  a bound reason and for a persisting transient. Green:
  `^(proc-backpressure-sampling|bp-declared-observer|bp-disk-observer)$` PASS 669 SKIP 5; with Python
  3.15 and the real observer the writer and observer files PASS 841, all four writer cases with
  `observer_retries` 0; `^(proc-|bp-)` PASS 2317 SKIP 16; `bp_observe()` in rocker/r-ver:4.5.0 stops
  a persisting transient after 10 retries at 1.09 s. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: native-07 passed on 74de8c6 with the one retry. On d9a7840 (run
  39274424747) the 1 s did not cover native-01's entry on oldrel-4: attempt 2 (job 118200832757)
  raised `observer-metadata-invalid` after 8 retries, so CI-73 charges an exactly delete-pending file
  as a file; attempt 1 had failed native-08 earlier, at the observer's construction (CI-72).

## Task CI-71 - Two tests abort a hanging fake request only once the provider has read it (2026-10-19, #51)
- Both attempts of R-CMD-check `ubuntu-latest (oldrel-4)` on d9a7840 (run 39274424747, jobs
  118134892383 and 118200833216) hit the 45-minute job timeout. In both hung logs all 21 backpressure
  witnesses name one worker as `parent_pid` (9900 in attempt 1, 10038 in attempt 2), the later files'
  output arrives contiguous and in file order, and `> test-agent-run.R: [gptr] aborted`, which the
  test at line 1135 prints, is missing; the passing oldrel-4 logs (85e5883, 74de8c6, d62eb7f) split
  the witnesses 4/15, 11/8 and 4/13 and print it. A callr worker on testthat's pipes delivers a
  flushed `cat()` line while it blocks, so the other worker (9902 in attempt 1, 10040 in attempt 2,
  each job's only orphan, with no child process) held `test-agent-run.R` and stopped before line
  1135, where only "run_start(s, NULL) continues from the leaf after an abort" waits without a bound
  after a hang reply.
- Cause (a test race since 9cfb00d, c610e38 for the fork test): that test and "a fork of a source
  still in its first turn freezes its own prompt" (`test-session-store.R`) script the fake provider
  as `list(list(hang = TRUE), <answer>)`, pump for a fixed 0.2 s, abort, then wait for a second
  request without a bound. The provider numbers a request at its first stream poll, one pump
  iteration after the request begins (`reactor_run_tasks()` runs only the tasks that existed when it
  started); a first iteration of 0.2 s or more leaves the aborted request without a reply, so the
  second request takes reply 1, the hang. Fix (tests only, `a41cfb8`): both tests pump until the run
  streams, bounded by the 30 s that the file's other aborts of an in-flight request use; no product
  code, bound or assertion changed.
- Red: with a `before_request` hook that sleeps 0.3 s, the d9a7840 versions of both tests ran until
  killed after 60 s. Green: the new versions pass in 3 s; `test-agent-run.R` (661) and
  `test-session-store.R` (273) pass; the installed package's suite under `test_check()` with
  `TESTTHAT_PARALLEL=true`, 2 workers and the aaa-state install test active: 34744 ok, 0 failed.
  Lint clean.
- Reviews: r1 3 findings: the trigger wording (medium) -> reworded with the runner and collection
  evidence below; the localisation (low) -> built on the `parent_pid` split and the missing notice,
  pids labelled by attempt, the one-baseline minute estimate dropped; a `stopifnot()` on the pump's
  result (low) not applied, as the reviewer recommended.
- Deviations: none. Open: why the race lost on both attempts on d9a7840 is not established. None of
  the 16 earlier parallel oldrel-4 jobs since b612001 hung, and runner speed does not separate the
  runs (attempt 1 on a centralus runner as fast as 85e5883's, attempt 2 on an eastus runner as slow
  as the passing westus3 runs); a full collection of the 190 MB heap (0.11 s on an Apple performance
  core, 0.48 s on an efficiency core) in the first iteration, or a stall from the other worker's
  processes, would lose it, but neither is shown. Fixed only once `ubuntu-latest (oldrel-4)` passes
  on hosted CI; should it hang again, a per-file timing reporter would name the stuck test. Neither
  pump checks its result, so a 30 s stall without a first poll would still end in the unbounded wait.

## Task CI-72 - The sampler retries an observer construction that meets its initial deadline (2026-10-19, #51)
- R-CMD-check `windows-latest (oldrel-4)` on d9a7840 (run 39274424747, attempt 1, job 118134892183)
  failed native-08 "idle Windows writer retirement preserves target stdin and later FIFO EOF"
  (`test-proc-writer-retirement.R:487`) while constructing the observer: `DiskObserver.__init__`
  raised `observer-initial-entry-or-time-limit`. `windows-latest (release)` on 40c463a (job
  116949579452) had failed native-04's first case, duplex, the same way.
- Cause: that one reason covered both limits on the constructor's walk of the lexical parent chain
  from the volume root. The entry limit cannot fire with the defaults (one entry per path component,
  at most 32, above which `observer-parent-chain-invalid` is raised, against 4096), so the walk
  outlasted its 1 s deadline. Both failures were the first construction in a fresh native process:
  the retained hosted witnesses show 1.06 to 1.97 s of R-side initialization (Python start-up
  included) for first constructions and 0.01 to 0.50 s for later ones, and in job 116949579452 the
  next two constructions in the failed process took 0.09 and 0.05 s and completed.
- Fix (tests only, `6ad7a95`): the observer raises `observer-initial-entry-limit` and
  `observer-initial-deadline` at the same points with the same limits. `bp_run()` constructs through
  `bp_observe()`, which adds `observer-initial-deadline` to its transient reasons and retries it
  every 100 ms until 1 s has passed since the first failure, as for the snapshot deadline (CI-70);
  the entry limit, every other reason and a deadline that lasts past 1 s stay fatal with the last
  condition. `tracked` and `observer_retried` are defined before construction, so `observer_retries`
  counts construction retries and `observer_retry_reason` keeps the first reason. The observer
  limits, the 45 s initialization bound, the 1 GB RSS cap and the 30 s and 60 s deadlines are
  unchanged.
- Red: the new Python controls fail 2 of 46 on the old observer; `^proc-backpressure-sampling$` with
  the old helper and observer FAIL 10 plus one error at the construction retry. Green:
  `run-controls.py` passes 46 cases (pins updated);
  `^(proc-backpressure-sampling|bp-declared-observer|bp-disk-observer)$` PASS 686 SKIP 5; with Python
  3.15 and the real observer in a clean TMPDIR the writer, backpressure and observer files PASS 1112
  SKIP 1, all 7 real cases with `observer_retries` 0; an observer copy whose first construction's
  clock jumps 1 s gives a real `observer-initial-deadline` that `bp_observe()` retries once, and one
  that is always slow raises after 9 retries at 1.03 s; `^(proc-|bp-)` PASS 2336 SKIP 16; the dev/ci
  tests that source the helper pass; in rocker/r-ver:4.5.0 (`--network none`) `bp_observe()` stops
  a persisting initial deadline after 10 retries at 1.07 s. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: not yet run on hosted Windows; a retried construction shows
  `observer_retry_reason` "observer-initial-deadline" in its witness. The cold cost inside the first
  construction's 1 s is inferred (a loaded runner or a first-call cost): the witness records only the
  R-side `initialization_elapsed`. `test-bp-disk-observer.R` constructs directly, without the retry,
  as it already snapshots without one; the frozen windows-token packets keep the combined reason.
  Locally the real observer needs a TMPDIR outside macOS's default (104,171 entries), where
  snapshots meet their 1 s deadline at d9a7840 too.

## Task CI-73 - The observer charges an exactly delete-pending Windows file as a file (2026-10-19, #51)
- R-CMD-check `windows-latest (oldrel-4)` on d9a7840 (run 39274424747, attempt 2, job 118200832757)
  failed native-01 "native GPTR Python startup preserves R state and uses its private numerical
  runtime" as `resource_observation` in phase `independent-python-cli`: `observer-metadata-invalid`
  at `entry-metadata` (entries 60, directories 5, max_depth 4, bytes 0) after 8 retries, with peak
  disk 30,148 B and RSS within the caps. An entry's lstat gave `st_ino` 0 for longer than CI-70's
  1 s retry, which had replaced CI-23's single retry.
- Cause (inferred, not observed): CPython's Windows lstat falls back to the directory listing, which
  has no file id, when its attribute open fails with `ERROR_ACCESS_DENIED`, and the observer's
  identity checks made `st_ino` 0 fatal. In this owned tree the listable parent grants attribute
  reads, which leaves a classic pending deletion as the likely cause: the file stays listed but
  unopenable until its last handle (an antivirus scan, say) closes, and Win32 maps that state and a
  real denial to the same error. A process marker or `write_atomic` temporary in
  `cache/R/gptr/procs` fits the witness (four directories deep, no bytes charged), but so would a
  pending `.stdin` mailbox directory, since the witness does not record the entry's kind; the
  deleter is not identified (R's `unlink()` calls `DeleteFileW`, which recent Windows builds may run
  with POSIX semantics that unlist the name at once).
- Fix (tests only, `1b472c2`): after the native attributes, listed metadata and kind checks pass,
  the observer asks, only for `st_ino` 0 on a non-reparse regular file, whether
  `NtQueryAttributesFile` on the same literal path (attributes only, no link followed) returns
  exactly `STATUS_DELETE_PENDING` (0xC0000056) (`_windows_delete_pending()`). Such an entry stays
  kind `file`: it is charged its listed size like any file (so not in `declared_only` mode) under the
  unchanged byte, entry and deadline checks, and is never opened, followed or identity-compared. Any
  other status, an `st_ino`-0 directory or link, a declared entry, another host, or fake operations
  without the `delete_pending` hook still raise `observer-metadata-invalid` (or
  `declared-entry-not-link`), which R retries for 1 s as before (CI-70). An `st_ino`-0 entry that
  also fails one of the earlier checks now reports that reason, which is not retried; a real lstat
  cannot reach that, and the outcome is stricter. The bounds, `bp_observe()` and its transient
  reasons and the frozen windows-token packets are unchanged. Retrying in `bp_observe()` for the rest
  of the case deadline was rejected: it would leave RSS unsampled for up to about 29 s.
- `406befb` (tests): "the optional observer charges a real Windows delete-pending file until it
  closes" in `test-bp-disk-observer.R`, which R-CMD-check runs on Windows with the provisioned
  Python, opens a 180-byte file through ctypes with DELETE access and every share mode, sets the
  classic `FileDispositionInfo` and keeps that last handle open. One comparison requires that an
  ordinary file and an absent path are not pending; the file stays listed, lstat gives it `st_ino` 0
  (not the ordinary file) and `_windows_delete_pending()` says yes; three snapshots charge 187 B
  (7 + 180) with nothing disappeared; and once the handle closes the name is gone within 10 s, the
  check says no and a snapshot charges 7 B. It skips off Windows, so the Optional-integrations
  registry makes it `test-bp-disk-observer.R`'s one platform guard (an allowed skip off Windows
  only).
- Red: the new Python controls against the 6ad7a95 observer: failures 4, errors 5 (all five new
  tests red). Green: `run-controls.py` passes 51 cases (46 -> 51, pins updated) on Python 3.12 and
  3.15; 100 queries add 2 entries to ctypes' pointer type cache (200 before);
  `^(proc-backpressure-sampling|bp-declared-observer|bp-disk-observer)$` PASS 686 SKIP 6 without
  Python and PASS 766 SKIP 1 with the real observer; `^(proc-|bp-)` PASS 2416 SKIP 12; on macOS the
  new case's Python, through reticulate on Python 3.12 with fake kernel32, observer and check,
  returns the expected list, and the case skips; `dev/ci/test-optional-integrations.R` passes 3823.
  Lint clean.
- Reviews: R1 and R2: a real delete-pending control (R1-1, R2-1) -> `406befb`; the separate
  `pending` kind dropped, so the entry stays a `file` (R1-3, R2-3); the query types built once
  (R1-4); a recurrence no longer said to prove another status (R2-2); the scope kept to regular files
  (R1-2); the reason precedence kept and explained in the commit (R2-4, received truncated).
- Deviations: none. Open: hosted Windows has not run either commit. The new case is the first real
  test of the two facts the fix rests on (CPython 3.12's lstat gives `st_ino` 0, the query gives
  0xC0000056); its failure output shows which does not hold. Even if it passes, native-01's entry is
  unidentified: a pending directory (still fatal by design, such as a `.stdin` mailbox removed by
  `unlink(recursive = TRUE)`), another status, or a deletion that completes between lstat and the
  query (retried) all give that reason, and one green run cannot tell a fix from a race that did not
  recur, so judge native-01 over several runs. No claim about the native-06 and native-07 failures
  (CI-23, CI-70).

## Task CI-74 - A new-session preview syncs skills; the token benchmark pins the catalog (2026-10-20)
- Cause: skills are discovered by `skill_sync()` in builtin:skills' `session_start` hook, which fires at a session's
  first run. `gptr_prompt()` composes without that event, so in a fresh R session its preview had no `skills`
  section, unlike the prompt the first run freezes; the IC-68 test in test-northstar.R passed only because an
  earlier block had run a session. `bench_case()` also freezes without `session_start`, so the token baseline
  measured no skills catalog either.
- Fix: `skills_section_text()` syncs the skills of a top-level session before listing them (idempotent; a real
  first run's frozen T0 and T1 are byte-identical before and after). The benchmark pins the `skills` stand-in (the
  built-in catalog, the same text a fresh session lists) for the fixtures that name it, like `r_env` (CI-18), so
  the developer's own skill folders never enter the prefix.
- Red: test-skill-discover.R's preview test FAIL 2. Green: `skill-|northstar|prompt-|subagent-|arch-layers` PASS;
  in CRAN mode `northstar|skill-discover` PASS 106. New `test-token-gates.R` test (a machine skill leaves ns02's
  prefix unchanged) fails without the pin.
- Baseline (`run.R --update`): the 12 standard cases' prefix and catalog +143 (catalog 399 -> 542, the value
  recorded before the drift noted in D-135 item 6), input totals +143 per request; the two minimal cases unchanged.
  `run.R --check` OK; polyglot within 10%; `dev/bench/tests` PASS.

## Task CI-75 - The Windows stdin writer reads a refused chunk again (2026-10-21, #61)
- In the 123 hosted Windows jobs since `2654a21` that ran native-04 (R-CMD-check and Windows-check
  shard 1), its first case, duplex (`test-proc-windows-backpressure.R:3`), failed twice with the
  same witness (run 38874952436, job 116887641964, release, `3a8315f`; run 39532643181, job
  119001917749, oldrel-4, `1b0d3bd`): an io error at stage `delivery`, "Could not deliver queued
  bytes through the stdin writer.", with `accepted_bytes` 3604480 and 3080192, exact multiples of
  64 KB. Every failing writer step quit with status 1 and the drain replaced the inner cause, so the
  witness could not name the check. `3a05693` names it: each writer step exits with status 10 plus
  its index in `proc_writer_steps`, the writer turns warnings into errors, each parent-side publish
  and acknowledgement check has its own fixed message, and the stdin failure condition and the
  backpressure witness gain the writer's step, status, cause and, for the steps that take the
  chunk, the published chunk's size (D-241 item 2).
- `claude/native04-loop` (never merged) repeated the duplex case on hosted Windows, R 4.6.1 and
  R 4.2.3, in runs 39560105451 (300 iterations, before taking a chunk was split into size, read and
  length) and 39565526323 (600): 896 complete, 4 failed, 2 per R version. Every failure is stage
  `delivery`, step `read` (status 19), after 42, 30, 58 and 43 full chunks (`accepted_bytes`
  2752512, 1966080, 3801088 and 2818048). In the second run that step is
  `readBin(path, "raw", n = 65537L)` alone, after `file.size()` had admitted the chunk, and
  `writer_chunk_bytes` is 65536: the parent measured the chunk file `in-<index>` at its full size
  after the writer exited (only the writer deletes it). `observer_retries` and `sampling_errors`
  were 0 and no deadline fired; the unlink, create, rename, validation and alive steps never failed.
- Cause (inferred, not observed): `readBin()` of a chunk that the size step had admitted, and that
  the parent measured at 65536 bytes after the writer exited, failed. The witness keeps no OS reason
  (`cause` is the parent's "The owned stdin writer exited before delivery settled."). A transient
  open refusal fits this, but whether a re-read succeeds is untested until `claude/native04-loop`
  runs on the fix. The writer treated the failure as fatal.
- Fix: `proc_writer_main()`'s read step muffles the `readBin()` warning and catches its error. A
  failed read sleeps 0.05 s and returns to the writer's poll for the same chunk, which checks that
  the parent and target still run (step `alive`, status 17), validates the mailbox for that chunk
  (`safe("read", ...)`, fail-closed, status 18) and takes the size again, so `length` compares the
  bytes with the size taken right before that read. No new bound: the parent's no-progress deadline
  (`gptr.stdin_timeout`) still ends a read that never succeeds as the typed `gptr_error_timeout`
  and stops the writer. Nothing else retries. `read` keeps its index, so every status is unchanged;
  it can no longer exit, so the parent records `writer_chunk_bytes` for a size or length step only.
  The warning is muffled, not turned into an error: under `warn = 2`, R 4.2's `file()` leaks the
  connection of a refused open whose warning became an error (R 4.3's connections.c cleans it up,
  PR#18491), so about 125 refusals would fill R's 128 connections and fail the next validation
  (status 18) before the deadline. Muffled, the open fails and `file()` destroys the connection
  before it raises "cannot open the connection". On R 4.6.1 (macOS) 1,500 refused opens through
  the muffled read leave the connection table unchanged; the R 4.2 leak is read from the 4.2 and
  4.3 branch sources, not run. The trusted bootstrap grows by 52 to 56 bytes at a fixed mailbox
  path (long path 9,429 to 9,485). The production witness, whose size follows the session tempdir
  and `.libPaths()`, measured 9,513 in four runs after the fix, 485 bytes under the 9,998-byte
  Rscript limit.
- Tests: the cold control in `test-proc-windows-backpressure.R` takes the expected `outcome`
  (complete, io or timeout). "a cold writer names a failed chunk read" becomes "a cold writer reads
  a refused chunk again and delivers every byte" (the second chunk's `readBin()` warns, then errors,
  once: the echoed lines are identical, the target exits 0 and stdin has no error) and "a chunk read
  that keeps failing ends at the delivery deadline" (`gptr_error_timeout` after 2 s while the writer
  runs, `writer_step` and `writer_status` NULL, `accepted_bytes` 65536). While the read keeps
  failing, "a refused chunk is not read again once the mailbox fails validation" (step
  validate_read, status 18) and "... once the parent or target is gone" (step alive, status 17)
  each fail one retry check, with `accepted_bytes` 65536; the injection's `refused` counter lives in
  the actor body, so the other injection sees it. The step tests for alive, validate_read, size,
  length, unlink, create and rename are unchanged. In `test-proc-writer-runtime.R` the chunk-size
  test takes size in place of read ("a writer failed in its size or length step reports that
  chunk's size").
- Red: on `3a05693` merged with main (`7e0238b`), `^proc-windows-backpressure$` FAIL 9 PASS 225:
  the refused-once test ends in the io failure with the transfer short, the other three as step
  read, status 19. A mutant that reads again without the poll's checks (an inner `repeat`) fails
  the two retry-check tests with the stdin timeout (FAIL 6 PASS 228). Green:
  `^proc-windows-backpressure$` PASS 234;
  `^(proc-windows-backpressure|proc-writer-runtime)$` PASS 934 SKIP 8;
  `^(proc-writer|proc-windows-backpressure|proc-spawn|http-reactor|proc-)` PASS 2653 SKIP 13
  (PASS 2622 SKIP 13 after the merge, before the fix); `^zzz$` PASS 145. Lint clean.
- Reviews: R1 and R2, applied here: the read's warning muffled, so a refused open leaks no
  connection on R 4.2 (R1-1, R2-1); a failed read returns to the writer's poll, so the liveness and
  mailbox checks run right before the next read (R1-3, R2-3); tests for those two checks after a
  refused read (R1-2); `read` dropped from the chunk-size steps (R1-4, R2-7); the cause marked
  inferred and "intact" replaced by the measured size (R2-2); the bootstrap growth measured at
  fixed paths (R2-4); the census cited by job (R2-5); the loop's header and body corrected and its
  summary given a class column (R2-6).
- Deviations: D-241. Open: hosted Windows has not run the fix; `claude/native04-loop`, rebased onto
  it, repeats the duplex case in 16 jobs (1,200 iterations). A refusal that outlasts the stdin
  deadline, or a chunk that vanishes after a failed read, now ends as the delivery
  `gptr_error_timeout` with no writer step; the loop summary's class column shows it. The follow-up
  card "stdin-writer delivery timeout" (a startup-time `gptr_error_timeout` with `accepted_bytes` 0
  under the 2 s budget) is a different class and stays open; INFRA-01 is unrelated.

## Task CI-76 - The parent-death witness waits until ps stops listing the killed parent (2026-10-21, #62)
- Windows-check.yaml `windows-latest (release, shard 1/4)` on c80b703 (PR #56; run 39552770163,
  attempt 1, job 119065497023, R 4.6.1) failed native-10 "a Windows worker exits within 10 s after
  its acknowledged parent dies (IC-60)" at `test-subagent-worker.R:715`:
  `parent_dead_before_cleanup` FALSE. Everything else in the witness passed: it completed in
  5.96 s, all 20 pre-kill checks held, the worker was gone 0.10 s after the kill and cleanup
  settled. It is 1 of 247 executions that reached that check since 2026-10-12 (release 1/145,
  oldrel-4 0/102), and attempt 2 on the same sha passed.
- Cause (inferred, not observed): `wpd_child_case()` kills the parent with `ps::ps_kill()`
  (`TerminateProcess()`, which returns before the process has exited), polls until the worker reads
  as gone, then reads the parent once. The worker's exit starts inside the parent's own exit: either
  the processx job object closes with the parent's handles or the worker reads EPIPE while they are
  torn down. So the worker can be gone while ps still lists the parent for a moment (as for CI-45),
  and that single read then gives alive.
- Fix (tests only): just before that read the helper calls `proc_wait_exit(list(parent_handle))`
  with its default bound and poll (2 s, 20 ms), the wait `kill_all()` makes after its signals
  (D-180 item 1, unchanged). `worker_exit_elapsed` is still measured before the wait, so the 10 s
  bound and every expectation stay as they were; a parent still listed after 2 s fails as before.
  No product code changed.
- Red: the new test "the Windows witness reads its killed parent once ps no longer lists it (IC-60)"
  runs on any OS. It evaluates the helper's own statements from `killed_at` through `parent_dead`
  with `proc_handle_alive()` mocked (each process reads as running once, then gone), `ps_kill()`
  stubbed and a virtual clock. On 221f4a8 it gives FAIL 1 (`parent_dead` FALSE). Green: it passes,
  and `^subagent-worker$` gives FAIL 0 SKIP 1 PASS 161 (the Windows witness skips on macOS). The
  block takes 42 ms in CRAN mode, so it starts with `skip_on_cran()` (D-240). Lint clean.
- Reviews: skeptic: the worker's death may also come from EPIPE as the parent's handles are torn
  down, so the cause is said to start inside the parent's exit rather than to be the job's kill.
- Deviations: none. Open: hosted Windows has not run the fix yet, and at about 0.4% per execution
  one green run proves nothing. The new test pins the order of the reads, not Windows' timing. A
  parent that ps lists for more than 2 s, or a `proc_handle_alive()` NA (an unrecognised ps error),
  still fails the check.

## Task CI-77 - The six-stream wall starts when the requests came, not at the heads (2026-10-21, #62)
- Windows-check.yaml `windows-latest (release, shard 3/4)` on c80b703 (PR #56; run 39552770163,
  attempt 1, job 119065496949, R 4.6.1) failed INFRA-01 "six streams of 1.00-2.25 s finish within
  10% of the slowest" (`test-http-reactor.R:674`) with a wall of 2.532 s against 2.475 s. The heads
  were at 0, 0.227, 0.228 | 0.007, 0.275, 0.276 s, written 0.107, 0.223, 0.005 | 0.112, 0.265,
  0.006 s after the mock read each request, and gptr delivered every end within 16 ms. Since
  2026-10-12 the test failed in 7 of 257 hosted Windows executions, 6 of them on timing (one was a
  ready.json open error), at about the same rate without and with CI-62's `92a2944` (4 of 174 and
  2 of 83 timing failures).
- Cause (inferred): the mock is single-threaded. It logged the second request of each mock and
  then took about 0.2 s before scheduling its head, while the third waited. The test measured the
  wall from the heads the mock wrote, so it charged the mock's own stall to gptr. What stalled is
  not known: GC in the mock is not ruled out on Windows (locally its log, plan and schedule take
  under 0.04 s with no GC time), and a forward wall-clock step between the read and the head write
  fits the same numbers just as well.
- Fix (tests only): the mock first polls its sockets without waiting and waits only when nothing is
  ready, stamping `srv$idle` as each wait ends. Each request record gains `came`: the end of the
  wait that saw the request or, if the request came while the mock was working, of the last wait
  before it. It is never later than the request's arrival plus the select's wake-up, and never after
  `time` (when the mock read it, unchanged); `mock_log()` returns it. `infra01_six()` (`:589-593` on
  c80b703, `:605-609` on 221f4a8) anchors each stream at its request's `came` instead of its head
  write: the wall runs from the first `came` to the latest `came` plus scheduled length plus gptr's
  delivery latency. So the mock's lateness in writing a head is netted out, like its lateness in
  writing a last piece, and a clock step after the requests came cancels out as well. The 2.475 s
  bound and the latency check are unchanged; the failure message now gives each request's offset and
  each head's delay after its request.
- The proposed diff stamped `time` itself. test-s1-client.R's IC-64 rate check reads `time` as a
  lower bound of when each request started, and on macOS with that diff a 0.2 s stall injected at
  request 60 failed the check in 3 of 3 runs (least margin -0.03 s, against +0.14 s with read
  stamps). So `came` is a field of its own, and `time` keeps its meaning for the other tests.
- Red: the new test "INFRA-01: a request that comes while the mock works is logged at its last wait"
  holds the mock in its first request's plan until a gate file exists while a second request comes,
  then sends a third once the mock has waited again: the second must be stamped before the release
  and the third after it. Run on its own, on 221f4a8 it gives FAIL 2 (`came` is not logged there),
  and reading `time`, the only stamp there, FAIL 1 (the second request 0.041 s after the release;
  3 of 3 runs). A mutant that takes `came` at the read gives FAIL 1 (0.028 s after the release) and
  one that never renews `srv$idle` after a wait FAIL 1 (the third stamped 0.76 s before the
  release), 5 of 5 runs each. Green: it passes 5 of 5; `^http-reactor$` FAIL 0 SKIP 2 PASS 231; the
  17 files that start the mock server FAIL 0 SKIP 3 PASS 4607. In the investigation, a 0.35 s and
  0.27 s stall injected before the first two heads failed the old measure (walls 2.527 and 2.537 s)
  and passed the new one (2.251 and 2.252 s), while late requests (2.535 and 2.526 s) and serialised
  streams (3.324 s) still failed. Stalls injected here (in the plan or after the schedule; 0.35 and
  0.27 s, or 0.2 s each) did not give the hosted shape: each mock read its three requests in one
  iteration, so the old measure passed too, and the new wall was 2.251 s in all four. Lint clean.
- Reviews: skeptic corrections, kept here. Line numbers had drifted (`infra01_six()` is at
  `:589-593` on c80b703). The stall exceeds the head spread that the bound allows
  (2.475 - 2.25 = 0.225 s) only for the long mock (0.265 s; the short mock's 0.223 s does not), and
  only the long streams set the wall. A wall-clock step is an equally possible cause, and the fix
  neutralises it too. GC is not ruled out on Windows. A client's lateness in sending a request
  inside a busy window is not counted, and the old measure hid it too. r1 4 findings, all applied: a
  mutant that never renews `srv$idle` passed the gate test, which now requires the third request
  (medium); the Open note below separates the runner pause from the late-head shape (low); `came`
  was called a strict lower bound of the arrival, which holds only inside a busy window (low); the
  measurement unit test still named its anchors `heads` (low).
- Deviations: none new. The new anchor amends the INFRA-01 measurement of D-016 item 1 and D-063
  item 2: the wall runs from the first request's `came`, not from the first head write, and each
  stream ends at its request's `came` plus its scheduled length plus gptr's latency. The bound is
  unchanged. Tests only, so the amendment is recorded here. Open: hosted Windows has not run the
  fix. Of the 6 timing failures, 5 have stream 1 of each mock starting at once and streams 2 and 3
  starting together 0.23 to 1.5 s later, with gptr's delivery within 16 ms (0.28 s once): heads
  written late after their requests, which the new anchor nets out (inferred). The sixth, job
  118506033270 (run 39386048610, wall 3.183 s), is a runner pause in which gptr delivered two long
  streams' ends 0.46 and 0.89 s late, and it still fails, by design. So about 1 in 256 executions
  may still fail, and the fix is judged by whether the late-head shape comes back over several
  shard 3/4 runs, not by the overall 2.3%. The wall still counts gptr sending a request late while
  the mock waits, and gptr's delivery; a request sent late while the mock is busy is stamped early,
  so that lateness is not counted.

## Task CI-78 - The sampler retries an observer walk that meets a directory being removed (2026-10-21, #61)
- The native-04 loop on CI-75 (run 39574684025, 16 jobs, 1,200 duplex iterations on hosted Windows,
  R 4.6.1 and R 4.2.3) had no delivery failure and one `resource_observation` (job 119137147326,
  `native04-loop-oldrel-4-1`, R 4.2.3, iteration 6): the transfer completed (phases spawn, ready,
  writing, complete; 20 samples), then a snapshot raised `observer-parent-enumeration-unavailable`
  at `directory-identity` (entries 378, directories 15, max_depth 4, disappeared 0, bytes 17724,
  0.016 s) with `observer_retries` 0, since `bp_observe()` did not retry that reason. R-CMD-check
  run 39505627064 (job 118913688321, #56, oldrel-4) had failed native-04's duplex case at the same
  phase as `observer-directory-unreadable` at `directory-enumeration` (entries 539, directories 17,
  max_depth 5).
- Cause (inferred; the witness keeps no Win32 code): on Windows the reason comes only from
  `_windows_entry()` (`bp-disk-observer.py:135`), when `FindFirstFileW` on `<dir>\<name>` fails with
  an error other than 2 or 3 (`:274` rewraps an `OSError`; `:289` is the POSIX branch).
  `directory-identity` is `direct()`, whose `_listed()` looks the directory up component by
  component from the volume root; each lookup opens the parent of the component it names, which the
  same call lstat'ed just before, so only a directory that holds a subdirectory is opened. Opening a
  directory whose deletion is pending fails with `STATUS_DELETE_PENDING`, which Win32 reports as
  `ERROR_ACCESS_DENIED` (5), the denial the note at `:85` describes; once the removal completes the
  lookup gives 3, which the walk treats as absence. In this tree the only removed directories that
  hold a subdirectory are the case process's session tempdir and the `gptr` in it
  (`tmp/Rtmp*/gptr/childenv`, `child_env()`'s empty startup files), which R deletes when that
  process exits after phase complete. The witness fits: the loop's final snapshots that still hold
  that tempdir show 15 directories, 421 to 434 entries and depth 4, so every directory had been
  entered and the walk was in its last stretch, under `tmp`, which sorts last; and bytes 17724
  charge every file but `result.rds` (such snapshots charge 17,712 to 17,725 bytes without it and
  17,904 to 17,918 with it), so the root listing preceded the case's last write and its exit fell
  inside this 16 ms snapshot. The writer's mailbox (`cache/R/gptr/procs/<marker>.stdin`, the depth-5
  directory of the last good snapshot) was already gone (max_depth 4) and holds no subdirectory, so
  its chunk and ack deletes and renames cannot raise this reason. `observer-directory-unreadable` is
  the same removal met by `names()`' `scandir()` of the directory itself after its identity check
  (denied while pending, absent after).
- Fix (tests only): `bp_observe()` adds `observer-parent-enumeration-unavailable` and
  `observer-directory-unreadable` to the reasons it retries every 100 ms until 1 s has passed since
  the first failure (CI-70); a fresh snapshot after the removal no longer lists the directory. A
  real denial outlasts the 1 s and stays one fatal sampling error with the last condition, as does
  every other reason. The observer, its 1 s, entry, depth and byte limits, the RSS caps and the 30 s
  and 45/60 s deadlines are unchanged. An observer-side check (a lookup denied under an exactly
  delete-pending parent counted as absent) was rejected: that parent is still listed, so the walk's
  next step raises `observer-metadata-invalid` or `-entry-disappearance-uncertain`, which R retries
  anyway. In the same 1,200 iterations one `observer-metadata-invalid` and six snapshot deadlines
  cleared at their first retry.
- Red: `^proc-backpressure-sampling$` FAIL 13 PASS 556 with the old helper (the unit test's
  transient set gains the two reasons; each fails its five checks, and the run of every transient in
  a row fails three). Green: PASS 569;
  `^(proc-backpressure-sampling|bp-declared-observer|bp-disk-observer)$` PASS 696 SKIP 6;
  `^(proc-|bp-)` PASS 2482 SKIP 17; `dev/ci/test-optional-integrations.R` PASS 3823. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: hosted Windows has not run the fix, and the reason occurred once in 1,200
  iterations, so one green run proves little. The Win32 code and the removed directory are inferred;
  a real Windows control (a directory held delete-pending, like CI-73's file) would observe code 5
  but is not added. The census's observer construction error is not examined here.

## Task CI-79 - The Windows writer-runtime cases give a lazy writer cold start the duplex budget (2026-10-21, #63)
- Windows-check `windows-latest (release, shard 1/4)` on 176a3a2 (PR #61, run 39580403671, job
  119156456410) failed native-09 "Windows reactor shutdown settles an idle production writer": a
  `gptr_error_timeout` at stage delivery with accepted_bytes 0. The lazily started writer was alive
  and ready 1.93 s after the write was queued (PowerShell's protected CreateDirectory took 0.64 to
  1.81 s), leaving under 0.07 s of the 2 s window for the first ACK; the file's other cases started
  in 0.62 to 0.81 s. Same class: bc13aba binary (job 116726253175, 1.93 s, which led to 35536d4),
  fa64ef2 shutdown (windows-by-file job 118304278433, 1.41 s), c5a2b8e shutdown and orphan (job
  116082432978, 2.09 and 1.97 s, at stage startup). In R CMD check, this class is 3 of 202 native-09
  runs since 2026-10-14 (c5a2b8e, bc13aba and 176a3a2); fa64ef2 was a windows-by-file run outside
  that count.
- Cause (the limit, not the code): IC-60's no-progress window opens when the write is queued, before
  the lazy `proc_writer_start()`, and only an ACK moves it ("Windows writer startup progress cannot
  extend the stdin deadline" pins this), so each case's 2 s covered writer cold start (Rscript actor
  and PowerShell ACL verifier) plus the first ACK. Hosted cold starts: 437 witnesses, p50 0.65 s,
  p99 1.97 s, max 5.24 s; readiness to first ACK: 166 base-only controls, p50 0.05 s, max 0.57 s.
- Fix (tests only, D-246): `rw_child_case()` sets `gptr.stdin_timeout = 20`, the duplex budget
  (2654a21), and the binary-only 2 s writer admission (35536d4) goes. Product code, IC-60 and the
  60 s default are unchanged; the no-reader timeout cases and the base-only controls keep 2 s.
- Red: a scratch replay of the largest cold start plus the largest readiness-to-ACK (write queued at
  0, ready at 5.24 s, ACK drained at 5.81 s) through the real `reactor_drain_child()`, with each
  case's budget read from `rw_child_case()`: FAIL 6 (`gptr_error_timeout`) on the old helper. Green:
  the replay PASS 12; `^(proc-writer-runtime|proc-windows-backpressure|proc-backpressure.*)$` PASS
  1357 SKIP 8 (the real cases skip off Windows). Lint clean. The replay is not committed: it only
  restates the budget.
- Deviations: D-246. Open: not yet run on hosted Windows. PR #61's writer adds a silent read retry,
  so a retrying writer would leave the same witness; the 0.07 s margin explains 176a3a2, and bc13aba
  and fa64ef2 failed without the retry. fa64ef2 had no ACK 0.59 s after readiness, past the
  controls' 0.57 s, so a host stall also occurs and 5.81 s (two maxima from different samples) is
  not a bound. Still at risk: the no-reader timeout cases (native-04, native-09) need readiness
  within 2 s (none failed at stage startup since 2654a21, in about 300 runs), and the acl case's
  PowerShell readback has 5 s (a 3.20 s PowerShell start and a 5.00 s ACL step were witnessed in a
  duplex case at 3a8315f).

## Task CI-80 - The many-hunks diff bound counts CPU time, not wall time (2026-10-21, #63)
- The CI-79 job (176a3a2, PR #61, run 39580403671, job 119156456410) also failed "many hunks render
  in linear time" (`test-tool-diff.R:182`): 11.4 s >= 5. It is the only failure in 205 hosted
  Windows runs since 2026-10-14 (none in 624 Ubuntu, 100 Ubuntu serial and 101 macOS runs). Hosted
  Windows otherwise took 1.27 to 1.86 s (11 windows-by-file runs, a fresh R per file); in the failed
  run the file's other 5 s bounds passed seconds later, the job's step times were normal, and the
  rerun (job 119173100470) passed.
- Cause: a runner stall caught by an absolute wall-clock bound. `diff_lines()` is linear (1.97 to
  2.14 times the time and 2.00 times the allocated bytes per doubling, 25k to 400k lines locally),
  single-threaded and without children; in-suite and fresh-session times match (0.63 and 0.66 s).
- Fix (tests only): the bound stays at 5 s but counts the call's CPU time (`user.self + sys.self`),
  which a stalled runner does not add and superlinear work does; the failure message also names the
  elapsed time. An allocation-ratio bound was rejected: Rprofmem misses superlinear work without
  large allocations (a stack pop that scans the whole match vector took 3.25 times as long per
  doubling at the same 2.00 byte ratio). D-246 records the change from the plan's wall-clock bound.
- Red: a scratch check mocks a 6 s `Sys.sleep()` (stall) or a 6 s busy loop (slow code) into
  `diff_ops()`; with the wall-clock bound the stall fails ("Expected elapsed time (CPU 0.83 s) < 5").
  Green: the stall passes, the busy loop fails ("Expected CPU time (elapsed 6.67 s) < 5"), and the
  unmocked block passes; `^tool-diff$` PASS 570. Lint clean.
- Deviations: D-246 (second rule). Open: on Windows a hypervisor pause may still be charged to the
  process as CPU time; the file's other 5 s wall bounds (`:83`, `:260`, `:268`) had no failures.

## Task CI-81 - Only the re-send to the silent server gets a short first-byte timeout (2026-10-21, #64)
- PR #61 run 39605697535 (job 119241185802, R 4.2.3, oldrel-4 shard 1/4) failed "a failed re-send
  closes the retry before on_fail; cancelling from retry_end stops it" (`test-http-retry.R:759`):
  the exhausted path expected `gptr_error_overloaded` and got `gptr_error_timeout_first_byte`. No
  earlier failure of this test is in the saved Windows census logs (968 jobs to 2026-10-21T10:20Z).
- Cause: every path ran with `first_byte_timeout = 1`, which only the first_byte path needs (its
  re-send goes to a server that never answers). The reactor takes a transfer's timeouts once
  (`R/http-reactor.R:818`), so the first attempt's 503 from the mock also had to start within 1 s;
  on a loaded runner it did not, and a first-byte timeout is not retried, so the path failed early.
- Fix (tests only): exhausted and start use the default first-byte timeout; the first_byte path
  keeps a short one at 3 s, enough for a slow 503 and still short for the silent re-send. The mock
  server already skips on CRAN.
- Red: a scratch copy whose mock sends every reply's head after 1.2 s; the old block fails 14
  expectations (exhausted and start end as `timeout_first_byte`). Green: the same copy passes all;
  `^http-retry$` PASS 337. Lint clean.
- Deviations: none (tests only; no product bound changed).

## Task CI-82 - Deparsed user and model code passes `backtick`, so a call chain cannot recurse (2026-10-21, #66)
- Windows-check on main `412cf2c` (run 39605492452 attempt 1, job 119240498955, oldrel-4 shard 3/4,
  R 4.2.3) aborted R with "evaluation nested too deeply" and then an `Rcpp::exception` from
  `sys.nframe()`: 1 abort in 499 hosted Windows runs. The log names no test; a local profile of
  shard 3 places its only recursion that deep in `test-env-history.R:184-194`, which logs a
  3,000-head chain `f(1)(1)...(1)` through `user_log_callback()`, whose `user_log_line()` called
  `deparse(expr, width.cutoff = 500L, nlines = 120L)` with `backtick` defaulted.
- Cause: base `deparse()`'s default `backtick = mode(expr) %in% c("call", "expression", "(",
  "function")` calls `mode()`, which for a call returns `switch(deparse(x[[1L]])[1L], ...)`, so
  `deparse()`, `%in%` and `mode()` recurse once per head (an estimated 2,900 R frames there; R 4.2.3
  and 4.6.1 define both alike). On an 8 MB C stack this ends at the C stack check; on Windows' 64 MB
  Rterm stack at `options(expressions)`, which `user_log_text()` catches. When the later package's
  Windows `WM_TIMER` handler (armed once later, httpuv or chromote has run) fires at that depth, its
  `at_top_level()` evaluates `sys.nframe()` through `R_tryEval()`, which fails, and `Rcpp::stop()`
  escapes `DispatchMessage()`, so `std::terminate()` aborts R (from the job log and later's source).
  A user's Windows session with later loaded can abort the same way.
- Fix: `deparse_code()` (`R/utils-text.R`) calls `deparse()` with `backtick = is.call(expr) ||
  is.expression(expr) || is.function(expr)`, the value the default computes, so the text is the same
  and `mode()` is never called. Every `deparse()` of language gptr did not build goes through it (15
  sites): `user_log_line()`, `eval_call_text()`, `eval_format_calls()`, `risk_code_text()`,
  `risk_scan()`'s labels, `dot_labels()`, `ident_label()`, `gptr_describe()`'s function, default,
  formula and model-formula text, `ns_formals_text()`, `ns_collect_input()`, `home_label()` and the
  sidecar's call identity in `doc_sidecar_data()`. Left as they are: `artifact-app.R` (a name that
  already passes `backtick = TRUE`, and data names as strings) and `proc-spawn.R` (gptr's own
  functions). `user_log_text()`'s note drops long call chains: 20,000 heads now deparse in 0.16 s
  on an 8 MB stack.
- Tests: under `options(expressions = 1000)`, a 500-head chain is deparsed at each site family, one
  new test each in eval-core, perm-classify (`risk_code_text()`), gptr-capture, env-describe,
  tool-namespace and session-live; the env-history test now expects the cut 3,000-head text, not the
  "cannot be deparsed" note. The default reaches that limit at 197 heads (about 5 evaluation levels
  per head). `risk_scan()`'s labels and the sidecar's call identity rest on the rule and the
  identity check instead: without the JIT, `risk_scan()`'s own walk nests about as deep per head as
  the default (4 against 5 evaluation levels), and the sidecar's 64-level bound keeps it far below
  any limit.
- Identity: old and new outputs are `identical()` on an 81-item corpus (non-syntactic names,
  operators, `%op%`, formulas, `\(x)`, closures, builtins, specials, symbols, expressions, the empty
  symbol, atomic values) under each argument set the sites pass: 651 `deparse()` comparisons and 816
  site outputs, including 11 errors the old code raised on odd inputs.
- Red: the new tests on main `7cfd543`: FAIL 7 PASS 2261 (six "evaluation nested too deeply"
  errors; the env-history log holds the note). Green: the same files PASS 2271;
  `^(env-history|eval-|perm-|risk|gptr-capture|doc-|console-render)` PASS 4901 SKIP 2;
  `^(env-describe|tool-namespace|session-live|session-object|gptr-gateway|agent-run|env-snapshot|`
  `prompt-compact|s1-route|arch-layers|lint-rules)$` PASS 3059. Lint clean.
- Deviations: none (output unchanged). Open: hosted Windows has not run the fix. Other R recursion
  that reaches `options(expressions)` on Windows with later loaded, such as `risk_scan()`'s walk on
  deeply nested code (caught by `risk_classify_r()`), still meets later's timer handler. Past about
  60,000 heads on an 8 MB stack (about 8 times that on Windows' 64 MB), `deparse_code()` overflows
  R's unchecked C deparser instead of failing catchably in `mode()`; `user_log` caps chains at 5,000
  heads, and `gptr_risk()` already overflows on such code on main.

## Task CI-83 - The observer retry test's mixed sequence stays inside the retry deadline (2026-10-21, #65)
- main 7cfd543 (PR #61 merged) failed macos-latest (release) in run 39617294607:
  "backpressure observation retries fixed transient observer reasons for one deadline"
  (`test-proc-backpressure-sampling.R:686-688`) ended its eighth transient as the error, with 8 calls
  and 7 retries instead of 9 and 8.
- Cause: CI-78 added two reasons to the "repeated transients in any order" case, so it chained 8
  failures. `bp_observe()` sleeps 0.1 s per retry and stops retrying 1 s after the first failure;
  eight in a row need at least 0.7 s of sleep plus each call's time, and a slow runner crossed 1 s.
  The code is right; the test needed the margin.
- Fix (tests only): the mixed sequence uses four reasons in a new order (8, 1, 7, 2); each of the
  eight reasons is still retried and checked on its own above it. No bound changes.
- Red: a scratch copy whose fake observer takes 50 ms per call; the old block fails 3 expectations
  exactly as on macOS, the new one none. Green: `^proc-backpressure-sampling$` PASS 569. Lint clean.
- Deviations: none.

## Task CI-84 - Reactor tasks end with their worker or codex exec, not at their next poll (2026-10-21, #67)
- PR #64 run 39617443293 (attempt 1, job 119282269044, oldrel-4, R 4.2.3, two parallel test
  processes) failed 10 of 18 blocks of `test-compaction-wait.R` with `cp_wait_clock()`:
  `!length(ls(r$tasks)) is not TRUE` (`:42`, every block starts on an idle reactor). Main 7cfd543
  passed oldrel-4 (run 39617294607); no other of the 33 failed R-CMD-check jobs since 2026-10-19 has
  it.
- Leaker: `test-cli-codex.R` "a fake CLI joins two inline agents and two workers on one reactor
  (INFRA-16)", the file's last test that pumps the reactor (the log's last lines before the failures
  are from cli-codex and cli-claude). It left one worker's abort guard (`worker_spawn()`) and
  nothing else: no transfer, watcher, run or timer. Nothing in compaction-wait pumps before that
  check, so every block failed. The guard polled every 0.1 s and ended only at its first poll after
  the exit; the proxy request's generator polls every 0.05 s, so the run settles and the team's pump
  returns a few ms after the exit is handled. Whether the guard polled in between depends on how
  long that handling takes: here `kill_all()` of an exited child walks 1259 processes in 33 to 63 ms
  per child.
- Evidence: per-test snapshots of the 38 earlier files in one session, and three concurrent copies
  of the cli and compaction files under 20 busy loops, ended every file idle. INFRA-16 alone left a
  task in 0 of 6 runs; with an exited child's `kill_all()` returning at once, as on a small runner,
  and the task calls traced, 2 of 6 left the second worker's guard (`t22`, `t86`); fixed, 0 of 5.
- The codex relay task (`pcli_codex_relay()`) ended the same way, at its first 0.02 s poll after the
  turn; INFRA-16 leaves it, one task and nothing else, if its codex agent settles last. The log
  cannot tell the two apart.
- Fix: `worker_cleanup()`, which both ends (`worker_on_exit()`, `worker_kill()`) call, cancels the
  guard first; the guard no longer checks `st$exited`. `pcli_codex_end()`, every end of a codex
  exec, cancels the relay and removes its mailbox before the terminal event; the relay no longer
  checks `s$done` (a finished turn is never current). `cp_wait_clock()` names each task an earlier
  test left by the start of its body instead of the bare `stopifnot()`.
- Red: the new "a worker's exit ends its abort guard before the guard polls again" (a mocked
  `proc_rscript()` starts a 0 s Rscript; the guard's registration is read as the exit is handled)
  failed 3 of 3 and left `t2`; "the relay mailbox is answered in order" now checks the mailbox and
  task are gone as `turn.completed` returns, and failed both and left `t2`. Each run before
  `test-compaction-wait.R` in one process failed 10 of 18 blocks, now naming the task: "an earlier
  test left reactor tasks:" `{ if (isTRUE(st$exited)) return(FALSE) ...` and
  `{ if (s$done || !pcli_turn_current(s)) ...`. Green: both pass, and 0 of 18.
  `^(cli-|subagent-|compaction-|auth-|console-setup$|provider-registry$|arch)` PASS 5094 SKIP 4;
  `^(agent-|reactor|http-|proc-|team|tool-)` PASS 6158 SKIP 13; the whole suite with two parallel
  workers (`TESTTHAT_PARALLEL=true`) PASS 35153 SKIP 64. Lint clean.
- Deviations: none (no contract or user-visible change). Open: a codex exec P05 lets go of without
  its normaliser (`stream_abort()`, `stream_detach()`) still ends its relay at the next poll.

## Task CI-85 - The idle Windows writer cases give a retirement and cold start the duplex budget (2026-10-21, #68)
- Windows-check run 39617294666 on `7cfd543` failed `windows-latest (oldrel-4, shard 1/4)` in
  attempts 2 and 4 (1, 3 and 5 passed): native-08 "idle Windows writer retirement preserves target
  stdin and later FIFO EOF" (job 119296531347, `test-proc-writer-retirement.R:501-525`) and
  native-06 "two acknowledged idle Windows writers do not starve a third reading target" (job
  119328715831, `test-proc-writer-idle-slots.R:114-116`). Each third write ended in
  `gptr_error_timeout` (2 s) after 2.50 and 2.58 s, with accepted_bytes 0 and the third writer
  alive (step, status and cause NULL): native-06 at stage startup, its writer started 1.08 to
  1.66 s after the write was queued (the retirement plus start preparation); native-08 at stage
  delivery, its writer ready 1.00 s after its start. These are the only failures among 74
  complete hosted witnesses of the two cases since 2026-10-12; the 72 delivered third writes took
  0.65 to 1.28 s (median 0.89 s).
- Cause (the limit, not the code): with two idle writers at the cap, `proc_writer_start()` first
  retires one (`proc_writer_stop()`, `kill_all()` with taskkill) and then cold-starts the third
  writer, and IC-60's window opened when the write was queued (CI-79). So 2 s covered the
  retirement and start preparation (1.08 to 1.66 s in native-06), a cold start (p99 1.97 s, max
  5.24 s) and the first ACK. native-06's writer never became ready, so CI-75's read retry (PR #61)
  cannot be involved there; native-08's witness cannot exclude it (a retried read keeps the writer
  alive with no step or status), though its timeline fits the budget alone. Both failures came
  from the 28 native-real jobs carrying #61's code (none in the 209 before).
- A side-by-side hosted loop settles that: run 39643195277 (never-merged branch
  `claude/writer-loop`, 8 jobs, R 4.6.1 and R 4.2.3) ran both cases 40 times per job with main's
  writer (carrying #61) and with the writer of `412cf2c` (before #61) on the same runners. main's
  writer failed 0 of 320 case runs, the older writer 1 (an `idle-restart` restart write,
  `gptr_error_timeout`, R 4.2.3), and the third writes took the same time (median about 1.0 s, max
  1.47 s against 1.59 s). So #61 does not raise the rate; the census split reflects one slow run.
- Fix (tests only; D-246 amended to one rule): `idle_child_case()` and `idle_restart_child_case()`
  set `gptr.stdin_timeout = 20`, the duplex budget, and `warm_idle_child_case()` (native-05) sets
  it for its third write, whose title becomes "... a third write" (also in
  `dev/ci/optional-integrations.R` and its test). native-08 drops `expect_lte(third_elapsed, 2)`
  and `all(again_elapsed <= 2)`, since a later write retires and cold-starts too, and keeps
  `expect_length(again_elapsed, 2L)`. Product code, IC-60 and the 60 s default are unchanged.
  Starvation, the property under test, still fails: a write that never gets a writer times out at
  20 s, inside the 30 s case deadline.
- Red: a scratch replay through the real `reactor_drain_child()` (write queued at 0, writer started
  at 1.08 s, ready at 2.08 s, ACK at 2.14 s), with each case's third-write budget read from
  its last `gptr.stdin_timeout` setting: FAIL 3 (`gptr_error_timeout` for native-05, -06 and -08 at
  2 s). Green: the replay PASS 6, and a write that gets no writer slot is pending at 19.99 s and
  times out at 20 s (PASS 4); `^proc-writer-` PASS 930 SKIP 11 and `^proc-windows-backpressure$`
  PASS 234 (the real cases skip off Windows); `dev/ci/test-optional-integrations.R` PASS 3823
  (FAIL 1 on the renamed title before its registry entries changed). Lint clean. The replay is not
  committed: it only restates the budget.
- Deviations: D-246. Open: not yet run on hosted Windows; native-05 has not failed and changes only
  to keep one rule; if native-08 recurs at stage delivery, suspect CI-75's read retry first.

## Task CI-86 - Linux CI installs its system libraries without pak's Chromium PPA (2026-10-21, #69)
- Since about 14:30Z on 2026-10-21 Ubuntu jobs failed in `setup-r-dependencies`: pak maps chromote's
  and gptr's own SystemRequirements (a Chrome-family browser) to `chromium`, so it runs
  `add-apt-repository -y ppa:xtradeb/apps` and `apt-get install chromium`, and
  ppa.launchpadcontent.net answered 503 ("E: Failed to fetch .../chromium_155.0.8059.79-...deb 503
  Service Unavailable", then "System command 'sudo' failed"). Run 39617294607 (main) lost 4 Linux
  jobs this way, run 39638712528 (PR #67) 6; the rest passed only while the PPA answered. pkgdown
  (run 39617294897) and the dispatch workflows add the same PPA.
- Fix: `.github/actions/system-libraries` holds Plan-gates' apt list and dpkg verification. Every
  Linux job that installs R dependencies, except rhub.yaml's, runs it before `setup-r-dependencies`,
  which gets `PKG_SYSREQS: 'false'`: R-CMD-check (Ubuntu rows, no-suggests, c-locale, cran-mode,
  copy-safety, connections, bench), Plan-gates, pkgdown, Optional-integrations, rscript-native,
  callr-native-environment, windows-by-file's optional Linux row and Exact-tarball's producer,
  Ubuntu check rows and dependency-profiles (from the controller checkout, sparse in the first two,
  since the nominated source may predate the action). On macOS and Windows rows the action is
  skipped and `PKG_SYSREQS` is inert (pak's sysreqs support Linux only); job names are unchanged;
  jobs with smaller profiles (no-suggests, pkgdown) now install the whole list. chromote searches
  `google-chrome` first, which the ubuntu-latest image provides, so CHROMOTE_CHROME stays unset.
- Coverage: every pak install list in the failing runs and the latest Linux runs of the dispatch
  workflows is in the list except `chromium` and `libfreetype6-dev` (transitional to the listed
  `libfreetype-dev`); devtools jobs also asked for `git` (preinstalled) and `libx11-dev` (installed
  with `libmagick++-dev`, Plan-gates run 39371724850).
- Checks: every workflow and action parses with `yaml::read_yaml`; `^zzz$` PASS 145;
  `dev/ci/test-optional-dependencies.py` OK; the action's script passes `bash -n`.
- Deviations: none. Open: not yet run on hosted runners; a new dependency's library must be added to
  the list (Plan-gates' `pak::sysreqs_check_installed()` reports it for its profile); rhub.yaml
  (r-hub/actions/setup-deps in its Ubuntu containers and on the `linux` VM platform) still adds
  ppa:xtradeb/apps, as in run 39566663196, and the action (sudo, noble package names) cannot run in
  r-hub's root containers; the source_sha nominated to Plan-gates, Optional-integrations,
  rscript-native, callr-native-environment and windows-by-file (optional) must contain
  `.github/actions/system-libraries` (this commit or later), as Optional-integrations and
  windows-by-file already need for `optional-dependencies`; Exact-tarball takes the action from its
  controller checkout.

## Task CI-87 - The codex turn test keeps its fake keys out of the process vault (2026-10-21, #71)
- `dev/ci/isolated-check.R test '^(cli-codex|perm-classify)$'` failed "secret rules come from P03's
  secret_scan()" (`test-perm-classify.R:723`): `gptr_risk("k = Sys.getenv('OPENAI_API_KEY')")`
  had `secret_guard` TRUE. Each file alone passed.
- Cause (the test, not the code): "a codex turn: exact argv, ..." (`test-cli-codex.R:942`) sets fake
  `OPENAI_API_KEY` and `CODEX_API_KEY` with `withr::local_envvar()` and runs `peter()`.
  `session_new()` registers secret-looking environment variables (`secret_discover_env()`,
  `R/session-object.R:94`, as contract 04's `session_new` row requires), and the vault belongs to
  the process, so both names stayed registered after the variables were restored, and the
  classifier read `OPENAI_API_KEY` as a registered (guarded) secret. A testthat state inspector over
  `secrets_state()$reg` showed this block, and no other, adding the two names. The codex CLI is the
  fake one, so an installed Codex CLI plays no part. The whole suite hid the leak: files between the
  two (console-render, mcp-client, ...) reset the vault with `local_vault()`. CRAN skips the block.
- Fix (tests only): the block calls `local_vault()`, and a new block after it checks that neither
  fake key is registered. Ambient discovery at session start is unchanged.
- Red: `^cli-codex$` FAIL 1 PASS 511 (the new check); `^(cli-codex|perm-classify)$` FAIL 2 PASS
  1400. Green: `^cli-codex$` PASS 512; `^(cli-codex|perm-classify)$` PASS 1402;
  `^(cli-|perm-|auth-)` PASS 3856 SKIP 3. Lint clean.
- Deviations: none. Open: the file's later `peter()` blocks still register any secret-looking
  variable of the host that setup.R does not blank (here Claude Code's
  `CLAUDE_CODE_MESSAGING_TOKEN`, first at `:988`) and leave it in the vault.

## Task FIX-13 - One honest size for every object (2026-10-21, #73)
- The maintainer's rule: an object the agent creates is the console's, at the same size, and gptr's size
  reports are honest for every kind of object. The fidelity harness (37 cases, each built at the console and
  through `peter()`; truth `lobstr::obj_size()` and the bytes not shared with namespaces) found the objects
  identical but 134 dishonest size rows on main (ggplot2 4.0.3, S7 0.2.2, R 4.6.1): no size for S7 plots,
  functions, environments and compact sequences (D-189); `object.size()` in lists of plots (seven themed plots
  111 MB against 9 MB: undo skipped, overwrite level 3), values and dot facts; checkpoint images sized leaf by
  leaf (a themed plot's image 15.8 MB against 840 B; pinfsc50's `@fix` edit 8.7 MB against 1.3 MB); shared
  elements counted per path; a formula's environment uncounted; R6 objects and environments "copied" by a
  `duplicate()` that returned them; a changed `1:1e6` called a sequence. The branch's first fix (S7 leaves
  through D-189's rule, unknown sizes copied at 0 bytes) left lists overstated and copied every plot unbounded.
- Fix: D-247 (amended): `env_snap_size()` in `utils-size.R` counts each part once by address and each string
  once by content, leaves out code, top-level environments, the home and running frames, walks an S7 class copy
  once per class, samples lists and environments of more than 64 items past 10,000 parts, and with `shared`
  sizes a checkpoint image against the current value; every size surface calls it (`env_snap_rows()`,
  `dsc_leaf_core()` and the describe headers, `risk_binding_leaf()`, `value_facts()`, `dot_facts()`,
  `tool_result_message()`, `subagent_fanout_spec()`, `artifact_data_facts()`, `ckpt_unshared_bytes()`), and
  `describe_binding()` describes with its home on the call stack. The value policy copies below
  `gptr.value_copy_max`, now 2 MiB, when `object.size()` is below `gptr.values_max_bytes` and keeps a copy that
  is a new object under the limit. Snapshot sizes are reused only while the fingerprint holds too.
  Review fixes: an environment takes the 100-level cap (a chain of 700 overflowed the node stack, so the snapshot
  failed: no `<workspace>` block, no checkpoint of the turn, "describe failed"); a vector counts its stored
  length through `object.size()` (`length()` dispatched: survival's `Surv` counted half, `bit::bit(1e8)` 381 MB
  for 12.5 MB); a closure's srcref is code (each of a sourced 748-line file's 53 functions was 589 KB); the
  describe header drops "(compact sequence)", whose check serialized a sequence-like vector a second time;
  `held_mb` and `disk_mb` count 2^20 bytes; a dead `home = NULL` and a redundant guard go.
  Deleted: D-189's NA rule and median rank, `ckpt_addr_collect()` and `ckpt_unshared_walk()`, the old
  three-element `env_compact_seq()`, the "(sequence)" shape and the describe headers' NA branches; the first
  fix's NA-means-copy rule and long-sequence exception are not kept.
- Red: on main (ba77f68) the new and changed expectations fail: FAIL 60 in 28 tests (env-snapshot 11,
  env-describe 8, ckpt-objects 2, session-object 2; arch-layers, copy-eval, gptr-capture, perm-classify and
  utils-options 1 each); on the size commit the 2 MiB default's check fails (`^(session-object|utils-options)$`
  FAIL 1). Review fixes, each before its commit: env-snapshot ERROR (node stack overflow) and FAIL 1 (a classed
  vector 232 B against 800,224 B), srcref FAIL 3 (env-snapshot 2, env-describe 1), env-describe FAIL 1 (the
  header), ckpt-rewind FAIL 1 (`held_mb` 1.049 against 1).
- Green: `^(env-snapshot|env-describe|ckpt-objects|perm-classify|gptr-capture|session-object|arch-layers|
  utils-options|copy-eval|copy-tools|tool-namespace|console-commands|s1-route|lint-rules|prompt-text|
  artifact-app)$` PASS 3954, SKIP 0 (the ggplot2 guard ran), WARN 0. The whole suite (NOT_CRAN) failed once in
  subagent-team, whose value held by name (1.6 MB) is copied at 2 MiB; it now returns 2.4 MB, and the suite
  passes: PASS 35225, SKIP 64 (Windows, live and Python-runtime blocks), WARN 0. Lint clean; `devtools::document()`
  leaves no diff; the plan checks pass. After the review fixes: `^(env-|ckpt|session|gptr-capture|perm-classify|
  copy-|arch|zzz|utils-options|subagent-team|listing-print)` PASS 4644, SKIP 1 (the C-locale display witness),
  WARN 0; the six changed files lint clean; `devtools::document()` leaves no diff.
- Harness (the review-fixed build at the 2 MiB default; the harness now judges the value mode at the build's
  `gptr.value_copy_max`, not a fixed 1 MiB, which had flagged `df_big` and the data frame of plots): defect rows
  134 on main, 15 with this rule (5 lobstr's ALTREP-wrapper undercount, 3 srcref, 5 "serializes differently", now
  also `df_big` and the data frame of plots, whose copies write out a compact `id` column, and 2 environments held
  by name); the two themed plots just over 1 MiB are copied (922 and 914 KB held) and survive the edit; against the
  build before the review fixes only `closure_factory` (784 to 782 KB) and `r6` (785 to 782 KB) changed, by their
  functions' srcrefs. Every surface shows one number per case; the judges' stress objects (sizes and images
  unchanged by the review fixes) within 0.6x to 1.2x of `lobstr::obj_size()` in at most 0.3 s (checkpoint forms
  0.6 s). Copy safety: 64 tracemem/address probes (list, nested, attribute, S4 slot, data frame column,
  environment, closure environment, character elements, lists past the budget walked and unwalked, the checkpoint
  form, plot data and labels, a list of 200 plots) match a run without sizing, rerun on the final `utils-size.R`. A
  1,000-node environment chain in the workspace keeps the `<workspace>` block and the turn's checkpoint (1/1
  objects).
- Reviews: three designs (minimal, sharing, purpose) judged twice; the minimal walk won, with the judges' grafts:
  strings once by content, the `object.size()` bound before a copy, no extrapolation from a first item that
  reaches a shared frame (now: the first, the last and the budget-spending item are not samples), 56 bytes a
  binding.
- Decisions: `gptr.value_copy_max` 2 MiB; `dot_facts()$bytes`, `value_ref$bytes` and the fan-out facts' bytes
  kept and sized by this rule; `describe_binding()`'s home on the call stack, the dropped "(sequence)" shape,
  the sampling budget and environment sizes that stay until the shape changes accepted; after review, the
  describe header's "(compact sequence)" dropped too and `held_mb` counted in 2^20 bytes.
- Deviations: D-247 (amended). Open: `fingerprint_sample()`'s `as_utf8()` makes the next in-place edit of a list
  with a character element copy after a snapshot (a main defect; fixed on its own branch). Found in review, main
  defects for their own branches: `/exit` sends `session_shutdown`, which releases the returned console session's
  undo images (`gptr_rewind()` then restores no object); `gptr_source()` rebuilds an object that captures a call
  with the document's srcref, as `source(keep.source = TRUE)` does; `gptr_export()` refuses a console transcript,
  whose later turns continue `s_<id> |> peter()`.

## Task FIX-14 - fingerprint() leaves a list's elements editable in place (2026-10-21, #72)
- Red: FAIL 2 in `^utils-hash$` (PASS 55): after `fingerprint()` of a list with a character
  element, the next in-place edit copied the character and the numeric element (a new CRAN-run
  `obj_address()` test, and a new tracemem row tracing a 40 MB numeric element). Installed builds:
  main FAIL 1 with NOT_CRAN unset, FAIL 2 with it set. `env_snapshot()` fingerprints every binding.
- Cause: `fingerprint_sample()`, called inside `fingerprint()`'s element loop, called `as_utf8()`.
  Its replacement calls (`Encoding(y) = ...`, `x[mark] = y`) run R's `INCLNK_stack_commit()`, which
  also links the loop variable's binding cell on the byte-code stack; the inline call's return
  restores `R_BCProtCommitted` (`restore_bcEval_globals()`, in the R 4.4.3, 4.5.0, 4.6.1 and trunk
  sources), so that link is never dropped, `R_CleanupEnvir()` stops at the cell when
  `fingerprint()` returns, and its argument promise keeps the list referenced. Byte-compiled code
  only: an installed package, or a JIT-compiled `as_utf8()` from its second call. A pure-R
  reproduction needs a compiled `for` loop in the function that holds the object and a replacement
  call in a callee (a `while` loop does not leak).
- Fix: `fingerprint_sample()` pastes the sampled values without `as_utf8()`; `fingerprint()`'s doc
  states the rule.
- Encoding: `cli::hash_sha256()` hashes the bytes as given; `paste()` turns latin1 text into UTF-8
  in a UTF-8 locale, so there fingerprints are unchanged and a latin1 and a UTF-8 spelling of a
  text fingerprint alike (new test). In a non-UTF-8 locale `paste()` gives native text
  (`caf<e9>` under LC_ALL=C), so the two spellings now differ there (the test skips).
- Green: `^utils-hash$` PASS 57, LC_ALL=C PASS 54 SKIP 1; installed fix FAIL 0 (NOT_CRAN unset and
  set); `^(utils-hash|env-snapshot|copy-)` PASS 354; `^(arch-layers|lint-rules|utils-encoding)$`
  PASS 123. Lint clean.
- Review: the orchestrator read the diff and tests; full suite (NOT_CRAN=true) FAIL 0, WARN 0, SKIP 64,
  PASS 35170.
- Deviations: none. Open: any compiled leaf whose `for` loop holds a user object and calls code
  that makes a replacement call copies the same way (R behaviour, not reported upstream);
  `d$s[1] = v` copies a data frame column whatever gptr does (`$<-.data.frame`).

## Task CI-88 - The Windows stdin drain reads writer liveness before its acknowledgements (2026-10-21, #75)
- PR #73 run 39701794227 (job 119572506456, ubuntu-latest release) failed "a cold writer names a
  failed mailbox validation" (`test-proc-windows-backpressure.R:375`): `accepted_bytes` 0, not
  65536, while the step (`validate_read`), status 18 and cause matched; the case's witness line
  reads `"drain_elapsed":0.446,"accepted_bytes":0`. No other run failed it: since the test landed
  (`3a05693`, 06:16Z) the failed-job logs of the 10 other R-CMD-check and Windows-check runs with
  failed jobs fail for other causes, and about 280 jobs of the kinds that run it passed.
- Cause (the product; the drain runs only on Windows): `proc_writer_drain()` read the
  acknowledgements (`proc_writer_ack()`), then the child's and the writer's liveness, and reported
  a writer seen exited with what it had read. Status 18 means the writer had published
  `ack-000000000001-065536`: it reaches `validate_read` for the second chunk only after that. A
  local probe saw that writer exit 39 to 68 ms (median 56, 30 runs) after its last acknowledgement
  became visible, so the parent was paused at least that long between `list.files()` and
  `is_alive()` (a full garbage collection late in the check's testthat process, or a descheduled
  vCPU) and reported 0 of the 65536 bytes the pipe had taken. Only this test is exposed: its
  injection refuses `in-000000000002` at the writer's first mailbox check for the second chunk,
  before the parent publishes it; the siblings fail on that chunk, which the parent publishes only
  after reading the first acknowledgement. The child-exit branch had the same order: a Windows
  child that read all of its stdin and exited could be reported as "The child exited before stdin
  was delivered." when its writer's last acknowledgement landed in that gap.
- Fix: the drain reads the writer's, then the child's liveness before the acknowledgements, so a
  writer seen exited has published all of its own, and a child whose exit ended the writer is seen
  exited too.
- Test: "a writer exiting right after its acknowledgement keeps the accepted bytes" makes the
  interleaving certain: the writer acknowledges 0.1 s late, and the parent pauses after its first
  read of the first chunk until the writer has exited. It uses the blocked child, which echoes
  nothing (with the echo child a probe hung on macOS once the paused parent stopped reading its
  output). The validation test and this one share `mailbox_refused`. A first version skipped that
  read instead; 1 of 200 runs failed when the writer had exited before it, which a real read
  would have seen. "a writer ended by its child's exit after full delivery is not a failure" pins
  the order of the two liveness reads: the numeric child reads all four bytes and exits, which ends
  its writer (status 17, `alive`), while the parent waits in a wrapped `isTRUE()` just before its
  first liveness read with the chunk pending.
- Measurements (macOS, 16 cores; the nine step-failure tests, 200 iterations each, one
  `test_file(desc =)` per test): before, idle 0/1800; 8 busy loops, side by side with the fixed
  tree, 0/1800; one busy loop per CPU plus two runners 22/1800, all `gptr_error_timeout` (nothing
  accepted for 2 s; tests up to 165 s against a 1.6 s median), none with the CI signature; the
  parent stopped by SIGSTOP for 30 or 120 ms at random, 0/40 and 0/100 of the exposed test. The
  regression on main: 100/100 and 200/200 fail with `accepted_bytes` 0. After: idle 0/1800 and the
  regression 0/500; 8 busy loops 0/1800 and the regression 0/200. Side by side under one busy loop
  per CPU (stopped after 41 tests each, load average above 300), both trees failed the same two
  tests at the same moments with timeouts. The child-exit test fails on main 120/120 (119 with
  `b$pos` 0; once main read the child's exit and the acknowledgement before any writer liveness
  read, so it never paused) and with the child's liveness read first 220/220 (4 of 4 bytes
  accepted; 100 of them under 8 busy loops); both errors are "The owned stdin writer exited before
  delivery settled.", step `alive`, status 17 (a probe, 10/10 each). After: idle 0/200, 8 busy
  loops 0/100.
- Red: `^proc-windows-backpressure$` on main FAIL 3 PASS 251 (`accepted_bytes` 0; the child-exit
  test's error and `b$pos` 0), with the child's liveness read first FAIL 1 PASS 253. Green: PASS
  254; `^proc-` PASS 2375 SKIP 11; `^(lint-rules|arch-layers)$` PASS 90. Lint clean.
- Deviations: none (no bound changed). Open: not yet run on hosted runners; the startup branch
  still reads `ready` before the writer's liveness, so a writer that exits right after publishing
  `ready` is reported as a startup failure (no bytes are lost); the cold controls' 2 s stdin bound
  fails under CPU saturation (above), which hosted runs have not shown.

## Task CI-89 - The six-stream wall nets out each end's garbage collection (2026-10-22, #74)
- PR #72 run 39706834831 (attempt 1, job 119589000853, ubuntu-latest oldrel-1, R 4.5.3, two test
  processes) failed INFRA-01 "six streams of 1.00-2.25 s finish within 10% of the slowest"
  (`test-http-reactor.R:717`): wall 2.684 s against 2.475 s. All six requests came at 0; gptr
  delivered the short ends 1-2 ms after the mock wrote them and the long ends, written at 2.341,
  2.375 and 2.383 s, all at 2.775 s (0.434, 0.400 and 0.392 s late).
- Rate: the 442 failed job logs since 2026-10-12 (first attempts of re-run runs included), out of
  about 1,650 hosted executions of the test, hold 7 failures of it. Four (114998072098,
  115386981898, 117897245682, 119065496949) are CI-77's late heads, with every end within 16 ms;
  114920821918 had heads 1.5 s apart (and a short end 0.281 s late); 118506033270 was a runner
  pause (the mock 0.54-1.70 s late, two ends 0.464 and 0.888 s); 119589000853 is this one. The
  per-delta test failed once the same way (macOS 115073223120: one delta 0.406 s late, the rest
  within 12 ms). So the test process stopping for about 0.4 s fails roughly 3 in 1,650 executions,
  on Linux 1 in about 1,000.
- Cause (the measurement): the test's R process stopped; the reactor and the mock did not. The
  pump polls curl's sockets and wakes at least every 100 ms (`slice_ms`): instrumented locally,
  over 21,000 wake-ups at load 4-342 slept at most 0.116 s, and 520 runs delivered every end within
  0.044 s. The mock wrote streams 5 and 6 34 and 42 ms after stream 4, so it ran during the stop,
  while one pump iteration delivered all three ends: the test process ran nothing for about 0.4 s.
  A full garbage collection is such a stop. After the 100 test files that sort before http-reactor,
  run in one process as a worker runs them, the reactor holds nothing, no finalizer is pending, and
  a full `gc()` takes 0.25-0.26 s here (5.2M cons cells, load 6-17), all of it collection; a hosted
  vCPU is slower. A full collection forced at 2.3 s with a 1.26 GB heap gives the hosted shape:
  collections of 0.36-0.43 s, the three long ends 0.21-0.38 s late together, the short ones within
  6 ms, walls 2.480-2.626 s, FAIL 10 of 10 (load 4-7). Which stop hit the runner is inferred: a
  collection fits, and a vCPU or scheduler stall fits the same numbers.
- Fix (tests only): each pump iteration of the test notes the wall clock and R's collection total
  (`gc.time(TRUE)`; off by default, used nowhere else, and off again when the test ends).
  `infra01_gc()` gives each end the collection time from the last iteration before the mock wrote
  it to the first one after gptr delivered it, and `infra01_six()` nets that out of that end only,
  as it nets the mock's lateness: a collection outside an end's window cannot have delayed it. The
  2.475 s bound and the latency check are unchanged; the message prints each end's netted time.
- Red: the measurement test's new cases (the long ends 0.4 s late are on time when R collected for
  0.4 s around their delivery and late when it collected only as the short ends came; a collection
  before an end's write counts nothing for it) FAIL 1 on main (`infra01_six()` takes no `gc`) and
  FAIL 1 on this task's first version, which netted the run's whole collection time; a mutant that
  gives every end the whole-run time FAIL 1, one that ignores `gc` FAIL 1. Green: `^http-reactor$`
  PASS 235 SKIP 2 (load 15-16); the six-stream test 200 of 200 (load 15-27); `^http-` PASS 808
  SKIP 2 (load 17-18); `^(console-|agent-)` PASS 3046 SKIP 1 (load 18-186). Injected into the real
  reactor and mock (1.24 GB heap, full `gc()` 0.30-0.33 s, 5 runs each, load 16-18, repeated from
  load 28-49 with the same outcome), unnetted / whole-run netting / per-end netting: a full
  collection at 2.3 s FAIL 4 / PASS 5 / PASS 5 (0.331-0.352 s netted for the long ends, 0 for the
  short; net walls 2.087-2.223 s); a collection at 0.3 s and a 0.3 s stall that is not one at
  2.3 s FAIL 4 / PASS 5 / FAIL 4 (nothing netted); no stop PASS 5 throughout; a 0.4 s stall that is
  not a collection FAIL 5 throughout. 100 unstopped runs (load 14-18): walls at most 2.255 s raw
  and net, a collection in 38 runs (at most 0.015 s), netted for an end in 10, delivery p50 1 ms,
  p99 6 ms, max 11 ms. Delivery of the ends before (the code is unchanged): 120 runs at load
  207-342 p50 1.8 ms, p99 24 ms, max 44 ms; 100 after the preceding files max 22 ms. Lint clean.
- Reviews: r1 2 findings, both applied. The first version netted every collection of the run, so
  an unrelated collection excused gptr's own stall (the injected early collection and end stall
  above passed 5 of 5); D-063 item 2 did not state the measure (nor CI-77's anchor).
- Deviations: none new (D-248 and D-249 are not taken); D-063 item 2 is edited in place to state
  the measure (CI-77's `came` anchor, this task's per-end netting, the bound unchanged, the rates
  above) and D-016 item 1's anchor with it. Open: a stop that is not a collection (a vCPU or
  scheduler stall) still fails, by design, and the message says which. An end's window opens at
  the last iteration before the write, so a collection that ended within that iteration (at most
  a 100 ms poll) before the write is netted too. The per-delta test has the same exposure (macOS
  115073223120) and is not changed here.

## Task CI-90 - A modern MCP server that answers the era probe late is probed again (2026-10-22, #76)
- Main 717f9bc, Windows-check run 39734651356 (job 119678206014, windows-latest oldrel-4, R 4.2.3,
  shard 2/4) failed "setting mcp.exposure = "direct" declares the tools of a server without
  exposure" (`test-mcp-namespace.R:216`): the session's frozen tool names lacked
  `mcp__fixture__echo` and `mcp__fixture__add`, with no error. The log says nothing else on MCP.
- Rate: the logs of the 1,059 failed jobs (all attempts) of runs since 2026-10-04 hold this
  signature three times, all on hosted Windows: 115336083629 (release, R 4.6.1, 2026-10-13, "a
  modern stdio server is found by the probe ...") and 115749420627 (oldrel-4, R 4.2.3, 2026-10-14,
  the progress test, which 35ca403 then gave a cached era) stopped with "MCP server fixture answered
  initialize with error -32601: Method not found: initialize"; this job is the same error inside
  builtin:mcp's session_start hook, which records it as a diagnostic. Since the client landed,
  hosted Windows ran the suite about 520 times (412 finished unsharded windows-latest jobs, 434
  finished shards), each starting about 25 modern stdio fixtures without a cached era: about 1 in
  170 Windows suites, 1 in 4,000 cold connections. None in 1,614 finished Linux and macOS jobs. The
  other MCP failures in those logs have other causes (a processx socket read error in
  `test-mcp-server.R` twice, the HTTP era test, an interrupt's cancel, the progress test's 1 s
  call).
- Cause (the product; not a race): `run_freeze()` emits `session_start` and waits for its handlers
  before `prompt.freeze`, and builtin:mcp's handler connects and lists the tools there, so the
  freeze never precedes the server's answers; a failed connection is a diagnostic and the server
  declares nothing. The connection failed in the era probe: `mcp_request()` opens the
  `server/discover` window (`gptr.mcp_probe_timeout`, 5 s) before its first write, which on Windows
  goes through the lazily started stdin writer (Rscript actor and PowerShell ACL verifier: cold
  start p50 0.65 s, p99 1.97 s, max 5.24 s on hosted runners, D-246) while the fixture's own Rscript
  starts. An unanswered probe was taken as legacy (report 16 4.5): `initialize` went out, the
  modern-only server (the 2026-07-28 era removed it) answered the probe late, which was dropped as
  cancelled, then refused `initialize` with -32601, and the connection failed. Any modern-only
  server slower than the probe to answer its first request could never connect. A traced run on main
  (probe 1 s, fixture asleep 2 s before serving): discover sent at 0, `initialize` at 1.05 s; the
  server read discover, the cancel and `initialize` at 2.16-2.18 s; the freeze came at 2.37 s, after
  the refusal, with that diagnostic.
- Fix: `mcp_handshake()` probes a server that refuses `initialize` after leaving the probe
  unanswered once more, in the probe window (it has just answered, so it is running); a modern
  answer wins and is cached, anything else re-raises the refusal. With `protocol: "modern"` nothing
  falls back, so its probe waits the request timeout; before, a slow modern-only server forced
  modern failed the same way ("did not answer as a 2026-07-28 server"). An answered probe, a forced
  or cached legacy era (D-165 item 1) and a legacy server that accepts `initialize` are unchanged.
- Test: the stdio fixture takes `--delay=S` (`local_mcp_fixture(delay =)`): its first answer comes
  S s after it reads the request, so a probe shorter than S times out whatever the write's delivery
  took. "a modern server that answers the probe late is probed again after refusing initialize"
  (probe 2 s, delay 4 s; the second probe must fit the window, and a ready Windows writer's first
  ACK took at most 0.57 s, D-246): modern era, cached, five tools, and the server read discover,
  the cancel, `initialize`, discover, `tools/list`. "a forced modern server's probe waits as long
  as any request" (probe 0.5 s, delay 2 s): modern, five tools, and the server read discover,
  `tools/list`. "a modern stdio server is found by the probe, ..." (115336083629) asserts that no
  `initialize` is sent, which a start beyond the probe breaks: it probes for 30 s, the fixture's
  request timeout and 5.7 times the 5.24 s cold start (D-246), instead of 5 s.
- Measurements (macOS, 16 cores, load 4.8-12.6 from other agents; the real CI test through
  `test_file(desc =)`, one process per loop): main 0/200 (each 0.50 s p50, 1.55 s max). Emulated
  slow starts: gptr's first write to a server sleeping 1 s inside the window, as the Windows
  writer's cold start does, with the probe at 0.5 s: main 200/200 fail with the CI signature; with
  the probe at 1 s and that write delayed 0.6, 0.8, 0.9 or 0.95 s main passes 40/40, at 1.0, 1.05,
  1.1, 1.2 or 1.5 s it fails 50/50: the tools go missing exactly when the first answer comes after
  the window. The test's body with the fixture asleep 2 s before serving (probe 1 s): main 30/30
  fail with the diagnostic. After (the first version): 0/200 plain, 0/200 with the delayed write,
  90/90 across the sweep, 0/30 asleep (each server log: discover, cancel, `initialize`, discover,
  `tools/list`); its test (probe 0.5 s, delay 2 s): main 50/50 fail, after 0/200 (2.37 s p50,
  2.66 s max). Final code (load 3.5-10.3): the test 30/30 (4.29 s p50, 4.78 s max; main 5/5 fail
  with -32601), the forced modern test 30/30 (2.28 s p50, 2.47 s max), the CI test's body with the
  first write delayed 1 s and the probe at 0.5 s 30/30 (1.33 s p50, 2.35 s max).
- Reviews: r1 3 findings, all applied. (1) The first version probed again with the request timeout
  (60 s), so a server that ignores the probe and refuses `initialize` (a strict legacy server) held
  every session start 60 s longer before the same diagnostic, and its era is never cached: with
  defaults and exposure direct main 6.15 and 6.22 s (r1's runs), the first version 66.13 and
  66.33 s, final 10.30-11.35 s (3 runs, load 4.3-10.3). (2) With `protocol: "modern"` an unanswered
  probe aborted before the fallback: delay 2 s, probe 0.5 s, main 5/5 and the first version 10/10
  "did not answer as a 2026-07-28 server", final 30/30 connect. (3) "a modern stdio server is found by the
  probe, ..." with gptr's first discover write delayed 6 s connects through the second probe but
  sends `initialize` 5/5 at the 5 s probe; at 30 s it is probe-only 5/5.
- Red: `^mcp-client$` on main with the first version's test FAIL 1 PASS 176 ("MCP server fixture
  answered initialize with error -32601"); on the first version with the forced modern test FAIL 1
  PASS 179 ("did not answer as a 2026-07-28 server"). Green: `^mcp-client$` PASS 182 SKIP 1;
  `^mcp-` PASS 810 SKIP 1 (45 s, load 8.7); `^(agent-|session-)` PASS 2619 (96 s, load 6.5);
  `^(lint-rules|arch-layers)$` PASS 90; lint clean.
- Deviations: D-165 item 5 (edited in place). Open: not yet run on hosted Windows. A slow start
  costs the probe window plus two round trips (one more window when the server neither answers
  the probe nor accepts `initialize`), and a dual-era server that starts slowly is still taken as
  legacy (cached for 7 days), which works. A hung server forced modern now fails after the request
  timeout instead of 5 s.

## Task FIX-16 - Cheat-sheet review: doc (2026-10-22, #PR)

### paths-1 - Memoise the *.Rproj probe of project_root() by directory mtime
- Findings 3, 36, 69, 83, 118, 159, 178; 60 and 157 (sessions-1, merged here).
- Red: FAIL 2 in `^utils-paths$` (PASS 154), with the listing moved into `dir_list_rproj()` and
  no memo: 11 walks from `a/b` listed `a` and `b` 22 times (expected 2), and an unpinned fake
  `peter()` call from a marker-less temp dir listed an ancestor again at an unchanged mtime.
- Cause: `project_root()` walks every ancestor up to `/` on each of the 80 to 160 calls of one
  `peter()` call, and `is_project_dir()` listed each unmarked one for `*.Rproj`, uncached. Under
  macOS `$TMPDIR` (79k to 107k entries) one listing takes 0.2 to 0.8 s: 9 to 66 s per offline call,
  and a false "Checkpoint scans ... take longer than gptr.checkpoint_scan_budget" notice, as
  `ckpt_prune()` walks inside the timed scan. The suite pins the root, so no test walked.
- Fix: the four stat probes stay live; the listing's answer is kept per directory in `the$rproj`
  and redone when `file.mtime(dir)` changes, as adding, removing or renaming an entry does.
- Green: `^utils-paths$` PASS 156; `^(utils-paths|aaa-state|arch-layers|lint-rules|gptr-config|
  ckpt-files)$` PASS 1052 (NOT_CRAN=true). Lint clean. Fake one-request call from a project under
  `$TMPDIR` (79,229 entries): main 6.37 and 6.05 s, fix 1.08 and 1.01 s (86 and 83 walks; 11, then
  0 listings).
- Deviations: none. Open: an `*.Rproj` created within the mtime granularity of a cached listing
  (2 s on FAT) is seen only at the directory's next change.

### ckpt-1 - Time only the walk against gptr.checkpoint_scan_budget
- Findings 150, 196.
- Red: FAIL 2 in `^ckpt-files$` (PASS 251): with `ckpt_prune()` slowed by 0.3 s and the budget at
  0.25 s, a fake `peter()` call in mode auto whose `r` call writes `out.txt` in an empty
  marker-less project printed the "Checkpoint scans of ... take longer than
  gptr.checkpoint_scan_budget" notice and set the tracker's `per_turn`.
- Cause: `ckpt_files_after()` timed all of `ckpt_files_step()`, which includes
  `ckpt_prune()` -> `workspace_root()` -> `project_root()` on every walk and every predicted path,
  and the blob-store root while storing; a slow root lookup alone switched the session to per-turn
  scans and the notice blamed the scan.
- Fix: the tracker computes its prune pattern once (`ckpt_files_tr()`: `prune`); `ckpt_walk(root,
  prune = ckpt_prune(root))` and `ckpt_walked()` use it; `ckpt_files_scan()` notes the walk's own
  time in `tr$walk_secs`, which `ckpt_files_after()` compares with the budget.
- Green: `^ckpt-files$` PASS 253, with a new guard that a walk slowed past the budget still
  switches once with one notice; `^(ckpt-.*|utils-paths|windows-security|windows-link-policy|
  arch-layers|lint-rules)$` PASS 974 SKIP 12 (Windows only; NOT_CRAN=true). Lint clean. One
  `after()` in an empty project with `ckpt_prune()` slowed by 0.3 s (3 runs, load 11): before
  0.31 to 0.37 s and per-turn mode, after 0.001 to 0.06 s (walk 0.001 to 0.046 s), no switch.
- Deviations: none; the documented contract already says walk time (`gptr.checkpoint_scan_budget`
  in `?gptr_options`, P16). Two tests follow the new signature (a hand-made tracker carries
  `prune`; the FIFO test's `ckpt_walk` mock takes it). Open: the prune pattern is fixed when the
  tracker is made, as its root is. `.gptr/` is pruned at any depth, so only `tempdir()/gptr` can
  escape it: when the root contains `tempdir()` and a `setwd()` mid-session leaves `.gptr/`.

### doc-1 - Keep pending sidecars of documents outside .gptr/ where every process finds them
- Findings 11, 15.
- Red: FAIL 4 in `^doc-io$` (PASS 679): in a project without `.gptr/`, `doc_sidecar_path()` was
  under `tempdir()/gptr`; a child Rscript acting as a Jupyter kernel queued its cell's block and
  exited, then `gptr_doc(nb, sync = TRUE)` here said nothing and wrote no cell. With the old path
  only, a child killed by SIGKILL after one recorded call: FAIL 2, "No pending blocks for job.R."
  and 0 blocks.
- Cause: `doc_sidecar_path()` fell back to `doc_root()`, `tempdir()/gptr`, when the document's
  project had no `.gptr/` (`.git` or `DESCRIPTION` do not count): each process looked in its own
  `tempdir()`, R deleted the kernel's at exit, a killed run's was orphaned. `doc_sync()` returned
  0 silently and `gptr_doc()` dropped the count.
- Fix: without `.gptr/` the sidecar is `R_user_dir("gptr", "cache")/pending/pending-<sha1>.json`
  (`doc_sidecar_write()` already makes the folder and a 0600 file; trust checks and the legacy path
  follow); `doc_sync()` informs "Wrote N block(s) into <doc>." or "No pending blocks for <doc>.";
  `gptr_doc(sync = TRUE)` leaves a dead run's recovery to `doc_sync()`, so the count includes it.
- Green: `^doc-io$` PASS 690; `^(doc-.*|arch-layers|lint-rules|utils-paths)$` PASS 2660 SKIP 3
  (repr not installed; Windows only); `^(doc-io|doc-formats|doc-replay|doc-export)$` PASS 1756
  (NOT_CRAN=true). Lint clean. Rd regenerated; plan checks pass.
- Deviations: D-249 (new). Not in the plan: `gptr_doc(sync = TRUE)` no longer runs
  `doc_recover()` first (it applied a killed run's blocks, and the sync then said "No pending
  blocks"); two existing syncs in test-doc-io and test-doc-formats now assert the message.
- Open: `gptr_cache("info")`, which the conflict warning names, lists only the workspace root's
  sidecars, not `pending/`; `doc_lock_dir()` still uses this process's workspace root, so two
  processes recording one document outside `.gptr/` do not exclude each other (finding 15).

### doc-2 - Say when a script call is not recorded because gptr_doc() bound another document
- Findings 22, 149, 174.
- Red: FAIL 2 in `^doc-replay$` (PASS 613): bound to `out.R`, non-interactive, `record` unset, a fake
  `peter()` call in `fk.R` run by `source()` and one in `job.R` under a mocked `Rscript --file=` gave
  no notice (out.R absent and both scripts unchanged, as expected).
- Cause: `doc_locate()` sites a call in the document that holds it; the binding is consent for its own
  path and the target only of calls in no document (console, `-e`, stdin). Unable to ask, `doc_keep()`
  dropped the site before `doc_upsert()`, whose "no write consent" notice was never reached.
- Fix: `doc_keep()` informs a `notice` once per document when a call that could record (record not
  FALSE, not replay mode) gets no consent while a binding exists: "gptr did not record this call: it is
  in fk.R, but gptr_doc() bound out.R. Calls are recorded into the document that holds them; run
  gptr_doc("fk.R") to record them there." No binding stays silent (IC-45). `?gptr_doc`, 04 §6.4 and
  IC-45, 03 §4.3 say what a binding covers; the help also how console turns are written (IC-49).
- Green: `^doc-replay$` PASS 615 (dropping the guards fails the silent cases: no binding, record FALSE,
  replay); `^(doc-.*|arch-layers|lint-rules)$` PASS 2519 SKIP 2 (NOT_CRAN=true). Lint clean. Rd
  regenerated; plan checks pass. Installed build, real `Rscript driver.R`, fake provider: one notice for
  two calls, no out.R, driver.R unchanged; a self-bound script records both blocks, no notice.
- Deviations: D-249 (extended). Open: an interactive run whose answer for a document is a remembered
  "off" also gets the notice once while another document is bound.

### doc-3 - Sheet: gptr_doc() binds this R session; bind quarto and Knit documents in their setup chunk
- Finding 19, its rendering half (doc-1 fixed the notebook and crash-recovery half).
- Red: none (wording). Installed build, fake provider, quarto 1.10.18: a `.qmd` bound at the
  console, then `quarto render`, got no block and no message; `rmarkdown::render()` of an `.Rmd`
  in the binding session recorded one.
- Cause: a binding is this R process's consent (`the$doc_binding`; 04 §6.4 already says "this R
  process"). `quarto render`, `quarto::quarto_render()` and RStudio's Knit and Render buttons knit
  in another process, which cannot ask, so `doc_keep()` drops the call and, unbound, says nothing
  (IC-45). The vignette's "Bind the report, run it with its normal renderer" and "Use `quarto
  render analysis.qmd`" was a recipe that records nothing.
- Fix: `script-as-history` says a binding belongs to the process that made it, keeps the in-process
  `rmarkdown::render()` example, and says to bind a document rendered elsewhere in its own setup
  chunk, shown as `library(gptr); gptr_doc("analysis.qmd")`. The `.Rmd` is the knitted `.Rmd.orig`.
- Green: a setup-chunk binding plus `quarto render` wrote `#| label: gptr-<id>`, outside and inside
  a `gptr_init()` project. `precompute.R script-as-history`: 0 problems, output byte-identical to
  the edited `.Rmd`. `^zzz$` PASS 145 (NOT_CRAN=true). Lint: the `.Rmd` is clean; the `.Rmd.orig`
  keeps its one lint from main (`mode = auto` in an `eval = FALSE` chunk, line 338).
- Deviations: none (the contract already binds this process). Not in the plan: no
  `gptr_config(record = "auto")` alternative. Measured with `quarto render`, it records only at
  user scope outside a `gptr_init()` project: the default scope is this session there, and inside
  a project the template's `record: "ask"` holds against a user "auto", and an untrusted
  project's own "auto" cannot loosen it. Open: none.

### doc-4 - Sheet: recording under Rscript or render() needs auto mode or allow rules
- Finding 16, its wording half (config-4 in the models group and gate-hint in the orchestration
  group carry its code items).
- Red: none (wording). Installed build, fake provider whose `r` call runs `fit = lm(mpg ~ wt,
  data = mtcars)`, `Rscript` on a script that binds itself with `gptr_doc()`: with default
  settings, rc 1, "The run stopped: `r` needs approval and no one can answer in this run", no
  block; the same in a `gptr_init()` project whose user level is auto.
- Cause: in the default manual mode a change waits for approval, and `gptr_can_prompt()` is FALSE
  under `Rscript` and while knitting (`is_knitting()`), even from an interactive console, so the
  gate stops the run before any block is written. The vignette's driver and its
  `rmarkdown::render()` example never said a mode was needed.
- Fix: `script-as-history` says recording needs the agent's code to run, that nobody can approve
  under `Rscript` or in `rmarkdown::render()`, and to run `gptr_config(mode = auto, .scope =
  "session")`, pass `mode = auto` or add `gptr_permissions()` rules; replays need no approval.
  The R Markdown section points back to it. Session scope, because it holds inside a
  `gptr_init()` project with or without config-4. The `.Rmd` is the knitted `.Rmd.orig`.
- Green: session scope and the call's `mode = auto` each wrote the block (rc 0), also in that
  `gptr_init()` project (effective mode manual there); `GPTR_REPLAY=replay` of the recorded
  script in manual mode rebuilt `fit` without asking. `precompute.R script-as-history`: 0
  problems, output byte-identical to the edited `.Rmd`. `^zzz$` PASS 145 (NOT_CRAN=true). Lint:
  the `.Rmd` is clean; the `.Rmd.orig` keeps its one lint from main (`mode = auto`, now line 350).
- Deviations: none (the gate is intended). Open: an empty block when the model passes
  `record = false` is by design and rare, so neither the sheet nor the vignette mentions it.

### doc-5 - The undone-block notice names replay = "record", the mode that regenerates it
- Finding 13.
- Red: FAIL 4 in `^doc-replay$` (PASS 625): under `auto` and `replay`, an undone team block's
  notice said "or run live to regenerate it" and did not name `replay = "record"`.
- Cause: G7 section 3.8's undone row gave the notice "run live to regenerate" while its `live`
  column is "run, no write"; `doc_skip_undone()` copied the one, `doc_decide()` the other. So
  `gptr_source(f, replay = "live")` called the model, left the block inert and wrote nothing.
- Fix: the notice ends `or run it with replay = "record" to regenerate it.`; `?gptr_source`
  and the `script-as-history` modes table say an undone block runs under `"live"` without being
  rewritten and `"record"` regenerates it; G7 3.8 and the P15 plan's copy say the same.
- Green: `^doc-replay$` PASS 629, with an end-to-end guard (fake provider, bound `.R`): an
  undone block stays undone and byte-identical under `"live"`, then `"record"` gives
  `regenerated` and `fresh`; `^(doc-.*|ckpt-rewind|arch-layers|lint-rules)$` PASS 2774 SKIP 2
  (NOT_CRAN=true). Lint clean (the `.Rmd.orig` keeps its one lint from main, line 350). Rd
  regenerated; plan checks pass. `precompute.R script-as-history`: 0 problems, output
  byte-identical to the edited `.Rmd`.
- Deviations: none (the G7 3.8 behaviour stands; only its notice text changed). Not in the plan:
  the guard scripts six replies, as it makes three model runs.
- Open: `gptr_source()` still lists the `"live"` run of an undone block as `NA`, which its
  `@return` keeps for blocks no call touched; making `"live"` regenerate undone blocks is the
  maintainer's call.

### doc-6 - Sheet: say where replay = "live" re-asks the model
- Finding 14, its driver half (doc-5 fixed the undone half; the sheet line is S26).
- Red: none (wording). Installed build, fake provider, a self-bound `live.R` with
  `peter(..., mode = "auto", replay = "live")`: the first `Rscript` made 2 requests and wrote
  the block; the second made 0, warned "Block 2d55a7 of live.R was not regenerated: under
  source() or Rscript the recorded code runs anyway, so it was replayed.", and left the file
  byte-identical; `gptr_source("live.R")` then listed it `regenerated` with a new sha.
- Cause: `doc_decide()` regenerates only under a driver that can skip the old block
  (`gptr_source()`, knitr or Quarto, an IDE, Jupyter); under base `source()` or Rscript every
  regeneration downgrades to replay with `replay_downgraded` (architecture 6.9.3). The modes
  table said `"live"` rewrites recorded blocks without naming a driver.
- Fix: the `script-as-history` live row names the four drivers and says a recorded block
  replays with a warning under base `source()` or Rscript. It does not say "at the console": a
  call typed there is a transcript turn and never re-asks a recorded block. The `.Rmd` is the
  knitted `.Rmd.orig`.
- Green: `precompute.R script-as-history`: 0 problems, output byte-identical to the edited
  `.Rmd`. `^zzz$` PASS 145 (NOT_CRAN=true). Lint: the `.Rmd` is clean; the `.Rmd.orig` keeps its
  one lint from main (`mode = auto`, line 350).
- Deviations: none (the downgrade is intended). Open: the `replay_downgraded` warning itself says
  "or run the call interactively to regenerate it", which holds in an IDE but not at a plain
  console.

### doc-7 - Transcript header names gptr_source(replay = "live")
- Finding 44.
- Red: FAIL 2 in `^doc-formats$` (PASS 252): a new transcript's fourth line was
  `# options(gptr.replay = "live") re-asks the model.`. FAIL 1 in `^doc-replay$` (PASS 635) on the
  same line of a console transcript recorded with the fake provider; its behaviour already held.
- Cause: `doc_transcript_header()` pointed to the option, which only `gptr_source()`, knitr, an IDE
  or Jupyter can honour; under `source()` or Rscript `doc_decide()` downgrades a regeneration to
  replay with `replay_downgraded` (architecture 6.9.3), so following the hint never re-asked.
- Fix: the line is `# gptr_source("<file name>", replay = "live") re-asks the model.`; the
  `source()` line above it stays.
- Green: `^(doc-formats|doc-replay)$` PASS 890, with a guard (fake provider): `source()` of the
  recorded transcript under `gptr.replay = "live"` warns `replay_downgraded` and sends nothing,
  `gptr_source(t, replay = "live")` sends two requests and gives `regenerated`;
  `^(doc-.*|arch-layers|lint-rules)$` PASS 2541 SKIP 2 (NOT_CRAN=true). Lint clean.
- Deviations: none (04 §11.5 names only the `source()` line). Open: the name is the file's at
  recording; a renamed or moved transcript keeps the old one.

### doc-8 - No temporary machine-log path in a transcript header
- Finding 18.
- Red: FAIL 2 in `^doc-formats$` (PASS 257): `doc_on_agent_end()` with a console site in a
  project without `.gptr/` wrote `# machine log: /private/var/folders/.../Rtmp.../gptr/sessions/
  <stamp>_<id>.jsonl`.
- Cause: without `.gptr/`, `workspace_root()` is `tempdir()/gptr`, which R deletes at exit;
  `doc_on_agent_end()` copied the session file's absolute path into `site$session_file`, and the
  durable transcript named a file gone after exit.
- Fix: `doc_on_agent_end()` leaves `session_file` NULL when the log is inside exactly
  `tempdir()/gptr`; `doc_transcript_header()` then writes `# machine log: none kept (gptr_init()
  keeps session logs in .gptr/)` (was `(none)`). 04 §11.5's transcript row says so.
- Green: `^(doc-formats|doc-replay)$` PASS 895 (a `.gptr/` project under `tempdir()` keeps
  `.gptr/sessions/<file>`); `^(doc-.*|arch-layers|lint-rules)$` PASS 2546 SKIP 2 (NOT_CRAN=true).
  Lint clean; plan checks pass. Installed build, fake provider, an `Rscript -e` console turn bound
  with `gptr_doc("log.R", format = "transcript")`: "none kept" outside `.gptr/`, the kept relative
  log inside it.
- Deviations: D-249 (extended). Open: replayed text comes from the S2 cache, also in
  `tempdir()/gptr` without `.gptr/`, so a later process's replay has `text` NA; `doc_conflict`'s
  "the session log has it" is equally untrue there after exit.

### doc-9 - /doc and /status see a gptr_doc() binding before the first prompt
- Finding 25.
- Red: FAIL 4 in `^console-commands$` (PASS 97): with `gptr_doc("log.R")` bound and no session,
  `cmd_doc_site(NULL)` was NULL, `/doc` said "No document is bound." and `/status` had no
  `document` line.
- Cause: `cmd_doc_site()` returned NULL for a NULL session without asking the doc.site service,
  whose answer without a session is the `gptr_doc()` binding (`doc_site_service()`, which
  `prompt_doc()` asks the same way); `cmd_status()` printed no document line before a session.
- Fix: `cmd_doc_site()` asks the service with the session as given; `/status` before the first
  prompt adds `document  <path>` or `(none)`. The `script-as-history` transcript paragraph says
  an `.R` binding is the transcript (`format = "transcript"` only labels it); that it holds each
  console `peter()` call and prompt as `s_<id> = peter("prompt", <context names>)` with its
  block, the console's `!`, `!!` and fenced R lines under `# direct R (no model)` and slash
  commands as comments; and that other code typed at R's `>` prompt is not recorded, so a
  transcript using objects made there fails on replay: make them with `!code`. The `.Rmd` is the
  knitted `.Rmd.orig`.
- Green: `^console-commands$` PASS 101; `^(console-.*|perm-plan|doc-replay|arch-layers|
  lint-rules)$` PASS 2690 SKIP 1 (INFRA-03, interactive R on CI; NOT_CRAN=true). Lint clean (the
  `.Rmd.orig` keeps its one lint from main, now line 356). `precompute.R script-as-history`: 0
  problems, output byte-identical to the edited `.Rmd`. Rd unchanged.
- Deviations: none (03 §6.17 lists `/status` and `/doc` without their lines; the doc.site service
  already answered the binding without a session). Not in the plan: `/status` before a session
  gains the `document` line, as it had none to correct.
- Open: the transcript still does not see R's own `>` prompt (no task callback; P15/IC-49). The
  verdict's other passing bug, `eval_guard()` refusing a `q` bound to a non-function, is the
  orchestration group's guard-1.

### doc-10 - Mark every cut of recorded #> output with the right count
- Finding 24.
- Red: FAIL 9 in `^(doc-blocks|tool-r)$` (PASS 451), fake `peter()` into a bound `.R`: `for (i in
  1:30) print(i)` and `summary(fit)` kept 12 lines with no marker; three expressions said "(3 more
  lines)" for 11; `doc$output_lines = 30` with the option unset still kept 12; `peter$describe(x)`'s
  two lines stayed under `sum(x)`; `r_doc_outputs()` returned a flat vector.
- Cause: `r_doc_outputs()` cut each expression to the option's 12 lines silently and flattened them;
  `doc_output_lines()` cut again and counted only the survivors, and `doc_turn_r()`'s `outs[kept]`
  never met a per-expression list.
- Fix: `r_doc_outputs()` keeps `list(lines, n)` per expression, capped by `doc_max_output_lines()`
  (moved to `eval-format.R`, as an L4 service file may be called from `tool-r.R`); `doc_output_lines()`
  shows lines up to the first cut one, cuts once and counts `sum(n)`; a flat vector still renders.
- Green: `^(doc-blocks|tool-r)$` PASS 460; `^(doc-.*|eval-format|tool-r|mcp-server|arch-layers|
  lint-rules)$` PASS 2879 SKIP 2 (repr), `^(mcp-recording|eval-core)$` PASS 346 (NOT_CRAN=true). Lint
  clean; plan checks pass. `local_doc_e2e()` and `doc_e2e_source()` moved to `helper-doc.R`.
- Deviations: D-249 (extended; 04 §4.4 `outputs`, §11.5). Open: none.

### doc-11 - Write a known zero cost as cost=0 in block headers
- Finding 122.
- Red: FAIL 2 in `^(doc-blocks|doc-replay)$` (PASS 972): a turn whose answers cost a known `0`
  had no `cost` header key; a fake `peter()` call recorded into `analysis.R` listed
  `gptr_blocks(f)$cost` NA while `s$cost` was 0.
- Cause: `doc_block_lines()` wrote `cost=` only when known and above 0, and `doc_block_row()` reads
  a missing key as NA, the value IC-74 keeps for unknown.
- Fix: the guard is `tb$cost_known`; an unknown cost stays omitted. `?gptr_blocks` says `cost` is
  `0` for a known free route and `NA` when unknown or not recorded; 04 §11.5's `cost` row says when
  it is written.
- Green: `^(doc-.*|subagent-team|ckpt-rewind|session-object|mcp-recording|console-commands|
  arch-layers|lint-rules)$` PASS 3820 SKIP 2 (repr; NOT_CRAN=true). Lint clean; Rd regenerated;
  plan checks pass. The IC-74 test's local-model case now expects `"0"` (its cost was a known 0).
- Deviations: D-249 (extended). Open: none.

### replay-1 - Replaying into the session that recorded the block adds no turn
- Finding 84.
- Red: FAIL 5 in `^(doc-replay|session-object)$` (PASS 1171): a two-block pipe chain recorded with
  `gptr_source(replay = "record")` read 4 turns after `gptr_source(replay = "replay")` in the same
  process, the next live turn was 5 and the user turns 1, 2, 5; `session_replay_new()` advanced a
  live session whose path held the block's `gptr.doc_block` entry.
- Cause: `replay_mark(advance = TRUE)` (both `session_replay_apply()` and `session_replay_new()`'s
  live-session branch) skipped only blocks in `seen`, which recording never fills, so the session
  that already held the turn gained one per block.
- Fix: `replay_mark()` advances only when `replay_holds_block()` finds no `gptr.doc_block` entry
  for the block, not undone, on the active path; it still records `gptr.replay`, `seen` and
  `value=` (a session rebuilt from JSONL holds the block and needs its value). IC-46 says so.
- Green: `^(doc-replay|session-object)$` PASS 1176; `^(doc-.*|session-.*|subagent-team|ckpt-rewind|
  arch-layers|lint-rules)$` PASS 4577 SKIP 2 (repr; NOT_CRAN=true). Lint clean; plan checks pass.
- Deviations: D-249 (extended). Open: replaying block 1 into the live session after turn 2 records
  its `gptr.replay` and `value=` at turn 2, the session's current turn.

### replay-2 - Record gptr_return(<expression>) so replay restores the value
- Findings 155, 151, 114 (their expression half; replay-3 has fan-out values, store-1 `$text`).
- Red: FAIL 17 in `^(doc-blocks|doc-replay|doc-export|doc-io)$` (PASS 1894): fake `r` code `fit =
  lm(mpg ~ wt, mtcars)\ngptr_return(coef(fit))` recorded `value=coef(fit)` and dropped the line; a
  same-process `gptr_source(replay = "replay")` gave `$value` NULL with "value `coef(fit)` (turn 1)
  is not bound in this R process"; a `GPTR_REPLAY=replay Rscript` replay failed its value check
  with and without `.gptr/`; a plain export held no line computing it.
- Cause: `gptr_return()` boxes an expression under its deparsed label, `r_new_value_name()` hands
  the label on, `doc_turn_r()` wrote it as `value=` and `doc_drop_expr()` cut the call, so replay
  looked the label up as a binding name and nothing in the document recomputed it.
- Fix: `doc_rewrite_return()` turns a top-level `gptr_return(<one unnamed argument, not a name>)`
  into `.gptr_value_<block id> = (<argument>)` (backquoted until `doc_prepare()` fills the id into
  the body and header); `doc_turn_r()` writes that name, keeps a syntactic name and omits a label.
  Replay uses the name path unchanged. `?gptr_return`, 04 §4.4, §7.15, §11.5, IC-48, 03 §6.9.3.
- Green: PASS 1911; `^(doc-.*|gptr-sdk|subagent-team|session-object|session-store|mcp-recording|
  tool-r|northstar|ckpt-rewind|console-commands|copy-tools|arch-layers|lint-rules)$` PASS 4442 SKIP
  2 (repr; NOT_CRAN=true). Lint clean; Rd regenerated; plan checks pass. Installed build, fake
  provider, a self-bound `analysis.R`: the block reads `.gptr_value_c5b47c = (coef(fit))`; the
  same-process and `GPTR_REPLAY=replay Rscript` replays print the coefficients, 0 requests, file
  unchanged.
- Deviations: D-249 (extended). Not in the plan: the Rscript case is in test-doc-io.R, beside its
  child-script helpers; the bare-name case is the existing acceptance-4 test; no test-doc-io case
  assumed a dropped expression line.
- Open: a same-process replay into an environment other than the recording one (and not the
  global one) still resolves `value=` in the recording home ("not bound"; a bare name gets the
  object of recording time); a `gptr_return(<expression>)` inside braces or a branch, or with its
  name split over lines, is not rewritten and its value is not recorded.

### replay-3 - Record team and fan-out child code and values for replay
- Findings 66, 65, 119 (their fan-out and team half; replay-2 has expressions, store-1 `$text`).
- Red: FAIL 17 in `^doc-replay$` (PASS 670): a fake fan-out
  `f = peter("Average .x", list(a = c(1, 2, 3), b = c(10, 20)), parallel = 1)` whose children ran
  `m = mean(.x[[1]]); gptr_return(m)`, recorded through `gptr_source()`, wrote
  `children="a:<sid>,b:<sid>"` and no child code, and `f$value` was `list(a = NULL, b = NULL)` in a
  simulated later process with and without the session store and S2 answers; the same for
  `gptr_return(mean(.x[[1]]))`; a one-agent team running `n = nrow(mtcars); gptr_return(n)` gave
  `tm$x$value` NULL with and without `export = "n"`; a three-field `children=` entry was skipped.
- Cause: `doc_team_block_lines()` wrote a child's code only when it had exports and never its value
  name; `doc_replay_team()` built each child with no `value=`, and a replayed fan-out child's home
  had no `.x`.
- Fix: `doc_session_code()` also gives the latest `value=` name; a child with one gets its code in
  `local({...}, envir = gptr_resume(block =, child =)$envir)` and the entry
  `<name>:<session id>:<value>` (replay-2's hidden name for an expression, its token filled in with
  the header's). `doc_replay_team()` reads two or three fields and passes the third as the child's
  `value=`. `route_fanout_run()` binds each replayed child's element as `.x` in its home
  (`subagent_fanout_element()`, shared with `subagent_fanout_spec()`). `replay_rebuild()` keeps no
  value record past the recorded turn: the same-process replay advanced a team child and stored a
  turn-2 copy record without its payload, which hid the value in the next process (the last red,
  FAIL 1: no exports, store kept). 04 §11.5 `children` and body, IC-46, IC-47; 03 §6.9.3; P15; the
  one teams-and-background paragraph.
- Green: `^doc-replay$` PASS 689; `^(doc-.*|session-.*|subagent-.*|copy-subagent|northstar|
  ckpt-rewind|arch-layers|lint-rules|console-commands|mcp-recording|gptr-sdk|tool-r)$` PASS 5687
  SKIP 3 (repr; Windows worker; NOT_CRAN=true). Lint clean; no Rd change; plan checks pass.
  Installed build, fake provider, a self-bound `analysis.R` in a `gptr_init()` project with that
  fan-out and team: recording printed `2 15`, `32`, sum 17 (6 requests); the same-process replay, a
  `GPTR_REPLAY=replay Rscript` run and one without `.gptr/sessions` and `.gptr/cache/s2` printed the
  same with 0 requests, rc 0, file unchanged.
- Deviations: D-249 (extended). Not as planned: the fan-out route (P19) binds `.x`, as
  `doc_replay_team()` may not call the fan-out helpers (IC-33), and binds only `.x`, all a live
  child's home holds (`.e1` stays in its private values environment); `replay_rebuild()`
  (session-object.R) was not in the plan; later processes are simulated in the tests (live table,
  replay table, and for the last one store and S2 cleared), the subprocess is the live check.
- Open: a same-process replay still advances a live team child one turn (replay-1 covers blocks); a
  replayed fan-out child keeps `.x` in its home (a live one's is removed when it settles); a child
  name holding `:` or `,` has no replayable entry; a child value whose code was not recorded replays
  "not bound", as a block's does.

### replay-4 - gptr_return() outside a run prints a one-time notice
- Findings 138, 190.
- Red: none (docs). The new test passes on main: with replay off, the first top-level
  `gptr_return(1)` signals the `gptr_message_notice` "only designates a value", the second is
  silent, and so is a call under `gptr.quiet`; the help page's own example prints it.
- Cause: the code follows IC-48 (a once-per-session notice, silent while replaying); `?gptr_return`
  and 03 §4.3 copied "returns its argument invisibly and does nothing else".
- Fix: both say it designates nothing and the first such call in an R session prints a one-line
  notice, silent while a document is replayed, with `options(gptr.quiet = TRUE)` or
  `suppressMessages()`.
- Green: `^(gptr-sdk|arch-layers|lint-rules)$` PASS 188 (NOT_CRAN=true). Lint clean; Rd
  regenerated; plan checks pass.
- Deviations: none. Open: the notice goes to stdout, like every `gptr_inform()` display.

### sessions-26 - Say that s$value keeps the newest returned value
- Finding 164 (moved from the sessions group: it edits `?gptr_return` after replay-2 and replay-4).
- Red: none (docs). The new session-level test passes on main: a fake session whose turns run
  `gptr_return(1)`, `gptr_return(2)` and nothing reads `$value` 2, `$turns` 3, `$text` "ok"; a
  fourth turn running `gptr_return(NULL)` reads NULL.
- Cause: `session_value_get()` returns the newest designated value of any turn, by design (G3, the
  existing "latest designated value" test), which a pipe such as `s |> peter("Explain the
  result.")` relies on; `?gptr_return` and `?peter` called it the run's result.
- Fix: `?gptr_return` says `$value` is the newest value designated in any turn, kept by a turn that
  designates none (`$values` by turn; `gptr_return(NULL)` clears it); `?peter`'s "Sessions and
  results" says the same, and that `$text` is the last turn's answer.
- Green: `^(session-object|gptr-sdk|gptr-gateway|arch-layers|lint-rules)$` PASS 1078
  (NOT_CRAN=true). Lint clean; Rd regenerated.
- Deviations: none. Open: the sheet's S06 and S09 lines follow in the sheet commit.

### replay-5 - Footer marks a replayed session and never prints a known zero
- Finding 21.
- Red: FAIL 2 in `^session-object$` (PASS 539): a one-turn fake session forgotten and rebuilt from
  its JSONL by `session_replay_new()` printed `idle . fake/fake-1 . 1 turn . 1.7k tokens . $0.0000`,
  as the live run did; one reconstructed from a document alone printed `0 tokens . $0.0000`.
- Cause: `session_footer()` never showed that a session was replayed, and a reconstruction holds no
  usage row, which `format_count()` and `format_cost()` print as a known zero.
- Fix: `replay_mark()` keeps the usage row count in `d$replay_rows`; while a replayed session
  still has that many rows its footer status reads `replayed`, and with none its tokens and cost
  read unknown. A live request adds a row and the footer is the usual one. `?print.gptr_session`,
  04 §5.1 (`print`, `.d` `replay_rows`), 03 §5.1.
- Green: `^session-object$` PASS 541; `^(doc-.*|session-.*|subagent-team|ckpt-rewind|
  console-commands|mcp-recording|gptr-sdk|arch-layers|lint-rules)$` PASS 4900 SKIP 2 (repr;
  NOT_CRAN=true). Lint clean; Rd regenerated; plan checks pass. Installed build, fake provider,
  a self-bound `analysis.R` run by `Rscript`, then `GPTR_REPLAY=replay Rscript`: in a
  `gptr_init()` project `replayed . fake/fake-1 . 1 turn . 3.7k tokens . $0.0000`, outside one
  `replayed . ... . unknown tokens . unknown cost`; file unchanged both times.
- Deviations: D-249 (extended). Open: the same-process replay into the recording session keeps
  its live footer (not a replayed session); outside a project the shell replay still prints no
  answer, as S2 lives in this process's `tempdir()`.

### export-1 - Sheet: state what gptr_export() admits and refuses
- Findings 26, 62 (the sheet's S27 lines follow in the sheet commit).
- Red: none (wording). `doc_export_chain()` on 15 shapes: admitted `peter("a")`, `mode = "auto"`,
  `1L, TRUE, NULL`, quoted `model`/`tools` and `peter("a") |> peter("b")`; refused a data object,
  bare `mode = auto` and `model = opus`, `.opts = list(...)`, `budget = list(...)`, `-0.5`, `NA`,
  `s |> peter("b")` and `peter("a", fit) |> peter("b")`. Fake provider: a recorded
  `s = peter("Fit it.", mtcars, mode = auto)` block is fresh and refused as "mixed or non-literal
  Peter expressions"; edited to `mode = "auto"` without the data object it stays fresh and exports
  in both formats.
- Cause: `doc_export_chain()` admits only arguments that are `NULL` or one non-`NA` atomic
  constant, by design (`?gptr_export`). A symbol or a call is not one, nor is the session that a
  later `s |> peter()` passes first. The vignette listed the other refusals but not this one, and
  named only `session$value` for the raw export's handle refusal.
- Fix: `script-as-history`'s export section names the admitted constants, the refused forms with
  the refusal's words, that a one-statement pipeline is admitted, that quoting an argument keeps
  the block fresh, `{name}` prompts ("interpolated inputs need review"), stale blocks, and
  `session$text` beside `session$value`. The `.Rmd` is the knitted `.Rmd.orig`.
- Green: `precompute.R script-as-history`: 0 problems, output byte-identical to the edited `.Rmd`.
  `^(zzz|doc-export)$` PASS 358 (NOT_CRAN=true). Lint: the `.Rmd` is clean; the `.Rmd.orig` keeps
  its one lint from main (`mode = auto`, now line 365).
- Deviations: none (the refusals are intended). Not planned: naming the line and argument in the
  refusal. Open: "later" code holds once export-2's position matching lands; until then the raw
  export also refuses code before the binding, and after an ordinary rebinding, that names a handle.

### export-2 - gptr_export() rebinds its gptr_doc() line and refuses only live handles
- Findings 27, 62 (the position bug).
- Red: FAIL 6 in `^doc-export$` (PASS 218): `gptr_doc("history.R")` and an absolute
  `gptr::gptr_doc(path = ...)` were copied verbatim in both formats, one sharing a line was
  admitted, and `gptr_source()` of the exported Peter script (fake provider, record "ask", not
  interactive) recorded no block; the raw export refused `s = "earlier"; print(s)` before `s =
  peter("one")` and `s = 1; print(s)` after it.
- Cause: `doc_export_lines()` kept every non-Peter statement, so the export bound the source, whose
  binding is consent for the source only (doc-2): its calls recorded nowhere and console turns went
  into the source. Handle names were refused in any other statement, whatever its position.
- Fix: `doc_export_bind()` finds a top-level `gptr_doc()` whose `path` literal (`match.call()`,
  nothing evaluated) names the source from its directory or the working directory; raw R comments it
  out, the Peter format writes the destination into the literal (only the file name in the same
  directory, else the full path); one sharing a line, or not read by `doc_unquote()`, is refused.
  One ordered pass keeps a handle live from its `peter()` statement until ordinary code assigns the
  name. `?gptr_export` @details.
- Green: `^doc-export$` PASS 224; `^(doc-export|doc-replay|doc-blocks|zzz|arch-layers|lint-rules)$`
  PASS 1493 (NOT_CRAN=true). Lint clean; Rd regenerated. Probe: a three-line
  `gptr_doc('sub/history.R', format = "transcript")` exported from the project root became
  `"sub/p1.R"` (same directory), the full path (another one), three comment lines (raw R).
- Deviations: D-249 (extended). From the plan: the working directory also resolves the literal (the
  verifier's fix), the literal keeps its directory part, and the commented line has no `# removed by
  gptr_export()` suffix. Open: a `gptr_doc()` assigned or with a computed path is kept; the handle
  refusal still names neither the handle nor its line.

### store-1 - Say that sessions and answers outlive R only in a .gptr/ workspace
- Findings 124, 139, 152 (the `$text` halves of 114 and 119; the sheet's S03, S12, S23 lines follow in the
  sheet commit).
- Red: FAIL 5. `^session-store$`: `gptr_resume("s0123456789")` outside a workspace said only "no stored session
  matches". `^doc-replay$`: a replay that restored no answer was silent in process, under `GPTR_REPLAY=replay
  Rscript` (exit 0, `TEXT NA`) and for fan-out children whose answers were removed.
- Cause: without `.gptr/`, `workspace_root()` is `tempdir()/gptr`, so the session store and the S2 answer cache end
  with R (intended: gptr writes only where named). Nothing said so where the loss is felt.
- Fix: both `resume_path()` store misses add "Without a .gptr/ workspace, sessions last until R exits;
  gptr_init(\".\") keeps them." when `workspace_dir()` is NULL. `doc_replay_no_answer()`, called for a replayed call
  and each team child, informs one `notice` per document and process when `$text` stays NA: "No recorded answer
  for <doc>: replayed answers ($text) are NA.", plus " gptr_init(\".\") keeps answers in .gptr/ for later R
  sessions." outside a workspace. NEWS: sessions are saved in `.gptr/` (without one, until R exits). 04 §6.5, IC-46.
- Green: `^(doc-replay|session-store)$` PASS 982 (703 + 279); `^(doc-.*|session-.*|subagent-.*|ckpt-rewind|
  console-commands|console-repl|mcp-recording|gptr-sdk|gptr-source|knitr.*|arch-layers|lint-rules|zzz)$` PASS 5884
  SKIP 3 (NOT_CRAN=true). Lint clean; no Rd change. Installed build, fake provider, two `Rscript` runs: outside a
  workspace the replay prints the notice with the hint, `TEXT NA`, exit 0, and `gptr_resume(id)` and
  `gptr_resume()` carry the hint; after `gptr_init(".")` neither error has it, a replay restores the text, still
  after `gptr_cache("clear", "s2")` (from the session file), and with `.gptr/sessions` removed too the notice comes
  without the hint.
- Deviations: D-249 (extended). From the plan: the notice keys on the outcome (`$text` NA after replay), not on a
  missing S2 record, which in a workspace or a live session is no loss (the session file or the live session holds
  the answer); the workspace text omits "the answer cache was cleared", as a copied document, a block recorded
  before `gptr_init()` or one recorded without an answer gives the same miss. Open: a piped replay keeps the
  previous turn's `$text` when its block's answer is missing (no notice there); a bare `/resume` still lists
  "# 0 rows" without the hint.

### replay-2b - A knitted first render shows a recorded gptr_return() with its block id
- Review of replay-2 (`R/doc-knitr.R`, medium).
- Red: FAIL 3 in `^doc-knitr$` (PASS 74): `knit_print()` of a live turn whose code ends in
  `gptr_return(coef(fit))` showed `` `.gptr_value_@@GPTR_BLOCK@@` = (coef(fit)) `` in its code
  fence, with and without a `gptr.doc_block` entry, and so did a first `knitr::knit()` (fake
  provider) of a report whose agent runs `gptr_return(n * 2)`.
- Cause: replay-2's rewrite leaves the hidden name backquoted with a token until `doc_prepare()`
  fills in the block id; `doc_knit_code()` printed `doc_turn_body()`'s body before that step.
- Fix: `doc_fill_id()` (both substitutions, shared with `doc_prepare()`); `doc_knit_code()` fills
  in the id of the turn's newest `gptr.doc_block` entry, else shows the line as the
  `gptr_return()` call it records.
- Green: `^doc-knitr$` PASS 77; `^(doc-.*|arch-layers|lint-rules)$` PASS 2656 SKIP 2 (repr;
  NOT_CRAN=true). Lint clean. The knit writes the block before the chunk prints, so the first
  render shows `.gptr_value_<id> = (n * 2)`.
- Deviations: none (the shown code is the block's). Open: none.

### replay-2c - Record the native-pipe form `<expression> |> gptr_return()` too
- Review of replay-2 (`R/doc-blocks.R`, medium).
- Red: FAIL 2 in `^doc-blocks$` (PASS 349): `doc_code_clean()` kept `coef(fit) |> gptr_return()`
  and `mtcars |> nrow() |> gptr::gptr_return( ) # done` as written, `returned` FALSE.
- Cause: the pipe form parses to `gptr_return(<expression>)`, so `doc_drop_expr()` kept it, but
  `doc_rewrite_return()` looked for the function name at the expression's start, found the
  argument's, and skipped it: `value=` was omitted and every replay gave `$value` NULL without a
  word, while the kept line printed the outside-a-run notice under `replay = "auto"`.
- Fix: when the top-level expression's own `PIPE` token ends on its last line, the hidden name
  and `(` go before the expression and the pipe with the call become `)`; a pipe split from its
  call over lines is kept as written, as a split call name is. IC-48 says so.
- Green: `^doc-blocks$` PASS 351 (a bare `fit |> gptr_return()` is still dropped);
  `^(doc-.*|tool-r|mcp-recording|gptr-sdk|arch-layers|lint-rules)$` PASS 2933 SKIP 2 (repr;
  NOT_CRAN=true). Lint clean; plan checks pass. Fake provider, `coef(fit) |> gptr_return()`
  recorded through `gptr_source()`: `.gptr_value_<id> = (coef(fit))`, and a simulated later
  process's replay returns the coefficients without a message.
- Deviations: D-249 (extended). Open: none.

### replay-2d - R served to a CLI route records what gptr_return() designated
- Review of replay-2 (`R/mcp-server.R`, medium; the CLI-route root cause of findings 155, 151).
- Red: FAIL 2 in `^mcp-recording$` (PASS 50): a fake model calling a probe tool that serves `fit =
  lm(mpg ~ wt, mtcars)\ngptr_return(coef(fit))` through `mcp_dispatch_local()`, recorded with
  `gptr_source()`, wrote the `.gptr_value_<id> = (coef(fit))` line but no `value=`, and a simulated
  later process's replay gave `$value` NULL.
- Cause: `mcp_serve_r()` (Claude Code, Codex) records a `gptr.mcp_r` entry without `value`, so
  `doc_turn_r()` never wrote the hidden name, and `doc_turn_body()` skips the boxed `gptr.value`
  record that could have named one.
- Fix: `mcp_serve_r()` counts the session's value records before evaluating and adds
  `value = r_new_value_name()` to the entry, as the `r` tool's `details$value`;
  `r_new_value_name()` moves from `tool-r.R` to the L4 service file `eval-format.R` beside
  `r_doc_outputs()`, as `mcp-server.R` may not call `tool-r.R` (IC-33).
- Green: `^mcp-recording$` PASS 52; `^(mcp-.*|tool-r|eval-format|doc-blocks|doc-replay|cli-codex|
  cli-claude|arch-layers|lint-rules)$` PASS 2913 SKIP 1 (Windows only; NOT_CRAN=true). Lint clean;
  plan checks pass. The relayed-Codex test's bare `gptr_return(beta)` is unchanged.
- Deviations: D-249 (extended). Open: none.

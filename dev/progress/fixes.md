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
  cases on release and oldrel-4, twice).

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

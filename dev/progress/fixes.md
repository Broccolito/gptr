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

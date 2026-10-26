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

## FIX-10 - A worker receives no closure environments beyond its own records (2026-10-06)
- Red: FAIL 2 in `^subagent-worker$` (the walk entered the registry; no `refhook`) and FAIL 2 in
  `^secrets-e2e$` (spec.rds 30 MB holding the key 15 times). Green: `^subagent-worker$` PASS 114,
  `^secrets-e2e$` PASS 36, `^(ext-plugins|secrets-e2e)$` PASS 415. Lint clean. Neighbours:
  `^subagent-` PASS 565, `^(secrets-e2e|injection-e2e)$` PASS 229, `cli-codex` PASS 248 (INFRA-16
  leg skips: gptr not installed), `^(arch-layers|lint-rules)$` PASS 19,
  `^(utils-paths|utils-hash|copy-ckpt|doc-io)$` PASS 604.
- Reviews: none recorded.
- Deviations: D-177. Open: none.

## Task CI-15 - The artifact registry tests leave no processx supervisor open (2026-10-06)
- Red: the connections gate on `^artifact-(app|registry)$` 3 -> 5, and on `^northstar$` 3 -> 5
  (processx's supervisor fifos: chromote, started by the registry's launching tests and by NS-8,
  always supervises Chrome). Fix (tests only): CI-8's per-file `supervisor_kill()` line moves from
  test-artifact-app.R to setup.R (`testthat::teardown_env()`), ending the supervisor with the run;
  NS-8 in test-northstar.R closes its browser. Green: gate
  `^(artifact-app|artifact-registry|northstar)$` 3 -> 3, PASS 543; `^northstar$` gate 3 -> 3,
  PASS 81. Lint clean. Neighbours:
  `^(artifact-|copy-artifact$|lint-rules$|northstar$|utils-options$)` PASS 603.
- Reviews: r1 1 finding (0/1/0): the per-file fix left NS-8's supervisor open (3 -> 5) -> fixed
  (suite-level).
- Deviations: none. Open: none.

## Task CI-16 - The plugin settings test unregisters the user-scope command it creates (2026-10-06)
- Red: after `^ext-plugins$` the process registry still held the user command `p17-user-ext` (1
  record, shipped to later workers). Fix (test only): the test's defer removes that record, as
  `test-secrets-e2e.R` does for `e2e-ext`; 0 records after the file. Green: `^ext-plugins$` PASS
  379, `^(ext-plugins|subagent-worker|secrets-e2e)$` PASS 529. Lint clean. Neighbours:
  `^(ext-|subagent-)` PASS 2332.
- Reviews: none recorded.
- Deviations: none. Open: none.

## FIX-11 - gptr_sessions() shows created and updated in the same time zone (2026-10-06)
- Red: FAIL 1 in `^session-store$` (America/Los_Angeles: `created` shown in UTC, `updated` from
  `file.mtime()` in local time, 25199 s apart). Fix: a stored row's `updated` is UTC POSIXct like
  `created`, the live row and the empty frame. Green: `^session-store$` PASS 253. Lint clean.
  Neighbours: `^session-(store|object|live)$` PASS 800, `^ckpt-rewind$` PASS 192,
  `^(arch-layers|lint-rules)$` PASS 19 green.
- Reviews: none recorded.
- Deviations: none. Open: none.

## PERF-2 - Stream-event redaction does constant work per event (2026-10-07)
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

## FIX-12 - A speculative keyring lookup never warns about keyring's env fallback (2026-10-07)
- Red: FAIL 2 in `^auth-secrets$` (the keyring source's `resolve`/`list` passed keyring's "Selecting
  'env' backend" warning through; hosted run 37588313491 WARN 2 at `test-auth-secrets.R:423/505`).
  Fix: both run with `options(keyring_warn_for_env_fallback = FALSE)`, restored on exit;
  `auth-store.R`'s explicit keyring references unchanged. Green: `^auth-secrets$` PASS 308 (+1
  test). Lint clean. Neighbours: `^auth-` PASS 1199 SKIP 1 (keyring installed), `^secrets` 36,
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
- `dev/ci/check-plans.py` required exactly P01..P25 and a 25-plan index, so P26 turned the Linux
  plan gate (Plan-gates.yaml, Optional-integrations.yaml) red with "Require the exact P01 through
  P25 plan set" before any check ran. Fix (CI only, `3e63a8a`): `plan_files()` takes P01..Pnn with
  no gap, duplicate or malformed name and n >= 25, and the index must cover all with zero error
  findings; `extract.py` extracts every `P<nn>-*.md` (it dropped plans above P25).
- Red: a full `check-plans.py` at base stops with the P25 message. Green: `test-check-plans.py` 8 OK
  (+2 plan-set cases); a full run 26 plans, 0 errors, 770 R blocks clean, no lints.
- Reviews: r1 1 finding (low: `extract.py` still stopped at P25) -> fixed.
- Deviations: none. Open: `build_index.py --scope` still defaults to P01-P25 (labels only);
  Plan-gates has not run on this branch (dispatch only).

## Task CI-26 - The optional-integration registry names current tests only (2026-10-18, #51)
- 7928d0f and 326fe82 renamed two cases each in `test-artifact-browser-cleanup.R` and
  `test-cli-codex.R`, but `dev/ci/optional-integrations.R` kept the old titles, so every
  Optional-integrations row selecting those files stopped at "Missing mandatory integration cases".
  Fix (CI only, `b00d681`): the registry and its two pinned copies carry the current titles; a pure
  gate test, "every approved title names a current test of its file", walks the combined registry
  by position.
- Red: the new test fails on exactly the two renamed files. Green:
  `dev/ci/test-optional-integrations.R` PASS 3737. Lint clean.
- Reviews: r1 1 finding (medium: a by-name lookup never read the guard titles) -> fixed (index
  loop).
- Deviations: none. Open: none; the gate caught the later renames (CI-57) in the optional run on
  2c9b6a4 (run 39202182790, job 117897311639) and passed on 92a2944 (run 39235001873).

## Task CI-27 - Ordinary windows-by-file runs provision R-CMD-check's Windows Python (2026-10-18, #51)
- On Windows `bp_run()` always starts the no-follow disk observer, which needs `RETICULATE_PYTHON`
  and `RETICULATE_USE_MANAGED_VENV=false`; ordinary windows-by-file set neither, so every observer
  case failed with "The optional nofollow observer requires its provisioned Python runtime" (run
  39179988023 job 117830492561; run 38839828091 job 116777121470). Fix (CI only, `f1b62da`):
  ordinary mode runs R-CMD-check's `actions/setup-python` pin (3.12.10) and provisioning step.
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
  (phases `absence-privilege-pre-backup-2`, `control-*-lookup-2`, probe 2). Fix (CI only,
  `1637f4b`): the ordinary by-file step uses pwsh; the two optional owned-child steps take the
  runner default (pwsh on Windows, bash on Linux).
- Green: both workflows parse; the folded command splits into the expected argv for Linux and
  Windows; `test-optional-dependencies.py` OK.
- Reviews: r1 1 finding (low: `shell: pwsh` also moved the Linux rows) -> fixed (runner default).
- Deviations: none. Open: the optional owned-child run of `test-proc-writer-runtime.R` under pwsh
  has not run; the ordinary pwsh run on 2c9b6a4 passed the file (853 expectations).

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

## Task CI-31 - Shell routes, scripts and knit engines run on Windows (2026-10-18, #51)
- `ec6cf5b`, `838f322`, `6ede769` (tests only): the resolution, direct-line, pipeline, timeout
  (`ps_children()` instead of pgrep), `.sh` and `#!` tests of `test-bridge-sh.R` and the
  shell-engine test of `test-bridge-lang.R` drop `skip_on_os("windows")`. New: "a background command
  line runs in the shell and kill() stops its process tree", Windows-only "without Git Bash a
  Windows command line runs in PowerShell, else in cmd", "on Windows a .sh script runs through Git
  Bash when no bash is on PATH", "a windows_only interpreter has its program on Windows and none
  elsewhere" and "the cmd and powershell engines run on Windows with UTF-8 output and exit codes".
- The elapsed bounds of the timeout test (`ec6cf5b`) and the shell-engine test (`6ede769`) go from
  10 s to 30 s on every OS, for Git Bash start-up on hosted Windows; their jobs run 57 s and 999 s,
  so a timeout kill is still proven.
- Green: `^bridge-sh$` PASS 275 SKIP 3, `^bridge-lang$` PASS 106 SKIP 4 on macOS. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: the first hosted runs found cmd output in the OEM page (CI-49) and a lost
  PowerShell exit status (CI-50, fixed by CI-66); the macOS skip of the background tree test went
  with CI-47; the background job tests' timing is CI-65.

## Task CI-32 - A bare R MCP server and the orphan sweep run on Windows (2026-10-18, #51)
- `efe55df`: "a server configured with a bare Rscript or R command runs with this R" also starts the
  fixture server with command `R` (on Windows `bin/x64/R.exe`, which starts Rterm.exe). `e1ebdb6`:
  "a killed parent leaves a grandchild that the next load's sweep removes" runs on Windows:
  processx's kill-on-close job ends the `proc_spawn()` child with its parent and `Rscript.exe` runs
  R in its own process (R's `src/unix/Rscript.c` calls `AppMain()`), so the child starts a
  `cleanup = FALSE` grandchild, which the sweep kills. Tests only.
- Green: `^mcp-client$` PASS 173 SKIP 1, `^proc-spawn$` PASS 222 on macOS. Lint clean.
- Reviews: r1 1 finding each: (high) the first sweep test followed a supposed Rterm.exe, which is
  the child itself -> fixed (grandchild); (low) a tautological `mcp_stdio_command()` check ->
  dropped.
- Deviations: D-019 item 2 corrected (P27). Open: the sweep test's read race on hosted Windows is
  CI-56; both pass in R-CMD-check run 39217189384 (9170baf).

## Task CI-33 - Paths, the walker and the edit and write tools run on Windows (2026-10-18, #51)
- Tests only: drive-path rewrites in `resolve_tool_path()` (`d43511f`); a real junction loop through
  `walk_files()`, `search_find()` and `search_grep()` (`607777a`); case-only patch moves
  (`439d00c`); read-only files refused with EACCES by write and edit (`ea3abc9`); the relative
  Rscript file fallback of `doc_rscript_file()` (`e23f44d`); two operations through a file link
  refused (`9be7d4b`); `path_class()` through junctions and file links (`c036bb2`);
  `local_symlink()` as the one link helper (`d29750a`). Windows links come from the wsec helpers,
  which skip on CRAN.
- Green: `^tool-walk$`, `^tool-edit$` PASS 170, `^tool-write$` PASS 69, `^doc-locate$`,
  `^storage-boundaries$` PASS 137, `^utils-paths$` PASS 123 SKIP 1 on macOS; the Windows branches
  were checked with `is_windows()` forced and `Sys.readlink()` emptied. Lint clean.
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
- `resolve_link_target()` took a dangling Windows link for a new file, so `write_file()` replaced
  the user's link where POSIX refuses ("it names no file"); `6541910` had pinned that replacement.
  Fix (`745397d`): a missing name that `path_listed()` finds is refused; the edit tool's
  `patch_key()` inherits it, and the dangling case of the chain test runs on Windows (NOT_CRAN).
- Red/green: simulated on macOS with the Windows stubs; `^tool-write$` PASS 69. Lint clean.
- Reviews: r1 (low): `6541910` pinned a fixable inconsistency -> reversed here.
- Deviations: D-231. Open: its premise was wrong: Windows `file.exists()` is TRUE for a dangling
  link, so the refusal never ran there (hosted, CI-51).

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
  "Windows wire log refuses escaping file links, dangling or not" passed in run 39217189384
  (9170baf).

## Task CI-38 - Scrub skips dangling links without Windows warnings (2026-10-18, #51)
- `scrub_walk()` chose files with `utils::file_test("-f")`: on Windows `stat()` succeeds on a
  dangling link, so `file.info()` warned "cannot open file" (D-137) and the link counted as a file;
  `scrub_scan()`'s `file.size()` warned again. Fix (`13de743`): a file needs a followed
  `file.info()` mtime, the warning muffled. POSIX unchanged.
- Red: a POSIX simulation with Windows `file.info()` gives WARN 1, ERROR 1 on the old code. Green:
  `^auth-redact$` PASS 486 SKIP 1. Lint clean.
- Reviews: none recorded.
- Deviations: D-231. Open: "Windows scrub skips foreign junctions and dangling links without
  warnings" passed on hosted Windows (2c9b6a4 ordinary by-file; 9170baf R-CMD-check).

## Task CI-39 - Crash recovery runs on Windows (2026-10-18, #51)
- Tests only: "SIGKILL mid-stream: resume parses, keeps the last complete message, no duplicate" and
  "SIGKILL mid-append, resume, three appends: all present and the tree connected (IC-59)"
  (`21f01b7`) and "SIGTERM leaves a sidecar that the next touch applies around user edits (IC-51)"
  (`f2cf9a3`) drop their Windows skips: processx's `kill()` and `signal(SIGTERM)` are
  `TerminateProcess()` plus a wait there. The two dangling sidecar tests use real junctions
  (`1b87c03`, `doc_io_dangling()`).
- Green: `^session-store$` PASS 273, `^doc-io$` PASS 670 on macOS. Lint clean.
- Reviews: r1 3 findings (medium: a tree kill built on the false Rterm.exe cause; low: a renamed
  IC-51 test; low: an overclaimed commit body) -> fixed.
- Deviations: none. Open: passed on hosted Windows (2c9b6a4 by-file; 9170baf R-CMD-check), the
  dangling sidecar tests with warnings until CI-60.

## Task CI-40 - The artifact tests run on Windows; a Chrome skip says why (2026-10-18, #51)
- Tests only: the access token test pins the Windows tokenless fallback (`6644347`); the socket path
  limit check runs on Windows (`0cbd095`); a session-check skip names `chromote::find_chrome()` and
  quotes the last 3 lines of the stderr log its own launch wrote (`71baed1`, `2a5e415`), since both
  Windows R-CMD-check jobs skipped with "startup timed out" only (run 39179983061). `610ecf8` (a
  USERPROFILE with AppData\Local) was reverted by `630968f` as unverified.
- Green: `^artifact-app$` PASS 494 SKIP 0 (real Chrome), PASS 482 SKIP 2 with a fake Chrome;
  `^artifact-browser-launch$` PASS 476. Lint clean.
- Reviews: r1 3 findings (medium: unverified swap -> reverted; low: stale allowances -> CI-42; low:
  a stale log could be quoted -> fixed; its claim that the refusal is a LOG(ERROR) was rejected).
- Deviations: none. Open: on 2c9b6a4 the system Google Chrome quoted "DevTools remote debugging
  requires a non-default data directory" (job 117897245682), so R-CMD-check's session checks still
  skipped; the cause was the suite's empty Windows profile (CI-63).

## Task CI-41 - The credential store, child env and CLI stdin are pinned on Windows (2026-10-18, #51)
- Tests only: "on Windows auth.json lives under the per-user APPDATA profile (privacy is its ACL)"
  (`0711327`); "an mcp child gets exactly the documented base variables its parent defines"
  (`6e225bb`); a 200 KB codex prompt and "a 200 KB first user line reaches the claude child intact"
  (`275cd6d`), more than the 65536-byte processx stdin pipe and one owned-writer chunk (D-019 item
  5).
- Red: dropping `TMPDIR` from the Unix `env_allow_base()` list fails the env test. Green:
  `^auth-store$` PASS 64 SKIP 2, `^auth-childenv$` PASS 167, `^cli-(claude|codex)$` PASS 790 on
  macOS, also under `LC_ALL=C`. Lint clean.
- Reviews: none recorded.
- Deviations: D-234; D-019 item 5, D-101, D-104, D-106 status. Open: passed on hosted Windows
  (2c9b6a4 by-file; 9170baf R-CMD-check); claude control responses over one chunk are untested.

## Task CI-42 - The renamed access-token test loses its Windows skip allowances (2026-10-18, #51)
- After `6644347` the old access-token title matched no test but stayed allowed to skip on Windows
  in `dev/ci/rscript-native.R` and `optional_allowed_skip()`. Fix (CI only, `37edb30`): both entries
  go, and the allowance test names another real Windows platform guard.
- Green: `dev/ci/test-optional-integrations.R` PASS 3695. Lint clean.
- Reviews: r1 finding 2 of CI-40 (low).
- Deviations: none. Open: none.

## Task CI-43 - A walked file is one /undo item in per-turn scan mode (2026-10-18, #51)
- The Exact-tarball windows-latest release check in CRAN mode (job 117848217386) failed the #37
  test: after a walk slower than `gptr.checkpoint_scan_budget` the session scans once per turn, and
  `ckpt_files_explicit()` recorded the walked `a.txt` with its absolute path, so one file was two
  `/undo` items, the dry run found a conflict and the UI cancelled. Fix (`e941222`): such a row is
  relative, as the walk records it; `05537a8` runs the #37 test in walk mode (budget `Inf`) and a
  new test in per-turn mode (budget -1).
- Red: per-turn mode forced on the old tree fails the #37 test on the same 7 lines as Windows.
  Green: all `ckpt-*` tests and the full offline suite. Lint clean.
- Reviews: r1 (the bound-document rewind fails in per-turn mode) -> CI-54.
- Deviations: D-228. Open: Exact-tarball on 2c9b6a4 (run 39202180585) green in CRAN mode, once.
  Repeat pending (P27 A5).

## Task CI-44 - The observer's supervisor counts toward the cap only by its growth (2026-10-18, #51)
- "a Windows worker exits within 10 s after its acknowledged parent dies (IC-60)" failed in
  rscript-native (run 39185663719, source context) as `resource_limit`: on Windows the observer
  added the supervisor's absolute RSS, 537 MB after 11 earlier files in one process, to the 544 MB
  family (1,088,077,824 > 1,073,741,824); the supervisor grew by 7 MB. Fix (tests only, `f663aa1`):
  the cap charges the supervisor only for its growth since `before_rss`; the 1 GiB cap, family and
  disk caps, deadlines and witness fields are unchanged; CI-23's unit-RSS mock goes.
- Red: FAIL 5 with the old helper and 1.2 GB of ballast. Green:
  `^(proc-backpressure-sampling|bp-declared-observer)$` PASS 583 with 0, 1.2 and 3.6 GB of ballast.
  Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: rscript-native on 2c9b6a4 (job 117897297705) completed the case with guard
  null (combined peak 1,130,909,696 B, growth within the cap); on 92a2944 rscript-native is green.

## Task CI-45 - An exited artifact test child must end with its whole marker family (2026-10-18, #51)
- Release run 39182291391 (job 117842876468) stopped "a broken app ends the child" in cleanup with
  "The artifact test child did not settle"; the same test passed in 37 other hosted Windows jobs.
  Inferred mechanism: processx's `wait()` returns at once after `is_alive()` collected the exit
  code, while ps 1.9.3 lists an exited pid as running; `kill_all()` then ran within milliseconds.
  Fix (tests only, `f35bb9a`): the two tests whose child exits by itself wait, within their 10 s and
  15 s, until ps lists neither the child nor a carrier of its marker (`family_left()`), which names
  what stays.
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
- Reviews: r1 finding 4 answered in the commit body; finding 5 declined (the probe calls stay
  pinned).
- Deviations: none. Open: the preflight passed in the optional run on 92a2944 (run 39235001873).

## Task CI-47 - kill_all() stops the background children a shell's interrupt leaves on macOS (2026-10-18, #51)
- `peter$bg("sleep 57 & sleep 58 & echo ready; wait")` then `job$kill()` left both sleeps running on
  macOS: SIGINT ended the shell alone, the sleeps were reparented to launchd, ps reads no
  environment of system binaries (no marker), and processx's `$kill()` does not signal a reaped
  leader's group. Fix (`812940c`, `R/proc-supervise.R`): `kill_all()` records a live process's
  descendants by parent link before the interrupt and kills them after `$kill()`; no bound changes.
- Red: the unskipped test fails on macOS with the old `kill_all()`. Green: `^bridge-sh$` PASS 279
  SKIP 2, 3 runs; `^(proc-.*|bridge-.*)$` PASS 2691 SKIP 23. Lint clean.
- Reviews: none recorded.
- Deviations: D-233. Open: on 92a2944 `ubuntu-latest (release, LC_ALL=C)` (job 118001849130) failed
  `test-bridge-sh.R:512` (`length(tree)` 1, expected >= 2) in this test; the Linux create-time
  filter of `ps_children()`, which also hid descendants from `kill_all()`, is CI-69.

## Task CI-48 - Scrub refuses a dangling lock-root link where readlink has no target (2026-10-18, #51)
- On Windows `Sys.readlink()` is "" and `normalizePath()` falls back to the lexical path, so
  `scrub_lock()` took the session lock and tried creates through a dangling junction at `.gptr` or
  `.gptr/locks` (Win32 `_wmkdir()` failed them; nothing was written outside). Fix (`2c9b6a4`):
  `scrub_lock()` refuses when `path_dangling(root)` or `path_dangling(lock_root)` holds, before any
  lock; `path_dangling()` (a listed entry without followed metadata; on POSIX a readlink target
  since CI-68) also backs the wire log.
- Red: an emulation on macOS records 2 `write_atomic()` calls on the base. Green: none on this
  commit; `^auth-redact$` PASS 486 SKIP 1, `^utils-paths$`, `^http-reactor$`. Lint clean.
- Reviews: r1 6 findings; F1-F3 applied, F4 not tested (rests on an unverified `dir.exists()`), F5
  -> CI-51, F6 -> CI-52.
- Deviations: D-231. Open: "Windows scrub refuses a dangling lock-root junction before taking any
  lock" passed in run 39217189384 (9170baf).

## Task CI-49 - A Windows cmd line runs in a cmd started after chcp 65001 (2026-10-18, #51)
- Hosted windows-by-file (run 39193453652) returned `"a b" caf\x82 ??` for `echo "a b" café 日本`
  from the cmd knit engine and the cmd route of `peter$sh()`: chcp and the echo shared one `/c`
  line, so the output kept the OEM page. Fix (`7c36123`): `shell_cmd()` runs an outer
  `cmd /d /v:on /s /c` that changes the code page and starts the inner cmd that runs the line from
  `GPTR_SHELL_CMD`; `bridge_exec()` and `bridge_bg()` set the target's env.
- Red: a cross-platform test of the target env fails with the old plumbing. Green: `^proc-spawn$`
  PASS 224, `^bridge-sh$` PASS 281 SKIP 2, `^bridge-lang$` PASS 106 SKIP 4. Lint clean.
- Reviews: r1 4 findings: a log claim removed; the env field documented and the spec rows routed to
  D-229; a caller's `GPTR_SHELL_CMD` documented as refused (precedence kept).
- Deviations: D-229. Open: the cmd route and engine passed in R-CMD-check run 39217189384 (9170baf,
  Windows release and oldrel-4); a multi-line cmd chunk still runs only to its first LF.

## Task CI-50 - The PowerShell route's lost exit status gets a diagnostic test (2026-10-18, #51)
- Hosted Windows (run 39193453652) returned status 0 for `Write-Output "café 日本"; cmd /c exit 4`
  through `-EncodedCommand` while stdout matched. `0fbca74` (tests only) keeps the assertion and
  adds a run that prints `lec=$LASTEXITCODE ok=$?` after `cmd /c exit 4` and `cmd /d /c exit 5`,
  then runs this R with status 6. Product unchanged here; the fix is CI-66.
- Green: `^bridge-sh$` PASS 281 SKIP 2 on macOS (the Windows assertions do not run there).
- Reviews: none recorded.
- Deviations: none. Open: on 9170baf both Windows R-CMD-check rows fail `test-bridge-sh.R:146`
  (status 0) and `:155` (stdout `lec= ok=True` twice), and again on 92a2944 (run 39235008757);
  status 6 passes. `$LASTEXITCODE` stays unset after both cmd exits, so registry AutoRun (the only
  effect of `/d`) is ruled out. Cause and fix: CI-66 (Rtools' MSYS2 `usr/bin/cmd` shadows `cmd.exe`
  in PowerShell's PATH search, diagnostic run 39234534171); its test asserts the status contract
  instead of printing these values.

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
- In per-turn scan mode (a slow walk, which a hosted Windows runner can cross at random) and on
  every CLI route, the agent_end turn scan recorded gptr's own block write into the bound script, so
  a rewind restored the turn-1 bytes and deleted the undone blocks (0 undone markers, 8 requests not
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
  `artifact_stop_grace` (3 s) first, wrapped so an error or interrupt cannot replace the launch
  error.
- Red: 9 failures against the base launch site, 1 against an unwrapped wait. Green: `^artifact-app$`
  PASS 517 (NOT_CRAN), PASS 437 SKIP 13 (CRAN mode). Lint clean.
- Reviews: r1 5 findings; 1-3 applied, 4-5 kept by choice.
- Deviations: none. Open: the root cause is not proven on Windows.

## Task CI-56 - The orphan sweep test reads only the marker records (2026-10-19, #51)
- R-CMD-check run 39202162326 (2c9b6a4, Windows release and oldrel-4) failed
  `test-proc-spawn.R:232`: the test listed `proc_dir()` by `^GPTR_PROC_`, which also matches the
  stdin writer's `<marker>.stdin` files, and one was removed between the listing and the read. Fix
  (tests only, `9170baf`): the test reads only `<marker>.json`, the records it checks.
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
- Deviations: D-230. Open: rscript-native on 92a2944 (run 39234997432) and the optional packet
  passed the session checks with Chrome for Testing; R-CMD-check's system Google Chrome refusal
  (CI-40) is CI-63.

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
- On Windows `file.exists()` is TRUE for a dangling link and a later `file()` warns and fails, so
  the readers, the read, edit and grep tools, `ls`, the files checkpointer, `@file` mentions, the
  document arguments and cache, image checks and `dotenv_discover()` gave warnings, base errors or
  wrong answers. Fix (`3383843`): their metadata reads and guards use `path_info()` and give POSIX's
  answers; gptr's own stores keep base reads and the trust gate keeps `file.exists()`.
- Red: on 9170baf the Windows emulation of the new test's calls gives warnings, base errors and
  wrong answers. Green: the full offline suite FAIL 0 WARN 0 SKIP 62 PASS 34753 on macOS. Lint
  clean.
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
  Branded Chrome serves DevTools only when `IsUsingDefaultDataDirectory()` is false and takes
  "cannot tell" for default; the unknown came from `SHGetFolderPath(CSIDL_LOCAL_APPDATA)`, whose
  registry value `%USERPROFILE%\AppData\Local` named a missing folder under the suite's empty home
  (Chromium sources; outside support: the Stack Overflow 50666524 answer). Chrome for Testing has no
  such gate, and real users keep their profile. Fix (tests only, `6bae056`): `setup.R` creates
  `APPDATA` and `LOCALAPPDATA` as `home/AppData/Roaming` and `home/AppData/Local`; the new case "the
  suite home is a Windows profile whose Local AppData the browser child resolves" pins the layout
  and, on Windows (NOT_CRAN), asks Windows PowerShell 5.1 for
  `GetFolderPath('LocalApplicationData')` in `child_env("artifact")`.
- Red: the new case fails before the change on macOS (folders missing, outside the home). Green: it
  passes, also its Windows branch with `/bin/sh` standing for PowerShell; `artifact-app` and
  `test-environment` with real Chrome FAIL 0 WARN 0 SKIP 2 PASS 524, both session checks ran; full
  suite FAIL 0 WARN 0 SKIP 63 PASS 34773. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: R-CMD-check Windows release and oldrel-4 on 85e5883 (jobs 118053097431,
  118053097175) and 74de8c6 (jobs 118076803835, 118076804097) list no `test-artifact-app.R` skip, so
  both session checks ran with system Google Chrome, and the new case passed. The two ordinary
  by-file runs on 74de8c6 (39255516069, 39255537264) skipped the first session check
  (`test-artifact-app.R:511`, `skip_if_browser_failed()`; the runner prints no skip reason); the run
  on 85e5883 (39250571244) ran both. Repeat pending on the final head.

## Task CI-64 - The owned Chrome's close waits for its unmarked helpers (2026-10-19, #51)
- Hosted ubuntu R-CMD-check failed the first real session check's cleanup
  (`test-artifact-app.R:488`) with "The private headless browser directory did not finish cleanup:
  unlink returned 1." (oldrel-4 on 9170baf, job 117943690034; oldrel-1 on 33720c1; oldrel-4 on
  945fa60 before the stage diagnostics): 3 of about 330 ubuntu jobs since Oct 13, none on macOS or
  Windows. `release()` judged the family by the `GPTR_PROC` marker alone, which Chrome's helpers
  never show: on Linux their `setproctitle()` zeroes the block `/proc/<pid>/environ` reads, and on
  macOS ps reads no Chrome environment. So the profile was unlinked while orphaned helpers (the
  network service above all) still wrote in it. Fix (`a7b1793`): `owner$close()` records the
  browser's descendants by parent link before SIGTERM through `proc_children()`, which `kill_all()`
  now shares; `release(seconds)` waits for them with `proc_wait_exit()` within the remaining 10 s
  `artifact_browser_close()` deadline, and a helper still running or unknown raises "The owned
  headless browser family did not finish cleanup." and keeps the directory for a retry. The startup
  unwind and the retained cleanup job keep the single check.
- Red: the new test "artifact browser close waits for its unmarked helpers before removing the
  profile" fails on 92a2944 with the hosted message. Green: it passes, and a helper alive past the
  deadline keeps the root until a retry succeeds; in an offline Ubuntu container with Chromium 145
  an immediate unlink failed 3 of 40 rounds and a wait for the recorded family first removed all 40
  (settled within 0.023 s); with real Chrome on macOS `release()` waits 0.06-0.08 s for 9 helpers;
  full offline suite FAIL 0 SKIP 62 PASS 34794. Lint clean.
- Reviews: none recorded.
- Deviations: D-233 (amended). Open: not seen in the ubuntu R-CMD-check rows on 85e5883 and 74de8c6,
  which at about 1% per job proves little; after a browser that died before `close()` no helper can
  be recorded, so `release()` has the marker check alone, as before; `proc_wait_exit()` polls every
  20 ms, so the wait can end one poll past the close deadline, which then reports "close timed out".

## Task CI-65 - A job's status is read before its bytes; its tests release through a file (2026-10-19, #51)
- `test-bridge-sh.R:445` and `:449` failed in the filtered windows-by-file run on 9170baf (run
  39217182105, job 117943670939) with `(no output) [j... done, 1s]`. Cause (test timing): there
  `bridge_bg()` takes 0.66 to 1.19 s to return, mostly after the spawn, which used up the child's
  `Sys.sleep(1)`; the first wait settled after the child had written DONE, so
  `wait(until = "ready")` rightly returned both lines and the next wait had none. Passing runs had
  about 60 ms to spare, and the partial-line test passed without exercising its rule. Fix (tests,
  `1f5359e`): each child blocks after its first output until the test creates the file `go` (its
  path an argument); the 20 s timeouts and the assertions are unchanged, and the partial-line test
  adds a 1 s wait that must return no line while only `rea` is written.
- Product (`adfef78`, a race on every OS, not the hosted cause): `bridge_job_read()` took the status
  after the bytes, so a child that exited in between gave a `done` footer while its partial last
  line was unread. The status now comes first and decides whether a partial line waits; the snapshot
  read (`file.size() - pos`, one `readBin()`) is unchanged.
- Red: 92a2944 with the new test "a job that exits during a read reads running, so a done read holds
  all output" FAIL 1 (footer `done`); with `bridge_emit()` slowed by 1.5 s the old tests fail `:445`
  and `:449` as hosted. Green: `^bridge-sh$` PASS 286 SKIP 2 (4 runs); the new tests pass with
  `bridge_emit()` slowed by 0, 0.9, 1.5 and 3 s; NOT_CRAN=false PASS 144 SKIP 27. Lint clean.
  Mutants: a `settled()` that matches partial lines fails the new partial-line test (`:467`); a read
  that returns partial lines fails `:465`.
- Reviews: r1 6 findings: the handshake (1) and the partial-line handshake (6) applied; the
  read-to-EOF loop and the unproven stale Windows `file.size()` claim reverted (2, 5: the hosted
  logs show the size was current); the `file.size` mock dropped (3); the status-first reorder kept
  (4).
- Deviations: none. Open: `test-bridge-sh.R` passed in the ordinary by-file runs on 85e5883
  (39250571244) and 74de8c6 (39255516069, 39255537264) and in R-CMD-check Windows release and
  oldrel-4 on both; repeat pending on the final head.

## Task CI-66 - PowerShell runs the program cmd would run and returns the last status (2026-10-19, #51)
- On hosted Windows the PowerShell route of `peter$sh()` returned 0 for `cmd /c exit 4` (CI-50). The
  diagnostic run 39234534171 (job 118000300246, branch `claude/diag-ps-exit`, since deleted) printed
  `(Get-Command cmd).Source` = `C:\rtools45/usr/bin\cmd` (pwsh 7.6.6), while `cmd.exe`,
  `& $env:ComSpec` and `Start-Process` each gave 4. PowerShell's `CommandPathSearch` takes the PATH
  directories in order and ranks the bare name last only within each, so MSYS2's extensionless
  `usr/bin/cmd` script, which R CMD's `Rcmd_environ` puts first on PATH, shadows `cmd.exe`;
  `IsExecutable` is false for it, so PowerShell opens it with ShellExecute in the background, does
  not wait and sets no `$LASTEXITCODE`.
- Fix (`shell_ps_encode()`, `R/proc-spawn.R`): `b4df19c` sets a `PostCommandLookupAction` that
  replaces a lookup resolved to an extensionless Application with the first Application of that name
  with an extension (`Get-Command -CommandType Application -All`, PowerShell's PATH order);
  `bd8e30b` makes the postfix
  `if ($?) { exit 0 }; if ($LASTEXITCODE) { exit $LASTEXITCODE }; exit 1`, so a last command that
  succeeded wins over an earlier native failure; `c65f11e` sets the hook only when
  `$IsWindows -ne $false` (pwsh on Windows and Windows PowerShell 5.1); `3596af1` makes a name that
  only an extensionless file provides not found ("not recognized", status 1), as in cmd. The same
  encoder serves the knit powershell engine and the stdin ACL verifier (bootstrap 9133 and 9117
  bytes on macOS, limit 9998). `3942e0b` (tests) runs the shadowed line under Windows PowerShell 5.1
  too.
- Red: hosted status 0 where 4 was expected. The Windows test now prepends a temporary directory
  with an extensionless `cmd` to PATH, which reproduces the shadow on any runner, and asserts status
  4 (pwsh and 5.1), status 6 and stdout `6\n` for this R after `cmd /d /c exit 5`, 0 for
  `cmd /c exit 4;
  Write-Output ok`, 1 for `cmd /c exit 0; Write-Error no`, and stdout `ok\n` with status 1 for an
  extensionless-only `gptr-none`. Green: on macOS `proc-spawn`, `bridge-sh`, `bridge-lang` and
  `proc-writer-runtime` PASS 1293 SKIP 14 (Windows-only). Lint clean.
- Reviews: r1 5 findings: (medium) green unproven -> the hosted runs below; (low) the 5.1 route
  never ran -> `3942e0b`; (low) the hook searched PATH on every native lookup under Unix pwsh ->
  `c65f11e`; (low) plan, spec and DEVIATIONS out of sync -> D-235 and the 03 and 04 rows; (low) a
  silent 0 for an extensionless-only name -> `3596af1`.
- Deviations: D-235. Open: the Windows test passed on 85e5883 (R-CMD-check jobs 118053097431 and
  118053097175, whose failure is CI-70; by-file run 39250571244) and on 74de8c6 (jobs 118076803835,
  118076804097; by-file runs 39255516069, 39255537264); no test runs the hook's Unix branch; a name
  with a non-PATHEXT extension is still opened with ShellExecute (a document with a file
  association, kept on purpose).

## Task CI-67 - path_info()'s dangling-link test runs on R 4.2 and ignores atime (2026-10-19, #51)
- On 92a2944 R 4.2.3 (Windows oldrel-4 job 118001849423, ubuntu oldrel-4 job 118001849303) errored
  at `test-utils-paths.R:324` in the Windows `file.info()` mock: R 4.2's `data.frame()` cannot
  coerce an octmode column. On macOS the comparison of a regular file's row with a second
  `file.info()` failed once on atime, which reading the file between the calls may update. Fix
  (tests only, `95199d2`): the mock adds the mode column after construction; atime leaves that one
  comparison.
- Red: the hosted R 4.2.3 error; the macOS atime failure once. Green: `test-utils-paths.R` passed on
  R 4.2.3 in R-CMD-check on 85e5883 (ubuntu oldrel-4 job 118053097194; Windows oldrel-4 job
  118053097175, whose failure is CI-70) and 74de8c6 (jobs 118076804031, 118076804097). No local run
  or lint is recorded in the commit.
- Reviews: none recorded.
- Deviations: none. Open: none beyond the repeat on the final head.

## Task CI-68 - A dangling link is a readlink target on POSIX, a listed entry on Windows (2026-10-19, #51)
- Since CI-48 `path_dangling()` asked for no followed metadata and a directory entry whose name
  matched with case folded, on every OS. On a case-sensitive file system (Linux) a missing name
  beside a sibling that differs only in case was therefore a dangling link: `wire_log_path()`
  refused a valid `gptr.wire_log` inside `tempdir()` with the "must be inside the workspace root or
  tempdir()" notice, and `scrub_lock()` refused a missing `locks/` beside `Locks/`; origin/main (a
  readlink target and no file) accepted both. Found by the whole-diff review. Fix (`dba9c78`): POSIX
  takes no followed metadata and a readlink target (`path_is_link()`), Windows keeps `path_listed()`
  (names folded as NTFS does); `resolve_link_target()` drops its own POSIX rule and asks
  `path_dangling()` and `path_is_link()` on every OS, with unchanged results. `089bc9a` (tests):
  `local_dangling_link()` in `helper-files.R` builds the fixture that `test-doc-io.R` and
  `test-utils-paths.R` each copied.
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
- Deviations: D-231 (corrected). Open: on d9a7840 (run 39274424747, both attempts) the case passed
  in R-CMD-check `windows-latest (release)`, the Windows branch (a junction `Link` looked up as
  `link`), and in the ubuntu rows other than oldrel-4 (CI-71), the case-sensitive branch; repeat
  pending on the final head.

## Task CI-69 - A child's descendants are read from ps's own handle of its pid (2026-10-19, #51)
- On 92a2944 `ubuntu-latest (release, LC_ALL=C)` (job 118001849130) found 1 of the 2 background
  sleeps at `test-bridge-sh.R:512` (CI-47). `85e5883` (tests) looked again for up to 10 s until ps
  listed both; it passed on 85e5883 (job 118053097216), but on 74de8c6 `ubuntu-latest (release, no
  Suggests)` (run 39255504135, job 118076803865) failed `test-bridge-sh.R:569` with 0 of 2 for the
  whole 10 s. Cause: on Linux processx 3.9.0 stamps a child from `CLOCK_REALTIME - CLOCK_MONOTONIC`
  read at the spawn, ps 1.9.3 times every process from the boot time it read once, and
  `ps_children()` keeps a descendant only when the parent's stamp is not later than its creation
  time; a shell forks its background jobs in its first 10 ms tick, so whenever processx's estimate
  was the larger, `ps_children(p$as_ps_handle())` listed none of them, at every look. `kill_all()`'s
  parent-link record (`proc_children()`) used the same lookup. Fix (`d480ee5`): `proc_children()`
  lists from `ps::ps_handle(pid)` and keeps the list only while processx still reads the child alive
  (no pid reuse); the bridge tests read the tree with `proc_children()`; `85e5883`'s re-look is
  removed; the 5 s bound for `kill()` is unchanged.
- Red: a C emulation with the formulas of processx 3.9.0, ps 1.9.3 and `ps_children()`, 1000 runs of
  the test's line in debian bookworm (arm64, dash): processx's handle listed neither sleep in 187
  runs (180 with LC_ALL=C; rocker/r-ver:4.5.0 under amd64 emulation 2 and 3 of 300). The new test
  "proc_children() follows parent links from ps's own handle while the parent lives" lists a child
  when processx's stamp of the parent reads later than the child (the old lookup lists nothing) and
  nothing once the parent ended. Green: ps's own handle listed both sleeps in every emulated run; on
  macOS `bridge-sh` and `proc-supervise` pass, also with `_R_CHECK_PACKAGE_NAME_=gptr` and LC_ALL=C,
  and the `proc-*`, `subagent-*`, `cli-*` and `bridge-*` files and their neighbours pass. Lint
  clean.
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
  `observer-metadata-invalid` at `entry-metadata` (a delete-pending Windows file, CPython `st_ino`
  0), and CI-23's one immediate retry met the same file (`elapsed_s` 0, `observer_retries` 1) while
  the writer met every bound (13 samples, peak disk 4,049,354 B). A file stays delete-pending while
  any handle (an antivirus or indexer scan) is open, which can span two back-to-back snapshots. Fix
  (tests only, `404b90a`): `bp_observe()` retries the same five reasons every 100 ms until the
  observer's own 1 s snapshot deadline has passed since the first failure (about ten retries); any
  other reason, and a transient that outlasts the deadline, stay one fatal sampling error with the
  last snapshot's condition. `observer_retries` counts every retry and the first reason is kept. The
  observer, the caps and the 1 s, 30 s and 45/60 s deadlines are unchanged; a sample can take about
  1 s longer, inside the 15 s the 60 s lease reserves.
- Red: `^proc-backpressure-sampling$` FAIL 12 with the old helper. The CI-23 unit test is renamed to
  "backpressure observation retries fixed transient observer reasons for one deadline" and covers
  transients that clear, a bound reason after two retries and a persisting transient (it stops after
  at least 1 s, after 2 to 19 retries); the `bp_run()` case completes after three retries and fails
  for a bound reason and for a persisting transient. Green:
  `^(proc-backpressure-sampling|bp-declared-observer|bp-disk-observer)$` PASS 669 SKIP 5; with
  Python 3.15 and the real observer the writer and observer files PASS 841, all four writer cases
  with `observer_retries` 0; `^(proc-|bp-)` PASS 2317 SKIP 16; `bp_observe()` in rocker/r-ver:4.5.0
  stops a persisting transient after 10 retries at 1.09 s. Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: native-07 passed on 74de8c6 with the one retry. On d9a7840 (run
  39274424747) the 1 s did not cover native-01's entry on oldrel-4: attempt 2 (job 118200832757)
  raised `observer-metadata-invalid` after 8 retries, so CI-73 charges an exactly delete-pending
  file as a file; attempt 1 had failed native-08 earlier, at the observer's construction (CI-72).

## Task CI-71 - Two tests abort a hanging fake request only once the provider has read it (2026-10-19, #51)
- Both attempts of R-CMD-check `ubuntu-latest (oldrel-4)` on d9a7840 (run 39274424747, jobs
  118134892383 and 118200833216) hit the 45-minute job timeout. In both hung logs all 21
  backpressure witnesses name one worker as `parent_pid` (9900 in attempt 1, 10038 in attempt 2),
  the later files' output arrives contiguous and in file order, and
  `> test-agent-run.R: [gptr] aborted`, which the test at line 1135 prints, is missing; the passing
  oldrel-4 logs (85e5883, 74de8c6, d62eb7f) split the witnesses 4/15, 11/8 and 4/13 and print it. A
  callr worker on testthat's pipes delivers a flushed `cat()` line while it blocks, so the other
  worker (9902 in attempt 1, 10040 in attempt 2, each job's only orphan, with no child process) held
  `test-agent-run.R` and stopped before line 1135, where only "run_start(s, NULL) continues from the
  leaf after an abort" waits without a bound after a hang reply.
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
  pump checks its result, so a 30 s stall without a first poll would still end in the unbounded
  wait.

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
  `^(proc-backpressure-sampling|bp-declared-observer|bp-disk-observer)$` PASS 686 SKIP 5; with
  Python 3.15 and the real observer in a clean TMPDIR the writer, backpressure and observer files
  PASS 1112 SKIP 1, all 7 real cases with `observer_retries` 0; an observer copy whose first
  construction's clock jumps 1 s gives a real `observer-initial-deadline` that `bp_observe()`
  retries once, and one that is always slow raises after 9 retries at 1.03 s; `^(proc-|bp-)` PASS
  2336 SKIP 16; the dev/ci tests that source the helper pass; in rocker/r-ver:4.5.0
  (`--network none`) `bp_observe()` stops a persisting initial deadline after 10 retries at 1.07 s.
  Lint clean.
- Reviews: none recorded.
- Deviations: none. Open: not yet run on hosted Windows; a retried construction shows
  `observer_retry_reason` "observer-initial-deadline" in its witness. The cold cost inside the first
  construction's 1 s is inferred (a loaded runner or a first-call cost): the witness records only
  the R-side `initialization_elapsed`. `test-bp-disk-observer.R` constructs directly, without the
  retry, as it already snapshots without one; the frozen windows-token packets keep the combined
  reason. Locally the real observer needs a TMPDIR outside macOS's default (104,171 entries), where
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
  kind `file`: it is charged its listed size like any file (so not in `declared_only` mode) under
  the unchanged byte, entry and deadline checks, and is never opened, followed or identity-compared.
  Any other status, an `st_ino`-0 directory or link, a declared entry, another host, or fake
  operations without the `delete_pending` hook still raise `observer-metadata-invalid` (or
  `declared-entry-not-link`), which R retries for 1 s as before (CI-70). An `st_ino`-0 entry that
  also fails one of the earlier checks now reports that reason, which is not retried; a real lstat
  cannot reach that, and the outcome is stricter. The bounds, `bp_observe()` and its transient
  reasons and the frozen windows-token packets are unchanged. Retrying in `bp_observe()` for the
  rest of the case deadline was rejected: it would leave RSS unsampled for up to about 29 s.
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
  (R1-4); a recurrence no longer said to prove another status (R2-2); the scope kept to regular
  files (R1-2); the reason precedence kept and explained in the commit (R2-4, received truncated).
- Deviations: none. Open: hosted Windows has not run either commit. The new case is the first real
  test of the two facts the fix rests on (CPython 3.12's lstat gives `st_ino` 0, the query gives
  0xC0000056); its failure output shows which does not hold. Even if it passes, native-01's entry is
  unidentified: a pending directory (still fatal by design, such as a `.stdin` mailbox removed by
  `unlink(recursive = TRUE)`), another status, or a deletion that completes between lstat and the
  query (retried) all give that reason, and one green run cannot tell a fix from a race that did not
  recur, so judge native-01 over several runs. No claim about the native-06 and native-07 failures
  (CI-23, CI-70).

## Task CI-74 - A new-session preview syncs skills; the token benchmark pins the catalog (2026-10-20)
- Cause: skills are discovered by `skill_sync()` in builtin:skills' `session_start` hook, which
  fires at a session's first run. `gptr_prompt()` composes without that event, so in a fresh R
  session its preview had no `skills` section, unlike the prompt the first run freezes; the IC-68
  test in test-northstar.R passed only because an earlier block had run a session. `bench_case()`
  also freezes without `session_start`, so the token baseline measured no skills catalog either.
- Fix: `skills_section_text()` syncs the skills of a top-level session before listing them
  (idempotent; a real first run's frozen T0 and T1 are byte-identical before and after). The
  benchmark pins the `skills` stand-in (the built-in catalog, the same text a fresh session lists)
  for the fixtures that name it, like `r_env` (CI-18), so the developer's own skill folders never
  enter the prefix.
- Red: test-skill-discover.R's preview test FAIL 2. Green:
  `skill-|northstar|prompt-|subagent-|arch-layers` PASS; in CRAN mode `northstar|skill-discover`
  PASS 106. New `test-token-gates.R` test (a machine skill leaves ns02's prefix unchanged) fails
  without the pin.
- Baseline (`run.R --update`): the 12 standard cases' prefix and catalog +143 (catalog 399 -> 542,
  the value recorded before the drift noted in D-135 item 6), input totals +143 per request; the two
  minimal cases unchanged. `run.R --check` OK; polyglot within 10%; `dev/bench/tests` PASS.

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
  `diff_ops()`; with the wall-clock bound the stall fails ("Expected elapsed time (CPU 0.83 s) <
  5"). Green: the stall passes, the busy loop fails ("Expected CPU time (elapsed 6.67 s) < 5"), and
  the unmocked block passes; `^tool-diff$` PASS 570. Lint clean.
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
  (`test-proc-backpressure-sampling.R:686-688`) ended its eighth transient as the error, with 8
  calls and 7 retries instead of 9 and 8.
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

## FIX-13 - One honest size for every object (2026-10-21, #73)
- The maintainer's rule: an object the agent creates is the console's, at the same size, and gptr's
  size reports are honest for every kind of object. The fidelity harness (37 cases, each built at
  the console and through `peter()`; truth `lobstr::obj_size()` and the bytes not shared with
  namespaces) found the objects identical but 134 dishonest size rows on main (ggplot2 4.0.3, S7
  0.2.2, R 4.6.1): no size for S7 plots, functions, environments and compact sequences (D-189);
  `object.size()` in lists of plots (seven themed plots 111 MB against 9 MB: undo skipped, overwrite
  level 3), values and dot facts; checkpoint images sized leaf by leaf (a themed plot's image 15.8
  MB against 840 B; pinfsc50's `@fix` edit 8.7 MB against 1.3 MB); shared elements counted per path;
  a formula's environment uncounted; R6 objects and environments "copied" by a `duplicate()` that
  returned them; a changed `1:1e6` called a sequence. The branch's first fix (S7 leaves through
  D-189's rule, unknown sizes copied at 0 bytes) left lists overstated and copied every plot
  unbounded.
- Fix: D-247 (amended): `env_snap_size()` in `utils-size.R` counts each part once by address and
  each string once by content, leaves out code, top-level environments, the home and running frames,
  walks an S7 class copy once per class, samples lists and environments of more than 64 items past
  10,000 parts, and with `shared` sizes a checkpoint image against the current value; every size
  surface calls it (`env_snap_rows()`, `dsc_leaf_core()` and the describe headers,
  `risk_binding_leaf()`, `value_facts()`, `dot_facts()`, `tool_result_message()`,
  `subagent_fanout_spec()`, `artifact_data_facts()`, `ckpt_unshared_bytes()`), and
  `describe_binding()` describes with its home on the call stack. The value policy copies below
  `gptr.value_copy_max`, now 2 MiB, when `object.size()` is below `gptr.values_max_bytes` and keeps
  a copy that is a new object under the limit. Snapshot sizes are reused only while the fingerprint
  holds too. Review fixes: an environment takes the 100-level cap (a chain of 700 overflowed the
  node stack, so the snapshot failed: no `<workspace>` block, no checkpoint of the turn, "describe
  failed"); a vector counts its stored length through `object.size()` (`length()` dispatched:
  survival's `Surv` counted half, `bit::bit(1e8)` 381 MB for 12.5 MB); a closure's srcref is code
  (each of a sourced 748-line file's 53 functions was 589 KB); the describe header drops "(compact
  sequence)", whose check serialized a sequence-like vector a second time; `held_mb` and `disk_mb`
  count 2^20 bytes; a dead `home = NULL` and a redundant guard go. Deleted: D-189's NA rule and
  median rank, `ckpt_addr_collect()` and `ckpt_unshared_walk()`, the old three-element
  `env_compact_seq()`, the "(sequence)" shape and the describe headers' NA branches; the first fix's
  NA-means-copy rule and long-sequence exception are not kept.
- Red: on main (ba77f68) the new and changed expectations fail: FAIL 60 in 28 tests (env-snapshot
  11, env-describe 8, ckpt-objects 2, session-object 2; arch-layers, copy-eval, gptr-capture,
  perm-classify and utils-options 1 each); on the size commit the 2 MiB default's check fails
  (`^(session-object|utils-options)$` FAIL 1). Review fixes, each before its commit: env-snapshot
  ERROR (node stack overflow) and FAIL 1 (a classed vector 232 B against 800,224 B), srcref FAIL 3
  (env-snapshot 2, env-describe 1), env-describe FAIL 1 (the header), ckpt-rewind FAIL 1 (`held_mb`
  1.049 against 1).
- Green:
  `^(env-snapshot|env-describe|ckpt-objects|perm-classify|gptr-capture|session-object|arch-layers|
  utils-options|copy-eval|copy-tools|tool-namespace|console-commands|s1-route|lint-rules|prompt-text|
  artifact-app)$` PASS 3954, SKIP 0 (the ggplot2 guard ran), WARN 0. The whole suite (NOT_CRAN)
  failed once in subagent-team, whose value held by name (1.6 MB) is copied at 2 MiB; it now returns
  2.4 MB, and the suite passes: PASS 35225, SKIP 64 (Windows, live and Python-runtime blocks),
  WARN 0. Lint clean; `devtools::document()` leaves no diff; the plan checks pass. After the review
  fixes: `^(env-|ckpt|session|gptr-capture|perm-classify|
  copy-|arch|zzz|utils-options|subagent-team|listing-print)` PASS 4644, SKIP 1 (the C-locale display
  witness), WARN 0; the six changed files lint clean; `devtools::document()` leaves no diff.
- Harness (the review-fixed build at the 2 MiB default; the harness now judges the value mode at the
  build's `gptr.value_copy_max`, not a fixed 1 MiB, which had flagged `df_big` and the data frame of
  plots): defect rows 134 on main, 15 with this rule (5 lobstr's ALTREP-wrapper undercount, 3
  srcref, 5 "serializes differently", now also `df_big` and the data frame of plots, whose copies
  write out a compact `id` column, and 2 environments held by name); the two themed plots just over
  1 MiB are copied (922 and 914 KB held) and survive the edit; against the build before the review
  fixes only `closure_factory` (784 to 782 KB) and `r6` (785 to 782 KB) changed, by their functions'
  srcrefs. Every surface shows one number per case; the judges' stress objects (sizes and images
  unchanged by the review fixes) within 0.6x to 1.2x of `lobstr::obj_size()` in at most 0.3 s
  (checkpoint forms 0.6 s). Copy safety: 64 tracemem/address probes (list, nested, attribute, S4
  slot, data frame column, environment, closure environment, character elements, lists past the
  budget walked and unwalked, the checkpoint form, plot data and labels, a list of 200 plots) match
  a run without sizing, rerun on the final `utils-size.R`. A 1,000-node environment chain in the
  workspace keeps the `<workspace>` block and the turn's checkpoint (1/1 objects).
- Reviews: three designs (minimal, sharing, purpose) judged twice; the minimal walk won, with the
  judges' grafts: strings once by content, the `object.size()` bound before a copy, no extrapolation
  from a first item that reaches a shared frame (now: the first, the last and the budget-spending
  item are not samples), 56 bytes a binding.
- Decisions: `gptr.value_copy_max` 2 MiB; `dot_facts()$bytes`, `value_ref$bytes` and the fan-out
  facts' bytes kept and sized by this rule; `describe_binding()`'s home on the call stack, the
  dropped "(sequence)" shape, the sampling budget and environment sizes that stay until the shape
  changes accepted; after review, the describe header's "(compact sequence)" dropped too and
  `held_mb` counted in 2^20 bytes.
- Deviations: D-247 (amended). Open: `fingerprint_sample()`'s `as_utf8()` makes the next in-place
  edit of a list with a character element copy after a snapshot (a main defect; fixed on its own
  branch). Found in review, main defects for their own branches: `/exit` sends `session_shutdown`,
  which releases the returned console session's undo images (`gptr_rewind()` then restores no
  object); `gptr_source()` rebuilds an object that captures a call with the document's srcref, as
  `source(keep.source = TRUE)` does; `gptr_export()` refuses a console transcript, whose later turns
  continue `s_<id> |> peter()`.

## FIX-14 - fingerprint() leaves a list's elements editable in place (2026-10-21, #72)
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
- Review: the orchestrator read the diff and tests; full suite (NOT_CRAN=true) FAIL 0, WARN 0,
  SKIP 64, PASS 35170.
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
  "did not answer as a 2026-07-28 server", final 30/30 connect. (3) "a modern stdio server is found
  by the probe, ..." with gptr's first discover write delayed 6 s connects through the second probe
  but sends `initialize` 5/5 at the 5 s probe; at 30 s it is probe-only 5/5.
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

## FIX-15 - Cheat-sheet review: tools (2026-10-22, #77)

### tools-1 - Dispatch refuses a direct call to a tool the session did not offer
- Red: FAIL 7 in `agent-dispatch` (PASS 221), mode auto with the fake provider: `write` under
  `tools = "-write"` wrote w.txt, `r` under `"-r"` bound `made_here`, `grep` under standard ran,
  and a non-interactive `ask` stopped the run with `gptr_error_noninteractive` (findings 12, 17).
- Cause: `call_record()` resolved a call with `tool_lookup()`, the registry alone (registered,
  `execute`, not hidden), never what the session declared; presets, `-name`, `tools.disable`,
  deferred and unavailable tools only shaped the array, and only the mode stood in the way.
- Fix: `run_tools()` takes the offered names once per batch (the frozen array plus every
  `tool_change` addition on the path and in the queue, `prompt_tools_known()`) and
  `call_record(run, block, offered)` resolves only those; any other name is "Tool <name> not
  found" before hooks and the permission check. `dispatch_nested()` is unchanged. The report02
  harness's `dispatch()` freezes the blocks' declarations (`freeze_tool_decl()`) when unfrozen.
- Green: `agent-dispatch` PASS 228; `^(agent-dispatch|agent-run|dispatch-elapsed|bridge-lang|
  bridge-sh|arch-layers|lint-rules)$` PASS 1383 SKIP 6; full suite (NOT_CRAN=true) FAIL 4 SKIP 64
  PASS 35277, all four the bridge tests below, then fixed. Lint clean. Live (Claude Opus 4.8,
  `tools = "-r"`, auto, 3 runs): 2 called `r`, got "Tool r not found" and wrote the code to a
  file instead; `sds` never created; all idle.
- Deviations: D-248. The frozen-schema test starts from the harness's freeze. The bridge
  through-run tests (py, sql, knit, sh) now read "Tool <name> not found", still refused before the
  permission check; the S-4 text "is an R function, not a tool" is now reached only by a bridge a
  continued session adds by value (`tools = "+sh"`, measured) and keeps its unit test.
- Reviews: r1 1 finding (low), applied: D-248 recorded the new refusal of an undeclared bridge
  only here; its first Rule now states it (`Tool <name> not found` before any hook; the S-4 hook
  text only for a bridge declared by value), Contract-visible lists P22 Task 5, and P22's S-4
  paragraph and self-review item 10 point to it. Plan checks pass.
- Open: the fixed preamble still says "with the r tool" when r is removed (by decision);
  `tool_change` declarations count after a switch to a provider that cannot take additions.

### tools-5 - Non-interactive manual mode with noninteractive_ask = deny says questions are refused
- Red: FAIL 1 in `prompt-context` (PASS 87): with deny, `context_mode_body("manual", FALSE)` still
  ended "questions asked with the ask tool, stop the run" (verdict of finding 168, item a).
- Cause: `context_mode_body()` chose the manual suffix before it looked at `deny`, while under deny
  a manual run's `ask` call is denied and the run goes on to idle.
- Fix: test deny first. The deny suffix ("are refused. State your assumptions instead of asking.")
  holds for a denied ask too; no new text, `preset_ask()` unchanged.
- Green: `prompt-context` PASS 88; `^(prompt-context|prompt-text|prompt-compact|tool-ask)$` PASS
  572. Lint clean; plan checks pass.
- Deviations: D-248 (04 section 9.3 suffix order). Open: none.

### tools-6 - Edit errors number edits from 1
- Red: FAIL 1 in `tool-edit` (PASS 170): `peter$edit()` with the first of two edits missing said
  "Could not find edits[0]", which an R reader takes for no edit (finding 4).
- Cause: `apply_edits()` and `edit_normalize_args()` printed `i - 1L`, Pi's JSON wording, on every
  path (console, inside `r`, direct tool), while the schema gate on the same tool counts from 1.
- Fix: the five messages (not found, empty oldText, occurrences, overlap, must be a string) print
  `i`; one rule for every caller, no base argument.
- Green: `tool-edit` PASS 179 (6 pins moved to 1-based); `^(tool-edit|tool-namespace|doc-replay|
  utils-paths|json-schema|doc-edit)$` PASS 1407 SKIP 1. Lint clean.
- Deviations: D-248 (no contract text names the index). Open: none.

### tools-7 - peter$edit names the fields it expects, and peter$help("edit") lists its arguments
- Red: FAIL 3 in `^(tool-edit|tool-namespace)$` (PASS 588): `peter$edit(f, list(list(old =,
  new =)))` said "oldText must not be empty", and `peter$help("edit")` had no Arguments block
  (finding 20).
- Cause: `edit_normalize_args()` never checked that the fields exist and `apply_edits()` read a
  missing one as "" (so an edit without newText deleted its text, measured); a named list counted
  as one edit only when it had oldText. `ns_tool_help()` listed arguments only when the schema's
  properties equalled the formals, and `edit` has `replace_all` beyond its schema.
- Fix: a named list of non-lists is one edit; an edit missing a field is refused with "edits[i]
  has no oldText or newText (it has: old, new). Use list(list(oldText = ..., newText = ...))."
  Help lists the schema arguments when they are among the formals, plus "[items: oldText,
  newText]" for an array; `find` now lists its arguments too. Inside `r` the schema gate already
  answered, so only the console changes.
- Green: PASS 595; `^(tool-edit|tool-namespace|doc-replay|doc-edit|utils-paths|json-schema|mcp-.*|
  skill-.*|bridge-lang|bridge-sh)$` PASS 2968 SKIP 8; `^(console-commands|northstar)$` PASS 175.
  Lint clean; Rd unchanged.
- Deviations: D-248. Open: none.

### tools-8 - A fuzzy peter$edit changes only what it matched, and says why it was not exact
- Red: FAIL 6 in `tool-edit` (PASS 188): `1 - 2` -> `1 to 2` against an en dash also straightened
  a curly apostrophe later on the line, unfolded the fi ligature, turned U+00B5 into U+03BC and NBSP
  into a space and dropped the trailing spaces; a printed fuzzy `gptr_patch` showed no reasons
  line (finding 1).
- Cause: `edit_splice_fuzzy()` (Pi's applyReplacementsPreservingUnchangedLines()) rebuilt each
  touched line group from the fuzzy view; `new_gptr_patch()` dropped `edit_reasons()`, which only
  the model saw.
- Fix: the splice landed (sheet entry S31 takes the vignette's wording: "changes only the matched
  text, unless the match starts or ends inside a ligature or between two letters with combining
  accents on one line; those lines are rewritten in normalised form").
  `fuzzy_offsets()` maps a fuzzy-view offset back to the original line by per-character
  normalisation (`fuzzy_normalize_lines(strip = FALSE)`) aligned with the line's own from both
  ends, and newText (file line ending) is spliced into the original bytes. When a boundary cannot
  be mapped (between two combining accents on its line, inside a ligature) the old line rewrite
  runs and the reasons add "the touched lines were rewritten in normalised form". `gptr_patch`
  gains `reasons` (all three call sites) and prints them bracketed between the message and the
  diff when fuzzy. Vignette sentence corrected in .Rmd and .Rmd.orig; Pi's not-found wording stays.
- Green: `tool-edit` PASS 194; `^(tool-edit|tool-namespace|tool-r|doc-replay|doc-formats|
  doc-blocks|utils-paths|json-schema)$` PASS 2129 SKIP 1; every existing fuzzy expectation (tws.txt
  included: covered trailing spaces go) unchanged. 20,000 fuzzy matches with replace_all: 1.8 s
  (was 2.7 s). Lint clean; Rd unchanged.
- Reviews: r1 2 findings (low), both applied. (1) The vignette sentence said "still changes only
  the matched text" with no exception for the fallback, and left out NFKC compatibility forms
  (ligatures, full-width letters, U+00B5, with stringi): both vignette files now name them and the
  exception, and say the printed result names the normalisation. (2) The first version sent a
  whole edit to the line rewrite when one combining sequence sat anywhere on a touched line:
  `cafe\u0301 \u2018x\u2019 \u2018y\u2019` edited `'x'` -> `'z'` composed the accent and
  straightened the other quote (red FAIL 2 in `tool-edit`, PASS 194). Aligned from both ends:
  `tool-edit` PASS 196; the neighbours above PASS 2137 SKIP 1; 20,000 matches 1.7 s (1.4 s before,
  same run). Lint clean.
- Deviations: D-248 (04 sections 5.10, 7.10). Open: the fallback still rewrites the lines when a
  boundary lies between two combining accents on its line or inside a ligature (said in the
  reasons); a non-fuzzy deviation (CRLF, re-encoding) still prints only the message.

### tools-9 - The r_session prompt mentions record = false only when the r tool has it
- Red: FAIL 1 in `tool-namespace` (PASS 415): a session with no document froze "Use peter$out(),
  peter$help(), peter$search() and peter$plot() only with record = false." while its `r` schema
  had only `code` (from the verdict of finding 20: `peter$help("edit", record = FALSE)` failed).
- Cause: `r_session_out_text` was a fixed string, while `record` is an `r` argument only with a
  document bound at freeze (`r_schema(document = TRUE)`).
- Fix: the fragment is a `function(ctx)` that adds the sentence only when `ctx$input$document` is
  set, the test `<documents>` uses; frozen once per session, so the cache prefix is unchanged.
- Green: `tool-namespace` PASS 417 (the stand-in and registration pins render the document
  text); `^(tool-namespace|tool-r|prompt-.*|northstar|bench-context|doc-formats|lint-rules|
  arch-layers)$` PASS 2031. Lint clean; Rd unchanged.
- Deviations: D-248 (03 section 7.3, IC-48). Open: none.

### tools-10 - read and peter$read count lines as readLines() does
- Red: FAIL 14 in `tool-read` (PASS 221): a 3-line `writeLines()` file read total 4 with a final
  "", "[2 more lines ...]" at limit 2, offset 4 accepted; 3000 lines at offset 2990, limit 5 said
  7 more; 2500 lines "of 2501"; `writeLines("done")` at limit 1 said 1 more (finding 5).
- Cause: Pi's `split("\n")` count, kept on all three paths: `length(nl) + 1L` in
  `read_window_small()`, `split_lines_js()` on UTF-16/32, the newline count plus one in
  `read_line_index_build()`. Every fixture was built with `paste(collapse = "\n")`.
- Fix: a final newline ends the last line on each path (subtract it; drop a final "" of more than
  one element); "" stays empty and "\n" alone is one empty line. Vignette: `read()` returns the
  file's lines, without line numbers (.Rmd and .Rmd.orig).
- Green: `tool-read` PASS 235 (Pi's count moved in seven tests: UTF-16, BOM CRLF, streaming
  index, BM text, cap, giant line, non-ASCII index); `tool-namespace` PASS 417 ("direct tools return
  Pi's texts" now "x = 1\ny = 2", total 2);
  `^(tool-.*|console-render|context-prefix|ext-api|ext-events|mcp-
  namespace|mcp-server|prompt-.*|session-object|skill-.*|doc-.*|lint-rules|arch-layers)$` PASS
  7261 SKIP 2 before that pin; full suite (NOT_CRAN=true) FAIL 2 SKIP 64 PASS 35324, both
  `proc-windows-backpressure` (a ps `access_denied` memory sample under load; the file alone PASS
  254). Lint clean; Rd unchanged.
- Deviations: D-248 (04 section 7.10 `read_file()`). Open: none.

### tools-11 - A finished background job's run time stops growing
- Red: FAIL 1 in `bridge-sh` (PASS 286): with `reactor_now()` mocked 100 s later, a waited-on
  done job and a killed one read `peter$jobs()` seconds and `read()` footers 101, 101, 100, 100
  instead of 1, 1, 0, 0 (finding 6; live GPT called a 2 s job 48 s).
- Cause: a `gptr_job` kept only `.started`; the footer and the `seconds` column measured to now
  whatever the status.
- Fix: `bridge_job_status()` sets `.ended` the first time it sees the process dead;
  `bridge_job_seconds()` (end, else now, minus start) serves both reports; `wait()`'s `settled()`
  asks the status, so a waited-on job stops within one 200 ms pump.
- Green: `bridge-sh` PASS 287 SKIP 2; `^(bridge-sh|bridge-lang|proc-supervise|gptr-jobs|
  copy-bridge|lint-rules|arch-layers)$` PASS 648 SKIP 6. Lint clean; Rd unchanged.
- Deviations: none (the contract does not define `seconds`). Open: a job nobody looks at until
  long after it ended (including after `kill()`) stops at that first look, an upper bound.

### tools-12 - peter$py() refuses RETICULATE_PYTHON=managed and gives advice an R user can follow
- Red: FAIL 1 in `bridge-lang` (PASS 106): with `RETICULATE_PYTHON=managed`, `py_available()`
  mocked FALSE and `import_main()` mocked to stop, `bridge_py_main()` reached `import_main()`
  (finding 2: reticulate then downloads a uv-managed Python, which the refusal says gptr never
  lets happen); the unconfigured refusal said "activate a virtual environment", which in R reads
  as `reticulate::use_virtualenv()`, refused by the same guard.
- Cause: the guard asked only `nzchar()` of `RETICULATE_PYTHON`, `RETICULATE_PYTHON_ENV` and
  `VIRTUAL_ENV`; "managed" is non-empty.
- Fix: `identical(Sys.getenv("RETICULATE_PYTHON"), "managed")` (reticulate's own `==` test) is
  refused like an unconfigured Python, first line "RETICULATE_PYTHON=managed asks reticulate to
  download a Python for peter$py()."; both refusals advise a Python executable in
  `RETICULATE_PYTHON` (or R started from an activated virtual environment), or
  `reticulate::use_python("<path>")` then `reticulate::py_config()` before the first call.
  P22 Task 7's guard rule amended.
- Green: `bridge-lang` PASS 115; `^(bridge-.*|copy-bridge|perm-classify|lint-rules|arch-layers)$`
  PASS 1546 SKIP 12. Unmocked (no Python configured, reticulate 1.47.0) `peter$py("1 + 1")` with
  `RETICULATE_PYTHON=managed` refuses and Python stays uninitialised. Lint clean; Rd unchanged
  (`@noRd`).
- Deviations: D-248 (P22 Task 7). Open: `use_python()`/`use_virtualenv()` without `py_config()`
  are still refused (accepting them needs reticulate internals or `RETICULATE_USE_MANAGED_VENV`
  handling, a later change); the cheat sheet takes sheet entry S32.

### tools-13 - A broken fake-provider script fails at once instead of being retried as overloaded
- Red: FAIL 7 in `provider-fake` (PASS 199): with `agent_retry_delay()` mocked to 0, a number
  as reply 2 of a list script made 4 requests and signalled `gptr_error_overloaded` (finding 10:
  "retrying in 2.0 s (overloaded)", then 4.0 s); a script function that stops ("boom 500
  timeout") and an empty script made 3 each; the no-script error event had class "provider"; a
  failing classifier script and a classifier with no script gave `gptr_error_s1_overloaded`.
- Cause: `fake_script_reply()` and `fake_pick()` reported gptr's own script failures as status
  500, which `fake_status_class()` names "overloaded", so `run_retryable()` retried them twice
  against its own rule (never a local failure); `fake_missing_events()` sent class "provider"
  with 500, which `err_class()` drops and reads back as overloaded; the classifier fake passed
  500 to `fake_s1_error()`.
- Fix: `fake_script_error()` gives a broken script's reply `status = NA` and class
  "invalid_spec" (never retried, signalled as `gptr_error_provider`); `fake_plan()` takes
  `reply$class` before the status; the no-script event is "invalid_spec" with no status. A
  scripted `list(error =, status = 529L)` still retries. Beyond the plan, the classifier fake's
  failures (a failing or empty script, no script found) follow through the same helper and an NA
  status: `gptr_error_s1_response`, never retried. No construction-time check of list elements:
  the request already names the misuse.
- Green: `provider-fake` PASS 206; `^(provider-.*|agent-run|agent-loop.*|s1-.*|gptr-gateway|
  lint-rules|arch-layers)$` PASS 5442; full suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35358.
  Lint clean; Rd unchanged (`@noRd`).
- Deviations: none (04 section 12.1 does not define a broken script; the fix restores
  `run_retryable()`'s rule). Open: none.

## FIX-16 - Cheat-sheet review: doc (2026-10-22, #77)

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
- Windows CI (#77): the user-cache sidecar test compared `gptr_cache()`'s path with
  `dirname(doc_sidecar_path())` as strings; on Windows the two spell the same directory differently
  (FAIL 1 on shard 1/4, release and oldrel-4). It now compares them with `path_key()`, as the test's
  later lines already do.

### doc-2 - Say when a script call is not recorded because gptr_doc() bound another document
- Findings 22, 149, 174.
- Red: FAIL 2 in `^doc-replay$` (PASS 613): bound to `out.R`, non-interactive, `record` unset, a
  fake `peter()` call in `fk.R` run by `source()` and one in `job.R` under a mocked
  `Rscript --file=` gave no notice (out.R absent and both scripts unchanged, as expected).
- Cause: `doc_locate()` sites a call in the document that holds it; the binding is consent for its
  own path and the target only of calls in no document (console, `-e`, stdin). Unable to ask,
  `doc_keep()` dropped the site before `doc_upsert()`, whose "no write consent" notice was never
  reached.
- Fix: `doc_keep()` informs a `notice` once per document when a call that could record (record not
  FALSE, not replay mode) gets no consent while a binding exists: "gptr did not record this call: it
  is in fk.R, but gptr_doc() bound out.R. Calls are recorded into the document that holds them; run
  gptr_doc("fk.R") to record them there." No binding stays silent (IC-45). `?gptr_doc`, 04
  section 6.4 and IC-45, 03 section 4.3 say what a binding covers; the help also how console turns
  are written (IC-49).
- Green: `^doc-replay$` PASS 615 (dropping the guards fails the silent cases: no binding, record
  FALSE, replay); `^(doc-.*|arch-layers|lint-rules)$` PASS 2519 SKIP 2 (NOT_CRAN=true). Lint clean.
  Rd regenerated; plan checks pass. Installed build, real `Rscript driver.R`, fake provider: one
  notice for two calls, no out.R, driver.R unchanged; a self-bound script records both blocks, no
  notice.
- Deviations: D-249 (extended). Open: an interactive run whose answer for a document is a remembered
  "off" also gets the notice once while another document is bound.

### doc-3 - Sheet: gptr_doc() binds this R session; bind quarto and Knit documents in their setup chunk
- Finding 19, its rendering half (doc-1 fixed the notebook and crash-recovery half).
- Red: none (wording). Installed build, fake provider, quarto 1.10.18: a `.qmd` bound at the
  console, then `quarto render`, got no block and no message; `rmarkdown::render()` of an `.Rmd`
  in the binding session recorded one.
- Cause: a binding is this R process's consent (`the$doc_binding`; 04 section 6.4 already says "this
  R process"). `quarto render`, `quarto::quarto_render()` and RStudio's Knit and Render buttons knit
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
- Deviations: none (04 section 11.5 names only the `source()` line). Open: the name is the file's at
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
  keeps session logs in .gptr/)` (was `(none)`). 04 section 11.5's transcript row says so.
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
- Deviations: none (03 section 6.17 lists `/status` and `/doc` without their lines; the doc.site
  service already answered the binding without a session). Not in the plan: `/status` before a
  session gains the `document` line, as it had none to correct.
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
  (moved to `eval-format.R`, as an L4 service file may be called from `tool-r.R`);
  `doc_output_lines()` shows lines up to the first cut one, cuts once and counts `sum(n)`; a flat
  vector still renders.
- Green: `^(doc-blocks|tool-r)$` PASS 460; `^(doc-.*|eval-format|tool-r|mcp-server|arch-layers|
  lint-rules)$` PASS 2879 SKIP 2 (repr), `^(mcp-recording|eval-core)$` PASS 346 (NOT_CRAN=true).
  Lint clean; plan checks pass. `local_doc_e2e()` and `doc_e2e_source()` moved to `helper-doc.R`.
- Deviations: D-249 (extended; 04 sections 4.4 `outputs`, 11.5). Open: none.

### doc-11 - Write a known zero cost as cost=0 in block headers
- Finding 122.
- Red: FAIL 2 in `^(doc-blocks|doc-replay)$` (PASS 972): a turn whose answers cost a known `0`
  had no `cost` header key; a fake `peter()` call recorded into `analysis.R` listed
  `gptr_blocks(f)$cost` NA while `s$cost` was 0.
- Cause: `doc_block_lines()` wrote `cost=` only when known and above 0, and `doc_block_row()` reads
  a missing key as NA, the value IC-74 keeps for unknown.
- Fix: the guard is `tb$cost_known`; an unknown cost stays omitted. `?gptr_blocks` says `cost` is
  `0` for a known free route and `NA` when unknown or not recorded; 04 section 11.5's `cost` row
  says when it is written.
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
  Replay uses the name path unchanged. `?gptr_return`, 04 sections 4.4, 7.15, 11.5, IC-48, 03
  section 6.9.3.
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
  FAIL 1: no exports, store kept). 04 section 11.5 `children` and body, IC-46, IC-47; 03
  section 6.9.3; P15; the one teams-and-background paragraph.
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
  and 03 section 4.3 copied "returns its argument invisibly and does nothing else".
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
  04 section 5.1 (`print`, `.d` `replay_rows`), 03 section 5.1.
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
- Findings 124, 139, 152 (the `$text` halves of 114 and 119; the sheet's S03, S12, S23 lines follow
  in the sheet commit).
- Red: FAIL 5. `^session-store$`: `gptr_resume("s0123456789")` outside a workspace said only "no
  stored session matches". `^doc-replay$`: a replay that restored no answer was silent in process,
  under `GPTR_REPLAY=replay
  Rscript` (exit 0, `TEXT NA`) and for fan-out children whose answers were removed.
- Cause: without `.gptr/`, `workspace_root()` is `tempdir()/gptr`, so the session store and the S2
  answer cache end with R (intended: gptr writes only where named). Nothing said so where the loss
  is felt.
- Fix: both `resume_path()` store misses add "Without a .gptr/ workspace, sessions last until R
  exits; gptr_init(\".\") keeps them." when `workspace_dir()` is NULL. `doc_replay_no_answer()`,
  called for a replayed call and each team child, informs one `notice` per document and process when
  `$text` stays NA: "No recorded answer for <doc>: replayed answers ($text) are NA.", plus "
  gptr_init(\".\") keeps answers in .gptr/ for later R sessions." outside a workspace. NEWS:
  sessions are saved in `.gptr/` (without one, until R exits). 04 section 6.5, IC-46.
- Green: `^(doc-replay|session-store)$` PASS 982 (703 + 279);
  `^(doc-.*|session-.*|subagent-.*|ckpt-rewind|
  console-commands|console-repl|mcp-recording|gptr-sdk|gptr-source|knitr.*|arch-layers|lint-rules|zzz)$`
  PASS 5884 SKIP 3 (NOT_CRAN=true). Lint clean; no Rd change. Installed build, fake provider, two
  `Rscript` runs: outside a workspace the replay prints the notice with the hint, `TEXT NA`, exit 0,
  and `gptr_resume(id)` and `gptr_resume()` carry the hint; after `gptr_init(".")` neither error has
  it, a replay restores the text, still after `gptr_cache("clear", "s2")` (from the session file),
  and with `.gptr/sessions` removed too the notice comes without the hint.
- Deviations: D-249 (extended). From the plan: the notice keys on the outcome (`$text` NA after
  replay), not on a missing S2 record, which in a workspace or a live session is no loss (the
  session file or the live session holds the answer); the workspace text omits "the answer cache was
  cleared", as a copied document, a block recorded before `gptr_init()` or one recorded without an
  answer gives the same miss. Open: a piped replay keeps the previous turn's `$text` when its
  block's answer is missing (no notice there); a bare `/resume` still lists "# 0 rows" without the
  hint.

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

### replay-2e - A replay into another environment of the recording process keeps the value
- Validation of replay-2 (low; not a regression: main gave NULL in every case).
- Red: FAIL 2 in `^doc-replay$` (PASS 704): after `gptr_source(f, envir = e)` recorded
  `gptr_return(coef(fit))`, `gptr_source(f, replay = "replay", envir = e3)` gave `e3$s$value` NULL
  with "value `.gptr_value_<id>` (turn 1) is not bound in this R process".
- Cause: the header's session is live here, so the replay marks it; `replay_value()` runs before
  the block's code, finds the hidden name unbound in the session's home `e`, and adds a name-only
  record at turn 1, which shadows the turn's held box. The code then binds the name in `e3`, where
  the record is never resolved.
- Fix: `replay_value()` adds no name-only record when the session holds a value of that turn; the
  recording session keeps its own. IC-46 says so.
- Green: `^doc-replay$` PASS 706; `^(doc-.*|session-.*|subagent-.*|copy-subagent|northstar|
  ckpt-rewind|console-commands|mcp-recording|gptr-sdk|tool-r|arch-layers|lint-rules)$` PASS 5747
  SKIP 3 (repr; Windows worker; NOT_CRAN=true). Lint clean; plan checks pass.
- Deviations: D-249 (extended). Open: a bare `gptr_return(fit)` replayed into another environment
  still gives the recording home's `fit`, as replay-2 left it.

### doc-1b - A document outside .gptr/ takes its lock beside its sidecar, and gptr_cache() lists both
- Review of doc-1 (`R/doc-io.R`, medium; the lock and listing half of finding 15).
- Red: FAIL 3 in `^doc-io$` (PASS 702): for a notebook in a project without `.gptr/`,
  `doc_lock_dir()` was under `tempdir()/gptr`, not beside its sidecar in the user cache's
  `pending/`, and `gptr_cache()` listed no row with the sidecar written there.
- Cause: `doc_lock_dir()` used this process's `workspace_root()`, so two runs of one document
  outside `.gptr/` shared doc-1's sidecar without sharing the lock that guards it (IC-51): either
  run's write could replace the other's record, and the first run's exit unlink the second's.
  `doc_cache_files("sidecar")` read only the workspace root's `cache/tmp`, which the conflict
  warning ("see gptr_cache(\"info\")") and IC-51 point to.
- Fix: `doc_pending_dir()`; `doc_lock_dir()` uses the document's `.gptr/` else that directory, as
  `doc_sidecar_path()` does; the sidecar listing adds its `pending-*` files, and `gptr_cache()`
  gives them a second `sidecar` row with that path. `?gptr_cache`, 04 section 6.4, IC-51.
- Green: `^(doc-io|doc-replay|storage-boundaries|windows-security)$` PASS 1548 SKIP 11;
  `^(doc-.*|storage-boundaries|windows-.*|console-.*|zzz|arch-layers|lint-rules)$` PASS 4830
  SKIP 14 (Windows filesystem; repr; INFRA-03; NOT_CRAN=true). Lint clean; Rd regenerated; plan
  checks pass. Seven `gptr_cache()` expectations in test-doc-replay gain the fifth row.
- Deviations: D-249 (extended). Not as suggested: the sidecar keeps doc-1's path (no shared
  `cache/tmp` under `pending/`). Open: a document in a `.gptr/` project now locks in that `.gptr/`
  also when this process works in another project (was this process's root).

### doc-7b - The transcript header names the transcript from the project root
- Review of doc-7 (`R/doc-formats.R`, low).
- Red: FAIL 2 in `^doc-formats$` (PASS 258): a transcript at `.gptr/transcripts/gptr-session-
  20260929-183000.R` read `# gptr_source("gptr-session-20260929-183000.R", replay = "live")`, a
  file `gptr_source()` refuses from the project root; one outside the project gave its file name.
- Cause: doc-7 built the literal from `basename(site$path)`, while console transcripts made by the
  default choice (`doc_new_transcript()`) live in `.gptr/transcripts/`.
- Fix: the literal is `doc_rel(site$path)`: relative to the project root, absolute outside it.
- Green: `^doc-formats$` PASS 260; `^(doc-formats|doc-replay|console-.*|arch-layers|lint-rules)$`
  PASS 2914 SKIP 1 (INFRA-03; NOT_CRAN=true). Lint clean. A root-level `log.R` still reads
  `"log.R"`.
- Deviations: none. Open: doc-7's, a moved transcript keeps the path it had when recorded.

### doc-2b - The other-binding notice suggests gptr_doc() with the path it resolves
- Review of doc-2 (`R/doc-replay.R`, low).
- Red: FAIL 1 in `^doc-replay$` (PASS 707): run from `analysis/` of a project bound to `out.R`, a
  fake `peter()` call in `analysis/driver.R` suggested `run gptr_doc("analysis/driver.R")`.
- Cause: the literal came from `doc_rel()`, relative to the project root, while `gptr_doc()`
  resolves its argument against the working directory (`analysis/analysis/driver.R`, refused as
  not in an existing directory); it was also pasted without escaping.
- Fix: the suggestion is `doc_str_literal(path_rel(site$path, getwd()))`: relative inside the
  working directory, absolute outside it; the sentence keeps `doc_rel()` for both documents.
- Green: `^(doc-.*|arch-layers|lint-rules)$` PASS 2672 SKIP 2 (repr; NOT_CRAN=true). Lint clean.
- Deviations: none (the notice's form in D-249 stands). Open: none.

### export-2b - A raw export refuses a function that names a session handle
- Validation and review of export-2 (`R/doc-export.R`, low; one finding reported twice).
- Red: FAIL 3 in `^doc-export$` (PASS 224): `report = function() cat(s$text)` before `s =
  peter("one")` and `report()` after it exported, and so did `s = 1; report = \() s$text;
  report()` before the call: the plain scripts fail with "object 's' not found" or report `1`.
- Cause: export-2's ordered pass counts a read only after the handle's `peter()` statement; a
  function reads its names when called, which `report()` does not show.
- Fix: a statement whose `all.names()` hold `function` (also `\()`) is refused when it names any
  handle a `peter()` statement of the document binds; direct reads keep the position rule.
  `?gptr_export` and the `script-as-history` export paragraph say so.
- Green: `^doc-export$` PASS 228; `^(doc-export|doc-replay|doc-blocks|zzz|arch-layers|lint-rules)$`
  PASS 1522 (NOT_CRAN=true). Lint clean (the `.Rmd.orig` keeps its one lint from main, line 365);
  Rd regenerated; plan checks pass. `precompute.R script-as-history`: 0 problems, output
  byte-identical to the edited `.Rmd`.
- Deviations: D-249 (extended). Open: a function whose own argument or local shares a handle's
  name is refused too (conservative).

### replay-4b - The gptr_return() notice is said to be silent in replay mode, as it is
- Review of replay-4 (`R/gptr-sdk.R`, low).
- Red: none (docs). The extended test passes before the change: with `gptr.replay = "replay"` the
  first call is silent, and a file holding `gptr_return(1)` sourced under `"auto"` gives the notice.
- Cause: replay-4 copied IC-48's "silent while a document is replayed" into `?gptr_return` and 03
  section 4.3; the code is silent only when `replay_mode()` is `"replay"` (P08 adaptation 13), so a
  recorded `gptr_return()` that stays in the code (nested, or a pipe split over lines) prints it
  when the document is sourced under the default `"auto"`.
- Fix: `?gptr_return`, 03 section 4.3, 04 section 6.6 and IC-48 say "silent in replay mode
  (`replay = "replay"` or `GPTR_REPLAY=replay`)".
- Green: `^(gptr-sdk|arch-layers|lint-rules)$` PASS 189 (NOT_CRAN=true). Lint clean; Rd
  regenerated; plan checks pass.
- Deviations: D-249 (extended: the contract text now names the implemented rule). Open: none.

### steer-doc-1 - A steer line reads the same with or without its trailing space; only gptr's lines get the block id
- Steering review finding 5, the record half (its ingress half, refusing a blank steer, is P28's
  steer-14).
- Red: FAIL 6 in `^doc-blocks$` (PASS 352): a blank steer relay and an attachment-only follow-up
  were written `## Steer: ` and `## Follow-up: `; a recorded block whose `## Steer: ` an editor
  trimmed read `user-edited` in `gptr_blocks()` and `gptr_export()` refused it; a steer and r code
  holding `@@GPTR_BLOCK@@` were written with the block id, also inside a child overlay.
- Cause: `doc_re_steer` needed the space after the colon, the three writers kept it after an empty
  text, and `doc_fill_id()` replaced the placeholder in every body line.
- Fix: `doc_re_steer` ends `:( |$)`; the writers use `doc_steer_line()`, which drops a trailing
  space; `doc_fill_id()` fills the id only into the hidden value name and `gptr_resume(block = `
  homes (the header keeps its substitution). IC-49 and P15 amended.
- Green: `^doc-blocks$` PASS 358; `^(doc-blocks|doc-replay|doc-export|doc-knitr)$` PASS 1371
  (NOT_CRAN=true). Lint clean; plan checks pass (index findings unchanged). Live: see steer-doc-2.
- Deviations: D-249 (extended). Open: with `.run = FALSE`, steers queued before the run go ahead of
  the deferred prompt, so the first is the turn's first message and is not recorded, and the prompt
  is recorded as `## Follow-up:` (seen live; steering audit finding 1, P28's).

### steer-doc-2 - Recorded steer, follow-up, decision and agent lines escape control characters
- Steering review finding 2 (partly confirmed: one line is the IC-49 design and a cut is
  `source()`'s, not ours; raw control characters are real).
- Red: FAIL 3 in `^doc-blocks$` (PASS 360): a turn whose `note`, steer relay and follow-up held ESC,
  BEL, FF, VT, U+0085, U+2028 and U+2029 wrote them raw into its `## Decision:`, `## Steer:` and
  `## Follow-up:` lines, also with `LC_CTYPE` C; `source(echo = TRUE)` then drew them.
- Cause: `doc_one_line()` collapsed only `[\r\n\t]`.
- Fix: it also turns U+0085, U+2028 and U+2029 into spaces and passes `ui_escape()` (rule C1),
  which writes control, bidi and zero-width characters as `<U+XXXX>`; the `## Agent` line, an S1
  block's `#>` line and a console command's `#` comment share it. Written blocks keep their bytes.
  04 section 11.5 amended.
- Green: `^doc-blocks$` PASS 363; `^(doc-blocks|doc-replay|doc-export|doc-knitr|doc-io|arch-layers|
  lint-rules)$` PASS 2171 (NOT_CRAN=true, the IC-49 menu-steer replay included). Lint clean.
  Live, installed build, with steer-doc-1 (GPT-5.6 Sol, Claude Opus 4.8, Ollama qwen3.8:27b): a
  `background = TRUE` script given `gptr_steer(s, "   ")` and a steer holding ESC, BEL and
  `@@GPTR_BLOCK@@`, run by `gptr_source()`, recorded `## Steer:` and the escaped text with the token
  kept; no raw control byte in the file or in `source(echo = TRUE)` of its export; `gptr_blocks()`
  fresh with and without the trailing space.
- Deviations: D-249 (extended). Open: none.

### steer-doc-3 - A console transcript records a run that ended aborted, at max_turns or with an error
- Steering review finding 10.
- Red: FAIL 37 in `^doc-replay$` (PASS 714): for each of `aborted`, `error`, `max_turns`, `blocked`
  and `budget`, a console turn's prompt, code and `## Steer:` were missing, the next turn was
  written `s_<hex> = peter("predict")` and its partial answer cached; a transcript whose errored
  first run set `x_err` failed to re-source with "object 'x_err' not found".
- Cause: `doc_on_agent_end()` wrote only `idle` runs (P15 decision 5), a rule made for script
  blocks, whose block caches the answer, and never weighed for a transcript, the history of what
  happened.
- Fix: a console site records every settled run; one that did not end `idle` gets a last
  `## Run: <status>` line (in the body and its sha) and no cached answer. Script documents keep
  decision 5. IC-49, P15 decision 5, the hook's roxygen, the script-as-history vignette and NEWS.
- Green: `^doc-replay$` PASS 752; `^(doc-replay|doc-blocks|doc-formats|doc-export|arch-layers|
  lint-rules)$` PASS 1693 (NOT_CRAN=true). Lint clean; plan checks unchanged; `precompute.R
  script-as-history` byte-identical to the edited `.Rmd`. Live, installed build (GPT-5.6 Sol,
  Claude Opus 4.8, Ollama qwen3.8:27b): an `Rscript -e` console transcript of a steered
  `background = TRUE` run stopped by `max_turns = 2`, then a piped turn, recorded the steer, both
  runs' code and `## Run: max_turns`, and `s_<hex> |> peter(...)`; `GPTR_REPLAY=replay` re-sourced
  it to `x_err`, `y_err`, `w_err` 21, 22, 42.
- Deviations: D-249 (extended). Not as planned: no list of ended statuses, since `run_settle()`
  gives `agent_end` no other non-idle status. Open: the background `[b]` path is not tested.

### steer-doc-4 - A replayed session keeps the recorded steers and every replayed turn
- Steering review finding 3 (understated: the whole second turn of a replayed chain was lost).
- Red: FAIL 16 in `^(doc-replay|session-object)$` (PASS 1300): the live call after a replayed
  two-block chain whose fake provider queued three `gptr_steer()` steers saw 9 messages with the
  session file kept (block 2 a dead sibling branch) and 5 in a clone (one merged `r` call, no
  steer, no block 2); a block with `## Steer:`/`## Follow-up:` lines between runs reconstructed
  as one call; a rebuilt session replayed block 2 after a live turn by dropping that turn.
- Cause: `doc_replay_doc()` kept only code lines, `replay_reconstruct()` wrote one `r` call, a piped
  block only marked the session, and `replay_rebuild()` cut the leaf once, at the first block.
- Fix: `doc_replay_steps()`; `replay_turn_append()` writes runs, steers as the live operator relay
  (recorded back as the same line) and follow-ups after a placeholder answer; a reconstructed piped
  session gains each block's turn; `replay_seek()` moves a rebuilt one to each block's turn until a
  live run (`replay_notice()`). IC-46 and the 04 replay functions amended.
- Green: `^(doc-replay|session-object)$` PASS 1319; `^(doc-.*|session-.*|agent-run|mcp-recording|
  arch-layers|lint-rules)$` PASS 4914 SKIP 2 (NOT_CRAN=true). Lint clean. Live, the three routes:
  that transcript re-sourced in a new process, with its session log and as a clone without one
  (`history_source` `store`, `reconstructed`), then continued live: each model quoted both prompts
  and the steer and named the three variables.
- Deviations: D-249 (extended). Not as planned: both paths give the same 14 messages (the plan's 18
  had context messages in the recorded turns); a live run also stops the seek. Open: a
  `gptr.replay` marker of an earlier block stays off the path once the next block moves on.

### steer-doc-5 - Replaying a script does not send its recorded steers again
- Steering review finding 0 (medium: the console never writes a `gptr_steer()` statement), and
  finding 4's residual sentence for `?gptr_steer`.
- Red: FAIL 5 in `^(doc-replay|gptr-sdk)$` (PASS 888): replaying a recorded `.run = FALSE` +
  `gptr_steer(as = "follow_up")` + `gptr_wait()` script, and `background = TRUE` ones with
  `gptr_steer()` or a pipe steer, each made one more request under `replay = "replay"`; in auto mode
  a steer left over after run 1 was recorded again in an appended block; a turn `gptr_wait()`
  started from queued input under a binding said nothing. A steer with new text was sent (control).
- Cause: replay kept nothing of a block's steer lines; `gptr_steer()` queued and `route_continue()`
  started a run on the idle replayed session; `sdk_launch()` gives such a run no document site.
- Fix: a replayed block's steer and follow-up texts become session notes (`replay_notes_add()`,
  which takes back a matching queued item); `gptr_steer()` and `route_continue()` drop an equal text
  on an idle session with one notice (`replay_note_take()`); a live run clears the notes;
  `sdk_launch()` informs once. `doc_one_line()` moves to `utils-text.R` (L0). `?gptr_steer`, 04
  section 6.5, IC-55, vignette.
- Green: `^(doc-replay|gptr-sdk)$` PASS 893; `^(doc-replay|gptr-sdk|session-object|gptr-gateway|
  agent-background|doc-blocks|utils-text|arch-layers|lint-rules)$` PASS 2474 (NOT_CRAN=true). Full
  suite `.`: FAIL 4 SKIP 64 PASS 35558, the 4 a `ps` memory sample refused (`access_denied`) under
  load in `proc-marker-family` and `proc-rscript-native`, which alone pass (PASS 213). Lint clean;
  Rd regenerated; `precompute.R script-as-history` byte-identical to the edited `.Rmd`. Live, the
  three routes: `Rscript analysis.R` bound to itself, a `background = TRUE` call plus `gptr_steer()`
  and `gptr_wait()`, recorded the steer; rerun under `GPTR_REPLAY=replay` and under auto it exited
  0 with the notice, one turn and the file unchanged.
- Deviations: D-249 (extended). Not as planned: the notes reach the session through the replay
  functions' `doc` (an L4 file calls only the kernel SDK); a live run clears them in `run_start()`
  (`replay_notice()`), not `gateway_run_start()`; the drain takes back only `api_user` and `pipe`
  items, never a typed steer. Open: at the P28 merge the drain emits
  `queue_emit(s, "withdraw", ...)`.
- Open: a new `s |> peter("<text>")` turn whose text equals a steer or follow-up recorded in an
  earlier replayed block, which the script does not send itself, is skipped on replay with the
  notice "A steer this script sends is already recorded..." (IC-55 says either kind; low; found by
  the round-2 validation).

### replay-2f - Every gptr_return() shape replays its value or says once why not
- Second validation of replay-2 (medium; a regression: main said "not bound" for every expression).
- Red: FAIL 24 in `^(doc-blocks|doc-replay|doc-io)$` (PASS 1885): recorded through `gptr_source()`
  and replayed as a later process, `coef(fit) |>\n  gptr_return()`, a four-line chain with a
  comment and `gptr_return(x = coef(fit))` gave `$value` NULL with no message, and so did
  `if (TRUE) gptr_return(...)`, `y = gptr_return(...)` and braces; `gptr_return(coef(fit))` then
  `if (TRUE) gptr_return(1)` replayed the coefficients, not 1; the same under `GPTR_REPLAY=replay
  Rscript`, with and without `.gptr/`.
- Cause: `doc_rewrite_return()` rewrote a call only when its name, or its pipe and call, sat on one
  line, `doc_drop_expr()` dropped an `x =` call, and `returned` held once any call was rewritten;
  `doc_turn_r()` then wrote no `value=` (or the wrong one), and nothing told the replay.
- Fix: one rule: any top-level call, piped or over lines, its argument unnamed or `x`, becomes
  `.gptr_value_<id> = (<argument>)` (checked by re-parsing), and `returned` holds only when no
  `gptr_return()` is left in the code. A replayed block with no `value=` whose code still calls
  `gptr_return()` informs once per block and process, "No recorded value for block <id> of <doc>: a
  document records gptr_return() only as a top-level call, so $value is not replayed."
  `?gptr_return`, 04 section 11.5, IC-46, IC-48, 03 section 6.9.3, P15.
- Green: `^(doc-blocks|doc-replay|doc-io)$` PASS 1909; `^(doc-.*|gptr-sdk|subagent-team|
  session-object|session-store|mcp-recording|tool-r|northstar|ckpt-rewind|console-commands|
  copy-tools|arch-layers|lint-rules)$` PASS 4707 SKIP 2 (repr; NOT_CRAN=true). Lint clean; Rd
  regenerated; plan checks unchanged from HEAD. Full suite `.`: FAIL 0 SKIP 64 PASS 35659. A
  nested bare name, pinned after, replays by name without the notice (`^(doc-replay|gptr-sdk)$`
  PASS 929); `?gptr_return` then said "such a value", not "argument". Installed build, fake `r`
  call, a self-bound `analysis.R` per shape recorded by `Rscript` and replayed by
  `GPTR_REPLAY=replay Rscript`, with and without `gptr_init()`: the seven top-level shapes print the
  coefficients, the three nested ones the notice and NULL, files unchanged; under auto a nested one
  adds the outside-a-run notice.
- Deviations: D-249 (extended). Open: a team or fan-out child that designates an expression inside
  another expression still replays NULL without a word (its code is recorded only with a value or
  exports); a nested bare name keeps `value=<name>`, as before.

### export-2c - The script-as-history export paragraph is wrapped at 100 columns
- Second validation of export-2b (low).
- Red: none (docs): `vignettes/script-as-history.Rmd` line 331 and its `.Rmd.orig` line 309 were
  145 columns.
- Cause: export-2b added the sentence on functions that name a handle without re-wrapping.
- Fix: the paragraph's last lines re-wrapped to 100 columns, identically in both files (longer lines
  remain only in a table row and the logo data); two lines of the replay-2f record wrapped too.
- Green: `precompute.R --check script-as-history` 0 problems; its knitted `.Rmd` is byte-identical
  to the edited one.
- Deviations: none. Open: none.

### steer-doc-5b - Every source of a script in one process keeps its recorded steers unsent
- Second validation of steer-doc-5 (high).
- Red: FAIL 7 in `^doc-replay$` (PASS 836): the follow-up, `gptr_steer()` and pipe-steer scripts,
  each sourced again three times in the recording process (auto, replay, auto), sent the recorded
  steer from the second source on (one or two more requests each), and the pipe steer wrote a
  second block into the file.
- Cause: session_replay_apply() set a block's notes only while the block was not yet `seen`, and
  replay_note_take() used them up, so the live session that had seen the block got none again.
- Fix: replay_notes_add(s, block, doc) sets the block's notes anew on every replay, keyed by block
  (no pile-up), also from replay_adopt(); replay_note_take() takes a text from the block holding
  it. IC-55 and D-249 amended.
- Green: `^(doc-replay|gptr-sdk)$` PASS 947; `^(session-object|gptr-gateway|agent-background|
  doc-blocks|utils-text|arch-layers|lint-rules)$` PASS 1598 (NOT_CRAN=true). Lint clean. Live,
  installed build (GPT-5.6 Sol, Claude Opus 4.8, Ollama qwen3.8:27b): the follow-up script and a
  `background = TRUE` one with a pipe steer, recorded, then sourced three more times in that
  process with gptr_source() (auto, replay, auto): no request, the file unchanged, the queue empty.
- Deviations: D-249 (extended). Open: none.

### steer-doc-4b - A rebuilt session seeks each block's own record, not the file's last entry
- Second validation of steer-doc-4 (medium).
- Red: FAIL 3 in `^session-object$` (PASS 543): after a replay of b1 alone (forgotten, as at a
  process exit), a rebuilt b1 piped into b2 had `turns` 2 but one user/assistant pair and `$text`
  "first answer", and the next live call lacked turn 2.
- Cause: replay_seek() could only cut back from the rebuilt leaf, the file's last entry, which a
  replay that stopped sooner (one line run, an interrupt, the pre-fix code) left on turn 1's branch.
- Fix: replay_seek(s, turn, block) moves to the block's last `gptr.doc_block` record not undone
  (replay_block_record(), shared with replay_holds_block()), else cuts from the tip as before;
  session_replay_apply() and replay_rebuild() pass the block. IC-46 and D-249 amended.
- Green: `^session-object$` PASS 547; `^(doc-.*|session-.*|agent-run|mcp-recording|arch-layers|
  lint-rules)$` PASS 5004 SKIP 2 (repr; NOT_CRAN=true). Lint clean. Live, the three routes: a
  two-statement chain recorded, its first block replayed alone in a second process (the file's
  last entry then a `gptr.replay` on turn 1's branch) and the whole file in a third: `turns` 2,
  8 messages, `$text` the second answer; a live call then named a = 1 and b = 2.
- Deviations: D-249 (extended). Open: a block without a record (a team child, a nested call)
  still seeks along the rebuilt path.

### replay-2g - A nested gptr_return() before the last top-level one keeps value=
- Second validation of replay-2f (low; a regression from 2df56eaa).
- Red: FAIL 3 in `^(doc-blocks|doc-replay)$` (PASS 1227): `if (FALSE) gptr_return(1)` then
  `gptr_return(coef(fit))` was recorded without `value=`; replayed in a later process `$value` was
  NULL with the false "only as a top-level call" notice.
- Cause: doc_rewrite_return() denied `returned` for any gptr_return() left in the code, also one
  that cannot run after the last rewritten call.
- Fix: only a leftover in a later top-level expression, or inside a function literal (which may
  be called later), denies it. `?gptr_return`, IC-48 and D-249 amended.
- Green: `^(doc-blocks|doc-replay|doc-io|doc-export|mcp-recording)$` PASS 2217; `^(gptr-sdk|
  arch-layers|lint-rules)$` PASS 194 (NOT_CRAN=true). Lint clean; Rd regenerated. Live, the
  three routes ran that code as asked: the block got `value=`, and a later process replayed the
  coefficients without a notice.
- Deviations: D-249 (extended). Open: none.

### replay-2h - No false no-value notice when the recording session replays its own value
- Second validation of replay-2f (low).
- Red: FAIL 1 in `^doc-replay$` (PASS 847): `if (TRUE) gptr_return(2)` recorded through
  gptr_source() and re-sourced with `replay = "replay"` in the same process gave `$value` 2 and
  yet "No recorded value for block <id> of analysis.R: ... so $value is not replayed."
- Cause: doc_replay_no_value() read only the header and the code, not the replayed session.
- Fix: it takes the session and is silent when it holds a value of its turn (replay_value()'s
  test). `?gptr_return` (the notice is a later R session's), IC-46 and D-249 amended.
- Green: `^(doc-replay|doc-blocks|doc-io|gptr-sdk|subagent-team|session-object|arch-layers|
  lint-rules)$` PASS 3027 (NOT_CRAN=true); the later-process shapes keep their notice. Full suite
  `.` after the four round-2 units: FAIL 0 SKIP 64 PASS 35689. Lint clean; Rd regenerated. Live
  (GPT-5.6 Sol, Claude Opus 4.8): that code replayed in the recording
  process to 2 without a notice, in a later one to NULL with it; Ollama ran it with
  `record = false`, so its block holds no code and its replays say nothing.
- Deviations: D-249 (extended). Open: none.

## FIX-17 - Cheat-sheet review: models (2026-10-22, #77)

### catalog-1 - Convert each models.dev price tier once, and reconvert caches written by the old converter
- Red: `^catalog-models$` FAIL 5, PASS 410: a 200k tier plus the legacy field gave
  `default, >200k, >200k` and `prices_df()` refused it ("Invalid prices; expected unique date/tier
  thresholds."); a converter-less cache was read, and the refresh sent its ETag and kept no
  `converter`.
- Cause: `catalog_prices_from()` added a `>Nk` row per context tier, then a `>200k` row from
  `context_over_200k`, which models.dev now ships as a copy of the first tier (620 of 620 models). A
  200k tier doubled (31 refreshed models unresolvable); a 272k or 256k tier gained a `>200k` premium
  (76 models). The cache stores converted rows behind an ETag and models.dev answers 304, so a code
  fix alone never reached it.
- Fix: the legacy field is read only without a context tier, and a repeated tier label is dropped;
  `catalog_snapshot()` stamps `converter = 2L`; `catalog_read_cache()` ignores a cache of another
  converter (`catalog_read_base()` falls back to the snapshot) and `catalog_refresh()` sends
  `If-None-Match` only for a current one. `prices_df()` stays strict. NEWS entry; 04 sections 11.9,
  11.10 amended.
- Green: `^catalog-models$` PASS 420; with provider-registry, provider-usage, s1-ollama,
  gptr-gateway, gptr-config, arch-layers and lint-rules PASS 2601. Lint clean. Live (models.dev,
  2026-10-22, an old converter-less cache plus a stale ETag in place): the snapshot was used, the
  refresh downloaded in full, 693 refs resolve with 0 failures; grok-4.7 `default, >200k`,
  gpt-5.6-terra `default, >272k` at $2/M for 250k.
- Deviations: D-250. Open: the maintainer's online `dev/catalog/build_models.R` run, after prompt-1;
  the shipped snapshot is not converter-checked.

### catalog-2 - An alias with no model in the catalog is an unknown-model error, not a fuzzy match
- Finding 35. Red: `^catalog-models$` FAIL 3, PASS 422: with the seed catalog
  `model_resolve("gemini")` and `"gemini:high"` returned google/gemini-3.8-flash, and
  `strict = FALSE` returned it instead of NULL.
- Cause: the seed has no Gemini Pro, so the `gemini` alias target is NA; `model_match()` then went
  on to the provider and fuzzy steps, whose substring match picked Flash, and `model_resolve()`'s
  alias error covered only a target whose provider is not registered.
- Fix: `model_match()` stops at an alias name without a model (either case) and carries the alias;
  `model_lookup()` keeps it behind a thinking suffix; `model_resolve()` says the alias names no
  model and to run `gptr_models(refresh = TRUE)` or name a `provider/id`. The orchestration skill's
  two `"gemini"` examples use `"flash"`. NEWS entry; 04 section 11.10 amended.
- Green: `^catalog-models$` PASS 425 (a models.dev-shaped gemini-3.1-pro-preview resolves as
  `gemini`); with provider-registry, provider-usage, s1-ollama, gptr-gateway, gptr-capture,
  gptr-config, subagent-backends, agent-run, arch-layers and lint-rules PASS 3779. Lint clean.
- Review fix: the alias stop came before IC-19's provider step, so a registered provider named like
  an alias without a model (`gptr_provider("gemini", models = corp-gemini)`) raised the alias error
  instead of running gemini/corp-gemini, as main did. It now follows the provider step and still
  precedes the fuzzy step. Red `^catalog-models$` ERROR 1, PASS 455; green PASS 457; catalog-*,
  provider-registry, gptr-gateway, gptr-config, subagent-backends, agent-run, arch-layers and
  lint-rules PASS 3062. Lint clean; 04 section 11.10 and the D-250 rule amended.
- Deviations: D-250 (catalog-2 rule). Open: none.

### prompt-1 - Cap the output reserve at half the window, and blame compact_at when it sets the threshold
- Findings 51, 160 (sessions-25). Red: `^prompt-compact$` FAIL 4, PASS 344: `compact_threshold()` of
  (524288, 524288), (262144, 262144) and (131072, 131072) gave -8,000; `^prompt-sections$` FAIL 11,
  PASS 383: `peter()` on a fake model with context = max_output = 131072 was refused at freeze ("too
  small", threshold -8,000), a 1,050,000-token model with `compact_at = 5000` was refused with
  `arg = "model"`, and both refusals hinted `preset = "minimal" or context = "names"`.
- Cause: `compact_threshold()` reserved `max(16384, max_output + 2 * r_cap)` with max_output
  unbounded, and models.dev often gives the whole window as max_output (40 refreshed models
  refused); the request builders sent that value as `max_tokens`. `prompt_floor_check()` used the
  compact_at wording only for an unknown window, and `peter()` takes `preset =` and `context =` as
  context objects (`context = "names"` never lowers the floor).
- Fix: `model_output_cap()` (`R/prompt-compact.R`), min(max_output, window / 2), in
  `compact_threshold()`, `prompt_request_context()` and `request_fallback()`; the refusal names
  compact_at when the threshold equals the cap alone, and hints `tools = "minimal"` (none for the
  minimal preset). The ten architecture-6.11 expectations hold; no shipped model's max_output
  exceeds half its window. NEWS entry; 03 section 6.11, 04 sections 7.7, 8.1, 15 amended.
- Green: `^prompt-compact$` PASS 351, `^prompt-sections$` PASS 398; prompt-*, agent-*, arch-layers,
  lint-rules, gptr-gateway, gptr-sdk and catalog-models PASS 3199. Lint clean; no Rd change.
- Deviations: D-250 (prompt-1 rule; pointer lines under D-067 and D-069). Open: the refusal does not
  compute the smallest passing compact_at (the floor rises with the 25% re-injection cut).

### ollama-1 - Ollama refusals name gptr_models(), not the unexported model_prepare()
- Finding 54. Red: `^(catalog-models|provider-registry)$` FAIL 8, PASS 1153: the missing-evidence
  refusal (`provider_preflight()` and `provider_stream()`) named `model_prepare()`, the
  endpoint-change refusal named only it ("prepare it again with model_prepare()"), and the
  not-installed text said "then prepare it again".
- Cause: `provider_preflight()` built both evidence refusals around `model_prepare()`, which is
  `@noRd` and not exported; two tests pinned that wording.
- Fix: missing evidence says
  `run gptr_models(provider = "<pid>", refresh = TRUE) while the server runs with
  the model installed`, stale evidence
  `<why>; run gptr_models(provider = "<pid>", refresh = TRUE) again`, not installed
  `then call again`. NEWS entry.
- Green: `^(catalog-models|provider-registry)$` PASS 1161; catalog-*, provider-*, s1-*,
  gptr-gateway, gptr-config, gptr-capture, arch-layers and lint-rules PASS 5943. Lint clean; no Rd
  change.
- Deviations: none (message text; 07 section 2.1 asks only for actionable failures). Open: a new R
  session still needs discovery before its first Ollama call (ollama-2).

### ollama-2 - System 2 prepares a selected Ollama model on a live call, as System 1 does
- Findings 23, 33, 113, 115. Red: `^catalog-models$` FAIL 7, PASS 435:
  `peter("p", model = "ollama/qwen3:1.7b")` reached `provider_stream()` with the undiscovered record
  (tool_call FALSE) and no server call, so the real preflight refused it in every new R session; a
  router's fallback default under replay was not refused.
- Cause: only System 1 prepared (`s1_ready()` -> `model_prepare()`). `run_target()` and
  `run_route()` used `run_model_resolve()` and `provider_stream()` runs only the pure
  `provider_preflight()`, while discovery evidence lives in memory only (07 section 2.1); a saved
  default Ollama model failed in each new session.
- Fix: `run_model_ready()` (`R/agent-run.R`) for `run_target()`, `route_answer()` and
  `route_default()`: an Ollama route not named by a session-only provider passes `replay_guard()`,
  then `model_prepare(ref, safety =
  stream_safety(NULL, run))`; a router's thinking is clamped to the prepared levels. 07 section 2.1
  and the 04 `model_prepare()` row amended; NEWS entry.
- Green: `^catalog-models$` PASS 443; agent-*, catalog-*, provider-*, s1-*, session-*, prompt-*,
  compaction-*, subagent-*, gptr-gateway, gptr-config, arch-layers and lint-rules PASS 10890 (SKIP
  1, Windows only). Lint clean; no Rd change. Live (Ollama 0.40.8, fresh process, no
  `gptr_models()`): `ollama/qwen3.8:27b` answered "OK" (24.7 s), evidence held for that model only,
  and a tool run returned 20.091 (20.0 s).
- Deviations: D-250 (ollama-2 rule). Beyond the plan: the `replay_guard()` line, since
  `route_default()` (after `router.call` fails, as under replay) has no earlier guard, and the test
  fixture drops `num_ctx` (8K is below the standard preset's compaction floor). Open: that fallback
  still sends a non-Ollama default's request under replay (by reading; pre-existing). The
  lmstudio/llamacpp/vllm tools note is sheet entry S17.

### catalog-3 - An unknown model on a route with no catalog models says a refresh fills it
- Findings 30, 41. Red: `^catalog-models$` FAIL 1, PASS 443: with the seed catalog
  `model_resolve("groq/llama-x")` said only "Unknown model reference 'groq/llama-x'." (no
  suggestions, no remedy).
- Cause: the shipped snapshot is seed-only (anthropic 4, google 1, ollama 2, openai 2, typesafe 1),
  so every openrouter, groq, deepseek, mistral, together, xai, cerebras, fireworks, azure or bedrock
  id is unknown until `gptr_models(refresh = TRUE)`, and `model_resolve()` gave no hint; the
  provider-scoped suggestions are empty.
- Fix: `model_resolve()` adds "The catalog lists no <pid> models yet; gptr_models(refresh = TRUE)
  downloads them from models.dev." when the reference names a models.dev route
  (`catalog_modelsdev_ids()`) with no catalog row, also with a thinking suffix. 04 `model_resolve()`
  row amended; NEWS entry.
- Green: `^catalog-models$` PASS 452 (anthropic/claude-nope keeps its suggestions and no hint; a
  user-registered provider gets no hint); catalog-*, provider-registry, gptr-gateway, agent-run,
  s1-client, session-object, console-commands, arch-layers and lint-rules PASS 3283. Lint clean; no
  Rd change. On the shipped snapshot: groq/llama-3.3-70b-versatile, azure/gpt-x,
  openrouter/openai/gpt-5-mini and xai/grok-4.7:high carry the hint.
- Deviations: D-250 (catalog-3 rule). The plan's condition ("a known provider with no catalog rows")
  is narrowed to models.dev routes, since a refresh brings nothing for a provider the user
  registered. Open: the maintainer's online `dev/catalog/build_models.R` run so the shipped snapshot
  carries these routes (release step, after catalog-1 and prompt-1); the refresh-scope wording is
  sheet entries S16 and S18.

### provider-2 - Model records accept prices as a list of records and check them at registration
- Finding 85. Red: `^ext-specs$` FAIL 1, PASS 305:
  `gptr_provider(..., models = list(list(id = "m", prices =
  list(list(input = 5, output = 25)))))` failed "field 'models[[1]].prices' must be a data frame".
- Cause: `spec_model_rules()` typed `prices` as `df` and `spec_model_metadata()` never normalised
  it, while `prices_df()` (and `gptr_config(providers =)`) take a list of records; a string price or
  duplicate tiers passed registration and failed at the first call with no provider, model or field
  named.
- Fix: `prices = f("df|list")`; `spec_model_metadata()` normalises it and re-raises a bad table as
  `invalid_spec` naming `models[[i]].prices` ("must be a data frame or a list of price records:
  invalid price.input, expected ..."). `?gptr_provider` documents the price shape. NEWS entry; 04
  sections 7.0, 10.2 amended.
- Green: `^(ext-specs|aaa-state)$` PASS 354; ext-*, aaa-state, provider-*, catalog-*,
  session-budget, arch-layers, lint-rules, gptr-config, gptr-gateway and agent-run PASS 6972. Lint
  clean; Rd regenerated.
- Review fix (docs): `?gptr_provider` gave `tier` as `"default"` or `">200k"`, while
  `price_threshold()` takes any `">Nk"` (catalog-1 makes `>272k` and `>256k`); it now reads `">Nk"`
  for prompts above N thousand tokens. `^(ext-specs|zzz|lint-rules)$` PASS 503. Lint clean;
  `man/gptr_provider.Rd` regenerated, `tools::checkRd()` clean.
- Deviations: D-250 (provider-2 rule). The plan's direct `prices_df()` call fails the layering test
  (ext-specs.R is L0, provider-usage.R L1), so P05 provides `prices_df()` as the `prices.table`
  service (IC-09), the pattern of `check.adapter`; without the service the table is checked when the
  model is resolved, as before. Open: a second user registration of the same provider id is ignored
  silently (verifier's side finding; not this unit).

### provider-3 - A provider without a valid base URL names the variable that sets it
- Finding 37. Red: `^provider-registry$` FAIL 5, PASS 735: with `AZURE_OPENAI_ENDPOINT` unset or
  `"not a url"`, `provider_credential(provider_get("azure"))` said "needs a valid configured origin
  before credentials can be bound" with `variables = character()`; a provider without env said the
  same.
- Cause: the no-origin branch of `provider_credential()` ignored the record's `compat$base_url_env`.
- Fix: "Provider <id> has no valid base URL: set <env> (for example with gptr_env()) or
  providers$<id>$base_url with gptr_config()." (`env` joined with " or "; without one only the
  `gptr_config()` clause), `variables =
  env`, class `no_key` kept. With the endpoint set and no key, "Set AZURE_OPENAI_API_KEY" is
  unchanged. NEWS entry.
- Green: `^provider-registry$` PASS 740; provider-*, catalog-models, gptr-config, gptr-gateway,
  s1-*, auth-*, arch-layers and lint-rules PASS 6985 (SKIP 3, platform). Lint clean; no Rd change.
- Deviations: none (message text; 04 section 2.2 `no_key` already carries `variables`). Open: the
  key variable is still reported only after the endpoint is fixed (the verifier's optional one-error
  variant was not planned).

### config-1 - A higher settings layer's array replaces the lower one's
- Finding 39. Red: `^gptr-config$` FAIL 4, PASS 518: `settings_combine()` of two
  `list(a = list(xs = <array>))` kept the lower `xs`; with user-scope `providers.bedrock.models`
  (`user-id`), `options(gptr.providers =)` (`opt-id`) and a session declaration (`session-id`) were
  both ignored, and `model_resolve("bedrock/session-id")` raised `unknown_model` ("Did you mean:
  bedrock/user-id?") while the source read "session".
- Cause: `settings_combine()` delegated to `utils::modifyList()`, which recurses into any two lists
  and applies nothing from an unnamed one, so every nested array resolved to the lowest layer that
  set it.
- Fix: an explicit merge that recurses only where both sides are named lists and otherwise takes the
  higher value; a NULL still removes the key (`budget = list(cost = NULL)`). Every other case
  matches `modifyList()`. NEWS entry.
- Green: `^gptr-config$` PASS 524 (the user `region` is kept); full suite (NOT_CRAN) PASS 35357,
  SKIP 64. Lint clean; no Rd change.
- Deviations: none (restores the rule of the function's doc and `?gptr_config`). Open: none.

### config-2 - gptr_config() warns when an untrusted project will not apply a saved setting
- Finding 32. Red: `^gptr-config$` FAIL 2, PASS 524: in an untrusted project
  `gptr_config(providers =
  list(bedrock = list(models = list(m))))` raised no condition, while
  `settings_get("providers")$bedrock` stayed NULL.
- Cause: with a `.gptr/` workspace the default scope is the project, whose non-tightening keys
  `settings_project_value()` drops while it is untrusted; `gptr_config()` saved them silently, and a
  recorded "no" skips even the one-time trust notice, so `peter()` failed later with a bare "Unknown
  model reference".
- Fix: `settings_untrusted_warn()` runs after a project write when `trust_get()` is FALSE and warns
  `untrusted_setting` (fields `keys`, `path`; once per root and keys) for each key whose untrusted
  contribution differs from the trusted one (`providers` counts as written, so no base-URL question
  is asked), naming `gptr_trust("<root>", trust = TRUE)` and `.scope = "session"`. The write is
  kept. 04 `gptr_config()` and section 2.2 warnings amended; NEWS entry.
- Green: `^gptr-config$` PASS 535; with the 13 other test files that call `gptr_config()`,
  arch-layers and lint-rules PASS 4280. Lint clean; no Rd change.
- Review fix: `permissions` was reported whole, though an untrusted project applies its deny and ask
  rules (`settings_project_value()`, `perm_rules_table()`) and drops only allow. A write with allow
  rules now names `permissions.allow`; deny or ask alone stays silent. Red `^gptr-config$` FAIL 2,
  PASS 569; green PASS 571; with perm-*, arch-layers and lint-rules PASS 1915. Lint clean; NEWS, 04
  `gptr_config()` and the D-250 rule amended.
- Deviations: D-250 (config-2 rule). Open: a project value that loosens a tighten key
  (`mode = yolo`) is dropped silently, trusted or not (section 11.2, not a trust matter).

### config-3 - gptr_config() warns when a saved model setting names no known model
- Finding 58. Red: `^gptr-config$` FAIL 2, PASS 535:
  `gptr_config(model = opuss, .scope = "session")` raised no condition.
- Cause: `model`, `small_model` and `system1` pass `resolve_identifier()`, which returns an unknown
  unbound symbol as its literal name, and the `ident` validator is only `check_string()`; nothing
  read the catalog until the next bare `peter()` (in every later session, for a user-scope value),
  while the console's `/model` checks with `model_canonical(strict = TRUE)`.
- Fix: `settings_model_warn()` runs after the write: each of the three keys (`system1` less
  `emulate:`; a registered router or `router:` passes) goes through
  `model_canonical(strict = TRUE)`, and an `unknown_model` becomes warning `unknown_model_setting`
  (fields `key`, `ref`) quoting that message and the undo call. The value is kept. 04
  `gptr_config()` and section 2.2 warnings amended; NEWS entry.
- Green: `^gptr-config$` PASS 546 (opus, haiku, `emulate:sonnet`, `ollama/any-tag:1b`, a router by
  name and as `router:` stay silent); 20 neighbour files PASS 5657; full suite (NOT_CRAN) FAIL 0,
  WARN 0, SKIP 64, PASS 35379. Lint clean; no Rd change.
- Review fix: only `unknown_model` was caught, so another resolution error escaped after the save (a
  declared `bedrock/m1` with two default price rows: `invalid_argument` "Invalid prices", yet the
  session held the value; main was silent). Any other `gptr_error` is now ignored and left to the
  call that uses the model. Red `^gptr-config$` FAIL 1, PASS 566; green PASS 568; with
  catalog-models, provider-usage, arch-layers and lint-rules PASS 1334. Lint clean; 04
  `gptr_config()` and the D-250 rule amended.
- Deviations: D-250 (config-3 rule). The warning quotes the `unknown_model` message instead of
  rebuilding its suggestions, so catalog-2's alias and catalog-3's refresh hints carry over. Open:
  the use-time error of a bad saved model still does not name its settings layer (the verifier's
  optional step 2, not planned).

### config-4 - A gptr_init() project no longer pins mode and record, and a trusted project may set mode
- Finding 16 (items 2 and 3). Red: `^gptr-config$` FAIL 9, PASS 553: after
  `gptr_config(mode = auto, record =
  "auto", .scope = "user")` and `gptr_init()`, `gptr_config()` gave `manual` and `ask` from
  `[project]`; a trusted project's `{"mode": "auto"}`, and `gptr_config(mode = auto)` at the default
  project scope, resolved `manual`; `gptr_config(mode = yolo)` was saved to the project; the
  template read `version, mode, record`.
- Cause: the template pinned the defaults `"mode": "manual"` and `"record": "ask"`, and
  `settings_project_value()` applies a tighten-type key from any project, so the pinned `manual`
  beat a user-level `auto`; its tighten branch also ran for a trusted project, which could never
  loosen the mode it saved.
- Fix: the template is `{"version": 1}`; a trusted project's `mode` applies as written unless it is
  `yolo` (or no mode); `settings_config_value()` refuses `mode = yolo` at project scope
  (`invalid_argument`, naming `.scope =
  "user"` and `"session"`). config-2's warning now names `mode` when an untrusted project saves a
  looser one. `?gptr_config`, the configuration vignette (.Rmd and .Rmd.orig), 04 and 03 amended;
  NEWS entry.
- Green: `^gptr-config$` PASS 566 (the template pin is now `list(version = 1L)`); full suite
  (NOT_CRAN) FAIL 0, WARN 0, SKIP 64, PASS 35399. Lint clean; `man/gptr_config.Rd` regenerated; plan
  checks pass.
- Deviations: D-250 (config-4 rule). Narrower than planned: the plan freed every tighten-type key of
  a trusted project; only `mode` is freed, since a project `record = "auto"` would be write consent,
  which IC-45 reserves to the person (req-7, P15 acceptance 5), and `context` bounds what reaches
  providers. Beyond the plan: the write-time refusal of a project `yolo`, because
  `settings_guard()`, which the plan said refuses it, covers only `providers`; the value was dropped
  silently. Open: the blocked-run hint (item 4) is orchestration's gate-hint; projects made earlier
  keep their pinned file (NEWS says to delete the two keys); a project `record = "auto"` or a looser
  `context` is still saved without a word in a trusted project.

### thinking-1 - bedrock-converse sends the thinking level to Claude models
- Findings 40, 79 and 88. Red: `^provider-bedrock$` FAIL 3, PASS 152: with `thinking = "high"`, an
  adaptive and a budget Claude record got no `additionalModelRequestFields`.
- Cause: `bedrock_build()` read only `params$max_tokens` and `temperature`, though
  `prompt_request_context()` puts the level in `params$thinking`; D-193 cut the request side, so
  every level, `:max` and `off` sent one body and nothing said so, while the normaliser already
  decoded and replayed signed reasoning.
- Fix: `bedrock_thinking()` gives a Claude id (`anthropic.claude`) the fields of
  `anthropic_thinking()` in `additionalModelRequestFields`; `anthropic_thinking()` now holds the
  budget clamp (moved from `anthropic_build()`) and returns `max_tokens`, which a budget sets as
  `inferenceConfig.maxTokens`. Another model's level gives a `notice` once per model.
  `?gptr_provider`'s example declares `reasoning` and the adaptive capabilities; IC-80 amended; NEWS
  entry.
- Green: `^provider-bedrock$` PASS 163; provider-anthropic, ext-specs, live-bedrock and lint-rules
  PASS 1096 (SKIP 2, live); full suite (NOT_CRAN) FAIL 0, WARN 0, SKIP 65, PASS 35413. Live on the
  Versa gateway: `^live-bedrock$` PASS 6 (Opus 4.8 declared adaptive returns signed thinking at
  `high`); Sonnet 4.6 on a budget with `anthropic_beta` returns signed thinking. Lint clean;
  `man/gptr_provider.Rd` regenerated.
- Review fix (docs): the NEWS bullet's first line was 101 columns, over the 100-column rule;
  rewrapped (no NEWS line now exceeds 100).
- Deviations: D-250 (thinking-1 rule), pointer under D-193. Beyond the plan: test-live-bedrock.R
  registers its endpoint through one local helper for both live tests. Open: an Opus 4.8 record
  declared without `capabilities` and given a level now gets the provider's HTTP 400 ("Use
  thinking.type.adaptive ...") instead of a silent no-op (fixed by thinking-1b); `:max` still clamps
  to `high` on a record without `thinking_levels` (thinking-4); `usage$reasoning` stays 0 on
  Converse.

### thinking-3 - A string that is not one of the choices is reported as such
- Finding 161. Red: `^utils-conditions$` FAIL 3, PASS 64: `check_choice("ultra", c("off", "high"),
  "thinking")` said "must be one of "off", "high", not a character of length 1." and `"HIGH"` got no
  hint.
- Cause: `check_choice()` and `gateway_choice()` fell through to `arg_abort()`, which describes
  class and length only, so a right-typed value that is not a choice read as a type error
  (`.opts$thinking`, `.opts$context`, `replay`, `.scope`).
- Fix: `choice_abort()` (`R/utils-conditions.R`), called by both: a string gets "...; the string
  given is not one of them." plus "Did you mean "<choice>"?" when it equals a choice but for case
  (the hint names the choice, never the value); anything else keeps `arg_abort()`. 04 section 1.1
  amended; NEWS entry.
- Green: `^utils-conditions$` PASS 70 (a fake key is still never quoted;
  `peter(.opts = list(thinking =
  "ultra"))` gives the new text); gptr-capture, gptr-config, gptr-gateway, doc-replay, arch-layers
  and lint-rules PASS 2039. Lint clean; no Rd change.
- Deviations: D-250 (thinking-3 rule). Open: NA still reads "not a character of length 1" (not a
  string).

### thinking-4 - A clamped thinking level is announced once
- Finding 167. Red: `^(agent-run|catalog-models)$` FAIL 2, PASS 1120:
  `peter("x", model = "fake/fake-1", .opts =
  list(thinking = "max"))` (levels off..high) sent `high` and `model_resolve("opus:off")` gave
  `low`, both with no message.
- Cause: `model_clamp_thinking()` moves a level the model lacks to the nearest it has (IC-74, by
  design), and its callers (`run_target()`, `run_model_resolve()`, `route_answer()`,
  `model_resolve()`) did it silently; a reasoning record without `thinking_levels` gets off..high,
  which `?gptr_provider` never said.
- Fix: `model_clamp_thinking(levels, level, ref)` informs `thinking_clamped` ("<ref> has no thinking
  level "<asked>"; using "<got>".") once per model and level when the level changes; the four
  callers pass the model's ref, `prompt_request_context()` stays silent. Same clamp in four lines
  (1179 level/subset cases equal the old body). `?gptr_provider` documents `thinking_levels`. 04
  sections 2.2 and 4.9 `thinking` row, 03 section 8.4 amended; NEWS entry.
- Green: `^(agent-run|catalog-models)$` PASS 1122 (a second identical call and `high` stay silent);
  full suite (NOT_CRAN) FAIL 2, WARN 0, SKIP 65, PASS 35417, both in `proc-rscript-native`
  artifact-cancel (a `ps` memory sample of the cancelled child got `access_denied`, with three other
  worktrees' suites running), which alone passes (PASS 132). Lint clean; `man/gptr_provider.Rd`
  regenerated.
- Deviations: D-250 (thinking-4 rule). Open: the sheet line is entry S15; the session still records
  the requested level (`session_data()$thinking`).

### bedrock-docs - Say that bedrock-converse requests no prompt caching
- Finding 89 (docs only). The verifier measured 0 cache reads over 7 requests on Opus 4.8 through
  the Versa gateway; with three injected `cachePoint`s the same run read 36,145 cached tokens (about
  70% less input cost), so the gateway accepts them.
- Cause: `bedrock_caps()` declares `cache = "none"` and `bedrock_build()` writes no `cachePoint`
  (IC-80, D-193, P26 open item), while NEWS promised prompt caching "where the model supports them",
  which Claude on Bedrock does.
- Fix: the NEWS providers bullet says "not yet through `api = "bedrock-converse"`";
  `?gptr_provider`'s bedrock-converse example and the language-models vignette (.Rmd and .Rmd.orig,
  which now also points to `api = "bedrock-converse"` for SigV4) say the adapter requests no
  caching, so each request sends the full prompt at the uncached rate.
- Green: `^(ext-specs|zzz)$` PASS 457; `tools::checkRd()` clean. Lint clean; `man/gptr_provider.Rd`
  regenerated.
- Deviations: none (the specs already state it). Open: Converse `cachePoint`s (plan anchors, the
  four-point limit, `cacheDetails[].ttl` attribution in the normaliser), a feature.

### capture-1 - A spec bound to an alias name gets the alias-shadowed notice
- Finding 92. Red: `^gptr-capture$` FAIL 2, PASS 361: `opus = gptr_fake_provider(...)` and `grep =
  gptr_tool("mygrep", ...)` resolved to the alias "opus" and the built-in "grep" with no
  `alias_shadowed`.
- Cause: `ident_shadow_notice()` spoke only for a character variable. The known identifier wins by
  design (packages export `claude`, `plan`, `write`), but a spec, which only a gptr user makes, was
  dropped silently.
- Fix: a spec the argument accepts (`ident_spec_ok()`) counts as its `name`, then the character rule
  applies; a function or another object stays silent. 03 section 4.1.3 and 04 section 6.1.3 amended;
  NEWS entry.
- Green: `^gptr-capture$` PASS 363; with gptr-gateway and gptr-config PASS 1284; full suite
  (NOT_CRAN) FAIL 0, WARN 0, SKIP 65, PASS 35437. Lint clean; no Rd change.
- Deviations: D-250 (capture-1 rule). The plan's trigger (every accepted spec) also fired for
  `local = gptr_provider("local", ...)` registered and passed as `model = local` (measured), which
  names the same provider; comparing `name` keeps it silent. Open: a call such as
  `model = if (x) haiku else opus` is evaluated in the alias mask and stays silent (by design, 03
  section 4.1.3).

### s1-1 - System 1 arguments on a conversational model are refused, as .opts$system1_images is
- Finding 132. Red: `^gptr-gateway$` FAIL 3, PASS 355:
  `peter("Which?", model = fake, choices = c("a",
  "b"))`, and the same with `levels`, `threshold = 0.7`, `min_confidence` or `uncertain`, returned a
  session without a word.
- Cause: `gateway_args()` validates the five arguments, but only the classifier route reads them;
  the nested, continue and new routes refused only `.opts$system1_images`
  (`route_refuse_s1_images()`, IC-74 section 4).
- Fix: `route_refuse_s1_args()` replaces it at its three call sites. After the images check it
  refuses the first of `choices`, `levels`, a `threshold` other than 0.5, `min_confidence` and
  `uncertain` as `invalid_argument` naming it, pointing to `jev` or `"ollama/clef-flash"` (after
  `gptr_config(system1 =
  "emulate:<ref>")`, `model = jev` runs a chat model). The continue route and a configured default
  chat model refuse too; an explicit `threshold = 0.5` runs. `?peter`, 03 section 4.1 and 04
  section 6.1.1 step 5 amended; NEWS entry.
- Green: `^gptr-gateway$` PASS 384; with s1-route and arch-layers PASS 720; full suite (NOT_CRAN)
  FAIL 0, WARN 0, SKIP 65, PASS 35466. Lint clean; `man/peter.Rd` regenerated, `tools::checkRd()`
  clean.
- Review fix: the remedy said to opt into emulation with `gptr_config(system1 = "emulate:<ref>")`,
  but emulation answers only `model = jev` or `"emulate:<ref>"` (`s1_target()`), so the setting
  alone left the call refused with the same advice. It now names `model = jev` (also `expected`,
  `?peter`, NEWS, 04, D-250; 03 section 4.1 never named the setting). Red `^gptr-gateway$` FAIL 5,
  PASS 381; green PASS 386; with s1-route, arch-layers, zzz and lint-rules PASS 937. Lint clean;
  `man/peter.Rd` regenerated, `tools::checkRd()` clean.
- Deviations: D-250 (s1-1 rule). Open: the `team` and `fanout` routes (`agents =`, `parallel =`)
  still drop these arguments and `.opts$system1_images` (measured: `parallel = 2, choices =` ran two
  sub-agents; fixed by s1-1b). The sheet's System 1 card can say these arguments need a decision
  model (the sheet is edited later).

### s1-2 - The uncertain = "stop" error names the uncertain inputs and carries the answers
- Finding 127. Red: `^s1-route$` FAIL 10, PASS 299: for `c(trial, weeks, chose, pilot)` with P(yes)
  0.98, 0.12, 0.05, 0.32 and `min_confidence = 0.8`, the error had no `index`, `names`, `confidence`
  or `value`, and its message ended "(confidence below 0.8)." without naming an input.
- Cause: `s1_abstain()` built the condition from `prob = unname(gptr_prob(out)[unsure])` only:
  P(yes) or the chosen option's probability, not the confidence the band tests, and the abort before
  `s1_record()` discarded every other answer.
- Fix: the condition adds `index`, `names` (`NULL` for unnamed input), `confidence` and `value` (the
  whole answer); `prob` stays (the IC-74 test pins it). The message lists the first ten names, a
  position where a name is empty, "and N more" beyond, and a second line: "The error's $value holds
  every answer; uncertain = NA keeps the others." 04 section 2.2 row amended; NEWS entry.
- Green: `^s1-route$` PASS 309 (unnamed input lists "2, 4"; a choice reports its stored confidence
  0.91, not the chosen 0.94); the `s1-*` files PASS 1435. Lint clean; no Rd change.
- Deviations: D-250 (s1-2 rule). The plan's second line, "e$value holds every answer", names a
  variable the user may not have; it reads "The error's $value". Open: the system-one vignette does
  not describe the fields (the message does).

### s1-3 - as.data.frame() of a score names its probability columns by level
- Finding 125. Red: `^s1-types$` FAIL 2, PASS 217: a score with levels "Very negative", "Neutral",
  "Very positive" gave the columns `p_0`, `p_1`, `p_2`, while `gptr_prob(x, "probabilities")` and a
  choice use the level names.
- Cause: `as.data.frame.gptr_s1()` named a score's columns by 0-based level index, against 04
  section 5.2's `p_<level>`; P13's test copied that deviation, and no user doc mentioned it.
- Fix: every type takes `colnames()` of the stored matrix (levels are unique, `s1-client.R`). NEWS
  entry.
- Green: `^s1-types$` PASS 219 (the new test ties both accessors for a choice and a score); the
  `s1-*`, `copy-s1` and `s11-conformance` files PASS 1504. Lint clean; no Rd change.
- Deviations: none (the contract already says `p_<level>`). Open: none.

### s1-4 - A factor-returning choice keeps its errors, and the factor result is documented
- Finding 131. Red: `^s1-route$` FAIL 1, PASS 314: with the mocked /systemone answering one of two
  states without probabilities, `choices = factor(c("liver", "lung", "other"))` warned "see attr(x,
  "meta")$errors" and returned a factor whose `meta` was NULL.
- Cause: `s1_run()` returns `factor(s1_bare(out), levels = q$options)` (by design, P13, INFRA-18),
  and `s1_bare()` strips every attribute after `s1_failures()` has warned; no user doc said a factor
  comes back.
- Fix: the factor keeps `meta = list(errors = <df>)` when elements failed and nothing else. `?peter`
  (System 1 arguments paragraph), `?gptr_prob` and the system-one vignette (.Rmd and .Rmd.orig) say
  that factor `choices` or `.opts = list(output = "factor")` return a plain factor without
  probabilities. 03 section 4.1.5 amended; NEWS entry.
- Green: `^s1-route$` PASS 316 (an answer without failures has only names, levels and class);
  s1-route, s1-types and gptr-gateway PASS 919; full suite (NOT_CRAN) FAIL 0, WARN 0, SKIP 65, PASS
  35492. Lint clean; `man/peter.Rd` and `man/gptr_prob.Rd` regenerated, `tools::checkRd()` clean.
- Deviations: D-250 (s1-4 rule). The plan kept the whole `meta`, which `print.factor()` prints with
  every answer (63 lines for two elements, measured, instead of 3); only `errors`, and only on
  failure, makes the warning true without that. Open: `gptr_prob()` on a factor still says only that
  `x` is not a `gptr_s1`.

### s1-5 - Say what confidence means where min_confidence is offered
- Findings 121 and 128. Red: `^s1-types$` FAIL 1, PASS 221: the guard's numbers already held
  (`s1_confidence_choice(c(.9, .05, .05))` 0.85, `s1_ollama_confidence()` 0.641), but
  `man/gptr_prob.Rd` did not give that example; `?peter` covered `min_confidence` and `uncertain`
  only as "System 1 answer shape and abstention".
- Cause: no user doc defined confidence. For yes/no it is `abs(2 * p - 1)`, so 0.8 abstains for 0.1
  < p < 0.9, not "80% sure"; for choices and scores each engine keeps its own measure (D-078 item 2,
  D-120), Jev's peak or MAD formula against Clef's entropy, and `?gptr_prob` and the vignette said
  only "concentration".
- Fix: docs only. `?peter` splits out `min_confidence` (the definition, the 0.8 band, the engine's
  own scale) and `uncertain` (`NA`, `TRUE`/`FALSE` for yes/no only, `function(state, answer)`,
  `"stop"`; no effect without `min_confidence`). `?gptr_prob` @details gives the three formulas and
  the 0.85 vs 0.64 example; the system-one vignette (.Rmd and .Rmd.orig) adds the example and
  "re-tune `min_confidence` when you switch engine".
- Green: `^s1-types$` PASS 222; s1-types and gptr-gateway PASS 606; lint-rules, zzz, s1-client and
  s1-ollama PASS 834. Lint clean; `man/peter.Rd` and `man/gptr_prob.Rd` regenerated,
  `tools::checkRd()` clean.
- Deviations: none (04 section 6.1 already defines the band). The guard also reads
  `man/gptr_prob.Rd` (skipped when installed, as test-agent-background.R does), so the example
  cannot drift from the code. The verifier's "the same value is stricter on Clef" is not used:
  0.50/0.50/0 gives 0.25 on Jev and 0.37 on Clef (measured).
- Open: the sheet's S14 caption is applied by the sheet commit.
  `peter("Is it?", "p=0.85", model = <System 1
  model>)` still warns `two_prompts` "the second is context" (finding 121's side note; measured at
  HEAD, not planned).

### thinking-1b - An undeclared Claude record on bedrock-converse gets no thinking, never an HTTP 400
- Review of thinking-1 (high). Red: `^provider-bedrock$` FAIL 3, PASS 160: a record shaped like the
  live `m$claude` (`us.anthropic.claude-opus-4-8`, `reasoning = TRUE`, no `capabilities`) got
  `thinking` `enabled` with a budget at `high` and `max`, and no notice.
- Cause: `model_capabilities()` fills undeclared flags with `FALSE`, so thinking-1 sent every Claude
  record without `adaptive_thinking` a budget; Opus 4.8 refuses it ("thinking.type.enabled is not
  supported for this model", HTTP 400, `gptr_error_provider`), where main sent nothing and answered.
- Fix: `bedrock_thinking()` sends thinking only to a Claude record declaring `adaptive_thinking`
  (adaptive fields); any other model gets none and a notice once per model naming
  `capabilities = list(adaptive_thinking =
  TRUE, effort = TRUE)`. The budget path and `anthropic_beta` leave `bedrock_build()`. IC-80,
  `?gptr_provider`'s example comment, NEWS and the D-250 rule (why: no budget declaration, no id
  inference) amended.
- Green: `^provider-bedrock$` PASS 163; provider-bedrock, provider-anthropic, ext-specs,
  live-bedrock, lint-rules, zzz and arch-layers PASS 1285 (SKIP 3, live); full suite (NOT_CRAN)
  FAIL 0, WARN 0, SKIP 66, PASS 35503. Lint clean; `man/gptr_provider.Rd` regenerated. Live (Versa
  gateway, installed branch): `m$claude` at `high`, `max` and `:high` answers "ready" (one notice;
  `max` also the thinking-4 clamp message); Opus 4.8 declared adaptive at `high` returns a thinking
  block; `^live-bedrock$` PASS 7 (+1: an undeclared record answers at `high`).
- Review fix (simplicity): with the budget path gone, thinking-1's refactor of the
  anthropic-messages adapter (the budget clamp moved from `anthropic_build()` into
  `anthropic_thinking()`, which returned `max_tokens`) had no second caller, so it is reverted:
  `R/provider-anthropic.R` is main's again, and `bedrock_thinking()` reads only the `thinking` and
  `effort` that main's `anthropic_thinking()` returns. provider-anthropic, provider-bedrock and
  arch-layers PASS 782; the D-250 sentence about the clamp is deleted.
- Deviations: D-250 (thinking-1 rule rewritten in place; D-193 pointer). Open: Claude 4.5 and
  earlier on Converse get no thinking (no budget declaration exists); `usage$reasoning` stays 0 on
  Converse.

### s1-1b - Teams and fan-outs refuse System 1 arguments too
- s1-1's open item. Red: `^subagent-team$` FAIL 7, PASS 347:
  `peter("Which tissue?", b, parallel = 2, choices =
  c("liver", "lung"))`, a team (`agents = list(a = agent(...))`) with `levels =`, and a fan-out with
  `.opts$system1_images` returned sessions (5 fake requests), while `?peter` says a conversational
  model refuses them.
- Cause: only P08's `nested`, `continue` and `new` routes call `route_refuse_s1_args()`; the `team`
  (15) and `fanout` (16) routes match first on `agents =` / `parallel =`, and the layering test kept
  P19 (L4) from the P08 helper.
- Fix: `subagent_route_checks()` ends with `route_refuse_s1_args(call)` (the same error, before any
  child starts); `arch_contract_edges()` admits subagent -> `route_refuse_s1_args`. 04 section 6.1.1
  step 5 names both routes and the edge; NEWS bullet amended. `?peter` already states the behaviour.
- Green: `^subagent-team$` PASS 354; gptr-gateway, arch-layers, s1-route, lint-rules,
  subagent-backends, subagent-defs, copy-subagent and zzz PASS 1245; full suite (NOT_CRAN) FAIL 0,
  WARN 0, SKIP 66, PASS 35510. Lint clean; `devtools::document()` changes nothing. Live (installed
  branch): `m$gpt`, `m$claude` and `m$ollama` with `choices =, parallel = 2` and with
  `levels =, agents =` (two members) each raise `invalid_argument` naming the argument in 0.2 to 0.3
  s; `gptr_usage()` has no row.
- Deviations: D-250 (s1-1 rule edited in place). Open: the classifier route (order 10) ignored
  `agents =` and `parallel =` given with a decision model (measured offline: a classifier fake with
  `parallel = 2` or `agents =` returned a `gptr_decision`), where this refusal's advice led; fixed
  by s1-1c.

### s1-1c - A decision model refuses agents = and parallel =, and a call without a model is "this call"
- Review of s1-1b (low). Red: `^s1-route$` FAIL 5, PASS 316: with a classifier fake,
  `peter("Is it fine?", x,
  model = judge, agents = list(a = agent(...)))` and the same with `parallel = 2` returned a
  `gptr_decision` (one fake request, the argument ignored); `^subagent-team$` FAIL 1: a team naming
  no model was told "the model of this call is conversational".
- Cause: the classifier route (order 10) matches before `team` (15) and `fanout` (16) and never read
  `agents` or `parallel`, so s1-1b's advice "Use a decision model" led to a silent drop (IC-74
  section 4); `route_refuse_s1_args()` named the call's model when the call had none.
- Fix: `s1_call()` refuses `agents =` (`length(call$ids$agents)`), then `parallel =`, as
  `invalid_argument` naming it ("... a decision model answers in one call (an answer per input
  element); drop `agents =`."), before `s1_ready()`; with no model the refusal says "this call is
  conversational". `?peter` (`agents`), 03 section 4.1, 04 section 6.1.1 step 5 and the NEWS bullet
  amended.
- Green: `^s1-route$` PASS 321; s1-route, subagent-team, gptr-gateway, arch-layers, lint-rules, zzz,
  copy-s1 and s1-types PASS 1522; full suite (NOT_CRAN) FAIL 0, WARN 0, SKIP 66, PASS 35515. Lint
  clean; `man/peter.Rd` regenerated, `tools::checkRd()` clean. Live (installed branch): a team
  naming no model with `levels =` on `m$gpt`, `m$claude` and `m$ollama` reads "this call is
  conversational"; `"ollama/clef-flash"` and `jev` emulated on `m$gpt` and `m$claude` refuse
  `agents =` and `parallel = 2` naming the argument in 0.1 to 0.3 s with no usage row; dropping
  them, `jev` on `m$gpt` answers a `gptr_decision` (the local clef-flash copy answered HTTP 400
  "format that is no longer supported", a stale Ollama download).
- Deviations: D-250 (s1-1 rule edited in place). The reviewer's smaller alternative (a team wording
  in `subagent_route_checks()`) is not used: it would leave the drop. Open: none.

## FIX-18 - Cheat-sheet review: sessions (2026-10-22, #77)

### tools-3 - Unknown names in tools = are refused, not silently ignored
- Red: FAIL 11 in `^gptr-gateway$` (PASS 357; finding 8): `tools = extendd`, `"Extended"`,
  `"-wirte"` and `"+gerp"` raised nothing and sent the request with the standard preset's tools,
  `c(readonly, extended)` ran `readonly`, and a continuation's `"+gerp"` ran.
- Cause: an unknown bare symbol is a literal string (`ident_symbol()`), `gateway_tool_mods()` passes
  every non-preset name on, `preset_tools()` unions or drops it and `prompt_tool_array()` leaves an
  unregistered name out with only a `missing_tool` diagnostic; `gateway_preset()` took the first
  preset.
- Fix: `prompt_tools_check()` refuses a call's name (`+`/`-` stripped) that names no tool of the
  session, hinting the closest preset or tool (`utils::adist()`, case-insensitive, at most 2). It
  runs in `prompt_compose_preset()` for run options that carry the call (after `session_start`; the
  run's startup failure re-signals it before any request) and, for a continuation, in
  `gateway_checks()` after the call's specs register (in `gateway_continue_session()` until
  gateway-1's r5). `gateway_preset()` refuses two presets. `?peter` `tools`: a bare name adds.
- Green: `^gptr-gateway$` PASS 368, `^prompt-sections$` PASS 387;
  `^(prompt-|gptr-|subagent-|arch-layers$|lint-rules$)` PASS 3383 SKIP 1. Lint clean.
- Review: r1 (low) applied. A continuation's `tools = c(readonly, extended)` passed
  `prompt_tools_check()` (presets dropped) and was refused only in `gateway_run_opts()`, after its
  model and mode switched (2 entries). It now calls `gateway_preset()` beside
  `prompt_tools_check()`. Red FAIL 1 (model `fb/fb-1`, mode `plan`, 5 entries for 3). Green
  `^gptr-gateway$` PASS 409; `^(gptr-|prompt-sections$|subagent-team$|copy-gateway$|arch-layers$|
  lint-rules$)` PASS 2254. Lint and check-plans clean.
- Deviations: D-251. From the plan: an agent definition's allowlist (sub-agent run options carry no
  call) stays unchecked, so a file agent's `mcp__` tool that is not loaded still degrades quietly.
  Open: a preset named in a continuation's `tools =` is still ignored; `gptr_config(preset =)` still
  accepts an unknown preset (finding 8, in passing).

### sessions-3 - A continuation's .opts$thinking applies without model =
- Red: FAIL 3 in `^gptr-gateway$` (PASS 369; findings 29 and 200): `s |> peter("y", .opts =
  list(thinking = "low"))` sent `high` and kept it, a session started without a level stayed
  without one, and a router session's level stayed NULL.
- Cause: `gateway_continue_session()` read `.opts$thinking` only inside
  `if (!is.null(call$ids$model))`; the level lives only on the session (`d$thinking`).
- Fix: without `model =`, a level goes through
  `kernel_model_switch(s, d$model, th, reason = "user")` (clamped; `model_change` only when it
  changes; a router keeps its model and takes `d$thinking`). `?peter` `.opts`: `thinking` applies to
  this call and the session's later turns.
- Green: `^gptr-gateway$` PASS 372; `^(gptr-|arch-layers$|lint-rules$|session-object$|agent-run$)`
  PASS 2620. Lint clean.
- Deviations: D-251 (extended). Open: none (the Bedrock and announced-clamp parts of finding 200
  belong to the models group).

### gateway-1 - A call that cannot reach its model changes nothing
- Red: FAIL 1 in `^gptr-gateway$` (PASS 372; findings 101, 67, 80, 106, 130, 140, 142): the refused
  switch to `corp` reached `session_set_model()` before egress. With every case evaluated, FAIL 8: a
  refused new session became `gptr_last()`; a switch to a disabled `openai` stayed, with 2 turns,
  status error and 2 entries, and the next plain pipe was refused for openai. The router test failed
  with `gptr_error_no_key`.
- Cause: `gateway_run()` applied the continuation (model, mode, tools) and `last_set()`
  (`session_new()` too, for a root session) before `gateway_guards()`; key, disabled-provider and
  preflight refusals came in `provider_stream()` after `run_start()` recorded the turn and prompt,
  which `project_structure()` keeps for the next request.
- Fix: `provider_ready()` (disabled provider, preflight; `prepare = TRUE` via `model_prepare()`)
  serves `provider_stream()` and `gateway_guards()`, which after egress and replay adds
  `stream_chat_model()` and `provider_credential(register = FALSE)`. A continuation guards its
  target before any change; a refused new call restores the previous `gptr_last()`. `?peter`; 04
  sections 6.1.2, 7.5.
- Green: `^gptr-gateway$` PASS 386;
  `^(gptr-|provider-registry|provider-transform|console-render|catalog-models|
  agent-run|session-object|subagent-team|copy-gateway|arch-layers|lint-rules)` PASS 4546 (INFRA-04
  included). Full suite FAIL 4 PASS 35297 SKIP 64: three load-timing failures in
  `proc-windows-backpressure` (alone PASS 254) and `console-render` "a failed sub-agent line ...",
  whose session is now made before it mocks the key away. Lint and check-plans clean.
- Review: r1 (high) applied. `router_guards()` ran the new readiness checks too, so a keyless router
  choice raised in `router_call()` and `run_route()` sent the turn to the default model, unchecked
  for egress (1 request). It keeps egress and replay only (`gateway_guards(ready = FALSE)`): the
  choice stops with `gptr_error_no_key` after 0 requests, as on main. Red FAIL 2 (the router test,
  rewritten). Green `^gptr-gateway$` PASS 406;
  `^(gptr-|agent-run$|prompt-compact$|subagent-|provider-registry$|arch-layers$|lint-rules$)`
  PASS 4183 SKIP 1.
- Review: r2 (medium) applied. The readiness checks also ran when a session was only built, so a
  keyless Opus stopped `peter(.run = FALSE)` and the whole `gptr_parallel()` with
  `gptr_error_no_key`, where main returned an idle session and a team whose member ended `error`
  (vignette teams-and-background, `?peter` `.run`). Building passes `ready = isTRUE(call$args$run)`;
  `sdk_check()` (`gptr_step()`, `gptr_wait()`) checks readiness before a run starts, and a member's
  request does. `?peter` `.run`, `?gptr_wait`; 04 section 6.1.2. Red FAIL 1 on 99e12070 (the build
  and, alone, the team). Green `^gptr-gateway$` PASS 414;
  `^(gptr-|agent-run$|subagent-|provider-registry$|
  doc-|console-render$|copy-gateway$|arch-layers$|lint-rules$)` PASS 6542 SKIP 3. Lint and Rd clean.
- Review: r2 documented, then reversed by r3 (7f1da628). A refused continuation was not refused
  "before anything changes": `gateway_register()` runs before `gateway_guards()`, so its extension
  fired on the next turn and its `model =` spec stayed registered. Moving the registration after the
  guards is not safe: they read it (a `model =` spec, a provider an extension registers; tried,
  `model = keyless` became `gptr_error_unknown_model`). r2 only documented the leak (`?peter`, 04
  section 6.1.2 and D-251 said a refused piped call left its extensions, plugins and specs loaded,
  and the refused-call test pinned it). No longer true: since r3 a refused call undoes its
  registrations and keeps no filters, and `?peter`, 04 section 6.1.2, D-251 and the refused-call
  test say so (r3 below). Green (r2) `^gptr-gateway$` PASS 415;
  `^(gptr-|lint-rules$|arch-layers$|zzz)` PASS 1619. Full suite (NOT_CRAN=true, in five filters)
  FAIL 0 PASS 35496 SKIP 64. Lint and Rd clean.
- Review: r3 (medium) applied. A piped `model =` provider spec never switched (on main too): the
  session's spec passed the guards, but `session_set_model()` and `kernel_model_ref()` resolved
  through `model_canonical(strict =
  TRUE)`, the global catalog only, so `s |> peter("next", model = corp)` was
  `gptr_error_unknown_model`, and so was a later `.opts$thinking` on a session started on such a
  spec. `model_canonical(strict = TRUE, session =)` resolves through `run_model_resolve()` (the
  session's rank-0 provider next); both pass the session. Red FAIL 1 (the new spec-switch test).
  Green `^gptr-gateway$` PASS 419; `^(gptr-|session-|agent-|console-commands|ext-|catalog-models|
  arch-layers|lint-rules)` PASS 6505. Lint and Rd clean.
- Review: r3 applied. A refused call still changed something: `gateway_register()` ran before the
  checks with no rollback, so a refused continuation's extension fired on the next turn, its
  `tools =` spec stayed registered and an earlier spec of the same name it replaced was lost, and
  any refused call, new ones too, left its `plugins =
  "-x"` filters in force for the R session. r2's test pinned the leak and passed on its parent
  095268e3 (PASS 415). `gateway_register()` returns an undo
  (`registry_session_mark()`/`registry_session_undo()`: records added removed, records removed put
  back, extensions forgotten, P17's plugin and extension-file table entries restored), which
  `gateway_continue_session()` runs when its tools, preset, guards or filters refuse;
  `gateway_filters_apply(call)` runs after the guards, for new calls too. The refused-call test
  expects none of it. Red FAIL 4 on d3db8eff. Green `^gptr-gateway$` PASS 425;
  `^(gptr-|ext-|skill-|mcp-|subagent-|session-|prompt-|copy-gateway|console-commands|
  arch-layers|lint-rules|zzz)` PASS 8205 SKIP 2. `?peter`, 04 section 6.1.2 (`agents =` dropped: a
  piped team is refused before any registration). Lint and Rd clean.
- Review: r3 documented (low). Since r2 a piped `.run = FALSE` call skips readiness, so its model,
  mode and tools apply before any key check:
  `s |> peter("next", model = opus, mode = "plan", .run = FALSE)` without a key returns,
  `gptr_step(s)` refuses with `gptr_error_no_key`, and the session stays on Opus in plan mode with
  no new turn (as on main). `?peter` `.run`, 04 section 6.1.2 and D-251 say so. Red: none, a docs
  unit. Green `^(gptr-gateway|zzz|lint-rules|doc-)` PASS 3014 SKIP 2. Lint and Rd clean.
- Review: r4 (medium) applied. Since r2 a `gptr_parallel()` member is built with `ready = FALSE`, so
  nothing prepared its Ollama model: its request ran `provider_ready(prepare = FALSE)`, which
  refuses a model without discovery evidence, and
  `gptr_parallel(a = peter("x", model = "ollama/qwen3:1.7b"))` in a fresh process ended `error` ("no
  current discovery evidence"), where 99e12070 discovered it at build. `run_target()` now prepares
  the session's model at the run's first request to it (`model_prepare()`, discovery only without
  current evidence), before it resolves the record the run keeps: a member runs on the discovered
  record (tool calling, window), not the catalog's guess (`tool_call = FALSE`, no window), which
  preparing inside `provider_stream()` kept (tried). Each route discovers once: a plain call and
  `gptr_step()` at their checks (their first request runs `model_prepare()` again and discovers
  nothing), a member at its first request, whose refusal still ends it `error`; building needs no
  key. A router's choice is unchanged. `ollama_fixture()` and `local_ollama_server()` moved to
  helper-ollama.R. Red FAIL 7 on af83cfe4 (the member `error`, undiscovered, without tool calling,
  then the counts; a member whose server is down ended `gptr_error_not_available`, not the server's
  `gptr_error_network`). Green `^gptr-gateway$` PASS 433;
  `^(catalog-models|provider-registry|agent-|subagent-|s1-|gptr-|arch-layers|lint-rules|
  copy-gateway|prompt-compact)` PASS 6591 SKIP 1. 04 section 6.1.2; D-251. Lint clean.
- Review: r5 applied. r3's undo did not cover every refusal, so r3's bullet above, `?peter` and 04
  section 6.1.2 said more than the code did. A refusal while the call registered (an unknown plugin
  name, after an extension it loaded or beside a `plugins = "-x"` filter) came before the undo
  existed: its extension fired on the next turn and its tools stayed. The `skills =` preload,
  `.opts$images` and prompt_secrets "ask" refusals came in `gateway_input()`, after a continuation
  switched model and mode with its filters applied, and after a new call became `gptr_last()`: the
  next turn ran on the refused call's model with its hook. `gateway_undo()` marks the session's
  registrations and the R session's filters before the call registers; `gateway_run()` registers
  inside the `tryCatch` of `gateway_checks()`, which now holds every refusal before anything
  switches: a continuation's tools, presets and model, the guards, images on the model the call
  runs, `background = TRUE` without later, the filters, the preloads and, last, the prompt's
  secrets. Red FAIL 7 on 8185ebdc (the new test: model, mode and entries switched, the filter and
  'probe' kept, the next turn on corp with the hook, a new call's `gptr_last()` and filter). Green
  `^gptr-gateway$` PASS 446; `^(gptr-|agent-|artifact-app|catalog-models|
  console-abort-stream|console-repl|console-commands|eval-format|ext-|doc-replay|env-snapshot|mcp-|s1-|s11-|
  prompt-|provider-message|provider-registry|session-|subagent-|skill-|tool-namespace|tool-r$|copy-gateway|
  arch-layers|lint-rules|zzz)` PASS 14237 SKIP 2; `^(gptr-gateway|doc-|copy-gateway|lint-rules|zzz)`
  PASS 3056 SKIP 2. `?peter`, 04 section 6.1.2, D-251. Lint and Rd clean. The work in progress found
  uncommitted on the branch was this fix; r5 finishes it (the prompt check moved last, the test
  names each refusal) and pushes r3 and r4 with it.
- Deviations: D-251 (extended). From the plan: the continuation guards its target whether or not it
  changes and `gateway_run()` guards only a new session (one check per switch); `session_new()` sets
  `gptr_last()`, so a refused new call restores it.
- Open: a new call's unknown tool name is refused when its prompt freezes, at the run's start
  (extension and MCP tools register at `session_start`), so the refused session still becomes
  `gptr_last()` (status `error`, no turn; 04 section 6.1.2 claims only a continuation's); a router
  choice refused for egress or replay still falls back through `route_default()`, which checks no
  egress on the default model (r1, on main too: L3's `run_route()` cannot call the L6 guards, so
  closing it changes IC-69's fallback; the models group edits `run_route()` in parallel).

### sessions-4 - Say when a continued session has no kept workspace
- Red: FAIL 2 in `^gptr-gateway$` (PASS 387; findings 97, 134, 143):
  `s = f(); s |> peter("Report z.")` for a session started inside `f()` (`s$envir` NULL) evaluated
  in the caller's environment and said nothing.
- Cause: R2 (`home_keep()`) never keeps a function frame, and `gateway_continue_envir()` fell back
  to the caller frame silently; `gptr_fork()` already informs for the same condition.
- Fix: without `envir =`, a session with no kept home whose `home_label` is a function frame informs
  once (`home_not_kept`) when `home_label(call$envir)` differs, naming both and `envir = new.env()`;
  a pipe inside the same function stays silent. `?session-accessors` (`envir` NULL inside a
  function, `cost` NA without prices), `?peter` `envir`; 04 sections 2.2, 5.1, IC-40.
- Green: `^gptr-gateway$` PASS 392;
  `^(gptr-|session-|subagent-|doc-|copy-gateway|console-render|agent-run|env-|
  arch-layers|lint-rules)` PASS 7623 SKIP 3. Full suite FAIL 5 PASS 35302 SKIP 64, all load timing
  in `proc-windows-backpressure` (alone PASS 254). Lint, Rd and check-plans clean.
- Deviations: D-251 (extended). From the plan: `?peter` `envir` also says a function frame,
  `environment()` included, is not kept (finding 143).
- Open: labels compare by name, so a session made in one call of `f()` and continued in another call
  of `f()` stays silent; the sheet's `s$envir` line is entry S07.

### sessions-5 - Warn when a misspelled peter() argument becomes context
- Red: FAIL 2 in `^gptr-gateway$` (PASS 392; finding 144): `peter("x", mo = "plan", model = fake)`
  warned nothing (its message check then errored); `mo`, `mod`, `tool` and `.opt` were attached as
  context in silence.
- Cause: every formal follows `...`, so only exact names match; `select_prompt()` and
  `gateway_context_items()` take any other named dot as context, and nothing compared its name with
  the formals.
- Fix: `warn_partial_names()` (gptr-capture.R), called after `select_prompt()`, reads facts only: a
  named context dot whose name is a prefix of a formal, or the formal plus `s`, and whose value fits
  it (character, plain list, function or spec) warns `partial_name`, naming each formal; the dot
  stays context. `?peter` dots; 04 sections 2.2, 6.1, 6.1.5.
- Green: `^gptr-gateway$` PASS 401;
  `^(gptr-|session-|subagent-|doc-|copy-gateway|console-|agent-|env-|arch-layers|
  lint-rules)` PASS 9741 SKIP 4. Full suite (NOT_CRAN=true) FAIL 0 PASS 35316 SKIP 64. Lint, Rd and
  check-plans clean.
- Deviations: D-251 (extended). From the plan: names of one character stay silent, as the verifier
  advised, since `a = list(1)` or `p = "a title"` would otherwise warn as `agents =`, `prompt =` or
  `plugins =`.
- Open: an unbound bare value (`mo = auto`) still stops in capture with "object 'auto' not found",
  not naming `mo` (the verifier's optional `dot_get()` change, not planned).

### sessions-6 - Charge nothing for a request that was rejected or never connected
- Red: FAIL 13 in `^agent-run$` (PASS 661; findings 47, 95, 135): on a fake priced at $4/$20 per M,
  a 401 recorded 2626 estimated input tokens and $0.011; a 529 under `budget = list(cost = 0.001)`
  ended as `gptr_error_budget_cost` after 1 request, not `gptr_error_overloaded` after 3; a refused
  connection to 127.0.0.1:9 on the real HTTP transport did the same, not `gptr_error_network`; the
  fake 400 and overflow 400 rows were estimated, and `run_overflow_tokens()` read an all-zero record
  as 0.
- Cause: `run_response()` gave every reply without reported usage the whole prompt's estimate
  (`run$tokens_est`, `estimated = TRUE`), failed requests included; `usage_row()` priced it at the
  catalog rate, and `run_used()` counted it before the retry's `budget_check()`.
- Fix: `run_unbilled()`: a failed reply with no content whose request was rejected
  (`err_status() >= 400`) or never received (`err_class()` `network` or `timeout_connect`) records
  `usage_new(input = 0, output = 0)`, chosen inside the unreported branch (an all-zero record reads
  as unreported). `run_overflow_tokens()` also requires `run_usage_reported()`. 04 section 4.3
  `estimated` (message and row).
- Green: `^agent-run$` PASS 674. Full suite (NOT_CRAN=true) FAIL 6 PASS 35323 SKIP 64, all load
  timing in `proc-windows-backpressure` (`^(agent-run|proc-windows-backpressure)$` PASS 928). Lint
  and check-plans clean.
- Deviations: D-251 (extended). From the plan: the optional loopback check is the last part of the
  new test (port 9, `gptr.max_attempts = 1`); a priced 500 after 2 deltas stays estimated with
  cost > 0.
- Open: acceptance is not tracked (finding 135's `stream_http()` route, not chosen), so a stream the
  provider took and then lost (curl or adapter `network` class) before any content block also counts
  zero. A zero row of a model without prices is still "unknown cost" (`usage_row()` prices nothing
  without a tier). `turns` still counts each retry, as documented.

### sessions-8 - A token-budget stop names the next request, and an extension is checked again
- Red: FAIL 8 in `^(session-budget|agent-run)$` (PASS 887; findings 75, 81, 137, 188):
  `budget = list(tokens =
  10)` stopped with "the tokens budget of this call (10) is reached" and no `estimate` in the
  condition, entry or event; with "Extend" answered, the request went out (1 request, status idle)
  and no second question came; the extend question named no usage.
- Cause: `budget_check()` stops when `used + estimate > limit` but returned only `used`;
  `run_stop_budget()` and `run_budget_extend()` always said "is reached"; `run_request()` sent after
  an extension without checking again.
- Fix: every hit carries `estimate`; `run_budget_reason()` words the stop and the question (a token
  hit with used < budget: "the next request (~N tokens) would exceed the tokens budget of this call
  (B; used U)", else "is reached (used U)"). The hit is the `gptr.budget` entry and the condition's
  data; `budget_exceeded` adds `estimate`. `run_request()` asks again until the request fits or the
  run stops. 04 sections 4.6, 7.6, 10.4, IC-66.
- Green: `^(session-budget|agent-run|ext-events)$` PASS 1095;
  `^(session-|agent-|ext-|gptr-|prompt-compact|
  subagent-|console-render|arch-layers|lint-rules)` PASS 7522 SKIP 1. Full suite (NOT_CRAN=true)
  FAIL 0 PASS 35342 SKIP 64. Lint and check-plans clean.
- Deviations: D-251 (extended). From the plan: every hit kind carries `estimate` (one shape for the
  entry, event and condition), and the two extend-question tests now pass `used`.
- Open: the estimate is uncalibrated (finding 75 in passing: 3.9k against 5.9k sent on Bedrock
  Claude), so the reservation can still run low; `gateway_signal()`'s fallback for a session without
  a stored condition carries no `estimate`.

### sessions-9 - Say that budget turns count model requests
- Red: none, a docs unit (findings 78, 145, 162, 163, 182, 197). The new pin "budget turns and
  max_turns count model requests; session$turns counts prompts" passes on the base (`^gptr-gateway$`
  PASS 405): three scripted `r` calls under `budget = list(turns = 2)` or
  `.opts = list(max_turns = 2L)` stop after 2 requests with `s$turns` 1.
- Cause: `run_used()` counts usage rows and `loop_at_limit()` loop requests, while `s$turns` counts
  prompts (`run_append_messages()`); `?peter` said only "limits for this call" and 04 section 6.1
  named no unit.
- Fix: `?peter` `budget`: `turns` counts model requests, retries and sub-agents' included,
  `session$turns` prompts; `.opts`: `max_turns` caps this call's model requests. 04 section 6.1's
  `budget` and `.opts` rows name the unit.
- Green: `^gptr-gateway$` PASS 405;
  `^(gptr-|doc-|copy-gateway|session-budget|arch-layers|lint-rules)` PASS 4102 SKIP 2. Lint, Rd and
  check-plans clean.
- Deviations: none (no contract change). From the plan: the spec rows also name the unit; the pin's
  second provider is `fake2`, because a bare `model = fake` names the registered provider `fake`,
  not the variable.
- Open: `gptr_step()`'s "model turns" and the `s$turns` accessor keep their wording (the doc group's
  sessions-26); the sheet's lines are S06 and S08.

### sessions-10 - Tell the caller when a cost limit meets an unpriced model
- Red: FAIL 3 in `^session-budget$` (PASS 223; findings 133, 158): `budget_near()` under
  `budget = list(cost = 1)` with a request of cost NA signalled nothing, and
  `peter(..., budget = list(cost = 0.01))` on a registered fake without `prices` ran 2 requests to
  `idle`, `s$cost` NA, with no notice (the verifiers' live repro: Versa `gpt-5.6-sol` under
  `cost = 1e-6` the same; registered with prices, it stopped after 1 request).
- Cause: `run_used()` sums the cost with `na.rm = TRUE`, so an unpriced request counts nothing
  (D-025 item 2: failing closed would stop every unpriced model under the default 5 USD); nothing
  told a caller whose own limit could not be enforced, only the footer's "unknown cost".
- Fix: `budget_unpriced()`, called at the end of `budget_near()`: when the run's own
  `opts$budget$cost` is set and a usage row since `run$usage_start` has NA cost, `gptr_inform()`
  once (`gptr_message_budget_unpriced`, fields `budget`, `model`; "cost_unknown" recorded in `near`
  of the run, or of the team or fan-out pool so members say it once). The settings default says
  nothing. `?peter` `budget`; 04 sections 2.2 messages, 6.1 `budget` row, IC-66.
- Green: `^session-budget$` PASS 231;
  `^(session-budget|gptr-gateway|agent-run|ext-events|arch-layers|lint-rules)$` PASS 1602. Full
  suite (NOT_CRAN=true) FAIL 0 PASS 35358 SKIP 64. Lint, Rd and check-plans clean. Live (Versa
  `gpt-5.6-sol`, `budget = list(cost = 1e-6)`): 2 requests, status idle, cost NA, exactly one
  notice.
- Deviations: D-251 (extended), pointer under D-025. From the plan: the team or fan-out pool holds
  the record, so a call's members say it once, not once each; the condition carries `budget` and
  `model`.
- Open: the notice prints a limit under $0.00005 as "$0.0000" (`format_cost()`, cosmetic);
  `gptr_provider()` still does not document `prices` (the verifier's docs suggestion, not planned);
  no `budget_unenforced` event (not planned); the sheet's budget line is S08.

### sessions-11 - A continued team or fan-out shows its own synthesis in $text and $value
- Red: FAIL 11 in `^subagent-team$` (PASS 353; findings 77, 116, 120, 170, 172): after NS-6's
  `reviews |>
  peter("Reconcile ...")`, `reviews$text`, `format()` and `print()` still gave the joined
  `### stats ...` reports; a `gptr_parallel()` team and a `parallel = 2` fan-out continued with
  "Combine." kept the reports (the fan-out its named chr), and `$value` stayed the members' list
  although the synthesis turn ran `gptr_return(42)`.
- Cause: `session_text()` and `session_value_get()` chose by kind alone; the continuation's answer
  and value sit in the container's `last_text` and `values`, which only NS-6's internal
  `session_data()` read checked.
- Fix: `session_text()` returns `last_text` once set, else joins or lists; `session_value_get()`
  delegates to the children only while the container has no values. `?session-accessors`,
  `?gptr_parallel` (first paragraph), the vignette's two paragraphs; 04 sections 5.1 `text` and
  `value` rows, 6.5 `gptr_parallel()`, 03 section 4.1.6.
- Green: `^subagent-team$` PASS 364;
  `^(subagent-|session-|doc-|ckpt-|console-render|gptr-gateway|copy-gateway|
  arch-layers|lint-rules|vignette)` PASS 6287 SKIP 3. Full suite (NOT_CRAN=true) FAIL 0 PASS 35375
  SKIP 64. Lint, Rd and check-plans clean.
- Deviations: D-251 (extended). From the plan: rewinding the synthesis turn resets `last_text` (the
  reports come back to `$text`) but not `values`, so `$value` keeps that turn's value, as
  `gptr_rewind()` does for every session (measured: a plain session rewound to turn 0 keeps `$value`
  42). One test holds both twins and the value case. A replay into a live team (`replay_mark()`)
  sets `last_text` to the recorded joined reports, so `$text` reads alike.
- Open: `doc_block_lines()` still writes a continued team's turn as the team block (finding 170); a
  blocked or failed member's section of the joined `$text` has no status note (findings 77, 120);
  rewinding keeps `values` for every session. Finding 120 part 1 is the sheet's S05, S35 and S43
  (sessions-21).

### team-2 - Printed teams and fan-outs show each child under its name, and mark a child that did not finish
- Red: FAIL 5 in `^subagent-team$` (PASS 374; finding 177): `print()` and the notebook repr of
  `peter("Sum.",
  list(a = 1, b = 2), parallel = 2)` showed "A report." twice with no `### a (fake/fake-1)` heading
  (`knit_print` too, an expectation later dropped); a `gptr_parallel()` team whose member `ko`
  failed with a 400 gave an empty `### ko (fake/fake-1)` section in `$text` and in print.
- Cause: `print.gptr_session()` and `doc_session_repr_text()` passed a fan-out's named chr through
  `msg_verbatim()` and `paste()`, which drop the names (and left out a child without an answer);
  `session_text()`'s team branch wrote no status.
- Fix: `session_child_reports(d)`, the team branch with `(ended with status <status>)` for a child
  that did not end idle (the marker of `subagent_reports_block()`), serves a team's `$text` and
  `session_display_text()`, which `print()` and the repr use: a fan-out without its own answer
  (sessions-11's rule) shows the headings, else `$text`. A fan-out's `$text`, `format()` and
  `as.character()` stay the named chr. `?print.gptr_session`, `?session-accessors`,
  `?gptr_parallel`, the vignette's team and fan-out paragraphs; 04 sections 5.1 `text` row and
  `print` method, 6.5 `gptr_map()`, 03 section 4.1.6.
- Green: `^subagent-team$` PASS 378;
  `^(subagent-|session-|doc-|ckpt-|console-render|gptr-gateway|copy-gateway|
  arch-layers|lint-rules|vignette)` PASS 6301 SKIP 3. Full suite (NOT_CRAN=true) FAIL 0 PASS 35389
  SKIP 64. Lint, Rd and check-plans clean.
- Deviations: D-251 (extended). From the plan: `knit_print` is unchanged, because doc-knitr.R (L5)
  may not call session-object.R (L3) internals (`arch-layers` failed on the first attempt), so a
  knitted fan-out still joins its answers without names. The failed member gets a 400 (not retried)
  in place of the plan's 529. The display helper handles only the fan-out, since a team's `$text`
  already is its reports.
- Open: `knit_print` of a fan-out (above; it needs a contract edge or an SDK verb); a fan-out's
  headings repeat the one model its children share (kept for one form with the team).

### tools-2 - A readonly session stays readonly outside plan mode
- Red: FAIL 3 in `^perm-plan$` (PASS 110; finding 9):
  `peter("x", model = fake, mode = auto, tools = readonly)` then `s |> peter("again")`: each of the
  3 requests offered `read`, `r` and carried "New tools are available from now on: edit, write."
  (measured on HEAD).
- Cause: `plan_on_agent_start()` (P11's `agent_start` hook) called `plan_add_tools()` at every run
  outside plan mode of a session frozen with `readonly`; that reads the configured preset
  (`readonly` as `standard`) and declared `edit` and `write`. Plan mode here freezes the configured
  preset, so the hook only widened a readonly choice.
- Fix: the hook and its registration are gone; `plan_execute()` (Execute in the plan menu) still
  calls `plan_add_tools()`. The menu test drops its two `plan_on_agent_start()` lines. 03
  section 6.8 says so.
- Green: `^perm-plan$` PASS 112;
  `^(perm-|prompt-|gptr-gateway|mcp-server|ext-|bridge-sh|gptr-capture|gptr-config|
  arch-layers|lint-rules)` PASS 5961 SKIP 2; `^(tool-r|session-object)$` PASS 653. Full suite
  (NOT_CRAN=true) FAIL 0 PASS 35395 SKIP 64. Lint, Rd and check-plans clean.
- Deviations: D-251 (extended). As planned; the scripted `write` still runs and creates `ro.txt`
  (measured), which the tools group's tools-1 refuses ("Tool write not found"), a post-merge check.
  Merged with tools-1, the test asserts that refusal and no `ro.txt`: `^perm-plan$` PASS 125.
- Open: plan mode freezes the configured preset, not `readonly` as 03 sections 6.8 and 10.8 say
  (finding 9, in passing); `r` under `readonly` can still change files outside plan mode (by design;
  the sheet's S29).

### sessions-12 - The plan go-ahead notice names a call that runs the whole plan
- Red: FAIL 3 in `^perm-plan$` (PASS 113; findings 86, 96, 166): with Execute answered "edits",
  `peter("Create
  f.txt", model = fake, mode = "plan")` printed "... gptr_step(gptr_last()) runs the plan.";
  evaluating that call left the session `running` after 2 of 4 fake requests (write done, read and
  the answer not).
- Cause: `plan_execute()` named `gptr_step()`, whose default `turns = 1L` returns after one model
  turn; a plan that calls a tool needs at least two, and the leftover run then advanced inside the
  next unrelated `peter()`.
- Fix: the notice reads "Queued the go-ahead in session <id> (mode <m>): gptr_wait(gptr_last()) runs
  the plan." The new test evaluates the call the notice prints and expects `idle`, 4 requests and
  `f.txt`.
- Green: `^perm-plan$` PASS 116; `^(perm-|gptr-sdk|gptr-gateway|console-|arch-layers|lint-rules)`
  PASS 3705 SKIP 1. Full suite (NOT_CRAN=true) FAIL 0 PASS 35399 SKIP 64. Lint and check-plans
  clean.
- Deviations: none (the notice text is in no contract; P11's plan prose keeps the old call as
  history).
- Open: the reactor still pumps any unsettled run inside a later call, and the spinner `gptr_step()`
  leaves on an unsettled run is not cleared (follow-ups); the go-ahead's missing `<mode>` note is
  sessions-13, the hand-off sessions-14.

### sessions-13 - The plan go-ahead tells the model the chosen mode
- Red: FAIL 1 in `^perm-plan$` (PASS 119; finding 198): with Execute answered "edits", the go-ahead
  request (`fake_requests(fake)[[2]]`) ended with the user message "Go ahead with the plan above."
  carrying no `<mode>` block, so the only one the model saw was the plan run's `<mode name="plan">`.
- Cause: the queued go-ahead starts through `sdk_launch()` -> `gateway_run_start(s, NULL, ...)`,
  which renders no turn context, and `session_set_mode()` on an idle session leaves the `<mode>`
  block to the next user message (04 section 7.6); that message was the go-ahead, enqueued without
  blocks.
- Fix: `plan_execute()` enqueues the go-ahead with P07's `context.turn` blocks (rendered after the
  mode switch and the plan's removal from the store), so it carries `<mode name="edits">` with the
  edits body, as a continuation turn would. The new test checks the last message of request 2: role
  `user`, the go-ahead text, one `mode` block named `edits`.
- Green: `^perm-plan$` PASS 120;
  `^(perm-|arch-layers|lint-rules|gptr-sdk|gptr-gateway|console-|prompt-context|
  agent-run|session-object)` PASS 5003 SKIP 1. Full suite (NOT_CRAN=true) FAIL 0 PASS 35403 SKIP 64.
  Lint and check-plans clean. Live m$gpt, Execute "edits" then `gptr_wait(gptr_last())`: HEAD
  refused in 1 of 2 runs ("the session remains in read-only plan mode"); the fix wrote and read back
  the file in 2 of 2.
- Deviations: none (04 section 7.6 already says the next user message carries the new `<mode>`
  block). Plan deviation: the planned
  `prompt_pending_add(s, msg_operator("mode", mode_block_text(s, mode)))` in `perm-plan.R` (L4)
  fails `test-arch-layers.R` (L4 reaches L3 only through the kernel SDK and services; both helpers
  are L3), so the go-ahead carries the turn blocks through the declared `context.turn` service
  instead.
- Open: any other follow-up queued on an idle session after a mode change still starts without turn
  context (the general `sdk_launch()` gap); the plan hand-off is sessions-14.

### sessions-14 - Document the plan hand-off to the next call
- Red: none, a docs unit (findings 90, 171). The hand-off is the designed IC-56 one, kept by safe-19
  for the two-statement script idiom and pinned by `test-perm-plan.R`'s hand-off and discard tests;
  only `?gptr_options` named it ("hand a plan from `plan` mode to the next call").
- Cause: `?peter` `mode`, the execution-model vignette and the sheet's plan row describe plan mode
  only as read-only.
- Fix: `?peter` `mode`, the vignette's permissions paragraph (`.Rmd` and `.Rmd.orig`) and
  `?gptr_options` `gptr.plan_handoff`: the plan goes once, as a `<plan>` block, to the next
  top-level `peter()` call from the same environment, within an hour and in another mode, whatever
  that call asks; another call first, or a next call inside a loop or a run, discards it; the option
  turns it off.
- Green: `^(perm-plan|gptr-gateway|utils-options)$` PASS 601; `^(zzz|lint-rules|arch-layers)$`
  PASS 235. Lint and Rd clean.
- Deviations: none (no contract change; 03 section 6.8.5 already says it).
- Open: with `gptr.plan_handoff = FALSE` `plan_capture()` still stores a record and the next call
  prints its discard notice, and under `gptr.quiet` the hand-off prints no notice (finding 90,
  follow-ups); the sheet's row is S34.

### sessions-15 - Plan mode runs console output such as cat()
- Red: FAIL 3 in `^(perm-classify|perm-plan)$` (PASS 1026; finding 70): the allowlist refused
  `cat('a\n')`, `base::cat(nrow(df), file = stdout())`, `writeLines('b')`, `dput(1:3)` and
  `do.call(rbind, lapply(...))`, and the fake's plan-mode `r` call `cat('a\n')` got "Permission
  denied: not known to be read-only in plan mode: cat.", though `gptr_risk()` scores each 0.
- Cause: `risk_plan_disallowed()` admitted only level-0 `read` rows; the rows of `cat`, `writeLines`
  and `dput` record their worst case (`file_write` through `path_arg`), `do.call`'s is `dynamic`,
  and the scan's verdict per call (a console target, a literal function: no flag) was not read.
- Fix: a `file_write` row with a path argument, or a `risk_lookups` function with a `dynamic` row,
  passes when the scan flags none of its calls; the path row also must never be used as a function
  value (`risk_scan()` now returns `values`, the names `use_value()` saw), whose arguments the scan
  cannot see. The interactive-console vignette (`.Rmd`, `.Rmd.orig`) says "R calls known to be
  read-only", not "level-1 R exploration". 04 IC-54.
- Green: `^(perm-classify|perm-plan)$` PASS 1029; `^(perm-|ckpt-|tool-r|arch-layers|lint-rules|zzz)`
  PASS 2558. Full suite (NOT_CRAN=true) FAIL 0 PASS 35419 SKIP 64. Lint and check-plans clean.
- Deviations: D-251 (extended). From the plan: the value rule and its two tests, because the planned
  rule admitted `lapply(1, cat, file = 'x.txt')` and `do.call(cat, list('a', file = 'x.txt'))`,
  which the scan scores 0 and which write; a lookup also needs its `dynamic` row.
- Open: `gptr_risk()` scores those value uses 0, so `manual` runs them unasked (a slot function is
  read with computed positional arguments, which `cat()`'s `...` takes, leaving `file` at its
  console default; a classifier follow-up); `cat('a', file = 'nul')` counts as the null device on
  every OS; getting-started still says "level-1 R exploration"; unlisted level-1 functions and
  helpers the code defines stay refused (by design).

### sessions-17 - Read a program given by its path as that program in rules
- Red: FAIL 20 in `^perm-(rules|gate)$` (PASS 272; findings 42, 49): `r(sh:rm *)` and
  `r(category:file_delete)` matched none of `peter$sh('/bin/rm -rf build')`, its argv form,
  `system()`, `system2()`, `/usr/bin/env rm`, `command /bin/rm`, `./rm` and `C:\bin\rm.exe` (16),
  and the fake's `peter$sh('/bin/rm -rf build')` ran in auto and yolo and deleted `build/` (4).
- Cause: `risk_cmd_simple()` read a program given by its path as one level-3 `process` row with the
  path in its text, and kept only the level-4 rows (`later()`) of its name's reading.
- Fix: a literal path to a known program (`risk_cmd_known()`, `.exe` stripped) adds that program's
  whole reading beside the `process` row (so `/usr/bin/env` alone carries `env`'s `secret` row too);
  a computed or unknown program keeps `later()`. Levels are unchanged.
- Green: `^perm-(rules|gate)$` PASS 292;
  `^(perm-|bridge-|agent-dispatch|tool-r|ckpt-|arch-layers|lint-rules|zzz)` PASS 3349 SKIP 12. Full
  suite (NOT_CRAN=true) FAIL 0 PASS 35455 SKIP 64. Lint and check-plans clean.
- Review: r1 (low) applied. `.exe` was stripped case-sensitively before `tolower()`, so
  `C:\bin\RM.EXE -rf build` was not a known program and kept `later()`: `r(category:file_delete)`
  and `r(sh:RM *)` missed it (and a bare `RM.EXE` was one `process` row). `risk_cmd_name()` strips
  it in any case at the four sites. Red FAIL 2. Green `^perm-` PASS 1345;
  `^(bridge-|agent-dispatch$|tool-r$|ckpt-|arch-layers$|lint-rules$|zzz$)` PASS 1816 SKIP 12. Lint
  and check-plans clean.
- Deviations: D-251 (extended). From the plan: the rules test also covers `./rm` and
  `C:\bin\rm.exe`, which the decision names. No live check (the fake run is the gate end to end).
- Open: such a call whose reading is flagged gets no `[a]lways` rule (no one `sh:` glob covers the
  path and the name); `peter$bg` is sessions-18; a computed command
  (`cmd = "rm -rf build"; peter$sh(cmd)`) is nested-1. `sh:` globs match a name as written, so
  `r(sh:rm *)` misses a bare `rm.exe` or `RM.EXE` and `C:\bin\RM.EXE` (`RM`).

### sessions-18 - Classify peter$bg() commands like peter$sh()
- Red: FAIL 9 in `^perm-(rules|gate|classify)$` (PASS 1198; finding 45): `r(sh:rm *)` deny and ask
  matched neither `peter$bg('rm -rf build')` nor its argv form, `r(sh:python3 -m*)` did not allow
  `peter$bg('python3 -m
  http.server 8000')`, `[a]lways` offered `r(sh:peter$bg*)`, `gptr_risk("peter$bg('rm -rf ~')")` was
  3, and the fake's `peter$bg('rm -rf build')` ran in auto and yolo and deleted `build/` (4).
- Cause: `risk_member_flags()` returned one `peter$bg` row at level 3 and never read the command.
- Fix: `bg` folds its `cmd` as `sh` does: a literal command gets `risk_command()`'s rows plus a
  level-3 `process` row carrying the command text; a computed one the `dynamic` level-3 row.
- Green: `^perm-(rules|gate|classify)$` PASS 1207;
  `^(perm-|bridge-|agent-dispatch|tool-r|ckpt-|arch-layers|
  lint-rules|zzz)` PASS 3359 SKIP 12. Full suite (NOT_CRAN=true) FAIL 0 PASS 35465 SKIP 64. Lint and
  check-plans clean.
- Deviations: D-251 (extended); 04 section 9.4 `bg` risk cell amended. From the plan: the level-4
  case is an expectation after the G5 table, which keeps its 46 cases. No live check (the fake run
  is the gate end to end).
- Open: `peter$script()` still offers `r(sh:peter$script*)`, which would allow every script (finding
  45, no unit); a computed command is nested-1.

### nested-1 - Deny and ask rules see the real command of a nested peter$sh() or peter$bg() call
- Red: FAIL 10 in `^perm-gate$` (PASS 144): under `r(sh:rm *)` deny, the fake's
  `cmd = paste('rm', '-rf',
  'build'); peter$sh(cmd)` and `peter$bg(cmd)` ran in auto and yolo and deleted `build/` (8); under
  the ask rule in auto nothing was asked and `build/` went (2).
- Cause: the static row is `peter$sh(<code the code computes>)`, which no `sh:` glob matches;
  `dispatch_nested()` re-checked the call only above the outer call's approved level (an in-project
  `rm` is 3, as the outer call), and then as tool `sh`, which `r(...)` rules never match.
- Fix: `nested_rules()`: a nested `sh` or `bg` call meets the registered `rules` policy as the
  literal call `peter$sh("rm -rf build")` (its risk through `call_risk()`, the `risk.classify`
  service), whatever its level; a deny refuses it with the rule's text, an ask goes through
  `perm_ask()`. No allow rules; skipped under `gptr.unsafe_no_permissions`, as `perm_check()` is.
- Green: `^perm-gate$` PASS 154;
  `^(perm-|bridge-|agent-dispatch|tool-r|ckpt-|arch-layers|lint-rules|zzz)` PASS 3370 SKIP 12. Full
  suite (NOT_CRAN=true) FAIL 0 PASS 35476 SKIP 64. Lint and check-plans clean.
- Review: r1 (medium) applied. The question offered `[a]lways r(sh:rm -rf*)`, but
  `perm_on_remember()` recomputes from tool `sh` and stored the allow rule `sh` (every nested shell
  call the level gate asks about; in project settings for `[p]`), and allow rules are not applied
  here anyway. `nested_rules()` clears `suggested_rule` before `perm_ask()`, so an ask rule asks
  every time and offers no `[a]lways`. Red FAIL 1 (an `a` answer: allow `sh`). Green `^perm-gate$`
  PASS 156; `^(perm-|agent-dispatch$|bridge-|tool-r$|console-ui$|arch-layers$|lint-rules$)`
  PASS 2428 SKIP 12. Lint and check-plans clean. 03 section 6.8.4 and 04 section 7.6 say so.
- Deviations: D-251 (extended); 03 section 6.8.4 and 04 section 7.6 `dispatch_nested()` amended.
  From the plan: `perm_policy_rules()` and `risk_command()` are L4, which L2's `agent-dispatch.R`
  may not call (arch-layers), so the registry's `rules` record is asked through
  `ext_policy_decide()` and the command is read through the literal call (the reading of sessions-17
  and sessions-18, `bg`'s `process` row included). No live check (the fake run is the gate end to
  end).
- Open: a command computed at run time and run through base `system()`
  (`cmd = paste("rm", "-rf", "build");
  system(cmd)`) still escapes a deny `r(sh:rm *)` in auto and yolo (fake run: `build/` deleted in
  both): its static row is `dynamic` (level 3, as is `system2("rm", a)`), which no `sh:` glob
  matches, and nested-1 re-checks only nested `peter$sh` and `peter$bg` calls. No code change (the
  gate is advisory); `?gptr_security` ("What the gate cannot do") names the limit. Docs:
  `^(zzz|lint-rules|doc-|gptr-config$)` PASS 3106 SKIP 2; check-docs 0 problems; release doc tests
  PASS 49. Lint and check-plans clean.

### sessions-22 - Keep a resumed session's mode
- Red: FAIL 5 in `^session-store$` (PASS 274; findings 148, 153): `peter(mode = "plan")`'s
  `gptr.frozen` held no mode, and its path rebuilt as `auto` under an `auto` setting; an `auto`
  session as `manual` under `manual`; `gptr_resume()` of the plan session's file came back `auto`; a
  stored `mode_change` to `"bogus"` was taken.
- Cause: nothing recorded a session's starting mode (not the header, not `gptr.frozen`, no
  `gptr.mode_change` at creation); `rebuild_mode()` took the last `gptr.mode_change`, else the
  resuming process's `mode` setting. `path_fields()` (replay cut) used the same function.
- Fix: `prompt_frozen_entry(frozen, mode)` and `freeze_fallback()` write `mode = d$mode` into
  `gptr.frozen`; `rebuild_mode()` walks the active path in order and keeps the last `gptr.frozen`
  `mode` or `gptr.mode_change` `to` that is one of `session_modes` (read with `[[`: `data$mode`
  partially matches `model`), else the setting.
- Green: `^session-store$` PASS 279;
  `^(session-|agent-run|prompt-|ckpt-rewind|gptr-gateway|console-commands|
  doc-replay|subagent-)` PASS 5457 SKIP 1. Two `Rscript` processes on one `.gptr/` project (fake
  provider): a `plan` session resumed under `gptr_config(mode = "auto")` reports `plan`. Full suite
  (NOT_CRAN=true) FAIL 0 PASS 35482 SKIP 64. Lint and check-plans clean.
- Deviations: D-251 (extended); 04 sections 4.6 `gptr.frozen` row and 6.5 `gptr_resume()` amended;
  `?gptr_sessions`. From the plan: the in-process rebuild from the file is the test (no callr test);
  the 1.0.0 user message's `mode` context block is not read, so such files keep the setting
  fallback.
- Open: the second half of 148 is designed (without `.gptr/` the store is `tempdir()`); the
  `/resume` row says so with the sheet (entry S12). Whether an imported (foreign) file may restore
  `yolo` (possible through `gptr.mode_change` before). A fork cut before a later mode change of its
  source runs in the source's mode (`edits`), but its file records the mode at the cut (`plan`),
  which its own rebuild reads (measured).

### sessions-24 - Say that gptr_init() asks the trust question
- Red: none, a docs unit (finding 46). In a pty `gptr_init(".")` itself asks "Trust this project
  (its settings, extensions and MCP servers)? [y/N]"; pasted as one block, the next line is taken by
  that question and dropped by `readline_answer()`'s 0.1 s guard (IC-75), so
  `gptr_trust(".", trust = TRUE)` never runs (verifier's reproduction).
- Cause: the configuration vignette (`.Rmd` and `.Rmd.orig`) showed `gptr_init()`, `gptr_trust()`
  and two `gptr_config()` lines as one block, without the question `gptr_init()` asks when
  `gptr_can_prompt()`.
- Fix: three blocks: `gptr_init()` alone, with "at the console it asks whether to trust the project;
  the default is No" and "run that line on its own"; `gptr_trust(path, trust = TRUE)` for a script,
  which records no decision, or to change an earlier answer, read back as `TRUE`, `FALSE` or `NA`;
  then the `gptr_config()` lines.
- Green: `^(zzz|lint-rules|doc-)` PASS 2589 SKIP 2; the vignette renders. Lint and check-plans
  clean.
- Deviations: none (no contract change; `?gptr_init` already says it asks). From the plan: no
  `gptr_init(trust =)` argument.
- Open: a recorded No is silent afterwards, unlike the undecided notice; `readline_answer()` drops a
  pasted line without saying so (finding 46, follow-ups); the sheet's card is S03.

### gateway-1b - A refused call does not announce its registry filters (2026-10-23)
- Last validation of gateway-1 (low). Red: FAIL 2 in `^gptr-gateway$` (PASS 480): a continuation
  with `plugins = "-builtin:memory"` refused for an unknown `skills =` preload printed "The filters
  -builtin:memory apply to every later peter() call of this R session ..." and used up its `.once`
  key, so the next accepted call with that filter said nothing.
- Cause: `gateway_filters_apply()` informed as it applied the filters, before the preload and
  prompt-secret checks that can still refuse the call (and undo them).
- Fix: it returns the announcement, which `gateway_checks()` makes after its last check.
- Green: `^(gptr-gateway|gptr-config|ext-registry|ext-plugins|arch-layers|lint-rules)$` PASS 1792.
  Lint clean.
- Deviations: none. Open: none.

### gateway-1c - An interrupt before the turn starts undoes the call too (2026-10-23)
- Last validation of gateway-1 (low). Red: FAIL 4 in `^gptr-gateway$` (PASS 485): Ctrl-C at the
  secret question (`gptr_confirm()` mocked to signal an interrupt) left a continuation's
  `-builtin:memory` filter, its `probe` tool and its extension's hook, which fired on the next turn,
  and a new call stayed `gptr_last()`.
- Cause: `gateway_run()` undid the registrations and restored `gptr_last()` only in an `error`
  handler.
- Fix: the registration and checks run in `tryCatch(finally =)`, which undoes both on any exit
  before `gateway_checks()` returns. `?peter`, 04 section 6.1.2 and D-251 say "or interrupted".
- Green: `^gptr-gateway$` PASS 489;
  `^(gptr-.*|console-.*|copy-gateway|subagent-team|session-object|doc-replay|
  arch-layers|lint-rules)$` PASS 5369 SKIP 1. Lint clean; Rd regenerated.
- Deviations: D-251 (extended). Open: none.

## FIX-19 - Cheat-sheet review: orchestration (2026-10-22, #77)

### ws-1 - A team, fan-out or nested child's <workspace> block lists the caller objects it can read
- Findings 123, 126, 156, 184, 199, 201. Red: `^(env-snapshot|subagent-team)$` FAIL 13 PASS 537:
  each team member's block was `<workspace env="overlay of stats" objects="0">` `(no objects)`, a
  fan-out child's listed `.x` only; the same held for a nested overlay and a fork overlay.
- Cause: `env_block_workspace()`, `env_block_changes()`, `env_on_agent_end()` and `env_on_tree()`
  snapshot `env_home()`, an overlay `new.env(parent = caller)`, and `ls()` never looks at the
  parent.
- Fix: `env_view_snapshot()` (R/env-snapshot.R) at all four sites: the overlay's rows, then each
  lower overlay's and the base's, own names first (`!duplicated()`); an overlay's block starts with
  `Reads fall through to globalenv; assignments stay here.` (or `<environment>`). The first version
  pinned a function-frame home: `[.data.frame` called in the frame that bound it kept that frame
  referenced (copy-eval's new row: 1 copy; test-copy-tools' function-frame `peter()` row still
  passed), so the helper drops `envir` before subsetting. The label is not `home_label()`, a
  session-layer function (arch-layers).
- Green: `^(env-snapshot|subagent-team)$` PASS 551; `^copy-` PASS 155; neighbours (env-, subagent-,
  session-object, session-store, gptr-gateway, prompt-, northstar, ckpt-rewind, gptr-config,
  agent-run, doc-blocks, arch-layers, lint-rules) PASS 5505 SKIP 1. Lint clean. Live (m$gpt, the
  sheet's team example, mode "auto"): both blocks list `fit  lm` under `objects="8"` and both
  members reviewed fit (48 s).
- Deviations: D-252 (new). Open: finding 126's container status and `$text` synthesis are
  sessions-11's; the extra line sits outside `workspace_lines()`'s budget (the block's truncation
  still applies).

### sessions-20 - A fork's change report names the source objects its code changed in place
- Findings 99, 110. Red: `^session-object$` FAIL 4 PASS 534: after the fork ran
  `dt[, z := 1]; e$flag = 'x'; v <<- 2; w = 3`, its r result had `added` = e, w and `modified`
  empty, while home's dt, e and v had changed (the source's turns and file md5 did not).
- Cause: `gptr_fork(envir = "overlay")` is `new.env(parent = home)`, which isolates bindings only,
  and `eval_run()` diffed snapshots of the overlay alone, so in-place edits below it were invisible
  and `e$flag = 'x'` (which binds the source's `e` in the overlay) looked new.
- Fix: `eval_run()` diffs `env_view_snapshot(sizes = FALSE)` (new `sizes` argument and `own`
  column); `eval_objects()` adds `(in the source workspace)` to a modified row not `own`, or whose
  new own binding shares the old row's object (a rebinding `k = 5` stays unmarked). The
  `gptr_fork()` doc and interactive-console vignette say in-place edits reach the source's objects.
- Green: `^session-object$` PASS 538; session-object, env-snapshot, eval-core, eval-format,
  eval-guard, copy-eval, copy-tools and tool-r PASS 1366; full suite (NOT_CRAN=true) FAIL 0 SKIP 64
  PASS 35300. Lint clean; plan checks pass. Live (m$gpt, the finding's data.table fork): the model
  ran `dt[, logmpg := log(mpg)]` and its result read `~ dt <data.table> modified (in the source
  workspace)`.
- Deviations: D-252 (extended). Open: no fork-scoped policy asks before `:=` or `<<-` (plan); an
  object a fork creates in the source with `<<-` is still listed as `+ name` without the mark.

### guard-1 - A q or quit bound to data in the workspace is not refused as quitting R
- Finding 25 (in passing). Red: `^eval-guard$` FAIL 4 PASS 126: `eval_guard()` took no `envir`,
  and a fake `r` call `summary(q)` in a session whose envir held `quantile(1:10)` came back
  `blocked`, "Not run: the code calls or refers to q()".
- Cause: a `q`/`quit` value passed only when the code itself assigned it; the guard never saw the
  workspace, so the user's own `q` (a quantile vector, a query) read as `base::q`.
- Fix: `eval_guard(exprs, envir = NULL)`; `eval_run()` passes `st$envir`. A value passes when the
  first binding R's value lookup finds from `envir` is data (`eval_guard_is_data()`; a promise or
  active binding is not forced and counts as unknown). Calls, `base::q`, `do.call("q")` and
  `sapply(x, q)` stay refused.
- Green: `^eval-guard$` PASS 136 (the end-to-end test needs no permission bypass in auto mode);
  eval-*, copy-eval, copy-tools, tool-r, arch-layers, lint-rules, s1-* PASS 2229; agent-dispatch,
  agent-loop, doc-blocks, gptr-gateway, injection-e2e, perm-gate, northstar, console-* PASS 3297
  SKIP 1. Lint clean; plan checks pass.
- Deviations: D-252 (extended): R's own lookup, not the plan's `binding_env()`, an L3 function the
  eval layer may not call that skips the parents of a function-frame home (a nearer `base::q`).
  Open: `rm(q); g = q; g()` passes, as `eval(parse(text = ...))` already does (advisory guard).

### team-1 - A team or fan-out with failed members reports it, and signals when none finished
- Findings 71, 72, 129, 185. Red: `^subagent-team$` FAIL 13 PASS 354: a manual-mode team and a
  fan-out whose members were both `blocked` returned `idle` with no condition (a single call
  signals `gptr_error_permission`), a mixed team was `idle` with `$reason` NULL while its
  `agent_end` said `error`, and a `gptr_parallel()` team with a failed member stayed `idle`.
- Cause: `subagent_run_children()` computed the outcome only for the `agent_end` event and never
  wrote it to the container, which `session_new()` leaves `idle`; the routes return it without
  the gateway's signal step.
- Fix: `subagent_settle_container()` gives a team, fan-out or `gptr_parallel()` team the first
  non-idle child's status and stored condition and the reason `k of n sub-agents did not finish:
  b (blocked)`; `agent_end` carries both; `agents =` and `parallel =` re-signal the condition with
  the container as `$session` (`subagent_signal()`, shared with `on_error = "stop"`) when no
  child ended idle. ?peter, the teams vignette and 04 section 6.1.2 say so.
- Green: `^(subagent-team|injection-e2e)$` PASS 571; with gptr-gateway PASS 926; full
  suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35329. Lint clean; plan checks pass. Live (m$gpt, the
  sheet's team code under Rscript, manual mode): stats blocked, code idle; the team returned
  `blocked`, reason `1 of 2 sub-agents did not finish: stats (blocked)` (30 s).
- Deviations: D-252 (extended): the plan's `gateway_signal()` is L6, which an L4 file may not call
  (arch-layers); every status it signals stores its condition, so re-signalling that is the same.
  Open: none.

### tools-4 - ?peter and ?gptr_options name gptr_error_noninteractive for a blocked ask
- Findings 7, 73, 168, 180, 194 (docs). Red: none (wording; the behaviour is pinned by
  agent-dispatch "a non-interactive ask call stops blocked with gptr_error_noninteractive").
- Cause: ?peter mapped `blocked` only to `gptr_error_permission`, and ?gptr_options said
  `gptr.noninteractive_ask = "stop"` raises it; an `ask` tool call nobody can answer raises
  `gptr_error_noninteractive` (03 section 6.8.5, IC-68). `preset_ask()` is right and unchanged.
- Fix: both items add "(`gptr_error_noninteractive` when the `ask` tool has no one to answer)";
  04 section 6.1.2's terminal-status list, which ?peter mirrors, says the same. Rd regenerated.
- Green: gptr-gateway, utils-options, tool-ask PASS 472. Lint clean; plan checks pass.
- Deviations: none (the contract already said so). Open: none.

### team-4 - gptr_sessions() lists a settled team or fan-out as idle, with its model
- Finding 74. Red: `^session-store$` FAIL 5 PASS 276: a settled fan-out, team and `gptr_parallel()`
  team listed `interrupted` with model NA and resumed (from the file, the live objects gone)
  `interrupted`, while each live object was `idle`.
- Cause: the stored status comes from the last message, and a container never writes an assistant
  message (its tail is the `<agent_reports>` user message); the listing took the model only from
  an assistant message, where `rebuild_model()` also reads `model_change` and `gptr.frozen`.
- Fix: `subagent_settle_container()` appends `gptr.container_end` `{status}`; `rebuild_status()` and
  `session_file_summary()` let the last message or end decide (an end is idle only with status
  idle; a later synthesis turn decides by itself); a row with no answer naming the model takes
  `rebuild_model()` of the head and tail lines. 04 section 4.6 and `gptr_resume()`, 03 section 5.1,
  ?gptr_resume.
- Green: `^(session-store|subagent-team)$` PASS 650; with subagent-backends, session-object,
  injection-e2e, gptr-gateway, arch-layers, lint-rules, ckpt-rewind PASS 2232; full suite
  (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35337. Lint clean; plan checks pass.
- Deviations: D-252 (extended). The plan's copy-under-another-id check cannot work (a durable usage
  record is bound to its header id), so the test cuts a copy for the negative case and resumes the
  real files after dropping the live sessions. Open: a `gptr_parallel()` row's title is still empty.

### bg-1 - A resumed background session tells the model the user can now be asked
- Findings 191, 204. Red: `^agent-background$` FAIL 6 PASS 194: with a fake model that does not
  repeat the call, the resumed request ended on the stale tool result "Permission denied: the user
  could not be asked ... Explain what you need or choose another approach." (for a blocked `ask`,
  "Tool execution was blocked: ..."); no message said the user was there.
- Cause: `bg_resume()` called `run_start(s, NULL)` with no input, so the run went on from the
  denial, and the denial's `how` was lost (`ui_answer_norm()` rebuilt the answer without it,
  `perm_ask()` passed none), so `perm_denial_text()` added "choose another approach". GPT read it
  as final: 7 of 8 runs ended without asking.
- Fix: `bg_resume()` queues a steer from the user (`api_user`) before `run_start()`,
  `bg_resume_text()`: "I am at the console now. Repeat the call that could not be approved
  (<summary>) with the same input; I will be asked to approve it." or "I am at the console now;
  ask again."; a resume that cannot start restores the queue. The idle-tick `permission()` answer
  carries `how = "Nothing ran and nobody declined; repeat the call when the session continues."`,
  which `ui_answer_norm()` keeps for a denial and `perm_ask()` gives `perm_result()`.
  ?gptr-background and the teams vignette say so; 03 section 6.2, 04 sections 7.21, 10.2 row 22,
  IC-57.
- Green: `^agent-background$` PASS 200; with agent-dispatch, console-ui, perm-*, tool-ask,
  subagent-worker, injection-e2e, ext-specs, agent-run, agent-loop PASS 3293 SKIP 1; full suite
  (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35354. Lint clean; plan checks pass. Live (m$gpt, manual
  mode, `peter("Check fit.", fit, background = TRUE)` at an interactive pty console): parked
  "waiting for approval", then `gptr_wait(b)` raised the allow? prompt in 3 of 3 runs (the
  verifier's baseline: 1 of 6).
- Deviations: D-252 (extended). `R/console-ui.R` (not in the plan's files) had to keep `how`. The
  "cannot continue" test now fails `run_start()` with a mock: a queued note gives its finished
  session something to run. Open: P28's sessions-16 also edits `perm_ask()` and `bg_ui_spec()`
  (the second merge keeps both); no notice backs up a model that still does not repeat the call.

### gate-hint - A blocked call's hint names where its mode came from, and knitting is not sent to the console
- Finding 16, item 4 (doc-4 holds the id). Red: `^agent-dispatch$` FAIL 6 PASS 229: a manual-mode
  `r` call under `gptr.interactive = FALSE` raised `gptr_error_permission` whose `how_to_allow` was
  always "Allow it with mode = "auto", a permission rule (gptr_permissions()), or run
  interactively.", naming no layer, the same with the mode set at session scope, by a project file
  over a user `auto`, by the call or by the session it continued, and with
  `knitr.in.progress = TRUE`.
- Cause: `perm_ask()` built a fixed sentence; it never looked at the run's mode or its origin, nor
  at `is_knitting()`, under which `gptr_can_prompt()` is FALSE even at a console.
- Fix: `gateway_run_opts()` records a top-level call's `mode_from = list(mode, from)`
  (`gateway_mode_from()`: the call's `mode =`, the continued session, else the
  `settings_layered("mode")` layer when it holds that mode); `perm_blocked_how()` starts the hint
  `Mode "manual" comes from
  .gptr/settings.json.` while the run keeps that mode, and while knitting ends "... or a permission
  rule (gptr_permissions()); knitting cannot ask." The `ask_human` text and `gateway_signal()` are
  unchanged. 04 section 7.6 (run options) and the `perm_check()` row amended.
- Green: `^agent-dispatch$` PASS 235; with gptr-gateway, gptr-config, gptr-sdk, perm-gate,
  doc-replay, mcp-server, northstar, agent-run, agent-background, subagent-team, injection-e2e,
  arch-layers, lint-rules PASS 3704; full suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35374. Lint
  clean; plan checks pass; Rd unchanged.
- Deviations: D-252 (extended). The plan's `settings_layered()` call in `perm_ask()` would cross
  layers (L2 to L6), so the gateway records the origin; a nested call's origin is not named (its run
  may have tightened the mode); a continued session names itself, not a settings layer it no longer
  follows. Open: none.

### tpl-1 - Prompt-template commands exist in the console before the first prompt
- Findings 104, 109 (the trust half of 104 is tpl-2). Red: `^console-commands$` FAIL 7 PASS 94: with
  no sync run, `/check mtcars` (a trusted `.gptr/prompts/check.md`) was "Unknown command", `/help`
  listed no `/check`, `/review` or `/explain`, a `later.md` saved afterwards stayed unknown, and a
  `.stdin` console whose first input was `/check mtcars` never reached the fake model.
- Cause: templates reach the command registry only through `template_sync()`, called only by
  `builtin:prompts`' `session_start` hook, and the console dispatches commands before its first
  session starts.
- Fix: `prompts_sync()` (the hook's `plugins_sync()` then `template_sync()`) is the service
  `templates.sync` (P17, owned by `builtin:prompts`, so filtering it keeps templates off);
  `console_command()` calls it when neither lookup finds the name and looks again; `cmd_help()`
  calls it first. 03 section 6.17, 04 sections 7.0, 7.17.
- Green: `^console-commands$` PASS 102; aaa-state, console-*, skill-*, ext-*, arch-layers,
  lint-rules PASS 4209 SKIP 1; full suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35382. Lint clean;
  plan checks pass; Rd unchanged. Installed branch, piped console (fake model): `/help check`,
  `/check mtcars` and `/review x` work as the first inputs.
- Deviations: D-252 (extended). The service needs its `service_plans` entry (`R/aaa-state.R`, which
  the arch helper reads; test-aaa-state's count 39 to 40), not in the plan's files; helper-arch.R
  needed no change. No sync in `repl_main()`, as planned. Open: none.

### tpl-2 - Projects whose only resources are prompts or agent-tool folders get the trust question
- Findings 117, 147 (its code items; the caption is sheet entry S37, the messages trust-msg, skipped
  files skills-2). Red: `^gptr-config$` FAIL 15 PASS 537: `trust_resources_present()` was FALSE for
  a project holding only `.gptr/prompts/check.md`, `.claude/skills`, `.agents/skills`,
  `.claude/agents`, `.codex/agents`, `.pi/agents`, `AGENTS.override.md`, `CLAUDE.local.md`,
  `.gptr/vignette.Rmd` or a relative `skills.paths` directory, so `trust_resolve()` returned FALSE
  with no question, notice or `project_trust` event and `template_roots()` dropped the root; the
  question named no skills.
- Cause: the check listed `AGENTS.md`, `CLAUDE.md`, `.gptr/skills` and `.gptr/agents` only, not
  every location skill, template, agent and instruction discovery reads under trust.
- Fix: it counts those instruction files and directories plus the relative `skills.paths` entries of
  the settings in force (`trust_skill_paths()`, through `settings_layered()`, which resolves no
  trust); the question of `trust_resolve()` and `gptr_init()` names skills, prompt templates and
  agent files; `?gptr_trust` lists project skills and prompt templates. 03 section 6.10, 04
  `gptr_init()`, `gptr_trust()`, IC-52.
- Green: `^gptr-config$` PASS 552; full suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35417. Lint clean;
  plan checks pass; `gptr_trust.Rd` regenerated. Installed branch, fake model, a prompts-only
  project: a script's `peter()` now gets the untrusted notice (none before); the console asks the
  trust question at the first prompt, and after `y` `/check mtcars` runs the template and
  `gptr_trust(".")` reads TRUE.
- Deviations: D-252 (extended). Also counts `.gptr/vignette.Rmd`, an instruction file whose
  authority follows trust, which the plan's list lacked. `skills.paths` is read through
  `settings_layered()` (the layers skill discovery reads; a project settings file is itself gated)
  rather than the two files as written. `gptr_init()` asks the same question, so its text changed
  too (one test-gptr-config expectation). Open: none.

### trust-msg - Untrusted-resource messages name the call that actually trusts
- Motivated by findings 111, 147 (sheet units). Red: `^(skill-discover|ext-plugins)$` FAIL 3
  PASS 562: the untrusted skill notice, `skill_body()`'s `gptr_error_untrusted` and the
  untrusted-plugin notice said `(gptr_trust())` or `trust it with gptr_trust()`, the read-only form,
  which returns `NA` and trusts nothing.
- Cause: the advice named the function, not the call; with `trust = NULL`, `gptr_trust()` only
  reads.
- Fix: all nine messages (skill notice and error, extension and plugin notices, `trust_resolve()`'s
  notice, project MCP server, project instructions, agent notice and error) name
  `gptr_trust(".", trust = TRUE)`, the form the sheet's Set up row uses. Text only.
- Green: `^(skill-discover|ext-plugins)$` PASS 565; with mcp-config, gptr-config, prompt-context,
  subagent-defs, lint-rules, arch-layers PASS 1538. Lint clean.
- Deviations: none (the contract quotes none of these messages). Open: none.

### sessions-23 - Report lapsed project trust as undecided
- Finding 52. Red: `^gptr-config$` FAIL 1 PASS 555: after `.gptr/settings.json` changed in a trusted
  project, `trust_get()` was FALSE but `gptr_trust(proj)` read TRUE.
- Cause: the read returned the recorded flag without the fingerprint check `trust_get()` and
  `trust_resolve()` apply, so it said TRUE while the run printed the untrusted notice and dropped
  the changed `SYSTEM.md`.
- Fix: a recorded TRUE whose fingerprint no longer matches (`trust_holds(root)$record`) reads NA, as
  the run treats it (asked again); a recorded FALSE stays FALSE; the write and its invisible
  previous value are unchanged. `@return` and 04 `gptr_trust()` amended.
- Green: `^gptr-config$` PASS 555 (after re-trusting, the read is TRUE and `SYSTEM.md` starts the
  next fake request's system prompt; a refusal stays FALSE after `SYSTEM.md` changes); with
  injection-e2e, perm-plan, prompt-sections, ext-plugins, lint-rules, arch-layers PASS 1718. Lint
  clean; plan checks pass; Rd regenerated.
- Deviations: D-252 (extended). Open: a `project_trust` hook's unremembered yes still reads NA
  (record only).

### plug-1 - gptr_plugins() lists the usable entry of a plugin first
- Finding 108. Red: `^ext-plugins$` FAIL 1 PASS 382: after `plugin_enable(lab, 0L, session = d1)` in
  an untrusted project, `gptr_trust(proj, TRUE)` and `plugin_enable(lab, 0L, session = d2)` (TRUE),
  `gptr_plugins()` listed `stale-lab` enabled FALSE, state `disabled`.
- Cause: entries were ordered process-before-session only and the first per path was kept, so the
  untrusted session's disabled entry hid the trusted session's until GC drained the first session.
- Fix: order entries usable first (enabled and not failed), then process before session.
- Green: `^ext-plugins$` PASS 383 (the "a plugin enabled twice once" row still lists the process
  entry); full suite (NOT_CRAN=true, with trust-msg and sessions-23) FAIL 0 SKIP 64 PASS 35426. Lint
  clean.
- Deviations: none (04 `gptr_plugins()` does not say which entry is listed). Open: none.

### skills-1 - gptr_skills() and gptr_agents() list the plugins of live sessions and of the settings
- Findings 93, 107. Red: `^ext-plugins$` FAIL 4 PASS 388: with a live `peter(plugins = d)` session,
  `gptr_skills()` had no `listed-skill` row and `gptr_agents()` no `listed-agent`; with
  `options(gptr.plugins = d)` and no session started, `gptr_skills()` had no `unsynced-skill` row.
- Cause: `res_plugin_dirs()` dropped every session entry, and `peter(plugins =)` plugins are always
  session-scoped; settings plugins enter the plugin table only through `plugins_sync()` at a session
  start. The session's catalog and `gptr_plugins()` showed both, so the listings disagreed with
  them.
- Fix: `res_plugin_dirs(type, listing)` and `res_roots(..., listing)`; with `listing = TRUE`, used
  only by `skill_discover()` and `agent_discover()` (through `skill_roots(listing)`,
  `agent_roots(listing)` and `agent_collect(roots = )`), they add the entries of live sessions and,
  at rank 3, the `plugins` setting's plugins with no enabled or failed entry, resolved by
  `plugin_resolve()` and read with `plugin_type_paths()` only, skipped where `plugin_trusted()` (now
  shared with `plugin_enable()`) refuses. Syncs keep `FALSE`.
- Green: `^ext-plugins$` PASS 392 (the IC-69 test unchanged; the eager `extensions/m.R` never ran; a
  settings plugin inside an untrusted project is not listed, which fails with the trust check
  removed); with skill-*, subagent-defs, arch-layers, lint-rules, console-commands PASS 1085; full
  suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35435. Lint clean; Rd unchanged.
- Deviations: none (04 `gptr_skills()` does not say which plugins are listed; the fix meets
  `?gptr_skills`, "those of enabled plugins"). A settings plugin whose entry failed is not listed
  (the plan said "no enabled entry"), and no separate dedupe: discovery keeps one row per path and
  source. Open: none.

### skills-2 - A skipped SKILL.md is named by gptr_skills() and by a preload of its name
- Finding 103. Red: `^skill-discover$` FAIL 2 PASS 187: in a trusted project holding
  `.gptr/skills/nodesc` (no description) and `.gptr/skills/Bad_Name`, `gptr_skills("project")`
  printed `# 0 rows` only, and `peter(skills = "nodesc")` said "No skill with this name is
  available; gptr_skills() lists them."
- Cause: `skill_parse()` wrote its reasons to the registry diagnostics only and `skill_collect()`
  dropped the NULL spec, so neither the listing nor `skill_body()`'s not-found branch knew of the
  file.
- Fix: `skill_collect()` also returns `skipped` (origin by path); `gptr_skills()` prints the footer
  `# 2 SKILL.md files skipped: .gptr/skills/Bad_Name, .gptr/skills/nodesc; gptr_registry(diagnostics = TRUE) says why.`;
  when a skipped file's directory name matches, `skill_body()` raises `gptr_error_invalid_argument`
  "The skill file .gptr/skills/nodesc/SKILL.md was skipped: description is required." Discovery
  still never errors.
- Green: `^skill-discover$` PASS 192 (no request reaches the fake model; an unknown name keeps its
  message); with skill-*, ext-plugins, tool-read, gptr-gateway, subagent-defs, console-commands,
  arch-layers, lint-rules PASS 1660. Lint clean; Rd unchanged.
- Deviations: none (the contract quotes neither text). The reasons come from parsing the file again
  with a `diag` callback (new `skill_parse()` argument), not from the latest diagnostic as planned:
  a cached skip whose diagnostic left the log (1,000 rows, a swapped registry) would have had none.
  Open: `read
  skill:nodesc/SKILL.md` still says "Unknown skill" (`skill_file_path()` in R/tool-read.R drops the
  reason).

### ident-1 - A bare hyphenated name gets a gptr error naming the quoted form
- Finding 112. Red: `^gptr-capture$` FAIL 1 PASS 357:
  `resolve_identifier(high-performance-r, "skills")` raised base R's simpleError "object 'high' not
  found" from `eval(expr, mask)`.
- Cause: R parses the name as `(high - performance) - r`; `resolve_identifier()` treats only unary
  `+`/`-` specially, so the binary call reached `ident_mask()`, which binds whole identifiers only
  (with numbers bound to the pieces, the error suggested quoting "high - performance - r").
- Fix: before the mask, a binary `-` whose leaves are names or numbers (`ident_hyphen_name()`) is
  refused with `gptr_error_invalid_identifier` "`high-performance-r` reads as subtraction; quote the
  name: skills = "high-performance-r"." Nothing is evaluated, so bound pieces change nothing. 03
  section 4.1.3, 04 section 6.1.3.
- Green: `^gptr-capture$` PASS 364 (`peter(skills = high-performance-r)` sends no request;
  `c(+grep, -write)` and `shiny_bslib` unchanged); with gptr-*, copy-gateway, subagent-defs,
  skill-discover, arch-layers, lint-rules PASS 1819. Lint clean; plan checks pass; Rd unchanged.
- Deviations: D-252 (extended). The test spells the call `high - performance - r` (the same parse)
  or builds it with `str2lang()`, as lintr's infix rule refuses the bare spelling. Open: none.

### mcp-print - print(h) says where the serve token is and what the served mode allows
- Finding 102 (and finding 100's point, shown on the handle). Red: `^mcp-server$` (NOT_CRAN=true)
  FAIL 3 PASS 167: `print(h)` said "token: in the environment variable GPTR_MCP_TOKEN of the client,
  as $config shows" and no mode line, while the claude_code, claude_desktop and cursor snippets
  embed `Bearer <token>`.
- Cause: the hard-coded token line described the codex snippet only.
- Fix:
  `token: inside the $config snippets, printed redacted (as.character() gives the text; $config$codex passes it as GPTR_MCP_TOKEN)`,
  and while the handle is the running server's,
  `mode: manual; calls that need approval are refused (set the mode, then restart the server to change it)`
  from its dedicated session.
- Green: `^mcp-server$` PASS 170 (the three JSON snippets hold the token, the codex `$args` do not;
  the print holds neither the token nor the old line); with mcp-*, arch-layers, lint-rules PASS 907
  SKIP 1. Lint clean; Rd unchanged.
- Deviations: none (the contract and vignette do not quote the print). Open: none.

### mcp-trusted - gptr_mcp()'s trusted column means what the server spec's trusted means
- Finding 105. Red: `^mcp-config$` FAIL 2 PASS 103: after `gptr_mcp_add("docs", url = ...)` the spec
  said `trusted` FALSE and the `gptr_mcp()` row TRUE; a project server in an untrusted project read
  TRUE once trusted.
- Cause: `mcp_server_listing()` filled `trusted` with project trust (`!isFALSE(s$startable)`), which
  status `"untrusted"` already reports, while the spec's `trusted` is annotation trust read by
  `mcp_tool_level()`.
- Fix: the column is `isTRUE(s$trusted)`; `?gptr_mcp` defines it (a user `mcp.json` entry marked
  `"trusted": true`, whose `readOnlyHint` then lowers tool risk) and the mcp vignette says how to
  mark a server. 04 section 5.12.
- Green: `^mcp-config$` PASS 106 (marking the entry makes both TRUE; a claude-code:user server reads
  FALSE; a trusted project's server stays FALSE with status configured); with mcp-*, arch-layers,
  lint-rules PASS 916 SKIP 1; zzz PASS 145. Lint clean; plan checks pass; `gptr_mcp.Rd` regenerated.
- Deviations: D-252 (extended). Open: none.

### art-1 - peter$app() launches by default only at the console, and says why it did not
- Finding 56. Red: `^artifact-app$` FAIL 4 PASS 521: without `launch` in a non-interactive run the
  tool result read only `(stopped)`; with `gptr.interactive = TRUE` nothing launched; the formals
  pinned `interactive()`.
- Cause: both forms defaulted to base `interactive()`, which ignores `gptr.interactive`, and the
  skip gave no reason, so a model in Rscript took it for a failure and built v002 with
  `launch = TRUE`.
- Fix: `launch = NULL` in both forms, resolved in `artifact_app()` as
  `launch %||% gptr_has_human()`; a skip that nobody asked for adds the message
  `not launched: nobody is at an interactive console, so v001 was saved without starting it; pass launch = TRUE to start and check it now, or gptr_artifacts("x", open = TRUE) later`.
  The tool's `launch` description, `?gptr_artifacts`, the tools-and-artifacts vignette, 03
  section 4.2 and 04 section 9.4 say so.
- Green: `^artifact-app$` PASS 525 (one version, no process record; `launch = FALSE` has no message;
  at the console the start path runs); with artifact-*, copy-artifact, arch-layers, lint-rules, zzz
  (NOT_CRAN=true) PASS 3294 SKIP 10. Lint clean; plan checks pass; `gptr_artifacts.Rd` regenerated.
- Deviations: D-252 (extended). The message is added once in `artifact_app()`, not in each caller;
  the test mocks `artifact_start()` rather than the type's launch; D-252's contract line, left 156
  wide by mcp-trusted, rewrapped. Open: none.

### art-2 - An artifact in a temporary workspace is announced to the user and the model
- Finding 48. Red: `^artifact-app$|^prompt-context$` FAIL 4 PASS 617: without `.gptr/` the
  environment block read `Artifacts: /var/folders/.../T//Rtmp.../gptr/artifacts` with no word that
  it is temporary, and `peter$app()` signalled no notice.
- Cause: the tempdir fallback is intended (`?gptr_artifacts`), but neither the model nor the user
  was told, so models shortened the opaque path to a relative `artifacts/<id>/app.R` that does not
  exist (3/3 GPT runs).
- Fix: the line is
  `Artifacts: <path_norm(tempdir()/gptr/artifacts)> (temporary: deleted when R exits; cite this full
  path; gptr_init() keeps artifacts)`; after a version is built without `.gptr/`, `artifact_app()`
  sends `gptr_inform(... "notice", .once = "artifact-temp-workspace")` naming
  `path_norm(artifact_dir(id))` and `gptr_init()`. 03 section 5.7.
- Green: `^artifact-app$|^prompt-context$` PASS 621 (one notice, none on the second call or with
  `.gptr/`; after `gptr_init()` the line is `.gptr/artifacts`); full suite (NOT_CRAN=true) FAIL 0
  SKIP 64 PASS 35482. Lint clean; plan checks pass; Rd unchanged.
- Deviations: D-252 (extended). The prompt's path is normalised (the plan's `tempdir()` path had a
  `//` and the unresolved `/var` link), so it is the prefix of the path the notice names. Open:
  none.

### reg-1 - Registering the same kind and name again replaces your earlier record
- Findings 38, 31 (absorbs the models plan's provider-1). Red: `ext-registry` FAIL 8 PASS 211: a
  second `gptr_register()` of provider `corp` left `base_url` at `a.invalid`, the new row
  `overridden`, no diagnostic and no message, the first `off()` returned `TRUE`; a re-registered
  `shout` tool kept its old `fun`.
- Cause: `gptr_register()` only appended a rank-3 `user` record; `registry_sort()` keeps the first
  at equal rank and `registry_collision()` skips same-source ties, so the stale record won silently
  (and kept the old egress).
- Fix: for `first`-resolving kinds, `gptr_register()` adds the new record, then removes the earlier
  process-level `user` records of that `(kind, name)`, logs a `replaced` diagnostic and sends the
  `notice` "Replaced your earlier <kind> '<name>'."; a spec that fails validation leaves the old
  one; hooks and policies keep both. `?gptr_register`, 03 sections 4.3, 04 `gptr_register()` and
  10.1.
- Green: `ext-registry` PASS 219 (one active `corp` at `b.invalid`, the old `off()` `FALSE`, the new
  one removes it; the tool's second `fun`; a corrupted spec leaves it; two `turn_end` hooks stay);
  full suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35496. Lint clean; plan checks pass;
  `gptr_register.Rd` regenerated.
- Deviations: D-252 (extended). The rule removes every earlier `user` record of the key, including
  one from a user directory, user `mcp.json` or user-scope extension, so the explicit registration
  wins in either order. Open: none.

### bg-1b - A message piped into a waiting session still opens the resumed run with the console note
- Review of bg-1 (medium). Red: `^agent-background$` FAIL 2 PASS 203: after a manual-mode background
  session parked, `s |> peter("also say hi")` then `gptr_step(s)` started the run itself, and the
  second request held the stale denial and "also say hi" but no "I am at the console now" note.
- Cause: a piped message (or a follow-up `bg_park_session()` re-queued) made `sdk_check()` see
  queued input, so `gptr_wait()`/`gptr_step()` started the run through `gateway_run_start()` and the
  sweep only cleared the ask.
- Fix: `sdk_check()` returns NULL for a `waiting` session; `gptr_wait()` keeps pumping while it
  waits and the sweep's `bg_resume()` queues the note and starts the run. `gptr_step()` leaves a
  waiting session as it is (as with nothing queued); `?gptr_step` and 04 section 6.5 say so, 04
  section 7.21 names `bg_resume()`.
- Green: `^(agent-background|gptr-sdk)$` PASS 300; with gptr-gateway, agent-run, injection-e2e,
  arch-layers, lint-rules, zzz (NOT_CRAN=true) PASS 1753. Lint clean; plan checks pass;
  `gptr_step.Rd` regenerated.
- Deviations: D-252 (extended). Open: none.

### sessions-20b - Removing a fork's shadowing binding is not reported as a change to the source
- Review of sessions-20 (low). Red: `^session-object$` FAIL 1 PASS 541: after the fork ran `k = 5`,
  a second `r` call `rm(k)` read `~ k <numeric> modified (in the source workspace)` while `home$k`
  was still 1.
- Cause: the mark took any modified row whose new binding is not `own`, so the source's binding
  reappearing under a removed overlay binding read as a change to it.
- Fix: `src = !old$own[k] & (!new$own[j] | env_same(...))`: only a row that was the source's before
  the code ran and still is, or whose new binding shares its object (`e$flag = 'x'`). `v <<- 2` and
  `:=` keep the mark; a rebinding and an un-shadowing `rm()` read `~ k <numeric> modified`. 03
  section 6.12 and 04 section 7.9 amended.
- Green: `^(session-object|eval-core|tool-r|env-snapshot|copy-eval)$` PASS 1196. Lint clean; plan
  checks pass.
- Deviations: D-252 (extended). Open: none.

### art-2b - The art-2 test removes its temporary-workspace artifact
- Review of art-2 (low). Red: a check placed after the test,
  `dir.exists(file.path(tempdir(), "gptr", "artifacts",
  "temp-workspace-notice"))`, was TRUE (`^artifact-app$` FAIL 1 PASS 530); the copy held app.R, v001
  and v002.
- Cause: `withr::defer(unlink(artifact_dir(id), ...))` evaluates `artifact_dir(id)` at exit, after
  the test made `.gptr/`, so it removed the project copy and left the shared temporary workspace's
  one for later tests.
- Fix: the path is taken before `.gptr/` exists (`tmp = artifact_dir(id)`), then deferred. Test
  only.
- Green: the check FALSE (PASS 531; the check is not kept); `^(artifact-app|prompt-context)$`
  PASS 621. Lint clean.
- Deviations: none. Open: none.

### bg-1c - The idle-tick denial says once to repeat the call
- Review of bg-1 (low). Red: `^agent-background$` FAIL 1 PASS 204: the denial read "... call the
  tool again with the same input and the user will be asked. Nothing ran and nobody declined; repeat
  the call when the session continues.", the same instruction twice (convention 11).
- Cause: bg-1's `how` repeated what `bg_pending_text("approval")`, the denial's reason, already
  says.
- Fix: `how = "Nothing ran and nobody declined."`, which still replaces "Explain what you need or
  choose another approach."; the test matches the whole ending.
- Green: `^(agent-background|console-ui|perm-ask|tool-ask|agent-dispatch)$` PASS 600; after bg-1b to
  bg-1c the full suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35504. Lint clean; plan checks pass.
- Deviations: D-252 (bg-1 quote amended). Open: none.

### guard-1b - A q bound to data is refused as the function argument a base function looks up
- Follow-up of guard-1. Red: `^eval-guard$` FAIL 9 PASS 139: with `q` bound to `quantile(1:10)` in
  `envir`, `Negate(q)('no')`, `base::Negate(f = q)`, `sweep(m, 1, s, q)`, `eapply(env, q)`,
  `.mapply(q, ...)`, `.S3method('print', 'foo', q)`, `Negate('q')('no')` and `Vectorize('q')('no')`
  passed, and a scan of base found `.mapply`, `.S3method`, `eapply`, `Negate` and `sweep` missing
  from the function-argument table.
- Cause: the table and the string list were hand lists of the apply family. With a data global `q`,
  each form above reaches `base::q` through the callee's `match.fun()` (for a string,
  `Vectorize()`'s `formals()`), calling it (`Negate(q)('no')`, `.mapply(q, list('no'), NULL)`) or
  returning or registering it for a later call (`Negate(f =
  q)`, `.S3method('print', 'foo', q)`).
- Fix: `eval_guard_fun_arg` holds `do.call()` and every base function that applies `match.fun()` to
  a formal; `eval_guard_indirect` is its names plus `Vectorize`, `get`, `get0`, `getExportedValue`
  and `Recall`. `Vectorize(q)` (returns the data) and `Recall(q)` (passes the value to the calling
  function, as `f(q)` does) still pass: a probe shows neither reaches `base::q`, so neither is
  refused.
- Green: `^eval-guard$` PASS 148; eval-*, copy-eval, copy-tools, tool-r, arch-layers, lint-rules,
  s1-* PASS 2454; full suite (NOT_CRAN=true) FAIL 0 SKIP 64 PASS 35516. Lint clean.
- Deviations: D-252 (guard-1 rule extended). Open: stats functions that `match.fun()` an argument
  (`integrate`, `aggregate`, `dendrapply`) and user functions that do still pass a data `q`
  (advisory guard), and so does a base function given as another's function argument that receives a
  data `q` through `...` (`sapply(x, lapply, q)`).

### guard-1c - Only a call's function argument is read as a string outside P09's indirect calls
- Review of guard-1b (low). Red: `^eval-guard$` FAIL 2 PASS 149:
  `.S3method('edit', 'myclass', function(name, ...)
  name)` and `Vectorize(function(x, de) x + de, 'de')` were refused as calling `edit()` and `de()`
  (so was `.S3method('identify', ...)`); all three passed before guard-1b.
- Cause: guard-1b gave every function-argument call and `Vectorize` the every-string rule, but a
  generic, a class and `vectorize.args` are not function names.
- Fix: `eval_guard_indirect` is P09's 18 names again; the walk adds the string function argument of
  every `eval_guard_fun_arg` call and of `Vectorize(FUN)`, so `Negate('q')`, `Vectorize('q')` and
  `.S3method('print',
  'foo', 'q')` stay refused. A `q` symbol is still checked in `eval_guard_fun_arg` calls only:
  `Vectorize(q)` of data passes.
- Green: `^eval-guard$` PASS 151;
  `^(eval-.*|copy-eval|copy-tools|tool-r|arch-layers|lint-rules|s1-.*)$` PASS 2244. Lint clean.
- Deviations: D-252 (guard-1 rule). Open: none.

### guard-1d - The function-argument rule refuses the argument as passed
- Review of guard-1b (medium). With a data `q`, `sapply(list('no'), lapply, q)` and
  `lapply(list('no'), sapply, q)` quit R and pass the guard: the inner function gets `q` through
  `...`, and its `match.fun()` finds `base::q`. `Map(lapply, list(list('no')), list(q))` only errors
  (`mapply()` passes `dots[[2L]][[1L]]`).
- Records only, the review's simplest fix: D-252 and guard-1b's heading say `q` passed directly as
  the function argument is refused, and guard-1b's Open names this form. A code fix would add one
  more special case (a `q` beside a base function given as the function argument) to an advisory
  guard that `eval(parse(text = ...))` evades.
- Deviations: D-252 (guard-1 rule wording). Open: as guard-1b.

### guard-1e - guard-1b says how each form reaches base::q
- Review of guard-1b (low) and a round-2 problem. `base::Negate(f = q)` and
  `.S3method('print', 'foo', q)` leave a child R alive (they return or register `base::q` for a
  later call), and `sweep(m, 1, s, q)` of a numeric `m` stops in `q()`'s `save` check, yet
  guard-1b's Cause and the test comment said each form quits R. Both now say each reaches `base::q`,
  calling it or returning or registering it. Records and a test comment only.
- The criterion that `Vectorize(q)(1)` and `Recall(q)` be refused is not adopted: neither reaches
  `base::q` (they stop with "attempt to apply non-function" and "'Recall' called from outside a
  closure"), as guard-1b records, so refusing them would be a deliberate over-refusal.
- Green: `^eval-guard$` PASS 151. Lint clean.
- Deviations: none. Open: none.

### guard-1f - The guard does not keep a function-frame home alive in the installed package (2026-10-23)
- Found by the integration branch's R CMD check (orchestration tip alone too, from guard-1's
  86a35bc7). Red: `test-copy-eval.R` and `test-copy-tools.R` against the installed (byte-compiled)
  package FAIL 5 PASS 36: "1 copies of `big` (allowed 0)" after `eval_r()` in a function-frame home.
  `devtools::test()` loads uncompiled code and passed.
- Cause: guard-1 passes the evaluation environment to `eval_guard()`, and a byte-compiled `for` loop
  calling a closure (`eval_guard_walk()`) keeps that frame, and so the user's frame, referenced
  after the call.
- Fix: the loop is a `while` loop, as `gateway_check_visible()` already does for the same reason.
- Green: the two files installed PASS 41; `^(eval-.*|copy-.*|arch-layers|lint-rules)$` PASS 815.
  Lint clean.
- Deviations: none. Open: none.

## Task CI-91 - PR #77's hosted checks: a C-locale capture, R-devel's Partial() and a late gc shutdown (2026-10-23, #77)

### ci91-1 - The fuzzy-edit print test compares the printed lines in any locale
- Red: PR #77 head 84fe1f1, R-CMD-check run 40049492168, job 120738934178 (ubuntu-latest release,
  LC_ALL=C) failed `test-tool-edit.R:309` and `:312` (tools-8's "gptr_patch prints the message, and
  the diff only when fuzzy"): the printed diff lines held `\342\200\230a\342\200\231` where the
  expected `p$diff` held `‘a’`. Locally `LC_ALL=C` `^tool-edit$` FAIL 2.
- Cause: the test, not the print. `print.gptr_patch()` writes UTF-8 bytes (`ns_print_lines()`,
  `useBytes = TRUE`), the right output for the console; `capture.output()` returns them unmarked in
  a C locale, so `identical()` compared unknown-encoding bytes with marked UTF-8 strings.
- Fix: the test marks the captured lines UTF-8 before comparing.
- Green: `LC_ALL=C` `^tool-edit$` PASS 196; `^(ext-check|eval-guard|tool-edit)$` PASS 605.
- Deviations: none. Open: none.

### ci91-2 - The q guard knows R-devel's Partial()
- Red: job 120738934342 (ubuntu-latest devel) failed `test-eval-guard.R:182`: guard-1b's scan of
  base found `Partial` (new in R-devel; it `match.fun()`s its `f`) missing from
  `eval_guard_fun_arg`.
- Cause: the table is written by hand and the test checks it against the running R's base, as
  guard-1b meant it to; R-devel added a function after it was written. With `q` bound to data,
  `Partial(q)('no')` would reach `base::q()`.
- Fix: `Partial = "f"` in the table (an entry for a function this R lacks matches nothing, since
  `eval_guard_match()` finds no definition); the q-form test adds `Partial(q)('no')` where base has
  `Partial`.
- Green: `^eval-guard$` on R 4.6.1 (no `Partial`) PASS; R-devel in hosted CI.
- Deviations: none (D-252's guard-1 rule names the table, not its entries). Open: none.

### ci91-3 - The D-085 test counts only its own session's shutdown
- Red: job 120738934119 (ubuntu-latest release) failed `test-ext-check.R:539` ("a session finalized
  during a check keeps its deferred shutdown (D-085)"): one deferred event was left. The test is
  main's and unchanged; the release jobs of main's last nine green runs passed it, and locally it
  passes.
- Cause: the test, not D-085. `session_finalizer()` is the only caller of `ev_defer()`: every
  session that gc collects queues its own `session_shutdown` in the registry current at that
  moment. The asserted event had run (its command was gone, `seen$reasons == "gc"`), so the entry
  left was another session's, left by an earlier test and collected after the check's drain. A
  collection before the drain would have added a second `"gc"` to `seen$reasons` the same way.
- Fix: the hook records only `s1`'s events (the queued payload names `s1`), and the test checks
  that no deferred event for `s1` is left.
- Green: `^ext-(check|events)$` PASS 455.
- Deviations: none. Open: none.

## Task CI-92 - INFRA-03 answers the pause menu at its chevron (2026-10-25, #79)
- Red: PR #77 head 84fe1f1, R-CMD-check run 40049492168, job 120738934342 (ubuntu-latest devel)
  failed INFRA-03 (`test-console-interrupt.R:496`, then 497, 501, 504 and 508): after `Paused` the
  driver sent `c` and `STATUS-TTFT idle` never came, step 2's tool never ran, step 3 passed. The
  test showed none of the child's output.
- Rate: the R-CMD-check.yaml runs since 2026-10-06 (389 runs, 3,025 jobs of all attempts, all 580
  failed job logs read) hold 3 INFRA-03 failures in about 1,604 runs of the test. Two (2026-10-07,
  "connections left open") came before CI-20, the menu never shown; one since CI-20 in 1,517 runs,
  this job. The other INFRA-03 lines in those logs are skips. Evidence (local, not committed):
  `dev/.session/live/infra03-measure.json`.
- Cause (the test, not the product): `readline_answer()` takes a line read back under 0.1 s as
  typed before the question (IC-75), and the driver sent each menu key 0.2 s after `Paused`, which
  the menu prints before its chevron. On a loaded runner the child reached the read more than
  0.1 s after the key came: the buffered `c` was stale, the menu asked again and took the driver's
  next line as its answer. Reproduced on d88014eb with a delay traced in before
  `readline_answer()` and main's strict rule (no stale line answers): 0.12, 0.3 and 0.6 s FAIL 10
  PASS 133 each, the trace showing `c` read in 0.081 s and `step_tool()` taken as the answer; 0,
  0.05 and 0.09 s pass. P28's stale-key rule (its Fix 8: a stale line that is one of the menu's
  keys answers it) hides it, 0.05 to 1.2 s pass, so red needed main's rule.
- Fix (test only, db24961b): the driver waits for the menu's chevron before each answer, as the
  steer already did, and sends it 0.2 s later; each wait is an expectation whose failure shows the
  child's whole output.
- Green: with the fix the injected delays (0 to 0.6 s strict, 0.12 to 1.2 s with P28's rule) PASS
  145 each, and a 31 s delay fails naming the missing chevron, the child's output shown. `CI=true`
  `NOT_CRAN=true` `^console-interrupt$`: 30 of 30 PASS 145 (load 25-82, 16 cores), 10 of 10 PASS
  145 at load 254-465 (32 busy loops). Merged with P28 at ccaa2a06: 10 of 10 PASS 151, INFRA-03
  run each time (no `SIGINT is ignored` skip); `^console-` PASS 3408; lint clean. Merged with P28
  at ecfad58c (d924d1bb), whose Task 89 made the steer's chevron waits `pty_asked()`: every
  chevron wait is `pty_asked()`, the chevron of the locale; 5 of 5 PASS 151 in UTF-8, 3 of 3
  PASS 136 SKIP 1 under `LC_ALL=C` (the skip `non utf8 locale` at line 151), INFRA-03 run each time.
- Deviations: none. Open: none.

## Task CI-93 - The check fits CRAN's time budget (2026-10-25, #79)
- Policy: CRAN asks that a check take as little CPU time as possible, long tests made optional,
  and its incoming pretest gives a NOTE when the whole check passes 10 minutes (`Overall checktime
  ... > 10 min`): 600 s is the de facto budget. The maintainer asked that gptr be designed to it.
- Measured (elapsed): main's CRAN-mode lane (cran-mode: ubuntu-latest R-devel, `NOT_CRAN=false`,
  `--no-manual`) checked 02e93fa in 301 s (job 120763739795: code checks 107 s, tests 48 s, install
  36 s, vignettes 14 s, examples 10 s). win-builder (Windows Server 2022, R 4.6.1) checked
  6777610e in 631 s: code checks 238 s, tests 177 s, PDF manual 40 s, examples 28 s, HTML manual
  24 s, vignettes 17 s, incoming feasibility 13 s. That run ended in Status 1 ERROR, two console
  tests that expected Unicode glyphs where its Windows console draws ASCII (test-console-repl.R:314,
  test-console-ui.R:614), which P28's Task 86 fixed; its timings stand, because every test ran
  (`[ FAIL 2 | WARN 0 | SKIP 1566 | PASS 4067 ]`) and the check went on to its end.
- Change: (1) cran-mode takes CRAN's thresholds (`_R_CHECK_TEST_TIMING_CPU_TO_ELAPSED_THRESHOLD_`
  and `_R_CHECK_EXAMPLE_TIMING_CPU_TO_ELAPSED_THRESHOLD_` 2.5, `_R_CHECK_EXAMPLE_TIMING_THRESHOLD_`
  5, `_R_CHECK_LIMIT_CORES_`), errors on a NOTE and fails when its check step passes 480 s
  (01d0b63d). (2) Windows-check.yaml's `cran` job checks the whole package as CRAN does, on
  Windows release and unsharded: CRAN's test list, both manuals (TinyTeX, HTML Tidy), the same
  thresholds and NOTE gate; it fails over 600 s (4d865b82). Each timed step includes the
  package's build. (3) The CRAN test trim (6816efd3): the list goes from 66 files to 35 and 8
  more blocks start with `skip_on_cran()`, chosen at 6777610e by time saved per CRAN-covered
  function lost while every R file a CRAN test reached stays reached, with tests of at least a
  quarter of its CRAN-covered functions; re-applied by block name to P28's tests. The 12 blocks
  it also skipped in the security files run on CRAN again (8c0edb03): D-240 skips only their
  blocks of 500 ms or more on Windows, and 11 took 250-480 ms on windows-latest in both timing
  runs (39555362618, 39559882743), the 12th postdating them. With incoming checks off, R lists
  slow examples without a NOTE, so the time budgets bound them, not the gate.
- Trim, measured on macOS (16 cores, load 6.5-7.9; the CRAN list against the installed tarball,
  `NOT_CRAN`, `CI` and `GITHUB_ACTIONS` unset, 4 alternating pairs): before (ecfad58c) 20.7 s in
  each run (PASS 4146 SKIP 1550), after (8c0edb03) 13.7-13.8 s (PASS 2589 SKIP 896), FAIL 0 in
  each: 33-34% less. covr over the CRAN list: lines 46.4% to 39.9%, functions 2,441 to 2,195 of
  4,138 (246 lose their last CRAN test), R files reached 115 of 125 before and after, each
  keeping at least 26.7% of its CRAN-covered functions (`console-input.R`, 4 of 15, the least).
  The touched files with `NOT_CRAN=true`: PASS 3865 SKIP 1.
- Expected: if win-builder's tests shrink alike, about 60 s less, a check near 570 s, 30 s under
  the budget, with code checks (238 s) its largest part; cran-mode about 16 s less.
- Tests: test-zzz.R's crashed-check guard covers the new job (`^zzz$` FAIL 2 before it, PASS 148
  after); both workflows parse with `yaml::read_yaml()`; lint clean. At 8c0edb03, the CRAN list
  from the installed tarball, `NOT_CRAN` unset: PASS 2589 SKIP 896 in 13.7-13.8 s in UTF-8; PASS
  2575 SKIP 900 WARN 1 in 13.4 s under `LC_ALL=C`, the warning (`strings not representable in
  native encoding`) from test-tool-read.R's UTF-8 BOM block, as on main at 02e93fa; `R CMD check
  --as-cran` in CRAN mode (cran-mode's variables, both manuals) Status OK in 139 s, `Running
  'testthat.R' [13s/14s]`. The security files with `NOT_CRAN=true`, in UTF-8 and under
  `LC_ALL=C`: PASS 2017 SKIP 1.
- Deviations: D-240 (amended in place). Open: the 10 R files no CRAN test reaches, before or after
  the trim (artifact-registry, bridge-lang, console-jsonl, doc-export, doc-knitr, proc-rscript,
  provider-bedrock, s1-emulate, s1-ollama, tool-search); the Windows budget's calibration against
  win-builder once the new lane has run (a hosted runner is not win-builder, and its timed step
  includes the build); that BOM block's warning in CRAN mode under `LC_ALL=C` on macOS.
- Windows evidence: corrected by CI-95 (run 40206216160), whose four blocks of 500 ms or more skip.

## FIX-20 - Console review fixes (2026-10-25, #80)
Scope: the cheat sheet's console sections reviewed against P28's build (`516ec73c`, PR #78); each
code finding was confirmed by an independent refuter before it was fixed. Of 34 findings (R01-R34),
33 are fixed (R29 in part) in 24 commits (duplicates share one), each red on `516ec73c`'s code
first; R27 is not fixed. Console neighbours
(`^(console-|gptr-config|agent-run|agent-loop|agent-dispatch|agent-background|session-object|doc-|arch-layers)`)
at `516ec73c`: FAIL 0 SKIP 3 PASS 8702.

### R01 - A label keeps a value wider than the row on its row
- Commit `cdd2b003`. Red: `^console-commands$` FAIL 1 PASS 146: on macOS without `.gptr/`,
  `/status`'s `file` row (a tempdir path of about 108 columns) broke at its only space, `file` alone
  and the path at column 2.
- Fix: `console_wrap()` (R/utils-conditions.R) keeps a label and one value wider than the row on one
  row, which the terminal wraps; a value that fits still goes to the next row. The verdict's guard
  kept every two-word line on one row, which would also overflow a pair that fits (menus and
  permission prompts count their rows).
- Green: PASS 147; neighbours FAIL 0 SKIP 3 PASS 8705. Lint clean.
- Deviations: none. Open: none.

### R02 - A failing command's notice ends with a blank row too
- Commit `6892a071`. Red: `^console-commands$` FAIL 2 PASS 147: after "Unknown command" and "Error
  in /<cmd>" `peter>` came straight after the red notice; every other console block ends with a
  blank row.
- Fix: `console_command()` prints its three notices through one local `say()`, which writes the
  margin's blank row.
- Green: PASS 149; neighbours FAIL 0 SKIP 3 PASS 8707. Lint clean.
- Deviations: none. Open: none.

### R03, R05 - /env and the banner in a fork list what the fork reads
- Commit `c54627b6`. Red: `^console-commands$` FAIL 3 PASS 151: after `/fork`, `/env` listed `ls()`
  of the overlay alone (described with `inherits = FALSE`) and the banner's objects line too, so the
  home's objects the fork reads were missing; `/env [pattern]` matches a literal substring (R05).
- Fix: `console_env_names()` walks the overlay chain as `env_view_snapshot()` does (D-252), and
  `/env` describes each name where it is bound. The verdicts named `binding_env()`, an L3 function
  the console may not call (arch-layers), so the lookup is a two-line walk. `/help` and the console
  vignette (.Rmd and .Rmd.orig) say `/env [text]`.
- Green: PASS 154; neighbours FAIL 0 SKIP 3 PASS 8712. Lint clean.
- Deviations: D-253. Open: none.

### R04 - /context marks the ledger's total as an estimate
- Commit `6c087d0b`. Red: `^console-commands$` FAIL 1 PASS 153: the ledger's `total` (gptr's
  estimate of what it sent) sat unmarked over `context left`, which comes from the counts the
  provider reported.
- Fix: the row reads `total (est.)`. The verdict also moved the test's total to `length - 2`; it is
  the row before `context left`, so the index stays `length - 1`.
- Green: PASS 154; neighbours FAIL 0 SKIP 3 PASS 8712. Lint clean.
- Deviations: D-253 (IC-77). Open: none.

### R06, R07 - /clear keeps the thinking level of the session it ends
- Commit `35b954b5`. Red: `^console-commands$` FAIL 2 PASS 155: in a console reopened with
  `s |> peter()` (`rs$model` NULL) `/clear` fell back to `s$model`, which holds no level, so the
  next conversation lost `:high`.
- Fix: the fallback is the session's model with its level as the `:<level>` suffix, built inline
  with `kernel_model_ref()`'s rule that a router chooses its own (that function is L3). R06's other
  points are left: the fork's objects after `/clear` are R08's, and `/exit` returning NULL after
  `/clear` is documented.
- Green: PASS 157; neighbours FAIL 0 SKIP 3 PASS 8715. Lint clean.
- Deviations: none. Open: none.

### R08 - /clear keeps the workspace the conversation used
- Commit `49b67fa7`. Red: `^console-commands$` FAIL 2 PASS 158: after `/fork`, or on a piped session
  with its own `envir`, `/clear` fell back to the console call's environment, so the objects `/env`
  had listed were gone from `/env` and `!code` although `/clear` said they were kept.
- Fix: `cmd_clear()` keeps the evaluation environment (`rs$envir = repl_eval_env(rs)`). R06's
  verdict advised against keeping a fork's overlay; two conversations of a default console share
  globalenv the same way and the fork's home stays untouched, so R08 is followed.
- Green: PASS 160; neighbours FAIL 0 SKIP 3 PASS 8718. Lint clean.
- Deviations: none. Open: none.

### R09 - A cut listing names as.data.frame() for the rest
- Commit `dee60779`. Red: `^(utils-text|listing-print)$` FAIL 2 PASS 85 SKIP 1:
  `print.gptr_listing()` said `# 20 of 26 rows shown` and no way to see the rest (`/skills` and
  every listing command).
- Fix: the count line adds `; as.data.frame() lists all`. No new argument; the verdict's `/skills`
  filter is a feature and is left out.
- Green: PASS 87 SKIP 1; neighbours FAIL 0 SKIP 3 PASS 8718. Lint clean.
- Deviations: none (04 says only "a count line"). Open: none.

### R10 - /doc and /status name the transcript the project remembers
- Commit `6dd99544`. Red: `^console-commands$` FAIL 3 PASS 164: between turns `/doc` said "No
  document is bound." and `/status` `document  (none)` while the console kept writing into the
  remembered transcript.
- Fix: the `doc.site` service (R/doc-replay.R) falls back, outside a run where a person can answer
  (`gptr_can_prompt()`) and with no document or `gptr_doc()` binding, to the transcript the project
  remembers (`doc_console_site()`; never a new one). In-run callers (the documents section, the r
  and edit tools) and callers nobody can answer are unchanged. The verdict put the fallback in
  `cmd_doc_site()`, which would call doc-*.R functions from the console (arch-layers).
- Green: PASS 167; neighbours FAIL 0 SKIP 3 PASS 8725. Lint clean.
- Deviations: D-253 (04 section 7.0). Open: none.

### R11 - An error message of two lines is two rows
- Commit `9a2ce208`. Red: `^console-(commands|repl)$` FAIL 2 PASS 510: `console_command()` and
  `repl_passthrough()` escaped a line feed as `<U+000A>`, so `gptr_abort(c(msg, hint))` (`/resume`
  without `.gptr/`) was one garbled row and `repl_passthrough()`'s split on "\n" never fired.
- Fix: both use `console_escape()`'s default, which keeps line breaks. The two optional sites in
  R/console-interrupt.R are left: their rows go through `console_wrap()` as one row, not a one-token
  change.
- Green: PASS 512; neighbours FAIL 0 SKIP 3 PASS 8726. Lint clean.
- Deviations: none. Open: none.

### R12, R13 - /retry preloads the undone prompt's skills again
- Commit `012b1a3b`. Red: `^(console-commands|ckpt-rewind)$` FAIL 1 PASS 412: `/retry` of a
  `/skill:<name>` turn, or of a first turn `peter(skills =)` preloaded, sent the bare text:
  `gptr_rewind()` kept only the prompt's text.
- Fix: `ckpt_rewind_target()` also returns the opening message's `skill_content` names,
  `gptr_rewind()` keeps them as `s$last_rewind$skills` (`?gptr_rewind`, man/gptr_rewind.Rd), and
  `cmd_retry()` makes them the next prompt's skills, as `/skill:` does. R12's version read the
  checkpoint tree from the console (arch-layers), so R13's is followed.
- Green: PASS 413; neighbours FAIL 0 SKIP 3 PASS 8731. Lint clean.
- Deviations: D-253 (04 section 5.1). Open: none.

### R14, R29 - A turn after an undone first turn assigns the session again
- Commit `2a74bac9`. Red: `^doc-formats$` FAIL 2 PASS 260: `doc_console_statement()` stripped the
  inert prefix, so the `#~ s_x = peter(...)` of an undone or retried first turn still counted as the
  assignment and the next turn was written `s_x |> peter(...)`, which `source()` could not run
  (object 's_x' not found).
- Fix: only a live assignment counts (one expression). R29's recommended fix ("bug 4") is this one.
- Green: PASS 262; neighbours FAIL 0 SKIP 3 PASS 8704. Lint clean.
- Deviations: none. Open: R29's reported part, a later `!code` line that uses an undone turn's
  object, stays live, so `source()` stops there; making direct-R lines inert by the names they
  mention is dependency tracking (about 25 lines and a `/redo` path) for a rare case, which the
  verdict and the sheet's note call a defensible limitation.

### R15 - Leaving with a second Ctrl-C ends the prompt's row
- Commit `1cb854dd`. Red: `^console-repl$` FAIL 1 PASS 344: the second Ctrl-C at the prompt left the
  `peter> ` row open, so R's own `> ` followed on the same row.
- Fix: the row is ended before the REPL leaves.
- Green: PASS 345; neighbours FAIL 0 SKIP 3 PASS 8705. Lint clean.
- Deviations: none. Open: none.

### R16 - The agent runs programs with peter$sh(), not system2()
- Commit `ce976049`. Red: `^(prompt-text|northstar|bench-context|prompt-sections)$` FAIL 4 PASS 622
  (the wording checks and the rendered `r_session` text in fixtures/bench/prefix-baseline.json): a
  `system()`/`system2()` child inherits fd 1, which `sink()` cannot redirect, so its output bypasses
  the capture ("[no output]") and lands on the frozen live row, while the D-216 line told the model
  to use `system2(..., stdin = nullfile())`.
- Fix: the line reads "- system() and system2() children read the user's terminal and you do not see
  their output: use peter$sh() instead." Same 27 o200k tokens; the static prefixes stay
  1262/2378/2856/2999 and `dev/bench/tokens/run.R --check` passes. The verdict's
  `system2(..., stdout = TRUE)` alternative and its `eval_r()` pins of base R's fd behaviour are
  left out (`peter$sh()` capture is tested in test-bridge-sh.R). `?peter` (R/gptr-gateway.R,
  man/peter.Rd) and 03 section 7.3 say the same.
- Green: PASS 626; with `gptr-gateway` and `eval-core` FAIL 0 PASS 1422; neighbours FAIL 0 SKIP 3
  PASS 8702. Lint clean.
- Deviations: D-253 (amends D-216). Open: the smeared live row of a `system()` child's output stays
  (no runtime change, as the verdict advised).

### R17 (bug 1), R18 - gptr_wait() releases the background session it settled
- Commit `aa4bf4c2`. Red: `^agent-background$` FAIL 3 PASS 211: after `[b]` and the hinted
  `!!gptr::gptr_wait(gptr::gptr_last())` the settled session stayed registered (only `bg_sweep()`
  from the 50 ms timer released it, and the `peter>` prompt runs none), so `console_foreground()`
  was FALSE and none of its later prompts rendered; `gptr_jobs()` still listed it.
- Fix: `gptr_wait()` (R/gptr-sdk.R) runs `bg_sweep(FALSE, FALSE)` once after its pump when
  background state exists, as the in-pump tick does (no notice, no resume); not in `sdk_pump()`,
  which nested pumps inside an idle tick's tool also call. The new test cancels the later timer, so
  only the wait can release the session.
- Green: PASS 214; `gptr-sdk` PASS 116; neighbours FAIL 0 SKIP 4 PASS 8704 (at `516ec73c` the same
  run had FAIL 3, the console-typing pause-menu pty test under load average 20, green in all three
  fixed runs). Lint clean.
- Deviations: none. Open: `gptr_step()` on a background session still relies on the timer (not
  reported; at R's prompt the idle tick releases it at once).

### R17 (bug 2), R19, R31 - [b]'s gptr_wait hint takes `!!` only under the chat
- Commit `2e676454`. Red: `^console-interrupt$` FAIL 1 SKIP 1 PASS 131: the `[b]` row always named
  `!!gptr::gptr_wait(...)`; for a `peter("...")` call at R's prompt `!!x` is a double negation, so
  the wait ran to its end and `!` then failed on the session ("invalid argument type").
- Fix: `bang = if (!is.null(console_repl_find())) "!!"` in `policy_menu()`, so `!peter(...)` in the
  chat's code keeps it (R31's argument for `console_repl_find()` over `console_repl_prompt()`).
- Green: PASS 132; neighbours FAIL 0 SKIP 3 PASS 8707. Lint clean.
- Deviations: D-253 (IC-76; amends D-245). Open: R17's cheat-sheet wording is the sheet's, not code.

### R20 - A transcript opens with its replay note whatever its first line
- Commit `c3ba3748`. Red: `^doc-formats$` FAIL 6 PASS 256: a transcript whose first line was a
  prompt put the session header above the replay note and `library(gptr)`; one started by direct R
  or a command put them first.
- Fix: `doc_transcript_header()` starts a new file with the preamble, then a blank line and the
  header, as IC-49 says; one existing test that pinned the old line index moved.
- Green: PASS 262; `doc-io` and `doc-replay` PASS 1562; neighbours FAIL 0 SKIP 3 PASS 8705. Lint
  clean.
- Deviations: D-253 (04 section 11.5). Open: none.

### R21 - peter(.stdin = TRUE) on a terminal shows each typed line once
- Commit `209a1d54`. Red: `^console-repl$` FAIL 1 PASS 346: the stdin reader echoed every line it
  read, which a terminal already shows, so each line appeared twice.
- Fix: the line is echoed only where the reader's `file("stdin")` is no tty
  (`typed = inherits(rd$con, "file") &&
  stdin_tty()`); the prompt is still written. The verdict's bare `!stdin_tty()` would break the
  suite's echo tests when Rscript runs from a terminal, as the test's textConnection pipe always
  echoes. Under script(1) "Hello." shows once (twice before); piped input is unchanged.
- Green: PASS 347, also with a tty stdin; neighbours FAIL 0 SKIP 3 PASS 8707. Lint clean.
- Deviations: none. Open: a secret question under `.stdin = TRUE` on a tty is still shown by the
  terminal's own echo, before and after this fix.

### R22, R33 - A session the console returns at /exit keeps its specs
- Commit `b3d4915f`. Red: `^console-repl$` FAIL 3 PASS 347: `repl_main()` dispatched
  `session_shutdown` (reason "exit") for a session it created, which dropped its rank-0 records (a
  provider object as `model =`, `tools =`, `agents =`, `plugins =`) while `/exit` returned it:
  `s |> peter()` then asked the egress question for an offline fake and lost the session's tools.
- Fix: the REPL no longer shuts the session down (net code removal); like an API or piped-in session
  it is the caller's and gets `session_shutdown` when collected or at unload (the jsonl frontend
  already worked so). R33's alternative, skipping the registry drop for reason "exit", would still
  stop the CLI child and forget the session's plugins and checkpoints at `/exit`, and shut down a
  session still running in the background.
- Green: PASS 350;
  `^(ext-events|ext-load|ext-registry|ext-plugins|session-live|session-registry-retention|
  cli-common|ckpt-rewind|gptr-gateway|skill-discover)$` PASS 2326; neighbours FAIL 0 SKIP 3
  PASS 8710. Lint clean.
- Deviations: D-253 (04 section 10.4 events table, 03 section 10.1 step 9; P14). Open: none.

### R23 - A trailing backslash continues a pasted line too
- Commit `eb839de7`. Red: `^console-repl$` FAIL 1 PASS 350: where a paste arrives whole (CRAN's R
  for macOS in a terminal), `repl_read_logical()` joined its lines before the continuation rule,
  which saw only the end of the joined text: a backslash ending the first or a middle line stayed in
  the message.
- Fix: every pasted line's trailing backslash continues it, as a typed one's does.
- Green: PASS 351; neighbours FAIL 0 SKIP 3 PASS 8711. Lint clean.
- Deviations: none. Open: none.

### R24 - RStudio's /help says tab skips $ and @ words
- Commit `9d68fdb2`. Red: `^console-commands$` FAIL 1 PASS 171: RStudio completes only syntactic
  names, so `!d$m` and `!x@y` complete nothing, while `/help` said "after ! or /, complete the
  word".
- Fix: in RStudio the key reads "after ! or / (not $ or @ words), complete the word"; the completer
  and the banner are unchanged, as the verdict says.
- Green: PASS 172; neighbours FAIL 0 SKIP 3 PASS 8731. Lint clean.
- Deviations: none. Open: none.
- Reverted by `e8f2728f` after the merge of P28's Tasks 88-92 (`bb87e279`): Task 91 gives a `$` or
  `@` word on a `!` line to RStudio's own completion, which completes it (S9: `!fuel$m` gives
  `!fuel$mpg`), so /help's "after ! or /, complete the word" holds again. Red with R24's code
  `^console-commands$` FAIL 1 PASS 171; green PASS 172.

### R25, R26 - The @files of a prompt fit their budget where the line says so
- Commit `528426f8`. Red: `^console-repl$` FAIL 8 PASS 352: the line under a prompt named each
  @file's 40 lines before the `user_files` budget (2,000 tokens) was applied at send time, which
  then dropped later files whole, or cut the first, unmarked.
- Fix: `repl_mentions()` fits the files in order as it builds their blocks (`lines_fit()`, one
  constant `console_files_budget`; `console_files_text()` deleted): a file cut to the room left is
  `truncated="true"` and said `first <n> lines`, one with no room is `omitted="true"` and said
  `not attached, over the size limit`. R26's sequential fill, not R25's equal split, which needs two
  passes and cuts files that would fit. `?peter` (man/peter.Rd) and the console vignette say the
  files of one prompt share about 2,000 tokens.
- Green: PASS 360; neighbours FAIL 0 SKIP 3 PASS 8720. Lint clean.
- Deviations: D-253. Open: none.

### R27 - A live re-ask does not resend an @file's head (not fixed)
- No commit. A `gptr_source(replay = "live")` re-ask sends the literal `@notes.md` without the
  console-only file head, which the transcript never records: a design gap, not a regression. The
  verdict's simplest option is no change (the sheet and `?peter` are accurate; the model still sees
  `@notes.md` and can read the file); its optional note (`# attached at the console: notes.md`)
  needs a call attribute, a site field and a parameter across console-repl.R, doc-locate.R,
  doc-replay.R and doc-formats.R and sends the same request.
- Deviations: none. Open: as above.

### R28, R34 - A ```r fence typed in RStudio's console runs as R
- Commit `b913a22d`. Red: `^console-repl$` FAIL 2 PASS 361: RStudio's insert_matching (on by
  default) pairs the third backtick, so a typed ```` ```r ```` reads ```` ```r` ````; its info
  string "r`" failed the R-fence test and the block went to the model as prompt text.
- Fix: backticks after the info string are ignored (the closer already accepts extra
  ones); ```` ```python` ```` stays prompt text. Both verifiers checked the regex in RStudio; the
  test feeds the lines RStudio produces.
- Green: PASS 363; `console-fences` green; neighbours FAIL 0 SKIP 3 PASS 8723. Lint clean.
- Deviations: none. Open: none.

### R30 - An interrupt right behind the first opens the pause menu
- Commit `35f15e96`. Red: `^console-interrupt$` FAIL 3 SKIP 1 PASS 132: RStudio delivers one Esc as
  two interrupts (it sets R's flag and sends a SIGINT whose handler sets it again); when R took the
  first before the second was set, the second fired inside `policy_menu()`, where only the policy's
  exiting handler is active, and the run aborted before `? Paused` showed (2 of 14 presses in the
  review).
- Fix: right after `pol$abort_runs = pol$runs` the menu runs
  `tryCatch(Sys.sleep(0.05), interrupt = function(e)
  NULL)`, so an interrupt in its first 50 ms is taken; a deliberate second press still aborts. The
  new test sends a real SIGINT from an active binding on `pol$runs` (skipped on CRAN, on Windows and
  where SIGINT is ignored).
- Green: PASS 135 (3 runs); with `CI=true` (INFRA-03, real SIGINTs to an interactive R) FAIL 0
  SKIP 0 PASS 153; neighbours with SIGINT at its default FAIL 0 SKIP 3 PASS 8710. Lint clean.
- Deviations: D-253 (04 section 7.14). Open: none (03 section 6.2's "a second Ctrl-C aborts" still
  holds for a person's press).

### R32 - gptr_init() does not ask about trust while trust holds
- Commit `30dbaa7b`. Red: `^gptr-config$` FAIL 4 PASS 609: `gptr_init()` asked the trust question
  and stored the answer unconditionally, so a trusted project was asked at every init and Enter's
  default No replaced the recorded TRUE; later runs then skipped the project's resources without a
  notice.
- Fix: `gptr_init()` asks only when `gptr_can_prompt()` and neither a recorded nor an in-process
  trust holds (`trust_holds(proj)`), as `trust_resolve()` does; a recorded No, an undecided project
  and a lapsed trust are asked as before. `?gptr_init` (R/gptr-config.R, man/gptr_init.Rd) says so;
  vignettes/configuration.Rmd describes a fresh project and stays.
- Green: PASS 613; the other `gptr_init()` callers' files PASS 2802; neighbours FAIL 0 SKIP 3
  PASS 8706. Lint clean.
- Deviations: D-253 (04 section 6.2). Open: none.

### Assembly
- The four groups' 24 commits were cherry-picked onto `516ec73c` (G3, G4, G1, G2) without conflicts;
  `document` changed nothing; lint of the 12 changed R and 10 test files is clean.
- Green at the branch head: neighbours FAIL 0 SKIP 5 PASS 8759 (the two extra skips are the SIGINT
  tests of `console-interrupt` and `console-render` in a process that ignores SIGINT;
  `^(console-interrupt|console-render)$` with SIGINT at its default FAIL 0 SKIP 1 PASS 853); the
  groups' other suites
  (`^(listing-print|utils-text|northstar|prompt-text|prompt-sections|bench-context|ckpt-rewind|gptr-sdk|gptr-gateway| eval-core|ext-events|ext-load|ext-registry|ext-plugins|session-live|session-registry-retention|cli-common| skill-discover|bridge-sh)$`)
  FAIL 0 SKIP 3 PASS 3749.
- Merged with P28's Tasks 88-92 (`ecfad58c`) in `bb87e279`: D-243 conflicted (both appended;
  Task 92's bullet is kept in order and D-253's amendment stays last); console-repl.R merged cleanly
  (Task 92's warning handler with R15's row end and R22's returned session); `e8f2728f` reverts R24
  (above). No test this branch added forces UTF-8 glyphs. Green at `e8f2728f` (NOT_CRAN=true
  CI=true, SIGINT at its default): neighbours FAIL 0 SKIP 2 PASS 8796, LC_ALL=C FAIL 0 SKIP 29
  PASS 8618 (INFRA-03 ran with its 18 expectations in both);
  `^(gptr-gateway|cli-claude|provider-fake|ckpt-rewind|listing-|utils-text|eval-core)` FAIL 0 SKIP 1
  PASS 1753, LC_ALL=C FAIL 0 SKIP 2 PASS 1744. Lint of the 33 R files either side changed is clean;
  `document` changed nothing; the four plan checks pass.
- Open: found in passing (R27's evidence, doc-locate.R): a console transcript with a `{name}` prompt
  cannot replay without a model, as `doc_console_site()` sets `args_hash = NULL` and the block reads
  stale under `GPTR_REPLAY=replay`; to triage.

## Task CI-94 - A paste on the polling beat is timed by its last key's read (2026-10-25, #81)
- Red: R-CMD-check run 40194786942 (PR #79 at df37cabe), job 121173185576 (macos-latest release)
  failed "a terminal: a paste during a run is one draft; Enter sends it as one steer (review)"
  (`test-console-typing.R:1219`, 1220, 1223 and 1227): no `› a b c` draft, `queued` seen 6 times,
  no `REQ 1 [a/b/c]`, two requests.
- Rate: in the 10 R-CMD-check runs that held the block before the fix (since 58874963), macos-latest
  (release) failed it in 3 of 8 finished jobs, all on 2026-10-25 (121172988616, push to main at
  b90a0040; 121173185576; 121181176010, PR at a61d1119), always these four lines; it passed in runs
  40180028016 and 40190321933, the latter on a tree identical to the first failure's, and in the
  three most recent. It never failed on an Ubuntu lane.
- Cause (the product): `console_keys()` timed a batch when `console_typed_chars()` returned, 50 ms
  after its last chunk, since the reader waits that long for more keys. A batch read on the beat
  measured 0.102-0.111 s, its last key's read 0.052-0.058 s, so the count term (more than
  `1 + gap / 0.03` keys) took every paste of four keys or fewer as typed, its head sent at once
  as a steer, and the test's five-key paste once the beat ran about 15 ms late. Traced at
  origin/main (fd-0 chunks, the gap both ways, each send): the five keys always came in one read;
  20 ms injected before each read failed the block 3 of 3 with CI's four lines (gap 0.137-0.139 s,
  steer `a\nb`, draft `c`); the four-key paste `a\rbc` split 3 of 3 with nothing injected.
- Fix: (1) 6820374d, test: the pty block pastes `one\rtwo\rthree`, more keys than a person types
  in 0.2 s, so only the beat's bound decides. (2) 12d7d590: the reader records its last chunk's
  time (`rd$read_at`) and the rule measures to it. A unit test drives the real reader on a fake
  fd and clock: a four-key paste on the beat stays one draft; keys typed 40 ms apart, read as they
  come, stay typed (Task 32). The fd-0 reader test's child, a deparsed copy of the reader, defines
  `reactor_now()` too.
- Green: the unit block FAIL 2 on main at 5ee45a04 (steer `a`, draft `bc`), PASS 3 after; a reader
  timed by its first chunk fails its typed half. Traced with the fix: the five-key paste stays one
  draft with 20-50 ms injected (gap 0.073-0.108 s) and splits from 60 ms (0.122 s); thirteen keys
  hold at 100 ms (0.163 s) and at 140 ms in 1 of 2 (0.194 s; the other read 0.204 s, past the
  bound); keys typed 30 and 40 ms apart stay typed (steer `red car`, draft `draft`). At 12d7d590
  (`CI=true` `NOT_CRAN=true`, SIGINT at its default) the block PASS 9 in 30 of 30 runs (load
  5.5-8.9, 16 cores), 10 of 10 under 32 busy loops (load 30-281) and 3 of 3 under `LC_ALL=C`.
  Neighbours
  (`^(console-|gptr-config|agent-run|agent-loop|agent-dispatch|session-object|arch-layers)`), which
  before the child's `reactor_now()` failed the fd-0 reader test (FAIL 4): `[ FAIL 0 | WARN 0 | SKIP
  0 | PASS 5817 ]` in UTF-8, `[ FAIL 0 | WARN 0 | SKIP 27 | PASS 5639 ]` under `LC_ALL=C` (each skip
  needs a UTF-8 locale). Lint clean (3 files); `document()` changes nothing.
- Deviations: none; IC-76's rule is unchanged, the reader now times a batch as it states. Open:
  none.

## Task CI-95 - The security blocks of 500 ms or more on Windows skip on CRAN (2026-10-25, #81)
- Why: CI-93 put the 12 blocks its trim had skipped in the security files back on CRAN (8c0edb03),
  judged by Windows timing runs 39555362618 and 39559882743 (2026-10-21), from before two of those
  blocks changed or existed (perm-classify's plan-mode allowlist grew since; perm-rules' `sh:` block
  came on 2026-10-23). Its verifier found that evidence weak for D-240's rule there, which skips
  only blocks of 500 ms or more on Windows.
- Evidence: run 40206216160 on claude/cran-timing-windows (811d465: main f8c48802 plus a workflow,
  never merged, that times each block of the six security files in CRAN mode on windows-latest,
  R-devel and R-release, two jobs each). In each job 160 blocks ran, 38 skipped, none failed. Four
  take 500 ms or more in the mean of a version's two jobs (R-devel/R-release): perm-rules "sh: and
  category: rules see a program given by its path" 1820/1755 ms, perm-plan "a readonly session
  keeps read and r outside plan mode (D-251)" 1120/1040, perm-classify "the plan-mode allowlist
  admits only known read-only calls (IC-54)" 625/595, perm-rules "rule_suggest() covers exactly the
  flagged calls, never level 4 or control (7.11)" 535/510. The largest kept, auth-redact "a short
  stream equals whole-text redaction (CRAN-sized)", takes 440/400.
- Change (7cfd4252): the four start with `skip_on_cran()`. Three are of CI-93's 12; perm-plan's
  block (02bead73, 2026-10-23) was never skipped. The other 156 security blocks that ran there stay
  on CRAN.
- Measured at the head (macOS, 16 cores, load 9-18; the CRAN list against the installed tarball from
  a copy of tests/ with no source tree above it, `NOT_CRAN`, `CI` and `GITHUB_ACTIONS` unset, 3
  alternating triples in UTF-8): before the trim (ecfad58c) 21.7-22.1 s (PASS 4146 SKIP 1550), main
  (f8c48802) 14.2-14.4 s (PASS 2589 SKIP 896), the head 13.7-13.8 s (PASS 2501 SKIP 900), FAIL 0 in
  each: 37% less than before the trim (main 35%), 0.5 s less than main. Under `LC_ALL=C` main 14.3 s
  (PASS 2575 SKIP 900 WARN 1) and the head 13.4 s (PASS 2487 SKIP 904 WARN 1), the warning as on
  main. covr over the CRAN list: lines 46.4% before the trim, 39.9% at main, 39.7% at the head;
  functions 2,441, 2,195 and 2,185 of 4,138, the 10 that lose their last CRAN test in ext-registry,
  gptr-capture, gptr-gateway, prompt-sections and session-object; R files reached 115 of 125 each
  time, each keeping at least 26.7% of its CRAN-covered functions (`console-input.R`, 4 of 15, the
  least), so CI-93's guard holds. Block skips in the 35 listed files: 841 to 845. The CRAN-mode
  `R CMD check --as-cran` (cran-mode's variables, both manuals): Status OK in 136 s, with
  `Running 'testthat.R' [13s/14s]` as at main, so cran-comments.md keeps its 14 s.
- Tests: the six security files with `NOT_CRAN=true`, in UTF-8 and under `LC_ALL=C`: PASS 2142
  SKIP 1 each; lint of the three touched files clean.
- Deviations: D-240 (amended in place). Open: a block near 500 ms can cross it between runs:
  `rule_suggest()`'s block took at most 480 ms in CI-93's runs and 510-535 ms here.

## Task CI-96 - The macOS row has time for the whole suite (2026-10-25, #81)
- Red: main's R-CMD-check run 40203827918 at f8c48802 (PR #79 merged), job 121200423672
  (macos-latest release), was cancelled at its 45-minute limit 42 minutes into R CMD check
  ("The job has exceeded the maximum execution time of 45m0s"); every other job of the run passed.
- Measured (macos-latest release, R-CMD-check.yaml, job start to end): the 19 finished jobs from
  2026-10-21 to 2026-10-24 took 25-37 minutes; on 2026-10-25, after P28 (#78) added its pty console
  tests, which macOS runs serially, the 7 finished jobs took 36.5-43.6 minutes and the one above
  reached the limit at 45.3.
- Fix: the macOS row of the matrix gets `minutes: 60`, a third over the slowest finished job; the
  other rows keep 45 and Ubuntu R-devel 120. test-zzz.R's time-limit test (CI-19) pins it.
- Tests: `^zzz$` FAIL 1 before the change (test-zzz.R:320), FAIL 0 PASS 149 after; lint clean.
- Deviations: none. Open: the macOS row's time grows with the serial pty tests; running them in
  two testthat workers, as the Linux rows do, would halve it but loads the runner the pty tests
  time against.

## Task CI-97 - An HTTP stream checks the abort before each unit (2026-10-25, #82)
- Red: main 5ee45a04, R-CMD-check run 40208376485, job 121214117745 (ubuntu-latest release, two
  testthat workers) failed `test-provider-anthropic.R:851` in "end to end on the mock server:
  streaming, retry and abort (skip on CRAN)": the aborted message held `tok01 tok02 tok03 tok04 `,
  not `tok01 tok02 `; its `stop_reason` `aborted` (850) and last `error` event (852) passed.
- Rate: since the block came (ea14e6f0, 2026-10-04) it ran in 2,817 jobs of 344 runs
  (R-CMD-check.yaml 280, Windows-check.yaml 64; the log of every failed or cancelled job that
  reached its check read, 1,242) and failed 3 times, 0.11% (95% CI 0.04-0.31%), always there:
  job 112532681385 (ubuntu-latest oldrel-1, serial, 2026-10-06) and 115430722254 (macos-latest
  release, 2026-10-13) kept 1 token after the abort, this job 2. Linux 2/1985, macOS 1/286,
  Windows 0/546; on the ubuntu rows serial 1/707, two workers 1/437. Evidence (local, not
  committed): the job listings and stripped logs.
- Cause (P05's glue, not the test): `stream_http()` read `opts$signal$aborted` only in its watch
  task, which `reactor_step()` runs after `reactor_io()` has delivered every chunk curl read in
  that iteration, and `on_bytes()` pushed every unit checking only `st$finished`. Tokens come every
  0.2 s; a reader 0.4 s behind got tok02 to tok04 in one iteration, `mock_stream()`'s `emit()` set
  the flag on tok02, tok03 and tok04 still reached the normaliser and `emit()`, and the watch then
  ended the stream `aborted` with them in the partial. A body ending in that iteration lost the
  abort (`stop`). Runs were not affected: `run_abort()` closes the request and records `run$acc`
  itself, and `run_on_event()` drops later events.
- Reproduced at 5ee45a04 with a stall traced in before the reader's next `curl::multi_run()` after
  tok01 (scratch helper, not committed): 0.7 s FAIL 5 of 5 with the CI text, 0.5 s 3 of 3 with
  `tok01 tok02 tok03 `, the trace showing tok03 and tok04 pushed with the flag set. Without a
  stall it never failed on a 16-core Mac (plain 0/40, twice the cores busy 0/20, a second test
  worker 0/15, both 0/15, the mock server stopped 0.6 s 0/10; longest reader gap 0.122 s).
- Fix (1ad5d7ce): `on_bytes()` (on entry and before each unit) and `on_done()` run `stream_over()`
  in place of `st$finished`, as `process_jsonl`'s lines and exit do (D-018): the first input after
  the flag aborts the stream and cancels its transfer, so the reactor drops what it still holds.
  The block is unchanged.
- Test (9aa1e3f3): test-provider-registry.R "an abort flag set during an event ends the stream
  before the next unit or the end" (the flag set by `emit()` on the first delta; two deltas in
  one chunk, then one delta and the body's end): at 5ee45a04 FAIL 6 PASS 1 (the second delta
  emitted; `done` with `stop` at the end), with the fix PASS 7; without the unit check or the end
  check it fails again.
- Green (`NOT_CRAN=true`, the block alone): the red stalls PASS 12 each, 0.7 s 5 of 5, 0.5 s 5 of
  5, 3 s (the rest of the stream and its end in one iteration) 3 of 3, the trace aborting at
  tok03's chunk; 30 of 30 in UTF-8; 10 of 10 under 32 busy loops (16 cores, load 128 at the end);
  3 of 3 under `LC_ALL=C LANG=C`. `^(provider-|http-|reactor|agent-run|agent-loop|stream)` (19
  files) PASS 4529 SKIP 2 FAIL 0 in UTF-8 and under `LC_ALL=C`, the skips Windows-only; lint
  clean; `document()` no diff.
- Deviations: D-254. Open: inside one unit (an SSE event, or a whole chunk for `stream = "raw"`,
  Bedrock) the normaliser's events still follow each other after the flag; a transfer failure
  delivered in the iteration that set it ends `error`, not `aborted` (`on_fail()` checks only
  `st$finished`).

## Task CI-98 - The writer prototype reports an early writer exit (2026-10-25, #84)
- Red: PR #83 at 6e3bad83 (R/ and tests/ as on main b58d1e1b, whose Windows-check run 40234878533
  passed), Windows-check run 40236997275, job 121300574990 (windows-latest oldrel-4, shard 1/4),
  failed "owned writer prototype cancels a queued 4 MB write without a late exit"
  (`test-proc-writer-prototype.R:32`): `writer-cancel  spawn /ready /queued /cancel` not complete,
  no guard, 21.7 s of the case's 30; its witness held no result and a case failure of class
  `gptr_error_invalid_argument`. Attempt 2 (job 121307986374) passed.
- Rate: the block ran in 405 Windows jobs (R-CMD-check.yaml's whole-suite rows and
  Windows-check.yaml's shard 1/4, since 2026-10-12). Its 40 failures in the shared suite
  (2026-10-13 to 10-14) were the observer's resource bound, gone when a351c85a gave the native
  files fresh R sessions. Since then it failed 1 of 339 (0.29%, 95% CI 0.05-1.7%; oldrel-4 1/169,
  release 0/170), this job. The binary block failed the same way in job 118948395161 (release,
  2026-10-20): phases spawn/ready/queued, `gptr_error_invalid_argument`, 2.3 s. That is 2 of the
  1,356 writer cases in those jobs. Evidence (local, not committed): the job listings and logs.
- Cause (the test transport, not the product): `wp_child_case()` started its poll timer id as
  NULL, and only the last line of `poll_ack()` set it. When the first `poll_ack()`, 1 ms after the
  input was queued, found the writer dead with nothing accepted, it took its `writer_failed`
  branch and scheduled no timer, and `reactor_cancel(NULL)` raised (ids are a character vector):
  in the cancel case inside the cancel callback, before `st$cancelled`, so the pump ran its 20 s
  and the cancel after the pump raised again; in the other cases after the pump. The case child died
  without a result. The failing case left 11 directories, as a writer that stops with an R error
  or an interrupt does (12 when it is killed), so the writer ended through R's own exit before the
  input existed; its stderr went with the case root.
- Reproduced: on Windows, run 40245496947 (claude/ci98-writer-cancel-measure, main with traces,
  never merged) stopped the writer after its ready file: an R error and a processx interrupt (6
  times per lane each) and a kill (3) all gave CI's line in 21.3-22.1 s, the error and the
  interrupt with 11 directories (3 of 24 with 14), the kill with 12. On macOS at b33fcabb, with
  `stop()` after the ready file: the cancel block FAIL with CI's text in 22.4 s, the timeout case
  the binary job's signature in 2.7 s; duplex and binary reported `writer_failed`, their writer
  still alive at the first poll. The natural exit never came: 0 in 943 runs of native-07 through
  R CMD BATCH (release 519, oldrel-4 424; 3,772 cases, run 40245496947) and 0 in 2,811 cancel
  cases (run 40240516501).
- Fix (test only, 12dfc6d3): the timer id starts as `character()`, which `reactor_cancel()` takes
  as no id, so the case completes and the test fails on `writer_failed`. The result keeps the last
  20 lines of the writer's stderr, which tell an R error (`Error in ...`) from an interrupt (an
  empty line, then `Execution halted`); both exit with status 1.
- Green: with the injected stop every case completes and reports `writer_failed` with the
  writer's `Error in ...: injected writer exit after ready`: on macOS in 2.4-4.8 s, the cancel
  block failing only on `writer_failed` (line 32); on Windows (run 40249408080, the fix plus the
  injection, never merged) 3 runs of native-07 through R CMD BATCH per lane, 12 of 12 cases each in
  1.4-3.7 s (release) and 1.8-3.9 s (oldrel-4). Without it: windows-by-file run 40249276416
  (release) PASS 92 FAIL 0 in 21.1 s; native-07 through R CMD BATCH for 25 minutes, release 88 of
  88 and oldrel-4 113 of 113 runs PASS (804 cases, the cancel case at most 4.7 s, the writer's
  stderr always empty); on macOS the file 5 of 5 FAIL 0 and `^proc-` `[ FAIL 0 | WARN 0 | SKIP 11
  | PASS 2375 ]` (each skip Windows only). Lint: the helper's 19 `object_usage_linter` notes, as on
  main (testthat and bp_run() are outside a lone helper); R/ is unchanged.
- Deviations: none. Open: why the writer exits early (2 of 1,356 Windows writer cases in CI, none
  in 6,583 measured); a recurrence now fails on `writer_failed` in about 5 s, the writer's stderr
  in the witness.

## Task CI-102 - Installs from GitHub work; the README names two session errors (2026-10-26, #PR)
- Report: on a Mac with R 4.4 (arm64), in one R session, `pak::pak("Broccolito/gptr")` stopped in
  pak's `remote()` with `Subprocess is busy or cannot start`, then `library(devtools); load_all()`
  in a clone stopped in `ns_s3_methods(package)` with
  `cannot open file '<lib>/gptr/R/gptr.rdb': No such file or directory`, `<lib>` the system library
  `/Library/Frameworks/R.framework/Versions/4.4-arm64/Resources/library`.
- Measured: runs 40291788064 and 40292515157 on claude/ci102-install-measure (only a workflow,
  never merged, deleted after), each case a fresh job installing main 7e23ebd3 with the job's token
  as `GITHUB_PAT`; macos-latest R 4.4.3 and R 4.6.1, ubuntu-latest and windows-latest R 4.6.1;
  pak 0.11.1, remotes 2.5.0, devtools 2.5.2, pkgload 1.5.3. `pak::pak()` after a fresh pak took
  42-99 s, `remotes::install_github()` 40-62 s, `devtools::install_github()` with remotes installed
  36-58 s, each followed by `library(gptr)` 1.0.0 at 7e23ebd3 with no load error: 12 of 12. A
  clone, its Imports and `devtools::load_all()` (1.9-2.6 s): 4 of 4 (the ubuntu job's attempt 1
  hung 14 minutes in setup-r and was cancelled). pak fetched the 11.57 MB tarball, packaged it in
  1.9-16.8 s and built it in 19.1-37.1 s. Locally (R 4.6.1, temporary libraries and user
  directories) `pak::pak("Broccolito/gptr", lib = <tmp>)` took 31.2 s and `load_all()` in a clone
  1.5 s.
- Replicated, both errors word for word (run 40291788064, job "one session", macos-latest R 4.4.3,
  the system library, each scenario one `Rscript` session): CRAN's gptr 0.7.0, `library(gptr)`,
  `remove.packages("gptr")`, `library(devtools); load_all()` gave the report's `load_all()` error;
  from a directory whose `.Rprofile` sleeps 7 s, `pak::pak("Broccolito/gptr")` gave the report's
  pak error after 5.4 s, and the same call under `PKG_SUBPROCESS_TIMEOUT=60000` installed gptr.
  The likely sequence, CRAN's 0.7.0, `library(gptr)`, `pak::pak("Broccolito/gptr")` (62.6 s, pak
  warning that gptr is loaded) and `load_all()`, installs 1.0.0, and `load_all()` then stops in
  `ns_s3_methods(package)` with `lazy-load database '<lib>/gptr/R/gptr.rdb' is corrupt`. With
  1.0.0 loaded, `pak::pak()` (9.1 s) and `load_all()` (3.6 s) pass. Locally the removal, the slow
  profile and the likely sequence gave the same results, and a pak install interrupted 20 s in,
  while building, kept the old copy; the next `pak::pak()` installed it with no error (the runner's
  two interrupts came after pak, building from its cache, had finished). pak's first subprocess
  call took 0.9-1.1 s in three fresh sessions on the runner and 1.2 s locally.
- Cause (the session, not the repository): pak 0.11.1's `remote()` runs pak's work in a background
  R process (a callr `r_session`, which sources the working directory's `.Rprofile`), restarts it
  when it is busy or dead, and waits `PKG_SUBPROCESS_TIMEOUT` (5000 ms) for it to be ready; one
  still starting then, or dead while starting, gives the message, so anything that slows or stops
  a new R process on that Mac does it. gptr never runs in that process. pkgload's `unload()` reads
  the loaded namespace's `.__S3MethodsTable__.` through its lazy-load promise: "cannot open file"
  means the copy that session loaded was removed (by `remove.packages()`, or by an install that
  removed it: on macOS pkgdepends deletes the old directory, then moves the new one in), "is
  corrupt" that a new version replaced it. Restarting R before `load_all()` avoids either.
- Repository checked: DESCRIPTION has no `Remotes` or `Config/*` field for installers, and neither
  pak nor remotes builds the vignettes `VignetteBuilder` names; `.Rbuildignore` keeps `dev/` out of
  the package; no path is longer than 85 characters. Of the load-time expressions only
  `proc_sweep()` touches processes, and it signals only processes that carry the `GPTR_PROC_`
  marker of a gptr parent that is gone, or a recorded child at its exact creation time; pak's and
  callr's subprocesses carry no marker. Locally, four stale records naming pak's live subprocess
  and a callr `r_session` (creation time unknown or 5 s off, parent gone) were deleted by the sweep
  of `library(gptr)`, which killed neither; pak worked after.
- Also found: devtools 2.5.0 deprecated `devtools::install_github()` and `install_deps()` for
  `pak::pak()` and no longer installs remotes: without it both stop with
  `The package "remotes" is required.` (run 40291788064, 8 of 8 jobs; run 40292515157 installs
  remotes first).
- Fix (README.Rmd and README.md, the latter rendered by `dev/release/precompute.R --readme`, its
  unrelated session line restored): one sentence after the install chunk says that if pak stops
  with `Subprocess is busy or cannot start`, or a later call reports a missing or corrupt
  `gptr.rdb`, restart R and install again before loading gptr, or use
  `remotes::install_github("Broccolito/gptr")`.
- Green: `dev/release/check-files.R readme` 0 problems; `dev/release/tests` filtered to
  readme|precompute|docs PASS 81; `^proc-supervise$` (the sweep's tests) with `NOT_CRAN=true` PASS
  151 FAIL 0 in UTF-8 and under `LC_ALL=C LANG=C`; R/ and tests/ unchanged.
- Deviations: none. Open: what slowed or stopped pak's subprocess on the reporting Mac, and what
  removed its loaded copy of gptr before `load_all()`, is not in the report.

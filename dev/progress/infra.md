# Infrastructure - hosted CI, tooling and Linux portability

Status: hosted CI rounds CI-1..CI-6 committed (`118f78b`..`38db483`); M0 hosted gate: run 37351073211 on `2823b07`
green on all 13 jobs. A hosted run validates only its own commit; P03/P04 acceptance recorded (M0-ACC); M0 tag
pending (maintainer).

## Workflow and hosted runs
- `.github/workflows/R-CMD-check.yaml` (P01 Task 21, `22c9ee6`) runs on push to `main`; concurrency (`d051686`,
  `0398aee`): one run per ref, running checks finish, only the newest push queues. R CMD check fails on warnings
  (`error-on: "warning"`) and when `00check.log` has no `Status:` line; limits: check jobs 45 min (Windows release 75,
  R-devel 120), others 30. Windows release first streams the suite file by file (`dev/ci/test-by-file.R`, non-gating,
  at most 30 min).
- Logs: `gh run view <run> --json jobs`; `gh api --allow-escape-sequences repos/Broccolito/gptr/actions/jobs/<job-id>/logs`.

| Run (commit) | Result | Fixed by |
|---|---|---|
| 37165877166 (`eea1e36`, P01 snapshot) | installed-test IRkernel mock error; Windows CRLF completion markers; oldrel-4 `str(big)` control made no copy; connections pass | `d4aabfb`, D-009 `285deec` (progress/P01.md) |
| 37167848633 (`55ec31d`) | Ubuntu release, LC_ALL=C, oldrel-1: FAIL 11 (dead-PID lock reclaim, `kill_all()` markers, orphan sweep); Windows release FAIL 8 (CRLF, `Rterm.exe` grandchild, async kill, finalizer mock) | `c8470f7` (Linux liveness); CI-2 |
| 37169255693 (`8e8d8e0`), 37170545611 (`a2ba302`) | `test-aaa-state.R:127-128` on every Ubuntu job, macOS, no-Suggests, LC_ALL=C, connections; INFRA-01 six-stream wall (macOS 2.57 s, connections 2.483 / 2.553 s) and macOS gap `:557`; Windows oldrel-4 false success (check aborted at start); Windows release hung in tests (68 min; over 2 h without a limit); connection gate stopped at the first failure; `file_test` NOTE | CI-1, CI-2 |
| 37176542781 (`118f78b`), 37193999181 (`489eb0b`), 37195622025 (`95dd9b8`, partial) | `test-provider-registry.R:970` (test race) on Ubuntu release, devel, oldrel-1, oldrel-4, no-Suggests, LC_ALL=C and connections; Windows `test-auth-redact.R:934` (backslash path in a mock); Windows release stream INFRA-23 1.060 s and `Rscript*` NOTE (open). Confirms CI-2: Windows hang gone (stream 611 s, check tests 498 s), proc tests pass on Windows; macOS passes INFRA-01 | CI-3 |
| 37210924368 (`51ba767`), 37213342336 (`b40b4d1`) | WARNING missing `gptr::gptr`, `gptr::gptr_return` on all 9 check jobs (Ubuntu tests otherwise green: confirms CI-3); R 4.2.3 invalid UTF-8 ran as `<xx>` text (`test-eval-core.R:512-514`, oldrel-4); Windows `test-tool-diff.R` (runner `core.autocrlf=true`) and PNG test CRLF; macOS INFRA-01 six-stream 2.486 s | CI-4 |
| 37262066260 (`0398aee`), 37266727707 (`bdf7c18`), 37269169488 (`01e13a5`, partial) | R 4.6.1, devel, macOS, connections: `test-tool-search.R:223` (`basename()` inside `tools::file_ext()`); Windows: CRLF checkout (`test-doc-formats.R` x15, `test-perm-classify.R:19`), `~` with a backslash home (`test-ext-plugins.R:481`, `test-skill-discover.R:295-297`), C-locale names (`test-tool-search.R:219-229`), finalizer reaching the `ps_kill` mock (`test-proc-supervise.R:306`); Windows oldrel-4 INFRA-23 1.020 s. Ubuntu oldrel-4 passes: confirms CI-4 | CI-5 |
| 37303873005 (`602ba53`), 37313611932 (`e214a61`), 37317629994 (`0c37a8d`), 37329796830 (`718659d`) | every R 4.6.1 and devel job: `test-copy-gateway.R:108` (G3 copy of `big`); both Windows: `test-cli-codex.R:477-490` (links); Windows release cancelled at 45 min (stream timed out in quadratic `pd_calls()`); `test-proc-supervise.R:89` (oldrel-1, connections); Windows INFRA-23 5 of 9, INFRA-01 | CI-6 |
| 37351073211 (`2823b07`) | green, 13/13: macOS; Windows release, oldrel-4; Ubuntu devel, release, oldrel-1, oldrel-4; no-Suggests; LC_ALL=C; copy-safety release, devel; connections; token bench. Confirms CI-6 | - |
| 37390651676 (`31118fb`, docs only) | Windows oldrel-4 only: INFRA-23 1.040 s (`test-http-sse.R:126`); 12 jobs green | CI-7 |
| 37503348214 (`fba1a15`) | Ubuntu oldrel-4 only: `test-cli-claude.R:774` (no `interrupt` row), Chrome detritus NOTE; 12 jobs green | CI-14 |
| 37566867447 (`0a23d95`) | Ubuntu release, devel, oldrel-1, oldrel-4, macOS (`R_KEEP_PKG_SOURCE=yes`): `test-secrets-e2e.R:237,240`, worker spec 18.2-18.3 MB, 6062 key matches in it and callr's function file; LC_ALL=C (no keep-source) green; Windows, connections cancelled | CI-17 |
| 37583355970 (`2e8fd09`) | token benchmark, first run of its `dev/bench` test step (`d1691d4`): `test-token-gates.R:145-147`, `run.R --check` exits 0 with the ns02 prefix baseline scaled by 0.97 (prefix 2287 hosted, 2409 on macOS: the machine's `<r_env>`) | CI-18 |
| 37540280557 (`f6aa1c8`) to 37583355970 (`2e8fd09`) | connections (30 min) and both Windows jobs (45 and 75 min) cancelled at their timeouts in every run; on `2e8fd09` every Ubuntu and macOS check job is green (CI-17 confirmed) | CI-19 |
| 37588313491 (`0292aad`) | connections completes (suite 2331 s; CI-19 confirmed for it): FAIL 3 `test-console-interrupt.R:467,469,470` (INFRA-03 step 1: no pause menu, status line or tokens; steps 2-3 pass), WARN 2 `test-auth-secrets.R:423,505` (keyring's "Selecting 'env' backend"); both Windows jobs cancelled at 120 min inside `checking tests`; Ubuntu, macOS, copy-safety and token benchmark green | CI-20 (FAIL 3); WARN 2 and Windows open |

## Task CI-1 - Cross-platform hosted CI corrections (2026-10-03, `118f78b`)
- Fixed: P01's service test isolated from undeclared built-ins (D-016 item 2); INFRA-01 measured on the mock's clock
  (`log_writes`, `writes()`; item 1); Windows oldrel-4 check env, `Status:` guard, job limits (item 3); the connection
  gate runs the whole suite, then compares the table (`run_gate()`, `suite_failures()`; D-006); `utils::file_test()` NOTE.
- Red: aaa-state FAIL 2 (hosted `:127-128`), zzz FAIL 11 (no limits or guard), auth-redact FAIL 1 (`file_test`
  global), check-connections FAIL 6. Green: aaa-state PASS 42, http-reactor PASS 205 (x3), `^http-|^provider-fake$`
  PASS 909, `zzz|auth-redact` PASS 483, check-connections PASS 20; full suite and connection gate SKIP 1 PASS 5960
  (keyring skip), table unchanged. Lint clean. Neighbours: `ext-|lint|arch|utils-options` PASS 1418.
- Reviews: r1 4 findings (0/3/1) -> D-016 items 1-2. Deviations: D-016. Open: macOS INFRA-01 gap (Open hosted items).

## Task CI-2 - Windows process portability and the hung Windows test run (2026-10-03, `90a43f5`)
- Fixed: CRLF echo redaction and the LF form of a CRLF secret (D-019 item 1); `Rterm.exe` grandchild in tree tests
  (item 2); bounded wait for the handles a kill signalled (`proc_kill_signalled()`, item 3); finalizer-safe
  `ps_kill_tree` mock (item 4); byte fixtures write one CRLF on every OS. The hang: processx writes stdin with a
  blocking `WriteFile()` on Windows (4 MB echo deadlock); two stdin tests skip there (item 5). New stream step.
- Red: proc FAIL 5 (CRLF value echoed, async kill kept the marker), zzz FAIL 7 (no stream step); the plan's finalizer
  assertion fails on a collected processx process. Green: `^proc|^zzz$` PASS 381, `^auth` SKIP 1 PASS 1005, `^http`
  PASS 698; full suite SKIP 1 PASS 6289. Lint clean.
- Reviews: r1 4 findings (0/1/1, 2 nits), r2 1 (0/1/0) -> D-019 items 1, 3. Deviations: D-019. Open: D-019 item 5.

## Task CI-3 - Remaining hosted failures on Ubuntu, LC_ALL=C and Windows (2026-10-04, `2246628`)
- Fixed (tests only): the overload test pumps, bounded at 30 s, until P04 forgets the transfer (curl read the chunked
  terminator after `done`), plus a test that holds curl's `done` event to force that order on any OS; both scrub
  mocks compare `path_key()` (IC-51) and the lock test counts its matches (`test-auth-redact.R:846`, `:934`).
- Red: provider-registry FAIL 1 (new test in the old form, hosted message); a simulated Windows path gives the hosted
  scrub message. Green: provider-registry PASS 725, auth-redact PASS 405, both under `LC_ALL=C` PASS 1130; a
  never-forget negative control fails both pumps; full suite SKIP 10 PASS 8835. Lint clean. Neighbours:
  `^(provider-|auth-|http-reactor$)` SKIP 7 PASS 3672.
- Reviews: none recorded. Deviations: none. Open: INFRA-23 on Windows, `Rscript*` NOTE (Open hosted items).

## Task CI-4 - Hosted regressions after the P06/P09/P10 waves (2026-10-04, `9a3b3ad`)
- Fixed: `eval_guard_ns_call()` builds `gptr::<name>` with `call()` and a zzz test requires every `gptr::` call to
  name an export; `as_utf8()` keeps invalid UTF-8 bytes on every R (`native_to_utf8()`, D-063 item 1); tool-diff
  writes LF patches and applies with `core.autocrlf=false` (its emulated-runner control needs git >= 2.31); the PNG
  test reads CRLF as LF; the six-stream INFRA-01 wall nets out the mock's lateness (`infra01_six()`, D-063 item 2).
- Red: local R CMD check of `3cda7b2` 1 WARNING (hosted); utils-encoding|zzz FAIL 3; tool-diff under
  `core.autocrlf=true` FAIL 59. Green: `^(utils-encoding|zzz|eval-guard|eval-core|tool-diff|http-reactor)$` SKIP 1
  PASS 1266, `LC_ALL=C` SKIP 4 PASS 1035; full suite SKIP 11 PASS 11669 (+20); R CMD check `Status: OK`, SKIP 21
  PASS 11599. Lint clean. Neighbours: 12 neighbour files SKIP 1 PASS 1476, `lint-rules|arch-layers` PASS 18.
- Reviews: r1 1 finding (0/0/1, git < 2.31) -> fixed. Deviations: D-063. Open: two one-off P04 failures (below).

## Task CI-5 - Hosted regressions after the P07-P20 waves (2026-10-04, `29b85f2`)
- Fixed: `path_has_ext()`, `path_ext()`, `path_sans_ext()` replace `tools::file_ext()`/`file_path_sans_ext()` in
  tool-search and tool-read (D-111 item 1); `path_norm()` expands `~` first (item 2); `.gitattributes` `* -text`
  (item 3); `helper-locale.R` (`local_name_locale()`, item 4; `local_r46_file_ext()`); the `ps_kill` mock forwards
  foreign calls and checks finalizer graces with `%in%`.
- Red: focused FAIL 10 (hosted message through the R 4.6 emulation); `core.autocrlf=true` clone FAIL 16; backslash
  home FAIL 4; proc-supervise FAIL 1. Green: `^(proc-|utils-paths$|tool-search$|tool-read$|zzz$)` PASS 745, `LC_ALL=C`
  PASS 358, autocrlf clone PASS 344, backslash home PASS 385; R CMD check 1 NOTE (future timestamps), SKIP 18
  PASS 16446. Lint clean. Neighbours: `^(lint-rules|arch-layers|tool-|utils-|ext-plugins|skill-)` PASS 2062.
- Reviews: r1 2 findings (1/0/0, 1 nit) -> fixed; D-111 item 1. Deviations: D-111. Open: `tools::file_ext()` (below).

## Task CI-6 - Hosted regressions after the gateway, documents and System 1 waves (2026-10-05, `38db483`)
- Fixed: `$.gptr_ctx` calls an active member's function, since R 4.6 pins a frame read through a binding (D-137 item
  1); a dangling Codex control link is `unreadable` without a warning on Windows (item 2); `pd_calls()` vectorised
  (same output on 95 files, 152.2 s -> 5.4 s); Windows release limit 75 min, stream 30;
  `test-proc-supervise.R:89` names its survivors.
- Red: ext-api|zzz FAIL 5 (binding read, limits); the R 4.6 emulation gives the hosted G3 message; simulated Windows
  links: cli-codex FAIL 3. Green: `^(ext-api|zzz|cli-codex|arch-layers|lint-rules|proc-supervise)$` PASS 711 (31 s);
  emulation 4/4; link simulation SKIP 1 PASS 223; R CMD check 1 NOTE (future timestamps), SKIP 28 PASS 22054. Lint
  clean. Neighbours: `^(ext-|agent-|env-|prompt-|gptr-|session-|cli-|copy-|s1-|eval-)` SKIP 6 PASS 8824.
- Reviews: r1 2 findings (0/0/1, 1 nit; documentation) -> fixed. Deviations: D-137 (committed with `ff3a558`).
  Open: Open hosted items.

## Task CI-7 - INFRA-23 measures the best of three runs on shared runners (2026-10-05)
- Red: not applicable (hosted flake, run 37390651676); a throwaway slowed `json_decode()` mock fails the new
  assertion (best of three 3.3 s), its unslowed control passes. Green: http-sse PASS 70 (unchanged; local runs
  0.39-0.40 s). Lint clean. Neighbours: `http-|proc-` PASS 990 green.
- Reviews: none recorded. Deviations: D-011 (Rule line edited in place). Open: hosted Windows confirmation.

## Task M0-ACC - Record the P03 and P04 plan acceptance tables (2026-10-05)
- Red: not applicable (records only). Green: every P03 and P04 row filter FAIL 0, WARN 0 on the working tree
  (`auth` SKIP 1 PASS 1068, `http|proc` PASS 990, `lint|arch` PASS 143); `http-sse|http-reactor` PASS 273 with
  INFRA-01 latency at most 0.025 s, six-stream wall 2.262 s, INFRA-23 0.378 s CPU (load about 11); gate rows cite
  the clean export of `bd8eeaf` (suite SKIP 13 PASS 22392, R CMD check 0/0/0, M0 install `* DONE`, filter PASS
  1133). No R files touched.
- Reviews: r1 5 findings (0/0/3, 2 nits; CI-7 overclaimed, incoming NOTE cause, D-011 measurements) -> fixed.
  Deviations: none. Open: M0 tag (maintainer); hosted CI-7 confirmation.

## Task CI-10 - The FIX-1 deferred-shutdown test counts only its own sessions (2026-10-05)
- Red: hosted devel (run 37404322232, `167baf8`) `test-ext-registry.R:244`: seven earlier tests' dead sessions,
  collected during the test, queued their `gc` shutdowns in its scratch registry; a throwaway control (dead sessions
  plus a forced collection inside `registry_add()`) FAIL 3 the same way. Fix (test only): `gc()` before
  `local_registry()`, as `fix1_registry()` does. Green: control PASS; `^ext-registry$` PASS 175 (x3); `ext-` PASS
  1782. Lint clean. Neighbours: `ext-` green.
- Reviews: none recorded. Deviations: none. Open: hosted devel confirmation.

## Task CI-8 - Close the processx supervisor the artifact tests leave open (2026-10-05)
- Red: hosted connections (run 37404322232, `167baf8`) table 3 -> 5, processx's supervisor fifos: `serve_child()`
  passed `supervise = TRUE` and chromote 0.5.1 always supervises Chrome; the gate on `^artifact-(app|registry)$`
  gives 3 -> 5 locally. Fix (tests only; `supervisor_kill()` in R/ could end other code's supervised processes):
  `serve_child()` uses `supervise_default()`; test-artifact-app.R ends the supervisor with the file when gptr does
  not supervise (IC-60). Green: that gate 3 -> 3, PASS 316 (one run beside lint under load: FAIL 1 `:519`,
  launcher `h$alive()` after `h$stop()`; re-run PASS 316); `^artifact-` PASS 316. Lint clean. Neighbours: the whole
  connections gate keeps the table (3 -> 3), FAIL 1 `test-cli-codex.R:770`: order-dependent, the once-only
  `billing_env` warning is spent by `test-auth-childenv.R` (`^(auth-childenv|cli-codex)$` FAIL 1); lane cli-sub.
- Reviews: r1 1 finding (0/1/0; `:770` blamed on mid-commit edits) -> corrected, reported to the coordinator.
  Deviations: none. Open: hosted connections confirmation, which also needs lane cli-sub's `:770` fix.

## Task CI-9 - INFRA-23 headroom: one-pass as_utf8() and json_decode() without paste for one string (2026-10-05)
- Red: not applicable (performance; INFRA-23 and its 1 s budget unchanged, D-011). Differential against HEAD in
  en_US.UTF-8 and C: `as_utf8()` on 40,050 vectors (UTF-8, latin1, unknown, bytes, invalid bytes, NA, empty, names,
  class, dim, 5,000 elements, 200 kB strings), `json_decode()` on 3,169 inputs: 0 mismatches in values, marks, bytes,
  attributes, warnings and errors (mutation controls: 569-34,216). INFRA-23 workload CPU, best of 3 (7 rounds, macOS,
  load 6-10): 0.330 -> 0.241 s (-27%; interleaved -24%); `json_decode()` alone 0.202 -> 0.118 s.
- Green: `^http-sse$` PASS 70; `utils-encoding|json-` PASS 745 (with http-sse under LC_ALL=C: SKIP 1 PASS 811);
  `^(arch-layers|lint-rules)$` PASS 19. Lint clean. Neighbours: `http-|proc-|provider-|s1-|doc-io|tool-read|auth-`
  SKIP 1 PASS 6601 (first run FAIL 3 `test-provider-anthropic.R:816-818`, mock stream retried under load; alone and
  re-run green).
- Reviews: none recorded. Deviations: none. Open: hosted Windows INFRA-23 confirmation.

## Task CI-11 - The headless-browser session checks skip when Chrome cannot start (2026-10-05)
- Red: run 37410891417 (`3418582`): Windows release and oldrel-4 FAIL 9 (both session-check tests), Ubuntu oldrel-4
  FAIL 4 (first test only, the cold start): the contract's HTTP-only fallback (`ok` NA, "the headless browser failed:
  Chrome debugging port not open after 10 seconds."); a throwaway control with `artifact_session_browse()` mocked to
  that error FAIL 9 WARN 1, as hosted. Fix (tests only): `skip_if_browser_failed(res)` after each
  `artifact_session_check()` skips with the result's message when `ok` is NA and no browser started
  (`artifact_state$browser` NULL). Green: control with `artifact_browser()` mocked to that error SKIP 2 FAIL 0; a broken
  `artifact_js_state` (Chrome starts) still FAIL 9 WARN 1; `^artifact-` PASS 316 (Chrome starts locally). Lint clean.
  Neighbours: `^(lint-rules|arch-layers)$` PASS 19.
- Reviews: r1 2 findings (0/1/0, 1 nit): the skip matched every "headless browser failed" and hid gptr regressions
  after Chrome started -> fixed (no-browser condition); Red wording -> fixed. Deviations: none. Open: hosted
  confirmation.

## Task CI-12 - The codex billing-warning test does not depend on test order (2026-10-06)
- Red: `^(auth-childenv|cli-codex)$` FAIL 1 `test-cli-codex.R:770`: `test-auth-childenv.R` had spent the once-only
  `billing_env` warning (`the$once`). Fix (test only): the codex turn test binds a fresh `the$once` for itself
  (`rlang::local_bindings()`, restored at its end). Green: that filter PASS 385; `^cli-` SKIP 3 PASS 748;
  `^auth-childenv$` PASS 140. Lint clean. Neighbours: `^(lint-rules|arch-layers)$` PASS 19 green.
- Reviews: none recorded. Deviations: none. Open: hosted connections confirmation (with CI-8).

## Task CI-13 - The launcher's stop returns once the child has exited (2026-10-06)
- Red: `test-artifact-app.R:528` (CI-8's `:519`) `h$alive()` TRUE after `h$stop()`: a child that outlives the 3 s
  grace gets `kill_tree()`'s SIGKILL, and processx's `kill()` then returns without reaping it while it exits (a 1.2 GB
  child reads alive for about 20 ms); a throwaway control (an 800 MB app that sleeps 5 s at exit) FAIL 3 of 3. Fix:
  the launcher's `stop` waits for the exit, bounded by the grace (artifact children are the only `kill_all()` targets
  without a gptr marker, whose cleanup already waits). Green: control PASS 6; `^artifact-app$` PASS 272 (x5, r1 x3);
  `^artifact-` PASS 316 (beside lint). Lint clean. Neighbours: `^(lint-rules|arch-layers)$` PASS 19 green.
- Reviews: r1 1 finding (0/0/1; heading named a test change, the fix is in R/) -> fixed. Deviations: none. Open: none.

## Task CI-14 - A claude interrupt is not raced by the aborted turn's stream (2026-10-06)
- Red: hosted `test-cli-claude.R:774` (run 37503348214). Cause in R/: P05's route of the aborted turn kills the
  child at its next line (D-018), so a line unread at the cancel stopped it before `write_all()` wrote the
  interrupt. The test now waits for unread output (`claude-hang.ndjson` pauses 0.5 s before its last line):
  `^cli-claude$` FAIL 2 (`:778` no interrupt, the hosted message; `:794` 2 of 3). Fix: `pcli_stop_child()`
  routes the child's lines to its acknowledgement check from the interrupt on (grace 2 s unchanged); the
  normaliser's now unreachable check goes (`R/cli-claude.R`).
- Green: `^cli-claude$` PASS 238 (x3); a throwaway copy with a slowed fake (0.3 s before each stdin read and
  each turn) under two busy cores, every cancel acknowledged. Lint clean. Neighbours: `^cli-` SKIP 3 PASS 750,
  `^(provider-registry|subagent-backends)$` PASS 838, `^(arch-layers|lint-rules)$` PASS 19 green.
- Reviews: r1 3 findings (0/0/2, 1 nit): no test asserted the acknowledgement (a no-ack mutant passed) -> fixed,
  the mutant now FAIL 1 `:779`; heading named a test change, the fix is in R/ -> fixed; another lane's
  DEVIATIONS hunk -> not CI-14's, stage D-163 only. Deviations: D-163. Open: hosted confirmation.

## Task CI-17 - Worker spec and callr function files carry no lazily loaded package source (2026-10-06)
- Red: hosted run 37566867447 (above). Not registry leftovers: an installed-package probe over the 114 files to
  secrets-e2e (`CI=true`) finds no user record left by any test. Cause in R/: installed with its source, a
  package keeps a source file's `lines` as a lazy-load promise reaching `the` (vault, out store), shipped by the
  e2e extension's API closures (spec) and `worker_main` (callr keeps its body's source files). The same order on
  a keep-source install gives the hosted failure (14.6 MB, 6062 matches); `^subagent-worker$` FAIL 2 (new tests).
- Fix: `worker_refhook()` writes a source file holding a lazy-load promise as a reference; callr gets
  `utils::removeSource()` of `worker_main` and `artifact_serve` (`R/artifact-app.R`).
  Green: `^subagent-worker$` PASS 119 (x2); `^(secrets-e2e|subagent-worker|subagent-backends)$` PASS 308;
  `^(ext-plugins|secrets-e2e)$` PASS 415; `^artifact-` PASS 464. Keep-source install: the 114-file order green
  (2856 tests, 15 skips), `^(secrets-e2e|subagent-worker|artifact-app)$` green; with a marker in `the`, a shipped
  package function is 10.5 KB and callr's `artifact_serve` 6 KB, neither holding it. Lint clean. Neighbours:
  `^subagent-` PASS 570, `^(arch-layers|lint-rules|injection-e2e|zzz)$` PASS 306 green.
- Reviews: r1 2 findings (0/2/0): every source file a reference broke a user's shipped function (read back as the
  empty environment, its description printed to the worker's JSONL stdout and classed that environment) ->
  fixed, a user's source file ships by value (new assertion FAIL 1 with the r1 hook); `artifact_serve` went to
  callr with the package source (8.2 MB) -> fixed (new test FAIL 1 before). Deviations: D-177 (edited in place).
  Open: hosted confirmation.

## Task CI-18 - The token benchmark pins the machine's r_env section (2026-10-07)
- Red: hosted run 37583355970 (above): T1 is the machine's real `<r_env>` (`only_missing` skips its stand-in), so a
  case prefix describes the machine. New `test-token-gates.R` test (a mocked `r_env_probe()` moves ns02's prefix)
  FAIL 1, PASS 62. Fix: `bench_case()` pins the `r_env` stand-in at session rank 0 (`bench_standins()`), like
  `<environment>`.
- Baseline (`run.R --update`, reviewed): the 12 standard cases' prefix and catalog +48 (stand-in 399, this machine
  351), input totals +48 and estimates +30 (ns10 +31) per request; minimal cases, requests, output, image tokens and
  facts unchanged; the six rows recorded before `0d70a9d` also take its +47 (P24-3's Open). The hosted rows
  (`<r_env>` 229) plus 170 (prefix) and 170 per request (input) give every refreshed row exactly.
- Green: dev `test_dir("dev/bench/tests")` PASS 524 (token-gates 63); `run.R --check` OK (4 static prefixes, 14
  transcripts; results equal the baseline). Lint clean. Neighbours: `^(bench-context|context-prefix|prompt-sections)$`
  PASS 435, `^(arch-layers|lint-rules)$` PASS 19.
- Reviews: r1 clear; minor (hand-built `r_env` stand-in) -> reuses `bench_standins()`; nit (test header) -> fixed.
  Deviations: none. Open: hosted confirmation; `dev/bench/cache-sim` (local-only, not on CI) drives
  `peter()`, so its baseline still holds the machine's `<r_env>`.

## Task CI-19 - Hosted job budgets fit the grown suite (2026-10-07)
- Red: since `f6aa1c8` three jobs are cancelled at their `timeout-minutes` in every run (shown as cancelled, not failed):
  connections at 30 min (reached `subagent-defs`; 15.6 min on `ef21d3f`), Windows oldrel-4 at 45 (31 min on `ef21d3f`)
  and Windows release at 75 (57 min), whose 30 min file-by-file step now ends at `injection-e2e` (70 of ~170 files).
  No file hangs: every file takes about twice its Linux time (copy-gateway 125 s, copy-ckpt 112 s, artifact-app 99 s).
- Fix: connections 60 min, both Windows jobs 120 min (job budgets, not timing assertions; every test bound unchanged,
  D-011); the Windows release job no longer runs `dev/ci/test-by-file.R`, kept for on-demand diagnosis (D-019 edited).
- Test: `test-zzz.R`'s file-by-file block becomes "the hosted jobs have time for the whole suite (CI-19)": red on the old
  workflow FAIL 2 (Windows 75/45 < 120, connections 30 < 60), green `^zzz$` PASS 88. Lint clean.
- Green: hosted confirmation pending. Deviations: D-019 (edited in place).

## Task DOC-3 - Internal roxygen comments hold no unresolved links (2026-10-07)
- Red: `document()` printed 44 `✖` lines (exit 0; roxygen 7.3.3 reports them through `cli::cli_inform()`): bracketed
  text in `#'` comments of 14 files read as links: copy-safety tags `[R1][R2]`, `[leaf]`, `[experimental]`, console
  syntax `/model [ref]`, intervals `[0, 1]`, `a[x + 1 ..]`, and `"[...]"` (found in 18 packages).
- Fix: each fragment says what it means: "(rules R1, R2)", "(leaf function)", "(...; experimental)", command
  syntax and index or glob notation in backticks, intervals in words. Comment lines only.
- Green: `document()` exit 0 with no `✖` line, NAMESPACE and `man/` unchanged; lint clean (14 files);
  `^(arch-layers|lint-rules|zzz)$` PASS 107. Deviations: none.

## Task CI-20 - INFRA-03 interrupts once the mock holds the request (2026-10-07)
- Red: hosted run 37588313491 (above). Step 1 sent its SIGINT a fixed 1 s after `step_ttft()`; a throwaway copy whose
  child waits 1.5 s before `peter()` FAIL 3 at the same assertions: 0 request rows at the SIGINT, the call aborts at
  top level and `c` prints R's primitive. Fix (test only): step 1 waits, bounded at 30 s, for the ttft mock's request
  row (logged on arrival, before its 3 s head delay; the child sends only from the pump under the policy), asserts
  it, then interrupts. Steps 2-3 already wait for output. Green: `CI=true` `^console-interrupt$` PASS 65 (x3, x3 after
  r1; +1 the row assertion); the slowed copy PASS 65. Lint clean. Neighbours: `CI=true` `^console-` PASS 457 beside a
  concurrent `^copy-gateway$` run, green.
- Reviews: r1 clear; minor (1 of its 9 runs: the `stream` mock exited before ready with empty stderr, line 438, before
  the edit; 160 starts did not reproduce it) -> declined, out of scope. Deviations: none. Open: hosted confirmation.

## Task WIN-1 - Worker children never block reading an empty stdin on Windows (2026-10-07)
- Red: on-demand Windows run 37639048633: `subagent-worker`, `cli-codex` (INFRA-16) and `injection-e2e` time out; the
  `secrets-e2e` and `subagent-backends` workers end `error`. Probes on a temporary branch (runs 37654220709,
  37657007246): processx's fd-0 poll fails (error 87) and its read drops data; `file("stdin")` reads lines and EOF;
  the tests' blocking in-process pipe end never reads; a worker that is the first supervised child fails "no file
  found" (`supervisor_path()` without `R_ARCH`); secrets-e2e's `setdiff()` kept the `.env` file (path separators).
  Local: new tests FAIL 4 (`^subagent-worker$`), FAIL 1 (`^auth-childenv$`).
- Green: Windows run 37657687678, the five files plus `auth-childenv`: 0 failed (platform skips only). Local
  `^subagent-` PASS 580, `^(cli-codex|injection-e2e|secrets-e2e|auth-)` PASS 1677 (2 environmental skips). Lint clean.
- Reviews: none. Deviations: D-179. Open: hosted confirmation on `main`.

## Open hosted items
- INFRA-23 (`test-http-sse.R:126`, 20,000 deltas under 1 s CPU, decomposition P04 acceptance 5): hosted Windows
  single runs 1.01-1.39 s (5 failures in 9 Windows executions of the CI-6 runs; oldrel-4 1.040 s in 37390651676);
  local macOS 0.30-0.40 s. CI-7 asserts the best of three runs, budget unchanged (D-011); CI-9 cut the decode (-27%
  CPU); if hosted Windows still fails, optimise the SSE split (P04).
- INFRA-01: the CI-1 macOS gap failure (`test-http-reactor.R:557`) is unexplained; Windows release had late first
  deltas (0.38 / 0.181 s, `0c37a8d`) and a six-stream failure (`718659d`). Messages print the mock's lateness and
  gptr's latency; a gptr-side failure needs a P04 investigation (D-011).
- `test-proc-supervise.R:89` "kill_all() leaves no descendant": 2 failures in 4 runs, Linux only; plausible, not
  verified: a grandchild between `fork()` and `exec()` when the tree is read.
- One-off local failures (P04; both read the mock's log): `test-http-retry.R:613` (0-row log) and
  `test-http-reactor.R:726` (`disconnected` FALSE, loaded machine). Investigate if either recurs.
- D-019 item 5: processx `write_all()` blocks on Windows; P04 decision before P18, P19, P20 and P22 send large stdin.
- `tools::file_ext()` calls `basename()` on R >= 4.6 (stops on a non-ASCII path in a non-UTF-8 locale): P17
  `R/ext-specs.R:1330` (also needs `fs_path()`) and P08 `R/gptr-gateway.R:796` should use `path_ext()` (D-111).
- ctx members read with `get()`, `get0()`, `mget()` or `as.list()` pin a function frame on R >= 4.6 (D-137 item 1);
  none in `R/`.
- Chrome leaves `com.google.Chrome.*` temp dirs that R CMD check reports as detritus NOTEs on hosted runners
  (run 37503348214); harmless for CRAN because those tests `skip_on_cran()`.
- Non-gating NOTEs: Windows `Rscript*` temp detritus from killed `Rscript -e` children (suggested, unverified: give
  them TMPDIR/TMP/TEMP in `withr::local_tempdir()` or run a script file); macOS `com.apple.*` folders under
  `/var/folders/.../T` (runner); Windows installed size 6.8 MB; local "future file timestamps" (no time server).

## Tooling (2026-10-03, `17f78c2`)
- Project-local library `dev/.library/` (ignored, D-002); default libraries untouched (they keep roxygen2 8.1.0).
  Prefix every `Rscript --vanilla`, including `devtools::document()`, with `R_LIBS_USER="$PWD/dev/.library"`
  (absolute path from other directories). Child processes that sanitise their environment must keep `.libPaths()`/
  `R_LIBS` through their documented mechanism.
- Loaded in clean processes: roxygen2 7.3.3 (pinned, CRAN archive source), chromote 0.5.1, duckdb 1.5.6, keyring 1.4.1,
  rtiktoken 0.11.0.3, spelling 2.3.2 (macOS arm64 binaries); also AsioHeaders 1.30.2-1, websocket 1.4.4, hunspell 3.0.6.
  The eight Imports meet their floors; every declared Suggests is installed.
- `dev/ci/isolated-check.R` (`55ec31d`) `test <filter> | lint [files] | document | connections | check <dir>`: fresh
  home, config, cache, data and project paths before any load, provider credentials cleared, live tests off;
  `connections` runs the full suite under IC-60 check-mode supervision and compares the connection table (D-006).
- Forward notes: token baselines were recorded with rtiktoken 0.0.7 (P07 validates counts); Quarto CLI absent (P15's
  test may skip); P22 selects the Python interpreter explicitly; Chrome is present, the Shiny/chromote session ladder
  has not run.

## Linux process liveness (2026-10-03, `c8470f7`)
- Cause: ps 1.9.3's Linux `psll_handle()` reads `/proc/<pid>/stat`; a vanished PID raises `os_error` with an errno,
  not `no_such_process`, so dead lock holders, `kill_all()` targets and orphans stayed uncertain (run 37167848633).
- Rule: an `os_error` with ENOENT or ESRCH means gone only when an independent `ps_pids()` inventory (each entry
  checked with `proc_pid_valid()`) includes the current process and excludes the target; other errors or an
  inconclusive inventory stay uncertain. Creation-time checks and signals through the same verified handle are
  unchanged. Errno values come from `ps::errno()`'s `name`/`value` columns.
- Red: `^(proc-supervise|auth-store)$` FAIL 5 (errno identity, stale lock, vanished-handle status, orphan marker).
  Green: `^(proc-supervise|auth-store|proc-spawn)$` SKIP 1 PASS 333 (keyring skip). Lint clean.
- Reviews: r1 1 finding (validate inventory PIDs) -> fixed; r2 clean. Deviations: none. Open: none (hosted Ubuntu
  green in run 37351073211).

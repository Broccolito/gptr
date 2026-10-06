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

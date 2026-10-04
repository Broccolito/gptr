# Hosted CI lane (M0 hosted gate)

Corrections to the GitHub Actions workflow `.github/workflows/R-CMD-check.yaml` (P01 Task 21)
and to the code and tests its hosted runs exposed. Each task records the hosted evidence that
motivated it, its actual local red/green results and the logs under the ignored
`dev/.validation/CI/`. A hosted run validates only the commit it ran on; local results here do
not close the M0 hosted gate.

## Task CI-1 - Cross-platform hosted CI corrections

Hosted evidence (fetched with `gh api .../actions/jobs/<id>/logs`): run 37169255693 on
`8e8d8e0` and run 37170545611 on `a2ba302`.

| Failure | Where | Cause |
|---|---|---|
| `test-aaa-state.R:127-128` "ext_service_set() registers and replaces services" | every Ubuntu job, macOS, no-Suggests, LC_ALL=C, connections | the plan test registers a service owned by the never-declared `builtin:workspace` (P09); once the secrets/fake/providers built-ins have loaded records, the plan's `service_builtin_active()` counts it as filtered out |
| `test-http-reactor.R:570` six-stream wall `<= 2.475` | macOS release (2.57 s, run 37169255693), connections (2.4830 s, 2.553 s) | wall clock anchored when the client queued the transfers, so connection setup and the mock's request handling (about 0.04 s locally to build a response plan) counted against INFRA-01 |
| `test-http-reactor.R:557` consecutive delta gaps `< 0.35` | macOS release (both runs) | not connection setup (a gap compares consecutive deltas). Cause unknown: either the mock's own write lateness or gptr's delivery, possibly runner scheduling or `socketSelect()` overshoot. Open item, see below. |
| windows-latest (oldrel-4) "success" | both runs | R CMD check aborted at its start (`[.data.frame(file.info(foo), , "uname")`: undefined columns) because `_R_CHECK_THINGS_IN_OTHER_DIRS_=true` needs owner columns that Windows R has only from 4.5.0; rcmdcheck still reported success |
| windows-latest (release) | both runs | hung inside "checking tests" for over an hour until cancelled (no time limit) |
| connections | both runs | `devtools::test(stop_on_failure = TRUE)` inside the gate aborted on the first failing test, so the connection tables were never compared |
| NOTE "no visible global function definition for 'file_test'" | every R CMD check | `R/auth-redact.R:615,630` called `file_test()` unqualified (utils is not imported) |

What was built:

1. Final state after review round 1: `R/aaa-state.R` is unchanged (the plan's rule). The plan
   test "ext_service_set() registers and replaces services" mocks `service_builtin_active()` to
   `TRUE`, because it tests the bootstrap table and the owning built-in `workspace` is not
   declared in this build (D-016 item 2). The round-1 product change, which read P02's
   `the$builtins` directly, was withdrawn (see Review round 1).
2. Final state after review round 1: INFRA-01 is measured on the mock's own clock. With
   `log_writes = TRUE` the mock (`fixtures/mock_server.R`) logs the wall-clock time just before
   each response piece is written, and `local_mock_server()` returns that log as `writes()`
   (`mock_writes()` in `helper-mock-server.R`). `start_transfer()` records wall-clock arrivals
   and the wall-clock end. Three helpers measure against it: `infra01_delivery()`,
   `infra01_on_time()` (every latency below 0.35 s, every gap on the 0.25 s cadence below
   0.35 s, no latency below -0.05 s) and `infra01_wall()` (six streams, from the first head
   written to the last end, at most 2.475 s). D-016 item 1.
3. Workflow: `things-in-other-dirs: 'false'` on the Windows oldrel-4 matrix entry with
   `_R_CHECK_THINGS_IN_OTHER_DIRS_: ${{ matrix.config.things-in-other-dirs || 'true' }}` (a
   quoted string, because an unquoted `false` would make the expression fall back to `'true'`);
   a step after each R CMD check (matrix, no-Suggests, LC_ALL=C) that fails unless
   `check/gptr.Rcheck/00check.log` exists and has a `^Status:` line; `timeout-minutes` on every
   job: 45 for R CMD check jobs, 30 for the others, 120 for R-devel (its dependency install took
   63 and 67 minutes on a cold cache in run 37169255693). New test in `test-zzz.R`: "hosted CI
   jobs are bounded and a crashed R CMD check cannot pass".
4. `dev/ci/check-connections.R`: `check_connections(code, failures)` now captures a suite error,
   always compares the before/after tables, then fails reporting every problem (failed tests,
   suite error, changed table); `suite_failures()` counts failed expectations plus errored tests
   of a `testthat_results`; `run_gate()` runs `devtools::test(stop_on_failure = FALSE)` through
   the gate (the script's entry point, and `dev/ci/isolated-check.R connections`). The
   deliberate-leak negative control and the option-restore tests are kept (D-006); new tests
   cover a leak together with failed tests, failed tests without a leak, a leak together with a
   suite error, `suite_failures()` on a real `test_file()` result (2 failed expectations + 1
   error + 1 skip + 1 pass = 3) and `run_gate()` passing `stop_on_failure = FALSE`.
5. `R/auth-redact.R`: `utils::file_test()`; new codetools test in `test-auth-redact.R`.
6. Not touched: the `catalog_http_get` NOTE (owned by P05 Task 8) and every P05-owned file.

Adaptations: the plan has no literal for these corrections. P04's literal INFRA-01 anchors are
replaced and P01's service registration test is isolated, as recorded in D-016. The P01 plan's
`service_builtin_active()` is kept. The workflow deviates from P01 Task 21's literal only as
listed in item 3.

### Implementation round (superseded where review round 1 says so)

Red (actual, before the source/workflow changes):

- `aaa-state`: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 41 ]` - the plan test (127, 128) and the new
  test (`service_builtin_active("workspace")` FALSE; `describe` not available). The plan test
  alone reproduced FAIL 2 / PASS 38 with the filter before any edit (`task1-aaa-state-baseline.log`).
- `zzz`: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 68 ]` - six jobs without `timeout-minutes`, three
  check jobs without the status guard, the env value `TRUE` and the Windows oldrel-4 value `"true"`.
- `auth-redact`: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 403 ]` - `file_test` is a global of `scrub_walk`.
- `dev/ci/test-check-connections.R`: `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 11 ]` - unused argument
  `failures`, `suite_failures`/`run_gate` missing, a suite error skipped the table comparison.
- INFRA-01: the red evidence is the hosted failures above (a timing target cannot be made to
  fail on a healthy local host). Local probe of the real mock, plan anchor vs new measurement,
  five repetitions (`task1-infra01-probe.log`): connection setup 0.063-0.111 s (single) and
  0.071-0.120 s (six), plan six-stream wall 2.337-2.372 s, plan max gap 0.251-0.262 s; new
  worst schedule offset 0.003-0.050 s, stagger of first events 0.001-0.010 s, six-stream ratio
  1.000-1.004 (limit 1.10).

Green (actual):

- `aaa-state`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 49 ]` (38 + the plan test's 4: its failure,
  its error and the 2 expectations the error had skipped + the new test's 7).
- `zzz`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 79 ]`.
- `auth-redact`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 404 ]`.
- `^http-reactor$`, three consecutive runs: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 198 ]` each
  (18-19 s; the measurement change is +5 expectations: 5 negative controls, -1 in the
  single-stream test, +1 in the six-stream test).
- `dev/ci/test-check-connections.R`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 20 ]`.
- Neighbours `ext-|lint|arch|utils-options` (P02 tests that depend on the service rule, the
  package lint rules and the layer table): `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1418 ]`.
- YAML: parsed with Python `yaml.safe_load` and by the `zzz` test with `yaml::read_yaml`.
- Full unfiltered offline suite (`isolated-check.R test '.'`, HEAD `7633ff1` plus this task's
  changes and the concurrent P05 Task 9 working-tree edits): `[ FAIL 0 | WARN 0 | SKIP 1 |
  PASS 5805 ]` in about 3 min 19 s; the one skip is the expected keyring-installed skip
  (`test-auth-store.R:75`). No cross-file pollution remains.
- Connection gate end to end (`isolated-check.R connections`, now `run_gate()`): the same
  `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 5805 ]`, unchanged connection table, exit 0.

Lint: `isolated-check.R lint` on `R/aaa-state.R`, `R/auth-redact.R`, `test-aaa-state.R`,
`test-http-reactor.R`, `test-zzz.R`, `test-auth-redact.R`, `dev/ci/check-connections.R`,
`dev/ci/test-check-connections.R`, `dev/ci/isolated-check.R`: no lints (one 101-character
line in the gate was wrapped first). No roxygen or export change, so no document run.

Logs: `dev/.validation/CI/task1-*.log` (baseline, red, green, three reactor runs, probe,
neighbours, lint, YAML, full suite with its `.head`/`.status`, connection gate). The hosted job
logs used for the diagnosis are not in the repository; refetch them by job id if needed.

### Review round 1

Findings, checked against the contract, the architecture and the decomposition:

1. Major, accepted. The single-stream test anchored at the client-side arrival of
   `message_start`, so a delay common to every event went unbounded: 1.5 s on every event
   passed. Architecture 6.18 anchors at "the mock writing it". Fixed by measuring each delta's
   latency from the mock's own logged write.
2. Major, accepted. The six-stream test compared the span only with the measured slowest
   stream, so a common stretch passed (six streams at 0.375 s per delta, 3.375 s). Fixed by
   keeping the plan's bound of 2.475 s and moving only the anchor, from the client's queue time
   to the first response head the mocks wrote.
3. Major, accepted. `service_builtin_active()` read P02's `the$builtins` directly, which
   contract 7.0 forbids. No contract-listed P02 function says whether a built-in is declared or
   filtered. Fixed by the coordinator's alternative: `R/aaa-state.R` is restored to HEAD (the
   plan's rule, no product change) and the plan test is isolated. The round-1 test "a built-in
   that no loaded plan declares is not filtered out (IC-34)" is removed with the product change.
4. Minor, accepted, and one premise corrected. The gap target is not only P04's literal:
   decomposition P04 acceptance 2 names it ("every inter-delta gap is under 0.35 s"), and
   architecture 6.18 does not contradict it. So it is kept, not replaced. The gap between
   consecutive deltas on the mock's 0.25 s cadence must be below 0.35 s. Only the mock's own
   write lateness is netted out, so gptr's delivery may still vary by less than 0.1 s from one
   delta to the next, as in the plan. D-016 now records the macOS `:557` failure as not caused
   by connection setup and as an open item.

What changed: `tests/testthat/fixtures/mock_server.R` (opt-in `log_writes`, and `first_event()`
names each queued piece), `tests/testthat/helper-mock-server.R` (`mock_writes()`, `writes()`),
`tests/testthat/test-http-reactor.R` (wall-clock arrivals in `start_transfer()`, the new helpers,
11 synthetic controls, both real-mock tests), `tests/testthat/test-aaa-state.R` (isolation of
the plan test; the round-1 test removed), `R/aaa-state.R` (restored to HEAD), and D-016 items 1
and 2 rewritten. Note: the concurrent P05 commit `add014a` swept the round-1 D-016 text into
HEAD, so this task's change to `dev/DEVIATIONS.md` is a rewrite of that entry. The P05 lane's
uncommitted D-017 also sits in that file, so stage only the D-016 hunk.

Regression red (actual):

- `^http-reactor$` with the reviewer's three scenarios added as controls against the round-1
  helpers: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 198 ]`. The three failures, at 595, 599 and 601,
  are the expectations that 1.5 s on every event, six streams stretched 1.5x and a 0.93 s gap
  must fail; each passed the round-1 measurement (`fix1-red-http-reactor.log`).
- `aaa-state` with `R/aaa-state.R` restored to HEAD and the plan test not yet isolated:
  `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 38 ]` at `test-aaa-state.R:127-128`, the hosted failure
  (`fix1-red-aaa-state.log`).

Real-mock probe, five repetitions (`fix1-infra01-probe.log`, script in the session scratchpad):
delivery latency 0.3-41 ms; gaps at most 0.254 s; the mock's own write lateness at most 2 ms
after 37-42 ms of building its plan; raw arrival gaps at most 0.260 s; six-stream wall from the
first head 2.268-2.273 s (heads within 10-12 ms), against 2.341-2.374 s with the plan's anchor.
Negative controls on the real mock: pausing the pump for 1.5 s after the mock has read the
request fails (latency 1.237 s). Holding 0.4 s after delta 4 also fails: its latency, 0.163 s,
alone would pass, but its gap, 0.410 s, does not.

Regression green and final green (actual):

- `aaa-state`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 42 ]` (38 + the plan test's 4).
- `^http-reactor$`, three consecutive runs: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 205 ]` each.
  That is 198 + 7: the controls test went from 5 to 11 expectations and the single-stream test
  from 5 to 6.
- Mock-server consumers `^http-|^provider-fake$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 909 ]`.
- Neighbours `ext-|lint|arch|utils-options`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1418 ]`.
- `zzz|auth-redact`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 483 ]` (79 + 404).
- `dev/ci/test-check-connections.R` (`testthat::test_file`, `stop_on_failure = TRUE`):
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 20 ]`.
- Full unfiltered offline suite (`isolated-check.R test '.'`, HEAD `add014a` plus this task's
  changes and the concurrent P05 working-tree edits): `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 5960 ]`,
  exit 0, 3 min 23 s. The one skip is the keyring skip at `test-auth-store.R:75`.
- Connection gate end to end (`isolated-check.R connections`): the same
  `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 5960 ]`, exit 0.
- Lint (`isolated-check.R lint`) on all 11 R files of this task found no lints: `R/aaa-state.R`,
  `R/auth-redact.R`, `test-aaa-state.R`, `test-http-reactor.R`, `test-zzz.R`,
  `test-auth-redact.R`, `helper-mock-server.R`, `fixtures/mock_server.R`,
  `dev/ci/check-connections.R`, `dev/ci/test-check-connections.R` and
  `dev/ci/isolated-check.R`. No roxygen change, so no document run.

Logs: `dev/.validation/CI/fix1-*.log`.

Open items (not fixed here):

- The windows-latest (release) hang inside "checking tests" needs a separate diagnosis. R CMD
  check prints test output only at the end; the new 45-minute limit turns the hang into a
  visible failure instead of a cancelled run.
- The hosted macOS INFRA-01 gap failure (`:557`) is not explained. On the next hosted macOS run,
  read the failure message, if any: it prints every latency and gap and the mock's own
  lateness. A gap still over 0.35 s there is gptr's delivery and needs a P04 investigation
  (D-011).
- The hosted gate is not closed until a pushed commit containing these corrections passes on
  every job.

## Task CI-2 - Windows process portability and the hung Windows test run

Hosted evidence: the Windows release job of run 37167848633 on `55ec31d` (job 111334466669,
complete: `[ FAIL 8 | WARN 0 | SKIP 8 | PASS 4430 ]` in 216 s) and of run 37169255693 on
`8e8d8e0` (cancelled after 68 minutes in "checking tests"; its `_problems` list ends at
`test-proc-spawn-294`). The job of run 37170545611 on `a2ba302` (no time limit) was still in
"checking tests" after more than two hours when looked at once during this task.

| Failure | Cause |
|---|---|
| `test-proc-spawn.R:99`, `:106` byte-exact and code-page `proc_run()` output ended `0d 0a` | R's stdout is a text-mode stream on Windows: an R child's `"\n"` reaches the pipe as CRLF. `proc_run()` correctly keeps the bytes; the expectations assumed LF |
| `test-proc-spawn.R:143` `line_reader()` gave `"a\r"`; `test-http-reactor.R:309` (`8e8d8e0` only) the same | the fixtures wrote an explicit CRLF, which arrives as `"\r\r\n"` on Windows; `line_reader()` strips one CR, as specified. Found locally: on macOS the `:143` child `cat('a\\r\\nb\\nc')`, passed with `-e`, wrote `61 0a 62 0a 63` (no CR), so the plan's fixture never tested CRLF on Unix (`task2-fixture-bytes.log`) |
| `test-proc-spawn.R:294` echo of `FAKEfirstLine\r\nFAKEsecondLine` not redacted | the registered value holds LF; the echo passed the child's CRLF to the redactor (a real product gap, reproduced on macOS by the new unit test) |
| `test-proc-spawn.R:83`, `test-proc-supervise.R:102` `length(proc_tree(marker)) == 1L` FALSE | `Rscript.exe` runs `Rterm.exe` as its child on Windows, which inherits the marker (callr's `setup_r_binary_and_args()` also starts `Rterm` directly on Windows) |
| `test-proc-supervise.R:109` orphan marker file kept although the orphan died within 5 s (`:108` passed) | ps 1.9.3's `ps_kill()` on Windows calls `TerminateProcess()` and returns at once (on Unix it sends SIGTERM and waits up to its grace period before SIGKILL), so `proc_cleanup_record()` saw the processes still running and kept the record |
| `test-proc-supervise.R:253` mocked `ps::ps_kill_tree()` called 3 times | processx's finalizer of a process started with `cleanup_tree = TRUE` calls `get("ps_kill_tree", asNamespace("ps"))(tree_id)`, which reaches the mock when a garbage collection runs during the test; reproduced on macOS (`task2-red-finalizer.log`: one call with processx's `PS..._...` tree id) |
| the hang | first run in which the P04 Task 8 stdin tests existed (`f33c191`, after `55ec31d`); they follow `:294`. processx writes stdin with a blocking `WriteFile()` on Windows (pipe without `FILE_FLAG_OVERLAPPED`, `PIPE_WAIT`, 64 KB; `lpOverlapped = NULL`), read from processx's `src/win/stdio.c` and `src/processx-connection.c`. The 4 MB echo test deadlocks: the parent blocks writing a 64 KB slice while the child blocks writing its echo into a full stdout pipe. No R-level timeout can end that call |

What was built:

1. `R/proc-spawn.R`: `proc_echo()` shows CRLF as LF before redaction (echo only; the redirect
   file and `proc_run()`'s returned text keep the child's bytes, as P22's `bridge_decode()`
   expects). Roxygen of `proc_echo()` and `proc_run()` says so.
2. `R/proc-supervise.R`: new `proc_wait_exit(handles, seconds = 2)`; `proc_cleanup_record()`
   waits for the processes it signalled (the marked tree and the recorded child) before it counts
   kills and checks survivors. No wait when the kill completed (Unix), none on an unknown state.
3. Tests, `test-proc-spawn.R`: helpers `child_eol()`, `cat_raw_code()`, `crlf_bytes()`,
   `marker_tree_is()`; `:99` and `:106` expect the platform line end; the `line_reader()`
   fixture writes bytes (`61 0d 0a 62 0a 63` on Unix, measured; a bare LF on Windows), so one
   CRLF reaches the pipe on every OS; the tree test requires the child and its descendants; new
   "line readers end lines at CRLF as a Windows child writes them, across reads" (unit, fake
   process) and "proc_run echo
   ends lines at CRLF, so a Windows child's output is redacted as LF" (unit of `proc_echo()`
   over a CRLF redirect file, two polls); `skip_if_blocking_stdin()` (D-019) on the 4 MB echo
   test and on the timeout part of the stdin timeout test, whose no-pipe refusal now runs first
   and still runs on Windows. `test-proc-supervise.R`: `marker_tree_is()` in the sweep test; the
   reused-PID boundary test runs a synthetic processx-style finalizer under the mock and fails
   only on a signalled `GPTR_PROC_` marker; new "boundary: orphan cleanup waits for a kill that
   completes asynchronously" (mocked: the killed process reads as running for 0.3 s).
   `test-http-reactor.R:296`: the byte-exact pipe fixture writes one CRLF on every OS.
4. Workflow: step "Offline tests file by file (Windows release diagnosis)" in the R-CMD-check job
   before R CMD check, only for `runner.os == 'Windows' && matrix.config.r == 'release'`,
   `timeout-minutes: 20`, `continue-on-error: true`, `NOT_CRAN: 'true'`, running the new
   `dev/ci/test-by-file.R`: it redirects the home and `R_user_dir()` folders, loads the package
   once, then for each file prints its name and time into the run, every test start/end and
   expectation (`LocationReporter`) to unbuffered stderr, and per file the counts and failure
   messages; exit 1 on any failure. New `test-zzz.R` test "the Windows release job streams the
   offline suite file by file, bounded".

Adaptations and deviations (D-019): plan literal tests changed for Windows text-mode CRLF, the
`Rterm.exe` grandchild and processx finalizers (no target weakened: each now states the exact
platform behaviour, and the finalizer control proves the assertion still sees calls); two new
product behaviours (CRLF echo, bounded wait after a kill); two stdin tests skip on Windows with
the D-019 number because processx cannot write stdin without blocking there (open item below).
The P05 lane's uncommitted D-018 sits above D-019 in `dev/DEVIATIONS.md`: stage only the D-019
section (how: review round 1, finding 4). No P05-owned file was touched.

Red (actual, `isolated-check.R`):

- `^proc`: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 277 ]` (`task2-red-proc.log`): the CRLF echo test
  (`FAKE` in the echo, the text `"prefix FAKEfirstLine\r"`, `"FAKEsecondLine suffix\r"`) and the
  asynchronous-kill test (`proc_sweep()` 0 instead of 1, the process still running when it
  returned, the marker file kept). The Windows-only fixture changes pass on macOS by design.
  Baseline before any change: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 269 ]`
  (`task2-baseline-proc.log`).
- `^zzz$`: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 79 ]` (`task2-red-zzz.log`): no diagnostic step
  (count, order, `if`, limit, `continue-on-error`, `NOT_CRAN`) and no `dev/ci/test-by-file.R`.
- Finalizer reproduction with the plan's assertion (`task2-red-finalizer.log`, scratch test
  file run with `testthat::test_file()`): "Expected `signalled` to have length 0. Actual length:
  1." after collecting a processx process started with `cleanup_tree = TRUE`.
- The hang and the Windows-only failures cannot be reproduced on macOS; their red evidence is
  the hosted logs above.

Green (actual):

- `^proc`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 282 ]` (269 + 13: 5 + 4 + 3 in the three new tests,
  +1 in the reused-PID test) (`task2-green-proc.log`).
- `^zzz$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 86 ]` (`task2-green-zzz.log`).
- `^http` (all HTTP files, including the changed reactor test): `[ FAIL 0 | WARN 0 | SKIP 0 |
  PASS 698 ]`, 1 min 53 s (`task2-green-http.log`).
- Full unfiltered offline suite (`isolated-check.R test '.'`, HEAD `118f78b` plus this task's
  changes and the concurrent P05 working-tree edits): `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 6172 ]`,
  exit 0, 3 min 26 s; the skip is the keyring skip at `test-auth-store.R:75`
  (`task2-full.log`). It ran before the `line_reader()` fixture moved to bytes; `^proc` was
  re-run after that change (below).
- `dev/ci/test-by-file.R` locally on `test-proc-supervise.R` and `test-utils-hash.R`: per-file
  headers, every test start/end and expectation, `0 failed, 0 skipped, 134 passed` and
  `0 failed, 0 skipped, 43 passed`, exit 0 (`task2-by-file-local.log`). Its failure summary was
  checked on scratch controls (1 failure + 1 error + 1 skip + 1 pass gave "2 failed, 1 skipped,
  1 passed" and both messages).
- YAML parsed with Python `yaml.safe_load` (`task2-yaml.log`) and by `test-zzz.R`.
- Fixture bytes (`task2-fixture-bytes.log`): the plan's escaped child wrote `61 0a 62 0a 63` on
  macOS, the new byte fixture `61 0d 0a 62 0a 63`; `^proc` re-run with it: `[ FAIL 0 | WARN 0 |
  SKIP 0 | PASS 282 ]`.
- Final, after comment-only edits to `R/proc-supervise.R`: `^proc|^zzz$` `[ FAIL 0 | WARN 0 |
  SKIP 0 | PASS 368 ]` (282 + 86) (`task2-green-final.log`).

Lint: `isolated-check.R lint` on `R/proc-spawn.R`, `R/proc-supervise.R`, `test-proc-spawn.R`,
`test-proc-supervise.R`, `test-http-reactor.R`, `test-zzz.R` and `dev/ci/test-by-file.R`: no
lints (`task2-lint.log`); every touched file is ASCII-only. No roxygen export change, so no
document run.

Logs: `dev/.validation/CI/task2-*.log`.

To be confirmed by the hosted Windows run of the pushed commit (local results do not close it):

- the diagnostic step's stream completes within 20 minutes and names no hanging file; if a file
  still hangs, its last "Start test:" line names the test;
- `test-proc-spawn.R` (tree, `proc_run()` line ends, `line_reader()`, echo redaction) and
  `test-http-reactor.R` byte-exact pipe test pass on Windows release and oldrel-4 (which now
  runs its tests, since CI-1);
- `test-proc-supervise.R` sweep test: the bounded wait is the fix for the kept marker file
  only if the cause is the asynchronous `TerminateProcess()`; if `:109` still fails, read
  whether the survivor reads as running or unknown;
- R CMD check on both Windows jobs finishes and writes its `Status:` line.

Open items:

- D-019 item 5: `write_all()` blocks on Windows (processx). A P04 product decision is needed
  before P18, P19, P20 and P22 send large stdin payloads to Windows children.
- Not this task: the connections job of run 37176542781 (`118f78b`) failed at
  `test-provider-registry.R:970` (P05 lane), seen once while fetching logs.

### Review round 1 (Task CI-2)

Findings, checked against the contract and the architecture:

1. Major, accepted. The echo's CRLF-to-LF step ran before redaction, and `secret_variants()`
   had no line-end form, so a registered value that itself holds CRLF, written verbatim by a
   child (any Unix child, a binary-mode Windows child), reached the redactor as LF and was
   echoed in clear; HEAD redacted it. Architecture 6.5 lists the derived forms (URL-encoded,
   JSON-escaped, base64 cores) without excluding others, so adding one only widens redaction.
   Fixed with the reviewer's option 1, which keeps the hosted LF fix and covers every case:
   `secret_variants()` (`R/auth-secrets.R`) adds the value with CRLF turned into LF when it holds
   CRLF. With the echo's step this also redacts a CRLF value written through Windows text mode
   (`"\r\r\n"` becomes `"\r\n"`, the value itself). A value without CRLF has the same forms as
   before; `secret_late_check()` gains the same form (no double count: the LF form is not a
   substring of the CRLF value). D-019 item 1 says so.
2. Minor, accepted. `proc_wait_exit()` waited for every tree handle that read as running,
   including those whose `ps_kill()` failed, so each kept record cost 2 s on every
   `library(gptr)` sweep and `kill_all()`. Fixed: new `proc_kill_signalled(handles)` kills the
   tree with one `ps_kill()` call (no serial grace periods on Unix) and returns only the handles
   it signalled, from the per-handle `results` ps attaches when some of several handles fail
   (none on a failure without them); the recorded child is added only when its own `ps_kill()`
   did not fail. Only those are waited for. D-019 item 3 says so.
3. Nit, fixed: `kill_all()`'s roxygen names the bounded wait of the marker cleanup (D-019).
4. Nit, accepted: `git add -p` cannot split the contiguous D-018 and D-019 additions. The
   committer stages the HEAD file plus the D-019 section as a blob, without touching the
   working tree (checked in the scratchpad: the result equals the working file minus the D-018
   lines 331-367, and adds 56 lines to HEAD):

   ```sh
   T=$(mktemp -d)
   git show HEAD:dev/DEVIATIONS.md > "$T/d.md" && printf '\n' >> "$T/d.md"
   sed -n '/^## D-019/,$p' dev/DEVIATIONS.md >> "$T/d.md"
   git update-index --cacheinfo "100644,$(git hash-object -w "$T/d.md"),dev/DEVIATIONS.md"
   git diff --cached dev/DEVIATIONS.md   # only the D-019 section
   ```

What changed: `R/auth-secrets.R` (`secret_variants()` LF form), `R/proc-supervise.R`
(`proc_kill_signalled()`, `proc_cleanup_record()` waits only for signalled handles, `kill_all()`
roxygen), `tests/testthat/test-proc-spawn.R` (new "proc_run echo redacts a registered CRLF value
however the child wrote its line end": CRLF written verbatim and as text-mode `"\r\r\n"`, the
line break between two polls), `tests/testthat/test-proc-supervise.R` (the failed-cleanup
boundary test mocks `proc_wait_exit()` and expects no handle waited for, no wall clock; new
"boundary: a kill counts as signalled only for the handles ps_kill() reached": partial failure
with ps's `results`, a plain failure, success, an empty tree), `dev/DEVIATIONS.md` (D-019 items
1 and 3).

Red (actual): `^proc` `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 284 ]`
(`task2-fix1-red-proc.log`): `test-proc-spawn.R:395`, `:396` (the verbatim CRLF case echoed
`FAKE...`; the text-mode case already passed) and `test-proc-supervise.R:250` (`waited` had
length 2, the tree handle and the child, whose kills had failed). The reviewer's scratch
reproductions after the fix (`task2-fix1-reviewer-repro.log`): two failed-kill sweeps 0.01 s and
0.02 s (were 2.02 s and 2.04 s), records kept; the CRLF value echoed as
`prefix [secret:CRLF_TOKEN] suffix\n`, and the LF value in Windows text mode too.

Green (actual):

- `^proc` after the two fixes: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 287 ]`
  (`task2-fix1-green-proc.log`; 282 + 4 + 1).
- `^proc|^zzz$|^auth` with the `proc_kill_signalled()` test (written after the fix, so it has
  no red run): `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 1383 ]`, the skip the keyring skip at
  `test-auth-store.R:75` (`task2-fix1-green-final.log`).
- `^proc|^zzz$` final: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 378 ]` (292 + 86: the new
  `proc_kill_signalled()` test adds 5) (`task2-fix1-green-proc-zzz.log`).
- Full unfiltered offline suite (`isolated-check.R test '.'`, with the concurrent P05
  working-tree edits): `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 6219 ]`, exit 0; the skip is the
  keyring skip at `test-auth-store.R:75` (`task2-fix1-full.log`). It covers every other user of
  `secret_variants()` (redaction, late check, scrub).

Lint: `isolated-check.R lint` on `R/auth-secrets.R`, `R/proc-spawn.R`, `R/proc-supervise.R`,
`test-proc-spawn.R`, `test-proc-supervise.R`, `test-http-reactor.R`, `test-zzz.R` and
`dev/ci/test-by-file.R`: no lints (`task2-fix1-lint.log`). Touched files and the D-019 section
are ASCII-only. Roxygen changed only in `@noRd` blocks; `isolated-check.R document` ran (exit 0) and
changed no file under `man/` and not `NAMESPACE` (`task2-fix1-document.log`).

Still to be confirmed by the hosted Windows run of the pushed commit: the items listed above
under "To be confirmed"; review round 1 changes nothing there.

### Review round 2 (Task CI-2)

The reviewer re-ran `^proc` (292), `^zzz$` (86), `^http` (698), `^proc|^zzz$` (378), lint on
the 8 files, and the full suite: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 6286 ]` once the P05 lane
had stopped editing. A first full run had 17 failures, all in `test-provider-registry.R`, which
P05 rewrote during that run; a copy of HEAD plus only the CI-2 files passed. The reviewer also
checked the processx and ps sources and the D-019 staging recipe. One finding:

1. Major, accepted. Round 1's LF form went through `secret_variants()`'s
   `nchar(out) >= min_len` filter like the other derived forms. Each CRLF becomes one character
   shorter, so a value just long enough to be redacted lost its LF form whenever the LF form
   fell under `gptr.redact_min_chars`. Such a value has n characters with n >= min, but n minus
   its k CRLFs is under min. Written verbatim, it was then echoed in clear, where HEAD had
   redacted it. Example: the 8-character `"Ab3\r\nXy9"` echoed as `"pre Ab3\nXy9 post\n"`.
   Contract 3.1 defines `gptr.redact_min_chars` as the "shortest value-redacted secret", so it
   is a property of the registered value (`secret_register()` sets `redact` from the value's
   own length), not of each displayed form. Fixed as the reviewer proposed:
   `secret_variants()` filters the other forms by length, then adds the LF form whenever
   `nchar(v) >= min_len`. The LF form has at least half the value's characters (a CRLF is
   two). It is the value as the echo shows it, so it adds no redaction beyond the value
   itself. D-019 item 1 records the rule. The D-019 section now has 59 lines, not 56, and the
   round 1 staging recipe still picks it up whole. That was checked in the scratchpad: the
   staged file adds 59 lines to HEAD and changes nothing else.

What changed: `R/auth-secrets.R` (`secret_variants()`: the LF form is kept by the value's own
length, roxygen says so), `tests/testthat/test-proc-spawn.R` (new "proc_run echo redacts a CRLF
value whose LF form is under the redaction minimum": `gptr.redact_min_chars = 8`,
`"Ab3\r\nXy9"` written verbatim, echoed with `final = TRUE`, no part of the value shown),
`dev/DEVIATIONS.md` (D-019 item 1).

Red (actual): `^proc-spawn$` `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 152 ]`
(`task2-r2fix-red-proc-spawn.log`). It failed at `test-proc-spawn.R:416`, `:417` and `:418`:
"Ab3" and "Xy9" were in the echo, and the text was not `"pre [secret:EDGE_TEST_TOKEN] post\n"`.

Green (actual):

- `^proc-spawn$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 155 ]` (`task2-r2fix-green-proc-spawn.log`).
- `^auth`: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 1005 ]`. The skip is the keyring skip at
  `test-auth-store.R:75` (`task2-r2fix-green-auth.log`). This filter covers redaction, the late
  check and scrub.
- `^http`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 698 ]` (`task2-r2fix-green-http.log`).
- `^proc|^zzz$` final: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 381 ]`, which is 378 + 3
  (`task2-r2fix-green-final.log`).
- Full unfiltered offline suite (`isolated-check.R test '.'`, with the concurrent P05
  working-tree edits): `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 6289 ]`, exit 0. That is the
  reviewer's 6286 + 3, and the skip is the keyring skip at `test-auth-store.R:75`
  (`task2-r2fix-full.log`).

Lint: `isolated-check.R lint` on `R/auth-secrets.R`, `R/proc-spawn.R`, `R/proc-supervise.R`,
`test-proc-spawn.R`, `test-proc-supervise.R`, `test-http-reactor.R`, `test-zzz.R` and
`dev/ci/test-by-file.R` found no lints, exit 0 (`task2-r2fix-lint.log`). A first lint run
flagged the new test's 101-character title; the title was shortened. The touched files and the
D-019 section are ASCII-only. Roxygen changed only in a `@noRd` block, so there was no
`document` run.

Still to be confirmed by the hosted Windows run of the pushed commit: the items under "To be
confirmed" above. Review round 2 changes none of them.

## Task CI-3 - Remaining hosted failures on Ubuntu, LC_ALL=C and Windows

Hosted evidence (job logs fetched with `gh api .../actions/jobs/<id>/logs`): run 37193999181 on
`489eb0b` (complete) and the jobs of run 37195622025 on `95dd9b8` that had completed when read
once (its Windows release job was still running; not waited for).

| Failure | Where | Cause |
|---|---|---|
| `test-provider-registry.R:970` "an overload before any delta is re-sent by P04's reactor on the same transfer": `exists(id, envir = r$transfers)` TRUE | 489eb0b: Ubuntu release, devel, oldrel-4, LC_ALL=C (`[ FAIL 1 \| WARN 0 \| SKIP 11 \| PASS 8249 ]` each); 95dd9b8: Ubuntu release, no-Suggests, devel, oldrel-1 (`[ FAIL 1 \| WARN 0 \| SKIP 15 \| PASS 8454 ]` each); earlier the connections job of run 37176542781 | a test race, not a product bug. The normaliser emits `done` at `message_stop` (from `on_bytes`); P04 forgets the transfer only when curl reports the end of the body. The mock writes the last event and the chunked terminator `0\r\n\r\n` as two writes, and on hosted Linux curl often read the terminator in the next pump iteration, after `reactor_pump(until = done)` had returned. Same diagnosis as P05 Task 11's "possible timing flake" note. Not locale-specific: the LC_ALL=C job failed on 489eb0b and passed on 95dd9b8 |
| `test-auth-redact.R:934` "scrub rereads after acquiring locks and releases locks after write errors": "Expected `gptr_scrub(f, dry_run = FALSE)` to throw a error." | 489eb0b: Windows release and oldrel-4 (`[ FAIL 1 \| WARN 0 \| SKIP 22 \| PASS 8196 ]` each); 95dd9b8: Windows oldrel-4 (`[ FAIL 1 \| WARN 0 \| SKIP 26 \| PASS 8401 ]`) | non-portable test: the `write_atomic` mock compared the path with `normalizePath(f)`, which uses backslashes on Windows (`winslash = "\\"` by default), while `scrub_files()` hands `write_atomic()` `normalizePath(winslash = "/")` paths, so the synthetic failure never fired. The same comparison at `:846` ("scrub holds session and document writer locks throughout replacement") never matched on Windows either, so its lock expectations passed there without running |
| NOTE "checking for detritus in the temp directory": `Rscript*` files | Windows release and oldrel-4 (9 files each, 489eb0b), Windows oldrel-4 again (9 files, 95dd9b8), Ubuntu devel once (`Rscript2b1c.Mup7ui`, 95dd9b8) | not fixed, see open items. A NOTE does not fail the gate (`error-on: "warning"`) |
| `test-http-sse.R:126` INFRA-23 CPU `1.060 >= 1.000` | Windows release, only in the non-gating diagnostic stream; the test passed in R CMD check of both Windows jobs | not fixed, see open items |

The Windows release hang is gone. The diagnostic stream of job 111411943327 ran every file in
611 s ("files with failures: test-auth-redact.R, test-http-sse.R"), and R CMD check ran the tests
in 498 s and wrote `Status: 1 ERROR, 1 NOTE`; oldrel-4 wrote the same status after 519 s. The
CI-2 items to confirm: `test-proc-spawn.R` (0 failed, 3 skipped, 142 passed), `test-proc-supervise.R`
(0 failed, 140 passed) and `test-http-reactor.R` (0 failed, 2 skipped, 193 passed) pass in the
Windows release stream, and R CMD check on both Windows jobs failed only at `test-auth-redact.R:934`.
macOS release passed in both runs, including the INFRA-01 gap test (`:557`) that CI-1 left open;
its cause stays unexplained (two passing runs do not explain the earlier failure).

What was built (tests only; no product, workflow or roxygen change):

1. `tests/testthat/test-provider-registry.R`: the overload test no longer reads the transfer
   table at the instant `done` fires. It pumps, bounded at 30 s, until P04 has forgotten the
   transfer, then checks that the late end of the body added no second `done` and that no reactor
   task is left. New test "a transfer whose terminal event precedes the end of its body is
   still released": with `local_mocked_bindings()` on `reactor_curl_event()` and
   `reactor_multi_run()`, every curl `done` event is held until the next pump iteration, which
   reproduces the hosted Linux order deterministically on any OS. The test asserts that the
   order took effect (the transfer still exists when `done` fires), then that the transfer is
   forgotten within the bounded pump, no held event is left, the events are `start`,
   `retry_start`, `retry_end`, three `text_delta`, `done`, there is exactly one `done`, the mock
   saw two requests, and no task is left.
2. `tests/testthat/test-auth-redact.R`: both `write_atomic` mocks compare
   `path_key(path)` with `path_key(f)` (IC-51 path keys: forward slashes, symlinks resolved,
   lower case on Windows and macOS). The lock test counts its matches and expects exactly one
   rewrite, so a comparison that never matches can no longer pass without running its
   expectations.

Adaptations: none against a plan literal. Neither test is a plan literal (the overload test
comes from P05 Task 10, the two scrub tests from P03's scrubber task), and both files are
committed and owned by no plan lane in progress. The bounded wait does not weaken the test. A
transfer that is never forgotten still fails: in the negative control below, both pump
expectations fail after 30 s. The bound follows conventions section 7 (no wall-clock bound
under 5 s). No D-entry: no product or contract behaviour changed.

Red (actual):

- `^provider-registry$` with the new test written in the old test's form (`expect_false(exists(
  id, envir = r$transfers))` right after `done`): `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 721 ]`. The
  failure is at `:1000` with the hosted message ("Expected `exists(id, envir = r$transfers,
  inherits = FALSE)` to be FALSE", actual TRUE) (`task3-red-provider-registry.log`). The unchanged
  original test passed locally: a probe ran it 20 times on macOS, and the transfer was gone when
  `done` fired every time (script `race-probe.R` in the session scratchpad).
- Windows path comparison, simulated on macOS (`task3-red-scrub-winpath-sim.log`, script
  `scrub-winpath-sim.R` in the scratchpad). The `:931` mock was given the Windows form of
  `normalizePath(f)` (backslashes). Result: "Expected `gptr_scrub(f, dry_run = FALSE)` to throw a
  error.", the hosted message. The path-key comparison given the backslash form of `f` passed.
  The Windows failure itself cannot be reproduced on macOS.

Green (actual, `isolated-check.R`):

- `^provider-registry$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 725 ]`, which is 716 + 1 + 8: one
  added expectation in the overload test, whose `expect_false` became the pump's `expect_true`,
  and 8 in the new test (`task3-green-provider-registry.log`).
- `^auth-redact$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 405 ]`, 404 + the rewrite counter
  (`task3-green-auth-redact.log`).
- Both filters under `LC_ALL=C LANG=C` (`Sys.getlocale("LC_CTYPE")` is `C`): `[ FAIL 0 | WARN 0 |
  SKIP 0 | PASS 1130 ]` (`task3-green-clocale.log`).
- Negative control on a scratch `git archive HEAD` copy with this task's registry test file,
  where `reactor_on_done()` never forgets a finished 2xx transfer: `[ FAIL 2 | WARN 0 | SKIP 0 |
  PASS 723 ]`, at `:972` and `:1006` (both bounded pumps return FALSE)
  (`task3-negctl-no-forget.log`).
- Neighbours `^(provider-|auth-|http-reactor$)` (every user of the reactor glue, the mock server
  and the scrubber): `[ FAIL 0 | WARN 0 | SKIP 7 | PASS 3672 ]`. The skips are the keyring skip
  (`test-auth-store.R:75`), the four "default cache_policy of builtin:prompt is not loaded" skips
  and the two "P06's session_run() and P07's request.build are not loaded" skips
  (`task3-neighbours.log`).
- Full unfiltered offline suite (`isolated-check.R test '.'`, HEAD `95dd9b8` plus this task's
  changes and the concurrent P06 and P09 working-tree edits): `[ FAIL 0 | WARN 0 | SKIP 10 |
  PASS 8835 ]`, exit 0. The skips are the 7 above plus the three gated live round trips
  (`test-live-anthropic.R:6`, `test-live-google.R:6`, `test-live-openai.R:6`)
  (`task3-full.log`).

Lint: `isolated-check.R lint` on `test-provider-registry.R` and `test-auth-redact.R` found no
lints (`task3-lint.log`). Both files are ASCII-only. No roxygen or export change, so there was
no `document` run.

Logs: `dev/.validation/CI/task3-*.log`. The hosted job logs are not in the repository; refetch
them by job id: 111411943172, 111411943314, 111411943327, 111411943330, 111411943420,
111411943427 (run 37193999181) and 111416799359, 111416799388, 111416799402, 111416799424,
111416799425 (run 37195622025).

To be confirmed by the hosted run of the pushed commit: every Ubuntu job (release, devel,
oldrel-1, oldrel-4, no-Suggests, LC_ALL=C) and the connections job pass `test-provider-registry.R`,
and both Windows jobs pass `test-auth-redact.R`. With those, the R CMD check jobs should report
`Status: OK` (Ubuntu) or a detritus NOTE only (Windows).

Open items:

- INFRA-23 on hosted Windows: 20,000 deltas took 1.060 s of CPU once (Windows release,
  diagnostic stream of job 111411943327). The same test passed in R CMD check of both Windows
  jobs. Locally (macOS, R 4.5.0) it takes 0.30-0.33 s: splitting about 0.17 s, `json_decode()`
  of each event about 0.22 s. The 1 s target is named by the spec (decomposition P04 acceptance
  5), so this task did not change the test. The hosted Windows runner is near the target. A P04
  decision is needed: optimise the SSE split and decode path, or state how INFRA-23 is measured on
  slow hosted runners. The diagnostic step does not gate the job.
- Temp-directory detritus NOTE. The `Rscript*` names match the temporary file that the Rscript
  front end writes for `-e` expressions and deletes after R exits. This is from reading R's
  front end and is not verified on Windows. Many tests kill `Rscript --vanilla -e ...` children
  (for example the `Sys.sleep(30)` children in `test-proc-spawn.R`, `test-proc-supervise.R`,
  `test-http-reactor.R`, `test-ext-check.R`, `test-session-live.R`, and the real children of
  `test-provider-registry.R`), so the front end cannot delete the file. Suggested fix, to be
  verified on Windows: start every child the test kills with TMPDIR, TMP and TEMP in a
  `withr::local_tempdir()`, as `local_mock_server()` already does, or from a script file instead
  of `-e`. CRAN skips these tests (`skip_on_cran()`), and the gate fails only on warnings.

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

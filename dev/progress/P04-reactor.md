# P04 Task 6: reactor core

Owner: requirements_audit. Scope: `R/http-reactor.R` and
`tests/testthat/test-http-reactor.R`. Tasks 8/10/11 later extend the transport
placeholders; this task does not implement child pipes or HTTP transfers.

## Task 6 implementation and evidence

- Read P04 Task 6 and interface contract section 8.2 / IC-57. The reactor remains
  an ordinary top-level pump function, with monotonic timing, one FIFO tool per
  iteration, explicit nested-run admission, callback busy marks and balanced
  cleanup during interruption.
- Dependency check found `registry_diagnostic()` was not part of P02 Task 2.
  Reported this to the coordinator and P02 owner; no stub was added. The actual
  P02 Task 4 function arrived before the first green run and is exercised by an
  additional integration test.
- RED: wrote the plan's 15 tests before `R/http-reactor.R`; all 15 tests errored
  on missing reactor APIs or diagnostic bindings. Saved local evidence in
  ignored `dev/.validation/P04-T06/red.log`.
- GREEN: implemented the core; the original tests passed 55 expectations with
  zero failures, errors, test warnings or skips.
- Added coverage for callbacks cancelling pending work without resurrection,
  task/tool interrupts propagating while clearing busy/depth/allow/tool stacks,
  and callback failures reaching the real registry diagnostic store. The
  focused suite passed 71 expectations with zero failures, errors, warnings or
  skips. Exact command inside the isolated runner:

  ```r
  testthat::set_max_fails(Inf)
  res = devtools::test(filter = "^http-reactor$", reporter = "summary")
  tab = as.data.frame(res)
  print(colSums(tab[c("failed", "error", "warning", "skipped", "passed")]))
  stopifnot(sum(tab$failed) == 0, !any(tab$error))
  ```

- Scoped lint after `pkgload::load_all(quiet = TRUE)` reports zero findings in
  the two owned files. A first lint attempt without loading the namespace
  reported unresolved package symbols; loading the actual package fixed that
  harness issue, without suppressions or source changes.
- All R invocations used `Rscript --vanilla`, the ignored project-local library,
  and fresh outer HOME, R_USER_CONFIG/DATA/CACHE_DIR, XDG, Windows-equivalent and
  project directories before package loading. This prevents load-time orphan
  sweeps from seeing user marker files. Live tests were disabled, key variables
  cleared, and numerical workers bounded to two or fewer. The testthat package
  built-under-R-4.5.2 startup message is outside test results; host R is 4.5.0.
- No documentation generation, credential access, network calls or full-tree
  tests were performed in this lane.
- Independent review by plans_security_review with a disjoint reviewer found
  no actionable issue in the core scope. The review checked cancellation,
  reentry, interrupts and numeric boundaries; Task 8/11 transport placeholders
  were explicitly excluded. No plan/interface deviation was needed.
- Scoped Task 6 commit approved through the coordinator's Git lock; exact files
  are this log, the reactor source and its test file. No generated docs changed.

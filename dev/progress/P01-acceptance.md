# P01 integrated acceptance

Validation target: `eea1e369a1b4a5c64561bd52ff51f396099d0b72`.
This contains all 21 P01 tasks and the independently completed P04 stream
splitter. It excludes uncommitted P02 work. Tests below validate this exact
source snapshot; later branch changes require their own gates.

## Snapshot and local checks

- Created with `git archive <sha>` into a fresh temporary directory on
  2026-10-03. Exact local path and raw logs are in ignored
  `dev/.validation/P01-acceptance/`.
- Set `R_LIBS_USER` to the absolute project-local `dev/.library` path; used
  `Rscript --vanilla` and pinned roxygen2 7.3.3.
- `devtools::document()` exited 0. The subsequent loaded-namespace
  `lintr::lint_package()` reported no lints and exited 0.
- `Rscript --vanilla dev/ci/check-connections.R` exited 0: the full offline
  suite passed **1,599 assertions, 0 failures, 0 test warnings, 0 skips** in
  25.7 seconds, and the complete connection table matched its baseline.
  Synthetic loopback HTTP servers were allowed; no real provider requests or
  credentials were used.
- A startup diagnostic outside the test results reports that installed
  testthat was built under R 4.5.2; the running interpreter is R 4.5.0.
- First `devtools::check(args = c("--as-cran", "--no-manual"),
  error_on = "warning", document = FALSE)` found one installed-test error:
  the IRkernel predicate test clears `TESTTHAT` and `_R_CHECK_PACKAGE_NAME_`,
  preventing `local_mocked_bindings()` from inferring its package. It had
  passed in the source tree because pkgload supplied that inference.
- Added explicit `.package = "gptr"` to that test's mock call. The corrected
  snapshot is the target SHA above plus this one-line test change; runtime
  source is unchanged. The complete installed-package check then passed in 35.1 seconds:
  **0 errors, 0 warnings, 0 notes**. The only two test skips are source-tree
  metadata checks when running the installed package. The correction is
  committed in `d4aabfb`; it also passed independent review. Hosted results at
  the original SHA cannot validate this correction.

## Hosted validation

The snapshot was pushed to the implementation branch and draft PR #4.
[GitHub Actions run 37165877166](https://github.com/Broccolito/gptr/actions/runs/37165877166)
has the exact target SHA. Its completed jobs expose the pre-correction
installed-test failure. Windows additionally found CRLF completion markers were
not recognised; oldrel-4 Linux found the plan's `str(big)` negative control did
not copy on that interpreter. The connection gate passed. Benchmark/copy-safety
jobs without their later-plan suites are scaffolding successes, not those
later acceptance results.

The two portability corrections are recorded in D-009. Actual local regression:
FAIL 3 / PASS 40 before the CRLF change, then **FAIL 0 / WARN 0 / SKIP 0 /
PASS 43**, with both changed files lint-clean and independent review accepted.
The old-R negative control now retains an explicit alias, which must force the
next edit to copy; package functions remain subject to the same zero-copy rule.

P01 acceptance remains pending a new hosted run containing all corrections.
The macOS runner's extra NOTE names Apple system services creating temporary
files; it is recorded as runner noise, not silently reported as a package pass.

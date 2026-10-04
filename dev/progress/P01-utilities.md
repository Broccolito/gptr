# P01 utilities task evidence

Tasks 9–12 are implemented in the shared implementation checkout after Task 8
commit `e6fc6c3`, under an explicit handoff from the foundation owner. Commands
run from the repository root with `R_LIBS_USER="$PWD/dev/.library" Rscript
--vanilla`; roxygen2 is pinned to 7.3.3. Raw logs remain ignored under
`dev/.validation/P01-Tnn-{red,green}.log`. All tests are offline and no
credentials are read. Shared documentation generation and Git commits are
serialized with the foundation owner.

## Task 9 — calibrated token estimator

Created `R/utils-tokens.R`, its focused tests and the 12-sample token fixture.
The estimator uses content classes and Unicode weights, supports provider image
formulas and updates the session multiplier only for sufficiently large samples.

- Red: `testthat::set_max_fails(Inf); devtools::test(filter = "^utils-tokens$")`:
  FAIL 5, WARN 0, SKIP 0, PASS 1; missing estimator functions as expected.
- Green: `devtools::document(); devtools::test(filter = "^utils-tokens$")`:
  FAIL 0, WARN 0, SKIP 0, PASS 20; documentation exits successfully.
- Green command additionally asserts zero failed expectations and no test errors
  from the returned testthat results.
- Installed rtiktoken 0.11.0.3 exactly reproduces all 12 fixture counts with
  `get_token_count(text, model = "o200k_base")`. This does not establish the
  later P07 benchmark's baseline or timing gate.
- Testthat emits its existing package-build warning outside test results
  (built under R 4.5.2, runtime R 4.5.0); test warnings remain zero.
- Commit: `feat(utils): add the calibrated token estimator and its fixture`.

## Task 10 — output budgets and listings

Created `R/utils-text.R` and focused tests for token-budgeted head/tail output,
session/process output stores, redacted spill-file recovery, terminal cleanup
and listing output. The session lookup falls back to the process store and then
the spill file, as IC-71 requires.

- Red filter `^utils-text$`: FAIL 8, WARN 0, SKIP 0, PASS 0; missing functions.
- Green after documentation: FAIL 0, WARN 0, SKIP 0, PASS 40, with zero-failure
  assertions on the returned test results.
- Shared `NAMESPACE` diff contains only `S3method(print,gptr_listing)`.
- Focused `git diff --check` passes. The pre-existing testthat build-version
  warning remains outside test results.
- Commit: `feat(utils): add output truncation, the out store, spill files and listings`.

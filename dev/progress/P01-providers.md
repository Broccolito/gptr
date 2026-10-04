# P01 provider and test infrastructure implementation

Owner: scientific_value. Scope: tasks 14-18 only. No Task 13 edits.

## Task 14 - provider events and accumulator

- Red: `Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "provider-events")'`
  produced FAIL 4 / WARN 0 / SKIP 0 / PASS 0 (missing implementation).
- Added sparse partial-block and terminal-error regressions. The plan implementation
  failed the sparse partial-block test with a subscript-out-of-bounds error:
  FAIL 1 / WARN 0 / SKIP 0 / PASS 16.
- Fixed lookup of absent indexed buffers so the intended implicit-buffer path works.
- Green: `Rscript --vanilla -e 'devtools::test(filter = "provider-events", stop_on_failure = TRUE)'`
  produced FAIL 0 / WARN 0 / SKIP 0 / PASS 17, exit 0. Includes the 100,000-delta
  performance bound (under 5 seconds) and terminal-message preservation.
- R startup reports the installed testthat binary was built under R 4.5.2;
  this is outside the test reporter (zero test warnings).
- Commit: `6b7163e` (`feat(provider): add INFRA-02 events and linear-time accumulator`).

## Task 15 - offline scripted provider and canonical classifiers

- Red: `Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "provider-fake", stop_on_failure = TRUE)'`
  produced FAIL 15 / WARN 0 / SKIP 0 / PASS 0, exit 1 (missing implementation).
- Applied the accepted IC-74 contract to the tests before implementing: `noul`
  returns `prob`, probability collections are named numeric vectors and score
  legends are named character vectors. The old Jev wire shape is not canonical.
- Added probability/schema rejection, request-order ties and cancellation tests.
  The historical plan source produced FAIL 13 / WARN 0 / SKIP 0 / PASS 73.
- Corrected canonical normalization, finite/bounded probabilities and sums, unique
  question/option names, and reordered probability vectors to request order.
  Synthetic fake responses make no empirical calibration claim (`NA`). Optional
  provider/API/locality/model identity metadata is included. The fake uses
  `classify$run(model, state, questions, opts)`; IC-74's five-argument `parse`
  callback applies to HTTP adapters, which this task does not implement.
- Fixed two cancellation failures: pre-aborted streams must not invoke their
  script or consume a request; abort during the initial delay must emit `start`
  before its single terminal error.
- Green: `Rscript --vanilla -e 'devtools::test(filter = "provider-fake", stop_on_failure = TRUE)'`
  produced FAIL 0 / WARN 0 / SKIP 0 / PASS 99, exit 0.
- Generated public documentation with pinned roxygen2 7.3.3. All four owned source/test
  files passed scoped lint. Combined provider-event/provider-fake tests passed 116 assertions
  with FAIL 0 / WARN 0 / SKIP 0, exit 0. Task 15 is recorded in this commit.

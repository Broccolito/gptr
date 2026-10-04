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

## Task 16 - shared fake and project helpers

- Red: focused provider-fake tests failed 4 times (missing helper functions),
  with 99 pre-existing assertions passing. The planned helpers made 124 assertions pass.
- A new isolation regression then failed 4 assertions: a `../` fixture path could
  escape the temporary project, and unnamed/duplicate fixture names were accepted.
  The helper now validates every fixture path and name before writing any content.
  The regression's attempted outside file was itself in a managed temporary directory.
- Green: provider-fake tests passed 128 assertions, FAIL 0 / WARN 0 / SKIP 0, exit 0.
  Explicit UTF-8 fixture reads follow the conventions. No public documentation changed.

## Task 17 - fresh-process copy-safety harness

- Red: utils-hash reported 3 missing-harness failures plus the existing random-port
  sandbox restriction (30 assertions passed). Local-socket escalation is required for
  that pre-existing test; the suite uses no external network.
- Implemented the fresh-Rscript harness; the initial scoped suite passed 39 assertions.
  A new regression exposed a false success when a child printed its final marker but
  exited nonzero (FAIL 1 / PASS 39). The harness now checks exit status as well as the
  marker. Generated loader paths use R quoting, including apostrophes in checkout paths.
- Green: escalated offline utils-hash tests passed 40 assertions, FAIL 0 / WARN 0 /
  SKIP 0, exit 0 (2.6 seconds). This includes the str() negative control, fingerprint()
  and save_rds() non-retention checks, and edits during/after a simulated run.
- Scoped lint on helper-tracemem.R and test-utils-hash.R passed. No public docs changed.

## Task 18 - synthetic HTTP fixture server

- Red: provider-fake tests failed 8 times (missing local_mock_server), with 128
  assertions passing. The planned scenarios then passed 187 assertions.
- Added regressions reproducing four failures across proxy inheritance, erased
  lexical callback bindings and a missing-parent orphan server. Fixed loopback-only
  proxy bypass, selected callback binding capture and missing-parent shutdown.
- A subsequent narrow review found malformed requests could terminate the child,
  and callback captures could retain unrelated frames through nested functions.
  New tests reproduced FAIL 4 / WARN 1 / PASS 195. The server now rejects invalid
  request lines/headers, duplicate/invalid Content-Length and transfer-encoding
  uploads, with 64 KiB header / 16 MiB body limits and a per-client error boundary.
  Nine malformed inputs are followed by a successful authorized request, which is
  the only request counted as scenario traffic.
- Callback capture preserves lexical parent/binding identity and recursively copies
  referenced functions and supported list/vector values. It strips source references
  (which otherwise retained unrelated source text), rejects explicit captured
  environments, connections, S4 objects and custom function attributes before spawn,
  and guards the optional codetools dependency. Tests cover a nested synthetic canary,
  shared mutable lexical bindings, original-function preservation and explicit rejection.
  This helper supports lexical captures, not arbitrary dynamic lookup or object cloning.
- Intermediate callback regressions caught an attribute-recursion overflow and a
  source-reference canary retention; both were corrected. A final function-attribute
  regression failed once, then passed after the explicit rejection was added.
- All fixture scenarios run serially with at most one server child; concurrent
  stream coverage uses three clients in that one child. The Jev System One fixture
  deliberately preserves wire shape for future adapter tests; fake_classify remains
  provider-neutral. No live endpoint or real credential is used.
- Final green: `Rscript --vanilla -e 'devtools::test(filter = "provider-fake", stop_on_failure = TRUE)'`
  (escalated only for loopback sockets) passed 211 assertions, FAIL 0 / WARN 0 /
  SKIP 0, exit 0, in 16.7 seconds. Includes the final function-attribute rejection.
- Scoped lint on helper-mock-server.R, fixtures/mock_server.R and test-provider-fake.R
  passed, as did `git diff --check`. No public documentation changed in this task.

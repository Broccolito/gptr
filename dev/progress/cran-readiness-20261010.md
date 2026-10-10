# CRAN readiness review, 2026-10-10

Current primary sources and a static working-tree audit were reviewed at HEAD `e5703be`.
No R process, build, check, installation or live request was run in this lane. This is
readiness guidance, not evidence that the current release tarball passes CRAN checks.

## Current rules and useful thresholds

| Area | Requirement or guidance | Primary source |
| --- | --- | --- |
| Distribution size | Data and documentation generally stay within 5 MB; documentation may be required to shrink to that maximum. Source tarballs should preferably stay within 10 MB. | [CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html) |
| Check resources | At most two simultaneous cores/threads. Minimize checking CPU time; examples should take only a few seconds. No universal five-minute total-check limit was stated in the reviewed policy/manual. | [CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html) |
| Network and state | Handle unavailable Internet gracefully; obtain consent for third-party session transmission. Restrict writes to permitted temporary/user directories and close started external programs. | [CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html) |
| Installed size | The current checker reports installed size above `5 * 1024` KiB, using `du -k`; it lists top-level directories above 1 MiB. This is a checker diagnostic, distinct from the policy's documentation/data guidance. | [R-devel checker, lines6454-6494](https://svn.r-project.org/R/trunk/src/library/tools/R/check.R) |
| Timing instrumentation | `_R_CHECK_TIMINGS_=0` records install/check-section timings. `--as-cran` enables example timing reports above five seconds; keep `*-Ex.timings` and per-test/vignette logs. Installation should preferably avoid Internet access. | [Writing R Extensions: check timing](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#Check-timing), [portable packages](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#Writing-portable-packages) |
| Dependencies and vignettes | Declare optional dependencies and guard their use when absent. For `knitr::rmarkdown`, both `knitr` and `rmarkdown` belong in `VignetteBuilder` and at least `Suggests`. | [Writing R Extensions: DESCRIPTION](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#The-DESCRIPTION-file) |
| Submission conventions | Use informative Title/Description text, `foo()` for function names, quoted external-software names, appropriate author/copyright roles and identifiers. | [CRAN submission checklist](https://cran.r-project.org/web/packages/submission_checklist.html) |

The checker's section timeouts are configurable (`_R_CHECK_ELAPSED_TIMEOUT_`,
`_R_CHECK_TESTS_ELAPSED_TIMEOUT_`, `_R_CHECK_ONE_VIGNETTE_ELAPSED_TIMEOUT_`); local
runner timeouts are not universal CRAN acceptance limits. Current R-devel also treats
maintainer-only incoming metadata as OK (checker lines6584-6593), rather than generating
the historical maintainer-only NOTE.

## Current static findings and changes

- [DESCRIPTION](../../DESCRIPTION#L72) now has `VignetteBuilder: knitr, rmarkdown`, matching
  [the shipped engine](../../vignettes/getting-started.Rmd#L3). Both packages were already
  suggested. Only this metadata field was edited; `Config/roxygen2/version: 8.1.0` was
  preserved. Matching guards in [release tooling](../release/lib.R#L569), its existing
  [self-test](../release/tests/test-description.R#L6), and [test-zzz](../../tests/testthat/test-zzz.R#L34)
  were aligned. Root validation passed: package metadata tests 88 assertions and release
  metadata self-tests 19 assertions, with zero test failures/warnings/skips. Documentation
  and release-file audits each reported zero problems; three changed R files lint clean.
  The installed development testthat emitted its known R-build-version startup warning
  outside test results. Evidence: ignored `dev/.validation/live-20261010/cran-metadata.log`.
- [.Rbuildignore](../../.Rbuildignore#L6) excludes development tooling, pkgdown output,
  `.orig` sources, `.secrets`, environment files and machine-local directories. Inspect the
  actual final tarball listing as well; ignore patterns alone do not prove its contents.
- Static logical file sizes: `R/` 3,091,650 bytes; `man/` 376,059 bytes, including nine
  figure assets totaling 223,101; `inst/` 143,804; `tests/` 3,735,046; shipped `vignettes/*.Rmd`
  130,230. These measurements do not include build products or compressed/lazy-load
  artifacts and are not installed-package or source-tarball measurements.
- There are 14 shipped Rmd guides, with zero executable R chunk headers. The existing
  [precompute helper](../release/lib.R#L454) knits their excluded `.orig` sources offline,
  in temporary directories, against an installed package. Its 60-second aggregate budget
  is a project gate.
- [Example validation](../release/lib.R#L352) uses one fresh process per Rd page, cleared
  credentials, temporary home/project paths, closed-port HTTP proxies, replay mode, and
  connection/process/file cleanup checks. Its five-second page budget is a project gate;
  its 120-second subprocess timeout and 900-second installation timeout are local guards.
- [DESCRIPTION](../../DESCRIPTION#L32) declares R >=4.2, optional external programs,
  UTF-8 and no compilation. No configure/cleanup/Makevars/install.libs.R files were found.
  [`.onLoad`](../../R/zzz.R#L5) dispatches initialization and built-in registration; this
  narrow inspection does not replace an isolated install/load test.
- [CI](../../.github/workflows/R-CMD-check.yaml#L40) uses `--as-cran --no-manual`, suppresses
  incoming checks and requires a written check status. It is useful continuing validation;
  final incoming/manual/platform checks still need fresh evidence.
- [cran-comments](../../cran-comments.md#L55) now says 14 guides and labels its 0/0/0 local
  result as historical. The pending current tarball/win-builder check must replace that
  record before submission. Its dated reverse-dependency result also needs refreshing.
  Old five-guide/knitr-only plan descriptions were not edited.

## Periodic and final gates

Reuse the existing release tooling rather than adding another framework. At meaningful
release-boundary changes, run `dev/release/check-docs.R` and
`dev/release/check-files.R all` plus focused isolated tests/lint. When examples or vignette
sources change, add `check-examples.R` and `precompute.R --check` sequentially. Keep the
existing full CI matrix. Record the slowest example and vignette aggregate time from
these scripts; do not hide regressions by raising their budgets.

Periodically, in an available single local validation slot, use the existing isolated
check wrapper with `_R_CHECK_TIMINGS_=0` and retained vignette logs. Save check status,
installation/example/test/vignette times, built tarball bytes, installed `du -k` size and
largest installed directories beside its commit/artifact hash. Flag source growth near
10 MB, documentation/data near 5 MB, and the checker's installed-size diagnostic; review
changes against prior measurements. Do not equate CI's 45/120-minute job timeout with
package checking time because it includes setup and dependency installation.

For submission, build once and check the exact upload tarball with current R-devel
`R CMD check --as-cran`, then verify Windows and reverse dependencies. Resolve warnings
and significant notes. Keep the checked artifact hash and logs; change no shipped input
after that gate. [CRAN Repository Policy](https://cran.r-project.org/web/packages/policies.html)
defines this final tarball gate. Include manual validation in the final check, or separately
record it when a local `--no-manual` run is necessary. Refresh submission comments with
actual results and submit only after the maintainer's final authorization.

## Historical stream-order review: cross-block redaction assessment

This source-review candidate was subsequently reproduced on both the earlier and patched
versions, then corrected by `b8f8386`: text blocks now retain canonical separators and
buffered tails flush before tool/pause boundaries. The synthetic console regressions pass
(154 assertions, no failures/warnings) and changed files lint clean. See
[live harness evidence](live-harness-20261010.md#console-content-boundaries). The analysis
below records the earlier hypothesis; it is not an outstanding finding or a new assessment.

The patch keeps secret redaction per content index:
[run_on_event](../../R/agent-run.R#L1133) creates one redactor per block;
[run_flush_deltas](../../R/agent-run.R#L1155) flushes that redactor at its end and removes
it before emission. [redact_stream](../../R/auth-redact.R#L462) still enforces its hold
limit and fail-closed state, and its flush runs the normal redactor. The existing
[synthetic regression](../../tests/testthat/test-stream-order.R#L111) exercises a complete
registered value split across deltas within one block.

A registered value deliberately split across two adjacent text blocks needs a separate
offline regression: each redactor sees only a fragment, and event payload redaction
[visits individual string fields](../../R/ext-events.R#L169). The console's
[message-text helper](../../R/console-render.R#L440) concatenates text blocks without a
separator. Source inspection predicts that the assembled display could contain the
registered literal even though neither individual update contains it. This has not been
executed in this lane and is not a confirmed new vulnerability. At pre-patch `8b93b1e`,
redactors were already independent and were flushed separately at completion, so the
same candidate spans a pre-existing boundary. The patch moves their flush earlier.

Suggested case to append temporarily to the existing offline harness when its R slot is
available (synthetic material only):

```r
test_that("a registered synthetic value cannot reappear across text blocks", {
  local_gptr_options(verbose = 0L)
  updates = local_events("message_update")
  run = stream_order_run()
  secret = paste0("offline-", strrep("FAKE", 8L))
  secret_register(secret, "STREAM_ORDER_TOKEN", source = "test")
  stream_order_block(run, 1L, substr(secret, 1L, 13L))
  stream_order_block(run, 2L, substr(secret, 14L, nchar(secret)))
  stream_order_finish(run)
  expect_false(grepl(secret, stream_order_text(updates(run$shell)), fixed = TRUE))
})
```

Run it both before and after the patch, including a captured console assertion, before
classifying the result or changing redaction. Keep hold-limit failure tests and same-block
secret protection intact. No security runtime change was made during this review.

## Current R and exact-artifact checkpoint

Primary sites currently identify R 4.6.1 as release and an Apple Silicon R-devel 4.7.0 build.
This machine's live fixtures use R 4.5.0. Local diagnostics must state that version; they do
not replace current-release/R-devel checks. Published macOS framework binaries target the
system framework location. An isolated source build with a private prefix, or an official
builder check of the exact artifact, avoids replacing the user's R installation.
[CRAN macOS](https://cran.r-project.org/bin/macosx/),
[nightly builds](https://mac.r-project.org/),
[R administration](https://cran.r-project.org/doc/manuals/r-devel/R-admin.html#Frameworks)

`dev/ci/isolated-check.R check` rebuilds its source and uses `--no-manual`; it does not take
a nominated archive. For the final artifact gate, export the committed shipping inputs,
build once, and run `R CMD check --as-cran` on that exact archive with the manual and incoming
checks enabled. Retain its SHA256, bytes, archive listing, installed sizes, section/example/
test/vignette timings, and actual R version. Repository CI independently rebuilds the
checkout and is not proof of byte-identical archive validation.

The committed runtime `4e66376` installed with default byte compilation in 16.14s and peaked
at 293 MiB process-family RSS. This is an installation diagnostic, not a fresh tarball check
or total package-size measurement. No source-size or timing threshold is relaxed.

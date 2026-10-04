# P02 integrated acceptance

Initial immutable target: `e2a5f575197cb4ea5a2005a757d993017c7783a8`.
This contains P01/P02 plus committed P03 tasks 1–3 and 6–10, P04 tasks 1–7,
and P05 usage/pricing. It excludes later uncommitted work. Raw logs and the
exact archive path are in ignored `dev/.validation/P02-acceptance/`.

- Pinned documentation generation exited 0; loaded-namespace package lint
  exited 0 with no findings.
- The full offline suite passed **4,348 assertions, 0 failures, 0 test warnings,
  1 expected skip** (keyring is installed). Duration: 73.3 seconds. The
  separate full-table connection gate failed (3 before, 5 after).
- A diagnostic rerun repeated the passing assertions and identified the two
  connections as processx supervisor FIFOs. These intentionally live until R
  exits outside check mode. No provider or user data was used.
- IC-60 already requires supervision off under R CMD check. The standalone
  gate now applies that setting in a restored local option scope; no connection
  is ignored. Its new tests first failed 2 assertions and then passed all 9,
  retaining the deliberate leaked-connection negative control.
- Installed-package `devtools::check(args = c("--as-cran", "--no-manual"),
  error_on = "warning", document = FALSE)` passed in 1m 28.5s with **0 errors,
  0 warnings, 0 notes**. The inherited devtools offline-check settings disable
  CRAN incoming/remote incoming checks and optional-Suggests enforcement;
  `NOT_CRAN=true` keeps the synthetic process tests enabled. This is local
  package acceptance, not CRAN submission/server acceptance.
- A subsequent immutable checkpoint must include the gate correction and pass
  the full connection comparison before hosted acceptance is claimed.
- The external startup diagnostic that testthat was built under R 4.5.2 remains
  separate from test warnings (host interpreter R 4.5.0).

P01 hosted portability and full P02 acceptance remain pending; component-level
checks and this initial suite do not close those gates.

## Corrected coherent checkpoint

Target: `55ec31dc99f2d991b4b2d495320b76af25735bf6` (includes the reviewed
history and rate-limiter components committed between the initial snapshot and
the harness correction). This is a fresh `git archive`, with its own receipt in
`final-snapshot.json`; no uncommitted runtime source was overlaid.

- `Rscript --vanilla dev/ci/isolated-check.R connections` passed **4,474
  assertions, 0 failures, 0 test warnings, 1 expected keyring-installed skip**
  in 74.7 seconds. The complete connection table remained identical.
- `Rscript --vanilla dev/ci/isolated-check.R check <isolated-output>` passed
  in 1m 26.6s with **0 errors, 0 warnings, 0 notes**. Same library, interpreter,
  offline flags and pre-load isolation as the initial snapshot.
- Checkpoint published to draft PR #4. Hosted run
  [37167848633](https://github.com/Broccolito/gptr/actions/runs/37167848633)
  targets this exact SHA. Hosted jobs are in progress; later commits are not
  covered by these local results or by this hosted run.

## Hosted Linux findings at the corrected checkpoint

Completed Ubuntu release and LC_ALL=C jobs both report **FAIL11/WARN0/SKIP4/
PASS4443**. Credential-store tests cannot reclaim a dead-PID lock; process
cleanup reports false and retains markers, and the orphan-sweep fixture retains
children. These shared liveness symptoms are assigned to the dedicated Astra
portability lane, with Luna regression execution and a separate Astra review.
Windows oldrel-4 passed; other job states are recorded by their actual receipts.
Raw completed-job logs are under ignored `hosted/`. No cross-platform pass is
claimed from the successful local Mac gate or from a different hosted commit.

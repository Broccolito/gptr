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

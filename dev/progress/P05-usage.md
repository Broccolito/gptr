# P05 Task 1: usage records and dated prices

Owner: requirements_audit. Dependency-ready component using validated P01
conditions and `%||%`; this does not complete P05, M0 or M1. Task 9 remains
blocked on its actual catalog/model dependencies. Owned files are
`R/provider-usage.R`, `tests/testthat/test-provider-usage.R`, and this log.

## IC-74 reconciliation

- `usage_new()` keeps the contract's zero defaults for omitted legacy fields.
  Explicit `NA` or null observations remain unknown. `usage_as()` normalizes an
  absent record, empty R/JSON object, metadata-only or aggregate-only record to unknown counters,
  while retaining explicit reported totals, cost metadata and estimation status.
  A genuine partial legacy observation retains omitted-component zero defaults.
- Missing price evidence yields unknown cost. The historical constructor's zero
  defaults cannot establish that an unpriced request was free. An explicit zero
  rate establishes zero metered API charge even with unknown tokens; the model
  catalog must supply that rate from its evidence. Neither `local = TRUE` nor
  `locality = "local"` alone creates a zero price. This says nothing about compute
  or energy cost and also permits an explicitly free remote price.
- Known usage, rates and costs are nonnegative finite real scalars; unknowns are
  `NA`. Invalid values, dates, tier syntax and duplicate effective date/threshold
  records fail with typed errors. Documented cache-rate defaults remain 0.1x,
  1.25x and 2x the input rate.
- The latest price set effective on or before the request date applies. A request
  before the first known date has no applicable price; the older literal plan's
  extrapolation from a future price was intentionally removed. `default` and
  `<=Nk` remain base-tier labels as documented in the plan. Premium `>Nk` tiers
  apply strictly above the threshold. Unknown prompt size cannot choose among
  differing effective rates; identical rates across all possible covered tiers
  may still establish a price, including an all-zero local API rate.

## Test-first and review evidence

1. Wrote reconciled historical tests and focused IC-74 boundary tests before the
   source. Initial RED: 8 errors on missing usage/pricing APIs, 0 passes.
2. Implemented Task 1 only. Initial GREEN: 119 expectations, no failures/errors,
   test warnings or skips. Existing INFRA-20 dollar examples remain unchanged.
3. Independent review found the canonical empty JSON object and metadata-only
   usage paths still became known zeros. Added regressions first: RED 8 failed /
   126 passed, then GREEN 134. A further explicit-null-cost regression failed
   once before the targeted null-preservation fix. Review also identified that
   an observed aggregate total does not establish its component counts: the
   total-only regression failed once (137 passed), then passed after preserving
   its aggregate while leaving all components unknown.
4. Final focused GREEN: 138 expectations, 0 failures/errors/warnings/skips.
   The test includes the existing P01 JSON usage round-trip and explicit reported
   totals with unknown component observations. Both owned source/test files have
   zero scoped lint findings.

Exact focused command (within startup isolation):

```r
res = devtools::test(filter = "^provider-usage$", reporter = "summary")
tab = as.data.frame(res)
print(colSums(tab[c("failed", "error", "warning", "skipped", "passed")]))
stopifnot(sum(tab$failed) == 0, !any(tab$error))
files = c("R/provider-usage.R", "tests/testthat/test-provider-usage.R")
lint = lapply(files, lintr::lint)
print(lint)
stopifnot(all(lengths(lint) == 0))
```

All runs used `Rscript --vanilla`, the ignored local library, fresh HOME and
config/data/cache/project locations before package load, disabled live tests,
cleared key variables and at most two numerical workers. Local raw evidence is
ignored under `dev/.validation/P05-T01/`. The installed testthat built-under-R
startup message is outside the test warning counts. No credentials, real provider
calls, installations, full-tree tests or documentation generation were used.

Independent review: plans_security_review and a disjoint pricing reviewer.
Final corrected source has no remaining actionable finding in Task 1 scope.
The scoped commit uses the coordinator's serialized Git-only window; no generated
documentation changes are required for these internal helpers.

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

## Task 9 - Usage rows, roll-up and the process System 1 log

Built in `R/provider-usage.R` (appended): `usage_empty()` (plan literal, the 21 section 4.3
columns), `usage_row(msg, session, agent, parent_id, started, seconds, multiplier)`,
`usage_log_append(row)`/`usage_log()` (`the$s1_log`, append-only) and the private
`usage_rollup(rows)` (columns `group`, `requests`, `input`, `output`, `cache_read`,
`cache_write`, `cost` of the section 5.12 aggregated view), with helpers `usage_chr1()`,
`usage_time()`, `usage_rows_check()`, `usage_reported_cost()` and `usage_roots()`. The row's
model comes from the real Task 7 resolver (`model_resolve("<provider>/<model>", strict = FALSE)`,
which also resolves live fake providers); its cost from Task 1's `usage_cost()`/`price_select()`
on the request date (UTC). No roxygen export, so no `document` run.

State at start: `git status` was clean. The pre-pause Task 9 tests were **already committed**: the
Task 8 commit `7633ff1` swept the then-unstaged `tests/testthat/test-provider-usage.R` in (despite
its review note), so `HEAD`'s `^provider-usage$` run is red (FAIL 10) until this task is committed.
The Task 1 prefix is unchanged from `783c5b8` (checked with `git diff 783c5b8 7633ff1`).

Adaptations (reasons in brackets; behavioural ones also in D-015):

1. Test fixture: `local_priced_provider()` passes `prices` as a data frame (`price_rows()`), not
   a list of records [P02's `spec_model_rules()` requires `prices = "df"`; the earlier agent's
   correction, reflowed by me to the 100-character limit].
2. Tests beyond the plan's four blocks (earlier agent): unknown observations, price evidence and
   elapsed time; plan-CLI missing vs supplied-zero cost; `NA` propagation through roll-ups;
   inconsistent/cyclic ancestry; log validation before mutation and independent copies; no
   recycling of scalar arguments [IC-74, contract 4.3]. I reviewed them against the plan,
   contract 4.3/5.12/7.5/8.5 and 07 section 5 and kept them, then added 12 assertions after the
   first green (no separate red): log order across cached reads, route/request-id rejection in
   the log, and `agent`/`parent_id`/`session`/message-field validation in `usage_row()`.
3. Non-CLI cost only from price evidence; `NA` for an unresolved model or a date before the first
   price (the plan fell back to the message's legacy-zero `cost$total`) [IC-74]. The priced
   record is the resolved one after the request's pure `provider_preflight()` (fix round 1), so
   a bare local Ollama name with current `:latest` evidence costs 0 [07 section 5].
4. `tier` is `NA` when no tier applies (plan: `"default"`) [no price evidence, no tier].
5. `plan-cli` keeps the message's own reported `cost$total` (raw usage record), `NA` when absent
   or when the record is `estimated` (fix round 1); a canonical supplied `0` is a known zero
   [contract 4.3, 8.5 and IC-74]. Consumer: P20 adapters pass `cost = NULL` when the CLI reported
   usage without `total_cost_usd`.
6. Validated scalars (`started` must be one finite POSIXct or epoch seconds; the plan's
   `.POSIXct(as.numeric("bad"))` gave `NA` with a warning), typed `invalid_argument`.
7. `usage_log_append()` validates column types (numbers finite nonnegative or `NA`, `started`
   POSIXct, `estimated` non-`NA`, `route` one of the four, request id present) before mutation
   and returns the rows appended (a zero-row frame is a no-op, `0L`).
8. `usage_log()` binds newly appended rows once and keeps the bound table, so repeated reads by
   `gptr_usage()` do not re-bind a long System 1 log; content and order never change.
9. `usage_rollup()` validates its rows, refuses two different recorded parents or cyclic
   ancestry (an `NA` parent records none and joins its session's recorded parent, fix round 1),
   groups rows without a session as `NA`, and treats `NULL` as no rows.

Evidence (raw logs in ignored `dev/.validation/P05/`):

- Actual red (existing tests, before any source): `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 138 ]`,
  every failure a missing `usage_row` (9; one reported as `object 'usage_row' not found` through
  `do.call()`) or `usage_log` (1), each raised after the fixtures `local_priced_provider()`/
  `usage_msg()` had run (`task9-red.log`).
- First green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 213 ]` (`task9-green-1.log`); final green after
  the added assertions `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 225 ]` (`task9-green.log`). The plan's
  red 4/23 and green 51 are historical: Task 1 already had 138 expectations under IC-74.
- Clean `git archive HEAD` export plus only the two task files, `^(provider-usage|catalog-models)$`:
  PASS 606, 0 failures (`task9-green-head-export.log`), so the result does not depend on the
  concurrent uncommitted CI/state edits in the working tree.
- Neighbours `^(catalog-models|provider-registry|provider-fake|provider-message|
  provider-transform|agent-loop|lint-rules|arch-layers|ext-specs)$`: PASS 1316, 0 failures,
  0 warnings (`task9-neighbours.log`).
- Lint: zero on `R/provider-usage.R` and `tests/testthat/test-provider-usage.R`
  (`task9-lint.log`); both ASCII-only, no line over 100 characters.
- Review 1 fixes (round 1): see the Task 9 section of [`P05.md`](P05.md).

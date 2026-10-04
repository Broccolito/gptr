# P04 Task 9: provider rate limiter

Owner: requirements_audit. Append-only ownership of the rate-limiter section in
`R/http-retry.R` and matching tests, plus this log. The reviewed Task 3 source
and test contents are retained byte-for-byte as prefixes. Reactor Task 6 and
the real P02 registry are dependencies; no stand-ins were added.

## Behavior and plan reconciliation

- One process-wide limiter state per provider in `reactor_get()$limits`.
  Admission never blocks and consumes one request unit only when it succeeds.
  Request budgets, token-exhaustion windows and static request rates all gate
  the same admission decision.
- Static rates must be positive, finite real scalars (or omitted/NULL). Invalid
  configuration is rejected before mutation. Fractional request rates use a
  capacity of at least one request, allowing e.g. 0.5 requests/s to admit one
  request every two seconds instead of starving permanently.
- Header counts must parse to finite values; malformed headers preserve known
  state. Negative remaining counts conservatively mean exhausted. Token windows
  for total/input/output and the compatible x-ratelimit window are retained and
  expired separately, so an unrelated positive window neither erases exhaustion
  nor extends an exhausted window's reset.
- Retry cooldown has its own deadline, capped by validated
  `gptr.max_retry_delay`; it does not zero an otherwise positive request budget
  until that budget's much later reset. Request/token windows remain independent
  constraints, and a genuine exhausted budget still applies after retry cooldown.
- `ratelimit_next()` refreshes time-derived credit without consuming it, then
  reports when all current blockers can clear. Repeated checks do not move the
  refill deadline forward. Deadline addition and refill avoid leaking nonfinite
  arithmetic into state.
- The literal interface has no per-request token estimate: `tokens_per_s` stays
  validated metadata; token reservation/refund is not implemented or implied.
  Header-reported token exhaustion gates until reset. IC-74 decision concurrency
  remains the later System One layer's responsibility.

## Observed validation

1. Appended the five baseline tests before source: RED 5 errors, 95 existing
   Task 3 expectations passed.
2. Appended the literal baseline limiter: GREEN 116 expectations.
3. Added deterministic clock and validation boundaries before fixes: RED 60
   failures, 1 error, 2 test warnings, 123 passed. These exposed fractional-rate
   starvation, malformed input/coercion, coupled cooldown/reset, token-window
   loss and stale refill/deadline behavior.
4. Corrected only the new section: GREEN 189 expectations, zero failures,
   errors, test warnings or skips. Both complete owned source/test files lint
   clean. Confirmed the earlier Task 3 prefixes remain byte-for-byte unchanged.
5. Added a defensive internal-API identity regression before the key fix: RED 3
   failures, 191 passed; separate anonymous/provider storage keys then yielded
   GREEN 194, zero failures, errors, test warnings or skips, and lint 0. This
   protects the NULL-capable internal API; registered provider IDs already have
   stricter grammar, so the synthetic sentinel name is not a valid registered
   provider collision. A concurrent reactor parse error briefly blocked this
   check; the recorded red/green runs both occurred after its owner repaired it.

Commands used inside the isolated runner:

```r
res = devtools::test(filter = "^http-retry$", reporter = "summary")
tab = as.data.frame(res)
print(colSums(tab[c("failed", "error", "warning", "skipped", "passed")]))
stopifnot(sum(tab$failed) == 0, !any(tab$error))
results = lapply(c("R/http-retry.R", "tests/testthat/test-http-retry.R"), lintr::lint)
print(results)
stopifnot(all(lengths(results) == 0))
```

All R processes used `Rscript --vanilla`, the ignored project-local library,
fresh outer HOME/config/data/cache/project paths before package loading, disabled
live tests and cleared credential variables. No network, real credentials,
multiworker job, documentation generation or full-tree test was used. Local raw
evidence is ignored under `dev/.validation/P04-T09/`. The installed testthat's
built-under-R startup message is outside test warning counts.

Independent review by plans_security_review found no remaining actionable
issue in the new limiter section. The earlier retry helper section remained
outside this change. Ready for the scoped commit and handoff to Task 12's owner.

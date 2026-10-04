# P05 Tasks 4-5: transcript hand-off and projection

Owner: requirements_audit. Dependency-ready lane using actual P01 messages,
blocks and hashes, P02 registry/spec APIs, and P05 Task 2 `provider_get()`.
Owned files: `R/provider-transform.R`, `tests/testthat/test-provider-transform.R`,
and this log. This component alone does not complete P05 or its milestone.

## Task 4: cross-provider hand-off

- Same-model content remains unchanged except the documented empty unsigned
  thinking filter and blocks with foreign origin. Origin-mismatched reasoning
  honors the selected target's replay capability even inside a same-model turn.
  Explicit model capabilities take precedence over adapter fallback.
- Foreign signatures, redacted reasoning and other models' opaque data cannot
  reach the target. Images unsupported by the selected target become one text
  placeholder per consecutive run, retaining the surrounding content.
- Tool IDs follow target API rules, with results following the transformed IDs.
  Mapping is scoped to the current assistant turn so reused raw IDs do not carry
  a stale mapping. Sanitizing/truncation collisions receive deterministic hash
  alternatives through the same normalizer. Unchanged same-model IDs are
  reserved first, including later native turns, without rewriting native data.
- All transformations are deterministic and copy-safe; they use the already
  resolved target and do not discover models or mutate frozen history.

### Test-first evidence

1. Historical tests before source: RED 5 missing-function errors, 0 passes.
2. Literal Task 4 source: GREEN 32 expectations.
3. Added foreign-origin replay, stale reused-ID and normalization collision
   regressions: RED 4 failures, 40 passes. Scoped fixes: GREEN 44, lint 0.
4. Added mixed native/foreign Mistral ID reservation in either order, plus model
   versus adapter capability precedence: RED 2 failures, 54 passes. Reserved
   unchanged native IDs before normalization. Final GREEN 57, zero failures,
   errors, test warnings or skips; lint 0 for both source and test files.

Independent source review by plans_security_review/p02_metadata_review found no
remaining issue in Task 4 scope (read-only review; validation above is owner-run).
Raw local evidence: ignored
`dev/.validation/P05/T04/`.

## Validation process

All R runs use `Rscript --vanilla`, the ignored project-local library, and fresh
outer HOME/config/data/cache/project directories before package loading. Live
tests are disabled and credential variables cleared. No credentials, provider
calls, network, multiworker builds, documentation generation or full-tree tests
were used. The installed testthat built-under-R message is a startup message,
not a test warning.

```r
res = devtools::test(filter = "^provider-transform$", reporter = "summary")
tab = as.data.frame(res)
print(colSums(tab[c("failed", "error", "warning", "skipped", "passed")]))
stopifnot(sum(tab$failed) == 0, !any(tab$error))
lint = lapply(c("R/provider-transform.R", "tests/testthat/test-provider-transform.R"), lintr::lint)
print(lint)
stopifnot(all(lengths(lint) == 0))
```

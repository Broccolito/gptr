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

## Task 5: transcript projection

- Walks only the selected ancestry, with the documented previous-entry fallback
  for a missing parent. A non-NULL unknown leaf is a typed error, including an
  empty transcript; NULL remains the empty projection.
- Applies the newest ancestry compaction as the replacement prefix and retains
  its stored context blocks exactly. Older compaction entries inside the kept
  range do not reintroduce superseded summaries. Compactions on other branches
  have no effect; tool results whose calls were cut are dropped.
- Drops errored/aborted assistant turns. Each open call receives one real or
  synthetic result; duplicate, unmatched and late results are dropped, while
  repeated IDs in later groups remain independent. Interrupted synthetic results
  retain the assistant timestamp and elapsed-time wording, making repeated
  projections stable. Other orphans receive `No result provided`.
- Holds operator relays until tool results finish, preserving FIFO at normal
  completion, abort/error boundaries and EOF. Both documented operator entry
  shapes work; user extension notes remain user messages. Stored entries are
  unchanged.

### Test-first evidence

1. Appended historical tests before projection source: RED 6 missing-function
   errors with the 57 Task 4 expectations still passing.
2. Literal Task 5 source: GREEN 83 expectations.
3. Added partial-result/abort/error, relay FIFO, duplicate/unmatched/reused IDs,
   branch compaction, multiple compactions, NULL kept range and empty-transcript
   unknown-leaf regressions. Two initial test assertions incorrectly used
   `msg_text()` for context blocks; corrected them to inspect context text and
   serialized messages before evaluating the implementation failures.
4. Corrected boundary RED: 3 failures, 118 passes (superseded compaction summary
   retained; missing leaf silently accepted). Applied the two scoped fixes:
   GREEN 121, zero failures, errors, test warnings or skips. One test-only brace
   style finding was then corrected. Package-aware scoped lint: 0 for both files.
   A standalone lint invocation without loading the namespace had unresolved
   package-symbol findings; loading the package before lint resolved those.
5. Timestamp boundary regressions produced RED 6 failures / 125 passes.
   Numeric NA, NaN and infinite timestamps now map to zero, matching invalid
   text timestamps; projection never emits a non-finite timestamp. Final GREEN:
   131 passes, zero failures, errors, test warnings or skips; scoped lint zero.
   Astra independent source review confirmed the finite guard on 2026-10-03.
6. Luna independently reran the current exact source: GREEN 131, no failures,
   warnings or skips, and both source and tests lint clean. Saved evidence:
   `dev/.validation/P05/provider-transform-luna-green.log` and
   `dev/.validation/P05/provider-transform-luna-lint.log`.
7. Pinned roxygen documentation generation found an unresolved cross-reference
   to the private `handoff_transform()` helper. Replaced the link with inline
   code in its roxygen comment; no runtime change. Documentation revalidation
   is coordinated at the next root documentation window.

Independent source review: plans_security_review/p02_metadata_review confirmed
both fixes against the contract and found no further issue in that narrow pass;
The additional Astra review found no remaining timestamp defect. Raw evidence is ignored under
`dev/.validation/P05/T05/`.

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

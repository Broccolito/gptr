# Implementation decisions and deviations

## D-001 — Branch and implementation authorization (2026-10-03)

Use `codex/gptr-1.0-implementation` from synchronized `main` instead of recreating
the already-merged historical `gptr-1.0` branch. This preserves the completed
design history and follows the current branch convention. No design behavior changes.

## D-002 — Isolated tooling and current environment (2026-10-03)

The maintainer's start-to-finish implementation request authorizes necessary
development setup. Missing dependencies and pinned roxygen2 will be installed
in an ignored project-local library rather than replacing the user's packages.
The tool inventory is checked live; old `/Users/wanjun` snapshots are historical.
The task logs will record exact versions and relevant test outcomes without
publishing the private host inventory.

## D-003 — Public transition begins before P25 (2026-10-03)

The maintainer explicitly requested rewriting README and GitHub About now.
Replace obsolete 0.7 examples with an accurate development-status overview.
Working examples and installation promises must track verified implementation;
P25 still owns the final user documentation and release validation.

## D-004 — Available implementation workflow (2026-10-03)

The named `superpowers:*` skills are not installed. Use the available subagent
tools for task-sized implementation and independent review, preserving actual
test-first evidence and plan gates. Do not install unrelated skills or claim
that a named external workflow was run.

## D-005 — Parallel foundation tasks (2026-10-03)

The maintainer authorized parallel implementation. P01 Tasks 19–21 run once
Task 3's service table is stable: their structural checks do not require the
remaining token/message utilities. Tasks 9–12 and 13–18 may proceed in separate
lanes after Task 8. Scope edits and Git commits to each owner, preserve actual
red/green checks, and rerun complete P01 acceptance after integration. No plan
or milestone is declared complete from a partial tree.

P02's independent event-catalogue task also begins after its actual P01
condition/encoding dependencies pass. P02 spec-engine tasks wait for the schema
and fake-provider contracts. This uses the tested interface dependency order;
full P01 acceptance still precedes P02 completion and milestone promotion.
P04 Task 1 (SSE/NDJSON splitters) likewise uses only the verified P01 JSON
decoder. It can run independently before registry/secrets integration; the
remaining transport tasks wait for their actual authentication prerequisites. P04 Tasks 4–5
(process supervision and the job table) also use only P01 interfaces and run in
a separate lane while root validates the immutable foundation snapshot.
Tasks that materialize secrets or persist transport data still wait for P03.

P06 Task 1's pure agent-loop state machine may likewise use the actual completed
P01/P02 interfaces while transport acceptance finishes. Four unused test helpers
that call future P06 functions (`local_events`, `test_session`, `test_run`,
`run_text`) are deferred until Tasks 3–5 supply those functions. Restore them
from Task 1's harness definition at their first dependent task; no production
stub or lint suppression stands in for those dependencies. Full P06/M1 gates
still require the complete dependency chain.

## D-006 — Effective connection cleanup gate (2026-10-03)

Independent review found that setting `_R_CHECK_CONNECTIONS_LEFT_OPEN_` around
`devtools::test()` does not check the test suite's connections: R CMD check uses
that flag for examples. CI now compares the complete R connection table before
and after the suite through `dev/ci/check-connections.R`. A synthetic leaking
connection is an explicit negative control. Ordinary R CMD check example
checks remain enabled. The full wrapper must also pass after P01 integration.

The combined P02/P04 snapshot exposed processx's two intentional process-wide
supervisor FIFOs. IC-60 already disables this supervisor under R CMD check.
The standalone connection gate now scopes the same `gptr.supervise = FALSE`
option and restores the caller's value, including on error. It still compares
the complete table without exemptions and retains its deliberate-leak negative
control; child cleanup and orphan recovery tests still execute.

## D-007 — Stream parser boundary corrections (2026-10-03)

The literal P04 splitter silently removed NUL bytes, changing provider data.
Both splitters now signal a typed provider error because R strings cannot
represent NUL; error messages never include the input. This is an explicit R
representation limit, not a claim that NUL is forbidden by the SSE standard.
Invalid retry fields are ignored before choosing the last valid numeric retry.
The contract's deliberate final-event flush behavior is preserved.


## D-008 — Independent usage-accounting component (2026-10-03)

P05 Task 1 consumes only P01 condition/list utilities and can be developed in a
separate file while the M0 registry, secrets and transport integration proceeds.
Its owner reconciles unknown usage and prices with IC-74 instead of copying the
older plan's conversion of missing measurements into zero. No later usage rows
or model resolution are implemented before their dependencies. This parallel
component does not complete P05 or advance the milestone gate.


## D-009 — Portable copy-safety controls (2026-10-03)

Hosted P01 validation exposed two test-harness assumptions. Windows child stdout
uses CRLF, so completion-marker parsing must accept CRLF as well as LF. A
synthetic output regression checks both successful completion and detection of
a copy under CRLF.

The literal plan's `str(big)` negative control makes no observable next-edit
copy on the hosted oldrel-4 R interpreter, although it does on this Mac. Use
`retained = big` as the portable negative control: keeping a second reference
must force the next edit to copy. The zero-copy requirement for the package's
fingerprint/save operations and the real edit tests is unchanged. Full Windows
and old-R acceptance still needs a new hosted run containing these corrections.

## D-010 — Streaming redaction fails closed at its bound (2026-10-03)

The literal P03 Task 3 implementation advances the emit point when a sensitive
candidate exceeds the hold-back cap, potentially releasing a secret prefix.
That conflicts with the design's confidentiality guarantee. The stream now
fails closed with `gptr_error_redaction_limit`, a numeric `limit` field and a
generic message. Held input is discarded; later push/flush calls remain failed.
Normal bounded streams retain chunk/whole parity. Overflow is an explicit
termination case, not a parity claim. Contract section 7.3 and the condition
table record this clarification; the P03 task log owns its regression evidence.

## D-011 — Explicit transport performance acceptance (2026-10-03)

Architecture section 6.18 explicitly requires INFRA-01's first-delta latency
and six-stream concurrency targets. P04's Global Constraints already state an
explicit exception for INFRA-01 and INFRA-23 to the general five-second guidance.
This records that existing exception; it introduces no new target or waiver. Run the named performance
checks on a resource-healthy host with competing heavy validation paused, and
record actual measurements. Ordinary functional tests should prefer event and
ordering assertions. A timing failure needs investigation, not a silently
loosened target or a substitute claim based only on receiving callbacks.

## D-012 — Reactor retries fail closed and honour the hint's class (2026-10-03)

P04 Task 12's literal plan code is changed in two behaviours; contract 8.1-8.2 governs both.

1. **A malformed commitment fails closed.** The plan's `reactor_failure()` used
   `isTRUE(tryCatch(tr$retry$committed(), error = function(e) TRUE))`, so a malformed result
   (`NA`, a non-logical or a longer vector) counted as "not committed" and the request was
   sent again. Now every result other than exactly `FALSE` counts as committed, the same as
   an error: no retry, and the classed condition goes to `on_fail`. Contract 8.2 retries only
   when `committed()` "is `FALSE`". A re-send after an ambiguous commitment could repeat side
   effects that the stream already delivered, such as deltas shown or tool calls emitted.
   Regression: "a malformed committed result fails closed without retrying".
2. **`reactor_retry()` decides whether the hint is retryable.** In the plan, every in-stream
   hint set `retry = TRUE`, except a `retry_after` above the cap. The decision now uses
   `retry_classify()`'s table: `auth`, `spend_cap`, `redirect`, `retry_after`, `timeout_idle`
   and `timeout_first_byte` are never retried. `overloaded`, `rate_limit`, `network`,
   `timeout_connect` and a 408, 409, 429 or 5xx status are retried. This keeps the
   nonretryable rules for every path that reports a failure: the spend cap is never retried,
   401/403 are `auth`, 3xx are never retried (IC-64), and the INFRA-05 timers are never
   retried. Only a retryable hint above `gptr.max_retry_delay` becomes class `retry_after`.
   `timeout_*` classes keep the parent `gptr_error_timeout`, and the others keep
   `gptr_error_provider` (contract 2.2). The condition's status is an integer, and its
   request id comes from the attempt's 2xx head. Regressions: "stream retry hints validate
   delays and preserve nonretryable classes" and "stream retry hints keep their class, the
   integer status and the server's request id".

## D-013 — Claude subagent workflow replaces the Astra/Luna lanes (2026-10-03)

The maintainer resumed the paused implementation with Claude Code and asked for
all work to be consolidated onto `main` (no feature branch, no PRs) with periodic
pushes. The handoff's model allocation (gpt-6-astra for implementation/review,
gpt-6-luna for tests) is not available in this harness. Each task now runs as:
a Claude implementer (actual red, implementation, actual green, scoped lint,
evidence in `progress/Pxx.md`), a separate Claude reviewer that independently
re-runs the focused tests and lint and audits the diff against plan and contract,
a fixer for blocker/major/minor findings (up to two re-review rounds), then a
commit of exactly the task's files with the plan's message. The separation of
implementation, independent review and acceptance is unchanged; no gate is
weakened. Pushing `main` triggers the hosted CI matrix, which supplies the
cross-platform evidence previously obtained through the draft PR.

## D-014 - IC-74 discovery and preflight choices in P05 Task 8 (2026-10-03)

IC-74 (`spec/07-local-ollama.md` sections 2 and 2.1) adds `model_prepare()` and
`provider_preflight()` but names no condition classes, and the plan's Task 8 literal predates
it. P05 Task 8 fixes these behaviours, which P08 and P13 consume:

1. **Condition classes.** Local-only refusals (non-loopback endpoint, cloud selector, remote
   markers, evidence without local execution) signal `gptr_error_untrusted` (`what`, `path` =
   the model ref, `origin`). Missing or stale discovery evidence, a missing capability, a
   model-level type/api mismatch or an old server signal `gptr_error_not_available` (`member` =
   the ref, `provided_by`). `gptr_models(provider = "ollama", refresh = TRUE)` can therefore
   signal these two classes besides the `invalid_argument`/`network` of contract section 6.2.
2. **Discovery egress.** Native discovery is itself refused before any request for a
   non-loopback endpoint unless the protected safety record sets `ollama_local_only = FALSE`;
   `gptr_models()` has no safety argument, so its Ollama refresh is loopback-only.
3. **Listed names grant nothing.** Generic `discover()` results (LM Studio, llama.cpp, vLLM) add
   descriptive entries without tools, vision or locality; the plan literal granted
   `tool_call = TRUE`.
4. **System 1 default.** `model_default("system1")` keeps the setting, then the TypeSafe key, then
   a native classifier whose current private evidence passes the default local-only preflight
   (07 section 5), skipping a provider disabled in the settings. It never discovers.
5. **Checked model.** `provider_preflight()` returns the model narrowed to the evidence (tools,
   reasoning, image input, context) with the evidence's digest, server version and locality,
   and a zero metered price when the evidence establishes local execution (so a bare catalog
   name such as `ollama/clef-flash` prices like its discovered `:latest` tag); a record whose
   digest or server version differs from current evidence is refused, so a prepared model is
   never silently replaced.

Validation: `progress/P05.md`, Task 8 (`test-catalog-models.R` IC-74 tests).

## D-015 - IC-74 usage rows: unknown cost and tier stay NA; validated roll-up (2026-10-03)

P05 Task 9's literal `usage_row()`/`usage_rollup()` predate IC-74 (07-local-ollama.md section 5:
"Missing usage remains unknown"). Behaviours changed, which P06, P13 and P20 consume:

1. **Cost only from evidence.** On the `api`, `system-one` and `emulated` routes the row's cost
   comes only from the dated price tier in force (`usage_cost()`); an unresolved model or a
   request before the first known price gives `NA`. The plan fell back to the message's own
   `cost$total`, which for a `usage_new()` record without `cost` is the legacy constructor zero.
   An explicit zero rate still gives a known zero cost, even with unknown tokens (Task 1 rule).
   The priced record is the resolved record after the same pure, no-I/O `provider_preflight()`
   the request ran (the plan priced the bare catalog record), so a bare Ollama name (shipped
   `ollama/clef-flash`, no prices) whose current `:latest` evidence establishes local execution
   records the zero metered charge that 07 section 5 requires, as the tagged name does; a record
   the preflight refuses (no current evidence, a cloud model) keeps its catalog prices.
2. **`tier` is `NA` when no price tier applies** (the plan wrote `"default"`).
3. **`plan-cli` cost is the CLI's reported `cost$total`, read from the message's usage record:**
   a supplied total (zero included) is kept, a missing one is `NA`, and an `estimated = TRUE`
   record (contract 4.3: the provider reported nothing, so no `total_cost_usd`) is `NA`, so P06's
   plan-literal estimator fallback in `run_response()` (`usage_new(..., estimated = TRUE)`) never
   records a known zero. A `usage_new()` record always carries a total, so **P20 adapters pass
   `cost = NULL` when the CLI reported usage but no `total_cost_usd`**.
4. **Validation.** `usage_row()` refuses non-scalar or invalid `session`, `agent`, `parent_id`,
   `started`, `seconds`, `multiplier` and message fields (`gptr_error_invalid_argument`) instead
   of recycling them into several rows; `usage_log_append()` validates the section 4.3 column
   types before the log changes; `usage_rollup()` refuses a session with two different recorded
   `parent_id`s and cyclic ancestry (the plan stopped silently at a cycle). An `NA` `parent_id`
   records no parent (contract 4.3; P13's System 1 rows of a child session), so it joins the
   parent its session's other rows record. Rows without a session (process System 1 calls) form
   the `NA` group; an `NA` value makes its group's sum `NA`.

Validation: `progress/P05-usage.md`, Task 9 (`test-provider-usage.R`; the evidence-priced row
in `test-catalog-models.R`).

## D-016 - Hosted CI corrections: INFRA-01 measurement, undeclared built-ins, old Windows R (2026-10-03)

Hosted run 37169255693 (`8e8d8e0`) and run 37170545611 (`a2ba302`) failed on every platform.
CI Task CI-1 changes three behaviours of plan literals; contract and architecture targets stay.

1. **INFRA-01 is measured on each stream's own schedule.** P04's tests anchored both targets at
   the moment the transfers were queued, so connection setup and the mock server's accept/parse
   time counted against them: hosted macOS measured 2.57 s and the hosted connection job 2.4830 s
   and 2.553 s for six streams (limit 2.475 s), and one macOS delta gap exceeded 0.35 s. Locally
   that setup is 0.06-0.12 s of a 2.34-2.37 s wall. The mock writes `message_start` with the
   response head when it has read the request and delta i at `i * 0.25` s after it, so the
   tests now measure from each stream's first event. "First delta within 0.35 s of the mock
   writing it" (architecture 6.18) applies to every delta: its offset from its scheduled write
   must stay below 0.35 s in either direction (late = stalled or slow delivery; early = the
   first event came late; a batched stream has every delta far ahead of its schedule). "Six
   streams of 1.00-2.25 s finish within 10% of the slowest" compares the span from the earliest
   stream's first event to the last stream's end with 1.10 times the slowest stream's own span
   (its first event to its end), which must itself be at least 2.25 - 0.35 s; serialised streams
   (about 9.75 s) still fail. Both thresholds (0.35 s, 10%) are unchanged (D-011); synthetic
   negative controls prove that a 0.4 s stall, a batched stream and serialised streams fail and
   that 0.3 s of common connection setup does not. Locally: worst schedule offset 0.003-0.050 s,
   six-stream ratio 1.000-1.004.
2. **A built-in that no loaded plan declares is not filtered out.** Contract 7.0 makes a service
   unavailable when absent or when its owning built-in is filtered out. P01's
   `service_builtin_active()` also treated every built-in without records as filtered once the
   registry listed any record, so P01's own test of a `describe` service (built-in `workspace`,
   P09, not built yet) failed in every package run after P03/P05 built-ins began loading
   records. Now a built-in without enabled records counts as filtered out only when it has
   disabled records or is declared in `the$builtins` (declared but skipped by a filter, or
   failed); a never-declared one stays active. Behaviour for every declared built-in is
   unchanged. Consequence for P07 Task 2 and P08 Tasks 2/3/6: their bootstrap services become
   available before their built-in is declared; their reviewed tests already avoid asserting
   `not_available` there.
3. **Windows R before 4.5.0 runs R CMD check without `_R_CHECK_THINGS_IN_OTHER_DIRS_`.** That
   check reads `file.info()` owner columns, which Windows R has only from 4.5.0 (R NEWS); on
   the oldrel-4 job (R 4.2.3) R CMD check aborted at its start and rcmdcheck still reported
   success. The matrix entry sets it to `false` there only; every other configuration keeps it.
   Every R CMD check job now fails unless `check/gptr.Rcheck/00check.log` has a `Status:` line,
   every job has a time limit (120 minutes for R-devel, whose dependencies build from source
   for about 65 minutes on a cold cache), and the connection gate runs the whole suite before
   comparing the connection table, then fails on failed tests and on any leak (D-006).

Validation: `progress/ci-hosted.md`, Task CI-1.

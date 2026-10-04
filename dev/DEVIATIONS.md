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

## D-016 - Hosted CI corrections: INFRA-01 clock, service test isolation, old Windows R (2026-10-03)

Hosted run 37169255693 (`8e8d8e0`) and run 37170545611 (`a2ba302`) failed on every platform.
CI Task CI-1 changes how plan literals measure, isolate and check. Every contract, architecture
and decomposition target and threshold stays, and no product behaviour changes.

1. **INFRA-01 is measured on the mock's own clock.** P04's tests anchored the targets at the
   moment the client queued the transfers and compared raw arrival times. So connection setup,
   the mock's request handling (about 0.04 s locally to build a response plan before scheduling
   it) and any lateness in the mock's own writes all counted against gptr. Hosted macOS measured
   2.57 s for six streams, and the hosted connection job measured 2.4830 s and 2.553 s (limit
   2.475 s). Hosted macOS also had one consecutive delta gap of 0.35 s or more in both runs.
   With `log_writes = TRUE`, the mock (`fixtures/mock_server.R`) now also logs the wall-clock
   time just before it writes each response piece, and the SSE event the piece starts with.
   `local_mock_server()` returns that log as `writes()`. This adds a member to contract 12.2's
   list and changes nothing else; only the INFRA-01 tests enable it. The client records
   wall-clock arrivals on the same clock. The targets, with the plan's thresholds:
   - Architecture 6.18, "first delta within 0.35 s of the mock writing it": the latency
     (arrival minus write) of every delta, not only the first, is below 0.35 s.
   - Decomposition P04 acceptance 2 and P04 Global Constraints, "every inter-delta gap is under
     0.35 s": the gap between consecutive deltas on the mock's 0.25 s cadence,
     `0.25 + diff(latency)`, is below 0.35 s. When the mock writes on time this equals the raw
     arrival gap. It nets out only the mock's own lateness, so gptr's delivery may still vary
     by less than 0.1 s from one delta to the next, as before.
   - "Six streams of 1.00-2.25 s finish within 10% of the slowest": from the first response
     head the mocks wrote, which starts every stream's schedule, to the end of the last stream
     at the callback, at most 1.10 * 9 * 0.25 = 2.475 s. The bound is the plan's. Only the
     anchor moved, from the client's queue time to the first head write, which leaves out
     connection setup and the mock's request handling. Contention that stretches every stream
     still fails, and so do serialised streams.
   - A latency below -0.05 s fails, because it means arrivals were matched to the wrong writes.
   Synthetic controls pass on-time delivery and a mock write 0.11 s late. They fail a constant
   1.5 s delivery delay, a 0.4 s stall, a delta held back 0.11 s (a 0.36 s gap) or 0.34 s,
   batching, mismatched writes, six streams stretched to one delta per 0.375 s, and serialised
   streams. On the real mock, a 1.5 s pause of the pump and a 0.4 s hold after delta 4 both
   fail. The hold fails only on the gap, since its latency is 0.16 s. Local results over five
   repetitions: latency 0.3-41 ms; gaps at most 0.254 s; the mock's own write lateness at most
   2 ms after 37-42 ms of plan building; six-stream wall 2.268-2.273 s, against 2.34-2.37 s with
   the plan's anchor. Open item (D-011): the hosted macOS gap failure is not explained by
   connection setup, because a gap compares consecutive deltas. Its cause is unknown: either the
   mock's own write lateness, which is now netted out, or gptr's delivery, which still fails. The
   failure message now prints every latency and gap and the mock's own lateness. Read it on the
   next hosted macOS run.
2. **P01's service registration test is isolated from later built-ins.** In `test-aaa-state.R`,
   "ext_service_set() registers and replaces services" registers a `describe` service owned by
   built-in `workspace` (P09, not built yet). Once P02 is loaded, the plan's
   `service_builtin_active()` counts a built-in without enabled records as filtered out
   whenever the registry lists any records. So the test failed in every package run after the
   P03/P05 built-ins began loading records (hosted `test-aaa-state.R:127-128`). The test now
   mocks `service_builtin_active()` to `TRUE`, as its neighbour already does. It still tests
   registration and replacement in the bootstrap table; the rule keeps its own plan tests. The
   product rule stays the plan's, and P01 reads only `gptr_registry()`: contract 7.0 assigns
   `the$builtins` to P02. In a complete build, each provider plan declares the built-in that owns
   its services.
3. **Windows R before 4.5.0 runs R CMD check without `_R_CHECK_THINGS_IN_OTHER_DIRS_`.** That
   check reads `file.info()` owner columns, which Windows R has only from 4.5.0 (R NEWS). On
   the oldrel-4 job (R 4.2.3), R CMD check aborted at its start and rcmdcheck still reported
   success. The matrix entry sets the variable to `false` there only; every other configuration
   keeps it. Every R CMD check job now fails unless `check/gptr.Rcheck/00check.log` has a
   `Status:` line. Every job has a time limit, 120 minutes for R-devel, whose dependencies build
   from source for about 65 minutes on a cold cache. The connection gate runs the whole suite
   before comparing the connection table, then fails on failed tests and on any leak (D-006).

Validation: `progress/ci-hosted.md`, Task CI-1.

## D-017 - IC-74 request preflight and decision-only refusal in provider_stream() (2026-10-03)

P05 Task 10's literal `provider_stream()` predates IC-74. Behaviours changed, which P06, P07, P08,
P13 and P05 Task 11 consume:

1. **Preflight before egress.** `provider_stream()` calls `provider_preflight(model, provider,
   safety)` (07-local-ollama.md section 2.1) after the adapter/provider/`enabled` checks and before
   credential lookup and `build()`; the adapter and normaliser receive the checked model. A
   refused preflight is signalled before anything starts (`gptr_error_not_available` or
   `gptr_error_untrusted`, D-014), so a local-only selection never reaches the network.
2. **The safety record.** Read from the run's frozen option snapshot `run$opts$safety` (contract
   7.6, IC-53) and from `opts$safety`; only the field `ollama_local_only` is read. When a run is
   given its snapshot is authoritative, and a run without one counts as local-only. Either record
   can only tighten: local-only holds unless every record present says `FALSE`; a malformed
   record is `gptr_error_invalid_argument`; no record means local-only. `opts$safety` therefore
   relaxes the policy only for a caller with no run object at hand. P06/P08 must put
   `ollama_local_only` into the run's safety snapshot (human user/session configuration only).
3. **Decision-only models never stream.** A model with `type = "classifier"` is refused first
   (`gptr_error_not_available`, `member` = the model ref, `provided_by = "a conversational
   model"`), and so is an adapter without the stream functions of its transport (`member` = the
   api). P01's `fake_classifier_stream()` is therefore no longer reached through
   `provider_stream()`; System One requests go through `s1_request()` (contract 8.1).
4. **Transport drivers.** `stream_driver()` maps `http_sse`/`http_ndjson`/`http_json` to the HTTP
   driver; a transport without a driver is refused before anything starts (`not_available`,
   `member` = the transport). Task 11 adds `inprocess` and `process_jsonl` there (the plan
   literal referenced their functions before they existed).

Validation: `progress/P05.md`, Task 10 (`test-provider-registry.R`).

## D-018 - process_jsonl turns the glue ends drop their child; send only to the open turn (2026-10-03)

P05 Task 11's literal `process_jsonl` driver killed the session's child only on an abort or
when a new `start` replaced it. Behaviours P06 and P20 consume:

1. **A turn the glue ends itself forgets and kills its child.** Besides an abort, a local
   failure (an adapter normaliser error, a retry hint, which `process_jsonl` cannot re-send, a
   write failing after the spawn) and a run that settled while the turn was open end the turn
   and kill the child after forgetting it (`opts$state$process = NULL`). Its late lines and exit
   reach no turn, and the session's next turn must start a new child: a P20 adapter returns
   `start` when `opts$state$process` is NULL (and resumes its CLI session itself if it wants the
   context back). A turn the normaliser ends (`done`/`error` event) or the child's exit ends
   keeps a living child for the next turn.
   Every child the glue lets go of (these turns, a child a new `start` replaces, the job row's
   `stop()`) is stopped by `stream_process_kill(p, watch, job)` (Task 11 review, round 2): P04's
   `reactor_cancel()` of the child's watcher (the watcher goes, pending stdin is dropped, then
   `kill_all()`), and the job row is removed at once, because P04 reports no exit for a
   cancelled watcher. A child without a watcher is killed directly. `kill_all()` must never run
   under a living watcher: processx 3.9.0's `$kill()`/`$kill_tree()` close the child's pipes
   (`close_connections = TRUE`), so P04's line reader never reaches end of stream, the exit is
   never reported (no `on_exit`, so the `cli` job row stays `running`) and the closed pipes are
   polled in every later pump iteration (a full CPU core, measured by the reviewer). The job
   row's `stop()` (`gptr_jobs(kill = TRUE)`, unload) also reports the exit to the turn that last
   used the child from the next pump iteration (`reactor_timer()`), as P04 would have: an open
   turn ends through the normaliser's `finish()`.
   **For P20:** the planned `pcli_stop_child()` (P20 Task 9) forgets the child and then calls
   `kill_all(p, grace = 1)` directly, which hits the same leak while P05's watcher is
   registered. It should end with `stream_process_kill(p, state$watch, state$job)` instead (after
   its interrupt and `write_close()`), or stop through the row (`jobs_env()$table[[state$job]]`).
2. **`opts$send()` writes only to the open turn's own child.** A finished turn's `send()` writes
   nothing, so an asynchronous control response (a `control_request` answered after an abort)
   never reaches another child of the session.
3. **inprocess** streams also let go of a settled run without `done` (as `stream_watch()`,
   INFRA-15), and malformed generator steps end the stream with one `error` event.
4. **A process turn does not depend on its watch task** (Task 11 review, round 1).
   `provider_stream()` returns the watch task id for `process_jsonl` (04 section 8.4 step 5),
   and P06's `run_abort()` and `run_settle()` cancel it (P04: removed without callbacks), so the
   watch never sees that abort or settled run. Each line and the exit of the turn's child first
   apply the watch's rule (`stream_over()`: an aborted turn ends as `aborted`, a settled run's
   turn is let go without `done`), so the line never reaches the normaliser (no `gate` or
   `mcp_dispatch` call for an ended run), and both drop the child. A turn still open when the
   session's next turn starts (its child silent since the cancel) is let go and its child
   dropped before `build()`, so `build()` sees no child and returns `start`. P05 owns the
   `opts$state` fields `process`, `job`, `watch` (the child's P04 watcher id), `route`,
   `route_exit` and `stream_turn`.
   For P20: its `agent_end` hook (`pcli_stop_child()`, P20 Task 9) writes the interrupt and
   pumps until the acknowledgement or the child's death. The first line the child sends after
   the run settled now ends the turn and stops the child (`stream_process_kill()`: P04's
   `reactor_cancel()` of the watcher, then `kill_all()`: interrupt, grace, kill), so the wait
   ends at the child's death and the acknowledgement line is not pushed to the ended turn's
   normaliser. P04 reports no exit for that child, so the wait must test the child itself
   (`state$process` or `p$is_alive()`), not wait for an exit report. The rest of P20's design
   holds: `state$process` is NULL afterwards and the next turn starts a child.

Validation: `progress/P05.md`, Task 11 (`test-provider-registry.R`).

## D-019 - Windows processes: CRLF output, asynchronous kills, blocking child stdin (2026-10-03)

Hosted Windows release runs on `55ec31d` and `8e8d8e0` exposed eight process-engine failures,
and the `8e8d8e0` run hung in "checking tests" for 68 minutes (the job of run 37170545611 on
`a2ba302`, which had no time limit, was still running after two hours). CI Task CI-2 changes
the following; contract 7.4 and IC-60 are otherwise unchanged.

1. **CRLF child output.** R's stdout is a text-mode stream on Windows, so an R child's `"\n"`
   reaches the pipe as CRLF and an explicit `"\r\n"` as `"\r\r\n"`. `line_reader()` already strips
   one trailing CR (unchanged). `proc_run()` returns stdout and stderr as the child wrote them,
   CRLF included, as P22's `bridge_decode()` expects, so the byte-exact and code-page tests
   expect the platform's line end. The plan's fixtures that wrote an explicit CRLF (the
   `line_reader()` test and the reactor's byte-exact pipe test) write a bare LF on Windows, so
   one CRLF reaches the pipe on every OS. The `line_reader()` fixture also writes bytes instead
   of escapes: on macOS its `-e` expression `cat('a\\r\\nb\\nc')` wrote `"a\nb\nc"` (measured),
   so it had never tested CRLF there. New behaviour: `proc_run(echo = TRUE)` shows a CRLF line
   end as LF before redaction, so a registered multi-line value is redacted in a Windows child's
   output (hosted: `FAKEfirstLine\r\nFAKEsecondLine` was echoed unredacted). So that a value
   which itself holds CRLF still matches a child that writes it verbatim (review round 1: it
   leaked after the echo change), `secret_variants()` adds one derived form, the value with
   CRLF turned into LF, to the forms of architecture 6.5 (URL-encoded, JSON-escaped, base64
   cores). It only adds redaction; a value without CRLF has the same forms as before. The LF
   form is kept whenever the value itself is long enough to be redacted
   (`gptr.redact_min_chars`), not filtered by its own shorter length (review round 2: an
   8-character `"Ab3\r\nXy9"` lost its 7-character LF form and leaked when written verbatim).
2. **Tree markers on Windows.** `Rscript.exe` runs `Rterm.exe` as its child, which inherits the
   marker, so the plan's `length(proc_tree(marker)) == 1L` was FALSE there. The two tests now
   require the marked processes to be the child and its descendants only.
3. **Asynchronous kills.** On Windows `ps::ps_kill()` calls `TerminateProcess()`, which returns
   before the process has exited (on Unix `ps_kill()` sends SIGTERM and waits up to its grace
   period before SIGKILL). The orphan sweep checked for survivors at once and kept the marker
   file of an orphan that died moments later. New behaviour: `proc_cleanup_record()` (the sweep
   and `kill_all()`) waits at most 2 s for the processes it signalled to stop reading as running
   before it decides; it never waits on an unknown state, nor on a process whose kill failed
   (`ps_kill()`'s per-handle results; a kept record must not delay every `library(gptr)`).
   Nothing changes when the kill completed, as on Unix.
4. **The boundary test of a reused PID record** mocked `ps::ps_kill_tree()` and expected no
   call at all. processx's finalizer calls that binding by name with processx's own tree id, so
   a garbage collection during the test reached the mock (hosted Windows: 3 calls; reproduced
   on macOS by collecting a process started with `cleanup_tree = TRUE`). The test now collects
   a synthetic finalizer of the same kind and fails only on a signalled gptr marker.
5. **Blocking child stdin on Windows (open item, maintainer decision).** processx writes a
   child's stdin with a blocking `WriteFile()` on Windows: the pipe is created without
   `FILE_FLAG_OVERLAPPED`, in `PIPE_WAIT` mode, with a 64 KB buffer, and
   `processx_c_connection_write_bytes()` passes no `OVERLAPPED` (processx `src/win/stdio.c`,
   `src/processx-connection.c`). So IC-60's non-blocking `write_all()` holds only on Unix. On
   Windows, a write blocks until the child has read enough; a child that stops reading stdin
   while its stdout pipe is full (the 4 MB echo test) deadlocks the R process, and no
   `gptr.stdin_timeout` or pump timeout can end a call that never returns. The two tests that
   need a non-blocking write (the 4 MB echo and the stdin timeout on a child that reads nothing)
   skip on Windows with this deviation's number; the other stdin tests still run there. Making
   `write_all()` safe on Windows (for example a relay process or a bounded write size) is a
   P04 product decision, not made here. P18, P19, P20 and P22 children that receive large
   stdin payloads on Windows are affected until then.

The hosted Windows release job also streams the offline suite file by file before R CMD check
(`dev/ci/test-by-file.R`, 20-minute step limit, diagnosis only). Validation:
`progress/ci-hosted.md`, Task CI-2.

## D-020 - gptr_providers(): IC-74 egress and default model, one-attempt probe, row-local failures (2026-10-03)

P05 Task 12's literal `gptr_providers()` predates IC-74. Behaviours changed, which P08 (egress),
P13 and P20 (`status()` functions) consume:

1. **Egress follows the effective endpoint.** Contract 10.2 row 1 lets a `local` provider skip
   the egress acknowledgement; IC-74 (07-local-ollama.md sections 2.1 and 5) says the `local`
   hint is insufficient and a remote Ollama endpoint needs the normal acknowledgement. The
   `egress` column is therefore `ack` for an offline provider, for a `local` provider whose
   effective base URL is a loopback address (`catalog_endpoint()`), and otherwise only when the
   user settings' `egress.<id>` is `"ack"`. P08's `egress_check()` should apply the same
   effective-origin rule (P07/P08 row of 07 section 6).
2. **Default model by type.** A decision-only (classifier) model is never shown as the default
   of a chat or CLI provider, and a classifier provider shows only its classifier models (the
   plan took the newest active catalog row, which made `ollama/clef` Ollama's default chat
   model). Ollama's default is `NA` with the shipped snapshot, whose Ollama rows are
   classifiers.
3. **One probe, bounded.** `check = TRUE` calls `catalog_http_request(<base>/models, "GET",
   list(), NULL, timeout = 2, attempts = 1L, max_bytes = 65536)` instead of the plan's
   `catalog_http_get()`, whose P04 default policy retries (the plan says "one unauthenticated
   GET"). Any HTTP status proves reachability, also when it arrives with a body above the bound
   (the condition's `status`). The probe runs only for rows whose status is `ready` or `no key`.
4. **Failures stay in their row.** A credential lookup that fails other than with
   `gptr_error_no_key` (a plugin `auth` function that throws a plain R error or returns no
   handle), and a provider whose settings cannot be applied (an invalid
   `providers.<id>.headers`, which `provider_get()` refuses), show `error` instead of aborting
   the listing. An HTTP provider (its adapter's transport, or a built-in HTTP api while P12/P13
   have not registered the adapter) without a base URL shows `no base url`, with a malformed
   one `invalid base url` (the plan showed `no key` or `ready`), in both `check` modes, and
   neither is probed; only HTTP providers are probed (contract 6.2), so an `inprocess` or
   `process_jsonl` provider keeps its `check = FALSE` status. A provider's `status()` result
   lacking `status` maps `available` (`TRUE` -> `ready`, `FALSE` -> `unavailable`, else
   `unknown`), as plan ambiguity 18 requires; a `package_version` `version` is shown as text.
5. **The listing binds nothing.** The plan called `provider_credential()`, whose environment
   step registers the variable's value and binds it to the first provider's origin: listing
   providers in id order decided which provider could use a shared variable for the rest of
   the session (a plugin `gateway` keyed by `OPENAI_API_KEY` left `openai` with `no key`) and
   dispatched `secret_registered`, although contract 6.2 says the function emits nothing.
   `gptr_providers()` calls `provider_credential(p, register = FALSE)`: the same order and
   outcome, but an environment (or plain stored) value is only fingerprinted (P03's 6 hex), and
   a value the vault already binds elsewhere counts as absent. vLLM's built-in optional-key
   function is looked up the same way (its `gptr_optional_auth` attribute names the variable);
   a plugin's `auth` function is still called. P03's `auth_store_get()` still registers stored
   fields unbound when it reads them (its contract; no origin binding).

Validation: `progress/P05.md`, Task 12 (`test-provider-registry.R`). This entry first landed in
commit 90a43f5 (an unrelated CI commit); point 5 and the transport and settings parts of
point 4 were added by Task 12's review round 1.

## D-021 - IC-74 usage frames: missing usage stays NA, unknown counts print "unknown" (2026-10-03)

P06 Task 2's literal `usage_conform()` and `format_count()` predate IC-74 (07-local-ollama.md
section 5: "Missing usage remains unknown"). Behaviours changed, which P06 Tasks 4, 10, 11 and 13
and P18's tests consume through `usage_add()`/`gptr_usage()`:

1. **Missing columns are unknown.** `usage_conform(row)` fills every column the row lacks with the
   typed NA of P05's `usage_empty()`, the token and cost columns included (the plan filled those
   with 0). A known zero in the row stays zero. Rows from P05's `usage_row()` (complete, with
   D-015's NA for unknown tokens and unpriced cost) pass through unchanged. A fixture that means
   "known zero cache use" must state the zero columns.
2. **Unknown sums and counts.** `usage_totals()` sums without `na.rm`, so one unknown value makes
   its total unknown (as P05's `usage_rollup()`); `format_count()` returns `"unknown"` for an
   unknown count (the plan's version errored on NA) and picks the unit from the printed value
   (999.7 -> `"1.0k"`, 999999 -> `"1.0M"`).
3. **No silent coercion.** `usage_conform()` refuses wrong-typed columns (character tokens,
   numeric ids, non-logical `estimated`, unparsed `started`), known numbers that are negative,
   infinite or NaN, and a known `started` that is infinite or NaN, with
   `gptr_error_invalid_argument` (`arg = "row$<col>"`), P05's rule for usage rows (an NA start
   stays unknown); a bare logical `NA` column becomes its typed NA. It also refuses (`arg =
   "row"`) a non-list input and a list that is not named, equal-length, non-nested columns
   (a `NULL` element is an absent column), which `as.data.frame()` would otherwise flatten,
   recycle or rename. The plan's `as.numeric()` would have turned bad input into an invented
   unknown with a warning.

Later tasks that print usage must treat an unknown cost the same way (the plan's
`sprintf("$%.4f", ...)` footers print `$NA`).

Validation: `progress/P06.md`, Task 2 (`test-session-budget.R`).

## D-022 - IC-74 usage in the P12 normaliser core; contract-typed stop reasons and errors (2026-10-03)

P12 Task 1's literal `adp_usage()` predates IC-74 (07-local-ollama.md section 5: "Missing usage
remains unknown"). Behaviours changed in the shared normaliser core (`R/provider-anthropic.R`),
which every P12 adapter, P20's reuse of `anthropic_normaliser()` and P06's usage rows consume:

1. **Unreported usage is unknown.** A stream that reported no usage at all (for example an error
   before Anthropic's `message_start`, or an OpenAI-compatible server that sends no usage chunk)
   gives a message whose counters, total and cost are `NA` (P05's `usage_as(NULL)`); the plan
   wrote zeros. A reported value that is not a nonnegative number is `NA`; a field the provider
   left out of a reported usage keeps P05's legacy zero (P05 Task 1's "genuine partial
   observation" rule), so the hand-written golden usages are unchanged. Reported usage is merged
   as a cumulative update (Anthropic's `message_delta`; report 03 section 2.5.1, the SDK's
   MessageDeltaUsage): a JSON null keeps the value reported before it and is `NA` only when
   nothing was reported before (`adp_usage_set()`), including the `cache_creation` split fields
   (the plan's `%||% 0` made a null split field a known zero).
2. **Cost only from price evidence.** The message's cost always comes from `usage_cost()` with the
   model's dated prices: an unpriced model has an unknown cost (the plan kept `usage_new()`'s
   constructor zero when the model had no `prices`), a declared zero rate (a local Ollama model)
   a known zero; a price table `usage_cost()` refuses gives an unknown cost. On the `plan-cli`
   route P20 must still set the cost from the CLI's reported `total_cost_usd` (D-015 point 3).
3. **Contract-typed stop reasons and error types.** A non-string Anthropic `stop_reason` or error
   `type` is mapped to `error`/`provider` (R's `switch()` would have picked an alternative by
   position: `2` became `stop`, `5` became `auth`), and `raw_stop_reason` is stored as text
   (04 section 4.2: chr(1)).
4. **push() after a refused retry.** When the transport's `retry(info)` refuses at once and calls
   `fail()` from inside it, `push()` returns `TRUE` (the terminal event was emitted, 04 section
   8.1); the plan returned `FALSE`.
5. **The 5-minute/1-hour cache split survives `message_delta`.** The current wire shape repeats
   the cumulative `cache_creation_input_tokens` in `message_delta` without a `cache_creation`
   object (report 07 section 3.14). The plan treated that bare total as a new split (every write
   5-minute, `cache_write_1h = 0`), so 1-hour writes (gptr's BP1/BP2 default) were priced at the
   5-minute rate. A bare total now updates the split (`anthropic_cache_total()`): a split that
   adds up to it is kept, otherwise the known 1-hour writes are kept and the rest are 5-minute
   writes; only when no split was ever reported is every write a 5-minute write (report 07
   section 3.5). `usage.iterations` is not used (its relation to the top-level totals is not
   verified).

Validation: `progress/P12.md`, Task 1 (`test-provider-anthropic.R`; the four regression tests
failed 9 assertions against the plan-literal source; the two review-round regression tests for
points 1 and 5 failed 7 assertions before the fix).

## D-023 - P12 request headers from the resolved provider record, merged by name; no thinking without budget room (2026-10-03)

Four changes to P12 Task 2's plan-literal request builder (`R/provider-anthropic.R`):

1. **`adp_provider_headers(model, opts = NULL)`.** The plan's helper took only `model` and looked
   the provider up again with the global `provider_get()`. That lookup never sees a session-scoped
   (rank 0) record, such as a provider passed as `model = <spec>` (04 section 10.1). Such a
   provider's non-secret `headers` (04 section 10.2 row 1) were dropped. When a session record
   shadowed a global one with the same id, the request mixed the session record's base URL and
   credential with the global record's headers. The helper now uses the record that
   `provider_stream()` resolved and passed as `opts$provider` (session first, settings applied;
   P05 ambiguity 13). It accepts that record when the model's provider is its id, name or one of
   its aliases. Otherwise it uses the session's own record (`opts$session`, with the settings
   applied), and only then the global `provider_get()`. The argument is optional, so the plan's
   one-argument calls still work. Tasks 5, 7 and 9 must call `adp_provider_headers(model, opts)`
   so the defect does not spread to their adapters.
2. **A budget model with no room for the minimum budget sends no thinking.** The plan's clamp
   `min(budget, max(1024, max_tokens - 1024))` gave `budget_tokens = max_tokens` when the model's
   `max_output` (or the requested `max_tokens`) left `max_tokens <= 1024`. The API needs
   `1024 <= budget_tokens < max_tokens` (report 07 section 2.6, and the plan's own body rule "a
   budget below `max_tokens`"). In that case the body now carries no `thinking` and no
   interleaved-thinking beta, and `max_tokens` stays at the requested value (capped by
   `max_output`) instead of the raised one. Any `max_tokens` above 1024 keeps budget thinking,
   with the plan's clamp. No current catalog model is affected (Haiku 4.5 has `max_output`
   64000).
3. **Provider headers are merged, not appended: `adp_merge_headers(base, extra, lists, auth)`.**
   The plan's `headers = c(headers, adp_provider_headers(model))` repeats a name when the record
   (or `providers.<id>.headers` in settings) sets one the adapter also sets, and P04's
   `http_headers()` refuses a spec with a repeated name (in any case), so the request never left
   the process. An `anthropic-beta` header in the record broke only requests where gptr adds its
   own beta (an OAuth token, budget thinking, inline tool additions), so it could fail mid-session.
   The helper compares names case-insensitively. The adapter's headers win: a record header with
   the name of one the adapter set is dropped, so a record never changes the wire format
   (`content-type`, `accept`, the API version) or replaces the credential. This differs from Pi,
   where caller headers replace defaults, because gptr's parser and credential handling depend on
   them. Two exceptions. A header named in `lists` (for Anthropic `anthropic-beta`) gets the
   tokens of both sides, the adapter's first, each once. While the adapter sends a credential, a
   record header named in `auth` (for Anthropic `x-api-key` and `authorization`) is dropped, so
   two credentials are never sent (plan Global Constraints: "never sends both"). Without a
   credential, such a record header is sent as it is. Of two record headers with the same name,
   the last is kept. Tasks 5, 7 and 9 must call
   `adp_merge_headers(headers, adp_provider_headers(model, opts), auth = <their credential
   header names>)` instead of the plan's `c()`: Chat Completions `c("authorization", "api-key")`,
   Responses `"authorization"`, Gemini `"x-goog-api-key"`.
4. **An image-only tool result for a model without image input carries only the omission note.**
   The plan's `anthropic_tool_result()` led every result without text with "(see attached
   image)", also when each image had been replaced by the note "(image omitted: this model does
   not accept images)", so the model got two contradicting notes. The lead is now added only when
   an image block is attached. P05's `handoff_transform()` usually strips images for text-only
   targets first, so this mainly concerns direct `build()` callers.

Validation: `progress/P12.md`, Task 2 review rounds 1 and 2. The round-1 regression tests failed 7
assertions against the plan-literal source; the round-2 tests failed 6 (4 header, 2 image note).

## D-024 - IC-74 usage roll-up: request ids are required, an unknown cache read stays unknown (2026-10-03)

P06 Task 4's literal `usage_add()` and `ledger_mark_cached()` predate IC-74 (07-local-ollama.md
section 5: "Missing usage remains unknown"). Two behaviours changed, which Tasks 10, 11 and 13,
P18's tests and P19's roll-up consume:

1. **Every usage row needs its request id.** `usage_add(s, row)` refuses a row whose
   `request_id` is `NA` with `gptr_error_invalid_argument` (`arg = "row$request_id"`) before any
   session changes. `session_usage_rows()` de-duplicates by request id (a request recorded twice
   counts once), so distinct rows without an id would have collapsed into one and understated the
   totals. P05's `usage_row()` always sets an id (it generates one when the message has none) and
   every planned caller passes one.
2. **An unknown cache read leaves the ledger's cache flags unknown.**
   `ledger_mark_cached(s, request_id, cache_read)` with `cache_read = NA` (a reported usage whose
   cache read is unknown) sets that request's `cached` flags to `NA`; the plan left them `FALSE`, a
   claim that nothing was cached. A fully unreported usage (D-022) is first replaced by Task 10's
   estimate, whose `cache_read` is 0, so it never reaches the ledger as `NA`. A known zero still leaves them `FALSE`, and a positive read marks the
   leading components as planned.

The session footer follows D-021: an unknown token count or cost prints as `unknown tokens` /
`unknown cost` (new `format_cost()`), never `$NA` or zero, and `s$cost` is `NA` when any request's
cost is unknown.

Validation: `progress/P06.md`, Task 4 (`test-session-budget.R`, `test-session-object.R`; the added
tests failed 8 assertions against the plan-literal code).

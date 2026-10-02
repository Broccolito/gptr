# P06 Session Kernel and Agent Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the S-8 session object and the offline agent runtime of gptr: the session shell with its weak live registry, the append-only Pi-v3 JSONL store with fork, resume and replay, budgets and usage, the pure agent-loop state machine, the run lifecycle on P04's reactor, the never-throw tool dispatcher with the fail-closed permission kernel, and the `ctx.kernel` service.

**Architecture:** A session is a classed environment (the shell) whose only binding is `.d`, an unclassed data environment; live resources sit in `the$live[[id]] = rlang::new_weakref(key = shell, value = live)` and `the$last` holds the most recent shell strongly (IC-71). `agent-loop.R` is Pi's two nested loops rewritten as a pure state machine that the run engine (`agent-run.R`) drives from reactor callbacks: requests go out through P05's `provider_stream()`, tool batches through `agent-dispatch.R` (validate -> `tool_call` hooks -> `perm_check()` -> checkpointers -> execute in P04's tool FIFO -> `tool_result` hooks), and every entry is appended open-append-close to `<workspace root>/sessions/<stamp>_<id>.jsonl` inside `suspendInterrupts()`. Later plans reach the kernel through the kernel SDK of IC-33 and the `ctx.kernel` service; P06 reaches later plans only through the P07/P08/P11/P14/P15/P16/P18 services of 04 §7.0, each with its documented fallback.

**Tech Stack:** base R (>= 4.2.0); rlang (weak references, `obj_address()`, `duplicate()`); jsonlite (through P01's `json_encode()`/`json_decode()`); ps (lock creation times); cli (colours in the print footer); utils; P04's reactor; testthat 3e, withr and processx in tests (processx and pkgload only in the `skip_on_cran()` crash and lock tests); roxygen2 through `devtools::document()`.

**Spec:** dev/spec/03-architecture.md (§2.2, §2.3, §3.2, §5.1-5.5, §6.2, §6.4, §6.8.2-6.8.5, §6.9.1-6.9.2, §6.11, §6.18 INFRA-09..15/25/26, §12.5-12.6), dev/spec/04-interface-contract.md (§1.1-1.4, §2.1-2.2, §3.1, §4.1-4.8, §5.1, §5.7, §5.12-5.13, §6.5 `gptr_fork()`/`gptr_sessions()`/`gptr_resume()`/`gptr_last()`/`gptr_usage()`, §7.0-7.6, §7.11 permission request record, §8.1, §8.4, §9.1, §10.2-10.7, §11.4-11.5, §12.1-12.4, §15: IC-33, IC-34, IC-46, IC-52, IC-53, IC-55, IC-57, IC-59, IC-61, IC-66, IC-67, IC-69, IC-71), dev/spec/05-plan-decomposition.md (P06).

**Depends on:** P04, P05 (and through them P01, P02, P03). **Milestone:** M1.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never `<-`; `<<-` only for closure state), the native `|>` (never `%>%`), ASCII-only R sources including tests (non-ASCII as `\u` escapes), lines of at most 100 characters, `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()` for conditions (messages built by concatenation, never glue-interpolated), no `:::` in `R/`, no `.GlobalEnv`, no `withr::` in `R/`, every changed global state restored with `on.exit(..., add = TRUE)`, testthat 3e, no network in tests, `Rscript --vanilla` from the repository root `/Users/wanjun/Desktop/gptr`, one commit per task whose message ends with the attribution line required by the executing harness (conventions §10). Plan-specific requirements, copied from the specification:

- Owned files (05 P06): `R/session-object.R`, `R/session-live.R`, `R/session-store.R`, `R/session-budget.R`, `R/agent-loop.R`, `R/agent-run.R`, `R/agent-dispatch.R`, their test files `tests/testthat/test-session-object.R`, `test-session-live.R`, `test-session-store.R`, `test-session-budget.R`, `test-agent-loop.R`, `test-agent-run.R`, `test-agent-dispatch.R`, and `tests/testthat/fixtures/oracles/report02/` ("the 24 loop, 42 store and 26 recovery checks of report 02, converted to R test data"); plus `NAMESPACE` and `man/` through `Rscript --vanilla -e 'devtools::document()'`, and the snapshot file `tests/testthat/_snaps/session-object.md` of P06's own `expect_snapshot()` calls.
- Layers (03 §2.2, §3.2): `agent-loop.R` and `agent-dispatch.R` are L2; `session-*.R` and `agent-run.R` are L3. L2 "may call L0, L1 types" and, by P01's `arch_edge_ok()`, its own `agent` area, so the L2 files never call a `session-*.R` function: the dispatcher reaches the session through agent-area helpers of `agent-run.R` (`run_data()`, `run_ctx()`, `run_append_message()`, ...), and P01's `test-arch-layers.R` checks every edge. L3 "never call an L4 capability by function name" (registry lookups only); nothing below L5 prints except `print()` methods of P06's own classes.
- Exports (04 §14.1, §6.5), exact signatures: `gptr_fork(s, at = NULL, envir = c("overlay", "shared"))`, `gptr_sessions(project = TRUE)`, `gptr_resume(x = NULL, envir = parent.frame(), block = NULL, child = NULL)`, `gptr_last()`, `gptr_usage(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE)`. Their examples run offline: the parts that need `gptr()` (P08) are in `@examplesIf exists("gptr", mode = "function")` blocks. S3 methods of `gptr_session` (04 §5.1): `$`, `[[`, `$<-`, `[[<-`, `names`, `.DollarNames` (utils), `print`, `format`, `as.character`, `summary`, `str` (utils); `print.gptr_session_summary`.
- Kernel SDK owned here (IC-33): `session_data()`, `session_live()`, `session_home()`, `session_append()`, `session_set_model()`, `session_set_mode()`, `session_enqueue()`, `session_value_set()`, `session_value_get()`, `session_replay_apply()`, `session_replay_new()`, `session_replay_bind()`, `replay_lookup()`, `session_run()`, `run_start()`, `run_wait()`, `run_abort()`, `run_current()`, `run_eval_env()`, `run_emit()`, `dispatch_nested()`, `perm_check()`, `tool_result_message()`, `store_read()`, `store_rebuild()`, `last_set()`.
- Internal signatures (04 §7.6): `session_new(model, mode, home = NULL, kind = "chat", parent = NULL, preset = NULL, opts = list())`, `session_set_model(s, ref, reason = "user")`, `session_set_mode(s, mode, source = "user")`, `session_enqueue(s, text, as = c("steer", "follow_up"), source = "api_user", blocks = list())`, `session_value_set(s, label, value, name = NULL, forced_home = NULL)`, `session_value_get(s, turn = NULL)`, `live_all()`, `last_set(s)`, `store_open(s)`, `store_append(store, entries)`, `store_read(path)`, `store_close(store)`, `store_fork(s, cut, new)`, `store_rebuild(path, home)`, `store_heartbeat(store)`, `session_replay_apply(s, block, header, text = NULL)`, `session_replay_new(block, header, envir, doc)`, `session_replay_bind(block, s, child = NULL)`, `replay_lookup(block, child = NULL)`, `budget_check(s, estimate = 0)`, `ledger_add(s, request_id, components)`, `session_run(s, input, opts = list())`, `run_start(s, input, opts = list())`, `run_wait(runs, timeout = Inf)`, `run_abort(run, reason = "user")`, `run_current()`, `run_eval_env(run)`, `run_emit(run, type, ...)`, `dispatch_tools(run, calls)`, `dispatch_nested(name, input, ctx)`, `tool_validate(tool, input)`, `perm_check(call, run)`, `tool_result_message(result, call)`.
- Classes (04 §5.1, §5.12, §5.13): `gptr_session` (shell), `gptr_session_summary`, `gptr_usage`, `gptr_ledger`, `gptr_sessions` (listings through P01's `new_listing()`), `gptr_run`, `gptr_loop`, `gptr_store`.
- Package state owned (04 §7.0): `the$live` ("weak index of live sessions `id -> weakref(key = shell, value = live)`"), `the$last` ("the last session, held strongly (IC-71)"), `the$replay_blocks` ("block id -> the session replay bound to it (gptr-created sessions only, IC-46)"). No other package-global run state (INFRA-15).
- Consumed from P05 without redefinition: `usage_empty()` (the zero-row table with the 21 columns of 04 §4.3), `usage_row(msg, session, agent, parent_id, started, seconds, multiplier)`, `usage_new(...)`, `usage_log()`, `model_resolve(ref, strict = TRUE)`, `project_messages(entries, leaf, target)`, `adapter_get(api)`, `model_default(role = c("chat", "small", "system1"))`, `provider_stream(model, context, opts, emit, done, run = NULL)` (with `opts$gate`, `opts$tool_result` and `opts$mcp_dispatch` passed in `opts`, IC-33). P06 defines no function whose name another plan defines: P01's `usage_to_json()`/`usage_from_json()`, P04's `proc_create_time(pid)` and P08's `mode_tighter()`/`control_check()` exist, so P06's helpers are `entry_usage_to_json()`, `entry_usage_from_json()`, `lock_self_created()`, `run_mode_tighter()` and `session_control_check()` (two definitions of one name in `R/` would let the later-collating file silently replace the other; `usage_to_json()` replaced inside `msg_to_json()` would even recurse without end).
- Cross-plan slots P06 fills (from the P01, P02, P05, P07 and P08 plans): operator entries carry `custom_type = "gptr.operator"` (P05's `project_messages()` projects exactly those); `.d$frozen` is `NULL` until the first freeze (P07's `prompt_freeze()` freezes only a `NULL` value) and the freeze options are the run options plus `start`, `interactive` and `refreeze`; `live$out` starts `NULL` (P01's `out_store()` creates a `gptr_out_store` lazily and rejects a bare environment); the IC-53 one-shot approval tokens are function names in `run$signal$control` (P08's `control_check()`) plus P02's `ext_control_grant(run, what)`; the stored terminal condition is also `run$signal$condition` (P08's `gateway_signal()`).
- Ids (IC-20): session ids `s` + 10 lower hex (`id_new("s", 10L)`), entry ids 8 lower hex (`id_entry()`), request ids `q` + 12 hex, run ids `u` + 8 hex. `.Random.seed` is never touched (IC-61).
- Options owned (04 §3.1): `gptr.unsafe_no_permissions` (`FALSE`; "set outside a run only: no permission gate (sandboxed CI); snapshotted at run start (IC-53)"), `gptr.value_copy_max` (`1048576` bytes), `gptr.values_max_bytes` (`67108864` bytes), `gptr.max_turns` (`50L`), `gptr.max_nested_calls` (`20L`), `gptr.noninteractive_ask` (`"stop"` or `"deny"`; default `"stop"`). All read with `gptr_opt()`.
- Safety snapshot (IC-53 item 2): `run_start()` snapshots `gptr.ui`, `gptr.interactive`, `gptr.critical_guard`, `gptr.secret_guard`, `gptr.noninteractive_ask`, `gptr.protect_size`, `gptr.mode` and `gptr.unsafe_no_permissions`; "the run's gate reads only the snapshot".
- Gate (IC-04, IC-53, 03 §6.8.2): `perm_check(call, run)` returns `list(decision = "allow" | "deny" | "ask" | "ask_human" | "modify", reason, input, risk, rule)`; policies combine "deny > ask_human > ask > modify > allow; a throwing policy denies; no active `mode` policy = ask"; "a `modify` is re-classified and re-checked once (a second modify denies)"; `ask` goes to `permission_request` hooks (first decision; error = deny) then the UI; "an `ask_human` skips the hooks"; without a human `"stop"` stops the run with status `blocked` (stored condition `gptr_error_permission`, or `gptr_error_noninteractive` with `what = "ask"` and the questions when the blocked call is the `ask` tool, IC-68) and `"deny"` returns a denial; a policy answer that is not `NULL`, a list or one known decision denies (fail closed, as a throwing policy).
- Budgets (IC-66): settings default `budget = {cost: 5, tokens: 2000000, turns: null}` per top-level call; `budget_near` at 80%; reaching it "asks to extend by the same amount (`ask_human`) interactively and stops with status `budget` otherwise"; "`null` set explicitly disables a limit"; every request charges the root (the live runs of a session's ancestors, and the session named by the run option `root`, "the root session id for budgets" of 04 §7.6: its run, or one shared pool when it has no run, as a top-level team or fan-out container); `gptr.max_nested_calls` = 20 `gptr()` calls per `r` evaluation.
- Store (IC-59, 04 §11.4): `<workspace root>/sessions/<YYYYmmddTHHMMSS>_<session id>.jsonl`; header §4.7 (`"type":"session","version":3`); entries §4.6; each append is `file(path, "ab")` opened, written, flushed and closed through `on.exit()` inside `suspendInterrupts()`; a resume on a file whose last byte is not LF first appends `"\n"` and a `gptr.recovered` entry `{from, to}`; readers skip unparsable lines with a diagnostic and re-parent children of missing ids; lock directory `<file>.lock/` with file `pid` holding the pid and the process creation time, touched every 10 minutes, stale when `pid_alive()` is `FALSE` or its heartbeat is older than 24 h.
- Custom entries written here (04 §4.6): `gptr.mode_change` `{from, to, source}`, `gptr.value` `{turn, mode, name, address, class, bytes}` (never the value), `gptr.recovered` `{from, to}`, `gptr.router` `{router, state, model, reason}`, `gptr.image_elision` `{images: [ids]}`, `gptr.budget` `{kind, budget, used}`, `gptr.replay` `{doc, block, mode, turn, value}`; plus, on behalf of other owners, `gptr.frozen` (only the fallback freeze before P07), `gptr.checkpoint` (the container of checkpointer fragments) and `gptr.ext` (`ctx$state()` persistence).
- Texts (04 §4.2, IC-55): the steering relay is exactly `The user sent this message while you were working: <text>` (user sources `pipe`, `pause_menu`, `repl`, `api_user` only); extension items are user-role `Extension <name> sent this note (not from the user): <text>`; agent items are user-role `<agent_report from="<name>">` data; the unknown tool text is `Tool <name> not found` (04 §7.6).
- Recovery (C-33, INFRA-26): at most two agent-level retries of transient errors, 2 s then 4 s; one compact-and-retry per run through the `compact.run` service; a second overflow surfaces as `gptr_error_context_overflow` (parent `gptr_error_provider`, field `tokens`).
- Conditions (04 §2.2): `gptr_error_readonly` (`object`, `field`), `gptr_error_unknown_member` (`name`, `available`), `gptr_error_invalid_argument` (`arg`, `expected`), `gptr_error_split_brain` (`id`, `holder_pid`), `gptr_error_busy` (`session`), `gptr_error_replay_unbound` (parent `gptr_error_not_recorded`; `block`, `child`), `gptr_error_permission` (`action`, `tool`, `risk`, `how_to_allow`, `session`), `gptr_error_noninteractive` (`what`, `questions`; the `ask` tool in a run nobody can answer, IC-68), `gptr_error_budget` and `gptr_error_budget_tokens|cost|turns` (`kind`, `budget`, `used`, `session`), `gptr_error_max_turns` (`max_turns`, `session`), `gptr_error_provider` and subclasses (`provider`, `model`, `status`, `request_id`, `error_type`, `session`), `gptr_error_tool` (`tool`, `status`), `gptr_error_internal` (`detail`); messages `gptr_message_value_rebound` and `gptr_message_notice`. Terminal-status conditions are stored unsignalled; the gateway (P08) signals them (04 §6.1.2).
- Events emitted (04 §10.4): `session_start` (collect; reasons `new`, `fork`, `resume`, `replay`, `child`), `session_before_fork` (first decision), `session_shutdown` (reasons `gc`, `unload`), `agent_start`, `agent_end` (`status`, `reason`, `usage`, `doc`, `turns`), `turn_start`, `turn_end` (`message`, `results`), `before_request` (`provider`, `model`, `request_id`, `view`, `tokens_est`), `request_params` (patch chain), `message_start`, `message_update` (`index`, `kind`, `delta`), `message_end` (`message`), `tool_call` (decision, error = block), `permission_request` (first decision, error = deny), `tool_execution_start`, `tool_execution_update` (`tool_call_id`, `tool_name`, `text`), `tool_execution_end`, `tool_result` (patch chain), `queue_update` (`steer`, `follow_up`), `retry_start`, `retry_end`, `usage` (`row`), `budget_near`, `budget_exceeded`, `model_select` (`from`, `to`, `reason`), `route`. Every event is built with `ev_new()` and dispatched with `ev_dispatch()` (P02), which redacts payloads with the `stream` profile.
- Services (04 §7.0): provided `ctx.kernel` (`function() named list` of the §10.6 members marked P06: `envir`, `run`, `mode`, `model`, `execute_tool`, `send`, `set_model`, `append_entry`, `abort`, `aborted`, `update`, `usage`, `state`; each implementation takes the `ctx` first, then the member's arguments, positionally, in the convention P02's `ctx_new()` uses: `send(ctx, text, as[, plugin])`, `append_entry(ctx, type, data[, plugin])`, `state(ctx[, plugin])`, where the optional last argument is passed only inside a handler and is the handler's plugin name with its source prefix removed (`"plugin:panel"` -> `"panel"`); P06 names that formal `extension = NULL` and its `ctx_ext_label()` accepts the bare name or a full source). Consumed, with the documented fallbacks of 04 §7.0 ("freeze: empty T0/T1 and the direct tools' JSON; first message: the prompt alone; request: the projected messages; no prefix guard; no compaction"): `prompt.freeze`, `request.build`, `prefix.guard`, `compact.should`, `compact.run`, `console.interrupt_policy` (else abort-only), `ui.get`, `risk.classify`, `router.call`, `checkpoint.note`, `mcp.dispatch_local`, `settings.get` (through `setting_get()`). The built-in `store` record `jsonl` (IC-69) is declared as `builtin:store`.
- Copy safety (03 §6.4, G3 verification log): "never put a user frame in a list or closure that can become garbage; hold it only in environment bindings that are explicitly reset"; a function-frame home lives only in the run's `home` binding, reset to `NULL` at settlement; the live index is weak and keyed on shells, which hold no frames or user objects (R10); values follow the §5.1 value policy (R1); interruptions of tools are recorded with `on.exit()`, never an exiting `tryCatch(interrupt =)`. Settlement cancels the run's reactor task, timers, transfers and a FIFO tool job that has not started, so that nothing keeps a settled session alive. Tool `value`s never enter events or the loop state: the loop and `turn_end` receive the tool-result messages (rule R1).
- Tests (conventions §7, 04 §12): the fake provider (`gptr_fake_provider()`, `local_fake_provider()`, `fake_text()`, `fake_tool()`, `fake_tools()`, `fake_error()`, `fake_requests()`), `local_project()`, `local_gptr_options()`; processes only under `skip_on_cran()` and started with `rscript_path()`; `pkgload::load_all()` only inside the text of a generated child script; printed output through `expect_snapshot()` inside `testthat::local_reproducible_output(width = 80)`. The shared P06 test harness lives in P06's own fixture directory (`fixtures/oracles/report02/harness.R`) and is sourced by each P06 test file; closures registered in the registry by tests are defined at the top level of a test file whenever a test later expects the session to be garbage-collected (a closure created inside a helper keeps the helper's frame, and the session in it, alive).
- Test commands use anchored filters (`devtools::test(filter = "^agent-loop$")`) so that later plans' files with similar names never run. The expected summary lines were measured on macOS (R 4.4.3, testthat 3.3.2, roxygen2 7.3.3) with stand-ins for P01-P05 that follow 04 §7.1-7.5 and §12.1-12.2 (P05's `usage_empty()` copied verbatim from its plan) and with `NOT_CRAN=true` (as `devtools::test()` sets it); FAIL counts are exact, and PASS counts match whenever the earlier plans behave as the contract specifies.

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `R/agent-loop.R` | create (Task 1) | the pure L2 loop state machine `gptr_loop` (Pi's two nested loops), `max_turns`, queue-item messages (relays by source) |
| `R/session-budget.R` | create (Task 2), extend (Tasks 4, 5, 11) | usage frames and the token ledger, roll-up to ancestors, budget limits and checks, `gptr_usage()` |
| `R/session-object.R` | create (Task 3), extend (Tasks 4, 6, 12, 13, 14) | shell and `.d`, entries and paths, accessors, printing, value policy, model/mode/queue verbs, `gptr_fork()`, the replay table and the replay functions |
| `R/session-live.R` | create (Task 3) | weak live registry, homes (R2), finalizer, unload, split-brain attach, pid locks, `gptr_last()` |
| `R/session-store.R` | create (Task 3), extend (Tasks 12, 13) | the open-append-close writer, header, R -> JSON entries, torn-line recovery, fork files, the `builtin:store` record, reader, rebuild, `gptr_sessions()`, `gptr_resume()` |
| `R/agent-run.R` | create (Task 5), extend (Tasks 8, 9, 10, 14, 15) | run records, events, recovery classification, request shaping, the run engine, the reconstructed-history notice, `ctx.kernel` |
| `R/agent-dispatch.R` | create (Task 7) | the never-throw tool dispatcher, nested calls, `tool_result_message()`, checkpointer calls, `perm_check()` |
| `tests/testthat/fixtures/oracles/report02/harness.R` | create (Task 1) | P06's shared test helpers and the oracle loader |
| `tests/testthat/fixtures/oracles/report02/store.json`, `recovery.json`, `loop.json` | create (Tasks 3, 8, 10) | report 02's 42 store, 26 recovery and 24 loop checks as R test data |
| `tests/testthat/test-agent-loop.R` | create (Task 1), extend (Task 10) | state machine; report 02 loop checks L01-L24 |
| `tests/testthat/test-session-budget.R` | create (Task 2), extend (Tasks 4, 5, 10, 11) | frames, roll-up, budgets, `gptr_usage()` |
| `tests/testthat/test-session-object.R` | create (Task 3), extend (Tasks 4, 6, 12, 14, 16) | shell, accessors, printing, value policy, verbs, fork, replay, exports |
| `tests/testthat/test-session-live.R` | create (Task 3), extend (Task 13) | registry, homes, gc, locks, split brain, connections |
| `tests/testthat/test-session-store.R` | create (Task 3), extend (Tasks 7, 9, 10, 12, 13) | report 02 store checks S01-S42, crash safety, listing, resume |
| `tests/testthat/test-agent-run.R` | create (Task 5), extend (Tasks 8, 9, 10, 15) | run records, recovery checks R01-R26, request shaping, engine, `ctx.kernel` |
| `tests/testthat/test-agent-dispatch.R` | create (Task 7), extend (Task 10) | dispatcher pipeline, perm matrix, nested calls, INFRA-09/10 |
| `tests/testthat/_snaps/session-object.md` | create (Task 4) | the expected `expect_snapshot()` output of `print()` and `str()` |
| `NAMESPACE`, `man/gptr_fork.Rd`, `man/gptr_sessions.Rd`, `man/gptr_resume.Rd`, `man/gptr_last.Rd`, `man/gptr_usage.Rd`, `man/session-accessors.Rd`, `man/print.gptr_session.Rd`, `man/format.gptr_session.Rd`, `man/summary.gptr_session.Rd`, `man/print.gptr_session_summary.Rd`, `man/str.gptr_session.Rd` | generated (Task 16) | by `devtools::document()` |

## Tasks (overview)

1. Agent-loop state machine and the P06 test harness (`agent-loop.R`)
2. Usage frames and the ledger frame (`session-budget.R`)
3. Session shell, transcript, live registry, locks and the store writer (`session-object.R`, `session-live.R`, `session-store.R`)
4. Accessors, printing, the value policy and usage roll-up (`session-object.R`, `session-budget.R`)
5. Run records, events and budget checks (`agent-run.R`, `session-budget.R`)
6. Session verbs: model, mode and the steering queue (`session-object.R`)
7. Tool dispatcher and permission kernel (`agent-dispatch.R`)
8. Recovery classification (`agent-run.R`)
9. Request shaping: freeze, routers, request params, image elision, returns (`agent-run.R`)
10. The run engine (`agent-run.R`)
11. `gptr_usage()` (`session-budget.R`)
12. `gptr_fork()` and fork files (`session-object.R`, `session-store.R`)
13. Reader, resume, listing and crash safety (`session-store.R`, `session-object.R`)
14. Replay functions (IC-46) (`session-object.R`, `agent-run.R`)
15. The `ctx.kernel` service (`agent-run.R`)
16. Documentation, NAMESPACE and plan acceptance

---
### Task 1: Agent-loop state machine and the P06 test harness

**Files:**

- Create: `R/agent-loop.R`
- Create: `tests/testthat/fixtures/oracles/report02/harness.R`
- Test: `tests/testthat/test-agent-loop.R`

**Interfaces:**

Consumes:

- P01 (04 §4.1-4.2): `msg_user(content, source = "prompt", timestamp = NULL)`, `msg_operator(kind, text, tool_add = NULL, origin_text = NULL, timestamp = NULL)`, `block_text(text, signature = NULL)`, `block_context(kind, text, attrs = list(), anchor = FALSE)`, `` `%||%` ``.
- Tests and harness (04 §12.2, §6.7-6.8, §7.2): `json_decode(text)`, `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())`, `local_gptr_options(..., .env = parent.frame())` (P01); `gptr_tool()`, `gptr_policy(name, check, description = NULL)`, `gptr_spec(kind, name, ...)`, `gptr_register(spec)`, `registry_add(spec, source, rank, session = NULL, state = "active")`, `registry_remove(id)`, `hook_add(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL)`, `hook_remove(id)` (P02). The harness only defines helpers; the helpers that call later P06 functions (`test_session()`, `test_run()`, `run_text()`) are first used in Tasks 3-5.

Produces:

- `loop_new(max_turns = NULL, steering = function() list(), follow_up = function() list(), finish_turn = function(turn) NULL, emit = function(type, ...) invisible(NULL))` -> an environment of class `gptr_loop`.
- `loop_next(lp)` -> `list(action = "request", messages)`, `list(action = "tools", calls, message, truncated)`, `list(action = "end", reason)` or `list(action = "wait")`; `loop_response(lp, message)`, `loop_results(lp, results, terminate = FALSE)`, `loop_end(lp, reason)`.
- `queue_item_message(item, which, relay = FALSE)` (IC-55 texts); `queue_user_sources`, `queue_sources`.
- Harness helpers used by every later P06 test file: `oracle(group)`, `oracle_title(recs, id)`, `expect_oracles_covered(recs, file)`, `local_store()`, `local_tool()`, `local_policy()`, `local_service()`, `local_without_services()` (hides later plans' bootstrap services so that a fallback test keeps testing the fallback in the full suite), `local_hook()`, `local_events()`, `local_permissive()`, `test_session()`, `test_run()`, `run_text()`, `roles()`, `tool_results()`, `req_roles()`, `num_schema()`.

- [ ] **Step 1: Write the failing test**

The harness is sourced (not a `helper-*.R` file, which P06 does not own) by the first line of every P06 test file. The state machine is tested in isolation with hand-written assistant messages; the report 02 loop checks L01-L24 that need the engine come in Task 10.

Create `tests/testthat/fixtures/oracles/report02/harness.R`:

```r
# Shared test harness of P06 (session kernel and agent loop). The first line of every P06 test
# file sources this file with local = TRUE, locating it through testthat::test_path().
# It lives in P06's own fixture directory (P06 owns no helper-*.R file) and holds the loader of
# report 02's oracle checks plus small helpers built only on P01's test helpers (contract 04
# section 12.2) and the P02 registry API.

#' The report 02 oracle checks of one group ("loop", "store", "recovery"), keyed by id
oracle = function(group) {
  path = testthat::test_path("fixtures", "oracles", "report02", paste0(group, ".json"))
  recs = json_decode(paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n"))
  stats::setNames(recs, vapply(recs, function(r) r$id, ""))
}

#' The title of the test of one oracle check: "<id> <gptr assertion>"
oracle_title = function(recs, id) paste(id, recs[[id]]$gptr)

#' Every oracle id of `recs` has a test_that() titled with oracle_title() in `file`
expect_oracles_covered = function(recs, file) {
  src = paste(readLines(testthat::test_path(file), encoding = "UTF-8", warn = FALSE),
              collapse = "\n")
  hits = regmatches(src, gregexpr("oracle_title\\([a-z_]+, \"[A-Z][0-9]{2}\"\\)", src))[[1L]]
  ids = sub("^.*\"([A-Z][0-9]{2})\"\\)$", "\\1", hits)
  testthat::expect_setequal(unique(ids), names(recs))
}

#' A temporary project with a .gptr/ workspace that project_root() resolves to
local_store = function(.env = parent.frame()) {
  dir = local_project(.env = .env)
  withr::local_envvar(GPTR_PROJECT_ROOT = dir, .local_envir = .env)
  withr::local_options(gptr.project_root = dir, .local_envir = .env)
  dir
}

#' Register a test tool (rank 3) for the calling test
local_tool = function(name, execute, parameters = list(type = "object", properties = json_obj()),
                      execution = "sequential", annotations = list(), risk = NULL,
                      .env = parent.frame()) {
  spec = gptr_tool(name, paste("Test tool", name), parameters = parameters, execute = execute,
                   execution = execution, annotations = annotations, risk = risk)
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  invisible(spec)
}

#' Register a test policy (rank 3) for the calling test
local_policy = function(name, check, .env = parent.frame()) {
  off = gptr_register(gptr_policy(name, check))
  withr::defer(off(), envir = .env)
  invisible(NULL)
}

#' Provide or replace a service through the registry's `service` kind (IC-34)
local_service = function(name, fun, .env = parent.frame()) {
  id = registry_add(gptr_spec("service", name, fun = fun), source = "user", rank = 3L)
  withr::defer(registry_remove(id), envir = .env)
  invisible(id)
}

#' Hide bootstrap services of later plans for the calling test (the fallbacks of 04 section 7.0)
#'
#' P07, P11, ... register their services in P01's bootstrap table from on_load(), so in the full
#' suite `ext_service_has()` is TRUE for them; a test of a P06 fallback hides them first. Records
#' added with local_service() live in the registry and are not affected.
local_without_services = function(names, .env = parent.frame()) {
  old = the$services
  withr::defer(assign("services", old, envir = the), envir = .env)
  svc = old
  for (nm in names) svc[[nm]] = NULL
  assign("services", svc, envir = the)
  invisible(NULL)
}

#' A process-wide hook, or a session listener when `session` (an id) is given
local_hook = function(event, handler, session = NULL, .env = parent.frame()) {
  id = hook_add(event, handler, rank = if (is.null(session)) 3L else 0L,
                source = if (is.null(session)) "user" else "session", session = session)
  withr::defer(hook_remove(id), envir = .env)
  invisible(id)
}

#' Record events of the given types; returns an accessor `function(s = NULL)`
local_events = function(types, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$events = list()
  for (type in types) {
    local_hook(type, function(event, ctx) {
      log$events[[length(log$events) + 1L]] = event
      NULL
    }, .env = .env)
  }
  function(s = NULL) {
    ev = log$events
    if (is.null(s)) ev else Filter(function(e) identical(e$session, session_data(s)$id), ev)
  }
}

#' Allow every tool call in the calling test (the IC-53 escape hatch, set outside the run)
local_permissive = function(.env = parent.frame()) {
  local_gptr_options(unsafe_no_permissions = TRUE, .env = .env)
}

#' A fresh session on the fake provider (register one with local_fake_provider() first)
test_session = function(mode = "auto", home = new.env(), model = "fake/fake-1", ...) {
  session_new(model, mode, home = home, ...)
}

#' A run record attached to a session without starting it (unit tests of gates and budgets)
test_run = function(s, opts = list(), .env = parent.frame()) {
  run = run_new(s, opts, NULL)
  live = session_live(s)
  live$run = run
  withr::defer(assign("run", NULL, envir = live), envir = .env)
  run
}

run_text = function(s, text, opts = list()) session_run(s, msg_user(text), opts)
roles = function(s) vapply(s$messages, function(m) m$role, "")
tool_results = function(s) Filter(function(m) identical(m$role, "tool_result"), s$messages)
req_roles = function(req) vapply(req$messages, function(m) m$role, "")
num_schema = function(...) {
  props = lapply(list(...), function(type) list(type = type))
  list(type = "object", required = I(names(props)), properties = props)
}
```

Create `tests/testthat/test-agent-loop.R`:

```r
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# ---------------------------------------------------------------- the pure state machine

reply_text = function(text = "ok", stop = "stop") {
  list(role = "assistant", content = list(list(type = "text", text = text)), stop_reason = stop)
}
reply_tool = function(name = "t", stop = "tool_use") {
  list(role = "assistant", stop_reason = stop,
       content = list(list(type = "tool_call", id = "c1", name = name, arguments = list())))
}
drive = function(lp, replies, terminate = FALSE) {
  actions = character()
  n = 0L
  repeat {
    act = loop_next(lp)
    actions = c(actions, act$action)
    if (identical(act$action, "end")) return(list(reason = act$reason, actions = actions,
                                                  requests = n))
    if (identical(act$action, "request")) {
      n = n + 1L
      loop_response(lp, replies[[min(n, length(replies))]])
    }
    if (identical(act$action, "tools")) loop_results(lp, list("r"), terminate)
  }
}
event_log = function() {
  log = new.env()
  log$types = character()
  log$emit = function(type, ...) log$types = c(log$types, type)
  log
}

test_that("a text reply ends the loop after one request and one turn_end", {
  ev = event_log()
  lp = loop_new(emit = ev$emit)
  expect_s3_class(lp, "gptr_loop")
  out = drive(lp, list(reply_text()))
  expect_identical(out$reason, "stop")
  expect_identical(out$requests, 1L)
  expect_identical(ev$types, "turn_end")
})

test_that("a tool reply asks for tools, then a second turn starts with turn_start", {
  ev = event_log()
  out = drive(loop_new(emit = ev$emit), list(reply_tool(), reply_text()))
  expect_identical(out$actions, c("request", "tools", "request", "end"))
  expect_identical(ev$types, c("turn_end", "turn_start", "turn_end"))
})

test_that("while a response is outstanding the loop waits", {
  lp = loop_new()
  expect_identical(loop_next(lp)$action, "request")
  expect_identical(loop_next(lp)$action, "wait")
})

test_that("steering is polled at the start and after each turn; follow-ups only when stopping", {
  queues = new.env()
  queues$steer = list(list(role = "operator", kind = "steer_relay"))
  queues$follow = list(list(role = "user", source = "follow_up"))
  queues$polled = character()
  take = function(which) {
    function() {
      queues$polled = c(queues$polled, which)
      x = queues[[which]]
      queues[[which]] = list()
      x
    }
  }
  lp = loop_new(steering = take("steer"), follow_up = take("follow"))
  sent = list()
  repeat {
    act = loop_next(lp)
    if (identical(act$action, "end")) break
    if (identical(act$action, "request")) {
      sent[[length(sent) + 1L]] = act$messages
      loop_response(lp, reply_text())
    }
  }
  expect_identical(queues$polled[1:3], c("steer", "steer", "follow"))
  expect_length(sent, 2L)
  expect_identical(sent[[1L]][[1L]]$role, "operator")
  expect_identical(sent[[2L]][[1L]]$source, "follow_up")
})

test_that("max_turns caps the requests of a run", {
  out = drive(loop_new(max_turns = 3L), list(reply_tool()))
  expect_identical(out$reason, "max_turns")
  expect_identical(out$requests, 3L)
})

test_that("a batch whose results all terminate ends the run without another request", {
  out = drive(loop_new(), list(reply_tool(), reply_text()), terminate = TRUE)
  expect_identical(out$reason, "stop")
  expect_identical(out$requests, 1L)
})

test_that("error and aborted responses end the loop after turn_end", {
  ev = event_log()
  out = drive(loop_new(emit = ev$emit), list(reply_text(stop = "error")))
  expect_identical(out$reason, "error")
  expect_identical(ev$types, "turn_end")
  expect_identical(drive(loop_new(), list(reply_text(stop = "aborted")))$reason, "aborted")
})

test_that("length and refusal stops mark the tool batch truncated", {
  lp = loop_new()
  loop_next(lp)
  loop_response(lp, reply_tool(stop = "length"))
  act = loop_next(lp)
  expect_identical(act$action, "tools")
  expect_true(act$truncated)
})

test_that("finish_turn can end the loop with a reason", {
  out = drive(loop_new(finish_turn = function(turn) list(action = "end", reason = "blocked")),
              list(reply_tool()))
  expect_identical(out$reason, "blocked")
  expect_identical(out$requests, 1L)
})

test_that("queue items become relays, user messages, extension notes and agent reports (IC-55)", {
  it = function(source, name = NULL) {
    list(text = "use TPM", blocks = list(), source = source, name = name, t = 0)
  }
  relay = queue_item_message(it("pipe"), "steer", relay = TRUE)
  expect_identical(relay$role, "operator")
  expect_identical(relay$kind, "steer_relay")
  expect_identical(msg_text(relay), "The user sent this message while you were working: use TPM")
  expect_identical(queue_item_message(it("pipe"), "steer", relay = FALSE)$role, "user")
  expect_identical(queue_item_message(it("repl"), "follow_up", relay = TRUE)$source, "follow_up")
  ext = queue_item_message(it("extension", "panel"), "steer", relay = TRUE)
  expect_identical(ext$role, "user")
  expect_identical(msg_text(ext), "Extension panel sent this note (not from the user): use TPM")
  rep = queue_item_message(it("agent", "stats"), "steer", relay = TRUE)
  expect_identical(rep$source, "agent")
  expect_identical(rep$content[[1L]]$type, "context")
  expect_match(rep$content[[1L]]$text, "<agent_report from=\"stats\">", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^agent-loop$")'`

Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 0 ]`, with errors such as ``Error in `loop_new(emit = ev$emit)`: could not find function "loop_new"``.

- [ ] **Step 3: Write the implementation**

Pi's `runLoop()` (packages/agent/src/agent-loop.ts:102-321 at 1b347794; report 02 §2.2, prototype `run_agent_loop()` in §5.1) becomes explicit states: `begin` polls steering once, `inner` loops while there is more to do or pending messages, `turn` issues one request (`max_turns` caps requests), `tools` hands the batch to the engine, `after_turn` asks `finish_turn()` whether the run ends (gptr additions: `blocked`, `aborted`, `budget`), `outer` drains follow-ups. `turn_start` is emitted by the loop only for turns after the first (the engine emits the first with `agent_start`).

Create `R/agent-loop.R`:

```r
# agent-loop.R -- the pure agent-loop state machine (P06, layer L2).
#
# Pi's two nested loops (packages/agent/src/agent-loop.ts:102-321 at 1b347794, restated in
# dev/research/02-pi-agent-loop-sessions.md section 2.2 and prototyped in section 5.1 as
# `run_agent_loop()`), rewritten as a state machine so that the run engine (agent-run.R) can drive
# it from reactor callbacks. The loop knows nothing about sessions, stores, providers or the
# reactor: the engine asks `loop_next()` for the next action, performs it and reports the outcome
# with `loop_response()` or `loop_results()`. gptr additions (report 02 section 4.11): a finite
# `max_turns` that caps the model requests of one run, and `finish_turn()` decisions that end the
# run (`blocked`, `aborted`, `budget`).

queue_user_sources = c("pipe", "pause_menu", "repl", "api_user")
queue_sources = c(queue_user_sources, "extension", "agent")

#' Create a loop state machine
#'
#' @param max_turns Integer or NULL: the most model requests this run may make.
#' @param steering,follow_up Functions of no argument returning a list of messages (at most one
#'   queue item each, one-at-a-time delivery as in Pi).
#' @param finish_turn Function of `list(message, results, turn)` returning `NULL` or
#'   `list(action = "end", reason = chr(1))`.
#' @param emit Function `(type, ...)` for the loop-owned events `turn_start` and `turn_end`.
#' @return An environment of class `gptr_loop`.
#' @noRd
loop_new = function(max_turns = NULL, steering = function() list(), follow_up = function() list(),
                    finish_turn = function(turn) NULL, emit = function(type, ...) invisible(NULL)) {
  lp = new.env(parent = emptyenv())
  lp$state = "begin"
  lp$turn = 0L
  lp$first = TRUE
  lp$has_more = TRUE
  lp$pending = list()
  lp$message = NULL
  lp$calls = list()
  lp$results = list()
  lp$reason = NULL
  lp$max_turns = if (is.null(max_turns)) NULL else as.integer(max_turns)
  lp$steering = steering
  lp$follow_up = follow_up
  lp$finish_turn = finish_turn
  lp$emit = emit
  class(lp) = "gptr_loop"
  lp
}

#' The next action of the loop
#'
#' @return One of `list(action = "request", messages)` (the queued messages to append before the
#'   request), `list(action = "tools", calls, message, truncated)`, `list(action = "end", reason)`
#'   or `list(action = "wait")` while a response or a tool batch is outstanding.
#' @noRd
loop_next = function(lp) {
  repeat {
    st = lp$state
    if (identical(st, "begin")) {
      lp$pending = lp$steering()
      lp$has_more = TRUE
      lp$state = "inner"
    } else if (identical(st, "inner")) {
      lp$state = if (lp$has_more || length(lp$pending) > 0L) "turn" else "outer"
    } else if (identical(st, "turn")) {
      if (!is.null(lp$max_turns) && lp$turn >= lp$max_turns) return(loop_end(lp, "max_turns"))
      if (!lp$first) {
        if (!length(lp$pending)) lp$pending = lp$steering()
        lp$emit("turn_start")
      }
      lp$first = FALSE
      msgs = lp$pending
      lp$pending = list()
      lp$turn = lp$turn + 1L
      lp$state = "await_response"
      return(list(action = "request", messages = msgs))
    } else if (identical(st, "tools")) {
      lp$state = "await_tools"
      stop_reason = lp$message$stop_reason %||% "stop"
      return(list(action = "tools", calls = lp$calls, message = lp$message,
                  truncated = stop_reason %in% c("length", "refusal")))
    } else if (identical(st, "failed")) {
      lp$finish_turn(list(message = lp$message, results = list(), turn = lp$turn))
      lp$emit("turn_end", message = lp$message, results = list())
      return(loop_end(lp, lp$message$stop_reason %||% "error"))
    } else if (identical(st, "after_turn")) {
      decision = lp$finish_turn(list(message = lp$message, results = lp$results, turn = lp$turn))
      lp$emit("turn_end", message = lp$message, results = lp$results)
      if (is.list(decision) && identical(decision$action, "end")) {
        return(loop_end(lp, decision$reason %||% "stop"))
      }
      lp$pending = lp$steering()
      lp$state = "inner"
    } else if (identical(st, "outer")) {
      fu = lp$follow_up()
      if (!length(fu)) return(loop_end(lp, "stop"))
      lp$pending = fu
      lp$has_more = TRUE
      lp$state = "inner"
    } else if (identical(st, "done")) {
      return(list(action = "end", reason = lp$reason))
    } else {
      return(list(action = "wait"))
    }
  }
}

#' Record the assistant message of the current request
#' @noRd
loop_response = function(lp, message) {
  lp$message = message
  lp$results = list()
  if ((message$stop_reason %||% "stop") %in% c("error", "aborted")) {
    lp$state = "failed"
    return(invisible(lp))
  }
  lp$calls = Filter(function(b) identical(b$type, "tool_call"), message$content %||% list())
  lp$has_more = FALSE
  lp$state = if (length(lp$calls)) "tools" else "after_turn"
  invisible(lp)
}

#' Record the tool results of the current turn; `terminate = TRUE` ends the run after this batch
#' @noRd
loop_results = function(lp, results, terminate = FALSE) {
  lp$results = results
  lp$has_more = !isTRUE(terminate)
  lp$state = "after_turn"
  invisible(lp)
}

#' End the loop with a reason
#' @noRd
loop_end = function(lp, reason) {
  lp$state = "done"
  lp$reason = reason
  list(action = "end", reason = reason)
}

#' Turn one queue item into the message delivered to the model (IC-55)
#'
#' Steers from user sources become operator relays once the run has made a request (`relay =
#' TRUE`); before that, and for follow-ups, they are ordinary user messages. Extension notes and
#' agent reports are user-role data and never relays.
#' @param item A queue item `list(text, blocks, source, t)` (optionally `name` for extension and
#'   agent items).
#' @param which `"steer"` or `"follow_up"`.
#' @noRd
queue_item_message = function(item, which, relay = FALSE) {
  text = item$text
  blocks = item$blocks %||% list()
  if (item$source %in% queue_user_sources) {
    if (identical(which, "steer") && isTRUE(relay)) {
      return(msg_operator("steer_relay",
                          paste0("The user sent this message while you were working: ", text),
                          origin_text = text))
    }
    return(msg_user(c(blocks, list(block_text(text))), source = which))
  }
  if (identical(item$source, "extension")) {
    note = paste0("Extension ", item$name %||% "plugin", " sent this note (not from the user): ",
                  text)
    return(msg_user(c(blocks, list(block_text(note))), source = "extension"))
  }
  content = if (length(blocks)) {
    blocks
  } else {
    list(block_context("agent_report", text, attrs = list(from = item$name %||% "agent")))
  }
  msg_user(content, source = "agent")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^agent-loop$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 33 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/agent-loop.R tests/testthat/fixtures/oracles/report02/harness.R tests/testthat/test-agent-loop.R
git commit -m "feat(agent): add the agent-loop state machine and the P06 test harness"
```

---

### Task 2: Usage frames and the ledger frame

**Files:**

- Create: `R/session-budget.R`
- Test: `tests/testthat/test-session-budget.R`

**Interfaces:**

Consumes:

- P05: `usage_empty()` (the zero-row usage table with the 21 columns of 04 §4.3, in order).

Produces:

- `usage_columns` (the 21 column names of 04 §4.3), `usage_token_columns`.
- `usage_conform(row)` -> the rows with the §4.3 columns, order and types (missing token and cost columns 0, other missing columns `NA`, `started` POSIXct).
- `usage_totals(u)` -> named num `requests`, `input`, `output`, `cache_read`, `cache_write`, `cost`.
- `ledger_empty()` -> the zero-row ledger (`request_id`, `component`, `tokens`, `cached`) of 04 §4.3; `format_count(n)` -> `"950"`, `"1.2k"`, `"3.4M"`.

- [ ] **Step 1: Write the failing test**

These are the data-frame helpers every later budget and usage function builds on.

Create `tests/testthat/test-session-budget.R`:

```r
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

usage_fixture = function(session, request_id, cost = 0, input = 100, agent = "main",
                         route = "api") {
  usage_conform(data.frame(request_id = request_id, session = session, agent = agent,
                           parent_id = NA_character_, provider = "fake", model = "fake-1",
                           route = route, input = input, output = 10, cache_read = 0,
                           cache_write_5m = 0, cache_write_1h = 0, reasoning = 0, images = 0,
                           cost = cost, tier = "default", stop_reason = "stop",
                           started = Sys.time(), seconds = 1, estimated = FALSE, multiplier = 1,
                           stringsAsFactors = FALSE))
}

test_that("usage_columns are the 21 section 4.3 columns of P05's usage_empty(), in order", {
  u = usage_empty()
  expect_identical(names(u), usage_columns)
  expect_length(usage_columns, 21L)
  expect_identical(nrow(u), 0L)
  expect_s3_class(u$started, "POSIXct")
})

test_that("usage_conform() orders the columns, fills missing ones and fixes the types", {
  row = data.frame(model = "fake-1", request_id = "q000000000001", input = 5L, output = 2L,
                   started = 0, stringsAsFactors = FALSE)
  u = usage_conform(row)
  expect_identical(names(u), usage_columns)
  expect_identical(u$request_id, "q000000000001")
  expect_true(is.na(u$session))
  expect_identical(u$input, 5)
  expect_identical(u$cost, 0)
  expect_s3_class(u$started, "POSIXct")
  expect_identical(nrow(usage_conform(usage_empty())), 0L)
})

test_that("usage_totals() sums requests, tokens and cost", {
  u = rbind(usage_fixture("s1", "q1", cost = 0.25), usage_fixture("s1", "q2", cost = 0.5))
  tot = usage_totals(u)
  expect_identical(names(tot), c("requests", "input", "output", "cache_read", "cache_write",
                                 "cost"))
  expect_equal(unname(tot[c("requests", "input", "cost")]), c(2, 200, 0.75))
})

test_that("ledger_empty() has the ledger columns and format_count() abbreviates", {
  expect_identical(names(ledger_empty()), c("request_id", "component", "tokens", "cached"))
  expect_identical(format_count(950), "950")
  expect_identical(format_count(1234), "1.2k")
  expect_identical(format_count(3.4e6), "3.4M")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-budget$")'`

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`, with errors such as ``Error in `usage_conform(row)`: could not find function "usage_conform"``.

- [ ] **Step 3: Write the implementation**

IC-05 moved `gptr_usage()` to P06; the per-request rows themselves come from P05's `usage_row()` and are never rebuilt here.

Create `R/session-budget.R`:

```r
# session-budget.R -- usage rows, the token ledger, budgets and gptr_usage() (P06, layer L3).
#
# Usage rows (contract 04 section 4.3) live in the session's `.d$usage`; a row is added to the
# session that made the request and to every ancestor, so a root's rows include its children's
# and budgets are charged to the root (IC-66). gptr_usage() aggregates live sessions and the
# process System 1 log; no usage lives in the package namespace (INFRA-15). IC-05 moved
# gptr_usage() here from P05's provider-usage.R; the zero-row table `usage_empty()` and the rows
# themselves (`usage_row()`) are P05's.

usage_columns = c("request_id", "session", "agent", "parent_id", "provider", "model", "route",
                  "input", "output", "cache_read", "cache_write_5m", "cache_write_1h", "reasoning",
                  "images", "cost", "tier", "stop_reason", "started", "seconds", "estimated",
                  "multiplier")
usage_token_columns = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h",
                        "reasoning", "images", "cost")

#' Conform usage rows (from P05's usage_row()) to the section 4.3 columns, types and order;
#' missing token and cost columns are 0, other missing columns NA (P05's usage_empty() gives the
#' column types)
#' @noRd
usage_conform = function(row) {
  row = as.data.frame(row, stringsAsFactors = FALSE)
  empty = usage_empty()
  for (col in setdiff(usage_columns, names(row))) {
    row[[col]] = if (col %in% usage_token_columns) rep(0, nrow(row)) else
      rep(empty[[col]][NA_integer_], nrow(row))
  }
  row = row[, usage_columns, drop = FALSE]
  for (col in c(usage_token_columns, "seconds", "multiplier")) row[[col]] = as.numeric(row[[col]])
  row$estimated = as.logical(row$estimated)
  if (!inherits(row$started, "POSIXct")) row$started = .POSIXct(as.numeric(row$started), tz = "UTC")
  rownames(row) = NULL
  row
}

#' Totals of usage rows: requests, input, output, cache reads, cache writes and cost
#' @noRd
usage_totals = function(u) {
  c(requests = nrow(u), input = sum(u$input), output = sum(u$output),
    cache_read = sum(u$cache_read), cache_write = sum(u$cache_write_5m + u$cache_write_1h),
    cost = sum(u$cost))
}

#' An empty token ledger: one row per request and context component (04 section 4.3)
#' @noRd
ledger_empty = function() {
  data.frame(request_id = character(), component = character(), tokens = numeric(),
             cached = logical(), stringsAsFactors = FALSE)
}

#' A short token count: 950, 1.2k, 3.4M
#' @noRd
format_count = function(n) {
  n = sum(n)
  if (n < 1000) return(as.character(round(n)))
  if (n < 1e6) return(sprintf("%.1fk", n / 1000))
  sprintf("%.1fM", n / 1e6)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-budget$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 17 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/session-budget.R tests/testthat/test-session-budget.R
git commit -m "feat(session): add usage frames and the token ledger frame"
```

---

### Task 3: Session shell, transcript, live registry, locks and the store writer

**Files:**

- Create: `R/session-object.R`
- Create: `R/session-live.R`
- Create: `R/session-store.R`
- Create: `tests/testthat/fixtures/oracles/report02/store.json`
- Test: `tests/testthat/test-session-object.R`
- Test: `tests/testthat/test-session-live.R`
- Test: `tests/testthat/test-session-store.R`

**Interfaces:**

Consumes:

- P01: `id_new(prefix = "", n = 10L)`, `id_entry(taken = NULL)`, `as_utf8(x)`, `json_encode(x, pretty = FALSE)`, `json_obj()`, `msg_to_json(msg)`, `msg_text(msg)`, `msg_user()`, `msg_assistant()`, `ev_new(type, ...)`, `write_atomic(path, content)`, `ws_path(..., create_parent = TRUE)`, `path_norm(path)`, `setting_get(key, session = NULL, default = NULL)`, `on_load(expr)`, `on_unload(fun)`, `gptr_abort()`, `gptr_inform()`, the checkers of 04 §1.1.
- P02: `ctx_new(session, run = NULL)`, `ev_dispatch(event, payload, session = NULL, ctx = NULL)`, `registry_get(kind, name, session = NULL)`.
- P03: `redact_tree(x, profile = "persist", structural = FALSE)`, `secret_discover_env(env = Sys.getenv())`, `secret_live_entries_set(fun)` (P03's callback slot for the IC-70 late-registration scan, its ambiguity A1: a zero-argument function returning session id -> list of entries); in tests `secret_register(value, name, source = "user", active = TRUE, origin = NULL)` and `vault_reset()`.
- P04: `pid_alive(pid, create_time = NULL)`.
- P05: `model_resolve(ref, strict = TRUE)`, `usage_empty()`; Task 2: `ledger_empty()`.

Produces:

- `session_new(model, mode, home = NULL, kind = "chat", parent = NULL, preset = NULL, opts = list())` -> a new idle `gptr_session` (opts: `id`, `name`, `thinking`, `max_turns`); `session_data(s)`, `session_live(s)`, `session_home(s)`, `session_by_id(id)`, `live_all()`, `live_entries_all()` (the in-memory entries of the live sessions, named by id; installed with `on_load(secret_live_entries_set(live_entries_all))` and again by `live_new()`, so that P03's `secret_register()` warns `secret_late`, IC-70), `last_set(s)`, the export `gptr_last()`.
- `session_append(s, entry)` -> the entry id, invisibly; entry constructors `entry_message(msg)`, `entry_custom(custom_type, data)`, `entry_model_change(ref, thinking = NULL, reason = "user")`; path readers `entries_path(d, leaf = d$leaf)`, `path_messages(path)`, `path_turn(path)`, `final_text(path)`; `iso_time()`, `drop_null(x)`, `model_canonical(model, strict = FALSE)`.
- Live records (04 §5.1 fields `home`, `run`, `listeners`, `store`, `ctx`, `memo`, `adapter`, `background`, `lock`, `out`, `mcp_token`, plus `ext`), `home_keep(env)`, `home_label(env)`, `live_forget(s)` (undoes the registration of a shell whose resume failed, Task 13), `session_attach(s, home = NULL)` (split-brain rules), locks `lock_path()`, `lock_acquire()`, `lock_holder()`, `lock_release()`, `lock_held_elsewhere()`.
- The store writer: `store_open(s)` -> `gptr_store`, `store_append(store, entries)`, `store_close(store)`, `store_heartbeat(store)`, `store_impl()` (the selected `store` record, else the built-in functions), `entry_to_json(e)`, `store_header(d)`; package state `the$live`, `the$last`, `the$replay_blocks`.

- [ ] **Step 1: Write the failing test**

`store.json` holds report 02's 42 store checks (the `session_store.R` prototype of §5.2, verification log applied): `id`, `source`, the original `check`, `status` (`port` or `adapted`) and the gptr assertion in `gptr`. The writer checks S01-S10, S30 and S37 are tested here; the remaining S checks follow in Tasks 7, 9, 10, 12 and 13, and Task 13 adds the test that every id has a test.

Create `tests/testthat/fixtures/oracles/report02/store.json`:

```json
[
 {"id":"S01","source":"02 5.2","check":"windows-style cwd encodes","status":"adapted","gptr":"no cwd encoding: files are <workspace root>/sessions/<YYYYmmddTHHMMSS>_<id>.jsonl"},
 {"id":"S02","source":"02 5.2","check":"set.seed stream unchanged by id generation","status":"port","gptr":".Random.seed is identical before and after 1,000 appends (INFRA-13)"},
 {"id":"S03","source":"02 5.2","check":"200 ids unique","status":"port","gptr":"200 appended entries have unique 8-hex ids"},
 {"id":"S04","source":"02 5.2","check":"uuidv7-shaped session id","status":"adapted","gptr":"session ids are s + 10 lower hex (IC-20)"},
 {"id":"S05","source":"02 5.2","check":"no file before the first user message","status":"adapted","gptr":"a new session has no file until its first entry"},
 {"id":"S06","source":"02 5.2","check":"file created once conversation exists","status":"port","gptr":"the first appended entry creates the file"},
 {"id":"S07","source":"02 5.2","check":"one line per entry + header","status":"port","gptr":"the file has one header line plus one line per entry"},
 {"id":"S08","source":"02 5.2","check":"header fields","status":"port","gptr":"the header has type session, version 3, the id, cwd and the gptr object"},
 {"id":"S09","source":"02 5.2","check":"root entry has explicit parentId null","status":"port","gptr":"the first entry's JSON has parentId: null"},
 {"id":"S10","source":"02 5.2","check":"LF line endings","status":"port","gptr":"the file contains no CR byte"},
 {"id":"S11","source":"02 5.2","check":"roles identical after reload","status":"port","gptr":"a rebuilt session has the same message roles on its path"},
 {"id":"S12","source":"02 5.2","check":"messages byte-identical after JSON round trip","status":"port","gptr":"entry lines re-encode byte-identically after store_read()"},
 {"id":"S13","source":"02 5.2","check":"model restored from path","status":"port","gptr":"a rebuilt session's model is the last model on its path"},
 {"id":"S14","source":"02 5.2","check":"unicode preserved","status":"port","gptr":"unicode text survives the file round trip"},
 {"id":"S15","source":"02 5.2","check":"branch point now has 2 children","status":"adapted","gptr":"a detached copy continued after its original is gone adds a sibling branch in the same file"},
 {"id":"S16","source":"02 5.2","check":"both branches have equal depth","status":"port","gptr":"the two branches have the same depth from the root"},
 {"id":"S17","source":"02 5.2","check":"leaf moved to the new branch","status":"port","gptr":"the copy's leaf is on the new branch"},
 {"id":"S18","source":"02 5.2","check":"branch_summary records fromId","status":"adapted","gptr":"a Pi branch_summary entry read from a file is kept raw and never rewritten"},
 {"id":"S19","source":"02 5.2","check":"branch summary becomes a user message wrapped in <summary> tags","status":"adapted","gptr":"Pi-only entries never reach the model context"},
 {"id":"S20","source":"02 5.2","check":"label resolved","status":"adapted","gptr":"Pi label entries are read without error"},
 {"id":"S21","source":"02 5.2","check":"fork wrote a new file","status":"adapted","gptr":"a fork writes its own file at its first own message"},
 {"id":"S22","source":"02 5.2","check":"fork header points at parent session","status":"port","gptr":"parentSession is the source file and gptr.forkOf names the source id, entry and turn"},
 {"id":"S23","source":"02 5.2","check":"labels carried into fork","status":"adapted","gptr":"labels are dropped (a deliberate G3 difference); the copied path keeps the source entry ids"},
 {"id":"S24","source":"02 5.2","check":"fork context == source branch context","status":"port","gptr":"the fork file replays to the source path's context (INFRA-13)"},
 {"id":"S25","source":"02 5.2","check":"threshold: tokens > window - reserve","status":"kernel","gptr":"the kernel consults compact.should at a request boundary and runs compact.run(s, 'threshold') when it answers TRUE"},
 {"id":"S26","source":"02 5.2","check":"cut lands on the 2nd user message (turn boundary)","status":"kernel","gptr":"compaction runs only at a request boundary, never between a tool call and its result"},
 {"id":"S27","source":"02 5.2","check":"7 messages of turn 1 are summarized","status":"kernel","gptr":"a compaction entry's blocks replace everything before firstKeptEntryId in the next request"},
 {"id":"S28","source":"02 5.2","check":"summary max_tokens = floor(0.8 * reserveTokens)","status":"kernel","gptr":"a compaction entry (summary, firstKeptEntryId, tokensBefore, gptr.blocks) is written to the file"},
 {"id":"S29","source":"02 5.2","check":"prompt = <conversation> + instructions","status":"kernel","gptr":"the kernel passes the reason ('threshold' or 'overflow') to compact.run"},
 {"id":"S30","source":"02 5.2","check":"tool calls serialized Pi-style","status":"kernel","gptr":"tool_call blocks are written as toolCall with an object arguments field, {} when empty"},
 {"id":"S31","source":"02 5.2","check":"tool results truncated to 2000 chars","status":"kernel","gptr":"tool result text above the tool's output budget is truncated before it enters the transcript"},
 {"id":"S32","source":"02 5.2","check":"file lists: read-only vs modified","status":"kernel","gptr":"tool result details (never sent to the model) round-trip through the store"},
 {"id":"S33","source":"02 5.2","check":"context = summary + kept tail","status":"kernel","gptr":"after a compaction the next request starts with the compaction blocks followed by the kept tail"},
 {"id":"S34","source":"02 5.2","check":"tokens after < before","status":"kernel","gptr":"the context estimate used for compact.should falls after a compaction entry"},
 {"id":"S35","source":"02 5.2","check":"nothing deleted: 11 original entries + compaction entry","status":"port","gptr":"compaction appends one entry; nothing is removed from memory or the file"},
 {"id":"S36","source":"02 5.2","check":"cannot compact twice in a row (leaf is a compaction)","status":"kernel","gptr":"at most one compaction per request boundary"},
 {"id":"S37","source":"02 5.2","check":"2nd compaction uses update prompt + previous summary","status":"kernel","gptr":"the latest compaction entry on the path wins in projection"},
 {"id":"S38","source":"02 5.2","check":"file tracking is cumulative across compactions","status":"kernel","gptr":"entries before a compaction stay readable in memory and on disk"},
 {"id":"S39","source":"02 5.2","check":"split turn detected: prefix summarized separately","status":"kernel","gptr":"an overflow in the middle of a turn compacts and continues the same turn (the prompt is not re-sent)"},
 {"id":"S40","source":"02 5.2","check":"split-turn cut is at an assistant message, never a toolResult","status":"kernel","gptr":"after overflow recovery every tool call in the request still has its result"},
 {"id":"S41","source":"02 5.2","check":"drained 2 messages in order","status":"adapted","gptr":"no file inbox in core (03 6.2): the session queue delivers a steer then a follow-up in order"},
 {"id":"S42","source":"02 5.2","check":"inbox empty after drain","status":"adapted","gptr":"the queue is empty after delivery and queue_update reports zero"}
]
```

Create `tests/testthat/test-session-object.R`:

```r
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# ---------------------------------------------------------------- the shell and the transcript

test_that("session_new() builds an idle shell whose only binding is .d", {
  home = new.env()
  s = test_session(mode = "manual", home = home)
  d = session_data(s)
  expect_s3_class(s, "gptr_session")
  expect_identical(ls(s, all.names = TRUE), ".d")
  # .d is unclassed; nothing is frozen before the first run (P07 freezes only a NULL `frozen`);
  # the out store is created lazily by P01's out_store() (it rejects a bare environment)
  expect_identical(list(attr(d, "class"), d$frozen, session_live(s)$out), list(NULL, NULL, NULL))
  expect_match(d$id, "^s[0-9a-f]{10}$")
  expect_identical(d$status, "idle")
  expect_identical(d$mode, "manual")
  expect_identical(d$kind, "chat")
  expect_identical(d$turns, 0L)
  expect_true(is.na(d$last_text))
  expect_identical(d$queue, list(steer = list(), follow_up = list()))
  expect_identical(names(d$usage), usage_columns)
  expect_identical(session_home(s), home)
  expect_identical(gptr_last(), s)
  expect_identical(session_live(s)$ctx$session, s)
})

test_that("session_new() validates its arguments with gptr_error_invalid_argument", {
  expect_error(session_new("fake/fake-1", "reckless"), class = "gptr_error_invalid_argument")
  expect_error(session_new(1, "auto"), class = "gptr_error_invalid_argument")
  expect_error(session_new("fake/fake-1", "auto", home = list()),
               class = "gptr_error_invalid_argument")
  expect_error(session_new("fake/fake-1", "auto", kind = "robot"),
               class = "gptr_error_invalid_argument")
})

test_that("an id already live in this process is split brain", {
  s = test_session()
  expect_error(test_session(opts = list(id = session_data(s)$id)), class = "gptr_error_split_brain")
})

test_that("child sessions are registered under their parent, one level deeper", {
  root = test_session()
  last = gptr_last()
  child = test_session(kind = "child", parent = root, opts = list(name = "stats"))
  cd = session_data(child)
  expect_identical(cd$parent_id, session_data(root)$id)
  expect_identical(cd$depth, 1L)
  expect_identical(session_data(root)$children$stats, child)
  expect_identical(gptr_last(), last)
})

test_that("session_append() numbers, parents and time-stamps entries and moves the leaf", {
  s = test_session()
  id1 = session_append(s, entry_message(msg_user("hello")))
  id2 = session_append(s, entry_custom("test.note", list(n = 1L)))
  d = session_data(s)
  expect_match(c(id1, id2), "^[0-9a-f]{8}$")
  expect_null(d$entries[[1L]]$parent_id)
  expect_identical(d$entries[[2L]]$parent_id, id1)
  expect_identical(d$leaf, id2)
  expect_match(d$entries[[1L]]$timestamp, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[.][0-9]{3}Z$")
  expect_identical(d$entries[[1L]]$gptr$turn, 0L)
  expect_identical(d$entries[[2L]]$custom_type, "test.note")
})

test_that("entries_path() walks leaf to root; path_messages(), path_turn(), final_text() read it", {
  s = test_session()
  d = session_data(s)
  d$turns = 1L
  session_append(s, entry_message(msg_user("q1")))
  session_append(s, entry_message(msg_assistant("a1", api = "fake", provider = "fake",
                                                model = "fake-1")))
  path = entries_path(d)
  expect_length(path, 2L)
  expect_identical(vapply(path_messages(path), function(m) m$role, ""), c("user", "assistant"))
  expect_identical(path_turn(path), 1L)
  expect_identical(final_text(path), "a1")
  call = block_tool_call("c1", "read", list(path = "a"))
  session_append(s, entry_message(msg_assistant(list(call), api = "fake", provider = "fake",
                                                model = "fake-1", stop_reason = "tool_use")))
  expect_null(final_text(entries_path(d)))
})

test_that("entry_model_change() records routers as provider router", {
  e = entry_model_change("router:cheapest", reason = "router")
  expect_identical(c(e$provider, e$model_id), c("router", "cheapest"))
  e2 = entry_model_change("anthropic/claude-sonnet-5-5", thinking = "high")
  expect_identical(c(e2$provider, e2$model_id, e2$gptr$thinking), c("anthropic",
                                                                    "claude-sonnet-5-5", "high"))
})
```

Create `tests/testthat/test-session-live.R`:

```r
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

test_that("the live registry is weak and keyed on the shell: a detached copy has no live record", {
  s = test_session()
  id = session_data(s)$id
  copy = unserialize(serialize(s, NULL))
  expect_false(is.null(session_live(s)))
  expect_null(session_live(copy))
  expect_identical(session_by_id(id), s)
  expect_true(id %in% names(live_all()))
})

test_that("a function frame is never kept as the home (R2)", {
  f = function() test_session(home = environment())
  s = f()
  expect_null(session_home(s))
  expect_match(session_data(s)$home_label, "^frame of f")
  g = test_session(home = globalenv())
  expect_identical(session_home(g), globalenv())
  expect_identical(session_data(g)$home_label, "globalenv")
})

test_that("gptr_last() holds the most recent session strongly and survives gc()", {
  s = test_session()
  id = session_data(s)$id
  rm(s)
  invisible(gc())
  expect_identical(session_data(gptr_last())$id, id)
  expect_false(is.null(session_by_id(id)))
})

test_that("an unreferenced session is finalised and its lock removed, except gptr_last()'s", {
  local_store()
  a = test_session()
  session_append(a, entry_custom("test.note", list(i = 1L)))
  lock_a = lock_path(session_data(a)$file)
  id_a = session_data(a)$id
  b = test_session()
  session_append(b, entry_custom("test.note", list(i = 2L)))
  lock_b = lock_path(session_data(b)$file)
  expect_true(dir.exists(lock_a))
  rm(a)
  invisible(gc())
  expect_false(dir.exists(lock_a))
  expect_null(session_by_id(id_a))
  rm(b)
  invisible(gc())
  expect_true(dir.exists(lock_b))
})

test_that("a same-process duplicate cannot attach: gptr_error_split_brain", {
  s = test_session()
  copy = unserialize(serialize(s, NULL))
  expect_error(session_attach(copy), class = "gptr_error_split_brain")
})

test_that("a detached copy continues from its own leaf once the original is gone", {
  local_store()
  s = test_session(home = globalenv())
  d = session_data(s)
  d$turns = 1L
  session_append(s, entry_message(msg_user("one")))
  session_append(s, entry_message(msg_assistant("first", api = "fake", provider = "fake",
                                                model = "fake-1")))
  snap = serialize(s, NULL)
  d$turns = 2L
  session_append(s, entry_message(msg_user("two")))
  file = d$file
  other = test_session()
  rm(s, d)
  invisible(gc())
  copy = unserialize(snap)
  session_attach(copy)
  session_append(copy, entry_message(msg_user("two, rephrased")))
  lines = readLines(file, encoding = "UTF-8")[-1L]
  entries = lapply(lines, json_decode)
  users = Filter(function(e) identical(e$message$role, "user"), entries)
  expect_length(users, 3L)
  expect_identical(users[[2L]]$parentId, users[[3L]]$parentId)
})

test_that("locks hold the pid and the process creation time; a dead holder is stale", {
  local_store()
  s = test_session()
  session_append(s, entry_custom("test.note", list(i = 1L)))
  file = session_data(s)$file
  h = lock_holder(lock_path(file))
  expect_identical(h$pid, Sys.getpid())
  expect_true(lock_is_mine(h))
  write_atomic(file.path(lock_path(file), "pid"), c("999999", "1"))
  expect_false(lock_held_elsewhere(file))
  expect_identical(lock_acquire(file), lock_path(file))
})

test_that("a lock held by another live process is split brain", {
  skip_on_cran()
  local_store()
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"),
                           supervise = supervise_default())
  withr::defer(p$kill())
  s = test_session()
  session_append(s, entry_custom("test.note", list(i = 1L)))
  file = session_data(s)$file
  created = as.numeric(ps::ps_create_time(ps::ps_handle(p$get_pid())))
  write_atomic(file.path(lock_path(file), "pid"),
               c(as.character(p$get_pid()), format(created, digits = 17)))
  expect_true(lock_held_elsewhere(file))
  expect_error(lock_acquire(file), class = "gptr_error_split_brain")
})

test_that("300 sessions kept in a list leave no connection open (IC-59)", {
  local_store()
  n0 = nrow(showConnections())
  keep = lapply(1:300, function(i) {
    s = test_session()
    session_append(s, entry_custom("test.note", list(i = i)))
    s
  })
  expect_length(keep, 300L)
  expect_identical(nrow(showConnections()), n0)
})

test_that("secret_register() warns secret_late for a value a live session already holds (IC-70)", {
  local_store()
  s = test_session()
  late = paste0("FAKE_late_", "kernel_secret_77")
  session_append(s, entry_message(msg_user(paste("my key is", late))))
  withr::defer(vault_reset())
  w = expect_warning(secret_register(late, "LATE_KERNEL", source = "session"),
                     class = "gptr_warning_secret_late")
  expect_identical(names(w$counts), session_data(s)$id)
})
```

Create `tests/testthat/test-session-store.R`:

```r
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)
store_recs = oracle("store")

# A stored session with one prompt turn, a tool round trip and unicode text, built by appends.
written_session = function(.env = parent.frame()) {
  local_store(.env = .env)
  s = test_session(home = globalenv())
  d = session_data(s)
  d$turns = 1L
  call = block_tool_call("c1", "read", list(path = "R/a.R"))
  session_append(s, entry_message(msg_user("Refactor a.R")))
  session_append(s, entry_message(msg_assistant(list(call), api = "fake", provider = "fake",
                                                model = "fake-1", stop_reason = "tool_use")))
  session_append(s, entry_message(msg_tool_result("c1", "read", "contents of R/a.R",
                                                  details = list(lines = 1L))))
  session_append(s, entry_message(msg_assistant("All done \u2713", api = "fake", provider = "fake",
                                                model = "fake-1")))
  s
}

# ---------------------------------------------------------------- report 02 section 5.2 (writer)

test_that(oracle_title(store_recs, "S01"), {
  s = written_session()
  d = session_data(s)
  expect_match(basename(d$file), paste0("^[0-9]{8}T[0-9]{6}_", d$id, "[.]jsonl$"))
  expect_identical(basename(dirname(d$file)), "sessions")
  expect_identical(normalizePath(dirname(dirname(d$file))),
                   normalizePath(file.path(project_root(), ".gptr")))
})

test_that(oracle_title(store_recs, "S02"), {
  local_store()
  withr::local_seed(42)
  before = get(".Random.seed", envir = globalenv())
  s = test_session()
  for (i in 1:1000) session_append(s, entry_custom("test.note", list(i = i)))
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that(oracle_title(store_recs, "S03"), {
  local_store()
  s = test_session()
  for (i in 1:200) session_append(s, entry_custom("test.note", list(i = i)))
  ids = vapply(session_data(s)$entries, function(e) e$id, "")
  expect_length(unique(ids), 200L)
  expect_true(all(grepl("^[0-9a-f]{8}$", ids)))
})

test_that(oracle_title(store_recs, "S04"), {
  expect_match(session_data(test_session())$id, "^s[0-9a-f]{10}$")
})

test_that(oracle_title(store_recs, "S05"), {
  local_store()
  s = test_session()
  expect_null(session_data(s)$file)
  expect_length(list.files(file.path(project_root(), ".gptr"), recursive = TRUE,
                           pattern = "jsonl$"), 0L)
})

test_that(oracle_title(store_recs, "S06"), {
  local_store()
  s = test_session()
  session_append(s, entry_message(msg_user("hello")))
  expect_true(file.exists(session_data(s)$file))
})

test_that(oracle_title(store_recs, "S07"), {
  s = written_session()
  lines = readLines(session_data(s)$file, encoding = "UTF-8")
  expect_length(lines, 1L + length(session_data(s)$entries))
})

test_that(oracle_title(store_recs, "S08"), {
  s = written_session()
  hdr = json_decode(readLines(session_data(s)$file, n = 1L, encoding = "UTF-8"))
  expect_identical(hdr$type, "session")
  expect_identical(hdr$version, 3L)
  expect_identical(hdr$id, session_data(s)$id)
  expect_false(is.null(hdr$cwd))
  expect_identical(hdr$gptr$api, "1.0")
  expect_identical(hdr$gptr$kind, "chat")
  expect_identical(hdr$gptr$home, "globalenv")
  expect_null(hdr$parentSession)
})

test_that(oracle_title(store_recs, "S09"), {
  s = written_session()
  line = readLines(session_data(s)$file, encoding = "UTF-8")[[2L]]
  expect_match(line, "\"parentId\":null", fixed = TRUE)
})

test_that(oracle_title(store_recs, "S10"), {
  s = written_session()
  file = session_data(s)$file
  raw = readBin(file, "raw", file.size(file))
  expect_false(any(raw == as.raw(13L)))
  expect_identical(raw[length(raw)], as.raw(10L))
})

test_that(oracle_title(store_recs, "S30"), {
  s = written_session()
  lines = readLines(session_data(s)$file, encoding = "UTF-8")
  call_line = lines[grepl("\"toolCall\"", lines, fixed = TRUE)][[1L]]
  expect_match(call_line, "\"arguments\":{\"path\":\"R/a.R\"}", fixed = TRUE)
  expect_match(call_line, "\"stopReason\":\"toolUse\"", fixed = TRUE)
  call = msg_assistant(list(block_tool_call("k", "ls", json_obj())), api = "fake",
                       provider = "fake", model = "fake-1", stop_reason = "tool_use")
  empty = entry_to_json(list(type = "message", id = "e1", parent_id = NULL, timestamp = "t",
                             message = call))
  expect_match(json_encode(empty), "\"arguments\":{}", fixed = TRUE)
})

test_that(oracle_title(store_recs, "S37"), {
  local_fake_provider(list("a"))
  s = test_session()
  u = session_append(s, entry_message(msg_user("one")))
  session_append(s, entry_message(msg_assistant("a", api = "fake", provider = "fake",
                                                model = "fake-1")))
  for (tag in c("old", "new")) {
    blocks = list(block_context("checkpoint", tag))
    session_append(s, list(type = "compaction", summary = tag, first_kept_entry_id = u,
                           tokens_before = 1, gptr = list(blocks = blocks, state = list(), n = 1L)))
  }
  d = session_data(s)
  msgs = project_messages(d$entries, d$leaf, model_resolve("fake/fake-1"))
  expect_match(msgs[[1L]]$content[[1L]]$text, "new", fixed = TRUE)
})

# ---------------------------------------------------------------- entry shapes and the writer

test_that("operator, model_change, compaction and custom entries have their JSON shapes", {
  local_store()
  s = test_session()
  relay = "The user sent this message while you were working: x"
  session_append(s, entry_message(msg_operator("steer_relay", relay, origin_text = "x")))
  session_append(s, entry_model_change("fake/fake-2", reason = "user"))
  session_append(s, list(type = "compaction", summary = "sum", first_kept_entry_id = NULL,
                         tokens_before = 10,
                         gptr = list(blocks = list(block_context("checkpoint", "sum",
                                                                 attrs = list(n = "1"))),
                                     state = list(), n = 1L)))
  session_append(s, entry_custom("gptr.mode_change", list(from = "manual", to = "auto",
                                                          source = "user")))
  x = lapply(readLines(session_data(s)$file, encoding = "UTF-8")[-1L], json_decode)
  expect_identical(x[[1L]]$type, "custom_message")
  expect_identical(x[[1L]]$customType, "gptr.operator")
  expect_identical(x[[1L]]$details$kind, "steer_relay")
  expect_identical(x[[1L]]$details$originText, "x")
  expect_identical(x[[2L]]$modelId, "fake-2")
  expect_identical(x[[2L]]$gptr$reason, "user")
  expect_identical(x[[3L]]$tokensBefore, 10L)
  expect_identical(x[[3L]]$gptr$blocks[[1L]]$gptr$context, "checkpoint")
  expect_identical(x[[4L]]$customType, "gptr.mode_change")
  expect_identical(x[[4L]]$data$to, "auto")
})

test_that("opening a file whose last byte is not LF appends LF and a gptr.recovered entry", {
  s = written_session()
  d = session_data(s)
  file = d$file
  size = file.size(file)
  cat("{\"type\":\"message\",\"id\":\"deadbeef\",\"parentId\":\"x", file = file, append = TRUE)
  live = session_live(s)
  live$store = NULL
  session_append(s, entry_custom("test.after", list(i = 1L)))
  types = vapply(d$entries, function(e) e$custom_type %||% e$type, "")
  expect_identical(types[length(types) - 1L], "gptr.recovered")
  rec = d$entries[[length(d$entries) - 1L]]$data
  expect_identical(rec$from, size)
  lines = readLines(file, encoding = "UTF-8")
  parsed = vapply(lines, function(l) !is.null(tryCatch(json_decode(l), error = function(e) NULL)),
                  NA)
  expect_identical(sum(!parsed), 1L)
  expect_identical(json_decode(lines[[length(lines)]])$customType, "test.after")
})

test_that("appends leave no connection open (IC-59)", {
  local_store()
  n0 = nrow(showConnections())
  s = test_session()
  for (i in 1:20) session_append(s, entry_custom("test.note", list(i = i)))
  expect_identical(nrow(showConnections()), n0)
})

test_that("a detached copy persists nothing until it is attached", {
  local_store()
  s = test_session()
  session_append(s, entry_message(msg_user("hello")))
  copy = unserialize(serialize(s, NULL))
  n = length(readLines(session_data(s)$file, encoding = "UTF-8"))
  session_append(copy, entry_custom("test.note", list(i = 1L)))
  expect_length(readLines(session_data(s)$file, encoding = "UTF-8"), n)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-(object|live|store)$")'`

Expected: `[ FAIL 33 | WARN 0 | SKIP 0 | PASS 0 ]`, with errors such as ``Error in `session_new(model, mode, home = home, ...)`: could not find function "session_new"``.

- [ ] **Step 3: Write the implementation**

The shell and `.d` follow the verified G3 prototype (`gptr_session.R` in dev/research/G3-session-object-pipe-steering.md) with its verification-log corrections: no user frame in a list or closure, the live index is a weak reference keyed on the shell, and the store is open-append-close (IC-59) instead of a kept connection. `session_append()` does the in-memory update and the file append inside one `suspendInterrupts()`, so an interrupt can never leave the file and `.d$entries` disagreeing. A detached copy (from `serialize()`) has no live record until `session_attach()` gives it one; until then nothing is written.

Create `R/session-object.R`:

```r
# session-object.R -- the S-8 session object (P06, layer L3).
#
# A session is a classed environment (the shell) whose only binding is `.d`, an unclassed
# environment of serialisable fields (contract 04 section 5.1). Live resources sit in the weak
# live registry of session-live.R. Adapted from the verified G3 prototype
# (dev/research/G3-session-object-pipe-steering.md, `gptr_session.R`) with the corrections of its
# verification log: no user frame is held in a list or closure, values that capture environments
# are documented, and the store is open-append-close (IC-59).

session_accessors = c("text", "value", "values", "usage", "cost", "history", "messages", "model",
                      "mode", "status", "reason", "id", "kind", "file", "turns", "envir",
                      "children", "ext", "plan", "last_rewind", "editor_text")
session_modes = c("plan", "manual", "edits", "auto")
session_kinds = c("chat", "team", "fanout", "child", "replayed")

#' Create a new idle session
#'
#' The prompt is frozen lazily at the first run (the `prompt.freeze` service) so that
#' `session_start` handlers can contribute; the egress acknowledgement is not checked here.
#' @param model chr(1): canonical `provider/id` (or `router:<name>`) of the next request.
#' @param mode One of `plan`, `manual`, `edits`, `auto`.
#' @param home The workspace environment or `NULL`; kept only when it is not a function frame (rule
#'   R2).
#' @param kind One of `chat`, `team`, `fanout`, `child`, `replayed`.
#' @param parent A parent `gptr_session` (children), or `NULL`.
#' @param preset chr(1) or `NULL` (the `preset` setting, default `"standard"`).
#' @param opts Named list: `id` (adopt a recorded id), `name` (the name under the parent's
#'   `children`), `thinking`, `max_turns`.
#' @return A new idle `gptr_session`.
#' @noRd
session_new = function(model, mode, home = NULL, kind = "chat", parent = NULL, preset = NULL,
                       opts = list()) {
  check_string(model, "model")
  mode = check_choice(mode, session_modes, "mode")
  check_env(home, "home", null = TRUE)
  kind = check_choice(kind, session_kinds, "kind")
  check_class(parent, "gptr_session", "parent", null = TRUE)
  check_string(preset, "preset", null = TRUE)
  check_list(opts, "opts")
  id = opts$id %||% id_new("s", 10L)
  if (!is.null(session_by_id(id))) {
    gptr_abort(paste0("session ", id, " is already live in this R process; use gptr_resume(\"",
                      id, "\") to get it"), "split_brain", id = id, holder_pid = Sys.getpid())
  }
  ref = model_canonical(model)
  s = new.env(parent = emptyenv())
  d = new.env(parent = emptyenv())
  assign(".d", d, envir = s)
  class(s) = "gptr_session"
  pd = if (is.null(parent)) NULL else session_data(parent)
  d$id = id
  d$kind = kind
  d$parent_id = if (is.null(pd)) NULL else pd$id
  d$fork_of = NULL
  d$depth = if (is.null(pd)) 0L else pd$depth + 1L
  d$created = as.numeric(Sys.time())
  d$status = "idle"
  d$reason = NULL
  d$model = ref$ref
  d$thinking = opts$thinking %||% ref$thinking
  d$mode = mode
  d$preset = preset %||% setting_get("preset", default = "standard")
  d$rules = list(allow = character(), ask = character(), deny = character())
  # NULL until the first run freezes the prompt: P07's prompt_freeze() freezes only when
  # `.d$frozen` is NULL, and P06 tests `length(d$frozen)`
  d$frozen = NULL
  d$entries = list()
  d$index = new.env(parent = emptyenv())
  d$leaf = NULL
  d$turns = 0L
  d$seen = character()
  d$last_text = NA_character_
  d$values = list()
  d$queue = list(steer = list(), follow_up = list())
  d$history_source = "store"
  d$dropped = list()
  d$usage = usage_empty()
  d$budget = NULL
  d$max_turns = if (is.null(opts$max_turns)) NULL else as.integer(opts$max_turns)
  d$children = list()
  d$doc = NULL
  d$file = NULL
  d$home_label = home_label(home)
  d$plan = NULL
  d$replayed = identical(kind, "replayed")
  d$block = NULL
  d$snapshot = NULL
  d$ext = list()
  d$backend = character()
  d$agent = character()
  d$exports = character()
  d$last_rewind = NULL
  d$editor_text = NULL
  # internal fields outside the section 5.1 list (see the plan's self-review): the unsignalled
  # condition of the last terminal status, the token ledger and the estimator state
  d$condition = NULL
  d$ledger = ledger_empty()
  d$estimator = NULL
  # TRUE for a foreign file rebuilt by store_rebuild() (IC-52): the next freeze passes
  # `refreeze = TRUE` to prompt.freeze so that P07 ignores the file's gptr.frozen entry
  d$refreeze = FALSE
  live_new(s, home)
  if (!is.null(pd)) {
    kids = pd$children
    kids[[opts$name %||% id]] = s
    pd$children = kids
  }
  secret_discover_env()
  if (is.null(parent)) last_set(s)
  s
}

#' Canonical model reference; lenient (an unknown model fails at the first request, not here)
#' @noRd
model_canonical = function(model, strict = FALSE) {
  if (startsWith(model, "router:")) return(list(ref = model, thinking = NULL))
  rec = if (strict) {
    model_resolve(model, strict = TRUE)
  } else {
    tryCatch(model_resolve(model, strict = FALSE), error = function(e) NULL)
  }
  if (is.null(rec)) return(list(ref = model, thinking = NULL))
  list(ref = rec$ref, thinking = rec$thinking)
}

#' The data environment of a session (read by every plan; written only through P06's verbs)
#' @noRd
session_data = function(s) get(".d", envir = s, inherits = FALSE)

#' ISO 8601 UTC time with milliseconds, locale independent (04 section 1.2)
#' @noRd
iso_time = function(t = as.numeric(Sys.time())) {
  ms = round(t * 1000)
  paste0(format(.POSIXct(ms %/% 1000, tz = "UTC"), "%Y-%m-%dT%H:%M:%S", tz = "UTC"), ".",
         sprintf("%03d", as.integer(ms %% 1000)), "Z")
}

#' Entry constructors (R shape, 04 section 4.6); id, parent and time are set by session_append()
#'
#' An operator message is a `custom_message` entry with `custom_type = "gptr.operator"`: P05's
#' `project_messages()` projects exactly those entries as operator messages (steering relays,
#' mode notes), so the field is required in memory as well as in the file.
#' @noRd
entry_message = function(msg) {
  if (identical(msg$role, "operator")) {
    return(list(type = "custom_message", custom_type = "gptr.operator", message = msg))
  }
  list(type = "message", message = msg)
}

#' A `custom` entry (`customType` + JSON-able `data`)
#' @noRd
entry_custom = function(custom_type, data) {
  list(type = "custom", custom_type = custom_type, data = data)
}

#' A `model_change` entry; router models are recorded as provider `router`
#' @noRd
entry_model_change = function(ref, thinking = NULL, reason = "user") {
  router = startsWith(ref, "router:")
  list(type = "model_change",
       provider = if (router) "router" else sub("/.*$", "", ref),
       model_id = if (router) sub("^router:", "", ref) else sub("^[^/]*/", "", ref),
       gptr = drop_null(list(ref = ref, thinking = thinking, reason = reason)))
}

#' Append an entry to the transcript and the store
#'
#' The entry is redacted with the `persist` profile at ingress, gets an 8-hex id, the current leaf
#' as parent and a timestamp, and becomes the leaf. Opening the store, the in-memory update and the
#' file append run inside `suspendInterrupts()`.
#' @param entry An entry in R shape (`entry_message()`, `entry_custom()`, ...).
#' @return The entry id, invisibly.
#' @noRd
session_append = function(s, entry) {
  d = session_data(s)
  e = NULL
  suspendInterrupts({
    store_ready(s)
    e = entry_prepare(d, entry)
    entries_push(d, e)
    store_persist(s, list(e))
  })
  invisible(e$id)
}

#' Redact, number, parent and time-stamp an entry; user messages carry their prompt turn
#' @noRd
entry_prepare = function(d, entry) {
  e = redact_tree(entry, profile = "persist")
  repeat {
    e$id = id_entry()
    if (!exists(e$id, envir = d$index, inherits = FALSE)) break
  }
  e["parent_id"] = list(d$leaf)
  e$timestamp = iso_time()
  if (identical(e$type, "message") && identical(e$message$role, "user") && is.null(e$gptr$turn)) {
    e$gptr = list(turn = d$turns)
  }
  e
}

#' Push a prepared entry into `.d$entries` and the id index; it becomes the leaf
#' @noRd
entries_push = function(d, e) {
  n = length(d$entries) + 1L
  d$entries[[n]] = e
  assign(e$id, n, envir = d$index)
  d$leaf = e$id
  invisible(n)
}

#' Entries on the path root -> leaf (`d` is a `.d` environment or a list with the same fields)
#' @noRd
entries_path = function(d, leaf = d$leaf) {
  out = list()
  id = leaf
  guard = length(d$entries) + 1L
  while (!is.null(id) && guard > 0L) {
    i = get0(id, envir = d$index, inherits = FALSE)
    if (is.null(i)) break
    e = d$entries[[i]]
    out[[length(out) + 1L]] = e
    id = e$parent_id
    guard = guard - 1L
  }
  rev(out)
}

#' Messages (R shape, unprojected) of the entries of a path
#' @noRd
path_messages = function(path) {
  keep = vapply(path, function(e) {
    e$type %in% c("message", "custom_message") && !is.null(e$message)
  }, NA)
  lapply(path[keep], function(e) e$message)
}

#' The prompt turn reached at the end of a path
#' @noRd
path_turn = function(path) {
  t = 0L
  for (e in path) {
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      t = as.integer(e$gptr$turn %||% (t + 1L))
    }
  }
  t
}

#' The last final assistant text of a path, or NULL when the path ends inside a turn
#' @noRd
final_text = function(path) {
  for (e in rev(path)) {
    if (!identical(e$type, "message")) next
    m = e$message
    if (!identical(m$role, "assistant")) next
    if ((m$stop_reason %||% "stop") %in% c("error", "aborted")) next
    calls = vapply(m$content %||% list(), function(b) identical(b$type, "tool_call"), NA)
    if (any(calls)) return(NULL)
    return(msg_text(m))
  }
  NULL
}

#' Drop NULL elements of a list (top level)
#' @noRd
drop_null = function(x) x[!vapply(x, is.null, NA)]
```

Create `R/session-live.R`:

```r
# session-live.R -- the live-session registry, homes, locks, split-brain rules and gptr_last()
# (P06, layer L3).
#
# Live resources (the kept home, the active run, the store handle, ctx, caches) are held in
# `the$live[[id]] = rlang::new_weakref(key = <shell>, value = <live>)`: an unreferenced, settled
# session is collected and its finalizer removes the entry and the file lock (G3 findings 2 and
# 10, verified). `the$last` holds the most recent session strongly (IC-71): a shell holds no frames
# or user objects, so this is copy-safe (rule R10). Locks are `<file>.lock/pid` holding the pid
# and the process creation time, checked with P04's `pid_alive()` (IC-59).

on_load({
  the$live = new.env(parent = emptyenv())
  the$last = NULL
  the$replay_blocks = new.env(parent = emptyenv())
})
on_load(on_unload(live_unload))

#' Create and register the live record of a session (04 section 5.1)
#' @noRd
live_new = function(s, home) {
  d = session_data(s)
  live = new.env(parent = emptyenv())
  live$home = if (!is.null(home) && home_keep(home)) home else NULL
  live$run = NULL
  live$listeners = list()
  live$store = NULL
  live$ctx = NULL
  live$memo = new.env(parent = emptyenv())
  live$adapter = new.env(parent = emptyenv())
  live$background = NULL
  live$lock = NULL
  # the session's gptr$out() store (IC-71): NULL until P01's out_store(live) creates it on the
  # first out_put(..., session = live); P01 accepts NULL or a gptr_out_store, never a bare env
  live$out = NULL
  live$mcp_token = NULL
  live$ext = new.env(parent = emptyenv())
  assign(d$id, rlang::new_weakref(key = s, value = live), envir = the$live)
  reg.finalizer(s, session_finalizer, onexit = TRUE)
  live$ctx = ctx_new(s)
  # the IC-70 late-registration scan reads live sessions through this callback (P03)
  secret_live_entries_set(live_entries_all)
  live
}

#' Undo the live registration of a fresh shell whose construction failed (store_rebuild() could
#' not open its store): the id is free again and the finalizer will neither release a lock nor
#' notify `session_shutdown` for it
#' @noRd
live_forget = function(s) {
  d = session_data(s)
  d$forgotten = TRUE
  w = get0(d$id, envir = the$live, inherits = FALSE)
  if (!is.null(w) && identical(rlang::wref_key(w), s)) rm(list = d$id, envir = the$live)
  invisible(NULL)
}

#' The live record of a session, or NULL for a detached copy
#' @noRd
session_live = function(s) {
  w = get0(session_data(s)$id, envir = the$live, inherits = FALSE)
  if (is.null(w)) return(NULL)
  k = rlang::wref_key(w)
  if (is.null(k) || !identical(k, s)) return(NULL)
  rlang::wref_value(w)
}

#' The kept home environment of a session, or NULL
#' @noRd
session_home = function(s) {
  live = session_live(s)
  if (is.null(live)) NULL else live$home
}

#' The live session object with this id, or NULL
#' @noRd
session_by_id = function(id) {
  if (is.null(id) || is.null(the$live)) return(NULL)
  w = get0(id, envir = the$live, inherits = FALSE)
  if (is.null(w)) return(NULL)
  rlang::wref_key(w)
}

#' Live sessions of this process, named by id
#' @noRd
live_all = function() {
  out = list()
  for (id in ls(the$live, all.names = TRUE)) {
    s = session_by_id(id)
    if (!is.null(s)) out[[id]] = s
  }
  out
}

#' The in-memory entries of the live sessions, named by id: the callback P03's secret_register()
#' scans for a newly registered value (IC-70, warning `secret_late`). P03's auth-secrets.R is L0
#' and may not read `the$live`, so the session layer installs it (03 section 2.2: callbacks
#' registered by upper layers); live_new() installs it again, so that a test that cleared P03's
#' slot cannot leave the scan inert for later sessions.
#' @noRd
live_entries_all = function() {
  lapply(live_all(), function(s) session_data(s)$entries %||% list())
}

on_load(secret_live_entries_set(live_entries_all))

#' Remember the most recently active session (a strong reference, IC-71)
#' @noRd
last_set = function(s) {
  the$last = s
  invisible(s)
}

#' The most recent session
#'
#' Returns the most recently active session of this R process. It is held strongly (it survives
#' `gc()`), so a session whose call was interrupted before its result was assigned is not lost.
#'
#' @return A `gptr_session`, or `NULL` when no session was created in this process.
#' @examples
#' s = gptr_last()
#' is.null(s) || inherits(s, "gptr_session")
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' identical(gptr_last(), s)
#' @export
gptr_last = function() the$last

#' May a session keep this environment as its home? Not a function frame on the stack (rule R2)
#' @noRd
home_keep = function(env) {
  if (identical(env, globalenv())) return(TRUE)
  k = sys.nframe()
  while (k > 0L) {
    if (identical(sys.frame(k), env)) return(FALSE)
    k = k - 1L
  }
  TRUE
}

#' A description of a home (a string, never the environment itself)
#' @noRd
home_label = function(env) {
  if (is.null(env)) return("<none>")
  if (identical(env, globalenv())) return("globalenv")
  ov = attr(env, "gptr_overlay", exact = TRUE)
  if (!is.null(ov)) return(ov)
  k = sys.nframe()
  while (k > 0L) {
    if (identical(sys.frame(k), env)) {
      fn = sys.call(k)[[1L]]
      return(paste0("frame of ", paste(deparse(fn, nlines = 1L), collapse = ""), "()"))
    }
    k = k - 1L
  }
  "<environment>"
}

#' Finalizer of a shell: drop the registry entry, release the lock, notify `session_shutdown`
#' (nothing for a shell whose registration was undone by live_forget())
#' @noRd
session_finalizer = function(s) {
  d = tryCatch(session_data(s), error = function(e) NULL)
  if (is.null(d) || isTRUE(d$forgotten)) return(invisible(NULL))
  w = get0(d$id, envir = the$live, inherits = FALSE)
  if (!is.null(w)) {
    k = rlang::wref_key(w)
    if (is.null(k) || identical(k, s)) rm(list = d$id, envir = the$live)
  }
  if (!is.null(d$file)) lock_release(lock_path(d$file))
  # dispatched with the session id (the shell is being finalised): P02's ev_dispatch() then drops
  # the session's rank-0 registry records after the handlers ran (IC-69)
  tryCatch(ev_dispatch("session_shutdown",
                       ev_new("session_shutdown", session = d$id, run = NULL, agent = "main",
                              turn = d$turns, reason = "gc"),
                       session = d$id),
           error = function(e) NULL)
  invisible(NULL)
}

#' At unload: release every live session's lock and notify `session_shutdown` (reason unload)
#' @noRd
live_unload = function() {
  for (s in live_all()) {
    d = session_data(s)
    if (!is.null(d$file)) lock_release(lock_path(d$file))
    live = session_live(s)
    tryCatch(ev_dispatch("session_shutdown",
                         ev_new("session_shutdown", session = d$id, run = NULL, agent = "main",
                                turn = d$turns, reason = "unload"),
                         session = s, ctx = live$ctx),
             error = function(e) NULL)
  }
  invisible(NULL)
}

#' Attach a detached copy (saveRDS, a knitr cache, callr) so that it can continue
#'
#' A same-process duplicate of a live original is `gptr_error_split_brain` (`busy` when the
#' original is running), after one `gc()` re-check; a copy whose file is locked by another live
#' process is `split_brain`; otherwise the copy continues from its own leaf and new entries form a
#' sibling branch in the same file (G3 finding 14).
#' @return The live record.
#' @noRd
session_attach = function(s, home = NULL) {
  live = session_live(s)
  if (!is.null(live)) return(live)
  d = session_data(s)
  other = session_by_id(d$id)
  if (!is.null(other)) {
    invisible(gc())
    other = session_by_id(d$id)
  }
  if (!is.null(other) && !identical(other, s)) {
    if (identical(session_data(other)$status, "running")) {
      gptr_abort(paste0("session ", d$id, " is running in this R process"), "busy", session = d$id)
    }
    gptr_abort(paste0("another live object for session ", d$id, " exists in this R process; use ",
                      "gptr_resume(\"", d$id, "\") to get it, or gptr_fork() to branch this copy"),
               "split_brain", id = d$id, holder_pid = Sys.getpid())
  }
  if (!is.null(d$file) && lock_held_elsewhere(d$file)) {
    h = lock_holder(lock_path(d$file))
    gptr_abort(paste0("session ", d$id, " is attached in another R process (pid ", h$pid,
                      "); use gptr_fork() to branch it"), "split_brain", id = d$id,
               holder_pid = h$pid)
  }
  if (identical(d$status, "running")) {
    d$status = "aborted"
    d$reason = "detached"
  }
  live = live_new(s, home)
  if (!is.null(d$file) && isTRUE(file.size(d$file) > 0)) {
    live$store = store_open(s)
    n_file = length(readLines(d$file, encoding = "UTF-8", warn = FALSE)) - 1L
    if (n_file > length(d$entries)) {
      gptr_inform(paste0("session ", d$id, ": continuing from this object's state (turn ",
                         d$turns, "); ", n_file - length(d$entries), " newer entries in the file ",
                         "stay as a sibling branch"), "notice")
    }
  }
  live
}

#' The lock directory of a session file
#' @noRd
lock_path = function(file) paste0(file, ".lock")

#' The creation time of this R process (seconds since the epoch). Not named proc_create_time(),
#' which is P04's `proc_create_time(pid)` in proc-supervise.R.
#' @noRd
lock_self_created = function() as.numeric(ps::ps_create_time(ps::ps_handle()))

#' Take the lock of a session file, or signal split brain when another live process holds it
#' @return The lock directory.
#' @noRd
lock_acquire = function(file) {
  dir = lock_path(file)
  if (!dir.create(dir, showWarnings = FALSE, recursive = TRUE)) {
    h = lock_holder(dir)
    if (!is.null(h) && !lock_is_mine(h) && lock_is_live(h)) {
      gptr_abort(paste0("the session file ", basename(file),
                        " is locked by another R process (pid ",
                        h$pid, ")"), "split_brain",
                 id = sub("^.*_", "", sub("[.]jsonl$", "", basename(file))), holder_pid = h$pid)
    }
  }
  write_atomic(file.path(dir, "pid"),
               c(as.character(Sys.getpid()), format(lock_self_created(), digits = 17)))
  dir
}

#' The holder of a lock: `list(pid, created, heartbeat)` or NULL
#' @noRd
lock_holder = function(dir) {
  f = file.path(dir, "pid")
  if (!file.exists(f)) return(NULL)
  x = tryCatch(readLines(f, encoding = "UTF-8", warn = FALSE), error = function(e) character())
  if (length(x) < 2L) return(NULL)
  list(pid = suppressWarnings(as.integer(x[[1L]])), created = suppressWarnings(as.numeric(x[[2L]])),
       heartbeat = as.numeric(file.mtime(f)))
}

#' Is a lock held by this process?
#' @noRd
lock_is_mine = function(h) {
  identical(h$pid, Sys.getpid()) && isTRUE(abs(h$created - lock_self_created()) < 0.01)
}

#' Is a lock's holder alive (pid and creation time) with a heartbeat younger than 24 h?
#' @noRd
lock_is_live = function(h) {
  if (is.na(h$pid)) return(FALSE)
  if (isTRUE(as.numeric(Sys.time()) - h$heartbeat > 24 * 3600)) return(FALSE)
  isTRUE(pid_alive(h$pid, .POSIXct(h$created, tz = "UTC")))
}

#' Is a session file locked by another live process?
#' @noRd
lock_held_elsewhere = function(file) {
  h = lock_holder(lock_path(file))
  !is.null(h) && !lock_is_mine(h) && lock_is_live(h)
}

#' Release a lock this process holds
#' @noRd
lock_release = function(dir) {
  h = lock_holder(dir)
  if (!is.null(h) && lock_is_mine(h)) unlink(dir, recursive = TRUE)
  invisible(TRUE)
}
```

Create `R/session-store.R`:

```r
# session-store.R -- the append-only Pi-v3 JSONL session store, resume and listing (P06, layer L3).
#
# One file per session tree: `<workspace root>/sessions/<YYYYmmddTHHMMSS>_<id>.jsonl`, a header
# line (04 section 4.7) then entries (04 section 4.6). Every append opens the file with
# `file(path, "ab")`, writes, flushes and closes it inside `suspendInterrupts()`, so no R
# connection outlives a gptr call (IC-59). Opening an existing file whose last byte is not LF
# first appends "\n" and a `gptr.recovered` entry; the reader skips unparsable lines with a
# diagnostic and re-parents the children of missing ids. Adapted from report 02 section 5.2
# (`session_store.R`) and G3's `gptr_session.R` store, converted to open-append-close and the
# entry shapes of the contract.

#' The store implementation selected by the `store` setting (default `jsonl`, IC-69)
#' @noRd
store_impl = function() {
  name = setting_get("store", default = "jsonl")
  spec = tryCatch(registry_get("store", name), error = function(e) NULL)
  if (is.null(spec)) {
    return(list(open = store_open, append = store_append))
  }
  spec
}

#' Open an existing session file before the next entry is pushed (torn-line recovery first)
#' @noRd
store_ready = function(s) {
  live = session_live(s)
  if (is.null(live) || !is.null(live$store)) return(invisible(FALSE))
  d = session_data(s)
  if (!is.null(d$file) && isTRUE(file.size(d$file) > 0)) live$store = store_impl()$open(s)
  invisible(TRUE)
}

#' Persist freshly appended entries (called by session_append())
#'
#' The file is created lazily: at the first entry of a session, or at the first own message of a
#' fork. A detached copy (no live record) persists nothing until it is attached.
#' @noRd
store_persist = function(s, entries) {
  live = session_live(s)
  if (is.null(live)) return(invisible(FALSE))
  d = session_data(s)
  impl = store_impl()
  res = tryCatch({
    if (is.null(live$store)) {
      is_msg = vapply(entries, function(e) e$type %in% c("message", "custom_message"), NA)
      if (!is.null(d$fork_of) && !any(is_msg)) return(invisible(FALSE))
      st = impl$open(s)
      live$store = st
      if (!isTRUE(st$fresh)) impl$append(st, entries)
    } else {
      impl$append(live$store, entries)
    }
    TRUE
  }, error = function(e) e)
  if (inherits(res, "gptr_error_split_brain")) stop(res)
  if (inherits(res, "error")) {
    gptr_abort(paste0("the session store failed: ", conditionMessage(res)), "internal",
               detail = conditionMessage(res))
  }
  invisible(TRUE)
}

#' Open the file of a session: create it with the header and every entry in memory, or open an
#' existing file (lock, torn-line recovery)
#' @return A `gptr_store` environment (`path`, `lock`, `fresh`); no connection is kept.
#' @noRd
store_open = function(s) {
  d = session_data(s)
  path = d$file %||% store_new_path(d)
  st = new.env(parent = emptyenv())
  class(st) = "gptr_store"
  st$path = path
  st$lock = lock_acquire(path)
  if (isTRUE(file.size(path) > 0)) {
    st$fresh = FALSE
    d$file = path
    store_recover(s, st)
  } else {
    st$fresh = TRUE
    lines = c(json_encode(store_header(d)), vapply(d$entries, entry_json_line, ""))
    store_write_lines(path, lines, append = FALSE)
    d$file = path
  }
  st
}

#' Append entries: one JSON line each (open, append, flush, close)
#' @noRd
store_append = function(store, entries) {
  if (!length(entries)) return(invisible(store))
  store_write_lines(store$path, vapply(entries, entry_json_line, ""), append = TRUE)
  invisible(store)
}

#' Release the lock of a store
#' @noRd
store_close = function(store) {
  if (!is.null(store$lock)) lock_release(store$lock)
  invisible(TRUE)
}

#' Touch the lock file (called from a reactor timer every 10 minutes while a run is live)
#' @noRd
store_heartbeat = function(store) {
  f = file.path(store$lock, "pid")
  if (file.exists(f)) Sys.setFileTime(f, Sys.time())
  invisible(TRUE)
}

#' The path of a new session file under the workspace root
#' @noRd
store_new_path = function(d) {
  stamp = format(.POSIXct(d$created, tz = "UTC"), "%Y%m%dT%H%M%S", tz = "UTC")
  ws_path("sessions", paste0(stamp, "_", d$id, ".jsonl"))
}

#' Write JSON lines as UTF-8 bytes with LF, open-append-close inside suspendInterrupts()
#' @noRd
store_write_lines = function(path, lines, append = TRUE) {
  suspendInterrupts(store_write_now(path, lines, append))
  invisible(path)
}

#' The connection-owning writer (the connection is closed by on.exit() on every path)
#' @noRd
store_write_now = function(path, lines, append) {
  con = file(path, open = if (append) "ab" else "wb")
  on.exit(close(con), add = TRUE)
  writeLines(as_utf8(lines), con, sep = "\n", useBytes = TRUE)
  flush(con)
  invisible(path)
}

#' Torn-line recovery (IC-59): a file whose last byte is not LF gets "\n" and a gptr.recovered entry
#' @noRd
store_recover = function(s, st) {
  info = file_tail_info(st$path)
  if (info$size == 0 || info$ends_lf) return(invisible(FALSE))
  d = session_data(s)
  e = entry_prepare(d, entry_custom("gptr.recovered", list(from = info$last_lf, to = info$size)))
  entries_push(d, e)
  store_write_lines(st$path, c("", entry_json_line(e)), append = TRUE)
  invisible(TRUE)
}

#' Size, last byte and last LF offset of a file (reads at most the last 1 MiB)
#' @noRd
file_tail_info = function(path) {
  size = file.size(path)
  if (is.na(size) || size == 0) return(list(size = 0, ends_lf = TRUE, last_lf = 0))
  n = min(size, 1048576)
  con = file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  seek(con, size - n)
  raw = readBin(con, "raw", n)
  lf = which(raw == as.raw(10L))
  list(size = size, ends_lf = raw[length(raw)] == as.raw(10L),
       last_lf = if (length(lf)) size - n + max(lf) else 0)
}

#' The installed gptr version (header field `gptr.version`)
#' @noRd
store_pkg_version = function() as.character(utils::packageVersion("gptr"))

#' The header line of a session file (04 section 4.7)
#' @noRd
store_header = function(d) {
  fork = d$fork_of
  g = drop_null(list(version = store_pkg_version(), api = "1.0", kind = d$kind,
                     parent = d$parent_id,
                     depth = d$depth, home = d$home_label,
                     forkOf = if (is.null(fork)) NULL else
                       drop_null(fork[c("id", "entry", "turn")])))
  drop_null(list(type = "session", version = 3L, id = d$id, timestamp = iso_time(d$created),
                 cwd = path_norm(getwd()), parentSession = fork$file, gptr = g))
}

#' One JSON line of an entry
#' @noRd
entry_json_line = function(e) json_encode(entry_to_json(e))

#' An entry in its JSON shape (04 sections 4.6 and 4.8)
#' @noRd
entry_to_json = function(e) {
  out = list(type = e$type, id = e$id)
  out["parentId"] = list(e$parent_id)
  out$timestamp = e$timestamp
  body = switch(e$type,
    message = drop_null(list(message = msg_to_json(e$message), gptr = e$gptr)),
    custom_message = if (!is.null(e$message)) operator_to_json(e$message) else e$raw,
    model_change = drop_null(list(provider = e$provider, modelId = e$model_id,
                                  gptr = drop_null(e$gptr))),
    thinking_level_change = list(thinkingLevel = e$thinking_level),
    compaction = drop_null(list(summary = e$summary, firstKeptEntryId = e$first_kept_entry_id,
                                tokensBefore = e$tokens_before, details = e$details,
                                usage = entry_usage_to_json(e$usage),
                                gptr = compaction_gptr_to_json(e$gptr))),
    custom = drop_null(list(customType = e$custom_type, data = e$data)),
    e$raw)
  c(out, body)
}

#' An operator message as a Pi `custom_message` entry body (`customType = "gptr.operator"`)
#' @noRd
operator_to_json = function(m) {
  list(customType = "gptr.operator",
       content = lapply(m$content, function(b) list(type = "text", text = b$text)),
       display = FALSE,
       details = drop_null(list(kind = m$kind, toolAdd = m$tool_add, originText = m$origin_text)))
}

#' A usage record in its JSON shape (through P01's message mapping; not named usage_to_json(),
#' which is P01's own helper inside msg_to_json())
#' @noRd
entry_usage_to_json = function(u) {
  if (is.null(u)) return(NULL)
  msg_to_json(msg_assistant(list(), api = "x", provider = "x", model = "x", usage = u))$usage
}

#' Content blocks in their JSON shape (through P01's message mapping)
#' @noRd
blocks_to_json = function(blocks) msg_to_json(msg_user(blocks))$content

#' The `gptr` object of a compaction entry with its context blocks in JSON shape
#' @noRd
compaction_gptr_to_json = function(g) {
  if (is.null(g)) return(NULL)
  if (!is.null(g$blocks)) g$blocks = blocks_to_json(g$blocks)
  g
}

#' The sections data frame of a frozen prompt (`name`, `tier`, `hash`, `tokens`)
#' @noRd
frozen_sections_df = function(x) {
  if (!length(x)) {
    return(data.frame(name = character(), tier = character(), hash = character(),
                      tokens = numeric(), stringsAsFactors = FALSE))
  }
  data.frame(name = vapply(x, function(r) r$name %||% "", ""),
             tier = vapply(x, function(r) r$tier %||% "", ""),
             hash = vapply(x, function(r) r$hash %||% "", ""),
             tokens = vapply(x, function(r) as.numeric(r$tokens %||% NA_real_), 1),
             stringsAsFactors = FALSE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-(object|live|store)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 106 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/session-object.R R/session-live.R R/session-store.R tests/testthat/fixtures/oracles/report02/store.json tests/testthat/test-session-object.R tests/testthat/test-session-live.R tests/testthat/test-session-store.R
git commit -m "feat(session): add the session shell, live registry, locks and the JSONL writer"
```

---

### Task 4: Accessors, printing, the value policy and usage roll-up

**Files:**

- Modify: `R/session-object.R`
- Modify: `R/session-budget.R`
- Create: `tests/testthat/_snaps/session-object.md`
- Test: `tests/testthat/test-session-object.R`
- Test: `tests/testthat/test-session-budget.R`

**Interfaces:**

Consumes:

- P01: `new_listing(df, class, footer = NULL)`, `msg_verbatim(x, stream = c("stdout", "stderr"))`, `est_tokens(x, class = "prose")`, `gptr_opt(name)`; rlang `obj_address()`, `duplicate()`; cli `col_grey()`, `is_utf8_output()`.
- Task 2: `usage_conform()`, `usage_totals()`, `format_count()`; Task 3: `session_data()`, `session_home()`, `session_append()`, `entries_path()`, `path_messages()`, `entry_custom()`, `session_by_id()`.

Produces:

- S3 methods of 04 §5.1: `$.gptr_session`, `[[.gptr_session` (integer index into `children`), `$<-`/`[[<-` refusing with `gptr_error_readonly` (`object`, `field`), `names.gptr_session`, `.DollarNames.gptr_session`, `print.gptr_session` (answer, then the dim footer `status . model . turns . tokens . cost . id`; `invisible(x)`), `format.gptr_session`, `as.character.gptr_session`, `summary.gptr_session` -> `gptr_session_summary`, `print.gptr_session_summary`, `str.gptr_session`; unknown members signal `gptr_error_unknown_member` (`name`, `available`).
- The value policy: `session_value_set(s, label, value, name = NULL, forced_home = NULL)` (copy below `gptr.value_copy_max`, name + address above, box otherwise; `gptr.value` entry without the value; held copies trimmed to `gptr.values_max_bytes`), `session_value_get(s, turn = NULL)` (a `value_rebound` message when a name was re-bound), `binding_env(name, env)`.
- Usage: `usage_add(s, row)` (the session and every live ancestor), `session_usage_rows(s)` -> `gptr_usage` listing of this session and its children, `ledger_add(s, request_id, components)`, `ledger_mark_cached(s, request_id, cache_read)`.

- [ ] **Step 1: Write the failing test**

The snapshot file is the expected output of the two `expect_snapshot()` calls; create it exactly as shown (testthat compares against it instead of recording a new one). The footer uses `" . "` because `local_reproducible_output()` turns UTF-8 output off. The printed lines are recorded under `Message`, not `Output`: `print()` and `str()` write through P01's `msg_verbatim()`, i.e. `cli::cli_verbatim()`, which emits a cli message condition outside an interactive console (verified with testthat 3.3.2 and cli 3.6.6: a `cli::cli_verbatim()` call inside `expect_snapshot()` is recorded as `Message`, and `utils::capture.output()` captures nothing).

Append to `tests/testthat/test-session-object.R`:

```r
# ---------------------------------------------------------------- accessors and printing

# A one-turn session built by appends, with one usage row (no run needed).
answered_session = function(text = "The data has 32 rows.") {
  s = test_session()
  d = session_data(s)
  d$turns = 1L
  session_append(s, entry_message(msg_user("How many rows?")))
  session_append(s, entry_message(msg_assistant(text, api = "fake", provider = "fake",
                                                model = "fake-1")))
  d$last_text = text
  usage_add(s, usage_conform(data.frame(request_id = "q000000000001", session = d$id,
                                        agent = "main",
                                        provider = "fake", model = "fake-1", route = "api",
                                        input = 1200, output = 34, cost = 0.0123,
                                        stringsAsFactors = FALSE)))
  s
}

test_that("accessors read .d; names() and .DollarNames() list them; unknown members are classed", {
  s = answered_session()
  expect_identical(s$text, "The data has 32 rows.")
  expect_identical(s$status, "idle")
  expect_identical(s$turns, 1L)
  expect_identical(s[["model"]], "fake/fake-1")
  expect_identical(vapply(s$messages, function(m) m$role, ""), c("user", "assistant"))
  expect_equal(s$cost, 0.0123)
  expect_s3_class(s$usage, "gptr_usage")
  expect_identical(s$history$role, c("user", "assistant"))
  expect_true(all(c("text", "value", "usage", "history", "envir") %in% names(s)))
  expect_identical(.DollarNames(s, "^us"), "usage")
  err = expect_error(s$nope, class = "gptr_error_unknown_member")
  expect_true("text" %in% err$available)
})

test_that("$<- and [[<- are refused (gptr_error_readonly)", {
  s = test_session()
  expect_error({
    s$status = "x"
  }, class = "gptr_error_readonly")
  expect_error({
    s[["status"]] = "x"
  }, class = "gptr_error_readonly")
  expect_identical(s$status, "idle")
})

test_that("children are reachable by name and by index; team text joins the reports", {
  team = test_session(kind = "team")
  a = test_session(kind = "child", parent = team, opts = list(name = "stats"))
  ad = session_data(a)
  ad$last_text = "p < 0.05"
  expect_identical(team$stats, a)
  expect_identical(team[[1L]], a)
  expect_true("stats" %in% names(team))
  expect_identical(team$text, "### stats (fake/fake-1)\np < 0.05")
})

test_that("print(), str(), format() and summary() read only .d", {
  s = answered_session()
  testthat::local_reproducible_output(width = 80)
  hide = function(x) gsub("s[0-9a-f]{10}", "s<id>", x)
  expect_snapshot(print(s), transform = hide)
  expect_snapshot(str(s), transform = hide)
  expect_identical(format(s), "The data has 32 rows.")
  expect_identical(as.character(s), "The data has 32 rows.")
  sm = summary(s)
  expect_s3_class(sm, "gptr_session_summary")
  expect_identical(sm$role, c("user", "assistant"))
  suppressMessages(utils::capture.output({
    vis = withVisible(print(s))
  }))
  expect_false(vis$visible)
  expect_identical(vis$value, s)
})

# ---------------------------------------------------------------- the value policy (03 section 5.1)

test_that("a small bound value is copied, a large one held by name, an anonymous one boxed", {
  home = new.env()
  home$small = 1:10
  home$big = as.numeric(1:3e5)
  s = test_session(home = home)
  session_value_set(s, "small", home$small, name = "small")
  session_value_set(s, "big", home$big, name = "big")
  session_value_set(s, "lm(...)", list(a = 1))
  vals = session_data(s)$values
  expect_identical(vapply(vals, function(v) v$mode, ""), c("copy", "name", "box"))
  expect_null(vals[[2L]]$value)
  expect_identical(s$values$mode, c("copy", "name", "box"))
  entries = Filter(function(e) identical(e$custom_type, "gptr.value"), session_data(s)$entries)
  expect_length(entries, 3L)
  expect_null(entries[[2L]]$data$value)
  expect_identical(entries[[2L]]$data$address, rlang::obj_address(home$big))
  expect_null(entries[[1L]]$data$address)
})

test_that("$value is the latest designated value; names are live views with a rebound notice", {
  home = new.env()
  home$big = as.numeric(1:3e5)
  s = test_session(home = home)
  session_value_set(s, "big", home$big, name = "big")
  expect_identical(s$value, home$big)
  home$big = "replaced"
  withr::local_options(gptr.quiet = FALSE)
  expect_message({
    v = s$value
  }, class = "gptr_message_value_rebound")
  expect_identical(v, "replaced")
})

test_that("a value bound in a function frame that is not kept is boxed", {
  s = test_session(home = new.env())
  f = function() {
    fit = list(coef = 1)
    session_value_set(s, "fit", fit, name = "fit", forced_home = environment())
  }
  f()
  expect_identical(session_data(s)$values[[1L]]$mode, "box")
  expect_identical(s$value, list(coef = 1))
})

test_that("held copies and boxes are trimmed to gptr.values_max_bytes, the latest kept", {
  local_gptr_options(values_max_bytes = 5000)
  s = test_session()
  for (i in 1:5) session_value_set(s, paste0("v", i), rep(as.numeric(i), 500))
  held = vapply(session_data(s)$values, function(v) !is.null(v$value), NA)
  expect_true(held[[5L]])
  expect_false(held[[1L]])
  expect_identical(s$value, rep(5, 500))
})

test_that("session_value_get(turn =) returns the value of that turn or NULL", {
  s = test_session()
  d = session_data(s)
  session_value_set(s, "a", "first")
  d$turns = 1L
  session_value_set(s, "b", "second")
  expect_identical(session_value_get(s, turn = 0L), "first")
  expect_identical(session_value_get(s), "second")
  expect_null(session_value_get(s, turn = 7L))
})
```

Create `tests/testthat/_snaps/session-object.md`:

```md
# print(), str(), format() and summary() read only .d

    Code
      print(s)
    Message
      The data has 32 rows.
      idle . fake/fake-1 . 1 turn . 1.2k tokens . $0.0123 . s<id>

---

    Code
      str(s)
    Message
      <gptr_session s<id> | chat | idle | 1 turns | fake/fake-1>
```

Append to `tests/testthat/test-session-budget.R`:

```r

test_that("usage rows roll up to every ancestor and are deduplicated per request", {
  root = test_session()
  child = test_session(kind = "child", parent = root)
  usage_add(child, usage_fixture(session_data(child)$id, "q000000000001", cost = 0.5))
  expect_named(child$usage, usage_columns)
  expect_identical(nrow(root$usage), 1L)
  expect_identical(root$usage$session, session_data(child)$id)
  expect_equal(root$cost, 0.5)
  expect_equal(attr(root$usage, "totals")[["cost"]], 0.5)
  usage_add(child, usage_fixture(session_data(child)$id, "q000000000001", cost = 0.5))
  expect_identical(nrow(root$usage), 1L)
})

test_that("ledger_add() records components and ledger_mark_cached() marks the cached prefix", {
  s = test_session()
  ledger_add(s, "q1", list(t0 = 600, tools = 400, transcript = 300))
  ledger_mark_cached(s, "q1", cache_read = 1000)
  led = session_data(s)$ledger
  expect_identical(led$component, c("t0", "tools", "transcript"))
  expect_identical(led$cached, c(TRUE, TRUE, FALSE))
  expect_null(ledger_add(s, "q2", list()))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-(object|budget)$")'`

Expected: `[ FAIL 14 | WARN 0 | SKIP 0 | PASS 54 ]`, with errors such as ``Error in `usage_add(child, usage_fixture(session_data(child)$id, "q000000000001", cost = 0.5))`: could not find function "usage_add"``.

- [ ] **Step 3: Write the implementation**

`print()`, `format()`, `str()` and `summary()` read only `.d` (copy-safe, rules R1/R4). A name-held value is resolved with `get0()` through the fork overlays down to `globalenv()`, never kept.

Append to `R/session-object.R`:

```r
# ---------------------------------------------------------------------------- accessors

#' Session accessors
#'
#' `$` and `[[` read a session: `text`, `value`, `values`, `usage`, `cost`, `history`,
#' `messages`, `model`, `mode`, `status`, `reason`, `id`, `kind`, `file`, `turns`, `envir`,
#' `children`, `ext`, `plan`, `last_rewind`, `editor_text`, and the names of child sessions.
#' Sessions are changed only through `gptr()` and the `gptr_*()` verbs, so `$<-` and `[[<-`
#' signal `gptr_error_readonly`.
#'
#' @param x A `gptr_session`.
#' @param name,i A member name; `[[` also takes an integer index into `children`.
#' @param value Refused.
#' @param ... Unused.
#' @param pattern A regular expression for `.DollarNames()`.
#' @return The member's value; `names()` and `.DollarNames()` return the member names.
#' @name session-accessors
#' @keywords internal
NULL

#' @rdname session-accessors
#' @export
`$.gptr_session` = function(x, name) session_get(x, name)

#' @rdname session-accessors
#' @export
`[[.gptr_session` = function(x, i, ...) {
  if (is.numeric(i)) return(session_data(x)$children[[i]])
  session_get(x, i)
}

#' @rdname session-accessors
#' @export
`$<-.gptr_session` = function(x, name, value) session_readonly(name)

#' @rdname session-accessors
#' @export
`[[<-.gptr_session` = function(x, i, value) session_readonly(i)

#' @rdname session-accessors
#' @export
names.gptr_session = function(x) c(session_accessors, names(session_data(x)$children))

#' @rdname session-accessors
#' @exportS3Method utils::.DollarNames
.DollarNames.gptr_session = function(x, pattern = "") {
  n = names.gptr_session(x)
  n[grepl(pattern, n)]
}

#' Refuse an assignment to a session member
#' @noRd
session_readonly = function(field) {
  field = paste(as.character(field), collapse = "")
  gptr_abort(paste0("sessions are read-only: `", field, "` cannot be assigned; change a session ",
                    "only through gptr() and the gptr_*() verbs"),
             "readonly", object = "gptr_session", field = field)
}

#' The value of one accessor (04 section 5.1)
#' @noRd
session_get = function(s, name) {
  d = session_data(s)
  switch(name,
    text = session_text(s),
    value = session_value_get(s),
    values = session_values_df(s),
    usage = session_usage_rows(s),
    cost = sum(session_usage_rows(s)$cost),
    history = session_history(s),
    messages = path_messages(entries_path(d)),
    model = d$model,
    mode = d$mode,
    status = d$status,
    reason = d$reason,
    id = d$id,
    kind = d$kind,
    file = d$file,
    turns = d$turns,
    envir = session_home(s),
    children = d$children,
    ext = d$ext,
    plan = d$plan,
    last_rewind = d$last_rewind,
    editor_text = d$editor_text,
    {
      child = if (length(d$children)) d$children[[name, exact = TRUE]] else NULL
      if (!is.null(child)) return(child)
      avail = c(session_accessors, names(d$children))
      gptr_abort(paste0("`", name, "` is not a member of a gptr session; available: ",
                        paste(avail, collapse = ", ")),
                 "unknown_member", name = name, available = avail)
    })
}

#' `$text`: the last final answer; team sessions join their reports; fan-outs give a named chr
#' @noRd
session_text = function(s) {
  d = session_data(s)
  if (identical(d$kind, "team") && length(d$children)) {
    parts = vapply(names(d$children), function(nm) {
      cd = session_data(d$children[[nm]])
      paste0("### ", nm, " (", cd$model, ")\n", if (is.na(cd$last_text)) "" else cd$last_text)
    }, "")
    return(paste(parts, collapse = "\n\n"))
  }
  if (identical(d$kind, "fanout") && length(d$children)) {
    return(vapply(d$children, function(ch) session_data(ch)$last_text, ""))
  }
  d$last_text
}

#' `$history`: one row per message on the active path
#' @noRd
session_history = function(s) {
  d = session_data(s)
  path = Filter(function(e) e$type %in% c("message", "custom_message") && !is.null(e$message),
                entries_path(d))
  turn = 0L
  rows = vector("list", length(path))
  for (i in seq_along(path)) {
    e = path[[i]]
    m = e$message
    if (identical(m$role, "user")) turn = as.integer(e$gptr$turn %||% (turn + 1L))
    calls = Filter(function(b) identical(b$type, "tool_call"), m$content %||% list())
    tools = if (identical(m$role, "tool_result")) m$tool_name else
      paste(vapply(calls, function(b) b$name, ""), collapse = ",")
    text = msg_text(m)
    tokens = if (identical(m$role, "assistant") && !is.null(m$usage$total)) m$usage$total else
      est_tokens(text, "prose")
    rows[[i]] = data.frame(turn = turn, role = m$role, preview = substr(text, 1L, 60L),
                           tools = tools, tokens = as.numeric(tokens), stringsAsFactors = FALSE)
  }
  if (!length(rows)) {
    return(data.frame(turn = integer(), role = character(), preview = character(),
                      tools = character(), tokens = numeric(), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

# ---------------------------------------------------------------------------- printing

#' Print a session: the last answer, then a dim footer
#'
#' @param x A `gptr_session`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
print.gptr_session = function(x, ...) {
  txt = session_text(x)
  txt = txt[!is.na(txt) & nzchar(txt)]
  if (length(txt)) msg_verbatim(txt)
  msg_verbatim(cli::col_grey(session_footer(x)))
  invisible(x)
}

#' The footer line: status . model . turns . tokens . cost . id
#' @noRd
session_footer = function(s) {
  d = session_data(s)
  u = session_usage_rows(s)
  tokens = sum(u$input + u$output + u$cache_read + u$cache_write_5m + u$cache_write_1h)
  dot = if (cli::is_utf8_output()) " \u00b7 " else " . "
  paste(c(d$status, d$model, paste(d$turns, if (identical(d$turns, 1L)) "turn" else "turns"),
          paste(format_count(tokens), "tokens"), sprintf("$%.4f", sum(u$cost)), d$id),
        collapse = dot)
}

#' Format a session as its text
#'
#' @param x A `gptr_session`.
#' @param ... Unused.
#' @return `x$text`.
#' @export
format.gptr_session = function(x, ...) session_text(x)

#' @rdname format.gptr_session
#' @export
as.character.gptr_session = function(x, ...) session_text(x)

#' Summarise a session as its history
#'
#' @param object A `gptr_session`.
#' @param ... Unused.
#' @return A `gptr_session_summary` data frame (`turn`, `role`, `preview`, `tools`, `tokens`).
#' @export
summary.gptr_session = function(object, ...) {
  structure(session_history(object), class = c("gptr_session_summary", "data.frame"))
}

#' Print a session summary
#'
#' @param x A `gptr_session_summary`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
print.gptr_session_summary = function(x, ...) {
  df = x
  class(df) = "data.frame"
  msg_verbatim(utils::capture.output(print(df, row.names = FALSE)))
  invisible(x)
}

#' Show the structure of a session in one line (never touches user objects)
#'
#' @param object A `gptr_session`.
#' @param ... Unused.
#' @return `NULL`, invisibly.
#' @exportS3Method utils::str
str.gptr_session = function(object, ...) {
  d = session_data(object)
  msg_verbatim(paste0("<gptr_session ", d$id, " | ", d$kind, " | ", d$status, " | ", d$turns,
                      " turns | ", d$model, ">"))
  invisible(NULL)
}

# ---------------------------------------------------------------------------- the value policy

#' Designate a value of the session (the section 5.1 value policy of 03)
#'
#' A name bound in the kept home (or globalenv) below `gptr.value_copy_max` is deep-copied; a
#' larger one is held by name and address only (no reference); anything else is boxed. Appends a
#' `gptr.value` entry holding metadata, never the value (rule R1).
#' @param label chr(1): the expression label (the name of an anonymous value).
#' @param value The value.
#' @param name chr(1) or `NULL`: the binding name when the value is bound.
#' @param forced_home The environment where `name` is bound when it is not the kept home.
#' @return `invisible(NULL)`.
#' @noRd
session_value_set = function(s, label, value, name = NULL, forced_home = NULL) {
  check_string(label, "label")
  check_string(name, "name", null = TRUE)
  check_env(forced_home, "forced_home", null = TRUE)
  d = session_data(s)
  kept = session_home(s)
  where = forced_home %||% kept
  bound = !is.null(name) && !is.null(where) &&
    (identical(where, globalenv()) || identical(where, kept)) &&
    exists(name, envir = where, inherits = FALSE)
  facts = value_facts(value)
  mode = if (!bound) "box" else if (facts$bytes < gptr_opt("value_copy_max")) "copy" else "name"
  held = switch(mode, copy = rlang::duplicate(value, shallow = FALSE), name = NULL, box = value)
  rec = list(turn = d$turns, mode = mode, name = name %||% label,
             address = if (identical(mode, "name")) facts$address else NA_character_,
             class = facts$class, bytes = facts$bytes, value = held)
  vals = d$values
  vals[[length(vals) + 1L]] = rec
  d$values = vals
  values_trim(d)
  session_append(s, entry_custom("gptr.value",
                                 drop_null(list(turn = rec$turn, mode = mode, name = rec$name,
                                                address = if (identical(mode, "name")) rec$address,
                                                class = rec$class, bytes = rec$bytes))))
  invisible(NULL)
}

#' Facts of a value through one leaf (rule R4)
#' @noRd
value_facts = function(x) {
  list(class = class(x)[1L], bytes = as.numeric(utils::object.size(x)),
       address = rlang::obj_address(x))
}

#' Release the oldest held copies and boxes above `gptr.values_max_bytes` (the latest is kept)
#' @noRd
values_trim = function(d) {
  vals = d$values
  held = which(vapply(vals, function(v) !is.null(v$value), NA))
  budget = gptr_opt("values_max_bytes")
  while (length(held) > 1L && sum(vapply(vals[held], function(v) v$bytes, 1)) > budget) {
    vals[[held[1L]]]["value"] = list(NULL)
    vals[[held[1L]]]$released = TRUE
    held = held[-1L]
  }
  d$values = vals
  invisible(d)
}

#' The designated value: the latest by turn, or the one of `turn`; NULL when none
#' @noRd
session_value_get = function(s, turn = NULL) {
  d = session_data(s)
  if (d$kind %in% c("team", "fanout") && length(d$children)) {
    return(lapply(d$children, function(ch) session_value_get(ch)))
  }
  if (!length(d$values)) return(NULL)
  turns = vapply(d$values, function(v) as.integer(v$turn), 1L)
  if (is.null(turn)) {
    i = max(which(turns == max(turns)))
  } else {
    hit = which(turns == as.integer(turn))
    if (!length(hit)) return(NULL)
    i = max(hit)
  }
  value_resolve(s, d$values[[i]], latest = is.null(turn))
}

#' Resolve a value record: held copies and boxes directly, names through the kept home
#' @noRd
value_resolve = function(s, v, latest) {
  if (v$mode %in% c("copy", "box")) {
    if (is.null(v$value) && isTRUE(v$released)) {
      gptr_inform(paste0("the value of turn ", v$turn, " was released (gptr.values_max_bytes)"),
                  "notice")
    }
    return(v$value)
  }
  env = binding_env(v$name, session_home(s) %||% globalenv())
  if (is.null(env)) {
    gptr_inform(paste0("value `", v$name, "` (turn ", v$turn, ") is not bound in this R process"),
                "notice")
    return(NULL)
  }
  obj = get(v$name, envir = env, inherits = FALSE)
  if (!is.na(v$address) && !identical(rlang::obj_address(obj), v$address)) {
    gptr_inform(paste0("`", v$name, "` was re-bound after turn ", v$turn,
                       if (latest) "; showing the current object" else "; that object is gone"),
                "value_rebound")
    if (!latest) return(NULL)
  }
  obj
}

#' The environment binding `name`, walking fork overlays down to (and including) globalenv
#' @noRd
binding_env = function(name, env) {
  while (!is.null(env) && !identical(env, emptyenv())) {
    if (exists(name, envir = env, inherits = FALSE)) return(env)
    if (identical(env, globalenv())) return(NULL)
    env = parent.env(env)
  }
  NULL
}

#' `$values`: one row per designated value (turn, mode, name, class, bytes)
#' @noRd
session_values_df = function(s) {
  vals = session_data(s)$values
  data.frame(turn = vapply(vals, function(v) as.integer(v$turn), 1L),
             mode = vapply(vals, function(v) v$mode, ""),
             name = vapply(vals, function(v) v$name %||% NA_character_, ""),
             class = vapply(vals, function(v) v$class %||% NA_character_, ""),
             bytes = vapply(vals, function(v) as.numeric(v$bytes %||% NA_real_), 1),
             stringsAsFactors = FALSE)
}
```

Append to `R/session-budget.R`:

```r
# ---------------------------------------------------------------------------- rows and the ledger

#' Add a usage row to the session and every live ancestor (root charging, IC-66)
#' @noRd
usage_add = function(s, row) {
  row = usage_conform(row)
  cur = s
  seen = character()
  while (!is.null(cur)) {
    d = session_data(cur)
    if (d$id %in% seen) break
    seen = c(seen, d$id)
    d$usage = rbind(d$usage, row)
    cur = if (is.null(d$parent_id)) NULL else session_by_id(d$parent_id)
  }
  invisible(row)
}

#' The usage rows of a session and its children, one per request, as a `gptr_usage` listing
#' @noRd
session_usage_rows = function(s) {
  u = session_data(s)$usage
  u = u[!duplicated(u$request_id), , drop = FALSE]
  rownames(u) = NULL
  out = new_listing(u, "gptr_usage")
  attr(out, "totals") = usage_totals(u)
  out
}

#' Add the per-component token estimate of one request (the ledger of gptr_usage(detail = TRUE))
#' @param components Named list or vector: component -> estimated tokens (`t0`, `t1`, `tools`,
#'   `project`, `environment`, `workspace`, `attached`, `transcript`, `tool_results`, `images`,
#'   `other`).
#' @noRd
ledger_add = function(s, request_id, components) {
  comp = unlist(components)
  if (!length(comp)) return(invisible(NULL))
  d = session_data(s)
  rows = data.frame(request_id = request_id, component = names(comp), tokens = as.numeric(comp),
                    cached = FALSE, stringsAsFactors = FALSE)
  d$ledger = rbind(d$ledger, rows)
  invisible(rows)
}

#' Mark the leading components of a request as cached, up to the reported cache-read tokens
#' @noRd
ledger_mark_cached = function(s, request_id, cache_read) {
  d = session_data(s)
  i = which(d$ledger$request_id == request_id)
  if (!length(i) || !isTRUE(cache_read > 0)) return(invisible(NULL))
  led = d$ledger
  led$cached[i] = cumsum(led$tokens[i]) <= cache_read
  d$ledger = led
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-(object|budget)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 108 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/session-object.R R/session-budget.R tests/testthat/_snaps/session-object.md tests/testthat/test-session-object.R tests/testthat/test-session-budget.R
git commit -m "feat(session): add session accessors, printing, the value policy and usage roll-up"
```

---

### Task 5: Run records, events and budget checks

**Files:**

- Create: `R/agent-run.R`
- Modify: `R/session-budget.R`
- Test: `tests/testthat/test-agent-run.R`
- Test: `tests/testthat/test-session-budget.R`

**Interfaces:**

Consumes:

- P01: `ev_new(type, ...)`, `gptr_opt(name)`, `gptr_can_prompt()`, `gptr_has_human()`, `setting_get()`, `ext_service_has(name)`, `ext_service_get(name)`, `id_new()`; P02: `ev_dispatch()`.
- Task 3: `session_data()`, `session_live()`, `session_by_id()`; Task 4: `session_usage_rows()`.

Produces:

- `run_new(s, opts, outer)` -> an environment of class `gptr_run` with the 04 §7.6 fields `id` (`u` + 8 hex), `session`, `status` (`queued`), `turn`, `mode`, `model`, `depth`, `parent_run`, `opts` (with `opts$safety`), `signal` (environment `aborted`, `reason`), `started`, `children`, plus private fields (`shell`, `home`, `scratch`, `budget`, `transfers`, `timers`, ...).
- `safety_snapshot()` (IC-53 item 2), `run_mode_tighter(a, b)` (not `mode_tighter()`, which is P08's), `run_current()` (walks `sys.frame()` for the `.gptr_tool_run` marker), `run_eval_env(run)` (plan-mode scratch overlay, else the run's home), `run_emit(run, type, ...)`, `session_emit(s, type, ...)`, `run_ui(run)` (the `ui.get` service or `NULL`); the agent-area accessors the L2 dispatcher of Task 7 uses instead of the L3 session files (03 §2.2, P01's `test-arch-layers.R`): `run_data(run)`, `run_live(run)`, `run_ctx(run)`, `run_ctx_sid(ctx)`, `run_append_message(run, msg)`, `run_append_custom(run, type, data)`.
- Budgets (IC-66): `run_budget_limits(s, opts, outer)`, `run_budget_root(s, opts)` (the live session named by the run option `root`, 04 §7.6), `run_budget_pool(s, opts)` (the shared pool of a root without a run, kept as `budget_root` on the root's live record and in `run$budget_root`), `run_chain(run)`, `run_used(run)`, `budget_check(s, estimate = 0)` -> `NULL` or `list(kind, budget, used)`, `budget_near(run)`. A child whose `root` is another session starts with its own share only and is checked against the root's run or pool as well ("children start with `min(<their share>, <root remaining>)`"), so the children of a top-level team or fan-out share one per-call budget.

- [ ] **Step 1: Write the failing test**

`test_run()` (harness) attaches an unstarted run to a session so that gates and budgets can be tested without the engine of Task 10.

Create `tests/testthat/test-agent-run.R`:

```r
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# ---------------------------------------------------------------- run records (04 section 7.6)

test_that("run_new() builds a queued gptr_run with the contract fields", {
  home = new.env()
  s = test_session(mode = "edits", home = home)
  run = run_new(s, list(agent = "main"), NULL)
  expect_s3_class(run, "gptr_run")
  expect_match(run$id, "^u[0-9a-f]{8}$")
  expect_identical(run$session, session_data(s)$id)
  expect_identical(run$status, "queued")
  expect_identical(run$turn, 0L)
  expect_identical(run$mode, "edits")
  expect_identical(run$depth, 0L)
  expect_null(run$parent_run)
  expect_identical(run$children, character())
  expect_false(run$signal$aborted)
  expect_s3_class(run$started, "POSIXct")
  expect_identical(run$max_turns, 50L)
  expect_identical(run_eval_env(run), home)
})

test_that("the safety options are snapshotted at the start of a root run (IC-53)", {
  local_gptr_options(noninteractive_ask = "deny", unsafe_no_permissions = FALSE)
  s = test_session()
  run = run_new(s, list(), NULL)
  options(gptr.noninteractive_ask = "stop", gptr.unsafe_no_permissions = TRUE)
  expect_identical(run$opts$safety$noninteractive_ask, "deny")
  expect_false(run$opts$safety$unsafe_no_permissions)
  expect_named(run$opts$safety, c("ui", "interactive", "critical_guard", "secret_guard",
                                  "noninteractive_ask", "protect_size", "mode",
                                  "unsafe_no_permissions", "can_prompt", "has_human"))
})

test_that("a nested run tightens the mode, inherits the snapshot and links to the outer run", {
  outer_s = test_session(mode = "manual")
  outer = run_new(outer_s, list(), NULL)
  child = test_session(mode = "auto", kind = "child", parent = outer_s)
  inner = run_new(child, list(), outer)
  expect_identical(inner$mode, "manual")
  expect_identical(inner$opts$safety, outer$opts$safety)
  expect_identical(inner$parent_run, outer$id)
  expect_identical(inner$depth, 1L)
  expect_true(session_data(child)$id %in% outer$children)
  expect_identical(run_mode_tighter("auto", "plan"), "plan")
})

test_that("plan mode evaluates in a scratch overlay of the home (IC-15)", {
  home = new.env()
  s = test_session(mode = "plan", home = home)
  run = run_new(s, list(), NULL)
  env = run_eval_env(run)
  expect_false(identical(env, home))
  expect_identical(parent.env(env), home)
  expect_null(run_eval_env(NULL))
})

test_that("the gateway's evaluation environment wins over the kept home (IC-40)", {
  home = new.env()
  frame = new.env()
  s = test_session(home = home)
  call = new.env()
  call$envir = frame
  expect_identical(run_eval_env(run_new(s, list(call = call), NULL)), frame)
})

test_that("run_current() finds the innermost frame that marks a running tool", {
  s = test_session()
  run = run_new(s, list(), NULL)
  expect_null(run_current())
  inner = function() run_current()
  tool_frame = function() {
    .gptr_tool_run = run
    inner()
  }
  expect_identical(tool_frame(), run)
  expect_null(run_current())
})

test_that("run_emit() and session_emit() dispatch events with the section 4.5 fields", {
  s = test_session()
  sid = session_data(s)$id
  got = new.env()
  local_hook("turn_start", function(event, ctx) {
    got$ev = event
    got$ctx = ctx
    NULL
  }, session = sid)
  run = test_run(s, list(agent = "stats"))
  run_emit(run, "turn_start")
  expect_identical(got$ev$type, "turn_start")
  expect_identical(got$ev$session, sid)
  expect_identical(got$ev$run, run$id)
  expect_identical(got$ev$agent, "stats")
  expect_identical(got$ev$turn, 0L)
  expect_true(is.numeric(got$ev$ts))
  expect_identical(got$ctx, session_live(s)$ctx)
  session_emit(s, "turn_start")
  expect_identical(got$ev$run, run$id)
})

test_that("run_ui() is NULL without the ui.get service and the service's UI otherwise", {
  local_without_services("ui.get")
  s = test_session()
  run = run_new(s, list(), NULL)
  expect_null(run_ui(run))
  local_service("ui.get", function(session = NULL) {
    list(name = "scripted", has_ui = function() TRUE)
  })
  expect_identical(run_ui(run)$name, "scripted")
})

test_that("interactive = FALSE in the run options means nobody can answer the run's gate", {
  local_gptr_options(interactive = TRUE)
  s = test_session()
  expect_true(run_new(s, list(), NULL)$opts$safety$can_prompt)
  expect_false(run_new(s, list(interactive = FALSE), NULL)$opts$safety$can_prompt)
})
```

Append to `tests/testthat/test-session-budget.R`:

```r

test_that("the default budget is 2e6 tokens and 5 USD per top-level call; NULL disables (IC-66)", {
  s = test_session()
  lim = run_budget_limits(s, list(), NULL)
  expect_identical(lim$tokens, 2e6)
  expect_identical(lim$cost, 5)
  expect_null(lim$turns)
  lim2 = run_budget_limits(s, list(budget = list(cost = NULL, turns = 3)), NULL)
  expect_null(lim2$cost)
  expect_identical(lim2$turns, 3)
  outer = run_new(s, list(), NULL)
  expect_identical(run_budget_limits(s, list(budget = list(turns = 1)), outer), list(turns = 1))
})

test_that("budget_check() is NULL outside a run and names the kind inside one", {
  s = test_session()
  expect_null(budget_check(s))
  test_run(s, list(budget = list(turns = 1, tokens = 1000)))
  expect_null(budget_check(s))
  expect_identical(budget_check(s, estimate = 2000)$kind, "tokens")
  usage_add(s, usage_fixture(session_data(s)$id, "q-turn"))
  hit = budget_check(s)
  expect_identical(hit$kind, "turns")
  expect_identical(hit$used, 1L)
})

test_that("a child's usage is charged to its root: the root's cost budget stops the child", {
  root = test_session()
  test_run(root, list(budget = list(cost = 5)))
  child = test_session(kind = "child", parent = root)
  # the child's own limits are far above the cost, so only the root's 5 USD can stop it
  test_run(child, list(budget = list(cost = 100, tokens = 1e9)))
  expect_null(budget_check(child))
  usage_add(child, usage_fixture(session_data(child)$id, "q-costly", cost = 6))
  hit = budget_check(child)
  expect_identical(hit$kind, "cost")
  expect_equal(c(hit$budget, hit$used), c(5, 6))
})

test_that("children of a root without a run share one budget through opts$root (IC-66)", {
  team = test_session(kind = "team")
  tid = session_data(team)$id
  a = test_session(kind = "child", parent = team)
  b = test_session(kind = "child", parent = team)
  ra = test_run(a, list(root = tid, budget = list(tokens = 1000)))
  rb = test_run(b, list(root = tid, budget = list(tokens = 1000)))
  # each child keeps only its share; the container holds the one per-call budget
  expect_identical(ra$budget, list(tokens = 1000))
  expect_identical(rb$budget_root, ra$budget_root)
  expect_identical(ra$budget_root$budget$tokens, 1000)
  expect_identical(ra$budget_root$budget$cost, 5)
  usage_add(a, usage_fixture(session_data(a)$id, "q-a", input = 590))
  expect_null(budget_check(a))
  expect_null(budget_check(b))
  usage_add(b, usage_fixture(session_data(b)$id, "q-b", input = 590))
  hit = budget_check(b)
  expect_identical(hit$kind, "tokens")
  expect_equal(c(hit$budget, hit$used), c(1000, 1200))
  expect_identical(budget_check(a)$kind, "tokens")
  # a root that runs is charged through its own run; no pool is made
  top = test_session()
  top_run = test_run(top, list(budget = list(cost = 5)))
  other = test_session()
  ro = test_run(other, list(root = session_data(top)$id))
  expect_null(ro$budget_root)
  expect_identical(ro$budget, list())
  expect_true(top_run$id %in% vapply(run_chain(ro), function(r) r$id, ""))
})

test_that("budget_near is emitted once per kind at 80%", {
  s = test_session()
  ev = local_events("budget_near")
  run = test_run(s, list(budget = list(cost = 1)))
  usage_add(s, usage_fixture(session_data(s)$id, "q1", cost = 0.85))
  budget_near(run)
  budget_near(run)
  near = ev(s)
  expect_length(near, 1L)
  expect_identical(near[[1L]]$kind, "cost")
  expect_equal(near[[1L]]$used, 0.85)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(agent-run|session-budget)$")'`

Expected: `[ FAIL 14 | WARN 0 | SKIP 0 | PASS 26 ]`, with errors such as ``Error in `run_new(s, list(agent = "main"), NULL)`: could not find function "run_new"``.

- [ ] **Step 3: Write the implementation**

No run state lives in the package namespace (INFRA-15): `run_current()` finds the innermost executing tool by walking `sys.frame(k)` (never `sys.frames()`, rule R3) for the binding `.gptr_tool_run` that the dispatcher's execution frame holds.

Create `R/agent-run.R`:

```r
# agent-run.R -- the run lifecycle on the reactor (P06, layer L3).
#
# A run drives the pure loop of agent-loop.R from reactor callbacks: `run_start()` registers the run
# and one reactor task that asks the loop for its next action; requests go out through P05's
# `provider_stream()` with the run's emit/done callbacks; tool batches run in the reactor's tool
# FIFO (sequential tools) or directly (concurrent batches); steering is delivered after complete
# tool results. Recovery follows report 02 sections 2.8-2.9 and 5.3 (`run_with_recovery()`) with
# gptr's constants (C-33: at most 2 agent-level retries, 2 s then 4 s; one compact-and-retry on
# overflow). The interrupt policy is the `console.interrupt_policy` service (P14) when registered,
# else abort-only (report 02 section 4.8; G3 finding 5). No run state lives in the package
# namespace (INFRA-15): the reactor holds active runs until they settle.

#' A new run record (04 section 7.6 fields plus private fields)
#'
#' The safety options are snapshotted here for a root run and inherited by nested runs (IC-53);
#' a nested run's mode is the stricter of the outer run's and the session's. The evaluation
#' environment is the gateway's choice (`opts$call$envir`, IC-40) or the kept home; it is held only
#' in the `home` binding, which is reset to NULL at settlement (rule R2).
#' @return An environment of class `gptr_run`.
#' @noRd
run_new = function(s, opts, outer) {
  d = session_data(s)
  live = session_live(s)
  run = new.env(parent = emptyenv())
  class(run) = "gptr_run"
  run$id = id_new("u", 8L)
  run$session = d$id
  run$shell = s
  run$status = "queued"
  run$turn = 0L
  run$opts = opts
  run$opts$safety = opts$safety %||% (if (is.null(outer)) safety_snapshot() else outer$opts$safety)
  # the run option `interactive = FALSE` (04 section 7.6: "a human can answer") means nobody can
  # answer this run's gate (background runs, children without a human): asks stop or deny
  if (isFALSE(opts$interactive)) run$opts$safety$can_prompt = FALSE
  run$mode = if (is.null(outer)) d$mode else run_mode_tighter(outer$mode, d$mode)
  run$model = NULL
  run$depth = as.integer(opts$depth %||% d$depth)
  run$parent_run = opts$parent_run %||% (if (is.null(outer)) NULL else outer$id)
  run$signal = new.env(parent = emptyenv())
  run$signal$aborted = FALSE
  run$signal$reason = NULL
  # IC-53 item 3: the one-shot approval tokens (names of control exports approved through an
  # ask_human for the executing call), the slot P08's control_check() consumes; and the stored,
  # unsignalled condition of the terminal status that P08's gateway_signal() reads
  run$signal$control = character()
  run$signal$condition = NULL
  run$started = Sys.time()
  run$children = character()
  run$outer = outer
  run$max_turns = as.integer(opts$max_turns %||% d$max_turns %||% gptr_opt("max_turns"))
  run$budget = run_budget_limits(s, opts, outer)
  # the shared pool of a root without a run (opts$root names a team or fan-out container, IC-66)
  run$budget_root = if (is.null(outer)) run_budget_pool(s, opts) else NULL
  run$usage_start = nrow(d$usage)
  run$near = character()
  run$home = opts$call$envir %||% live$home
  plan = identical(run$mode, "plan") && !is.null(run$home)
  run$scratch = if (plan) new.env(parent = run$home) else NULL
  run$busy = FALSE
  run$settled = FALSE
  run$requested = FALSE
  run$counted_turn = FALSE
  run$attempt = 0L
  run$overflow_used = FALSE
  run$transfers = character()
  run$timers = character()
  run$fifo = character()
  run$request_ids = character()
  run$nested = list()
  run$nested_count = list()
  run$pending_operator = list()
  run$pending_model = NULL
  run$pending_compact = NULL
  run$blocked = NULL
  run$condition = NULL
  run$message = NULL
  run$tool_call = NULL
  run$abort_after_call = FALSE
  if (!is.null(outer)) outer$children = unique(c(outer$children, d$id))
  run
}

#' The safety options of a run, snapshotted at its start (IC-53 item 2)
#' @noRd
safety_snapshot = function() {
  list(ui = getOption("gptr.ui"), interactive = getOption("gptr.interactive"),
       critical_guard = gptr_opt("critical_guard"), secret_guard = gptr_opt("secret_guard"),
       noninteractive_ask = gptr_opt("noninteractive_ask"), protect_size = gptr_opt("protect_size"),
       mode = getOption("gptr.mode"),
       unsafe_no_permissions = isTRUE(gptr_opt("unsafe_no_permissions")),
       can_prompt = gptr_can_prompt(), has_human = gptr_has_human())
}

#' The stricter of two modes (plan < manual < edits < auto)
#' @noRd
run_mode_tighter = function(a, b) session_modes[min(match(c(a, b), session_modes))]

#' The innermost run whose tool is executing on this call stack, or NULL
#'
#' A tool executes inside `tool_execute_frame()` (agent-dispatch.R), whose frame binds the marker
#' `.gptr_tool_run`; the call stack is walked with `sys.frame(k)` (never `sys.frames()`, R3), so
#' no package-global stack exists (INFRA-15).
#' @noRd
run_current = function() {
  k = sys.nframe()
  while (k > 0L) {
    run = get0(".gptr_tool_run", envir = sys.frame(k), inherits = FALSE)
    if (inherits(run, "gptr_run")) return(run)
    k = k - 1L
  }
  NULL
}

#' Where `r` evaluates for this run: the plan-mode scratch overlay (IC-15), else the run's home
#' @noRd
run_eval_env = function(run) {
  if (is.null(run)) return(NULL)
  run$scratch %||% run$home
}

#' Build and dispatch an agent event for a run (ev_dispatch() redacts the payload)
#' @return The dispatch result (decision, collect and patch events).
#' @noRd
run_emit = function(run, type, ...) {
  s = run$shell
  d = session_data(s)
  live = session_live(s)
  ev = ev_new(type, session = d$id, run = run$id, agent = run$opts$agent %||% "main",
              turn = d$turns, ...)
  ev_dispatch(type, ev, session = s, ctx = if (is.null(live)) NULL else live$ctx)
}

#' Build and dispatch a session event (outside a run, or for the session's current run)
#' @noRd
session_emit = function(s, type, ...) {
  d = session_data(s)
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  ev = ev_new(type, session = d$id, run = if (is.null(run)) NULL else run$id, agent = "main",
              turn = d$turns, ...)
  ev_dispatch(type, ev, session = s, ctx = if (is.null(live)) NULL else live$ctx)
}

#' The UI backend of a run (the `ui.get` service of P11), or NULL
#' @noRd
run_ui = function(run) {
  if (!ext_service_has("ui.get")) return(NULL)
  tryCatch(ext_service_get("ui.get")(run$shell), error = function(e) NULL)
}

# The dispatcher (agent-dispatch.R) is layer L2: it may call L0, L1 records and its own `agent`
# area, never the L3 session files (03 section 2.2; P01's test-arch-layers.R). It reaches the
# session only through its run and the agent-area helpers below.

#' The data environment of a run's session
#' @noRd
run_data = function(run) session_data(run$shell)

#' The live record of a run's session, or NULL
#' @noRd
run_live = function(run) session_live(run$shell)

#' The ctx of a run's session, or NULL
#' @noRd
run_ctx = function(run) {
  live = session_live(run$shell)
  if (is.null(live)) NULL else live$ctx
}

#' The id of a ctx's session, or NULL for a process-level ctx
#' @noRd
run_ctx_sid = function(ctx) {
  s = ctx$session
  if (is.null(s)) NULL else session_data(s)$id
}

#' Append a message (a tool result) to a run's session; returns the entry id invisibly
#' @noRd
run_append_message = function(run, msg) session_append(run$shell, entry_message(msg))

#' Append a custom entry to a run's session; returns the entry id invisibly
#' @noRd
run_append_custom = function(run, type, data) {
  session_append(run$shell, entry_custom(type, data))
}
```

Append to `R/session-budget.R`:

```r
# ---------------------------------------------------------------------------- budgets (IC-66)

#' Budget limits of a new run: the call's budget over the settings default for a root run; for a
#' nested run, or a child whose run option `root` names another session (IC-66), only the call's
#' own share (the root's limits still apply through run_chain(): min(share, root remaining))
#' @noRd
run_budget_limits = function(s, opts, outer) {
  own = as.list(opts$budget %||% list())
  if (!is.null(outer) || !is.null(run_budget_root(s, opts))) return(own)
  defaults = setting_get("budget", session = s,
                         default = list(tokens = 2e6, cost = 5, turns = NULL))
  utils::modifyList(as.list(defaults), own)
}

#' The live root session named by the run option `root` (04 section 7.6: "the root session id
#' for budgets, IC-66") when it is another session than `s`, else NULL
#' @noRd
run_budget_root = function(s, opts) {
  rid = opts$root
  if (!is.character(rid) || length(rid) != 1L || is.na(rid)) return(NULL)
  if (identical(rid, session_data(s)$id)) return(NULL)
  session_by_id(rid)
}

#' The shared budget pool of a root that has no run of its own: the container of a top-level team
#' or fan-out (P19 passes its id as `opts$root`). Created once, on the root's live record, with
#' the per-call default merged with the call's budget; it is charged with the root's usage since
#' its creation (usage_add() rolls every child's rows up to the root). P19 creates one container
#' per top-level call, so one pool per container is one budget per top-level call (IC-66).
#' @return An environment with the fields run_chain(), run_used() and budget_near() read (`id`,
#'   `shell`, `budget`, `usage_start`, `near`), or NULL.
#' @noRd
run_budget_pool = function(s, opts) {
  root = run_budget_root(s, opts)
  if (is.null(root)) return(NULL)
  rl = session_live(root)
  if (is.null(rl) || !is.null(rl$run)) return(NULL)
  if (is.null(rl$budget_root)) {
    rd = session_data(root)
    pool = new.env(parent = emptyenv())
    pool$id = paste0("root:", rd$id)
    pool$shell = root
    pool$budget = run_budget_limits(root, list(budget = opts$budget), NULL)
    pool$usage_start = nrow(rd$usage)
    pool$near = character()
    rl$budget_root = pool
  }
  rl$budget_root
}

#' The runs whose budgets apply to a run: itself, its outer runs, the live runs of its session's
#' ancestors (children charge the root), and the root named by the run option `root`: its run, or
#' the shared pool of a root without a run (IC-66)
#' @noRd
run_chain = function(run) {
  out = list()
  ids = character()
  add = function(r) {
    if (!is.null(r) && !(r$id %in% ids)) {
      out[[length(out) + 1L]] <<- r
      ids <<- c(ids, r$id)
    }
  }
  r = run
  while (!is.null(r)) {
    add(r)
    r = r$outer
  }
  pid = session_data(run$shell)$parent_id
  while (!is.null(pid)) {
    p = session_by_id(pid)
    if (is.null(p)) break
    pl = session_live(p)
    if (!is.null(pl$run)) add(pl$run)
    pid = session_data(p)$parent_id
  }
  root = run_budget_root(run$shell, run$opts)
  if (!is.null(root)) {
    rl = session_live(root)
    if (!is.null(rl$run)) add(rl$run)
  }
  add(run$budget_root)
  out
}

#' Tokens, cost and requests charged to a run's session since the run started (children included)
#' @noRd
run_used = function(run) {
  u = session_data(run$shell)$usage
  u = u[seq_len(nrow(u)) > run$usage_start, , drop = FALSE]
  u = u[!duplicated(u$request_id), , drop = FALSE]
  list(tokens = sum(u$input + u$output + u$cache_read + u$cache_write_5m + u$cache_write_1h),
       cost = sum(u$cost), turns = nrow(u))
}

#' Check the budgets that apply to a session's current run
#' @param estimate Estimated input tokens of the next request.
#' @return `NULL` or `list(kind, budget, used)`.
#' @noRd
budget_check = function(s, estimate = 0) {
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  if (is.null(run)) return(NULL)
  for (r in run_chain(run)) {
    lim = r$budget
    if (!length(lim)) next
    used = run_used(r)
    if (!is.null(lim$tokens) && used$tokens + estimate > lim$tokens) {
      return(list(kind = "tokens", budget = lim$tokens, used = used$tokens))
    }
    if (!is.null(lim$cost) && used$cost >= lim$cost) {
      return(list(kind = "cost", budget = lim$cost, used = used$cost))
    }
    if (!is.null(lim$turns) && used$turns >= lim$turns) {
      return(list(kind = "turns", budget = lim$turns, used = used$turns))
    }
  }
  NULL
}

#' Emit `budget_near` once per kind when a budget that applies to the run passes 80%
#' @noRd
budget_near = function(run) {
  for (r in run_chain(run)) {
    lim = r$budget
    if (!length(lim)) next
    used = run_used(r)
    for (kind in intersect(names(lim), c("tokens", "cost", "turns"))) {
      b = lim[[kind]]
      if (is.null(b) || kind %in% r$near) next
      if (used[[kind]] >= 0.8 * b) {
        r$near = c(r$near, kind)
        run_emit(run, "budget_near", kind = kind, budget = b, used = used[[kind]])
      }
    }
  }
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(agent-run|session-budget)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 96 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/agent-run.R R/session-budget.R tests/testthat/test-agent-run.R tests/testthat/test-session-budget.R
git commit -m "feat(agent): add run records, agent events and budget checks"
```

---

### Task 6: Session verbs: model, mode and the steering queue

**Files:**

- Modify: `R/session-object.R`
- Test: `tests/testthat/test-session-object.R`

**Interfaces:**

Consumes:

- P01: `block_context()`, `msg_operator()`, `as_utf8()`; P02: `registry_get()`; P03: `redact(x, profile = "persist")`.
- Tasks 3-5: `model_canonical()`, `entry_model_change()`, `entry_custom()`, `session_append()`, `session_emit()`, `session_live()`, `run_current()`.

Produces:

- `session_set_model(s, ref, reason = "user")` (resolves, appends `model_change`, emits `model_select`), `session_set_mode(s, mode, source = "user")` (appends `gptr.mode_change`; a running run gets an operator `mode` message after the current tool results), `session_enqueue(s, text, as = c("steer", "follow_up"), source = "api_user", blocks = list())` (FIFO items `list(text, blocks, source, t)`, `queue_update`; refused with `gptr_error_permission` from model code of the same session tree, IC-55), `session_root_id(s)`, `mode_block_text(s, mode)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-session-object.R`:

```r

# ---------------------------------------------------------------- verbs

test_that("session_set_model() appends model_change and emits model_select", {
  local_fake_provider(list("x"))
  local_fake_provider(list("y"), name = "other")
  ev = local_events("model_select")
  s = test_session()
  session_set_model(s, "other/other-1", reason = "user")
  expect_identical(s$model, "other/other-1")
  d = session_data(s)
  last = d$entries[[length(d$entries)]]
  expect_identical(last$type, "model_change")
  expect_identical(last$gptr$reason, "user")
  expect_identical(ev(s)[[1L]]$from, "fake/fake-1")
  expect_identical(ev(s)[[1L]]$to, "other/other-1")
  n = length(d$entries)
  session_set_model(s, "other/other-1")
  expect_length(d$entries, n)
  expect_error(session_set_model(s, "nowhere/model-9"), class = "gptr_error_unknown_model")
})

test_that("session_set_mode() appends gptr.mode_change; a running session gets an operator note", {
  s = test_session(mode = "manual")
  session_set_mode(s, "auto", source = "user")
  expect_identical(s$mode, "auto")
  d = session_data(s)
  last = d$entries[[length(d$entries)]]
  expect_identical(last$custom_type, "gptr.mode_change")
  expect_identical(last$data, list(from = "manual", to = "auto", source = "user"))
  run = test_run(s)
  session_set_mode(s, "plan", source = "pause_menu")
  expect_identical(run$mode, "plan")
  op = run$pending_operator[[1L]]
  expect_identical(op$role, "operator")
  expect_identical(op$kind, "mode")
  expect_match(msg_text(op), "<mode name=\"plan\">", fixed = TRUE)
  expect_error(session_set_mode(s, "reckless"), class = "gptr_error_invalid_argument")
})

test_that("a registered `mode` context block renders the operator note", {
  id = registry_add(gptr_spec("context_block", "mode", provide = function(ctx, budget) "MODE TEXT",
                              placement = "turn", authority = "data", budget = 300L, order = 300L),
                    source = "user", rank = 3L)
  withr::defer(registry_remove(id))
  s = test_session()
  expect_identical(mode_block_text(s, "edits"), "<mode name=\"edits\">\nMODE TEXT\n</mode>")
})

test_that("session_enqueue() appends FIFO items by kind and emits queue_update", {
  ev = local_events("queue_update")
  s = test_session()
  session_enqueue(s, "first", as = "steer", source = "pipe")
  session_enqueue(s, "second", as = "follow_up", source = "repl")
  session_enqueue(s, "third", as = "steer", source = "extension")
  q = session_data(s)$queue
  expect_identical(vapply(q$steer, function(i) i$text, ""), c("first", "third"))
  expect_identical(q$follow_up[[1L]]$source, "repl")
  expect_named(q$steer[[1L]], c("text", "blocks", "source", "t"))
  last = ev(s)[[3L]]
  expect_identical(c(last$steer, last$follow_up), c(2L, 1L))
  expect_error(session_enqueue(s, "x", source = "nowhere"), class = "gptr_error_invalid_argument")
  expect_error(session_enqueue(s, 1), class = "gptr_error_invalid_argument")
})

test_that("session_root_id() follows live parents to the root", {
  root = test_session()
  child = test_session(kind = "child", parent = root)
  grandchild = test_session(kind = "child", parent = child)
  expect_identical(session_root_id(grandchild), session_data(root)$id)
  expect_identical(session_root_id(root), session_data(root)$id)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-object$")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 82 ]`, with errors such as ``Error in `session_set_model(s, "other/other-1", reason = "user")`: could not find function "session_set_model"``.

- [ ] **Step 3: Write the implementation**

The `<mode>` block comes from a registered `mode` context block (P07) when there is one, else a one-line notice, so the verb works before P07 exists.

Append to `R/session-object.R`:

```r
# ---------------------------------------------------------------------------- verbs

#' Switch the session's model: resolve, append `model_change`, emit `model_select`
#' @noRd
session_set_model = function(s, ref, reason = "user") {
  check_string(ref, "ref")
  check_string(reason, "reason")
  d = session_data(s)
  m = model_canonical(ref, strict = TRUE)
  from = d$model
  if (identical(from, m$ref) && identical(d$thinking, m$thinking)) return(invisible(s))
  session_append(s, entry_model_change(m$ref, m$thinking, reason))
  d$model = m$ref
  d$thinking = m$thinking
  session_emit(s, "model_select", from = from, to = m$ref, reason = reason)
  invisible(s)
}

#' Switch the session's permission mode
#'
#' Appends `gptr.mode_change`. On an idle session the next user message carries the new `<mode>`
#' block (P07's turn blocks); on a running session the run's mode changes at once and an operator
#' message carrying the `<mode>` block is sent after the current tool results.
#' @noRd
session_set_mode = function(s, mode, source = "user") {
  mode = check_choice(mode, session_modes, "mode")
  check_string(source, "source")
  d = session_data(s)
  from = d$mode
  if (identical(from, mode)) return(invisible(s))
  session_append(s, entry_custom("gptr.mode_change", list(from = from, to = mode, source = source)))
  d$mode = mode
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  if (!is.null(run)) {
    run$mode = mode
    note = msg_operator("mode", mode_block_text(s, mode))
    run$pending_operator = c(run$pending_operator, list(note))
  }
  invisible(s)
}

#' The `<mode>` block of a mode: the registered `mode` context block (P07), else a one-line notice
#' @noRd
mode_block_text = function(s, mode) {
  d = session_data(s)
  live = session_live(s)
  spec = tryCatch(registry_get("context_block", "mode", session = d$id), error = function(e) NULL)
  body = NULL
  if (!is.null(spec) && is.function(spec$provide) && !is.null(live)) {
    out = tryCatch(spec$provide(live$ctx, spec$budget %||% 300L), error = function(e) NULL)
    body = if (is.list(out)) out$text else out
  }
  if (!is.character(body) || length(body) != 1L || is.na(body) || !nzchar(body)) {
    body = paste0("The permission mode is now ", mode, ".")
  }
  block_context("mode", body, attrs = list(name = mode))$text
}

#' Enqueue a steer or a follow-up: the queue behind gptr_steer(), the pipe and ctx$send() (IC-55)
#'
#' Model code of the same session tree (an `r` evaluation of a run of the tree) cannot steer a
#' session of the tree that has already run: `gptr_error_permission`. The first input of a
#' session that has never run (P08 queues a `.run = FALSE` call's prompt as a follow-up) is not a
#' steer and is accepted. The text is redacted with the `context` profile at ingress.
#' @return `s`, invisibly.
#' @noRd
session_enqueue = function(s, text, as = c("steer", "follow_up"), source = "api_user",
                           blocks = list()) {
  check_class(s, "gptr_session", "s")
  check_string(text, "text")
  as = check_choice(as, c("steer", "follow_up"), "as")
  source = check_choice(source, queue_sources, "source")
  check_list(blocks, "blocks")
  d = session_data(s)
  cur = run_current()
  never_ran = !length(d$entries) && is.null(session_live(s)$run)
  if (!is.null(cur) && identical(cur$tool_call$name, "r") && !never_ran &&
      identical(session_root_id(cur$shell), session_root_id(s))) {
    gptr_abort(paste0("model code cannot send steering messages to its own session tree (session ",
                      d$id, ")"),
               "permission", action = "steer the running session tree", tool = "r", risk = NULL,
               how_to_allow = "send steering messages from outside the run", session = d$id)
  }
  item = list(text = redact(as_utf8(text), "context"), blocks = blocks, source = source,
              t = as.numeric(Sys.time()))
  q = d$queue
  q[[as]][[length(q[[as]]) + 1L]] = item
  d$queue = q
  session_emit(s, "queue_update", steer = length(q$steer), follow_up = length(q$follow_up))
  invisible(s)
}

#' The id of the root of a session tree (following live parents)
#' @noRd
session_root_id = function(s) {
  d = session_data(s)
  seen = d$id
  while (!is.null(d$parent_id)) {
    p = session_by_id(d$parent_id)
    if (is.null(p) || d$parent_id %in% seen) return(d$parent_id)
    d = session_data(p)
    seen = c(seen, d$id)
  }
  d$id
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-object$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 106 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/session-object.R tests/testthat/test-session-object.R
git commit -m "feat(session): add the model, mode and steering-queue verbs"
```

---

### Task 7: Tool dispatcher and permission kernel

**Files:**

- Create: `R/agent-dispatch.R`
- Test: `tests/testthat/test-agent-dispatch.R`
- Test: `tests/testthat/test-session-store.R`

**Interfaces:**

Consumes:

- P01: `schema_validate(schema, input)`, `truncate_output(text, budget_tokens, class = "r_output", head = 0.4, id_prefix = "o")`, `json_decode()`, `json_encode()`, `json_obj()`, `msg_tool_result(tool_call_id, tool_name, content, is_error = FALSE, details = NULL, usage = NULL, timestamp = NULL)`, `block_text()`, `est_tokens()`, `gptr_opt()`, `project_root()`, `ext_service_has()`, `ext_service_get()`.
- P02: `registry_get()`, `registry_all(kind, session = NULL)`, `as_tool_result(x)`, `gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)`, `spec_tool_execute(fun, output_tokens)` (`ext-specs.R`, L0: the generated `execute` of 04 §6.8, which `dispatch_nested()` builds for an `r` member that has only `fun`), `ext_control_grant(run, what)` (P02's IC-53 point 3 helper: "P06 or P11 calls `ext_control_grant()` after an `ask_human` approval of a control export"); P03: `redact()`; P04: `reactor_now()`.
- Services (04 §7.0): `risk.classify`, `ui.get` (through `run_ui()`), `checkpoint.note`.
- Task 5 (agent area): `run_emit()`, `run_current()`, `run_eval_env()`, `run_ui()`, `run_data()`, `run_live()`, `run_ctx()`, `run_ctx_sid()`, `run_append_message()`, `run_append_custom()`. This file is layer L2 (03 §3.2): it calls L0, the L1 record constructors and its own `agent` area only, never the L3 `session-*.R` files, which P01's `test-arch-layers.R` would flag; the session is reached through the run.

Produces:

- `dispatch_tools(run, calls)` -> `list(results = list(<gptr_tool_result>), terminate = lgl(1), messages = list(<tool_result message>))` (04 §7.6's two fields plus the appended tool-result messages, which the engine of Task 10 passes to the loop and to `turn_end` so that no tool `value` enters an event or the loop state, rule R1; never throws; a `length`/`refusal` stop fails every call unrun); `call_record(run, block)` (04 §4.4 call records); `tool_validate(tool, input)`; `tool_lookup(name, session_id = NULL)`, `tool_schema(tool)`, `tool_error(text)`.
- `perm_check(call, run)` -> `list(decision, reason, input, risk, rule)` (IC-04, IC-53; a policy answer that is not `NULL`, a list or one known decision denies); `perm_request_record(call, run, out, risk, tier)` (04 §7.11), `risk_level(risk)`; `perm_ask_questions(input)` (the question texts of a blocked `ask` call, stored in `gptr_error_noninteractive`, IC-68; a remembered UI answer is stored by P11 through `permissions:remember`, never by the kernel); `perm_grant_control(run, risk)` (the one-shot tokens of an approved `ask_human`: the flagged control exports appended to `run$signal$control`, the slot P08's `control_check()` reads, plus P02's `ext_control_grant()`; cleared when the call ends).
- `tool_result_message(result, call)` (redaction with the `context` profile, truncation to `gptr.r_output_tokens`, `details$value_ref`, never the value); `dispatch_nested(name, input, ctx)` (nested `gptr$` calls: skips the gate for members listed by the outer analysis at an approved level, records at most 20 `details$nested`, signals `gptr_error_tool` inside model code; an `r` member declared with `fun` only runs through P02's generated `execute`, 04 §6.8).
- Checkpointer calls `checkpoint_before()`/`checkpoint_after()` gathered into one `gptr.checkpoint` entry.

- [ ] **Step 1: Write the failing test**

S31 (tool-result truncation) lives in the store test file because report 02 lists it with the store checks.

Create `tests/testthat/test-agent-dispatch.R`:

```r
source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# Dispatch one assistant message's tool calls on a run that is attached but not started.
dispatch = function(s, blocks, stop_reason = "tool_use", opts = list(), .env = parent.frame()) {
  run = test_run(s, opts, .env = .env)
  run$message = msg_assistant(blocks, api = "fake", provider = "fake", model = "fake-1",
                              stop_reason = stop_reason)
  calls = lapply(blocks, function(b) call_record(run, b))
  out = dispatch_tools(run, calls)
  list(run = run, out = out, msgs = tool_results(s))
}
tc = function(name, input = json_obj(), id = paste0("c_", name)) block_tool_call(id, name, input)
a_call = function(name = "w", input = list(x = 1), tool = NULL) {
  list(id = "c1", name = name, input = input, raw = NULL, tool = tool, nested = FALSE,
       parent_id = NULL, outer_level = NULL, risk = NULL)
}
code_schema = list(type = "object", required = I("code"),
                   properties = list(code = list(type = "string")))

# ---------------------------------------------------------------- the pipeline (INFRA-09, INFRA-10)

test_that("`{\"n\":3}` without the required `code` is an error result; nothing runs (INFRA-09)", {
  local_permissive()
  ran = new.env()
  ran$yes = FALSE
  local_tool("r", function(input, ctx) {
    ran$yes = TRUE
    "x"
  }, parameters = code_schema)
  x = dispatch(test_session(), list(tc("r", list(n = 3))))
  tr = x$msgs[[1L]]
  expect_true(tr$is_error)
  expect_match(msg_text(tr), "^Invalid arguments for r: .*code")
  expect_false(ran$yes)
})

test_that("arguments that failed the final JSON parse are an error result", {
  local_permissive()
  local_tool("r", function(input, ctx) "x", parameters = code_schema)
  x = dispatch(test_session(), list(tc("r", list(INVALID_JSON = "{\"code\": \"1 +"))))
  expect_match(msg_text(x$msgs[[1L]]), "not valid JSON", fixed = TRUE)
})

test_that("a length or refusal stop fails every call unrun (INFRA-09)", {
  local_permissive()
  ran = new.env()
  ran$n = 0L
  local_tool("w", function(input, ctx) {
    ran$n = ran$n + 1L
    "x"
  })
  for (stop in c("length", "refusal")) {
    x = dispatch(test_session(), list(tc("w"), tc("w", id = "c2")), stop_reason = stop)
    expect_length(x$msgs, 2L)
    expect_identical(msg_text(x$msgs[[1L]]),
                     paste0("Tool call not executed: the response stopped (", stop,
                            ") before the call was complete."))
  }
  expect_identical(ran$n, 0L)
})

test_that("an unknown tool is an error result", {
  local_permissive()
  x = dispatch(test_session(), list(tc("nope")))
  expect_identical(msg_text(x$msgs[[1L]]), "Tool nope not found")
  expect_true(x$msgs[[1L]]$is_error)
})

failing_tools = function(.env = parent.frame()) {
  local_tool("throw", function(input, ctx) stop("boom"), .env = .env)
  local_tool("warn2", function(input, ctx) {
    old = options(warn = 2)
    on.exit(options(old), add = TRUE)
    warning("warned")
    "not reached"
  }, .env = .env)
  local_tool("slowloop", function(input, ctx) {
    setTimeLimit(elapsed = 0.3, transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
    repeat NULL
  }, .env = .env)
  local_tool("spin", function(input, ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "not reached"
  }, .env = .env)
}

test_that("throw, warn-as-error, time limit and interrupt give paired events (INFRA-10)", {
  local_permissive()
  failing_tools()
  orders = list(c("throw", "warn2", "slowloop", "spin"), c("spin", "throw", "warn2", "slowloop"),
                c("warn2", "spin", "slowloop", "throw"), c("slowloop", "throw", "spin", "warn2"))
  for (ord in orders) {
    s = test_session()
    ev = local_events(c("tool_execution_start", "tool_execution_end"))
    blocks = lapply(ord, function(n) tc(n, id = paste0("c_", n)))
    res = tryCatch({
      dispatch(s, blocks)
      "returned"
    }, interrupt = function(cnd) "interrupted")
    expect_identical(res, "interrupted")
    tr = tool_results(s)
    k = match("spin", ord)
    expect_length(tr, k)
    expect_true(all(vapply(tr, function(m) isTRUE(m$is_error), NA)))
    texts = stats::setNames(vapply(tr, msg_text, ""), ord[seq_len(k)])
    expect_match(texts[["spin"]],
                 "^Interrupted after [0-9.]+ s; side effects may have occurred[.]$")
    if ("throw" %in% names(texts)) expect_match(texts[["throw"]], "boom", fixed = TRUE)
    if ("warn2" %in% names(texts)) expect_match(texts[["warn2"]], "warned", fixed = TRUE)
    if ("slowloop" %in% names(texts)) expect_match(texts[["slowloop"]], "time limit|elapsed")
    types = vapply(ev(s), function(e) e$type, "")
    expect_identical(sum(types == "tool_execution_start"), k)
    expect_identical(sum(types == "tool_execution_end"), k)
    expect_identical(vapply(tr, function(m) m$tool_call_id, ""), paste0("c_", ord[seq_len(k)]))
  }
})

test_that("tool_call hooks block, modify, and fail closed", {
  local_permissive()
  seen = new.env()
  local_tool("echo", function(input, ctx) {
    seen$x = input$x
    "ok"
  }, parameters = list(type = "object", properties = list(x = list(type = "string"))))
  local_hook("tool_call", function(event, ctx) {
    list(decision = "modify", input = list(x = "changed"))
  })
  dispatch(test_session(), list(tc("echo", list(x = "original"))))
  expect_identical(seen$x, "changed")
  local_hook("tool_call", function(event, ctx) {
    list(decision = "block", reason = "denied by policy")
  })
  x = dispatch(test_session(), list(tc("echo", list(x = "original"))))
  expect_identical(msg_text(x$msgs[[1L]]), "Tool execution was blocked: denied by policy")
})

test_that("a throwing tool_call hook blocks the call (fail closed)", {
  local_permissive()
  local_tool("echo", function(input, ctx) "ran")
  local_hook("tool_call", function(event, ctx) stop("hook bug"))
  x = dispatch(test_session(), list(tc("echo")))
  expect_match(msg_text(x$msgs[[1L]]), "^Tool execution was blocked")
})

test_that("tool_result hooks patch the content; terminate is reported when every result sets it", {
  local_permissive()
  local_tool("add", function(input, ctx) "2")
  local_tool("stopper", function(input, ctx) {
    res = gptr_tool_result("final")
    res$terminate = TRUE
    res
  })
  local_hook("tool_result", function(event, ctx) {
    list(content = list(block_text(paste0("[audited] ", event$content[[1L]]$text))))
  })
  x = dispatch(test_session(), list(tc("add")))
  expect_identical(msg_text(x$msgs[[1L]]), "[audited] 2")
  expect_false(x$out$terminate)
  expect_true(dispatch(test_session(), list(tc("stopper")))$out$terminate)
  expect_false(dispatch(test_session(), list(tc("stopper"), tc("add")))$out$terminate)
})

test_that("tool_result_message() redacts, truncates, keeps value_ref and never the value", {
  local_gptr_options(r_output_tokens = 20L)
  spec = gptr_tool("t", "t", execute = function(input, ctx) NULL)
  res = gptr_tool_result(paste(rep("line of output", 200), collapse = "\n"), value = mtcars)
  msg = tool_result_message(res, a_call("t", tool = spec))
  expect_identical(msg$role, "tool_result")
  expect_lt(nchar(msg_text(msg)), 3000L)
  expect_identical(msg$details$value_ref$class, "data.frame")
  expect_null(msg$details[["value"]])
})

test_that("checkpointers wrap sequential mutating calls into one gptr.checkpoint entry", {
  local_permissive()
  local_tool("mut", function(input, ctx) "changed")
  local_tool("ro", function(input, ctx) "read", annotations = list(read_only = TRUE))
  # P02's checkpointer validator requires `undo` and `redo` as well (04 section 10.2 row 29)
  id = registry_add(gptr_spec("checkpointer", "test_cp", scope = "objects",
                              before = function(call, ctx) list(name = call$name),
                              after = function(call, ctx, token) list(saw = token$name),
                              undo = function(fragment, ctx, force) character(),
                              redo = function(fragment, ctx, force) character()),
                    source = "user", rank = 3L)
  withr::defer(registry_remove(id))
  s = test_session()
  x = dispatch(s, list(tc("mut"), tc("ro")))
  cps = Filter(function(e) identical(e$custom_type, "gptr.checkpoint"), session_data(s)$entries)
  expect_length(cps, 1L)
  expect_identical(cps[[1L]]$data$fragments$test_cp$saw, "mut")
  expect_identical(x$msgs[[1L]]$details$checkpoint, cps[[1L]]$id)
})

test_that("session_enqueue() from model code of the same session tree is refused (IC-55)", {
  local_permissive()
  local_tool("r", function(input, ctx) {
    session_enqueue(ctx$session, "sneaky", as = "steer", source = "pipe")
    "sent"
  }, parameters = code_schema)
  local_tool("helper", function(input, ctx) {
    session_enqueue(ctx$session, "from a tool", as = "steer", source = "pipe")
    "sent"
  })
  s = test_session()
  x = dispatch(s, list(tc("r", list(code = "gptr_steer(s, 'x')")), tc("helper")))
  expect_true(x$msgs[[1L]]$is_error)
  expect_match(msg_text(x$msgs[[1L]]), "cannot send steering messages", fixed = TRUE)
  expect_identical(msg_text(x$msgs[[2L]]), "sent")
  expect_identical(vapply(session_data(s)$queue$steer, function(i) i$text, ""), "from a tool")
})

# ---------------------------------------------------------------- nested calls (03 section 6.8.4)

test_that("dispatch_nested() gates, records and returns the member's value", {
  local_permissive()
  local_tool("inner", function(input, ctx) gptr_tool_result("inner ran", value = 42L))
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$value = dispatch_nested("inner", json_obj(), ctx)
    "outer ran"
  })
  x = dispatch(test_session(), list(tc("outer")))
  expect_identical(box$value, 42L)
  nested = x$msgs[[1L]]$details$nested
  expect_length(nested, 1L)
  expect_identical(nested[[1L]]$tool, "inner")
})

test_that("a failing nested member signals gptr_error_tool inside the model's code", {
  local_permissive()
  local_tool("inner", function(input, ctx) stop("inner failed"))
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$err = tryCatch(dispatch_nested("inner", json_obj(), ctx), error = function(e) e)
    "outer ran"
  })
  dispatch(test_session(), list(tc("outer")))
  expect_s3_class(box$err, "gptr_error_tool")
  expect_identical(box$err$tool, "inner")
  expect_error(dispatch_nested("absent", json_obj(), session_live(test_session())$ctx),
               class = "gptr_error_tool")
})

test_that("a member listed by the outer call's analysis at an approved level skips the gate", {
  checked = new.env()
  checked$names = character()
  local_policy("mode", function(call, ctx) {
    checked$names = c(checked$names, call$name)
    list(decision = "allow", reason = "ok")
  })
  local_tool("inner", function(input, ctx) gptr_tool_result("x", value = 1))
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$v = dispatch_nested("inner", json_obj(), ctx)
    "ok"
  }, risk = function(input, ctx) {
    list(level = 2L, categories = character(), paths = character(),
         flagged = data.frame(call = "gptr$inner()", fn = "gptr$inner", level = 1L, category = "",
                              path = NA_character_, path_class = NA_character_,
                              stringsAsFactors = FALSE))
  })
  dispatch(test_session(), list(tc("outer")))
  expect_identical(box$v, 1)
  expect_identical(checked$names, "outer")
})

test_that("outside a run a member simply runs and returns its value", {
  local_tool("inner", function(input, ctx) gptr_tool_result("x", value = "direct"))
  expect_identical(dispatch_nested("inner", json_obj(), session_live(test_session())$ctx), "direct")
})

test_that("an r member declared with fun only runs through the generated execute (04 6.8)", {
  local_permissive()
  off = gptr_register(gptr_tool("hello", "Say hi",
                                parameters = list(type = "object", required = I("name"),
                                                  properties = list(name = list(type = "string"))),
                                fun = function(name) paste("hi", name), exposure = "r",
                                namespace = "wdemo"))
  withr::defer(off())
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$value = dispatch_nested("wdemo/hello", list(name = "x"), ctx)
    "outer ran"
  })
  x = dispatch(test_session(), list(tc("outer")))
  expect_identical(box$value, "hi x")
  expect_identical(x$msgs[[1L]]$details$nested[[1L]]$tool, "wdemo/hello")
  expect_identical(dispatch_nested("wdemo/hello", list(name = "y"),
                                   session_live(test_session())$ctx), "hi y")
})

# ---------------------------------------------------------------- permission checks (IC-04, IC-53)

test_that("with no mode policy a mutating tool asks and is blocked without a UI (NS-12)", {
  local_tool("w", function(input, ctx) "written")
  s = test_session(mode = "manual")
  x = dispatch(s, list(tc("w"), tc("w", id = "c2")))
  expect_length(x$msgs, 1L)
  expect_match(msg_text(x$msgs[[1L]]), "^Permission denied: ")
  cnd = x$run$condition
  expect_s3_class(cnd, "gptr_error_permission")
  expect_identical(cnd$tool, "w")
  expect_identical(cnd$session, session_data(s)$id)
  expect_match(cnd$how_to_allow, "mode = \"auto\"", fixed = TRUE)
  expect_false(is.null(x$run$blocked))
})

test_that("a non-interactive ask call stops blocked with gptr_error_noninteractive (IC-68)", {
  local_tool("ask", function(input, ctx) "answered",
             parameters = list(type = "object",
                               properties = list(questions = list(type = "array"))))
  local_policy("mode", function(call, ctx) {
    if (identical(call$name, "ask")) {
      list(decision = "ask_human", reason = "no one can answer the questions")
    } else {
      list(decision = "allow", reason = "ok")
    }
  })
  qs = list(list(id = "q1", question = "Which file?", type = "text"),
            list(id = "q2", question = "Keep the old one?", type = "text"))
  x = dispatch(test_session(mode = "manual"), list(tc("ask", list(questions = qs))))
  cnd = x$run$condition
  expect_s3_class(cnd, "gptr_error_noninteractive")
  expect_identical(cnd$what, "ask")
  expect_identical(cnd$questions, c("Which file?", "Keep the old one?"))
  expect_match(conditionMessage(cnd), "Which file? | Keep the old one?", fixed = TRUE)
  expect_false(is.null(x$run$blocked))
  expect_match(msg_text(x$msgs[[1L]]), "^Permission denied")
})

test_that("policies combine deny > ask_human > ask > modify > allow", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) list(decision = "allow", reason = "mode"))
  expect_identical(perm_check(a_call(), run)$decision, "allow")
  local_policy("other", function(call, ctx) list(decision = "deny", reason = "no"))
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_identical(dec$rule, "other")
})

test_that("a throwing policy denies", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) stop("broken policy"))
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_match(dec$reason, "broken policy", fixed = TRUE)
})

test_that("a malformed policy answer denies instead of throwing (fail closed)", {
  run = test_run(test_session())
  box = new.env()
  box$answer = "yes"
  local_policy("mode", function(call, ctx) box$answer)
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_match(dec$reason, "malformed answer", fixed = TRUE)
  box$answer = list(decision = c("allow", "deny"), reason = "two answers")
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_match(dec$reason, "unknown decision", fixed = TRUE)
  box$answer = TRUE
  expect_identical(perm_check(a_call(), run)$decision, "deny")
})

test_that("a modify is re-checked once; a second modify denies", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) {
    if (identical(call$input$x, 1)) {
      list(decision = "modify", reason = "fix", input = list(x = 2))
    } else {
      list(decision = "allow", reason = "ok")
    }
  })
  dec = perm_check(a_call(input = list(x = 1)), run)
  expect_identical(dec$decision, "allow")
  expect_identical(dec$input$x, 2)
  local_policy("again", function(call, ctx) {
    list(decision = "modify", reason = "again", input = list(x = 3))
  })
  expect_identical(perm_check(a_call(input = list(x = 1)), run)$decision, "deny")
})

test_that("permission_request hooks answer an ask; a hook error denies", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) list(decision = "ask", reason = "level 2"))
  id = local_hook("permission_request", function(event, ctx) {
    list(decision = "allow", reason = "reviewer")
  })
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "allow")
  expect_identical(dec$rule, "hook")
  hook_remove(id)
  local_hook("permission_request", function(event, ctx) stop("reviewer crashed"))
  expect_identical(perm_check(a_call(), run)$decision, "deny")
})

test_that("a hook answering allow to an ask_human is ignored (IC-53)", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) list(decision = "ask_human", reason = "level 4"))
  local_hook("permission_request", function(event, ctx) {
    list(decision = "allow", reason = "reviewer")
  })
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_false(is.null(run$blocked))
  expect_match(run$blocked$how_to_allow, "interactively", fixed = TRUE)
})

test_that("gptr.noninteractive_ask = \"deny\" returns a denial the model sees", {
  local_gptr_options(noninteractive_ask = "deny")
  run = test_run(test_session())
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_null(run$blocked)
  expect_match(perm_denial_text(dec), "no one can approve", fixed = TRUE)
})

test_that("the UI answers asks when the run's snapshot can prompt", {
  local_gptr_options(interactive = TRUE)
  ui = new.env()
  ui$answer = list(decision = "allow", remember = "session", feedback = NULL)
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE,
         permission = function(request) {
           ui$request = request
           ui$answer
         })
  })
  local_policy("mode", function(call, ctx) {
    list(decision = "ask", reason = "level 2", suggested_rule = "w(**)")
  })
  s = test_session()
  run = test_run(s)
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "allow")
  expect_identical(ui$request$tier, "ask")
  expect_identical(ui$request$tool, "w")
  expect_identical(ui$request$session, session_data(s)$id)
  # a remembered answer is P11's to store (permissions:remember); the kernel keeps no copy
  expect_identical(session_data(s)$rules$allow, character())
  ui$answer = list(decision = "deny", feedback = "use the other file")
  expect_identical(perm_check(a_call(), run)$reason, "use the other file")
  ui$answer = list(decision = "abort")
  perm_check(a_call(), run)
  expect_true(run$abort_after_call)
})

test_that("an option changed by model code mid-run does not change the run's gate (IC-53)", {
  withr::defer(options(gptr.unsafe_no_permissions = NULL))
  local_tool("loosen", function(input, ctx) {
    options(gptr.unsafe_no_permissions = TRUE)
    "loosened"
  })
  local_tool("w", function(input, ctx) "written")
  local_policy("mode", function(call, ctx) {
    if (identical(call$name, "loosen")) list(decision = "allow", reason = "ok") else
      list(decision = "ask", reason = "needs approval")
  })
  x = dispatch(test_session(mode = "manual"), list(tc("loosen"), tc("w")))
  expect_identical(msg_text(x$msgs[[1L]]), "loosened")
  expect_match(msg_text(x$msgs[[2L]]), "^Permission denied")
  expect_false(is.null(x$run$blocked))
})

test_that("a forwarded request is re-classified from its raw input (IC-53)", {
  run = test_run(test_session())
  spec = gptr_tool("rm_all", "Delete", execute = function(input, ctx) "x",
                   risk = function(input, ctx) {
                     list(level = 3L, categories = "delete", paths = character())
                   })
  local_policy("mode", function(call, ctx) {
    if (call$risk$level >= 3L) list(decision = "ask", reason = "level 3") else
      list(decision = "allow", reason = "ok")
  })
  forged = a_call("rm_all", tool = spec)
  forged$risk = list(level = 0L)
  dec = perm_check(forged, run)
  expect_identical(dec$decision, "deny")
  expect_identical(dec$risk$level, 3L)
})
```

Append to `tests/testthat/test-session-store.R`:

```r

test_that(oracle_title(store_recs, "S31"), {
  local_gptr_options(r_output_tokens = 50L)
  spec = gptr_tool("big", "big", execute = function(input, ctx) NULL)
  long = paste(rep("a long line of printed output", 400), collapse = "\n")
  msg = tool_result_message(gptr_tool_result(long), list(id = "c1", name = "big", tool = spec))
  expect_lt(nchar(msg_text(msg)), nchar(long))
  expect_lt(est_tokens(msg_text(msg), "r_output"), 200)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(agent-dispatch|session-store)$")'`

Expected: `[ FAIL 29 | WARN 0 | SKIP 0 | PASS 42 ]`, with errors such as ``Error in `call_record(run, b)`: could not find function "call_record"``.

- [ ] **Step 3: Write the implementation**

Adapted from report 02 §5.1 (`run_tool_call()`, `execute_tool_calls()`) with gptr's texts. An interrupted tool is recorded by `on.exit()` in `tool_execute_frame()` ("Interrupted after <s> s; side effects may have occurred.") and the interrupt continues to the run's interrupt policy: never an exiting `tryCatch(interrupt =)` (G3 finding 5).

Create `R/agent-dispatch.R`:

```r
# agent-dispatch.R -- the tool dispatcher and the permission kernel (P06, layer L2).
#
# lookup -> validate -> tool_call hooks -> perm_check() -> checkpointers' before -> execute ->
# checkpointers' after -> tool_result hooks; never throws (INFRA-10); results and tool-result
# messages in source order. Adapted from report 02 section 5.1 (`run_tool_call()`,
# `execute_tool_calls()`) with gptr's texts and G3's interrupt rule: an interrupted tool is recorded
# with on.exit(), never with an exiting tryCatch(interrupt =), which would pre-empt the pause menu.
# `perm_check()` is the permission combination of IC-04 and IC-53: policies (deny > ask_human > ask
# > modify > allow; a throwing policy denies; no active `mode` policy means ask, fail closed), then
# `permission_request` hooks for `ask`, then the UI, then the non-interactive stop.

perm_decisions = c("allow", "modify", "ask", "ask_human", "deny")

#' Execute a turn's tool calls in source order
#'
#' A `length` or `refusal` stop of the assistant message (`run$message`) fails every call unrun.
#' After an abort or a blocked gate the remaining calls are skipped (their calls are closed by the
#' projection of P05).
#' @param calls Call records (04 section 4.4).
#' @return `list(results = list(<gptr_tool_result>), terminate = lgl(1), messages = list(<msg>))`:
#'   the contract's two fields plus the tool-result messages appended to the transcript. The run
#'   engine hands `messages` (never `results`, whose `value` may be a user object, rule R1) to the
#'   loop and to `turn_end`.
#' @noRd
dispatch_tools = function(run, calls) {
  stop_reason = run$message$stop_reason %||% "stop"
  truncated = stop_reason %in% c("length", "refusal")
  results = list()
  messages = list()
  flags = logical()
  for (call in calls) {
    if (isTRUE(run$signal$aborted) || !is.null(run$blocked)) break
    run_emit(run, "tool_execution_start", tool_call_id = call$id, tool_name = call$name,
             input = call$input)
    t0 = reactor_now()
    res = if (truncated) {
      tool_error(paste0("Tool call not executed: the response stopped (", stop_reason,
                        ") before the call was complete."))
    } else {
      dispatch_one(run, call)
    }
    msg = dispatch_finish(run, call, res, t0)
    results[[length(results) + 1L]] = res
    messages[[length(messages) + 1L]] = msg
    flags = c(flags, isTRUE(res$terminate))
    if (isTRUE(run$abort_after_call)) {
      run$abort_after_call = FALSE
      run$signal$aborted = TRUE
      run$signal$reason = "user"
      break
    }
  }
  list(results = results, terminate = length(flags) > 0L && all(flags), messages = messages)
}

#' One call through the pipeline; returns a gptr_tool_result and never throws an R error
#' @noRd
dispatch_one = function(run, call) {
  ctx = run_ctx(run)
  if (is.null(call$tool)) return(tool_error(paste0("Tool ", call$name, " not found")))
  v = tool_validate(tool_frozen(run, call$tool), call$input)
  if (!isTRUE(v$ok)) {
    return(tool_error(paste0("Invalid arguments for ", call$name, ": ",
                             paste(v$errors, collapse = "; "))))
  }
  call$input = v$input
  hk = run_emit(run, "tool_call", tool_name = call$name, tool_call_id = call$id, input = call$input,
                nested = FALSE, parent_tool_call_id = NULL, risk = call_risk(call, ctx, run))
  if (is.list(hk) && identical(hk$decision, "block")) {
    return(tool_error(paste0("Tool execution was blocked: ",
                             hk$reason %||% "a tool_call hook blocked it")))
  }
  if (is.list(hk) && identical(hk$decision, "modify") && is.list(hk$input)) call$input = hk$input
  dec = perm_check(call, run)
  call$risk = dec$risk
  if (!identical(dec$decision, "allow")) return(tool_error(perm_denial_text(dec)))
  call$input = dec$input %||% call$input
  call$approved_level = risk_level(dec$risk)
  tokens = checkpoint_before(run, call, ctx)
  res = tool_execute_frame(run, call, ctx)
  res = checkpoint_after(run, call, ctx, tokens, res)
  nested = run$nested[[call$id]]
  if (length(nested)) res$details$nested = nested
  tool_result_hooks(run, call, res)
}

#' Execute a tool; the frame marks the running tool for run_current() (`.gptr_tool_run`)
#'
#' The one-shot tokens that a human approval of an `ask_human` call granted for gptr's control
#' exports (`run$signal$control`, IC-53 item 3) live only while this call executes; they are
#' cleared when it ends. Errors (including warnings under `warn = 2` and time limits) become
#' error results; an interrupt unwinds through on.exit(), which records "Interrupted after <s> s;
#' side effects may have occurred." and leaves the decision to the run's interrupt policy.
#' @noRd
tool_execute_frame = function(run, call, ctx) {
  .gptr_tool_run = run
  force(.gptr_tool_run)
  t0 = reactor_now()
  done = FALSE
  run$tool_call = call
  on.exit({
    run$tool_call = NULL
    run$signal$control = character()
    if (!done) tool_interrupted(run, call, reactor_now() - t0)
  }, add = TRUE)
  res = tryCatch(as_tool_result(call$tool$execute(call$input, ctx)),
                 error = function(e) tool_error(conditionMessage(e)))
  done = TRUE
  res
}

#' Record the truthful result of an interrupted tool (then the interrupt continues to unwind)
#' @noRd
tool_interrupted = function(run, call, elapsed) {
  res = tool_error(paste0("Interrupted after ", format(round(elapsed, 1), nsmall = 1),
                          " s; side effects may have occurred."))
  tryCatch(dispatch_finish(run, call, res, reactor_now() - elapsed), error = function(e) NULL)
  invisible(res)
}

#' Append the tool-result message and emit tool_execution_end, message_start and message_end
#' @return The tool-result message, invisibly.
#' @noRd
dispatch_finish = function(run, call, res, t0) {
  msg = tool_result_message(res, call)
  run_append_message(run, msg)
  run_emit(run, "tool_execution_end", tool_call_id = call$id, tool_name = call$name,
           is_error = isTRUE(res$is_error), elapsed = reactor_now() - t0,
           details = list(fields = names(res$details)))
  run_emit(run, "message_start", role = "tool_result")
  run_emit(run, "message_end", role = "tool_result", message = msg)
  invisible(msg)
}

#' An error result with one text block
#' @noRd
tool_error = function(text) gptr_tool_result(text, is_error = TRUE)

#' The text content of a result
#' @noRd
tool_result_text = function(res) {
  paste(vapply(Filter(function(b) identical(b$type, "text"), res$content %||% list()),
               function(b) b$text, ""), collapse = "\n")
}

#' The `tool_result` patch chain (any subset of content, details, is_error)
#' @noRd
tool_result_hooks = function(run, call, res) {
  out = run_emit(run, "tool_result", tool_name = call$name, tool_call_id = call$id,
                 input = call$input, content = res$content, details = res$details,
                 is_error = isTRUE(res$is_error))
  if (!is.list(out)) return(res)
  if (!is.null(out$content)) {
    res$content = if (is.character(out$content)) {
      list(block_text(paste(out$content, collapse = "\n")))
    } else {
      out$content
    }
  }
  if (!is.null(out$details)) res$details = out$details
  if (!is.null(out$is_error)) res$is_error = isTRUE(out$is_error)
  res
}

#' The call record of a tool_call block (04 section 4.4)
#' @noRd
call_record = function(run, block) {
  list(id = block$id, name = block$name, input = block$arguments %||% json_obj(),
       raw = block$raw_arguments, tool = tool_lookup(block$name, run$session), nested = FALSE,
       parent_id = NULL, outer_level = NULL, risk = NULL)
}

#' A tool the model may call: registered, with an `execute`, not hidden
#' @noRd
tool_lookup = function(name, session_id = NULL) {
  spec = tryCatch(registry_get("tool", name, session = session_id), error = function(e) NULL)
  hidden = is.null(spec) || !is.function(spec$execute) || identical(spec$exposure, "hidden")
  if (hidden) NULL else spec
}

#' A tool whose `parameters` is a function gets the schema frozen for the session (IC-68)
#' @noRd
tool_frozen = function(run, tool) {
  if (!is.function(tool$parameters)) return(tool)
  live = run_live(run)
  schemas = get0("tool_schemas", envir = live$memo, inherits = FALSE)
  if (is.null(schemas)) {
    arr = tryCatch(json_decode(run_data(run)$frozen$tools_json %||% "[]"),
                   error = function(e) list())
    schemas = stats::setNames(lapply(arr, function(t) t$input_schema),
                              vapply(arr, function(t) t$name %||% "", ""))
    assign("tool_schemas", schemas, envir = live$memo)
  }
  tool$parameters = schemas[[tool$name]]
  tool
}

#' Validate a tool's input against its parameters (INFRA-09)
#' @return `list(ok, input, errors)` as `schema_validate()`; `{"INVALID_JSON": raw}` input fails.
#' @noRd
tool_validate = function(tool, input) {
  if (is.list(input) && !is.null(input$INVALID_JSON)) {
    return(list(ok = FALSE, input = input, errors = "the arguments are not valid JSON"))
  }
  schema = tool_schema(tool)
  if (is.null(schema)) return(list(ok = TRUE, input = input, errors = character()))
  schema_validate(schema, if (length(input)) input else json_obj())
}

#' A tool's JSON Schema: its `parameters`, else one derived from `fun`'s formals (every property a
#' string, required when it has no default); NULL when there is nothing to validate against
#' @noRd
tool_schema = function(tool) {
  p = tool$parameters
  if (is.list(p)) return(p)
  if (is.function(p) || !is.function(tool$fun)) return(NULL)
  f = formals(tool$fun)
  f = f[names(f) != "..."]
  if (!length(f)) return(list(type = "object", properties = json_obj()))
  req = names(f)[vapply(seq_along(f), function(i) identical(f[[i]], quote(expr = )), NA)]
  props = stats::setNames(lapply(names(f), function(n) list(type = "string")), names(f))
  list(type = "object", properties = props, required = I(req))
}

#' The tool-result message of a result (04 section 4.4)
#'
#' Text is redacted with the `context` profile and truncated to the tool's output budget; details
#' carry `value_ref` (class and size), never the value.
#' @noRd
tool_result_message = function(result, call) {
  budget = call$tool$output_tokens %||% gptr_opt("r_output_tokens")
  details = result$details %||% list()
  content = lapply(result$content %||% list(), function(b) {
    if (!identical(b$type, "text")) return(b)
    txt = redact(b$text, "context")
    if (est_tokens(txt, "r_output") > budget) {
      tr = truncate_output(strsplit(txt, "\n", fixed = TRUE)[[1L]], budget)
      txt = tr$text
      if (!is.null(tr$out_id)) details$out_id = tr$out_id
    }
    block_text(txt)
  })
  if (!is.null(result$value)) {
    details$value_ref = list(class = class(result$value)[1L],
                             bytes = as.numeric(utils::object.size(result$value)))
  }
  if (!is.null(result$out_id)) details$out_id = result$out_id
  msg_tool_result(call$id, call$name, content, is_error = isTRUE(result$is_error),
                  details = if (length(details)) details else NULL, usage = result$usage)
}

# ---------------------------------------------------------------------------- checkpointers

#' Checkpointers run only for sequential tools that are not read-only
#' @noRd
checkpoint_applies = function(call) {
  !is.null(call$tool) && !identical(call$tool$execution, "concurrent") &&
    !isTRUE(call$tool$annotations$read_only)
}

#' Call every checkpointer's `before`; a failure marks its fragment not restorable
#' @return A named list of tokens, or NULL when checkpointing does not apply.
#' @noRd
checkpoint_before = function(run, call, ctx) {
  if (!checkpoint_applies(call)) return(NULL)
  cps = registry_all("checkpointer", session = run$session)
  if (!length(cps)) return(NULL)
  tokens = list()
  for (cp in cps) {
    tokens[cp$name] = list(tryCatch(cp$before(call, ctx), error = function(e) {
      structure(list(reason = conditionMessage(e)), class = "gptr_checkpoint_failed")
    }))
  }
  tokens
}

#' Call every checkpointer's `after`; the fragments go into one gptr.checkpoint entry
#' @noRd
checkpoint_after = function(run, call, ctx, tokens, res) {
  if (is.null(tokens)) return(res)
  frags = list()
  for (cp in registry_all("checkpointer", session = run$session)) {
    tok = tokens[[cp$name]]
    frag = if (inherits(tok, "gptr_checkpoint_failed")) {
      list(restorable = FALSE, reason = tok$reason)
    } else {
      tryCatch(cp$after(call, ctx, tok),
               error = function(e) list(restorable = FALSE, reason = conditionMessage(e)))
    }
    if (!is.null(frag)) frags[[cp$name]] = frag
  }
  if (!length(frags)) return(res)
  id = run_append_custom(run, "gptr.checkpoint", list(tool_call_id = call$id, fragments = frags))
  res$details$checkpoint = id
  res
}

# ---------------------------------------------------------------------------- nested calls

#' Nested `gptr$...` calls made while an `r` evaluation runs (04 section 7.6)
#'
#' A function the outer call's static analysis listed at a level no higher than the level approved
#' for the outer call runs without a second prompt; otherwise the call passes perm_check(). The
#' call is recorded in the outer result's `details$nested` (at most 20). Returns the tool's value,
#' or signals `gptr_error_tool` inside the model's code. Outside a run the member simply runs.
#' @noRd
dispatch_nested = function(name, input, ctx) {
  check_string(name, "name")
  sid = run_ctx_sid(ctx)
  tool = tryCatch(registry_get("tool", name, session = sid), error = function(e) NULL)
  # an `r` member declared with `fun` only has no `execute` (04 section 6.8): run its `fun`
  # through P02's generated execute (printed value within output_tokens, `value` kept)
  if (!is.null(tool) && !is.function(tool$execute) && is.function(tool$fun)) {
    tool$execute = spec_tool_execute(tool$fun, tool[["output_tokens"]])
  }
  if (is.null(tool) || !is.function(tool$execute)) {
    gptr_abort(paste0("Tool ", name, " not found"), "tool", tool = name, status = "not_found")
  }
  v = tool_validate(tool, input)
  if (!isTRUE(v$ok)) {
    gptr_abort(paste0("Invalid arguments for ", name, ": ", paste(v$errors, collapse = "; ")),
               "tool", tool = name, status = "invalid")
  }
  run = run_current()
  if (is.null(run)) {
    res = tryCatch(as_tool_result(tool$execute(v$input, ctx)),
                   error = function(e) tool_error(conditionMessage(e)))
    return(nested_value(res, name))
  }
  outer = run$tool_call
  k = length(run$nested[[outer$id]]) + 1L
  call = list(id = paste0(outer$id, "/", k), name = name, input = v$input, raw = NULL, tool = tool,
              nested = TRUE, parent_id = outer$id, outer_level = outer$approved_level %||% 0L,
              risk = NULL)
  hk = run_emit(run, "tool_call", tool_name = name, tool_call_id = call$id, input = call$input,
                nested = TRUE, parent_tool_call_id = outer$id, risk = NULL)
  if (is.list(hk) && identical(hk$decision, "block")) {
    nested_record(run, outer$id, name, tool_error("blocked"), NA_integer_)
    gptr_abort(paste0("Tool execution was blocked: ", hk$reason %||% "a tool_call hook blocked it"),
               "tool", tool = name, status = "blocked")
  }
  if (is.list(hk) && identical(hk$decision, "modify") && is.list(hk$input)) call$input = hk$input
  level = nested_listed_level(outer, name)
  if (is.null(level) || level > call$outer_level) {
    dec = perm_check(call, run)
    level = risk_level(dec$risk)
    if (!identical(dec$decision, "allow")) {
      nested_record(run, outer$id, name, tool_error(dec$reason %||% "denied"), level)
      gptr_abort(perm_denial_text(dec), "tool", tool = name, status = "denied")
    }
    call$input = dec$input %||% call$input
  }
  t0 = reactor_now()
  run_emit(run, "tool_execution_start", tool_call_id = call$id, tool_name = name,
           input = call$input)
  res = tryCatch(as_tool_result(tool$execute(call$input, ctx)),
                 error = function(e) tool_error(conditionMessage(e)))
  run_emit(run, "tool_execution_end", tool_call_id = call$id, tool_name = name,
           is_error = isTRUE(res$is_error), elapsed = reactor_now() - t0,
           details = list(fields = names(res$details)))
  nested_record(run, outer$id, name, res, level)
  nested_value(res, name)
}

#' The R value of a nested result, or gptr_error_tool for an error result
#' @noRd
nested_value = function(res, name) {
  if (isTRUE(res$is_error)) gptr_abort(tool_result_text(res), "tool", tool = name, status = "error")
  res$value
}

#' The level at which the outer call's static analysis listed a member, or NULL
#' @noRd
nested_listed_level = function(outer, name) {
  flagged = outer$risk$flagged
  if (!is.data.frame(flagged) || !nrow(flagged)) return(NULL)
  short = sub("^.*/", "", name)
  hit = flagged$fn %in% c(name, short, paste0("gptr$", short),
                          paste0("gptr$", sub("/", "$", name, fixed = TRUE)))
  if (!any(hit)) return(NULL)
  max(as.integer(flagged$level[hit]))
}

#' Record a nested call (at most 20 per outer call)
#' @noRd
nested_record = function(run, outer_id, name, res, level) {
  rec = run$nested[[outer_id]] %||% list()
  if (length(rec) < 20L) {
    rec[[length(rec) + 1L]] = list(tool = name, summary = substr(tool_result_text(res), 1L, 60L),
                                   is_error = isTRUE(res$is_error), level = level)
  }
  nested = run$nested
  nested[[outer_id]] = rec
  run$nested = nested
  invisible(NULL)
}

# ---------------------------------------------------------------------------- permissions

#' The permission combination (IC-04, IC-53)
#'
#' The risk is always recomputed from the call's raw input (a forwarded worker request is
#' re-classified by the parent). Reads only the run's safety snapshot.
#' @return `list(decision = "allow" | "deny" | "ask" | "ask_human" | "modify", reason, input,
#'   risk, rule)`; the dispatcher executes only "allow".
#' @noRd
perm_check = function(call, run) {
  ctx = run_ctx(run)
  snap = run$opts$safety %||% list()
  risk = call_risk(call, ctx, run)
  if (isTRUE(snap$unsafe_no_permissions)) {
    return(perm_result("allow", "gptr.unsafe_no_permissions is set", call$input, risk))
  }
  out = perm_policies(call, ctx, run, risk)
  if (identical(out$decision, "modify")) {
    call2 = call
    call2$input = out$input
    risk2 = call_risk(call2, ctx, run)
    out2 = perm_policies(call2, ctx, run, risk2)
    if (identical(out2$decision, "modify")) {
      return(perm_result("deny", "a policy modified the call twice", call$input, risk2, out2$rule))
    }
    call = call2
    risk = risk2
    out = out2
  }
  if (out$decision %in% c("allow", "deny")) {
    return(perm_result(out$decision, out$reason, call$input, risk, out$rule))
  }
  perm_ask(call, run, out, risk)
}

#' A perm_check() result
#' @noRd
perm_result = function(decision, reason, input, risk = NULL, rule = NULL, how = NULL) {
  list(decision = decision, reason = reason %||% "", input = input, risk = risk, rule = rule,
       how = how)
}

#' The strictness of a decision (higher wins)
#' @noRd
perm_rank = function(decision) match(decision, perm_decisions)

#' Combine every policy's opinion: deny > ask_human > ask > modify > allow; a throwing policy
#' denies; no active `mode` policy means ask (fail closed)
#' @noRd
perm_policies = function(call, ctx, run, risk) {
  specs = registry_all("policy", session = run$session)
  call$risk = risk
  best = NULL
  for (p in specs) {
    res = tryCatch(p$check(call, ctx), error = function(e) {
      list(decision = "deny", reason = paste0("policy ", p$name, " failed: ", conditionMessage(e)))
    })
    if (is.null(res)) next
    # a malformed answer fails closed like a throwing policy (04 section 10.2 row 12)
    if (!is.list(res)) {
      res = list(decision = "deny", reason = paste0("policy ", p$name,
                                                    " returned a malformed answer"))
    }
    if (is.null(res$decision)) next
    ok = is.character(res$decision) && length(res$decision) == 1L &&
      res$decision %in% perm_decisions
    if (!ok) {
      res = list(decision = "deny", reason = paste0("policy ", p$name,
                                                    " returned an unknown decision"))
    }
    res$rule = res$rule %||% p$name
    if (is.null(best) || perm_rank(res$decision) > perm_rank(best$decision)) best = res
  }
  has_mode = any(vapply(specs, function(p) identical(p$name, "mode"), NA))
  if (!has_mode && (is.null(best) || perm_rank(best$decision) < perm_rank("ask"))) {
    best = list(decision = "ask", reason = "no permission mode policy is active", rule = NULL)
  }
  if (is.null(best)) best = list(decision = "allow", reason = "no policy objected", rule = NULL)
  best$input = best$input %||% call$input
  best
}

#' Ask: permission_request hooks (tier `ask` only), then the UI, then the non-interactive stop
#' @noRd
perm_ask = function(call, run, out, risk) {
  snap = run$opts$safety %||% list()
  tier = if (identical(out$decision, "ask_human")) "ask_human" else "ask"
  req = perm_request_record(call, run, out, risk, tier)
  if (identical(tier, "ask")) {
    payload = req[setdiff(names(req), c("session", "turn"))]
    hk = do.call(run_emit, c(list(run, "permission_request"), payload))
    if (is.list(hk) && identical(hk$decision, "allow")) {
      return(perm_result("allow", hk$reason %||% "allowed by a permission_request hook", call$input,
                         risk, "hook"))
    }
    if (is.list(hk) && identical(hk$decision, "deny")) {
      return(perm_result("deny", hk$reason %||% "denied by a permission_request hook", call$input,
                         risk, "hook"))
    }
  }
  ui = if (isTRUE(snap$can_prompt)) run_ui(run) else NULL
  if (!is.null(ui) && isTRUE(tryCatch(ui$has_ui(), error = function(e) FALSE))) {
    ans = tryCatch(ui$permission(req), error = function(e) list(decision = "deny", feedback = NULL))
    if (identical(ans$decision, "allow")) {
      # a `remember` answer is stored by P11's builtin:permissions (channel permissions:remember,
      # never for level 4, control or ask_human), not here
      if (identical(tier, "ask_human")) perm_grant_control(run, risk)
      return(perm_result("allow", "approved by the user", call$input, risk, "user"))
    }
    if (identical(ans$decision, "abort")) {
      run$abort_after_call = TRUE
      return(perm_result("deny", "the user aborted the run", call$input, risk, "user",
                         how = "The run stops here."))
    }
    return(perm_result("deny", ans$feedback %||% "the user declined", call$input, risk, "user"))
  }
  if (identical(snap$noninteractive_ask, "deny")) {
    return(perm_result("deny", "no one can approve this action in this run", call$input, risk,
                       how = "Choose an approach that needs no approval, or report what you need."))
  }
  how = if (identical(tier, "ask_human")) {
    "This action always needs a person to approve it: run it interactively."
  } else {
    "Allow it with mode = \"auto\", a permission rule (gptr_permissions()), or run interactively."
  }
  run$blocked = list(tool = call$name, risk = risk, how_to_allow = how)
  run$condition = if (identical(call$name, "ask")) {
    # the `ask` tool in a run nobody can answer (IC-68, NS-12): gptr_error_noninteractive
    qs = perm_ask_questions(call$input)
    tryCatch(
      gptr_abort(paste0("The run stopped: the model asked a question and no one can answer in ",
                        "this run: ", paste(qs, collapse = " | ")),
                 "noninteractive", what = "ask", questions = qs),
      error = function(e) e)
  } else {
    tryCatch(
      gptr_abort(paste0("The run stopped: `", call$name, "` needs approval and no one can ",
                        "answer in this run. ", how),
                 "permission", action = paste(req$summary, collapse = "\n"), tool = call$name,
                 risk = risk, how_to_allow = how, session = run$session),
      error = function(e) e)
  }
  perm_result("deny", "approval is needed and no one can answer in this run", call$input, risk,
              how = "The run stops here.")
}

#' The question texts of an `ask` call's input (`questions`: a list of `list(id, question, ...)`)
#' @noRd
perm_ask_questions = function(input) {
  qs = if (is.list(input)) input$questions else NULL
  if (!is.list(qs)) return(character())
  vapply(qs, function(q) {
    txt = if (is.list(q)) q$question else NULL
    if (is.character(txt) && length(txt)) txt[[1L]] else ""
  }, "", USE.NAMES = FALSE)
}

#' Grant the one-shot tokens of an approved `ask_human` call (IC-53 item 3)
#'
#' One token per control export the call's risk record flags (category `control`), appended to
#' `run$signal$control` (the slot P08's `control_check()` and P06's `session_control_check()`
#' consume) and recorded with P02's `ext_control_grant()` for P02's own guard. The tokens are
#' cleared when the call ends (`tool_execute_frame()`).
#' @noRd
perm_grant_control = function(run, risk) {
  fl = risk$flagged
  fns = character()
  if (is.data.frame(fl) && nrow(fl) && all(c("fn", "category") %in% names(fl))) {
    fns = unique(sub("^gptr::", "", as.character(fl$fn[fl$category %in% "control"])))
  }
  run$signal$control = c(run$signal$control %||% character(), fns)
  for (fn in fns) tryCatch(ext_control_grant(run$id, fn), error = function(e) NULL)
  invisible(fns)
}

#' The permission request record (04 section 7.11)
#' @noRd
perm_request_record = function(call, run, out, risk, tier) {
  d = run_data(run)
  note = if (ext_service_has("checkpoint.note")) {
    tryCatch(ext_service_get("checkpoint.note")(call, run), error = function(e) NULL)
  } else {
    NULL
  }
  list(tool = call$name, input = call$input, summary = perm_summary(call), risk = risk,
       reason = out$reason %||% "", suggested_rule = out$suggested_rule, undo_note = note,
       session = d$id, turn = d$turns, nested = isTRUE(call$nested), tier = tier)
}

#' The lines to show for a request: the code (at most 20 lines), a path, or the input as JSON
#' @noRd
perm_summary = function(call) {
  code = call$input$code
  if (is.character(code) && length(code) == 1L) {
    lines = strsplit(code, "\n", fixed = TRUE)[[1L]]
    if (length(lines) > 20L) lines = c(lines[1:20], paste0("+", length(lines) - 20L, " more lines"))
    return(lines)
  }
  path = call$input$path
  if (is.character(path)) return(paste0("path: ", path))
  txt = json_encode(call$input)
  if (nchar(txt) > 200L) paste0(substr(txt, 1L, 200L), "...") else txt
}

#' The text the model sees for a denial
#' @noRd
perm_denial_text = function(dec) {
  paste0("Permission denied: ", dec$reason %||% "not allowed", ". ",
         dec$how %||% "Explain what you need or choose another approach.")
}

#' Classify a call: the tool's `risk` function, the `risk.classify` service for `r` code (P11),
#' else level 0 for read-only tools and 2 otherwise; an error in a classifier gives level 3
#' @noRd
call_risk = function(call, ctx, run) {
  tool = call$tool
  fallback = list(level = 3L, categories = "unknown", paths = character())
  if (!is.null(tool) && is.function(tool$risk)) {
    return(tryCatch(tool$risk(call$input, ctx), error = function(e) fallback))
  }
  r_code = identical(call$name, "r") && is.character(call$input$code)
  if (r_code && ext_service_has("risk.classify")) {
    return(tryCatch(ext_service_get("risk.classify")(call$input$code, envir = run_eval_env(run),
                                                     root = project_root(), kind = "r"),
                    error = function(e) fallback))
  }
  list(level = if (isTRUE(tool$annotations$read_only)) 0L else 2L, categories = character(),
       paths = character())
}

#' The level of a risk record (2 when unknown)
#' @noRd
risk_level = function(risk) as.integer(risk$level %||% 2L)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(agent-dispatch|session-store)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 166 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/agent-dispatch.R tests/testthat/test-agent-dispatch.R tests/testthat/test-session-store.R
git commit -m "feat(agent): add the tool dispatcher and the permission kernel"
```

---

### Task 8: Recovery classification

**Files:**

- Modify: `R/agent-run.R`
- Create: `tests/testthat/fixtures/oracles/report02/recovery.json`
- Test: `tests/testthat/test-agent-run.R`

**Interfaces:**

Consumes:

- None beyond base R: the classifier works on assistant messages (`stop_reason`, `error_message`) and the unsignalled condition carried by an `error` event (04 §4.5).

Produces:

- `is_context_overflow(message, context_window = NULL, error = NULL)` (the 21 provider texts of report 02 §5.3, the 413/no-body forms, silent overflow by usage), `run_retryable(msg, err)` (transient vs. non-retryable, never an overflow), `retryable_error_text(text)`, `err_class(err)`, `provider_classes(err)`, `agent_retry_delay(attempt)` (2 then 4 seconds, C-33); pattern constants `overflow_patterns`, `non_overflow_patterns`, `bodyless_overflow_pattern`, `retryable_pattern`, `non_retryable_pattern`.

- [ ] **Step 1: Write the failing test**

`recovery.json` holds report 02's 26 recovery checks; R01's `data` field holds the 21 overflow texts. R01-R18 (pure classification) are tested here; R19-R26 need the engine and come with Task 10.

Create `tests/testthat/fixtures/oracles/report02/recovery.json`:

```json
[
 {"id":"R01","source":"02 5.3","check":"21/21 provider overflow examples detected","status":"port","gptr":"is_context_overflow() detects all 21 provider texts","data":["prompt is too long: 213462 tokens > 200000 maximum","413 {\"error\":{\"type\":\"request_too_large\",\"message\":\"Request exceeds the maximum size\"}}","Your input exceeds the context window of this model","Requested token count exceeds the model's maximum context length of 131072 tokens","Input length (265330) exceeds model's maximum context length (262144).","The input token count (1196265) exceeds the maximum number of tokens allowed (1048575)","This model's maximum prompt length is 131072 but the request contains 537812 tokens","Please reduce the length of the messages or completion","This endpoint's maximum context length is 128000 tokens. However, you requested about 150000 tokens","Input length 300000 exceeds the maximum allowed input length of 262,144 tokens.","The input (300000 tokens) is longer than the model's context length (262144 tokens).","the request exceeds the available context size, try increasing it","tokens to keep from the initial prompt is greater than the context length","prompt token count of 140000 exceeds the limit of 128000","invalid params, context window exceeds limit","Your request exceeded model token limit: 262144 (requested: 300000)","Prompt has 9,000 tokens, but the configured context size is 8,192 tokens","Prompt contains 140000 tokens and 0 draft tokens, too large for model with 131072 maximum context length","{\"code\":\"1261\",\"message\":\"Prompt too long\"}","Range of input length should be [1, 98304]","prompt too long; exceeded max context length by 1200 tokens"]},
 {"id":"R02","source":"02 5.3","check":"throttling text containing 'too many tokens' is NOT overflow","status":"port","gptr":"a throttling message mentioning too many tokens is not an overflow"},
 {"id":"R03","source":"02 5.3","check":"cerebras body-less 400 special case","status":"port","gptr":"'400 status code (no body)' is an overflow for cerebras only"},
 {"id":"R04","source":"02 5.3","check":"silent overflow via usage > window","status":"port","gptr":"a stop with input + cache_read above the window is an overflow"},
 {"id":"R05","source":"02 5.3","check":"length-stop overflow (output 0, input >= 99% window)","status":"port","gptr":"a length stop with zero output at 99% of the window is an overflow"},
 {"id":"R06","source":"02 5.3","check":"length-stop overflow also after a JSON round trip (output is integer 0L)","status":"port","gptr":"an integer 0L output from jsonlite still counts"},
 {"id":"R07","source":"02 5.3","check":"transient errors retryable","status":"port","gptr":"529 overloaded, fetch failed and timeouts are retryable"},
 {"id":"R08","source":"02 5.3","check":"quota/billing never retried","status":"port","gptr":"insufficient_quota, spend-cap and billing errors are not retryable"},
 {"id":"R09","source":"02 5.3","check":"auth error not retryable","status":"port","gptr":"an invalid-key error (status 401) is not retryable"},
 {"id":"R10","source":"02 5.3","check":"agent backoff 2s,4s,8s,... capped at 60s","status":"adapted","gptr":"gptr's agent backoff is 2 s then 4 s, at most two retries (C-33)"},
 {"id":"R11","source":"02 5.3","check":"server-requested delays honoured","status":"port","gptr":"retry_classify() honours retry-after-ms and retry-after (P04)"},
 {"id":"R12","source":"02 5.3","check":"server delay above cap fails fast","status":"port","gptr":"a retry-after above gptr.max_retry_delay is not retried (class retry_after)"},
 {"id":"R13","source":"02 5.3","check":"provider backoff 0.5s*2^i capped at 8s","status":"adapted","gptr":"a 503 is retryable and its computed delay is at most 8 s (P04)"},
 {"id":"R14","source":"02 5.3","check":"HTTP-date retry-after parsed in any LC_TIME; unparsable value falls back to backoff","status":"port","gptr":"an HTTP-date retry-after gives about 5 s; 'soon' falls back to backoff (P04)"},
 {"id":"R15","source":"02 5.3","check":"status classification + x-should-retry","status":"adapted","gptr":"408, 409, 429, 5xx and 529 retry; 400, 401 and 403 do not (x-should-retry is not a gptr input)"},
 {"id":"R16","source":"02 5.3","check":"aborted assistant dropped; synthetic result for c2 inserted before the next user message","status":"port","gptr":"projection drops the aborted message and closes the orphaned call before the next user message (P05)"},
 {"id":"R17","source":"02 5.3","check":"synthetic result text matches Pi","status":"port","gptr":"the orphan's synthetic result is an error result for its call id"},
 {"id":"R18","source":"02 5.3","check":"system message between a tool call and its result is held back (as Pi)","status":"adapted","gptr":"a steering relay recorded between a call and its result is projected after the result"},
 {"id":"R19","source":"02 5.3","check":"succeeded on 3rd request","status":"port","gptr":"529 then 503 then success: three requests, status idle"},
 {"id":"R20","source":"02 5.3","check":"retried request contains only the user prompt (failed attempts omitted from context)","status":"port","gptr":"failed attempts are projected out of the retried request"},
 {"id":"R21","source":"02 5.3","check":"failed attempts stay in the raw transcript","status":"port","gptr":"both error messages remain entries"},
 {"id":"R22","source":"02 5.3","check":"backoff slept 40ms + 80ms","status":"adapted","gptr":"retry_start events carry the delays of agent_retry_delay() and the run waits them"},
 {"id":"R23","source":"02 5.3","check":"non-retryable error: no retry","status":"port","gptr":"insufficient_quota: one request, no retry_start"},
 {"id":"R24","source":"02 5.3","check":"gives up after maxRetries (1 initial + 2 retries)","status":"port","gptr":"three requests, retry_end with ok = FALSE, status error"},
 {"id":"R25","source":"02 5.3","check":"one compaction, then retry succeeded","status":"port","gptr":"an overflow runs compact.run once and the retry succeeds (INFRA-26)"},
 {"id":"R26","source":"02 5.3","check":"second overflow is terminal (no compaction loop); overflow is never 'retried'","status":"port","gptr":"a second overflow settles with gptr_error_context_overflow; compact.run ran once"}
]
```

Append to `tests/testthat/test-agent-run.R`:

```r

# ---------------------------------------------------------------- report 02 section 5.3 (26 checks)

recovery_recs = oracle("recovery")
err_msg = function(text, provider = "x", stop = "error", usage = list()) {
  list(role = "assistant", stop_reason = stop, error_message = text, provider = provider,
       usage = usage)
}

test_that(oracle_title(recovery_recs, "R01"), {
  ex = unlist(recovery_recs$R01$data)
  expect_length(ex, 21L)
  expect_true(all(vapply(ex, function(e) is_context_overflow(err_msg(e)), NA)))
})

test_that(oracle_title(recovery_recs, "R02"), {
  expect_false(is_context_overflow(err_msg(
    "ThrottlingException: Too many tokens, please wait before trying again. rate limit")))
})

test_that(oracle_title(recovery_recs, "R03"), {
  expect_true(is_context_overflow(err_msg("400 status code (no body)", "cerebras")))
  expect_false(is_context_overflow(err_msg("400 status code (no body)", "openai")))
})

test_that(oracle_title(recovery_recs, "R04"), {
  m = list(role = "assistant", stop_reason = "stop",
           usage = list(input = 190000, cache_read = 20000, output = 5))
  expect_true(is_context_overflow(m, 200000))
  expect_false(is_context_overflow(m, 300000))
})

test_that(oracle_title(recovery_recs, "R05"), {
  m = list(role = "assistant", stop_reason = "length",
           usage = list(input = 199000, cache_read = 0, output = 0))
  expect_true(is_context_overflow(m, 200000))
})

test_that(oracle_title(recovery_recs, "R06"), {
  m = json_decode(paste0('{"role":"assistant","stop_reason":"length",',
                         '"usage":{"input":199000,"cache_read":0,"output":0}}'))
  expect_true(is.integer(m$usage$output))
  expect_true(is_context_overflow(m, 200000))
})

test_that(oracle_title(recovery_recs, "R07"), {
  expect_true(run_retryable(err_msg("529 overloaded"), list(status = 529L)))
  expect_true(run_retryable(err_msg("Error: fetch failed"), list()))
  expect_true(run_retryable(err_msg("Connection timed out after 10001 milliseconds"), list()))
  expect_true(run_retryable(err_msg("idle"), list(class = "gptr_error_timeout_idle")))
})

test_that(oracle_title(recovery_recs, "R08"), {
  expect_false(run_retryable(err_msg("insufficient_quota: You exceeded your current quota"),
                             list()))
  expect_false(run_retryable(err_msg("insufficient_quota"), list(status = 429L)))
  expect_false(run_retryable(err_msg("spend limit reached"), list(class = "gptr_error_spend_cap")))
  expect_false(retryable_error_text("429 billing hard limit reached"))
})

test_that(oracle_title(recovery_recs, "R09"), {
  expect_false(run_retryable(err_msg("invalid x-api-key"), list(status = 401L)))
  expect_identical(provider_classes(list(status = 401L)), c("auth", "provider"))
})

test_that(oracle_title(recovery_recs, "R10"), {
  expect_identical(vapply(1:2, agent_retry_delay, 1), c(2, 4))
})

test_that(oracle_title(recovery_recs, "R11"), {
  a = retry_classify(429L, list(`retry-after-ms` = "1500"))
  b = retry_classify(429L, list(`retry-after` = "7"))
  expect_true(a$retry && b$retry)
  expect_equal(a$delay, 1.5)
  expect_equal(b$delay, 7)
})

test_that(oracle_title(recovery_recs, "R12"), {
  x = retry_classify(429L, list(`retry-after` = "120"))
  expect_false(x$retry)
  expect_true("retry_after" %in% x$class)
})

test_that(oracle_title(recovery_recs, "R13"), {
  x = retry_classify(503L, list())
  expect_true(x$retry)
  expect_true(is.null(x$delay) || x$delay <= 8)
})

test_that(oracle_title(recovery_recs, "R14"), {
  lt = as.POSIXlt(Sys.time() + 5, tz = "GMT")
  days = c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
  hd = sprintf("%s, %02d %s %d %02d:%02d:%02d GMT", days[lt$wday + 1L], lt$mday,
               month.abb[lt$mon + 1L], lt$year + 1900L, lt$hour, lt$min, as.integer(lt$sec))
  x = retry_classify(429L, list(`retry-after` = hd))
  expect_true(x$retry)
  expect_true(x$delay > 3 && x$delay <= 5)
  expect_true(retry_classify(429L, list(`retry-after` = "soon"))$retry)
})

test_that(oracle_title(recovery_recs, "R15"), {
  for (st in c(408L, 409L, 429L, 500L, 503L, 529L)) expect_true(retry_classify(st, list())$retry)
  for (st in c(400L, 401L, 403L)) expect_false(retry_classify(st, list())$retry)
})

projection_session = function() {
  local_fake_provider(list("x"), .env = parent.frame())
  s = test_session()
  call = function(id) block_tool_call(id, "read", list(path = "a"))
  session_append(s, entry_message(msg_user("q")))
  session_append(s, entry_message(msg_assistant(list(call("c1"), call("c2")), api = "fake",
                                                provider = "fake", model = "fake-1",
                                                stop_reason = "tool_use")))
  session_append(s, entry_message(msg_tool_result("c1", "read", "ok")))
  session_append(s, entry_message(msg_assistant("partial", api = "fake", provider = "fake",
                                                model = "fake-1", stop_reason = "aborted")))
  session_append(s, entry_message(msg_user("next")))
  s
}

test_that(oracle_title(recovery_recs, "R16"), {
  s = projection_session()
  d = session_data(s)
  pr = project_messages(d$entries, d$leaf, model_resolve("fake/fake-1"))
  expect_identical(vapply(pr, function(m) m$role, ""),
                   c("user", "assistant", "tool_result", "tool_result", "user"))
})

test_that(oracle_title(recovery_recs, "R17"), {
  s = projection_session()
  d = session_data(s)
  pr = project_messages(d$entries, d$leaf, model_resolve("fake/fake-1"))
  expect_identical(pr[[4L]]$tool_call_id, "c2")
  expect_true(pr[[4L]]$is_error)
})

test_that(oracle_title(recovery_recs, "R18"), {
  local_fake_provider(list("x"))
  s = test_session()
  session_append(s, entry_message(msg_user("q")))
  session_append(s, entry_message(msg_assistant(list(block_tool_call("c1", "read",
                                                                     list(path = "a"))),
                                                api = "fake", provider = "fake", model = "fake-1",
                                                stop_reason = "tool_use")))
  relay = "The user sent this message while you were working: x"
  session_append(s, entry_message(msg_operator("steer_relay", relay)))
  session_append(s, entry_message(msg_tool_result("c1", "read", "ok")))
  d = session_data(s)
  pr = project_messages(d$entries, d$leaf, model_resolve("fake/fake-1"))
  expect_identical(vapply(pr, function(m) m$role, ""), c("user", "assistant", "tool_result",
                                                         "operator"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^agent-run$")'`

Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 66 ]`, with errors such as ``Error in `is_context_overflow(err_msg(e))`: could not find function "is_context_overflow"``.

- [ ] **Step 3: Write the implementation**

Ported from report 02 §2.8-2.9 and the §5.3 prototype (`run_with_recovery()`), with the verification-log fixes applied and gptr's constants (C-33).

Append to `R/agent-run.R`:

```r
# ---------------------------------------------------------------------------- recovery

# Error-text patterns: provider error-message facts collected by Pi (MIT licence;
# packages/ai/src/utils/overflow.ts and retry.ts at commit 1b347794), transcribed in report 02
# section 5.3 (`recovery.R`, with the verifier's fixes) and gptr's libcurl additions. Matched with
# perl = TRUE and ignore.case = TRUE.
overflow_patterns = c(
  "prompt (?:is )?too long", "request_too_large", "input is too long for requested model",
  "exceeds the context window",
  "exceeds (?:the )?(?:model'?s )?maximum context length(?: of [\\d,]+ tokens?|\\s*\\([\\d,]+\\))",
  "input token count.*exceeds the maximum", "maximum prompt length is \\d+",
  "reduce the length of the messages", "maximum context length is \\d+ tokens",
  "exceeds (?:the )?maximum allowed input length of [\\d,]+ tokens?",
  "input \\(\\d+ tokens\\) is longer than the model'?s context length \\(\\d+ tokens\\)",
  "exceeds the limit of \\d+", "exceeds the available context size",
  "greater than the context length", "context window exceeds limit", "exceeded model token limit",
  "too large for model with \\d+ maximum context length",
  "prompt has [\\d,]+ tokens?, but the configured context size is [\\d,]+ tokens?",
  "model_context_window_exceeded", "prompt too long; exceeded (?:max )?context length",
  "range of input length should be", "context[_ ]length[_ ]exceeded", "too many tokens",
  "token limit exceeded")
non_overflow_patterns = c("^(Throttling error|Service unavailable):", "rate limit",
                          "too many requests")
bodyless_overflow_pattern = "^4(?:00|13)\\s*(?:status code)?\\s*\\(no body\\)"
non_retryable_pattern = paste(c(
  "GoUsageLimitError", "FreeUsageLimitError", "Monthly usage limit reached", "available balance",
  "insufficient_quota", "out of budget", "quota exceeded", "billing",
  "subscription_sharing_usage_limit_exceeded"), collapse = "|")
retryable_pattern = paste(c(
  "overloaded", "currently experiencing high demand", "rate.?limit", "too many requests", "429",
  "500", "502", "503", "504", "520", "524", "service.?unavailable", "server.?error",
  "internal.?error", "provider.?returned.?error",
  "exceeded request buffer limit while retrying upstream", "network.?error",
  "connection.?error", "connection.?refused", "connection.?lost", "other side closed",
  "fetch failed", "getaddrinfo", "ENOTFOUND", "EAI_AGAIN", "upstream.?connect",
  "reset before headers", "socket hang up", "socket connection was closed", "timed? out",
  "timeout", "terminated", "websocket.?closed", "websocket.?error", "ended without",
  "stream ended before message_stop", "stream ended before a terminal response event",
  "http2 request did not get a response", "retry delay", "you can retry your request",
  "try your request again", "please retry your request", "ResourceExhausted",
  "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable",
  "could not resolve host", "failed to connect", "recv failure", "send failure",
  "ssl connect error", "transfer closed with", "empty reply from server"), collapse = "|")

#' Does any of the patterns match the text? (PCRE, case-insensitive)
#' @noRd
any_match = function(patterns, x) {
  any(vapply(patterns, function(p) grepl(p, x, perl = TRUE, ignore.case = TRUE), NA))
}

#' Is a response a context overflow? (report 02 section 5.3 `is_context_overflow()`)
#' @param message An assistant message (R shape).
#' @param context_window The model's window in tokens, or NULL/NA.
#' @param error The error record of the terminal `error` event, if any.
#' @noRd
is_context_overflow = function(message, context_window = NULL, error = NULL) {
  if (identical(err_class(error %||% list()), "context_overflow")) return(TRUE)
  err = message$error_message
  if (identical(message$stop_reason, "error") && !is.null(err) && nzchar(err)) {
    if (!any_match(non_overflow_patterns, err)) {
      if (any_match(overflow_patterns, err)) return(TRUE)
      if (identical(message$provider, "cerebras") && any_match(bodyless_overflow_pattern, err)) {
        return(TRUE)
      }
    }
  }
  window = suppressWarnings(as.numeric(context_window %||% NA))
  if (is.finite(window) && window > 0) {
    input = (message$usage$input %||% 0) + (message$usage$cache_read %||% 0)
    if (identical(message$stop_reason, "stop") && input > window) return(TRUE)
    if (identical(message$stop_reason, "length") && isTRUE((message$usage$output %||% 0) == 0) &&
        input >= window * 0.99) return(TRUE)
  }
  FALSE
}

#' Does an error text describe a transient failure? (non-retryable patterns win)
#' @noRd
retryable_error_text = function(text) {
  if (is.null(text) || !nzchar(text)) return(FALSE)
  if (grepl(non_retryable_pattern, text, perl = TRUE, ignore.case = TRUE)) return(FALSE)
  grepl(retryable_pattern, text, perl = TRUE, ignore.case = TRUE)
}

#' The gptr class name of an error record (`list(class, status, ...)` of an `error` event)
#' @noRd
err_class = function(err) {
  cls = sub("^gptr_error_", "", as.character(err$class %||% character()))
  cls = setdiff(cls, c("gptr_error", "error", "condition", "provider", "timeout"))
  if (length(cls)) return(cls[[1L]])
  st = suppressWarnings(as.integer(err$status %||% NA_integer_))
  if (is.na(st)) return(NA_character_)
  if (st %in% c(401L, 403L)) return("auth")
  if (st == 429L) return("rate_limit")
  if (st >= 500L) return("overloaded")
  NA_character_
}

#' The condition classes of a failed request (most specific first)
#' @noRd
provider_classes = function(err) {
  k = err_class(err)
  if (is.na(k)) return("provider")
  if (startsWith(k, "timeout")) return(c(k, "timeout"))
  if (k %in% c("auth", "rate_limit", "spend_cap", "retry_after", "overloaded", "context_overflow",
               "network", "redirect", "billing")) return(c(k, "provider"))
  "provider"
}

#' Is a failed request transient, to be retried at agent level?
#' @noRd
run_retryable = function(msg, err) {
  k = err_class(err)
  if (!is.na(k) && k %in% c("spend_cap", "auth", "retry_after", "redirect", "billing",
                            "context_overflow")) {
    return(FALSE)
  }
  if (!is.na(k) && k %in% c("overloaded", "rate_limit", "network", "timeout_idle",
                            "timeout_first_byte", "timeout_connect")) {
    return(!grepl(non_retryable_pattern, msg$error_message %||% "", perl = TRUE,
                  ignore.case = TRUE))
  }
  st = suppressWarnings(as.integer(err$status %||% NA_integer_))
  if (!is.na(st) && (st %in% c(408L, 409L, 429L, 529L) || st >= 500L)) {
    return(!grepl(non_retryable_pattern, msg$error_message %||% "", perl = TRUE,
                  ignore.case = TRUE))
  }
  retryable_error_text(msg$error_message)
}

#' Agent-level retry delays in seconds: 2 s, then 4 s (C-33)
#' @noRd
agent_retry_delay = function(attempt) c(2, 4)[min(attempt, 2L)]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^agent-run$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 85 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/agent-run.R tests/testthat/fixtures/oracles/report02/recovery.json tests/testthat/test-agent-run.R
git commit -m "feat(agent): add recovery classification"
```

---

### Task 9: Request shaping: freeze, routers, request params, image elision, returns

**Files:**

- Modify: `R/agent-run.R`
- Test: `tests/testthat/test-agent-run.R`
- Test: `tests/testthat/test-session-store.R`

**Interfaces:**

Consumes:

- P01: `est_tokens()`, `est_multiplier(state, estimated, reported, prior)`, `hash_sha256()`, `json_verbatim(text)`, `json_decode()`, `json_encode()`, `schema_validate()`, `block_text()`, `msg_text()`; P02: `registry_diagnostic(source, event, class, message)`, `registry_get(kind, name, session = NULL)` (a session's rank-0 `provider` record), in tests `gptr_provider()`, `registry_add()`, `registry_remove()`.
- P05: `model_resolve()`, `model_default(role = c("chat", "small", "system1"))`, `adapter_get(api)` (`capabilities$request_params`), `project_messages(entries, leaf, target)`.
- Services: `prompt.freeze`, `request.build`, `router.call` (IC-69), with the 04 §7.0 fallbacks.
- Tasks 3-7: `session_append()`, `entry_custom()`, `entry_model_change()`, `session_set_model()`, `session_value_set()`, `run_emit()`, `tool_lookup()`, `tool_schema()`.

Produces:

- `run_freeze(run, input)` (the `prompt.freeze` service, else the fallback `freeze_fallback()` appending `gptr.frozen`; `session_start` collect results joined to the first user message), `session_start_reason(d)`.
- `run_target(run)` (a pending `ctx$set_model()` switch, then `router.call` for `router:` models, IC-69), `run_route(run, reason = "turn")` (`model_change` + `gptr.router` + `route` per switch), `run_model_resolve(ref, sid)` (P05's catalog, else the session's rank-0 provider spec of `model = <spec:provider>` narrowed to the named model and passed to `model_resolve()`, else the strict `gptr_error_unknown_model`).
- `run_build(run, target)` (`request.build` or `request_fallback()`), `run_request_params(run, target, params)` (patch chain limited to the adapter's declared fields), `images_elide(s, messages, target)` (`gptr.image_elision`, IC-67), `run_returns(run)` (`returns =` schema: designated value or a notice), `plugin_state_persist(s)` (`gptr.ext`), `run_estimator_update(run, msg)`, `context_tokens(s)`, `context_idle(s)`.

- [ ] **Step 1: Write the failing test**

S34 (the compaction entry shrinks the context estimate) is a store check that needs `context_tokens()`.

Append to `tests/testthat/test-agent-run.R`:

```r

# ---------------------------------------------------------------- request shaping

test_that("the fallback freeze appends gptr.frozen and emits session_start (reason new)", {
  local_without_services(c("prompt.freeze", "request.build", "prefix.guard", "context.first",
                           "context.turn"))
  local_tool("read", function(input, ctx) "x",
             parameters = list(type = "object", properties = list(path = list(type = "string"))))
  ev = local_events("session_start")
  s = test_session()
  run = test_run(s)
  input = run_freeze(run, list(msg_user("hi")))
  d = session_data(s)
  expect_identical(d$entries[[1L]]$custom_type, "gptr.frozen")
  expect_named(d$frozen, c("t0", "t1", "tools_json", "tool_names", "sections"))
  expect_identical(d$frozen$tool_names, "read")
  expect_match(d$frozen$tools_json, "\"input_schema\"", fixed = TRUE)
  expect_identical(ev(s)[[1L]]$reason, "new")
  expect_identical(input[[1L]]$content[[1L]]$text, "hi")
  n = length(d$entries)
  run_freeze(run, list(msg_user("again")))
  expect_length(d$entries, n)
})

test_that("session_start blocks join the first user message; the prompt.freeze service is used", {
  local_hook("session_start", function(event, ctx) {
    list(blocks = list(block_context("lab_notebook", "Experiment 12")))
  })
  got = new.env()
  local_service("prompt.freeze", function(s, opts) {
    got$opts = opts
    d = session_data(s)
    d$frozen = list(t0 = "T0", t1 = "T1", tools_json = "[]", tool_names = character(),
                    sections = frozen_sections_df(list()))
    invisible(d$frozen)
  })
  s = test_session()
  run = test_run(s)
  lead = block_context("environment", "Date: today")
  input = run_freeze(run, list(msg_user(list(lead, block_text("hi")))))
  kinds = vapply(input[[1L]]$content, function(b) b$kind %||% b$type, "")
  expect_identical(kinds, c("environment", "lab_notebook", "text"))
  expect_identical(session_data(s)$frozen$t0, "T0")
  expect_identical(got$opts$start$blocks[[1L]]$kind, "lab_notebook")
})

test_that("session_start reasons follow the session's origin", {
  expect_identical(session_start_reason(list(kind = "chat", entries = list())), "new")
  expect_identical(session_start_reason(list(kind = "child", entries = list())), "child")
  expect_identical(session_start_reason(list(kind = "replayed", entries = list())), "replay")
  expect_identical(session_start_reason(list(kind = "chat", entries = list(1), fork_of = NULL)),
                   "resume")
  expect_identical(session_start_reason(list(kind = "chat", fork_of = list(id = "s1"))), "fork")
})

test_that("run_target() resolves the model once and applies a pending ctx$set_model() switch", {
  local_fake_provider(list("x"))
  local_fake_provider(list("y"), name = "other")
  s = test_session()
  run = test_run(s)
  expect_identical(run_target(run)$ref, "fake/fake-1")
  run$pending_model = list(ref = "other/other-1", thinking = "high", reason = "plugin")
  rec = run_target(run)
  expect_identical(rec$ref, "other/other-1")
  expect_identical(rec$thinking, "high")
  expect_identical(s$model, "other/other-1")
  d = session_data(s)
  expect_identical(d$entries[[length(d$entries)]]$gptr$reason, "plugin")
})

test_that("run_target() resolves a provider registered for the session only (model = <spec>)", {
  s = test_session()
  d = session_data(s)
  spec = gptr_provider("loc", api = "fake", models = list(list(id = "m0"), list(id = "m1")),
                       offline = TRUE)
  id = registry_add(spec, source = "session", rank = 0L, session = d$id)
  withr::defer(registry_remove(id))
  expect_null(model_resolve("loc/m1", strict = FALSE))
  d$model = "loc/m1"
  run = test_run(s)
  rec = run_target(run)
  expect_identical(c(rec$provider, rec$id, rec$ref), c("loc", "m1", "loc/m1"))
  d$model = "loc/absent"
  expect_error(run_target(run), class = "gptr_error_unknown_model")
})

test_that("a router session asks router.call before each request and records each switch (IC-69)", {
  local_fake_provider(list("x"))
  calls = new.env()
  calls$reasons = character()
  local_service("router.call", function(s, reason) {
    calls$reasons = c(calls$reasons, reason)
    list(model = "fake/fake-1", thinking = NULL, state = list(k = 1))
  })
  ev = local_events("route")
  s = session_new("router:cheapest", "auto", home = new.env())
  run = test_run(s)
  expect_identical(run_target(run)$ref, "fake/fake-1")
  expect_identical(run_target(run)$ref, "fake/fake-1")
  expect_identical(calls$reasons, c("turn", "turn"))
  types = vapply(session_data(s)$entries, function(e) e$custom_type %||% e$type, "")
  expect_identical(types, c("model_change", "gptr.router"))
  router = session_data(s)$entries[[2L]]$data
  expect_identical(router$router, "cheapest")
  expect_identical(router$state, list(k = 1))
  expect_length(ev(s), 1L)
})

test_that("a failing router falls back to the default model with a diagnostic", {
  local_fake_provider(list("x"))
  local_service("router.call", function(s, reason) stop("router crashed"))
  testthat::local_mocked_bindings(model_default = function(role = "chat") "fake/fake-1")
  s = session_new("router:cheapest", "auto", home = new.env())
  expect_identical(run_route(test_run(s), "turn")$ref, "fake/fake-1")
})

test_that("the fallback request projects the transcript and carries the frozen tools", {
  local_without_services(c("prompt.freeze", "request.build", "prefix.guard", "context.first",
                           "context.turn"))
  local_fake_provider(list("x"))
  local_tool("read", function(input, ctx) "x")
  s = test_session()
  run = test_run(s, list(returns = list(type = "object")))
  freeze_fallback(s)
  session_append(s, entry_message(msg_user("What is in a.R?")))
  req = run_build(run, run_target(run))
  ctx = req$context
  expect_named(ctx$system, c("t0", "t1"))
  expect_s3_class(ctx$tools_json, "json")
  expect_identical(vapply(ctx$tools, function(t) t$name, ""), "read")
  expect_identical(vapply(ctx$messages, function(m) m$role, ""), "user")
  expect_match(ctx$request_id, "^q[0-9a-f]{12}$")
  expect_identical(ctx$params$returns, list(type = "object"))
  expect_gt(req$tokens_est, 0)
  expect_true(all(c("tools", "transcript") %in% names(req$components)))
})

test_that("request_params handlers patch only the adapter's declared fields (IC-69)", {
  testthat::local_mocked_bindings(adapter_get = function(api) {
    list(api = api, capabilities = list(request_params = "service_tier"))
  })
  local_hook("request_params", function(event, ctx) {
    list(params = list(service_tier = "priority", max_tokens = 5L))
  })
  run = test_run(test_session())
  out = run_request_params(run, list(api = "fake", provider = "fake", ref = "fake/fake-1"),
                           list(max_tokens = 100L, service_tier = "auto"))
  expect_identical(out$service_tier, "priority")
  expect_identical(out$max_tokens, 100L)
})

test_that("older images are elided above the model's image limit, once (IC-67)", {
  s = test_session()
  img = function(k) block_image(strrep(as.character(k), 40))
  msgs = list(msg_user(list(img(1), img(2), img(3), block_text("look"))))
  out = images_elide(s, msgs, list(max_images = 2))
  expect_match(out[[1L]]$content[[1L]]$text, "^\\[image omitted: gptr\\$plot\\(")
  expect_identical(out[[1L]]$content[[2L]]$type, "image")
  d = session_data(s)
  expect_identical(d$entries[[length(d$entries)]]$custom_type, "gptr.image_elision")
  n = length(d$entries)
  again = images_elide(s, msgs, list(max_images = 2))
  expect_length(d$entries, n)
  expect_match(again[[1L]]$content[[1L]]$text, "image omitted", fixed = TRUE)
})

test_that("returns = <schema> designates the parsed final answer; a mismatch is a notice", {
  s = test_session()
  run = test_run(s, list(returns = list(type = "object", required = I("n"),
                                        properties = list(n = list(type = "integer")))))
  d = session_data(s)
  d$last_text = "{\"n\": 32}"
  run_returns(run)
  expect_identical(s$value$n, 32L)
  d$last_text = "no JSON here"
  withr::local_options(gptr.quiet = FALSE)
  expect_message(run_returns(run), class = "gptr_message_notice")
})

test_that("JSON-able plugin state is persisted as a gptr.ext entry when it changed", {
  s = test_session()
  st = new.env()
  st$count = 1L
  assign("panel", st, envir = session_live(s)$ext)
  plugin_state_persist(s)
  plugin_state_persist(s)
  ext = Filter(function(e) identical(e$custom_type, "gptr.ext"), session_data(s)$entries)
  expect_length(ext, 1L)
  expect_identical(ext[[1L]]$data, list(plugin = "panel", state = list(count = 1L)))
  expect_identical(s$ext$panel$count, 1L)
})

test_that("the estimator multiplier follows reported usage (03 section 12.5)", {
  s = test_session()
  run = test_run(s)
  run$model = list(provider = "anthropic")
  run$tokens_est = 1000
  run_estimator_update(run, list(usage = usage_new(input = 1500, output = 10)))
  st = session_data(s)$estimator
  expect_gt(st$m, 1)
  expect_identical(st$n, 1L)
})

test_that("context_tokens() is the last reported total plus the multiplier times new content", {
  s = test_session()
  session_append(s, entry_message(msg_user("q")))
  session_append(s, entry_message(msg_assistant("a", api = "fake", provider = "fake",
                                                model = "fake-1",
                                                usage = usage_new(input = 500, output = 20))))
  expect_equal(context_tokens(s), 520)
  session_append(s, entry_message(msg_user(strrep("x", 400))))
  expect_equal(context_tokens(s), 520 + est_tokens(strrep("x", 400), "prose"))
  expect_gte(context_idle(s), 0)
})
```

Append to `tests/testthat/test-session-store.R`:

```r

test_that(oracle_title(store_recs, "S34"), {
  s = test_session()
  session_append(s, entry_message(msg_user(strrep("long question ", 200))))
  session_append(s, entry_message(msg_assistant("a", api = "fake", provider = "fake",
                                                model = "fake-1",
                                                usage = usage_new(input = 5000, output = 20))))
  before = context_tokens(s)
  session_append(s, list(type = "compaction", summary = "short", first_kept_entry_id = NULL,
                         tokens_before = before,
                         gptr = list(blocks = list(block_context("checkpoint", "short summary")),
                                     state = list(), n = 1L)))
  expect_lt(context_tokens(s), before)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(agent-run|session-store)$")'`

Expected: `[ FAIL 15 | WARN 0 | SKIP 0 | PASS 130 ]`, with errors such as ``Error in `run_freeze(run, list(msg_user("hi")))`: could not find function "run_freeze"``.

- [ ] **Step 3: Write the implementation**

The fallbacks make every request possible before P07 exists: an empty T0/T1 and the frozen direct tools' JSON, the prompt alone as the first message, the projected transcript as the request, no prefix guard, no compaction.

Append to `R/agent-run.R`:

```r
# ---------------------------------------------------------------------------- freeze and input

#' Freeze the prompt at the first run
#'
#' Emits `session_start` (collect), then calls the `prompt.freeze` service (P07) or the documented
#' fallback (empty T0/T1 and the core tools' JSON, 04 section 7.0); blocks returned by
#' `session_start` handlers join the first user message.
#' @return The input messages, with the collected blocks inserted.
#' @noRd
run_freeze = function(run, input) {
  s = run$shell
  d = session_data(s)
  if (length(d$frozen)) return(input)
  collected = run_emit(run, "session_start", reason = session_start_reason(d))
  if (ext_service_has("prompt.freeze")) {
    # the run options P07's prompt_compose() reads (`preset`, `tools`, `doc`, `system`, `call`),
    # plus `start` (the merged session_start result), `interactive` and `refreeze` (IC-52)
    fopts = run$opts
    fopts$start = collected
    fopts$interactive = fopts$interactive %||% isTRUE(fopts$safety$can_prompt)
    fopts$refreeze = isTRUE(d$refreeze)
    fr = ext_service_get("prompt.freeze")(s, fopts)
    if (!length(d$frozen)) d$frozen = fr
  } else {
    freeze_fallback(s)
  }
  d$refreeze = FALSE
  blocks = if (is.list(collected)) collected$blocks else NULL
  if (length(blocks) && !is.null(input)) input = input_insert_blocks(input, blocks)
  input
}

#' The `session_start` reason of a session's first freeze
#' @noRd
session_start_reason = function(d) {
  if (!is.null(d$fork_of)) return("fork")
  if (identical(d$kind, "child")) return("child")
  if (identical(d$kind, "replayed")) return("replay")
  if (length(d$entries)) return("resume")
  "new"
}

#' The fallback freeze used before P07 is loaded: empty T0/T1 and the four core tools' JSON
#' @noRd
freeze_fallback = function(s) {
  d = session_data(s)
  core = c("read", "r", "edit", "write")
  specs = lapply(core, function(n) tool_lookup(n, d$id))
  keep = !vapply(specs, is.null, NA)
  arr = lapply(specs[keep], function(t) {
    list(name = t$name, description = t$description, input_schema = tool_schema(t) %||% json_obj())
  })
  fr = list(t0 = "", t1 = "", tools_json = json_encode(arr), tool_names = core[keep],
            sections = frozen_sections_df(list()))
  d$frozen = fr
  session_append(s, entry_custom("gptr.frozen",
                                 list(preset = d$preset, t0 = "", t1 = "",
                                      toolsJson = fr$tools_json,
                                      toolNames = I(fr$tool_names), sections = list(),
                                      model = d$model)))
  invisible(fr)
}

#' Insert context blocks contributed by session_start handlers into the first user message,
#' after its leading context blocks and before its text
#' @noRd
input_insert_blocks = function(input, blocks) {
  for (i in seq_along(input)) {
    m = input[[i]]
    if (!identical(m$role, "user")) next
    content = m$content
    pos = which(!vapply(content, function(b) identical(b$type, "context"), NA))
    at = if (length(pos)) pos[[1L]] - 1L else length(content)
    m$content = append(content, blocks, after = at)
    input[[i]] = m
    break
  }
  input
}

# ---------------------------------------------------------------------------- the next request

#' The model record of the next request: a pending `ctx$set_model()` switch first, then the router
#' (`router.call`, IC-69) for `router:` models, else the session's model
#' @noRd
run_target = function(run) {
  s = run$shell
  d = session_data(s)
  pm = run$pending_model
  if (!is.null(pm)) {
    run$pending_model = NULL
    session_set_model(s, pm$ref, pm$reason)
    if (!is.null(pm$thinking)) d$thinking = pm$thinking
  }
  if (startsWith(d$model, "router:")) return(run_route(run, "turn"))
  if (is.null(run$model) || !identical(run$model_key, d$model)) {
    run$model = run_model_resolve(d$model, d$id)
    run$model_key = d$model
  }
  if (!is.null(d$thinking)) run$model$thinking = d$thinking
  run$model
}

#' Resolve a model reference for a session: P05's catalog first, else a provider registered at
#' rank 0 for this session only (`model = <spec:provider>`, 04 section 6.1), which the catalog
#' does not list; P05's model_resolve() accepts that spec (its first model), so the spec is
#' narrowed to the declared model the reference names. Anything else is the strict, classed
#' `gptr_error_unknown_model` of model_resolve().
#' @noRd
run_model_resolve = function(ref, sid) {
  rec = model_resolve(ref, strict = FALSE)
  if (!is.null(rec)) return(rec)
  pos = regexpr(":[^:/]*$", ref)
  base = if (pos > 0L) substr(ref, 1L, pos - 1L) else ref
  thinking = if (pos > 0L) substring(ref, pos + 1L) else NULL
  if (grepl("/", base, fixed = TRUE)) {
    pid = sub("/.*$", "", base)
    mid = sub("^[^/]*/", "", base)
    pr = tryCatch(registry_get("provider", pid, session = sid), error = function(e) NULL)
    model_id = function(m) as.character(m[["id"]] %||% sub("^[^/]*/", "", m[["ref"]] %||% ""))
    keep = if (inherits(pr, "gptr_provider")) {
      Filter(function(m) identical(model_id(m), mid), pr$models %||% list())
    } else {
      list()
    }
    if (length(keep)) {
      pr$models = keep[1L]
      rec = model_resolve(pr)
      if (!is.null(thinking) && thinking %in% rec$thinking_levels) rec$thinking = thinking
      return(rec)
    }
  }
  model_resolve(ref)
}

#' Ask the session's router for the model (IC-69); a failing router falls back to the default
#' model with a diagnostic. Each switch appends `model_change` and `gptr.router`, and emits `route`.
#' @param reason `"turn"` or `"compaction"`.
#' @noRd
run_route = function(run, reason = "turn") {
  s = run$shell
  d = session_data(s)
  router = sub("^router:", "", d$model)
  res = tryCatch(ext_service_get("router.call")(s, reason), error = function(e) {
    registry_diagnostic("session", "router", "router_fallback",
                        paste0("router ", router, " failed: ", conditionMessage(e)))
    NULL
  })
  ref = if (is.list(res)) res$model else res
  if (is.null(ref)) ref = model_default("chat")
  if (is.null(ref)) {
    gptr_abort(paste0("router ", router, " gave no model and no default model is configured"),
               "unknown_model", ref = d$model, suggestions = character())
  }
  rec = run_model_resolve(ref, d$id)
  if (is.list(res) && !is.null(res$thinking)) rec$thinking = res$thinking
  if (!identical(run$routed, rec$ref)) {
    session_append(s, entry_model_change(rec$ref, rec$thinking, "router"))
    session_append(s, entry_custom("gptr.router",
                                   drop_null(list(router = router,
                                                  state = if (is.list(res)) res$state,
                                                  model = rec$ref, reason = reason))))
    run_emit(run, "route", route = "router", router = router, model = rec$ref, reason = reason)
    run$routed = rec$ref
  }
  run$model = rec
  rec
}

#' The request for a target: the `request.build` service (P07) or the fallback, then image elision
#' @return `list(context, view, tokens_est, components)`.
#' @noRd
run_build = function(run, target) {
  s = run$shell
  req = if (ext_service_has("request.build")) {
    ext_service_get("request.build")(s, target, NULL)
  } else {
    request_fallback(run, target)
  }
  req$context$request_id = req$context$request_id %||% id_new("q", 12L)
  req$context$session_id = req$context$session_id %||% session_data(s)$id
  req$context$messages = images_elide(s, req$context$messages, target)
  req$tokens_est = req$tokens_est %||% 0
  req
}

#' The fallback request before P07 is loaded: the projected messages and the frozen tools
#' @noRd
request_fallback = function(run, target) {
  s = run$shell
  d = session_data(s)
  fr = d$frozen
  msgs = project_messages(d$entries, d$leaf, target)
  tools = lapply(fr$tool_names %||% character(), function(n) tool_lookup(n, d$id))
  tools = Filter(Negate(is.null), tools)
  transcript = sum(vapply(msgs, function(m) est_tokens(msg_text(m), "prose"), 1))
  static = est_tokens(paste(fr$t0 %||% "", fr$t1 %||% "", fr$tools_json %||% ""), "prose")
  max_out = suppressWarnings(as.numeric(target$max_output %||% NA))
  context = list(system = list(t0 = fr$t0 %||% "", t1 = fr$t1 %||% ""),
                 tools_json = json_verbatim(fr$tools_json %||% "[]"), tools = tools,
                 messages = msgs,
                 cache_plan = list(anchors = character(), tail_ttl = "5m", key = ""),
                 params = list(max_tokens = if (is.finite(max_out)) as.integer(max_out) else 8192L,
                               thinking = target$thinking, effort = NULL, tool_choice = "auto",
                               returns = run$opts$returns, temperature = NULL),
                 session_id = d$id, request_id = id_new("q", 12L))
  list(context = context, view = NULL, tokens_est = static + transcript,
       components = list(tools = static, transcript = transcript))
}

#' The `request_params` patch chain over the adapter's declared non-prefix fields (IC-69)
#' @noRd
run_request_params = function(run, target, params) {
  adapter = tryCatch(adapter_get(target$api), error = function(e) NULL)
  fields = adapter$capabilities$request_params %||% character()
  if (!length(fields)) return(params)
  res = run_emit(run, "request_params", provider = target$provider, model = target$ref,
                 params = params[intersect(names(params), fields)])
  patched = if (is.list(res)) res$params else NULL
  if (!is.list(patched)) return(params)
  bad = setdiff(names(patched), fields)
  if (length(bad)) {
    registry_diagnostic("session", "request_params", "ignored_patch",
                        paste0("request_params handlers may not patch: ",
                               paste(bad, collapse = ", ")))
  }
  for (f in intersect(names(patched), fields)) params[f] = list(patched[[f]])
  params
}

#' Older images projected as omitted when a request exceeds the model's image count or 32 MB (IC-67)
#'
#' Newly elided images are recorded by one appended `gptr.image_elision` entry (one stated cache
#' break); images elided earlier on the path stay elided.
#' @noRd
images_elide = function(s, messages, target) {
  info = images_scan(messages)
  if (!nrow(info)) return(messages)
  d = session_data(s)
  max_n = suppressWarnings(as.numeric(target$max_images %||% NA))
  keep = !(info$id %in% elided_image_ids(d))
  over = function() (is.finite(max_n) && sum(keep) > max_n) || sum(info$bytes[keep]) > 32 * 1024^2
  new = character()
  while (any(keep) && over()) {
    i = which(keep)[[1L]]
    keep[i] = FALSE
    new = c(new, info$id[i])
  }
  if (length(new)) session_append(s, entry_custom("gptr.image_elision",
                                                  list(images = I(unique(new)))))
  for (r in which(!keep)) {
    messages[[info$msg[r]]]$content[[info$block[r]]] =
      block_text(paste0("[image omitted: gptr$plot(\"", info$id[r], "\")]"))
  }
  messages
}

#' The image blocks of a message list: position, id (8 hex of the data's sha256) and bytes
#' @noRd
images_scan = function(messages) {
  rows = list()
  for (i in seq_along(messages)) {
    content = messages[[i]]$content %||% list()
    for (j in seq_along(content)) {
      b = content[[j]]
      if (!identical(b$type, "image")) next
      rows[[length(rows) + 1L]] = data.frame(msg = i, block = j,
                                             id = substr(hash_sha256(b$data), 1L, 8L),
                                             bytes = nchar(b$data, type = "bytes") * 3 / 4,
                                             stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) {
    return(data.frame(msg = integer(), block = integer(), id = character(), bytes = numeric(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' Image ids already elided on the session's path
#' @noRd
elided_image_ids = function(d) {
  ids = character()
  for (e in entries_path(d)) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.image_elision")) {
      ids = c(ids, as.character(unlist(e$data$images)))
    }
  }
  ids
}

# ---------------------------------------------------------------------------- answers and state

#' Structured final answers (`opts$returns`, INFRA-25): the final text parsed, validated and
#' designated as the run's value; a mismatch is a notice
#' @noRd
run_returns = function(run) {
  schema = run$opts$returns
  if (is.null(schema)) return(invisible(NULL))
  s = run$shell
  txt = session_data(s)$last_text
  val = if (is.na(txt)) NULL else tryCatch(json_decode(txt), error = function(e) NULL)
  chk = if (is.null(val)) NULL else schema_validate(schema, val)
  if (is.null(chk) || !isTRUE(chk$ok)) {
    gptr_inform(paste0("the final answer does not match `returns`",
                       if (is.null(chk)) " (not JSON)" else
                         paste0(": ", paste(chk$errors, collapse = "; "))),
                "notice")
    return(invisible(NULL))
  }
  session_value_set(s, "returns", chk$input)
  invisible(NULL)
}

#' Persist JSON-able per-plugin state (`ctx$state()`) as gptr.ext entries when it changed
#' @noRd
plugin_state_persist = function(s) {
  live = session_live(s)
  if (is.null(live)) return(invisible(NULL))
  d = session_data(s)
  for (plugin in ls(live$ext)) {
    vals = as.list(get(plugin, envir = live$ext), sorted = TRUE)
    ok = tryCatch({
      json_encode(vals)
      TRUE
    }, error = function(e) FALSE)
    if (!ok || !length(vals) || identical(d$ext[[plugin]], vals)) next
    ext = d$ext
    ext[[plugin]] = vals
    d$ext = ext
    session_append(s, entry_custom("gptr.ext", list(plugin = plugin, state = vals)))
  }
  invisible(NULL)
}

#' Update the session's estimator multiplier from provider-reported usage (03 section 12.5)
#' @noRd
run_estimator_update = function(run, msg) {
  d = session_data(run$shell)
  u = msg$usage
  reported = sum(unlist(u[c("input", "cache_read", "cache_write_5m", "cache_write_1h")]))
  est = run$tokens_est %||% 0
  if (isTRUE(u$estimated) || !(reported > 0) || !(est > 0)) return(invisible(NULL))
  prior = switch(run$model$provider %||% "", anthropic = 1.35, google = 1.10, 1.00)
  state = d$estimator %||% list(m = prior, n = 0L)
  d$estimator = est_multiplier(state, estimated = est, reported = reported, prior = prior)
  invisible(NULL)
}

#' Context size projection: the last reported total (or the latest compaction's blocks) plus the
#' multiplier times the estimate of the content after it (03 section 12.5)
#' @noRd
context_tokens = function(s) {
  d = session_data(s)
  path = entries_path(d)
  base = 0
  idx = 0L
  for (i in rev(seq_along(path))) {
    e = path[[i]]
    if (identical(e$type, "compaction")) {
      blocks = e$gptr$blocks %||% list()
      base = sum(vapply(blocks, function(b) est_tokens(b$text %||% "", "prose"), 1))
      idx = i
      break
    }
    m = e$message
    if (identical(e$type, "message") && identical(m$role, "assistant") &&
        !(m$stop_reason %||% "stop") %in% c("error", "aborted") && !is.null(m$usage$total)) {
      base = m$usage$total
      idx = i
      break
    }
  }
  trailing = 0
  for (i in seq_along(path)) {
    is_msg = path[[i]]$type %in% c("message", "custom_message") && !is.null(path[[i]]$message)
    if (i > idx && is_msg) {
      trailing = trailing + est_tokens(msg_text(path[[i]]$message), "prose")
    }
  }
  base + (d$estimator$m %||% 1) * trailing
}

#' Seconds since the last assistant message on the path (the cold rule of compact.should)
#' @noRd
context_idle = function(s) {
  d = session_data(s)
  for (e in rev(entries_path(d))) {
    if (identical(e$type, "message") && identical(e$message$role, "assistant")) {
      return(max(0, as.numeric(Sys.time()) - (e$message$timestamp %||% 0) / 1000))
    }
  }
  0
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(agent-run|session-store)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 186 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/agent-run.R tests/testthat/test-agent-run.R tests/testthat/test-session-store.R
git commit -m "feat(agent): add request shaping (freeze, routers, params, image elision, returns)"
```

---

### Task 10: The run engine

**Files:**

- Modify: `R/agent-run.R`
- Create: `tests/testthat/fixtures/oracles/report02/loop.json`
- Test: `tests/testthat/test-agent-loop.R`
- Test: `tests/testthat/test-agent-run.R`
- Test: `tests/testthat/test-agent-dispatch.R`
- Test: `tests/testthat/test-session-budget.R`
- Test: `tests/testthat/test-session-store.R`

**Interfaces:**

Consumes:

- P01: `acc_new()`, `msg_assistant()`, `msg_text()`, `est_tokens()`, `gptr_opt()`, `id_new()`; P03: `redact_stream(profile = "stream")`.
- P04 (04 §8.2): `reactor_task(fn, run = NULL)`, `reactor_timer(at, fn, run = NULL)`, `reactor_enqueue_tool(run, fn)`, `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`, `reactor_cancel(ids)`, `reactor_run_add(run)`, `reactor_run_remove(run)`, `reactor_now()`.
- P05: `provider_stream(model, context, opts, emit, done, run = NULL)`, `usage_new(...)`, `usage_row(msg, session, agent, parent_id, started, seconds, multiplier)`.
- Services: `console.interrupt_policy` (else abort-only), `compact.should`, `compact.run`, `prefix.guard`, `mcp.dispatch_local`.
- Tasks 1-9: the loop, `dispatch_tools()`, `call_record()`, `perm_check()`, `tool_result_message()`, `budget_check()`, `budget_near()`, `usage_add()`, `ledger_add()`, `run_new()`, `run_freeze()`, `run_target()`, `run_build()`, the recovery classifiers, `session_attach()`, `store_heartbeat()`, `last_set()`.

Produces:

- `session_run(s, input, opts = list())` -> `s` invisibly (settles on the reactor under the interrupt policy; raises nothing itself), `run_start(s, input, opts = list())` -> a registered `gptr_run`, `run_wait(runs, timeout = Inf)` -> `invisible(lgl(1))`, `run_abort(run, reason = "user")`.
- Settlement `run_settle(run, reason)`: statuses `idle`, `blocked`, `budget`, `max_turns`, `error`, `aborted`; the stored unsignalled condition in `.d$condition` and in `run$signal$condition` (where P08's `gateway_signal()` reads it); the run's `home`, `scratch`, `outer` and `opts$call` bindings reset; its reactor task, timers, transfers and queued FIFO tool job cancelled; `agent_end`. A failure before the run is wired (freeze, first append) settles it with status `error` and re-signals the condition, so the session never stays `running`.
- Recovery on the reactor: two transient retries (2 s, 4 s) with `retry_start`/`retry_end`, one compact-and-retry via `compact.run`, then `gptr_error_context_overflow`; budgets `gptr.budget` + `budget_exceeded` (interactive extension through `ask_human`); `gptr.max_nested_calls` (`run_count_nested()`); the `prefix.guard` service's `gptr_error_internal` under `gptr.check_prefix = "error"` (04 §3.1) ends the run with status `error`, any other failure of the guard is a diagnostic.

- [ ] **Step 1: Write the failing test**

`loop.json` holds report 02's 24 loop checks. This task adds the checks that need the engine: L01-L24 (with the coverage test for the loop group), R19-R26 and the recovery coverage test, the S25-S29, S33, S35, S36 and S38-S42 store checks, the INFRA-09 `length` stop, the NS-12 blocked ask, and the budget stops.

Create `tests/testthat/fixtures/oracles/report02/loop.json`:

```json
[
 {"id":"L01","source":"02 5.1 A","check":"transcript roles","status":"adapted","gptr":"the active path holds user then assistant (the system prompt is frozen T0/T1, not a transcript message)"},
 {"id":"L02","source":"02 5.1 A","check":"assistant text reassembled from deltas","status":"port","gptr":"$text equals the scripted answer streamed in several text deltas"},
 {"id":"L03","source":"02 5.1 A","check":"reason == stop","status":"port","gptr":"the run settles with status idle"},
 {"id":"L04","source":"02 5.1 B","check":"4 tool results","status":"port","gptr":"four tool calls give four tool_result messages"},
 {"id":"L05","source":"02 5.1 B","check":"add(2,'3') coerced + executed = 5","status":"adapted","gptr":"numbers execute (add(2, 3) = 5); a string for a number is a validation error, gptr coerces only explicitly (INFRA-09)"},
 {"id":"L06","source":"02 5.1 B","check":"thrown error -> isError result with message","status":"port","gptr":"an R error inside execute becomes an is_error result carrying the message"},
 {"id":"L07","source":"02 5.1 B","check":"unknown tool","status":"port","gptr":"an unknown tool gives the result text 'Tool nope not found'"},
 {"id":"L08","source":"02 5.1 B","check":"validation failure","status":"adapted","gptr":"a missing required argument gives 'Invalid arguments for add: ...' naming it, and the tool is not called"},
 {"id":"L09","source":"02 5.1 B","check":"exactly 2 provider requests","status":"port","gptr":"one request for the calls, one after the results"},
 {"id":"L10","source":"02 5.1 B","check":"2nd request carries tool results in source order","status":"port","gptr":"the second request ends with the four tool results in call order"},
 {"id":"L11","source":"02 5.1 C","check":"order: toolResult -> steer1 -> asst -> steer2 -> asst -> followup -> asst","status":"adapted","gptr":"user-source steers arrive as operator relays after the complete tool result, one per request; the follow-up arrives last as a user message (IC-55)"},
 {"id":"L12","source":"02 5.1 C","check":"one-at-a-time delivery, follow-up last","status":"port","gptr":"each relay carries one steer; the follow-up text is in the last user message"},
 {"id":"L13","source":"02 5.1 C2","check":"mode=all injects both steering messages before one LLM call","status":"adapted","gptr":"gptr has no 'all' mode: two queued steers take two requests, each ending with one relay"},
 {"id":"L14","source":"02 5.1 D","check":"truncated tool call not executed","status":"port","gptr":"a length stop fails the call unrun with 'Tool call not executed: the response stopped (length) before the call was complete.'"},
 {"id":"L15","source":"02 5.1 E","check":"blocked call -> error result with reason","status":"adapted","gptr":"a tool_call hook returning block gives 'Tool execution was blocked: <reason>'"},
 {"id":"L16","source":"02 5.1 E","check":"terminate=TRUE on every result stops without another LLM call","status":"port","gptr":"a result with terminate = TRUE ends the run after its batch"},
 {"id":"L17","source":"02 5.1 E","check":"after_tool_call replaces content","status":"adapted","gptr":"a tool_result hook patches the content the model sees"},
 {"id":"L18","source":"02 5.1 F","check":"run ends with aborted assistant message","status":"adapted","gptr":"an interrupt inside a tool aborts the run (status aborted) and makes no further request"},
 {"id":"L19","source":"02 5.1 F","check":"remaining tool calls skipped after abort","status":"port","gptr":"only the interrupted call has a result, 'Interrupted after <s> s; side effects may have occurred.'"},
 {"id":"L20","source":"02 5.1 F","check":"agent is idle again","status":"adapted","gptr":"the session keeps no run after the abort and continues with the next run"},
 {"id":"L21","source":"02 5.1 G","check":"provider error ends the run","status":"adapted","gptr":"a non-transient provider error settles with status error and a stored gptr_error_provider"},
 {"id":"L22","source":"02 5.1 H","check":"max_turns guard","status":"port","gptr":"max_turns = 3 stops after three requests with status max_turns (INFRA-12)"},
 {"id":"L23","source":"02 5.1 I","check":"a failing event handler does not break the loop","status":"port","gptr":"a throwing message_end listener becomes a diagnostic; the run settles idle"},
 {"id":"L24","source":"02 5.1 J","check":"re-entrancy guard","status":"adapted","gptr":"run_start() on a running session signals gptr_error_busy"}
]
```

Append to `tests/testthat/test-agent-loop.R`:

```r

# ---------------------------------------------------------------- report 02 section 5.1 (24 checks)

loop_recs = oracle("loop")
add_tool = function(.env = parent.frame()) {
  local_tool("add", function(input, ctx) as.character(input$a + input$b),
             parameters = num_schema(a = "number", b = "number"), .env = .env)
}

test_that(oracle_title(loop_recs, "L01"), {
  local_permissive()
  local_fake_provider(list("Hello from gptr!"))
  s = test_session()
  run_text(s, "Hi")
  expect_identical(roles(s), c("user", "assistant"))
})

test_that(oracle_title(loop_recs, "L02"), {
  local_permissive()
  local_fake_provider(list(fake_text("Hello from gptr! A longer answer.", chunk = 8L)))
  updates = local_events("message_update")
  s = test_session()
  run_text(s, "Hi")
  expect_identical(s$text, "Hello from gptr! A longer answer.")
  expect_gt(length(updates(s)), 1L)
  expect_identical(paste(vapply(updates(s), function(e) e$delta, ""), collapse = ""), s$text)
})

test_that(oracle_title(loop_recs, "L03"), {
  local_permissive()
  local_fake_provider(list("Hello"))
  s = test_session()
  run_text(s, "Hi")
  expect_identical(s$status, "idle")
})

test_that(oracle_title(loop_recs, "L04"), {
  local_permissive()
  add_tool()
  local_tool("boom", function(input, ctx) stop("kaboom: file not found"))
  local_fake_provider(list(fake_tools(list(name = "add", input = list(a = 2, b = 3)),
                                      list(name = "boom", input = json_obj()),
                                      list(name = "nope", input = json_obj()),
                                      list(name = "add", input = list(a = 1))),
                           "Done: 5"))
  s = test_session()
  run_text(s, "compute")
  expect_length(tool_results(s), 4L)
})

test_that(oracle_title(loop_recs, "L05"), {
  local_permissive()
  add_tool()
  local_fake_provider(list(fake_tools(list(name = "add", input = list(a = 2, b = 3)),
                                      list(name = "add", input = list(a = 2, b = "3"))),
                           "ok"))
  s = test_session()
  run_text(s, "compute")
  tr = tool_results(s)
  expect_identical(msg_text(tr[[1L]]), "5")
  expect_false(tr[[1L]]$is_error)
  expect_true(tr[[2L]]$is_error)
  expect_match(msg_text(tr[[2L]]), "^Invalid arguments for add")
})

test_that(oracle_title(loop_recs, "L06"), {
  local_permissive()
  local_tool("boom", function(input, ctx) stop("kaboom: file not found"))
  local_fake_provider(list(fake_tool("boom"), "ok"))
  s = test_session()
  run_text(s, "go")
  tr = tool_results(s)[[1L]]
  expect_true(tr$is_error)
  expect_match(msg_text(tr), "kaboom: file not found", fixed = TRUE)
})

test_that(oracle_title(loop_recs, "L07"), {
  local_permissive()
  local_fake_provider(list(fake_tool("nope"), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_identical(msg_text(tool_results(s)[[1L]]), "Tool nope not found")
})

test_that(oracle_title(loop_recs, "L08"), {
  local_permissive()
  ran = new.env()
  ran$yes = FALSE
  local_tool("add", function(input, ctx) {
    ran$yes = TRUE
    "x"
  }, parameters = num_schema(a = "number", b = "number"))
  local_fake_provider(list(fake_tool("add", a = 1), "ok"))
  s = test_session()
  run_text(s, "go")
  tr = tool_results(s)[[1L]]
  expect_true(tr$is_error)
  expect_match(msg_text(tr), "^Invalid arguments for add: .*b")
  expect_false(ran$yes)
})

test_that(oracle_title(loop_recs, "L09"), {
  local_permissive()
  add_tool()
  fake = local_fake_provider(list(fake_tools(list(name = "add", input = list(a = 1, b = 2)),
                                             list(name = "add", input = list(a = 3, b = 4))),
                                  "done"))
  run_text(test_session(), "go")
  expect_length(fake_requests(fake), 2L)
})

test_that(oracle_title(loop_recs, "L10"), {
  local_permissive()
  add_tool()
  fake = local_fake_provider(list(fake_tools(list(name = "add", input = list(a = 1, b = 1)),
                                             list(name = "add", input = list(a = 1, b = 2)),
                                             list(name = "add", input = list(a = 1, b = 3)),
                                             list(name = "add", input = list(a = 1, b = 4))),
                                  "done"))
  run_text(test_session(), "go")
  req = fake_requests(fake)[[2L]]
  expect_identical(req_roles(req), c("user", "assistant", rep("tool_result", 4L)))
  expect_identical(vapply(req$messages[3:6], msg_text, ""), c("2", "3", "4", "5"))
})

steer_during_slow = function(box, .env = parent.frame()) {
  local_tool("slow", function(input, ctx) "slow done", .env = .env)
  local_hook("tool_execution_start", function(event, ctx) {
    if (identical(event$tool_name, "slow")) {
      session_enqueue(box$s, "STEER-1: actually use metric units", "steer", source = "pipe")
      session_enqueue(box$s, "STEER-2: and be brief", "steer", source = "pipe")
      session_enqueue(box$s, "FOLLOWUP: now summarise", "follow_up", source = "pipe")
    }
    NULL
  }, .env = .env)
}

test_that(oracle_title(loop_recs, "L11"), {
  local_permissive()
  box = new.env()
  steer_during_slow(box)
  local_fake_provider(list(fake_tool("slow"), "ack steer 1", "ack steer 2", "summary"))
  box$s = test_session()
  run_text(box$s, "go")
  expect_identical(roles(box$s), c("user", "assistant", "tool_result", "operator", "assistant",
                                   "operator", "assistant", "user", "assistant"))
})

test_that(oracle_title(loop_recs, "L12"), {
  local_permissive()
  box = new.env()
  steer_during_slow(box)
  local_fake_provider(list(fake_tool("slow"), "ack steer 1", "ack steer 2", "summary"))
  box$s = test_session()
  run_text(box$s, "go")
  txt = vapply(box$s$messages, msg_text, "")
  expect_match(txt[[4L]], "STEER-1", fixed = TRUE)
  expect_match(txt[[6L]], "STEER-2", fixed = TRUE)
  expect_match(txt[[8L]], "FOLLOWUP", fixed = TRUE)
})

test_that(oracle_title(loop_recs, "L13"), {
  local_permissive()
  box = new.env()
  steer_during_slow(box)
  fake = local_fake_provider(list(fake_tool("slow"), "ack steer 1", "ack steer 2", "summary"))
  box$s = test_session()
  run_text(box$s, "go")
  reqs = fake_requests(fake)
  expect_length(reqs, 4L)
  last_role = vapply(reqs[2:3], function(r) r$messages[[length(r$messages)]]$role, "")
  expect_identical(last_role, c("operator", "operator"))
})

test_that(oracle_title(loop_recs, "L14"), {
  local_permissive()
  ran = new.env()
  ran$yes = FALSE
  local_tool("w", function(input, ctx) {
    ran$yes = TRUE
    "x"
  })
  local_fake_provider(list(c(fake_tool("w"), list(stop = "length")), "retry ok"))
  s = test_session()
  run_text(s, "go")
  tr = tool_results(s)[[1L]]
  expect_false(ran$yes)
  expect_true(tr$is_error)
  expect_identical(msg_text(tr), paste0("Tool call not executed: the response stopped (length) ",
                                        "before the call was complete."))
})

test_that(oracle_title(loop_recs, "L15"), {
  local_permissive()
  add_tool()
  local_hook("tool_call", function(event, ctx) {
    list(decision = "block", reason = "denied by permission mode")
  })
  local_fake_provider(list(fake_tool("add", a = 1, b = 1), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_identical(msg_text(tool_results(s)[[1L]]),
                   "Tool execution was blocked: denied by permission mode")
})

test_that(oracle_title(loop_recs, "L16"), {
  local_permissive()
  local_tool("stopper", function(input, ctx) {
    res = gptr_tool_result("final")
    res$terminate = TRUE
    res
  })
  fake = local_fake_provider(list(fake_tool("stopper"), "unused"))
  s = test_session()
  run_text(s, "go")
  expect_length(fake_requests(fake), 1L)
  expect_identical(s$status, "idle")
})

test_that(oracle_title(loop_recs, "L17"), {
  local_permissive()
  add_tool()
  local_hook("tool_result", function(event, ctx) {
    list(content = list(block_text(paste0("[audited] ", event$content[[1L]]$text))))
  })
  local_fake_provider(list(fake_tool("add", a = 1, b = 1), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_identical(msg_text(tool_results(s)[[1L]]), "[audited] 2")
})

interrupting_run = function(.env = parent.frame()) {
  add_tool(.env = .env)
  local_tool("spin", function(input, ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "not reached"
  }, .env = .env)
  fake = local_fake_provider(list(fake_tools(list(name = "spin", input = json_obj()),
                                             list(name = "add", input = list(a = 1, b = 1))),
                                  "after the interrupt"), .env = .env)
  s = test_session()
  res = tryCatch({
    run_text(s, "go")
    "returned"
  }, interrupt = function(cnd) "interrupted")
  list(s = s, res = res, fake = fake)
}

test_that(oracle_title(loop_recs, "L18"), {
  local_permissive()
  x = interrupting_run()
  expect_identical(x$res, "interrupted")
  expect_identical(x$s$status, "aborted")
  expect_length(fake_requests(x$fake), 1L)
})

test_that(oracle_title(loop_recs, "L19"), {
  local_permissive()
  x = interrupting_run()
  tr = tool_results(x$s)
  expect_length(tr, 1L)
  expect_match(msg_text(tr[[1L]]),
               "^Interrupted after [0-9.]+ s; side effects may have occurred[.]$")
})

test_that(oracle_title(loop_recs, "L20"), {
  local_permissive()
  x = interrupting_run()
  expect_null(session_live(x$s)$run)
  run_text(x$s, "continue")
  expect_identical(x$s$status, "idle")
  expect_identical(x$s$text, "after the interrupt")
  req = fake_requests(x$fake)[[2L]]
  ids = vapply(Filter(function(m) identical(m$role, "tool_result"), req$messages),
               function(m) m$tool_call_id, "")
  expect_length(ids, 2L)
})

test_that(oracle_title(loop_recs, "L21"), {
  local_permissive()
  local_fake_provider(list(fake_error("400 invalid request: bad parameter", status = 400L)))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "error")
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_provider")
  expect_match(conditionMessage(cnd), "bad parameter", fixed = TRUE)
  expect_identical(cnd$session, session_data(s)$id)
})

test_that(oracle_title(loop_recs, "L22"), {
  local_permissive()
  add_tool()
  fake = local_fake_provider(list(fake_tool("add", a = 1, b = 1)))
  s = test_session()
  run_text(s, "loop forever", list(max_turns = 3L))
  expect_identical(s$status, "max_turns")
  expect_length(fake_requests(fake), 3L)
  expect_s3_class(session_data(s)$condition, "gptr_error_max_turns")
  expect_identical(session_data(s)$condition$max_turns, 3L)
})

test_that(oracle_title(loop_recs, "L23"), {
  local_permissive()
  local_hook("message_end", function(event, ctx) stop("listener bug"))
  local_fake_provider(list("fine"))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "idle")
  expect_identical(s$text, "fine")
})

test_that(oracle_title(loop_recs, "L24"), {
  local_permissive()
  box = new.env()
  local_tool("re", function(input, ctx) {
    box$err = tryCatch({
      run_start(box$s, msg_user("nested"))
      "no error"
    }, error = function(e) e)
    "ok"
  })
  local_fake_provider(list(fake_tool("re"), "x"))
  box$s = test_session()
  run_text(box$s, "go")
  expect_s3_class(box$err, "gptr_error_busy")
})

test_that("every report 02 loop check has a test", {
  expect_oracles_covered(loop_recs, "test-agent-loop.R")
})
```

Append to `tests/testthat/test-agent-run.R`:

```r

# ---------------------------------------------------------------- the run engine

test_that("session_run() returns the identical session; each run is one prompt turn", {
  local_permissive()
  local_fake_provider(list("one", "two"))
  s = test_session()
  expect_identical(session_run(s, msg_user("a")), s)
  expect_identical(s |> session_run(msg_user("b")), s)
  expect_identical(s$turns, 2L)
  expect_identical(s$text, "two")
  expect_identical(s$status, "idle")
})

test_that("run_start() is non-blocking; run_wait() settles; the run carries its contract fields", {
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  run = run_start(s, msg_user("go"))
  expect_identical(s$status, "running")
  expect_identical(session_live(s)$run, run)
  expect_true(run_wait(list(run), timeout = 30))
  expect_identical(run$status, "idle")
  expect_identical(run$turn, 1L)
  expect_identical(s$status, "idle")
  expect_null(session_live(s)$run)
  expect_identical(gptr_last(), s)
})

test_that("agent events are paired and ordered", {
  local_permissive()
  local_fake_provider(list("done"))
  ev = local_events(c("agent_start", "turn_start", "message_start", "message_end", "turn_end",
                      "agent_end"))
  s = test_session()
  run_text(s, "go")
  types = vapply(ev(s), function(e) e$type, "")
  expect_identical(types, c("agent_start", "turn_start", "message_start", "message_end",
                            "message_start", "message_end", "turn_end", "agent_end"))
  end = ev(s)[[length(ev(s))]]
  expect_identical(end$status, "idle")
  expect_identical(end$turns, 1L)
  expect_identical(nrow(end$usage), 1L)
})

test_that("turn_end carries the tool-result messages, never the tools' R values (R1)", {
  local_permissive()
  local_tool("val", function(input, ctx) gptr_tool_result("made", value = as.numeric(1:10)))
  ev = local_events("turn_end")
  local_fake_provider(list(fake_tool("val"), "done"))
  s = test_session()
  run_text(s, "go")
  res = ev(s)[[1L]]$results[[1L]]
  expect_identical(res$role, "tool_result")
  expect_identical(msg_text(res), "made")
  expect_null(res[["value"]])
})

test_that("the first run freezes the prompt: gptr.frozen is the first entry (fallback before P07)",
          {
  local_without_services(c("prompt.freeze", "request.build", "prefix.guard", "context.first",
                           "context.turn"))
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  run_text(s, "go")
  first = session_data(s)$entries[[1L]]
  expect_identical(first$custom_type, "gptr.frozen")
})

test_that("a busy session refuses a second run", {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE)))
  s = test_session()
  run = run_start(s, msg_user("go"))
  expect_error(run_start(s, msg_user("again")), class = "gptr_error_busy")
  run_abort(run)
  expect_identical(s$status, "aborted")
})

test_that("an empty input, an empty queue and a finished answer is refused", {
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  run_text(s, "go")
  expect_error(run_start(s, NULL), class = "gptr_error_invalid_argument")
})

test_that("queued items start an idle session's run (input = NULL)", {
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  session_enqueue(s, "please start", as = "follow_up", source = "api_user")
  session_run(s, NULL)
  expect_identical(roles(s), c("user", "assistant"))
  expect_identical(s$messages[[1L]]$source, "follow_up")
  expect_identical(s$turns, 1L)
})

test_that("run_start(s, NULL) continues from the leaf after an abort", {
  local_permissive()
  fake = local_fake_provider(list(list(hang = TRUE), "resumed answer"))
  s = test_session()
  run = run_start(s, msg_user("go"))
  run_wait(list(run), timeout = 0.2)
  run_abort(run, "waiting")
  session_run(s, NULL)
  expect_identical(s$text, "resumed answer")
  expect_identical(s$turns, 1L)
  expect_identical(req_roles(fake_requests(fake)[[2L]]), "user")
})

test_that("run_current() and run_eval_env() inside a tool; the home is reset at settlement", {
  local_permissive()
  box = new.env()
  local_tool("peek", function(input, ctx) {
    box$run = run_current()
    box$env = run_eval_env(box$run)
    "seen"
  })
  local_fake_provider(list(fake_tool("peek"), "done"))
  home = new.env()
  s = test_session(home = home)
  run_text(s, "go")
  expect_s3_class(box$run, "gptr_run")
  expect_identical(box$env, home)
  expect_null(box$run$home)
  expect_null(run_current())
})

test_that("plan mode evaluates in a scratch overlay that is discarded (IC-15)", {
  local_permissive()
  box = new.env()
  local_tool("peek", function(input, ctx) {
    box$env = run_eval_env(run_current())
    assign("scratch_obj", 1, envir = box$env)
    "ok"
  })
  local_fake_provider(list(fake_tool("peek"), "plan ready"))
  home = new.env()
  s = test_session(mode = "plan", home = home)
  run_text(s, "plan it")
  expect_identical(parent.env(box$env), home)
  expect_false(exists("scratch_obj", envir = home, inherits = FALSE))
})

test_that("a function-frame home is used for the run but never kept (R2)", {
  local_permissive()
  box = new.env()
  local_tool("peek", function(input, ctx) {
    box$env = run_eval_env(run_current())
    "ok"
  })
  local_fake_provider(list(fake_tool("peek"), "done"))
  f = function() {
    s = session_new("fake/fake-1", "auto", home = environment())
    call = new.env()
    call$envir = environment()
    session_run(s, msg_user("go"), list(call = call))
    list(s = s, frame = environment())
  }
  x = f()
  expect_identical(box$env, x$frame)
  expect_null(x$s$envir)
  expect_match(session_data(x$s)$home_label, "^frame of f")
})

test_that("run_abort() records the partial answer, moves the queue to dropped and settles aborted",
          {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE)))
  ev = local_events("agent_end")
  s = test_session()
  run = run_start(s, msg_user("go"))
  run_wait(list(run), timeout = 0.3)
  session_enqueue(s, "later", as = "steer", source = "pipe")
  run_abort(run, "user")
  expect_identical(s$status, "aborted")
  last = s$messages[[length(s$messages)]]
  expect_identical(last$role, "assistant")
  expect_identical(last$stop_reason, "aborted")
  expect_length(session_data(s)$dropped, 1L)
  expect_length(session_data(s)$queue$steer, 0L)
  expect_identical(ev(s)[[1L]]$status, "aborted")
})

test_that("an abort while a tool waits in the FIFO cancels the job; the session can be collected", {
  local_permissive()
  local_tool("queued", function(input, ctx) "never runs")
  local_fake_provider(list(fake_tool("queued"), "never"))
  s = test_session()
  id = session_data(s)$id
  run = run_start(s, msg_user("go"))
  # pump without running any FIFO tool (allow_runs = character()) until the batch is queued
  reactor_pump(until = function() identical(run$status, "tools"), allow_runs = character(),
               timeout = 30)
  run_abort(run)
  other = test_session()
  rm(s, run)
  invisible(gc())
  expect_null(session_by_id(id))
})

test_that("an interrupt aborts the run and is re-signalled; no connection is left open", {
  local_permissive()
  local_store()
  n0 = nrow(showConnections())
  local_tool("spin", function(input, ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "no"
  })
  local_fake_provider(list(fake_tool("spin"), "never"))
  s = test_session()
  res = tryCatch({
    run_text(s, "go")
    "returned"
  }, interrupt = function(cnd) "interrupted")
  expect_identical(res, "interrupted")
  expect_identical(s$status, "aborted")
  expect_identical(nrow(showConnections()), n0)
})

test_that("no connection is left open after a run returns or errors (IC-59)", {
  local_permissive()
  local_store()
  n0 = nrow(showConnections())
  local_fake_provider(list("ok", fake_error("400 bad request", status = 400L)))
  s = test_session()
  run_text(s, "a")
  run_text(s, "b")
  expect_identical(s$status, "error")
  expect_identical(nrow(showConnections()), n0)
})

test_that("a nested run tightens the mode, inherits the snapshot and links to the outer run", {
  local_permissive()
  box = new.env()
  local_tool("sub", function(input, ctx) {
    child = session_new("fake/fake-1", "auto", home = new.env(), kind = "child",
                        parent = ctx$session)
    box$outer = run_current()
    box$child_run = run_start(child, msg_user("child task"))
    box$child = child
    run_wait(list(box$child_run))
    "child done"
  })
  local_fake_provider(list(fake_tool("sub"), "child answer", "outer done"))
  s = test_session(mode = "manual")
  run_text(s, "go")
  expect_identical(box$child_run$mode, "manual")
  expect_identical(box$child_run$opts$safety, box$outer$opts$safety)
  expect_identical(box$child_run$parent_run, box$outer$id)
  expect_true(session_data(box$child)$id %in% box$outer$children)
  expect_identical(session_data(box$child)$depth, 1L)
  expect_identical(box$child$text, "child answer")
  expect_identical(nrow(s$usage), 3L)
})

test_that("gptr.max_nested_calls caps gptr() calls of one evaluation; a group counts once", {
  local_permissive()
  local_gptr_options(max_nested_calls = 2L)
  box = new.env()
  local_tool("many", function(input, ctx) {
    # three children of one team share `nested_group` and count once (1 of 2) ...
    box$team = tryCatch({
      for (i in 1:3) {
        child = session_new("fake/fake-1", "auto", home = new.env(), kind = "child",
                            parent = ctx$session)
        run_wait(list(run_start(child, msg_user("x"), list(nested_group = "team1"))))
      }
      "ok"
    }, error = function(e) e)
    # ... so one more call fits (2 of 2) and the next is refused (3 > 2)
    box$err = tryCatch({
      for (i in 1:2) {
        child = session_new("fake/fake-1", "auto", home = new.env(), kind = "child",
                            parent = ctx$session)
        run_wait(list(run_start(child, msg_user("x"))))
      }
      NULL
    }, error = function(e) e)
    "ok"
  })
  local_fake_provider(list(fake_tool("many"), "c"))
  s = test_session()
  run_text(s, "go")
  expect_identical(box$team, "ok")
  expect_s3_class(box$err, "gptr_error_budget")
  expect_identical(box$err$kind, "nested_calls")
})

test_that("tools plus returns = <schema> give a typed $value and keep the tool calls (INFRA-25)", {
  local_permissive()
  local_tool("count", function(input, ctx) "32")
  local_fake_provider(list(fake_tool("count"), list(json = list(n = 32L))))
  s = test_session()
  run_text(s, "count", list(returns = list(type = "object", required = I("n"),
                                           properties = list(n = list(type = "integer")))))
  expect_identical(s$value$n, 32L)
  expect_identical(roles(s), c("user", "assistant", "tool_result", "assistant"))
})

test_that("a router session calls router.call before each request (IC-69)", {
  # P07's compactor would ask the router for its compaction model first (reason "compaction")
  local_without_services(c("compact.should", "compact.run"))
  local_permissive()
  local_fake_provider(list("routed"))
  calls = new.env()
  calls$reasons = character()
  local_service("router.call", function(s, reason) {
    calls$reasons = c(calls$reasons, reason)
    list(model = "fake/fake-1", thinking = NULL, state = list(k = 1))
  })
  s = session_new("router:cheapest", "auto", home = new.env())
  run_text(s, "go")
  expect_identical(calls$reasons, "turn")
  types = vapply(session_data(s)$entries, function(e) e$custom_type %||% e$type, "")
  expect_true(all(c("model_change", "gptr.router") %in% types))
  expect_identical(s$text, "routed")
  expect_identical(s$model, "router:cheapest")
})

test_that("a prefix break stops the run only under gptr.check_prefix = \"error\"", {
  local_permissive()
  local_service("prefix.guard", function(s, target, view) {
    gptr_abort("Prompt-cache prefix broken at t1", "internal", detail = "test break")
  })
  fake = local_fake_provider(list("ok"))
  local_gptr_options(check_prefix = "error")
  s = test_session()
  run_text(s, "hello")
  expect_identical(s$status, "error")
  expect_s3_class(session_data(s)$condition, "gptr_error_internal")
  expect_length(fake_requests(fake), 0L)
  local_gptr_options(check_prefix = "event")
  s2 = test_session()
  run_text(s2, "hello")
  expect_identical(s2$status, "idle")
  expect_identical(s2$text, "ok")
})

test_that("two concurrent sessions keep separate usage and tool context (INFRA-15)", {
  local_permissive()
  seen = new.env()
  local_tool("who", function(input, ctx) {
    seen[[session_data(ctx$session)$id]] = run_current()$session
    "me"
  })
  local_fake_provider(list(fake_tool("who"), "a2"), name = "fa")
  local_fake_provider(list(fake_tool("who"), "b2"), name = "fb")
  s1 = test_session(model = "fa/fa-1")
  s2 = test_session(model = "fb/fb-1")
  r1 = run_start(s1, msg_user("x"))
  r2 = run_start(s2, msg_user("y"))
  run_wait(list(r1, r2))
  id1 = session_data(s1)$id
  id2 = session_data(s2)$id
  expect_identical(nrow(s1$usage), 2L)
  expect_identical(unique(s1$usage$session), id1)
  expect_identical(unique(s2$usage$session), id2)
  expect_identical(seen[[id1]], id1)
  expect_identical(seen[[id2]], id2)
})

test_that("a tool piping into its own running session enqueues a steer delivered after its result",
          {
  local_permissive()
  local_tool("self", function(input, ctx) {
    session_enqueue(ctx$session, "use TPM", as = "steer", source = "pipe")
    "sent"
  })
  fake = local_fake_provider(list(fake_tool("self"), "ack", "done"))
  s = test_session()
  run_text(s, "go")
  req = fake_requests(fake)[[2L]]
  expect_identical(req_roles(req), c("user", "assistant", "tool_result", "operator"))
  expect_identical(msg_text(req$messages[[4L]]),
                   "The user sent this message while you were working: use TPM")
})

test_that("a mode change during a run reaches the model as an operator message after the results", {
  local_permissive()
  box = new.env()
  local_tool("switch", function(input, ctx) {
    session_set_mode(ctx$session, "plan", source = "pause_menu")
    "switched"
  })
  fake = local_fake_provider(list(fake_tool("switch"), "ok"))
  s = test_session(mode = "auto")
  run_text(s, "go")
  req = fake_requests(fake)[[2L]]
  expect_identical(req_roles(req), c("user", "assistant", "tool_result", "operator"))
  expect_match(msg_text(req$messages[[4L]]), "<mode name=\"plan\">", fixed = TRUE)
})

test_that("a run sent to the background ends the foreground wait (P21)", {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE)))
  s = test_session()
  local_hook("message_start", function(event, ctx) {
    run = session_live(ctx$session)$run
    if (!is.null(run)) run$opts$background = TRUE
    NULL
  })
  session_run(s, msg_user("go"))
  expect_identical(s$status, "running")
  run_abort(session_live(s)$run)
})

test_that("a UI answering abort to a permission request aborts the run", {
  local_gptr_options(interactive = TRUE)
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE, permission = function(request) list(decision = "abort"))
  })
  local_tool("w", function(input, ctx) "written")
  fake = local_fake_provider(list(fake_tools(list(name = "w", input = json_obj()),
                                             list(name = "w", input = json_obj())), "never"))
  s = test_session(mode = "manual")
  run_text(s, "go")
  expect_identical(s$status, "aborted")
  expect_length(tool_results(s), 1L)
  expect_length(fake_requests(fake), 1L)
})

# ---------------------------------------------------------------- report 02 section 5.3: the driver

local_fast_retry = function(.env = parent.frame()) {
  testthat::local_mocked_bindings(agent_retry_delay = function(attempt) c(0.04, 0.08)[attempt],
                                  .env = .env)
}
flaky = function() {
  list(fake_error("529 overloaded", 529L), fake_error("503 service unavailable", 503L), "finally")
}

test_that(oracle_title(recovery_recs, "R19"), {
  local_permissive()
  local_fast_retry()
  fake = local_fake_provider(flaky())
  s = test_session()
  run_text(s, "hello")
  expect_length(fake_requests(fake), 3L)
  expect_identical(s$text, "finally")
  expect_identical(s$status, "idle")
})

test_that(oracle_title(recovery_recs, "R20"), {
  local_permissive()
  local_fast_retry()
  fake = local_fake_provider(flaky())
  run_text(test_session(), "hello")
  expect_identical(req_roles(fake_requests(fake)[[3L]]), "user")
})

test_that(oracle_title(recovery_recs, "R21"), {
  local_permissive()
  local_fast_retry()
  local_fake_provider(flaky())
  s = test_session()
  run_text(s, "hello")
  expect_identical(sum(vapply(s$messages, function(m) identical(m$stop_reason, "error"), NA)), 2L)
})

test_that(oracle_title(recovery_recs, "R22"), {
  local_permissive()
  local_fast_retry()
  ev = local_events(c("retry_start", "retry_end"))
  local_fake_provider(flaky())
  s = test_session()
  t0 = Sys.time()
  run_text(s, "hello")
  el = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  starts = Filter(function(e) identical(e$type, "retry_start"), ev(s))
  expect_identical(vapply(starts, function(e) e$delay, 1), c(0.04, 0.08))
  expect_gte(el, 0.1)
  expect_true(ev(s)[[length(ev(s))]]$ok)
})

test_that(oracle_title(recovery_recs, "R23"), {
  local_permissive()
  ev = local_events("retry_start")
  fake = local_fake_provider(list(fake_error("insufficient_quota", status = 400L)))
  s = test_session()
  run_text(s, "hello")
  expect_length(fake_requests(fake), 1L)
  expect_length(ev(s), 0L)
  expect_identical(s$status, "error")
})

test_that(oracle_title(recovery_recs, "R24"), {
  local_permissive()
  local_fast_retry()
  ev = local_events("retry_end")
  fake = local_fake_provider(list(fake_error("overloaded", 529L)))
  s = test_session()
  run_text(s, "hello")
  expect_length(fake_requests(fake), 3L)
  expect_false(ev(s)[[1L]]$ok)
  expect_identical(s$status, "error")
  expect_s3_class(session_data(s)$condition, "gptr_error_provider")
})

test_that(oracle_title(recovery_recs, "R25"), {
  local_permissive()
  n = new.env()
  n$calls = 0L
  local_service("compact.run", function(s, reason, focus = NULL) {
    n$calls = n$calls + 1L
    n$reason = reason
    invisible(s)
  })
  fake = local_fake_provider(list(list(overflow = TRUE), "fits now"))
  s = test_session()
  run_text(s, "hello")
  expect_identical(n$calls, 1L)
  expect_identical(n$reason, "overflow")
  expect_length(fake_requests(fake), 2L)
  expect_identical(s$status, "idle")
})

test_that(oracle_title(recovery_recs, "R26"), {
  local_permissive()
  n = new.env()
  n$calls = 0L
  local_service("compact.run", function(s, reason, focus = NULL) {
    n$calls = n$calls + 1L
    invisible(s)
  })
  fake = local_fake_provider(list(list(overflow = TRUE)))
  s = test_session()
  run_text(s, "hello")
  expect_identical(n$calls, 1L)
  expect_length(fake_requests(fake), 2L)
  expect_identical(s$status, "error")
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_context_overflow")
  expect_s3_class(cnd, "gptr_error_provider")
  expect_match(conditionMessage(cnd), "still too large after one compaction", fixed = TRUE)
})

test_that("without a compactor the first overflow is terminal", {
  local_without_services(c("compact.should", "compact.run"))
  local_permissive()
  fake = local_fake_provider(list(list(overflow = TRUE)))
  s = test_session()
  run_text(s, "hello")
  expect_length(fake_requests(fake), 1L)
  expect_s3_class(session_data(s)$condition, "gptr_error_context_overflow")
})

test_that("every report 02 recovery check has a test", {
  expect_oracles_covered(recovery_recs, "test-agent-run.R")
})
```

Append to `tests/testthat/test-agent-dispatch.R`:

```r

# ---------------------------------------------------------------- through runs

test_that("a length stop mid-call gives an error result and done(length) (INFRA-09)", {
  local_permissive()
  ran = new.env()
  ran$yes = FALSE
  local_tool("w", function(input, ctx) {
    ran$yes = TRUE
    "x"
  })
  local_fake_provider(list(c(fake_tool("w"), list(stop = "length")), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_false(ran$yes)
  expect_identical(s$messages[[2L]]$stop_reason, "length")
  expect_true(tool_results(s)[[1L]]$is_error)
  expect_identical(s$status, "idle")
})

test_that("with no policy a mutating tool asks and the run ends blocked without a human", {
  local_tool("w", function(input, ctx) "written")
  fake = local_fake_provider(list(fake_tool("w"), "never"))
  s = test_session(mode = "manual")
  run_text(s, "go")
  expect_identical(s$status, "blocked")
  expect_length(fake_requests(fake), 1L)
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_permission")
  expect_identical(s$reason, conditionMessage(cnd))
})
```

Append to `tests/testthat/test-session-budget.R`:

```r

test_that("a token budget stops the run before the next request with status budget", {
  local_permissive()
  ev = local_events(c("budget_exceeded", "budget_near"))
  local_tool("noop", function(input, ctx) "ok")
  fake = local_fake_provider(list(c(fake_tool("noop"), list(usage = usage_new(input = 990,
                                                                              output = 50))),
                                  "never"), name = "fb")
  s = test_session(model = "fb/fb-1")
  run_text(s, "go", list(budget = list(tokens = 1000)))
  expect_identical(s$status, "budget")
  expect_length(fake_requests(fake), 1L)
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_budget_tokens")
  expect_s3_class(cnd, "gptr_error_budget")
  expect_identical(cnd$kind, "tokens")
  types = vapply(ev(s), function(e) e$type, "")
  expect_identical(types, c("budget_near", "budget_exceeded"))
  d = session_data(s)
  last = d$entries[[length(d$entries)]]
  expect_identical(last$custom_type, "gptr.budget")
})

test_that("a budget of 5 USD on a root stops its children (root charging, IC-66)", {
  local_permissive()
  box = new.env()
  local_tool("spawn", function(input, ctx) {
    root = ctx$session
    usage_add(root, usage_fixture(session_data(root)$id, "q-costly", cost = 6))
    child = session_new("fake/fake-1", "auto", home = new.env(), kind = "child", parent = root)
    box$child = child
    run_wait(list(run_start(child, msg_user("child work"))))
    "spawned"
  })
  fake = local_fake_provider(list(fake_tool("spawn"), "never"))
  s = test_session()
  run_text(s, "go", list(budget = list(cost = 5)))
  expect_identical(box$child$status, "budget")
  expect_s3_class(session_data(box$child)$condition, "gptr_error_budget_cost")
  expect_identical(s$status, "budget")
  expect_length(fake_requests(fake), 1L)
})

test_that("interactively a reached budget can be extended by the same amount (ask_human)", {
  local_permissive()
  local_gptr_options(interactive = TRUE)
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE, select = function(title, choices, default = NULL, ...) 1L)
  })
  local_tool("noop", function(input, ctx) "ok")
  fake = local_fake_provider(list(c(fake_tool("noop"), list(usage = usage_new(input = 990,
                                                                              output = 50))),
                                  "finished"), name = "fb")
  s = test_session(model = "fb/fb-1")
  run_text(s, "go", list(budget = list(tokens = 1000)))
  expect_identical(s$status, "idle")
  expect_length(fake_requests(fake), 2L)
})
```

Append to `tests/testthat/test-session-store.R`:

```r

# ---------------------------------------------------------------- the kernel side of compaction
# The algorithm is P07's; a fake compactor stands in through the compact.should/compact.run
# services.

local_compactor = function(should = function(s, tokens, idle_s) FALSE, .env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$calls = list()
  log$tokens = numeric()
  local_service("compact.should", function(s, tokens, idle_s) {
    log$tokens = c(log$tokens, tokens)
    should(s, tokens, idle_s)
  }, .env = .env)
  local_service("compact.run", function(s, reason, focus = NULL) {
    d = session_data(s)
    last = d$entries[[length(d$entries)]]
    log$calls[[length(log$calls) + 1L]] = list(reason = reason, last = last)
    users = Filter(function(e) identical(e$type, "message") && identical(e$message$role, "user"),
                   entries_path(d))
    session_append(s, list(type = "compaction", summary = "## Goal\nsummary",
                           first_kept_entry_id = users[[length(users)]]$id, tokens_before = 1234,
                           details = list(readFiles = list("R/a.R")),
                           gptr = list(blocks = list(block_context("checkpoint", "summary",
                                                                   attrs = list(n = "1"))),
                                       state = list(), n = 1L)))
    invisible(s)
  }, .env = .env)
  log
}

compacting_run = function(.env = parent.frame()) {
  local_store(.env = .env)
  local_permissive(.env = .env)
  local_tool("read", function(input, ctx) paste(rep("lorem ipsum", 50), collapse = " "),
             .env = .env)
  once = new.env()
  once$done = FALSE
  log = local_compactor(should = function(s, tokens, idle_s) {
    if (once$done || session_data(s)$turns < 2L) return(FALSE)
    once$done = TRUE
    TRUE
  }, .env = .env)
  fake = local_fake_provider(list("first answer", fake_tool("read", path = "R/a.R"),
                                  "second answer"),
                             .env = .env)
  s = test_session()
  run_text(s, "Task 1")
  n_before = length(session_data(s)$entries)
  run_text(s, "Task 2")
  list(s = s, log = log, fake = fake, n_before = n_before)
}

file_entries = function(s) {
  lapply(readLines(session_data(s)$file, encoding = "UTF-8")[-1L], json_decode)
}

test_that(oracle_title(store_recs, "S25"), {
  x = compacting_run()
  expect_length(x$log$calls, 1L)
  expect_identical(x$log$calls[[1L]]$reason, "threshold")
  expect_true(all(is.finite(x$log$tokens)))
})

test_that(oracle_title(store_recs, "S26"), {
  x = compacting_run()
  last = x$log$calls[[1L]]$last
  expect_identical(last$message$role, "user")
  d = session_data(x$s)
  for (e in d$entries) {
    if (identical(e$type, "compaction")) break
    prev = e
  }
  expect_false(identical(prev$message$role, "assistant") &&
                 any(vapply(prev$message$content, function(b) identical(b$type, "tool_call"), NA)))
})

test_that(oracle_title(store_recs, "S27"), {
  x = compacting_run()
  req = fake_requests(x$fake)[[2L]]
  texts = vapply(req$messages, msg_text, "")
  expect_false(any(grepl("Task 1", texts, fixed = TRUE)))
  expect_false(any(texts == "first answer"))
  expect_true(any(grepl("Task 2", texts, fixed = TRUE)))
})

test_that(oracle_title(store_recs, "S28"), {
  x = compacting_run()
  e = Filter(function(e) identical(e$type, "compaction"), file_entries(x$s))[[1L]]
  expect_identical(e$summary, "## Goal\nsummary")
  expect_identical(e$tokensBefore, 1234L)
  expect_false(is.null(e$firstKeptEntryId))
  expect_identical(e$gptr$blocks[[1L]]$gptr$context, "checkpoint")
})

test_that(oracle_title(store_recs, "S29"), {
  x = compacting_run()
  expect_identical(vapply(x$log$calls, function(k) k$reason, ""), "threshold")
})

test_that(oracle_title(store_recs, "S33"), {
  x = compacting_run()
  req = fake_requests(x$fake)[[3L]]
  first = req$messages[[1L]]
  expect_true(any(vapply(first$content, function(b) {
    identical(b$type, "context") && identical(b$kind, "checkpoint")
  }, NA)))
  expect_identical(req_roles(req), c("user", "user", "assistant", "tool_result"))
})

test_that(oracle_title(store_recs, "S35"), {
  x = compacting_run()
  d = session_data(x$s)
  expect_identical(sum(vapply(d$entries, function(e) identical(e$type, "compaction"), NA)), 1L)
  expect_gt(length(d$entries), x$n_before)
  expect_length(readLines(d$file, encoding = "UTF-8"), 1L + length(d$entries))
})

test_that(oracle_title(store_recs, "S36"), {
  local_permissive()
  log = local_compactor(should = function(s, tokens, idle_s) TRUE)
  local_fake_provider(list("a"))
  run_text(test_session(), "one")
  expect_length(log$calls, 1L)
})

test_that(oracle_title(store_recs, "S38"), {
  x = compacting_run()
  lines = readLines(session_data(x$s)$file, encoding = "UTF-8")
  expect_true(any(grepl("Task 1", lines, fixed = TRUE)))
  expect_true(any(vapply(session_data(x$s)$entries, function(e) {
    identical(e$type, "message") && identical(msg_text(e$message), "Task 1")
  }, NA)))
})

test_that(oracle_title(store_recs, "S39"), {
  local_permissive()
  local_tool("read", function(input, ctx) "data")
  n = new.env()
  n$calls = 0L
  local_service("compact.run", function(s, reason, focus = NULL) {
    n$calls = n$calls + 1L
    invisible(s)
  })
  local_fake_provider(list(fake_tool("read", path = "a"), list(overflow = TRUE), "done"))
  s = test_session()
  run_text(s, "long task")
  expect_identical(n$calls, 1L)
  expect_length(Filter(function(m) identical(m$role, "user"), s$messages), 1L)
  expect_identical(s$status, "idle")
  expect_identical(s$turns, 1L)
})

test_that(oracle_title(store_recs, "S40"), {
  local_permissive()
  local_tool("read", function(input, ctx) "data")
  local_service("compact.run", function(s, reason, focus = NULL) invisible(s))
  fake = local_fake_provider(list(fake_tool("read", path = "a"), list(overflow = TRUE), "done"))
  run_text(test_session(), "long task")
  req = fake_requests(fake)[[3L]]
  calls = unlist(lapply(req$messages, function(m) {
    vapply(Filter(function(b) identical(b$type, "tool_call"), m$content %||% list()),
           function(b) b$id, "")
  }))
  results = vapply(Filter(function(m) identical(m$role, "tool_result"), req$messages),
                   function(m) m$tool_call_id, "")
  expect_setequal(calls, results)
})

test_that(oracle_title(store_recs, "S41"), {
  local_permissive()
  local_tool("slow", function(input, ctx) "done")
  box = new.env()
  local_hook("tool_execution_start", function(event, ctx) {
    session_enqueue(box$s, "use data.table instead", "steer", source = "pipe")
    session_enqueue(box$s, "then plot it", "follow_up", source = "pipe")
    NULL
  })
  local_fake_provider(list(fake_tool("slow"), "ok 1", "ok 2"))
  box$s = test_session()
  run_text(box$s, "go")
  txt = vapply(box$s$messages, msg_text, "")
  i = grep("use data.table instead", txt, fixed = TRUE)
  j = grep("then plot it", txt, fixed = TRUE)
  expect_true(length(i) == 1L && length(j) == 1L && i < j)
})

test_that(oracle_title(store_recs, "S42"), {
  local_permissive()
  local_tool("slow", function(input, ctx) "done")
  box = new.env()
  local_hook("tool_execution_start", function(event, ctx) {
    session_enqueue(box$s, "steer me", "steer", source = "pipe")
    NULL
  })
  ev = local_events("queue_update")
  local_fake_provider(list(fake_tool("slow"), "ok"))
  box$s = test_session()
  run_text(box$s, "go")
  expect_length(session_data(box$s)$queue$steer, 0L)
  last = ev(box$s)[[length(ev(box$s))]]
  expect_identical(c(last$steer, last$follow_up), c(0L, 0L))
})

test_that("each run touches its session's lock when it starts (heartbeat, IC-59)", {
  local_store()
  local_permissive()
  local_fake_provider(list("one", "two"))
  s = test_session()
  run_text(s, "first")
  pid_file = file.path(lock_path(session_data(s)$file), "pid")
  Sys.setFileTime(pid_file, Sys.time() - 86400)
  run_text(s, "second")
  expect_lt(as.numeric(Sys.time()) - as.numeric(file.mtime(pid_file)), 3600)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(agent-loop|agent-run|agent-dispatch|session-budget|session-store)$")'`

Expected: `[ FAIL 78 | WARN 0 | SKIP 0 | PASS 398 ]`, with errors such as ``Error in `session_run(s, msg_user(text), opts)`: could not find function "session_run"``.

- [ ] **Step 3: Write the implementation**

One reactor task per run (`run_drive()`) asks the loop for its next action whenever the run is not busy. A request goes out through `provider_stream()` with emit/done closures whose frame holds the run and the request but never a user frame (a function-frame home is reachable only through `run$home`, reset at settlement, rule R2), and with the run's gate, tool-result builder and MCP dispatcher in `opts` (IC-33; P05 reads them from there); deltas become `message_update` events through a stream redactor; `done()` records the assistant message, the usage row (charged to every ancestor, IC-66) and the ledger. Sequential tools go through P04's tool FIFO (`reactor_enqueue_tool()`), so a nested pump never runs another run's tool (IC-57). Steering is taken only at turn boundaries, after complete tool results (INFRA-12). `session_run()` pumps until settlement under the `console.interrupt_policy` service; without it an interrupt aborts the run and is re-signalled.

Append to `R/agent-run.R`:

```r
# ---------------------------------------------------------------------------- starting and waiting

#' Run a session to settlement
#'
#' Appends the input and runs `s` on the reactor under the interrupt policy (the
#' `console.interrupt_policy` service of P14 when registered, else abort-only). Raises nothing
#' itself: the gateway maps terminal statuses to conditions (04 section 6.1.2); an interrupt aborts
#' the run, keeps the partial turn and is re-signalled. A run marked `opts$background` by P21 stops
#' the foreground wait.
#' @param input A message (`msg_user()`), a list of messages, or `NULL` (the queued items, else a
#'   continuation from the leaf).
#' @param opts Run options (04 section 7.6).
#' @return `s`, invisibly.
#' @noRd
session_run = function(s, input, opts = list()) {
  run = run_start(s, input, opts)
  wait = function() run_wait_foreground(run)
  if (ext_service_has("console.interrupt_policy")) {
    ext_service_get("console.interrupt_policy")(wait, list(run), mode = "call")
  } else {
    run_abort_only(wait, run)
  }
  invisible(s)
}

#' Pump until the run settles or is sent to the background
#' @noRd
run_wait_foreground = function(run) {
  allow = if (is.null(run_current())) NULL else run$id
  reactor_pump(until = function() isTRUE(run$settled) || isTRUE(run$opts$background),
               slice_ms = 100L, allow_runs = allow)
}

#' The abort-only interrupt policy: abort the run, then re-signal the interrupt
#' @noRd
run_abort_only = function(expr_fun, run) {
  tryCatch(expr_fun(), interrupt = function(cnd) {
    run_abort(run, "interrupt")
    run_resignal_interrupt()
  })
}

#' Re-signal an interrupt after cleanup (report 02 section 5.8): enclosing handlers see it, and
#' without one the evaluation returns to the top level
#' @noRd
run_resignal_interrupt = function() {
  cnd = structure(class = c("interrupt", "condition"), list(message = "", call = NULL))
  signalCondition(cnd)
  invokeRestart("abort")
}

#' Start a run without blocking
#'
#' Attaches a detached copy first (split-brain rules), refuses a running session
#' (`gptr_error_busy`), counts nested `gptr()` calls against `gptr.max_nested_calls` (IC-66),
#' freezes the prompt at the first run, appends the input and registers the run with the reactor.
#' @return A `gptr_run` held by the reactor until it settles.
#' @noRd
run_start = function(s, input, opts = list()) {
  check_class(s, "gptr_session", "s")
  check_list(opts, "opts")
  input = run_input(input)
  outer = run_current()
  live = session_attach(s)
  d = session_data(s)
  if (!is.null(live$run) || identical(d$status, "running")) {
    gptr_abort(paste0("session ", d$id, " is running; steer it with gptr_steer() or wait for it"),
               "busy", session = d$id)
  }
  if (!is.null(outer)) run_count_nested(outer, opts)
  run = run_new(s, opts, outer)
  input = run_initial_input(run, input)
  live$run = run
  d$status = "running"
  d$reason = NULL
  d$condition = NULL
  d$budget = run$budget
  if (is.null(d$parent_id)) last_set(s)
  reactor_run_add(run)
  # a failure before the run is wired (a freeze that refuses the model, a store error) settles
  # the run with status error and re-signals, so the session never stays `running`
  started = tryCatch({
    input = run_freeze(run, input)
    run_emit(run, "agent_start")
    run_emit(run, "turn_start")
    if (!is.null(input)) run_append_messages(run, input)
    run_wire(run)
    TRUE
  }, error = function(e) e)
  if (!isTRUE(started)) {
    run_fail(run, started)
    stop(started)
  }
  run
}

#' Normalise the input of a run: NULL, one message, or a list of messages
#' @noRd
run_input = function(input) {
  if (is.null(input)) return(NULL)
  if (is.list(input) && !is.null(input$role)) return(list(input))
  if (is.list(input) && length(input) &&
      all(vapply(input, function(m) is.list(m) && !is.null(m$role), NA))) return(input)
  gptr_abort("`input` must be a message or a list of messages", "invalid_argument", arg = "input",
             expected = "a message from msg_user() or a list of messages")
}

#' Without input: the first queued item (steers first) opens the turn; with an empty queue the run
#' continues from the leaf when the path awaits a response, else there is nothing to run
#' @noRd
run_initial_input = function(run, input) {
  if (!is.null(input)) return(input)
  d = session_data(run$shell)
  for (which in c("steer", "follow_up")) {
    if (length(d$queue[[which]])) return(run_take(run, which))
  }
  msgs = Filter(function(m) {
    !(identical(m$role, "assistant") && (m$stop_reason %||% "stop") %in% c("error", "aborted"))
  }, path_messages(entries_path(d)))
  if (length(msgs)) {
    last = msgs[[length(msgs)]]
    open_calls = any(vapply(last$content %||% list(),
                            function(b) identical(b$type, "tool_call"), NA))
    if (!identical(last$role, "assistant") || open_calls) return(NULL)
  }
  gptr_abort("nothing to run: no input, an empty queue and a finished answer", "invalid_argument",
             arg = "input", expected = "a message or queued items")
}

#' Wire a run: the loop, its reactor task, the heartbeat and the callbacks that provider_stream()
#' injects into adapters (IC-33); the closures capture a frame that holds only `run` (rule R2)
#' @noRd
run_wire = function(run) {
  run$gate = function(call) perm_check(call, run)
  run$tool_result = function(result, call) tool_result_message(result, call)
  run$mcp_dispatch = function(message) ext_service_get("mcp.dispatch_local")(message, run$shell)
  run$loop = loop_new(max_turns = run$max_turns,
                      steering = function() run_take(run, "steer"),
                      follow_up = function() run_take(run, "follow_up"),
                      finish_turn = function(turn) run_finish_turn(run, turn),
                      emit = function(type, ...) run_emit(run, type, ...))
  run$task = reactor_task(function() run_drive(run), run = run)
  # touch the lock now, then every 10 minutes (IC-59): a session whose runs are all shorter than
  # 10 minutes still refreshes its lock at each run, so another process never takes an actively
  # used session's lock for stale after 24 h
  run_heartbeat(run)
  invisible(run)
}

#' Count gptr() calls made from one `r` evaluation (gptr.max_nested_calls, IC-66); the children of
#' one team or fan-out share `opts$nested_group` and count once
#' @noRd
run_count_nested = function(outer, opts) {
  tc = outer$tool_call
  if (is.null(tc)) return(invisible(NULL))
  counts = outer$nested_count
  keys = unique(c(counts[[tc$id]], opts$nested_group %||% id_new("g", 8L)))
  counts[[tc$id]] = keys
  outer$nested_count = counts
  cap = gptr_opt("max_nested_calls")
  if (length(keys) > cap) {
    gptr_abort(paste0("too many gptr() calls in one evaluation (limit ", cap,
                      ", option gptr.max_nested_calls)"),
               "budget", kind = "nested_calls", budget = cap, used = length(keys),
               session = outer$session)
  }
  invisible(length(keys))
}

#' Pump the reactor until every run settled or `timeout` seconds passed
#' @return `invisible(TRUE)` when all settled.
#' @noRd
run_wait = function(runs, timeout = Inf) {
  if (inherits(runs, "gptr_run")) runs = list(runs)
  settled = function() all(vapply(runs, function(r) isTRUE(r$settled), NA))
  if (settled()) return(invisible(TRUE))
  allow = if (is.null(run_current())) NULL else vapply(runs, function(r) r$id, "")
  ok = reactor_pump(until = settled, slice_ms = 100L, allow_runs = allow, timeout = timeout)
  invisible(isTRUE(ok) || settled())
}

#' Append messages and emit their events; the first user message of a run opens a prompt turn
#' @noRd
run_append_messages = function(run, msgs) {
  s = run$shell
  d = session_data(s)
  for (m in msgs) {
    if (identical(m$role, "user") && !isTRUE(run$counted_turn) && !isTRUE(run$requested)) {
      d$turns = d$turns + 1L
      run$counted_turn = TRUE
    }
    session_append(s, entry_message(m))
    run_emit(run, "message_start", role = m$role)
    run_emit(run, "message_end", role = m$role, message = m)
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------- driving the loop

#' The reactor task of a run: one loop action per call while not waiting
#' @return `TRUE` while the run is active.
#' @noRd
run_drive = function(run) {
  if (isTRUE(run$settled)) return(FALSE)
  if (isTRUE(run$busy)) return(TRUE)
  tryCatch(run_step(run), error = function(e) run_fail(run, e))
  !isTRUE(run$settled)
}

#' One step: abort when signalled, else the loop's next action
#' @noRd
run_step = function(run) {
  if (isTRUE(run$signal$aborted)) return(run_abort(run, run$signal$reason %||% "user"))
  act = loop_next(run$loop)
  switch(act$action,
    request = run_begin_request(run, act$messages),
    tools = run_tools(run, act),
    end = run_settle(run, act$reason),
    invisible(NULL))
}

#' Take one queued item and turn it into a message (IC-55); steers become relays once the run has
#' made a request
#' @noRd
run_take = function(run, which) {
  d = session_data(run$shell)
  q = d$queue
  if (!length(q[[which]])) return(list())
  item = q[[which]][[1L]]
  q[[which]] = q[[which]][-1L]
  d$queue = q
  run_emit(run, "queue_update", steer = length(q$steer), follow_up = length(q$follow_up))
  list(queue_item_message(item, which, relay = isTRUE(run$requested)))
}

#' The loop's finish_turn hook: a blocked gate or an abort ends the run
#' @noRd
run_finish_turn = function(run, turn) {
  if (!is.null(run$blocked)) return(list(action = "end", reason = "blocked"))
  if (isTRUE(run$signal$aborted)) return(list(action = "end", reason = "aborted"))
  NULL
}

#' Start a turn's request: pending operator messages and queued messages first
#' @noRd
run_begin_request = function(run, messages) {
  ops = run$pending_operator
  run$pending_operator = list()
  run_append_messages(run, c(ops, messages))
  run$requested = TRUE
  run$boundary_compacted = FALSE
  run_request(run)
}

#' Make one model request (also used for retries)
#' @noRd
run_request = function(run) {
  s = run$shell
  d = session_data(s)
  live = session_live(s)
  if (isTRUE(run$signal$aborted)) return(run_abort(run, run$signal$reason %||% "user"))
  if (identical(run$attempt, 0L) && !isTRUE(run$boundary_compacted)) run_compact_check(run)
  target = run_target(run)
  req = run_build(run, target)
  hit = budget_check(s, req$tokens_est)
  if (!is.null(hit) && !run_budget_extend(run, hit)) return(run_stop_budget(run, hit))
  if (ext_service_has("prefix.guard")) {
    # gptr.check_prefix = "error" (04 section 3.1) stops the run: P07's guard signals
    # gptr_error_internal and the run settles with status error; other failures are diagnostics
    tryCatch(ext_service_get("prefix.guard")(s, target, req$view), error = function(e) {
      if (inherits(e, "gptr_error_internal") && identical(gptr_opt("check_prefix"), "error")) {
        stop(e)
      }
      registry_diagnostic("session", "prefix.guard", "service_error", conditionMessage(e))
    })
  }
  run$request_id = req$context$request_id
  run$request_ids = c(run$request_ids, run$request_id)
  run$tokens_est = req$tokens_est
  ledger_add(s, run$request_id, req$components)
  run_emit(run, "before_request", provider = target$provider, model = target$ref,
           request_id = run$request_id, view = req$view, tokens_est = req$tokens_est)
  req$context$params = run_request_params(run, target, req$context$params)
  run$acc = acc_new()
  run$rs = new.env(parent = emptyenv())
  run$last_error = NULL
  run$request_started = Sys.time()
  run$request_closed = FALSE
  run$busy = TRUE
  run$status = "requesting"
  run$turn = run$loop$turn
  # IC-33: the run's gate, tool-result builder and MCP dispatcher are injected through `opts`
  # (P05's provider_stream() reads opts$gate, opts$tool_result and opts$mcp_dispatch and falls
  # back to a closed gate without them)
  opts = list(signal = run$signal, state = live$adapter, memo = live$memo, run = run$id,
              session = d$id, gate = run$gate, tool_result = run$tool_result)
  if (ext_service_has("mcp.dispatch_local")) opts$mcp_dispatch = run$mcp_dispatch
  tid = provider_stream(target, req$context, opts,
                        emit = function(ev) run_on_event(run, ev),
                        done = function(msg) run_on_done(run, msg), run = run)
  tid = as.character(tid)
  if (length(tid) == 1L && !is.na(tid)) run$transfers = c(run$transfers, tid)
  invisible(NULL)
}

# ---------------------------------------------------------------------------- stream callbacks

#' INFRA-02 events: delta-only agent events, redacted per content block with a streaming hold-back
#' @noRd
run_on_event = function(run, ev) {
  if (isTRUE(run$settled) || isTRUE(run$request_closed)) return(invisible(NULL))
  run$acc$push(ev)
  type = ev$type
  if (identical(type, "start")) {
    run$status = "streaming"
    run_emit(run, "message_start", role = "assistant")
  } else if (type %in% c("text_delta", "thinking_delta", "toolcall_delta")) {
    kind = sub("_delta$", "", type)
    key = as.character(ev$index)
    x = get0(key, envir = run$rs, inherits = FALSE)
    if (is.null(x)) {
      x = list(rs = redact_stream("stream"), kind = kind)
      assign(key, x, envir = run$rs)
    }
    safe = x$rs$push(ev$delta)
    if (nzchar(safe)) run_emit(run, "message_update", index = ev$index, kind = kind, delta = safe)
  } else if (identical(type, "error")) {
    run$last_error = ev$error
  } else if (type %in% c("retry_start", "retry_end")) {
    args = ev[setdiff(names(ev), c("type", "ts", "session", "run", "agent", "turn"))]
    do.call(run_emit, c(list(run, type), args))
  }
  invisible(NULL)
}

#' Emit what the streaming redactors still hold
#' @noRd
run_flush_deltas = function(run) {
  for (key in ls(run$rs)) {
    x = get(key, envir = run$rs)
    rest = x$rs$flush()
    if (nzchar(rest)) run_emit(run, "message_update", index = as.integer(key), kind = x$kind,
                               delta = rest)
  }
  invisible(NULL)
}

#' The final assistant message of a request (called once by provider_stream())
#' @noRd
run_on_done = function(run, msg) {
  if (isTRUE(run$settled) || isTRUE(run$request_closed)) return(invisible(NULL))
  run$request_closed = TRUE
  tryCatch(run_response(run, msg), error = function(e) run_fail(run, e))
  invisible(NULL)
}

#' Account, append and hand the response to the loop (or to recovery when it failed)
#' @noRd
run_response = function(run, msg) {
  s = run$shell
  d = session_data(s)
  run_flush_deltas(run)
  if (is.null(msg$usage) || !isTRUE(sum(unlist(msg$usage[c("input", "output")])) > 0)) {
    msg$usage = usage_new(input = run$tokens_est %||% 0,
                          output = est_tokens(msg_text(msg), "prose"), estimated = TRUE)
  }
  row = usage_row(msg, session = d$id, agent = run$opts$agent %||% "main",
                  parent_id = d$parent_id %||% NA_character_, started = run$request_started,
                  seconds = as.numeric(difftime(Sys.time(), run$request_started, units = "secs")),
                  multiplier = d$estimator$m %||% 1)
  row = usage_conform(row)
  row$request_id = run$request_id
  usage_add(s, row)
  ledger_mark_cached(s, run$request_id, msg$usage$cache_read %||% 0)
  run_emit(run, "usage", row = row)
  run_estimator_update(run, msg)
  session_append(s, entry_message(msg))
  run_emit(run, "message_end", role = "assistant", message = msg)
  run$message = msg
  if (identical(msg$stop_reason, "error")) return(run_response_error(run, msg))
  if (run$attempt > 0L) {
    run_emit(run, "retry_end", attempt = run$attempt, ok = TRUE)
    run$attempt = 0L
  }
  if (identical(msg$stop_reason, "stop") && is_context_overflow(msg, run$model$context)) {
    run$pending_compact = "overflow"
  }
  budget_near(run)
  run$busy = FALSE
  loop_response(run$loop, msg)
  invisible(NULL)
}

#' Recovery of a failed request: one compact-and-retry on overflow, at most two agent-level
#' retries of transient errors, else the error ends the run (report 02 sections 2.8-2.9, C-33)
#' @noRd
run_response_error = function(run, msg) {
  err = run$last_error %||% list()
  if (is_context_overflow(msg, run$model$context, err)) {
    if (!isTRUE(run$overflow_used) && ext_service_has("compact.run")) {
      run$overflow_used = TRUE
      ok = tryCatch({
        ext_service_get("compact.run")(run$shell, "overflow")
        TRUE
      }, error = function(e) {
        registry_diagnostic("session", "compaction", "compaction_failed", conditionMessage(e))
        FALSE
      })
      if (ok) {
        run$boundary_compacted = TRUE
        return(run_schedule_request(run, 0))
      }
    }
    run$condition = run_condition(
      run, msg, c("context_overflow", "provider"),
      message = paste0("the context is still too large",
                       if (isTRUE(run$overflow_used)) " after one compaction and retry" else "",
                       ": ", msg$error_message %||% "context overflow"),
      tokens = msg$usage$input %||% NA_real_)
    return(run_response_final(run, msg))
  }
  if (run_retryable(msg, err) && run$attempt < 2L) {
    run$attempt = run$attempt + 1L
    delay = agent_retry_delay(run$attempt)
    run_emit(run, "retry_start", attempt = run$attempt, delay = delay, class = err_class(err))
    return(run_schedule_request(run, delay))
  }
  if (run$attempt > 0L) run_emit(run, "retry_end", attempt = run$attempt, ok = FALSE)
  run$condition = run_condition(run, msg, provider_classes(err))
  run_response_final(run, msg)
}

#' Hand a failed response to the loop, which ends the run
#' @noRd
run_response_final = function(run, msg) {
  run$busy = FALSE
  loop_response(run$loop, msg)
  invisible(NULL)
}

#' Re-send the current request after `delay` seconds (an interruptible reactor timer)
#' @noRd
run_schedule_request = function(run, delay) {
  run$busy = TRUE
  id = reactor_timer(at = reactor_now() + delay, fn = function() {
    tryCatch(run_request(run), error = function(e) run_fail(run, e))
  }, run = run)
  run$timers = c(run$timers, id)
  invisible(NULL)
}

#' The unsignalled condition object stored for a terminal status (04 section 2.2)
#' @noRd
run_condition = function(run, msg, cls, message = NULL, ...) {
  err = run$last_error %||% list()
  d = session_data(run$shell)
  tryCatch(gptr_abort(message %||% msg$error_message %||% "the model request failed", cls,
                      provider = run$model$provider %||% NA_character_,
                      model = run$model$ref %||% d$model,
                      status = err$status %||% NA_integer_,
                      request_id = err$request_id %||% run$request_id %||% NA_character_,
                      error_type = err_class(err), session = d$id, ...),
           error = function(e) e)
}

# ---------------------------------------------------------------------------- compaction, budgets

#' Threshold compaction at a request boundary (compact.should), or the pending compaction after a
#' silent overflow; none before P07 registers the services. A router session is asked for the
#' compaction model first (IC-69)
#' @noRd
run_compact_check = function(run) {
  s = run$shell
  reason = run$pending_compact
  run$pending_compact = NULL
  if (is.null(reason) && ext_service_has("compact.should")) {
    should_fun = ext_service_get("compact.should")
    should = tryCatch(isTRUE(should_fun(s, context_tokens(s), context_idle(s))),
                      error = function(e) FALSE)
    if (should) reason = "threshold"
  }
  if (is.null(reason) || !ext_service_has("compact.run")) return(invisible(FALSE))
  if (startsWith(session_data(s)$model, "router:")) run_route(run, "compaction")
  ok = tryCatch({
    ext_service_get("compact.run")(s, reason)
    TRUE
  }, error = function(e) {
    registry_diagnostic("session", "compaction", "compaction_failed", conditionMessage(e))
    FALSE
  })
  if (ok) run$boundary_compacted = TRUE
  invisible(ok)
}

#' Ask to extend a reached budget by the same amount (ask_human: the run's UI only)
#' @noRd
run_budget_extend = function(run, hit) {
  if (!isTRUE(run$opts$safety$can_prompt)) return(FALSE)
  ui = run_ui(run)
  if (is.null(ui) || !isTRUE(tryCatch(ui$has_ui(), error = function(e) FALSE))) return(FALSE)
  title = paste0("The ", hit$kind, " budget of this call (", format(hit$budget), ") is reached.")
  ans = tryCatch(ui$select(title, c("Extend it by the same amount", "Stop the run"), default = 2L),
                 error = function(e) NA_integer_)
  if (!identical(as.integer(ans), 1L)) return(FALSE)
  for (r in run_chain(run)) {
    if (identical(r$budget[[hit$kind]], hit$budget)) {
      b = r$budget
      b[[hit$kind]] = 2 * hit$budget
      r$budget = b
      return(TRUE)
    }
  }
  FALSE
}

#' Stop a run at a request boundary because a budget is reached (status budget)
#' @noRd
run_stop_budget = function(run, hit) {
  s = run$shell
  d = session_data(s)
  session_append(s, entry_custom("gptr.budget", list(kind = hit$kind, budget = hit$budget,
                                                     used = hit$used)))
  run_emit(run, "budget_exceeded", kind = hit$kind, budget = hit$budget, used = hit$used)
  run$condition = tryCatch(
    gptr_abort(paste0("the ", hit$kind, " budget of this call (", format(hit$budget),
                      ") is reached (used ", format(hit$used), ")"),
               c(paste0("budget_", hit$kind), "budget"), kind = hit$kind, budget = hit$budget,
               used = hit$used, session = d$id),
    error = function(e) e)
  run_settle(run, "budget")
}

# ---------------------------------------------------------------------------- tools

#' Hand a turn's tool calls to the dispatcher: through the reactor's tool FIFO when any call is
#' sequential (R-evaluating or file-writing tools), directly when every call is concurrent or the
#' batch is truncated (nothing executes). The loop (and so `turn_end`) receives the tool-result
#' messages, never the results' R values (rule R1). The FIFO item id is kept in `run$fifo` so that
#' settlement cancels a job that has not started (it would otherwise hold the run, and the
#' session, until the next pump).
#' @noRd
run_tools = function(run, act) {
  calls = lapply(act$calls, function(b) call_record(run, b))
  run$status = "tools"
  run$busy = TRUE
  job = function() {
    tryCatch({
      out = dispatch_tools(run, calls)
      if (!isTRUE(run$settled)) {
        run$busy = FALSE
        run$status = "boundary"
        loop_results(run$loop, out$messages, out$terminate)
      }
    }, error = function(e) run_fail(run, e))
    invisible(NULL)
  }
  sequential = any(vapply(calls, function(cl) {
    is.null(cl$tool) || !identical(cl$tool$execution, "concurrent")
  }, NA))
  if (sequential && !isTRUE(act$truncated)) {
    run$fifo = c(run$fifo, reactor_enqueue_tool(run, job))
  } else {
    job()
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------- settle and abort

#' Settle a run with a loop end reason: status, stored condition, released frame bindings (rule R2),
#' `agent_end`
#' @noRd
run_settle = function(run, reason) {
  if (isTRUE(run$settled)) return(invisible(NULL))
  run$settled = TRUE
  s = run$shell
  d = session_data(s)
  live = session_live(s)
  status = switch(reason, aborted = "aborted", error = "error", max_turns = "max_turns",
                  blocked = "blocked", budget = "budget", "idle")
  if (identical(status, "max_turns") && is.null(run$condition)) {
    run$condition = tryCatch(
      gptr_abort(paste0("the run stopped after ", run$max_turns, " turns (max_turns)"),
                 "max_turns", max_turns = run$max_turns, session = d$id),
      error = function(e) e)
  }
  if (identical(status, "error") && is.null(run$condition)) {
    run$condition = run_condition(run, run$message %||% list(), "provider")
  }
  txt = final_text(entries_path(d))
  if (!is.null(txt) && !status %in% c("error", "aborted")) d$last_text = txt
  if (identical(status, "idle")) run_returns(run)
  plugin_state_persist(s)
  d$status = status
  d$reason = if (is.null(run$condition)) NULL else conditionMessage(run$condition)
  d$condition = run$condition
  # 04 section 2.2: the condition object travels in the run; P08's gateway_signal() reads it here
  run$signal$condition = run$condition
  run$status = status
  run$home = NULL
  run$scratch = NULL
  run$outer = NULL
  run$opts["call"] = list(NULL)
  ids = as.character(c(run$task, run$timers, run$transfers, run$fifo))
  ids = ids[!is.na(ids) & nzchar(ids)]
  if (length(ids)) tryCatch(reactor_cancel(ids), error = function(e) NULL)
  if (!is.null(live) && identical(live$run, run)) live$run = NULL
  reactor_run_remove(run)
  u = d$usage
  run_emit(run, "agent_end", status = status, reason = d$reason,
           usage = u[u$request_id %in% run$request_ids, , drop = FALSE], doc = run$opts$doc,
           turns = d$turns)
  if (is.null(d$parent_id)) last_set(s)
  invisible(NULL)
}

#' Settle a run after an unexpected R error (kept as the stored condition)
#' @noRd
run_fail = function(run, e) {
  if (isTRUE(run$settled)) return(invisible(NULL))
  run$condition = if (inherits(e, "gptr_error")) {
    e
  } else {
    tryCatch(gptr_abort(paste0("internal error in the run: ", conditionMessage(e)), "internal",
                        detail = conditionMessage(e)),
             error = function(x) x)
  }
  run_settle(run, "error")
}

#' Abort a run: cancel its transfers and child runs, record the partial answer with
#' `stop_reason = "aborted"`, move the queue to `dropped`, settle with status `aborted`
#' @noRd
run_abort = function(run, reason = "user") {
  if (isTRUE(run$settled)) return(invisible(run))
  s = run$shell
  d = session_data(s)
  run$signal$aborted = TRUE
  run$signal$reason = reason
  if (length(run$transfers)) tryCatch(reactor_cancel(run$transfers), error = function(e) NULL)
  for (cid in run$children) {
    cs = session_by_id(cid)
    cl = if (is.null(cs)) NULL else session_live(cs)
    if (!is.null(cl$run)) run_abort(cl$run, reason)
  }
  streaming = run$status %in% c("requesting", "streaming")
  if (isTRUE(run$busy) && streaming && !isTRUE(run$request_closed)) {
    run$request_closed = TRUE
    msg = tryCatch(run$acc$message(), error = function(e) NULL)
    if (is.null(msg)) {
      msg = msg_assistant(list(), api = run$model$api %||% "unknown",
                          provider = run$model$provider %||% "unknown",
                          model = run$model$id %||% "unknown", stop_reason = "aborted")
    }
    msg$stop_reason = "aborted"
    msg$error_message = paste0("aborted (", reason, ")")
    session_append(s, entry_message(msg))
    run_emit(run, "message_end", role = "assistant", message = msg)
  }
  d$dropped = c(d$dropped, d$queue$steer, d$queue$follow_up)
  d$queue = list(steer = list(), follow_up = list())
  run_settle(run, "aborted")
  invisible(run)
}

#' Touch the session's lock every 10 minutes while the run is live (IC-59)
#' @noRd
run_heartbeat = function(run) {
  if (isTRUE(run$settled)) return(invisible(NULL))
  live = session_live(run$shell)
  if (!is.null(live$store)) tryCatch(store_heartbeat(live$store), error = function(e) NULL)
  run$timers = c(run$timers, reactor_timer(at = reactor_now() + 600,
                                           fn = function() run_heartbeat(run), run = run))
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(agent-loop|agent-run|agent-dispatch|session-budget|session-store)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 613 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/agent-run.R tests/testthat/fixtures/oracles/report02/loop.json tests/testthat/test-agent-loop.R tests/testthat/test-agent-run.R tests/testthat/test-agent-dispatch.R tests/testthat/test-session-budget.R tests/testthat/test-session-store.R
git commit -m "feat(agent): add the run engine on the reactor"
```

---

### Task 11: `gptr_usage()`

**Files:**

- Modify: `R/session-budget.R`
- Test: `tests/testthat/test-session-budget.R`

**Interfaces:**

Consumes:

- P01: `check_choice()`, `check_flag()`, `new_listing()`; P05: `usage_log()` (the process System 1 log), `usage_empty()`.
- Tasks 2-4: `usage_conform()`, `usage_totals()`, `format_count()`, `ledger_empty()`; Task 3: `live_all()`, `session_data()`.

Produces:

- The export `gptr_usage(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE)` -> a `gptr_usage` data frame (`group`, `requests`, `input`, `output`, `cache_read`, `cache_write`, `cost`) with attribute `totals` and a footer, or with `detail = TRUE` the `gptr_ledger` (`request_id`, `component`, `tokens`, `cached`); `usage_sessions(x)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-session-budget.R`:

```r

# ---------------------------------------------------------------- usage (gptr_usage)

test_that("gptr_usage() aggregates by session, agent, model and route, counting each request once",
          {
  root = test_session()
  child = test_session(kind = "child", parent = root)
  rid = session_data(root)$id
  cid = session_data(child)$id
  usage_add(root, usage_fixture(rid, "q1", cost = 1))
  usage_add(child, usage_fixture(cid, "q2", cost = 2, agent = "stats", route = "plan-cli"))
  u = gptr_usage(list(root, child))
  expect_s3_class(u, "gptr_usage")
  expect_named(u, c("group", "requests", "input", "output", "cache_read", "cache_write", "cost"))
  expect_identical(sort(u$group), sort(c(rid, cid)))
  expect_equal(sum(u$cost), 3)
  expect_equal(attr(u, "totals")[["requests"]], 2)
  expect_identical(sort(gptr_usage(root, by = "agent")$group), c("main", "stats"))
  expect_identical(gptr_usage(root, by = "model")$group, "fake/fake-1")
  expect_identical(sort(gptr_usage(root, by = "route")$group), c("api", "plan-cli"))
})

test_that("gptr_usage() validates x, by and detail", {
  expect_error(gptr_usage(42), class = "gptr_error_invalid_argument")
  expect_error(gptr_usage(by = "colour"), class = "gptr_error_invalid_argument")
  expect_error(gptr_usage(detail = NA), class = "gptr_error_invalid_argument")
})

test_that("gptr_usage() with x = NULL covers the live sessions of this process", {
  s = test_session()
  usage_add(s, usage_fixture(session_data(s)$id, "q-live-1"))
  expect_true(session_data(s)$id %in% gptr_usage()$group)
})

test_that("gptr_usage() counts rows whose group is NA (process-level System 1 rows)", {
  s = test_session()
  usage_add(s, usage_fixture(session_data(s)$id, "q-na", cost = 0.5, agent = NA_character_))
  u = gptr_usage(s, by = "agent")
  expect_identical(u$requests, 1L)
  expect_equal(u$cost, 0.5)
})

test_that("gptr_usage(detail = TRUE) returns the token ledger per request and component", {
  local_permissive()
  local_fake_provider(list("done"))
  s = test_session()
  run_text(s, "hi")
  led = gptr_usage(s, detail = TRUE)
  expect_s3_class(led, "gptr_ledger")
  expect_named(led, c("request_id", "component", "tokens", "cached"))
  expect_true("transcript" %in% led$component)
  expect_identical(unique(led$request_id), s$usage$request_id)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-budget$")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 68 ]`, with errors such as ``Error in `gptr_usage(list(root, child))`: could not find function "gptr_usage"``.

- [ ] **Step 3: Write the implementation**

Each request is counted once even though its row sits in the session and in every ancestor (root charging).

Append to `R/session-budget.R`:

```r
# ---------------------------------------------------------------------------- usage (gptr_usage)

#' Token usage and cost
#'
#' Aggregates the usage rows of sessions (children included, each request counted once) and, for
#' `x = NULL`, of every live session of this process plus the process System 1 log. Reads only.
#'
#' @param x A `gptr_session`, a list of sessions, or `NULL` (every live session of this process
#'   and the System 1 log).
#' @param by Grouping of the summary: `"session"`, `"agent"`, `"model"` or `"route"`.
#' @param detail `FALSE`: a `gptr_usage` data frame (`group`, `requests`, `input`, `output`,
#'   `cache_read`, `cache_write`, `cost`) with attribute `totals`; `TRUE`: the `gptr_ledger` per
#'   request and context component (`request_id`, `component`, `tokens`, `cached`).
#' @return A `gptr_usage` or `gptr_ledger` data frame.
#' @examples
#' gptr_usage()
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' gptr_usage(s)
#' @export
gptr_usage = function(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE) {
  by = check_choice(by, c("session", "agent", "model", "route"), "by")
  check_flag(detail, "detail")
  sessions = usage_sessions(x)
  if (detail) {
    rows = do.call(rbind, c(list(ledger_empty()), lapply(sessions,
                                                         function(s) session_data(s)$ledger)))
    rows = rows[!duplicated(rows[c("request_id", "component")]), , drop = FALSE]
    rownames(rows) = NULL
    return(new_listing(rows, "gptr_ledger"))
  }
  rows = do.call(rbind, c(list(usage_empty()), lapply(sessions, function(s) session_data(s)$usage)))
  if (is.null(x)) {
    s1 = tryCatch(usage_log(), error = function(e) NULL)
    if (is.data.frame(s1) && nrow(s1)) rows = rbind(rows, usage_conform(s1))
  }
  rows = rows[!duplicated(rows$request_id), , drop = FALSE]
  group = switch(by, session = rows$session, agent = rows$agent,
                 model = paste(rows$provider, rows$model, sep = "/"), route = rows$route)
  keys = unique(group)
  # %in%, not ==, and unnamed results: a group may be NA (process-level System 1 rows have no
  # session) and must still be counted; NA names would make data.frame() fail on its row names
  agg = function(col) {
    vapply(keys, function(k) sum(rows[[col]][group %in% k]), 1, USE.NAMES = FALSE)
  }
  df = data.frame(group = keys,
                  requests = vapply(keys, function(k) sum(group %in% k), 1L, USE.NAMES = FALSE),
                  input = agg("input"), output = agg("output"), cache_read = agg("cache_read"),
                  cache_write = agg("cache_write_5m") + agg("cache_write_1h"), cost = agg("cost"),
                  stringsAsFactors = FALSE)
  rownames(df) = NULL
  totals = usage_totals(rows)
  out = new_listing(df, "gptr_usage",
                    footer = sprintf("%d requests, %s tokens in, $%.4f",
                                     as.integer(totals[["requests"]]),
                                     format_count(totals[["input"]] + totals[["cache_read"]]),
                                     totals[["cost"]]))
  attr(out, "totals") = totals
  out
}

#' The sessions gptr_usage() reads: every live one for NULL, else the given ones
#' @noRd
usage_sessions = function(x) {
  if (is.null(x)) return(live_all())
  if (inherits(x, "gptr_session")) return(list(x))
  if (is.list(x) && length(x) && all(vapply(x, function(s) inherits(s, "gptr_session"),
                                            NA))) return(x)
  gptr_abort("`x` must be a gptr_session, a list of sessions or NULL", "invalid_argument",
             arg = "x",
             expected = "a gptr_session, a list of sessions or NULL")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-budget$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 86 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/session-budget.R tests/testthat/test-session-budget.R
git commit -m "feat(session): add gptr_usage()"
```

---

### Task 12: `gptr_fork()` and fork files

**Files:**

- Modify: `R/session-object.R`
- Modify: `R/session-store.R`
- Test: `tests/testthat/test-session-object.R`
- Test: `tests/testthat/test-session-store.R`

**Interfaces:**

Consumes:

- P01: `check_number()`, `check_choice()`, `check_class()`, `id_new()`, `gptr_inform()`; P02: `registry_add()`, `registry_get()`, `registry_names(kind, session = NULL)`.
- Tasks 3-5: `session_new()`, `session_data()`, `session_live()`, `session_emit()`, `entries_path()`, `path_turn()`, `final_text()`, `lock_held_elsewhere()`, `run_current()`.

Produces:

- The export `gptr_fork(s, at = NULL, envir = c("overlay", "shared"))` -> a new idle `gptr_session` (cut at the last closed boundary, turn `k`, `0` or an entry id; entry ids kept and re-chained; overlay `new.env(parent = <source home>)`; rank-0 specs re-registered; `session_before_fork` may cancel; `session_start` with reason `fork`).
- `store_fork(s, cut, new)` (lazy fork file with `parentSession` and `gptr.forkOf`), `fork_cut(d, at)`, `fork_boundaries(path)`, `overlay_new(home, id)`, `fork_copy_specs(src_id, new_id)`, `session_control_check(what, s = NULL)` (IC-53 item 3: model code may not act on another session without a human approval; it consumes the one-shot token `what` from `run$signal$control`; not `control_check()`, which is P08's).

- [ ] **Step 1: Write the failing test**

S21-S23 check the fork files; the object tests cover INFRA-14 (a listener on the fork never fires for the source; overlay writes never reach the source home).

Append to `tests/testthat/test-session-object.R`:

```r

# ---------------------------------------------------------------- forks (gptr_fork, INFRA-14)

fork_source = function(.env = parent.frame()) {
  local_permissive(.env = .env)
  local_fake_provider(list("A", "B", "C", "D"), .env = .env)
  home = new.env()
  home$x = 1
  s = test_session(home = home)
  run_text(s, "first")
  run_text(s, "second")
  list(s = s, home = home)
}

test_that("an overlay fork reads the source home and writes to its own overlay", {
  x = fork_source()
  f = gptr_fork(x$s)
  expect_false(identical(f$id, x$s$id))
  expect_identical(f$turns, 2L)
  expect_identical(f$text, "B")
  expect_identical(f$status, "idle")
  expect_identical(parent.env(f$envir), x$home)
  expect_identical(get("x", envir = f$envir), 1)
  assign("y", 2, envir = f$envir)
  expect_false(exists("y", envir = x$home, inherits = FALSE))
  expect_match(session_data(f)$home_label, "^overlay of ")
  expect_identical(gptr_fork(x$s, envir = "shared")$envir, x$home)
})

test_that("gptr_fork(at =) cuts at a turn, at 0 or at an entry id", {
  x = fork_source()
  f1 = gptr_fork(x$s, at = 1)
  expect_identical(f1$turns, 1L)
  expect_identical(f1$text, "A")
  expect_identical(gptr_fork(x$s, at = 0)$turns, 0L)
  expect_length(session_data(gptr_fork(x$s, at = 0))$entries, 0L)
  first_user = Filter(function(e) identical(e$type, "message"), session_data(x$s)$entries)[[1L]]
  f3 = gptr_fork(x$s, at = first_user$id)
  expect_identical(session_data(f3)$leaf, first_user$id)
  expect_error(gptr_fork(x$s, at = 9), class = "gptr_error_invalid_argument")
  expect_error(gptr_fork(x$s, at = "ffffffff"), class = "gptr_error_invalid_argument")
  expect_error(gptr_fork(x$s, envir = "copy"), class = "gptr_error_invalid_argument")
})

test_that("a listener on the fork never fires for the source; nothing live is shared", {
  x = fork_source()
  f = gptr_fork(x$s)
  fired = new.env()
  fired$ids = character()
  local_hook("message_end", function(event, ctx) {
    fired$ids = c(fired$ids, event$session)
    NULL
  }, session = f$id)
  run_text(x$s, "on the source")
  expect_false(x$s$id %in% fired$ids)
  run_text(f, "on the fork")
  expect_true(f$id %in% fired$ids)
  expect_false(identical(session_live(f)$ctx, session_live(x$s)$ctx))
  expect_identical(nrow(f$usage), 1L)
  expect_false(identical(session_data(f)$leaf, session_data(x$s)$leaf))
})

test_that("a running source is cut at its last closed boundary", {
  local_permissive()
  local_fake_provider(list("A", list(hang = TRUE)))
  s = test_session()
  run_text(s, "first")
  run = run_start(s, msg_user("second"))
  run_wait(list(run), timeout = 0.2)
  f = gptr_fork(s)
  expect_identical(f$turns, 1L)
  expect_identical(f$text, "A")
  run_abort(run)
})

test_that("a session_before_fork handler may cancel the fork", {
  x = fork_source()
  local_hook("session_before_fork", function(event, ctx) list(cancel = TRUE, reason = "not now"))
  expect_error(gptr_fork(x$s), "not now", class = "gptr_error_invalid_argument")
})

test_that("gptr_fork() emits session_start with reason fork to process-wide hooks", {
  x = fork_source()
  ev = local_events("session_start")
  f = gptr_fork(x$s)
  starts = ev(f)
  expect_length(starts, 1L)
  expect_identical(starts[[1L]]$reason, "fork")
})

test_that("rank-0 specs of the source are registered again for the fork", {
  x = fork_source()
  spec = gptr_tool("only_here", "A session tool", execute = function(input, ctx) "x")
  id = registry_add(spec, source = "session", rank = 0L, session = x$s$id)
  withr::defer(registry_remove(id))
  f = gptr_fork(x$s)
  expect_false(is.null(registry_get("tool", "only_here", session = f$id)))
})

test_that("a source without a kept home gives a fork without one, with a notice", {
  local_permissive()
  local_fake_provider(list("A"))
  g = function() {
    s = session_new("fake/fake-1", "auto", home = environment())
    session_run(s, msg_user("x"))
    s
  }
  s = g()
  withr::local_options(gptr.quiet = FALSE)
  expect_message({
    f = gptr_fork(s)
  }, class = "gptr_message_notice")
  expect_null(f$envir)
})

test_that("the fork keeps the values of the turns it copies", {
  x = fork_source()
  d = session_data(x$s)
  vals = d$values
  vals[[1L]] = list(turn = 1L, mode = "box", name = "a", address = NA_character_,
                    class = "character",
                    bytes = 56, value = "turn one")
  vals[[2L]] = list(turn = 2L, mode = "box", name = "b", address = NA_character_,
                    class = "character",
                    bytes = 56, value = "turn two")
  d$values = vals
  expect_identical(gptr_fork(x$s, at = 1)$value, "turn one")
  expect_identical(gptr_fork(x$s)$value, "turn two")
})

test_that("model code cannot fork another session without a human approval (IC-53)", {
  local_permissive()
  other = test_session()
  box = new.env()
  local_tool("forker", function(input, ctx) {
    box$err = tryCatch(gptr_fork(other), error = function(e) e)
    box$own = gptr_fork(ctx$session)
    "done"
  })
  local_fake_provider(list(fake_tool("forker"), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_s3_class(box$err, "gptr_error_permission")
  expect_s3_class(box$own, "gptr_session")
  expect_s3_class(gptr_fork(other), "gptr_session")
})

test_that("an approved ask_human is a one-shot token for one control call", {
  local_gptr_options(interactive = TRUE)
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE, permission = function(request) list(decision = "allow"))
  })
  local_policy("mode", function(call, ctx) list(decision = "ask_human", reason = "control"))
  other = test_session()
  box = new.env()
  # the tool's risk record flags gptr_fork() in the `control` category, as P11's classifier
  # does for model code; the approval grants exactly one `gptr_fork` token
  control_risk = function(input, ctx) {
    list(level = 4L, categories = "control", paths = character(),
         flagged = data.frame(call = "gptr_fork(other)", fn = "gptr_fork", level = 4L,
                              category = "control", path = NA_character_,
                              path_class = NA_character_, stringsAsFactors = FALSE))
  }
  local_tool("forker", function(input, ctx) {
    box$first = tryCatch(gptr_fork(other), error = function(e) e)
    box$second = tryCatch(gptr_fork(other), error = function(e) e)
    "done"
  }, risk = control_risk)
  local_fake_provider(list(fake_tool("forker"), "ok"))
  run_text(test_session(mode = "manual"), "go")
  expect_s3_class(box$first, "gptr_session")
  expect_s3_class(box$second, "gptr_error_permission")
})
```

Append to `tests/testthat/test-session-store.R`:

```r

# ---------------------------------------------------------------- fork files

# The read tool of stored_run(). It is defined at the top level of the file on purpose: a closure
# created inside stored_run() would keep that frame, and with it the session, alive in the
# registry, so the garbage-collection tests below could never collect the session.
stored_read = function(input, ctx) {
  gptr_tool_result(paste("contents of", input$path), details = list(lines = 1L))
}

stored_run = function(.env = parent.frame()) {
  local_store(.env = .env)
  local_permissive(.env = .env)
  local_tool("read", stored_read,
             parameters = list(type = "object", required = I("path"),
                               properties = list(path = list(type = "string"))), .env = .env)
  local_fake_provider(list(fake_tool("read", path = "R/a.R"), "All done \u2713", "branch answer"),
                      .env = .env)
  s = test_session(home = globalenv())
  run_text(s, "Refactor a.R")
  s
}

test_that(oracle_title(store_recs, "S21"), {
  s = stored_run()
  f = gptr_fork(s)
  expect_null(f$file)
  run_text(f, "branch")
  expect_true(file.exists(f$file))
  expect_false(identical(f$file, s$file))
})

test_that(oracle_title(store_recs, "S22"), {
  s = stored_run()
  f = gptr_fork(s)
  run_text(f, "branch")
  hdr = json_decode(readLines(f$file, n = 1L, encoding = "UTF-8"))
  expect_identical(hdr$parentSession, s$file)
  expect_identical(hdr$gptr$forkOf$id, s$id)
  expect_identical(hdr$gptr$forkOf$entry, session_data(s)$leaf)
  expect_identical(hdr$gptr$forkOf$turn, 1L)
})

test_that(oracle_title(store_recs, "S23"), {
  s = stored_run()
  session_append(s, list(type = "label", raw = list(targetId = session_data(s)$leaf,
                                                    label = "start")))
  f = gptr_fork(s, at = session_data(s)$leaf)
  kept = vapply(session_data(f)$entries, function(e) e$id, "")
  src = Filter(function(e) !identical(e$type, "label"), entries_path(session_data(s)))
  expect_identical(kept, vapply(src, function(e) e$id, ""))
  expect_false("label" %in% vapply(session_data(f)$entries, function(e) e$type, ""))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-(object|store)$")'`

Expected: `[ FAIL 17 | WARN 0 | SKIP 0 | PASS 181 ]`, with errors such as ``Error in `gptr_fork(x$s)`: could not find function "gptr_fork"``.

- [ ] **Step 3: Write the implementation**

Pi's `createBranchedSession()` (report 02 §2.11; G3 finding 11) copies the path with ids kept and parents re-chained; the file is written at the fork's first own message.

Append to `R/session-object.R`:

```r
# ---------------------------------------------------------------------------- fork

#' Fork a session
#'
#' Creates a new idle session whose transcript is the source path up to a cut, with the same entry
#' ids. Nothing live is shared (listeners, queue, run, lock, usage); the fork's file is written
#' lazily at its first own message, with `parentSession` and `gptr.forkOf` in its header. The
#' fork's workspace is an overlay of the source's kept home: it reads every object of the source
#' at zero cost, and its writes stay in the overlay.
#'
#' @param s A `gptr_session`: the source.
#' @param at `NULL` (the last closed boundary; a running source is cut there), an integer `k >= 0`
#'   (the end of turn `k`; `0` is an empty conversation) or an entry id.
#' @param envir `"overlay"`: the fork evaluates in `new.env(parent = <source home>)`;
#'   `"shared"`: the same home.
#' @return A new idle `gptr_session`.
#' @examples
#' s = gptr_last()
#' if (!is.null(s)) {
#'   f = gptr_fork(s)
#'   f$turns
#' }
#' @examplesIf exists("gptr", mode = "function")
#' fake = gptr_fake_provider(list("A", "B"))
#' s = gptr("first", model = fake, envir = new.env())
#' f = gptr_fork(s)
#' f |> gptr("branch")
#' c(s$turns, f$turns)
#' @export
gptr_fork = function(s, at = NULL, envir = c("overlay", "shared")) {
  check_class(s, "gptr_session", "s")
  envir = check_choice(envir, c("overlay", "shared"), "envir")
  session_control_check("gptr_fork", s)
  if (!is.null(at) && !(is.character(at) && length(at) == 1L && !is.na(at))) {
    check_number(at, "at", min = 0, int = TRUE)
  }
  d = session_data(s)
  live = session_live(s)
  if (is.null(live) && !is.null(d$file) && lock_held_elsewhere(d$file)) {
    gptr_abort(paste0("session ", d$id, " is attached in another R process"), "busy",
               session = d$id)
  }
  dec = session_emit(s, "session_before_fork", source = d$id, at = at)
  if (is.list(dec) && isTRUE(dec$cancel)) {
    gptr_abort(paste0("gptr_fork() was cancelled by a session_before_fork handler: ",
                      dec$reason %||% "no reason given"),
               "invalid_argument", arg = "s", expected = "a session whose fork no handler cancels")
  }
  cut = fork_cut(d, at)
  home = if (is.null(live)) NULL else live$home
  if (is.null(home)) {
    gptr_inform(paste0("session ", d$id, " has no kept workspace, so each turn of the fork ",
                       "evaluates in the caller of that gptr() call"), "notice")
  }
  new_home = home
  if (!is.null(home) && identical(envir, "overlay")) new_home = overlay_new(home, d$id)
  fid = id_new("s", 10L)
  fork_copy_specs(d$id, fid)
  f = session_new(d$model, d$mode, home = new_home, kind = "chat", preset = d$preset,
                  opts = list(id = fid, thinking = d$thinking))
  store_fork(s, cut$entry, f)
  fd = session_data(f)
  fd$fork_of = list(id = d$id, entry = cut$entry, turn = cut$turn, file = d$file)
  fd$turns = cut$turn
  fd$frozen = d$frozen
  fd$rules = d$rules
  fd$last_text = final_text(entries_path(fd)) %||% NA_character_
  fd$values = Filter(function(v) as.integer(v$turn) <= cut$turn, d$values)
  session_emit(f, "session_start", reason = "fork")
  f
}

#' A fork overlay: reads fall through to the home, writes stay in the overlay (rule R2)
#' @noRd
overlay_new = function(home, id) {
  ov = new.env(parent = home)
  attr(ov, "gptr_overlay") = paste0("overlay of ", id)
  ov
}

#' Register the source's rank-0 specs again for the fork (never listeners)
#' @noRd
fork_copy_specs = function(src_id, new_id) {
  for (kind in c("provider", "model", "tool", "agent", "router")) {
    nms = tryCatch(registry_names(kind, session = src_id), error = function(e) character())
    for (nm in nms) {
      a = registry_get(kind, nm, session = src_id)
      b = registry_get(kind, nm, session = NULL)
      if (!is.null(a) && !identical(a, b)) {
        registry_add(a, source = "session", rank = 0L, session = new_id)
      }
    }
  }
  invisible(NULL)
}

#' Where a fork cuts the source path
#' @return `list(entry = <last kept entry id or NULL>, turn = int)`.
#' @noRd
fork_cut = function(d, at) {
  if (is.character(at)) {
    if (!exists(at, envir = d$index, inherits = FALSE)) {
      gptr_abort(paste0("entry ", at, " is not in session ", d$id), "invalid_argument", arg = "at",
                 expected = "an entry id of this session")
    }
    return(list(entry = at, turn = path_turn(entries_path(d, at))))
  }
  if (!is.null(at) && as.integer(at) == 0L) return(list(entry = NULL, turn = 0L))
  path = entries_path(d)
  b = fork_boundaries(path)
  if (is.null(at)) {
    if (!nrow(b)) return(list(entry = NULL, turn = 0L))
    i = max(b$index)
  } else {
    ok = b$index[b$turn == as.integer(at)]
    if (!length(ok)) {
      gptr_abort(paste0("turn ", at, " of session ", d$id, " has no closed boundary to fork at"),
                 "invalid_argument", arg = "at",
                 expected = paste0("a completed turn between 0 and ", d$turns))
    }
    i = max(ok)
  }
  list(entry = path[[i]]$id, turn = b$turn[b$index == i][1L])
}

#' Closed boundaries of a path: message positions where no tool call awaits its result
#' @return A data frame `index`, `turn`.
#' @noRd
fork_boundaries = function(path) {
  open = 0L
  turn = 0L
  idx = integer()
  trn = integer()
  for (i in seq_along(path)) {
    e = path[[i]]
    if (!identical(e$type, "message")) next
    m = e$message
    if (identical(m$role, "user")) {
      turn = as.integer(e$gptr$turn %||% (turn + 1L))
      next
    }
    if (identical(m$role, "assistant")) {
      if ((m$stop_reason %||% "stop") %in% c("error", "aborted")) next
      open = sum(vapply(m$content %||% list(), function(b) identical(b$type, "tool_call"), NA))
    }
    if (identical(m$role, "tool_result")) open = max(0L, open - 1L)
    if (open == 0L) {
      idx = c(idx, i)
      trn = c(trn, turn)
    }
  }
  data.frame(index = idx, turn = trn)
}

#' Model code may not reach a session other than the running one through gptr's control exports
#' (IC-53 item 3) unless the dispatcher approved exactly this call through an `ask_human`: a
#' one-shot token named after the export in `run$signal$control` (granted by
#' `perm_grant_control()`, the slot P08's `control_check()` also consumes; cleared when the call
#' ends). Not named control_check(), which is P08's.
#' @param what The export's name (the token it consumes).
#' @param s The target session, or NULL when unknown (always another session).
#' @noRd
session_control_check = function(what, s = NULL) {
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  if (!is.null(s) && identical(session_data(s)$id, run$session)) return(invisible(TRUE))
  tokens = run$signal$control %||% character()
  i = match(what, tokens)
  if (!is.na(i)) {
    run$signal$control = tokens[-i]
    return(invisible(TRUE))
  }
  gptr_abort(paste0(what, "() on another session is refused while a run executes model code; ",
                    "a person must approve it"),
             "permission", action = what, tool = run$tool_call$name %||% "r", risk = NULL,
             how_to_allow = "call it outside the run, or approve it when asked",
             session = run$session)
}
```

Append to `R/session-store.R`:

```r

# ---------------------------------------------------------------------------- fork files

#' Copy the source path up to `cut` (an entry id or NULL) into `new`: ids kept, labels dropped,
#' parents re-chained (Pi `createBranchedSession`, G3 finding 11); the file is written lazily
#' @noRd
store_fork = function(s, cut, new) {
  d = session_data(s)
  nd = session_data(new)
  path = if (is.null(cut)) list() else entries_path(d, cut)
  path = Filter(function(e) !identical(e$type, "label"), path)
  prev = NULL
  for (i in seq_along(path)) {
    path[[i]]["parent_id"] = list(prev)
    prev = path[[i]]$id
  }
  nd$entries = path
  nd$index = new.env(parent = emptyenv())
  for (i in seq_along(path)) assign(path[[i]]$id, i, envir = nd$index)
  nd$leaf = prev
  invisible(new)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-(object|store)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 227 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/session-object.R R/session-store.R tests/testthat/test-session-object.R tests/testthat/test-session-store.R
git commit -m "feat(session): add gptr_fork() and fork files"
```

---

### Task 13: Reader, resume, listing and crash safety

**Files:**

- Modify: `R/session-store.R`
- Modify: `R/session-object.R`
- Test: `tests/testthat/test-session-live.R`
- Test: `tests/testthat/test-session-store.R`

**Interfaces:**

Consumes:

- P01: `json_decode()`, `msg_from_json(x)`, `msg_operator()`, `msg_text()`, `path_key(path)`, `project_root()`, `workspace_root(create = TRUE)`, `new_listing()`, `as_utf8()`; P02: `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, `gptr_spec()`, `registry_diagnostic()`; P04: `proc_run(command, args = character(), input = NULL, timeout = 120, env = NULL, wd = NULL, echo = FALSE)` (only `git ls-files`); P05: `usage_row()`.
- Tests: `rscript_path()` (P01), processx (a child killed with SIGKILL), pkgload inside the generated child script only.
- Tasks 3-12: `session_new()`, `session_attach()`, `store_open()`, `home_keep()`, `overlay_new()`, `entries_path()`, `path_turn()`, `final_text()`, `usage_conform()`, `session_control_check()`, `live_all()`.

Produces:

- `store_read(path)` -> `list(header, entries)` (unparsable lines skipped with one diagnostic, orphans re-parented), `entry_from_json(x)`, `store_rebuild(path, home)` -> `gptr_session` (leaf = last entry; `idle` or `interrupted`; a fork gets a fresh overlay of `home`, IC-46; a foreign or git-tracked file gets a fresh prompt and `imported` user turns, IC-52), `store_find(id)`, `sessions_dir()`.
- The built-in `store` record `jsonl` (`builtin_store()`, declared as `builtin:store`, IC-69).
- The exports `gptr_sessions(project = TRUE)` -> `gptr_sessions` listing (`id`, `file`, `created`, `updated`, `turns`, `model`, `status`, `title`, `live`) and `gptr_resume(x = NULL, envir = parent.frame(), block = NULL, child = NULL)`.
- The replay table: `session_replay_bind(block, s, child = NULL)`, `replay_lookup(block, child = NULL)`, `replay_key()`.

- [ ] **Step 1: Write the failing test**

The two crash tests start a child R process with `rscript_path()` that loads the package sources (`pkgload::load_all()` appears only in the generated script text) and SIGKILL it mid-stream and mid-append; they skip on CRAN and on Windows. `package_src` is resolved when testthat sources the file, before `local_store()` changes the working directory. The Pi file of S18-S20 is a real Pi v3 session (a `label` and a `branch_summary` entry) that must be read and written back unchanged.

Append to `tests/testthat/test-session-live.R`:

```r

test_that("continuing a same-process duplicate with a run is split brain", {
  local_permissive()
  local_fake_provider(list("a"))
  s = test_session()
  run_text(s, "one")
  copy = unserialize(serialize(s, NULL))
  expect_error(run_start(copy, msg_user("again")), class = "gptr_error_split_brain")
  expect_error(gptr_resume(copy), class = "gptr_error_split_brain")
})

test_that("a copy snapshotted while running is attached as aborted (reason detached)", {
  local_permissive()
  local_fake_provider(list(list(hang = TRUE), "resumed"))
  s = test_session()
  run = run_start(s, msg_user("go"))
  snap = serialize(s, NULL)
  run_abort(run)
  other = test_session()
  rm(s, run)
  invisible(gc())
  copy = unserialize(snap)
  gptr_resume(copy)
  expect_identical(copy$status, "aborted")
  expect_identical(copy$reason, "detached")
})

test_that("a file locked by another live process is not resumed and leaves no live session", {
  skip_on_cran()
  local_store()
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"),
                           supervise = supervise_default())
  withr::defer(p$kill())
  s = test_session()
  session_append(s, entry_custom("test.note", list(i = 1L)))
  file = session_data(s)$file
  id = session_data(s)$id
  last = test_session()
  rm(s)
  invisible(gc())
  created = as.numeric(ps::ps_create_time(ps::ps_handle(p$get_pid())))
  dir.create(lock_path(file), showWarnings = FALSE)
  write_atomic(file.path(lock_path(file), "pid"),
               c(as.character(p$get_pid()), format(created, digits = 17)))
  expect_error(gptr_resume(file, envir = new.env()), class = "gptr_error_split_brain")
  expect_null(session_by_id(id))
  expect_identical(gptr_last(), last)
  expect_error(gptr_resume(id, envir = new.env()), class = "gptr_error_split_brain")
})
```

Append to `tests/testthat/test-session-store.R`:

```r

# ---------------------------------------------------------------- reading and rebuilding

path_of_entries = function(entries, leaf) {
  d = list(entries = entries, index = new.env(parent = emptyenv()), leaf = leaf)
  for (i in seq_along(entries)) assign(entries[[i]]$id, i, envir = d$index)
  entries_path(d)
}

test_that(oracle_title(store_recs, "S11"), {
  s = stored_run()
  x = store_read(s$file)
  path = path_of_entries(x$entries, x$entries[[length(x$entries)]]$id)
  expect_identical(vapply(path_messages(path), function(m) m$role, ""), roles(s))
})

test_that(oracle_title(store_recs, "S12"), {
  s = stored_run()
  lines = readLines(s$file, encoding = "UTF-8")[-1L]
  expect_identical(vapply(store_read(s$file)$entries, entry_json_line, ""), lines)
})

test_that(oracle_title(store_recs, "S13"), {
  s = stored_run()
  expect_identical(rebuild_model(store_read(s$file)$entries), s$model)
})

test_that(oracle_title(store_recs, "S14"), {
  s = stored_run()
  x = store_read(s$file)
  last = x$entries[[length(x$entries)]]$message
  expect_identical(msg_text(last), "All done \u2713")
  expect_identical(Encoding(msg_text(last)), "UTF-8")
})

branch_in_file = function(.env = parent.frame()) {
  local_store(.env = .env)
  local_permissive(.env = .env)
  local_fake_provider(list("first", "second", "third"), .env = .env)
  s = test_session(home = globalenv())
  run_text(s, "one")
  snap = serialize(s, NULL)
  run_text(s, "two")
  main_leaf = session_data(s)$leaf
  file = s$file
  other = test_session()
  rm(s)
  invisible(gc())
  copy = unserialize(snap)
  run_text(copy, "two, rephrased")
  list(copy = copy, file = file, main_leaf = main_leaf, other = other)
}

test_that(oracle_title(store_recs, "S15"), {
  b = branch_in_file()
  x = store_read(b$file)
  users = Filter(function(e) identical(e$type, "message") && identical(e$message$role, "user"),
                 x$entries)
  kids = Filter(function(e) identical(e$parent_id, users[[2L]]$parent_id), x$entries)
  expect_length(kids, 2L)
})

test_that(oracle_title(store_recs, "S16"), {
  b = branch_in_file()
  x = store_read(b$file)
  expect_identical(length(path_of_entries(x$entries, b$main_leaf)),
                   length(path_of_entries(x$entries, session_data(b$copy)$leaf)))
})

test_that(oracle_title(store_recs, "S17"), {
  b = branch_in_file()
  expect_false(identical(session_data(b$copy)$leaf, b$main_leaf))
  expect_identical(b$copy$text, "third")
})

pi_file = function(dir) {
  path = file.path(dir, "pi-session.jsonl")
  lines = c(
    paste0('{"type":"session","version":3,"id":"01a0ef8c-ce95-7666-a2d3-93e232db4a44",',
           '"timestamp":"2026-09-29T23:42:57.689Z","cwd":"/home/me/proj"}'),
    paste0('{"type":"message","id":"dcadc3e4","parentId":null,',
           '"timestamp":"2026-09-29T23:42:57.824Z","message":{"role":"user",',
           '"content":[{"type":"text","text":"What does R/a.R do?"}],"timestamp":1790725377787}}'),
    paste0('{"type":"message","id":"1078c0bc","parentId":"dcadc3e4",',
           '"timestamp":"2026-09-29T23:42:57.939Z","message":{"role":"assistant",',
           '"content":[{"type":"text","text":"It assigns 1 to x."}],"api":"fake",',
           '"provider":"fake","model":"fake-1","usage":{"input":10,"output":5,"cacheRead":0,',
           '"cacheWrite":0,"totalTokens":15,"cost":{"input":0,"output":0,"cacheRead":0,',
           '"cacheWrite":0,"total":0}},"stopReason":"stop","timestamp":1790725377940}}'),
    paste0('{"type":"label","id":"67b57f16","parentId":"1078c0bc",',
           '"timestamp":"2026-09-29T23:42:57.944Z","targetId":"dcadc3e4","label":"start"}'),
    paste0('{"type":"branch_summary","id":"6aafe2ca","parentId":"67b57f16",',
           '"timestamp":"2026-09-29T23:42:57.945Z","fromId":"1078c0bc",',
           '"summary":"Tried X on the other branch."}'))
  writeLines(lines, path, useBytes = TRUE)
  path
}

test_that(oracle_title(store_recs, "S18"), {
  x = store_read(pi_file(withr::local_tempdir()))
  bs = Filter(function(e) identical(e$type, "branch_summary"), x$entries)
  expect_length(bs, 1L)
  expect_identical(bs[[1L]]$raw$fromId, "1078c0bc")
  expect_match(entry_json_line(bs[[1L]]), "\"fromId\":\"1078c0bc\"", fixed = TRUE)
})

test_that(oracle_title(store_recs, "S19"), {
  local_fake_provider(list("x"))
  x = store_read(pi_file(withr::local_tempdir()))
  msgs = project_messages(x$entries, x$entries[[length(x$entries)]]$id,
                          model_resolve("fake/fake-1"))
  expect_identical(vapply(msgs, function(m) m$role, ""), c("user", "assistant"))
})

test_that(oracle_title(store_recs, "S20"), {
  x = store_read(pi_file(withr::local_tempdir()))
  expect_true("label" %in% vapply(x$entries, function(e) e$type, ""))
  expect_identical(x$header$version, 3L)
})

test_that(oracle_title(store_recs, "S24"), {
  s = stored_run()
  f = gptr_fork(s)
  run_text(f, "branch")
  x = store_read(f$file)
  cut = session_data(s)$leaf
  m = model_resolve("fake/fake-1")
  wire = function(msgs) vapply(msgs, function(msg) json_encode(msg_to_json(msg)), "")
  expect_identical(wire(project_messages(x$entries, cut, m)),
                   wire(project_messages(session_data(s)$entries, cut, m)))
})

test_that(oracle_title(store_recs, "S32"), {
  s = stored_run()
  tr = Filter(function(e) identical(e$type, "message") && identical(e$message$role, "tool_result"),
              store_read(s$file)$entries)
  expect_identical(tr[[1L]]$message$details$lines, 1L)
})

test_that("every report 02 store check has a test", {
  expect_oracles_covered(store_recs, "test-session-store.R")
})

# ---------------------------------------------------------------- crash safety (INFRA-13, IC-59)

test_that("a torn last line is recovered at resume; three appends stay connected", {
  s = stored_run()
  file = s$file
  cat("{\"type\":\"message\",\"id\":\"deadbeef\",\"parentId\":\"x", file = file, append = TRUE)
  other = test_session()
  rm(s)
  invisible(gc())
  r = gptr_resume(file, envir = new.env())
  types = vapply(session_data(r)$entries, function(e) e$custom_type %||% e$type, "")
  expect_true("gptr.recovered" %in% types)
  for (i in 1:3) session_append(r, entry_custom("test.after", list(i = i)))
  x = store_read(file)
  ids = vapply(x$entries, function(e) e$id, "")
  parents = vapply(x$entries[-1L], function(e) e$parent_id %||% NA_character_, "")
  expect_true(all(parents %in% ids))
  expect_identical(sum(vapply(x$entries, function(e) identical(e$custom_type, "test.after"), NA)),
                   3L)
  expect_false(any(duplicated(ids)))
})

test_that("an unparsable middle line is skipped and its children re-parented", {
  s = stored_run()
  lines = readLines(s$file, encoding = "UTF-8")
  lines[[3L]] = "{not json"
  writeLines(lines, s$file, useBytes = TRUE)
  x = store_read(s$file)
  ids = vapply(x$entries, function(e) e$id, "")
  expect_length(x$entries, length(lines) - 2L)
  expect_true(all(vapply(x$entries[-1L], function(e) e$parent_id %in% ids, NA)))
})

# The package source tree, resolved when testthat sources this file (the working directory is
# tests/testthat then; local_store() changes it inside the tests). Under R CMD check there are no
# sources and the two crash tests skip.
package_src = normalizePath(testthat::test_path("..", ".."), winslash = "/", mustWork = FALSE)

# A child script that loads the package sources (pkgload::load_all() exists only in this
# generated text, IC-71) and runs `body` against the store of project `dir`.
child_script = function(dir, body) {
  skip_if_not(file.exists(file.path(package_src, "DESCRIPTION")), "package sources not found")
  skip_if_not_installed("pkgload")
  script = tempfile(fileext = ".R")
  writeLines(c(sprintf("pkgload::load_all(%s, quiet = TRUE)", deparse(package_src)),
               sprintf(paste0("options(gptr.project_root = %s, gptr.unsafe_no_permissions = TRUE, ",
                              "gptr.quiet = TRUE)"), deparse(dir)),
               body), script)
  script
}

wait_ready = function(p) {
  out = character()
  deadline = Sys.time() + 60
  while (!any(grepl("^READY", out)) && Sys.time() < deadline && p$is_alive()) {
    p$poll_io(1000)
    out = c(out, p$read_output_lines())
  }
  line = grep("^READY", out, value = TRUE)
  if (!length(line)) return(NULL)
  trimws(sub("^READY ", "", line[[1L]]))
}

test_that("SIGKILL mid-stream: resume parses, keeps the last complete message, no duplicate", {
  skip_on_cran()
  skip_on_os("windows")
  dir = local_store()
  script = child_script(dir, c(
    "long = list(text = strrep('x', 4000), gap = 0.05, chunk = 10)",
    "fake = gptr_fake_provider(list('first answer', long))",
    "gptr_register(fake)",
    "s = session_new('fake/fake-1', 'auto', home = globalenv())",
    "session_run(s, msg_user('one'))",
    "flag = new.env()",
    "hook_add('message_update', function(event, ctx) {",
    "  if (is.null(flag$done)) {",
    "    flag$done = TRUE",
    "    cat('READY', session_data(s)$file, '\\n')",
    "    flush(stdout())",
    "  }",
    "  NULL",
    "})",
    "session_run(s, msg_user('two'))"))
  p = processx::process$new(rscript_path(), c("--vanilla", script), stdout = "|", stderr = "|",
                            supervise = supervise_default())
  withr::defer(if (p$is_alive()) p$kill())
  file = wait_ready(p)
  skip_if(is.null(file), "the child did not start streaming")
  p$kill()
  r = gptr_resume(file, envir = new.env())
  ids = vapply(session_data(r)$entries, function(e) e$id, "")
  expect_false(any(duplicated(ids)))
  expect_identical(r$status, "interrupted")
  expect_identical(msg_text(r$messages[[length(r$messages)]]), "two")
  expect_true(any(vapply(r$messages, function(m) identical(msg_text(m), "first answer"), NA)))
})

test_that("SIGKILL mid-append, resume, three appends: all present and the tree connected (IC-59)", {
  skip_on_cran()
  skip_on_os("windows")
  dir = local_store()
  script = child_script(dir, c(
    "s = session_new('fake/fake-1', 'auto', home = globalenv())",
    "i = 0L",
    "repeat {",
    "  i = i + 1L",
    "  session_append(s, entry_custom('test.note', list(i = i, pad = strrep('y', 4000))))",
    "  if (i == 50L) { cat('READY', session_data(s)$file, '\\n'); flush(stdout()) }",
    "}"))
  p = processx::process$new(rscript_path(), c("--vanilla", script), stdout = "|", stderr = "|",
                            supervise = supervise_default())
  withr::defer(if (p$is_alive()) p$kill())
  file = wait_ready(p)
  skip_if(is.null(file), "the child did not start appending")
  Sys.sleep(0.2)
  p$kill()
  r = gptr_resume(file, envir = new.env())
  for (i in 1:3) session_append(r, entry_custom("test.after", list(i = i)))
  lines = readLines(file, encoding = "UTF-8", warn = FALSE)
  bad = sum(vapply(lines, function(l) is.null(tryCatch(json_decode(l), error = function(e) NULL)),
                   NA))
  expect_lte(bad, 1L)
  x = store_read(file)
  ids = vapply(x$entries, function(e) e$id, "")
  parents = vapply(x$entries[-1L], function(e) e$parent_id %||% NA_character_, "")
  expect_true(all(parents %in% ids))
  expect_false(any(duplicated(ids)))
  expect_identical(sum(vapply(x$entries, function(e) identical(e$custom_type, "test.after"), NA)),
                   3L)
})

# ---------------------------------------------------------------- listing and resume

test_that("the built-in store record is registered and selected by the store setting", {
  expect_false(is.null(registry_get("store", "jsonl")))
  expect_true(is.function(store_impl()$append))
})

test_that("gptr_sessions() lists stored sessions with their columns and live flag", {
  s = stored_run()
  x = gptr_sessions()
  expect_s3_class(x, "gptr_sessions")
  expect_named(x, c("id", "file", "created", "updated", "turns", "model", "status", "title",
                    "live"))
  row = x[x$id == s$id, ]
  expect_identical(row$turns, 1L)
  expect_identical(row$title, "Refactor a.R")
  expect_identical(row$status, "idle")
  expect_identical(row$model, "fake/fake-1")
  expect_true(row$live)
  fresh = test_session()
  expect_false(fresh$id %in% gptr_sessions()$id)
  expect_true(fresh$id %in% gptr_sessions(project = FALSE)$id)
  expect_error(gptr_sessions(project = "yes"), class = "gptr_error_invalid_argument")
})

test_that("gptr_resume() returns the live object for an id, a path or NULL", {
  s = stored_run()
  expect_identical(gptr_resume(s$id), s)
  expect_identical(gptr_resume(s$file), s)
  expect_identical(gptr_resume(), s)
  expect_identical(gptr_resume(s), s)
})

test_that("gptr_resume() rebuilds a stored session with its history, status, model and turns", {
  s = stored_run()
  file = s$file
  id = s$id
  msgs = roles(s)
  ev = local_events("session_start")
  other = test_session()
  rm(s)
  invisible(gc())
  r = gptr_resume(id, envir = globalenv())
  expect_identical(r$id, id)
  expect_identical(roles(r), msgs)
  expect_identical(r$status, "idle")
  expect_identical(r$text, "All done \u2713")
  expect_identical(r$model, "fake/fake-1")
  expect_identical(r$turns, 1L)
  expect_identical(r$envir, globalenv())
  expect_identical(nrow(r$usage), 2L)
  expect_true(nzchar(session_data(r)$frozen$tools_json))
  expect_identical(ev(r)[[1L]]$reason, "resume")
  run_text(r, "and then?")
  expect_identical(r$turns, 2L)
})

test_that("a rebuilt fork gets a fresh overlay of envir (IC-46)", {
  s = stored_run()
  f = gptr_fork(s)
  run_text(f, "branch")
  file = f$file
  other = test_session()
  rm(f)
  invisible(gc())
  home = new.env()
  r = gptr_resume(file, envir = home)
  expect_identical(parent.env(r$envir), home)
  expect_identical(session_data(r)$fork_of$id, s$id)
})

test_that("a file from another project gets a fresh prompt and imported turns (IC-52)", {
  s = stored_run()
  lines = readLines(s$file, encoding = "UTF-8")
  hdr = json_decode(lines[[1L]])
  hdr$cwd = "/nonexistent/elsewhere"
  hdr$id = "s00000000aa"
  lines[[1L]] = json_encode(hdr)
  foreign = file.path(dirname(s$file), "20260101T000000_s00000000aa.jsonl")
  writeLines(lines, foreign, useBytes = TRUE)
  r = gptr_resume(foreign, envir = new.env())
  expect_identical(length(session_data(r)$frozen), 0L)
  expect_identical(r$messages[[1L]]$source, "imported")
})

test_that("gptr_resume() validates x", {
  local_store()
  expect_error(gptr_resume("s9999999999"), class = "gptr_error_invalid_argument")
  expect_error(gptr_resume(42), class = "gptr_error_invalid_argument")
  expect_error(gptr_resume(), class = "gptr_error_invalid_argument")
})

test_that("gptr_resume(block =) returns the session replay bound to the block, never a fallback", {
  s = test_session()
  session_replay_bind("6413d0", s)
  expect_identical(replay_lookup("6413d0"), s)
  expect_identical(gptr_resume(block = "6413d0"), s)
  session_replay_bind("team01", s, child = "stats")
  expect_identical(gptr_resume(block = "team01", child = "stats"), s)
  err = expect_error(gptr_resume(block = "ffffff"), class = "gptr_error_replay_unbound")
  expect_s3_class(err, "gptr_error_not_recorded")
  expect_identical(err$block, "ffffff")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-(live|store)$")'`

Expected: `[ FAIL 26 | WARN 0 | SKIP 0 | PASS 116 ]`, with errors such as ``Error in `gptr_resume(copy)`: could not find function "gptr_resume"`` and ``Error in `store_read(s$file)`: could not find function "store_read"``.

- [ ] **Step 3: Write the implementation**

`gptr_resume(block =)` never falls back to `envir`: an unbound block is `gptr_error_replay_unbound` (IC-46).

Append to `R/session-store.R`:

```r

# ---------------------------------------------------------------------------- the store record

on_load(ext_declare_builtin("store", builtin_store, replaceable = FALSE))

#' The built-in `store` record `jsonl` (kind `store`, IC-69), declared as `builtin:store`
#' @noRd
builtin_store = function(gptr) {
  gptr$register(gptr_spec("store", "jsonl", open = store_open, append = store_append,
                          read = store_read, fork = store_fork))
  invisible(NULL)
}

# ---------------------------------------------------------------------------- reading

#' Read a session file: the header and the entries (R shape)
#'
#' Unparsable lines (a torn last line, a hand edit) are skipped with one diagnostic; an entry whose
#' parent id is missing is re-parented to the nearest earlier valid entry.
#' @return `list(header, entries)`.
#' @noRd
store_read = function(path) {
  lines = readLines(path, encoding = "UTF-8", warn = FALSE)
  lines = lines[nzchar(trimws(lines))]
  header = NULL
  entries = vector("list", length(lines))
  n = 0L
  bad = 0L
  for (line in lines) {
    obj = tryCatch(json_decode(line), error = function(e) NULL)
    if (!is.list(obj) || is.null(obj$type)) {
      bad = bad + 1L
      next
    }
    if (is.null(header) && identical(obj$type, "session")) {
      header = obj
      next
    }
    n = n + 1L
    entries[[n]] = entry_from_json(obj)
  }
  entries = entries[seq_len(n)]
  if (bad > 0L) {
    registry_diagnostic("session", "store_read", "torn_line",
                        paste0("skipped ", bad, " unparsable line(s) in ", basename(path)))
  }
  if (is.null(header)) {
    gptr_abort(paste0("not a gptr or Pi session file: ", basename(path)), "invalid_argument",
               arg = "x", expected = "a session JSONL file")
  }
  seen = new.env(parent = emptyenv())
  prev = NULL
  for (i in seq_along(entries)) {
    p = entries[[i]]$parent_id
    if (!is.null(p) && !exists(p, envir = seen,
                               inherits = FALSE)) entries[[i]]["parent_id"] = list(prev)
    prev = entries[[i]]$id
    assign(prev, TRUE, envir = seen)
  }
  list(header = header, entries = entries)
}

#' An entry from its JSON shape; unknown types (Pi's label, branch_summary, ...) keep their
#' fields under `raw` and are written back unchanged
#' @noRd
entry_from_json = function(x) {
  e = list(type = x$type, id = x$id)
  e["parent_id"] = list(x$parentId)
  e$timestamp = x$timestamp
  rest = x[setdiff(names(x), c("type", "id", "parentId", "timestamp"))]
  body = switch(x$type %||% "",
    message = list(message = msg_from_json(x$message), gptr = x$gptr),
    custom_message = if (identical(x$customType, "gptr.operator")) {
      list(custom_type = "gptr.operator", message = operator_from_json(x))
    } else {
      list(raw = rest)
    },
    model_change = list(provider = x$provider, model_id = x$modelId, gptr = x$gptr),
    thinking_level_change = list(thinking_level = x$thinkingLevel),
    compaction = list(summary = x$summary, first_kept_entry_id = x$firstKeptEntryId,
                      tokens_before = x$tokensBefore, details = x$details,
                      usage = if (is.null(x$usage)) NULL else entry_usage_from_json(x$usage),
                      gptr = compaction_gptr_from_json(x$gptr)),
    custom = list(custom_type = x$customType, data = x$data),
    list(raw = rest))
  c(e, drop_null(body))
}

#' An operator message from a `gptr.operator` custom_message entry
#' @noRd
operator_from_json = function(x) {
  text = paste(vapply(x$content %||% list(), function(b) b$text %||% "", ""), collapse = "\n")
  msg_operator(x$details$kind %||% "reminder", text, tool_add = x$details$toolAdd,
               origin_text = x$details$originText, timestamp = iso_ms(x$timestamp))
}

#' A usage record from its JSON shape (through P01's message mapping; not named
#' usage_from_json(), which is P01's own helper inside msg_from_json())
#' @noRd
entry_usage_from_json = function(x) {
  msg_from_json(list(role = "assistant", content = list(), api = "x", provider = "x", model = "x",
                     usage = x, stopReason = "stop", timestamp = 0))$usage
}

#' Content blocks from their JSON shape (through P01's message mapping)
#' @noRd
blocks_from_json = function(x) {
  msg_from_json(list(role = "user", content = x, timestamp = 0))$content
}

#' The `gptr` object of a compaction entry with its context blocks in R shape
#' @noRd
compaction_gptr_from_json = function(g) {
  if (is.null(g)) return(NULL)
  if (!is.null(g$blocks)) g$blocks = blocks_from_json(g$blocks)
  g
}

#' Epoch milliseconds of an ISO 8601 UTC time (NULL for NULL)
#' @noRd
iso_ms = function(x) {
  if (is.null(x)) return(NULL)
  round(as.numeric(as.POSIXct(sub("Z$", "", x), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")) * 1000)
}

# ---------------------------------------------------------------------------- rebuilding

#' Rebuild a session from its file (resume)
#'
#' Leaf = the last entry; status `idle` when the tail is a final answer, else `interrupted`; a fork
#' gets a fresh overlay `new.env(parent = home)` (IC-46); a file from another project or tracked by
#' git is rebuilt with a freshly frozen prompt and its user turns marked `imported` (IC-52).
#' @noRd
store_rebuild = function(path, home) {
  x = store_read(path)
  h = x$header
  g = h$gptr %||% list()
  live_s = session_by_id(h$id)
  if (!is.null(live_s)) return(live_s)
  # split brain is checked before anything is registered: a half-built live session would
  # otherwise hold the recorded id, and the next gptr_resume() would return it unlocked
  if (lock_held_elsewhere(path)) {
    holder = lock_holder(lock_path(path))
    gptr_abort(paste0("session ", h$id, " is attached in another R process (pid ", holder$pid,
                      "); use gptr_fork() there, or resume it after that process ends"),
               "split_brain", id = h$id, holder_pid = holder$pid)
  }
  prev_last = the$last
  fork = g$forkOf
  keep_home = !is.null(fork) && !is.null(home) && home_keep(home)
  s = session_new(rebuild_model(x$entries) %||% "unknown/unknown", rebuild_mode(x$entries),
                  home = if (keep_home) overlay_new(home, fork$id) else home,
                  kind = g$kind %||% "chat", opts = list(id = h$id))
  d = session_data(s)
  d$parent_id = g$parent
  d$depth = as.integer(g$depth %||% 0L)
  d$created = (iso_ms(h$timestamp) %||% (1000 * as.numeric(Sys.time()))) / 1000
  d$file = normalizePath(path, winslash = "/", mustWork = TRUE)
  d$fork_of = if (is.null(fork)) NULL else c(fork, list(file = h$parentSession))
  entries = x$entries
  foreign = rebuild_foreign(h, path)
  if (foreign) {
    entries = lapply(entries, function(e) {
      if (identical(e$type, "message") && identical(e$message$role,
                                                    "user")) e$message$source = "imported"
      e
    })
  }
  d$entries = entries
  d$index = new.env(parent = emptyenv())
  for (i in seq_along(entries)) assign(entries[[i]]$id, i, envir = d$index)
  d$leaf = if (length(entries)) entries[[length(entries)]]$id else NULL
  path_e = entries_path(d)
  d$model = rebuild_model(path_e) %||% d$model
  d$turns = path_turn(path_e)
  d$last_text = final_text(path_e) %||% NA_character_
  d$status = rebuild_status(path_e)
  d$frozen = if (foreign) NULL else rebuild_frozen(entries)
  d$refreeze = foreign
  d$values = rebuild_values(path_e)
  d$usage = rebuild_usage(entries, d)
  live = session_live(s)
  st = tryCatch(store_open(s), error = function(e) e)
  if (inherits(st, "error")) {
    # a lock taken in between (or an unwritable file): release a lock this process took, undo
    # the registration, then re-signal
    lock_release(lock_path(d$file))
    live_forget(s)
    the$last = prev_last
    stop(st)
  }
  live$store = st
  if (length(d$frozen)) session_emit(s, "session_start", reason = "resume")
  s
}

#' The model of a rebuilt session: the last model of the given entries (store_rebuild() passes
#' the active path, so a sibling branch never decides it)
#' @noRd
rebuild_model = function(entries) {
  model = NULL
  for (e in entries) {
    if (identical(e$type, "model_change")) model = e$gptr$ref %||% paste0(e$provider, "/",
                                                                          e$model_id)
    if (identical(e$type, "message") && identical(e$message$role, "assistant") &&
        !is.null(e$message$provider)) {
      model = paste0(e$message$provider, "/", e$message$model)
    }
  }
  model
}

#' The mode of a rebuilt session: the last gptr.mode_change, else the `mode` setting
#' @noRd
rebuild_mode = function(entries) {
  mode = setting_get("mode", default = "manual")
  for (e in entries) {
    if (identical(e$type, "custom") && identical(e$custom_type,
                                                 "gptr.mode_change")) mode = e$data$to
  }
  mode
}

#' `idle` when the path ends with a final answer, else `interrupted`
#' @noRd
rebuild_status = function(path) {
  msgs = Filter(function(e) identical(e$type, "message"), path)
  if (!length(msgs)) return("idle")
  m = msgs[[length(msgs)]]$message
  final = identical(m$role, "assistant") && !(m$stop_reason %||% "stop") %in% c("error",
                                                                                "aborted") &&
    !any(vapply(m$content %||% list(), function(b) identical(b$type, "tool_call"), NA))
  if (final) "idle" else "interrupted"
}

#' The frozen prompt of a rebuilt session, from its gptr.frozen entry (NULL without one); the
#' fields are those P07's own restore reads back (`preset`, `model`, `t0`, `t1`, `tools_json`,
#' `tool_names`, `sections`)
#' @noRd
rebuild_frozen = function(entries) {
  for (e in entries) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.frozen")) {
      x = e$data
      return(list(preset = x$preset, model = x$model, t0 = x$t0 %||% "", t1 = x$t1 %||% "",
                  tools_json = x$toolsJson %||% "[]",
                  tool_names = as.character(unlist(x$toolNames)),
                  sections = frozen_sections_df(x$sections)))
    }
  }
  NULL
}

#' Value records of a rebuilt session (metadata only: held copies are not persisted)
#' @noRd
rebuild_values = function(path) {
  out = list()
  for (e in path) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.value")) {
      v = e$data
      out[[length(out) + 1L]] = list(turn = as.integer(v$turn), mode = v$mode, name = v$name,
                                     address = v$address %||% NA_character_, class = v$class,
                                     bytes = as.numeric(v$bytes %||% NA_real_), value = NULL)
    }
  }
  out
}

#' Usage rows of a rebuilt session, from its assistant messages
#' @noRd
rebuild_usage = function(entries, d) {
  rows = list(usage_empty())
  for (e in entries) {
    if (!identical(e$type, "message") || !identical(e$message$role, "assistant")) next
    m = e$message
    if (is.null(m$usage)) next
    row = usage_row(m, session = d$id, agent = "main", parent_id = d$parent_id %||% NA_character_,
                    started = .POSIXct((iso_ms(e$timestamp) %||% 0) / 1000, tz = "UTC"),
                    seconds = NA_real_, multiplier = 1)
    rows[[length(rows) + 1L]] = usage_conform(row)
  }
  do.call(rbind, rows)
}

#' Is a session file foreign to this project (another machine or tracked by git)? (IC-52)
#' @noRd
rebuild_foreign = function(h, path) {
  cwd = h$cwd %||% ""
  if (!nzchar(cwd) || !dir.exists(cwd)) return(TRUE)
  if (!identical(path_key(project_root(cwd)), path_key(project_root()))) return(TRUE)
  git_tracked(path)
}

#' Does git track this file? (only when the project root is a git work tree)
#' @noRd
git_tracked = function(path) {
  root = project_root()
  if (!dir.exists(file.path(root, ".git")) || !nzchar(Sys.which("git"))) return(FALSE)
  res = tryCatch(proc_run("git", c("-C", root, "ls-files", "--error-unmatch", path), timeout = 5),
                 error = function(e) NULL)
  isTRUE(res$status == 0L)
}

#' The stored file of a session id in the workspace store, or NULL
#' @noRd
store_find = function(id) {
  dir = sessions_dir()
  if (!dir.exists(dir)) return(NULL)
  f = list.files(dir, pattern = paste0("_", id, "[.]jsonl$"), full.names = TRUE)
  if (length(f)) f[[1L]] else NULL
}

#' The sessions directory of the workspace store (not created)
#' @noRd
sessions_dir = function() file.path(workspace_root(create = FALSE), "sessions")

# ---------------------------------------------------------------------------- list (gptr_sessions)

#' List stored sessions
#'
#' Lists the sessions of the workspace store (`.gptr/sessions/`, or `tempdir()/gptr/sessions/`
#' without a workspace), newest first. Reads only the header and the last lines of each file.
#'
#' @param project `TRUE`: the stored sessions; `FALSE`: also the live sessions of this process
#'   that are not in that store.
#' @return A `gptr_sessions` data frame: `id`, `file`, `created`, `updated`, `turns`, `model`,
#'   `status`, `title` (the first prompt, 60 characters), `live`.
#' @examples
#' gptr_sessions()
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' gptr_sessions()
#' @export
gptr_sessions = function(project = TRUE) {
  check_flag(project, "project")
  dir = sessions_dir()
  files = if (dir.exists(dir)) list.files(dir, pattern = "[.]jsonl$",
                                          full.names = TRUE) else character()
  # one damaged file (NUL bytes after a power loss, a file removed meanwhile) is left out, never
  # an error for the whole listing
  rows = Filter(Negate(is.null), lapply(files, function(f) {
    tryCatch(session_file_summary(f), error = function(e) NULL)
  }))
  df = do.call(rbind, c(list(sessions_empty()), rows))
  live = live_all()
  live_ids = vapply(live, function(x) session_data(x)$id, "")
  df$live = df$id %in% live_ids
  if (!project) {
    for (x in live[!(live_ids %in% df$id)]) df = rbind(df, session_live_summary(x))
  }
  df = df[order(df$updated, decreasing = TRUE), , drop = FALSE]
  rownames(df) = NULL
  new_listing(df, "gptr_sessions")
}

#' An empty gptr_sessions frame
#' @noRd
sessions_empty = function() {
  data.frame(id = character(), file = character(), created = .POSIXct(numeric(), tz = "UTC"),
             updated = .POSIXct(numeric(), tz = "UTC"), turns = integer(), model = character(),
             status = character(), title = character(), live = logical(), stringsAsFactors = FALSE)
}

#' One row of gptr_sessions() for a live session without a stored file
#' @noRd
session_live_summary = function(s) {
  d = session_data(s)
  first = Filter(function(m) identical(m$role, "user"), path_messages(entries_path(d)))
  data.frame(id = d$id, file = d$file %||% NA_character_, created = .POSIXct(d$created, tz = "UTC"),
             updated = .POSIXct(as.numeric(Sys.time()), tz = "UTC"), turns = d$turns,
             model = d$model, status = d$status,
             title = if (length(first)) substr(msg_text(first[[1L]]), 1L, 60L) else NA_character_,
             live = TRUE, stringsAsFactors = FALSE)
}

#' One row of gptr_sessions() from the head and the tail of a file
#' @noRd
session_file_summary = function(path) {
  head = file_chunk_lines(path, from_end = FALSE)
  if (!length(head)) return(NULL)
  hdr = tryCatch(json_decode(head[[1L]]), error = function(e) NULL)
  if (!is.list(hdr) || !identical(hdr$type, "session")) return(NULL)
  title = NA_character_
  for (line in head[-1L]) {
    obj = tryCatch(json_decode(line), error = function(e) NULL)
    if (is.list(obj) && identical(obj$type, "message") && identical(obj$message$role, "user")) {
      title = substr(json_user_text(obj$message), 1L, 60L)
      break
    }
  }
  model = NA_character_
  status = "idle"
  turns = NA_integer_
  last_msg = NULL
  for (line in rev(file_chunk_lines(path, from_end = TRUE))) {
    obj = tryCatch(json_decode(line), error = function(e) NULL)
    if (!is.list(obj) || !identical(obj$type, "message")) next
    m = obj$message
    if (is.null(last_msg)) last_msg = m
    if (is.na(model) && identical(m$role, "assistant")) model = paste0(m$provider, "/", m$model)
    if (identical(m$role, "user")) {
      turns = as.integer(obj$gptr$turn %||% NA_integer_)
      break
    }
  }
  if (!is.null(last_msg)) {
    calls = vapply(last_msg$content %||% list(), function(b) identical(b$type, "toolCall"), NA)
    final = identical(last_msg$role, "assistant") && !any(calls) &&
      !(last_msg$stopReason %||% "stop") %in% c("error", "aborted")
    status = if (final) "idle" else "interrupted"
  }
  created = (iso_ms(hdr$timestamp) %||% (1000 * as.numeric(file.mtime(path)))) / 1000
  data.frame(id = hdr$id, file = normalizePath(path, winslash = "/"),
             created = .POSIXct(created, tz = "UTC"), updated = file.mtime(path), turns = turns,
             model = model, status = status, title = title, live = FALSE, stringsAsFactors = FALSE)
}

#' The text of a user message in JSON shape, without context blocks
#' @noRd
json_user_text = function(m) {
  txt = vapply(m$content %||% list(), function(b) {
    if (identical(b$type, "text") && is.null(b$gptr$context)) b$text %||% "" else ""
  }, "")
  paste(txt[nzchar(txt)], collapse = " ")
}

#' Complete lines of the first or last 64 KiB of a file
#' @noRd
file_chunk_lines = function(path, from_end = FALSE, n = 65536) {
  size = file.size(path)
  if (is.na(size) || size == 0) return(character())
  k = min(size, n)
  con = file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  if (from_end) seek(con, size - k)
  txt = rawToChar(readBin(con, "raw", k))
  lines = strsplit(txt, "\n", fixed = TRUE)[[1L]]
  if (!from_end && k < size && length(lines)) lines = lines[-length(lines)]
  if (from_end && k < size && length(lines)) lines = lines[-1L]
  as_utf8(lines[nzchar(lines)])
}

# ---------------------------------------------------------------------------- resume (gptr_resume)

#' Resume a stored session
#'
#' Returns the live object when one exists in this process; otherwise rebuilds the session from
#' its JSONL file (leaf = the last entry; status `idle` when the tail is a final answer, else
#' `interrupted`) with home `envir`. A rebuilt fork always gets a fresh overlay of `envir`. A
#' detached copy (from `saveRDS()`, a knitr cache or callr) is attached under the split-brain
#' rules. `block =` returns the session that a document replay bound to that block.
#'
#' @param x `NULL` (the most recently updated stored session), a session id, a file path, or a
#'   detached `gptr_session`.
#' @param envir The home of a rebuilt session.
#' @param block,child A document block id (and a team member name): the session replay bound to
#'   that block in this process, or `gptr_error_replay_unbound`; never a fallback to `envir`.
#' @return A `gptr_session`.
#' @examples
#' s = gptr_last()
#' if (!is.null(s)) identical(gptr_resume(s$id), s)
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' identical(gptr_resume(s$id), s)
#' @export
gptr_resume = function(x = NULL, envir = parent.frame(), block = NULL, child = NULL) {
  check_string(block, "block", null = TRUE)
  check_string(child, "child", null = TRUE)
  if (!is.null(block)) {
    s = replay_lookup(block, child)
    if (is.null(s)) {
      gptr_abort(paste0("no session is bound to block ", block,
                        if (is.null(child)) "" else paste0(" (child ", child, ")"),
                        " in this R process; source the statement that owns block ", block,
                        " first"),
                 c("replay_unbound", "not_recorded"), block = block, child = child)
    }
    session_control_check("gptr_resume", s)
    return(s)
  }
  check_env(envir, "envir")
  if (inherits(x, "gptr_session")) {
    session_control_check("gptr_resume", x)
    session_attach(x, envir)
    return(x)
  }
  if (is.character(x) && length(x) == 1L && !is.na(x) && grepl("^s[0-9a-f]{10}$", x)) {
    live_s = session_by_id(x)
    if (!is.null(live_s)) {
      session_control_check("gptr_resume", live_s)
      return(live_s)
    }
  }
  path = resume_path(x)
  session_control_check("gptr_resume", NULL)
  store_rebuild(path, envir)
}

#' The file gptr_resume() rebuilds from
#' @noRd
resume_path = function(x) {
  if (is.null(x)) {
    dir = sessions_dir()
    files = if (dir.exists(dir)) list.files(dir, pattern = "[.]jsonl$",
                                            full.names = TRUE) else character()
    if (!length(files)) {
      gptr_abort("there is no stored session to resume", "invalid_argument", arg = "x",
                 expected = "a stored session")
    }
    return(files[[which.max(file.mtime(files))]])
  }
  if (!(is.character(x) && length(x) == 1L && !is.na(x))) {
    gptr_abort("`x` must be NULL, a session id, a file path or a gptr_session", "invalid_argument",
               arg = "x", expected = "NULL, a session id, a file path or a gptr_session")
  }
  if (file.exists(x)) return(x)
  f = store_find(x)
  if (is.null(f)) {
    gptr_abort(paste0("no stored session matches ", x), "invalid_argument", arg = "x",
               expected = "a session id or a session file")
  }
  f
}
```

Append to `R/session-object.R`:

```r

# ---------------------------------------------------------------------------- the replay table
# (IC-46)

#' Bind a replayed session to its document block id (gptr-created sessions only)
#' @return `s`, invisibly.
#' @noRd
session_replay_bind = function(block, s, child = NULL) {
  check_string(block, "block")
  check_class(s, "gptr_session", "s")
  check_string(child, "child", null = TRUE)
  assign(replay_key(block, child), s, envir = the$replay_blocks)
  invisible(s)
}

#' The session bound to a block (and a team member), or NULL
#' @noRd
replay_lookup = function(block, child = NULL) {
  check_string(block, "block")
  check_string(child, "child", null = TRUE)
  get0(replay_key(block, child), envir = the$replay_blocks, inherits = FALSE)
}

#' The key of a block in the replay table
#' @noRd
replay_key = function(block, child = NULL) if (is.null(child)) block else paste0(block, "/", child)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-(live|store)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 191 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/session-store.R R/session-object.R tests/testthat/test-session-live.R tests/testthat/test-session-store.R
git commit -m "feat(session): add the store reader, gptr_resume(), gptr_sessions() and crash recovery"
```

---

### Task 14: Replay functions (IC-46)

**Files:**

- Modify: `R/session-object.R`
- Modify: `R/agent-run.R`
- Test: `tests/testthat/test-session-object.R`

**Interfaces:**

Consumes:

- P01: `msg_user()`, `msg_assistant()`, `msg_tool_result()`, `block_tool_call(id, name, arguments, raw_arguments = NULL, thought_signature = NULL)`, `setting_get()`, `gptr_inform(..., .once =)`, `id_new()`.
- Tasks 3-13: `session_new()`, `session_append()`, `session_value_set()`, `session_home()`, `session_by_id()`, `entry_custom()`, `entry_message()`, `entries_path()`, `final_text()`, `fork_cut()`, `store_find()`, `store_rebuild()`, `run_start()`.

Produces:

- `session_replay_apply(s, block, header, text = NULL)` -> `s` (advanced in place: `gptr.replay`, `seen`, one more turn, the `value=` name, `last_text`), `session_replay_new(block, header, envir, doc)` -> the live session with the header's id (advanced), else a `replayed` session adopting the recorded id, rebuilt from its JSONL cut at the recorded turn or reconstructed from the document (`history_source = "reconstructed"`); private `replay_mark()`, `replay_value()`, `replay_rebuild()`, `replay_reconstruct()`, `replay_notice()` (the one-time notice when a reconstructed session continues live).
- `header` is the parsed block header of 04 §11.5 as a named list of strings (`model`, `session`, `turn`, `value`, `fork`, ...), plus `doc` and `mode` when P15 knows them; `doc` is `list(path, format, template, code, output, text)`.

- [ ] **Step 1: Write the failing test**

The chain test proves the acceptance line "`session_replay_apply()` keeps `identical()` along a replayed pipe chain".

Append to `tests/testthat/test-session-object.R`:

```r
# ---------------------------------------------------------------- replay (IC-46)

replay_types = function(s) {
  vapply(session_data(s)$entries, function(e) e$custom_type %||% e$type, "")
}

test_that("session_replay_apply() advances the piped session in place; identical() holds", {
  s = test_session()
  r = s |>
    session_replay_apply("a1b2c3", list(session = s$id, turn = "1")) |>
    session_replay_apply("d4e5f6", list(session = s$id, turn = "2"), text = "cached answer")
  expect_identical(r, s)
  expect_identical(s$turns, 2L)
  expect_identical(session_data(s)$seen, c("a1b2c3", "d4e5f6"))
  expect_identical(s$text, "cached answer")
  rep = Filter(function(e) identical(e$custom_type, "gptr.replay"), session_data(s)$entries)
  expect_length(rep, 2L)
  expect_identical(rep[[2L]]$data$block, "d4e5f6")
  expect_identical(rep[[2L]]$data$turn, 2L)
  expect_identical(rep[[2L]]$data$mode, "replay")
})

test_that("a block already seen adds no turn and no entry", {
  s = test_session()
  session_replay_apply(s, "a1b2c3", list(turn = "1"))
  n = length(session_data(s)$entries)
  session_replay_apply(s, "a1b2c3", list(turn = "1"))
  expect_identical(s$turns, 1L)
  expect_length(session_data(s)$entries, n)
})

test_that("value= designates the named object of the kept home under the value policy", {
  home = new.env()
  home$qc = c(a = 1, b = 2)
  s = test_session(home = home)
  session_replay_apply(s, "a1b2c3", list(turn = "1", value = "qc"))
  expect_identical(s$value, c(a = 1, b = 2))
  expect_identical(s$values$mode, "copy")
  expect_identical(s$values$name, "qc")
  session_replay_apply(s, "d4e5f6", list(turn = "2", value = "later"))
  expect_identical(s$values$mode, c("copy", "name"))
  home$later = "bound after the replay"
  expect_identical(s$value, "bound after the replay")
})

test_that("session_replay_apply() validates its arguments", {
  s = test_session()
  expect_error(session_replay_apply(s, 1, list()), class = "gptr_error_invalid_argument")
  expect_error(session_replay_apply(s, "a1b2c3", "x"), class = "gptr_error_invalid_argument")
  expect_error(session_replay_apply(list(), "a1b2c3", list()),
               class = "gptr_error_invalid_argument")
})

test_that("session_replay_new() returns the live session holding the header's id", {
  s = test_session()
  r = session_replay_new("a1b2c3", list(session = s$id, turn = "1"), envir = globalenv(),
                         doc = list(path = "analysis.R", text = "cached"))
  expect_identical(r, s)
  expect_identical(s$turns, 1L)
  expect_identical(s$text, "cached")
})

test_that("session_replay_new() rebuilds from the JSONL, cut at the recorded turn", {
  local_store()
  local_permissive()
  local_fake_provider(list("first answer", "second answer"))
  s = test_session(home = globalenv())
  run_text(s, "one")
  run_text(s, "two")
  id = s$id
  other = test_session()
  rm(s)
  invisible(gc())
  expect_null(session_by_id(id))
  home = new.env()
  r = session_replay_new("a1b2c3", list(session = id, turn = "1", model = "fake/fake-1"),
                         envir = home, doc = list(path = "analysis.R", format = "r"))
  expect_identical(r$id, id)
  expect_identical(r$kind, "replayed")
  expect_identical(r$turns, 1L)
  expect_identical(r$text, "first answer")
  expect_identical(session_data(r)$history_source, "store")
  expect_identical(session_data(r)$doc$path, "analysis.R")
  expect_identical(roles(r), c("user", "assistant"))
  expect_true("gptr.replay" %in% replay_types(r))
})

test_that("without a file the session is reconstructed from the document", {
  local_store()
  home = new.env()
  doc = list(path = "analysis.R", format = "r", template = "Count the rows of d",
             code = "n = nrow(d)", output = "[1] 32", text = "There are 32 rows.")
  r = session_replay_new("a1b2c3", list(session = "s0123456789", turn = "2",
                                        model = "fake/fake-1", value = "n"),
                         envir = home, doc = doc)
  expect_identical(r$id, "s0123456789")
  expect_identical(r$kind, "replayed")
  expect_identical(session_data(r)$history_source, "reconstructed")
  expect_identical(r$turns, 2L)
  expect_identical(r$text, "There are 32 rows.")
  expect_identical(roles(r), c("user", "assistant", "tool_result", "assistant"))
  call = r$messages[[2L]]$content[[1L]]
  expect_identical(call$name, "r")
  expect_identical(call$arguments$code, "n = nrow(d)")
  expect_identical(msg_text(r$messages[[3L]]), "[1] 32")
  expect_identical(r$messages[[1L]]$source, "replay")
  expect_identical(r$values$name, "n")
  expect_identical(r$envir, home)
  # a fork block (`fork=` header) reconstructed without a file gets a fresh overlay (IC-46)
  f = session_replay_new("b7c8d9", list(session = "s0123456787", turn = "1",
                                        model = "fake/fake-1", fork = "s0123456789"),
                         envir = home, doc = doc)
  expect_identical(parent.env(f$envir), home)
})

test_that("a later live run of a reconstructed session gives a one-time notice", {
  local_store()
  local_permissive()
  local_fake_provider(list("continued"))
  local_gptr_options(quiet = FALSE)
  r = session_replay_new("a1b2c3", list(session = "s0123456788", turn = "1", model = "fake/fake-1"),
                         envir = new.env(), doc = list(template = "Summarise d", text = "Done."))
  expect_message(run_text(r, "and then?"), "reconstructed", class = "gptr_message_notice")
  expect_identical(r$text, "continued")
  expect_no_message(run_text(r, "more"), message = "reconstructed")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-object$")'`

Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 144 ]`, with errors such as ``Error in `session_replay_apply(s, "a1b2c3", list(turn = "1"))`: could not find function "session_replay_apply"``.

- [ ] **Step 3: Write the implementation**

A rebuilt session keeps the turn of its transcript (no extra turn), a piped session gains one. The name-only value record resolves later through the kept home, so a replayed `value=` name bound after the replay is still found.

Append to `R/session-object.R`:

```r
# ---------------------------------------------------------------------------- replay (IC-46)

#' Advance a piped session in place for a fresh recorded block (IC-46)
#'
#' Appends a `gptr.replay` entry, adds the block to `seen` (a block already seen changes
#' nothing), counts one turn, designates the header's `value=` name under the value policy and
#' takes `last_text` from the cached answer. The same object is returned, so
#' `identical(chain_result, first_result)` holds along a replayed pipe chain.
#' @param s The piped `gptr_session`.
#' @param block chr(1): the block id.
#' @param header Named list: the parsed block header (04 section 11.5: `model`, `session`,
#'   `turn`, `value`, `fork`, ...), plus `doc` (the document path) and `mode` (the replay mode of
#'   P15) when the caller knows them.
#' @param text chr(1) or `NULL`: the cached answer text (the S2 cache of P15).
#' @return `s`.
#' @noRd
session_replay_apply = function(s, block, header, text = NULL) {
  check_class(s, "gptr_session", "s")
  check_string(block, "block")
  check_list(header, "header")
  check_string(text, "text", null = TRUE)
  replay_mark(s, block, header, text, advance = TRUE)
  s
}

#' The session a fresh block replays into when no session is piped (IC-46)
#'
#' The live session holding the header's `session=` id when one exists in this process (advanced
#' with `session_replay_apply()`); otherwise a `replayed` session that adopts the recorded id:
#' rebuilt from its JSONL with the leaf moved back to the end of the recorded turn, or, without a
#' file, reconstructed from the document (`history_source = "reconstructed"`).
#' @param block chr(1): the block id.
#' @param header Named list: the parsed block header (see `session_replay_apply()`).
#' @param envir The environment the document is sourced into (the rebuilt session's home; a
#'   rebuilt fork gets a fresh overlay of it).
#' @param doc Named list from the document or `NULL`: `path`, `format`, `template` (the prompt
#'   template), `code` (chr: the recorded code lines), `output` (chr: the `#>` lines without their
#'   prefix), `text` (the cached answer or `NULL`).
#' @return A live `gptr_session`.
#' @noRd
session_replay_new = function(block, header, envir, doc) {
  check_string(block, "block")
  check_list(header, "header")
  check_env(envir, "envir")
  check_list(doc, "doc", null = TRUE)
  id = header$session
  live_s = if (is.null(id)) NULL else session_by_id(id)
  if (!is.null(live_s)) return(session_replay_apply(live_s, block, header, doc$text))
  path = if (is.null(id)) NULL else store_find(id)
  s = if (is.null(path)) replay_reconstruct(header, envir, doc) else replay_rebuild(path, header,
                                                                                    envir)
  d = session_data(s)
  d$kind = "replayed"
  d$replayed = TRUE
  d$block = block
  if (!is.null(doc$path)) {
    d$doc = list(path = doc$path, format = doc$format %||% NA_character_, site = NULL,
                 blocks = block)
  }
  replay_mark(s, block, header, doc$text, advance = FALSE)
  s
}

#' Record a replayed block on a session: `gptr.replay`, `seen`, the turn, the value, `last_text`
#' @param advance `TRUE` counts one more turn (a piped session); `FALSE` keeps the turn of a
#'   rebuilt or reconstructed transcript.
#' @noRd
replay_mark = function(s, block, header, text, advance) {
  d = session_data(s)
  if (block %in% d$seen) return(invisible(s))
  turn = if (advance) d$turns + 1L else d$turns
  session_append(s, entry_custom("gptr.replay", drop_null(list(
    doc = header$doc %||% d$doc$path, block = block, mode = header$mode %||% "replay",
    turn = turn, value = header$value))))
  d$seen = c(d$seen, block)
  d$turns = turn
  if (!is.null(header$value)) replay_value(s, header$value)
  if (!is.null(text)) d$last_text = text
  invisible(s)
}

#' Designate the replayed block's `value=` name: through the value policy when the name is bound
#' in the kept home, else held by name only (resolved when first read)
#' @noRd
replay_value = function(s, name) {
  home = session_home(s)
  if (!is.null(home) && exists(name, envir = home, inherits = FALSE)) {
    session_value_set(s, name, get(name, envir = home, inherits = FALSE), name = name)
    return(invisible(NULL))
  }
  d = session_data(s)
  vals = d$values
  vals[[length(vals) + 1L]] = list(turn = d$turns, mode = "name", name = name,
                                   address = NA_character_, class = NA_character_,
                                   bytes = NA_real_, value = NULL)
  d$values = vals
  session_append(s, entry_custom("gptr.value", list(turn = d$turns, mode = "name", name = name)))
  invisible(NULL)
}

#' Rebuild a replayed session from its JSONL, the leaf moved back to the end of the recorded turn
#' @noRd
replay_rebuild = function(path, header, envir) {
  s = store_rebuild(path, envir)
  d = session_data(s)
  turn = suppressWarnings(as.integer(header$turn %||% d$turns))
  if (!is.na(turn) && turn < d$turns) {
    cut = tryCatch(fork_cut(d, turn), error = function(e) NULL)
    if (!is.null(cut) && !is.null(cut$entry)) {
      d$leaf = cut$entry
      d$turns = cut$turn
      path_e = entries_path(d)
      d$last_text = final_text(path_e) %||% NA_character_
      d$values = Filter(function(v) as.integer(v$turn) <= cut$turn, d$values)
      d$status = "idle"
    }
  }
  s
}

#' Reconstruct a replayed session from its document block: the template as the user message, the
#' recorded code as the assistant's `r` call, the `#>` lines as its result, then the cached answer.
#' A fork block (`fork=` header) gets a fresh overlay of `envir`, like a fork rebuilt from its
#' JSONL (IC-46), so its objects never land in the document's environment.
#' @noRd
replay_reconstruct = function(header, envir, doc) {
  model = header$model %||% "unknown/unknown"
  fork = header$fork
  home = if (!is.null(fork) && home_keep(envir)) overlay_new(envir, fork) else envir
  s = session_new(model, setting_get("mode", default = "manual"), home = home, kind = "replayed",
                  opts = list(id = header$session %||% id_new("s", 10L)))
  d = session_data(s)
  d$history_source = "reconstructed"
  turn = suppressWarnings(as.integer(header$turn %||% 1L))
  d$turns = if (is.na(turn)) 1L else turn
  provider = sub("/.*$", "", model)
  model_id = sub("^[^/]*/", "", model)
  session_append(s, entry_message(msg_user(doc$template %||% "(the prompt was not recorded)",
                                           source = "replay")))
  if (length(doc$code)) {
    call_id = paste0("replay_", d$turns)
    call = block_tool_call(call_id, "r", list(code = paste(doc$code, collapse = "\n")))
    session_append(s, entry_message(msg_assistant(list(call), api = "replay", provider = provider,
                                                  model = model_id, stop_reason = "tool_use")))
    out = if (length(doc$output)) paste(doc$output, collapse = "\n") else "(no output recorded)"
    session_append(s, entry_message(msg_tool_result(call_id, "r", out)))
  }
  answer = doc$text %||% "(the answer of this turn was not recorded; its code is above)"
  session_append(s, entry_message(msg_assistant(answer, api = "replay", provider = provider,
                                                model = model_id)))
  s
}

#' The one-time notice when a reconstructed session continues live (IC-46)
#' @noRd
replay_notice = function(s) {
  d = session_data(s)
  if (!identical(d$history_source, "reconstructed")) return(invisible(NULL))
  gptr_inform(paste0("session ", d$id, " continues from a history reconstructed from its ",
                     "document; earlier tool calls and answers are approximate"),
              "notice", .once = paste0("reconstructed:", d$id))
  invisible(NULL)
}
```

Modify `R/agent-run.R`: in `run_start()`, call `replay_notice(s)` right after the run record is created. Replace

```r
  run = run_new(s, opts, outer)
  input = run_initial_input(run, input)
```

with

```r
  run = run_new(s, opts, outer)
  replay_notice(s)
  input = run_initial_input(run, input)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-object$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 189 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/session-object.R R/agent-run.R tests/testthat/test-session-object.R
git commit -m "feat(session): add the replay functions (IC-46)"
```

---

### Task 15: The `ctx.kernel` service

**Files:**

- Modify: `R/agent-run.R`
- Test: `tests/testthat/test-agent-run.R`

**Interfaces:**

Consumes:

- P01: `on_load()`, `ext_service_set(name, fun, provided_by, builtin = NULL)`, `ext_service_has()`, `ext_service_get()`, `check_choice()`, `check_string()`, `setting_get()`; P05: `model_default(role = c("chat", "small", "system1"))` (the `model` member of a session-less, process-level `ctx`).
- P02 (the caller): `ctx_new()` calls each member as `impl(ctx, ...)` with positional arguments and, only inside a handler, appends the handler's source (`ctx_source(ctx)`, for example `"plugin:panel"`; P06's `ctx_ext_label()` derives `"panel"`) as the last positional argument (`extension`) of `send`, `append_entry` and `state` (P02 plan Task 7, `ctx_call_plugin()`).
- Tasks 3-14: `session_data()`, `session_live()`, `session_home()`, `session_append()`, `entry_custom()`, `session_enqueue()`, `session_set_model()`, `run_eval_env()`, `run_emit()`, `run_abort()`, `dispatch_nested()`, `gptr_usage()`, `queue_item_message()`.

Produces:

- The service `ctx.kernel` (IC-34): `ctx_kernel()` -> a named list of the 04 §10.6 member implementations marked P06, with the calling convention P02's `ctx_new()` uses (`impl(ctx, ...)` with positional arguments; inside a handler P02 adds the handler's plugin name, already stripped of its `plugin:`/`builtin:` prefix, as the last argument of `send`, `append_entry` and `state`; outside handlers it adds nothing, so the default applies): `envir(ctx)`, `run(ctx)`, `mode(ctx)`, `model(ctx)`, `execute_tool(ctx, name, input)`, `send(ctx, text, as = c("steer", "follow_up"), extension = NULL)`, `set_model(ctx, ref, thinking = NULL, reason = "plugin")`, `append_entry(ctx, type, data, extension = NULL)`, `abort(ctx, reason = "plugin")`, `aborted(ctx)`, `update(ctx, text)`, `usage(ctx)`, `state(ctx, extension = NULL)`; private `ctx_run(ctx)` and `ctx_ext_label(extension)` (`"plugin:units"` -> `"units"`, `"plugin"` without a source).

- [ ] **Step 1: Write the failing test**

P02's `ctx_new()` is a thin shell whose members fetch this service at call time (IC-34); the tests call the implementations directly with the session's `ctx`.

Append to `tests/testthat/test-agent-run.R`:

```r
# ---------------------------------------------------------------- the ctx.kernel service (IC-34)

kernel_members = c("envir", "run", "mode", "model", "execute_tool", "send", "set_model",
                   "append_entry", "abort", "aborted", "update", "usage", "state")

test_that("ctx.kernel is a registered service listing the P06 members of section 10.6", {
  expect_true(ext_service_has("ctx.kernel"))
  k = ext_service_get("ctx.kernel")()
  expect_identical(names(k), kernel_members)
  expect_true(all(vapply(k, is.function, NA)))
})

test_that("outside a run the members read the session", {
  home = new.env()
  s = test_session(mode = "manual", home = home)
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  expect_identical(k$envir(ctx), home)
  expect_null(k$run(ctx))
  expect_identical(k$mode(ctx), "manual")
  expect_identical(k$model(ctx), "fake/fake-1")
  expect_false(k$aborted(ctx))
  expect_s3_class(k$usage(ctx), "gptr_usage")
  expect_null(k$update(ctx, "ignored outside a tool"))
  expect_null(k$abort(ctx))
})

test_that("inside a tool the members see the run; update emits tool_execution_update", {
  local_permissive()
  box = new.env()
  local_tool("probe", function(input, ctx) {
    k = ctx_kernel()
    box$run = k$run(ctx)
    box$envir = k$envir(ctx)
    box$mode = k$mode(ctx)
    k$update(ctx, "half way")
    "probed"
  })
  local_fake_provider(list(fake_tool("probe"), "done"))
  ev = local_events("tool_execution_update")
  home = new.env()
  s = test_session(home = home)
  run_text(s, "go")
  expect_match(box$run, "^u[0-9a-f]{8}$")
  expect_identical(box$envir, home)
  expect_identical(box$mode, "auto")
  up = ev(s)
  expect_length(up, 1L)
  expect_identical(up[[1L]]$text, "half way")
  expect_identical(up[[1L]]$tool_name, "probe")
})

test_that("send() enqueues extension notes, never operator relays (IC-55)", {
  s = test_session()
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  k$send(ctx, "check the units", extension = "plugin:units")
  k$send(ctx, "then plot", as = "follow_up")
  q = session_data(s)$queue
  expect_identical(q$steer[[1L]]$source, "extension")
  expect_identical(q$steer[[1L]]$name, "units")
  expect_identical(q$follow_up[[1L]]$text, "then plot")
  m = queue_item_message(q$steer[[1L]], "steer", relay = TRUE)
  expect_identical(m$role, "user")
  expect_identical(msg_text(m),
                   "Extension units sent this note (not from the user): check the units")
})

test_that("send() from model code of the same session tree is refused (IC-55)", {
  local_permissive()
  box = new.env()
  local_tool("r", function(input, ctx) {
    box$err = tryCatch(ctx_kernel()$send(ctx, "sneaky"), error = function(e) e)
    "ran"
  }, parameters = list(type = "object", required = I("code"),
                       properties = list(code = list(type = "string"))))
  local_fake_provider(list(fake_tool("r", code = "gptr_steer(s, 'x')"), "done"))
  s = test_session()
  run_text(s, "go")
  expect_s3_class(box$err, "gptr_error_permission")
  expect_length(session_data(s)$queue$steer, 0L)
})

test_that("set_model() switches at once when idle and at the next request inside a run", {
  local_permissive()
  local_fake_provider(list("a"))
  local_fake_provider(list("from other"), name = "other")
  s = test_session()
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  k$set_model(ctx, "other/other-1", thinking = "high", reason = "plugin")
  expect_identical(s$model, "other/other-1")
  change = Filter(function(e) identical(e$type, "model_change"), session_data(s)$entries)
  expect_identical(change[[1L]]$gptr$reason, "plugin")
  run = test_run(s)
  k$set_model(ctx, "fake/fake-1", thinking = "low")
  expect_identical(s$model, "other/other-1")
  expect_identical(run$pending_model, list(ref = "fake/fake-1", thinking = "low",
                                           reason = "plugin"))
})

test_that("append_entry() writes a custom entry named <plugin>.<type>", {
  s = test_session()
  ctx = session_live(s)$ctx
  id = ctx_kernel()$append_entry(ctx, "note", list(n = 1L), extension = "plugin:units")
  e = session_data(s)$entries[[length(session_data(s)$entries)]]
  expect_identical(e$id, id)
  expect_identical(e$custom_type, "units.note")
  expect_identical(e$data, list(n = 1L))
})

test_that("abort() inside a tool stops the run after the call with the given reason", {
  local_permissive()
  local_tool("stopper", function(input, ctx) {
    ctx_kernel()$abort(ctx, "plugin stop")
    "stopping"
  })
  local_fake_provider(list(fake_tools(list(name = "stopper", input = json_obj()),
                                      list(name = "stopper", input = json_obj())),
                           "never reached"))
  s = test_session()
  run_text(s, "go")
  expect_identical(s$status, "aborted")
  expect_length(tool_results(s), 1L)
  expect_false(identical(s$text, "never reached"))
})

test_that("state() is one environment per session and plugin, persisted when JSON-able", {
  local_permissive()
  local_fake_provider(list("ok"))
  s = test_session()
  ctx = session_live(s)$ctx
  k = ctx_kernel()
  st = k$state(ctx, extension = "plugin:panel")
  st$count = 2L
  expect_identical(k$state(ctx, extension = "plugin:panel"), st)
  expect_false(identical(k$state(ctx, extension = "plugin:other"), st))
  run_text(s, "go")
  expect_identical(s$ext$panel$count, 2L)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^agent-run$")'`

Expected: `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 255 ]`, with errors such as ``Error in `ctx_kernel()`: could not find function "ctx_kernel"`` and a failure because `ext_service_has("ctx.kernel")` is `FALSE`.

- [ ] **Step 3: Write the implementation**

`abort()` from inside a tool only raises the run's abort signal, so the dispatcher skips the remaining calls and the next step settles the run with the given reason; outside a tool it aborts at once.

Append to `R/agent-run.R`:

```r
# ---------------------------------------------------------------------------- ctx.kernel (IC-34)

on_load(ext_service_set("ctx.kernel", ctx_kernel, provided_by = "P06"))

#' The `ctx.kernel` service: the implementations of the `ctx` members marked P06 in contract
#' section 10.6
#'
#' P02's `ctx_new()` is a thin shell whose members fetch this list at call time and call the
#' member with the `ctx` first, then the member's own arguments, positionally (P02's
#' `ctx_call()`); inside a handler P02 appends the handler's plugin name (`"units"`, from the
#' source `"plugin:units"`) as the last argument of `send`, `append_entry` and `state`, which P06
#' receives as `extension` (`NULL` outside handlers; `ctx_ext_label()` accepts the bare name or a
#' full source). The run a member acts on is the session's current run
#' (`session_live(ctx$session)$run`).
#' @return A named list of functions: `envir`, `run`, `mode`, `model`, `execute_tool`, `send`,
#'   `set_model`, `append_entry`, `abort`, `aborted`, `update`, `usage`, `state`.
#' @noRd
ctx_kernel = function() {
  list(
    envir = function(ctx) {
      run = ctx_run(ctx)
      if (!is.null(run)) return(run_eval_env(run))
      if (is.null(ctx$session)) NULL else session_home(ctx$session)
    },
    run = function(ctx) {
      run = ctx_run(ctx)
      if (is.null(run)) NULL else run$id
    },
    mode = function(ctx) {
      run = ctx_run(ctx)
      if (!is.null(run)) return(run$mode)
      if (is.null(ctx$session)) setting_get("mode", default = "manual") else
        session_data(ctx$session)$mode
    },
    model = function(ctx) {
      if (is.null(ctx$session)) model_default("chat") %||% NA_character_ else
        session_data(ctx$session)$model
    },
    execute_tool = function(ctx, name, input) dispatch_nested(name, input, ctx),
    send = function(ctx, text, as = c("steer", "follow_up"), extension = NULL) {
      as = check_choice(as, c("steer", "follow_up"), "as")
      session_enqueue(ctx$session, paste(text, collapse = "\n"), as = as, source = "extension")
      d = session_data(ctx$session)
      q = d$queue
      q[[as]][[length(q[[as]])]]$name = ctx_ext_label(extension)
      d$queue = q
      invisible(NULL)
    },
    set_model = function(ctx, ref, thinking = NULL, reason = "plugin") {
      check_string(ref, "ref")
      check_string(thinking, "thinking", null = TRUE)
      run = ctx_run(ctx)
      if (is.null(run)) {
        session_set_model(ctx$session, ref, reason)
        if (!is.null(thinking)) {
          d = session_data(ctx$session)
          d$thinking = thinking
        }
      } else {
        run$pending_model = list(ref = ref, thinking = thinking, reason = reason)
      }
      invisible(NULL)
    },
    append_entry = function(ctx, type, data, extension = NULL) {
      check_string(type, "type")
      session_append(ctx$session, entry_custom(paste0(ctx_ext_label(extension), ".", type), data))
    },
    abort = function(ctx, reason = "plugin") {
      run = ctx_run(ctx)
      if (is.null(run)) return(invisible(NULL))
      if (is.null(run$tool_call)) {
        run_abort(run, reason)
      } else {
        run$signal$aborted = TRUE
        run$signal$reason = reason
      }
      invisible(NULL)
    },
    aborted = function(ctx) {
      run = ctx_run(ctx)
      isTRUE(run$signal$aborted)
    },
    update = function(ctx, text) {
      check_string(text, "text")
      run = ctx_run(ctx)
      if (!is.null(run) && !is.null(run$tool_call)) {
        run_emit(run, "tool_execution_update", tool_call_id = run$tool_call$id,
                 tool_name = run$tool_call$name, text = text)
      }
      invisible(NULL)
    },
    usage = function(ctx) gptr_usage(ctx$session),
    state = function(ctx, extension = NULL) {
      plugin = ctx_ext_label(extension)
      live = session_live(ctx$session)
      if (is.null(live)) return(NULL)
      e = get0(plugin, envir = live$ext, inherits = FALSE)
      if (is.null(e)) {
        e = new.env(parent = emptyenv())
        prior = session_data(ctx$session)$ext[[plugin]]
        if (is.list(prior)) list2env(prior, envir = e)
        assign(plugin, e, envir = live$ext)
      }
      e
    })
}

#' The current run of a ctx's session, or NULL
#' @noRd
ctx_run = function(ctx) {
  s = ctx$session
  if (is.null(s)) return(NULL)
  live = session_live(s)
  if (is.null(live)) NULL else live$run
}

#' The plugin label of a handler's extension source: `"plugin:units"` -> `"units"`,
#' `"builtin:tools"` -> `"tools"`; `"plugin"` when no source is known (P02 passes `NULL`)
#' @noRd
ctx_ext_label = function(extension) {
  if (!is.character(extension) || !length(extension) || is.na(extension[[1L]]) ||
      !nzchar(extension[[1L]])) {
    return("plugin")
  }
  sub("^[A-Za-z_]+:", "", extension[[1L]])
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^agent-run$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 291 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/agent-run.R tests/testthat/test-agent-run.R
git commit -m "feat(agent): add the ctx.kernel service"
```

---

### Task 16: Documentation, NAMESPACE and plan acceptance

**Files:**

- Modify: `NAMESPACE`
- Create: `man/gptr_fork.Rd`, `man/gptr_sessions.Rd`, `man/gptr_resume.Rd`, `man/gptr_last.Rd`, `man/gptr_usage.Rd`, `man/session-accessors.Rd`, `man/print.gptr_session.Rd`, `man/format.gptr_session.Rd`, `man/summary.gptr_session.Rd`, `man/print.gptr_session_summary.Rd`, `man/str.gptr_session.Rd` (generated)
- Test: `tests/testthat/test-session-object.R`

**Interfaces:**

Consumes:

- The roxygen blocks written in Tasks 3, 4, 11, 12 and 13.

Produces:

- `NAMESPACE` entries `export(gptr_fork)`, `export(gptr_last)`, `export(gptr_resume)`, `export(gptr_sessions)`, `export(gptr_usage)` and the twelve `S3method()` registrations of the session methods; the eleven man pages.

- [ ] **Step 1: Write the failing test**

Under `devtools::test()` all functions are visible even without `NAMESPACE` entries, so this test reads the `NAMESPACE` file itself (`system.file()` finds it in the source tree under pkgload and in the installed package under R CMD check).

Append to `tests/testthat/test-session-object.R`:

```r
# ---------------------------------------------------------------- exports (contract 14.1)

test_that("NAMESPACE exports the session API and registers the session methods", {
  ns = readLines(system.file("NAMESPACE", package = "gptr"), warn = FALSE)
  exports = paste0("export(", c("gptr_fork", "gptr_last", "gptr_resume", "gptr_sessions",
                                "gptr_usage"), ")")
  methods = c("S3method(\"$\",gptr_session)", "S3method(\"$<-\",gptr_session)",
              "S3method(\"[[\",gptr_session)", "S3method(\"[[<-\",gptr_session)",
              "S3method(as.character,gptr_session)", "S3method(format,gptr_session)",
              "S3method(names,gptr_session)", "S3method(print,gptr_session)",
              "S3method(print,gptr_session_summary)", "S3method(summary,gptr_session)",
              "S3method(utils::.DollarNames,gptr_session)", "S3method(utils::str,gptr_session)")
  expect_identical(setdiff(c(exports, methods), ns), character())
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-object$")'`

Expected: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 189 ]`, with errors such as ``Failure ('test-session-object.R'): NAMESPACE exports the session API and registers the session methods``: `setdiff(c(exports, methods), ns)` lists the 17 missing lines.

- [ ] **Step 3: Write the implementation**

Generate `NAMESPACE` and the man pages from the roxygen blocks of Tasks 3, 4, 11, 12 and 13:

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected: roxygen2 reports `Writing 'NAMESPACE'` and writes `gptr_usage.Rd`, `gptr_last.Rd`, `session-accessors.Rd`, `print.gptr_session.Rd`, `format.gptr_session.Rd`, `summary.gptr_session.Rd`, `print.gptr_session_summary.Rd`, `str.gptr_session.Rd`, `gptr_fork.Rd`, `gptr_sessions.Rd` and `gptr_resume.Rd` without any warning (no unresolved link: roxygen text in P06 writes copy-safety rules as `(rule R2)`, never as `[R2]`, which markdown roxygen would read as a link). The P06 lines of `NAMESPACE` are then exactly:

```text
S3method("$",gptr_session)
S3method("$<-",gptr_session)
S3method("[[",gptr_session)
S3method("[[<-",gptr_session)
S3method(as.character,gptr_session)
S3method(format,gptr_session)
S3method(names,gptr_session)
S3method(print,gptr_session)
S3method(print,gptr_session_summary)
S3method(summary,gptr_session)
S3method(utils::.DollarNames,gptr_session)
S3method(utils::str,gptr_session)
export(gptr_fork)
export(gptr_last)
export(gptr_resume)
export(gptr_sessions)
export(gptr_usage)
```

Then run every example offline: `Rscript --vanilla -e 'devtools::run_examples(document = FALSE)'` finishes without error. Before P08 exists the `@examplesIf exists("gptr", mode = "function")` sections of the five P06 exports are skipped, `gptr_last()` returns `NULL`, and `gptr_sessions()` and `gptr_usage()` print empty listings.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "^session-object$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 190 ]`.

Then run the whole P06 suite (plan acceptance 1):

Run: `Rscript --vanilla -e 'devtools::test(filter = "session|agent")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 974 ]` (on CRAN, where `NOT_CRAN` is unset, the two SIGKILL tests, the two foreign-lock tests and the snapshot test skip).

Then run P01's layering and lint tests, which now scan the seven P06 files (every call edge against the 03 §2.2 table and the IC-33 kernel SDK; the parse-tree lint rules of 04 §12.3):

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(arch-layers|lint-rules)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]` (with P01-P06 in `R/`; a call from `agent-dispatch.R` or `agent-loop.R` into a `session-*.R` function would fail `test-arch-layers.R` with a "layering violations" listing).

- [ ] **Step 5: Commit**

```bash
git add NAMESPACE man/gptr_fork.Rd man/gptr_sessions.Rd man/gptr_resume.Rd man/gptr_last.Rd man/gptr_usage.Rd man/session-accessors.Rd man/print.gptr_session.Rd man/format.gptr_session.Rd man/summary.gptr_session.Rd man/print.gptr_session_summary.Rd man/str.gptr_session.Rd tests/testthat/test-session-object.R
git commit -m "docs(session): generate NAMESPACE and man pages for the session API"
```

---
## Plan acceptance

Every command runs from `/Users/wanjun/Desktop/gptr` after Task 16. The counts are those of the P06 test files (`test-agent-dispatch.R` 130, `test-agent-loop.R` 86, `test-agent-run.R` 291, `test-session-budget.R` 86, `test-session-live.R` 35, `test-session-object.R` 190, `test-session-store.R` 156 expectations).

| # | Acceptance check (05 P06, with its review amendments) | Proved by | Command and expected result |
|---|---|---|---|
| 1 | `devtools::test(filter = "session|agent")` is green (the SIGKILL test skips on CRAN) | Task 16 Step 4; the crash tests of Task 13 call `skip_on_cran()` and `skip_on_os("windows")`; P01's `test-arch-layers.R` and `test-lint-rules.R` stay green over the P06 files (Task 16 Step 4) | `Rscript --vanilla -e 'devtools::test(filter = "session|agent")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 974 ]`; `Rscript --vanilla -e 'devtools::test(filter = "^(arch-layers|lint-rules)$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]` |
| 2 | Report 02's 24 loop, 42 store and 26 recovery checks pass | `test-agent-loop.R` tests titled `L01`-`L24` (Task 10) and "every report 02 loop check has a test"; `test-session-store.R` `S01`-`S42` (Tasks 3, 7, 9, 10, 12, 13) and "every report 02 store check has a test" (Task 13); `test-agent-run.R` `R01`-`R26` (Tasks 8, 10) and "every report 02 recovery check has a test" (Task 10). The coverage tests compare the ids of `fixtures/oracles/report02/{loop,store,recovery}.json` with the `oracle_title()` calls of the file, so a missing check fails | `Rscript --vanilla -e 'devtools::test(filter = "^(agent-loop|agent-run|session-store)$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 533 ]` |
| 3 | INFRA-09/10: `{"n":3}` without `code` gives an error result and the function is not called; a `length` stop mid-call gives an error result and `done(length)`; a property test with throw, interrupt, warn-as-error and a timeout inside tools completes with paired events | `test-agent-dispatch.R`: "`{\"n\":3}` without the required `code` is an error result; nothing runs (INFRA-09)" and "throw, warn-as-error, time limit and interrupt give paired events (INFRA-10)" (Task 7; four call orders; the timeout is `setTimeLimit(elapsed = 0.3)`, the same code path as a 30 s limit without a 30 s test); "a length stop mid-call gives an error result and done(length) (INFRA-09)" (Task 10); L14 (Task 10) | `Rscript --vanilla -e 'devtools::test(filter = "^agent-dispatch$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 130 ]` |
| 4 | INFRA-12: a steer enqueued during a tool is on the wire after the tool-result message; `max_turns = 3` stops with status `max_turns` | L11-L13 and L22 in `test-agent-loop.R`; "a tool piping into its own running session enqueues a steer delivered after its result" in `test-agent-run.R` (Task 10) | `Rscript --vanilla -e 'devtools::test(filter = "^agent-loop$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 86 ]` |
| 5 | INFRA-13: SIGKILL during a streamed turn, then `gptr_resume()`: the file parses, the last complete message is present, nothing is duplicated; `.Random.seed` unchanged over 1,000 appends; a forked file replays to the source path's context | "SIGKILL mid-stream: resume parses, keeps the last complete message, no duplicate" (Task 13); S02 (Task 3); S24 (Task 13) | `Rscript --vanilla -e 'devtools::test(filter = "^session-store$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 156 ]` |
| 6 | INFRA-14/15: a listener on `gptr_fork(s)` never fires for `s`; overlay writes do not reach `s$envir`; two concurrent sessions keep separate usage | "a listener on the fork never fires for the source; nothing live is shared" and "an overlay fork reads the source home and writes to its own overlay" (Task 12); "two concurrent sessions keep separate usage and tool context (INFRA-15)" (Task 10) | `Rscript --vanilla -e 'devtools::test(filter = "^(session-object|agent-run)$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 481 ]` |
| 7 | G3 analogues: `identical(s |> step, s)`; `$<-` refused; an unreferenced settled session is finalised and its lock removed (except the one `gptr_last()` holds); a same-process duplicate continues with `gptr_error_split_brain` | "session_run() returns the identical session; each run is one prompt turn" (Task 10: `expect_identical(s |> session_run(msg_user("b")), s)`; `gptr_step()` is P08's and repeats the check on the gateway); "$<- and [[<- are refused (gptr_error_readonly)" (Task 4); "an unreferenced session is finalised and its lock removed, except gptr_last()'s" (Task 3); "a same-process duplicate cannot attach: gptr_error_split_brain" (Task 3) and "continuing a same-process duplicate with a run is split brain" (Task 13); a settled (aborted) session with nothing left in the reactor is collected: "an abort while a tool waits in the FIFO cancels the job; the session can be collected" (Task 10, `test-agent-run.R`, run by acceptance 1) | `Rscript --vanilla -e 'devtools::test(filter = "^session-(object|live)$")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 225 ]` |
| 8 | Review additions: `nrow(showConnections())` unchanged after a run returns, errors or is interrupted and after 300 sessions kept in a list; SIGKILL mid-append, resume, three appends: all present and the tree connected; `gptr_last()` survives `gc()`; with no policy a mutating tool asks (and is `blocked` without a UI); a hook answering allow to an `ask_human` is ignored; an option changed by model code mid-run does not change the run's gate; a budget of 5 USD on a root stops its children (a top-level container without a run still caps its children, IC-66); `session_replay_apply()` keeps `identical()` along a replayed pipe chain | "no connection is left open after a run returns or errors (IC-59)" and "an interrupt aborts the run and is re-signalled; no connection is left open" (Task 10; `gptr()` is P08's and repeats them on the gateway); "300 sessions kept in a list leave no connection open (IC-59)" and "gptr_last() holds the most recent session strongly and survives gc()" (Task 3); "SIGKILL mid-append, resume, three appends: all present and the tree connected (IC-59)" (Task 13); "with no mode policy a mutating tool asks and is blocked without a UI (NS-12)", "a hook answering allow to an ask_human is ignored (IC-53)", "an option changed by model code mid-run does not change the run's gate (IC-53)" (Task 7) and "with no policy a mutating tool asks and the run ends blocked without a human" (Task 10); "a budget of 5 USD on a root stops its children (root charging, IC-66)" (Task 10) and, for a top-level container without a run, "children of a root without a run share one budget through opts$root (IC-66)" (Task 5); "session_replay_apply() advances the piped session in place; identical() holds" (Task 14) | `Rscript --vanilla -e 'devtools::test(filter = "session|agent")'` -> `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 974 ]` |

Review amendments of 05 P06 and where they are implemented: open-append-close appends, torn-line recovery at resume, unparsable lines skipped, locks with pid, creation time and 10-minute heartbeat (IC-59): Tasks 3, 10 (`run_heartbeat()`), 13; `the$last` strong (IC-71): Task 3; the replay functions and `gptr_resume(block =, child =)` with fresh overlays (IC-46): Tasks 13, 14; `perm_check()` with `ask_human`, one modify re-check, the safety snapshot and mode inheritance for every call made during a run (IC-53): Tasks 5, 7; relays and queue items by source (IC-55): Tasks 1, 6, 15; budgets with the default ceiling, root charging and `gptr.max_nested_calls` (IC-66): Tasks 4, 5, 10; router calls before each request (IC-69): Tasks 9, 10; `ctx.kernel` (IC-34): Task 15; per-session `out` stores (IC-71): Task 3 (`live$out`); image elision entries (IC-67): Task 9; the `store` kind's built-in record (IC-69): Task 13; re-classification of worker-forwarded permission requests (IC-53): Task 7 ("a forwarded request is re-classified from its raw input (IC-53)").

## Self-review

### Spec coverage

| 05 P06 scope item | Task |
|---|---|
| `session-object.R`: shell + `.d` | 3 |
| accessors, `print`/`format`/`summary`/`str` (no `knit_print`: P15, IC-07), `$<-` refusal | 4 |
| value policy (03 §5.1) | 4 (replay `value=` in 14) |
| `gptr_fork()` with the overlay default | 12 |
| model, mode and queue verbs (04 §7.6) | 6 |
| replay functions (IC-46) | 13 (table), 14 |
| `session-live.R`: weak live registry, home policy with the frame reset at settlement, pid locks, split-brain rules, `gptr_last()` | 3 (registry, homes, locks, attach, `gptr_last()`), 10 (reset at settlement), 13 (split brain on resume) |
| `session-store.R`: Pi-v3 JSONL tree, appends in `suspendInterrupts()` | 3 |
| torn-line tolerant reader, `gptr_sessions()`, `gptr_resume()` | 13 |
| lazy fork files | 12 |
| `session-budget.R`: budgets, token ledger, `gptr_usage()` (IC-05) | 2, 4, 5, 10, 11 |
| `agent-loop.R`: pure state machine with injected stream, context and tool functions; steer/follow-up queues; `max_turns` | 1 (the engine injects them in 10) |
| `agent-run.R`: lifecycle on the reactor, agent-level retry, overflow and one compact-and-retry, nested runs with `allow_runs`, abort, `.opts$returns`, plan-mode scratch overlay `run_eval_env()` (IC-15) | 5, 8, 9, 10 |
| `agent-dispatch.R`: validate -> gate -> execute, never throws, FIFO, source order, nested-call gating, `perm_check()` (IC-04, IC-53) | 7 |
| `ctx.kernel` service (IC-34) | 15 |
| exports, `NAMESPACE`, man pages | 16 |
| `fixtures/oracles/report02/` (24 loop, 42 store, 26 recovery checks) | 3 (store), 8 (recovery), 10 (loop) |

Every acceptance check maps to a task and a test in "Plan acceptance" above.

### Placeholder scan

The plan was searched (case-sensitive `grep`) for every placeholder phrase that the plan format forbids (unfinished-work markers, deferred implementation, vague error or edge-case handling, references to another task instead of code, test steps without test code) and for steps that describe code without showing it: there are no hits. Every step that changes a file shows the complete code or the exact replacement; the only generated files (`NAMESPACE`, `man/`) come from `devtools::document()` with their expected `NAMESPACE` lines shown.

### Type and name consistency with 04

- Every function of 04 §7.6 exists with the contract's exact signature: `session_new()`, `session_data()`, `session_live()`, `session_home()`, `session_append()`, `session_set_model()`, `session_set_mode()`, `session_enqueue()`, `session_value_set()`, `session_value_get()`, `live_all()`, `last_set()`, `store_open()`, `store_append()`, `store_read()`, `store_close()`, `store_fork()`, `store_rebuild()`, `store_heartbeat()`, `session_replay_apply()`, `session_replay_new()`, `session_replay_bind()`, `replay_lookup()`, `budget_check()`, `ledger_add()`, `session_run()`, `run_start()`, `run_wait()`, `run_abort()`, `run_current()`, `run_eval_env()`, `run_emit()`, `dispatch_tools()`, `dispatch_nested()`, `tool_validate()`, `perm_check()`, `tool_result_message()`.
- The five exports match 04 §6.5 argument for argument; the listings carry the 04 §5.12 classes and columns; `gptr_run` carries the 04 §7.6 fields; `.d` carries every 04 §5.1 field.
- Condition classes and fields, option names and defaults, entry and event names are those of 04 §2.2, §3.1, §4.6 and §10.4 (Global Constraints).
- Functions consumed from P01-P05 are called by their 04 names and signatures, and the five dependency plans in `dev/plan/` agree: the review assembled their R code with this plan's and ran the whole P06 suite against it (Executed validation). P05's `usage_empty()` is consumed, not redefined. No function name of this plan is defined by another plan's `R/` code (a parse of every plan's code blocks; the one other `.DollarNames.gptr_session` is P01's lint fixture). P02's `ctx_new()` calls the `ctx.kernel` members positionally (ambiguity 4); P02's checkpointer validator requires `undo` and `redo` (Task 7's test supplies them); P08's `control_check()` and `run_settled()` read `run$signal$control` and the run statuses `queued`, `requesting`, `streaming`, `tools`, `boundary` that this plan writes.

### Ambiguities in 04 and the reading this plan implements

1. `session_replay_new(block, header, envir, doc)`: 04 does not define `header` or `doc`. `header` is the parsed block header of 04 §11.5 as a named list of strings (`model`, `session`, `turn`, `value`, `fork`, ...) plus `doc` (document path) and `mode` (P15's replay mode) when known; `doc` is `list(path, format, template, code, output, text)`. P15 builds both.
2. `session_replay_new()` when a live session holds the header's id: 04 says it "returns" that session; this plan also records the block on it through `session_replay_apply()` (so `gptr.replay`, `seen` and the turn advance) and returns it.
3. A session rebuilt from JSONL for a replay emits `session_start` with reason `resume` (inside `store_rebuild(path, home)`, whose fixed signature has no reason); a reconstructed replay session emits `replay` at its first freeze.
4. `ctx.kernel` calling convention: 04 §10.6 lists the members but not how P02 calls them. Each implementation takes the `ctx` first, then the member's arguments positionally (P02's `ctx_call()`). `ctx` carries no plugin identity, so `send()`, `append_entry()` and `state()` take an optional last formal `extension = NULL`; P02's `ctx_call_plugin()` fills it positionally, only inside a handler, with the plugin name stripped of its `plugin:`/`builtin:` prefix (`"panel"`), and P06's `ctx_ext_label()` maps `NULL` to `"plugin"` and accepts either form. `append_entry()` writes `customType = "<plugin>.<type>"`; `send()` labels the queue item's `name` with it. (P02's own test stub names the formal `name`/`plugin`; positional calls make the names irrelevant.)
5. `ctx$abort()` from inside a tool raises the run's abort signal (the dispatcher skips the remaining calls and the next step settles the run with the reason); outside a tool it calls `run_abort()` at once.
6. `ctx$usage()` returns `gptr_usage(ctx$session)` (the aggregated `gptr_usage` view), not the per-request rows of `s$usage`; both have class `gptr_usage`.
7. Internal `.d` fields beyond 04 §5.1: `condition` (the stored unsignalled condition of the last terminal status, read by P08), `ledger` (the token ledger) and `estimator` (the EWMA state of 03 §12.5). `gptr_run` has private fields beyond 04 §7.6 (`shell`, `home`, `scratch`, `budget`, `budget_root`, `transfers`, `timers`, ...), and the live record one beyond 04 §5.1 (`budget_root`, ambiguity 19); other plans read only the contract fields.
8. `the$last` is set when a top-level session is created as well as when it runs (IC-71 "the most recently active session ... including one whose call was interrupted before assignment").
9. `str()` prints `<gptr_session s... | chat | idle | 1 turns | fake/fake-1>`: the 04 §5.1 template with "turns" kept literal for every count.
10. A replayed `value=` name that is not bound yet is recorded by name only (`gptr.value` with `turn`, `mode = "name"`, `name`; no `address`, `class`, `bytes`); the value resolves when first read.
11. 05 acceptance 7 and 8 name `s |> step` and `gptr()`; both are P08's. This plan proves the kernel form (`session_run()`), and P08's acceptance repeats the checks on the gateway.
12. P05's plan also defines `usage_rollup(rows)` (roll-up to root sessions for an aggregated view). P06 charges every request to the session and each live ancestor at write time (`usage_add()`, IC-66) and aggregates with request de-duplication in `gptr_usage()`; it does not call `usage_rollup()`. The two agree on totals.
13. `turn_end`'s `results` (04 §10.4: "tool results") are the tool-result messages of the turn (Pi's `toolResults`), not `gptr_tool_result` objects: a result's `value` may be a user object, which must not sit in the loop state or pass `redact_tree()` in an event payload (rule R1). `dispatch_tools()` therefore returns 04 §7.6's `results` and `terminate` plus `messages`.
14. `gptr.max_nested_calls` (IC-66: "a team or fan-out counts as one"): 04 names no run option for the grouping, so the children of one team or fan-out pass the same `opts$nested_group` (P19 sets it) and count once; the error is `gptr_error_budget` with `kind = "nested_calls"`, `budget` (the cap) and `used`, the IC-66 budget class with a kind outside the three `budget_<kind>` subclasses.
15. The run option `interactive` (04 §7.6: "a human can answer") is applied to the run's safety snapshot: `interactive = FALSE` sets `can_prompt = FALSE`, so the gate stops or denies instead of prompting (background runs, children without a human); `TRUE` cannot loosen the snapshot of `gptr_can_prompt()`.
16. A `session_before_fork` handler answering `list(cancel = TRUE, reason)` makes `gptr_fork()` signal `gptr_error_invalid_argument` carrying the reason (04 names no class for a cancelled fork).
17. `agent` queue items: `session_enqueue()` has no name argument in 04, so a sub-agent names itself by passing its report as `blocks` (an `agent_report` context block with `attrs = list(from = <name>)`), which `queue_item_message()` delivers as is; `extension` items get their `name` from the `ctx.kernel` `send()` member.
18. `run_start()` (and so `session_run()`) re-signals a failure that happens before the run is wired (a freeze that refuses the model, a store error) after settling the run with status `error`; 04's "raises nothing itself" is read as "maps no terminal status to a condition".
19. The run option `root` (04 §7.6, IC-66) when the root has no run (the container of a top-level team or fan-out): 04 does not say where the root's per-call budget lives. P06 keeps one pool per root on its live record (`budget_root`), created at the first child's run with the settings default merged with that child's `opts$budget` (P19 passes the call's budget to every child of one container), charged with the root's rolled-up usage since its creation. P19 creates a container per top-level call and refuses to continue one, so the pool is never reset. A child whose root is another session starts with its own share only (`min(<share>, <root remaining>)` holds because both are checked).
20. `secret_live_entries_set()` is P03's addition (its ambiguity A1). P06 installs `live_entries_all()` at load and again in every `live_new()`: P03's own test clears the slot with `secret_live_entries_set(NULL)` when it ends, and a scan that stayed inert for the rest of the process would break IC-70 silently.
21. `model = <spec:provider>` registered at rank 0 for one session (P08, P19): P05's catalog lists only process-level providers and `model_resolve(ref, strict = TRUE)` has no session argument, but it accepts a `gptr_provider` spec. `run_model_resolve(ref, sid)` therefore falls back to the session's `provider` record, narrowed to the declared model the reference names; `provider_stream()` already finds that record through `opts$session`.

### Executed validation

- The seven R files, the seven test files, the harness and the three oracle files of this plan were assembled into a scratch package (`DESCRIPTION`, `R/aaa-stubs.R` with stand-ins for the P01-P05 functions named above that follow 04, P05's `usage_empty()` copied verbatim, and an `.onLoad` running the `on_load()` expressions), and `devtools::test()` was run with `NOT_CRAN=true` after every task, first with the task's tests but without its implementation (red) and then with both (green). Every Step 2 and Step 4 summary line above is the measured one. The two SIGKILL tests ran for real (a child `Rscript` loading the scratch package with `pkgload::load_all()` and killed mid-stream and mid-append) and passed; the foreign-lock test ran against a live `Rscript` child.
- `devtools::document()` on the scratch package produced exactly the `NAMESPACE` lines of Task 16 and the eleven man pages with no roxygen warning; `devtools::run_examples()` ran every example of the five exports offline.
- Every ```` ```r ```` block of this plan was extracted to its own file and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'`: all parse. A `getParseData()` scan of every block finds no `<-` assignment and no `%>%`: the only `LEFT_ASSIGN` tokens are the two `<<-` in `run_chain()` (Task 5), which update the closure state of its `add()` helper as conventions §4 allows, and the other `<-` characters in code are inside the S3 method names `` `$<-.gptr_session` `` / `` `[[<-.gptr_session` `` and the strings of the Task 16 test. All R code is ASCII and no line exceeds 100 characters.
- Two defects of the earlier draft were found and fixed by this validation: settlement did not cancel the run's reactor task, so an aborted run that no pump visited again kept its session alive (the finaliser and split-brain tests failed); and a test helper registered a tool closure created inside the helper, which kept the helper's frame and the session alive in the registry.
- Review round (2026-10-01). The R code of P01-P05 was assembled from their plans in `dev/plan/` (P04's "replace the definitions" blocks applied) together with this plan's seven files (Task 14's one-line modification applied), P01's `setup.R` and `helper-fake.R`, and this plan's tests, harness, oracles and snapshot, into a scratch package (no stand-ins). Results with `NOT_CRAN=true`, R 4.4.3, testthat 3.3.2: `roxygen2::roxygenise()` wrote exactly the 17 `NAMESPACE` lines of Task 16 and the eleven man pages, with no warning from a P06 file; the examples of the five exports ran offline (before P08 the `@examplesIf` parts skip) and left no connection open; `devtools::test(filter = "session|agent")` gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 938 ]` (dispatch 116, loop 86, run 283, budget 74, live 33, object 190, store 156; both SIGKILL tests and both foreign-lock tests ran against real `Rscript` children); P01's `test-arch-layers.R` and `test-lint-rules.R` gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]`. Before the review fixes the same run gave one error (the checkpointer spec of Task 7 lacked the `undo`/`redo` that P02's validator requires) and `test-arch-layers.R` listed eleven L2 -> L3 layering violations from `agent-dispatch.R`; each test the review added was run once with its fix reverted and failed (2, 3, 1, 4 and 1 failed expectations; the `gptr_usage()` test errored with "row names contain missing values"). P01's and P02's own tests were run with and without the P06 files: the only one whose result changes is P02's "ctx members whose plan is not loaded signal gptr_error_not_available", which assumes that no `ctx.kernel` bootstrap service exists (see the review log).
- Cross-plan consolidation round (2026-10-01; see the consolidation log at the end). P01-P05 plus this plan were assembled again from `dev/plan/`, and every changed Step 2 and Step 4 line was measured: Task 3 `FAIL 33`/`PASS 106`, Task 5 `FAIL 14 | PASS 26`/`PASS 96`, Task 7 `FAIL 29 | PASS 42`/`PASS 166`, Task 8 unchanged (`FAIL 10 | PASS 66`/`PASS 85`), Task 9 `FAIL 15 | PASS 130`/`PASS 186`, Task 10 `FAIL 78 | PASS 398`/`PASS 613`, Task 11 `FAIL 5 | PASS 68`/`PASS 86`, Task 13 `FAIL 26 | PASS 116`/`PASS 191`, Task 15 `FAIL 12 | PASS 255`/`PASS 291`, and the suite `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 974 ]` (dispatch 130, loop 86, run 291, budget 86, live 35, object 190, store 156). The same suite with P07's R code also loaded gives `PASS 974` (before this round it gave three failures: the fallback freeze, the router test and the overflow test). With P03's test files added, `^(agent-run|auth-.*|session-live)$` stays green, so the installed `secret_late` callback changes no P03 result and survives P03's test clearing it. `test-arch-layers.R` reports no new layering edge.
- Finalize pass (2026-10-01; rows F1-F7 of the consolidation log, and the "Finalize pass" paragraph after its table). The lints that the consolidation run reported for this plan are fixed. The re-extracted `r` blocks lint clean with P01's linters (`indentation_linter = NULL`) and parse. The P06 suite, assembled with P01-P05, stays at `PASS 974` with unchanged per-file counts.

## Plan review log

Adversarial review of 2026-10-01 against 04 (with §15), 03, 05 P06, the conventions, reports 02 and G3 and the dependency plans P01-P05 in `dev/plan/`; every finding below was checked by running the assembled P01-P06 code (Self-review, Executed validation, "Review round").

| # | Severity | Location | Finding | Verdict | What changed, or why rejected |
|---|---|---|---|---|---|
| 1 | blocker | Task 7, `agent-dispatch.R` | The dispatcher (layer L2) called eleven functions of the L3 `session-*.R` files (`session_live()`, `session_data()`, `session_append()`, `entry_message()`, `entry_custom()`); P01's `test-arch-layers.R` reports them as layering violations as soon as P06 is in `R/`, so the M1 test suite and check go red | applied | Task 5 adds agent-area accessors to `agent-run.R` (`run_data()`, `run_live()`, `run_ctx()`, `run_ctx_sid()`, `run_append_message()`, `run_append_custom()`), which the dispatcher uses instead; Global Constraints (Layers) and Task 7 Consumes say so; Task 16 Step 4 and acceptance 1 run `^(arch-layers|lint-rules)$` -> `PASS 16` |
| 2 | major | Task 7 test "checkpointers wrap sequential mutating calls ..." | The test's `gptr_spec("checkpointer", ...)` had no `undo`/`redo`, which P02's checkpointer validator requires (04 §10.2 row 29), so the test errors and Task 7's Step 4 count is unreachable | applied | The spec now carries `undo` and `redo` functions with the required formals |
| 3 | major | Tasks 7 and 10, `dispatch_tools()`, `run_tools()` | `turn_end`'s `results` and the loop state (`lp$results`) held the `gptr_tool_result` objects, whose `value` may be a user object: rule R1 broken, and every `turn_end` ran `redact_tree()` over such values | applied | `dispatch_tools()` also returns the tool-result `messages` (04's two fields kept); the engine hands those to `loop_results()`, so `turn_end` carries messages (Pi's `toolResults`); new test "turn_end carries the tool-result messages, never the tools' R values (R1)"; ambiguity 13 |
| 4 | major | Task 13, `store_rebuild()` | The rebuilt session was registered under the recorded id (and set as `gptr_last()`) before `store_open()` took the lock; when another live process held the lock, the split-brain error left that half-built session live, so the next `gptr_resume()` returned it without a lock and appended to a file another process writes | applied | The foreign lock is checked before anything is registered; a failing `store_open()` is rolled back (a lock this process took is released, the registration undone with the new `live_forget()` of Task 3, the previous `the$last` restored); the finalizer ignores forgotten shells; new test "a file locked by another live process is not resumed and leaves no live session" |
| 5 | major | Task 10, `run_wire()` | The lock heartbeat was first scheduled 10 minutes after a run started, so a session whose runs are all shorter never refreshed its lock, and after 24 h another process took an actively used session's lock for stale (IC-59) | applied | `run_wire()` calls `run_heartbeat()` at once (touch now, then every 10 minutes); new test "each run touches its session's lock when it starts (heartbeat, IC-59)" |
| 6 | major | Task 5, `run_new()` | The run option `interactive` (04 §7.6: "a human can answer") was ignored by the gate: a background run or a child started with `interactive = FALSE` could still prompt through the UI | applied | `interactive = FALSE` sets the run snapshot's `can_prompt = FALSE`; new test "interactive = FALSE in the run options means nobody can answer the run's gate"; ambiguity 15 |
| 7 | major | Task 11, `gptr_usage()` | A group that is `NA` (System 1 log rows without a session, rows without an agent) made `data.frame()` fail ("row names contain missing values", from the named `vapply()` results) and `group == k` gave `NA` sums, so `gptr_usage()` errors once P13 logs System 1 calls | applied | `%in%` and `USE.NAMES = FALSE`; new test "gptr_usage() counts rows whose group is NA (process-level System 1 rows)" |
| 8 | minor | Task 10, `run_tools()`, `run_settle()` | A sequential batch queued in P04's tool FIFO but not yet started was never cancelled at settlement; the job's closure kept the run and the session alive until some later pump | applied | The FIFO item id is kept in `run$fifo` and cancelled with the task, timers and transfers; new test "an abort while a tool waits in the FIFO cancels the job; the session can be collected" (also proves 05 acceptance 7's "settled session is finalised") |
| 9 | minor | Task 13, `gptr_sessions()` | One unreadable session file (NUL bytes after a power loss, a file removed meanwhile) made the whole listing fail | applied | Each file summary is read inside `tryCatch()`; a damaged file is left out |
| 10 | minor | Global Constraints (Services), Task 15 Consumes/Produces, `ctx_kernel()` roxygen, ambiguity 4 | The `ctx.kernel` calling convention was described three different ways, none matching P02's `ctx_new()` (positional arguments; inside a handler only, the plugin name already stripped of `plugin:`); the code itself was compatible | applied | All four passages now describe P02's actual call; `ctx_ext_label()` (unchanged) accepts the bare name or a full source |
| 11 | minor | Self-review (Type and name consistency, Ambiguities) | The self-review said the P01, P02 and P04 plans were not written; several readings of 04 that the code implements were unrecorded (`opts$nested_group` and the `nested_calls` budget class, the class of a cancelled fork, how `agent` queue items name their sender, `run_start()` re-signalling a pre-wiring failure) | applied | The consistency bullet records the cross-plan checks; ambiguities 13-18 added; Executed validation gains the review-round bullet |
| 12 | minor | Steps 2 and 4 of Tasks 5, 8-13, 15, 16; Plan acceptance | The expected summary lines did not include the review's new tests | applied | Recomputed and confirmed by the run: the P06 suite is `PASS 938` (dispatch 116, loop 86, run 283, budget 74, live 33, object 190, store 156); acceptance rows 2, 5, 6, 7 give 525, 156, 473 and 223 |
| 13 | major | Task 10, `run_abort_only()`, `run_resignal_interrupt()` | Claim: the abort-only fallback catches the interrupt with an exiting `tryCatch(interrupt =)` and signals a newly built interrupt plus `invokeRestart("abort")` instead of letting R's own condition continue, unlike P08's `on.exit()` form | rejected | This is report 02 §5.8's `resignal_interrupt()`, confirmed in its verification log (item 42: enclosing handlers see it, `Rscript` halts, the console returns to top level); 03 §6.2 says programmatic calls re-signal; the condition has the same class and no fields; G3's "never an exiting `tryCatch(interrupt =)`" concerns tool frames, which still record interruptions with `on.exit()`; L18-L20 and the interrupt tests pass |
| 14 | major | P02's test "ctx members whose plan is not loaded signal gptr_error_not_available" (`test-ext-api.R`) | Once P06 registers the `ctx.kernel` bootstrap service, `ctx$mode()` no longer fails, so that P02 test fails in the full suite (the only P01/P02 test whose result P06 changes) | rejected | Not a P06 defect and not a P06 file: P06 must provide `ctx.kernel` (IC-34), and the test belongs to P02, which must remove `ctx.kernel` from `the$services` for its duration (save and restore, as its `local_bootstrap_service()` does). Flagged for the P02 review |
| 15 | minor | Task 7, `dispatch_one()` | Claim: input replaced by a `tool_call` hook's `modify` is not validated against the schema again | rejected | 04 §10.7 lets a `modify` replace the input "for later handlers and the tool"; the modified input still goes through `perm_check()`, whose policies classify exactly that input |
| 16 | minor | Task 5, `run_ui()` | Claim: the UI is resolved from the current options, not the run's `gptr.ui` snapshot (IC-53) | rejected | 04 §7.11 puts that resolution in P11's `ui.get` service ("resolution from the run's snapshot of `gptr.ui`"); P06 passes the session, through which P11 reaches the running run's snapshot |
| 17 | minor | Task 7 INFRA-10 test | Claim: 05 acceptance 3 names a 30 s timeout but the test uses `setTimeLimit(elapsed = 0.3)` | rejected | The code path is the same (an elapsed time limit inside the tool becomes an error result with paired events); a 30 s wait would only slow the suite, and Plan acceptance row 3 states the substitution |

## Cross-plan consolidation log

Consolidation of 2026-10-01 against 04 (with §15), 03, 05 and the plans P01-P23. Each finding was checked against the contract and the related plans; the changed plan was assembled with P01-P05 (and once more with P07's R code) and run (Self-review, Executed validation, "Cross-plan consolidation round"). Every `r` block parses, contains no `<-` assignment (only the two `<<-` of `run_chain()`'s closure helper) and no `%>%`, is ASCII and has no line over 100 characters.

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | interfaces | major | `test-agent-run.R`: the fallback freeze (Task 9), the fallback request (Task 9), "without a compactor the first overflow is terminal" (Task 10), the `run_ui()` test (Task 5); harness | applied | Valid: 04 §7.0 fallbacks are chosen with `ext_service_has()`, and P07/P11 register `prompt.freeze`, `request.build`, `prefix.guard`, `compact.should`, `compact.run` and `ui.get` in P01's bootstrap table from `on_load()`. Reproduced: with P07's code loaded the suite gave 3 failures. The harness gains `local_without_services(names, .env)` (saves `the$services`, drops the names, restores it on exit; Task 1 Produces lists it). The two fallback tests and "the first run freezes the prompt ... (fallback before P07)" hide `prompt.freeze`, `request.build`, `prefix.guard`, `context.first`, `context.turn`; the overflow test hides `compact.should`, `compact.run`; the `run_ui()` test hides `ui.get` (its second half uses a registry record, which still wins). The same run showed a third P07 interaction the checkers did not list: "a router session calls router.call before each request (IC-69)" saw reasons `compaction`, `turn` because P07's compactor asked the router first; that test now hides `compact.should`, `compact.run` too. With P07 loaded the suite is green (`PASS 974`); no expectation count changes |
| 2 | interfaces | major | Task 3, `R/session-live.R`, `test-session-live.R` | applied | Valid (IC-70, 04 §7.3; P03 ambiguity A1 and review row 6). New `live_entries_all()` (entries of `live_all()`, named by id), installed with `on_load(secret_live_entries_set(live_entries_all))` and again in `live_new()`, because P03's own test ends with `secret_live_entries_set(NULL)` and test files run alphabetically (`test-auth-*` before `test-session-*`). New test "secret_register() warns secret_late for a value a live session already holds (IC-70)" (2 expectations). Task 3 Consumes adds P03's `secret_live_entries_set(fun)` (and `secret_register()`, `vault_reset()` in tests); Produces adds `live_entries_all()`; ambiguity 20. P03's test files stay green with the callback installed |
| 3 | interfaces | major | Task 5, `run_budget_limits()`, `run_chain()` | applied | Valid: 04 §7.6 defines the run option `root` ("the root session id for budgets, IC-66") and IC-66 requires children to start with `min(<share>, <root remaining>)`; P19 passes `root = <container id>` for the children of a top-level team or fan-out, whose container has no run. Implemented as described in row 11 (one design for rows 3, 11 and 15) |
| 4 | interfaces | minor | Self-review, "Type and name consistency" | applied | `gateway_control_check()` was a stale name: the bullet now reads P08's `control_check()` (P08's `control_check = function(what)`) |
| 5 | shared-names | major | the same fallback tests as row 1; harness | applied | Duplicate of row 1. One helper serves both findings: `local_without_services()` takes a vector of names, so the suggested single-name `local_no_service()` was not added as a second helper |
| 6 | shared-names | minor | Self-review, "Type and name consistency" | applied | Duplicate of row 4; same one-word change |
| 7 | obligations | major | Task 7, `dispatch_nested()` | applied | Valid (04 §6.8: a `fun`-only `r` member gets no generated `execute`; 04 §7.6 and §7.10 promise the member's value through `dispatch_nested()`; P10 review row 5 reproduced `Tool wdemo/hello not found`). When the record has no `execute` but a `fun`, the dispatcher builds P02's `spec_tool_execute(tool$fun, tool[["output_tokens"]])` (L0, callable from L2); records with neither still give `Tool <name> not found`. New test "an r member declared with fun only runs through the generated execute (04 6.8)" (3 expectations: inside a run, the nested record, and outside a run). Task 7 Consumes adds `spec_tool_execute()` |
| 8 | obligations | major | Task 7, `perm_policies()` | applied | Valid (04 §10.2 row 12 "a throwing policy denies"; 04 §7.6 fail closed): a non-list answer (`"yes"`, `TRUE`) errored at `res$decision` outside the `tryCatch()`, and a decision of length 2 errored in `if`. A non-list answer now denies with "returned a malformed answer"; a decision that is not one known string denies with "returned an unknown decision"; `NULL` and a list without `decision` stay "no opinion". New test "a malformed policy answer denies instead of throwing (fail closed)" (5 expectations) |
| 9 | obligations | major | Task 3, `R/session-live.R` | applied | Duplicate of row 2 |
| 10 | obligations | major | Task 7, `perm_ask()` non-interactive stop | applied | Valid (IC-68, 04 §2.2 `noninteractive` row: "the `ask` tool in a non-interactive `manual` run (P11; status `blocked`)"; P11 self-review item 6 and review row 13). When the blocked call is the `ask` tool, the stored condition is `gptr_error_noninteractive` with `what = "ask"` and `questions` (the question texts, through the new `perm_ask_questions(input)`); `run$blocked` and the returned denial are unchanged, and every other tool keeps `gptr_error_permission`. New test "a non-interactive ask call stops blocked with gptr_error_noninteractive (IC-68)" (6 expectations); Global Constraints (Gate, Conditions) and Task 7 Produces updated |
| 11 | obligations | major | Task 5, `run_new()`, `run_budget_limits()`, `run_chain()` | applied | Valid (see row 3). `run_budget_root(s, opts)` returns the live session named by `opts$root` when it is another session. `run_budget_limits()` gives such a child only its own share, as a nested run. `run_budget_pool(s, opts)` creates, once per root without a run, an environment `budget_root` on the root's live record (`id = "root:<id>"`, `shell`, `budget` = the settings default merged with the call's budget, `usage_start`, `near`); `run_new()` keeps it in `run$budget_root`; `run_chain()` adds it, and also adds the root's own run when `opts$root` names a running session that the ancestor walk did not reach. `budget_check()`, `budget_near()` and `run_budget_extend()` work on it unchanged, because `usage_add()` already rolls every child's rows up to the root. The pool lives on the live record rather than in `.d` (runtime state that a `saveRDS()` copy must not carry). Not adopted: clearing the pool at the container's `agent_end`; P19 creates a new container for every top-level call and refuses to continue one (piped sessions are refused), so one pool per container is one budget per call (ambiguity 19). New test "children of a root without a run share one budget through opts$root (IC-66)" (12 expectations, two children of a run-less team container plus a running root); Global Constraints (Budgets), Task 5 Produces and Plan acceptance row 8 updated |
| 12 | obligations | major | Task 9, `run_target()` | applied | Valid (04 §6.1 `model = <spec:provider>`; P08 review row 17, P19 item 23c; P05 documents that `model_resolve()` accepts a `gptr_provider` spec "which is how a session-scoped `model = <spec>` resolves"). New `run_model_resolve(ref, sid)`: P05's catalog (`strict = FALSE`) first; else the session's `provider` record (`registry_get("provider", <id>, session = sid)`), narrowed to the declared model the reference names (by `id`, or the `ref` P08's specs may carry), resolved with `model_resolve(<spec>)`, with a thinking suffix kept when the model supports it; else the strict `model_resolve(ref)` for the classed `gptr_error_unknown_model`. `run_target()` and `run_route()` (router answers) use it. New test "run_target() resolves a provider registered for the session only (model = <spec>)" (3 expectations; api `fake`, models `m0` and `m1`, `offline = TRUE`); Task 9 Consumes and Produces updated; ambiguity 21 |
| 13 | obligations | minor | Task 10, `run_request()` prefix guard | applied | Valid (04 §3.1 `gptr.check_prefix`: `"event"`, `"warn"`, `"error"`; P07 review row 18 left the rethrow to P06). The handler re-signals a `gptr_error_internal` when `gptr_opt("check_prefix")` is `"error"`, so `run_fail()` settles the run with status `error`; any other failure stays a diagnostic. New test "a prefix break stops the run only under `gptr.check_prefix = "error"`" (5 expectations, with a stub `prefix.guard` registry record); Task 10 Produces updated |
| 14 | obligations | minor | Task 7, `perm_ask()` remember branch | applied | Valid: no policy reads `.d$rules`, P11's `builtin:permissions` stores remembered answers through the UI wrapper's `permissions:remember` channel (never for level 4, control or `ask_human`), and 04 assigns P06 no remember duty. The block is removed; the test "the UI answers asks when the run's snapshot can prompt" now expects `session_data(s)$rules$allow` to stay `character()` (same expectation count) |
| 15 | trace | major | Task 5, `run_budget_limits()`, `run_chain()`; Plan acceptance row 8 | applied | Duplicate of rows 3 and 11 (one implementation). Acceptance row 8 now names "a top-level container without a run still caps its children (IC-66)" and the new Task 5 test. The suggested 3 USD-per-request engine test was replaced by the deterministic Task 5 unit test with `usage_add()`, which exercises the same `budget_check()` path the engine calls before each request |
| F1 | finalize | minor | Task 1, `tests/testthat/fixtures/oracles/report02/harness.R`, header comment | applied | `commented_code_linter` (consolidation lint `P06_L00117.R:2`): the header line that quoted `source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)` as a comment is now prose ("The first line of every P06 test file sources this file with local = TRUE, locating it through testthat::test_path()."); the first lines of the test files are unchanged |
| F2 | finalize | minor | Tasks 3, 4, 7, 8, 9, 10, 12, 13: the oracle objects of `test-session-store.R`, `test-agent-run.R` and `test-agent-loop.R`; Task 1 harness, `expect_oracles_covered()` | applied | `object_name_linter` (`P06_L01063.R:2`, `P06_L04817.R:4`, `P06_L05889.R:4`): `S = oracle("store")`, `R = oracle("recovery")` and `L = oracle("loop")` are renamed `store_recs` (44 uses), `recovery_recs` (29 uses) and `loop_recs` (26 uses), after `oracle_title()`'s `recs` argument; every `oracle_title(<x>, "<id>")`, `expect_oracles_covered(<x>, ...)` and `unlist(<x>$R01$data)` was updated. They are test-local objects that 04 does not name; `grep` of `dev/plan/` and the consolidation index (`objects`: `S`, `R`, `L` defined only by P06) show no other plan using them, and the new names collide with nothing. `expect_oracles_covered()` matched the old upper-case names, so its pattern changes from `oracle_title\\([A-Z]+, ...` to `oracle_title\\([a-z_]+, ...`. Test titles (the oracle ids) and expectation counts are unchanged |
| F3 | finalize | minor | `queue_item_message()` (Task 1, `R/agent-loop.R`); `tool_result_hooks()` and `perm_request_record()` (Task 7, `R/agent-dispatch.R`); `run_fail()` (Task 10, `R/agent-run.R`); `entry_from_json()`, `custom_message` branch (Task 13, `R/session-store.R`) | applied | `brace_linter`, "either both or neither branch" (`P06_L00399.R:161`, `P06_L04116.R:154`, `P06_L04116.R:575`, `P06_L07091.R:622`, `P06_L08933.R:73`): the bare branch of each `if`/`else` is braced too; the values are unchanged |
| F4 | finalize | minor | `entry_custom()` (Task 3, `R/session-object.R`); the `Filter()` predicate of `run_initial_input()` (Task 10, `R/agent-run.R`); `blocks_from_json()` (Task 13, `R/session-store.R`) | applied | `brace_linter`, "wrap multi-line function bodies in curly braces" (`P06_L01273.R:153`, `P06_L07091.R:117`, `P06_L08933.R:105`): each body is wrapped in braces and now fits on one line; same expression |
| F5 | finalize | minor | Test helpers and inline tools, policies and hooks: the `run_ui()` test (Task 5, `test-agent-run.R`); the `tool_call` hook test, the policy and `permission_request` hook tests and the forwarded-request `risk` function (Task 7, `test-agent-dispatch.R`); the blocking `tool_call` hook (Task 10, `test-agent-loop.R`); `flaky()` (Task 10, `test-agent-run.R`); `file_entries()` (Task 10, `test-session-store.R`) | applied | `brace_linter`, "wrap multi-line function bodies in curly braces" (`P06_L02797.R:108`, `P06_L03626.R:115`, `:119`, `:365`, `:373`, `:386`, `:450`, `P06_L05889.R:191`, `P06_L06213.R:428`, `P06_L06863.R:53`): each anonymous or helper function body is braced; the returned lists are unchanged |
| F6 | finalize | minor | One-line `{ a; b }` blocks in tests: Task 4 and Task 12 `test-session-object.R` (the two read-only `expect_error()` probes, `capture.output()` of `print(s)`, `expect_message()` of `s$value` and of `gptr_fork(s)`); Task 7 and Task 10 `test-agent-dispatch.R` (the counting tools, the interrupt `tryCatch()`, the `seen` echo tool, the UI's `permission` callback, the length-stop tool); Task 10 `test-agent-loop.R` (the two flag tools, the interrupt `tryCatch()`, the nested `run_start()` probe); Task 10 `test-agent-run.R` (the interrupt `tryCatch()`) | applied | `brace_linter`, "opening curly braces ... followed by a new line", and `semicolon_linter` (`P06_L02151.R:38`, `:39`, `:65`, `:99`, `P06_L03626.R:26`, `:45`, `:91`, `:113`, `:409`, `P06_L05889.R:89`, `:177`, `:236`, `:308`, `P06_L06213.R:214`, `P06_L06767.R:8`, `P06_L07990.R:110`): each brace opens a multi-line block with one statement per line; the evaluated code is the same |
| F7 | finalize | minor | Section-header comments: Task 7 `test-agent-dispatch.R`; Task 11 `test-session-budget.R` and `R/session-budget.R`; Task 12 `test-session-object.R`; Task 13 `R/session-store.R` (two) | applied | `commented_code_linter` (`P06_L03626.R:280`, `P06_L07805.R:2`, `P06_L07873.R:1`, `P06_L07990.R:2`, `P06_L08933.R:313`, `P06_L08933.R:439`): headers such as `# ---- gptr_usage()` parse as R code. They now read `permission checks (IC-04, IC-53)`, `usage (gptr_usage)` (test and source), `forks (gptr_fork, INFRA-14)`, `list (gptr_sessions)` and `resume (gptr_resume)`; every header line stays within 100 characters |

Counts changed by this round (measured): `test-agent-dispatch.R` 116 -> 130, `test-agent-run.R` 283 -> 291, `test-session-budget.R` 74 -> 86, `test-session-live.R` 33 -> 35; the suite 938 -> 974; acceptance rows 2, 3, 6 and 7 give 533, 130, 481 and 225. The red and green lines of Tasks 3, 5, 7, 9, 10, 11, 13 and 15 and Task 16 Step 4 were updated to the measured values.

Finalize pass (2026-10-01, rows F1-F7): every row of `dev/research/assets/consolidation-lint-results.csv` for P06 except `indentation_linter` (now off) was fixed; no lint was silenced with `# nolint`. Verification: the 52 `r` blocks were re-extracted with the consolidation harness and linted with P01's `.lintr` linters (`indentation_linter = NULL`; `object_usage_linter` off for single blocks): no lints. Every block parses with `Rscript --vanilla`, has no `<-` or `%>%`, is ASCII and has no line over 100 characters. P01-P05 plus this plan were assembled again and the P06 suite was run before and after the pass: `PASS 974` both times with the same per-file counts (`test-agent-dispatch.R` 130, `test-agent-loop.R` 86, `test-agent-run.R` 291, `test-session-budget.R` 86, `test-session-live.R` 35, `test-session-object.R` 190, `test-session-store.R` 156), so no Step 2 or Step 4 line and no acceptance count changes. Linting the seven assembled `R/` files after `pkgload::load_all()` with `object_usage_linter` on also gives no lints. In the five test files, `object_usage_linter` reports "no visible global function definition" for the harness helpers (`test_session()`, `run_text()`, `local_store()`, `local_tool()` and others) wherever a top-level test helper function calls them, because the harness is sourced by each file rather than loaded as a `helper-*.R` file. This pass leaves those reports as they are: they come from the harness layout, not from a P06 code defect.

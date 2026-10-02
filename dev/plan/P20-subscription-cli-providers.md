# P20 Subscription CLI providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use the user's Claude plan through their own `claude` CLI and the ChatGPT plan through their own Codex CLI as two `process_jsonl` model routes (`claude-cli`, alias `claude_code`; `codex`) whose tools evaluate R in the live session through gptr's permission gate (REQ-12, REQ-34, INFRA-19).

**Architecture:** Three L1 files. `cli-common.R` finds the CLIs without starting a process (`options(gptr.cli_path)`, PATH, per-OS install locations; the `claude.cmd` shim refused), probes `--version`/`--help` once per command, prints one-time notices, reports cached status to `gptr_providers()`, holds the turn helpers both adapters share (one INFRA-02 stream per CLI turn, wire log, wall clock, a weak table of live children) and declares `builtin:cli`, whose hooks pass the run's mode and remaining budget to the adapters as request parameters and stop a child whose run ended mid-turn (interrupt control request, then `kill_all()`). `cli-claude.R` drives one long-lived `claude -p` child per session in stream-json mode (per run while budget flags apply, resuming the CLI session), answers the control protocol (`mcp_message` through the injected `opts$mcp_dispatch`, the single gate; `can_use_tool` through `opts$gate`) and reuses P12's Anthropic normaliser for `stream_event` lines; `cli-codex.R` runs one `codex exec --json --ignore-user-config ... -` per turn with the prompt on stdin, the MCP overrides pointing at `gptr_mcp_serve()` (token only in the child's environment), the sandbox mapping, control-file hashing and a turn cap.

**Tech Stack:** R (>= 4.2.0); processx and jsonlite through P04/P01 helpers; rlang (weak references); P05's `process_jsonl` transport on P04's reactor; P12's `anthropic_normaliser()`; P18's `mcp.dispatch_local`/`mcp.serve_ensure` services; testthat 3e and withr (tests only); a fake CLI written in R (`inst/gptr/fixtures/fake_cli.R`) run through `rscript_path()`.

**Spec:** dev/spec/03-architecture.md (§2.1-2.2, §3.2 rows `cli-*`, §3.3 `inst/gptr/fixtures/fake_cli.R`, §3.4 `test-live-cli.R` and `fixtures/cli/`, §6.5, §6.7, §6.13 `cli` backend, §6.18 rows 16 and 19, §8.3, §8.4), dev/spec/04-interface-contract.md (§2.2 `billing`, `cli_missing`, `pcli_version`, `billing_env`, `notice`; §3.1 `gptr.cli_path`, `gptr.cli_turn_timeout`; §3.2 `GPTR_MCP_TOKEN`; §4.2-4.5; §5.1 accessors; §5.11 `gptr_mcp_handle`; §7.0 services `mcp.dispatch_local`, `mcp.serve_ensure`; §7.3 `child_env()`; §7.4; §7.5; §7.12 `anthropic_normaliser()`; §7.18; §7.19; §7.20; §8.1; §8.4; §8.5; §10.2 rows 1-2; §10.3 `builtin:cli`; §10.4 `request_params`, `usage`, `agent_end`, `session_shutdown`; §10.6; §11.10; §12.2-12.4; §15 IC-33, IC-36, IC-45, IC-57, IC-58, IC-60, IC-61, IC-62, IC-65, IC-66), dev/spec/05-plan-decomposition.md (P20).

**Depends on:** P12, P18, P19 (and through them P01-P11, P14, P15, P17). **Milestone:** M4.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never `<-`; `<<-` only for closure state), native `|>` (never `%>%`), ASCII-only R sources (non-ASCII as `\u` escapes), `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()` for conditions (messages by concatenation, never glue), JSON through `json_encode()`/`json_decode()`, testthat 3e, no network and no real keys in tests, every process-spawning test calls `skip_on_cran()`, `Rscript --vanilla` from the repository root `/Users/wanjun/Desktop/gptr`, one commit per task whose message ends with the attribution line the executing harness specifies (conventions §10).

Plan-specific requirements (values copied verbatim from the spec):

- Function names: P20's internal functions and objects use the prefix `pcli_` (plan-route CLI), never `cli_`: P01's lint rule `cli_literal` (conventions §5, 04 §12.3, `tests/testthat/test-lint-rules.R` "R/ follows the package lint rules") flags every unqualified `cli_*()` call in `R/` whose first argument is not a literal, which would hit P20's own calls such as `cli_find(cli)` and `cli_version(path)` (231 hits in the review's scan). The three contract names of 04 §7.20 exist as one-line aliases, `cli_find(cli)`, `cli_version(path)` and `cli_probe(path)`, which P20's code never calls (their bodies call `pcli_find()`, `pcli_version()`, `pcli_probe()`, which the rule does not match). Option names (`gptr.cli_path`, `gptr.cli_turn_timeout`), request parameters (`cli_mode`, `cli_budget`), condition classes (`gptr_error_cli_missing`, `gptr_error_cli_version`, `gptr_warning_cli_sandbox`) and test-only helpers keep their names.
- Files and layer (03 §3.2): `cli-common.R` | L1 | "CLI discovery (native binaries preferred), minimum-version probe, one-time notice, billing-switch scrub" | built-in `cli` | P20; `cli-claude.R` | L1 | "`cli-claude` adapter: stream-json, control protocol, in-process `sdk` MCP, `can_use_tool`"; `cli-codex.R` | L1 | "`cli-codex` adapter: `codex exec --json --ignore-user-config -`, sandbox mapping, MCP via `-c`". L1 "may call L0" (and L1); "the run's gate, MCP dispatcher and tool-result builder arrive as injected `opts` callbacks [IC-33]"; `cli-claude.R` "uses only these" (IC-33).
- Contract rows (04 §7.20): `builtin_cli(gptr)` "registers providers `claude-cli` (alias `claude_code`, `type = "cli"`) and `codex` (alias `codex`), adapters `cli-claude` and `cli-codex` (`transport = "process_jsonl"`), a `status` function per provider for `gptr_providers()`"; `cli_find(cli = c("claude", "codex"))` "path from `gptr.cli_path`, then PATH, then the per-OS known locations of IC-65; native binaries only for claude (the npm `claude.cmd` shim is refused with an install hint); `gptr_error_cli_missing` otherwise"; `cli_version(path)`, `cli_probe(path)` "`package_version` from `--version` and a capability probe of `--help` (cached per path and mtime; run only on first use or `check = TRUE`); below the minimum (`claude` >= 2.0.0), or a `-p` that defaults to `--bare` without a documented opt-out, signals `gptr_error_cli_version`".
- claude argv (04 §8.5, 03 §8.3), exactly: `-p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --tools "" --strict-mcp-config --setting-sources "" --disable-slash-commands --mcp-config <file> --permission-prompt-tool stdio --permission-mode default --allowedTools mcp__gptr__* --system-prompt-file <file> --model <full id>`, "plus `--max-turns <n> --max-budget-usd <x>` when a budget is in force (IC-65, IC-66) (never `--bare`)". The `--mcp-config` file "contains `{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}`; the system-prompt file holds the session's frozen T0 + T1". "Per turn `send` = one `{"type":"user","message":{"role":"user","content":<blocks>},"parent_tool_use_id":null,"session_id":""}` line." `mcp_message` is answered as `{"type":"control_response","response":{"subtype":"success","request_id":…,"response":{"mcp_response":…}}}`; `can_use_tool` "`{"behavior":"allow","updatedInput":…}` or `{"behavior":"deny","message":…}`; unknown subtypes -> an error response. After `system/init`, an `apiKeySource` other than `"none"` aborts the turn with `gptr_error_billing`." "`result` lines end the turn (usage from `usage` and `total_cost_usd` as an estimate, route `plan-cli`); `rate_limit_event` updates the provider's plan status. Interrupt: `{"type":"control_request","request_id":…,"request":{"subtype":"interrupt"}}`, then `kill_all()` after the grace period."
- codex argv (04 §8.5, IC-65), exactly: `codex exec --json --ignore-user-config --skip-git-repo-check -m <full id> -C <wd> -c mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp -c mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN -c mcp_servers.gptr.default_tools_approval_mode="approve" -c mcp_servers.gptr.required=true -c mcp_servers.gptr.tool_timeout_sec=3600 --sandbox <read-only | workspace-write> -`; "resume: `codex exec resume <thread> --json ... -c sandbox_mode=<mode> -` (resume rejects `-s` and `-C`)"; "the prompt on stdin (`write_all()`), `GPTR_MCP_TOKEN` (a token bound to this session, IC-58) only in the child's environment (`child_env("cli-codex", set =)`); the MCP server comes from the `mcp.serve_ensure` service (P18); without httpuv/later/openssl the route runs on files only with a `notice`."
- Codex events (04 §8.5): "`thread.started`, `turn.started`, `item.started|updated|completed` (`agent_message` -> text, `reasoning` -> thinking, `mcp_tool_call`/`command_execution` -> informational `tool_execution_*` events), `turn.completed{usage}`, `turn.failed{error}`, `error`"; "gptr counts turns and cancels at the cap, with `gptr.cli_turn_timeout` per exec".
- Sandbox mapping (IC-65): "`plan`, `manual` and `edits` -> `read-only` (file changes go through gptr's gated `write`/`edit` over MCP, so edits-mode approval and checkpoints apply); `auto` -> `workspace-write`. Before a `workspace-write` exec gptr hashes the `control` files (IC-54) and refuses to load changed ones until the user confirms; the files checkpointer walks after each exec so `/undo` covers Codex's edits" (the walk is P16's `turn_end` hook for `type = "cli"` sessions); "On native Windows the sandbox is probed and the route falls back to `read-only` with a warning when it is not ready". Control files (IC-54): `.gptr/settings*.json`, `.gptr/mcp.json`, `.gptr/extensions/`, `.gptr/plugins/`, `.gptr/SYSTEM.md`, `.gptr/APPEND_SYSTEM.md`, `.gptr/agents/`, `.git/hooks/`, `.git/config`, `.Rprofile`, `Rprofile.site`, `Renviron.site` (the project-root members of the list).
- Child environments (IC-65, G6 §3.7, through P03's `child_env()` profiles `cli-claude` and `cli-codex`): claude removes "secret-like names, registered values, `^(CLAUDECODE$|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID$)` and `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_PROFILE`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_ORGANIZATION_ID`; keep `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_GIT_BASH_PATH`; `CLAUDE_CODE_USE_BEDROCK`/`VERTEX`/`FOUNDRY` are removed with the `billing_env` warning"; codex "removes `^(CODEX_MANAGED_|CODEX_SANDBOX)`, `CODEX_API_KEY`, `CODEX_ACCESS_TOKEN`, `OPENAI_API_KEY`, `OPENAI_BASE_URL` and keeps `CODEX_HOME`". Every profile points `R_ENVIRON_USER`/`R_PROFILE_USER` at empty files (IC-60). P05's `process_jsonl` transport calls `child_env(<env_profile>, set = <env>)`; P20 never calls `child_env()` with `provider =`.
- Minimum version (03 §8.3): "The minimum CLI version is probed (>= 2.0.0, the Agent SDK's floor; 2.1.261 tested)". "Never `--bare` (it never reads the subscription login [07]); a capability probe of `--help` and the version detects a CLI whose `-p` defaults to bare and passes the documented opt-out or stops with `gptr_error_cli_version`."
- Discovery (IC-65): "`options(gptr.cli_path = list(claude =, codex =))`, then PATH, then per-OS known locations (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `%USERPROFILE%\.local\bin`, WinGet links, and for codex the npm prefix resolved to the vendored `codex.exe`)"; "The providers' `status()` functions use only cached `Sys.which()` data unless `gptr_providers(check = TRUE)`; `check = FALSE` never spawns a process." P05 calls `status(check = check)` and reads `status`, `version`, `available` (P05 plan, ambiguity 18).
- Options (04 §3.1): `gptr.cli_path` | named list \| `NULL` | `NULL` | P20 | "explicit `claude`/`codex` paths (tests point them at the fake CLI, IC-65)"; `gptr.cli_turn_timeout` | `num(1)` | `3600` | P20 | "wall-clock seconds per CLI turn (IC-65)"; both read with `gptr_opt()`. The codex turn cap falls back to `gptr.max_turns` (`50L`). Settings default (IC-66, P08): `budget` `{tokens: 2000000, cost: 5, turns: null}`.
- Conditions (04 §2.2): `gptr_error_billing` (parent `provider`, field `source`) "the claude CLI reports an `apiKeySource` other than `"none"` on the plan route"; `gptr_error_cli_missing` (`cli`) "the `claude`/`codex` binary was not found"; `gptr_error_cli_version` (`cli`, `found`, `required`) "below the minimum version"; warning `gptr_warning_billing_env` (P03/P20; "names of removed billing variables"); message `gptr_message_notice` ("one-time notices: experimental routes, Codex overhead"). P20 addition to 04 §2.2's warnings: `gptr_warning_cli_sandbox` (P20; Codex's Windows sandbox not ready, the route runs read-only; once per process; the same class reports control files that a `workspace-write` exec changed, after the exec's terminal event). 04 §8.5 and IC-65 require a warning for the Windows fallback ("falls back to `read-only` with a warning") without naming its class and no listed class fits, so the class is an addition, recorded here so that the condition reference assembled by P25 lists it (self-review ambiguity 4). Adapters signal nothing after `start`: failures are one terminal `error` event (04 §8.1).
- Environment variable (04 §3.2): `GPTR_MCP_TOKEN` | P18/P20 | "set only in a child's environment: the bearer token of `gptr_mcp_serve()`".
- Messages (04 §4.2): CLI assistant messages carry `route = "plan-cli"`; usage (04 §4.3) has `estimated = FALSE` (the CLI reports usage) and the claude cost is `total_cost_usd` (P05's `usage_row()` keeps `u$cost$total` for route `plan-cli`).
- Wire log (04 §8.2, IC-65): "one file per session" at `cache/tmp/wire-<session id>.jsonl`, "each line open-append-close"; one line per CLI turn start and terminal event, never prompts or output.
- Model ids (03 §8.4, 04 §11.10): "CLI invocations always receive full ids"; "`claude-cli/default` and `codex/default` resolve through the CLI provider's `status()` to a full id before any invocation".
- Concurrency (03 §8.3, IC-57, IC-60): "one `claude-cli` child per session by default" (a child that carries `--max-turns`/`--max-budget-usd` serves only the run that started it, and the next run resumes the CLI session in a new child: the flags are fixed at launch while IC-66 budgets restart with every top-level call; Task 5); R tools never overlap (the claude `tools/call` runs from P04's tool FIFO of the run); a codex exec served by gptr's MCP server is marked with `reactor_served(run)` so a nested pump keeps servicing `later`; "Under `check_running()` every child-process pool ... is capped at 2" (`proc_pool_cap()`).
- Tests (04 §12.4, IC-45, IC-60): "`fixtures/cli/claude-<case>.ndjson`, `codex-<case>.jsonl` ... redacted CLI transcripts; `inst/gptr/fixtures/fake_cli.R` replays them as a fake `claude`/`codex`, run as `c(rscript_path(), fake_cli)` through `gptr.cli_path` with `offline = TRUE` provider records". Live tests (IC-65): "(`GPTR_LIVE_TESTS=true`) run Codex in a non-git temporary directory and require it to call the gptr MCP `r` tool".
- Copy safety (03 §6.4): P20 holds no user object and no frame; adapter state holds a process handle, ids and two temporary file paths.
- Policy (03 §8.3): the provider id avoids the Claude Code product name; `claude_code` is only an alias; "gptr never reads, stores or brokers Claude credentials"; "gptr never reads `~/.codex/auth.json`".

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `R/cli-common.R` | create (Task 1), append (Tasks 2-4, 8, 9), modify `builtin_cli()` (Tasks 9, 10) | discovery (`pcli_find()`), version and capability probes (`pcli_version()`, `pcli_probe()`), notices, cached `status()`, plan status, model entries and fake-CLI records, the turn helpers both adapters share, the weak child table, `pcli_stop_child()`, the `request_params`/`usage`/`agent_end`/`session_shutdown` hooks and `builtin:cli` |
| `R/cli-claude.R` | create (Task 5), append (Task 6) | the `cli-claude` adapter: argv, MCP-config and system-prompt files, stream-json user lines, the control protocol, the per-turn normaliser over P12's `anthropic_normaliser()` |
| `R/cli-codex.R` | create (Task 7) | the `cli-codex` adapter: argv and resume form, sandbox mapping and the Windows probe, the MCP handle and token, the stdin prompt, control-file hashing, the turn cap, the exec normaliser |
| `inst/gptr/fixtures/fake_cli.R` | create (Task 2) | the fake `claude`/`codex` CLI (answers `--version`/`--help`, logs argv, env names and stdin, replays a fixture, speaks the control protocol, calls gptr's HTTP MCP server) |
| `tests/testthat/fixtures/cli/local-fake-cli.R` | create (Task 1), append (Tasks 2-4, 6-8, 10) | test support sourced by the three test files (P20 owns `fixtures/cli/`, not a `helper-*.R` file) |
| `tests/testthat/fixtures/cli/claude-call2.ndjson`, `claude-apikey.ndjson`, `claude-hang.ndjson` | create (Task 6) | the redacted live capture of 07 §3.14 and two constructed claude transcripts |
| `tests/testthat/fixtures/cli/codex-call1.jsonl`, `codex-text.jsonl`, `codex-mcp.jsonl`, `codex-many.jsonl`, `codex-hang.jsonl` | create (Task 7) | the redacted capture of 08 §5.2 and constructed codex transcripts |
| `tests/testthat/fixtures/cli/claude-text.ndjson`, `claude-tool.ndjson`, `claude-slow.ndjson` | create (Task 8) | constructed claude transcripts for the end-to-end tests |
| `tests/testthat/fixtures/cli/codex-slow.jsonl` | create (Task 10) | a codex transcript with pauses for the INFRA-16 leg |
| `tests/testthat/test-cli-common.R` | create (Task 1), append (Tasks 2-4, 8-10) | tests of `cli-common.R` |
| `tests/testthat/test-cli-claude.R` | create (Task 5), append (Tasks 6, 8, 9) | tests of `cli-claude.R` and the claude route end to end (INFRA-19) |
| `tests/testthat/test-cli-codex.R` | create (Task 7), append (Task 10) | tests of `cli-codex.R`, the codex route end to end, the `cli` backend's auto rule and the CLI leg of INFRA-16 |
| `tests/testthat/test-live-cli.R` | create (Task 11) | gated live tests against the real CLIs |
| `NAMESPACE`, `man/` | unchanged | P20 exports nothing (every function is internal, `@noRd`) and registers no S3 method, so `devtools::document()` writes nothing |

## Interfaces used from earlier plans

Exact signatures (04 and the dependency plans); the tasks call nothing else.

| Owner | Function or record | Used for |
|---|---|---|
| P01 `aaa-state.R` | `on_load(expr)`; `ext_service_get(name)`; `ext_service_has(name)`; `` `%||%` `` | declaring `builtin:cli`; the `mcp.serve_ensure` service |
| P01 `utils-options.R`, `utils-conditions.R` | `gptr_opt(name)` (`cli_path`, `cli_turn_timeout`, `max_turns`); `setting_get(key, session = NULL, default = NULL)`; `gptr_abort(message, class, ..., .data = NULL, call = NULL)`; `gptr_warn(message, class, ..., .data = NULL, .once = NULL)`; `gptr_inform(message, class, ..., .data = NULL, .once = NULL)`; `check_choice(x, choices, arg)` | options, the budget setting, conditions |
| P01 `utils-paths.R`, `utils-encoding.R`, `utils-hash.R`, `json-*.R` | `user_home()`; `rscript_path()`; `project_root(path = getwd())`; `path_norm(path)`; `path_rel(path, root = project_root())`; `write_utf8(path, text, eol = "\n", bom = FALSE, final_newline = TRUE)`; `as_utf8(x)`; `hash_file(path)`; `id_new(prefix = "", n = 10L)`; `json_encode(x, pretty = FALSE)`; `json_decode(text)`; `json_obj()`; `json_verbatim(text)` | paths, files, ids, JSON |
| P01 `provider-message.R`, `provider-events.R` | `msg_assistant(content, api, provider, model, usage = NULL, stop_reason = "stop", response_id = NULL, response_model = NULL, error_message = NULL, raw_stop_reason = NULL, thinking_level = NULL, route = "api", request_id = NULL, timestamp = NULL)`; `block_text(text, signature = NULL)`; `block_thinking(thinking, signature = NULL, redacted = FALSE, data = NULL, origin = NULL)`; `ev_new(type, ...)`; in tests `msg_user()`, `msg_text()`, `block_context()`, `block_image()` | messages and INFRA-02 events |
| P01 tests (`helper-fake.R`, `setup.R`) | `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())`; `local_gptr_options(..., .env = parent.frame())`; `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))`; `setup.R` redirects `HOME` and sets `GPTR_REPLAY=replay` | test environment |
| P02 | `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`; `gptr_provider(id, api, base_url = NULL, auth = NULL, models = NULL, compat = list(), type = c("chat", "classifier", "cli"), headers = list(), discover = NULL, status = NULL, aliases = character(), local = FALSE, offline = FALSE, rate = NULL)`; `gptr_adapter(api, transport = c(...), build = NULL, parse = NULL, stream = NULL, classify = NULL, capabilities = list())`; factory API `gptr$register(spec)`, `gptr$on(event, handler, matcher = NULL)`; in tests `gptr_register(spec)` (returns an unregister function), `gptr_spec(kind, name, ...)` (kind `service`, field `fun`, IC-34), `registry_get(kind, name, session = NULL)`, `gptr_registry(kind = NULL, diagnostics = FALSE)` (columns `kind`, `name`, `source`) | registration |
| P03 | `child_env(profile, pass = character(), set = character(), provider = NULL)` (profiles `cli-claude`, `cli-codex`; warning `gptr_warning_billing_env` with field `variables`); `redact(x, profile = "persist")` | probe environments, redaction of the wire log and of error text |
| P04 | `proc_run(command, args = character(), input = NULL, timeout = 120, env = NULL, wd = NULL, echo = FALSE)`; `write_all(p, data)`; `write_close(p)`; `kill_all(p, grace = 2)`; `reactor_now()`; `reactor_timer(at, fn, run = NULL)`; `reactor_cancel(ids)`; `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`; `reactor_enqueue_tool(run, fn)`; `reactor_served(run, served = TRUE)` (P04 plan); `wire_log_path(session)`, `wire_log_append(path, line)` (P04 plan); `proc_pool_cap(n)`; `pid_alive(pid, create_time = NULL)` | probes, the stdin writer, timers, the FIFO, the wire log |
| P05 | `provider_stream(model, context, opts, emit, done, run = NULL)` with the `process_jsonl` transport: `build()` returns `list(start = list(command, args, env_profile, env = named chr, wd) \| NULL, send = list(...), close_stdin = lgl(1))`; the child lives in `opts$state$process` (a new `start` kills the old child); lines arrive as `list(data, obj)`; `opts$send(obj)` writes one JSON line; `usage_new(...)`; `model_resolve(ref, strict = TRUE)`; `gptr_providers(check = FALSE)` calls `status(check = check)` | the transport, usage records, model ids |
| P06 | events (04 §10.4): `request_params` (patch chain; payload `provider`, `model`, `params` limited to the adapter's `capabilities$request_params`), `usage` (`row`), `agent_end` (`status`, `reason`, ...), `session_shutdown` (`reason`); `ctx` members (04 §10.6) `ctx$session`, `ctx$run`, `ctx$mode()`, `ctx$state()`, `ctx$get(kind, name)`; the injected `opts$gate`, `opts$mcp_dispatch`, `opts$signal`, `opts$run`, `opts$session` (04 §8.1); in tests `gptr()`, `gptr_wait(x, timeout = Inf)`, `gptr_cancel(x)` and the session accessors `$text`, `$status`, `$id`, `$messages`, `$cost`, `$kind` | hooks and end-to-end tests |
| P11 tests | `local_scripted_ui(answers = list(), .env = parent.frame())` (log column `method`, value `"permission"`) | the gated-once test |
| P12 | `anthropic_normaliser(model, opts)` -> `list(push, push_parsed, finish, fail, message)` | claude `stream_event` lines |
| P18 | services `mcp.dispatch_local` `function(message, session) list` (reached through the injected `opts$mcp_dispatch`, IC-33) and `mcp.serve_ensure` `function(session) <gptr_mcp_handle>` (`session` is the `gptr_session` object: P18's `mcp_serve_ensure()` checks its class, so builtin:cli's `request_params` hook calls it with `ctx$session`; fields `url`, `port`, `token_env`, `config` with `config$codex$env[[token_env]]` = the token, `stop()`, 04 §5.11); `gptr_mcp_serve(..., stop = FALSE)` in tests | live R for both routes |
| P19 | `subagent_backend(agent, model)` (the `auto` rule); `gptr_agent(..., model = NULL, ..., backend = c("auto", "inline", "worker", "cli"), ...)`; teams through `gptr(agents = list(...))` | the `cli` backend tests (IC-36) |

## Interfaces this plan produces

| Name | Contract |
|---|---|
| `builtin_cli(gptr)` | 04 §7.20 (declared with `on_load(ext_declare_builtin("cli", builtin_cli))`); providers `claude-cli` (`api = "cli-claude"`, `type = "cli"`, `aliases = "claude_code"`) and `codex` (`api = "cli-codex"`, `aliases = "codex"`), each with `models` (`default` plus full ids) and `status = function(check = FALSE) list(status, available, path, version, default_model, plan)`; adapters `cli-claude`, `cli-codex` (`transport = "process_jsonl"`, `capabilities$request_params = c("cli_mode", "cli_budget")`); hooks `request_params`, `usage`, `agent_end`, `session_shutdown` |
| `cli_find(cli = c("claude", "codex"))` (implemented as `pcli_find()`) | 04 §7.20; returns the command (executable followed by prefix arguments) with attribute `cli` |
| `cli_version(path)`, `cli_probe(path)` (implemented as `pcli_version()`, `pcli_probe()`) | 04 §7.20; the probe returns `list(cli, version, bare_default, bare_optout, resume, missing)` |
| `pcli_claude_build(model, context, opts)`, `pcli_claude_parse(model, opts)`, `pcli_codex_build(model, context, opts)`, `pcli_codex_parse(model, opts)` | 04 §8.1 `build`/`parse` of a `process_jsonl` adapter |
| `pcli_stop_child(state, wait_ack = TRUE, grace = 2)`, `pcli_tracked(session)` | internal: stop a session's CLI child (interrupt for claude mid-turn, stdin closed, then `kill_all()`); the adapter state of a session |
| `pcli_codex_ensure(session)`, `pcli_codex_mcp(opts)`, `pcli_codex_forget(session)` | internal: the per-session MCP record (URL, port, token) that the `request_params` hook fills from `mcp.serve_ensure(<session object>)` and the codex adapter reads by session id |
| `pcli_fake_command(cli, case, fixtures, log)`, `pcli_fake_provider(cli, id = NULL, models = NULL)` | internal, for tests and examples: the fake CLI's command for `options(gptr.cli_path)` and its `offline = TRUE` provider record (IC-45, IC-60) |
| `inst/gptr/fixtures/fake_cli.R`, `tests/testthat/fixtures/cli/*` | 04 §12.4 |

## Tasks

1. Discovery of the claude and codex CLIs
2. The fake CLI, version and capability probes, notices
3. Status, plan status, model entries and fake-CLI records
4. Turn helpers, the child table and stopping a child
5. The cli-claude adapter: argv, files and the turn's input
6. The cli-claude normaliser: control protocol, stream, result
7. The cli-codex adapter
8. builtin:cli and the claude route end to end
9. Stopping CLI children: interrupt then kill (INFRA-19)
10. The codex route end to end and the CLI leg of INFRA-16
11. The gated live test

---

### Task 1: Discovery of the claude and codex CLIs

**Files:**
- Create: `R/cli-common.R`
- Create: `tests/testthat/fixtures/cli/local-fake-cli.R`
- Test: `tests/testthat/test-cli-common.R` (create)

**Interfaces:**
- Consumes: `gptr_opt(name)`, `check_choice(x, choices, arg)`, `user_home()`, `gptr_abort(message, class, ..., .data = NULL, call = NULL)`, `` `%||%` `` (P01); in tests `rscript_path()` (P01).
- Produces: `cli_find(cli = c("claude", "codex"))` (04 §7.20; a contract alias of the implementation `pcli_find()`, see Global Constraints) -> chr, the normalised executable followed by any prefix arguments, with attribute `cli`; `gptr_error_cli_missing` with field `cli` (04 §2.2). Private: `pcli_cache` (process-level data: discovery results, versions, probes, plan status and, from Task 4, the weak child table), `pcli_cache_clear()`, `pcli_install_hint`, `pcli_is_windows()`, `pcli_path_dirs()`, `pcli_exe_names(cli)`, `pcli_on_path(cli)`, `pcli_known_paths(cli)`, `pcli_is_shim(path)`, `pcli_codex_vendored(shim)`, `pcli_record(cli, path = NULL, version = NULL, error = NULL)`, `pcli_forget(cli)`, `pcli_found(cli, cmd)`, `pcli_refuse_shim(cli, shim)`, `pcli_identity(cmd)`. Test support: `fake_cli_fixtures()`, `cli_billing_vars`.

Adapted from `cc_find_cli()` of report 07 §5.7 (verified live; verification log item 37 confirms the install paths) with the review fixes of IC-65: PATH is scanned with `file.exists()`/`file.access()` instead of `Sys.which()` (which runs `which` on Unix, and `status()` must never start a process), native executables anywhere on PATH come before `.cmd`/`.bat` shims (07 §6.2: the official SDK prefers `claude.exe`), the npm `claude.cmd` shim is refused (so the empty-string arguments `--tools ""` and `--setting-sources ""` reach a native binary intact), and an npm `codex.cmd` shim resolves to its vendored `codex.exe` (08 §3.11, §6.2). The `~/.claude/local` location comes from the same verified prototype.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/cli/local-fake-cli.R` (the shared test support; later tasks append to it):

```r
# tests/testthat/fixtures/cli/local-fake-cli.R -- shared support of test-cli-*.R (P20).
# Each test-cli-*.R file sources it as its first statement, with local = TRUE, from the path
# testthat::test_path("fixtures", "cli", "local-fake-cli.R") (P20 owns fixtures/cli/, not a
# helper-*.R file). Tests run inside the gptr namespace, so internal functions are visible.

# The fixtures directory of the fake CLI, absolute (fixed when this file is sourced, so tests
# that change the working directory, such as local_project(), still find it)
cli_fixture_dir = normalizePath(testthat::test_path("fixtures", "cli"), winslash = "/")
fake_cli_fixtures = function() cli_fixture_dir

# The variables that switch a CLI to API billing (G6 3.7; P03 removes them with a billing_env
# warning). The helpers unset them, so a developer's own environment never adds a warning.
cli_billing_vars = c("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE",
                     "ANTHROPIC_BASE_URL", "ANTHROPIC_FEDERATION_RULE_ID",
                     "ANTHROPIC_ORGANIZATION_ID", "CLAUDE_CODE_USE_BEDROCK",
                     "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "OPENAI_API_KEY",
                     "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL")
```

Create `tests/testthat/test-cli-common.R`:

```r
# tests/testthat/test-cli-common.R -- discovery, probes, notices, status, the shared turn
# helpers and builtin:cli (P20)

source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# ---- discovery (Task 1) ------------------------------------------------------------------------

test_that("pcli_find() uses options(gptr.cli_path) and keeps prefix arguments", {
  pcli_cache_clear()
  withr::local_options(gptr.cli_path = list(claude = c(rscript_path(), "--vanilla", "fake.R")))
  path = pcli_find("claude")
  expect_identical(as.vector(path[-1L]), c("--vanilla", "fake.R"))
  expect_identical(attr(path, "cli"), "claude")
  expect_true(file.exists(path[[1L]]))
  expect_identical(pcli_identity(path), "claude")
  expect_identical(pcli_cache$status$claude$path, path[[1L]])
})

test_that("a missing command signals gptr_error_cli_missing with the install hint", {
  withr::local_options(gptr.cli_path = list(codex = file.path(tempdir(), "no-such-codex")))
  err = expect_error(pcli_find("codex"), class = "gptr_error_cli_missing")
  expect_identical(err$cli, "codex")
  expect_match(conditionMessage(err), "codex login", fixed = TRUE)
  withr::local_options(gptr.cli_path = NULL)
  empty = withr::local_tempdir()
  local_mocked_bindings(pcli_on_path = function(cli) character(),
                        pcli_known_paths = function(cli) file.path(empty, cli))
  err = expect_error(pcli_find("claude"), class = "gptr_error_cli_missing")
  expect_match(conditionMessage(err), "options(gptr.cli_path", fixed = TRUE)
  expect_true(is.na(pcli_cache$status$claude$path))
})

test_that("pcli_find() scans PATH without a process, then the per-OS install locations", {
  home = withr::local_tempdir()
  bin = file.path(home, ".local", "bin")
  dir.create(bin, recursive = TRUE)
  file.create(file.path(bin, "claude"))
  Sys.chmod(file.path(bin, "claude"), "0755")
  withr::local_options(gptr.cli_path = NULL)
  withr::local_envvar(PATH = withr::local_tempdir())
  local_mocked_bindings(user_home = function() home, pcli_is_windows = function() FALSE)
  expect_identical(pcli_find("claude")[[1L]],
                   normalizePath(file.path(bin, "claude"), winslash = "/"))
  on_path = withr::local_tempdir()
  file.create(file.path(on_path, "claude"))
  Sys.chmod(file.path(on_path, "claude"), "0755")
  withr::local_envvar(PATH = on_path)
  expect_identical(pcli_find("claude")[[1L]],
                   normalizePath(file.path(on_path, "claude"), winslash = "/"))
})

test_that("the Windows install locations include WinGet links and the npm prefix", {
  local_mocked_bindings(pcli_is_windows = function() TRUE, user_home = function() "C:/Users/me")
  withr::local_envvar(LOCALAPPDATA = "C:/Users/me/AppData/Local",
                      APPDATA = "C:/Users/me/AppData/Roaming")
  claude = pcli_known_paths("claude")
  expect_true("C:/Users/me/.local/bin/claude.exe" %in% claude)
  expect_true("C:/Users/me/AppData/Local/Microsoft/WinGet/Links/claude.exe" %in% claude)
  expect_true("C:/Users/me/AppData/Roaming/npm/codex.cmd" %in% pcli_known_paths("codex"))
  expect_identical(pcli_exe_names("claude"), c("claude.exe", "claude.cmd", "claude.bat"))
})

test_that("a .cmd claude is refused with the install hint", {
  dir = withr::local_tempdir()
  shim = file.path(dir, "claude.cmd")
  writeLines("@echo off", shim)
  withr::local_options(gptr.cli_path = list(claude = shim))
  err = expect_error(pcli_find("claude"), class = "gptr_error_cli_missing")
  expect_match(conditionMessage(err), "install.ps1", fixed = TRUE)
  withr::local_options(gptr.cli_path = NULL)
  local_mocked_bindings(pcli_on_path = function(cli) shim,
                        pcli_known_paths = function(cli) character())
  err = expect_error(pcli_find("claude"), class = "gptr_error_cli_missing")
  expect_match(conditionMessage(err), "only native executables", fixed = TRUE)
})

test_that("a codex npm shim resolves to its vendored codex.exe", {
  npm = withr::local_tempdir()
  shim = file.path(npm, "codex.cmd")
  writeLines("@echo off", shim)
  exe = file.path(npm, "node_modules", "@openai", "codex", "node_modules", "@openai",
                  "codex-win32-x64", "vendor", "x86_64-pc-windows-msvc", "bin", "codex.exe")
  dir.create(dirname(exe), recursive = TRUE)
  file.create(exe)
  withr::local_envvar(PROCESSOR_ARCHITECTURE = "AMD64")
  expect_identical(pcli_codex_vendored(shim), exe)
  withr::local_options(gptr.cli_path = NULL)
  local_mocked_bindings(pcli_on_path = function(cli) shim,
                        pcli_known_paths = function(cli) character())
  expect_identical(pcli_find("codex")[[1L]], normalizePath(exe, winslash = "/"))
  expect_identical(pcli_identity(pcli_find("codex")), "codex")
})

test_that("the contract name cli_find() of 04 7.20 is pcli_find()", {
  withr::local_options(gptr.cli_path = list(claude = c(rscript_path(), "--vanilla", "fake.R")))
  expect_identical(names(formals(cli_find)), "cli")
  expect_identical(cli_find("claude"), pcli_find("claude"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`; every test errors, with ``could not find function "pcli_cache_clear"``, ``could not find function "pcli_find"``, ``object 'cli_find' not found``, ``Can't find binding for `pcli_is_windows` `` and ``could not find function "pcli_codex_vendored"``.

- [ ] **Step 3: Write the implementation**

Create `R/cli-common.R`:

```r
# Subscription CLI providers (P20): discovery of the claude and codex CLIs, version and
# capability probes, one-time notices, cached status, the turn helpers shared by the two
# process_jsonl adapters, and builtin:cli (architecture 8.3; contract 7.20, 8.5, IC-65).
# Layer L1 (architecture 2.2): these files call L0 and L1 helpers only; the run's permission
# gate, MCP dispatcher and stdin writer arrive as injected `opts` callbacks (IC-33), and the
# run's mode and budget arrive as request parameters patched in by builtin:cli's
# `request_params` hook (contract 10.4).
#
# Options (P25 collects them into ?gptr_options; P01's gptr_opt() holds the defaults):
#   gptr.cli_path          named list or NULL (default NULL): explicit commands, for example
#                          list(claude = "/opt/homebrew/bin/claude"); an element may be a
#                          character vector, the command followed by prefix arguments (the
#                          fake CLI of the tests is c(rscript_path(), "--vanilla", <fake_cli.R>,
#                          ...), IC-60).
#   gptr.cli_turn_timeout  num(1) (default 3600): wall-clock seconds of one CLI turn.

#' Process-level data of P20: discovery results, versions, capability probes, plan status, the
#' weak table of live CLI children by session id (a process table like P04's job table,
#' architecture 2.2 rule 5; never run state) and, from Task 7, the per-session MCP records of
#' the codex route
#' @noRd
pcli_cache = new.env(parent = emptyenv())

#' Forget every cached discovery, version, probe and plan status (the child table and the MCP
#' records stay)
#' @noRd
pcli_cache_clear = function() {
  keep = c("children", "mcp")
  rm(list = setdiff(ls(pcli_cache, all.names = TRUE), keep), envir = pcli_cache)
  invisible(NULL)
}

#' Install hints used by gptr_error_cli_missing and gptr_error_cli_version (07 6.2, 08 3.11)
#' @noRd
pcli_install_hint = c(
  claude = paste0("Install the native claude CLI (macOS and Linux: curl -fsSL ",
                  "https://claude.ai/install.sh | bash; Windows PowerShell: irm ",
                  "https://claude.ai/install.ps1 | iex), then run `claude` once to sign in."),
  codex = paste0("Install the Codex CLI (brew install --cask codex, or npm install -g ",
                 "@openai/codex; Windows PowerShell: irm https://chatgpt.com/codex/install.ps1 ",
                 "| iex), then run `codex login`.")
)

#' TRUE on native Windows (a P20 wrapper, so tests can mock it without touching P01)
#' @noRd
pcli_is_windows = function() identical(.Platform$OS.type, "windows")

#' The directories of PATH, in order
#' @noRd
pcli_path_dirs = function() {
  dirs = strsplit(Sys.getenv("PATH", unset = ""), .Platform$path.sep, fixed = TRUE)[[1L]]
  unique(dirs[nzchar(dirs)])
}

#' File names a CLI may have: native executables first, then the shims gptr refuses
#' @noRd
pcli_exe_names = function(cli) {
  if (pcli_is_windows()) paste0(cli, c(".exe", ".cmd", ".bat")) else cli
}

#' Candidates for a CLI on PATH, found without starting a process (Sys.which() runs `which`
#' on Unix, and IC-65 forbids process I/O in status())
#'
#' Native executables anywhere on PATH come before shims: the official SDK prefers claude.exe
#' over an earlier-on-PATH claude.cmd (07 6.2).
#' @noRd
pcli_on_path = function(cli) {
  dirs = pcli_path_dirs()
  if (!length(dirs)) return(character())
  cands = as.vector(outer(dirs, pcli_exe_names(cli), file.path))
  ok = file.exists(cands) & !dir.exists(cands)
  if (!pcli_is_windows()) ok = ok & file.access(cands, 1L) == 0L
  cands[ok]
}

#' Per-OS install locations searched after PATH (IC-65): RStudio and Positron on macOS do not
#' source shell profiles, so ~/.local/bin is often missing from PATH (07 6.3)
#' @noRd
pcli_known_paths = function(cli) {
  home = user_home()
  if (pcli_is_windows()) {
    local = Sys.getenv("LOCALAPPDATA", unset = file.path(home, "AppData", "Local"))
    roaming = Sys.getenv("APPDATA", unset = file.path(home, "AppData", "Roaming"))
    dirs = c(file.path(home, ".local", "bin"), file.path(local, "Microsoft", "WinGet", "Links"),
             file.path(roaming, "npm"))
    return(as.vector(outer(dirs, pcli_exe_names(cli), file.path)))
  }
  dirs = c(file.path(home, ".local", "bin"), "/opt/homebrew/bin", "/usr/local/bin",
           file.path(home, ".npm-global", "bin"))
  if (identical(cli, "claude")) dirs = c(dirs, file.path(home, ".claude", "local"))
  file.path(dirs, cli)
}

#' Is a path a batch shim that cmd.exe would re-parse ("BatBadBut", 07 6.2)?
#' @noRd
pcli_is_shim = function(path) grepl("[.](cmd|bat)$", path, ignore.case = TRUE)

#' The native codex.exe that the npm codex.cmd shim launches, or NULL (08 3.11, 6.2)
#' @noRd
pcli_codex_vendored = function(shim) {
  arm = grepl("arm|aarch", Sys.getenv("PROCESSOR_ARCHITECTURE"), ignore.case = TRUE)
  pkg = if (arm) "codex-win32-arm64" else "codex-win32-x64"
  triple = if (arm) "aarch64-pc-windows-msvc" else "x86_64-pc-windows-msvc"
  base = file.path(dirname(shim), "node_modules", "@openai")
  tail = file.path(pkg, "vendor", triple, "bin", "codex.exe")
  cands = c(file.path(base, "codex", "node_modules", "@openai", tail), file.path(base, tail))
  hit = cands[file.exists(cands)]
  if (length(hit)) hit[[1L]] else NULL
}

#' Record a discovery or version result in the cache that status() reads (IC-65)
#' @noRd
pcli_record = function(cli, path = NULL, version = NULL, error = NULL) {
  st = pcli_cache$status %||% list()
  cur = st[[cli]] %||% list()
  if (!is.null(path)) cur$path = path[[1L]]
  if (!is.null(version)) cur$version = as.character(version)
  cur["error"] = list(error)
  cur$time = Sys.time()
  st[[cli]] = cur
  pcli_cache$status = st
  invisible(cur)
}

#' Forget the cached discovery of one CLI
#' @noRd
pcli_forget = function(cli) {
  st = pcli_cache$status %||% list()
  st[[cli]] = NULL
  pcli_cache$status = st
  invisible(NULL)
}

#' A found command: the executable normalised, prefix arguments kept, tagged with its CLI
#' @noRd
pcli_found = function(cli, cmd) {
  cmd = as.character(cmd)
  cmd[[1L]] = normalizePath(cmd[[1L]], winslash = "/", mustWork = FALSE)
  pcli_record(cli, path = cmd[[1L]])
  structure(cmd, cli = cli)
}

#' Refuse a batch shim with the install hint (07 6.2; IC-65)
#' @noRd
pcli_refuse_shim = function(cli, shim) {
  pcli_record(cli, path = NA_character_, error = "shim refused")
  gptr_abort(paste0("gptr does not run ", shim, ": cmd.exe re-parses the arguments of a ",
                    ".cmd or .bat shim, and gptr runs only native executables. ",
                    pcli_install_hint[[cli]]),
             "cli_missing", cli = cli)
}

#' Locate the claude or codex CLI (contract 7.20, IC-65)
#'
#' Order: `options(gptr.cli_path)`, then PATH (scanned without starting a process), then the
#' per-OS install locations. Only native executables run: a claude.cmd shim is refused with
#' the install hint; behind a codex.cmd shim the vendored codex.exe is used when present.
#' @param cli "claude" or "codex".
#' @return chr: the command (normalised) followed by any prefix arguments, attribute `cli`.
#' @noRd
pcli_find = function(cli = c("claude", "codex")) {
  cli = check_choice(cli, c("claude", "codex"), "cli")
  opt = gptr_opt("cli_path")
  if (!is.null(opt) && !is.null(names(opt)) && cli %in% names(opt)) {
    cmd = as.character(unlist(opt[[cli]], use.names = FALSE))
    if (!length(cmd) || !nzchar(cmd[[1L]]) || !file.exists(cmd[[1L]])) {
      pcli_record(cli, path = NA_character_, error = "not found")
      gptr_abort(paste0("The ", cli, " command set in options(gptr.cli_path) does not exist: ",
                        if (length(cmd)) cmd[[1L]] else "(empty)", ". ", pcli_install_hint[[cli]]),
                 "cli_missing", cli = cli)
    }
    if (pcli_is_shim(cmd[[1L]])) {
      exe = if (identical(cli, "codex")) pcli_codex_vendored(cmd[[1L]]) else NULL
      if (is.null(exe)) pcli_refuse_shim(cli, cmd[[1L]])
      cmd[[1L]] = exe
    }
    return(pcli_found(cli, cmd))
  }
  shims = character()
  for (cand in unique(c(pcli_on_path(cli), pcli_known_paths(cli)))) {
    if (!file.exists(cand) || dir.exists(cand)) next
    if (!pcli_is_shim(cand)) return(pcli_found(cli, cand))
    exe = if (identical(cli, "codex")) pcli_codex_vendored(cand) else NULL
    if (!is.null(exe)) return(pcli_found(cli, exe))
    shims = c(shims, cand)
  }
  if (length(shims)) pcli_refuse_shim(cli, shims[[1L]])
  pcli_record(cli, path = NA_character_, error = "not found")
  gptr_abort(paste0("The ", cli, " CLI was not found on PATH or in the usual install ",
                    "locations. ", pcli_install_hint[[cli]], " Or set options(gptr.cli_path = ",
                    "list(", cli, " = \"<path>\"))."), "cli_missing", cli = cli)
}

#' The contract name of pcli_find() (04 7.20). P20's own code calls pcli_find(): P01's lint rule
#' `cli_literal` flags unqualified cli_*() calls whose first argument is not a literal
#' @noRd
cli_find = function(cli = c("claude", "codex")) pcli_find(cli)

#' Which CLI a found command belongs to (its `cli` attribute)
#' @noRd
pcli_identity = function(cmd) {
  cli = attr(cmd, "cli")
  if (is.character(cli) && length(cli) == 1L && cli %in% c("claude", "codex")) return(cli)
  if (grepl("codex", paste(cmd, collapse = " "), ignore.case = TRUE)) "codex" else "claude"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 26 ]`

- [ ] **Step 5: Commit**

```bash
git add R/cli-common.R tests/testthat/test-cli-common.R tests/testthat/fixtures/cli/local-fake-cli.R
git commit -m "feat(cli): find the claude and codex CLIs without starting a process"
```

---

### Task 2: The fake CLI, version and capability probes, notices

**Files:**
- Create: `inst/gptr/fixtures/fake_cli.R`
- Modify: `R/cli-common.R` (append)
- Modify: `tests/testthat/fixtures/cli/local-fake-cli.R` (append)
- Test: `tests/testthat/test-cli-common.R` (append)

**Interfaces:**
- Consumes: `child_env(profile, pass = character(), set = character(), provider = NULL)` (P03; profiles `cli-claude`, `cli-codex`), `proc_run(command, args = character(), input = NULL, timeout = 120, env = NULL, wd = NULL, echo = FALSE)` (P04; never a shell, R only through `rscript_path()`), `as_utf8(x)`, `gptr_inform(message, class, ..., .data = NULL, .once = NULL)`, `rscript_path()` (P01); `pid_alive(pid, create_time = NULL)` (P04) in the test support.
- Produces: `cli_version(path)` -> `package_version`, `cli_probe(path)` -> `list(cli, version, bare_default, bare_optout, resume, missing)` (04 §7.20, both cached per command and executable mtime; contract aliases of the implementations `pcli_version()` and `pcli_probe()`); `gptr_error_cli_version` with fields `cli`, `found`, `required`; `pcli_notice(cli)` (a `gptr_message_notice` once per route, `.once = "cli_notice:<cli>"`); `pcli_fake_command(cli = c("claude", "codex"), case = "text", fixtures, log)` -> the fake CLI's command for `options(gptr.cli_path)`. Private: `pcli_min_version` (`claude = "2.0.0"`), `pcli_profile(cli)`, `pcli_cache_key(cmd)`, `pcli_run(cmd, args, timeout = 30)`, `pcli_version_forget(path)`, `pcli_flags(help)`, `pcli_bare_state(help)`. The fake CLI's command-line and fixture grammar are documented at the top of `fake_cli.R`. Test support: `local_fake_cli_path(cli, case = "text", .env = parent.frame())`, `fake_log(fake, kind = NULL)`, `fake_argv(fake)`, `fake_env_names(fake)`, `fake_prompts(fake)`, `fake_pids(fake)`, `expect_all_dead(pids)`.

The fake CLI adapts the verified offline fake of report 07 §5.9 (verification log item 32: it "needs R >= 4.4.0 for base `%||%`", so the script defines its own) and the stdin handling of 08 §5.1 (the looping writer of verification item 54 is P04's `write_all()` on the gptr side; the fake reads stdin to EOF in binary). Its `--help` texts reproduce the relevant lines of `claude --help` 2.1.261 and `codex exec --help` 0.157.0 (07 §2.13, 08 §2.E, 15 §2.9). The `--bare` probe follows 15 §2.9's verifier note ("`--bare` ... will become the default for `-p` in a future release", so the subscription path may later need an explicit opt-out): a help line that names `--bare` with "default" and `-p`/`--print` (and not "future") means bare by default; `--no-bare` is the opt-out passed when the help lists it. The probes run through `child_env("cli-<name>")`, so even `--version` never sees a billing variable. The test support unsets the billing variables of G6 §3.7 and passes this session's library paths in `R_LIBS` (setup.R moves `HOME`, so a user library would not be found by the child Rscript).

- [ ] **Step 1: Write the failing test**

Create `inst/gptr/fixtures/fake_cli.R`:

```r
# fake_cli.R -- a fake `claude` / `codex` CLI for gptr's tests (P20; contract 12.4, IC-60).
#
# Run through rscript_path(), never by name:
#   Rscript --vanilla fake_cli.R --fake-cli <claude|codex> --fake-case <case> \
#           --fake-dir <fixtures dir> --fake-log <log file> <the real CLI's argv ...>
# It answers --version, --help and `exec --help` like the real CLIs (claude 2.1.261, codex-cli
# 0.157.0; case "old" reports older versions, "bare-default"/"bare-optout" change the claude
# help, "old"/"noresume" the codex help), logs its argv, pid, environment variable NAMES (never
# values), stdin lines and the start ("turn") and end ("turn_done") of each claude turn as JSON
# lines to the log file, and replays
# <fixtures dir>/claude-<case>.ndjson or codex-<case>.jsonl line by line. Fixture lines that are
# JSON objects with a "fake" key are directives:
#   {"fake":"sleep","seconds":0.5}                       pause
#   {"fake":"hang"}                                      claude: wait for stdin (an interrupt
#                                                        control request then ends the turn as
#                                                        aborted); codex: sleep for an hour
#   {"fake":"exit","status":1}                           exit with a status
#   {"fake":"mcp","method":"tools/call","params":{}}     claude: ask the host over mcp_message
#   {"fake":"can_use_tool","tool_name":"..","input":{}}  claude: ask the host for permission
#   {"fake":"mcp_call","tool":"r","arguments":{}}        codex: call gptr's HTTP MCP server
#   {"fake":"write_file","path":"x.txt","text":".."}     codex: write a file in its directory
# Other lines are printed verbatim after replacing $TOOL_TEXT (text of the last MCP result,
# JSON-escaped), $THREAD (the codex thread id) and $PROMPT_BYTES (bytes codex read on stdin).
# Base R, jsonlite and (for mcp_call only) curl. It never reads credentials or calls a model.

# gptr's internal infix is not visible in this script and base R has one only from 4.4.0
`%||%` = function(a, b) if (is.null(a)) b else a # nolint: object_name_linter.

argv = commandArgs(trailingOnly = TRUE)
opt = list(cli = "claude", case = "text", dir = ".", log = "")
while (length(argv) >= 2L && startsWith(argv[[1L]], "--fake-")) {
  opt[[sub("^--fake-", "", argv[[1L]])]] = argv[[2L]]
  argv = argv[-(1:2)]
}

to_json = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}
from_json = function(x) {
  Encoding(x) = "UTF-8"
  tryCatch(jsonlite::fromJSON(x, simplifyVector = FALSE), error = function(e) NULL)
}
out = function(txt) {
  writeLines(txt, stdout(), useBytes = TRUE)
  flush(stdout())
}
log_line = function(kind, ...) {
  if (!nzchar(opt$log)) return(invisible(NULL))
  con = file(opt$log, open = "ab")
  on.exit(close(con))
  writeLines(to_json(list(kind = kind, pid = Sys.getpid(), t = as.numeric(Sys.time()), ...)),
             con, useBytes = TRUE)
  invisible(NULL)
}
json_inner = function(x) {
  j = to_json(x)
  substr(j, 2L, nchar(j) - 1L)
}

state = new.env()
state$n = 0L
state$tool_text = ""
state$thread = "00000000-0000-4000-8000-000000000001"
state$session = "11111111-1111-4111-8111-111111111111"
state$prompt_bytes = 0L
state$queue = list()
state$hanging = FALSE

fill = function(ln) {
  ln = gsub("$TOOL_TEXT", json_inner(state$tool_text), ln, fixed = TRUE)
  ln = gsub("$THREAD", state$thread, ln, fixed = TRUE)
  gsub("$PROMPT_BYTES", as.character(state$prompt_bytes), ln, fixed = TRUE)
}

# ---- probes: --version, --help, exec --help, sandbox -----------------------------------------
if ("--version" %in% argv) {
  old = identical(opt$case, "old")
  out(if (identical(opt$cli, "claude")) {
    if (old) "1.9.0 (Claude Code)" else "2.1.261 (Claude Code)"
  } else {
    if (old) "codex-cli 0.100.0" else "codex-cli 0.157.0"
  })
  quit(save = "no", status = 0L)
}
if (identical(opt$cli, "codex") && length(argv) && identical(argv[[1L]], "sandbox")) {
  log_line("sandbox", argv = I(argv))
  quit(save = "no", status = 0L)
}
if ("--help" %in% argv) {
  if (identical(opt$cli, "claude")) {
    bare_default = "  --bare                 Minimal mode (the default with -p/--print)"
    bare = switch(opt$case,
                  "bare-optout" = c(bare_default, "  --no-bare              Full mode"),
                  "bare-default" = bare_default,
                  "  --bare                 Minimal mode: skip hooks, plugins and CLAUDE.md")
    out(c("Usage: claude [options] [command] [prompt]", "",
          "  -p, --print            Print response and exit (useful for pipes)",
          "  --output-format <format>  \"text\", \"json\" or \"stream-json\"",
          "  --input-format <format>   \"text\" or \"stream-json\"",
          "  --include-partial-messages  Include partial message chunks",
          "  --verbose              Override verbose mode setting from config",
          "  --tools <tools...>     Built-in tools; \"\" disables all",
          "  --mcp-config <configs...>  Load MCP servers from JSON files or strings",
          "  --strict-mcp-config    Only use MCP servers from --mcp-config",
          "  --setting-sources <sources>  Comma-separated setting sources",
          "  --disable-slash-commands  Disable all skills",
          "  --permission-mode <mode>  Permission mode for the session",
          "  --allowedTools, --allowed-tools <tools...>  Tools to allow",
          "  --model <model>        Model for the current session",
          "  --resume [value]       Resume a conversation by session ID",
          bare))
  } else {
    resume = if (identical(opt$case, "noresume")) character() else
      "  resume  Resume a previous session by id or pick the most recent with --last"
    flags = if (identical(opt$case, "old")) {
      c("  --json                 Print events to stdout as JSONL", "  -m, --model <MODEL>")
    } else {
      c("  --json                 Print events to stdout as JSONL",
        "  --ignore-user-config   Do not load $CODEX_HOME/config.toml",
        "  --skip-git-repo-check  Allow running outside a Git repository",
        "  -s, --sandbox <SANDBOX_MODE>", "  -C, --cd <DIR>", "  -m, --model <MODEL>",
        "  -c, --config <key=value>")
    }
    out(c("Run Codex non-interactively", "", "Usage: codex exec [OPTIONS] [PROMPT] [COMMAND]",
          "", "Commands:", resume, "", "Options:", flags))
  }
  quit(save = "no", status = 0L)
}

# ---- a session --------------------------------------------------------------------------------
log_line("argv", argv = I(argv))
log_line("env", names = I(sort(names(Sys.getenv()))))
log_line("start", wd = getwd())
ext = if (identical(opt$cli, "claude")) ".ndjson" else ".jsonl"
script = readLines(file.path(opt$dir, paste0(opt$cli, "-", opt$case, ext)), encoding = "UTF-8",
                   warn = FALSE)
script = script[nzchar(trimws(script))]

# ---- claude: stream-json on stdin and stdout, control protocol both ways ----------------------
if (identical(opt$cli, "claude")) {
  inp = file("stdin", open = "r")
  next_msg = function() {
    repeat {
      ln = readLines(inp, n = 1L, encoding = "UTF-8", warn = FALSE)
      if (!length(ln)) return(NULL)
      if (!nzchar(ln)) next
      log_line("stdin", line = ln)
      m = from_json(ln)
      if (is.list(m)) return(m)
    }
  }
  reply = function(id, response) {
    out(to_json(list(type = "control_response",
                     response = list(subtype = "success", request_id = id,
                                     response = response))))
  }
  aborted_result = function() {
    out(to_json(list(type = "result", subtype = "error_during_execution", is_error = TRUE,
                     terminal_reason = "aborted_streaming", result = "",
                     session_id = state$session, total_cost_usd = 0, num_turns = 1L,
                     usage = list(input_tokens = 0L, output_tokens = 0L,
                                  cache_read_input_tokens = 0L,
                                  cache_creation_input_tokens = 0L))))
  }
  host_request = function(m) {
    sub = m$request$subtype %||% ""
    if (identical(sub, "interrupt")) {
      log_line("interrupt")
      reply(m$request_id, list(still_queued = list()))
      if (isTRUE(state$hanging)) {
        state$hanging = FALSE
        aborted_result()
      }
      return(invisible(NULL))
    }
    if (identical(sub, "initialize")) {
      handshake()
      return(reply(m$request_id, list(commands = list(), models = list())))
    }
    out(to_json(list(type = "control_response",
                     response = list(subtype = "error", request_id = m$request_id,
                                     error = paste("Unsupported control request subtype:",
                                                   sub)))))
  }
  ask = function(request) {
    state$n = state$n + 1L
    id = paste0("cli_req_", state$n)
    out(to_json(list(type = "control_request", request_id = id, request = request)))
    repeat {
      m = next_msg()
      if (is.null(m)) quit(save = "no", status = 0L)
      if (identical(m$type, "control_response") && identical(m$response$request_id, id)) {
        return(m$response)
      }
      if (identical(m$type, "control_request")) {
        host_request(m)
      } else {
        state$queue[[length(state$queue) + 1L]] = m
      }
    }
  }
  mcp = function(method, params = NULL, notify = FALSE) {
    message = list(jsonrpc = "2.0", method = method)
    if (!notify) message$id = state$n + 100L
    if (!is.null(params)) message$params = params
    ask(list(subtype = "mcp_message", server_name = "gptr", message = message))
  }
  handshake = function() {
    mcp("initialize", list(protocolVersion = "2025-06-18",
                           capabilities = structure(list(), names = character()),
                           clientInfo = list(name = "fake-claude", version = "0.0.1")))
    mcp("notifications/initialized", notify = TRUE)
    mcp("tools/list")
    log_line("handshake")
    invisible(NULL)
  }
  run_turn = function() {
    for (ln in script) {
      d = from_json(ln)
      if (!is.list(d) || is.null(d$fake)) {
        out(fill(ln))
        next
      }
      if (identical(d$fake, "hang")) {
        state$hanging = TRUE
        return(invisible(FALSE))
      }
      if (identical(d$fake, "sleep")) Sys.sleep(as.numeric(d$seconds %||% 0.1))
      if (identical(d$fake, "exit")) quit(save = "no", status = as.integer(d$status %||% 1L))
      if (identical(d$fake, "mcp")) {
        r = mcp(d$method, d$params)
        content = r$response$mcp_response$result$content
        state$tool_text = if (length(content)) content[[1L]]$text %||% "" else ""
        log_line("mcp", method = d$method, text = state$tool_text)
      }
      if (identical(d$fake, "can_use_tool")) {
        r = ask(list(subtype = "can_use_tool", tool_name = d$tool_name,
                     input = d$input %||% structure(list(), names = character()),
                     tool_use_id = d$tool_use_id %||% "toolu_fake"))
        log_line("permission", behavior = r$response$behavior %||% "none")
      }
    }
    invisible(TRUE)
  }
  repeat {
    if (length(state$queue)) {
      m = state$queue[[1L]]
      state$queue = state$queue[-1L]
    } else {
      m = next_msg()
    }
    if (is.null(m)) break
    if (identical(m$type, "control_request")) {
      host_request(m)
    } else if (identical(m$type, "user")) {
      log_line("turn")
      if (isTRUE(run_turn())) log_line("turn_done")
    }
  }
  log_line("end")
  quit(save = "no", status = 0L)
}

# ---- codex: the prompt on stdin until EOF, JSONL on stdout ------------------------------------
con = file("stdin", open = "rb")
chunks = list()
repeat {
  b = readBin(con, "raw", 65536L)
  if (!length(b)) break
  chunks[[length(chunks) + 1L]] = b
}
close(con)
prompt = if (length(chunks)) do.call(c, chunks) else raw()
state$prompt_bytes = length(prompt)
prompt_file = if (nzchar(opt$log)) paste0(opt$log, ".", Sys.getpid(), ".prompt") else ""
if (nzchar(prompt_file)) writeBin(prompt, prompt_file)
log_line("prompt", bytes = length(prompt), file = prompt_file)
if (length(argv) >= 3L && identical(argv[[2L]], "resume")) state$thread = argv[[3L]]

mcp_url = function() {
  hit = grep("^mcp_servers[.]gptr[.]url=", argv, value = TRUE)
  if (length(hit)) sub("^mcp_servers[.]gptr[.]url=", "", hit[[1L]]) else ""
}
mcp_post = function(url, token, body, sid = NULL) {
  h = curl::new_handle()
  hdr = list(`Content-Type` = "application/json", Accept = "application/json, text/event-stream",
             Authorization = paste("Bearer", token), `MCP-Protocol-Version` = "2025-11-25")
  if (!is.null(sid)) hdr[["Mcp-Session-Id"]] = sid
  do.call(curl::handle_setheaders, c(list(h), hdr))
  curl::handle_setopt(h, postfields = to_json(body), followlocation = 0L, timeout = 120L)
  curl::curl_fetch_memory(url, handle = h)
}
mcp_body = function(res) {
  txt = rawToChar(res$content)
  Encoding(txt) = "UTF-8"
  if (!grepl("^[[:space:]]*[{[]", txt)) {
    lines = strsplit(txt, "\r?\n")[[1L]]
    txt = paste(sub("^data: ?", "", grep("^data:", lines, value = TRUE)), collapse = "\n")
  }
  from_json(txt) %||% list()
}
mcp_call = function(d) {
  url = mcp_url()
  token = Sys.getenv("GPTR_MCP_TOKEN")
  if (!nzchar(url) || !nzchar(token)) {
    state$tool_text = "no gptr MCP server"
    log_line("mcp", status = NA, text = state$tool_text)
    return(invisible(NULL))
  }
  params = list(protocolVersion = "2025-11-25",
                capabilities = structure(list(), names = character()),
                clientInfo = list(name = "fake-codex", version = "0.0.1"))
  init = mcp_post(url, token,
                  list(jsonrpc = "2.0", id = 1L, method = "initialize", params = params))
  sid = curl::parse_headers_list(init$headers)[["mcp-session-id"]]
  mcp_post(url, token, list(jsonrpc = "2.0", method = "notifications/initialized"), sid)
  res = mcp_post(url, token, list(jsonrpc = "2.0", id = 2L, method = "tools/call",
                                  params = list(name = d$tool, arguments = d$arguments)), sid)
  body = mcp_body(res)
  content = body$result$content
  state$tool_text = if (length(content)) content[[1L]]$text %||% "" else body$error$message %||% ""
  log_line("mcp", status = res$status_code, text = state$tool_text)
  invisible(NULL)
}

for (ln in script) {
  d = from_json(ln)
  if (!is.list(d) || is.null(d$fake)) {
    out(fill(ln))
    next
  }
  if (identical(d$fake, "sleep")) Sys.sleep(as.numeric(d$seconds %||% 0.1))
  if (identical(d$fake, "hang")) Sys.sleep(3600)
  if (identical(d$fake, "exit")) quit(save = "no", status = as.integer(d$status %||% 1L))
  if (identical(d$fake, "write_file")) writeLines(d$text %||% "", d$path)
  if (identical(d$fake, "mcp_call")) mcp_call(d)
}
log_line("end")
quit(save = "no", status = 0L)
```

Append to `tests/testthat/fixtures/cli/local-fake-cli.R`:

```r
# Point options(gptr.cli_path) at the fake CLI in one case for the calling test
local_fake_cli_path = function(cli, case = "text", .env = parent.frame()) {
  dir = withr::local_tempdir(.local_envir = .env)
  log = file.path(normalizePath(dir, winslash = "/"), "fake-log.jsonl")
  path = pcli_fake_command(cli, case, fixtures = fake_cli_fixtures(), log = log)
  paths = getOption("gptr.cli_path") %||% list()
  paths[[cli]] = path
  withr::local_options(gptr.cli_path = paths, .local_envir = .env)
  # the fake Rscript child finds jsonlite and curl in this session's libraries (setup.R moves
  # HOME, so a user library would not be found by default)
  withr::local_envvar(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
                      .local_envir = .env)
  withr::local_envvar(stats::setNames(rep(NA_character_, length(cli_billing_vars)),
                                      cli_billing_vars), .local_envir = .env)
  list(path = path, log = log, cli = cli)
}

# Rows of a fake CLI's log (JSON lines), optionally of one kind
fake_log = function(fake, kind = NULL) {
  if (!file.exists(fake$log)) return(list())
  lines = readLines(fake$log, encoding = "UTF-8", warn = FALSE)
  rows = lapply(lines[nzchar(lines)], json_decode)
  if (is.null(kind)) return(rows)
  Filter(function(r) identical(r[["kind"]], kind), rows)
}

# The argv of the fake's session runs (not its --version/--help/sandbox probes)
fake_argv = function(fake) {
  lapply(fake_log(fake, "argv"), function(r) as.character(unlist(r[["argv"]])))
}

# Environment variable names each session run of the fake saw
fake_env_names = function(fake) {
  lapply(fake_log(fake, "env"), function(r) as.character(unlist(r[["names"]])))
}

# The stdin prompts a fake codex received, in order, as raw bytes
fake_prompts = function(fake) {
  lapply(fake_log(fake, "prompt"), function(r) readBin(r[["file"]], "raw", file.size(r[["file"]])))
}

# Process ids of the fake's session runs
fake_pids = function(fake) {
  vapply(fake_log(fake, "start"), function(r) as.integer(r[["pid"]]), 1L)
}

# Every process is gone within 10 seconds
expect_all_dead = function(pids) {
  deadline = Sys.time() + 10
  alive = function() any(vapply(pids, function(p) isTRUE(pid_alive(p)), NA))
  while (alive() && Sys.time() < deadline) Sys.sleep(0.1)
  expect_false(alive())
}
```

Append to `tests/testthat/test-cli-common.R`:

```r
# ---- version and capability probes, notices (Task 2) -------------------------------------------

test_that("pcli_bare_state() detects a -p that defaults to --bare and its opt-out", {
  plain = pcli_bare_state("  --bare   Minimal mode: skip hooks, plugins and CLAUDE.md")
  expect_false(plain$bare_default)
  expect_null(plain$bare_optout)
  future = pcli_bare_state("  --bare   Will become the default for -p in a future release")
  expect_false(future$bare_default)
  s = pcli_bare_state(paste0("  --bare   Minimal mode (the default with -p/--print)\n",
                            "  --no-bare  Full mode"))
  expect_true(s$bare_default)
  expect_identical(s$bare_optout, "--no-bare")
  s = pcli_bare_state("  --bare   Minimal mode (the default with -p/--print)")
  expect_true(s$bare_default)
  expect_null(s$bare_optout)
})

test_that("pcli_version() and pcli_probe() read the fake CLIs and cache per command", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_fake_cli_path("claude", "text")
  local_fake_cli_path("codex", "text")
  path = pcli_find("claude")
  expect_identical(pcli_version(path), package_version("2.1.261"))
  probe = pcli_probe(path)
  expect_false(probe$bare_default)
  expect_null(probe$bare_optout)
  expect_identical(pcli_cache$status$claude$version, "2.1.261")
  codex = pcli_probe(pcli_find("codex"))
  expect_true(codex$resume)
  expect_identical(codex$version, "0.157.0")
  local_mocked_bindings(proc_run = function(...) stop("spawned a process"))
  expect_identical(pcli_version(path), package_version("2.1.261"))
  expect_identical(pcli_probe(path)$version, "2.1.261")
})

test_that("an old or bare-only claude and an old codex signal gptr_error_cli_version", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_fake_cli_path("claude", "old")
  err = expect_error(pcli_version(pcli_find("claude")), class = "gptr_error_cli_version")
  expect_identical(err$found, "1.9.0")
  expect_identical(err$required, "2.0.0")
  expect_identical(pcli_cache$status$claude$error, "outdated")
  local_fake_cli_path("claude", "bare-default")
  expect_error(pcli_probe(pcli_find("claude")), class = "gptr_error_cli_version")
  local_fake_cli_path("claude", "bare-optout")
  expect_identical(pcli_probe(pcli_find("claude"))$bare_optout, "--no-bare")
  local_fake_cli_path("codex", "old")
  err = expect_error(pcli_probe(pcli_find("codex")), class = "gptr_error_cli_version")
  expect_match(err$required, "--ignore-user-config", fixed = TRUE)
  local_fake_cli_path("codex", "noresume")
  expect_false(pcli_probe(pcli_find("codex"))$resume)
})

test_that("the contract names cli_version() and cli_probe() of 04 7.20 are the probes", {
  expect_identical(names(formals(cli_version)), "path")
  expect_identical(names(formals(cli_probe)), "path")
  local_mocked_bindings(pcli_version = function(path) package_version("9.9.9"),
                        pcli_probe = function(path) list(cli = "claude", version = "9.9.9"))
  expect_identical(cli_version("claude"), package_version("9.9.9"))
  expect_identical(cli_probe("claude")$version, "9.9.9")
})

test_that("each route prints its one-time notice through gptr_inform()", {
  seen = new.env()
  seen$calls = list()
  local_mocked_bindings(gptr_inform = function(message, class, ..., .data = NULL, .once = NULL) {
    seen$calls[[length(seen$calls) + 1L]] = list(message = message, class = class, once = .once)
    invisible(NULL)
  })
  pcli_notice("claude")
  pcli_notice("codex")
  expect_identical(vapply(seen$calls, function(x) x$class, ""), c("notice", "notice"))
  expect_identical(vapply(seen$calls, function(x) x$once, ""),
                   c("cli_notice:claude", "cli_notice:codex"))
  expect_match(seen$calls[[1]]$message, "experimental", fixed = TRUE)
  expect_match(seen$calls[[2]]$message, "19-38K", fixed = TRUE)
  expect_match(seen$calls[[2]]$message, "own shell inside its sandbox", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 26 ]`; the five new tests error with ``could not find function "pcli_bare_state"``, ``could not find function "pcli_fake_command"`` (twice, from `local_fake_cli_path()`), ``object 'cli_version' not found`` and ``could not find function "pcli_notice"``.

- [ ] **Step 3: Write the implementation**

Append to `R/cli-common.R`:

```r
# ---- version and capability probes, notices (Task 2) ------------------------------------------

#' Minimum versions: claude >= 2.0.0 (the Agent SDK's floor, 07 verification log item 19);
#' codex is checked through the flags its `exec --help` must list instead
#' @noRd
pcli_min_version = list(claude = "2.0.0", codex = NULL)

#' The child-environment profile of a CLI (P03 removes billing and enclosing-agent variables
#' with one billing_env warning, G6 3.7)
#' @noRd
pcli_profile = function(cli) paste0("cli-", cli)

#' Cache key of a command: its words and the executable's modification time (contract 7.20)
#' @noRd
pcli_cache_key = function(cmd) {
  mtime = file.mtime(cmd[[1L]])
  stamp = if (is.na(mtime)) "NA" else format(as.numeric(mtime), digits = 15)
  paste(c(as.character(cmd), stamp), collapse = "\r")
}

#' Run a CLI command to completion through the process engine (never a shell, never by name)
#' @noRd
pcli_run = function(cmd, args, timeout = 30) {
  env = child_env(pcli_profile(pcli_identity(cmd)))
  proc_run(cmd[[1L]], c(as.character(cmd[-1L]), args), timeout = timeout, env = env)
}

#' Version of a CLI from `--version`, cached per command and modification time
#'
#' Runs only on first use or for `gptr_providers(check = TRUE)` (IC-65).
#' @param path a command from pcli_find().
#' @return a `package_version`; `gptr_error_cli_version` below the minimum.
#' @noRd
pcli_version = function(path) {
  cli = pcli_identity(path)
  key = pcli_cache_key(path)
  cache = pcli_cache$version %||% list()
  hit = cache[[key]]
  if (is.null(hit)) {
    res = pcli_run(path, "--version")
    txt = paste(res$stdout, res$stderr)
    m = regmatches(txt, regexpr("[0-9]+[.][0-9]+[.][0-9]+", txt))
    if (!length(m) || isTRUE(res$timed_out)) {
      pcli_record(cli, path = path[[1L]], error = "version unreadable")
      gptr_abort(paste0("gptr could not read the version of the ", cli, " CLI (", path[[1L]],
                        "). ", pcli_install_hint[[cli]]), "cli_version", cli = cli,
                 found = NA_character_, required = pcli_min_version[[cli]] %||% NA_character_)
    }
    hit = package_version(m)
    cache[[key]] = hit
    pcli_cache$version = cache
  }
  req = pcli_min_version[[cli]]
  if (!is.null(req) && hit < package_version(req)) {
    pcli_record(cli, path = path[[1L]], version = hit, error = "outdated")
    gptr_abort(paste0("The ", cli, " CLI is version ", as.character(hit), "; gptr needs ", req,
                      " or later. ", pcli_install_hint[[cli]]), "cli_version", cli = cli,
               found = as.character(hit), required = req)
  }
  pcli_record(cli, path = path[[1L]], version = hit)
  hit
}

#' Drop the cached version and probe of one command (gptr_providers(check = TRUE) re-runs them)
#' @noRd
pcli_version_forget = function(path) {
  key = pcli_cache_key(path)
  for (slot in c("version", "probe")) {
    cache = pcli_cache[[slot]] %||% list()
    cache[[key]] = NULL
    assign(slot, cache, envir = pcli_cache)
  }
  invisible(NULL)
}

#' Long flags named in a help text
#' @noRd
pcli_flags = function(help) {
  unique(regmatches(help, gregexpr("--[A-Za-z][A-Za-z0-9-]*", help))[[1L]])
}

#' Does `claude -p` default to --bare, and is there a documented opt-out? (15 2.9 verifier:
#' "`--bare` ... will become the default for `-p` in a future release")
#'
#' A help line that names --bare together with "default" and -p/--print (and does not speak of
#' a future release) means bare by default; `--no-bare` is the opt-out gptr passes.
#' @noRd
pcli_bare_state = function(help) {
  lines = strsplit(help, "\n", fixed = TRUE)[[1L]]
  bare = lines[grepl("--bare([^A-Za-z0-9-]|$)", lines)]
  said = grepl("default", bare, ignore.case = TRUE) &
    grepl("(^|[^A-Za-z0-9-])(-p|--print)([^A-Za-z0-9-]|$)|print mode", bare) &
    !grepl("future|will become", bare, ignore.case = TRUE)
  optout = if ("--no-bare" %in% pcli_flags(help)) "--no-bare" else NULL
  list(bare_default = any(said), bare_optout = optout)
}

#' Capability probe of a CLI (`claude --help`, `codex exec --help`), cached per command and
#' modification time (contract 7.20, IC-65)
#' @param path a command from pcli_find().
#' @return list(cli, version, bare_default, bare_optout, resume, missing); signals
#'   `gptr_error_cli_version` for a claude whose -p is bare without an opt-out, or a codex
#'   whose exec lacks --json, --ignore-user-config or --skip-git-repo-check.
#' @noRd
pcli_probe = function(path) {
  cli = pcli_identity(path)
  version = pcli_version(path)
  key = pcli_cache_key(path)
  cache = pcli_cache$probe %||% list()
  hit = cache[[key]]
  if (is.null(hit)) {
    args = if (identical(cli, "claude")) "--help" else c("exec", "--help")
    res = pcli_run(path, args)
    help = as_utf8(paste(res$stdout, res$stderr, sep = "\n"))
    hit = list(cli = cli, version = as.character(version), bare_default = FALSE,
               bare_optout = NULL, resume = FALSE, missing = character())
    if (identical(cli, "claude")) {
      bare = pcli_bare_state(help)
      hit$bare_default = bare$bare_default
      hit["bare_optout"] = list(bare$bare_optout)
    } else {
      hit$resume = grepl("(^|\n)[[:space:]]*resume([[:space:]]|$)", help)
      hit$missing = setdiff(c("--json", "--ignore-user-config", "--skip-git-repo-check"),
                            pcli_flags(help))
    }
    cache[[key]] = hit
    pcli_cache$probe = cache
  }
  if (isTRUE(hit$bare_default) && is.null(hit$bare_optout)) {
    pcli_record(cli, path = path[[1L]], error = "bare by default")
    gptr_abort(paste0("This claude CLI (", hit$version, ") runs -p in --bare mode by default, ",
                      "which never uses your Claude plan login, and offers no opt-out. ",
                      pcli_install_hint[["claude"]]), "cli_version", cli = "claude",
               found = hit$version, required = "a claude CLI whose -p can use the plan login")
  }
  if (length(hit$missing)) {
    pcli_record(cli, path = path[[1L]], error = "missing exec flags")
    gptr_abort(paste0("This codex CLI (", hit$version, ") lacks ",
                      paste(hit$missing, collapse = ", "), " in `codex exec`. ",
                      pcli_install_hint[["codex"]]), "cli_version", cli = "codex",
               found = hit$version,
               required = paste("codex exec with", paste(hit$missing, collapse = " ")))
  }
  hit
}

#' The contract name of pcli_version() (04 7.20; P20's code calls pcli_version(), see cli_find())
#' @noRd
cli_version = function(path) pcli_version(path)

#' The contract name of pcli_probe() (04 7.20; P20's code calls pcli_probe(), see cli_find())
#' @noRd
cli_probe = function(path) pcli_probe(path)

#' The one-time notice of a subscription route (03 8.3; message class `notice`)
#' @noRd
pcli_notice = function(cli) {
  text = if (identical(cli, "claude")) {
    paste0("The claude-cli route is experimental: gptr drives your own claude CLI with your ",
           "own sign-in, usage counts against your Claude plan and Anthropic's terms apply. ",
           "gptr never reads or stores Claude credentials.")
  } else {
    paste0("The codex route drives your own Codex CLI with your own sign-in; usage counts ",
           "against your ChatGPT plan. Codex runs its own shell inside its sandbox, and each ",
           "turn adds about 19-38K input tokens of Codex's own instructions.")
  }
  gptr_inform(text, "notice", .once = paste0("cli_notice:", cli))
}

#' The command of the fake CLI shipped for tests (contract 12.4, IC-60): Rscript (through
#' rscript_path(), never by name) running inst/gptr/fixtures/fake_cli.R in a given case
#' @noRd
pcli_fake_command = function(cli = c("claude", "codex"), case = "text", fixtures,
                            log = tempfile("fake-cli-", fileext = ".jsonl")) {
  cli = check_choice(cli, c("claude", "codex"), "cli")
  script = system.file("gptr", "fixtures", "fake_cli.R", package = "gptr", mustWork = TRUE)
  dir = normalizePath(fixtures, winslash = "/", mustWork = TRUE)
  c(rscript_path(), "--vanilla", script, "--fake-cli", cli, "--fake-case", case,
    "--fake-dir", dir, "--fake-log", log)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 59 ]`

- [ ] **Step 5: Commit**

```bash
git add inst/gptr/fixtures/fake_cli.R R/cli-common.R tests/testthat/test-cli-common.R tests/testthat/fixtures/cli/local-fake-cli.R
git commit -m "feat(cli): version and capability probes, notices and the fake CLI"
```

---

### Task 3: Status, plan status, model entries and fake-CLI records

**Files:**
- Modify: `R/cli-common.R` (append)
- Modify: `tests/testthat/fixtures/cli/local-fake-cli.R` (append)
- Test: `tests/testthat/test-cli-common.R` (append)

**Interfaces:**
- Consumes: `model_resolve(ref, strict = TRUE)` (P05; the `sonnet` and `gpt` aliases), `gptr_provider(...)` (P02), `check_choice()` (P01); in the test support `gptr_register(spec)` (P02).
- Produces: `pcli_status(cli, provider, api)` -> the provider record's `status = function(check = FALSE)` returning `list(status, available, path, version, default_model, plan)` (P05 calls `status(check = check)` and reads `status`, `version`, `available`; `check = FALSE` starts no process, IC-65); status values `"not found"`, `"found"`, `"ready"`, or the recorded problem (`"shim refused"`, `"outdated"`, `"version unreadable"`, `"bare by default"`, `"missing exec flags"`); `pcli_default_model(api)`, `pcli_model_id(model)` (`default` -> a full id, 04 §11.10); `pcli_plan_set(provider, info)` (the plan status of a `rate_limit_event`, 07 §2.14); `pcli_model_entry(id, name, input = "text", context = 200000, max_output = 64000)`; `pcli_models(cli)`; `pcli_fake_provider(cli = c("claude", "codex"), id = NULL, models = NULL)` -> a `gptr_provider` with `type = "cli"` and `offline = TRUE` (IC-45). Test support: `local_fake_cli(cli, case = "text", models = NULL, register = TRUE, .env = parent.frame())` -> `list(path, log, cli, provider, id, model)`.

`status(check = FALSE)` reports the cached discovery and, when nothing is cached yet, runs the file-system discovery of `pcli_find()` once (a PATH scan, the replacement of `Sys.which()`); this is how P05's `model_default()` can fall back to "a detected CLI" (03 §8.4) without process I/O. `check = TRUE` forgets the cache entry, finds the CLI again and re-runs `--version`. The model lists carry `default` plus the full ids the CLIs accept (07 §3.13, 08 §2.C); `default` resolves to the newest Sonnet (claude) or GPT (codex) of the catalog, with fixed fallbacks when the catalog has none.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/fixtures/cli/local-fake-cli.R`:

```r
# Point options(gptr.cli_path) at the fake CLI and register its offline provider record
# ("fakeclaude" or "fakecodex", IC-45) for the calling test; `model` is the first model ref
local_fake_cli = function(cli, case = "text", models = NULL, register = TRUE,
                          .env = parent.frame()) {
  fake = local_fake_cli_path(cli, case, .env = .env)
  spec = pcli_fake_provider(cli, models = models)
  if (register) {
    off = gptr_register(spec)
    withr::defer(off(), envir = .env)
  }
  c(fake, list(provider = spec, id = spec$id,
               model = paste0(spec$id, "/", spec$models[[1L]]$id)))
}
```

Append to `tests/testthat/test-cli-common.R`:

```r
# ---- status, plan status, model entries (Task 3) -------------------------------------------------

test_that("status() never starts a process without check = TRUE", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_mocked_bindings(proc_run = function(...) stop("spawned a process"),
                        proc_spawn = function(...) stop("spawned a process"))
  withr::local_options(gptr.cli_path = list(codex = c(rscript_path(), "--vanilla", "x.R")))
  st = pcli_status("codex", "codex", "cli-codex")()
  expect_identical(st$status, "found")
  expect_true(st$available)
  expect_true(is.na(st$version))
  expect_identical(st$path, normalizePath(rscript_path(), winslash = "/"))
  withr::local_options(gptr.cli_path = NULL)
  pcli_cache_clear()
  local_mocked_bindings(pcli_on_path = function(cli) character(),
                        pcli_known_paths = function(cli) character())
  st = pcli_status("claude", "claude-cli", "cli-claude")(check = FALSE)
  expect_identical(st$status, "not found")
  expect_false(st$available)
})

test_that("status(check = TRUE) finds and versions a CLI", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_fake_cli_path("codex", "text")
  st = pcli_status("codex", "codex", "cli-codex")(check = TRUE)
  expect_identical(st$status, "ready")
  expect_identical(st$version, "0.157.0")
  expect_true(st$available)
})

test_that("CLI invocations always get full model ids", {
  local_mocked_bindings(model_resolve = function(ref, strict = TRUE) {
    list(id = paste0(ref, "-9-9"))
  })
  expect_identical(pcli_model_id(list(id = "default", api = "cli-claude")), "sonnet-9-9")
  expect_identical(pcli_model_id(list(id = "default", api = "cli-codex")), "gpt-9-9")
  expect_identical(pcli_model_id(list(id = "claude-opus-5-5", api = "cli-claude")),
                   "claude-opus-5-5")
  local_mocked_bindings(model_resolve = function(ref, strict = TRUE) stop("no catalog"))
  expect_identical(pcli_default_model("cli-claude"), "claude-sonnet-5-5")
  expect_identical(pcli_default_model("cli-codex"), "gpt-6-sol")
})

test_that("a rate_limit_event becomes the provider's plan status", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  info = list(status = "allowed", resetsAt = 1790749800, rateLimitType = "five_hour",
              unifiedWindows = list(five_hour = list(utilization = 0.15),
                                    seven_day = list(utilization = 0.34)))
  pcli_plan_set("claude-cli", info)
  local_mocked_bindings(pcli_on_path = function(cli) character(),
                        pcli_known_paths = function(cli) character())
  plan = pcli_status("claude", "claude-cli", "cli-claude")()$plan
  expect_identical(plan$status, "allowed")
  expect_identical(plan$type, "five_hour")
  expect_equal(plan$five_hour, 0.15)
  expect_equal(plan$seven_day, 0.34)
})

test_that("the plan routes list `default` and full ids; fake CLI records are offline", {
  ids = vapply(pcli_models("claude"), function(m) m$id, "")
  expect_identical(ids, c("default", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"))
  expect_identical(pcli_models("codex")[[1]]$id, "default")
  p = pcli_fake_provider("codex")
  expect_s3_class(p, "gptr_provider")
  expect_identical(p$id, "fakecodex")
  expect_identical(p$api, "cli-codex")
  expect_identical(p$type, "cli")
  expect_true(p$offline)
  expect_identical(vapply(p$models, function(m) m$id, ""), c("gpt-6-sol", "default"))
  expect_true("check" %in% names(formals(p$status)))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 59 ]`; the five new tests error with ``could not find function "pcli_status"``, ``could not find function "pcli_model_id"``, ``could not find function "pcli_plan_set"`` and ``could not find function "pcli_models"``.

- [ ] **Step 3: Write the implementation**

Append to `R/cli-common.R`:

```r
# ---- status, plan status, model entries, provider records (Task 3) ----------------------------

#' Full model id behind `<cli provider>/default` (CLI invocations always get full ids, 03 8.4):
#' the newest Sonnet for claude and the newest GPT for codex from the catalog
#' @noRd
pcli_default_model = function(api) {
  codex = identical(api, "cli-codex")
  m = tryCatch(model_resolve(if (codex) "gpt" else "sonnet", strict = FALSE),
               error = function(e) NULL)
  id = m[["id"]]
  if (is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)) return(id)
  if (codex) "gpt-6-sol" else "claude-sonnet-5-5"
}

#' The model id passed to a CLI: `default` resolves to a full id (contract 11.10)
#' @noRd
pcli_model_id = function(model) {
  id = model[["id"]] %||% "default"
  if (identical(id, "default")) pcli_default_model(model[["api"]]) else id
}

#' Store the plan status of a claude `rate_limit_event` (07 2.14: nested in rate_limit_info)
#' @noRd
pcli_plan_set = function(provider, info) {
  w = info[["unifiedWindows"]] %||% list()
  rec = list(status = info[["status"]] %||% NA_character_,
             type = info[["rateLimitType"]] %||% NA_character_,
             resets_at = info[["resetsAt"]] %||% NA_real_,
             five_hour = w[["five_hour"]][["utilization"]] %||% NA_real_,
             seven_day = w[["seven_day"]][["utilization"]] %||% NA_real_,
             time = Sys.time())
  plan = pcli_cache$plan %||% list()
  plan[[provider]] = rec
  pcli_cache$plan = plan
  invisible(rec)
}

#' The `status()` function of a CLI provider record (contract 7.20; P05 reads `status`,
#' `version` and `available`)
#'
#' `check = FALSE` never starts a process (IC-65): it reports the cached discovery, and runs the
#' file-system discovery of pcli_find() once when nothing is cached (the PATH scan replaces
#' `Sys.which()`, which runs `which` on Unix). `check = TRUE` finds the CLI again and runs its
#' `--version` probe.
#' @noRd
pcli_status = function(cli, provider, api) {
  force(cli)
  force(provider)
  force(api)
  function(check = FALSE) {
    if (isTRUE(check)) {
      pcli_forget(cli)
      path = tryCatch(pcli_find(cli), gptr_error = function(e) NULL)
      if (!is.null(path)) {
        pcli_version_forget(path)
        tryCatch(pcli_version(path), gptr_error = function(e) NULL)
      }
    } else if (is.null((pcli_cache$status %||% list())[[cli]])) {
      tryCatch(pcli_find(cli), gptr_error = function(e) NULL)
    }
    cur = (pcli_cache$status %||% list())[[cli]]
    path = cur$path %||% NA_character_
    status = if (is.null(cur)) {
      "not found"
    } else if (!is.null(cur$error)) {
      cur$error
    } else if (is.na(path)) {
      "not found"
    } else if (is.null(cur$version)) {
      "found"
    } else {
      "ready"
    }
    list(status = status, available = status %in% c("found", "ready"), path = path,
         version = cur$version %||% NA_character_, default_model = pcli_default_model(api),
         plan = (pcli_cache$plan %||% list())[[provider]])
  }
}

#' A model entry of a CLI provider record (catalog shape, contract 4.9; no prices: plan usage)
#' @noRd
pcli_model_entry = function(id, name, input = "text", context = 200000, max_output = 64000) {
  list(id = id, name = name, reasoning = TRUE, input = input, tool_call = TRUE,
       context = context, max_output = max_output, status = "active")
}

#' The model entries of the built-in plan routes: `default` plus the full ids the CLIs accept
#' (07 3.13, 08 2.C; 03 8.4)
#' @noRd
pcli_models = function(cli) {
  if (identical(cli, "claude")) {
    img = c("text", "image")
    return(list(pcli_model_entry("default", "Claude plan default model (claude CLI)", img),
                pcli_model_entry("claude-opus-5-5", "Claude Opus 5.5 (claude CLI)", img),
                pcli_model_entry("claude-sonnet-5-5", "Claude Sonnet 5.5 (claude CLI)", img),
                pcli_model_entry("claude-haiku-4-5", "Claude Haiku 4.5 (claude CLI)", img)))
  }
  list(pcli_model_entry("default", "ChatGPT plan default model (Codex CLI)", context = 272000),
       pcli_model_entry("gpt-6-sol", "GPT-6 Sol (Codex CLI)", context = 272000),
       pcli_model_entry("gpt-6-luna", "GPT-6 Luna (Codex CLI)", context = 272000))
}

#' The provider record of a fake CLI (contract 12.4, IC-45): `offline = TRUE`, so
#' `GPTR_REPLAY=replay` (tests/testthat/setup.R) does not block it; like the real CLIs, it takes
#' its command from options(gptr.cli_path)
#' @noRd
pcli_fake_provider = function(cli = c("claude", "codex"), id = NULL, models = NULL) {
  cli = check_choice(cli, c("claude", "codex"), "cli")
  id = id %||% paste0("fake", cli)
  api = paste0("cli-", cli)
  models = models %||% (if (identical(cli, "claude")) "claude-sonnet-5-5" else "gpt-6-sol")
  entries = lapply(c(models, "default"), function(m) pcli_model_entry(m, paste(m, "(fake CLI)")))
  gptr_provider(id, api = api, type = "cli", models = entries,
                status = pcli_status(cli, id, api), offline = TRUE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 86 ]`

- [ ] **Step 5: Commit**

```bash
git add R/cli-common.R tests/testthat/test-cli-common.R tests/testthat/fixtures/cli/local-fake-cli.R
git commit -m "feat(cli): cached status, plan status and the plan-route model entries"
```

---

### Task 4: Turn helpers, the child table and stopping a child

**Files:**
- Modify: `R/cli-common.R` (append)
- Modify: `tests/testthat/fixtures/cli/local-fake-cli.R` (append)
- Test: `tests/testthat/test-cli-common.R` (append)

**Interfaces:**
- Consumes: `msg_assistant(...)`, `block_text(text, signature = NULL)`, `block_thinking(thinking, signature = NULL, redacted = FALSE, data = NULL, origin = NULL)`, `ev_new(type, ...)`, `id_new(prefix = "", n = 10L)`, `json_encode(x, pretty = FALSE)`, `json_decode(text)` (P01); `usage_new(...)` (P05); `write_all(p, data)`, `write_close(p)`, `kill_all(p, grace = 2)`, `reactor_pump(until = function() FALSE, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`, `reactor_now()`, `reactor_timer(at, fn, run = NULL)`, `reactor_cancel(ids)`, `reactor_served(run, served = TRUE)`, `wire_log_path(session)`, `wire_log_append(path, line)` (P04); `redact(x, profile = "persist")` (P03); `rlang::new_weakref()`, `rlang::wref_key()`; in tests `msg_user()`, `block_context()`, `msg_text()`, `local_project()`, `local_gptr_options()` (P01).
- Produces (used by Tasks 5-10): `pcli_split(messages)` -> `list(prior, input)`; `pcli_unseen(prior, provider)` (the earlier messages after the last assistant message `provider` answered); `pcli_block_text(b)`, `pcli_message_text(m)`, `pcli_input_text(messages)`, `pcli_history_text(prior)`, `pcli_system_text(context)`; `pcli_scalar_num(x)`; `pcli_params(context)` -> `list(mode, turns, cost)` from `context$params$cli_mode`/`cli_budget` (default mode `"manual"`); `pcli_state(opts)`; `pcli_child(state)`; `pcli_alive(p)`; the weak child table `pcli_track(session, state)`, `pcli_tracked(session)`, `pcli_untrack(session)`; `pcli_request_id(state)` (`req_<n>_<8 hex>`, RNG-free); `pcli_control_request(state, request)`; `pcli_send(opts, obj)`; `pcli_stop_child(state, wait_ack = TRUE, grace = 2)`; `pcli_parse_line(x)`; the turn state `pcli_turn_new(model, opts)`, `pcli_aborted(s)`, `pcli_start(s, response_id = NULL)`, `pcli_text_block(s, text, kind = "text")`, `pcli_blocks(s)`, `pcli_message(s, stop_reason = "stop", usage = NULL, error_message = NULL, raw_stop_reason = NULL)`, `pcli_finish(s, msg, event)`, `pcli_done(s, usage, stop_reason = "stop", raw_stop_reason = NULL)`, `pcli_fail(s, class, message, reason = "error", status = NA_integer_, usage = NULL, retry_after = NULL)`, `pcli_turn_seconds()`, `pcli_turn_timer(s, on_timeout)`, `pcli_wire_log(s, event)`. Adapter state fields set here: `turn_open`, `turn_timer`, `interrupt_id`, `interrupt_acked`, `served_run`, `n_req`. Test support: `stub_opts(gate = NULL, dispatch = NULL, ...)`, `stub_model(cli = "claude", id = NULL)`, `event_types(opts)`, `stub_process(pid = 4242L)`.

One CLI turn is one INFRA-02 stream (04 §4.5): one `start`, block events, exactly one terminal `done` or `error` carrying the partial message (04 §8.1: "Normalisers never signal R conditions after `start`"). Messages carry `route = "plan-cli"` and the request id. The child table maps a session id to its adapter state through `rlang::new_weakref()`: the session's live record owns the state (`opts$state` is the live record's `adapter` environment), so the table never keeps a session alive and a collected session's processx object cleans its child up; the table is a process table like P04's job table (03 §2.2 rule 5). `pcli_stop_child()` sends the claude interrupt control request only while a turn is open (07 §3.10: `interrupt` ends the turn cleanly), pumps the reactor with `allow_runs = character()` (no FIFO tool runs, IC-57) until the CLI acknowledges or `grace` seconds pass, forgets the child (`state$process = NULL`, so P05 routes none of its late lines or its exit, as P05's own `stream_abort()` does), closes its stdin with P04's `write_close()` (a claude CLI in stream-json mode exits at end of input, and so does the fake, which an R child blocked on stdin would otherwise ignore SIGINT for the whole grace period) and then calls `kill_all(p, grace = 1)`. `pcli_unseen()` serves cross-model continuity (REQ-34, 03 §8.3 "another model may have answered"): a reused claude child, a resumed claude session and a resumed Codex thread have seen the conversation only up to the last assistant message their own provider answered, so the messages after it (a turn answered by another model in between) travel as a `<conversation_history>` block. The wire log writes the fields of P04's `wire_log()` (`ts` in epoch seconds, `request_id`, `provider`, `model`, `url` as `cli:<name>`, `seconds`, `event`), redacted, never prompts or output.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/fixtures/cli/local-fake-cli.R`:

```r
# Adapter options (contract 8.1) whose effects are recorded in opts$log: emitted events, lines
# sent to the child, MCP messages dispatched, gate calls
stub_opts = function(gate = NULL, dispatch = NULL, ...) {
  log = new.env(parent = emptyenv())
  log$events = list()
  log$sent = list()
  log$dispatched = list()
  log$gated = list()
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  signal$reason = NULL
  opts = list(
    emit = function(ev) {
      log$events[[length(log$events) + 1L]] = ev
      invisible(NULL)
    },
    send = function(obj) {
      log$sent[[length(log$sent) + 1L]] = obj
      invisible(NULL)
    },
    retry = function(info) invisible(NULL),
    signal = signal,
    state = new.env(parent = emptyenv()),
    memo = new.env(parent = emptyenv()),
    gate = gate %||% function(call) {
      log$gated[[length(log$gated) + 1L]] = call
      list(decision = "deny", reason = "denied in tests")
    },
    mcp_dispatch = dispatch %||% function(message) {
      log$dispatched[[length(log$dispatched) + 1L]] = message
      if (is.null(message[["id"]])) return(NULL)
      list(jsonrpc = "2.0", id = message[["id"]],
           result = list(content = list(list(type = "text", text = "[1] 24")),
                         isError = FALSE))
    },
    tool_result = function(result, call) NULL,
    run = NULL,
    session = "s0123456789"
  )
  extra = list(...)
  for (k in names(extra)) opts[k] = list(extra[[k]])
  opts$log = log
  opts
}

# A model record of a fake CLI provider (contract 4.9 fields the adapters read)
stub_model = function(cli = "claude", id = NULL) {
  id = id %||% (if (identical(cli, "claude")) "claude-sonnet-5-5" else "gpt-6-sol")
  provider = paste0("fake", cli)
  list(ref = paste0(provider, "/", id), provider = provider, id = id,
       api = paste0("cli-", cli), type = "cli")
}

# Types of the events an adapter emitted
event_types = function(opts) vapply(opts$log$events, function(e) e[["type"]], "")

# A processx-like stand-in for a CLI child (class "process"; alive until killed)
stub_process = function(pid = 4242L) {
  p = new.env(parent = emptyenv())
  p$alive = TRUE
  p$is_alive = function() p$alive
  p$get_pid = function() pid
  class(p) = c("stub_process", "process")
  p
}
```

Append to `tests/testthat/test-cli-common.R`:

```r
# ---- shared turn helpers (Task 4) ---------------------------------------------------------------

test_that("the new input and a synthetic history come from the projected messages", {
  msgs = list(msg_user("first question"),
              msg_assistant(list(block_text("first answer")), api = "fake", provider = "fake",
                            model = "fake-1"),
              msg_user(list(block_context("workspace", "x = 1"), block_text("second question"))))
  parts = pcli_split(msgs)
  expect_length(parts$prior, 2L)
  expect_length(parts$input, 1L)
  expect_match(pcli_history_text(parts$prior), "User: first question\n\nAssistant: first answer",
               fixed = TRUE)
  expect_match(pcli_history_text(parts$prior), "^<conversation_history>\n")
  expect_identical(pcli_input_text(parts$input),
                   "<workspace>\nx = 1\n</workspace>\n\nsecond question")
  expect_identical(pcli_history_text(list()), "")
  expect_identical(pcli_input_text(list()), "(no new input)")
  ctx = list(system = list(t0 = "You are gptr.", t1 = "Project notes."))
  expect_identical(pcli_system_text(ctx), "You are gptr.\n\nProject notes.")
})

test_that("a CLI sees only the turns after the last one its own provider answered", {
  mine = function(text) {
    msg_assistant(list(block_text(text)), api = "cli-claude", provider = "fakeclaude",
                  model = "claude-sonnet-5-5")
  }
  other = function(text) {
    msg_assistant(list(block_text(text)), api = "anthropic-messages", provider = "anthropic",
                  model = "claude-sonnet-5-5")
  }
  prior = list(msg_user("one"), mine("a1"), msg_user("two"), other("a2"))
  unseen = pcli_unseen(prior, "fakeclaude")
  expect_length(unseen, 2L)
  expect_identical(msg_text(unseen[[2]]), "a2")
  expect_length(pcli_unseen(prior[1:2], "fakeclaude"), 0L)
  expect_length(pcli_unseen(prior, "codex"), 4L)
  expect_length(pcli_unseen(list(), "fakeclaude"), 0L)
})

test_that("pcli_params() reads the mode and budget patched in by request_params", {
  p = pcli_params(list(params = list(cli_mode = "auto", cli_budget = list(turns = 3, cost = 1.5))))
  expect_identical(p, list(mode = "auto", turns = 3, cost = 1.5))
  p = pcli_params(list(params = list(max_tokens = 1000L)))
  expect_identical(p$mode, "manual")
  expect_null(p$turns)
  expect_null(p$cost)
  expect_identical(pcli_params(list(params = list(cli_mode = "yolo")))$mode, "manual")
})

test_that("one CLI turn emits one start and one terminal event and closes the turn", {
  opts = stub_opts()
  opts$state$pcli_request_id = "q000000000001"
  s = pcli_turn_new(stub_model("codex"), opts)
  expect_true(opts$state$turn_open)
  pcli_text_block(s, "thinking it over", kind = "thinking")
  pcli_text_block(s, "All done.")
  msg = pcli_done(s, usage_new(input = 10, output = 5), "stop", "completed")
  expect_identical(event_types(opts),
                   c("start", "thinking_start", "thinking_delta", "thinking_end", "text_start",
                     "text_delta", "text_end", "done"))
  expect_identical(msg$route, "plan-cli")
  expect_identical(msg$request_id, "q000000000001")
  expect_identical(msg_text(msg), "All done.")
  expect_identical(msg$content[[1]]$type, "thinking")
  expect_equal(msg$usage$input, 10)
  expect_false(opts$state$turn_open)
  expect_identical(pcli_fail(s, "provider", "too late"), msg)
  expect_length(opts$log$events, 8L)
})

test_that("a failed turn emits one error event with the class and the partial message", {
  opts = stub_opts()
  s = pcli_turn_new(stub_model("claude"), opts)
  pcli_text_block(s, "partial")
  msg = pcli_fail(s, "billing", "billed to an API key", status = 402L)
  expect_identical(event_types(opts), c("start", "text_start", "text_delta", "text_end", "error"))
  err = opts$log$events[[5]]$error
  expect_identical(err$class, "billing")
  expect_identical(err$status, 402L)
  expect_identical(msg$stop_reason, "error")
  expect_identical(msg$error_message, "billed to an API key")
  expect_identical(msg_text(msg), "partial")
  expect_identical(pcli_done(s, usage_new()), msg)
})

test_that("the child table holds adapter states weakly", {
  st = new.env()
  pcli_track("s00000000aa", st)
  expect_identical(pcli_tracked("s00000000aa"), st)
  rm(st)
  gc()
  expect_null(pcli_tracked("s00000000aa"))
  st2 = new.env()
  pcli_track("s00000000bb", st2)
  pcli_untrack("s00000000bb")
  expect_null(pcli_tracked("s00000000bb"))
})

test_that("stopping a claude child mid-turn sends the interrupt, then kill_all()", {
  seen = new.env()
  seen$written = character()
  seen$killed = 0L
  seen$closed = 0L
  p = stub_process()
  state = new.env()
  state$process = p
  state$cli_api = "cli-claude"
  state$turn_open = TRUE
  local_mocked_bindings(
    write_all = function(p, data) {
      seen$written = c(seen$written, data)
      invisible(p)
    },
    write_close = function(p) {
      seen$closed = seen$closed + 1L
      invisible(p)
    },
    reactor_pump = function(until = function() FALSE, slice_ms = 100L, allow_runs = NULL,
                            timeout = Inf) {
      seen$allow = allow_runs
      state$interrupt_acked = TRUE
      invisible(until())
    },
    kill_all = function(p, grace = 2) {
      seen$killed = seen$killed + 1L
      p$alive = FALSE
      invisible(TRUE)
    }
  )
  expect_true(pcli_stop_child(state))
  line = json_decode(seen$written[[1]])
  expect_identical(line$type, "control_request")
  expect_identical(line$request$subtype, "interrupt")
  expect_identical(line$request_id, state$interrupt_id)
  expect_identical(seen$allow, character())
  expect_identical(seen$killed, 1L)
  expect_identical(seen$closed, 1L)
  expect_null(state$process)
  expect_false(state$turn_open)
  codex = new.env()
  codex$process = stub_process(4343L)
  codex$cli_api = "cli-codex"
  codex$turn_open = TRUE
  expect_true(pcli_stop_child(codex))
  expect_length(seen$written, 1L)
  expect_identical(seen$killed, 2L)
  expect_false(pcli_stop_child(codex))
})

test_that("the wire log gets one redacted line per CLI turn start and terminal event", {
  local_project()
  local_gptr_options(wire_log = TRUE)
  n0 = nrow(showConnections())
  opts = stub_opts()
  s = pcli_turn_new(stub_model("claude"), opts)
  pcli_wire_log(s, "start")
  pcli_done(s, usage_new())
  rows = lapply(readLines(wire_log_path(opts$session), encoding = "UTF-8"), json_decode)
  expect_identical(vapply(rows, function(r) r$event, ""), c("start", "done"))
  expect_identical(rows[[1]]$url, "cli:claude")
  expect_identical(rows[[2]]$provider, "fakeclaude")
  expect_identical(nrow(showConnections()), n0)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 86 ]`; the eight new tests error with ``could not find function "pcli_split"``, ``could not find function "pcli_unseen"``, ``could not find function "pcli_params"``, ``could not find function "pcli_turn_new"``, ``could not find function "pcli_track"`` and ``could not find function "pcli_stop_child"``.

- [ ] **Step 3: Write the implementation**

Append to `R/cli-common.R`:

```r
# ---- turn helpers shared by the two adapters (Task 4) -----------------------------------------

#' Split projected messages into the earlier conversation and the new input (the messages
#' after the last assistant message)
#' @noRd
pcli_split = function(messages) {
  roles = vapply(messages, function(m) m[["role"]] %||% "", "")
  last = max(c(0L, which(roles == "assistant")))
  keep = seq_along(messages) > last
  list(prior = messages[!keep], input = messages[keep])
}

#' The earlier messages a CLI conversation has not seen: those after the last assistant message
#' that `provider` answered (a reused child, a resumed claude session or a resumed Codex thread
#' holds the rest); all of `prior` when it answered none (03 8.3: another model may have
#' answered them; REQ-34)
#' @noRd
pcli_unseen = function(prior, provider) {
  mine = vapply(prior, function(m) {
    identical(m[["role"]], "assistant") && identical(m[["provider"]], provider)
  }, NA)
  k = max(c(0L, which(mine)))
  prior[seq_along(prior) > k]
}

#' Plain text of one content block (context blocks carry their rendered text, 04 4.1)
#' @noRd
pcli_block_text = function(b) {
  switch(b[["type"]] %||% "",
         text = b[["text"]] %||% "",
         context = b[["text"]] %||% "",
         image = "[image omitted]",
         tool_call = paste0("[called tool ", b[["name"]] %||% "?", "]"),
         "")
}

#' Plain text of one message, its blocks joined by blank lines
#' @noRd
pcli_message_text = function(m) {
  parts = vapply(m[["content"]] %||% list(), pcli_block_text, "")
  paste(parts[nzchar(parts)], collapse = "\n\n")
}

#' Plain text of the new input; never empty
#' @noRd
pcli_input_text = function(messages) {
  parts = vapply(messages, pcli_message_text, "")
  text = paste(parts[nzchar(parts)], collapse = "\n\n")
  if (nzchar(text)) text else "(no new input)"
}

#' A synthetic history for a CLI that has not seen the earlier turns (03 8.3: another model
#' answered them, or the CLI cannot resume); tool results longer than 2,000 characters are cut
#' @noRd
pcli_history_text = function(prior) {
  if (!length(prior)) return("")
  lines = vapply(prior, function(m) {
    role = m[["role"]] %||% ""
    txt = trimws(pcli_message_text(m))
    if (identical(role, "tool_result") && nchar(txt) > 2000L) {
      txt = paste0(substr(txt, 1L, 2000L), " [...]")
    }
    label = switch(role, user = "User", assistant = "Assistant", operator = "Harness note",
                   tool_result = paste0("Tool result (", m[["tool_name"]] %||% "tool", ")"),
                   "Note")
    paste0(label, ": ", txt)
  }, "")
  paste0("<conversation_history>\nThe conversation so far (earlier turns ran on another ",
         "model or in an earlier CLI process):\n\n", paste(lines, collapse = "\n\n"),
         "\n</conversation_history>\n\n")
}

#' The frozen system text of a request context: T0, a blank line, T1 (04 8.1)
#' @noRd
pcli_system_text = function(context) {
  parts = c(context[["system"]][["t0"]], context[["system"]][["t1"]])
  parts = parts[nzchar(parts)]
  paste(parts, collapse = "\n\n")
}

#' A positive number or NULL
#' @noRd
pcli_scalar_num = function(x) {
  if (is.numeric(x) && length(x) == 1L && !is.na(x) && x > 0) as.numeric(x) else NULL
}

#' The run's mode and remaining budget, patched into `context$params` by builtin:cli's
#' `request_params` hook (fields `cli_mode`, `cli_budget`); without them (a direct adapter
#' call) the strictest mapping applies: mode `manual` and no budget flags
#' @return list(mode = chr(1), turns = num(1) | NULL, cost = num(1) | NULL)
#' @noRd
pcli_params = function(context) {
  p = context[["params"]] %||% list()
  mode = p[["cli_mode"]]
  ok = is.character(mode) && length(mode) == 1L && !is.na(mode) &&
    mode %in% c("plan", "manual", "edits", "auto")
  b = p[["cli_budget"]] %||% list()
  list(mode = if (ok) mode else "manual", turns = pcli_scalar_num(b[["turns"]]),
       cost = pcli_scalar_num(b[["cost"]]))
}

#' The adapter state environment of a request (04 8.1 `opts$state`; a fresh one when absent)
#' @noRd
pcli_state = function(opts) {
  st = opts[["state"]]
  if (is.environment(st)) st else new.env(parent = emptyenv())
}

#' The CLI child recorded by P05's process_jsonl transport in the adapter state, or NULL
#' @noRd
pcli_child = function(state) {
  p = if (is.environment(state)) state$process else NULL
  if (inherits(p, "process")) p else NULL
}

#' Is a processx child alive?
#' @noRd
pcli_alive = function(p) {
  !is.null(p) && isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))
}

#' Remember the adapter state of a session that runs a CLI child, weakly: the session's live
#' record owns the state, so the table never keeps a session alive
#' @noRd
pcli_track = function(session, state) {
  ok = is.character(session) && length(session) == 1L && !is.na(session) && nzchar(session)
  if (!ok || !is.environment(state)) return(invisible(NULL))
  tab = pcli_cache$children
  if (is.null(tab)) {
    tab = new.env(parent = emptyenv())
    pcli_cache$children = tab
  }
  assign(session, rlang::new_weakref(state), envir = tab)
  invisible(NULL)
}

#' The adapter state of a session's CLI child, or NULL
#' @noRd
pcli_tracked = function(session) {
  tab = pcli_cache$children
  ok = is.character(session) && length(session) == 1L && !is.na(session) && nzchar(session)
  if (is.null(tab) || !ok) return(NULL)
  w = get0(session, envir = tab, inherits = FALSE)
  if (is.null(w)) return(NULL)
  st = rlang::wref_key(w)
  if (is.null(st)) rm(list = session, envir = tab)
  st
}

#' Forget a session in the child table
#' @noRd
pcli_untrack = function(session) {
  tab = pcli_cache$children
  if (!is.null(tab) && is.character(session) && length(session) == 1L &&
      exists(session, envir = tab, inherits = FALSE)) {
    rm(list = session, envir = tab)
  }
  invisible(NULL)
}

#' A fresh control-request id `req_<n>_<8 hex>` (07 3.10 shape; RNG-free, IC-61)
#' @noRd
pcli_request_id = function(state) {
  n = (state$n_req %||% 0L) + 1L
  state$n_req = n
  paste0("req_", n, "_", id_new("", 8L))
}

#' A control request line of the claude stream-json protocol (07 3.10)
#' @noRd
pcli_control_request = function(state, request) {
  list(type = "control_request", request_id = pcli_request_id(state), request = request)
}

#' Write one JSON line to the child through the transport's `opts$send()` (04 8.1)
#' @noRd
pcli_send = function(opts, obj) {
  send = opts[["send"]]
  if (is.function(send)) tryCatch(send(obj), error = function(e) NULL)
  invisible(NULL)
}

#' Stop the CLI child of a session (03 8.3; 07 3.9-3.10; 15 2.9)
#'
#' A claude child in the middle of a turn first gets the control-protocol interrupt; with
#' `wait_ack` the reactor is pumped (no FIFO tool runs) until the CLI acknowledges it or `grace`
#' seconds pass. Then the child is forgotten (its late lines and exit reach no turn), its stdin
#' is closed (a stream-json claude CLI exits at end of input) and kill_all() stops the process
#' tree. Called by builtin:cli's `agent_end` hook for a run that ended during a turn (Ctrl-C,
#' gptr_cancel()) or that leaves a budgeted claude child behind, by its `session_shutdown` hook,
#' and without the wait by the adapters themselves (billing stop, turn cap, wall-clock limit,
#' a claude child replaced at a new run).
#' @noRd
pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
  if (!is.environment(state)) return(invisible(FALSE))
  if (!is.null(state$turn_timer)) {
    tryCatch(reactor_cancel(state$turn_timer), error = function(e) NULL)
    state$turn_timer = NULL
  }
  p = pcli_child(state)
  if (!pcli_alive(p)) {
    state$turn_open = FALSE
    return(invisible(FALSE))
  }
  if (identical(state$cli_api, "cli-claude") && isTRUE(state$turn_open)) {
    req = pcli_control_request(state, list(subtype = "interrupt"))
    state$interrupt_id = req$request_id
    state$interrupt_acked = FALSE
    sent = tryCatch({
      write_all(p, paste0(json_encode(req), "\n"))
      TRUE
    }, error = function(e) FALSE)
    if (sent && isTRUE(wait_ack)) {
      tryCatch(reactor_pump(until = function() isTRUE(state$interrupt_acked) || !pcli_alive(p),
                            slice_ms = 20L, allow_runs = character(), timeout = grace),
               error = function(e) NULL, interrupt = function(e) NULL)
    }
  }
  state$turn_open = FALSE
  if (identical(state$process, p)) state$process = NULL
  tryCatch(write_close(p), error = function(e) NULL)
  tryCatch(kill_all(p, grace = 1), error = function(e) NULL)
  invisible(TRUE)
}

#' Parse one output line when the transport did not (P05 passes `obj`)
#' @noRd
pcli_parse_line = function(x) {
  if (!is.character(x) || length(x) != 1L || !nzchar(x)) return(NULL)
  tryCatch(json_decode(x), error = function(e) NULL)
}

#' The state of one CLI turn (one INFRA-02 stream: one `start`, one terminal event)
#' @noRd
pcli_turn_new = function(model, opts) {
  s = new.env(parent = emptyenv())
  s$model = model
  s$opts = opts
  s$state = pcli_state(opts)
  s$started = FALSE
  s$done = FALSE
  s$blocks = list()
  s$open = list()
  s$n = 0L
  s$msg = NULL
  s$response_id = NULL
  s$response_model = NULL
  s$t0 = reactor_now()
  s$timer = NULL
  s$state$turn_open = TRUE
  s
}

#' Has the run been aborted (04 8.1 `opts$signal`)?
#' @noRd
pcli_aborted = function(s) isTRUE(s$opts[["signal"]]$aborted)

#' Emit the turn's `start` event once (04 4.5)
#' @noRd
pcli_start = function(s, response_id = NULL) {
  if (!is.null(response_id)) s$response_id = response_id
  if (s$started) return(invisible(NULL))
  s$started = TRUE
  m = s$model
  emit = s$opts[["emit"]]
  if (is.function(emit)) {
    emit(ev_new("start", api = m$api, provider = m$provider, model = m$id,
                request_id = s$state$pcli_request_id, response_id = s$response_id))
  }
  invisible(NULL)
}

#' Emit a whole text or thinking block (start, one delta, end) and keep it
#' @noRd
pcli_text_block = function(s, text, kind = "text") {
  if (!is.character(text) || length(text) != 1L || !nzchar(text)) return(invisible(NULL))
  pcli_start(s)
  m = s$model
  blk = if (identical(kind, "thinking")) {
    block_thinking(text, origin = list(api = m$api, provider = m$provider, model = m$id))
  } else {
    block_text(text)
  }
  s$n = s$n + 1L
  i = s$n
  emit = s$opts[["emit"]]
  if (is.function(emit)) {
    emit(ev_new(paste0(kind, "_start"), index = i))
    emit(ev_new(paste0(kind, "_delta"), index = i, delta = text))
    emit(ev_new(paste0(kind, "_end"), index = i, block = blk))
  }
  s$blocks[[i]] = blk
  invisible(blk)
}

#' The content blocks of the turn in index order (text and thinking only: tools ran inside the
#' CLI): finished blocks, and the text so far of blocks still streaming (a partial message)
#' @noRd
pcli_blocks = function(s) {
  out = list()
  for (i in seq_len(s$n)) {
    b = if (i <= length(s$blocks)) s$blocks[[i]] else NULL
    o = if (i <= length(s$open)) s$open[[i]] else NULL
    if (is.null(b) && is.environment(o) && o$n > 0L) {
      txt = paste(unlist(o$parts[seq_len(o$n)], use.names = FALSE), collapse = "")
      b = if (identical(o$kind, "thinking")) block_thinking(txt) else block_text(txt)
    }
    if (!is.null(b)) out[[length(out) + 1L]] = b
  }
  out
}

#' The turn's assistant message (route plan-cli; 04 4.2)
#' @noRd
pcli_message = function(s, stop_reason = "stop", usage = NULL, error_message = NULL,
                       raw_stop_reason = NULL) {
  m = s$model
  msg_assistant(pcli_blocks(s), api = m$api, provider = m$provider, model = m$id,
                usage = usage %||% usage_new(), stop_reason = stop_reason,
                response_id = s$response_id, response_model = s$response_model,
                error_message = error_message, raw_stop_reason = raw_stop_reason,
                route = "plan-cli", request_id = s$state$pcli_request_id)
}

#' End the turn: remember the message, cancel the wall-clock timer, release the served mark of a
#' codex exec, log the terminal event
#' @noRd
pcli_finish = function(s, msg, event) {
  s$done = TRUE
  s$msg = msg
  s$state$turn_open = FALSE
  if (!is.null(s$timer)) {
    tryCatch(reactor_cancel(s$timer), error = function(e) NULL)
    s$timer = NULL
    s$state$turn_timer = NULL
  }
  served = s$state$served_run
  if (is.character(served) && length(served) == 1L) {
    tryCatch(reactor_served(served, FALSE), error = function(e) NULL)
    s$state$served_run = NULL
  }
  pcli_wire_log(s, event)
  invisible(msg)
}

#' Emit the terminal `done` event and return the final message
#' @noRd
pcli_done = function(s, usage, stop_reason = "stop", raw_stop_reason = NULL) {
  if (s$done) return(s$msg)
  pcli_start(s)
  msg = pcli_message(s, stop_reason, usage, raw_stop_reason = raw_stop_reason)
  emit = s$opts[["emit"]]
  if (is.function(emit)) emit(ev_new("done", reason = stop_reason, message = msg, usage = usage))
  pcli_finish(s, msg, "done")
}

#' Emit the one terminal `error` event (INFRA-02) with the partial message and return it
#'
#' `class` is a condition suffix of 04 2.2 (P06 turns it into the run's condition); the
#' event's `error` is list(class, status, request_id, retry_after) (04 4.5).
#' @noRd
pcli_fail = function(s, class, message, reason = "error", status = NA_integer_, usage = NULL,
                    retry_after = NULL) {
  if (s$done) return(s$msg)
  pcli_start(s)
  msg = pcli_message(s, reason, usage, error_message = message)
  status = suppressWarnings(as.integer(status %||% NA_integer_))
  err = list(class = class, status = if (length(status) != 1L || is.na(status)) NULL else status,
             request_id = s$state$pcli_request_id, retry_after = retry_after)
  emit = s$opts[["emit"]]
  if (is.function(emit)) emit(ev_new("error", reason = reason, message = msg, error = err))
  pcli_finish(s, msg, "error")
}

#' The wall-clock limit of one CLI turn in seconds (option gptr.cli_turn_timeout, IC-65)
#' @noRd
pcli_turn_seconds = function() as.numeric(gptr_opt("cli_turn_timeout") %||% 3600)

#' Start the per-turn wall-clock timer
#' @noRd
pcli_turn_timer = function(s, on_timeout) {
  s$timer = reactor_timer(reactor_now() + pcli_turn_seconds(), on_timeout, run = s$opts[["run"]])
  s$state$turn_timer = s$timer
  invisible(s$timer)
}

#' One redacted wire-log line per CLI turn start and terminal event (P04's per-session file,
#' IC-65; `url` names the CLI because there is no HTTP request; never prompts or output)
#' @noRd
pcli_wire_log = function(s, event) {
  path = tryCatch(wire_log_path(s$opts[["session"]]), error = function(e) NULL)
  if (is.null(path)) return(invisible(NULL))
  m = s$model
  rec = list(ts = round(as.numeric(Sys.time()), 3), request_id = s$state$pcli_request_id,
             provider = m$provider, model = m$id,
             url = paste0("cli:", sub("^cli-", "", m$api %||% "")),
             seconds = round(reactor_now() - s$t0, 3), event = event)
  rec = rec[!vapply(rec, is.null, NA)]
  tryCatch(wire_log_append(path, redact(json_encode(rec), "persist")), error = function(e) NULL)
  invisible(path)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 141 ]`

- [ ] **Step 5: Commit**

```bash
git add R/cli-common.R tests/testthat/test-cli-common.R tests/testthat/fixtures/cli/local-fake-cli.R
git commit -m "feat(cli): shared turn helpers, the weak child table and pcli_stop_child()"
```

---

### Task 5: The cli-claude adapter: argv, files and the turn's input

**Files:**
- Create: `R/cli-claude.R`
- Test: `tests/testthat/test-cli-claude.R` (create)

**Interfaces:**
- Consumes: Tasks 1-4 (`pcli_find()`, `pcli_probe()`, `pcli_notice()`, `pcli_state()`, `pcli_track()`, `pcli_model_id()`, `pcli_params()`, `pcli_split()`, `pcli_unseen()`, `pcli_history_text()`, `pcli_block_text()`, `pcli_system_text()`, `pcli_child()`, `pcli_alive()`, `pcli_stop_child()`, `pcli_control_request()`, `pcli_scalar_num()`); `write_utf8(path, text, eol = "\n", bom = FALSE, final_newline = TRUE)`, `path_norm(path)`, `id_new()` (P01). P05's `process_jsonl` contract: `build()` returns `list(start = list(command, args, env_profile, env, wd) | NULL, send = list(...), close_stdin = lgl(1))`, and a non-`NULL` `start` replaces the session's child.
- Produces: `pcli_claude_args(model_id, mcp_config, system_file, budget = NULL, optout = NULL, resume = NULL)` (the 04 §8.5 argv in its exact order, then `--max-turns`/`--max-budget-usd`, the opt-out, `--resume`); `pcli_claude_mcp_json()`; `pcli_claude_files(state, context, session)` (the two files under `file.path(tempdir(), "gptr", "cli")`, written once per session); `pcli_claude_content(input)` (Anthropic content blocks); `pcli_claude_user_line(content)`; `pcli_claude_budgeted(flags)` (does a child carry `--max-turns`/`--max-budget-usd`?); `pcli_claude_build(model, context, opts)` (04 §8.1 `build`). Adapter state fields: `cli_api` (`"cli-claude"`), `claude_model`, `claude_session` (set by Task 6), `claude_run` (the run that started the child), `claude_flags` (`list(turns, cost)` it was started with), `claude_cost_seen` (its last `total_cost_usd`, Task 6), `claude_mcp_file`, `claude_system_file`, `pcli_request_id`.

The argv is architecture §8.3 / 04 §8.5 verbatim. Report 07 §3.9's verified launch argv used `--session-id`; gptr instead learns the CLI's own session id from `system/init` (Task 6) and passes `--resume <id>` when a session's child is restarted (07 §2.16: "gptr must send the same system prompt file on resume", hence the files are written once per session). A fresh child without a CLI session gets the earlier conversation as a `<conversation_history>` text block (03 §8.3: another model may have answered it); a reused child or a resumed session gets only the turns after the last one its provider answered (`pcli_unseen()`). The first send of a new child is the `initialize` control request of 07 §3.10 (`{"subtype":"initialize","hooks":null}`), which makes the CLI connect the in-process `sdk` server through `mcp_message` before the first user line. The budget flags come from `context$params$cli_budget` (Task 8's `request_params` hook); without them no budget flag is passed.

Child lifetime under a budget: `--max-turns` and `--max-budget-usd` are fixed when the long-lived child starts, the CLI's cost tracker covers the whole process (07 §3.14: `total_cost_usd` equals `modelUsage.costUSD`, which also counts the CLI's auxiliary calls), and IC-66 budgets restart with every top-level call. A child that carries budget flags therefore serves only the run that started it: a later run retires it (stdin closed, then `pcli_stop_child()`) and starts a new child with `--resume <CLI session>` and that run's remaining budget, so continuity and the frozen system-prompt file are kept. Without any budget flag (the user disabled the budget) the child is reused across runs, as 03 §8.3 describes. Task 9's `agent_end` hook retires a budgeted child as soon as its run ends, so no idle CLI process waits for a run that would replace it anyway.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-cli-claude.R`:

```r
# tests/testthat/test-cli-claude.R -- the cli-claude adapter (P20)

source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# The argv of architecture 8.3 / contract 8.5, verbatim
claude_argv_8_3 = function(mcp, system, model) {
  c("-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
    "--include-partial-messages", "--tools", "", "--strict-mcp-config", "--setting-sources", "",
    "--disable-slash-commands", "--mcp-config", mcp, "--permission-prompt-tool", "stdio",
    "--permission-mode", "default", "--allowedTools", "mcp__gptr__*", "--system-prompt-file",
    system, "--model", model)
}

# ---- build (Task 5) ----------------------------------------------------------------------------

test_that("the claude argv equals architecture 8.3 exactly, plus budget, opt-out, resume", {
  expect_identical(pcli_claude_args("claude-sonnet-5-5", "/t/m.json", "/t/s.md"),
                   claude_argv_8_3("/t/m.json", "/t/s.md", "claude-sonnet-5-5"))
  full = pcli_claude_args("claude-opus-5-5", "/t/m.json", "/t/s.md",
                         budget = list(turns = 7.6, cost = 2.5), optout = "--no-bare",
                         resume = "11111111-1111-4111-8111-111111111111")
  expect_identical(full[seq_len(25L)], claude_argv_8_3("/t/m.json", "/t/s.md", "claude-opus-5-5"))
  expect_identical(full[-seq_len(25L)],
                   c("--max-turns", "7", "--max-budget-usd", "2.5", "--no-bare", "--resume",
                     "11111111-1111-4111-8111-111111111111"))
  expect_false("--bare" %in% full)
  expect_identical(pcli_claude_mcp_json(), '{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}')
})

test_that("the new input becomes Anthropic content blocks", {
  input = list(msg_user(list(block_context("workspace", "x = 1"), block_text("Plot it"),
                             block_image("iVBORw0KGgo=", mime = "image/png"))))
  out = pcli_claude_content(input)
  expect_identical(out[[1]], list(type = "text", text = "<workspace>\nx = 1\n</workspace>"))
  expect_identical(out[[2]], list(type = "text", text = "Plot it"))
  expect_identical(out[[3]]$source,
                   list(type = "base64", media_type = "image/png", data = "iVBORw0KGgo="))
  expect_identical(pcli_claude_content(list()), list(list(type = "text", text = "(no new input)")))
  line = json_encode(pcli_claude_user_line(out[1]))
  expect_match(line, '^\\{"type":"user","message":\\{"role":"user","content":\\[\\{"type":"text"')
  expect_match(line, '"parent_tool_use_id":null,"session_id":""}', fixed = TRUE)
})

test_that("build() starts a child once, then reuses it for the next turn", {
  local_fake_cli_path("claude", "text")
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = NULL),
                        pcli_notice = function(cli) invisible(NULL))
  opts = stub_opts()
  ctx = list(system = list(t0 = "You are gptr.", t1 = "Notes."), request_id = "q000000000001",
             messages = list(msg_user("Hello")),
             params = list(cli_mode = "manual", cli_budget = list(cost = 5)))
  spec = pcli_claude_build(stub_model("claude"), ctx, opts)
  args = spec$start$args
  n = length(args)
  expect_identical(spec$start$command, normalizePath(rscript_path(), winslash = "/"))
  expect_identical(args[(n - 26L):n],
                   c(claude_argv_8_3(opts$state$claude_mcp_file, opts$state$claude_system_file,
                                     "claude-sonnet-5-5"), "--max-budget-usd", "5"))
  expect_identical(spec$start$env_profile, "cli-claude")
  expect_false(spec$close_stdin)
  expect_identical(readLines(opts$state$claude_system_file), c("You are gptr.", "", "Notes."))
  expect_identical(readLines(opts$state$claude_mcp_file), pcli_claude_mcp_json())
  expect_identical(spec$send[[1]]$request$subtype, "initialize")
  expect_identical(spec$send[[2]]$message$content, list(list(type = "text", text = "Hello")))
  expect_identical(pcli_tracked("s0123456789"), opts$state)
  opts$state$process = stub_process()
  ctx$messages = c(ctx$messages, list(msg_assistant(list(block_text("Hi")), api = "cli-claude",
                                                    provider = "fakeclaude",
                                                    model = "claude-sonnet-5-5")),
                   list(msg_user("Again")))
  spec2 = pcli_claude_build(stub_model("claude"), ctx, opts)
  expect_null(spec2$start)
  expect_length(spec2$send, 1L)
  expect_identical(spec2$send[[1]]$message$content, list(list(type = "text", text = "Again")))
  pcli_untrack("s0123456789")
})

test_that("a budgeted child serves one run; an unbudgeted child lives across runs", {
  local_fake_cli_path("claude", "text")
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = NULL),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
                          stopped$n = stopped$n + 1L
                          state$process = NULL
                          invisible(TRUE)
                        })
  hi = msg_assistant(list(block_text("Hi")), api = "cli-claude", provider = "fakeclaude",
                     model = "claude-sonnet-5-5")
  ctx = list(system = list(t0 = "T0", t1 = ""), messages = list(msg_user("Hello")),
             params = list(cli_budget = list(cost = 5)))
  opts = stub_opts(run = "r0000000001")
  pcli_claude_build(stub_model("claude"), ctx, opts)
  opts$state$process = stub_process()
  opts$state$claude_session = "11111111-1111-4111-8111-111111111111"
  opts$run = "r0000000002"
  ctx$messages = list(msg_user("Hello"), hi, msg_user("Again"))
  next_run = pcli_claude_build(stub_model("claude"), ctx, opts)
  expect_identical(stopped$n, 1L)
  expect_identical(utils::tail(next_run$start$args, 4L),
                   c("--max-budget-usd", "5", "--resume", "11111111-1111-4111-8111-111111111111"))
  expect_identical(next_run$send[[2]]$message$content, list(list(type = "text", text = "Again")))
  expect_identical(opts$state$claude_run, "r0000000002")
  free = list(system = list(t0 = "T0", t1 = ""), messages = list(msg_user("Hello")),
              params = list(cli_mode = "auto"))
  opts2 = stub_opts(run = "r0000000003")
  pcli_claude_build(stub_model("claude"), free, opts2)
  opts2$state$process = stub_process()
  opts2$run = "r0000000004"
  free$messages = list(msg_user("Hello"), hi, msg_user("Again"))
  expect_null(pcli_claude_build(stub_model("claude"), free, opts2)$start)
  expect_identical(stopped$n, 1L)
  pcli_untrack("s0123456789")
})

test_that("a restarted child resumes the CLI session; a fresh one gets the history", {
  local_fake_cli_path("claude", "text")
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = "--no-bare"),
                        pcli_notice = function(cli) invisible(NULL))
  msgs = list(msg_user("first"),
              msg_assistant(list(block_text("answer one")), api = "anthropic-messages",
                            provider = "anthropic", model = "claude-sonnet-5-5"),
              msg_user("second"))
  ctx = list(system = list(t0 = "T0", t1 = ""), request_id = "q000000000002", messages = msgs)
  opts = stub_opts()
  fresh = pcli_claude_build(stub_model("claude"), ctx, opts)
  expect_false("--resume" %in% fresh$start$args)
  expect_identical(utils::tail(fresh$start$args, 1L), "--no-bare")
  first = fresh$send[[2]]$message$content
  expect_match(first[[1]]$text, "Assistant: answer one", fixed = TRUE)
  expect_identical(first[[2]]$text, "second")
  own = msg_assistant(list(block_text("answer one")), api = "cli-claude", provider = "fakeclaude",
                      model = "claude-sonnet-5-5")
  ctx$messages = list(msg_user("first"), own, msg_user("second"))
  opts2 = stub_opts()
  opts2$state$claude_session = "11111111-1111-4111-8111-111111111111"
  resumed = pcli_claude_build(stub_model("claude"), ctx, opts2)
  expect_identical(utils::tail(resumed$start$args, 2L),
                   c("--resume", "11111111-1111-4111-8111-111111111111"))
  expect_identical(resumed$send[[2]]$message$content, list(list(type = "text", text = "second")))
  ctx$messages = list(msg_user("first"), own, msg_user("aside"),
                      msg_assistant(list(block_text("answer two")), api = "anthropic-messages",
                                    provider = "anthropic", model = "claude-sonnet-5-5"),
                      msg_user("third"))
  opts3 = stub_opts()
  opts3$state$claude_session = "11111111-1111-4111-8111-111111111111"
  later = pcli_claude_build(stub_model("claude"), ctx, opts3)$send[[2]]$message$content
  expect_match(later[[1]]$text, "User: aside\n\nAssistant: answer two", fixed = TRUE)
  expect_false(grepl("answer one", later[[1]]$text, fixed = TRUE))
  expect_identical(later[[2]]$text, "third")
  pcli_untrack("s0123456789")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-claude")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 0 ]`; the five tests error with ``could not find function "pcli_claude_args"``, ``could not find function "pcli_claude_content"`` and ``could not find function "pcli_claude_build"``.

- [ ] **Step 3: Write the implementation**

Create `R/cli-claude.R`:

```r
# The cli-claude adapter (P20): the user's own claude CLI in stream-json mode, one long-lived
# child per session (per run while it carries budget flags), gptr's tools through the
# in-process `sdk` MCP server over the control protocol (architecture 8.3; contract 8.5,
# IC-65). L1: besides L0 helpers it calls only the
# injected opts$send, opts$gate and opts$mcp_dispatch and P12's anthropic_normaliser() (IC-33).
# Adapted from the verified driver of report 07 section 5.7 (cc_proto.R: argv, control
# protocol, notification acks) and its live capture 3.14 (the fixture claude-call2.ndjson).

# ---- build (Task 5) ----------------------------------------------------------------------------

#' The claude argv of architecture 8.3 in its exact order, then the budget flags (IC-65,
#' IC-66), the documented --bare opt-out when the probe found one, and --resume (never --bare)
#' @noRd
pcli_claude_args = function(model_id, mcp_config, system_file, budget = NULL, optout = NULL,
                           resume = NULL) {
  args = c("-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
           "--include-partial-messages", "--tools", "", "--strict-mcp-config",
           "--setting-sources", "", "--disable-slash-commands", "--mcp-config", mcp_config,
           "--permission-prompt-tool", "stdio", "--permission-mode", "default",
           "--allowedTools", "mcp__gptr__*", "--system-prompt-file", system_file,
           "--model", model_id)
  turns = pcli_scalar_num(budget[["turns"]])
  cost = pcli_scalar_num(budget[["cost"]])
  if (!is.null(turns)) args = c(args, "--max-turns", as.character(max(1L, as.integer(turns))))
  if (!is.null(cost)) {
    args = c(args, "--max-budget-usd",
             format(max(0.01, round(cost, 4)), scientific = FALSE, trim = TRUE))
  }
  if (!is.null(optout)) args = c(args, optout)
  if (!is.null(resume)) args = c(args, "--resume", resume)
  args
}

#' The --mcp-config file content: gptr's in-process sdk server (contract 8.5, verbatim)
#' @noRd
pcli_claude_mcp_json = function() '{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}'

#' Write the MCP config and the system-prompt files of a session once, under tempdir(); a
#' restarted child (--resume) gets the same files (07 2.16: the same system prompt on resume)
#' @noRd
pcli_claude_files = function(state, context, session) {
  dir = file.path(tempdir(), "gptr", "cli")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  stem = paste0(session %||% id_new("s", 10L), "-claude")
  if (is.null(state$claude_mcp_file) || !file.exists(state$claude_mcp_file)) {
    state$claude_mcp_file = path_norm(file.path(dir, paste0(stem, "-mcp.json")))
    write_utf8(state$claude_mcp_file, pcli_claude_mcp_json())
  }
  if (is.null(state$claude_system_file) || !file.exists(state$claude_system_file)) {
    state$claude_system_file = path_norm(file.path(dir, paste0(stem, "-system.md")))
    write_utf8(state$claude_system_file, pcli_system_text(context))
  }
  list(mcp = state$claude_mcp_file, system = state$claude_system_file)
}

#' Anthropic content blocks of the new input: text, rendered context blocks, base64 images
#' (07 2.14: the stream-json user message takes Anthropic content blocks)
#' @noRd
pcli_claude_content = function(input) {
  out = list()
  for (m in input) {
    for (b in m[["content"]] %||% list()) {
      type = b[["type"]] %||% ""
      blk = if (identical(type, "image") && is.character(b[["data"]])) {
        list(type = "image", source = list(type = "base64",
                                           media_type = b[["mime"]] %||% "image/png",
                                           data = b[["data"]]))
      } else {
        txt = pcli_block_text(b)
        if (nzchar(txt)) list(type = "text", text = txt) else NULL
      }
      if (!is.null(blk)) out[[length(out) + 1L]] = blk
    }
  }
  if (!length(out)) out = list(list(type = "text", text = "(no new input)"))
  out
}

#' The stdin line of one user turn (contract 8.5; 07 3.12)
#' @noRd
pcli_claude_user_line = function(content) {
  list(type = "user", message = list(role = "user", content = content),
       parent_tool_use_id = NULL, session_id = "")
}

#' Does a child carry budget flags (`--max-turns`, `--max-budget-usd`)?
#' @param flags list(turns, cost) or NULL.
#' @noRd
pcli_claude_budgeted = function(flags) {
  !is.null(flags[["turns"]]) || !is.null(flags[["cost"]])
}

#' build(): reuse the session's live claude child, or start one (find, probe, notice, files,
#' argv, the `initialize` control request), then send the turn (contract 8.1 process_jsonl,
#' 8.5)
#'
#' A child is reused for the same model while it lives, but a child with budget flags only
#' within the run that started it: the flags are fixed at launch and the CLI counts cost for its
#' whole process, while gptr's budgets restart with every top-level call (IC-66). A replaced
#' child is retired here (stdin closed, then kill_all()), and the new one resumes the CLI
#' session. A reused child or a resumed session gets the turns it has not seen (another model
#' may have answered them, pcli_unseen()); a fresh child gets the whole earlier conversation.
#' @noRd
pcli_claude_build = function(model, context, opts) {
  state = pcli_state(opts)
  state$pcli_request_id = context[["request_id"]]
  state$interrupt_id = NULL
  state$interrupt_acked = FALSE
  pcli_track(opts[["session"]], state)
  model_id = pcli_model_id(model)
  par = pcli_params(context)
  parts = pcli_split(context[["messages"]] %||% list())
  flags = list(turns = par$turns, cost = par$cost)
  same_run = identical(state$claude_run, opts[["run"]])
  unbudgeted = !pcli_claude_budgeted(flags) && !pcli_claude_budgeted(state$claude_flags)
  reuse = identical(state$cli_api, "cli-claude") && identical(state$claude_model, model_id) &&
    pcli_alive(pcli_child(state)) && (same_run || unbudgeted)
  start = NULL
  send = list()
  resume = NULL
  if (!reuse) {
    if (pcli_alive(pcli_child(state))) pcli_stop_child(state, wait_ack = FALSE)
    path = pcli_find("claude")
    probe = pcli_probe(path)
    pcli_notice("claude")
    files = pcli_claude_files(state, context, opts[["session"]])
    resume = state$claude_session
    args = pcli_claude_args(model_id, files$mcp, files$system, budget = flags,
                           optout = probe$bare_optout, resume = resume)
    start = list(command = path[[1L]], args = c(as.character(path[-1L]), args),
                 env_profile = "cli-claude", env = character(), wd = path_norm(getwd()))
    state$cli_api = "cli-claude"
    state$claude_model = model_id
    state$claude_run = opts[["run"]]
    state$claude_flags = flags
    state$claude_cost_seen = 0
    state$n_req = 0L
    send = list(pcli_control_request(state, list(subtype = "initialize", hooks = NULL)))
  }
  seen = reuse || !is.null(resume)
  history = pcli_history_text(if (seen) pcli_unseen(parts$prior, model$provider) else parts$prior)
  content = pcli_claude_content(parts$input)
  if (nzchar(history)) content = c(list(list(type = "text", text = history)), content)
  list(start = start, send = c(send, list(pcli_claude_user_line(content))), close_stdin = FALSE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-claude")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 38 ]`

- [ ] **Step 5: Commit**

```bash
git add R/cli-claude.R tests/testthat/test-cli-claude.R
git commit -m "feat(cli): cli-claude build with the exact argv of architecture 8.3"
```

---

### Task 6: The cli-claude normaliser: control protocol, stream, result

**Files:**
- Modify: `R/cli-claude.R` (append)
- Create: `tests/testthat/fixtures/cli/claude-call2.ndjson`, `claude-apikey.ndjson`, `claude-hang.ndjson`
- Modify: `tests/testthat/fixtures/cli/local-fake-cli.R` (append)
- Test: `tests/testthat/test-cli-claude.R` (append)

**Interfaces:**
- Consumes: `anthropic_normaliser(model, opts)` with `push_parsed(obj)` (P12, 04 §7.12); the injected `opts$send(obj)`, `opts$mcp_dispatch(message)` (P18's `mcp.dispatch_local` bound to the session, "the single gate for the claude route", IC-65), `opts$gate(call)` (the run's `perm_check()`), `opts$signal`, `opts$run`, `opts$emit` (04 §8.1, IC-33); `reactor_enqueue_tool(run, fn)` (P04); `redact(x, profile = "persist")` (P03); `usage_new(...)` (P05); `json_obj()` (P01); Tasks 3-4.
- Produces: `pcli_claude_parse(model, opts)` -> `list(push, finish, fail, message)` (04 §8.1); private `pcli_control_ok(id, response)`, `pcli_control_err(id, error)`, `pcli_jsonrpc_error(msg, code, text)`, `pcli_claude_ack(obj, state)`, `pcli_claude_mcp(req, id, s)`, `pcli_claude_permission(req, opts)`, `pcli_claude_control(obj, s)`, `pcli_claude_refuse(obj, s)`, `pcli_claude_forward(ev, s)`, `pcli_claude_stream(event, s)`, `pcli_claude_system(obj, s)`, `pcli_claude_cost(obj, state = NULL)`, `pcli_claude_usage(obj, state = NULL)`, `pcli_claude_stop(raw)`, `pcli_claude_error_class(obj)`, `pcli_claude_result(obj, s)`, `pcli_claude_timeout(s)`. Terminal error classes: `billing`, `max_turns`, `budget_cost`, `auth`, `rate_limit`, `overloaded`, `provider`, `timeout`, `aborted`. Test support: `local_normaliser(parse, model, opts, .env = parent.frame())`, `feed_fixture(n, name)`, `push_obj(n, obj)`.

The control protocol follows report 07 §3.10 and §5.7 (`cc_proto.R`, verified live with CLI 2.1.261; verification log item 18): `mcp_message` is answered with `{"mcp_response": <JSON-RPC response>}`, a JSON-RPC notification (no `id`) with the ack `{"jsonrpc":"2.0","result":{}}` (`query.py:670-673`), an unknown server with JSON-RPC error `-32601`, an unsupported subtype with an error response `Unsupported control request subtype: <subtype>`. `tools/call` runs from P04's tool FIFO of the run (`reactor_enqueue_tool(opts$run, ...)`), so it never overlaps another agent's R tool and a nested pump runs it only for the runs it waits for (IC-57); the handshake runs at once. `can_use_tool` for `mcp__gptr__*` is allowed without a gate call (they are pre-allowed by `--allowedTools`, so the gate runs once, in the `mcp_message` dispatch; IC-65); any other tool goes to `opts$gate(call)` with a 04 §4.4 call record. `stream_event` lines (07 §2.14; `parent_tool_use_id` non-null lines belong to the CLI's own sub-agents and are skipped) feed a fresh `anthropic_normaliser()` per API message (07 §5.8: "The CLI stream reuses the native accumulator", verified); its `start` and terminal events are absorbed and text/thinking blocks re-indexed into the one outer stream of the turn, while its tool-call events are dropped (the tools ran through `mcp_message`). `rate_limit_event` is nested under `rate_limit_info` (07 verification log item 25). The `result` line ends the turn (07 §2.14 subtypes; an API failure arrives as `subtype: "success"` with `is_error: true` and `api_error_status`); its `total_cost_usd` covers the CLI process (it equals `modelUsage.costUSD` in the 07 §3.14 capture, which also counts the CLI's auxiliary calls), so a turn's cost is the increase since the child's previous result (`pcli_claude_cost()`; a child without budget flags serves several runs); "No conversation found" clears the CLI session id so the next child starts fresh (07 §2.13). Error texts for a timeout contain "out of budget", which P06's retry rules treat as final. The fixture `claude-call2.ndjson` is the redacted live capture of 07 §3.14 (39 lines; only the R code the model wrote inside two JSON strings is spelled with `=`, conventions §4); `claude-apikey.ndjson` and `claude-hang.ndjson` are constructed in the same shapes.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/cli/claude-call2.ndjson` (the 07 §3.14 capture, one JSON object per line; keep each line on one line):

```text
{"type":"system","subtype":"init","cwd":"<cwd>","session_id":"<session_id>","tools":["mcp__gptr__r_eval","mcp__gptr__r_plot"],"mcp_servers":[{"name":"gptr","status":"connected"}],"model":"claude-haiku-4-5-20251001","permissionMode":"default","slash_commands":[],"apiKeySource":"none","claude_code_version":"2.1.261","output_style":"default","agents":["claude","Explore","general-purpose","Plan","statusline-setup"],"skills":[],"plugins":[],"capabilities":["interrupt_receipt_v1","interrupt_cancel_queued_v1","msg_lifecycle_v1"],"analytics_disabled":false,"product_feedback_disabled":false,"uuid":"<uuid>","memory_paths":{"auto":"<path>"},"messaging_socket_path":"<socket>","fast_mode_state":"off","fast_mode_disabled_reason":"sdk_opt_in_required"}
{"type":"system","subtype":"status","status":"requesting","session_id":"<session_id>","uuid":"<uuid>"}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1790749800,"rateLimitType":"five_hour","overageStatus":"rejected","overageDisabledReason":"out_of_credits","isUsingOverage":false,"unifiedWindows":{"five_hour":{"utilization":0.15,"resetsAt":1790749800},"seven_day":{"utilization":0.34,"resetsAt":1790870400}}},"uuid":"<uuid>","session_id":"<session_id>"}
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"<id>","type":"message","role":"assistant","content":[],"container":null,"stop_reason":null,"stop_sequence":null,"stop_details":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":7448,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":7448},"output_tokens":3,"service_tier":"standard","inference_geo":"not_available"},"diagnostics":null,"context_management":null}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>","ttft_ms":636}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":"<signature>"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"system","subtype":"thinking_tokens","estimated_tokens":50,"estimated_tokens_delta":50,"session_id":"<session_id>","uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"","estimated_tokens":50}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"","estimated_tokens":null}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"system","subtype":"thinking_tokens","estimated_tokens":133,"estimated_tokens_delta":83,"session_id":"<session_id>","uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"<signature>"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","id":"<id>","type":"message","role":"assistant","content":[{"type":"thinking","thinking":"","signature":"<signature>"}],"container":null,"stop_reason":null,"stop_sequence":null,"stop_details":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":7448,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":7448},"output_tokens":3,"service_tier":"standard","inference_geo":"not_available"},"diagnostics":null,"context_management":null},"parent_tool_use_id":null,"session_id":"<session_id>","uuid":"<uuid>","timestamp":"2026-09-30T01:41:51.406Z","request_id":"<request_id>"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"<id>","name":"mcp__gptr__r_eval","input":{},"caller":{"type":"direct"}}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"code\": \"answer"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" = mean(big"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"_vector) *"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" 2;"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" answer"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"}"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","id":"<id>","type":"message","role":"assistant","content":[{"type":"tool_use","id":"<id>","name":"mcp__gptr__r_eval","input":{"code":"answer = mean(big_vector) * 2; answer"},"caller":{"type":"direct"}}],"container":null,"stop_reason":null,"stop_sequence":null,"stop_details":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":7448,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":7448},"output_tokens":3,"service_tier":"standard","inference_geo":"not_available"},"diagnostics":null,"context_management":null},"parent_tool_use_id":null,"session_id":"<session_id>","uuid":"<uuid>","timestamp":"2026-09-30T01:41:51.701Z","request_id":"<request_id>","tool_use_meta":[{"id":"<id>","display_name":"R Eval","server_display_name":"gptr"}]}
{"type":"stream_event","event":{"type":"content_block_stop","index":1},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null,"stop_details":null,"container":null},"usage":{"input_tokens":10,"cache_creation_input_tokens":7448,"cache_read_input_tokens":0,"output_tokens":137,"output_tokens_details":{"thinking_tokens":63},"iterations":[{"input_tokens":10,"output_tokens":137,"cache_read_input_tokens":0,"cache_creation_input_tokens":7448,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":7448},"type":"message"}]},"context_management":{"applied_edits":[]}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"<tool_use_id>","type":"tool_result","content":[{"type":"text","text":"[1] 24"}]}]},"parent_tool_use_id":null,"session_id":"<session_id>","uuid":"<uuid>","timestamp":"2026-09-30T01:41:51.754Z","tool_use_result":[{"type":"text","text":"[1] 24"}]}
{"type":"system","subtype":"status","status":"requesting","session_id":"<session_id>","uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-haiku-4-5-20251001","id":"<id>","type":"message","role":"assistant","content":[],"container":null,"stop_reason":null,"stop_sequence":null,"stop_details":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":193,"cache_read_input_tokens":7448,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":193},"output_tokens":3,"service_tier":"standard","inference_geo":"not_available"},"diagnostics":null,"context_management":null}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>","ttft_ms":464}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":"<signature>"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"","estimated_tokens":null}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"<signature>"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","id":"<id>","type":"message","role":"assistant","content":[{"type":"thinking","thinking":"","signature":"<signature>"}],"container":null,"stop_reason":null,"stop_sequence":null,"stop_details":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":193,"cache_read_input_tokens":7448,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":193},"output_tokens":3,"service_tier":"standard","inference_geo":"not_available"},"diagnostics":null,"context_management":null},"parent_tool_use_id":null,"session_id":"<session_id>","uuid":"<uuid>","timestamp":"2026-09-30T01:41:52.462Z","request_id":"<request_id>"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"24"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","id":"<id>","type":"message","role":"assistant","content":[{"type":"text","text":"24"}],"container":null,"stop_reason":null,"stop_sequence":null,"stop_details":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":193,"cache_read_input_tokens":7448,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":193},"output_tokens":3,"service_tier":"standard","inference_geo":"not_available"},"diagnostics":null,"context_management":null},"parent_tool_use_id":null,"session_id":"<session_id>","uuid":"<uuid>","timestamp":"2026-09-30T01:41:52.559Z","request_id":"<request_id>"}
{"type":"stream_event","event":{"type":"content_block_stop","index":1},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null,"stop_details":null,"container":null},"usage":{"input_tokens":10,"cache_creation_input_tokens":193,"cache_read_input_tokens":7448,"output_tokens":35,"output_tokens_details":{"thinking_tokens":28},"iterations":[{"input_tokens":10,"output_tokens":35,"cache_read_input_tokens":7448,"cache_creation_input_tokens":193,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":193},"type":"message"}]},"context_management":{"applied_edits":[]}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"duration_api_ms":3458,"stop_reason":"end_turn","session_id":"<session_id>","total_cost_usd":0.0178928,"usage":{"input_tokens":20,"cache_creation_input_tokens":7641,"cache_read_input_tokens":7448,"output_tokens":172,"output_tokens_details":{"thinking_tokens":91},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":7641,"ephemeral_5m_input_tokens":0},"inference_geo":"not_available","iterations":[{"input_tokens":10,"output_tokens":35,"cache_read_input_tokens":7448,"cache_creation_input_tokens":193,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":193},"type":"message"}],"speed":"standard"},"modelUsage":{"claude-haiku-4-5-20251001":{"inputTokens":946,"outputTokens":184,"cacheReadInputTokens":7448,"cacheCreationInputTokens":7641,"webSearchRequests":0,"costUSD":0.0178928,"contextWindow":200000,"maxOutputTokens":32000,"thinkingTokens":91,"canonicalModel":"claude-haiku-4-5","provider":"firstParty","costBasis":"list"}},"permission_denials":[],"terminal_reason":"completed","fast_mode_state":"off","fast_mode_disabled_reason":"sdk_opt_in_required","subagent_stats":{"spawned":0,"requested":{"background":0,"foreground":0,"unset":0},"started_in_background":0,"max_depth":0,"spawned_by_subagents":0,"completed":0,"failed":0,"killed":{"parent":0,"user":0,"system":0},"refused":{"depth_limit":0,"concurrency_limit":0,"budget":0},"by_type":{}},"is_error":false,"num_turns":2,"subtype":"success","api_error_status":null,"result":"24","ttft_ms":1461,"type":"result","duration_ms":2692,"uuid":"<uuid>","ttft_stream_ms":727,"time_to_request_ms":91,"first_content_frame_ms":728,"queued_turn_count":0}
```

Create `tests/testthat/fixtures/cli/claude-apikey.ndjson`:

```text
{"type":"system","subtype":"init","cwd":"<cwd>","session_id":"11111111-1111-4111-8111-111111111111","tools":["mcp__gptr__r","mcp__gptr__read","mcp__gptr__edit","mcp__gptr__write"],"mcp_servers":[{"name":"gptr","status":"connected"}],"model":"claude-sonnet-5-5","permissionMode":"default","apiKeySource":"ANTHROPIC_API_KEY","claude_code_version":"2.1.261","uuid":"u"}
{"fake":"hang"}
```

Create `tests/testthat/fixtures/cli/claude-hang.ndjson`:

```text
{"type":"system","subtype":"init","cwd":"<cwd>","session_id":"11111111-1111-4111-8111-111111111111","tools":["mcp__gptr__r","mcp__gptr__read","mcp__gptr__edit","mcp__gptr__write"],"mcp_servers":[{"name":"gptr","status":"connected"}],"model":"claude-sonnet-5-5","permissionMode":"default","apiKeySource":"none","claude_code_version":"2.1.261","uuid":"u"}
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-sonnet-5-5","id":"msg_fake_1","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":12,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Working"}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"fake":"hang"}
```

Append to `tests/testthat/fixtures/cli/local-fake-cli.R`:

```r
# A normaliser of one turn whose wall-clock timer is cancelled when the test ends
local_normaliser = function(parse, model, opts, .env = parent.frame()) {
  n = parse(model, opts)
  withr::defer({
    t = opts$state$turn_timer
    if (!is.null(t)) reactor_cancel(t)
  }, envir = .env)
  n
}

# Feed a fixture transcript to a normaliser as process lines (fake-CLI directives skipped);
# TRUE when the turn completed
feed_fixture = function(n, name) {
  done = FALSE
  lines = readLines(file.path(fake_cli_fixtures(), name), encoding = "UTF-8", warn = FALSE)
  for (ln in lines[nzchar(lines)]) {
    obj = json_decode(ln)
    if (!is.null(obj[["fake"]])) next
    done = n$push(list(data = ln, obj = obj))
    if (isTRUE(done)) break
  }
  done
}

# Push one object as a process line
push_obj = function(n, obj) n$push(list(data = json_encode(obj), obj = obj))
```

Append to `tests/testthat/test-cli-claude.R`:

```r
# ---- the cli-claude normaliser (Task 6) ---------------------------------------------------------

test_that("the call-2 capture streams thinking and text and reports the result's usage", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  opts = stub_opts()
  opts$state$pcli_request_id = "q000000000003"
  n = local_normaliser(pcli_claude_parse, stub_model("claude", "claude-haiku-4-5"), opts)
  expect_true(feed_fixture(n, "claude-call2.ndjson"))
  expect_identical(event_types(opts),
                   c("start", "thinking_start", "thinking_end", "thinking_start", "thinking_end",
                     "text_start", "text_delta", "text_end", "done"))
  msg = n$message()
  expect_identical(msg_text(msg), "24")
  expect_identical(vapply(msg$content, function(b) b$type, ""), c("thinking", "thinking", "text"))
  expect_true(nzchar(msg$content[[1]]$signature))
  expect_identical(msg$stop_reason, "stop")
  expect_identical(msg$raw_stop_reason, "end_turn")
  expect_identical(msg$route, "plan-cli")
  expect_identical(msg$request_id, "q000000000003")
  expect_identical(msg$response_model, "claude-haiku-4-5-20251001")
  u = msg$usage
  expect_equal(c(u$input, u$output, u$cache_read, u$cache_write_5m, u$cache_write_1h,
                 u$reasoning), c(20, 172, 7448, 0, 7641, 91))
  expect_equal(u$cost$total, 0.0178928)
  expect_identical(opts$state$claude_session, "<session_id>")
  expect_identical(pcli_cache$plan$fakeclaude$type, "five_hour")
  expect_false(opts$state$turn_open)
  expect_null(opts$state$turn_timer)
  expect_identical(n$finish(), msg)
})

test_that("a reused child's turn costs the increase of the CLI's total_cost_usd", {
  state = new.env()
  expect_equal(pcli_claude_cost(list(total_cost_usd = 0.02), state), 0.02)
  expect_equal(pcli_claude_cost(list(total_cost_usd = 0.035), state), 0.015)
  expect_equal(state$claude_cost_seen, 0.035)
  expect_equal(pcli_claude_cost(list(total_cost_usd = 0.01), state), 0.01)
  expect_null(pcli_claude_cost(list(), state))
  expect_equal(pcli_claude_cost(list(total_cost_usd = 0.5)), 0.5)
})

test_that("mcp_message requests go to opts$mcp_dispatch; tools/call through the tool FIFO", {
  queued = new.env()
  queued$fns = list()
  local_mocked_bindings(reactor_enqueue_tool = function(run, fn) {
    queued$run = run
    queued$fns[[length(queued$fns) + 1L]] = fn
    invisible("f1")
  })
  opts = stub_opts(run = "r0000000001")
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  mcp = function(id, message, server = "gptr") {
    list(type = "control_request", request_id = id,
         request = list(subtype = "mcp_message", server_name = server, message = message))
  }
  push_obj(n, mcp("c1", list(jsonrpc = "2.0", id = 0L, method = "initialize")))
  push_obj(n, mcp("c2", list(jsonrpc = "2.0", method = "notifications/initialized")))
  push_obj(n, mcp("c3", list(jsonrpc = "2.0", id = 1L, method = "tools/call",
                             params = list(name = "r", arguments = list(code = "1 + 1")))))
  push_obj(n, mcp("c4", list(jsonrpc = "2.0", id = 2L, method = "tools/list"), server = "other"))
  expect_length(opts$log$sent, 3L)
  expect_identical(opts$log$sent[[1]]$response$request_id, "c1")
  expect_identical(opts$log$sent[[1]]$response$response$mcp_response$id, 0L)
  expect_identical(opts$log$sent[[2]]$response$response$mcp_response,
                   list(jsonrpc = "2.0", result = json_obj()))
  expect_identical(opts$log$sent[[3]]$response$response$mcp_response$error$code, -32601L)
  expect_length(queued$fns, 1L)
  expect_identical(queued$run, "r0000000001")
  queued$fns[[1]]()
  expect_length(opts$log$sent, 4L)
  expect_identical(opts$log$sent[[4]]$response$request_id, "c3")
  res = opts$log$sent[[4]]$response$response$mcp_response
  expect_identical(res$result$content[[1]]$text, "[1] 24")
  expect_identical(vapply(opts$log$dispatched, function(m) m$method, ""),
                   c("initialize", "notifications/initialized", "tools/call"))
  expect_length(opts$log$gated, 0L)
})

test_that("can_use_tool allows gptr's own tools without a second gate; others ask the gate", {
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  ask = function(id, tool) {
    list(type = "control_request", request_id = id,
         request = list(subtype = "can_use_tool", tool_name = tool,
                        input = list(code = "x = 1"), tool_use_id = "toolu_1"))
  }
  push_obj(n, ask("p1", "mcp__gptr__r"))
  expect_identical(opts$log$sent[[1]]$response$response,
                   list(behavior = "allow", updatedInput = list(code = "x = 1")))
  expect_length(opts$log$gated, 0L)
  push_obj(n, ask("p2", "Bash"))
  expect_identical(opts$log$sent[[2]]$response$response,
                   list(behavior = "deny", message = "denied in tests"))
  expect_length(opts$log$gated, 1L)
  expect_identical(opts$log$gated[[1]]$name, "Bash")
  opts2 = stub_opts(gate = function(call) list(decision = "allow", reason = "ok", input = NULL))
  n2 = local_normaliser(pcli_claude_parse, stub_model("claude"), opts2)
  push_obj(n2, ask("p3", "Bash"))
  expect_identical(opts2$log$sent[[1]]$response$response$behavior, "allow")
  push_obj(n2, list(type = "control_request", request_id = "p4",
                    request = list(subtype = "rewind_files")))
  expect_identical(opts2$log$sent[[2]]$response,
                   list(subtype = "error", request_id = "p4",
                        error = "Unsupported control request subtype: rewind_files"))
})

test_that("an apiKeySource other than none ends the turn with gptr_error_billing", {
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    stopped$n = stopped$n + 1L
    stopped$wait = wait_ack
    invisible(TRUE)
  })
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  expect_true(feed_fixture(n, "claude-apikey.ndjson"))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$type, "error")
  expect_identical(ev$error$class, "billing")
  expect_match(ev$message$error_message, "apiKeySource ANTHROPIC_API_KEY", fixed = TRUE)
  expect_identical(stopped$n, 1L)
  expect_false(stopped$wait)
})

test_that("failed results map to gptr condition classes", {
  run = function(result) {
    opts = stub_opts()
    n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
    push_obj(n, c(list(type = "result", usage = list(input_tokens = 3L)), result))
    ev = opts$log$events[[length(opts$log$events)]]
    list(ev = ev, state = opts$state)
  }
  r = run(list(subtype = "error_max_turns", is_error = TRUE))
  expect_identical(r$ev$error$class, "max_turns")
  expect_match(r$ev$message$error_message, "--max-turns", fixed = TRUE)
  expect_identical(run(list(subtype = "error_max_budget_usd", is_error = TRUE))$ev$error$class,
                   "budget_cost")
  r = run(list(subtype = "success", is_error = TRUE, api_error_status = 429L))
  expect_identical(r$ev$error$class, "rate_limit")
  expect_identical(r$ev$error$status, 429L)
  r = run(list(subtype = "error_during_execution", is_error = TRUE,
               terminal_reason = "aborted_streaming"))
  expect_identical(r$ev$reason, "aborted")
  expect_identical(r$ev$message$stop_reason, "aborted")
  opts = stub_opts()
  opts$state$claude_session = "gone"
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  push_obj(n, list(type = "result", subtype = "error_during_execution", is_error = TRUE,
                   errors = list("No conversation found with session ID: gone")))
  expect_null(opts$state$claude_session)
})

test_that("a turn without a result line ends with an error; an aborted one with aborted", {
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  feed_fixture(n, "claude-hang.ndjson")
  msg = n$finish()
  expect_identical(msg$stop_reason, "error")
  expect_match(msg$error_message, "exited before the end of the turn", fixed = TRUE)
  expect_identical(msg_text(msg), "Working")
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_claude_parse, stub_model("claude"), opts2)
  opts2$signal$aborted = TRUE
  push_obj(n2, list(type = "control_request", request_id = "c9",
                    request = list(subtype = "mcp_message", server_name = "gptr",
                                   message = list(jsonrpc = "2.0", id = 5L,
                                                  method = "tools/call"))))
  expect_identical(opts2$log$sent[[1]]$response$response$mcp_response$error$message,
                   "The gptr turn is over.")
  expect_length(opts2$log$dispatched, 0L)
  expect_identical(n2$finish()$stop_reason, "aborted")
})

test_that("the per-turn wall clock interrupts the CLI and ends the turn as out of budget", {
  local_gptr_options(cli_turn_timeout = 0.3)
  opts = stub_opts()
  n = local_normaliser(pcli_claude_parse, stub_model("claude"), opts)
  expect_true(reactor_pump(until = function() length(opts$log$events) > 0L, timeout = 5))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$type, "error")
  expect_identical(ev$error$class, "timeout")
  expect_match(ev$message$error_message, "out of budget", fixed = TRUE)
  expect_identical(opts$log$sent[[1]]$request$subtype, "interrupt")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-claude")'`

Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 38 ]`; the eight new tests error with ``could not find function "pcli_claude_parse"`` or ``could not find function "pcli_claude_cost"``.

- [ ] **Step 3: Write the implementation**

Append to `R/cli-claude.R`:

```r
# ---- the cli-claude normaliser (Task 6) --------------------------------------------------------

#' A success control_response (07 3.10)
#' @noRd
pcli_control_ok = function(id, response) {
  list(type = "control_response",
       response = list(subtype = "success", request_id = id, response = response))
}

#' An error control_response (07 3.10)
#' @noRd
pcli_control_err = function(id, error) {
  list(type = "control_response",
       response = list(subtype = "error", request_id = id, error = error))
}

#' A JSON-RPC error answering `msg`
#' @noRd
pcli_jsonrpc_error = function(msg, code, text) {
  list(jsonrpc = "2.0", id = msg[["id"]], error = list(code = code, message = text))
}

#' Note the CLI's answer to gptr's interrupt request (pcli_stop_child() waits for it)
#' @noRd
pcli_claude_ack = function(obj, state) {
  id = obj[["response"]][["request_id"]]
  if (!is.null(id) && identical(id, state$interrupt_id)) state$interrupt_acked = TRUE
  invisible(NULL)
}

#' mcp_message: one JSON-RPC message for gptr's tools, answered through opts$mcp_dispatch (P18's
#' mcp_dispatch_local, the single gate of the claude route, IC-65)
#'
#' `tools/call` runs from the reactor's tool FIFO of the run, so the R tools of other agents
#' never overlap with it (IC-57); the handshake and notifications are answered at once. A
#' notification (no id) gets the ack `{"jsonrpc":"2.0","result":{}}` (07 3.10).
#' @noRd
pcli_claude_mcp = function(req, id, s) {
  opts = s$opts
  msg = req[["message"]] %||% list()
  answer = function(resp) pcli_send(opts, pcli_control_ok(id, list(mcp_response = resp)))
  if (!identical(req[["server_name"]], "gptr")) {
    return(answer(pcli_jsonrpc_error(msg, -32601L, "Server not found")))
  }
  dispatch = opts[["mcp_dispatch"]]
  if (!is.function(dispatch)) {
    return(answer(pcli_jsonrpc_error(msg, -32603L, "gptr's MCP dispatcher is not available")))
  }
  run_it = function() {
    if (pcli_aborted(s)) {
      return(answer(pcli_jsonrpc_error(msg, -32603L, "The gptr run was aborted.")))
    }
    resp = tryCatch(dispatch(msg), error = function(e) {
      pcli_jsonrpc_error(msg, -32603L, redact(conditionMessage(e), "context"))
    })
    if (is.null(resp)) resp = list(jsonrpc = "2.0", result = json_obj())
    answer(resp)
  }
  run = opts[["run"]]
  if (identical(msg[["method"]], "tools/call") && is.character(run) && length(run) == 1L) {
    reactor_enqueue_tool(run, run_it)
  } else {
    run_it()
  }
  invisible(NULL)
}

#' can_use_tool: gptr's own tools are pre-allowed by --allowedTools mcp__gptr__* and gated once,
#' in mcp_message; any other tool goes through the injected opts$gate (03 8.3)
#' @noRd
pcli_claude_permission = function(req, opts) {
  name = req[["tool_name"]] %||% ""
  input = req[["input"]]
  if (!length(input)) input = json_obj()
  if (startsWith(name, "mcp__gptr__")) return(list(behavior = "allow", updatedInput = input))
  gate = opts[["gate"]]
  if (!is.function(gate)) {
    return(list(behavior = "deny", message = "gptr has no permission gate for this request."))
  }
  call = list(id = req[["tool_use_id"]] %||% "cli", name = name, input = input, raw = NULL,
              tool = NULL, nested = FALSE, parent_id = NULL, outer_level = NULL, risk = NULL)
  d = tryCatch(gate(call), error = function(e) {
    list(decision = "deny", reason = conditionMessage(e))
  })
  if ((d[["decision"]] %||% "") %in% c("allow", "modify")) {
    upd = d[["input"]]
    if (!length(upd)) upd = input
    return(list(behavior = "allow", updatedInput = upd))
  }
  list(behavior = "deny", message = d[["reason"]] %||% "Denied by gptr's permission gate.")
}

#' Answer a control_request from the CLI (contract 8.5)
#' @noRd
pcli_claude_control = function(obj, s) {
  req = obj[["request"]] %||% list()
  id = obj[["request_id"]]
  sub = req[["subtype"]] %||% ""
  if (identical(sub, "mcp_message")) return(pcli_claude_mcp(req, id, s))
  if (identical(sub, "can_use_tool")) {
    return(pcli_send(s$opts, pcli_control_ok(id, pcli_claude_permission(req, s$opts))))
  }
  pcli_send(s$opts, pcli_control_err(id, paste("Unsupported control request subtype:", sub)))
}

#' Refuse a control request that arrives after the turn ended or after an abort
#' @noRd
pcli_claude_refuse = function(obj, s) {
  req = obj[["request"]] %||% list()
  id = obj[["request_id"]]
  if (identical(req[["subtype"]], "mcp_message")) {
    msg = req[["message"]] %||% list()
    resp = pcli_jsonrpc_error(msg, -32603L, "The gptr turn is over.")
    return(pcli_send(s$opts, pcli_control_ok(id, list(mcp_response = resp))))
  }
  if (identical(req[["subtype"]], "can_use_tool")) {
    answer = list(behavior = "deny", message = "The gptr turn is over.")
    return(pcli_send(s$opts, pcli_control_ok(id, answer)))
  }
  pcli_send(s$opts, pcli_control_err(id, "The gptr turn is over."))
}

#' Forward one event of the inner (per API message) Anthropic normaliser into the turn's stream
#'
#' One outer stream per CLI turn: inner `start` and terminal events are absorbed, text and
#' thinking blocks are re-indexed, tool calls are not forwarded (they ran through mcp_message).
#' @noRd
pcli_claude_forward = function(ev, s) {
  type = ev[["type"]] %||% ""
  if (identical(type, "start")) return(pcli_start(s, ev[["response_id"]]))
  kinds = c("text_start", "text_delta", "text_end", "thinking_start", "thinking_delta",
            "thinking_end")
  if (!(type %in% kinds) || s$done) return(invisible(NULL))
  key = as.character(ev[["index"]])
  if (type %in% c("text_start", "thinking_start")) {
    pcli_start(s)
    s$n = s$n + 1L
    s$map[key] = s$n
    o = new.env(parent = emptyenv())
    o$kind = sub("_start$", "", type)
    o$parts = vector("list", 16L)
    o$n = 0L
    s$open[[s$n]] = o
  }
  i = unname(s$map[key])
  if (!length(i) || is.na(i)) return(invisible(NULL))
  ev[["index"]] = i
  if (type %in% c("text_delta", "thinking_delta")) {
    o = s$open[[i]]
    if (o$n == length(o$parts)) length(o$parts) = 2L * length(o$parts)
    o$n = o$n + 1L
    o$parts[[o$n]] = ev[["delta"]]
  }
  if (type %in% c("text_end", "thinking_end")) s$blocks[[i]] = ev[["block"]]
  emit = s$opts[["emit"]]
  if (is.function(emit)) emit(ev)
  invisible(NULL)
}

#' Feed one `stream_event` (a raw Anthropic SSE data object) to the inner normaliser; a new one
#' starts at each `message_start` (07 5.8: the CLI stream reuses the native accumulator)
#' @noRd
pcli_claude_stream = function(event, s) {
  if (!is.list(event)) return(invisible(NULL))
  if (identical(event[["type"]], "message_start") || is.null(s$inner)) {
    s$map = integer()
    inner_opts = list(emit = function(ev) pcli_claude_forward(ev, s),
                      retry = function(info) invisible(NULL), signal = s$opts[["signal"]])
    s$inner = anthropic_normaliser(s$model, inner_opts)
  }
  s$inner$push_parsed(event)
  invisible(NULL)
}

#' system lines: `init` records the CLI session id and model; an `apiKeySource` other than
#' "none" stops the turn with gptr_error_billing and the child (07 line 503; IC-65)
#' @noRd
pcli_claude_system = function(obj, s) {
  if (!identical(obj[["subtype"]], "init")) return(invisible(NULL))
  sid = obj[["session_id"]]
  if (is.character(sid) && length(sid) == 1L && nzchar(sid)) s$state$claude_session = sid
  if (is.character(obj[["model"]])) s$response_model = obj[["model"]]
  src = obj[["apiKeySource"]]
  if (is.null(src) || identical(src, "none")) return(invisible(NULL))
  why = paste0("The claude CLI reported apiKeySource ", src, ": this turn would be billed to ",
               "an API key instead of your Claude plan, so gptr stopped it. Remove the key from ",
               "the claude CLI's own settings, or use the anthropic provider for API billing.")
  pcli_fail(s, "billing", why)
  pcli_stop_child(s$state, wait_ack = FALSE)
  invisible(NULL)
}

#' The plan-cost estimate of one turn from a `result` line (contract 8.5). `total_cost_usd`
#' covers the whole CLI process (07 3.14: it equals `modelUsage.costUSD`, which also counts the
#' CLI's auxiliary calls), so the turn costs its increase since the child's previous result;
#' a smaller value (a new process) counts whole. NULL when the line carries no cost.
#' @noRd
pcli_claude_cost = function(obj, state = NULL) {
  total = suppressWarnings(as.numeric(obj[["total_cost_usd"]] %||% NA_real_)[1L])
  if (is.na(total)) return(NULL)
  if (!is.environment(state)) return(total)
  seen = state$claude_cost_seen %||% 0
  state$claude_cost_seen = total
  if (total >= seen) total - seen else total
}

#' Usage of a `result` line: the CLI's token totals for the turn and its plan-cost estimate
#' (contract 8.5); 5-minute and 1-hour cache writes split as in 07 5.2
#' @noRd
pcli_claude_usage = function(obj, state = NULL) {
  u = obj[["usage"]] %||% list()
  cc = u[["cache_creation"]]
  if (is.list(cc)) {
    w5 = cc[["ephemeral_5m_input_tokens"]]
    w1 = cc[["ephemeral_1h_input_tokens"]]
  } else {
    w5 = u[["cache_creation_input_tokens"]]
    w1 = 0
  }
  usage_new(input = u[["input_tokens"]], output = u[["output_tokens"]],
            cache_read = u[["cache_read_input_tokens"]], cache_write_5m = w5,
            cache_write_1h = w1, reasoning = u[["output_tokens_details"]][["thinking_tokens"]],
            cost = list(total = pcli_claude_cost(obj, state)))
}

#' gptr stop reason of the CLI's final stop reason (04 4.2; no tool_use: tools ran in the CLI)
#' @noRd
pcli_claude_stop = function(raw) {
  switch(raw %||% "end_turn", max_tokens = "length", refusal = "refusal", pause_turn = "pause",
         "stop")
}

#' Condition class (04 2.2 suffix) of a failed `result` line
#' @noRd
pcli_claude_error_class = function(obj) {
  sub = obj[["subtype"]] %||% ""
  if (identical(sub, "error_max_turns")) return("max_turns")
  if (identical(sub, "error_max_budget_usd")) return("budget_cost")
  st = suppressWarnings(as.integer(obj[["api_error_status"]] %||% NA_integer_))
  if (!is.na(st) && st %in% c(401L, 403L)) return("auth")
  if (!is.na(st) && st == 429L) return("rate_limit")
  if (!is.na(st) && st >= 500L) return("overloaded")
  "provider"
}

#' result: the end of the turn (usage, plan cost estimate, route plan-cli) or its failure
#' @noRd
pcli_claude_result = function(obj, s) {
  text = obj[["result"]]
  has_text = any(vapply(pcli_blocks(s), function(b) identical(b[["type"]], "text"), NA))
  if (!has_text && is.character(text) && length(text) == 1L) pcli_text_block(s, text)
  usage = pcli_claude_usage(obj, s$state)
  aborted = startsWith(obj[["terminal_reason"]] %||% "", "aborted")
  failed = isTRUE(obj[["is_error"]]) || !identical(obj[["subtype"]] %||% "success", "success")
  if (!aborted && !failed) {
    raw = obj[["stop_reason"]] %||% "end_turn"
    return(pcli_done(s, usage, pcli_claude_stop(raw), raw))
  }
  detail = as.character(unlist(obj[["errors"]]))
  if (any(grepl("No conversation found", detail, fixed = TRUE))) s$state$claude_session = NULL
  cls = if (aborted) "aborted" else pcli_claude_error_class(obj)
  what = switch(cls,
                max_turns = "it reached --max-turns",
                budget_cost = "the turn is out of budget (--max-budget-usd)",
                aborted = "the turn was interrupted",
                paste0("it reported ", obj[["subtype"]] %||% "an error"))
  if (length(detail)) what = paste0(what, ": ", paste(detail, collapse = "; "))
  pcli_fail(s, cls, paste0("The claude CLI ended the turn: ", what, "."),
           reason = if (aborted) "aborted" else "error",
           status = obj[["api_error_status"]] %||% NA_integer_, usage = usage)
}

#' The per-turn wall-clock limit passed: interrupt, report and stop the child. The words "out
#' of budget" keep P06 from retrying the turn as a transient failure.
#' @noRd
pcli_claude_timeout = function(s) {
  if (s$done) return(invisible(NULL))
  if (pcli_aborted(s)) {
    s$done = TRUE
    s$state$turn_open = FALSE
    return(invisible(NULL))
  }
  secs = pcli_turn_seconds()
  pcli_send(s$opts, pcli_control_request(s$state, list(subtype = "interrupt")))
  pcli_fail(s, "timeout", paste0("The claude CLI turn is out of budget: it ran past the ",
                                "per-turn limit of ", secs, " s (option gptr.cli_turn_timeout)."))
  pcli_stop_child(s$state, wait_ack = FALSE)
  invisible(NULL)
}

#' parse(): the normaliser of one claude turn (contract 8.1, 8.5)
#' @noRd
pcli_claude_parse = function(model, opts) {
  s = pcli_turn_new(model, opts)
  s$inner = NULL
  s$map = integer()
  pcli_wire_log(s, "start")
  pcli_turn_timer(s, function() pcli_claude_timeout(s))

  push = function(ev) {
    obj = ev[["obj"]] %||% pcli_parse_line(ev[["data"]])
    if (!is.list(obj)) return(s$done)
    type = obj[["type"]] %||% ""
    if (identical(type, "control_response")) {
      pcli_claude_ack(obj, s$state)
      return(s$done)
    }
    if (identical(type, "control_request")) {
      if (s$done || pcli_aborted(s)) pcli_claude_refuse(obj, s) else pcli_claude_control(obj, s)
      return(s$done)
    }
    if (s$done) return(TRUE)
    if (pcli_aborted(s)) {
      if (identical(type, "result")) {
        pcli_fail(s, "aborted", "The run was aborted.", reason = "aborted",
                 usage = pcli_claude_usage(obj, s$state))
      }
      return(s$done)
    }
    if (identical(type, "system")) {
      pcli_claude_system(obj, s)
    } else if (identical(type, "rate_limit_event")) {
      pcli_plan_set(model$provider, obj[["rate_limit_info"]] %||% list())
    } else if (identical(type, "stream_event")) {
      if (is.null(obj[["parent_tool_use_id"]])) pcli_claude_stream(obj[["event"]], s)
    } else if (identical(type, "result")) {
      pcli_claude_result(obj, s)
    }
    s$done
  }

  finish = function() {
    if (!s$done) {
      if (pcli_aborted(s)) {
        pcli_fail(s, "aborted", "The run was aborted.", reason = "aborted")
      } else {
        pcli_fail(s, "provider", "The claude CLI exited before the end of the turn.")
      }
    }
    s$msg
  }

  fail = function(cnd) {
    if (!s$done) {
      aborted = pcli_aborted(s)
      cls = sub("^gptr_error_", "", class(cnd)[[1L]])
      pcli_fail(s, if (aborted) "aborted" else cls, conditionMessage(cnd),
               reason = if (aborted) "aborted" else "error",
               status = cnd[["status"]] %||% NA_integer_)
    }
    s$msg
  }

  message = function() s$msg %||% pcli_message(s)

  list(push = push, finish = finish, fail = fail, message = message)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-claude")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 105 ]`

- [ ] **Step 5: Commit**

```bash
git add R/cli-claude.R tests/testthat/test-cli-claude.R tests/testthat/fixtures/cli/local-fake-cli.R tests/testthat/fixtures/cli/claude-call2.ndjson tests/testthat/fixtures/cli/claude-apikey.ndjson tests/testthat/fixtures/cli/claude-hang.ndjson
git commit -m "feat(cli): cli-claude normaliser with the control protocol and billing check"
```

---

### Task 7: The cli-codex adapter

**Files:**
- Create: `R/cli-codex.R`
- Create: `tests/testthat/fixtures/cli/codex-call1.jsonl`, `codex-text.jsonl`, `codex-mcp.jsonl`, `codex-many.jsonl`, `codex-hang.jsonl`
- Modify: `tests/testthat/fixtures/cli/local-fake-cli.R` (append)
- Test: `tests/testthat/test-cli-codex.R` (create)

**Interfaces:**
- Consumes: Tasks 1-4; `ext_service_has(name)`, `ext_service_get(name)` (P01) for `mcp.serve_ensure` `function(session) <gptr_mcp_handle>` (P18; `session` is the `gptr_session` object, which P18's `mcp_serve_ensure()` checks with `check_class()`, as P19's `backend_cli_start()` passes it; handle fields `url`, `port`, `token_env`, `config`, `stop()`, 04 §5.11; P20 reads the token from `h$config$codex$env[[h$token_env]]`, the shape P18 produces); in tests `gptr_register(spec)`, `gptr_spec("service", name, fun = )` (P02; a user-rank `service` record replaces P18's built-in for one test, IC-34); `reactor_served(run, served = TRUE)` (P04); `hash_file(path)`, `project_root()`, `path_rel()`, `path_norm()`, `json_verbatim(text)`, `json_obj()`, `gptr_warn()` (P01); `usage_new(...)` (P05).
- Produces: `pcli_codex_mcp_args(port)`, `pcli_codex_args(model_id, wd, sandbox, port = NULL, resume = NULL)` (the IC-65 argv and resume form), `pcli_codex_windows_ready(path)`, `pcli_codex_sandbox(mode, path)` (mapping and Windows fallback with `gptr_warning_cli_sandbox`), `pcli_codex_files_only(why)`, `pcli_codex_env(h)` -> `c(GPTR_MCP_TOKEN = <token>)` or `character()`, `pcli_codex_ensure(session)` (called by Task 8's `request_params` hook with the session object: `mcp.serve_ensure(session)`, then the URL, port and this session's token kept per session id in `pcli_cache$mcp`, or `list(error = <why>)`), `pcli_codex_forget(session)` (Task 9's `session_shutdown` hook), `pcli_codex_mcp(opts)` (the record of `opts$session`, else `NULL` with the files-only notice), `pcli_codex_prompt(context, fresh, provider = NULL)`, `pcli_control_paths(root)`, `pcli_control_hash(root = project_root())`, `pcli_control_changed(before, after)`, `pcli_codex_cap(par)`, `pcli_codex_build(model, context, opts)` (04 §8.1 `build`; `close_stdin = TRUE`), `pcli_codex_tool_kinds`, `pcli_num(x)`, `pcli_codex_usage(u)`, `pcli_codex_files(item)`, `pcli_codex_tool_name(item)`, `pcli_codex_tool(s, item, phase)`, `pcli_codex_after(s)` (changed control files, without signalling), `pcli_codex_warn(changed)`, `pcli_codex_error(s, class, text, reason = "error", kill = FALSE, usage = NULL)`, `pcli_codex_item(s, item)`, `pcli_codex_event(obj, s)`, `pcli_codex_timeout(s)`, `pcli_codex_parse(model, opts)` (04 §8.1 `parse`). Adapter state fields: `cli_api` (`"cli-codex"`), `codex_thread`, `codex_sandbox`, `codex_cap`, `codex_control`, `served_run`. Test support: `stub_mcp_handle(port = 54321L, token = "tok-test-0123456789")`, `local_mcp_stub(handle = stub_mcp_handle(), .env = parent.frame())`.

The exec driver follows report 08 §5.1 (verified) with its verification log: `--ignore-user-config` keeps the user's MCP servers and settings out while auth still comes from `CODEX_HOME` (item 14), `exec resume` rejects `-s` and `-C` (item 16), and the prompt goes on stdin through a writer that loops until every byte is written (item 54: `write_input()` truncated at 8 KB; P04's `write_all()` does this, and P05 closes stdin after it with `write_close()` for `close_stdin = TRUE`). The prompt is the send object `json_verbatim(<text>)`, which `json_encode()` writes unchanged. The event schema is 08 §3.9 (`codex-rs/exec/src/exec_events.rs`): `input_tokens` includes `cached_input_tokens` (OpenAI semantics), so the usage record keeps the uncached part as `input`. The informational `tool_execution_*` events of 04 §8.5 are emitted for tool items; codex tool items count against the run's turn cap (IC-65: "Codex has no turn cap flag"). A top-level `error` event is noted, not terminal: the verified driver of 08 §5.1 only records it and decides at `turn.failed` or the exit, and ending the turn there would leave a Codex that is still working unsupervised (its turn would no longer be open for Task 9's `agent_end` hook); `turn.failed` ends the turn, and an exit without `turn.completed` reports the last error. The server and token come from `mcp.serve_ensure`, which takes the `gptr_session` object (P18 checks its class), while an adapter holds only ids (04 §8.1 `opts$session`): builtin:cli's `request_params` hook (Task 8), which receives the session as `ctx$session`, calls `pcli_codex_ensure(ctx$session)` before every codex request and keeps the URL, port and this session's token (strings only, never the handle, whose `stop()` would keep the session alive) for `pcli_codex_mcp(opts)`. Without a token for the session (no httpuv/later/openssl, no P18 service, or a request that did not pass the hook) the MCP overrides are left out, because `required=true` would make Codex fail at startup, and a one-time notice says the route works on files only. Changed control files are reported with `gptr_warning_cli_sandbox` only after the terminal event (04 §8.1: normalisers signal nothing before their terminal event; a warning turned into an error by `options(warn = 2)` then cannot fail a completed exec). The Windows sandbox probe runs `codex sandbox windows cmd.exe /d /c exit 0` once per command (08 §6.2 names the setup requirement, not the probe command; see the self-review). `codex-call1.jsonl` is the redacted live capture of 08 §5.2; the other transcripts are constructed in the 08 §3.9 shapes (`$THREAD`, `$TOOL_TEXT` and `$PROMPT_BYTES` are filled in by the fake CLI).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/cli/codex-call1.jsonl`:

```text
{"type":"thread.started","thread_id":"<UUID>"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'echo gptr-probe'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'echo gptr-probe'","aggregated_output":"gptr-probe\n","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"pong"}}
{"type":"turn.completed","usage":{"input_tokens":38544,"cached_input_tokens":30208,"cache_write_input_tokens":0,"output_tokens":35,"reasoning_output_tokens":0}}
```

Create `tests/testthat/fixtures/cli/codex-text.jsonl`:

```text
{"type":"thread.started","thread_id":"$THREAD"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"Reading the prompt."}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Hello from the fake codex CLI ($PROMPT_BYTES prompt bytes)."}}
{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"cache_write_input_tokens":0,"output_tokens":122,"reasoning_output_tokens":0}}
```

Create `tests/testthat/fixtures/cli/codex-mcp.jsonl`:

```text
{"type":"thread.started","thread_id":"$THREAD"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item_0","type":"mcp_tool_call","server":"gptr","tool":"r","arguments":{"code":"live_answer = sum(1:10); live_answer"},"result":null,"error":null,"status":"in_progress"}}
{"fake":"mcp_call","tool":"r","arguments":{"code":"live_answer = sum(1:10); live_answer"}}
{"type":"item.completed","item":{"id":"item_0","type":"mcp_tool_call","server":"gptr","tool":"r","arguments":{"code":"live_answer = sum(1:10); live_answer"},"result":{"content":[{"type":"text","text":"$TOOL_TEXT"}],"structured_content":null},"error":null,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"R said: $TOOL_TEXT"}}
{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"cache_write_input_tokens":0,"output_tokens":122,"reasoning_output_tokens":0}}
```

Create `tests/testthat/fixtures/cli/codex-many.jsonl`:

```text
{"type":"thread.started","thread_id":"$THREAD"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/sh -lc true","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/sh -lc true","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_3","type":"command_execution","command":"/bin/sh -lc true","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_4","type":"command_execution","command":"/bin/sh -lc true","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_9","type":"agent_message","text":"Ran four commands."}}
{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"cache_write_input_tokens":0,"output_tokens":122,"reasoning_output_tokens":0}}
```

Create `tests/testthat/fixtures/cli/codex-hang.jsonl`:

```text
{"type":"thread.started","thread_id":"$THREAD"}
{"type":"turn.started"}
{"fake":"hang"}
```

Append to `tests/testthat/fixtures/cli/local-fake-cli.R`:

```r
# A gptr_mcp_handle stand-in (04 5.11 fields) whose token lives in its Codex snippet
stub_mcp_handle = function(port = 54321L, token = "tok-test-0123456789") {
  h = new.env(parent = emptyenv())
  h$url = paste0("http://127.0.0.1:", port, "/mcp")
  h$port = port
  h$token_env = "GPTR_MCP_TOKEN"
  h$config = list(codex = list(env = c(GPTR_MCP_TOKEN = token)))
  h$stop = function() invisible(NULL)
  h
}

# Replace the mcp.serve_ensure service for the calling test with one returning `handle`
# (a `service` registry record at user rank wins over P18's built-in, IC-34)
local_mcp_stub = function(handle = stub_mcp_handle(), .env = parent.frame()) {
  off = gptr_register(gptr_spec("service", "mcp.serve_ensure", fun = function(session) handle))
  withr::defer(off(), envir = .env)
  invisible(handle)
}
```

Create `tests/testthat/test-cli-codex.R`:

```r
# tests/testthat/test-cli-codex.R -- the cli-codex adapter, the codex routes end to end and the
# CLI leg of INFRA-16 (P20)

source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# The MCP overrides of contract 8.5 / IC-65, verbatim
codex_mcp_8_5 = function(port) {
  c("-c", paste0("mcp_servers.gptr.url=http://127.0.0.1:", port, "/mcp"),
    "-c", "mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN",
    "-c", "mcp_servers.gptr.default_tools_approval_mode=\"approve\"",
    "-c", "mcp_servers.gptr.required=true",
    "-c", "mcp_servers.gptr.tool_timeout_sec=3600")
}

# ---- the cli-codex adapter (Task 7) -------------------------------------------------------------

test_that("the codex argv follows IC-65, and the resume form uses -c sandbox_mode=", {
  expect_identical(pcli_codex_args("gpt-6-sol", "/w", "read-only", port = 54321L),
                   c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
                     "gpt-6-sol", "-C", "/w", codex_mcp_8_5(54321L), "--sandbox", "read-only",
                     "-"))
  resumed = pcli_codex_args("gpt-6-sol", "/w", "workspace-write", port = 54321L,
                           resume = "0199a213-thread")
  expect_identical(resumed,
                   c("exec", "resume", "0199a213-thread", "--json", "--ignore-user-config",
                     "--skip-git-repo-check", "-m", "gpt-6-sol", codex_mcp_8_5(54321L), "-c",
                     "sandbox_mode=workspace-write", "-"))
  expect_false(any(c("-C", "-s", "--sandbox") %in% resumed))
  expect_identical(pcli_codex_args("gpt-6-sol", "/w", "read-only"),
                   c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
                     "gpt-6-sol", "-C", "/w", "--sandbox", "read-only", "-"))
})

test_that("plan, manual and edits run read-only; auto workspace-write; Windows falls back", {
  local_mocked_bindings(pcli_is_windows = function() FALSE)
  for (mode in c("plan", "manual", "edits")) {
    expect_identical(pcli_codex_sandbox(mode, "codex"), "read-only")
  }
  expect_identical(pcli_codex_sandbox("auto", "codex"), "workspace-write")
  local_mocked_bindings(pcli_is_windows = function() TRUE,
                        pcli_codex_windows_ready = function(path) FALSE)
  w = expect_warning(pcli_codex_sandbox("auto", "codex"), class = "gptr_warning_cli_sandbox")
  expect_match(conditionMessage(w), "runs read-only", fixed = TRUE)
})

test_that("the prompt carries instructions and history on a fresh thread only", {
  msgs = list(msg_user("first"),
              msg_assistant(list(block_text("one")), api = "fake", provider = "fake",
                            model = "fake-1"),
              msg_user("second"))
  ctx = list(system = list(t0 = "You are gptr.", t1 = ""), messages = msgs)
  fresh = pcli_codex_prompt(ctx, fresh = TRUE)
  expect_match(fresh, "^<gptr_instructions>\nYou are gptr.\n</gptr_instructions>\n\n")
  expect_match(fresh, "Assistant: one", fixed = TRUE)
  expect_match(fresh, "\n\nsecond$")
  expect_identical(pcli_codex_prompt(ctx, fresh = FALSE, provider = "fake"), "second")
  foreign = pcli_codex_prompt(ctx, fresh = FALSE, provider = "fakecodex")
  expect_match(foreign, "^<conversation_history>\n")
  expect_match(foreign, "Assistant: one", fixed = TRUE)
  expect_false(grepl("<gptr_instructions>", foreign, fixed = TRUE))
})

test_that("the MCP record of a session reaches only its own codex exec", {
  local_mcp_stub(stub_mcp_handle(port = 54999L, token = "tok-session-0123"))
  rec = pcli_codex_ensure(list(id = "s0123456789"))
  withr::defer(pcli_codex_forget("s0123456789"))
  expect_identical(rec$port, 54999L)
  h = pcli_codex_mcp(stub_opts())
  expect_identical(h$port, 54999L)
  expect_identical(pcli_codex_env(h), c(GPTR_MCP_TOKEN = "tok-session-0123"))
  expect_null(pcli_codex_mcp(stub_opts(session = "s9999999999")))
  expect_null(pcli_codex_ensure(list(id = NULL)))
  pcli_codex_forget("s0123456789")
  expect_null(pcli_codex_mcp(stub_opts()))
})

test_that("a tokenless MCP server leaves the exec on files only", {
  h = stub_mcp_handle()
  h$config = list()
  local_mcp_stub(h)
  rec = pcli_codex_ensure(list(id = "s0123456789"))
  withr::defer(pcli_codex_forget("s0123456789"))
  expect_match(rec$error, "no token", fixed = TRUE)
  expect_null(pcli_codex_mcp(stub_opts()))
})

test_that("build() starts one exec per turn with the MCP overrides and the token in env", {
  local_fake_cli_path("codex", "text")
  seen = new.env()
  local_mocked_bindings(
    pcli_probe = function(path) list(resume = TRUE),
    pcli_notice = function(cli) invisible(NULL),
    pcli_codex_mcp = function(opts) stub_mcp_handle(),
    reactor_served = function(run, served = TRUE) {
      seen$calls = c(seen$calls, paste(run, served))
      invisible(run)
    }
  )
  opts = stub_opts(run = "r0000000002")
  ctx = list(system = list(t0 = "T0", t1 = ""), request_id = "q000000000004",
             messages = list(msg_user("Summarise x")),
             params = list(cli_mode = "edits", cli_budget = list(turns = 4)))
  spec = pcli_codex_build(stub_model("codex"), ctx, opts)
  args = spec$start$args
  tail = c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m", "gpt-6-sol",
           "-C", path_norm(getwd()), codex_mcp_8_5(54321L), "--sandbox", "read-only", "-")
  expect_identical(args[(length(args) - length(tail) + 1L):length(args)], tail)
  expect_identical(spec$start$env, c(GPTR_MCP_TOKEN = "tok-test-0123456789"))
  expect_identical(spec$start$env_profile, "cli-codex")
  expect_true(spec$close_stdin)
  expect_s3_class(spec$send[[1]], "json")
  expect_match(spec$send[[1]], "Summarise x$")
  expect_identical(opts$state$codex_cap, 4L)
  expect_identical(seen$calls, "r0000000002 TRUE")
  opts$state$codex_thread = "0199a213-thread"
  spec2 = pcli_codex_build(stub_model("codex"), ctx, opts)
  i = match("exec", spec2$start$args)
  expect_identical(spec2$start$args[i + 0:2], c("exec", "resume", "0199a213-thread"))
  expect_identical(as.character(spec2$send[[1]]), "Summarise x")
  pcli_untrack("s0123456789")
})

test_that("without a token for this session the exec runs on files only", {
  local_fake_cli_path("codex", "text")
  local_mocked_bindings(pcli_probe = function(path) list(resume = FALSE),
                        pcli_notice = function(cli) invisible(NULL),
                        pcli_codex_mcp = function(opts) NULL)
  spec = pcli_codex_build(stub_model("codex"), list(messages = list(msg_user("hi"))), stub_opts())
  expect_false(any(grepl("mcp_servers", spec$start$args, fixed = TRUE)))
  expect_identical(spec$start$env, character())
  pcli_untrack("s0123456789")
})

test_that("the call-1 capture: informational tool events, the answer and the usage", {
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(feed_fixture(n, "codex-call1.jsonl"))
  expect_identical(event_types(opts),
                   c("start", "tool_execution_start", "tool_execution_end", "text_start",
                     "text_delta", "text_end", "done"))
  expect_identical(opts$log$events[[2]]$tool_name, "codex_shell")
  expect_false(opts$log$events[[3]]$is_error)
  msg = n$message()
  expect_identical(msg_text(msg), "pong")
  expect_identical(msg$route, "plan-cli")
  expect_identical(msg$raw_stop_reason, "completed")
  expect_equal(c(msg$usage$input, msg$usage$cache_read, msg$usage$output), c(8336, 30208, 35))
  expect_identical(opts$state$codex_thread, "<UUID>")
})

test_that("gptr's own MCP calls are reported, reasoning becomes thinking", {
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(feed_fixture(n, "codex-mcp.jsonl"))
  starts = Filter(function(e) identical(e$type, "tool_execution_start"), opts$log$events)
  expect_identical(starts[[1]]$tool_name, "mcp__gptr__r")
  expect_identical(starts[[1]]$input$code, "live_answer = sum(1:10); live_answer")
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  feed_fixture(n2, "codex-text.jsonl")
  expect_identical(vapply(n2$message()$content, function(b) b$type, ""), c("thinking", "text"))
})

test_that("Codex is stopped at the run's turn cap", {
  stopped = new.env()
  stopped$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    stopped$n = stopped$n + 1L
    invisible(TRUE)
  })
  opts = stub_opts()
  opts$state$codex_cap = 2L
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  expect_true(feed_fixture(n, "codex-many.jsonl"))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$type, "error")
  expect_identical(ev$error$class, "max_turns")
  expect_match(ev$message$error_message, "turn cap of this run (2 tool steps)", fixed = TRUE)
  expect_identical(stopped$n, 1L)
})

test_that("turn.failed, a missing turn.completed and the wall clock end the exec", {
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  push_obj(n, list(type = "turn.started"))
  push_obj(n, list(type = "turn.failed", error = list(message = "usage limit reached")))
  ev = opts$log$events[[length(opts$log$events)]]
  expect_identical(ev$error$class, "provider")
  expect_match(ev$message$error_message, "usage limit reached", fixed = TRUE)
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  feed_fixture(n2, "codex-hang.jsonl")
  expect_match(n2$finish()$error_message, "exited before completing the turn", fixed = TRUE)
  local_gptr_options(cli_turn_timeout = 0.3)
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    invisible(TRUE)
  })
  opts3 = stub_opts()
  n3 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts3)
  expect_true(reactor_pump(until = function() length(opts3$log$events) > 0L, timeout = 5))
  ev3 = opts3$log$events[[length(opts3$log$events)]]
  expect_identical(ev3$error$class, "timeout")
  expect_match(ev3$message$error_message, "out of budget", fixed = TRUE)
})

test_that("a Codex error event is noted, not terminal; turn.failed and the exit report it", {
  opts = stub_opts()
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  push_obj(n, list(type = "turn.started"))
  expect_false(push_obj(n, list(type = "error", message = "Reconnecting... 1/5")))
  push_obj(n, list(type = "item.completed",
                   item = list(id = "item_1", type = "agent_message", text = "ok")))
  expect_true(push_obj(n, list(type = "turn.completed", usage = list(input_tokens = 5L))))
  expect_identical(event_types(opts)[length(opts$log$events)], "done")
  opts2 = stub_opts()
  n2 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts2)
  push_obj(n2, list(type = "error", message = "stream disconnected"))
  expect_match(n2$finish()$error_message, "Its last error: stream disconnected", fixed = TRUE)
  opts3 = stub_opts()
  n3 = local_normaliser(pcli_codex_parse, stub_model("codex"), opts3)
  push_obj(n3, list(type = "error", message = "usage limit reached"))
  expect_true(push_obj(n3, list(type = "turn.failed", error = json_obj())))
  expect_match(n3$message()$error_message, "Codex reported an error: usage limit reached",
               fixed = TRUE)
})

test_that("a workspace-write exec that changes control files is reported after it ends", {
  root = local_project(files = list(".gptr/settings.json" = "{}"))
  opts = stub_opts()
  opts$state$codex_sandbox = "workspace-write"
  opts$state$codex_control = pcli_control_hash(root)
  n = local_normaliser(pcli_codex_parse, stub_model("codex"), opts)
  writeLines('{"permissions": {"allow": ["r(*)"]}}', file.path(root, ".gptr", "settings.json"))
  seen = new.env()
  seen$events = NA_integer_
  withCallingHandlers(feed_fixture(n, "codex-text.jsonl"),
                      gptr_warning_cli_sandbox = function(w) {
                        seen$events = length(opts$log$events)
                        seen$text = conditionMessage(w)
                        invokeRestart("muffleWarning")
                      })
  expect_match(seen$text, ".gptr/settings.json", fixed = TRUE)
  expect_identical(event_types(opts)[[seen$events]], "done")
  expect_length(opts$log$events, seen$events)
  expect_null(opts$state$codex_control)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-codex")'`

Expected: `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 0 ]`; the thirteen tests error with ``could not find function "pcli_codex_args"``, ``could not find function "pcli_codex_sandbox"``, ``could not find function "pcli_codex_prompt"``, ``could not find function "pcli_codex_ensure"``, ``Can't find binding for `pcli_codex_mcp` ``, ``could not find function "pcli_codex_parse"`` and ``could not find function "pcli_control_hash"``.

- [ ] **Step 3: Write the implementation**

Create `R/cli-codex.R`:

```r
# The cli-codex adapter (P20): one `codex exec --json --ignore-user-config ... -` per turn with the
# prompt on stdin, gptr's live R session through gptr_mcp_serve() (the mcp.serve_ensure service
# of P18, a token bound to this session, IC-58), the sandbox mapping with control-file hashing,
# the turn counter and the per-exec wall clock (architecture 8.3; contract 8.5, IC-65). L1: L0
# helpers, the injected opts and declared services only (IC-33). Adapted from the verified exec
# driver of report 08 section 5.1 (prompt on stdin through a looping writer, JSONL events of
# section 3.9) with the fixes of its verification log (items 14, 16, 54).

#' The `-c` overrides pointing Codex at gptr's MCP server (contract 8.5, verbatim)
#' @noRd
pcli_codex_mcp_args = function(port) {
  c("-c", paste0("mcp_servers.gptr.url=http://127.0.0.1:", as.integer(port), "/mcp"),
    "-c", "mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN",
    "-c", "mcp_servers.gptr.default_tools_approval_mode=\"approve\"",
    "-c", "mcp_servers.gptr.required=true",
    "-c", "mcp_servers.gptr.tool_timeout_sec=3600")
}

#' The codex argv of IC-65: a new exec, or `exec resume` (which rejects -s and -C, so the sandbox
#' travels as `-c sandbox_mode=`)
#' @noRd
pcli_codex_args = function(model_id, wd, sandbox, port = NULL, resume = NULL) {
  mcp = if (is.null(port)) character() else pcli_codex_mcp_args(port)
  if (is.null(resume)) {
    return(c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m", model_id,
             "-C", wd, mcp, "--sandbox", sandbox, "-"))
  }
  c("exec", "resume", resume, "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
    model_id, mcp, "-c", paste0("sandbox_mode=", sandbox), "-")
}

#' Is Codex's native Windows sandbox ready? `codex sandbox windows` runs a no-op command in it;
#' the answer is cached per command (08 6.2)
#' @noRd
pcli_codex_windows_ready = function(path) {
  key = paste("windows-sandbox", pcli_cache_key(path))
  cache = pcli_cache$probe %||% list()
  hit = cache[[key]]
  if (is.null(hit)) {
    res = tryCatch(pcli_run(path, c("sandbox", "windows", "cmd.exe", "/d", "/c", "exit", "0"),
                           timeout = 60), error = function(e) NULL)
    hit = !is.null(res) && !isTRUE(res$timed_out) && identical(as.integer(res$status), 0L)
    cache[[key]] = hit
    pcli_cache$probe = cache
  }
  hit
}

#' The sandbox of a permission mode: plan, manual and edits -> read-only (file changes go through
#' gptr's gated write/edit over MCP), auto -> workspace-write; on native Windows read-only with a
#' warning while the sandbox is not ready (IC-65)
#' @noRd
pcli_codex_sandbox = function(mode, path) {
  if (!identical(mode, "auto")) return("read-only")
  if (pcli_is_windows() && !pcli_codex_windows_ready(path)) {
    gptr_warn(paste0("Codex's Windows sandbox is not ready, so the codex route runs read-only. ",
                     "Set the sandbox up with the Codex CLI to let Codex edit files itself."),
              "cli_sandbox", .once = "cli_sandbox_windows")
    return("read-only")
  }
  "workspace-write"
}

#' Say once that Codex works on files only (no MCP server: httpuv, later or openssl missing)
#' @noRd
pcli_codex_files_only = function(why) {
  gptr_inform(paste0("Codex cannot evaluate R in this session (", why, "); the codex route ",
                     "works on files only. Install httpuv, later and openssl for live R access."),
              "notice", .once = "cli_codex_files_only")
  NULL
}

#' The child-environment addition of the handle: GPTR_MCP_TOKEN, taken from its Codex client
#' snippet (`$config$codex$env`, 04 5.11: the token lives only in child environments and in
#' snippets); empty when the handle has none
#' @noRd
pcli_codex_env = function(h) {
  if (is.null(h)) return(character())
  name = h$token_env %||% "GPTR_MCP_TOKEN"
  env = h$config$codex$env
  tok = if (is.null(env)) NULL else env[[name]]
  ok = is.character(tok) && length(tok) == 1L && !is.na(tok) && nzchar(tok)
  if (ok) c(GPTR_MCP_TOKEN = tok) else character()
}

#' Ensure gptr's MCP server for a session and keep what its next codex exec needs: the URL, the
#' port and this session's bearer token (mcp.serve_ensure, IC-58)
#'
#' Called by builtin:cli's `request_params` hook with the session object, which the service
#' takes (P18 checks its class) while the adapter holds only ids (contract 8.1). Only strings
#' are kept, per session id, never the handle (its stop() would keep the session alive);
#' session_shutdown forgets them (pcli_codex_forget()).
#' @param session a gptr_session (anything with an `$id`).
#' @return invisible(the record kept), or invisible(NULL) without a session id.
#' @noRd
pcli_codex_ensure = function(session) {
  id = tryCatch(session$id, error = function(e) NULL)
  ok = is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)
  if (!ok) return(invisible(NULL))
  rec = if (!ext_service_has("mcp.serve_ensure")) {
    list(error = "gptr's MCP server is not loaded")
  } else {
    h = tryCatch(ext_service_get("mcp.serve_ensure")(session), error = function(e) e)
    if (inherits(h, "condition")) {
      list(error = conditionMessage(h))
    } else if (!length(pcli_codex_env(h))) {
      list(error = "the MCP server gave no token for this session")
    } else {
      list(url = h$url, port = h$port, token_env = "GPTR_MCP_TOKEN",
           config = list(codex = list(env = pcli_codex_env(h))))
    }
  }
  tab = pcli_cache$mcp %||% list()
  tab[[id]] = rec
  pcli_cache$mcp = tab
  invisible(rec)
}

#' Forget the MCP record of a session (its session_shutdown)
#' @noRd
pcli_codex_forget = function(session) {
  tab = pcli_cache$mcp %||% list()
  if (is.character(session) && length(session) == 1L && !is.na(session)) tab[[session]] = NULL
  pcli_cache$mcp = tab
  invisible(NULL)
}

#' The MCP record of this request's session (pcli_codex_ensure()), or NULL with the one-time
#' files-only notice
#' @noRd
pcli_codex_mcp = function(opts) {
  sid = opts[["session"]]
  ok = is.character(sid) && length(sid) == 1L && !is.na(sid) && nzchar(sid)
  rec = if (ok) (pcli_cache$mcp %||% list())[[sid]] else NULL
  if (is.null(rec)) {
    return(pcli_codex_files_only("gptr's MCP server was not started for this session"))
  }
  if (!is.null(rec$error)) return(pcli_codex_files_only(rec$error))
  rec
}

#' The stdin prompt: gptr's frozen instructions and the history on a fresh thread; on a resumed
#' thread the turns it has not seen (another model may have answered them, pcli_unseen()); the
#' new input always
#' @noRd
pcli_codex_prompt = function(context, fresh, provider = NULL) {
  parts = pcli_split(context[["messages"]] %||% list())
  input = pcli_input_text(parts$input)
  if (!fresh) return(paste0(pcli_history_text(pcli_unseen(parts$prior, provider)), input))
  sys = pcli_system_text(context)
  pre = if (nzchar(sys)) paste0("<gptr_instructions>\n", sys, "\n</gptr_instructions>\n\n") else ""
  paste0(pre, pcli_history_text(parts$prior), input)
}

#' gptr's control files inside a project (IC-54), hashed around a workspace-write exec
#' @noRd
pcli_control_paths = function(root) {
  g = file.path(root, ".gptr")
  fixed = c(list.files(g, pattern = "^settings.*[.]json$", full.names = TRUE),
            file.path(g, c("mcp.json", "SYSTEM.md", "APPEND_SYSTEM.md")),
            file.path(root, c(".Rprofile", "Rprofile.site", "Renviron.site")),
            file.path(root, ".git", "config"))
  dirs = c(file.path(g, c("extensions", "plugins", "agents")), file.path(root, ".git", "hooks"))
  dirs = dirs[dir.exists(dirs)]
  inside = unlist(lapply(dirs, list.files, recursive = TRUE, full.names = TRUE,
                         all.files = TRUE, no.. = TRUE), use.names = FALSE)
  paths = unique(c(fixed[file.exists(fixed) & !dir.exists(fixed)], inside))
  sort(path_norm(paths), method = "radix")
}

#' Content hashes of the control files, named by path
#' @noRd
pcli_control_hash = function(root = project_root()) {
  p = pcli_control_paths(root)
  if (!length(p)) return(stats::setNames(character(), character()))
  stats::setNames(as.character(hash_file(p)), p)
}

#' Control files added, removed or changed between two hash sets
#' @noRd
pcli_control_changed = function(before, after) {
  both = intersect(names(before), names(after))
  changed = c(setdiff(names(after), names(before)), setdiff(names(before), names(after)),
              both[before[both] != after[both]])
  sort(unique(changed), method = "radix")
}

#' The turn cap of an exec: the run's remaining turns, else gptr.max_turns (IC-65: Codex has no
#' turn-cap flag)
#' @noRd
pcli_codex_cap = function(par) {
  if (!is.null(par$turns)) return(max(1L, as.integer(par$turns)))
  as.integer(gptr_opt("max_turns") %||% 50L)
}

#' build(): one codex exec per turn, the prompt on stdin, then stdin closed (contract 8.1, 8.5)
#' @noRd
pcli_codex_build = function(model, context, opts) {
  state = pcli_state(opts)
  state$pcli_request_id = context[["request_id"]]
  pcli_track(opts[["session"]], state)
  path = pcli_find("codex")
  probe = pcli_probe(path)
  pcli_notice("codex")
  par = pcli_params(context)
  sandbox = pcli_codex_sandbox(par$mode, path)
  h = pcli_codex_mcp(opts)
  env = pcli_codex_env(h)
  if (!is.null(h) && !length(env)) {
    h = pcli_codex_files_only("the MCP server gave no token for this session")
  }
  port = if (is.null(h)) NULL else h$port
  resume = if (isTRUE(probe$resume)) state$codex_thread else NULL
  wd = path_norm(getwd())
  args = pcli_codex_args(pcli_model_id(model), wd, sandbox, port = port, resume = resume)
  state$cli_api = "cli-codex"
  state$codex_sandbox = sandbox
  state$codex_cap = pcli_codex_cap(par)
  state$codex_control = NULL
  if (identical(sandbox, "workspace-write")) state$codex_control = pcli_control_hash(project_root())
  run = opts[["run"]]
  if (!is.null(port) && is.character(run) && length(run) == 1L) {
    reactor_served(run, TRUE)
    state$served_run = run
  }
  list(start = list(command = path[[1L]], args = c(as.character(path[-1L]), args),
                    env_profile = "cli-codex", env = env, wd = wd),
       send = list(json_verbatim(pcli_codex_prompt(context, fresh = is.null(resume),
                                                  provider = model$provider))),
       close_stdin = TRUE)
}

#' Item types that are Codex tool steps (counted against the turn cap)
#' @noRd
pcli_codex_tool_kinds = c("mcp_tool_call", "command_execution", "file_change", "web_search",
                         "collab_tool_call")

#' A non-negative number from a usage field (0 when absent)
#' @noRd
pcli_num = function(x) {
  v = suppressWarnings(as.numeric(x %||% 0)[1L])
  if (is.na(v)) 0 else v
}

#' Usage of turn.completed: input_tokens includes the cached ones (OpenAI semantics, 08 3.9);
#' plan usage has no price
#' @noRd
pcli_codex_usage = function(u) {
  input = pcli_num(u[["input_tokens"]])
  cached = pcli_num(u[["cached_input_tokens"]])
  write = pcli_num(u[["cache_write_input_tokens"]])
  usage_new(input = max(0, input - cached - write), output = pcli_num(u[["output_tokens"]]),
            cache_read = cached, cache_write_5m = write, cache_write_1h = 0,
            reasoning = pcli_num(u[["reasoning_output_tokens"]]))
}

#' Paths of a file_change item
#' @noRd
pcli_codex_files = function(item) {
  vapply(item[["changes"]] %||% list(), function(ch) ch[["path"]] %||% "", "")
}

#' Informational tool name of a Codex item
#' @noRd
pcli_codex_tool_name = function(item) {
  switch(item[["type"]] %||% "",
         mcp_tool_call = paste0("mcp__", item[["server"]] %||% "?", "__", item[["tool"]] %||% "?"),
         command_execution = "codex_shell", file_change = "codex_file_change",
         web_search = "codex_web_search", collab_tool_call = "codex_agent", "codex_item")
}

#' Emit the informational tool_execution_start/_end events of a Codex tool item (contract 8.5)
#' @noRd
pcli_codex_tool = function(s, item, phase) {
  kind = item[["type"]] %||% ""
  if (!(kind %in% pcli_codex_tool_kinds)) return(invisible(FALSE))
  emit = s$opts[["emit"]]
  if (!is.function(emit)) return(invisible(FALSE))
  id = paste0("codex_", item[["id"]] %||% "item")
  name = pcli_codex_tool_name(item)
  if (!(id %in% s$open_tools)) {
    s$open_tools = c(s$open_tools, id)
    input = switch(kind, command_execution = list(command = item[["command"]] %||% ""),
                   mcp_tool_call = item[["arguments"]] %||% json_obj(),
                   file_change = list(paths = I(pcli_codex_files(item))),
                   web_search = list(query = item[["query"]] %||% ""), json_obj())
    emit(ev_new("tool_execution_start", tool_call_id = id, tool_name = name, input = input))
  }
  if (identical(phase, "end")) {
    failed = (item[["status"]] %||% "") %in% c("failed", "declined") ||
      !is.null(item[["error"]])
    emit(ev_new("tool_execution_end", tool_call_id = id, tool_name = name, is_error = failed,
                elapsed = NA_real_,
                details = list(status = item[["status"]] %||% NA_character_,
                               files = I(pcli_codex_files(item)))))
  }
  invisible(TRUE)
}

#' After a workspace-write exec: the control files it added, removed or changed (IC-54, IC-65);
#' nothing is signalled here, the caller warns after the terminal event (pcli_codex_warn())
#' @noRd
pcli_codex_after = function(s) {
  before = s$state$codex_control
  s$state$codex_control = NULL
  if (!identical(s$sandbox, "workspace-write") || is.null(before)) return(character())
  pcli_control_changed(before, pcli_control_hash(project_root()))
}

#' Warn about changed control files once the exec has ended; the trust fingerprint of P08 then
#' treats changed trust-gated files as untrusted until confirmed
#' @noRd
pcli_codex_warn = function(changed) {
  if (!length(changed)) return(invisible(changed))
  gptr_warn(paste0("Codex changed gptr control files during its workspace-write turn: ",
                   paste(path_rel(changed), collapse = ", "), ". Changed project settings, ",
                   "MCP servers, extensions and agents are treated as untrusted until you ",
                   "confirm them; review the other files before you restart R."),
            "cli_sandbox")
  invisible(changed)
}

#' End an exec with the terminal error event; `kill` stops the child (turn cap, wall clock)
#' @noRd
pcli_codex_error = function(s, class, text, reason = "error", kill = FALSE, usage = NULL) {
  if (s$done) return(s$msg)
  changed = pcli_codex_after(s)
  msg = pcli_fail(s, class, text, reason = reason, usage = usage)
  if (kill) pcli_stop_child(s$state, wait_ack = FALSE)
  pcli_codex_warn(changed)
  msg
}

#' One completed item: text, reasoning, or a counted tool step
#' @noRd
pcli_codex_item = function(s, item) {
  kind = item[["type"]] %||% ""
  if (identical(kind, "agent_message")) {
    pcli_text_block(s, item[["text"]] %||% "")
  } else if (identical(kind, "reasoning")) {
    pcli_text_block(s, item[["text"]] %||% "", kind = "thinking")
  } else if (kind %in% pcli_codex_tool_kinds) {
    pcli_codex_tool(s, item, "end")
    s$items = s$items + 1L
    if (s$items > s$cap) {
      pcli_codex_error(s, "max_turns",
                      paste0("Codex exceeded the turn cap of this run (", s$cap,
                             " tool steps), so gptr stopped it."), kill = TRUE)
    }
  }
  invisible(NULL)
}

#' Dispatch one `codex exec --json` event (08 3.9). A top-level `error` event is noted, not
#' terminal (the verified driver of 08 5.1 records it and decides at `turn.failed` or the exit)
#' @noRd
pcli_codex_event = function(obj, s) {
  type = obj[["type"]] %||% ""
  item = obj[["item"]] %||% list()
  if (identical(type, "thread.started")) {
    tid = obj[["thread_id"]]
    if (is.character(tid) && length(tid) == 1L && nzchar(tid)) s$state$codex_thread = tid
    pcli_start(s)
  } else if (identical(type, "turn.started")) {
    pcli_start(s)
  } else if (identical(type, "item.started")) {
    pcli_start(s)
    pcli_codex_tool(s, item, "start")
  } else if (identical(type, "item.completed")) {
    pcli_start(s)
    pcli_codex_item(s, item)
  } else if (identical(type, "turn.completed")) {
    changed = pcli_codex_after(s)
    pcli_done(s, pcli_codex_usage(obj[["usage"]] %||% list()), "stop", "completed")
    pcli_codex_warn(changed)
  } else if (identical(type, "turn.failed")) {
    why = obj[["error"]][["message"]] %||% s$last_error %||% "unknown error"
    pcli_codex_error(s, "provider", paste0("Codex reported an error: ", why))
  } else if (identical(type, "error")) {
    why = obj[["message"]] %||% obj[["error"]][["message"]]
    if (is.character(why) && length(why) == 1L && nzchar(why)) s$last_error = why
  }
  invisible(NULL)
}

#' The wall-clock limit of an exec passed: report and stop it (the words "out of budget" keep P06
#' from retrying the turn)
#' @noRd
pcli_codex_timeout = function(s) {
  if (s$done) return(invisible(NULL))
  secs = pcli_turn_seconds()
  pcli_codex_error(s, "timeout", paste0("The codex exec is out of budget: it ran past the ",
                                       "per-turn limit of ", secs,
                                       " s (option gptr.cli_turn_timeout)."), kill = TRUE)
  invisible(NULL)
}

#' parse(): the normaliser of one codex exec (contract 8.1, 8.5)
#' @noRd
pcli_codex_parse = function(model, opts) {
  s = pcli_turn_new(model, opts)
  s$items = 0L
  s$open_tools = character()
  s$last_error = NULL
  s$sandbox = s$state$codex_sandbox %||% "read-only"
  s$cap = s$state$codex_cap %||% as.integer(gptr_opt("max_turns") %||% 50L)
  pcli_wire_log(s, "start")
  pcli_turn_timer(s, function() pcli_codex_timeout(s))

  push = function(ev) {
    if (s$done) return(TRUE)
    obj = ev[["obj"]] %||% pcli_parse_line(ev[["data"]])
    if (!is.list(obj)) return(FALSE)
    if (pcli_aborted(s)) {
      pcli_codex_error(s, "aborted", "The run was aborted.", reason = "aborted")
      return(TRUE)
    }
    pcli_codex_event(obj, s)
    s$done
  }

  finish = function() {
    if (!s$done) {
      if (pcli_aborted(s)) {
        pcli_codex_error(s, "aborted", "The run was aborted.", reason = "aborted")
      } else {
        last = if (is.null(s$last_error)) "" else paste0(" Its last error: ", s$last_error)
        pcli_codex_error(s, "provider",
                        paste0("codex exec exited before completing the turn.", last))
      }
    }
    s$msg
  }

  fail = function(cnd) {
    if (!s$done) {
      aborted = pcli_aborted(s)
      pcli_codex_error(s, if (aborted) "aborted" else sub("^gptr_error_", "", class(cnd)[[1L]]),
                      conditionMessage(cnd), reason = if (aborted) "aborted" else "error")
    }
    s$msg
  }

  message = function() s$msg %||% pcli_message(s)

  list(push = push, finish = finish, fail = fail, message = message)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-codex")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 71 ]`

- [ ] **Step 5: Commit**

```bash
git add R/cli-codex.R tests/testthat/test-cli-codex.R tests/testthat/fixtures/cli/local-fake-cli.R tests/testthat/fixtures/cli/codex-call1.jsonl tests/testthat/fixtures/cli/codex-text.jsonl tests/testthat/fixtures/cli/codex-mcp.jsonl tests/testthat/fixtures/cli/codex-many.jsonl tests/testthat/fixtures/cli/codex-hang.jsonl
git commit -m "feat(cli): cli-codex adapter with sandbox mapping, MCP overrides and turn cap"
```

---

### Task 8: builtin:cli and the claude route end to end

**Files:**
- Modify: `R/cli-common.R` (append)
- Create: `tests/testthat/fixtures/cli/claude-text.ndjson`, `claude-tool.ndjson`, `claude-slow.ndjson`
- Modify: `tests/testthat/fixtures/cli/local-fake-cli.R` (append)
- Test: `tests/testthat/test-cli-common.R` (append), `tests/testthat/test-cli-claude.R` (append)

**Interfaces:**
- Consumes: Tasks 1-7 (among them `pcli_codex_ensure(session)` and, in tests, `local_mcp_stub()`, `pcli_codex_mcp()`, `pcli_codex_forget()` of Task 7); `on_load(expr)` (P01), `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, `gptr_provider(...)`, `gptr_adapter(...)`, the factory API `gptr$register(spec)` and `gptr$on(event, handler, matcher = NULL)` (P02); `setting_get(key, session = NULL, default = NULL)` (P01; the `budget` setting); the `request_params` patch chain and the `usage` event of P06 (04 §10.4: a `request_params` handler returns `list(params)` and may patch only the fields in the adapter's `capabilities$request_params`); `ctx$get(kind, name)`, `ctx$mode()`, `ctx$run`, `ctx$state()`, `ctx$session` (04 §10.6); in tests `gptr()`, `gptr_wait()`, the session accessors (P06/P08), `local_scripted_ui()` (P11), `gptr_registry()`, `registry_get()` (P02), `proc_pool_cap(n)` (P04). The `mcp_message` round trip needs P18's `mcp.dispatch_local` (injected by P06 as `opts$mcp_dispatch`).
- Produces: `builtin_cli(gptr)` (04 §7.20; here the `claude-cli` provider, the `cli-claude` adapter and two hooks; Tasks 9 and 10 complete it), `pcli_capabilities()`, `pcli_used(ctx)`, `pcli_hook_usage(event, ctx)`, `pcli_hook_params(event, ctx)` -> `list(params = list(cli_mode, cli_budget = list(turns, cost)))` for `cli-*` providers, else `NULL`; for a `cli-codex` provider it first calls Task 7's `pcli_codex_ensure(ctx$session)` (the session object `mcp.serve_ensure` needs). Test support: `local_cli_cleanup(s, .env = parent.frame())`, `wait_fake_log(fake, kind, n, runs, timeout = 20)`.

An L1 adapter receives no mode and no budget in `opts` (04 §8.1; P06 passes `signal`, `state`, `memo`, `run`, `session`, `gate`, `tool_result`, `mcp_dispatch`), and IC-33 forbids it to call the session kernel. builtin:cli therefore declares the request parameters `cli_mode` and `cli_budget` in both adapters' `capabilities$request_params` and patches them in with a `request_params` hook: the mode is `ctx$mode()`, the remaining budget is the `budget` setting (default `{tokens: 2000000, cost: 5, turns: null}`, IC-66) minus the cost and request count of the current run, which a `usage` hook accumulates in the session's plugin state (`ctx$state()`, inside an environment so P06 never persists it as a `gptr.ext` entry). Under the default budget the claude argv therefore ends with `--max-budget-usd 5` (and no `--max-turns`, whose budget is `null`), and each top-level call starts its own claude child that resumes the CLI session (Task 5). P06's own budget check stays authoritative between requests. The same hook is where a codex request gets gptr's MCP server: `ctx$session` is the session object that P18's `mcp.serve_ensure` takes, so the hook calls `pcli_codex_ensure(ctx$session)` and the adapter, which holds only the session id, reads the result (Task 7). The end-to-end tests drive `gptr()` with the fake CLI through P05's `process_jsonl` transport.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/cli/claude-text.ndjson`:

```text
{"type":"system","subtype":"init","cwd":"<cwd>","session_id":"11111111-1111-4111-8111-111111111111","tools":["mcp__gptr__r","mcp__gptr__read","mcp__gptr__edit","mcp__gptr__write"],"mcp_servers":[{"name":"gptr","status":"connected"}],"model":"claude-sonnet-5-5","permissionMode":"default","apiKeySource":"none","claude_code_version":"2.1.261","uuid":"u"}
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-sonnet-5-5","id":"msg_fake_1","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":12,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello from "}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"the fake claude CLI."}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":9}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1790749800,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.15,"resetsAt":1790749800},"seven_day":{"utilization":0.34,"resetsAt":1790870400}}},"uuid":"u","session_id":"11111111-1111-4111-8111-111111111111"}
{"type":"result","subtype":"success","is_error":false,"result":"Hello from the fake claude CLI.","stop_reason":"end_turn","session_id":"11111111-1111-4111-8111-111111111111","num_turns":1,"total_cost_usd":0.0012,"usage":{"input_tokens":12,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":9,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"terminal_reason":"completed","uuid":"u"}
```

Create `tests/testthat/fixtures/cli/claude-tool.ndjson` (the CLI asks permission for a pre-allowed tool, as an older CLI that ignored `--allowedTools` would, then calls gptr's `r` tool over `mcp_message`):

```text
{"type":"system","subtype":"init","cwd":"<cwd>","session_id":"11111111-1111-4111-8111-111111111111","tools":["mcp__gptr__r","mcp__gptr__read","mcp__gptr__edit","mcp__gptr__write"],"mcp_servers":[{"name":"gptr","status":"connected"}],"model":"claude-sonnet-5-5","permissionMode":"default","apiKeySource":"none","claude_code_version":"2.1.261","uuid":"u"}
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-sonnet-5-5","id":"msg_fake_1","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":12,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_fake_1","name":"mcp__gptr__r","input":{}}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"code\": \"answer = mean(big_vector) * 2; answer\"}"}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":20}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"fake":"can_use_tool","tool_name":"mcp__gptr__r","input":{"code":"answer = mean(big_vector) * 2; answer"},"tool_use_id":"toolu_fake_1"}
{"fake":"mcp","method":"tools/call","params":{"name":"r","arguments":{"code":"answer = mean(big_vector) * 2; answer"}}}
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_fake_1","type":"tool_result","content":[{"type":"text","text":"$TOOL_TEXT"}]}]},"parent_tool_use_id":null,"uuid":"u","session_id":"11111111-1111-4111-8111-111111111111"}
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-sonnet-5-5","id":"msg_fake_2","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":30,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"The tool said: $TOOL_TEXT"}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":9}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"result","subtype":"success","is_error":false,"result":"The tool said: $TOOL_TEXT","stop_reason":"end_turn","session_id":"11111111-1111-4111-8111-111111111111","num_turns":2,"total_cost_usd":0.0012,"usage":{"input_tokens":12,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":9,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"terminal_reason":"completed","uuid":"u"}
```

Create `tests/testthat/fixtures/cli/claude-slow.ndjson`:

```text
{"type":"system","subtype":"init","cwd":"<cwd>","session_id":"11111111-1111-4111-8111-111111111111","tools":["mcp__gptr__r","mcp__gptr__read","mcp__gptr__edit","mcp__gptr__write"],"mcp_servers":[{"name":"gptr","status":"connected"}],"model":"claude-sonnet-5-5","permissionMode":"default","apiKeySource":"none","claude_code_version":"2.1.261","uuid":"u"}
{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-sonnet-5-5","id":"msg_fake_1","type":"message","role":"assistant","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":12,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1}}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"One "}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"fake":"sleep","seconds":0.5}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"two "}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"fake":"sleep","seconds":0.5}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"three "}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"fake":"sleep","seconds":0.5}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"four "}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"fake":"sleep","seconds":0.5}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"five "}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"fake":"sleep","seconds":0.5}
{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"six."}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"fake":"sleep","seconds":0.5}
{"type":"stream_event","event":{"type":"content_block_stop","index":0},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":9}},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"stream_event","event":{"type":"message_stop"},"session_id":"11111111-1111-4111-8111-111111111111","parent_tool_use_id":null,"uuid":"u"}
{"type":"result","subtype":"success","is_error":false,"result":"One two three four five six.","stop_reason":"end_turn","session_id":"11111111-1111-4111-8111-111111111111","num_turns":1,"total_cost_usd":0.0012,"usage":{"input_tokens":12,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":9,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}},"terminal_reason":"completed","uuid":"u"}
```

Append to `tests/testthat/fixtures/cli/local-fake-cli.R`:

```r
# Stop a session's CLI child and forget it when the calling test ends (claude children live as
# long as their session)
local_cli_cleanup = function(s, .env = parent.frame()) {
  id = s$id
  withr::defer({
    st = pcli_tracked(id)
    if (!is.null(st)) pcli_stop_child(st, wait_ack = FALSE)
    pcli_untrack(id)
  }, envir = .env)
  invisible(s)
}

# Pump the given sessions until the fake CLI has logged `n` rows of `kind` or `timeout` seconds
# passed; returns the count (tests wait on events, never on short wall-clock limits)
wait_fake_log = function(fake, kind, n, runs, timeout = 20) {
  deadline = Sys.time() + timeout
  while (length(fake_log(fake, kind)) < n && Sys.time() < deadline) {
    gptr_wait(runs, timeout = 0.25)
  }
  length(fake_log(fake, kind))
}
```

Append to `tests/testthat/test-cli-common.R`:

```r
# ---- builtin:cli (Task 8) -----------------------------------------------------------------------

# A ctx stand-in with the members the hooks use (contract 10.6)
stub_ctx = function(api = "cli-codex", mode = "edits", run = "r0000000001", id = "s00000000cc") {
  st = new.env()
  list(get = function(kind, name) list(id = name, api = api), mode = function() mode,
       run = run, session = list(id = id), state = function() st)
}

# The hook events builtin:cli registered
cli_hook_events = function() {
  reg = gptr_registry("hook")
  reg$name[reg$source == "builtin:cli"]
}

test_that("builtin:cli registers the claude-cli route, its adapter and two hooks", {
  claude = registry_get("provider", "claude-cli")
  expect_identical(claude$api, "cli-claude")
  expect_identical(claude$type, "cli")
  expect_true("claude_code" %in% claude$aliases)
  expect_true(is.function(claude$status))
  expect_false(isTRUE(claude$offline))
  expect_identical(claude$models[[1]]$id, "default")
  a = registry_get("adapter", "cli-claude")
  expect_identical(a$transport, "process_jsonl")
  expect_identical(a$build, pcli_claude_build)
  expect_identical(a$parse, pcli_claude_parse)
  expect_identical(a$capabilities$request_params, c("cli_mode", "cli_budget"))
  expect_true(all(c("request_params", "usage") %in% cli_hook_events()))
})

test_that("request_params gives CLI routes the mode and the remaining budget", {
  local_mocked_bindings(setting_get = function(key, session = NULL, default = NULL) {
    if (identical(key, "budget")) list(tokens = 2e6, cost = 5, turns = 10) else default
  })
  expect_null(pcli_hook_params(list(provider = "openai"), stub_ctx(api = "openai-responses")))
  ctx = stub_ctx()
  p = pcli_hook_params(list(provider = "codex"), ctx)$params
  expect_identical(p$cli_mode, "edits")
  expect_equal(p$cli_budget, list(turns = 10, cost = 5))
  row = data.frame(cost = 1.25, request_id = "q1")
  pcli_hook_usage(list(row = row), ctx)
  pcli_hook_usage(list(row = row), ctx)
  p = pcli_hook_params(list(provider = "codex"), ctx)$params
  expect_equal(p$cli_budget, list(turns = 8, cost = 2.5))
  ctx$run = "r0000000002"
  expect_equal(pcli_hook_params(list(provider = "codex"), ctx)$params$cli_budget,
               list(turns = 10, cost = 5))
  local_mocked_bindings(setting_get = function(key, session = NULL, default = NULL) {
    list(tokens = 2e6, cost = NULL, turns = NULL)
  })
  b = pcli_hook_params(list(provider = "codex"), ctx)$params$cli_budget
  expect_null(b$turns)
  expect_null(b$cost)
})

test_that("request_params ensures gptr's MCP server for a codex session, not for claude", {
  withr::defer(pcli_codex_forget("s00000000cc"))
  local_mocked_bindings(setting_get = function(key, session = NULL, default = NULL) default)
  local_mcp_stub(stub_mcp_handle(port = 54777L))
  pcli_hook_params(list(provider = "claude-cli"), stub_ctx(api = "cli-claude"))
  expect_null(pcli_codex_mcp(list(session = "s00000000cc")))
  pcli_hook_params(list(provider = "codex"), stub_ctx())
  h = pcli_codex_mcp(list(session = "s00000000cc"))
  expect_identical(h$port, 54777L)
  expect_identical(pcli_codex_env(h), c(GPTR_MCP_TOKEN = "tok-test-0123456789"))
})
```

Append to `tests/testthat/test-cli-claude.R`:

```r
# ---- the claude route end to end (Task 8) -------------------------------------------------------

test_that("a claude turn through gptr() streams the answer; the next call resumes the session", {
  skip_on_cran()
  f = local_fake_cli("claude", "text")
  s = gptr("Say hello", model = f$model, envir = new.env(), mode = "auto")
  local_cli_cleanup(s)
  expect_identical(s$text, "Hello from the fake claude CLI.")
  expect_identical(s$status, "idle")
  s |> gptr("Again")
  expect_identical(s$text, "Hello from the fake claude CLI.")
  argv = fake_argv(f)
  expect_length(argv, 2L)
  expect_false("--resume" %in% argv[[1]])
  expect_identical(utils::tail(argv[[2]], 2L),
                   c("--resume", "11111111-1111-4111-8111-111111111111"))
  expect_length(fake_log(f, "turn"), 2L)
  expect_length(fake_log(f, "handshake"), 2L)
  expect_identical(json_decode(fake_log(f, "stdin")[[1]]$line)$request$subtype, "initialize")
  expect_all_dead(fake_pids(f)[1L])
})

test_that("the claude argv of a gptr() call equals architecture 8.3", {
  skip_on_cran()
  f = local_fake_cli("claude", "text")
  s = gptr("Say hello", model = f$model, envir = new.env())
  local_cli_cleanup(s)
  st = pcli_tracked(s$id)
  expect_identical(fake_argv(f)[[1]],
                   c(claude_argv_8_3(st$claude_mcp_file, st$claude_system_file,
                                     "claude-sonnet-5-5"), "--max-budget-usd", "5"))
  expect_identical(readLines(st$claude_mcp_file), pcli_claude_mcp_json())
  expect_gt(file.size(st$claude_system_file), 0)
})

test_that("usage fields are populated and the rate-limit event becomes plan status", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  f = local_fake_cli("claude", "call2", models = "claude-haiku-4-5")
  s = gptr("Compute", model = f$model, envir = new.env())
  local_cli_cleanup(s)
  expect_identical(s$text, "24")
  msgs = s$messages
  m = msgs[[length(msgs)]]
  expect_identical(m$route, "plan-cli")
  u = m$usage
  expect_equal(c(u$input, u$output, u$cache_read, u$cache_write_1h, u$reasoning),
               c(20, 172, 7448, 7641, 91))
  expect_equal(s$cost, 0.0178928)
  expect_identical(f$provider$status()$plan$type, "five_hour")
})

test_that("an mcp_message round trip evaluates R in the live session and is gated once", {
  skip_on_cran()
  skip_if_not(ext_service_has("mcp.dispatch_local"), "P18's mcp.dispatch_local is not loaded")
  f = local_fake_cli("claude", "tool")
  ui = local_scripted_ui(answers = list("y"))
  e = new.env()
  e$big_vector = c(2, 4, 6, 8, 40)
  s = gptr("Compute twice the mean of big_vector", model = f$model, envir = e, mode = "manual")
  local_cli_cleanup(s)
  expect_identical(e$answer, 24)
  expect_identical(sum(ui$log$method == "permission"), 1L)
  expect_identical(fake_log(f, "permission")[[1]]$behavior, "allow")
  expect_match(fake_log(f, "mcp")[[1]]$text, "24", fixed = TRUE)
  expect_match(s$text, "The tool said:", fixed = TRUE)
})

test_that("an init line with apiKeySource ANTHROPIC_API_KEY stops the turn: gptr_error_billing", {
  skip_on_cran()
  f = local_fake_cli("claude", "apikey")
  err = expect_error(gptr("hi", model = f$model, envir = new.env()), class = "gptr_error_billing")
  expect_match(conditionMessage(err), "apiKeySource ANTHROPIC_API_KEY", fixed = TRUE)
  expect_all_dead(fake_pids(f))
})

test_that("billing and enclosing-agent variables never reach the claude child", {
  skip_on_cran()
  f = local_fake_cli("claude", "text")
  withr::local_envvar(ANTHROPIC_API_KEY = "sk-ant-api03-p20fake-000000000000000000000",
                      ANTHROPIC_PROFILE = "work", ANTHROPIC_FEDERATION_RULE_ID = "p20-rule",
                      CLAUDECODE = "1")
  seen = new.env()
  seen$vars = character()
  seen$text = character()
  s = withCallingHandlers(
    gptr("Say hello", model = f$model, envir = new.env()),
    gptr_warning_billing_env = function(w) {
      seen$vars = c(seen$vars, w$variables)
      seen$text = c(seen$text, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  local_cli_cleanup(s)
  env = fake_env_names(f)[[1]]
  expect_false(any(c("ANTHROPIC_API_KEY", "ANTHROPIC_PROFILE", "ANTHROPIC_FEDERATION_RULE_ID",
                     "CLAUDECODE") %in% env))
  expect_true(all(c("ANTHROPIC_API_KEY", "ANTHROPIC_PROFILE", "ANTHROPIC_FEDERATION_RULE_ID") %in%
                    seen$vars))
  expect_false("CLAUDECODE" %in% seen$vars)
  expect_false(any(grepl("p20fake", seen$text, fixed = TRUE)))
})

test_that("a .cmd claude is refused with the install hint through gptr()", {
  skip_on_cran()
  f = local_fake_cli("claude", "text")
  shim = file.path(withr::local_tempdir(), "claude.cmd")
  writeLines("@echo off", shim)
  withr::local_options(gptr.cli_path = list(claude = shim))
  expect_error(gptr("hi", model = f$model, envir = new.env()), "install.ps1", fixed = TRUE)
})

test_that("three concurrent fake-CLI agents stream into one reactor (INFRA-19)", {
  skip_on_cran()
  n = proc_pool_cap(3L)
  f = local_fake_cli("claude", "slow")
  runs = lapply(seq_len(n), function(i) {
    gptr(paste("Count", i), model = f$model, envir = new.env(), .run = FALSE)
  })
  for (s in runs) local_cli_cleanup(s)
  t0 = Sys.time()
  gptr_wait(runs, timeout = 30)
  elapsed = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  expect_identical(vapply(runs, function(s) s$text, ""), rep("One two three four five six.", n))
  expect_length(unique(fake_pids(f)), n)
  # every turn started before any turn ended: the children streamed at the same time (with
  # proc_pool_cap() = 2 under R CMD check a time bound alone could not tell)
  started = vapply(fake_log(f, "turn"), function(r) as.numeric(r$t), 0)
  ended = vapply(fake_log(f, "turn_done"), function(r) as.numeric(r$t), 0)
  expect_true(length(ended) == n && max(started) < min(ended))
  expect_lt(elapsed, 8)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 12 | WARN 0 | SKIP 0 | PASS 142 ]`; the registration test records ten failed expectations (`registry_get("provider", "claude-cli")` and `registry_get("adapter", "cli-claude")` are `NULL`) and the two hook tests error with ``could not find function "pcli_hook_params"``.

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-claude")'`

Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 106 ]`; every `gptr()` call ends with ``No adapter is registered for the api cli-claude.`` (seven tests error; the INFRA-19 test, whose sessions are started by `gptr_wait()`, records three failed expectations and passes its time bound).

- [ ] **Step 3: Write the implementation**

Append to `R/cli-common.R`:

```r
# ---- builtin:cli (Task 8) ----------------------------------------------------------------------

#' Adapter capabilities of the two plan routes (contract 8.1): plain-text operator notes, no
#' provider cache control, and the two request parameters the `request_params` hook patches in
#' @noRd
pcli_capabilities = function() {
  list(images_in_results = FALSE, tool_addition = FALSE, structured_output = FALSE,
       reasoning_replay = FALSE, parallel_tools = FALSE, forced_tool_choice = FALSE,
       request_params = c("cli_mode", "cli_budget"), operator_role = "user", cache = "none",
       tool_shape = "anthropic")
}

#' The cost and request count charged so far to the current run of a session, kept in the
#' session's plugin state (ctx$state()) inside an environment: a run's counters are not
#' JSON-able on purpose, so P06 never persists them as a gptr.ext entry
#' @noRd
pcli_used = function(ctx) {
  st = tryCatch(ctx$state(), error = function(e) NULL)
  if (!is.environment(st)) return(NULL)
  run = tryCatch(ctx$run, error = function(e) NULL)
  u = st$used
  if (!is.environment(u) || !identical(u$run, run)) {
    u = new.env(parent = emptyenv())
    u$run = run
    u$cost = 0
    u$turns = 0
    st$used = u
  }
  u
}

#' `usage` hook: count each request of the run (contract 10.4 payload `row`)
#' @noRd
pcli_hook_usage = function(event, ctx) {
  row = event[["row"]]
  u = pcli_used(ctx)
  if (is.null(u) || !is.data.frame(row)) return(invisible(NULL))
  u$cost = u$cost + sum(row[["cost"]], na.rm = TRUE)
  u$turns = u$turns + nrow(row)
  invisible(NULL)
}

#' `request_params` hook (a patch chain, contract 10.4): give the plan-route adapters the run's
#' mode (codex sandbox mapping) and the remaining budget (claude --max-turns/--max-budget-usd,
#' the codex turn cap; IC-65, IC-66), and ensure gptr's MCP server with this session's token
#' before a codex request (mcp.serve_ensure takes the session object, which only the hook has;
#' IC-58); other providers are left alone
#' @noRd
pcli_hook_params = function(event, ctx) {
  p = tryCatch(ctx$get("provider", event[["provider"]]), error = function(e) NULL)
  api = p[["api"]] %||% ""
  if (!(api %in% c("cli-claude", "cli-codex"))) return(NULL)
  if (identical(api, "cli-codex")) pcli_codex_ensure(ctx$session)
  lim = setting_get("budget", session = ctx$session,
                    default = list(tokens = 2e6, cost = 5, turns = NULL))
  u = pcli_used(ctx)
  turns = pcli_scalar_num(lim[["turns"]])
  cost = pcli_scalar_num(lim[["cost"]])
  if (!is.null(turns)) turns = max(1, turns - (u$turns %||% 0))
  if (!is.null(cost)) cost = max(0.01, cost - (u$cost %||% 0))
  list(params = list(cli_mode = ctx$mode(), cli_budget = list(turns = turns, cost = cost)))
}

#' builtin:cli: the subscription-plan routes (`claude-cli`, alias claude_code, experimental;
#' `codex`), their process_jsonl adapters and their hooks (contract 7.20, 10.3)
#' @noRd
builtin_cli = function(gptr) {
  gptr$register(gptr_provider("claude-cli", api = "cli-claude", type = "cli",
                              models = pcli_models("claude"),
                              status = pcli_status("claude", "claude-cli", "cli-claude"),
                              aliases = "claude_code"))
  gptr$register(gptr_adapter("cli-claude", transport = "process_jsonl", build = pcli_claude_build,
                             parse = pcli_claude_parse, capabilities = pcli_capabilities()))
  gptr$on("request_params", pcli_hook_params)
  gptr$on("usage", pcli_hook_usage)
  invisible(NULL)
}

on_load(ext_declare_builtin("cli", builtin_cli))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 162 ]`

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-claude")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 140 ]`

- [ ] **Step 5: Commit**

```bash
git add R/cli-common.R tests/testthat/test-cli-common.R tests/testthat/test-cli-claude.R tests/testthat/fixtures/cli/local-fake-cli.R tests/testthat/fixtures/cli/claude-text.ndjson tests/testthat/fixtures/cli/claude-tool.ndjson tests/testthat/fixtures/cli/claude-slow.ndjson
git commit -m "feat(cli): builtin:cli with the claude-cli route, mode and budget hooks"
```

---

### Task 9: Stopping CLI children: interrupt then kill (INFRA-19)

**Files:**
- Modify: `R/cli-common.R` (append; replace `builtin_cli()`)
- Test: `tests/testthat/test-cli-common.R` (append), `tests/testthat/test-cli-claude.R` (append)

**Interfaces:**
- Consumes: the `agent_end` (`status`, `reason`, ...) and `session_shutdown` (`reason`) events (04 §10.4; P06 emits `agent_end` inside `run_settle()`, so it runs during `run_abort()` from Ctrl-C through P14's `console.interrupt_policy` and from `gptr_cancel()`); `ctx$session` and its `$id` accessor (04 §5.1); Task 4's `pcli_tracked()`, `pcli_untrack()`, `pcli_stop_child()`, Task 5's `pcli_claude_budgeted()`, Task 7's `pcli_codex_forget()`; in tests `gptr_wait(x, timeout = Inf)` and `gptr_cancel(x)` (P08), Task 8's `wait_fake_log()`.
- Produces: `pcli_ctx_session(ctx)`, `pcli_hook_end(event, ctx)` (stops a child whose turn is still open: the claude interrupt control request, a wait of up to 2 s for its acknowledgement, then `kill_all()`; retires a claude child that carries budget flags once its run has ended, Task 5), `pcli_hook_shutdown(event, ctx)` (stops the child without waiting, removes the session's claude files and forgets its MCP record, `pcli_codex_forget()`); `builtin_cli()` gains `gptr$on("agent_end", pcli_hook_end)` and `gptr$on("session_shutdown", pcli_hook_shutdown)`.

Why a hook: P06's `run_abort()` cancels the run's transfers, which include P05's stream-watch task, so P05's own abort path (`kill_all()` without the protocol interrupt) never runs for an aborted run, and a claude child would keep working on the turn. 03 §8.3 and 04 §8.5 ask for "a `control_request` interrupt, then `kill_all()`"; 15 §2.9 for "SIGINT first ... then `kill_tree()` after a grace period"; `kill_all()` (P04) sends the interrupt signal, waits and kills the tree. A child whose turn ended without budget flags is left alive for the next turn (one claude child per session, 03 §8.3) and is stopped at `session_shutdown`; a child with budget flags would only be replaced by the next run (Task 5), so `agent_end` retires it at once. The e2e tests wait for the fake's own log rows (`wait_fake_log()`), never on a wall-clock limit under 5 s (conventions §7).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-cli-common.R`:

```r
# ---- stopping CLI children (Task 9) --------------------------------------------------------------

test_that("agent_end stops a child whose turn is open; session_shutdown always", {
  calls = new.env()
  calls$n = 0L
  local_mocked_bindings(pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
    calls$n = calls$n + 1L
    calls$wait = c(calls$wait, wait_ack)
    invisible(TRUE)
  })
  ctx = stub_ctx(id = "s00000000dd")
  st = new.env()
  st$turn_open = FALSE
  pcli_track("s00000000dd", st)
  pcli_hook_end(list(status = "idle"), ctx)
  expect_identical(calls$n, 0L)
  st$turn_open = TRUE
  pcli_hook_end(list(status = "aborted"), ctx)
  expect_identical(calls$n, 1L)
  st$turn_open = FALSE
  st$cli_api = "cli-claude"
  st$claude_flags = list(turns = NULL, cost = 5)
  pcli_hook_end(list(status = "idle"), ctx)
  expect_identical(calls$n, 2L)
  st$claude_flags = list(turns = NULL, cost = NULL)
  pcli_hook_end(list(status = "idle"), ctx)
  expect_identical(calls$n, 2L)
  st$claude_mcp_file = withr::local_tempfile(lines = "{}")
  tab = pcli_cache$mcp %||% list()
  tab$s00000000dd = list(port = 54321L)
  pcli_cache$mcp = tab
  pcli_hook_shutdown(list(reason = "exit"), ctx)
  expect_identical(calls$n, 3L)
  expect_identical(calls$wait, c(TRUE, FALSE, FALSE))
  expect_false(file.exists(st$claude_mcp_file))
  expect_null(pcli_tracked("s00000000dd"))
  expect_null(pcli_cache$mcp$s00000000dd)
  pcli_hook_shutdown(list(reason = "gc"), list(session = NULL))
  expect_identical(calls$n, 3L)
})

test_that("builtin:cli also hooks agent_end and session_shutdown", {
  expect_true(all(c("agent_end", "session_shutdown") %in% cli_hook_events()))
})
```

Append to `tests/testthat/test-cli-claude.R`:

```r
# ---- stopping CLI children (Task 9) --------------------------------------------------------------

test_that("gptr_cancel() sends the interrupt control request, then kill_all()", {
  skip_on_cran()
  f = local_fake_cli("claude", "hang")
  s = gptr("Wait for it", model = f$model, envir = new.env(), .run = FALSE)
  local_cli_cleanup(s)
  expect_identical(wait_fake_log(f, "turn", 1L, s), 1L)
  expect_identical(s$status, "running")
  gptr_cancel(s)
  expect_identical(s$status, "aborted")
  expect_length(fake_log(f, "interrupt"), 1L)
  expect_all_dead(fake_pids(f))
  expect_null(pcli_tracked(s$id)$process)
})

test_that("an abort of three running CLI agents leaves no process tree (INFRA-19)", {
  skip_on_cran()
  n = proc_pool_cap(3L)
  f = local_fake_cli("claude", "hang")
  runs = lapply(seq_len(n), function(i) {
    gptr(paste("Wait", i), model = f$model, envir = new.env(), .run = FALSE)
  })
  for (s in runs) local_cli_cleanup(s)
  expect_identical(wait_fake_log(f, "turn", n, runs), n)
  gptr_cancel(runs)
  expect_identical(vapply(runs, function(s) s$status, ""), rep("aborted", n))
  expect_length(fake_log(f, "interrupt"), n)
  expect_all_dead(fake_pids(f))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 162 ]`; ``could not find function "pcli_hook_end"`` and `c("agent_end", "session_shutdown") %in% cli_hook_events()` is not all `TRUE`.

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-claude")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 145 ]`; after `gptr_cancel()` the fake logged no `interrupt` (`fake_log(f, "interrupt")` has length 0), its processes are still alive after 10 s and `pcli_tracked(s$id)$process` is not `NULL`.

- [ ] **Step 3: Write the implementation**

Append to `R/cli-common.R`:

```r
# ---- stopping CLI children (Task 9) ----------------------------------------------------------

#' The session id of a ctx (NULL for process-level dispatch or a collected session)
#' @noRd
pcli_ctx_session = function(ctx) {
  id = tryCatch(ctx$session$id, error = function(e) NULL)
  if (is.character(id) && length(id) == 1L && !is.na(id)) id else NULL
}

#' `agent_end` hook: a run that ended while its CLI turn was still open (Ctrl-C through the
#' interrupt policy, gptr_cancel(), a budget stop) stops the child: the claude interrupt control
#' request, then kill_all() (03 8.3; INFRA-19). A claude child with budget flags is retired once
#' its run has ended: the next run would replace it anyway (Task 5)
#' @noRd
pcli_hook_end = function(event, ctx) {
  state = pcli_tracked(pcli_ctx_session(ctx))
  if (is.null(state)) return(invisible(NULL))
  if (isTRUE(state$turn_open)) {
    pcli_stop_child(state, wait_ack = TRUE)
  } else if (identical(state$cli_api, "cli-claude") &&
             pcli_claude_budgeted(state$claude_flags)) {
    pcli_stop_child(state, wait_ack = FALSE)
  }
  invisible(NULL)
}

#' `session_shutdown` hook: stop the session's CLI child, remove its temporary files and forget
#' its MCP record
#' @noRd
pcli_hook_shutdown = function(event, ctx) {
  id = pcli_ctx_session(ctx)
  state = pcli_tracked(id)
  pcli_untrack(id)
  pcli_codex_forget(id)
  if (is.null(state)) return(invisible(NULL))
  pcli_stop_child(state, wait_ack = FALSE)
  files = c(state$claude_mcp_file, state$claude_system_file)
  if (length(files)) unlink(files)
  invisible(NULL)
}
```

In `R/cli-common.R`, replace the whole definition of `builtin_cli()` (its roxygen block and function; the `on_load()` line after it stays) with:

```r
#' builtin:cli: the subscription-plan routes (`claude-cli`, alias claude_code, experimental;
#' `codex`), their process_jsonl adapters and their hooks (contract 7.20, 10.3)
#' @noRd
builtin_cli = function(gptr) {
  gptr$register(gptr_provider("claude-cli", api = "cli-claude", type = "cli",
                              models = pcli_models("claude"),
                              status = pcli_status("claude", "claude-cli", "cli-claude"),
                              aliases = "claude_code"))
  gptr$register(gptr_adapter("cli-claude", transport = "process_jsonl", build = pcli_claude_build,
                             parse = pcli_claude_parse, capabilities = pcli_capabilities()))
  gptr$on("request_params", pcli_hook_params)
  gptr$on("usage", pcli_hook_usage)
  gptr$on("agent_end", pcli_hook_end)
  gptr$on("session_shutdown", pcli_hook_shutdown)
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 173 ]`

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-claude")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 150 ]`

- [ ] **Step 5: Commit**

```bash
git add R/cli-common.R tests/testthat/test-cli-common.R tests/testthat/test-cli-claude.R
git commit -m "feat(cli): interrupt then kill a CLI child whose run ends mid-turn"
```

---

### Task 10: The codex route end to end and the CLI leg of INFRA-16

**Files:**
- Modify: `R/cli-common.R` (replace `builtin_cli()`)
- Create: `tests/testthat/fixtures/cli/codex-slow.jsonl`
- Modify: `tests/testthat/fixtures/cli/local-fake-cli.R` (append)
- Test: `tests/testthat/test-cli-common.R` (append), `tests/testthat/test-cli-codex.R` (append)

**Interfaces:**
- Consumes: Tasks 3, 7 and 8; `gptr_providers(check = FALSE)` (P05); in tests Task 7's `local_mcp_stub()` (a user-rank `service` record replaces P18's built-in `mcp.serve_ensure`, IC-34, so neither the request hook nor P19's `backend_cli_start()` starts a real server), `gptr_mcp_serve(stop = TRUE)` (P18), `subagent_backend(agent, model)`, `gptr_agent(...)` and teams through `gptr(agents = list(...))` (P19), `gptr_fake_provider(script, name = "fake", type = "chat")` with the `delay` modifier (P01, 04 §12.1), `model_resolve()` (P05), `path_norm()` (P01).
- Produces: the complete `builtin_cli(gptr)` of 04 §7.20 (providers `claude-cli` and `codex`, adapters `cli-claude` and `cli-codex`, four hooks). Test support: `skip_without_installed_gptr()`.

The `cli` backend is P19's code; its tests are P20's (IC-36): the `auto` rule ("inline, except `cli` for CLI-only models", 03 §6.13) and a team in which a fake codex agent joins two inline agents and two workers on one reactor (INFRA-16, 03 §6.18 row 16: "the CLI leg (a fake CLI joining them) in `test-cli-codex.R` (P20)"). Each of the five agents takes about 3 s, so a sequential run takes at least 15 s; the test asks for under 13 s. Worker children load the installed gptr through callr, so that test runs under `R CMD check` (which installs the package) and skips under `devtools::test()` unless the version under test is installed; conventions §1 forbid installing from a plan step. The MCP round trip uses P18's real server (httpuv, later and openssl are Suggests; the test skips without them).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/cli/codex-slow.jsonl`:

```text
{"type":"thread.started","thread_id":"$THREAD"}
{"type":"turn.started"}
{"fake":"sleep","seconds":1}
{"type":"item.completed","item":{"id":"item_r1","type":"reasoning","text":"step 1"}}
{"fake":"sleep","seconds":1}
{"type":"item.completed","item":{"id":"item_r2","type":"reasoning","text":"step 2"}}
{"fake":"sleep","seconds":1}
{"type":"item.completed","item":{"id":"item_r3","type":"reasoning","text":"step 3"}}
{"type":"item.completed","item":{"id":"item_9","type":"agent_message","text":"Slow codex done."}}
{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"cache_write_input_tokens":0,"output_tokens":122,"reasoning_output_tokens":0}}
```

Append to `tests/testthat/fixtures/cli/local-fake-cli.R`:

```r
# Worker children load the installed gptr (callr): skip unless the installed version is the one
# under test (R CMD check installs it; devtools::test() does not)
skip_without_installed_gptr = function() {
  inst = tryCatch(utils::packageVersion("gptr", lib.loc = .libPaths()), error = function(e) NULL)
  desc = testthat::test_path("..", "..", "DESCRIPTION")
  here = NULL
  if (file.exists(desc)) here = package_version(read.dcf(desc, fields = "Version")[1L, 1L])
  testthat::skip_if(is.null(inst) || (!is.null(here) && inst != here),
                    "worker children need this version of gptr installed")
}
```

Append to `tests/testthat/test-cli-common.R`:

```r
# ---- the codex route (Task 10) ------------------------------------------------------------------

test_that("builtin:cli registers the codex route and its adapter", {
  codex = registry_get("provider", "codex")
  expect_identical(codex$api, "cli-codex")
  expect_identical(codex$type, "cli")
  expect_true("codex" %in% codex$aliases)
  expect_identical(vapply(codex$models, function(m) m$id, ""),
                   c("default", "gpt-6-sol", "gpt-6-luna"))
  a = registry_get("adapter", "cli-codex")
  expect_identical(a$transport, "process_jsonl")
  expect_identical(a$build, pcli_codex_build)
  expect_identical(a$parse, pcli_codex_parse)
})

test_that("gptr_providers() lists both plan routes without starting a process", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_mocked_bindings(proc_run = function(...) stop("spawned a process"),
                        proc_spawn = function(...) stop("spawned a process"))
  pr = gptr_providers()
  expect_true(all(c("claude-cli", "codex") %in% pr$id))
  expect_identical(pr$type[pr$id == "codex"], "cli")
  expect_identical(pr$api[pr$id == "claude-cli"], "cli-claude")
  expect_true(pr$status[pr$id == "codex"] %in% c("found", "not found", "shim refused"))
})
```

Append to `tests/testthat/test-cli-codex.R`:

```r
# ---- the codex route end to end, the CLI leg of INFRA-16 (Task 10) ------------------------------

test_that("a codex turn: exact argv, a 50 KB prompt on stdin intact, the token only in env", {
  skip_on_cran()
  f = local_fake_cli("codex", "text")
  local_mcp_stub()
  withr::local_envvar(OPENAI_API_KEY = "sk-p20fake-openai-0000000000000000",
                      CODEX_API_KEY = "codex-p20fake-0000000000000",
                      OPENAI_BASE_URL = "https://example.invalid/v1", CODEX_SANDBOX = "seatbelt")
  big = paste0("Summarise this text: ", strrep("abcdefghij", 5000L), " caf\u00e9.")
  seen = new.env()
  seen$vars = character()
  s = withCallingHandlers(
    gptr(big, model = f$model, envir = new.env(), mode = "edits"),
    gptr_warning_billing_env = function(w) {
      seen$vars = c(seen$vars, w$variables)
      invokeRestart("muffleWarning")
    })
  expect_identical(fake_argv(f)[[1]],
                   c("exec", "--json", "--ignore-user-config", "--skip-git-repo-check", "-m",
                     "gpt-6-sol", "-C", path_norm(getwd()), codex_mcp_8_5(54321L), "--sandbox",
                     "read-only", "-"))
  bytes = fake_prompts(f)[[1]]
  prompt = rawToChar(bytes)
  Encoding(prompt) = "UTF-8"
  expect_gt(length(bytes), 50000L)
  expect_true(grepl(big, prompt, fixed = TRUE, useBytes = TRUE))
  expect_match(prompt, "^<gptr_instructions>\n")
  env = fake_env_names(f)[[1]]
  expect_true("GPTR_MCP_TOKEN" %in% env)
  expect_false(any(c("OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL", "CODEX_SANDBOX") %in%
                     env))
  expect_true(all(c("OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL") %in% seen$vars))
  expect_false("CODEX_SANDBOX" %in% seen$vars)
  expect_identical(s$text, paste0("Hello from the fake codex CLI (", length(bytes),
                                  " prompt bytes)."))
  m = s$messages[[length(s$messages)]]
  expect_identical(m$route, "plan-cli")
  expect_equal(m$usage$cache_read, 24448)
})

test_that("the next turn resumes the Codex thread with -c sandbox_mode=", {
  skip_on_cran()
  f = local_fake_cli("codex", "text")
  local_mcp_stub()
  s = gptr("First", model = f$model, envir = new.env(), mode = "auto")
  s |> gptr("Second")
  argv = fake_argv(f)
  expect_length(argv, 2L)
  expect_identical(argv[[1]][match("--sandbox", argv[[1]]) + 1L], "workspace-write")
  expect_identical(argv[[2]][1:3], c("exec", "resume", "00000000-0000-4000-8000-000000000001"))
  expect_true("sandbox_mode=workspace-write" %in% argv[[2]])
  expect_false(any(c("-C", "--sandbox") %in% argv[[2]]))
  second = rawToChar(fake_prompts(f)[[2]])
  expect_false(grepl("<gptr_instructions>", second, fixed = TRUE))
  expect_match(second, "Second\n$")
})

test_that("a fake codex evaluates R in the live session through gptr's MCP server", {
  skip_on_cran()
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  skip_if_not_installed("openssl")
  skip_if_not(ext_service_has("mcp.serve_ensure"), "P18's mcp.serve_ensure is not loaded")
  withr::defer(gptr_mcp_serve(stop = TRUE))
  f = local_fake_cli("codex", "mcp")
  e = new.env()
  s = gptr("Compute the sum of 1 to 10 in R", model = f$model, envir = e, mode = "auto")
  expect_identical(e$live_answer, 55L)
  expect_identical(fake_log(f, "mcp")[[1]]$status, 200L)
  expect_match(s$text, "55", fixed = TRUE)
})

test_that("the auto rule runs CLI-only models on the cli backend", {
  f = local_fake_cli("codex", "text")
  expect_identical(subagent_backend(gptr_agent(model = "fakecodex/gpt-6-sol"),
                                    model_resolve(f$model)), "cli")
})

test_that("a fake CLI joins two inline agents and two workers on one reactor (INFRA-16)", {
  skip_on_cran()
  skip_without_installed_gptr()
  f = local_fake_cli("codex", "slow")
  local_mcp_stub()
  slow = function(name) {
    gptr_fake_provider(list(list(text = paste(name, "done"), delay = 3)), name = name)
  }
  inline1 = slow("fakea")
  inline2 = slow("fakeb")
  work1 = slow("fakec")
  work2 = slow("faked")
  t0 = Sys.time()
  team = gptr("Review the analysis", envir = new.env(), agents = list(
    a1 = agent(model = inline1), a2 = agent(model = inline2),
    w1 = agent(model = work1, backend = "worker"), w2 = agent(model = work2, backend = "worker"),
    code = agent(model = "fakecodex/gpt-6-sol")))
  elapsed = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  expect_identical(team$kind, "team")
  expect_identical(team$code$text, "Slow codex done.")
  expect_identical(team$a1$text, "fakea done")
  expect_identical(team$w2$text, "faked done")
  expect_identical(team$code$messages[[length(team$code$messages)]]$route, "plan-cli")
  expect_lt(elapsed, 13)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 174 ]`; `registry_get("provider", "codex")` is `NULL` and `gptr_providers()` has no `codex` row.

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-codex")'`

Expected (the current gptr not installed): `[ FAIL 3 | WARN 0 | SKIP 1 | PASS 72 ]`; the `gptr()` calls end with ``No adapter is registered for the api cli-codex.``; the auto-rule test already passes (the fake provider has `type = "cli"` since Task 3); the INFRA-16 test is skipped with "worker children need this version of gptr installed".

- [ ] **Step 3: Write the implementation**

In `R/cli-common.R`, replace the whole definition of `builtin_cli()` (its roxygen block and function; the `on_load()` line after it stays) with:

```r
#' builtin:cli: the subscription-plan routes (`claude-cli`, alias claude_code, experimental;
#' `codex`), their process_jsonl adapters and their hooks (contract 7.20, 10.3)
#' @noRd
builtin_cli = function(gptr) {
  gptr$register(gptr_provider("claude-cli", api = "cli-claude", type = "cli",
                              models = pcli_models("claude"),
                              status = pcli_status("claude", "claude-cli", "cli-claude"),
                              aliases = "claude_code"))
  gptr$register(gptr_provider("codex", api = "cli-codex", type = "cli",
                              models = pcli_models("codex"),
                              status = pcli_status("codex", "codex", "cli-codex"),
                              aliases = "codex"))
  gptr$register(gptr_adapter("cli-claude", transport = "process_jsonl", build = pcli_claude_build,
                             parse = pcli_claude_parse, capabilities = pcli_capabilities()))
  gptr$register(gptr_adapter("cli-codex", transport = "process_jsonl", build = pcli_codex_build,
                             parse = pcli_codex_parse, capabilities = pcli_capabilities()))
  gptr$on("request_params", pcli_hook_params)
  gptr$on("usage", pcli_hook_usage)
  gptr$on("agent_end", pcli_hook_end)
  gptr$on("session_shutdown", pcli_hook_shutdown)
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-common")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 184 ]`

Run: `Rscript --vanilla -e 'devtools::test(filter = "cli-codex")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 93 ]` (the INFRA-16 test skips unless the version under test is installed; with it installed `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 99 ]`; without httpuv, later or openssl the MCP round trip skips too: `SKIP 2 | PASS 90`).

- [ ] **Step 5: Commit**

```bash
git add R/cli-common.R tests/testthat/test-cli-common.R tests/testthat/test-cli-codex.R tests/testthat/fixtures/cli/local-fake-cli.R tests/testthat/fixtures/cli/codex-slow.jsonl
git commit -m "feat(cli): codex route end to end and the CLI leg of INFRA-16"
```

---

### Task 11: The gated live test

**Files:**
- Test: `tests/testthat/test-live-cli.R` (create)

**Interfaces:**
- Consumes: everything above; `pcli_find()`, `pcli_hook_shutdown()`; `gptr()`, `gptr_mcp_serve(stop = TRUE)` (P08, P18); the real `claude` and `codex` CLIs, signed in by the user.
- Produces: `test-live-cli.R` (03 §3.4: "gated; real `claude`/`codex`"); each test makes one small model call through the user's own plan.

05 P20 acceptance 3: "the gated live test runs Codex in a non-git temporary directory and requires a call of the gptr `r` tool"; IC-65: "Live tests (`GPTR_LIVE_TESTS=true`) run Codex in a non-git temporary directory and require it to call the gptr MCP `r` tool". `tests/testthat/setup.R` (P01) moves `HOME` and `USERPROFILE` to a temporary directory for every test, where neither CLI finds its sign-in, so the live tests also need `GPTR_LIVE_HOME` (the real home directory) and point `HOME`/`USERPROFILE` back at it for the duration of each test; they never read a credential file themselves. `setup.R` also sets `GPTR_REPLAY=replay`, under which P08's `replay_guard()` refuses every provider that is not `offline = TRUE` (`gptr_error_not_recorded`), and runs non-interactively, where P08's `egress_check()` stops a provider without a recorded acknowledgement (`gptr_error_egress`): the helper sets `GPTR_REPLAY=live` for the test, and the calls pass `.opts = list(context = "none")` (P08's documented egress exemption; the prompts are self-contained). The helper also unsets the billing variables, so a developer's own API keys (setup.R keeps them when `GPTR_LIVE_TESTS=true`) neither reach the CLIs nor add a `billing_env` warning.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-live-cli.R`:

```r
# tests/testthat/test-live-cli.R -- the plan routes against the real claude and codex CLIs (P20)
#
# Gated: runs only with GPTR_LIVE_TESTS=true. tests/testthat/setup.R moves HOME to a temporary
# directory, where the CLIs find no sign-in, so these tests also need GPTR_LIVE_HOME set to the
# real home directory; they point HOME/USERPROFILE back at it for the duration of each test. Each
# test makes one small model call through the user's own plan and never reads a credential file.
# setup.R's GPTR_REPLAY=replay would refuse these non-offline providers (P08's replay_guard()),
# so the helper sets GPTR_REPLAY=live; the calls pass .opts = list(context = "none"), P08's
# egress exemption for a non-interactive run; the billing variables are unset so the CLIs bill
# the plan and P03 has nothing to warn about.
#   GPTR_LIVE_TESTS=true GPTR_LIVE_HOME="$HOME" \
#     Rscript --vanilla -e 'devtools::test(filter = "live-cli")'

live_billing_vars = c("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE",
                      "ANTHROPIC_BASE_URL", "ANTHROPIC_FEDERATION_RULE_ID",
                      "ANTHROPIC_ORGANIZATION_ID", "CLAUDE_CODE_USE_BEDROCK",
                      "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "OPENAI_API_KEY",
                      "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL")

skip_live_cli = function(cli, .env = parent.frame()) {
  skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"), "GPTR_LIVE_TESTS is not true")
  home = Sys.getenv("GPTR_LIVE_HOME")
  skip_if_not(nzchar(home) && dir.exists(home), "GPTR_LIVE_HOME names no directory")
  withr::local_envvar(HOME = home, USERPROFILE = home, GPTR_REPLAY = "live",
                      .local_envir = .env)
  withr::local_envvar(stats::setNames(rep(NA_character_, length(live_billing_vars)),
                                      live_billing_vars), .local_envir = .env)
  found = tryCatch(pcli_find(cli), gptr_error = function(e) NULL)
  skip_if(is.null(found), paste("the", cli, "CLI is not installed"))
  invisible(found)
}

test_that("the claude plan route evaluates R in the live session", {
  skip_live_cli("claude")
  skip_if_not(ext_service_has("mcp.dispatch_local"), "P18's mcp.dispatch_local is not loaded")
  e = new.env()
  s = gptr(paste("Use the gptr r tool to run exactly `live_answer = 6 * 7`, then reply with",
                 "the number only."),
           model = "claude-cli/claude-haiku-4-5", envir = e, mode = "auto",
           .opts = list(context = "none"))
  withr::defer(pcli_hook_shutdown(list(reason = "exit"), list(session = list(id = s$id))))
  expect_identical(e$live_answer, 42)
  expect_match(s$text, "42", fixed = TRUE)
  m = s$messages[[length(s$messages)]]
  expect_identical(m$route, "plan-cli")
  expect_gt(m$usage$output, 0)
})

test_that("Codex in a non-git temporary directory calls the gptr r tool", {
  skip_live_cli("codex")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  skip_if_not_installed("openssl")
  skip_if_not(ext_service_has("mcp.serve_ensure"), "P18's mcp.serve_ensure is not loaded")
  withr::defer(gptr_mcp_serve(stop = TRUE))
  dir = withr::local_tempdir()
  withr::local_dir(dir)
  expect_false(dir.exists(file.path(dir, ".git")))
  e = new.env()
  s = gptr(paste("Call the gptr MCP tool `r` with the code `live_answer = sum(1:10);",
                 "live_answer`, then reply with the result only."),
           model = "codex/default", envir = e, mode = "auto", .opts = list(context = "none"))
  expect_identical(e$live_answer, 55L)
  expect_match(s$text, "55", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify the gate**

Run: `Rscript --vanilla -e 'devtools::test(filter = "live-cli")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 0 ]` ("GPTR_LIVE_TESTS is not true"). No package code is missing: the live test exercises Tasks 1-10 against the real CLIs.

- [ ] **Step 3: Write the implementation**

No package code changes in this task. When the maintainer chooses to spend plan quota (optional; never in CI), run with both CLIs installed and signed in:

```bash
GPTR_LIVE_TESTS=true GPTR_LIVE_HOME="$HOME" Rscript --vanilla -e 'devtools::test(filter = "live-cli")'
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "live-cli")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 2 | PASS 0 ]`. With the live command of Step 3: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 7 ]` (a missing or signed-out CLI skips its test instead).

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/test-live-cli.R
git commit -m "test(cli): gated live tests of the claude and codex plan routes"
```

---

## Plan acceptance

Run from the repository root after Task 11, with P01-P19 in place. Every check of 05 P20 (acceptance 1-3 and the review amendments) maps to the tasks and tests below; acceptance 4 (the M4 exit) is row 4, proven by the Milestone gate after this section (steps 1-4 at the end of this plan, step 5 in P21).

| # | Check (05 P20) | Proven by | Command and expected result |
|---|---|---|---|
| 1 | "`devtools::test(filter = "cli-")` is green; the live test skips unless `GPTR_LIVE_TESTS=true`" | Tasks 1-10 (`test-cli-common.R`, `test-cli-claude.R`, `test-cli-codex.R`); Task 11 (`test-live-cli.R`) | `Rscript --vanilla -e 'devtools::test(filter = "cli-")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 1 \| PASS 427 ]` (184 + 150 + 93; the INFRA-16 leg skips unless the version under test is installed, else `SKIP 0 \| PASS 433`; without httpuv, later or openssl the codex MCP round trip skips too: `SKIP 2 \| PASS 424`); `Rscript --vanilla -e 'devtools::test(filter = "live-cli")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 2 \| PASS 0 ]` |
| 2a | "the claude argv equals §8.3 exactly" | Task 5 "the claude argv equals architecture 8.3 exactly, plus budget, opt-out, resume", "build() starts a child once, then reuses it for the next turn", "a budgeted child serves one run; an unbudgeted child lives across runs"; Task 8 "the claude argv of a gptr() call equals architecture 8.3" | `devtools::test(filter = "cli-claude")` green |
| 2b | "an `mcp_message` round trip evaluates R in the live session and is gated once (no second prompt from `can_use_tool`)" | Task 6 "mcp_message requests go to opts$mcp_dispatch; tools/call through the tool FIFO", "can_use_tool allows gptr's own tools without a second gate; others ask the gate"; Task 8 "an mcp_message round trip evaluates R in the live session and is gated once" (one `permission` row in the scripted UI, `e$answer == 24`) | as 2a |
| 2c | "a Ctrl-C sends the interrupt control request then `kill_all()`" | Task 4 "stopping a claude child mid-turn sends the interrupt, then kill_all()"; Task 9 "gptr_cancel() sends the interrupt control request, then kill_all()" and "agent_end stops a child whose turn is open; session_shutdown always" (Ctrl-C reaches the same `run_abort()` -> `agent_end` path through P14's interrupt policy) | as 2a; `devtools::test(filter = "cli-common")` green |
| 2d | "three concurrent fake-CLI agents stream into the reactor and an abort leaves no process tree (INFRA-19)" | Task 8 "three concurrent fake-CLI agents stream into one reactor (INFRA-19)" (every fake's turn starts before any ends, so the children streamed at the same time also when R CMD check caps the pool at 2; under 8 s); Task 9 "an abort of three running CLI agents leaves no process tree (INFRA-19)" (`pid_alive()` false for every fake) | as 2a |
| 2e | "usage fields are populated" | Task 6 "the call-2 capture streams thinking and text and reports the result's usage"; Task 8 "usage fields are populated and the rate-limit event becomes plan status"; Task 7 "the call-1 capture: informational tool events, the answer and the usage" | as 2a and `devtools::test(filter = "cli-codex")` green |
| 2f | "a fake CLI joins two inline agents and two workers on one reactor within about the slowest agent's wall time (the INFRA-16 CLI leg, IC-36)" | Task 10 "a fake CLI joins two inline agents and two workers on one reactor (INFRA-16)" | runs under R CMD check (`devtools::check()`, Milestone gate step 5, which is P21's Plan acceptance command 5); with the version under test installed also under `devtools::test(filter = "cli-codex")` |
| 2g | "an `init` line with `apiKeySource: "ANTHROPIC_API_KEY"` aborts the turn with `gptr_error_billing`" | Task 6 "an apiKeySource other than none ends the turn with gptr_error_billing"; Task 8 "an init line with apiKeySource ANTHROPIC_API_KEY stops the turn: gptr_error_billing" (the child is gone afterwards) | as 2a |
| 3a | "The codex invocation passes `--skip-git-repo-check`, `-m <full id>`, `-C`, the MCP overrides including `default_tools_approval_mode="approve"` and `required=true`, and a 50 KB prompt on stdin intact" | Task 7 "the codex argv follows IC-65, and the resume form uses -c sandbox_mode=", "build() starts one exec per turn with the MCP overrides and the token in env"; Task 10 "a codex turn: exact argv, a 50 KB prompt on stdin intact, the token only in env" | `devtools::test(filter = "cli-codex")` green |
| 3b | "the resume form uses `-c sandbox_mode=`; `edits` maps to `read-only`" | Task 7 (argv and "plan, manual and edits run read-only; auto workspace-write; Windows falls back"); Task 10 "the next turn resumes the Codex thread with -c sandbox_mode=" and the 50 KB test (`mode = "edits"` -> `--sandbox read-only`) | as 3a |
| 3c | "`ANTHROPIC_API_KEY`, `ANTHROPIC_PROFILE`, `CLAUDECODE`, `OPENAI_API_KEY`, `CODEX_API_KEY` and `CODEX_SANDBOX` are absent from the children's environment and a warning names the billing ones" | Task 8 "billing and enclosing-agent variables never reach the claude child"; Task 10 "a codex turn: exact argv, a 50 KB prompt on stdin intact, the token only in env" (the fake logs the variable names it saw; `gptr_warning_billing_env$variables` names the billing ones, not `CLAUDECODE`/`CODEX_SANDBOX`) | as 2a and 3a |
| 3d | "`gptr_providers()` spawns no process with `check = FALSE`" | Task 3 "status() never starts a process without check = TRUE"; Task 10 "gptr_providers() lists both plan routes without starting a process" | `devtools::test(filter = "cli-common")` green |
| 3e | "a `.cmd` fake claude is refused with the install hint" | Task 1 "a .cmd claude is refused with the install hint"; Task 8 "a .cmd claude is refused with the install hint through gptr()" | as 3d and 2a |
| 3f | "the gated live test runs Codex in a non-git temporary directory and requires a call of the gptr `r` tool" | Task 11 "Codex in a non-git temporary directory calls the gptr r tool" (and the claude counterpart; `GPTR_REPLAY=live` and `.opts = list(context = "none")` so P08's replay guard and egress check let the real CLIs run) | `GPTR_LIVE_TESTS=true GPTR_LIVE_HOME="$HOME" Rscript --vanilla -e 'devtools::test(filter = "live-cli")'` -> `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 7 ]` (maintainer only; spends plan quota) |
| 4 | "**M4 exit** (once P18-P21 are complete): NS-6 (two inline fakes, one worker and fake codex on one reactor), NS-9 (`gptr_config(model = sonnet, mode = manual)` writing project defaults after `gptr_init()`, and `gptr_providers(check = TRUE)` with the fake CLIs) and NS-10 MCP pass; `devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")` clean" | Milestone gate steps 1-4 below, run at the end of this plan (they need P18-P20 only); step 5 (the R CMD check) is P21's Plan acceptance command 5, run once P18-P21 are complete | the commands of Milestone gate steps 1 and 3, with the results stated there |
| R1 | Review amendment: "claude argv with `--permission-mode default`, `--allowedTools mcp__gptr__*` and, under a budget, `--max-turns`/`--max-budget-usd`" | Task 5 argv test; Task 8 argv test (default budget -> `--max-budget-usd 5`); Task 8 "request_params gives CLI routes the mode and the remaining budget" | as 2a, 3d |
| R2 | "one gate through `opts$mcp_dispatch`; `opts$gate` for other `can_use_tool` requests" | Task 6 can_use_tool test; Task 8 gated-once test | as 2a |
| R3 | "the `--bare` probe" | Task 2 "pcli_bare_state() detects a -p that defaults to --bare and its opt-out", "an old or bare-only claude and an old codex signal gptr_error_cli_version"; Task 5 (the opt-out is appended) | as 3d |
| R4 | "the `apiKeySource` check and `gptr_error_billing`" | as 2g | as 2a |
| R5 | "G6 §3.7 environment lists" | as 3c (P03's `cli-claude`/`cli-codex` profiles, used by P05's transport and by `pcli_run()`) | as 2a, 3a |
| R6 | "codex argv with `--skip-git-repo-check`, `-m`, `-C`, `default_tools_approval_mode="approve"`, `required=true`, resume with `-c sandbox_mode=`" | as 3a, 3b | as 3a |
| R7 | "sandbox mapping plan/manual/edits -> read-only, auto -> workspace-write with control-file hashing and a checkpointer walk" | Task 7 sandbox test and "a workspace-write exec that changes control files is reported after it ends"; Task 10 resume test (`mode = "auto"` -> `workspace-write`); the walk itself is P16's `turn_end` hook for `type = "cli"` sessions (P16 Task 6) | as 3a |
| R8 | "the Windows sandbox probe" | Task 7 sandbox test (`pcli_codex_windows_ready()` false -> `read-only` and `gptr_warning_cli_sandbox`); the fake CLI answers `codex sandbox ...` with status 0 | as 3a |
| R9 | "the turn counter and `gptr.cli_turn_timeout`" | Task 7 "Codex is stopped at the run's turn cap", "turn.failed, a missing turn.completed and the wall clock end the exec", "a Codex error event is noted, not terminal; turn.failed and the exit report it"; Task 6 "the per-turn wall clock interrupts the CLI and ends the turn as out of budget" | as 2a, 3a |
| R10 | "per-session wire logs" | Task 4 "the wire log gets one redacted line per CLI turn start and terminal event" | as 3d |
| R11 | "per-session MCP tokens (IC-58)" | Task 7 "the MCP record of a session reaches only its own codex exec", "a tokenless MCP server leaves the exec on files only" and the build test (`GPTR_MCP_TOKEN` only in `start$env`); Task 8 "request_params ensures gptr's MCP server for a codex session, not for claude" (`mcp.serve_ensure(ctx$session)` before every codex request); Task 10 50 KB test (the token's name in the child's environment, not in argv) and the live-server round trip | as 3a |
| R12 | "fake CLIs run through `rscript_path()` with `offline = TRUE` records (IC-60, IC-45)" | Task 2 (`pcli_fake_command()`), Task 3 "the plan routes list `default` and full ids; fake CLI records are offline" | as 3d |
| R13 | "the CLI leg of INFRA-16 (IC-36)" | as 2f | as 2f |
| - | 05 Scope: "one-time notice", "cached `status()` data", "session continuity", "usage as plan estimate", "resume when supported", "overhead notice" | Task 2 notice test; Task 3 status tests; Task 4 "a CLI sees only the turns after the last one its own provider answered"; Task 5 "a restarted child resumes the CLI session; a fresh one gets the history" and "a budgeted child serves one run; an unbudgeted child lives across runs"; Task 8 "a claude turn through gptr() streams the answer; the next call resumes the session"; Task 6 call-2 usage and "a reused child's turn costs the increase of the CLI's total_cost_usd"; Task 7 build test (`resume` only when the probe lists it) and the notice text (19-38K tokens) | as above |

## Milestone gate (M4 exit, 05 P20 acceptance 4)

05 P20 acceptance 4 is the M4 exit ("once P18-P21 are complete"; P21 is outside this plan's dependency chain). Steps 1-4 run at the end of this plan (they need P18-P20 only; P21's later-dependent tests skip or are absent). Step 5, the R CMD check, is P21's Plan acceptance command 5, run once P18-P21 are complete. Run every command from the repository root `/Users/wanjun/Desktop/gptr`:

1. The whole suite: `Rscript --vanilla -e 'devtools::test()'` -> `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` with only the documented skips (live tests, Suggests-dependent tests, worker tests when the version under test is not installed, P21's later-dependent tests once P21 is in place; at the end of this plan P21's tests are absent).
2. NS-6 ("two inline fakes, one worker and fake codex on one reactor"): P19's team tests and this plan's Task 10 INFRA-16 leg pass under step 5 (P21's check: R CMD check installs the package, so the worker leg runs there); within step 1 the INFRA-16 leg skips unless the version under test is installed.
3. NS-9 (`gptr_config(model = sonnet, mode = manual)` writing project defaults after `gptr_init()`, P08's tests) and `gptr_providers(check = TRUE)` with the fake CLIs:
   `Rscript --vanilla -e 'pkgload::load_all(".", quiet = TRUE); fix = normalizePath("tests/testthat/fixtures/cli"); options(gptr.cli_path = list(claude = pcli_fake_command("claude", "text", fix, tempfile()), codex = pcli_fake_command("codex", "text", fix, tempfile()))); p = gptr_providers(check = TRUE); print(p[p$type == "cli", c("id", "status", "version")])'`
   -> rows `claude-cli ready 2.1.261` and `codex ready 0.157.0`.
4. NS-10 MCP: P18's acceptance tests green within step 1.
5. P21's Plan acceptance command 5, run once P18-P21 are complete (not at the end of this plan): `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'` -> 0 errors, 0 warnings, no NOTE apart from the incoming-feasibility NOTE naming the maintainer, on the CI matrix of P01.

---

## Self-review

### Spec coverage

| 05 P20 scope item | Task |
|---|---|
| `cli-common.R`: "discovery through `gptr.cli_path`, PATH and known install locations" | 1 (`pcli_find()`, `pcli_on_path()`, `pcli_known_paths()`) |
| "native binaries only for claude (the `claude.cmd` shim refused)" | 1 (`pcli_refuse_shim()`; codex shims resolve to the vendored `codex.exe`) |
| "minimum-version and capability probes" | 2 (`pcli_version()`, `pcli_probe()`, `pcli_bare_state()`) |
| "one-time notice" | 2 (`pcli_notice()`), 7 (the files-only notice) |
| "billing-switch scrub with warning" | P03's `cli-claude`/`cli-codex` profiles, applied by `pcli_run()` (Task 2) and by P05's transport; proven end to end in Tasks 8 and 10 |
| "cached `status()` data" | 3 (`pcli_status()`), 10 (`gptr_providers()`) |
| "`builtin:cli`; IC-65" | 8, 9, 10 |
| `cli-claude.R`: "the flags of architecture §8.3" | 5 |
| "stream-json input/output" | 5 (user lines), 6 (stream events) |
| "control protocol" | 6 |
| "in-process `sdk` MCP via `mcp-server.R`" | 5 (the `--mcp-config` file), 6 (`mcp_message` -> `opts$mcp_dispatch`, P18's `mcp_dispatch_local()`), 8 (round trip) |
| "`can_use_tool` through `perm_check()`" | 6 (`opts$gate`, the run's `perm_check()`) |
| "interrupt" | 4 (`pcli_stop_child()`), 9 (hooks), 6 (wall clock) |
| "session continuity" | 5 (`--resume`, same system-prompt file, history for a fresh child, the unseen turns of other models for a reused or resumed one; a budgeted child serves one run and the next resumes the session), 4 (`pcli_unseen()`), 6 (`system/init` session id; "No conversation found"), 7 (the unseen turns on a resumed Codex thread) |
| "usage as plan estimate" | 6 (`total_cost_usd` as the increase since the child's previous result, route `plan-cli`), 8 |
| `cli-codex.R`: "`codex exec --json --ignore-user-config` with MCP `-c` overrides pointing at `gptr_mcp_serve()`" | 7 (`pcli_codex_ensure()`, `pcli_codex_mcp()`), 8 (the `request_params` hook calls `mcp.serve_ensure(ctx$session)`), 10 |
| "prompt on stdin via `write_all()`" | 7 (send object), 10 (50 KB through P05's `write_all()`) |
| "sandbox mapping" | 7 |
| "resume when supported" | 7 (`probe$resume`), 10 |
| "overhead notice" | 2 (19-38K tokens, own shell in its sandbox) |
| `inst/gptr/fixtures/fake_cli.R` | 2 |
| `fixtures/cli/` | 6, 7, 8, 10 |
| "gated live test" | 11 |

Every acceptance check and review amendment is mapped in "Plan acceptance" above.

### Placeholder scan

The plan contains no "TBD", "TODO", "implement later", "similar to Task N" or step without code. The strings `$TOOL_TEXT`, `$THREAD` and `$PROMPT_BYTES` in fixtures are substitution tokens of the fake CLI (documented at the top of `fake_cli.R`); `<session_id>`, `<signature>`, `<uuid>`, `<UUID>` and similar are the redaction markers of the reports' live captures (07 §3.14, 08 §5.2), kept as captured.

### Type and name consistency with 04

- `builtin_cli(gptr)`, `cli_find(cli = c("claude", "codex"))`, `cli_version(path)`, `cli_probe(path)` have the 04 §7.20 signatures (contract aliases of `pcli_find()`, `pcli_version()`, `pcli_probe()`, tested in Tasks 1 and 2); providers `claude-cli` (alias `claude_code`, `type = "cli"`) and `codex` (alias `codex`), adapters `cli-claude` and `cli-codex` with `transport = "process_jsonl"` and `build`/`parse` of 04 §8.1.
- Conditions: `gptr_error_cli_missing` (`cli`), `gptr_error_cli_version` (`cli`, `found`, `required`), `billing` as the class of the terminal error event (P06 turns it into `gptr_error_billing`/`gptr_error_provider`), `gptr_warning_billing_env` (raised by P03's `child_env()`), `gptr_message_notice`; plus the P20 addition `gptr_warning_cli_sandbox` (Global Constraints, ambiguity 4).
- Options `gptr.cli_path`, `gptr.cli_turn_timeout` read through `gptr_opt()`; events and payloads of 04 §10.4; `ctx` members of 04 §10.6; adapter `opts` fields of 04 §8.1; message, usage and event shapes of 04 §4.2-4.5 (`route = "plan-cli"`).
- Every function consumed from P01-P05 and P12 was taken from those plans' code (and executed, see below). P18 and P19 were checked against their plan files in the review of 2026-10-01: P18's `mcp_serve_ensure(session)` requires the `gptr_session` object (`check_class()`) and returns the handle whose `config$codex$env[[token_env]]` holds the token (P18 ambiguity 19); P19's `backend_cli_start()` passes the child session object to the same service and `subagent_backend(agent, model)` reads `model$type`; P06 passes `opts$session = <session id>` and `opts$mcp_dispatch = function(message)` bound to the session; P16 walks the files checkpointer at `turn_end` of `type = "cli"` sessions (P16 ambiguity 9); P08's `replay_guard()`/`egress_check()` govern the live tests.

### Contract ambiguities and decisions

1. `mcp.serve_ensure(session)` (04 §7.0) takes the session object: P18's `mcp_serve_ensure()` checks `check_class(session, "gptr_session")` and P19 passes the child session, while an L1 adapter holds only the session id (04 §8.1 `opts$session`; P06 passes `d$id`) and IC-33 keeps it away from the kernel's session lookup. The earlier draft passed the id, so every real Codex exec would have run on files only. builtin:cli's `request_params` hook, which receives the session as `ctx$session`, now calls the service (`pcli_codex_ensure()`) before every codex request and keeps the URL, port and token (strings, never the handle, whose `stop()` closure would keep the session alive) per session id for the adapter; `session_shutdown` forgets them. `mcp.dispatch_local(message, session)` arrives bound to the session as P06's `opts$mcp_dispatch(message)`. The token is read from `h$config$codex$env[[h$token_env]]`, the shape P18 produces (its ambiguity 19).
2. The run's mode (codex sandbox) and remaining budget (claude `--max-turns`/`--max-budget-usd`, codex turn cap) are not in the adapter `opts` of 04 §8.1, and IC-33 forbids L1 code to call the kernel. They reach the adapters as request parameters `cli_mode`/`cli_budget`, declared in `capabilities$request_params` (IC-69) and patched in by a `request_params` hook of `builtin:cli`. The remaining budget is the `budget` setting minus the current run's own usage rows (counted by a `usage` hook); a call's `budget =` argument and the root-level charges of IC-66 are not visible there, so the CLI caps are an extra limit and P06's `budget_check()` stays authoritative between requests. The claude caps are fixed when the child starts, so a child with budget flags serves only the run that started it (decision 19).
3. Ctrl-C: P06's `run_abort()` cancels P05's stream watch, so P05's abort (a kill without the protocol interrupt, P05 ambiguity 11) never runs for an aborted run. The interrupt is sent from `builtin:cli`'s `agent_end` hook (which runs inside `run_settle()`), through a weak table of adapter states keyed by session id (a process table like P04's job table, 03 §2.2 rule 5). 05's "a Ctrl-C sends the interrupt control request then `kill_all()`" is tested through `gptr_cancel()`, which follows the same `run_abort()` -> `agent_end` path as P14's interrupt policy.
4. 04 §2.2 lists no warning class for "falls back to `read-only` with a warning" (IC-65, 04 §8.5) or for changed control files; P20 uses `gptr_warning_cli_sandbox` for both (once per process for the Windows fallback, `.once = "cli_sandbox_windows"`) and records it in Global Constraints as a P20 addition to 04 §2.2's warnings, so that the condition reference assembled by P25 lists it.
5. `gptr_error_billing` has the field `source` in 04 §2.2, but P06's `run_condition()` copies only fixed fields from the error event (04 §4.5 `error = list(class, status, request_id, retry_after)`); the source is named in the message instead.
6. IC-65's "cached `Sys.which()` data": `Sys.which()` runs `which` on Unix, so `status(check = FALSE)` performs a PATH scan with `file.exists()`/`file.access()` once and caches it; it never starts a process. This also gives P05's `model_default()` "a detected CLI".
7. Status strings are not enumerated in 04; P20 returns `not found`, `found`, `ready` or the recorded problem, plus `available`, `version`, `path`, `default_model`, `plan` (P05 reads `status`, `version`, `available`).
8. The `--bare` opt-out is hypothetical (no released CLI defaults `-p` to bare; 15 §2.9 verifier); the probe passes `--no-bare` when `--help` lists it and otherwise stops with `gptr_error_cli_version`.
9. The Windows sandbox probe command (`codex sandbox windows cmd.exe /d /c exit 0`) is UNCERTAIN: 08 §6.2 names the setup requirement (`windowsSandbox/readiness` exists only in app-server) but no exec-level probe; nothing was run on Windows.
10. The codex argv is fixed (IC-65), so gptr's frozen T0 + T1 travel in the stdin prompt of a fresh thread as `<gptr_instructions>`; a resumed thread gets only the new input.
11. `claude-cli/default` and `codex/default` resolve to the catalog's newest Sonnet and GPT (aliases `sonnet`, `gpt`), with fixed fallbacks `claude-sonnet-5-5` and `gpt-6-sol`.
12. The informational codex `tool_execution_*` events are emitted through `opts$emit` as 04 §8.5 says; P06's `run_on_event()` forwards only stream events, so they reach P05's accumulator but no hook.
13. The files checkpointer walk after a `workspace-write` exec is P16's `turn_end` hook for `type = "cli"` sessions (P16 ambiguity 9); P20 hashes the control files and warns about changes; P08's trust fingerprint (IC-52) keeps changed trust-gated files untrusted until confirmed.
14. P12's normaliser appends `signature_delta` to the signature given in `content_block_start`; the redacted capture carries a placeholder in both, so the tests assert a non-empty signature only.
15. The provider `codex` has alias `codex` equal to its id (04 §7.20, literally).
16. The live tests need `GPTR_LIVE_HOME` (read only by `test-live-cli.R`): P01's `setup.R` moves `HOME` for every test, where the CLIs find no sign-in.
17. INFRA-19's "three concurrent fake-CLI agents" uses `proc_pool_cap(3L)` agents (2 under R CMD check, IC-60).
18. The INFRA-16 leg needs worker children, which load the installed gptr; it runs under R CMD check and skips under `devtools::test()` unless the version under test is installed (conventions §1 forbid installing from a plan step).
19. Claude child lifetime under a budget (UNCERTAIN CLI semantics, decided defensively). 03 §8.3 wants one long-lived child per session, and IC-65/IC-66 want `--max-turns`/`--max-budget-usd` set to the remaining budget of a budget that restarts with every top-level call. The flags are fixed at launch, and report 07 ran one query per process, so whether a stream-json child applies `--max-budget-usd` and reports `total_cost_usd` per query or per process is not verified; the 07 §3.14 capture points to the process (`total_cost_usd` equals `modelUsage.costUSD`, whose 946 input tokens include the CLI's auxiliary calls, against `usage`'s 20). P20 therefore (a) reuses a child that carries budget flags only within the run that started it: the next run retires it and resumes the CLI session (`--resume`, the same system-prompt file) with fresh flags, and `agent_end` retires it at once; a child without budget flags lives across runs, as 03 §8.3 describes; and (b) records a turn's cost as the increase of `total_cost_usd` since the child's previous result (`pcli_claude_cost()`; a smaller value counts whole). Under the default budget (`cost: 5`) each top-level call therefore starts one claude process. Should a live check show per-query semantics, the reuse rule can drop its run condition; the cost rule is then wrong only for a later turn that costs more than the previous one on the same child.
20. Codex's top-level `error` event is treated as non-terminal (the verified driver of 08 §5.1 records it and decides at `turn.failed` or the exit). Codex reports transient problems such as stream reconnects through it (UNCERTAIN for the 0.157.0 schema; non-terminal handling is the safe reading either way: a fatal error is followed by `turn.failed` or the exit, and the per-exec wall clock bounds a hang).
21. Cross-model continuity (REQ-34): a reused claude child, a resumed claude session and a resumed Codex thread get the turns after the last assistant message their own provider answered as a `<conversation_history>` block (`pcli_unseen()`), so turns answered by another model in between are not lost.
22. 04 is internally inconsistent on names: §7.20 names `cli_version(path)` and `cli_probe(path)`, while §12.3's lint rule (IC-72; P01's `lint_call_rule()`) flags every unqualified `cli_*()` call in `R/` whose first argument is not a literal, which any call of those two functions is. P20 keeps the §7.20 names as one-line aliases (tested) and implements and calls everything under the prefix `pcli_`, so P01's lint test stays green without a change to P01. P18's prose (its ambiguity 19) still names the reader `cli_codex_env()`, now `pcli_codex_env()`; P18 has no code that calls it.

### Validation executed

- Every ```` ```r ```` block of this plan (34) was extracted to the scratch directory and parsed with `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'` (no errors); `getParseData()` finds no `LEFT_ASSIGN` token in the R files, tests, test support or fake CLI, no `<<-`, no `%>%` and no `:::`; every R block is ASCII and at most 100 characters per line. P01's own lint scanner (`lint_scan()` of `test-lint-rules.R`, extracted from the P01 plan) reports 0 hits on `R/cli-common.R`, `R/cli-claude.R` and `R/cli-codex.R` (231 `cli_literal` hits before the `pcli_` rename of the review).
- A scratch package (`DESCRIPTION` `Package: gptr`) held the definitions extracted from the code of P01-P05 and P12 (the transitive closure of everything P20 and its tests call, with P01's `the` fields, P03's `on_load()` registrations and `.onLoad`) plus this plan's files, assembled from the plan's own blocks by a script; `builtin:cli` loaded through P02's real registry. Every red and green summary line of Tasks 1-7 and of the `test-cli-common.R` steps of Tasks 8-10 was produced there by building the package stage by stage (the R code of the earlier tasks, the tests of the task) and running `devtools::test(reporter = "check")`: final `test-cli-common.R` 32 tests, 184 expectations; `test-cli-claude.R` 13 unit tests, 105 expectations; `test-cli-codex.R` 13 unit tests, 71 expectations, all passing; `test-live-cli.R` 2 skips. The end-to-end tests (Tasks 8-10) error there only with ``could not find function "gptr"`` / `"subagent_backend"` (P06-P19 not extracted); their red and green lines are counted from the tests.
- Integration through P05's `provider_stream()` and P04's reactor with the fake CLI (scratch script, not part of the plan): claude, two requests of one run on one child, then a request of a new run under `cli_budget = list(cost = 5)`: a second child whose argv ends `--max-budget-usd 5 --resume 11111111-1111-4111-8111-111111111111`, the first child dead (stdin closed, 0.3 s), and the resumed child receiving only the new input; `pcli_stop_child()` on a hanging turn: the fake logged and acknowledged the interrupt and was gone after 0.06 s (stdin closed); codex with the MCP record that `pcli_codex_ensure()` keeps for the session: the argv carries the `mcp_servers.gptr.url` override, `GPTR_MCP_TOKEN` is in the child's environment and not in its argv, and an `error` event (`Reconnecting... 1/5`) followed by `turn.completed` ends the exec with `done` and the text `Recovered.`. The original writer's integration run (50 KB prompt with a non-ASCII character under the C locale received intact, the resume argv, `status(check = TRUE)` `ready` for both fakes) was not affected by the review's changes.
- `claude-call2.ndjson` is identical to the 07 §3.14 capture (`diff`) except that the R code the model wrote inside two JSON strings uses `=` instead of `<-` (conventions §4: "every code block in the plans"); `codex-call1.jsonl` is identical to the 08 §5.2 capture.
- Probes run: the fake receives empty-string arguments intact (`--tools ""`, `--setting-sources ""`); an Rscript child blocked in `readLines()` on stdin survives SIGINT, which is why `pcli_stop_child()` closes stdin before `kill_all()`.
- Not executed: `gptr()` end to end (needs P06-P19), worker children, P18's real MCP server, Windows, the live CLIs.

## Plan review log

Adversarial review of 2026-10-01 against 00-conventions, 04 (with §15), 05 P20, 03 §8.3, the research reports 07/08 and the dependency plans P01-P06, P08, P12, P16, P18 and P19. Every R block was re-extracted and parsed, P01's lint scanner was run over the R files, the red and green lines of Tasks 1-10 were recomputed by stage builds of a scratch package assembled from the plan's own blocks, and the changed behaviour was run through P05's `provider_stream()` with the fake CLI (see "Validation executed").

| # | Severity | Location | Verdict | What changed, or why rejected |
|---|---|---|---|---|
| 1 | blocker | Task 7 `pcli_codex_mcp()`; Task 8 `pcli_hook_params()` | applied | The codex adapter called `mcp.serve_ensure` with `opts$session`, a session id (04 §8.1; P06 passes `d$id`), but P18's `mcp_serve_ensure()` requires the `gptr_session` (`check_class()`), as P19's `backend_cli_start()` passes it: every real Codex exec would have run on files only and Task 10's real-server round trip would fail. The `request_params` hook, which has the session as `ctx$session`, now calls `pcli_codex_ensure()`, which keeps the URL, port and token (strings, never the handle) per session id; `pcli_codex_mcp(opts)` reads them; `session_shutdown` forgets them (`pcli_codex_forget()`). Tests: Task 7 (two), Task 8 (one), Task 9 (shutdown). |
| 2 | blocker | all R code of Tasks 1-10 | applied | 126 internal functions and objects were named `cli_*` and called unqualified with non-literal first arguments; P01's lint rule `cli_literal` (conventions §5: "Every `cli_*()` call in `R/` takes a literal first argument"; `test-lint-rules.R` "R/ follows the package lint rules") reports 231 hits, so P01's lint test would fail once P20 lands. A token-based rename gave them the prefix `pcli_` (709 symbols, comments, test names and prose); the 04 §7.20 names `cli_find()`, `cli_version()`, `cli_probe()` stay as tested one-line aliases; option names, request parameters and condition classes keep their names. P01's scanner now reports 0 hits (ambiguity 22). |
| 3 | major | Task 11 `test-live-cli.R` | applied | `setup.R`'s `GPTR_REPLAY=replay` makes P08's `replay_guard()` refuse the non-offline `claude-cli`/`codex` providers (`gptr_error_not_recorded`), and the non-interactive `egress_check()` stops without an acknowledgement (`gptr_error_egress`): neither live test could pass. The helper sets `GPTR_REPLAY=live` and unsets the billing variables (a developer's own keys would also have produced a `billing_env` warning, contradicting `WARN 0`); the calls pass `.opts = list(context = "none")`. |
| 4 | major | Task 7 `pcli_codex_event()`, `parse()$finish` | applied | A top-level `error` event ended the turn, although the verified driver of 08 §5.1 only records it and decides at `turn.failed` or the exit; ending there leaves a Codex that may still be working (and writing under `workspace-write`) unsupervised, since its turn is no longer open for the `agent_end` hook. The event is now noted (`s$last_error`), `turn.failed` ends the turn, an exit without `turn.completed` reports the last error; new test; integration run (`Reconnecting... 1/5` then `done`). Ambiguity 20. |
| 5 | major | Tasks 5, 6, 9 (claude child lifetime and cost) | applied | The long-lived claude child kept the `--max-turns`/`--max-budget-usd` of the run that started it, while IC-66 budgets restart with every top-level call, and each turn recorded the result's `total_cost_usd`, which the 07 §3.14 capture shows to be process-level (equal to `modelUsage.costUSD`, which counts the CLI's auxiliary calls): later calls could be cut off by a stale cap and the session cost would double count. A child with budget flags now serves only its run (the next run retires it, stdin closed, and resumes the CLI session with `--resume` and fresh flags; `agent_end` retires it at once); a turn's cost is the increase since the child's previous result (`pcli_claude_cost()`). Tests in Tasks 5, 6, 8 and 9; ambiguity 19 records the unverified CLI semantics. |
| 6 | major | Tasks 4, 5, 7 (continuity, REQ-34) | applied | A reused or resumed claude child and a resumed Codex thread received only the messages after the last assistant message, so turns another model answered in between (03 §8.3) never reached the CLI. `pcli_unseen(prior, provider)` sends the turns after the last one this provider answered as `<conversation_history>`; tests in Tasks 4, 5 and 7. |
| 7 | minor | Task 9 end-to-end tests | applied | `gptr_wait(timeout = 3)` and `timeout = 4` followed by assertions that the fakes had started were wall-clock limits under 5 s (conventions §7). `wait_fake_log()` (Task 8 test support) waits for the fake's log rows with a 20 s cap. |
| 8 | minor | Task 8 INFRA-19 test | applied | Under R CMD check the pool holds 2 agents, so a sequential run (2 x 3 s plus start-up) also met the 8 s bound and the test proved no concurrency there. The fake now logs `turn_done`; the test asserts that every turn started before any ended. |
| 9 | minor | Task 7 `pcli_codex_after()` | applied | `gptr_warn()` was signalled inside the normaliser before the terminal `done` event (04 §8.1); under `options(warn = 2)` a completed exec became an internal failure. The changed files are computed first and `pcli_codex_warn()` warns after the terminal event; the test checks that `done` came first. |
| 10 | minor | Task 10 INFRA-16 test | applied | Mocking `cli_codex_mcp()` left P19's `backend_cli_start()` (and now the request hook) calling P18's real `mcp.serve_ensure`, which starts an HTTP server that the test never stops. It uses `local_mcp_stub()`, moved to Task 7's test support. |
| 11 | minor | Task 4 `pcli_stop_child()` | applied | An R child blocked on stdin ignores SIGINT, so every stop of an idle child (and each per-run replacement of finding 5) waited the whole kill grace. stdin is closed with P04's `write_close()` before `kill_all()` (0.06-0.3 s measured); the unit test asserts it. |
| 12 | minor | Self-review ambiguity 1, Interfaces tables, Global Constraints | applied | Ambiguity 1 said P18 and P19 had no plan and that the service gets the session id. Rewritten after checking both plans; the P18 row of "Interfaces used" and the concurrency line of Global Constraints updated. |
| 13 | minor | every Step 2/Step 4 line, Plan acceptance row 1 | applied | Recomputed by stage builds after the changes (for example Task 7 green 54 -> 71, `test-cli-common.R` 166 -> 184, `filter = "cli-"` 373 -> 427). |
| 14 | minor | Task 6 `pcli_claude_permission()` | rejected | Suggested denying every non-`mcp__gptr__*` `can_use_tool` outright (IC-65: "the handler still denies anything else"). That parenthesis describes the `mcp_message` dispatch handler; 04 §8.5 and 05's review amendment route other requests through `opts$gate`, and `--tools ""` with `--strict-mcp-config` leaves the CLI no other tool. |
| 15 | minor | Task 7 `gptr_warning_cli_sandbox` | rejected | Not in 04 §2.2, but IC-65 requires a warning for the Windows fallback and no listed class fits; kept and recorded as ambiguity 4. |
| 16 | minor | Task 3 `pcli_status()` | rejected | Suggested using `Sys.which()` as IC-65 words it; `Sys.which()` runs `which` (a process) on Unix, and IC-65 also says `check = FALSE` never spawns one; the file-system PATH scan is kept (ambiguity 6). |
| 17 | minor | Task 10 INFRA-16 bound (13 s) | rejected | A tighter bound would be flaky: worker start-up under R CMD check (two callr children loading gptr, slower on Windows) dominates; the leg's purpose is that a fake CLI joins the shared reactor, and P19 owns the inline/worker overlap check. |

## Cross-plan consolidation log

Issues raised by the cross-plan checkers (2026-10-01), verified against 04 (§2.2 warning list, §8.5, IC-65), 00-conventions §5 ("complete list of class names is ... section 2.2"), 05 (P20 acceptance 4, the M4 row of the milestone table), P18 (Plan acceptance note: "The M4 exit check ... is P20's acceptance 4, run once P18-P21 are complete"), P19 (NS-6 team tests, real-worker tests) and P21 (Plan acceptance command 5). After the changes every ```` ```r ```` block (34) was re-extracted and parsed with `Rscript --vanilla` (0 errors; no `<-` or `%>%` in any block, no `LEFT_ASSIGN` token, ASCII only, no line over 100 characters), and the Milestone gate step 3 command parses as well. No test, code block or expected count changed.

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| C1 | shared-names | minor | Task 7 `pcli_codex_sandbox()` (`gptr_warning_cli_sandbox`); Global Constraints conditions list | applied | Valid: 04 §2.2's warning list has no `cli_sandbox`, while 04 §8.5 and IC-65 mandate a warning for the Windows fallback ("falls back to `read-only` with a warning") without naming a class, and no listed class fits; 04 is silent, so the class is kept as an addition, not a deviation. The Global Constraints conditions bullet now records "P20 addition to 04 §2.2's warnings: `gptr_warning_cli_sandbox` (P20; Codex's Windows sandbox not ready, the route runs read-only; once per process; the same class reports control files that a `workspace-write` exec changed, after the exec's terminal event)", so that the condition reference assembled by P25 lists it; the second use (`pcli_codex_warn()`, Task 7) is named too because the plan's code raises the class there. Ambiguity 4 and "Type and name consistency with 04" point at the record. The class is already proven by Task 7's tests "plan, manual and edits run read-only; auto workspace-write; Windows falls back" (`expect_warning(..., class = "gptr_warning_cli_sandbox")`) and "a workspace-write exec that changes control files is reported after it ends"; no test change. P25 (not edited here) should list the class in its condition reference. |
| C2 | trace | major | "Milestone gate" section; Plan acceptance intro and rows 2f and 4 | applied | Valid: the plan index that the section said to run the gate from does not exist (only `00-conventions.md` and P01-P25 are in `dev/plan/`), P21's acceptance runs only `devtools::check()` (its command 5), so the NS-9 `gptr_providers(check = TRUE)` command with the fake CLIs (step 3) was never executed, and step 2 named step 4 for the R CMD check, which is step 5. Heading renamed "Milestone gate (M4 exit, 05 P20 acceptance 4)"; the intro now says steps 1-4 run at the end of this plan (they need P18-P20 only; P21's later-dependent tests skip or are absent) and step 5, the R CMD check, is P21's Plan acceptance command 5, run once P18-P21 are complete; step 1's skip list notes that P21's tests are absent at the end of this plan; step 2 says "pass under step 5 (P21's check ...)" and that the INFRA-16 leg skips within step 1 unless the version under test is installed; step 5 names P21's command 5. New Plan acceptance row 4 quotes 05 P20 acceptance 4 and maps it to gate steps 1-4 (commands of steps 1 and 3, results as stated there), step 5 in P21; row 2f and the intro point at gate step 5 / P21 command 5. No reference to that index file remains. The checker's 5-cell row was fitted to the table's 4 columns. |
| F1 | finalize | minor | Task 1 `tests/testthat/fixtures/cli/local-fake-cli.R`, header comment | applied | `commented_code_linter` (consolidation lint `P20_L00130.R:3`): the header quoted the sourcing call `source(testthat::test_path(...), local = TRUE)` on a comment line of its own, which parses as code. The header is now prose ("Each test-cli-*.R file sources it as its first statement, with local = TRUE, from the path testthat::test_path("fixtures", "cli", "local-fake-cli.R") ..."), one line shorter; the call itself stays in the three test files. No code, test or count change. |
| F2 | finalize | minor | Task 2 `inst/gptr/fixtures/fake_cli.R`, definition of `` `%\|\|%` `` | applied | `object_name_linter` (consolidation lint `P20_L00505.R:26`): not renamed, because the infix name is fixed (an operator, the same name as P01's `R/aaa-state.R` helper, which carries the same nolint). The fake runs as a standalone `Rscript --vanilla` script, where gptr's internal `%\|\|%` is not visible and base R (>= 4.2.0 per DESCRIPTION) has one only from 4.4.0, so the script keeps its own definition; the line now ends `# nolint: object_name_linter.` and a comment line above gives the reason. No other plan calls the fake's copy (it is a script, not a function of the namespace). No behaviour, test or count change. |
| F3 | finalize | minor | Task 3 `R/cli-common.R`, roxygen of `pcli_fake_provider()` | applied | `commented_code_linter` (consolidation lint `P20_L01322.R:105`): the roxygen line `#' options(gptr.cli_path) like the real CLIs'` parsed as a single-quoted string after the `#`. Reworded to "like the real CLIs, it takes its command from options(gptr.cli_path)" (same meaning). Lint of all 34 P20 `r` blocks with P01's linters (`indentation_linter = NULL`; `object_usage_linter = NULL` for standalone blocks): 0 lints; every block re-extracted and parsed under `Rscript --vanilla` (0 errors, no `<-` or `%>%`, ASCII, no line over 100 characters). No test or count change. |

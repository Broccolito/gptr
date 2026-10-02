# P18 MCP and OAuth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give gptr harness-agnostic MCP (REQ-30): a client of both protocol eras over stdio and Streamable HTTP whose tools the model calls as R functions (`gptr$mcp$<server>$<tool>()`), read-only discovery and on-request import of the servers other harnesses configured, gptr itself as an MCP server for the live session, and OAuth (PKCE S256) and credential login.

**Architecture:** Five files. `R/auth-oauth.R` (layer L0) holds PKCE, RFC 9728/8414 discovery, the loopback or paste redirect reader, the locked refresh and `gptr_login()`/`gptr_logout()`; credentials live in P03's credential store and access tokens only in P03's vault. `R/mcp-client.R` (L4) speaks the 2026-07-28 and 2025-11-25 eras over P04's process engine (stdio) and reactor (Streamable HTTP), with the era probe and cache, pagination, progress, cancellation, MRTR and elicitation through P11's ask UI; `R/mcp-config.R` reads gptr's `mcp.json` and the configs of Claude Code, Claude Desktop, Codex (a TOML subset), Cursor, VS Code and Pi and registers `mcp_server` records; `R/mcp-namespace.R` turns tools into `gptr_member` closures behind P10's namespace provider and renders the budgeted T1 `<mcp>` catalog (`builtin:mcp`); `R/mcp-server.R` dispatches JSON-RPC over the session's `r`, `read`, `edit` and `write` through the permission gate, for the claude CLI's in-process `sdk` transport (`mcp.dispatch_local`) and a loopback Streamable HTTP server with one bearer token per client (`gptr_mcp_serve()`, `mcp.serve_ensure`).

**Tech Stack:** base R (>= 4.2.0); jsonlite, curl and processx through P01's JSON helpers and P04's reactor and process engine; ps (lock holders); rlang (`new_weakref()`); Suggests behind `requireNamespace()` with the seed preserved: httpuv, later, openssl (server, loopback redirect, random tokens); testthat 3e and withr in tests; rtiktoken only in the development runner `dev/bench/tokens/run.R` (P07's, not a dependency).

**Spec:** dev/spec/03-architecture.md (§2.2, §3.2, §6.5, §6.7, §6.8, §6.14, §7.3 `<mcp>`, §11.1, §12.2-12.3), dev/spec/04-interface-contract.md (§2.2, §3.1-3.2, §5.1, §5.3, §5.11-5.13, §6.2 `gptr_login()`, §6.3, §7.0, §7.18, §9.3-9.4, §10.4, §11.1, §11.7-11.9, §12.2, §12.4, §15: IC-33, IC-34, IC-37, IC-53, IC-54, IC-57, IC-58, IC-60, IC-61, IC-62, IC-63, IC-64, IC-70, IC-71, IC-72, IC-73), dev/spec/05-plan-decomposition.md (P18).

**Depends on:** P10, P11 (and through them P01-P09). **Milestone:** M4.

## Global Constraints

`dev/plan/00-conventions.md` applies in full (`=` for assignment, never the left arrow; native `|>`; ASCII-only `R/` sources with `\u` escapes; `pkg::fun()` calls; `gptr_abort()`/`gptr_warn()`/`gptr_inform()`; no `:::`; no `.GlobalEnv`; state restored with `on.exit(..., add = TRUE)`; testthat 3e; no network in tests; lines of at most 100 characters). Plan-specific requirements, copied from the specification:

- Owned options (04 §3.1): `gptr.mcp_budget` `int(1)` default `1500L` ("MCP signature catalog tokens"); `gptr.mcp_timeout` `num(1)` default `60` ("seconds per MCP request (soft; progress re-arms)"); `gptr.mcp_probe_timeout` `num(1)` default `5` ("seconds for the era probe"); `gptr.mcp_debug` `lgl(1)` default `FALSE` ("keep redacted MCP server logs in the user cache instead of `tempdir()` (IC-70)"). The defaults already live in P01's `gptr_opt()` table; P18 adds no option.
- Settings key `mcp` (04 §11.2): `{exposure: chr, budget: int, import: [chr]}`, default `{exposure: "r", budget: 1500, import: ["claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi"]}`, read through `setting_get("mcp")`.
- Environment variable (04 §3.2): `GPTR_MCP_TOKEN`, "set only in a child's environment: the bearer token of `gptr_mcp_serve()`".
- Protocol (03 §6.14, report 16 §3.1): modern era `"2026-07-28"` (`_meta` keys `io.modelcontextprotocol/protocolVersion`, `.../clientCapabilities`, `.../clientInfo`, `.../serverInfo`); legacy era `"2025-11-25"`, also accepting `"2025-06-18"`, `"2025-03-26"`, `"2024-11-05"`; `server/discover` probe within `gptr.mcp_probe_timeout`, else legacy `initialize`; "The fallback MUST NOT be keyed to one specific error code"; the era "is cached per server config" for 7 days; progress re-arms the soft timeout and a hard cap of 10 x the timeout applies; "timeouts and interrupts send `notifications/cancelled`"; "MRTR `input_required` at most 5 rounds (elicitation to the `ask` UI, roots answer the project directory, sampling refused)"; the old HTTP+SSE transport (`type: "sse"`) "is refused with an actionable error".
- Files (04 §11.1, §11.7-11.9): gptr's `mcp.json` at `tools::R_user_dir("gptr", "config")/mcp.json` (user) and `.gptr/mcp.json` (project, used only when trusted), written atomically under a short `mkdir` lock (`<file>.lock/`, pid + creation time, 50 x 100 ms retries, IC-71); caches `R_user_dir("gptr", "cache")/mcp-tools/<hash>.json` (`{"tools", "fetched_at", "ttl_ms", "cache_scope"}`) and `mcp-era/<hash>.json` (`{"era": "modern" | "legacy", "version", "date"}`, 7-day expiry), key `hash_sha256(canonical_json(command + args, or URL origin + path))`; server logs "in `tempdir()/gptr/mcp-logs/` unless `options(gptr.mcp_debug = TRUE)`" (then `R_user_dir("gptr", "cache")/mcp-logs/`, 5 MB rotation), appended through `redact_stream("persist")` (IC-70); credentials in `auth.json` (0600) through P03's `auth_store_*()`.
- Placeholders (04 §11.7): `${VAR}`, `${VAR:-default}`, `${env:VAR}`, `${workspaceFolder}`, `${userHome}` (= `user_home()`, IC-63), "expanded at connect time, never when loading; expanded secret-like values are registered".
- Foreign configs (IC-63): found under `user_home()` and `app_config_dir()`, never `path.expand("~")`; listed read-only, imported only by `gptr_mcp_add()`; gptr never edits another harness's file.
- Exposure (03 §6.14, 04 §9.4): default `r`; per-tool `direct`, `deferred`, `hidden`; "one signature line each in the T1 `<mcp>` catalog within 1,500 tokens (least recently used descriptions trimmed first; overflow through `gptr$search()`)"; the `mcp` section is T1, order 840 (04 §7.18); risk of an MCP tool: "`readOnlyHint` 0 (trusted servers), `destructiveHint = FALSE` 2, none 3"; R values are "`structuredContent` simplified, else text"; `isError` -> `gptr_error_mcp_tool` in R; direct MCP results cap at 4,000 tokens; direct tool names `mcp__<server>__<tool>` (at most 64 characters).
- Server (04 §6.3, IC-57, IC-58, IC-61): "binds `127.0.0.1` on `port` (`NULL` = a free port from `port_candidates()`, never `httpuv::randomPort()`)", "a 192-bit bearer token (`openssl::rand_bytes(24)`, hex)", "validates `Origin`", one listening socket with a token per client bound to its session ("The explicit user handle keeps its dedicated session", IC-58: the user's token is bound to a session `gptr_mcp_serve()` creates, `kind = "chat"`, home `envir`, ambiguity 1); a request whose run is outside the serving pump's `allow_runs` gets "a retryable JSON-RPC error (`-32002`, "gptr is busy; retry")"; at an idle console "a request that needs approval is denied with how to allow it" (never a prompt from a callback); client snippets set "a tool timeout of at least 3,600 s".
- OAuth (IC-71, 03 §6.14): "refuse AS metadata without `code_challenge_methods_supported` or without S256; validate `iss` (RFC 9207) when advertised; own callback reader keeping `iss`; state and redirect checks"; client identity pre-registered > DCR (`application_type` `"native"`); "a tool call never opens a browser (a classed condition names the login call)"; every transfer sets `followlocation = 0L` (IC-64, through P04's `reactor_http()`).
- Conditions (04 §2.2): `gptr_error_mcp` (field `server`), `gptr_error_mcp_auth_required` (parent `mcp`; `server`, `login`), `gptr_error_mcp_protocol` (parent `mcp`; `server`, `code`), `gptr_error_mcp_tool` (parent `mcp`; `server`, `tool`); also `noninteractive` (`what`, `questions`), `untrusted` (`what`, `path`, `origin`), `missing_package` (`package`, `feature`), `invalid_argument` (`arg`, `expected`), `provider` (`provider`, `status`), `timeout` (`seconds`, `what`), `workspace` (`path`), `unknown_member` (`name`, `available`), `not_available` (`member`, `provided_by`), `spawn` (`command`), `permission` (through P02's `ext_control_guard()`).
- Classes (04 §5.11-5.13): `gptr_mcp_handle` (environment: `url`, `port`, `token_env`, `config`, `stop()`; plus `token`, see ambiguity 3; `config$codex` is `list(args, env)` with `env = c(GPTR_MCP_TOKEN = <token>)`, the shape P20's `pcli_codex_env(h)` reads, see ambiguity 19), `gptr_mcp_servers` (listing: `name`, `source`, `transport`, `era`, `status`, `tools`, `exposure`, `tokens`, `trusted`), `gptr_mcp_conn` (internal environment), `gptr_ns` nodes of kinds `"mcp"` and `"mcp_server"`, `gptr_member` closures.
- Package state (04 §7.0): P18 owns `the$mcp_conns` (connections, P18's registry ids, the config stamp, catalog last-use times), `the$mcp_server` (the running server; `$user = list(key, session)` holds the dedicated session of `gptr_mcp_serve()` with the sha256 of the user's token) and `the$mcp_tokens` (sha256 of a bearer token -> its session id, never a token value).
- Services (04 §7.0, IC-34): `mcp.catalog` `function(session, budget) chr(1) or NULL`; `mcp.dispatch_local` `function(message, session) list` (JSON-RPC response); `mcp.serve_ensure` `function(session) <gptr_mcp_handle>`; all `provided_by = "P18"`, `builtin = "mcp"`. `session` may be a `gptr_session` or its id. P20's builtin:cli `request_params` hook calls `mcp.serve_ensure(ctx$session)` with the session object (through `pcli_codex_ensure(ctx$session)`, before each Codex request) and P19's `cli` backend passes the child session object; because 04 §8.1 gives L1 adapters only ids ("`run`, `session` | ids"), P18 also accepts an id and resolves it through its own weak index of the sessions whose `session_start` builtin:mcp saw (ambiguity 20). Events (P02 catalogue): `mcp_servers_change` (`added`, `removed`), `mcp_serve_start` (`url`), `mcp_serve_stop` (`url`), all notify.
- Layering (03 §2.2, IC-33): `auth-oauth.R` is L0 and reaches the MCP layer only through the callback it is given (`oauth_hooks_set()`); the `mcp-*.R` files are L4 and call only L0, their own area, the declared services, the `tool-walk.R` service file (`glob_to_regex()`), the kernel SDK (`session_data()`, `session_live()`, `session_home()`, `run_current()`, `run_eval_env()`, `dispatch_nested()`, `perm_check()`, `format_eval_result()`, `setting_get()`) and P06's `session_new()` for the dedicated session of `gptr_mcp_serve()` (the `mcp` contract edge of P01's `arch_contract_edges()`, 04 §6.3); P10's `ns_register_provider()` is called only from a top-level `on_load()` expression.
- Control exports (IC-53): `gptr_mcp_add()`, `gptr_mcp_remove()`, `gptr_mcp_serve()`, `gptr_login()` and `gptr_logout()` start with P02's `ext_control_guard("<name>")`.
- Randomness (IC-61): tokens, PKCE verifiers and states come from `openssl::rand_bytes()`; httpuv and openssl load and `httpuv::startServer()` runs inside `with_seed_preserved()`; tests assert an identical `.Random.seed` after `gptr_mcp_serve()` and after the OAuth loopback.
- Child processes (IC-60): stdio servers start through `proc_spawn()` with `child_env("mcp", set = <expanded env>)`; at most `proc_pool_cap(64L)` stdio connections are open (2 under `R CMD check`); every test helper starts children with `rscript_path()`; every process- or server-starting test calls `skip_on_cran()`.
- Test environment: P01's `setup.R` redirects `HOME`, `USERPROFILE`, `APPDATA`, `XDG_CONFIG_HOME` and `R_USER_*_DIR`; P18's tests also redirect them per test (`local_user_dirs()`, `local_mcp_home()`) and set `CODEX_HOME = ""`, so no test reads a real harness file or credential. Every test that registers secrets starts from an empty vault and empties it again on exit (P03's `vault_reset()`, called by `local_user_dirs()`, `local_mcp_home()` and the two tests that register secrets directly), as P03's test convention requires; fake keys are assembled with `paste0()` so no key-shaped literal sits in a source file. In a C locale R's parser double-encodes the `\u` escapes of a string literal that also contains a `\U` escape, so no test literal mixes the two.
- Credentials and origins (04 §11.8, IC-64): a stored MCP credential records the `resource` it was issued for, and `oauth_access()` hands it only to that resource's origin, so a server whose URL changed (for example a trusted project's `mcp.json` reusing a user server's name) never receives the old server's token; origins are compared after `url_origin()` (P04, default ports dropped), because P03 stores handle origins canonically with the port (`https://host:443`).
- IC-73: P18 adds its north-star fixture and baseline row to `dev/bench/tokens/` with P07's runner (`--update <id>`), the named exception to file ownership.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `R/auth-oauth.R` | create (Tasks 1, 2) | URL, header, form and query helpers; PKCE S256; metadata, redirect and `iss` checks; the `mkdir` lock; reactor HTTP, RFC 9728/8414 discovery, DCR; access tokens in the vault, the locked refresh; the loopback or paste redirect; `oauth_flow()`; `gptr_login()`, `gptr_logout()` |
| `R/mcp-client.R` | create (Tasks 3, 4, 5) | wire helpers (ASCII JSON, header values, names, schema coercion, results); the process state and the era, tool and log caches; placeholder expansion; connections (era handshake, requests, progress, cancellation, server requests, MRTR, elicitation, pagination); the stdio transport; the Streamable HTTP transport with stored credentials |
| `R/mcp-config.R` | create (Task 6) | the TOML subset; the config sources of every harness; normalisation, merging, trust; `mcp_server` records; gptr's `mcp.json` writer; `gptr_mcp()`, `gptr_mcp_add()`, `gptr_mcp_remove()` |
| `R/mcp-namespace.R` | create (Task 7) | MCP tool specs and risk; `gptr_ns` nodes and `gptr_member` closures; the budgeted `<mcp>` catalog; the `mcp.catalog` service; direct tools at session start; `builtin:mcp`; the namespace provider and login target registered at load |
| `R/mcp-server.R` | create (Tasks 8, 9) | the JSON-RPC dispatcher over `r`, `read`, `edit`, `write` (both eras) and the `mcp.dispatch_local` service; bearer tokens per session; the loopback HTTP server; client snippets; `gptr_mcp_serve()` with its dedicated session, and `mcp.serve_ensure` |
| `tests/testthat/test-auth-oauth.R` | create (Tasks 1, 2) | pure OAuth checks; sign-in, refresh, refusals, key entry, the OpenRouter-style exchange |
| `tests/testthat/test-mcp-client.R` | create (Tasks 3, 4, 5) | wire helpers and caches; both eras over stdio and HTTP; progress, cancel, interrupt, MRTR, elicitation, stderr redaction, `.cmd` shims, OAuth bearer tokens |
| `tests/testthat/test-mcp-config.R` | create (Task 6) | TOML; foreign configs; precedence and trust; listings; `gptr_mcp_add()`/`gptr_mcp_remove()` |
| `tests/testthat/test-mcp-namespace.R` | create (Task 7) | closures, nested gating, catalog budget and LRU, search, exposure, foreign servers |
| `tests/testthat/test-mcp-server.R` | create (Tasks 8, 9) | dispatcher; the claude route; the HTTP server's token, Origin, binding, gating, seed, dedicated session (mode, usage), fork overlay, plan mode, busy rule, snippets |
| `tests/testthat/helper-mcp-server.R` | create (Tasks 2, 4, 6, 8, 9) | `local_mcp_fixture()` (contract 12.2) and the other MCP and OAuth test helpers |
| `tests/testthat/fixtures/mcp/server.R` | create (Task 4) | the pure-R MCP fixture server (both eras, stdio or HTTP) |
| `tests/testthat/fixtures/mcp/oauth.R` | create (Task 2) | the OAuth authorization server and protected MCP resource |
| `tests/testthat/fixtures/mcp/browser.R` | create (Task 2) | a stand-in browser that follows the sign-in redirects |
| `tests/testthat/fixtures/mcp/client.R` | create (Task 9) | a stand-in CLI child speaking HTTP MCP with `GPTR_MCP_TOKEN` |
| `dev/bench/tokens/fixtures/ns10-mcp-catalog.json` | create (Task 10) | P18's NS-10 golden transcript (IC-73) |
| `dev/bench/tokens/baseline.csv` | modify (Task 10, through P07's runner) | the `ns10-mcp-catalog` baseline row |
| `NAMESPACE`, `man/gptr_login.Rd`, `man/gptr_mcp.Rd`, `man/gptr_mcp_add.Rd`, `man/gptr_mcp_serve.Rd` | generated (Tasks 2, 6, 9) | `Rscript --vanilla -e 'devtools::document()'` |

Tasks:

1. OAuth building blocks: URLs, forms, PKCE, metadata and redirect checks, the lock
2. OAuth sign-in: discovery, flows, the locked refresh, `gptr_login()` and `gptr_logout()`
3. MCP wire helpers, process state, caches and placeholders
4. The MCP client over stdio: era handshake, requests, progress, cancellation, MRTR, elicitation
5. The Streamable HTTP transport and stored credentials
6. MCP configuration: gptr's `mcp.json`, other harnesses, `gptr_mcp()`, `gptr_mcp_add()`, `gptr_mcp_remove()`
7. The `gptr$mcp` namespace, the `<mcp>` catalog and `builtin:mcp`
8. The MCP server dispatcher and the claude route (`mcp.dispatch_local`)
9. The loopback HTTP server: tokens per client, `gptr_mcp_serve()`, `mcp.serve_ensure`
10. The NS-10 golden transcript (`dev/bench/tokens/`)

Every test command runs from the repository root. The expected summaries were measured on macOS with R 4.4.3 and testthat 3.3.2; on Windows the `.cmd` test of Task 4 runs instead of skipping (SKIP 0, PASS + 1).

### Functions consumed from earlier plans

Exactly as defined in 04 and in the dependency plans (internal helpers of a dependency plan are marked as such):

- P01: `the`, `on_load(expr)`, `on_unload(fun)`, `` `%||%` ``, `ext_service_set(name, fun, provided_by, builtin = NULL)`, `ext_service_get(name)`, `ext_service_has(name)`, `setting_get(key, session = NULL, default = NULL)`, `gptr_opt(name)`, `gptr_can_prompt()`, `gptr_has_human()`, `gptr_is_interactive()`, `gptr_abort(message, class, ..., .data = NULL, call = NULL)`, `gptr_inform(message, class, ...)`, `msg_verbatim(x, stream = c("stdout", "stderr"))`, the §1.1 checkers (`check_string()`, `check_strings()`, `check_flag()`, `check_number()`, `check_choice()`, `check_env()`, `check_list()`, `check_class()`), `json_encode(x, pretty = FALSE)`, `json_decode(text)`, `json_obj()`, `canonical_json(x)`, `hash_sha256(x)`, `id_new()`, `port_candidates(n = 20L)`, `with_seed_preserved(expr)`, `as_utf8(x)`, `raw_to_utf8(x, fallback = "CP1252")`, `read_utf8(path)`, `write_atomic(path, content)`, `user_home()`, `app_config_dir(app)`, `path_key(path)`, `path_norm(path)`, `project_root(path = getwd())`, `workspace_dir(path = getwd())`, `gptr_user_dir(which, create = FALSE)`, `rscript_path()`, `est_tokens(x, class)`, `truncate_output(text, budget_tokens, class = "r_output", head = 0.4, id_prefix = "o")`, `new_listing(df, class, footer = NULL)`, `schema_validate(schema, input)`, `schema_signature(name, schema, description = NULL, prefix = "")`, `first_sentence(text)` (internal, `json-schema.R`), `block_image(data, mime = "image/png", source = "plot", width = NULL, height = NULL)` (source `"mcp"`); test helpers `local_fake_provider()`, `fake_tool()`, `fake_requests()`, `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())`, `local_gptr_options(...)`.
- P02: `registry_add(spec, source, rank, session = NULL, state = "active")`, `registry_remove(id)`, `registry_get(kind, name, session = NULL)`, `registry_all(kind, session = NULL)`, `registry_names(kind, session = NULL)`, `registry_diagnostic(source, event, class, message)`, `gptr_spec(kind, name, ...)` (kind `mcp_server`), `gptr_tool(name, description, parameters = NULL, execute = NULL, fun = NULL, exposure = c("direct", "r", "deferred", "hidden"), namespace = NULL, execution = c("sequential", "concurrent"), risk = NULL, snippet = NULL, guidelines = NULL, signature = NULL, output_tokens = NULL, record = TRUE, available = NULL, annotations = list())`, `gptr_prompt_section(name, text, tier = c("T0", "T1"), order = 500L, budget = 300L, parent = NULL)`, `gptr_tool_result(text = NULL, images = NULL, details = NULL, is_error = FALSE, value = NULL)`, `as_tool_result(x)`, `gptr_register(spec)`, `ev_dispatch(event, payload, session = NULL, ctx = NULL)`, `hook_add(event, handler, matcher = NULL, rank = 3L, source = "user", session = NULL)`, `hook_remove(id)`, `ctx_new(session, run = NULL)`, `ext_declare_builtin(name, factory, after = character(), replaceable = TRUE)`, `ext_control_guard(what)` (internal, `ext-registry.R`).
- P03: `secret_register(value, name, source = "user", active = TRUE, origin = NULL)`, `secret_value(handle, origin)`, `secret_lookup(name)`, `redact(x, profile = "persist")`, `redact_stream(profile = "stream")`, `auth_store_get(key)`, `auth_store_set(key, record)`, `auth_store_remove(key)`, `auth_lock_stale(lock)` (internal, `auth-store.R`), `secrets_state()` (internal, `auth-secrets.R`: the registry `reg` of vault entries, read by `oauth_forget_access()` in the same `auth` area), `vault_reset()` (internal, `auth-secrets.R`; tests only), `child_env(profile, pass = character(), set = character(), provider = NULL)`.
- P04: `reactor_http(spec, on_bytes, on_done, on_fail, on_headers = NULL, run = NULL, provider = NULL, retry = NULL)` (spec fields `url`, `method`, `headers` (values chr, handles or `list("Bearer ", <handle>)`), `body`, `first_byte_timeout`, `idle_timeout`), `reactor_proc(proc, on_line, on_exit, run = NULL, stream = "stdout", on_stderr = NULL)`, `reactor_pump(until, slice_ms = 100L, allow_runs = NULL, timeout = Inf)`, `reactor_cancel(ids)`, `reactor_now()`, `reactor_allow_runs()` (internal), `reactor_depth()` (internal: the pump depth, `0L` outside any pump), `url_origin(url)` (internal, `http-request.R`; lower-cased `scheme://host[:port]`, default ports dropped), `sse_splitter()`, `proc_spawn(command, args, env, wd, stdin, stdout, stderr, cleanup_tree, supervise)`, `write_all(p, data)`, `write_close(p)` (internal), `kill_all(p, grace = 2)`, `proc_pool_cap(n)` (internal), `job_add(kind, id, name, pid = NA, stop, status)`, `job_remove(id)`, `job_list(kind = NULL)`.
- P06: `session_data(s)`, `session_live(s)`, `session_home(s)`, `run_current()` (a `gptr_run` with fields `id`, `shell`, `mode`, `opts`), `run_eval_env(run)`, `dispatch_nested(name, input, ctx)`, `perm_check(call, run)`, `gptr_fork(s, at = NULL, envir = c("overlay", "shared"))`; `session_new(model, mode, home = NULL, kind = "chat", parent = NULL, preset = NULL, opts = list())`, called only by `mcp_serve_session()` for the dedicated session of `gptr_mcp_serve()` (04 §6.3; not on the IC-33 kernel SDK, P01's `arch_contract_edges()` admits the `mcp-*.R` -> `session_new()` edge); tests: `gptr_usage(x = NULL, by = "session")`, `usage_add(s, row)` and `usage_conform(row)` (internal, `session-budget.R`); the `session_start` event (collect; emitted at a session's first freeze and by `gptr_fork()` with reason `fork`, its `ctx$session` the session). `session_by_id()` is not on the IC-33 kernel SDK, so P18 never calls it.
- P08: `gptr()` (tests), the `trust.get` service (`function(path = getwd()) lgl(1)`), `gptr_trust(path = ".", trust = NULL)` (bench fixture).
- P09: the `eval.r` service (`eval_r()`'s arguments), `format_eval_result(res, budget_tokens)`.
- P10: `ns_register_provider(name, fun)`, `glob_to_regex(glob)`, the `gptr_ns` methods (`$`, `[[`, `names`, `print` read the bindings `path`, `kind`, `members()`, `signatures()`), `gptr$search()` and `gptr$help()` (which read the `mcp.catalog` service and the `mcp` provider).
- P11: the `ui.get` service (`function(session = NULL) <spec:ui>` with `has_ui()`, `input(prompt, default = "", secret = FALSE)`, `questions(qs)` -> `list(answers, cancelled)`, `notify(text, level = "info")`), the `risk.classify` service, the `mode`, `rules` and `plan` policies; test helper `local_scripted_ui(answers = list(), .env = parent.frame())`.


---

### Task 1: OAuth building blocks: URLs, forms, PKCE, metadata and redirect checks, the lock

**Files:**
- Create: `R/auth-oauth.R`
- Test: `tests/testthat/test-auth-oauth.R` (create)

**Interfaces:**
- Consumes: P01 `gptr_abort()`, `as_utf8()`, `json_obj()`, `with_seed_preserved()`, `rscript_path()` (tests); P03 `auth_lock_stale(lock)` (internal: `TRUE` when the lock directory is older than 30 s, its pid is dead, or the pid's creation time differs; IC-71); `jsonlite::base64_enc()`; Suggests `openssl::rand_bytes()`, `openssl::sha256()`; `ps::ps_handle()`, `ps::ps_create_time()`.
- Produces (internal; used by Tasks 2-9): `url_parts(url)` -> `list(scheme, host, port, path, query)`; `hdr_value(headers, name)` -> chr(1) or `NULL`; `form_encode(fields)` -> chr(1); `query_parse(q)` -> named list; `b64url(bytes)`; `oauth_parse_challenge(h)` -> named list; `oauth_check_metadata(meta, issuer)` -> `meta` invisibly or `gptr_error_untrusted`; `oauth_authorize_url(meta, client_id, redirect_uri, scope, state, challenge, resource = NULL)`; `oauth_parse_redirect(input, redirect_uri, state, issuer, iss_supported = FALSE)` -> the code or `gptr_error_untrusted`/`gptr_error_provider`; `oauth_need(pkg, feature)` (`gptr_error_missing_package`); `rand_hex(n)` -> 2n lower-hex characters; `pkce_new(verifier = NULL)` -> `list(verifier, challenge, method = "S256")`; `oauth_lock_with(path, fun, tries = 50L, wait = 0.1)` -> `fun()`'s value or `gptr_error_timeout`.

These helpers are pure or local: report 03 §5.6 (PKCE checked against RFC 7636 appendix B) and report 16 §2.9, §3.5 and §5.15 with its verification-log fixes 7 (metadata without `code_challenge_methods_supported` is refused) and 17 (gptr reads the redirect itself so that `iss` survives). The lock reuses P03's staleness rule instead of a second one.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-auth-oauth.R`:

```r
test_that("url helpers split URLs; hdr_value reads headers case-insensitively", {
  u = url_parts("https://Example.org:8443/a/b?x=1&y=2")
  expect_identical(u$scheme, "https")
  expect_identical(u$host, "example.org")
  expect_identical(u$port, "8443")
  expect_identical(u$path, "/a/b")
  expect_identical(u$query, "x=1&y=2")
  expect_identical(url_parts("http://[::1]:5000/cb")$host, "[::1]")
  expect_error(url_parts("no scheme"), class = "gptr_error_invalid_argument")
  expect_identical(hdr_value(list(`Www-Authenticate` = "Bearer x"), "WWW-Authenticate"), "Bearer x")
  expect_null(hdr_value(list(a = "1"), "b"))
  expect_null(hdr_value(NULL, "b"))
})

test_that("form and query encoding round-trip", {
  expect_identical(form_encode(list(a = "x y", b = NULL, c = "p&q=r")), "a=x%20y&c=p%26q%3Dr")
  q = query_parse("?code=abc&state=s%201&iss=https%3A%2F%2Fas.example&empty")
  expect_identical(q$code, "abc")
  expect_identical(q$state, "s 1")
  expect_identical(q$iss, "https://as.example")
  expect_identical(q$empty, "")
  expect_identical(query_parse(""), json_obj())
})

test_that("PKCE follows the RFC 7636 appendix B vector; tokens never touch the RNG", {
  skip_if_not_installed("openssl")
  p = pkce_new("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
  expect_identical(p$challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  expect_identical(p$method, "S256")
  withr::local_seed(1)
  seed = get(".Random.seed", envir = globalenv())
  expect_match(pkce_new()$verifier, "^[A-Za-z0-9_-]{43}$")
  expect_match(rand_hex(24L), "^[0-9a-f]{48}$")
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
})

test_that("the WWW-Authenticate challenge is parsed", {
  ch = oauth_parse_challenge(paste0(
    "Bearer realm=\"OAuth\", resource_metadata=",
    "\"https://mcp.example/.well-known/oauth-protected-resource/mcp\", scope=\"read write\""))
  expect_identical(ch$resource_metadata,
                   "https://mcp.example/.well-known/oauth-protected-resource/mcp")
  expect_identical(ch$scope, "read write")
  expect_identical(oauth_parse_challenge(NULL), list())
})

test_that("metadata without S256 PKCE or for another issuer is refused (IC-71)", {
  good = list(issuer = "https://as.example", authorization_endpoint = "https://as.example/auth",
              token_endpoint = "https://as.example/token",
              code_challenge_methods_supported = list("S256"))
  expect_invisible(oauth_check_metadata(good, "https://as.example"))
  no_pkce = good
  no_pkce$code_challenge_methods_supported = NULL
  expect_error(oauth_check_metadata(no_pkce, "https://as.example"), "PKCE",
               class = "gptr_error_untrusted")
  plain = good
  plain$code_challenge_methods_supported = list("plain")
  expect_error(oauth_check_metadata(plain, "https://as.example"), "S256",
               class = "gptr_error_untrusted")
  expect_error(oauth_check_metadata(good, "https://other.example"), "another issuer",
               class = "gptr_error_untrusted")
})

test_that("the authorization URL carries PKCE, state and the resource", {
  meta = list(authorization_endpoint = "https://as.example/authorize")
  url = oauth_authorize_url(meta, "c1", "http://127.0.0.1:50000/callback", "read", "st", "CH",
                            resource = "https://mcp.example/mcp")
  q = query_parse(url_parts(url)$query)
  expect_identical(q$response_type, "code")
  expect_identical(q$code_challenge_method, "S256")
  expect_identical(q$code_challenge, "CH")
  expect_identical(q$state, "st")
  expect_identical(q$resource, "https://mcp.example/mcp")
  expect_identical(q$redirect_uri, "http://127.0.0.1:50000/callback")
})

test_that("redirects are checked for target, state and iss before the code is used", {
  redirect = "http://127.0.0.1:50000/callback"
  iss = "https://as.example"
  ok = paste0(redirect, "?code=abc&state=st&iss=https%3A%2F%2Fas.example")
  expect_identical(oauth_parse_redirect(ok, redirect, "st", iss, TRUE), "abc")
  expect_identical(oauth_parse_redirect("code=abc&state=st", redirect, "st", iss, FALSE), "abc")
  expect_error(oauth_parse_redirect(paste0(redirect, "?code=abc&state=bad"), redirect, "st", iss),
               "state", class = "gptr_error_untrusted")
  wrong = paste0(redirect, "?code=abc&state=st&iss=https%3A%2F%2Fevil.example")
  expect_error(oauth_parse_redirect(wrong, redirect, "st", iss), "issuer",
               class = "gptr_error_untrusted")
  expect_error(oauth_parse_redirect(paste0(redirect, "?code=abc&state=st"), redirect, "st", iss,
                                    TRUE), "missing", class = "gptr_error_untrusted")
  expect_error(oauth_parse_redirect("http://127.0.0.1:1/other?code=abc&state=st", redirect, "st",
                                    iss), "another address", class = "gptr_error_untrusted")
  expect_error(oauth_parse_redirect(paste0(redirect, "?error=access_denied&state=st"), redirect,
                                    "st", iss), "declined", class = "gptr_error_provider")
  expect_error(oauth_parse_redirect("", redirect, "st", iss), "nothing",
               class = "gptr_error_untrusted")
})

test_that("oauth_lock_with() serialises, waits for a live holder and breaks stale locks", {
  path = file.path(withr::local_tempdir(), "mcp.json")
  lock = paste0(path, ".lock")
  expect_true(oauth_lock_with(path, function() dir.exists(lock)))
  expect_false(dir.exists(lock))
  dir.create(lock)
  me = paste(Sys.getpid(), format(as.numeric(ps::ps_create_time(ps::ps_handle())), digits = 15))
  writeLines(me, file.path(lock, "pid"))
  expect_error(oauth_lock_with(path, function() "ran", tries = 3L, wait = 0.01),
               class = "gptr_error_timeout")
  unlink(lock, recursive = TRUE)
  skip_on_cran()
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  dead$wait(10000)
  dir.create(lock)
  writeLines(paste(dead$get_pid(), 1), file.path(lock, "pid"))
  expect_identical(oauth_lock_with(path, function() "ran"), "ran")
  expect_false(dir.exists(lock))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "auth-oauth")'`
Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 0 ]`; the first error is `could not find function "url_parts"`.

- [ ] **Step 3: Write the implementation**

Create `R/auth-oauth.R`:

```r
# OAuth 2.1 with PKCE S256 and credential login (REQ-15, REQ-30; contract 6.2, 7.18; IC-71).
#
# Adapted from dev/research/03-pi-ai-providers-auth.md section 5.6 (PKCE checked against the
# RFC 7636 appendix B vector, the loopback receiver, the double-checked locked refresh) and
# dev/research/16-mcp-skills-plugins.md sections 2.9, 3.5 and 5.15 (RFC 9728 discovery, the
# authorization-server metadata order, the iss rule). Report 16's verification-log fixes are
# applied: metadata without code_challenge_methods_supported, or without S256, is refused (#7),
# and the redirect is read by gptr's own listener or paste reader so that `iss` survives (#17).
# httr2 is never used (conventions section 8); every transfer runs on P04's reactor, whose
# handles set followlocation = 0L (IC-64). Layer L0: the MCP layer reaches gptr_login("mcp:")
# through the callback it registers with oauth_hooks_set() at load (architecture 2.2).
# Credentials: refresh tokens and API keys live in P03's credential store (auth.json, 0600);
# access tokens live only in the vault (secret "auth:<key>:access", bound to the resource's
# origin) with their expiry in the store record (contract 11.8).

# ---- URLs, headers, forms (pure) -----------------------------------------------------------

#' Split a URL into scheme, host, port, path and query (the query without "?")
#' @noRd
url_parts = function(url) {
  pat = "^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)([^?#]*)(\\?[^#]*)?"
  m = regmatches(url, regexec(pat, url))[[1L]]
  if (!length(m)) {
    gptr_abort("A URL must start with a scheme such as https://.", "invalid_argument",
               arg = "url", expected = "an absolute URL")
  }
  hostport = sub("^.*@", "", m[3L])
  if (startsWith(hostport, "[")) {
    host = sub("^(\\[[^]]*\\]).*$", "\\1", hostport)
    port = sub("^\\[[^]]*\\]:?", "", hostport)
  } else {
    host = sub(":.*$", "", hostport)
    port = if (grepl(":", hostport, fixed = TRUE)) sub("^[^:]*:", "", hostport) else ""
  }
  list(scheme = tolower(m[2L]), host = tolower(host), port = port, path = m[4L],
       query = sub("^\\?", "", m[5L]))
}

#' One header value from a named list or vector (case-insensitive), or NULL
#' @noRd
hdr_value = function(headers, name) {
  if (is.null(headers) || !length(headers) || is.null(names(headers))) return(NULL)
  i = match(tolower(name), tolower(names(headers)))
  if (is.na(i)) return(NULL)
  as.character(unlist(headers[[i]]))[1L]
}

#' An application/x-www-form-urlencoded body; NULL fields are dropped
#' @noRd
form_encode = function(fields) {
  fields = fields[!vapply(fields, is.null, NA)]
  vals = vapply(fields, function(v) utils::URLencode(as.character(v)[1L], reserved = TRUE), "")
  paste(paste0(names(fields), "=", vals), collapse = "&")
}

#' Parse a query string into a named list of UTF-8 strings
#' @noRd
query_parse = function(q) {
  q = sub("^\\?", "", q %||% "")
  if (is.na(q) || !nzchar(q)) return(json_obj())
  kv = strsplit(strsplit(q, "&", fixed = TRUE)[[1L]], "=", fixed = TRUE)
  dec = function(x) as_utf8(utils::URLdecode(gsub("+", " ", x, fixed = TRUE)))
  keys = vapply(kv, function(p) dec(p[1L]), "")
  vals = lapply(kv, function(p) if (length(p) < 2L) "" else dec(paste(p[-1L], collapse = "=")))
  stats::setNames(vals, keys)
}

#' base64url without padding (RFC 4648 section 5)
#' @noRd
b64url = function(bytes) {
  x = gsub("[\r\n]", "", jsonlite::base64_enc(as.raw(bytes)))
  chartr("+/", "-_", sub("=+$", "", x))
}

#' Parse the quoted parameters of a WWW-Authenticate challenge
#' @noRd
oauth_parse_challenge = function(h) {
  if (is.null(h) || !nzchar(h)) return(list())
  kv = regmatches(h, gregexpr("([A-Za-z_]+)=\"([^\"]*)\"", h))[[1L]]
  if (!length(kv)) return(list())
  stats::setNames(as.list(sub("^[^=]+=\"(.*)\"$", "\\1", kv)), sub("=.*$", "", kv))
}

#' Refuse authorization-server metadata for another issuer, or without S256 PKCE (IC-71)
#' @noRd
oauth_check_metadata = function(meta, issuer) {
  refuse = function(why) {
    gptr_abort(paste0("The authorization server ", issuer, " ", why, "; gptr refuses to sign in."),
               "untrusted", what = "authorization server metadata", path = NA_character_,
               origin = issuer)
  }
  if (!is.list(meta) || !identical(meta$issuer, issuer)) {
    refuse("returned metadata for another issuer")
  }
  methods = unlist(meta$code_challenge_methods_supported)
  if (is.null(methods)) {
    refuse("does not declare PKCE support (code_challenge_methods_supported is missing)")
  }
  if (!"S256" %in% methods) refuse("does not support S256 PKCE")
  if (!is.character(meta$authorization_endpoint) || !is.character(meta$token_endpoint)) {
    refuse("does not name an authorization and a token endpoint")
  }
  invisible(meta)
}

#' The authorization URL of the code flow (state, PKCE S256, RFC 8707 resource)
#' @noRd
oauth_authorize_url = function(meta, client_id, redirect_uri, scope, state, challenge,
                               resource = NULL) {
  q = form_encode(list(response_type = "code", client_id = client_id, redirect_uri = redirect_uri,
                       scope = if (length(scope) && nzchar(scope)) scope, state = state,
                       code_challenge = challenge, code_challenge_method = "S256",
                       resource = resource))
  sep = if (grepl("?", meta$authorization_endpoint, fixed = TRUE)) "&" else "?"
  paste0(meta$authorization_endpoint, sep, q)
}

#' Validate a redirect (a full URL, or the pasted query) and return the authorization code: the
#' redirect target, the state and, per RFC 9207, `iss` are checked before the code is redeemed
#' @noRd
oauth_parse_redirect = function(input, redirect_uri, state, issuer, iss_supported = FALSE) {
  input = trimws(as.character(input %||% ""))
  untrusted = function(why) {
    gptr_abort(paste0("The sign-in redirect was refused: ", why, "."), "untrusted",
               what = "OAuth redirect", path = NA_character_, origin = issuer)
  }
  if (!length(input) || is.na(input[1L]) || !nzchar(input[1L])) untrusted("nothing was received")
  input = input[1L]
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*://", input)) {
    got = url_parts(input)
    want = url_parts(redirect_uri)
    keys = c("scheme", "host", "port", "path")
    if (!identical(got[keys], want[keys])) {
      untrusted("it went to another address than the one gptr registered")
    }
    q = query_parse(got$query)
  } else {
    q = query_parse(input)
  }
  if (!is.null(q$error)) {
    gptr_abort(paste0("The sign-in was declined: ", q$error_description %||% q$error, "."),
               "provider", provider = issuer, status = NA_integer_, error_type = q$error)
  }
  if (!identical(q$state, state)) untrusted("the state parameter does not match")
  if (!is.null(q$iss)) {
    if (!identical(q$iss, issuer)) untrusted("it came from another issuer (iss)")
  } else if (isTRUE(iss_supported)) {
    untrusted("the issuer (iss) is missing although the server promises to send it")
  }
  if (is.null(q$code) || !nzchar(q$code)) untrusted("it carries no authorization code")
  q$code
}

# ---- Suggests, randomness, PKCE, locks -----------------------------------------------------

#' Abort with gptr_error_missing_package unless a Suggests package loads; loading never moves
#' the user's .Random.seed (IC-61)
#' @noRd
oauth_need = function(pkg, feature) {
  ok = with_seed_preserved(requireNamespace(pkg, quietly = TRUE))
  if (!isTRUE(ok)) {
    gptr_abort(paste0(feature, " needs the '", pkg, "' package; install it with ",
                      "install.packages(\"", pkg, "\")."), "missing_package", package = pkg,
               feature = feature)
  }
  invisible(TRUE)
}

#' A cryptographically random hex string of n bytes (openssl; never R's RNG, IC-61)
#' @noRd
rand_hex = function(n) {
  oauth_need("openssl", "A random sign-in token")
  paste(as.character(openssl::rand_bytes(as.integer(n))), collapse = "")
}

#' A PKCE pair (RFC 7636, S256); 32 random bytes give a 43-character verifier
#' @noRd
pkce_new = function(verifier = NULL) {
  oauth_need("openssl", "OAuth sign-in")
  if (is.null(verifier)) verifier = b64url(openssl::rand_bytes(32L))
  list(verifier = verifier, challenge = b64url(openssl::sha256(charToRaw(verifier))),
       method = "S256")
}

#' Run fun() holding the short mkdir lock `<path>.lock/` (IC-71: pid and process creation time,
#' `tries` x `wait` seconds, a stale lock is broken with P03's auth_lock_stale()); used for the
#' OAuth refresh and for gptr's mcp.json
#' @noRd
oauth_lock_with = function(path, fun, tries = 50L, wait = 0.1) {
  lock = paste0(path, ".lock")
  dir.create(dirname(lock), recursive = TRUE, showWarnings = FALSE)
  got = FALSE
  for (i in seq_len(tries)) {
    if (dir.create(lock, showWarnings = FALSE)) {
      got = TRUE
      break
    }
    if (auth_lock_stale(lock)) {
      unlink(lock, recursive = TRUE, force = TRUE)
      next
    }
    Sys.sleep(wait)
  }
  if (!got) {
    gptr_abort(paste0("Could not lock ", basename(path), ": another R process holds the lock."),
               "timeout", seconds = tries * wait, what = "lock")
  }
  on.exit(unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  created = tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle())), error = function(e) NA)
  writeLines(paste(Sys.getpid(), format(created, digits = 15)), file.path(lock, "pid"))
  fun()
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "auth-oauth")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 47 ]`

- [ ] **Step 5: Commit**

```bash
git add R/auth-oauth.R tests/testthat/test-auth-oauth.R
git commit -m "feat(auth): add the OAuth building blocks (PKCE S256, metadata and redirect checks, lock)"
```


---

### Task 2: OAuth sign-in: discovery, flows, the locked refresh, `gptr_login()` and `gptr_logout()`

**Files:**
- Modify: `R/auth-oauth.R` (append)
- Create: `tests/testthat/helper-mcp-server.R`, `tests/testthat/fixtures/mcp/oauth.R`, `tests/testthat/fixtures/mcp/browser.R`
- Test: `tests/testthat/test-auth-oauth.R` (append)
- Generated: `NAMESPACE`, `man/gptr_login.Rd`

**Interfaces:**
- Consumes: Task 1; P01 `json_encode()`, `json_decode()`, `raw_to_utf8()`, `port_candidates()`, `gptr_can_prompt()`, `gptr_is_interactive()`, `gptr_user_dir()`, `hash_sha256()`; P02 `registry_get()`, `ext_control_guard()`; P03 `secret_register()`, `secret_value()`, `secret_lookup()`, `secrets_state()` (internal), `auth_store_get()`, `auth_store_set()`, `auth_store_remove()`, `vault_reset()` (tests); P04 `reactor_http()`, `reactor_pump()`, `reactor_cancel()`, `url_origin()`; P11 the `ui.get` service (`notify()`, `input(prompt, default, secret)`); Suggests httpuv (`startServer()`, `stopServer()`), later; tests: P11 `local_scripted_ui()`.
- Produces: the exports `gptr_login(provider, method = c("auto", "oauth", "key"))` -> `invisible(TRUE)` and `gptr_logout(provider)` -> `invisible(<lgl: something removed>)`, removing the stored credential and deactivating its in-memory access token (04 §6.2; conditions `noninteractive`, `invalid_argument`, `missing_package`, `provider`, `untrusted`; emits `secret_registered` through P03); internal `oauth_flow(issuer_or_provider, scopes = NULL, client = NULL)` (04 §7.18) -> the credential record to store; `oauth_access(key, origin, force = FALSE)` -> the Authorization value `list("Bearer ", <gptr_secret>)` or `NULL` (used by Task 5; `NULL` as well when the record's `resource` lies on another origin); `oauth_refresh(key, origin)`; `oauth_forget_access(key)` -> lgl(1); `oauth_discover(resource_url, www_authenticate = NULL)`; `oauth_http(url, method, headers, body, timeout)`; `oauth_hooks` and `oauth_hooks_set(target = NULL)` (Task 7 registers `target(name) -> list(url, oauth)`); `oauth_access_name(key)` = `"auth:<key>:access"`; `oauth_now_ms()`; test helpers `mcp_fixture_libs()`, `local_user_dirs()`, `mcp_fixture_dir`, `mcp_fixture_http()`, `local_oauth_mock(pkce = "yes", iss = "good")`, `local_browser()`, `local_login_target(urls)`.

Credentials (04 §11.8): `gptr_login()` stores `{"type": "oauth", "issuer", "client_id", "token_endpoint", "resource", "scope", "expires", "refresh"}` or `{"type": "api_key", "key"}` (an MCP server's hand-entered token also keeps its `resource`) through P03's `auth_store_set()`, which writes `auth.json` 0600 and registers every secret field. Access tokens are never written: they are registered in the vault as `auth:<key>:access`, bound to the resource's origin, and found again with `secret_lookup()` while the stored `expires` (epoch ms, five minutes early) lies more than a minute ahead. A record with a `resource` is handed only to that resource's origin. A refresh re-reads the record under a lock (`oauth-<16 hex>.lock` in the user config directory), so two R processes never redeem one rotating refresh token (report 03's double-checked refresh); its token request times out after 20 s, inside the 30 s after which P03's rule calls a lock stale. The refresh token is materialised for the token endpoint's origin only, as RFC 6749 §6 requires a form field (ambiguity 2). `gptr_logout()` removes the stored record and deactivates the in-memory access token (the value stays registered, so it is still redacted). `gptr_login("mcp:<name>")` asks the MCP layer for the server's URL through the callback in `oauth_hooks`, tries RFC 9728 discovery (refusing metadata that names another resource, RFC 9728 §3.3) and falls back to masked token entry when the server publishes no metadata. The loopback listener binds 127.0.0.1 on a port from `port_candidates()` with the seed preserved; without httpuv and later the user pastes the address their browser ended on, and gptr parses it itself so `iss` is checked either way. OpenRouter's PKCE flow (report 03 §3, Pi `openrouter.ts:19-22`) returns a permanent API key; its protocol has no `state`, so the redirect path carries a random segment.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/mcp/oauth.R` (an authorization server and a protected MCP resource on 127.0.0.1; it verifies the PKCE challenge and can omit `code_challenge_methods_supported` or send a wrong `iss`):

```r
# OAuth 2.1 authorization server and protected MCP resource for gptr's tests (127.0.0.1 only).
# Adapted from dev/research/03-pi-ai-providers-auth.md 5.6 (a mock server verifying the PKCE
# challenge) and 16 section 3.5 (discovery documents, the WWW-Authenticate challenge).
# Usage: Rscript --vanilla oauth.R --port=N --pkce=yes|no --iss=good|wrong|absent --log=<path>
args = commandArgs(trailingOnly = TRUE)
arg = function(name, default = NULL) {
  hit = grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1L]) else default
}
# base R has `%||%` only from R 4.4.0 (the fixture runs on R >= 4.2); an operator keeps its name
`%||%` = function(a, b) if (is.null(a)) b else a # nolint: object_name_linter.
port = as.integer(arg("port"))
pkce = arg("pkce", "yes")
iss_mode = arg("iss", "good")
log_path = arg("log", tempfile())
base = paste0("http://127.0.0.1:", port)
state = new.env()
state$challenge = NULL
state$redirect = NULL
state$tokens = c("access-1", "access-2", "access-3")
json = function(status, x, headers = list()) {
  list(status = status, headers = c(list(`Content-Type` = "application/json"), headers),
       body = as.character(jsonlite::toJSON(x, auto_unbox = TRUE)))
}
b64url = function(bytes) {
  chartr("+/", "-_", gsub("=+$", "", gsub("[\r\n]", "", jsonlite::base64_enc(bytes))))
}
form = function(txt) {
  txt = sub("^\\?", "", txt)
  if (!nzchar(txt)) return(list())
  kv = strsplit(strsplit(txt, "&", fixed = TRUE)[[1L]], "=", fixed = TRUE)
  vals = lapply(kv, function(p) {
    utils::URLdecode(gsub("+", " ", paste(p[-1L], collapse = "="), fixed = TRUE))
  })
  stats::setNames(vals, vapply(kv, `[[`, "", 1L))
}
log = function(path, what) {
  cat(as.character(jsonlite::toJSON(list(path = path, what = what), auto_unbox = TRUE)), "\n",
      sep = "", file = log_path, append = TRUE)
}
authorized = function(req) {
  a = req$HTTP_AUTHORIZATION %||% ""
  a %in% paste("Bearer", c(state$tokens, "manual-token-123"))
}
mcp = function(req, body) {
  if (!authorized(req)) {
    log("/mcp", "401")
    challenge = paste0("Bearer realm=\"OAuth\", resource_metadata=\"", base,
                       "/.well-known/oauth-protected-resource/mcp\", scope=\"read\"")
    return(json(401L, list(error = "invalid_token"), list(`WWW-Authenticate` = challenge)))
  }
  msg = jsonlite::fromJSON(body, simplifyVector = FALSE)
  log("/mcp", msg$method %||% "notification")
  if (is.null(msg$id)) return(list(status = 202L, headers = list(), body = ""))
  empty = structure(list(), names = character())
  res = switch(msg$method,
    `server/discover` = list(resultType = "complete", supportedVersions = I("2026-07-28"),
                             capabilities = list(tools = empty)),
    `tools/list` = list(resultType = "complete", tools = list(list(
      name = "whoami", description = "Who am I?",
      inputSchema = list(type = "object", properties = empty)))),
    `tools/call` = list(resultType = "complete",
                        content = list(list(type = "text", text = "you are signed in"))),
    NULL)
  if (is.null(res)) {
    return(json(404L, list(jsonrpc = "2.0", id = msg$id,
                           error = list(code = -32601L, message = "Method not found"))))
  }
  json(200L, list(jsonrpc = "2.0", id = msg$id, result = res))
}
app = list(call = function(req) {
  path = req$PATH_INFO
  body = rawToChar(req$rook.input$read())
  if (identical(path, "/mcp")) return(mcp(req, body))
  if (identical(path, "/.well-known/oauth-protected-resource/mcp")) {
    log(path, "prm")
    return(json(200L, list(resource = paste0(base, "/mcp"), authorization_servers = I(base),
                           scopes_supported = I("read"))))
  }
  if (identical(path, "/.well-known/oauth-authorization-server")) {
    log(path, "as")
    meta = list(issuer = base, authorization_endpoint = paste0(base, "/authorize"),
                token_endpoint = paste0(base, "/token"),
                registration_endpoint = paste0(base, "/register"), scopes_supported = I("read"),
                authorization_response_iss_parameter_supported = !identical(iss_mode, "absent"))
    if (identical(pkce, "yes")) meta$code_challenge_methods_supported = I("S256")
    return(json(200L, meta))
  }
  if (identical(path, "/register")) {
    x = jsonlite::fromJSON(body, simplifyVector = FALSE)
    log(path, x$application_type %||% "none")
    return(json(201L, list(client_id = "client-1", redirect_uris = x$redirect_uris)))
  }
  if (identical(path, "/authorize") || identical(path, "/auth")) {
    q = form(req$QUERY_STRING %||% "")
    state$challenge = q$code_challenge
    state$redirect = q$redirect_uri %||% q$callback_url
    log(path, q$code_challenge_method %||% "none")
    extra = switch(iss_mode,
                   good = paste0("&iss=", utils::URLencode(base, reserved = TRUE)),
                   wrong = "&iss=http%3A%2F%2Fevil.example",
                   "")
    loc = if (identical(path, "/auth")) {
      paste0(state$redirect, "?code=or-code-1")
    } else {
      paste0(state$redirect, "?code=code-1&state=",
             utils::URLencode(q$state %||% "", reserved = TRUE), extra)
    }
    return(list(status = 302L, headers = list(Location = loc), body = ""))
  }
  if (identical(path, "/token")) {
    f = form(body)
    log(path, f$grant_type %||% "none")
    if (identical(f$grant_type, "authorization_code")) {
      verified = identical(b64url(openssl::sha256(charToRaw(f$code_verifier %||% ""))),
                           state$challenge)
      ok = identical(f$code, "code-1") && identical(f$redirect_uri, state$redirect) && verified
      if (!ok) return(json(400L, list(error = "invalid_grant")))
      return(json(200L, list(access_token = "access-1", refresh_token = "refresh-1",
                             expires_in = 3600, token_type = "Bearer")))
    }
    if (identical(f$grant_type, "refresh_token")) {
      n = match(f$refresh_token, c("refresh-1", "refresh-2"))
      if (is.na(n)) return(json(400L, list(error = "invalid_grant")))
      return(json(200L, list(access_token = state$tokens[n + 1L],
                             refresh_token = paste0("refresh-", n + 1L), expires_in = 3600)))
    }
    return(json(400L, list(error = "unsupported_grant_type")))
  }
  if (identical(path, "/api/v1/auth/keys")) {
    x = jsonlite::fromJSON(body, simplifyVector = FALSE)
    log(path, "key")
    verified = identical(b64url(openssl::sha256(charToRaw(x$code_verifier %||% ""))),
                         state$challenge)
    if (!identical(x$code, "or-code-1") || !verified) {
      return(json(400L, list(error = "invalid_code")))
    }
    return(json(200L, list(key = paste0("sk-or-v1-", "mockkeyabcdefghijklmnopqrst"))))
  }
  json(404L, list(error = "not_found"))
})
srv = tryCatch(httpuv::startServer("127.0.0.1", port, app), error = function(e) NULL)
if (is.null(srv)) quit(save = "no", status = 3L)
cat("READY", port, "\n")
flush(stdout())
parent = suppressWarnings(as.integer(Sys.getenv("GPTR_FIXTURE_PARENT")))
repeat {
  httpuv::service(100)
  alive = is.na(parent) ||
    tryCatch(ps::ps_is_running(ps::ps_handle(parent)), error = function(e) FALSE)
  if (!alive) break
}
```

Create `tests/testthat/fixtures/mcp/browser.R`:

```r
# A stand-in browser for gptr's OAuth tests: it opens the sign-in URL and follows the redirects
# to gptr's loopback listener, then prints the final status.
# Usage: Rscript --vanilla browser.R <url>
url = commandArgs(trailingOnly = TRUE)[1L]
r = tryCatch(curl::curl_fetch_memory(url, handle = curl::new_handle(followlocation = TRUE)),
             error = function(e) NULL)
cat(if (is.null(r)) "failed" else r$status_code, "\n")
```

Create `tests/testthat/helper-mcp-server.R`:

```r
# MCP and OAuth test helpers (P18; contract 12.2). Fixture scripts live in fixtures/mcp/: the
# pure-R MCP server speaking either era over stdio or Streamable HTTP on 127.0.0.1 (server.R),
# the OAuth authorization server and protected resource (oauth.R), a stand-in browser
# (browser.R) and a stand-in CLI child that speaks HTTP MCP with its GPTR_MCP_TOKEN (client.R).
# Children start with rscript_path() (IC-60), run only off CRAN, and stop when the test ends.

# The library path of this process, for children started with --vanilla
mcp_fixture_libs = function() paste(.libPaths(), collapse = .Platform$path.sep)

# Fresh user directories (config, cache) and an empty vault for the calling test: credential
# stores, mcp.json files, caches and registered secrets of one test never reach another (P03's
# test convention: vault_reset() before and after)
local_user_dirs = function(.env = parent.frame()) {
  root = withr::local_tempdir("gptr-user-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = file.path(root, "config"),
                      R_USER_CACHE_DIR = file.path(root, "cache"), .local_envir = .env)
  vault_reset()
  withr::defer(vault_reset(), envir = .env)
  invisible(root)
}

# The fixture scripts, resolved once while the working directory is tests/testthat (tests may
# change it with local_project())
mcp_fixture_dir = normalizePath(testthat::test_path("fixtures", "mcp"))

# Start an HTTP fixture script on a free 127.0.0.1 port (port_candidates(), IC-61) and wait for
# its READY line; skips the test when no port works
mcp_fixture_http = function(script, args, .env) {
  for (port in port_candidates(20L)) {
    p = processx::process$new(rscript_path(),
                              c("--vanilla", script, args, paste0("--port=", port)),
                              stdout = "|", stderr = "|", cleanup_tree = TRUE,
                              env = c("current", R_LIBS = mcp_fixture_libs(),
                                      GPTR_FIXTURE_PARENT = Sys.getpid()))
    ready = FALSE
    t0 = Sys.time()
    while (p$is_alive() && difftime(Sys.time(), t0, units = "secs") < 30) {
      p$poll_io(200L)
      if (any(grepl("^READY", p$read_output_lines()))) {
        ready = TRUE
        break
      }
    }
    if (ready) {
      withr::defer(p$kill_tree(), envir = .env)
      return(list(process = p, port = port))
    }
    p$kill_tree()
  }
  testthat::skip("could not start an HTTP fixture on a free port")
}

# The OAuth authorization server and protected MCP resource (fixtures/mcp/oauth.R):
# list(url (the resource, ".../mcp"), base (the issuer), port, log = function() df(path, what))
local_oauth_mock = function(pkce = "yes", iss = "good", .env = parent.frame()) {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("httpuv")
  testthat::skip_if_not_installed("later")
  testthat::skip_if_not_installed("openssl")
  log = withr::local_tempfile(fileext = ".jsonl", .local_envir = .env)
  srv = mcp_fixture_http(file.path(mcp_fixture_dir, "oauth.R"),
                         c(paste0("--pkce=", pkce), paste0("--iss=", iss), paste0("--log=", log)),
                         .env)
  base = paste0("http://127.0.0.1:", srv$port)
  list(url = paste0(base, "/mcp"), base = base, port = srv$port,
       log = function() {
         if (!file.exists(log)) return(data.frame(path = character(), what = character()))
         rows = lapply(readLines(log, warn = FALSE, encoding = "UTF-8"), function(l) {
           as.data.frame(jsonlite::fromJSON(l), stringsAsFactors = FALSE)
         })
         do.call(rbind, rows)
       })
}

# A stand-in browser: oauth_open_browser() starts fixtures/mcp/browser.R, which follows the
# redirects of the sign-in URL to gptr's loopback listener; returns the record of opened URLs
local_browser = function(.env = parent.frame()) {
  seen = new.env(parent = emptyenv())
  seen$urls = character()
  seen$procs = list()
  script = file.path(mcp_fixture_dir, "browser.R")
  testthat::local_mocked_bindings(oauth_open_browser = function(url) {
    seen$urls = c(seen$urls, url)
    seen$procs[[length(seen$procs) + 1L]] = processx::process$new(
      rscript_path(), c("--vanilla", script, url), stdout = "|", stderr = "|",
      env = c("current", R_LIBS = mcp_fixture_libs()), cleanup_tree = TRUE)
    invisible(NULL)
  }, .env = .env)
  withr::defer(for (p in seen$procs) p$kill_tree(), envir = .env)
  invisible(seen)
}

# Point gptr_login("mcp:<name>") at fixed URLs for the calling test: `urls` is a named chr
# (server name -> resource URL); the previous login-target callback is restored afterwards
local_login_target = function(urls, .env = parent.frame()) {
  old = get0("target", envir = oauth_hooks, inherits = FALSE)
  oauth_hooks_set(target = function(name) list(url = urls[[name]], oauth = list()))
  withr::defer({
    if (is.null(old)) {
      if (exists("target", envir = oauth_hooks)) rm("target", envir = oauth_hooks)
    } else {
      oauth_hooks_set(target = old)
    }
  }, envir = .env)
  invisible(urls)
}
```

Append to the end of `tests/testthat/test-auth-oauth.R`:

```r
test_that("gptr_login() signs in to an MCP server: PKCE S256, DCR, loopback redirect, 0600 store", {
  local_user_dirs()
  mock = local_oauth_mock()
  local_login_target(c(secure = mock$url))
  browser = local_browser()
  ui = local_scripted_ui()
  withr::local_seed(42)
  seed = get(".Random.seed", envir = globalenv())
  expect_invisible(gptr_login("mcp:secure"))
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_length(browser$urls, 1L)
  expect_true(any(grepl("Sign in at:", ui$log$prompt, fixed = TRUE)))
  rec = auth_store_get("mcp:secure")
  expect_identical(rec$type, "oauth")
  expect_identical(rec$client_id, "client-1")
  expect_identical(rec$issuer, mock$base)
  expect_identical(secret_value(rec$refresh, mock$base), "refresh-1")
  expect_null(rec$access)
  path = file.path(gptr_user_dir("config"), "auth.json")
  txt = paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl("access-1", txt, fixed = TRUE))
  if (.Platform$OS.type == "unix") expect_identical(format(file.info(path)$mode), "600")
  log = mock$log()
  expect_identical(log$what[log$path == "/register"], "native")
  expect_identical(log$what[log$path == "/authorize"], "S256")
  expect_identical(log$what[log$path == "/token"], "authorization_code")
  header = oauth_access("mcp:secure", url_origin(mock$url))
  expect_identical(header[[1L]], "Bearer ")
  expect_s3_class(header[[2L]], "gptr_secret")
  expect_identical(secret_value(header[[2L]], mock$url), "access-1")
  expect_error(secret_value(header[[2L]], "https://evil.example"), class = "gptr_error_untrusted")
})

test_that("an expired access token is refreshed under the lock; a stale lock is broken", {
  skip_on_cran()
  local_user_dirs()
  mock = local_oauth_mock()
  local_login_target(c(secure = mock$url))
  local_browser()
  local_scripted_ui()
  gptr_login("mcp:secure")
  rec = auth_store_get("mcp:secure")
  rec$refresh = secret_value(rec$refresh, mock$base)
  rec$expires = 0
  auth_store_set("mcp:secure", rec)
  lock = file.path(gptr_user_dir("config"),
                   paste0("oauth-", substr(hash_sha256("mcp:secure"), 1L, 16L), ".lock"))
  dead = processx::process$new(rscript_path(), c("--vanilla", "-e", "invisible(0)"))
  dead$wait(10000)
  dir.create(lock)
  writeLines(paste(dead$get_pid(), 1), file.path(lock, "pid"))
  header = oauth_access("mcp:secure", url_origin(mock$url))
  expect_identical(secret_value(header[[2L]], mock$url), "access-2")
  expect_false(dir.exists(lock))
  expect_identical(secret_value(auth_store_get("mcp:secure")$refresh, mock$base), "refresh-2")
  expect_identical(tail(mock$log()$what[mock$log()$path == "/token"], 1L), "refresh_token")
  again = oauth_access("mcp:secure", url_origin(mock$url))
  expect_identical(secret_value(again[[2L]], mock$url), "access-2")
  expect_identical(sum(mock$log()$what == "refresh_token"), 1L)
})

test_that("authorization servers without S256 PKCE or with a wrong iss are refused (IC-71)", {
  local_user_dirs()
  mock = local_oauth_mock(pkce = "no")
  mock2 = local_oauth_mock(iss = "wrong")
  local_login_target(c(nopkce = mock$url, badiss = mock2$url))
  local_browser()
  local_scripted_ui()
  expect_error(gptr_login("mcp:nopkce"), "PKCE", class = "gptr_error_untrusted")
  expect_false("/authorize" %in% mock$log()$path)
  expect_error(gptr_login("mcp:badiss"), "issuer", class = "gptr_error_untrusted")
  expect_true("/authorize" %in% mock2$log()$path)
  expect_false("/token" %in% mock2$log()$path)
  expect_null(auth_store_get("mcp:nopkce"))
  expect_null(auth_store_get("mcp:badiss"))
})

test_that("a server without OAuth metadata gets masked token entry", {
  local_user_dirs()
  mock = local_oauth_mock()
  local_login_target(c(plain = paste0(mock$base, "/plain")))
  ui = local_scripted_ui(list("manual-token-123"))
  gptr_login("mcp:plain")
  expect_identical(ui$log$method, "input")
  rec = auth_store_get("mcp:plain")
  expect_identical(rec$type, "api_key")
  expect_identical(rec$resource, paste0(mock$base, "/plain"))
  header = oauth_access("mcp:plain", mock$base)
  expect_identical(secret_value(header[[2L]], mock$base), "manual-token-123")
  expect_null(oauth_access("mcp:plain", "https://elsewhere.example"))
  expect_error(gptr_login("mcp:plain", method = "oauth"), "does not offer OAuth",
               class = "gptr_error_invalid_argument")
})

test_that("protected-resource metadata naming another resource is refused (RFC 9728)", {
  local_mocked_bindings(oauth_get_json = function(url) {
    list(resource = "https://other.example/mcp", authorization_servers = list("https://as.example"))
  })
  expect_error(oauth_discover("https://mcp.example/mcp"), "another resource",
               class = "gptr_error_untrusted")
})

test_that("key entry stores an API key; gptr_logout() removes it; no person means no login", {
  local_user_dirs()
  key = paste0("sk-or-v1-", "testkeyabcdefghijklmnopqrstuv")
  local_scripted_ui(list(key))
  gptr_login("openrouter", method = "key")
  rec = auth_store_get("openrouter")
  expect_identical(rec$type, "api_key")
  expect_false(grepl("testkeyabcdef", redact(key), fixed = TRUE))
  expect_true(gptr_logout("openrouter"))
  expect_null(auth_store_get("openrouter"))
  expect_false(gptr_logout("openrouter"))
  withr::local_options(gptr.interactive = FALSE)
  expect_error(gptr_login("openrouter"), class = "gptr_error_noninteractive")
  expect_error(gptr_login("nope", method = "key"), class = "gptr_error_noninteractive")
  withr::local_options(gptr.interactive = TRUE)
  expect_error(gptr_login("nope", method = "key"), "Unknown provider",
               class = "gptr_error_invalid_argument")
})

test_that("the OpenRouter-style PKCE key exchange stores the returned key", {
  local_user_dirs()
  mock = local_oauth_mock()
  local_mocked_bindings(oauth_builtin_flows = function() {
    list(openrouter = list(authorize = paste0(mock$base, "/auth"),
                           token = paste0(mock$base, "/api/v1/auth/keys"), origin = mock$base))
  })
  local_browser()
  local_scripted_ui()
  gptr_login("openrouter")
  expect_identical(secret_value(auth_store_get("openrouter")$key, NULL),
                   paste0("sk-or-v1-", "mockkeyabcdefghijklmnopqrst"))
  expect_identical(mock$log()$what[mock$log()$path == "/auth"], "S256")
  expect_true("/api/v1/auth/keys" %in% mock$log()$path)
  gptr_logout("openrouter")
})

test_that("without httpuv and later the redirect is pasted, iss included", {
  skip_if_not_installed("openssl")
  local_mocked_bindings(oauth_loopback_ok = function() FALSE)
  ui = local_scripted_ui(list("http://127.0.0.1:1/x"))
  cb = oauth_redirect_setup(port = 50111L)
  expect_identical(cb$redirect_uri, "http://127.0.0.1:50111/callback")
  expect_identical(cb$wait(), "http://127.0.0.1:1/x")
  expect_identical(ui$log$method, "input")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "auth-oauth")'`
Expected: `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 47 ]`; the first error is `object 'oauth_hooks' not found` (raised by `local_login_target()`); the Task 1 tests still pass.

- [ ] **Step 3: Write the implementation**

Append to the end of `R/auth-oauth.R`:

```r
# ---- HTTP on the reactor, discovery, client registration --------------------------------------

#' One HTTP exchange on the reactor (followlocation = 0L, one attempt; IC-64):
#' list(status, headers, body, error). A non-2xx answer arrives as `error` carrying its status.
#' @noRd
oauth_http = function(url, method = "GET", headers = list(), body = NULL, timeout = 30) {
  st = new.env(parent = emptyenv())
  st$done = FALSE
  st$status = NA_integer_
  st$headers = list()
  st$chunks = list()
  st$error = NULL
  spec = list(url = url, method = method, headers = headers, body = body,
              first_byte_timeout = timeout, idle_timeout = timeout)
  id = reactor_http(spec,
    on_bytes = function(raw) {
      st$chunks[[length(st$chunks) + 1L]] = raw
    },
    on_done = function(status, headers) {
      st$status = as.integer(status)
      st$headers = headers
      st$done = TRUE
    },
    on_fail = function(cnd) {
      st$error = cnd
      st$status = suppressWarnings(as.integer(cnd$status %||% NA_integer_))
      st$done = TRUE
    },
    on_headers = function(status, headers) {
      st$status = as.integer(status)
      st$headers = headers
    },
    retry = list(max_attempts = 1L))
  if (!isTRUE(reactor_pump(until = function() isTRUE(st$done), slice_ms = 50L,
                           timeout = timeout + 5))) {
    reactor_cancel(id)
    gptr_abort(paste0("No answer from ", url_origin(url), " within ", timeout, " s."), "timeout",
               seconds = timeout, what = "OAuth request")
  }
  body = if (length(st$chunks)) raw_to_utf8(do.call(c, st$chunks)) else ""
  list(status = st$status, headers = st$headers, body = body, error = st$error)
}

#' GET a JSON document; NULL unless the answer is a 2xx JSON object
#' @noRd
oauth_get_json = function(url) {
  r = tryCatch(oauth_http(url, "GET", headers = list(Accept = "application/json")),
               gptr_error = function(e) NULL)
  if (is.null(r) || !is.null(r$error) || !isTRUE(r$status >= 200L && r$status < 300L)) {
    return(NULL)
  }
  x = tryCatch(json_decode(r$body), error = function(e) NULL)
  if (is.list(x) && length(x) && !is.null(names(x))) x else NULL
}

#' Validated authorization-server metadata of an issuer (RFC 8414 and OpenID discovery, in the
#' order of the MCP authorization specification; report 16 section 3.5)
#' @noRd
oauth_as_metadata = function(issuer) {
  u = url_parts(issuer)
  base = url_origin(issuer)
  path = sub("/$", "", u$path)
  cands = if (nzchar(path)) {
    c(paste0(base, "/.well-known/oauth-authorization-server", path),
      paste0(base, "/.well-known/openid-configuration", path),
      paste0(base, path, "/.well-known/openid-configuration"))
  } else {
    c(paste0(base, "/.well-known/oauth-authorization-server"),
      paste0(base, "/.well-known/openid-configuration"))
  }
  for (m in cands) {
    meta = oauth_get_json(m)
    if (!is.null(meta)) return(oauth_check_metadata(meta, issuer))
  }
  gptr_abort(paste0("No OAuth metadata was found for the authorization server ", issuer, "."),
             "provider", provider = issuer, status = NA_integer_)
}

#' RFC 9728 discovery for a protected resource: the challenge's resource_metadata, then the two
#' well-known URLs; NULL when the resource publishes no metadata (it offers no OAuth). Metadata
#' whose `resource` is not the URL gptr asked about is refused (RFC 9728 section 3.3), so a
#' server cannot send the user to sign in for another resource.
#' @noRd
oauth_discover = function(resource_url, www_authenticate = NULL) {
  ch = oauth_parse_challenge(www_authenticate)
  base = url_origin(resource_url)
  path = sub("/$", "", url_parts(resource_url)$path)
  cands = unique(c(ch$resource_metadata,
                   if (nzchar(path)) paste0(base, "/.well-known/oauth-protected-resource", path),
                   paste0(base, "/.well-known/oauth-protected-resource")))
  prm = NULL
  for (p in cands) {
    prm = oauth_get_json(p)
    if (!is.null(prm) && length(prm$authorization_servers)) break
    prm = NULL
  }
  if (is.null(prm)) return(NULL)
  named = as.character(unlist(prm$resource))[1L]
  same = function(a, b) identical(sub("/$", "", a), sub("/$", "", b))
  if (!is.na(named) && !same(named, resource_url)) {
    gptr_abort(paste0("The protected-resource metadata of ", base, " names another resource (",
                      named, "); gptr refuses to sign in."), "untrusted",
               what = "protected resource metadata", path = NA_character_, origin = base)
  }
  issuer = as.character(unlist(prm$authorization_servers))[1L]
  scopes = if (!is.null(ch$scope)) {
    strsplit(ch$scope, " ", fixed = TRUE)[[1L]]
  } else {
    as.character(unlist(prm$scopes_supported))
  }
  list(resource = resource_url, issuer = issuer, metadata = oauth_as_metadata(issuer),
       scopes = scopes)
}

#' POST a form to a token endpoint; the parsed token response, or gptr_error_provider
#' @noRd
oauth_token_request = function(endpoint, fields, timeout = 30) {
  r = oauth_http(endpoint, "POST",
                 headers = list(Accept = "application/json",
                                `Content-Type` = "application/x-www-form-urlencoded"),
                 body = form_encode(fields), timeout = timeout)
  tok = if (is.null(r$error)) tryCatch(json_decode(r$body), error = function(e) NULL)
  if (!is.list(tok) || !is.character(tok$access_token)) {
    gptr_abort(paste0("The token endpoint of ", url_origin(endpoint), " refused the request (HTTP ",
                      format(r$status), ")."), "provider", provider = url_origin(endpoint),
               status = r$status)
  }
  tok
}

#' Dynamic client registration (RFC 7591, application_type "native"); the client_id, or NULL
#' when the server has no registration endpoint
#' @noRd
oauth_register_client = function(meta, redirect_uri, scope) {
  if (!is.character(meta$registration_endpoint)) return(NULL)
  body = list(client_name = "gptr (R)", redirect_uris = I(redirect_uri),
              grant_types = I(c("authorization_code", "refresh_token")),
              response_types = I("code"), token_endpoint_auth_method = "none",
              application_type = "native", software_id = "gptr",
              software_version = as.character(utils::packageVersion("gptr")))
  if (length(scope) && nzchar(scope)) body$scope = scope
  r = oauth_http(meta$registration_endpoint, "POST",
                 headers = list(Accept = "application/json", `Content-Type` = "application/json"),
                 body = json_encode(body))
  x = if (is.null(r$error)) tryCatch(json_decode(r$body), error = function(e) NULL)
  if (!is.list(x) || !is.character(x$client_id)) {
    gptr_abort(paste0("Client registration at ", url_origin(meta$registration_endpoint),
                      " failed (HTTP ", format(r$status), ")."), "provider",
               provider = meta$issuer, status = r$status)
  }
  x$client_id
}

# ---- access tokens: the vault and the credential store ----------------------------------------

#' Epoch milliseconds
#' @noRd
oauth_now_ms = function() as.numeric(Sys.time()) * 1000

#' Expiry of a token response in epoch ms, five minutes early (Pi's skew)
#' @noRd
oauth_expiry = function(tok) {
  oauth_now_ms() + (as.numeric(tok$expires_in %||% 3600) - 300) * 1000
}

#' Vault name of the in-memory access token of a credential key
#' @noRd
oauth_access_name = function(key) paste0("auth:", key, ":access")

#' Keep an access token in memory only: registered in the vault, bound to the resource's origin;
#' the Authorization value list("Bearer ", <handle>) is materialised only by P04 (contract 7.3)
#' @noRd
oauth_remember = function(key, access, origin) {
  h = secret_register(access, oauth_access_name(key), source = "oauth", origin = origin)
  list("Bearer ", h)
}

#' The Authorization value for `key`, or NULL when nothing is stored: an API key, or a valid
#' in-memory access token, else an OAuth refresh under a lock (`force` = refresh now, after a 401).
#' A record that names its `resource` is handed only to that resource's origin: a server whose
#' URL changed (another config reusing the name) gets no credential and asks for a sign-in.
#' @noRd
oauth_access = function(key, origin, force = FALSE) {
  rec = auth_store_get(key)
  if (is.null(rec)) return(NULL)
  if (is.character(rec$resource) && !is.null(origin) &&
        !identical(url_origin(rec$resource), url_origin(origin))) {
    return(NULL)
  }
  if (identical(rec$type, "api_key") && inherits(rec$key, "gptr_secret")) {
    return(list("Bearer ", rec$key))
  }
  if (!identical(rec$type, "oauth")) return(NULL)
  h = secret_lookup(oauth_access_name(key))
  fresh = isTRUE(as.numeric(rec$expires %||% 0) > oauth_now_ms() + 60000)
  if (!isTRUE(force) && !is.null(h) && fresh) return(list("Bearer ", h))
  oauth_refresh(key, origin)
}

#' Refresh an OAuth credential. The store is re-read under a lock, so two R processes never
#' redeem the same rotating refresh token (report 03's double-checked refresh). The stored
#' refresh token leaves the vault only here, for the token endpoint's own origin, as the form
#' field RFC 6749 section 6 requires (P04 bodies cannot carry handles; plan ambiguity 2).
#' @noRd
oauth_refresh = function(key, origin) {
  lock = file.path(gptr_user_dir("config", create = TRUE),
                   paste0("oauth-", substr(hash_sha256(key), 1L, 16L)))
  oauth_lock_with(lock, function() {
    rec = auth_store_get(key)
    if (!inherits(rec$refresh, "gptr_secret") || !is.character(rec$token_endpoint)) return(NULL)
    refresh = secret_value(rec$refresh, url_origin(rec$token_endpoint))
    # 20 s: the request ends before P03's staleness rule (30 s) lets another process break the
    # lock and redeem the same rotating refresh token
    tok = oauth_token_request(rec$token_endpoint,
                              list(grant_type = "refresh_token", refresh_token = refresh,
                                   client_id = rec$client_id, resource = rec$resource),
                              timeout = 20)
    keep = rec[setdiff(names(rec), c("refresh", "key"))]
    keep$refresh = if (is.character(tok$refresh_token) && nzchar(tok$refresh_token)) {
      tok$refresh_token
    } else {
      refresh
    }
    keep$expires = oauth_expiry(tok)
    header = oauth_remember(key, tok$access_token, origin)
    auth_store_set(key, keep)
    header
  })
}

#' Deactivate the in-memory access tokens of `key` (gptr_logout(), contract 6.2): secret_lookup()
#' no longer finds them, while their values stay registered and redacted. P03 has no unregister
#' function, so its registry entries (secrets_state()$reg, same `auth` area) are marked inactive,
#' the state P03's own `active = FALSE` registrations produce; TRUE when one was active.
#' @noRd
oauth_forget_access = function(key) {
  st = secrets_state()
  name = oauth_access_name(key)
  hit = FALSE
  for (id in names(st$reg)) {
    e = st$reg[[id]]
    if (identical(e$name, name) && isTRUE(e$active)) {
      e$active = FALSE
      st$reg[[id]] = e
      hit = TRUE
    }
  }
  hit
}

# ---- the authorization-code flow ---------------------------------------------------------------

#' Load-time callbacks of the layers above (architecture 2.2: L0 talks upward only through
#' callbacks), like P10's namespace providers: `target(name)` resolves gptr_login("mcp:<name>")
#' to list(url, oauth). No credentials and no run state live here.
#' @noRd
oauth_hooks = new.env(parent = emptyenv())

#' Register the callbacks (mcp-namespace.R does at load)
#' @noRd
oauth_hooks_set = function(target = NULL) {
  if (!is.null(target)) assign("target", target, envir = oauth_hooks)
  invisible(NULL)
}

#' Provider sign-ins gptr knows without discovery (report 03 section 3, Pi openrouter.ts:19-22):
#' OpenRouter's PKCE flow returns a permanent, user-controlled API key
#' @noRd
oauth_builtin_flows = function() {
  list(openrouter = list(authorize = "https://openrouter.ai/auth",
                         token = "https://openrouter.ai/api/v1/auth/keys",
                         origin = "https://openrouter.ai"))
}

#' The UI of this process (the ui.get service of P11)
#' @noRd
oauth_ui = function() ext_service_get("ui.get")(NULL)

#' Can the loopback redirect be served (httpuv and later installed)?
#' @noRd
oauth_loopback_ok = function() {
  with_seed_preserved(requireNamespace("httpuv", quietly = TRUE) &&
                        requireNamespace("later", quietly = TRUE))
}

#' Open the sign-in page in a browser, only at an interactive R prompt (13 C-42)
#' @noRd
oauth_open_browser = function(url) {
  if (gptr_is_interactive()) utils::browseURL(url)
  invisible(NULL)
}

#' Show the sign-in URL through the UI and open the browser
#' @noRd
oauth_notify_url = function(url) {
  oauth_ui()$notify(paste0("Sign in at: ", url), level = "info")
  oauth_open_browser(url)
  invisible(NULL)
}

#' A small HTML page for the loopback listener
#' @noRd
oauth_page = function(status, text) {
  list(status = as.integer(status),
       headers = list(`Content-Type` = "text/html; charset=utf-8", `Cache-Control` = "no-store"),
       body = paste0("<!doctype html><meta charset='utf-8'><title>gptr</title><p>", text, "</p>"))
}

#' Where the browser comes back: a loopback listener on 127.0.0.1 (a port from
#' port_candidates(), started with the seed preserved; IC-61) that keeps the whole query string,
#' `iss` included (IC-71), or, without httpuv and later, a paste prompt. Returns
#' list(redirect_uri, wait(timeout), close()).
#' @noRd
oauth_redirect_setup = function(port = NULL, path = "/callback", state = NULL) {
  st = new.env(parent = emptyenv())
  st$query = NULL
  if (!oauth_loopback_ok()) {
    p = if (is.null(port)) port_candidates(1L)[1L] else as.integer(port)
    uri = paste0("http://127.0.0.1:", p, path)
    return(list(redirect_uri = uri, close = function() invisible(NULL),
                wait = function(timeout = 300) {
                  oauth_ui()$input(paste0("After signing in, paste the full address of the ",
                                          "page your browser opened: "))
                }))
  }
  app = list(call = function(req) {
    if (!identical(req$REQUEST_METHOD, "GET") || !identical(req$PATH_INFO, path)) {
      return(oauth_page(404L, "Not found."))
    }
    if (!is.null(st$query)) return(oauth_page(409L, "This sign-in was already handled."))
    q = sub("^\\?", "", req$QUERY_STRING %||% "")
    if (!is.null(state) && !identical(query_parse(q)$state, state)) {
      return(oauth_page(400L, "This page does not belong to the current sign-in."))
    }
    st$query = q
    oauth_page(200L, "Signed in. You can close this page and return to R.")
  })
  ports = if (is.null(port)) port_candidates(20L) else as.integer(port)
  srv = NULL
  with_seed_preserved({
    for (p in ports) {
      srv = tryCatch(httpuv::startServer("127.0.0.1", p, app), error = function(e) NULL)
      if (!is.null(srv)) {
        st$port = p
        break
      }
    }
  })
  if (is.null(srv)) {
    gptr_abort("Could not open a local port for the sign-in redirect.", "spawn",
               command = "httpuv::startServer")
  }
  uri = paste0("http://127.0.0.1:", st$port, path)
  list(redirect_uri = uri,
       close = function() with_seed_preserved(try(httpuv::stopServer(srv), silent = TRUE)),
       wait = function(timeout = 300) {
         ok = reactor_pump(until = function() !is.null(st$query), slice_ms = 100L,
                           timeout = timeout)
         if (!isTRUE(ok)) {
           gptr_abort(paste0("No sign-in arrived within ", timeout, " s."), "timeout",
                      seconds = timeout, what = "OAuth redirect")
         }
         sep = if (nzchar(st$query)) "?" else ""
         paste0(uri, sep, st$query)
       })
}

#' OAuth authorization-code flow with PKCE S256 (contract 7.18)
#'
#' `issuer_or_provider`: an issuer URL, a discovery result of oauth_discover(), or a built-in
#' provider id (oauth_builtin_flows()); `client`: list(client_id, callback_port, resource, key).
#' The access token stays in the vault; returns the credential record to store (the refresh
#' token as a value, never the access token).
#' @noRd
oauth_flow = function(issuer_or_provider, scopes = NULL, client = NULL) {
  client = client %||% list()
  flows = oauth_builtin_flows()
  if (is.character(issuer_or_provider) && issuer_or_provider %in% names(flows)) {
    return(oauth_key_exchange(issuer_or_provider, flows[[issuer_or_provider]], client))
  }
  disc = if (is.list(issuer_or_provider)) {
    issuer_or_provider
  } else {
    list(issuer = issuer_or_provider, metadata = oauth_as_metadata(issuer_or_provider),
         resource = client$resource, scopes = character())
  }
  meta = disc$metadata
  scope = paste(unique(c(scopes, disc$scopes)), collapse = " ")
  key = client$key %||% disc$issuer
  state = rand_hex(16L)
  pk = pkce_new()
  cb = oauth_redirect_setup(client$callback_port, state = state)
  on.exit(cb$close(), add = TRUE)
  client_id = client$client_id %||% oauth_register_client(meta, cb$redirect_uri, scope)
  if (is.null(client_id)) {
    client_id = oauth_ui()$input(paste0("Client id registered with ", disc$issuer, ": "))
    if (!is.character(client_id) || is.na(client_id) || !nzchar(client_id)) {
      gptr_abort("A client id is needed for this server.", "invalid_argument", arg = "client_id",
                 expected = "a client id")
    }
  }
  oauth_notify_url(oauth_authorize_url(meta, client_id, cb$redirect_uri, scope, state,
                                       pk$challenge, disc$resource))
  code = oauth_parse_redirect(cb$wait(300), cb$redirect_uri, state, disc$issuer,
                              isTRUE(meta$authorization_response_iss_parameter_supported))
  tok = oauth_token_request(meta$token_endpoint,
                            list(grant_type = "authorization_code", code = code,
                                 redirect_uri = cb$redirect_uri, code_verifier = pk$verifier,
                                 client_id = client_id, resource = disc$resource))
  oauth_remember(key, tok$access_token, url_origin(disc$resource %||% disc$issuer))
  rec = list(type = "oauth", issuer = disc$issuer, client_id = client_id,
             token_endpoint = meta$token_endpoint, resource = disc$resource, scope = scope,
             expires = oauth_expiry(tok))
  if (is.character(tok$refresh_token) && nzchar(tok$refresh_token)) {
    rec$refresh = tok$refresh_token
  }
  rec
}

#' A provider's PKCE flow that returns an API key (OpenRouter). The protocol has no state, so
#' the redirect path carries a random segment and only that path is accepted.
#' @noRd
oauth_key_exchange = function(id, flow, client) {
  pk = pkce_new()
  cb = oauth_redirect_setup(client$callback_port, path = paste0("/callback/", rand_hex(8L)))
  on.exit(cb$close(), add = TRUE)
  url = paste0(flow$authorize, "?", form_encode(list(callback_url = cb$redirect_uri,
                                                      code_challenge = pk$challenge,
                                                      code_challenge_method = "S256")))
  oauth_notify_url(url)
  got = trimws(cb$wait(300))
  if (!startsWith(got, paste0(cb$redirect_uri, "?")) && !identical(got, cb$redirect_uri)) {
    gptr_abort("The sign-in redirect went to another address than the one gptr opened.",
               "untrusted", what = "OAuth redirect", path = NA_character_, origin = flow$origin)
  }
  code = query_parse(url_parts(got)$query)$code
  if (is.null(code) || !nzchar(code)) {
    gptr_abort("The sign-in redirect carries no code.", "untrusted", what = "OAuth redirect",
               path = NA_character_, origin = flow$origin)
  }
  r = oauth_http(flow$token, "POST",
                 headers = list(Accept = "application/json", `Content-Type` = "application/json"),
                 body = json_encode(list(code = code, code_verifier = pk$verifier,
                                         code_challenge_method = "S256")))
  x = if (is.null(r$error)) tryCatch(json_decode(r$body), error = function(e) NULL)
  if (!is.list(x) || !is.character(x$key)) {
    gptr_abort(paste0("The key exchange at ", url_origin(flow$token), " failed (HTTP ",
                      format(r$status), ")."), "provider", provider = id, status = r$status)
  }
  list(type = "api_key", key = x$key)
}

#' Masked key entry through the UI (P11: rstudioapi::askForPassword() or a no-echo read)
#' @noRd
oauth_ask_key = function(what) {
  v = oauth_ui()$input(paste0(what, ": "), secret = TRUE)
  if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(trimws(v))) {
    gptr_abort("No key was entered.", "invalid_argument", arg = "key", expected = "a non-empty key")
  }
  trimws(v)
}

# ---- gptr_login() and gptr_logout() -----------------------------------------------------------

#' Sign in to a model provider or an MCP server
#'
#' Stores a credential for a model provider (for example `"openrouter"`) or for an MCP server
#' (`"mcp:<server>"`). With `method = "auto"`, providers and MCP servers that support OAuth
#' get the authorization-code flow with PKCE (S256): a page on 127.0.0.1 receives the redirect
#' when 'httpuv' and 'later' are installed; otherwise you paste the address your browser ends
#' on. Everything else gets masked key entry. Credentials go to the credential store
#' (`auth.json`, readable only by you, or a keyring reference); access tokens stay in memory.
#' A tool call never opens a browser: when an MCP server needs a sign-in, the call fails with
#' an error naming this function.
#'
#' @param provider A provider id such as `"openrouter"`, or `"mcp:<server>"` for an MCP server.
#' @param method `"auto"` (default), `"oauth"` (the browser flow only) or `"key"` (key entry).
#' @return `gptr_login()` returns `TRUE` invisibly; `gptr_logout()` removes the stored
#'   credential and forgets the access token held in memory, and returns `TRUE` invisibly when
#'   it removed something, else `FALSE`.
#' @examplesIf interactive()
#' gptr_login("openrouter")
#' gptr_logout("openrouter")
#' @export
gptr_login = function(provider, method = c("auto", "oauth", "key")) {
  provider = check_string(provider, "provider")
  method = check_choice(method, c("auto", "oauth", "key"), "method")
  ext_control_guard("gptr_login")
  if (!gptr_can_prompt()) {
    gptr_abort("gptr_login() needs a person to sign in; run it in an interactive R session.",
               "noninteractive", what = "gptr_login()", questions = NULL)
  }
  if (startsWith(provider, "mcp:")) {
    oauth_login_mcp(substring(provider, 5L), method)
    return(invisible(TRUE))
  }
  flow = oauth_builtin_flows()[[provider]]
  if (is.null(flow) && is.null(registry_get("provider", provider))) {
    gptr_abort(paste0("Unknown provider: ", provider, "."), "invalid_argument", arg = "provider",
               expected = "a provider id from gptr_providers(), or \"mcp:<server>\"")
  }
  if (identical(method, "oauth") && is.null(flow)) {
    gptr_abort(paste0("Provider ", provider, " has no sign-in flow in gptr; use method = \"key\"."),
               "invalid_argument", arg = "method",
               expected = "\"key\" or \"auto\" for this provider")
  }
  rec = if (!is.null(flow) && !identical(method, "key")) {
    oauth_need("openssl", "Signing in")
    oauth_flow(provider, client = list(key = provider))
  } else {
    list(type = "api_key", key = oauth_ask_key(paste("API key for", provider)))
  }
  auth_store_set(provider, rec)
  invisible(TRUE)
}

#' The MCP branch of gptr_login(): RFC 9728 discovery and OAuth, or a bearer token entered by
#' hand when the server offers no OAuth
#' @noRd
oauth_login_mcp = function(name, method) {
  target_fun = get0("target", envir = oauth_hooks, inherits = FALSE)
  if (!is.function(target_fun)) {
    gptr_abort("MCP support is not loaded (builtin:mcp is filtered out).", "not_available",
               member = "gptr_login(\"mcp:...\")", provided_by = "P18")
  }
  key = paste0("mcp:", name)
  target = target_fun(name)
  disc = if (!identical(method, "key")) {
    oauth_need("openssl", "Signing in")
    oauth_discover(target$url)
  }
  if (is.null(disc)) {
    if (identical(method, "oauth")) {
      gptr_abort(paste0("MCP server ", name, " does not offer OAuth; use method = \"key\"."),
                 "invalid_argument", arg = "method", expected = "\"key\" for this server")
    }
    token = oauth_ask_key(paste("Bearer token for MCP server", name))
    auth_store_set(key, list(type = "api_key", key = token, resource = target$url))
    return(invisible(TRUE))
  }
  o = target$oauth %||% list()
  rec = oauth_flow(disc, scopes = o$scope,
                   client = list(client_id = o$clientId, callback_port = o$callbackPort,
                                 resource = target$url, key = key))
  auth_store_set(key, rec)
  invisible(TRUE)
}

#' @rdname gptr_login
#' @export
gptr_logout = function(provider) {
  provider = check_string(provider, "provider")
  ext_control_guard("gptr_logout")
  stored = isTRUE(auth_store_remove(provider))
  memory = oauth_forget_access(provider)
  invisible(stored || memory)
}
```

Then regenerate the documentation: `Rscript --vanilla -e 'devtools::document()'`. Expected: `NAMESPACE` gains `export(gptr_login)` and `export(gptr_logout)`; `man/gptr_login.Rd` is written (one page, aliases `gptr_login` and `gptr_logout`, the example wrapped in `\dontshow{if (interactive()) ...}` by `@examplesIf`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "auth-oauth")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 99 ]` (the sign-in tests start the fixture servers and skip on CRAN)

- [ ] **Step 5: Commit**

```bash
git add R/auth-oauth.R tests/testthat/test-auth-oauth.R tests/testthat/helper-mcp-server.R tests/testthat/fixtures/mcp/oauth.R tests/testthat/fixtures/mcp/browser.R NAMESPACE man/gptr_login.Rd
git commit -m "feat(auth): add OAuth discovery, the locked refresh, gptr_login() and gptr_logout()"
```


---

### Task 3: MCP wire helpers, process state, caches and placeholders

**Files:**
- Create: `R/mcp-client.R`
- Test: `tests/testthat/test-mcp-client.R` (create)

**Interfaces:**
- Consumes: P01 `json_encode()`, `json_decode()`, `json_obj()`, `as_utf8()`, `first_sentence()`, `hash_sha256()`, `canonical_json()`, `gptr_user_dir()`, `read_utf8()`, `write_atomic()`, `user_home()`, `project_root()`, `block_image()`, `gptr_opt()`, `gptr_abort()`; P03 `redact()`, `secret_register()`, `secret_lookup()` (tests); P04 `url_origin()`; Task 1 `url_parts()`.
- Produces (internal; used by Tasks 4-9): `mcp_versions()` -> `list(modern = "2026-07-28", legacy = c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"))`; the `_meta` key constants `mcp_k_ver`, `mcp_k_caps`, `mcp_k_cinfo`, `mcp_k_sinfo`; `json_ascii(s)`, `mcp_json(x)` (ASCII-only JSON text); `mcp_header_value(x)` (`=?base64?...?=` for non-ASCII); `mcp_r_name(x)`, `mcp_wire_name(server, tool)` (`mcp__<server>__<tool>`, at most 64 characters); `mcp_first_sentence(d, n = 120L)`; `mcp_coerce(x, schema, path = "args")`; `mcp_tool_norm(t)` -> `list(name, title, description, input_schema, annotations, output_schema)`; `mcp_result_parse(res, elapsed = NA_real_)` -> `list(content, structured, is_error, text, images, elapsed)`; `mcp_value(res)`; `mcp_rpc_ok(id, result)`, `mcp_rpc_err(id, code, message, data = NULL)`; `mcp_client_caps()`, `mcp_client_info()`, `mcp_meta_fields(version)`, `mcp_file_uri(path)`; `mcp_state()` (`the$mcp_conns`: environments `conns`, `specs`, `servers`, `lru`, `sessions` (session id -> weak reference, Task 7) and the config `stamp`); `mcp_transport(spec)`; the caches `mcp_cache_key(spec)`, `mcp_cache_path(kind, spec, create = FALSE)`, `mcp_era_get(spec)`, `mcp_era_put(spec, era, version)`, `mcp_era_forget(spec)`, `mcp_tools_cache_get(spec)`, `mcp_tools_cache_put(spec, tools, ttl_ms = NULL, cache_scope = NULL)`, `mcp_tools_cache_fresh(x)`; the logs `mcp_log_path(name)`, `mcp_log_append(path, txt)`, `mcp_log(conn, line)`; placeholders `mcp_expand(x, project = project_root())`, `mcp_expand1(s, project)`, `mcp_secret_name(x)`, `mcp_expand_spec(spec, project = project_root())`.

Every JSON text sent to a server is ASCII (report 16 §2.17: servers in a C locale or a Windows code page read it intact; jsonlite would otherwise write unknown-encoded bytes as `<c3><a9>`). Arguments are coerced by the tool's schema before `json_encode()` so that `auto_unbox = TRUE` never turns a length-1 array into a scalar (report 06 §4.5.3's `coerce_to_schema()`). `structuredContent` is the one value gptr parses with `simplifyVector = TRUE`, because 04 §9.4 promises "R values (`structuredContent` simplified, else text)".

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-mcp-client.R`:

```r
test_that("json_ascii() escapes non-ASCII characters, surrogate pairs included", {
  # one literal must not mix \u and \U escapes: in a C locale R's parser double-encodes the
  # \u part of such a literal
  txt = paste0("caf\u00e9 \u4e16 ", "\U0001f600")
  a = json_ascii(paste0("{\"t\":\"", txt, "\"}"))
  expect_false(any(charToRaw(a) > as.raw(127L)))
  expect_match(a, "caf\\u00e9", fixed = TRUE)
  expect_match(a, "\\ud83d\\ude00", fixed = TRUE)
  expect_identical(json_decode(a)$t, txt)
  expect_identical(json_ascii("{\"a\":1}"), "{\"a\":1}")
})

test_that("header values are base64-wrapped only when they are not plain ASCII", {
  expect_identical(mcp_header_value("get_weather"), "get_weather")
  expect_match(mcp_header_value("caf\u00e9"), "^=\\?base64\\?.*\\?=$")
  expect_match(mcp_header_value(" padded"), "^=\\?base64\\?")
  expect_identical(rawToChar(jsonlite::base64_dec(sub("^=\\?base64\\?(.*)\\?=$", "\\1",
                                                      mcp_header_value(" padded")))), " padded")
})

test_that("names become syntactic R names and bounded wire names", {
  expect_identical(mcp_r_name(c("my-tool", "_private", "9lives", "repeat", "ok.name")),
                   c("my_tool", "t__private", "t_9lives", "repeat_", "ok.name"))
  expect_identical(mcp_wire_name("github", "search_code"), "mcp__github__search_code")
  long = mcp_wire_name("server", strrep("x", 80))
  expect_identical(nchar(long), 64L)
  expect_match(long, "^mcp__server__x+_[0-9a-f]{8}$")
  expect_identical(mcp_first_sentence("Search code. Returns matches."), "Search code.")
  expect_identical(nchar(mcp_first_sentence(strrep("a", 300), 120L)), 120L)
})

test_that("arguments are coerced by schema: arrays stay arrays, NA is dropped, whole integers", {
  schema = list(type = "object", properties = list(
    ids = list(type = "array", items = list(type = "integer")),
    opts = list(type = "object"), name = list(type = "string"), when = list(type = "string"),
    rows = list(type = "array", items = list(type = "object")), n = list(type = "integer")))
  x = mcp_coerce(list(ids = 7, opts = list(), name = factor("a"), when = NA,
                      rows = data.frame(x = 1:2, y = c("a", "b")), n = 3), schema)
  expect_identical(json_encode(x), paste0("{\"ids\":[7],\"opts\":{},\"name\":\"a\",",
                                          "\"rows\":[{\"x\":1,\"y\":\"a\"},{\"x\":2,\"y\":\"b\"}],",
                                          "\"n\":3}"))
  expect_error(mcp_coerce(list(n = 2.5), schema), "whole", class = "gptr_error_invalid_argument")
  expect_error(mcp_coerce(list(name = c("a", "b")), schema), "single string",
               class = "gptr_error_invalid_argument")
  expect_identical(json_encode(mcp_coerce(list(), list(type = "object"))), "{}")
  either = list(anyOf = list(list(type = "integer"), list(type = "string")))
  expect_identical(mcp_coerce("x", either), "x")
})

test_that("tool results become text, images and R values", {
  res = list(content = list(list(type = "text", text = "{\"n\":3}"),
                            list(type = "image", data = "AAAA", mimeType = "image/png"),
                            list(type = "resource_link", uri = "file:///x.csv", name = "x")),
             structuredContent = list(n = 3L, rows = list(list(a = 1, b = "x"),
                                                         list(a = 2, b = "y"))),
             isError = FALSE)
  p = mcp_result_parse(res, elapsed = 0.5)
  expect_false(p$is_error)
  expect_match(p$text, "[image image/png]", fixed = TRUE)
  expect_match(p$text, "[resource_link file:///x.csv]", fixed = TRUE)
  expect_length(p$images, 1L)
  expect_identical(p$images[[1L]]$source, "mcp")
  v = mcp_value(p)
  expect_identical(v$n, 3L)
  expect_s3_class(v$rows, "data.frame")
  plain = mcp_result_parse(list(content = list(list(type = "text", text = "hi"))))
  expect_identical(mcp_value(plain), "hi")
})

test_that("placeholders expand at connect time; secret-like values are registered", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(MCP_T_TOKEN = "tok-abcdefghijklmnop", MCP_T_UNSET = NA,
                      MCP_T_ARG_TOKEN = "argtok-abcdefghijkl")
  x = mcp_expand(c(a = "${MCP_T_TOKEN}", b = "${MCP_T_UNSET:-dflt}", c = "${env:MCP_T_TOKEN}",
                   d = "${userHome}/x", e = "${workspaceFolder}/db", f = "${MCP_T_UNSET}"),
                 project = "/proj")
  expect_identical(unname(x), c("tok-abcdefghijklmnop", "dflt", "tok-abcdefghijklmnop",
                                paste0(user_home(), "/x"), "/proj/db", ""))
  expect_identical(names(x), c("a", "b", "c", "d", "e", "f"))
  ex = mcp_expand_spec(list(command = "srv", env = list(API_TOKEN = "${MCP_T_TOKEN}")), "/proj")
  expect_identical(ex$env[["API_TOKEN"]], "tok-abcdefghijklmnop")
  expect_false(is.null(secret_lookup("API_TOKEN")))
  expect_false(grepl("tok-abcdefghijklmnop", redact("tok-abcdefghijklmnop"), fixed = TRUE))
  ex = mcp_expand_spec(list(command = "srv", args = c("--token", "${MCP_T_ARG_TOKEN}")), "/proj")
  expect_identical(ex$args, c("--token", "argtok-abcdefghijkl"))
  expect_false(is.null(secret_lookup("MCP_T_ARG_TOKEN")))
})

test_that("era and tool caches live in the user cache with their keys and expiry (11.9)", {
  spec = list(name = "s", command = "srv", args = c("a", "b"))
  expect_identical(mcp_cache_key(spec),
                   hash_sha256(canonical_json(list(command = "srv", args = I(c("a", "b"))))))
  expect_null(mcp_era_get(spec))
  mcp_era_put(spec, "legacy", "2025-11-25")
  expect_identical(mcp_era_get(spec)$era, "legacy")
  expect_true(startsWith(mcp_cache_path("mcp-era", spec), gptr_user_dir("cache")))
  mcp_era_forget(spec)
  expect_null(mcp_era_get(spec))
  mcp_tools_cache_put(spec, list(list(name = "t")), ttl_ms = 60000)
  x = mcp_tools_cache_get(spec)
  expect_identical(x$tools[[1L]]$name, "t")
  expect_true(mcp_tools_cache_fresh(x))
  x$fetched_at = 0
  expect_false(mcp_tools_cache_fresh(x))
  web = list(name = "w", url = "https://Mcp.Example.com:443/mcp?x=1")
  expect_identical(mcp_cache_key(web),
                   hash_sha256(canonical_json(list(url = "https://mcp.example.com/mcp"))))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-client")'`
Expected: `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`; the first error is `could not find function "json_ascii"`.

- [ ] **Step 3: Write the implementation**

Create `R/mcp-client.R`:

```r
# MCP client for both protocol eras: legacy (2025-11-25 and earlier) and modern (2026-07-28)
# (REQ-30, D-14; architecture 6.14; contract 7.18).
#
# Adapted from dev/research/16-mcp-skills-plugins.md 5.3 (stdio client), 5.9 (HTTP client) and
# 5.14 (tools as R functions) and dev/research/06-pi-subagents-mcp-codemode.md 4.5.3 (argument
# coercion by schema), moved onto P04's process engine and reactor instead of blocking polls and
# httr2. Report 16's verification-log fixes are applied: the stdio probe falls back to the
# legacy handshake on any non-modern answer or a timeout (#3), a legacy HTTP cancel is a SHOULD
# (#5), stdout is read line by line through the reactor (#22). Server stderr is read by gptr and
# appended redacted to tempdir()/gptr/mcp-logs/ unless options(gptr.mcp_debug = TRUE) (IC-70).

# ---- wire helpers (pure) -------------------------------------------------------------------

mcp_k_ver = "io.modelcontextprotocol/protocolVersion"
mcp_k_caps = "io.modelcontextprotocol/clientCapabilities"
mcp_k_cinfo = "io.modelcontextprotocol/clientInfo"
mcp_k_sinfo = "io.modelcontextprotocol/serverInfo"

#' Protocol versions gptr speaks, newest first per era
#' @noRd
mcp_versions = function() {
  list(modern = "2026-07-28", legacy = c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"))
}

#' JSON text with every non-ASCII character written as a \\u escape (surrogate pairs above the
#' BMP), so servers in a C locale or a Windows code page read it intact (report 16 section 2.17)
#' @noRd
json_ascii = function(s) {
  s = as_utf8(as.character(s))
  if (!any(charToRaw(s) > as.raw(127L))) return(s)
  cp = utf8ToInt(s)
  if (anyNA(cp)) return(s)
  hi = which(cp > 127L)
  out = intToUtf8(cp, multiple = TRUE)
  v = cp[hi]
  esc = character(length(v))
  bmp = v < 65536L
  esc[bmp] = sprintf("\\u%04x", v[bmp])
  a = v[!bmp] - 65536L
  esc[!bmp] = sprintf("\\u%04x\\u%04x", 55296L + a %/% 1024L, 56320L + a %% 1024L)
  out[hi] = esc
  paste(out, collapse = "")
}

#' ASCII-only JSON of an R value
#' @noRd
mcp_json = function(x) json_ascii(json_encode(x))

#' The 2026-07-28 header value encoding of Mcp-Name and Mcp-Param-* ("=?base64?...?=")
#' @noRd
mcp_header_value = function(x) {
  x = as_utf8(as.character(x)[1L])
  plain = !grepl("[^\\x20-\\x7e]", x, perl = TRUE, useBytes = TRUE) &&
    !grepl("^\\s|\\s$", x) && !(startsWith(x, "=?base64?") && endsWith(x, "?="))
  if (plain) return(x)
  paste0("=?base64?", gsub("[\r\n]", "", jsonlite::base64_enc(charToRaw(x))), "?=")
}

#' Syntactic R name of an MCP tool or server name (report 06 section 4.5.3)
#' @noRd
mcp_r_name = function(x) {
  y = gsub("[^A-Za-z0-9_.]", "_", x)
  y = ifelse(grepl("^[A-Za-z]", y), y, paste0("t_", y))
  reserved = c("if", "else", "repeat", "while", "function", "for", "next", "break", "TRUE",
               "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_", "NA_character_",
               "NA_complex_", "in")
  ifelse(y %in% reserved, paste0(y, "_"), y)
}

#' Registry and wire name of an MCP tool: mcp__<server>__<tool>, at most 64 characters
#' @noRd
mcp_wire_name = function(server, tool) {
  clean = function(x) gsub("[^A-Za-z0-9_-]", "_", x)
  nm = paste0("mcp__", clean(server), "__", clean(tool))
  if (nchar(nm) > 64L) nm = paste0(substr(nm, 1L, 55L), "_", substr(hash_sha256(nm), 1L, 8L))
  nm
}

#' First sentence of a description, at most n characters
#' @noRd
mcp_first_sentence = function(d, n = 120L) {
  d = first_sentence(gsub("\\s+", " ", trimws(as.character(d %||% ""))))
  if (nchar(d) > n) d = paste0(substr(d, 1L, n - 3L), "...")
  d
}

#' Abort for an argument that does not fit the tool's schema
#' @noRd
mcp_arg_error = function(path, what) {
  gptr_abort(paste0(path, " must be ", what, "."), "invalid_argument", arg = path, expected = what)
}

#' One scalar converted by conv(); NA becomes NULL (the field is omitted)
#' @noRd
mcp_scalar = function(x, conv, what, path) {
  if (length(x) != 1L) mcp_arg_error(path, what)
  if (is.list(x)) x = x[[1L]]
  if (is.atomic(x) && length(x) == 1L && is.na(x)) return(NULL)
  conv(x)
}

#' A value without schema guidance: factors become strings, data frames arrays of rows
#' @noRd
mcp_plain = function(x) {
  if (is.factor(x)) return(as.character(x))
  if (is.data.frame(x)) return(lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE])))
  x
}

#' An R value made JSON-ready by a JSON Schema: arrays stay arrays at length 1, objects need
#' names and an empty one is {}, integers must be whole, NA and NULL fields are omitted (report
#' 06's coerce_to_schema() in gptr's json_encode(auto_unbox = TRUE) world)
#' @noRd
mcp_coerce = function(x, schema, path = "args") {
  if (is.null(x)) return(NULL)
  if (!is.list(schema) || !length(schema)) return(mcp_plain(x))
  variants = schema$anyOf %||% schema$oneOf
  if (!is.null(variants)) {
    for (v in variants) {
      r = tryCatch(mcp_coerce(x, v, path), gptr_error = function(e) NULL)
      if (!is.null(r)) return(r)
    }
    return(mcp_plain(x))
  }
  type = schema$type
  if (is.list(type) || length(type) > 1L) type = setdiff(as.character(unlist(type)), "null")[1L]
  if (is.null(type) || is.na(type)) {
    type = if (!is.null(schema$properties)) {
      "object"
    } else if (!is.null(schema$items)) {
      "array"
    } else {
      "any"
    }
  }
  if (is.factor(x)) x = as.character(x)
  whole = function(v) {
    if (!is.numeric(v) || v != round(v)) mcp_arg_error(path, "a whole number")
    as.integer(v)
  }
  switch(type,
    string = mcp_scalar(x, as.character, "a single string", path),
    number = mcp_scalar(x, as.numeric, "a single number", path),
    integer = mcp_scalar(x, whole, "a single whole number", path),
    boolean = mcp_scalar(x, as.logical, "TRUE or FALSE", path),
    array = {
      if (is.data.frame(x)) x = lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE]))
      lapply(seq_along(x), function(i) {
        mcp_coerce(x[[i]], schema$items, sprintf("%s[[%d]]", path, i))
      })
    },
    object = {
      if (!is.list(x)) x = as.list(x)
      if (length(x) && (is.null(names(x)) || any(!nzchar(names(x))))) {
        mcp_arg_error(path, "a named list")
      }
      props = schema$properties %||% list()
      out = lapply(names(x), function(n) mcp_coerce(x[[n]], props[[n]], paste0(path, "$", n)))
      names(out) = names(x)
      out = out[!vapply(out, is.null, NA)]
      if (length(out)) out else json_obj()
    },
    mcp_plain(x))
}

#' A tool of tools/list in gptr's shape: list(name, title, description, input_schema,
#' annotations, output_schema)
#' @noRd
mcp_tool_norm = function(t) {
  schema = t$inputSchema
  if (!is.list(schema)) schema = list(type = "object")
  list(name = as.character(t$name), title = t$title,
       description = as_utf8(as.character(t$description %||% "")), input_schema = schema,
       annotations = t$annotations %||% list(), output_schema = t$outputSchema)
}

#' A tools/call result as list(content, structured, is_error, text, images, elapsed); the text
#' is what a model sees: text blocks verbatim, other blocks as short placeholders
#' @noRd
mcp_result_parse = function(res, elapsed = NA_real_) {
  blocks = res$content %||% list()
  texts = character()
  images = list()
  for (b in blocks) {
    type = as.character(b$type %||% "")
    if (identical(type, "text")) {
      texts = c(texts, as_utf8(as.character(b$text %||% "")))
    } else if (identical(type, "image") && is.character(b$data)) {
      images[[length(images) + 1L]] = block_image(b$data, mime = b$mimeType %||% "image/png",
                                                  source = "mcp")
      texts = c(texts, paste0("[image ", b$mimeType %||% "", "]"))
    } else if (identical(type, "resource")) {
      r = b$resource %||% list()
      texts = c(texts, if (is.character(r$text)) {
        as_utf8(r$text)
      } else {
        paste0("[resource ", r$uri %||% "", "]")
      })
    } else if (identical(type, "resource_link")) {
      texts = c(texts, paste0("[resource_link ", b$uri %||% "", "]"))
    } else {
      texts = c(texts, paste0("[", type, " ", b$mimeType %||% "block", "]"))
    }
  }
  list(content = blocks, structured = res$structuredContent, is_error = isTRUE(res$isError),
       text = paste(texts, collapse = "\n"), images = images, elapsed = elapsed)
}

#' The R value of a result (contract 9.4): structuredContent simplified by jsonlite (arrays of
#' objects become data frames; the one place gptr parses with simplifyVector = TRUE), else text
#' @noRd
mcp_value = function(res) {
  if (!is.null(res$structured)) {
    return(jsonlite::fromJSON(json_encode(res$structured), simplifyVector = TRUE))
  }
  res$text
}

#' A JSON-RPC success response
#' @noRd
mcp_rpc_ok = function(id, result) list(jsonrpc = "2.0", id = id, result = result)

#' A JSON-RPC error response
#' @noRd
mcp_rpc_err = function(id, code, message, data = NULL) {
  err = list(code = as.integer(code), message = message)
  if (!is.null(data)) err$data = data
  list(jsonrpc = "2.0", id = id, error = err)
}

#' clientCapabilities gptr declares: form elicitation (the ask UI) and roots
#' @noRd
mcp_client_caps = function() {
  list(elicitation = list(form = json_obj()), roots = list(listChanged = FALSE))
}

#' clientInfo gptr sends
#' @noRd
mcp_client_info = function() {
  list(name = "gptr", version = as.character(utils::packageVersion("gptr")))
}

#' The per-request _meta fields of 2026-07-28
#' @noRd
mcp_meta_fields = function(version) {
  stats::setNames(list(version, mcp_client_caps(), mcp_client_info()),
                  c(mcp_k_ver, mcp_k_caps, mcp_k_cinfo))
}

#' file:// URI of a local directory
#' @noRd
mcp_file_uri = function(path) {
  p = normalizePath(path, winslash = "/", mustWork = FALSE)
  paste0("file://", if (!startsWith(p, "/")) "/", utils::URLencode(p))
}

# ---- process state, caches and logs ----------------------------------------------------------

#' P18's process state `the$mcp_conns`: live connections, P18's registry ids of tool specs and
#' configured servers, the config stamp, the catalog's last-use times and the weak index of the
#' sessions builtin:mcp saw start (so a service called with a session id can find the session)
#' @noRd
mcp_state = function() {
  st = the$mcp_conns
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$conns = new.env(parent = emptyenv())
    st$specs = new.env(parent = emptyenv())
    st$servers = new.env(parent = emptyenv())
    st$lru = new.env(parent = emptyenv())
    st$sessions = new.env(parent = emptyenv())
    st$stamp = NULL
    the$mcp_conns = st
  }
  st
}

#' Transport of a server spec: "stdio", "http", "sse" (refused) or another declared type
#' @noRd
mcp_transport = function(spec) {
  if (identical(spec$type, "sse") || identical(spec$transport, "sse")) return("sse")
  t = spec$transport
  if (is.character(t) && length(t) == 1L && !is.na(t)) return(t)
  if (!is.null(spec$command)) "stdio" else if (!is.null(spec$url)) "http" else NA_character_
}

#' Cache key of a server: sha256 of its command and args, or of its URL origin and path
#' (contract 11.9)
#' @noRd
mcp_cache_key = function(spec) {
  if (!is.null(spec$url)) {
    where = paste0(url_origin(spec$url), url_parts(spec$url)$path)
    return(hash_sha256(canonical_json(list(url = where))))
  }
  hash_sha256(canonical_json(list(command = as.character(spec$command),
                                  args = I(as.character(unlist(spec$args) %||% character())))))
}

#' A cache file under R_user_dir("gptr", "cache")/<kind>/ (directories only created to write)
#' @noRd
mcp_cache_path = function(kind, spec, create = FALSE) {
  dir = file.path(gptr_user_dir("cache", create = create), kind)
  if (create) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, paste0(mcp_cache_key(spec), ".json"))
}

#' Read a small JSON cache file; NULL when absent or unreadable
#' @noRd
mcp_cache_read = function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
}

#' The cached era of a server, NULL when absent or older than 7 days
#' @noRd
mcp_era_get = function(spec) {
  x = mcp_cache_read(mcp_cache_path("mcp-era", spec))
  if (is.null(x$era) || is.null(x$date)) return(NULL)
  when = as.POSIXct(x$date, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.na(when) || difftime(Sys.time(), when, units = "days") > 7) return(NULL)
  x
}

#' Cache the era of a server for 7 days
#' @noRd
mcp_era_put = function(spec, era, version) {
  write_atomic(mcp_cache_path("mcp-era", spec, create = TRUE),
               json_encode(list(era = era, version = version,
                                date = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))))
}

#' Forget the cached era of a server
#' @noRd
mcp_era_forget = function(spec) invisible(unlink(mcp_cache_path("mcp-era", spec)))

#' The cached tool list of a server: list(tools, fetched_at, ttl_ms, cache_scope), or NULL
#' @noRd
mcp_tools_cache_get = function(spec) mcp_cache_read(mcp_cache_path("mcp-tools", spec))

#' Cache a tool list (the credentials are always the user's own, so cacheScope "private" is
#' cached too; contract 11.9)
#' @noRd
mcp_tools_cache_put = function(spec, tools, ttl_ms = NULL, cache_scope = NULL) {
  write_atomic(mcp_cache_path("mcp-tools", spec, create = TRUE),
               json_encode(list(tools = tools, fetched_at = as.numeric(Sys.time()) * 1000,
                                ttl_ms = ttl_ms, cache_scope = cache_scope)))
}

#' Is a cached tool list fresh? Modern servers: within ttlMs; legacy servers: 24 hours
#' @noRd
mcp_tools_cache_fresh = function(x) {
  if (is.null(x$fetched_at)) return(FALSE)
  age = as.numeric(Sys.time()) * 1000 - as.numeric(x$fetched_at)
  ttl = if (is.null(x$ttl_ms)) 24 * 3600 * 1000 else as.numeric(x$ttl_ms)
  age <= ttl
}

#' The redacted stderr log of a server: tempdir()/gptr/mcp-logs/ unless gptr.mcp_debug, then
#' the user cache (IC-70)
#' @noRd
mcp_log_path = function(name) {
  dir = if (isTRUE(gptr_opt("mcp_debug"))) {
    file.path(gptr_user_dir("cache", create = TRUE), "mcp-logs")
  } else {
    file.path(tempdir(), "gptr", "mcp-logs")
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, paste0(gsub("[^A-Za-z0-9_-]", "_", name), ".log"))
}

#' Append already-redacted text to a log (open, append, close; 5 MB rotation; IC-59)
#' @noRd
mcp_log_append = function(path, txt) {
  if (is.null(path) || !length(txt) || !nzchar(txt)) return(invisible(NULL))
  if (isTRUE(file.size(path) > 5e6)) file.rename(path, paste0(path, ".1"))
  con = file(path, open = "ab")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(as_utf8(txt)), con)
  invisible(NULL)
}

#' One line of server output for the log, through the connection's persist-profile redactor
#' @noRd
mcp_log = function(conn, line) {
  if (is.null(conn$rs)) return(invisible(NULL))
  mcp_log_append(conn$log_path, conn$rs$push(paste0(line, "\n")))
}

# ---- placeholders (expanded at connect time, contract 11.7) -----------------------------------

#' Expand ${VAR}, ${VAR:-default}, ${env:VAR}, ${workspaceFolder} and ${userHome} (IC-63) in a
#' character vector or list; an unset variable without a default becomes ""
#' @noRd
mcp_expand = function(x, project = project_root()) {
  if (is.null(x)) return(NULL)
  if (is.list(x)) return(lapply(x, mcp_expand, project = project))
  if (!is.character(x)) return(x)
  out = vapply(x, mcp_expand1, "", project = project, USE.NAMES = FALSE)
  names(out) = names(x)
  out
}

#' Expand the placeholders of one string; replacement text is spliced in literally
#' @noRd
mcp_expand1 = function(s, project) {
  splice = function(s, pos, len, val) {
    paste0(substr(s, 1L, pos - 1L), val, substr(s, pos + len, nchar(s)))
  }
  fixed = list(c("${userHome}", user_home()), c("${workspaceFolder}", project))
  for (f in fixed) {
    repeat {
      pos = regexpr(f[1L], s, fixed = TRUE)
      if (pos < 0L) break
      s = splice(s, pos, nchar(f[1L]), f[2L])
    }
  }
  for (k in seq_len(50L)) {
    pos = regexpr("\\$\\{(env:)?[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\\}", s)
    if (pos < 0L) break
    m = regmatches(s, pos)
    inner = sub("^\\$\\{(env:)?", "", sub("\\}$", "", m))
    var = sub(":-.*$", "", inner)
    def = if (grepl(":-", inner, fixed = TRUE)) sub("^[^:]*:-", "", inner) else NA_character_
    val = Sys.getenv(var, unset = NA_character_)
    if (is.na(val)) val = if (is.na(def)) "" else def
    s = splice(s, pos, attr(pos, "match.length"), val)
  }
  as_utf8(s)
}

#' Is a header or environment variable name secret-like?
#' @noRd
mcp_secret_name = function(x) grepl("(?i)(key|token|secret|pass|auth|cred|cookie)", x, perl = TRUE)

#' The connect-time view of a spec: placeholders expanded; values that came from a placeholder
#' under a secret-like name, or that look secret, are registered in the vault at once (env
#' entries by their name; `${VAR}` placeholders of args and the URL by the variable's name)
#' @noRd
mcp_expand_spec = function(spec, project = project_root()) {
  raw_args = as.character(unlist(spec$args) %||% character())
  ex = list(command = mcp_expand(spec$command, project),
            args = mcp_expand(raw_args, project),
            env = mcp_expand(unlist(spec$env), project), cwd = mcp_expand(spec$cwd, project),
            url = mcp_expand(spec$url, project),
            headers = mcp_expand(unlist(spec$headers), project))
  raw = unlist(spec$env) %||% character()
  for (k in names(ex$env)) {
    v = ex$env[[k]]
    from_var = grepl("${", raw[[k]], fixed = TRUE)
    if (nchar(v) >= 8L && ((from_var && mcp_secret_name(k)) || !identical(redact(v), v))) {
      secret_register(v, k, source = "mcp")
    }
  }
  refs = unlist(regmatches(c(raw_args, spec$url), gregexpr("\\$\\{(env:)?[A-Za-z_][A-Za-z0-9_]*",
                                                          c(raw_args, spec$url))))
  for (var in unique(sub("^\\$\\{(env:)?", "", refs))) {
    v = Sys.getenv(var, unset = "")
    if (nchar(v) >= 8L && mcp_secret_name(var)) secret_register(as_utf8(v), var, source = "mcp")
  }
  ex
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-client")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 44 ]`

- [ ] **Step 5: Commit**

```bash
git add R/mcp-client.R tests/testthat/test-mcp-client.R
git commit -m "feat(mcp): add the MCP wire helpers, caches and placeholder expansion"
```


---

### Task 4: The MCP client over stdio: era handshake, requests, progress, cancellation, MRTR, elicitation

**Files:**
- Modify: `R/mcp-client.R` (append)
- Create: `tests/testthat/fixtures/mcp/server.R`
- Modify: `tests/testthat/helper-mcp-server.R` (append)
- Test: `tests/testthat/test-mcp-client.R` (append)

**Interfaces:**
- Consumes: Task 3; P01 `gptr_can_prompt()`, `check_list()`, `rscript_path()` (a bare `Rscript` command, and the fixtures); P02 `registry_diagnostic()` (Task 5 uses it); P03 `child_env()`, `redact_stream()`; P04 `proc_spawn()`, `reactor_proc()`, `reactor_pump()`, `reactor_cancel()`, `reactor_now()`, `write_all()`, `write_close()`, `kill_all()`, `proc_pool_cap()`; P11 the `ui.get` service (`has_ui()`, `questions()`); tests: P11 `local_scripted_ui()`.
- Produces: 04 §7.18 `mcp_connect(spec)` -> a `gptr_mcp_conn` environment (fields `name`, `spec`, `transport`, `era` (`"modern"`/`"legacy"`), `version`, `alive`, `tools`, `capabilities`, `instructions`, `server_info`, `era_from_cache`, `log_path`, `proc`); `mcp_tools(conn, refresh = FALSE)` -> list of `list(name, title, description, input_schema, annotations, output_schema)`; `mcp_call(conn, tool, args, timeout = NULL, on_progress = NULL)` -> `list(content, structured, is_error, text, images, elapsed)`; `mcp_close(conn)`; plus `mcp_close_all()`, `mcp_request(conn, method, params = NULL, timeout = NULL, modern = NULL, raw = FALSE, on_progress = NULL, retried = FALSE)`, `mcp_handshake(conn, use_cache = TRUE)`, `mcp_fulfil(conn, requests)`, `mcp_elicit(conn, params)`, `mcp_tool_schema(conn, tool)`, `mcp_stdio_command(command)` (a bare `Rscript`/`R` becomes this R's binary); the test helpers of 04 §12.2: `local_mcp_fixture(era = c("modern", "legacy"), transport = c("stdio", "http"), tools = c("echo", "add", "slow", "fail", "elicit"), n_extra = 0L, .env = parent.frame())` -> `list(spec, log = function() df, stop = function())` and `mcp_fixture_log(path)`.

Report 16 §5.3 (the stdio client) and §5.4 (its tests) moved onto P04's engine: the child starts with `proc_spawn()` and the `mcp` child environment plus the spec's expanded `env` (`.cmd`/`.bat` shims run through `cmd.exe /d /c call`), stdout lines arrive through `reactor_proc()` and stderr goes, redacted, to the log (IC-70), writes are non-blocking `write_all()` calls, and every wait is a `reactor_pump()` with a soft deadline that each progress notification re-arms and a hard deadline of 10 x the timeout. The handshake follows report 16 §2.1 with verification-log fix 3: `server/discover` first; a result listing `"2026-07-28"` means modern; any other answer or a timeout means legacy (`initialize` + `notifications/initialized`); the era is cached for 7 days and re-probed once when a cached era meets `-32600`, `-32601` or `-32602`. Server-to-client requests of the legacy era (`ping`, `roots/list`, `elicitation/create`) are answered outside reactor callbacks; `sampling/createMessage` and everything else is refused with `-32601`. Modern `input_required` results are fulfilled through the same handlers and retried with a new id, `inputResponses` and the echoed `requestState`, at most 5 times. An interrupt or a timeout sends `notifications/cancelled` and drops the late answer; a real Esc would also stop testthat, so the test signals R's `interrupt` condition object instead.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/mcp/server.R` (report 16 §5.2 and §5.9, dual-era, stdio or HTTP on 127.0.0.1; it logs every request it receives to the JSONL file named by `--log`):

```r
# Pure-R MCP fixture server for gptr's tests: either era, over stdio or Streamable HTTP on
# 127.0.0.1. Adapted from dev/research/16-mcp-skills-plugins.md 5.2 (mcp_server_stdio.R) and
# 5.9 (mcp_session_server()): only JSON-RPC on stdout, logs on stderr, ASCII JSON, exit on EOF.
# Usage: Rscript --vanilla server.R --transport=stdio|http --era=modern|legacy
#        --tools=echo,add,slow,fail,elicit --extra=N --log=<path> [--port=N]
args = commandArgs(trailingOnly = TRUE)
arg = function(name, default = NULL) {
  hit = grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[1L]) else default
}
# base R has `%||%` only from R 4.4.0 (the fixture runs on R >= 4.2); an operator keeps its name
`%||%` = function(a, b) if (is.null(a)) b else a # nolint: object_name_linter.
transport = arg("transport", "stdio")
era = arg("era", "modern")
wanted = strsplit(arg("tools", "echo,add,slow,fail,elicit"), ",", fixed = TRUE)[[1L]]
n_extra = as.integer(arg("extra", "0"))
log_path = arg("log", tempfile())
modern_version = "2026-07-28"
legacy_versions = c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
k_ver = "io.modelcontextprotocol/protocolVersion"
k_caps = "io.modelcontextprotocol/clientCapabilities"
k_sinfo = "io.modelcontextprotocol/serverInfo"
page_size = 50L
empty_obj = function() structure(list(), names = character())
info = list(name = "gptr-fixture", version = "1.0.0")

json_ascii = function(s) {
  s = as.character(s)
  Encoding(s) = "UTF-8"
  if (!any(charToRaw(s) > as.raw(127L))) return(s)
  cp = utf8ToInt(s)
  hi = which(cp > 127L)
  out = intToUtf8(cp, multiple = TRUE)
  v = cp[hi]
  esc = character(length(v))
  bmp = v < 65536L
  esc[bmp] = sprintf("\\u%04x", v[bmp])
  a = v[!bmp] - 65536L
  esc[!bmp] = sprintf("\\u%04x\\u%04x", 55296L + a %/% 1024L, 56320L + a %% 1024L)
  out[hi] = esc
  paste(out, collapse = "")
}
to_json = function(x) {
  json_ascii(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}
log_msg = function(msg, via) {
  rec = list(t = as.numeric(Sys.time()), method = msg$method %||% "response", id = msg$id %||% NA,
             era = era, via = via, arguments = msg$params$arguments %||% empty_obj())
  cat(to_json(rec), "\n", sep = "", file = log_path, append = TRUE)
}
rpc_error = function(id, code, message, data = NULL) {
  e = list(code = code, message = message)
  if (!is.null(data)) e$data = data
  list(jsonrpc = "2.0", id = id, error = e)
}

object_schema = function(properties = empty_obj(), required = NULL) {
  s = list(type = "object", properties = properties)
  if (!is.null(required)) s$required = I(required)
  s
}
tool_defs = function() {
  defs = list(
    echo = list(name = "echo", description = "Echo the text back. Use it to test the connection.",
                inputSchema = object_schema(list(text = list(type = "string",
                                                             description = "Text to echo")),
                                            "text"),
                annotations = list(readOnlyHint = TRUE)),
    add = list(name = "add", description = "Add two numbers.",
               inputSchema = object_schema(list(a = list(type = "number"),
                                                b = list(type = "number")), c("a", "b")),
               annotations = list(readOnlyHint = TRUE, destructiveHint = FALSE)),
    slow = list(name = "slow",
                description = "Wait in steps and report progress between the steps.",
                inputSchema = object_schema(list(steps = list(type = "integer"),
                                                 step_ms = list(type = "integer"),
                                                 progress = list(type = "boolean")))),
    fail = list(name = "fail", description = "Always fails with a tool error.",
                inputSchema = object_schema()),
    elicit = list(name = "elicit", description = "Ask the user for a name and greet them.",
                  inputSchema = object_schema()))
  out = unname(defs[intersect(wanted, names(defs))])
  for (i in seq_len(n_extra)) {
    out[[length(out) + 1L]] = list(
      name = sprintf("tool_%03d", i),
      description = sprintf(paste("Generated tool %d for catalog budget tests.",
                                  "It returns its number."), i),
      inputSchema = object_schema(list(query = list(type = "string", description = "A query"),
                                       limit = list(type = "integer")), "query"))
  }
  out
}
tool_list = tool_defs()

finish_modern = function(result, cacheable = FALSE) {
  if (is.null(result$resultType)) result$resultType = "complete"
  result[["_meta"]] = stats::setNames(list(info), k_sinfo)
  if (cacheable) {
    result$ttlMs = 60000L
    result$cacheScope = "public"
  }
  result
}

list_page = function(cursor) {
  start = if (is.null(cursor)) 1L else suppressWarnings(as.integer(cursor))
  if (is.na(start) || start < 1L) return(NULL)
  idx = seq.int(start, length.out = max(0L, min(page_size, length(tool_list) - start + 1L)))
  res = list(tools = unname(tool_list[idx]))
  if (start + page_size <= length(tool_list)) res$nextCursor = as.character(start + page_size)
  res
}

text_result = function(txt, structured = NULL, is_error = FALSE) {
  r = list(content = list(list(type = "text", text = txt)), isError = is_error)
  if (!is.null(structured)) r$structuredContent = structured
  r
}

# The elicit tool: an input_required round (modern) or an elicitation/create request (legacy)
call_elicit = function(params, ctx) {
  form = list(mode = "form", message = "Who are you?",
              requestedSchema = object_schema(list(name = list(type = "string",
                                                               title = "Your name")), "name"))
  if (ctx$modern) {
    if (is.null(params$inputResponses)) {
      return(list(resultType = "input_required", requestState = "state-1",
                  inputRequests = list(who = list(method = "elicitation/create",
                                                  params = form))))
    }
    if (!identical(params$requestState, "state-1")) {
      return(text_result("bad requestState", is_error = TRUE))
    }
    r = params$inputResponses$who
  } else {
    r = ctx$ask(list(jsonrpc = "2.0", id = "e1", method = "elicitation/create",
                     params = form))$result
  }
  if (identical(r$action, "accept")) return(text_result(paste("Hello", r$content$name)))
  text_result(paste("No name:", r$action %||% "none"))
}

# ctx: list(modern, send = function(msg), ask = function(request), progress_token)
call_tool = function(name, a, params, ctx) {
  if (identical(name, "echo")) {
    txt = as.character(a$text %||% "")
    if (startsWith(txt, "stderr:")) {
      cat(substring(txt, 8L), "\n", sep = "", file = stderr())
      flush(stderr())
    }
    return(text_result(txt, list(text = txt)))
  }
  if (identical(name, "add")) {
    s = as.numeric(a$a) + as.numeric(a$b)
    return(text_result(format(s), list(sum = s)))
  }
  if (identical(name, "slow")) {
    steps = as.integer(a$steps %||% 3L)
    step_ms = as.integer(a$step_ms %||% 200L)
    for (i in seq_len(steps)) {
      Sys.sleep(step_ms / 1000)
      if (!isFALSE(a$progress) && !is.null(ctx$progress_token)) {
        ctx$send(list(jsonrpc = "2.0", method = "notifications/progress",
                      params = list(progressToken = ctx$progress_token, progress = i,
                                    total = steps)))
      }
    }
    return(text_result("done"))
  }
  if (identical(name, "fail")) return(text_result("boom", is_error = TRUE))
  if (identical(name, "elicit")) return(call_elicit(params, ctx))
  if (grepl("^tool_[0-9]+$", name)) return(text_result(sub("^tool_0*", "", name)))
  NULL
}

state = new.env()
state$legacy = FALSE

# One request: a response list, or NULL for notifications
handle = function(msg, ctx) {
  id = msg$id
  method = msg$method
  params = msg$params %||% list()
  if (is.null(method)) return(NULL)
  if (is.null(id)) {
    if (identical(method, "notifications/initialized")) state$legacy = TRUE
    return(NULL)
  }
  ok = function(result) list(jsonrpc = "2.0", id = id, result = result)
  meta_ver = params[["_meta"]][[k_ver]]
  if (identical(method, "initialize")) {
    if (identical(era, "modern")) return(rpc_error(id, -32601L, "Method not found: initialize"))
    v = params$protocolVersion
    v = if (!is.null(v) && v %in% legacy_versions) v else legacy_versions[1L]
    state$legacy = TRUE
    return(ok(list(protocolVersion = v, capabilities = list(tools = list(listChanged = FALSE)),
                   serverInfo = info, instructions = "Fixture server.")))
  }
  if (identical(method, "ping")) return(ok(empty_obj()))
  modern = FALSE
  if (!is.null(meta_ver)) {
    if (identical(era, "legacy")) return(rpc_error(id, -32601L, paste("Method not found:", method)))
    if (!identical(meta_ver, modern_version)) {
      return(rpc_error(id, -32022L, "Unsupported protocol version",
                       list(supported = I(modern_version), requested = meta_ver)))
    }
    if (is.null(params[["_meta"]][[k_caps]])) {
      return(rpc_error(id, -32602L, "Missing _meta clientCapabilities"))
    }
    modern = TRUE
  } else if (!isTRUE(state$legacy)) {
    return(rpc_error(id, -32602L, "Missing _meta protocol fields (or send initialize first)"))
  }
  ctx$modern = modern
  ctx$progress_token = params[["_meta"]]$progressToken
  if (identical(method, "server/discover")) {
    return(ok(finish_modern(list(supportedVersions = I(modern_version),
                                 capabilities = list(tools = list(listChanged = FALSE)),
                                 instructions = "Fixture server."), cacheable = TRUE)))
  }
  if (identical(method, "tools/list")) {
    res = list_page(params$cursor)
    if (is.null(res)) return(rpc_error(id, -32602L, "Invalid cursor"))
    return(ok(if (modern) finish_modern(res, cacheable = TRUE) else res))
  }
  if (identical(method, "tools/call")) {
    res = call_tool(as.character(params$name %||% ""), params$arguments %||% list(), params, ctx)
    if (is.null(res)) return(rpc_error(id, -32602L, paste("Unknown tool:", params$name)))
    return(ok(if (modern) finish_modern(res) else res))
  }
  rpc_error(id, -32601L, paste("Method not found:", method))
}

serve_stdio = function() {
  con = file("stdin", open = "r")
  send = function(msg) {
    cat(to_json(msg), "\n", sep = "", file = stdout())
    flush(stdout())
  }
  read_msg = function() {
    repeat {
      line = readLines(con, n = 1L, warn = FALSE, encoding = "UTF-8")
      if (!length(line)) return(NULL)
      line = sub("\r$", "", line)
      if (!nzchar(trimws(line))) next
      msg = tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(msg)) {
        send(rpc_error(NULL, -32700L, "Parse error"))
        next
      }
      log_msg(msg, "stdio")
      return(msg)
    }
  }
  ask = function(request) {
    send(request)
    repeat {
      m = read_msg()
      if (is.null(m)) return(NULL)
      if (identical(m$id, request$id) && is.null(m$method)) return(m)
    }
  }
  repeat {
    msg = read_msg()
    if (is.null(msg)) break
    resp = tryCatch(handle(msg, list(send = send, ask = ask)), error = function(e) {
      rpc_error(msg$id, -32603L, conditionMessage(e))
    })
    if (!is.null(resp)) send(resp)
  }
  close(con)
}

serve_http = function(port) {
  sessions = new.env()
  resp = function(status, body = "", headers = list(), type = "application/json") {
    list(status = status, headers = c(list(`Content-Type` = type), headers), body = body)
  }
  bad = function(status, id, code, message) resp(status, to_json(rpc_error(id, code, message)))
  route = function(req) {
    h = function(name) req[[paste0("HTTP_", toupper(gsub("-", "_", name)))]]
    if (!identical(req$PATH_INFO, "/mcp")) return(resp(404L))
    if (!identical(req$REQUEST_METHOD, "POST")) {
      sid = h("Mcp-Session-Id")
      gone = identical(req$REQUEST_METHOD, "DELETE") && !is.null(sid) &&
        exists(sid, envir = sessions)
      if (gone) {
        rm(list = sid, envir = sessions)
        return(resp(200L))
      }
      return(resp(405L, "", list(Allow = "POST")))
    }
    body = rawToChar(req$rook.input$read())
    Encoding(body) = "UTF-8"
    msg = tryCatch(jsonlite::fromJSON(body, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(msg)) return(bad(400L, NULL, -32700L, "Parse error"))
    log_msg(msg, "http")
    notes = list()
    ctx = list(send = function(m) notes[[length(notes) + 1L]] <<- m, ask = function(r) NULL)
    meta_ver = msg$params[["_meta"]][[k_ver]]
    if (!is.null(meta_ver)) {
      if (identical(era, "legacy")) return(bad(400L, msg$id, -32600L, "Missing Mcp-Session-Id"))
      same = identical(h("MCP-Protocol-Version"), meta_ver) &&
        identical(h("Mcp-Method"), msg$method)
      if (!same) return(bad(400L, msg$id, -32020L, "Header mismatch"))
      if (is.null(msg$id)) return(resp(202L))
      out = handle(msg, ctx)
    } else {
      if (identical(msg$method, "initialize")) {
        out = handle(msg, ctx)
        if (!is.null(out$error)) return(resp(400L, to_json(out)))
        state$n_sessions = (state$n_sessions %||% 0L) + 1L
        sid = sprintf("session-%d-%d", Sys.getpid(), state$n_sessions)
        assign(sid, TRUE, envir = sessions)
        return(resp(200L, to_json(out), list(`Mcp-Session-Id` = sid)))
      }
      if (identical(era, "modern")) {
        return(bad(400L, msg$id, -32602L, "Missing _meta protocol fields"))
      }
      sid = h("Mcp-Session-Id")
      if (is.null(sid)) return(bad(400L, msg$id, -32600L, "Missing Mcp-Session-Id"))
      if (!exists(sid, envir = sessions)) return(resp(404L))
      if (is.null(msg$id)) return(resp(202L))
      state$legacy = TRUE
      out = handle(msg, ctx)
    }
    if (length(notes)) {
      ev = vapply(c(notes, list(out)), function(n) {
        paste0("event: message\ndata: ", to_json(n), "\n\n")
      }, "")
      return(resp(200L, paste(ev, collapse = ""), list(`Cache-Control` = "no-cache"),
                  type = "text/event-stream"))
    }
    resp(200L, to_json(out))
  }
  app = list(call = function(req) {
    tryCatch(route(req), error = function(e) {
      resp(500L, to_json(list(error = conditionMessage(e))))
    })
  })
  srv = tryCatch(httpuv::startServer("127.0.0.1", port, app), error = function(e) NULL)
  if (is.null(srv)) quit(save = "no", status = 3L)
  cat("READY", port, "\n")
  flush(stdout())
  parent = suppressWarnings(as.integer(Sys.getenv("GPTR_FIXTURE_PARENT")))
  repeat {
    httpuv::service(100)
    alive = is.na(parent) ||
      tryCatch(ps::ps_is_running(ps::ps_handle(parent)), error = function(e) FALSE)
    if (!alive) break
  }
  httpuv::stopServer(srv)
}

if (identical(transport, "http")) serve_http(as.integer(arg("port", "0"))) else serve_stdio()
quit(save = "no", status = 0L)
```

Append to the end of `tests/testthat/helper-mcp-server.R`:

```r
# Rows of a fixture server's JSONL request log: df(t, method, id, era, via)
mcp_fixture_log = function(path) {
  empty = data.frame(t = numeric(), method = character(), id = character(), era = character(),
                     via = character(), stringsAsFactors = FALSE)
  if (!file.exists(path)) return(empty)
  lines = readLines(path, warn = FALSE, encoding = "UTF-8")
  if (!length(lines)) return(empty)
  rows = lapply(lines, function(l) {
    x = jsonlite::fromJSON(l, simplifyVector = FALSE)
    data.frame(t = x$t, method = x$method, id = as.character(x$id %||% NA), era = x$era,
               via = x$via, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# The MCP fixture server (contract 12.2): list(spec, log = function() df, stop = function()).
# The spec is a plain list in the shape of a `mcp_server` spec, connectable with mcp_connect().
local_mcp_fixture = function(era = c("modern", "legacy"), transport = c("stdio", "http"),
                             tools = c("echo", "add", "slow", "fail", "elicit"), n_extra = 0L,
                             .env = parent.frame()) {
  era = era[1L]
  transport = transport[1L]
  stopifnot(era %in% c("modern", "legacy"), transport %in% c("stdio", "http"))
  testthat::skip_on_cran()
  log = withr::local_tempfile(fileext = ".jsonl", .local_envir = .env)
  script = file.path(mcp_fixture_dir, "server.R")
  args = c(paste0("--era=", era), paste0("--tools=", paste(tools, collapse = ",")),
           paste0("--extra=", n_extra), paste0("--log=", log))
  spec = if (identical(transport, "stdio")) {
    list(name = "fixture", transport = "stdio", command = rscript_path(),
         args = c("--vanilla", script, args, "--transport=stdio"),
         env = c(R_LIBS = mcp_fixture_libs()), timeout = 30, protocol = "auto")
  } else {
    testthat::skip_if_not_installed("httpuv")
    srv = mcp_fixture_http(script, c(args, "--transport=http"), .env)
    list(name = "fixture", transport = "http",
         url = paste0("http://127.0.0.1:", srv$port, "/mcp"), timeout = 30, protocol = "auto")
  }
  withr::defer(mcp_close_all(), envir = .env)
  list(spec = spec, log = function() mcp_fixture_log(log), stop = function() mcp_close_all())
}
```

Append to the end of `tests/testthat/test-mcp-client.R`:

```r
test_that("a modern stdio server is found by the probe, listed with pagination and called", {
  fx = local_mcp_fixture("modern", "stdio", n_extra = 60L)
  conn = mcp_connect(fx$spec)
  expect_s3_class(conn, "gptr_mcp_conn")
  expect_identical(conn$era, "modern")
  expect_identical(conn$version, "2026-07-28")
  tools = mcp_tools(conn)
  expect_length(tools, 65L)
  expect_identical(tools[[1L]]$name, "echo")
  expect_identical(names(tools[[1L]]),
                   c("name", "title", "description", "input_schema", "annotations",
                     "output_schema"))
  res = mcp_call(conn, "echo", list(text = "x"))
  expect_named(res, c("content", "structured", "is_error", "text", "images", "elapsed"))
  expect_false(res$is_error)
  expect_identical(res$text, "x")
  expect_identical(mcp_value(res), list(text = "x"))
  expect_identical(mcp_value(mcp_call(conn, "add", list(a = 2, b = 3))), list(sum = 5L))
  expect_true(mcp_call(conn, "fail", list())$is_error)
  log = fx$log()
  expect_identical(log$method[1L], "server/discover")
  expect_false("initialize" %in% log$method)
  expect_identical(sum(log$method == "tools/list"), 2L)
  expect_identical(mcp_era_get(fx$spec)$era, "modern")
  mcp_close(conn)
  expect_false(conn$alive)
  expect_false(conn$proc$is_alive())
})

test_that("a legacy stdio server falls back to initialize, and the era is cached", {
  fx = local_mcp_fixture("legacy", "stdio")
  conn = mcp_connect(fx$spec)
  expect_identical(conn$era, "legacy")
  expect_identical(conn$version, "2025-11-25")
  expect_identical(mcp_call(conn, "echo", list(text = "old"))$text, "old")
  mcp_close(conn)
  expect_identical(fx$log()$method[1:3],
                   c("server/discover", "initialize", "notifications/initialized"))
  n_before = nrow(fx$log())
  conn2 = mcp_connect(fx$spec)
  expect_identical(conn2$era, "legacy")
  expect_true(conn2$era_from_cache)
  mcp_close(conn2)
  again = fx$log()[-seq_len(n_before), ]
  expect_identical(again$method[1L], "initialize")
  expect_false("server/discover" %in% again$method)
})

test_that("progress re-arms the idle timer; without progress a call times out and is cancelled", {
  fx = local_mcp_fixture("modern", "stdio")
  conn = mcp_connect(fx$spec)
  seen = new.env()
  seen$n = 0L
  res = mcp_call(conn, "slow", list(steps = 4L, step_ms = 600L), timeout = 1,
                 on_progress = function(p) seen$n = seen$n + 1L)
  expect_identical(res$text, "done")
  expect_identical(seen$n, 4L)
  expect_error(mcp_call(conn, "slow", list(steps = 2L, step_ms = 1500L, progress = FALSE),
                        timeout = 1), class = "gptr_error_timeout")
  reactor_pump(until = function() "notifications/cancelled" %in% fx$log()$method, timeout = 10)
  expect_true("notifications/cancelled" %in% fx$log()$method)
  expect_identical(mcp_call(conn, "echo", list(text = "still alive"))$text, "still alive")
  mcp_close(conn)
})

test_that("an interrupt sends notifications/cancelled and is re-signalled", {
  fx = local_mcp_fixture("modern", "stdio")
  conn = mcp_connect(fx$spec)
  # the condition R signals for Esc/Ctrl-C (a real interrupt would also stop testthat)
  esc = structure(class = c("interrupt", "condition"), list(message = "", call = NULL))
  got = tryCatch(mcp_call(conn, "slow", list(steps = 3L, step_ms = 300L), timeout = 10,
                          on_progress = function(p) stop(esc)),
                 interrupt = function(e) "interrupted")
  expect_identical(got, "interrupted")
  reactor_pump(until = function() "notifications/cancelled" %in% fx$log()$method, timeout = 10)
  expect_true("notifications/cancelled" %in% fx$log()$method)
  mcp_close(conn)
})

test_that("input_required rounds (modern) and elicitation/create (legacy) reach the ask UI", {
  ui = local_scripted_ui(list(list(name = "octocat"), list(name = "octocat")))
  for (era in c("modern", "legacy")) {
    fx = local_mcp_fixture(era, "stdio")
    conn = mcp_connect(fx$spec)
    expect_identical(mcp_call(conn, "elicit", list())$text, "Hello octocat")
    mcp_close(conn)
  }
  expect_identical(ui$log$method, c("questions", "questions"))
  expect_match(ui$log$prompt, "Who are you?", fixed = TRUE)
  fx = local_mcp_fixture("modern", "stdio")
  withr::local_options(gptr.interactive = FALSE)
  conn = mcp_connect(fx$spec)
  expect_identical(mcp_call(conn, "elicit", list())$text, "No name: decline")
  mcp_close(conn)
})

test_that("more than 5 input_required rounds stop the call", {
  st = new.env()
  st$n = 0L
  local_mocked_bindings(
    mcp_tool_schema = function(conn, tool) list(type = "object"),
    mcp_request = function(conn, method, params = NULL, ...) {
      st$n = st$n + 1L
      list(resultType = "input_required", requestState = "s",
           inputRequests = list(r = list(method = "roots/list", params = list())))
    })
  conn = structure(list2env(list(name = "x", project = tempdir())), class = "gptr_mcp_conn")
  expect_error(mcp_call(conn, "t", list()), "more than 5", class = "gptr_error_mcp_protocol")
  expect_identical(st$n, 6L)
})

test_that("sampling requests are refused; roots answer the project directory", {
  conn = structure(list2env(list(name = "x", project = tempdir())), class = "gptr_mcp_conn")
  expect_error(mcp_fulfil(conn, list(s = list(method = "sampling/createMessage"))),
               class = "gptr_error_mcp_protocol")
  roots = mcp_fulfil(conn, list(r = list(method = "roots/list")))$r$roots
  expect_match(roots[[1L]]$uri, "^file://")
})

test_that("server stderr is read by gptr and persisted redacted in tempdir() (IC-70)", {
  vault_reset()
  withr::defer(vault_reset())
  fx = local_mcp_fixture("modern", "stdio")
  key = paste0("sk-test-", strrep("a1b2", 6))
  secret_register(key, "FAKE_MCP_KEY")
  conn = mcp_connect(fx$spec)
  mcp_call(conn, "echo", list(text = paste("stderr:token", key)))
  reactor_pump(until = function() {
    file.exists(conn$log_path) &&
      any(grepl("token", readLines(conn$log_path, warn = FALSE, encoding = "UTF-8")))
  }, timeout = 10)
  mcp_close(conn)
  txt = paste(readLines(conn$log_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl(key, txt, fixed = TRUE))
  expect_match(txt, "[secret:FAKE_MCP_KEY]", fixed = TRUE)
  expect_true(startsWith(normalizePath(conn$log_path), normalizePath(tempdir())))
  withr::local_options(gptr.mcp_debug = TRUE)
  expect_true(startsWith(mcp_log_path("fixture"), gptr_user_dir("cache")))
})

test_that("the sse transport is refused with an actionable error", {
  spec = list(name = "old", type = "sse", url = "http://127.0.0.1:1/sse")
  expect_error(mcp_connect(spec), "Streamable HTTP", class = "gptr_error_mcp_protocol")
})

test_that("a server configured with a bare Rscript command runs with this R's Rscript", {
  expect_identical(mcp_stdio_command("Rscript"), rscript_path())
  expect_identical(mcp_stdio_command("npx"), "npx")
  fx = local_mcp_fixture("modern", "stdio")
  spec = fx$spec
  spec$command = "Rscript"
  conn = mcp_connect(spec)
  expect_identical(mcp_call(conn, "echo", list(text = "via Rscript"))$text, "via Rscript")
  mcp_close(conn)
})

test_that("a .cmd MCP command runs through cmd.exe /d /c call on Windows", {
  skip_on_cran()
  skip_on_os(c("mac", "linux", "solaris"))
  fx = local_mcp_fixture("modern", "stdio")
  shim = file.path(withr::local_tempdir(), "fixture-server.cmd")
  writeLines(c("@echo off", paste0("\"", rscript_path(), "\" %*")), shim)
  spec = fx$spec
  spec$command = shim
  conn = mcp_connect(spec)
  expect_identical(mcp_call(conn, "echo", list(text = "via cmd"))$text, "via cmd")
  mcp_close(conn)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "mcp-client")'` (without `set_max_fails(Inf)` testthat stops after ten failures)
Expected: `[ FAIL 16 | WARN 0 | SKIP 1 | PASS 44 ]`; the first error is `could not find function "mcp_connect"` (the fixture's deferred cleanup adds `could not find function "mcp_close_all"`); the Task 3 tests still pass.

- [ ] **Step 3: Write the implementation**

Append to the end of `R/mcp-client.R`:

```r
# ---- connections: handshake, requests, cancellation, server requests -------------------------

#' Open a connection (contract 7.18): start the transport, then the era handshake (probe,
#' fallback, cache). Returns a `gptr_mcp_conn` environment.
#' @noRd
mcp_connect = function(spec) {
  check_list(spec, "spec", named = TRUE)
  name = as.character(spec$name %||% "server")
  transport = mcp_transport(spec)
  if (identical(transport, "sse")) {
    gptr_abort(paste0("MCP server ", name, " uses the old HTTP+SSE transport, which gptr does ",
                      "not support; use its Streamable HTTP endpoint (often the same URL ending ",
                      "in /mcp)."), c("mcp_protocol", "mcp"), server = name, code = NA_integer_)
  }
  if (!isTRUE(transport %in% c("stdio", "http"))) {
    gptr_abort(paste0("MCP server ", name, " needs a command (stdio) or a url (Streamable HTTP)."),
               c("mcp_protocol", "mcp"), server = name, code = NA_integer_)
  }
  conn = new.env(parent = emptyenv())
  conn$name = name
  conn$spec = spec
  conn$transport = transport
  conn$next_id = 0L
  conn$pending = new.env(parent = emptyenv())
  conn$cancelled = new.env(parent = emptyenv())
  conn$progress = new.env(parent = emptyenv())
  conn$requests = list()
  conn$alive = TRUE
  conn$era = NA_character_
  conn$version = NA_character_
  conn$tools = NULL
  conn$tools_stale = TRUE
  conn$era_from_cache = FALSE
  conn$timeout = as.numeric(spec$timeout %||% gptr_opt("mcp_timeout"))
  conn$project = project_root()
  conn$last_used = reactor_now()
  class(conn) = "gptr_mcp_conn"
  ok = FALSE
  on.exit(if (!ok) mcp_close(conn), add = TRUE)
  if (identical(transport, "stdio")) mcp_stdio_start(conn) else mcp_http_setup(conn)
  mcp_handshake(conn)
  ok = TRUE
  conn
}

#' The era handshake: a cached era skips the probe; otherwise `server/discover` with the modern
#' _meta, and on any other answer or a timeout the legacy initialize and
#' notifications/initialized (report 16 4.5 step 3)
#' @noRd
mcp_handshake = function(conn, use_cache = TRUE) {
  spec = conn$spec
  v = mcp_versions()
  want = as.character(spec$protocol %||% "auto")
  auto = identical(want, "auto")
  cached = if (use_cache && auto) mcp_era_get(spec)
  conn$era = NA_character_
  if (!is.null(cached)) {
    conn$era_from_cache = TRUE
    if (identical(cached$era, "modern")) {
      conn$era = "modern"
      conn$version = v$modern
      return(invisible(conn))
    }
    want = "legacy"
  }
  if (want %in% c("auto", "modern")) {
    probe = tryCatch(
      mcp_request(conn, "server/discover", json_obj(), timeout = gptr_opt("mcp_probe_timeout"),
                  modern = TRUE, raw = TRUE),
      gptr_error_timeout = function(e) list(error = list(code = NA_integer_, message = "timeout")))
    sup = as.character(unlist(probe$result$supportedVersions %||% probe$error$data$supported))
    if (!is.null(probe$result) && v$modern %in% sup) {
      conn$era = "modern"
      conn$version = v$modern
      conn$server_info = probe$result[["_meta"]][[mcp_k_sinfo]]
      conn$capabilities = probe$result$capabilities
      conn$instructions = probe$result$instructions
    } else if (identical(want, "modern") ||
                 isTRUE(probe$error$code == -32022L && v$modern %in% sup)) {
      if (!v$modern %in% sup) {
        gptr_abort(paste0("MCP server ", conn$name, " did not answer as a ", v$modern, " server."),
                   c("mcp_protocol", "mcp"), server = conn$name,
                   code = probe$error$code %||% NA_integer_)
      }
      conn$era = "modern"
      conn$version = v$modern
    }
  }
  if (is.na(conn$era)) {
    init = mcp_request(conn, "initialize",
                       list(protocolVersion = v$legacy[1L], capabilities = mcp_client_caps(),
                            clientInfo = mcp_client_info()), modern = FALSE)
    if (!isTRUE(init$protocolVersion %in% v$legacy)) {
      gptr_abort(paste0("MCP server ", conn$name, " chose protocol version ",
                        init$protocolVersion %||% "(none)", ", which gptr does not speak."),
                 c("mcp_protocol", "mcp"), server = conn$name, code = NA_integer_)
    }
    conn$era = "legacy"
    conn$version = init$protocolVersion
    conn$server_info = init$serverInfo
    conn$capabilities = init$capabilities
    conn$instructions = init$instructions
    mcp_notify(conn, "notifications/initialized")
  }
  if (auto) mcp_era_put(spec, conn$era, conn$version)
  invisible(conn)
}

#' Send a request and wait for its response on the reactor. Every request carries a progress
#' token whose notifications re-arm the soft deadline (`timeout`); the hard deadline is ten
#' times the timeout; a timeout or an interrupt cancels the request.
#' @noRd
mcp_request = function(conn, method, params = NULL, timeout = NULL, modern = NULL, raw = FALSE,
                       on_progress = NULL, retried = FALSE) {
  if (!isTRUE(conn$alive)) {
    gptr_abort(paste0("MCP server ", conn$name, " is not running."), c("mcp_protocol", "mcp"),
               server = conn$name, code = NA_integer_)
  }
  timeout = as.numeric(timeout %||% conn$timeout)
  conn$next_id = conn$next_id + 1L
  conn$last_used = reactor_now()
  id = conn$next_id
  key = as.character(id)
  modern = modern %||% identical(conn$era, "modern")
  params = params %||% json_obj()
  meta = params[["_meta"]] %||% json_obj()
  if (modern) {
    f = mcp_meta_fields(mcp_versions()$modern)
    for (k in names(f)) meta[[k]] = f[[k]]
  }
  tok = paste0("p", id)
  meta$progressToken = tok
  params[["_meta"]] = meta
  st = new.env(parent = emptyenv())
  st$deadline = reactor_now() + timeout
  st$hard = reactor_now() + 10 * timeout
  st$failed = FALSE
  # a named closure, then assign(): lintr's object_usage_linter checks a function literal passed
  # to assign() on its own, without this function's arguments
  on_tick = function(p) {
    st$deadline = reactor_now() + timeout
    if (is.function(on_progress)) on_progress(p)
  }
  assign(tok, on_tick, envir = conn$progress)
  on.exit(if (exists(tok, envir = conn$progress, inherits = FALSE)) {
    rm(list = tok, envir = conn$progress)
  }, add = TRUE)
  msg = list(jsonrpc = "2.0", id = id, method = method, params = params)
  if (identical(conn$transport, "stdio")) {
    mcp_stdio_send(conn, msg)
  } else {
    mcp_http_send(conn, msg, st)
  }
  resp = mcp_await(conn, key, st, id, method, timeout)
  if (identical(conn$transport, "http")) {
    status = as.integer(resp$http_status %||% 200L)
    if (identical(status, 401L)) {
      if (!isTRUE(retried) && mcp_http_auth_retry(conn)) {
        return(mcp_request(conn, method, params, timeout, modern, raw, on_progress, TRUE))
      }
      mcp_auth_required(conn)
    }
    legacy_gone = identical(status, 404L) && identical(conn$era, "legacy") &&
      !is.null(conn$session_id)
    if (legacy_gone && !isTRUE(retried)) {
      conn$session_id = NULL
      mcp_handshake(conn, use_cache = FALSE)
      return(mcp_request(conn, method, params, timeout, modern, raw, on_progress, TRUE))
    }
  }
  if (raw) return(resp)
  if (!is.null(resp$error)) {
    code = suppressWarnings(as.integer(resp$error$code %||% NA_integer_))
    stale = isTRUE(conn$era_from_cache) && !isTRUE(retried) &&
      isTRUE(code %in% c(-32600L, -32601L, -32602L))
    if (stale) {
      conn$era_from_cache = FALSE
      mcp_era_forget(conn$spec)
      mcp_handshake(conn, use_cache = FALSE)
      params[["_meta"]] = NULL
      return(mcp_request(conn, method, params, timeout, NULL, raw, on_progress, TRUE))
    }
    gptr_abort(paste0("MCP server ", conn$name, " answered ", method, " with error ",
                      format(code), ": ", as.character(resp$error$message %||% "")),
               c("mcp_protocol", "mcp"), server = conn$name, code = code)
  }
  resp$result %||% json_obj()
}

#' Pump the reactor until the response, a server request, a failure, an exit or a deadline
#' @noRd
mcp_await = function(conn, key, st, id, method, timeout) {
  done = function() {
    exists(key, envir = conn$pending, inherits = FALSE) || length(conn$requests) > 0L ||
      !isTRUE(conn$alive) || isTRUE(st$failed) || reactor_now() > min(st$deadline, st$hard)
  }
  withCallingHandlers({
    repeat {
      left = min(st$deadline, st$hard) - reactor_now()
      reactor_pump(until = done, slice_ms = 50L, timeout = max(0.05, left))
      if (length(conn$requests)) mcp_answer_requests(conn)
      if (exists(key, envir = conn$pending, inherits = FALSE)) {
        r = get(key, envir = conn$pending, inherits = FALSE)
        rm(list = key, envir = conn$pending)
        if (!is.null(st$status)) r$http_status = st$status
        return(r)
      }
      if (isTRUE(st$failed)) return(st$failure)
      if (!isTRUE(conn$alive)) {
        return(list(error = list(code = NA_integer_, message = "the server process exited"),
                    exited = TRUE))
      }
      if (reactor_now() > min(st$deadline, st$hard)) {
        mcp_cancel(conn, id, st, "timeout")
        gptr_abort(paste0("MCP server ", conn$name, " did not answer ", method, " within ",
                          format(timeout), " s."), "timeout", seconds = timeout,
                   what = paste("MCP", method))
      }
    }
  }, interrupt = function(e) mcp_cancel(conn, id, st, "user interrupt"))
}

#' Cancel an in-flight request: a late answer is dropped; stdio and legacy HTTP send
#' notifications/cancelled; modern HTTP closes the response stream, which is the cancellation
#' @noRd
mcp_cancel = function(conn, id, st, reason) {
  assign(as.character(id), TRUE, envir = conn$cancelled)
  if (identical(conn$transport, "http") && !is.null(st$transfer)) {
    try(reactor_cancel(st$transfer), silent = TRUE)
  }
  if (isTRUE(conn$alive) && (identical(conn$transport, "stdio") || identical(conn$era, "legacy"))) {
    msg = list(jsonrpc = "2.0", method = "notifications/cancelled",
               params = list(requestId = id, reason = reason))
    if (identical(conn$transport, "stdio")) {
      try(mcp_stdio_send(conn, msg), silent = TRUE)
    } else {
      try(mcp_http_send(conn, msg), silent = TRUE)
    }
  }
  invisible(NULL)
}

#' Send a notification
#' @noRd
mcp_notify = function(conn, method, params = NULL) {
  msg = list(jsonrpc = "2.0", method = method)
  if (!is.null(params)) msg$params = params
  mcp_reply(conn, msg)
}

#' Send a message that expects no answer (a notification or a response to a server request)
#' @noRd
mcp_reply = function(conn, msg) {
  if (identical(conn$transport, "stdio")) {
    mcp_stdio_send(conn, msg)
  } else {
    mcp_http_post_quiet(conn, msg)
  }
  invisible(NULL)
}

#' Route one incoming JSON-RPC message: responses by id (late answers to cancelled ids are
#' dropped), notifications to their handlers, server requests queued for mcp_answer_requests()
#' @noRd
mcp_on_message = function(conn, msg) {
  if (!is.list(msg)) return(invisible(NULL))
  id = msg$id
  if (!is.null(id) && (!is.null(msg$result) || !is.null(msg$error))) {
    k = as.character(id)
    if (exists(k, envir = conn$cancelled, inherits = FALSE)) {
      rm(list = k, envir = conn$cancelled)
      return(invisible(NULL))
    }
    assign(k, msg, envir = conn$pending)
    return(invisible(NULL))
  }
  method = msg$method
  if (is.null(method)) return(invisible(NULL))
  if (is.null(id)) {
    if (identical(method, "notifications/progress")) {
      cb = get0(as.character(msg$params$progressToken %||% ""), envir = conn$progress,
                inherits = FALSE)
      if (is.function(cb)) cb(msg$params)
    } else if (identical(method, "notifications/tools/list_changed")) {
      conn$tools_stale = TRUE
    } else if (identical(method, "notifications/message")) {
      mcp_log(conn, paste("[log]", msg$params$level %||% "info", json_encode(msg$params$data)))
    }
    return(invisible(NULL))
  }
  conn$requests[[length(conn$requests) + 1L]] = msg
  invisible(NULL)
}

#' Answer queued server requests (legacy era) outside reactor callbacks: ping, roots/list and
#' elicitation/create through the ask UI; sampling and everything else are refused
#' @noRd
mcp_answer_requests = function(conn) {
  while (length(conn$requests)) {
    req = conn$requests[[1L]]
    conn$requests = conn$requests[-1L]
    out = switch(as.character(req$method),
      ping = mcp_rpc_ok(req$id, json_obj()),
      `roots/list` = mcp_rpc_ok(req$id, mcp_roots(conn)),
      `elicitation/create` = mcp_rpc_ok(req$id, mcp_elicit(conn, req$params)),
      mcp_rpc_err(req$id, -32601L, paste("Method not supported by gptr:", req$method)))
    mcp_reply(conn, out)
  }
  invisible(NULL)
}

#' The roots gptr offers: the project directory
#' @noRd
mcp_roots = function(conn) {
  list(roots = list(list(uri = mcp_file_uri(conn$project), name = basename(conn$project))))
}

#' The UI for elicitation (the ui.get service of P11), or NULL
#' @noRd
mcp_ui = function() if (ext_service_has("ui.get")) ext_service_get("ui.get")(NULL) else NULL

#' Answer an elicitation form through the ask UI; declined without a person (IC-43) and for the
#' URL mode
#' @noRd
mcp_elicit = function(conn, params) {
  if (!identical(params$mode %||% "form", "form") || !gptr_can_prompt()) {
    return(list(action = "decline"))
  }
  ui = mcp_ui()
  if (is.null(ui) || !isTRUE(ui$has_ui())) return(list(action = "decline"))
  props = params$requestedSchema$properties %||% list()
  if (!length(props)) return(list(action = "accept", content = json_obj()))
  qs = lapply(seq_along(props), function(i) {
    p = props[[i]]
    lead = if (i == 1L) {
      paste0("MCP server ", conn$name, " asks: ", params$message %||% "", "\n")
    } else {
      ""
    }
    out = list(id = names(props)[i],
               question = paste0(lead, p$title %||% p$description %||% names(props)[i]),
               type = if (length(p$enum)) "single" else "text")
    if (length(p$enum)) out$options = as.character(unlist(p$enum))
    out
  })
  ans = ui$questions(qs)
  if (isTRUE(ans$cancelled)) return(list(action = "cancel"))
  content = lapply(names(props), function(nm) mcp_elicit_value(ans$answers[[nm]], props[[nm]]))
  names(content) = names(props)
  content = content[!vapply(content, is.null, NA)]
  list(action = "accept", content = if (length(content)) content else json_obj())
}

#' Convert one elicitation answer to the schema's primitive type
#' @noRd
mcp_elicit_value = function(x, p) {
  if (is.null(x) || !length(x)) return(NULL)
  x = as.character(unlist(x))
  switch(as.character(p$type %||% "string"),
    number = as.numeric(x[1L]),
    integer = as.integer(x[1L]),
    boolean = tolower(x[1L]) %in% c("true", "yes", "y", "1"),
    array = as.list(x),
    x[1L])
}

#' Answer the inputRequests of a modern input_required result (MRTR)
#' @noRd
mcp_fulfil = function(conn, requests) {
  out = lapply(names(requests), function(k) {
    r = requests[[k]]
    switch(as.character(r$method),
      `elicitation/create` = mcp_elicit(conn, r$params),
      `roots/list` = mcp_roots(conn),
      gptr_abort(paste0("MCP server ", conn$name, " asked for ", r$method,
                        "; gptr does not let servers call models or other client features."),
                 c("mcp_protocol", "mcp"), server = conn$name, code = -32601L))
  })
  names(out) = names(requests)
  if (length(out)) out else json_obj()
}

#' The paginated tool list (at most 100 pages), kept in memory and in the disk cache
#' @noRd
mcp_tools = function(conn, refresh = FALSE) {
  if (!isTRUE(refresh) && !isTRUE(conn$tools_stale) && !is.null(conn$tools)) return(conn$tools)
  tools = list()
  cursor = NULL
  ttl = NULL
  scope = NULL
  for (i in seq_len(100L)) {
    params = if (is.null(cursor)) json_obj() else list(cursor = cursor)
    res = mcp_request(conn, "tools/list", params)
    tools = c(tools, res$tools %||% list())
    ttl = res$ttlMs %||% ttl
    scope = res$cacheScope %||% scope
    cursor = res$nextCursor
    if (is.null(cursor)) break
  }
  tools = lapply(tools, mcp_tool_norm)
  if (identical(conn$transport, "http") && identical(conn$era, "modern")) {
    tools = Filter(mcp_tool_headers_ok, tools)
  }
  conn$tools = tools
  conn$tools_stale = FALSE
  mcp_tools_cache_put(conn$spec, tools, ttl, scope)
  tools
}

#' HTTP clients drop tools whose x-mcp-header annotations are invalid (2026-07-28)
#' @noRd
mcp_tool_headers_ok = function(tool) {
  props = tool$input_schema$properties %||% list()
  h = unlist(lapply(props, function(p) p[["x-mcp-header"]]))
  all(grepl("^[A-Za-z0-9-]+$", h))
}

#' The input schema of a tool (listing the tools first when needed)
#' @noRd
mcp_tool_schema = function(conn, tool) {
  find = function(tl) Filter(function(t) identical(t$name, tool), tl)
  hit = find(conn$tools %||% mcp_tools(conn))
  if (!length(hit)) hit = find(mcp_tools(conn, refresh = TRUE))
  if (!length(hit)) {
    gptr_abort(paste0("MCP server ", conn$name, " has no tool ", tool, "."),
               c("mcp_protocol", "mcp"),
               server = conn$name, code = -32602L)
  }
  hit[[1L]]$input_schema
}

#' Call a tool (contract 7.18): arguments coerced by the schema, progress re-arms the timer,
#' input_required rounds (MRTR) answered at most 5 times
#' @noRd
mcp_call = function(conn, tool, args, timeout = NULL, on_progress = NULL) {
  t0 = reactor_now()
  schema = mcp_tool_schema(conn, tool)
  obj = c(list(type = "object"), schema[setdiff(names(schema), "type")])
  params = list(name = tool, arguments = mcp_coerce(args %||% list(), obj, "args") %||% json_obj())
  rounds = 0L
  repeat {
    res = mcp_request(conn, "tools/call", params, timeout = timeout, on_progress = on_progress)
    if (!identical(res$resultType, "input_required")) break
    rounds = rounds + 1L
    if (rounds > 5L) {
      gptr_abort(paste0("MCP server ", conn$name, " asked for input more than 5 times in one ",
                        "call of ", tool, "."), c("mcp_protocol", "mcp"), server = conn$name,
                 code = NA_integer_)
    }
    params$inputResponses = mcp_fulfil(conn, res$inputRequests %||% list())
    if (!is.null(res$requestState)) params$requestState = res$requestState
  }
  mcp_result_parse(res, reactor_now() - t0)
}

#' Close a connection (contract 7.18): stdin closed, 2 s grace, then kill_all(); a legacy HTTP
#' session is deleted
#' @noRd
mcp_close = function(conn) {
  if (!inherits(conn, "gptr_mcp_conn")) return(invisible(FALSE))
  if (identical(conn$transport, "stdio") && !is.null(conn$proc)) {
    p = conn$proc
    if (isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))) {
      write_close(p)
      reactor_pump(until = function() !p$is_alive(), slice_ms = 50L, timeout = 2)
      if (p$is_alive()) kill_all(p, grace = 0)
    }
    if (!is.null(conn$watch)) try(reactor_cancel(conn$watch), silent = TRUE)
  } else if (identical(conn$transport, "http") && identical(conn$era, "legacy") &&
               !is.null(conn$session_id)) {
    try(mcp_http_delete(conn), silent = TRUE)
  }
  if (!is.null(conn$rs)) mcp_log_append(conn$log_path, conn$rs$flush())
  conn$alive = FALSE
  invisible(TRUE)
}

#' Close every connection of this process (on unload and in tests)
#' @noRd
mcp_close_all = function() {
  st = mcp_state()
  for (nm in ls(st$conns)) {
    try(mcp_close(get(nm, envir = st$conns)), silent = TRUE)
    rm(list = nm, envir = st$conns)
  }
  invisible(NULL)
}

# ---- stdio transport -----------------------------------------------------------------------

#' Close the least recently used stdio connection while the stdio pool is full (IC-60: at most
#' 2 children under R CMD check, through P04's proc_pool_cap())
#' @noRd
mcp_stdio_make_room = function() {
  st = mcp_state()
  repeat {
    nms = ls(st$conns)
    live = Filter(function(n) {
      c = get(n, envir = st$conns)
      identical(c$transport, "stdio") && isTRUE(c$alive)
    }, nms)
    if (length(live) < proc_pool_cap(64L)) break
    used = vapply(live, function(n) get(n, envir = st$conns)$last_used, 0)
    victim = live[which.min(used)]
    mcp_close(get(victim, envir = st$conns))
    rm(list = victim, envir = st$conns)
  }
  invisible(NULL)
}

#' The program of a stdio server. A bare `Rscript` or `R` (the usual command of R MCP servers,
#' such as `Rscript -e "mcptools::mcp_server()"`) is this R's own binary: P04's proc_resolve()
#' refuses R by name, because R CMD check puts failing R and Rscript scripts first on PATH (IC-60)
#' @noRd
mcp_stdio_command = function(command) {
  if (!is.character(command) || length(command) != 1L) return(command)
  if (command %in% c("Rscript", "Rscript.exe")) return(rscript_path())
  if (command %in% c("R", "R.exe")) {
    return(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"))
  }
  command
}

#' Start a stdio server through the process engine with the mcp child environment plus the
#' spec's expanded env (IC-60; `.cmd`/`.bat` shims run through cmd.exe /d /c call in
#' proc_spawn()); stdout and stderr lines are read by the reactor
#' @noRd
mcp_stdio_start = function(conn) {
  mcp_stdio_make_room()
  ex = mcp_expand_spec(conn$spec, conn$project)
  env = child_env("mcp", set = ex$env %||% character())
  conn$log_path = mcp_log_path(conn$name)
  conn$rs = redact_stream("persist")
  conn$proc = proc_spawn(mcp_stdio_command(ex$command), ex$args, env = env, wd = ex$cwd,
                         stdin = "|", stdout = "|", stderr = "|")
  conn$watch = reactor_proc(conn$proc,
    on_line = function(line) mcp_on_line(conn, line),
    on_exit = function(status) {
      conn$alive = FALSE
      conn$exit_status = status
    },
    stream = "stdout",
    on_stderr = function(line) mcp_log(conn, line))
  invisible(conn)
}

#' One stdout line of a stdio server (anything that is not JSON goes to the log)
#' @noRd
mcp_on_line = function(conn, line) {
  if (!nzchar(trimws(line))) return(invisible(NULL))
  msg = tryCatch(json_decode(line), error = function(e) NULL)
  if (is.null(msg)) {
    mcp_log(conn, paste("[stdout is not JSON]", substr(line, 1L, 200L)))
    return(invisible(NULL))
  }
  mcp_on_message(conn, msg)
}

#' Write one ASCII JSON line to a stdio server (non-blocking inside a pump; IC-60)
#' @noRd
mcp_stdio_send = function(conn, msg) {
  if (!isTRUE(tryCatch(conn$proc$is_alive(), error = function(e) FALSE))) {
    conn$alive = FALSE
    return(invisible(FALSE))
  }
  write_all(conn$proc, paste0(mcp_json(msg), "\n"))
  invisible(TRUE)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-client")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 94 ]` (the skip is the Windows-only `.cmd` test)

- [ ] **Step 5: Commit**

```bash
git add R/mcp-client.R tests/testthat/test-mcp-client.R tests/testthat/helper-mcp-server.R tests/testthat/fixtures/mcp/server.R
git commit -m "feat(mcp): add the dual-era MCP client over stdio"
```


---

### Task 5: The Streamable HTTP transport and stored credentials

**Files:**
- Modify: `R/mcp-client.R` (append)
- Test: `tests/testthat/test-mcp-client.R` (append)

**Interfaces:**
- Consumes: Tasks 1-4; P02 `registry_diagnostic()`; P03 `secret_register()`; P04 `reactor_http()` (one attempt: `retry = list(max_attempts = 1L)`, so a tool call never runs twice; the spec's `first_byte_timeout` and `idle_timeout` are set to the request's hard deadline because MCP keeps its own progress-aware timer), `sse_splitter()`, `url_origin()`; Task 2 `oauth_access()`, `oauth_access_name()`, `oauth_now_ms()`; P03 `auth_store_set()` and `secret_value()` (tests); Task 2 `local_user_dirs()` and `local_oauth_mock()` (tests).
- Produces: the `http` transport of `mcp_connect()`/`mcp_request()`/`mcp_close()`; `mcp_http_setup(conn)`, `mcp_http_auth(conn, force = FALSE)`, `mcp_http_headers(conn, msg)`, `mcp_param_headers(conn, params)`, `mcp_http_send(conn, msg, st = NULL)`, `mcp_http_post_quiet(conn, msg)`, `mcp_http_delete(conn)`, `mcp_http_auth_retry(conn)`, `mcp_auth_required(conn)` (signals `gptr_error_mcp_auth_required` with `server` and `login = "gptr_login(\"mcp:<name>\")"`).

Report 16 §3.4 and §4.5 on P04's reactor (not httr2): every POST carries `Accept: application/json, text/event-stream`; modern requests add `MCP-Protocol-Version` (equal to the `_meta` version), `Mcp-Method`, `Mcp-Name` and `Mcp-Param-*` for `x-mcp-header` properties (tools with an invalid annotation are dropped); legacy requests carry the negotiated version and `Mcp-Session-Id`, re-initialise once on a 404 and `DELETE` the session on close. JSON and SSE bodies feed the same message router as stdio. Configured header values that came from a placeholder, sit under a secret-like name or look secret travel as handles bound to the server's origin. Without a configured `Authorization` header the credential store answers per request (so `gptr_logout()` takes effect at once); a 401 refreshes once, and a second 401, a failed refresh or a credential bound to another origin becomes `gptr_error_mcp_auth_required`, which names the login call: a tool call never opens a browser (03 §6.14).

- [ ] **Step 1: Write the failing test**

Append to the end of `tests/testthat/test-mcp-client.R`:

```r
test_that("Streamable HTTP works in both eras: probe, fallback, cache, list, call, SSE bodies", {
  fx = local_mcp_fixture("modern", "http", n_extra = 55L)
  conn = mcp_connect(fx$spec)
  expect_identical(conn$era, "modern")
  expect_length(mcp_tools(conn), 60L)
  expect_identical(mcp_call(conn, "echo", list(text = "over http"))$text, "over http")
  seen = new.env()
  seen$n = 0L
  res = mcp_call(conn, "slow", list(steps = 2L, step_ms = 50L),
                 on_progress = function(p) seen$n = seen$n + 1L)
  expect_identical(res$text, "done")
  expect_identical(seen$n, 2L)
  mcp_close(conn)

  fx = local_mcp_fixture("legacy", "http")
  conn = mcp_connect(fx$spec)
  expect_identical(conn$era, "legacy")
  expect_false(is.null(conn$session_id))
  expect_identical(mcp_call(conn, "add", list(a = 1, b = 41))$text, "42")
  mcp_close(conn)
  expect_identical(fx$log()$method[1:3],
                   c("server/discover", "initialize", "notifications/initialized"))
  conn = mcp_connect(fx$spec)
  expect_identical(conn$era, "legacy")
  mcp_close(conn)
  expect_identical(sum(fx$log()$method == "server/discover"), 1L)
})

test_that("an HTTP 401 without stored credentials names the login call and opens no browser", {
  local_user_dirs()
  mock = local_oauth_mock()
  browser = local_browser()
  spec = list(name = "secure", transport = "http", url = mock$url, protocol = "auto")
  err = expect_error(mcp_connect(spec), class = "gptr_error_mcp_auth_required")
  expect_match(conditionMessage(err), "gptr_login(\"mcp:secure\")", fixed = TRUE)
  expect_identical(err$login, "gptr_login(\"mcp:secure\")")
  expect_identical(err$server, "secure")
  expect_length(browser$urls, 0L)
})

test_that("stored credentials authorise HTTP requests; a 401 refreshes the token once", {
  local_user_dirs()
  mock = local_oauth_mock()
  spec = list(name = "secure", transport = "http", url = mock$url, protocol = "auto")
  auth_store_set("mcp:secure", list(type = "api_key", key = "manual-token-123"))
  conn = mcp_connect(spec)
  expect_identical(mcp_call(conn, "whoami", list())$text, "you are signed in")
  mcp_close(conn)
  auth_store_set("mcp:secure", list(type = "oauth", issuer = mock$base, client_id = "client-1",
                                    token_endpoint = paste0(mock$base, "/token"),
                                    resource = mock$url, refresh = "refresh-1",
                                    expires = oauth_now_ms() + 3.6e6))
  secret_register("stale-access-token", oauth_access_name("mcp:secure"), source = "oauth",
                  origin = mock$base)
  conn = mcp_connect(spec)
  expect_identical(mcp_call(conn, "whoami", list())$text, "you are signed in")
  mcp_close(conn)
  log = mock$log()
  expect_identical(log$what[log$path == "/token"], "refresh_token")
  expect_identical(secret_value(auth_store_get("mcp:secure")$refresh, mock$base), "refresh-2")
  expect_true(gptr_logout("mcp:secure"))
  expect_null(secret_lookup(oauth_access_name("mcp:secure")))
  conn = mcp_connect(spec)
  expect_true(conn$era_from_cache)
  expect_error(mcp_tools(conn, refresh = TRUE), class = "gptr_error_mcp_auth_required")
  mcp_close(conn)
})

test_that("a credential bound to another origin is never sent; the 401 asks for a sign-in", {
  local_user_dirs()
  mock = local_oauth_mock()
  auth_store_set("mcp:moved", list(type = "oauth", issuer = "http://127.0.0.1:9",
                                   client_id = "client-1",
                                   token_endpoint = "http://127.0.0.1:9/token",
                                   resource = "http://127.0.0.1:9/mcp", refresh = "refresh-x",
                                   expires = oauth_now_ms() + 3.6e6))
  secret_register("access-for-the-old-url", oauth_access_name("mcp:moved"), source = "oauth",
                  origin = "http://127.0.0.1:9")
  spec = list(name = "moved", transport = "http", url = mock$url, protocol = "auto")
  expect_error(mcp_connect(spec), class = "gptr_error_mcp_auth_required")
  expect_false(any(grepl("access-for-the-old-url", mock$log()$what, fixed = TRUE)))
  # a hand-entered token of a server whose URL changed is not sent to the new URL either (the
  # mock would accept it)
  auth_store_set("mcp:moved2", list(type = "api_key", key = "manual-token-123",
                                    resource = "http://127.0.0.1:9/mcp"))
  spec2 = list(name = "moved2", transport = "http", url = mock$url, protocol = "auto")
  expect_error(mcp_connect(spec2), class = "gptr_error_mcp_auth_required")
})

test_that("an access token bound to an https origin on the default port is sent", {
  local_user_dirs()
  auth_store_set("mcp:web", list(type = "oauth", issuer = "https://as.example", client_id = "c1",
                                 token_endpoint = "https://as.example/token",
                                 resource = "https://mcp.example.com/mcp", refresh = "refresh-w",
                                 expires = oauth_now_ms() + 3.6e6))
  value = paste0("access-", "web-abcdefghij")
  secret_register(value, oauth_access_name("mcp:web"), source = "oauth",
                  origin = "https://mcp.example.com")
  conn = list2env(list(name = "web", auth_key = "mcp:web", headers = list(),
                       origin = url_origin("https://mcp.example.com/mcp")))
  auth = mcp_http_auth(conn)
  expect_identical(auth[[1L]], "Bearer ")
  expect_identical(secret_value(auth[[2L]], "https://mcp.example.com/mcp"), value)
  conn$origin = url_origin("https://other.example.com/mcp")
  expect_null(mcp_http_auth(conn))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-client")'`
Expected: `[ FAIL 5 | WARN 0 | SKIP 1 | PASS 94 ]`; the first error is `could not find function "mcp_http_setup"`.

- [ ] **Step 3: Write the implementation**

Append to the end of `R/mcp-client.R`:

```r
# ---- Streamable HTTP transport ---------------------------------------------------------------

#' HTTP setup: the expanded URL, its origin, the configured headers (values that came from a
#' placeholder, sit under a secret-like name or look secret travel as handles bound to the
#' server's origin) and the credential-store key "mcp:<name>"
#' @noRd
mcp_http_setup = function(conn) {
  ex = mcp_expand_spec(conn$spec, conn$project)
  conn$url = ex$url
  conn$origin = url_origin(ex$url)
  raw = unlist(conn$spec$headers) %||% character()
  hdr = list()
  for (k in names(ex$headers)) {
    v = ex$headers[[k]]
    secret = grepl("${", raw[[k]], fixed = TRUE) || mcp_secret_name(k) || !identical(redact(v), v)
    hdr[[k]] = if (secret && nzchar(v)) {
      nm = paste0("MCP_", toupper(gsub("[^A-Za-z0-9]+", "_", conn$name)), "_",
                  toupper(gsub("[^A-Za-z0-9]+", "_", k)))
      secret_register(v, nm, source = "mcp", origin = conn$origin)
    } else {
      v
    }
  }
  conn$headers = hdr
  conn$auth_key = paste0("mcp:", conn$name)
  conn$session_id = NULL
  invisible(conn)
}

#' The Authorization value of a connection: a configured header wins; otherwise the credential
#' store's (oauth_access(): an API key or an OAuth access token, refreshed under a lock); read
#' per request, so gptr_logout() takes effect at once. NULL when there is none, when it is bound
#' to another origin, or when the refresh failed (a registry diagnostic): the server's 401 then
#' asks the user to sign in again.
#' @noRd
mcp_http_auth = function(conn, force = FALSE) {
  if ("authorization" %in% tolower(names(conn$headers))) return(NULL)
  auth = tryCatch(oauth_access(conn$auth_key, conn$origin, force = force),
                  gptr_error = function(e) {
                    registry_diagnostic("builtin:mcp", "mcp_auth", class(e)[1L],
                                        conditionMessage(e))
                    NULL
                  })
  h = if (is.list(auth) && length(auth) == 2L) auth[[2L]]
  # P03 keeps handle origins canonically with the port (https://host:443); url_origin() drops
  # default ports, so both sides are compared in url_origin()'s form
  if (inherits(h, "gptr_secret") && !is.null(h$origin) &&
        !identical(url_origin(h$origin), conn$origin)) {
    return(NULL)
  }
  auth
}

#' Headers of one POST: Accept, content type, the configured headers, Authorization from the
#' credential store (oauth_access()), and the era headers (MCP-Protocol-Version, Mcp-Method,
#' Mcp-Name, Mcp-Param-*, or the legacy version and Mcp-Session-Id)
#' @noRd
mcp_http_headers = function(conn, msg) {
  h = c(list(Accept = "application/json, text/event-stream", `Content-Type` = "application/json"),
        conn$headers)
  auth = mcp_http_auth(conn)
  if (!is.null(auth)) h$Authorization = auth
  meta_ver = msg$params[["_meta"]][[mcp_k_ver]]
  if (!is.null(meta_ver)) {
    h[["MCP-Protocol-Version"]] = meta_ver
    h[["Mcp-Method"]] = msg$method
    if (isTRUE(msg$method %in% c("tools/call", "prompts/get"))) {
      h[["Mcp-Name"]] = mcp_header_value(msg$params$name)
    }
    if (identical(msg$method, "resources/read")) h[["Mcp-Name"]] = mcp_header_value(msg$params$uri)
    if (identical(msg$method, "tools/call")) h = c(h, mcp_param_headers(conn, msg$params))
  } else if (identical(conn$era, "legacy") && !is.na(conn$version)) {
    h[["MCP-Protocol-Version"]] = conn$version
  }
  if (!is.null(conn$session_id)) h[["Mcp-Session-Id"]] = conn$session_id
  h
}

#' Mcp-Param-<Name> headers for arguments whose schema property carries x-mcp-header
#' @noRd
mcp_param_headers = function(conn, params) {
  tool = Filter(function(t) identical(t$name, params$name), conn$tools %||% list())
  if (!length(tool)) return(list())
  props = tool[[1L]]$input_schema$properties %||% list()
  out = list()
  for (p in names(props)) {
    h = props[[p]][["x-mcp-header"]]
    v = params$arguments[[p]]
    if (is.character(h) && !is.null(v)) out[[paste0("Mcp-Param-", h)]] = mcp_header_value(format(v))
  }
  out
}

#' POST one JSON-RPC message on the reactor (no retry: a tool call must not run twice). JSON
#' and SSE bodies are routed through mcp_on_message(); a failed transfer marks the request
#' state with its HTTP status. The reactor's first-byte and idle timers are set to the
#' request's hard deadline: MCP enforces its own, progress-aware timeout.
#' @noRd
mcp_http_send = function(conn, msg, st = NULL) {
  st = st %||% new.env(parent = emptyenv())
  st$chunks = list()
  st$sse = NULL
  st$status = NA_integer_
  st$done = FALSE
  st$failed = FALSE
  hard = if (is.null(st$hard)) 30 else max(1, st$hard - reactor_now())
  spec = list(url = conn$url, method = "POST", headers = mcp_http_headers(conn, msg),
              body = mcp_json(msg), first_byte_timeout = hard, idle_timeout = hard)
  st$transfer = reactor_http(spec,
    on_bytes = function(raw) mcp_http_bytes(conn, st, raw),
    on_done = function(status, headers) mcp_http_done(conn, st, msg, status),
    on_fail = function(cnd) mcp_http_fail(st, cnd),
    on_headers = function(status, headers) mcp_http_head(conn, st, msg, status, headers),
    retry = list(max_attempts = 1L))
  invisible(st)
}

#' A 2xx response head: an SSE body gets a splitter; initialize's Mcp-Session-Id is kept
#' @noRd
mcp_http_head = function(conn, st, msg, status, headers) {
  st$status = as.integer(status)
  ctype = hdr_value(headers, "Content-Type") %||% ""
  if (grepl("text/event-stream", ctype, fixed = TRUE)) st$sse = sse_splitter()
  sid = hdr_value(headers, "Mcp-Session-Id")
  if (!is.null(sid) && identical(msg$method, "initialize")) conn$session_id = sid
  invisible(NULL)
}

#' Response bytes: SSE events are dispatched as they arrive, JSON bodies are collected
#' @noRd
mcp_http_bytes = function(conn, st, raw) {
  if (!is.null(st$sse)) {
    for (ev in st$sse$push(raw)) mcp_http_event(conn, ev$data)
  } else {
    st$chunks[[length(st$chunks) + 1L]] = raw
  }
  invisible(NULL)
}

#' One SSE data payload
#' @noRd
mcp_http_event = function(conn, data) {
  if (is.null(data) || !nzchar(data)) return(invisible(NULL))
  msg = tryCatch(json_decode(data), error = function(e) NULL)
  if (!is.null(msg)) mcp_on_message(conn, msg)
  invisible(NULL)
}

#' End of a 2xx response: the JSON body is dispatched; a request left without an answer fails
#' @noRd
mcp_http_done = function(conn, st, msg, status) {
  st$status = as.integer(status)
  if (!is.null(st$sse)) {
    last = st$sse$flush()
    if (!is.null(last)) mcp_http_event(conn, last$data)
  } else if (length(st$chunks)) {
    txt = raw_to_utf8(do.call(c, st$chunks))
    if (nzchar(trimws(txt))) {
      body = tryCatch(json_decode(txt), error = function(e) NULL)
      if (is.list(body)) mcp_on_message(conn, body)
    }
  }
  st$done = TRUE
  if (!is.null(msg$id) && !exists(as.character(msg$id), envir = conn$pending, inherits = FALSE)) {
    st$failure = list(error = list(code = NA_integer_,
                                   message = paste0("HTTP ", status, " without a JSON-RPC answer")),
                      http_status = st$status)
    st$failed = TRUE
  }
  invisible(NULL)
}

#' A failed transfer (non-2xx, network, redirect, timeout): the request fails with the status
#' @noRd
mcp_http_fail = function(st, cnd) {
  st$done = TRUE
  st$status = suppressWarnings(as.integer(cnd$status %||% NA_integer_))
  st$failure = list(error = list(code = NA_integer_, message = conditionMessage(cnd)),
                    http_status = st$status)
  st$failed = TRUE
  invisible(NULL)
}

#' POST a notification or a response and wait (at most 10 s) until the server took it
#' @noRd
mcp_http_post_quiet = function(conn, msg) {
  st = mcp_http_send(conn, msg)
  reactor_pump(until = function() isTRUE(st$done), slice_ms = 50L, timeout = 10)
  invisible(st)
}

#' DELETE the legacy session
#' @noRd
mcp_http_delete = function(conn) {
  st = new.env(parent = emptyenv())
  st$done = FALSE
  hdr = c(conn$headers, list(`Mcp-Session-Id` = conn$session_id))
  auth = mcp_http_auth(conn)
  if (!is.null(auth)) hdr$Authorization = auth
  reactor_http(list(url = conn$url, method = "DELETE", headers = hdr, body = NULL),
               on_bytes = function(raw) NULL,
               on_done = function(status, headers) st$done = TRUE,
               on_fail = function(cnd) st$done = TRUE,
               retry = list(max_attempts = 1L))
  reactor_pump(until = function() isTRUE(st$done), slice_ms = 50L, timeout = 5)
  invisible(NULL)
}

#' After a 401: refresh the stored credential; TRUE when a retry makes sense (a configured
#' Authorization header or no stored credential means the user must sign in)
#' @noRd
mcp_http_auth_retry = function(conn) {
  !is.null(mcp_http_auth(conn, force = TRUE))
}

#' The server needs a sign-in. A tool call never opens a browser (architecture 6.14): the
#' condition names the login call.
#' @noRd
mcp_auth_required = function(conn) {
  login = paste0("gptr_login(\"mcp:", conn$name, "\")")
  gptr_abort(paste0("MCP server ", conn$name, " needs a sign-in. Run ", login,
                    " at the R prompt, then retry."), c("mcp_auth_required", "mcp"),
             server = conn$name, login = login)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-client")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 124 ]`

- [ ] **Step 5: Commit**

```bash
git add R/mcp-client.R tests/testthat/test-mcp-client.R
git commit -m "feat(mcp): add the Streamable HTTP transport of the MCP client"
```


---

### Task 6: MCP configuration: gptr's `mcp.json`, other harnesses, `gptr_mcp()`, `gptr_mcp_add()`, `gptr_mcp_remove()`

**Files:**
- Create: `R/mcp-config.R`
- Modify: `tests/testthat/helper-mcp-server.R` (append)
- Test: `tests/testthat/test-mcp-config.R` (create)
- Generated: `NAMESPACE`, `man/gptr_mcp.Rd`, `man/gptr_mcp_add.Rd`

**Interfaces:**
- Consumes: Tasks 1-5; P01 `user_home()`, `app_config_dir()`, `path_key()`, `path_norm()` (tests), `gptr_user_dir()`, `workspace_dir()`, `project_root()`, `write_atomic()`, `read_utf8()`, `new_listing()`, `est_tokens()`, `schema_signature()`, the checkers; P02 `gptr_spec("mcp_server", name, ...)`, `registry_add()`, `registry_remove()`, `registry_get()`, `registry_names()`, `registry_diagnostic()`, `ev_dispatch()`, `hook_add()`/`hook_remove()` (tests), `ext_control_guard()`; P03 `redact()`; P08 the `trust.get` service (fallback: untrusted); P10 `glob_to_regex()`; tests: P01 `local_project()`, `local_gptr_options()`.
- Produces: the exports of 04 §6.3 `gptr_mcp(server = NULL, tools = FALSE, refresh = FALSE)` -> a `gptr_mcp_servers` listing (`name`, `source`, `transport`, `era`, `status`, `tools`, `exposure`, `tokens`, `trusted`) or, with `tools = TRUE`, a data frame `server`, `tool`, `signature`, `exposure`, `tokens`; `gptr_mcp_add(name, command = NULL, args = character(), url = NULL, env = NULL, headers = NULL, exposure = "r", timeout = 60, scope = c("user", "project"))` -> the `mcp_server` spec invisibly; `gptr_mcp_remove(name, scope = c("user", "project"))` -> `invisible(<lgl: removed>)`; both emit `mcp_servers_change` (`added`, `removed`). Internal: 04 §7.18 `mcp_config_all(project = project_root())` -> named list of entries in the 04 §11.7 shape with `source` (`gptr:user`, `gptr:project`, `<harness>:<scope>`), `trusted`, `also_in` (plus `startable`, `needs_input`, `path`); `mcp_toml_read(file = NULL, text = NULL)`; `mcp_sync(force = FALSE, session = NULL)` -> the `mcp_server` specs visible to `session`, by name; `mcp_servers_all(session = NULL)`; `mcp_server_resolve(name, session = NULL)`; `mcp_server_get(name, session = NULL)`; `mcp_conn_get(name, session = NULL)`; `mcp_usable(s)`; `mcp_foreign(s)`; `mcp_tools_known(s)`; `mcp_tool_exposure(s, tool)`; `mcp_server_lines(s, tools, keep = NULL, bare = character(), exposures = "r")`, `mcp_unlisted_line(name)` (the line of a server whose tools are not known yet); `mcp_forget_conn(name)`; `mcp_file_update(path, fun)`; test helpers `local_mcp_home()`, `write_json_file(path, x)`, `local_mcp_server(fx, name = "fixture")`.

Report 16 §5.11 (harness-agnostic discovery, verified after its fixture-relocation fix: verification log 46) and §5.12 (the TOML reader; 36 of 39 values agree with RcppTOML and the three differences are RcppTOML's: verification log 27). Sources in precedence order (earlier rows win on a name collision): gptr's project file (used only when the project is trusted), gptr's user file, then the harnesses of setting `mcp.import` in the order Claude Code (local, project `.mcp.json`, user `~/.claude.json`), Claude Desktop, Codex (project, then `$CODEX_HOME` or `~/.codex`), Cursor, VS Code, Pi. A server with the same command, args and URL in several harnesses is listed once with `also_in`; another harness's server whose name collides is renamed `<harness>_<name>`. Codex's `env_vars`, `http_headers`, `env_http_headers`, `bearer_token_env_var`, `tool_timeout_sec` and `enabled_tools`/`disabled_tools`, Claude Code's millisecond `timeout` and VS Code's `servers` map are normalised; VS Code `${input:...}` values mark the entry `needs input`; gptr's `defaults` apply to its own entries. Records: gptr:user at rank 3 (source `user`), a trusted gptr:project at rank 1 (source `project`), every other entry at rank 6 (source `builtin:mcp`), so plugins and sessions (rank 0/5, P17) keep winning. Foreign servers are reachable by name but never advertised (D-14, Task 7). Nothing connects while listing.

- [ ] **Step 1: Write the failing test**

Append to the end of `tests/testthat/helper-mcp-server.R`:

```r
# A fresh user config directory, home and vault for the calling test, so that gptr's user
# mcp.json, the foreign harness files and the secrets of one test never reach another
local_mcp_home = function(.env = parent.frame()) {
  home = path_norm(withr::local_tempdir("home-", .local_envir = .env))
  withr::local_envvar(HOME = home, USERPROFILE = home,
                      APPDATA = file.path(home, "AppData", "Roaming"),
                      XDG_CONFIG_HOME = file.path(home, ".config"), CODEX_HOME = "",
                      R_USER_CONFIG_DIR = file.path(home, "gptr-config"),
                      R_USER_CACHE_DIR = file.path(home, "gptr-cache"), .local_envir = .env)
  vault_reset()
  withr::defer(vault_reset(), envir = .env)
  withr::defer(mcp_sync(force = TRUE), envir = .env)
  home
}

write_json_file = function(path, x) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_atomic(path, json_encode(x, pretty = TRUE))
}

# Register a fixture (local_mcp_fixture()) as gptr's user server `name` for the calling test
local_mcp_server = function(fx, name = "fixture", .env = parent.frame()) {
  s = fx$spec
  if (identical(s$transport, "stdio")) {
    gptr_mcp_add(name, command = s$command, args = s$args, env = s$env, timeout = 30)
  } else {
    gptr_mcp_add(name, url = s$url, timeout = 30)
  }
  withr::defer(gptr_mcp_remove(name), envir = .env)
  invisible(name)
}
```

Create `tests/testthat/test-mcp-config.R`:

```r
# Configurations of every harness gptr reads, in a temporary home and project
local_foreign_configs = function(trust = FALSE, files = list(), .env = parent.frame()) {
  home = local_mcp_home(.env)
  proj = local_project(files = files, trust = trust, .env = .env)
  write_json_file(file.path(proj, ".mcp.json"), list(mcpServers = list(
    filesystem = list(command = "npx",
                      args = I(c("-y", "@modelcontextprotocol/server-filesystem", "."))),
    sentry = list(type = "http", url = "https://mcp.sentry.dev/mcp"))))
  claude = list(numStartups = 3L, mcpServers = list(github = list(
    type = "http", url = "https://api.githubcopilot.com/mcp/",
    headers = list(Authorization = "Bearer ${GITHUB_TOKEN}"), timeout = 120000L)))
  claude$projects = list()
  claude$projects[[proj]] = list(mcpServers = list(`local-db` = list(
    type = "stdio", command = "uvx",
    args = I(c("mcp-server-sqlite", "--db-path", "${CLAUDE_PROJECT_DIR:-.}/data.db")))))
  write_json_file(file.path(home, ".claude.json"), claude)
  write_json_file(file.path(app_config_dir("Claude"), "claude_desktop_config.json"),
                  list(mcpServers = list(filesystem = list(
                    command = "npx",
                    args = I(c("-y", "@modelcontextprotocol/server-filesystem", "."))))))
  dir.create(file.path(home, ".codex"), showWarnings = FALSE)
  writeLines(c("model = \"gpt-5.5\"", "[mcp_servers.context7]", "command = \"npx\"",
               "args = [\"-y\", \"@upstash/context7-mcp@latest\"]", "tool_timeout_sec = 90",
               "[mcp_servers.figma]", "url = \"https://mcp.figma.com/mcp\"",
               "bearer_token_env_var = \"FIGMA_OAUTH_TOKEN\"", "enabled_tools = [\"get_file\"]",
               "enabled = false"), file.path(home, ".codex", "config.toml"))
  write_json_file(file.path(proj, ".vscode", "mcp.json"), list(
    inputs = list(list(type = "promptString", id = "k", password = TRUE)),
    servers = list(perplexity = list(type = "stdio", command = "npx",
                                     args = I("server-perplexity-ask"),
                                     env = list(PERPLEXITY_API_KEY = "${input:k}")))))
  write_json_file(file.path(home, ".pi", "agent", "mcp.json"), list(mcpServers = list(
    docs = list(url = "https://example.com/mcp", exposure = "deferred"))))
  list(home = home, project = proj)
}

test_that("the TOML subset reads a Codex config", {
  x = mcp_toml_read(text = c(
    "# comment", "model = \"gpt-5.5\"", "[mcp_servers.context7]", "command = \"npx\"",
    "args = [\"-y\", \"pkg\"]   # trailing", "tool_timeout_sec = 60.5",
    "[mcp_servers.context7.env]", "K = \"v\"", "\"QUOTED.KEY\" = 'C:\\Users'",
    "[mcp_servers.\"r-session\"]", "command = 'Rscript'", "env_vars = [\"HOME\"]",
    "[[skills.config]]", "path = \"a\"", "[[skills.config]]", "path = \"b\"",
    "[misc]", "hex = 0xDEAD_BEEF", "big = 9_007_199_254_740_991",
    "ml = \"\"\"", "Roses \\", "   violets\"\"\"", "empty = []", "t = { a = 1, b = [1, 2] }",
    "when = 1979-05-27T07:32:00Z"))
  expect_identical(x$model, "gpt-5.5")
  expect_identical(x$mcp_servers$context7$args, c("-y", "pkg"))
  expect_identical(x$mcp_servers$context7$tool_timeout_sec, 60.5)
  expect_identical(x$mcp_servers$context7$env$QUOTED.KEY, "C:\\Users")
  expect_identical(x$mcp_servers[["r-session"]]$env_vars, "HOME")
  expect_identical(vapply(x$skills$config, `[[`, "", "path"), c("a", "b"))
  expect_identical(x$misc$hex, 3735928559)
  expect_identical(x$misc$big, 9007199254740991)
  expect_identical(x$misc$ml, "Roses violets")
  expect_identical(x$misc$empty, list())
  expect_identical(x$misc$t$b, 1:2)
  expect_identical(x$misc$when, "1979-05-27T07:32:00Z")
  expect_error(mcp_toml_read(text = "a = [1, 2\nb = 3"), "line 2",
               class = "gptr_error_invalid_argument")
})

test_that("foreign configs are found under user_home() and app_config_dir() and merged (IC-63)", {
  fx = local_foreign_configs()
  specs = mcp_config_all(fx$project)
  expect_setequal(names(specs), c("local-db", "filesystem", "sentry", "github", "context7",
                                  "figma", "perplexity", "docs"))
  expect_identical(specs$`local-db`$source, "claude-code:local")
  expect_identical(specs$filesystem$source, "claude-code:project")
  expect_identical(specs$filesystem$also_in, "claude-desktop:user")
  expect_identical(specs$github$timeout, 120)
  expect_identical(specs$github$headers[["Authorization"]], "Bearer ${GITHUB_TOKEN}")
  expect_identical(specs$context7$timeout, 90)
  expect_identical(specs$figma$headers[["Authorization"]], "Bearer ${FIGMA_OAUTH_TOKEN}")
  expect_false(specs$figma$enabled)
  expect_identical(specs$figma$toolExposure, list(get_file = "r", `*` = "hidden"))
  expect_true(specs$perplexity$needs_input)
  expect_identical(specs$docs$exposure, "deferred")
  expect_false(specs$filesystem$startable)
  expect_true(specs$github$startable)
  expect_false(specs$github$trusted)
})

test_that("timeouts: seconds in gptr's and Codex's files, milliseconds in Claude Code's", {
  tmo = function(x, harness) {
    mcp_entry_norm("s", c(list(command = "srv"), x), harness, "user", "p")$timeout
  }
  expect_identical(tmo(list(timeout = 3600), "gptr"), 3600)
  expect_identical(tmo(list(tool_timeout_sec = 3600), "codex"), 3600)
  expect_identical(tmo(list(timeout = 3600000), "claude-code"), 3600)
  expect_identical(tmo(list(timeout = 90000), "cursor"), 90)
  expect_identical(tmo(list(timeout = 120), "cursor"), 120)
})

test_that("gptr's own files win, defaults apply, and the import setting limits the harnesses", {
  project_mcp = json_encode(list(mcpServers = list(
    sentry = list(url = "https://sentry.example/mcp"))))
  fx = local_foreign_configs(trust = TRUE, files = list(".gptr/mcp.json" = project_mcp))
  write_json_file(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"), list(
    mcpServers = list(github = list(url = "https://gh.example/mcp", trusted = TRUE)),
    defaults = list(exposure = "deferred", timeout = 30)))
  specs = mcp_config_all(fx$project)
  expect_identical(specs$github$source, "gptr:user")
  expect_true(specs$github$trusted)
  expect_identical(specs$github$exposure, "deferred")
  expect_identical(specs$github$timeout, 30)
  expect_identical(specs$sentry$source, "gptr:project")
  expect_true(specs$sentry$startable)
  expect_identical(specs$`claude-code_github`$source, "claude-code:user")
  expect_identical(specs$`claude-code_sentry`$source, "claude-code:project")
  expect_identical(gptr_mcp()$status[gptr_mcp()$name == "perplexity"], "needs input")
  local_gptr_options(mcp = list(import = "codex"))
  expect_setequal(names(mcp_config_all(fx$project)), c("github", "sentry", "context7", "figma"))
})

test_that("gptr_mcp() lists servers without connecting; untrusted project servers never start", {
  fx = local_foreign_configs()
  write_json_file(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"), list(
    mcpServers = list(old = list(type = "sse", url = "https://old.example/sse"))))
  spec = list(command = "npx", args = c("-y", "@upstash/context7-mcp@latest"))
  mcp_era_put(spec, "modern", "2026-07-28")
  procs = length(ps::ps_children(ps::ps_handle()))
  x = gptr_mcp()
  expect_s3_class(x, c("gptr_mcp_servers", "gptr_listing", "data.frame"))
  expect_identical(names(x), c("name", "source", "transport", "era", "status", "tools",
                               "exposure", "tokens", "trusted"))
  expect_identical(length(ps::ps_children(ps::ps_handle())), procs)
  row = function(n) x[x$name == n, ]
  expect_identical(row("context7")$era, "modern")
  expect_identical(row("figma")$status, "disabled")
  expect_identical(row("filesystem")$status, "untrusted")
  expect_false(row("filesystem")$trusted)
  expect_identical(row("perplexity")$status, "untrusted")
  expect_identical(row("old")$status, "unsupported (sse)")
  expect_identical(row("github")$status, "configured")
  expect_error(gptr_mcp("filesystem", tools = TRUE), class = "gptr_error_untrusted")
  expect_error(gptr_mcp("nope"), class = "gptr_error_unknown_member")
  expect_error(gptr_mcp(tools = NA), class = "gptr_error_invalid_argument")
})

test_that("a .claude.json under the user's profile is listed (Windows home, IC-63)", {
  home = local_mcp_home()
  other = withr::local_tempdir("not-home-")
  if (.Platform$OS.type == "windows") withr::local_envvar(HOME = other)
  write_json_file(file.path(home, ".claude.json"), list(mcpServers = list(
    winsrv = list(command = "uvx", args = I("mcp-server-time")))))
  local_project()
  x = gptr_mcp()
  expect_identical(x$source[x$name == "winsrv"], "claude-code:user")
})

test_that("gptr_mcp_add() and gptr_mcp_remove() write gptr's own mcp.json only", {
  fx = local_foreign_configs()
  seen = new.env()
  seen$events = list()
  off = hook_add("mcp_servers_change", function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  })
  withr::defer(hook_remove(off))
  claude_before = readLines(file.path(fx$home, ".claude.json"), encoding = "UTF-8")
  spec = gptr_mcp_add("fs", command = "npx", args = c("-y", "server-fs"),
                      env = c(LOG_LEVEL = "info", API_KEY = "${FS_KEY}"), timeout = 120)
  expect_s3_class(spec, "gptr_mcp_server")
  expect_identical(spec$source, "gptr:user")
  path = file.path(gptr_user_dir("config"), "mcp.json")
  x = json_decode(read_utf8(path)$text)
  expect_identical(x$mcpServers$fs$command, "npx")
  expect_identical(x$mcpServers$fs$args, list("-y", "server-fs"))
  expect_identical(x$mcpServers$fs$env$API_KEY, "${FS_KEY}")
  expect_identical(x$mcpServers$fs$timeout, 120L)
  gptr_mcp_add("web", url = "https://web.example/mcp",
                headers = c(Authorization = "Bearer ${WEB_TOKEN}"), exposure = "direct")
  expect_setequal(names(json_decode(read_utf8(path)$text)$mcpServers), c("fs", "web"))
  expect_identical(readLines(file.path(fx$home, ".claude.json"), encoding = "UTF-8"),
                   claude_before)
  expect_true(gptr_mcp_remove("fs"))
  expect_false(gptr_mcp_remove("fs"))
  expect_identical(names(json_decode(read_utf8(path)$text)$mcpServers), "web")
  expect_identical(vapply(seen$events, function(e) length(e$added), 0L), c(1L, 1L, 0L))
  expect_identical(seen$events[[3L]]$removed, "fs")
  expect_false(dir.exists(paste0(path, ".lock")))
  gptr_mcp_add("proj", command = "srv", scope = "project")
  expect_identical(names(json_decode(read_utf8(file.path(fx$project, ".gptr", "mcp.json"))$text)$
                           mcpServers), "proj")
  expect_true(gptr_mcp_remove("proj", scope = "project"))
})

test_that("gptr_mcp_add() validates its arguments and refuses literal secrets", {
  local_mcp_home()
  local_project(gptr = FALSE)
  expect_error(gptr_mcp_add("bad name", command = "x"), class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_add("x"), "exactly one", class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_add("x", command = "a", url = "https://b"), "exactly one",
               class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_add("x", command = "a", exposure = "loud"),
               class = "gptr_error_invalid_argument")
  literal = paste0("Bearer sk-ant-api03-", "abcdefghijklmnopqrstuvwxyz0123456789")
  err = expect_error(gptr_mcp_add("x", url = "https://b/mcp", headers = c(Authorization = literal)),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "headers$Authorization")
  expect_false(grepl("abcdefghijklmnop", conditionMessage(err), fixed = TRUE))
  expect_error(gptr_mcp_add("x", command = "a", scope = "project"), class = "gptr_error_workspace")
  expect_false(file.exists(file.path(gptr_user_dir("config"), "mcp.json")))
})

test_that("gptr_mcp(tools = TRUE) uses a fresh tool cache and connects only when needed", {
  local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio")
  gptr_mcp_add("fixture", command = fx$spec$command, args = fx$spec$args, env = fx$spec$env,
               timeout = 30)
  x = gptr_mcp("fixture", tools = TRUE)
  expect_identical(names(x), c("server", "tool", "signature", "exposure", "tokens"))
  expect_identical(x$tool, c("echo", "add", "slow", "fail", "elicit"))
  expect_identical(x$signature[1L], "echo(text: string)  # Echo the text back.")
  n = sum(fx$log()$method == "tools/list")
  mcp_close_all()
  y = gptr_mcp("fixture", tools = TRUE)
  expect_identical(sum(fx$log()$method == "tools/list"), n)
  expect_identical(gptr_mcp()$tools[gptr_mcp()$name == "fixture"], 5L)
  gptr_mcp("fixture", tools = TRUE, refresh = TRUE)
  expect_identical(sum(fx$log()$method == "tools/list"), n + 1L)
  expect_identical(gptr_mcp()$status[gptr_mcp()$name == "fixture"], "connected")
  gptr_mcp_remove("fixture")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "mcp-config")'`
Expected: `[ FAIL 16 | WARN 0 | SKIP 0 | PASS 0 ]`; the first error is `could not find function "mcp_toml_read"`.

- [ ] **Step 3: Write the implementation**

Create `R/mcp-config.R`:

```r
# MCP configuration (contract 6.3, 11.7; architecture 6.14): gptr's own mcp.json (user; project
# when trusted) and the read-only discovery of the servers configured for Claude Code, Claude
# Desktop, Codex (a TOML subset), Cursor, VS Code and Pi, found under user_home() and
# app_config_dir() (IC-63). Adapted from dev/research/16-mcp-skills-plugins.md 5.11
# (mcp_config.R, verified after the fixture relocation fix) and 5.12 (toml_read.R, checked
# against RcppTOML: 36 of 39 values agree and the 3 differences are RcppTOML's). Foreign servers
# are imported on request (D-14): listed by gptr_mcp(), reachable by name, never advertised in
# the prompt catalog. gptr never writes another harness's file.

#' A TOML 1.0 reader for agent config files (base R); arrays of scalars become atomic vectors,
#' arrays of tables lists, dates stay text (report 16 section 5.12)
#' @noRd
mcp_toml_read = function(file = NULL, text = NULL) {
  if (is.null(text)) text = readLines(file, warn = FALSE, encoding = "UTF-8")
  text = as_utf8(paste(text, collapse = "\n"))
  bom = intToUtf8(65279L)
  if (startsWith(text, bom)) text = substring(text, 2L)
  ch = strsplit(gsub("\r\n", "\n", text, fixed = TRUE), "")[[1L]]
  n = length(ch)
  i = 1L
  root = structure(list(), names = character())
  cur_path = character()

  err = function(msg) {
    line = sum(ch[seq_len(min(i, n))] == "\n") + 1L
    gptr_abort(paste0("TOML parse error (line ", line, "): ", msg), "invalid_argument",
               arg = "file", expected = "valid TOML")
  }
  peek = function(k = 0L) if (i + k <= n) ch[i + k] else ""
  skip_ws = function() while (i <= n && ch[i] %in% c(" ", "\t")) i <<- i + 1L
  skip_comment = function() if (peek() == "#") while (i <= n && ch[i] != "\n") i <<- i + 1L
  skip_ws_nl_comments = function() {
    repeat {
      skip_ws()
      skip_comment()
      if (i <= n && ch[i] == "\n") {
        i <<- i + 1L
        next
      }
      break
    }
  }
  expect_eol = function() {
    skip_ws()
    skip_comment()
    if (i <= n && ch[i] != "\n") err(paste0("unexpected '", ch[i], "' after value"))
  }
  hex_char = function(len) {
    h = paste(ch[i:(i + len - 1L)], collapse = "")
    i <<- i + len
    intToUtf8(strtoi(h, 16L))
  }
  read_escape = function() {
    e = peek()
    i <<- i + 1L
    switch(e, b = "\b", t = "\t", n = "\n", f = "\f", r = "\r", `"` = "\"", `\\` = "\\",
           u = hex_char(4L), U = hex_char(8L), err(paste0("bad escape \\", e)))
  }
  read_basic = function() {
    out = character()
    repeat {
      if (i > n) err("unterminated string")
      c1 = ch[i]
      if (c1 == "\"") {
        i <<- i + 1L
        break
      }
      if (c1 == "\n") err("newline in basic string")
      if (c1 == "\\") {
        i <<- i + 1L
        out = c(out, read_escape())
      } else {
        out = c(out, c1)
        i <<- i + 1L
      }
    }
    paste(out, collapse = "")
  }
  read_ml_basic = function() {
    if (peek() == "\n") i <<- i + 1L
    out = character()
    repeat {
      if (i > n) err("unterminated multi-line string")
      if (ch[i] == "\"" && peek(1L) == "\"" && peek(2L) == "\"") {
        i <<- i + 3L
        while (peek() == "\"") {
          out = c(out, "\"")
          i <<- i + 1L
        }
        break
      }
      if (ch[i] == "\\") {
        j = i + 1L
        while (j <= n && ch[j] %in% c(" ", "\t")) j = j + 1L
        if (j <= n && ch[j] == "\n") {
          i <<- j
          while (i <= n && ch[i] %in% c(" ", "\t", "\n")) i <<- i + 1L
          next
        }
        i <<- i + 1L
        out = c(out, read_escape())
        next
      }
      out = c(out, ch[i])
      i <<- i + 1L
    }
    paste(out, collapse = "")
  }
  read_literal = function() {
    s = i
    while (i <= n && ch[i] != "'") {
      if (ch[i] == "\n") err("newline in literal string")
      i <<- i + 1L
    }
    if (i > n) err("unterminated literal string")
    v = paste(ch[seq.int(s, length.out = i - s)], collapse = "")
    i <<- i + 1L
    v
  }
  read_ml_literal = function() {
    if (peek() == "\n") i <<- i + 1L
    s = i
    while (i <= n && !(ch[i] == "'" && peek(1L) == "'" && peek(2L) == "'")) i <<- i + 1L
    if (i > n) err("unterminated multi-line literal string")
    e = i
    i <<- i + 3L
    extra = 0L
    while (peek() == "'" && extra < 2L) {
      extra = extra + 1L
      i <<- i + 1L
    }
    paste(c(ch[seq.int(s, length.out = e - s)], rep("'", extra)), collapse = "")
  }
  read_key = function() {
    parts = character()
    repeat {
      skip_ws()
      c1 = peek()
      if (c1 == "\"") {
        i <<- i + 1L
        parts = c(parts, read_basic())
      } else if (c1 == "'") {
        i <<- i + 1L
        parts = c(parts, read_literal())
      } else {
        s = i
        while (i <= n && grepl("^[A-Za-z0-9_-]$", ch[i])) i <<- i + 1L
        if (i == s) err("expected a key")
        parts = c(parts, paste(ch[s:(i - 1L)], collapse = ""))
      }
      skip_ws()
      if (peek() == ".") {
        i <<- i + 1L
        next
      }
      break
    }
    parts
  }
  radix = function(s, base) {
    d = match(strsplit(tolower(gsub("_", "", s)), "")[[1L]], c(0:9, letters[1:6])) - 1
    sum(d * base^rev(seq_along(d) - 1))
  }
  read_value = function() {
    skip_ws()
    c1 = peek()
    if (c1 == "\"") {
      if (peek(1L) == "\"" && peek(2L) == "\"") {
        i <<- i + 3L
        return(read_ml_basic())
      }
      i <<- i + 1L
      return(read_basic())
    }
    if (c1 == "'") {
      if (peek(1L) == "'" && peek(2L) == "'") {
        i <<- i + 3L
        return(read_ml_literal())
      }
      i <<- i + 1L
      return(read_literal())
    }
    if (c1 == "[") {
      i <<- i + 1L
      return(read_array())
    }
    if (c1 == "{") {
      i <<- i + 1L
      return(read_inline_table())
    }
    s = i
    while (i <= n && !(ch[i] %in% c(",", "]", "}", "\n", "#")) &&
           !(ch[i] %in% c(" ", "\t") &&
             !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", paste(ch[s:(i - 1L)], collapse = "")))) {
      i <<- i + 1L
    }
    tok = trimws(paste(ch[seq.int(s, length.out = i - s)], collapse = ""))
    if (tok == "true") return(TRUE)
    if (tok == "false") return(FALSE)
    if (grepl("^[+-]?(inf|nan)$", tok)) {
      return(if (grepl("nan", tok)) NaN else if (startsWith(tok, "-")) -Inf else Inf)
    }
    if (grepl("^0x[0-9A-Fa-f_]+$", tok)) return(radix(substring(tok, 3L), 16))
    if (grepl("^0o[0-7_]+$", tok)) return(radix(substring(tok, 3L), 8))
    if (grepl("^0b[01_]+$", tok)) return(radix(substring(tok, 3L), 2))
    if (grepl("^[+-]?[0-9][0-9_]*$", tok)) {
      v = as.numeric(gsub("_", "", tok))
      return(if (abs(v) <= .Machine$integer.max) as.integer(v) else v)
    }
    if (grepl("^[+-]?[0-9_]+(\\.[0-9_]+)?([eE][+-]?[0-9_]+)?$", tok)) {
      return(as.numeric(gsub("_", "", tok)))
    }
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}|^[0-9]{2}:[0-9]{2}", tok)) return(tok)
    err(paste0("invalid value '", tok, "'"))
  }
  simplify = function(x) {
    if (length(x) && all(vapply(x, function(e) is.atomic(e) && length(e) == 1L, TRUE))) {
      cls = unique(vapply(x, function(e) class(e)[1L], ""))
      if (length(cls) == 1L || all(cls %in% c("integer", "numeric"))) return(unlist(x))
    }
    x
  }
  read_array = function() {
    out = list()
    repeat {
      skip_ws_nl_comments()
      if (peek() == "]") {
        i <<- i + 1L
        break
      }
      out[[length(out) + 1L]] = read_value()
      skip_ws_nl_comments()
      if (peek() == ",") {
        i <<- i + 1L
        next
      }
      if (peek() == "]") {
        i <<- i + 1L
        break
      }
      err("expected , or ] in array")
    }
    simplify(out)
  }
  read_inline_table = function() {
    tbl = structure(list(), names = character())
    skip_ws()
    if (peek() == "}") {
      i <<- i + 1L
      return(tbl)
    }
    repeat {
      key = read_key()
      skip_ws()
      if (peek() != "=") err("expected = in inline table")
      i <<- i + 1L
      tbl = set_in(tbl, key, read_value())
      skip_ws()
      if (peek() == ",") {
        i <<- i + 1L
        next
      }
      if (peek() == "}") {
        i <<- i + 1L
        break
      }
      err("expected , or } in inline table")
    }
    tbl
  }
  set_in = function(tbl, path, value) {
    if (length(path) == 1L) {
      tbl[[path]] = value
      return(tbl)
    }
    sub = tbl[[path[1L]]]
    if (is.null(sub)) sub = structure(list(), names = character())
    tbl[[path[1L]]] = set_in(sub, path[-1L], value)
    tbl
  }
  assign_rec = function(tbl, path, key, value) {
    if (!length(path)) return(set_in(tbl, key, value))
    p = path[1L]
    sub = tbl[[p]]
    if (is.null(sub)) sub = structure(list(), names = character())
    if (is.list(sub) && is.null(names(sub)) && length(sub)) {
      k = length(sub)
      sub[[k]] = assign_rec(sub[[k]], path[-1L], key, value)
    } else {
      sub = assign_rec(sub, path[-1L], key, value)
    }
    tbl[[p]] = sub
    tbl
  }
  ensure_table = function(tbl, path, aot_append = FALSE) {
    p = path[1L]
    sub = tbl[[p]]
    if (length(path) == 1L) {
      if (aot_append) {
        if (is.null(sub)) sub = list()
        sub[[length(sub) + 1L]] = structure(list(), names = character())
      } else if (is.null(sub)) {
        sub = structure(list(), names = character())
      }
      tbl[[p]] = sub
      return(tbl)
    }
    if (is.null(sub)) sub = structure(list(), names = character())
    if (is.list(sub) && is.null(names(sub)) && length(sub)) {
      k = length(sub)
      sub[[k]] = ensure_table(sub[[k]], path[-1L], aot_append)
    } else {
      sub = ensure_table(sub, path[-1L], aot_append)
    }
    tbl[[p]] = sub
    tbl
  }

  repeat {
    skip_ws_nl_comments()
    if (i > n) break
    if (peek() == "[") {
      aot = peek(1L) == "["
      i = i + if (aot) 2L else 1L
      path = read_key()
      skip_ws()
      if (aot) {
        if (peek() != "]" || peek(1L) != "]") err("expected ]]")
        i = i + 2L
      } else {
        if (peek() != "]") err("expected ]")
        i = i + 1L
      }
      root = ensure_table(root, path, aot_append = aot)
      cur_path = path
      expect_eol()
      next
    }
    key = read_key()
    skip_ws()
    if (peek() != "=") err("expected = after key")
    i = i + 1L
    val = read_value()
    root = assign_rec(root, cur_path, key, val)
    expect_eol()
  }
  root
}

# ---- reading the configurations --------------------------------------------------------------

#' Harness prefixes of foreign servers' `source` (gptr's own are "gptr:user", "gptr:project")
#' @noRd
mcp_harnesses = c("claude-code", "claude-desktop", "codex", "cursor", "vscode", "pi")

#' The config files gptr reads, in precedence order (earlier rows win on name collisions)
#' @noRd
mcp_config_sources = function(project = project_root()) {
  home = user_home()
  codex_home = Sys.getenv("CODEX_HOME")
  if (!nzchar(codex_home)) codex_home = file.path(home, ".codex")
  src = function(harness, scope, path, format) {
    list(harness = harness, scope = scope, path = path, format = format)
  }
  list(
    src("gptr", "project", file.path(project, ".gptr", "mcp.json"), "mcpServers"),
    src("gptr", "user", file.path(gptr_user_dir("config"), "mcp.json"), "mcpServers"),
    src("claude-code", "local", file.path(home, ".claude.json"), "claude.local"),
    src("claude-code", "project", file.path(project, ".mcp.json"), "mcpServers"),
    src("claude-code", "user", file.path(home, ".claude.json"), "mcpServers"),
    src("claude-desktop", "user", file.path(app_config_dir("Claude"), "claude_desktop_config.json"),
        "mcpServers"),
    src("codex", "project", file.path(project, ".codex", "config.toml"), "codex"),
    src("codex", "user", file.path(codex_home, "config.toml"), "codex"),
    src("cursor", "project", file.path(project, ".cursor", "mcp.json"), "mcpServers"),
    src("cursor", "user", file.path(home, ".cursor", "mcp.json"), "mcpServers"),
    src("vscode", "project", file.path(project, ".vscode", "mcp.json"), "vscode"),
    src("vscode", "user", file.path(app_config_dir("Code"), "User", "mcp.json"), "vscode"),
    src("pi", "project", file.path(project, ".pi", "mcp.json"), "mcpServers"),
    src("pi", "user", file.path(home, ".pi", "agent", "mcp.json"), "mcpServers"))
}

#' A character vector from a JSON value (NULL stays NULL)
#' @noRd
mcp_chr = function(x) if (is.null(x)) NULL else as_utf8(as.character(unlist(x)))

#' A named character vector from a JSON object (NULL or empty stays NULL)
#' @noRd
mcp_named_chr = function(x) {
  if (is.null(x) || !length(x) || is.null(names(x))) return(NULL)
  out = vapply(x, function(v) as_utf8(as.character(unlist(v))[1L]), "")
  names(out) = names(x)
  out
}

#' One entry of any harness as the fields of gptr's `mcp_server` spec (contract 11.7) plus
#' `path`, `needs_input` (VS Code ${input:...}) and `startable` (FALSE for project entries of
#' an untrusted project)
#' @noRd
mcp_entry_norm = function(name, e, harness, scope, path) {
  type = as.character(e$type %||% "")
  url = e$url %||% e$httpUrl
  transport = if (identical(type, "sse")) {
    "sse"
  } else if (type %in% c("http", "streamable-http", "streamableHttp")) {
    "http"
  } else if (!is.null(e$command)) {
    "stdio"
  } else if (!is.null(url)) {
    "http"
  } else {
    NA_character_
  }
  env = mcp_named_chr(e$env)
  headers = mcp_named_chr(e$headers)
  tool_exposure = e$toolExposure
  timeout = e$timeout
  if (identical(harness, "codex")) {
    for (v in mcp_chr(e$env_vars)) env[[v]] = paste0("${", v, "}")
    headers = c(headers, mcp_named_chr(e$http_headers))
    for (h in names(e$env_http_headers)) {
      headers[[h]] = paste0("${", as.character(e$env_http_headers[[h]]), "}")
    }
    if (!is.null(e$bearer_token_env_var)) {
      headers[["Authorization"]] = paste0("Bearer ${", e$bearer_token_env_var, "}")
    }
    timeout = e$tool_timeout_sec
    te = list()
    for (t in mcp_chr(e$disabled_tools)) te[[t]] = "hidden"
    if (length(e$enabled_tools)) {
      for (t in mcp_chr(e$enabled_tools)) te[[t]] = "r"
      te[["*"]] = "hidden"
    }
    if (length(te)) tool_exposure = te
  }
  if (!is.null(timeout)) {
    # seconds in gptr's mcp.json (contract 11.7) and in Codex's tool_timeout_sec; milliseconds in
    # Claude Code's files; the other harnesses' values of 1000 or more are taken as milliseconds
    timeout = as.numeric(timeout)[1L]
    ms = identical(harness, "claude-code") ||
      (!harness %in% c("gptr", "codex") && isTRUE(timeout >= 1000))
    if (ms) timeout = timeout / 1000
  }
  exposure = mcp_chr(e$exposure)
  if (!is.null(exposure) && !exposure[1L] %in% c("r", "direct", "deferred", "hidden")) {
    exposure = NULL
  }
  protocol = as.character(e$protocol %||% "auto")
  if (!protocol %in% c("auto", "modern", "legacy")) protocol = "auto"
  raw = json_encode(list(env = e$env, headers = e$headers, args = e$args))
  out = list(name = name, transport = transport, command = mcp_chr(e$command)[1L],
             args = mcp_chr(e$args) %||% character(), env = env, headers = headers,
             cwd = mcp_chr(e$cwd)[1L], url = mcp_chr(url)[1L], timeout = timeout,
             protocol = protocol, exposure = exposure[1L], toolExposure = tool_exposure,
             enabled = !isFALSE(e$enabled) && !isTRUE(e$disabled),
             trusted = identical(harness, "gptr") && identical(scope, "user") && isTRUE(e$trusted),
             oauth = if (is.list(e$oauth) && length(e$oauth)) e$oauth,
             source = paste0(harness, ":", scope),
             path = path, also_in = character(), needs_input = grepl("${input:", raw, fixed = TRUE),
             startable = TRUE)
  out[!vapply(out, is.null, NA)]
}

#' Parse one config file into entries; a parse failure is a registry diagnostic, never an error
#' @noRd
mcp_read_source = function(src, project) {
  if (!file.exists(src$path)) return(list())
  x = tryCatch({
    if (identical(src$format, "codex")) {
      mcp_toml_read(src$path)
    } else {
      json_decode(read_utf8(src$path)$text)
    }
  }, error = function(e) {
    registry_diagnostic("builtin:mcp", "mcp_config", "parse",
                        paste0("cannot parse ", src$path, ": ", conditionMessage(e)))
    NULL
  })
  if (!is.list(x)) return(list())
  entries = switch(src$format,
    mcpServers = x$mcpServers,
    claude.local = {
      keys = names(x$projects %||% list())
      hit = keys[vapply(keys, function(k) identical(path_key(k), path_key(project)), NA)]
      if (length(hit)) x$projects[[hit[1L]]]$mcpServers else NULL
    },
    vscode = x$servers,
    codex = x$mcp_servers,
    NULL)
  defaults = if (identical(src$harness, "gptr") && is.list(x$defaults)) x$defaults else list()
  out = list()
  for (nm in names(entries)) {
    e = entries[[nm]]
    if (!is.list(e)) next
    for (k in intersect(names(defaults), c("exposure", "timeout", "protocol"))) {
      if (is.null(e[[k]])) e[[k]] = defaults[[k]]
    }
    out[[length(out) + 1L]] = mcp_entry_norm(nm, e, src$harness, src$scope, src$path)
  }
  out
}

#' Is the project trusted? (the trust.get service of P08; untrusted when absent, IC-33)
#' @noRd
mcp_trusted = function(project = project_root()) {
  ext_service_has("trust.get") && isTRUE(ext_service_get("trust.get")(project))
}

#' A field of the `mcp` settings key (contract 11.2), else `default`
#' @noRd
mcp_setting = function(key, default = NULL) {
  x = setting_get("mcp")
  v = if (is.list(x)) x[[key]]
  v %||% default
}

#' Every configured server (contract 7.18): gptr's project file (trusted) over gptr's user file
#' over the harnesses of setting `mcp.import`. A server with the same transport, command, args
#' and url in several harnesses is listed once with `also_in`; a foreign name collision is
#' renamed `<harness>_<name>`; project entries of an untrusted project get `startable = FALSE`.
#' @noRd
mcp_config_all = function(project = project_root()) {
  import = mcp_chr(mcp_setting("import", mcp_harnesses))
  trusted = mcp_trusted(project)
  all = list()
  for (src in mcp_config_sources(project)) {
    if (!identical(src$harness, "gptr") && !src$harness %in% import) next
    for (s in mcp_read_source(src, project)) {
      if (identical(src$scope, "project")) s$startable = trusted
      all[[length(all) + 1L]] = s
    }
  }
  fp = vapply(all, function(s) {
    paste(s$transport, s$command %||% "", paste(s$args, collapse = " "), s$url %||% "", sep = "|")
  }, "")
  keep = list()
  seen_fp = character()
  seen_name = character()
  for (j in seq_along(all)) {
    s = all[[j]]
    own = startsWith(s$source, "gptr:")
    if (own && s$name %in% seen_name) next
    if (!own && fp[j] %in% seen_fp) {
      w = match(fp[j], seen_fp)
      keep[[w]]$also_in = c(keep[[w]]$also_in, s$source)
      next
    }
    if (s$name %in% seen_name) s$name = paste0(sub(":.*$", "", s$source), "_", s$name)
    keep[[length(keep) + 1L]] = s
    seen_fp = c(seen_fp, fp[j])
    seen_name = c(seen_name, s$name)
  }
  names(keep) = vapply(keep, function(s) s$name, "")
  keep
}

# ---- the registry view of the servers --------------------------------------------------------

#' Register the configured servers as `mcp_server` records: gptr:user at rank 3 (source
#' "user"), a trusted gptr:project at rank 1 (source "project"), every other entry at rank 6
#' (source "builtin:mcp"). The files are re-read only when their stamps, the trust state or the
#' import setting changed. Plugin and session records (P17) are never touched. Returns the
#' `mcp_server` specs visible to `session`, by name.
#' @noRd
mcp_sync = function(force = FALSE, session = NULL) {
  st = mcp_state()
  project = project_root()
  srcs = mcp_config_sources(project)
  info = file.info(vapply(srcs, function(s) s$path, ""))
  stamp = paste(c(project, info$size, as.numeric(info$mtime), mcp_trusted(project),
                  mcp_chr(mcp_setting("import", character()))), collapse = "|")
  if (!isTRUE(force) && identical(st$stamp, stamp)) return(mcp_servers_all(session))
  for (nm in ls(st$servers)) {
    registry_remove(get(nm, envir = st$servers))
    rm(list = nm, envir = st$servers)
  }
  for (s in mcp_config_all(project)) {
    own_project = identical(s$source, "gptr:project") && isTRUE(s$startable)
    own_user = identical(s$source, "gptr:user")
    spec = tryCatch(do.call(gptr_spec, c(list("mcp_server", s$name), s[setdiff(names(s), "name")])),
                    gptr_error = function(e) {
                      registry_diagnostic("builtin:mcp", "mcp_config", "invalid_spec",
                                          paste0("server ", s$name, " (", s$source, "): ",
                                                 conditionMessage(e)))
                      NULL
                    })
    if (is.null(spec)) next
    source = if (own_project) "project" else if (own_user) "user" else "builtin:mcp"
    rank = if (own_project) 1L else if (own_user) 3L else 6L
    id = registry_add(spec, source = source, rank = rank)
    assign(s$name, id, envir = st$servers)
  }
  st$stamp = stamp
  mcp_servers_all(session)
}

#' Every `mcp_server` spec visible to `session` (configured, registered with gptr_register(),
#' plugins), by name
#' @noRd
mcp_servers_all = function(session = NULL) {
  nms = registry_names("mcp_server", session = session)
  specs = lapply(nms, function(n) registry_get("mcp_server", n, session = session))
  names(specs) = nms
  specs[!vapply(specs, is.null, NA)]
}

#' Can a server be started and used?
#' @noRd
mcp_usable = function(s) {
  !isFALSE(s$enabled) && !isFALSE(s$startable) && !isTRUE(s$needs_input) &&
    isTRUE(mcp_transport(s) %in% c("stdio", "http"))
}

#' Does a server come from another harness's configuration (imported on request, D-14)?
#' @noRd
mcp_foreign = function(s) {
  src = s$source %||% ""
  any(startsWith(src, paste0(mcp_harnesses, ":")))
}

#' The canonical name of a server written as typed or as its syntactic R name
#' @noRd
mcp_server_resolve = function(name, session = NULL) {
  specs = mcp_sync(session = session)
  if (name %in% names(specs)) return(name)
  hit = names(specs)[mcp_r_name(names(specs)) == name]
  if (length(hit) == 1L) return(hit)
  gptr_abort(paste0("No MCP server named ", name, " is configured."), "unknown_member",
             name = name, available = mcp_r_name(names(Filter(mcp_usable, specs))))
}

#' A usable server spec, or the classed reason why it cannot be used
#' @noRd
mcp_server_get = function(name, session = NULL) {
  name = mcp_server_resolve(name, session)
  s = registry_get("mcp_server", name, session = session)
  if (isFALSE(s$enabled)) {
    gptr_abort(paste0("MCP server ", name, " is disabled in its configuration."),
               c("mcp_protocol", "mcp"), server = name, code = NA_integer_)
  }
  if (isFALSE(s$startable)) {
    gptr_abort(paste0("MCP server ", name, " comes from a project you have not trusted; run ",
                      "gptr_trust() to use it."), "untrusted", what = "project MCP server",
               path = s$path %||% NA_character_, origin = NA_character_)
  }
  if (isTRUE(s$needs_input)) {
    gptr_abort(paste0("MCP server ", name, " uses VS Code ${input:...} values; add it to gptr ",
                      "with gptr_mcp_add()."), c("mcp_protocol", "mcp"), server = name,
               code = NA_integer_)
  }
  s$name = name
  s
}

#' The live connection of a server, connecting lazily (and again after an exit)
#' @noRd
mcp_conn_get = function(name, session = NULL) {
  conns = mcp_state()$conns
  conn = get0(name, envir = conns, inherits = FALSE)
  if (!is.null(conn) && isTRUE(conn$alive)) return(conn)
  conn = mcp_connect(mcp_server_get(name, session))
  assign(name, conn, envir = conns)
  conn
}

#' Tools known without connecting: the live connection's list, else the disk cache, else NULL
#' @noRd
mcp_tools_known = function(s) {
  conn = get0(s$name, envir = mcp_state()$conns, inherits = FALSE)
  if (!is.null(conn) && !is.null(conn$tools)) return(conn$tools)
  mcp_tools_cache_get(s)$tools
}

#' Exposure of one tool: the first matching toolExposure glob, else the server's exposure, else
#' the setting `mcp.exposure` ("r")
#' @noRd
mcp_tool_exposure = function(s, tool) {
  te = s$toolExposure
  for (g in names(te)) {
    if (grepl(glob_to_regex(g), tool, perl = TRUE)) return(as.character(te[[g]]))
  }
  as.character(s$exposure %||% mcp_setting("exposure", "r"))
}

#' The catalog line of a server whose tools are not known yet (nothing cached, never connected):
#' it says how to list them, since printing the server node connects (Task 7)
#' @noRd
mcp_unlisted_line = function(name) {
  paste0(mcp_r_name(name), ": tools not listed yet; print(gptr$mcp$", mcp_r_name(name),
         ") lists them")
}

#' Catalog lines of one server: "<server>: <n> tools, <k> shown" and one signature per shown
#' `r` tool (`keep` = tools shown, NULL for all; `bare` = shown without their description)
#' @noRd
mcp_server_lines = function(s, tools = mcp_tools_known(s), keep = NULL, bare = character(),
                            exposures = "r") {
  if (is.null(tools)) return(mcp_unlisted_line(s$name))
  mine = Filter(function(t) mcp_tool_exposure(s, t$name) %in% exposures, tools)
  nm = vapply(mine, function(t) t$name, "")
  show = if (is.null(keep)) nm else intersect(nm, keep)
  lines = paste0(mcp_r_name(s$name), ": ", length(mine), " tools, ", length(show), " shown")
  for (t in mine[nm %in% show]) {
    d = if (t$name %in% bare) NULL else mcp_first_sentence(t$description)
    lines = c(lines, paste0("  ", schema_signature(mcp_r_name(t$name), t$input_schema, d %||% "")))
  }
  lines
}

# ---- writing gptr's mcp.json ------------------------------------------------------------------

#' Path of gptr's own mcp.json at a scope; the project scope needs a workspace
#' @noRd
mcp_config_path = function(scope) {
  if (identical(scope, "user")) {
    return(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"))
  }
  ws = workspace_dir()
  if (is.null(ws)) {
    gptr_abort("The project scope needs a .gptr/ workspace; run gptr_init() first.", "workspace",
               path = project_root())
  }
  file.path(ws, "mcp.json")
}

#' Read-modify-write gptr's mcp.json under the short mkdir lock (IC-71), atomically; unknown
#' keys are preserved and mcpServers stays a JSON object
#' @noRd
mcp_file_update = function(path, fun) {
  oauth_lock_with(path, function() {
    x = if (file.exists(path)) tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
    if (!is.list(x)) x = list()
    x = fun(x)
    if (!length(x$mcpServers)) x$mcpServers = json_obj()
    write_atomic(path, json_encode(x, pretty = TRUE))
    invisible(x)
  })
}

#' Validate env/headers: a named character vector whose secret-looking values (a registered
#' value or a redaction pattern) must be ${VAR} placeholders (contract 6.3)
#' @noRd
mcp_check_kv = function(x, arg) {
  if (is.null(x)) return(NULL)
  check_strings(x, arg)
  if (is.null(names(x)) || any(!nzchar(names(x)))) {
    gptr_abort(paste0("`", arg, "` must be a named character vector."), "invalid_argument",
               arg = arg, expected = "a named character vector")
  }
  for (k in names(x)) {
    v = x[[k]]
    if (!grepl("${", v, fixed = TRUE) && !identical(redact(v), v)) {
      gptr_abort(paste0("The value of ", arg, "[[\"", k, "\"]] looks like a secret; write it as ",
                        "a ${VAR} placeholder and set VAR in the environment."),
                 "invalid_argument", arg = paste0(arg, "$", k),
                 expected = "a ${VAR} placeholder for secret values")
    }
  }
  x
}

#' Add or remove an MCP server in gptr's configuration
#'
#' `gptr_mcp_add()` writes a server into gptr's own `mcp.json`: the user file under
#' `tools::R_user_dir("gptr", "config")`, or `.gptr/mcp.json` of the project (used only when
#' you trust the project). It never edits another harness's files. Give exactly one of
#' `command` (a server started as a local process speaking stdio) and `url` (a Streamable HTTP
#' server). Secret values in `env` and `headers` must be `${VAR}` placeholders: they are
#' expanded from the environment when gptr connects and never stored. Nothing connects until a
#' tool is used.
#'
#' @param name Server name: 1-64 letters, digits, `_` or `-`. Its tools are reached as
#'   `gptr$mcp$<name>$<tool>()` inside the `r` tool.
#' @param command,args The program and its arguments for a stdio server.
#' @param url The endpoint of a Streamable HTTP server.
#' @param env,headers Named character vectors: environment variables of a stdio server, HTTP
#'   headers of an HTTP server. Write secrets as `${VAR}` placeholders.
#' @param exposure How the model reaches the tools: `"r"` (R functions listed in the prompt),
#'   `"direct"` (declared as tools), `"deferred"` (found through `gptr$search()`) or
#'   `"hidden"`.
#' @param timeout Seconds per request; progress notifications from the server extend it.
#' @param scope `"user"` (default) or `"project"`.
#' @return `gptr_mcp_add()` returns the server spec invisibly; `gptr_mcp_remove()` returns
#'   `TRUE` invisibly when a server was removed, else `FALSE`.
#' @examplesIf interactive()
#' gptr_mcp_add("fs", command = "npx",
#'              args = c("-y", "@modelcontextprotocol/server-filesystem", "."))
#' gptr_mcp_remove("fs")
#' @export
gptr_mcp_add = function(name, command = NULL, args = character(), url = NULL, env = NULL,
                        headers = NULL, exposure = "r", timeout = 60,
                        scope = c("user", "project")) {
  name = check_string(name, "name")
  if (!grepl("^[A-Za-z0-9_-]{1,64}$", name)) {
    gptr_abort("`name` must be 1-64 letters, digits, '_' or '-'.", "invalid_argument", arg = "name",
               expected = "a name matching ^[A-Za-z0-9_-]{1,64}$")
  }
  check_string(command, "command", null = TRUE)
  check_strings(args, "args")
  check_string(url, "url", null = TRUE)
  if (is.null(command) == is.null(url)) {
    gptr_abort(paste("Give exactly one of `command` (a stdio server) and `url` (a Streamable",
                     "HTTP server)."),
               "invalid_argument", arg = "command", expected = "exactly one of command and url")
  }
  env = mcp_check_kv(env, "env")
  headers = mcp_check_kv(headers, "headers")
  exposure = check_choice(exposure, c("r", "direct", "deferred", "hidden"), "exposure")
  timeout = check_number(timeout, "timeout", min = 1)
  scope = check_choice(scope, c("user", "project"), "scope")
  ext_control_guard("gptr_mcp_add")
  entry = if (!is.null(command)) list(command = command, args = I(args)) else list(url = url)
  if (!is.null(env)) entry$env = as.list(env)
  if (!is.null(headers)) entry$headers = as.list(headers)
  entry$exposure = exposure
  entry$timeout = timeout
  mcp_file_update(mcp_config_path(scope), function(x) {
    servers = x$mcpServers %||% list()
    servers[[name]] = entry
    x$mcpServers = servers
    x
  })
  mcp_forget_conn(name)
  mcp_sync(force = TRUE)
  ev_dispatch("mcp_servers_change", list(added = name, removed = character()))
  invisible(registry_get("mcp_server", name))
}

#' @rdname gptr_mcp_add
#' @export
gptr_mcp_remove = function(name, scope = c("user", "project")) {
  name = check_string(name, "name")
  scope = check_choice(scope, c("user", "project"), "scope")
  ext_control_guard("gptr_mcp_remove")
  path = mcp_config_path(scope)
  st = new.env(parent = emptyenv())
  st$removed = FALSE
  if (file.exists(path)) {
    mcp_file_update(path, function(x) {
      if (!is.null(x$mcpServers[[name]])) {
        x$mcpServers[[name]] = NULL
        st$removed = TRUE
      }
      x
    })
  }
  mcp_forget_conn(name)
  mcp_sync(force = TRUE)
  if (st$removed) ev_dispatch("mcp_servers_change", list(added = character(), removed = name))
  invisible(st$removed)
}

#' Close and forget the connection of a server
#' @noRd
mcp_forget_conn = function(name) {
  conns = mcp_state()$conns
  if (exists(name, envir = conns, inherits = FALSE)) {
    mcp_close(get(name, envir = conns))
    rm(list = name, envir = conns)
  }
  invisible(NULL)
}

# ---- gptr_mcp() ------------------------------------------------------------------------------

#' List MCP servers and their tools
#'
#' Without `tools`, lists gptr's servers (the user `mcp.json` and, in a trusted project,
#' `.gptr/mcp.json`) together with the servers configured for Claude Code, Claude Desktop,
#' Codex, Cursor, VS Code and Pi, which gptr reads but never edits. Nothing is started: the era
#' and the tool counts come from gptr's caches. With `tools = TRUE`, lists the tools of
#' `server` (or of every usable server) with their R signatures and catalog cost, from the
#' cache when it is fresh and otherwise by connecting (which starts stdio servers). Servers of
#' an untrusted project are listed but never started.
#'
#' @param server A server name, or `NULL` for all.
#' @param tools `TRUE` to list tools instead of servers.
#' @param refresh `TRUE` to reconnect and refresh the caches.
#' @return A `gptr_mcp_servers` data frame (`name`, `source`, `transport`, `era`, `status`,
#'   `tools`, `exposure`, `tokens`, `trusted`) or, with `tools = TRUE`, a data frame with
#'   `server`, `tool`, `signature`, `exposure` and `tokens`.
#' @examples
#' gptr_mcp()
#' @export
gptr_mcp = function(server = NULL, tools = FALSE, refresh = FALSE) {
  check_string(server, "server", null = TRUE)
  tools = check_flag(tools, "tools")
  refresh = check_flag(refresh, "refresh")
  specs = mcp_sync(force = TRUE)
  if (!is.null(server)) server = mcp_server_resolve(server)
  targets = if (is.null(server)) specs else specs[server]
  if (refresh) {
    for (s in Filter(mcp_usable, targets)) {
      mcp_era_forget(s)
      mcp_forget_conn(s$name)
      tryCatch(mcp_tools(mcp_conn_get(s$name), refresh = TRUE), gptr_error = function(e) {
        if (!is.null(server)) stop(e)
        registry_diagnostic("builtin:mcp", "mcp_refresh", class(e)[1L], conditionMessage(e))
      })
    }
  }
  if (!tools) return(mcp_server_listing(specs))
  rows = list()
  for (s in targets) {
    if (!is.null(server)) mcp_server_get(s$name)
    if (!mcp_usable(s)) next
    cached = mcp_tools_cache_get(s)
    tl = if (!is.null(cached) && mcp_tools_cache_fresh(cached)) {
      cached$tools
    } else {
      mcp_tools(mcp_conn_get(s$name))
    }
    for (t in tl) {
      sig = schema_signature(mcp_r_name(t$name), t$input_schema, mcp_first_sentence(t$description))
      rows[[length(rows) + 1L]] = data.frame(server = s$name, tool = t$name, signature = sig,
                                             exposure = mcp_tool_exposure(s, t$name),
                                             tokens = est_tokens(sig, "code"),
                                             stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) {
    return(data.frame(server = character(), tool = character(), signature = character(),
                      exposure = character(), tokens = numeric(), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' The gptr_mcp_servers listing (contract 5.12); no connection is made
#' @noRd
mcp_server_listing = function(specs) {
  conns = mcp_state()$conns
  rows = lapply(specs, function(s) {
    conn = get0(s$name, envir = conns, inherits = FALSE)
    tl = mcp_tools_known(s)
    status = if (isFALSE(s$enabled)) {
      "disabled"
    } else if (isFALSE(s$startable)) {
      "untrusted"
    } else if (identical(mcp_transport(s), "sse")) {
      "unsupported (sse)"
    } else if (isTRUE(s$needs_input)) {
      "needs input"
    } else if (!is.null(conn) && isTRUE(conn$alive)) {
      "connected"
    } else {
      "configured"
    }
    lines = mcp_server_lines(s, tl)
    data.frame(name = s$name, source = s$source %||% "registry", transport = mcp_transport(s),
               era = mcp_era_get(s)$era %||% NA_character_, status = status,
               tools = if (is.null(tl)) NA_integer_ else length(tl),
               exposure = s$exposure %||% mcp_setting("exposure", "r"),
               tokens = est_tokens(paste(lines, collapse = "\n"), "code"),
               trusted = !isFALSE(s$startable), stringsAsFactors = FALSE)
  })
  df = if (length(rows)) {
    do.call(rbind, unname(rows))
  } else {
    data.frame(name = character(), source = character(), transport = character(),
               era = character(), status = character(), tools = integer(), exposure = character(),
               tokens = numeric(), trusted = logical(), stringsAsFactors = FALSE)
  }
  rownames(df) = NULL
  new_listing(df, "gptr_mcp_servers",
              footer = paste("gptr_mcp(tools = TRUE) lists tools; gptr_mcp_add() adds a server to",
                             "gptr's mcp.json."))
}
```

Then regenerate the documentation: `Rscript --vanilla -e 'devtools::document()'`. Expected: `NAMESPACE` gains `export(gptr_mcp)`, `export(gptr_mcp_add)` and `export(gptr_mcp_remove)`; `man/gptr_mcp.Rd` (its example `gptr_mcp()` runs offline: it reads the configuration files and connects to nothing) and `man/gptr_mcp_add.Rd` (aliases `gptr_mcp_add`, `gptr_mcp_remove`; the example is guarded by `@examplesIf interactive()` because it writes the user `mcp.json`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-config")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 89 ]`

- [ ] **Step 5: Commit**

```bash
git add R/mcp-config.R tests/testthat/test-mcp-config.R tests/testthat/helper-mcp-server.R NAMESPACE man/gptr_mcp.Rd man/gptr_mcp_add.Rd
git commit -m "feat(mcp): add MCP configuration, gptr_mcp(), gptr_mcp_add() and gptr_mcp_remove()"
```


---

### Task 7: The `gptr$mcp` namespace, the `<mcp>` catalog and `builtin:mcp`

**Files:**
- Create: `R/mcp-namespace.R`
- Test: `tests/testthat/test-mcp-namespace.R` (create)

**Interfaces:**
- Consumes: Tasks 2-6; P01 `on_load()`, `on_unload()`, `ext_service_set()`, `ext_service_has()`, `est_tokens()`, `schema_signature()`, `truncate_output()`, `json_obj()`; P02 `gptr_tool()`, `gptr_prompt_section()`, `gptr_tool_result()`, `registry_add()`, `registry_remove()`, `registry_get()`, `registry_diagnostic()`, `ext_declare_builtin()`, the API object's `register()` and `on()`; P06 `run_current()`, `session_live()`, `session_data()`, `dispatch_nested()`, the `session_start` event; P10 `ns_register_provider()` (in `on_load()` only) and the `gptr_ns` methods; Task 2 `oauth_hooks_set()`; `rlang::new_weakref()`, `rlang::wref_key()`; tests: P08 `gptr()`, P01 `local_fake_provider()`, `fake_tool()`, `fake_requests()`, P11 `local_scripted_ui()`, P10 `gptr$search()`.
- Produces: `builtin_mcp(gptr)` (04 §7.18; declared as `builtin:mcp`): the `mcp` prompt section (T1, order 840, budget 1,500) and a `session_start` hook that registers the `direct` tools of advertised servers before the prompt freezes; the `mcp` namespace provider `mcp_ns_provider(path)` (`gptr$mcp` and `gptr$mcp$<server>` are `gptr_ns` nodes of kinds `"mcp"` and `"mcp_server"` with `members()` and `signatures()`; `gptr$mcp$<server>$<tool>` is a `gptr_member` closure); the service `mcp.catalog` = `mcp_catalog(session = NULL, budget = NULL)` -> chr(1) or `NULL`; the login target of `gptr_login("mcp:<name>")`; internal `mcp_invoke(server, tool, input)` -> a `gptr_tool_result` whose `value` is the R value, `mcp_tool_spec(s, tool, exposure)`, `mcp_spec_ensure(s, tool, exposure, session = NULL)`, `mcp_tool_level(s, tool)`, `mcp_member_closure(spec, server, tool)`, `mcp_catalog_header()`, `mcp_catalog_lines(specs, budget, exposures = "r")`, `mcp_catalog_text(session = NULL, budget = mcp_budget())`, `mcp_budget()`, `mcp_advertised(s)`, `mcp_tools_load(s, session = NULL)` (known tools, else a connection lists them: `names()` and `print()` of a server node), `mcp_session_remember(session)` and `mcp_session_resolve(session)` (a session or the id of one whose `session_start` builtin:mcp saw; Tasks 8 and 9).

Report 16 §4.7 and §5.14 with report 06 §4.5.3: each MCP tool is an R function whose formals come from its JSON Schema (required properties first, optional ones `NULL`; non-syntactic names mapped by `mcp_r_name()`), so 125 tools cost about 2,285 o200k tokens as signatures instead of 28,534 as declarations (G2 (b)). A closure called from model code inside an `r` evaluation goes through `dispatch_nested()` with the tool's wire name `mcp__<server>__<tool>`, so the gate decides with the server-annotation risk (04 §9.4); called at the console it runs directly. The tool spec is registered lazily at first use (rank 6, `builtin:mcp`) with exposure `hidden` (no `gptr$` member of its own) or `direct` (declared in the tool array). The catalog header is 03 §7.3 verbatim; each advertised server gives `<server>: <n> tools, <k> shown` and one signature line per `r` tool (a server whose tools are neither cached nor listed gives `<server>: tools not listed yet; print(gptr$mcp$<server>) lists them`, and `print()`, `names()` or completion of that node connects and lists them, so the model never meets a server it cannot explore); over the budget the least recently used tools lose their descriptions, then their lines, and the most recently used get their descriptions back while they fit, re-estimated on the joined text. `gptr$search()` and `gptr$help("<server>/<tool>")` (P10) read every non-hidden tool of every usable server through `mcp.catalog` and the provider.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-mcp-namespace.R`:

```r
# A temporary home and project with the fixture server registered as gptr's user server
local_fixture_server = function(..., name = "fixture", .env = parent.frame()) {
  local_mcp_home(.env)
  local_project(.env = .env)
  fx = local_mcp_fixture(..., .env = .env)
  local_mcp_server(fx, name, .env = .env)
  fx
}

test_that("gptr$mcp$<server>$<tool>() closures connect lazily and return R values", {
  fx = local_fixture_server("modern", "stdio")
  expect_identical(nrow(fx$log()), 0L)
  node = gptr$mcp
  expect_s3_class(node, "gptr_ns")
  expect_identical(names(node), "fixture")
  echo = gptr$mcp$fixture$echo
  expect_s3_class(echo, "gptr_member")
  expect_identical(names(formals(echo)), "text")
  expect_identical(attr(echo, "signature"),
                   "gptr$mcp$fixture$echo(text: string)  # Echo the text back.")
  expect_identical(echo(text = "x"), list(text = "x"))
  expect_identical(fx$log()$method[1L], "server/discover")
  expect_identical(gptr$mcp$fixture$add(a = 2, b = 40), list(sum = 42L))
  expect_identical(names(formals(gptr$mcp$fixture$slow)), c("steps", "step_ms", "progress"))
  expect_null(formals(gptr$mcp$fixture$slow)$steps)
  expect_setequal(names(gptr$mcp$fixture), c("echo", "add", "slow", "fail", "elicit"))
  err = expect_error(gptr$mcp$fixture$fail(), class = "gptr_error_mcp_tool")
  expect_identical(err$server, "fixture")
  expect_identical(err$tool, "fail")
  expect_error(gptr$mcp$fixture$echo(), "text", class = "gptr_error_invalid_argument")
  expect_error(gptr$mcp$fixture$nope, class = "gptr_error_unknown_member")
  expect_error(gptr$mcp$nobody, class = "gptr_error_unknown_member")
  expect_output(print(gptr$mcp$fixture), "fixture: 5 tools")
})

test_that("an unlisted server tells how to list it; printing it connects and lists the tools", {
  fx = local_fixture_server("modern", "stdio")
  expect_match(mcp_catalog_text(NULL),
               "fixture: tools not listed yet; print(gptr$mcp$fixture) lists them", fixed = TRUE)
  expect_identical(nrow(fx$log()), 0L)
  expect_output(print(gptr$mcp$fixture), "echo(text: string)", fixed = TRUE)
  expect_identical(fx$log()$method[1L], "server/discover")
  expect_setequal(names(gptr$mcp$fixture), c("echo", "add", "slow", "fail", "elicit"))
  expect_match(mcp_catalog_text(NULL), "fixture: 5 tools, 5 shown", fixed = TRUE)
})

test_that("an MCP call inside r passes the gate as a nested call and returns an R value", {
  fx = local_fixture_server("modern", "stdio")
  code = paste("res = gptr$mcp$fixture$echo(text = \"x\")",
               "bad = tryCatch(gptr$mcp$fixture$fail(),",
               "               gptr_error_mcp_tool = function(e) 'caught')", sep = "\n")
  fake = local_fake_provider(list(fake_tool("r", code = code), "done"))
  e = new.env()
  s = gptr("Echo x through MCP", model = fake, envir = e, mode = auto)
  expect_identical(e$res, list(text = "x"))
  expect_identical(e$bad, "caught")
  res = fake_requests(fake)[[2L]]$last_results[[1L]]
  tools = vapply(res$details$nested, function(n) n$tool, "")
  expect_identical(tools, c("mcp__fixture__echo", "mcp__fixture__fail"))
  expect_false(res$details$nested[[1L]]$is_error)
})

test_that("a nested MCP call that needs approval is asked separately and can be denied", {
  fx = local_fixture_server("modern", "stdio")
  ui = local_scripted_ui(list("y", "n"))
  code = "res = tryCatch(gptr$mcp$fixture$echo(text = 'x'), gptr_error = function(e) class(e)[1])"
  fake = local_fake_provider(list(fake_tool("r", code = code), "done"))
  e = new.env()
  gptr("Echo x", model = fake, envir = e, mode = manual)
  expect_identical(e$res, "gptr_error_tool")
  expect_identical(ui$log$method, c("permission", "permission"))
  expect_false("tools/call" %in% fx$log()$method)
})

test_that("the <mcp> catalog fits 1,500 tokens with 125 tools; gptr$search() finds the rest", {
  fx = local_fixture_server("modern", "stdio", n_extra = 120L)
  gptr_mcp("fixture", tools = TRUE)
  txt = mcp_catalog_text(NULL, 1500)
  body = sub("^[^\n]*\n", "", txt)
  expect_lte(est_tokens(mcp_catalog_header(), "prose") + est_tokens(body, "code"), 1500)
  first = strsplit(body, "\n", fixed = TRUE)[[1L]][1L]
  shown = as.integer(sub("^fixture: 125 tools, ([0-9]+) shown$", "\\1", first))
  expect_true(shown < 125L)
  full = mcp_catalog_lines(Filter(mcp_advertised, mcp_sync()), 1e6)
  expect_gt(est_tokens(paste(full, collapse = "\n"), "code"), 1500)
  hits = gptr$search("Generated tool 117")
  expect_identical(hits$name[1L], "fixture/tool_117")
  expect_identical(hits$kind[1L], "mcp")
  fake = local_fake_provider(list("hi"))
  s = gptr("hi", model = fake, envir = new.env(), mode = auto)
  t1 = session_data(s)$frozen$t1
  expect_match(t1, "<mcp>\nMCP tools are R functions called inside r", fixed = TRUE)
  expect_match(t1, "fixture: 125 tools", fixed = TRUE)
})

test_that("the least recently used tools lose their descriptions first", {
  fx = local_fixture_server("modern", "stdio", tools = "echo", n_extra = 20L)
  gptr_mcp("fixture", tools = TRUE)
  expect_identical(gptr$mcp$fixture$tool_020(query = "q"), "20")
  specs = Filter(mcp_advertised, mcp_sync())
  cost = function(lines) {
    est_tokens(mcp_catalog_header(), "prose") + est_tokens(paste(lines, collapse = "\n"), "code")
  }
  full = cost(mcp_catalog_lines(specs, 1e6))
  bare = cost(mcp_server_lines(specs$fixture, bare = sprintf("tool_%03d", 1:20)))
  lines = mcp_catalog_lines(specs, floor((full + bare) / 2))
  expect_lte(cost(lines), floor((full + bare) / 2))
  expect_identical(lines[1L], "fixture: 21 tools, 21 shown")
  expect_true(any(grepl("tool_020(query: string, limit?: integer)  # Generated tool 20",
                        lines, fixed = TRUE)))
  expect_true(any(lines == "  tool_001(query: string, limit?: integer)"))
})

test_that("per-tool exposure: direct tools enter the tool array, hidden ones are unreachable", {
  home = local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio")
  write_json_file(file.path(gptr_user_dir("config", create = TRUE), "mcp.json"), list(
    mcpServers = list(fixture = list(command = fx$spec$command, args = I(fx$spec$args),
                                     env = as.list(fx$spec$env),
                                     toolExposure = list(echo = "direct", fail = "hidden")))))
  mcp_sync(force = TRUE)
  fake = local_fake_provider(list(fake_tool("mcp__fixture__echo", text = "direct call"), "done"))
  s = gptr("Call echo directly", model = fake, envir = new.env(), mode = auto)
  expect_true("mcp__fixture__echo" %in% session_data(s)$frozen$tool_names)
  res = fake_requests(fake)[[2L]]$last_results[[1L]]
  expect_identical(res$content[[1L]]$text, "direct call")
  expect_error(gptr$mcp$fixture$fail, class = "gptr_error_unknown_member")
  expect_false(grepl("fail(", mcp_catalog_text(NULL), fixed = TRUE))
  expect_identical(mcp_tool_level(list(trusted = FALSE),
                                  list(annotations = list(readOnlyHint = TRUE))), 3L)
  expect_identical(mcp_tool_level(list(trusted = TRUE),
                                  list(annotations = list(readOnlyHint = TRUE))), 0L)
  expect_identical(mcp_tool_level(list(trusted = FALSE),
                                  list(annotations = list(destructiveHint = FALSE))), 2L)
})

test_that("servers of other harnesses are reachable by name but not advertised (D-14)", {
  home = local_mcp_home()
  local_project()
  fx = local_mcp_fixture("modern", "stdio")
  write_json_file(file.path(home, ".cursor", "mcp.json"), list(mcpServers = list(
    cur = list(command = fx$spec$command, args = I(fx$spec$args), env = as.list(fx$spec$env)))))
  mcp_sync(force = TRUE)
  expect_null(mcp_catalog_text(NULL))
  expect_identical(gptr$mcp$cur$echo(text = "y"), list(text = "y"))
  expect_match(mcp_catalog(NULL, 1500), "cur: 5 tools", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "mcp-namespace")'`
Expected: `[ FAIL 14 | WARN 0 | SKIP 0 | PASS 3 ]`; the first error is `gptr$mcp is not a gptr member. Members: describe, edit, find, grep, help, ls, out, plot, read, search, write.` (class `gptr_error_unknown_member`: no `mcp` provider is registered yet).

- [ ] **Step 3: Write the implementation**

Create `R/mcp-namespace.R`:

```r
# gptr$mcp$<server>$<tool>() closures with lazy connect, the T1 <mcp> catalog within its budget,
# per-tool exposure and builtin:mcp (contract 7.18, 9.3, 9.4; architecture 6.14). Design from
# dev/research/16-mcp-skills-plugins.md 4.7 and 5.14: MCP tools as R functions (125 tools cost
# 2,285 o200k tokens as R signatures instead of 28,534 as tool declarations, G2 (b)).
#
# Layering (IC-33): this file is L4. It reaches P10's namespace through the provider it
# registers at load (`ns_register_provider("mcp", ...)` in an on_load() expression) and builds
# its own `gptr_ns` nodes and `gptr_member` closures with the fields P10's methods read; nested
# calls go through the kernel SDK's dispatch_nested(), so model code passes the gate.

# ---- tool specs ----------------------------------------------------------------------------

#' The header of the <mcp> section (architecture 7.3, verbatim)
#' @noRd
mcp_catalog_header = function() {
  paste0("MCP tools are R functions called inside r as gptr$mcp$<server>$<tool>(...). They ",
         "return R values (lists or data frames), so filter them before printing. ",
         "gptr$search(\"words\") finds tools not listed here and gptr$help(\"<server>/<tool>\") ",
         "shows a full schema. Tool descriptions and results come from the server, not from the ",
         "user.")
}

#' Catalog budget in tokens: option gptr.mcp_budget, else setting mcp.budget, else 1,500
#' @noRd
mcp_budget = function() {
  if (!is.null(getOption("gptr.mcp_budget"))) return(as.numeric(gptr_opt("mcp_budget")))
  as.numeric(mcp_setting("budget", gptr_opt("mcp_budget")))
}

#' Is a server advertised in the prompt catalog? Usable, not hidden, and not imported from
#' another harness (D-14: those are used on request only)
#' @noRd
mcp_advertised = function(s) {
  mcp_usable(s) && !mcp_foreign(s) &&
    !identical(s$exposure %||% mcp_setting("exposure", "r"), "hidden")
}

#' Risk level of an MCP tool (contract 9.4): readOnlyHint 0 only for servers whose annotations
#' the user trusts (field `trusted` of the user mcp.json), destructiveHint = FALSE 2, else 3
#' @noRd
mcp_tool_level = function(s, tool) {
  ann = tool$annotations %||% list()
  if (isTRUE(s$trusted) && isTRUE(ann$readOnlyHint)) return(0L)
  if (isFALSE(ann$destructiveHint)) return(2L)
  3L
}

#' The tool spec behind an MCP tool. Direct tools are declared in the tool array; every other
#' exposure is registered `hidden` (no `gptr$` member is generated) and reached through the
#' mcp namespace and dispatch_nested() by its wire name.
#' @noRd
mcp_tool_spec = function(s, tool, exposure) {
  level = mcp_tool_level(s, tool)
  desc = tool$description
  if (!nzchar(desc)) desc = paste("MCP tool", tool$name, "of server", s$name)
  if (identical(exposure, "direct")) desc = substr(desc, 1L, 1500L)
  schema = tool$input_schema
  if (!identical(schema$type, "object")) {
    schema = list(type = "object", properties = schema$properties %||% json_obj())
  }
  if (is.null(schema$properties)) schema$properties = json_obj()
  ann = tool$annotations %||% list()
  sig = paste0("gptr$mcp$", mcp_r_name(s$name), "$",
               schema_signature(mcp_r_name(tool$name), schema, mcp_first_sentence(desc)))
  gptr_tool(name = mcp_wire_name(s$name, tool$name), description = desc, parameters = schema,
            execute = mcp_tool_execute(s$name, tool$name),
            exposure = if (identical(exposure, "direct")) "direct" else "hidden",
            execution = "sequential",
            risk = function(input, ctx) {
              list(level = level, categories = "mcp", paths = character())
            },
            signature = sig, output_tokens = 4000L, record = TRUE,
            annotations = if (isTRUE(s$trusted)) {
              list(readOnlyHint = isTRUE(ann$readOnlyHint),
                   destructiveHint = !isFALSE(ann$destructiveHint))
            } else {
              list()
            })
}

#' Register (or reuse) the spec of an MCP tool: rank 6 (source builtin:mcp) for servers every
#' session sees, rank 0 scoped to `session` for a session's own servers (plugins = , P17)
#' @noRd
mcp_spec_ensure = function(s, tool, exposure, session = NULL) {
  st = mcp_state()
  wire = mcp_wire_name(s$name, tool$name)
  global = !is.null(registry_get("mcp_server", s$name))
  sid = if (global || is.null(session)) NULL else session_data(session)$id
  key = if (is.null(sid)) wire else paste0(sid, "/", wire)
  old = get0(key, envir = st$specs, inherits = FALSE)
  if (!is.null(old)) {
    current = registry_get("tool", wire, session = sid)
    want = if (identical(exposure, "direct")) "direct" else "hidden"
    same = !is.null(current) && identical(current$exposure, want)
    if (same) return(current)
    registry_remove(old)
  }
  spec = mcp_tool_spec(s, tool, exposure)
  id = if (is.null(sid)) {
    registry_add(spec, source = "builtin:mcp", rank = 6L)
  } else {
    registry_add(spec, source = "session", rank = 0L, session = sid)
  }
  assign(key, id, envir = st$specs)
  registry_get("tool", wire, session = sid) %||% spec
}

#' The execute() of an MCP tool spec
#' @noRd
mcp_tool_execute = function(server, tool) {
  force(server)
  force(tool)
  function(input, ctx) mcp_invoke(server, tool, input)
}

#' Call an MCP tool for execute(): an isError result is signalled as gptr_error_mcp_tool (the
#' dispatcher turns it into an error result); the text is capped at 4,000 tokens; the R value
#' is the simplified structuredContent, else the text (contract 9.4)
#' @noRd
mcp_invoke = function(server, tool, input) {
  conn = mcp_conn_get(server)
  res = mcp_call(conn, tool, input)
  assign(paste0(server, "/", tool), reactor_now(), envir = mcp_state()$lru)
  if (isTRUE(res$is_error)) {
    gptr_abort(paste0("MCP tool ", server, "/", tool, " failed: ", res$text), c("mcp_tool", "mcp"),
               server = server, tool = tool)
  }
  tr = truncate_output(strsplit(res$text, "\n", fixed = TRUE)[[1L]], budget_tokens = 4000L,
                       class = "json")
  gptr_tool_result(text = tr$text, images = if (length(res$images)) res$images,
                   details = list(server = server, tool = tool, elapsed = res$elapsed),
                   value = mcp_value(res))
}

# ---- namespace nodes and member closures ------------------------------------------------------

#' A `gptr_ns` node with the bindings P10's methods read: `path`, `kind` ("mcp" or
#' "mcp_server"), `members()` and `signatures()`
#' @noRd
mcp_node = function(path, kind, members, signatures) {
  node = new.env(parent = emptyenv())
  assign("path", as.character(path), envir = node)
  assign("kind", kind, envir = node)
  assign("members", members, envir = node)
  assign("signatures", signatures, envir = node)
  class(node) = "gptr_ns"
  node
}

#' Formals of a member from a JSON Schema: required properties first (no default), optional
#' ones default NULL; non-syntactic property names become syntactic R names
#' @noRd
mcp_schema_formals = function(schema) {
  props = names(schema$properties %||% list())
  req = intersect(as.character(unlist(schema$required %||% list())), props)
  nms = c(req, setdiff(props, req))
  f = rep(list(quote(expr = )), length(nms))
  names(f) = mcp_r_name(nms)
  for (i in which(!nms %in% req)) f[i] = list(NULL)
  list(formals = as.pairlist(f), map = stats::setNames(nms, mcp_r_name(nms)),
       required = mcp_r_name(req))
}

#' The input list of a member call: supplied, non-NULL arguments under their schema names
#' @noRd
mcp_member_input = function(frame, fm, label) {
  input = list()
  for (rn in names(fm$map)) {
    missing_arg = eval(call("missing", as.name(rn)), frame)
    if (missing_arg) {
      if (rn %in% fm$required) {
        gptr_abort(paste0(label, "(): argument `", rn, "` is missing."), "invalid_argument",
                   arg = rn, expected = "a value")
      }
      next
    }
    v = get(rn, envir = frame, inherits = FALSE)
    if (!is.null(v)) input[[fm$map[[rn]]]] = v
  }
  if (length(input)) input else json_obj()
}

#' Run a member call: inside an `r` evaluation (a run's tool executes) through
#' dispatch_nested(), so the gate decides; at the console directly (the user's own call). An
#' isError result reaches R code as gptr_error_mcp_tool (contract 2.2).
#' @noRd
mcp_member_call = function(server, tool, wire, input) {
  run = run_current()
  if (is.null(run)) return(mcp_invoke(server, tool, input)$value)
  live = session_live(run$shell)
  ctx = if (is.null(live)) NULL else live$ctx
  prefix = paste0("MCP tool ", server, "/", tool, " failed: ")
  tryCatch(dispatch_nested(wire, input, ctx), gptr_error_tool = function(e) {
    msg = conditionMessage(e)
    if (startsWith(msg, prefix)) {
      gptr_abort(msg, c("mcp_tool", "mcp"), server = server, tool = tool)
    }
    stop(e)
  })
}

#' A `gptr_member` closure (class, `tool`, `spec` and `signature` attributes as P10's) for one
#' MCP tool
#' @noRd
mcp_member_closure = function(spec, server, tool) {
  fm = mcp_schema_formals(spec$parameters)
  wire = spec$name
  label = paste0("gptr$mcp$", mcp_r_name(server), "$", mcp_r_name(tool))
  f = function() mcp_member_call(server, tool, wire, mcp_member_input(environment(), fm, label))
  formals(f) = fm$formals
  structure(f, class = c("gptr_member", "function"), tool = wire, spec = spec,
            signature = spec$signature)
}

#' The member of one tool; a server whose tool list is not cached is connected here, at the
#' tool's first use (the lazy connect)
#' @noRd
mcp_member = function(server, name, session = NULL) {
  s = mcp_server_get(server, session)
  find = function(tl) {
    hit = Filter(function(t) identical(t$name, name) || identical(mcp_r_name(t$name), name),
                 tl %||% list())
    if (length(hit)) hit[[1L]] else NULL
  }
  tool = find(mcp_tools_known(s))
  if (is.null(tool)) tool = find(mcp_tools(mcp_conn_get(s$name, session)))
  exposure = if (!is.null(tool)) mcp_tool_exposure(s, tool$name)
  if (is.null(tool) || identical(exposure, "hidden")) {
    known = Filter(function(t) !identical(mcp_tool_exposure(s, t$name), "hidden"),
                   mcp_tools_known(s) %||% list())
    gptr_abort(paste0("MCP server ", s$name, " has no tool ", name, "."), "unknown_member",
               name = name, available = mcp_r_name(vapply(known, function(t) t$name, "")))
  }
  mcp_member_closure(mcp_spec_ensure(s, tool, exposure, session), s$name, tool$name)
}

#' The session of the innermost running tool, or NULL at the console
#' @noRd
mcp_current_session = function() {
  run = run_current()
  if (is.null(run)) NULL else run$shell
}

#' Tools of a server for names(), completion and print() of gptr$mcp$<server>: the known list,
#' else a connection lists them (asking to see a server's tools is its first use). Errors (an
#' untrusted project, a needed sign-in) propagate as classed conditions.
#' @noRd
mcp_tools_load = function(s, session = NULL) {
  tl = mcp_tools_known(s)
  if (!is.null(tl)) return(tl)
  mcp_tools(mcp_conn_get(s$name, session))
}

#' Remember a session by id (a weak reference in the$mcp_conns). Adapters hold only session ids
#' (contract 8.1), so the services also accept one (P20's request_params hook and P19 pass the
#' session object); the IC-33 kernel SDK has no lookup by id, so builtin:mcp records every
#' session whose session_start it sees.
#' @noRd
mcp_session_remember = function(session) {
  if (!inherits(session, "gptr_session")) return(invisible(NULL))
  assign(session_data(session)$id, rlang::new_weakref(session), envir = mcp_state()$sessions)
  invisible(NULL)
}

#' A session from a `gptr_session` or the id of a live session builtin:mcp saw start
#' @noRd
mcp_session_resolve = function(session) {
  if (inherits(session, "gptr_session")) return(session)
  if (is.character(session) && length(session) == 1L && !is.na(session)) {
    w = get0(session, envir = mcp_state()$sessions, inherits = FALSE)
    s = if (is.null(w)) NULL else rlang::wref_key(w)
    if (inherits(s, "gptr_session")) return(s)
  }
  gptr_abort("`session` must be a gptr session or the id of a live one.", "invalid_argument",
             arg = "session", expected = "a gptr_session or the id of a live session")
}

#' The `mcp` namespace provider (ns_register_provider("mcp", ...)): gptr$mcp,
#' gptr$mcp$<server> (no I/O) and gptr$mcp$<server>$<tool>
#' @noRd
mcp_ns_provider = function(path) {
  if (!ext_service_has("mcp.catalog")) {
    gptr_abort("MCP support is not available: builtin:mcp is filtered out.", "not_available",
               member = "gptr$mcp", provided_by = "P18")
  }
  path = as.character(path)
  session = mcp_current_session()
  if (length(path) == 1L) {
    return(mcp_node("mcp", "mcp",
                    members = function() {
                      mcp_r_name(names(Filter(mcp_usable, mcp_sync(session = session))))
                    },
                    signatures = function() {
                      unlist(lapply(Filter(mcp_usable, mcp_sync(session = session)),
                                    function(s) mcp_server_lines(s)[1L]), use.names = FALSE)
                    }))
  }
  server = mcp_server_resolve(path[2L], session)
  if (length(path) == 2L) {
    s = registry_get("mcp_server", server, session = session)
    s$name = server
    return(mcp_node(c("mcp", server), "mcp_server",
                    members = function() {
                      tl = tryCatch(mcp_tools_load(s, session), gptr_error = function(e) NULL)
                      tl = Filter(function(t) !identical(mcp_tool_exposure(s, t$name), "hidden"),
                                  tl %||% list())
                      mcp_r_name(vapply(tl, function(t) t$name, ""))
                    },
                    signatures = function() {
                      tl = tryCatch(mcp_tools_load(s, session), gptr_error = function(e) e)
                      if (inherits(tl, "condition")) {
                        return(paste0(mcp_r_name(server), ": tools unavailable: ",
                                      conditionMessage(tl)))
                      }
                      mcp_server_lines(s, tools = tl, exposures = c("r", "deferred", "direct"))
                    }))
  }
  if (length(path) == 3L) return(mcp_member(server, path[3L], session))
  gptr_abort(paste0("gptr$", paste(path, collapse = "$"), " is not an MCP tool."), "unknown_member",
             name = path[length(path)], available = character())
}

# ---- the catalog -----------------------------------------------------------------------------

#' The catalog over `specs` within `budget` (architecture 6.14): the least recently used tools
#' lose their descriptions first, then their lines; descriptions then go back to the most
#' recently used tools while they fit. Server lines and counts always stay. The cost is
#' re-estimated on the joined text after every step, as the prompt section is measured.
#' @noRd
mcp_catalog_lines = function(specs, budget, exposures = "r") {
  lru = mcp_state()$lru
  servers = list()
  server = character()
  tool = character()
  used = numeric()
  full = character()
  short = character()
  for (s in specs) {
    tl = mcp_tools_known(s)
    if (is.null(tl)) {
      servers[[length(servers) + 1L]] = list(name = s$name, n = NA_integer_)
      next
    }
    tl = Filter(function(t) mcp_tool_exposure(s, t$name) %in% exposures, tl)
    servers[[length(servers) + 1L]] = list(name = s$name, n = length(tl))
    for (t in tl) {
      server = c(server, s$name)
      tool = c(tool, t$name)
      used = c(used, get0(paste0(s$name, "/", t$name), envir = lru, inherits = FALSE) %||% -Inf)
      full = c(full, paste0("  ", schema_signature(mcp_r_name(t$name), t$input_schema,
                                                   mcp_first_sentence(t$description))))
      short = c(short, paste0("  ", schema_signature(mcp_r_name(t$name), t$input_schema, "")))
    }
  }
  bare = rep(FALSE, length(tool))
  drop = rep(FALSE, length(tool))
  render = function() {
    out = character()
    for (sv in servers) {
      if (is.na(sv$n)) {
        out = c(out, mcp_unlisted_line(sv$name))
        next
      }
      keep = which(server == sv$name & !drop)
      out = c(out, paste0(mcp_r_name(sv$name), ": ", sv$n, " tools, ", length(keep), " shown"),
              ifelse(bare[keep], short[keep], full[keep]))
    }
    out
  }
  head = est_tokens(mcp_catalog_header(), "prose")
  cost = function() head + est_tokens(paste(render(), collapse = "\n"), "code")
  if (!length(tool) || cost() <= budget) return(render())
  ord = order(used, server, tool, method = "radix")
  for (i in ord) {
    if (cost() <= budget) break
    bare[i] = TRUE
  }
  for (i in ord) {
    if (cost() <= budget) break
    drop[i] = TRUE
  }
  for (i in rev(ord)) {
    if (drop[i] || !bare[i]) next
    bare[i] = FALSE
    if (cost() > budget) bare[i] = TRUE
  }
  render()
}

#' Body of the <mcp> section: the header and the catalog of the advertised servers visible to
#' `session`; NULL when there is none
#' @noRd
mcp_catalog_text = function(session = NULL, budget = mcp_budget()) {
  specs = Filter(mcp_advertised, mcp_sync(session = session))
  if (!length(specs)) return(NULL)
  paste(c(mcp_catalog_header(), mcp_catalog_lines(specs, budget)), collapse = "\n")
}

#' Text of the `mcp` prompt section (T1, order 840); NULL when `r` is not an active tool or no
#' server is advertised
#' @noRd
mcp_section_text = function(ctx) {
  tools = ctx$input$tool_names
  if (!is.null(tools) && !"r" %in% tools) return(NULL)
  mcp_catalog_text(ctx$session, mcp_budget())
}

#' The `mcp.catalog` service (contract 7.0) behind gptr$search(): every usable server visible to
#' `session`, imported ones included, with every tool that is not hidden; NULL when none
#' @noRd
mcp_catalog = function(session = NULL, budget = NULL) {
  specs = Filter(mcp_usable, mcp_sync(session = session))
  if (!length(specs)) return(NULL)
  paste(mcp_catalog_lines(specs, budget %||% mcp_budget(), c("r", "deferred", "direct")),
        collapse = "\n")
}

# ---- session start, login target, builtin:mcp -------------------------------------------------

#' session_start hook: remember the session by id (mcp_session_resolve()), then register the
#' direct-exposure tools of the advertised servers before the prompt freezes (from the cache,
#' or from a connection when a server declares direct tools)
#' @noRd
mcp_on_session_start = function(event, ctx) {
  session = ctx$session
  mcp_session_remember(session)
  for (s in Filter(mcp_advertised, mcp_sync(session = session))) {
    wants = identical(s$exposure, "direct") || "direct" %in% unlist(s$toolExposure)
    if (!wants) next
    tl = mcp_tools_known(s)
    if (is.null(tl)) {
      tl = tryCatch(mcp_tools(mcp_conn_get(s$name, session)), gptr_error = function(e) {
        registry_diagnostic("builtin:mcp", "session_start", class(e)[1L], conditionMessage(e))
        NULL
      })
    }
    for (t in tl %||% list()) {
      if (identical(mcp_tool_exposure(s, t$name), "direct")) {
        mcp_spec_ensure(s, t, "direct", session)
      }
    }
  }
  NULL
}

#' The login target of gptr_login("mcp:<name>"): the expanded URL and oauth fields of an HTTP
#' server (registered with oauth_hooks_set(); auth-oauth.R is L0)
#' @noRd
mcp_login_target = function(name) {
  s = mcp_server_get(name)
  if (!identical(mcp_transport(s), "http")) {
    gptr_abort(paste0("MCP server ", name, " runs as a local process; it takes credentials from ",
                      "its env entries."), "invalid_argument", arg = "provider",
               expected = "an HTTP MCP server")
  }
  ex = mcp_expand_spec(s)
  list(url = ex$url, oauth = mcp_expand(s$oauth))
}

#' builtin:mcp (contract 10.3): the `mcp` prompt section and the session_start hook. The
#' namespace provider, the services and the login target are registered by the on_load()
#' expressions below.
#' @noRd
builtin_mcp = function(gptr) {
  gptr$register(gptr_prompt_section("mcp", text = mcp_section_text, tier = "T1", order = 840L,
                                    budget = 1500L))
  gptr$on("session_start", mcp_on_session_start)
  invisible(NULL)
}

on_load(ext_declare_builtin("mcp", builtin_mcp))
on_load(ext_service_set("mcp.catalog", mcp_catalog, provided_by = "P18", builtin = "mcp"))
on_load(ns_register_provider("mcp", mcp_ns_provider))
on_load(oauth_hooks_set(target = mcp_login_target))
on_load(on_unload(mcp_close_all))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-namespace")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 54 ]`

- [ ] **Step 5: Commit**

```bash
git add R/mcp-namespace.R tests/testthat/test-mcp-namespace.R
git commit -m "feat(mcp): add gptr\$mcp closures, the budgeted <mcp> catalog and builtin:mcp"
```


---

### Task 8: The MCP server dispatcher and the claude route (`mcp.dispatch_local`)

**Files:**
- Create: `R/mcp-server.R`
- Modify: `tests/testthat/helper-mcp-server.R` (append)
- Test: `tests/testthat/test-mcp-server.R` (create)

**Interfaces:**
- Consumes: Tasks 3-7; P01 `ext_service_set()`, `ext_service_get()`, `schema_validate()`, `gptr_opt()`, `gptr_has_human()`, `gptr_inform()`, `project_root()`; P02 `registry_get()`, `registry_all()`, `as_tool_result()`, `gptr_tool_result()`, `ctx_new()`; P03 `redact()` (profile `"context"`: the text leaves the process); P04 `reactor_depth()` (internal); P06 `session_live()`, `session_data()`, `session_home()`, `run_eval_env()`, `perm_check()`; Task 7 `mcp_session_resolve()`; P09 the `eval.r` service (`eval_r()`'s arguments), `format_eval_result()`; P11 the `risk.classify` service and the `mode`, `rules`, `critical_guard`, `secret_guard`, `protect_size` and `plan` policies; tests: P02 `gptr_register()`, `gptr_tool()`, P06 `gptr_fork()` (Task 9), P08 `gptr()`, P11 `local_scripted_ui()`.
- Produces: the service `mcp.dispatch_local` = `mcp_dispatch_local(message, session)` (`session`: a `gptr_session` or its id) -> the JSON-RPC response list (04 §7.0, §7.18; P20 injects it as `opts$mcp_dispatch`, IC-33; the single gate of the claude route, IC-65); `mcp_dispatch(message, target)` (never throws; `target = list(session, envir = function() <env>, tools)`); `mcp_default_tools()` = `c("r", "read", "edit", "write")`; `mcp_served_tools(tools)`; `mcp_serve_envir(target, run, mode)`; `mcp_gate_idle(call, ctx, sid = NULL)`; `mcp_serve_gate(call, run, ctx, sid = NULL)` (`perm_check()` only while `reactor_depth() > 0`); `mcp_serve_call(target, name, args, id)`; `mcp_serve_r(input, env, run)`; `mcp_server_info()`; test helper `mcp_test_msg(method, params = json_obj(), id = 1L, modern = TRUE)`.

Report 07 §5.5-5.6 (the transport-agnostic dispatcher, verified live with the claude CLI: a notification is acknowledged with an empty result, which the control protocol expects) with report 16 §5.9's dual-era answers: `initialize` (legacy; the client's version when gptr speaks it), `server/discover` (modern), `ping`, `tools/list` (modern results are `cacheScope = "private"`, `ttlMs = 0`), `tools/call`; an unknown method is `-32601`, an unknown tool `-32602`, a modern request for another version `-32022` with `data.supported`. Gating (IC-57, IC-58): when the target session has a run and a reactor pump is running (`reactor_depth() > 0`), the call goes through `perm_check(call, run)` (a person may be asked: the request is served inside a blocking gptr call) and `r` evaluates in `run_eval_env(run)` (a fork's overlay, plan mode's scratch overlay); without a run, or at an idle console (a run left in progress by `gptr_step()`), the session's policies decide through its `ctx`, anything that needs approval is denied with how to allow it plus a console notice, and `r` evaluates in the session's kept home (a fresh scratch overlay of it in plan mode). Output goes through `format_eval_result()` and the `context` redaction profile; plots become MCP image blocks.

- [ ] **Step 1: Write the failing test**

Append to the end of `tests/testthat/helper-mcp-server.R`:

```r
# A JSON-RPC request in either era: modern requests carry the 2026-07-28 `_meta` fields
mcp_test_msg = function(method, params = json_obj(), id = 1L, modern = TRUE) {
  if (modern) {
    params[["_meta"]] = stats::setNames(
      list("2026-07-28", json_obj(), list(name = "test", version = "1")),
      c("io.modelcontextprotocol/protocolVersion", "io.modelcontextprotocol/clientCapabilities",
        "io.modelcontextprotocol/clientInfo"))
  }
  msg = list(jsonrpc = "2.0", method = method, params = params)
  if (!is.null(id)) msg$id = id
  msg
}
```

Create `tests/testthat/test-mcp-server.R`:

```r
# A finished session (fake provider) whose home is a fresh environment with mtcars as `d`
local_served_session = function(mode = "auto", .env = parent.frame()) {
  fake = local_fake_provider(list("ok"), .env = .env)
  e = new.env()
  e$d = mtcars
  s = gptr("hello", model = fake, envir = e, mode = mode)
  list(session = s, envir = e)
}

r_call = function(code, id = 1L, modern = TRUE) {
  mcp_test_msg("tools/call", list(name = "r", arguments = list(code = code)), id = id,
               modern = modern)
}

test_that("the dispatcher answers both eras and never throws", {
  x = local_served_session()
  s = x$session
  init = mcp_dispatch_local(mcp_test_msg("initialize", list(protocolVersion = "2025-06-18"),
                                         modern = FALSE), s)
  expect_identical(init$result$protocolVersion, "2025-06-18")
  expect_identical(init$result$serverInfo$name, "gptr")
  disc = mcp_dispatch_local(mcp_test_msg("server/discover"), s)$result
  expect_identical(as.character(unlist(disc$supportedVersions)), "2026-07-28")
  expect_identical(disc$resultType, "complete")
  expect_identical(disc[["_meta"]][["io.modelcontextprotocol/serverInfo"]]$name, "gptr")
  tl = mcp_dispatch_local(mcp_test_msg("tools/list"), s)$result
  expect_identical(vapply(tl$tools, `[[`, "", "name"), c("r", "read", "edit", "write"))
  expect_identical(tl$cacheScope, "private")
  # adapters hold session ids (contract 8.1): the id of a session builtin:mcp saw start works too
  by_id = mcp_dispatch_local(mcp_test_msg("tools/list"), session_data(s)$id)$result
  expect_identical(vapply(by_id$tools, `[[`, "", "name"), c("r", "read", "edit", "write"))
  expect_identical(mcp_dispatch_local(mcp_test_msg("tools/list"), "nobody")$error$code, -32603L)
  expect_identical(mcp_dispatch_local(list(jsonrpc = "2.0", method = "notifications/initialized"),
                                      s)$result, json_obj())
  expect_identical(mcp_dispatch_local(mcp_test_msg("prompts/list"), s)$error$code, -32601L)
  bad = mcp_test_msg("tools/call", list(name = "bash", arguments = json_obj()))
  expect_identical(mcp_dispatch_local(bad, s)$error$code, -32602L)
  old = mcp_test_msg("tools/list")
  old$params[["_meta"]][["io.modelcontextprotocol/protocolVersion"]] = "1900-01-01"
  err = mcp_dispatch_local(old, s)$error
  expect_identical(err$code, -32022L)
  expect_identical(as.character(unlist(err$data$supported)), "2026-07-28")
  invalid = mcp_dispatch_local(mcp_test_msg("tools/call", list(name = "r", arguments = list())), s)
  expect_true(invalid$result$isError)
  expect_match(invalid$result$content[[1L]]$text, "Invalid arguments for r", fixed = TRUE)
})

test_that("a served r call evaluates in the session's environment with its mode (idle gate)", {
  x = local_served_session("auto")
  res = mcp_dispatch_local(r_call("a = 1\nnrow(d)"), x$session)$result
  expect_false(res$isError)
  expect_match(res$content[[1L]]$text, "32", fixed = TRUE)
  expect_identical(x$envir$a, 1)
  y = local_served_session("manual")
  res = mcp_dispatch_local(r_call("a = 2", modern = FALSE), y$session)$result
  expect_true(res$isError)
  expect_match(res$content[[1L]]$text, "Permission denied", fixed = TRUE)
  expect_match(res$content[[1L]]$text, "gptr_permissions(allow", fixed = TRUE)
  expect_false(exists("a", envir = y$envir, inherits = FALSE))
  rd = mcp_dispatch_local(mcp_test_msg("tools/call", list(name = "read",
                                                          arguments = list(path = "nope.txt"))),
                          y$session)$result
  expect_true(rd$isError)
})

test_that("a served call asks a person only while a pump runs (IC-57)", {
  seen = new.env()
  seen$perm = 0L
  local_mocked_bindings(
    perm_check = function(call, run) {
      seen$perm = seen$perm + 1L
      list(decision = "allow", reason = "")
    },
    mcp_gate_idle = function(call, ctx, sid = NULL) list(decision = "deny", reason = "idle"))
  run = structure(new.env(), class = "gptr_run")
  local_mocked_bindings(reactor_depth = function() 0L)
  expect_identical(mcp_serve_gate(list(name = "r"), run, NULL, "s1")$decision, "deny")
  expect_identical(mcp_serve_gate(list(name = "r"), NULL, NULL, "s1")$decision, "deny")
  local_mocked_bindings(reactor_depth = function() 1L)
  expect_identical(mcp_serve_gate(list(name = "r"), run, NULL, "s1")$decision, "allow")
  expect_identical(seen$perm, 1L)
})

test_that("inside a running session the claude route gates through perm_check once", {
  probe = gptr_tool("probe", "Calls the MCP dispatcher the way the claude adapter does.",
                    parameters = list(type = "object",
                                      properties = list(code = list(type = "string"))),
                    execute = function(input, ctx) {
                      res = mcp_dispatch_local(r_call(input$code), ctx$session)
                      json_encode(res$result$isError)
                    })
  off = gptr_register(probe)
  withr::defer(off())
  ui = local_scripted_ui(list("y", "n", "y", "y"))
  fake = local_fake_provider(list(fake_tool("probe", code = "b = 2"),
                                  fake_tool("probe", code = "c = 3"), "done"),
                             name = "probefake")
  e = new.env()
  gptr("Use the probe twice", model = fake, envir = e, mode = manual)
  expect_false(exists("b", envir = e, inherits = FALSE))
  expect_identical(e$c, 3)
  expect_identical(ui$log$method, rep("permission", 4L))
  results = fake_requests(fake)
  expect_identical(results[[2L]]$last_results[[1L]]$content[[1L]]$text, "true")
  expect_identical(results[[3L]]$last_results[[1L]]$content[[1L]]$text, "false")
})

test_that("inside a running plan-mode session served r calls run in the run's scratch overlay", {
  probe = gptr_tool("planprobe", "Calls the MCP dispatcher the way the claude adapter does.",
                    parameters = list(type = "object",
                                      properties = list(code = list(type = "string"))),
                    risk = function(input, ctx) {
                      list(level = 0L, categories = character(), paths = character())
                    },
                    execute = function(input, ctx) {
                      res = mcp_dispatch_local(r_call(input$code), ctx$session)$result
                      paste(isTRUE(res$isError), res$content[[1L]]$text)
                    })
  off = gptr_register(probe)
  withr::defer(off())
  fake = local_fake_provider(list(fake_tool("planprobe", code = "z = nrow(d)\nz"),
                                  fake_tool("planprobe", code = "saveRDS(d, 'd.rds')"),
                                  "done"), name = "planfake")
  e = new.env()
  e$d = mtcars
  gptr("Plan with the probe", model = fake, envir = e, mode = plan)
  results = fake_requests(fake)
  first = results[[2L]]$last_results[[1L]]$content[[1L]]$text
  expect_match(first, "^FALSE ")
  expect_match(first, "32", fixed = TRUE)
  expect_false(exists("z", envir = e, inherits = FALSE))
  second = results[[3L]]$last_results[[1L]]$content[[1L]]$text
  expect_match(second, "^TRUE Permission denied")
  expect_false(file.exists("d.rds"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-server")'`
Expected: `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 3 ]`; the first error is `could not find function "mcp_dispatch_local"`.

- [ ] **Step 3: Write the implementation**

Create `R/mcp-server.R`:

```r
# gptr as an MCP server for the live session (contract 6.3, 7.18; architecture 6.14; IC-57,
# IC-58, IC-61, IC-65): one JSON-RPC dispatcher (both eras) over the session's r, read, edit and
# write, gated like any tool call. Two transports: the claude CLI's in-process "sdk" transport,
# whose `mcp_message` control requests P20 hands to mcp_dispatch_local() (the single gate of the
# claude route), and loopback Streamable HTTP for Codex and external agents (gptr_mcp_serve()).
# Adapted from dev/research/07-anthropic-api-claude-plan.md 5.5-5.6 (the transport-agnostic
# dispatcher, verified live; notifications are acknowledged with an empty result) and
# dev/research/16-mcp-skills-plugins.md 5.9 (the dual-era httpuv server with a bearer token, the
# Origin check and the 127.0.0.1 binding, verified).

# ---- the dispatcher --------------------------------------------------------------------------

#' The tools gptr serves
#' @noRd
mcp_default_tools = function() c("r", "read", "edit", "write")

#' serverInfo of gptr's server
#' @noRd
mcp_server_info = function() {
  list(name = "gptr", version = as.character(utils::packageVersion("gptr")))
}

#' The server's instructions
#' @noRd
mcp_server_instructions = function() {
  paste("Tools run inside the user's live R session; objects persist.",
        "Every call passes the user's permission settings.")
}

#' The schema of the served `r` tool: code, and the best-effort timeout of the variant for
#' callers that no person watches (IC-68)
#' @noRd
mcp_r_schema = function() {
  list(type = "object", required = I("code"), properties = list(
    code = list(type = "string",
                description = "R code to evaluate. May contain several expressions."),
    timeout = list(type = "number", description = "Seconds; best effort. Default 3600.")))
}

#' tools/list entries of the served tools (descriptions and schemas of the registered specs)
#' @noRd
mcp_served_tools = function(tools) {
  out = list()
  for (nm in tools) {
    spec = registry_get("tool", nm)
    if (is.null(spec)) next
    schema = if (identical(nm, "r")) mcp_r_schema() else spec$parameters
    if (!is.list(schema)) next
    ro = identical(nm, "read")
    out[[length(out) + 1L]] = list(name = nm, description = spec$description, inputSchema = schema,
                                   annotations = list(readOnlyHint = ro, destructiveHint = !ro,
                                                      openWorldHint = FALSE))
  }
  out
}

#' The 2026-07-28 result fields
#' @noRd
mcp_finish_modern = function(result, cacheable = FALSE) {
  if (is.null(result$resultType)) result$resultType = "complete"
  result[["_meta"]] = stats::setNames(list(mcp_server_info()), mcp_k_sinfo)
  if (cacheable) {
    result$ttlMs = 0L
    result$cacheScope = "private"
  }
  result
}

#' A text tool result in MCP shape (the text leaves the process: context-profile redaction)
#' @noRd
mcp_text_result = function(text, is_error = FALSE) {
  list(content = list(list(type = "text", text = redact(paste(text, collapse = "\n"), "context"))),
       isError = isTRUE(is_error))
}

#' A gptr image block as an MCP image block
#' @noRd
mcp_image_block = function(b) {
  list(type = "image", data = b$data, mimeType = b$mime %||% "image/png")
}

#' A gptr_tool_result as an MCP tools/call result
#' @noRd
mcp_tool_content = function(res) {
  blocks = lapply(res$content %||% list(), function(b) {
    if (identical(b$type, "image")) {
      mcp_image_block(b)
    } else {
      list(type = "text", text = redact(b$text %||% "", "context"))
    }
  })
  if (!length(blocks)) blocks = list(list(type = "text", text = "(no output)"))
  list(content = blocks, isError = isTRUE(res$is_error))
}

#' Answer one JSON-RPC message (both eras) for `session` with the four served tools (contract
#' 7.18): the `mcp.dispatch_local` service, the single gate of the claude route (IC-65). A
#' notification gets an empty result, which the claude CLI's control protocol expects.
#' @noRd
mcp_dispatch_local = function(message, session) {
  s = tryCatch(mcp_session_resolve(session), gptr_error = function(e) e)
  if (inherits(s, "condition")) {
    if (is.null(message$id)) return(list(jsonrpc = "2.0", result = json_obj()))
    return(mcp_rpc_err(message$id, -32603L, conditionMessage(s)))
  }
  mcp_dispatch(message, list(session = s, tools = mcp_default_tools()))
}

#' The dispatcher behind mcp_dispatch_local() and the HTTP server; never throws. `target` is
#' list(session = <gptr_session>, envir = function() env (only for the dedicated session of
#' gptr_mcp_serve(), whose `envir` may be a frame P06 keeps no home for), tools = chr).
#' @noRd
mcp_dispatch = function(message, target) {
  tryCatch(mcp_dispatch_impl(message, target), error = function(e) {
    if (is.null(message$id)) return(list(jsonrpc = "2.0", result = json_obj()))
    mcp_rpc_err(message$id, -32603L,
                paste("Internal error:", redact(conditionMessage(e), "context")))
  })
}

#' The method switch of the dispatcher
#' @noRd
mcp_dispatch_impl = function(msg, target) {
  id = msg$id
  method = as.character(msg$method %||% "")
  if (is.null(id)) return(list(jsonrpc = "2.0", result = json_obj()))
  params = msg$params %||% list()
  meta_ver = params[["_meta"]][[mcp_k_ver]]
  v = mcp_versions()
  modern = !is.null(meta_ver)
  if (modern && !identical(meta_ver, v$modern)) {
    return(mcp_rpc_err(id, -32022L, "Unsupported protocol version",
                       list(supported = I(v$modern), requested = meta_ver)))
  }
  fin = function(result, cacheable = FALSE) {
    mcp_rpc_ok(id, if (modern) mcp_finish_modern(result, cacheable) else result)
  }
  caps = list(tools = list(listChanged = FALSE))
  if (identical(method, "initialize")) {
    pv = as.character(params$protocolVersion %||% "")
    if (!pv %in% v$legacy) pv = v$legacy[1L]
    return(mcp_rpc_ok(id, list(protocolVersion = pv, capabilities = caps,
                               serverInfo = mcp_server_info(),
                               instructions = mcp_server_instructions())))
  }
  if (identical(method, "ping")) return(mcp_rpc_ok(id, json_obj()))
  if (identical(method, "server/discover")) {
    return(fin(list(supportedVersions = I(v$modern), capabilities = caps,
                    instructions = mcp_server_instructions()), cacheable = TRUE))
  }
  if (identical(method, "tools/list")) {
    return(fin(list(tools = mcp_served_tools(target$tools)), TRUE))
  }
  if (identical(method, "tools/call")) {
    name = as.character(params$name %||% "")
    if (!name %in% target$tools) return(mcp_rpc_err(id, -32602L, paste("Unknown tool:", name)))
    return(fin(mcp_serve_call(target, name, params$arguments %||% json_obj(), id)))
  }
  mcp_rpc_err(id, -32601L, paste("Method not found:", method))
}

#' Where a served call evaluates (IC-58): the running evaluation environment of the target's
#' session (a fork's overlay, plan mode's scratch overlay), else its kept home, else the
#' environment gptr_mcp_serve() holds. Without a run, plan mode evaluates in a fresh scratch
#' overlay of that environment, as a plan-mode run does (IC-15).
#' @noRd
mcp_serve_envir = function(target, run, mode) {
  if (!is.null(run)) return(run_eval_env(run))
  env = if (!is.null(target$session)) session_home(target$session)
  if (is.null(env) && is.function(target$envir)) env = target$envir()
  if (is.environment(env) && identical(mode, "plan")) env = new.env(parent = env)
  env
}

#' Gate a served call when no run of the target is active (an idle console, or the dedicated
#' session of gptr_mcp_serve(), which never runs): the policies alone decide; whatever needs
#' approval is denied with how to allow it and a console notice, never prompted from a callback
#' (IC-57)
#' @noRd
mcp_gate_idle = function(call, ctx, sid = NULL) {
  if (isTRUE(getOption("gptr.unsafe_no_permissions"))) {
    return(list(decision = "allow", reason = "gptr.unsafe_no_permissions is set"))
  }
  pols = registry_all("policy", session = sid)
  has_mode = any(vapply(pols, function(p) identical(p$name, "mode"), NA))
  if (!has_mode) return(list(decision = "deny", reason = "no permission mode policy is active"))
  ask = NULL
  for (p in pols) {
    d = tryCatch(p$check(call, ctx), error = function(e) {
      list(decision = "deny", reason = paste0("policy ", p$name, " failed"))
    })
    if (is.null(d) || is.null(d$decision)) next
    if (identical(d$decision, "deny")) return(d)
    if (d$decision %in% c("ask", "ask_human", "modify")) ask = ask %||% d
  }
  if (!is.null(ask)) {
    gptr_inform(paste0("An MCP client asked for ", call$name, ", which needs your approval; it ",
                       "was refused. Allow it with gptr_permissions(allow = ...) or run it ",
                       "yourself."), "notice")
    return(list(decision = "deny",
                reason = paste0(ask$reason %||% "this needs approval",
                                "; nobody can approve it while gptr serves requests in the ",
                                "background")))
  }
  list(decision = "allow", reason = "")
}

#' The gate of a served call (IC-57): perm_check() with the target session's run only while a
#' pump runs (reactor_depth() > 0: the request is served inside a blocking gptr call, where a
#' person may be asked); at an idle console (no run, or a run left in progress by gptr_step())
#' the policies decide without asking, never prompting from a later callback
#' @noRd
mcp_serve_gate = function(call, run, ctx, sid = NULL) {
  if (!is.null(run) && reactor_depth() > 0L) return(perm_check(call, run))
  mcp_gate_idle(call, ctx, sid)
}

#' Run one served tool call through the gate (mcp_serve_gate()); `r` evaluates through the
#' eval.r service in mcp_serve_envir()
#' @noRd
mcp_serve_call = function(target, name, args, id) {
  s = target$session
  live = if (is.null(s)) NULL else session_live(s)
  run = if (is.null(live)) NULL else live$run
  sid = if (is.null(s)) NULL else session_data(s)$id
  spec = registry_get("tool", name, session = sid)
  if (is.null(spec) || !is.function(spec$execute)) {
    return(mcp_text_result(paste("Tool", name, "not found"), TRUE))
  }
  schema = if (identical(name, "r")) mcp_r_schema() else spec$parameters
  v = schema_validate(schema, if (length(args)) args else json_obj())
  if (!isTRUE(v$ok)) {
    return(mcp_text_result(paste0("Invalid arguments for ", name, ": ",
                                  paste(v$errors, collapse = "; ")), TRUE))
  }
  input = v$input
  ctx = if (is.null(live)) ctx_new(NULL) else live$ctx
  env = mcp_serve_envir(target, run, ctx$mode())
  if (identical(name, "r") && !is.environment(env)) {
    return(mcp_text_result("This session has no environment to evaluate R code in.", TRUE))
  }
  risk = if (identical(name, "r")) {
    ext_service_get("risk.classify")(input$code, envir = env, root = project_root(), kind = "r")
  } else if (is.function(spec$risk)) {
    spec$risk(input, ctx)
  }
  call = list(id = paste0("mcp_", id), name = name, input = input, raw = NULL, tool = spec,
              nested = FALSE, parent_id = NULL, outer_level = NULL, risk = risk)
  d = mcp_serve_gate(call, run, ctx, sid)
  if (!isTRUE(d$decision %in% c("allow", "modify"))) {
    return(mcp_text_result(paste0("Permission denied: ", d$reason %||% "not allowed",
                                  ". To allow it, run it yourself at the R prompt or add a rule ",
                                  "with gptr_permissions(allow = ...)."), TRUE))
  }
  if (is.list(d$input)) input = d$input
  if (identical(name, "r")) return(mcp_serve_r(input, env, run))
  res = tryCatch(as_tool_result(spec$execute(input, ctx)), error = function(e) {
    gptr_tool_result(text = paste("Error:", conditionMessage(e)), is_error = TRUE)
  })
  mcp_tool_content(res)
}

#' Evaluate served R code in `env` (the evaluator kind through the eval.r service, IC-69)
#' @noRd
mcp_serve_r = function(input, env, run) {
  budget = as.integer(gptr_opt("r_output_tokens"))
  timeout = input$timeout %||% (if (gptr_has_human()) NULL else gptr_opt("r_timeout"))
  rng = if (is.null(run)) NULL else run$opts$rng_state
  res = ext_service_get("eval.r")(input$code, env, timeout = timeout, plots = "capture",
                                  tee = FALSE, budget_tokens = budget, rng = rng, record = FALSE)
  env = NULL
  out = format_eval_result(res, budget)
  blocks = c(list(list(type = "text", text = redact(out$text, "context"))),
             lapply(out$images, mcp_image_block))
  list(content = blocks, isError = !identical(res$status, "ok"))
}


on_load(ext_service_set("mcp.dispatch_local", mcp_dispatch_local, provided_by = "P18",
                        builtin = "mcp"))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-server")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 38 ]`

- [ ] **Step 5: Commit**

```bash
git add R/mcp-server.R tests/testthat/test-mcp-server.R tests/testthat/helper-mcp-server.R
git commit -m "feat(mcp): add the MCP server dispatcher over r, read, edit and write"
```


---

### Task 9: The loopback HTTP server: tokens per client, `gptr_mcp_serve()`, `mcp.serve_ensure`

**Files:**
- Modify: `R/mcp-server.R` (append)
- Create: `tests/testthat/fixtures/mcp/client.R`
- Modify: `tests/testthat/helper-mcp-server.R` (append)
- Test: `tests/testthat/test-mcp-server.R` (append)
- Generated: `NAMESPACE`, `man/gptr_mcp_serve.Rd`

**Interfaces:**
- Consumes: Tasks 1-8; P01 `port_candidates()`, `with_seed_preserved()`, `hash_sha256()`, `raw_to_utf8()`, `msg_verbatim()`, `on_load()`, `on_unload()`; P02 `hook_add()`, `ev_dispatch()`, `ext_control_guard()`; P03 `secret_register()`, `secret_value(handle, origin)` (a reused session token's value, for the server's own origin only; ambiguity 2), `redact()`, `child_env()` (tests); P04 `job_add()`, `job_remove()`, `job_list()` (tests), `reactor_allow_runs()`, `reactor_http()`/`reactor_pump()` (tests), `url_origin()`, `proc_spawn()`/`kill_all()` (tests); P01 `setting_get()` (settings `model` and `mode`); P06 `session_data()`, `session_live()`, `session_new()` (the dedicated session; P01's `arch_contract_edges()` admits the edge, 04 §6.3), `session_home()`, `gptr_usage()`, `usage_add()`, `usage_conform()` (tests); Task 1 `oauth_need()`, `rand_hex()`; Suggests httpuv (`startServer()`, `stopServer()`, the server's `getHost()`), later, openssl; `rlang::new_weakref()`, `rlang::wref_key()`.
- Produces: the export of 04 §6.3 `gptr_mcp_serve(tools = c("r", "read", "edit", "write"), envir = parent.frame(), port = NULL, stop = FALSE)` -> a `gptr_mcp_handle` environment (`url` = `"http://127.0.0.1:<port>/mcp"`, `port`, `token_env` = `"GPTR_MCP_TOKEN"`, `token` (the `gptr_secret` handle of the bearer token, never its value; ambiguity 3), `config` (snippets of class `gptr_mcp_snippet`, each with a tool timeout of 3,600 s: `codex` is a list, `args` = the `-c` overrides of the server URL, `bearer_token_env_var=GPTR_MCP_TOKEN` and `tool_timeout_sec=3600`, and `env` = `c(GPTR_MCP_TOKEN = <token value>)`, marked secret; `claude_code`, `claude_desktop` and `cursor` are JSON text carrying the bearer header, marked secret), `stop()`), or `invisible(NULL)` with `stop = TRUE`; the user's token is bound to a dedicated session that `mcp_serve_session(envir)` creates with `session_new()` (`kind = "chat"`, no parent, home `envir`, the `mode` setting at start, the `model` setting or the placeholder `"mcp/serve"`), held as `the$mcp_server$user = list(key = <sha256 of the user's token>, session)` and released by `stop()`; its live record's `mcp_token` is the handle's token (ambiguity 1); emits `mcp_serve_start`/`mcp_serve_stop` (`url`); adds a `mcp_serve` row to P04's job table. The service `mcp.serve_ensure` = `mcp_serve_ensure(session)` (`session`: a `gptr_session`, as P20's `pcli_codex_ensure(ctx$session)` (called by builtin:cli's `request_params` hook before each Codex request) and P19's `cli` backend pass it, or its id, resolved by Task 7's `mcp_session_resolve()`) -> a `gptr_mcp_handle` whose token is bound to `session`; every call for the same session returns the same token, with its value in `h$config$codex$env[[h$token_env]]` (P20's `pcli_codex_env(h)` reads exactly that; `pcli_codex_ensure()` keeps url, port and that value per session id, and the adapter reads the record back by `opts$session` through `pcli_codex_mcp(opts)` and passes `c(GPTR_MCP_TOKEN = <value>)` as its `start$env`, which P05 hands to `child_env("cli-codex", set = )`; P19's `cli` backend calls the service once before the child's first run; `child_env(set = list(GPTR_MCP_TOKEN = h$token))` with the handle works as well); `h$stop()` revokes that token only. Internal `mcp_serve_token(session)` (04 §7.18; reuses a live token, returning its value from the vault, and revokes it at the session's `session_shutdown`; records the handle as `session_live(session)$mcp_token`), `mcp_token_new(st, session, tools)` (every token is bound to a session), `mcp_token_revoke(id)`, `mcp_token_lookup(authorization)` (the record plus its `key`), `mcp_serve_session(envir)`, `mcp_serve_start(port = NULL)`, `mcp_serve_stop()`, `mcp_serve_busy(rec)`, `mcp_http_handle(st, req)`; S3 methods `print.gptr_mcp_handle()` and `print.gptr_mcp_snippet()` (the token is shown as `[secret:GPTR_MCP_TOKEN]`); test helpers `mcp_test_post(url, msg, token = NULL, headers = list(), timeout = 20)` and `mcp_cli_child(url, token, msgs, timeout = 60)` (`token`: a token handle, or the value P20 takes from the Codex snippet).

Report 16 §5.9 (the in-process httpuv server, verified with 11 requests: 401, 403, 405, `-32020`) and report 08 (Codex's in-session HTTP MCP route), with the review amendments: one listening socket per process with a separate 192-bit token per client (IC-58), stored only as `sha256(token)` -> session id in `the$mcp_tokens` and registered in the vault, so the value never appears in a log, print or snapshot; a request is routed by its token to its session, so a fork's CLI child evaluates in the fork's overlay and a plan-mode parent's child is gated in plan mode; the user's token is routed the same way to the dedicated session of `gptr_mcp_serve()` (IC-58: "The explicit user handle keeps its dedicated session"), whose `ctx` (mode, rules, policies) gates the call and whose kept home is `envir`, with `the$mcp_server$envir` as the fallback when `envir` is a function frame P06 keeps no home for (R2). The path must be `/mcp`; a foreign `Origin` (anything but `http://127.0.0.1:<port>` or `http://localhost:<port>`) is 403; a missing or unknown bearer token is 401 with `WWW-Authenticate: Bearer error="invalid_token"`; GET and DELETE are 405 (DELETE ends a legacy session); a modern request whose headers disagree with its `_meta` is 400 / `-32020`; legacy clients get an `Mcp-Session-Id` that carries no state. httpuv handlers run only through P04's `later::run_now(0)` (the outermost pump, or a nested pump serving a CLI child's run, IC-57); a `tools/call` arriving in a nested pump whose `allow_runs` does not include the token's run, or on the user's token (its dedicated session never runs), gets `-32002` "gptr is busy; retry". Acceptance check 7 note: the CLI adapters belong to P20, so the fork and plan-mode checks use a stand-in CLI child (`fixtures/mcp/client.R`) carrying a session-bound token from `mcp.serve_ensure`; P20 tests the real CLI leg.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/mcp/client.R`:

```r
# A stand-in for a CLI child of gptr (Codex speaking Streamable HTTP MCP): it reads its bearer
# token from GPTR_MCP_TOKEN, POSTs each JSON-RPC message given on the command line to the URL
# and prints one JSON line per response: {"status": <int>, "body": <text>}.
# Usage: Rscript --vanilla client.R <url> <json> [<json> ...]
args = commandArgs(trailingOnly = TRUE)
url = args[1L]
token = Sys.getenv("GPTR_MCP_TOKEN")
session = NULL
for (body in args[-1L]) {
  msg = jsonlite::fromJSON(body, simplifyVector = FALSE)
  h = curl::new_handle(followlocation = FALSE)
  hdr = list(`Content-Type` = "application/json", Accept = "application/json, text/event-stream",
             Authorization = paste("Bearer", token))
  ver = msg$params[["_meta"]][["io.modelcontextprotocol/protocolVersion"]]
  if (!is.null(ver)) {
    hdr[["MCP-Protocol-Version"]] = ver
    hdr[["Mcp-Method"]] = msg$method
  }
  if (!is.null(session)) hdr[["Mcp-Session-Id"]] = session
  curl::handle_setheaders(h, .list = hdr)
  curl::handle_setopt(h, copypostfields = body)
  r = tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) NULL)
  if (is.null(r)) {
    cat(jsonlite::toJSON(list(status = 0L, body = ""), auto_unbox = TRUE), "\n", sep = "")
    next
  }
  sid = curl::parse_headers_list(r$headers)[["mcp-session-id"]]
  if (!is.null(sid)) session = sid
  out = list(status = r$status_code, body = rawToChar(r$content))
  cat(jsonlite::toJSON(out, auto_unbox = TRUE), "\n", sep = "")
}
```

Append to the end of `tests/testthat/helper-mcp-server.R`:

```r
# One HTTP POST to a gptr server from this process, through the reactor (its outermost pump
# services httpuv with later::run_now(0), IC-57): list(status, body, json, headers)
mcp_test_post = function(url, msg, token = NULL, headers = list(), timeout = 20) {
  st = new.env(parent = emptyenv())
  st$done = FALSE
  st$chunks = list()
  st$status = NA_integer_
  h = c(list(`Content-Type` = "application/json",
             Accept = "application/json, text/event-stream"), headers)
  if (!is.null(token)) h$Authorization = list("Bearer ", token)
  ver = if (is.list(msg)) msg$params[["_meta"]][["io.modelcontextprotocol/protocolVersion"]]
  if (!is.null(ver)) {
    h[["MCP-Protocol-Version"]] = h[["MCP-Protocol-Version"]] %||% ver
    h[["Mcp-Method"]] = h[["Mcp-Method"]] %||% msg$method
  }
  body = if (is.character(msg)) msg else json_encode(msg)
  reactor_http(list(url = url, method = "POST", headers = h, body = body),
               on_bytes = function(raw) st$chunks[[length(st$chunks) + 1L]] = raw,
               on_done = function(status, hd) {
                 st$status = status
                 st$headers = hd
                 st$done = TRUE
               },
               on_fail = function(cnd) {
                 st$status = cnd$status
                 st$done = TRUE
               },
               retry = list(max_attempts = 1L))
  reactor_pump(until = function() isTRUE(st$done), timeout = timeout)
  txt = if (length(st$chunks)) rawToChar(do.call(c, st$chunks)) else ""
  list(status = as.integer(st$status), body = txt,
       json = if (nzchar(txt)) jsonlite::fromJSON(txt, simplifyVector = FALSE),
       headers = st$headers)
}

# A stand-in CLI child of a session (fixtures/mcp/client.R): a separate R process whose
# environment carries GPTR_MCP_TOKEN (child_env(), IC-58; `token` is the handle's token handle,
# or the value of its Codex snippet as P20 passes it) posts `msgs` to `url` while this process
# pumps the reactor; returns one list(status, body) per message
mcp_cli_child = function(url, token, msgs, timeout = 60) {
  env = child_env("mcp", set = list(GPTR_MCP_TOKEN = token, R_LIBS = mcp_fixture_libs()))
  bodies = vapply(msgs, json_encode, "")
  p = proc_spawn(rscript_path(), c("--vanilla", file.path(mcp_fixture_dir, "client.R"), url,
                                   bodies), env = env, stdin = NULL, stdout = "|", stderr = "|")
  on.exit(kill_all(p, grace = 0), add = TRUE)
  got = new.env(parent = emptyenv())
  got$lines = character()
  reactor_pump(until = function() {
    got$lines = c(got$lines, p$read_output_lines())
    !p$is_alive()
  }, timeout = timeout)
  lines = c(got$lines, p$read_output_lines())
  lapply(lines[nzchar(lines)], function(l) jsonlite::fromJSON(l, simplifyVector = FALSE))
}
```

Append to the end of `tests/testthat/test-mcp-server.R`:

```r
skip_without_server = function() {
  skip_on_cran()
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  skip_if_not_installed("openssl")
}

test_that("gptr_mcp_serve() binds 127.0.0.1, needs the token, checks Origin and keeps the seed", {
  skip_without_server()
  e = new.env()
  e$d = mtcars
  withr::local_seed(7)
  seed = get(".Random.seed", envir = globalenv())
  h = gptr_mcp_serve(envir = e)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
  expect_s3_class(h, "gptr_mcp_handle")
  expect_match(h$url, "^http://127\\.0\\.0\\.1:[0-9]+/mcp$")
  expect_identical(the$mcp_server$srv$getHost(), "127.0.0.1")
  expect_identical(h$token_env, "GPTR_MCP_TOKEN")
  expect_s3_class(h$token, "gptr_secret")
  expect_identical(gptr_mcp_serve(envir = e), h)
  expect_true("mcp_serve" %in% job_list()$kind)
  lst = mcp_test_msg("tools/list")
  expect_identical(mcp_test_post(h$url, lst)$status, 401L)
  expect_identical(mcp_test_post(h$url, lst, token = "wrong-token")$status, 401L)
  evil = mcp_test_post(h$url, lst, token = h$token, headers = list(Origin = "http://evil.example"))
  expect_identical(evil$status, 403L)
  ok = mcp_test_post(h$url, lst, token = h$token,
                     headers = list(Origin = paste0("http://localhost:", h$port)))
  expect_identical(ok$status, 200L)
  expect_identical(vapply(ok$json$result$tools, `[[`, "", "name"), c("r", "read", "edit", "write"))
  bad_hdr = mcp_test_post(h$url, lst, token = h$token, headers = list(`Mcp-Method` = "tools/call"))
  expect_identical(bad_hdr$status, 400L)
  req = list(PATH_INFO = "/mcp", REQUEST_METHOD = "POST",
             HTTP_AUTHORIZATION = paste("Bearer", secret_value(h$token, h$url)),
             HTTP_MCP_PROTOCOL_VERSION = "2026-07-28", HTTP_MCP_METHOD = "tools/call",
             rook.input = list(read = function() charToRaw(json_encode(lst))))
  expect_identical(json_decode(mcp_http_handle(the$mcp_server, req)$body)$error$code, -32020L)
  req$REQUEST_METHOD = "GET"
  expect_identical(mcp_http_handle(the$mcp_server, req)$status, 405L)
  expect_identical(get(".Random.seed", envir = globalenv()), seed)
})

test_that("an r call through the server is gated: read-only runs, writes wait for permission", {
  skip_without_server()
  e = new.env()
  e$d = mtcars
  h = gptr_mcp_serve(envir = e)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  call = function(code) mcp_test_post(h$url, r_call(code), token = h$token)$json$result
  res = call("nrow(d)")
  expect_false(res$isError)
  expect_match(res$content[[1L]]$text, "32", fixed = TRUE)
  res = call("x = 1")
  expect_true(res$isError)
  expect_match(res$content[[1L]]$text, "Permission denied", fixed = TRUE)
  expect_false(exists("x", envir = e, inherits = FALSE))
  # the dedicated session keeps the mode it started with, like any session (IC-58): a new mode
  # setting applies once the server is started again
  local_gptr_options(mode = "auto")
  expect_true(call("x = 1")$isError)
  gptr_mcp_serve(stop = TRUE)
  h = gptr_mcp_serve(envir = e)
  expect_identical(session_data(the$mcp_server$user$session)$mode, "auto")
  expect_false(call("x = 1")$isError)
  expect_identical(e$x, 1)
})

test_that("the user's token has a dedicated chat session; its usage stays its own (IC-58)", {
  skip_without_server()
  x = local_served_session("auto")
  own = gptr_usage(x$session)
  e = new.env()
  h = gptr_mcp_serve(envir = e)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  st = the$mcp_server
  s = st$user$session
  d = session_data(s)
  expect_s3_class(s, "gptr_session")
  expect_identical(list(d$kind, d$mode, d$parent_id), list("chat", "manual", NULL))
  expect_identical(session_home(s), e)
  expect_identical(session_live(s)$mcp_token, h$token)
  bearer = paste("Bearer", secret_value(h$token, h$url))
  rec = mcp_token_lookup(bearer)
  expect_identical(c(rec$id, rec$key), c(d$id, st$user$key))
  # the dedicated session's manual mode gates the user's token, not the auto mode of x's session
  res = mcp_test_post(h$url, r_call("w = 1"), token = h$token)$json$result
  expect_true(res$isError)
  expect_false(exists("w", envir = e, inherits = FALSE))
  # served r, read, edit and write calls send no model request; a request charged to the
  # dedicated session (top-level, no parent) rolls up to it alone (P06's usage_add(), IC-66),
  # never to the session the user was working in
  usage_add(s, usage_conform(data.frame(request_id = "mcp-q1", session = d$id, agent = "main",
                                        provider = "fake", model = "fake-1", route = "api",
                                        input = 100, cost = 0.5, stringsAsFactors = FALSE)))
  expect_identical(attr(gptr_usage(s), "totals")[["requests"]], 1)
  expect_true(d$id %in% gptr_usage()$group)
  expect_identical(gptr_usage(x$session), own)
  gptr_mcp_serve(stop = TRUE)
  expect_null(st$user)
  expect_null(mcp_token_lookup(bearer))
})

test_that("both client eras work against gptr's own server, legacy sessions included", {
  skip_without_server()
  e = new.env()
  local_gptr_options(mode = "auto")
  h = gptr_mcp_serve(envir = e)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  bearer = paste("Bearer", secret_value(h$token, h$url))
  for (era in c("modern", "legacy")) {
    spec = list(name = paste0("self_", era), transport = "http", url = h$url, protocol = era,
                headers = list(Authorization = bearer))
    conn = mcp_connect(spec)
    expect_identical(conn$era, era)
    expect_identical(vapply(mcp_tools(conn), function(t) t$name, ""),
                     c("r", "read", "edit", "write"))
    res = mcp_call(conn, "r", list(code = paste0("v_", era, " = 2 * 21")))
    expect_false(res$is_error)
    mcp_close(conn)
  }
  expect_identical(e$v_modern, 42)
  expect_identical(e$v_legacy, 42)
  expect_identical(ls(the$mcp_server$legacy), character())
})

test_that("a CLI child's token evaluates in its fork's overlay (IC-58)", {
  skip_without_server()
  x = local_served_session("auto")
  f = gptr_fork(x$session)
  h = ext_service_get("mcp.serve_ensure")(f)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  expect_s3_class(h, "gptr_mcp_handle")
  expect_identical(session_live(f)$mcp_token, h$token)
  # P20's request_params hook calls the service with the session object before every codex
  # request (pcli_codex_ensure(ctx$session)) and puts the value of the Codex snippet's env into
  # the child's environment; an id (contract 8.1) resolves to the same session: every call gives
  # the same usable token
  again = ext_service_get("mcp.serve_ensure")(f)
  by_id = ext_service_get("mcp.serve_ensure")(session_data(f)$id)
  expect_identical(list(again$token, by_id$token), list(h$token, h$token))
  expect_error(ext_service_get("mcp.serve_ensure")("no-such-session"),
               class = "gptr_error_invalid_argument")
  value = again$config$codex$env[[again$token_env]]
  expect_identical(value, secret_value(h$token, h$url))
  out = mcp_cli_child(h$url, value, list(r_call("y_child = 42", id = 1L),
                                         r_call("exists('d')", id = 2L)))
  expect_identical(vapply(out, function(o) o$status, 0L), c(200L, 200L))
  expect_false(jsonlite::fromJSON(out[[1L]]$body, simplifyVector = FALSE)$result$isError)
  expect_identical(get("y_child", envir = session_home(f), inherits = FALSE), 42)
  expect_false(exists("y_child", envir = x$envir, inherits = FALSE))
  h$stop()
  expect_identical(mcp_test_post(h$url, r_call("1"), token = h$token)$status, 401L)
})

test_that("a CLI child of a plan-mode parent is gated in plan mode", {
  skip_without_server()
  x = local_served_session("plan")
  # by id (contract 8.1 gives L1 adapters only ids; P18 accepts one beside the session object
  # that P20's request_params hook and P19's cli backend pass)
  h = ext_service_get("mcp.serve_ensure")(session_data(x$session)$id)
  withr::defer(gptr_mcp_serve(stop = TRUE))
  out = mcp_cli_child(h$url, h$token, list(r_call("saveRDS(d, 'd.rds')", id = 1L),
                                           r_call("nrow(d)", id = 2L),
                                           r_call("z = 1", id = 3L)))
  body = lapply(out, function(o) jsonlite::fromJSON(o$body, simplifyVector = FALSE)$result)
  expect_true(all(vapply(body, function(b) isTRUE(b$isError), NA)))
  expect_match(body[[1L]]$content[[1L]]$text, "plan mode", fixed = TRUE)
  expect_false(file.exists("d.rds"))
  # at an idle console a plan-mode session has no run, hence no scratch overlay (IC-15): P11's
  # plan policy refuses every r call then
  expect_match(body[[2L]]$content[[1L]]$text, "plan mode needs a scratch environment",
               fixed = TRUE)
  expect_false(exists("z", envir = x$envir, inherits = FALSE))
})

test_that("in a nested pump only the runs it serves are answered; others get -32002 (IC-57)", {
  skip_without_server()
  x = local_served_session("auto")
  h = ext_service_get("mcp.serve_ensure")(x$session)
  user = gptr_mcp_serve(envir = new.env())
  withr::defer(gptr_mcp_serve(stop = TRUE))
  rec_user = mcp_token_lookup(paste("Bearer", secret_value(user$token, user$url)))
  rec_s = mcp_token_lookup(paste("Bearer", secret_value(h$token, h$url)))
  expect_false(mcp_serve_busy(rec_user))
  local_mocked_bindings(reactor_allow_runs = function() "u00000000")
  expect_true(mcp_serve_busy(rec_user))
  expect_true(mcp_serve_busy(rec_s))
  req = list(PATH_INFO = "/mcp", REQUEST_METHOD = "POST",
             HTTP_AUTHORIZATION = paste("Bearer", secret_value(h$token, h$url)),
             HTTP_MCP_PROTOCOL_VERSION = "2026-07-28", HTTP_MCP_METHOD = "tools/call",
             rook.input = list(read = function() charToRaw(json_encode(r_call("1")))))
  res = mcp_http_handle(the$mcp_server, req)
  expect_identical(res$status, 200L)
  expect_identical(json_decode(res$body)$error$code, -32002L)
})

test_that("client snippets carry a 3,600 s tool timeout and print without the token", {
  skip_without_server()
  h = gptr_mcp_serve(envir = new.env())
  withr::defer(gptr_mcp_serve(stop = TRUE))
  expect_setequal(names(h$config), c("codex", "claude_code", "claude_desktop", "cursor"))
  value = secret_value(h$token, h$url)
  expect_true("mcp_servers.gptr.tool_timeout_sec=3600" %in% h$config$codex$args)
  expect_true("mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN" %in% h$config$codex$args)
  expect_identical(h$config$codex$env[[h$token_env]], value)
  expect_identical(json_decode(h$config$claude_code)$mcpServers$gptr$timeout, 3600000L)
  expect_true(grepl(value, as.character(h$config$cursor), fixed = TRUE))
  shown = paste(cli::cli_fmt(print(h$config$cursor)), collapse = "\n")
  expect_false(grepl(value, shown, fixed = TRUE))
  expect_match(shown, "Bearer [secret:GPTR_MCP_TOKEN]", fixed = TRUE)
  shown = paste(cli::cli_fmt(print(h$config$codex)), collapse = "\n")
  expect_false(grepl(value, shown, fixed = TRUE))
  expect_match(shown, "GPTR_MCP_TOKEN=[secret:GPTR_MCP_TOKEN]", fixed = TRUE)
  shown = paste(cli::cli_fmt(print(h)), collapse = "\n")
  expect_match(shown, "<gptr MCP server> http://127.0.0.1:", fixed = TRUE)
  expect_false(grepl(value, shown, fixed = TRUE))
  expect_null(gptr_mcp_serve(stop = TRUE))
  expect_null(the$mcp_server)
  expect_false("mcp_serve" %in% job_list()$kind)
})

test_that("gptr_mcp_serve() validates its arguments and is refused from model code", {
  expect_error(gptr_mcp_serve(tools = "bash"), class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_serve(envir = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_mcp_serve(port = 0), class = "gptr_error_invalid_argument")
  local_mocked_bindings(ext_control_guard = function(what) {
    gptr_abort("refused", "permission", action = what, tool = "r", risk = 4L,
               how_to_allow = "run it yourself", session = NULL)
  })
  expect_error(gptr_mcp_serve(envir = new.env()), class = "gptr_error_permission")
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-server")'`
Expected: `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 38 ]`; the first error is `could not find function "gptr_mcp_serve"`.

- [ ] **Step 3: Write the implementation**

Append to the end of `R/mcp-server.R`:

```r
# ---- bearer tokens (IC-58) -------------------------------------------------------------------

#' The token table `the$mcp_tokens`: sha256(token) -> list(id (session id), ref (weak reference
#' to the session), handle, tools); never a token value. Every token is bound to a session: a CLI
#' child's (mcp.serve_ensure) or the dedicated session of gptr_mcp_serve() (IC-58)
#' @noRd
mcp_tokens_env = function() {
  x = the$mcp_tokens
  if (is.null(x)) {
    x = new.env(parent = emptyenv())
    the$mcp_tokens = x
  }
  x
}

#' Issue a 192-bit bearer token (openssl::rand_bytes(24), hex) bound to `session`. The value is
#' registered as a secret bound to the server's origin; only its sha256 is kept.
#' @noRd
mcp_token_new = function(st, session, tools = mcp_default_tools()) {
  value = rand_hex(24L)
  handle = secret_register(value, "GPTR_MCP_TOKEN", source = "mcp_serve",
                           origin = url_origin(st$url))
  key = hash_sha256(value)
  rec = list(id = session_data(session)$id, ref = rlang::new_weakref(session), handle = handle,
             tools = tools)
  assign(key, rec, envir = mcp_tokens_env())
  list(value = value, handle = handle, key = key)
}

#' Revoke every token bound to a session id
#' @noRd
mcp_token_revoke = function(id) {
  env = mcp_tokens_env()
  for (k in ls(env)) if (identical(get(k, envir = env)$id, id)) rm(list = k, envir = env)
  invisible(NULL)
}

#' The token record behind an Authorization header, plus its `key` (the sha256 of the token), or
#' NULL (a token whose session was collected is no longer valid)
#' @noRd
mcp_token_lookup = function(authorization) {
  if (!is.character(authorization) || length(authorization) != 1L ||
        !startsWith(authorization, "Bearer ")) {
    return(NULL)
  }
  key = hash_sha256(substring(authorization, 8L))
  rec = get0(key, envir = mcp_tokens_env(), inherits = FALSE)
  if (is.null(rec) || is.null(rlang::wref_key(rec$ref))) return(NULL)
  rec$key = key
  rec
}

#' A bearer token bound to `session` on the shared server (contract 7.18): reused while valid,
#' kept as a handle in the session's live record (`mcp_token`, contract 5.1) and revoked at the
#' session's shutdown or through the stop() of the handle mcp.serve_ensure returns. A reused
#' token's value comes back from the vault for the server's own origin: P20's request_params
#' hook calls the service before every codex request (pcli_codex_ensure()) and reads the value
#' from the handle's `config$codex$env` (pcli_codex_env())
#' @noRd
mcp_serve_token = function(session) {
  st = the$mcp_server
  sid = session_data(session)$id
  env = mcp_tokens_env()
  for (k in ls(env)) {
    rec = get(k, envir = env)
    if (identical(rec$id, sid)) {
      return(list(handle = rec$handle, key = k, value = secret_value(rec$handle, st$url)))
    }
  }
  tok = mcp_token_new(st, session, mcp_default_tools())
  hook_add("session_shutdown", function(event, ctx) mcp_token_revoke(sid), rank = 0L,
           source = "session", session = sid)
  live = session_live(session)
  if (!is.null(live)) live$mcp_token = tok$handle
  tok
}

# ---- the loopback HTTP server ------------------------------------------------------------------

#' httpuv, later and openssl, loaded with the seed preserved (gptr_error_missing_package)
#' @noRd
mcp_serve_need = function() {
  for (p in c("httpuv", "later", "openssl")) oauth_need(p, "The MCP server")
  invisible(TRUE)
}

#' The listening socket (one per process, IC-58): 127.0.0.1 on a port from port_candidates()
#' (never httpuv::randomPort(), IC-61), started with the seed preserved, recorded in the job table
#' @noRd
mcp_serve_start = function(port = NULL) {
  st = the$mcp_server
  if (!is.null(st)) return(st)
  mcp_serve_need()
  st = new.env(parent = emptyenv())
  st$legacy = new.env(parent = emptyenv())
  st$envir = NULL
  st$tools = mcp_default_tools()
  st$user = NULL
  st$handle = NULL
  app = list(call = function(req) mcp_http_handle(st, req))
  ports = if (is.null(port)) port_candidates(20L) else as.integer(port)
  srv = NULL
  with_seed_preserved({
    for (p in ports) {
      srv = tryCatch(httpuv::startServer("127.0.0.1", p, app), error = function(e) NULL)
      if (!is.null(srv)) {
        st$port = as.integer(p)
        break
      }
    }
  })
  if (is.null(srv)) {
    gptr_abort("Could not open a local port for the MCP server.", "spawn",
               command = "httpuv::startServer")
  }
  st$srv = srv
  st$url = paste0("http://127.0.0.1:", st$port, "/mcp")
  st$job = paste0("mcp-serve-", st$port)
  job_add("mcp_serve", st$job, paste("MCP server", st$url), pid = Sys.getpid(),
          stop = function() mcp_serve_stop())
  the$mcp_server = st
  ev_dispatch("mcp_serve_start", list(url = st$url))
  st
}

#' Stop the server: revoke every token and release the served environment and the dedicated
#' session (R2)
#' @noRd
mcp_serve_stop = function() {
  st = the$mcp_server
  if (is.null(st)) return(invisible(FALSE))
  the$mcp_server = NULL
  with_seed_preserved(try(httpuv::stopServer(st$srv), silent = TRUE))
  env = mcp_tokens_env()
  rm(list = ls(env), envir = env)
  st$envir = NULL
  st$user = NULL
  st$handle = NULL
  try(job_remove(st$job), silent = TRUE)
  ev_dispatch("mcp_serve_stop", list(url = st$url))
  invisible(TRUE)
}

#' An HTTP response for httpuv
#' @noRd
mcp_http_resp = function(status, body = "", headers = list()) {
  list(status = as.integer(status), headers = c(list(`Content-Type` = "application/json"), headers),
       body = body)
}

#' The busy rule of IC-57: inside a nested pump (a tool of some run is waiting) only requests of
#' the runs that pump serves are answered; others, and requests on the user's token (whose
#' dedicated session never runs), get the retryable JSON-RPC error -32002
#' @noRd
mcp_serve_busy = function(rec) {
  allow = reactor_allow_runs()
  if (is.null(allow)) return(FALSE)
  s = rlang::wref_key(rec$ref)
  live = if (is.null(s)) NULL else session_live(s)
  run = if (is.null(live)) NULL else live$run
  is.null(run) || !(run$id %in% allow)
}

#' The httpuv handler; never throws into httpuv
#' @noRd
mcp_http_handle = function(st, req) {
  tryCatch(mcp_http_route(st, req), error = function(e) {
    mcp_http_resp(500L, "{\"error\":\"internal error\"}")
  })
}

#' Route one HTTP request: path (404), Origin (403), bearer token (401), method (405), the era
#' headers, legacy sessions, the busy rule, then the dispatcher
#' @noRd
mcp_http_route = function(st, req) {
  h = function(name) req[[paste0("HTTP_", toupper(gsub("-", "_", name)))]]
  if (!identical(req$PATH_INFO, "/mcp")) return(mcp_http_resp(404L))
  origin = h("Origin")
  allowed = c(paste0("http://127.0.0.1:", st$port), paste0("http://localhost:", st$port))
  if (!is.null(origin) && !origin %in% allowed) {
    return(mcp_http_resp(403L, "{\"error\":\"forbidden origin\"}"))
  }
  rec = mcp_token_lookup(h("Authorization"))
  if (is.null(rec)) {
    return(mcp_http_resp(401L, "{\"error\":\"invalid_token\"}",
                         list(`WWW-Authenticate` = "Bearer error=\"invalid_token\"")))
  }
  if (!identical(req$REQUEST_METHOD, "POST")) {
    sid = h("Mcp-Session-Id")
    if (identical(req$REQUEST_METHOD, "DELETE") && !is.null(sid) &&
          exists(sid, envir = st$legacy, inherits = FALSE)) {
      rm(list = sid, envir = st$legacy)
      return(mcp_http_resp(200L))
    }
    return(mcp_http_resp(405L, "", list(Allow = "POST")))
  }
  msg = tryCatch(json_decode(raw_to_utf8(req$rook.input$read())), error = function(e) NULL)
  if (!is.list(msg) || is.null(names(msg))) {
    return(mcp_http_resp(400L, mcp_json(mcp_rpc_err(NULL, -32700L, "Parse error"))))
  }
  # every token is bound to a session (IC-58); the user's token (st$user$key) also falls back to
  # the environment gptr_mcp_serve() holds when its dedicated session keeps no home (R2)
  target = list(session = rlang::wref_key(rec$ref), tools = rec$tools)
  if (identical(rec$key, st$user$key)) target$envir = function() st$envir
  extra = list()
  meta_ver = msg$params[["_meta"]][[mcp_k_ver]]
  if (!is.null(meta_ver)) {
    same = identical(h("MCP-Protocol-Version"), meta_ver) && identical(h("Mcp-Method"), msg$method)
    if (!same) {
      return(mcp_http_resp(400L, mcp_json(mcp_rpc_err(msg$id, -32020L, "Header mismatch"))))
    }
  } else if (identical(msg$method, "initialize")) {
    sid = rand_hex(16L)
    assign(sid, TRUE, envir = st$legacy)
    extra = list(`Mcp-Session-Id` = sid)
  } else {
    sid = h("Mcp-Session-Id")
    if (is.null(sid)) {
      return(mcp_http_resp(400L, mcp_json(mcp_rpc_err(msg$id, -32600L, paste(
        "Missing Mcp-Session-Id: send initialize first, or use the 2026-07-28 _meta fields")))))
    }
    if (!exists(sid, envir = st$legacy, inherits = FALSE)) return(mcp_http_resp(404L))
  }
  if (is.null(msg$id)) return(mcp_http_resp(202L))
  if (identical(msg$method, "tools/call") && mcp_serve_busy(rec)) {
    return(mcp_http_resp(200L, mcp_json(mcp_rpc_err(msg$id, -32002L, "gptr is busy; retry"))))
  }
  mcp_http_resp(200L, mcp_json(mcp_dispatch(msg, target)), extra)
}

# ---- handles, snippets and the exported server -------------------------------------------------

#' A client snippet (text, or for Codex a list of `args` and `env`); snippets carrying a token
#' print redacted
#' @noRd
mcp_snippet = function(x, secret) {
  base = if (is.list(x)) "list" else "character"
  if (!is.list(x)) x = as.character(x)
  structure(x, class = c("gptr_mcp_snippet", base), secret = isTRUE(secret))
}

#' Client snippets for Codex, Claude Code, Claude Desktop and Cursor, each with a tool timeout of
#' at least 3,600 s (HTTP MCP clients apply a 60 s per-request timer, 07 fact-check). The Codex
#' snippet is a list: `args` (the `-c` overrides, which read the token from GPTR_MCP_TOKEN) and
#' `env` (`c(GPTR_MCP_TOKEN = <token>)`, the child's environment; P20's pcli_codex_env() reads
#' `config$codex$env[[token_env]]`), marked secret (contract 6.3)
#' @noRd
mcp_client_snippets = function(url, token) {
  bearer = paste("Bearer", token)
  obj = function(x) json_encode(list(mcpServers = list(gptr = x)), pretty = TRUE)
  list(
    codex = mcp_snippet(list(args = c("-c", paste0("mcp_servers.gptr.url=", url), "-c",
                                      "mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN",
                                      "-c", "mcp_servers.gptr.tool_timeout_sec=3600"),
                             env = c(GPTR_MCP_TOKEN = token)), secret = TRUE),
    claude_code = mcp_snippet(obj(list(type = "http", url = url,
                                       headers = list(Authorization = bearer), timeout = 3600000L)),
                              secret = TRUE),
    claude_desktop = mcp_snippet(obj(list(command = "npx",
                                          args = I(c("-y", "mcp-remote", url, "--header",
                                                     paste0("Authorization: ", bearer))),
                                          timeout = 3600000L)), secret = TRUE),
    cursor = mcp_snippet(obj(list(url = url, headers = list(Authorization = bearer),
                                  timeout = 3600000L)), secret = TRUE))
}

#' A `gptr_mcp_handle` (contract 5.11): url, port, token_env, config and stop(), plus `token`,
#' the `gptr_secret` handle of the bearer token bound to the server's origin (never its value),
#' for child_env(set = list(GPTR_MCP_TOKEN = h$token)) (plan ambiguity 3); the value itself is
#' only in the secret snippets of `config` (`config$codex$env` for the CLI routes, contract 6.3)
#' @noRd
mcp_handle_new = function(st, tok, stop_fun) {
  h = new.env(parent = emptyenv())
  h$url = st$url
  h$port = st$port
  h$token_env = "GPTR_MCP_TOKEN"
  h$token = tok$handle
  h$config = mcp_client_snippets(st$url, tok$value)
  h$stop = stop_fun
  class(h) = "gptr_mcp_handle"
  h
}

#' The dedicated session of gptr_mcp_serve() (contract 6.3, IC-58): `kind = "chat"`, no parent,
#' home `envir` (P06 keeps no function frame as a home, R2; the HTTP route then falls back to
#' `the$mcp_server$envir`), the permission mode of the `mode` setting now and the `model` setting
#' (else a placeholder: the session never sends a request). P01's arch_contract_edges() admits
#' this mcp -> session_new() edge (04 6.3); like every top-level session it becomes gptr_last()
#' @noRd
mcp_serve_session = function(envir) {
  model = setting_get("model") %||% "mcp/serve"
  session_new(model, setting_get("mode", default = "manual"), home = envir, kind = "chat")
}

#' Serve the live R session to other agents over MCP
#'
#' Starts an MCP server inside this R session that offers `r`, `read`, `edit` and `write` to
#' agents such as Codex, Claude Code, Claude Desktop or Cursor. It listens only on 127.0.0.1,
#' on a free port, requires a 192-bit bearer token, rejects foreign browser origins, and runs
#' every call through your permission settings; R code evaluates in `envir`, where its objects
#' persist. The calls belong to a dedicated gptr session whose permission mode is the one in
#' effect when the server starts (stop and start the server to change it); like any new
#' session, it becomes [gptr_last()]. Requests are answered while R waits at the console or
#' inside a gptr call; one that needs your approval is refused with a note on how to allow it,
#' because gptr never asks from a background callback. The token appears only in the snippets
#' of `$config` (printed redacted; `as.character()` gives the text to paste; `$config$codex`
#' holds the `codex` options in `$args` and the environment to start Codex with in `$env`) and
#' in the environment of children gptr starts. One server runs per R process. Needs 'httpuv',
#' 'later' and 'openssl'.
#'
#' @param tools The tools to serve: a subset of `c("r", "read", "edit", "write")`.
#' @param envir Where served R code evaluates and its objects persist.
#' @param port A port, or `NULL` for a free one.
#' @param stop `TRUE` to stop the server.
#' @return A `gptr_mcp_handle` with `$url`, `$port`, `$token_env`, `$config` and `$stop()`;
#'   calling again returns the running handle; with `stop = TRUE`, `invisible(NULL)`.
#' @examplesIf interactive()
#' h = gptr_mcp_serve(envir = globalenv())
#' h$config$codex
#' gptr_mcp_serve(stop = TRUE)
#' @export
gptr_mcp_serve = function(tools = c("r", "read", "edit", "write"), envir = parent.frame(),
                          port = NULL, stop = FALSE) {
  check_strings(tools, "tools")
  if (!length(tools) || !all(tools %in% mcp_default_tools())) {
    gptr_abort("`tools` must be a subset of \"r\", \"read\", \"edit\" and \"write\".",
               "invalid_argument", arg = "tools", expected = "a subset of r, read, edit, write")
  }
  check_env(envir, "envir")
  port = check_number(port, "port", min = 1, max = 65535, int = TRUE, null = TRUE)
  stop = check_flag(stop, "stop")
  ext_control_guard("gptr_mcp_serve")
  if (stop) {
    mcp_serve_stop()
    return(invisible(NULL))
  }
  st = the$mcp_server
  if (!is.null(st) && !is.null(st$handle)) return(st$handle)
  st = mcp_serve_start(port)
  st$envir = envir
  st$tools = unique(tools)
  s = mcp_serve_session(envir)
  tok = mcp_token_new(st, s, st$tools)
  # the dedicated session, keyed by the sha256 of the user's token (never its value); held here
  # and released by stop() (R2)
  st$user = list(key = tok$key, session = s)
  live = session_live(s)
  live$mcp_token = tok$handle
  st$handle = mcp_handle_new(st, tok, function() mcp_serve_stop())
  st$handle
}

#' The `mcp.serve_ensure` service (contract 7.0, IC-58): the shared socket plus a token bound to
#' `session` (a CLI child's session, P19/P20); the handle's stop() revokes that token only
#' @noRd
mcp_serve_ensure = function(session) {
  session = mcp_session_resolve(session)
  mcp_session_remember(session)
  st = mcp_serve_start(NULL)
  tok = mcp_serve_token(session)
  sid = session_data(session)$id
  mcp_handle_new(st, tok, function() mcp_token_revoke(sid))
}

#' Print a server handle (never the token)
#'
#' @param x A `gptr_mcp_handle`.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_mcp_handle = function(x, ...) {
  msg_verbatim(c(paste0("<gptr MCP server> ", x$url),
                 paste0("token: in the environment variable ", x$token_env,
                        " of children gptr starts"),
                 paste0("config: ", paste(names(x$config), collapse = ", ")),
                 "stop: $stop() or gptr_mcp_serve(stop = TRUE)"))
  invisible(x)
}

#' Print a client snippet with its token redacted
#'
#' @param x A `gptr_mcp_snippet`.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_mcp_snippet = function(x, ...) {
  if (is.list(x)) {
    text = c(paste(x$args, collapse = " "), paste0(names(x$env), "=", unname(x$env)))
    note = "(the token is hidden; $args are the codex options, $env the child's environment)"
  } else {
    text = as.character(x)
    note = "(the token is hidden; as.character() gives the text to paste)"
  }
  msg_verbatim(redact(text, "persist"))
  if (isTRUE(attr(x, "secret"))) msg_verbatim(note)
  invisible(x)
}

on_load(ext_service_set("mcp.serve_ensure", mcp_serve_ensure, provided_by = "P18",
                        builtin = "mcp"))
on_load(on_unload(function() invisible(tryCatch(mcp_serve_stop(), error = function(e) FALSE))))
```

Then regenerate the documentation: `Rscript --vanilla -e 'devtools::document()'`. Expected: `NAMESPACE` gains `export(gptr_mcp_serve)`, `S3method(print,gptr_mcp_handle)` and `S3method(print,gptr_mcp_snippet)`; `man/gptr_mcp_serve.Rd` is written (the example runs only under `@examplesIf interactive()`, because it starts a server).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp-server")'`
Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 124 ]`

Then run every P18 test file together, with P01's lint and layering tests:

Run: `Rscript --vanilla -e 'devtools::test(filter = "mcp|auth-oauth|lint-rules|arch-layers")'`
Expected: no failure from a P18 file; the P18 files alone give `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 490 ]` (the skip is the Windows-only `.cmd` test), `test-lint-rules.R` passes and `test-arch-layers.R` reports no layering violation from `auth-oauth.R` or `mcp-*.R`.

- [ ] **Step 5: Commit**

```bash
git add R/mcp-server.R tests/testthat/test-mcp-server.R tests/testthat/helper-mcp-server.R tests/testthat/fixtures/mcp/client.R NAMESPACE man/gptr_mcp_serve.Rd
git commit -m "feat(mcp): add gptr_mcp_serve() and per-session tokens (mcp.serve_ensure)"
```


---

### Task 10: The NS-10 golden transcript (`dev/bench/tokens/`)

**Files:**
- Create: `dev/bench/tokens/fixtures/ns10-mcp-catalog.json`
- Modify: `dev/bench/tokens/baseline.csv` (one row added by P07's runner; IC-73 names this addition by P18)

**Interfaces:**
- Consumes (P07, IC-73): `Rscript --vanilla dev/bench/tokens/run.R [--check] [--update [ids]]` and its fixture format (`id`, `north_star`, `description`, `mode`, `human`, `preset`, `models`, `standins`, `environment`, `files`, `objects`, `facts`, `turns` with `prompt`, `source`, `context`, `steps` of `text` and `calls`); the runner redirects `R_USER_CONFIG_DIR`/`R_USER_CACHE_DIR` to `tempdir()`, writes each fixture's `files` into a fresh temporary project and evaluates each `objects` expression there before the prompt freezes; P08 `gptr_trust(path = ".", trust = NULL)`; Task 3's tool-cache format and key (`hash_sha256(canonical_json(list(url = <origin + path>)))`); rtiktoken (development tool, not a dependency).
- Produces: the fixture `ns10-mcp-catalog` and its baseline row (P24 gates every row: prefix +2%, input and output +5%, requests and image tokens +0, catalog +5%, facts no loss).

NS-10 (02 §10) asks for "skills, extensions, plugins, MCP"; P18's share is the cost of MCP in the prompt. The fixture runs `gptr("Find trials for this indication", indication)` in a project whose `.gptr/mcp.json` configures one ClinicalTrials-style HTTP server with 12 tools. P07's runner has no MCP hook, so the expression that creates `indication` also seeds the tool cache from the fixture file `.bench/trials-tools.json` and trusts the temporary project (the project, its trust record and the cache key are unique to this fixture, so no other golden transcript sees the server, and no server is ever contacted). The tools reach the model as 12 signature lines in the T1 `<mcp>` section (measured: 386 o200k tokens, header included) instead of 12 tool declarations, and the model answers with one composed `r` call that runs `gptr$mcp$trials$search_trials()` and filters the data frame it returns (S-12).

- [ ] **Step 1: Write the fixture**

Check the development tool first: `Rscript --vanilla -e 'cat(requireNamespace("rtiktoken", quietly = TRUE), "\n")'` must print `TRUE`. If it prints `FALSE`, stop and ask the maintainer to install rtiktoken (CRAN) into their library; do not install it from a plan step (conventions §1).

Create `dev/bench/tokens/fixtures/ns10-mcp-catalog.json`:

```json
{
  "id": "ns10-mcp-catalog",
  "north_star": 10,
  "description": "gptr(\"Find trials for this indication\", indication) in a trusted project whose .gptr/mcp.json configures a ClinicalTrials-style MCP server with 12 tools: the tools reach the model as R signatures in the T1 <mcp> catalog (no tool declarations), and one composed r call runs gptr$mcp$trials$search_trials() and filters the data frame it returns. The object expression of `indication` seeds the tool cache from .bench/trials-tools.json and trusts the temporary project, so no server is contacted.",
  "mode": "manual",
  "human": true,
  "preset": null,
  "models": [
    "benchmain/benchmain-1"
  ],
  "standins": [
    "artifacts",
    "system1",
    "skills",
    "r_env"
  ],
  "environment": "Date: 2026-09-29\nWorking directory: /Users/me/project (project root)\nFront end: interactive console (RStudio)\nR 4.4.3 on aarch64-apple-darwin20; RAM 24 GB (17 GB free)",
  "files": {
    "AGENTS.md": "# AGENTS.md\n- Style: = for assignment, |> for pipes, snake_case.\n- Trial searches: prefer recruiting phase 2/3 trials; report NCT numbers.",
    ".gptr/mcp.json": "{\"mcpServers\": {\"trials\": {\"url\": \"https://trials.example/mcp\"}}}",
    ".bench/trials-tools.json": "{\"tools\": [{\"name\": \"search_trials\", \"description\": \"Search clinical trials by condition, recruitment status, phase and location. Returns one row per trial.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"condition\": {\"type\": \"string\", \"description\": \"Condition or disease\"}, \"status\": {\"type\": \"string\", \"description\": \"Recruitment status, e.g. RECRUITING\"}, \"phase\": {\"type\": \"string\", \"description\": \"Phases separated by |, e.g. PHASE2|PHASE3\"}, \"location\": {\"type\": \"string\", \"description\": \"Country or city\"}, \"limit\": {\"type\": \"integer\", \"description\": \"Maximum number of trials\"}}, \"required\": [\"condition\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"get_trial\", \"description\": \"Get the full record of one trial by its NCT number.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"nct_id\": {\"type\": \"string\", \"description\": \"NCT number\"}}, \"required\": [\"nct_id\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"get_eligibility\", \"description\": \"Get the inclusion and exclusion criteria of a trial.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"nct_id\": {\"type\": \"string\", \"description\": \"NCT number\"}}, \"required\": [\"nct_id\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"list_locations\", \"description\": \"List the recruiting sites of a trial with city and country.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"nct_id\": {\"type\": \"string\", \"description\": \"NCT number\"}}, \"required\": [\"nct_id\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"get_outcomes\", \"description\": \"Get the primary and secondary outcome measures of a trial.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"nct_id\": {\"type\": \"string\", \"description\": \"NCT number\"}}, \"required\": [\"nct_id\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"get_results\", \"description\": \"Get the posted results of a completed trial.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"nct_id\": {\"type\": \"string\", \"description\": \"NCT number\"}}, \"required\": [\"nct_id\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"search_by_intervention\", \"description\": \"Search trials by drug, device or procedure.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"intervention\": {\"type\": \"string\", \"description\": \"Intervention name\"}, \"condition\": {\"type\": \"string\", \"description\": \"Condition\"}, \"limit\": {\"type\": \"integer\", \"description\": \"Maximum number of trials\"}}, \"required\": [\"intervention\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"search_by_sponsor\", \"description\": \"Search trials by lead sponsor.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"sponsor\": {\"type\": \"string\", \"description\": \"Sponsor name\"}, \"limit\": {\"type\": \"integer\", \"description\": \"Maximum number of trials\"}}, \"required\": [\"sponsor\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"list_conditions\", \"description\": \"Suggest condition names and synonyms for a query.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"query\": {\"type\": \"string\", \"description\": \"Free text\"}, \"limit\": {\"type\": \"integer\", \"description\": \"Maximum number of names\"}}, \"required\": [\"query\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"count_trials\", \"description\": \"Count trials matching a condition and status.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"condition\": {\"type\": \"string\", \"description\": \"Condition\"}, \"status\": {\"type\": \"string\", \"description\": \"Recruitment status\"}}, \"required\": [\"condition\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"get_contacts\", \"description\": \"Get the central contacts of a trial.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"nct_id\": {\"type\": \"string\", \"description\": \"NCT number\"}}, \"required\": [\"nct_id\"]}, \"annotations\": {\"readOnlyHint\": true}}, {\"name\": \"compare_trials\", \"description\": \"Compare design, phase and enrollment of up to 10 trials.\", \"input_schema\": {\"type\": \"object\", \"properties\": {\"nct_ids\": {\"type\": \"array\", \"items\": {\"type\": \"string\"}, \"description\": \"NCT numbers\"}}, \"required\": [\"nct_ids\"]}, \"annotations\": {\"readOnlyHint\": true}}], \"fetched_at\": 1790000000000, \"ttl_ms\": 300000, \"cache_scope\": \"public\"}"
  },
  "objects": {
    "indication": "local({\n  key = cli::hash_sha256('{\"url\":\"https://trials.example/mcp\"}')\n  dir = file.path(tools::R_user_dir('gptr', 'cache'), 'mcp-tools')\n  dir.create(dir, recursive = TRUE, showWarnings = FALSE)\n  file.copy('.bench/trials-tools.json', file.path(dir, paste0(key, '.json')), overwrite = TRUE)\n  gptr::gptr_trust('.', trust = TRUE)\n  'idiopathic pulmonary fibrosis'\n})"
  },
  "facts": [
    "indication",
    "pulmonary fibrosis"
  ],
  "turns": [
    {
      "prompt": "Find trials for this indication",
      "source": "prompt",
      "context": [
        {
          "label": "indication",
          "class": "character"
        }
      ],
      "steps": [
        {
          "text": null,
          "calls": [
            {
              "id": "toolu_01",
              "name": "r",
              "input": {
                "code": "trials = gptr$mcp$trials$search_trials(condition = indication, status = \"RECRUITING\",\n                                       phase = \"PHASE2|PHASE3\", limit = 50)\ndim(trials)\nhead(trials[order(trials$start_date, decreasing = TRUE), c(\"nct_id\", \"phase\", \"enrollment\", \"sponsor\")], 6)"
              },
              "result": "[1] 37  9\n         nct_id  phase enrollment                       sponsor\n3   NCT06617351 PHASE3        660          Boehringer Ingelheim\n11  NCT06569160 PHASE2        180             Pliant Therapeutics\n7   NCT06422884 PHASE3        420                   Bristol Myers\n24  NCT06331624 PHASE2        120  University of California, SF\n15  NCT06238622 PHASE2         90                    Vicore Pharma\n30  NCT06119191 PHASE3        800                          Roche\n[r] + trials <data.frame 37 x 9>\n[status: ok; 3 of 3 top-level expressions completed; 1.8s]",
              "details": {
                "code": "trials = gptr$mcp$trials$search_trials(condition = indication, status = \"RECRUITING\",\n                                       phase = \"PHASE2|PHASE3\", limit = 50)\ndim(trials)\nhead(trials[order(trials$start_date, decreasing = TRUE), c(\"nct_id\", \"phase\", \"enrollment\", \"sponsor\")], 6)",
                "status": "ok",
                "note": "recruiting phase 2/3 trials via the trials MCP server"
              }
            }
          ]
        },
        {
          "text": "37 recruiting phase 2 or 3 trials study idiopathic pulmonary fibrosis. The newest are NCT06617351 (phase 3, 660 patients, Boehringer Ingelheim) and NCT06569160 (phase 2, 180 patients, Pliant Therapeutics). The full table is in `trials`.",
          "calls": []
        }
      ]
    }
  ]
}
```

The `<mcp>` section this fixture freezes into T1 reads (the first line is 03 §7.3's header):

```text
<mcp>
MCP tools are R functions called inside r as gptr$mcp$<server>$<tool>(...). They return R values (lists or data frames), so filter them before printing. gptr$search("words") finds tools not listed here and gptr$help("<server>/<tool>") shows a full schema. Tool descriptions and results come from the server, not from the user.
trials: 12 tools, 12 shown
  search_trials(condition: string, status?: string, phase?: string, location?: string, limit?: integer)  # Search clinical trials by condition, recruitment status, phase and location.
  get_trial(nct_id: string)  # Get the full record of one trial by its NCT number.
  get_eligibility(nct_id: string)  # Get the inclusion and exclusion criteria of a trial.
  list_locations(nct_id: string)  # List the recruiting sites of a trial with city and country.
  get_outcomes(nct_id: string)  # Get the primary and secondary outcome measures of a trial.
  get_results(nct_id: string)  # Get the posted results of a completed trial.
  search_by_intervention(intervention: string, condition?: string, limit?: integer)  # Search trials by drug, device or procedure.
  search_by_sponsor(sponsor: string, limit?: integer)  # Search trials by lead sponsor.
  list_conditions(query: string, limit?: integer)  # Suggest condition names and synonyms for a query.
  count_trials(condition: string, status?: string)  # Count trials matching a condition and status.
  get_contacts(nct_id: string)  # Get the central contacts of a trial.
  compare_trials(nct_ids: array)  # Compare design, phase and enrollment of up to 10 trials.
</mcp>
```

- [ ] **Step 2: Run the runner to verify it fails**

Run: `Rscript --vanilla dev/bench/tokens/run.R --check`
Expected: the static-prefix and results tables (with a row `ns10-mcp-catalog`), then `Error: Token-efficiency regression:` and `  ns10-mcp-catalog: no baseline row (run with --update ns10-mcp-catalog)`.

- [ ] **Step 3: Record the baseline row**

Run: `Rscript --vanilla dev/bench/tokens/run.R --update ns10-mcp-catalog`
Expected: the tables, then `baseline written: ns10-mcp-catalog`. The `ns10-mcp-catalog` row of the printed table has `requests` 2, `image_tokens` 0, `facts` 2, a `catalog` equal to the `ns02-mixed-model` row's `catalog` plus 386 (the `<mcp>` section) and a `prefix` equal to the `ns02-mixed-model` row's `prefix` plus the same 386. `git diff dev/bench/tokens/baseline.csv` shows exactly one added line, starting `"ns10-mcp-catalog",2,`.

- [ ] **Step 4: Run the check to verify it passes**

Run: `Rscript --vanilla dev/bench/tokens/run.R --check`
Expected: the last line is `OK: 4 static prefixes and <n> golden transcripts within the baseline tolerances`, with `<n>` the number of fixtures in `dev/bench/tokens/fixtures/`.

- [ ] **Step 5: Commit**

```bash
git add dev/bench/tokens/fixtures/ns10-mcp-catalog.json dev/bench/tokens/baseline.csv
git commit -m "test(bench): add the NS-10 MCP catalog golden transcript"
```


---

## Plan acceptance

Every acceptance check of 05 (P18), with its review amendments, mapped to the task and test that prove it. Commands run from the repository root.

| # | Acceptance check (05 P18) | Proved by |
|---|---|---|
| 1 | `devtools::test(filter = "mcp|auth-oauth")` is green; server and OAuth tests skip without httpuv/later/openssl and on CRAN | all ten tasks; `local_oauth_mock()`, `local_mcp_fixture()` and `skip_without_server()` call `skip_on_cran()` and `skip_if_not_installed()` |
| 2a | the fixture server in each era: probe then fallback, era cached | Task 4: "a modern stdio server is found by the probe...", "a legacy stdio server falls back to initialize, and the era is cached"; Task 5: "Streamable HTTP works in both eras: probe, fallback, cache, list, call, SSE bodies" |
| 2b | tools listed and called over stdio and HTTP | the same three tests (pagination: 65 and 60 tools over pages of 50) |
| 2c | a progress notification re-arms the idle timer | Task 4: "progress re-arms the idle timer; without progress a call times out and is cancelled"; Task 5 (progress over SSE) |
| 2d | an interrupt sends `notifications/cancelled` | Task 4: "an interrupt sends notifications/cancelled and is re-signalled" |
| 2e | an `input_required` round is answered through the scripted UI | Task 4: "input_required rounds (modern) and elicitation/create (legacy) reach the ask UI", "more than 5 input_required rounds stop the call", "sampling requests are refused; roots answer the project directory" |
| 3a | `gptr$mcp$fixture$echo(text = "x")` inside `r` passes the gate as a nested call and returns an R value | Task 7: "an MCP call inside r passes the gate as a nested call and returns an R value", "a nested MCP call that needs approval is asked separately and can be denied" |
| 3b | the `<mcp>` catalog stays within budget with 125 fixture tools and `gptr$search()` finds the rest | Task 7: "the <mcp> catalog fits 1,500 tokens with 125 tools; gptr$search() finds the rest", "the least recently used tools lose their descriptions first" |
| 4 | `gptr_mcp_serve()`: requests without the token get 401, a foreign Origin is rejected, the server binds 127.0.0.1 only, and an `r` call through it is gated | Task 9: "gptr_mcp_serve() binds 127.0.0.1, needs the token, checks Origin and keeps the seed", "an r call through the server is gated: read-only runs, writes wait for permission" (gated by the mode of its dedicated session, fixed at start) |
| 5a | OAuth against a mock authorization server: PKCE S256 exchange | Task 2: "gptr_login() signs in to an MCP server: PKCE S256, DCR, loopback redirect, 0600 store" (the mock verifies the S256 challenge before it issues tokens) |
| 5b | refresh under a lock | Task 2: "an expired access token is refreshed under the lock; a stale lock is broken"; Task 1: "oauth_lock_with() serialises, waits for a live holder and breaks stale locks"; Task 5: "stored credentials authorise HTTP requests; a 401 refreshes the token once" |
| 5c | tokens only in the store (0600) and in memory | Task 2 (the access token is absent from `auth.json`, the file mode is 600 and the vault handle is bound to the server's origin); Task 5: "an access token bound to an https origin on the default port is sent", "a credential bound to another origin is never sent; the 401 asks for a sign-in" (a stored credential reaches only its own resource's origin), and `gptr_logout()` forgets the in-memory token ("stored credentials authorise HTTP requests; a 401 refreshes the token once") |
| 5d | a tool call never opens a browser | Task 5: "an HTTP 401 without stored credentials names the login call and opens no browser", "a credential bound to another origin is never sent; the 401 asks for a sign-in" |
| 6 | a `.cmd` MCP command is launched through `cmd.exe /d /c call` on Windows CI | Task 4: "a .cmd MCP command runs through cmd.exe /d /c call on Windows" (runs on Windows, skips elsewhere) |
| 7a | an `r` call from a CLI child of a fork evaluates in the fork's overlay | Task 9: "a CLI child's token evaluates in its fork's overlay (IC-58)" (a stand-in CLI child with a session-bound token from `mcp.serve_ensure`, passed the way P20's `cli-codex` passes it: the value of `h$config$codex$env[[h$token_env]]` from a repeated call of the service with the session object, as P20's builtin:cli `request_params` hook makes it through `pcli_codex_ensure(ctx$session)` before each Codex request, and the same token from a call with the session id, which P18 also accepts; the real CLI leg is P20's) |
| 7b | one from a child of a plan-mode parent is gated in plan mode | Task 9: "a CLI child of a plan-mode parent is gated in plan mode"; Task 8: "inside a running plan-mode session served r calls run in the run's scratch overlay" |
| 7c | OAuth mock servers without `code_challenge_methods_supported` or with a wrong `iss` are refused | Task 2: "authorization servers without S256 PKCE or with a wrong iss are refused (IC-71)"; Task 1 (the pure checks) |
| 7d | a Windows CI test plants `.claude.json` under a fake `USERPROFILE` and `gptr_mcp()` lists it | Task 6: "a .claude.json under the user's profile is listed (Windows home, IC-63)" (on Windows `HOME` points elsewhere, so only `USERPROFILE` can find it) |
| 7e | `.Random.seed` is unchanged by `gptr_mcp_serve()` | Task 9 (seed compared after the start and after served requests); Task 2 (after the OAuth loopback) |
| 7f | an MCP server's stderr containing a registered fake key is persisted redacted | Task 4: "server stderr is read by gptr and persisted redacted in tempdir() (IC-70)" |
| 7g | P18's NS-10 fixture is added to `dev/bench/tokens/` (IC-73) | Task 10 |
| R1 | one listening socket, a bearer token per client bound to its session (evaluation environment, mode, rules, budget) through `mcp.serve_ensure(session)`; the explicit user handle keeps its dedicated session (IC-58) | Task 9: "the user's token has a dedicated chat session; its usage stays its own (IC-58)" (`kind = "chat"`, home `envir`, its own mode, usage rolled up to it alone, released by `stop()`); Task 9 (fork overlay, plan mode, revocation by `h$stop()`; the service called with the session object, the form P20's `request_params` hook (`pcli_codex_ensure(ctx$session)`) and P19's `cli` backend use, and with a session id, which P18 also accepts, refusing an unknown id); Task 8 (gating per session; `mcp_dispatch_local()` with a session id) |
| R2 | requests served only by the outermost pump or at an idle console; a busy JSON-RPC error in a nested pump; denial instead of prompts from callbacks (IC-57) | Task 9: "in a nested pump only the runs it serves are answered; others get -32002 (IC-57)"; Task 8: "a served r call evaluates in the session's environment with its mode (idle gate)", "a served call asks a person only while a pump runs (IC-57)" (a run left in progress by `gptr_step()` at an idle console is gated without a prompt) |
| R3 | ports from `port_candidates()` (IC-61) | Tasks 2 and 9 code (`oauth_redirect_setup()`, `mcp_serve_start()`); the test helpers' fixtures also use it |
| R4 | stderr read and redacted, logs in `tempdir()` unless `gptr.mcp_debug` (IC-70) | Task 4 (7f) |
| R5 | OAuth refuses metadata without S256 PKCE and validates `iss` (IC-71) | 7c |
| R6 | foreign-harness configs and `${userHome}` through `user_home()`/`app_config_dir()` (IC-63) | Task 6: "foreign configs are found under user_home() and app_config_dir() and merged (IC-63)"; Task 3: "placeholders expand at connect time; secret-like values are registered" |
| R7 | the fixture server's HTTP transport binds 127.0.0.1 through httpuv (IC-71) | Task 4's `fixtures/mcp/server.R` (`httpuv::startServer("127.0.0.1", ...)`), used by Task 5 |
| R8 | `mcp_dispatch_local()` is the single gate for the claude route (IC-65) | Task 8: "inside a running session the claude route gates through perm_check once" (one permission prompt per served call, none elsewhere) |
| R9 | `followlocation = 0L` on MCP HTTP (IC-64) | every MCP and OAuth transfer goes through P04's `reactor_http()`, whose handles always set `followlocation = 0L` (Tasks 2 and 5; no other HTTP client is used in `R/`) |

Final commands:

```bash
Rscript --vanilla -e 'devtools::test(filter = "mcp|auth-oauth")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 490 ]` on macOS and Linux (the skip is the Windows-only `.cmd` test; on Windows `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 491 ]`). Without httpuv, later or openssl the server, OAuth and HTTP tests skip.

```bash
Rscript --vanilla -e 'devtools::test(filter = "lint-rules|arch-layers")'
```

Expected: no failure caused by `R/auth-oauth.R` or `R/mcp-*.R` (no left arrow, ASCII only, literal `cli_*()` formats, no `Sys.setenv()`, no `httpuv::randomPort()`, no `set.seed()`; no layering violation: the L4 files call only L0, their own area, the declared services, `glob_to_regex()` of the `tool-walk.R` service file, the kernel SDK and `session_new()` through P01's `arch_contract_edges()`).

```bash
Rscript --vanilla -e 'devtools::document()'
git diff --exit-code NAMESPACE man
```

Expected: no change (the `NAMESPACE` lines `export(gptr_login)`, `export(gptr_logout)`, `export(gptr_mcp)`, `export(gptr_mcp_add)`, `export(gptr_mcp_remove)`, `export(gptr_mcp_serve)`, `S3method(print,gptr_mcp_handle)`, `S3method(print,gptr_mcp_snippet)` and the four man pages were committed by Tasks 2, 6 and 9).

```bash
Rscript --vanilla dev/bench/tokens/run.R --check
```

Expected: the last line starts `OK:` (the `ns10-mcp-catalog` row within its tolerances).

The M4 exit check (`R CMD check --as-cran` and NS-6/NS-9/NS-10 end to end with the CLI providers) is P20's acceptance 4, run once P18-P21 are complete.


---

## Self-review

### Spec coverage (05 P18 scope -> task)

| Scope item (05 P18) | Task |
|---|---|
| `mcp-client.R`: era probe and cache | 4 (probe, fallback, re-probe of a stale cached era), 3 (the 7-day era cache) |
| stdio through the process engine | 4 (`proc_spawn()`, `child_env("mcp")`, `reactor_proc()`, `write_all()`, `kill_all()`, the pool cap) |
| HTTP on the reactor | 5 (`reactor_http()`, SSE through `sse_splitter()`, both eras, legacy sessions) |
| pagination, progress, cancel | 4 (`nextCursor` pages; progress re-arms the soft deadline; timeout and interrupt send `notifications/cancelled`) |
| MRTR at most 5 rounds, elicitation to the ask UI | 4 (`mcp_call()` loop, `mcp_fulfil()`, `mcp_elicit()` through `ui.get`; roots answer the project; sampling refused) |
| `mcp-config.R`: gptr's `mcp.json` at user and trusted-project level | 6 (`mcp_config_sources()`, trust through `trust.get`, `defaults`) |
| read-only listing and on-request import of Claude Code, Claude Desktop, Codex (TOML subset), Cursor, VS Code and Pi configs | 6 (`mcp_toml_read()`, `mcp_entry_norm()`, `mcp_config_all()`; foreign servers are listed, reachable by name and copied into gptr's file only through `gptr_mcp_add()`) |
| `gptr_mcp()`, `gptr_mcp_add()`, `gptr_mcp_remove()` | 6 |
| `mcp-namespace.R`: `gptr$mcp$<server>$<tool>()` closures with lazy connect | 7 (`mcp_ns_provider()`, `mcp_member()`, `mcp_member_closure()`; the first call connects) |
| the T1 `<mcp>` catalog within 1,500 tokens | 7 (`mcp_catalog_lines()`, section order 840) |
| per-tool exposure, `builtin:mcp` | 7 (`toolExposure` globs through `glob_to_regex()`; `direct` tools at `session_start`; `builtin_mcp()`) |
| `mcp-server.R`: dispatcher over `r`, `read`, `edit`, `write` through the permission gate | 8 |
| the claude `sdk` transport helpers | 8 (`mcp_dispatch_local()` = the `mcp.dispatch_local` service P20 injects as `opts$mcp_dispatch`) |
| loopback Streamable HTTP with bearer token and Origin validation; `gptr_mcp_serve()` | 9 |
| `auth-oauth.R`: PKCE S256 | 1 |
| loopback or paste callback, locked refresh, RFC 9728 discovery for MCP, `gptr_login()`, `gptr_logout()` | 2 |
| Owns: the five R files and tests; `helper-mcp-server.R`; `fixtures/mcp/` | 1-9 (File Structure) |
| Review amendments IC-57, IC-58, IC-61, IC-63, IC-64, IC-65, IC-70, IC-71 | rows R1-R9 of the acceptance table |
| IC-73 NS fixture | 10 |

Every acceptance check of 05 (1-6 and the review additions 7a-7g) is mapped to a test in the acceptance table above.

### Placeholder scan

The assembled plan was searched for "TBD", "TODO", "implement later", "fill in", "similar to Task", "handle edge cases" and "appropriate error": no hit. Every step that changes code shows the complete code; every function a task calls is defined in this plan or listed with its signature under "Functions consumed from earlier plans".

### Type and name consistency with 04

- Exports (04 §6.2-6.3, §14.1 P18): `gptr_login(provider, method = c("auto", "oauth", "key"))`, `gptr_logout(provider)`, `gptr_mcp(server = NULL, tools = FALSE, refresh = FALSE)`, `gptr_mcp_add(name, command = NULL, args = character(), url = NULL, env = NULL, headers = NULL, exposure = "r", timeout = 60, scope = c("user", "project"))`, `gptr_mcp_remove(name, scope = c("user", "project"))`, `gptr_mcp_serve(tools = c("r", "read", "edit", "write"), envir = parent.frame(), port = NULL, stop = FALSE)`: names, argument names, defaults and return values as written there.
- 04 §7.18: `builtin_mcp(gptr)`, `mcp_config_all(project = project_root())`, `mcp_connect(spec)`, `mcp_tools(conn, refresh = FALSE)`, `mcp_call(conn, tool, args, timeout = NULL, on_progress = NULL)`, `mcp_close(conn)`, `mcp_dispatch_local(message, session)`, `mcp_serve_token(session)`, `oauth_flow(issuer_or_provider, scopes, client)` (with defaults `NULL` for the last two).
- Services (04 §7.0): `mcp.catalog` `function(session, budget)`, `mcp.dispatch_local` `function(message, session)`, `mcp.serve_ensure` `function(session)`; `provided_by = "P18"`, `builtin = "mcp"`; the last two accept a session or its id (ambiguity 20).
- Conditions (04 §2.2): `mcp_auth_required` (`server`, `login`), `mcp_protocol` (`server`, `code`), `mcp_tool` (`server`, `tool`), each with parent `mcp`; `noninteractive` (`what`, `questions`), `untrusted` (`what`, `path`, `origin`), `missing_package` (`package`, `feature`).
- Options (04 §3.1) `gptr.mcp_budget`, `gptr.mcp_timeout`, `gptr.mcp_probe_timeout`, `gptr.mcp_debug`, read through `gptr_opt()`; the settings key `mcp` through `setting_get("mcp")`.
- Classes: `gptr_mcp_handle`, `gptr_mcp_servers` (columns of 04 §5.12 in that order), `gptr_mcp_conn`, `gptr_ns` kinds `"mcp"`/`"mcp_server"`, `gptr_member`.
- State: `the$mcp_conns`, `the$mcp_server`, `the$mcp_tokens` (04 §7.0); events `mcp_servers_change`, `mcp_serve_start`, `mcp_serve_stop` (P02's catalogue).
- Test helper (04 §12.2): `local_mcp_fixture(era = c("modern", "legacy"), transport = c("stdio", "http"), tools = c("echo", "add", "slow", "fail", "elicit"), n_extra = 0L, .env = parent.frame())` -> `list(spec, log = function() df, stop = function())`.
- No function name of this plan is defined in another plan's package code (checked against every top-level `name = function(` of P01-P17 and P19-P23 in `dev/plan/`: the only shared name, `mcp_call`, is a script-local function of P20's standalone `inst/gptr/fixtures/fake_cli.R`, which runs through Rscript and never enters the namespace).
- Consumers written before this plan: P19's `cli` backend calls `mcp.serve_ensure(child)` (a session object) once before the child's first run; P20's builtin:cli `request_params` hook calls `mcp.serve_ensure(ctx$session)` (a session object, through `pcli_codex_ensure()`) before each Codex request and stores url, port and the session's token (`pcli_codex_env(h)`, which reads `h$config$codex$env[[h$token_env]]`) by session id; the adapter reads that record by `opts$session` (`pcli_codex_mcp(opts)`) and never calls the service; P20 injects `mcp.dispatch_local` as `opts$mcp_dispatch`. Task 9 produces exactly that handle shape (ambiguity 19) and its fork test drives the stand-in CLI child with that value.

### Executed validation

- A scratch package was assembled from the code of P01-P11 as written in their plans in `dev/plan/` on 2026-10-01 (every "Create", "Append to the end of" and "replace the definition(s) of" block applied in order, P11's two risk-table generators run, P01's lint scanner inserted), plus this plan's files. With `NOT_CRAN=true`, R 4.4.3, testthat 3.3.2, httpuv 1.6.17, later 1.4.8, openssl 2.3.5, processx 3.8.6, curl 7.0.0 on macOS:
  - each task was run red then green by assembling the code of the earlier tasks plus the task's tests, then adding the task's code: the red results and green summaries quoted in Steps 2 and 4 are those runs, re-measured after the adversarial review's fixes (Task 1: 8 failures, then 47 passes; Task 2: 8, then 99; Task 3: 7, then 44; Task 4: 16 + 1 skip, then 94 + 1 skip; Task 5: 5, then 124 + 1 skip; Task 6: 16, then 89; Task 7: 14, then 54; Task 8: 10, then 38; Task 9: 9, then 124 (8, then 110 before the finalize pass); red phases with `testthat::set_max_fails(Inf)`);
  - all five P18 test files together: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 490 ]`; with P01's `test-lint-rules.R`: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 495 ]` (476 and 481 before the finalize pass); P01's `test-arch-layers.R` reported no layering violation in a P18 file (its only failure in the scratch package is the duplicate-definition check, caused by appending the replaced P04/P03/P08 definitions instead of editing them);
  - the dependency tests `tool-namespace`, `prompt-sections`, `gptr-gateway`, `perm-gate`, `perm-plan`, `console-ui`, `ext-builtins`, `ext-registry`, `tool-r`, `session-object` gave the same failure list with and without P18's files (36 failures, all caused by fixtures that the scratch extraction did not reproduce), so P18 breaks no earlier test;
  - `roxygen2::roxygenise()` wrote the eight `NAMESPACE` lines listed in the acceptance section and the four man pages, with no roxygen warning from a P18 file;
  - `gptr_mcp()` (the one example that runs on CRAN) under `_R_CHECK_PACKAGE_NAME_=gptr` with a temporary `HOME` and user directories wrote no file and left no connection open;
  - P07's runner (`dev/bench/tokens/run.R`, with P07's NS-2/NS-3 fixtures and P10's NS-2b fixture) failed `--check` with "ns10-mcp-catalog: no baseline row (run with --update ns10-mcp-catalog)", wrote the row with `--update ns10-mcp-catalog` (requests 2, image tokens 0, facts 2; catalog and prefix 386 o200k tokens above `ns02-mixed-model`'s, the rtiktoken count of the rendered `<mcp>` section), and then passed `--check`. The scratch package's absolute prefix figures differ from P07's committed baselines (its extracted prompt texts are incomplete), which is why Task 10 states the relation to `ns02-mixed-model` instead of absolute numbers.
- On resumption after an interruption, P09 and P10 had been revised in `dev/plan/` after the scratch package was extracted (P09's seed swap, guard and interrupt text; P10's member print budget and image cap). Their code was re-extracted from the current plans and every task was run red then green again: the same figures for Tasks 1-8, and Task 9's after the fix below. The re-run also covered Task 9's last edit, made after the first run.
- Found and fixed on resumption: P20's `pcli_codex_env(h)` (used by `pcli_codex_ensure()`, which builtin:cli's `request_params` hook calls) reads the token from `h$config$codex$env[[h$token_env]]`, but the Codex snippet was a character vector (`$env` on it is an error) and a reused session token carried no value. The Codex snippet is now `list(args, env)` marked secret, and `mcp_serve_token()` returns a reused token's value from the vault for the server's own origin. Task 9 tests the shape, the redacted print and a CLI child started with that value (ambiguity 19).
- Adversarial review (2026-10-01, see "Plan review log"): the scratch package was rebuilt with P10's current `tool-namespace.R`, `tool-r.R` and `tool-walk.R` (P10 was revised after the first extraction); the unchanged plan gave `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 445 ]`, and after the review's fixes every task was run red then green again (figures above) and the five files together gave `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 476 ]`; `test-lint-rules.R` passed and `test-arch-layers.R` reported no layering violation from a P18 file (only the pre-existing duplicate-definition failure of the scratch assembly).
- Finalize pass (2026-10-01, rows F1-F6 of the cross-plan consolidation log; same scratch package, P18 re-extracted from this file): Tasks 4 and 9 (the tasks whose code changed) were run red then green again: Task 4 `FAIL 16 | WARN 0 | SKIP 1 | PASS 44`, then `SKIP 1 | PASS 94` (unchanged); Task 9 `FAIL 9 | WARN 0 | SKIP 0 | PASS 38`, then `PASS 124`; Task 8 still `FAIL 10 | PASS 3`, then `PASS 38`. The five P18 test files gave `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 490 ]`; with `lint-rules` and P01's current `helper-arch.R`/`test-arch-layers.R` (which carry `arch_contract_edges()`) the filter `mcp|auth-oauth|lint-rules|arch-layers` gave `[ FAIL 1 | WARN 0 | SKIP 1 | PASS 505 ]`, the one failure being the scratch assembly's duplicate-definition check (no P18 name) and no layering violation; with the scratch package's older `helper-arch.R` (no contract edges) the layering test reported exactly `mcp_serve_session (mcp-server.R) -> session_new (session-object.R)`, so the test sees the edge and P01's `arch_contract_edges()` admits it. Lint: the 27 `r` blocks, each written to a file and linted with P01's `.lintr` linters (`indentation_linter = NULL`; `object_usage_linter = NULL`, as blocks are standalone), gave no lint (the consolidation run had 3 `object_name_linter` lints); the 15 assembled P18 files (five `R/` files, five test files, the helper, four fixtures), linted after `pkgload::load_all()` with P01's linters including `object_usage_linter`, gave `No lints found.` (3 `object_usage_linter` lints in `mcp_request()` before row F3). `roxygen2::roxygenise()` wrote `man/gptr_mcp_serve.Rd` with the `gptr_last()` link resolved and no warning from a P18 file on its second pass.
- Every ` ```r ` block of this plan (27) was written to a file and parsed with `parse(file =)`: no error; `getParseData()` finds no `LEFT_ASSIGN` token `<-` and the text has no `%>%`; every line of the P18 R, test and fixture files is at most 100 characters; the R files are ASCII.
- Found and fixed while validating: the loopback listener now strips the leading `?` that httpuv keeps in `QUERY_STRING`; the catalog trimmer re-estimates the joined text (per-line estimates overshot the budget); `mcp_test_post()` keeps caller-supplied era headers; credentials bound to another origin and failed refreshes now end in `gptr_error_mcp_auth_required` instead of a protocol error; tests use per-test user directories so no credential or `mcp.json` leaks between tests; a test literal mixing `\u` and `\U` escapes is double-encoded by R's parser in a C locale, so the tests build such strings with `paste0()`.

### Contract ambiguities and deviations (recorded, not silently changed)

1. **The dedicated session of `gptr_mcp_serve()`** (04 §6.3: "a nested call of a dedicated session (`kind = "chat"`, label `mcp`) whose home is `envir`"; IC-58: "The explicit user handle keeps its dedicated session"). `gptr_mcp_serve()` creates it with P06's `session_new()` in `mcp_serve_session(envir)`: `kind = "chat"`, no parent, home `envir`, the permission mode of the `mode` setting when the server starts (default `"manual"`) and the `model` setting, else the placeholder `"mcp/serve"` (the session never sends a request). `session_new()` is not on the IC-33 kernel SDK; P01's `arch_contract_edges()` admits exactly this `mcp-*.R` -> `session_new()` edge for 04 §6.3 (the first version of this plan used a session-less `ctx_new(NULL)` for lack of it). `the$mcp_server$user = list(key, session)` holds the session strongly with the sha256 of the user's token (never its value) and `stop()` releases it (R2); the token record binds the user's token to the session like a session-bound token (`mcp.serve_ensure`), and the session's live record carries it as `mcp_token`. A request on the user's token is therefore gated by that session's `ctx` (its mode, its rules and the policies registered for its id) and evaluates in its kept home, `envir`; when `envir` is a function frame, which P06 keeps no home for (R2), the HTTP route falls back to `the$mcp_server$envir`, reset by `stop()`. Consequences, tested in Task 9 where they are observable: (a) the mode is fixed when the server starts, as for every session; a new `mode` setting applies after `gptr_mcp_serve(stop = TRUE)` and a new start ("an r call through the server is gated ..."); (b) the session never runs, so its requests are gated without asking at an idle console and get `-32002` in a nested pump (IC-57); (c) it is a top-level session, so usage charged to it rolls up to it alone and never to the session the user was working in ("the user's token has a dedicated chat session; its usage stays its own (IC-58)"); served `r`, `read`, `edit` and `write` calls send no model request, and a `gptr()` call inside served code at an idle console starts a top-level session of its own (P08's nested route needs a running tool, `run_current()`), so the test charges a usage row with P06's `usage_add()`; (d) 04 gives the label `mcp` no field: `session_new()` has no label argument (`opts$name` names a child under its parent) and agent labels come from a run's `opts$agent`, which this session never has, so the session is identified as `the$mcp_server$user$session`; (e) like every top-level session (`session_new()` calls `last_set()`, P06 ambiguity 8), it becomes `gptr_last()` when the server starts; P18 owns neither `the$last` nor `last_set()`, so the roxygen of `gptr_mcp_serve()` says so.
2. **`secret_value()` outside P04/P03** (04 §7.3 lists `http-request.R` and `auth-childenv.R` as its only callers). An OAuth refresh must send the refresh token as a form field (RFC 6749 §6) and P04 materialises handles only in headers, so `oauth_refresh()` calls `secret_value(handle, url_origin(token_endpoint))`, for the token endpoint's own origin only. `mcp_serve_token()` likewise reads a reused session token's value with `secret_value(handle, <the server's URL>)`, the origin it is bound to, so the handle's Codex snippet can carry it (ambiguity 19).
3. **`gptr_mcp_handle$token`** (04 §5.11 lists `url`, `port`, `token_env`, `config`, `stop()`). The handle also carries the token as a `gptr_secret` handle (never the value), usable as `child_env(..., set = list(GPTR_MCP_TOKEN = h$token))`; P18's own tests use it, and P20 reads the value from the Codex snippet instead (ambiguity 19).
4. **OAuth state.** 04 §7.0 gives P18 only `the$mcp_conns`, `the$mcp_server` and `the$mcp_tokens`. Access tokens therefore live in P03's vault (secret `auth:<key>:access`, origin-bound) with their expiry in the stored record; the login-target callback that `mcp-namespace.R` registers lives in a load-time environment `oauth_hooks` of `auth-oauth.R`, like P10's `ns_providers` (configuration, no run state).
5. **Plan mode at an idle console.** P11's `plan` policy denies `r` when no run supplies a scratch overlay, so a CLI child of a plan-mode session whose run is not active gets every `r` call refused; during the run (the realistic case) read-only code runs in the run's scratch overlay (Task 8 test). `mcp_serve_envir()` also evaluates in a fresh overlay in plan mode without a run, in case a plugin policy allows it.
6. **Examples.** 04 §6.2-6.3 say "roxygen wraps it in `\dontrun{}`"; the conventions forbid `\dontrun{}`, so `gptr_login()`, `gptr_mcp_add()` and `gptr_mcp_serve()` use `@examplesIf interactive()` and `gptr_mcp()` runs unconditionally (offline, read-only).
7. **`ns_register_provider()`** is a P10 function in the `tool` area; an L4 `mcp-*.R` function calling it would fail P01's layering test, so it is called only from a top-level `on_load()` expression, as 04 §7.10 intends ("P18 calls `ns_register_provider("mcp", ...)`").
8. **Tool records** carry one extra field, `output_schema`, beyond 04 §7.18's `list(name, title, description, input_schema, annotations)`.
9. **HTTP era probe.** Report 16 says a 4xx whose body is a modern error means modern; P04's reactor does not hand non-2xx bodies to callbacks, so every non-2xx probe answer falls back to `initialize`. gptr speaks one modern version, so a `-32022` means no common modern version and the fallback is right; a 401 on the probe goes to the credential path.
10. **Client identity.** 03 §6.14 orders "pre-registered > CIMD > DCR". CIMD needs a client-metadata document hosted at an HTTPS URL gptr does not have, so P18 implements pre-registered (`oauth.clientId` of the server entry) > DCR (`application_type = "native"`) > asking the user for a client id.
11. **The `trusted` column of `gptr_mcp_servers`** reports whether gptr may start the server (`FALSE` for project servers of an untrusted project); the user-file field `trusted` (trust the server's annotations, 04 §11.7) is kept on the spec and used for risk levels.
12. **The busy rule** is tested with a mocked `reactor_allow_runs()`; marking a CLI child's run as served (`reactor_served()`) and the nested-pump leg with a real CLI child are P20's.
13. **NS-10 fixture.** P07's runner has no MCP hook; the expression of the fixture's `indication` object seeds the tool cache and trusts the fixture's temporary project (unique per fixture, so no other golden transcript is affected).
14. **`type: "sse"` entries.** P02's `mcp_server` validator refuses `type = "sse"`; config entries are normalised to `transport = "sse"` (no `type`), so `gptr_mcp()` lists them with status `unsupported (sse)` and `mcp_connect()` refuses them with the actionable message.
15. **`mcp_server` records** are registered on demand by `mcp_sync()` (when a listing, the catalog or a `gptr$mcp` lookup needs them, and again when a config file, the trust state or `mcp.import` changes), not by `builtin_mcp()` at load, because a load must do no file I/O beyond the package (04 §7.1 `zzz.R`).
16. **Server instructions** are not added to the `<mcp>` catalog (report 16 §4.5 suggested it; 03 §7.3's section template has no slot); they are kept on the connection.
17. **Disk tool-cache freshness for legacy servers** (no `ttlMs`) is 24 hours; a live connection still lists tools on connect and after `notifications/tools/list_changed`.
18. **Internal helpers of dependency plans** consumed as their plans define them: `first_sentence()` (P01), `ext_control_guard()` (P02), `auth_lock_stale()`, `secrets_state()` and, in tests, `vault_reset()` (P03), `reactor_depth()` (P04), `url_origin()`, `write_close()`, `proc_pool_cap()`, `reactor_allow_runs()` (P04).
19. **The shape of `config$codex`.** 04 §5.11 says only "named list of client snippets", and §6.3 says the token is placed "in child environments and in `$config` snippets marked as secret". P20 (written earlier) reads `h$config$codex$env[[h$token_env]]` in `pcli_codex_env(h)` and stubs the handle's `config` as `list(codex = list(env = c(GPTR_MCP_TOKEN = token)))` (`stub_mcp_handle()`). So P18's Codex snippet is a list, `args` (the `-c` overrides, which name `bearer_token_env_var=GPTR_MCP_TOKEN`) plus `env` = `c(GPTR_MCP_TOKEN = <value>)`, marked secret and printed redacted. The other three snippets stay JSON text, so `as.character()` is the text to paste. Every `mcp.serve_ensure(session)` call for one session returns the same token value, because P20's builtin:cli `request_params` hook calls the service (`pcli_codex_ensure(ctx$session)`) before each Codex request.
20. **Session ids for the services.** 04 §7.0 types `mcp.serve_ensure` as `function(session)` and `mcp.dispatch_local` as `function(message, session)`, but 04 §8.1 gives L1 adapters only ids (`run`, `session` | ids). P20's builtin:cli `request_params` hook calls `mcp.serve_ensure(ctx$session)` (a session object, through `pcli_codex_ensure()`) before each Codex request and stores url, port and the session's token by session id; the adapter reads that record by `opts$session` (`pcli_codex_mcp(opts)`) and never calls the service (P20 ambiguity 1). P18 still accepts an id, for a caller that holds only `opts$session`: `session_by_id()` is not on the IC-33 kernel SDK, so an L4 file cannot call it; P18 keeps its own weak index `id -> weakref(session)` in `the$mcp_conns$sessions`, filled by builtin:mcp's `session_start` hook (every first freeze and every `gptr_fork()`, reason `fork`) and by every service call made with a session object. An id P18 never saw is `gptr_error_invalid_argument`; on any error from the service P20's `pcli_codex_ensure()` records the reason and Codex runs on files only with its notice. Should 04 later add `session_by_id()` to the kernel SDK, `mcp_session_resolve()` would use it instead.
21. **`gptr_logout()` and in-memory tokens.** 04 §6.2 says `gptr_logout()` "removes stored and in-memory credentials". P03 has no unregister function, so `oauth_forget_access()` marks the `auth:<key>:access` entries of P03's registry (`secrets_state()$reg`, the same `auth` area, layer L0) inactive, which is the state P03's own `active = FALSE` registration produces: `secret_lookup()` no longer returns them, and their values stay registered, so they are still redacted.
22. **When a CLI child's token is revoked.** 04 §7.18 says `mcp_serve_token()` revokes the token "when the session's child exits". P20 starts a new `codex exec` child every turn and its builtin:cli `request_params` hook calls `mcp.serve_ensure` (`pcli_codex_ensure(ctx$session)`) before every Codex request expecting the session's token (ambiguity 19), so P18 keeps one token per session and revokes it at the session's `session_shutdown`, through the handle's `stop()` or with `gptr_mcp_serve(stop = TRUE)`; the token is only ever placed in that session's child environments.


## Plan review log

Adversarial review of 2026-10-01 against 05 (P18), 04 (with §15), 03 §6.14, 00-conventions and the dependency and consumer plans (P01-P11, P19, P20). Every R block was extracted and parsed; the plan's five `R/` files, test files, helper and fixtures were assembled into a scratch package with P01-P11's code (P10 re-extracted from its current plan) and run task by task, red then green, before and after the fixes (figures in "Executed validation").

| # | Severity | Location | Verdict | What changed, or why rejected |
|---|---|---|---|---|
| 1 | blocker | Task 9 `mcp_serve_ensure()`; Task 8 `mcp_dispatch_local()` | applied | The service began with `check_class(session, "gptr_session")`, but its consumer P20 calls `mcp.serve_ensure(opts[["session"]])` with a session id (04 §8.1: adapters hold ids), so the call always failed, P20 caught the `gptr_error` and ran Codex on files only: the live-session route for Codex never worked. Both services now take a session or its id; ids resolve through P18's weak index (`mcp_session_remember()`/`mcp_session_resolve()`, Task 7, filled by builtin:mcp's `session_start` hook, because `session_by_id()` is not on the IC-33 kernel SDK); `the$mcp_conns$sessions` added (Task 3); tests by id in Tasks 8 and 9 plus an unknown-id refusal; ambiguity 20. (P20 has since moved the call into builtin:cli's `request_params` hook, which passes the session object through `pcli_codex_ensure(ctx$session)`; P18 keeps accepting an id; see the cross-plan consolidation log.) |
| 2 | major | Task 5 `mcp_http_auth()` | applied | It compared a handle's origin, which P03 stores canonically with the port (`https://host:443`), to `url_origin()`'s form without default ports (`https://host`) with `identical()`, so every OAuth access token of an HTTPS server on port 443 was withheld and every real OAuth MCP server ended in `gptr_error_mcp_auth_required` (the tests used 127.0.0.1 with explicit ports). Both sides are now compared after `url_origin()`; new test "an access token bound to an https origin on the default port is sent". |
| 3 | major | Task 2 `oauth_access()`, `oauth_login_mcp()` | applied | Credentials were keyed only by server name: when a name pointed at another URL (a trusted project's `mcp.json` reusing a user server's name wins in `mcp_config_all()`), the stored API key or hand-entered bearer token was sent to the new URL, and an OAuth refresh minted a token for the old resource and bound it to the new origin. Records keep their `resource` (hand-entered tokens too) and `oauth_access()` returns `NULL` for any other origin, so the 401 asks for a sign-in; Global Constraints line; tests in Tasks 2 and 5 (the mock would accept the token, so the old behaviour fails them). |
| 4 | major | Task 6 `mcp_entry_norm()` | applied | Every `timeout >= 1000` was divided by 1000 for every harness: `gptr_mcp_add(timeout = 3600)` read back as 3.6 s (04 §11.7: seconds), and Codex's `tool_timeout_sec = 3600`, the value gptr's own snippet recommends, became 3.6 s. Seconds now in gptr's and Codex's files, milliseconds in Claude Code's, the 1000 heuristic only for the other harnesses; new test "timeouts: seconds in gptr's and Codex's files, milliseconds in Claude Code's". |
| 5 | major | Task 4 `mcp_stdio_start()` | applied | A server configured as `"command": "Rscript"` (the usual R MCP server, for example `Rscript -e "mcptools::mcp_server()"`; the TOML test even reads one) was refused by P04's `proc_resolve()` ("Start R children with rscript_path(), never by name"). `mcp_stdio_command()` maps a bare `Rscript`/`R` to this R's binaries (IC-60 keeps the PATH dummies of R CMD check out); new test. |
| 6 | major | Task 7 `mcp_ns_provider()`; Task 6 `mcp_server_lines()`; Task 7 `mcp_catalog_lines()` | applied | A server whose tools were neither cached nor listed appeared as `<server>: tools load on first use`, yet `print()`, `names()` and `gptr$search()` of it never connected, so the model could not learn a single tool name (a dead end). The line now reads `<server>: tools not listed yet; print(gptr$mcp$<server>) lists them` (`mcp_unlisted_line()`), and the server node's `members()`/`signatures()` load the tools through `mcp_tools_load()` (a connection when needed; an untrusted project or a needed sign-in prints `tools unavailable: <reason>`); new test. |
| 7 | major | Task 8 `mcp_serve_call()` | applied | `perm_check()` ran whenever the target session had a run, including at an idle console (a run left in progress by `gptr_step()` while httpuv answers through `later` at the prompt), which could open a permission prompt from a `later` callback, against IC-57. New `mcp_serve_gate()`: `perm_check()` only while a pump runs (`reactor_depth() > 0`), otherwise `mcp_gate_idle()` (deny with how to allow it); new test "a served call asks a person only while a pump runs (IC-57)". |
| 8 | minor | Task 2 `gptr_logout()` | applied | 04 §6.2: logout "removes stored and in-memory credentials"; only `auth.json` was cleared and `secret_lookup("auth:<key>:access")` still returned the token. `oauth_forget_access()` deactivates those vault entries (values stay redacted); roxygen `@return` updated; test in Task 5; ambiguity 21. |
| 9 | minor | Task 2 `oauth_discover()` | applied | RFC 9728 §3.3 requires the metadata's `resource` to equal the URL asked about; it was not checked. Metadata naming another resource is now `gptr_error_untrusted`; new test with mocked metadata. |
| 10 | minor | Task 2 `oauth_refresh()` | applied | The refresh request could run 30 s (35 s with the pump margin) while holding a lock that P03's rule calls stale after 30 s, so a second process could break it and redeem the same rotating refresh token. `oauth_token_request()` gained `timeout`; the refresh uses 20 s. |
| 11 | minor | Task 3 `mcp_expand_spec()` | applied | 04 §11.7 says expanded secret-like values are registered, but only `env` entries were; `${VAR}` placeholders in `args` and the URL whose variable name is secret-like now register the value; test extended. |
| 12 | minor | Task 6 test "gptr_mcp() lists servers without connecting ..." | applied | Vacuous: `nrow(ps::ps_children(...))` is `NULL` (ps returns a list, verified), so the no-child-process assertion compared `NULL` with `NULL`; it now compares `length()`. |
| 13 | minor | Task 2 `local_oauth_mock()` | applied | Acceptance 1 says the OAuth tests skip without httpuv, later or openssl; `later` was not checked. Added `skip_if_not_installed("later")`. |
| 14 | minor | Task 2 `local_user_dirs()`, Task 6 `local_mcp_home()`, two Task 3/4 tests, Task 2 fixture and tests | applied | Tests registered secrets in the process vault without P03's `vault_reset()` convention (handles such as `auth:openrouter` leaked into later test files) and kept key-shaped literals (`sk-or-v1-...`) in source files. The helpers and the two tests that register secrets directly now reset the vault before and after; fake keys are built with `paste0()`; Global Constraints test line. |
| 15 | minor | Steps 2 and 4 of Tasks 2-9; Plan acceptance; Self-review | applied | Re-measured after the fixes: Task 2 `FAIL 8 \| PASS 47` / `PASS 99`; Task 3 `PASS 44`; Task 4 `FAIL 16 \| SKIP 1 \| PASS 44` / `SKIP 1 \| PASS 94`; Task 5 `FAIL 5 \| SKIP 1 \| PASS 94` / `SKIP 1 \| PASS 124`; Task 6 `FAIL 16` / `PASS 89`; Task 7 `FAIL 14 \| PASS 3` / `PASS 54`; Task 8 `FAIL 10 \| PASS 3` / `PASS 38`; Task 9 `FAIL 8 \| PASS 38` / `PASS 110`; all files `SKIP 1 \| PASS 476` (Windows `PASS 477`). The red steps of Tasks 4, 6 and 7 now give exact summaries (`testthat::set_max_fails(Inf)`). Acceptance rows 5c, 7a, R1 and R2 name the new tests. |
| 16 | minor | Task 9 token revocation (04 §7.18 "revokes it when the session's child exits") | rejected | P20 starts a new Codex child each turn and its builtin:cli `request_params` hook calls `mcp.serve_ensure` before every Codex request (`pcli_codex_ensure(ctx$session)`, the token read with `pcli_codex_env(h)`) expecting the session's token, and P19's `cli` backend calls the service once before the child's first run, so revoking at each child exit would break the consumers; the token lives only in that session's child environments and is revoked at `session_shutdown`, `stop()` or `gptr_mcp_serve(stop = TRUE)`. Recorded as ambiguity 22. |
| 17 | minor | Tasks 2 and 9 call `secret_value()` outside P04/P03 (04 §7.3) | rejected | No sanctioned alternative exists: RFC 6749 §6 puts the refresh token in the form body while P04 materialises handles only in headers, and P20 requires the token value in the Codex snippet; both calls are bound to the handle's own origin. Already recorded as ambiguity 2. |
| 18 | minor | Task 7 `mcp_member()` connects when `gptr$mcp$<server>$<tool>` is resolved (04 §5.3 "no I/O" of `$.gptr_gateway`) | rejected | The no-I/O rule concerns the gateway's first `$`; 04 §5.3 lets `gptr_ns` nodes "resolve the next path element lazily", 05 asks for closures "with lazy connect", and the closure's formals need the tool's schema. |
| 19 | minor | Task 6 foreign servers are startable by name without `gptr_mcp_add()` | rejected | Report 16's importer design turns import on for user-level files and imports project-level files only in trusted projects (the plan's `startable` rule); the `mcp.import` setting removes a harness, foreign servers are never advertised in the prompt (D-14), and copying into gptr's file stays `gptr_mcp_add()`. |

## Cross-plan consolidation log

Consolidation of 2026-10-01 against 04 (§7.0 `mcp.serve_ensure` `function(session)`, §8.1 adapters hold ids), 05 (P18, P20) and P20's current text (L93, L3178, L3599-3666, L4366, its ambiguity 1 and review item 1). Both issues concern prose only: P18's code already accepts a `gptr_session` or its id (`mcp_session_resolve()`), and P20's code passes the session object. The handle shape (`config$codex = list(args, env)`, `token_env`) already matched P20. Every R block was re-extracted and parsed with `Rscript --vanilla`, and none contains a left arrow or `%>%`. Test and expectation counts are unchanged.

| # | Lens | Severity | Location | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | interfaces | minor | Global Constraints (classes, services); Task 9 Produces; acceptance rows 7a and R1; consumer and resumption notes; ambiguities 19, 20 and 22; review rows 1 and 16 | applied | Renamed P20's consumers to their current names: `cli_codex_env(h)` is now `pcli_codex_env(h)`, and `cli_codex_mcp()` is now `pcli_codex_ensure(session)`, which builtin:cli's `request_params` hook calls. The service call is now described as `mcp.serve_ensure(ctx$session)` with the session object; P18 still also accepts an id. Ambiguity 20 keeps the design that resolves ids through the weak index and names P20's current call. Review row 1, a historical entry, gains a note saying that P20 has since moved the call into the hook. |
| 2 | shared-names | minor | the same lines as issue 1 | applied | The consumer note and ambiguity 20 now say that P20's `request_params` hook calls `mcp.serve_ensure(ctx$session)` (through `pcli_codex_ensure()`) before each Codex request and stores url, port and the session's token by session id. The adapter reads that record by `opts$session` through `pcli_codex_mcp(opts)` and never calls the service. Task 9 Produces adds that the adapter passes the value as `start$env`, which P05 hands to `child_env("cli-codex", set = )`. Code comments that named the old flow were updated: `mcp_session_remember()`, `mcp_serve_token()`, `mcp_client_snippets()` and the plan-mode test. In Task 9's fork test, the repeated call now passes the session object `f`, as P20's hook does. A call by id checks that the id gives the same token. The two checks share one `expect_identical()`, so Task 9 still shows `PASS 110` and the suite still shows `PASS 476`. `mcp_session_resolve()` still accepts an id. |
| F1 | finalize | minor | Task 2 `tests/testthat/fixtures/mcp/oauth.R`, Task 4 `tests/testthat/fixtures/mcp/server.R` (the `%\|\|%` definitions) | applied | Consolidation lint rows `P18_L00488.R` line 10 and `P18_L02137.R` line 11 (`object_name_linter`). The two standalone fixture scripts define `%\|\|%` because base R has it only from 4.4.0 and the package depends on R >= 4.2.0; an operator's name is fixed, so each definition now carries `# nolint: object_name_linter.`, with the reason on a comment line above it (P01's precedent in `aaa-state.R` and `fixtures/mock_server.R`). No behaviour change. |
| F2 | finalize | minor | Task 4 `tests/testthat/fixtures/mcp/server.R` (`TOOLS`) | applied | Consolidation lint row `P18_L02137.R` line 92 (`object_name_linter`). The script-local `TOOLS = tool_defs()` is renamed `tool_list`, with its three uses in `list_page()`. No other plan's code uses the name (the cross-plan index lists only this definition; P22's consolidation log names the file's old head in prose only, which is left as a historical record). No behaviour change. |
| F3 | finalize | minor | Task 4 `mcp_request()` (`R/mcp-client.R`) | applied | Found by linting the assembled P18 files after `pkgload::load_all()` with P01's linters, `object_usage_linter` included, as P01's A3 gate runs them on the whole package: lintr checks a function literal passed to `assign()` on its own, so `timeout` and `on_progress` (arguments of `mcp_request()`) were reported as undefined globals (3 lints). The progress callback is now a named closure `on_tick` that `assign()` stores; behaviour unchanged (Task 4 red and green summaries unchanged). |
| F4 | finalize | major | Task 9 `gptr_mcp_serve()`, new `mcp_serve_session()`, `mcp_token_new()`, `mcp_token_lookup()`, `mcp_token_revoke()`, `mcp_tokens_env()`, `mcp_serve_busy()`, `mcp_serve_start()`, `mcp_serve_stop()`, `mcp_http_route()`; Task 8 roxygen of `mcp_dispatch()` and `mcp_gate_idle()` | applied | Consolidation finding (ambiguity 1): requests on the user's own token were served through a session-less `ctx_new(NULL)`, but 04 §6.3 says "a nested call of a dedicated session (`kind = "chat"`, label `mcp`) whose home is `envir`", and IC-58 says "The explicit user handle keeps its dedicated session". The reason for the deviation is gone: P01's `arch_contract_edges()` now admits the `mcp-*.R` -> `session_new()` edge. `gptr_mcp_serve()` now creates the session with `mcp_serve_session(envir)` = `session_new(<model setting or "mcp/serve">, <mode setting, default "manual">, home = envir, kind = "chat")`. It keeps it as `the$mcp_server$user = list(key = <sha256 of the user's token>, session)`, binds the token to it in `the$mcp_tokens` like a session-bound token, records the token handle as the session's live `mcp_token`, and releases it in `mcp_serve_stop()`. `mcp_http_route()` now routes every token the same way: the target is the token's session, and the user's token alone falls back to `the$mcp_server$envir` when P06 keeps no home for a function-frame `envir` (R2). The `""` id of a session-less token is gone: `mcp_token_new()` requires a session, `mcp_token_lookup()` drops a token whose session was collected and returns the record with its `key`, and `mcp_serve_busy()` loses its special case (the dedicated session never runs, so it is busy in a nested pump as before). Ambiguity 1 is rewritten with the consequences: the mode is fixed at start; `-32002` in a nested pump; usage rolls up to the session alone; no field for the label `mcp`; the session becomes `gptr_last()` like every top-level `session_new()`, which the roxygen now says. The layering test was confirmed to see the new edge (see Executed validation). |
| F5 | finalize | minor | Task 9 tests; Steps 2 and 4; Plan acceptance (final command, rows 4 and R1); Executed validation | applied | The test "an r call through the server is gated ..." now shows that the dedicated session keeps its mode when the `mode` option changes, and that a restart applies the new mode (2 more expectations). The new test "the user's token has a dedicated chat session; its usage stays its own (IC-58)" (12 expectations) checks these things: kind `chat`, mode, no parent, home `envir`, the live `mcp_token` and the token record's id and key; a write on the user's token is denied by the session's manual mode while the user's auto-mode session exists; a usage row charged to the session with P06's `usage_add()` appears in `gptr_usage(s)` and `gptr_usage()` but leaves `gptr_usage()` of the user's session unchanged; `stop()` releases the session and revokes the token. In "both client eras work ...", `local_gptr_options(mode = "auto")` now comes before `gptr_mcp_serve()`, because the session takes its mode at start. Re-measured counts: Task 9 red `FAIL 8` -> `FAIL 9` (`PASS 38`), green `PASS 110` -> `PASS 124`; all P18 files `PASS 476` -> `PASS 490` (Windows 477 -> 491); with `test-lint-rules.R` 481 -> 495. |
| F6 | finalize | minor | Global Constraints (server, package state, layering); Functions consumed (P06); File Structure (`R/mcp-server.R`, `test-mcp-server.R`); Task 9 Interfaces and text; roxygen of `gptr_mcp_serve()`; Plan acceptance lint/arch expectation | applied | The prose now matches row F4. It names the dedicated session, `the$mcp_server$user` and `mcp_serve_session()`, and lists `session_new()` among P06's consumed functions as the one contract edge outside the IC-33 kernel SDK, and `setting_get()` (settings `model` and `mode`) among Task 9's. It also lists the tests' P06 functions (`session_home()`, `gptr_usage()`, `usage_add()`, `usage_conform()`). The busy rule now speaks of "the user's token (its dedicated session never runs)" instead of "the user's own serving context". The arch-layers expectation now admits `session_new()` through P01's `arch_contract_edges()`. The roxygen paragraph was reflowed to 100 columns. Every `r` block was re-extracted and parses under `Rscript --vanilla` (27 blocks, no `<-` token, no `%>%`, ASCII only, no line over 100 characters). |

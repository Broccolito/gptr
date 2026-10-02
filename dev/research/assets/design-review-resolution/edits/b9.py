from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/spec/04-interface-contract.md"
pairs = [
("""| `send(obj)` | `process_jsonl` only: writes one JSON line to the child's stdin (`write_all()`) |
| `run`, `session` | ids, for events and nested calls |""",
"""| `send(obj)` | `process_jsonl` only: writes one JSON line to the child's stdin (`write_all()`) |
| `gate(call)`, `mcp_dispatch(message)`, `tool_result(result, call)` | injected by `provider_stream()` from the run: the run's `perm_check()`, the `mcp.dispatch_local` service bound to the session, and `tool_result_message()`; L1 adapters use only these, never L2+ functions (IC-33) |
| `run`, `session` | ids, for events and nested calls |"""),
("""**`capabilities`** (named list; missing entries mean `FALSE`/`NULL`): `images_in_results`, `tool_addition`,
`structured_output`, `reasoning_replay`, `parallel_tools` (lgl);""",
"""**`capabilities`** (named list; missing entries mean `FALSE`/`NULL`): `images_in_results`, `tool_addition`,
`structured_output`, `reasoning_replay`, `parallel_tools`, `forced_tool_choice` (lgl; `FALSE` for Anthropic 5.x
models, IC-71); `request_params` (chr: non-prefix request fields a `request_params` handler may patch, IC-69);"""),
("""| `reactor_http(...)` | queues one HTTP transfer (admitted while global `gptr.max_active` and per-provider limiter slots allow); `spec` from `build()`; every handle sets `pipewait = 0L`, `connecttimeout`, `low_speed_limit = 1`, `low_speed_time = idle + 30` as a backstop and no total timeout;""",
"""| `reactor_http(...)` | queues one HTTP transfer (admitted while global `gptr.max_active` and per-provider limiter slots allow); `spec` from `build()`; every handle sets `pipewait = 0L`, `followlocation = 0L` (a 3xx is `gptr_error_redirect`, never retried, IC-64), `connecttimeout`, `low_speed_limit = 1`, `low_speed_time = idle + 30` as a backstop and no total timeout;"""),
("""| `reactor_enqueue_tool(run, fn)` | appends `fn` (a zero-argument function executing one R-evaluating tool) to the FIFO; at most one runs per iteration, only for runs in `allow_runs` of the innermost pump |
| `reactor_pump(...)` | the only blocking wait in gptr. One iteration: admit queued transfers; `processx::poll(c(processx::curl_fds(curl::multi_fdset(pool)), <pipes>), ms = min(next timer, slice_ms))`; `curl::multi_run(timeout = 0)`; read ready pipes; fire due timers; run tasks; `later::run_now(0)` when later is loaded; run at most one FIFO tool whose run is in `allow_runs` (all runs when `NULL`). Loops until `until()` is `TRUE` (returns `TRUE`) or `timeout` seconds (returns `FALSE`). Re-entrant: a nested pump (a sub-agent started inside an `r` evaluation) passes `allow_runs = <its run ids>`. R interrupts propagate out of the pump to the caller's interrupt policy |""",
"""| `reactor_enqueue_tool(run, fn)` | appends `fn` (a zero-argument function executing one R-evaluating tool) to the FIFO; at most one runs per iteration, only for runs in `allow_runs` of the innermost pump |
| `reactor_pump(...)` | the only blocking wait in gptr; it tracks its depth (IC-57). One iteration: admit queued transfers; `processx::poll(c(processx::curl_fds(curl::multi_fdset(pool)), <pipes>), ms = min(next timer, slice_ms))`; `curl::multi_run(timeout = 0)`; read ready pipes and drain pending stdin buffers (IC-60); fire due timers; run tasks; `later::run_now(0)` only at depth 1, or at depth > 1 when `allow_runs` holds a CLI child served by the MCP server (whose handler then refuses requests of runs outside `allow_runs` with the retryable JSON-RPC error `-32002`); run at most one FIFO tool whose run is in `allow_runs`. `allow_runs` defaults to `NULL` (all runs) only when `run_current()` is `NULL`, else to `character()`; a nested pump (a sub-agent, System 1 or MCP call made inside an `r` evaluation) passes the ids it waits for. Loops until `until()` is `TRUE` (returns `TRUE`) or `timeout` seconds (returns `FALSE`). R interrupts propagate out of the pump to the caller's interrupt policy |"""),
("""**Admission and rate limits** (`http-retry.R`): `ratelimit_update(provider, headers)` reads
`anthropic-ratelimit-*`, `x-ratelimit-*` and `retry-after*` into a per-provider token bucket;""",
"""**Admission and rate limits** (`http-retry.R`): `ratelimit_update(provider, headers)` reads
`anthropic-ratelimit-*`, `x-ratelimit-*` and `retry-after*` into a per-provider token bucket that also holds the
provider record's static `rate` (IC-64; System 1 admission is process-wide); HTTP-date `retry-after` values go
through the locale-independent `parse_http_date()` (`month.abb`, UTC; unparsable -> backoff);"""),
("""**Wire log** (INFRA-28, `gptr.wire_log`): one redacted JSON line per request start and per terminal event""",
"""**Wire log** (INFRA-28, `gptr.wire_log`; one file per session, each line open-append-close, IC-59, IC-65): one
redacted JSON line per request start and per terminal event"""),
("""| `sse_splitter()` | environment with `push(raw)` -> list of events `list(event = chr(1) \\| NULL, data = chr(1), id = chr(1) \\| NULL, retry = num(1) \\| NULL)` (fields joined per the SSE spec; comment lines dropped; boundaries found with `grepRaw()` on raw bytes; the incomplete tail carried; each complete event decoded with `rawToChar()` and marked UTF-8) and `flush()` -> the final unterminated event, if any |""",
"""| `sse_splitter()` | environment with `push(raw)` -> list of events `list(event = chr(1) \\| NULL, data = chr(1), id = chr(1) \\| NULL, retry = num(1) \\| NULL)` (fields per the SSE spec: LF, CRLF and lone CR line ends, a CR at the end of a chunk held until the next chunk, a leading BOM stripped, comment lines dropped, `data:` lines joined with `"\\n"`, the **last** `event:` field wins; boundaries found with `grepRaw()` on raw bytes; the incomplete tail carried; each complete event decoded with `rawToChar()` and marked UTF-8; IC-64) and `flush()` -> the final unterminated event, if any |"""),
("""Measured cost target: 20,000 deltas in under 1 s CPU; identical output under random re-chunking including splits
inside multi-byte characters (INFRA-23).""",
"""Measured cost target: 20,000 deltas in under 1 s CPU; identical output under random re-chunking including splits
inside multi-byte characters and inside CRLF pairs, CR-only streams and duplicate `event:` fields (INFRA-23)."""),
("""- **`cli-claude`** (provider `claude-cli`, alias `claude_code`; experimental). `start$args` are exactly
  `-p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --tools ""
  --strict-mcp-config --setting-sources "" --disable-slash-commands --mcp-config <file> --permission-prompt-tool
  stdio --system-prompt-file <file> --model <full id>` (never `--bare`);""",
"""- **`cli-claude`** (provider `claude-cli`, alias `claude_code`; experimental). `start$args` are exactly
  `-p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --tools ""
  --strict-mcp-config --setting-sources "" --disable-slash-commands --mcp-config <file> --permission-prompt-tool
  stdio --permission-mode default --allowedTools mcp__gptr__* --system-prompt-file <file> --model <full id>`, plus
  `--max-turns <n> --max-budget-usd <x>` when a budget is in force (IC-65, IC-66) (never `--bare`; a CLI whose
  `-p` defaults to bare is handled by the probe of IC-65; the binary is native, never the `claude.cmd` shim);"""),
("""`control_request` lines by subtype: `mcp_message` -> `mcp_dispatch_local(message, session)` (P18) answered as
  `{"type":"control_response","response":{"subtype":"success","request_id":…,"response":{"mcp_response":…}}}`;
  `can_use_tool` -> `perm_check()` (P06) answered `{"behavior":"allow","updatedInput":…}` or
  `{"behavior":"deny","message":…}`; unknown subtypes -> an error response.""",
"""`control_request` lines by subtype: `mcp_message` -> `opts$mcp_dispatch(message)` (P18's
  `mcp_dispatch_local()`, the single gate for gptr's tools) answered as
  `{"type":"control_response","response":{"subtype":"success","request_id":…,"response":{"mcp_response":…}}}`;
  `can_use_tool` (not sent for the pre-allowed `mcp__gptr__*` tools) -> `opts$gate(call)` answered
  `{"behavior":"allow","updatedInput":…}` or `{"behavior":"deny","message":…}`; unknown subtypes -> an error
  response. After `system/init`, an `apiKeySource` other than `"none"` aborts the turn with `gptr_error_billing`."""),
("""- **`cli-codex`** (provider `codex`, alias `codex`). One `codex exec --json --ignore-user-config -c
  mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp -c mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN -c
  mcp_servers.gptr.tool_timeout_sec=3600 --sandbox <read-only | workspace-write> -` per turn, the prompt on stdin
  (`write_all()`), `GPTR_MCP_TOKEN` only in the child's environment (`child_env("cli-codex", set =)`); the MCP
  server comes from the `mcp.serve_ensure` service (P18);""",
"""- **`cli-codex`** (provider `codex`, alias `codex`). One `codex exec --json --ignore-user-config
  --skip-git-repo-check -m <full id> -C <wd> -c mcp_servers.gptr.url=http://127.0.0.1:<port>/mcp -c
  mcp_servers.gptr.bearer_token_env_var=GPTR_MCP_TOKEN -c mcp_servers.gptr.default_tools_approval_mode="approve" -c
  mcp_servers.gptr.required=true -c mcp_servers.gptr.tool_timeout_sec=3600 --sandbox <read-only | workspace-write>
  -` per turn (resume: `codex exec resume <thread> --json ... -c sandbox_mode=<mode> -`, IC-65), the prompt on
  stdin (`write_all()`), `GPTR_MCP_TOKEN` (a token bound to this session, IC-58) only in the child's environment
  (`child_env("cli-codex", set =)`); the MCP server comes from the `mcp.serve_ensure` service (P18);"""),
("""`tool_execution_*` events), `turn.completed{usage}`, `turn.failed{error}`, `error` [08 §2.E]. Sandbox mapping:
  `plan` -> `read-only`; `manual` -> `read-only` (R tools gated by gptr); `edits`/`auto` -> `workspace-write`.""",
"""`tool_execution_*` events), `turn.completed{usage}`, `turn.failed{error}`, `error` [08 §2.E]; gptr counts turns
  and cancels at the cap, with `gptr.cli_turn_timeout` per exec. Sandbox mapping (IC-65): `plan`, `manual` and
  `edits` -> `read-only` (file changes go through gptr's gated `write`/`edit` over MCP); `auto` ->
  `workspace-write`, with control files hashed before and a files-checkpointer walk after each exec; native
  Windows falls back to `read-only` with a warning when the sandbox probe fails."""),
]
apply(P, pairs)

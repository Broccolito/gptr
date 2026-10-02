# Track 06 — Pi sub-agents, MCP client, tool search, codemode → R design for gptr

Date: 2026-09-29. Researcher: track-06 agent. Pi source: commit `1b34779` (2026-09-29).

Conventions used in this report

- `$PI` = `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/pi`
- `$W` = `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06` (prototype directory; temporary, so every prototype and test file is reproduced in full in section 5; the small helper scripts `dbg3.R`, `chk.R` and similar are *not* reproduced, and the claims resting on them were re-checked independently in the verification log)
- Evidence labels: **VERIFIED** (I read the cited source or ran the cited code and saw the result), **LIKELY** (inferred from verified facts, not directly observed), **UNCERTAIN** (not checked; needs a test, usually on Windows).
- Citations to local source are `file:line`. Citations to experiments are `executed: <file> -> <observation>`; the full output is in section 5.
- All experiments ran on macOS (Darwin 25.6.0), R 4.4.3, `Rscript --vanilla`. **Nothing was run on Windows or Linux.** No paid model API call was made.

---

## 1. Executive summary

1. **Sub-agents in Pi are not core; they are a ~1000-line example extension** that registers one tool, `subagent`, and spawns a separate `pi` process per sub-agent with `--mode json -p --no-session`. Context isolation is simply process isolation plus a fresh conversation that contains only the agent's system prompt and `Task: <task>`. (VERIFIED, `$PI/packages/coding-agent/examples/extensions/subagent/index.ts:4-5,300-341`)
2. **A Pi agent definition is a Markdown file with YAML frontmatter**: `name` and `description` are required, `tools` (comma string or YAML list) and `model` are optional, and the body is the system prompt. This is the same file shape Claude Code uses in `.claude/agents/*.md`, so gptr can read both. (VERIFIED, `agents.ts:34-39,88-103`; Claude Code docs)
3. **Three modes, hard limits**: single, parallel (at most 8 tasks, 4 concurrent), chain (sequential, `{previous}` is replaced by the prior step's final text, stops at the first failure). Parallel output returned to the parent model is capped at 50 KB per task. (VERIFIED, `index.ts:33-36,550-686`)
4. **Pi's example does not roll sub-agent cost into the parent's usage**; usage is only kept in the tool result `details` for display. gptr should do better and return it as tool-result usage. (VERIFIED, `index.ts` returns `{content, details, isError}` only)
5. **Pi ships its own MCP client (`@earendil-works/pi-mcp`, v0.99.1) with no dependency on the official SDK**: a transport-neutral JSON-RPC core, stdio and Streamable HTTP transports, and an OAuth subset adapted from the MIT-licensed official TypeScript SDK v1.29.0. It requests protocol `2025-11-25` and accepts `2025-06-18`, `2025-03-26`, `2024-11-05`. (VERIFIED, `$PI/packages/mcp/README.md:3,112,118`, `protocol/types.ts:4-9`)
6. **Pi's MCP config is the common `mcpServers` JSON shape** in `~/.pi/agent/mcp.json` and `<project>/.pi/mcp.json` (project file only when the project is trusted). Tools are named `mcp__<server>__<tool>`, sanitised to `[A-Za-z0-9_-]`, capped at 64 characters with a sha256 suffix. (VERIFIED, `docs/mcp.md:7-48`, `extensions/mcp/tools.ts:80-89`)
7. **Pi's default for MCP tools is *not* to declare them to the model.** Default exposure is `codemode`: tools are callable only from model-written scripts. Other exposures: `codemode-deferred`, `deferred` (loaded by `tool_search`), `direct`, `hidden`; `toolExposure` overrides per tool with `*` patterns. (VERIFIED, `core/mcp-servers.ts:8-42,141-149`)
8. **`tool_search` is a BM25 ranker (k1 = 1.2, b = 0.75, default limit 8)** over tool name, description, schema property names and descriptions, and namespace. Matches are added to the active tool set, so they are declared from the next model call. I ported it to 48 lines of base R and it reproduces the reference scores to 1e-12. (VERIFIED, `extensions/tool-search/tool.ts:117-156`; executed: `test_bm25.R`)
9. **Codemode = the model writes JavaScript that calls tools as `await tools.<name>(args)`** inside a QuickJS VM compiled to WebAssembly, one fresh worker thread and VM per execution, 256 MB heap limit, no timers, network, or file system. Tool declarations are rendered as TypeScript from JSON Schema under a 3000-token budget. Only the script's output reaches the model. (VERIFIED, `$PI/packages/codemode/README.md`, `extensions/codemode/tool.ts:131-156,223`, `execute.ts:48`)
10. **The R analogue needs no sandbox VM and no second language**: gptr's primary tool already evaluates R in the live session. The equivalent is *tools-as-R-functions*: every tool (built-in, extension, MCP, sub-agent) is an R function generated from its JSON Schema, routed through the harness tool pipeline. Prototyped and verified, including loops over in-memory objects, schema-directed JSON coercion, permission hooks and a bounded nested-call record. (executed: `test_tools_fn.R` -> 12/12 pass)
11. **A pure-R MCP client is feasible and small.** My prototype (JSON-RPC core, stdio via processx, Streamable HTTP via httr2, SSE resumption, OAuth with PKCE, dynamic client registration, refresh and step-up) passed 27 stdio checks, 19 HTTP/OAuth checks and 3 streaming checks against local fixtures, and completed a real handshake with Claude Code's MCP server (`claude mcp serve`: protocol `2025-11-25`, 29 tools; 27 tools on the verifier's re-run the same day, so the count depends on the Claude Code version and configuration). (executed: `test_stdio.R`, `test_http.R`, `test_stream.R`, `test_interop.R`)
12. **`httr2::resp_stream_sse()` cannot be used for MCP resumption**: it drops events whose `data` is empty (the MCP priming event) and ignores `retry`. gptr needs its own 25-line SSE parser on top of `httr2::resp_stream_lines()`. (VERIFIED by reading `httr2:::parse_event` in httr2 1.2.2, and re-verified in the current CRAN release httr2 1.3.0 (2026-07-13), whose `parse_event()` still returns `NULL` for empty `data`, loses that event's `id`, and has no `retry` branch; own parser executed in `test_http.R`, `test_stream.R`, also under httr2 1.3.0.) Two httr2 1.3.0 changes matter for that parser: `resp_stream_lines()` no longer treats a bare CR as a line end (the SSE format allows it; MCP servers in practice send LF or CRLF), and its `warn` argument is soft-deprecated (the prototype passes `warn = FALSE`, which does not warn; drop it in gptr).
13. **Encoding pitfall found by experiment**: in a C locale, `cat()` or `writeLines()` of a string marked UTF-8 writes `<U+00E9>` escapes, and UTF-8 bytes held in a string that is *not* marked UTF-8 are turned into `<c3><a9>` by `jsonlite::toJSON()`/`fromJSON()`; either way JSON on pipes is corrupted. A connection opened with `file(..., encoding = "UTF-8")` does not help. Every JSON line gptr writes to a pipe or file must use `writeLines(enc2utf8(x), con, useBytes = TRUE)` or `writeBin()`, and every line read from a pipe must be marked UTF-8 before parsing. (executed: `dbg3.R`, not reproduced in this report; re-checked by the verifier with `LC_ALL=C`: marked string via `cat()` -> `3c 55 2b 30 30 45 39 3e` = `<U+00E9>`; unmarked bytes via jsonlite -> `<c3><a9>`; `useBytes = TRUE` and `writeBin()` -> `c3 a9`)
14. **jsonlite pitfall found by experiment**: with `auto_unbox = TRUE` a length-1 R vector is sent as a scalar, which breaks tools whose schema says `array`. Arguments must be coerced by schema before serialisation. (executed: `test_stdio.R` -> "WITHOUT I(): auto_unbox sends a scalar -> server rejects")
15. **Sub-agent backends for gptr, measured**: a `callr::r_bg()` child costs about 0.3-0.4 s to start; exporting a 381 MB object to it by serialisation took 1.1-1.5 s, while a forked child (`parallel::mcparallel`, Unix only) saw the same object copy-on-write in 0.12-0.18 s. An *inline* sub-agent (separate history, overlay environment on the live session) has no cost and is unique to gptr. (executed: `test_backends.R`)
16. **Recommended default**: `backend = "inline"` for single sub-agents that need session objects, `backend = "process"` (callr) for parallel work, `backend = "fork"` opt-in on Unix terminals only. Parallel pool verified: 6 tasks with concurrency 4 finished in about 2.0 s against 4 s of sleeps; a user interrupt sent after 1 s ended the pool and its children 0.2-0.45 s later. (executed: `test_subagents.R` -> 23/23 pass on the recorded run; `test_abort_pids.R`)
17. **Harness-agnostic MCP config (REQ-30) is practical**: one loader read gptr's own file, `.mcp.json`, Cursor, VS Code (`servers` key), Codex TOML, Pi and mcptools files, with `${VAR}`, `${VAR:-default}`, `${env:VAR}`, `{env:VAR}`, `$VAR` and `!command` values. A unit trap: Claude Code's `timeout` is milliseconds, Pi's and Codex's are seconds. (executed: `test_config.R` -> 18/18 pass)
18. **Durable/coordinator ideas worth borrowing**: commit before show, idempotent `requestId` for re-runs, per-tool `replay: "safe"` declaration, task ownership (aborting a call aborts the child conversation it owns), steer/follow-up/reject inbox, reset-with-handoff-note, generation-tagged worker retirement. Not worth borrowing for v1: the socket coordinator, CBOR protocol and Chord documents.
19. **CRAN posture**: own code stays pure R. Proposed hard dependencies for this track are `jsonlite`, `processx`, `callr`, `httr2` (with `openssl` arriving through httr2). `httpuv` + `later` (OAuth loopback listener) and `yaml` can be `Suggests` with fallbacks. Base R `serverSocket()` must not be used for the OAuth callback because it listens on all interfaces. (executed: `test_stream.R` -> `lsof` shows `*:port`)

---

## 2. Findings

### 2.1 Sub-agents in Pi

Source: `$PI/packages/coding-agent/examples/extensions/subagent/` (`index.ts` 1038 lines, `agents.ts` 157 lines, `README.md`, four agents, three prompt templates).

#### 2.1.1 Where sub-agents live

- The coding agent has no built-in sub-agent concept. `grep` over `docs/*.md` for "subagent" returns nothing. The capability is an *example extension* that the user symlinks into `~/.pi/agent/extensions/subagent/`. (VERIFIED, `README.md:32-53`)
- A published package `pi-subagents` exists on pi.dev with background runs, seven built-in agents and `maxSubagentSpawnsPerRun` default 64. I only read its package page, not its source. (Page content re-checked 2026-09-29: seven built-in agent rows `scout`, `researcher`, `evidence-auditor`, `worker`, `reviewer`, `oracle`, `delegate`, plus a separate `/council` feature; `maxSubagentSpawnsPerRun` "defaults to 64". Behaviour LIKELY, https://pi.dev/packages/pi-subagents)
- `@earendil-works/pi-durable` documents a second, in-process pattern: a `subagent` tool that creates a child *conversation* owned by the tool's task (section 2.5).

#### 2.1.2 Agent definition files

`agents.ts:34-39` defines the raw frontmatter, `agents.ts:11-19` the loaded config:

| Field | Required | Type accepted | Meaning |
|---|---|---|---|
| `name` | yes | string | Identifier used in the tool call |
| `description` | yes | string | Shown in listings |
| `tools` | no | `"read, grep"` (comma string) or `[read, grep]` (YAML list) | Passed as `--tools`; when absent the child uses Pi's default tools |
| `model` | no | string | Passed as `--model`; when absent the child inherits the dispatcher's model *and* thinking level |
| body | — | Markdown | System prompt, passed with `--append-system-prompt` |

- A file is skipped, without an error, when `name` or `description` is not a string. Anything that is not a string or list in `tools` yields no tool restriction. The stated reason: "a single bad file must not take down every other agent in the same directory". (VERIFIED, `agents.ts:41-60,90-92`)
- Only `*.md` regular files or symlinks directly inside the directory are read (not recursive). (VERIFIED, `agents.ts:76-78`)
- Locations: user `~/.pi/agent/agents/` (`getAgentDir()` = `$PI_CODING_AGENT_DIR` or `~/.pi/agent`), project = the nearest `.pi/agents` directory found by walking up from the working directory. (VERIFIED, `agents.ts:116-130`, `src/config.ts:532-562`)
- Scope parameter `agentScope`: `"user"` (default), `"project"`, `"both"`. With `"both"` a project agent replaces a user agent of the same name. (VERIFIED, `agents.ts:132-146`)
- Agents are re-discovered on every tool invocation, so edits apply mid-session. (VERIFIED, `index.ts:489`, `README.md:176`)
- Sample agents: `scout` (haiku, `read, grep, find, ls, bash`), `planner` (sonnet, read-only tools), `reviewer` (sonnet, bash restricted by prompt only), `worker` (sonnet, all default tools). (VERIFIED, `agents/*.md`)

#### 2.1.3 Security model

- Project agents are repo-controlled prompts. They are loaded only when the model passes `agentScope: "project"` or `"both"`.
- Before running a project agent the tool asks `ctx.ui.confirm("Run project-local agents?", ...)`, unless there is no UI, the project is already trusted, or `confirmProjectAgents: false`. (VERIFIED, `index.ts:520-548`)

#### 2.1.4 Spawning

- One OS process per sub-agent: `spawn(command, args, { cwd, shell: false, stdio: ["ignore", "pipe", "pipe"] })`. (VERIFIED, `index.ts:346-350`)
- Arguments, in order (VERIFIED, `index.ts:300-341`):

```
--mode json -p --no-session
[--model <agent.model or dispatcher "provider/id">]
[--thinking <dispatcher thinking level>]        # only when the agent has no model of its own
[--tools <comma separated agent.tools>]
[--append-system-prompt <temp file path>]
"Task: <task text>"
```

- The system prompt is written to `<os.tmpdir()>/pi-subagent-XXXXXX/prompt-<safe agent name>.md` with mode `0o600`, and the file and directory are removed in a `finally` block. (VERIFIED, `index.ts:239-247,426-439`)
- `getPiInvocation()` re-runs the current script with the current runtime when possible, falls back to the executable itself when it is not `node`/`bun`, and finally to `pi` on the PATH. (VERIFIED, `index.ts:249-263`)
- There is no in-process mode in this extension.

#### 2.1.5 How results and usage flow back

- The child writes JSONL events on stdout (`docs/json.md`). The parent splits on `\n`, ignores lines that are not JSON, and handles two event types (VERIFIED, `index.ts:353-388`):
  - `message_end` with `message`: the message is appended to the result. For `role: "assistant"` it increments `turns`, adds `usage.input`, `usage.output`, `usage.cacheRead`, `usage.cacheWrite`, `usage.cost.total`, sets `contextTokens = usage.totalTokens` (last value wins), and records `model`, `stopReason`, `errorMessage`.
  - `tool_result_end` with `message`: appended. **This event name occurs nowhere else in the repository** (`grep -rn tool_result_end $PI/packages` finds only `index.ts:384`), and `docs/json.md` lists `tool_execution_end` instead. Tool results reach the parent anyway because the agent loop emits `message_end` for tool-result messages (`$PI/packages/agent/src/agent-loop.ts:939`). (VERIFIED for the grep and the emit site; that the branch is dead code is LIKELY)
- stderr is accumulated as a string for diagnostics. (VERIFIED, `index.ts:397-399`)
- Final output = the first `text` part of the last assistant message. (VERIFIED, `index.ts:170-180`)
- Failure = `exitCode !== 0` or `stopReason` is `"error"` or `"aborted"`. The text reported for a failure is `errorMessage || stderr || final output || "(no output)"`. (VERIFIED, `index.ts:182-191`)
- Streaming: after every message the tool calls `onUpdate` with the current partial result, so the TUI shows tool calls of the child live. (VERIFIED, `index.ts:324-331,381,386`)
- Return value to the parent model:
  - single: final text, or `Agent <stopReason|failed>: <error text>` with `isError: true`.
  - chain: final text of the last step, or `Chain stopped at step N (<agent>): <error>`.
  - parallel: `Parallel: X/N succeeded` followed by one `### [agent] completed|failed (<stopReason>)` section per task, separated by `---`, each output truncated to 50 KB with the note `[Output truncated: N bytes omitted. Full output preserved in tool details.]`. (VERIFIED, `index.ts:193-202,669-685`)
- Usage is kept per result in `details.results[i].usage` and aggregated only by the renderer. The tool result carries no `usage` field, so the parent session's cost excludes sub-agent cost in this example. (VERIFIED, `index.ts:850-861` and the three `return` sites)

#### 2.1.6 Concurrency, abort, isolation

- Constants (VERIFIED, `index.ts:33-36`): `MAX_PARALLEL_TASKS = 8`, `MAX_CONCURRENCY = 4`, `COLLAPSED_ITEM_COUNT = 10`, `PER_TASK_OUTPUT_CAP = 50 * 1024`.
- More than 8 tasks returns the text `Too many parallel tasks (N). Max is 8.` without running anything. (VERIFIED, `index.ts:605-614`)
- The pool is `mapWithConcurrencyLimit`: `limit` workers each pull the next index until the list is exhausted; results keep input order. (VERIFIED, `index.ts:219-237`)
- Abort: the tool's `AbortSignal` sends `SIGTERM` and the call throws `Subagent was aborted`. A `SIGKILL` is scheduled after 5000 ms, but it is guarded by `if (!proc.killed)`, and Node sets `subprocess.killed` as soon as a signal was *delivered* ("The `killed` property does not indicate whether the child process has terminated", Node docs). After a successful `SIGTERM` the `SIGKILL` is therefore never sent, so a child that ignores `SIGTERM` keeps running. Do not copy this; gptr should check whether the process has actually exited (`p$is_alive()`) before escalating. (VERIFIED, `index.ts:410-424`; Node `child_process` docs)
- Isolation: separate process, `--no-session` (no session file is written), no parent history, tool set limited by `--tools`. The child does inherit the environment, the working directory (or the per-task `cwd`), the user's Pi settings, credentials and extensions. A child could therefore spawn sub-agents itself if the extension is installed; the example has no depth limit. (VERIFIED for the flags; the recursion remark is LIKELY)
- Exactly one mode must be given; otherwise the tool returns `Invalid parameters. Provide exactly one mode.` and the list of available agents. (VERIFIED, `index.ts:493-518`)

#### 2.1.7 Workflow prompt templates

`prompts/implement.md`, `scout-and-plan.md`, `implement-and-review.md` are ordinary prompt templates (frontmatter `description`, `$@` for the arguments) that tell the model to call the `subagent` tool with a `chain`. The graph is prose, executed by the model. (VERIFIED, `prompts/*.md`)

#### 2.1.8 Handoff (`examples/extensions/handoff.ts`)

- `/handoff <goal>` serialises the current branch (compaction summary plus kept entries when the branch was compacted), asks the current model to write a self-contained prompt with a fixed system prompt (sections `## Context`, files involved, `## Task`), lets the user edit the draft, then opens a new session with `parentSession` set to the old session file and the draft placed in the editor. (VERIFIED, `handoff.ts:20-40,57-78,131-139,167-183`)
- The generation call uses `cacheRetention: "none"` and a fresh `sessionId`. (VERIFIED, `handoff.ts:134-138`)
- Relevance: a lossy but portable way to move a conversation between providers (REQ-14) when message histories cannot be translated.

### 2.2 MCP in Pi

Sources: `$PI/packages/mcp` (library), `$PI/packages/coding-agent/src/extensions/mcp` (integration), `src/core/mcp-servers.ts`, `docs/mcp.md`.

#### 2.2.1 Configuration

- Files: `~/.pi/agent/mcp.json` (global) and `<cwd>/.pi/mcp.json` (project). The project file is read only when the project is trusted "because stdio servers run commands". Project entries replace global entries of the same name. (VERIFIED, `config.ts:98-107`, `docs/mcp.md:31`)
- Shape: top-level `mcpServers` object, plus optional top-level boolean `autoEnableCodemode` (default true; a project value overrides the global one). (VERIFIED, `config.ts:68-92`)
- Entry validation (VERIFIED, `core/mcp-servers.ts:152-196`):
  - server name must match `^[A-Za-z0-9_-]+$`
  - `type` is optional; `command` means stdio, `url` means Streamable HTTP; accepted explicit values are `stdio`, `http`, `streamable-http`; `sse` is rejected with "legacy SSE transport is not supported; use the streamable HTTP URL"
  - `url` must parse and be `http:` or `https:`
  - `args` array of strings, `env` and `headers` string maps, `cwd` string
  - `enabled` boolean, `timeout` positive number of **seconds** (default 60), `exposure` one of five values, `toolExposure` map
  - `oauth`: `clientId`, `clientSecret`, `callbackPort` (1-65535), `callbackUrl` (must be `http` on `localhost`, `127.0.0.1` or `[::1]`, no query or fragment, and must not contradict `callbackPort`), `scope`
  - invalid entries are skipped and reported; the other servers still load
- Value resolution for `env`, `headers` and `oauth.clientSecret` (VERIFIED, `core/resolve-config-value.ts:28-151,198-216`):
  - a value starting with `!` runs the rest as a shell command (10 s timeout, stdout trimmed; on Windows the configured shell is tried first)
  - `${NAME}` and `$NAME` are replaced by environment variables; `$$` is a literal `$`, `$!` a literal `!`
  - a missing variable is an error that names the variable
  - `${NAME:-default}` is **not** supported by Pi (it is by Claude Code)
- `~` and `~/...` (also `~\...` on Windows) are expanded in `command`, each argument and `cwd`. Relative `cwd` resolves against the session directory. (VERIFIED, `runtime.ts:88-94,113-119`)
- `pi mcp add|remove|list|login|logout` edit and inspect the files from a shell; the file is rewritten preserving its indentation. (VERIFIED, `docs/mcp.md:33-40`, `config.ts:168-182`)
- Extensions can register servers at runtime with `pi.registerMcpServer(name, config)`; a server of the same name in `mcp.json` wins. (VERIFIED, `core/mcp-servers.ts:198-237`, `index.ts:203-219`)

#### 2.2.2 Start-up, lifecycle, errors

- The MCP runtime module is loaded lazily, only when at least one enabled server exists, and one event-loop turn after `session_start` so the first render is not delayed. (VERIFIED, `extensions/mcp/index.ts:805-829`)
- All enabled servers connect concurrently at session start. The first prompt waits at most `DEFAULT_STARTUP_WAIT_MS = 10_000` for them; slower servers join when ready. (VERIFIED, `index.ts:79,833-848`)
- Connection states: `connecting`, `connected`, `disconnected`, `needs-auth`, `failed`, `closed`. (VERIFIED, `runtime.ts:52-56`)
- HTTP connects are retried after 250 ms and 1000 ms for transient errors (network `TypeError`, HTTP 408, 429, 5xx except 501). stdio connects are not retried. (VERIFIED, `runtime.ts:49-50,68-74,343-360`)
- A dropped connection becomes `disconnected` with the stderr tail (last 2000 characters) as the error, and the **next call reconnects lazily** through `getClient()`. (VERIFIED, `runtime.ts:240-247,422-430`)
- Tool calls are never retried "since they may have run". Read-only requests (resources) are retried once after a transient HTTP error. A `404` with a session id (`McpSessionExpiredError`) is retried once on a new session. (VERIFIED, `runtime.ts:277-304`)
- Problems are reported once after start-up: config errors, failed servers, servers that need sign-in. (VERIFIED, `index.ts:408-420`)
- `notifications/tools/list_changed` triggers a new `tools/list`. Tools cannot be unregistered, so withdrawn tools are re-registered with exposure `hidden`. (VERIFIED, `runtime.ts:375-377,432-442`, `index.ts:272-277`)
- Servers without the `tools` capability are not asked for tools. (VERIFIED, `runtime.ts:383-388`)
- Server log notifications (`notifications/message`) are appended to `~/.pi/agent/mcp.log` as `<ISO time> [<server>] <level> <logger>: <message>`, rotated to `mcp.log.1` past 5 MB. (VERIFIED, `log.ts:10,26-32,50-56`)
- The client sends `roots: [{ uri: <file URL of cwd>, name: <basename> }]` and client name `pi`. (VERIFIED, `runtime.ts:363-368`)

#### 2.2.3 Client core (`packages/mcp/src/client.ts`)

- `DEFAULT_REQUEST_TIMEOUT_MS = 30_000` in the library; the coding agent passes 60 s. `MAX_LIST_PAGES = 1_000`. (VERIFIED, `client.ts:38-39`, `runtime.ts:47`)
- `connect()`: `transport.start()`, `initialize` request, check the result shape, check that the server's version is one of the supported four, `transport.setProtocolVersion()`, send `notifications/initialized`, state `connected`. Any failure closes the transport. (VERIFIED, `client.ts:202-248`)
- Request ids are integers from 1. When the caller passes `onProgress`, `_meta.progressToken` is set to the request id. (VERIFIED, `client.ts:402-413`)
- A progress notification re-arms the request timeout. (VERIFIED, `client.ts:531-542`)
- Timeout or abort rejects the request and sends `notifications/cancelled` with `requestId` and `reason`; `initialize` is never cancelled (the spec forbids it). (VERIFIED, `client.ts:421-429,548-570`)
- Server requests handled: `ping` (returns `{}`) and `roots/list`; anything else gets JSON-RPC error `-32601`. (VERIFIED, `client.ts:171-180,487-517`)
- Pagination follows `nextCursor`, fails on a repeated cursor or more than 1000 pages. (VERIFIED, `client.ts:355-374`)
- `tools/call` results without `content` get `content: []`; `structuredContent`, when present, must be an object. (VERIFIED, `client.ts:142-151`)
- Not implemented: JSON-RPC batches, legacy HTTP+SSE, sampling, tasks (VERIFIED, `README.md:132`, which also lists "servers"); elicitation and `prompts/*` are not listed there but have no code in `src/client.ts` (VERIFIED by grep; only an `elicitation` capability type exists in `protocol/types.ts:27`). Resources (`resources/list`, `resources/read`) *are* implemented (`client.ts:300-336`).

#### 2.2.4 stdio transport

- Spawned with `cross-spawn` (so `.cmd` shims work on Windows), `stdio: pipe/pipe/pipe`, `windowsHide: true`, and on non-Windows `detached: true` so the server gets its own process group. (VERIFIED, `transports/stdio.ts:95-109`)
- Environment: `process.env` merged with the configured `env` unless `inheritEnv: false`. (VERIFIED, `stdio.ts:94`)
- Framing: one JSON document per line, written as `JSON.stringify(message) + "\n"`; on read, split at byte `0x0a`, strip a trailing `\r`, skip blank lines, report lines over 16 MiB as errors. (VERIFIED, `stdio.ts:143-150,181-207`, `transport.ts:3`)
- stderr is kept as a tail of at most 64 KiB. (VERIFIED, `stdio.ts:7,209-215`)
- Shutdown: close stdin, after 500 ms send `SIGTERM` to the process group, after a further 2000 ms send `SIGKILL`. On Windows `taskkill /pid <pid> /T /F` is used for every "signal". An exit hook kills remaining process groups if the host exits. (VERIFIED, `stdio.ts:8-10,17-53,152-179`)

#### 2.2.5 Streamable HTTP transport

- Every message is an HTTP `POST` to the one endpoint with `accept: application/json, text/event-stream` and `content-type: application/json`. (VERIFIED, `streamable-http.ts:220-227`)
- Headers added to every request once known: `Mcp-Session-Id` (captured from any response header `mcp-session-id`), `MCP-Protocol-Version` (after initialisation), `Authorization: Bearer <token>` from the auth provider, plus the configured headers. (VERIFIED, `streamable-http.ts:300-313`)
- Notifications and responses expect no body. A request answered with `202` or `204` is an error. A request answered with `application/json` yields one or several messages. A request answered with `text/event-stream` is consumed in the background. Any other content type is an error. (VERIFIED, `streamable-http.ts:229-251`)
- After `notifications/initialized` the transport opens the optional server-to-client `GET` stream (`accept: text/event-stream`); `405` means the server offers none. It is kept open with exponential backoff. (VERIFIED, `streamable-http.ts:233,398-452`)
- Status handling: `401` → `McpAuthRequiredError` (keeps `WWW-Authenticate`), `404` with a session id → `McpSessionExpiredError`, other non-2xx → `McpHttpError` with at most 500 characters of the body in the message. (VERIFIED, `streamable-http.ts:14-15,315-321`)
- Auth retry: a `401`, or a `403` whose challenge contains `error="insufficient_scope"`, is handed to `authProvider.onUnauthorized` once, then the request is repeated once. (VERIFIED, `streamable-http.ts:159-164,278-298`)
- SSE parsing: own parser; `data` lines are joined with `\n`; `id` values containing NUL are ignored; `retry` must be digits; events whose type is not `message` or whose data is blank are not JSON-RPC but still update the cursor. (VERIFIED, `streamable-http.ts:35-103,336-349`)
- Resumption of a response stream: when the stream ends or breaks before the response arrived *and* the server sent at least one event id, the transport waits (`retry` from the server, else `min(1000 * 2^attempt, 30000)` ms), then issues `GET` with `last-event-id`. At most 5 consecutive failed attempts; the counter resets when a reopened stream delivered an event. Without an event id, or after giving up, it synthesises a JSON-RPC error `-32603` "MCP response stream failed: ..." for that request id. (VERIFIED, `streamable-http.ts:16-18,358-396,465-477`)
- `close()`: abort all fetches, then `DELETE` with the session header, bounded by 1 s, errors ignored. (VERIFIED, `streamable-http.ts:253-272`)

#### 2.2.6 OAuth

Library (`packages/mcp/src/oauth/*`) and integration (`extensions/mcp/oauth.ts`):

- **Connections never open a browser.** They send the stored access token, refresh after a `401` or when the token is within 30 s of expiry, and otherwise fail with `McpOAuthAuthorizationRequiredError`. The server is then shown as `needs-auth` and the user signs in with `/mcp login <server>`. (VERIFIED, `extensions/mcp/oauth.ts:1-10,38,266-287`)
- OAuth is used only for HTTP servers whose config has **no `Authorization` header**. (VERIFIED, `runtime.ts:80-85`)
- Discovery (VERIFIED, `oauth/discovery.ts:63-151`):
  1. protected resource metadata from the `resource_metadata` URL in the challenge, else `/.well-known/oauth-protected-resource<path>`, else `/.well-known/oauth-protected-resource`; 4xx and 502 count as "not here"
  2. authorization server = `authorization_servers[0]`, else the origin of the MCP server
  3. authorization server metadata from, in order, `/.well-known/oauth-authorization-server<path>`, `/.well-known/openid-configuration<path>`, `<path>/.well-known/openid-configuration`
  4. the metadata `issuer` must equal the URL that was asked for (compared without trailing slash), else `OAuthIssuerMismatchError`
  5. every discovery request carries `Accept: application/json` and `MCP-Protocol-Version`
- Resource indicator: the metadata `resource` must have the same origin as the server URL and a path that is a prefix of it; it is sent as `resource` in the authorization and token requests. (VERIFIED, `discovery.ts:159-172`, `flow.ts:163,174`)
- Client identity, in order: configured `clientId`; a Client ID Metadata Document URL when the server advertises `client_id_metadata_document_supported` and the provider has one; else dynamic client registration at `registration_endpoint` (default `/register`). (VERIFIED, `flow.ts:284-302`)
- Registration metadata defaults: `redirect_uris: [redirectUrl]`, `grant_types: ["authorization_code", "refresh_token"]`, `response_types: ["code"]`, `token_endpoint_auth_method: "client_secret_post"` with a secret, else `"none"`; `client_name` is the app name. (VERIFIED, `oauth/provider.ts:54-62`, `extensions/mcp/oauth.ts:199-208`)
- PKCE: 32 random bytes as base64url verifier, `S256` challenge; refuses servers that advertise challenge methods without `S256` and response types without `code`. When `code_challenge_methods_supported` is **absent**, Pi proceeds anyway (`if (metadata?.code_challenge_methods_supported && ...)`), although the MCP specification says the client "MUST refuse to proceed" in that case; gptr's prototype (`mcp_oauth.R`) refuses, and gptr should keep the spec behaviour. (VERIFIED, `flow.ts:128-153`; spec 2025-11-25 authorization, "Authorization Code Protection")
- Authorization URL parameters: `response_type=code`, `client_id`, `code_challenge`, `code_challenge_method=S256`, `redirect_uri`, `state`, `scope`, `resource`, and `prompt=consent` when the scope includes `offline_access`. (VERIFIED, `flow.ts:154-164`)
- Token endpoint must be HTTPS unless the host is loopback (`OAuthInsecureEndpointError`). Client authentication is chosen among `client_secret_basic`, `client_secret_post`, `none`. OAuth errors in the body are honoured whatever the HTTP status. (VERIFIED, `flow.ts:83-126,167-204`)
- Scope choice: explicit option, else `scopes_supported` of the resource metadata joined by spaces, else the client metadata scope. On step-up the challenge scope is merged with the configured scope. (VERIFIED, `flow.ts:282-283`, `extensions/mcp/oauth.ts:91-95,410`)
- Recovery: `invalid_client` or `unauthorized_client` wipes all stored state and re-runs the flow once; `invalid_grant` wipes the tokens and re-runs once. (VERIFIED, `flow.ts:348-362`)
- Loopback callback server: `127.0.0.1`, free port (or the configured one), path `/callback`, 5 minute timeout, replies 404 for other paths, 400 for unknown `state`, 200 for success or provider error. (VERIFIED, `oauth/callback.ts:61-151`)
- Fallback for remote machines: the user pastes the full redirect URL; whichever of callback and paste arrives first wins. (VERIFIED, `extensions/mcp/oauth.ts:308-343`)
- The port of an already registered redirect URI is reused so the registered client stays valid; if the redirect URI has to change, the stored client and tokens are dropped. (VERIFIED, `extensions/mcp/oauth.ts:382-400`)
- Storage: `~/.pi/agent/mcp-auth.json`, keyed by the normalised server URL, holding client information, tokens, `tokensExpireAt`, PKCE verifier, OAuth state and discovery state. State stored for another URL is ignored. (VERIFIED, `oauth/provider.ts:4-13,150-153`, `extensions/mcp/oauth.ts:111-131`)
- Rotating refresh tokens: refreshes are shared in-process and serialised across processes by a lock file `mcp-auth-refresh-<sha256 of URL, 16 hex>` (stale after 20 s, waits up to 25 s, retries every 100 ms); a token that changed meanwhile is used without refreshing. Shutdown waits for a running refresh. (VERIFIED, `extensions/mcp/oauth.ts:40-45,133-158,238-264`, `runtime.ts:460-462`)
- The browser is opened without a shell: `open` (macOS), `rundll32 url.dll,FileProtocolHandler` (Windows), `xdg-open` (others). (VERIFIED, `src/utils/open-browser.ts`)

#### 2.2.7 Tool naming, schema and result conversion

- Name: `mcp__<server>__<tool>` with every character outside `[A-Za-z0-9_-]` replaced by `_`. If it is longer than 64 characters or already taken by a different tool, it becomes `<first 55 chars>_<first 8 hex of sha256("<server>\0<tool>")>`. (VERIFIED, `tools.ts:42-43,80-89`)
- Namespace: `{ name: "mcp__<server>", description: <server instructions from initialize, or a default> }`. (VERIFIED, `index.ts:241-245`)
- Input schema: passed through, with `type: "object"` and `properties: {}` added when missing, because "some providers reject object schemas without `properties`". (VERIFIED, `tools.ts:228-238`)
- Description: `tool.description`, else the title, else `MCP tool <name> from server <server>`. (VERIFIED, `tools.ts:270`)
- Annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`) are copied for permission extensions. (VERIFIED, `tools.ts:240-250`)
- Progress notifications become partial tool updates with the text `progress.message` or `Progress <n>/<total>`. (VERIFIED, `tools.ts:299-303`)
- Content conversion for the model (VERIFIED, `protocol/content.ts:78-117`, `tools.ts:163-194`):

| MCP block | Model-facing content |
|---|---|
| `text` | text |
| `image` | image (`data`, `mimeType`) |
| `audio` | text `[audio <mimeType> omitted]` |
| `resource_link` | text `[Resource <uri> "<title or name>" (<mime>, <size>): <description>. Read it with read_mcp_resource (server "<server>")]` |
| `resource` with `text` | text |
| `resource` with `blob`, image MIME | image |
| `resource` with `blob`, text-like MIME (`text/*`, `application/json`, `*+json`, `*+xml`) | decoded text |
| `resource` with other `blob` | saved to a temp file (mode 0600), text `[Binary resource <uri> (<mime>, <size>) saved to <path>]` |
| unknown type | text `[unsupported MCP content <type>]` |
| no content but `structuredContent` | pretty-printed JSON as text |

- `isError: true` makes the tool result an error for the model; if it has no text, the text `MCP tool <server>/<tool> returned an error` is added. (VERIFIED, `tools.ts:206-226`)
- Output limit: combined text over `MCP_OUTPUT_MAX_BYTES = 20 * 1024` is cut in the middle on UTF-8 character boundaries as `<head>…N chars truncated…<tail>` and wrapped as `Warning: truncated output (original token count: <bytes/4>)`, `Total output lines: <n>`, the text, and `[Full output: <path> (read it with offset/limit)]`. Images are kept after the text. (VERIFIED, `tools.ts:45,120-141`, `core/tools/truncate.ts:292-314`)
- Scripts (codemode) receive the whole `CallToolResult` without `_meta`, never truncated. (VERIFIED, `tools.ts:1-11,219-225`)
- Resources: three extra tools `list_mcp_resources`, `list_mcp_resource_templates`, `read_mcp_resource`, named after Codex's and opencode's tools; MCP App resources (`ui://`, `profile=mcp-app`) are left out. (VERIFIED, `resources.ts:1-54`)
- All MCP calls go through the normal tool pipeline, so permission hooks apply; calls from scripts carry the script call's id as `parentToolCallId`. (VERIFIED, `docs/mcp.md:174-176`)

### 2.3 tool-search: deferred tool loading

Source: `$PI/packages/coding-agent/src/extensions/tool-search/tool.ts`.

- Purpose: keep large tool lists out of the model's tool declarations. Tools with exposure `codemode` or `deferred` that are not active are *searchable*. (VERIFIED, `tool.ts:190-193`)
- The tool `tool_search` has parameters `{ query: string, limit?: number }`, exposure `model-only` (scripts cannot call it), and is registered inactive. (VERIFIED, `tool.ts:158-163,243`, `index.ts:12-16`)
- Execution: rank the searchable, inactive tools; add the matches to the active tool set with `setActiveTools([...active, ...matches])`; answer `Loaded N tools. They are available from your next call:` and one `- name: first line of description` per tool, or `No matching tools found.` (VERIFIED, `tool.ts:199-213,255-267`)
- Because loading is a change of the active tool set, it is recorded in the transcript and survives resume, fork and tree navigation. (VERIFIED, `tool.ts:5-9`)
- The tool's description is rebuilt whenever the tool set changes and lists the namespaces that can be searched. (VERIFIED, `tool.ts:219-230,245-254`)
- Ranker (VERIFIED, `tool.ts:39-156`):
  - document text = name, name with `_` as spaces, description, every schema `description` and property name (recursing into `properties`, `items`, `anyOf`, `oneOf`, `allOf`), namespace name and description
  - tokeniser: split camelCase, lower-case, split on `[^a-z0-9]+`, drop 21 stop words, naive singular stemming
  - Okapi BM25 with `idf = ln(1 + (N - f + 0.5) / (f + 0.5))`, score `idf * c * (k1 + 1) / (c + k1 * (1 - b + b * len / avglen))`, ties keep document order
- The same ranker backs `searchTools()` inside codemode scripts. (VERIFIED, `extensions/codemode/execute.ts:25,323-352`)
- Claude Code has the same concept ("tool search", on by default, `ENABLE_TOOL_SEARCH=false` disables it). (VERIFIED, Claude Code MCP docs)

### 2.4 codemode

Sources: `$PI/packages/codemode` (sandbox), `$PI/packages/coding-agent/src/extensions/codemode` (tool).

#### 2.4.1 What it is

- One tool, `codemode`, parameter `{ code: string }`. The code is the body of an async function. (VERIFIED, `tool.ts:85-90`)
- Inside the script: `tools.<id>(args)` returns a promise; `ALL_TOOLS` lists `{ name, description }`; `text()`, `image()`, `exit()`, `console.*`, `store(key, value)` / `load(key)`; `searchTools(query, { limit, namespace })`, `describeTool(name)`; and `models.*` including `models.classify(model, { state, questions })` for classifier models such as TypeSafe's Jev. (VERIFIED, `tool.ts:131-217`, `docs/models.md:103-136`)
- An optional first line `// @options: {"max_output_tokens": 2000, "timeout_ms": 60000}`; unknown fields are errors. Defaults: output budget 10000 tokens (4 characters per token), no deadline. (VERIFIED, `codemode/src/source.ts:11-115`, `execute.ts:129-132,277,309`)
- The result starts with `Script completed` or `Script failed`, `Wall time <s> seconds`, `Output:`. A failed script keeps its partial output, followed by `Script error:` and the error plus `Tool calls made before the failure (they are not undone): ...`. (VERIFIED, `execute.ts:140-156,304-320`)
- Exposure `model-only`: scripts cannot start scripts. (VERIFIED, `tool.ts:427-428`)
- For providers that support grammar-constrained tool input, a Lark grammar lets the model send raw source instead of a JSON-escaped string. (VERIFIED, `source.ts:22-30`, `tool.ts:430-431`)

#### 2.4.2 Sandboxing

- QuickJS compiled to WebAssembly (`quickjs-wasi` 3.6.2). Each `execute()` starts a **new worker thread and a new VM** (about 20 ms), so a runaway script cannot affect the next run. (VERIFIED, `codemode/README.md:172-180`, `runtime/host.ts:81-85`, `package.json:58`)
- The VM's only imports are a WASI shim whose output is discarded and one bridge function. The bridge lives in a closure of the prelude, so the script cannot call it directly. No timers, `fetch`, `process`, `require`, modules or `WebAssembly`. (VERIFIED, `runtime/worker.ts:26-100`, `README.md:47`)
- Arguments and results cross the boundary as JSON strings. (VERIFIED, `runtime/protocol.ts:4-8`)
- Limits: deadline default 300 000 ms in the library (the coding agent passes `Infinity` unless `timeout_ms` is given), heap limit 256 MB in the coding agent, deep recursion raises a catchable `RangeError`, a script waiting on a promise nothing can settle fails immediately. (VERIFIED, `host.ts:22`, `execute.ts:43-48,277-278`, `worker.ts:57-61,117-122`)
- Termination sets a shared interrupt flag that the VM polls, then terminates the worker. (VERIFIED, `host.ts:268-272`)
- Error kinds: `script`, `timeout`, `aborted`, `sandbox`. Calls still running when the script ends are aborted and recorded as `cancelled`. (VERIFIED, `types.ts:57-72`, `README.md:161-170`)

#### 2.4.3 Declarations

- `renderDeclarations()` turns each tool into a member of `declare const tools: { ... }`: a doc comment from the description and `name(args: <input type>): Promise<<output type>>;`. (VERIFIED, `declarations.ts:105-147`)
- `schemaToType()` maps JSON Schema to TypeScript: `const`, `enum`, `anyOf`/`oneOf` (union), `allOf` (intersection), type arrays, `string|number|integer|boolean|null`, `Array<T>`, tuples, objects with properties **sorted by name**, optional marker `?`, `[key: string]: T` for additional properties, property descriptions as `//` comments. Local `$ref`s are expanded (at most 32 expansions, recursion gives `unknown`). An input type over 16 000 characters becomes `unknown`. (VERIFIED, `declarations.ts:10-12,217-351`)
- Identifier rule: characters invalid in a JavaScript identifier become `_` (`my-tool` → `tools.my_tool`), and `tools["my-tool"]` also works. The first tool wins when two names normalise to the same identifier. (VERIFIED, `identifier.ts:5-12`, `prelude-source.ts` tools loop)
- MCP tools are declared as `Promise<CallToolResult<T>>` with a shared type preamble. (VERIFIED, `declarations.ts:18-93,161-184`)
- Budget: tool sections share `DEFAULT_CODEMODE_INLINE_BUDGET = 3000` estimated tokens (characters / 4). Selection is round-robin over namespaces, cheapest tool first, so every namespace is represented before any is complete. The description states `COMPLETE list (N tools)` or `PARTIAL - X of N shown`, and every namespace is listed with its tool count. (VERIFIED, `tool.ts:222-225,275-368`)
- Two presentation modes: `on` (declared tools stay declared and get their script declaration appended) and `only` (every tool is reached through scripts). (VERIFIED, `tool.ts:370-414`, `docs/settings.md:41`)

#### 2.4.4 Nested calls

- Nested calls run through `ctx.executeTool()`, the same pipeline as model-issued calls: validation, `tool_call`/`tool_result` hooks, permission checks. The call id is `<calling id>/<n>` and events carry `parentToolCallId`. (VERIFIED, `core/extensions/types.ts:376-394`)
- Value handed to the script: `structuredContent` when the tool declares `outputSchema`; else the text content as one string; a failed call rejects with the tool's error text. MCP results with `isError` resolve, because MCP tools always declare an output schema. (VERIFIED, `execute.ts:199-211`)
- A bounded record of nested calls is stored on the calling tool's result: at most 256 calls, 8 KiB of arguments per call, 32 KiB in total, 500 characters of error text. Usage of nested results is summed. (VERIFIED, `core/nested-tool-calls.ts:26-31`)
- `store()` writes are appended to the session as `codemode-store` entries only when the script succeeds; limits are 256 Ki characters per value and 1 Mi in total. (VERIFIED, `tool.ts:50-56`, `prelude-source.ts` constants)
- Classifier calls from one script are limited to 4 in flight. (VERIFIED, `execute.ts:41-42`)

### 2.5 Coordinator, session workers, durable, server, protocol, client

#### 2.5.1 Experimental coordinator and session workers

- The coordinator is a separate, detached process that is "intentionally a transport shim": it depends only on Node built-ins and never interprets payloads. It listens on two Unix sockets, a *public* one that it pipes to the current server's endpoint and a *control* one for JSON-lines routing. (VERIFIED, `experimental/coordinator.ts:260-329,444-473`)
- Roles on the control socket: exactly one current `server` (a newer registration replaces the old one, which receives `server_replaced`) and any number of `peer`s (session workers). Messages: `register_server`, `register_peer`, `send {to, payload}`, `broadcast` (server only); events `peer_connected`, `peer_disconnected`, `server_connected`, `server_disconnected`, `message {from, payload}`. Protocol version 3. (VERIFIED, `coordinator.ts:14-29,330-442`)
- The coordinator exits by itself: 30 s after start if nobody connected, 250 ms after the last connection closes. Start-up is polled every 10 ms for at most 10 s. Sockets are `chmod 0600` except on Windows. (VERIFIED, `coordinator.ts:15-16,187-199,263-264,483-500,570-572`)
- One **session worker process per session**, spawned detached with a role in the environment variable `__PI_INTERNAL_SPAWN` and four `PI_SESSION_WORKER_*` variables (control address, token, session key in base64url, peer id). (VERIFIED, `experimental/process.ts:6,41-71`, `session-worker.ts:67-70`, `session-worker-manager.ts:476-484`)
- Worker protocol: commands `shutdown`, `discover_workers`, `session_demand`, `operation`, `operation_cancel`; events `worker_ready`, `worker_failed`, `demand_applied`, `demand_rejected`, `operation_response`, `service_update`. Every event carries the worker's token and session key, and the manager drops events that do not match. (VERIFIED, `session-worker.ts:96-186`, `session-worker-manager.ts:516-589`)
- Timeouts: worker start 15 s, shutdown 10 s then `SIGKILL`, discovery 5 s, demand update 5 s. Operations have no wall-clock timeout. (VERIFIED, `session-worker-manager.ts:34-37,320`)
- Worker retirement: a worker retires when it has no attachment demand, no active operation and no retirement hold. Initial grace 10 s, orphan grace 30 s after its server generation disconnects. (VERIFIED, `session-worker.ts:190-320`)
- A worker takes a lock file on the session file, so one process owns a session's writes. (VERIFIED, `session-worker.ts:533`)
- A replaced server `detach()`es, forgetting workers without stopping them; the new server re-discovers them by broadcast. (VERIFIED, `session-worker-manager.ts:154-176,438-450`)
- Control lines are limited to 128 MiB. (VERIFIED, `process.ts:100-106`)

#### 2.5.2 `@earendil-works/pi-durable` (experimental)

(VERIFIED, `$PI/packages/durable/README.md`)

- Everything is committed to storage before it is shown; reopening the storage resumes interrupted work (`harness.resume()`).
- Concepts: Harness, Conversation (immutable entries), Commit (atomic), Document (typed JSON state next to the transcript), Task (a state machine checkpointed at every step), Submission, Registry.
- Built-in tasks per answered input: `pi.generation`, `pi.tool` × n, `pi.post-tools`.
- Idempotent submissions: the same `requestId` returns the existing submission.
- Tool replay: a tool's intent is committed before `execute()`; after a crash it is re-run only when declared `replay: "safe"`, otherwise the model receives an `interrupted` error result with the output committed so far.
- Tool results may return `usage` (added to the conversation's usage) and `control: { terminate: true }` or `control: { handoff: "..." }`.
- Busy conversations: `whenBusy` is `follow-up` (default), `steer` or `reject`; writes append an entry without asking the model.
- `reset(note?)` starts a new context, optionally from a handoff note; old entries stay in storage.
- Sub-agents: a child conversation created with `ownership: { kind: "task", taskId }`. Aborting the call aborts the child, the parent is idle only once the child is, and `{ background: true }` creates a boundary that survives the parent's abort.
- Usage is kept per `provider/model` and per tool name, including failed and aborted attempts.
- Partial output is committed at most every 100 ms. A slow watcher keeps at most 100 frames, then receives one full snapshot.
- Storage: memory, SQLite (WAL, `synchronous = NORMAL`), JSONL. One process owns a storage; there is no cross-process locking.

#### 2.5.3 `pi-server`, `pi-protocol`, `pi-client` (experimental)

(VERIFIED, the three `README.md` files)

- Protocol version 8: a version handshake naming a logical `serverId`; targets `{ serverId }` or `{ serverId, sessionId, attachmentId }`; correlated requests and responses with opaque strict-JSON payloads; cancellation; subscription updates.
- Wire format: four-byte big-endian length followed by one CBOR item. Limits: 16 MiB per frame, 1 000 000 array or map entries, 64 nesting levels.
- The client never reconnects or replays on its own: "explicitly repeat only operations known to be safe".
- Peer authentication is not implemented by the experimental Unix transport.

---

## 3. Exact specifications

### 3.1 Agent definition file (Pi example; identical core to Claude Code)

```markdown
---
name: my-agent
description: What this agent does
tools: read, grep, find, ls
model: claude-haiku-4-5
---

System prompt for the agent goes here.
```

Claude Code's additional frontmatter fields (docs, 2026-09): `disallowedTools`, `model` aliases `sonnet|opus|haiku|fable|inherit` or a full id, `permissionMode` (`default|acceptEdits|auto|dontAsk|bypassPermissions|plan`, plus `manual` as an alias of `default`), `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory` (`user|project|local`), `background`, `omitClaudeMd`, `isolation: worktree`, `effort` (`low|medium|high|xhigh|max`), `color` (`red|blue|green|yellow|purple|orange|pink|cyan`), `initialPrompt`, `experimental` (map, e.g. `cacheTtl`). `name` must not contain `:` or start with `-`. Unrecognised fields are ignored without an error. Locations `.claude/agents/` (walked up from cwd, scanned recursively) and `~/.claude/agents/`. Default depth limit 3 layers below the main conversation (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), default concurrency limit 20 running sub-agents (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`). (Verified against https://code.claude.com/docs/en/sub-agents on 2026-09-29.)

### 3.2 `subagent` tool parameters (JSON Schema equivalent of `index.ts:442-469`)

```json
{
  "type": "object",
  "properties": {
    "agent": { "type": "string", "description": "Name of the agent to invoke (for single mode)" },
    "task": { "type": "string", "description": "Task to delegate (for single mode)" },
    "tasks": {
      "type": "array", "description": "Array of {agent, task} for parallel execution",
      "items": { "type": "object", "required": ["agent", "task"], "properties": {
        "agent": { "type": "string", "description": "Name of the agent to invoke" },
        "task": { "type": "string", "description": "Task to delegate to the agent" },
        "cwd": { "type": "string", "description": "Working directory for the agent process" } } }
    },
    "chain": {
      "type": "array", "description": "Array of {agent, task} for sequential execution",
      "items": { "type": "object", "required": ["agent", "task"], "properties": {
        "agent": { "type": "string" },
        "task": { "type": "string", "description": "Task with optional {previous} placeholder for prior output" },
        "cwd": { "type": "string" } } }
    },
    "agentScope": { "type": "string", "enum": ["user", "project", "both"], "default": "user" },
    "confirmProjectAgents": { "type": "boolean", "default": true },
    "cwd": { "type": "string", "description": "Working directory for the agent process (single mode)" }
  }
}
```

Result `details`: `{ mode: "single"|"parallel"|"chain", agentScope, projectAgentsDir, results: SingleResult[] }` with `SingleResult = { agent, agentSource: "user"|"project"|"unknown", task, exitCode (-1 while running), messages, stderr, usage: { input, output, cacheRead, cacheWrite, cost, contextTokens, turns }, model?, stopReason?, errorMessage?, step? }`.

### 3.3 JSONL events a parent needs from a child (`docs/json.md`)

Framing: one JSON object per line, LF terminated, split only on LF and strip an optional CR. stdout carries only JSONL; diagnostics go to stderr.

```json
{"type":"session","version":3,"id":"uuid","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/path"}
{"type":"agent_start"}
{"type":"turn_start"}
{"type":"message_start","message":{"role":"user","content":"...","timestamp":1733234401000}}
{"type":"message_end","message":{"role":"assistant","content":[...],"usage":{"input":100,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":101,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"stopReason":"stop","model":"..."}}
{"type":"tool_execution_start","toolCallId":"call_abc123","toolName":"bash","args":{"command":"ls -la"}}
{"type":"tool_execution_end","toolCallId":"call_abc123","toolName":"bash","result":{"content":[{"type":"text","text":"..."}],"details":{}},"isError":false}
{"type":"turn_end","message":{...},"toolResults":[]}
{"type":"agent_end","messages":[...],"willRetry":false}
{"type":"agent_settled"}
```

Tool result message: `{ role: "toolResult", toolCallId, toolName, content: (TextContent | ImageContent)[], details?, usage?, isError, timestamp }`. The optional `usage` "reports nested model work performed by the tool" (`docs/message-types.md`).

### 3.4 MCP configuration

Pi (`~/.pi/agent/mcp.json`, `<project>/.pi/mcp.json`):

```json
{
  "autoEnableCodemode": true,
  "mcpServers": {
    "filesystem": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "."], "env": { "K": "${V}" }, "cwd": "sub/dir" },
    "docs": { "url": "https://example.com/mcp", "headers": { "Authorization": "Bearer ${DOCS_TOKEN}" }, "exposure": "direct", "timeout": 60, "enabled": true },
    "example": { "url": "https://mcp.example.com/mcp", "oauth": { "clientId": "my-client", "clientSecret": "${EXAMPLE_SECRET}", "callbackPort": 8765, "callbackUrl": "http://localhost:8765/oauth/callback", "scope": "a b" } },
    "github": { "url": "https://api.githubcopilot.com/mcp/", "exposure": "deferred", "toolExposure": { "search_code": "direct", "get_*": "codemode", "delete_*": "hidden" } }
  }
}
```

Where other harnesses keep MCP servers (all from current documentation; none of these files was read on this machine):

| Harness | User-level file | Project-level file | Top-level key | Notes |
|---|---|---|---|---|
| Pi | `~/.pi/agent/mcp.json` | `.pi/mcp.json` | `mcpServers` | `timeout` in seconds; `!command` values |
| Claude Code | `~/.claude.json` (`mcpServers`, and `projects["<abs path>"].mcpServers` for local scope) | `.mcp.json` | `mcpServers` | `type`: `stdio`, `http`/`streamable-http`, `sse`, `ws`; `timeout` in **milliseconds** (values under 1000 are ignored); `${VAR}` and `${VAR:-default}` in `command`, `args`, `env`, `url`, `headers`; `headersHelper` |
| Claude Desktop | macOS `~/Library/Application Support/Claude/claude_desktop_config.json`; Windows `%APPDATA%\Claude\claude_desktop_config.json` (MSIX installs use `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\`) | — | `mcpServers` | paths from web search results, LIKELY; the Linux path used in my prototype (`~/.config/Claude/`) is UNCERTAIN |
| Cursor | `~/.cursor/mcp.json` | `.cursor/mcp.json` | `mcpServers` | paths and `${env:NAME}` VERIFIED against https://cursor.com/docs/mcp (2026-09-29); Cursor also expands `${userHome}`, `${workspaceFolder}`, `${workspaceFolderBasename}`, `${pathSeparator}`/`${/}` in `command`, `args`, `env`, `url`, `headers`, which the prototype loader does not handle yet |
| VS Code | user profile `mcp.json` | `.vscode/mcp.json` | `servers` | `inputs` and `${input:...}` prompts (Pi `docs/mcp.md:57`) |
| Codex | `~/.codex/config.toml` | `.codex/config.toml` (trusted projects) | `[mcp_servers.<name>]` | keys `command`, `args`, `env`, `env_vars`, `cwd`, `url`, `bearer_token_env_var`, `http_headers`, `env_http_headers`, `startup_timeout_sec` (10), `tool_timeout_sec` (60), `enabled`, `enabled_tools`, `disabled_tools` |
| opencode | — | — | `mcp` | `type: "local"` with `command` as an array and `environment`; `type: "remote"`; `{env:NAME}` (from Pi's `docs/mcp.md:59`) |
| mcptools (R) | `~/.config/mcptools/config.json` | — | `mcpServers` | returns ellmer tools |

### 3.5 MCP wire format (spec 2025-11-25)

Initialize request as sent by my prototype (and by Pi, with its own client name):

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{"roots":{}},"clientInfo":{"name":"gptr","version":"0.0.0.9000"}}}
```

Server result (spec example, shortened):

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{"logging":{},"tools":{"listChanged":true}},"serverInfo":{"name":"ExampleServer","version":"1.0.0"},"instructions":"Optional instructions for the client"}}
```

Then the client sends `{"jsonrpc":"2.0","method":"notifications/initialized"}`.

Other messages:

```json
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"cursor":"optional-cursor-value"}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_weather","arguments":{"location":"New York"},"_meta":{"progressToken":3}}}
{"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":3,"progress":1,"total":4,"message":"step 1/4"}}
{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3,"reason":"Request timed out"}}
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"..."}],"structuredContent":{"temperature":22.5},"isError":false}}
{"jsonrpc":"2.0","id":4,"error":{"code":-32602,"message":"Unknown tool: invalid_tool_name"}}
```

JSON-RPC error codes: `-32700` parse error, `-32600` invalid request, `-32601` method not found, `-32602` invalid params, `-32603` internal error.

Rules quoted from the specification:

- stdio: "Messages are delimited by newlines, and MUST NOT contain embedded newlines." "The server MUST NOT write anything to its stdout that is not a valid MCP message." Shutdown: close the input stream, wait, `SIGTERM`, then `SIGKILL`.
- HTTP POST: "The client MUST include an Accept header, listing both application/json and text/event-stream as supported content types." Notifications and responses are answered with `202 Accepted` and no body. For a request the server returns `application/json` or `text/event-stream`, and "The client MUST support both these cases."
- Session: a server may return `MCP-Session-Id` with the initialize result; the client "MUST include it in the MCP-Session-Id header on all of their subsequent HTTP requests". On `404` with a session id the client "MUST start a new session by sending a new InitializeRequest without a session ID attached". Clients "SHOULD send an HTTP DELETE" when done; the server may answer `405`.
- Version header: "the client MUST include the MCP-Protocol-Version: <protocol-version> HTTP header on all subsequent requests".
- Resumption: "Resumption is always via HTTP GET with Last-Event-ID." "The client MUST respect the retry field."
- Tool names "SHOULD be between 1 and 128 characters" and use only `A-Z a-z 0-9 _ - .`. Note that `.` is allowed by MCP but not by model providers' tool-name rules, and `-` is not valid in an R identifier.
- Authorization: `resource` "MUST be included in both authorization requests and token requests"; clients "MUST use the S256 code challenge method when technically capable"; if `code_challenge_methods_supported` is absent the client "MUST refuse to proceed"; "Access tokens MUST NOT be included in the URI query string"; registration priority is pre-registered client, Client ID Metadata Document, dynamic client registration, then asking the user.

### 3.6 Constants and limits

| Constant | Value | Source |
|---|---|---|
| Sub-agent max parallel tasks | 8 | `subagent/index.ts:33` |
| Sub-agent max concurrency | 4 | `index.ts:34` |
| Sub-agent output cap to parent (parallel) | 50 KiB per task | `index.ts:36` |
| Sub-agent kill grace (TERM → KILL) | 5000 ms as written; in practice no KILL is sent after a delivered TERM (`!proc.killed` guard, see 2.1.6) | `index.ts:414-416` |
| MCP protocol versions | request `2025-11-25`; accept `2025-06-18`, `2025-03-26`, `2024-11-05` | `mcp/protocol/types.ts:4-9` |
| MCP request timeout | 30 s library, 60 s coding agent; progress resets it | `client.ts:38`, `runtime.ts:47` |
| MCP max list pages | 1000 | `client.ts:39` |
| MCP max message | 16 MiB | `transports/transport.ts:3` |
| stdio stderr tail | 64 KiB kept, 2000 characters shown | `stdio.ts:7`, `runtime.ts:48` |
| stdio shutdown | 500 ms after stdin close → TERM; +2000 ms → KILL | `stdio.ts:8-10` |
| HTTP connect retries | after 250 ms and 1000 ms, transient errors only | `runtime.ts:50` |
| HTTP error body kept | 8 KiB read, 500 characters in the message | `streamable-http.ts:14-15` |
| SSE reconnect | initial 1000 ms, ×2, max 30 000 ms, 5 retries | `streamable-http.ts:16-18` |
| HTTP session DELETE timeout | 1000 ms | `streamable-http.ts:259` |
| Start-up wait of the first prompt | 10 000 ms | `extensions/mcp/index.ts:79` |
| MCP tool name | 64 characters, `[A-Za-z0-9_-]`, 8 hex sha256 suffix | `extensions/mcp/tools.ts:43,80-89` |
| MCP model-facing text limit | 20 KiB, cut in the middle | `tools.ts:45` |
| MCP log rotation | 5 MiB | `log.ts:10` |
| OAuth callback timeout | 5 min | `oauth/callback.ts:80` |
| OAuth refresh skew / request timeout | 30 s / 15 s | `extensions/mcp/oauth.ts:38-40` |
| OAuth refresh lock | stale 20 s, wait 25 s, retry 100 ms | `extensions/mcp/oauth.ts:42-45` |
| tool_search default limit | 8 | `tool-search/tool.ts:21` |
| BM25 parameters | k1 1.2, b 0.75 | `tool.ts:122-125` |
| Codemode declaration budget | 3000 tokens (characters / 4) | `codemode/tool.ts:223-225` |
| Codemode output budget | 10 000 tokens | `codemode/execute.ts:130` |
| Codemode heap limit | 256 MiB | `execute.ts:48` |
| Codemode library default deadline | 300 000 ms | `codemode/src/runtime/host.ts:22` |
| Codemode input type max | 16 000 characters, 32 `$ref` expansions | `declarations.ts:10-12` |
| Codemode store | 256 Ki characters per value, 1 Mi total | `prelude-source.ts` |
| Classifier calls in flight per script | 4 | `execute.ts:42` |
| Nested call record | 256 calls, 8 KiB args per call, 32 KiB total, 500 characters of error | `core/nested-tool-calls.ts:26-31` |
| Coordinator protocol / start timeout | 3 / 10 s | `coordinator.ts:14-15` |
| Worker start / shutdown / discovery / demand | 15 s / 10 s / 5 s / 5 s | `session-worker-manager.ts:34-37` |
| Worker initial / orphan grace | 10 s / 30 s | `session-worker.ts:317-318` |

---

## 4. Recommended design for gptr

Requirement coverage of this track: REQ-30 (MCP), REQ-32, REQ-33, REQ-34, REQ-35 (sub-agents and orchestration), REQ-10 (minimal tool surface), and the interaction with REQ-09, REQ-22, REQ-24, REQ-37, REQ-38.

### 4.1 Packages

| Package | Role in this track | Recommendation |
|---|---|---|
| jsonlite | JSON-RPC, JSONL events, config files | **Imports** |
| processx | stdio MCP servers, polling several children | **Imports** (compiled, binaries on CRAN for Windows and macOS; brings `ps`, which `kill_tree()` needs) |
| callr | sub-agent child processes (`r_bg`, optionally `r_session`) | **Imports** (no compiled code; depends on processx and R6) |
| httr2 | Streamable HTTP, OAuth requests | **Imports** (presumably already imported for providers) |
| openssl | PKCE (sha256, random bytes), tool-name hash | reachable through httr2's Imports; list it in **Imports** because gptr calls it directly |
| httpuv + later | OAuth loopback callback bound to `127.0.0.1` | **Suggests**; without them `mcp_login()` falls back to pasting the redirect URL |
| yaml | agent and skill frontmatter | **Suggests** with a small `key: value` fallback parser, or Imports if the skills track needs it anyway |
| parallel | fork backend | base R, **Imports** |
| digest | — | not needed (my prototype used it for sha256; use `openssl::sha256()` instead) |
| RcppTOML | — | not needed; a 60-line reader handles Codex's `[mcp_servers.*]` tables (verified against RcppTOML on one file) |
| mcptools | alternative MCP client | **not recommended as a dependency**: v1.0.3 imports ellmer, nanonext, httpuv, promises and returns ellmer tool objects. Read its config file for compatibility instead. |
| mirai | alternative process pool | not needed for v1 |

### 4.2 Sub-agents

#### 4.2.1 Data structures

```r
# S3 class "gptr_agent"
list(
  name = "scout",                 # chr(1), required
  description = "Fast recon",     # chr(1), required
  tools = c("read", "grep"),      # chr or NULL (NULL = harness defaults)
  model = NULL,                   # chr(1) "provider/id" or alias; NULL or "inherit" = dispatcher's model
  thinking = NULL,                # chr(1) or NULL (frontmatter `effort` or `thinking`)
  max_turns = NULL,               # int(1) or NULL (frontmatter `maxTurns`)
  system_prompt = "You are ...",  # Markdown body
  source = "user",                # "user" | "project" | "inline"
  file_path = "/path/scout.md"
)

# S3 class "gptr_agent_result"
list(
  agent, agent_source, task, step,
  text,           # final assistant text ("" when none)
  value,          # optional R object returned by the child (process and fork backends)
  messages,       # list of messages of the child run
  usage = list(input, output, cache_read, cache_write, cost, context_tokens, turns),
  model, stop_reason, error_message, exit_code, stderr, duration,
  session_file    # child's own session file, when sessions are enabled
)
```

#### 4.2.2 Functions

```r
gptr_agent(name, description, system_prompt, tools = NULL, model = NULL,
           thinking = NULL, max_turns = NULL)

gptr_agents(scope = c("user", "project", "both"), cwd = getwd())
#   user:    file.path(tools::R_user_dir("gptr", "config"), "agents")
#   project: nearest .gptr/agents walking up from cwd, then .claude/agents and .pi/agents
#   precedence (low to high): user < foreign project dirs < .gptr/agents

agent_run(agent, task, ..., model = NULL,
          backend = c("auto", "inline", "process", "fork"),
          env = parent.frame(), env_mode = c("overlay", "shared"),
          export = NULL, cwd = NULL, timeout = Inf, on_event = NULL)

agent_parallel(tasks, ..., backend = "process", max_concurrency = 4L, max_tasks = 8L,
               on_update = NULL)
#   tasks: list of list(agent =, task =, cwd =) or a data frame with those columns

agent_chain(steps, ..., placeholder = "{previous}")
```

Also register the model-facing tool `subagent` with the parameter schema of section 3.2 (renaming `agentScope` and `confirmProjectAgents` is unnecessary; models have seen these names). Because gptr exposes tools as R functions (section 4.5), the model can also write `gptr::agent_parallel(...)` inside R code, which is how REQ-35 ("the R script is the graph") is met.

#### 4.2.3 Backends

| Backend | Context isolation | Sees live objects | Parallel | Platforms | Use |
|---|---|---|---|---|---|
| `inline` | separate message history, own system prompt and tool set | yes, through an overlay environment whose parent is the target environment (writes stay in the overlay) or directly with `env_mode = "shared"` | no | all | default for one sub-agent that must use session objects |
| `process` | fresh R process via `callr::r_bg()` | only objects named in `export` (serialised) | yes | all | default for `agent_parallel()` |
| `fork` | forked copy of the session via `parallel::mcparallel()` | yes, copy-on-write, read-only in effect | yes | Unix, not inside RStudio or other GUIs | opt-in for big in-memory objects |

`backend = "auto"`: `inline` for `agent_run()`, `process` for `agent_parallel()`.

Measured on the development machine (section 5.9): child start 0.24-0.4 s; 381 MB object exported by serialisation 1.06-1.5 s; forked child 0.12-0.18 s; four forked tasks (1 s sleep each) over the same object in parallel 2.2-3.5 s. (Ranges include the verifier's re-run: 0.32/0.24 s, 1.06 s, 0.13 s, 2.24 s; timings depend on machine load.)

#### 4.2.4 Process backend protocol

- Spawn: `callr::r_bg(function(spec) gptr:::subagent_worker(spec), args = list(spec = spec), package = "gptr", stdout = "|", stderr = "|", stdin = "|", wd = cwd, supervise = TRUE, cleanup_tree = TRUE, user_profile = FALSE, system_profile = FALSE, env = c(callr::rcmd_safe_env(), GPTR_SUBAGENT_DEPTH = depth + 1))`. `stdin = "|"` is passed through to processx and works (executed: `chk.R` -> "r_bg stdin round trip: hello from parent").
- `spec` = `list(agent, system_prompt, tools, model, thinking, task = paste0("Task: ", task), export = list(...), max_turns, permission_mode)`. callr serialises it to a temporary file, so there are no command-line length or quoting problems.
- Child to parent: JSONL events on stdout with the event names of section 3.3, written with `writeLines(enc2utf8(json), stdout(), useBytes = TRUE)`. The child must `sink()` tool output away from stdout; the parent ignores lines that are not JSON objects (verified with a noise line).
- Parent to child: JSON lines on stdin for answers to `permission_request` and `ask_user` events, so REQ-36 and REQ-37 work although the child has no console.
- Result: the child function's return value, read with `p$get_result()`, may be any R object (verified with a data frame).
- Scheduler: `processx::poll(list_of_processes, ms)` over all running children; start the next task when a slot frees; results keep task order.
- Abort (REQ-38): an R interrupt in the parent calls `p$interrupt()` on every child (SIGINT on Unix, CTRL+BREAK on Windows), waits up to 5 s, then `p$kill_tree()`, and signals a condition of class `gptr_aborted`.
- Depth: `GPTR_SUBAGENT_DEPTH` counts nesting. Default maximum 1: children do not get the `subagent` tool unless `options(gptr.subagent_max_depth = n)` allows it.
- Cost accounting: the parent tool result carries `usage` = the sum over children, so session totals include sub-agent cost.
- Warm workers (optional, later): a pool of `callr::r_session` objects (start 0.10-0.16 s, warm call 0.03-0.05 s, interruptible and reusable afterwards; executed: `chk.R`), retired after an idle period as Pi's workers are.

#### 4.2.5 Cross-LLM collaboration (REQ-34)

Each agent file names its own model; `agent_chain()` with a planner, implementer and reviewer from different providers needs nothing else. `gptr_handoff(chat, goal, model = )` (the `/handoff` idea) creates a fresh conversation from a generated, user-editable summary.

### 4.3 MCP client

#### 4.3.1 Layers

```
mcp_config  ->  mcp_registry (package-level, lives for the R session)
                  |- mcp_connection (one per server: state, tools cache, lazy connect, reconnect)
                       |- mcp_client (JSON-RPC core)
                            |- transport: stdio (processx) | http (httr2 + own SSE parser)
                                 |- auth provider (tokens file, refresh, step-up detection)
```

#### 4.3.2 Functions

```r
# configuration
mcp_servers(cwd = getwd(), foreign = getOption("gptr.mcp.foreign", FALSE))   # merged, validated entries
mcp_add(name, command = NULL, args = character(), env = NULL, url = NULL, headers = NULL,
        scope = c("user", "project"), exposure = "code", timeout = NULL)
mcp_remove(name, scope = c("user", "project"))
mcp_import(from = c("claude-code", "claude-desktop", "cursor", "vscode", "codex", "pi", "mcptools"),
           servers = NULL, scope = "user")          # copies entries into gptr's own file
mcp_status()                                        # data frame: name, state, tools, exposure, source, error
mcp_login(name, manual = FALSE); mcp_logout(name); mcp_reconnect(name)

# programmatic use
mcp_call(server, tool, ..., .timeout = NULL, .raw = FALSE)   # lazy connect, returns an R value
mcp_tools(server = NULL)                                      # tool metadata (from cache when offline)

# internals (prototyped in section 5)
mcp_transport_stdio(command, args, env, cwd, inherit_env = TRUE, close_timeout_ms = 2000)
mcp_transport_http(url, headers, auth, reconnect, connect_timeout = 30)
mcp_client(transport, name, version, roots, request_timeout = 60, max_total_timeout = 3600,
           protocol_version = "2025-11-25", on_notification, on_log)
#   $connect() $request() $notify() $ping() $list_tools() $call_tool() $call_many() $close()
mcp_to_llm_content(result, server, readable_resources, save)
mcp_limit_content(content, max_bytes = 20 * 1024)
mcp_tool_name(server, tool, is_taken)
```

#### 4.3.3 Behaviour

- **Own config**: `file.path(tools::R_user_dir("gptr", "config"), "mcp.json")` (user) and `<project>/.gptr/mcp.json` (project), both in the `mcpServers` shape. Also read `<project>/.mcp.json`, the de facto shared project file.
- **Foreign user-level files are not read silently.** `mcp_import()` or `options(gptr.mcp.foreign = TRUE)` enables them. When reading `~/.claude.json`, only `mcpServers` and `projects[[cwd]]$mcpServers` are touched.
- **Trust**: project-level files start commands, so they are used only after the user trusted the project once (stored in the user config directory). Until then `mcp_status()` lists them as skipped.
- **Value syntax accepted**: `${VAR}`, `${VAR:-default}`, `$VAR`, `${env:VAR}`, `{env:VAR}`, `$$`, `$!`, `!command`; `${input:...}` gives an actionable error. Values are resolved at connect time, never stored resolved.
- **Timeout unit**: gptr's own files use seconds. Values read from Claude Code files, and any value of 1000 or more, are taken as milliseconds. (Heuristic; see open questions.)
- **Lazy connection**: nothing is started when the package loads or when `gptr()` is called. A server is started on the first call of one of its tools, or when its tool list is needed and no cache exists. Tool metadata is cached in `tools::R_user_dir("gptr", "cache")/mcp/<sha256 of resolved config>.json` with the server version and a timestamp, so declarations and `tool_search` work without connecting. The cache is refreshed after each connect and on `notifications/tools/list_changed`.
- **Connections persist across `gptr()` calls** within one R session (they live in the package namespace), so a loop of `gptr()` calls does not restart servers. `reg.finalizer(..., onexit = TRUE)` closes them; processx's `cleanup_tree = TRUE` is the safety net.
- **Reconnect**: a dropped connection is re-opened on the next call. Tool calls are never retried automatically, except once after `mcp_session_expired` (the server did not run the request). HTTP connects are retried after 250 ms and 1000 ms for transient failures.
- **Timeouts**: per-request idle timeout (default 60 s) re-armed by progress notifications, plus a hard maximum (default 3600 s), as the spec asks. On timeout or user interrupt the client sends `notifications/cancelled`.
- **Capabilities declared**: `roots` only. No sampling, elicitation or tasks in v1. The `GET` server-to-client stream is off by default in v1 (a synchronous client only reads while it waits); `tools/list_changed` is still seen on response streams and on reconnect.
- **OAuth**: connections never open a browser. They raise a condition of class `mcp_auth_required` that carries the parsed challenge; `mcp_login()` runs the browser flow. Tokens live in `file.path(tools::R_user_dir("gptr", "config"), "mcp-auth.json")`, mode 0600, keyed by server URL. The callback port is stored and reused so a dynamically registered client stays valid.
- **Results**: `mcp_to_llm_content()` implements the table of section 2.2.7; `mcp_limit_content()` the 20 KiB middle cut with a spill file; R code receives untruncated values.
- **Exposure** (per server, overridable per tool with `toolExposure`): `code` (default; callable from R, declared in the R tool's description within the budget), `code-deferred` (callable, not listed), `deferred` (declared after `tool_search` loads it), `direct` (declared like a built-in tool), `hidden`. Pi's spellings `codemode` and `codemode-deferred` are accepted as synonyms. Codex's `enabled_tools` and `disabled_tools` map to `hidden`.
- **Permissions**: every MCP call passes the harness permission gate. `readOnlyHint = TRUE` may skip the prompt in intermediate modes, but annotations from servers are untrusted hints (the spec says so explicitly).

### 4.4 Tool search

```r
tool_search(query, limit = 8L, namespace = NULL)   # exported; also callable from model-written R code
tool_help(name)                                    # declaration and description of one tool
tools_list()                                       # data frame: name, namespace, exposure, description (first line)
```

- Model-facing tool `tool_search` with `{query, limit}`; it activates the matches for the next model call and answers in Pi's format (section 2.3).
- Ranker: the base-R port in section 5.7. The documents come from the tool metadata cache, so searching never starts a server.
- Activation is recorded in the session history so that replaying the history document reproduces the tool set.
- The ranker sits behind a function argument (`ranker = bm25_rank`) so that an embedding or hybrid ranker can replace it.

### 4.5 Tools as R functions (the codemode analogue)

#### 4.5.1 Principle

Pi needs a sandboxed second runtime because its host language is not the language the model writes. gptr's primary tool evaluates R in the live session, so the codemode surface collapses into ordinary R:

| Pi codemode | gptr |
|---|---|
| `await tools.read({ path })` | `tools$read(path = )` |
| `Promise.all([...])` | `lapply()` for sequential calls; `mcp_call_many()` / `agent_parallel()` for concurrency |
| `text(value)`, `console.log` | `print()`, `cat()`, `message()` (captured by the R tool, REQ-23) |
| `image(block)` | `gptr::show_image(x)`, or simply drawing a plot |
| `return value` | value of the last expression |
| `store(key, value)` / `load(key)` | plain assignment; objects persist in the session (REQ-22) |
| `ALL_TOOLS`, `searchTools()`, `describeTool()` | `tools_list()`, `tool_search()`, `tool_help()` |
| `models.classify(jev, { state, questions })` | `gptr(model = jev, ...)`, typed and vectorised (REQ-20) |
| QuickJS sandbox | none: the code runs with the user's rights, so the permission mode (REQ-37) is the control |

#### 4.5.2 The dispatcher object

- Export one object `tools` of S3 class `gptr_tools` with methods `$`, `[[`, `names`, `print`, `.DollarNames` (completion in RStudio and Positron). `tools$<id>` looks the tool up in the registry of the *active session* and returns a generated function.
- Why an exported object and not functions injected into an environment:
  - nothing is assigned into the user's global environment and `attach()` is not used;
  - **code written by the agent into the history document stays runnable later** (REQ-24): `gptr::tools$mcp__github__search_code(q = "x")` connects lazily when the script is sourced;
  - evaluating model code in a child environment would hide its assignments from the user (against REQ-22).
- The name `tools` does not collide with the base package `tools` at the language level (`tools::file_ext` is a namespace lookup), but it may confuse readers. See open questions.

#### 4.5.3 Generated functions

- Formals come from `inputSchema`: required properties first without default, optional properties with `NULL`, then `...`. Names that are not syntactic R names are kept and back-quoted.
- The body collects the supplied arguments, checks required ones (error message includes the usage line), coerces by schema, and calls `runner(tool, args)`.
- Identifier rule: replace characters outside `[A-Za-z0-9_.]` by `_`; prefix `t_` when the name does not start with a letter; append `_` to R reserved words. Examples verified: `my-tool` → `my_tool`, `_private` → `t_private`, `9lives` → `t_9lives`, `repeat` → `repeat_`.
- Coercion by schema (`coerce_to_schema()`): `array` always becomes a JSON array, also for one element; a data frame becomes an array of row objects; `object` needs a named list and an empty one becomes `{}`; `integer` must be whole; scalars of length other than 1 are an error raised before the call; factors become strings; `NA` becomes `null`.
- Return value: `structuredContent` (an R list) when present, else the text as one string; images are attached as attribute `"images"`. A tool error raises a condition of class `gptr_tool_error` that `tryCatch()` can handle.
- `runner` is the harness pipeline: nested-call record, `before` hook (permission gate, may block), execution, result conversion. Nested call ids are `<parent id>/<n>`. The record uses Pi's limits.

#### 4.5.4 Declarations shown to the model

Rendered by `render_tool_declaration()` (verified output):

```r
#' Join an array of tags (tests array coercion and name sanitising).
#' @param tags vector<string>
#' @param sep string, optional (default ",")
#' @return string (the tool's text output)
tools$mcp__fix__tags_join(tags, sep = NULL)
```

- Type strings from JSON Schema: `string`, `number`, `integer`, `logical`, `NULL`, `vector<T>`, `list(a: T, b?: T)`, `one of "a" | "b"`, unions with ` | `, `any`. Local `$ref`s are resolved; recursion gives `any`; nesting is cut at depth 3.
- Budget: 3000 estimated tokens for declarations in the R tool's description (or a system-prompt section), chosen round-robin over namespaces, cheapest first; every namespace is listed with its tool count and the listing says whether it is complete. The rest is found with `tool_search()`.
- Guidance to put in the prompt: assign tool results to variables and inspect them with `str()` or `head()` instead of printing them, because printed output is what reaches the context.

#### 4.5.5 Concurrency inside model-written code

- `mcp_call_many(calls)`: send all requests, then collect by id (verified for one server as `$call_many()`; four pipelined calls, errors isolated per call).
- For HTTP servers and model providers, several streams can be multiplexed in one R process with `curl::multi_add(data = )` and `curl::multi_run()` (verified: three 1.85 s streams finished in 1.92-1.95 s). This is the building block for in-process parallel sub-agents later; v1 should use processes.

### 4.6 Durable and coordinator concepts to borrow

| Concept | Borrow for gptr | How |
|---|---|---|
| Commit before show | yes | append the event to the session JSONL (with `useBytes = TRUE`) before printing it |
| Idempotent `requestId` | yes | when a history document is re-run, key each `gptr()` call by a hash of prompt, model and inputs and offer replay from the recorded result (REQ-24) |
| `replay: "safe"` per tool | yes | tools declare whether re-execution after an interruption is safe; others yield an `interrupted` result |
| Task ownership | yes | a sub-agent belongs to the tool call that started it: aborting the call aborts the child; the parent is busy while the child runs |
| Background boundary | later | background sub-agents that outlive the call need a supervisor; out of scope for v1 |
| Inbox (`steer`, `follow-up`, `reject`) | yes | the interactive console can queue a steering message between tool rounds (REQ-38) |
| Reset with handoff note | yes | alternative to compaction and the basis of cross-provider hand-off |
| Usage per model and per tool | yes | tool results may carry `usage`; sub-agents and System 1 calls report through it |
| One writer per session file | yes | each sub-agent writes its own session file; the parent records the path |
| Worker retirement by demand | later | only with a warm `r_session` pool |
| Protocol version in the first event | yes | `{"type":"session","version":N,...}` as the first JSONL line of a child |
| Socket coordinator, CBOR framing, Chord documents, multi-client attachment | no | gptr lives inside one R session; callr pipes are private and need no router or authentication |

---

## 5. Verified prototypes

Everything below was executed with `/usr/local/bin/Rscript --vanilla` on macOS, R 4.4.3, with `LANG=en_US.UTF-8` unless stated. Package versions: jsonlite 2.0.0, processx 3.8.6, callr 3.7.6, httr2 1.2.2, curl 7.0.0, openssl 2.3.5, httpuv 1.6.17, later 1.4.8, yaml 2.3.12, digest 0.6.39, ps 1.9.3. The machine was under load from other jobs (load average about 10 on 8 cores), so timings vary by some tenths of a second between runs.

The test files contain the constant `W <- "<absolute path of $W>"` (the literal track06 path); change it when re-running. Code is prototype quality: closures over environments instead of R6, few argument checks.

Verifier re-run (2026-09-29): every R block below was extracted from this report, `W` was repointed, and all tests were run again with `Rscript --vanilla` in a **C locale** (the shell had no `LANG`) with the package versions above: `test_stdio` 27/27, `test_http` 19/19, `test_stream` 3/3, `test_tools_fn` 12/12, `test_bm25` parity PASS (with Node 26.8.2), `test_subagents` 23/23, `test_abort_pids` PASS, `test_config` 18/18, `test_multi` PASS, `test_interrupt` and `test_backends` as described. They were run a second time against the **current CRAN releases** httr2 1.3.0, processx 3.9.0, callr 3.8.0 and rlang 1.3.0 (installed in a temporary library) with the same results. Note that CRAN now also has curl 8.0.0 and openssl 2.4.2, which were not tested. Three literal non-ASCII characters in library/test code (`…` in `truncate_middle()` and in one `test_stdio.R` line, a literal BOM in `subagents.R`) were replaced by `\u2026` / `\ufeff` escapes after this re-run (see 6.1); the escaped versions pass 27/27 and 23/23 in both C and `en_US.UTF-8` locales.

### 5.1 MCP client library (`mcp_client.R`)

`````r
# Prototype: pure-R MCP client (JSON-RPC core + stdio transport + streamable HTTP transport)
# Dependencies: jsonlite, processx (stdio), httr2 (http). No compiled code of our own.

MCP_LATEST <- "2025-11-25"
MCP_SUPPORTED <- c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
MCP_MAX_MESSAGE_BYTES <- 16 * 1024^2
MCP_MAX_STDERR_BYTES <- 64 * 1024

`%||%` <- function(a, b) if (is.null(a)) b else a
mcp_obj <- function() structure(list(), names = character(0))
mcp_to_json <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, force = TRUE))
}
mcp_from_json <- function(s) jsonlite::fromJSON(s, simplifyVector = FALSE, bigint_as_char = FALSE)
now_ms <- function() as.numeric(Sys.time()) * 1000

mcp_abort <- function(message, class = NULL, ...) {
  stop(structure(class = c(class, "mcp_error", "error", "condition"),
                 list(message = message, call = NULL, ...)))
}
is_response <- function(m) !is.null(m$id) && is.null(m$method) && (!is.null(m$error) || "result" %in% names(m))
is_request <- function(m) !is.null(m$id) && !is.null(m$method)
is_notification <- function(m) is.null(m$id) && !is.null(m$method)

# ---------------------------------------------------------------------------
# stdio transport
# ---------------------------------------------------------------------------
mcp_transport_stdio <- function(command, args = character(), env = NULL, cwd = NULL,
                                inherit_env = TRUE, close_timeout_ms = 2000) {
  self <- new.env(parent = emptyenv())
  self$kind <- "stdio"; self$proc <- NULL; self$stderr <- ""; self$closed <- FALSE

  self$start <- function() {
    penv <- if (length(env)) c(if (inherit_env) "current", unlist(env)) else if (inherit_env) NULL else character()
    self$proc <- processx::process$new(
      command, args, stdin = "|", stdout = "|", stderr = "|",
      env = penv, wd = cwd, cleanup = TRUE, cleanup_tree = TRUE,
      windows_hide_window = TRUE, encoding = "UTF-8")
    invisible(TRUE)
  }
  drain_stderr <- function() {
    if (is.null(self$proc) || !self$proc$has_error_connection()) return(invisible())
    chunk <- tryCatch(self$proc$read_error(), error = function(e) "")
    if (nzchar(chunk)) {
      s <- paste0(self$stderr, chunk)
      n <- nchar(s, type = "bytes")
      if (n > MCP_MAX_STDERR_BYTES) s <- substring(s, nchar(s) - MCP_MAX_STDERR_BYTES + 1L)
      self$stderr <- s
    }
  }
  self$pending <- list()
  read_available <- function() {
    lines <- tryCatch(self$proc$read_output_lines(), error = function(e) character())
    out <- list()
    for (ln in lines) {
      ln <- sub("\r$", "", ln)
      if (!nzchar(trimws(ln))) next
      if (nchar(ln, type = "bytes") > MCP_MAX_MESSAGE_BYTES) next
      m <- tryCatch(mcp_from_json(ln), error = function(e) NULL)
      if (is.null(m) || !identical(m$jsonrpc, "2.0")) next   # stray non-JSON output is ignored
      out[[length(out) + 1L]] <- m
    }
    out
  }
  self$send <- function(msg) {
    if (self$closed || is.null(self$proc) || !self$proc$is_alive())
      mcp_abort(paste0("MCP stdio server is not running.", stderr_note()), "mcp_connection_closed")
    rest <- self$proc$write_input(paste0(mcp_to_json(msg), "\n"), sep = "")
    while (length(rest) > 0) {
      # The pipe is full: the server may be blocked writing to us, so keep reading.
      self$pending <- c(self$pending, read_available()); drain_stderr()
      if (!self$proc$is_alive()) mcp_abort("MCP stdio server exited while writing", "mcp_connection_closed")
      self$proc$poll_io(10)
      rest <- self$proc$write_input(rest, sep = "")
    }
    invisible(TRUE)
  }
  stderr_note <- function() {
    drain_stderr()
    s <- trimws(self$stderr)
    if (nzchar(s)) paste0("\nstderr (tail):\n", substring(s, max(1L, nchar(s) - 2000L))) else ""
  }
  self$stderr_tail <- function(n = 2000L) { drain_stderr(); s <- trimws(self$stderr); substring(s, max(1L, nchar(s) - n)) }
  self$receive <- function(timeout_ms = 100) {
    if (length(self$pending)) { out <- self$pending; self$pending <- list(); return(out) }
    if (is.null(self$proc)) return(list())
    self$proc$poll_io(as.integer(max(0, timeout_ms)))
    drain_stderr()
    read_available()
  }
  self$is_open <- function() !self$closed && !is.null(self$proc) &&
    (self$proc$is_alive() || self$proc$is_incomplete_output())
  self$set_protocol_version <- function(v) invisible(NULL)
  self$close <- function() {
    if (self$closed) return(invisible()); self$closed <- TRUE
    p <- self$proc; if (is.null(p)) return(invisible())
    # Spec shutdown: close stdin, wait, SIGTERM, wait, SIGKILL (whole tree).
    try(close(p$get_input_connection()), silent = TRUE)
    p$wait(timeout = 500)
    if (p$is_alive()) { try(p$signal(15L), silent = TRUE); p$wait(timeout = close_timeout_ms) }
    if (p$is_alive()) try(p$kill_tree(), silent = TRUE) else try(p$kill_tree(), silent = TRUE)
    drain_stderr()
    invisible()
  }
  self
}

# ---------------------------------------------------------------------------
# SSE parser (own implementation: httr2::resp_stream_sse drops events with empty
# data and ignores `retry`, both of which MCP resumption needs)
# ---------------------------------------------------------------------------
sse_parser <- function() {
  st <- new.env(parent = emptyenv())
  st$event <- NULL; st$id <- NULL; st$data <- character(); st$last_id <- NULL; st$retry_ms <- NULL
  st$feed_line <- function(line) {
    line <- sub("\r$", "", line)
    if (identical(line, "")) {                          # dispatch
      ev <- NULL
      if (length(st$data)) ev <- list(event = st$event %||% "message",
                                      data = paste(st$data, collapse = "\n"), id = st$id)
      st$event <- NULL; st$id <- NULL; st$data <- character()
      return(ev)
    }
    if (startsWith(line, ":")) return(NULL)             # comment / keep-alive
    colon <- regexpr(":", line, fixed = TRUE)
    field <- if (colon < 0) line else substr(line, 1L, colon - 1L)
    value <- if (colon < 0) "" else substring(line, colon + 1L)
    if (startsWith(value, " ")) value <- substring(value, 2L)
    if (field == "data") st$data <- c(st$data, value)
    else if (field == "event") st$event <- value
    else if (field == "id") { if (!grepl("\\0", value, fixed = TRUE)) { st$id <- value; st$last_id <- value } }
    else if (field == "retry" && grepl("^[0-9]+$", value)) st$retry_ms <- as.numeric(value)
    NULL
  }
  st
}

# ---------------------------------------------------------------------------
# Streamable HTTP transport
# auth: NULL or list(token = function() chr|NULL, on_unauthorized = function(resp, token) NULL)
# ---------------------------------------------------------------------------
mcp_transport_http <- function(url, headers = list(), auth = NULL,
                               reconnect = list(initial_delay_ms = 1000, max_delay_ms = 30000, max_retries = 5),
                               connect_timeout = 30) {
  self <- new.env(parent = emptyenv())
  self$kind <- "http"; self$url <- url; self$session_id <- NULL; self$protocol_version <- NULL
  self$inbox <- list(); self$streams <- list(); self$closed <- FALSE; self$started <- FALSE
  self$log <- character()

  build <- function(method, extra = list(), body = NULL) {
    h <- c(headers, extra)
    if (!is.null(self$session_id)) h[["Mcp-Session-Id"]] <- self$session_id
    if (!is.null(self$protocol_version)) h[["MCP-Protocol-Version"]] <- self$protocol_version
    token <- if (!is.null(auth)) auth$token() else NULL
    if (!is.null(token)) h[["Authorization"]] <- paste("Bearer", token)
    req <- httr2::request(self$url)
    req <- httr2::req_method(req, method)
    req <- do.call(httr2::req_headers, c(list(req), h, list(.redact = "Authorization")))
    req <- httr2::req_error(req, is_error = function(resp) FALSE)
    req <- httr2::req_options(req, connecttimeout = connect_timeout)
    if (!is.null(body)) req <- httr2::req_body_raw(req, body, type = "application/json")
    list(req = req, token = token)
  }
  needs_auth <- function(resp) {
    s <- httr2::resp_status(resp)
    if (s == 401L) return(TRUE)
    if (s != 403L) return(FALSE)
    grepl("(^|[\\s,])error=\"?insufficient_scope\"?", httr2::resp_header(resp, "www-authenticate") %||% "",
          perl = TRUE, ignore.case = TRUE)
  }
  perform <- function(method, extra = list(), body = NULL) {
    for (attempt in 0:1) {
      b <- build(method, extra, body)
      resp <- httr2::req_perform_connection(b$req, blocking = FALSE)
      if (attempt > 0 || is.null(auth) || is.null(auth$on_unauthorized) || !needs_auth(resp)) return(resp)
      rejected <- resp
      # Refreshes the tokens, or signals mcp_auth_required when the user has to sign in.
      tryCatch(auth$on_unauthorized(rejected, b$token), finally = try(close(rejected), silent = TRUE))
    }
  }
  read_all <- function(resp, limit = MCP_MAX_MESSAGE_BYTES, timeout_ms = 60000) {
    buf <- raw(); deadline <- now_ms() + timeout_ms
    repeat {
      chunk <- httr2::resp_stream_raw(resp, kb = 64)
      if (length(chunk)) buf <- c(buf, chunk)
      if (length(buf) > limit) break
      if (httr2::resp_stream_is_complete(resp)) break
      if (!length(chunk)) { if (now_ms() > deadline) break; Sys.sleep(0.005) }
    }
    s <- rawToChar(buf); Encoding(s) <- "UTF-8"; s
  }
  check <- function(resp) {
    s <- httr2::resp_status(resp)
    if (s >= 200L && s < 300L) return(invisible())
    body <- substr(tryCatch(read_all(resp, 8 * 1024, 2000), error = function(e) ""), 1L, 500L)
    try(close(resp), silent = TRUE)
    if (s == 401L) mcp_abort("MCP server requires authentication", c("mcp_auth_required", "mcp_http_error"),
                             status = s, www_authenticate = httr2::resp_header(resp, "www-authenticate"))
    if (s == 404L && !is.null(self$session_id))
      mcp_abort("MCP session expired", c("mcp_session_expired", "mcp_http_error"), status = s)
    mcp_abort(sprintf("MCP HTTP request failed with status %d%s", s,
                      if (nzchar(trimws(body))) paste0(": ", trimws(body)) else ""),
              "mcp_http_error", status = s, body = body)
  }
  capture_session <- function(resp) {
    sid <- httr2::resp_header(resp, "mcp-session-id")
    if (!is.null(sid) && nzchar(sid)) self$session_id <- sid
  }
  content_type <- function(resp) {
    ct <- httr2::resp_header(resp, "content-type")
    if (is.null(ct)) NULL else tolower(trimws(strsplit(ct, ";", fixed = TRUE)[[1]][1]))
  }

  self$start <- function() { self$started <- TRUE; invisible(TRUE) }
  self$set_protocol_version <- function(v) self$protocol_version <- v
  self$is_open <- function() !self$closed

  self$send <- function(msg) {
    if (!self$started || self$closed) mcp_abort("MCP HTTP transport is closed", "mcp_connection_closed")
    resp <- perform("POST", list(Accept = "application/json, text/event-stream"), mcp_to_json(msg))
    check(resp); capture_session(resp)
    if (!is_request(msg)) { try(close(resp), silent = TRUE); return(invisible(TRUE)) }
    st <- httr2::resp_status(resp)
    if (st %in% c(202L, 204L)) {
      try(close(resp), silent = TRUE)
      mcp_abort(sprintf("MCP server accepted request %s without a response", msg$method), "mcp_http_error", status = st)
    }
    ct <- content_type(resp)
    if (identical(ct, "application/json")) {
      body <- mcp_from_json(read_all(resp)); try(close(resp), silent = TRUE)
      items <- if (is.null(names(body))) body else list(body)
      self$inbox <- c(self$inbox, items)
    } else if (identical(ct, "text/event-stream")) {
      self$streams[[length(self$streams) + 1L]] <- list2env(list(
        resp = resp, request_id = msg$id, parser = sse_parser(), answered = FALSE,
        attempt = 0L, received = FALSE, wake_at = NULL), parent = emptyenv())
    } else {
      try(close(resp), silent = TRUE)
      mcp_abort(paste0("Unsupported MCP response content type: ", ct %||% "missing"), "mcp_http_error", status = st)
    }
    invisible(TRUE)
  }

  fail_stream <- function(s, reason) {
    self$inbox[[length(self$inbox) + 1L]] <- list(jsonrpc = "2.0", id = s$request_id,
      error = list(code = -32603, message = paste0("MCP response stream failed: ", reason)))
    s$answered <- TRUE
  }
  pump_stream <- function(s) {
    if (!is.null(s$wake_at)) {                 # waiting to resume
      if (now_ms() < s$wake_at) return(invisible())
      s$wake_at <- NULL
      resp <- tryCatch(perform("GET", c(list(Accept = "text/event-stream"),
                                        list(`Last-Event-ID` = s$parser$last_id)), NULL),
                       error = function(e) e)
      if (inherits(resp, "error")) return(schedule_resume(s, conditionMessage(resp)))
      stc <- httr2::resp_status(resp)
      if (stc == 405L || !identical(content_type(resp), "text/event-stream")) {
        try(close(resp), silent = TRUE); return(fail_stream(s, sprintf("cannot resume (HTTP %d)", stc)))
      }
      if (stc >= 400L) {
        try(close(resp), silent = TRUE)
        if (stc %in% c(408L, 429L) || stc >= 500L) return(schedule_resume(s, sprintf("HTTP %d", stc)))
        return(fail_stream(s, sprintf("HTTP %d", stc)))
      }
      self$log <- c(self$log, paste0("resumed with Last-Event-ID=", s$parser$last_id))
      s$resp <- resp; s$received <- FALSE
    }
    lines <- tryCatch(httr2::resp_stream_lines(s$resp, lines = 1000, warn = FALSE), error = function(e) e)
    if (inherits(lines, "error")) return(schedule_resume(s, conditionMessage(lines)))
    for (ln in lines) {
      ev <- s$parser$feed_line(ln)
      if (is.null(ev)) next
      s$received <- TRUE
      if (!nzchar(trimws(ev$data)) || !identical(ev$event, "message")) next
      m <- tryCatch(mcp_from_json(ev$data), error = function(e) NULL)
      if (is.null(m)) next
      if (is_response(m) && identical(m$id, s$request_id)) s$answered <- TRUE
      self$inbox[[length(self$inbox) + 1L]] <- m
    }
    if (!s$answered && httr2::resp_stream_is_complete(s$resp)) {
      try(close(s$resp), silent = TRUE)
      schedule_resume(s, "stream ended without a response")
    }
    invisible()
  }
  schedule_resume <- function(s, reason) {
    if (is.null(s$parser$last_id) || s$attempt >= reconnect$max_retries) return(fail_stream(s, reason))
    if (isTRUE(s$received)) s$attempt <- 0L
    delay <- s$parser$retry_ms %||% min(reconnect$initial_delay_ms * 2^s$attempt, reconnect$max_delay_ms)
    s$attempt <- s$attempt + 1L
    s$wake_at <- now_ms() + delay
    invisible()
  }

  self$receive <- function(timeout_ms = 100) {
    deadline <- now_ms() + timeout_ms
    repeat {
      for (s in self$streams) if (!s$answered) pump_stream(s)
      self$streams <- Filter(function(s) { if (s$answered) try(close(s$resp), silent = TRUE); !s$answered },
                             self$streams)
      if (length(self$inbox)) { out <- self$inbox; self$inbox <- list(); return(out) }
      if (now_ms() >= deadline) return(list())
      Sys.sleep(0.01)
    }
  }
  self$close <- function() {
    if (self$closed) return(invisible()); self$closed <- TRUE
    for (s in self$streams) try(close(s$resp), silent = TRUE)
    if (self$started && !is.null(self$session_id)) {
      try({
        b <- build("DELETE"); req <- httr2::req_timeout(b$req, 1)
        httr2::req_perform(req)
      }, silent = TRUE)
    }
    invisible()
  }
  self
}

# ---------------------------------------------------------------------------
# Client core: correlation, initialization, timeouts, cancellation, server requests
# ---------------------------------------------------------------------------
mcp_client <- function(transport, name = "gptr", version = "0.0.0.9000", roots = NULL,
                       request_timeout = 60, max_total_timeout = 3600,
                       protocol_version = MCP_LATEST,
                       on_notification = NULL, on_log = NULL) {
  self <- new.env(parent = emptyenv())
  self$transport <- transport; self$state <- "idle"; self$next_id <- 1L
  self$responses <- list(); self$server_info <- NULL; self$capabilities <- NULL
  self$instructions <- NULL; self$protocol_version <- NULL; self$tools_dirty <- FALSE
  self$progress <- list()      # token -> list(on_progress, touched)

  handlers <- list(
    ping = function(params) mcp_obj(),
    `roots/list` = if (!is.null(roots)) function(params) list(roots = if (is.function(roots)) roots() else roots)
  )
  handlers <- Filter(Negate(is.null), handlers)

  dispatch <- function(m) {
    if (is_response(m)) { self$responses[[as.character(m$id)]] <- m; return(invisible()) }
    if (is_request(m)) {
      h <- handlers[[m$method]]
      out <- if (is.null(h)) list(jsonrpc = "2.0", id = m$id,
                                  error = list(code = -32601, message = paste0("Method not found: ", m$method)))
             else tryCatch(list(jsonrpc = "2.0", id = m$id, result = h(m$params)),
                           error = function(e) list(jsonrpc = "2.0", id = m$id,
                                                    error = list(code = -32603, message = conditionMessage(e))))
      try(self$transport$send(out), silent = TRUE)
      return(invisible())
    }
    if (is_notification(m)) {
      if (identical(m$method, "notifications/progress")) {
        key <- as.character(m$params$progressToken)
        p <- self$progress[[key]]
        if (!is.null(p)) {
          self$progress[[key]]$touched <- now_ms()
          if (is.function(p$on_progress)) try(p$on_progress(m$params), silent = TRUE)
        }
      } else if (identical(m$method, "notifications/tools/list_changed")) self$tools_dirty <- TRUE
      else if (identical(m$method, "notifications/message") && is.function(on_log)) try(on_log(m$params), silent = TRUE)
      if (is.function(on_notification)) try(on_notification(m$method, m$params), silent = TRUE)
    }
    invisible()
  }

  send_request <- function(method, params = NULL, on_progress = NULL) {
    id <- self$next_id; self$next_id <- id + 1L
    if (!is.null(on_progress)) {
      params <- params %||% list()
      params[["_meta"]] <- c(params[["_meta"]] %||% list(), list(progressToken = id))
    }
    msg <- list(jsonrpc = "2.0", id = id, method = method)
    if (!is.null(params)) msg$params <- params
    self$progress[[as.character(id)]] <- list(on_progress = on_progress, touched = now_ms())
    self$transport$send(msg)
    id
  }
  cancel <- function(id, reason) {
    try(self$transport$send(list(jsonrpc = "2.0", method = "notifications/cancelled",
                                 params = list(requestId = id, reason = reason))), silent = TRUE)
  }
  # Wait for the responses of `ids`. Progress resets the per-request clock.
  await <- function(ids, timeout, cancellable = TRUE) {
    keys <- as.character(ids); started <- now_ms()
    on.exit(for (k in keys) self$progress[[k]] <- NULL, add = TRUE)
    out <- withCallingHandlers(
      repeat {
        if (all(keys %in% names(self$responses))) break
        last <- max(vapply(keys, function(k) self$progress[[k]]$touched %||% started, numeric(1)))
        remaining <- min(last + timeout * 1000, started + max_total_timeout * 1000) - now_ms()
        if (remaining <= 0) {
          for (k in setdiff(keys, names(self$responses))) if (cancellable) cancel(as.integer(k), "Request timed out")
          mcp_abort(sprintf("MCP request timed out after %gs", timeout), "mcp_timeout")
        }
        msgs <- self$transport$receive(min(remaining, 200))
        for (m in msgs) dispatch(m)
        if (!length(msgs) && !self$transport$is_open()) {
          tail <- if (is.function(self$transport$stderr_tail)) self$transport$stderr_tail() else ""
          self$state <- "closed"
          mcp_abort(paste0("MCP connection closed", if (nzchar(tail)) paste0("\n", tail) else ""),
                    "mcp_connection_closed")
        }
      },
      interrupt = function(cnd) {                       # user pressed Esc / Ctrl-C
        for (k in setdiff(keys, names(self$responses))) if (cancellable) cancel(as.integer(k), "Aborted")
      })
    res <- self$responses[keys]; self$responses[keys] <- NULL
    lapply(res, function(m) {
      if (!is.null(m$error)) structure(class = c("mcp_rpc_error", "mcp_error", "error", "condition"),
        list(message = m$error$message %||% "MCP error", call = NULL, code = m$error$code, data = m$error$data))
      else m$result
    })
  }
  request <- function(method, params = NULL, timeout = request_timeout, on_progress = NULL,
                      allow_connecting = FALSE) {
    if (!(self$state == "connected" || (allow_connecting && self$state == "connecting")))
      mcp_abort(paste0("MCP client is ", self$state), "mcp_connection_closed")
    id <- send_request(method, params, on_progress)
    res <- await(id, timeout, cancellable = !identical(method, "initialize"))[[1]]
    if (inherits(res, "error")) stop(res)
    res
  }
  self$request <- request
  self$notify <- function(method, params = NULL) {
    msg <- list(jsonrpc = "2.0", method = method); if (!is.null(params)) msg$params <- params
    self$transport$send(msg)
  }
  self$connect <- function() {
    if (self$state != "idle") mcp_abort(paste0("Cannot connect MCP client in state ", self$state))
    self$state <- "connecting"
    ok <- FALSE
    on.exit(if (!ok) { self$state <- "closed"; try(self$transport$close(), silent = TRUE) }, add = TRUE)
    self$transport$start()
    caps <- mcp_obj(); if (!is.null(roots)) caps <- list(roots = mcp_obj())
    res <- request("initialize", list(protocolVersion = protocol_version, capabilities = caps,
                                      clientInfo = list(name = name, version = version)),
                   allow_connecting = TRUE)
    if (!is.character(res$protocolVersion) || !is.list(res$serverInfo))
      mcp_abort("Invalid MCP initialize result")
    if (!res$protocolVersion %in% MCP_SUPPORTED)
      mcp_abort(paste0("MCP server selected unsupported protocol version ", res$protocolVersion))
    self$protocol_version <- res$protocolVersion; self$server_info <- res$serverInfo
    self$capabilities <- res$capabilities; self$instructions <- res$instructions
    self$transport$set_protocol_version(res$protocolVersion)
    self$notify("notifications/initialized")
    self$state <- "connected"; ok <- TRUE
    invisible(res)
  }
  self$ping <- function() invisible(request("ping", timeout = 10))
  self$list_tools <- function() {
    tools <- list(); cursor <- NULL; seen <- character()
    for (page in seq_len(1000L)) {
      res <- request("tools/list", if (!is.null(cursor)) list(cursor = cursor))
      if (!is.list(res$tools)) mcp_abort("Invalid MCP tools/list result")
      tools <- c(tools, Filter(function(t) is.character(t$name) && is.list(t$inputSchema), res$tools))
      cursor <- res$nextCursor
      if (is.null(cursor)) { self$tools_dirty <- FALSE; return(tools) }
      if (cursor %in% seen) mcp_abort(paste0("MCP tools/list returned duplicate cursor: ", cursor))
      seen <- c(seen, cursor)
    }
    mcp_abort("MCP tools/list exceeded 1000 pages")
  }
  norm_result <- function(res) { if (is.null(res$content)) res$content <- list(); res }
  self$call_tool <- function(name, arguments = NULL, timeout = request_timeout, on_progress = NULL) {
    params <- list(name = name)
    if (!is.null(arguments)) params$arguments <- if (length(arguments)) arguments else mcp_obj()
    norm_result(request("tools/call", params, timeout = timeout, on_progress = on_progress))
  }
  # Pipelined calls: send everything, then collect. Errors are returned as condition objects.
  self$call_many <- function(calls, timeout = request_timeout) {
    ids <- vapply(calls, function(cl) {
      params <- list(name = cl$name)
      if (!is.null(cl$arguments)) params$arguments <- if (length(cl$arguments)) cl$arguments else mcp_obj()
      send_request("tools/call", params)
    }, integer(1))
    res <- await(ids, timeout)
    unname(lapply(res, function(r) if (inherits(r, "error")) r else norm_result(r)))
  }
  self$close <- function() { self$state <- "closed"; self$transport$close(); invisible() }
  self
}

# ---------------------------------------------------------------------------
# Result conversion (mirrors pi-mcp toLlmContent + coding-agent limitMcpContent)
# ---------------------------------------------------------------------------
mcp_to_llm_content <- function(result, server = "", readable_resources = FALSE, save = NULL) {
  save <- save %||% function(data, ext) {
    path <- tempfile("gptr-mcp-", fileext = ext)
    if (is.raw(data)) writeBin(data, path) else writeLines(enc2utf8(data), path, useBytes = TRUE)
    try(Sys.chmod(path, "0600"), silent = TRUE); path
  }
  is_text_mime <- function(m) {
    if (is.null(m)) return(FALSE)
    t <- tolower(trimws(strsplit(m, ";", fixed = TRUE)[[1]][1]))
    startsWith(t, "text/") || t == "application/json" || endsWith(t, "+json") || endsWith(t, "+xml")
  }
  one <- function(b) {
    switch(b$type %||% "",
      text = list(type = "text", text = b$text),
      image = list(type = "image", data = b$data, mimeType = b$mimeType),
      audio = list(type = "text", text = sprintf("[audio %s omitted]", b$mimeType)),
      resource_link = list(type = "text", text = sprintf("[Resource %s \"%s\"%s%s]", b$uri, b$title %||% b$name,
          if (!is.null(b$description)) paste0(": ", b$description) else "",
          if (readable_resources) sprintf(". Read it with read_mcp_resource (server \"%s\")", server) else "")),
      resource = {
        r <- b$resource
        if (!is.null(r$text)) list(type = "text", text = r$text)
        else if (startsWith(r$mimeType %||% "", "image/")) list(type = "image", data = r$blob, mimeType = r$mimeType)
        else {
          raw <- jsonlite::base64_dec(r$blob)
          if (is_text_mime(r$mimeType)) { s <- rawToChar(raw); Encoding(s) <- "UTF-8"; list(type = "text", text = s) }
          else {
            ext <- regmatches(r$uri, regexpr("\\.[A-Za-z0-9]{1,8}$", r$uri)); if (!length(ext)) ext <- ".bin"
            list(type = "text", text = sprintf("[Binary resource %s (%s, %d bytes) saved to %s]", r$uri,
                 r$mimeType %||% "unknown type", length(raw), save(raw, ext)))
          }
        }
      },
      list(type = "text", text = sprintf("[unsupported MCP content %s]", b$type %||% "?")))
  }
  content <- lapply(result$content %||% list(), one)
  if (!length(content) && !is.null(result$structuredContent))
    content <- list(list(type = "text", text = as.character(jsonlite::toJSON(result$structuredContent,
                         auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA))))
  if (isTRUE(result$isError) && !any(vapply(content, function(b) b$type == "text" && nzchar(b$text), logical(1))))
    content <- c(content, list(list(type = "text", text = "MCP tool returned an error")))
  content
}

truncate_middle <- function(text, max_bytes = 20 * 1024) {
  raw <- charToRaw(enc2utf8(text)); n <- length(raw)
  total_lines <- length(strsplit(text, "\n", fixed = TRUE)[[1]])
  if (n <= max_bytes) return(list(content = text, truncated = FALSE, total_bytes = n, total_lines = total_lines))
  is_boundary <- function(i) i > n || bitwAnd(as.integer(raw[i]), 0xC0L) != 0x80L   # 1-based index of a char start
  head_end <- max_bytes %/% 2L                      # bytes kept at the start
  while (head_end > 0 && !is_boundary(head_end + 1L)) head_end <- head_end - 1L
  tail_start <- n - (max_bytes - max_bytes %/% 2L) + 1L
  while (tail_start <= n && !is_boundary(tail_start)) tail_start <- tail_start + 1L
  conv <- function(r) { s <- rawToChar(r); Encoding(s) <- "UTF-8"; s }
  head <- conv(raw[seq_len(head_end)]); tail <- if (tail_start <= n) conv(raw[tail_start:n]) else ""
  removed <- nchar(conv(raw[(head_end + 1L):(tail_start - 1L)]), type = "chars")
  list(content = sprintf("%s\u2026%d chars truncated\u2026%s", head, removed, tail),
       truncated = TRUE, total_bytes = n, total_lines = total_lines, removed_chars = removed)
}

mcp_limit_content <- function(content, max_bytes = 20 * 1024) {
  texts <- vapply(Filter(function(b) b$type == "text", content), function(b) b$text, character(1))
  combined <- paste(texts, collapse = "\n")
  tr <- truncate_middle(combined, max_bytes)
  if (!tr$truncated) return(list(content = content))
  path <- tempfile("gptr-mcp-", fileext = ".txt")
  con <- file(path, open = "wb"); writeBin(charToRaw(enc2utf8(combined)), con); close(con)
  try(Sys.chmod(path, "0600"), silent = TRUE)
  text <- sprintf("Warning: truncated output (original token count: %d)\nTotal output lines: %d\n\n%s\n\n[Full output: %s (read it with offset/limit)]",
                  ceiling(tr$total_bytes / 4), tr$total_lines, tr$content, path)
  list(content = c(list(list(type = "text", text = text)), Filter(function(b) b$type == "image", content)),
       full_output_path = path)
}

# mcp__<server>__<tool>, sanitised to [A-Za-z0-9_-], max 64 chars, sha256 suffix on overflow/collision
mcp_tool_name <- function(server, tool, is_taken = function(name) FALSE) {
  name <- gsub("[^A-Za-z0-9_-]", "_", paste0("mcp__", server, "__", tool))
  if (nchar(name) <= 64L && !is_taken(name)) return(name)
  hash <- substr(digest::digest(c(charToRaw(enc2utf8(server)), as.raw(0), charToRaw(enc2utf8(tool))),
                                algo = "sha256", serialize = FALSE), 1L, 8L)
  paste0(substr(name, 1L, 64L - nchar(hash) - 1L), "_", hash)
}
`````

### 5.2 stdio fixture server in pure R (`fixture_mcp_stdio.R`)

Usable later as the testthat fixture: it needs no network and no Node.

`````r
# Minimal MCP stdio server written in pure R (test fixture).
# Run: Rscript --vanilla fixture_mcp_stdio.R
# Speaks newline-delimited JSON-RPC 2.0 on stdin/stdout, logs to stderr.
suppressWarnings(suppressMessages(library(jsonlite)))

obj <- function(...) { x <- list(...); if (length(x) == 0) structure(list(), names = character(0)) else x }
OUT <- stdout()
send <- function(msg) {
  # useBytes = TRUE: never let R re-encode UTF-8 JSON to the native locale (C locale would write <c3><a9>)
  writeLines(enc2utf8(as.character(toJSON(msg, auto_unbox = TRUE, null = "null", digits = NA))), OUT, useBytes = TRUE)
  flush(OUT)
}
reply <- function(id, result) send(list(jsonrpc = "2.0", id = id, result = result))
fail  <- function(id, code, message) send(list(jsonrpc = "2.0", id = id, error = list(code = code, message = message)))

SUPPORTED <- c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
# 1x1 transparent PNG
PNG_B64 <- "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

TOOLS <- list(
  list(name = "echo", title = "Echo", description = "Echo the text back.",
       inputSchema = list(type = "object",
                          properties = list(text = list(type = "string", description = "Text to echo")),
                          required = list("text")),
       annotations = list(readOnlyHint = TRUE)),
  list(name = "add", description = "Add two numbers and return structured content.",
       inputSchema = list(type = "object",
                          properties = list(a = list(type = "number"), b = list(type = "number")),
                          required = list("a", "b")),
       outputSchema = list(type = "object", properties = list(sum = list(type = "number")),
                           required = list("sum"))),
  list(name = "tags.join", description = "Join an array of tags (tests array coercion and name sanitising).",
       inputSchema = list(type = "object",
                          properties = list(tags = list(type = "array", items = list(type = "string")),
                                            sep = list(type = "string", default = ",")),
                          required = list("tags"))),
  list(name = "image", description = "Return a 1x1 PNG image.",
       inputSchema = list(type = "object", properties = obj())),
  list(name = "slow", description = "Sleep for `seconds`, sending progress notifications.",
       inputSchema = list(type = "object", properties = list(seconds = list(type = "number")))),
  list(name = "fail", description = "Always returns isError = true.",
       inputSchema = list(type = "object")),
  list(name = "big", description = "Return `n` bytes of text.",
       inputSchema = list(type = "object", properties = list(n = list(type = "integer")))),
  list(name = "roots", description = "Asks the client for its roots (server-to-client request) and returns them.",
       inputSchema = list(type = "object", properties = obj()))
)
PAGE <- 3L

cat("fixture: ready\n", file = stderr())
con <- file("stdin", open = "r")
pending_roots <- NULL   # id of the tools/call waiting on a roots/list answer
next_server_id <- 1000L
cancelled <- character()

repeat {
  line <- readLines(con, n = 1L, warn = FALSE, encoding = "UTF-8")
  if (length(line) == 0) break            # stdin closed -> exit (spec shutdown)
  if (!nzchar(trimws(line))) next
  msg <- tryCatch(fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(msg)) { cat("fixture: bad json\n", file = stderr()); next }

  # Response to a server-initiated request (roots/list)
  if (is.null(msg$method) && !is.null(msg$id)) {
    if (!is.null(pending_roots)) {
      reply(pending_roots, list(content = list(list(type = "text",
            text = toJSON(msg$result$roots, auto_unbox = TRUE)))))
      pending_roots <- NULL
    }
    next
  }
  method <- msg$method; id <- msg$id; params <- msg$params
  if (is.null(id)) {                       # notification
    if (identical(method, "notifications/cancelled")) cancelled <- c(cancelled, as.character(params$requestId))
    next
  }
  switch(method,
    "initialize" = {
      v <- params$protocolVersion
      reply(id, list(protocolVersion = if (v %in% SUPPORTED) v else SUPPORTED[1],
                     capabilities = list(tools = list(listChanged = TRUE), logging = obj()),
                     serverInfo = list(name = "r-fixture", version = "0.0.1"),
                     instructions = "Fixture server. Tools are toys."))
    },
    "ping" = reply(id, obj()),
    "tools/list" = {
      start <- if (is.null(params$cursor)) 1L else as.integer(params$cursor)
      end <- min(length(TOOLS), start + PAGE - 1L)
      res <- list(tools = TOOLS[start:end])
      if (end < length(TOOLS)) res$nextCursor <- as.character(end + 1L)
      reply(id, res)
    },
    "tools/call" = {
      a <- params$arguments; name <- params$name
      token <- params$`_meta`$progressToken
      switch(name,
        "echo" = reply(id, list(content = list(list(type = "text", text = as.character(a$text))))),
        "add" = {
          s <- a$a + a$b
          reply(id, list(content = list(list(type = "text", text = toJSON(list(sum = s), auto_unbox = TRUE))),
                         structuredContent = list(sum = s)))
        },
        "tags.join" = {
          # Proves the client sent a JSON array even for one tag.
          if (!is.list(a$tags)) reply(id, list(isError = TRUE,
              content = list(list(type = "text", text = "tags was not an array"))))
          else reply(id, list(content = list(list(type = "text",
              text = paste(unlist(a$tags), collapse = if (is.null(a$sep)) "," else a$sep)))))
        },
        "image" = reply(id, list(content = list(list(type = "text", text = "one pixel"),
                                                list(type = "image", data = PNG_B64, mimeType = "image/png")))),
        "slow" = {
          n <- if (is.null(a$seconds)) 1 else a$seconds
          steps <- max(1L, as.integer(ceiling(n / 0.25)))
          send(list(jsonrpc = "2.0", method = "notifications/message",
                    params = list(level = "info", logger = "slow", data = "starting")))
          for (i in seq_len(steps)) {
            Sys.sleep(n / steps)
            if (!is.null(token)) send(list(jsonrpc = "2.0", method = "notifications/progress",
                 params = list(progressToken = token, progress = i, total = steps,
                               message = sprintf("step %d/%d", i, steps))))
          }
          reply(id, list(content = list(list(type = "text", text = sprintf("slept %s", n)))))
        },
        "fail" = reply(id, list(isError = TRUE, content = list(list(type = "text", text = "boom")))),
        "big" = reply(id, list(content = list(list(type = "text",
                  text = paste(rep("x", if (is.null(a$n)) 50000L else a$n), collapse = ""))))),
        "roots" = {
          pending_roots <- id
          send(list(jsonrpc = "2.0", id = next_server_id, method = "roots/list"))
          next_server_id <- next_server_id + 1L
        },
        fail(id, -32602, paste0("Unknown tool: ", name))
      )
    },
    fail(id, -32601, paste0("Method not found: ", method))
  )
}
cat("fixture: stdin closed, exiting\n", file = stderr())
`````

### 5.3 stdio tests (`test_stdio.R`) and output

`````r
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "mcp_client.R"))
ok <- function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

t0 <- Sys.time()
tr <- mcp_transport_stdio(rscript, c("--vanilla", file.path(W, "fixture_mcp_stdio.R")),
                          env = list(FIXTURE_FLAG = "1"))
logs <- list(); notes <- character()
cl <- mcp_client(tr, roots = list(list(uri = paste0("file://", getwd()), name = basename(getwd()))),
                 request_timeout = 5,
                 on_log = function(p) logs[[length(logs) + 1L]] <<- p,
                 on_notification = function(method, params) notes <<- c(notes, method))
init <- cl$connect()
cat(sprintf("connect took %.2fs\n", as.numeric(Sys.time() - t0, units = "secs")))
ok("initialize negotiated 2025-11-25", identical(cl$protocol_version, "2025-11-25"))
ok("serverInfo name", identical(cl$server_info$name, "r-fixture"))
ok("instructions captured", grepl("Fixture", cl$instructions))

tools <- cl$list_tools()
ok("paginated tools/list returned all 8 tools", length(tools) == 8L)
cat("tools:", paste(vapply(tools, function(t) t$name, ""), collapse = ", "), "\n")

r <- cl$call_tool("echo", list(text = "héllo 你好 \U0001F600"))
ok("echo round-trips UTF-8", identical(r$content[[1]]$text, "héllo 你好 \U0001F600"))

r <- cl$call_tool("add", list(a = 2, b = 40.5))
ok("structuredContent", identical(r$structuredContent$sum, 42.5))

r <- cl$call_tool("tags.join", list(tags = I("solo")))
ok("length-1 array sent as JSON array (I())", identical(r$content[[1]]$text, "solo") && !isTRUE(r$isError))
r <- cl$call_tool("tags.join", list(tags = "solo"))
ok("WITHOUT I(): auto_unbox sends a scalar -> server rejects", isTRUE(r$isError))

r <- cl$call_tool("image")
llm <- mcp_to_llm_content(r)
ok("image content converted", llm[[2]]$type == "image" && llm[[2]]$mimeType == "image/png")

r <- cl$call_tool("fail")
ok("isError result is a result, not an R error", isTRUE(r$isError) && r$content[[1]]$text == "boom")

prog <- list()
t1 <- Sys.time()
r <- cl$call_tool("slow", list(seconds = 1), timeout = 0.6, on_progress = function(p) prog[[length(prog) + 1L]] <<- p)
ok("progress notifications reset the 0.6s timeout for a 1s call", r$content[[1]]$text == "slept 1" && length(prog) == 4L)
ok("notifications/message logged", length(logs) >= 1L && logs[[1]]$data == "starting")

e <- tryCatch(cl$call_tool("slow", list(seconds = 1.5), timeout = 0.4), error = function(e) e)
ok("timeout without progress -> mcp_timeout", inherits(e, "mcp_timeout"))
Sys.sleep(1.3)  # let the fixture finish the abandoned call
r <- cl$call_tool("echo", list(text = "after-timeout"))
ok("late response of the timed-out call is discarded; next call works", r$content[[1]]$text == "after-timeout")

r <- cl$call_tool("big", list(n = 300000L))
ok("300 KB single-line message (beyond pipe buffer)", nchar(r$content[[1]]$text) == 300000L)
lim <- mcp_limit_content(mcp_to_llm_content(r))
ok("model-facing text truncated in the middle to ~20KB + spill file",
   nchar(lim$content[[1]]$text) < 21500 && file.exists(lim$full_output_path) &&
   file.size(lim$full_output_path) == 300000)
cat(substr(lim$content[[1]]$text, 1, 90), "...\n")
cat(sub(".*(\u2026[0-9]+ chars truncated\u2026).*", "\\1", lim$content[[1]]$text), "\n")

r <- cl$call_tool("roots")
ok("server->client roots/list request answered", grepl("file://", r$content[[1]]$text))

e <- tryCatch(cl$call_tool("nope"), error = function(e) e)
ok("JSON-RPC error -> mcp_rpc_error with code", inherits(e, "mcp_rpc_error") && e$code == -32602)
e <- tryCatch(cl$request("no/such"), error = function(e) e)
ok("method not found -32601", inherits(e, "mcp_rpc_error") && e$code == -32601)

t2 <- Sys.time()
rs <- cl$call_many(list(list(name = "echo", arguments = list(text = "a")),
                        list(name = "add", arguments = list(a = 1, b = 2)),
                        list(name = "nope"),
                        list(name = "echo", arguments = list(text = "d"))))
ok("pipelined call_many keeps order and isolates errors",
   rs[[1]]$content[[1]]$text == "a" && rs[[2]]$structuredContent$sum == 3 &&
   inherits(rs[[3]], "mcp_rpc_error") && rs[[4]]$content[[1]]$text == "d")

big_in <- paste(rep("y", 400000), collapse = "")
r <- cl$call_tool("echo", list(text = big_in))
ok("400 KB request written in full (partial write loop)", nchar(r$content[[1]]$text) == 400000L)

pid <- tr$proc$get_pid()
t3 <- Sys.time(); cl$close()
ok("server exited after stdin close", !tr$proc$is_alive())
cat(sprintf("close took %.2fs; exit status %s\n", as.numeric(Sys.time() - t3, units = "secs"),
            format(tr$proc$get_exit_status())))
cat("stderr tail:", gsub("\n", " | ", tr$stderr_tail()), "\n")
e <- tryCatch(cl$call_tool("echo", list(text = "x")), error = function(e) e)
ok("call after close -> mcp_connection_closed", inherits(e, "mcp_connection_closed"))

# Failure to start: command not found / server that dies immediately
e <- tryCatch({ t <- mcp_transport_stdio("definitely-not-a-command-xyz"); c2 <- mcp_client(t); c2$connect() },
              error = function(e) e)
ok("missing command gives an R error", inherits(e, "error")); cat("  msg:", conditionMessage(e), "\n")
e <- tryCatch({ t <- mcp_transport_stdio(rscript, c("--vanilla", "-e", "message('bad config: missing API key'); quit(status = 3)"))
                c3 <- mcp_client(t, request_timeout = 5); c3$connect() }, error = function(e) e)
ok("server that exits at startup -> connection closed + stderr tail",
   inherits(e, "mcp_connection_closed") && grepl("missing API key", conditionMessage(e)))
cat("  msg:", gsub("\n", " | ", conditionMessage(e)), "\n")

ok("tool name mcp__srv__tags_join", mcp_tool_name("srv", "tags.join") == "mcp__srv__tags_join")
long <- mcp_tool_name("my-server", paste(rep("x", 80), collapse = ""))
ok("long tool name capped at 64 with hash suffix", nchar(long) == 64L && grepl("_[0-9a-f]{8}$", long))
cat("  ", long, "\n")
`````

Observed output (27 PASS, 0 FAIL):

`````text
connect took 0.30s
[PASS] initialize negotiated 2025-11-25
[PASS] serverInfo name
[PASS] instructions captured
[PASS] paginated tools/list returned all 8 tools
tools: echo, add, tags.join, image, slow, fail, big, roots 
[PASS] echo round-trips UTF-8
[PASS] structuredContent
[PASS] length-1 array sent as JSON array (I())
[PASS] WITHOUT I(): auto_unbox sends a scalar -> server rejects
[PASS] image content converted
[PASS] isError result is a result, not an R error
[PASS] progress notifications reset the 0.6s timeout for a 1s call
[PASS] notifications/message logged
[PASS] timeout without progress -> mcp_timeout
[PASS] late response of the timed-out call is discarded; next call works
[PASS] 300 KB single-line message (beyond pipe buffer)
[PASS] model-facing text truncated in the middle to ~20KB + spill file
Warning: truncated output (original token count: 75000)
Total output lines: 1

xxxxxxxxxxx ...
…279520 chars truncated… 
[PASS] server->client roots/list request answered
[PASS] JSON-RPC error -> mcp_rpc_error with code
[PASS] method not found -32601
[PASS] pipelined call_many keeps order and isolates errors
[PASS] 400 KB request written in full (partial write loop)
[PASS] server exited after stdin close
close took 0.04s; exit status 0
stderr tail: fixture: ready 
[PASS] call after close -> mcp_connection_closed
[PASS] missing command gives an R error
  msg: ! Native call to `processx_exec` failed
Caused by error in `chain_call(c_processx_exec, command, c(command, args), pty, pty_options, ...`:
! cannot start processx process 'definitely-not-a-command-xyz' (system error 2, No such file or directory) @unix/processx.c:613 (processx_exec) 
[PASS] server that exits at startup -> connection closed + stderr tail
  msg: MCP connection closed | bad config: missing API key 
[PASS] tool name mcp__srv__tags_join
[PASS] long tool name capped at 64 with hash suffix
   mcp__my-server__xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx_d365ded5 
`````

C-locale check with properly marked UTF-8 strings (`dbg3.R`, run with `LANG` unset). Before the fixture wrote with `useBytes = TRUE` the round trip returned `68 3c 63 33 3e ...` (the characters `<c3><a9>`); after the fix:

`````text
locale: C 
json bytes ok: TRUE  enc: UTF-8 
round trip identical bytes: TRUE  enc: UTF-8 
 [1] 68 c3 a9 20 e4 bd a0 20 f0 9f 98 80
`````

Interrupt test (`test_interrupt.R`): a helper process sends `SIGINT` to the R process while it waits for a 5 s tool call.

`````r
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "mcp_client.R"))
rscript <- file.path(R.home("bin"), "Rscript")
tr <- mcp_transport_stdio(rscript, c("--vanilla", file.path(W, "fixture_mcp_stdio.R")))
sent <- character(); orig <- tr$send
tr$send <- function(msg) { sent <<- c(sent, mcp_to_json(msg)); orig(msg) }
cl <- mcp_client(tr, request_timeout = 30); cl$connect()
killer <- processx::process$new("sh", c("-c", sprintf("sleep 0.7; kill -INT %d", Sys.getpid())))
t0 <- Sys.time()
res <- tryCatch(cl$call_tool("slow", list(seconds = 5)), interrupt = function(e) "INTERRUPTED")
cat("result:", format(res), sprintf(" after %.2fs\n", as.numeric(Sys.time() - t0, units = "secs")))
cat("last message sent by client:", tail(sent, 1), "\n")
# The connection is still usable afterwards (the late response of the cancelled call is dropped).
r <- cl$call_tool("echo", list(text = "still alive"), timeout = 20)
cat("after interrupt:", r$content[[1]]$text, "\n")
cl$close()
`````

`````text
result: INTERRUPTED  after 0.92s
last message sent by client: {"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":2,"reason":"Aborted"}} 
after interrupt: still alive 
`````

Interoperability with an independent server implementation (`test_interop.R`): handshake and `tools/list` only, no tool call, no model request.

`````r
# Interop check against independent MCP server implementations that are already installed on this machine.
# Handshake and tools/list only: no tool is called and no model request is made.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "mcp_client.R")); source(file.path(W, "tools_as_functions.R"))
try_server <- function(label, command, args) {
  path <- Sys.which(command)
  if (!nzchar(path)) { cat(label, ": not installed\n"); return(invisible()) }
  t0 <- Sys.time()
  res <- tryCatch({
    cl <- mcp_client(mcp_transport_stdio(path, args), request_timeout = 25)
    on.exit(try(cl$close(), silent = TRUE))
    cl$connect(); tools <- cl$list_tools()
    list(version = cl$protocol_version, server = cl$server_info, caps = names(cl$capabilities), tools = tools)
  }, error = function(e) e)
  if (inherits(res, "error")) { cat(label, ": FAILED -", substr(gsub("\n", " | ", conditionMessage(res)), 1, 300), "\n"); return(invisible()) }
  cat(sprintf("%s: OK in %.1fs  protocol=%s  server=%s %s  capabilities=[%s]  tools=%d\n", label, as.numeric(Sys.time() - t0, units = "secs"),
      res$version, res$server$name, res$server$version, paste(res$caps, collapse = ","), length(res$tools)))
  cat("  tool names:", paste(utils::head(vapply(res$tools, function(t) t$name, ""), 12), collapse = ", "), "\n")
  if (length(res$tools)) { t <- res$tools[[1]]; t$name <- mcp_tool_name(label, t$name)
    cat("  first declaration as R:\n"); cat(paste0("    ", strsplit(substr(render_tool_declaration(t), 1, 700), "\n")[[1]]), sep = "\n") }
}
try_server("claude", "claude", c("mcp", "serve"))
try_server("codex", "codex", c("mcp-server"))
`````

`````text
claude: OK in 1.5s  protocol=2025-11-25  server=claude/tengu 2.1.261  capabilities=[tools]  tools=29
  tool names: Agent, TaskOutput, Bash, Read, Edit, Write, NotebookEdit, WebFetch, ReportFindings, WebSearch, TaskStop, Skill 
  (first declaration rendered as an R signature; the tool's long description text is omitted here)
codex : FAILED - MCP connection closed | Error: stdin is not a terminal 
`````

The Codex line shows that `codex mcp-server` did not start as a stdio server from a non-terminal parent on this machine; I did not investigate further.

### 5.4 OAuth library (`mcp_oauth.R`)

`````r
# Prototype: MCP OAuth 2.1 client subset in R (discovery, DCR, PKCE S256, loopback callback, refresh,
# step-up detection). Dependencies: httr2, openssl, jsonlite, httpuv + later (callback server only).

oauth_b64url <- function(raw) gsub("=+$", "", chartr("+/", "-_", openssl::base64_encode(raw)))
oauth_pkce <- function(verifier = oauth_b64url(openssl::rand_bytes(32))) {
  list(verifier = verifier, challenge = oauth_b64url(openssl::sha256(charToRaw(verifier))))
}
oauth_state <- function() paste(as.character(openssl::rand_bytes(32)), collapse = "")

oauth_parse_www_authenticate <- function(header) {
  if (is.null(header) || !nzchar(header)) return(list())
  scheme <- tolower(strsplit(trimws(header), "\\s+")[[1]][1])
  if (!scheme %in% c("bearer", "dpop")) return(list())
  field <- function(name) {
    m <- regmatches(header, regexec(sprintf("(?:^|[,\\s])%s=(?:\"([^\"]*)\"|([^\\s,]+))", name), header,
                                    perl = TRUE, ignore.case = TRUE))[[1]]
    if (!length(m)) return(NULL)
    if (nzchar(m[2])) m[2] else if (nzchar(m[3])) m[3] else NULL
  }
  Filter(Negate(is.null), list(resource_metadata = field("resource_metadata"), scope = field("scope"),
                               error = field("error"), error_description = field("error_description")))
}

oauth_get_json <- function(url, protocol_version = "2025-11-25") {
  req <- httr2::request(url)
  req <- httr2::req_headers(req, Accept = "application/json", `MCP-Protocol-Version` = protocol_version)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  req <- httr2::req_timeout(req, 15)
  resp <- httr2::req_perform(req)
  list(status = httr2::resp_status(resp),
       body = if (httr2::resp_status(resp) < 300) tryCatch(httr2::resp_body_json(resp, check_type = FALSE),
                                                           error = function(e) NULL))
}
is_discovery_miss <- function(status) (status >= 400 && status < 500) || status == 502
origin_of <- function(u) { p <- httr2::url_parse(u); paste0(p$scheme, "://", p$hostname, if (!is.null(p$port)) paste0(":", p$port) else "") }
path_suffix <- function(u) { p <- httr2::url_parse(u)$path %||% ""; p <- sub("/$", "", p); p }
`%||%` <- function(a, b) if (is.null(a)) b else a

oauth_discover_resource <- function(server_url, resource_metadata_url = NULL) {
  if (!is.null(resource_metadata_url)) {
    r <- oauth_get_json(resource_metadata_url)
  } else {
    r <- oauth_get_json(paste0(origin_of(server_url), "/.well-known/oauth-protected-resource", path_suffix(server_url)))
    if (nzchar(path_suffix(server_url)) && is_discovery_miss(r$status))
      r <- oauth_get_json(paste0(origin_of(server_url), "/.well-known/oauth-protected-resource"))
  }
  if (r$status >= 300 || is.null(r$body$resource)) return(NULL)
  r$body
}
oauth_as_discovery_urls <- function(issuer) {
  o <- origin_of(issuer); p <- path_suffix(issuer)
  urls <- c(paste0(o, "/.well-known/oauth-authorization-server", p), paste0(o, "/.well-known/openid-configuration", p))
  if (nzchar(p)) urls <- c(urls, paste0(o, p, "/.well-known/openid-configuration"))
  urls
}
oauth_discover_as <- function(issuer) {
  for (u in oauth_as_discovery_urls(issuer)) {
    r <- oauth_get_json(u)
    if (r$status >= 300) { if (is_discovery_miss(r$status)) next; stop(sprintf("HTTP %d loading authorization server metadata from %s", r$status, u)) }
    m <- r$body
    trim <- function(x) sub("/$", "", x)
    if (!identical(trim(m$issuer), trim(issuer)))
      stop(sprintf("OAuth issuer mismatch: expected %s, received %s", issuer, m$issuer))
    return(m)
  }
  NULL
}
oauth_select_resource <- function(server_url, resource_meta) {
  if (is.null(resource_meta)) return(NULL)
  if (!identical(origin_of(server_url), origin_of(resource_meta$resource)))
    stop(sprintf("Protected resource %s does not match MCP server %s", resource_meta$resource, server_url))
  req_path <- paste0(sub("/$", "", httr2::url_parse(server_url)$path %||% ""), "/")
  cfg_path <- paste0(sub("/$", "", httr2::url_parse(resource_meta$resource)$path %||% ""), "/")
  if (!startsWith(req_path, cfg_path))
    stop(sprintf("Protected resource %s does not match MCP server %s", resource_meta$resource, server_url))
  resource_meta$resource
}
oauth_secure_endpoint <- function(url) {
  p <- httr2::url_parse(url)
  if (!identical(p$scheme, "https") && !p$hostname %in% c("localhost", "127.0.0.1", "::1", "[::1]"))
    stop("Refusing to send OAuth credentials to non-HTTPS endpoint ", url)
  url
}
oauth_token_request <- function(as_meta, client, params, resource = NULL) {
  url <- oauth_secure_endpoint(as_meta$token_endpoint)
  if (!is.null(resource)) params$resource <- resource
  req <- httr2::request(url)
  req <- httr2::req_headers(req, Accept = "application/json")
  supported <- unlist(as_meta$token_endpoint_auth_methods_supported)
  if (!is.null(client$client_secret) && (is.null(supported) || "client_secret_basic" %in% supported)) {
    req <- httr2::req_auth_basic(req, client$client_id, client$client_secret)
  } else {
    params$client_id <- client$client_id
    if (!is.null(client$client_secret)) params$client_secret <- client$client_secret
  }
  req <- do.call(httr2::req_body_form, c(list(req), params))
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  req <- httr2::req_timeout(req, 15)
  resp <- httr2::req_perform(req)
  body <- tryCatch(httr2::resp_body_json(resp, check_type = FALSE), error = function(e) NULL)
  if (is.character(body$error)) stop(structure(class = c("oauth_error", "error", "condition"),
      list(message = body$error_description %||% body$error, code = body$error, call = NULL)))
  if (httr2::resp_status(resp) >= 300) stop(structure(class = c("oauth_error", "error", "condition"),
      list(message = sprintf("HTTP %d from token endpoint", httr2::resp_status(resp)), code = "server_error", call = NULL)))
  if (!is.character(body$access_token) || !is.character(body$token_type)) stop("Invalid OAuth token response")
  body
}

# ---- credential store: one JSON file, keyed by server URL, mode 0600 --------
oauth_store <- function(path) {
  read <- function() if (file.exists(path)) jsonlite::fromJSON(path, simplifyVector = FALSE) else list()
  write <- function(x) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
    tmp <- paste0(path, ".tmp-", Sys.getpid())
    writeLines(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)),
               tmp, useBytes = TRUE)
    Sys.chmod(tmp, "0600"); file.rename(tmp, path)
  }
  list(path = path,
       load = function(server_url) read()[[server_url]],
       save = function(server_url, state) { x <- read(); x[[server_url]] <- state; write(x) },
       remove = function(server_url) { x <- read(); had <- !is.null(x[[server_url]]); x[[server_url]] <- NULL; write(x); had })
}

# ---- loopback callback server (httpuv binds 127.0.0.1 only) -----------------
oauth_callback_server <- function(port = NULL, path = "/callback") {
  port <- port %||% httpuv::randomPort(min = 49152L, max = 65535L, host = "127.0.0.1")
  got <- new.env(parent = emptyenv()); got$result <- NULL; got$expect_state <- NULL
  page <- function(status, text) list(status = status,
      headers = list("Content-Type" = "text/plain; charset=utf-8", "Cache-Control" = "no-store"), body = text)
  app <- list(call = function(req) {
    if (!identical(req$PATH_INFO, path)) return(page(404L, "Not found"))
    q <- httr2::url_parse(paste0("http://x/", req$QUERY_STRING))$query
    if (is.null(q$state) || !identical(q$state, got$expect_state)) return(page(400L, "Invalid or expired OAuth state"))
    if (!is.null(q$error)) { got$result <- list(error = q$error_description %||% q$error)
      return(page(200L, "Authorization failed. You may close this window.")) }
    if (is.null(q$code)) return(page(400L, "Missing authorization code"))
    got$result <- list(code = q$code, state = q$state)
    page(200L, "Authorization complete. You may close this window.")
  })
  srv <- httpuv::startServer("127.0.0.1", port, app)
  list(redirect_url = sprintf("http://127.0.0.1:%d%s", port, path), port = port,
       wait = function(state, timeout = 300) {
         got$expect_state <- state; deadline <- Sys.time() + timeout
         while (is.null(got$result)) {
           if (Sys.time() > deadline) stop("OAuth callback timed out")
           later::run_now(0.1)               # services httpuv; interruptible by the user
         }
         if (!is.null(got$result$error)) stop(got$result$error)
         got$result$code
       },
       close = function() httpuv::stopServer(srv))
}

# ---- sign in (browser flow) --------------------------------------------------
mcp_sign_in <- function(server_url, store, settings = list(), challenge = list(),
                        open_url = utils::browseURL, client_name = "gptr", timeout = 300) {
  res_meta <- oauth_discover_resource(server_url, challenge$resource_metadata)
  issuer <- res_meta$authorization_servers[[1]] %||% paste0(origin_of(server_url), "/")
  as_meta <- oauth_discover_as(issuer)
  if (is.null(as_meta)) stop("Could not discover the authorization server for ", server_url)
  if (!"code" %in% unlist(as_meta$response_types_supported)) stop("Authorization server does not support authorization codes")
  if (!"S256" %in% unlist(as_meta$code_challenge_methods_supported))
    stop("Authorization server does not advertise PKCE S256; refusing to proceed")   # MUST per MCP spec
  resource <- oauth_select_resource(server_url, res_meta)
  scopes <- unique(unlist(strsplit(paste(c(settings$scope, challenge$scope %||%
              paste(unlist(res_meta$scopes_supported), collapse = " ")), collapse = " "), "\\s+")))
  scope <- paste(scopes[nzchar(scopes)], collapse = " ")

  cb <- oauth_callback_server(settings$callback_port); on.exit(cb$close(), add = TRUE)
  stored <- store$load(server_url) %||% list()
  client <- if (!is.null(settings$client_id)) list(client_id = settings$client_id, client_secret = settings$client_secret)
            else stored$client
  if (is.null(client) || (is.null(settings$client_id) && !cb$redirect_url %in% unlist(client$redirect_uris))) {
    if (is.null(as_meta$registration_endpoint)) stop("Authorization server does not support dynamic client registration; configure oauth.clientId")
    req <- httr2::request(as_meta$registration_endpoint)
    req <- httr2::req_body_json(req, list(client_name = client_name, redirect_uris = list(cb$redirect_url),
        grant_types = list("authorization_code", "refresh_token"), response_types = list("code"),
        token_endpoint_auth_method = "none", scope = scope))
    req <- httr2::req_timeout(req, 15)
    client <- httr2::resp_body_json(httr2::req_perform(req), check_type = FALSE)
  }
  pk <- oauth_pkce(); state <- oauth_state()
  auth_url <- httr2::url_parse(as_meta$authorization_endpoint)
  auth_url$query <- c(auth_url$query, Filter(Negate(is.null), list(response_type = "code", client_id = client$client_id,
      code_challenge = pk$challenge, code_challenge_method = "S256", redirect_uri = cb$redirect_url,
      state = state, scope = if (nzchar(scope)) scope, resource = resource)))
  if ("offline_access" %in% scopes) auth_url$query$prompt <- "consent"
  url <- httr2::url_build(auth_url)
  open_url(url)
  code <- cb$wait(state, timeout)
  tokens <- oauth_token_request(as_meta, client, list(grant_type = "authorization_code", code = code,
      code_verifier = pk$verifier, redirect_uri = cb$redirect_url), resource)
  store$save(server_url, list(server_url = server_url, client = client, tokens = tokens,
      tokens_expire_at = if (!is.null(tokens$expires_in)) as.numeric(Sys.time()) + tokens$expires_in,
      discovery = list(issuer = issuer, as_meta = as_meta, resource = resource)))
  invisible(tokens)
}

# ---- auth provider used by the HTTP transport --------------------------------
mcp_auth_provider <- function(server_url, store, refresh_skew = 30) {
  need_sign_in <- function(message, challenge = list()) stop(structure(
    class = c("mcp_auth_required", "mcp_error", "error", "condition"),
    list(message = message, challenge = challenge, call = NULL)))
  refresh <- function(stale_token, challenge = list()) {
    st <- store$load(server_url)
    if (!identical(st$tokens$access_token, stale_token)) return(invisible())   # someone else refreshed already
    if (is.null(st$tokens$refresh_token)) need_sign_in("MCP server requires sign-in", challenge)
    tokens <- tryCatch(oauth_token_request(st$discovery$as_meta, st$client,
        list(grant_type = "refresh_token", refresh_token = st$tokens$refresh_token), st$discovery$resource),
      oauth_error = function(e) need_sign_in(paste0("MCP server requires sign-in (refresh failed: ", e$code, ")"), challenge))
    if (is.null(tokens$refresh_token)) tokens$refresh_token <- st$tokens$refresh_token
    st$tokens <- tokens
    st$tokens_expire_at <- if (!is.null(tokens$expires_in)) as.numeric(Sys.time()) + tokens$expires_in
    store$save(server_url, st)
    invisible()
  }
  list(
    token = function() {
      st <- store$load(server_url); tok <- st$tokens$access_token
      if (!is.null(st$tokens_expire_at) && st$tokens_expire_at - refresh_skew <= as.numeric(Sys.time()) &&
          !is.null(st$tokens$refresh_token)) { try(refresh(tok), silent = TRUE); tok <- store$load(server_url)$tokens$access_token }
      tok
    },
    on_unauthorized = function(resp, token) {
      ch <- oauth_parse_www_authenticate(httr2::resp_header(resp, "www-authenticate"))
      # A refresh keeps the granted scope, so a request for more scope needs the browser flow.
      if (identical(ch$error, "insufficient_scope")) need_sign_in("MCP server requires sign-in for more scope", ch)
      refresh(token, ch)
    })
}
`````

### 5.5 HTTP fixture with OAuth server (`fixture_mcp_http.R`), tests (`test_http.R`), streaming test

`````r
# Streamable-HTTP MCP fixture server (httpuv) with an optional OAuth 2.1 authorization server.
# Run: Rscript --vanilla fixture_mcp_http.R <port>      env FIXTURE_AUTH=1 enables OAuth
suppressWarnings(suppressMessages({ library(httpuv); library(jsonlite) }))
port <- as.integer(commandArgs(TRUE)[1])
base <- sprintf("http://127.0.0.1:%d", port)
require_auth <- identical(Sys.getenv("FIXTURE_AUTH"), "1")
logfile <- Sys.getenv("FIXTURE_LOG", "")
log_line <- function(...) if (nzchar(logfile)) cat(paste0(..., "\n"), file = logfile, append = TRUE)

obj <- function() structure(list(), names = character(0))
js <- function(x) enc2utf8(as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)))
json_resp <- function(x, status = 200L, headers = list()) {
  list(status = status, headers = c(list("Content-Type" = "application/json"), headers), body = js(x))
}
sse <- function(events, headers = list()) {
  body <- paste(vapply(events, function(e) {
    paste0(if (!is.null(e$retry)) paste0("retry: ", e$retry, "\n") else "",
           if (!is.null(e$id)) paste0("id: ", e$id, "\n") else "",
           if (!is.null(e$event)) paste0("event: ", e$event, "\n") else "",
           "data: ", if (is.null(e$data)) "" else e$data, "\n\n")
  }, ""), collapse = "")
  list(status = 200L, headers = c(list("Content-Type" = "text/event-stream", "Cache-Control" = "no-cache"), headers),
       body = body)
}
b64url <- function(raw) gsub("=+$", "", chartr("+/", "-_", base64_enc(raw)))

state <- new.env()
state$sessions <- character(); state$n <- 0L
state$resume <- list()          # last-event-id -> events still to deliver
state$valid_tokens <- character(); state$refresh <- list(); state$codes <- list(); state$tok_n <- 0L
state$token_scope <- list()

TOOLS <- list(
  list(name = "echo", description = "Echo text", inputSchema = list(type = "object",
       properties = list(text = list(type = "string")), required = list("text"))),
  list(name = "resumable", description = "Response stream is cut before the response; client must resume",
       inputSchema = list(type = "object", properties = obj())),
  list(name = "expire_session", description = "Server forgets the session", inputSchema = list(type = "object", properties = obj())),
  list(name = "expire_token", description = "Server invalidates the access token", inputSchema = list(type = "object", properties = obj())),
  list(name = "admin", description = "Needs scope mcp:admin", inputSchema = list(type = "object", properties = obj()))
)

parse_query <- function(q) {
  q <- sub("^\\?", "", q); if (!nzchar(q)) return(list())
  kv <- strsplit(strsplit(q, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
  out <- lapply(kv, function(p) utils::URLdecode(gsub("+", " ", if (length(p) > 1) p[2] else "", fixed = TRUE)))
  names(out) <- vapply(kv, function(p) utils::URLdecode(p[1]), ""); out
}
issue_tokens <- function(scope) {
  state$tok_n <- state$tok_n + 1L
  at <- paste0("tok-", state$tok_n); rt <- paste0("ref-", state$tok_n)
  state$valid_tokens <- c(state$valid_tokens, at); state$refresh[[rt]] <- scope; state$token_scope[[at]] <- scope
  list(access_token = at, token_type = "Bearer", expires_in = 3600, refresh_token = rt, scope = scope)
}
challenge <- function(extra = "") paste0(
  'Bearer resource_metadata="', base, '/.well-known/oauth-protected-resource/mcp", scope="mcp:tools"', extra)

mcp <- function(req) {
  method <- req$REQUEST_METHOD
  token <- NULL
  if (require_auth) {
    auth <- req$HTTP_AUTHORIZATION
    token <- if (!is.null(auth) && grepl("^Bearer ", auth)) sub("^Bearer ", "", auth) else NULL
    if (is.null(token) || !token %in% state$valid_tokens) {
      log_line("401 token=", if (is.null(token)) "none" else token)
      return(list(status = 401L, headers = list("WWW-Authenticate" = challenge(), "Content-Type" = "text/plain"),
                  body = "unauthorized"))
    }
  }
  sid <- req$HTTP_MCP_SESSION_ID
  if (method == "DELETE") {
    log_line("DELETE session=", sid); state$sessions <- setdiff(state$sessions, sid)
    return(list(status = 200L, headers = list("Content-Type" = "text/plain"), body = ""))
  }
  if (method == "GET") {
    last <- req$HTTP_LAST_EVENT_ID
    log_line("GET last-event-id=", if (is.null(last)) "none" else last)
    if (is.null(last) || is.null(state$resume[[last]]))
      return(list(status = 405L, headers = list("Content-Type" = "text/plain", Allow = "POST, DELETE"), body = ""))
    ev <- state$resume[[last]]; state$resume[[last]] <- NULL
    return(sse(ev))
  }
  if (method != "POST") return(list(status = 405L, headers = list("Content-Type" = "text/plain"), body = ""))
  accept <- req$HTTP_ACCEPT
  if (is.null(accept) || !grepl("application/json", accept) || !grepl("text/event-stream", accept))
    return(list(status = 406L, headers = list("Content-Type" = "text/plain"), body = "Accept must list both types"))
  msg <- fromJSON(rawToChar(req$rook.input$read()), simplifyVector = FALSE)
  log_line("POST ", if (is.null(msg$method)) "response" else msg$method, " session=", if (is.null(sid)) "none" else sid,
           " version=", if (is.null(req$HTTP_MCP_PROTOCOL_VERSION)) "none" else req$HTTP_MCP_PROTOCOL_VERSION)
  if (identical(msg$method, "initialize")) {
    state$n <- state$n + 1L; new_sid <- sprintf("sess-%d", state$n); state$sessions <- c(state$sessions, new_sid)
    return(json_resp(list(jsonrpc = "2.0", id = msg$id, result = list(
      protocolVersion = "2025-11-25", capabilities = list(tools = obj()),
      serverInfo = list(name = "r-http-fixture", version = "0.0.1"))), headers = list("Mcp-Session-Id" = new_sid)))
  }
  if (is.null(sid)) return(json_resp(list(jsonrpc = "2.0", error = list(code = -32600, message = "Missing session")), 400L))
  if (!sid %in% state$sessions) return(json_resp(list(jsonrpc = "2.0", error = list(code = -32001, message = "Session not found")), 404L))
  if (is.null(msg$id) || is.null(msg$method)) return(list(status = 202L, headers = list("Content-Type" = "text/plain"), body = ""))
  ok <- function(result) list(jsonrpc = "2.0", id = msg$id, result = result)
  text <- function(s) list(content = list(list(type = "text", text = s)))
  switch(msg$method,
    "ping" = json_resp(ok(obj())),
    "tools/list" = json_resp(ok(list(tools = TOOLS))),
    "tools/call" = switch(msg$params$name,
      # SSE answer with a priming event (id + empty data) followed by the response
      "echo" = sse(list(list(id = paste0("e", msg$id, "-0")),
                        list(id = paste0("e", msg$id, "-1"), event = "message",
                             data = js(ok(text(msg$params$arguments$text)))))),
      "resumable" = {
        cut <- paste0("r", msg$id, "-1")
        state$resume[[cut]] <- list(list(id = paste0("r", msg$id, "-2"), event = "message",
                                         data = js(ok(text("resumed ok")))))
        sse(list(list(id = paste0("r", msg$id, "-0"), retry = 50),
                 list(id = cut, event = "message", data = js(list(jsonrpc = "2.0",
                      method = "notifications/message", params = list(level = "info", data = "half way"))))))
      },
      "expire_session" = { state$sessions <- setdiff(state$sessions, sid); json_resp(ok(text("session dropped"))) },
      "expire_token" = { state$valid_tokens <- setdiff(state$valid_tokens, token); json_resp(ok(text("token dropped"))) },
      "admin" = {
        if (require_auth && !grepl("mcp:admin", state$token_scope[[token]]))
          list(status = 403L, headers = list("Content-Type" = "text/plain", "WWW-Authenticate" =
            paste0('Bearer error="insufficient_scope", scope="mcp:tools mcp:admin", resource_metadata="', base,
                   '/.well-known/oauth-protected-resource/mcp"')), body = "forbidden")
        else json_resp(ok(text("admin ok")))
      },
      json_resp(list(jsonrpc = "2.0", id = msg$id, error = list(code = -32602, message = "Unknown tool")))),
    json_resp(list(jsonrpc = "2.0", id = msg$id, error = list(code = -32601, message = "Method not found"))))
}

app <- list(call = function(req) {
  path <- req$PATH_INFO
  tryCatch({
    if (path == "/mcp") return(mcp(req))
    if (path == "/.well-known/oauth-protected-resource/mcp")
      return(json_resp(list(resource = paste0(base, "/mcp"), authorization_servers = list(base),
                            scopes_supported = list("mcp:tools"))))
    if (path == "/.well-known/oauth-authorization-server")
      return(json_resp(list(issuer = base, authorization_endpoint = paste0(base, "/authorize"),
        token_endpoint = paste0(base, "/token"), registration_endpoint = paste0(base, "/register"),
        response_types_supported = list("code"), grant_types_supported = list("authorization_code", "refresh_token"),
        code_challenge_methods_supported = list("S256"), token_endpoint_auth_methods_supported = list("none"))))
    if (path == "/register") {
      meta <- fromJSON(rawToChar(req$rook.input$read()), simplifyVector = FALSE)
      log_line("REGISTER ", js(meta))
      return(json_resp(c(list(client_id = "client-123", client_id_issued_at = 1), meta), 201L))
    }
    if (path == "/authorize") {
      q <- parse_query(req$QUERY_STRING); log_line("AUTHORIZE ", js(q))
      bad <- NULL
      if (!identical(q$response_type, "code")) bad <- "response_type"
      if (!identical(q$code_challenge_method, "S256") || is.null(q$code_challenge)) bad <- "pkce"
      if (!identical(q$client_id, "client-123")) bad <- "client_id"
      if (!identical(q$resource, paste0(base, "/mcp"))) bad <- "resource"
      if (!is.null(bad)) return(list(status = 400L, headers = list("Content-Type" = "text/plain"), body = paste("bad", bad)))
      code <- paste0("code-", length(state$codes) + 1L)
      state$codes[[code]] <- q
      loc <- paste0(q$redirect_uri, "?code=", code, "&state=", utils::URLencode(q$state, reserved = TRUE))
      return(list(status = 302L, headers = list(Location = loc, "Content-Type" = "text/plain"), body = ""))
    }
    if (path == "/token") {
      f <- parse_query(rawToChar(req$rook.input$read())); log_line("TOKEN ", js(f[setdiff(names(f), c("code_verifier"))]))
      err <- function(code) json_resp(list(error = code, error_description = code), 400L)
      if (identical(f$grant_type, "authorization_code")) {
        q <- state$codes[[f$code]]; if (is.null(q)) return(err("invalid_grant"))
        state$codes[[f$code]] <- NULL
        if (!identical(b64url(openssl::sha256(charToRaw(f$code_verifier))), q$code_challenge)) return(err("invalid_grant"))
        if (!identical(f$redirect_uri, q$redirect_uri) || !identical(f$resource, q$resource)) return(err("invalid_request"))
        return(json_resp(issue_tokens(q$scope)))
      }
      if (identical(f$grant_type, "refresh_token")) {
        scope <- state$refresh[[f$refresh_token]]; if (is.null(scope)) return(err("invalid_grant"))
        state$refresh[[f$refresh_token]] <- NULL                 # rotation
        return(json_resp(issue_tokens(scope)))
      }
      return(err("unsupported_grant_type"))
    }
    list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "not found")
  }, error = function(e) list(status = 500L, headers = list("Content-Type" = "text/plain"), body = conditionMessage(e)))
})
cat("http fixture listening on", base, "\n")
runServer("127.0.0.1", port, app)
`````

`````r
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "mcp_client.R")); source(file.path(W, "mcp_oauth.R"))
ok <- function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
rscript <- file.path(R.home("bin"), "Rscript")
start_fixture <- function(auth = FALSE) {
  port <- httpuv::randomPort(host = "127.0.0.1")
  logf <- tempfile("fixture-log-")
  p <- processx::process$new(rscript, c("--vanilla", file.path(W, "fixture_mcp_http.R"), port),
        env = c("current", FIXTURE_AUTH = if (auth) "1" else "0", FIXTURE_LOG = logf), stdout = "|", stderr = "|")
  for (i in 1:100) {   # wait until it accepts connections
    up <- tryCatch({ curl::curl_fetch_memory(sprintf("http://127.0.0.1:%d/nothing", port)); TRUE }, error = function(e) FALSE)
    if (up) break; Sys.sleep(0.1)
  }
  list(proc = p, port = port, url = sprintf("http://127.0.0.1:%d/mcp", port), log = function() readLines(logf, warn = FALSE))
}

cat("==== Streamable HTTP without auth ====\n")
fx <- start_fixture()
tr <- mcp_transport_http(fx$url, headers = list(`X-Custom` = "1"))
notes <- list()
cl <- mcp_client(tr, request_timeout = 5, on_log = function(p) notes[[length(notes) + 1L]] <<- p)
cl$connect()
ok("session id captured from initialize response", identical(tr$session_id, "sess-1"))
tools <- cl$list_tools(); ok("tools/list over JSON response", length(tools) == 5L)
r <- cl$call_tool("echo", list(text = "via sse"))
ok("tools/call answered on an SSE stream with a priming event", identical(r$content[[1]]$text, "via sse"))
r <- cl$call_tool("resumable")
ok("dropped response stream resumed with GET + Last-Event-ID", identical(r$content[[1]]$text, "resumed ok"))
ok("notification delivered before the cut was dispatched", length(notes) == 1L && notes[[1]]$data == "half way")
cat("  transport log:", tr$log, "\n")
lg <- fx$log()
ok("server saw MCP-Protocol-Version + Mcp-Session-Id on later requests",
   any(grepl("POST tools/list session=sess-1 version=2025-11-25", lg, fixed = TRUE)))
ok("initialize was sent without a session/version header", any(grepl("POST initialize session=none version=none", lg, fixed = TRUE)))
ok("server saw the resumption GET", any(grepl("GET last-event-id=r4-1", lg, fixed = TRUE)))
invisible(cl$call_tool("expire_session"))
e <- tryCatch(cl$call_tool("echo", list(text = "x")), error = function(e) e)
ok("404 with a session id -> mcp_session_expired", inherits(e, "mcp_session_expired"))
cl$close()
Sys.sleep(0.2)
ok("close() sent DELETE with the session id", any(grepl("DELETE session=sess-1", fx$log(), fixed = TRUE)))
invisible(fx$proc$kill())

cat("==== Streamable HTTP with OAuth ====\n")
ok("PKCE matches RFC 7636 appendix B vector",
   identical(oauth_pkce("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")$challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"))
ch <- oauth_parse_www_authenticate('Bearer error="insufficient_scope", scope="files:read files:write", resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource", error_description="Additional file write permission required"')
ok("WWW-Authenticate parsed", identical(ch$scope, "files:read files:write") && identical(ch$error, "insufficient_scope") &&
   identical(ch$resource_metadata, "https://mcp.example.com/.well-known/oauth-protected-resource"))
ok("AS discovery URL order (issuer with path)", identical(oauth_as_discovery_urls("https://auth.example.com/tenant1"),
   c("https://auth.example.com/.well-known/oauth-authorization-server/tenant1",
     "https://auth.example.com/.well-known/openid-configuration/tenant1",
     "https://auth.example.com/tenant1/.well-known/openid-configuration")))

fx <- start_fixture(auth = TRUE)
store <- oauth_store(file.path(tempfile("gptr-auth-"), "mcp-auth.json"))
auth <- mcp_auth_provider(fx$url, store)
tr <- mcp_transport_http(fx$url, auth = auth); cl <- mcp_client(tr, request_timeout = 5)
e <- tryCatch(cl$connect(), error = function(e) e)
ok("unauthenticated connect -> mcp_auth_required (no browser opened by the connection)", inherits(e, "mcp_auth_required"))
challenge <- e$challenge
cat("  challenge:", jsonlite::toJSON(challenge, auto_unbox = TRUE), "\n")

# "Browser": a separate process that follows the redirect chain to our loopback callback.
fake_browser <- function(url) {
  cat("  authorization URL:", sub("code_challenge=[^&]+", "code_challenge=...", sub("state=[^&]+", "state=...", url)), "\n")
  processx::process$new(rscript, c("--vanilla", "-e", sprintf(
    "Sys.sleep(0.3); r <- curl::curl_fetch_memory(%s); cat(r$status_code, rawToChar(r$content))", deparse(url))),
    stdout = "|", stderr = "|", cleanup = FALSE)
}
t0 <- Sys.time()
tokens <- mcp_sign_in(fx$url, store, challenge = challenge, open_url = fake_browser, timeout = 20)
cat(sprintf("  sign-in took %.2fs\n", as.numeric(Sys.time() - t0, units = "secs")))
ok("sign-in stored tokens (file mode 600)", identical(store$load(fx$url)$tokens$access_token, "tok-1") &&
   identical(format(file.info(store$path)$mode), "600"))
tr <- mcp_transport_http(fx$url, auth = auth); cl <- mcp_client(tr, request_timeout = 5); cl$connect()
r <- cl$call_tool("echo", list(text = "authed")); ok("authenticated call", identical(r$content[[1]]$text, "authed"))
invisible(cl$call_tool("expire_token"))
r <- cl$call_tool("echo", list(text = "after refresh"))
ok("401 -> refresh with rotating refresh token -> request retried once",
   identical(r$content[[1]]$text, "after refresh") && identical(store$load(fx$url)$tokens$access_token, "tok-2") &&
   identical(store$load(fx$url)$tokens$refresh_token, "ref-2"))
e <- tryCatch(cl$call_tool("admin"), error = function(e) e)
ok("403 insufficient_scope -> mcp_auth_required carrying the challenge scope",
   inherits(e, "mcp_auth_required") && identical(e$challenge$scope, "mcp:tools mcp:admin"))
tokens <- mcp_sign_in(fx$url, store, challenge = e$challenge, open_url = fake_browser, timeout = 20)
tr <- mcp_transport_http(fx$url, auth = auth); cl <- mcp_client(tr, request_timeout = 5); cl$connect()
r <- cl$call_tool("admin"); ok("step-up sign-in grants the extra scope", identical(r$content[[1]]$text, "admin ok"))
cl$close()
cat("  fixture log (auth-related):\n"); cat(paste0("    ", grep("REGISTER|AUTHORIZE|TOKEN|401", fx$log(), value = TRUE)), sep = "\n")
fx$proc$kill()
`````

Observed output (19 PASS, 0 FAIL). The "browser" is a separate R process that follows the redirect from `/authorize` to the loopback callback.

`````text
==== Streamable HTTP without auth ====
[PASS] session id captured from initialize response
[PASS] tools/list over JSON response
[PASS] tools/call answered on an SSE stream with a priming event
[PASS] dropped response stream resumed with GET + Last-Event-ID
[PASS] notification delivered before the cut was dispatched
  transport log: resumed with Last-Event-ID=r4-1 
[PASS] server saw MCP-Protocol-Version + Mcp-Session-Id on later requests
[PASS] initialize was sent without a session/version header
[PASS] server saw the resumption GET
[PASS] 404 with a session id -> mcp_session_expired
[PASS] close() sent DELETE with the session id
==== Streamable HTTP with OAuth ====
[PASS] PKCE matches RFC 7636 appendix B vector
[PASS] WWW-Authenticate parsed
[PASS] AS discovery URL order (issuer with path)
[PASS] unauthenticated connect -> mcp_auth_required (no browser opened by the connection)
  challenge: {"resource_metadata":"http://127.0.0.1:48531/.well-known/oauth-protected-resource/mcp","scope":"mcp:tools"} 
  authorization URL: http://127.0.0.1:48531/authorize?response_type=code&client_id=client-123&code_challenge=...&code_challenge_method=S256&redirect_uri=http%3A%2F%2F127.0.0.1%3A64832%2Fcallback&state=...&scope=mcp%3Atools&resource=http%3A%2F%2F127.0.0.1%3A48531%2Fmcp 
  sign-in took 0.54s
[PASS] sign-in stored tokens (file mode 600)
[PASS] authenticated call
[PASS] 401 -> refresh with rotating refresh token -> request retried once
[PASS] 403 insufficient_scope -> mcp_auth_required carrying the challenge scope
  authorization URL: http://127.0.0.1:48531/authorize?response_type=code&client_id=client-123&code_challenge=...&code_challenge_method=S256&redirect_uri=http%3A%2F%2F127.0.0.1%3A51458%2Fcallback&state=...&scope=mcp%3Atools%20mcp%3Aadmin&resource=http%3A%2F%2F127.0.0.1%3A48531%2Fmcp 
[PASS] step-up sign-in grants the extra scope
  fixture log (auth-related):
    401 token=none
    REGISTER {"client_name":"gptr","redirect_uris":["http://127.0.0.1:64832/callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none","scope":"mcp:tools"}
    AUTHORIZE {"response_type":"code","client_id":"client-123","code_challenge":"xBDUmnuMiVsmGnXfOTnJ2ZxqQZgHcoSzJ7OVhho5UWI","code_challenge_method":"S256","redirect_uri":"http://127.0.0.1:64832/callback","state":"f1289f1f5ff1a3ecd28cb0920e1330d3f09518318720d10986acf6c9fee26557","scope":"mcp:tools","resource":"http://127.0.0.1:48531/mcp"}
    TOKEN {"grant_type":"authorization_code","code":"code-1","redirect_uri":"http://127.0.0.1:64832/callback","resource":"http://127.0.0.1:48531/mcp","client_id":"client-123"}
    401 token=tok-1
    TOKEN {"grant_type":"refresh_token","refresh_token":"ref-1","resource":"http://127.0.0.1:48531/mcp","client_id":"client-123"}
    REGISTER {"client_name":"gptr","redirect_uris":["http://127.0.0.1:51458/callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none","scope":"mcp:tools mcp:admin"}
    AUTHORIZE {"response_type":"code","client_id":"client-123","code_challenge":"Kac3IGLA1pgId7tYdOc4R5uQxJdEiuiCxtMLcWoSwn0","code_challenge_method":"S256","redirect_uri":"http://127.0.0.1:51458/callback","state":"7cbc90fcdcf973ce0cc89af5f3c04e7dd5be6980bb14cfa684b29a2ded6193f7","scope":"mcp:tools mcp:admin","resource":"http://127.0.0.1:48531/mcp"}
    TOKEN {"grant_type":"authorization_code","code":"code-1","redirect_uri":"http://127.0.0.1:51458/callback","resource":"http://127.0.0.1:48531/mcp","client_id":"client-123"}
[1] TRUE
`````

Observation: the second sign-in registered a new client because the callback port changed. The final design must store and reuse the port (section 4.3.3).

Incremental streaming (`fixture_stream_socket.R`, `test_stream.R`): a base-R socket server writes SSE events 0.4 s apart.

`````r
# Base-R socket HTTP server that streams SSE events over time (one connection at a time).
suppressWarnings(suppressMessages(library(jsonlite)))
port <- as.integer(commandArgs(TRUE)[1])
srv <- serverSocket(port)
js <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null"))
w <- function(con, s) { writeBin(charToRaw(enc2utf8(s)), con); flush(con) }
repeat {
  con <- tryCatch(socketAccept(srv, blocking = TRUE, open = "a+b", timeout = 60), error = function(e) NULL)
  if (is.null(con)) next
  tryCatch({
    first <- readLines(con, n = 1L, warn = FALSE); hdr <- character()
    repeat { l <- readLines(con, n = 1L, warn = FALSE); if (!length(l) || !nzchar(l)) break; hdr <- c(hdr, l) }
    len <- as.integer(sub("^[^:]+:\\s*", "", grep("^content-length:", hdr, ignore.case = TRUE, value = TRUE)))
    body <- if (length(len) && len > 0) rawToChar(readBin(con, "raw", n = len)) else ""
    method <- strsplit(first, " ")[[1]][1]
    if (method != "POST") { w(con, "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    } else {
      msg <- fromJSON(body, simplifyVector = FALSE)
      plain <- function(x) { b <- js(x); w(con, sprintf("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", nchar(b, "bytes"), b)) }
      if (is.null(msg$id)) w(con, "HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      else if (msg$method == "initialize") plain(list(jsonrpc = "2.0", id = msg$id, result = list(protocolVersion = "2025-11-25",
            capabilities = list(tools = structure(list(), names = character(0))), serverInfo = list(name = "socket-fixture", version = "0"))))
      else {
        n <- msg$params$arguments$steps; delay <- msg$params$arguments$delay
        w(con, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")
        w(con, ": keep-alive comment\n\n")
        for (i in seq_len(n)) {
          Sys.sleep(delay)
          w(con, paste0("event: message\ndata: ", js(list(jsonrpc = "2.0", method = "notifications/progress",
              params = list(progressToken = msg$params$`_meta`$progressToken, progress = i, total = n))), "\n\n"))
        }
        Sys.sleep(delay)
        # response split over two writes and two data: lines is still one event
        w(con, "event: message\ndata: {\"jsonrpc\":\"2.0\",\n")
        Sys.sleep(0.05)
        w(con, paste0("data: \"id\":", msg$id, ",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"streamed\"}]}}\n\n"))
      }
    }
  }, error = function(e) message("fixture error: ", conditionMessage(e)), finally = close(con))
}
`````

`````r
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "mcp_client.R"))
ok <- function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
port <- httpuv::randomPort(host = "127.0.0.1")
p <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", file.path(W, "fixture_stream_socket.R"), port), stderr = "|")
Sys.sleep(1)
cat("listening sockets for the base-R serverSocket():\n"); system(sprintf("lsof -nP -iTCP:%d -sTCP:LISTEN | awk '{print $1, $8, $9, $10}'", port))
tr <- mcp_transport_http(sprintf("http://127.0.0.1:%d/mcp", port)); cl <- mcp_client(tr, request_timeout = 1)
cl$connect()
stamps <- numeric(); t0 <- Sys.time()
r <- cl$call_tool("x", list(steps = 5L, delay = 0.4), timeout = 1,
                  on_progress = function(pr) stamps <<- c(stamps, round(as.numeric(Sys.time() - t0, units = "secs"), 2)))
total <- as.numeric(Sys.time() - t0, units = "secs")
ok("2.4s streamed call succeeds under a 1s idle timeout because progress resets it", identical(r$content[[1]]$text, "streamed"))
ok("progress events were delivered incrementally, not at the end", length(stamps) == 5L && all(diff(stamps) > 0.2))
cat("  progress arrival times (s):", stamps, " total:", round(total, 2), "\n")
e <- tryCatch(cl$call_tool("x", list(steps = 1L, delay = 1.5), timeout = 1), error = function(e) e)
ok("silent stream -> mcp_timeout", inherits(e, "mcp_timeout"))
invisible(p$kill())
`````

`````text
listening sockets for the base-R serverSocket():
COMMAND NODE NAME 
R TCP *:14202 (LISTEN)
[PASS] 2.4s streamed call succeeds under a 1s idle timeout because progress resets it
[PASS] progress events were delivered incrementally, not at the end
  progress arrival times (s): 0.43 0.83 1.23 1.64 2.04  total: 2.49 
[PASS] silent stream -> mcp_timeout
`````

The `lsof` line shows that base R's `serverSocket()` listens on `*:<port>`, that is on all interfaces.

### 5.6 Tools as R functions (`tools_as_functions.R`, `test_tools_fn.R`)

`````r
# Prototype: tools-as-R-functions (the R analogue of Pi's codemode)
#  - every registered tool (built-in, extension, MCP, sub-agent) becomes an ordinary R function whose
#    formals come from the tool's JSON Schema
#  - arguments are coerced to JSON by schema (arrays stay arrays), results come back as R values
#  - nested calls run through one `runner`, i.e. the harness tool pipeline (hooks, permissions, records)
#  - declarations for the model are rendered as R signatures with roxygen-style comments
`%||%` <- function(a, b) if (is.null(a)) b else a

R_RESERVED <- c("if", "else", "repeat", "while", "function", "for", "next", "break", "TRUE", "FALSE", "NULL",
                "Inf", "NaN", "NA", "NA_integer_", "NA_real_", "NA_complex_", "NA_character_", "in")
# Identifier the model uses: [A-Za-z0-9._] only, must start with a letter, never a reserved word.
tool_identifier <- function(name) {
  id <- gsub("[^A-Za-z0-9_.]", "_", name)
  if (!grepl("^[A-Za-z]", id)) id <- paste0("t_", sub("^[_.]+", "", id))
  if (id %in% R_RESERVED) id <- paste0(id, "_")
  id
}
arg_name <- function(n) if (make.names(n) == n && !n %in% R_RESERVED) n else paste0("`", n, "`")

# ---- JSON Schema -> compact R type string (for declarations only) -------------
schema_resolve <- function(schema, root, seen = character()) {
  ref <- schema[["$ref"]]
  if (!is.character(ref)) return(schema)
  if (ref %in% seen || !startsWith(ref, "#/")) return(NULL)
  cur <- root
  for (seg in strsplit(substring(ref, 3L), "/", fixed = TRUE)[[1]]) {
    seg <- gsub("~0", "~", gsub("~1", "/", utils::URLdecode(seg), fixed = TRUE), fixed = TRUE)
    if (!is.list(cur) || is.null(cur[[seg]])) return(NULL)
    cur <- cur[[seg]]
  }
  schema_resolve(cur, root, c(seen, ref))
}
schema_to_rtype <- function(schema, root = schema, depth = 0L) {
  if (isTRUE(schema)) return("any"); if (isFALSE(schema)) return("never")
  if (!is.list(schema)) return("any")
  schema <- schema_resolve(schema, root); if (is.null(schema)) return("any")
  if (!is.null(schema$const)) return(deparse(schema$const))
  if (!is.null(schema$enum)) return(paste0("one of ", paste(vapply(schema$enum, function(v)
    if (is.character(v)) dQuote(v, FALSE) else format(v), ""), collapse = " | ")))
  variants <- schema$anyOf %||% schema$oneOf
  if (!is.null(variants)) return(paste(unique(vapply(variants, schema_to_rtype, "", root = root, depth = depth)), collapse = " | "))
  type <- schema$type
  if (length(type) > 1) return(paste(unique(vapply(type, function(t) schema_to_rtype(c(list(type = t),
      schema[setdiff(names(schema), "type")]), root, depth), "")), collapse = " | "))
  if (is.null(type)) type <- if (!is.null(schema$properties)) "object" else if (!is.null(schema$items)) "array" else "any"
  switch(type,
    string = "string", number = "number", integer = "integer", boolean = "logical", null = "NULL",
    array = paste0("vector<", if (is.null(schema$items)) "any" else schema_to_rtype(schema$items, root, depth + 1L), ">"),
    object = {
      props <- schema$properties
      if (!length(props) || depth >= 3L) "list" else {
        req <- unlist(schema$required)
        paste0("list(", paste(vapply(names(props), function(n) paste0(arg_name(n), if (n %in% req) "" else "?", ": ",
                 schema_to_rtype(props[[n]], root, depth + 1L)), ""), collapse = ", "), ")")
      }
    },
    "any")
}

# ---- declaration shown to the model ---------------------------------------------
render_tool_signature <- function(tool, prefix = "tools$") {
  props <- tool$inputSchema$properties %||% list(); req <- unlist(tool$inputSchema$required)
  ord <- c(intersect(names(props), req), setdiff(names(props), req))
  args <- vapply(ord, function(n) if (n %in% req) arg_name(n) else paste0(arg_name(n), " = NULL"), "")
  paste0(prefix, tool_identifier(tool$name), "(", paste(args, collapse = ", "), ")")
}
render_tool_declaration <- function(tool, prefix = "tools$", max_chars = 16000L) {
  props <- tool$inputSchema$properties %||% list(); req <- unlist(tool$inputSchema$required)
  ord <- c(intersect(names(props), req), setdiff(names(props), req))
  desc <- strsplit(trimws(tool$description %||% ""), "\r?\n")[[1]]
  lines <- paste0("#' ", desc)
  for (n in ord) {
    p <- props[[n]]
    d <- gsub("\\s*\r?\n\\s*", " ", trimws(p$description %||% ""))
    dflt <- if (!is.null(p$default)) paste0(" (default ", as.character(jsonlite::toJSON(p$default, auto_unbox = TRUE)), ")") else ""
    lines <- c(lines, paste0("#' @param ", n, " ", schema_to_rtype(p, tool$inputSchema),
                             if (!n %in% req) ", optional" else "", dflt, if (nzchar(d)) paste0(". ", d) else ""))
  }
  ret <- if (!is.null(tool$outputSchema)) schema_to_rtype(tool$outputSchema) else "string (the tool's text output)"
  lines <- c(lines, paste0("#' @return ", ret))
  out <- paste(c(lines, render_tool_signature(tool, prefix)), collapse = "\n")
  if (nchar(out) > max_chars) paste(c(paste0("#' ", desc[1]), render_tool_signature(tool, prefix)), collapse = "\n") else out
}

# ---- R value -> JSON-ready value, directed by the schema -------------------------
coerce_to_schema <- function(x, schema, root = schema, path = "args") {
  if (is.null(schema) || !is.list(schema)) return(x)
  schema <- schema_resolve(schema, root) %||% list()
  variants <- schema$anyOf %||% schema$oneOf
  if (!is.null(variants)) {
    for (v in variants) { r <- tryCatch(coerce_to_schema(x, v, root, path), error = function(e) NULL); if (!is.null(r)) return(r) }
    return(x)
  }
  type <- schema$type
  if (length(type) > 1) type <- setdiff(unlist(type), "null")[1]
  if (is.null(type)) type <- if (!is.null(schema$properties)) "object" else if (!is.null(schema$items)) "array" else "any"
  if (is.null(x)) return(NULL)
  if (is.factor(x)) x <- as.character(x)
  scalar <- function(conv, what) {
    if (length(x) != 1L) stop(sprintf("%s must be a single %s, not a vector of length %d", path, what, length(x)), call. = FALSE)
    if (is.list(x)) x <- x[[1]]
    if (is.na(x)) return(NULL)
    jsonlite::unbox(conv(x))
  }
  switch(type,
    string = scalar(as.character, "string"),
    number = scalar(as.numeric, "number"),
    integer = scalar(function(v) { if (v != round(v)) stop(sprintf("%s must be a whole number", path), call. = FALSE); as.integer(v) }, "integer"),
    boolean = scalar(as.logical, "logical"),
    array = {
      if (is.data.frame(x)) x <- lapply(seq_len(nrow(x)), function(i) as.list(x[i, , drop = FALSE]))
      items <- schema$items
      lapply(seq_along(x), function(i) coerce_to_schema(x[[i]], items, root, sprintf("%s[[%d]]", path, i)))
    },
    object = {
      if (!is.list(x)) x <- as.list(x)
      if (length(x) && (is.null(names(x)) || any(!nzchar(names(x))))) stop(sprintf("%s must be a named list", path), call. = FALSE)
      props <- schema$properties %||% list()
      out <- lapply(names(x), function(n) coerce_to_schema(x[[n]], props[[n]], root, paste0(path, "$", n)))
      names(out) <- names(x)
      out <- Filter(Negate(is.null), out)
      miss <- setdiff(unlist(schema$required), names(out))
      if (length(miss)) stop(sprintf("%s is missing required %s", path, paste(sQuote(miss, FALSE), collapse = ", ")), call. = FALSE)
      if (!length(out)) structure(list(), names = character(0)) else out
    },
    x)
}

# ---- tool function factory --------------------------------------------------------
make_tool_function <- function(tool, runner) {
  props <- tool$inputSchema$properties %||% list(); req <- unlist(tool$inputSchema$required)
  ord <- c(intersect(names(props), req), setdiff(names(props), req))
  fmls <- c(stats::setNames(rep(list(quote(expr = )), length(intersect(ord, req))), intersect(ord, req)),
            stats::setNames(vector("list", length(setdiff(ord, req))), setdiff(ord, req)),
            alist(... = ))
  f <- function() {
    given <- as.list(match.call(expand.dots = FALSE))[-1]
    given$... <- NULL
    vals <- c(mget(as.character(names(given)), envir = environment(), inherits = FALSE), list(...))
    missing_req <- setdiff(.req, names(vals))
    if (length(missing_req)) stop(sprintf("%s: missing required argument%s %s\nUsage: %s", .tool$name,
        if (length(missing_req) > 1) "s" else "", paste(sQuote(missing_req, FALSE), collapse = ", "),
        render_tool_signature(.tool)), call. = FALSE)
    args <- coerce_to_schema(Filter(Negate(is.null), vals), c(list(type = "object"), .tool$inputSchema[setdiff(names(.tool$inputSchema), "type")]))
    .runner(.tool, args)
  }
  formals(f) <- fmls
  environment(f) <- list2env(list(.tool = tool, .req = req, .runner = runner), parent = environment(make_tool_function))
  class(f) <- c("gptr_tool_function", "function")
  f
}
print.gptr_tool_function <- function(x, ...) { cat(render_tool_declaration(environment(x)$.tool), "\n"); invisible(x) }

# The exported dispatcher: `tools$<id>(...)`. It resolves against the registry of the active session.
new_tools <- function(registry, runner) structure(list(registry = registry, runner = runner), class = "gptr_tools")
`$.gptr_tools` <- function(x, name) {
  reg <- unclass(x)$registry(); ids <- vapply(reg, function(t) tool_identifier(t$name), "")
  i <- match(name, ids); if (is.na(i)) i <- match(name, vapply(reg, function(t) t$name, ""))
  if (is.na(i)) {
    near <- ids[utils::adist(name, ids) <= 3]
    stop(sprintf("Unknown tool %s.%s Use tool_search(\"...\") to find tools.", sQuote(name, FALSE),
                 if (length(near)) paste0(" Did you mean ", paste(near, collapse = ", "), "?") else ""), call. = FALSE)
  }
  make_tool_function(reg[[i]], unclass(x)$runner)
}
`[[.gptr_tools` <- function(x, name) `$.gptr_tools`(x, name)
names.gptr_tools <- function(x) vapply(unclass(x)$registry(), function(t) tool_identifier(t$name), "")
.DollarNames.gptr_tools <- function(x, pattern = "") grep(pattern, names(x), value = TRUE)
print.gptr_tools <- function(x, ...) { cat("<gptr tools>", length(names(x)), "tools\n"); cat(paste0("  ", names(x)), sep = "\n"); invisible(x) }

# ---- nested-call pipeline (what `runner` does inside the harness) -----------------
NESTED_LIMITS <- list(max_calls = 256L, max_arg_bytes_per_call = 8L * 1024L, max_arg_bytes_total = 32L * 1024L, max_error_chars = 500L)
new_nested_recorder <- function() {
  st <- new.env(parent = emptyenv()); st$calls <- list(); st$complete <- TRUE; st$arg_bytes <- 0L; st$n <- 0L
  st$start <- function(parent_id, name, args) {
    st$n <- st$n + 1L
    if (length(st$calls) >= NESTED_LIMITS$max_calls) { st$complete <- FALSE; return(NULL) }
    rec <- list(id = sprintf("%s/%d", parent_id, st$n), name = name, status = "unfinished", started = Sys.time())
    js <- as.character(jsonlite::toJSON(args, auto_unbox = TRUE, null = "null", digits = NA)); b <- nchar(js, "bytes")
    if (b > NESTED_LIMITS$max_arg_bytes_per_call || st$arg_bytes + b > NESTED_LIMITS$max_arg_bytes_total) {
      rec$arguments_bytes <- b; st$complete <- FALSE
    } else { rec$arguments <- js; st$arg_bytes <- st$arg_bytes + b }
    st$calls[[length(st$calls) + 1L]] <- rec
    length(st$calls)
  }
  st$finish <- function(i, is_error, error_text = "") {
    if (is.null(i)) return(invisible())
    st$calls[[i]]$status <- if (is_error) "error" else "ok"
    st$calls[[i]]$duration_ms <- round(as.numeric(Sys.time() - st$calls[[i]]$started, units = "secs") * 1000)
    if (is_error) st$calls[[i]]$error <- substr(error_text, 1L, NESTED_LIMITS$max_error_chars)
    st$calls[[i]]$started <- NULL
  }
  st
}
tool_error <- function(tool, text, result = NULL) structure(class = c("gptr_tool_error", "error", "condition"),
  list(message = sprintf("Tool %s failed: %s", tool, text), call = NULL, tool = tool, result = result))

# runner(tool, args): hooks -> execute -> record -> convert to an R value
make_runner <- function(execute, recorder, parent_id = "call_0", before = NULL) {
  function(tool, args) {
    i <- recorder$start(parent_id, tool$name, args)
    if (is.function(before)) {
      verdict <- before(tool, args)                    # permission gate / tool_call hook
      if (is.list(verdict) && !is.null(verdict$block)) {
        recorder$finish(i, TRUE, verdict$block); stop(tool_error(tool$name, verdict$block))
      }
    }
    result <- tryCatch(execute(tool, args), error = function(e) e)
    if (inherits(result, "error")) { recorder$finish(i, TRUE, conditionMessage(result)); stop(tool_error(tool$name, conditionMessage(result))) }
    texts <- vapply(Filter(function(b) identical(b$type, "text"), result$content %||% list()), function(b) b$text, "")
    text <- paste(texts, collapse = "\n")
    if (isTRUE(result$isError)) { recorder$finish(i, TRUE, text); stop(tool_error(tool$name, text, result)) }
    recorder$finish(i, FALSE)
    value <- if (!is.null(result$structuredContent)) result$structuredContent else text
    images <- Filter(function(b) identical(b$type, "image"), result$content %||% list())
    if (length(images)) attr(value, "images") <- images
    value
  }
}
`````

`````r
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "mcp_client.R")); source(file.path(W, "tools_as_functions.R"))
ok <- function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
rscript <- file.path(R.home("bin"), "Rscript")

# One live MCP server, connected lazily on the first call.
conn <- new.env(); conn$client <- NULL; conn$connects <- 0L
get_client <- function() {
  if (is.null(conn$client) || conn$client$state != "connected") {
    conn$client <- mcp_client(mcp_transport_stdio(rscript, c("--vanilla", file.path(W, "fixture_mcp_stdio.R"))), request_timeout = 10)
    conn$client$connect(); conn$connects <- conn$connects + 1L
  }
  conn$client
}
# Tool metadata can come from a cache; here we list once and close, to show that calls reconnect lazily.
server_tools <- get_client()$list_tools(); conn$client$close()
registry <- function() c(
  lapply(server_tools, function(t) { t$mcp <- list(server = "fix", tool = t$name); t$name <- mcp_tool_name("fix", t$name); t }),
  list(list(name = "word-count", description = "Count words in a string (a plain R tool).",
            inputSchema = list(type = "object", properties = list(text = list(type = "string")), required = list("text")),
            outputSchema = list(type = "object", properties = list(n = list(type = "integer"))),
            fn = function(args) list(content = list(), structuredContent = list(n = lengths(strsplit(args$text, "\\s+")))))))
execute <- function(tool, args) {
  if (!is.null(tool$mcp)) get_client()$call_tool(tool$mcp$tool, args) else tool$fn(args)
}
rec <- new_nested_recorder()
blocked <- character()
before <- function(tool, args) if (grepl("fail$", tool$name) && length(blocked)) list(block = "blocked by permission hook")
tools <- new_tools(registry, make_runner(execute, rec, parent_id = "toolu_01", before = before))

cat("---- declarations the model sees ----\n")
for (t in registry()[c(1, 2, 3, 9)]) cat(render_tool_declaration(t), "\n\n")

cat("---- model-written R code composing tools ----\n")
ok("names(tools) lists identifiers", all(c("mcp__fix__echo", "mcp__fix__tags_join", "word_count") %in% names(tools)))
ok("no connection until the first call", conn$connects == 1L)   # only the listing above
code <- quote({
  inputs <- c(alpha = "one two three", beta = "four five", gamma = "six")
  counts <- vapply(inputs, function(s) tools$word_count(text = s)$n, integer(1))
  total <- 0
  for (n in counts) total <- tools$mcp__fix__add(a = total, b = n)$sum
  label <- tools$mcp__fix__tags_join(tags = names(inputs)[counts > 1], sep = "+")
  single <- tools$mcp__fix__tags_join(tags = "solo")             # length-1 vector must stay a JSON array
  echoed <- tools$mcp__fix__echo("positional works too")
  list(counts = counts, total = total, label = label, single = single, echoed = echoed)
})
env <- new.env(parent = globalenv()); assign("tools", tools, envir = env)
out <- eval(code, env)
str(out)
ok("loop over in-memory objects + tool results", isTRUE(out$total == 6) && identical(out$label, "alpha+beta") &&
   identical(out$single, "solo") && identical(unname(out$counts), c(3L, 2L, 1L)))
ok("lazy reconnect happened exactly once for all nested calls", conn$connects == 2L)

e <- tryCatch(tools$mcp__fix__fail(), error = function(e) e)
ok("isError -> R condition gptr_tool_error (catchable with tryCatch)", inherits(e, "gptr_tool_error") && grepl("boom", conditionMessage(e)))
blocked <- "x"; e <- tryCatch(tools$mcp__fix__fail(), error = function(e) e)
ok("permission hook can block a nested call", grepl("blocked by permission hook", conditionMessage(e)))
e <- tryCatch(tools$mcp__fix__add(a = 1), error = function(e) e)
ok("missing required argument -> helpful error with usage", grepl("missing required argument 'b'", conditionMessage(e)) &&
   grepl("tools\\$mcp__fix__add\\(a, b\\)", conditionMessage(e)))
cat("  ", gsub("\n", " | ", conditionMessage(e)), "\n")
e <- tryCatch(tools$mcp__fix__add(a = 1:3, b = 2), error = function(e) e)
ok("vector passed where a scalar is required -> error before the call", grepl("args\\$a must be a single number", conditionMessage(e)))
e <- tryCatch(tools$mcp__fix__ecko("x"), error = function(e) e)
ok("unknown tool suggests near matches", grepl("Did you mean mcp__fix__echo", conditionMessage(e)))
img <- tools$mcp__fix__image()
ok("images ride along as an attribute", identical(attr(img, "images")[[1]]$mimeType, "image/png") && identical(as.character(img), "one pixel"))

cat("---- nested call record (attached to the R tool result) ----\n")
cat(sprintf("%d calls, complete=%s\n", length(rec$calls), rec$complete))
for (r in rec$calls[c(1, 4, 8, length(rec$calls) - 5)]) cat(" ", r$id, r$name, r$status, r$arguments %||% "", r$error %||% "", "\n")

cat("---- coercion unit checks ----\n")
s <- list(type = "object", properties = list(ids = list(type = "array", items = list(type = "integer")),
     opts = list(type = "object", properties = list(deep = list(type = "boolean"))), rows = list(type = "array", items = list(type = "object")),
     mode = list(enum = list("a", "b")), when = list(anyOf = list(list(type = "string"), list(type = "null")))))
j <- mcp_to_json(coerce_to_schema(list(ids = 7, opts = list(), rows = data.frame(x = 1:2, y = c("a", "b")), mode = factor("a"), when = NA), s))
cat(j, "\n")
ok("schema-directed JSON", identical(j, '{"ids":[7],"opts":{},"rows":[{"x":1,"y":"a"},{"x":2,"y":"b"}],"mode":"a","when":null}'))
ok("identifier rules", identical(vapply(c("my-tool", "_private", "9lives", "repeat", "a.b"), tool_identifier, "", USE.NAMES = FALSE),
   c("my_tool", "t_private", "t_9lives", "repeat_", "a.b")))
conn$client$close()
`````

Observed output (12 PASS, 0 FAIL):

`````text
---- declarations the model sees ----
#' Echo the text back.
#' @param text string. Text to echo
#' @return string (the tool's text output)
tools$mcp__fix__echo(text) 

#' Add two numbers and return structured content.
#' @param a number
#' @param b number
#' @return list(sum: number)
tools$mcp__fix__add(a, b) 

#' Join an array of tags (tests array coercion and name sanitising).
#' @param tags vector<string>
#' @param sep string, optional (default ",")
#' @return string (the tool's text output)
tools$mcp__fix__tags_join(tags, sep = NULL) 

#' Count words in a string (a plain R tool).
#' @param text string
#' @return list(n?: integer)
tools$word_count(text) 

---- model-written R code composing tools ----
[PASS] names(tools) lists identifiers
[PASS] no connection until the first call
List of 5
 $ counts: Named int [1:3] 3 2 1
  ..- attr(*, "names")= chr [1:3] "alpha" "beta" "gamma"
 $ total : int 6
 $ label : chr "alpha+beta"
 $ single: chr "solo"
 $ echoed: chr "positional works too"
[PASS] loop over in-memory objects + tool results
[PASS] lazy reconnect happened exactly once for all nested calls
[PASS] isError -> R condition gptr_tool_error (catchable with tryCatch)
[PASS] permission hook can block a nested call
[PASS] missing required argument -> helpful error with usage
   mcp__fix__add: missing required argument 'b' | Usage: tools$mcp__fix__add(a, b) 
[PASS] vector passed where a scalar is required -> error before the call
[PASS] unknown tool suggests near matches
[PASS] images ride along as an attribute
---- nested call record (attached to the R tool result) ----
12 calls, complete=TRUE
  toolu_01/1 word-count ok {"text":"one two three"}  
  toolu_01/4 mcp__fix__add ok {"a":0,"b":3}  
  toolu_01/8 mcp__fix__tags_join ok {"tags":["solo"]}  
  toolu_01/7 mcp__fix__tags_join ok {"tags":["alpha","beta"],"sep":"+"}  
---- coercion unit checks ----
{"ids":[7],"opts":{},"rows":[{"x":1,"y":"a"},{"x":2,"y":"b"}],"mode":"a","when":null} 
[PASS] schema-directed JSON
[PASS] identifier rules
`````

### 5.7 BM25 tool search (`bm25.R`, `test_bm25.R`)

`````r
# Port of Pi's tool-search ranker (packages/coding-agent/src/extensions/tool-search/tool.ts) to base R.
BM25_STOP_WORDS <- c("a","an","and","are","as","at","be","by","for","from","in","is","it","of","on","or","that","the","this","to","with")
bm25_stem <- function(term) {
  n <- nchar(term)
  ifelse(n > 4 & endsWith(term, "ies"), paste0(substr(term, 1, n - 3), "y"),
  ifelse(n > 4 & grepl("(ches|shes|sses|xes|zes)$", term), substr(term, 1, n - 2),
  ifelse(n > 3 & endsWith(term, "s") & !endsWith(term, "ss"), substr(term, 1, n - 1), term)))
}
bm25_tokenize <- function(text) {
  text <- gsub("([a-z0-9])([A-Z])", "\\1 \\2", text, perl = TRUE)
  text <- gsub("([A-Z]+)([A-Z][a-z])", "\\1 \\2", text, perl = TRUE)
  terms <- strsplit(tolower(text), "[^a-z0-9]+", perl = TRUE)[[1]]
  terms <- terms[nzchar(terms) & !terms %in% BM25_STOP_WORDS]
  if (!length(terms)) character() else bm25_stem(terms)
}
schema_text <- function(schema) {
  if (!is.list(schema) || is.null(names(schema))) return(character())
  parts <- character()
  if (is.character(schema$description)) parts <- c(parts, schema$description)
  if (is.list(schema$properties)) for (n in names(schema$properties)) parts <- c(parts, n, schema_text(schema$properties[[n]]))
  parts <- c(parts, schema_text(schema$items))
  for (key in c("anyOf", "oneOf", "allOf")) if (is.list(schema[[key]])) for (v in schema[[key]]) parts <- c(parts, schema_text(v))
  parts
}
tool_search_document <- function(tool, namespace = NULL) {
  parts <- c(tool$name, gsub("_", " ", tool$name, fixed = TRUE), tool$description %||% "", schema_text(tool$parameters %||% tool$inputSchema))
  if (!is.null(namespace)) parts <- c(parts, namespace$name, namespace$description %||% "")
  list(name = tool$name, text = paste(parts[nzchar(trimws(parts))], collapse = " "))
}
`%||%` <- function(a, b) if (is.null(a)) b else a
bm25_rank <- function(query, documents, limit = 8L, k1 = 1.2, b = 0.75) {
  q <- unique(bm25_tokenize(query))
  if (!length(q) || !length(documents) || limit <= 0) return(data.frame(name = character(), score = numeric()))
  counts <- lapply(documents, function(d) table(bm25_tokenize(d$text)))
  lengths_ <- vapply(counts, sum, numeric(1)); avg <- sum(lengths_) / length(documents); if (avg == 0) avg <- 1
  N <- length(documents)
  idf <- vapply(q, function(t) { f <- sum(vapply(counts, function(cn) t %in% names(cn), logical(1))); log(1 + (N - f + 0.5) / (f + 0.5)) }, numeric(1))
  score <- vapply(seq_along(documents), function(i) {
    cn <- counts[[i]]; s <- 0
    for (t in q) { c_ <- if (t %in% names(cn)) cn[[t]] else 0; if (!c_) next
      norm <- k1 * (1 - b + b * lengths_[i] / avg); s <- s + idf[[t]] * (c_ * (k1 + 1)) / (c_ + norm) }
    s }, numeric(1))
  out <- data.frame(name = vapply(documents, function(d) d$name, ""), score = score, stringsAsFactors = FALSE)
  out <- out[out$score > 0, , drop = FALSE]
  out <- out[order(-out$score, seq_len(nrow(out))), , drop = FALSE]      # ties keep document order
  rownames(out) <- NULL
  utils::head(out, limit)
}
`````

The reference is my transcription of Pi's ranking functions with the types removed (`bm25_ref.mjs`), run with the local Node 26.8.2. No Pi code was executed from the clone.

`````javascript
// Reference: the ranking functions from Pi's tool-search/tool.ts, types stripped, for a parity check.
const STOP_WORDS = new Set(["a","an","and","are","as","at","be","by","for","from","in","is","it","of","on","or","that","the","this","to","with"]);
function stem(term){ if (term.length>4 && term.endsWith("ies")) return `${term.slice(0,-3)}y`; if (term.length>4 && /(ches|shes|sses|xes|zes)$/.test(term)) return term.slice(0,-2); if (term.length>3 && term.endsWith("s") && !term.endsWith("ss")) return term.slice(0,-1); return term; }
function tokenize(text){ return text.replace(/([a-z0-9])([A-Z])/g,"$1 $2").replace(/([A-Z]+)([A-Z][a-z])/g,"$1 $2").toLowerCase().split(/[^a-z0-9]+/).filter(t=>t.length>0 && !STOP_WORDS.has(t)).map(stem); }
function isObject(v){ return typeof v==="object" && v!==null && !Array.isArray(v); }
function schemaText(schema, parts){ if(!isObject(schema)) return; if(typeof schema.description==="string") parts.push(schema.description); if(isObject(schema.properties)){ for(const [n,p] of Object.entries(schema.properties)){ parts.push(n); schemaText(p,parts);} } schemaText(schema.items,parts); for(const k of ["anyOf","oneOf","allOf"]){ const v=schema[k]; if(Array.isArray(v)) for(const x of v) schemaText(x,parts);} }
function doc(tool, namespace){ const parts=[tool.name, tool.name.replaceAll("_"," "), tool.description]; schemaText(tool.parameters, parts); if(namespace) parts.push(namespace.name, namespace.description ?? ""); return {name: tool.name, text: parts.filter(p=>p.trim()).join(" ")}; }
function rank(query, documents, limit, k1=1.2, b=0.75){ const q=[...new Set(tokenize(query))]; if(q.length===0||documents.length===0||limit<=0) return []; const tc=documents.map(d=>{const c=new Map(); for(const t of tokenize(d.text)) c.set(t,(c.get(t)??0)+1); return c;}); const lengths=tc.map(c=>[...c.values()].reduce((s,x)=>s+x,0)); const avg=lengths.reduce((s,x)=>s+x,0)/documents.length||1; const idf=new Map(q.map(t=>{const f=tc.filter(c=>c.has(t)).length; return [t, Math.log(1+(documents.length-f+0.5)/(f+0.5))];})); const m=[]; documents.forEach((d,i)=>{let s=0; for(const t of q){const c=tc[i].get(t); if(!c) continue; const norm=k1*(1-b+(b*lengths[i])/avg); s+=(idf.get(t)??0)*((c*(k1+1))/(c+norm));} if(s>0) m.push({name:d.name,score:s});}); return m.sort((a,b)=>b.score-a.score).slice(0,limit); }
import { readFileSync } from "node:fs";
const input = JSON.parse(readFileSync(process.argv[2], "utf8"));
const docs = input.tools.map(t => doc(t, t.namespace));
console.log(JSON.stringify({ tokens: tokenize(input.tokenize), results: input.queries.map(q => rank(q, docs, 8)) }));
`````

`````r
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "bm25.R"))
ns_gh <- list(name = "mcp__github", description = "GitHub repositories, issues and pull requests")
ns_db <- list(name = "mcp__warehouse", description = "SQL warehouse")
tools <- list(
  list(name = "mcp__github__search_issues", description = "Search issues and pull requests across repositories.", namespace = ns_gh,
       parameters = list(type = "object", properties = list(query = list(type = "string", description = "Search query using GitHub syntax"), perPage = list(type = "integer")))),
  list(name = "mcp__github__create_issue", description = "Open a new issue in a repository.", namespace = ns_gh,
       parameters = list(type = "object", properties = list(title = list(type = "string"), body = list(type = "string"), labels = list(type = "array", items = list(type = "string", description = "Label names"))))),
  list(name = "mcp__github__getPullRequestFiles", description = "List the files changed by a pull request.", namespace = ns_gh,
       parameters = list(type = "object", properties = list(pullNumber = list(type = "integer")))),
  list(name = "mcp__warehouse__run_query", description = "Run a read-only SQL query and return rows.", namespace = ns_db,
       parameters = list(type = "object", properties = list(sql = list(type = "string", description = "The SQL statement"), limit = list(type = "integer")))),
  list(name = "mcp__warehouse__list_tables", description = "List the tables of a schema with their columns.", namespace = ns_db,
       parameters = list(type = "object", properties = list(schema = list(anyOf = list(list(type = "string", description = "Schema name"), list(type = "null")))))),
  list(name = "fetch_url", description = "Fetch a web page and convert it to markdown.", parameters = list(type = "object", properties = list(url = list(type = "string"))))
)
queries <- c("search github issues", "sql tables", "pull request files", "the of and", "markdown", "issue labels", "queries")
input <- list(tools = tools, queries = queries, tokenize = "getHTTPResponse parses XMLHttpRequest_bodies, the Queries & classes/boxes")
f <- tempfile(fileext = ".json"); writeLines(jsonlite::toJSON(input, auto_unbox = TRUE, null = "null"), f)
ref <- jsonlite::fromJSON(system2("node", c(file.path(W, "bm25_ref.mjs"), f), stdout = TRUE), simplifyVector = FALSE)
docs <- lapply(tools, function(t) tool_search_document(t, t$namespace))
cat("R tokens:   ", bm25_tokenize(input$tokenize), "\n"); cat("node tokens:", unlist(ref$tokens), "\n")
all_ok <- identical(bm25_tokenize(input$tokenize), unlist(ref$tokens))
for (i in seq_along(queries)) {
  r <- bm25_rank(queries[i], docs); n <- ref$results[[i]]
  same <- nrow(r) == length(n) && (nrow(r) == 0 || (identical(r$name, vapply(n, function(x) x$name, "")) &&
          isTRUE(all.equal(r$score, vapply(n, function(x) x$score, 0), tolerance = 1e-12))))
  all_ok <- all_ok && same
  cat(sprintf("%-22s %s  top: %s\n", dQuote(queries[i], FALSE), if (same) "MATCH" else "DIFF",
      if (nrow(r)) paste(sprintf("%s (%.4f)", sub("^mcp__", "", r$name[1:min(2, nrow(r))]), r$score[1:min(2, nrow(r))]), collapse = ", ") else "(none)"))
}
cat(if (all_ok) "[PASS]" else "[FAIL]", "R port matches the reference ranker on names, order and scores\n")
`````

`````text
R tokens:    get http response parse xml http request body query class box 
node tokens: get http response parse xml http request body query class box 
"search github issues" MATCH  top: github__search_issues (4.5635), github__create_issue (2.2182)
"sql tables"           MATCH  top: warehouse__list_tables (3.5650), warehouse__run_query (1.7380)
"pull request files"   MATCH  top: github__getPullRequestFiles (4.6575), github__search_issues (1.7275)
"the of and"           MATCH  top: (none)
"markdown"             MATCH  top: fetch_url (1.9970)
"issue labels"         MATCH  top: github__create_issue (3.2110), github__search_issues (1.1028)
"queries"              MATCH  top: warehouse__run_query (1.6129), github__search_issues (1.2831)
[PASS] R port matches the reference ranker on names, order and scores
`````

### 5.8 Sub-agents (`subagents.R`, `test_subagents.R`)

The child runs a fake agent loop that emits Pi-shaped events; no model is called.

`````r
# Prototype: sub-agents for gptr (definition files, discovery, single / parallel / chain, usage roll-up)
# Backend "process": one fresh R process per sub-agent via callr::r_bg(); JSONL events on stdout,
# the structured result (any R object) through callr's result file.
`%||%` <- function(a, b) if (is.null(a)) b else a

SUBAGENT_MAX_PARALLEL_TASKS <- 8L
SUBAGENT_MAX_CONCURRENCY <- 4L
SUBAGENT_OUTPUT_CAP <- 50L * 1024L
SUBAGENT_KILL_GRACE_MS <- 5000

# ---- agent definition files --------------------------------------------------------
parse_frontmatter <- function(text) {
  text <- sub("^\ufeff", "", text)
  lines <- strsplit(gsub("\r\n?", "\n", text), "\n", fixed = TRUE)[[1]]
  if (!length(lines) || !grepl("^---\\s*$", lines[1])) return(list(frontmatter = list(), body = text))
  end <- which(grepl("^---\\s*$", lines[-1]))[1]
  if (is.na(end)) return(list(frontmatter = list(), body = text))
  fm <- tryCatch(yaml::yaml.load(paste(lines[seq_len(end)[-1]], collapse = "\n")), error = function(e) list())
  if (!is.list(fm)) fm <- list()
  body <- paste(lines[-seq_len(end + 1L)], collapse = "\n")
  list(frontmatter = fm, body = sub("^\n+", "", body))
}
parse_tool_list <- function(value) {
  raw <- if (is.character(value) && length(value) == 1L) strsplit(value, ",", fixed = TRUE)[[1]]
         else if (is.character(value)) value
         else if (is.list(value)) unlist(Filter(is.character, value)) else character()
  tools <- trimws(raw); tools <- tools[nzchar(tools)]
  if (length(tools)) tools else NULL
}
load_agents_from_dir <- function(dir, source) {
  if (!dir.exists(dir)) return(list())
  files <- sort(list.files(dir, pattern = "\\.md$", full.names = TRUE, recursive = TRUE))
  agents <- lapply(files, function(f) {
    txt <- tryCatch(paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), error = function(e) NULL)
    if (is.null(txt)) return(NULL)
    p <- parse_frontmatter(txt); fm <- p$frontmatter
    if (!is.character(fm$name) || !is.character(fm$description)) return(NULL)   # one bad file never breaks discovery
    list(name = fm$name, description = fm$description, tools = parse_tool_list(fm$tools),
         model = if (is.character(fm$model) && !identical(fm$model, "inherit")) fm$model,
         thinking = if (is.character(fm$effort %||% fm$thinking)) fm$effort %||% fm$thinking,
         max_turns = if (is.numeric(fm$maxTurns %||% fm$max_turns)) as.integer(fm$maxTurns %||% fm$max_turns),
         system_prompt = p$body, source = source, file_path = f)
  })
  Filter(Negate(is.null), agents)
}
find_nearest_dir <- function(cwd, rel) {
  cur <- normalizePath(cwd, winslash = "/", mustWork = FALSE)
  repeat {
    cand <- file.path(cur, rel); if (dir.exists(cand)) return(cand)
    parent <- dirname(cur); if (identical(parent, cur)) return(NULL)
    cur <- parent
  }
}
discover_agents <- function(cwd = getwd(), scope = c("user", "project", "both"),
                            user_dirs = file.path(tools::R_user_dir("gptr", "config"), "agents"),
                            project_rel = c(file.path(".gptr", "agents"), file.path(".claude", "agents"), file.path(".pi", "agents"))) {
  scope <- match.arg(scope)
  user <- if (scope != "project") unlist(lapply(user_dirs, load_agents_from_dir, source = "user"), recursive = FALSE) else list()
  project_dirs <- Filter(Negate(is.null), lapply(project_rel, function(r) find_nearest_dir(cwd, r)))
  # lowest priority first: foreign harness dirs, then .gptr/agents
  project <- if (scope != "user") unlist(lapply(rev(project_dirs), load_agents_from_dir, source = "project"), recursive = FALSE) else list()
  by_name <- list()
  for (a in c(user, project)) by_name[[a$name]] <- a            # project overrides user
  list(agents = unname(by_name), project_dirs = unlist(project_dirs))
}

# ---- result bookkeeping -------------------------------------------------------------
empty_usage <- function() list(input = 0, output = 0, cache_read = 0, cache_write = 0, cost = 0, context_tokens = 0, turns = 0L)
add_usage <- function(a, b) { for (k in c("input", "output", "cache_read", "cache_write", "cost")) a[[k]] <- a[[k]] + (b[[k]] %||% 0)
  a$turns <- a$turns + (b$turns %||% 0L); a }
final_output <- function(messages) {
  for (m in rev(messages)) if (identical(m$role, "assistant")) for (part in m$content) if (identical(part$type, "text")) return(part$text)
  ""
}
is_failed <- function(r) !identical(r$exit_code, 0L) || r$stop_reason %in% c("error", "aborted")
result_output <- function(r) {
  out <- if (is_failed(r)) c(r$error_message, if (nzchar(trimws(r$stderr))) r$stderr, final_output(r$messages)) else final_output(r$messages)
  out <- out[!is.na(out) & nzchar(out)]
  if (length(out)) out[[1]] else "(no output)"
}
truncate_output <- function(s, cap = SUBAGENT_OUTPUT_CAP) {
  n <- nchar(s, type = "bytes"); if (n <= cap) return(s)
  raw <- charToRaw(enc2utf8(s))[seq_len(cap)]
  while (length(raw) && bitwAnd(as.integer(raw[length(raw)]), 0xC0L) == 0x80L) raw <- raw[-length(raw)]   # do not cut a character
  if (length(raw) && as.integer(raw[length(raw)]) >= 0xC0L) raw <- raw[-length(raw)]
  kept <- rawToChar(raw); Encoding(kept) <- "UTF-8"
  sprintf("%s\n\n[Output truncated: %d bytes omitted. Full output preserved in the result object.]", kept, n - length(raw))
}
format_tokens <- function(n) if (n < 1000) as.character(n) else if (n < 10000) sprintf("%.1fk", n / 1000) else if (n < 1e6) sprintf("%dk", round(n / 1000)) else sprintf("%.1fM", n / 1e6)
format_usage <- function(u, model = NULL) {
  p <- c(if (u$turns > 0) sprintf("%d turn%s", u$turns, if (u$turns > 1) "s" else ""),
         if (u$input > 0) paste0("in:", format_tokens(u$input)), if (u$output > 0) paste0("out:", format_tokens(u$output)),
         if (u$cache_read > 0) paste0("R", format_tokens(u$cache_read)), if (u$cache_write > 0) paste0("W", format_tokens(u$cache_write)),
         if (u$cost > 0) sprintf("$%.4f", u$cost), model)
  paste(p, collapse = " ")
}

# ---- one running sub-agent -----------------------------------------------------------
# `worker` is a function(task) run in the child; it must cat() JSONL events and may return an R object.
subagent_start <- function(agent, task, worker, defaults = list(), cwd = NULL, step = NULL, export = list()) {
  spec <- list(agent = agent$name, system_prompt = agent$system_prompt, tools = agent$tools,
               model = agent$model %||% defaults$model,
               thinking = if (is.null(agent$model)) defaults$thinking else agent$thinking,   # inherit only with the model
               task = paste0("Task: ", task), export = export)
  proc <- callr::r_bg(worker, args = list(spec = spec), stdout = "|", stderr = "|", wd = cwd %||% getwd(),
                      supervise = TRUE, cleanup_tree = TRUE, package = FALSE,
                      env = c(callr::rcmd_safe_env(), GPTR_SUBAGENT_DEPTH = as.character(as.integer(Sys.getenv("GPTR_SUBAGENT_DEPTH", "0")) + 1L)))
  st <- new.env(parent = emptyenv())
  st$proc <- proc; st$agent <- agent$name; st$source <- agent$source; st$task <- task; st$step <- step
  st$messages <- list(); st$usage <- empty_usage(); st$stderr <- ""; st$model <- spec$model
  st$stop_reason <- NULL; st$error_message <- NULL; st$exit_code <- -1L; st$value <- NULL; st$aborted <- FALSE
  st$started <- Sys.time()
  st
}
subagent_pump <- function(st) {
  p <- st$proc
  lines <- tryCatch(p$read_output_lines(), error = function(e) character())
  err <- tryCatch(p$read_error(), error = function(e) ""); if (nzchar(err)) st$stderr <- paste0(st$stderr, err)
  changed <- FALSE
  for (ln in lines) {
    if (!nzchar(trimws(ln))) next
    ev <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(ev) || !is.list(ev)) next                       # non-JSON output of the child is ignored
    if (identical(ev$type, "message_end") && !is.null(ev$message)) {
      m <- ev$message; st$messages[[length(st$messages) + 1L]] <- m; changed <- TRUE
      if (identical(m$role, "assistant")) {
        st$usage$turns <- st$usage$turns + 1L
        u <- m$usage
        if (!is.null(u)) {
          st$usage$input <- st$usage$input + (u$input %||% 0); st$usage$output <- st$usage$output + (u$output %||% 0)
          st$usage$cache_read <- st$usage$cache_read + (u$cacheRead %||% 0); st$usage$cache_write <- st$usage$cache_write + (u$cacheWrite %||% 0)
          st$usage$cost <- st$usage$cost + (u$cost$total %||% 0); st$usage$context_tokens <- u$totalTokens %||% 0
        }
        if (is.null(st$model) && !is.null(m$model)) st$model <- m$model
        if (!is.null(m$stopReason)) st$stop_reason <- m$stopReason
        if (!is.null(m$errorMessage)) st$error_message <- m$errorMessage
      }
    }
  }
  changed
}
subagent_finish <- function(st) {
  subagent_pump(st)
  st$exit_code <- as.integer(st$proc$get_exit_status() %||% 1L)
  st$value <- tryCatch(st$proc$get_result(), error = function(e) {
    if (st$exit_code == 0L) st$exit_code <- 1L
    # The child's own stderr explains a crash better than callr's generic message.
    if (is.null(st$error_message) && !nzchar(trimws(st$stderr))) st$error_message <- conditionMessage(e)
    NULL })
  st$duration <- as.numeric(Sys.time() - st$started, units = "secs")
  invisible(st)
}
subagent_abort <- function(st) {
  if (!st$proc$is_alive()) return(invisible())
  st$aborted <- TRUE; st$stop_reason <- "aborted"
  try(st$proc$interrupt(), silent = TRUE)                      # SIGINT / CTRL+C: lets the child flush and clean up
  st$proc$wait(timeout = SUBAGENT_KILL_GRACE_MS)
  if (st$proc$is_alive()) try(st$proc$kill_tree(), silent = TRUE)
  invisible()
}
as_result <- function(st) list(agent = st$agent, agent_source = st$source %||% "unknown", task = st$task, exit_code = st$exit_code,
  messages = st$messages, stderr = st$stderr, usage = st$usage, model = st$model, stop_reason = st$stop_reason %||% "",
  error_message = st$error_message, step = st$step, value = st$value, duration = st$duration)

unknown_agent <- function(name, task, agents, step = NULL) list(agent = name, agent_source = "unknown", task = task, exit_code = 1L,
  messages = list(), stderr = sprintf("Unknown agent: \"%s\". Available agents: %s.", name,
  if (length(agents)) paste(sprintf("\"%s\"", vapply(agents, function(a) a$name, "")), collapse = ", ") else "none"),
  usage = empty_usage(), stop_reason = "", step = step)

# ---- scheduler: at most `concurrency` children, polled together -------------------------
run_pool <- function(jobs, start, concurrency = SUBAGENT_MAX_CONCURRENCY, on_update = NULL, poll_ms = 100) {
  n <- length(jobs); results <- vector("list", n); running <- list(); next_i <- 1L
  limit <- max(1L, min(concurrency, n))
  emit <- function() if (is.function(on_update)) on_update(list(done = sum(!vapply(results, is.null, NA)), running = length(running), total = n))
  tryCatch({
    while (next_i <= n || length(running)) {
      while (next_i <= n && length(running) < limit) {
        st <- start(jobs[[next_i]], next_i)
        if (is.environment(st)) running[[as.character(next_i)]] <- st else results[[next_i]] <- st   # immediate failure
        next_i <- next_i + 1L; emit()
      }
      if (!length(running)) next
      processx::poll(lapply(running, function(s) s$proc), poll_ms)
      for (key in names(running)) {
        st <- running[[key]]
        changed <- subagent_pump(st)
        if (!st$proc$is_alive()) {
          results[[as.integer(key)]] <- as_result(subagent_finish(st)); running[[key]] <- NULL; changed <- TRUE
        }
        if (changed) emit()
      }
    }
  }, interrupt = function(cnd) {
    for (st in running) subagent_abort(st)                      # Esc / Ctrl-C kills every child
    stop(structure(class = c("gptr_aborted", "error", "condition"), list(message = "Subagent was aborted", call = NULL)))
  })
  results
}

subagent_single <- function(agents, agent, task, worker, defaults = list(), cwd = NULL, on_update = NULL) {
  a <- Filter(function(x) x$name == agent, agents)
  if (!length(a)) return(unknown_agent(agent, task, agents))
  run_pool(list(list(agent = a[[1]], task = task, cwd = cwd)), function(job, i) subagent_start(job$agent, job$task, worker, defaults, job$cwd),
           1L, on_update)[[1]]
}
subagent_parallel <- function(agents, tasks, worker, defaults = list(), on_update = NULL, concurrency = SUBAGENT_MAX_CONCURRENCY) {
  if (length(tasks) > SUBAGENT_MAX_PARALLEL_TASKS)
    stop(sprintf("Too many parallel tasks (%d). Max is %d.", length(tasks), SUBAGENT_MAX_PARALLEL_TASKS), call. = FALSE)
  results <- run_pool(tasks, function(job, i) {
    a <- Filter(function(x) x$name == job$agent, agents)
    if (!length(a)) unknown_agent(job$agent, job$task, agents) else subagent_start(a[[1]], job$task, worker, defaults, job$cwd)
  }, concurrency, on_update)
  ok <- sum(!vapply(results, is_failed, NA))
  summaries <- vapply(results, function(r) sprintf("### [%s] %s\n\n%s", r$agent,
      if (is_failed(r)) paste0("failed", if (nzchar(r$stop_reason) && r$stop_reason != "end") sprintf(" (%s)", r$stop_reason) else "") else "completed",
      truncate_output(result_output(r))), "")
  list(text = sprintf("Parallel: %d/%d succeeded\n\n%s", ok, length(results), paste(summaries, collapse = "\n\n---\n\n")),
       mode = "parallel", results = results, usage = Reduce(add_usage, lapply(results, function(r) r$usage), empty_usage()))
}
subagent_chain <- function(agents, chain, worker, defaults = list(), on_update = NULL) {
  results <- list(); previous <- ""
  for (i in seq_along(chain)) {
    step <- chain[[i]]
    task <- gsub("{previous}", previous, step$task, fixed = TRUE)
    a <- Filter(function(x) x$name == step$agent, agents)
    r <- if (!length(a)) unknown_agent(step$agent, task, agents, i)
         else { st <- run_pool(list(1), function(job, k) subagent_start(a[[1]], task, worker, defaults, step$cwd, step = i), 1L, on_update)[[1]]; st$step <- i; st }
    results[[i]] <- r
    if (is_failed(r)) return(list(text = sprintf("Chain stopped at step %d (%s): %s", i, step$agent, result_output(r)),
                                  mode = "chain", results = results, is_error = TRUE,
                                  usage = Reduce(add_usage, lapply(results, function(r) r$usage), empty_usage())))
    previous <- final_output(r$messages)
  }
  list(text = final_output(results[[length(results)]]$messages) %||% "(no output)", mode = "chain", results = results,
       usage = Reduce(add_usage, lapply(results, function(r) r$usage), empty_usage()))
}
`````

`````r
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "subagents.R"))
ok <- function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))

# ---- agent files: gptr's own dir plus a foreign harness dir -------------------------
proj <- file.path(tempfile("proj-"), "pkg", "R"); dir.create(proj, recursive = TRUE)
root <- dirname(dirname(proj))
dir.create(file.path(root, ".gptr", "agents"), recursive = TRUE); dir.create(file.path(root, ".claude", "agents"), recursive = TRUE)
user_dir <- file.path(root, "user-agents"); dir.create(user_dir)
writeLines(c("---", "name: scout", "description: Fast recon", "tools: read, grep, find, ls", "model: claude-haiku-4-5", "---", "", "You are a scout."), file.path(user_dir, "scout.md"))
writeLines(c("---", "name: planner", "description: Plans", "tools: [read, grep]", "---", "You plan."), file.path(user_dir, "planner.md"))
writeLines(c("---", "name: scout", "description: Project scout overrides the user one", "tools:", "  - read", "  - R", "model: inherit", "maxTurns: 5", "---", "Project scout."), file.path(root, ".gptr", "agents", "scout.md"))
writeLines(c("---", "name: reviewer", "description: From a Claude Code project dir", "tools: Read, Grep, Glob", "model: sonnet", "---", "You review."), file.path(root, ".claude", "agents", "reviewer.md"))
writeLines(c("---", "description: no name -> skipped", "---", "x"), file.path(user_dir, "broken.md"))
writeLines(c("---", "name: [unclosed", "---", "x"), file.path(user_dir, "badyaml.md"))
d_user <- discover_agents(proj, "user", user_dirs = user_dir)
d_both <- discover_agents(proj, "both", user_dirs = user_dir)
nm <- function(d) sort(vapply(d$agents, function(a) a$name, ""))
ok("scope=user loads only user agents; broken files are skipped", identical(nm(d_user), c("planner", "scout")))
ok("scope=both adds project agents found by walking up from cwd (.gptr and .claude)", identical(nm(d_both), c("planner", "reviewer", "scout")))
sc <- Filter(function(a) a$name == "scout", d_both$agents)[[1]]
ok("project agent overrides the user agent of the same name", sc$source == "project" && identical(sc$tools, c("read", "R")) && is.null(sc$model) && identical(sc$max_turns, 5L))
ok("tools accepted as string or YAML list", identical(Filter(function(a) a$name == "planner", d_both$agents)[[1]]$tools, c("read", "grep")))

# ---- a fake agent loop run in the child (no model calls) -----------------------------
worker <- function(spec) {
  emit <- function(x) { writeLines(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")), stdout(), useBytes = TRUE); flush(stdout()) }
  task <- sub("^Task: ", "", spec$task)
  secs <- suppressWarnings(as.numeric(sub(".*sleep=([0-9.]+).*", "\\1", task))); if (is.na(secs)) secs <- 0.2
  emit(list(type = "session", id = "x")); cat("some non-JSON noise on stdout\n")
  if (grepl("crash", task)) { message("Error: provider key missing"); quit(status = 3) }
  for (turn in 1:2) {
    Sys.sleep(secs / 2)
    emit(list(type = "message_end", message = list(role = "assistant", model = spec$model %||% "default-model",
      content = if (turn == 1) list(list(type = "toolCall", id = "c1", name = "read", arguments = list(path = "DESCRIPTION")))
                else list(list(type = "text", text = sprintf("[%s pid=%d depth=%s] %s", spec$agent, Sys.getpid(), Sys.getenv("GPTR_SUBAGENT_DEPTH"), toupper(task)))),
      usage = list(input = 100, output = 20, cacheRead = 1000, cacheWrite = 0, totalTokens = 1120, cost = list(total = 0.0012)),
      stopReason = if (turn == 1) "toolUse" else if (grepl("llmerror", task)) "error" else "stop",
      errorMessage = if (turn == 2 && grepl("llmerror", task)) "529 overloaded")))
    if (turn == 1) emit(list(type = "message_end", message = list(role = "toolResult", toolCallId = "c1", toolName = "read",
                        content = list(list(type = "text", text = "Package: x")), isError = FALSE)))
  }
  data.frame(agent = spec$agent, n = nchar(task))          # structured R value returned next to the text
}
environment(worker) <- globalenv()
`%||%` <- function(a, b) if (is.null(a)) b else a
agents <- d_both$agents
defaults <- list(model = "anthropic/claude-sonnet-5", thinking = "medium")

cat("---- single ----\n")
r <- subagent_single(agents, "scout", "find auth code sleep=0.2", worker, defaults)
ok("single: final text, exit 0", !is_failed(r) && grepl("FIND AUTH CODE", final_output(r$messages)))
ok("single: agent without model inherits the dispatcher's model", identical(r$model, "anthropic/claude-sonnet-5"))
ok("single: usage rolled up over 2 turns", r$usage$turns == 2L && r$usage$input == 200 && abs(r$usage$cost - 0.0024) < 1e-12 && r$usage$context_tokens == 1120)
ok("single: tool result messages collected too (3 messages)", length(r$messages) == 3L)
ok("single: structured R value returned from the child", is.data.frame(r$value) && r$value$agent == "scout")
ok("child sees depth counter", grepl("depth=1", final_output(r$messages)))
cat("  ", format_usage(r$usage, r$model), "\n")
r <- subagent_single(agents, "nobody", "x", worker, defaults)
ok("unknown agent -> failed result listing the available agents", is_failed(r) && grepl('Available agents: "planner"', r$stderr))

cat("---- parallel ----\n")
updates <- character()
tasks <- lapply(1:6, function(i) list(agent = c("scout", "planner", "reviewer")[(i %% 3) + 1], task = sprintf("job %d sleep=1", i)))
tasks[[3]]$task <- "crash please"; tasks[[5]]$task <- "llmerror sleep=0.2"
t0 <- Sys.time()
p <- subagent_parallel(agents, tasks, worker, defaults, on_update = function(u) updates <<- c(updates, sprintf("%d/%d done, %d running", u$done, u$total, u$running)))
el <- as.numeric(Sys.time() - t0, units = "secs")
cat(sprintf("  6 tasks (4 x 1s, 2 fast failures), concurrency 4: %.2fs wall\n", el))
ok("parallel faster than sequential (4s of sleeps alone)", el < 3.2)
ok("never more than 4 running", max(as.integer(sub(".*, ([0-9]+) running", "\\1", updates))) <= 4L)
ok("results keep task order", identical(vapply(p$results, function(r) r$task, ""), vapply(tasks, function(t) t$task, "")))
ok("process crash -> failed with stderr diagnostics", is_failed(p$results[[3]]) && p$results[[3]]$exit_code == 3L && grepl("provider key missing", result_output(p$results[[3]])))
ok("stopReason error -> failed with the model error message", is_failed(p$results[[5]]) && identical(result_output(p$results[[5]]), "529 overloaded"))
ok("distinct child processes", length(unique(sub(".*pid=([0-9]+).*", "\\1", vapply(p$results[c(1, 2, 4, 6)], function(r) final_output(r$messages), "")))) == 4L)
ok("usage aggregated over tasks", p$usage$turns == 10L)
cat(substr(p$text, 1, 400), "\n  ...\n"); cat("  updates:", paste(unique(updates), collapse = " | "), "\n")
e <- tryCatch(subagent_parallel(agents, rep(tasks, 2), worker, defaults), error = function(e) conditionMessage(e))
ok("more than 8 tasks rejected", identical(e, "Too many parallel tasks (12). Max is 8."))

cat("---- chain ----\n")
ch <- subagent_chain(agents, list(list(agent = "scout", task = "alpha sleep=0.1"), list(agent = "planner", task = "plan using <{previous}> sleep=0.1")), worker, defaults)
cat("  ", ch$text, "\n")
ok("{previous} replaced by the prior step's final text", grepl("PLAN USING <\\[SCOUT PID=[0-9]+ DEPTH=1\\] ALPHA SLEEP=0.1>", ch$text))
ch <- subagent_chain(agents, list(list(agent = "scout", task = "crash"), list(agent = "planner", task = "never runs {previous}")), worker, defaults)
ok("chain stops at the first failing step", isTRUE(ch$is_error) && length(ch$results) == 1L && grepl("^Chain stopped at step 1 \\(scout\\)", ch$text))

cat("---- abort ----\n")
killer <- processx::process$new("sh", c("-c", sprintf("sleep 1; kill -INT %d", Sys.getpid())))
t0 <- Sys.time(); pids <- integer()
res <- tryCatch(subagent_parallel(agents, lapply(1:3, function(i) list(agent = "scout", task = "long sleep=30")), worker, defaults),
                gptr_aborted = function(e) "ABORTED")
el <- as.numeric(Sys.time() - t0, units = "secs")
ok("interrupt aborts the pool and kills the children quickly", identical(res, "ABORTED") && el < 8)
cat(sprintf("  aborted after %.2fs\n", el))
Sys.sleep(0.5)
left <- system2("pgrep", c("-f", "callr-"), stdout = TRUE, stderr = FALSE)
cat("  leftover callr children:", length(left), "\n")
ok("output cap keeps valid UTF-8", { s <- truncate_output(paste(rep("é", 40000), collapse = "")); validUTF8(s) && grepl("bytes omitted", s) })
`````

Observed output (23 PASS, 0 FAIL on this run):

`````text
[PASS] scope=user loads only user agents; broken files are skipped
[PASS] scope=both adds project agents found by walking up from cwd (.gptr and .claude)
[PASS] project agent overrides the user agent of the same name
[PASS] tools accepted as string or YAML list
---- single ----
[PASS] single: final text, exit 0
[PASS] single: agent without model inherits the dispatcher's model
[PASS] single: usage rolled up over 2 turns
[PASS] single: tool result messages collected too (3 messages)
[PASS] single: structured R value returned from the child
[PASS] child sees depth counter
   2 turns in:200 out:40 R2.0k $0.0024 anthropic/claude-sonnet-5 
[PASS] unknown agent -> failed result listing the available agents
---- parallel ----
  6 tasks (4 x 1s, 2 fast failures), concurrency 4: 2.10s wall
[PASS] parallel faster than sequential (4s of sleeps alone)
[PASS] never more than 4 running
[PASS] results keep task order
[PASS] process crash -> failed with stderr diagnostics
[PASS] stopReason error -> failed with the model error message
[PASS] distinct child processes
[PASS] usage aggregated over tasks
Parallel: 4/6 succeeded

### [planner] completed

[planner pid=31290 depth=1] JOB 1 SLEEP=1

---

### [reviewer] completed

[reviewer pid=31294 depth=1] JOB 2 SLEEP=1

---

### [scout] failed

Error: provider key missing


---

### [planner] completed

[planner pid=31308 depth=1] JOB 4 SLEEP=1

---

### [reviewer] failed (error)

529 overloaded

---

### [scout] completed

[scout pid=31345 depth=1 
  ...
  updates: 0/6 done, 1 running | 0/6 done, 2 running | 0/6 done, 3 running | 0/6 done, 4 running | 1/6 done, 3 running | 1/6 done, 4 running | 2/6 done, 3 running | 2/6 done, 4 running | 3/6 done, 3 running | 4/6 done, 2 running | 5/6 done, 1 running | 6/6 done, 0 running 
[PASS] more than 8 tasks rejected
---- chain ----
   [planner pid=31388 depth=1] PLAN USING <[SCOUT PID=31375 DEPTH=1] ALPHA SLEEP=0.1> SLEEP=0.1 
[PASS] {previous} replaced by the prior step's final text
[PASS] chain stops at the first failing step
---- abort ----
[PASS] interrupt aborts the pool and kills the children quickly
  aborted after 1.45s
Warning message:
In system2("pgrep", c("-f", "callr-"), stdout = TRUE, stderr = FALSE) :
  running command ''pgrep' -f callr- 2>/dev/null' had status 1
  leftover callr children: 0 
[PASS] output cap keeps valid UTF-8
`````

Timing of the parallel case over eight runs: seven between 1.84 and 2.15 s (1.84, 1.90, 2.15, 1.99, 1.97, 2.01, 2.10), and one run of 4.18 s that failed the `< 3.2 s` assertion while the full test suite was running on the loaded machine. A real test must not assert wall-clock bounds this tight.

Stronger abort check by process id (`test_abort_pids.R`), because `pgrep -f callr-` in the test above is a weak check:

`````r
# Stronger check than pgrep: the exact child pids must be gone after an abort.
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "subagents.R"))
worker <- function(spec) { cat('{"type":"session"}\n'); Sys.sleep(60); "never" }
environment(worker) <- globalenv()
agent <- list(name = "scout", description = "x", system_prompt = "x", source = "user")
sts <- lapply(1:3, function(i) subagent_start(agent, "long", worker))
Sys.sleep(1)
pids <- vapply(sts, function(s) s$proc$get_pid(), integer(1))
alive_before <- vapply(pids, function(p) ps::ps_is_running(ps::ps_handle(p)), NA)
t0 <- Sys.time(); for (s in sts) subagent_abort(s); el <- as.numeric(Sys.time() - t0, units = "secs")
Sys.sleep(0.3)
alive_after <- vapply(pids, function(p) tryCatch(ps::ps_is_running(ps::ps_handle(p)), error = function(e) FALSE), NA)
cat("children alive before abort:", alive_before, "\n")
cat(sprintf("abort of 3 children took %.2fs\n", el))
cat("children alive after abort: ", alive_after, "\n")
cat(if (all(alive_before) && !any(alive_after)) "[PASS]" else "[FAIL]", "all child processes are gone after abort\n")
`````

`````text
children alive before abort: TRUE TRUE TRUE 
abort of 3 children took 0.14s
children alive after abort:  FALSE FALSE FALSE 
[PASS] all child processes are gone after abort
`````

### 5.9 Backend measurements (`test_backends.R`) and callr checks

`````r
tm <- function(expr) { t0 <- Sys.time(); v <- force(expr); list(value = v, secs = round(as.numeric(Sys.time() - t0, units = "secs"), 2)) }
cat("R", as.character(getRversion()), " callr", as.character(packageVersion("callr")), " cores:", parallel::detectCores(), "\n")

# 1. process backend: cold start cost
r <- tm({ p <- callr::r_bg(function() Sys.getpid(), supervise = TRUE); p$wait(); p$get_result() })
cat(sprintf("callr::r_bg trivial child: %.2fs\n", r$secs))
r <- tm({ p <- callr::r_bg(function() { library(httr2); library(jsonlite); Sys.getpid() }); p$wait(); p$get_result() })
cat(sprintf("callr::r_bg child that loads httr2+jsonlite: %.2fs\n", r$secs))
rs <- tm(callr::r_session$new(wait = TRUE)); cat(sprintf("callr::r_session start: %.2fs; ", rs$secs))
r <- tm(rs$value$run(function() 1 + 1)); cat(sprintf("warm call: %.2fs\n", r$secs)); rs$value$close()

# 2. big in-memory object: 400 MB
big <- runif(5e7); cat(sprintf("object size: %.0f MB\n", as.numeric(object.size(big)) / 1024^2))
r <- tm({ p <- callr::r_bg(function(x) c(length(x), mean(x)), args = list(x = big)); p$wait(); p$get_result() })
cat(sprintf("process backend, object exported by serialization: %.2fs -> %s\n", r$secs, paste(signif(r$value, 6), collapse = " ")))

# 3. fork backend (Unix only): child sees `big` copy-on-write, nothing is serialized
if (.Platform$OS.type == "unix") {
  r <- tm({ job <- parallel::mcparallel({ c(length(big), mean(big), Sys.getpid()) }); parallel::mccollect(job)[[1]] })
  cat(sprintf("fork backend (mcparallel), same object: %.2fs -> %s (parent pid %d)\n", r$secs, paste(signif(r$value, 6), collapse = " "), Sys.getpid()))
  # four forked children in parallel, each doing HTTP-free work on the shared object
  r <- tm({ jobs <- lapply(1:4, function(i) parallel::mcparallel({ Sys.sleep(1); quantile(big, i / 5, names = FALSE) })); unlist(parallel::mccollect(jobs)) })
  cat(sprintf("4 forked sub-tasks x (1s sleep + quantile over 400MB): %.2fs wall -> %s\n", r$secs, paste(signif(r$value, 4), collapse = " ")))
  # child cannot change the parent's objects
  x <- 1; parallel::mccollect(parallel::mcparallel({ x <<- 2; assign("y_new", 1, envir = globalenv()); NULL }))
  cat("after forked child assigned x <<- 2: parent x =", x, "; y_new exists in parent:", exists("y_new"), "\n")
}
# 4. inline backend: separate history, shared environment through an overlay
target <- new.env(); assign("seurat_like", big[1:10], envir = target)
overlay <- new.env(parent = target)
eval(quote({ m <- mean(seurat_like); seurat_like <- NULL }), overlay)
cat("inline overlay: child computed m =", signif(get("m", overlay), 4), "; parent object intact:", length(get("seurat_like", target)) == 10L,
    "; parent has m:", exists("m", envir = target, inherits = FALSE), "\n")
`````

`````text
R 4.4.3  callr 3.7.6  cores: 8 
callr::r_bg trivial child: 0.40s
callr::r_bg child that loads httr2+jsonlite: 0.33s
callr::r_session start: 0.16s; warm call: 0.05s
object size: 381 MB
process backend, object exported by serialization: 1.47s -> 5e+07 0.499999
fork backend (mcparallel), same object: 0.18s -> 5e+07 0.499999 30207 (parent pid 30127)
4 forked sub-tasks x (1s sleep + quantile over 400MB): 3.47s wall -> 0.1999 0.4 0.6001 0.8
after forked child assigned x <<- 2: parent x = 1 ; y_new exists in parent: FALSE 
inline overlay: child computed m = 0.4257 ; parent object intact: TRUE ; parent has m: FALSE 
`````

An earlier run of the same script gave 0.37 s, 0.24 s, 0.10 s / 0.03 s, 1.06 s, 0.12 s and 3.09 s for the same lines.

callr facts checked separately (`chk.R`, not reproduced; re-checked by the verifier with callr 3.7.6 and 3.8.0): `callr::r_bg(..., stdin = "|", wd = , cleanup_tree = TRUE)` passes these through `...` to processx and delivers a line written by the parent to the child; `rs$run_with_output()` returns the child's stdout together with the result; `rs$interrupt()` stops a running call within about 0.02-0.07 s and leaves the session `idle` and reusable. The interrupted call's result carries an error of class `callr_timeout_error`, so gptr must not report an interrupt as a timeout by class alone. callr 3.8.0 changed the default of `r_bg(package =)` from `FALSE` to `NULL`; pass it explicitly.

### 5.10 In-process multiplexing of streams (`test_multi.R`)

`````r
# In-process concurrency: N streaming HTTP responses multiplexed by one curl multi pool (no threads, no child R).
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "mcp_client.R"))
rscript <- file.path(R.home("bin"), "Rscript")
ports <- replicate(3, httpuv::randomPort(host = "127.0.0.1"))
procs <- lapply(ports, function(p) processx::process$new(rscript, c("--vanilla", file.path(W, "fixture_stream_socket.R"), p)))
Sys.sleep(1.2)
pool <- curl::new_pool()
state <- lapply(seq_along(ports), function(i) { e <- new.env(); e$parser <- sse_parser(); e$buf <- raw(); e$events <- list(); e$stamps <- numeric(); e$done <- FALSE; e })
t0 <- Sys.time()
for (i in seq_along(ports)) local({
  st <- state[[i]]; idx <- i
  h <- curl::new_handle(url = sprintf("http://127.0.0.1:%d/mcp", ports[idx]))
  body <- mcp_to_json(list(jsonrpc = "2.0", id = idx, method = "tools/call",
            params = list(name = "x", arguments = list(steps = 5L, delay = 0.3), `_meta` = list(progressToken = idx))))
  curl::handle_setopt(h, post = TRUE, postfields = body)
  curl::handle_setheaders(h, "Content-Type" = "application/json", Accept = "application/json, text/event-stream")
  curl::multi_add(h, pool = pool,
    data = function(bytes, final = FALSE) {                 # called as chunks arrive
      st$buf <- c(st$buf, bytes)
      repeat {
        nl <- match(as.raw(0x0a), st$buf); if (is.na(nl)) break
        line <- rawToChar(st$buf[seq_len(nl - 1L)]); Encoding(line) <- "UTF-8"; st$buf <- st$buf[-seq_len(nl)]
        ev <- st$parser$feed_line(line)
        if (!is.null(ev)) { st$events[[length(st$events) + 1L]] <- mcp_from_json(ev$data)
                            st$stamps <- c(st$stamps, round(as.numeric(Sys.time() - t0, units = "secs"), 2)) }
      }
    },
    done = function(res) st$done <- TRUE, fail = function(msg) { st$done <- TRUE; st$error <- msg })
})
ticks <- 0L
while (!all(vapply(state, function(s) s$done, NA))) { curl::multi_run(timeout = 0.2, poll = TRUE, pool = pool); ticks <- ticks + 1L }
total <- as.numeric(Sys.time() - t0, units = "secs")
for (i in seq_along(state)) cat(sprintf("stream %d: %d events at %s -> %s\n", i, length(state[[i]]$events), paste(state[[i]]$stamps, collapse = " "),
    state[[i]]$events[[length(state[[i]]$events)]]$result$content[[1]]$text))
cat(sprintf("3 concurrent 1.85s streams finished in %.2fs wall (event loop iterations: %d)\n", total, ticks))
cat(if (total < 2.6 && all(vapply(state, function(s) length(s$events) == 6L, NA))) "[PASS]" else "[FAIL]", "streams were multiplexed in one R process\n")
invisible(lapply(procs, function(p) p$kill()))
`````

`````text
stream 1: 6 events at 0.37 0.67 0.97 1.28 1.58 1.94 -> streamed
stream 2: 6 events at 0.36 0.67 0.97 1.27 1.58 1.94 -> streamed
stream 3: 6 events at 0.37 0.67 0.97 1.28 1.59 1.94 -> streamed
3 concurrent 1.85s streams finished in 1.95s wall (event loop iterations: 3)
[PASS] streams were multiplexed in one R process
`````

### 5.11 Harness-agnostic MCP config (`mcp_config.R`, `test_config.R`)

`````r
# Prototype: harness-agnostic MCP configuration loading for gptr
`%||%` <- function(a, b) if (is.null(a)) b else a
MCP_EXPOSURES <- c("code", "code-deferred", "deferred", "direct", "hidden")
MCP_SERVER_NAME <- "^[A-Za-z0-9_-]+$"

# ---- value resolution: ${VAR}, ${VAR:-default}, $VAR, ${env:VAR}, {env:VAR}, $$, !command -------------
resolve_config_value <- function(value, env = character(), allow_command = TRUE, description = "value") {
  stopifnot(is.character(value), length(value) == 1L)
  lookup <- function(name) { v <- env[name]; if (!is.na(v) && nzchar(v)) return(unname(v)); v <- Sys.getenv(name, NA); if (is.na(v) || !nzchar(v)) NULL else v }
  if (startsWith(value, "!")) {
    if (!allow_command) stop(sprintf("Failed to resolve %s: commands are disabled", description), call. = FALSE)
    cmd <- substring(value, 2L)
    shell <- if (.Platform$OS.type == "windows") list(Sys.getenv("COMSPEC", "cmd.exe"), c("/d", "/s", "/c", cmd)) else list("/bin/sh", c("-c", cmd))
    res <- tryCatch(processx::run(shell[[1]], shell[[2]], timeout = 10, error_on_status = FALSE,
                                  windows_verbatim_args = .Platform$OS.type == "windows"), error = function(e) NULL)
    out <- if (!is.null(res) && identical(res$status, 0L)) trimws(res$stdout) else ""
    if (!nzchar(out)) stop(sprintf("Failed to resolve %s from shell command", description), call. = FALSE)
    return(out)
  }
  if (grepl("${input:", value, fixed = TRUE))
    stop(sprintf("%s uses a VS Code ${input:...} prompt; replace it with an environment variable", description), call. = FALSE)
  out <- ""; missing <- character(); i <- 1L; n <- nchar(value)
  take <- function(name, default = NULL) { v <- lookup(name) %||% default; if (is.null(v)) { missing <<- c(missing, name); "" } else v }
  while (i <= n) {
    rest <- substring(value, i)
    if (startsWith(rest, "$$")) { out <- paste0(out, "$"); i <- i + 2L; next }
    if (startsWith(rest, "$!")) { out <- paste0(out, "!"); i <- i + 2L; next }
    m <- regmatches(rest, regexec("^\\$\\{(?:env:)?([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\\}", rest, perl = TRUE))[[1]]
    if (length(m)) { has_default <- grepl(":-", m[1], fixed = TRUE)
      out <- paste0(out, take(m[2], if (has_default) m[3])); i <- i + nchar(m[1]); next }
    m <- regmatches(rest, regexec("^\\{env:([A-Za-z_][A-Za-z0-9_]*)\\}", rest, perl = TRUE))[[1]]
    if (length(m)) { out <- paste0(out, take(m[2])); i <- i + nchar(m[1]); next }
    m <- regmatches(rest, regexec("^\\$([A-Za-z_][A-Za-z0-9_]*)", rest, perl = TRUE))[[1]]
    if (length(m)) { out <- paste0(out, take(m[2])); i <- i + nchar(m[1]); next }
    out <- paste0(out, substr(rest, 1L, 1L)); i <- i + 1L
  }
  if (length(missing)) stop(sprintf("Failed to resolve %s from environment variable%s: %s", description,
                                    if (length(unique(missing)) > 1) "s" else "", paste(unique(missing), collapse = ", ")), call. = FALSE)
  out
}
expand_home <- function(x) {
  if (identical(x, "~")) return(path.expand("~"))
  if (startsWith(x, "~/") || (.Platform$OS.type == "windows" && startsWith(x, "~\\"))) return(file.path(path.expand("~"), substring(x, 3L)))
  x
}

# ---- minimal TOML reader (enough for Codex's [mcp_servers.*] tables) --------------------------------
toml_parse <- function(text) {
  lines <- strsplit(gsub("\r\n?", "\n", paste(text, collapse = "\n")), "\n", fixed = TRUE)[[1]]
  root <- list(); path <- character()
  strip_comment <- function(s) {           # remove a # comment that is outside strings
    inq <- ""; ch <- strsplit(s, "")[[1]]; i <- 1L
    while (i <= length(ch)) { c_ <- ch[i]
      if (nzchar(inq)) { if (c_ == "\\" && inq == "\"") i <- i + 1L else if (c_ == inq) inq <- "" }
      else if (c_ %in% c("\"", "'")) inq <- c_
      else if (c_ == "#") return(paste(ch[seq_len(i - 1L)], collapse = ""))
      i <- i + 1L }
    s
  }
  split_top <- function(s, sep) {          # split on sep outside strings / brackets
    out <- character(); cur <- ""; depth <- 0L; inq <- ""; ch <- strsplit(s, "")[[1]]; i <- 1L
    while (i <= length(ch)) { c_ <- ch[i]
      if (nzchar(inq)) { cur <- paste0(cur, c_); if (c_ == "\\" && inq == "\"" && i < length(ch)) { i <- i + 1L; cur <- paste0(cur, ch[i]) } else if (c_ == inq) inq <- "" }
      else if (c_ %in% c("\"", "'")) { inq <- c_; cur <- paste0(cur, c_) }
      else if (c_ %in% c("[", "{")) { depth <- depth + 1L; cur <- paste0(cur, c_) }
      else if (c_ %in% c("]", "}")) { depth <- depth - 1L; cur <- paste0(cur, c_) }
      else if (c_ == sep && depth == 0L) { out <- c(out, cur); cur <- "" }
      else cur <- paste0(cur, c_)
      i <- i + 1L }
    c(out, cur)
  }
  parse_key <- function(k) vapply(split_top(trimws(k), "."), function(p) { p <- trimws(p)
    if (grepl("^\".*\"$", p)) jsonlite::fromJSON(p) else if (grepl("^'.*'$", p)) substr(p, 2L, nchar(p) - 1L) else p }, "", USE.NAMES = FALSE)
  parse_value <- function(v) {
    v <- trimws(v)
    if (grepl("^\"", v)) return(jsonlite::fromJSON(v))                       # basic string: JSON-compatible escapes
    if (grepl("^'", v)) return(substr(v, 2L, nchar(v) - 1L))                 # literal string
    if (v %in% c("true", "false")) return(v == "true")
    if (grepl("^\\[", v)) { inner <- trimws(substr(v, 2L, nchar(v) - 1L)); if (!nzchar(inner)) return(list())
      items <- trimws(split_top(inner, ",")); return(lapply(items[nzchar(items)], parse_value)) }
    if (grepl("^\\{", v)) { inner <- trimws(substr(v, 2L, nchar(v) - 1L)); out <- list(); if (!nzchar(inner)) return(structure(list(), names = character(0)))
      for (kv in split_top(inner, ",")) { p <- split_top(kv, "="); out <- set_in(out, parse_key(p[1]), parse_value(paste(p[-1], collapse = "="))) }
      return(out) }
    num <- suppressWarnings(as.numeric(gsub("_", "", v))); if (!is.na(num)) return(num)
    stop("Unsupported TOML value: ", v, call. = FALSE)
  }
  set_in <- function(x, keys, value) { if (length(keys) == 1L) { x[[keys]] <- value; return(x) }
    x[[keys[1]]] <- set_in(if (is.list(x[[keys[1]]])) x[[keys[1]]] else list(), keys[-1], value); x }
  i <- 1L
  while (i <= length(lines)) {
    ln <- trimws(strip_comment(lines[i])); i <- i + 1L
    if (!nzchar(ln)) next
    if (grepl("^\\[\\[", ln)) stop("TOML arrays of tables are not supported", call. = FALSE)
    if (grepl("^\\[.*\\]$", ln)) { path <- parse_key(substr(ln, 2L, nchar(ln) - 1L)); root <- set_in(root, path, get_in(root, path) %||% list()); next }
    eq <- split_top(ln, "=")
    val <- paste(eq[-1], collapse = "=")
    while (sum(lengths(regmatches(val, gregexpr("[[{]", val)))) > sum(lengths(regmatches(val, gregexpr("[]}]", val)))) && i <= length(lines)) {
      val <- paste(val, trimws(strip_comment(lines[i]))); i <- i + 1L }               # multi-line array
    root <- set_in(root, c(path, parse_key(eq[1])), parse_value(val))
  }
  root
}
get_in <- function(x, keys) { for (k in keys) { if (!is.list(x) || is.null(x[[k]])) return(NULL); x <- x[[k]] }; x }

# ---- normalisation of one server entry from any harness into gptr's shape ---------------------------
# gptr shape: list(type = "stdio"|"http", command, args, env, cwd | url, headers, oauth, timeout (seconds),
#                  startup_timeout, exposure, tool_exposure, enabled, enabled_tools, disabled_tools)
normalize_server <- function(name, x, dialect = "mcpServers") {
  if (!grepl(MCP_SERVER_NAME, name)) return(sprintf("invalid server name \"%s\" (use letters, digits, \"_\" and \"-\")", name))
  if (!is.list(x) || is.null(names(x))) return(sprintf("server \"%s\" must be an object", name))
  type <- x$type
  if (identical(dialect, "opencode")) {                       # {"type":"local","command":[...],"environment":{}} / {"type":"remote","url":}
    if (identical(type, "local")) { cmd <- unlist(x$command); x$command <- cmd[1]; x$args <- as.list(cmd[-1]); x$env <- x$environment; type <- "stdio" }
    if (identical(type, "remote")) type <- "http"
  }
  if (identical(dialect, "codex")) {
    hdr <- x$http_headers %||% list()
    for (h in names(x$env_http_headers %||% list())) hdr[[h]] <- paste0("${", x$env_http_headers[[h]], "}")
    if (!is.null(x$bearer_token_env_var)) hdr[["Authorization"]] <- paste0("Bearer ${", x$bearer_token_env_var, "}")
    if (length(hdr)) x$headers <- hdr
    for (v in unlist(x$env_vars)) x$env[[v]] <- x$env[[v]] %||% paste0("${", v, "}")
    x$timeout <- x$tool_timeout_sec; x$startup_timeout <- x$startup_timeout_sec
  }
  if (identical(type, "sse")) return(sprintf("server \"%s\": legacy SSE transport is not supported; use the streamable HTTP URL", name))
  if (identical(type, "ws")) return(sprintf("server \"%s\": WebSocket transport is not supported", name))
  out <- list(name = name, enabled = !identical(x$enabled, FALSE) && !isTRUE(x$disabled))
  timeout <- x$timeout
  if (is.numeric(timeout)) {
    if (timeout <= 0) return(sprintf("server \"%s\": timeout must be positive", name))
    # Claude Code writes milliseconds (minimum 1000), Pi and Codex write seconds.
    out$timeout <- as.numeric(if (identical(dialect, "claude") || timeout >= 1000) timeout / 1000 else timeout)
  }
  if (is.numeric(x$startup_timeout)) out$startup_timeout <- x$startup_timeout
  exposure <- x$exposure; if (identical(exposure, "codemode")) exposure <- "code"; if (identical(exposure, "codemode-deferred")) exposure <- "code-deferred"
  if (!is.null(exposure) && !exposure %in% MCP_EXPOSURES) return(sprintf("server \"%s\": exposure must be one of %s", name, paste(MCP_EXPOSURES, collapse = ", ")))
  out$exposure <- exposure %||% "code"
  out$tool_exposure <- x$toolExposure %||% x$tool_exposure
  out$enabled_tools <- unlist(x$enabled_tools); out$disabled_tools <- unlist(x$disabled_tools)
  if (is.character(x$url) && (is.null(type) || type %in% c("http", "streamable-http"))) {
    # Claude Code expands variables in `url` too, so a templated URL is validated when it is resolved at connect time.
    if (!grepl("$", x$url, fixed = TRUE) && !grepl("^https?://", x$url)) return(sprintf("server \"%s\": url must be an http or https URL", name))
    out$type <- "http"; out$url <- x$url; out$headers <- x$headers; out$oauth <- x$oauth
    return(out)
  }
  if (is.character(x$command) && (is.null(type) || identical(type, "stdio"))) {
    if (length(x$command) != 1L) return(sprintf("server \"%s\": command is a single executable; put arguments in args", name))
    if (!is.null(x$args) && !all(vapply(x$args, is.character, NA))) return(sprintf("server \"%s\": args must be an array of strings", name))
    out$type <- "stdio"; out$command <- x$command; out$args <- unlist(x$args) %||% character(); out$env <- x$env; out$cwd <- x$cwd
    return(out)
  }
  sprintf("server \"%s\" needs either \"command\" (stdio) or \"url\" (streamable HTTP)", name)
}

read_mcp_file <- function(path, scope, dialect = NULL, project = NULL) {
  servers <- list(); errors <- character()
  if (!file.exists(path)) return(list(servers = servers, errors = errors))
  dialect <- dialect %||% if (grepl("\\.toml$", path)) "codex" else "mcpServers"
  parsed <- tryCatch(if (dialect == "codex") toml_parse(readLines(path, warn = FALSE, encoding = "UTF-8"))
                     else jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) e)
  if (inherits(parsed, "error")) return(list(servers = servers, errors = sprintf("%s: %s", path, conditionMessage(parsed))))
  table <- switch(dialect,
    codex = parsed$mcp_servers, vscode = parsed$servers, opencode = parsed$mcp,
    claude = c(parsed$mcpServers, if (!is.null(project)) parsed$projects[[project]]$mcpServers),   # ~/.claude.json: only these keys are read
    parsed$mcpServers %||% parsed$servers)
  for (name in names(table)) {
    s <- normalize_server(name, table[[name]], dialect)
    if (is.character(s)) errors <- c(errors, sprintf("%s: %s", path, s)) else { s$source <- path; s$scope <- scope; servers[[name]] <- s }
  }
  list(servers = servers, errors = errors)
}

mcp_config_candidates <- function(cwd = getwd(), home = path.expand("~"), foreign = FALSE) {
  win <- .Platform$OS.type == "windows"; mac <- Sys.info()[["sysname"]] == "Darwin"
  appdata <- Sys.getenv("APPDATA", file.path(home, "AppData", "Roaming"))
  own <- list(
    list(path = file.path(tools::R_user_dir("gptr", "config"), "mcp.json"), scope = "user", dialect = "mcpServers"),
    list(path = file.path(cwd, ".mcp.json"), scope = "project", dialect = "claude"),          # shared project standard
    list(path = file.path(cwd, ".gptr", "mcp.json"), scope = "project", dialect = "mcpServers"))
  other <- list(
    list(path = file.path(home, ".claude.json"), scope = "user", dialect = "claude", harness = "claude-code"),
    list(path = if (win) file.path(appdata, "Claude", "claude_desktop_config.json")
                else if (mac) file.path(home, "Library", "Application Support", "Claude", "claude_desktop_config.json")
                else file.path(home, ".config", "Claude", "claude_desktop_config.json"), scope = "user", dialect = "mcpServers", harness = "claude-desktop"),
    list(path = file.path(home, ".cursor", "mcp.json"), scope = "user", dialect = "mcpServers", harness = "cursor"),
    list(path = file.path(cwd, ".cursor", "mcp.json"), scope = "project", dialect = "mcpServers", harness = "cursor"),
    list(path = file.path(cwd, ".vscode", "mcp.json"), scope = "project", dialect = "vscode", harness = "vscode"),
    list(path = file.path(home, ".codex", "config.toml"), scope = "user", dialect = "codex", harness = "codex"),
    list(path = file.path(cwd, ".codex", "config.toml"), scope = "project", dialect = "codex", harness = "codex"),
    list(path = file.path(home, ".pi", "agent", "mcp.json"), scope = "user", dialect = "mcpServers", harness = "pi"),
    list(path = file.path(cwd, ".pi", "mcp.json"), scope = "project", dialect = "mcpServers", harness = "pi"),
    list(path = file.path(home, ".config", "mcptools", "config.json"), scope = "user", dialect = "mcpServers", harness = "mcptools"))
  if (foreign) c(other, own) else own          # later entries win
}
load_mcp_config <- function(cwd = getwd(), home = path.expand("~"), foreign = FALSE, project_trusted = FALSE) {
  servers <- list(); errors <- character(); skipped <- character()
  for (cand in mcp_config_candidates(cwd, home, foreign)) {
    if (cand$scope == "project" && !project_trusted) { if (file.exists(cand$path)) skipped <- c(skipped, cand$path); next }
    r <- read_mcp_file(cand$path, cand$scope, cand$dialect, project = normalizePath(cwd, winslash = "/", mustWork = FALSE))
    for (n in names(r$servers)) servers[[n]] <- r$servers[[n]]
    errors <- c(errors, r$errors)
  }
  list(servers = servers, errors = errors, skipped_untrusted = skipped)
}
tool_exposure <- function(server, tool) {
  ov <- server$tool_exposure %||% list()
  if (!is.null(ov[[tool]])) return(ov[[tool]])
  for (pat in names(ov)) if (grepl("*", pat, fixed = TRUE) && grepl(utils::glob2rx(pat), tool)) return(ov[[pat]])
  if (length(server$enabled_tools) && !tool %in% server$enabled_tools) return("hidden")
  if (tool %in% server$disabled_tools) return("hidden")
  server$exposure %||% "code"
}
`````

`````r
W <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track06"
source(file.path(W, "mcp_config.R"))
ok <- function(label, cond) cat(sprintf("[%s] %s\n", if (isTRUE(cond)) "PASS" else "FAIL", label))
home <- tempfile("home-"); cwd <- file.path(home, "work", "proj")
dir.create(file.path(cwd, ".gptr"), recursive = TRUE); dir.create(file.path(cwd, ".vscode")); dir.create(file.path(home, ".codex")); dir.create(file.path(home, ".cursor"))
Sys.setenv(R_USER_CONFIG_DIR = file.path(home, "rconfig"), DOCS_TOKEN = "tok123", FIGMA_OAUTH_TOKEN = "fig456", REGION = "us-east-1")
dir.create(tools::R_user_dir("gptr", "config"), recursive = TRUE)
cat("user config dir:", tools::R_user_dir("gptr", "config"), "\n")

writeLines('{"mcpServers": {
  "filesystem": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "."]},
  "docs": {"url": "https://example.com/mcp", "headers": {"Authorization": "Bearer ${DOCS_TOKEN}"}, "exposure": "direct", "timeout": 120},
  "old": {"type": "sse", "url": "https://example.com/sse"},
  "bad name!": {"command": "x"},
  "github": {"url": "https://api.githubcopilot.com/mcp/", "exposure": "deferred",
             "toolExposure": {"search_code": "direct", "get_*": "codemode", "delete_*": "hidden"}}}}',
  file.path(tools::R_user_dir("gptr", "config"), "mcp.json"))
writeLines('{"mcpServers": {"docs": {"type": "http", "url": "${API_BASE_URL:-https://api.example.com}/mcp", "timeout": 600000},
  "local": {"type": "stdio", "command": "~/bin/server", "args": ["--root", "${REGION}"], "env": {"K": "v"}}}}', file.path(cwd, ".mcp.json"))
writeLines('{"servers": {"vs": {"type": "stdio", "command": "uvx", "args": ["thing"], "env": {"KEY": "${input:api-key}"}}}}', file.path(cwd, ".vscode", "mcp.json"))
writeLines(c('# codex config', 'model = "gpt-6-sol"', '', '[mcp_servers.context7]', 'command = "npx"', 'args = ["-y", "@upstash/context7-mcp"] # trailing comment',
  'env_vars = ["LOCAL_TOKEN"]', 'startup_timeout_sec = 20', '', '[mcp_servers.context7.env]', 'MY_ENV_VAR = "MY # not a comment"', '',
  '[mcp_servers.figma]', 'url = "https://mcp.figma.com/mcp"', 'bearer_token_env_var = "FIGMA_OAUTH_TOKEN"', 'http_headers = { "X-Figma-Region" = "us-east-1" }',
  'tool_timeout_sec = 45', 'enabled_tools = [', '  "get_file",', '  "get_comments",', ']', 'enabled = false'), file.path(home, ".codex", "config.toml"))
writeLines('{"mcpServers": {"cur": {"command": "node", "args": ["server.js"], "env": {"A": "${env:REGION}"}}}}', file.path(home, ".cursor", "mcp.json"))

cfg <- load_mcp_config(cwd, home, foreign = FALSE, project_trusted = FALSE)
ok("untrusted project: only the user file is read, project files are reported as skipped",
   identical(sort(names(cfg$servers)), c("docs", "filesystem", "github")) && length(cfg$skipped_untrusted) == 1L)
ok("invalid entries are reported, the others still load", length(cfg$errors) == 2L && any(grepl("legacy SSE", cfg$errors)) && any(grepl("invalid server name", cfg$errors)))
cat(paste0("  ", sub(home, "~", cfg$errors, fixed = TRUE)), sep = "\n")

cfg <- load_mcp_config(cwd, home, foreign = TRUE, project_trusted = TRUE)
cat("  servers:", paste(sprintf("%s[%s,%s]", names(cfg$servers), vapply(cfg$servers, function(s) s$type, ""), vapply(cfg$servers, function(s) s$scope, "")), collapse = " "), "\n")
ok("all harness files merged", setequal(names(cfg$servers), c("filesystem", "docs", "github", "local", "vs", "context7", "figma", "cur")))
ok("project entry replaces the user entry of the same name", identical(cfg$servers$docs$scope, "project") && identical(cfg$servers$docs$source, file.path(cwd, ".mcp.json")))
ok("Claude Code timeout 600000 ms -> 600 s; Pi-style 120 stays seconds", identical(cfg$servers$docs$timeout, 600) &&
   identical(load_mcp_config(cwd, home)$servers$docs$timeout, 120))
ok("${VAR:-default} expands to the default", identical(resolve_config_value(cfg$servers$docs$url), "https://api.example.com/mcp"))
ok("codex TOML: stdio table, nested env table, comment inside string", identical(cfg$servers$context7$args, c("-y", "@upstash/context7-mcp")) &&
   identical(cfg$servers$context7$env$MY_ENV_VAR, "MY # not a comment") && identical(cfg$servers$context7$env$LOCAL_TOKEN, "${LOCAL_TOKEN}") && cfg$servers$context7$startup_timeout == 20)
ok("codex TOML: bearer_token_env_var + http_headers + multi-line array + enabled=false", identical(cfg$servers$figma$headers$Authorization, "Bearer ${FIGMA_OAUTH_TOKEN}") &&
   identical(cfg$servers$figma$headers$`X-Figma-Region`, "us-east-1") && identical(cfg$servers$figma$enabled_tools, c("get_file", "get_comments")) &&
   isFALSE(cfg$servers$figma$enabled) && cfg$servers$figma$timeout == 45)
ok("header resolution", identical(resolve_config_value(cfg$servers$figma$headers$Authorization), "Bearer fig456"))
ok("${env:VAR} (Cursor/VS Code) and {env:VAR} (opencode)", identical(resolve_config_value(cfg$servers$cur$env$A), "us-east-1") && identical(resolve_config_value("x-{env:REGION}"), "x-us-east-1"))
e <- tryCatch(resolve_config_value(cfg$servers$vs$env$KEY, description = 'MCP server "vs" env "KEY"'), error = function(e) conditionMessage(e))
ok("${input:...} gives an actionable error", grepl("VS Code \\$\\{input", e)); cat("  ", e, "\n")
e <- tryCatch(resolve_config_value("Bearer ${NOPE_1} $NOPE_2", description = 'header "Authorization"'), error = function(e) conditionMessage(e))
ok("missing variables are named", identical(e, 'Failed to resolve header "Authorization" from environment variables: NOPE_1, NOPE_2'))
ok("escapes $$ and $!", identical(resolve_config_value("cost $$5 $!x"), "cost $5 !x"))
ok("!command", identical(resolve_config_value("!echo Bearer abc"), "Bearer abc"))
ok("~ expansion in command", identical(expand_home(cfg$servers$local$command), file.path(path.expand("~"), "bin/server")))
gh <- cfg$servers$github
ok("toolExposure: exact > first matching pattern > server default (codemode mapped to code)",
   identical(c(tool_exposure(gh, "search_code"), tool_exposure(gh, "get_issue"), tool_exposure(gh, "delete_repo"), tool_exposure(gh, "list_prs")),
             c("direct", "codemode", "hidden", "deferred")))
ok("codex enabled_tools acts as an allow list", identical(c(tool_exposure(cfg$servers$figma, "get_file"), tool_exposure(cfg$servers$figma, "post")), c("code", "hidden")))
if (requireNamespace("RcppTOML", quietly = TRUE)) {
  ref <- RcppTOML::parseTOML(file.path(home, ".codex", "config.toml")); mine <- toml_parse(readLines(file.path(home, ".codex", "config.toml")))
  ok("minimal TOML reader agrees with RcppTOML on this file", identical(unlist(mine$mcp_servers$figma$enabled_tools), ref$mcp_servers$figma$enabled_tools) &&
     identical(mine$mcp_servers$context7$env$MY_ENV_VAR, ref$mcp_servers$context7$env$MY_ENV_VAR) && identical(mine$model, ref$model) &&
     identical(mine$mcp_servers$figma$http_headers[["X-Figma-Region"]], ref$mcp_servers$figma$http_headers[["X-Figma-Region"]]))
}
`````

Observed output (18 PASS, 0 FAIL):

`````text
user config dir: <tmp>//Rtmpjqp5sO/home-764f30e18ef/rconfig/R/gptr 
[PASS] untrusted project: only the user file is read, project files are reported as skipped
[PASS] invalid entries are reported, the others still load
  ~/rconfig/R/gptr/mcp.json: server "old": legacy SSE transport is not supported; use the streamable HTTP URL
  ~/rconfig/R/gptr/mcp.json: invalid server name "bad name!" (use letters, digits, "_" and "-")
  servers: cur[stdio,user] vs[stdio,project] context7[stdio,user] figma[http,user] filesystem[stdio,user] docs[http,project] github[http,user] local[stdio,project] 
[PASS] all harness files merged
[PASS] project entry replaces the user entry of the same name
[PASS] Claude Code timeout 600000 ms -> 600 s; Pi-style 120 stays seconds
[PASS] ${VAR:-default} expands to the default
[PASS] codex TOML: stdio table, nested env table, comment inside string
[PASS] codex TOML: bearer_token_env_var + http_headers + multi-line array + enabled=false
[PASS] header resolution
[PASS] ${env:VAR} (Cursor/VS Code) and {env:VAR} (opencode)
[PASS] ${input:...} gives an actionable error
   MCP server "vs" env "KEY" uses a VS Code ${input:...} prompt; replace it with an environment variable 
[PASS] missing variables are named
[PASS] escapes $$ and $!
[PASS] !command
[PASS] ~ expansion in command
[PASS] toolExposure: exact > first matching pattern > server default (codemode mapped to code)
[PASS] codex enabled_tools acts as an allow list
[PASS] minimal TOML reader agrees with RcppTOML on this file
`````

### 5.12 What was not run

- Nothing on Windows or Linux.
- No third-party MCP server other than the handshake with `claude mcp serve`. No `npx` or `uvx` server was started.
- No real OAuth provider; the authorization server was my fixture.
- No real browser; `utils::browseURL()` was replaced by a process that follows redirects.
- No sub-agent with a real model; usage numbers in the sub-agent test are synthetic.
- The `GET` server-to-client stream, `resources/*` and Client ID Metadata Documents are not implemented in the prototype.
- The keep-alive/backoff path of SSE resumption was exercised once (one cut, one resume), not the retry limit.

---

## 6. CRAN and cross-platform considerations

### 6.1 CRAN policy

- **File system**: write only under `tools::R_user_dir("gptr", "config" | "cache" | "data")` (R >= 4.0) and the project's `.gptr/`, and only after a user action (`mcp_add()`, `mcp_login()`, first interactive `gptr()`), never at load time. Tests and examples use `tempdir()` and set `R_USER_CONFIG_DIR` (verified to redirect `R_user_dir()` in `test_config.R`).
- **Global environment**: the `tools` dispatcher avoids assignments into `.GlobalEnv` and avoids `attach()`.
- **Network**: tests use the local fixtures; still wrap tests that open sockets or start processes in `skip_on_cran()`, because CRAN machines may forbid listening sockets and timing is unreliable there.
- **Cores**: examples and tests must not use more than 2 processes. `max_concurrency` defaults to 4 at run time; tests set it to 2.
- **Processes left behind**: use `cleanup_tree = TRUE`, `supervise = TRUE`, and close everything in `on.exit()`. After an abort the three child process ids were no longer running (executed: `test_abort_pids.R`).
- **Non-ASCII in R code**: R code must be ASCII; `R CMD check` gives a WARNING ("Portable packages must use only ASCII characters in their R code ... Use \uxxxx escapes", verified with a throw-away package under R 4.4.3). The truncation marker must therefore be written `"\u2026"` and the BOM strip `"^\ufeff"`. The prototypes as first recorded contained the literal characters (`truncate_middle()` in `mcp_client.R`, the BOM regex in `subagents.R`, one display line in `test_stdio.R`); the listings in section 5 now use the escapes.
- **Interactive only**: `mcp_login()` opens a browser; guard with `interactive()` and offer `manual = TRUE`.
- **License**: Pi's OAuth code is adapted from the MIT-licensed MCP TypeScript SDK. My R code is written from the specification and from reading Pi, not translated line by line; still, credit both in `inst/COPYRIGHTS` or the DESCRIPTION if the implementation follows them closely.

### 6.2 Windows specifics

| Topic | Issue | Recommendation | Status |
|---|---|---|---|
| `.cmd` / `.bat` shims (`npx.cmd`, `uvx` is an `.exe`) | `CreateProcess` does not run batch files directly; Pi uses `cross-spawn` for this | resolve with `Sys.which()`; if the path ends in `.cmd` or `.bat`, run `cmd.exe /c call <shim> <args...>` as the processx documentation advises | documentation VERIFIED (processx help, "Batch files"); behaviour UNCERTAIN, not run |
| Process tree | killing `cmd.exe` leaves the server alive; Pi uses `taskkill /T /F` | `p$kill_tree()` (uses the `ps` package, which processx imports) | LIKELY |
| Signals | no `SIGTERM`; Pi force-kills on Windows | close stdin, wait, then `p$kill_tree()`; skip `p$signal(15)` on Windows | LIKELY |
| Interrupting children | `p$interrupt()` sends CTRL+BREAK on Windows | use it for sub-agents; fall back to kill after 5 s | documentation VERIFIED; behaviour UNCERTAIN |
| Console windows | child windows pop up | `windows_hide_window = TRUE` (set in the prototype) | LIKELY |
| Line endings | servers may write `\r\n` | strip a trailing `\r` (done in both parsers) | VERIFIED in code, not on Windows |
| Encoding | native encoding is not always UTF-8 before R 4.2 / old Windows | `encoding = "UTF-8"` in processx, `enc2utf8()` + `useBytes = TRUE` on write, mark strings on read | VERIFIED on macOS in a C locale |
| File permissions | `Sys.chmod("0600")` has no effect | rely on the user profile's ACL; document it; consider the keyring package as an option | LIKELY |
| Home expansion | `~` and `~\` | `path.expand()`; handle `~\` | VERIFIED in code |
| Fork backend | not available | `backend = "fork"` errors with a clear message; `auto` never picks it | VERIFIED: `mcparallel` is Unix only by documentation |
| Shell for `!command` values | no `/bin/sh` | `cmd.exe /d /s /c` with `windows_verbatim_args = TRUE` | UNCERTAIN |
| Firewall prompt | listening on all interfaces triggers a prompt | bind the OAuth callback to `127.0.0.1` with httpuv; never use base `serverSocket()` | VERIFIED that `serverSocket()` binds `*` |
| Opening the browser | `cmd /c start` re-parses metacharacters | `utils::browseURL()` calls `shell.exec()` on Windows, which does not go through `cmd.exe` | LIKELY |
| Config paths | `%APPDATA%`, MSIX redirect for Claude Desktop | table in section 3.4 | from documentation |

### 6.3 Other environments

- **RStudio and Positron**: forking is unsafe there; `backend = "fork"` must refuse when `Sys.getenv("RSTUDIO") == "1"` or when the session is a GUI. processx and callr work.
- **knitr / Quarto rendering and `Rscript`**: non-interactive, so permission prompts and OAuth sign-in cannot ask. MCP servers that need sign-in fail with `mcp_auth_required` and a message naming `mcp_login()`.
- **Jupyter (IRkernel)**: stdout of the kernel is not a terminal; progress display must go through `message()` or the display system. Child processes work as elsewhere (LIKELY).
- **C locale** (CI, Docker, cron): handled by the `useBytes` rule; covered by a test that unsets `LANG`.

---

## 7. Risks, pitfalls, open questions

### 7.1 Pitfalls found by experiment or by reading

1. `cat()` and `writeLines()` without `useBytes = TRUE` re-encode UTF-8 to the native encoding; in a C locale a marked UTF-8 string is written as `<U+00E9>`, and unmarked UTF-8 bytes passed through jsonlite become `<c3><a9>`. Both corrupt JSON (section 5.3; re-checked by the verifier with `LC_ALL=C`). `file(encoding = "UTF-8")` connections do not avoid it.
2. `jsonlite::toJSON(auto_unbox = TRUE)` turns length-1 vectors into scalars; an empty `list()` becomes `[]`, not `{}`. Use schema-directed coercion and `structure(list(), names = character(0))`.
3. `jsonlite::fromJSON()` returns integers for whole numbers, so `identical(x, 6)` fails; compare with `==` or convert.
4. `httr2::resp_stream_sse()` drops events with empty data and ignores `retry`; it cannot drive MCP resumption.
5. `processx$write_input()` is non-blocking and may write only part of a large message; loop on the returned remainder and keep reading stdout meanwhile to avoid a pipe deadlock (verified with 400 KB).
6. A function used inside `lapply()` does not see the caller's frame through `environment()`; capture the frame first (bug hit while writing the tool function factory).
7. `on.exit(close(resp))` inside a retry loop closes the response bound to the name at exit, that is the retried one; close the rejected response explicitly (bug hit in the HTTP transport).
8. Dynamic client registration is repeated if the callback port changes between sign-ins; store and reuse the port.
9. A timed-out request may still be answered later; the client must discard responses with unknown ids (verified).
10. The `timeout` field means seconds in Pi and Codex and milliseconds in Claude Code.
11. MCP tool names may contain `.`; model providers' tool names may not, and R identifiers may not contain `-`. Sanitising can make two names collide; the hash suffix resolves it for provider names, the "first wins" rule for identifiers.
12. Pi's sub-agent example listens for `tool_result_end`, an event that does not exist elsewhere in the repository. Do not copy it; use `message_end` and `tool_execution_end`.
13. Pi's sub-agent example does not add child usage to the parent's totals.
14. Wall-clock assertions in tests are flaky on loaded machines (one of eight runs took 4.18 s instead of about 2 s).
15. Pi's sub-agent example schedules `SIGKILL` behind `if (!proc.killed)`; in Node `killed` becomes true once `SIGTERM` is delivered, so the escalation never happens. gptr must test whether the child has exited, not whether a signal was sent.
16. `pgrep -f callr-` counts callr processes of *other* R sessions on a shared machine (the verifier's re-run saw 1-3 unrelated, freshly started ones); check exact child pids as `test_abort_pids.R` does.

### 7.2 Risks

- **Security of project files**: `.mcp.json`, `.gptr/mcp.json` and project agent files are controlled by whoever wrote the repository and can start arbitrary commands or carry hostile prompts. Trust prompts are required, and non-interactive runs must default to *not* loading untrusted project files.
- **`!command` values** run a shell. Support them only in user-level files, or behind an option.
- **Tool descriptions and MCP results are untrusted text** that reaches the model. The harness should mark tool output as data, and permission checks must not rely on server-provided annotations alone.
- **Tokens at rest** are plain JSON. Mode 0600 protects on Unix only.
- **No sandbox**: model-written R code that calls tools has the user's rights. This is inherent in REQ-09 and REQ-22; permission modes are the control, and nested tool calls must pass the same gate as direct calls.
- **Fork backend**: forking a process that has loaded multi-threaded libraries (data.table, arrow, BLAS) or has open connections can hang or corrupt state. Keep it opt-in and documented as experimental.
- **Synchronous client**: notifications that arrive while gptr is not waiting are read only at the next request. For stdio the pipe buffers them; a very chatty server could fill the pipe and block. Draining all connections at each turn boundary limits this.
- **Context cost of sub-agents**: every child re-sends its system prompt and tool declarations; cheap models for scouts and the 50 KB cap on returned text keep the parent context small.
- **Maintenance**: the MCP specification changes about twice a year. Keeping the client small and version negotiation tolerant (four accepted versions) limits the cost.

### 7.3 Open questions

1. **Default sub-agent backend**: `inline` (can use session objects, sequential, shares the process) or `process` (isolated, parallel, no objects)? Recommendation above is `auto`; the maintainer should confirm.
2. **Name of the dispatcher object**: `tools` reads like Pi's codemode and is what models expect, but shares its name with a base package. Alternatives: `tool`, `gptr_tools`.
3. **Should user-level configs of other harnesses be read automatically?** REQ-30 says servers configured for other agents "should be usable". Automatic reading is convenient but touches files such as `~/.claude.json` that hold unrelated private data.
4. **Default exposure of MCP tools**: `code` (Pi's choice, minimal tool surface) or `direct` (works with models that write poor R)? Possibly `direct` below some tool count and `code` above.
5. **Client identity for OAuth**: the 2025-11-25 specification prefers Client ID Metadata Documents, which need a document hosted at an HTTPS URL owned by the project. Dynamic registration works today but is labelled a backwards-compatibility path.
6. **Timeout unit heuristic** (values >= 1000 are milliseconds): acceptable, or should gptr use an unambiguous key such as `timeout_sec` in its own files?
7. **Permission prompts from child processes**: forward to the parent console over stdin/stdout as proposed, or run children only in non-interactive permission modes?
8. **Sessions of sub-agents**: keep a session file per child (debuggable, costs disk) or none, as Pi's `--no-session`?
9. **Elicitation and sampling**: some servers require them. Not planned for v1; is that acceptable?
10. **Windows behaviour** of `.cmd` shims, CTRL+BREAK and `kill_tree()` must be tested on a Windows machine before release.
11. **`yaml` as Imports or Suggests** depends on the skills track.

---

## 8. Sources

### Local source (Pi commit `1b34779`)

- `$PI/packages/coding-agent/examples/extensions/subagent/index.ts`, `agents.ts`, `README.md`, `agents/{scout,planner,reviewer,worker}.md`, `prompts/{implement,scout-and-plan,implement-and-review}.md`
- `$PI/packages/coding-agent/examples/extensions/handoff.ts`
- `$PI/packages/mcp/README.md`, `package.json`, `src/client.ts`, `src/auth-provider.ts`, `src/index.ts`, `src/protocol/{types,jsonrpc,content}.ts`, `src/transports/{transport,stdio,streamable-http}.ts`, `src/oauth/{types,discovery,errors,flow,provider,callback,index}.ts`, `test/fixtures/{stdio-server,stubborn-server}.mjs` (read only)
- `$PI/packages/coding-agent/src/extensions/mcp/{index,config,runtime,tools,oauth,resources,log}.ts`
- `$PI/packages/coding-agent/src/core/{mcp-servers,resolve-config-value,nested-tool-calls}.ts`, `src/core/extensions/types.ts:360-615`, `src/core/tools/truncate.ts:292-314`, `src/config.ts:532-562`, `src/utils/open-browser.ts`
- `$PI/packages/coding-agent/src/extensions/tool-search/{index,tool}.ts`
- `$PI/packages/codemode/README.md`, `package.json`, `src/{types,index,identifier,source,wasm,declarations}.ts`, `src/runtime/{host,worker,protocol,prelude-source}.ts`
- `$PI/packages/coding-agent/src/extensions/codemode/{tool,execute}.ts`
- `$PI/packages/coding-agent/src/experimental/{coordinator,process,session-worker-manager}.ts`, `session-worker.ts:1-420`
- `$PI/packages/agent/examples/mcp-codemode/tools.ts`, `$PI/packages/agent/src/agent-loop.ts:939`
- `$PI/packages/durable/README.md`, `$PI/packages/{server,protocol,client}/README.md`
- `$PI/packages/coding-agent/docs/{mcp,json,message-types,cli,settings,models,sdk}.md`

### Web (fetched 2026-09-29)

- MCP specification 2025-11-25, transports: https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- MCP specification 2025-11-25, lifecycle: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
- MCP specification 2025-11-25, authorization: https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization
- MCP specification 2025-11-25, tools: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- Claude Code, MCP: https://code.claude.com/docs/en/mcp
- Claude Code, sub-agents: https://code.claude.com/docs/en/sub-agents
- Codex, MCP configuration: https://learn.chatgpt.com/docs/extend/mcp?surface=cli (redirect target of https://developers.openai.com/codex/mcp)
- mcptools on CRAN (v1.0.3, 2026-09-18): https://cran.r-project.org/package=mcptools and https://cran.r-project.org/web/packages/mcptools/refman/mcptools.html
- mcptools 1.0.0 announcement: https://opensource.posit.co/blog/2026-07-06_mcptools-1-0-0/
- pi-subagents package page: https://pi.dev/packages/pi-subagents
- Config file locations of Claude Desktop, Cursor, VS Code (search results): https://scalar.com/learn/mcp/mcp-server-configuration, https://github.com/anthropics/claude-code/issues/26073, https://gofastmcp.com/integrations/mcp-json-configuration
- RFC 7636 appendix B test vector (used in `test_http.R`): https://datatracker.ietf.org/doc/html/rfc7636#appendix-B

### Local documentation

- processx 3.8.6 help page `?process` (sections "Batch files", `interrupt()`, `kill_tree()`, `write_input()`, `encoding`)
- httr2 1.2.2 source of `resp_stream_sse`, `parse_event`, `resp_boundary_pushback` (printed from the installed package)
- callr 3.7.6 `args(callr::r_bg)`

---

## Verification log

Adversarial fact-check performed 2026-09-29 by a separate verifier against the Pi clone (commit `1b34779`), official documentation, and fresh runs of every prototype in section 5 (extracted from this report, `W` repointed). Runs used `/usr/local/bin/Rscript --vanilla`, R 4.4.3, macOS; the verifier's shell had **no `LANG`, i.e. a C locale**, and the key tests were repeated with `LANG=en_US.UTF-8` and against current CRAN httr2 1.3.0 / processx 3.9.0 / callr 3.8.0 / rlang 1.3.0 in a temporary library. No paid API call; `claude mcp serve` was started only for the handshake in `test_interop.R`.

| # | Claim (section) | Verdict | Source / evidence |
|---|---|---|---|
| 1 | Sub-agent spawn arguments, order, `shell: false`, stdio, temp prompt file mode 0600 removed in `finally` (2.1.4) | confirmed | `subagent/index.ts:239-247,249-263,300-350,426-439` |
| 2 | Agent frontmatter: `name`/`description` required strings, `tools` string or list, `model` string, non-recursive `*.md`, scope precedence, re-discovery per call (2.1.2) | confirmed | `agents.ts:11-19,34-39,53-60,76-103,116-147`; `index.ts:489`; `src/config.ts:532-562` |
| 3 | `MAX_PARALLEL_TASKS = 8`, `MAX_CONCURRENCY = 4`, `COLLAPSED_ITEM_COUNT = 10`, `PER_TASK_OUTPUT_CAP = 50 * 1024`; error and summary texts (2.1.5-2.1.6, 3.6) | confirmed | `index.ts:33-36,193-202,505-518,591,605-614,669-685,705` |
| 4 | Abort sends SIGTERM then SIGKILL after 5000 ms "if the process has not exited" (2.1.6, 3.6) | **corrected** | `index.ts:410-424` guards the KILL with `!proc.killed`; Node docs: `killed` "does not indicate whether the child process has terminated" (https://nodejs.org/api/child_process.html) |
| 5 | `tool_result_end` occurs only in the sub-agent example; tool results arrive as `message_end` (2.1.5) | confirmed | `grep -rn tool_result_end packages` -> `index.ts:384` only; `agent/src/agent-loop.ts:938-939`; `docs/json.md` |
| 6 | Sub-agent usage not added to the parent's usage (1.4, 2.1.5) | confirmed | `index.ts` return sites carry `content`, `details`, `isError` only; aggregation only in the renderer (`index.ts:850-861`) |
| 7 | `@earendil-works/pi-mcp` 0.99.1, no official SDK dependency, OAuth adapted from SDK v1.29.0, protocol `2025-11-25` + three accepted versions (1.5, 3.6) | confirmed | `mcp/package.json:2-3,53-55` (only dependency `cross-spawn`), `mcp/README.md:3,112,118`, `protocol/types.ts:4-9` |
| 8 | Not implemented: batches, legacy HTTP+SSE, sampling, elicitation, tasks, prompts, cited to `README.md:132` (2.2.3) | **corrected** | README lists batches, legacy HTTP+SSE, servers, sampling, tasks; elicitation/prompts absent by grep of `client.ts`; resources are implemented |
| 9 | Default MCP exposure `codemode`; five exposures; `toolExposure` exact > first matching pattern (1.7, 2.2.1) | confirmed | `core/mcp-servers.ts:8-42,141-149`; note `extensions/mcp/tools.ts:38-40` maps both `codemode-deferred` and `deferred` to core exposure `deferred` |
| 10 | Config validation (name regex, `sse` rejected with quoted message, `timeout` seconds default 60), project file only when trusted (2.2.1) | confirmed | `core/mcp-servers.ts:152-196`; `extensions/mcp/config.ts:68-107`; `docs/mcp.md:28-31` |
| 11 | Pi value resolution: `!cmd`, `${NAME}`/`$NAME`, `$$`, `$!`; no `${NAME:-default}` (2.2.1) | confirmed | `core/resolve-config-value.ts:11-12,138-150` (no `:-` handling) |
| 12 | Tool name `mcp__<server>__<tool>`, `[A-Za-z0-9_-]`, 64 chars, 55 + `_` + 8 hex sha256; 20 KiB middle cut with spill file (2.2.7) | confirmed | `extensions/mcp/tools.ts:42-45,74-89,120-141`; prototype `test_stdio.R` re-run |
| 13 | Streamable HTTP headers, 202/204 handling, 405 on GET, error body 8 KiB/500 chars, reconnect 1000 ms ×2 max 30 000 ms, 5 retries (2.2.5, 3.6) | confirmed | `transports/streamable-http.ts:14-18,156-163,223-262,303-311,432-440` |
| 14 | Pi PKCE refuses only when methods are advertised without S256 (2.2.6) | **corrected** (clarified) | `oauth/flow.ts:147-152`: absent `code_challenge_methods_supported` is accepted, contrary to the spec's "MUST refuse to proceed" (https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization) |
| 15 | OAuth constants: callback 127.0.0.1 `/callback` 5 min; refresh skew 30 s, request 15 s, lock 20/25 s/100 ms (2.2.6, 3.6) | confirmed | `oauth/callback.ts:62-80`; `extensions/mcp/oauth.ts:38-45` |
| 16 | `tool_search`: BM25 k1 1.2, b 0.75, limit 8, 21 stop words, searchable = `codemode`/`deferred` inactive tools, `model-only`, registered inactive, answer texts (2.3, 3.6) | confirmed | `tool-search/tool.ts:20-21,39-156,158-163,190-213,243,255-267`; `tool-search/index.ts:12-16` |
| 17 | BM25 base-R port matches the reference to 1e-12 (1.8, 5.7) | confirmed | re-ran `test_bm25.R` (Node 26.8.2): PASS; `bm25_ref.mjs` compared line by line with `tool.ts:39-156` |
| 18 | Codemode constants: 3000-token declaration budget, 10 000-token output budget, 256 MiB heap, 300 000 ms library deadline, `quickjs-wasi` 3.6.2, store 256 Ki/1 Mi, 4 classifier calls, `model-only`, 16 000 chars / 32 `$ref` (2.4, 3.6) | confirmed | `codemode/tool.ts:139-154,223,428`; `codemode/execute.ts:42,48,130,142,311`; `packages/codemode/package.json:58`; `runtime/host.ts:22`; `declarations.ts:10-12`; `prelude-source.ts:28-29`; `nested-tool-calls.ts:27-30` |
| 19 | MCP spec quotations (stdio framing, Accept header, 202, both response types, `MCP-Session-Id`, 404 re-init, DELETE/405, `MCP-Protocol-Version`, `Last-Event-ID`, `retry`, tool names 1-128 chars `A-Za-z0-9_-.`, `resource` in both requests, S256, no tokens in query string, registration priority, DCR as backwards compatibility, stdio shutdown sequence) (3.5, 7.3) | confirmed | spec 2025-11-25 pages transports, lifecycle, authorization, tools (fetched 2026-09-29) |
| 20 | Claude Code sub-agent frontmatter, recursive scan, walk-up, depth 3, concurrency 20 (3.1) | confirmed, supplemented | https://code.claude.com/docs/en/sub-agents (adds `experimental`, `manual` alias, the two env vars) |
| 21 | Claude Code MCP: `timeout` in ms, values < 1000 ignored, `${VAR}`/`${VAR:-default}` fields, `headersHelper`, types incl. `ws` and `streamable-http` alias, `~/.claude.json` scopes, `ENABLE_TOOL_SEARCH=false` (2.3, 3.4) | confirmed | https://code.claude.com/docs/en/mcp |
| 22 | Codex keys and defaults `startup_timeout_sec` 10, `tool_timeout_sec` 60, project `.codex/config.toml` trusted only (3.4) | confirmed | https://learn.chatgpt.com/docs/extend/mcp?surface=cli (also lists `experimental_environment`, `http_headers_helper`, `required`, `default_tools_approval_mode`, not in the table) |
| 23 | Cursor `${env:VAR}` "from memory, UNCERTAIN" (3.4) | **corrected** (upgraded to verified) | https://cursor.com/docs/mcp |
| 24 | mcptools 1.0.3 (2026-09-18) imports ellmer, nanonext, httpuv, promises; config `~/.config/mcptools/config.json` with `mcpServers`; returns ellmer tools (3.4, 4.1) | confirmed | CRAN page and refman; note it requires httr2 >= 1.2.3 |
| 25 | `httr2::resp_stream_sse()` drops empty-data events and ignores `retry` (1.12, 7.1) | confirmed, extended | `httr2:::parse_event` in 1.2.2 (installed) and in the 1.3.0 CRAN source; 1.3.0 NEWS: bare-CR change and `warn` deprecation |
| 26 | C-locale corruption shown as `<c3><a9>` from `cat()` (1.13, 7.1) | **corrected** | verifier scripts with `LC_ALL=C`: marked UTF-8 via `cat()`/`writeLines()` -> `<U+00E9>`; unmarked bytes via jsonlite -> `<c3><a9>`; `useBytes = TRUE`/`writeBin()` -> correct bytes; `dbg3.R` itself is not in the report |
| 27 | Non-ASCII in R code "must be written `…`, as in the prototype" (6.1) | **corrected** | `R CMD check` on a throw-away package: WARNING "Portable packages must use only ASCII characters in their R code"; prototype code in 5.1, 5.3 and 5.8 changed to backslash-u escapes and re-run (27/27, 23/23 in C and UTF-8 locales) |
| 28 | `callr::r_bg()` accepts `stdin = "|"`, `wd`, `cleanup_tree` (via `...`), round trip works; `r_session` output and interrupt (4.2.4, 5.9) | confirmed, supplemented | verifier script with callr 3.7.6 and 3.8.0; interrupt 0.06 s, error class `callr_timeout_error`; `package` default changed to `NULL` in 3.8.0 |
| 29 | Base R `serverSocket()` listens on all interfaces (1.19, 6.2) | confirmed | `args(serverSocket)` in R 4.4.3 is `function (port)`; `test_stream.R` re-run: `lsof` shows `*:<port>` |
| 30 | processx `interrupt()` is CTRL+BREAK on Windows; "Batch files" advice `cmd.exe /c call` (6.2) | confirmed (documentation only) | processx 3.8.6 `?process`; behaviour on Windows not run |
| 31 | Prototype pass counts 27 / 19 / 3 / 12 / 18 / 23 and abort by pid (1.11, 1.16, 1.17, section 5) | confirmed | all re-run: same counts in C locale, in `en_US.UTF-8`, and under httr2 1.3.0 / processx 3.9.0 / callr 3.8.0 |
| 32 | Backend timings (1.15, 4.2.3) | confirmed, ranges widened | re-run: r_bg 0.32/0.24 s, export 1.06 s, fork 0.13 s, four forks 2.24 s, r_session 0.11 s/0.01 s |
| 33 | `claude mcp serve` handshake: 2025-11-25, 29 tools (1.11, 5.3) | confirmed with a different count | re-run: OK, protocol 2025-11-25, 27 tools; `codex mcp-server` fails the same way ("stdin is not a terminal") |
| 34 | CRAN policy: at most two cores, `tools::R_user_dir()` for user files (6.1) | confirmed | https://cran.r-project.org/web/packages/policies.html |
| 35 | pi-subagents package page: background runs, seven built-in agents, `maxSubagentSpawnsPerRun` 64 (2.1.1) | confirmed (page only) | https://pi.dev/packages/pi-subagents |
| 36 | Durable/protocol README facts: `requestId`, `replay: "safe"`, 100 ms commits, 100 frames, SQLite WAL + `synchronous = NORMAL`; protocol version 8, CBOR, 16 MiB, 1 000 000 entries, 64 levels; coordinator protocol 3, 10 s start, 30 s/250 ms grace (2.5) | confirmed | `durable/README.md:106-111,149,203-205,360`; `protocol/README.md:5,21,41`; `coordinator.ts:14-16,263-264` |

Not verified (left as labelled in the report): all Windows behaviour in 6.2 (`.cmd` shims, CTRL+BREAK handling, `kill_tree()`, `Sys.chmod()`, `browseURL()` via `shell.exec()`); Claude Desktop config paths (LIKELY) and the Linux path (UNCERTAIN); fork safety inside RStudio/Positron; behaviour against real OAuth providers and third-party MCP servers; curl 8.0.0 and openssl 2.4.2 (current CRAN) with the prototypes.

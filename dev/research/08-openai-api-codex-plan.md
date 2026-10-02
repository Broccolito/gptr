# Track 08: OpenAI APIs and ChatGPT plan usage through Codex

- Date: 2026-09-30 (research session started 2026-09-29 local time).
- Requirements covered: REQ-11 (native OpenAI and OpenAI-compatible providers), REQ-12 (ChatGPT plan via Codex), plus REQ-01/02/03, REQ-21/22 (in-memory tools), REQ-30 (MCP), REQ-32 (CLI sub-agents), REQ-37/38 (permissions, interrupt/steer).
- Environment: macOS (Darwin 25.6, arm64), R 4.4.3 run as `Rscript --vanilla` (locale `C`, because `LANG` is unset in this shell), httr2 1.2.2, processx 3.8.6, jsonlite 2.0.0, curl 7.0.0, httpuv 1.6.17, openssl 2.3.5, callr 3.7.6. jose 1.2.1 was installed into the private scratch library only. (Verification, 2026-09-29: CRAN sources are newer, namely httr2 1.3.0, processx 3.9.0, jose 2.0.0, openssl 2.4.2 and callr 3.8.0. The binary install on this R 4.4.3 still fetched httr2 1.2.2, processx 3.8.6 and jose 1.2.1. The transport test and the jose calls used here were re-run on httr2 1.3.0 and jose 2.0.0 with identical results.)
- External versions: Codex CLI `codex-cli 0.157.0` (Homebrew/npm install at `/opt/homebrew/bin/codex`), openai/codex `main` at `2cc65cdd4c7c167f0c7252fcb5165d649c16aca0` (committed 2026-09-30T01:35:21Z), Pi clone at `1b347794` (2026-09-29), openai/sign-in-with-chatgpt-devkit `main` (last pushed 2026-09-29T16:09:24Z).
- Documentation: fetched 2026-09-30 01:32 UTC as Markdown twins from `developers.openai.com` (API, Sign in with ChatGPT, cookbook) and `learn.chatgpt.com` (Codex docs, which moved there from `developers.openai.com/codex`). Byte sizes match the previous researcher's snapshots, which confirms the pages did not change during the session.
- Model calls: 3 tiny real Codex calls through the user's existing ChatGPT (Pro) login in Codex: 2 × `codex exec --json` and 1 × `codex app-server` turn. No paid OpenAI API call was made. Every other experiment ran offline, against local mock servers, or against Codex app-server methods that do not call a model.
- Prior work: a previous researcher left raw material in `.../scratchpad/work/track08/` (doc snapshots, app-server schema dumps, an app-server client, an R MCP stdio server) but no report. I re-fetched the docs and source files and compared them byte for byte (identical), regenerated the app-server JSON Schema with the installed CLI (identical), and re-ran the handshake script. Everything in this report was re-verified or is labelled otherwise.
- Evidence labels: **VERIFIED** means I saw the evidence myself (file:line, URL, or an executed command and its output). **LIKELY** means strongly implied by the evidence but not directly executed. **UNCERTAIN** means inferred or not checkable here.
- Scratch paths below are relative to `/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/` (abbreviated `T08/`). That directory is temporary, so section 5 embeds every prototype and its output.

---

## 1. Executive summary

1. **OpenAI now officially supports using a ChatGPT plan from open-source, locally run apps.** The programme is "Sign in with ChatGPT → ChatGPT plan usage" and is in preview. An app registers itself during an OAuth flow with a public client (`client_id=dynamic_agent_client`, PKCE S256, no client secret), requests the scope `chatgpt.tokens.use.direct`, and then calls the **public** `POST https://api.openai.com/v1/responses` with the user's access token, `store:false` and `stream:true`. Access tokens last 1 h; refresh tokens last 30 days and rotate on every refresh. OpenAI states this is available to "open-source projects, personal projects that run locally, and selected private apps". gptr (MIT, CRAN, local) qualifies. VERIFIED from docs (§3.8).
2. **This makes REQ-12 (ChatGPT side) achievable in pure R with gptr's own agent loop and in-memory R tools.** The same `openai-responses` adapter serves both API-key and plan usage; plan mode only adds a request filter. I built and verified every building block offline: PKCE (cross-checked against the `openssl` CLI), the authorize URL, a 127.0.0.1 loopback callback served by httpuv, the exact token-exchange and refresh request bodies (`req_dry_run`), the live OpenAI JWKS, RS256 ID-token validation logic, and an atomic 0600 credential file. **Not run:** a real end-to-end sign-in, because it needs the user's browser consent.
3. **OpenAI's position on third-party use of Codex auth is explicit.** The Codex app-server docs say app-server authentication "has never been permitted for commercial or hosted services". They allow existing local and open-source apps to keep using it but "recommend migrating to Sign in with ChatGPT". Pi's `openai-codex` provider is labelled "OpenAI Codex (legacy)" in its own source. It calls `chatgpt.com/backend-api/codex/responses` with the Codex CLI's OAuth client id and `originator` header, which impersonates the Codex CLI. **Do not port it.** VERIFIED.
4. **`codex mcp-server` has been removed.** Both the docs and CLI 0.157.0 confirm this, which answers track 06's open question. Codex offers two integration surfaces:
   - `codex exec --json`: the documented automation path.
   - `codex app-server`: JSON-RPC 2.0 over stdio JSONL. It is labelled "experimental" but is used by the official Python SDK, which ships as a stable release.
5. **Live `codex exec --json` from R (processx) works.** The event schema is `thread.started` → `turn.started` → `item.started`/`item.completed` (items `command_execution`, `mcp_tool_call`, `agent_message`, …) → `turn.completed{usage}`. An R MCP stdio server was attached purely through `-c mcp_servers.<id>.*` overrides, with no edit to `~/.codex/config.toml`. `--output-schema` returned schema-valid JSON. VERIFIED (§5.2).
6. **Codex is a heavy agent.** A trivial `exec` turn consumed **38,544 input tokens** (30,208 cached). The trivial app-server turn consumed 19,324. Codex brings its own system prompt, shell tool, sandbox and approvals. As a delegate agent it is excellent; as a "model" behind gptr's own loop it is the wrong tool.
7. **Richest R integration: app-server with *dynamic tools* (experimental).**
   - `thread/start{dynamicTools:[…]}` makes Codex send an `item/tool/call` JSON-RPC **request** back over the same pipe, and the live R session answers it.
   - VERIFIED live: the model called `r_eval("nrow(big_df)")` and R answered `[1] 123457` from an object that existed only in the parent session.
   - Approvals arrive as server requests (`item/commandExecution/requestApproval`, `item/fileChange/requestApproval`), which map directly onto gptr permission modes (REQ-37).
   - `turn/steer` and `turn/interrupt` give REQ-38.
   - `model/list`, `account/read` and `account/rateLimits/read` feed the UI (verified: Pro plan, weekly window 10,080 min, 45 % used).
8. **Verified: an MCP server hosted inside the same R session over streamable HTTP.** httpuv serves it and the R loop pumps it while waiting on Codex. `codex app-server` listed its tools and executed `r_eval` in the live environment, with **no model call** (§5.5). The same bridge should also serve `codex exec` (same `-c mcp_servers.<id>.url` key) and `claude -p` (`--mcp-config`), so the Claude and Codex routes can share one "external CLI agent" adapter; LIKELY, because only the app-server path was run. This answers D-14 and the open question on digest line 205.
9. **Responses API facts to build against** (current docs):
   - `reasoning.effort` ∈ `none|minimal|low|medium|high|xhigh|max`, and support is model-dependent.
   - `reasoning.summary` ∈ `auto|concise|detailed`.
   - `reasoning.context` ∈ `auto|current_turn|all_turns`.
   - With `store:false`, reasoning items carry `encrypted_content` **by default**. `include:["reasoning.encrypted_content"]` is now optional legacy.
   - Assistant messages carry `phase` (`commentary`/`final_answer`), which **must be preserved on replay**.
   - `prompt_cache_options{ttl:"30m",mode}` replaces the deprecated `prompt_cache_retention`.
   - New input/tool features: `namespace` tools, `configuration_update` input items (change effort mid-conversation), and server-side compaction via `context_management`.
10. **Current flagship models** (docs, 2026-09-30):

    | Model | Input / 1M | Cached / 1M | Cache write / 1M | Output / 1M |
    |---|---|---|---|---|
    | `gpt-6-astra` | $10 | $1 | $12.50 | $50 |
    | `gpt-6.1-sol` | $2 | $0.10 | $2.50 | $10 |
    | `gpt-6-sol` | $2 | $0.20 | $2.50 | $10 |
    | `gpt-6-luna` | $0.10 | $0.01 | $0.125 | $0.50 |

    - All four have a 1,050,000-token context window, 922,000 max input and 128,000 max output. Requests with more than 272K input tokens cost 2× input and cache and 1.5× output.
    - Astra and 6.1 Sol reject effort `none`. Their tool calling needs Responses: Chat Completions tools are unsupported for them, and 6 Sol/Luna allow Chat tools only with effort `none`.
11. **Chat Completions is still the lingua franca for OpenAI-compatible servers.** It streams data-only SSE ending with `data: [DONE]`. `tool_calls` deltas are keyed by `index`. `stream_options.include_usage` adds a final chunk with empty `choices`. VERIFIED with a fixture and a local mock server.
12. **Four R pitfalls found, all verified here and all silent data corruption or crashes:**
    - (a) processx with its default `encoding = ""` **drops non-ASCII bytes** from child stdout in a C locale. Always pass `encoding = "UTF-8"`.
    - (b) `jsonlite::fromJSON()` on *unmarked* UTF-8 text in a C locale turns `é` into the literal text `<c3><a9>`. Always set `Encoding(x) <- "UTF-8"` first on text built from raw bytes or pipes. (Correction from verification: `httr2::resp_stream_sse()` in httr2 1.2.2 and 1.3.0 already returns `data` marked UTF-8, so re-marking it is only defensive.)
    - (c) `$` does partial matching: `msg$params$item` matched `itemId` and crashed the live app-server run. Use `[[` everywhere.
    - (d) `processx::process$write_input()` is **non-blocking**: it writes what fits in the pipe (8 KB on macOS) and returns the unwritten bytes as a raw vector. Ignoring the return value silently truncated a 50 KB prompt to about 8 KB (found during verification). Loop until nothing is left (`proc_write_all()` in §5.1).
13. **Recommended architecture:**
    - Provider `openai` is native Responses, authenticated by API key **or** a ChatGPT plan (Sign in with ChatGPT, SIWC). It is the default ChatGPT-plan route.
    - Provider `openai_compatible` is native Chat Completions.
    - Provider `codex` is an *external agent* behind a shared `ext_agent` adapter. The default driver is app-server; `exec` is the fallback and is used for fire-and-forget parallel delegation. Claude Code plugs into the same adapter (`claude -p --input-format stream-json --output-format stream-json`), and tools reach both CLIs through the in-session HTTP MCP bridge.
14. **Packages.**
    - Imports: `httr2`, `jsonlite`, `processx`, `openssl` (already a hard dependency of httr2).
    - Suggests: `httpuv` (OAuth callback and MCP bridge; shiny already depends on it) and `jose` (ID-token signature verification, CRAN, pure openssl).
    - No Node or Python dependency. The Codex CLI is an optional external program, detected at runtime.
15. **ChatGPT-plan (SIWC) request constraints:**
    - Omit `temperature`, `max_output_tokens`, `truncation`, `metadata`, `top_p`, `top_logprobs`, `safety_identifier`, `prompt_cache_retention`, `background`, `conversation`, `max_tool_calls`, `moderation`, `multi_agent`, `prompt` and `user`.
    - Send `input` as an array. No `previous_response_id` over HTTP.
    - No `role:"system"` items.
    - Group function/custom tools in namespaces or send them through `additional_tools`.
    - Unsupported tools: image generation, file search, Code Interpreter, native computer use, hosted MCP/connectors and Responses `tool_search`. `programmatic_tool_calling` is not accepted in top-level `tools`. Web search "remains subject to model and account/workspace policy" (so it is not blanket-forbidden).
    - `subscription_sharing_usage_limit_exceeded` (429) or `subscription_sharing_usage_unavailable` (503) can arrive **mid-stream** as `response.failed`.
    - Plus users share one 5-hour limit across all apps; Pro users have no 5-hour limit.
16. **CRAN:** every network or subprocess path is testable offline. I verified fixtures, a callr-hosted mock SSE server, a fake-`codex` executable, and app-server methods that make no model call. Credentials go only under `tools::R_user_dir("gptr", "config")` after explicit login. No browser is launched in non-interactive sessions.
17. **Windows** (not run here; LIKELY):
    - Resolve the native `codex.exe` rather than the npm `codex.cmd` shim.
    - Always pass the prompt on stdin (`codex exec -`), never in argv.
    - Use TOML literal strings (`'C:/...'`) for paths in `-c` overrides.
    - Use CRLF/CR-tolerant parsers. The SSE parser is verified with LF, CRLF and CR-only framing.
    - Codex's native Windows sandbox (`[windows] sandbox = "elevated"|"unelevated"`) needs setup.

---

## 2. Findings

### 2.A OpenAI Responses API (native HTTP)

- **Endpoint and auth.** VERIFIED: `ref_responses_create.md` line 5 reads **post** `/responses`, and API reference overview line 33 reads `Authorization: Bearer OPENAI_API_KEY_OR_ACCESS_TOKEN`.
  - Base URL: `https://api.openai.com/v1`.
  - `Authorization: Bearer <API key or OAuth access token>`.
  - Optional request headers: `OpenAI-Organization` and `OpenAI-Project`.
  - `X-Client-Request-Id`: ASCII, at most 512 chars, otherwise the request fails with 400.
  - Response headers: `x-request-id`, `openai-processing-ms`, `openai-version` (currently `2020-10-01`), `openai-organization`.
- **Body parameters (full list).** VERIFIED from the reference body section (§3.1): `access_programs, background, context_management, conversation, include, input, instructions, max_output_tokens, max_tool_calls, metadata, model, moderation, parallel_tool_calls, previous_response_id, prompt, prompt_cache_key, prompt_cache_options, prompt_cache_retention (deprecated), reasoning, safety_identifier, service_tier, store, stream, stream_options, temperature, text, tool_choice, tools, top_logprobs, top_p, truncation, user`.
- **`store` defaults to true.** VERIFIED: stored responses are kept at least 30 days. gptr should always send `store:false`, because the script is the history (REQ-24) and plan mode requires it.
- **Stateless replay.** VERIFIED from the reasoning guide:
  - With `store:false`, reasoning output items include `encrypted_content` by default. The legacy `include: ["reasoning.encrypted_content"]` is accepted but no longer required (`g_reasoning.md` lines 689–707).
  - When streaming, take the completed reasoning item from `response.output_item.done`. The `encrypted_content` in `response.output_item.added` may be incomplete (reference, Reasoning input item).
  - `reasoning.context`: the GPT-5.6 family defaults to `all_turns` (earlier reasoning is rendered into the next sample). GPT-6.1 Sol *supports* `all_turns`, but the docs do not state its default. Earlier models default to `current_turn`. The effective mode is echoed in `response.reasoning.context` (`g_reasoning.md` 506–526).
  - When model families switch, the API silently omits incompatible reasoning.
- **`phase` on assistant messages.** VERIFIED.
  - Values are `commentary` and `final_answer`. For "gpt-5.3-codex and beyond … preserve and resend phase on all assistant messages — dropping it can degrade performance" (EasyInputMessage `phase`).
  - The reasoning guide says missing `phase` can make preambles be treated as final answers.
- **Function calling.**
  - VERIFIED: tool definitions are flat (`{type:"function", name, description, parameters, strict}`), not nested under `function` as in Chat Completions.
  - VERIFIED: calls come back as output items `{type:"function_call", id:"fc_…", call_id:"call_…", name, arguments:"<json string>", namespace?}`. Results go back as input items `{type:"function_call_output", call_id, output: string | [input_text|input_image|input_file]}`.
  - VERIFIED: with `strict` omitted, **Responses tries to make the schema strict and falls back to non-strict**, while Chat Completions stays non-strict (function-calling guide, "Strict mode").
  - VERIFIED: strict schemas need `additionalProperties:false` on every object and every property listed in `required`. Optional fields use `type: [T, "null"]`.
- **New tool constructs.** VERIFIED:
  - `namespace` tools: `{type:"namespace", name, description, tools:[function|custom]}`.
  - `custom` tools with grammar formats.
  - `defer_loading` together with `tool_search` (gpt-5.4 and later).
  - `async` tools on GPT-6.
  - `additional_tools` input items, which add tools mid-conversation.
  - `configuration_update` input items, which change effort without breaking the cache prefix.
- **Compaction.** VERIFIED (`g_compaction.md`):
  - Server-side: `context_management:[{type:"compaction", compact_threshold:N}]` emits an encrypted `compaction` item in the stream. With stateless chaining, items before the latest compaction item can be dropped.
  - Standalone: `POST /responses/compact` returns a new window that must not be pruned.
- **Prompt caching.**
  - VERIFIED (corrected): `prompt_cache_key` groups requests for cache routing on older models. On GPT-5.6 and later "OpenAI handles cache routing automatically; the key is not needed to optimize caching". There the key only separates cache accounting (prompt-caching guide).
  - VERIFIED: `prompt_cache_options{mode:"implicit"|"explicit", ttl:"30m", prewarm, comparison_response_id}` applies to gpt-5.6 and later. Explicit breakpoints are `prompt_cache_breakpoint:{mode:"explicit"}` on content blocks, with up to 4 written per request.
  - VERIFIED: cache writes are billed at 1.25× input on the new models.
  - LIKELY: gptr can set `prompt_cache_key` to a stable session id (harmless, and useful on pre-5.6 models) and leave everything else default.
- **Streaming.** VERIFIED (§3.3):
  - SSE with `event: <type>` plus `data: <json>` lines. Every event carries `type` and `sequence_number`.
  - Terminal events are `response.completed`, `response.incomplete` (e.g. `incomplete_details.reason = "max_output_tokens"`; over WebSocket it can also be `"steered"`) and `response.failed` (`response.error{code,message}`). There is also a separate top-level `error` event `{code,message,param}`.
  - 58 distinct `response.*` event types are documented, and a client only needs to handle about 15 of them.

### 2.B Chat Completions (OpenAI-compatible lingua franca)

- `POST /chat/completions`. VERIFIED.
  - Messages use roles `developer|system|user|assistant|tool`. Tool results are `{role:"tool", tool_call_id, content}`.
  - Tools are `{type:"function", function:{name, description, parameters, strict}}`, and custom tools are also allowed.
  - `reasoning_effort` is a top-level string. Structured output uses `response_format:{type:"json_schema", json_schema:{name, schema, strict}}`.
  - `stream_options:{include_usage, include_obfuscation}`.
  - The stream is `data: {chat.completion.chunk}` lines ending with `data: [DONE]`. `delta.tool_calls[]` carries `index`, `id` (first chunk only), `function.name` and `function.arguments` fragments. `finish_reason` ∈ `stop|length|tool_calls|content_filter|function_call`.
  - With `include_usage`, a last chunk before `[DONE]` has `choices: []` and `usage`, and "if the stream is interrupted … you may not receive the final usage chunk".
- VERIFIED: Chat Completions on GPT-6 models is limited. Astra and 6.1 Sol support Chat Completions, but "tool calling requires Responses". 6 Sol and 6 Luna allow function calling on Chat only with `reasoning_effort:"none"` (latest-model guide). So gptr must use **Responses for OpenAI itself** and keep Chat Completions for third-party compatible servers.
- Compatibility quirks: Pi's `openai-completions` adapter carries flags such as `supportsDeveloperRole`, `supportsUsageInStreaming`, `supportsStrictMode`, `maxTokensField`, `thinkingFormat`, `requiresToolResultName` and `requiresAssistantAfterToolResult` (grep of `packages/ai/src/api/openai-completions.ts`). Track 03 covers these in depth. From this track: default `developer`→`system` downgrade for unknown servers, `max_completion_tokens` vs `max_tokens`, and treat a missing usage chunk as "unknown usage" rather than an error.

### 2.C Models, context sizes, pricing

VERIFIED from `developers.openai.com/api/docs/models/<id>.md` and `/api/docs/pricing.md` (§3.7 has the full table). Other points:

- Featured models are `gpt-6-astra` (flagship), `gpt-6.1-sol` (balanced) and `gpt-6-luna` (cheap and fast).
- Also current: `gpt-6-sol`, `gpt-5.6-sol/terra/luna`, `gpt-5.5`, `gpt-5.4` (and mini/nano), and `chat-latest`.
- Batch and Flex cost 50 % of standard. Fast mode (`service_tier:"fast"|"priority"`) costs 2×.
- Knowledge cutoffs: Astra and 6.1 Sol 2026-04-30; 6 Luna 2026-05-18.
- **Codex's catalog is different from the API catalog.** VERIFIED:
  - `codex debug models` and app-server `model/list` for this Pro account list `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol/terra/luna`, `gpt-5.5` (and hidden `gpt-reserve`, `codex-auto-review`). **`gpt-6.1-sol` is absent** even though the docs use it in examples ("requires access").
  - Codex reports `context_window` 272,000 (max 872,000, effective 95 %) and effort levels up to `ultra` for Astra/Sol ("Maximum reasoning with automatic task delegation").
  - **gptr must query the catalog at runtime rather than hard-code it.**

### 2.D Errors and rate limits

- VERIFIED (`g_errors.md`, `g_rate_limits.md`):
  - 401: invalid auth, wrong key, IP not allowlisted.
  - 403: unsupported region.
  - 429 codes: `credit_balance_exhausted`, `slow_down` (type `rate_limit_error`), `organization_spend_limit_exceeded`, `project_spend_limit_exceeded`, `organization_usage_limit_exceeded`, plus plain "Rate limit reached for requests".
  - 500 server error; 503 `server_is_overloaded` (type `service_unavailable_error`).
  - `Retry-After` may appear on 429 (temporary) and 503. Quota and billing errors must not be retried.
- Rate-limit headers (VERIFIED): `x-ratelimit-limit-requests`, `x-ratelimit-limit-tokens`, `x-ratelimit-remaining-requests`, `x-ratelimit-remaining-tokens`, `x-ratelimit-reset-requests` (e.g. `1s`), `x-ratelimit-reset-tokens` (e.g. `6m0s`), and the `-project-tokens` variants.
- Plan-mode errors (VERIFIED, SIWC errors page):
  - Before streaming, admission can return `{"detail": "..."}` with 401/403/503, which is not the standard error object.
  - Structured codes: `subscription_sharing_user_not_eligible` (403), `subscription_sharing_usage_limit_exceeded` (429), `subscription_sharing_usage_unavailable` (503), `subscription_sharing_unsupported_capability` (400, see `error.param`), `subscription_sharing_route_not_supported` (403), `subscription_sharing_invalid_user` (401), `chatpass_v2_scope_not_authorized` and `chatpass_v2_invalid_authorization_context` (403), `subscription_sharing_user_unavailable` (503).
  - "OpenAI does not silently switch the request to another billing path."

### 2.E Codex CLI, non-interactive (`codex exec`)

- VERIFIED (`codex exec --help`, captured in `T08/cli/exec_help.txt`):
  - Options: `-c/--config key=value` (TOML value), `--enable/--disable FEATURE`, `--strict-config`, `-i/--image`, `-m/--model`, `--oss`, `--local-provider`, `-p/--profile`, `-s/--sandbox read-only|workspace-write|danger-full-access`, `--approve-for-me`, `--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`, `-C/--cd`, `--worktree`, `--add-dir`, `--thread-source`, `--skip-git-repo-check`, `--ephemeral`, `--ignore-user-config`, `--ignore-rules`, `--output-schema FILE`, `--color`, `--json`, `-o/--output-last-message FILE`.
  - The prompt is an argument, or `-`/omitted to read stdin. With both stdin and a prompt, stdin is appended as a `<stdin>` block.
  - Subcommands: `resume [SESSION_ID] [PROMPT]` (with `--last` and `--all`), `fork`, `review`.
- **No `-a/--ask-for-approval` on `exec`.** Headless exec forces `approval_policy = Never`. VERIFIED in source: `codex-rs/exec/src/lib.rs` line 576 reads `approval_policy: Some(AskForApproval::Never)` with the comment "Default to never ask for approvals in headless mode. Rebuild below if the fully resolved reviewer is AutoReview". Approvals are therefore not interactive in exec. Permissions come from `--sandbox`, except that `--approve-for-me` "route[s] approval requests through automatic review using the workspace-write sandbox" (exec `--help`), so an automatic reviewer rather than a human can approve.
- `--ignore-user-config` makes exec skip `$CODEX_HOME/config.toml` while "auth still uses `CODEX_HOME`" (exec `--help`; non-interactive doc). This is the clean way to keep the user's own MCP servers and settings out of a gptr-driven exec run without moving the login. VERIFIED (help text and docs; not run). `exec resume` accepts it too.
- Defaults: exec runs in a read-only sandbox (non-interactive doc). It refuses to run outside a git repo unless `--skip-git-repo-check` is given. `--full-auto` is deprecated. VERIFIED.
- JSONL events (`--json`). VERIFIED from source `codex-rs/exec/src/exec_events.rs` and from the live calls:
  - Event types: `thread.started{thread_id}`, `turn.started{}`, `turn.completed{usage}`, `turn.failed{error{message}}`, `item.started|item.updated|item.completed{item}` and `error{message}`.
  - Item types: `agent_message`, `reasoning`, `command_execution`, `file_change`, `mcp_tool_call`, `collab_tool_call`, `web_search`, `todo_list`, `error`.
  - `usage` = `{input_tokens, cached_input_tokens, cache_write_input_tokens, output_tokens, reasoning_output_tokens}`.
  - The schema is in §3.9.
- Live timings (call 1): the first event arrived after 1.1 s and the whole trivial turn took 7.0 s. Exit status 0. `stderr` was empty with `--json`, and `-o` wrote `pong`. VERIFIED.
- `codex login status` prints "Logged in using ChatGPT" and never prints tokens. `codex login --with-api-key` and `--with-access-token` read from stdin; `--device-auth` gives headless login. VERIFIED (`--help` and a run piped through an email-redacting filter).

### 2.F Codex app-server (JSON-RPC)

- VERIFIED (`learn.chatgpt.com/docs/app-server.md`, the schema generated by `codex app-server generate-json-schema --experimental`, and live runs):
  - Transport `--listen stdio://` (default) sends newline-delimited JSON. Messages are JSON-RPC 2.0 **without** the `"jsonrpc"` field.
  - Other transports: `ws://IP:PORT` (experimental, with health probes `/readyz` and `/healthz`) and `unix://`.
  - The client must send `initialize{clientInfo{name,title,version}, capabilities{experimentalApi?, optOutNotificationMethods?, …}}` and then the `initialized` notification.
  - The response contains `userAgent` (observed: `gptr/0.157.0 (Mac OS 26.6.2; arm64) unknown (gptr; 0.0.0.9000)`, so `clientInfo.name` becomes the originator), `codexHome`, `platformFamily` and `platformOs`.
- Core flow:
  1. `thread/start{model, cwd, approvalPolicy, sandbox, ephemeral, baseInstructions, developerInstructions, dynamicTools, config, …}` returns `{thread{id,…}, model, modelProvider, cwd, approvalPolicy, sandbox, reasoningEffort, …}`.
  2. `turn/start{threadId, input:[{type:"text"|"image"|"localImage"|"audio"|"localAudio"|"skill"|"mention",…}], effort?, model?, summary?, outputSchema?, sandboxPolicy?, approvalPolicy?, cwd?, toolOutput?}` returns `{turn{id,status:"inProgress"}}`.
  3. Notifications follow: `turn/started`, `item/started`, `item/agentMessage/delta{delta}`, `item/reasoning/summaryTextDelta`, `item/completed`, `thread/tokenUsage/updated`, `account/rateLimits/updated`, then `turn/completed{turn{status: completed|interrupted|failed, error?}}`.
- Server→client **requests**, which need a reply with the same `id` (VERIFIED list from `ServerRequest.json`):
  - `item/commandExecution/requestApproval`
  - `item/fileChange/requestApproval`
  - `item/tool/requestUserInput`
  - `mcpServer/elicitation/request`
  - `item/permissions/requestApproval`
  - `item/tool/call` (dynamic tools)
  - `account/chatgptAuthTokens/refresh`
  - `attestation/generate`
  - `currentTime/read`
  - legacy `applyPatchApproval` and `execCommandApproval`
- **Dynamic tools** (experimental, needs `capabilities.experimentalApi=true`). VERIFIED live:
  - Spec: `{type:"function", name, description, inputSchema, deferLoading?}` or `{type:"namespace", name, description, tools:[…]}`.
  - The request params are `{threadId, turnId, callId, tool, namespace, arguments}`.
  - The response is `{contentItems:[{type:"inputText",text}|{type:"inputImage",imageUrl}|{type:"inputAudio",audioUrl}], success}`.
  - Codex persists `dynamicTools` in the rollout and restores them on `thread/resume` (docs line 555).
- **App-server loads the user's global Codex config** (`~/.codex/config.toml` and plugins). VERIFIED: the call-3 log shows it starting the user's MCP servers `openaiDeveloperDocs`, `codex_apps`, `node_repl`, `biookf` (failed), `cua_repl`. gptr should expect this. `codex app-server` 0.157.0 has no `--ignore-user-config` flag (VERIFIED, `codex app-server --help`), and a separate `CODEX_HOME` also moves the login, so per-server `-c mcp_servers.<name>.enabled=false` overrides are the only isolation found for app-server. For `codex exec`, use `--ignore-user-config` (§2.E).
- Other useful methods (VERIFIED in the schema):
  - Thread lifecycle: `thread/resume`, `thread/fork`, `thread/read`, `thread/list`, `thread/inject_items` (raw Responses items).
  - Turn control: `turn/steer{threadId, input, expectedTurnId}`, `turn/interrupt{threadId, turnId}`.
  - Discovery: `model/list`, `mcpServerStatus/list`, `mcpServer/tool/call`, `skills/list`.
  - Execution: `command/exec` (a sandboxed one-shot command without a turn).
  - Account: `account/read`, `account/login/start`, `account/rateLimits/read`, `account/usage/read`.
- Errors (VERIFIED in the schema):
  - The `error` notification is `{error:{message, codexErrorInfo?, additionalDetails?}, threadId, turnId, willRetry}`, and then the turn ends `failed`.
  - `codexErrorInfo` enum: `contextWindowExceeded|sessionBudgetExceeded|usageLimitExceeded|rateLimitExceeded|serverOverloaded|cyberPolicy|misalignmentPolicyViolation|internalServerError|unauthorized|badRequest|threadRollbackFailed|sandboxError|other`, plus object variants `httpConnectionFailed`, `responseStreamConnectionFailed`, `responseStreamDisconnected`, `responseTooManyFailedAttempts`, `activeTurnNotSteerable`. The prose docs use PascalCase; the generated schema's camelCase is authoritative.
- **Doc vs schema mismatch.** The docs' `thread/start` example uses `"sandbox":"workspaceWrite"` and another example uses `"approvalPolicy":"unlessTrusted"`. The generated schema for 0.157.0 uses `SandboxMode` = `read-only|workspace-write|danger-full-access` for `thread/start.sandbox` and `AskForApproval` = `untrusted|on-request|never|{granular:{…}}` for `approvalPolicy`. Careful: `turn/start.sandboxPolicy` is a *different* type, `SandboxPolicy`, an object whose `type` **is** camelCase (`readOnly|workspaceWrite|dangerFullAccess|externalSandbox`), so the docs' `"sandboxPolicy":{"type":"workspaceWrite"}` is correct. VERIFIED in the regenerated schema. Whether the server also accepts camelCase aliases for `sandbox` is untested. The config reference says `untrusted` is unsupported in config. **Rule for gptr:** generate the schema from the installed binary (`codex app-server generate-json-schema --out DIR`) in development and trust it over prose. Live runs used `approvalPolicy:"never"` and `sandbox:"read-only"` successfully. VERIFIED.

### 2.G Custom tools reaching Codex

Three verified routes:

1. **MCP stdio server** through `-c` overrides, with no config file edit (VERIFIED live, call 2):
   - `-c mcp_servers.gptr.command='<Rscript>'`
   - `-c mcp_servers.gptr.args=['--vanilla','<server.R>']`
   - `-c mcp_servers.gptr.default_tools_approval_mode="approve"`
   - `-c mcp_servers.gptr.required=true`

   The tool runs in a separate R process, so it cannot see the live session's objects unless it proxies back.
2. **MCP streamable-HTTP server inside the live R session.** It is served by httpuv and serviced by the same loop that pumps Codex's pipes. Config: `-c mcp_servers.gptr_live.url="http://127.0.0.1:<port>/mcp"`. VERIFIED with app-server `mcpServerStatus/list` and `mcpServer/tool/call` without a model call.
3. **App-server `dynamicTools`.** The tool call comes back on the same stdio pipe. VERIFIED live (call 3).

- MCP config keys (VERIFIED, config reference): `command, args, env, env_vars, cwd, url, auth (oauth|chatgpt), oauth.*, bearer_token_env_var, http_headers, http_headers_helper, env_http_headers, enabled, required, startup_timeout_sec (default 10), startup_timeout_ms, tool_timeout_sec (default 60), enabled_tools, disabled_tools, default_tools_approval_mode (auto|prompt|writes|approve), tools.<tool>.approval_mode, tools.<tool>.output_token_limit, scopes, oauth_resource`.
- `codex mcp add <name> -- <cmd…>` or `--url` *persists* to `~/.codex/config.toml`. gptr should prefer `-c` overrides, or `thread/start.config` for app-server, so the user's configuration is never modified.

### 2.H Codex login and `auth.json`

From source and docs only; I never read the local file.

- Storage: `$CODEX_HOME/auth.json`, default `~/.codex`, written with mode 0600. Alternatively the OS keyring under service `"Codex Auth"`, selected by `cli_auth_credentials_store = file|keyring|auto|ephemeral`. VERIFIED: `codex-rs/login/src/auth/storage.rs` lines 47–72, 162–163, 225, 243; auth doc "Credential storage".
- Shape (`AuthDotJson`): `{auth_mode?, "OPENAI_API_KEY": string|null, tokens?: {id_token (JWT string), access_token (JWT), refresh_token, account_id?}, last_refresh?: RFC3339, agent_identity?, personal_access_token?, bedrock_api_key?, bedrock_access_keys?}`. VERIFIED (`storage.rs` 49–72, `token_data.rs` 10–25). The ID-token claims Codex parses are `email`, `https://api.openai.com/profile`, and `https://api.openai.com/auth` (`chatgpt_plan_type`, `chatgpt_user_id`, `chatgpt_account_id`, …) (`token_data.rs` 27–80).
- Codex's own OAuth (VERIFIED: `codex-rs/login/src/auth/manager.rs` 203–216 and 1718; `server.rs` 77–78 and 594–610):
  - Issuer `https://auth.openai.com`, `/oauth/authorize`, `/oauth/token`.
  - `CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"`, callback port 1455, scope `openid profile email offline_access api.connectors.read api.connectors.invoke`.
  - Extra parameters: `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `originator`.
  - Refresh happens when `last_refresh` is older than 8 days.
  - Overrides: `CODEX_APP_SERVER_LOGIN_CLIENT_ID`, `CODEX_REFRESH_TOKEN_URL_OVERRIDE`.
- **gptr must never read, copy or refresh `~/.codex/auth.json`.** Codex's CI/CD doc says to let Codex refresh it and not to "call the refresh API yourself". gptr reuses the Codex login only by *running Codex*.

### 2.I Pi's two OpenAI subscription providers

- **`openai` + `openaiChatGPTOAuth`** (current). VERIFIED:
  - Source: `pi/packages/ai/src/providers/openai.ts` 1–24 and `auth/oauth/openai-chatgpt.ts` 1–310.
  - Implements SIWC: `DYNAMIC_CLIENT_ID = "dynamic_agent_client"`, `AGENT_NAME_HINT = "Pi"`, authorize `https://auth.openai.com/api/accounts/authorize`, token `.../api/accounts/oauth/token`, `RESOURCE = https://api.openai.com/v1`, `REDIRECT_URI = http://127.0.0.1:1455/auth/callback`, `SCOPE = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"`.
  - Host id is `urn:uuid:<device uuid>`. The expiry margin is 3 min.
  - It rejects grants that lack `chatgpt.tokens.use.direct`. The refresh body has no `scope`.
  - The request side (`api/openai-responses.ts` 36–47 and 328–346) treats a non-`sk-` key sent to `https://api.openai.com/v1` as a SIWC token and then drops `prompt_cache_retention`, `prompt_cache_options`, `max_output_tokens` and `temperature`. It adds `https://chatgpt.com/settings/usage` to `subscription_sharing_usage_limit_exceeded` errors (lines 226–229).
  - It sends `store:false` and puts function tools **at top level**, not in namespaces. See the risk in §7.
- **`openai-codex`** ("OpenAI Codex (legacy)"). VERIFIED: `providers/openai-codex.ts` 7–21, `api/openai-codex-responses.ts` 52–60, 527–600, 641–654, 1596–1697, and `auth/oauth/openai-codex.ts` 22–35 and 289–308.
  - Base URL `https://chatgpt.com/backend-api`, POSTing to `/codex/responses`.
  - Headers: `Authorization: Bearer <ChatGPT access JWT>`, `chatgpt-account-id: <JWT claim https://api.openai.com/auth.chatgpt_account_id>`, `originator: pi`, `User-Agent`, `OpenAI-Beta: responses=experimental`, `accept: text/event-stream`, `session-id` / `x-client-request-id`.
  - Optional `content-encoding: zstd` body. WebSocket transport uses `OpenAI-Beta: responses_websockets=2026-02-06`.
  - Body: `store:false, stream:true, instructions` (defaults to `"You are a helpful assistant."` when there is no system prompt), `text.verbosity` (default `"low"`), `include:["reasoning.encrypted_content"]`, `prompt_cache_key`, `tool_choice:"auto"`, `parallel_tool_calls:true`.
  - OAuth uses the **Codex CLI's** client id `app_EMoamEEZ73f0CkXaXp7hrann` with `codex_cli_simplified_flow`. Device code goes through `/api/accounts/deviceauth/usercode` and `/deviceauth/token`.
  - Error mapping looks for `usage_limit_reached|usage_not_included|rate_limit_exceeded` and `resets_at`.
  - **Assessment:** this client-impersonation path should not be ported (D-15, digest line 188).

### 2.J Sign in with ChatGPT for open-source apps (the sanctioned plan route)

- VERIFIED throughout (`developers.openai.com/siwc/...`, fetched 2026-09-30; full spec in §3.8). Main points:
  - Register on the first sign-in with `dynamic_agent_client`. Save the **issued** `client_id` (e.g. `oaiapp_…`) from the callback and reuse it later.
  - Send a per-host `ext_agent_host_id`, chosen before the first sign-in and persisted. Formats: `urn:uuid:<v4>` (supported), `urn:ietf:params:oauth:jwk-thumbprint:…` (recommended), or `did:key:…`.
  - Send `agent_name_hint` (the app's real name, first registration only). App-server's `clientInfo.name` should match it.
- Callback rules:
  - The redirect must be exactly `http://127.0.0.1:<port>/auth/callback`. Only the port may vary between sign-ins; never use `localhost`.
  - The listener must start before the browser opens.
  - Reject callbacks with a different `client_id` on re-authorisation. On re-authorisation the callback "may omit `client_id`"; then keep the saved issued id for the exchange (sign-in doc, step 3). The §5.8 prototype returns `q$client_id` as is, so it must fall back to the saved id.
- Validation and storage:
  - Validate the ID token (RS256, JWKS at `https://auth.openai.com/.well-known/jwks.json`; `iss`, `aud` = issued client id, `exp`, `nonce`).
  - Check that the granted scopes include `chatgpt.tokens.use.direct`.
  - Store one credential record per issued client id: atomic write, 0600, never logged.
- Refresh, sign-out and usage:
  - Refresh near expiry with `grant_type=refresh_token`, the issued client id, the refresh token and `resource`, **without `scope`**. The refresh token rotates; serialise refreshes.
  - Sign-out revokes the refresh token at `https://auth.openai.com/api/accounts/oauth/revoke` (VERIFIED live via the discovery document).
  - Model list: `GET https://api.openai.com/v1/models` with the OAuth token returns `{models:[{slug, display_name, visibility, …}]}`. This is not the API-key list shape. Keep `visibility=="list"` entries and preserve server order.
  - UI duties: first-sign-in notice "You're using your ChatGPT plan", "Using ChatGPT plan" beside the model picker, and a "Manage usage" link to `https://chatgpt.com/settings/usage`.
- Codex app-server with a SIWC token (VERIFIED from the doc; not run). Start app-server with:
  - `-c model_provider="openai_chatgpt_plan"`
  - `-c model_providers.openai_chatgpt_plan.base_url="https://api.openai.com/v1"`
  - `-c model_providers.openai_chatgpt_plan.env_key="ACCESS_TOKEN"`
  - `wire_api="responses"`, `requires_openai_auth=false`, `supports_websockets=false`

  Then run the child with the token in its `ACCESS_TOKEN` environment variable. On expiry, restart app-server and use `thread/resume`. LIKELY alternative that avoids restarts: `model_providers.<id>.auth.command`/`args`/`timeout_ms` (default 5000)/`refresh_interval_ms` (default 300000), a command-backed bearer token documented in the config reference (the command prints the token to stdout). The config reference says "Do not combine with `env_key`, `experimental_bearer_token`, or `requires_openai_auth`", so it replaces the `env_key` and `requires_openai_auth` lines above rather than adding to them. This is a general Codex feature and is not mentioned on the SIWC page. UNCERTAIN whether OpenAI endorses it for SIWC.
- Official reference implementation: `openai/sign-in-with-chatgpt-devkit` (`packages/local/src/{oauth,responses,models}.ts`). VERIFIED details:
  - A redirect port of `0` selects any free port.
  - The ID token is checked with a 5-second clock tolerance.
  - A refresh may omit `scope` in the response.
  - Responses are streamed with the same minimal body `{model, input, instructions?, store:false, stream:true}`.
  - The direct route "can return valid SSE without Content-Type", so do not require the header.
  - Success requires `response.completed`, and anything else is an error or an interruption.
  - The SSE parser accepts LF, CRLF and CR.

### 2.K Terms and policy for third-party harnesses

- **SIWC, open-source local apps:** explicitly allowed. "ChatGPT plan usage is available to all open-source partners and selected private clients" (SIWC quickstart). The cookbook says it is "available for open-source tools and personal projects that run locally. If you're building a paid or remotely hosted app, join the waitlist". VERIFIED.
- **Codex app-server auth:** allowed for local/open-source apps but "never been permitted for commercial or hosted services", with SIWC recommended instead (app-server.md line 1914). VERIFIED.
- **General Terms of Use:** they reportedly prohibit "automatically or programmatically extract[ing] data or Output" and sharing account credentials. LIKELY: this comes from search-result snippets only, because `openai.com/policies` returned HTTP 403 to automated fetches. SIWC and the official Codex CLI are the sanctioned programmatic channels. A GitHub discussion (openai/codex #8338) confirms forks of the Apache-licensed CLI are fine but leaves ToS questions about commercial bring-your-own-subscription unanswered as of 2026-08-27. VERIFIED (fetched summary).
- **Consequences for gptr:**
  1. Use SIWC with `agent_name_hint="gptr"` and app-server `clientInfo.name="gptr"`.
  2. Never impersonate the Codex CLI or read its tokens.
  3. Show the required SIWC UX elements.
  4. Document that plan usage is for the user's own local use.

---

## 3. Exact specifications

### 3.1 Responses API: request

```
POST https://api.openai.com/v1/responses
Authorization: Bearer <OPENAI_API_KEY | SIWC access token>
Content-Type: application/json
Accept: text/event-stream            (when stream=true)
X-Client-Request-Id: <ascii, <=512>  (optional; must be unique per request, e.g. <turn id>-<request n>)
OpenAI-Organization / OpenAI-Project (optional, API-key mode)
```

Body fields for gptr, with type notes. VERIFIED against the reference; the omitted fields are not needed in v1.

| field | type / values | gptr usage |
|---|---|---|
| `model` | string | required |
| `input` | string or array of items (§3.2) | always an array (stateless) |
| `instructions` | string | the system prompt; in plan mode the only system channel besides developer items |
| `tools` | array: `function`, `custom`, `namespace`, hosted tools | gptr tools; namespaced in plan mode |
| `tool_choice` | `"none"`, `"auto"`, `"required"`, `{type:"function",name}`, `{type:"allowed_tools",mode,tools}`, `{type:"custom",name}`, … | default auto |
| `parallel_tool_calls` | bool | TRUE (gptr executes sequentially unless parallel-safe) |
| `reasoning` | `{effort, summary, context, mode}` | effort from the model setting; `summary:"auto"` when the user wants thinking shown |
| `text` | `{format:{type:"text"}` or `{type:"json_schema",name,schema,strict,description}` or `{type:"json_object"}`, `verbosity:"low"|"medium"|"high"}` | structured output (System-1-like extraction) |
| `store` | bool (default **true**) | always FALSE |
| `stream` | bool | TRUE |
| `stream_options` | `{include_obfuscation}` | optional FALSE on trusted networks |
| `include` | array, incl. `"reasoning.encrypted_content"` | optional (encrypted reasoning is returned by default when store=false) |
| `previous_response_id` | string | not used (stateless; forbidden in plan mode) |
| `prompt_cache_key` | string | stable session id |
| `prompt_cache_options` | `{mode:"implicit"|"explicit", ttl:"30m", prewarm, comparison_response_id}` | leave default |
| `max_output_tokens` | int (≥16 per Pi #6265) | API-key mode only |
| `temperature`, `top_p`, `top_logprobs` | numbers | API-key mode and non-reasoning effort only |
| `truncation` | `"auto"|"disabled"` (default disabled → 400 on overflow) | not used; gptr compacts itself |
| `service_tier` | `auto|default|flex|scale|priority|fast|ultrafast` | optional user option |
| `context_management` | `[{type:"compaction", compact_threshold}]` | optional server compaction (API-key mode) |
| `safety_identifier` | ≤64 chars | optional (hash); API-key mode |

**ChatGPT-plan mode filter** (SIWC "Preview limitations"): force `store=false` and `stream=true`, and remove `background, conversation, max_output_tokens, max_tool_calls, metadata, moderation, multi_agent, prompt, prompt_cache_retention, safety_identifier, temperature, top_logprobs, top_p, truncation, user` and `previous_response_id`. Reject any `role:"system"` item and send `input` as an array. Group tools in `namespace`, or send them as an `additional_tools` item. Do not send image generation, file search, Code Interpreter, native computer use, hosted MCP/connectors or `tool_search`, and do not put `programmatic_tool_calling` in `tools`. Web search is subject to model and account policy. VERIFIED (doc); the field filter is implemented and tested in §5.7 (the tool restrictions are not implemented there).

### 3.2 Responses input and output item formats (verbatim shapes)

```json
{"role": "developer", "content": "R session: R 4.4.3; objects: big_df (data.frame 123457x2)"}
{"role": "user", "content": [{"type": "input_text", "text": "How many rows?"},
                             {"type": "input_image", "image_url": "data:image/png;base64,...", "detail": "auto"}]}
{"type": "message", "role": "assistant", "id": "msg_...", "phase": "commentary",
 "content": [{"type": "output_text", "text": "Checking the data frame.", "annotations": []}], "status": "completed"}
{"type": "reasoning", "id": "rs_...", "summary": [{"type": "summary_text", "text": "..."}],
 "encrypted_content": "gAAAA..."}
{"type": "function_call", "id": "fc_...", "call_id": "call_...", "name": "r_eval",
 "namespace": "gptr", "arguments": "{\"code\":\"nrow(big_df)\"}"}
{"type": "function_call_output", "call_id": "call_...", "output": "[1] 123457"}
{"type": "function_call_output", "call_id": "call_...",
 "output": [{"type": "input_text", "text": "plot attached"},
            {"type": "input_image", "image_url": "data:image/png;base64,..."}]}
{"type": "configuration_update", "reasoning": {"effort": "high"}}
{"type": "compaction", "encrypted_content": "..."}
{"type": "additional_tools", "role": "developer", "tools": [ ... ]}
```

Function and namespace tool definitions (VERIFIED, function-calling guide):

```json
{"type": "function", "name": "r_eval", "description": "Evaluate R code in the live session.",
 "parameters": {"type": "object", "properties": {"code": {"type": "string"}},
                "required": ["code"], "additionalProperties": false},
 "strict": true}
{"type": "namespace", "name": "gptr", "description": "Tools acting on the user's live R session.",
 "tools": [ {"type": "function", "name": "r_eval", "...": "..."} ]}
```

Output item types a client must handle: `message`, `reasoning`, `function_call`, `custom_tool_call` (`input` string), `compaction`, `web_search_call`, `tool_search_call` and `tool_search_output`, plus hosted-tool calls (ignore them unless enabled).

Structured Outputs limits (VERIFIED, `g_structured.md` 3576–3864):
- Supported types: string, number, boolean, integer, object, array, enum, anyOf.
- String keywords: `pattern`, `format` (date-time, time, date, duration, email, hostname, ipv4, ipv6, uuid). Number keywords: `multipleOf`, `maximum`, `exclusiveMaximum`, `minimum`, `exclusiveMinimum`. Array keywords: `minItems`, `maxItems`.
- Unsupported: `allOf`, `not`, `if/then/else`, `dependent*`.
- The root must be an object, not anyOf. Every field is required. `additionalProperties:false` is mandatory.
- Size limits: ≤5000 properties, ≤10 nesting levels, ≤120,000 characters across names and enum values, ≤1000 enum values (≤15,000 characters for one enum with more than 250 values).
- `$defs` and recursion are supported.

### 3.3 Responses streaming (SSE)

Wire framing:

```
event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_123","output_index":0,"content_index":0,"delta":"In","sequence_number":1,"logprobs":[]}

```

Events gptr must handle (VERIFIED names and fields from the reference; examples are verbatim from the docs):

| event | key fields | action |
|---|---|---|
| `response.created`, `response.in_progress`, `response.queued` | `response{id,status,...}` | record id |
| `response.output_item.added` | `output_index`, `item{id,type,...}` | open a slot (message / reasoning / function_call / custom_tool_call) |
| `response.content_part.added/done` | `item_id, output_index, content_index, part` | optional |
| `response.output_text.delta` | `delta` | stream text |
| `response.output_text.done` | `text` | optional |
| `response.refusal.delta/done` | `delta` / `refusal` | stream as text, flag refusal |
| `response.reasoning_summary_part.added/done` | `summary_index, part` | paragraph break |
| `response.reasoning_summary_text.delta/done` | `delta` / `text` | stream "thinking" |
| `response.reasoning_text.delta/done` | `delta` / `text` | raw reasoning (rare) |
| `response.function_call_arguments.delta/done` | `delta` / `arguments` | accumulate JSON |
| `response.custom_tool_call_input.delta/done` | `delta` / `input` | accumulate text |
| `response.output_item.done` | `item` (authoritative, incl. `encrypted_content`) | finalise slot; **store the item for replay** |
| `response.completed` | `response{status,usage,output,...}` | success; backfill any item missing from `.done`, and backfill `encrypted_content` into reasoning items whose `.done` copy lacks it (the actual Azure quirk in Pi #6409, `openai-responses-shared.ts` 535–552) |
| `response.incomplete` | `response.incomplete_details.reason` (`max_output_tokens`, `max_messages`, `content_filter`, `steered`) | stop reason length / error |
| `response.failed` | `response.error{code,message}` | error (can be a plan usage limit mid-stream) |
| `error` | `code, message, param` | error |
| `response.compaction.compacting` | (progress only) | ignore |

`response.completed` example (verbatim, trimmed):

```json
{"type":"response.completed","response":{"id":"resp_123","object":"response","status":"completed",
 "output":[{"id":"msg_123","type":"message","role":"assistant","content":[{"type":"output_text","text":"In a shimmering forest ...","annotations":[],"logprobs":[]}],"status":"completed"}],
 "store":false,"usage":{"input_tokens":0,"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":0,
 "input_tokens_details":{"cached_tokens":0,"cache_write_tokens":0}}},"sequence_number":1}
```

`response.failed` example: `{"type":"response.failed","response":{"id":"resp_123","status":"failed","error":{"code":"server_error","message":"The model failed to generate a response."}, ...}}`.

Usage accounting (Pi convention, verified in `openai-responses-shared.ts` 561–577):
- `input_tokens` includes cached and cache-write tokens, so uncached input = `input_tokens - cached_tokens - cache_write_tokens`.
- Reasoning tokens are in `output_tokens_details.reasoning_tokens`, which is part of `output_tokens`.

### 3.4 Chat Completions

```
POST https://api.openai.com/v1/chat/completions   (or <compatible base>/chat/completions)
{"model":"gpt-6-luna","messages":[{"role":"developer","content":"..."},{"role":"user","content":"hi"}],
 "tools":[{"type":"function","function":{"name":"r_eval","description":"...","parameters":{...},"strict":true}}],
 "tool_choice":"auto","reasoning_effort":"none","stream":true,"stream_options":{"include_usage":true}}
```

Assistant tool-call message and tool result for replay:

```json
{"role":"assistant","content":null,"tool_calls":[{"id":"call_abc123","type":"function","function":{"name":"r_eval","arguments":"{\"code\":\"1+1\"}"}}]}
{"role":"tool","tool_call_id":"call_abc123","content":"[1] 2"}
```

Stream (verbatim doc example): `data: {"id":"chatcmpl-123","object":"chat.completion.chunk",...,"choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}` … `data: [DONE]`.
- Tool-call deltas: `{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"r_eval","arguments":""}}]}`, then `{"tool_calls":[{"index":0,"function":{"arguments":"{\"code\":"}}]}`.
- The usage chunk is `{"choices":[],"usage":{"prompt_tokens":..,"completion_tokens":..,"total_tokens":..,"prompt_tokens_details":{"cached_tokens":..,"cache_write_tokens":..},"completion_tokens_details":{"reasoning_tokens":..}}}`.

### 3.5 Errors and headers

```json
{"error":{"message":"Rate limit reached for requests","type":"rate_limit_error","param":null,"code":"slow_down"}}
```

- Retry: follow `Retry-After` (seconds or HTTP date) on 429 `slow_down` and plain rate limits, and on 503 `server_is_overloaded`. Otherwise use exponential backoff with jitter and cap both attempts and total time. Never retry `credit_balance_exhausted`, `*_spend_limit_exceeded`, `organization_usage_limit_exceeded`, 401, 403, or plan codes other than `*_unavailable`.
- Pi also honours a non-standard `retry-after-ms` header (`openai-codex-responses.ts` 139–164).
- Rate-limit headers are listed in §2.D. Request ids come from `x-request-id`; send `X-Client-Request-Id` so a timed-out request can still be traced.

### 3.6 SIWC error handling table

See §2.D. On `subscription_sharing_usage_limit_exceeded`:
1. Pause plan requests.
2. Show "Manage usage" (`https://chatgpt.com/settings/usage`).
3. Do not infer a reset time.

On `*_unsupported_capability`: inspect `error.param`, remove the field or tool, and do not retry the same body. Refresh errors split into two cases:
- Unusable refresh token (`invalid_grant`, `invalid_refresh_token`, `token_expired`, `refresh_token_expired`, `refresh_token_invalidated`, `refresh_token_reused`): clear the tokens and re-run OAuth with the saved issued client id.
- `invalid_client`: a configuration bug.

### 3.7 Models and pricing (USD per 1M tokens, standard tier; docs 2026-09-30)

| model | input | cached | cache write | output | ctx / max in / max out | efforts | Chat Completions |
|---|---|---|---|---|---|---|---|
| gpt-6-astra | 10.00 | 1.00 | 12.50 | 50.00 | 1,050,000 / 922,000 / 128,000 | low…max (no none) | yes, but tools need Responses |
| gpt-6.1-sol | 2.00 | 0.10 | 2.50 | 10.00 | 1,050,000 / 922,000 / 128,000 | low, medium (default), high, xhigh, max | yes, without tools |
| gpt-6-sol | 2.00 | 0.20 | 2.50 | 10.00 | 1,050,000 / 922,000 / 128,000 | none…max, default medium | yes; tools only with effort none |
| gpt-6-luna | 0.10 | 0.01 | 0.125 | 0.50 | 1,050,000 / 922,000 / 128,000 | none…max, default medium | yes; tools only with effort none |
| gpt-5.6-sol | 4.00 | 0.40 | 5.00 | 20.00 | 1,050,000 / 922,000 / 128,000 | model page | yes |
| gpt-5.6-terra | 2.00 | 0.20 | 2.50 | 12.00 | same | | yes |
| gpt-5.6-luna | 0.20 | 0.02 | 0.25 | 1.20 | same | | yes |
| gpt-5.5 | 5.00 | 0.50 | – | 30.00 | 1,050,000 / – / 128,000 | default medium | yes |
| gpt-5.4 | 2.50 | 0.25 | – | 15.00 | 1,050,000 / – / 128,000 | | yes |
| gpt-5.4-mini | 0.75 | 0.075 | – | 4.50 | 400,000 / 272,000 / 128,000 | | yes |
| gpt-5.4-nano | 0.20 | 0.02 | – | 1.25 | 400,000 / 272,000 / 128,000 | | yes |
| gpt-4.1 | 2.00 | 0.50 | – | 8.00 | 1,047,576 / – / 32,768 | (non-reasoning) | yes |
| gpt-4.1-mini | 0.40 | 0.10 | – | 1.60 | 1,047,576 / – / 32,768 | | yes |

- Long context (more than 272K input) costs 2× input and cache and 1.5× output for the whole request on the 1.05M models.
- Batch and Flex cost 0.5×. Fast costs 2×; Pi applies 2.5× for gpt-5.5 priority (`openai-responses.ts` 387–400).
- **Ship this as a snapshot in `inst/extdata` (D-18) and refresh it on request.** SIWC accounts must use `GET /v1/models` (`models[].slug`).

### 3.8 Sign in with ChatGPT: ChatGPT plan usage for OSS apps (complete contract)

Discovery (VERIFIED live `GET https://auth.openai.com/.well-known/openid-configuration`):
- `issuer=https://auth.openai.com`
- `authorization_endpoint=https://auth.openai.com/api/accounts/authorize`
- `token_endpoint=https://auth.openai.com/api/accounts/oauth/token`
- `revocation_endpoint=https://auth.openai.com/api/accounts/oauth/revoke`
- `jwks_uri=https://auth.openai.com/.well-known/jwks.json` (VERIFIED: 4 RSA keys, alg RS256)
- `userinfo_endpoint=.../api/accounts/oauth/userinfo`
- `code_challenge_methods_supported=["S256"]`, `token_endpoint_auth_methods_supported` includes `"none"`

Authorize request (system browser):

| parameter | value |
|---|---|
| `client_id` | `dynamic_agent_client` (first registration) or the saved issued id (`oaiapp_…`) |
| `agent_name_hint` | `gptr`, sent only with `dynamic_agent_client` |
| `ext_agent_host_id` | persisted `urn:uuid:<v4>` (or a JWK thumbprint URI, or `did:key`) |
| `response_type` | `code` |
| `redirect_uri` | `http://127.0.0.1:<port>/auth/callback` (exact; only the port varies; never `localhost`) |
| `scope` | `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct` |
| `resource` | `https://api.openai.com/v1` |
| `state`, `nonce` | fresh random per attempt |
| `code_challenge_method` / `code_challenge` | `S256` / base64url(SHA-256(verifier)), no padding |
| `id_token_hint`, `login_hint` | re-authorisation only (saved ID token / email) |
| `prompt=consent` (or later `force_reconsent=true`) | only when the user re-enables plan use after declining |

Callback: `?code=…&scope=chatgpt.tokens.use.direct+email+offline_access+openid+profile+resource.invoke&state=…&client_id=<issued>`, or `error=access_denied`.

Token exchange (form-encoded POST to the token endpoint, no secret). VERIFIED shape via `req_dry_run`:

```
grant_type=authorization_code&client_id=<issued>&code=<code>&code_verifier=<verifier>&redirect_uri=<same>&resource=https%3A%2F%2Fapi.openai.com%2Fv1
```

- Response: `access_token`, `refresh_token`, `id_token`, `token_type`, `expires_in` (3600), `scope`, `earliest_refresh_at`.
- Refresh body: `grant_type=refresh_token&client_id=<issued>&refresh_token=<rt>&resource=...`, with no scope. The response carries a new access token and a **replacement** refresh token (30 days).
- Revoke: POST `token=<rt>&token_type_hint=refresh_token&client_id=<issued>`. An empty 200 means success.
- Access-token claims: `sub, aud ("https://api.openai.com/v1"), client_id, scope, https://api.openai.com/auth{per_user_salt, encrypted_auth_metadata}, iss, iat, exp, jti, nbf`. Treat them as opaque.

Credential record (documented shape; one file per issued client id):

```json
{"email":"user@example.com","issuer":"https://auth.openai.com","subject":"<sub>","client_id":"<issued>",
 "ext_agent_host_id":"urn:uuid:...","id_token":"<ID_TOKEN>","access_token":"<AT>","refresh_token":"<RT>",
 "token_type":"Bearer","expires_in":3600,"scopes":["chatgpt.tokens.use.direct","email","offline_access","openid","profile","resource.invoke"],
 "saved_at":"<UTC>"}
```

Inference: `POST https://api.openai.com/v1/responses`, `Authorization: Bearer <AT>`, with `store:false` and `stream:true`. Success only on `response.completed`. Models come from `GET https://api.openai.com/v1/models` → `.models[] | select(.visibility=="list") | {slug, display_name}`. Do not use `chatgpt.com/backend-api`.

### 3.9 Codex `exec --json` event schema (source `codex-rs/exec/src/exec_events.rs`, JSON as emitted)

```json
{"type":"thread.started","thread_id":"<uuid>"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'echo gptr-probe'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.updated","item":{"id":"item_2","type":"todo_list","items":[{"text":"...","completed":false}]}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"pong"}}
{"type":"item.completed","item":{"id":"item_0","type":"mcp_tool_call","server":"gptr","tool":"r_eval","arguments":{"code":"sum(1:10)"},"result":{"content":[{"type":"text","text":"[1] 55"}],"structured_content":null},"error":null,"status":"completed"}}
{"type":"turn.completed","usage":{"input_tokens":38544,"cached_input_tokens":30208,"cache_write_input_tokens":0,"output_tokens":35,"reasoning_output_tokens":0}}
{"type":"turn.failed","error":{"message":"..."}}
{"type":"error","message":"..."}
```

Item payloads:
- `agent_message{text}`: JSON text when `--output-schema` is used.
- `reasoning{text}`.
- `command_execution{command, aggregated_output, exit_code, status: in_progress|completed|failed|declined}`.
- `file_change{changes:[{path, kind: add|delete|update}], status: in_progress|completed|failed}`.
- `mcp_tool_call{server, tool, arguments, result{content[], structured_content, _meta?}|null, error{message}|null, status}`.
- `collab_tool_call{tool: spawn_agent|send_input|wait|close_agent, sender_thread_id, receiver_thread_ids, prompt, agents_states, status}`.
- `web_search{id, query, action, results?}`.
- `todo_list{items[{text, completed}]}`.
- `error{message}`.

The lines above marked with real values were captured live and redacted.

Recommended invocation from R:

```
codex exec --json -m <model> -s <read-only|workspace-write> -C <cwd> --skip-git-repo-check [--ephemeral] [--ignore-user-config]
          [-c model_reasoning_effort="low"] [-c developer_instructions='...'] [-c mcp_servers.<id>.url="http://127.0.0.1:<p>/mcp"]
          [--output-schema <file>] [-o <file>] [-i <image>]... -
```

- The prompt goes on stdin, then close stdin.
- Resume with `codex exec resume <thread_id> --json ... -` (not ephemeral; `-C` and `-s` are not accepted, so use `-c sandbox_mode=`).
- Useful config keys: `model_reasoning_effort` (low|medium|high|xhigh|max|ultra, model-dependent), `model_reasoning_summary` (auto|concise|detailed|none), `model_verbosity`, `developer_instructions`, `model_instructions_file` (replaces the built-in instructions), `sandbox_mode`, `sandbox_workspace_write.network_access`, `web_search` (disabled|cached|indexed|live), `shell_environment_policy.inherit` (all|core|none), `hide_agent_reasoning`, `history.persistence` (save-all|none), `model_provider`, `model_providers.<id>.*`.

### 3.10 Codex app-server protocol (stdio)

Framing: one JSON object per line.
- Request: `{"method":..., "id":N, "params":{...}}`.
- Response: `{"id":N, "result":...}` or `{"id":N, "error":{"code":..,"message":..}}`.
- Notification: `{"method":..., "params":...}`, with no id.
- The server also sends requests with its own ids, starting at 0. Reply with the same id.

Minimal session for gptr (verified live except `turn/steer`, `turn/interrupt` and `thread/resume`):

```json
{"method":"initialize","id":1,"params":{"clientInfo":{"name":"gptr","title":"gptr (R)","version":"0.0.0.9000"},"capabilities":{"experimentalApi":true}}}
{"method":"initialized","params":{}}
{"method":"thread/start","id":2,"params":{"model":"gpt-6-luna","cwd":"/abs/path","approvalPolicy":"never","sandbox":"read-only","ephemeral":true,
  "developerInstructions":"You are running inside the user's R session via gptr...",
  "dynamicTools":[{"type":"function","name":"r_eval","description":"Evaluate R code in the user's live R session and return the printed result.",
                   "inputSchema":{"type":"object","properties":{"code":{"type":"string"}},"required":["code"],"additionalProperties":false}}]}}
{"method":"turn/start","id":3,"params":{"threadId":"<id>","input":[{"type":"text","text":"..."}],"effort":"low"}}
<- {"method":"item/tool/call","id":0,"params":{"threadId":"..","turnId":"..","callId":"exec-..","namespace":null,"tool":"r_eval","arguments":{"code":"nrow(big_df)"}}}
-> {"id":0,"result":{"contentItems":[{"type":"inputText","text":"[1] 123457"}],"success":true}}
<- {"method":"item/started","params":{"item":{"type":"agentMessage","id":"msg_..","text":"","phase":"final_answer"},...}}
<- {"method":"item/agentMessage/delta","params":{"threadId":"..","turnId":"..","itemId":"msg_..","delta":"123"}}
<- {"method":"turn/completed","params":{"threadId":"..","turn":{"id":"..","status":"completed","error":null,...}}}
{"method":"turn/steer","id":4,"params":{"threadId":"..","input":[{"type":"text","text":"focus on X"}],"expectedTurnId":".."}}
{"method":"turn/interrupt","id":5,"params":{"threadId":"..","turnId":".."}}
{"method":"thread/resume","id":6,"params":{"threadId":".."}}
```

Approval replies (VERIFIED enum definitions):
- `item/commandExecution/requestApproval` → `{"decision":"accept"|"acceptForSession"|"decline"|"cancel"|{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":[...]}}|{"applyNetworkPolicyAmendment":{...}}}`.
- `item/fileChange/requestApproval` → `{"decision":"accept"|"acceptForSession"|"decline"|"cancel"}`. `cancel` also interrupts the turn.
- `item/tool/requestUserInput{questions:[{id,header,question,options?,isOther,isSecret}], isBlocking}` → `{"answers":{"<id>":{"answers":["..."]}}}`.
- `item/permissions/requestApproval` → `{"permissions":{...granted subset...},"scope":"turn"|"session"}`.
- `mcpServer/elicitation/request` → `{"action":"accept","content":{...}}` or `{"action":"decline"|"cancel","content":null}`.

Account and usage:
- `account/read{refreshToken:false}` → `{account:{type:"chatgpt",email,planType}, requiresOpenaiAuth, workspaceRouting{...}}`.
- `account/rateLimits/read` → `{rateLimits:{limitId:"codex", primary:{usedPercent, windowDurationMins, resetsAt}, secondary, credits, planType, rateLimitReachedType}, rateLimitsByLimitId, rateLimitResetCredits}`. Observed live: Pro, `windowDurationMins: 10080`, `usedPercent: 45`.
- Login flows: `account/login/start{type:"chatgpt"|"chatgptDeviceCode"|"apiKey"|"chatgptAuthTokens"}`. The first two return `authUrl` or `verificationUrl`/`userCode`. `chatgptAuthTokens` is experimental host-owned tokens, with a refresh server request.

SIWC provider configuration for app-server (verbatim from the SIWC doc; the child environment carries `ACCESS_TOKEN`):

```
codex app-server --listen stdio:// \
  -c 'model_provider="openai_chatgpt_plan"' \
  -c 'model_providers.openai_chatgpt_plan.name="ChatGPT plan"' \
  -c 'model_providers.openai_chatgpt_plan.base_url="https://api.openai.com/v1"' \
  -c 'model_providers.openai_chatgpt_plan.env_key="ACCESS_TOKEN"' \
  -c 'model_providers.openai_chatgpt_plan.wire_api="responses"' \
  -c 'model_providers.openai_chatgpt_plan.requires_openai_auth=false' \
  -c 'model_providers.openai_chatgpt_plan.supports_websockets=false'
```

### 3.11 Codex CLI surface (0.157.0, `codex --help`)

- Commands: `agents, exec (e), review, login [status], logout, mcp {list,get,add,remove,login,logout}, plugin, app-server {daemon,proxy,generate-ts,generate-json-schema}, remote-control, app, completion, update, doctor [--json], sandbox, debug {models [--bundled], app-server, prompt-input}, apply, resume, queue, archive, delete, migrate-rollouts, unarchive, fork, cloud, exec-server, features`.
- **`mcp-server` is gone.** `codex mcp-server --help` falls through to the top-level help.
- Top-level flags add `-a/--ask-for-approval on-request|never`, `--search`, `--remote <ws://|wss://|unix://>`, `--no-alt-screen`, `--no-daemon` and `--worktree`.
- Install methods (doc): standalone installer (`curl … install.sh | sh`; Windows `irm https://chatgpt.com/codex/install.ps1 | iex`), `npm install -g @openai/codex`, `brew install --cask codex`.
- The npm launcher (`codex-cli/bin/codex.js`) spawns the native binary at `<pkg>/node_modules/@openai/codex-<platform>/vendor/<triple>/bin/codex[.exe]` (triples include `x86_64-pc-windows-msvc` and `aarch64-pc-windows-msvc`). It only adds `CODEX_MANAGED_*` environment variables. VERIFIED (source and the local darwin layout).

---

## 4. Recommended design for gptr

### 4.1 Routes and defaults

| provider id | transport | auth | when | status |
|---|---|---|---|---|
| `openai` | native Responses (httr2 SSE) | `OPENAI_API_KEY` **or** `chatgpt` (SIWC token) | default for OpenAI models inside gptr's own agent loop | build (v1) |
| `openai_compatible` (+ presets `openrouter`, `ollama`, `groq`, …) | native Chat Completions | per-provider key | lingua franca | build (v1; see track 03 for compat flags) |
| `codex` | external agent: `codex app-server` (default) / `codex exec --json` (fallback, batch) | whatever Codex is logged in with, **or** gptr's SIWC token via `openai_chatgpt_plan` provider config | delegate whole tasks to Codex (sub-agent mode `cli`, D-12) | build (v1, experimental flag) |
| `claude_code` | external agent: `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages` | Claude Code's own login | Claude plan (REQ-12, track 07) | shares the `ext_agent` adapter |

**Default ChatGPT-plan route: `openai` with `auth = "chatgpt"` (SIWC).** Reasons:
1. It is pure R (REQ-01).
2. gptr's minimal system prompt and in-memory tools run natively, with no 20–40K-token Codex overhead.
3. It is the path OpenAI recommends for open-source apps and it attributes usage to "gptr" in ChatGPT settings.
4. It shares all code with API-key mode.

**Default `codex` provider driver: app-server.** Reasons:
1. Tools execute in-session (dynamic tools, verified).
2. Approvals map onto gptr permission modes.
3. `turn/steer` and `turn/interrupt` satisfy REQ-38.
4. Streaming deltas are available.
5. Threads persist and resume.
6. `model/list` and `account/rateLimits/read` feed the UI.
7. The official Python SDK uses the same protocol.

Fall back to `exec --json` when:
- app-server fails to initialise, or the Codex version is below a tested minimum;
- the user sets `driver = "exec"`;
- gptr runs many parallel one-shot delegations (REQ-33), where process isolation is simpler.

### 4.2 User-facing API (proposed)

```r
gptr_login("chatgpt")            # SIWC: opens browser (interactive only), stores credentials; prints "You're using your ChatGPT plan"
gptr_login("chatgpt", account = "work")   # additional registration/profile
gptr_logout("chatgpt")           # revoke refresh token, clear tokens, keep client/host mapping
gptr_accounts()                  # data.frame: provider, label, email, client_id (masked), plan_scope, expires_at, active
gptr_usage("chatgpt")            # opens https://chatgpt.com/settings/usage ("Manage usage")
gptr_models("openai")            # live catalog: API-key -> /v1/models list; chatgpt -> models[].slug
gptr("prompt", model = openai/gpt-6.1-sol)            # auth auto: api key if set, else chatgpt plan
gptr("prompt", model = openai/gpt-6.1-sol, auth = "chatgpt")
gptr("refactor R/foo.R", model = codex/gpt-6-luna, sandbox = "workspace-write")  # external agent
gptr_codex_status()              # codex path/version, login state (via app-server account/read), rate-limit %
```

### 4.3 Internal modules (file layout and signatures)

- `R/sse.R`: `sse_parser()` returns `function(bytes = raw(0), final = FALSE)` → list of `list(event, data, id)`. Byte-level; handles LF, CRLF and CR; splits only on blank lines, so UTF-8 split across chunks survives. VERIFIED (§5.7).
- `R/json.R`: `json_parse(txt)` sets `Encoding(txt) <- "UTF-8"` before `jsonlite::fromJSON(txt, simplifyVector = FALSE)`. `json_dump(x)` is `jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)`. Exact-match accessors only (`[[`).
- `R/provider-openai-responses.R`:
  - `openai_responses_body(model, input, instructions, tools, tool_choice, parallel_tool_calls, reasoning_effort, reasoning_summary, text_format, verbosity, max_output_tokens, temperature, prompt_cache_key, include, plan_mode)`
  - `responses_accumulator(on_text, on_reasoning)` with `$handle(event)` and `$result()` → `list(response_id, status, terminal, incomplete_reason, error, text, tool_calls, output_items, usage)`
  - `responses_replay_items(output_items)`, `function_call_output(call_id, output)`
  - `gptr_tools_to_responses(tools, namespace = if (plan_mode) "gptr")`
- `R/provider-openai-chat.R`: `chat_completions_body(...)`, `chat_accumulator(on_text)`, plus compat flags (track 03).
- `R/http-stream.R`: `openai_stream(url, body, token, on_event, headers, timeout)`, built on `httr2::req_perform_connection()`. Either use `resp_stream_sse()` and re-mark UTF-8, or use `resp_stream_raw()` with `sse_parser()`. Both are verified identical on fixtures. **Prefer the raw variant**, but for a different reason than first stated: in httr2 1.2.2 and 1.3.0, `resp_stream_sse()` also handled CR-only framing and a missing Content-Type (verification test). Its real gap is that it drops a final event that lacks the terminating blank line, with the warning "Premature end of input; ignoring final partial chunk", whereas `sse_parser(final = TRUE)` flushes it, as the devkit does.
  - Retries happen only before the first byte, and only for 429/503 without a terminal code, or for network errors.
  - Never retry after a stream has started (a partial turn must be surfaced).
- `R/auth-chatgpt.R` (SIWC):
  - `siwc_host_id()`: reads or creates `R_user_dir("gptr","config")/chatgpt/host.json`.
  - `siwc_login(label, open_browser = interactive(), port = 0L)`: loopback on `127.0.0.1` via httpuv. If the listener fails or no browser is available, accept a pasted redirect URL, as Pi and the devkit do.
  - `siwc_exchange()`, `siwc_validate_id_token()` (jose if installed; otherwise refuse login with a clear message; pick the JWKS key whose `kid` equals `jose::jwt_split(id_token)$header$kid`, because the live JWKS has 4 keys; compare `aud` with `%in%` in case it is an array), `siwc_refresh(cred)` (serialised with a lock file; refresh 3 min before `exp`), `siwc_revoke()`, `siwc_store_read/write()` (atomic, 0600), `siwc_list_models(token)`.
- `R/ext-agent.R`: the shared adapter for external CLI agents (below).
- `R/ext-agent-codex.R`: `codex_find()`, `codex_version()`, `codex_appserver_start()`, `codex_exec_run()`, and event mappers.
- `R/ext-agent-claude.R`: track 07.
- `R/mcp-bridge.R`: `mcp_http_bridge_start(tools, env)` → `list(url, stop)`, a streamable-HTTP MCP server (JSON-response mode) on `127.0.0.1:<random>` served by httpuv. `mcp_bridge_pump(ms)` calls `httpuv::service(ms)`.

### 4.4 The shared "external CLI agent" adapter

Data structure (an R6 or environment-based object; methods are closures):

```r
ext_agent <- function(kind, ...)            # kind: "codex_appserver" | "codex_exec" | "claude_stream"
# fields: kind, proc (processx), version, session_id (thread id / claude session id), model,
#         tools (named list of R functions + JSON schemas), env (evaluation env), permission (gptr mode),
#         bridge (mcp_http_bridge or NULL), pending (map of outstanding request ids)
# methods:
#   $start()                 spawn + handshake (initialize / thread/start | none for exec)
#   $run(prompt, images = NULL, on_event)  -> gptr_turn_result (blocks; pumps IO, bridge, interrupts)
#   $steer(text)             app-server turn/steer | claude stream-json user message | exec: unsupported
#   $interrupt()             app-server turn/interrupt | claude: control interrupt | exec: kill_tree()
#   $resume(session_id)      app-server thread/resume | exec: `exec resume <id>` | claude --resume
#   $close()
```

Normalised event vocabulary, emitted to gptr's console renderer, script recorder and hooks:

| gptr event | codex app-server | codex exec | claude stream-json (track 07) | openai responses (native) |
|---|---|---|---|---|
| `turn_start` | `turn/started` | `turn.started` | `system/init` | `response.created` |
| `text_delta` | `item/agentMessage/delta` | (none; final text only) | `stream_event` content_block_delta text | `response.output_text.delta` |
| `reasoning_delta` | `item/reasoning/summaryTextDelta` | `item.completed{reasoning}` | thinking delta | `response.reasoning_summary_text.delta` |
| `tool_start` / `tool_end` | `item/started` / `item/completed` (`dynamicToolCall`, `mcpToolCall`, `commandExecution`, `fileChange`, `webSearch`) | `item.started` / `item.completed` | `tool_use` / `tool_result` | `output_item.added` / `.done` (function_call), after local exec |
| `approval_request` | server requests (§3.10) | n/a (never) | permission prompt tool / control request | gptr permission layer |
| `usage` | `thread/tokenUsage/updated` | `turn.completed.usage` | `result.usage` | `response.completed.usage` |
| `turn_end` | `turn/completed{status}` | `turn.completed` / `turn.failed` | `result` | terminal event |
| `error` | `error{error.codexErrorInfo}` | `error` / `turn.failed` | `result{is_error}` | `response.failed` / `error` |

Main loop, the same for every kind:

```
repeat {
  proc$poll_io(50)                                   # processx
  lines <- splitter(proc$read_output()) ; dispatch each (json_parse, [[ ]])
  if (!is.null(bridge)) httpuv::service(0)           # in-session MCP bridge (tools see live env)
  later::run_now(0)                                  # other async work (optional)
  if (interrupted) agent$interrupt()                 # caught via tryCatch(interrupt = ...) around the loop
  if (turn_done) break
}
```

This loop was verified in pieces: the exec loop (§5.2, §5.6), app-server request and response handling (§5.4), and httpuv servicing during Codex waits (§5.5). Ctrl+C handling is **not** verified here; see track 15 on concurrency.

Tool exposure:
- `codex_appserver` uses `dynamicTools`: R functions are exported with their JSON schemas and answered in-process.
- `codex_exec` and `claude_stream` use the in-session HTTP MCP bridge: `-c mcp_servers.gptr.url=...` for Codex (config key VERIFIED), and `--mcp-config '{"mcpServers":{"gptr":{"type":"http","url":"http://127.0.0.1:<p>/mcp"}}}' --strict-mcp-config` for Claude. The flags are VERIFIED in `claude --help` (v2.1.261); the JSON `type:"http"` shape is LIKELY and should be confirmed by track 07.
- A stdio MCP server in a separate R process is the last resort, because it cannot see live objects.

Permission mapping (REQ-37, D-11):

| gptr mode | codex app-server | codex exec | notes |
|---|---|---|---|
| `plan` (read-only) | `sandbox:"read-only"`, `approvalPolicy:"never"` | `-s read-only` | also gptr tools restricted to read-only |
| `manual` | `sandbox:"workspace-write"`, `approvalPolicy:"on-request"`; every approval request → console prompt (`utils::menu`) | not supported → downgrade to `plan` with a message | dynamic tool calls also pass gptr's own permission hook before evaluation |
| `edits` | workspace-write + on-request; auto-`accept` `fileChange` inside the workspace, prompt for commands | `-s workspace-write` (no prompts possible) | |
| `auto` | workspace-write + `never` (or `danger-full-access` only if the user explicitly sets `sandbox = "full"`) | `-s workspace-write` | never pass `--dangerously-bypass-approvals-and-sandbox` by default |

Conversation continuity (REQ-18):
- The `gptr` result object stores `provider = "codex"`, `session_id = thread_id` and the driver.
- A piped call reuses the live app-server process (keyed by session id), or starts one and calls `thread/resume`.
- For exec, gptr omits `--ephemeral` whenever continuity may be needed and uses `codex exec resume <thread_id> --json -`. This is LIKELY from the help text; not run because of the call budget.

Script-as-history (REQ-24/25): record the prompt (`gptr("...", model = codex/...)`), the final agent message as comments, file changes as a list of paths plus the `turn/diff/updated` unified diff, and the thread id, so a re-run can resume or replay.

### 4.5 Native `openai` provider algorithms

Turn algorithm (stateless):

1. Build `input` = gptr transcript converted to Responses items:
   - System prompt goes to `instructions`, or a `developer` item for mid-conversation updates.
   - User content becomes `input_text`/`input_image` (base64 PNG from captured plots for vision models).
   - Prior assistant turns **from the same provider and model family** are replayed verbatim from their stored `output_items`, including reasoning `encrypted_content` and `phase`. Cross-provider turns become plain assistant text and function_call/function_call_output pairs without `fc_` ids (Pi drops foreign item ids, `openai-responses-shared.ts` 296–306).
   - Tool results become `function_call_output{call_id, output}`. Text is truncated per D-19; images become an array output.
2. POST with `stream:true`, `store:false` and `prompt_cache_key = <gptr session id>`. Feed events to `responses_accumulator`.
3. On a terminal event:
   - `completed` with function calls: run the gptr tools through the permission hook, append `output_items` and the outputs, and loop.
   - `completed` without calls: return.
   - `incomplete{max_output_tokens}`: return with a warning and `stop_reason = "length"`.
   - `failed` / `error`: signal a classed condition (`gptr_error_openai`, with subclasses `rate_limit`, `usage_limit`, `unsupported_capability`, `auth`, `server`).
   - A stream ending without a terminal event is an error (as in Pi and the devkit).
4. Plan mode (SIWC): apply the §3.1 filter and wrap tools in `namespace "gptr"`. If `subscription_sharing_unsupported_capability` names `tools`, retry once with the tools sent as an `additional_tools` input item. Surface "Manage usage" on limit errors.
5. Usage and cost: tokens as in §3.3. Cost comes from the pricing snapshot for API-key mode and is shown as "plan" (no cost) for SIWC.

Token refresh (SIWC):
- Before each request, if `expires_at - now < 180 s`, refresh under a file lock (`R_user_dir(...)/chatgpt/<client_id>.lock`).
- Write `access_token`, `refresh_token`, `scopes`, `expires_at` and `earliest_refresh_at` atomically.
- On a terminal refresh error, keep the record without tokens and ask the user to run `gptr_login("chatgpt")`.

### 4.6 Package choices

| package | role | Imports / Suggests |
|---|---|---|
| httr2 (≥ 1.1.1: `req_perform_connection()` exists since 1.0.4, `resp_stream_is_complete()` since 1.1.0, and `resp_stream_sse()` returns single-string data and skips data-less events since 1.1.1, per httr2 NEWS; prototypes verified on 1.2.2 and 1.3.0) | HTTP, streaming | Imports |
| jsonlite | JSON | Imports |
| processx | CLI agents (codex, claude), MCP stdio | Imports (already chosen in D-14) |
| openssl | PKCE (sha256, rand_bytes, base64) | Imports (hard dependency of httr2 anyway) |
| httpuv | OAuth loopback callback, in-session MCP HTTP bridge | Suggests (`rlang::check_installed()` at login or bridge start); already pulled in by shiny for REQ-39 |
| jose | RS256 ID-token signature check against JWKS (`read_jwk`, `jwt_decode_sig`, `jwt_split` for the `kid`). CRAN is at 2.0.0 (Depends openssl, Imports jsonlite); these functions behave the same in 1.2.1 and 2.0.0 (verified). Since 1.2, `jwt_decode_sig(jwt, pubkey)` itself rejects expired tokens and has no leeway argument, so the devkit's 5-second clock tolerance cannot be passed through it | Suggests (needed by `gptr_login("chatgpt")`) |
| later | optional event-loop integration | Suggests |
| ellmer | reference only; not used | none |

---

## 5. Verified R prototypes

Every file below was run with `Rscript --vanilla` on R 4.4.3 (macOS arm64, locale `C` unless stated). The outputs are pasted verbatim. Identifiers are redacted with `<UUID>`, `<EMAIL>`, `<HOME>` and `<RANDOM>`, and repeated lines are condensed where marked. Real model calls: **§5.2, §5.3 and §5.4 only** (3 calls in total, all through the user's Codex ChatGPT login). No OpenAI API call was made.

Verification note: the fact-check re-ran every offline prototype (§5.4 replay, §5.5, §5.6, §5.7, §5.8, §5.9) from the code embedded here and reproduced the outputs shown. The three live-call scripts were not re-run. Three fixes were then made in place: `proc_write_all()` in §5.1, the looping `self$send` in §5.4's `appserver_client.R`, and the reasoning `encrypted_content` backfill in §5.7's `responses_accumulator()`. After the fixes, §5.6, §5.7 (identical output) and §5.5 were re-run. The live-call outputs in §5.2–§5.4 come from the pre-fix code, whose messages were all under 8 KB.

### 5.1 `codex exec` driver (processx + JSONL)

This is the core of the proposed `ext_agent_codex_exec`. Design points:
- The prompt goes on stdin (`codex exec … -`), written with `proc_write_all()` because `write_input()` is non-blocking (added during verification; the original single `p$write_input()` call truncated a 50 KB prompt to about 8 KB).
- `encoding = "UTF-8"` is required (see §5.9).
- The JSONL line splitter tolerates CRLF.
- The read loop uses `processx`'s `is_incomplete_output()`.
- `codex` may be a vector (executable plus prefix arguments), which allows `wsl codex` and a fake binary for tests.

`T08/proto/codex_exec.R`

```r
# Prototype: drive `codex exec --json` from R with processx and parse the JSONL
# event stream incrementally. Pure R (processx + jsonlite). Cross-platform:
# the prompt goes through stdin (`codex exec -`) so there is no argv length or
# quoting problem on Windows (cmd line limit 32,767 chars).

jsonl_splitter <- function() {
  buf <- ""
  function(chunk) {
    if (!nzchar(chunk)) return(character())
    buf <<- paste0(buf, chunk)
    parts <- strsplit(buf, "\n", fixed = TRUE)[[1]]
    if (endsWith(buf, "\n")) {
      buf <<- ""
    } else {
      buf <<- parts[length(parts)]
      parts <- parts[-length(parts)]
    }
    parts <- sub("\r$", "", parts)          # tolerate CRLF on Windows
    parts[nzchar(trimws(parts))]
  }
}

codex_find <- function() {
  exe <- Sys.getenv("GPTR_CODEX_PATH", unset = "")
  if (nzchar(exe)) return(exe)
  exe <- Sys.which("codex")
  if (!nzchar(exe) && .Platform$OS.type == "windows") {
    # npm installs a codex.cmd shim on Windows
    exe <- Sys.which("codex.cmd")
  }
  if (!nzchar(exe)) stop("Codex CLI not found on PATH; install it or set GPTR_CODEX_PATH")
  unname(exe)
}

codex_exec_args <- function(model = NULL, sandbox = c("read-only", "workspace-write", "danger-full-access"),
                            cwd = NULL, config = list(), output_schema = NULL, last_message_file = NULL,
                            ephemeral = TRUE, skip_git_repo_check = TRUE, images = character(),
                            resume = NULL) {
  sandbox <- match.arg(sandbox)
  args <- c("exec")
  if (!is.null(resume)) args <- c(args, "resume", resume)   # `codex exec resume <id> -`
  args <- c(args, "--json")
  if (!is.null(model)) args <- c(args, "-m", model)
  if (is.null(resume)) args <- c(args, "-s", sandbox)       # resume does not accept -s; use -c sandbox_mode=
  else args <- c(args, "-c", sprintf('sandbox_mode="%s"', sandbox))
  if (!is.null(cwd) && is.null(resume)) args <- c(args, "-C", cwd)
  if (isTRUE(skip_git_repo_check)) args <- c(args, "--skip-git-repo-check")
  if (isTRUE(ephemeral)) args <- c(args, "--ephemeral")
  if (!is.null(output_schema)) args <- c(args, "--output-schema", output_schema)
  if (!is.null(last_message_file)) args <- c(args, "-o", last_message_file)
  for (img in images) args <- c(args, "-i", img)
  for (nm in names(config)) args <- c(args, "-c", paste0(nm, "=", config[[nm]]))
  c(args, "-")                                                # prompt from stdin
}

# processx write_input() is NON-BLOCKING: it writes what fits in the pipe (8 KB on macOS)
# and returns the unwritten bytes as a raw vector. Ignoring that return value silently
# truncates long prompts (verified). Loop until everything is written.
proc_write_all <- function(p, x, timeout = 60) {
  rest <- if (is.raw(x)) x else charToRaw(enc2utf8(x))
  deadline <- Sys.time() + timeout
  while (length(rest)) {
    rest <- p$write_input(rest)
    if (!length(rest)) break
    if (!p$is_alive()) stop("child exited before reading all of stdin")
    if (Sys.time() > deadline) stop("timed out writing to child stdin")
    Sys.sleep(0.005)
  }
  invisible(TRUE)
}

codex_exec <- function(prompt, ..., on_event = NULL, timeout = 300, env = NULL,
                       codex = codex_find(), wd = NULL) {
  args <- codex_exec_args(...)
  # `codex` may be a vector: executable + prefix args (e.g. c("wsl", "codex") or a test fake)
  p <- processx::process$new(
    codex[[1]], c(codex[-1], args),
    stdin = "|", stdout = "|", stderr = "|",
    env = env, wd = wd,
    cleanup = TRUE, cleanup_tree = TRUE, windows_hide_window = TRUE,
    encoding = "UTF-8"   # REQUIRED: default "" drops non-ASCII bytes in a C locale (verified)
  )
  on.exit(if (p$is_alive()) p$kill_tree(), add = TRUE)
  proc_write_all(p, prompt)                    # NOT p$write_input(): see proc_write_all()
  close(p$get_input_connection())               # EOF: codex starts the turn

  split_out <- jsonl_splitter()
  events <- list()
  stderr_txt <- character()
  deadline <- Sys.time() + timeout
  handle_lines <- function(lines) {
    for (ln in lines) {
      Encoding(ln) <- "UTF-8"; ev <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(ev)) { stderr_txt <<- c(stderr_txt, paste("[non-json stdout]", ln)); next }
      events[[length(events) + 1L]] <<- ev
      if (!is.null(on_event)) on_event(ev)
    }
  }
  # Canonical processx loop: keep reading until both pipes hit EOF.
  while (p$is_incomplete_output() || p$is_incomplete_error()) {
    p$poll_io(200)
    if (p$is_incomplete_output()) handle_lines(split_out(p$read_output()))
    if (p$is_incomplete_error()) stderr_txt <- c(stderr_txt, p$read_error())
    if (Sys.time() > deadline) { p$kill_tree(); stop("codex exec timed out after ", timeout, "s") }
  }
  handle_lines(split_out("\n"))                  # flush a final unterminated line
  p$wait(5000)
  status <- p$get_exit_status()
  codex_exec_result(events, status, paste(stderr_txt, collapse = ""))
}

# Fold the event list into a result object.
codex_exec_result <- function(events, status = 0L, stderr = "") {
  types <- vapply(events, function(e) if (is.null(e$type)) NA_character_ else e$type, "")
  thread_id <- NULL; usage <- NULL; error <- NULL
  items <- list(); final_text <- NULL
  for (e in events) {
    switch(e$type,
      "thread.started" = { thread_id <- e$thread_id },
      "turn.completed" = { usage <- e$usage },
      "turn.failed"    = { error <- e$error$message },
      "error"          = { error <- e$message },
      "item.completed" = {
        items[[e$item$id]] <- e$item
        if (identical(e$item$type, "agent_message")) final_text <- e$item$text
      },
      NULL)
  }
  structure(list(
    text = final_text, thread_id = thread_id, usage = usage, error = error,
    items = unname(items), event_types = types, exit_status = status, stderr = stderr
  ), class = "gptr_codex_result")
}

redact_ids <- function(x) {
  if (is.list(x)) return(lapply(x, redact_ids))
  if (!is.character(x)) return(x)
  x <- gsub("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", "<UUID>", x, ignore.case = TRUE)
  x <- gsub("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "<EMAIL>", x)
  gsub(path.expand("~"), "<HOME>", x, fixed = TRUE)
}
```

### 5.2 Live call 1: plain `codex exec --json` (REAL model call 1 of 3)

`T08/proto/run_call1.R`

```r
# Real call 1 of 3: plain `codex exec --json` driven from R.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto/codex_exec.R")
wd <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto/sandbox1"
dir.create(wd, showWarnings = FALSE, recursive = TRUE)
raw_file <- file.path(dirname(wd), "call1_events.jsonl")
last_msg <- file.path(dirname(wd), "call1_last_message.txt")
raw <- file(raw_file, "w")
t0 <- Sys.time()
res <- codex_exec(
  "Run the shell command `echo gptr-probe` exactly once, then reply with exactly the single word: pong",
  model = "gpt-6-luna", sandbox = "read-only", cwd = wd,
  config = list(model_reasoning_effort = '"low"'),
  last_message_file = last_msg,
  on_event = function(ev) {
    writeLines(jsonlite::toJSON(redact_ids(ev), auto_unbox = TRUE, null = "null"), raw)
    cat(sprintf("[%5.1fs] %s%s\n", as.numeric(Sys.time() - t0, units = "secs"), ev$type,
                if (!is.null(ev$item)) paste0(" ", ev$item$type, " (", ev$item$status %||% "", ")") else ""))
  },
  timeout = 240
)
close(raw)
cat("\nexit status:", res$exit_status, "\n")
cat("final text:", res$text, "\n")
cat("thread id present:", !is.null(res$thread_id), "\n")
cat("usage:", jsonlite::toJSON(res$usage, auto_unbox = TRUE), "\n")
cat("event types:", paste(res$event_types, collapse = ", "), "\n")
cat("last-message file:", readLines(last_msg, warn = FALSE), "\n")
cat("stderr (first 400 chars):", substr(redact_ids(res$stderr), 1, 400), "\n")
```

Observed output (`out_call1.txt`):

```text
[  1.1s] thread.started
[  1.1s] turn.started
[  6.1s] item.started command_execution (in_progress)
[  6.2s] item.completed command_execution (completed)
[  6.8s] item.completed agent_message ()
[  7.0s] turn.completed

exit status: 0 
final text: pong 
thread id present: TRUE 
usage: {"input_tokens":38544,"cached_input_tokens":30208,"cache_write_input_tokens":0,"output_tokens":35,"reasoning_output_tokens":0} 
event types: thread.started, turn.started, item.started, item.completed, item.completed, turn.completed 
last-message file: pong 
stderr (first 400 chars): 
```

Captured JSONL (redacted, `T08/proto/call1_events.jsonl`):

```json
{"type":"thread.started","thread_id":"<UUID>"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'echo gptr-probe'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'echo gptr-probe'","aggregated_output":"gptr-probe\n","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"pong"}}
{"type":"turn.completed","usage":{"input_tokens":38544,"cached_input_tokens":30208,"cache_write_input_tokens":0,"output_tokens":35,"reasoning_output_tokens":0}}
```

The shell tool ran `/bin/zsh -lc 'echo gptr-probe'`: Codex uses the user's login shell on macOS. The 38.5K input tokens for a two-line task show Codex's built-in prompt and tool overhead. VERIFIED.

### 5.3 Live call 2: R MCP stdio server via `-c` overrides + `--output-schema` (REAL model call 2 of 3)

`T08/proto/mcp_stdio_server.R`

```r
# Minimal MCP stdio server in pure R (jsonlite only).
# Protocol: newline-delimited JSON-RPC 2.0 on stdin/stdout. Logs go to stderr.
# Exposes one tool: r_eval_expr(code) -> evaluates an R expression and returns its printed value.
suppressWarnings(suppressMessages(library(jsonlite)))

to_json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)
send <- function(x) {
  cat(to_json(x), "\n", sep = "", file = stdout())
  flush(stdout())
}
log_msg <- function(...) cat("[gptr-mcp] ", ..., "\n", sep = "", file = stderr())

tools <- list(list(
  name = "r_eval_expr",
  description = "Evaluate one R expression in the gptr helper process and return the printed result.",
  inputSchema = list(
    type = "object",
    properties = list(code = list(type = "string", description = "R expression to evaluate")),
    required = list("code"),
    additionalProperties = FALSE
  ),
  annotations = list(readOnlyHint = TRUE, destructiveHint = FALSE, openWorldHint = FALSE)
))

handle <- function(msg) {
  id <- msg$id
  method <- msg$method
  if (is.null(method)) return(invisible())            # a response to us; ignore
  if (identical(method, "initialize")) {
    pv <- msg$params$protocolVersion
    if (is.null(pv)) pv <- "2025-06-18"
    send(list(jsonrpc = "2.0", id = id, result = list(
      protocolVersion = pv,
      capabilities = list(tools = list(listChanged = FALSE)),
      serverInfo = list(name = "gptr-r-tools", version = "0.0.1"),
      instructions = "R tools served by gptr."
    )))
  } else if (identical(method, "notifications/initialized")) {
    invisible()
  } else if (identical(method, "ping")) {
    send(list(jsonrpc = "2.0", id = id, result = structure(list(), names = character())))
  } else if (identical(method, "tools/list")) {
    send(list(jsonrpc = "2.0", id = id, result = list(tools = tools)))
  } else if (identical(method, "tools/call")) {
    name <- msg$params$name
    args <- msg$params$arguments
    if (!identical(name, "r_eval_expr")) {
      send(list(jsonrpc = "2.0", id = id, error = list(code = -32602L, message = paste("Unknown tool:", name))))
      return(invisible())
    }
    out <- tryCatch({
      val <- eval(parse(text = args$code), envir = globalenv())
      list(text = paste(utils::capture.output(print(val)), collapse = "\n"), is_error = FALSE)
    }, error = function(e) list(text = paste("Error:", conditionMessage(e)), is_error = TRUE))
    send(list(jsonrpc = "2.0", id = id, result = list(
      content = list(list(type = "text", text = out$text)),
      isError = out$is_error
    )))
  } else if (!is.null(id)) {
    send(list(jsonrpc = "2.0", id = id, error = list(code = -32601L, message = paste("Method not found:", method))))
  }
}

con <- file("stdin", open = "r")
log_msg("started")
repeat {
  line <- readLines(con, n = 1L, warn = FALSE)
  if (length(line) == 0L) break
  if (!nzchar(trimws(line))) next
  msg <- tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(msg)) { log_msg("bad json: ", line); next }
  handle(msg)
}
log_msg("stdin closed; exiting")
```

`T08/proto/run_call2.R`

```r
# Real call 2 of 3: `codex exec --json` + an R MCP stdio server supplied only via
# `-c` overrides (no edit to ~/.codex/config.toml) + `--output-schema`.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto/codex_exec.R")
base <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto"
wd <- file.path(base, "sandbox2"); dir.create(wd, showWarnings = FALSE)
schema_file <- file.path(base, "call2_schema.json")
writeLines(jsonlite::toJSON(list(
  type = "object",
  properties = list(answer = list(type = "string"), tool_used = list(type = "boolean")),
  required = c("answer", "tool_used"),
  additionalProperties = FALSE
), auto_unbox = TRUE), schema_file)

toml_str <- function(x) paste0("'", x, "'")     # TOML literal string: no backslash escaping (Windows paths)
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
mcp <- list(
  "mcp_servers.gptr.command" = toml_str(normalizePath(rscript, winslash = "/")),
  "mcp_servers.gptr.args" = sprintf("[%s,%s]", toml_str("--vanilla"), toml_str(file.path(base, "mcp_stdio_server.R"))),
  "mcp_servers.gptr.default_tools_approval_mode" = '"approve"',
  "mcp_servers.gptr.startup_timeout_sec" = "20",
  "mcp_servers.gptr.required" = "true",
  "model_reasoning_effort" = '"low"'
)
raw <- file(file.path(base, "call2_events.jsonl"), "w")
t0 <- Sys.time()
res <- codex_exec(
  "Use the r_eval_expr tool from the gptr MCP server to evaluate the R expression `sum(1:10)`. Put the printed result in `answer` and set `tool_used` to true.",
  model = "gpt-6-luna", sandbox = "read-only", cwd = wd, config = mcp,
  output_schema = schema_file,
  on_event = function(ev) {
    writeLines(jsonlite::toJSON(redact_ids(ev), auto_unbox = TRUE, null = "null"), raw)
    cat(sprintf("[%5.1fs] %s%s\n", as.numeric(Sys.time() - t0, units = "secs"), ev$type,
                if (!is.null(ev$item)) paste0(" ", ev$item$type, " (", ev$item$status %||% "", ")") else ""))
  },
  timeout = 240
)
close(raw)
cat("\nexit status:", res$exit_status, "\n")
cat("final text:", res$text, "\n")
parsed <- tryCatch(jsonlite::fromJSON(res$text), error = function(e) conditionMessage(e))
str(parsed)
cat("usage:", jsonlite::toJSON(res$usage, auto_unbox = TRUE), "\n")
cat("stderr (first 600 chars):", substr(redact_ids(res$stderr), 1, 600), "\n")
```

Observed output (`out_call2.txt`):

```text
[  3.0s] thread.started
[  3.1s] turn.started
[  8.6s] item.started mcp_tool_call (in_progress)
[  8.7s] item.completed mcp_tool_call (completed)
[ 10.0s] item.completed agent_message ()
[ 10.1s] turn.completed

exit status: 0 
final text: {"answer":"[1] 55","tool_used":true} 
List of 2
 $ answer   : chr "[1] 55"
 $ tool_used: logi TRUE
usage: {"input_tokens":58681,"cached_input_tokens":38400,"cache_write_input_tokens":0,"output_tokens":103,"reasoning_output_tokens":0} 
stderr (first 600 chars):  
```

Captured JSONL (`T08/proto/call2_events.jsonl`):

```json
{"type":"thread.started","thread_id":"<UUID>"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item_0","type":"mcp_tool_call","server":"gptr","tool":"r_eval_expr","arguments":{"code":"sum(1:10)"},"result":null,"error":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_0","type":"mcp_tool_call","server":"gptr","tool":"r_eval_expr","arguments":{"code":"sum(1:10)"},"result":{"content":[{"type":"text","text":"[1] 55"}],"structured_content":null},"error":null,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"{\"answer\":\"[1] 55\",\"tool_used\":true}"}}
{"type":"turn.completed","usage":{"input_tokens":58681,"cached_input_tokens":38400,"cache_write_input_tokens":0,"output_tokens":103,"reasoning_output_tokens":0}}
```

VERIFIED:
- MCP servers can be injected per run with TOML literal-string paths.
- `mcp_tool_call` items carry `server`, `tool`, `arguments` and `result.content`.
- The `--output-schema` result arrives as the `agent_message` text (valid JSON).
- The standalone MCP server also answered `initialize`, `tools/list` and `tools/call` when piped by hand (run log in the session; the protocol lines are the same as in §5.5).

### 5.4 Live call 3: `codex app-server` with a dynamic tool answered by the live R session (REAL model call 3 of 3)

JSON-RPC client over stdio (the previous researcher's file, re-verified, with `encoding = "UTF-8"` and UTF-8 marking added):

`T08/proto/appserver_client.R`

```r
# Minimal Codex app-server JSON-RPC client over stdio, in R (processx + jsonlite).
# No model calls are made by the functions in this file unless turn/start is sent.
suppressWarnings(suppressMessages({
  library(processx)
  library(jsonlite)
}))

to_json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
empty_obj <- function() structure(list(), names = character())

# Redact anything that looks like an identifier, email, path under HOME, or token.
redact <- function(x) {
  if (is.list(x)) return(lapply(x, redact))
  if (!is.character(x)) return(x)
  x <- gsub("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "<EMAIL>", x)
  x <- gsub("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", "<UUID>", x, ignore.case = TRUE)
  x <- gsub("eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}", "<JWT>", x)
  x <- gsub(path.expand("~"), "<HOME>", x, fixed = TRUE)
  x
}

codex_app_server <- function(config = character(), env = NULL, codex = Sys.which("codex")) {
  args <- c("app-server", "--listen", "stdio://")
  for (kv in config) args <- c(args, "-c", kv)
  p <- processx::process$new(codex, args, stdin = "|", stdout = "|", stderr = "|",
                             env = env, cleanup = TRUE, cleanup_tree = TRUE,
                             encoding = "UTF-8")
  self <- new.env(parent = emptyenv())
  self$p <- p
  self$buf <- ""
  self$next_id <- 0L
  self$inbox <- list()          # parsed messages not yet consumed
  self$log <- list()            # every message received, in order
  self$stderr <- character()

  self$send <- function(msg) {
    rest <- charToRaw(enc2utf8(paste0(to_json(msg), "\n")))   # write_input() is non-blocking and returns
    while (length(rest)) {                               # the unwritten bytes: loop (>8 KB messages)
      rest <- p$write_input(rest)
      if (length(rest)) { if (!p$is_alive()) stop("app-server exited"); Sys.sleep(0.005) }
    }
    invisible()
  }
  self$pump <- function(timeout_ms = 200) {
    p$poll_io(timeout_ms)
    err <- p$read_error()
    if (nzchar(err)) self$stderr <- c(self$stderr, err)
    out <- p$read_output()
    if (!nzchar(out)) return(invisible(0L))
    self$buf <- paste0(self$buf, out)
    lines <- strsplit(self$buf, "\n", fixed = TRUE)[[1]]
    complete <- endsWith(self$buf, "\n")
    if (!complete) {
      self$buf <- lines[length(lines)]
      lines <- lines[-length(lines)]
    } else {
      self$buf <- ""
    }
    n <- 0L
    for (ln in lines) {
      if (!nzchar(trimws(ln))) next
      Encoding(ln) <- "UTF-8"; msg <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(msg)) next
      self$inbox[[length(self$inbox) + 1L]] <- msg
      self$log[[length(self$log) + 1L]] <- msg
      n <- n + 1L
    }
    invisible(n)
  }
  # Send a request and wait for its response; server requests/notifications that
  # arrive meanwhile are passed to `on_message` (which may reply via self$send).
  self$request <- function(method, params = empty_obj(), timeout = 30, on_message = NULL) {
    self$next_id <- self$next_id + 1L
    id <- self$next_id
    self$send(list(method = method, id = id, params = params))
    deadline <- Sys.time() + timeout
    repeat {
      while (length(self$inbox) > 0L) {
        msg <- self$inbox[[1L]]
        self$inbox <- self$inbox[-1L]
        is_response <- is.null(msg$method) && !is.null(msg$id)
        if (is_response && identical(as.integer(msg$id), id)) return(msg)
        if (!is.null(on_message)) on_message(msg, self)
      }
      if (!p$is_alive() && length(self$inbox) == 0L) stop("app-server exited: ", paste(self$stderr, collapse = ""))
      if (Sys.time() > deadline) stop("timeout waiting for response to ", method)
      self$pump(200)
    }
  }
  self$notify <- function(method, params = empty_obj()) self$send(list(method = method, params = params))
  self$close <- function() {
    try(close(p$get_input_connection()), silent = TRUE)
    p$wait(2000)
    if (p$is_alive()) p$kill()
    invisible()
  }
  self
}
```

`T08/proto/run_call3_appserver_dynamic_tool.R`

```r
# NOTE: the live run crashed in the logging `cat()` because `msg$params$item` partially
# matched `itemId` (a string). Fixed below with `[[`; the fixed script was NOT re-run
# (model-call budget); see test_appserver_replay.R for the fixture-verified dispatcher.
# Real call 3 of 3: Codex app-server over stdio, with an experimental *dynamic tool*
# whose handler runs inside THIS R process (the live session), so the model can
# operate on in-memory objects. Pure R: processx + jsonlite.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto/appserver_client.R")
base <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto"
wd <- file.path(base, "sandbox3"); dir.create(wd, showWarnings = FALSE)

# A "big" in-memory object that exists only in this R session.
session_env <- new.env()
session_env$big_df <- data.frame(x = seq_len(123457), g = rep(letters[1:7], length.out = 123457))

r_eval_tool <- function(args) {
  out <- tryCatch({
    val <- eval(parse(text = args$code), envir = session_env)
    paste(utils::capture.output(print(val)), collapse = "\n")
  }, error = function(e) paste("Error:", conditionMessage(e)))
  list(contentItems = list(list(type = "inputText", text = out)), success = !startsWith(out, "Error:"))
}

log_file <- file(file.path(base, "call3_messages.jsonl"), "w")
t0 <- Sys.time()
stamp <- function() sprintf("[%5.1fs]", as.numeric(Sys.time() - t0, units = "secs"))
srv <- codex_app_server()
on.exit(srv$close(), add = TRUE)

deltas <- character()
turn_done <- NULL
handle <- function(msg, self) {
  writeLines(jsonlite::toJSON(redact(msg), auto_unbox = TRUE, null = "null"), log_file)
  m <- msg$method
  if (is.null(m)) return(invisible())
  is_request <- !is.null(msg$id)
  cat(stamp(), if (is_request) "SERVER REQUEST" else "notify", m,
      if (!is.null(msg[["params"]][["item"]][["type"]])) paste0("[", msg[["params"]][["item"]][["type"]], "]") else "", "\n")
  if (is_request && m == "item/tool/call") {
    cat("        -> tool", msg$params$tool, "args", jsonlite::toJSON(msg$params$arguments, auto_unbox = TRUE), "\n")
    res <- r_eval_tool(msg$params$arguments)
    self$send(list(id = msg$id, result = res))
  } else if (is_request && m %in% c("item/commandExecution/requestApproval", "item/fileChange/requestApproval")) {
    self$send(list(id = msg$id, result = list(decision = "decline")))
  } else if (is_request) {
    self$send(list(id = msg$id, error = list(code = -32601L, message = "not supported by gptr")))
  } else if (m == "item/agentMessage/delta") {
    deltas <<- c(deltas, msg$params$delta)
  } else if (m == "turn/completed") {
    turn_done <<- msg$params$turn
  }
}

r <- srv$request("initialize", list(
  clientInfo = list(name = "gptr", title = "gptr (R)", version = "0.0.0.9000"),
  capabilities = list(experimentalApi = TRUE)
), on_message = handle)
srv$notify("initialized")

r <- srv$request("thread/start", list(
  model = "gpt-6-luna",
  cwd = wd,
  approvalPolicy = "never",
  sandbox = "read-only",
  ephemeral = TRUE,
  developerInstructions = "You are running inside the user's R session via gptr. Prefer the r_eval tool for anything about R objects.",
  dynamicTools = list(list(
    type = "function",
    name = "r_eval",
    description = "Evaluate R code in the user's live R session and return the printed result.",
    inputSchema = list(
      type = "object",
      properties = list(code = list(type = "string", description = "R code to evaluate")),
      required = list("code"),
      additionalProperties = FALSE
    )
  ))
), on_message = handle, timeout = 60)
thread_id <- r$result$thread$id
cat(stamp(), "thread/start ok; result fields:", paste(names(r$result), collapse = ", "), "\n")

r <- srv$request("turn/start", list(
  threadId = thread_id,
  input = list(list(type = "text", text = "Use the r_eval tool to compute nrow(big_df) in my live R session. Reply with just the number.")),
  effort = "low"
), on_message = handle, timeout = 60)
cat(stamp(), "turn/start ok; status:", r$result$turn$status, "\n")

deadline <- Sys.time() + 240
while (is.null(turn_done) && Sys.time() < deadline) {
  srv$pump(200)
  while (length(srv$inbox) > 0L) { msg <- srv$inbox[[1L]]; srv$inbox <- srv$inbox[-1L]; handle(msg, srv) }
}
close(log_file)
cat("\nturn status:", turn_done$status, "\n")
cat("streamed agent text:", paste(deltas, collapse = ""), "\n")
if (!is.null(turn_done$error)) print(turn_done$error)
```

Observed console output. The repeated `mcpServer/startupStatus/updated` lines are condensed; they come from the user's own MCP servers in `~/.codex/config.toml`.

Observed output (`out_call3.txt`):

```text
[  0.8s] notify remoteControl/status/changed  
[  1.2s] notify account/updated  
[  1.2s] thread/start ok; result fields: thread, model, modelProvider, serviceTier, disabledPluginIds, cwd, runtimeWorkspaceRoots, instructionSources, approvalPolicy, approvalsReviewer, sandbox, activePermissionProfile, reasoningEffort, multiAgentMode 
[  1.2s] notify thread/started  
[  1.2s] notify mcpServer/startupStatus/updated      (x6, user's own MCP servers from ~/.codex/config.toml)
[  1.3s] notify thread/settings/updated  
[  1.3s] turn/start ok; status: inProgress 
[  1.5s] notify thread/status/changed  
[  1.5s] notify turn/started  
[  1.6s]..[2.4s] notify mcpServer/startupStatus/updated (x6)
[  4.0s] notify item/started [userMessage] 
[  4.0s] notify item/completed [userMessage] 
[  5.6s] notify item/started [dynamicToolCall] 
[  5.6s] SERVER REQUEST item/tool/call  
        -> tool r_eval args {"code":"nrow(big_df)"} 
[  5.6s] notify item/completed [dynamicToolCall] 
[  5.6s] notify thread/tokenUsage/updated  
[  5.7s] notify account/rateLimits/updated  
[  6.5s] notify item/started [agentMessage] 
Error in msg$params$item$type : $ operator is invalid for atomic vectors
Calls: handle -> cat
Execution halted
```

Key protocol messages captured in that run (`T08/proto/call3_messages.jsonl` lines 20–27, redacted, each line cut at 900 characters):

```json
{"method":"item/completed","params":{"item":{"type":"userMessage","id":"<UUID>","clientId":null,"content":[{"type":"text","text":"Use the r_eval tool to compute nrow(big_df) in my live R session. Reply with just the number.","text_elements":[]}]},"threadId":"<UUID>","turnId":"<UUID>","completedAtMs":1790732560096},"emittedAtMs":1790732560097}
{"method":"item/started","params":{"item":{"type":"dynamicToolCall","id":"exec-<UUID>","namespace":null,"tool":"r_eval","arguments":{"code":"nrow(big_df)"},"status":"inProgress","contentItems":null,"success":null,"durationMs":null},"threadId":"<UUID>","turnId":"<UUID>","startedAtMs":1790732561689},"emittedAtMs":1790732561690}
{"method":"item/tool/call","id":0,"params":{"threadId":"<UUID>","turnId":"<UUID>","callId":"exec-<UUID>","namespace":null,"tool":"r_eval","arguments":{"code":"nrow(big_df)"}}}
{"method":"item/completed","params":{"item":{"type":"dynamicToolCall","id":"exec-<UUID>","namespace":null,"tool":"r_eval","arguments":{"code":"nrow(big_df)"},"status":"completed","contentItems":[{"type":"inputText","text":"[1] 123457"}],"success":true,"durationMs":18},"threadId":"<UUID>","turnId":"<UUID>","completedAtMs":1790732561707},"emittedAtMs":1790732561708}
{"method":"thread/tokenUsage/updated","params":{"threadId":"<UUID>","turnId":"<UUID>","tokenUsage":{"total":{"totalTokens":19354,"inputTokens":19324,"cachedInputTokens":1792,"cacheWriteInputTokens":0,"outputTokens":30,"reasoningOutputTokens":0},"last":{"totalTokens":19354,"inputTokens":19324,"cachedInputTokens":1792,"cacheWriteInputTokens":0,"outputTokens":30,"reasoningOutputTokens":0},"modelContextWindow":258400}},"emittedAtMs":1790732561720}
{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","limitName":null,"normalModelSlug":null,"primary":{"usedPercent":45,"windowDurationMins":10080,"resetsAt":1791071630},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"individualLimit":null,"spendControlReached":null,"planType":"pro","rateLimitReachedType":null}},"emittedAtMs":1790732561720}
{"method":"item/started","params":{"item":{"type":"agentMessage","id":"msg_0f90ca712c200ee0016abc6912940c87d0b4697aa63d3da504","text":"","phase":"final_answer","memoryCitation":null,"delivery":null,"questions":null},"threadId":"<UUID>","turnId":"<UUID>","startedAtMs":1790732562576},"emittedAtMs":1790732562576}
{"method":"item/agentMessage/delta","params":{"threadId":"<UUID>","turnId":"<UUID>","itemId":"msg_0f90ca712c200ee0016abc6912940c87d0b4697aa63d3da504","delta":"123"},"emittedAtMs":1790732562576}
```

The dynamic-tool round trip is VERIFIED. The live model asked for `nrow(big_df)`, R evaluated it in `session_env` (an object that existed only in the parent R process) and replied `[1] 123457`. `item/completed` reports `success:true, durationMs:18`, and the final `agentMessage` (phase `final_answer`) began streaming `"123"`.

The script then crashed in its own logging line: `msg$params$item` partially matched the `itemId` string. The script was fixed to use `[[` but **not re-run**, to respect the 3-call budget. Instead, the dispatcher below was verified by replaying the captured log plus a schema-conformant synthetic tail (`turn/completed`):

`T08/proto/appserver_dispatch.R`

```r
# Reusable dispatcher for Codex app-server messages (JSON-RPC 2.0 without the
# "jsonrpc" field, newline-delimited on stdio). Uses `[[` (exact matching) only.
`%||%` <- function(x, y) if (is.null(x)) y else x

appserver_turn_state <- function() {
  st <- new.env(parent = emptyenv())
  st$text <- character(); st$items <- list(); st$turn <- NULL; st$usage <- NULL
  st$tool_calls <- list(); st$errors <- list(); st$rate_limits <- NULL
  st
}

# tools: named list of R functions(args) -> character (text result) ; errors become success=FALSE
# approve: function(kind, params) -> "accept" | "decline" | "cancel" (permission-mode hook)
appserver_dispatch <- function(msg, send, st, tools = list(), approve = function(kind, params) "decline",
                               on_text = NULL) {
  method <- msg[["method"]]
  params <- msg[["params"]]
  id <- msg[["id"]]
  if (is.null(method)) return(invisible("response"))           # a response to one of our requests
  if (!is.null(id)) {                                            # ---- server -> client REQUEST
    result <- switch(method,
      "item/tool/call" = {
        fn <- tools[[params[["tool"]]]]
        out <- if (is.null(fn)) list(text = paste("Unknown tool:", params[["tool"]]), ok = FALSE) else
          tryCatch(list(text = fn(params[["arguments"]]), ok = TRUE),
                   error = function(e) list(text = paste("Error:", conditionMessage(e)), ok = FALSE))
        st$tool_calls[[length(st$tool_calls) + 1L]] <- list(tool = params[["tool"]], arguments = params[["arguments"]], ok = out$ok)
        list(contentItems = list(list(type = "inputText", text = out$text)), success = out$ok)
      },
      "item/commandExecution/requestApproval" = list(decision = approve("command", params)),
      "item/fileChange/requestApproval"       = list(decision = approve("file", params)),
      "item/permissions/requestApproval"      = list(permissions = structure(list(), names = character())),
      "mcpServer/elicitation/request"         = list(action = "decline", content = NULL),
      NULL)
    if (is.null(result)) send(list(id = id, error = list(code = -32601L, message = paste("gptr does not handle", method))))
    else send(list(id = id, result = result))
    return(invisible("request"))
  }
  switch(method,                                                  # ---- NOTIFICATION
    "item/agentMessage/delta" = { st$text <- c(st$text, params[["delta"]]); if (!is.null(on_text)) on_text(params[["delta"]]) },
    "item/completed" = { it <- params[["item"]]; st$items[[it[["id"]]]] <- it },
    "thread/tokenUsage/updated" = { st$usage <- params[["tokenUsage"]] },
    "account/rateLimits/updated" = { st$rate_limits <- params[["rateLimits"]] },
    "error" = { st$errors[[length(st$errors) + 1L]] <- params[["error"]] },
    "turn/completed" = { st$turn <- params[["turn"]] },
    NULL)
  invisible("notification")
}

appserver_final_text <- function(st) {
  msgs <- Filter(function(it) identical(it[["type"]], "agentMessage"), st$items)
  final <- Filter(function(it) identical(it[["phase"]], "final_answer"), msgs)
  if (length(final)) return(final[[length(final)]][["text"]])
  if (length(msgs)) return(msgs[[length(msgs)]][["text"]])
  paste(st$text, collapse = "")
}
```

`T08/proto/test_appserver_replay.R`

```r
# Fixture replay: the real (redacted) message log captured in call 3, plus a
# schema-conformant synthetic tail (the live run's logging crashed on `$` partial
# matching right after the tool round trip, so the tail was not captured).
base <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto"
source(file.path(base, "appserver_dispatch.R"))
lines <- readLines(file.path(base, "call3_messages.jsonl"))
msgs <- lapply(lines, function(l) { Encoding(l) <- "UTF-8"; jsonlite::fromJSON(l, simplifyVector = FALSE) })
tail_msgs <- list(
  list(method = "item/agentMessage/delta", params = list(threadId = "t", turnId = "u", itemId = "msg_x", delta = "457")),
  list(method = "item/completed", params = list(threadId = "t", turnId = "u",
       item = list(type = "agentMessage", id = "msg_x", text = "123457", phase = "final_answer"))),
  list(method = "thread/tokenUsage/updated", params = list(threadId = "t", turnId = "u",
       tokenUsage = list(total = list(totalTokens = 19500L, inputTokens = 19450L, cachedInputTokens = 1792L, outputTokens = 50L)))),
  list(method = "turn/completed", params = list(threadId = "t", turn = list(id = "u", status = "completed", items = list(), error = NULL)))
)
session_env <- new.env(); session_env$big_df <- data.frame(x = seq_len(123457))
tools <- list(r_eval = function(args) paste(capture.output(print(eval(parse(text = args[["code"]]), session_env))), collapse = "\n"))
sent <- list(); send <- function(x) sent[[length(sent) + 1L]] <<- x
st <- appserver_turn_state()
kinds <- vapply(c(msgs, tail_msgs), function(m) appserver_dispatch(m, send, st, tools = tools), "")
print(table(kinds))
cat("replies sent to server:\n"); cat(jsonlite::toJSON(sent, auto_unbox = TRUE, pretty = TRUE), "\n")
cat("turn status:", st$turn[["status"]], "| final text:", appserver_final_text(st),
    "| streamed:", paste(st$text, collapse = ""), "| tool calls:", length(st$tool_calls), "\n")
cat("rate limit window (min):", st$rate_limits[["primary"]][["windowDurationMins"]], "used %:", st$rate_limits[["primary"]][["usedPercent"]], "\n")
```

Observed output (`out_test_appserver_replay.txt`):

```text
kinds
notification      request 
          30            1 
replies sent to server:
[
  {
    "id": 0,
    "result": {
      "contentItems": [
        {
          "type": "inputText",
          "text": "[1] 123457"
        }
      ],
      "success": true
    }
  }
] 
turn status: completed | final text: 123457 | streamed: 123457 | tool calls: 1 
rate limit window (min): 10080 used %: 45 
```

Handshake-only session (no model call): initialize, account, rate limits and model catalog. `T08/proto/appserver_handshake.R` is the previous researcher's script with paths updated. The output is redacted and truncated before the MCP server list:

Observed output (`out_appserver_handshake.txt`):

```text

## initialize response 
{
  "id": 1,
  "result": {
    "userAgent": "gptr/0.157.0 (Mac OS 26.6.2; arm64) unknown (gptr; 0.0.0.9000)",
    "codexHome": "<HOME>/.codex",
    "platformFamily": "unix",
    "platformOs": "macos"
  }
} 

## account/read response 
{
  "id": 2,
  "result": {
    "account": {
      "type": "chatgpt",
      "email": "<EMAIL>",
      "planType": "pro"
    },
    "requiresOpenaiAuth": true,
    "workspaceRouting": {
      "chatgptAccountId": "<UUID>",
      "backendOrigin": "https://chatgpt.com",
      "accountRoutingOverride": "NO_CONSTRAINT"
    }
  }
} 

## account/rateLimits/read response 
{
  "id": 3,
  "result": {
    "ordinaryUsageAllowed": true,
    "rateLimits": {
      "limitId": "codex",
      "limitName": null,
      "normalModelSlug": null,
      "primary": {
        "usedPercent": 45,
        "windowDurationMins": 10080,
        "resetsAt": 1791071630
      },
      "secondary": null,
      "credits": {
        "hasCredits": false,
        "unlimited": false,
        "balance": "0"
      },
      "individualLimit": null,
      "spendControlReached": false,
      "planType": "pro",
      "rateLimitReachedType": null
    },
    "rateLimitsByLimitId": {
      "codex": {
        "limitId": "codex",
        "limitName": null,
        "normalModelSlug": null,
        "primary": {
          "usedPercent": 45,
          "windowDurationMins": 10080,
          "resetsAt": 1791071630
        },
        "secondary": null,
        "credits": {
          "hasCredits": false,
          "unlimited": false,
          "balance": "0"
        },
        "individualLimit": null,
        "spendControlReached": false,
        "planType": "pro",
        "rateLimitReachedType": null
      }
    },
    "rateLimitResetCredits": {
      "availableCount": 1,
      "credits": [
        {
          "id": "RateLimitResetCredit_<ID>",
          "resetType": "codexRateLimits",
          "status": "available",
          "grantedAt": <TS>,
          "expiresAt": <TS>,
          "title": "Full reset",
          "description": "Thanks for using Codex! You've been granted one free rate limit reset."
        }
      ]
    },
    "accountId": "<UUID>",
    "rateLimitUpsell": null
  }
} 

## model/list (summarised) 
[
  {
    "id": "gpt-6-astra",
    "displayName": "GPT-6-Astra",
    "isDefault": true,
    "defaultReasoningEffort": "medium",
    "efforts": ["low", "medium", "high", "xhigh", "max", "ultra"],
    "inputModalities": ["text", "image"]
  },
  {
    "id": "gpt-6-sol",
    "displayName": "GPT-6-Sol",
    "isDefault": false,
    "defaultReasoningEffort": "medium",
    "efforts": ["low", "medium", "high", "xhigh", "max", "ultra"],
    "inputModalities": ["text", "image"]
  },
  {
    "id": "gpt-6-luna",
    "displayName": "GPT-6-Luna",
    "isDefault": false,
    "defaultReasoningEffort": "medium",
    "efforts": ["low", "medium", "high", "xhigh", "max"],
    "inputModalities": ["text", "image"]
  },
  {
    "id": "gpt-5.6-sol",
    "displayName": "GPT-5.6-Sol",
    "isDefault": false,
    "defaultReasoningEffort": "low",
    "efforts": ["low", "medium", "high", "xhigh", "max", "ultra"],
    "inputModalities": ["text", "image"]
  },
  {
    "id": "gpt-5.6-terra",
    "displayName": "GPT-5.6-Terra",
    "isDefault": false,
    "defaultReasoningEffort": "medium",
    "efforts": ["low", "medium", "high", "xhigh", "max", "ultra"],
    "inputModalities": ["text", "image"]
  },
  {
    "id": "gpt-5.6-luna",
    "displayName": "GPT-5.6-Luna",
    "isDefault": false,
    "defaultReasoningEffort": "medium",
    "efforts": ["low", "medium", "high", "xhigh", "max"],
    "inputModalities": ["text", "image"]
  },
  {
    "id": "gpt-5.5",
    "displayName": "GPT-5.5",
    "isDefault": false,
    "defaultReasoningEffort": "medium",
    "efforts": ["low", "medium", "high", "xhigh"],
    "inputModalities": ["text", "image"]
  }
] 
fields of first model entry: id, model, upgrade, upgradeInfo, availabilityNux, displayName, description, modelSpecialty, hidden, supportedReasoningEfforts, defaultReasoningEffort, inputModalities, supportsPersonality, multiAgentVersion, additionalSpeedTiers, serviceTiers, defaultServiceTier, availableAccessPrograms, isDefault 

```

### 5.5 In-session MCP server over streamable HTTP, consumed by Codex (no model call)

This proves that tools served *from the live R session* reach Codex while R waits on Codex's pipe. The same bridge serves `codex exec` and `claude -p`.

`T08/proto/test_inprocess_http_mcp.R`

```r
# In-session MCP server (streamable HTTP, JSON-response mode) served by httpuv from
# THIS R process, consumed by `codex app-server`. The R main loop pumps both the
# app-server stdio pipe and httpuv (httpuv::service), so tool calls execute in the
# live session environment. NO model call is made: we use thread/start (no turn),
# mcpServerStatus/list and mcpServer/tool/call.
base <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto"
source(file.path(base, "appserver_client.R"))
`%||%` <- function(x, y) if (is.null(x)) y else x

live_env <- new.env()
live_env$seurat_like <- list(cells = 250000L, genes = 33538L)   # stands in for a huge in-memory object
hits <- 0L
mcp_tools <- list(list(
  name = "r_eval", description = "Evaluate R code in the user's live gptr session.",
  inputSchema = list(type = "object", properties = list(code = list(type = "string")),
                     required = list("code"), additionalProperties = FALSE)))
mcp_handle <- function(msg) {
  m <- msg[["method"]]; id <- msg[["id"]]
  res <- switch(m,
    "initialize" = list(protocolVersion = msg[["params"]][["protocolVersion"]] %||% "2025-06-18",
                        capabilities = list(tools = list(listChanged = FALSE)),
                        serverInfo = list(name = "gptr-live", version = "0.0.1")),
    "tools/list" = list(tools = mcp_tools),
    "tools/call" = {
      hits <<- hits + 1L
      code <- msg[["params"]][["arguments"]][["code"]]
      txt <- tryCatch(paste(capture.output(print(eval(parse(text = code), live_env))), collapse = "\n"),
                      error = function(e) paste("Error:", conditionMessage(e)))
      list(content = list(list(type = "text", text = txt)), isError = startsWith(txt, "Error:"))
    },
    "ping" = structure(list(), names = character()),
    NULL)
  if (is.null(id)) return(NULL)                      # notification
  if (is.null(res)) return(list(jsonrpc = "2.0", id = id, error = list(code = -32601L, message = "not found")))
  list(jsonrpc = "2.0", id = id, result = res)
}
port <- httpuv::randomPort()
server <- httpuv::startServer("127.0.0.1", port, list(call = function(req) {
  if (req$REQUEST_METHOD != "POST") return(list(status = 405L, headers = list(Allow = "POST"), body = ""))
  txt <- rawToChar(req$rook.input$read()); Encoding(txt) <- "UTF-8"
  msg <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  out <- mcp_handle(msg)
  if (is.null(out)) return(list(status = 202L, headers = list(), body = ""))
  list(status = 200L, headers = list(`Content-Type` = "application/json", `Mcp-Session-Id` = "gptr-1"),
       body = as.character(jsonlite::toJSON(out, auto_unbox = TRUE, null = "null")))
}))
on.exit(httpuv::stopServer(server), add = TRUE)

srv <- codex_app_server(config = c(
  sprintf('mcp_servers.gptr_live.url="http://127.0.0.1:%d/mcp"', port),
  'mcp_servers.gptr_live.default_tools_approval_mode="approve"'))
on.exit(srv$close(), add = TRUE)
# While waiting on app-server responses, also service httpuv so the MCP server can answer.
pump_both <- function(msg, self) invisible(NULL)
orig_pump <- srv$pump
srv$pump <- function(timeout_ms = 200) { httpuv::service(20); orig_pump(timeout_ms) }

srv$request("initialize", list(clientInfo = list(name = "gptr", title = "gptr (R)", version = "0.0.0.9000"),
                               capabilities = list(experimentalApi = TRUE)))
srv$notify("initialized")
th <- srv$request("thread/start", list(model = "gpt-6-luna", cwd = base, approvalPolicy = "never",
                                       sandbox = "read-only", ephemeral = TRUE), timeout = 60)
thread_id <- th$result$thread$id
st <- srv$request("mcpServerStatus/list", list(detail = "toolsAndAuthOnly"), timeout = 60)
mine <- Filter(function(s) identical(s[["name"]], "gptr_live"), st$result$data)[[1]]
cat("gptr_live status: tools =", paste(names(mine[["tools"]]), collapse = ", "), "\n")
call <- srv$request("mcpServer/tool/call", list(threadId = thread_id, server = "gptr_live", tool = "r_eval",
                                                arguments = list(code = "seurat_like$cells * 2L")), timeout = 60)
cat("mcpServer/tool/call result:", jsonlite::toJSON(call$result, auto_unbox = TRUE), "\n")
cat("tool executions observed in THIS R session:", hits, "\n")
```

Observed output (`out_test_inprocess_http_mcp.txt`):

```text
gptr_live status: tools = r_eval 
mcpServer/tool/call result: {"content":[{"type":"text","text":"[1] 500000"}],"isError":false} 
tool executions observed in THIS R session: 1 
```

### 5.6 `codex_exec()` against a fake `codex` executable (offline, UTF-8 both ways)

`T08/proto/fake_codex.R`

```r
# Fake `codex exec --json -`: reads the prompt from stdin, replays call-1 events,
# adds a non-ASCII agent message, and splits output into odd-sized writes.
args <- commandArgs(trailingOnly = TRUE)
prompt <- readLines(file("stdin", encoding = "UTF-8"), warn = FALSE)
ev <- readLines("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto/call1_events.jsonl")
msg <- sprintf('{"type":"item.completed","item":{"id":"item_9","type":"agent_message","text":"echo: %s %s"}}', paste(prompt, collapse = " "), `Encoding<-`(rawToChar(as.raw(c(0xc3, 0xa9, 0xe2, 0x9c, 0x93))), "UTF-8"))
out <- paste0(paste(c(ev[1:4], msg, ev[6]), collapse = "\n"), "\n")
b <- charToRaw(enc2utf8(out)); i <- 1L
while (i <= length(b)) { j <- min(length(b), i + 37L); writeLines(rawToChar(b[i:j]), stdout(), sep = "", useBytes = TRUE); flush(stdout()); Sys.sleep(0.01); i <- j + 1L }
cat("args:", paste(args, collapse = " "), "\n", file = stderr())
```

`T08/proto/test_codex_exec_fake.R`

```r
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto/codex_exec.R")
rscript <- file.path(R.home("bin"), "Rscript")
fake <- c(rscript, "--vanilla", "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto/fake_codex.R")
res <- codex_exec(paste("hello", intToUtf8(c(0x6c34, 0x3067))), model = "gpt-6-luna", sandbox = "read-only",
                  config = list(model_reasoning_effort = '"low"'), codex = fake, timeout = 60)
cat("locale:", Sys.getlocale("LC_CTYPE"), "| exit:", res$exit_status, "| events:", paste(res$event_types, collapse = ","), "\n")
cat("final text bytes ok:", grepl(intToUtf8(c(0xe9, 0x2713)), res$text, fixed = TRUE),
    "| prompt round-tripped via stdin:", grepl(intToUtf8(c(0x6c34, 0x3067)), res$text, fixed = TRUE), "\n")
cat("usage:", jsonlite::toJSON(res$usage, auto_unbox = TRUE), "\n")
cat("argv seen by fake:", res$stderr)
```

Observed output (`out_test_codex_exec_fake.txt`):

```text
locale: C | exit: 0 | events: thread.started,turn.started,item.started,item.completed,item.completed,turn.completed 
final text bytes ok: TRUE | prompt round-tripped via stdin: TRUE 
usage: {"input_tokens":38544,"cached_input_tokens":30208,"cache_write_input_tokens":0,"output_tokens":35,"reasoning_output_tokens":0} 
argv seen by fake: args: exec --json -m gpt-6-luna -s read-only --skip-git-repo-check --ephemeral -c model_reasoning_effort="low" - 
```

In the C locale the non-ASCII prompt (`水で`) and the non-ASCII reply (`é✓`) both survive. VERIFIED. (In `en_US.UTF-8` the result is also TRUE/TRUE.)

Verification addendum: the same fake with a 50,008-character prompt echoed only about 8,200 characters back when `codex_exec()` used a single `p$write_input()` call (processx 3.8.6, macOS). With `proc_write_all()` (now in §5.1) the whole prompt arrived. A 2 MB write straight to `sh -c 'sleep 1; wc -c'` showed the same thing: the first `write_input()` returned 1,991,808 unwritten bytes, so the child received 8,192.

### 5.7 Responses and Chat Completions: builders, SSE parser, accumulators, transport (offline)

`T08/proto/openai_stream.R`

```r
# OpenAI Responses + Chat Completions request builders and SSE stream accumulators.
# Pure R: jsonlite (+ httr2 for transport). Use `[[` everywhere: `$` does partial
# matching on lists (msg$params$item silently matches `itemId`).

`%||%` <- function(x, y) if (is.null(x)) y else x

# Always mark JSON text as UTF-8 before parsing: in a non-UTF-8 locale (LANG unset,
# e.g. Rscript --vanilla under cron/CI, or LANG=C) jsonlite::fromJSON() on an
# unmarked string turns UTF-8 bytes into literal "<c3><a9>" text (verified).
json_parse <- function(txt) {
  Encoding(txt) <- "UTF-8"
  jsonlite::fromJSON(txt, simplifyVector = FALSE)
}

# ---------------------------------------------------------------- SSE framing
# Incremental SSE parser over raw bytes. Splits only on blank lines, so UTF-8
# multi-byte characters split across network chunks are reassembled correctly.
sse_parser <- function() {
  buf <- raw(0); held_cr <- raw(0)
  CR <- as.raw(13L); LF <- as.raw(10L)
  normalise_eol <- function(b) {                        # CRLF -> LF, lone CR -> LF
    cr <- which(b == CR)
    if (!length(cr)) return(b)
    n <- length(b)
    crlf <- cr < n & b[pmin(cr + 1L, n)] == LF
    b[cr[!crlf]] <- LF
    if (any(crlf)) b <- b[-cr[crlf]]
    b
  }
  # Call with final = TRUE at end of stream to flush a held CR and a last event
  # that lacks its terminating blank line (as the official SIWC devkit does).
  function(bytes = raw(0), final = FALSE) {
    if (is.character(bytes)) bytes <- charToRaw(enc2utf8(bytes))
    bytes <- c(held_cr, bytes); held_cr <<- raw(0)
    n <- length(bytes)
    if (!final && n && bytes[n] == CR) { held_cr <<- CR; bytes <- bytes[-n] }  # CRLF may be split across chunks
    buf <<- c(buf, normalise_eol(bytes))
    if (final && length(buf)) buf <<- c(buf, LF, LF)
    out <- list()
    repeat {
      n <- length(buf)
      if (n < 2L) break
      hit <- which(buf[-n] == as.raw(10L) & buf[-1L] == as.raw(10L))
      if (!length(hit)) break
      k <- hit[1L]
      block <- if (k > 1L) rawToChar(buf[seq_len(k - 1L)]) else ""
      buf <<- if (k + 2L <= n) buf[(k + 2L):n] else raw(0)
      Encoding(block) <- "UTF-8"
      ev <- list(event = NULL, data = character(), id = NULL)
      for (ln in strsplit(block, "\n", fixed = TRUE)[[1L]]) {
        if (!nzchar(ln) || startsWith(ln, ":")) next     # comment / keep-alive
        pos <- regexpr(":", ln, fixed = TRUE)
        field <- if (pos > 0) substr(ln, 1L, pos - 1L) else ln
        value <- if (pos > 0) sub("^ ", "", substr(ln, pos + 1L, nchar(ln))) else ""
        if (field == "data") ev$data <- c(ev$data, value)
        else if (field == "event") ev$event <- value
        else if (field == "id") ev$id <- value
      }
      if (length(ev$data)) { ev$data <- paste(ev$data, collapse = "\n"); out[[length(out) + 1L]] <- ev }
    }
    out
  }
}

# ---------------------------------------------------------------- Responses API
# plan_mode = TRUE applies the "ChatGPT plan usage" (Sign in with ChatGPT) contract:
# store=false, stream=true, no system-role items, and none of the unsupported fields.
openai_responses_body <- function(model, input, instructions = NULL, tools = NULL,
                                  tool_choice = NULL, parallel_tool_calls = NULL,
                                  reasoning_effort = NULL, reasoning_summary = NULL,
                                  text_format = NULL, verbosity = NULL,
                                  max_output_tokens = NULL, temperature = NULL,
                                  prompt_cache_key = NULL, store = FALSE, stream = TRUE,
                                  include = NULL, truncation = NULL, plan_mode = FALSE) {
  body <- list(model = model, input = input, store = store, stream = stream)
  body$instructions <- instructions
  body$tools <- tools
  body$tool_choice <- tool_choice
  body$parallel_tool_calls <- parallel_tool_calls
  if (!is.null(reasoning_effort) || !is.null(reasoning_summary))
    body$reasoning <- Filter(Negate(is.null), list(effort = reasoning_effort, summary = reasoning_summary))
  if (!is.null(text_format) || !is.null(verbosity))
    body$text <- Filter(Negate(is.null), list(format = text_format, verbosity = verbosity))
  body$max_output_tokens <- max_output_tokens
  body$temperature <- temperature
  body$prompt_cache_key <- prompt_cache_key
  body$include <- include
  body$truncation <- truncation
  if (isTRUE(plan_mode)) {
    body$store <- FALSE; body$stream <- TRUE
    unsupported <- c("background", "conversation", "max_output_tokens", "max_tool_calls", "metadata",
                     "moderation", "multi_agent", "prompt", "prompt_cache_retention", "safety_identifier",
                     "temperature", "top_logprobs", "top_p", "truncation", "user", "previous_response_id")
    body[intersect(names(body), unsupported)] <- NULL
    is_sys <- vapply(body$input, function(it) identical(it[["role"]], "system"), logical(1))
    if (any(is_sys)) stop("plan mode rejects role='system' input items; use `instructions` or role='developer'")
  }
  body
}

function_tool <- function(name, description, parameters, strict = NULL) {
  Filter(Negate(is.null), list(type = "function", name = name, description = description,
                              parameters = parameters, strict = strict))
}
namespace_tool <- function(name, description, tools) {
  list(type = "namespace", name = name, description = description, tools = tools)
}

responses_accumulator <- function(on_text = NULL, on_reasoning = NULL) {
  st <- new.env(parent = emptyenv())
  st$items <- list(); st$text <- list(); st$args <- list(); st$summary <- list()
  st$response_id <- NULL; st$status <- NULL; st$usage <- NULL; st$error <- NULL
  st$incomplete_reason <- NULL; st$terminal <- FALSE
  key <- function(i) as.character(i)
  handle <- function(ev) {
    type <- ev[["type"]] %||% ""
    oi <- key(ev[["output_index"]] %||% -1L)
    switch(type,
      "response.created" = { st$response_id <- ev[["response"]][["id"]] },
      "response.output_item.added" = { st$items[[oi]] <- ev[["item"]] },
      "response.output_text.delta" = {
        st$text[[oi]] <- paste0(st$text[[oi]] %||% "", ev[["delta"]])
        if (!is.null(on_text)) on_text(ev[["delta"]])
      },
      "response.refusal.delta" = { st$text[[oi]] <- paste0(st$text[[oi]] %||% "", ev[["delta"]]) },
      "response.reasoning_summary_text.delta" = {
        st$summary[[oi]] <- paste0(st$summary[[oi]] %||% "", ev[["delta"]])
        if (!is.null(on_reasoning)) on_reasoning(ev[["delta"]])
      },
      "response.function_call_arguments.delta" = { st$args[[oi]] <- paste0(st$args[[oi]] %||% "", ev[["delta"]]) },
      "response.function_call_arguments.done" = { st$args[[oi]] <- ev[["arguments"]] },
      "response.output_item.done" = { st$items[[oi]] <- ev[["item"]] },   # authoritative (incl. encrypted_content)
      "response.completed" = , "response.incomplete" = {
        r <- ev[["response"]]
        st$terminal <- TRUE; st$status <- r[["status"]]; st$usage <- r[["usage"]]
        st$incomplete_reason <- r[["incomplete_details"]][["reason"]]
        # Backfill from the terminal response: (a) items never sent as output_item.done;
        # (b) reasoning items whose .done copy lacks encrypted_content (Azure quirk, Pi #6409).
        ids <- vapply(st$items, function(it) it[["id"]] %||% "", "")
        for (i in seq_along(r[["output"]])) {
          it <- r[["output"]][[i]]; k <- key(i - 1L)
          j <- match(it[["id"]] %||% NA_character_, ids)
          if (is.na(j)) { if (is.null(st$items[[k]])) st$items[[k]] <- it }
          else if (identical(it[["type"]], "reasoning") && is.null(st$items[[j]][["encrypted_content"]]) &&
                   !is.null(it[["encrypted_content"]])) st$items[[j]][["encrypted_content"]] <- it[["encrypted_content"]]
        }
      },
      "response.failed" = {
        st$terminal <- TRUE; st$status <- "failed"; st$error <- ev[["response"]][["error"]]
      },
      "error" = { st$terminal <- TRUE; st$status <- "error";
                  st$error <- list(code = ev[["code"]], message = ev[["message"]], param = ev[["param"]]) },
      NULL)
    invisible(NULL)
  }
  result <- function() {
    idx <- order(as.integer(names(st$items)))
    items <- unname(st$items[idx])
    types <- vapply(items, function(it) it[["type"]] %||% "", "")
    msg_text <- vapply(items[types == "message"], function(it)
      paste(vapply(it[["content"]], function(c) c[["text"]] %||% c[["refusal"]] %||% "", ""), collapse = ""), "")
    calls <- lapply(items[types == "function_call"], function(it) list(
      call_id = it[["call_id"]], name = it[["name"]], namespace = it[["namespace"]],
      arguments = json_parse(it[["arguments"]] %||% "{}")))
    list(response_id = st$response_id, status = st$status, terminal = st$terminal,
         incomplete_reason = st$incomplete_reason, error = st$error,
         text = paste(msg_text, collapse = "\n"), tool_calls = calls,
         output_items = items, usage = st$usage)
  }
  list(handle = handle, result = result)
}

# Items to append to the next request's `input` for stateless (store=false) replay.
# Keep reasoning items whole (encrypted_content) and assistant `phase`.
responses_replay_items <- function(output_items) {
  lapply(output_items, function(it) {
    switch(it[["type"]],
      reasoning = it[intersect(names(it), c("type", "id", "summary", "encrypted_content", "content"))],
      message = it[intersect(names(it), c("type", "id", "role", "content", "phase", "status"))],
      function_call = it[intersect(names(it), c("type", "id", "call_id", "name", "namespace", "arguments", "status"))],
      it)
  })
}
function_call_output <- function(call_id, output) {
  list(type = "function_call_output", call_id = call_id, output = output)
}

# ---------------------------------------------------------------- Chat Completions
chat_accumulator <- function(on_text = NULL) {
  st <- new.env(parent = emptyenv())
  st$content <- ""; st$calls <- list(); st$finish <- NULL; st$usage <- NULL; st$done <- FALSE; st$id <- NULL
  handle <- function(data) {
    if (identical(data, "[DONE]")) { st$done <- TRUE; return(invisible()) }
    ch <- json_parse(data)
    st$id <- ch[["id"]] %||% st$id
    if (!is.null(ch[["usage"]])) st$usage <- ch[["usage"]]
    for (choice in ch[["choices"]]) {
      d <- choice[["delta"]]
      if (!is.null(d[["content"]])) { st$content <- paste0(st$content, d[["content"]]); if (!is.null(on_text)) on_text(d[["content"]]) }
      for (tc in d[["tool_calls"]]) {
        k <- as.character(tc[["index"]])
        cur <- st$calls[[k]] %||% list(id = NULL, name = "", arguments = "")
        if (!is.null(tc[["id"]])) cur$id <- tc[["id"]]
        fn <- tc[["function"]]
        if (!is.null(fn[["name"]])) cur$name <- paste0(cur$name, fn[["name"]])
        if (!is.null(fn[["arguments"]])) cur$arguments <- paste0(cur$arguments, fn[["arguments"]])
        st$calls[[k]] <- cur
      }
      if (!is.null(choice[["finish_reason"]])) st$finish <- choice[["finish_reason"]]
    }
    invisible()
  }
  result <- function() {
    calls <- unname(st$calls[order(as.integer(names(st$calls)))])
    list(id = st$id, content = st$content, finish_reason = st$finish, done = st$done, usage = st$usage,
         tool_calls = lapply(calls, function(cl) list(id = cl$id, name = cl$name,
           arguments = json_parse(if (nzchar(cl$arguments)) cl$arguments else "{}"))))
  }
  list(handle = handle, result = result)
}

# ---------------------------------------------------------------- transport (httr2)
openai_stream <- function(url, body, token, on_event, extra_headers = list(), timeout = 600) {
  req <- httr2::request(url)
  req <- httr2::req_headers(req, Authorization = paste("Bearer", token),
                            `Content-Type` = "application/json", Accept = "text/event-stream",
                            `X-Client-Request-Id` = extra_headers[["X-Client-Request-Id"]] %||% NULL,
                            .redact = "Authorization")
  req <- httr2::req_body_raw(req, jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA), "application/json")
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)   # handle status ourselves
  resp <- httr2::req_perform_connection(req)
  on.exit(close(resp), add = TRUE)
  status <- httr2::resp_status(resp)
  if (status >= 400) {
    body_txt <- httr2::resp_body_string(resp, encoding = "UTF-8")
    return(list(ok = FALSE, status = status, body = body_txt,
                request_id = httr2::resp_header(resp, "x-request-id"),
                retry_after = httr2::resp_header(resp, "retry-after")))
  }
  repeat {
    ev <- httr2::resp_stream_sse(resp)
    if (is.null(ev)) break
    Encoding(ev$data) <- "UTF-8"
    on_event(ev)
  }
  list(ok = TRUE, status = status, request_id = httr2::resp_header(resp, "x-request-id"),
       ratelimit = httr2::resp_headers(resp, "^x-ratelimit-"))
}

# Variant: raw chunks + our own SSE parser. Unlike resp_stream_sse() it flushes a final
# event that lacks its terminating blank line (parse(final = TRUE)). Both variants handled
# CR-only framing and a missing Content-Type in httr2 1.2.2/1.3.0 (verification test).
openai_stream_raw <- function(url, body, token, on_event, timeout = 600, kb = 16) {
  req <- httr2::request(url)
  req <- httr2::req_headers(req, Authorization = paste("Bearer", token), Accept = "text/event-stream",
                            .redact = "Authorization")
  req <- httr2::req_body_raw(req, jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA), "application/json")
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- httr2::req_perform_connection(req)
  on.exit(close(resp), add = TRUE)
  if (httr2::resp_status(resp) >= 400)
    return(list(ok = FALSE, status = httr2::resp_status(resp), body = httr2::resp_body_string(resp, encoding = "UTF-8")))
  parse <- sse_parser(); n <- 0L
  while (!httr2::resp_stream_is_complete(resp)) {
    for (ev in parse(httr2::resp_stream_raw(resp, kb = kb))) { n <- n + 1L; on_event(ev) }
  }
  for (ev in parse(final = TRUE)) { n <- n + 1L; on_event(ev) }
  list(ok = TRUE, status = httr2::resp_status(resp), events = n, request_id = httr2::resp_header(resp, "x-request-id"))
}
```

`T08/proto/make_fixtures.R`

```r
# Build SSE fixtures that follow the documented event shapes
# (developers.openai.com/api/reference/resources/responses/streaming-events and
#  .../chat/subresources/completions/streaming-events). No network, no API calls.
base <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto"
j <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
sse <- function(ev) paste0("event: ", ev$type, "\n", "data: ", j(ev), "\n\n")
seq_n <- 0L
ev <- function(...) { seq_n <<- seq_n + 1L; x <- list(...); x$sequence_number <- seq_n; x }

resp_skel <- function(status, output = list(), usage = NULL) list(
  id = "resp_fixture1", object = "response", created_at = 1790000000, status = status,
  error = NULL, incomplete_details = NULL, model = "gpt-6-luna", output = output,
  parallel_tool_calls = TRUE, store = FALSE, tool_choice = "auto", usage = usage
)
reasoning_done <- list(id = "rs_fixture1", type = "reasoning",
  summary = list(list(type = "summary_text", text = "**Planning** Need nrow of the data.")),
  encrypted_content = "gAAAAB-fixture-opaque-blob==", status = "completed")
fc_done <- list(id = "fc_fixture1", type = "function_call", status = "completed",
  call_id = "call_fixture1", name = "r_eval", arguments = "{\"code\":\"nrow(big_df)\"}")
msg_done <- list(id = "msg_fixture1", type = "message", role = "assistant", status = "completed",
  phase = "commentary",
  content = list(list(type = "output_text", text = "Checking the data frame.", annotations = list(), logprobs = list())))

events <- list(
  ev(type = "response.created", response = resp_skel("in_progress")),
  ev(type = "response.in_progress", response = resp_skel("in_progress")),
  ev(type = "response.output_item.added", output_index = 0L,
     item = list(id = "rs_fixture1", type = "reasoning", summary = list(), status = "in_progress")),
  ev(type = "response.reasoning_summary_part.added", item_id = "rs_fixture1", output_index = 0L, summary_index = 0L,
     part = list(type = "summary_text", text = "")),
  ev(type = "response.reasoning_summary_text.delta", item_id = "rs_fixture1", output_index = 0L, summary_index = 0L,
     delta = "**Planning** Need nrow "),
  ev(type = "response.reasoning_summary_text.delta", item_id = "rs_fixture1", output_index = 0L, summary_index = 0L,
     delta = "of the data."),
  ev(type = "response.reasoning_summary_part.done", item_id = "rs_fixture1", output_index = 0L, summary_index = 0L,
     part = list(type = "summary_text", text = "**Planning** Need nrow of the data.")),
  ev(type = "response.output_item.done", output_index = 0L, item = reasoning_done),
  ev(type = "response.output_item.added", output_index = 1L,
     item = list(id = "msg_fixture1", type = "message", role = "assistant", status = "in_progress", phase = "commentary", content = list())),
  ev(type = "response.content_part.added", item_id = "msg_fixture1", output_index = 1L, content_index = 0L,
     part = list(type = "output_text", text = "", annotations = list())),
  ev(type = "response.output_text.delta", item_id = "msg_fixture1", output_index = 1L, content_index = 0L,
     delta = "Checking the ", logprobs = list()),
  ev(type = "response.output_text.delta", item_id = "msg_fixture1", output_index = 1L, content_index = 0L,
     delta = paste0("data frame ", intToUtf8(c(0xe9, 0xe8)), " ", intToUtf8(0x2713), "."), logprobs = list()),
  ev(type = "response.output_text.done", item_id = "msg_fixture1", output_index = 1L, content_index = 0L,
     text = "Checking the data frame.", logprobs = list()),
  ev(type = "response.output_item.done", output_index = 1L, item = msg_done),
  ev(type = "response.output_item.added", output_index = 2L,
     item = list(id = "fc_fixture1", type = "function_call", status = "in_progress", call_id = "call_fixture1", name = "r_eval", arguments = "")),
  ev(type = "response.function_call_arguments.delta", item_id = "fc_fixture1", output_index = 2L, delta = "{\"code\":"),
  ev(type = "response.function_call_arguments.delta", item_id = "fc_fixture1", output_index = 2L, delta = "\"nrow(big_df)\"}"),
  ev(type = "response.function_call_arguments.done", item_id = "fc_fixture1", output_index = 2L, arguments = "{\"code\":\"nrow(big_df)\"}"),
  ev(type = "response.output_item.done", output_index = 2L, item = fc_done),
  ev(type = "response.completed", response = resp_skel("completed", list(reasoning_done, msg_done, fc_done),
     usage = list(input_tokens = 812L, input_tokens_details = list(cached_tokens = 512L, cache_write_tokens = 0L),
                  output_tokens = 64L, output_tokens_details = list(reasoning_tokens = 32L), total_tokens = 876L)))
)
writeLines(paste(vapply(events, sse, ""), collapse = ""), file.path(base, "fixture_responses.sse"), sep = "", useBytes = TRUE)

# A failure stream (documented shape of response.failed) and an `error` event.
seq_n <- 0L
fail <- list(
  ev(type = "response.created", response = resp_skel("in_progress")),
  ev(type = "response.failed", response = modifyList(resp_skel("failed"),
     list(error = list(code = "subscription_sharing_usage_limit_exceeded", message = "Usage limit reached."))))
)
writeLines(paste(vapply(fail, sse, ""), collapse = ""), file.path(base, "fixture_responses_failed.sse"), sep = "", useBytes = TRUE)

# Chat Completions: data-only SSE, tool_calls deltas by index, final usage chunk, [DONE].
chunk <- function(delta, finish = NULL, usage = NULL, choices = TRUE) {
  x <- list(id = "chatcmpl-fixture", object = "chat.completion.chunk", created = 1790000000L, model = "gpt-6-luna")
  x$choices <- if (choices) list(list(index = 0L, delta = delta, logprobs = NULL, finish_reason = finish)) else list()
  if (!is.null(usage)) x$usage <- usage
  paste0("data: ", j(x), "\n\n")
}
chat <- c(
  chunk(list(role = "assistant", content = "")),
  chunk(list(content = "Let me check")),
  chunk(list(tool_calls = list(list(index = 0L, id = "call_a", type = "function", `function` = list(name = "r_eval", arguments = ""))))),
  chunk(list(tool_calls = list(list(index = 0L, `function` = list(arguments = "{\"code\":"))))),
  chunk(list(tool_calls = list(list(index = 1L, id = "call_b", type = "function", `function` = list(name = "r_ls", arguments = "{}"))))),
  chunk(list(tool_calls = list(list(index = 0L, `function` = list(arguments = "\"nrow(big_df)\"}"))))),
  chunk(structure(list(), names = character()), finish = "tool_calls"),
  chunk(NULL, choices = FALSE, usage = list(prompt_tokens = 90L, completion_tokens = 20L, total_tokens = 110L,
        prompt_tokens_details = list(cached_tokens = 0L), completion_tokens_details = list(reasoning_tokens = 0L))),
  "data: [DONE]\n\n"
)
writeLines(paste(chat, collapse = ""), file.path(base, "fixture_chat.sse"), sep = "", useBytes = TRUE)
cat("fixtures written:", length(events), "responses events;", length(chat), "chat chunks\n")
```

`T08/proto/test_openai_stream.R`

```r
base <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto"
source(file.path(base, "openai_stream.R"))
set.seed(42)

# ---- 1. SSE parser is robust to arbitrary chunking (incl. inside UTF-8 sequences)
bytes <- readBin(file.path(base, "fixture_responses.sse"), "raw", 1e6)
whole <- sse_parser()(bytes)
for (trial in 1:200) {
  p <- sse_parser(); got <- list(); i <- 1L
  while (i <= length(bytes)) {
    n <- sample.int(7L, 1L); j <- min(length(bytes), i + n - 1L)
    got <- c(got, p(bytes[i:j])); i <- j + 1L
  }
  stopifnot(identical(got, whole))
}
cat("1. SSE parser: ", length(whole), "events identical across 200 random chunkings\n")
crlf <- charToRaw(gsub("\n", "\r\n", rawToChar(bytes), fixed = TRUE))
stopifnot(identical(sse_parser()(crlf), whole))
cr_only <- charToRaw(gsub("\n", "\r", rawToChar(bytes), fixed = TRUE))
for (trial in 1:100) {                      # CRLF and CR-only, randomly chunked (CR/LF split across chunks)
  for (src in list(crlf, cr_only)) {
    p <- sse_parser(); got <- list(); i <- 1L
    while (i <= length(src)) { j <- min(length(src), i + sample.int(5L, 1L) - 1L); got <- c(got, p(src[i:j])); i <- j + 1L }
    got <- c(got, p(final = TRUE))
    stopifnot(identical(got, whole))
  }
}
cat("   CRLF and CR-only framing parse identically under random chunking\n")
d12 <- json_parse(whole[[12]]$data)$delta
stopifnot(grepl(intToUtf8(c(0xe9, 0xe8)), d12, fixed = TRUE), grepl(intToUtf8(0x2713), d12, fixed = TRUE))
cat("   non-ASCII delta survives (locale=", Sys.getlocale("LC_CTYPE"), "): ", nchar(d12), " chars, Encoding=",
    Encoding(d12), "\n", sep = "")

# ---- 2. Responses accumulator on the fixture
acc <- responses_accumulator(on_text = function(d) NULL)
for (e in whole) acc$handle(json_parse(e$data))
r <- acc$result()
cat("2. status:", r$status, "| terminal:", r$terminal, "| text:", r$text, "\n")
cat("   tool calls:", vapply(r$tool_calls, function(x) paste0(x$name, "(", jsonlite::toJSON(x$arguments, auto_unbox = TRUE), ") call_id=", x$call_id), ""), "\n")
cat("   usage: input", r$usage$input_tokens, "cached", r$usage$input_tokens_details$cached_tokens,
    "output", r$usage$output_tokens, "reasoning", r$usage$output_tokens_details$reasoning_tokens, "\n")
replay <- c(list(list(role = "user", content = "How many rows?")), responses_replay_items(r$output_items),
            list(function_call_output(r$tool_calls[[1]]$call_id, "[1] 123457")))
cat("   replay item types:", vapply(replay, function(x) x[["type"]] %||% "message(user)", ""), "\n")
cat("   reasoning item keeps encrypted_content:", !is.null(replay[[2]]$encrypted_content), "\n")
cat("   assistant message keeps phase:", replay[[3]]$phase, "\n")

# ---- 3. failed stream -> structured error
accf <- responses_accumulator()
for (e in sse_parser()(readBin(file.path(base, "fixture_responses_failed.sse"), "raw", 1e6)))
  accf$handle(json_parse(e$data))
rf <- accf$result(); cat("3. failed stream -> status:", rf$status, "code:", rf$error$code, "\n")

# ---- 4. Chat Completions accumulator (tool_calls deltas by index, usage chunk, [DONE])
cacc <- chat_accumulator()
for (e in sse_parser()(readBin(file.path(base, "fixture_chat.sse"), "raw", 1e6))) cacc$handle(e$data)
cr <- cacc$result()
cat("4. chat: content=", shQuote(cr$content), " finish=", cr$finish_reason, " done=", cr$done,
    " usage.total=", cr$usage$total_tokens, "\n", sep = "")
for (tc in cr$tool_calls) cat("   tool_call", tc$id, tc$name, jsonlite::toJSON(tc$arguments, auto_unbox = TRUE), "\n")

# ---- 5. Request body builders, incl. ChatGPT-plan contract
b <- openai_responses_body(
  model = "gpt-6-luna", instructions = "You are gptr.",
  input = list(list(role = "developer", content = "Session: R 4.4"), list(role = "user", content = "hi")),
  tools = list(namespace_tool("r", "Tools that act on the live R session", list(
    function_tool("r_eval", "Evaluate R code", list(type = "object",
      properties = list(code = list(type = "string")), required = list("code"), additionalProperties = FALSE), strict = TRUE)))),
  reasoning_effort = "low", reasoning_summary = "auto", verbosity = "low",
  max_output_tokens = 2000, temperature = 0.2, prompt_cache_key = "gptr-session-1", plan_mode = TRUE)
cat("5. plan-mode body fields:", paste(names(b), collapse = ", "), "\n")
stopifnot(is.null(b$max_output_tokens), is.null(b$temperature), identical(b$store, FALSE), identical(b$stream, TRUE))
err <- tryCatch(openai_responses_body("m", list(list(role = "system", content = "x")), plan_mode = TRUE), error = conditionMessage)
cat("   system item in plan mode ->", err, "\n")
cat(substr(jsonlite::toJSON(b, auto_unbox = TRUE), 1, 500), "...\n")
```

Observed output (`out_test_openai_stream.txt`):

```text
1. SSE parser:  20 events identical across 200 random chunkings
   CRLF and CR-only framing parse identically under random chunking
   non-ASCII delta survives (locale=C): 16 chars, Encoding=UTF-8
2. status: completed | terminal: TRUE | text: Checking the data frame. 
   tool calls: r_eval({"code":"nrow(big_df)"}) call_id=call_fixture1 
   usage: input 812 cached 512 output 64 reasoning 32 
   replay item types: message(user) reasoning message function_call function_call_output 
   reasoning item keeps encrypted_content: TRUE 
   assistant message keeps phase: commentary 
3. failed stream -> status: failed code: subscription_sharing_usage_limit_exceeded 
4. chat: content='Let me check' finish=tool_calls done=TRUE usage.total=110
   tool_call call_a r_eval {"code":"nrow(big_df)"} 
   tool_call call_b r_ls {} 
5. plan-mode body fields: model, input, store, stream, instructions, tools, reasoning, text, prompt_cache_key 
   system item in plan mode -> plan mode rejects role='system' input items; use `instructions` or role='developer' 
{"model":"gpt-6-luna","input":[{"role":"developer","content":"Session: R 4.4"},{"role":"user","content":"hi"}],"store":false,"stream":true,"instructions":"You are gptr.","tools":[{"type":"namespace","name":"r","description":"Tools that act on the live R session","tools":[{"type":"function","name":"r_eval","description":"Evaluate R code","parameters":{"type":"object","properties":{"code":{"type":"string"}},"required":["code"],"additionalProperties":false},"strict":true}]}],"reasoning":{"effort":" ...
```

`T08/proto/test_transport.R`

```r
# End-to-end transport test against a local mock server (separate R process via callr),
# so no OpenAI API call is made. Verifies httr2::req_perform_connection() +
# resp_stream_sse() + our accumulators, request headers/body, and error handling.
base <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto"
source(file.path(base, "openai_stream.R"))
port <- httpuv::randomPort()
req_log <- file.path(base, "mock_requests.jsonl"); unlink(req_log)

srv <- callr::r_bg(function(port, base, req_log) {
  fix <- function(f) readBin(file.path(base, f), "raw", 1e6)
  httpuv::runServer("127.0.0.1", port, list(call = function(req) {
    body <- rawToChar(req$rook.input$read())
    cat(jsonlite::toJSON(list(path = req$PATH_INFO, auth = substr(req$HTTP_AUTHORIZATION, 1, 12),
                              accept = req$HTTP_ACCEPT, client_request_id = req$HTTP_X_CLIENT_REQUEST_ID,
                              body = jsonlite::fromJSON(body, simplifyVector = FALSE)),
                         auto_unbox = TRUE, null = "null"), "\n", file = req_log, append = TRUE)
    if (req$PATH_INFO == "/v1/responses")
      return(list(status = 200L, headers = list(`Content-Type` = "text/event-stream", `x-request-id` = "req_mock1",
                  `x-ratelimit-remaining-requests` = "499", `x-ratelimit-remaining-tokens` = "499188"),
                  body = fix("fixture_responses.sse")))
    if (req$PATH_INFO == "/v1/chat/completions")
      return(list(status = 200L, headers = list(`Content-Type` = "text/event-stream"), body = fix("fixture_chat.sse")))
    list(status = 429L, headers = list(`Content-Type` = "application/json", `retry-after` = "7", `x-request-id` = "req_mock2"),
         body = '{"error":{"message":"Rate limit reached for requests","type":"rate_limit_error","param":null,"code":"slow_down"}}')
  }))
}, args = list(port = port, base = base, req_log = req_log))
on.exit(srv$kill(), add = TRUE)
Sys.sleep(1.5)
url <- sprintf("http://127.0.0.1:%d/v1", port)

acc <- responses_accumulator(on_text = function(d) cat("   [text delta]", d, "\n"))
body <- openai_responses_body("gpt-6-luna", list(list(role = "user", content = "rows?")),
                              instructions = "You are gptr.", reasoning_effort = "low")
t <- openai_stream(paste0(url, "/responses"), body, token = "sk-test-not-real",
                   on_event = function(ev) acc$handle(json_parse(ev$data)),
                   extra_headers = list(`X-Client-Request-Id` = "gptr-test-1"))
r <- acc$result()
cat("responses: ok=", t$ok, " request_id=", t$request_id, " status=", r$status, " text=", r$text,
    " calls=", length(r$tool_calls), "\n", sep = "")
print(t$ratelimit)

cacc <- chat_accumulator()
t2 <- openai_stream(paste0(url, "/chat/completions"),
                    list(model = "gpt-6-luna", stream = TRUE, stream_options = list(include_usage = TRUE),
                         messages = list(list(role = "user", content = "hi"))),
                    token = "sk-test-not-real", on_event = function(ev) cacc$handle(ev$data))
cr <- cacc$result()
cat("chat: ok=", t2$ok, " finish=", cr$finish_reason, " tool_calls=", length(cr$tool_calls), " usage.total=", cr$usage$total_tokens, "\n", sep = "")

t3 <- openai_stream(paste0(url, "/err"), list(model = "x"), token = "sk-test-not-real", on_event = function(ev) NULL)
cat("error path: ok=", t3$ok, " status=", t3$status, " retry_after=", t3$retry_after, " request_id=", t3$request_id, "\n", sep = "")
cat("error body:", t3$body, "\n")

cat("\nrequests seen by mock server:\n")
for (ln in readLines(req_log)) {
  x <- jsonlite::fromJSON(ln, simplifyVector = FALSE)
  cat(" ", x$path, "| auth prefix:", x$auth, "| accept:", x$accept, "| x-client-request-id:", x$client_request_id %||% "-",
      "| body keys:", paste(names(x$body), collapse = ","), "\n")
}

acc2 <- responses_accumulator()
t4 <- openai_stream_raw(paste0(url, "/responses"), body, token = "sk-test-not-real", kb = 1,
                        on_event = function(ev) acc2$handle(json_parse(ev$data)))
r2 <- acc2$result()
cat("raw-chunk variant (1 KB reads): ok=", t4$ok, " events=", t4$events, " status=", r2$status,
    " identical result to resp_stream_sse path: ", identical(r2, r), "\n", sep = "")
```

Observed output (`out_test_transport.txt`):

```text
   [text delta] Checking the  
   [text delta] data frame <U+00E9><U+00E8> <U+2713>. 
responses: ok=TRUE request_id=req_mock1 status=completed text=Checking the data frame. calls=1
<httr2_headers>
x-ratelimit-remaining-requests: 499
x-ratelimit-remaining-tokens: 499188
chat: ok=TRUE finish=tool_calls tool_calls=2 usage.total=110
error path: ok=FALSE status=429 retry_after=7 request_id=req_mock2
error body: {"error":{"message":"Rate limit reached for requests","type":"rate_limit_error","param":null,"code":"slow_down"}} 

requests seen by mock server:
  /v1/responses | auth prefix: Bearer sk-te | accept: text/event-stream | x-client-request-id: gptr-test-1 | body keys: model,input,store,stream,instructions,reasoning 
  /v1/chat/completions | auth prefix: Bearer sk-te | accept: text/event-stream | x-client-request-id: - | body keys: model,stream,stream_options,messages 
  /v1/err | auth prefix: Bearer sk-te | accept: text/event-stream | x-client-request-id: - | body keys: model 
raw-chunk variant (1 KB reads): ok=TRUE events=20 status=completed identical result to resp_stream_sse path: TRUE
```

In the transport output, `<U+00E9>` is how `cat()` renders a correct UTF-8 string in a C-locale console. The data is intact (see the check in `test_openai_stream.R`).

### 5.8 Sign in with ChatGPT building blocks (offline; public JWKS fetched live)

`T08/proto/siwc_oauth.R`

```r
# Sign in with ChatGPT (ChatGPT plan usage for open-source apps) in pure R.
# Spec: developers.openai.com/siwc/token-sharing-open-source/* (fetched 2026-09-30).
`%||%` <- function(x, y) if (is.null(x)) y else x
SIWC <- list(
  issuer = "https://auth.openai.com",
  authorize = "https://auth.openai.com/api/accounts/authorize",
  token = "https://auth.openai.com/api/accounts/oauth/token",
  revoke = "https://auth.openai.com/api/accounts/oauth/revoke",
  jwks = "https://auth.openai.com/.well-known/jwks.json",
  resource = "https://api.openai.com/v1",
  scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
  plan_scope = "chatgpt.tokens.use.direct",
  dynamic_client = "dynamic_agent_client",
  callback_path = "/auth/callback"
)

b64url <- function(raw) sub("=+$", "", chartr("+/", "-_", openssl::base64_encode(raw)))
b64url_decode <- function(s) {
  s <- chartr("-_", "+/", s); pad <- (4 - nchar(s) %% 4) %% 4
  openssl::base64_decode(paste0(s, strrep("=", pad)))
}
uuid_v4 <- function() {
  b <- as.integer(openssl::rand_bytes(16))
  b[7] <- bitwOr(bitwAnd(b[7], 0x0f), 0x40); b[9] <- bitwOr(bitwAnd(b[9], 0x3f), 0x80)
  h <- sprintf("%02x", b)
  paste(paste(h[1:4], collapse = ""), paste(h[5:6], collapse = ""), paste(h[7:8], collapse = ""),
        paste(h[9:10], collapse = ""), paste(h[11:16], collapse = ""), sep = "-")
}
siwc_new_host_id <- function() paste0("urn:uuid:", uuid_v4())   # persist once per host
pkce_pair <- function() {
  verifier <- b64url(openssl::rand_bytes(32))
  list(verifier = verifier, challenge = b64url(openssl::sha256(charToRaw(verifier))))
}

siwc_authorize_url <- function(host_id, redirect_uri, state, nonce, challenge,
                               client_id = SIWC$dynamic_client, agent_name_hint = "gptr",
                               id_token_hint = NULL, login_hint = NULL) {
  q <- list(client_id = client_id, response_type = "code", redirect_uri = redirect_uri,
            scope = SIWC$scope, resource = SIWC$resource, state = state, nonce = nonce,
            code_challenge_method = "S256", code_challenge = challenge, ext_agent_host_id = host_id)
  if (identical(client_id, SIWC$dynamic_client)) q$agent_name_hint <- agent_name_hint   # first registration only
  q$id_token_hint <- id_token_hint; q$login_hint <- login_hint
  paste0(SIWC$authorize, "?", paste(names(q), vapply(q, function(v) utils::URLencode(v, reserved = TRUE), ""),
                                     sep = "=", collapse = "&"))
}

# Loopback listener on 127.0.0.1 (never "localhost"); returns a function that
# services the event loop until the callback arrives or times out.
siwc_callback_server <- function(state, port = httpuv::randomPort()) {
  result <- NULL
  srv <- httpuv::startServer("127.0.0.1", port, list(call = function(req) {
    if (req$PATH_INFO != SIWC$callback_path) return(list(status = 404L, headers = list(), body = "not found"))
    q <- shiny_parse_query(req$QUERY_STRING)
    if (!identical(q$state, state)) { result <<- list(error = "state_mismatch"); return(list(status = 400L, headers = list(), body = "State mismatch")) }
    if (!is.null(q$error)) { result <<- list(error = q$error); return(list(status = 200L, headers = list(), body = "ChatGPT was not connected. You can close this window.")) }
    result <<- list(code = q$code, client_id = q$client_id, scope = q$scope)
    list(status = 200L, headers = list(`Content-Type` = "text/html"), body = "Signed in. You can close this window and return to R.")
  }))
  list(redirect_uri = sprintf("http://127.0.0.1:%d%s", port, SIWC$callback_path),
       wait = function(timeout = 300, tick = function() NULL) {
         deadline <- Sys.time() + timeout
         while (is.null(result) && Sys.time() < deadline) { httpuv::service(100); tick() }
         for (i in 1:5) httpuv::service(50)   # let the browser receive its page before closing
         httpuv::stopServer(srv); result
       })
}
shiny_parse_query <- function(qs) {          # tiny query-string parser (no shiny dependency)
  qs <- sub("^\\?", "", qs); if (!nzchar(qs)) return(list())
  kv <- strsplit(strsplit(qs, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
  stats::setNames(lapply(kv, function(p) utils::URLdecode(gsub("+", " ", p[2] %||% "", fixed = TRUE))),
                  vapply(kv, `[`, "", 1))
}

siwc_token_request <- function(form) {
  req <- httr2::request(SIWC$token)
  req <- httr2::req_headers(req, Accept = "application/json")
  do.call(httr2::req_body_form, c(list(req), form))
}
siwc_exchange_request <- function(code, verifier, client_id, redirect_uri)
  siwc_token_request(list(grant_type = "authorization_code", client_id = client_id, code = code,
                          code_verifier = verifier, redirect_uri = redirect_uri, resource = SIWC$resource))
siwc_refresh_request <- function(refresh_token, client_id)
  siwc_token_request(list(grant_type = "refresh_token", client_id = client_id,
                          refresh_token = refresh_token, resource = SIWC$resource))   # omit scope

jwt_payload <- function(jwt) {                 # decode WITHOUT verifying (display/expiry only)
  p <- strsplit(jwt, ".", fixed = TRUE)[[1]][2]
  txt <- rawToChar(b64url_decode(p)); Encoding(txt) <- "UTF-8"
  jsonlite::fromJSON(txt, simplifyVector = FALSE)
}

# Atomic, owner-only credential write (0600 on Unix; Windows relies on the per-user profile ACL).
write_secret_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
  tmp <- tempfile(tmpdir = dirname(path), fileext = ".tmp")
  old <- Sys.umask("077"); on.exit(Sys.umask(old), add = TRUE)
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", pretty = TRUE), tmp, useBytes = TRUE)
  Sys.chmod(tmp, "0600")
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}
```

`T08/proto/test_siwc_oauth.R`

```r
# Offline test of the SIWC building blocks. No real sign-in, no token request is sent.
base <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track08/proto"
source(file.path(base, "siwc_oauth.R"))
lib <- "/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/rlib"

host <- siwc_new_host_id(); cat("host id:", host, "valid:", grepl("^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", host), "\n")
pk <- pkce_pair(); cat("pkce verifier nchar:", nchar(pk$verifier), "challenge nchar:", nchar(pk$challenge), "(43 = 32 bytes b64url, no padding)\n")
# Cross-check S256 against the system openssl CLI (independent implementation)
cli <- system2("sh", c("-c", shQuote(sprintf("printf '%%s' '%s' | openssl dgst -sha256 -binary | base64", pk$verifier))), stdout = TRUE)
stopifnot(identical(pk$challenge, sub("=+$", "", chartr("+/", "-_", cli))))
cat("PKCE S256 challenge matches `openssl dgst -sha256 | base64` (base64url, unpadded)\n")

state <- b64url(openssl::rand_bytes(32)); nonce <- b64url(openssl::rand_bytes(32))
cb <- siwc_callback_server(state)
url <- siwc_authorize_url(host, cb$redirect_uri, state, nonce, pk$challenge)
cat("authorize URL (host id redacted):\n ", sub("ext_agent_host_id=[^&]+", "ext_agent_host_id=<HOST>", url), "\n")

# Simulate the browser redirect with a child process while the R loop services httpuv.
sim <- processx::process$new("curl", c("-s", paste0(cb$redirect_uri, "?code=AUTH_CODE_X&scope=chatgpt.tokens.use.direct+email+offline_access+openid+profile+resource.invoke&state=",
                                                    state, "&client_id=oaiapp_TESTCLIENT")), stdout = "|")
res <- cb$wait(timeout = 20)
sim$wait(5000)
cat("callback captured: code =", res$code, "| issued client_id =", res$client_id, "| scope =", res$scope, "\n")
cat("browser saw:", sim$read_all_output(), "\n")

req <- siwc_exchange_request(res$code, pk$verifier, res$client_id, cb$redirect_uri)
cat("\n-- token exchange request (dry run, not sent):\n")
httr2::req_dry_run(req, redact_headers = TRUE)
cat("\n-- refresh request (dry run):\n")
httr2::req_dry_run(siwc_refresh_request("REFRESH_X", "oaiapp_TESTCLIENT"))

# Live, public, unauthenticated: OpenAI JWKS used to verify ID tokens.
jwks <- jsonlite::fromJSON(SIWC$jwks, simplifyVector = FALSE)
cat("\nJWKS keys:", length(jwks$keys), "| kty:", paste(unique(vapply(jwks$keys, `[[`, "", "kty")), collapse = ","),
    "| alg:", paste(unique(vapply(jwks$keys, function(k) k$alg %||% "?", "")), collapse = ","), "\n")
suppressPackageStartupMessages(library(jose, lib.loc = lib))
k1 <- jose::read_jwk(jsonlite::toJSON(jwks$keys[[1]], auto_unbox = TRUE))
cat("first JWKS key parses as:", class(k1)[1], "\n")

# ID-token validation logic, exercised with a locally generated RSA key.
key <- openssl::rsa_keygen(2048)
claims <- jose::jwt_claim(iss = SIWC$issuer, aud = "oaiapp_TESTCLIENT", sub = "user-123",
                          exp = as.numeric(Sys.time()) + 3600, iat = as.numeric(Sys.time()), nonce = nonce, email = "u@example.com")
idt <- jose::jwt_encode_sig(claims, key)
validate_id_token <- function(jwt, pubkey, client_id, nonce, leeway = 60) {
  cl <- jose::jwt_decode_sig(jwt, pubkey)              # verifies RS256 signature
  stopifnot(identical(cl$iss, SIWC$issuer), identical(cl$aud, client_id), identical(cl$nonce, nonce),
            cl$exp + leeway > as.numeric(Sys.time()), nzchar(cl$sub))
  cl
}
ok <- validate_id_token(idt, key$pubkey, "oaiapp_TESTCLIENT", nonce)
cat("id_token validated; sub =", ok$sub, "\n")
bad <- tryCatch(validate_id_token(idt, openssl::rsa_keygen(2048)$pubkey, "oaiapp_TESTCLIENT", nonce), error = function(e) "rejected")
cat("wrong key ->", bad, "\n")

# Credential record in the documented shape, written atomically 0600.
cred <- list(email = "u@example.com", issuer = SIWC$issuer, subject = "user-123", client_id = "oaiapp_TESTCLIENT",
             ext_agent_host_id = host, id_token = "<ID_TOKEN>", access_token = "<ACCESS_TOKEN>", refresh_token = "<REFRESH_TOKEN>",
             token_type = "Bearer", expires_in = 3600L, scopes = strsplit(res$scope, " ")[[1]],
             saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
path <- file.path(base, "cred_test", "chatgpt", "oaiapp_TESTCLIENT.json")
write_secret_json(cred, path)
cat("credential file mode:", format(file.info(path)$mode), "| has plan scope:", SIWC$plan_scope %in% cred$scopes, "\n")
unlink(file.path(base, "cred_test"), recursive = TRUE)
```

Observed output (`out_test_siwc_oauth.txt`):

```text
host id: urn:uuid:<UUIDv4> valid: TRUE 
pkce verifier nchar: 43 challenge nchar: 43 (43 = 32 bytes b64url, no padding)
PKCE S256 challenge matches `openssl dgst -sha256 | base64` (base64url, unpadded)
authorize URL (host id redacted):
  https://auth.openai.com/api/accounts/authorize?client_id=dynamic_agent_client&response_type=code&redirect_uri=http%3A%2F%2F127.0.0.1%3A24331%2Fauth%2Fcallback&scope=openid%20profile%20email%20offline_access%20resource.invoke%20chatgpt.tokens.use.direct&resource=https%3A%2F%2Fapi.openai.com%2Fv1&state=<RANDOM>&nonce=<RANDOM>&code_challenge_method=S256&code_challenge=<RANDOM>&ext_agent_host_id=<HOST>&agent_name_hint=gptr 
callback captured: code = AUTH_CODE_X | issued client_id = oaiapp_TESTCLIENT | scope = chatgpt.tokens.use.direct email offline_access openid profile resource.invoke 
browser saw: Signed in. You can close this window and return to R. 

-- token exchange request (dry run, not sent):
POST /api/accounts/oauth/token HTTP/1.1
accept: application/json
accept-encoding: deflate, gzip
content-length: 237
content-type: application/x-www-form-urlencoded
host: auth.openai.com
user-agent: httr2/1.2.2 r-curl/7.0.0 libcurl/8.14.1

grant_type=authorization_code&client_id=oaiapp_TESTCLIENT&code=AUTH_CODE_X&code_verifier=<RANDOM>&redirect_uri=http%3A%2F%2F127.0.0.1%3A24331%2Fauth%2Fcallback&resource=https%3A%2F%2Fapi.openai.com%2Fv1

-- refresh request (dry run):
POST /api/accounts/oauth/token HTTP/1.1
accept: application/json
accept-encoding: deflate, gzip
content-length: 119
content-type: application/x-www-form-urlencoded
host: auth.openai.com
user-agent: httr2/1.2.2 r-curl/7.0.0 libcurl/8.14.1

grant_type=refresh_token&client_id=oaiapp_TESTCLIENT&refresh_token=REFRESH_X&resource=https%3A%2F%2Fapi.openai.com%2Fv1

JWKS keys: 4 | kty: RSA | alg: RS256 
first JWKS key parses as: pubkey 
id_token validated; sub = user-123 
wrong key -> rejected 
credential file mode: 600 | has plan scope: TRUE 
```

Not verified: a real authorization at `auth.openai.com` (needs the user in a browser), the real token exchange, a real refresh, and a plan-mode `/v1/responses` call. The request bodies above are exactly what the docs specify.

Prototype limits to fix when porting (found during verification):
- `validate_id_token()` is tested only with one local key. Production code must choose the JWKS key by `kid`.
- Its `leeway` argument has no effect, because `jose::jwt_decode_sig()` already rejects expired tokens (verified: "Token has expired on …").
- `identical(cl$aud, client_id)` fails if `aud` is an array.
- `shiny_parse_query()` splits on every `=`, so a raw `=` inside a value truncates it.
- The callback handler uses `q$state`, `q$code` and `q$client_id` (`$` partial matching), against this report's own `[[` rule.

### 5.9 Encoding experiments (why `encoding = "UTF-8"` and `Encoding<-` are mandatory)

`T08/proto/enc_processx.R`

```r
cat("locale:", Sys.getlocale("LC_CTYPE"), "\n")
for (enc in c("", "UTF-8")) {
  p <- processx::process$new("printf", "{\"a\":\"d\\303\\251\"}\\n", stdout = "|", encoding = enc)
  p$wait(); out <- p$read_all_output_lines()
  x <- tryCatch(jsonlite::fromJSON(out[1])$a, error = function(e) paste("ERR", conditionMessage(e)))
  Encoding(out) <- "UTF-8"; y <- jsonlite::fromJSON(out[1])$a
  cat(sprintf("encoding=%-6s raw line enc=%s bytes=%s | fromJSON as-is: %s | after marking UTF-8: bytes=%s\n",
      shQuote(enc), Encoding(out[1]), paste(as.character(charToRaw(out[1]))[8:10], collapse=" "),
      paste(as.character(charToRaw(x)), collapse=" "), paste(as.character(charToRaw(y)), collapse=" ")))
}
```

Observed output (`out_enc_processx.txt`):

```text
locale: C 
encoding=''     raw line enc=unknown bytes=22 7d NA | fromJSON as-is: 64 | after marking UTF-8: bytes=64
encoding='UTF-8' raw line enc=UTF-8 bytes=c3 a9 22 | fromJSON as-is: 64 c3 a9 | after marking UTF-8: bytes=64 c3 a9
locale: en_US.UTF-8 
encoding=''     raw line enc=UTF-8 bytes=c3 a9 22 | fromJSON as-is: 64 c3 a9 | after marking UTF-8: bytes=64 c3 a9
encoding='UTF-8' raw line enc=UTF-8 bytes=c3 a9 22 | fromJSON as-is: 64 c3 a9 | after marking UTF-8: bytes=64 c3 a9
```

`T08/proto/enc2.R`

```r
cat("locale:", Sys.getlocale("LC_CTYPE"), " utf8 locale:", l10n_info()[["UTF-8"]], "\n")
x <- rawToChar(as.raw(c(0x64, 0xc3, 0xa9))); Encoding(x) <- "UTF-8"
cat("marked UTF-8:", Encoding(x), "\n")
s <- jsonlite::toJSON(list(a = x), auto_unbox = TRUE)
cat("toJSON bytes:", paste(as.character(charToRaw(s)), collapse = " "), "\n")
s2 <- jsonlite::toJSON(list(a = x), auto_unbox = TRUE, pretty = FALSE)
y <- jsonlite::fromJSON('{"a":"d\\u00e9"}')
cat("fromJSON \\u escape -> Encoding:", Encoding(y$a), " bytes:", paste(as.character(charToRaw(y$a)), collapse=" "), "\n")
z <- rawToChar(as.raw(c(0x7b,0x22,0x61,0x22,0x3a,0x22,0x64,0xc3,0xa9,0x22,0x7d)))
w <- jsonlite::fromJSON(z); cat("fromJSON raw utf8 (unmarked input) -> Encoding:", Encoding(w$a), " bytes:", paste(as.character(charToRaw(w$a)), collapse=" "), "\n")
Encoding(z) <- "UTF-8"; w2 <- jsonlite::fromJSON(z); cat("fromJSON raw utf8 (marked input) -> Encoding:", Encoding(w2$a), " bytes:", paste(as.character(charToRaw(w2$a)), collapse=" "), "\n")
p <- jsonlite::parse_json(z); cat("parse_json marked:", Encoding(p$a), paste(as.character(charToRaw(p$a)), collapse=" "), "\n")
```

Observed output (`out_enc_jsonlite.txt`):

```text
--- C locale
locale: C  utf8 locale: FALSE 
marked UTF-8: UTF-8 
toJSON bytes: 7b 22 61 22 3a 22 64 c3 a9 22 7d 
fromJSON \u escape -> Encoding: UTF-8  bytes: 64 c3 a9 
fromJSON raw utf8 (unmarked input) -> Encoding: unknown  bytes: 64 3c 63 33 3e 3c 61 39 3e 
fromJSON raw utf8 (marked input) -> Encoding: UTF-8  bytes: 64 c3 a9 
parse_json marked: UTF-8 64 c3 a9 
--- UTF-8 locale
locale: en_US.UTF-8  utf8 locale: TRUE 
marked UTF-8: UTF-8 
toJSON bytes: 7b 22 61 22 3a 22 64 c3 a9 22 7d 
fromJSON \u escape -> Encoding: UTF-8  bytes: 64 c3 a9 
fromJSON raw utf8 (unmarked input) -> Encoding: UTF-8  bytes: 64 c3 a9 
fromJSON raw utf8 (marked input) -> Encoding: UTF-8  bytes: 64 c3 a9 
parse_json marked: UTF-8 64 c3 a9 
```

Reading the output:
- processx with its default `encoding = ""` in a C locale turned the child's `{"a":"dé"}` into `{"a":"d"}`: the bytes were dropped.
- `jsonlite::fromJSON()` on unmarked UTF-8 text in a C locale produced the literal characters `<c3><a9>`.
- Both are silent data corruption.

This matters for `Rscript` under cron, CI and CRAN check machines, and for any user with `LANG=C`. Windows R ≥ 4.2 uses UTF-8 natively, which LIKELY avoids it there, but explicit settings are still required.

---

## 6. CRAN and cross-platform considerations

### 6.1 CRAN policy mapping

- **No network or subprocess in examples, tests or vignettes by default.** Wrap live paths in `if (interactive())` or `\dontrun{}` in examples. Tests use:
  - SSE fixtures (§5.7);
  - a callr-hosted httpuv mock server (§5.7), guarded by `skip_on_cran()` because it binds a local port (LIKELY acceptable, but local ports can collide on check farms; `httpuv::randomPort()` reduces the risk);
  - a fake `codex` executable written in R (§5.6), which needs no Codex install;
  - recorded app-server logs replayed through the dispatcher (§5.4);
  - PKCE, URL and credential-file unit tests (§5.8) with `tempdir()` paths.
- **File writes.** Credentials, host id and the model-catalog cache live under `tools::R_user_dir("gptr", "config")` (D-10) and are created only by an explicit `gptr_login()` or `gptr_setup()`. Tests use `withr::local_envvar(R_USER_CONFIG_DIR = tempdir())`. Never touch `~/.codex`.
- **Browsers and interactive prompts.** Call `utils::browseURL()` only when `interactive()`. Otherwise print the URL and accept a pasted redirect URL.
- **Child processes.** Use `processx::process$new(..., cleanup = TRUE, cleanup_tree = TRUE)`, and add `reg.finalizer()` plus `on.exit(kill_tree())` so no Codex or httpuv process survives the call. For app-server sessions kept alive between `gptr()` calls, add an explicit `gptr_stop()` and kill on `.onUnload`.
- **Cores.** CLI agents are single processes. Parallel sub-agents obey `getOption("gptr.max_agents")` and never exceed 2 cores in tests.
- **`%||%`.** It is in base R only from 4.4.0 (it worked unqualified here on 4.4.3). If gptr supports R < 4.4, define it internally or use `rlang::%||%`.
- **Package sizes.** Ship the pricing and model snapshot as a small JSON in `inst/extdata`. Do not ship the app-server JSON Schema bundle (600–870 KB); generate it in development only.

### 6.2 Windows specifics (none of this was run on Windows; LIKELY unless stated)

- **Locating Codex:**
  1. `GPTR_CODEX_PATH`;
  2. `Sys.which("codex")`, which finds `codex.exe` from the standalone installer, or `codex.cmd` from npm;
  3. with the npm shim, resolve the native binary `…\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe`, or the `…\@openai\codex-win32-x64\…` sibling (layout VERIFIED from `codex.js` source and the macOS install).

  Calling `.cmd` batch files through CreateProcess is subject to cmd.exe quoting (the "BatBadBut" class of argument-injection problems). Avoid it, or pass **no untrusted text in argv**: the prompt always goes on stdin (§5.1).
- **`-c` values are TOML.** Windows paths contain backslashes, so use literal strings (`'C:/Users/x/…'` or `'C:\Users\x\…'`) or forward slashes via `normalizePath(winslash = "/")`. VERIFIED on macOS for literal-string paths.
- **Rscript for MCP stdio servers:** `file.path(R.home("bin"), "Rscript.exe")`.
- **Line endings.** Codex writes `\n`, but parsers must accept `\r\n`. The JSONL splitter strips a trailing `\r`, and the SSE parser handles LF, CRLF and CR (VERIFIED §5.7).
- **Encoding.** R ≥ 4.2 on Windows uses UTF-8 as the native encoding (UCRT). Still pass `encoding = "UTF-8"` to processx and mark JSON text as UTF-8.
- **Sandbox.** Codex on native Windows needs its Windows sandbox (`[windows] sandbox = "elevated"` preferred, `"unelevated"` fallback; app-server offers `windowsSandbox/setupStart` and `windowsSandbox/readiness`). gptr should surface `windowsSandbox/setupCompleted` and warning events and default to `read-only` until setup succeeds. WSL is an alternative: `codex = c("wsl", "codex")` works with the vector-executable design (UNCERTAIN: path translation of `-C`).
- **Loopback OAuth on Windows.** Binding `127.0.0.1` normally does not trigger a Windows Defender Firewall prompt, which applies to external interfaces (UNCERTAIN). `browseURL` uses `shell.exec`.
- **Killing process trees.** `processx::kill_tree()` works on Windows. Codex spawns grandchildren (shell, MCP servers), so always use `cleanup_tree = TRUE`.
- **Ctrl+C.** In RGui, RStudio and Positron, interrupts are delivered to R, not to children. gptr must translate them into `turn/interrupt` (app-server) or `kill_tree()` (exec).

### 6.3 macOS and Linux

- Codex's shell tool runs the user's login shell (observed `/bin/zsh -lc`), so the user's shell profile affects agent commands. Sandboxing uses Seatbelt on macOS and Landlock/bubblewrap on Linux (Codex docs; not verified here).
- Headless Linux, for SIWC: there is no device-code flow for dynamic clients in the SIWC docs (UNCERTAIN). Use paste-the-redirect-URL, or the "Self-hosted VMs" procedure: authorise locally, then copy the credential record over SSH while keeping the VM's own host id.

---

## 7. Risks, pitfalls, open questions

### 7.1 Risks

1. **SIWC is a preview.** Field restrictions, error codes and the namespace requirement may change. Mitigate with a plan-mode filter table in one place, generic handling of `subscription_sharing_unsupported_capability` using `error.param`, and a test fixture per documented error.
2. **Namespace wording is ambiguous.** "Group function/custom tools in namespaces or supply them through additional_tools" may mean that top-level function tools are rejected in plan mode. Pi sends top-level tools with SIWC tokens and apparently works (UNCERTAIN). gptr should wrap tools in `namespace "gptr"` in plan mode. That means handling `namespace` on returned `function_call` items and echoing it on replay (implemented in the prototype).
3. **App-server is "experimental and isn't supported for production workloads"**, and `dynamicTools` is experimental. Mitigations:
   - pin a tested minimum Codex version (`codex --version`);
   - on `initialize`, check `userAgent` for the version;
   - treat unknown notifications as no-ops and unknown server requests as JSON-RPC `-32601`;
   - keep the `exec` fallback;
   - generate the JSON Schema in CI against the latest Codex and diff it.
4. **Doc/schema drift.** The docs use `workspaceWrite`/`unlessTrusted` for `thread/start.sandbox`/`approvalPolicy` and PascalCase error codes; the 0.157.0 schema uses `workspace-write`/`untrusted` and camelCase. (`turn/start.sandboxPolicy.type` really is camelCase, see §2.F.) Build against the generated schema.
5. **Codex loads the user's global config and MCP servers**, which slows startup and may fail (e.g. `biookf` failed here). For `codex exec`, `--ignore-user-config` skips `config.toml` but keeps the login (help text and docs; not run). For app-server (no such flag in 0.157.0), the only mitigation found is `-c mcp_servers.<name>.enabled=false` for servers listed by `mcpServerStatus/list`, because moving `CODEX_HOME` also moves the login. This is heavy; treat it as a user option.
6. **Token overhead and plan usage.** Codex turns cost 20–40K input tokens even for trivial tasks, which consumes the plan quickly. Warn users; for quick questions prefer the native `openai` route with plan auth.
7. **The ChatGPT model catalog differs by account and by route** (Codex catalog vs API vs SIWC `/v1/models`). `gpt-6.1-sol` was absent from this Pro account's Codex catalog. Always query live, and never hard-code availability.
8. **Terms.** Plan usage through SIWC is for open-source, local and personal use. If gptr is ever embedded in a hosted service (e.g. a Shiny server or Posit Connect deployment of a gptr-powered app), SIWC plan usage and Codex auth become **not permitted**. The package should refuse plan auth when it detects a hosted context (for example `SHINY_PORT`/Connect environment variables; heuristic, UNCERTAIN) and say so in the docs.
9. **Refresh-token rotation races.** Two R sessions refreshing the same SIWC record can invalidate each other (`refresh_token_reused`). Use a lock file and re-read the record after acquiring the lock.
10. **Credential security.** Tokens in plain JSON with 0600 match OpenAI's example. Windows has no chmod, so rely on the profile ACL. An OS keyring (the `keyring` package, Suggests) could be optional later. Never log tokens, redact `id_token_hint` URLs, and never put tokens in URLs.

### 7.2 Pitfalls observed in this session (all VERIFIED)

- `$` partial matching on parsed JSON lists crashed a live run (`msg$params$item` → `itemId`). Use `[[`.
- processx `encoding = ""` drops non-ASCII in a C locale, and `jsonlite::fromJSON()` on unmarked UTF-8 emits `<c3><a9>`. (Corrected: `httr2::resp_stream_sse()` in httr2 1.2.2 and 1.3.0 returns `data` already marked UTF-8, because its internal `parse_event()` sets `Encoding()`.)
- `processx::process$write_input()` is non-blocking and returns the unwritten bytes. A single call silently truncated stdin at 8 KB. Loop (`proc_write_all()`, §5.1). This affects `codex exec -` prompts and every app-server JSON-RPC message over 8 KB, such as large tool results or base64 images.
- `jsonlite::toJSON(auto_unbox = TRUE)` turns `list()` into `[]` and a length-1 `required = "code"` into a scalar string, and both are invalid in JSON Schema tool definitions. Use `structure(list(), names = character())` for an empty object and `list("code")` or `I("code")` for arrays (verified).
- R code that builds JSON with `sprintf()` from mixed-encoding strings in a C locale also produces `<c3><a9>` (seen in the first fake-codex attempt). Build JSON with `jsonlite::toJSON()` from UTF-8-marked strings.
- An httpuv server stopped immediately after capturing the OAuth callback leaves the browser with an empty page. Service the loop a few more ticks before `stopServer()`.
- `httr2::req_timeout()` is a *total* timeout. Long reasoning streams (minutes) need a generous value or a connect-plus-idle scheme (UNCERTAIN how to express idle timeouts in httr2; curl's `low_speed_time` option via `req_options()` is LIKELY suitable).
- The Codex docs site moved from `developers.openai.com/codex` to `learn.chatgpt.com/docs`. Old links in other tracks may be stale.

### 7.3 Open questions

1. Does plan-mode `/v1/responses` accept top-level function tools, or only namespaced ones? Answer with one live SIWC call once the maintainer signs in.
2. Does the SIWC token work with `codex exec` (not just app-server) through `-c model_provider=…`? LIKELY, because it is the same config system, but OpenAI documents only app-server. Also, is `model_providers.<id>.auth.command` (command-backed token) acceptable for SIWC tokens, to avoid restarting app-server hourly?
3. `codex exec resume <id>` with `--json`: does the resumed session keep the same `thread_id`, and are `-c` MCP overrides needed again on resume? LIKELY yes (config is per invocation). Not run because of the call budget.
4. Ctrl+C semantics while R is blocked in `processx::poll_io()` or `httr2` stream reads, across RStudio, Positron, RGui and terminal. Track 15/REQ-38 must verify with `tryCatch(..., interrupt = )`.
5. Can gptr suppress Codex's built-in instructions to cut the ~20–38K token overhead (`baseInstructions` on `thread/start`, `model_instructions_file` for exec) without degrading Codex models, which are tuned to those prompts? Needs an evaluation.
6. Is there a SIWC device-code or out-of-band flow for headless servers? It is not documented for dynamic clients.
7. Does the direct plan route return OpenAI rate-limit headers (`x-ratelimit-*`)? Unknown. Plan usage visibility is via ChatGPT Settings → Usage, and for Codex via `account/rateLimits/read`.

---

## 8. Sources

OpenAI API (fetched 2026-09-30 as Markdown twins):

- Responses create: https://developers.openai.com/api/reference/resources/responses/methods/create.md
- Responses streaming events: https://developers.openai.com/api/reference/resources/responses/streaming-events.md
- Responses compact: https://developers.openai.com/api/reference/resources/responses/methods/compact.md
- Chat resource (create, params, streaming example): https://developers.openai.com/api/reference/resources/chat.md
- Chat Completions streaming events: https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events.md
- API overview (auth, headers, `X-Client-Request-Id`): https://developers.openai.com/api/reference/overview.md
- Guides (all under `https://developers.openai.com/api/docs/guides/`):
  - Function calling: `function-calling.md`
  - Reasoning: `reasoning.md`
  - Structured outputs: `structured-outputs.md`
  - Streaming: `streaming-responses.md`
  - Conversation state: `conversation-state.md`
  - Compaction: `compaction.md`
  - Prompt caching: `prompt-caching.md`
  - Error codes: `error-codes.md`
  - Rate limits: `rate-limits.md`
  - Latest model: `latest-model.md`
  - Tool search: `tools-tool-search.md`
  - Migrate to Responses: `migrate-to-responses.md`
- Models: https://developers.openai.com/api/docs/models.md and https://developers.openai.com/api/docs/models/{gpt-6-astra, gpt-6.1-sol, gpt-6-sol, gpt-6-luna, gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna, gpt-5.5, gpt-5.5-pro, gpt-5.4, gpt-5.4-mini, gpt-5.4-nano, gpt-4.1, gpt-4.1-mini, gpt-oss-120b, gpt-5.3-codex, chat-latest}.md
- Pricing: https://developers.openai.com/api/docs/pricing.md
- Index: https://developers.openai.com/llms.txt, https://developers.openai.com/api/reference/llms.txt

Sign in with ChatGPT:

- https://developers.openai.com/siwc/quickstart.md
- https://developers.openai.com/siwc/token-sharing-open-source.md, plus `/sign-in.md`, `/token-reference.md`, `/profiles-and-sessions.md`, `/errors-and-recovery.md`, `/models-and-inference.md`, `/codex-app-server.md`, `/preview-limitations.md`, `/self-hosted-vms.md`
- https://developers.openai.com/siwc/ui-ux-guidelines.md, https://developers.openai.com/siwc/website.md, https://developers.openai.com/siwc/request-client-id.md, https://developers.openai.com/siwc/llms-full.txt
- Cookbook: https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt.md
- OIDC discovery (fetched live): https://auth.openai.com/.well-known/openid-configuration ; JWKS: https://auth.openai.com/.well-known/jwks.json
- DevKit source: https://github.com/openai/sign-in-with-chatgpt-devkit (`packages/local/src/responses.ts`, `models.ts`, `oauth.ts`, `index.ts`, `README.md`)

Codex (docs moved to learn.chatgpt.com):

- https://learn.chatgpt.com/docs/non-interactive-mode.md, `/app-server.md`, `/auth.md`, `/auth/ci-cd-auth.md`, `/codex-sdk.md`, `/config-file/config-reference.md`, `/config-file/config-advanced.md`, `/config-file/environment-variables.md`, `/extend/mcp.md`, `/mcp-server.md` (removal notice), `/pricing.md`, `/permission-modes.md`, `/permissions.md`, `/sandboxing.md`, `/agent-approvals-security.md`, `/models.md`, `/open-source.md`, `/windows/windows-sandbox.md`, `/hooks.md`, `/codex/cli.md`
- Source, openai/codex @ `2cc65cdd` (raw.githubusercontent.com): `codex-rs/exec/src/exec_events.rs`, `codex-rs/exec/src/cli.rs`, `codex-rs/exec/src/lib.rs` (line 576), `codex-rs/login/src/auth/storage.rs` (47–72, 162–163, 225, 243), `codex-rs/login/src/token_data.rs`, `codex-rs/login/src/auth/manager.rs` (203–216, 1718), `codex-rs/login/src/server.rs` (77–78, 594–610, 1023–1040), `codex-rs/login/src/auth/default_client.rs` (42), `codex-cli/bin/codex.js`
- GitHub discussion on forks and ToS: https://github.com/openai/codex/discussions/8338
- Local CLI: `codex --help`, `codex exec --help`, `codex exec resume --help`, `codex app-server --help`, `codex mcp add --help`, `codex login --help`, `codex debug models [--bundled]`, `codex app-server generate-json-schema [--experimental] --out …` (Codex 0.157.0), captured in `T08/cli/*.txt`, `T08/schema_v157*/`, `T08/models_refreshed.json`, `T08/models_bundled.json`

Pi (local clone @ `1b347794`):

- `packages/ai/src/api/openai-codex-responses.ts` (52–64, 123–164, 237–600, 641–654, 743–859, 865, 1596–1697)
- `packages/ai/src/api/openai-responses.ts` (1–415)
- `packages/ai/src/api/openai-responses-shared.ts` (145–355, 361–398, 434–810)
- `packages/ai/src/auth/oauth/openai-chatgpt.ts` (1–310), `packages/ai/src/auth/oauth/openai-codex.ts` (22–35, 289–435)
- `packages/ai/src/providers/openai.ts`, `packages/ai/src/providers/openai-codex.ts`, `packages/ai/src/auth/oauth/load.ts`

Terms (secondary; the primary pages returned 403 to automated fetches):

- https://openai.com/policies/row-terms-of-use/ and https://openai.com/policies/eu-terms-of-use/ (clause wording from search snippets only)
- Claude Code flags for the adapter comparison: local `claude --help` (v2.1.261)

---

## Verification log

An independent fact-check ran on 2026-09-29. Method:
- **Docs:** fresh `.md` fetches of developers.openai.com (API reference and guides, SIWC, cookbook) and learn.chatgpt.com (Codex docs).
- **Codex source:** raw.githubusercontent.com at `openai/codex@2cc65cdd`.
- **Local CLIs:** Codex CLI 0.157.0 (`--help`, `app-server generate-json-schema --experimental`, `debug models --bundled`) and Claude Code 2.1.261 (`--help`).
- **Pi:** the local clone at `1b347794`.
- **Live public endpoints:** OIDC discovery, JWKS and the GitHub API.
- **R:** Rscript --vanilla on R 4.4.3 in C and UTF-8 locales, httr2 1.2.2 and 1.3.0, jose 1.2.1 and 2.0.0 (private library).

No model call or paid API call was made. Scratch files are in `.../scratchpad/work/verify-08/`.

| # | Claim (section) | Verdict | Source |
|---|---|---|---|
| 1 | OIDC endpoints: authorize, token, revoke, jwks, userinfo; PKCE `S256`; token auth `none` (§3.8) | confirmed | live `auth.openai.com/.well-known/openid-configuration` |
| 2 | JWKS has 4 RSA keys, alg RS256 (§3.8) | confirmed; added: select the key by `kid` (4 distinct kids) | live JWKS; `jose::jwt_split` |
| 3 | Authorize parameters: `dynamic_agent_client`, scope string, `resource`, `127.0.0.1` redirect where only the port varies, `agent_name_hint` on first registration only (§2.J, §3.8) | confirmed; added: the callback may omit `client_id` on re-authorisation | SIWC `sign-in.md`, `profiles-and-sessions.md` |
| 4 | Access token 1 h, refresh token 30 days and rotating; token-response fields; access-token claims (§1, §3.8) | confirmed | SIWC `token-reference.md` |
| 5 | Refresh body without `scope`; revoke form `token`/`token_type_hint`/`client_id`, empty 200; serialise refreshes (§3.8) | confirmed | SIWC `profiles-and-sessions.md` |
| 6 | Plan-mode unsupported-field list (§1.15, §3.1) | confirmed, word for word | SIWC `preview-limitations.md` |
| 7 | "No hosted tools" in plan mode (§1.15, §3.1) | **corrected**: specific tools listed; web search is policy-dependent; `programmatic_tool_calling` is rejected; `input` must be an array | SIWC `preview-limitations.md` |
| 8 | SIWC error codes and HTTP statuses; mid-stream `response.failed` (§2.D, §1.15) | confirmed; added `subscription_sharing_usage_unavailable` mid-stream | SIWC `errors-and-recovery.md`, `models-and-inference.md` |
| 9 | Plus: one shared 5-hour limit; Pro: no 5-hour limit (§1.15) | confirmed | SIWC `profiles-and-sessions.md` line 60 |
| 10 | Availability quotes ("all open-source partners and selected private clients"; "open-source projects, personal projects that run locally, and selected private apps") (§1.1, §2.K) | confirmed | SIWC `quickstart.md`, cookbook |
| 11 | App-server auth "has never been permitted for commercial or hosted services" (§1.3, §2.K) | confirmed | learn.chatgpt.com `app-server.md` line 1914 |
| 12 | `codex mcp-server` removed (§1.4) | confirmed | CLI 0.157.0 falls through to the top-level help; `mcp-server.md` |
| 13 | exec forces `approval_policy = Never` (`lib.rs` 576) (§2.E) | confirmed; added the `--approve-for-me` auto-review nuance | `codex-rs/exec/src/lib.rs` @2cc65cdd; `codex exec --help` |
| 14 | "cannot easily isolate" from the user's Codex config (§2.F, §7.1 risk 5) | **corrected**: exec has `--ignore-user-config` (auth still from `CODEX_HOME`); app-server has no such flag | `codex exec --help`, `codex app-server --help`, `non-interactive-mode.md` |
| 15 | exec JSONL event, item and usage schema (§2.E, §3.9) | confirmed | `codex-rs/exec/src/exec_events.rs` |
| 16 | `exec resume` does not accept `-s`/`-C`; `-` reads stdin (§3.9) | confirmed | `codex exec resume --help` |
| 17 | Server→client request list (§2.F) | confirmed (11 methods) | regenerated `ServerRequest.json` |
| 18 | Dynamic tool spec, call params and response `contentItems`/`success` (§2.F) | confirmed | `DynamicToolSpec`, `DynamicToolCallParams/Response.json` |
| 19 | `codexErrorInfo` enum and object variants (§2.F) | confirmed | v2 schema `CodexErrorInfo` |
| 20 | `SandboxMode` and `AskForApproval` enums; doc/schema mismatch (§2.F, §7.1) | confirmed; **clarified** that `turn/start.sandboxPolicy.type` is camelCase (`SandboxPolicy`) | v2 schema |
| 21 | `turn/start` input types (§2.F) | **corrected**: added `audio`, `localAudio` | v2 schema `UserInput` |
| 22 | Approval, permissions, elicitation and user-input reply shapes (§3.10) | confirmed | `*RequestApprovalResponse.json` etc. |
| 23 | `dynamicTools` persisted and restored on `thread/resume` (§2.F) | confirmed | `app-server.md` line 555 |
| 24 | SIWC app-server provider config (§2.J, §3.10) | confirmed verbatim | SIWC `codex-app-server.md` |
| 25 | `model_providers.<id>.auth.command` alternative (§2.J) | **corrected**: must not be combined with `env_key`/`requires_openai_auth`; defaults added; still UNCERTAIN for SIWC | Codex `config-reference.md` |
| 26 | MCP config keys and defaults (10 s, 60 s, approval modes) (§2.G) | confirmed | Codex `config-reference.md` |
| 27 | Codex OAuth constants (client id, port 1455, scope, extra params, 8-day refresh, env overrides) (§2.H) | confirmed | `manager.rs` 203–216/1718/3026, `server.rs` 78/594–610 |
| 28 | `auth.json` shape, 0600, keyring service "Codex Auth" (§2.H) | confirmed | `storage.rs` 47–72, 163, 225, 243 |
| 29 | Pi SIWC constants, 3-min margin, scope check, refresh without scope (§2.I) | confirmed | Pi `auth/oauth/openai-chatgpt.ts` 16–29, 165–177, 185–222 |
| 30 | Pi SIWC detection (non-`sk-` key) and dropped fields; usage-URL hint; gpt-5.5 priority 2.5× (§2.I, §3.7) | confirmed | Pi `api/openai-responses.ts` 35–46, 226–229, 327–346, 388–401 |
| 31 | Pi legacy `openai-codex`: URL, headers, body defaults, Codex client id, device-code URLs, error regex, WebSocket beta header (§2.I) | confirmed | Pi `openai-codex-responses.ts`, `providers/openai-codex.ts`, `auth/oauth/openai-codex.ts` |
| 32 | "backfill any item missing from `.done` (Azure quirk, Pi #6409)" (§3.3, §5.7) | **corrected**: the quirk is a missing `encrypted_content` on reasoning items; prototype fixed and tested | Pi `openai-responses-shared.ts` 535–552; `verify-08/test_backfill.R` |
| 33 | Pi sends function tools at top level (§2.I) | confirmed | Pi `convertResponsesTools` |
| 34 | Responses body-parameter list (§2.A) | confirmed exactly (32 names) | `responses/methods/create.md` |
| 35 | `reasoning.effort`/`summary`/`context`/`mode` values and defaults (§1.9, §2.A) | confirmed | create reference; reasoning guide |
| 36 | `store` defaults to true (≥30 days); `encrypted_content` returned by default when stateless (§2.A) | confirmed | create reference; reasoning guide line 689 |
| 37 | `phase` must be preserved; strict-mode default differs between Responses and Chat (§2.A) | confirmed | create reference; function-calling guide 1047–1055 |
| 38 | `prompt_cache_key` groups requests for caching (§2.A) | **corrected**: on GPT-5.6+ routing is automatic and the key is for accounting only | prompt-caching guide lines 218, 475 |
| 39 | `prompt_cache_options`, 1.25× cache write, up to 4 writes (§2.A) | confirmed | prompt-caching guide |
| 40 | `X-Client-Request-Id` ASCII ≤512; `openai-version` 2020-10-01 (§2.A) | confirmed; recommendation **corrected** to "unique per request" | API `overview.md` |
| 41 | 58 `response.*` streaming event types; `incomplete_details.reason` values (§2.A, §3.3) | confirmed 58; added `max_messages` | streaming-events reference |
| 42 | Pricing table (all listed rows), long-context 2×/1.5×, Batch/Flex 0.5×, Fast 2× (§1.10, §3.7) | confirmed | `api/docs/pricing.md` |
| 43 | GPT-6 model specs (1,050,000/922,000/128,000), effort sets, Chat Completions tool limits, cutoffs (§1.10, §2.B, §3.7) | confirmed | `models/gpt-6-*.md`, reasoning guide |
| 44 | Codex catalog 272,000/872,000/95 %; `gpt-6.1-sol` absent (§2.C) | confirmed for the bundled catalog; the account-refreshed catalog was not re-fetched | `codex debug models --bundled` |
| 45 | API error codes and `x-ratelimit-*` headers (§2.D) | confirmed | error-codes and rate-limits guides |
| 46 | Structured Outputs limits (§3.2) | confirmed | structured-outputs guide 3798–3810 |
| 47 | SIWC UI strings ("You're using your ChatGPT plan", "Using ChatGPT plan", "Manage usage") (§2.J) | confirmed | SIWC `ui-ux-guidelines.md` |
| 48 | Devkit: port 0, 5 s clock tolerance, refresh may omit scope, SSE without Content-Type, CR handling (§2.J) | confirmed | devkit `packages/local/src/{oauth,responses}.ts` @main |
| 49 | processx `encoding = ""` drops non-ASCII in a C locale (§1.12a, §5.9) | confirmed (re-run) | `enc_processx.R` |
| 50 | `jsonlite::fromJSON()` on unmarked UTF-8 gives `<c3><a9>` (§1.12b, §5.9) | confirmed (re-run) | `enc2.R` |
| 51 | "`httr2::resp_stream_sse()` returns unmarked strings" (§1.12b, §7.2) | **corrected**: 1.2.2 and 1.3.0 return UTF-8-marked `data` | `verify-08/sse_enc_test.R`; `httr2:::parse_event` |
| 52 | "Prefer the raw variant: it tolerates CR-only framing and a missing Content-Type" (§4.3) | **corrected**: `resp_stream_sse()` handled both; the real gap is that it drops an unterminated final event | `verify-08/sse_enc_test.R`, `sse_partial_test.R` |
| 53 | `$` partial matching; `%||%` in base since R 4.4.0 (§1.12c, §6.1) | confirmed | Rscript; R NEWS db (4.4.0) |
| 54 | `codex_exec()`/app-server `send` write the prompt/messages safely via stdin (§5.1, §5.4) | **defect found and fixed**: `write_input()` is non-blocking and truncated at 8 KB; `proc_write_all()` added and tested with 50 KB and 2 MB | `verify-08/wi_test.R`, `wi_fix.R`, `big_prompt_test.R` |
| 55 | "httr2 (≥ 1.1 for `req_perform_connection`)" (§4.6) | **corrected** to ≥ 1.1.1 with reasons | httr2 NEWS.md |
| 56 | jose `read_jwk`/`jwt_decode_sig` (§4.6, §5.8) | confirmed on 1.2.1 and 2.0.0; added: jose enforces `exp` itself with no leeway | jose NEWS; Rscript |
| 57 | `jsonlite::toJSON(auto_unbox = TRUE)` for tool schemas (§4.3) | pitfall added (`list()` gives `[]`, length-1 `required` gives a scalar) | Rscript |
| 58 | Offline prototypes §5.4 replay, §5.5, §5.6, §5.7 (both tests), §5.8, §5.9 and the MCP stdio server by hand | confirmed: outputs reproduced from the embedded code (§5.5 prints the unassigned `initialize` result in addition) | `verify-08/proto/` |
| 59 | Codex CLI command list (§3.11) | corrected: `agents` added | `codex --help` |
| 60 | Cross-references "§5.3" for the SSE parser and plan filter | corrected to §5.7 | report structure |
| 61 | Claude Code flags (`--mcp-config`, `--strict-mcp-config`, stream-json) | confirmed | `claude --help` 2.1.261 |
| 62 | npm launcher binary layout and `CODEX_MANAGED_*` env (§3.11) | confirmed | `codex-cli/bin/codex.js` @2cc65cdd |
| 63 | Codex Python SDK is a stable release that drives app-server (§1.4) | confirmed | `codex-sdk.md` lines 73, 85 |
| 64 | GitHub discussion openai/codex #8338 (§2.K) | confirmed (last update 2026-08-27; no legal answer) | GitHub API |
| 65 | OpenAI Terms of Use clause wording (§2.K) | unverifiable (HTTP 403); stays LIKELY | — |
| 66 | Live-call results: token counts (38,544/30,208; 19,324), timings, rate limit 45 %/10,080 min, account model list, `userAgent` string (§1.6–7, §5.2–5.4) | unverifiable here (not re-run, to avoid model calls); the fixtures derived from them replay consistently | — |

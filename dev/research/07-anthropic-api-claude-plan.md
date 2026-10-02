# Track 07 - Anthropic Messages API and Claude plan usage through Claude Code

Research date: 2026-09-29. Researcher: track-07 agent (resumed from an interrupted earlier attempt;
all prior scratch prototypes were re-run, two of them were found broken and fixed, see section 5).

Environment actually used for every experiment in this report:
macOS (Darwin 25.6), R 4.4.3 via `Rscript --vanilla`, httr2 1.2.2, curl 7.0.0, jsonlite 2.0.0,
processx 3.8.6, httpuv 1.6.17, callr 3.7.6, openssl 2.3.5, later 1.4.8,
Claude Code CLI `2.1.261 (Claude Code)` at `~/.local/bin/claude`, signed in with a claude.ai
Max subscription (`claude auth status --json` -> `authMethod: "claude.ai"`, `subscriptionType: "max"`;
all other fields redacted, no credential was read).

Scratch directory (temporary, everything important is embedded below):
`/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/track-07/`

Real model calls made (limit was 3, all through the Claude plan, model `haiku`):
1. Call 1 (plain text) - the request was sent, but my recorder crashed on a redaction bug after
   `message_start`, so only `system/init` + `system/status` were captured. Counted as spent.
2. Call 2 - an R tool served in-process to the CLI, permission prompt answered by R. Succeeded,
   full redacted stream captured (section 3.14). CLI-estimated cost $0.0179 (list price, billed to plan).
3. Call 3 - `--resume` of call 2's session in a new process. Succeeded (cost estimate $0.0025).
No Anthropic API (api.anthropic.com) call was made: the native-API work is verified against the
official docs plus local mock servers.

Claim labels: **[VERIFIED]** = I saw the evidence (file:line, URL text, or executed output);
**[LIKELY]** = strong indirect evidence; **[UNCERTAIN]** = not confirmed.

---------------------------------------------------------------------------------------------------

## 1. Executive summary

1. **Current Claude API models [VERIFIED, platform.claude.com models overview + pricing, fetched 2026-09-29]:**
   `claude-fable-5-1` ($10/$50, 1M ctx, 128K out), `claude-opus-5-5` ($4/$20, 1M, 128K, default effort
   `medium`), `claude-sonnet-5-5` ($2/$10, 1M, 128K), `claude-haiku-4-5-20251001` (alias
   `claude-haiku-4-5`, $1/$5, 200K, 64K). The four IDs in the task brief are correct. Cache reads are
   0.1x input except Opus 5.5 (0.05x, $0.20) and Fable 5.1 (0.025x, $0.25); 5-minute cache writes 1.25x,
   1-hour writes 2x.
2. **Wire basics [VERIFIED]:** `POST https://api.anthropic.com/v1/messages`, headers `x-api-key`,
   `anthropic-version: 2023-06-01`, `content-type: application/json`, optional comma-separated
   `anthropic-beta`. OAuth/Console-profile tokens go in `Authorization: Bearer` **plus**
   `anthropic-beta: oauth-2025-04-20`; never send both `x-api-key` and Bearer (the skill says "the API
   rejects the request"; the exact status code is not stated in the source - do not hard-code 401).
3. **Breaking API drift gptr must design for [VERIFIED]:** on Opus 5.5 / Fable 5.1 / Sonnet 5.5,
   `thinking:{type:"disabled"}` and `budget_tokens` return 400 (effort is the only thinking control;
   Sonnet 5.5 has `between_tools`); forced `tool_choice` (`any`/`tool`) returns 400; sampling params
   (`temperature`, `top_p`, `top_k`) and assistant prefill return 400; `thinking.display` defaults to
   `"omitted"` (empty thinking text); text between tool calls arrives as progress-update `thinking` blocks.
4. **Preserved thinking [VERIFIED]:** on Fable 5.1 / Opus 5.5 / Sonnet 5.5 a thinking block's signature
   binds it to the model and to the exact prefix (system, tools, earlier messages). Accounts created on
   or after 2026-08-31 get a 400 when an earlier turn was edited. **gptr's transcript must be strictly
   append-only**; instruction changes go into mid-conversation `{"role":"system"}` messages; tools are
   fixed at session start.
5. **Streaming [VERIFIED]:** SSE sequence `message_start` -> (`content_block_start`, `content_block_delta`*,
   `content_block_stop`)* -> `message_delta`+ -> `message_stop`, plus `ping` and `error` at any time;
   delta types `text_delta`, `input_json_delta`, `thinking_delta`, `signature_delta`, `citations_delta`
  (the last one is documented on the citations page, not the streaming page; field `delta.citation`);
   `message_delta.usage` is cumulative; unknown events must be ignored. `httr2::resp_stream_sse()`
   (httr2 1.2.2) parsed CRLF, comments and UTF-8 characters split across TCP writes correctly in my
   mock-server test, so gptr need not hand-write an SSE parser.
6. **Tools [VERIFIED]:** all `tool_result` blocks for one assistant turn go in ONE user message, first in
   the content array, no text immediately after them (can cause empty `end_turn` replies);
   `tool_result.content` may hold `text`, `image`, `document`, `search_result` blocks (images from R plots
   go inside the result); `is_error: true` for failures; streamed client tools should set
   `eager_input_streaming: true` and gptr must validate the parsed input itself.
7. **Prompt caching for gptr's loop [VERIFIED]:** explicit `cache_control` on the last system block
   (covers tools + system) plus top-level automatic `cache_control` (or a moving breakpoint on the last
   block of the last user message); max 4 breakpoints; 512-token minimum on the 5.x models; deterministic
   tool order; never put timestamps in the system prompt; verify with `usage.cache_read_input_tokens`.
8. **Errors/retries [VERIFIED]:** retry 408/409/429/5xx/529 with `retry-after` (seconds), exponential
   backoff otherwise; a 429 whose `error.details.error_code` is `enforced_spend_limit_reached` has no
   `retry-after` and must not be retried; mid-stream failures arrive as `event: error`.
9. **Claude plan from R - the sanctioned route [VERIFIED docs]:** spawn the user's own, unmodified
   `claude` binary (which the user signed in to through Anthropic's own flow) in headless mode.
   Anthropic's legal page explicitly does not prevent "an end user from signing in to the unmodified
   Claude Code binary with their own Claude subscription"; the support article (updated 2026-06-16)
   says "`claude -p`, and third-party app usage still draw from your subscription's usage limits".
10. **Not sanctioned [VERIFIED docs]:** using subscription OAuth tokens directly against the API from a
    third-party harness (Pi's "stealth mode"), offering claude.ai login inside gptr, or collecting /
    storing Claude.ai tokens. Since 2026-04-04 Anthropic bills such third-party-harness traffic as
    per-token extra usage (Anthropic email quoted on HN; Pi now warns users). gptr must not port this.
11. **Gray area to flag to the maintainer [VERIFIED docs]:** the Agent SDK overview says "Unless
    previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate
    limits for their products, including agents built on the Claude Agent SDK." gptr's `claude-code`
    provider never touches credentials, but it does let a user spend plan limits inside a third-party
    tool. Recommendation: opt-in only, clearly documented, no Claude/Claude Code branding, and consider
    asking Anthropic before advertising it.
12. **Key technical discovery [VERIFIED by live test]:** headless Claude Code speaks the same
    NDJSON control protocol that the official Agent SDKs use. An R process can register an **in-process
    "sdk" MCP server** by passing `--mcp-config` with `{"type":"sdk","name":"gptr"}` and then answering
    `control_request`/`mcp_message` lines on stdout by writing `control_response` lines to stdin. In
    call 2, Claude (haiku) called `mcp__gptr__r_eval`, the R handler evaluated
    `answer <- mean(big_vector) * 2` **inside the live R session**, and `answer` (= 24) was then visible to
    the user's next line of R. No port, no HTTP server, no auth token, no idle timeout.
13. **Permission prompts answered in R [VERIFIED live]:** with `--permission-prompt-tool stdio`, the CLI
    sends `control_request` `can_use_tool` (tool name, input, suggestions) and waits for R's
    `{"behavior":"allow","updatedInput":...}` or `{"behavior":"deny","message":...}` - this is exactly
    what REQ-37 (permission modes) needs.
14. **Claude Code's `stream_event` lines are raw Anthropic SSE events [VERIFIED]:** the same R
    accumulator used for the native API rebuilt both API messages of call 2 (thinking + tool_use, then
    thinking + text) from the CLI stream. gptr needs one normaliser for both providers.
15. **Isolation flags [VERIFIED, zero-cost probes]:** `--tools "" --strict-mcp-config --setting-sources ""
    --disable-slash-commands --system-prompt-file <gptr prompt>` reduced the CLI's prompt from ~18.4K
    tokens (default tools + prompt) or ~3.1K (no tools, default prompt) to 12-27 tokens, and excluded the
    user's CLAUDE.md, MCP servers and custom agents (which added ~13K tokens without isolation).
    Do **not** use `--bare`: it ignores OAuth, i.e. the subscription.
16. **Session continuity [VERIFIED live]:** `--session-id <uuid>` pins the id before the run;
    `--resume <id>` in a new process continued the conversation (answered "24", same `session_id`);
    transcripts live at `~/.claude/projects/<cwd with every non-alphanumeric character replaced by
    ->/<session_id>.jsonl` (names over 200 chars are truncated and suffixed with a hash; sessions docs).
17. **Hidden-but-accepted flags [CORRECTED by verifier: `claude --help` of CLI 2.1.261 + raw
    cli-reference.md]:** flags with no entry of their own in `claude --help`: `--max-turns`,
    `--permission-prompt-tool` (only mentioned inside the `--permission-prompts` text),
    `--system-prompt-file`, `--append-system-prompt-file`, `--max-thinking-tokens`,
    `--thinking adaptive|disabled`, `--thinking-display`, `--task-budget`. `--fallback-model`,
    `--max-budget-usd`, `--json-schema`, `--effort` and `--permission-prompts` ARE listed in `--help`.
    The CLI reference ("`claude --help` does not list every flag") documents all of these EXCEPT
    `--max-thinking-tokens`, `--thinking`, `--thinking-display` and `--task-budget`, which are known only
    from the Python SDK's argv builder (`subprocess_cli.py:620` for `--task-budget`, `:757-774` for the
    thinking flags) - treat them as undocumented.
18. **Windows [VERIFIED from SDK source + docs, not run on Windows]:** use the native `claude.exe`
    (`%USERPROFILE%\.local\bin\claude.exe`, or WinGet); refuse npm's `claude.cmd` shim (cmd.exe re-parses
    argv: "BatBadBut"); pass no free text on argv (prompts on stdin, system prompt and MCP config as
    files); set `processx::process$new(encoding = "UTF-8")`; interrupt through the control protocol, not
    signals (on Windows `p$interrupt()` is CTRL+BREAK).
19. **R-specific pitfall found [VERIFIED]:** under a C locale (e.g. `Rscript` with `LANG` unset, as in
    this harness) `jsonlite::toJSON()` turns unmarked non-ASCII strings into literal `<c3><a9>` text, and
    `enc2utf8()` does the same; `jsonlite::fromJSON()` on an UNMARKED UTF-8 JSON string corrupts it the
    same way (verifier re-run). gptr must mark UTF-8 strings (`Encoding(x) <- "UTF-8"`) before
    serialising AND before parsing, and warn when `l10n_info()[["UTF-8"]]` is FALSE.
20. **Recommendation:** default `claude-code` provider = one long-lived `claude -p --input-format
    stream-json --output-format stream-json --verbose --include-partial-messages` child per gptr session,
    driven by processx, built-in tools disabled, gptr's R tools served in-process over the control
    protocol, permissions answered by gptr, events normalised by the shared Anthropic accumulator.
    Fallback transport: the same MCP dispatcher over a loopback httpuv endpoint (also reusable for Codex).

---------------------------------------------------------------------------------------------------

## 2. Findings

### 2.1 Models, context windows, output limits, pricing

Source: https://platform.claude.com/docs/en/about-claude/models/overview.md and
https://platform.claude.com/docs/en/about-claude/pricing.md (both fetched 2026-09-29) [VERIFIED];
cross-checked with the bundled `claude-api` skill (`shared/models.md`, cached 2026-09-25) [VERIFIED].

| Model | Claude API ID (alias) | Context | Max output | Input $/MTok | Output $/MTok | 5m write | 1h write | Cache read | Thinking | Default effort |
|---|---|---|---|---|---|---|---|---|---|---|
| Claude Fable 5.1 | `claude-fable-5-1` | 1M | 128K | 10 | 50 | 12.50 | 20 | 0.25 | adaptive, always on | high |
| Claude Opus 5.5 | `claude-opus-5-5` | 1M | 128K | 4 | 20 | 5 | 8 | 0.20 | adaptive, always on | **medium** |
| Claude Sonnet 5.5 | `claude-sonnet-5-5` | 1M | 128K | 2 | 10 | 2.50 | 4 | 0.20 | adaptive (off = `between_tools`) | high |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001` (`claude-haiku-4-5`) | 200K | 64K | 1 | 5 | 1.25 | 2 | 0.10 | extended (`budget_tokens`) | effort not supported |
| Legacy still served | `claude-fable-5`, `claude-opus-5` ($5/$25), `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-6`, `claude-sonnet-5` ($2/$10), `claude-sonnet-4-6` ($3/$15), `claude-opus-4-5`, `claude-sonnet-4-5` | | | | | | | | | |

Other facts [VERIFIED, same pages]:
- Batch API: 50% off input and output. Fast mode (research preview, Claude API only): Opus 5.5 $8/$40,
  beta `fast-mode-2026-02-01`, body `speed: "fast"`.
- `inference_geo: "us"` multiplies all token prices by 1.1 (4.6+ models).
- "Every Claude model ID is a pinned snapshot, including the dateless IDs used from the 4.6 generation on."
- Tool-use system prompt overhead: Opus 5.5 and Sonnet 5.5 add 286 tokens when `tools` is present.
- Web search: $10 per 1,000 searches plus tokens; web fetch: tokens only; code execution free when used
  with `web_search_20260209`/`web_fetch_20260209`, otherwise 1,550 free hours/month then $0.05/hour.
- Tokenizer: Claude 4.7+ models (all 5.x) produce about 30% more tokens than Sonnet 4.6 for the same text.
- Retirement: Opus 5.5 not sooner than 2027-09-22; Haiku 4.5 not sooner than 2026-10-15 (plan for it).
- Rate limits (Start tier): Opus 5.5 1,000 RPM / 2M ITPM / 400K OTPM; Fable 5.x 1,000 RPM / 500K ITPM /
  100K OTPM. Cache reads do **not** count toward ITPM (all current models).

The Claude Code CLI's own aliases lag the API [VERIFIED, zero-cost `initialize` probe, CLI 2.1.261,
Max account]: `default` and `opus[1m]` -> `claude-opus-5[1m]`, `sonnet` -> `claude-sonnet-5`,
`haiku` -> `claude-haiku-4-5-20251001`, `claude-fable-5-1[1m]` -> `claude-fable-5-1`. So the gptr
`claude-code` provider should pass full model IDs (`--model claude-opus-5-5`) when the user names a model.

### 2.2 Authentication modes for the native API

[VERIFIED: `shared/anthropic-cli.md` lines 31-73 of the claude-api skill; code.claude.com/docs/en/authentication]
- API key: `x-api-key: <key>` (env `ANTHROPIC_API_KEY`).
- Bearer token: `Authorization: Bearer <token>` + `anthropic-beta: oauth-2025-04-20` (env
  `ANTHROPIC_AUTH_TOKEN`). The legitimate source for API-billed OAuth tokens is the Anthropic CLI:
  `ant auth login` (Console account, API billing) then `ant auth print-credentials --access-token`
  (short-lived; re-run before expiry; the no-flag form prints JSON). Profiles live under
  `~/.config/anthropic/` (`%APPDATA%\Anthropic` on Windows) - gptr must not read those files itself.
- If both `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` are set, SDKs send both and the API rejects it
  (status code not stated in the skill [UNCERTAIN that it is 401]). gptr must pick exactly one (precedence: explicit argument > `ANTHROPIC_API_KEY` >
  `ANTHROPIC_AUTH_TOKEN`) and never send both.
- Subscription tokens (from `claude setup-token` or Claude Code's own login) must not be used against
  the API by gptr (section 2.19). Pi detects them by the substring `sk-ant-oat`
  (`packages/ai/src/api/anthropic-messages.ts:914-916`) [VERIFIED in Pi]; gptr can use the same test to
  refuse such a value with an explanatory error [LIKELY that all setup-token values carry that prefix].

### 2.3 Request body fields

[VERIFIED from the claude-api skill (`SKILL.md` quick references, `curl/examples.md`,
`shared/tool-use-concepts.md`) and the fetched API reference; the reference page summary was lossy, so the
list below is assembled from those plus the live CLI stream in 3.14]

Required: `model`, `max_tokens` (0 allowed only for cache pre-warming, non-streaming), `messages`.
Optional (top level): `system` (string or array of text blocks, may carry `cache_control`), `tools`,
`tool_choice` (`auto` | `any` | `tool` | `none`, each may add `disable_parallel_tool_use`),
`thinking` (`{type:"adaptive", display?}` | `{type:"enabled", budget_tokens}` (Haiku 4.5 and older) |
`{type:"disabled"}` (only where allowed) | `{type:"between_tools"}` (Sonnet 5.5 only)),
`output_config` (`effort`: `low|medium|high|xhigh|max`; `format`: `{type:"json_schema", schema}`;
`task_budget` (beta)), `stream`, `stop_sequences`, `metadata` (`{user_id}`), `cache_control`
(top-level automatic caching), `service_tier`, `inference_geo`, `container`, `context_management`
(beta), `mcp_servers` (beta MCP connector), `speed` (beta fast mode), `fallbacks` (beta server-side
refusal fallback), `diagnostics` (beta cache diagnostics). `temperature`/`top_p`/`top_k`: non-default
values are 400 on all 5.x models and Opus 4.7/4.8.

Message roles: `user`, `assistant`, and (on Opus 5/5.5, Opus 4.8, Fable 5/5.1, Sonnet 5.5, not
Sonnet 5 or Haiku) mid-conversation `system` messages appended inside `messages` (not as `messages[0]`,
must follow a user message (or an assistant message ending in server-tool use), AND must be either the
last entry in `messages` or be followed by an `assistant` turn; content text only; unsupported models
return 400 `role 'system' is not supported on this model`) [placement rule added by verifier from skill
`shared/prompt-caching.md:65-81`].

Content block types gptr will send: `text`, `image` (`source` base64 / url / file), `document`
(PDF base64 / url / file; plain-text source), `tool_use` (echoed), `tool_result`, `thinking` and
`redacted_thinking` (echoed verbatim), `server_tool_use` + server tool results (echoed verbatim),
`fallback` blocks (echoed verbatim).

### 2.4 Streaming (SSE)

[VERIFIED: https://platform.claude.com/docs/en/build-with-claude/streaming.md, sections "Event types",
"Content block delta types", "Full HTTP stream response", "Error recovery"]
- Flow: `message_start` (Message with empty `content`, `stop_reason: null`, initial `usage`) ->
  per content block `content_block_start` / `content_block_delta`* / `content_block_stop` (the `index`
  equals the position in the final `content` array) -> one or more `message_delta` (`delta.stop_reason`,
  `delta.stop_sequence`, cumulative `usage`) -> `message_stop`. `ping` events can appear anywhere.
  "new event types may be added, and your code should handle unknown event types gracefully".
- `error` events mid-stream: `event: error` / `data: {"type": "error", "error": {"type":
  "overloaded_error", "message": "Overloaded"}}` (would be HTTP 529 non-streaming).
- `input_json_delta.partial_json` fragments are concatenated and parsed at `content_block_stop`;
  `tool_use.input` starts as `{}` in `content_block_start`. Server tool result blocks (e.g.
  `web_search_tool_result`) arrive complete in `content_block_start` with no deltas; `fallback` blocks
  arrive as a start/stop pair with no deltas.
- `thinking` blocks: `thinking_delta`s then one `signature_delta` just before `content_block_stop`. With
  `display: "omitted"` the block gets one `thinking_delta` with empty text then the signature
  (observed live in 3.14).
- Under the `thinking-binding-controls-2026-08-01` beta, `message_start.message` carries
  `input_transformations`.
- Error recovery on 4.6+ models: resend with a *user* message containing the partial response and
  "Continue from where you left off" (no assistant prefill); tool-use and thinking blocks cannot be
  partially recovered.

Extra fields seen in real traffic (call 2) [VERIFIED]: `message.container`, `message.stop_details`,
`message.diagnostics`, `message.context_management`, `usage.cache_creation.{ephemeral_5m_input_tokens,
ephemeral_1h_input_tokens}`, `usage.service_tier`, `usage.inference_geo`,
`usage.output_tokens_details.thinking_tokens`, `usage.iterations[]`, `message_delta.context_management
.applied_edits`, `tool_use.caller: {"type":"direct"}`. Accumulators must copy unknown fields through.

### 2.5 Tool use

[VERIFIED: https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls.md;
skill `shared/tool-use-concepts.md` lines 5-165; stop-reasons page]
- Definition: `{name, description, input_schema}` plus optional `strict: true` (schema must set
  `additionalProperties:false` and `required`), `eager_input_streaming: true` (streaming only; client
  tools only; the API then stops validating/coercing, so gptr validates), `cache_control`,
  `defer_loading: true` (with tool search / mid-conversation tool additions), `input_examples`.
- Tool names must match `^[a-zA-Z0-9_-]{1,128}$` [CORRECTED by verifier: define-tools.md, "Must match the
  regex"; the earlier `{1,64}` was wrong]. Pi's `anthropic-messages.ts:1215-1218` (`normalizeToolCallId`)
  normalises tool-call IDs (`tool_use.id`), not tool names, to `[a-zA-Z0-9_-]` and 64 chars. gptr may still
  cap its own tool names at 64 chars for cross-provider portability (design choice, not an API limit).
- `tool_result`: `{type:"tool_result", tool_use_id, content?, is_error?}`; `content` is a string, or a
  list of `text` / `image` / `document` / `search_result` blocks; it can be omitted (empty result).
- Ordering: tool results must immediately follow the assistant turn with the `tool_use` blocks; in that
  user message the `tool_result` blocks come FIRST; any text after them. If the assistant turn also has
  an unresolved `server_tool_use`, the user message may contain only `tool_result` blocks.
- Parallel tool use is on by default; return all results in one user message (the parallel-tool-use
  docs say parallelism keeps working only when all results come back in a single user message with no
  text before them; the earlier "silently trains..." wording was not found in the fetched docs); a
  failed tool still gets a `tool_result` with
  `is_error: true`. `disable_parallel_tool_use: true` limits to at most one call.
- Empty `end_turn` responses are commonly caused by "Adding text blocks immediately after tool results";
  do not retry an empty reply unchanged, add "Please continue" as a new user message.
- Forced tool use (`tool_choice` `any`/`tool`) returns 400 on Opus 5.5, Sonnet 5.5, Fable 5.1 (also on
  `count_tokens` and Batches): use `auto` + prompt instruction + `strict: true`, and check a call happened.
- With eager input streaming, on `stop_reason` `max_tokens` or `refusal` never execute that turn's tools;
  on parse/validation failure answer with `is_error:true` content `{"INVALID_JSON": "<raw>"}` built with a
  JSON encoder.

### 2.6 Thinking, effort, and preserving thinking blocks

[VERIFIED: https://platform.claude.com/docs/en/build-with-claude/thinking.md ("Configuring thinking"
table, "Preserving thinking blocks", "Interleaved thinking", "Progress updates between tool calls",
"Thinking block preservation by model", "Preserved thinking", "Redacted thinking blocks"); skill
`shared/model-migration.md` lines 1600-1674 and 1867-2066]

Per-model behaviour of the `thinking` field (subset):

| Model | omitted | `adaptive` | `enabled`+budget | `between_tools` | `disabled` |
|---|---|---|---|---|---|
| Opus 5.5 | adaptive | adaptive | 400 | 400 | 400 |
| Sonnet 5.5 | adaptive | adaptive | 400 | up-front thinking off (effort <= high) | 400 |
| Fable 5.1 | adaptive | adaptive | 400 | 400 | 400 |
| Opus 5 | adaptive | adaptive | 400 | 400 | off at effort <= high |
| Haiku 4.5 | off | 400 | extended thinking | 400 | off |

- `display`: `"summarized"` returns a summary of reasoning, `"omitted"` (default on all 5.x) returns
  empty `thinking` strings, `"updates"` (beta `thinking-display-updates-2026-08-18`) returns only
  progress-update notes. The raw chain of thought is never returned. Billing is identical.
- `effort` is in `output_config`; Opus 5.5 defaults to `medium`, others to `high`. Changing top-level
  effort or thinking config invalidates the messages cache; per-message effort via a
  `{"role":"system","content":[],"output_config":{"effort":...}}` message (beta
  `mid-conversation-output-config-2026-07-01`) does not.
- Tool loops: "within a tool-use turn, pass thinking blocks back" complete and unmodified (including
  empty-text blocks and `redacted_thinking` blocks with their opaque `data`); across turns "pass
  everything back"; the API filters and bills only what it keeps. Modified blocks in the latest
  assistant message -> 400 ("`thinking` or `redacted_thinking` blocks in the latest assistant message
  cannot be modified").
- Preserved thinking (Fable 5.1, Opus 5.5, Sonnet 5.5): a block is valid only while the system prompt,
  the tool set and all earlier messages are byte-identical; edits invalidate that block and every later
  one. Enforced by default for accounts created on/after 2026-08-31 (400 `Invalid signature in thinking
  block. The block is bound to a different conversation...`). Opt-in controls: beta
  `thinking-binding-controls-2026-08-01` + `thinking.block_binding.prefix_mismatch_behavior`
  (`"error"` | `"drop_block"`) -> response `input_transformations` array. Allowed: appending messages,
  appended `role:"system"` messages, moving `cache_control` markers, changing request params outside
  system/tools/messages, removing a *leading* run of thinking blocks, server-side compaction/context
  editing.
- Model binding: Opus 5.5 reads blocks from Opus 5 and older Opus/Sonnet/Haiku; only Fable 5.1/Mythos 5.1
  (Claude API) read Opus 5.5 blocks; nobody else reads Sonnet 5.5's; Sonnet 5.5 blocks are also bound to
  the producing account. Switching models: keep passing blocks unchanged; the API drops unreadable ones,
  unbilled.
- Interleaved thinking is automatic with adaptive thinking (no beta header).

### 2.7 Prompt caching

[VERIFIED: skill `shared/prompt-caching.md` (whole file); pricing page]
- Prefix match over the rendered order `tools` -> `system` -> `messages`; any byte change invalidates
  everything after it. Max 4 breakpoints; `cache_control: {type:"ephemeral"}` (5 min) or
  `{type:"ephemeral", ttl:"1h"}`; longer TTL entries must precede shorter ones.
- Minimum cacheable prefix: 512 tokens on Opus 5.5/5, Fable 5.x, Sonnet 5.5; 1024 on Opus 4.8, Sonnet 5,
  Sonnet 4.6; 4096 on Haiku 4.5 and Opus 4.6/4.5. Below the minimum: silently no caching.
- "The robust combination for agent loops": one explicit breakpoint on the last block of the static
  system prefix plus top-level automatic caching (`cache_control` at the request top level) for the
  growing tail. Automatic caching also consumes one of the 4 slots.
- 20-block lookback: each breakpoint looks back at most 20 positions (runs of consecutive `tool_use` or
  `tool_result` blocks count as one); add intermediate breakpoints in very long single turns.
- Invalidation hierarchy: tool-definition changes and model switches invalidate everything; system prompt
  changes invalidate system + messages; `tool_choice`/image toggles invalidate messages; thinking/effort
  changes invalidate messages (and, model-specific, more). Caches are model-scoped and workspace-scoped.
- A cache entry becomes readable only once the first response starts streaming (fan-out: send one, await
  first token, then the rest).
- Pre-warm/keep-alive: non-streaming request with `max_tokens: 0` (rejected with `stream: true`,
  structured outputs, forced tool_choice, Batches).
- Pi's placement [VERIFIED, Pi `anthropic-messages.ts:1085-1107` (system blocks), `:1407-1431` (last
  block of the last user/system message), `:1497` (last tool)]: system + last tool + tail.
- Claude Code itself uses 1-hour cache writes on subscription traffic [VERIFIED, call 2 usage:
  `"ephemeral_1h_input_tokens":7448`].

### 2.8 Images and PDFs

[VERIFIED: https://platform.claude.com/docs/en/build-with-claude/vision.md; skill SKILL.md "Document &
File Input"]
- Formats: `image/jpeg`, `image/png`, `image/gif` (first frame), `image/webp`. Sources: `base64`
  (`{type, media_type, data}`), `url`, `file` (Files API `file_id`, GA, no beta header).
- Limits: 10 MB per image (base64) on the Claude API (5 MB on Bedrock/Vertex); 8000x8000 px max;
  600 images per request (100 for 200K-context models such as Haiku 4.5); with more than 20 images a
  stricter per-image limit applies (stay <= 2000 px per side); 32 MB total request.
- Cost: `ceil(w/28) * ceil(h/28)` visual tokens; Claude 4.7+ models: long edge up to 2576 px /
  4784 visual tokens before downscaling (older: 1568 px / 1568 tokens). Tool-result images from the
  computer/browser toolsets are rejected rather than downscaled.
- PDFs: `{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":...}}`
  before the question text; 32 MB request, 600 pages (100 for 200K-context models); optional
  `citations: {enabled: true}`.
- For R plots: render PNG at, e.g., 1024-1568 px long edge; put it inside the `tool_result`.

### 2.9 Token counting and models list

[VERIFIED: https://platform.claude.com/docs/en/build-with-claude/token-counting.md and
https://platform.claude.com/docs/en/api/models/list.md]
- `POST /v1/messages/count_tokens`, same body as Messages (model, system, messages, tools, thinking,
  tool_choice...), response `{"input_tokens": N}`. Free, own RPM limit (Start 5,000). Estimate only.
  Rejects server tools (except advisor), MCP connector, and `url`/`file` image/document sources.
  Runs the preserved-thinking check and the forced-tool_choice check too.
- `GET /v1/models?limit=1..1000(default 20)&after_id=&before_id=` -> `{data:[ModelInfo], has_more,
  first_id, last_id}`; `ModelInfo` = `{type:"model", id, display_name, created_at, max_input_tokens,
  max_tokens, capabilities:{batch, citations, code_execution, context_management{...}, effort{low,
  medium, high, xhigh, max, supported}, image_input, pdf_input, structured_outputs, thinking{supported,
  types{adaptive, enabled}}}}` (each leaf `{supported: bool}`). `GET /v1/models/{id}` for one model.

### 2.10 Stop reasons

[VERIFIED: https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons.md; skill]
`end_turn`, `max_tokens`, `stop_sequence`, `tool_use`, `pause_turn` (server-tool loop hit its
iteration limit: resend the assistant content, no extra "continue" message), `refusal` (safety
classifier; `stop_details: {type:"refusal", category, explanation}` only in this case; never run tools
from a refused turn), `model_context_window_exceeded` (treat as truncated). `stop_reason` is `null` in
`message_start` and arrives in `message_delta`.

### 2.11 Errors, retries, limits

[VERIFIED: https://platform.claude.com/docs/en/api/errors.md, https://platform.claude.com/docs/en/api/rate-limits.md,
skill `shared/error-codes.md`]

| HTTP | `error.type` | Retry? |
|---|---|---|
| 400 | `invalid_request_error` (also: your own spend limit reached) | no |
| 401 | `authentication_error` | no |
| 402 | `billing_error` | no |
| 403 | `permission_error` | no |
| 404 | `not_found_error` (unknown model or not available to org) | no |
| 409 | `conflict_error` | yes (mirrors the SDKs' default retry set; the errors page says "resolve the conflict, then retry") |
| 413 | `request_too_large` (Messages 32 MB, Batch 256 MB, Files 500 MB) | no |
| 429 | `rate_limit_error` | yes, honour `retry-after`; NOT if `error.details.error_code == "enforced_spend_limit_reached"` (no `retry-after`) |
| 500 | `api_error` | yes, backoff |
| 504 | `timeout_error` | yes (prefer streaming) |
| 529 | `overloaded_error` | yes, backoff |

408 is not a documented Messages API status; retrying it is a transport-level choice copied from the SDKs
[LIKELY]. A spend limit on the Claude Code workspace can return 429 instead of 400 (errors page).
Error body: `{"type":"error","error":{"type":...,"message":...},"request_id":"req_..."}`; header
`request-id` on every response. SDK default: 2 retries with exponential backoff honouring `retry-after`.
Rate-limit headers: `retry-after` (seconds), `anthropic-ratelimit-{requests,tokens,input-tokens,
output-tokens}-{limit,remaining,reset}` (reset in RFC 3339), `anthropic-priority-*` (Priority Tier),
`anthropic-fast-*` (fast mode), `anthropic-workspace-id`. Long requests: stream (or Batches) for anything
that may exceed 10 minutes; enable TCP keep-alive.

### 2.12 Server-side tools worth exposing in gptr

[VERIFIED: skill SKILL.md "Server Tools (Quick Reference)", `shared/tool-use-concepts.md` 169-260]
| Tool | Declaration | Result block | Notes |
|---|---|---|---|
| Web search | `{"type":"web_search_20260209","name":"web_search"}` (+ `max_uses`, `allowed_domains`/`blocked_domains`, `user_location`) | `web_search_tool_result` (list on success, error object on failure) | $10/1k searches; dynamic filtering built in on Opus 5.5/Sonnet 5.5; older models `web_search_20250305` |
| Web fetch | `{"type":"web_fetch_20260209","name":"web_fetch"}` (+ `max_uses`, domains, `citations`, `max_content_tokens`) | `web_fetch_tool_result` | only fetches URLs already in the conversation |
| Code execution | `{"type":"code_execution_20260521","name":"code_execution"}` | `bash_code_execution_tool_result` | Python sandbox; low value for gptr (R is local). [CORRECTED by verifier, code-execution-tool.md] `_20260521` is the latest version; it is NOT needed for the web tools' dynamic filtering (the API provisions it), and if declared alongside `web_search_20260209`/`web_fetch_20260209` it must be `code_execution_20260120` or later and is then free - the earlier "don't combine" advice was wrong |
| Advisor (beta `advisor-tool-2026-03-01`) | `{"type":"advisor_20260301","name":"advisor","model":...}` | `advisor_tool_result` | executor/advisor pairing rules; useful for REQ-34 later |
Server-tool errors return HTTP 200 with an error object inside the result block; `pause_turn` must be
handled. Recommend exposing web search and web fetch behind `gptr(..., web = TRUE)`.

### 2.13 Claude Code headless: flags

[VERIFIED: `claude --help` / `claude -p --help` captured locally (identical to the earlier attempt's
captures); https://code.claude.com/docs/en/cli-reference; hidden flags probed with no prompt sent]

Relevant flags for gptr (all accepted by CLI 2.1.261; "(hidden)" = not in `--help`):

| Flag | Use in gptr |
|---|---|
| `-p, --print` | headless mode (required) |
| `--output-format stream-json` + `--verbose` | NDJSON output; `stream-json` without `--verbose` fails: `Error: When using --print, --output-format=stream-json requires --verbose` (observed) |
| `--input-format stream-json` | NDJSON input on stdin; required for the control protocol, multi-turn, images |
| `--include-partial-messages` | adds `stream_event` lines (raw Anthropic SSE events) for token streaming |
| `--replay-user-messages` | echoes stdin user messages (acknowledgement); optional |
| `--model <alias or full id>` | pass full IDs (`claude-opus-5-5`) |
| `--effort low|medium|high|xhigh|max|ultracode` | maps gptr effort |
| `--thinking adaptive|disabled`, `--thinking-display`, `--max-thinking-tokens` (hidden) | used by the official SDK (`subprocess_cli.py:757-774`); NOT in the CLI reference either - undocumented |
| `--system-prompt-file <path>` / `--system-prompt` | replace Claude Code's prompt with gptr's (hidden in help, documented) |
| `--append-system-prompt-file` / `--append-system-prompt` | append instead |
| `--tools ""` | remove all built-in tools (MCP tools unaffected; CLI reference: `""` removes the `EndConversation` tool only when no MCP tools remain - not observed in 2.1.261's `system/init.tools`) |
| `--allowedTools`, `--disallowedTools` | permission rules; `"mcp__*"` removes all MCP tools |
| `--mcp-config <file or JSON>`, `--strict-mcp-config` | register gptr's MCP server only |
| `--setting-sources ""`, `--disable-slash-commands` | ignore user/project/local settings, CLAUDE.md, skills |
| `--permission-mode default|acceptEdits|plan|auto|dontAsk|bypassPermissions|manual` | baseline |
| `--permission-prompt-tool stdio` (hidden in `--help`) | route permission prompts to the host via `can_use_tool` control requests. The flag is documented (value = an MCP tool name); the `stdio` value is undocumented and is what the Python SDK sets when `can_use_tool` is given (`types.py:1927-1949`) |
| `--permission-prompts host|none` | `none` = deny anything that would prompt (unattended runs) |
| `--session-id <uuid>`, `--resume <id or .jsonl path>`, `--continue`, `--fork-session`, `--no-session-persistence` | sessions |
| `--max-turns <n>` (hidden in help), `--max-budget-usd <x>` | safety caps (`error_max_turns` / budget result subtypes) |
| `--json-schema <schema>` | structured output in `result.structured_output` |
| `--add-dir <dir...>` | extra directories for built-in file tools (not needed with `--tools ""`) |
| `--settings <file-or-json>`, `--agents <json>` | inject settings / subagents |
| `--fallback-model a,b` | overload fallback (print mode only) |
| `--bare` | DO NOT USE for the plan route: "never reads OAuth credentials or the system keychain" |
| `--betas` | ignored for subscription users (observed: `Warning: Custom betas are only available for API key users. Ignoring provided betas.`) |
| `--exclude-dynamic-system-prompt-sections`, `--system-prompt-snapshot on|off` | cache-friendliness with the default prompt |

Other observed behaviours [VERIFIED]:
- Unknown flags exit 1 with `error: unknown option '--x'` on stderr before any network activity.
- `--session-id not-a-uuid` -> `Error: Invalid session ID. Must be a valid UUID.`
- `-p` with no prompt and empty stdin in text mode -> `Error: Input must be provided either through stdin or as a prompt argument when using --print`.
- With `--input-format stream-json` and an empty stdin the CLI exits 0 with no request made; it is
  silent only with the isolation flags. Without `--setting-sources ""` the user's plugin/settings
  `SessionStart` hooks run and emit `system/hook_started` / `system/hook_response` lines before any
  `system/init` (verifier re-run; CLI reference: SessionStart and Setup hook events are always included
  in stream-json). gptr's event mapper must ignore/log `hook_*` subtypes.
- `stream-json` output without `--verbose` fails with the quoted error when stdin is stream-json; with
  text input and an empty stdin the "Input must be provided..." error is reported first (verifier re-run).
- `--resume` with an unknown id emits a `result` line with `subtype: "error_during_execution"`,
  `is_error: true`, `errors: ["No conversation found with session ID: ..."]`, zero cost.
- Exit code 143 on SIGTERM leaves the turn unfinished; SIGINT or the `interrupt` control request ends
  it cleanly (headless docs "Stop a run with SIGTERM").
- Piped stdin capped at 10 MB (headless docs).

### 2.14 Claude Code stream-json protocol

[VERIFIED: live capture (3.14), official Python Agent SDK source at commit f2204bb (2026-09-29):
`src/claude_agent_sdk/_internal/query.py:340-376, 577-751, 786-869`,
`_internal/transport/subprocess_cli.py:570-791`, `_internal/message_parser.py`, `types.py:1340-1377`;
headless docs]

Host -> CLI (one JSON object per line on stdin):
- User turn: `{"type":"user","message":{"role":"user","content":<string or content blocks>},
  "parent_tool_use_id":null,"session_id":""}`. Content blocks are Anthropic content blocks, so images and
  documents can be sent [LIKELY; text verified live].
- Control request: `{"type":"control_request","request_id":"req_<n>_<hex>","request":{"subtype":...}}`
  with subtypes `initialize` (`hooks`, `agents`, `skills`, `excludeDynamicSections`,
  `systemPromptSnapshot`, `forwardSubagentText`), `interrupt`, `set_permission_mode` (`mode`),
  `set_model` (`model`), `mcp_status`, `get_context_usage`, `mcp_reconnect`, `mcp_toggle`,
  `rewind_files`, `stop_task`.
- Control response (answering the CLI): `{"type":"control_response","response":{"subtype":"success",
  "request_id":...,"response":{...}}}` or `{"subtype":"error","request_id":...,"error":"..."}`.
- EOF on stdin ends the session after the current work (the CLI exits 0).

CLI -> host (stdout):
- `system/init` (session metadata: `session_id`, `model`, `tools`, `mcp_servers[{name,status}]`,
  `permissionMode`, `apiKeySource`, `claude_code_version`, `capabilities`
  `["interrupt_receipt_v1","interrupt_cancel_queued_v1","msg_lifecycle_v1"]`, ...). Emitted when the
  first user turn starts, not at process start.
- `system/status` (`status:"requesting"`), `system/thinking_tokens` (estimates), `system/api_retry`
  (`attempt`, `max_retries`, `retry_delay_ms`, `error_status`, `error` category), `system/permission_denied`,
  `system/task_*` (subagents), hook events.
- `rate_limit_event` - plan usage, NESTED under `rate_limit_info` (verifier, fixture 3.14):
  `{"type":"rate_limit_event","rate_limit_info":{...}}` where `rate_limit_info` =
  `{"status":"allowed","resetsAt":<epoch>,"rateLimitType":"five_hour",
  "overageStatus":...,"unifiedWindows":{"five_hour":{"utilization":0.15,"resetsAt":...},
  "seven_day":{"utilization":0.34,...}}}` (observed; useful for a gptr status line).
- `stream_event` - `{"type":"stream_event","event":<raw Anthropic SSE data object>,"session_id",
  "parent_tool_use_id","uuid"}`; the CLI adds `ttft_ms` to `message_start` lines and
  `estimated_tokens` to `thinking_delta`s.
- `assistant` - one snapshot per completed content block (`message.content` has ONE block), with the
  full `tool_use.input`, `usage`, `request_id`; plus `tool_use_meta` for MCP tools.
- `user` - tool results the CLI produced (`message.content[].tool_result`, `tool_use_result`).
- `result` - end of turn: `subtype` (`success`, `error_during_execution`, `error_max_turns`,
  `error_max_budget_usd`, ...), `is_error`, `result` (final text), `stop_reason`, `num_turns`,
  `session_id`, `total_cost_usd` (client-side estimate), `usage`, `modelUsage` (per model incl.
  `contextWindow`, `maxOutputTokens`, `costUSD`), `permission_denials`, `errors`, `api_error_status`
  (an API failure arrives as `subtype:"success"` with `is_error:true`), `terminal_reason`
  (`completed`, `max_turns`, `aborted_streaming`, `aborted_tools`), `structured_output`, timings.
- `control_request` from the CLI: `mcp_message` (`server_name`, JSON-RPC `message`), `can_use_tool`
  (`tool_name`, `display_name`, `input`, `permission_suggestions`, `tool_use_id`, ...),
  `hook_callback` (`callback_id`, `input`, `tool_use_id`). `control_cancel_request` cancels one.
- `control_response` to host requests.

Observed responses to host control requests while idle (zero-cost probe, 3.13): `interrupt` ->
`{"still_queued":[]}`; `set_permission_mode` -> `{"mode":"acceptEdits"}`; `set_model` -> `null`;
`get_context_usage` -> `{categories:[{name,tokens,color}], totalTokens, maxTokens, rawMaxTokens,
autocompactSource, ...}`; unknown subtype -> error `Unsupported control request subtype: ...`.
`initialize` returns `commands, agents, output_style, available_output_styles, models[{value,
resolvedModel, displayName, description, supportsEffort, supportedEffortLevels,
supportsAdaptiveThinking, supportsFastMode, supportsAutoMode}], account{email, organization,
subscriptionType, apiProvider}, pid, current_permission_mode, fast_mode_state, session_state, ...`
(gptr must never log `account`).

### 2.15 Giving headless Claude Code custom tools - options analysed

Claude Code only accepts extra tools through MCP (headless docs, Agent SDK custom-tools docs) [VERIFIED].

| Option | How | Tools run where | Verdict |
|---|---|---|---|
| A. In-process "sdk" MCP over the control protocol | `--mcp-config` file with `{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}`; answer `mcp_message` control requests | inside the live R session (R is blocked in the pump loop and runs the handler synchronously) | **Recommended.** Verified live (call 2). No port/token/firewall; not subject to the MCP idle timeout ("Doesn't apply to IDE servers or SDK in-process servers", env-vars docs); same pipe as events. Relies on a protocol that is documented only through the open-source SDKs. |
| B. HTTP MCP server inside R (httpuv) | `{"type":"http","url":"http://127.0.0.1:<port>/mcp","headers":{"Authorization":"Bearer <token>"},"alwaysLoad":true}`; R pumps `httpuv::service()` while waiting | inside the live R session | **Fallback** (older CLIs, and reusable for the Codex CLI). Verified offline against a JSON-RPC client (proto4/4b), not live with Claude Code. Network servers get a 5-minute idle abort unless a per-server `timeout` or progress notifications are used. ALSO (verifier, mcp.md): HTTP servers have a per-request timer to the first response byte = max(60 s, the server's tool timeout, `MCP_TIMEOUT`), and the unset 28-h `MCP_TOOL_TIMEOUT` default does not count - because httpuv answers only after the R code finishes, gptr MUST put a per-server `"timeout"` (ms) in the HTTP config or any tool call over 60 s aborts. Needs httpuv (Suggests). |
| C. Claude Code built-in tools (Bash, Read, Edit...) | default `--tools` | in a separate shell/process | Rejected for gptr's core: code would run in a fresh R process, losing in-memory objects (violates REQ-09/REQ-22). Could be allowed on request for file work. |
| D. Plain text generator | `--tools ""`, no MCP; gptr parses R code blocks from replies or uses `--json-schema` actions, executes them, sends output as the next user message | inside R | Degraded mode only: no native tool calls, more turns, weaker results, output-format fragility. |

What "running tools INSIDE the live R session" means with A/B: gptr's `gptr()` call stays on the R call
stack, pumping the CLI's stdout (and, for B, httpuv). When a tool call arrives, gptr evaluates the R
code in the captured environment (`parent.frame()` of `gptr()`), captures output/plots, and replies.
Objects created by the tool persist (verified: `live$answer == 24` after call 2). While a tool runs, the
CLI waits; the user can Ctrl-C (gptr catches the R interrupt, returns an `isError` result or sends a
`control_request` `interrupt`).

### 2.16 Sessions

[VERIFIED live + headless docs]
- The CLI owns the conversation state for this provider. Session transcript path observed:
  `~/.claude/projects/-private-tmp-...-track-07-ccwd/<session_id>.jsonl` (sessions docs: cwd with every
  non-alphanumeric character replaced by `-`; names over 200 chars truncated plus a hash of the path -
  do not re-derive the path, read `session_id` and use `--resume`); record types seen: `user`, `assistant`, `attachment`, `queue-operation`, `last-prompt`,
  `ai-title`, `mode`, `atis-latch`.
- `--resume <id>` works from any directory on the machine (docs, v2.1.223+); `--fork-session` branches;
  `--no-session-persistence` makes a session non-resumable.
- Claude Code makes auxiliary model calls (e.g. session title, `ai-title`) - visible as extra
  `modelUsage.inputTokens` (946 vs 20 on the main requests in call 2) - small extra plan usage [LIKELY].
- `--system-prompt*` text is recorded on the first request and reused on resume until compaction
  (`--system-prompt-snapshot`), so gptr must send the same system prompt file on resume.

### 2.17 Claude Agent SDK

[VERIFIED: https://code.claude.com/docs/en/agent-sdk/overview, .../custom-tools, SDK source]
- Python (`claude-agent-sdk`) and TypeScript (`@anthropic-ai/claude-agent-sdk`) libraries that spawn the
  Claude Code binary (bundled per platform, or found on PATH) with `--output-format stream-json --verbose
  --input-format stream-json` and speak the control protocol above. There is no R SDK. "To drive the
  same agent loop from a language other than Python or TypeScript, run the CLI as a subprocess with the
  `-p` flag and `--output-format json`" (overview page; the quote ends with the json flag, gptr uses
  stream-json instead).
- Custom tools = in-process SDK MCP servers (`create_sdk_mcp_server` / `createSdkMcpServer`), named
  `mcp__<server>__<tool>`; results `{content:[text|image|audio|resource|resource_link], isError?,
  structuredContent?}`; `readOnlyHint: true` allows parallel calls; tool search defers SDK MCP tools
  unless `alwaysLoad: true` (observed: with `--tools ""` both R tools appeared directly in
  `system/init.tools`).
- Auth rule on the SDK overview: "Unless previously approved, Anthropic does not allow third party
  developers to offer claude.ai login or rate limits for their products, including agents built on the
  Claude Agent SDK. Use the API key authentication methods described in the Quickstart instead."
- License: SDK use is governed by the Commercial Terms of Service.
- Branding: products must not be called "Claude Code" or mimic it; "Claude Agent" / "Powered by Claude"
  allowed.

### 2.18 Subscription (plan) policy - timeline and current text

[VERIFIED sources in brackets]
- 2026-01 [UNCERTAIN]: Anthropic briefly blocked subscription OAuth tokens outside official apps, then
  reversed [search results: gigazine.net 2026-02-20, winbuzzer.com 2026-02-19 - search snippets only, not
  fetched].
- 2026-02-19 [UNCERTAIN]: docs clarified that OAuth tokens from Free/Pro/Max are for Claude Code and
  Claude.ai only [same search snippets; consistent with the current legal page below].
- 2026-04-04: Anthropic email: "starting April 4, third-party harnesses like OpenClaw connected to your
  Claude account will draw from extra usage instead of from your subscription."
  [https://news.ycombinator.com/item?id=47633464]. Pi now shows: "Anthropic subscription auth is
  active. Third-party harness usage draws from extra usage and is billed per token, not your Claude plan
  limits." [Pi `packages/coding-agent/src/modes/interactive/interactive-mode.ts:299`; issue
  https://github.com/earendil-works/pi/issues/3670, 2026-04-24].
- 2026-05-13: plan announced to move Agent SDK, `claude -p`, GitHub Actions and "third-party apps that
  authenticate with your Claude subscription through the Agent SDK" to a separate monthly credit from
  2026-06-15 [https://venturebeat.com/...-with-a-catch; support article].
- 2026-06-15/16: paused. Current support text: "We're pausing the changes to Claude Agent SDK usage
  described below. For now, nothing has changed: Claude Agent SDK, `claude -p`, and third-party app usage
  still draw from your subscription's usage limits." Last updated 2026-06-16
  [https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan].
- Current legal page ("Authentication and credential use") [https://code.claude.com/docs/en/legal-and-compliance]:
  OAuth "is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise
  subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic
  applications"; developers building products "should use API key authentication"; "Anthropic does not
  permit third-party developers to offer Claude.ai login into their own applications, or to route
  requests through Free, Pro, or Max plan credentials on behalf of their users. Moreover, developers may
  not collect, store, or intermediate Claude.ai credentials or session tokens"; but "Nor does it prevent
  an end user from signing in to the unmodified Claude Code binary with their own Claude subscription".
  Also: "Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code
  and the Agent SDK." Anthropic "may [enforce] without prior notice".
- Same legal page, section "Can customers offer Claude Code in their products?" [VERIFIED 2026-09-29 by
  verifier; applicability to gptr UNCERTAIN]: preinstalling or running Claude Code in your products or
  services requires agreeing to the Commercial Terms, keeping the binary unmodified (no auth method
  removed or disabled), and never paying for, reselling or intermediating end users' Claude usage (each
  end user authenticates with their own key, plan or 3P credential). Name/logo rule: a product may say in
  plain text that it runs Claude Code, but may not use the Claude Code or Anthropic names/logos in its own
  product, feature or company name. gptr runs the user's own install rather than shipping it, but this
  section and the provider id `"claude-code"` are worth raising with Anthropic (see 7.1).
- `claude setup-token` [https://code.claude.com/docs/en/authentication]: one-year OAuth token for CI and
  scripts, printed not saved; used via `CLAUDE_CODE_OAUTH_TOKEN` (precedence 5 of 7, below cloud
  providers, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `apiKeyHelper`); "It can only make model
  requests"; "Bare mode does not read `CLAUDE_CODE_OAUTH_TOKEN`". Credentials are stored in the macOS
  Keychain, `~/.claude/.credentials.json` (Linux, mode 0600), `%USERPROFILE%\.claude\.credentials.json`
  (Windows).

Sanctioned-route table (my reading of the above):

| Route | Status | Notes |
|---|---|---|
| gptr spawns the user's unmodified `claude` CLI; user signed in via `claude`/`claude auth login` | **Allowed with caveats** (gray area for a distributed tool, see 1.11) | gptr never reads, stores or forwards credentials; draws plan limits (June 2026 text) |
| Same, with `CLAUDE_CODE_OAUTH_TOKEN` set by the user (from `claude setup-token`) in the CLI's env | Allowed (documented CI/script path for Claude Code) | gptr only passes the variable through to the child; never uses it itself |
| gptr (or Pi) uses a subscription OAuth token directly against api.anthropic.com | **Not allowed** | "route requests through ... plan credentials", "collect, store, or intermediate"; billed as extra usage since 2026-04-04 |
| gptr implements its own claude.ai OAuth login (Pi's PKCE flow) | **Not allowed** | "offer Claude.ai login into their own applications" |
| gptr uses the user's Console API key or `ant auth login` Console OAuth token (API billing) | Allowed | normal API usage |
| Agent SDK (Python/TS) inside a product with claude.ai login | Not allowed "unless previously approved" | |

### 2.19 How Pi does Anthropic subscription auth today

[VERIFIED in the Pi clone, commit 1b347794]
- `packages/ai/src/auth/oauth/anthropic.ts:13-22`: PKCE authorization-code flow against
  `https://claude.ai/oauth/authorize` with token endpoint `https://platform.claude.com/v1/oauth/token`,
  loopback redirect `http://localhost:53692/callback`, scopes `org:create_api_key user:profile
  user:inference user:sessions:claude_code user:mcp_servers user:file_upload`, and Claude Code's own OAuth
  client id stored base64-obfuscated (`CLIENT_ID = decode("...")`, line 14 - not reproduced here).
  Refresh via `grant_type: refresh_token` (lines 188-200); expiry stored 5 minutes early (line 131).
- `packages/ai/src/api/anthropic-messages.ts:86` "Stealth mode: Mimic Claude Code's tool naming exactly"
  (`claudeCodeVersion = "2.1.280"`, CC tool names list lines 89-110); `:914-916` token detection by
  `sk-ant-oat`; `:948-968` OAuth requests use Bearer auth with `user-agent: claude-cli/<version>` and
  `x-app: cli`; `:1025` adds betas `claude-code-20250219`, `oauth-2025-04-20`; `:1085-1090` "For OAuth
  tokens, we MUST include Claude Code identity" (system text "You are Claude Code, Anthropic's official
  CLI for Claude."); tool names renamed to Claude Code casing (`:1268`, `:1367`).
- Pi never drives the Claude Code CLI (grep for `stream-json` / `claude-agent-sdk` in `packages/`: no
  matches).
- Conclusion: Pi's approach impersonates Claude Code with a borrowed client id; gptr must not port it.

---------------------------------------------------------------------------------------------------

## 3. Exact specifications

### 3.1 Native API request (streaming, adaptive thinking, tools, caching) - canonical gptr shape

```http
POST https://api.anthropic.com/v1/messages
x-api-key: <ANTHROPIC_API_KEY>            (or: Authorization: Bearer <token> + anthropic-beta: oauth-2025-04-20)
anthropic-version: 2023-06-01
content-type: application/json
accept: text/event-stream
anthropic-beta: server-side-fallback-2026-07-01      (only when the fallbacks field is sent)
```
```json
{
  "model": "claude-opus-5-5",
  "max_tokens": 64000,
  "stream": true,
  "cache_control": {"type": "ephemeral"},
  "system": [{"type": "text", "text": "<frozen gptr system prompt>", "cache_control": {"type": "ephemeral"}}],
  "tools": [
    {"name": "list_objects", "description": "...", "eager_input_streaming": true,
     "input_schema": {"type": "object", "properties": {}, "required": []}},
    {"name": "r_eval", "description": "Evaluate R code in the live session. Call this whenever you need to compute.",
     "eager_input_streaming": true,
     "input_schema": {"type": "object", "properties": {"code": {"type": "string", "description": "R code"}},
                      "required": ["code"]}}
  ],
  "thinking": {"type": "adaptive", "display": "summarized"},
  "output_config": {"effort": "medium"},
  "fallbacks": "default",
  "messages": [
    {"role": "user", "content": "Summarise x and plot it."},
    {"role": "assistant", "content": [
      {"type": "thinking", "thinking": "", "signature": "<opaque, verbatim>"},
      {"type": "text", "text": "I will inspect x."},
      {"type": "tool_use", "id": "toolu_01A", "name": "r_eval", "input": {"code": "summary(x)"}},
      {"type": "tool_use", "id": "toolu_01B", "name": "list_objects", "input": {}}]},
    {"role": "user", "content": [
      {"type": "tool_result", "tool_use_id": "toolu_01A", "content": [{"type": "text", "text": "..."}]},
      {"type": "tool_result", "tool_use_id": "toolu_01B", "content": [
        {"type": "text", "text": "x: numeric [1:5]"},
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "<b64, no newlines>"}}]}]}
  ]
}
```
Notes: `fallbacks: "default"` + `server-side-fallback-2026-07-01` is the skill's recommended default for
Opus 5.5/Fable 5.1/Sonnet 5.5 on the Claude API (array form uses `server-side-fallback-2026-06-01`;
mixing forms/headers is a 400; not available on Bedrock/Vertex/Foundry or Batches) [VERIFIED skill
SKILL.md; curl/examples.md 212-246]. A fallback turn adds `fallback` content blocks that must be echoed.

### 3.2 SSE fixture (tool use) - from the streaming docs [VERIFIED]
```
event: message_start
data: {"type":"message_start","message":{"id":"msg_014p7gG3wDgGV9EUtLvnow3U","type":"message","role":"assistant","model":"claude-opus-5","stop_sequence":null,"usage":{"input_tokens":472,"output_tokens":2},"content":[],"stop_reason":null}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Okay"}}
...
event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01T1x1fJ34qAmk2tNTrN7Up6","name":"get_weather","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"location\":"}}
...
event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":89}}

event: message_stop
data: {"type":"message_stop"}
```
Thinking block events: `{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}`,
`{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"..."}}`,
`{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQB..."}}`.
Error event: `event: error` / `data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}`.

### 3.3 Non-streaming response shape
```json
{"id":"msg_...","type":"message","role":"assistant","model":"claude-opus-5-5",
 "content":[{"type":"thinking","thinking":"","signature":"..."},{"type":"text","text":"..."}],
 "stop_reason":"end_turn","stop_sequence":null,"stop_details":null,"container":null,
 "usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,
          "cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},
          "output_tokens":35,"output_tokens_details":{"thinking_tokens":28},
          "service_tier":"standard","inference_geo":"...","server_tool_use":{"web_search_requests":0}}}
```
Total prompt tokens = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

### 3.4 Error response and headers
```json
{"type":"error","error":{"type":"rate_limit_error","message":"...","details":{"error_code":"enforced_spend_limit_reached"}},"request_id":"req_018EeWyXxfu5pfWkrYcMdjWG"}
```
Headers: `request-id`, `retry-after` (s), `anthropic-ratelimit-requests-limit|remaining|reset`,
`anthropic-ratelimit-tokens-*`, `anthropic-ratelimit-input-tokens-*`, `anthropic-ratelimit-output-tokens-*`,
`anthropic-workspace-id`, `anthropic-organization-id`.

### 3.5 Cost formula (per request)
```
cost = ( input_tokens * p_in
       + output_tokens * p_out                      # thinking tokens are output tokens
       + cache_read_input_tokens * p_read
       + ephemeral_5m_input_tokens * 1.25 * p_in
       + ephemeral_1h_input_tokens * 2    * p_in ) / 1e6
       * (1.1 if inference_geo == "us") * (0.5 if batch) ; + 10/1000 per web search
```
(If `usage.cache_creation` is missing, treat all `cache_creation_input_tokens` as 5-minute writes.)

### 3.6 Token counting
`POST /v1/messages/count_tokens` body = Messages body minus `max_tokens`/`stream`; response
`{"input_tokens": 14}`.

### 3.7 Models list
`GET /v1/models?limit=1000` -> `{"data":[{"type":"model","id":"claude-opus-5","display_name":"Claude Opus 5","created_at":"2026-07-24T00:00:00Z","max_input_tokens":...,"max_tokens":...,"capabilities":{...}}],"first_id":...,"has_more":false,"last_id":...}`.

### 3.8 Beta header values relevant to gptr (from the models-list `anthropic-beta` enum, VERIFIED)
`server-side-fallback-2026-07-01` (and `-06-01`), `thinking-binding-controls-2026-08-01`,
`thinking-display-updates-2026-08-18`, `mid-conversation-output-config-2026-07-01`,
`mid-conversation-system-clear-at-2026-08-21`, `mid-conversation-tool-changes-2026-07-01`,
`context-management-2025-06-27`, `compact-2026-01-12`, `compact-2026-09-04`, `cache-diagnosis-2026-04-07`,
`task-budgets-2026-03-13`, `advisor-tool-2026-03-01`, `fast-mode-2026-02-01`, `output-300k-2026-03-24`,
`mcp-client-2025-11-20` (and `mcp-client-2026-09-15`), `inline-tools-2026-09-15`.
`oauth-2025-04-20` (Bearer auth) is NOT in that enum [CORRECTED by verifier]; it comes from the skill
(`shared/anthropic-cli.md`: required on `/v1/messages` with Bearer tokens). An unknown/unenabled beta is a 400
``Unexpected value(s) `<value>` for the `anthropic-beta` header.``

### 3.9 Claude Code: recommended launch argv (as used in the verified call 2)
```
claude -p --output-format stream-json --verbose --input-format stream-json --include-partial-messages
       --model <id> --tools "" --mcp-config <tmpfile.json>
       --strict-mcp-config --setting-sources "" --disable-slash-commands
       --session-id <uuid> --permission-prompt-tool stdio
       [--system-prompt-file <gptr_system.md>] [--effort <level>] [--max-turns <n>]
```
`<tmpfile.json>`: `{"mcpServers":{"gptr":{"type":"sdk","name":"gptr"}}}`.

### 3.10 Claude Code control protocol messages (verbatim shapes used/observed)
```json
{"type":"control_request","request_id":"req_1_9f3a1c2b","request":{"subtype":"initialize","hooks":null}}
{"type":"control_request","request_id":"<cli id>","request":{"subtype":"mcp_message","server_name":"gptr","message":{"jsonrpc":"2.0","id":0,"method":"initialize","params":{...}}}}
{"type":"control_response","response":{"subtype":"success","request_id":"<cli id>","response":{"mcp_response":{"jsonrpc":"2.0","id":0,"result":{...}}}}}
{"type":"control_request","request_id":"<cli id>","request":{"subtype":"can_use_tool","tool_name":"mcp__gptr__r_eval","display_name":"R Eval","input":{"code":"answer <- mean(big_vector) * 2; answer"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"mcp__gptr__r_eval"}],"behavior":"allow","destination":"localSettings"}],"tool_use_id":"<id>"}}
{"type":"control_response","response":{"subtype":"success","request_id":"<cli id>","response":{"behavior":"allow","updatedInput":{"code":"..."}}}}
{"type":"control_response","response":{"subtype":"success","request_id":"<cli id>","response":{"behavior":"deny","message":"User declined"}}}
{"type":"control_request","request_id":"req_2_...","request":{"subtype":"interrupt"}}
{"type":"control_request","request_id":"req_3_...","request":{"subtype":"set_model","model":"claude-opus-5-5"}}
{"type":"control_request","request_id":"req_4_...","request":{"subtype":"set_permission_mode","mode":"acceptEdits"}}
{"type":"control_request","request_id":"req_5_...","request":{"subtype":"get_context_usage"}}
{"type":"control_request","request_id":"req_6_...","request":{"subtype":"mcp_status"}}
```
`mcp_status` answer observed: `{"mcpServers":[{"name":"gptr","status":"connected","serverInfo":{"name":"gptr","version":"0.0.1"},"scope":"dynamic","tools":[{"name":"r_eval","annotations":{}},{"name":"r_plot","annotations":{}}]}]}`.
JSON-RPC notifications (no `id`) get an ack `{"jsonrpc":"2.0","result":{}}` inside `mcp_response`
(`query.py:670-673`).

### 3.11 MCP tool result -> Claude content
`{"content":[{"type":"text","text":"[1] 24"}],"isError":false}` became
`{"type":"tool_result","tool_use_id":...,"content":[{"type":"text","text":"[1] 24"}]}` in the transcript
(observed). Image block: `{"type":"image","data":"<b64>","mimeType":"image/png"}` (PNG/JPEG/GIF/WebP
reach Claude as vision input; CLI 2.1.283+ also saves the original bytes in the session's `tool-results`
directory under `~/.claude/projects/`, except with `--no-session-persistence` [VERIFIED mcp.md]).
Text results over `MAX_MCP_OUTPUT_TOKENS` (default 25,000 tokens; warning at 10,000) are written to a file
and replaced by its path [VERIFIED raw mcp.md + env-vars.md]; per-tool `_meta: {"anthropic/maxResultSizeChars": N}`
raises it for text (hard ceiling 500,000 chars; image results stay under the token limit).

### 3.12 Claude Code user message (stdin)
```json
{"type":"user","message":{"role":"user","content":"Use the r_eval tool to run exactly this R code: ..."},"parent_tool_use_id":null,"session_id":""}
```
(The Python SDK sends `"session_id":"default"` (`src/claude_agent_sdk/client.py:252` at f2204bb); `""`
worked in the live calls.)

### 3.13 Zero-cost probe outputs (no user message sent)
```
initialize answered after 2.3s; top-level keys: commands, agents, output_style, available_output_styles, models, account, pid, current_permission_mode, analytics_disabled, remote_control_auto_enable, remote_control_available, remote_control_auto_on_by_default, ide_rc_auto_enable_gate, fast_mode_state, fast_mode_disabled_reason, session_state
  [log] CLI control_request:  mcp_message  server=gptr  method=initialize
  [log] CLI control_request:  mcp_message  server=gptr  method=notifications/initialized
  [log] CLI control_request:  mcp_message  server=gptr  method=tools/list
mcp_status: {"mcpServers":[{"name":"gptr","status":"connected",...,"tools":[{"name":"r_eval",...},{"name":"r_plot",...}]}]}
exit status after close(): 0

                value                  resolved                    effort  fast
              default         claude-opus-5[1m] low/medium/high/xhigh/max  TRUE
             opus[1m]         claude-opus-5[1m] low/medium/high/xhigh/max  TRUE
 claude-fable-5-1[1m]          claude-fable-5-1 low/medium/high/xhigh/max FALSE
               sonnet           claude-sonnet-5 low/medium/high/xhigh/max FALSE
                haiku claude-haiku-4-5-20251001                           FALSE

interrupt              -> {"still_queued":[]}
set_permission_mode    -> {"mode":"acceptEdits"}
set_model              -> null
get_context_usage      -> {"categories":[{"name":"System prompt","tokens":6217,...},...],"totalTokens":6225,"maxTokens":200000,...
no_such_subtype        -> "ERROR: control request failed: Unsupported control request subtype: no_such_subtype"

default system prompt            total=3152  [System prompt=3144, Messages=8, Autocompact buffer=33000, Free space=963848]
--system-prompt-file             total=35  [System prompt=27, Messages=8, Autocompact buffer=33000, Free space=966965]
default tools + default prompt   total=18392  [System prompt=3144, System tools=15240, System tools (deferred)=13074, ...]

isolate + default system prompt               [System prompt=3144, Messages=8]
isolate + --system-prompt-file                [System prompt=12, Messages=8]
isolate=FALSE + --system-prompt-file          [System prompt=14, MCP tools=6470, Custom agents=1407, Memory files=4207, Messages=1290]
```
(The last block used a working directory containing a 200-line `CLAUDE.md`; "isolate" = `--strict-mcp-config
--setting-sources "" --disable-slash-commands`.)

### 3.14 Live capture of call 2 (redacted; ids, signatures, paths replaced) - usable as a test fixture
```
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
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" <- mean(big"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"_vector) *"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" 2;"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":" answer"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"}"}},"session_id":"<session_id>","parent_tool_use_id":null,"uuid":"<uuid>"}
{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","id":"<id>","type":"message","role":"assistant","content":[{"type":"tool_use","id":"<id>","name":"mcp__gptr__r_eval","input":{"code":"answer <- mean(big_vector) * 2; answer"},"caller":{"type":"direct"}}],"container":null,"stop_reason":null,"stop_sequence":null,"stop_details":null,"usage":{"input_tokens":10,"cache_creation_input_tokens":7448,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":7448},"output_tokens":3,"service_tier":"standard","inference_geo":"not_available"},"diagnostics":null,"context_management":null},"parent_tool_use_id":null,"session_id":"<session_id>","uuid":"<uuid>","timestamp":"2026-09-30T01:41:51.701Z","request_id":"<request_id>","tool_use_meta":[{"id":"<id>","display_name":"R Eval","server_display_name":"gptr"}]}
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
(Call 3, the resumed session in a new process: `system/init` with `"tools":[]`, `"mcp_servers":[]`, same
`session_id`; one API message thinking + text `"24"`; `result` `subtype:"success"`, `total_cost_usd:
0.0024747`, `cache_read_input_tokens: 6147` - the resumed prefix was a cache hit.)

---------------------------------------------------------------------------------------------------

## 4. Recommended design for gptr

### 4.1 Package choices (Imports vs Suggests)

| Package | Role | Recommendation |
|---|---|---|
| httr2 (>= 1.1.1) | native API requests, `req_perform_connection()`, `resp_stream_sse()`, retries | Imports. [CORRECTED by verifier from httr2 NEWS] `resp_stream_is_complete()` arrived in 1.1.0, but `resp_stream_sse()` only returns `data` as a single string and skips data-less events from 1.1.1; 1.2.2 (the only version tested) also fixes a `close()` error after network failures in `req_perform_connection()` (#817) - consider `>= 1.2.2` |
| jsonlite | JSON (with the UTF-8 marking rule in 6.4) | Imports |
| processx (>= 3.8.0) | Claude Code child process, stdin/stdout pipes, `poll_io`, `kill_tree` | Imports (also needed for Codex/MCP stdio) |
| cli | console rendering | Imports (per D-20) |
| httpuv | HTTP MCP fallback transport | Suggests |
| openssl | random bearer token for the httpuv endpoint (avoid touching the user's RNG) | Suggests (only with httpuv) |
| callr | tests only (mock servers) | Suggests |
| later | not needed for this track (the pump loop is synchronous) | - |

No Node/Python dependency: the Claude Code CLI is an external, user-installed program (like `git`),
detected at runtime; everything else is R.

### 4.2 Native `anthropic` provider

Files: `R/provider-anthropic.R`, `R/anthropic-stream.R`, `R/anthropic-convert.R`, `R/costs.R`.

```r
provider_anthropic <- function(api_key = NULL, auth_token = NULL,
                               base_url = Sys.getenv("ANTHROPIC_BASE_URL", "https://api.anthropic.com"),
                               default_model = "claude-opus-5-5", betas = character(),
                               fallbacks = "default", thinking_display = NULL, max_retries = 3L)
# -> structure(list(...), class = c("gptr_provider_anthropic", "gptr_provider"))
# Credential resolution: api_key arg > ANTHROPIC_API_KEY > auth_token arg > ANTHROPIC_AUTH_TOKEN.
# Refuse values containing "sk-ant-oat" (subscription tokens) with a message pointing to provider "claude-code".

anthropic_build_body(model, system, tools, messages, max_tokens = 64000L, effort = NULL,
                     thinking = list(type = "adaptive", display = "summarized"),
                     cache = TRUE, cache_ttl = NULL, stream = TRUE, fallbacks = "default", extra = list())
anthropic_perform(provider, body, on_event = function(ev) NULL)      # returns an anthropic message (list)
anthropic_accumulator(on_event)   # $handle(list(event=, data=)), $push_parsed(obj), $result()
anthropic_count_tokens(provider, body)                                # -> integer
anthropic_models(provider, refresh = FALSE)                           # GET /v1/models, cached in R_user_dir
anthropic_cost(model, usage, catalog = gptr_model_catalog())          # section 3.5
gptr_to_anthropic(transcript) / anthropic_to_gptr(message)            # lossless for anthropic-origin blocks
```

Algorithm for one agent step (`anthropic_perform`):
1. Build body from the append-only transcript (never mutate stored messages; cache markers are added to
   a copy). Sort tools by name once per session; freeze system text at session start (no timestamps -
   put dynamic context such as "objects in the session" into the newest user message or a mid-conversation
   `role:"system"` message).
2. `req <- request(base_url) |> req_url_path_append("v1","messages") |> req_headers(...) |>
   req_body_raw(json) |> req_error(is_error = \(r) FALSE) |> req_options(tcp_keepalive = 1L)`;
   `resp <- req_perform_connection(req)`.
3. On status >= 400: parse the error body, classify, retry per 2.11 (`retry-after` seconds, else
   `min(8, 0.5*2^(attempt-1))` with jitter; spend-cap 429 = no retry), otherwise signal
   `gptr_error_anthropic_<type>` (fields: status, request_id, body).
4. On 200: loop `resp_stream_sse(resp)` -> `acc$handle()`; `on.exit(close(resp))` so a user interrupt
   closes the connection; an `error` SSE event raises a classed condition; a stream that ends before
   `message_stop` raises "Anthropic stream ended before message_stop".
5. After the message: if `stop_reason %in% c("max_tokens","refusal")` and tool calls are present, do not
   execute tools; `pause_turn` -> resend with the assistant content appended (cap 5); `refusal` -> surface
   `stop_details`; `tool_use` -> validate each input against the tool's schema (types, required), run
   tools, append ONE user message with all `tool_result` blocks (images inside results, no trailing text).
6. Record usage and cost; expose `request-id` and `anthropic-ratelimit-*` headers in the result.

Defaults: model `claude-opus-5-5`; `effort` explicit (`"medium"` for Opus 5.5 unless the user sets
otherwise; expose `effort=`); thinking `adaptive` with `display = "summarized"` in interactive sessions
(so the console can show reasoning) and `"omitted"` in non-interactive runs; `max_tokens` 64000 when
streaming; `eager_input_streaming = TRUE` on client tools; `strict = TRUE` on tools whose schema allows
it; `fallbacks = "default"` + its beta header on the Claude API for the three 5.x models (opt-out
argument, documented billing); automatic top-level `cache_control` + explicit marker on the system block;
5-minute TTL during a running agent loop, optional 1-hour TTL (`cache_ttl = "1h"`) for interactive
sessions where the user pauses longer.

Cross-provider hand-off (REQ-14): keep Anthropic blocks verbatim in the transcript (including `thinking`,
`redacted_thinking`, `server_tool_use`, `fallback` blocks, signatures). When sending to another provider,
drop thinking/signature blocks (other providers cannot use them) and render server-tool results as text.
When switching back to Anthropic, pass everything unchanged; the API drops what it cannot read.
Model switches restart the prompt cache (model-scoped).

### 4.3 `claude-code` provider (Claude plan via the CLI)

Files: `R/provider-claude-code.R`, `R/cc-process.R`, `R/mcp-dispatch.R`, `R/mcp-http.R` (fallback).

```r
provider_claude_code(cli = NULL, model = NULL, effort = NULL,
                     system_prompt = c("gptr", "claude_code", "append"),
                     permission = c("gptr", "accept_edits", "plan", "none"),
                     isolate = TRUE, persist = TRUE, max_turns = NULL, max_budget_usd = NULL)
cc_doctor()                         # CLI found? version >= "2.1.0"? `claude auth status --json`$loggedIn/authMethod only
cc_session_start(provider, registry, envir, resume = NULL, fork = FALSE)   # -> environment, class "gptr_cc_session"
cc_turn(session, content, on_event)          # sends a user message, pumps until `result`, returns gptr_result
cc_interrupt(session)                        # control_request interrupt (also on R Ctrl-C)
cc_set_model(session, model); cc_set_permission_mode(session, mode)
cc_context_usage(session)                    # get_context_usage -> tokens by category
cc_close(session)                            # close stdin -> wait -> interrupt -> kill_tree
```

Process architecture:
- One long-lived child per gptr session (so the pipeline `gptr("a") |> gptr("b")` continues the same
  CLI conversation without re-spawning). Record `session_id` from `system/init`; if the child died or R
  restarted, respawn with `--resume <session_id>` and the same system-prompt file.
- argv exactly as 3.9; write the MCP config and the gptr system prompt to files under `tempdir()`
  (or `tools::R_user_dir("gptr","cache")`), never free text on argv.
- Environment: inherit, but drop variables of an enclosing Claude Code (`CLAUDECODE`, `CLAUDE_CODE_*`
  except `CLAUDE_CODE_OAUTH_TOKEN`/`CLAUDE_CODE_USE_*`/`CLAUDE_CODE_GIT_BASH_PATH`, `CLAUDE_AGENT_SDK_*`,
  `ANTHROPIC_BASE_URL`); warn if `ANTHROPIC_API_KEY` is set because the CLI would then bill the API key,
  not the plan (auth precedence #3 vs #7) - offer `use_api_key = FALSE` to unset it for the child. The
  same applies to `ANTHROPIC_AUTH_TOKEN` (#2), an `apiKeyHelper` in settings (#4), `CLAUDE_CODE_USE_*`
  cloud providers (#1) and an `ANTHROPIC_PROFILE`-selected `ant` profile (#6) [verifier, authentication
  docs precedence list].
- Startup: `initialize` control request (fail fast if the CLI does not answer in 60 s); check
  `mcp_status` shows gptr `connected`; else fall back to the httpuv transport.
- Pump loop: `p$poll_io(50)` -> `p$read_output()` -> split NDJSON -> dispatch: control requests
  (`mcp_message` -> `dispatcher$handle()`; `can_use_tool` -> gptr permission policy; unknown -> error
  response), control responses (by `request_id`), other lines -> event mapper. Also service httpuv
  when that transport is active. Wrap in `withCallingHandlers(interrupt = ...)`: on Ctrl-C send
  `interrupt` and keep pumping until the `result` (`terminal_reason` `aborted_*`); a second Ctrl-C kills
  the child.
- Tools: gptr's registry (`r`, `read`, `write`, `edit`, `grep`, `find`, `ls`, ...) exposed through
  `mcp_dispatcher()` with names `r_eval` etc. -> the model sees `mcp__gptr__r_eval`. Tool descriptions
  and JSON schemas are shared with the native provider. Handlers evaluate in `envir` and return
  `{content, isError}` (images as `{"type":"image","data","mimeType"}`). Mark read-only tools with
  `readOnlyHint` so the CLI may run them in parallel (they are still executed sequentially by R).
- Permissions: `--permission-prompt-tool stdio` routes prompts to R. gptr maps its modes (D-11):
  `auto` -> allow all gptr tools; `manual` -> ask in the console (`readline()` works because R is the
  host and is waiting); `plan` -> deny mutating tools with a message; non-interactive + manual -> deny
  with explanation. Alternatively gate inside the tool handler (works for both transports).
- Event mapping to gptr's normalised events (names follow Pi's AssistantMessageEvent family, as in the
  native provider):

| CLI line | gptr event |
|---|---|
| `system/init` | `session_start` {session_id, model, tools, mcp_servers, cli_version, capabilities} |
| `stream_event` (parent_tool_use_id null) | fed to `anthropic_accumulator()$push_parsed(event)` -> `start`, `text_start/delta/end`, `thinking_start/delta/end`, `toolcall_start/delta/end`, `done` per API message |
| `stream_event` with parent_tool_use_id | subagent activity (ignored unless `--forward-subagent-text`) |
| `assistant` snapshot | authoritative content block for the transcript (full input, signature) |
| `user` with `tool_result` | `tool_result` {tool_use_id, content, is_error} |
| `system/api_retry` | `retry` {attempt, max_retries, delay, status, error} |
| `rate_limit_event` | `plan_usage` {five_hour/seven_day utilisation, resets_at, status} |
| `system/status`, `system/thinking_tokens` | `status` / `thinking_progress` |
| `system/permission_denied` | `permission_denied` |
| `result` | `turn_end` {ok = !is_error, subtype, text = result, stop_reason, num_turns, usage, cost_estimate_usd, model_usage, errors, terminal_reason, structured_output} |

- History: the CLI's `.jsonl` is the machine truth for this provider; gptr keeps its own normalised
  transcript (text, tool calls, tool results, usage) for script-as-history (REQ-24) and for cross-provider
  hand-off. On hand-off from `claude-code` to `anthropic`, send gptr's normalised history (without Claude
  Code's thinking signatures; they are bound to Claude Code's system prompt/tools prefix and account).
- Cost/usage: report `total_cost_usd` as "API-equivalent estimate, drawn from your Claude plan", and show
  `rate_limit_event` utilisation instead of dollars.

### 4.4 Shared MCP core (`mcp_dispatcher`)
One transport-agnostic JSON-RPC handler (initialize / ping / tools/list / tools/call, protocol versions
2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05; errors -32601/-32602/-32700; notifications return NULL)
used by: (1) the Claude Code `sdk` transport, (2) the httpuv Streamable-HTTP endpoint (loopback only,
bearer token, Origin check, POST only, 202 for notifications), (3) later a stdio server mode
(`gptr::mcp_serve()`) for other harnesses (track 06). Code in 5.3.

### 4.5 Plan/policy guard-rails in code
- Never read `~/.claude/.credentials.json`, the Keychain, or `~/.config/anthropic/credentials/`.
- `cc_doctor()` may run `claude auth status --json` and keep only `loggedIn`, `authMethod`,
  `apiProvider`, `subscriptionType` (drop email/org fields immediately).
- The provider is opt-in (`gptr_config(provider = "claude-code")`), prints a one-time notice: "Uses your
  locally installed Claude Code and your own sign-in; usage counts against your Claude plan and is subject
  to Anthropic's terms." No "Claude Code" branding in gptr's UI names. [UNCERTAIN, verifier] The legal
  page forbids the Claude Code name "as part of your own product, feature, or company name"; a provider
  id `"claude-code"` may count as a feature name - consider a neutral id (e.g. `"cc-cli"`/`"claude-cli"`)
  or confirm with Anthropic.

---------------------------------------------------------------------------------------------------

## 5. Verified R prototypes

All scripts were run with `Rscript --vanilla` from the scratch directory; outputs are copied verbatim.
Two scripts from the interrupted attempt were broken and are fixed here: `cc_lib.R` called a
non-existent `processx::conn_read_raw()` (its `cc_run()` had never run; superseded by `cc_proto.R`), and
`proto4_mcp_offline.R` called `req_body_raw(body, ...)` without the request and `resp_body_raw()` on an
empty body.

### 5.1 SSE decoder + Anthropic accumulator (`proto1_lib.R`, used by proto1/3/5 and the CLI reuse test)

```r
suppressPackageStartupMessages(library(jsonlite))
sse_decoder <- function() {                       # raw-chunk SSE decoder (UTF-8 safe)
  buf <- raw(0); ev_name <- NULL; ev_data <- character(0)
  flush_event <- function() {
    if (is.null(ev_name) && length(ev_data) == 0L) return(NULL)
    out <- list(event = ev_name, data = paste(ev_data, collapse = "\n"))
    ev_name <<- NULL; ev_data <<- character(0); out
  }
  handle_line <- function(line) {
    if (identical(line, "")) return(flush_event())
    if (startsWith(line, ":")) return(NULL)
    pos <- regexpr(":", line, fixed = TRUE)
    if (pos == -1L) { field <- line; value <- "" } else {
      field <- substr(line, 1L, pos - 1L); value <- substr(line, pos + 1L, nchar(line))
      if (startsWith(value, " ")) value <- substr(value, 2L, nchar(value))
    }
    if (field == "event") ev_name <<- value else if (field == "data") ev_data <<- c(ev_data, value)
    NULL
  }
  feed <- function(chunk) {
    buf <<- c(buf, chunk); events <- list()
    repeat {
      nl <- which(buf == as.raw(0x0a) | buf == as.raw(0x0d)); if (length(nl) == 0L) break
      i <- nl[1L]
      if (buf[i] == as.raw(0x0d) && i == length(buf)) break
      line_raw <- if (i > 1L) buf[seq_len(i - 1L)] else raw(0)
      skip <- if (buf[i] == as.raw(0x0d) && buf[i + 1L] == as.raw(0x0a)) 2L else 1L
      buf <<- if (length(buf) >= i + skip) buf[(i + skip):length(buf)] else raw(0)
      line <- rawToChar(line_raw); Encoding(line) <- "UTF-8"
      ev <- handle_line(line); if (!is.null(ev)) events[[length(events) + 1L]] <- ev
    }
    events
  }
  finish <- function() {
    events <- list()
    if (length(buf) > 0L) { line <- rawToChar(buf[buf != as.raw(0x0d)]); Encoding(line) <- "UTF-8"
      buf <<- raw(0); ev <- handle_line(line); if (!is.null(ev)) events[[1L]] <- ev }
    ev <- flush_event(); if (!is.null(ev)) events[[length(events) + 1L]] <- ev
    events
  }
  list(feed = feed, finish = finish)
}

anthropic_accumulator <- function(on_event = function(ev) NULL) {
  msg <- list(id = NULL, model = NULL, role = "assistant", content = list(),
              stop_reason = NULL, stop_sequence = NULL, stop_details = NULL, usage = list())
  partial_json <- list(); saw_start <- FALSE; saw_stop <- FALSE
  merge_usage <- function(u) for (k in names(u)) if (!is.null(u[[k]])) msg$usage[[k]] <<- u[[k]]
  idx <- function(i) i + 1L
  kind <- function(t) switch(t, text = "text", thinking = "thinking", redacted_thinking = "thinking",
                             tool_use = "toolcall", server_tool_use = "server_toolcall", t)
  handle <- function(ev) {
    name <- ev$event
    if (identical(name, "ping")) return(invisible(NULL))
    if (identical(name, "error")) {
      e <- tryCatch(fromJSON(ev$data, simplifyVector = FALSE), error = function(e) NULL)
      type <- e$error$type %||% "unknown_error"
      stop(structure(class = c(paste0("anthropic_", type), "anthropic_stream_error", "error", "condition"),
                     list(message = paste0(type, ": ", e$error$message %||% ev$data), call = NULL,
                          error_type = type, body = e)))
    }
    d <- tryCatch(fromJSON(ev$data, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d)) return(invisible(NULL))
    switch(d$type %||% "",
      message_start = { saw_start <<- TRUE; msg$id <<- d$message$id; msg$model <<- d$message$model
                        merge_usage(d$message$usage); on_event(list(type = "start", id = msg$id, model = msg$model)) },
      content_block_start = { b <- d$content_block; msg$content[[idx(d$index)]] <<- b
        if (b$type %in% c("tool_use", "server_tool_use")) partial_json[[as.character(d$index)]] <<- ""
        on_event(list(type = paste0(kind(b$type), "_start"), index = d$index, block = b)) },
      content_block_delta = { i <- idx(d$index); dl <- d$delta
        switch(dl$type,
          text_delta = { msg$content[[i]]$text <<- paste0(msg$content[[i]]$text, dl$text)
                         on_event(list(type = "text_delta", index = d$index, delta = dl$text)) },
          thinking_delta = { msg$content[[i]]$thinking <<- paste0(msg$content[[i]]$thinking, dl$thinking)
                             on_event(list(type = "thinking_delta", index = d$index, delta = dl$thinking)) },
          signature_delta = { msg$content[[i]]$signature <<- paste0(msg$content[[i]]$signature, dl$signature) },
          input_json_delta = { k <- as.character(d$index)
                               partial_json[[k]] <<- paste0(partial_json[[k]], dl$partial_json)
                               on_event(list(type = "toolcall_delta", index = d$index, delta = dl$partial_json)) },
          citations_delta = { msg$content[[i]]$citations <<- c(msg$content[[i]]$citations, list(dl$citation)) },
          NULL) },
      content_block_stop = { i <- idx(d$index); b <- msg$content[[i]]
        if (b$type %in% c("tool_use", "server_tool_use")) {
          pj <- partial_json[[as.character(d$index)]]
          parsed <- if (!nzchar(pj)) structure(list(), names = character(0)) else
            tryCatch(fromJSON(pj, simplifyVector = FALSE), error = function(e) e)
          if (inherits(parsed, "error")) { msg$content[[i]]$input_parse_error <<- conditionMessage(parsed)
                                           msg$content[[i]]$input_raw <<- pj }
          else msg$content[[i]]$input <<- parsed
        }
        on_event(list(type = paste0(kind(b$type), "_end"), index = d$index, block = msg$content[[i]])) },
      message_delta = { if (!is.null(d$delta$stop_reason)) msg$stop_reason <<- d$delta$stop_reason
        if (!is.null(d$delta$stop_sequence)) msg$stop_sequence <<- d$delta$stop_sequence
        if (!is.null(d$delta$stop_details)) msg$stop_details <<- d$delta$stop_details
        merge_usage(d$usage) },
      message_stop = { saw_stop <<- TRUE; on_event(list(type = "done", stop_reason = msg$stop_reason)) },
      NULL)
    invisible(NULL)
  }
  result <- function() { if (saw_start && !saw_stop) stop("Anthropic stream ended before message_stop"); msg }
  list(handle = handle, result = result)
}
`%||%` <- function(a, b) if (is.null(a)) b else a
```
(For gptr add `push_parsed <- function(d) handle(list(event = d$type, data = jsonlite::toJSON(d,
auto_unbox = TRUE, null = "null")))` - or better, refactor `handle` to take the parsed object directly.)

`proto1_anthropic_sse.R` feeds a CRLF fixture (thinking + multibyte text + 2 tool_use blocks + ping +
comment + unknown event) whole, byte-by-byte and in random chunks. Output:
```
identical(whole, byte-by-byte): TRUE
identical(whole, random chunks): TRUE
normalised events: start thinking_start thinking_delta thinking_end text_start text_delta text_end toolcall_start toolcall_delta toolcall_delta toolcall_delta toolcall_end toolcall_start toolcall_end done
stop_reason: tool_use
usage: {"input_tokens":472,"cache_creation_input_tokens":0,"cache_read_input_tokens":300,"output_tokens":89}
block types: thinking, text, tool_use, tool_use
thinking bytes ok: TRUE | signature: EqQBCgIYAhIM
text bytes: 4f 6b 61 79 20 e2 80 94 20 63 61 66 c3 a9 20 f0 9f 98 80 | Encoding: UTF-8 | nchar: 13
tool 1 input: {"code":"mean(x)"}
tool 2 input (no args) serialises as: {}
caught: anthropic_overloaded_error - overloaded_error: Overloaded
caught: Anthropic stream ended before message_stop
```

### 5.2 Request builder, jsonlite pitfalls, cache markers, cost, retry (`proto2_request_builder.R`)

Key helpers (full script in scratch; the parts an implementer needs):
```r
to_json <- function(x) toJSON(x, auto_unbox = TRUE, null = "null", digits = NA, pretty = FALSE)
blk_text  <- function(text) list(type = "text", text = text)
blk_image <- function(path_or_raw, media_type = NULL) {
  raw <- if (is.raw(path_or_raw)) path_or_raw else readBin(path_or_raw, "raw", file.size(path_or_raw))
  if (is.null(media_type)) media_type <-
    if (identical(raw[1:4], as.raw(c(0x89, 0x50, 0x4e, 0x47)))) "image/png"
    else if (identical(raw[1:3], as.raw(c(0xff, 0xd8, 0xff)))) "image/jpeg"
    else if (identical(rawToChar(raw[1:4]), "GIF8")) "image/gif"
    else if (identical(rawToChar(raw[9:12]), "WEBP")) "image/webp" else stop("unsupported image type")
  list(type = "image", source = list(type = "base64", media_type = media_type,
                                     data = gsub("\n", "", jsonlite::base64_enc(raw), fixed = TRUE)))
}
blk_tool_result <- function(tool_use_id, content, is_error = FALSE) {
  if (is.character(content)) content <- list(blk_text(paste(content, collapse = "\n")))
  out <- list(type = "tool_result", tool_use_id = tool_use_id, content = content)
  if (isTRUE(is_error)) out$is_error <- TRUE
  out
}
tool_def <- function(name, description, properties, required = character(0), strict = FALSE, eager = TRUE) {
  schema <- list(type = "object", properties = properties, required = I(required))
  if (strict) schema$additionalProperties <- FALSE
  out <- list(name = name, description = description)
  if (eager) out$eager_input_streaming <- TRUE
  if (strict) out$strict <- TRUE
  out$input_schema <- schema
  out
}
with_cache_breakpoints <- function(system, messages, ttl = NULL) {   # copy-on-build, never stored
  cc <- c(list(type = "ephemeral"), if (!is.null(ttl)) list(ttl = ttl))
  if (length(system) > 0L) system[[length(system)]]$cache_control <- cc
  n <- length(messages)
  if (n > 0L && messages[[n]]$role == "user") {
    content <- messages[[n]]$content
    if (is.character(content)) content <- list(blk_text(content))
    k <- length(content)
    if (content[[k]]$type %in% c("text", "image", "document", "tool_result")) content[[k]]$cache_control <- cc
    messages[[n]]$content <- content
  }
  list(system = system, messages = messages)
}
retry_delay <- function(status, headers, attempt, base = 0.5, cap = 8) {
  ra <- suppressWarnings(as.numeric(headers[["retry-after"]]))
  if (length(ra) == 1 && !is.na(ra)) return(ra)
  min(cap, base * 2^(attempt - 1)) * (1 - 0.25 * stats::runif(1))    # gptr: jitter without touching .Random.seed (see 6.5)
}
is_retryable <- function(status, body = NULL) {
  if (identical(body$error$details$error_code, "enforced_spend_limit_reached")) return(FALSE)
  status %in% c(408L, 409L, 429L) || status >= 500L
}
```
Output (verbatim, request JSON abbreviated to the checks):
```
P1 length-1 character vector with auto_unbox:      {"required":"code"}
P1 fix with I():                                   {"required":["code"]}
P2 empty list():                                   {"input":[]}
P2 fix, empty NAMED list:                          {"input":{}}
P3 NULL member, default:                           {"stop_sequence":{}}
P3 NULL member, null='null':                       {"stop_sequence":null}
P4 double 100000, default digits:                  {"max_tokens":100000}
P4 double 1e15, digits = NA:                       {"n":1e+15}
P5 NA logical:                                     {"is_error":null}
P6 round trip of {} through fromJSON(simplifyVector=FALSE):  {"input":{}}
P6 round trip of [] through fromJSON(simplifyVector=FALSE):  {"content":[]}
P7 round trip of nested numbers keeps integers:    {"a":1,"b":1.5,"c":[1,2],"d":true,"e":null}
...
cache_control markers in request: 2 (max allowed 4)
messages of request 1 are a byte prefix of request 2: TRUE
tools+system identical between requests: TRUE
body size (bytes): 1578
cost(opus-5-5, {"input_tokens":50,"output_tokens":1200,"cache_read_input_tokens":200000,"cache_creation_input_tokens":3000}) = $0.079200
context tokens in prompt = 203050
retry 429 with retry-after: 7 -> 7 s
retry 529 no header, attempts 1..5 -> 0.47, 0.91, 1.71, 3.09, 7.6 s
retryable: 400 FALSE | 429 TRUE | 529 TRUE | 429 spend cap FALSE
```
Assertions that passed: `max_tokens` integer, tools sorted, `"properties":{}`, `"required":[]`,
`"required":["code"]`, no-arg `tool_use` replayed as `"input":{}`, thinking signature and empty thinking
text replayed unchanged, stored transcript untouched by cache markers. Lesson: use `$` never for usage
fields (`usage$cache_creation` partially matches `cache_creation_input_tokens`); always `[[`.
The price table used (all verified against the pricing page): opus-5-5 4/20/0.20/5/8, fable-5-1
10/50/0.25/12.50/20, sonnet-5-5 2/10/0.20/2.50/4, haiku-4-5 1/5/0.10/1.25/2 (input/output/read/5m/1h).

### 5.3 Streaming HTTP call with retries against a local mock (`proto3_http_stream.R`)
Core function (uses 5.1):
```r
anthropic_stream <- function(body, api_key, base_url, on_event = function(ev) NULL,
                             max_retries = 3L, betas = character(0)) {
  attempt <- 0L
  repeat {
    attempt <- attempt + 1L
    req <- request(base_url) |> req_url_path_append("v1", "messages") |>
      req_headers(`x-api-key` = api_key, `anthropic-version` = "2023-06-01",
                  `content-type` = "application/json", accept = "text/event-stream", .redact = "x-api-key") |>
      req_user_agent("gptr/0.0.0.9000 (R; httr2)") |>
      req_body_raw(toJSON(body, auto_unbox = TRUE, null = "null", digits = NA), type = "application/json") |>
      req_error(is_error = function(resp) FALSE) |> req_options(tcp_keepalive = 1L)
    if (length(betas)) req <- req_headers(req, `anthropic-beta` = paste(betas, collapse = ","))
    resp <- req_perform_connection(req)
    status <- resp_status(resp)
    if (status >= 400L) {
      err <- tryCatch(resp_body_json(resp), error = function(e) NULL); hdrs <- resp_headers(resp); close(resp)
      retryable <- (status %in% c(408L, 409L, 429L) || status >= 500L) &&
        !identical(err$error$details$error_code, "enforced_spend_limit_reached")
      if (!retryable || attempt > max_retries)
        stop(structure(class = c(paste0("anthropic_", err$error$type %||% "api_error"), "anthropic_error", "error", "condition"),
                       list(message = sprintf("HTTP %d %s: %s", status, err$error$type %||% "", err$error$message %||% ""),
                            call = NULL, status = status, request_id = hdrs[["request-id"]], body = err)))
      ra <- suppressWarnings(as.numeric(hdrs[["retry-after"]]))
      delay <- if (length(ra) == 1L && !is.na(ra)) ra else min(8, 0.5 * 2^(attempt - 1L))
      on_event(list(type = "retry", attempt = attempt, status = status, delay = delay))
      Sys.sleep(delay); next
    }
    dec <- sse_decoder(); acc <- anthropic_accumulator(on_event); ok <- FALSE
    on.exit(if (!ok) try(close(resp), silent = TRUE), add = TRUE)       # also runs on user interrupt
    while (!resp_stream_is_complete(resp)) {
      chunk <- resp_stream_raw(resp, kb = 8)
      if (length(chunk)) for (ev in dec$feed(chunk)) acc$handle(ev)
    }
    for (ev in dec$finish()) acc$handle(ev)
    close(resp); ok <- TRUE
    msg <- acc$result(); msg$request_id <- resp_header(resp, "request-id"); return(msg)
  }
}
```
Mock (callr + base `serverSocket`) answers 529, then 429 with `retry-after: 1`, then a streamed 200 whose
events are split across TCP writes. Output:
```
elapsed: 2.54 s
events: retry(status=529,delay=0.5s) | retry(status=429,delay=1.0s) | start | text_start | text_delta("Hello") | text_delta(" from the mock") | text_end | done
final text: Hello from the mock
stop_reason: end_turn  usage: {"input_tokens":25,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":15}  request_id: req_mock3
mock saw 3 requests
request line: POST /v1/messages HTTP/1.1
headers sent: host=127.0.0.1:18668; user-agent=gptr/0.0.0.9000 (R; httr2); accept-encoding=deflate, gzip; x-api-key=<present>; anthropic-version=2023-06-01; content-type=application/json; accept=text/event-stream; anthropic-beta=context-management-2025-06-27; content-length=107
body sent: {"model":"claude-opus-5-5","max_tokens":64000,"stream":true,"messages":[{"role":"user","content":"Hello"}]}
```

### 5.4 httr2's own SSE reader is sufficient (`proto5_httr2_sse.R`)
```r
resp <- request(sprintf("http://127.0.0.1:%d/v1/messages", port)) |> req_perform_connection()
acc <- anthropic_accumulator(); names_seen <- character(0)
repeat {
  e <- resp_stream_sse(resp)
  if (is.null(e)) { if (resp_stream_is_complete(resp)) break else next }
  names_seen <- c(names_seen, e$type)
  acc$handle(list(event = e$type, data = e$data))
}
close(resp)
```
The mock sends CRLF SSE (a comment line, `ping`, an unknown `future_event`, an em dash and a 4-byte emoji)
in 7-byte TCP writes. Output:
```
event names from resp_stream_sse(): message_start content_block_start ping content_block_delta future_event content_block_stop message_delta message_stop
text bytes: 41 e2 80 94 20 42 20 f0 9f 98 80  Encoding: UTF-8
stop_reason: end_turn  output_tokens: 7
httr2::resp_stream_sse handled CRLF, comments and split multibyte characters correctly
```

### 5.5 Transport-agnostic MCP core (`mcp_core.R`)
```r
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a)) b else a
mcp_json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)
mcp_text <- function(...) list(type = "text", text = paste0(..., collapse = "\n"))
mcp_image <- function(raw, mime = "image/png")
  list(type = "image", data = gsub("\n", "", jsonlite::base64_enc(raw), fixed = TRUE), mimeType = mime)
empty_obj <- function() structure(list(), names = character(0))

# tools: named list; element = list(description, input_schema, handler = function(args), read_only = FALSE)
mcp_dispatcher <- function(tools, name = "gptr", version = "0.0.1",
                           instructions = "Tools run inside the user's live R session.",
                           log = function(...) NULL) {
  supported <- c("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
  calls <- 0L
  ok  <- function(id, result) list(jsonrpc = "2.0", id = id, result = result)
  err <- function(id, code, message) list(jsonrpc = "2.0", id = id, error = list(code = code, message = message))
  handle <- function(msg) {
    method <- msg$method %||% ""
    id <- msg$id
    log(sprintf("<- %s%s", if (nzchar(method)) method else "(response)",
                if (!is.null(msg$params$name)) paste0(" ", msg$params$name) else ""))
    if (is.null(id)) return(NULL)                         # notification / response: no reply
    switch(method,
      initialize = {
        pv <- msg$params$protocolVersion %||% supported[[1]]
        if (!pv %in% supported) pv <- "2025-06-18"
        ok(id, list(protocolVersion = pv, capabilities = list(tools = list(listChanged = FALSE)),
                    serverInfo = list(name = name, version = version), instructions = instructions))
      },
      ping = ok(id, empty_obj()),
      `tools/list` = ok(id, list(tools = unname(lapply(names(tools), function(n) {
        t <- tools[[n]]
        list(name = n, description = t$description, inputSchema = t$input_schema,
             annotations = list(readOnlyHint = isTRUE(t$read_only)))
      })))),
      `tools/call` = {
        tn <- msg$params$name; t <- tools[[tn]]
        if (is.null(t)) return(err(id, -32602, paste0("Unknown tool: ", tn)))
        calls <<- calls + 1L
        args <- msg$params$arguments %||% empty_obj()
        res <- tryCatch(t$handler(args),
                        error = function(e) list(content = list(mcp_text("Error: ", conditionMessage(e))), isError = TRUE),
                        interrupt = function(e) list(content = list(mcp_text("Interrupted by the user")), isError = TRUE))
        if (is.character(res)) res <- list(content = list(mcp_text(res)))
        res$isError <- isTRUE(res$isError)
        ok(id, res)
      },
      err(id, -32601, paste0("Method not found: ", method)))
  }
  list(handle = handle, n_calls = function() calls, name = name)
}

gptr_demo_tools <- function(envir) list(
  r_eval = list(
    description = paste("Evaluate R code in the user's live R session and return printed output.",
                        "Objects you create persist in the session. Call this whenever you need to compute or inspect data."),
    input_schema = list(type = "object", properties = list(code = list(type = "string", description = "R code to evaluate")),
                        required = I("code"), additionalProperties = FALSE),
    handler = function(args) {
      out <- utils::capture.output({
        res <- withVisible(eval(parse(text = args$code), envir = envir))
        if (res$visible) print(res$value)
      })
      if (!length(out)) out <- "(no output)"
      list(content = list(mcp_text(out)))
    }),
  r_plot = list(
    description = "Evaluate R plotting code in the live session and return the plot as a PNG image.",
    input_schema = list(type = "object", properties = list(code = list(type = "string", description = "R plotting code")),
                        required = I("code"), additionalProperties = FALSE),
    handler = function(args) {
      f <- tempfile(fileext = ".png"); on.exit(unlink(f))
      grDevices::png(f, width = 320, height = 200)
      tryCatch(eval(parse(text = args$code), envir = envir), finally = grDevices::dev.off())
      list(content = list(mcp_text("Plot rendered (320x200 PNG)."), mcp_image(readBin(f, "raw", file.size(f)))))
    })
)
```

### 5.6 HTTP transport over the same dispatcher (`mcp_http.R`, `proto4b_mcp_http.R`)
```r
suppressPackageStartupMessages(library(httpuv)); source("mcp_core.R")
mcp_http_start <- function(dispatcher, host = "127.0.0.1", port = httpuv::randomPort(host = "127.0.0.1"),
                           token = paste(sprintf("%02x", as.integer(openssl::rand_bytes(24))), collapse = "")) {
  app <- list(call = function(req) {
    hdr <- function(n) req[[paste0("HTTP_", toupper(gsub("-", "_", n)))]]
    txt <- function(status, body, extra = list())
      list(status = status, headers = c(list(`Content-Type` = "text/plain"), extra), body = body)
    origin <- hdr("origin")
    if (!is.null(origin) && !grepl("^https?://(127\\.0\\.0\\.1|localhost)(:[0-9]+)?$", origin))
      return(txt(403L, "forbidden origin"))
    if (!identical(hdr("authorization"), paste("Bearer", token)))
      return(txt(401L, "unauthorized", list(`WWW-Authenticate` = "Bearer")))
    if (!identical(req$PATH_INFO, "/mcp")) return(txt(404L, "not found"))
    if (req$REQUEST_METHOD != "POST") return(txt(405L, "method not allowed", list(Allow = "POST")))
    body <- rawToChar(req$rook.input$read()); Encoding(body) <- "UTF-8"
    msg <- tryCatch(jsonlite::fromJSON(body, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(msg))
      return(list(status = 400L, headers = list(`Content-Type` = "application/json"),
                  body = mcp_json(list(jsonrpc = "2.0", id = NULL, error = list(code = -32700, message = "Parse error")))))
    batch <- is.null(names(msg))
    out <- if (batch) Filter(Negate(is.null), lapply(msg, dispatcher$handle)) else dispatcher$handle(msg)
    if (is.null(out) || (batch && !length(out))) return(txt(202L, ""))
    list(status = 200L, headers = list(`Content-Type` = "application/json"), body = mcp_json(out))
  })
  srv <- httpuv::startServer(host, port, app)
  url <- sprintf("http://%s:%d/mcp", host, port)
  list(url = url, token = token, stop = function() httpuv::stopServer(srv),
       service = function(ms = 1) httpuv::service(ms),
       config = function(name = dispatcher$name)
         list(mcpServers = setNames(list(list(type = "http", url = url,
                                              headers = list(Authorization = paste("Bearer", token)),
                                              alwaysLoad = TRUE)), name)))
}
```
The test starts the endpoint, runs an httr2 JSON-RPC client in a `callr::r_bg()` process, and pumps
`srv$service(20)` while the client is alive. Output:
```
config: {"mcpServers":{"gptr":{"type":"http","url":"http://127.0.0.1:34379/mcp","headers":{"Authorization":"Bearer <token>"},"alwaysLoad":true}}}
  [mcp] <- initialize
  [mcp] <- notifications/initialized
  [mcp] <- tools/call r_eval
  [mcp] <- tools/call r_eval
init    HTTP 200 {"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":false}},"serverInfo":{"name":"gptr","version":"0.0.1"},"
inited  HTTP 202
call    HTTP 200 {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"[1] 24"}],"isError":false}}
err     HTTP 200 {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Error: boom"}],"isError":true}}
bad     HTTP 401 unauthorized
live$answer = 24
```
(The fixed older `proto4_mcp_offline.R` additionally showed an image result of 7306 PNG bytes,
`resources/list` -> -32601, and GET -> 405.)
Verifier: re-ran `proto4b` with the code exactly as printed in 5.5/5.6 - identical output. Before using
`config()` with the real CLI, add a per-server `timeout` (ms, > 60000) next to `alwaysLoad`, otherwise
Claude Code aborts HTTP tool calls whose response takes over 60 s (2.15 B).

### 5.7 Claude Code driver with the control protocol (`cc_proto.R`) - verified live

```r
suppressPackageStartupMessages({ library(processx); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
to_json1 <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)

cc_find_cli <- function() {
  opt <- getOption("gptr.claude_path", Sys.getenv("GPTR_CLAUDE_PATH", ""))
  if (nzchar(opt) && file.exists(opt)) return(normalizePath(opt))
  win <- .Platform$OS.type == "windows"
  p <- Sys.which(if (win) "claude.exe" else "claude")
  if (nzchar(p)) return(unname(p))
  home <- path.expand("~")
  cand <- if (win) file.path(Sys.getenv("USERPROFILE", home), ".local", "bin", "claude.exe")
          else c(file.path(home, ".local", "bin", "claude"), "/usr/local/bin/claude",
                 "/opt/homebrew/bin/claude", file.path(home, ".claude", "local", "claude"),
                 file.path(home, ".npm-global", "bin", "claude"))
  hit <- cand[file.exists(cand)]
  if (length(hit)) return(hit[[1]])
  stop("Claude Code CLI not found. Install it (https://code.claude.com/docs/en/setup), run `claude` once ",
       "to sign in, or set options(gptr.claude_path=).", call. = FALSE)
}

cc_child_env <- function(extra = character(0)) {
  env <- Sys.getenv(); env <- setNames(as.character(env), names(env))
  drop <- grepl("^(CLAUDECODE$|CLAUDE_CODE_|CLAUDE_AGENT_SDK_|CLAUDE_PID$|CLAUDE_EFFORT$|CLAUDE_PLUGIN_|CLAUDE_PREVIEW_)",
                names(env)) | names(env) %in% "ANTHROPIC_BASE_URL"
  keep <- names(env) %in% c("CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX",
                            "CLAUDE_CODE_USE_FOUNDRY", "CLAUDE_CODE_GIT_BASH_PATH")
  env <- env[!drop | keep]
  env[names(extra)] <- extra
  env
}

cc_args <- function(model = NULL, system_prompt_file = NULL, append_system_prompt_file = NULL,
                    tools = "", allowed_tools = NULL, disallowed_tools = NULL, mcp_config_file = NULL,
                    permission_mode = NULL, resume = NULL, session_id = NULL, fork_session = FALSE,
                    max_turns = NULL, effort = NULL, persist = TRUE, partial = TRUE, isolate = TRUE,
                    add_dir = NULL, extra = character(0)) {
  a <- c("-p", "--output-format", "stream-json", "--verbose", "--input-format", "stream-json")
  if (partial) a <- c(a, "--include-partial-messages")
  if (!is.null(model)) a <- c(a, "--model", model)
  if (!is.null(system_prompt_file)) a <- c(a, "--system-prompt-file", system_prompt_file)
  if (!is.null(append_system_prompt_file)) a <- c(a, "--append-system-prompt-file", append_system_prompt_file)
  if (!is.null(tools)) a <- c(a, "--tools", paste(tools, collapse = ","))
  if (length(allowed_tools)) a <- c(a, "--allowedTools", paste(allowed_tools, collapse = ","))
  if (length(disallowed_tools)) a <- c(a, "--disallowedTools", paste(disallowed_tools, collapse = ","))
  if (!is.null(mcp_config_file)) a <- c(a, "--mcp-config", mcp_config_file)
  if (isolate) a <- c(a, "--strict-mcp-config", "--setting-sources", "", "--disable-slash-commands")
  if (!is.null(permission_mode)) a <- c(a, "--permission-mode", permission_mode)
  if (!is.null(resume)) a <- c(a, "--resume", resume)
  if (!is.null(session_id)) a <- c(a, "--session-id", session_id)
  if (fork_session) a <- c(a, "--fork-session")
  if (!is.null(max_turns)) a <- c(a, "--max-turns", as.character(max_turns))
  if (!is.null(effort)) a <- c(a, "--effort", effort)
  if (!persist) a <- c(a, "--no-session-persistence")
  for (d in add_dir) a <- c(a, "--add-dir", d)
  c(a, extra)
}

ndjson_splitter <- function() {           # character-level; processx never splits a UTF-8 character
  buf <- ""
  function(chunk = "", flush = FALSE) {
    if (length(chunk) && nzchar(chunk)) buf <<- paste0(buf, chunk)
    if (!grepl("\n", buf, fixed = TRUE) && !flush) return(character(0))
    parts <- strsplit(buf, "\n", fixed = TRUE)[[1]]
    complete <- endsWith(buf, "\n") || flush
    if (!complete) { buf <<- parts[length(parts)]; parts <- parts[-length(parts)] } else buf <<- ""
    parts <- sub("\r$", "", parts)
    out <- parts[nzchar(parts)]
    Encoding(out) <- "UTF-8"
    out
  }
}

uuid4 <- function() {
  b <- as.integer(openssl::rand_bytes(16))
  b[7] <- bitwOr(bitwAnd(b[7], 0x0f), 0x40); b[9] <- bitwOr(bitwAnd(b[9], 0x3f), 0x80)
  h <- sprintf("%02x", b)
  paste0(paste(h[1:4], collapse = ""), "-", paste(h[5:6], collapse = ""), "-", paste(h[7:8], collapse = ""), "-",
         paste(h[9:10], collapse = ""), "-", paste(h[11:16], collapse = ""))
}

cc_session <- function(args, cli = cc_find_cli(), wd = getwd(), env = cc_child_env(),
                       mcp_servers = list(), can_use_tool = NULL,
                       on_event = function(ev) NULL, log = function(...) NULL) {
  p <- processx::process$new(cli, args = args, stdin = "|", stdout = "|", stderr = "|", wd = wd, env = env,
                             cleanup = TRUE, cleanup_tree = TRUE, windows_hide_window = TRUE,
                             encoding = "UTF-8")
  split <- ndjson_splitter(); stderr_buf <- character(0)
  responses <- list(); counter <- 0L; results <- list(); lines <- character(0)
  self <- environment()
  write_line <- function(x) {
    rest <- p$write_input(paste0(to_json1(x), "\n"))
    t0 <- Sys.time()
    while (length(rest)) {
      if (as.numeric(Sys.time() - t0, units = "secs") > 30) stop("stdin write timed out")
      Sys.sleep(0.01); rest <- p$write_input(rest)
    }
    invisible(NULL)
  }
  answer <- function(request_id, response = NULL, error = NULL)
    write_line(list(type = "control_response",
                    response = if (is.null(error)) list(subtype = "success", request_id = request_id, response = response)
                               else list(subtype = "error", request_id = request_id, error = error)))
  handle_control_request <- function(msg) {
    req <- msg$request; st <- req$subtype %||% ""
    log("CLI control_request: ", st, if (!is.null(req$server_name)) paste0(" server=", req$server_name),
        if (!is.null(req$message$method)) paste0(" method=", req$message$method))
    if (st == "mcp_message") {
      srv <- mcp_servers[[req$server_name %||% ""]]
      resp <- if (is.null(srv)) list(jsonrpc = "2.0", id = req$message$id,
                                     error = list(code = -32601, message = "Server not found"))
              else srv$handle(req$message)
      if (is.null(resp)) resp <- list(jsonrpc = "2.0", result = structure(list(), names = character(0)))
      answer(msg$request_id, list(mcp_response = resp))
    } else if (st == "can_use_tool") {
      dec <- if (is.null(can_use_tool)) list(behavior = "deny", message = "No approval handler in gptr")
             else can_use_tool(req$tool_name, req$input, req)
      if (identical(dec$behavior, "allow") && is.null(dec$updatedInput)) dec$updatedInput <- req$input
      answer(msg$request_id, dec)
    } else {
      answer(msg$request_id, error = paste("Unsupported control request subtype:", st))
    }
  }
  handle_line <- function(ln) {
    msg <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(msg)) { log("unparsed: ", substr(ln, 1, 200)); return() }
    lines <<- c(lines, ln)
    t <- msg$type %||% ""
    if (t == "control_request") handle_control_request(msg)
    else if (t == "control_response") responses[[msg$response$request_id]] <<- msg$response
    else if (t == "control_cancel_request") log("control_cancel_request ", msg$request_id)
    else {
      if (t == "result") results[[length(results) + 1L]] <<- msg
      on_event(msg)
    }
  }
  pump <- function(until = function() FALSE, timeout = 60, service = function() NULL) {
    deadline <- Sys.time() + timeout
    repeat {
      if (until()) return(TRUE)
      pr <- p$poll_io(50)
      if (pr[["output"]] == "ready") for (ln in split(p$read_output(-1))) handle_line(ln)
      if (pr[["error"]] == "ready") stderr_buf <<- c(stderr_buf, p$read_error())
      service()
      if (!p$is_alive() && pr[["output"]] != "ready") {
        rest <- tryCatch(p$read_all_output(), error = function(e) "")
        for (ln in split(rest, flush = TRUE)) handle_line(ln)
        stderr_buf <<- c(stderr_buf, tryCatch(p$read_all_error(), error = function(e) ""))
        return(until())
      }
      if (Sys.time() > deadline) return(FALSE)
    }
  }
  control <- function(request, timeout = 60) {
    counter <<- counter + 1L
    id <- sprintf("req_%d_%s", counter, paste(sprintf("%02x", as.integer(openssl::rand_bytes(4))), collapse = ""))
    write_line(list(type = "control_request", request_id = id, request = request))
    if (!pump(function() !is.null(responses[[id]]), timeout)) stop("control request timed out: ", request$subtype)
    r <- responses[[id]]
    if (identical(r$subtype, "error")) stop("control request failed: ", r$error)
    r$response
  }
  send_user <- function(content, session_id = "")
    write_line(list(type = "user", message = list(role = "user", content = content),
                    parent_tool_use_id = NULL, session_id = session_id))
  turn <- function(content, timeout = 300, service = function() NULL) {
    n0 <- length(results); send_user(content)
    if (!pump(function() length(results) > n0, timeout, service)) stop("turn timed out")
    results[[length(results)]]
  }
  close <- function(grace_ms = 3000) {
    try(base::close(p$get_input_connection()), silent = TRUE)   # EOF on stdin -> CLI exits
    pump(function() FALSE, timeout = grace_ms / 1000)
    if (p$is_alive()) { try(p$interrupt(), silent = TRUE); p$wait(1000) }
    if (p$is_alive()) p$kill_tree()
    invisible(p$get_exit_status())
  }
  self
}

cc_redact <- function(x) {    # ids, signatures, emails, paths -> placeholders before logging
  if (is.list(x)) {
    nm <- names(x)
    for (i in seq_along(x)) {
      key <- if (is.null(nm)) "" else nm[i]; v <- x[[i]]
      if (is.character(v) && length(v) == 1L) {
        if (key %in% c("session_id", "uuid", "id", "request_id", "requestId", "message_id", "signature",
                       "user_message_uuid", "account_uuid", "organization_uuid", "email", "emailAddress",
                       "organization", "organizationName", "orgName", "orgId", "accountUuid", "organizationUuid",
                       "tool_use_id", "parent_tool_use_id", "prompt_id", "promptId"))
          x[[i]] <- paste0("<", key, ">")
        else if (key %in% c("cwd", "output_file", "path", "transcript_path", "configDirectory")) x[[i]] <- paste0("<", key, ">")
        else x[[i]] <- gsub("/(Users|home|private)/[^\"' ]+", "<path>", v)
      } else if (is.list(v)) x[i] <- list(cc_redact(v))   # x[[i]] <- NULL would delete the element
    }
  }
  x
}
```

Live call 2 (`real_calls.R 2`):
```r
source("cc_proto.R"); source("mcp_core.R")
live <- new.env(); live$big_vector <- c(2, 4, 6, 8, 40)
srv <- mcp_dispatcher(gptr_demo_tools(live), log = function(...) cat("  [mcp]", ..., "\n"))
cfg <- tempfile(fileext = ".json")
writeLines(to_json1(list(mcpServers = list(gptr = list(type = "sdk", name = "gptr")))), cfg)
sid <- uuid4()
approve <- function(tool_name, input, req) {        # gptr's permission gate (REQ-37)
  cat("  [approve?]", tool_name, to_json1(input), "-> allow\n")
  list(behavior = "allow", updatedInput = input)
}
args <- cc_args(model = "haiku", tools = "", mcp_config_file = cfg, session_id = sid,
                extra = c("--permission-prompt-tool", "stdio"))
s <- cc_session(args, wd = "ccwd", mcp_servers = list(gptr = srv), can_use_tool = approve,
                on_event = rec$on_event, log = function(...) cat("  [log]", ..., "\n"))
init <- s$control(list(subtype = "initialize", hooks = NULL), timeout = 60)
r <- s$turn(paste("Use the r_eval tool to run exactly this R code: answer <- mean(big_vector) * 2; answer",
                  "Then reply with only the resulting number."), timeout = 240)
```
Output (events summarised by the recorder):
```
  [log] CLI control_request:  mcp_message  server=gptr  method=initialize
  [mcp] <- initialize
  [log] CLI control_request:  mcp_message  server=gptr  method=notifications/initialized
  [mcp] <- notifications/initialized
  [log] CLI control_request:  mcp_message  server=gptr  method=tools/list
  [mcp] <- tools/list
   system/init
   system/status
   rate_limit_event/
   stream_event/message_start
   stream_event/content_block_start:thinking
   system/thinking_tokens
   stream_event/content_block_delta:thinking_delta
   stream_event/content_block_delta:thinking_delta
   system/thinking_tokens
   stream_event/content_block_delta:signature_delta
   assistant [thinking]
   stream_event/content_block_stop
   stream_event/content_block_start:tool_use
   stream_event/content_block_delta:input_json_delta   (x7)
   assistant [tool_use]
  [log] CLI control_request:  can_use_tool
  [approve?] mcp__gptr__r_eval {"code":"answer <- mean(big_vector) * 2; answer"} -> allow
   stream_event/content_block_stop
   stream_event/message_delta
   stream_event/message_stop
  [log] CLI control_request:  mcp_message  server=gptr  method=tools/call
  [mcp] <- tools/call r_eval
   user [tool_result]
   system/status
   stream_event/message_start
   stream_event/content_block_start:thinking
   stream_event/content_block_delta:thinking_delta
   stream_event/content_block_delta:signature_delta
   assistant [thinking]
   stream_event/content_block_stop
   stream_event/content_block_start:text
   stream_event/content_block_delta:text_delta "24"
   assistant [text]
   stream_event/content_block_stop
   stream_event/message_delta
   stream_event/message_stop
   result/success
RESULT: success | result: "24" | num_turns: 2 | cost_usd: 0.0178928 | exit: 0
tool calls served by R: 1 | live$answer = 24
can_use_tool request (redacted): {"subtype":"can_use_tool","tool_name":"mcp__gptr__r_eval","display_name":"R Eval","input":{"code":"answer <- mean(big_vector) * 2; answer"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"mcp__gptr__r_eval"}],"behavior":"allow","destination":"localSettings"}],"tool_use_id":"<tool_use_id>"}
```
Live call 3 (`s <- cc_session(cc_args(model = "haiku", tools = "", resume = sid), wd = "ccwd")`;
`s$turn("What number did the tool return a moment ago? Reply with the number only.")`):
```
   system/init
   system/status
   stream_event/message_start
   ... thinking block ...
   stream_event/content_block_delta:text_delta "24"
   assistant [text]
   ...
   rate_limit_event/
   result/success
RESULT: success | result: "24" | same session id: TRUE | exit: 0
```

### 5.8 The CLI stream reuses the native accumulator (`reuse_accumulator.R`)
```r
source("proto1_lib.R")
L <- lapply(readLines("fixtures/call2.ndjson"), jsonlite::fromJSON, simplifyVector = FALSE)
msgs <- list(); acc <- NULL; norm <- character(0)
for (x in L) {
  if (!identical(x$type, "stream_event") || !is.null(x$parent_tool_use_id)) next
  e <- x$event
  if (identical(e$type, "message_start")) acc <- anthropic_accumulator(function(ev) norm <<- c(norm, ev$type))
  acc$handle(list(event = e$type, data = jsonlite::toJSON(e, auto_unbox = TRUE, null = "null")))
  if (identical(e$type, "message_stop")) msgs[[length(msgs) + 1L]] <- acc$result()
}
```
Output:
```
API messages rebuilt: 2
  stop_reason=tool_use blocks=thinking,tool_use    usage(out)=137
  stop_reason=end_turn blocks=thinking,text        usage(out)=35
tool_use: mcp__gptr__r_eval {"code":"answer <- mean(big_vector) * 2; answer"}
final text: 24
normalised events: start thinking_start thinking_delta thinking_delta thinking_end toolcall_start toolcall_delta toolcall_delta toolcall_delta toolcall_delta toolcall_delta toolcall_delta toolcall_delta toolcall_end done start thinking_start thinking_delta thinking_end text_start text_delta text_end done
assistant snapshots: 4 blocks: thinking,tool_use,thinking,text
```

### 5.9 Offline fake CLI for gptr's test suite (`fake_cli.R` + `test_fake.R`)
(Verifier: re-run with the code exactly as printed here - passes on R 4.4.3. It uses base R's `%||%`,
which exists only from R 4.4.0; add `` `%||%` <- function(a, b) if (is.null(a)) b else a `` for older R.
`ask()` loops forever if stdin hits EOF while waiting - acceptable for a test fixture only.)
A ~40-line R script that speaks the same protocol (initialize handshake that calls back into the host's
sdk MCP server, `can_use_tool`, `tools/call`, stream events, `result`). It lets CRAN-safe tests exercise
the whole driver with `cli = file.path(R.home("bin"), "Rscript")`, `args = c("--vanilla", "fake_cli.R")`.
```r
suppressPackageStartupMessages(library(jsonlite))
out <- function(x) { cat(toJSON(x, auto_unbox = TRUE, null = "null"), "\n", sep = ""); flush(stdout()) }
inp <- file("stdin", open = "r")
next_msg <- function() { ln <- readLines(inp, n = 1L); if (!length(ln)) NULL else fromJSON(ln, simplifyVector = FALSE) }
sid <- "00000000-0000-4000-8000-000000000000"; n <- 0L
ask <- function(request) {
  n <<- n + 1L; id <- paste0("cli_req_", n)
  out(list(type = "control_request", request_id = id, request = request))
  repeat { m <- next_msg(); if (identical(m$type, "control_response") && identical(m$response$request_id, id)) return(m$response) }
}
ev <- function(e) out(list(type = "stream_event", event = e, session_id = sid, parent_tool_use_id = NULL, uuid = "u"))
repeat {
  m <- next_msg(); if (is.null(m)) break
  if (identical(m$type, "control_request")) {
    st <- m$request$subtype
    resp <- if (st == "initialize") {
      ask(list(subtype = "mcp_message", server_name = "gptr",
               message = list(jsonrpc = "2.0", id = 0, method = "initialize", params = list(protocolVersion = "2025-06-18"))))
      list(commands = list(), models = list(list(value = "haiku")))
    } else list()
    out(list(type = "control_response", response = list(subtype = "success", request_id = m$request_id, response = resp)))
    next
  }
  if (identical(m$type, "user")) {
    out(list(type = "system", subtype = "init", session_id = sid, tools = list("mcp__gptr__r_eval"), model = "fake"))
    ev(list(type = "message_start", message = list(id = "msg_1", role = "assistant", content = list(), model = "fake")))
    ev(list(type = "content_block_start", index = 0, content_block = list(type = "tool_use", id = "toolu_1", name = "mcp__gptr__r_eval", input = setNames(list(), character(0)))))
    ev(list(type = "content_block_delta", index = 0, delta = list(type = "input_json_delta", partial_json = "{\"code\":\"answer <- mean(big_vector) * 2; answer\"}")))
    ev(list(type = "content_block_stop", index = 0))
    perm <- ask(list(subtype = "can_use_tool", tool_name = "mcp__gptr__r_eval", input = list(code = "answer <- mean(big_vector) * 2; answer"), tool_use_id = "toolu_1"))
    res <- if (identical(perm$response$behavior, "allow"))
      ask(list(subtype = "mcp_message", server_name = "gptr", message = list(jsonrpc = "2.0", id = 1, method = "tools/call",
               params = list(name = "r_eval", arguments = perm$response$updatedInput))))$response$mcp_response
    txt <- res$result$content[[1]]$text %||% "denied"
    out(list(type = "user", message = list(role = "user", content = list(list(type = "tool_result", tool_use_id = "toolu_1", content = txt))), session_id = sid, parent_tool_use_id = NULL))
    ev(list(type = "content_block_start", index = 0, content_block = list(type = "text", text = "")))
    ev(list(type = "content_block_delta", index = 0, delta = list(type = "text_delta", text = sub("^\\[1\\] ", "", txt))))
    ev(list(type = "content_block_stop", index = 0))
    out(list(type = "result", subtype = "success", is_error = FALSE, result = sub("^\\[1\\] ", "", txt), session_id = sid, num_turns = 2, total_cost_usd = 0))
  }
}
```
Output of `test_fake.R`:
```
  [mcp] <- initialize
init models: haiku
  [approve?] mcp__gptr__r_eval -> allow
  [mcp] <- tools/call r_eval
events: system stream_event/message_start stream_event/content_block_start stream_event/content_block_delta stream_event/content_block_stop user stream_event/content_block_start stream_event/content_block_delta stream_event/content_block_stop result
result: 24 | live$answer: 24 | exit: 0
```

### 5.10 C-locale JSON corruption (encoding pitfall)
```
$ env -u LANG -u LC_ALL -u LC_CTYPE Rscript --vanilla -e '...'
C
unknown 63 61 66 c3 a9                                      # "café" literal: bytes UTF-8, Encoding "unknown"
7b 22 74 22 3a 22 63 61 66 3c 63 33 3e 3c 61 39 3e 22 7d    # toJSON -> {"t":"caf<c3><a9>"}  (corrupted)
bytes (marked UTF-8 input): 7b 22 74 22 3a 22 63 61 66 c3 a9 22 7d  Encoding: UTF-8   # fixed by Encoding(x) <- "UTF-8"
enc2utf8 Encoding: unknown 63 61 66 3c 63 33 3e 3c 61 39 3e                          # enc2utf8 corrupts too in C locale
fromJSON(raw utf8 marked): UTF-8 63 61 66 c3 a9                                      # parsing is fine
```
Verifier re-run (same C locale) adds two cases: `fromJSON()` of an UNMARKED UTF-8 JSON string returns
`caf<c3><a9>` (Encoding "unknown") - parsing is fine only when the input is marked; and a literal
`"café"` in an `Rscript --vanilla` script file came out with Encoding "unknown" and was corrupted by
`toJSON()`. So `\u` escapes do not remove the need for `Encoding(x) <- "UTF-8"`.

### 5.11 Not run
- No request to api.anthropic.com (no key; not allowed by the track). The native provider is verified
  only against docs and mocks.
- Nothing was run on Windows or Linux.
- The httpuv transport was not exercised by the real Claude Code CLI (only by an httr2 JSON-RPC client).
- `interrupt` during a running turn, images in stdin user messages, `--json-schema`, and parallel MCP tool
  calls were not exercised live (would need more model calls).

---------------------------------------------------------------------------------------------------

## 6. CRAN and cross-platform considerations

### 6.1 CRAN
- No network or CLI use in examples/tests on CRAN: wrap real calls in `\dontrun{}` / `skip_on_cran()`;
  use the mock HTTP server (5.3/5.4) and the fake CLI (5.9) for tests, with `skip_if_not_installed()`.
  Mock servers must bind 127.0.0.1 and pick a random free port (`httpuv::randomPort()`). Wait for the
  mock to be listening (poll/retry the connect) instead of a fixed sleep: on re-run, `proto5` with
  `Sys.sleep(1)` after `callr::r_bg()` failed once with "cannot open the connection" (verifier).
- Do not write outside `tempdir()` in tests; the CLI writes session files under the user's home - tests
  must use `--no-session-persistence` and the fake CLI.
- Do not modify `.Random.seed`: the retry jitter in 5.2 uses `runif()` (changes the user's RNG); use a
  time-based jitter (`as.numeric(Sys.time()) %% 1`) or save/restore the seed. Session ids: let the CLI
  generate them (read from `system/init`) or use openssl only when available.
- Package code must be ASCII: write non-ASCII in tests as `\u` escapes and mark `Encoding()` (see 6.4).
- Child processes: `processx` with `cleanup = TRUE, cleanup_tree = TRUE`; also `reg.finalizer()` on the
  session environment and `on.exit()` in `gptr()` so no orphan `claude` survives `R CMD check`.
- The CLI is a `SystemRequirements`-style optional external tool: document it, detect at runtime, never
  install it (no `curl | bash` from R).

### 6.2 Windows (the important part)
- CLI location: native installer `%USERPROFILE%\.local\bin\claude.exe`; WinGet
  (`winget install Anthropic.ClaudeCode`) puts it on PATH; npm creates `%APPDATA%\npm\claude.cmd`.
  **Refuse `.cmd`/`.bat`**: CreateProcess runs them through `cmd.exe`, which re-parses the command line,
  so metacharacters in arguments can execute commands ("BatBadBut", CVE-2024-27980); the official Python
  SDK refuses them (`subprocess_cli.py:415-445`) and prefers `claude.exe` over an earlier-on-PATH shim
  (`:255-283`). If only the shim exists, tell the user to run `irm https://claude.ai/install.ps1 | iex`.
- Put no free text on argv: user prompts via stdin, system prompt via `--system-prompt-file`, MCP config
  via a file path (JSON on argv contains `"`, a cmd.exe metacharacter, and can exceed the 32,767-char
  command-line limit).
- `processx::process$new(..., encoding = "UTF-8", windows_hide_window = TRUE)`: the CLI writes UTF-8; do
  not rely on the native code page (R >= 4.2 on Windows is UTF-8 native, but be explicit).
- Interrupts: `p$interrupt()` sends CTRL+BREAK on Windows (processx docs), which typically terminates the
  child; use the `interrupt` control request to stop a turn and `kill_tree()` only for shutdown.
- Git for Windows is optional for Claude Code (only its Bash tool needs it); with `--tools ""` gptr does
  not need it (setup docs).
- Paths in the MCP config and `--add-dir` should be `normalizePath(winslash = "/")`.
- httpuv fallback: binding 127.0.0.1 only; Windows Defender may still prompt for some apps [UNCERTAIN];
  the sdk transport avoids sockets entirely.
- Credentials (for documentation only; gptr never reads them): `%USERPROFILE%\.claude\.credentials.json`.

### 6.3 macOS/Linux
- CLI at `~/.local/bin/claude` (native), Homebrew cask (`/opt/homebrew/bin` or `/usr/local/bin`),
  `~/.npm-global/bin`, `/usr/local/bin`; Linux packages via apt/dnf/apk. `Sys.which()` may miss
  `~/.local/bin` when R is started from a GUI (RStudio/Positron on macOS do not source shell profiles) -
  hence the explicit candidate list in `cc_find_cli()`.

### 6.4 Encoding rules for gptr
- At load: `if (!isTRUE(l10n_info()[["UTF-8"]])) cli::cli_warn(...)` once.
- Mark every string coming from JSON, processx (`encoding = "UTF-8"`), files read as UTF-8, or the API
  with `Encoding(x) <- "UTF-8"`. jsonlite marks parsed strings as UTF-8 only when its INPUT string is
  marked UTF-8 (or the locale is UTF-8); an unmarked input is corrupted in a C locale (5.10, verifier), so
  mark raw text (processx output, `rawToChar()`, `readLines()`) before `fromJSON()`.
- For user-typed text in non-UTF-8 locales, convert with `iconv(x, "", "UTF-8")` only when the native
  encoding is known to be non-UTF-8 and not "C".
- Build binary request bodies with `req_body_raw()` from a UTF-8-marked JSON string.

### 6.5 Interactive vs non-interactive R
- Knitr/Quarto rendering and `Rscript`: `can_use_tool` must not call `readline()` when
  `!interactive()`; default to deny-with-explanation or the configured mode.
- RStudio/Positron: the console stays responsive only between pump iterations; print streamed text with
  `cat(); flush.console()`.

---------------------------------------------------------------------------------------------------

## 7. Risks, pitfalls, open questions

1. **Policy (highest risk).** The `claude-code` provider sits next to the SDK statement "does not allow
   third party developers to offer claude.ai login or rate limits for their products". gptr offers no
   login and handles no credentials, and the June 2026 support text treats `claude -p` and SDK-based
   third-party apps as drawing from plan limits - but Anthropic can change this "without prior notice"
   (it has changed four times in 2026). Mitigation: opt-in, clear notice, keep the native API provider
   first-class, monitor the support article. Open question for the maintainer: ask Anthropic
   (contact-sales link on the legal page) before CRAN release whether an open-source R package that
   drives the user's own Claude Code install is acceptable.
2. **The control protocol is not formally documented.** Its shapes come from the open-source SDKs, which
   pin `MINIMUM_CLAUDE_CODE_VERSION = "2.0.0"` (`subprocess_cli.py:37`), so it is maintained, but gptr
   should: feature-detect (`initialize` answer, `system/init.capabilities`, `mcp_status`), fall back to
   the httpuv MCP transport, and keep the fake CLI fixture updated.
3. **CLI version drift.** The installed CLI was 2.1.261 while the docs referenced features up to 2.1.283;
   aliases lag models (`opus` -> Opus 5 here). Pin full model IDs; show `claude --version` in
   `cc_doctor()`; warn below a tested minimum.
4. **`ANTHROPIC_API_KEY` in the environment silently switches the CLI from plan to API billing** (auth
   precedence 3 vs 7). Detect and ask.
5. **Auxiliary CLI requests** (session titles, etc.) add a little plan usage; `total_cost_usd` is a
   client-side estimate.
6. **Long R computations as tools.** In-process sdk MCP servers are exempt from the MCP idle timeout
   (env-vars doc), but the overall `MCP_TOOL_TIMEOUT` still applies [VERIFIED by verifier, env-vars.md:
   default 100000000 ms, about 28 h; `MCP_TIMEOUT` (startup) = 30 s]. Leave `MCP_TOOL_TIMEOUT` unset (or
   set it explicitly) and, for the HTTP fallback, always set a per-server `timeout` above 60000 ms - HTTP
   servers otherwise abort any call whose first response byte takes more than 60 s (see 2.15 B).
7. **Tool output size.** MCP text results above `MAX_MCP_OUTPUT_TOKENS` (default 25,000 tokens
   [VERIFIED by verifier, raw mcp.md and env-vars.md]) are spilled to a file by the CLI; gptr should truncate/summarise R output
   itself (D-19) and save full output to a temp file.
8. **Preserved-thinking 400s** on the native provider if any history edit slips in (e.g. re-rendering
   the system prompt with the current object list, deleting old tool results, rebuilding tool schemas).
   Add a CI test that builds two consecutive request bodies and asserts the byte-prefix property
   (as in 5.2), and optionally send `thinking.block_binding.prefix_mismatch_behavior: "error"` under
   the beta in tests.
9. **Refusals** (`stop_reason: "refusal"`, categories `cyber`, `bio`, `reasoning_extraction`, ...):
   bioinformatics users (Seurat etc.) may hit the Opus 5.5 `bio` classifier on dual-use topics; the
   fallback opt-in and a clear message are needed.
10. **Thinking display defaults to omitted**: a gptr console that renders only `text` blocks looks idle
    during long tool loops on 5.x models; use `display = "summarized"` or the `updates` beta.
11. **Empty `end_turn` after tool results** if gptr appends text after `tool_result` blocks; keep images
    and notes inside the results.
12. **The first real call was lost** to a bug in my redaction helper (`x[[i]] <- NULL` deletes list
    elements); fixed version in 5.7. The plain-text capture is therefore covered by calls 2 and 3 only.
13. **Open:** do images sent in stdin `user` messages to Claude Code arrive intact (LIKELY, untested)?
    Does `interrupt` during an MCP tool call cancel the pending `mcp_message` (a `control_cancel_request`
    is expected)? What does `--json-schema` return per turn in stream-json input mode? What is the exact
    `sk-ant-oat` prefix guarantee? These need a few more real calls in a later track.
14. **Open:** Anthropic "Claude apps gateway", Bedrock/Vertex/Foundry via Claude Code
    (`CLAUDE_CODE_USE_*`) work through the same CLI path; not researched here.

---------------------------------------------------------------------------------------------------

## 8. Sources

Official Anthropic documentation (fetched 2026-09-29):
- Models overview - https://platform.claude.com/docs/en/about-claude/models/overview.md
- Pricing - https://platform.claude.com/docs/en/about-claude/pricing.md
- Streaming - https://platform.claude.com/docs/en/build-with-claude/streaming.md
- Errors - https://platform.claude.com/docs/en/api/errors.md
- Rate limits - https://platform.claude.com/docs/en/api/rate-limits.md
- Thinking - https://platform.claude.com/docs/en/build-with-claude/thinking.md
- Handle tool calls - https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls.md
- Vision - https://platform.claude.com/docs/en/build-with-claude/vision.md
- Stop reasons - https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons.md
- Token counting - https://platform.claude.com/docs/en/build-with-claude/token-counting.md
- List models - https://platform.claude.com/docs/en/api/models/list.md
- Messages create reference - https://platform.claude.com/docs/en/api/messages/create.md (summary was lossy; used only for header list)
- Claude Code legal and compliance - https://code.claude.com/docs/en/legal-and-compliance
- Claude Code authentication - https://code.claude.com/docs/en/authentication
- Run Claude Code programmatically (headless) - https://code.claude.com/docs/en/headless
- CLI reference - https://code.claude.com/docs/en/cli-reference
- Agent SDK overview - https://code.claude.com/docs/en/agent-sdk/overview
- Agent SDK custom tools - https://code.claude.com/docs/en/agent-sdk/custom-tools
- Claude Code MCP - https://code.claude.com/docs/en/mcp (the verifier re-fetched the raw `.md`; timeout and output defaults now VERIFIED)
- Claude Code environment variables - https://code.claude.com/docs/en/env-vars
- Claude Code setup - https://code.claude.com/docs/en/setup
- Support: Use the Claude Agent SDK with your Claude plan - https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan

Bundled `claude-api` skill (authoritative cache, 2026-09-25):
`/private/tmp/claude-501/bundled-skills/2.1.284/20a00ddade81c2a9052a5d3ab1925f84/claude-api/`
`SKILL.md`, `curl/examples.md`, `shared/models.md`, `shared/prompt-caching.md`,
`shared/tool-use-concepts.md`, `shared/error-codes.md`, `shared/token-counting.md`,
`shared/anthropic-cli.md`, `shared/model-migration.md` (lines 1600-1674, 1867-2066), `shared/live-sources.md`.

Source code:
- Claude Agent SDK for Python, commit f2204bb956bab02907aaf3cb88eb9dead28eaa35 (2026-09-29):
  https://github.com/anthropics/claude-agent-sdk-python - `src/claude_agent_sdk/_internal/query.py`,
  `_internal/transport/subprocess_cli.py`, `_internal/message_parser.py`, `types.py` (downloaded for reading only).
- Pi (read-only clone, commit 1b347794): `packages/ai/src/auth/oauth/anthropic.ts`,
  `packages/ai/src/api/anthropic-messages.ts`, `packages/coding-agent/src/modes/interactive/interactive-mode.ts:299`,
  `packages/coding-agent/docs/providers.md`, `packages/coding-agent/docs/settings.md:167`.

Press and community (policy timeline):
- Anthropic email posted on HN, "Third-party Claude harnesses will now draw from extra usage" - https://news.ycombinator.com/item?id=47633464
- HN, pause of the Agent SDK change - https://news.ycombinator.com/item?id=49753579
- VentureBeat, 2026-05-13 - https://venturebeat.com/technology/anthropic-reinstates-openclaw-and-third-party-agent-usage-on-claude-subscriptions-with-a-catch
- Pi issue #3670 - https://github.com/earendil-works/pi/issues/3670
- Zed blog - https://zed.dev/blog/anthropic-subscription-changes
- Search-result snippets only (not fetched): https://gigazine.net/gsc_news/en/20260220-anthropic-third-party-block/ ,
  https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/

Local experiments (executed, outputs in section 5 and 3.13/3.14): `claude --help`, `claude -p --help`,
`claude auth --help`, `claude auth status --json` (redacted to 4 fields), flag probes with empty stdin,
`probe_sdk_mcp.R`, `probe_models.R`, `probe_controls.R`, `probe_sysprompt.R`, `probe_claudemd.R`,
`real_calls.R 1|2|3`, `proto1..proto5`, `proto4b_mcp_http.R`, `test_fake.R`, `reuse_accumulator.R`,
C-locale encoding checks.

---------------------------------------------------------------------------------------------------

## Verification log

Adversarial fact-check, 2026-09-29. Environment: macOS, R 4.4.3 (`Rscript --vanilla`, C locale),
httr2 1.2.2, jsonlite 2.0.0, processx 3.8.6, httpuv 1.6.17, callr 3.7.6, openssl 2.3.5, Claude Code CLI
2.1.261. Scratch: `.../scratchpad/work/verify-07/`. No model call, no API call, no package install, no
credential file read. Every R prototype in section 5 was re-run from the code AS PRINTED in this report
(extracted from the markdown, not from the author's scratch copies). Official pages were re-downloaded
as raw `.md` with curl (platform.claude.com, code.claude.com) or via WebFetch.

| # | Claim | Verdict | Source used |
|---|---|---|---|
| 1 | Model IDs, 1M/200K context, 128K/64K output, prices ($10/$50, $4/$20, $2/$10, $1/$5), cache reads 0.025x Fable 5.1, 0.05x Opus 5.5, 5m 1.25x, 1h 2x, legacy prices, `inference_geo` 1.1x, retirement dates, pinned-snapshot quote | confirmed | pricing.md, models/overview.md, skill `shared/models.md` |
| 2 | Thinking table per model (Opus 5.5 / Sonnet 5.5 `between_tools` / Fable 5.1 / Opus 5 / Haiku 4.5), `display` default `omitted` on 5.x, Opus 5.5 default effort `medium`, 2026-08-31 enforcement, `thinking-binding-controls-2026-08-01` + `prefix_mismatch_behavior` values, model-binding rules, Sonnet 5.5 account binding | confirmed | thinking.md, effort.md |
| 3 | SSE flow, cumulative `message_delta.usage`, unknown-event quote, overloaded `error` event, `signature_delta` before stop, omitted-display stream shape, fallback start/stop pair | confirmed | streaming.md |
| 4 | `citations_delta` delta type | confirmed (source is citations.md, not streaming.md; report fixed) | citations.md |
| 5 | Tool name regex `^[a-zA-Z0-9_-]{1,64}$` citing Pi 1215-1218 | corrected: `{1,128}`; Pi lines normalise tool-call IDs, not names | define-tools.md; Pi `anthropic-messages.ts:1215-1218` |
| 6 | tool_result ordering, empty `end_turn` cause, parallel results in one message; "silently trains" quote | confirmed substance; quote not found, replaced by paraphrase | handle-tool-calls.md, handling-stop-reasons.md, parallel-tool-use.md |
| 7 | Caching: 512/1024/4096 minimums, 4 breakpoints, auto caching uses a slot, 20-block lookback, entry readable after first response begins, `max_tokens: 0` pre-warm, "robust combination" | confirmed | prompt-caching.md, skill `shared/prompt-caching.md` |
| 8 | Error table, 32/256/500 MB, `request-id`, SDK 2 retries, `enforced_spend_limit_reached` with no `retry-after`, rate-limit headers RFC 3339, cache reads not in ITPM, Start-tier limits | confirmed; 408 not a documented status and 409 "resolve then retry" noted | errors.md, rate-limits.md |
| 9 | Both `x-api-key` and Bearer -> 401 | corrected to "rejected, status not stated" [UNCERTAIN 401] | skill `shared/anthropic-cli.md` |
| 10 | Beta list "from the models-list enum" incl. `oauth-2025-04-20` | corrected: `oauth-2025-04-20` is not in the enum (skill source); others present | api/models/list.md, skill `anthropic-cli.md` |
| 11 | Vision limits (10 MB, 8000 px, 600/100 images, >20 images -> 2000 px, 32 MB, 28-px patches, 2576/4784 vs 1568/1568) | confirmed | vision.md |
| 12 | count_tokens rejections, Start RPM 5,000; models list `limit` 1-1000 default 20 | confirmed | token-counting.md, api/models/list.md |
| 13 | Code execution "don't combine with the `_20260209` web tools" | corrected: not needed for dynamic filtering; if combined must be `>= _20260120` and is free | code-execution-tool.md, pricing.md |
| 14 | Mid-conversation `role:"system"` rules | confirmed + placement rule added (last entry or followed by assistant) | skill `shared/prompt-caching.md:65-81` |
| 15 | "Hidden-but-accepted flags ... all documented in the CLI reference" | corrected: 5 of the 13 are listed in `--help`; 4 (`--max-thinking-tokens`, `--thinking`, `--thinking-display`, `--task-budget`) are absent from the CLI reference | local `claude --help` (2.1.261, identical to earlier capture); raw cli-reference.md |
| 16 | `--bare` never reads OAuth/keychain; SIGTERM exit 143; stdin 10 MB cap; `--resume` any directory since 2.1.223; `--permission-prompts` host/none; `--effort ... ultracode`; `--permission-mode ... manual` | confirmed | headless.md, cli-reference.md, `--help` |
| 17 | CLI error messages (unknown option, invalid session id, missing input, stream-json needs `--verbose`) and "empty stdin exits 0 silently" | confirmed with qualifier: silent only with isolation flags, else SessionStart `hook_*` lines are emitted | local zero-inference probes (empty stdin) |
| 18 | Control protocol replies (`interrupt` -> `still_queued`, `set_permission_mode`, `set_model` -> null, `get_context_usage` shape, unsupported subtype error) and prompt-size numbers (3.1K / 27 / 18.4K tokens) | confirmed (3148 vs 3144 prompt tokens - date/path variance) | re-ran `probe_controls.R`, `probe_sysprompt.R` with the report's `cc_proto.R` against CLI 2.1.261 (no user message, no inference) |
| 19 | Python SDK at f2204bb: `MINIMUM_CLAUDE_CODE_VERSION = "2.0.0"` (line 37), `.bat/.cmd` refusal, `claude.exe` preference, thinking flags (757-774), `--task-budget` (620), notification ack (`query.py:670-673`), control subtypes, `req_<n>_<hex>` ids, envelope shapes, `permission_prompt_tool_name="stdio"` | confirmed (downloaded files byte-identical to the author's copies) | raw.githubusercontent.com at commit f2204bb |
| 20 | Pi: OAuth constants lines 13-22, expiry 5 min early (131), refresh (197), stealth mode (86-87, version 2.1.280), `sk-ant-oat` (914-916), Bearer + `claude-cli` UA + `x-app: cli` (948-968), betas (1025), identity text (1085-1090), cache placement (1091-1107, 1407-1431, 1497), warning text (`interactive-mode.ts:298-299`), `settings.md:167`, no `stream-json`/agent-SDK use | confirmed | Pi clone at 1b347794 |
| 21 | Legal page quotes, SDK overview "Unless previously approved" note and branding list, support article pause text (updated 2026-06-16), HN email quote, Pi issue #3670 (2026-04-24), VentureBeat 2026-05-13 | confirmed; overview "-p flag" quote completed; legal "Can customers offer Claude Code" section and name rule added [applicability UNCERTAIN]; 2026-01 / 2026-02-19 items marked UNCERTAIN (snippets only) | legal-and-compliance, agent-sdk/overview, support article, HN, GitHub, VentureBeat |
| 22 | Claude Code auth precedence (#1 cloud ... #7 `/login`), `setup-token` one-year / model-requests-only / not read in bare mode, credential locations | confirmed; design note widened to `ANTHROPIC_AUTH_TOKEN`, `apiKeyHelper`, profiles | authentication.md |
| 23 | `MCP_TOOL_TIMEOUT` default (was UNCERTAIN), `MAX_MCP_OUTPUT_TOKENS` 25,000 (was LIKELY), SDK servers exempt from idle timeout, image save path | confirmed (100000000 ms); NEW: HTTP servers' 60-s per-request timer added to 2.15 B / 5.6 / 7.6; image path corrected to the session's `tool-results` dir | env-vars.md, mcp.md |
| 24 | Transcript path "`/` and `.` replaced by `-`" | corrected: every non-alphanumeric char; >200 chars truncated + hash | sessions.md; directory names under `~/.claude/projects` (names only) |
| 25 | `rate_limit_event` fields at top level (2.14) | corrected: nested under `rate_limit_info` | fixture `call2.redacted.ndjson` |
| 26 | Live-call fixture values (cost 0.0178928, 1-h cache write 7448, `modelUsage` 946 input / 32000 max output, call 3 cost 0.0024747 / cache read 6147, init tools/capabilities) | confirmed against stored raw capture; the live calls themselves were not repeated (unverifiable without spending plan usage) | `fixtures/call2.redacted.ndjson`, `call3.redacted.ndjson` |
| 27 | 5.1 SSE decoder + accumulator (as printed) | confirmed: output identical to the report (whole = byte-by-byte = random chunks; overloaded and truncation conditions) | re-run `v_proto1.R` |
| 28 | 5.2 request builder + printed helpers | confirmed: full script output identical; printed helpers run (PNG/JPEG sniffing, strict tool def, `ttl` markers, retry/retryable, `$` partial match) | re-run `proto2_request_builder.R`, `v_proto2b.R` |
| 29 | 5.3 streaming with retries (printed function) against mock | confirmed (529 -> 429 retry-after -> 200, headers, body) | re-run `v_proto3.R` |
| 30 | 5.4 `resp_stream_sse()` handles CRLF/comments/split UTF-8 | confirmed; mock-startup race observed once (note added to 6.1) | re-run `v_proto5.R` |
| 31 | 5.5/5.6 MCP dispatcher + httpuv transport (printed code) and older offline proto | confirmed, identical output | re-run `v56/proto4b_mcp_http.R`, `proto4_mcp_offline.R` |
| 32 | 5.7 driver + 5.9 fake CLI (printed code) | confirmed end-to-end offline; fake CLI needs R >= 4.4.0 for base `%||%` (note added) | re-run `v57/test_fake.R` |
| 33 | 5.8 CLI stream reuses the accumulator | confirmed, identical output (on the redacted fixture) | re-run `v_reuse.R` |
| 34 | 5.10 C-locale encoding pitfall | confirmed; extended: `fromJSON()` of unmarked input and `\u` literals are also corrupted/unmarked under C locale (1.19, 5.10, 6.4 updated) | `v_enc.R`, `v_uesc.R` |
| 35 | httr2 `(>= 1.1.0)` minimum | corrected to `>= 1.1.1` (consider 1.2.2) | installed httr2 NEWS.md |
| 36 | processx `interrupt()` is CTRL+BREAK on Windows; `encoding`, `cleanup_tree`, `windows_hide_window` args | confirmed | processx `?process` |
| 37 | Windows install paths, WinGet id, `install.ps1`, Git for Windows optional | confirmed | setup.md, SDK `subprocess_cli.py:268-296` |

Not independently verifiable here: `claude auth status` fields (not re-run, it prints account data);
whether every `claude setup-token` value contains `sk-ant-oat`; behaviour of the three live calls beyond
the stored capture; Windows behaviour (nothing run on Windows); the `SKILL.md` statements of the
`claude-api` skill (file not on disk; only `shared/*` and `curl/examples.md` were checked).
